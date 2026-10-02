// SPDX-License-Identifier: GPL-2.0-or-later
#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <sched.h>
#include <stdio.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>
#include <sys/reboot.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <sys/statfs.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <sys/xattr.h>
#include <time.h>
#include <unistd.h>

#define CHECK(condition) do { if (!(condition)) { \
 printf("FAIL: xattr line %d errno=%d\n", __LINE__, errno); return 1; } } while (0)
#define EXPECT_ERROR(call, error) do { errno = 0; CHECK((call) == -1 && errno == (error)); } while (0)

static const unsigned char payload[] = {0, 1, 0xff, 0, 0x42};
struct heap { long size[32], objects[32]; int count; long large; };

static int heap_snapshot(struct heap *heap)
{
 FILE *file = fopen("/proc/slabinfo", "r");
 CHECK(file != NULL);
 char line[256];
 int saw_large = 0;
 memset(heap, 0, sizeof(*heap));
 while (fgets(line, sizeof(line), file)) {
  long label, size, objects, pages;
  if (sscanf(line, "size-%ld %ld %ld %ld", &label, &size, &objects, &pages) == 4 && label == size && heap->count < 32) {
   heap->size[heap->count] = size;
   heap->objects[heap->count++] = objects;
  } else if (sscanf(line, "large - - %ld", &pages) == 1) {
   heap->large = pages;
   saw_large = 1;
  }
 }
 fclose(file);
#if defined(__aarch64__)
 CHECK(heap->count == 18 && saw_large);
#else
 CHECK(heap->count == 14 && saw_large);
#endif
 return 0;
}

static int operations(int fd, int repeats)
{
 for (int i = 0; i < repeats; i++) {
  unsigned char got[32];
  char names[256];
  CHECK(fsetxattr(fd, "user.repeat", payload, sizeof(payload), XATTR_CREATE) == 0);
  CHECK(fgetxattr(fd, "user.repeat", NULL, 0) == sizeof(payload));
  CHECK(fgetxattr(fd, "user.repeat", got, sizeof(got)) == sizeof(payload));
  CHECK(memcmp(got, payload, sizeof(payload)) == 0);
  CHECK(flistxattr(fd, names, sizeof(names)) > 0);
  CHECK(fsetxattr(fd, "user.repeat", "replacement", 11, XATTR_REPLACE) == 0);
  CHECK(fremovexattr(fd, "user.repeat") == 0);
 }
 return 0;
}

static int metadata_operations(int fd, int repeats)
{
 const struct timespec times[2] = {{1700000000, 0}, {1700000001, 0}};
 for (int i = 0; i < repeats; i++) {
  CHECK(fchmod(fd, 0600) == 0 && fchown(fd, 0, 0) == 0 && futimens(fd, times) == 0);
 }
 return 0;
}

static int metadata_measure(const char *path, const char *backend)
{
 int fd = open(path, O_RDWR);
 CHECK(fd >= 0 && metadata_operations(fd, 100) == 0);
 struct heap before, after;
 CHECK(heap_snapshot(&before) == 0 && metadata_operations(fd, 200) == 0 && heap_snapshot(&after) == 0);
 CHECK(before.count == after.count);
 for (int i = 0; i < before.count; i++) {
  long kept = after.objects[i] - before.objects[i];
  printf("PERF-METADATA %s class=%ld objects=%ld kept-bytes=%ld\n", backend, before.size[i], kept, kept * before.size[i]);
  CHECK(kept <= 0);
 }
 printf("PERF-METADATA %s large-pages=%ld\n", backend, after.large - before.large);
 CHECK(after.large <= before.large);
 CHECK(close(fd) == 0);
 return 0;
}

static int copied_identity(const char *path)
{
 struct stat file;
 CHECK(stat(path, &file) == 0);
 CHECK(file.st_uid == 321 && file.st_gid == 654 && (file.st_mode & 07777) == 0600);
 CHECK(file.st_atim.tv_sec == 1700000000 && file.st_mtim.tv_sec == 1700000001);
 return 0;
}

