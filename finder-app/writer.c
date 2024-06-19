#include <stdio.h>
#include <stdlib.h>
#include <syslog.h>
#include <errno.h>
#include <string.h>

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

    FILE *file = fopen(filename, "w");
    if (!file) {
        syslog(LOG_ERR, "Failed to open file %s: %s", filename, strerror(errno));
        perror("fopen");
        return EXIT_FAILURE;
    }

    fprintf(file, "%s", string);
    fclose(file);

    syslog(LOG_DEBUG, "Writing %s to %s", string, filename);

    // Close syslog
    closelog();

    return EXIT_SUCCESS;
}

