/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Native libc, stat, signal and variadic ABI adapters. Collector policy is V. */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <limits.h>
#include <signal.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>
#include "collector_v.h"
volatile int stopping, reopening;
_Static_assert(sizeof(sig_atomic_t) == sizeof(int) && PATH_MAX <= 4096
               && sizeof(struct record) == 120, "V collector fixed storage ABI");
int vka_stat(int fd, struct vka_stat *out) {
    struct stat st;
    if (fstat(fd, &st)) return -1;
    *out = (struct vka_stat){st.st_mode, st.st_uid, st.st_nlink, st.st_dev, st.st_ino,
                            S_ISREG(st.st_mode), S_ISDIR(st.st_mode)};
    return 0;
}
size_t vka_path_max(void) { return PATH_MAX; }
char *vka_token(char *text, const char *delimiters, char **save) { return strtok_r(text, delimiters, save); }
/* Error selectors avoid depending on Darwin/Linux errno numeric differences. */
static const int error_codes[] = { EINTR, EEXIST, ENOENT, EOVERFLOW, EPROTO, EACCES, EINVAL, EIO };
int vka_errno(void) { return errno; }
int vka_is_error(int selector) { return errno == error_codes[selector]; }
void vka_set_errno(int selector) { errno = error_codes[selector]; }
void vka_restore_errno(int error) { errno = error; }
int vka_open_read(const char *path) { return open(path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC); }
int vka_open_root(void) { return open("/", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC); }
int vka_open_dir(int parent, const char *name) { return openat(parent, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC); }
int vka_open_log_file(int parent, const char *name, int create) {
    return openat(parent, name, O_WRONLY | O_APPEND | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC
                  | (create ? O_CREAT | O_EXCL : 0), 0600);
}
int vka_dup(int fd) { return fcntl(fd, F_DUPFD_CLOEXEC, 3); }
int vka_lock(int fd) { return flock(fd, LOCK_EX | LOCK_NB); }
int vka_mkdir(int parent, const char *name) { return mkdirat(parent, name, 0700); }
int64_t vka_read(int fd, void *buffer, size_t size) { return read(fd, buffer, size); }
int64_t vka_write(int fd, const void *buffer, size_t size) { return write(fd, buffer, size); }
int vka_close(int fd) { return close(fd); }
int vka_fsync(int fd) { return fsync(fd); }
uint32_t vka_uid(void) { return getuid(); }
uint32_t vka_euid(void) { return geteuid(); }
int64_t vka_pid(void) { return getpid(); }
void vka_umask(void) { umask(077); }
static void signal_handler(int signal) { if (signal == SIGHUP) reopening = 1; else stopping = 1; }
int vka_signals(void) {
    struct sigaction action = {0}; action.sa_handler = signal_handler; sigemptyset(&action.sa_mask);
    return sigaction(SIGTERM, &action, NULL) || sigaction(SIGINT, &action, NULL)
           || sigaction(SIGHUP, &action, NULL) ? -1 : 0;
}
uint64_t vka_wall_ns(void) {
    struct timespec now;
    if (clock_gettime(CLOCK_REALTIME, &now)) return 0;
    return (uint64_t)now.tv_sec * 1000000000 + (uint64_t)now.tv_nsec;
}
int vka_sleep(uint64_t *seconds, uint64_t *nanoseconds) {
    struct timespec delay = {(time_t)*seconds, (long)*nanoseconds};
    int result = nanosleep(&delay, &delay);
    *seconds = (uint64_t)delay.tv_sec; *nanoseconds = (uint64_t)delay.tv_nsec;
    return result;
}
void vka_usage(void) { fputs("usage: vinix-security-audit [--log /var/log/vinix-audit/seccomp.log] [--source /proc/security_audit] [--interval-ms 250] [--once]\n", stderr); }
void vka_root_required(void) { fputs("vinix-security-audit: initial-namespace root required\n", stderr); }
void vka_perror(const char *operation) { perror(operation); }
void vka_collection_error(int error) { fprintf(stderr, "vinix-security-audit: collection stopped: %s\n", strerror(error)); }
/* Keep the independent include-C fixtures' native va_list helper. Production
 * V output uses bounded character/decimal append and never this formatter. */
#ifdef main
static inline int add(struct output *o, const char *format, ...) {
    va_list args; va_start(args, format);
    int n = vsnprintf(o->bytes + o->used, sizeof(o->bytes) - o->used, format, args); va_end(args);
    if (n < 0 || (size_t)n >= sizeof(o->bytes) - o->used) { errno = EOVERFLOW; return -1; }
    o->used += (size_t)n; return 0;
}
static inline int number(const char *s, uint64_t *out) { return vka_number(s, out); }
static inline int parse_snapshot(char *text, struct snapshot *s) { return vka_parse_snapshot(text, s); }
static inline int collect(struct collector *c, const struct snapshot *s, struct output *o) { return vka_collect(c, s, o); }
static inline int end_pending(struct output *o, const struct collector *c, const char *reason) { return vka_end_pending(o, c, reason); }
static inline int log_stat(int fd, uid_t owner) { return vka_log_stat(fd, owner); }
static inline int directory_stat(int fd, uid_t owner) { return vka_directory_stat(fd, owner); }
static inline int open_log_at(int parent, const char *name, uid_t owner, int previous) { return vka_open_log_at(parent, name, owner, previous); }
static inline int open_log(const char *path, int previous) { return vka_open_log(path, previous); }
static inline int append(int fd, const struct output *o, uid_t owner) { return vka_append(fd, o, owner); }
static inline int read_snapshot(const char *path, struct snapshot *s) { return vka_read_snapshot(path, s); }
#endif
int main(int argc, char **argv) { return vka_main(argc, argv); }
