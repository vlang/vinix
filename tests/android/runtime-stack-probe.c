// SPDX-License-Identifier: GPL-2.0-or-later
#define _GNU_SOURCE
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

static pthread_t initial_thread;
static void *initial_base;
static size_t initial_size;
static const size_t worker_stack_size = 256 * 1024;
static const size_t worker_guard_size = 16 * 1024;

static int check_initial_stack(void)
{
    pthread_attr_t attributes;
    int result = pthread_getattr_np(initial_thread, &attributes);
    if (result != 0) {
        printf("ANDROID-STACK-FAIL initial getattr=%d\n", result);
        return 1;
    }
    void *base = NULL;
    size_t size = 0, guard = 0;
    int detach = -1;
    result = pthread_attr_getstack(&attributes, &base, &size);
    result |= pthread_attr_getguardsize(&attributes, &guard);
    result |= pthread_attr_getdetachstate(&attributes, &detach);
    pthread_attr_destroy(&attributes);
    if (result != 0 || size <= 16 * 1024 || guard != 0
        || detach != PTHREAD_CREATE_JOINABLE) {
        printf("ANDROID-STACK-FAIL initial base=%p size=%zu guard=%zu detach=%d\n",
               base, size, guard, detach);
        return 1;
    }
    if (initial_base != NULL && (base != initial_base || size != initial_size)) {
        puts("ANDROID-STACK-FAIL initial bounds changed when queried from worker");
        return 1;
    }
    initial_base = base;
    initial_size = size;
    return 0;
}

static int check_mapped_initial_stack(void)
{
    FILE *maps = fopen("/proc/self/maps", "r");
    if (maps == NULL) {
        puts("ANDROID-STACK-FAIL cannot read target maps");
        return 1;
    }
    uintptr_t stack_local;
    uintptr_t anchor = (uintptr_t)&stack_local;
    char *line = NULL;
    size_t capacity = 0;
    int result = 1;
    while (getline(&line, &capacity, maps) >= 0) {
        unsigned long begin, end;
        char permissions[5];
        if (sscanf(line, "%lx-%lx %4s", &begin, &end, permissions) != 3) {
            continue;
        }
        if (begin <= anchor && anchor < end && permissions[0] == 'r'
            && permissions[1] == 'w') {
            if ((uintptr_t)initial_base == begin && initial_size == end - begin) {
                result = 0;
            } else {
                printf("ANDROID-STACK-FAIL metadata=%p/%zu mapping=%lx-%lx\n",
                       initial_base, initial_size, begin, end);
            }
            break;
        }
    }
    free(line);
    fclose(maps);
    return result;
}

static void *check_worker(void *unused)
{
    (void)unused;
    if (check_initial_stack() != 0) {
        return (void *)1;
    }
    pthread_attr_t attributes;
    int result = pthread_getattr_np(pthread_self(), &attributes);
    if (result != 0) {
        printf("ANDROID-STACK-FAIL worker getattr=%d\n", result);
        return (void *)1;
    }
    void *base = NULL;
    size_t size = 0, guard = 0;
    int detach = -1;
    result = pthread_attr_getstack(&attributes, &base, &size);
    result |= pthread_attr_getguardsize(&attributes, &guard);
    result |= pthread_attr_getdetachstate(&attributes, &detach);
    pthread_attr_destroy(&attributes);
    uintptr_t local;
    uintptr_t anchor = (uintptr_t)&local;
    if (result != 0 || size < worker_stack_size || guard != worker_guard_size
        || detach != PTHREAD_CREATE_JOINABLE || anchor < (uintptr_t)base
        || anchor >= (uintptr_t)base + size) {
        printf("ANDROID-STACK-FAIL worker base=%p size=%zu guard=%zu detach=%d\n",
               base, size, guard, detach);
        return (void *)1;
    }
    printf("ANDROID-STACK worker base=%p size=%zu guard=%zu\n", base, size, guard);
    return NULL;
}

int main(void)
{
    initial_thread = pthread_self();
    if (check_initial_stack() != 0 || check_mapped_initial_stack() != 0) {
        return 1;
    }
    pthread_attr_t attributes;
    int result = pthread_attr_init(&attributes);
    if (result != 0) {
        return 1;
    }
    result = pthread_attr_setstacksize(&attributes, worker_stack_size);
    result |= pthread_attr_setguardsize(&attributes, worker_guard_size);
    pthread_t worker;
    if (result == 0) {
        result = pthread_create(&worker, &attributes, check_worker, NULL);
    }
    pthread_attr_destroy(&attributes);
    if (result != 0) {
        printf("ANDROID-STACK-FAIL worker create=%d\n", result);
        return 1;
    }
    void *status = NULL;
    result = pthread_join(worker, &status);
    if (result != 0 || status != NULL) {
        return 1;
    }
    printf("ANDROID-STACK-PASS initial base=%p size=%zu\n", initial_base, initial_size);
    return 0;
}
