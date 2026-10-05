// SPDX-License-Identifier: GPL-2.0-or-later
// Run on stock ARM64 musl with the actual Android compatibility preload.
#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

struct android_mallinfo {
    size_t arena, ordblks, smblks, hblks, hblkhd;
    size_t usmblks, fsmblks, uordblks, fordblks, keepcost;
};

int main(int argc, char **argv)
{
    struct android_mallinfo (*query)(void) = dlsym(RTLD_DEFAULT, "bionic_mallinfo");
    if (!query || dlsym(RTLD_DEFAULT, "__vinix_malloc_stats") != NULL) {
        fputs("fixture requires Android preload with stock host musl\n", stderr);
        return 1;
    }
    if (argc == 2 && strcmp(argv[1], "--missing-provider") == 0) {
        // This call must abort, rather than return invented allocator counters.
        (void)query();
        fputs("missing provider was accepted\n", stderr);
        return 1;
    }
    if (argc != 1) return 2;
    char *text = strdup("ANDROID-HOST-PRELOAD-PASS standard-libc=verified");
    if (!text) return 1;
    puts(text);
    free(text);
    return 0;
}
