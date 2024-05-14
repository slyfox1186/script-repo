// ==UserScript==
// @name Stop Nefarious Redirects
// @namespace http://tampermonkey.net/
// @version 3.87
// @description Block unauthorized redirects and prevent history manipulation
// @match http://*/*
// @match https://*/*
// @grant GM_setValue
// @grant GM_getValue
// @license MIT
// @run-at document-start
// ==/UserScript==
 
(function() {
  'use strict';
 
  // Function to get the current blacklist
  function getBlacklist() {
    return new Set(GM_getValue('blacklist', []));
  }
 
  // Function to add a URL to the blacklist
  function addToBlacklist(url) {
    let encodedUrl = encodeURIComponent(url);
    let blacklist = getBlacklist();
    if (!blacklist.has(encodedUrl)) {
      blacklist.add(encodedUrl);
      GM_setValue('blacklist', Array.from(blacklist));
      console.log('Added to blacklist:', url);
    }
  }
 
  // Function to display the blacklist
  function displayBlacklist() {
    let blacklist = getBlacklist();
    console.log('Current Blacklist:\n' + Array.from(blacklist).map(decodeURIComponent).join('\n'));
  }
 
  // Function to handle navigation events
  function handleNavigation(url) {
    try {
      if (!isUrlAllowed(url)) {
        console.error('Blocked navigation to:', url);
        addToBlacklist(url); // Add the unauthorized URL to the blacklist
        if (lastKnownGoodUrl) {
          window.location.replace(lastKnownGoodUrl);
        }
        return false;
      } else {
        console.log('Navigation allowed to:', url);
        lastKnownGoodUrl = url;
        return true;
      }
    } catch (error) {
      console.error('Error in handleNavigation:', error);
    }
  }
 
  let lastKnownGoodUrl = window.location.href;
  let navigationInProgress = false;
 
  // Monitor changes to window.location
  ['assign', 'replace', 'href'].forEach(property => {
    const original = window.location[property];
    if (typeof original === 'function') {
      window.location[property] = function(url) {
        if (!navigationInProgress && handleNavigation(url)) {
          navigationInProgress = true;
          setTimeout(() => {
            navigationInProgress = false;
          }, 0);
          return original.apply(this, arguments);
        }
      };
    } else {
      Object.defineProperty(window.location, property, {
        set: function(url) {
          if (!navigationInProgress && handleNavigation(url)) {
            navigationInProgress = true;
            setTimeout(() => {
              navigationInProgress = false;
            }, 0);
            return Reflect.set(window.location, property, url);
          }
        },
        get: function() {
          return original;
        },
        configurable: true
      });
    }
  });
 
  // Enhanced navigation control for back/forward buttons
  window.addEventListener('popstate', function(event) {
    if (!navigationInProgress && !isUrlAllowed(window.location.href)) {
      navigationInProgress = true;
      setTimeout(() => {
        navigationInProgress = false;
      }, 0);
      event.preventDefault();
    }
  });
 
  // Function to handle history manipulation
  function handleHistoryManipulation(originalMethod, data, title, url) {
    if (!isUrlAllowed(url)) {
      console.error('Blocked history manipulation to:', url);
      return;
    }
    return originalMethod(data, title, url);
  }
 
  // Wrap history.pushState and history.replaceState
  const originalPushState = history.pushState;
  const originalReplaceState = history.replaceState;
 
  history.pushState = function(data, title, url) {
    return handleHistoryManipulation.call(history, originalPushState.bind(this), data, title, url);
  };
 
  history.replaceState = function(data, title, url) {
    return handleHistoryManipulation.call(history, originalReplaceState.bind(this), data, title, url);
  };
 
  // Keyboard shortcut listener to display the blacklist
  document.addEventListener('keydown', function(e) {
    if (e.ctrlKey && e.shiftKey && e.key.toLowerCase() === 'l') {
      e.preventDefault();
      displayBlacklist();
    }
  });
 
  // Function to check if a URL is allowed based on the blacklist
  function isUrlAllowed(url) {
    let encodedUrl = encodeURIComponent(url);
    let blacklist = getBlacklist();
    return !Array.from(blacklist).some(blockedUrl => encodedUrl.includes(blockedUrl));
  }
 
  console.log('Redirect control script with blacklist initialized.');
})();
