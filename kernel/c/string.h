#ifndef _STRING_H
#define _STRING_H

#include <stddef.h>

// The memory and string routines are implemented in V, in lib/stubs, and
// exported under these names. V has no `const`, so these prototypes describe the
// definitions rather than the C standard's spelling: a qualifier the definition
// does not carry would be a conflicting declaration under
// `-target-libc-headers`, where V emits its own prototype for them too.

// Keep const-correct declarations for handwritten C and third-party callers.
// Only the generated V translation unit needs the unqualified definitions.
#ifdef VINIX_V_RUNTIME
void *memcpy(void *restrict dest, void *restrict src, size_t n);
void *memmove(void *dest, void *src, size_t n);
int memcmp(void *s1, void *s2, size_t n);
#else
void *memcpy(void *restrict dest, const void *restrict src, size_t n);
void *memmove(void *dest, const void *src, size_t n);
int memcmp(const void *s1, const void *s2, size_t n);
#endif
void *memset(void *s, int c, size_t n);
char *strcpy(char *dest, char *src);
int strcmp(char *s1, char *s2);
int strncmp(char *s1, char *s2, size_t n);
size_t strlen(char *s);

#endif
