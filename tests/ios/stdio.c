// SPDX-License-Identifier: GPL-2.0-or-later
#include <stdio.h>
#include <stdarg.h>
#include <string.h>
#include <unistd.h>
#include <sys/sysctl.h>
#include <errno.h>
#include <stdlib.h>
#include <time.h>
#include <spawn.h>
#include <dlfcn.h>
#include <sys/mman.h>
#include <dirent.h>
#include <math.h>
#include <setjmp.h>
extern int __tolower(int);
extern int __toupper(int);
#include <fcntl.h>
#include <sys/stat.h>

extern int __snprintf_chk(char *, size_t, int, size_t, const char *, ...);

_Static_assert(sizeof(FILE) == 152, "Darwin ARM64 FILE ABI");
_Static_assert(sizeof(struct stat) == 144, "Darwin ARM64 stat ABI");

static int format(char *output, size_t size, const char *pattern, ...) {
    va_list arguments;
    va_start(arguments, pattern);
    int result = vsnprintf(output, size, pattern, arguments);
    va_end(arguments);
    return result;
}

int main(void) {
    _Static_assert(sizeof(jmp_buf) == 192, "Darwin ARM64 jump buffer");
    struct { jmp_buf buffer; unsigned long guard; } jump = {.guard = 0x3141592653589793};
    volatile int jumped = 0;
    int result = setjmp(jump.buffer);
    if (!result) { jumped = 1; longjmp(jump.buffer, 37); }
    if (result != 37 || !jumped || jump.guard != 0x3141592653589793) return 78;
    result = _setjmp(jump.buffer);
    if (!result) _longjmp(jump.buffer, 0);
    if (result != 1 || jump.guard != 0x3141592653589793) return 79;
    volatile float angle_f = 0.5f;
    volatile double angle_d = 0.5;
    struct __float2 pair_f = __sincosf_stret(angle_f);
    struct __double2 pair_d = __sincos_stret(angle_d);
    if (pair_f.__sinval < 0.4794f || pair_f.__sinval > 0.4795f || pair_f.__cosval < 0.8775f || pair_f.__cosval > 0.8776f ||
        pair_d.__sinval < 0.4794 || pair_d.__sinval > 0.4795 || pair_d.__cosval < 0.8775 || pair_d.__cosval > 0.8776 ||
        __exp10(angle_d) < 3.1622 || __exp10(angle_d) > 3.1623 || __exp10f(angle_f) < 3.1622f || __exp10f(angle_f) > 3.1623f) return 77;
    if (__tolower('A') != 'a' || __toupper('z') != 'Z' || __tolower(-1) != -1 || __toupper(-1) != -1) return 76;
    FILE *directory_fixture = fopen("/tmp/ios-native-directory-test", "w");
    if (!directory_fixture || fclose(directory_fixture)) return 74;
    DIR *directory = opendir("/tmp");
    if (!directory) return 70;
    int found = 0;
    struct dirent *entry;
    errno = 0;
    while ((entry = readdir(directory))) {
        if (entry->d_namlen != strlen(entry->d_name) || entry->d_reclen < 21 + entry->d_namlen + 1) return 71;
        if (!strcmp(entry->d_name, "ios-native-directory-test")) {
            if (entry->d_type != DT_REG || !entry->d_ino) return 72;
            found++;
        }
    }
    if (errno || closedir(directory) || found != 1) return 73;
    if (unlink("/tmp/ios-native-directory-test")) return 75;
    char buffer[128];
    if (snprintf(buffer, sizeof(buffer), "%d %lld %.3f %s %*.*f", -42, 1234567890123LL,
        3.125, "arm64", 8, 2, 7.5) != 38) return 31;
    if (strcmp(buffer, "-42 1234567890123 3.125 arm64     7.50")) return 32;
    if (format(buffer, sizeof(buffer), "%d/%s/%.2f", 7, "native", 4.25) != 13) return 33;
    if (strcmp(buffer, "7/native/4.25")) return 34;
    int number;
    double real;
    if (sscanf("-123 6.75", "%d %lf", &number, &real) != 2 || number != -123 || real != 6.75) return 35;
    if (fprintf(stderr, "IOS-STDIO: %s %d %.2f\n", "Darwin varargs", number, real) < 0) return 36;
    FILE *file = fopen("/tmp/ios-native-stdio", "w+");
    if (!file || fwrite("abc\n", 1, 4, file) != 4 || ftell(file) != 4) return 37;
    rewind(file);
    if (getc(file) != 'a' || ungetc('a', file) != 'a') return 38;
    if (!fgets(buffer, sizeof(buffer), file) || strcmp(buffer, "abc\n")) return 39;
    if (getc(file) != EOF || !feof(file) || ferror(file)) return 40;
    clearerr(file);
    if (feof(file) || fseek(file, 0, SEEK_END) || putc('Z', file) != 'Z' || fflush(file)) return 41;
    rewind(file);
    if (fread(buffer, 1, 5, file) != 5 || memcmp(buffer, "abc\nZ", 5) || fclose(file)) return 42;
    int cpus = 0;
    size_t size = sizeof(cpus);
    if (sysctlbyname("hw.logicalcpu_max", &cpus, &size, NULL, 0) || cpus < 1 || size != 4) return 43;
    size = 1;
    if (sysctlbyname("hw.logicalcpu_max", &cpus, &size, NULL, 0) != -1 || errno != ENOMEM || size != 4) return 44;
    if (sysctlbyname("hw.vinix_test_unknown", NULL, &size, NULL, 0) != -1 || errno != ENOENT) return 45;
    char *allocated = NULL;
    if (asprintf(&allocated, "%s:%d/%.2f", "owned", -7, 3.25) != 13 || !allocated || strcmp(allocated, "owned:-7/3.25")) return 46;
    free(allocated);
    if (__snprintf_chk(buffer, sizeof(buffer), 0, sizeof(buffer), "%d %.2f", -9, 2.5) != 7 || strcmp(buffer, "-9 2.50")) return 47;
    struct timespec first, second;
    if (clock_gettime(CLOCK_MONOTONIC, &first) || clock_gettime(CLOCK_MONOTONIC, &second)) return 48;
    if (second.tv_sec < first.tv_sec || (second.tv_sec == first.tv_sec && second.tv_nsec < first.tv_nsec)) return 49;
    if (clock_gettime((clockid_t)999, &first) != -1 || errno != EINVAL) return 50;
    time_t epoch = 0;
    struct tm calendar;
    if (sizeof(calendar) != 56 || !gmtime_r(&epoch, &calendar) || calendar.tm_year != 70 || calendar.tm_mon || calendar.tm_mday != 1) return 51;
    if (strftime(buffer, sizeof(buffer), "%Y-%m-%d", &calendar) != 10 || strcmp(buffer, "1970-01-01")) return 52;
    pid_t child = -1;
    char *arguments[] = {"vinix-missing-executable", NULL};
    char *environment[] = {NULL};
    if (posix_spawnp(&child, "/vinix-missing-executable", NULL, NULL, arguments, environment) != ENOENT) return 53;
    void *process = dlopen(NULL, RTLD_LAZY);
    if (!process || !dlsym(process, "puts") || dlerror()) return 54;
    if (dlsym(process, "vinix_missing_symbol") || !dlerror() || dlerror() || dlclose(process)) return 55;
    int descriptor = open("/tmp/ios-open-mode", O_RDWR | O_CREAT | O_EXCL, 0600);
    if (descriptor < 0 || write(descriptor, "open", 4) != 4) return 56;
    struct { struct stat info; unsigned long guard; } metadata;
    metadata.guard = 0x123456789abcdef0;
    if (fstat(descriptor, &metadata.info) || metadata.info.st_size != 4 || !S_ISREG(metadata.info.st_mode) || metadata.guard != 0x123456789abcdef0) return 60;
    struct stat by_path;
    if (stat("/tmp/ios-open-mode", &by_path) || by_path.st_ino != metadata.info.st_ino || (by_path.st_mode & 0777) != 0600) return 61;
    if (close(descriptor) || unlink("/tmp/ios-open-mode")) return 62;
    descriptor = shm_open("/vinix-ios-shared-memory", O_RDWR | O_CREAT | O_EXCL, 0600);
    if (descriptor < 0 || shm_unlink("/vinix-ios-shared-memory") || ftruncate(descriptor, 16384)) return 57;
    unsigned char *left = mmap(NULL, 16384, PROT_READ | PROT_WRITE, MAP_SHARED, descriptor, 0);
    unsigned char *right = mmap(NULL, 16384, PROT_READ | PROT_WRITE, MAP_SHARED, descriptor, 0);
    if (left == MAP_FAILED || right == MAP_FAILED || left[100] || right[100]) return 58;
    left[100] = 42;
    if (right[100] != 42 || close(descriptor) || munmap(left, 16384) || munmap(right, 16384)) return 59;
    puts("IOS-STDIO: FILE layout, buffers, varargs and sysctl queries");
    puts("IOS-STDIO: allocation, checked formatting, clocks, spawn errors and dynamic lookup");
    puts("IOS-STDIO: Darwin open flags and shared memory aliases");
    return 0;
}
