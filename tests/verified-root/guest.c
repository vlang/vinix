/* SPDX-License-Identifier: GPL-2.0-or-later */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <unistd.h>

#define CHECK(x) do { if (!(x)) { printf("VERIFIED ROOT: FAIL line=%d errno=%d (%s)\n", __LINE__, errno, #x); fflush(stdout); for (;;) pause(); } } while (0)
#define ERROR(call, expected) do { errno = 0; CHECK((call) == -1 && errno == (expected)); } while (0)
static unsigned char bytes[4096];
struct slab_snapshot {
	unsigned long long size[32], live[32], large_pages;
	unsigned count;
};

static void slab_snapshot(int fd, struct slab_snapshot *snapshot)
{
	char text[4096];
	memset(snapshot, 0, sizeof(*snapshot));
	CHECK(lseek(fd, 0, SEEK_SET) == 0);
	ssize_t count = read(fd, text, sizeof(text) - 1);
	CHECK(count > 0);
	text[count] = 0;
	int saw_large = 0;
	for (char *line = text; line && *line;) {
		unsigned long long size, live, pages;
		if (sscanf(line, "size-%*u %llu %llu %llu", &size, &live, &pages) == 3) {
			CHECK(snapshot->count < 32);
			snapshot->size[snapshot->count] = size;
			snapshot->live[snapshot->count++] = live;
		} else if (sscanf(line, "large - - %llu", &pages) == 1) {
			snapshot->large_pages = pages;
			saw_large = 1;
		}
		line = strchr(line, '\n');
		if (line) line++;
	}
	CHECK(snapshot->count > 0 && saw_large);
}

static void retention(int fd, unsigned long block, int mappings)
{
	int slab = open("/proc/slabinfo", O_RDONLY);
	CHECK(slab >= 0);
	struct slab_snapshot before, after;
	for (int warm = 0; warm < 20; warm++) {
		if (mappings) {
			void *map = mmap(NULL, 4096, PROT_READ, MAP_SHARED, fd, 0);
			CHECK(map != MAP_FAILED && *(unsigned char *)map == 'v');
			CHECK(munmap(map, 4096) == 0);
		} else CHECK(pread(fd, bytes, sizeof(bytes), (off_t)block * 4096) == (ssize_t)sizeof(bytes));
		slab_snapshot(slab, &before);
	}
	CHECK(usleep(20000) == 0);
	slab_snapshot(slab, &before);
	for (int read = 0; read < 1000; read++) {
		if (mappings) {
			void *map = mmap(NULL, 4096, PROT_READ, MAP_SHARED, fd, 0);
			CHECK(map != MAP_FAILED && *(unsigned char *)map == 'v');
			CHECK(munmap(map, 4096) == 0);
		} else CHECK(pread(fd, bytes, sizeof(bytes), (off_t)block * 4096) == (ssize_t)sizeof(bytes));
	}
	CHECK(usleep(20000) == 0);
	slab_snapshot(slab, &after);
	CHECK(close(slab) == 0);
	CHECK(before.count == after.count);
	long long retained_bytes = 0, retained_objects = 0;
	int flat = after.large_pages <= before.large_pages;
	for (unsigned i = 0; i < before.count; i++) {
		CHECK(before.size[i] == after.size[i]);
		long long objects = (long long)after.live[i] - (long long)before.live[i];
		if (objects) printf("VERIFIED ROOT: SLAB path=%s size=%llu retained_objects=%lld operations=1000\n",
		                    mappings ? "mmap" : "read", before.size[i], objects);
		retained_objects += objects;
		retained_bytes += objects * (long long)before.size[i];
		if (objects > 0) flat = 0;
	}
	printf("VERIFIED ROOT: RETENTION path=%s retained_bytes=%lld retained_objects=%lld large_pages=%lld operations=1000\n",
	       mappings ? "mmap" : "read", retained_bytes, retained_objects,
	       (long long)after.large_pages - (long long)before.large_pages);
	CHECK(flat);
}

static void serial(void)
{
	int fd = open("/dev/com1", O_RDWR);
	if (fd < 0) fd = open("/dev/console", O_RDWR);
	if (fd >= 0) { dup2(fd, 0); dup2(fd, 1); dup2(fd, 2); if (fd > 2) close(fd); }
	setvbuf(stdout, NULL, _IONBF, 0);
}

static unsigned long number(const char *path)
{
	char text[80] = {0};
	int fd = open(path, O_RDONLY);
	CHECK(fd >= 0);
	CHECK(read(fd, text, sizeof(text) - 1) > 0);
	close(fd);
	return strtoul(text, NULL, 10);
}

static void check_payload(int fd)
{
	CHECK(pread(fd, bytes, sizeof(bytes), 0) == (ssize_t)sizeof(bytes));
	for (size_t i = 0; i < sizeof(bytes); i++) CHECK(bytes[i] == 'v');
}

static void writable(const char *path)
{
	int fd = open(path, O_CREAT | O_EXCL | O_RDWR, 0600);
	CHECK(fd >= 0);
	CHECK(write(fd, "RAM", 3) == 3);
	CHECK(close(fd) == 0);
}

