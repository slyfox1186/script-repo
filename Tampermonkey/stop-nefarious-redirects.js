// ==UserScript==
// @name         Stop Nefarious Redirects
// @namespace    http://tampermonkey.net/
// @version      4.2
// @description  Block unauthorized redirects and prevent history manipulation
// @match        http://*/*
// @match        https://*/*
// @grant        GM_setValue
// @grant        GM_getValue
// @grant        GM_xmlhttpRequest
// @license      MIT
// @run-at       document-start
// ==/UserScript==

(function() {
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

    function isDomainAllowed(hostname) {
        if (!hostname) return false;
        return [...allowedSites].some(domain => hostname === domain || hostname.endsWith('.' + domain));
    }

    function isUrlBlocked(url) {
        const hostname = getHostname(url);
        if (!hostname) return false;

        const automatedBlacklist = getAutomatedBlacklist();
        for (const blocked of manualBlacklist) {
            if (hostname === blocked || hostname.endsWith('.' + blocked)) return true;
        }
        for (const blocked of automatedBlacklist) {
            if (hostname === blocked || hostname.endsWith('.' + blocked)) return true;
        }
        return false;
    }

    function isNavigationAllowed(url) {
        if (!isUrlBlocked(url)) {
            console.log(`${LOG_PREFIX} Navigation allowed to:`, url);
            lastKnownGoodUrl = url;
            return true;
        } else {
            console.error(`${LOG_PREFIX} Blocked navigation to:`, url);
            const hostname = getHostname(url);
            if (hostname) addToAutomatedBlacklist(hostname);
            if (lastKnownGoodUrl) {
                window.location.replace(lastKnownGoodUrl);
            }
            return false;
        }
    }

    const originalOpen = window.open;
    window.open = function(url, name, features) {
        if (!url) return originalOpen.call(this, url, name, features);
        console.log(`${LOG_PREFIX} Popup attempt detected:`, url);
        const hostname = getHostname(url);
        if (isDomainAllowed(hostname) || isNavigationAllowed(url)) {
            console.log(`${LOG_PREFIX} Popup allowed for:`, url);
            return originalOpen.call(this, url, name, features);
        }
        console.log(`${LOG_PREFIX} Blocked a popup from:`, url);
        return null;
    };

    window.addEventListener('popstate', function() {
        if (!isNavigationAllowed(window.location.href)) {
            console.error(`${LOG_PREFIX} Blocked navigation to:`, window.location.href);
            history.pushState(null, "", lastKnownGoodUrl);
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

    history.pushState = function(data, title, url) {
        return handleHistoryManipulation(originalPushState, data, title, url);
    };

    history.replaceState = function(data, title, url) {
        return handleHistoryManipulation(originalReplaceState, data, title, url);
    };

    console.log(`${LOG_PREFIX} Redirect control script with blacklist initialized.`);
})();
