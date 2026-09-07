#define _GNU_SOURCE

#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <sched.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/epoll.h>
#include <sys/eventfd.h>
#include <sys/resource.h>
#include <sys/sendfile.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/uio.h>
#include <sys/utsname.h>
#include <sys/membarrier.h>
#include <time.h>
#include <unistd.h>

#ifndef AT_EMPTY_PATH
#define AT_EMPTY_PATH 0x1000
#endif

#ifndef SYS_epoll_pwait2
#define SYS_epoll_pwait2 441
#endif

struct open_how_abi {
    uint64_t flags;
    uint64_t mode;
    uint64_t resolve;
};

static int failures;

static void check(int condition, const char *description) {
    printf("%-42s %s\n", description, condition ? "ok" : "FAIL");
    fflush(stdout);
    if (!condition)
        failures++;
}

static void *eventfd_writer(void *argument) {
    int fd = *(int *)argument;
    struct timespec delay = {.tv_nsec = 10000000};
    nanosleep(&delay, NULL);
    eventfd_write(fd, 11);
    return NULL;
}

int main(void) {
    const char *path = "/tmp/aarch64-syscall-smoke";
    const char *copy_path = "/tmp/aarch64-syscall-copy";
    unlink(path);
    unlink(copy_path);

    int fd = open(path, O_CREAT | O_TRUNC | O_RDWR | O_CLOEXEC, 0600);
    check(fd >= 0, "open test file");
    if (fd < 0)
        return 1;

    check(pwrite(fd, "scalar", 6, 0) == 6, "pwrite64");
    char scalar[7] = {0};
    check(pread(fd, scalar, 6, 0) == 6 && !strcmp(scalar, "scalar"), "pread64");

    struct iovec write_iov[] = {
        {.iov_base = (void *)"vector", .iov_len = 6},
        {.iov_base = (void *)" write", .iov_len = 6},
    };
    lseek(fd, 7, SEEK_SET);
    check(pwritev(fd, write_iov, 2, 32) == 12, "pwritev split-offset ABI");
    char left[7] = {0};
    char right[7] = {0};
    struct iovec read_iov[] = {
        {.iov_base = left, .iov_len = 6},
        {.iov_base = right, .iov_len = 6},
    };
    check(preadv(fd, read_iov, 2, 32) == 12 && !strcmp(left, "vector") &&
              !strcmp(right, " write") && lseek(fd, 0, SEEK_CUR) == 7,
          "preadv preserves shared offset");

    uint64_t positioned_offset = 64;
    check(syscall(SYS_pwritev2, fd, write_iov, 2,
                  (uint32_t)positioned_offset, positioned_offset >> 32, 0) == 12,
          "pwritev2 Linux ABI");
    memset(left, 0, sizeof(left));
    memset(right, 0, sizeof(right));
    check(syscall(SYS_preadv2, fd, read_iov, 2,
                  (uint32_t)positioned_offset, positioned_offset >> 32, 0) == 12 &&
              !strcmp(left, "vector") && !strcmp(right, " write"),
          "preadv2 Linux ABI");

    errno = 0;
    check(readv(-1, NULL, 0) == -1 && errno == EBADF,
          "readv validates fd with zero vectors");

    check(posix_fallocate(fd, 0, 128) == 0, "fallocate");
    struct stat file_stat;
    check(fstat(fd, &file_stat) == 0 && file_stat.st_size >= 128,
          "fallocate extends file");
    check(posix_fadvise(fd, 0, 0, POSIX_FADV_NORMAL) == 0, "fadvise64");
    check(sync_file_range(fd, 0, 128, SYNC_FILE_RANGE_WRITE) == 0,
          "sync_file_range");

    int copy_fd = open(copy_path, O_CREAT | O_TRUNC | O_RDWR | O_CLOEXEC, 0600);
    off_t send_offset = 32;
    check(copy_fd >= 0 && sendfile(copy_fd, fd, &send_offset, 12) == 12 &&
              send_offset == 44 && lseek(fd, 0, SEEK_CUR) == 7,
          "sendfile positioned input");
    char copied[13] = {0};
    check(pread(copy_fd, copied, 12, 0) == 12 && !strcmp(copied, "vector write"),
          "sendfile contents");
    close(copy_fd);

    int counter = eventfd(0, EFD_NONBLOCK | EFD_CLOEXEC);
    int epoll = epoll_create1(EPOLL_CLOEXEC);
    struct epoll_event interest = {.events = EPOLLIN, .data.u64 = 0x56494e4958ULL};
    struct epoll_event ready = {0};
    check(counter >= 0 && epoll >= 0 && epoll_ctl(epoll, EPOLL_CTL_ADD, counter,
                                                   &interest) == 0,
          "eventfd and epoll setup");
    errno = 0;
    eventfd_t value = 0;
    check(eventfd_read(counter, &value) == -1 && errno == EAGAIN,
          "eventfd nonblocking empty read");
    check(eventfd_write(counter, 7) == 0 &&
              syscall(SYS_epoll_pwait2, epoll, &ready, 1,
                      &(struct timespec){.tv_sec = 1}, NULL, 8) == 1 &&
              ready.data.u64 == interest.data.u64 &&
              eventfd_read(counter, &value) == 0 && value == 7,
          "eventfd readiness via epoll_pwait2");
    close(epoll);
    close(counter);

    int blocking_counter = eventfd(0, EFD_CLOEXEC);
    pthread_t writer;
    check(blocking_counter >= 0 &&
              pthread_create(&writer, NULL, eventfd_writer, &blocking_counter) == 0 &&
              eventfd_read(blocking_counter, &value) == 0 && value == 11 &&
              pthread_join(writer, NULL) == 0,
          "blocking eventfd cross-thread wakeup");
    close(blocking_counter);

    struct open_how_abi how = {.flags = O_RDONLY | O_CLOEXEC};
    int opened = syscall(SYS_openat2, AT_FDCWD, path, &how, sizeof(how));
    check(opened >= 0, "openat2");
    if (opened >= 0)
        close(opened);
    check(syscall(SYS_faccessat, AT_FDCWD, path, F_OK) == 0,
          "legacy faccessat ABI");
    check(syscall(SYS_faccessat2, fd, "", F_OK, AT_EMPTY_PATH) == 0,
          "faccessat2 AT_EMPTY_PATH");

    struct rlimit limit;
    check(syscall(SYS_getrlimit, RLIMIT_NOFILE, &limit) == 0 &&
              limit.rlim_cur > 0 && limit.rlim_max >= limit.rlim_cur,
          "getrlimit");
    unsigned cpu = UINT32_MAX;
    unsigned node = UINT32_MAX;
    check(syscall(SYS_getcpu, &cpu, &node, NULL) == 0 && node == 0,
          "getcpu");
    struct timespec interval;
    check(sched_rr_get_interval(0, &interval) == 0 && interval.tv_nsec > 0,
          "sched_rr_get_interval");
    check(membarrier(MEMBARRIER_CMD_QUERY, 0) == 0,
          "membarrier feature query");

    check(sethostname("syscall-smoke", 13) == 0, "sethostname");
    check(syscall(SYS_setdomainname, "vinix.test", 10) == 0, "setdomainname");
    struct utsname uts;
    check(uname(&uts) == 0 && !strcmp(uts.machine, "aarch64") &&
              !strcmp(uts.nodename, "syscall-smoke") &&
              !strcmp(uts.domainname, "vinix.test"),
          "uname hostname and domainname");

    close(fd);
    unlink(path);
    unlink(copy_path);
    printf("AARCH64 SYSCALL SMOKE %s (%d failures)\n",
           failures ? "FAIL" : "PASS", failures);
    return failures ? 1 : 0;
}
