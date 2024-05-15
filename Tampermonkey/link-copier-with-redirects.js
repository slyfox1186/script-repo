/* jshint esversion: 8 */

// https://greasyfork.org/en/scripts/494987-link-copier-with-redirects

// ==UserScript==
// @name         Link Copier with Redirects
// @namespace    http://tampermonkey.net/
// @version      1.0
// @description  Copies all links on a page to the clipboard, including redirects
// @match        *://*/*
// @grant        GM_setClipboard
// @grant        GM.xmlHttpRequest
// @grant        GM_notification
// @license      MIT
// ==/UserScript==
 
(async function() {
    'use strict';
 
    // Handle keydown events
    window.addEventListener('keydown', handleKeydown);
 
    // Function to handle keydown events
    function handleKeydown(event) {
        if (event.altKey && event.key === '1') {
            console.log('Alt+1 detected, starting to copy links to clipboard.');
            startLinkCopying();
        }
    }
 
    // Function to start the link copying process
    function startLinkCopying() {
        console.log('Showing start notification...');
        GM_notification({
            title: 'Link Copier with Redirects',
            text: 'Link copying process started!',
            timeout: 2500,
        });
 
        copyLinksToClipboard();
    }
 
    // Function to copy links to clipboard
    async function copyLinksToClipboard() {
        console.log('Collecting links from the page...');
        const links = Array.from(document.getElementsByTagName('a'));
        const uniqueLinks = Array.from(new Set(links.map(link => link.href)));
        console.log(`Found ${uniqueLinks.length} unique links.`);
 
        console.log('Following redirects for each link...');
        const linkPromises = uniqueLinks.map(async (link) => followRedirect(link));
 
        const linkResults = await Promise.all(linkPromises);
        console.log('All redirect chains followed.');
 
        console.log('Preparing text for the clipboard...');
        const clipboardText = linkResults.map((redirectChain) => {
            const originalLink = redirectChain[0];
            const redirectText = redirectChain.slice(1).map(link => `  - ${link}`).join('\n');
            return `${originalLink}\n${redirectText}`;
        }).join('\n').trim().replace(/\n\n+/g, '\n');
 
        console.log('Setting clipboard content...');
        GM_setClipboard(clipboardText);
 
        console.log('Showing completion notification...');
        GM_notification({
            title: 'Link Copier with Redirects',
            text: 'Links successfully copied to clipboard!',
            timeout: 2500,
        });
    }
 
    // Function to follow redirects
    async function followRedirect(url, maxRedirects = 5) {
        const seenUrls = [url];
        let currentUrl = url;
        console.log(`Starting to follow redirects for: ${url}`);
 
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
 
        console.log(`Redirect chain for ${url}:`, seenUrls);
        return seenUrls;
    }
 
    // Function to fetch a URL and handle redirects
    async function fetchUrl(url) {
        return new Promise((resolve, reject) => {
            GM.xmlHttpRequest({
                method: "GET",
                url: url,
                onload: (response) => resolve(response),
                onerror: (error) => reject(error)
            });
        });
    }
 
    window.addEventListener('load', () => {
        console.log('Link Copier with Redirects script loaded. Press Alt+1 to copy links.');
    });
})();
