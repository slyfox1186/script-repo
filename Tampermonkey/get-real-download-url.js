// ==UserScript==
// @name         Get Real Download URL
// @namespace    http://tampermonkey.net/
// @version      1.1
// @description  Get the real download URL by right-clicking on a download link while holding the left Alt key.
// @match        *://*/*
// @grant        GM_setClipboard
// @license      MIT
// ==/UserScript==

(function() {
    'use strict';

    document.addEventListener('contextmenu', function(event) {
        if (event.altKey) {
            const link = event.target.closest('a[href]');
            if (link) {
                event.preventDefault();

                const customMenuItem = document.createElement('div');
                customMenuItem.textContent = 'Get Real Download URL';
                customMenuItem.style.position = 'fixed';
                customMenuItem.style.backgroundColor = '#fff';
                customMenuItem.style.border = '1px solid #ccc';
                customMenuItem.style.padding = '5px';
                customMenuItem.style.cursor = 'pointer';
                customMenuItem.style.zIndex = '10000';
                customMenuItem.style.top = `${event.clientY}px`;
                customMenuItem.style.left = `${event.clientX}px`;
                customMenuItem.style.boxShadow = '0 2px 10px rgba(0,0,0,0.5)';
                customMenuItem.style.borderRadius = '3px';

                function removeMenu() {
                    if (customMenuItem.parentNode) {
                        customMenuItem.parentNode.removeChild(customMenuItem);
                    }
                }

                let timeoutId;

                customMenuItem.addEventListener('click', async function(e) {
                    e.stopPropagation();
                    try {
                        const response = await fetch(link.href, {
                            method: 'HEAD',
                            redirect: 'follow'
                        });

                        const realUrl = response.url || link.href;
                        GM_setClipboard(realUrl);
                        showTemporaryMessage(`Real download URL copied to clipboard: ${realUrl}`, true);
                    } catch (error) {
                        console.error('Error fetching the real download URL:', error);
                        showTemporaryMessage('Failed to get the real download URL.', false);
                    } finally {
                        clearTimeout(timeoutId);
                        removeMenu();
                    }
                });

                customMenuItem.addEventListener('contextmenu', function(e) {
                    e.stopPropagation();
                    e.preventDefault();
                });

                document.body.appendChild(customMenuItem);

                timeoutId = setTimeout(removeMenu, 5000);
                document.addEventListener('click', function dismissMenu(e) {
                    if (e.target !== customMenuItem) {
                        clearTimeout(timeoutId);
                        removeMenu();
                        document.removeEventListener('click', dismissMenu);
                    }
                });
            }
        }
    });

    function showTemporaryMessage(message, success) {
        const msgDiv = document.createElement('div');
        msgDiv.textContent = message;
        msgDiv.style.position = 'fixed';
        msgDiv.style.bottom = '10px';
        msgDiv.style.right = '10px';
        msgDiv.style.backgroundColor = success ? 'green' : 'red';
        msgDiv.style.color = 'white';
        msgDiv.style.padding = '10px';
        msgDiv.style.borderRadius = '5px';
        msgDiv.style.zIndex = '10000';
        document.body.appendChild(msgDiv);
        setTimeout(() => {
            if (msgDiv.parentNode) {
                msgDiv.parentNode.removeChild(msgDiv);
            }
        }, 1000);
    }
})();
