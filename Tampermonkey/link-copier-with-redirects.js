// ==UserScript==
// @name         Link Copier with Redirects
// @namespace    http://tampermonkey.net/
// @version      1.2
// @description  Copies all links on a page to the clipboard, including redirects
// @match        *://*/*
// @grant        GM_setClipboard
// @grant        GM.xmlHttpRequest
// @grant        GM_notification
// @license      MIT
// ==/UserScript==

(function () {
    'use strict';

    const REQUEST_TIMEOUT_MS = 10000;
    const MAX_REDIRECT_HOPS = 5;
    const CONCURRENCY = 8;

    window.addEventListener('keydown', handleKeydown);
    console.log('Link Copier with Redirects script loaded. Press Alt+1 to copy links.');

    let running = false;

    function handleKeydown(event) {
        if (event.altKey && event.key === '1') {
            if (running) {
                console.log('Link copy already in progress; ignoring trigger.');
                return;
            }
            console.log('Alt+1 detected, starting to copy links to clipboard.');
            startLinkCopying();
        }
    }

    async function startLinkCopying() {
        running = true;
        try {
            GM_notification({
                title: 'Link Copier with Redirects',
                text: 'Link copying process started!',
                timeout: 2500,
            });
            await copyLinksToClipboard();
        } finally {
            running = false;
        }
    }

    async function copyLinksToClipboard() {
        const all = Array.from(document.querySelectorAll('a[href]'), a => a.href).filter(Boolean);
        const uniqueLinks = Array.from(new Set(all));
        console.log(`Found ${uniqueLinks.length} unique links.`);

        const linkResults = await mapWithConcurrency(uniqueLinks, CONCURRENCY, followRedirect);

        const clipboardText = linkResults
            .map(chain => {
                const original = chain[0];
                const tail = chain.slice(1).map(link => `  - ${link}`).join('\n');
                return tail ? `${original}\n${tail}` : original;
            })
            .filter(Boolean)
            .join('\n');

        GM_setClipboard(clipboardText);
        GM_notification({
            title: 'Link Copier with Redirects',
            text: `Copied ${uniqueLinks.length} link(s) to clipboard!`,
            timeout: 2500,
        });
    }

    // Run `worker` over `items` with at most `limit` in flight at once.
    async function mapWithConcurrency(items, limit, worker) {
        const results = new Array(items.length);
        let nextIndex = 0;
        const runners = Array.from({ length: Math.min(limit, items.length) }, async () => {
            while (true) {
                const i = nextIndex++;
                if (i >= items.length) return;
                try {
                    results[i] = await worker(items[i]);
                } catch (err) {
                    console.error(`Worker error on ${items[i]}:`, err);
                    results[i] = [items[i]];
                }
            }
        });
        await Promise.all(runners);
        return results;
    }

    async function followRedirect(url) {
        const seen = [url];
        let current = url;
        for (let hop = 0; hop < MAX_REDIRECT_HOPS; hop++) {
            let response;
            try {
                response = await fetchUrl(current);
            } catch (error) {
                console.error(`Error following redirect for ${current}:`, error);
                break;
            }
            const finalUrl = response && response.finalUrl;
            if (!finalUrl || finalUrl === current || seen.includes(finalUrl)) {
                break;
            }
            seen.push(finalUrl);
            current = finalUrl;
        }
        return seen;
    }

    function fetchUrl(url) {
        return new Promise((resolve, reject) => {
            let settled = false;
            const handle = GM.xmlHttpRequest({
                method: 'GET',
                url,
                timeout: REQUEST_TIMEOUT_MS,
                onload: (response) => {
                    if (settled) return;
                    settled = true;
                    resolve(response);
                },
                onerror: (error) => {
                    if (settled) return;
                    settled = true;
                    reject(error || new Error(`network error for ${url}`));
                },
                ontimeout: () => {
                    if (settled) return;
                    settled = true;
                    reject(new Error(`timeout after ${REQUEST_TIMEOUT_MS}ms for ${url}`));
                },
            });
            // Belt-and-suspenders timeout in case GM.xmlHttpRequest ignores `timeout`.
            setTimeout(() => {
                if (settled) return;
                settled = true;
                if (handle && typeof handle.abort === 'function') {
                    try { handle.abort(); } catch (_) { /* ignore */ }
                }
                reject(new Error(`hard timeout after ${REQUEST_TIMEOUT_MS}ms for ${url}`));
            }, REQUEST_TIMEOUT_MS + 500);
        });
    }
})();
