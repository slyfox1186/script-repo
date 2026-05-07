// ==UserScript==
// @name         Stack Overflow Code Copy Button
// @namespace    http://tampermonkey.net/
// @version      1.3
// @description  Adds a small copy button to the top right corner of every code block on Stack Overflow, including ones loaded after navigation.
// @match        https://stackoverflow.com/questions/*
// @match        https://*.stackexchange.com/questions/*
// @grant        none
// @license      MIT
// ==/UserScript==

(function () {
    'use strict';

    const BUTTON_FLAG = 'tmCopyButtonAttached';

    function addCopyButton(codeBlock) {
        if (codeBlock.dataset[BUTTON_FLAG] === '1') return;
        codeBlock.dataset[BUTTON_FLAG] = '1';

        if (getComputedStyle(codeBlock).position === 'static') {
            codeBlock.style.position = 'relative';
        }

        const button = document.createElement('button');
        button.type = 'button';
        button.textContent = 'Copy';
        Object.assign(button.style, {
            position: 'absolute',
            top: '5px',
            right: '5px',
            zIndex: '10',
            padding: '2px 8px',
            font: '12px sans-serif',
            cursor: 'pointer',
        });
        button.addEventListener('click', async () => {
            const codeEl = codeBlock.querySelector('code');
            const text = codeEl ? codeEl.innerText : codeBlock.innerText;
            try {
                await navigator.clipboard.writeText(text);
                flashLabel(button, 'Copied!');
            } catch (err) {
                console.error('Copy failed:', err);
                flashLabel(button, 'Failed');
            }
        });

        codeBlock.appendChild(button);
    }

    function flashLabel(button, label) {
        const original = 'Copy';
        button.textContent = label;
        setTimeout(() => { button.textContent = original; }, 1500);
    }

    function attachToAll(root) {
        const blocks = root.querySelectorAll
            ? root.querySelectorAll('pre')
            : [];
        blocks.forEach(addCopyButton);
    }

    // Initial pass.
    attachToAll(document);

    // Stack Overflow lazy-loads answers and inserts new <pre> blocks via XHR
    // (clicking "Show more answers", expanding accepted-answer threads, etc.).
    // Watch for additions and decorate them too.
    const observer = new MutationObserver((mutations) => {
        for (const m of mutations) {
            for (const node of m.addedNodes) {
                if (node.nodeType !== Node.ELEMENT_NODE) continue;
                if (node.tagName === 'PRE') addCopyButton(node);
                attachToAll(node);
            }
        }
    });
    observer.observe(document.body, { childList: true, subtree: true });
})();
