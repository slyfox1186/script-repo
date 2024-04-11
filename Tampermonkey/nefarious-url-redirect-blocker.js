// ==UserScript==
// @name         Stop Nefarious Redirects
// @namespace    http://tampermonkey.net/
// @version      2.71
// @description  Detects and stops nefarious URL redirections, allows redirects on trusted websites, and logs the actions
// @match        http://*/*
// @match        https://*/*
// @grant        none
// @license      MIT
// ==/UserScript==
 
(function() {
    'use strict';
 
    // List of trusted websites or domains where redirects are allowed
    const trustedWebsites = [
        '500px.com',
        'adobe.com',
        'amazon.com',
        'apple.com',
        'arstechnica.com',
        'artstation.com',
        'asana.com',
        'atlassian.com',
        'axios.com',
        'battle.net',
        'bbc.com',
        'behance.net',
        'bestbuy.com',
        'blogger.com',
        'booking.com',
        'buzzfeed.com',
        'canva.com',
        'cnn.com',
        'codecademy.com',
        'constantcontact.com',
        'coursera.org',
        'deviantart.com',
        'discord.com',
        'docusign.com',
        'dribbble.com',
        'dropbox.com',
        'duolingo.com',
        'ebay.com',
        'edx.org',
        'engadget.com',
        'epicgames.com',
        'etsy.com',
        'eurogamer.net',
        'facebook.com',
        'figma.com',
        'flickr.com',
        'forbes.com',
        'framer.com',
        'freecodecamp.org',
        'gamespot.com',
        'gettyimages.com',
        'github.com',
        'gizmodo.com',
        'gog.com',
        'hubspot.com',
        'huffpost.com',
        'humblebundle.com',
        'ign.com',
        'ikea.com',
        'imdb.com',
        'imgur.com',
        'instagram.com',
        'intuit.com',
        'invisionapp.com',
        'itch.io',
        'khanacademy.org',
        'kotaku.com',
        'lifehacker.com',
        'linkedin.com',
        'lynda.com',
        'mailchimp.com',
        'mashable.com',
        'masterclass.com',
        'medium.com',
        'microsoft.com',
        'mozilla.org',
        'msn.com',
        'netflix.com',
        'nytimes.com',
        'origin.com',
        'paypal.com',
        'pcgamer.com',
        'pexels.com',
        'pinterest.com',
        'pixabay.com',
        'pluralsight.com',
        'polygon.com',
        'quora.com',
        'reddit.com',
        'salesforce.com',
        'samsung.com',
        'shutterstock.com',
        'sketch.com',
        'skillshare.com',
        'skype.com',
        'slack.com',
        'soundcloud.com',
        'spotify.com',
        'stackoverflow.com',
        'steamcommunity.com',
        'surveymonkey.com',
        'target.com',
        'techcrunch.com',
        'theguardian.com',
        'theverge.com',
        'tiktok.com',
        'trello.com',
        'tripadvisor.com',
        'tumblr.com',
        'twitch.tv',
        'twitter.com',
        'udemy.com',
        'unsplash.com',
        'Vice.com',
        'vimeo.com',
        'vk.com',
        'vox.com',
        'walmart.com',
        'washingtonpost.com',
        'whatsapp.com',
        'wikimedia.org',
        'wikipedia.org',
        'wired.com',
        'wordpress.com',
        'wsj.com',
        'yahoo.com',
        'yelp.com',
        'youtube.com',
        'zapier.com',
        'zendesk.com',
        'zeplin.io',
        'zoom.us',
        'google.com'
        // Add more trusted websites or domains here
    ];
 
    // Store the current URL
    let currentUrl = window.location.href;
 
    // Store the previous URL
    let previousUrl = currentUrl;
 
    // Flag to track if the script has been activated
    let scriptActivated = false;
 
    // Function to log actions
    function logAction(message) {
        console.log(message);
    }
 
    // Function to check if a website is trusted
    function isTrustedWebsite(url) {
        return trustedWebsites.some(website => url.endsWith(website));
    }
 
    // Function to handle redirection
    function handleRedirect(event) {
        // Check if the URL has changed
        if (window.location.href !== currentUrl && !scriptActivated) {
            // Check if the current website is trusted
            if (isTrustedWebsite(window.location.href)) {
                // Allow the redirect on trusted websites
                previousUrl = currentUrl;
                currentUrl = window.location.href;
                return;
            }
 
            // Set the script activation flag
            scriptActivated = true;
 
            // Stop the redirection
            event.preventDefault();
            event.stopPropagation();
 
            // Push the previous URL into the browser history
            window.history.pushState(null, null, previousUrl);
 
            // Replace the current URL with the previous URL
            window.history.replaceState(null, null, previousUrl);
 
            // Log the action
            logAction('Nefarious redirection stopped. Previous URL loaded.');
        }
    }
 
    // Function to handle forward navigation
    function handleForwardNavigation() {
        // Store the current URL before navigation
        previousUrl = currentUrl;
        currentUrl = window.location.href;
    }
 
    // Function to handle back button navigation
    function handleBackNavigation(event) {
        // Check if the current URL is different from the previous URL
        if (window.location.href !== previousUrl) {
            // Set the script activation flag
            scriptActivated = true;
 
            // Stop the back navigation
            event.preventDefault();
            event.stopPropagation();
 
            // Replace the current URL with the previous URL
            window.history.replaceState(null, null, previousUrl);
 
            // Reload the previous URL
            window.location.href = previousUrl;
 
            // Log the action
            logAction('Back button navigation detected. Previous URL loaded.');
        }
    }
 
    // Function to continuously check for URL changes
    function checkUrlChange() {
        if (window.location.href !== currentUrl && !scriptActivated) {
            // Check if the current website is trusted
            if (isTrustedWebsite(window.location.href)) {
                // Allow the redirect on trusted websites
                previousUrl = currentUrl;
                currentUrl = window.location.href;
                return;
            }
 
            // Set the script activation flag
            scriptActivated = true;
 
            // Push the previous URL into the browser history
            window.history.pushState(null, null, previousUrl);
 
            // Replace the current URL with the previous URL
            window.history.replaceState(null, null, previousUrl);
 
            // Log the action
            logAction('Nefarious redirection stopped. Previous URL loaded.');
        }
 
        // Reset the script activation flag
        scriptActivated = false;
 
        // Schedule the next check
        setTimeout(checkUrlChange, 100);
    }
 
    // Listen for the beforeunload event (forward direction)
    window.addEventListener('beforeunload', handleRedirect);
 
    // Listen for the popstate event (backward direction)
    window.addEventListener('popstate', handleBackNavigation);
 
    // Listen for the click event on links
    document.addEventListener('click', handleForwardNavigation);
 
    // Start checking for URL changes
    checkUrlChange();
})();
