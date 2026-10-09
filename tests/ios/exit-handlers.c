// SPDX-License-Identifier: GPL-2.0-or-later
// The same callbacks exercise the installed Mac library and the V image queue.
extern int atexit(void (*)(void));
extern int __cxa_atexit(void (*)(void *), void *, void *);
extern void __cxa_finalize(void *);
extern void exit(int) __attribute__((noreturn));
extern void _exit(int) __attribute__((noreturn));
extern int puts(const char *);
extern int printf(const char *, ...);
extern int fflush(void *);
extern int strcmp(const char *, const char *);
extern int pthread_create(unsigned long *, const void *, void *(*)(void *), void *);
extern int pthread_join(unsigned long, void **);

static int dso, other_dso, stage, nested_calls, plain_calls;
static int calls[8], registration[8];

static void fail(void) { puts("IOS-EXIT: callback failure"); fflush(0); _exit(90); }
static void advance(int expected) {
    if (stage != expected) { printf("IOS-EXIT: stage %d expected %d\n", stage, expected); fail(); }
    stage++;
}
static void threaded_cleanup(void *argument) { (*(int *)argument)++; }
static void threaded_plain(void) { if (stage != 6) fail(); plain_calls++; }
static void *worker(void *argument) {
    unsigned long index = (unsigned long)argument;
    registration[index] = __cxa_atexit(threaded_cleanup, &calls[index], &dso);
    if (!registration[index]) registration[index] = atexit(threaded_plain);
    return 0;
}
static void nested(void *argument) {
    if (argument != &nested_calls || nested_calls++ != 0) fail();
    if (__cxa_atexit(threaded_cleanup, &nested_calls, &dso)) fail();
    __cxa_finalize(&dso);
    __cxa_finalize(&dso);
}

static void last(void) {
    if (plain_calls != 8) fail();
    advance(6);
    puts("IOS-EXIT: mixed LIFO, reentrant registration, DSO filtering and eight threads");
}
static void plain(void) { advance(5); }
static void middle(void *argument) { if (argument != &stage) fail(); advance(4); }
static void newest_plain(void) { advance(3); }
static void newest_cxa(void *argument) { if (argument != &dso) fail(); advance(2); }
static void reentrant(void *argument) {
    if (argument != &stage) fail();
    advance(1);
    if (atexit(newest_plain) || __cxa_atexit(newest_cxa, &dso, &dso)) fail();
}
static void filtered(void *argument) { if (argument != &stage) fail(); advance(0); }
static void forbidden(void) { puts("IOS-EXIT: forbidden immediate-exit callback"); _exit(91); }

int main(int argc, char **argv) {
    if (argc > 1 && !strcmp(argv[1], "immediate")) {
        if (atexit(forbidden)) return 10;
        puts("IOS-EXIT: immediate exit skips callbacks");
        fflush(0);
        _exit(8);
    }
    if (atexit(last)) return 18;
    unsigned long threads[8];
    for (unsigned long i = 0; i < 8; i++)
        if (pthread_create(&threads[i], 0, worker, (void *)i)) return 11;
    for (int i = 0; i < 8; i++)
        if (pthread_join(threads[i], 0) || registration[i]) return 12;
    __cxa_finalize(&dso);
    __cxa_finalize(&dso);
    for (int i = 0; i < 8; i++) if (calls[i] != 1) return 13;
    if (__cxa_atexit(nested, &nested_calls, &dso)) return 16;
    __cxa_finalize(&dso);
    __cxa_finalize(&dso);
    if (nested_calls != 2) return 17;
    if (atexit(plain) ||
        __cxa_atexit(middle, &stage, &other_dso) ||
        __cxa_atexit(reentrant, &stage, &other_dso) ||
        __cxa_atexit(filtered, &stage, &dso)) return 14;
    __cxa_finalize(&dso);
    __cxa_finalize(&dso);
    if (stage != 1) return 15;
    // Remaining callbacks run after this returns, or before exit terminates.
    puts("IOS-EXIT: main completed");
    if (argc > 1 && !strcmp(argv[1], "explicit")) exit(7);
    return 0;
}
