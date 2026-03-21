// ==UserScript==
// @name         Link Copier with Redirects
// @namespace    http://tampermonkey.net/
// @version      1.1
// @description  Copies all links on a page to the clipboard, including redirects
// @match        *://*/*
// @grant        GM_setClipboard
// @grant        GM.xmlHttpRequest
// @grant        GM_notification
// @license      MIT
// ==/UserScript==

(function() {
    'use strict';

    window.addEventListener('keydown', handleKeydown);

    function handleKeydown(event) {
        if (event.altKey && event.key === '1') {
            console.log('Alt+1 detected, starting to copy links to clipboard.');
            startLinkCopying();
        }
    }

    function startLinkCopying() {
        GM_notification({
            title: 'Link Copier with Redirects',
            text: 'Link copying process started!',
            timeout: 2500,
        });

        copyLinksToClipboard();
    }

    async function copyLinksToClipboard() {
        const links = Array.from(document.querySelectorAll('a[href]'));
        const uniqueLinks = Array.from(new Set(links.map(link => link.href).filter(Boolean)));
        console.log(`Found ${uniqueLinks.length} unique links.`);

        const linkResults = await Promise.all(uniqueLinks.map(link => followRedirect(link)));

        const clipboardText = linkResults.map((redirectChain) => {
            const originalLink = redirectChain[0];
            const redirectText = redirectChain.slice(1).map(link => `  - ${link}`).join('\n');
            return `${originalLink}\n${redirectText}`;
        }).join('\n').trim().replace(/\n\n+/g, '\n');

        GM_setClipboard(clipboardText);

        GM_notification({
            title: 'Link Copier with Redirects',
            text: 'Links successfully copied to clipboard!',
            timeout: 2500,
        });
    }

    async function followRedirect(url, maxRedirects = 5) {
        const seenUrls = [url];
        let currentUrl = url;

        while (maxRedirects > 0) {
            try {
                const response = await fetchUrl(currentUrl);

                if (response.finalUrl === currentUrl || seenUrls.includes(response.finalUrl)) {
                    break;
                }

                seenUrls.push(response.finalUrl);
                currentUrl = response.finalUrl;
                maxRedirects--;
            } catch (error) {
                console.error(`Error following redirect for link: ${currentUrl}`, error);
                break;
            }
        }

        return seenUrls;
    }

    function fetchUrl(url) {
        return new Promise((resolve, reject) => {
            GM.xmlHttpRequest({
                method: "GET",
                url: url,
                onload: (response) => resolve(response),
                onerror: (error) => reject(error)
            });
        });
    }

    console.log('Link Copier with Redirects script loaded. Press Alt+1 to copy links.');
})();
