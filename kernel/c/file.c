#include <stdint.h>
#include <stddef.h>
#include <stdarg.h>
#include <stdio.h>

FILE *stdin  = NULL;
FILE *stdout = NULL;
FILE *stderr = NULL;

int fflush(FILE *stream) {
    (void)stream;
    return 0;
}

int getc(FILE *stream) {
    (void)stream;
    lib__kpanic("getc is a stub");
    return -1;
}

char *fgets(char *str, size_t count, FILE *stream) {
    (void)str;
    (void)count;
    (void)stream;
    lib__kpanic("fgets is a stub");
    return NULL;
}

FILE *popen(const char *command, const char *type) {
    (void)command;
    (void)type;
    lib__kpanic("popen is a stub");
    return NULL;
}

int pclose(FILE *stream) {
    (void)stream;
    lib__kpanic("pclose is a stub");
    return -1;
}

ssize_t write(int fd, const void *buf, size_t count) {
    (void)fd;
    (void)buf;
    (void)count;
    if (fd != 1 && fd != 2) {
        lib__kpanic("write to fd != 1 && fd != 2 is a stub");
    }
    kprint__kprint((char *)buf);
    return count;
}

int isatty(int fd) {
    (void)fd;
    return 1;
}
