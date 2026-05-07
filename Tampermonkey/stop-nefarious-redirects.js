// ==UserScript==
// @name         Stop Nefarious Redirects
// @namespace    http://tampermonkey.net/
// @version      4.3
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

    const LOG_PREFIX = '[Nefarious Redirect Blocker]';

    const manualBlacklist = new Set([
        'getrunkhomuto.info'
    ]);

    const allowedSites = new Set([
        '500px.com', 'accuweather.com', 'adobe.com', 'alibaba.com', 'amazon.com',
        'apple.com', 'bbc.com', 'bing.com', 'cnn.com', 'craigslist.org',
        'dailymail.co.uk', 'ebay.com', 'facebook.com', 'github.com', 'google.com',
        'instagram.com', 'linkedin.com', 'microsoft.com', 'netflix.com', 'reddit.com',
        'twitter.com', 'wikipedia.org', 'youtube.com'
    ]);

    let lastKnownGoodUrl = window.location.href;

    console.log(`${LOG_PREFIX} Script initialization started.`);

    function getAutomatedBlacklist() {
        try {
            const stored = GM_getValue('blacklist', '[]');
            const parsed = typeof stored === 'string' ? JSON.parse(stored) : stored;
            return new Set(Array.isArray(parsed) ? parsed : []);
        } catch (e) {
            console.error(`${LOG_PREFIX} Error parsing blacklist:`, e);
            return new Set();
        }
    }

    function addToAutomatedBlacklist(hostname) {
        const blacklist = getAutomatedBlacklist();
        if (!blacklist.has(hostname)) {
            blacklist.add(hostname);
            GM_setValue('blacklist', JSON.stringify([...blacklist]));
            console.log(`${LOG_PREFIX} Added to automated blacklist:`, hostname);
        }
    }

    function getHostname(url) {
        try {
            return new URL(url, location.origin).hostname;
        } catch (e) {
            return null;
        }
    }

    function hostnameMatchesSet(hostname, siteSet) {
        if (!hostname) return false;
        for (const site of siteSet) {
            if (hostname === site || hostname.endsWith('.' + site)) return true;
        }
        return false;
    }

    function isDomainAllowed(hostname) {
        return hostnameMatchesSet(hostname, allowedSites);
    }

    function isUrlBlocked(url) {
        const hostname = getHostname(url);
        if (!hostname) return false;
        return hostnameMatchesSet(hostname, manualBlacklist) ||
               hostnameMatchesSet(hostname, getAutomatedBlacklist());
    }

    // Pure side-effect-free check: is this URL blocked?
    function isPopupAllowed(url) {
        const hostname = getHostname(url);
        if (isDomainAllowed(hostname)) return true;
        return !isUrlBlocked(url);
    }

    // Used only for navigation events on the *current* page (popstate, history methods).
    // It mutates lastKnownGoodUrl on allow and redirects the current page on block.
    function isCurrentPageNavigationAllowed(url) {
        if (!isUrlBlocked(url)) {
            console.log(`${LOG_PREFIX} Navigation allowed to:`, url);
            lastKnownGoodUrl = url;
            return true;
        }
        console.error(`${LOG_PREFIX} Blocked navigation to:`, url);
        const hostname = getHostname(url);
        if (hostname) addToAutomatedBlacklist(hostname);
        if (lastKnownGoodUrl && lastKnownGoodUrl !== url) {
            window.location.replace(lastKnownGoodUrl);
        }
        return false;
    }

    const originalOpen = window.open;
    window.open = function (url, name, features) {
        if (!url) return originalOpen.call(this, url, name, features);
        console.log(`${LOG_PREFIX} Popup attempt detected:`, url);
        if (isPopupAllowed(url)) {
            console.log(`${LOG_PREFIX} Popup allowed for:`, url);
            return originalOpen.call(this, url, name, features);
        }
        const hostname = getHostname(url);
        if (hostname) addToAutomatedBlacklist(hostname);
        console.log(`${LOG_PREFIX} Blocked popup from:`, url);
        return null;
    };

    window.addEventListener('popstate', function () {
        const here = window.location.href;
        if (!isCurrentPageNavigationAllowed(here)) {
            console.error(`${LOG_PREFIX} Reverting blocked popstate navigation.`);
            history.pushState(null, '', lastKnownGoodUrl);
            window.location.replace(lastKnownGoodUrl);
        }
    });

    function handleHistoryManipulation(originalMethod, data, title, url) {
        if (!url || !isUrlBlocked(url)) {
            return originalMethod.call(history, data, title, url);
        }
        console.error(`${LOG_PREFIX} Blocked history manipulation to:`, url);
    }

    const originalPushState = history.pushState;
    const originalReplaceState = history.replaceState;

    history.pushState = function (data, title, url) {
        return handleHistoryManipulation(originalPushState, data, title, url);
    };

    history.replaceState = function (data, title, url) {
        return handleHistoryManipulation(originalReplaceState, data, title, url);
    };

    console.log(`${LOG_PREFIX} Redirect control script with blacklist initialized.`);
})();
