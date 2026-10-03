/* Compile once as a packed-relocation DSO with BIONIC_LOADER_PAYLOAD,
 * then as a native 16 KiB fixture loading the DSO through the actual loader.
 * Link the fixture with the pinned main_executable/bionic_compat.c: the loader
 * requires its executable _r_debug and Android TLS initialization. */
#ifdef BIONIC_LOADER_PAYLOAD
extern void *dlopen(const char *, int);
extern void *dlsym(void *, const char *);
extern int dlclose(void *);
extern char *getenv(const char *);
static int value;
static int *volatile relocated_pointer = &value;

__attribute__((constructor)) static void initialize(void)
{
    /* The outer load must already own a reference while its constructor
     * temporarily opens and closes the same DSO. */
    const char *self_path = getenv("BIONIC_LOADER_TEST_SELF");
    void *self = self_path ? dlopen(self_path, 2) : (void *)0;
    if (!self || dlclose(self) != 0) {
        *relocated_pointer = -4;
        return;
    }
    /* A constructor's nested loader operations must acquire the same lock
     * recursively. Resolve and call the actual libc page-size query. */
    void *library = dlopen("libc.so", 2);
    if (!library) {
        *relocated_pointer = -1;
        return;
    }
    unsigned long (*query)(unsigned long) = dlsym(library, "getauxval");
    int result = query && query(6) != 0 ? 42 : -2;
    if (dlclose(library) != 0) result = -3;
    *relocated_pointer = result;
}

int loader_probe_value(void)
{
    return *relocated_pointer;
}
#else
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char **argv)
{
    if (argc != 3) {
        fprintf(stderr, "usage: %s libdl_bio.so packed-relocation-probe.so\n", argv[0]);
        return 2;
    }
    if (setenv("BIONIC_LOADER_TEST_SELF", argv[2], 1) != 0) return 1;
    void *provider = dlopen(argv[1], RTLD_NOW | RTLD_GLOBAL);
    if (!provider) {
        fprintf(stderr, "provider load failed: %s\n", dlerror());
        return 1;
    }
    const char *verbosity = getenv("BIONIC_LOADER_TEST_VERBOSE");
    if (verbosity) {
        int *level = dlsym(provider, "apkenv_debug_verbosity");
        if (level) *level = atoi(verbosity);
    }
    void *(*android_dlopen)(const char *, int) = dlsym(provider, "bionic_dlopen");
    void *(*android_dlsym)(void *, const char *) = dlsym(provider, "bionic_dlsym");
    int (*android_dlclose)(void *) = dlsym(provider, "bionic_dlclose");
    const char *(*android_dlerror)(void) = dlsym(provider, "bionic_dlerror");
    if (!android_dlopen || !android_dlsym || !android_dlclose || !android_dlerror) {
        fputs("missing real Bionic loader exports\n", stderr);
        return 1;
    }
    void *payload = android_dlopen(argv[2], RTLD_NOW);
    if (!payload) {
        fprintf(stderr, "Android DSO load failed: %s\n", android_dlerror());
        return 1;
    }
    int (*probe)(void) = android_dlsym(payload, "loader_probe_value");
    if (!probe || probe() != 42) {
        fputs("packed relocation or constructor was not applied\n", stderr);
        return 1;
    }
    if (android_dlclose(payload) != 0) {
        fputs("Android DSO close failed\n", stderr);
        return 1;
    }
    puts("ANDROID-BIONIC-LOADER pass");
    return 0;
}
#endif
