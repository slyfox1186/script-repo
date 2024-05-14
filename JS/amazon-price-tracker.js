// ==UserScript==
// @name            Amazon Price Charts
// @version         1.0
// @description     Efficiently add CamelCamelCamel and Keepa price charts to Amazon product pages.
// @author          miki.it
// @namespace       null
// @homepage        url
// @match           https://www.amazon.com/*
// @run-at          document-idle
// @grant           none
// ==/UserScript==

(function() {
    'use strict';

    // Utilize memoization to avoid redundant DOM access
    const memoize = (fn) => {
        const cache = new Map();
        return function(...args) {
            const key = JSON.stringify(args);
            if (cache.has(key)) return cache.get(key);
            const result = fn.apply(this, args);
            cache.set(key, result);
            return result;
        };
    };

    // Efficiently fetch ASIN from page with memoization
    const getASIN = memoize(() => {
        const asinElement = document.getElementById("ASIN") || document.querySelector('input[name="ASIN"]');
        if (!asinElement) {
            console.error("Unable to find ASIN on the page.");
            return null;
        }
        return asinElement.value;
    });

    // Create chart container with minimal overhead
    const createChartContainer = (url, imgUrl, width, height) => {
        const link = document.createElement("a");
        link.href = url;
        link.target = "_blank";
        link.rel = "noopener noreferrer"; // Security measure

        const img = new Image(width, height);
        img.src = imgUrl;
        img.loading = "lazy"; // Utilize lazy loading

        link.appendChild(img);
        return link;
    };

    // Efficient insertion of price charts
    const insertPriceCharts = (asin, country) => {
        const parentElement = document.getElementById("unifiedPrice_feature_div") || document.querySelector("#MediaMatrix");
        if (!parentElement) {
            return console.error("Unable to find a suitable parent element for inserting the price charts.");
        }

        const camelUrl = `https://${country}.camelcamelcamel.com/product/${asin}`;
        const camelImgUrl = `https://charts.camelcamelcamel.com/${country}/${asin}/amazon-new-used.png?force=1&zero=0&w=500&h=320&desired=false&legend=1&ilt=1&tp=all&fo=0`;
        const keepaUrl = `https://keepa.com/#!product/5-${asin}`;
        const keepaImgUrl = `https://graph.keepa.com/pricehistory.png?asin=${asin}&domain=${country}`;

        const chartsContainer = document.createElement("div");
        chartsContainer.appendChild(createChartContainer(camelUrl, camelImgUrl, 500, 320));
        chartsContainer.appendChild(createChartContainer(keepaUrl, keepaImgUrl, 500, 200));
        parentElement.appendChild(chartsContainer);
    };

    // Main execution with optimized logic
    const asin = getASIN();
    if (asin) {
        const country = document.location.hostname.endsWith(".com") ? "us" : "de";
        insertPriceCharts(asin, country);
    }
})();
