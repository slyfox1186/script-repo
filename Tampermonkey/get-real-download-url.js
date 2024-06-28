// ==UserScript==
// @name         Get Real Download URL
// @namespace    http://tampermonkey.net/
// @version      1.0
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
                // Create the custom menu item as a floating button
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
 
                const clickHandler = async function() {
                    try {
                        const response = await fetch(link.href, {
                            method: 'HEAD',
                            redirect: 'manual'
                        });
 
                        const realUrl = response.headers.get('location') || link.href;
 
                        GM_setClipboard(realUrl);
                        showTemporaryMessage(`Real download URL copied to clipboard: ${realUrl}`, true);
                    } catch (error) {
                        console.error('Error fetching the real download URL:', error);
                        showTemporaryMessage('Failed to get the real download URL.', false);
                    } finally {
                        document.body.removeChild(customMenuItem);
                    }
                };
 
                customMenuItem.addEventListener('click', clickHandler);
 
                document.body.appendChild(customMenuItem);
 
                const cleanup = () => {
                    if (customMenuItem.parentNode) {
                        customMenuItem.removeEventListener('click', clickHandler);
                        document.body.removeChild(customMenuItem);
                    }
                };
 
                // Cleanup after 5 seconds or when clicking elsewhere
                setTimeout(cleanup, 5000);
                document.addEventListener('click', cleanup, { once: true });
 
                // Prevent propagation to avoid closing the default context menu
                customMenuItem.addEventListener('contextmenu', function(e) {
                    e.stopPropagation();
                    e.preventDefault();
                });
 
                // Prevent default context menu from showing
                event.preventDefault();
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
            document.body.removeChild(msgDiv);
        }, 1000);
    }
})();
