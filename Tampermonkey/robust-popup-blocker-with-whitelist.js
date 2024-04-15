// ==UserScript==
// @name         Robust Popup Blocker with Whitelist
// @namespace    http://tampermonkey.net/
// @version      1.0
// @description  Blocks all popups unless they originate from a whitelisted domain, with enhanced handling.
// @author       Your Name
// @match        *://*/*
// @grant        none
// @run-at       document-start
// @license      MIT
// ==/UserScript==

(function() {
    'use strict';

    // List of trusted websites or domains where redirects are allowed
    const whitelist = [
        '500px.com',
        'adobe.com',
        'amazon.com',
        'apple.com',
        'archlinux.org',
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
        'somegit.dev',
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
        'google.com',
        'wiki.archlinux.org'
        // Add more trusted websites or domains here
    ];

    function isWhitelisted(url) {
        try {
            const hostname = new URL(url).hostname;
            return whitelist.some(domain => hostname === domain || hostname.endsWith('.' + domain));
        } catch (e) {
            console.error('Error checking whitelist:', e);
            return false;
        }
    }

    const originalOpen = window.open;
    window.open = function(url, name, features) {
        if (!url || isWhitelisted(url)) {
            return originalOpen.call(this, url, name, features);
        } else {
            console.log('Blocked popup from:', url);
            return null;
        }
    };

    // Disable other known methods to open a window
    window.alert = window.confirm = window.prompt = function() {
        console.log('Blocked suspicious popup interaction');
        return null;
    };

    // Observe and handle inline event triggers
    document.addEventListener('DOMContentLoaded', () => {
        const allElements = document.querySelectorAll('body *');
        allElements.forEach(el => {
            const isInlinePopup = el.getAttribute('onclick')?.includes('window.open');
            if (isInlinePopup) {
                el.removeAttribute('onclick');
                console.log('Removed inline popup trigger from element:', el);
            }
        });
    });

    console.log('Popup blocker initialized.');
})();
