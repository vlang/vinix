#include <stdint.h>
#include <stddef.h>

void  memory__free(void *ptr);
void *memory__malloc(size_t size);
void *memory__realloc(void *ptr, size_t new_size);

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
