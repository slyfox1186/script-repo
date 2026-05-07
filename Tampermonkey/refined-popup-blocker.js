// ==UserScript==
// @name         Refined Popup Blocker
// @namespace    http://tampermonkey.net/
// @version      2.9.0
// @description  Differentiates between good and bad pop-ups by monitoring user interactions and dynamically added content. Aggressively blocks unwanted pop-ups while allowing user-initiated ones. Prompts the user to blacklist sites when pop-ups are blocked. Press Alt+0 to remove the site and its subdomains from both the whitelist and blacklist.
// @match        *://*/*
// @grant        GM_getValue
// @grant        GM_setValue
// @run-at       document-start
// @license      MIT
// ==/UserScript==

(function () {
    'use strict';

    const LOG_PREFIX = '[Tampermonkey Popup Blocker]';
    const USER_INTENT_WINDOW_MS = 1000;

    let userInitiatedUntil = 0;
    let blacklistedWebsites = loadStoredSet('blacklistedWebsites');
    let whitelistedWebsites = loadStoredSet('whitelistedWebsites');
    const promptedWebsites = new Set();

    function log(message) {
        console.log(`${LOG_PREFIX} ${message}`);
    }

    function loadStoredSet(key) {
        try {
            return new Set(JSON.parse(GM_getValue(key, '[]')));
        } catch (e) {
            log(`Error parsing ${key} from storage: ${e}`);
            return new Set();
        }
    }

    function persistSet(key, sites) {
        GM_setValue(key, JSON.stringify([...sites]));
        log(`${key} saved`);
    }

    // Match exact host or any subdomain. Crucially, plain hostname.endsWith(site)
    // would let "evilexample.com" match "example.com"; we require '.<site>' or equality.
    function hostnameMatches(hostname, site) {
        return hostname === site || hostname.endsWith('.' + site);
    }

    function hostnameInSet(hostname, set) {
        if (!hostname) return false;
        for (const site of set) {
            if (hostnameMatches(hostname, site)) return true;
        }
        return false;
    }

    function urlMatchesSet(url, set) {
        try {
            return hostnameInSet(new URL(url, location.origin).hostname, set);
        } catch (e) {
            log(`Error parsing url '${url}': ${e}`);
            return false;
        }
    }

    function addToBlacklist(hostname) {
        blacklistedWebsites.add(hostname);
        persistSet('blacklistedWebsites', blacklistedWebsites);
        log(`Added ${hostname} to blacklist`);
    }

    function addToWhitelist(hostname) {
        whitelistedWebsites.add(hostname);
        persistSet('whitelistedWebsites', whitelistedWebsites);
        log(`Added ${hostname} to whitelist`);
    }

    // Remove the input hostname plus any of its subdomains from a set.
    // Does NOT remove unrelated hostnames that merely end with the input
    // (the previous bidirectional endsWith logic had that bug).
    function dropFromSet(set, hostname) {
        let removed = false;
        for (const site of [...set]) {
            if (site === hostname || site.endsWith('.' + hostname)) {
                set.delete(site);
                removed = true;
            }
        }
        return removed;
    }

    function removeFromLists(hostname) {
        const foundInBlacklist = dropFromSet(blacklistedWebsites, hostname);
        const foundInWhitelist = dropFromSet(whitelistedWebsites, hostname);
        if (foundInBlacklist) persistSet('blacklistedWebsites', blacklistedWebsites);
        if (foundInWhitelist) persistSet('whitelistedWebsites', whitelistedWebsites);
        return { foundInBlacklist, foundInWhitelist };
    }

    function isUserInitiated() {
        return Date.now() < userInitiatedUntil;
    }

    function allowPopup(url) {
        log(`Allowed popup: ${url}`);
    }

    function blockPopup(url) {
        let hostname;
        try {
            hostname = new URL(url, location.origin).hostname;
        } catch (e) {
            log(`Error blocking popup: ${e}`);
            return;
        }

        log(`Blocked popup: ${url}`);
        if (
            !hostnameInSet(hostname, blacklistedWebsites) &&
            !hostnameInSet(hostname, whitelistedWebsites) &&
            !promptedWebsites.has(hostname)
        ) {
            promptedWebsites.add(hostname);
            setTimeout(() => {
                if (confirm(`A popup from ${hostname} was blocked. Block pop-ups from this site in the future?`)) {
                    addToBlacklist(hostname);
                } else {
                    addToWhitelist(hostname);
                }
                location.reload();
            }, 0);
        }
    }

    // Intercept window.open
    const originalOpen = window.open;
    window.open = function (url, name, specs) {
        if (!url) return originalOpen.call(this, url, name, specs);
        let hostname;
        try {
            hostname = new URL(url, location.origin).hostname;
        } catch (e) {
            log(`Error parsing window.open url: ${e}`);
            return null;
        }
        log(`window.open called with url: ${url}`);
        if (isUserInitiated() || hostnameInSet(hostname, whitelistedWebsites)) {
            allowPopup(url);
            const newWindow = originalOpen.call(this, url, name, specs);
            monitorNewWindow(newWindow);
            return newWindow;
        }
        blockPopup(url);
        return null;
    };

    // Some hostile sites open a popup, then navigate it to about:blank for tracking.
    // Cross-origin reads will throw a SecurityError; we silently stop monitoring then.
    function monitorNewWindow(win) {
        if (!win) return;
        const interval = setInterval(() => {
            try {
                if (win.closed) {
                    clearInterval(interval);
                    return;
                }
                if (win.location.href === 'about:blank') {
                    log('Closed window that navigated to about:blank');
                    win.close();
                    clearInterval(interval);
                }
            } catch (e) {
                clearInterval(interval); // cross-origin: stop quietly
            }
        }, 100);
    }

    function noteUserInitiated() {
        userInitiatedUntil = Date.now() + USER_INTENT_WINDOW_MS;
    }

    document.addEventListener('click', noteUserInitiated, true);
    document.addEventListener('submit', noteUserInitiated, true);
    document.addEventListener('keydown', noteUserInitiated, true);

    if (hostnameInSet(location.hostname, whitelistedWebsites)) {
        log(`Site ${location.hostname} is whitelisted. Pop-up blocker is disabled.`);
    } else {
        const observer = new MutationObserver((mutations) => {
            for (const mutation of mutations) {
                for (const node of mutation.addedNodes) {
                    if (node.nodeType !== Node.ELEMENT_NODE) continue;
                    if (node.tagName !== 'IFRAME' && node.tagName !== 'SCRIPT') continue;
                    const src = node.getAttribute('src');
                    if (!src || src === 'about:blank' || urlMatchesSet(src, blacklistedWebsites)) {
                        log(`Blocked dynamically added element: ${node.tagName}, src: ${src}`);
                        blockPopup(src || 'about:blank');
                        node.remove();
                    }
                }
            }
        });
        observer.observe(document.documentElement, { childList: true, subtree: true });

        // Block string-eval popups in setTimeout/setInterval (legacy attack pattern).
        for (const fnName of ['setTimeout', 'setInterval']) {
            const original = window[fnName];
            window[fnName] = function (...args) {
                if (typeof args[0] === 'string' && args[0].includes('window.open')) {
                    log(`Blocked ${fnName} containing window.open`);
                    blockPopup('about:blank');
                    return null;
                }
                return original.apply(this, args);
            };
        }
    }

    document.addEventListener('keydown', (event) => {
        if (event.altKey && event.key === '0') {
            const hostname = location.hostname;
            const { foundInBlacklist, foundInWhitelist } = removeFromLists(hostname);
            if (foundInBlacklist || foundInWhitelist) {
                const lists = [foundInBlacklist && 'blacklist', foundInWhitelist && 'whitelist']
                    .filter(Boolean)
                    .join(' and ');
                alert(`${hostname} and its subdomains have been removed from the ${lists}.`);
            } else {
                alert(`${hostname} was not found in the blacklist or whitelist.`);
            }
        }
    });

    log('Refined Popup Blocker initialized with user interaction and dynamic content monitoring.');
})();
