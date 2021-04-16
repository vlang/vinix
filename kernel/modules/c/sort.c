#include <stddef.h>

void qsort(void *ptr, size_t count, size_t size, int (*comp)(const void *, const void *)) {
    (void)ptr;
    (void)count;
    (void)size;
    (void)comp;
    kpanic("qsort is a stub");
}
