// ==UserScript==
// @name         Stack Overflow Code Copy Button
// @namespace    http://tampermonkey.net/
// @version      1.1
// @description  Adds a small copy button to the top right corner of all code blocks on Stack Overflow making the copying process a breeze
// @match        https://stackoverflow.com/questions/*
// @grant        none
// @license      MIT
// ==/UserScript==
 
/*
    Update Notes:
    v1.1 - Adjusted button positioning to ensure it stays at the top right corner of the code box, even with horizontal scrolling due to long lines of code.
    v1.0 - Initial release which added a copy button to code blocks.
*/
 
(function() {
    'use strict';
 
    function addCopyButton(codeBlock) {
        const button = document.createElement('button');
        button.innerHTML = 'Copy';
        button.style.position = 'absolute';
        button.style.top = '5px';
        button.style.right = '5px';
        button.style.zIndex = '10'; // Ensure the button stays on top
        button.onclick = function() {
            const code = codeBlock.querySelector('code').innerText;
            navigator.clipboard.writeText(code);
        };
        const wrapper = document.createElement('div');
        wrapper.style.position = 'relative';
        codeBlock.style.position = 'relative';
        wrapper.appendChild(codeBlock.cloneNode(true));
        codeBlock.parentNode.replaceChild(wrapper, codeBlock);
        wrapper.appendChild(button);
    }
 
    const codeBlocks = document.querySelectorAll('pre');
    codeBlocks.forEach(addCopyButton);
})();
