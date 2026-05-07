// ==UserScript==
// @name         Stop Nefarious Redirects
// @namespace    http://tampermonkey.net/
// @version      5.1
// @description  Block unauthorized redirects and prevent history manipulation
// @match        http://*/*
// @match        https://*/*
// @grant        GM_setValue
// @grant        GM_getValue
// @grant        unsafeWindow
// @license      MIT
// @run-at       document-start
// ==/UserScript==

(function () {
    'use strict';

    /* eslint-disable no-console */

    // Hook the page's actual realm where possible -- on Firefox the
    // userscript runs in a sandbox whose Location.prototype is NOT the
    // page's; on Chrome the two are identical.
    const PAGE = (typeof unsafeWindow !== 'undefined') ? unsafeWindow : window;

    // ============================================================
    // Configuration
    // ============================================================

    // Always-blocked hostnames (and their subdomains).
    const manualBlacklist = new Set([
        'alexatracker.com',
        'getrunkhomuto.info',
    ]);

    // Cross-origin navigations to these hostnames (and their subdomains)
    // are always allowed.
    const allowedSites = new Set([
        '500px.com', 'accuweather.com', 'adobe.com', 'alibaba.com', 'amazon.com',
        'apple.com', 'bbc.com', 'bing.com', 'cnn.com', 'craigslist.org',
        'dailymail.co.uk', 'ebay.com', 'facebook.com', 'github.com', 'google.com',
        'instagram.com', 'linkedin.com', 'microsoft.com', 'netflix.com', 'reddit.com',
        'twitter.com', 'wikipedia.org', 'youtube.com',
    ]);

    // After a user clicks an anchor (or submits a form), we grant a
    // navigation consent for that *specific origin* for this many ms.
    // The previous "any user gesture allows any cross-origin nav for X ms"
    // was the leak that let alexatracker through.
    const NAV_CONSENT_TTL_MS = 2000;

    // ============================================================
    // State
    // ============================================================

    const LOG_PREFIX = '[Nefarious Redirect Blocker]';
    let lastKnownGoodUrl = window.location.href;
    const navConsent = { origin: null, expiresAt: 0 };

    function log(...args)  { console.log(LOG_PREFIX, ...args); }
    function warn(...args) { console.warn(LOG_PREFIX, ...args); }

    // ============================================================
    // Persistent automated blacklist (sites we caught misbehaving)
    // ============================================================

    function getAutomatedBlacklist() {
        try {
            const stored = GM_getValue('blacklist', '[]');
            const parsed = typeof stored === 'string' ? JSON.parse(stored) : stored;
            return new Set(Array.isArray(parsed) ? parsed : []);
        } catch (e) {
            console.error(LOG_PREFIX, 'Error parsing blacklist:', e);
            return new Set();
        }
    }

    function addToAutomatedBlacklist(hostname) {
        if (!hostname) return;
        const blacklist = getAutomatedBlacklist();
        if (!blacklist.has(hostname)) {
            blacklist.add(hostname);
            GM_setValue('blacklist', JSON.stringify([...blacklist]));
            log('Added to automated blacklist:', hostname);
        }
    }

    // ============================================================
    // URL helpers
    // ============================================================

    function urlOrNull(input) {
        try {
            return new URL(input, location.href);
        } catch (_) {
            return null;
        }
    }

    function getHostname(input) {
        const u = urlOrNull(input);
        return u ? u.hostname : null;
    }

    function getOrigin(input) {
        const u = urlOrNull(input);
        return u ? u.origin : null;
    }

    function hostnameMatchesSet(hostname, set) {
        if (!hostname) return false;
        for (const site of set) {
            if (hostname === site || hostname.endsWith('.' + site)) return true;
        }
        return false;
    }

    function isInAllowlist(url) {
        return hostnameMatchesSet(getHostname(url), allowedSites);
    }

    function isInBlacklist(url) {
        const hostname = getHostname(url);
        if (!hostname) return false;
        return hostnameMatchesSet(hostname, manualBlacklist) ||
               hostnameMatchesSet(hostname, getAutomatedBlacklist());
    }

    function isSameOrigin(url) {
        const origin = getOrigin(url);
        return origin == null || origin === location.origin;
    }

    // ============================================================
    // Per-origin navigation consent
    // ============================================================

    function grantNavConsent(forUrl) {
        const origin = getOrigin(forUrl);
        if (!origin) return;
        navConsent.origin = origin;
        navConsent.expiresAt = Date.now() + NAV_CONSENT_TTL_MS;
    }

    function hasNavConsentFor(url) {
        if (Date.now() > navConsent.expiresAt) return false;
        if (!navConsent.origin) return false;
        return getOrigin(url) === navConsent.origin;
    }

    // ============================================================
    // Central policy decision
    // ============================================================

    function shouldAllowNavigation(url, source) {
        if (!url) return true; // No URL = same-page reload or fragment.
        const target = urlOrNull(url);
        if (!target) return true; // Junk URLs - let the browser deal.

        // Block javascript: / data: regardless of source unless it's the
        // current page already running them.
        if (target.protocol === 'javascript:' || target.protocol === 'data:') {
            warn(`Blocked ${target.protocol} [${source}]: ${url}`);
            return false;
        }

        if (isInBlacklist(url)) {
            const h = target.hostname;
            if (h) addToAutomatedBlacklist(h);
            warn(`Blocked (blacklist) [${source}]: ${url}`);
            return false;
        }

        if (isSameOrigin(url)) return true;

        if (isInAllowlist(url)) return true;

        if (hasNavConsentFor(url)) {
            log(`Allowed (anchor/form consent) [${source}]: ${url}`);
            return true;
        }

        // Cross-origin without explicit per-origin consent = nefarious.
        // The previous "recent gesture = allow everything" rule was what
        // let alexatracker laundering attempts through.
        if (target.hostname) addToAutomatedBlacklist(target.hostname);
        warn(`Blocked (no per-origin consent) [${source}]: ${url}`);
        return false;
    }

    // ============================================================
    // Anchor / form gesture capture
    // ============================================================
    //
    // A click on <a href="https://example.com/x"> consents to navigations
    // whose destination is the *example.com origin*. A click on a button
    // grants no navigation consent at all -- that's the policy change.

    document.addEventListener('click', (event) => {
        const target = event.target;
        const anchor = target && target.closest && target.closest('a[href]');
        if (!anchor) return;

        const href = anchor.href;
        if (!href || href.startsWith('javascript:') || href.startsWith('mailto:')) return;

        if (!shouldAllowNavigation(href, 'anchor click')) {
            event.preventDefault();
            event.stopPropagation();
            return;
        }
        grantNavConsent(href);
    }, true);

    document.addEventListener('submit', (event) => {
        const form = event.target;
        const action = form && form.action;
        if (action && !shouldAllowNavigation(action, 'form submit (event)')) {
            event.preventDefault();
            event.stopPropagation();
            return;
        }
        if (action) grantNavConsent(action);
    }, true);

    // ============================================================
    // Navigation API hook -- the silver bullet on modern browsers
    // ============================================================
    //
    // The 'navigate' event fires for EVERY navigation initiated from this
    // window, including programmatic location.href = '...', location
    // .assign/replace, anchor clicks, form submits, history.* calls, and
    // back/forward. event.preventDefault() cancels it cleanly. Available
    // in Chrome >= 102, Edge >= 102, Firefox >= 137, Safari >= 18.4.

    const nav = (typeof PAGE !== 'undefined' && PAGE.navigation) || window.navigation;
    if (nav && typeof nav.addEventListener === 'function') {
        nav.addEventListener('navigate', (event) => {
            try {
                if (event.destination.sameDocument) return;
                const url = event.destination.url;
                if (!shouldAllowNavigation(url, `navigation.${event.navigationType || 'navigate'}`)) {
                    event.preventDefault();
                }
            } catch (e) {
                warn('Navigation event handler threw:', e);
            }
        });
        log('Navigation API hook installed (modern browser).');
    } else {
        warn('Navigation API not available; relying on legacy hooks.');
    }

    // ============================================================
    // Override Location methods/setter (best-effort fallback for
    // browsers without the Navigation API, or where it misses)
    // ============================================================

    function tryWrapLocationMethod(LocationProto, method) {
        try {
            const original = LocationProto[method];
            if (typeof original !== 'function') return false;
            LocationProto[method] = function (url) {
                if (!shouldAllowNavigation(url, `location.${method}`)) return undefined;
                return original.call(this, url);
            };
            return true;
        } catch (e) {
            warn(`Could not override Location.prototype.${method}:`, e);
            return false;
        }
    }

    const LocationProto = (PAGE && PAGE.Location && PAGE.Location.prototype) || Location.prototype;
    tryWrapLocationMethod(LocationProto, 'assign');
    tryWrapLocationMethod(LocationProto, 'replace');

    try {
        const desc = Object.getOwnPropertyDescriptor(LocationProto, 'href');
        if (desc && desc.set && desc.configurable) {
            const originalSetter = desc.set;
            const originalGetter = desc.get;
            Object.defineProperty(LocationProto, 'href', {
                configurable: true,
                enumerable: desc.enumerable,
                get() { return originalGetter.call(this); },
                set(value) {
                    if (!shouldAllowNavigation(value, 'location.href=')) return;
                    return originalSetter.call(this, value);
                },
            });
        }
    } catch (e) {
        warn('Could not override Location.prototype.href setter:', e);
    }

    // ============================================================
    // window.open
    // ============================================================

    const originalWindowOpen = PAGE.open || window.open;
    const openWrapper = function (url, name, features) {
        if (!url) return originalWindowOpen.call(this, url, name, features);
        if (!shouldAllowNavigation(url, 'window.open')) return null;
        return originalWindowOpen.call(this, url, name, features);
    };
    try { PAGE.open = openWrapper; } catch (_) { /* ignore */ }
    try { window.open = openWrapper; } catch (_) { /* ignore */ }

    // ============================================================
    // history.pushState / replaceState
    // ============================================================

    function wrapHistoryMethod(historyObj, method) {
        try {
            const original = historyObj[method];
            historyObj[method] = function (data, title, url) {
                if (url && !shouldAllowNavigation(url, `history.${method}`)) {
                    return undefined;
                }
                return original.apply(this, arguments);
            };
        } catch (e) {
            warn(`Could not wrap history.${method}:`, e);
        }
    }

    if (PAGE && PAGE.history) {
        wrapHistoryMethod(PAGE.history, 'pushState');
        wrapHistoryMethod(PAGE.history, 'replaceState');
    } else {
        wrapHistoryMethod(history, 'pushState');
        wrapHistoryMethod(history, 'replaceState');
    }

    // ============================================================
    // popstate revert (last-resort safety net)
    // ============================================================

    window.addEventListener('popstate', () => {
        const here = window.location.href;
        if (shouldAllowNavigation(here, 'popstate')) {
            lastKnownGoodUrl = here;
            return;
        }
        if (lastKnownGoodUrl && lastKnownGoodUrl !== here) {
            try { history.pushState(null, '', lastKnownGoodUrl); } catch (_) { /* ignore */ }
            window.location.replace(lastKnownGoodUrl);
        }
    });

    // ============================================================
    // HTMLFormElement.prototype.submit (programmatic submission)
    // ============================================================

    try {
        const FormProto = (PAGE && PAGE.HTMLFormElement && PAGE.HTMLFormElement.prototype) ||
                          HTMLFormElement.prototype;
        const originalSubmit = FormProto.submit;
        FormProto.submit = function () {
            const action = this.action || '';
            if (action && !shouldAllowNavigation(action, 'form.submit()')) return undefined;
            return originalSubmit.call(this);
        };
    } catch (e) {
        warn('Could not override HTMLFormElement.prototype.submit:', e);
    }

    // ============================================================
    // <meta http-equiv="refresh"> interceptor
    // ============================================================

    const META_REFRESH_URL_RE = /url\s*=\s*['"]?([^'">\s]+)/i;

    function inspectMetaRefresh(node) {
        if (!node || node.tagName !== 'META') return;
        const httpEquiv = (node.getAttribute('http-equiv') || '').toLowerCase();
        if (httpEquiv !== 'refresh') return;
        const content = node.getAttribute('content') || '';
        const match = content.match(META_REFRESH_URL_RE);
        if (!match) return; // Refresh without URL = page reload only; allow.
        const url = match[1];
        if (!shouldAllowNavigation(url, 'meta refresh')) {
            node.remove();
            warn('Removed meta refresh to blocked URL:', url);
        }
    }

    function scanForMetaRefresh(root) {
        if (!root || !root.querySelectorAll) return;
        root.querySelectorAll('meta[http-equiv="refresh" i]').forEach(inspectMetaRefresh);
    }

    scanForMetaRefresh(document);

    const observer = new MutationObserver((mutations) => {
        for (const mutation of mutations) {
            for (const node of mutation.addedNodes) {
                if (node.nodeType !== Node.ELEMENT_NODE) continue;
                inspectMetaRefresh(node);
                scanForMetaRefresh(node);
            }
            if (mutation.type === 'attributes' && mutation.target) {
                inspectMetaRefresh(mutation.target);
            }
        }
    });

    observer.observe(document.documentElement || document, {
        childList: true,
        subtree: true,
        attributes: true,
        attributeFilter: ['http-equiv', 'content'],
    });

    // ============================================================
    // Done
    // ============================================================

    log('Initialized v5.1. Hooks: Navigation API (if available),',
        'window.open, location.{assign,replace,href=},',
        'history.{pushState,replaceState,popstate}, form.submit(),',
        'anchor click, form submit, <meta http-equiv="refresh">. Per-origin',
        'consent model in effect.');
})();
