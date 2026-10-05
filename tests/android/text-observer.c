/* Test-only observation of text drawn by the unmodified Android APK. */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/resource.h>
#include <unistd.h>

__attribute__((constructor)) static void observe_stack(void) {
    pthread_attr_t attr;
    void *base = NULL;
    size_t size = 0, guard = 0;
    int result = pthread_getattr_np(pthread_self(), &attr);
    if (!result) {
        pthread_attr_getstack(&attr, &base, &size);
        pthread_attr_getguardsize(&attr, &guard);
        pthread_attr_destroy(&attr);
    }
    struct rlimit limit = {0, 0};
    getrlimit(RLIMIT_STACK, &limit);
    int fd = open("/tmp/android-text.log", O_WRONLY | O_CREAT | O_APPEND, 0600);
    if (fd >= 0) {
        char line[256];
        int count = snprintf(line, sizeof(line),
            "ANDROID-STACK pid=%ld local=%p result=%d base=%p size=%zu guard=%zu limit=%llu\n",
            (long)getpid(), &attr, result, base, size, guard, (unsigned long long)limit.rlim_cur);
        if (count > 0) (void)write(fd, line, (size_t)count);
        FILE *maps = fopen("/proc/self/maps", "r");
        if (maps) {
            int found = 0;
            while (fgets(line, sizeof(line), maps)) {
                unsigned long long start, end;
                if (sscanf(line, "%llx-%llx", &start, &end) == 2 &&
                    (unsigned long long)(uintptr_t)&attr >= start &&
                    (unsigned long long)(uintptr_t)&attr < end) {
                    (void)write(fd, "ANDROID-STACK-MAP ", sizeof("ANDROID-STACK-MAP ") - 1);
                    (void)write(fd, line, strlen(line));
                    found = 1;
                    break;
                }
            }
            if (!found) (void)write(fd, "ANDROID-STACK-MAP missing\n", sizeof("ANDROID-STACK-MAP missing\n") - 1);
            fclose(maps);
        }
        close(fd);
    }
}

static void observe(const char *text, int length) {
    const char *expected = getenv("VINIX_ANDROID_EXPECTED_RESULT");
    if (!text) return;
    if (length < 0) length = (int)strlen(text);
    if (length > 256) return;
    int fd = open("/tmp/android-text.log", O_WRONLY | O_CREAT | O_APPEND, 0600);
    if (fd >= 0) {
        char line[280];
        int count = snprintf(line, sizeof(line), "ANDROID-TEXT %.*s\n", length, text);
        if (count > 0) (void)write(fd, line, (size_t)count);
        close(fd);
    }
    if (expected && strlen(expected) == (size_t)length && !memcmp(expected, text, (size_t)length)) {
        fd = open("/tmp/android-result", O_WRONLY | O_CREAT | O_TRUNC, 0600);
        if (fd >= 0) {
            (void)write(fd, text, (size_t)length);
            close(fd);
        }
    }
}

static void observe_input(const char *text) {
    if (!text || strlen(text) > 256) return;
    int saved_errno = errno;
    char temporary[80];
    snprintf(temporary, sizeof(temporary), "/tmp/android-input.%ld", (long)getpid());
    int fd = open(temporary, O_WRONLY | O_CREAT | O_TRUNC, 0600);
    if (fd >= 0) {
        size_t length = strlen(text);
        ssize_t written = write(fd, text, length);
        close(fd);
        if (written == (ssize_t)length) (void)rename(temporary, "/tmp/android-input");
    }
    errno = saved_errno;
}

const char *gtk_entry_buffer_get_text(void *buffer) {
    static const char *(*real)(void *);
    if (!real) real = dlsym(RTLD_NEXT, "gtk_entry_buffer_get_text");
    const char *text = real(buffer);
    observe_input(text);
    return text;
}

const char *gtk_editable_get_text(void *editable) {
    static const char *(*real)(void *);
    if (!real) real = dlsym(RTLD_NEXT, "gtk_editable_get_text");
    const char *text = real(editable);
    observe_input(text);
    return text;
}

void gtk_label_set_text(void *label, const char *text) {
    static void (*real)(void *, const char *);
    if (!real) real = dlsym(RTLD_NEXT, "gtk_label_set_text");
    observe(text, -1);
    real(label, text);
}

void gtk_entry_buffer_set_text(void *buffer, const char *text, int length) {
    static void (*real)(void *, const char *, int);
    if (!real) real = dlsym(RTLD_NEXT, "gtk_entry_buffer_set_text");
    observe(text, length);
    real(buffer, text, length);
    (void)gtk_entry_buffer_get_text(buffer);
}

void pango_layout_set_text(void *layout, const char *text, int length) {
    static void (*real)(void *, const char *, int);
    if (!real) real = dlsym(RTLD_NEXT, "pango_layout_set_text");
    observe(text, length);
    real(layout, text, length);
}
