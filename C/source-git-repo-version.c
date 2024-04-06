#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <curl/curl.h>
#include <ctype.h>
#include <regex.h>

struct MemoryStruct {
    char *memory;
    size_t size;
};

static size_t WriteMemoryCallback(void *contents, size_t size, size_t nmemb, struct MemoryStruct *userp) {
    size_t realsize = size * nmemb;
    char *ptr = realloc(userp->memory, userp->size + realsize + 1);
    if(ptr == NULL) {
        fprintf(stderr, "Not enough memory\n");
        return 0;
    }
    userp->memory = ptr;
    memcpy(&(userp->memory[userp->size]), contents, realsize);
    userp->size += realsize;
    userp->memory[userp->size] = 0; // Null-terminate the string
    return realsize;
}

void find_version(const char *html) {
    regex_t regex;
    regmatch_t matches[2]; // Increase to 2 to capture the first subgroup
    int ret;

    // Adjusted regex to include a capture group for the version number
    char *pattern = "\\/[a-z.-]*([0-9]+\\.[0-9]+\\.[0-9]+[a-zA-Z0-9.-]*)";

    // Compile regex
    if (regcomp(&regex, pattern, REG_EXTENDED)) {
        fprintf(stderr, "Could not compile regex\n");
        return;
    }

    // Execute regex
    ret = regexec(&regex, html, 2, matches, 0);
    if (!ret) {
        // Check for at least one capture group
        if (matches[1].rm_so != -1) {
            // Match found for the capture group
            int match_length = matches[1].rm_eo - matches[1].rm_so;
            char matched[match_length + 1]; // +1 for null terminator
            memcpy(matched, &html[matches[1].rm_so], match_length);
            matched[match_length] = '\0'; // Null-terminate the string
            printf("%s\n", matched);
        } else {
            printf("No version capture group found\n");
        }
    } else if (ret == REG_NOMATCH) {
        printf("No version found\n");
    } else {
        // Error occurred
        char errorMessage[100];
        regerror(ret, &regex, errorMessage, sizeof(errorMessage));
        fprintf(stderr, "Regex match failed: %s\n", errorMessage);
    }

    // Free compiled regex
    regfree(&regex);
}


int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "Usage: %s <GitHub repo URL>\n", argv[0]);
        return 1;
    }

    CURL *curl;
    CURLcode res;
    struct MemoryStruct chunk = {0};

    chunk.memory = malloc(1);
    chunk.size = 0;

    curl_global_init(CURL_GLOBAL_ALL);
    curl = curl_easy_init();
    if(curl) {
        curl_easy_setopt(curl, CURLOPT_URL, argv[1]);
        curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, WriteMemoryCallback);
        curl_easy_setopt(curl, CURLOPT_WRITEDATA, (void *)&chunk);
        curl_easy_setopt(curl, CURLOPT_FOLLOWLOCATION, 1L);

        res = curl_easy_perform(curl);
        if(res != CURLE_OK) {
            fprintf(stderr, "curl_easy_perform() failed: %s\n", curl_easy_strerror(res));
        } else {
            find_version(chunk.memory);
        }
        curl_easy_cleanup(curl);
        free(chunk.memory);
    }
    curl_global_cleanup();

    return 0;
}
