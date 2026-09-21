#ifndef _STDLIB_H
#define _STDLIB_H

#include <stddef.h>

// The kernel is built with `-target-libc-headers`, which tells V that this tree
// declares the C library it may assume. V's runtime calls into the set below, so
// it has to be declared here, with the standard signatures: V generates its own
// prototypes only for functions no header of ours promises.
//
// `malloc`, `calloc`, `realloc`, `free` and `exit` are implemented in V and
// exported under these names. `qsort`, `getenv` and `setenv` are reached only
// from parts of V's runtime the kernel does not use; they are declared so the
// generated C parses, and being unreferenced they never become link errors.

int atoi(const char *text);

void *malloc(size_t size);
void *calloc(size_t nmemb, size_t size);
void *realloc(void *ptr, size_t size);
void free(void *ptr);

void qsort(void *base, size_t nmemb, size_t size,
           int (*compar)(const void *, const void *));

char *getenv(const char *name);
int setenv(const char *name, const char *value, int overwrite);

void exit(int status);
void abort(void);

#endif
