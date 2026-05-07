// ==UserScript==
// @name         Stop Nefarious Redirects
// @namespace    http://tampermonkey.net/
// @version      5.3
// @description  Block unauthorized redirects with layered defense: GM_addElement-injected page-world hooks (CSP-proof) AND always-on sandbox-side hooks.
// @match        http://*/*
// @match        https://*/*
// @grant        GM_setValue
// @grant        GM_getValue
// @grant        GM_addElement
// @grant        unsafeWindow
// @license      MIT
// @run-at       document-start
// ==/UserScript==

(function () {
    'use strict';

    /* eslint-disable no-console */

    const LOG_PREFIX = '[Nefarious Redirect Blocker]';
    const NAV_CONSENT_TTL_MS = 2000;

    // ============================================================
    // Persistent blacklist (sandbox-side; only sandbox can call GM_*)
    // ============================================================

    function getStoredBlacklist() {
        try {
            const raw = GM_getValue('blacklist', '[]');
            const parsed = typeof raw === 'string' ? JSON.parse(raw) : raw;
            return Array.isArray(parsed) ? parsed : [];
        } catch (_) {
            return [];
        }
    }

    function addToStoredBlacklist(host) {
        if (!host) return;
        const list = new Set(getStoredBlacklist());
        if (list.has(host)) return;
        list.add(host);
        try { GM_setValue('blacklist', JSON.stringify([...list])); } catch (_) { /* ignore */ }
    }

    // The page-world script can't reach GM_*, so it dispatches a CustomEvent
    // when it auto-blacklists a host; we persist on this side.
    document.addEventListener('snr:blacklist-add', (event) => {
        if (event && event.detail && typeof event.detail.host === 'string') {
            addToStoredBlacklist(event.detail.host);
        }
    });

    // ============================================================
    // Shared configuration
    // ============================================================

    const config = {
        manualBlacklist: [
            'alexatracker.com',
            'getrunkhomuto.info',
            'click.aliexpress.com', // catches s.click.aliexpress.com etc.
        ],
        allowedSites: [
            '500px.com', 'accuweather.com', 'adobe.com', 'alibaba.com', 'amazon.com',
            'apple.com', 'bbc.com', 'bing.com', 'cnn.com', 'craigslist.org',
            'dailymail.co.uk', 'ebay.com', 'facebook.com', 'github.com', 'google.com',
            'instagram.com', 'linkedin.com', 'microsoft.com', 'netflix.com', 'reddit.com',
            'twitter.com', 'wikipedia.org', 'youtube.com',
        ],
        autoBlacklist: getStoredBlacklist(),
        navConsentTtlMs: NAV_CONSENT_TTL_MS,
    };

    // ============================================================
    // Page-world hook function (runs in the page's main JS realm)
    //
    // Hits everything that lives in a JS realm: Location.prototype,
    // history methods, window.open, window.navigation, form.submit,
    // and DOM-level click/submit/meta-refresh.
    // ============================================================

    function pageWorldHooks(__cfg__) {
        'use strict';

        const LOG = '[Nefarious Redirect Blocker]';
        const NAV_TTL = __cfg__.navConsentTtlMs;
        const manualBlacklist = new Set(__cfg__.manualBlacklist);
        const allowedSites    = new Set(__cfg__.allowedSites);
        const autoBlacklist   = new Set(__cfg__.autoBlacklist);

        let lastKnownGoodUrl = location.href;
        const navConsent = { origin: null, expiresAt: 0 };

        function log(...a)  { console.log(LOG + ' [page]', ...a); }
        function warn(...a) { console.warn(LOG + ' [page]', ...a); }

        function persistBlacklistEntry(host) {
            if (!host || autoBlacklist.has(host)) return;
            autoBlacklist.add(host);
            try {
                document.dispatchEvent(new CustomEvent('snr:blacklist-add', {
                    detail: { host },
                }));
            } catch (_) { /* CustomEvent unavailable */ }
        }

        function urlOrNull(input) {
            try { return new URL(input, location.href); } catch (_) { return null; }
        }
        function getHostname(input) { const u = urlOrNull(input); return u ? u.hostname : null; }
        function getOrigin(input)   { const u = urlOrNull(input); return u ? u.origin   : null; }

        function hostnameMatchesSet(hostname, set) {
            if (!hostname) return false;
            for (const site of set) {
                if (hostname === site || hostname.endsWith('.' + site)) return true;
            }
            return false;
        }

        function isInAllowlist(url) { return hostnameMatchesSet(getHostname(url), allowedSites); }
        function isInBlacklist(url) {
            const h = getHostname(url);
            if (!h) return false;
            return hostnameMatchesSet(h, manualBlacklist) ||
                   hostnameMatchesSet(h, autoBlacklist);
        }
        function isSameOrigin(url) {
            const o = getOrigin(url);
            return o == null || o === location.origin;
        }

        function grantNavConsent(forUrl) {
            const o = getOrigin(forUrl);
            if (!o) return;
            navConsent.origin = o;
            navConsent.expiresAt = Date.now() + NAV_TTL;
        }
        function hasNavConsentFor(url) {
            if (Date.now() > navConsent.expiresAt) return false;
            if (!navConsent.origin) return false;
            return getOrigin(url) === navConsent.origin;
        }

        function shouldAllow(url, source) {
            if (!url) return true;
            const target = urlOrNull(url);
            if (!target) return true;

            if (target.protocol === 'javascript:' || target.protocol === 'data:') {
                warn(`Blocked ${target.protocol} [${source}]: ${url}`);
                return false;
            }
            if (isInBlacklist(url)) {
                if (target.hostname) persistBlacklistEntry(target.hostname);
                warn(`Blocked (blacklist) [${source}]: ${url}`);
                return false;
            }
            if (isSameOrigin(url))  return true;
            if (isInAllowlist(url)) return true;
            if (hasNavConsentFor(url)) {
                log(`Allowed (consent) [${source}]: ${url}`);
                return true;
            }
            if (target.hostname) persistBlacklistEntry(target.hostname);
            warn(`Blocked (no consent) [${source}]: ${url}`);
            return false;
        }

        document.addEventListener('click', (event) => {
            const t = event.target;
            const a = t && t.closest && t.closest('a[href]');
            if (!a) return;
            const href = a.href;
            if (!href || href.startsWith('javascript:') || href.startsWith('mailto:')) return;
            if (!shouldAllow(href, 'anchor click')) {
                event.preventDefault();
                event.stopPropagation();
                return;
            }
            grantNavConsent(href);
        }, true);

        document.addEventListener('submit', (event) => {
            const form = event.target;
            const action = form && form.action;
            if (action && !shouldAllow(action, 'form submit')) {
                event.preventDefault();
                event.stopPropagation();
                return;
            }
            if (action) grantNavConsent(action);
        }, true);

        if (window.navigation && typeof window.navigation.addEventListener === 'function') {
            window.navigation.addEventListener('navigate', (event) => {
                try {
                    if (event.destination && event.destination.sameDocument) return;
                    const url = event.destination ? event.destination.url : null;
                    if (!shouldAllow(url, `navigation.${event.navigationType || 'navigate'}`)) {
                        event.preventDefault();
                    }
                } catch (e) {
                    warn('navigation handler threw:', e);
                }
            });
            log('Navigation API hook installed.');
        } else {
            warn('Navigation API not available; relying on prototype + event hooks.');
        }

        function wrapLocationMethod(method) {
            try {
                const orig = Location.prototype[method];
                if (typeof orig !== 'function') return;
                Location.prototype[method] = function (url) {
                    if (!shouldAllow(url, `location.${method}`)) return undefined;
                    return orig.call(this, url);
                };
            } catch (e) { warn(`Location.${method} hook failed:`, e); }
        }
        wrapLocationMethod('assign');
        wrapLocationMethod('replace');

        try {
            const desc = Object.getOwnPropertyDescriptor(Location.prototype, 'href');
            if (desc && desc.set && desc.configurable) {
                const origGet = desc.get;
                const origSet = desc.set;
                Object.defineProperty(Location.prototype, 'href', {
                    configurable: true,
                    enumerable: desc.enumerable,
                    get() { return origGet.call(this); },
                    set(v) {
                        if (!shouldAllow(v, 'location.href=')) return;
                        return origSet.call(this, v);
                    },
                });
            }
        } catch (e) { warn('Location.href setter override failed:', e); }

        const origOpen = window.open;
        window.open = function (url, name, features) {
            if (!url) return origOpen.call(this, url, name, features);
            if (!shouldAllow(url, 'window.open')) return null;
            return origOpen.call(this, url, name, features);
        };

        function wrapHistoryMethod(method) {
            try {
                const orig = history[method];
                history[method] = function (data, title, url) {
                    if (url && !shouldAllow(url, `history.${method}`)) return undefined;
                    return orig.apply(this, arguments);
                };
            } catch (e) { warn(`history.${method} hook failed:`, e); }
        }
        wrapHistoryMethod('pushState');
        wrapHistoryMethod('replaceState');

        window.addEventListener('popstate', () => {
            const here = location.href;
            if (shouldAllow(here, 'popstate')) {
                lastKnownGoodUrl = here;
                return;
            }
            if (lastKnownGoodUrl && lastKnownGoodUrl !== here) {
                try { history.pushState(null, '', lastKnownGoodUrl); } catch (_) { /* ignore */ }
                location.replace(lastKnownGoodUrl);
            }
        });

        try {
            const origSubmit = HTMLFormElement.prototype.submit;
            HTMLFormElement.prototype.submit = function () {
                const action = this.action || '';
                if (action && !shouldAllow(action, 'form.submit()')) return undefined;
                return origSubmit.call(this);
            };
        } catch (e) { warn('HTMLFormElement.submit hook failed:', e); }

        const META_RE = /url\s*=\s*['"]?([^'">\s]+)/i;
        function checkMetaRefresh(node) {
            if (!node || node.tagName !== 'META') return;
            const eq = (node.getAttribute('http-equiv') || '').toLowerCase();
            if (eq !== 'refresh') return;
            const content = node.getAttribute('content') || '';
            const m = content.match(META_RE);
            if (!m) return;
            if (!shouldAllow(m[1], 'meta refresh')) {
                node.remove();
                warn('Removed meta refresh:', m[1]);
            }
        }
        function scanMetas(root) {
            if (!root || !root.querySelectorAll) return;
            root.querySelectorAll('meta[http-equiv="refresh" i]').forEach(checkMetaRefresh);
        }
        scanMetas(document);
        new MutationObserver((mutations) => {
            for (const m of mutations) {
                for (const n of m.addedNodes) {
                    if (n.nodeType !== 1) continue;
                    checkMetaRefresh(n);
                    scanMetas(n);
                }
                if (m.type === 'attributes' && m.target) checkMetaRefresh(m.target);
            }
        }).observe(document.documentElement || document, {
            childList: true,
            subtree: true,
            attributes: true,
            attributeFilter: ['http-equiv', 'content'],
        });

        log('v5.3 page-world hooks installed.');
    }

    // ============================================================
    // Inject page-world hooks
    //
    // Order of preference:
    //   1. GM_addElement('script', ...)  -- bypasses page CSP
    //   2. document.createElement('script') + textContent  -- blocked by strict CSP
    // Either way, the inline script runs synchronously when the element
    // is in the DOM, so hooks land before any in-document <script> the
    // parser will encounter.
    // ============================================================

    function buildPageWorldCode() {
        return `(${pageWorldHooks.toString()})(${JSON.stringify(config)});`;
    }

    let pageWorldOk = false;
    if (typeof GM_addElement === 'function') {
        try {
            GM_addElement('script', { textContent: buildPageWorldCode() });
            pageWorldOk = true;
            console.log(LOG_PREFIX, 'Page-world hooks injected via GM_addElement (CSP-proof).');
        } catch (e) {
            console.warn(LOG_PREFIX, 'GM_addElement injection failed:', e);
        }
    }
    if (!pageWorldOk) {
        try {
            const tag = document.createElement('script');
            tag.textContent = buildPageWorldCode();
            const parent = document.head || document.documentElement || document;
            parent.insertBefore(tag, parent.firstChild || null);
            tag.remove();
            pageWorldOk = true;
            console.log(LOG_PREFIX, 'Page-world hooks injected via inline <script>.');
        } catch (e) {
            console.warn(LOG_PREFIX, 'Inline <script> injection blocked (likely CSP):', e);
        }
    }
    if (!pageWorldOk) {
        console.warn(LOG_PREFIX, 'Page-world injection unavailable; running with sandbox hooks only.');
    }

    // ============================================================
    // Sandbox-side fallback hooks
    //
    // ALWAYS installed, regardless of whether page-world injection
    // succeeded. They use document-level events (which work via the
    // shared DOM, no realm crossing required) and unsafeWindow for
    // the rest. Even on a strict-CSP page where the injection above
    // failed silently, this layer still:
    //   - cancels anchor clicks to blocked destinations,
    //   - cancels form submissions to blocked actions,
    //   - removes hostile <meta http-equiv="refresh"> nodes,
    //   - blocks window.open() to blocked URLs,
    //   - blocks Navigation API navigations.
    // ============================================================

    sandboxHooks(config);

    function sandboxHooks(cfg) {
        const NAV_TTL = cfg.navConsentTtlMs;
        const manualBlacklist = new Set(cfg.manualBlacklist);
        const allowedSites    = new Set(cfg.allowedSites);
        const autoBlacklist   = new Set(cfg.autoBlacklist);
        const navConsent      = { origin: null, expiresAt: 0 };

        function log(...a)  { console.log(LOG_PREFIX, '[sandbox]', ...a); }
        function warn(...a) { console.warn(LOG_PREFIX, '[sandbox]', ...a); }

        function urlOrNull(input) {
            try { return new URL(input, location.href); } catch (_) { return null; }
        }
        function getOrigin(input)   { const u = urlOrNull(input); return u ? u.origin   : null; }
        function getHostname(input) { const u = urlOrNull(input); return u ? u.hostname : null; }
        function hostnameMatchesSet(hostname, set) {
            if (!hostname) return false;
            for (const site of set) {
                if (hostname === site || hostname.endsWith('.' + site)) return true;
            }
            return false;
        }

        function shouldAllow(url, source) {
            if (!url) return true;
            const target = urlOrNull(url);
            if (!target) return true;

            if (target.protocol === 'javascript:' || target.protocol === 'data:') {
                warn(`Blocked ${target.protocol} [${source}]: ${url}`);
                return false;
            }
            const h = target.hostname;
            if (h && (hostnameMatchesSet(h, manualBlacklist) || hostnameMatchesSet(h, autoBlacklist))) {
                warn(`Blocked (blacklist) [${source}]: ${url}`);
                addToStoredBlacklist(h);
                return false;
            }
            if (target.origin === location.origin) return true;
            if (h && hostnameMatchesSet(h, allowedSites)) return true;
            if (Date.now() < navConsent.expiresAt && navConsent.origin === target.origin) {
                log(`Allowed (consent) [${source}]: ${url}`);
                return true;
            }
            warn(`Blocked (no consent) [${source}]: ${url}`);
            if (h) {
                autoBlacklist.add(h);
                addToStoredBlacklist(h);
            }
            return false;
        }

        function grantNavConsent(forUrl) {
            const o = getOrigin(forUrl);
            if (!o) return;
            navConsent.origin = o;
            navConsent.expiresAt = Date.now() + NAV_TTL;
        }

        document.addEventListener('click', (event) => {
            const t = event.target;
            const a = t && t.closest && t.closest('a[href]');
            if (!a) return;
            const href = a.href;
            if (!href || href.startsWith('javascript:') || href.startsWith('mailto:')) return;
            if (!shouldAllow(href, 'anchor click')) {
                event.preventDefault();
                event.stopImmediatePropagation();
                return;
            }
            grantNavConsent(href);
        }, true);

        document.addEventListener('submit', (event) => {
            const f = event.target;
            const action = f && f.action;
            if (action && !shouldAllow(action, 'form submit')) {
                event.preventDefault();
                event.stopImmediatePropagation();
                return;
            }
            if (action) grantNavConsent(action);
        }, true);

        const META_RE = /url\s*=\s*['"]?([^'">\s]+)/i;
        function checkMetaRefresh(node) {
            if (!node || node.tagName !== 'META') return;
            const eq = (node.getAttribute('http-equiv') || '').toLowerCase();
            if (eq !== 'refresh') return;
            const content = node.getAttribute('content') || '';
            const m = content.match(META_RE);
            if (!m) return;
            if (!shouldAllow(m[1], 'meta refresh')) {
                node.remove();
                warn('Removed meta refresh:', m[1]);
            }
        }
        function scanMetas(root) {
            if (!root || !root.querySelectorAll) return;
            root.querySelectorAll('meta[http-equiv="refresh" i]').forEach(checkMetaRefresh);
        }
        scanMetas(document);
        new MutationObserver((mutations) => {
            for (const m of mutations) {
                for (const n of m.addedNodes) {
                    if (n.nodeType !== 1) continue;
                    checkMetaRefresh(n);
                    scanMetas(n);
                }
                if (m.type === 'attributes' && m.target) checkMetaRefresh(m.target);
            }
        }).observe(document.documentElement || document, {
            childList: true,
            subtree: true,
            attributes: true,
            attributeFilter: ['http-equiv', 'content'],
        });

        // Best-effort: the page realm may or may not honor these, depending
        // on Tampermonkey's wrapping. Page-world hooks above are the real
        // line of defense for these; this is belt-and-suspenders.
        try {
            const target = (typeof unsafeWindow !== 'undefined') ? unsafeWindow : window;
            const origOpen = target.open;
            target.open = function (url, name, features) {
                if (!url) return origOpen.call(this, url, name, features);
                if (!shouldAllow(url, 'window.open')) return null;
                return origOpen.call(this, url, name, features);
            };
        } catch (e) { warn('window.open override failed:', e); }

        try {
            const target = (typeof unsafeWindow !== 'undefined') ? unsafeWindow : window;
            if (target.navigation && typeof target.navigation.addEventListener === 'function') {
                target.navigation.addEventListener('navigate', (event) => {
                    try {
                        if (event.destination && event.destination.sameDocument) return;
                        const url = event.destination ? event.destination.url : null;
                        if (!shouldAllow(url, `navigation.${event.navigationType || 'navigate'}`)) {
                            event.preventDefault();
                        }
                    } catch (e) { warn('Navigation handler threw:', e); }
                });
            }
        } catch (e) { warn('Navigation API hook failed:', e); }

        log('v5.3 sandbox hooks installed.');
    }

    console.log(LOG_PREFIX, 'v5.3 initialized. Page-world injection:',
                pageWorldOk ? 'success' : 'failed (sandbox hooks only)');
})();
