#include <stdint.h>
#include <stddef.h>
#include <stdarg.h>
#include <stdio.h>

typedef long ssize_t;

FILE *stdin  = NULL;
FILE *stdout = NULL;
FILE *stderr = NULL;

int fflush(FILE *stream) {
    (void)stream;
    return 0;
}

int getc(FILE *stream) {
    (void)stream;
    kpanic("getc is a stub");
    return -1;
}

char *fgets(char *str, size_t count, FILE *stream) {
    (void)str;
    (void)count;
    (void)stream;
    kpanic("fgets is a stub");
    return NULL;
}

FILE *popen(const char *command, const char *type) {
    (void)command;
    (void)type;
    kpanic("popen is a stub");
    return NULL;
}

int pclose(FILE *stream) {
    (void)stream;
    kpanic("pclose is a stub");
    return -1;
}

ssize_t write(int fd, const void *buf, size_t count) {
    (void)fd;
    (void)buf;
    (void)count;
    if (fd != 1 && fd != 2) {
        kpanic("write to fd != 1 || fd != 2 is a stub");
    }
    kprint(buf, count);
    return 0;
}

int isatty(int fd) {
    (void)fd;
    kpanic("isatty is a stub");
    return -1;
}
