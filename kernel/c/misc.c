#include <stdint.h>
#include <stddef.h>

__attribute__((noreturn)) void lib__kpanic(void *, const char *);

int32_t **__ctype_tolower_loc(void) {
    lib__kpanic(NULL, "__ctype_tolower_loc is a stub");
}

int32_t **__ctype_toupper_loc(void) {
    lib__kpanic(NULL, "__ctype_toupper_loc is a stub");
}
