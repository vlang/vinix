#include <stdint.h>
#include <stddef.h>
#include <stdarg.h>

void *memcpy(void *dest, const void *src, size_t n) {
    uint8_t *pdest = (uint8_t *)dest;
    const uint8_t *psrc = (const uint8_t *)src;

    for (size_t i = 0; i < n; i++) {
        pdest[i] = psrc[i];
    }

    return dest;
}

void *memset(void *s, int c, size_t n) {
    uint8_t *p = (uint8_t *)s;

    for (size_t i = 0; i < n; i++) {
        p[i] = (uint8_t)c;
    }

    return s;
}

void *memmove(void *dest, const void *src, size_t n) {
    uint8_t *pdest = (uint8_t *)dest;
    const uint8_t *psrc = (const uint8_t *)src;

    if (src > dest) {
        for (size_t i = 0; i < n; i++) {
            pdest[i] = psrc[i];
        }
    } else if (src < dest) {
        for (size_t i = n; i > 0; i--) {
            pdest[i-1] = psrc[i-1];
        }
    }

    return dest;
}

int memcmp(const void *s1, const void *s2, size_t n) {
    const uint8_t *p1 = (const uint8_t *)s1;
    const uint8_t *p2 = (const uint8_t *)s2;

    for (size_t i = 0; i < n; i++) {
        if (p1[i] != p2[i])
            return p1[i] < p2[i] ? -1 : 1;
    }

    return 0;
}

char *strcpy(char *dest, const char *src) {
    size_t i;

    for (i = 0; src[i]; i++)
        dest[i] = src[i];

    dest[i] = 0;

    return dest;
}

char *strncpy(char *dest, const char *src, size_t n) {
    size_t i;

    for (i = 0; i < n && src[i]; i++)
        dest[i] = src[i];
    for ( ; i < n; i++)
        dest[i] = 0;

    return dest;
}

int strcmp(const char *s1, const char *s2) {
    for (size_t i = 0; ; i++) {
        char c1 = s1[i], c2 = s2[i];
        if (c1 != c2)
            return c1 - c2;
        if (!c1)
            return 0;
    }
}

int strncmp(const char *s1, const char *s2, size_t n) {
    for (size_t i = 0; i < n; i++) {
        char c1 = s1[i], c2 = s2[i];
        if (c1 != c2)
            return c1 - c2;
        if (!c1)
            return 0;
    }

    return 0;
}

size_t strlen(const char *str) {
    size_t len;

    for (len = 0; str[len]; len++);

    return len;
}

void free( void* ptr ) {}
void* malloc( size_t size ) {}
void* calloc( size_t num, size_t size ) {}
void *realloc( void *ptr, size_t new_size ) {}

void exit( int exit_code ) {}

typedef struct {

} FILE;

FILE *stdin, *stdout, *stderr;

int printf( const char *format, ... ) {}
int vsprintf( char *buffer, const char *format, va_list vlist ) {}
int vsnprintf( char *restrict buffer, size_t bufsz,
               const char *restrict format, va_list vlist ) {}
int fflush( FILE *stream ) {}
int getc( FILE *stream ) {}
char *fgets( char *str, int count, FILE *stream ) {}

void qsort( void *ptr, size_t count, size_t size,
            int (*comp)(const void *, const void *) ) {}

typedef signed long long ssize_t;
ssize_t write(int fd, const void *buf, size_t count) {}
int isatty(int fd) {}

FILE *popen(const char *command, const char *type) {}
int pclose(FILE *stream) {}

void *backtrace_symbols, *backtrace;

int32_t **__ctype_tolower_loc(void) {}
int32_t **__ctype_toupper_loc(void) {}
