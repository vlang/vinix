// SPDX-License-Identifier: GPL-2.0-or-later
extern int puts(const char *), __cxa_atexit(void (*)(void *), void *, void *);
extern void abort(void);
static _Thread_local volatile int tls = 17;
static volatile int initialized;
int module_value = 42;
int *module_value_pointer = &module_value;
static void cleanup(void *value) {
    if (value != &module_value || initialized != 123) abort();
    puts("IOS-MODULES: leaf destructor");
}
__attribute__((constructor)) static void initialize(void) {
    initialized = 123;
    tls = 29;
    if (__cxa_atexit(cleanup, &module_value, &module_value)) abort();
}
int module_leaf(void) { return initialized + tls; }
void module_leaf_set(int value) { tls = value; }
