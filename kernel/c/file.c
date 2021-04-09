#include <stdint.h>
#include <stddef.h>
#include <stdarg.h>

typedef signed long long ssize_t;

typedef struct {
    int unused;
} FILE;

FILE *stdin  = NULL;
FILE *stdout = NULL;
FILE *stderr = NULL;

int fflush(FILE *stream) {
    (void)stream;
    return -1;
}

int getc(FILE *stream) {
    (void)stream;
    return -1;
}

char *fgets(char *str, int count, FILE *stream) {
    (void)str;
    (void)count;
    (void)stream;
    return NULL;
}

FILE *popen(const char *command, const char *type) {
    (void)command;
    (void)type;
    return NULL;
}

int pclose(FILE *stream) {
    (void)stream;
    return -1;
}

ssize_t write(int fd, const void *buf, size_t count) {
    (void)fd;
    (void)buf;
    (void)count;
    return -1;
}

int isatty(int fd) {
    (void)fd;
    return -1;
}
