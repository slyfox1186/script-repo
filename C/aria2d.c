#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <pthread.h>
#include <unistd.h>
#include <sys/wait.h>
#include <regex.h>

#define MAX_DOWNLOADS 10
#define MAX_CMD_ARGS 20

// To compile and move execute the below command.
// gcc -O2 -pipe -march=native aria2d1.c -o aria2d -lpthread; sudo mv aria2d /usr/local/bin

typedef struct {
    char *filename;
    char *url;
} DownloadArgs;

int validate_input(const char *filename, const char *url) {
    regex_t regex;
    int reti;

    // Simple regex to validate the filename (basic example, adjust as needed)
    reti = regcomp(&regex, "^[a-zA-Z0-9._-]+$", REG_EXTENDED);
    if (reti) {
        fprintf(stderr, "Could not compile regex\n");
        return 0;
    }

    // Validate filename
    reti = regexec(&regex, filename, 0, NULL, 0);
    if (reti == REG_NOMATCH) {
        printf("Invalid filename: %s\n", filename);
        regfree(&regex);
        return 0;
    }

    // Simple URL validation (very basic, consider improving for real use cases)
    reti = regcomp(&regex, "^https?://", REG_EXTENDED | REG_NOSUB);
    if (reti) {
        fprintf(stderr, "Could not compile regex\n");
        return 0;
    }

    // Validate URL
    reti = regexec(&regex, url, 0, NULL, 0);
    if (reti == REG_NOMATCH) {
        printf("Invalid URL: %s\n", url);
        regfree(&regex);
        return 0;
    }

    regfree(&regex);
    return 1;
}

void *download_file(void *arguments) {
    DownloadArgs *args = (DownloadArgs *)arguments;
    pid_t pid;
    int status;

    if (!validate_input(args->filename, args->url)) {
        pthread_exit((void *)1); // Exit with error code if validation fails
    }

    char *cmd[MAX_CMD_ARGS] = {
        "aria2c",
        "--max-connection-per-server=16",
        "--max-concurrent-downloads=5",
        "--split=10",
        "--min-split-size=5M",
        "--disk-cache=256M",
        "--file-allocation=none",
        "--out", args->filename,
        args->url,
        NULL
    };

    pid = fork();
    if (pid == 0) { // Child process
        execvp(cmd[0], cmd);
        // If execvp returns, it must have failed.
        printf("Failed to start aria2c for %s\n", args->filename);
        exit(EXIT_FAILURE);
    } else if (pid > 0) { // Parent process
        waitpid(pid, &status, 0);
        if (status == 0) {
            printf("%s download complete.\n", args->filename);
        } else {
            printf("Download failed for %s.\n", args->filename);
        }
    } else {
        // Fork failed
        perror("fork");
        exit(EXIT_FAILURE);
    }

    pthread_exit(NULL);
}

int main(int argc, char *argv[]) {
    if (argc < 3 || argc % 2 != 1) {
        printf("Usage: %s [filename url]...\n", argv[0]);
        return 1;
    }

    int pairsCount = (argc - 1) / 2;
    pthread_t threads[pairsCount];
    DownloadArgs args[pairsCount];
    void *thread_result;
    int validation_failure = 0;

    for (int i = 0; i < pairsCount; i++) {
        args[i].filename = argv[2 * i + 1];
        args[i].url = argv[2 * i + 2];
        if (pthread_create(&threads[i], NULL, download_file, (void *)&args[i]) != 0) {
            perror("Failed to create thread");
            return 1;
        }
    }

    for (int i = 0; i < pairsCount; i++) {
        pthread_join(threads[i], &thread_result);
        if (thread_result != NULL) {
            validation_failure = 1;
        }
    }

    if (validation_failure) {
        printf("One or more downloads were not initiated due to validation failure.\n");
    } else {
        printf("All downloads have been completed.\n");
    }

    return 0;
}
