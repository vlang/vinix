// SPDX-License-Identifier: GPL-2.0-or-later
// One fixture for the installed Mac library and Vinix's Darwin ARM64 adapter.
extern void *dispatch_get_global_queue(long, unsigned long);
#ifdef IOS_DISPATCH_REFERENCE
extern char _dispatch_main_q[];
static void *dispatch_get_main_queue(void) { return _dispatch_main_q; }
#else
extern void *dispatch_get_main_queue(void);
#endif
extern void *dispatch_queue_create(const char *, void *);
#ifdef IOS_DISPATCH_REFERENCE
extern void *dispatch_queue_create_with_target(const char *, void *, void *);
#else
extern void *dispatch_queue_create_with_target(const char *, void *, void *) __asm("_dispatch_queue_create_with_target$V2");
#endif
extern const char *dispatch_queue_get_label(void *);
extern void dispatch_async(void *, void (^)(void)), dispatch_sync(void *, void (^)(void));
extern void dispatch_async_f(void *, void *, void (*)(void *)), dispatch_sync_f(void *, void *, void (*)(void *));
extern void dispatch_after(unsigned long long, void *, void (^)(void));
extern void dispatch_after_f(unsigned long long, void *, void *, void (*)(void *));
extern unsigned long long dispatch_time(unsigned long long, long long);
struct timestamp { long long seconds, nanoseconds; };
extern unsigned long long dispatch_walltime(const struct timestamp *, long long);
extern void dispatch_retain(void *), dispatch_release(void *);
extern void dispatch_set_context(void *, void *), *dispatch_get_context(void *);
extern void dispatch_set_finalizer_f(void *, void (*)(void *));
extern int pthread_mutex_init(void *, const void *), pthread_mutex_lock(void *), pthread_mutex_unlock(void *), pthread_mutex_destroy(void *);
extern int pthread_cond_init(void *, const void *), pthread_cond_timedwait(void *, void *, const void *), pthread_cond_broadcast(void *), pthread_cond_destroy(void *);
extern int clock_gettime(int, struct timestamp *), usleep(unsigned), strcmp(const char *, const char *), puts(const char *);
extern void abort(void);

#define CHECK(value) do { if (!(value)) abort(); } while (0)
#define FOREVER (~0ull)
#define WALL_NOW (~1ull)
static unsigned long long mutex[16], condition[16];
static int completed, sequence, running, peak;
static int timing_order;
typedef void *CapturedQueue __attribute__((NSObject));
static void *serial, *global;
static int observed[128];
struct context { int index; const char *label; };

static void done(void) {
    CHECK(pthread_mutex_lock(mutex) == 0);
    ++completed;
    CHECK(pthread_cond_broadcast(condition) == 0);
    CHECK(pthread_mutex_unlock(mutex) == 0);
}
static void wait_for(int count) {
    struct timestamp deadline;
    CHECK(clock_gettime(0, &deadline) == 0);
    deadline.seconds += 10;
    CHECK(pthread_mutex_lock(mutex) == 0);
    while (completed < count) CHECK(pthread_cond_timedwait(condition, mutex, &deadline) == 0);
    CHECK(pthread_mutex_unlock(mutex) == 0);
}
static void record(void *argument) {
    struct context *context = argument;
    CHECK(strcmp(dispatch_queue_get_label(0), context->label) == 0);
    CHECK(sequence == context->index);
    observed[sequence++] = context->index;
}
static void barrier(void *argument) {
    CHECK(argument == observed && sequence == 128);
    CHECK(strcmp(dispatch_queue_get_label(0), "serial.copy") == 0);
    for (int i = 0; i < 128; ++i) CHECK(observed[i] == i);
}
static void forbidden(void *argument) { (void)argument; abort(); }
static void delayed(void *argument) {
    struct context *context = argument;
    CHECK(context->index == 777);
    CHECK(strcmp(dispatch_queue_get_label(0), context->label) == 0);
    done();
}
static void parallel(void *argument) {
    CHECK(argument == global);
    CHECK(strcmp(dispatch_queue_get_label(0), dispatch_queue_get_label(global)) == 0);
    CHECK(pthread_mutex_lock(mutex) == 0);
    ++running;
    if (running > peak) peak = running;
    CHECK(pthread_cond_broadcast(condition) == 0);
    struct timestamp deadline;
    CHECK(clock_gettime(0, &deadline) == 0);
    deadline.seconds += 10;
    while (peak < 2) CHECK(pthread_cond_timedwait(condition, mutex, &deadline) == 0);
    --running;
    CHECK(pthread_mutex_unlock(mutex) == 0);
    done();
}
static void finalizer(void *argument) {
    struct context *context = argument;
    CHECK(context->index == 919);
    CHECK(strcmp(dispatch_queue_get_label(0), "parent.serial") == 0);
    done();
}
static void ordered_timer(void *argument) {
    CHECK(argument == serial && timing_order == 1);
    timing_order = 2;
    done();
}
static void finishing(void *argument) {
    done(); // main may now return while this callback is still running.
    usleep(50000);
    CHECK(argument == global);
    CHECK(strcmp(dispatch_queue_get_label(0), "com.apple.root.default-qos") == 0);
}

