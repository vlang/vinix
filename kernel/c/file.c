#include <stdint.h>
#include <stddef.h>
#include <stdarg.h>
#include <stdio.h>

__attribute__((noreturn)) void lib__kpanic(void *, const char *);
void kprint__kprint(const char *);

FILE *stdin  = NULL;
FILE *stdout = NULL;
FILE *stderr = NULL;

int fflush(FILE *stream) {
    (void)stream;
    return 0;
}

int getchar(void) {
    lib__kpanic(NULL, "getchar is a stub");
}

int getc(FILE *stream) {
    (void)stream;
    lib__kpanic(NULL, "getc is a stub");
}

char *fgets(char *str, size_t count, FILE *stream) {
    (void)str;
    (void)count;
    (void)stream;
    lib__kpanic(NULL, "fgets is a stub");
}

FILE *popen(const char *command, const char *type) {
    (void)command;
    (void)type;
    lib__kpanic(NULL, "popen is a stub");
}

int pclose(FILE *stream) {
    (void)stream;
    lib__kpanic(NULL, "pclose is a stub");
}

ssize_t write(int fd, const void *buf, size_t count) {
    (void)fd;
    (void)buf;
    (void)count;
    if (fd != 1 && fd != 2) {
        lib__kpanic(NULL, "write to fd != 1 && fd != 2 is a stub");
    }
    kprint__kprint((char *)buf);
    return count;
}

int isatty(int fd) {
    (void)fd;
    return 1;
}
