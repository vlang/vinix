/* A failing real disk must not poison fsync/fdatasync of a tmpfs file. */
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <sys/syscall.h>
#include <unistd.h>

#define CHECK(condition) do { if (!(condition)) { \
    printf("FSYNC-SCOPE FAIL: line=%d errno=%d\n", __LINE__, errno); return 1; \
} } while (0)

int main(void)
{
    setbuf(stdout, NULL);
    puts("FSYNC-SCOPE START");
    const char payload[] = "a RAM file has no failing backing disk";
    int ram = open("/tmp/sync-probe", O_CREAT | O_TRUNC | O_RDWR, 0600);
    CHECK(ram >= 0);
    CHECK(write(ram, payload, sizeof payload) == (ssize_t)sizeof payload);
    CHECK(fsync(ram) == 0 && fdatasync(ram) == 0);
    puts("FSYNC-SCOPE BASELINE-RAM-PASS");

    /* The filesystem is mounted normally, but its real NBD backend rejects
     * writes. Dirty pages remain retryable after that underlying I/O error. */
    int disk = open("/root/disk-probe.bin", O_RDWR);
    CHECK(disk >= 0);
    unsigned char bytes[8192];
    memset(bytes, 0x5a, sizeof bytes);
    CHECK(pwrite(disk, bytes, sizeof bytes, 0) == sizeof bytes);
    errno = 0;
    CHECK(fsync(disk) == -1 && errno == EIO);
    errno = 0;
    CHECK(syscall(SYS_syncfs, disk) == -1 && errno == EIO);
    puts("FSYNC-SCOPE FAILING-DISK-CONFIRMED");

    errno = 0;
    int file_result = fsync(ram), file_error = errno;
    errno = 0;
    int data_result = fdatasync(ram), data_error = errno;
    printf("FSYNC-SCOPE RAM-AFTER-DISK: fsync=%d errno=%d fdatasync=%d errno=%d\n",
           file_result, file_error, data_result, data_error);
    CHECK(file_result == 0 && data_result == 0);

    char observed[sizeof payload];
    CHECK(pread(ram, observed, sizeof observed, 0) == sizeof observed);
    CHECK(memcmp(observed, payload, sizeof payload) == 0);
    int readonly = open("/tmp/sync-probe", O_RDONLY);
    CHECK(readonly >= 0 && fsync(readonly) == 0 && fdatasync(readonly) == 0);
    CHECK(close(readonly) == 0);
    int directory = open("/tmp", O_RDONLY | O_DIRECTORY);
    CHECK(directory >= 0 && fsync(directory) == 0 && close(directory) == 0);
    int path = open("/tmp/sync-probe", O_PATH);
    CHECK(path >= 0);
    errno = 0;
    CHECK(fsync(path) == -1 && errno == EBADF);
    CHECK(close(path) == 0);
    errno = 0;
    CHECK(fsync(-1) == -1 && errno == EBADF);
    int stream[2];
    CHECK(pipe(stream) == 0);
    errno = 0;
    CHECK(fsync(stream[0]) == -1 && errno == EINVAL);
    CHECK(close(stream[0]) == 0 && close(stream[1]) == 0);

    /* The target error and dirty data must remain observable; only unrelated
     * successful resources stop inheriting a different disk's failure. */
    errno = 0;
    CHECK(fdatasync(disk) == -1 && errno == EIO);
    unsigned char retained[sizeof bytes];
    CHECK(pread(disk, retained, sizeof retained, 0) == sizeof retained);
    CHECK(memcmp(retained, bytes, sizeof bytes) == 0);
    CHECK(close(disk) == 0 && close(ram) == 0);
    puts("FSYNC-SCOPE PASS");
    for (;;) pause();
}
