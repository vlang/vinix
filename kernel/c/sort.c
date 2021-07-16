#include <stddef.h>

__attribute__((noreturn)) void lib__kpanic(const char *);

void qsort(void *ptr, size_t count, size_t size, int (*comp)(const void *, const void *)) {
    (void)ptr;
    (void)count;
    (void)size;
    (void)comp;
    lib__kpanic("qsort is a stub");
}
