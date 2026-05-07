// ==UserScript==
// @name         Stop Nefarious Redirects
// @namespace    http://tampermonkey.net/
// @version      5.2
// @description  Block unauthorized redirects from inside the page's own JS realm (script-tag injection so hooks survive Tampermonkey's sandbox).
// @match        http://*/*
// @match        https://*/*
// @grant        GM_setValue
// @grant        GM_getValue
// @license      MIT
// @run-at       document-start
// ==/UserScript==

(function () {
    'use strict';

    /* eslint-disable no-console */

    const LOG_PREFIX = '[Nefarious Redirect Blocker]';

    // ============================================================
    // Sandbox-side persistent blacklist (GM_* lives here)
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
        try {
            GM_setValue('blacklist', JSON.stringify([...list]));
        } catch (_) { /* ignore quota errors */ }
    }

    // The page-world script can't call GM_*, so it dispatches a CustomEvent
    // when it auto-blacklists a host; we persist on this side.
    document.addEventListener('snr:blacklist-add', (event) => {
        if (event && event.detail && typeof event.detail.host === 'string') {
            addToStoredBlacklist(event.detail.host);
        }
    });

    // ============================================================
    // Page-world script
    //
    // Everything below runs in the page's *main* JavaScript world, not
    // in the Tampermonkey sandbox. That's the whole point of v5.2: the
    // page's own scripts and our hooks share the same Location, the
    // same window.navigation, the same prototypes.
    // ============================================================

    function pageWorldScript(__cfg__) {
        'use strict';

        const LOG = '[Nefarious Redirect Blocker]';
        const NAV_CONSENT_TTL_MS = 2000;

        const manualBlacklist = new Set(__cfg__.manualBlacklist);
        const allowedSites    = new Set(__cfg__.allowedSites);
        const autoBlacklist   = new Set(__cfg__.autoBlacklist);

        let lastKnownGoodUrl = location.href;
        const navConsent = { origin: null, expiresAt: 0 };

        function log(...a)  { console.log(LOG, ...a); }
        function warn(...a) { console.warn(LOG, ...a); }

        // Forward auto-blacklist additions to the sandbox so they're
        // persisted via GM_setValue and survive page reloads.
        function persistBlacklistEntry(host) {
            if (!host || autoBlacklist.has(host)) return;
            autoBlacklist.add(host);
            try {
                document.dispatchEvent(new CustomEvent('snr:blacklist-add', {
                    detail: { host },
                }));
            } catch (_) { /* CustomEvent unavailable in some odd contexts */ }
        }

        // ---------- URL helpers ----------

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

        // ---------- Per-origin navigation consent ----------

        function grantNavConsent(forUrl) {
            const o = getOrigin(forUrl);
            if (!o) return;
            navConsent.origin = o;
            navConsent.expiresAt = Date.now() + NAV_CONSENT_TTL_MS;
        }

        function hasNavConsentFor(url) {
            if (Date.now() > navConsent.expiresAt) return false;
            if (!navConsent.origin) return false;
            return getOrigin(url) === navConsent.origin;
        }

        // ---------- Central policy ----------

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

        // ---------- Anchor / form gesture capture ----------

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

        // ---------- Navigation API (the most comprehensive hook) ----------

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
            log('Navigation API hook installed (page realm).');
        } else {
            warn('Navigation API not available; relying on prototype + event hooks.');
        }

        // ---------- Location.prototype hooks ----------

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

        // ---------- window.open ----------

        const origOpen = window.open;
        window.open = function (url, name, features) {
            if (!url) return origOpen.call(this, url, name, features);
            if (!shouldAllow(url, 'window.open')) return null;
            return origOpen.call(this, url, name, features);
        };

        // ---------- history.{pushState, replaceState} ----------

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

        // ---------- HTMLFormElement.prototype.submit ----------

        try {
            const origSubmit = HTMLFormElement.prototype.submit;
            HTMLFormElement.prototype.submit = function () {
                const action = this.action || '';
                if (action && !shouldAllow(action, 'form.submit()')) return undefined;
                return origSubmit.call(this);
            };
        } catch (e) { warn('HTMLFormElement.submit hook failed:', e); }

        // ---------- <meta http-equiv="refresh"> ----------

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

        log('v5.2 hooks installed in page world.');
    }

    // ============================================================
    // Inject the page-world script
    //
    // Inline <script> with textContent runs synchronously when appended,
    // so the hooks are in place before any page script can navigate.
    // The element is removed immediately after; the closure stays alive.
    // ============================================================

    const config = {
        manualBlacklist: [
            'alexatracker.com',
            'getrunkhomuto.info',
        ],
        allowedSites: [
            '500px.com', 'accuweather.com', 'adobe.com', 'alibaba.com', 'amazon.com',
            'apple.com', 'bbc.com', 'bing.com', 'cnn.com', 'craigslist.org',
            'dailymail.co.uk', 'ebay.com', 'facebook.com', 'github.com', 'google.com',
            'instagram.com', 'linkedin.com', 'microsoft.com', 'netflix.com', 'reddit.com',
            'twitter.com', 'wikipedia.org', 'youtube.com',
        ],
        autoBlacklist: getStoredBlacklist(),
    };

    try {
        const tag = document.createElement('script');
        tag.textContent = `(${pageWorldScript.toString()})(${JSON.stringify(config)});`;
        const parent = document.head || document.documentElement || document;
        parent.insertBefore(tag, parent.firstChild || null);
        tag.remove();
        console.log(LOG_PREFIX, 'v5.2 page-world hooks injected.');
    } catch (e) {
        // Strict CSP page-script-src can block inline scripts. Log but do not
        // throw -- the legacy sandbox-side hooks are no longer present in 5.2,
        // so on these pages we fail open rather than fail closed.
        console.error(LOG_PREFIX, 'Failed to inject page-world script (likely CSP):', e);
    }
})();