static int exercise(const char *path, int persistent)
{
 int fd = open(path, O_CREAT | O_EXCL | O_RDWR, 0600);
 CHECK(fd >= 0);
 unsigned char got[32];
 CHECK(fsetxattr(fd, "user.binary", payload, sizeof(payload), XATTR_CREATE) == 0);
 EXPECT_ERROR(fsetxattr(fd, "user.binary", payload, sizeof(payload), XATTR_CREATE), EEXIST);
 EXPECT_ERROR(fsetxattr(fd, "user.missing", payload, sizeof(payload), XATTR_REPLACE), ENODATA);
 CHECK(fgetxattr(fd, "user.binary", got, sizeof(got)) == sizeof(payload));
 CHECK(memcmp(got, payload, sizeof(payload)) == 0);
 EXPECT_ERROR(fsetxattr(fd, "user.binary", (void *)1, 1, 0), EFAULT);
 EXPECT_ERROR(fgetxattr(fd, "user.binary", (void *)1, sizeof(got)), EFAULT);
 EXPECT_ERROR(fsetxattr(fd, "user.binary", payload, 65537, 0), E2BIG);
 EXPECT_ERROR(fgetxattr(fd, "user.binary", got, 1), ERANGE);
 CHECK(fsetxattr(fd, "user.empty", NULL, 0, 0) == 0);
 CHECK(fgetxattr(fd, "user.empty", NULL, 0) == 0);
 CHECK(fremovexattr(fd, "user.empty") == 0);
 EXPECT_ERROR(fremovexattr(fd, "user.empty"), ENODATA);
 EXPECT_ERROR(fsetxattr(fd, "user.", payload, sizeof(payload), 0), EINVAL);
 EXPECT_ERROR(fsetxattr(fd, "unsupported.name", payload, sizeof(payload), 0), EOPNOTSUPP);
 EXPECT_ERROR(fsetxattr(fd, "system.unsupported", payload, sizeof(payload), 0), EOPNOTSUPP);
 EXPECT_ERROR(fsetxattr(fd, "user.binary", payload, sizeof(payload), 4), EINVAL);
 CHECK(fsetxattr(fd, "trusted.secret", "admin", 5, 0) == 0);
 CHECK(fsetxattr(fd, "security.test", "policy", 6, 0) == 0);
 CHECK(fsetxattr(fd, "user.\xc3\xa9", "utf8", 4, 0) == 0);
 char names[1024], long_name[256];
 memset(long_name, 'x', sizeof(long_name));
 memcpy(long_name, "user.", 5);
 long_name[255] = 0;
 CHECK(fsetxattr(fd, long_name, payload, sizeof(payload), 0) == 0);
 CHECK(fgetxattr(fd, long_name, got, sizeof(got)) == sizeof(payload));
 CHECK(fremovexattr(fd, long_name) == 0);
 CHECK(flistxattr(fd, NULL, 0) > 0);
 EXPECT_ERROR(flistxattr(fd, names, 1), ERANGE);
 CHECK(flistxattr(fd, names, sizeof(names)) > 0);
 EXPECT_ERROR(flistxattr(fd, (void *)1, sizeof(names)), EFAULT);
 if (persistent) {
  char large[4096] = {0};
  EXPECT_ERROR(fsetxattr(fd, "user.binary", large, sizeof(large), 0), ENOSPC);
  CHECK(fgetxattr(fd, "user.binary", got, sizeof(got)) == sizeof(payload));
  CHECK(memcmp(got, payload, sizeof(payload)) == 0);
 }
 pid_t child = fork();
 CHECK(child >= 0);
 if (child == 0) {
  CHECK(setgid(1000) == 0 && setuid(1000) == 0);
  EXPECT_ERROR(fgetxattr(fd, "user.binary", got, sizeof(got)), EACCES);
  EXPECT_ERROR(fgetxattr(fd, "trusted.secret", got, sizeof(got)), ENODATA);
  EXPECT_ERROR(fsetxattr(fd, "trusted.secret", "x", 1, 0), EPERM);
  EXPECT_ERROR(fsetxattr(fd, "security.test", "x", 1, 0), EPERM);
  ssize_t length = flistxattr(fd, names, sizeof(names));
  CHECK(length > 0);
  for (ssize_t i = 0; i < length; i += strlen(names + i) + 1)
   CHECK(strcmp(names + i, "trusted.secret") != 0);
  _exit(0);
 }
 int status = 0;
 CHECK(waitpid(child, &status, 0) == child && WIFEXITED(status) && WEXITSTATUS(status) == 0);
 CHECK(operations(fd, 200) == 0);
 struct heap before, after;
 CHECK(heap_snapshot(&before) == 0);
 CHECK(operations(fd, 200) == 0);
 CHECK(heap_snapshot(&after) == 0);
 CHECK(before.count == after.count);
 for (int i = 0; i < before.count; i++) {
  long kept = after.objects[i] - before.objects[i];
  printf("PERF-XATTR %s class=%ld objects=%ld kept-bytes=%ld\n", persistent ? "ext2" : "tmpfs", before.size[i], kept, kept * before.size[i]);
  CHECK(kept <= 0);
 }
 printf("PERF-XATTR %s large-pages=%ld\n", persistent ? "ext2" : "tmpfs", after.large - before.large);
 CHECK(after.large <= before.large);
 CHECK(fsync(fd) == 0 && close(fd) == 0);
 return 0;
}

