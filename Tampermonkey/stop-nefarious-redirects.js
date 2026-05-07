// ==UserScript==
// @name         Stop Nefarious Redirects
// @namespace    http://tampermonkey.net/
// @version      5.0
// @description  Block unauthorized redirects and prevent history manipulation
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

    // ============================================================
    // Configuration
    // ============================================================

    // Always-blocked hostnames (and their subdomains).
    const manualBlacklist = new Set([
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

    // Cross-origin navigations attempted within this many ms of a real user
    // gesture (click / keydown / submit / touchstart) are allowed even if
    // they aren't on the allowlist. Lower = stricter.
    const USER_INTERACTION_WINDOW_MS = 1500;

    // ============================================================
    // State
    // ============================================================

    const LOG_PREFIX = '[Nefarious Redirect Blocker]';
    let lastKnownGoodUrl = window.location.href;
    let lastInteractionAt = 0;

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
    // Hostname matching helpers
    // ============================================================

    function getHostname(url) {
        try {
            return new URL(url, location.href).hostname;
        } catch (_) {
            return null;
        }
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
        try {
            return new URL(url, location.href).origin === location.origin;
        } catch (_) {
            // Relative URLs and javascript: count as same-origin (let the page handle them).
            return true;
        }
    }

    function isUserRecentlyActive() {
        return Date.now() - lastInteractionAt < USER_INTERACTION_WINDOW_MS;
    }

    // ============================================================
    // Central policy decision
    // ============================================================
    //
    // Default-deny for cross-origin navigations that aren't tied to a real
    // user gesture, even if the destination isn't on the blacklist yet --
    // that's the difference from the old version, which only blocked
    // explicitly-blacklisted hosts and was therefore reactive instead of
    // preventive.
    //
    // Returns true to allow the navigation, false to block it.

    function shouldAllowNavigation(url, source) {
        if (!url) return true; // No URL = same-page reload or fragment.

        // 1. Always block blacklisted destinations.
        if (isInBlacklist(url)) {
            const h = getHostname(url);
            if (h) addToAutomatedBlacklist(h);
            warn(`Blocked (blacklist) [${source}]: ${url}`);
            return false;
        }

        // 2. Same-origin always allowed.
        if (isSameOrigin(url)) return true;

        // 3. Allowlisted cross-origin destinations.
        if (isInAllowlist(url)) return true;

        // 4. User just clicked / typed / submitted -> their intent.
        if (isUserRecentlyActive()) {
            log(`Allowed (user-initiated) [${source}]: ${url}`);
            return true;
        }

        // 5. Cross-origin without user interaction = nefarious by default.
        const h = getHostname(url);
        if (h) addToAutomatedBlacklist(h);
        warn(`Blocked (no user interaction) [${source}]: ${url}`);
        return false;
    }

    // ============================================================
    // User-gesture tracking + anchor/form click capture
    // ============================================================

    function noteInteraction() {
        lastInteractionAt = Date.now();
    }

    document.addEventListener('keydown', noteInteraction, true);
    document.addEventListener('touchstart', noteInteraction, true);

    document.addEventListener('click', (event) => {
        // Note: we set the timestamp BEFORE the policy check because the
        // click itself is the gesture; subsequent JS that reads
        // lastInteractionAt should see "yes, user just interacted".
        noteInteraction();

        const target = event.target;
        const anchor = target && target.closest && target.closest('a[href]');
        if (!anchor) return;

        const href = anchor.href;
        if (!href || href.startsWith('javascript:') || href.startsWith('mailto:')) return;

        if (!shouldAllowNavigation(href, 'anchor click')) {
            event.preventDefault();
            event.stopPropagation();
        }
    }, true);

    document.addEventListener('submit', (event) => {
        noteInteraction();
        const form = event.target;
        const action = form && form.action;
        if (action && !shouldAllowNavigation(action, 'form submit (event)')) {
            event.preventDefault();
            event.stopPropagation();
        }
    }, true);

    // ============================================================
    // Override Location methods/setter
    // ============================================================
    //
    // In modern browsers Location.prototype.{assign,replace,href} are
    // non-configurable, so the defineProperty/assignment below may throw.
    // That's fine -- we catch and fall back to the other hooks. Even when
    // these succeed, they're a strong front-line defense against scripted
    // `location.href = '...'` redirects, which the old version missed.

    function tryWrapLocationMethod(method) {
        try {
            const original = Location.prototype[method];
            if (typeof original !== 'function') return false;
            Location.prototype[method] = function (url) {
                if (!shouldAllowNavigation(url, `location.${method}`)) return undefined;
                return original.call(this, url);
            };
            return true;
        } catch (e) {
            warn(`Could not override Location.prototype.${method}:`, e);
            return false;
        }
    }

    tryWrapLocationMethod('assign');
    tryWrapLocationMethod('replace');

    try {
        const desc = Object.getOwnPropertyDescriptor(Location.prototype, 'href');
        if (desc && desc.set && desc.configurable !== false) {
            const originalSetter = desc.set;
            const originalGetter = desc.get;
            Object.defineProperty(Location.prototype, 'href', {
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

    const originalWindowOpen = window.open;
    window.open = function (url, name, features) {
        if (!url) return originalWindowOpen.call(this, url, name, features);
        if (!shouldAllowNavigation(url, 'window.open')) return null;
        return originalWindowOpen.call(this, url, name, features);
    };

    // ============================================================
    // history.pushState / replaceState
    // ============================================================

    function wrapHistoryMethod(method) {
        const original = history[method];
        history[method] = function (data, title, url) {
            if (url && !shouldAllowNavigation(url, `history.${method}`)) {
                return undefined;
            }
            return original.apply(this, arguments);
        };
    }

    wrapHistoryMethod('pushState');
    wrapHistoryMethod('replaceState');

    // ============================================================
    // popstate revert
    // ============================================================

    window.addEventListener('popstate', () => {
        const here = window.location.href;
        if (shouldAllowNavigation(here, 'popstate')) {
            lastKnownGoodUrl = here;
            return;
        }
        if (lastKnownGoodUrl && lastKnownGoodUrl !== here) {
            history.pushState(null, '', lastKnownGoodUrl);
            window.location.replace(lastKnownGoodUrl);
        }
    });

    // ============================================================
    // HTMLFormElement.prototype.submit (programmatic form submission)
    // ============================================================

    try {
        const originalSubmit = HTMLFormElement.prototype.submit;
        HTMLFormElement.prototype.submit = function () {
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
    //
    // Pattern: `content="3;url=https://evil.com"` (or `URL=`, `Url =`, etc.)
    // We pull the URL out, run it through the policy, and remove the node
    // if it's blocked. This is one of the most common nefarious-redirect
    // patterns and the old version did nothing about it.

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
            // Attribute changes on existing meta nodes (e.g. setAttribute('content', ...))
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

    log('Initialized v5.0. Hooks: window.open, location.{assign,replace,href=},',
        'history.{pushState,replaceState,popstate}, form.submit(),',
        'anchor/form click capture, <meta http-equiv="refresh">.');
})();
