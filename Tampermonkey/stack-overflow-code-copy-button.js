// ==UserScript==
// @name         Stack Overflow Code Copy Button
// @namespace    http://tampermonkey.net/
// @version      1.2
// @description  Adds a small copy button to the top right corner of all code blocks on Stack Overflow making the copying process a breeze
// @match        https://stackoverflow.com/questions/*
// @grant        none
// @license      MIT
// ==/UserScript==

(function() {
    'use strict';

    function addCopyButton(codeBlock) {
        codeBlock.style.position = 'relative';

        const button = document.createElement('button');
        button.textContent = 'Copy';
        button.style.position = 'absolute';
        button.style.top = '5px';
        button.style.right = '5px';
        button.style.zIndex = '10';
        button.onclick = function() {
            const codeEl = codeBlock.querySelector('code');
            const code = codeEl ? codeEl.innerText : codeBlock.innerText;
            navigator.clipboard.writeText(code).then(() => {
                button.textContent = 'Copied!';
                setTimeout(() => { button.textContent = 'Copy'; }, 1500);
            }, () => {
                button.textContent = 'Failed';
                setTimeout(() => { button.textContent = 'Copy'; }, 1500);
            });
        };

        codeBlock.appendChild(button);
    }

    document.querySelectorAll('pre').forEach(addCopyButton);
})();