static int block_release(void)
{
 struct statfs before, after;
 struct stat inode;
 CHECK(statfs("/root", &before) == 0);
 int fd = open("/root/xattr-disposable", O_CREAT | O_EXCL | O_RDWR, 0600);
 CHECK(fd >= 0);
 CHECK(fsetxattr(fd, "user.only", payload, sizeof(payload), 0) == 0);
 CHECK(fstat(fd, &inode) == 0 && inode.st_blocks == 8);
 CHECK(fremovexattr(fd, "user.only") == 0);
 CHECK(fstat(fd, &inode) == 0 && inode.st_blocks == 0);
 CHECK(fsetxattr(fd, "user.only", payload, sizeof(payload), 0) == 0);
 CHECK(unlink("/root/xattr-disposable") == 0);
 CHECK(fgetxattr(fd, "user.only", NULL, 0) == sizeof(payload));
 CHECK(close(fd) == 0);
 CHECK(statfs("/root", &after) == 0);
 CHECK(before.f_bfree == after.f_bfree);
 return 0;
}

#define COPY_FILES 64
#define COPY_ATTRIBUTES 12
struct copy_race {
 int fds[COPY_FILES];
 atomic_int stop, failed, changes;
};

static void *change_source_attributes(void *argument)
{
 struct copy_race *race = argument;
 while (!atomic_load(&race->stop)) {
  for (int i = 0; i < COPY_FILES && !atomic_load(&race->stop); i++) {
   for (int j = 0; j < COPY_ATTRIBUTES; j++) {
    char name[96];
    snprintf(name, sizeof(name), "user.concurrent-%02d-long-name-for-copy-ownership", j);
    if ((fremovexattr(race->fds[i], name) != 0 && errno != ENODATA)
        || fsetxattr(race->fds[i], name, payload, sizeof(payload), 0) != 0) {
     atomic_store(&race->failed, 1);
     return NULL;
    }
    atomic_fetch_add(&race->changes, 1);
   }
  }
 }
 return NULL;
}

