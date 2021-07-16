#include <stdlib.h>

__attribute__((noreturn)) void lib__kpanic(const char *);

__attribute__((noreturn)) void exit(int exit_code) {
    (void)exit_code;
    lib__kpanic("Kernel has called exit()");
    __builtin_unreachable();
}
