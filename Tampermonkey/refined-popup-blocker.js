// ==UserScript==
// @name         Refined Popup Blocker
// @namespace    http://tampermonkey.net/
// @version      2.8.0
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
    let userInitiated = false;
    let blacklistedWebsites = getBlacklistedWebsites();
    let whitelistedWebsites = getWhitelistedWebsites();
    let promptedWebsites = new Set();

    function log(message) {
        console.log(`${LOG_PREFIX} ${message}`);
    }

    function getBlacklistedWebsites() {
        try {
            return new Set(JSON.parse(GM_getValue('blacklistedWebsites', '[]')));
        } catch (e) {
            log('Error parsing blacklist from storage: ' + e);
            return new Set();
        }
    }

    function getWhitelistedWebsites() {
        try {
            return new Set(JSON.parse(GM_getValue('whitelistedWebsites', '[]')));
        } catch (e) {
            log('Error parsing whitelist from storage: ' + e);
            return new Set();
        }
    }

    function saveBlacklistedWebsites(sites) {
        GM_setValue('blacklistedWebsites', JSON.stringify([...sites]));
        log('Blacklist saved');
    }

    function saveWhitelistedWebsites(sites) {
        GM_setValue('whitelistedWebsites', JSON.stringify([...sites]));
        log('Whitelist saved');
    }

    function addToBlacklist(hostname) {
        blacklistedWebsites.add(hostname);
        saveBlacklistedWebsites(blacklistedWebsites);
        log(`Added ${hostname} to blacklist`);
    }

    function addToWhitelist(hostname) {
        whitelistedWebsites.add(hostname);
        saveWhitelistedWebsites(whitelistedWebsites);
        log(`Added ${hostname} to whitelist`);
    }

    function removeFromLists(hostname) {
        let foundInBlacklist = false;
        let foundInWhitelist = false;

        blacklistedWebsites.forEach(site => {
            if (hostname.endsWith(site) || site.endsWith(hostname)) {
                blacklistedWebsites.delete(site);
                foundInBlacklist = true;
            }
        });

        whitelistedWebsites.forEach(site => {
            if (hostname.endsWith(site) || site.endsWith(hostname)) {
                whitelistedWebsites.delete(site);
                foundInWhitelist = true;
            }
        });

        saveBlacklistedWebsites(blacklistedWebsites);
        saveWhitelistedWebsites(whitelistedWebsites);

        return { foundInBlacklist, foundInWhitelist };
    }

    function isBlacklisted(url) {
        try {
            const hostname = new URL(url, location.origin).hostname;
            for (let site of blacklistedWebsites) {
                if (hostname.endsWith(site)) {
                    return true;
                }
            }
            return false;
        } catch (e) {
            log('Error checking blacklist: ' + e);
            return false;
        }
    }

    function isWhitelisted(url) {
        try {
            const hostname = new URL(url, location.origin).hostname;
            for (let site of whitelistedWebsites) {
                if (hostname.endsWith(site)) {
                    return true;
                }
            }
            return false;
        } catch (e) {
            log('Error checking whitelist: ' + e);
            return false;
        }
    }

    function isHostnameWhitelisted(hostname) {
        for (let site of whitelistedWebsites) {
            if (hostname.endsWith(site)) {
                return true;
            }
        }
        return false;
    }

    function allowPopup(url) {
        log('Allowed popup: ' + url);
    }

    function blockPopup(url) {
        try {
            const hostname = new URL(url, location.origin).hostname;
            log('Blocked popup: ' + url);
            if (!blacklistedWebsites.has(hostname) && !whitelistedWebsites.has(hostname) && !promptedWebsites.has(hostname)) {
                promptedWebsites.add(hostname);
                setTimeout(() => {
                    if (confirm(`A popup from ${hostname} was blocked. Do you want to block pop-ups from this site in the future?`)) {
                        addToBlacklist(hostname);
                        location.reload();
                    } else {
                        addToWhitelist(hostname);
                        location.reload();
                    }
                }, 0);
            }
        } catch (e) {
            log('Error blocking popup: ' + e);
        }
    }

    // Intercept window.open calls
    const originalOpen = window.open;
    window.open = function (url, name, specs) {
        if (!url) {
            return originalOpen.call(this, url, name, specs);
        }
        const hostname = new URL(url, location.origin).hostname;
        log(`window.open called with url: ${url}`);
        if (userInitiated || isHostnameWhitelisted(hostname)) {
            allowPopup(url);
            const newWindow = originalOpen.call(this, url, name, specs);
            monitorNewWindow(newWindow);
            return newWindow;
        } else {
            blockPopup(url);
            return null;
        }
    };

    function monitorNewWindow(win) {
        if (!win) return;
        const interval = setInterval(() => {
            try {
                if (win.closed) {
                    clearInterval(interval);
                } else if (win.location.href === 'about:blank') {
                    log('Closed window that navigated to about:blank');
                    win.close();
                    clearInterval(interval);
                }
            } catch (e) {
                clearInterval(interval);
            }
        }, 100);
    }

    // Listen for user-initiated actions
    function setUserInitiated(event) {
        userInitiated = true;
        log(`User-initiated action detected for element: ${event.target.tagName}, class: ${event.target.className}`);
        setTimeout(() => {
            userInitiated = false;
            log('User-initiated action reset');
        }, 1000);
    }

    document.addEventListener('click', setUserInitiated, true);
    document.addEventListener('submit', setUserInitiated, true);
    document.addEventListener('keydown', setUserInitiated, true);

    // Ensure whitelisted sites are respected
    if (isHostnameWhitelisted(location.hostname)) {
        log(`Site ${location.hostname} is whitelisted. Pop-up blocker is disabled.`);
    } else {
        // MutationObserver to block dynamically added iframes and scripts
        const observer = new MutationObserver(function (mutations) {
            mutations.forEach(function (mutation) {
                mutation.addedNodes.forEach(function (node) {
                    if (node.nodeType !== Node.ELEMENT_NODE) return;
                    if (node.tagName === 'IFRAME' || node.tagName === 'SCRIPT') {
                        const src = node.getAttribute('src');
                        log(`Dynamically added element: ${node.tagName}, src: ${src}`);
                        if (!src || src === 'about:blank' || isBlacklisted(src)) {
                            log(`Blocked dynamically added element: ${node.tagName}, src: ${src}`);
                            blockPopup(src || 'about:blank');
                            node.remove();
                        }
                    }
                });
            });
        });

        observer.observe(document.documentElement, { childList: true, subtree: true });

        // Block suspicious string-eval patterns in setTimeout/setInterval
        ['setTimeout', 'setInterval'].forEach((func) => {
            const originalFunc = window[func];
            window[func] = function (...args) {
                if (typeof args[0] === 'string' && args[0].includes('window.open')) {
                    log(`Blocked ${func} containing window.open`);
                    blockPopup('about:blank');
                    return null;
                }
                return originalFunc.apply(this, args);
            };
        });
    }

    // Listen for Alt+0 keypress to remove site from both lists
    document.addEventListener('keydown', (event) => {
        if (event.altKey && event.key === '0') {
            const hostname = location.hostname;
            let { foundInBlacklist, foundInWhitelist } = removeFromLists(hostname);

            if (foundInBlacklist || foundInWhitelist) {
                const lists = [foundInBlacklist && 'blacklist', foundInWhitelist && 'whitelist'].filter(Boolean).join(' and ');
                alert(`${hostname} and its subdomains have been removed from the ${lists}.`);
            } else {
                alert(`${hostname} was not found in the blacklist or whitelist.`);
            }
        }
    });

    log('Refined Popup Blocker initialized with user interaction and dynamic content monitoring.');
})();