static void test_time(void) {
    CHECK(dispatch_time(FOREVER, 17) == FOREVER);
    CHECK(dispatch_time(FOREVER, -17) == FOREVER);
    CHECK(dispatch_time(0, 0) > 0 && dispatch_time(0, 0) < (1ull << 62));
    CHECK(dispatch_time(0, -0x7fffffffffffffffll) == 1);
    CHECK(dispatch_time(0, 0x7fffffffffffffffll) == FOREVER);
    CHECK(dispatch_time(1ull << 62, 0) == FOREVER);
    CHECK(dispatch_time(~3ull, 17) == ~20ull);
    CHECK(dispatch_time(~3ull, -17) == WALL_NOW);
    struct timestamp epoch = {0, 0}, second = {1, 0}, unnormalized = {1, -1};
    CHECK(dispatch_walltime(&epoch, 0) == FOREVER);
    CHECK(dispatch_walltime(&epoch, -1) == WALL_NOW);
    CHECK(dispatch_walltime(&epoch, 2) == WALL_NOW);
    CHECK(dispatch_walltime(&second, 17) == 0ull - 1000000017ull);
    CHECK(dispatch_walltime(&second, -1000000000ll) == WALL_NOW);
    CHECK(dispatch_walltime(&unnormalized, 0) == 0ull - 999999999ull);
    CHECK(dispatch_walltime(&second, 0x7fffffffffffffffll) == FOREVER);
    unsigned long long wall = dispatch_walltime(0, 0);
    CHECK(wall >> 62 == 3);
    CHECK(dispatch_time(wall, 1000000000ll) == wall - 1000000000ull);
    CHECK(dispatch_time(wall, -1000000000ll) == wall + 1000000000ull);
    CHECK(dispatch_time(WALL_NOW, 0) >> 62 == 3);
}

