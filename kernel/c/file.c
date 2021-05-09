#include <stdint.h>
#include <stddef.h>
#include <stdarg.h>
#include <stdio.h>

void lib__kpanicc(char *message);
void lib__kprintc(char *str);

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
    lib__kpanicc("getc is a stub");
    return -1;
}

char *fgets(char *str, size_t count, FILE *stream) {
    (void)str;
    (void)count;
    (void)stream;
    lib__kpanicc("fgets is a stub");
    return NULL;
}

FILE *popen(const char *command, const char *type) {
    (void)command;
    (void)type;
    lib__kpanicc("popen is a stub");
    return NULL;
}

int pclose(FILE *stream) {
    (void)stream;
    lib__kpanicc("pclose is a stub");
    return -1;
}

ssize_t write(int fd, const void *buf, size_t count) {
    (void)fd;
    (void)buf;
    (void)count;
    if (fd != 1 && fd != 2) {
        lib__kpanicc("write to fd != 1 || fd != 2 is a stub");
    }
    lib__kprintc((char *)buf);
    return 0;
}

int isatty(int fd) {
    (void)fd;
    return 1;
}
