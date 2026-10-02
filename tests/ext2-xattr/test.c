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
 EXPECT_ERROR(fsetxattr(fd, "system.posix_acl_access", payload, sizeof(payload), 0), EOPNOTSUPP);
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

static int concurrent_copy_up(void)
{
 CHECK(mkdir("/tmp/xattr-lower", 0700) == 0);
 CHECK(mkdir("/tmp/xattr-upper", 0700) == 0);
 CHECK(mkdir("/tmp/xattr-work", 0700) == 0);
 CHECK(mkdir("/tmp/xattr-merged", 0700) == 0);
 struct copy_race race = {0};
 for (int i = 0; i < COPY_FILES; i++) {
  char path[96], name[96];
  snprintf(path, sizeof(path), "/tmp/xattr-lower/file-%02d", i);
  race.fds[i] = open(path, O_CREAT | O_EXCL | O_RDWR, 0600);
  CHECK(race.fds[i] >= 0);
  CHECK(fsetxattr(race.fds[i], "user.stable", payload, sizeof(payload), 0) == 0);
  CHECK(fsetxattr(race.fds[i], "trusted.overlay.hidden", "y", 1, 0) == 0);
  for (int j = 0; j < COPY_ATTRIBUTES; j++) {
   snprintf(name, sizeof(name), "user.concurrent-%02d-long-name-for-copy-ownership", j);
   CHECK(fsetxattr(race.fds[i], name, payload, sizeof(payload), 0) == 0);
  }
 }
 CHECK(mount("overlay", "/tmp/xattr-merged", "overlay", 0,
             "lowerdir=/tmp/xattr-lower,upperdir=/tmp/xattr-upper,workdir=/tmp/xattr-work") == 0);
 pthread_t writer;
 CHECK(pthread_create(&writer, NULL, change_source_attributes, &race) == 0);
 while (!atomic_load(&race.changes) && !atomic_load(&race.failed)) sched_yield();
 CHECK(!atomic_load(&race.failed));
 for (int i = 0; i < COPY_FILES; i++) {
  char path[96];
  snprintf(path, sizeof(path), "/tmp/xattr-merged/file-%02d", i);
  int fd = open(path, O_WRONLY);
  CHECK(fd >= 0 && write(fd, "x", 1) == 1 && close(fd) == 0);
  sched_yield();
 }
 atomic_store(&race.stop, 1);
 CHECK(pthread_join(writer, NULL) == 0 && !atomic_load(&race.failed) && atomic_load(&race.changes) > 0);
 for (int i = 0; i < COPY_FILES; i++) {
  char path[96], names[2048];
  unsigned char got[32];
  snprintf(path, sizeof(path), "/tmp/xattr-upper/file-%02d", i);
  int fd = open(path, O_RDONLY);
  CHECK(fd >= 0);
  CHECK(fgetxattr(fd, "user.stable", got, sizeof(got)) == sizeof(payload));
  CHECK(memcmp(got, payload, sizeof(payload)) == 0);
  EXPECT_ERROR(fgetxattr(fd, "trusted.overlay.hidden", got, sizeof(got)), ENODATA);
  ssize_t length = flistxattr(fd, names, sizeof(names));
  CHECK(length > 0);
  for (ssize_t offset = 0; offset < length; offset += strlen(names + offset) + 1) {
   CHECK(strcmp(names + offset, "user.stable") == 0
         || strncmp(names + offset, "user.concurrent-", 16) == 0);
   CHECK(fgetxattr(fd, names + offset, got, sizeof(got)) == sizeof(payload));
   CHECK(memcmp(got, payload, sizeof(payload)) == 0);
  }
  CHECK(close(fd) == 0 && close(race.fds[i]) == 0);
 }
 CHECK(umount("/tmp/xattr-merged") == 0);
 puts("XATTR: CONCURRENT COPY-UP PASS");
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
  puts("XATTR: PASS");
  reboot(RB_POWER_OFF);
  for (;;) pause();
 }
 CHECK(errno == ENOENT);
 CHECK(exercise("/tmp/xattr-file", 0) == 0);
 CHECK(exercise("/root/xattr-marker", 1) == 0);
 CHECK(concurrent_copy_up() == 0);
 CHECK(block_release() == 0);
 CHECK(symlink("xattr-marker", "/root/xattr-link") == 0);
 CHECK(lsetxattr("/root/xattr-link", "security.test", "link", 4, 0) == 0);
 puts("XATTR: SYNC");
 sync();
 puts("XATTR: REBOOT");
 reboot(RB_AUTOBOOT);
 CHECK(0);
}
