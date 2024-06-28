// ==UserScript==
// @name         Stop Nefarious Redirects
// @namespace    http://tampermonkey.net/
// @version      4.1
// @description  Block unauthorized redirects and prevent history manipulation
// @match        http://*/*
// @match        https://*/*
// @grant        GM_setValue
// @grant        GM_getValue
// @grant        GM_xmlhttpRequest
// @license      MIT
// @run-at       document-start
// @icon         data:image/webp;base64,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
// ==/UserScript==
 
const manualBlacklist = new Set([
    'getrunkhomuto.info'
]);
 
// List of allowed popups domains (user should re-add specific domains here)
const allowedSites = new Set([
    '500px.com', 'accuweather.com', 'adobe.com', 'alibaba.com', 'amazon.com',
    'apple.com', 'bbc.com', 'bing.com', 'cnn.com', 'craigslist.org',
    'dailymail.co.uk', 'ebay.com', 'facebook.com', 'github.com', 'google.com',
    'instagram.com', 'linkedin.com', 'microsoft.com', 'netflix.com', 'reddit.com',
    'twitter.com', 'wikipedia.org', 'youtube.com'
]);
 
const logPrefix = '[Nefarious Redirect Blocker]';
 
(function() {
    'use strict';
 
    console.log(`${logPrefix} Script initialization started.`);
 
    function getAutomatedBlacklist() {
        return new Set(GM_getValue('blacklist', []));
    }
 
    function addToAutomatedBlacklist(url) {
        const encodedUrl = encodeURIComponent(url);
        const blacklist = getAutomatedBlacklist();
        if (!blacklist.has(encodedUrl)) {
            blacklist.add(encodedUrl);
            GM_setValue('blacklist', Array.from(blacklist));
            console.log(`${logPrefix} Added to automated blacklist:`, url);
        }
    }
 
    function isNavigationAllowed(url) {
        if (!isUrlBlocked(url)) {
            console.log(`${logPrefix} Navigation allowed to:`, url);
            lastKnownGoodUrl = url;
            return true;
        } else {
            console.error(`${logPrefix} Blocked navigation to:`, url);
            addToAutomatedBlacklist(url);
            if (lastKnownGoodUrl) {
                window.location.replace(lastKnownGoodUrl);
            }
            return false;
        }
    }
 
    const originalOpen = window.open;
 
    console.log(`${logPrefix} Original window.open saved.`);
 
    window.open = function(url, name, features) {
        console.log(`${logPrefix} Popup attempt detected:`, url);
        if (Array.from(allowedSites).some(domain => url.includes(domain)) || isNavigationAllowed(url)) {
            console.log(`${logPrefix} Popup allowed for:`, url);
            return originalOpen(url, name, features);
        }
        console.log(`${logPrefix} Blocked a popup from:`, url);
        return null;
    };
 
    console.log(`${logPrefix} window.open overridden with custom logic.`);
 
    let lastKnownGoodUrl = window.location.href;
 
    function interceptNavigation(event) {
        const url = event.detail.url;
        if (!isNavigationAllowed(url)) {
            event.preventDefault();
            return false;
        }
        return true;
    }
 
    window.addEventListener('beforeunload', function(event) {
        if (!isNavigationAllowed(window.location.href)) {
            event.preventDefault();
            event.returnValue = '';
            return false;
        }
    });
 
    window.addEventListener('popstate', function(event) {
        if (!isNavigationAllowed(window.location.href)) {
            console.error(`${logPrefix} Blocked navigation to:`, window.location.href);
            history.pushState(null, "", lastKnownGoodUrl);
            window.location.replace(lastKnownGoodUrl);
            event.preventDefault();
        }
    });
 
    function handleHistoryManipulation(originalMethod, data, title, url) {
        if (!isUrlBlocked(url)) {
            return originalMethod.call(history, data, title, url);
        }
        console.error(`${logPrefix} Blocked history manipulation to:`, url);
    }
 
    const originalPushState = history.pushState;
    const originalReplaceState = history.replaceState;
 
    history.pushState = function(data, title, url) {
        return handleHistoryManipulation(originalPushState, data, title, url);
    };
 
    history.replaceState = function(data, title, url) {
        return handleHistoryManipulation(originalReplaceState, data, title, url);
    };
 
    function isUrlBlocked(url) {
        const encodedUrl = encodeURIComponent(url);
        const automatedBlacklist = getAutomatedBlacklist();
        const isBlocked = [...manualBlacklist, ...automatedBlacklist].some(blockedUrl => encodedUrl.includes(blockedUrl));
        if (isBlocked) {
            console.log(`${logPrefix} Blocked URL:`, url);
        }
        return isBlocked;
    }
 
    console.log(`${logPrefix} Redirect control script with blacklist initialized.`);
})();
