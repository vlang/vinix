#include <stdint.h>
#include <stddef.h>
#include <stdarg.h>
#include <stdio.h>

__attribute__((noreturn)) void lib__kpanic(const char *);
void kprint__kprint(const char *);

FILE *stdin  = NULL;
FILE *stdout = NULL;
FILE *stderr = NULL;

int fflush(FILE *stream) {
    (void)stream;
    return 0;
}

int getchar(void) {
    lib__kpanic("getchar is a stub");
}

int getc(FILE *stream) {
    (void)stream;
    lib__kpanic("getc is a stub");
}

char *fgets(char *str, size_t count, FILE *stream) {
    (void)str;
    (void)count;
    (void)stream;
    lib__kpanic("fgets is a stub");
}

FILE *popen(const char *command, const char *type) {
    (void)command;
    (void)type;
    lib__kpanic("popen is a stub");
}

int pclose(FILE *stream) {
    (void)stream;
    lib__kpanic("pclose is a stub");
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
