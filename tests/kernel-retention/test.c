// SPDX-License-Identifier: GPL-2.0-or-later
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <unistd.h>

#define CHECK(c) do { if (!(c)) { printf("FAIL: retention line=%d errno=%d\n", __LINE__, errno); return 1; } } while (0)
#define FILES 128
struct heap { long sizes[32], objects[32], large; int count; };
struct dirent64 { uint64_t ino; int64_t offset; uint16_t length; uint8_t type; char name[]; };

static int snapshot(struct heap *heap)
{
 FILE *file = fopen("/proc/slabinfo", "r");
 CHECK(file != NULL);
 char line[256]; int saw_large = 0;
 memset(heap, 0, sizeof(*heap));
 while (fgets(line, sizeof(line), file)) {
  long label, size, objects, pages;
  if (sscanf(line, "size-%ld %ld %ld %ld", &label, &size, &objects, &pages) == 4 && label == size) {
   CHECK(heap->count < 32);
   heap->sizes[heap->count] = size; heap->objects[heap->count++] = objects;
  } else if (sscanf(line, "large - - %ld", &pages) == 1) {
   heap->large = pages; saw_large = 1;
  }
 }
 CHECK(fclose(file) == 0);
#ifdef __aarch64__
 CHECK(heap->count == 18 && saw_large);
#else
 CHECK(heap->count == 14 && saw_large);
#endif
 return 0;
}

static int listing(void)
{
 int fd = open("/tmp/retention/entries", O_RDONLY | O_DIRECTORY);
 CHECK(fd >= 0);
 unsigned char buffer[128], seen[FILES] = {0}; int total = 0;
 errno = 0;
 CHECK(syscall(SYS_getdents64, fd, buffer, 1) == -1 && errno == EINVAL);
 for (;;) {
  long length = syscall(SYS_getdents64, fd, buffer, sizeof(buffer));
  CHECK(length >= 0);
  if (!length) break;
  for (long at = 0; at < length;) {
   CHECK(length - at >= 20);
   struct dirent64 *entry = (void *)(buffer + at);
   CHECK(entry->length >= 20 && entry->length <= length - at && !(entry->length & 7));
   CHECK(memchr(entry->name, 0, entry->length - 19) != NULL);
   if (strcmp(entry->name, ".") && strcmp(entry->name, "..")) {
    unsigned number; char trailing;
    CHECK(sscanf(entry->name, "file-%u%c", &number, &trailing) == 1 && number < FILES && !seen[number]);
    seen[number] = 1; total++;
   }
   at += entry->length;
  }
 }
 CHECK(total == FILES && close(fd) == 0);
 return 0;
}

static int proc_reads(void)
{
 const char *paths[] = {"/proc/self/stat", "/proc/self/status", "/proc/meminfo", "/proc/uptime", "/proc/self/maps", "/proc/stat"};
 char buffer[4096];
 for (unsigned i = 0; i < sizeof(paths) / sizeof(paths[0]); i++) {
  int fd = open(paths[i], O_RDONLY); CHECK(fd >= 0);
  long count; long total = 0;
  while ((count = read(fd, buffer, sizeof(buffer))) > 0) total += count;
  CHECK(count == 0 && total > 0 && close(fd) == 0);
 }
 return 0;
}

static void trace(const char *op, int start)
{
 FILE *file = fopen(start ? "/proc/allocstart" : "/proc/allocsites", "r");
 if (!file) return;
 char line[512];
 while (fgets(line, sizeof(line), file)) {
  if (!start) printf("PERF-SITE retention op=%s %s", op, line);
 }
 fclose(file);
}

static int measure(const char *name, int (*operation)(void))
{
 for (int i = 0; i < 20; i++) CHECK(operation() == 0);
 struct heap before, after;
 trace(name, 1);
 CHECK(snapshot(&before) == 0);
 for (int i = 0; i < 200; i++) CHECK(operation() == 0);
 CHECK(snapshot(&after) == 0 && before.count == after.count);
 int growth = 0;
 for (int i = 0; i < before.count; i++) {
  CHECK(before.sizes[i] == after.sizes[i]);
  long kept = after.objects[i] - before.objects[i];
  printf("PERF-RETENTION op=%s class=%ld objects=%ld bytes=%ld\n", name, before.sizes[i], kept, kept * before.sizes[i]);
  growth |= kept > 0;
 }
 printf("PERF-RETENTION op=%s large-pages=%ld\n", name, after.large - before.large);
 growth |= after.large > before.large;
 trace(name, 0);
 return growth;
}

int main(void)
{
 setbuf(stdout, NULL);
 CHECK(mkdir("/tmp/retention", 0700) == 0);
 CHECK(mount("tmpfs", "/tmp/retention", "tmpfs", 0, NULL) == 0);
 CHECK(mkdir("/tmp/retention/entries", 0700) == 0);
 for (int i = 0; i < FILES; i++) {
  char name[96]; snprintf(name, sizeof(name), "/tmp/retention/entries/file-%03d", i);
  int fd = open(name, O_CREAT | O_EXCL | O_RDWR, 0600); CHECK(fd >= 0 && close(fd) == 0);
 }
 int listing_failed = measure("getdents64", listing);
 int proc_failed = measure("proc_read", proc_reads);
 CHECK(!listing_failed && !proc_failed);
 puts("KERNEL RETENTION: PASS");
 for (;;) pause();
}
