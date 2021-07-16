#include <stdint.h>
#include <stddef.h>
#include <stdlib.h>

void memory__free(void *);
void *memory__malloc(size_t);
void *memory__realloc(void *, size_t);

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
