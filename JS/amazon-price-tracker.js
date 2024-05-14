// ==UserScript==
// @name            Amazon CamelCamelCamel + Keepa Price Charts
// @version         1.0
// @description     Add CamelCamelCamel and Keepa price charts to Amazon product pages with optimized resource usage.
// @author          miki.it
// @namespace       null
// @homepage        url
// @match           https://www.amazon.com/*
// @run-at          document-idle
// @grant           none
// ==/UserScript==

(function() {
    'use strict';

    const getASIN = () => {
        const asinElement = document.getElementById("ASIN") || document.querySelector('[name="ASIN"]');
        return asinElement ? asinElement.value : console.error("Unable to find ASIN on the page.");
    };

    const createChartContainer = (url, imgUrl, width, height) => {
        const link = document.createElement("a");
        link.href = url;
        link.target = "_blank";

        const img = document.createElement("img");
        img.src = imgUrl;
        img.width = width;
        img.height = height;
        link.appendChild(img);

        const container = document.createElement("div");
        container.appendChild(link);
        return container;
    };

    const insertPriceCharts = (asin, country) => {
        const parentElement = document.getElementById("unifiedPrice_feature_div") || document.getElementById("MediaMatrix");
        if (!parentElement) {
            return console.error("Unable to find a suitable parent element for inserting the price charts.");
        }

        const camelUrl = `https://${country}.camelcamelcamel.com/product/${asin}`;
        const camelImgUrl = `https://charts.camelcamelcamel.com/${country}/${asin}/amazon-new-used.png?force=1&zero=0&w=500&h=320&desired=false&legend=1&ilt=1&tp=all&fo=0`;
        const keepaUrl = `https://keepa.com/#!product/5-${asin}`;
        const keepaImgUrl = `https://graph.keepa.com/pricehistory.png?asin=${asin}&domain=${country}`;

        parentElement.appendChild(createChartContainer(camelUrl, camelImgUrl, 500, 320));
        parentElement.appendChild(createChartContainer(keepaUrl, keepaImgUrl, 500, 200));
    };

    const asin = getASIN();
    if (asin) {
        const country = document.location.hostname.split('.').slice(-1)[0] === "com" ? "us" : "de";
        insertPriceCharts(asin, country);
    }
})();