static int concurrent_copy_up(const char *lower_base, const char *upper_base, const char *label)
{
 char lower[192], upper[192], work[192], merged[192], options[768];
 snprintf(lower, sizeof(lower), "%s/xattr-%s-lower", lower_base, label);
 snprintf(upper, sizeof(upper), "%s/xattr-%s-upper", upper_base, label);
 snprintf(work, sizeof(work), "%s/xattr-%s-work", upper_base, label);
 snprintf(merged, sizeof(merged), "/tmp/xattr-tmpfs/xattr-%s-merged", label);
 CHECK(mkdir(lower, 0700) == 0 && mkdir(upper, 0700) == 0);
 CHECK(mkdir(work, 0700) == 0 && mkdir(merged, 0700) == 0);
 struct copy_race race = {0};
 for (int i = 0; i < COPY_FILES; i++) {
  char path[256], name[96];
  snprintf(path, sizeof(path), "%s/file-%02d", lower, i);
  race.fds[i] = open(path, O_CREAT | O_EXCL | O_RDWR, 0600);
  CHECK(race.fds[i] >= 0);
  CHECK(fsetxattr(race.fds[i], "user.stable", payload, sizeof(payload), 0) == 0);
  CHECK(fsetxattr(race.fds[i], "trusted.copy", payload, sizeof(payload), 0) == 0);
  CHECK(fsetxattr(race.fds[i], "security.copy", payload, sizeof(payload), 0) == 0);
  CHECK(fsetxattr(race.fds[i], "trusted.overlay.hidden", "y", 1, 0) == 0);
  for (int j = 0; j < COPY_ATTRIBUTES; j++) {
   snprintf(name, sizeof(name), "user.concurrent-%02d-long-name-for-copy-ownership", j);
   CHECK(fsetxattr(race.fds[i], name, payload, sizeof(payload), 0) == 0);
  }
  const struct timespec times[2] = {{1700000000, 0}, {1700000001, 0}};
  CHECK(fchown(race.fds[i], 321, 654) == 0 && futimens(race.fds[i], times) == 0);
 }
 int capacity_fd = -1;
 int identity_fd = -1;
 char capacity_lower[256], capacity_upper[256], capacity_merged[256];
 char identity_lower[256], identity_upper[256], identity_merged[256];
 if (strcmp(label, "tmpfs-ext2") == 0) {
  char large[4096] = {0};
  snprintf(capacity_lower, sizeof(capacity_lower), "%s/too-large", lower);
  snprintf(capacity_upper, sizeof(capacity_upper), "%s/too-large", upper);
  snprintf(capacity_merged, sizeof(capacity_merged), "%s/too-large", merged);
  capacity_fd = open(capacity_lower, O_CREAT | O_EXCL | O_RDWR, 0600);
  CHECK(capacity_fd >= 0);
  CHECK(fsetxattr(capacity_fd, "user.first", payload, sizeof(payload), 0) == 0);
  CHECK(fsetxattr(capacity_fd, "user.large", large, sizeof(large), 0) == 0);
  snprintf(identity_lower, sizeof(identity_lower), "%s/large-uid", lower);
  snprintf(identity_upper, sizeof(identity_upper), "%s/large-uid", upper);
  snprintf(identity_merged, sizeof(identity_merged), "%s/large-uid", merged);
  identity_fd = open(identity_lower, O_CREAT | O_EXCL | O_RDWR, 0600);
  CHECK(identity_fd >= 0 && fchown(identity_fd, 70000, 654) == 0);
  CHECK(fsetxattr(identity_fd, "user.first", payload, sizeof(payload), 0) == 0);
 }
 snprintf(options, sizeof(options), "lowerdir=%s,upperdir=%s,workdir=%s", lower, upper, work);
 CHECK(mount("overlay", merged, "overlay", 0, options) == 0);
 if (capacity_fd >= 0) {
  struct stat ignored;
  struct statfs before_failure, after_failure;
  CHECK(statfs(upper, &before_failure) == 0);
  EXPECT_ERROR(setxattr(capacity_merged, "user.trigger", payload, sizeof(payload), 0), ENOSPC);
  EXPECT_ERROR(stat(capacity_upper, &ignored), ENOENT);
  CHECK(statfs(upper, &after_failure) == 0);
  CHECK(before_failure.f_bfree == after_failure.f_bfree && before_failure.f_ffree == after_failure.f_ffree);
  CHECK(fgetxattr(capacity_fd, "user.large", NULL, 0) == 4096);
  CHECK(fremovexattr(capacity_fd, "user.large") == 0);
  CHECK(setxattr(capacity_merged, "user.trigger", payload, sizeof(payload), 0) == 0);
  CHECK(getxattr(capacity_upper, "user.first", NULL, 0) == sizeof(payload));
  CHECK(close(capacity_fd) == 0);
 }
 if (identity_fd >= 0) {
  struct stat ignored;
  struct statfs before_failure, after_failure;
  CHECK(statfs(upper, &before_failure) == 0);
  EXPECT_ERROR(setxattr(identity_merged, "user.trigger", payload, sizeof(payload), 0), EOVERFLOW);
  EXPECT_ERROR(stat(identity_upper, &ignored), ENOENT);
  CHECK(statfs(upper, &after_failure) == 0);
  CHECK(before_failure.f_bfree == after_failure.f_bfree && before_failure.f_ffree == after_failure.f_ffree);
  const struct timespec times[2] = {{1700000000, 0}, {1700000001, 0}};
  CHECK(fchown(identity_fd, 321, 654) == 0 && futimens(identity_fd, times) == 0);
  CHECK(setxattr(identity_merged, "user.trigger", payload, sizeof(payload), 0) == 0);
  CHECK(copied_identity(identity_upper) == 0 && close(identity_fd) == 0);
 }
 pthread_t writer;
 CHECK(pthread_create(&writer, NULL, change_source_attributes, &race) == 0);
 while (!atomic_load(&race.changes) && !atomic_load(&race.failed)) sched_yield();
 CHECK(!atomic_load(&race.failed));
 for (int i = 0; i < COPY_FILES; i++) {
  char path[256];
  snprintf(path, sizeof(path), "%s/file-%02d", merged, i);
  CHECK(setxattr(path, "user.stable", payload, sizeof(payload), XATTR_REPLACE) == 0);
  sched_yield();
 }
 atomic_store(&race.stop, 1);
 CHECK(pthread_join(writer, NULL) == 0 && !atomic_load(&race.failed) && atomic_load(&race.changes) > 0);
 for (int i = 0; i < COPY_FILES; i++) {
  char path[256], names[2048];
  unsigned char got[32];
  snprintf(path, sizeof(path), "%s/file-%02d", upper, i);
  int fd = open(path, O_RDONLY);
  CHECK(fd >= 0);
  CHECK(copied_identity(path) == 0);
  CHECK(fgetxattr(fd, "user.stable", got, sizeof(got)) == sizeof(payload));
  CHECK(memcmp(got, payload, sizeof(payload)) == 0);
  EXPECT_ERROR(fgetxattr(fd, "trusted.overlay.hidden", got, sizeof(got)), ENODATA);
  ssize_t length = flistxattr(fd, names, sizeof(names));
  CHECK(length > 0);
  for (ssize_t offset = 0; offset < length; offset += strlen(names + offset) + 1) {
   CHECK(strcmp(names + offset, "user.stable") == 0
         || strcmp(names + offset, "trusted.copy") == 0
         || strcmp(names + offset, "security.copy") == 0
         || strncmp(names + offset, "user.concurrent-", 16) == 0);
   CHECK(fgetxattr(fd, names + offset, got, sizeof(got)) == sizeof(payload));
   CHECK(memcmp(got, payload, sizeof(payload)) == 0);
  }
  CHECK(close(fd) == 0 && close(race.fds[i]) == 0);
 }
 CHECK(umount(merged) == 0);
 printf("XATTR: CONCURRENT COPY-UP %s PASS\n", label);
 return 0;
}