int main(void)
{
	serial();
	puts("VERIFIED ROOT: START");
	ERROR(access("/bootstrap-only", F_OK), ENOENT);
	struct stat st;
	CHECK(stat("/sys/devices/system/cpu", &st) == 0 && S_ISDIR(st.st_mode));
	CHECK(stat("/proc/meminfo", &st) == 0);
	int fd = open("/payload", O_RDONLY);
	CHECK(fd >= 0);
	check_payload(fd);
	ERROR(open("/payload", O_RDWR), EROFS);
	ERROR(open("/payload", O_WRONLY | O_TRUNC), EROFS);
	ERROR(open("/new", O_CREAT | O_WRONLY, 0600), EROFS);
	ERROR(chmod("/payload", 0600), EROFS);
	ERROR(unlink("/payload"), EROFS);
	ERROR(rename("/payload", "/renamed"), EROFS);
	errno = 0;
	CHECK(mmap(NULL, 4096, PROT_WRITE, MAP_SHARED, fd, 0) == MAP_FAILED && errno == EACCES);
	void *map = mmap(NULL, 4096, PROT_READ, MAP_SHARED, fd, 0);
	CHECK(map != MAP_FAILED);
	CHECK(*(unsigned char *)map == 'v');
	CHECK(msync(map, 4096, MS_SYNC) == 0);
	CHECK(fsync(fd) == 0);
	ERROR(mprotect(map, 4096, PROT_READ | PROT_WRITE), EACCES);
	CHECK(munmap(map, 4096) == 0);
	map = mmap(NULL, 4096, PROT_NONE, MAP_SHARED, fd, 0);
	CHECK(map != MAP_FAILED);
	ERROR(mprotect(map, 4096, PROT_WRITE), EACCES);
	CHECK(munmap(map, 4096) == 0);
	map = mmap(NULL, 4096, PROT_READ | PROT_WRITE, MAP_PRIVATE, fd, 0);
	CHECK(map != MAP_FAILED);
	*(unsigned char *)map = 'x';
	CHECK(munmap(map, 4096) == 0);
	check_payload(fd);
	ERROR(mount("", "/", "", MS_REMOUNT, NULL), EROFS);
	CHECK(mkdir("/tmp/bind", 0700) == 0);
	CHECK(mount("/", "/tmp/bind", "", MS_BIND, NULL) == 0);
	ERROR(open("/tmp/bind/payload", O_RDWR), EROFS);
	ERROR(mount("", "/tmp/bind", "", MS_REMOUNT | MS_BIND, NULL), EROFS);
	CHECK(mkdir("/tmp/second", 0700) == 0);
	CHECK(mount("/dev/verity-root", "/tmp/second", "ext2", 0, NULL) == 0);
	ERROR(open("/tmp/second/payload", O_RDWR), EROFS);
	ERROR(mount("", "/tmp/second", "", MS_REMOUNT, NULL), EROFS);
	CHECK(mkdir("/tmp/wrong-source", 0700) == 0);
	char raw_path[80] = {0};
	int raw_name = open("/raw-device", O_RDONLY);
	CHECK(raw_name >= 0);
	CHECK(read(raw_name, raw_path, sizeof(raw_path) - 1) > 0);
	close(raw_name);
	ERROR(mount(raw_path, "/tmp/wrong-source", "ext2", 0, NULL), ENODEV);
	writable("/tmp/runtime"); writable("/run/runtime");
	writable("/var/runtime"); writable("/root/runtime");
	unsigned long block = number("/probe-block");
	unsigned long count = number("/data-blocks");
	int device = open("/dev/verity-root", O_RDWR);
	CHECK(device >= 0);
	CHECK(fstat(device, &st) == 0 && st.st_size == (off_t)count * 4096);
	ERROR(pwrite(device, bytes, 1, 0), EROFS);
	CHECK(pread(device, bytes, 1, (off_t)count * 4096) == 0);
	CHECK(pread(device, bytes, sizeof(bytes), (off_t)block * 4096) == (ssize_t)sizeof(bytes));
	retention(device, block, 0);
	retention(fd, 0, 1);
	puts("VERIFIED ROOT: READONLY PASS");
	printf("VERIFIED ROOT: READY mutation=%lu\n", block);
	/* Poll the verified device rather than relying on platform console input.
	 * The host changes only this block after the READY diagnostic. */
	int rejected = 0;
	for (int attempt = 0; attempt < 600; attempt++) {
		errno = 0;
		ssize_t result = pread(device, bytes, sizeof(bytes), (off_t)block * 4096);
		if (result == -1 && errno == EIO) { rejected = 1; break; }
		CHECK(result == (ssize_t)sizeof(bytes));
		CHECK(usleep(100000) == 0);
	}
	CHECK(rejected);
	/* Previously authenticated cached bytes stay valid. A new backing read
	 * must authenticate again, including after clean page-cache eviction. */
	check_payload(fd);
	ERROR(pread(device, bytes, sizeof(bytes), (off_t)block * 4096), EIO);
	CHECK(posix_fadvise(fd, 0, 4096, POSIX_FADV_DONTNEED) == 0);
	ERROR(pread(fd, bytes, sizeof(bytes), 0), EIO);
	puts("VERIFIED ROOT: PASS cached data stayed authenticated; changed disk reads rejected");
	for (;;) pause();
}
