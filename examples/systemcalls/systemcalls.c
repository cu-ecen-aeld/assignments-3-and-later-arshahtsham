#include <stdlib.h> // For system()
#include <stdbool.h>
#include <stdarg.h>
#include <unistd.h> // For pid_t, fork(), execv(), _exit()
#include <sys/wait.h> // For waitpid(), WIFEXITED(), WEXITSTATUS()
#include <fcntl.h> // For open(), O_WRONLY, O_CREAT, O_TRUNC, dup2(), close()
#include <stdio.h> // For fflush()

bool do_system(const char *cmd) {
    int ret = system(cmd);
    if (ret == -1 || ret != 0) {
        return false;
    }
    return true;
}

bool do_exec(int count, ...) {
    va_list args;
    va_start(args, count);
    char *command[count + 1];
    int i;

    for (i = 0; i < count; i++) {
        command[i] = va_arg(args, char *);
    }
    command[count] = NULL;

    va_end(args);

    // Flush stdout to avoid duplicate prints in forked processes
    fflush(stdout);

    pid_t pid = fork();
    if (pid == -1) {
        return false;
    } else if (pid == 0) {
        // Child process
        execv(command[0], command);
        _exit(EXIT_FAILURE);  // If execv fails
    } else {
        // Parent process
        int status;
        if (waitpid(pid, &status, 0) == -1) {
            return false;
        }
        if (WIFEXITED(status) && WEXITSTATUS(status) == 0) {
            return true;
        }
    }
    return false;
}

bool do_exec_redirect(const char *outputfile, int count, ...) {
    va_list args;
    va_start(args, count);
    char *command[count + 1];
    int i;

    for (i = 0; i < count; i++) {
        command[i] = va_arg(args, char *);
    }
    command[count] = NULL;

    va_end(args);

    // Flush stdout to avoid duplicate prints in forked processes
    fflush(stdout);

    pid_t pid = fork();
    if (pid == -1) {
        return false;
    } else if (pid == 0) {
        // Child process
        int fd = open(outputfile, O_WRONLY | O_CREAT | O_TRUNC, 0644);
        if (fd == -1) {
            _exit(EXIT_FAILURE);
        }
        if (dup2(fd, STDOUT_FILENO) == -1) {
            close(fd);
            _exit(EXIT_FAILURE);
        }
        close(fd);

        execv(command[0], command);
        _exit(EXIT_FAILURE);  // If execv fails
    } else {
        // Parent process
        int status;
        if (waitpid(pid, &status, 0) == -1) {
            return false;
        }
        if (WIFEXITED(status) && WEXITSTATUS(status) == 0) {
            return true;
        }
    }
    return false;
}

