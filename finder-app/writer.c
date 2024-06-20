#include <stdio.h>
#include <stdlib.h>
#include <syslog.h>
#include <errno.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>

void usage(const char *progname) {
    fprintf(stderr, "Usage: %s <file> <string>\n", progname);
}

int main(int argc, char *argv[]) {
    if (argc != 3) {
        usage(argv[0]);
        return EXIT_FAILURE;
    }

    const char *filename = argv[1];
    const char *string = argv[2];

    // Open syslog
    openlog("writer", LOG_PID | LOG_CONS, LOG_USER);

    // Create the directory if it doesn't exist
    char *dir = strdup(filename);
    if (dir == NULL) {
        syslog(LOG_ERR, "Failed to allocate memory");
        return EXIT_FAILURE;
    }
    char *last_slash = strrchr(dir, '/');
    if (last_slash != NULL) {
        *last_slash = '\0';
        if (mkdir(dir, 0755) == -1 && errno != EEXIST) {
            syslog(LOG_ERR, "Failed to create directory %s: %s", dir, strerror(errno));
            free(dir);
            return EXIT_FAILURE;
        }
    }
    free(dir);

    FILE *file = fopen(filename, "w");
    if (!file) {
        syslog(LOG_ERR, "Failed to open file %s: %s", filename, strerror(errno));
        perror("fopen");
        return EXIT_FAILURE;
    }

    if (fprintf(file, "%s", string) < 0) {
        syslog(LOG_ERR, "Failed to write to file %s: %s", filename, strerror(errno));
        perror("fprintf");
        fclose(file);
        return EXIT_FAILURE;
    }
    fclose(file);

    syslog(LOG_DEBUG, "Writing %s to %s", string, filename);

    // Close syslog
    closelog();

    printf("Successfully wrote to %s\n", filename);
    return EXIT_SUCCESS;
}