int main(void) {
    test_time();
    CHECK(pthread_mutex_init(mutex, 0) == 0 && pthread_cond_init(condition, 0) == 0);
    global = dispatch_get_global_queue(0, 0);
    CHECK(global && global == dispatch_get_global_queue(21, 0));
    CHECK(dispatch_get_global_queue(2, 0) == dispatch_get_global_queue(25, 0));
    CHECK(dispatch_get_global_queue(-2, 0) == dispatch_get_global_queue(17, 0));
    CHECK(dispatch_get_global_queue(-32768, 0) == dispatch_get_global_queue(9, 0));
    CHECK(dispatch_get_global_queue(33, 0));
    CHECK(!dispatch_get_global_queue(3, 0) && !dispatch_get_global_queue(0, 1));
    CHECK(strcmp(dispatch_queue_get_label(global), "com.apple.root.default-qos") == 0);
    CHECK(strcmp(dispatch_queue_get_label(dispatch_get_main_queue()), "com.apple.main-thread") == 0);
    dispatch_retain(global); dispatch_release(global);
    char label[] = "serial.copy";
    serial = dispatch_queue_create(label, 0);
    CHECK(serial);
    label[0] = '?';
    CHECK(strcmp(dispatch_queue_get_label(serial), "serial.copy") == 0);
    struct context records[128];
    for (int i = 0; i < 128; ++i) {
        records[i].index = i; records[i].label = "serial.copy";
        if (i & 1) dispatch_async_f(serial, &records[i], record);
        else {
            struct context *captured = &records[i];
            dispatch_async(serial, ^{ record(captured); });
        }
    }
    dispatch_sync_f(serial, observed, barrier);
    int captured = 42;
    dispatch_sync(serial, ^{ CHECK(captured == 42 && sequence == 128); });
    dispatch_async_f(global, global, parallel);
    dispatch_async_f(global, global, parallel);
    wait_for(2);

    // Future work must not obstruct immediate work or a serial sync barrier.
    struct context timer = {777, "serial.copy"};
    dispatch_after_f(dispatch_time(0, 100000000ll), serial, &timer, delayed);
    dispatch_sync_f(serial, observed, barrier);
    dispatch_after(dispatch_walltime(0, 100000000ll), serial, ^{ CHECK(captured == 42); done(); });
    wait_for(4);
    dispatch_after_f(0, serial, &timer, delayed);
    wait_for(5);

    // Sibling queues inherit serial exclusion and keep their target alive.
    void *parent = dispatch_queue_create("parent.serial", 0);
    void *left = dispatch_queue_create_with_target("left", 0, parent);
    void *right = dispatch_queue_create_with_target("right", 0, parent);
    CHECK(left && right);
    for (int i = 0; i < 64; ++i) {
        void *child = i & 1 ? left : right;
        dispatch_async(child, ^{
            CHECK(strcmp(dispatch_queue_get_label(0), i & 1 ? "left" : "right") == 0);
            CHECK(pthread_mutex_lock(mutex) == 0);
            CHECK(running == 0);
            ++running;
            CHECK(pthread_mutex_unlock(mutex) == 0);
            usleep(1000);
            CHECK(pthread_mutex_lock(mutex) == 0);
            CHECK(running == 1);
            --running;
            CHECK(pthread_mutex_unlock(mutex) == 0);
            done();
        });
    }
    struct context cleanup = {919, "parent.serial"};
    dispatch_set_context(left, &cleanup);
    CHECK(dispatch_get_context(left) == &cleanup);
    dispatch_set_finalizer_f(left, finalizer);
    dispatch_retain(left);
    dispatch_release(left);
    dispatch_release(left);
    dispatch_release(right);
    wait_for(70); // 5 earlier + 64 sibling jobs + one finalizer.
    dispatch_release(parent);

    // Delay holds the queue even after the caller releases its last reference.
    void *released = dispatch_queue_create("delayed.release", 0);
    struct context last = {777, "delayed.release"};
    dispatch_after_f(dispatch_time(0, 30000000ll), released, &last, delayed);
    dispatch_release(released);
    wait_for(71);
    dispatch_async(serial, ^{ usleep(90000); });
    dispatch_after_f(dispatch_time(0, 30000000ll), serial, serial, ordered_timer);
    dispatch_async(serial, ^{ CHECK(timing_order == 0); timing_order = 1; });
    wait_for(72);
    CHECK(timing_order == 2);
    CapturedQueue captured_queue = dispatch_queue_create("block.owned.queue", 0);
    // Queue-valued ObjC captures use the block copy/dispose helpers, even in
    // this freestanding C fixture. Releasing the caller's reference is safe.
    dispatch_after(dispatch_time(0, 30000000ll), serial, ^{
        CHECK(strcmp(dispatch_queue_get_label(captured_queue), "block.owned.queue") == 0);
        done();
    });
    dispatch_release(captured_queue);
    wait_for(73);
    // Returning from the image cancels pending work before its code unmaps.
    dispatch_after_f(dispatch_time(0, 60000000000ll), serial, 0, forbidden);
    dispatch_after(dispatch_time(0, 60000000000ll), serial, ^{ CHECK(captured != 42); abort(); });
    dispatch_release(serial);
    dispatch_async_f(global, global, finishing);
    wait_for(74);
    CHECK(pthread_cond_destroy(condition) == 0 && pthread_mutex_destroy(mutex) == 0);
    puts("IOS-DISPATCH: FIFO blocks/functions, concurrent workers, serial targets, deadlines and finalizers");
    return 0;
}