int main(void)
{
 setbuf(stdout, NULL);
 puts("XATTR: START");
 struct statfs filesystem;
 CHECK(statfs("/root", &filesystem) == 0 && filesystem.f_type == 0xef53);
 // A persistent x86 root keeps /tmp on ext2. Mount the intended tmpfs
 // backend explicitly so both architectures exercise the same copy-up case.
 CHECK(mount("tmpfs", "/tmp", "tmpfs", 0, "") == 0);
 int fd = open("/root/xattr-marker", O_RDONLY);
 if (fd >= 0) {
  unsigned char got[32];
  CHECK(fgetxattr(fd, "user.binary", got, sizeof(got)) == sizeof(payload));
  CHECK(memcmp(got, payload, sizeof(payload)) == 0);
  CHECK(fgetxattr(fd, "trusted.secret", got, sizeof(got)) == 5);
  CHECK(memcmp(got, "admin", 5) == 0);
  CHECK(fgetxattr(fd, "security.test", got, sizeof(got)) == 6);
  char target[32];
  CHECK(readlink("/root/xattr-link", target, sizeof(target)) == 12);
  CHECK(memcmp(target, "xattr-marker", 12) == 0);
  CHECK(lgetxattr("/root/xattr-link", "security.test", got, sizeof(got)) == 4);
  CHECK(close(fd) == 0);
  const char *copies[] = {"/root/xattr-tmpfs-ext2-upper/file-00", "/root/xattr-ext2-ext2-upper/file-00"};
  for (unsigned i = 0; i < sizeof(copies) / sizeof(copies[0]); i++) {
   CHECK(copied_identity(copies[i]) == 0);
   CHECK(getxattr(copies[i], "user.stable", got, sizeof(got)) == sizeof(payload));
   CHECK(memcmp(got, payload, sizeof(payload)) == 0);
   CHECK(getxattr(copies[i], "trusted.copy", got, sizeof(got)) == sizeof(payload));
   CHECK(getxattr(copies[i], "security.copy", got, sizeof(got)) == sizeof(payload));
  }
  puts("XATTR: PASS");
  reboot(RB_POWER_OFF);
  for (;;) pause();
 }
 CHECK(errno == ENOENT);
 CHECK(mkdir("/tmp/xattr-tmpfs", 0700) == 0);
 CHECK(mount("tmpfs", "/tmp/xattr-tmpfs", "tmpfs", 0, NULL) == 0);
 CHECK(statfs("/tmp/xattr-tmpfs", &filesystem) == 0 && filesystem.f_type == 0x01021994);
 CHECK(exercise("/tmp/xattr-tmpfs/xattr-file", 0) == 0);
 CHECK(exercise("/root/xattr-marker", 1) == 0);
 CHECK(metadata_measure("/tmp/xattr-tmpfs/xattr-file", "tmpfs") == 0);
 CHECK(metadata_measure("/root/xattr-marker", "ext2") == 0);
 CHECK(concurrent_copy_up("/tmp/xattr-tmpfs", "/tmp/xattr-tmpfs", "tmpfs-tmpfs") == 0);
 CHECK(concurrent_copy_up("/tmp/xattr-tmpfs", "/root", "tmpfs-ext2") == 0);
 CHECK(concurrent_copy_up("/root", "/tmp/xattr-tmpfs", "ext2-tmpfs") == 0);
 CHECK(concurrent_copy_up("/root", "/root", "ext2-ext2") == 0);
 CHECK(block_release() == 0);
 CHECK(symlink("xattr-marker", "/root/xattr-link") == 0);
 CHECK(lsetxattr("/root/xattr-link", "security.test", "link", 4, 0) == 0);
 puts("XATTR: SYNC");
 sync();
 puts("XATTR: REBOOT");
 reboot(RB_AUTOBOOT);
 CHECK(0);
}
