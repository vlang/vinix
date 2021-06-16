#include <stdint.h>
#include <stddef.h>

void free(void *ptr) {
    return memory__free(ptr);
}

void *malloc(size_t size) {
    return memory__malloc(size);
}

void *calloc(size_t num, size_t size) {
    return memory__malloc(num * size);
}

void *realloc(void *ptr, size_t new_size) {
    return memory__realloc(ptr, new_size);
}
