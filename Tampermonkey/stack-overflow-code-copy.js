// ==UserScript==
// @name         Stack Overflow Code Copy
// @namespace    http://tampermonkey.net/
// @version      1.0
// @description  Adds a copy button to code blocks on Stack Overflow
// @match        https://stackoverflow.com/questions/*
// @grant        none
// ==/UserScript==

(function() {
    'use strict';

    function addCopyButton(codeBlock) {
        const button = document.createElement('button');
        button.innerHTML = 'Copy';
        button.style.position = 'absolute';
        button.style.top = '5px';
        button.style.right = '5px';
        button.onclick = function() {
            const code = codeBlock.querySelector('code').innerText;
            navigator.clipboard.writeText(code);
        };
        codeBlock.style.position = 'relative';
        codeBlock.appendChild(button);
    }

    const codeBlocks = document.querySelectorAll('pre');
    codeBlocks.forEach(addCopyButton);
})();
