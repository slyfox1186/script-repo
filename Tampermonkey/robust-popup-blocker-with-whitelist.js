// ==UserScript==
// @name         Refined Popup Blocker
// @namespace    http://tampermonkey.net/
// @version      2.7.2
// @description  Blocks only the intrusive popups while allowing normal operations on legitimate links.
// @author       Your Name
// @match        *://*/*
// @grant        none
// @run-at       document-start
// @license      MIT
// ==/UserScript==
 
(function () {
	'use strict';
 
	// Whitelist of trusted domains
	const trustedWebsites = [
		'500px.com', 'accuweather.com', 'adobe.com', 'adulttime.com', 'alibaba.com', 'amazon.com',
		'amazonaws.com', 'amd.com', 'americanexpress.com', 'anaconda.com', 'angular.io', 'ap.org',
		'apache.org', 'apnews.com', 'apple.com', 'arstechnica.com', 'artstation.com', 'asana.com',
		'asus.com', 'atlassian.com', 'autodesk.com', 'axios.com', 'battle.net', 'bbc.co.uk', 'bbc.com',
		'behance.net', 'bestbuy.com', 'bing.com', 'bitbucket.org', 'blogger.com', 'bloomberg.com',
		'bmw.com', 'boeing.com', 'booking.co.uk', 'booking.com', 'bootstrapcdn.com', 'breitbart.com',
		'buzzfeed.com', 'canva.com', 'capitalone.com', 'cbsnews.com', 'character.ai', 'chase.com',
		'chaturbate.com', 'cisco.com', 'citi.com', 'cnbc.com', 'cnet.com', 'cnn.com', 'codecademy.com',
		'constantcontact.com', 'coursera.org', 'craigslist.org', 'dailymail.co.uk', 'dell.com',
		'deviantart.com', 'discord.com', 'disney.com', 'django.com', 'docker.com', 'docusign.com',
		'dribbble.com', 'dropbox.com', 'duckduckgo.com', 'duolingo.com', 'duosecurity.com', 'ebay.com',
		'economist.com', 'edx.org', 'elsevier.com', 'engadget.com', 'epicgames.com', 'eporner.com',
		'espn.com', 'etsy.com', 'eurogamer.net', 'expedia.com', 'facebook.com', 'fandom.com', 'fedex.com',
		'figma.com', 'finance.yahoo.com', 'flickr.com', 'flipkart.com', 'forbes.com', 'foxnews.com',
		'framer.com', 'freecodecamp.org', 'gamespot.com', 'gartner.com', 'gettyimages.com', 'git-scm.com',
		'github.com', 'gizmodo.com', 'go.com', 'godaddy.com', 'gog.com', 'goldmansachs.com', 'google.com',
		'healthline.com', 'hilton.com', 'homedepot.com', 'hp.com', 'hubspot.com', 'huffpost.com',
		'hulu.com', 'humblebundle.com', 'ibm.com', 'ieee.org', 'ifixit.com', 'ign.com', 'ikea.com',
		'imdb.com', 'imgur.com', 'indeed.com', 'instagram.com', 'instructure.com', 'intel.com',
		'intuit.com', 'invisionapp.com', 'itch.io', 'java.com', 'jetbrains.com', 'joomla.org',
		'jquery.com', 'khanacademy.org', 'kotaku.com', 'kotlinlang.org', 'laravel.com', 'lenovo.com',
		'lg.com', 'lifehacker.com', 'linkedin.com', 'live.com', 'lowes.com', 'lynda.com', 'macys.com',
		'mailchimp.com', 'marriott.com', 'mashable.com', 'masterclass.com', 'mcdonalds.com', 'medium.com',
		'mercedes-benz.com', 'microsoft.com', 'microsoftonline.com', 'mit.edu', 'mongodb.com', 'moodle.org',
		'mozilla.org', 'msn.com', 'msnbc.com', 'nasa.gov', 'nationalgeographic.com', 'nbc.com', 'nbcnews.com',
		'netflix.com', 'nextdoor.com', 'nih.gov', 'npr.org', 'nvidia.com', 'nypost.com', 'nytimes.com',
		'office.com', 'okta.com', 'onlyfans.com', 'openai.com', 'oracle.com', 'oreilly.com', 'origin.com',
		'outlook.com', 'overstock.com', 'patreon.com', 'paypal.com', 'pcgamer.com', 'pexels.com', 'php.net',
		'pinterest.com', 'pixabay.com', 'pluralsight.com', 'polygon.com', 'pornhub.com', 'python.org',
		'quizlet.com', 'quora.com', 'reactjs.org', 'realtor.com', 'reddit.com', 'redhat.com', 'roblox.com',
		'rubyonrails.org', 'salesforce.com', 'samsung.co.kr', 'samsung.com', 'sap.com', 'sciencedirect.com',
		'scopus.com', 'sears.com', 'sharepoint.com', 'shutterstock.com', 'siemens.com', 'sketch.com',
		'skillshare.com', 'skype.com', 'slack.com', 'sony.com', 'soundcloud.com', 'spotify.com', 'spring.io',
		'stackoverflow.com', 'steamcommunity.com', 'steampowered.com', 'surveymonkey.com', 'symantec.com',
		'target.com', 'techcrunch.com', 'temu.com', 'tesla.com', 'texasinstruments.com', 'theguardian.com',
		'thenextweb.com', 'theverge.com', 'tiktok.com', 'time.com', 'toyota.com', 'trello.com', 'trip.com',
		'tripadvisor.com', 'tumblr.com', 'twitch.tv', 'twitter.com', 'uber.com', 'ucla.edu', 'ucsf.edu',
		'udemy.com', 'unity.com', 'unsplash.com', 'ups.com', 'usatoday.com', 'usnews.com', 'usps.com',
		'verizon.com', 'vice.com', 'Vice.com', 'vimeo.com', 'vk.com', 'vmware.com', 'volkswagen.com', 'vox.com',
		'walmart.com', 'washingtonpost.com', 'weather.com', 'weather.gov', 'webmd.com', 'whatsapp.com',
		'wikimedia.org', 'wikipedia.org', 'wired.com', 'wordpress.com', 'wsj.com', 'wunderground.com', 'x.com',
		'xerox.com', 'xfinity.com', 'xhamster.com', 'xilinx.com', 'xnxx.com', 'xvideos.com', 'yahoo.com',
		'yelp.com', 'youtube.com', 'zapier.com', 'zendesk.com', 'zeplin.io', 'zillow.com', 'zoom.us', 'new.reddit.com'
	];
 
	console.log('Trusted websites loaded:', trustedWebsites);
 
	function isWhitelisted(url) {
		try {
			const parsedUrl = new URL(url);
			const hostname = parsedUrl.hostname;
			const isWhitelisted = trustedWebsites.some(domain => hostname.endsWith(domain));
			console.log(`URL check: ${url} is ${isWhitelisted ? '' : 'not '}whitelisted.`);
			return isWhitelisted;
		} catch (e) {
			console.error('Error checking whitelist:', e);
			return false;
		}
	}
 
	// Override window.open to block popups unless whitelisted
	const originalOpen = window.open;
	window.open = function (url, name, features) {
		console.log(`Attempting to open window with URL: ${url}`);
		// Check if the URL is 'null' or does not pass the whitelist check
		if (url === null || url === 'about:blank' || !isWhitelisted(url)) {
			console.log('Blocked popup from:', url);
			return null; // Block the popup
		}
		console.log('Allowed popup for:', url);
		return originalOpen.call(this, url, name, features); // Allow legitimate popups
	};
 
	// Enhanced event handlers to prevent default actions only for non-whitelisted popups
	document.addEventListener('click', function (event) {
		console.log('Click event detected.');
		let target = event.target;
		while (target && target.tagName !== 'A') {
			target = target.parentNode;
		}
		if (target && target.tagName === 'A' && target.getAttribute('target') === '_blank') {
			const href = target.getAttribute('href');
			console.log(`Checking link for blocking: ${href}`);
			if (href && !isWhitelisted(href) && href.includes('ad') && !href.includes('track/click')) {
				event.preventDefault();
				console.log('Blocked popup triggered by target="_blank" with href:', href);
			}
		}
	}, true);
 
	// MutationObserver for dynamic content
	const observer = new MutationObserver(function (mutations) {
		console.log('Mutation observed.');
		mutations.forEach(function (mutation) {
			if (mutation.type === 'childList') {
				mutation.addedNodes.forEach(function (node) {
					if (node.tagName === 'IFRAME') {
						console.log(`Iframe detected with source: ${node.getAttribute('src')}`);
						if (node.getAttribute('src') && !isWhitelisted(node.getAttribute('src')) && node.getAttribute('src').includes('ad')) {
							console.log('Blocked popup triggered by dynamic iframe with src:', node.getAttribute('src'));
							node.setAttribute('src', 'about:blank');
						}
					}
				});
			}
		});
	});
 
	// Configuration of the observer:
	const config = {
		childList: true,
		subtree: true
	};
	observer.observe(document.body, config);
 
	console.log('Refined Popup Blocker initialized with verbose logging.');
})();
