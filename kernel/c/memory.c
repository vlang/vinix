#include <stdint.h>
#include <stddef.h>

void free(void* ptr) {
    (void)ptr;
    return;
}

void* malloc(size_t size) {
    (void)size;
    return NULL;
}

void* calloc(size_t num, size_t size) {
    (void)num;
    (void)size;
    return NULL;
}

void *realloc(void *ptr, size_t new_size) {
    (void)ptr;
    (void)new_size;
    return NULL;
}
