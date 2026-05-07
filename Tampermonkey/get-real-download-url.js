// ==UserScript==
// @name         Get Real Download URL
// @namespace    http://tampermonkey.net/
// @version      1.2
// @description  Get the real download URL by right-clicking on a download link while holding the left Alt key.
// @match        *://*/*
// @grant        GM_setClipboard
// @license      MIT
// ==/UserScript==

(function () {
    'use strict';

    const MENU_TIMEOUT_MS = 5000;
    const FETCH_TIMEOUT_MS = 15000;
    const MENU_ID = 'tm-real-dl-url-menu';
    let activeMenu = null;
    let activeDismissHandler = null;
    let activeTimeoutId = null;

    document.addEventListener('contextmenu', (event) => {
        if (!event.altKey) return;
        const link = event.target.closest && event.target.closest('a[href]');
        if (!link) return;

        event.preventDefault();
        showResolveMenu(event.clientX, event.clientY, link.href);
    });

    function showResolveMenu(x, y, href) {
        removeActiveMenu(); // never stack menus

        const menu = document.createElement('div');
        menu.id = MENU_ID;
        menu.textContent = 'Get Real Download URL';
        Object.assign(menu.style, {
            position: 'fixed',
            top: `${y}px`,
            left: `${x}px`,
            backgroundColor: '#fff',
            color: '#111',
            border: '1px solid #ccc',
            borderRadius: '3px',
            padding: '5px 8px',
            cursor: 'pointer',
            zIndex: '2147483647',
            font: '13px sans-serif',
            boxShadow: '0 2px 10px rgba(0,0,0,0.5)',
        });

        menu.addEventListener('contextmenu', (e) => {
            e.preventDefault();
            e.stopPropagation();
        });
        menu.addEventListener('click', async (e) => {
            e.stopPropagation();
            try {
                const realUrl = await resolveFinalUrl(href, FETCH_TIMEOUT_MS);
                GM_setClipboard(realUrl);
                showTemporaryMessage(`Real download URL copied: ${realUrl}`, true);
            } catch (error) {
                console.error('Error fetching the real download URL:', error);
                showTemporaryMessage('Failed to get the real download URL.', false);
            } finally {
                removeActiveMenu();
            }
        });

        document.body.appendChild(menu);
        activeMenu = menu;

        activeTimeoutId = setTimeout(removeActiveMenu, MENU_TIMEOUT_MS);
        activeDismissHandler = (e) => {
            if (e.target !== menu) removeActiveMenu();
        };
        // Capture so we run before page click handlers can swallow the event.
        document.addEventListener('click', activeDismissHandler, true);
    }

    function removeActiveMenu() {
        if (activeTimeoutId !== null) {
            clearTimeout(activeTimeoutId);
            activeTimeoutId = null;
        }
        if (activeDismissHandler) {
            document.removeEventListener('click', activeDismissHandler, true);
            activeDismissHandler = null;
        }
        if (activeMenu && activeMenu.parentNode) {
            activeMenu.parentNode.removeChild(activeMenu);
        }
        activeMenu = null;
    }

    async function resolveFinalUrl(href, timeoutMs) {
        const controller = new AbortController();
        const timer = setTimeout(() => controller.abort(), timeoutMs);
        try {
            const response = await fetch(href, {
                method: 'HEAD',
                redirect: 'follow',
                signal: controller.signal,
            });
            return response.url || href;
        } finally {
            clearTimeout(timer);
        }
    }

    function showTemporaryMessage(message, success) {
        const div = document.createElement('div');
        div.textContent = message;
        Object.assign(div.style, {
            position: 'fixed',
            bottom: '10px',
            right: '10px',
            backgroundColor: success ? '#1e7e34' : '#c0392b',
            color: 'white',
            padding: '10px 12px',
            borderRadius: '5px',
            zIndex: '2147483647',
            font: '13px sans-serif',
            maxWidth: '60vw',
            wordBreak: 'break-all',
        });
        document.body.appendChild(div);
        setTimeout(() => {
            if (div.parentNode) div.parentNode.removeChild(div);
        }, 2500);
    }
})();
