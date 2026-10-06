// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

/* SPDX-License-Identifier: BSD-2-Clause
 * In-guest regression coverage for the VM, VFS, and Linux ABI fundamentals,
 * the same on both architectures. The binary is linked statically and
 * installed as PID 1: by scripts/run-aarch64.sh's --guest-init hook on arm64, and in
 * a throwaway ISO on amd64; see run.sh. */
#define _GNU_SOURCE
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <poll.h>
#include <pthread.h>
#include <sched.h>
#include <setjmp.h>
#include <signal.h>
#include <stdatomic.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/file.h>
#include <sys/inotify.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/mount.h>
#include <sys/random.h>
#include <sys/time.h>
#include <sys/resource.h>
#include <sys/select.h>
#include <sys/stat.h>
#include <sys/auxv.h>
#include <sys/eventfd.h>
#include <sys/epoll.h>
#include <sys/socket.h>
#include <sys/statfs.h>
#include <sys/sysinfo.h>
#include <sys/syscall.h>
#include <sys/time.h>
#include <sys/uio.h>
#include <sys/un.h>
#include <sys/wait.h>
#include <termios.h>
#include <ucontext.h>
#include <time.h>
#include <unistd.h>
#include "signalfixture-api.h"
#include "touchfixture-api.h"
#include "restartfixture-api.h"
#include "nanosleepfixture-api.h"
#include "blockedfixture-api.h"
#line 51 "test.c"

#define CHECK(expression) do {                                               \
	if (!(expression)) {                                                   \
		printf("QEMU CORE FAIL line %d: %s (errno=%d)\n",              \
		    __LINE__, #expression, errno);                               \
		return 1;                                                       \
	}                                                                       \
} while (0)

static const char *test_dir = "/root/vinix-qemu-core";
static const char *file_a = "/root/vinix-qemu-core/a";
static const char *file_b = "/root/vinix-qemu-core/b";
static const char *file_c = "/root/vinix-qemu-core/c";
static const char *surface_file = "/root/vinix-qemu-core/surface";
static const char *persist_file = "/root/vinix-qemu-core/persist";
static const char persist_payload[] = "vinix-ext2-cache-writeback-v1";
/* The same marker written the way a shell writes a file: buffered, closed, and
 * pushed out by sync(2) alone. Nothing else drains a small write from the
 * shared cache, so a restart used to lose it while the O_SYNC marker above
 * survived, which is exactly what made a persistent /root look empty. */
static const char *synced_file = "/root/vinix-qemu-core/synced";
static const char synced_payload[] = "vinix-ext2-sync-writeback-v1";
static volatile sig_atomic_t posix_timer_callbacks;
#line 75 "test.c"

static void posix_timer_callback(union sigval value)
{
	if (value.sival_int == 0x5649)
		posix_timer_callbacks++;
}

#line 87 "test.c"

int reap_ok(pid_t child)
{
	int status = -1;
	CHECK(child > 0);
	CHECK(waitpid(child, &status, 0) == child);
	CHECK(WIFEXITED(status) && WEXITSTATUS(status) == 0);
	return 0;
}

/* Return one for the verification boot, zero for a fresh volume, and minus
 * one for a malformed or unreadable persistence marker. */
static int verify_marker(const char *path, const char *payload, size_t length)
{
	int fd = open(path, O_RDONLY);
	if (fd < 0)
		return -1;
	char observed[64] = {0};
	if (length >= sizeof(observed)) {
		close(fd);
		errno = EINVAL;
		return -1;
	}
	ssize_t got = read(fd, observed, sizeof(observed));
	close(fd);
	if (got != (ssize_t)length || memcmp(observed, payload, length) != 0) {
		errno = EIO;
		return -1;
	}
	return unlink(path);
}

static int verify_persistence_boot(void)
{
	int fd = open(persist_file, O_RDONLY);
	if (fd < 0)
		return errno == ENOENT ? 0 : -1;
	close(fd);
	if (verify_marker(persist_file, persist_payload,
	        sizeof(persist_payload) - 1) != 0)
		return -1;
	if (verify_marker(synced_file, synced_payload,
	        sizeof(synced_payload) - 1) != 0)
		return -1;
	puts("VINIX QEMU CORE PERSIST: PASS");
	return 1;
}

static int test_random(void)
{
	unsigned char first[64] = {0};
	unsigned char second[64] = {0};
	unsigned char zero[64] = {0};
	CHECK(getrandom(first, sizeof(first), 0) == (ssize_t)sizeof(first));
	CHECK(getrandom(second, sizeof(second), 0) == (ssize_t)sizeof(second));
	CHECK(memcmp(first, zero, sizeof(first)) != 0);
	CHECK(memcmp(first, second, sizeof(first)) != 0);
	puts("QEMU CORE PASS: secure getrandom");
	return 0;
}

static int test_cow(void)
{
	volatile unsigned char *page = mmap(NULL, 4096, PROT_READ | PROT_WRITE,
	    MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
	CHECK(page != MAP_FAILED);
	page[0] = 0x31;
	page[4095] = 0x73;
	pid_t child = fork();
	if (child == 0) {
		if (page[0] != 0x31 || page[4095] != 0x73)
			_exit(1);
		page[0] = 0xa5;
		page[4095] = 0x5a;
		_exit(page[0] == 0xa5 && page[4095] == 0x5a ? 0 : 1);
	}
	CHECK(reap_ok(child) == 0);
	CHECK(page[0] == 0x31 && page[4095] == 0x73);
	CHECK(munmap((void *)page, 4096) == 0);
	puts("QEMU CORE PASS: copy-on-write fork");
	return 0;
}
#line 282 "test.c"
static int test_sparse_tmpfs_shared_mapping(void)
{
	const char *path = "/dev/shm/vinix-qemu-core-sparse";
	const size_t size = 64UL * 1024 * 1024;
	struct sysinfo before, sized, mapped;
	CHECK(sysinfo(&before) == 0);
	int fd = open(path, O_CREAT | O_EXCL | O_RDWR, 0600);
	CHECK(fd >= 0);
	CHECK(ftruncate(fd, (off_t)size) == 0);
	CHECK(sysinfo(&sized) == 0);
	CHECK(sized.freeram + 8UL * 1024 * 1024 >= before.freeram);
	unsigned char *area = mmap(NULL, size, PROT_READ | PROT_WRITE,
	    MAP_SHARED, fd, 0);
	CHECK(area != MAP_FAILED);
	CHECK(sysinfo(&mapped) == 0);
	CHECK(mapped.freeram + 8UL * 1024 * 1024 >= sized.freeram);
	CHECK(area[0] == 0 && area[size - 1] == 0);
	area[0] = 0x42;
	area[size - 1] = 0x73;
	CHECK(mprotect(area, size, PROT_READ) == 0);
	CHECK(sysinfo(&mapped) == 0);
	CHECK(mapped.freeram + 8UL * 1024 * 1024 >= sized.freeram);
	pid_t child = fork();
	CHECK(child >= 0);
	if (child == 0) {
		int reader = open(path, O_RDWR);
		if (reader < 0)
			_exit(1);
		unsigned char *other = mmap(NULL, size, PROT_READ | PROT_WRITE,
		    MAP_SHARED, reader, 0);
		if (other == MAP_FAILED || other[0] != 0x42 ||
		    other[size - 1] != 0x73 || other[size / 2] != 0)
			_exit(1);
		other[size / 2] = 0x5a;
		_exit(0);
	}
	CHECK(reap_ok(child) == 0);
	CHECK(area[size / 2] == 0x5a);
	CHECK(munmap(area, size) == 0);
	CHECK(close(fd) == 0);
	CHECK(unlink(path) == 0);
	puts("QEMU CORE PASS: sparse tmpfs shared mappings allocate on touch");
	return 0;
}

static int test_partial_munmap_reclaims_pages(void)
{
	const size_t size = 32UL * 1024 * 1024;
	const size_t page = (size_t)sysconf(_SC_PAGESIZE);
	const size_t hole = 16UL * 1024 * 1024;
	struct sysinfo before, populated, after_hole, after_all;
	CHECK(sysinfo(&before) == 0);
	unsigned char *area = mmap(NULL, size, PROT_READ | PROT_WRITE,
	    MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
	CHECK(area != MAP_FAILED);
	for (size_t offset = 0; offset < size; offset += page)
		area[offset] = 0x5a;
	CHECK(sysinfo(&populated) == 0);
	CHECK(populated.freeram + 24UL * 1024 * 1024 <= before.freeram);
	CHECK(munmap(area + 8UL * 1024 * 1024, hole) == 0);
	CHECK(sysinfo(&after_hole) == 0);
	CHECK(after_hole.freeram >= populated.freeram + 12UL * 1024 * 1024);
	CHECK(area[0] == 0x5a && area[size - 16384] == 0x5a);
	CHECK(munmap(area, 8UL * 1024 * 1024) == 0);
	CHECK(munmap(area + 24UL * 1024 * 1024, 8UL * 1024 * 1024) == 0);
	CHECK(sysinfo(&after_all) == 0);
	CHECK(after_all.freeram + 8UL * 1024 * 1024 >= before.freeram);

	/* A parent's partial unmap must retain pages still covered by a forked
	 * shared local. The child reads them after the parent's range changed. */
	int ready[2];
	CHECK(pipe(ready) == 0);
	unsigned char *shared = mmap(NULL, 4 * 16384, PROT_READ | PROT_WRITE,
	    MAP_SHARED | MAP_ANONYMOUS, -1, 0);
	CHECK(shared != MAP_FAILED);
	shared[0] = 0x31;
	shared[3 * 16384] = 0x73;
	pid_t child = fork();
	CHECK(child >= 0);
	if (child == 0) {
		char signal;
		close(ready[1]);
		if (read(ready[0], &signal, 1) != 1)
			_exit(1);
		_exit(shared[0] == 0x31 && shared[3 * 16384] == 0x73 ? 0 : 1);
	}
	CHECK(close(ready[0]) == 0);
	CHECK(munmap(shared, 16384) == 0);
	CHECK(write(ready[1], "x", 1) == 1);
	CHECK(close(ready[1]) == 0);
	CHECK(reap_ok(child) == 0);
	CHECK(shared[3 * 16384] == 0x73);
	CHECK(munmap(shared + 16384, 3 * 16384) == 0);
	puts("QEMU CORE PASS: partial unmap reclaims pages and retains forked shares");
	return 0;
}

#if defined(__aarch64__)
#define SYS_vinix_mimmutable 247
#else
#define SYS_vinix_mimmutable 500
#endif

/* Split a shared range -- change one page of it -- at the moment the process
 * it is shared with unmaps the whole of it. `how` picks the call and the
 * page. Answers zero when every page still holds what was written to it: a
 * page the kernel freed reads as its allocator's poison instead. */
static int split_while_a_sharer_unmaps(int how)
{
	enum { unit = 16384, pages = 4 };
	volatile int *go = mmap(NULL, unit, PROT_READ | PROT_WRITE,
	    MAP_SHARED | MAP_ANONYMOUS, -1, 0);
	unsigned char *shared = mmap(NULL, pages * unit, PROT_READ | PROT_WRITE,
	    MAP_SHARED | MAP_ANONYMOUS, -1, 0);
	if (go == MAP_FAILED || shared == MAP_FAILED)
		return 1;
	memset(shared, 0xa5, pages * unit);
	pid_t sharer = fork();
	if (sharer < 0)
		return 2;
	if (sharer == 0) {
		while (!*go)
			;
		_exit(munmap(shared, pages * unit) == 0 ? 0 : 1);
	}
	unsigned char *page = shared + (how & 1) * unit;
	*go = 1;
	int result;
	if (how < 2)
		result = mprotect(page, unit, PROT_READ);
	else if (how < 4)
		result = (int)syscall(SYS_vinix_mimmutable, page, (size_t)unit);
	else
		result = madvise(page, unit, MADV_DONTFORK);
	if (result != 0)
		return 3;
	int status = -1;
	if (waitpid(sharer, &status, 0) != sharer || !WIFEXITED(status) || WEXITSTATUS(status) != 0)
		return 4;
	for (size_t i = 0; i < pages * unit; i++)
		if (shared[i] != 0xa5)
			return 5;
	return 0;
}

/* A range's pages belong to it for as long as some process maps them. A
 * split used to take the changed page out of the range before putting the
 * piece that held it in, and an unmap by the range's other process in
 * between found the page mapped by no one and freed it. Each round runs in
 * a process of its own, since an immutable range lasts as long as one. */
static int test_split_keeps_pages_a_sharer_unmaps(void)
{
	for (int round = 0; round < 150; ++round) {
		pid_t splitter = fork();
		CHECK(splitter >= 0);
		if (splitter == 0)
			_exit(split_while_a_sharer_unmaps(round % 6));
		int status = -1;
		CHECK(waitpid(splitter, &status, 0) == splitter);
		if (!WIFEXITED(status) || WEXITSTATUS(status) != 0) {
			printf("split round %d (kind %d): status %#x\n", round, round % 6, status);
			CHECK(0);
		}
	}
	puts("QEMU CORE PASS: a range split while a sharer unmaps it keeps its pages");
	return 0;
}

static int test_madvise_reclaims_anonymous_pages(void)
{
	const size_t size = 32UL * 1024 * 1024;
	const size_t page = (size_t)sysconf(_SC_PAGESIZE);
	struct sysinfo populated, discarded;
	volatile unsigned char *area = mmap(NULL, size, PROT_READ | PROT_WRITE,
	    MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
	CHECK(area != MAP_FAILED);
	for (size_t offset = 0; offset < size; offset += page)
		area[offset] = 0x5a;
	CHECK(sysinfo(&populated) == 0);
	CHECK(madvise((void *)area, size, MADV_DONTNEED) == 0);
	CHECK(sysinfo(&discarded) == 0);
	CHECK(discarded.freeram >= populated.freeram + 24UL * 1024 * 1024);
	CHECK(area[0] == 0 && area[size - 16384] == 0);
	CHECK(munmap((void *)area, size) == 0);

	/* Discarding a fork child's private page releases only its reference. */
	area = mmap(NULL, 16384, PROT_READ | PROT_WRITE,
	    MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
	CHECK(area != MAP_FAILED);
	area[0] = 0x73;
	pid_t child = fork();
	CHECK(child >= 0);
	if (child == 0) {
		if (madvise((void *)area, 16384, MADV_DONTNEED) != 0)
			_exit(1);
		_exit(area[0] == 0 ? 0 : 1);
	}
	CHECK(reap_ok(child) == 0);
	CHECK(area[0] == 0x73);
	CHECK(munmap((void *)area, 16384) == 0);
	puts("QEMU CORE PASS: madvise returns anonymous pages to the allocator");
	return 0;
}

static int test_short_lived_process_memory_reclamation(void)
{
	struct sysinfo before, after;
	CHECK(sysinfo(&before) == 0);
	for (int attempt = 0; attempt < 16; ++attempt) {
		pid_t child = fork();
		CHECK(child >= 0);
		if (child == 0) {
			const size_t size = 32UL * 1024 * 1024;
			volatile unsigned char *area = mmap(NULL, size,
			    PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
			if (area == MAP_FAILED)
				_exit(1);
			for (size_t offset = 0; offset < size; offset += 16384)
				area[offset] = 0x5a;
			if (attempt & 1) {
				char *const argv[] = {"/sbin/init", "--exec-memory-probe", NULL};
				execv(argv[0], argv);
				_exit(1);
			}
			_exit(0);
		}
		CHECK(reap_ok(child) == 0);
	}
	CHECK(sysinfo(&after) == 0);
	CHECK(after.freeram + 32UL * 1024 * 1024 >= before.freeram);
	puts("QEMU CORE PASS: exit and exec reclaim process mappings");
	return 0;
}

static int test_forked_cow_memory_reclamation(void)
{
	const size_t size = 32UL * 1024 * 1024;
	volatile unsigned char *area = mmap(NULL, size, PROT_READ | PROT_WRITE,
	    MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
	CHECK(area != MAP_FAILED);
	for (size_t offset = 0; offset < size; offset += 16384)
		area[offset] = 0x31;
	struct sysinfo before, after;
	CHECK(sysinfo(&before) == 0);
	for (int attempt = 0; attempt < 16; ++attempt) {
		pid_t child = fork();
		CHECK(child >= 0);
		if (child == 0) {
			for (size_t offset = 0; offset < size; offset += 16384)
				area[offset] = 0x73;
			_exit(0);
		}
		CHECK(reap_ok(child) == 0);
	}
	CHECK(sysinfo(&after) == 0);
	CHECK(after.freeram + 32UL * 1024 * 1024 >= before.freeram);
	CHECK(area[0] == 0x31 && area[size - 16384] == 0x31);
	CHECK(munmap((void *)area, size) == 0);
	puts("QEMU CORE PASS: forked copy-on-write pages are reclaimed");
	return 0;
}
#line 671 "test.c"
#line 709 "test.c"

#line 744 "test.c"

static int prepare_directory(void)
{
	unlink(file_a);
	unlink(file_b);
	unlink(file_c);
	unlink("/root/vinix-qemu-core/notify-a");
	unlink("/root/vinix-qemu-core/notify-b");
	if (mkdir(test_dir, 0755) < 0)
		CHECK(errno == EEXIST);
	return 0;
}

static int test_ext2_mapping_and_namespace(void)
{
	unsigned char expected[8192];
	for (size_t i = 0; i < sizeof(expected); ++i)
		expected[i] = (unsigned char)(i * 37u + 11u);

	int fd = open(file_a, O_CREAT | O_TRUNC | O_RDWR | O_SYNC, 0640);
	CHECK(fd >= 0);
	CHECK(write(fd, expected, sizeof(expected)) == (ssize_t)sizeof(expected));
	CHECK(fsync(fd) == 0);

	unsigned char *mapped = mmap(NULL, sizeof(expected), PROT_READ | PROT_WRITE,
	    MAP_SHARED, fd, 0);
	CHECK(mapped != MAP_FAILED);
	CHECK(memcmp(mapped, expected, sizeof(expected)) == 0);
	mapped[17] = 0xc1;
	mapped[4096 + 23] = 0xd2;
	expected[17] = 0xc1;
	expected[4096 + 23] = 0xd2;
	CHECK(msync(mapped, sizeof(expected), MS_SYNC) == 0);
	unsigned char observed[8192];
	CHECK(pread(fd, observed, sizeof(observed), 0) == (ssize_t)sizeof(observed));
	CHECK(memcmp(observed, expected, sizeof(observed)) == 0);
	CHECK(munmap(mapped, sizeof(expected)) == 0);
	CHECK(fdatasync(fd) == 0);
	CHECK(close(fd) == 0);

	fd = open(file_a, O_RDONLY);
	CHECK(fd >= 0);
	memset(observed, 0, sizeof(observed));
	CHECK(read(fd, observed, sizeof(observed)) == (ssize_t)sizeof(observed));
	CHECK(memcmp(observed, expected, sizeof(observed)) == 0);
	CHECK(close(fd) == 0);

	CHECK(rename(file_a, file_b) == 0);
	CHECK(link(file_b, file_c) == 0);
	struct stat st;
	CHECK(stat(file_c, &st) == 0 && st.st_nlink == 2);
	CHECK(unlink(file_b) == 0);
	fd = open(file_c, O_RDONLY);
	CHECK(fd >= 0);
	CHECK(pread(fd, observed, 32, 0) == 32);
	CHECK(memcmp(observed, expected, 32) == 0);
	CHECK(close(fd) == 0);

	struct timespec times[2] = {{123456, 123000000}, {234567, 456000000}};
	CHECK(utimensat(AT_FDCWD, file_c, times, 0) == 0);
	CHECK(stat(file_c, &st) == 0);
	CHECK(st.st_atim.tv_sec == times[0].tv_sec);
	CHECK(st.st_mtim.tv_sec == times[1].tv_sec);
	struct statfs fsinfo;
	CHECK(statfs(test_dir, &fsinfo) == 0);
	CHECK(fsinfo.f_bsize > 0 && fsinfo.f_blocks > 0);
	puts("QEMU CORE PASS: ext2 cache, mmap, sync, namespace, timestamps");
	return 0;
}

/* A private file mapping is filled in as it is touched. Each page still has to
 * hold the file's bytes when first read, a write has to stay in the mapping,
 * and the rest of the last page past the end of the file reads as zeroes. */
/*
 * A syscall's buffer may lie in a page nothing has touched yet: a private file
 * mapping, and a large anonymous one, are paged in on first use. The kernel
 * copying to or from such a page has to page it in as a fault would, not fail
 * the call with EFAULT.
 */
static int test_syscall_buffers_in_untouched_pages(void)
{
	static const char *path = "/dev/shm/vinix-qemu-core-untouched";
	const size_t page = 4096;
	const size_t size = 64UL * 1024 * 1024;
	char text[64];
	for (size_t i = 0; i < sizeof(text); ++i)
		text[i] = (char)('a' + i % 26);

	int fd = open(path, O_CREAT | O_TRUNC | O_RDWR, 0600);
	CHECK(fd >= 0);
	CHECK(pwrite(fd, text, sizeof(text), 2 * page) == (ssize_t)sizeof(text));
	char *file = mmap(NULL, 3 * page, PROT_READ, MAP_PRIVATE, fd, 0);
	CHECK(file != MAP_FAILED);
	char *area = mmap(NULL, size, PROT_READ | PROT_WRITE,
	    MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
	CHECK(area != MAP_FAILED);

	/* An empty signal set in a file's page, as musl keeps one in read-only
	 * data. */
	CHECK(sigprocmask(SIG_BLOCK, (const sigset_t *)file, NULL) == 0);
	/* A file write from the file's own mapping... */
	CHECK(lseek(fd, 3 * page, SEEK_SET) == (off_t)(3 * page));
	CHECK(write(fd, file + 2 * page, sizeof(text)) == (ssize_t)sizeof(text));
	/* ...and a file read into anonymous memory. */
	char *target = area + size / 2 + 100;
	CHECK(lseek(fd, 3 * page, SEEK_SET) == (off_t)(3 * page));
	CHECK(read(fd, target, sizeof(text)) == (ssize_t)sizeof(text));
	CHECK(memcmp(target, text, sizeof(text)) == 0);

	CHECK(munmap(area, size) == 0);
	CHECK(munmap(file, 3 * page) == 0);
	CHECK(close(fd) == 0);
	CHECK(unlink(path) == 0);
	puts("QEMU CORE PASS: syscalls page in untouched buffers");
	return 0;
}

static int test_private_file_mapping(void)
{
	static const char *path = "/root/vinix-qemu-core/private";
	const size_t page = 4096;
	const size_t length = 5 * page + 123;
	unsigned char *expected = malloc(length);
	CHECK(expected != NULL);
	for (size_t i = 0; i < length; ++i)
		expected[i] = (unsigned char)(i / page * 29u + i * 7u + 3u);

	int fd = open(path, O_CREAT | O_TRUNC | O_RDWR, 0600);
	CHECK(fd >= 0);
	CHECK(write(fd, expected, length) == (ssize_t)length);

	unsigned char *mapped = mmap(NULL, 6 * page, PROT_READ | PROT_WRITE,
	    MAP_PRIVATE, fd, 0);
	CHECK(mapped != MAP_FAILED);
	/* Out of order, so no page is read only because its neighbour was. */
	for (size_t p = 5; p-- > 0;)
		CHECK(memcmp(mapped + p * page, expected + p * page, page) == 0);
	CHECK(memcmp(mapped + 5 * page, expected + 5 * page, 123) == 0);
	for (size_t i = 123; i < page; ++i)
		CHECK(mapped[5 * page + i] == 0);

	mapped[2 * page + 5] ^= 0xff;
	pid_t child = fork();
	if (child == 0) {
		/* The child inherits the private write and makes its own. */
		if (mapped[2 * page + 5] != (unsigned char)(expected[2 * page + 5] ^ 0xff))
			_exit(1);
		mapped[3 * page + 9] ^= 0xff;
		_exit(0);
	}
	CHECK(reap_ok(child) == 0);
	CHECK(mapped[3 * page + 9] == expected[3 * page + 9]);

	unsigned char observed[4096];
	CHECK(pread(fd, observed, page, 2 * page) == (ssize_t)page);
	CHECK(memcmp(observed, expected + 2 * page, page) == 0);
	CHECK(munmap(mapped, 6 * page) == 0);
	CHECK(close(fd) == 0);
	CHECK(unlink(path) == 0);
	free(expected);
	puts("QEMU CORE PASS: private file mappings read the file and keep their writes");
	return 0;
}

static unsigned long free_ram(void)
{
	struct sysinfo info;
	if (sysinfo(&info) != 0)
		return 0;
	return info.freeram * (info.mem_unit ? info.mem_unit : 1);
}

/* musl maps a library's whole span and then maps its segments over it; an
 * allocator maps more than it needs and trims the result to an alignment.
 * Either leaves part of a private mapping unmapped while the rest lives on,
 * and those pages stayed allocated until the whole mapping was gone. */
static int test_partial_munmap_returns_pages(void)
{
	/* 16 KiB on arm64: a length of 4 KiB short of the head would round up to
	 * the page that is meant to stay. */
	const size_t page = (size_t)sysconf(_SC_PAGESIZE);
	const size_t length = 32UL * 1024 * 1024;
	const unsigned long slack = 8UL * 1024 * 1024;
	unsigned char *region = mmap(NULL, length, PROT_READ | PROT_WRITE,
	    MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
	CHECK(region != MAP_FAILED);
	memset(region, 0x5a, length);

	/* The middle, then the head: both leave the mapping alive around them. */
	unsigned long before = free_ram();
	CHECK(munmap(region + length / 4, length / 2) == 0);
	CHECK(free_ram() + slack >= before + length / 2);
	before = free_ram();
	CHECK(munmap(region, length / 4 - page) == 0);
	CHECK(free_ram() + slack >= before + length / 4 - page);

	CHECK(region[length / 4 - page] == 0x5a);
	CHECK(region[length - 1] == 0x5a);
	CHECK(munmap(region + length / 4 - page, page) == 0);
	CHECK(munmap(region + 3 * length / 4, length / 4) == 0);
	puts("QEMU CORE PASS: a partial munmap gives its pages back");
	return 0;
}

/* A hosted X11 surface is exactly this: a file sized with ftruncate, never
 * written through its descriptor, and filled by the X server through a shared
 * mapping it never synchronises. The compositor maps it to display it, and
 * anything else -- a test, a screenshot tool, cp -- reads it. All three have to
 * see the same pixels.
 *
 * The interesting reader is a separate process with its own descriptor: it goes
 * through the same resource only if the cached mapping is found for the inode
 * rather than for the open file. */
static int test_shared_mapping_visible_to_readers(void)
{
	/* The size matters: a hosted browser's surface is megabytes, and a
	 * cache that behaves for one page can still lose the far end of a
	 * mapping that covers a thousand of them. */
	const size_t length = 4u * 1024u * 1024u;
	int fd = open(surface_file, O_CREAT | O_TRUNC | O_RDWR, 0640);
	CHECK(fd >= 0);
	CHECK(ftruncate(fd, (off_t)length) == 0);

	unsigned char *surface = mmap(NULL, length, PROT_READ | PROT_WRITE,
	    MAP_SHARED, fd, 0);
	CHECK(surface != MAP_FAILED);
	/* A sparse file reads as zeroes until something puts bytes there. */
	for (size_t i = 0; i < length; i += 512)
		CHECK(surface[i] == 0);
	for (size_t i = 0; i < length; ++i)
		surface[i] = (unsigned char)(i * 61u + 7u);

	/* Anything that wants to look at a surface has to size it first, and
	 * seeking to the end is how a reader that did not create it does that.
	 * A wrong answer here sends a checker to a negative offset, which looks
	 * exactly like a blank window. */
	CHECK(lseek(fd, 0, SEEK_END) == (off_t)length);
	CHECK(lseek(fd, 0, SEEK_SET) == 0);

	/* The writer's own descriptor first, with no msync: a mapping is not a
	 * write-behind cache that only becomes real when it is flushed. */
	unsigned char observed[4096];
	CHECK(pread(fd, observed, sizeof(observed), 0) == (ssize_t)sizeof(observed));
	for (size_t i = 0; i < sizeof(observed); ++i)
		CHECK(observed[i] == (unsigned char)(i * 61u + 7u));

	pid_t child = fork();
	CHECK(child >= 0);
	if (child == 0) {
		unsigned char seen[4096];
		int reader = open(surface_file, O_RDONLY);
		if (reader < 0)
			_exit(1);
		if (lseek(reader, 0, SEEK_END) != (off_t)length)
			_exit(4);
		/* Read the far end, past anything the writer's descriptor
		 * touched, and through a fresh descriptor of its own. */
		if (pread(reader, seen, sizeof(seen), (off_t)(length - sizeof(seen)))
		    != (ssize_t)sizeof(seen))
			_exit(2);
		for (size_t i = 0; i < sizeof(seen); ++i) {
			size_t at = length - sizeof(seen) + i;
			if (seen[i] != (unsigned char)(at * 61u + 7u))
				_exit(3);
		}
		_exit(0);
	}
	CHECK(reap_ok(child) == 0);

	CHECK(munmap(surface, length) == 0);
	CHECK(close(fd) == 0);
	CHECK(unlink(surface_file) == 0);
	puts("QEMU CORE PASS: a shared mapping is visible to every reader");
	return 0;
}

/* A process group outlives the process that named it. If the leader's pid is
 * handed to a new process while the group still has members, that process can
 * be given a pid equal to the group it inherits -- making it a group leader by
 * accident, and refusing it a session of its own. Chromium's crash handler,
 * four processes below the browser, treats that refusal as fatal.
 *
 * A: leader of its own session. B: its child, which keeps the group alive
 * after A exits. C: B's child, which must not be handed A's released pid. */
static int test_released_pid_is_not_reused_while_its_group_lives(void)
{
	int result[2];
	CHECK(pipe(result) == 0);

	pid_t a = fork();
	CHECK(a >= 0);
	if (a == 0) {
		close(result[0]);
		if (setsid() == -1)
			_exit(1);
		pid_t b = fork();
		if (b < 0)
			_exit(1);
		if (b == 0) {
			/* Outlive A, so its pid is free while its group is not. */
			sleep(2);
			pid_t c = fork();
			if (c < 0)
				_exit(1);
			if (c == 0) {
				unsigned char inherited_its_own_group =
				    (getpid() == getpgid(0)) ? 1 : 0;
				ssize_t wrote = write(result[1],
				    &inherited_its_own_group, 1);
				_exit(wrote == 1 ? 0 : 1);
			}
			int status = 0;
			waitpid(c, &status, 0);
			_exit(0);
		}
		_exit(0);
	}

	CHECK(close(result[1]) == 0);
	CHECK(reap_ok(a) == 0);
	unsigned char inherited_its_own_group = 1;
	CHECK(read(result[0], &inherited_its_own_group, 1) == 1);
	CHECK(inherited_its_own_group == 0);
	CHECK(close(result[0]) == 0);
	puts("QEMU CORE PASS: a released pid stays out of use while its group lives");
	return 0;
}

static int test_locks(void)
{
	int fd = open(file_c, O_RDWR);
	CHECK(fd >= 0);
	struct flock lock = {
		.l_type = F_WRLCK, .l_whence = SEEK_SET, .l_start = 0, .l_len = 0
	};
	CHECK(fcntl(fd, F_SETLK, &lock) == 0);
	/* Closing resources which cannot acquire locks must leave this lock
	 * intact, even while the global advisory table contains live entries. */
	int unrelated[2];
	CHECK(pipe(unrelated) == 0);
	CHECK(close(unrelated[0]) == 0);
	CHECK(close(unrelated[1]) == 0);
	CHECK(socketpair(AF_UNIX, SOCK_STREAM, 0, unrelated) == 0);
	CHECK(close(unrelated[0]) == 0);
	CHECK(close(unrelated[1]) == 0);
	pid_t child = fork();
	if (child == 0) {
		close(fd);
		int other = open(file_c, O_RDWR);
		if (other < 0)
			_exit(1);
		errno = 0;
		int result = fcntl(other, F_SETLK, &lock);
		_exit(result == -1 && (errno == EAGAIN || errno == EACCES) ? 0 : 1);
	}
	CHECK(reap_ok(child) == 0);
	lock.l_type = F_UNLCK;
	CHECK(fcntl(fd, F_SETLK, &lock) == 0);

	CHECK(flock(fd, LOCK_EX) == 0);
	child = fork();
	if (child == 0) {
		close(fd);
		int other = open(file_c, O_RDWR);
		if (other < 0)
			_exit(1);
		errno = 0;
		int result = flock(other, LOCK_EX | LOCK_NB);
		_exit(result == -1 && (errno == EWOULDBLOCK || errno == EAGAIN) ? 0 : 1);
	}
	CHECK(reap_ok(child) == 0);
	CHECK(flock(fd, LOCK_UN) == 0);
	CHECK(close(fd) == 0);
	puts("QEMU CORE PASS: fcntl and flock exclusion");

	/* POSIX locks go on any descriptor close, even with another dup open.
	 * flock instead lasts until the final open-file-description reference. */
	fd = open(file_c, O_RDWR);
	CHECK(fd >= 0);
	int alias = dup(fd);
	CHECK(alias >= 0);
	lock.l_type = F_WRLCK;
	CHECK(fcntl(fd, F_SETLK, &lock) == 0);
	CHECK(close(alias) == 0);
	child = fork();
	if (child == 0) {
		close(fd);
		int other = open(file_c, O_RDWR);
		_exit(other >= 0 && fcntl(other, F_SETLK, &lock) == 0 ? 0 : 1);
	}
	CHECK(reap_ok(child) == 0);
	CHECK(flock(fd, LOCK_EX) == 0);
	alias = dup(fd);
	CHECK(alias >= 0);
	CHECK(close(fd) == 0);
	child = fork();
	if (child == 0) {
		close(alias);
		int other = open(file_c, O_RDWR);
		errno = 0;
		int result = other >= 0 ? flock(other, LOCK_EX | LOCK_NB) : 0;
		_exit(result == -1 && (errno == EWOULDBLOCK || errno == EAGAIN) ? 0 : 1);
	}
	CHECK(reap_ok(child) == 0);
	CHECK(close(alias) == 0);
	child = fork();
	if (child == 0) {
		int other = open(file_c, O_RDWR);
		_exit(other >= 0 && flock(other, LOCK_EX | LOCK_NB) == 0 ? 0 : 1);
	}
	CHECK(reap_ok(child) == 0);
	puts("QEMU CORE PASS: advisory lock close and dup lifetimes");
	return 0;
}

static int test_permissions_and_limits(void)
{
	mode_t old_mask = umask(0077);
	int fd = open(file_a, O_CREAT | O_TRUNC | O_RDWR, 0666);
	CHECK(fd >= 0);
	CHECK(close(fd) == 0);
	umask(old_mask);
	struct stat st;
	CHECK(stat(file_a, &st) == 0 && (st.st_mode & 0777) == 0600);
	CHECK(chown(file_a, 1234, 1234) == 0);

	pid_t child = fork();
	if (child == 0) {
		if (setgid(2345) != 0 || setuid(2345) != 0 || getuid() != 2345)
			_exit(1);
		errno = 0;
		int denied = open(file_a, O_RDONLY);
		_exit(denied == -1 && errno == EACCES ? 0 : 1);
	}
	CHECK(reap_ok(child) == 0);

	child = fork();
	if (child == 0) {
		struct rlimit limit = {8, 8};
		if (setrlimit(RLIMIT_NOFILE, &limit) != 0)
			_exit(1);
		int opened[16];
		int count = 0;
		while (count < 16 && (opened[count] = open("/dev/console", O_RDONLY)) >= 0)
			++count;
		_exit(count < 16 && errno == EMFILE ? 0 : 1);
	}
	CHECK(reap_ok(child) == 0);

	child = fork();
	if (child == 0) {
		struct rlimit limit = {32, 32};
		if (setrlimit(RLIMIT_FSIZE, &limit) != 0)
			_exit(1);
		int limited = open(file_b, O_CREAT | O_TRUNC | O_WRONLY, 0600);
		char bytes[64] = {0};
		ssize_t first = limited < 0 ? -1 : write(limited, bytes, sizeof(bytes));
		errno = 0;
		ssize_t second = limited < 0 ? -1 : write(limited, bytes, 1);
		_exit(first == 32 && second == -1 && errno == EFBIG ? 0 : 1);
	}
	CHECK(reap_ok(child) == 0);
	puts("QEMU CORE PASS: permissions, umask, and resource limits");
	return 0;
}

static int test_inotify(void)
{
	int notify = inotify_init1(IN_NONBLOCK | IN_CLOEXEC);
	CHECK(notify >= 0);
	int watch = inotify_add_watch(notify, test_dir,
	    IN_CREATE | IN_DELETE | IN_MOVED_FROM | IN_MOVED_TO | IN_MODIFY);
	CHECK(watch > 0);
	const char *first = "/root/vinix-qemu-core/notify-a";
	const char *second = "/root/vinix-qemu-core/notify-b";
	int fd = open(first, O_CREAT | O_TRUNC | O_WRONLY, 0600);
	CHECK(fd >= 0);
	CHECK(write(fd, "event", 5) == 5);
	CHECK(close(fd) == 0);
	CHECK(rename(first, second) == 0);
	CHECK(unlink(second) == 0);

	unsigned char events[1024];
	ssize_t length = read(notify, events, sizeof(events));
	CHECK(length > 0);
	unsigned seen = 0;
	for (ssize_t offset = 0; offset < length;) {
		struct inotify_event *event = (struct inotify_event *)(events + offset);
		if (event->wd == watch)
			seen |= event->mask;
		offset += (ssize_t)sizeof(*event) + event->len;
	}
	CHECK((seen & IN_CREATE) != 0);
	CHECK((seen & IN_MOVED_FROM) != 0 && (seen & IN_MOVED_TO) != 0);
	CHECK((seen & IN_DELETE) != 0);
	CHECK(close(notify) == 0);
	puts("QEMU CORE PASS: inotify events");
	return 0;
}

static int test_scheduler_and_accounting(void)
{
	CHECK(setpriority(PRIO_PROCESS, 0, 5) == 0);
	errno = 0;
	CHECK(getpriority(PRIO_PROCESS, 0) == 5 && errno == 0);
	cpu_set_t requested;
	cpu_set_t observed;
	CPU_ZERO(&requested);
	CPU_SET(0, &requested);
	CHECK(sched_setaffinity(0, sizeof(requested), &requested) == 0);
	CPU_ZERO(&observed);
	CHECK(sched_getaffinity(0, sizeof(observed), &observed) == 0);
	CHECK(CPU_ISSET(0, &observed));

	struct rusage usage;
	struct sysinfo information;
	CHECK(getrusage(RUSAGE_SELF, &usage) == 0);
	CHECK(sysinfo(&information) == 0);
	CHECK(information.totalram > 0 && information.freeram > 0);
	puts("QEMU CORE PASS: priority, affinity, and accounting");
	return 0;
}

struct concurrent_wakeup_state {
	unsigned generation;
	unsigned ready;
	unsigned completed;
};

/* poll(2) attaches this thread to every descriptor event. Four independent
 * writers can therefore trigger four event locks at the same instant. The
 * scheduler used to check is_in_queue without serializing that check with its
 * slot insertion, allowing the same Thread pointer into several queue slots.
 */
static int run_concurrent_wakeup_race(void)
{
	enum { max_workers = 4, rounds = 512 };
	int workers = (int)sysconf(_SC_NPROCESSORS_ONLN);
	CHECK(workers >= 1);
	if (workers > max_workers)
		workers = max_workers;
	int channels[max_workers][2];
	pid_t children[max_workers];
	struct pollfd descriptors[max_workers];
	struct concurrent_wakeup_state *state = mmap(NULL, sizeof(*state),
	    PROT_READ | PROT_WRITE, MAP_SHARED | MAP_ANONYMOUS, -1, 0);
	CHECK(state != MAP_FAILED);
	memset(state, 0, sizeof(*state));

	for (int i = 0; i < workers; ++i)
		CHECK(pipe(channels[i]) == 0);
	for (int i = 0; i < workers; ++i) {
		children[i] = fork();
		CHECK(children[i] >= 0);
		if (children[i] != 0)
			continue;

		for (int j = 0; j < workers; ++j) {
			close(channels[j][0]);
			if (j != i)
				close(channels[j][1]);
		}
		cpu_set_t affinity;
		CPU_ZERO(&affinity);
		CPU_SET(i, &affinity);
		if (sched_setaffinity(0, sizeof(affinity), &affinity) != 0)
			_exit(2);
		__atomic_add_fetch(&state->ready, 1, __ATOMIC_RELEASE);
		for (unsigned round = 1; round <= rounds; ++round) {
			while (__atomic_load_n(&state->generation, __ATOMIC_ACQUIRE) < round)
				sched_yield();
			if (write(channels[i][1], "w", 1) != 1)
				_exit(3);
			__atomic_add_fetch(&state->completed, 1, __ATOMIC_RELEASE);
			while (__atomic_load_n(&state->generation, __ATOMIC_ACQUIRE) == round)
				sched_yield();
		}
		close(channels[i][1]);
		_exit(0);
	}

	for (int i = 0; i < workers; ++i) {
		close(channels[i][1]);
		descriptors[i].fd = channels[i][0];
		descriptors[i].events = POLLIN;
		descriptors[i].revents = 0;
	}
	alarm(60);
	while (__atomic_load_n(&state->ready, __ATOMIC_ACQUIRE) != (unsigned int)workers)
		sched_yield();
	for (unsigned round = 1; round <= rounds; ++round) {
		__atomic_store_n(&state->generation, round, __ATOMIC_RELEASE);
		CHECK(poll(descriptors, workers, 5000) > 0);
		for (int i = 0; i < workers; ++i) {
			char byte = 0;
			CHECK(read(channels[i][0], &byte, 1) == 1);
			CHECK(byte == 'w');
		}
		while (__atomic_load_n(&state->completed, __ATOMIC_ACQUIRE) <
		    round * workers)
			sched_yield();
	}
	/* Let workers leave their final generation barrier. */
	__atomic_store_n(&state->generation, rounds + 1, __ATOMIC_RELEASE);
	for (int i = 0; i < workers; ++i) {
		CHECK(close(channels[i][0]) == 0);
		CHECK(reap_ok(children[i]) == 0);
	}
	alarm(0);
	CHECK(munmap(state, sizeof(*state)) == 0);
	return 0;
}

static int test_concurrent_wakeups_queue_once(void)
{
	pid_t coordinator = fork();
	CHECK(coordinator >= 0);
	if (coordinator == 0)
		_exit(run_concurrent_wakeup_race());
	CHECK(reap_ok(coordinator) == 0);
	puts("QEMU CORE PASS: concurrent wakeups enqueue one thread once");
	return 0;
}

static int test_posix_timer_thread_notification(void)
{
	timer_t timer;
	struct sigevent notification = {
		.sigev_notify = SIGEV_THREAD,
		.sigev_notify_function = posix_timer_callback,
		.sigev_value.sival_int = 0x5649,
	};
	CHECK(timer_create(CLOCK_MONOTONIC, &notification, &timer) == 0);
	struct itimerspec setting = {
		.it_value = {.tv_nsec = 20000000},
	};
	CHECK(timer_settime(timer, 0, &setting, NULL) == 0);
	for (int attempt = 0; attempt < 100 && posix_timer_callbacks == 0; ++attempt)
		nanosleep(&(struct timespec){.tv_nsec = 10000000}, NULL);
	CHECK(posix_timer_callbacks == 1);
	struct itimerspec current;
	CHECK(timer_gettime(timer, &current) == 0);
	CHECK(current.it_value.tv_sec == 0 && current.it_value.tv_nsec == 0);
	CHECK(timer_getoverrun(timer) == 0);
	CHECK(timer_delete(timer) == 0);
	puts("QEMU CORE PASS: POSIX SIGEV_THREAD timer notification");
	return 0;
}

/* Anonymous descriptors have to carry an access mode. Without one they look
 * read-only, and write(2) on them is refused with EBADF: an X server answers
 * its clients with writev(2), so every graphical application on the machine
 * lost its connection the moment the server tried to reply. */
static int test_anonymous_descriptor_access(void)
{
	int pair[2];
	CHECK(socketpair(AF_UNIX, SOCK_STREAM, 0, pair) == 0);
	CHECK((fcntl(pair[0], F_GETFL) & O_ACCMODE) == O_RDWR);
	struct iovec vector[2];
	vector[0].iov_base = (void *)"soc";
	vector[0].iov_len = 3;
	vector[1].iov_base = (void *)"ket";
	vector[1].iov_len = 3;
	CHECK(writev(pair[0], vector, 2) == 6);
	char received[8] = { 0 };
	CHECK(read(pair[1], received, sizeof(received)) == 6);
	CHECK(memcmp(received, "socket", 6) == 0);
	CHECK(close(pair[0]) == 0);
	CHECK(close(pair[1]) == 0);

	/* A listening socket hands its access mode to what accept(2) returns. */
	struct sockaddr_un address;
	memset(&address, 0, sizeof(address));
	address.sun_family = AF_UNIX;
	/* The test image has no /tmp; the working directory is on the volume the
	 * rest of these tests use. */
	strcpy(address.sun_path, "/root/vinix-qemu-core/accept.sock");
	unlink(address.sun_path);
	int listener = socket(AF_UNIX, SOCK_STREAM, 0);
	CHECK(listener >= 0);
	CHECK(bind(listener, (struct sockaddr *)&address, sizeof(address)) == 0);
	CHECK(listen(listener, 4) == 0);
	int client = socket(AF_UNIX, SOCK_STREAM, 0);
	CHECK(client >= 0);
	CHECK(connect(client, (struct sockaddr *)&address, sizeof(address)) == 0);
	int served = accept(listener, NULL, NULL);
	CHECK(served >= 0);
	CHECK((fcntl(served, F_GETFL) & O_ACCMODE) == O_RDWR);
	CHECK(write(served, "reply", 5) == 5);
	char answer[8] = { 0 };
	CHECK(read(client, answer, sizeof(answer)) == 5);
	CHECK(memcmp(answer, "reply", 5) == 0);
	CHECK(close(served) == 0);
	CHECK(close(client) == 0);
	CHECK(close(listener) == 0);
	CHECK(unlink(address.sun_path) == 0);

	/* eventfd counts both ways, and its own flags share a bit with O_WRONLY. */
	int counter = eventfd(0, EFD_CLOEXEC);
	CHECK(counter >= 0);
	CHECK((fcntl(counter, F_GETFL) & O_ACCMODE) == O_RDWR);
	uint64_t one = 1;
	CHECK(write(counter, &one, sizeof(one)) == (ssize_t)sizeof(one));
	uint64_t read_back = 0;
	CHECK(read(counter, &read_back, sizeof(read_back)) == (ssize_t)sizeof(read_back));
	CHECK(read_back == 1);
	CHECK(close(counter) == 0);

	puts("QEMU CORE PASS: anonymous descriptors are open both ways");
	return 0;
}

/* Pipes and Unix sockets are resources created by almost every compiler and
 * shell helper. Their buffers must follow the final open-file description:
 * keeping one private "owner" reference leaked 64 KiB per pipe and 1 MiB per
 * Unix endpoint, so one native desktop build exhausted an 8 GiB guest just as
 * PID 1 started the replacement compositor. */
static int test_anonymous_ipc_memory_reclamation(void)
{
	struct sysinfo before;
	struct sysinfo after;
	CHECK(sysinfo(&before) == 0);

	for (int attempt = 0; attempt < 128; ++attempt) {
		int pair[2];
		CHECK(socketpair(AF_UNIX, SOCK_STREAM, 0, pair) == 0);
		CHECK(close(pair[0]) == 0);
		CHECK(close(pair[1]) == 0);
	}
	for (int attempt = 0; attempt < 1024; ++attempt) {
		int pair[2];
		CHECK(pipe(pair) == 0);
		CHECK(close(pair[0]) == 0);
		CHECK(close(pair[1]) == 0);
	}

	CHECK(sysinfo(&after) == 0);
	/* Allow ordinary allocator bookkeeping and concurrently active kernel
	 * services to retain a modest amount. The old leak consumed 320 MiB. */
	CHECK(after.freeram + 32UL * 1024 * 1024 >= before.freeram);
	puts("QEMU CORE PASS: anonymous IPC buffers are reclaimed");
	return 0;
}

/* Empty pipes promise a capacity, but do not need a ring until a writer puts
 * bytes in them. Hold enough live pipes to distinguish demand allocation
 * from allocating and then reclaiming every ring during create/close. */
static int test_empty_pipe_buffers(void)
{
	enum { count = 256 };
	int pairs[count][2];
	struct sysinfo before, empty, resized, written, closed;
	CHECK(sysinfo(&before) == 0);
	for (int i = 0; i < count; ++i) {
		CHECK(pipe(pairs[i]) == 0);
		CHECK(fcntl(pairs[i][0], F_GETPIPE_SZ) == 64 * 1024);
	}
	CHECK(sysinfo(&empty) == 0);
	/* Descriptor objects may grow slab pools. Eager 64 KiB rings retain
	 * over 16 MiB here; four MiB leaves room for ordinary kernel services. */
	CHECK(empty.freeram + 4UL * 1024 * 1024 >= before.freeram);

	struct pollfd readiness[2] = {
		{.fd = pairs[0][0], .events = POLLIN},
		{.fd = pairs[0][1], .events = POLLOUT},
	};
	CHECK(poll(readiness, 2, 0) == 1);
	CHECK(readiness[0].revents == 0);
	CHECK((readiness[1].revents & POLLOUT) != 0);
	int queued = -1;
	CHECK(ioctl(pairs[0][0], FIONREAD, &queued) == 0 && queued == 0);
	CHECK(fcntl(pairs[0][0], F_SETFL, O_NONBLOCK) == 0);
	unsigned char observed = 0;
	errno = 0;
	CHECK(read(pairs[0][0], &observed, 1) == -1 && errno == EAGAIN);
	CHECK(write(pairs[0][1], &observed, 0) == 0);
	CHECK(fcntl(pairs[0][0], F_SETPIPE_SZ, 1024 * 1024) == 1024 * 1024);
	CHECK(fcntl(pairs[1][0], F_SETPIPE_SZ, 4096) == 4096);
	CHECK(sysinfo(&resized) == 0);
	CHECK(resized.freeram + 4UL * 1024 * 1024 >= before.freeram);

	for (int i = 0; i < count; ++i) {
		unsigned char payload = (unsigned char)(i ^ 0xa5);
		CHECK(write(pairs[i][1], &payload, 1) == 1);
		CHECK(read(pairs[i][0], &observed, 1) == 1 && observed == payload);
	}
	CHECK(sysinfo(&written) == 0);
	/* The first write really acquired backing storage; all live rings must
	 * retain it even after their readers have drained the byte. */
	CHECK(written.freeram + 8UL * 1024 * 1024 < resized.freeram);
	for (int i = 0; i < count; ++i) {
		CHECK(close(pairs[i][1]) == 0);
		CHECK(read(pairs[i][0], &observed, 1) == 0);
		CHECK(close(pairs[i][0]) == 0);
	}
	CHECK(sysinfo(&closed) == 0);
	CHECK(closed.freeram + 4UL * 1024 * 1024 >= before.freeram);
	printf("QEMU CORE PIPE free bytes: before=%lu empty=%lu resized=%lu written=%lu closed=%lu\n",
	    before.freeram, empty.freeram, resized.freeram, written.freeram,
	    closed.freeram);
	/* The child inherits the same empty resource. A parent already asleep
	 * reading it must see the child's first write and then the final EOF. */
	int shared[2];
	CHECK(pipe(shared) == 0);
	pid_t child = fork();
	CHECK(child >= 0);
	if (child == 0) {
		close(shared[0]);
		usleep(20000);
		ssize_t sent = write(shared[1], "fork", 4);
		close(shared[1]);
		_exit(sent == 4 ? 0 : 1);
	}
	CHECK(close(shared[1]) == 0);
	char message[4] = {0};
	alarm(5);
	CHECK(read(shared[0], message, sizeof(message)) == (ssize_t)sizeof(message));
	CHECK(memcmp(message, "fork", sizeof(message)) == 0);
	CHECK(read(shared[0], message, sizeof(message)) == 0);
	alarm(0);
	CHECK(close(shared[0]) == 0);
	CHECK(reap_ok(child) == 0);
	puts("QEMU CORE PASS: empty pipes defer buffers and reclaim first-write storage");
	return 0;
}

/* A socket syscall boxes the V Socket interface for dispatch. Repeated empty
 * receives used to retain each box, consuming one 16 KiB slab page for every
 * few dozen calls while a busy X11 client polled its sockets. */
static int test_socket_interface_box_reclamation(void)
{
	int pair[2];
	struct sysinfo before, after;
	char byte;
	struct iovec iov = {.iov_base = &byte, .iov_len = sizeof(byte)};
	struct msghdr message = {.msg_iov = &iov, .msg_iovlen = 1};
	CHECK(socketpair(AF_UNIX, SOCK_STREAM, 0, pair) == 0);
	CHECK(sysinfo(&before) == 0);
	for (int i = 0; i < 65536; ++i) {
		errno = 0;
		CHECK(recvmsg(pair[0], &message, MSG_DONTWAIT) == -1);
		CHECK(errno == EAGAIN || errno == EWOULDBLOCK);
	}
	CHECK(sysinfo(&after) == 0);
	CHECK(after.freeram + 6UL * 1024 * 1024 >= before.freeram);
	CHECK(close(pair[0]) == 0);
	CHECK(close(pair[1]) == 0);
	puts("QEMU CORE PASS: socket interface boxes are reclaimed");
	return 0;
}

/* Idle sockets must not each reserve a 1 MiB receive buffer. A browser can
 * keep hundreds of UNIX endpoints open while starting; allocating them all
 * eagerly exhausted or fragmented the guest before Steam opened a window.
 * Also exercise FIFO order when a wrapped, partly consumed buffer grows. */
static int test_unix_socket_buffer_growth(void)
{
	struct sysinfo before, after;
	int pairs[16][2];
	CHECK(sysinfo(&before) == 0);
	for (int i = 0; i < 16; ++i)
		CHECK(socketpair(AF_UNIX, SOCK_STREAM, 0, pairs[i]) == 0);
	CHECK(sysinfo(&after) == 0);
	CHECK(after.freeram + 8UL * 1024 * 1024 >= before.freeram);
	for (int i = 0; i < 16; ++i) {
		CHECK(close(pairs[i][0]) == 0);
		CHECK(close(pairs[i][1]) == 0);
	}

	int pair[2];
	CHECK(socketpair(AF_UNIX, SOCK_STREAM, 0, pair) == 0);
	int receive_limit = 0;
	socklen_t limit_len = sizeof(receive_limit);
	CHECK(getsockopt(pair[1], SOL_SOCKET, SO_RCVBUF, &receive_limit,
	    &limit_len) == 0);
	CHECK(receive_limit == 1024 * 1024);
	char first[3000], second[6000], received[7000];
	memset(first, 'A', sizeof(first));
	memset(second, 'B', sizeof(second));
	CHECK(write(pair[0], first, sizeof(first)) == (ssize_t)sizeof(first));
	CHECK(read(pair[1], received, 2000) == 2000);
	CHECK(memcmp(received, first, 2000) == 0);
	CHECK(write(pair[0], second, sizeof(second)) == (ssize_t)sizeof(second));
	CHECK(read(pair[1], received, sizeof(received)) ==
	    (ssize_t)sizeof(received));
	CHECK(memcmp(received, first + 2000, 1000) == 0);
	CHECK(memcmp(received + 1000, second, sizeof(second)) == 0);
	CHECK(close(pair[0]) == 0);
	CHECK(close(pair[1]) == 0);

	CHECK(socketpair(AF_UNIX, SOCK_DGRAM, 0, pair) == 0);
	CHECK(send(pair[0], second, sizeof(second), 0) ==
	    (ssize_t)sizeof(second));
	CHECK(recv(pair[1], received, sizeof(received), 0) ==
	    (ssize_t)sizeof(second));
	CHECK(memcmp(received, second, sizeof(second)) == 0);
	CHECK(send(pair[0], "", 0, 0) == 0);
	CHECK(recv(pair[1], received, sizeof(received), 0) == 0);
	CHECK(close(pair[0]) == 0);
	CHECK(close(pair[1]) == 0);
	puts("QEMU CORE PASS: UNIX receive buffers grow on demand");
	return 0;
}

/* XCB flushes large images through a nonblocking Unix stream. Once its peer's
 * receive buffer is full, POLLOUT must stay clear until the server reads data;
 * otherwise the client spins on EAGAIN instead of waiting for space. */
static int test_unix_socket_full_write_readiness(void)
{
	int pair[2];
	CHECK(socketpair(AF_UNIX, SOCK_STREAM, 0, pair) == 0);
	CHECK(fcntl(pair[0], F_SETFL, O_NONBLOCK) == 0);
	char *image = malloc(1024 * 1024);
	CHECK(image != NULL);
	memset(image, 0x5a, 1024 * 1024);
	CHECK(write(pair[0], image, 1024 * 1024) == 1024 * 1024);

	struct pollfd writer = {.fd = pair[0], .events = POLLOUT};
	CHECK(poll(&writer, 1, 0) == 0);
	int epfd = epoll_create1(0);
	CHECK(epfd >= 0);
	struct epoll_event event = {.events = EPOLLOUT, .data.fd = pair[0]};
	CHECK(epoll_ctl(epfd, EPOLL_CTL_ADD, pair[0], &event) == 0);
	CHECK(epoll_wait(epfd, &event, 1, 0) == 0);

	char byte;
	CHECK(read(pair[1], &byte, 1) == 1 && byte == 0x5a);
	CHECK(poll(&writer, 1, 0) == 1 && (writer.revents & POLLOUT));
	CHECK(epoll_wait(epfd, &event, 1, 0) == 1 && (event.events & EPOLLOUT));
	CHECK(close(epfd) == 0);
	CHECK(close(pair[0]) == 0);
	CHECK(close(pair[1]) == 0);
	free(image);
	puts("QEMU CORE PASS: full UNIX stream clears write readiness");
	return 0;
}

/* Qt's raster painter uses FUTEX_WAKE_OP to notify a semaphore waiter. */
static int test_futex_wake_op(void)
{
	uint32_t words[2] = {0, 7};
	/* ADD 3; wake the second address only when its old value was 7. */
	CHECK(syscall(SYS_futex, &words[0], 5 | 128, 1, 1, &words[1],
	    0x10003007) == 0);
	CHECK(words[1] == 10);
	/* Qt's OR 0 / NE 0 form must preserve the word. */
	CHECK(syscall(SYS_futex, &words[0], 5 | 128, 1, 1, &words[1],
	    0x21000000) == 0);
	CHECK(words[1] == 10);
	errno = 0;
	CHECK(syscall(SYS_futex, &words[0], 5 | 128, 1, 1, (void *)1,
	    0x21000000) == -1 && errno == EFAULT);
	puts("QEMU CORE PASS: futex wake-op updates and compares user words");
	return 0;
}

/* A thread with a working directory of its own forks from there. */
static void *fork_from_own_directory(void *argument)
{
	int *ok = argument;
	if (unshare(CLONE_FS) != 0 || chdir("/dev") != 0)
		return NULL;
	pid_t child = fork();
	if (child == 0) {
		char path[64];
		_exit(getcwd(path, sizeof(path)) != NULL
		    && strcmp(path, "/dev") == 0 ? 0 : 1);
	}
	*ok = reap_ok(child) == 0;
	return NULL;
}

/* A forked child runs the same program, from the same auxiliary vector and
 * working directory, but does not keep a scheduling policy its parent set with
 * SCHED_RESET_ON_FORK. musl stubs the sched_*scheduler calls out, hence the
 * raw syscalls. */
static int test_fork_inherits_process_state(void)
{
	char exe[256], auxv[1024];
	ssize_t exe_length = readlink("/proc/self/exe", exe, sizeof(exe));
	CHECK(exe_length > 0);
	int fd = open("/proc/self/auxv", O_RDONLY);
	CHECK(fd >= 0);
	ssize_t auxv_length = read(fd, auxv, sizeof(auxv));
	CHECK(close(fd) == 0);
	CHECK(auxv_length > 0);

	struct sched_param priority = {.sched_priority = 1};
	CHECK(syscall(SYS_sched_setscheduler, 0,
	    SCHED_FIFO | SCHED_RESET_ON_FORK, &priority) == 0);
	pid_t child = fork();
	if (child == 0) {
		char seen[1024];
		ssize_t length = readlink("/proc/self/exe", seen, sizeof(seen));
		if (length != exe_length || memcmp(seen, exe, (size_t)length) != 0)
			_exit(1);
		int auxv_fd = open("/proc/self/auxv", O_RDONLY);
		if (auxv_fd < 0 || read(auxv_fd, seen, sizeof(seen)) != auxv_length
		    || memcmp(seen, auxv, (size_t)auxv_length) != 0)
			_exit(2);
		if (syscall(SYS_sched_getscheduler, 0) != SCHED_OTHER)
			_exit(3);
		_exit(0);
	}
	priority.sched_priority = 0;
	CHECK(syscall(SYS_sched_setscheduler, 0, SCHED_OTHER, &priority) == 0);
	CHECK(reap_ok(child) == 0);

	int ok = 0;
	pthread_t thread;
	CHECK(pthread_create(&thread, NULL, fork_from_own_directory, &ok) == 0);
	CHECK(pthread_join(thread, NULL) == 0);
	CHECK(ok);
	puts("QEMU CORE PASS: fork keeps the program, auxv and directory");
	return 0;
}

/* A child that counts as fast as it can on CPU `cpu`, into `counter`, without
 * ever making a syscall. */
static pid_t start_counter(volatile unsigned long *counter, int cpu)
{
	pid_t child = fork();
	if (child != 0)
		return child;
	cpu_set_t affinity;
	CPU_ZERO(&affinity);
	CPU_SET(cpu, &affinity);
	if (sched_setaffinity(0, sizeof(affinity), &affinity) != 0)
		_exit(2);
	for (;;)
		++*counter;
}

static unsigned long monotonic_ms(void)
{
	struct timespec now;
	clock_gettime(CLOCK_MONOTONIC, &now);
	return (unsigned long)now.tv_sec * 1000 + (unsigned long)now.tv_nsec / 1000000;
}

/* How far `counter` gets in `ms` milliseconds of this process sleeping, or of
 * it spinning when `spin` is set. */
static unsigned long count_for(volatile unsigned long *counter, unsigned long ms, int spin)
{
	unsigned long before = *counter;
	if (spin) {
		unsigned long end = monotonic_ms() + ms;
		while (monotonic_ms() < end)
			;
	} else {
		usleep((useconds_t)ms * 1000);
	}
	return *counter - before;
}

static int kill_counter(pid_t child)
{
	CHECK(kill(child, SIGKILL) == 0);
	int status;
	CHECK(waitpid(child, &status, 0) == child);
	CHECK(WIFSIGNALED(status) && WTERMSIG(status) == SIGKILL);
	return 0;
}

/* A SCHED_FIFO thread keeps the CPU it is on from an ordinary one for as long as
 * it has work, and gives it back when it goes back to SCHED_OTHER. musl stubs
 * sched_setscheduler out, hence the raw syscall. */
static int test_fifo_keeps_its_cpu(void)
{
	long cpus = sysconf(_SC_NPROCESSORS_ONLN);
	CHECK(cpus >= 2);
	int cpu = (int)cpus - 1;
	volatile unsigned long *counter = mmap(NULL, 4096, PROT_READ | PROT_WRITE,
	    MAP_SHARED | MAP_ANONYMOUS, -1, 0);
	CHECK(counter != MAP_FAILED);
	pid_t child = start_counter(counter, cpu);
	CHECK(child > 0);
	cpu_set_t affinity, original;
	CHECK(sched_getaffinity(0, sizeof(original), &original) == 0);
	CPU_ZERO(&affinity);
	CPU_SET(cpu, &affinity);
	CHECK(sched_setaffinity(0, sizeof(affinity), &affinity) == 0);

	/* Sharing the CPU, the child gets some of every stretch. */
	unsigned long shared = count_for(counter, 300, 1);
	struct sched_param priority = {.sched_priority = 10};
	CHECK(syscall(SYS_sched_setscheduler, 0, SCHED_FIFO, &priority) == 0);
	unsigned long held = count_for(counter, 300, 1);
	priority.sched_priority = 0;
	CHECK(syscall(SYS_sched_setscheduler, 0, SCHED_OTHER, &priority) == 0);
	unsigned long after = count_for(counter, 300, 0);

	CHECK(sched_setaffinity(0, sizeof(original), &original) == 0);
	CHECK(kill_counter(child) == 0);
	CHECK(munmap((void *)counter, 4096) == 0);
	if (!(shared > 0 && after > 0 && held * 20 < shared)) {
		printf("fifo counts: shared %lu, held %lu, after %lu\n", shared, held, after);
		CHECK(0);
	}
	puts("QEMU CORE PASS: a FIFO thread keeps its CPU");
	return 0;
}

static int write_text(const char *path, const char *text)
{
	int fd = open(path, O_WRONLY);
	CHECK(fd >= 0);
	CHECK(write(fd, text, strlen(text)) == (ssize_t)strlen(text));
	CHECK(close(fd) == 0);
	return 0;
}

/* A frozen cgroup's threads stop, even one that makes no syscalls, and go on
 * once it thaws. */
static int test_frozen_cgroup_stops_its_threads(void)
{
	static const char *root = "/dev/shm/vinix-qemu-core-cgroup";
	CHECK(mkdir(root, 0755) == 0);
	CHECK(mount("cgroup2", root, "cgroup2", 0, NULL) == 0);
	CHECK(mkdir("/dev/shm/vinix-qemu-core-cgroup/frozen", 0755) == 0);

	volatile unsigned long *counter = mmap(NULL, 4096, PROT_READ | PROT_WRITE,
	    MAP_SHARED | MAP_ANONYMOUS, -1, 0);
	CHECK(counter != MAP_FAILED);
	pid_t child = start_counter(counter, 0);
	CHECK(child > 0);
	char pid_text[32];
	snprintf(pid_text, sizeof(pid_text), "%d\n", child);
	CHECK(write_text("/dev/shm/vinix-qemu-core-cgroup/frozen/cgroup.procs", pid_text) == 0);

	CHECK(count_for(counter, 200, 0) > 0);
	CHECK(write_text("/dev/shm/vinix-qemu-core-cgroup/frozen/cgroup.freeze", "1\n") == 0);
	usleep(50000);
	unsigned long frozen = count_for(counter, 300, 0);
	CHECK(write_text("/dev/shm/vinix-qemu-core-cgroup/frozen/cgroup.freeze", "0\n") == 0);
	unsigned long thawed = count_for(counter, 300, 0);
	if (!(frozen == 0 && thawed > 0)) {
		printf("cgroup counts: frozen %lu, thawed %lu\n", frozen, thawed);
		CHECK(0);
	}

	CHECK(kill_counter(child) == 0);
	CHECK(munmap((void *)counter, 4096) == 0);
	CHECK(rmdir("/dev/shm/vinix-qemu-core-cgroup/frozen") == 0);
	CHECK(umount(root) == 0);
	CHECK(rmdir(root) == 0);
	puts("QEMU CORE PASS: a frozen cgroup stops its threads");
	return 0;
}

/* Whether the /proc/cpuinfo line starting `key` names `flag` as a word. */
static int cpuinfo_has(const char *text, const char *key, const char *flag)
{
	const char *line = strstr(text, key);
	if (line == NULL)
		return 0;
	const char *end = strchr(line, '\n');
	size_t length = strlen(flag);
	for (const char *at = strstr(line, flag); at != NULL && (end == NULL || at < end);
	    at = strstr(at + 1, flag)) {
		if (at[-1] == ' ' && (at[length] == ' ' || at[length] == '\n'))
			return 1;
	}
	return 0;
}

/* /proc/cpuinfo describes the machine's own architecture, one block per CPU:
 * on x86-64 the flags line programs grep for their extensions in, and which
 * names AVX2 exactly when a program may use it. */
static int test_cpuinfo(void)
{
	static char text[65536];
	int fd = open("/proc/cpuinfo", O_RDONLY);
	CHECK(fd >= 0);
	size_t length = 0;
	for (;;) {
		ssize_t got = read(fd, text + length, sizeof(text) - 1 - length);
		CHECK(got >= 0);
		if (got == 0)
			break;
		length += (size_t)got;
	}
	text[length] = 0;
	CHECK(close(fd) == 0);

	long processors = 0;
	for (const char *at = text; (at = strstr(at, "processor\t: ")) != NULL; ++at)
		++processors;
	CHECK(processors == sysconf(_SC_NPROCESSORS_ONLN));
#if defined(__x86_64__)
	CHECK(strstr(text, "vendor_id\t: ") != NULL);
	CHECK(cpuinfo_has(text, "flags\t\t:", "sse2"));
	CHECK(cpuinfo_has(text, "flags\t\t:", "lm"));
	unsigned a, b, c, d;
	__asm__ volatile("cpuid" : "=a"(a), "=b"(b), "=c"(c), "=d"(d) : "a"(1), "c"(0));
	int usable = 0;
	if (c & (1u << 27)) {
		unsigned xcr0, high;
		__asm__ volatile("xgetbv" : "=a"(xcr0), "=d"(high) : "c"(0));
		__asm__ volatile("cpuid" : "=a"(a), "=b"(b), "=c"(c), "=d"(d) : "a"(7), "c"(0));
		usable = (xcr0 & 6) == 6 && (b & (1u << 5)) != 0;
	}
	CHECK(cpuinfo_has(text, "flags\t\t:", "avx2") == usable);
#else
	CHECK(cpuinfo_has(text, "Features\t:", "fp"));
#endif
	puts("QEMU CORE PASS: /proc/cpuinfo describes the machine");
	return 0;
}

static void *return_at_once(void *argument)
{
	return argument;
}

/* A thread that has exited and been joined leaves nothing of itself in the
 * kernel: a program that starts a thread per request runs for good. The first
 * round lets allocator caches fill; the second may not cost more. */
static int test_joined_threads_return_their_memory(void)
{
	unsigned long before = 0;
	for (int round = 0; round < 2; ++round) {
		if (round == 1)
			before = free_ram();
		for (int i = 0; i < 2000; ++i) {
			pthread_t thread;
			CHECK(pthread_create(&thread, NULL, return_at_once, NULL) == 0);
			CHECK(pthread_join(thread, NULL) == 0);
		}
	}
	unsigned long after = free_ram();
	if (after + 4UL * 1024 * 1024 < before) {
		printf("thread churn: free before %lu, after %lu\n", before, after);
		CHECK(0);
	}
	puts("QEMU CORE PASS: joined threads return their memory");
	return 0;
}

/* The console as a controlling terminal: a session leader takes it with
 * TIOCSCTTY, and the session and foreground group it reports, its window
 * size, and /dev/tty all follow, until TIOCNOTTY gives it up. */
static int console_session_child(void)
{
	if (setsid() < 0)
		return 1;
	int console = open("/dev/console", O_RDWR | O_NOCTTY);
	if (console < 0)
		return 2;
	if (ioctl(console, TIOCSCTTY, 0) != 0)
		return 3;
	pid_t session = -1;
	if (ioctl(console, TIOCGSID, &session) != 0 || session != getsid(0))
		return 4;
	if (tcgetpgrp(console) != getpgrp() || tcsetpgrp(console, getpgrp()) != 0)
		return 5;
	int tty = open("/dev/tty", O_RDWR);
	if (tty < 0)
		return 6;
	struct winsize original, wanted = {.ws_row = 24, .ws_col = 80}, seen;
	if (ioctl(tty, TIOCGWINSZ, &original) != 0 || ioctl(tty, TIOCSWINSZ, &wanted) != 0
	    || ioctl(console, TIOCGWINSZ, &seen) != 0 || seen.ws_row != 24 || seen.ws_col != 80
	    || ioctl(tty, TIOCSWINSZ, &original) != 0)
		return 7;
	close(tty);
	/* Giving up the controlling terminal sends SIGHUP to its foreground
	 * group. Keep this child alive to verify the detached /dev/tty lookup. */
	if (signal(SIGHUP, SIG_IGN) == SIG_ERR)
		return 10;
	if (ioctl(console, TIOCNOTTY) != 0)
		return 8;
	errno = 0;
	if (open("/dev/tty", O_RDWR) >= 0 || errno != ENXIO)
		return 9;
	return 0;
}

static int test_console_controls_a_session(void)
{
	pid_t child = fork();
	CHECK(child >= 0);
	if (child == 0)
		_exit(console_session_child());
	int status;
	CHECK(waitpid(child, &status, 0) == child);
	if (!WIFEXITED(status) || WEXITSTATUS(status) != 0) {
		printf("console session: status 0x%x\n", status);
		CHECK(0);
	}
	puts("QEMU CORE PASS: the console controls a session");
	return 0;
}

/* A page table change reaches every CPU a process runs on, not only the CPU
 * that made it: x86 has to ask the others to drop what they hold. */
static volatile unsigned long *shootdown_page;
static volatile sig_atomic_t shootdown_faulted;
static volatile sig_atomic_t shootdown_stop;
static _Atomic unsigned long shootdown_reads;
static unsigned long shootdown_reads_at_fault;
static sigjmp_buf shootdown_jump;

static void shootdown_fault(int signal)
{
	(void)signal;
	shootdown_reads_at_fault = atomic_load(&shootdown_reads);
	shootdown_faulted = 1;
	siglongjmp(shootdown_jump, 1);
}

/* Pin the calling thread to `cpu`, and return once it runs there: affinity
 * moves a thread only when it next comes through the scheduler. */
static int pin_to(int cpu)
{
	cpu_set_t affinity;
	CPU_ZERO(&affinity);
	CPU_SET(cpu, &affinity);
	if (sched_setaffinity(0, sizeof(affinity), &affinity) != 0)
		return -1;
	for (int i = 0; i < 1000 && sched_getcpu() != cpu; ++i)
		usleep(1000);
	return sched_getcpu() == cpu ? 0 : -1;
}

static void *shootdown_reader(void *argument)
{
	if (pin_to((int)(intptr_t)argument) != 0)
		return (void *)1;
	if (sigsetjmp(shootdown_jump, 1) != 0)
		return NULL;
	while (!shootdown_stop) {
		(void)*shootdown_page;
		atomic_fetch_add(&shootdown_reads, 1);
	}
	return NULL;
}

static void *shootdown_writer(void *argument)
{
	if (pin_to((int)(intptr_t)argument) != 0)
		return (void *)1;
	while (!shootdown_stop) {
		++*shootdown_page;
		atomic_fetch_add(&shootdown_reads, 1);
	}
	return NULL;
}

static int wait_for_reads(void)
{
	unsigned long start = atomic_load(&shootdown_reads);
	for (int i = 0; i < 2000 && atomic_load(&shootdown_reads) < start + 1000; ++i)
		usleep(1000);
	CHECK(atomic_load(&shootdown_reads) >= start + 1000);
	return 0;
}

static int test_page_table_changes_reach_every_cpu(void)
{
	long cpus = sysconf(_SC_NPROCESSORS_ONLN);
	CHECK(cpus >= 2);
	/* The helper on the last CPU, this thread on the first. */
	void *other = (void *)(intptr_t)(cpus - 1);
	cpu_set_t original;
	CHECK(sched_getaffinity(0, sizeof(original), &original) == 0);

	/* munmap: a thread reading the page on another CPU faults on its next
	 * read after munmap returns, not whenever its CPU next happens to load
	 * another page map. */
	struct sigaction action = {.sa_handler = shootdown_fault}, previous;
	sigemptyset(&action.sa_mask);
	CHECK(sigaction(SIGSEGV, &action, &previous) == 0);
	shootdown_page = mmap(NULL, 4096, PROT_READ | PROT_WRITE,
	    MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
	CHECK(shootdown_page != MAP_FAILED);
	*shootdown_page = 1;
	shootdown_faulted = 0;
	shootdown_stop = 0;
	pthread_t reader;
	CHECK(pthread_create(&reader, NULL, shootdown_reader, other) == 0);
	CHECK(wait_for_reads() == 0);
	CHECK(pin_to(0) == 0);
	CHECK(munmap((void *)shootdown_page, 4096) == 0);
	unsigned long reads_at_unmap = atomic_load(&shootdown_reads);
	for (int i = 0; i < 1000 && !shootdown_faulted; ++i)
		usleep(1000);
	int faulted = shootdown_faulted;
	shootdown_stop = 1;
	void *pinned;
	CHECK(pthread_join(reader, &pinned) == 0 && pinned == NULL);
	CHECK(sigaction(SIGSEGV, &previous, NULL) == 0);
	if (!faulted || shootdown_reads_at_fault > reads_at_unmap + 16) {
		printf("shootdown: faulted %d, %lu reads after munmap\n", faulted,
		    faulted ? shootdown_reads_at_fault - reads_at_unmap : 0);
		CHECK(0);
	}

	/* fork: a thread writing on another CPU does not write into the child. */
	shootdown_page = mmap(NULL, 4096, PROT_READ | PROT_WRITE,
	    MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
	CHECK(shootdown_page != MAP_FAILED);
	*shootdown_page = 0;
	shootdown_stop = 0;
	CHECK(sched_setaffinity(0, sizeof(original), &original) == 0);
	pthread_t writer;
	CHECK(pthread_create(&writer, NULL, shootdown_writer, other) == 0);
	CHECK(wait_for_reads() == 0);
	CHECK(pin_to(0) == 0);
	pid_t child = fork();
	if (child == 0) {
		unsigned long first = *shootdown_page;
		usleep(100000);
		_exit(*shootdown_page == first ? 0 : 1);
	}
	CHECK(child > 0);
	int status;
	CHECK(waitpid(child, &status, 0) == child);
	shootdown_stop = 1;
	CHECK(pthread_join(writer, &pinned) == 0 && pinned == NULL);
	CHECK(munmap((void *)shootdown_page, 4096) == 0);
	CHECK(sched_setaffinity(0, sizeof(original), &original) == 0);
	CHECK(WIFEXITED(status) && WEXITSTATUS(status) == 0);
	puts("QEMU CORE PASS: page table changes reach every CPU");
	return 0;
}

static volatile sig_atomic_t alarms;

static void count_alarm(int signal)
{
	(void)signal;
	++alarms;
}

static long elapsed_ms(const struct timespec *start)
{
	struct timespec now;
	clock_gettime(CLOCK_MONOTONIC, &now);
	return (now.tv_sec - start->tv_sec) * 1000 + (now.tv_nsec - start->tv_nsec) / 1000000;
}

static _Atomic int yielders_stop;

static void *keep_yielding(void *argument)
{
	(void)argument;
	while (!atomic_load(&yielders_stop))
		sched_yield();
	return NULL;
}

/* alarm(2) and an ITIMER_REAL interval fire when they are due, with every CPU
 * busy going through the scheduler. Each CPU's tick counts the timers down,
 * and arm64 once let a CPU with an older clock reading count a wrap-around:
 * alarm(60) raised SIGALRM in milliseconds. */
static int test_alarm_fires_on_time(void)
{
	long cpus = sysconf(_SC_NPROCESSORS_ONLN);
	pthread_t yielders[8];
	int yielder_count = cpus < 8 ? (int)cpus : 8;
	atomic_store(&yielders_stop, 0);
	for (int i = 0; i < yielder_count; ++i)
		CHECK(pthread_create(&yielders[i], NULL, keep_yielding, NULL) == 0);

	struct sigaction action = {.sa_handler = count_alarm}, previous;
	sigemptyset(&action.sa_mask);
	CHECK(sigaction(SIGALRM, &action, &previous) == 0);

	alarms = 0;
	struct timespec start;
	CHECK(clock_gettime(CLOCK_MONOTONIC, &start) == 0);
	alarm(1);
	while (alarms == 0 && elapsed_ms(&start) < 3000)
		usleep(10000);
	long fired = elapsed_ms(&start);
	CHECK(alarms == 1);
	if (fired < 900 || fired > 2000) {
		printf("alarm(1) fired after %ld ms\n", fired);
		CHECK(0);
	}

	alarms = 0;
	struct itimerval interval = {{0, 50000}, {0, 50000}}, off = {{0, 0}, {0, 0}};
	CHECK(clock_gettime(CLOCK_MONOTONIC, &start) == 0);
	CHECK(setitimer(ITIMER_REAL, &interval, NULL) == 0);
	while (elapsed_ms(&start) < 1000)
		usleep(10000);
	CHECK(setitimer(ITIMER_REAL, &off, NULL) == 0);
	int count = alarms;
	CHECK(sigaction(SIGALRM, &previous, NULL) == 0);
	atomic_store(&yielders_stop, 1);
	for (int i = 0; i < yielder_count; ++i)
		CHECK(pthread_join(yielders[i], NULL) == 0);
	if (count < 10 || count > 25) {
		printf("a 50 ms ITIMER_REAL fired %d times in a second\n", count);
		CHECK(0);
	}
	puts("QEMU CORE PASS: alarm and ITIMER_REAL fire on time");
	return 0;
}

/* mprotect(2) and munmap(2) refuse an address inside a page, as Linux does,
 * rather than change the whole page around it. Raw syscalls: musl's mprotect()
 * rounds the address down itself, glibc's passes it on. */
static int test_unaligned_protection_changes_fail(void)
{
	size_t page = (size_t)sysconf(_SC_PAGESIZE);
	volatile char *area = mmap(NULL, 2 * page, PROT_READ | PROT_WRITE,
	    MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
	CHECK(area != MAP_FAILED);
	errno = 0;
	CHECK(syscall(SYS_mprotect, area + page / 2, page / 2, PROT_NONE) == -1 && errno == EINVAL);
	errno = 0;
	CHECK(syscall(SYS_munmap, area + page / 2, page / 2) == -1 && errno == EINVAL);
	area[0] = 1;
	area[page - 1] = 2;
	CHECK(area[0] == 1 && area[page - 1] == 2);
	CHECK(munmap((void *)area, 2 * page) == 0);
	puts("QEMU CORE PASS: mprotect and munmap refuse an address inside a page");
	return 0;
}

/* An event has room for 64 listeners. More threads than that waiting on one
 * futex see a spurious wake, which they retry, rather than stop the kernel. */
#define MANY_WAITERS 80
#define FUTEX_WAIT_PRIVATE_OP (0 | 128)
#define FUTEX_WAKE_PRIVATE_OP (1 | 128)
static _Atomic int many_waiters_word;
static _Atomic int many_waiters_woken;

static void *many_waiters_thread(void *argument)
{
	(void)argument;
	while (atomic_load(&many_waiters_word) == 0)
		syscall(SYS_futex, &many_waiters_word, FUTEX_WAIT_PRIVATE_OP,
		    0, NULL, NULL, 0);
	atomic_fetch_add(&many_waiters_woken, 1);
	return NULL;
}

static int test_more_waiters_than_an_event_holds(void)
{
	pthread_t threads[MANY_WAITERS];
	for (int i = 0; i < MANY_WAITERS; ++i)
		CHECK(pthread_create(&threads[i], NULL, many_waiters_thread,
		    NULL) == 0);
	usleep(300000);
	atomic_store(&many_waiters_word, 1);
	syscall(SYS_futex, &many_waiters_word, FUTEX_WAKE_PRIVATE_OP,
	    INT_MAX, NULL, NULL, 0);
	for (int i = 0; i < MANY_WAITERS; ++i)
		CHECK(pthread_join(threads[i], NULL) == 0);
	CHECK(atomic_load(&many_waiters_woken) == MANY_WAITERS);
	puts("QEMU CORE PASS: more waiters than an event holds");
	return 0;
}

static volatile sig_atomic_t counted_signals;

static void count_signal(int signal)
{
	(void)signal;
	++counted_signals;
}

/* Wait on an empty pipe for up to three seconds under `mask`: ppoll(2),
 * pselect(2) or epoll_pwait(2). */
static int wait_under_mask(int kind, int fd, const sigset_t *mask)
{
	struct timespec timeout = {3, 0};
	if (kind == 0) {
		struct pollfd descriptor = {.fd = fd, .events = POLLIN};
		return ppoll(&descriptor, 1, &timeout, mask);
	}
	if (kind == 1) {
		fd_set readable;
		FD_ZERO(&readable);
		FD_SET(fd, &readable);
		return pselect(fd + 1, &readable, NULL, NULL, &timeout, mask);
	}
	int poller = epoll_create1(0);
	if (poller < 0)
		return -2;
	struct epoll_event watched = {.events = EPOLLIN, .data.fd = fd}, ready;
	if (epoll_ctl(poller, EPOLL_CTL_ADD, fd, &watched) != 0)
		return -2;
	int result = epoll_pwait(poller, &ready, 1, 3000, mask);
	int error = errno;
	close(poller);
	errno = error;
	return result;
}

static int usr1_blocked_and_not_pending(void)
{
	sigset_t mask, pending;
	CHECK(sigprocmask(SIG_BLOCK, NULL, &mask) == 0);
	CHECK(sigismember(&mask, SIGUSR1));
	CHECK(sigpending(&pending) == 0);
	CHECK(!sigismember(&pending, SIGUSR1));
	return 0;
}

/* A wait does not start with a signal already pending that it does not block,
 * and the handler of a signal that only the wait's own mask lets in runs under
 * that mask: ppoll(2), pselect(2) and epoll_pwait(2) end at once with EINTR,
 * the handler runs, and the mask from before comes back afterwards. A wait
 * that ends for anything else puts its caller's mask back first, and the
 * signal stays pending. */
static int test_wait_ends_for_a_pending_signal(void)
{
	struct sigaction action = {.sa_handler = count_signal}, previous;
	sigemptyset(&action.sa_mask);
	CHECK(sigaction(SIGUSR1, &action, &previous) == 0);
	sigset_t blocked, original, open;
	sigemptyset(&blocked);
	sigaddset(&blocked, SIGUSR1);
	CHECK(sigprocmask(SIG_BLOCK, &blocked, &original) == 0);
	open = original;
	sigdelset(&open, SIGUSR1);
	int fds[2];
	CHECK(pipe(fds) == 0);

	for (int kind = 0; kind < 3; ++kind) {
		counted_signals = 0;
		CHECK(kill(getpid(), SIGUSR1) == 0);
		struct timespec start, end;
		CHECK(clock_gettime(CLOCK_MONOTONIC, &start) == 0);
		errno = 0;
		int ready = wait_under_mask(kind, fds[0], &open);
		int error = errno;
		CHECK(clock_gettime(CLOCK_MONOTONIC, &end) == 0);
		CHECK(ready == -1 && error == EINTR);
		CHECK(end.tv_sec - start.tv_sec < 2);
		CHECK(counted_signals == 1);
		CHECK(usr1_blocked_and_not_pending() == 0);
	}

	counted_signals = 0;
	CHECK(write(fds[1], "x", 1) == 1);
	CHECK(kill(getpid(), SIGUSR1) == 0);
	struct pollfd descriptor = {.fd = fds[0], .events = POLLIN};
	CHECK(ppoll(&descriptor, 1, NULL, &open) == 1);
	CHECK(counted_signals == 0);
	sigset_t pending;
	CHECK(sigpending(&pending) == 0);
	CHECK(sigismember(&pending, SIGUSR1));
	CHECK(sigprocmask(SIG_SETMASK, &open, NULL) == 0);
	CHECK(counted_signals == 1);

	CHECK(sigprocmask(SIG_SETMASK, &original, NULL) == 0);
	CHECK(sigaction(SIGUSR1, &previous, NULL) == 0);
	CHECK(close(fds[0]) == 0 && close(fds[1]) == 0);
	puts("QEMU CORE PASS: a wait ends for a signal already pending");
	return 0;
}

/* V3 makes the V `int` type pointer-width. Linux still defines pollfd.fd as a
 * 32-bit C int, so exercise the structure from a real libc caller: widening
 * the kernel field makes it combine fd/events into one invalid descriptor. */
static int test_pollfd_abi(void)
{
	int pair[2];
	CHECK(pipe(pair) == 0);
	struct pollfd descriptor = {
		.fd = pair[0],
		.events = POLLIN,
	};
	CHECK(poll(&descriptor, 1, 0) == 0);
	CHECK(descriptor.revents == 0);
	CHECK(write(pair[1], "p", 1) == 1);
	CHECK(poll(&descriptor, 1, 1000) == 1);
	CHECK((descriptor.revents & POLLIN) != 0);
	char byte = 0;
	CHECK(read(pair[0], &byte, 1) == 1);
	CHECK(byte == 'p');
	CHECK(close(pair[0]) == 0);
	CHECK(close(pair[1]) == 0);
	puts("QEMU CORE PASS: Linux pollfd ABI");
	return 0;
}

/* A blocking write larger than PIPE_BUF alternates between filling the pipe
 * and waiting for the reader to make room. Both directions share the pipe's
 * event. A reader used to be able to consume the "space available" wake in
 * the gap before the writer attached, then wait for data itself; the empty
 * pipe was left with both ends asleep forever. Keep enough transfers in one
 * syscall to exercise that hand-off repeatedly on the SMP VM. */
static int test_large_pipe_progress(void)
{
	enum { transfer_size = 2 * 1024 * 1024 };
	unsigned char *payload = malloc(transfer_size);
	unsigned char *observed = malloc(transfer_size);
	CHECK(payload != NULL && observed != NULL);
	for (size_t i = 0; i < transfer_size; ++i)
		payload[i] = (unsigned char)(i * 73u + 19u);

	int pair[2];
	CHECK(pipe(pair) == 0);
	CHECK(fcntl(pair[0], F_GETPIPE_SZ) >= 64 * 1024);
	/* Capacity is not the progress mechanism. Force the old one-page size so
	 * this transfer still has to exercise the blocking wake-up handshake. */
	CHECK(fcntl(pair[0], F_SETPIPE_SZ, 4096) == 4096);
	CHECK(fcntl(pair[0], F_GETPIPE_SZ) == 4096);

	/* PIPE_BUF is a distinct atomicity threshold. A larger nonblocking write
	 * may fill the available buffer partially, whereas a PIPE_BUF-sized write
	 * must not leak a prefix when even one byte of room is missing. Growing an
	 * occupied pipe also has to preserve its byte stream. */
	int writer_flags = fcntl(pair[1], F_GETFL);
	CHECK(writer_flags >= 0);
	CHECK(fcntl(pair[1], F_SETFL, writer_flags | O_NONBLOCK) == 0);
	CHECK(write(pair[1], payload, 8192) == 4096);
	CHECK(fcntl(pair[0], F_SETPIPE_SZ, 4097) == 8192);
	CHECK(read(pair[0], observed, 4096) == 4096);
	CHECK(memcmp(payload, observed, 4096) == 0);
	CHECK(fcntl(pair[0], F_SETPIPE_SZ, 4096) == 4096);
	CHECK(write(pair[1], payload, 1) == 1);
	errno = 0;
	CHECK(write(pair[1], payload, 4096) == -1 && errno == EAGAIN);
	CHECK(read(pair[0], observed, 1) == 1 && observed[0] == payload[0]);
	CHECK(fcntl(pair[1], F_SETFL, writer_flags) == 0);

	pid_t writer = fork();
	CHECK(writer >= 0);
	if (writer == 0) {
		close(pair[0]);
		ssize_t wrote = write(pair[1], payload, transfer_size);
		close(pair[1]);
		_exit(wrote == transfer_size ? 0 : 1);
	}

	CHECK(close(pair[1]) == 0);
	/* Turn a regression into a bounded test failure instead of letting the
	 * whole VM wait forever on the same deadlock this test is checking. */
	alarm(20);
	size_t received = 0;
	while (received < transfer_size) {
		ssize_t got = read(pair[0], observed + received,
		    transfer_size - received);
		CHECK(got > 0);
		received += (size_t)got;
	}
	alarm(0);
	CHECK(memcmp(payload, observed, transfer_size) == 0);
	CHECK(close(pair[0]) == 0);
	CHECK(reap_ok(writer) == 0);
	free(observed);
	free(payload);
	puts("QEMU CORE PASS: large blocking pipe transfer makes progress");
	return 0;
}

/* qemu-user translates an x86 epoll_event into the native AArch64 layout
 * before entering Vinix. Verify both that layout and the syscall result: a
 * wrong stride or a returned byte count makes userspace consume uninitialised
 * events, which is especially destructive to Wine's server protocol. */
static int test_epoll_abi_and_count(void)
{
	int pair[2];
	CHECK(pipe(pair) == 0);
	int epoll = epoll_create1(EPOLL_CLOEXEC);
	CHECK(epoll >= 0);
	struct epoll_event requested = {
		.events = EPOLLIN,
		.data.u64 = UINT64_C(0x56494e495845504f),
	};
	CHECK(epoll_ctl(epoll, EPOLL_CTL_ADD, pair[0], &requested) == 0);

	struct epoll_event observed[4];
	memset(observed, 0xa5, sizeof(observed));
	CHECK(epoll_wait(epoll, observed, 4, 0) == 0);
	CHECK(write(pair[1], "e", 1) == 1);
	CHECK(epoll_wait(epoll, observed, 4, 1000) == 1);
	CHECK((observed[0].events & EPOLLIN) != 0);
	CHECK(observed[0].data.u64 == requested.data.u64);

	char byte = 0;
	CHECK(read(pair[0], &byte, 1) == 1);
	CHECK(byte == 'e');
	CHECK(epoll_wait(epoll, observed, 4, 0) == 0);
	CHECK(close(epoll) == 0);
	CHECK(close(pair[0]) == 0);
	CHECK(close(pair[1]) == 0);
	puts("QEMU CORE PASS: Linux epoll ABI and event count");
	return 0;
}

/* The AArch64 syscall ABI leaves the unused high half of C-int arguments
 * unspecified. qemu-user zero-extends AT_FDCWD while translating x86 open(2),
 * and the kernel must truncate it before interpreting the signed value. */
static int test_syscall_int_truncation(void)
{
	long descriptor = syscall(SYS_openat, UINT64_C(0x00000000ffffff9c), ".",
	    O_RDONLY, 0);
	CHECK(descriptor >= 0);
	CHECK(close((int)descriptor) == 0);
	puts("QEMU CORE PASS: syscall C-int truncation");
	return 0;
}

/* An abstract socket name belongs to the socket that bound it, and has to come
 * back when that socket goes. Leaking it reserved the name for the life of the
 * machine: an X server that had been restarted could not bind its own display
 * again, and every hosted application after the first failed to start. */
static int test_abstract_socket_reuse(void)
{
	struct sockaddr_un address;
	const char name[] = "\0vinix-core-abstract";
	socklen_t length = offsetof(struct sockaddr_un, sun_path) + sizeof(name) - 1;

	for (int attempt = 0; attempt < 3; ++attempt) {
		memset(&address, 0, sizeof(address));
		address.sun_family = AF_UNIX;
		memcpy(address.sun_path, name, sizeof(name) - 1);

		int listener = socket(AF_UNIX, SOCK_STREAM, 0);
		CHECK(listener >= 0);
		CHECK(bind(listener, (struct sockaddr *)&address, length) == 0);
		CHECK(listen(listener, 4) == 0);

		int client = socket(AF_UNIX, SOCK_STREAM, 0);
		CHECK(client >= 0);
		CHECK(connect(client, (struct sockaddr *)&address, length) == 0);
		int served = accept(listener, NULL, NULL);
		CHECK(served >= 0);
		CHECK(close(served) == 0);
		CHECK(close(client) == 0);
		CHECK(close(listener) == 0);
	}

	/* And a name nobody holds is not connectable. */
	int probe = socket(AF_UNIX, SOCK_STREAM, 0);
	CHECK(probe >= 0);
	memset(&address, 0, sizeof(address));
	address.sun_family = AF_UNIX;
	memcpy(address.sun_path, name, sizeof(name) - 1);
	CHECK(connect(probe, (struct sockaddr *)&address, length) != 0);
	CHECK(close(probe) == 0);

	puts("QEMU CORE PASS: abstract socket names are released");
	return 0;
}

#if defined(__x86_64__)
/* x86-64's calls from before the *at() family and getdents64, which older
 * programs and static binaries still make: utime(2), utimes(2), futimesat(2)
 * and getdents(2), whose struct linux_dirent has the type in its last byte. */
struct linux_dirent_legacy {
	unsigned long d_ino;
	unsigned long d_off;
	unsigned short d_reclen;
	char d_name[];
};

static int timestamp_is(const struct timespec *at, time_t seconds, long nanoseconds)
{
	return at->tv_sec == seconds && at->tv_nsec == nanoseconds;
}

static int test_x86_legacy_file_calls(void)
{
	static const char dir[] = "/tmp/x86-legacy";
	char path[64];
	CHECK(mkdir(dir, 0755) == 0);
	for (int i = 0; i < 5; ++i) {
		snprintf(path, sizeof(path), "%s/file-%d", dir, i);
		int fd = open(path, O_CREAT | O_EXCL | O_WRONLY, 0644);
		CHECK(fd >= 0);
		CHECK(close(fd) == 0);
	}
	snprintf(path, sizeof(path), "%s/sub", dir);
	CHECK(mkdir(path, 0755) == 0);

	/* Every entry once, a few at a time; a buffer too small for one is
	 * EINVAL, and does not lose the entry. */
	int fd = open(dir, O_RDONLY | O_DIRECTORY);
	CHECK(fd >= 0);
	char small[16];
	errno = 0;
	CHECK(syscall(SYS_getdents, fd, small, sizeof(small)) == -1 && errno == EINVAL);
	int files = 0, subdirectories = 0;
	for (;;) {
		char buf[96] __attribute__((aligned(8)));
		long got = syscall(SYS_getdents, fd, buf, sizeof(buf));
		CHECK(got >= 0);
		if (got == 0)
			break;
		for (long at = 0; at < got;) {
			struct linux_dirent_legacy *entry = (void *)(buf + at);
			CHECK(entry->d_reclen >= 24 && entry->d_reclen % 8 == 0);
			CHECK(at + entry->d_reclen <= got);
			unsigned char type = (unsigned char)buf[at + entry->d_reclen - 1];
			if (strncmp(entry->d_name, "file-", 5) == 0) {
				CHECK(type == DT_REG);
				++files;
			} else if (strcmp(entry->d_name, "sub") == 0) {
				CHECK(type == DT_DIR);
				++subdirectories;
			}
			at += entry->d_reclen;
		}
	}
	CHECK(files == 5 && subdirectories == 1);
	CHECK(close(fd) == 0);

	/* utime: whole seconds, or now. */
	snprintf(path, sizeof(path), "%s/file-0", dir);
	struct stat st;
	const long utimbuf[2] = {1000000000, 1000000100};
	CHECK(syscall(SYS_utime, path, utimbuf) == 0);
	CHECK(stat(path, &st) == 0);
	CHECK(timestamp_is(&st.st_atim, 1000000000, 0));
	CHECK(timestamp_is(&st.st_mtim, 1000000100, 0));
	time_t now = time(NULL);
	CHECK(syscall(SYS_utime, path, NULL) == 0);
	CHECK(stat(path, &st) == 0);
	CHECK(st.st_mtim.tv_sec >= now - 5 && st.st_mtim.tv_sec <= now + 5);
	errno = 0;
	CHECK(syscall(SYS_utime, "/tmp/x86-legacy/none", utimbuf) == -1 && errno == ENOENT);

	/* utimes: microseconds, which must be whole and less than a second. */
	struct timeval timevals[2] = {{1100000000, 250000}, {1100000100, 750000}};
	CHECK(syscall(SYS_utimes, path, timevals) == 0);
	CHECK(stat(path, &st) == 0);
	CHECK(timestamp_is(&st.st_atim, 1100000000, 250000000));
	CHECK(timestamp_is(&st.st_mtim, 1100000100, 750000000));
	timevals[1].tv_usec = 1000000;
	errno = 0;
	CHECK(syscall(SYS_utimes, path, timevals) == -1 && errno == EINVAL);
	timevals[1].tv_usec = -1;
	errno = 0;
	CHECK(syscall(SYS_utimes, path, timevals) == -1 && errno == EINVAL);

	/* futimesat: relative to a directory, or with no path the file a
	 * descriptor is open on. */
	struct timeval later[2] = {{1200000000, 1}, {1200000100, 2}};
	int dirfd = open(dir, O_RDONLY | O_DIRECTORY);
	CHECK(dirfd >= 0);
	CHECK(syscall(SYS_futimesat, dirfd, "file-1", later) == 0);
	CHECK(fstatat(dirfd, "file-1", &st, 0) == 0);
	CHECK(timestamp_is(&st.st_atim, 1200000000, 1000));
	CHECK(timestamp_is(&st.st_mtim, 1200000100, 2000));
	CHECK(close(dirfd) == 0);
	snprintf(path, sizeof(path), "%s/file-2", dir);
	int file = open(path, O_RDONLY);
	CHECK(file >= 0);
	CHECK(syscall(SYS_futimesat, file, NULL, later) == 0);
	CHECK(fstat(file, &st) == 0);
	CHECK(timestamp_is(&st.st_mtim, 1200000100, 2000));
	CHECK(close(file) == 0);

	for (int i = 0; i < 5; ++i) {
		snprintf(path, sizeof(path), "%s/file-%d", dir, i);
		CHECK(unlink(path) == 0);
	}
	snprintf(path, sizeof(path), "%s/sub", dir);
	CHECK(rmdir(path) == 0);
	CHECK(rmdir(dir) == 0);
	puts("QEMU CORE PASS: x86-64 utime, utimes, futimesat and getdents");
	return 0;
}

/* struct user_desc, which modify_ldt(2) and set_thread_area(2) take. */
struct x86_user_desc {
	unsigned int entry_number;
	unsigned int base_addr;
	unsigned int limit;
	unsigned int seg_32bit : 1;
	unsigned int contents : 2;
	unsigned int read_exec_only : 1;
	unsigned int limit_in_pages : 1;
	unsigned int seg_not_present : 1;
	unsigned int useable : 1;
	unsigned int lm : 1;
};

/* Selector n of the LDT, and TLS entry n of the GDT, both of privilege 3. */
#define LDT_SELECTOR(n) ((unsigned short)((n) << 3 | 7))
#define TLS_SELECTOR(n) ((unsigned short)((n) << 3 | 3))

/* 32-bit code and the data segments point at run below 4 GiB, all that
 * compatibility mode and a descriptor's base reach: code in the first page,
 * data in the second, whose second half keeps what run32() saves. */
#define LOW_PAGE ((uintptr_t)0x30000000)
#define LOW_DATA ((volatile uint64_t *)(LOW_PAGE + 4096))
#define LOW_SAVE (LOW_PAGE + 4096 + 2048)

static long modify_ldt_call(int func, void *ptr, unsigned long count)
{
	return syscall(SYS_modify_ldt, func, ptr, count);
}

/* A 32-bit segment of privilege 3 in LDT entry `entry`: data for contents 0,
 * code for contents 2. */
static int set_ldt(unsigned entry, uintptr_t base, unsigned limit, unsigned contents, unsigned pages)
{
	struct x86_user_desc d = {
		.entry_number = entry, .base_addr = (unsigned)base, .limit = limit,
		.seg_32bit = 1, .contents = contents & 3, .limit_in_pages = pages & 1,
	};
	return (int)modify_ldt_call(0x11, &d, sizeof(d));
}

static int clear_ldt(unsigned entry)
{
	struct x86_user_desc d = {.entry_number = entry, .read_exec_only = 1, .seg_not_present = 1};
	return (int)modify_ldt_call(0x11, &d, sizeof(d));
}

static void load_gs(unsigned short selector)
{
	__asm__ volatile("mov %0, %%gs" : : "r"(selector) : "memory");
}

static unsigned short gs_selector(void)
{
	unsigned short selector;
	__asm__ volatile("mov %%gs, %0" : "=r"(selector));
	return selector;
}

static uint64_t gs_word(unsigned long offset)
{
	uint64_t value;
	__asm__ volatile("mov %%gs:(%1), %0" : "=r"(value) : "r"(offset) : "memory");
	return value;
}

static void load_ds(unsigned short selector)
{
	__asm__ volatile("mov %0, %%ds" : : "r"(selector) : "memory");
}

static unsigned short ds_selector(void)
{
	unsigned short selector;
	__asm__ volatile("mov %%ds, %0" : "=r"(selector));
	return selector;
}

static unsigned char *put_u32(unsigned char *at, uint32_t value)
{
	memcpy(at, &value, sizeof(value));
	return at + sizeof(value);
}

/* Put 32-bit code `body` in the low page, for run32() to run from code
 * segment `cs32`. The 64-bit code around it saves the registers the caller
 * keeps and the stack pointer in the data page, far-returns to the body, and
 * puts them back when it far-jumps back. The body may not use the stack. */
static int load_32bit_code(unsigned short cs32, const unsigned char *body, size_t length)
{
	static const unsigned char rex[7] = {0x48, 0x48, 0x48, 0x4c, 0x4c, 0x4c, 0x4c};
	static const unsigned char modrm[7] = {0x24, 0x1c, 0x2c, 0x24, 0x2c, 0x34, 0x3c};
	unsigned short cs64;
	__asm__ volatile("mov %%cs, %0" : "=r"(cs64));
	unsigned char *code = (unsigned char *)LOW_PAGE;
	if (mprotect(code, 4096, PROT_READ | PROT_WRITE) != 0)
		return -1;
	unsigned char *at = code;
	for (int i = 0; i < 7; ++i) { /* mov %rsp, %rbx, %rbp, %r12-%r15 to the save area */
		*at++ = rex[i];
		*at++ = 0x89;
		*at++ = modrm[i];
		*at++ = 0x25;
		at = put_u32(at, (uint32_t)(LOW_SAVE + 8 * i));
	}
	*at++ = 0x68; /* push $cs32 */
	at = put_u32(at, cs32);
	*at++ = 0x68; /* push $body */
	at = put_u32(at, (uint32_t)(LOW_PAGE + 0x100));
	*at++ = 0x48; /* lretq */
	*at++ = 0xcb;
	at = code + 0x100;
	memcpy(at, body, length);
	at += length;
	*at++ = 0xea; /* ljmp $cs64, $back */
	at = put_u32(at, (uint32_t)(LOW_PAGE + 0x200));
	*at++ = (unsigned char)cs64;
	*at++ = (unsigned char)(cs64 >> 8);
	at = code + 0x200;
	for (int i = 0; i < 7; ++i) {
		*at++ = rex[i];
		*at++ = 0x8b;
		*at++ = modrm[i];
		*at++ = 0x25;
		at = put_u32(at, (uint32_t)(LOW_SAVE + 8 * i));
	}
	*at++ = 0xc3; /* ret */
	return mprotect(code, 4096, PROT_READ | PROT_EXEC);
}

/* What the 32-bit code left in eax. */
static unsigned run32(void)
{
	return ((unsigned (*)(void))LOW_PAGE)();
}

static const unsigned char body_result[] = {0xb8, 0x5e, 0xb5, 0xeb, 0x5e}; /* mov $0x5eebb55e, %eax */
/* mov $100000000, %ecx; 1: dec %ecx; jnz 1b; mov $0x600df00d, %eax */
static const unsigned char body_loop[] = {0xb9, 0x00, 0xe1, 0xf5, 0x05, 0x49, 0x75, 0xfd,
	0xb8, 0x0d, 0xf0, 0x0d, 0x60};
static const unsigned char body_spin[] = {0xeb, 0xfe}; /* 1: jmp 1b */
static const unsigned char body_syscall[] = {0x0f, 0x05}; /* syscall */

static volatile sig_atomic_t alarms_in_32bit_code;

static void count_alarm_in_32bit_code(int signal, siginfo_t *info, void *context)
{
	(void)signal;
	(void)info;
	ucontext_t *uc = context;
	if ((uc->uc_mcontext.gregs[REG_CSGSFS] & 0xffff) == LDT_SELECTOR(1))
		++alarms_in_32bit_code;
}

/* In a child of its own: the signals leave nothing behind in the test. */
static int signals_in_32bit_code_child(void)
{
	static char altstack[65536];
	stack_t alternate = {.ss_sp = altstack, .ss_size = sizeof(altstack)};
	struct sigaction action = {.sa_sigaction = count_alarm_in_32bit_code,
		.sa_flags = SA_SIGINFO | SA_ONSTACK};
	sigemptyset(&action.sa_mask);
	struct itimerval every = {{0, 5000}, {0, 5000}}, off = {{0, 0}, {0, 0}};
	if (sigaltstack(&alternate, NULL) != 0 || sigaction(SIGALRM, &action, NULL) != 0
	    || load_32bit_code(LDT_SELECTOR(1), body_loop, sizeof(body_loop)) != 0
	    || setitimer(ITIMER_REAL, &every, NULL) != 0)
		return 1;
	unsigned looped = 0;
	for (int round = 0; round < 20 && alarms_in_32bit_code < 3; ++round)
		looped = run32();
	if (setitimer(ITIMER_REAL, &off, NULL) != 0)
		return 2;
	if (looped != 0x600df00d)
		return 3;
	return alarms_in_32bit_code >= 3 ? 0 : 4;
}

struct tls_worker {
	volatile uint64_t *word;
	int ok;
};

/* Two of these share one CPU and one TLS entry number, each with its own
 * descriptor: switching between them has to swap what that entry is. */
static void *tls_worker(void *argument)
{
	struct tls_worker *worker = argument;
	cpu_set_t one;
	CPU_ZERO(&one);
	CPU_SET(sysconf(_SC_NPROCESSORS_ONLN) > 1 ? 1 : 0, &one);
	if (sched_setaffinity(0, sizeof(one), &one) != 0)
		return NULL;
	struct x86_user_desc d = {
		.entry_number = 13, .base_addr = (unsigned)(uintptr_t)worker->word, .limit = 7,
		.seg_32bit = 1,
	};
	if (syscall(SYS_set_thread_area, &d) != 0)
		return NULL;
	load_gs(TLS_SELECTOR(13));
	for (int i = 0; i < 2000; ++i) {
		if (gs_selector() != TLS_SELECTOR(13) || gs_word(0) != *worker->word)
			return NULL;
		sched_yield();
	}
	load_gs(0);
	worker->ok = 1;
	return NULL;
}

static void *inherited_gs(void *argument)
{
	(void)argument;
	struct x86_user_desc d = {.entry_number = 14};
	if (syscall(SYS_get_thread_area, &d) != 0 || d.base_addr != (unsigned)(uintptr_t)&LOW_DATA[2])
		return NULL;
	return gs_selector() == TLS_SELECTOR(14) && gs_word(0) == LOW_DATA[2] ? argument : NULL;
}

static atomic_int stale_ready, stale_seen;

/* A data segment that goes while a thread has it in DS or GS is loaded null
 * where the thread has it next: on the way out of a syscall, out of an
 * interrupt, or on its way back onto a CPU. */
static void *stale_ds_in_syscalls(void *argument)
{
	(void)argument;
	load_ds(LDT_SELECTOR(2));
	atomic_fetch_add(&stale_ready, 1);
	for (long i = 0; i < 5000000; ++i) {
		getppid();
		if (ds_selector() == 0) {
			atomic_fetch_add(&stale_seen, 1);
			break;
		}
	}
	return NULL;
}

static void *stale_ds_without_syscalls(void *argument)
{
	(void)argument;
	load_ds(LDT_SELECTOR(3));
	atomic_fetch_add(&stale_ready, 1);
	for (long i = 0; i < 2000000000L; ++i) {
		if (ds_selector() == 0) {
			atomic_fetch_add(&stale_seen, 1);
			break;
		}
	}
	return NULL;
}

static void *stale_gs_while_asleep(void *argument)
{
	(void)argument;
	load_gs(LDT_SELECTOR(4));
	atomic_fetch_add(&stale_ready, 1);
	for (int i = 0; i < 5000; ++i) {
		usleep(1000);
		if (gs_selector() == 0) {
			atomic_fetch_add(&stale_seen, 1);
			break;
		}
	}
	return NULL;
}

static int stale_segments_child(void)
{
	if (set_ldt(2, 0, 0xfffff, 0, 1) != 0 || set_ldt(3, 0, 0xfffff, 0, 1) != 0
	    || set_ldt(4, (uintptr_t)&LOW_DATA[0], 7, 0, 0) != 0)
		return 1;
	pthread_t threads[3];
	void *(*const bodies[3])(void *) = {stale_ds_in_syscalls, stale_ds_without_syscalls,
		stale_gs_while_asleep};
	for (int i = 0; i < 3; ++i)
		if (pthread_create(&threads[i], NULL, bodies[i], NULL) != 0)
			return 2;
	while (atomic_load(&stale_ready) != 3)
		usleep(1000);
	usleep(20000);
	if (clear_ldt(2) != 0 || clear_ldt(3) != 0 || clear_ldt(4) != 0)
		return 3;
	for (int i = 0; i < 3; ++i)
		pthread_join(threads[i], NULL);
	return atomic_load(&stale_seen) == 3 ? 0 : 4;
}

static atomic_int spinning;

static void *spin_in_32bit_code(void *argument)
{
	(void)argument;
	atomic_store(&spinning, 1);
	run32();
	return NULL;
}

/* A code segment that goes from under a thread running in it: the thread
 * cannot be resumed there, and takes a SIGSEGV. On a CPU of its own it finds
 * out on the way back from an interrupt, and sharing one with the thread that
 * takes the segment away, when the scheduler resumes it. */
static int stale_code_segment_child(int one_cpu)
{
	if (one_cpu) {
		cpu_set_t first;
		CPU_ZERO(&first);
		CPU_SET(0, &first);
		if (sched_setaffinity(0, sizeof(first), &first) != 0)
			return 5;
	}
	if (load_32bit_code(LDT_SELECTOR(1), body_spin, sizeof(body_spin)) != 0)
		return 1;
	pthread_t thread;
	if (pthread_create(&thread, NULL, spin_in_32bit_code, NULL) != 0)
		return 2;
	while (!atomic_load(&spinning))
		usleep(1000);
	usleep(20000);
	if (clear_ldt(1) != 0)
		return 3;
	sleep(5);
	return 4;
}

/* A handler that sends sigreturn to a code segment of privilege 0, or to
 * none, only gets its thread a SIGSEGV. */
static unsigned short forged_cs;

static void forge_code_segment(int signal, siginfo_t *info, void *context)
{
	(void)signal;
	(void)info;
	ucontext_t *uc = context;
	uc->uc_mcontext.gregs[REG_CSGSFS] = (uc->uc_mcontext.gregs[REG_CSGSFS] & ~0xffffLL) | forged_cs;
}

static int forged_code_segment_child(unsigned short cs)
{
	forged_cs = cs;
	struct sigaction action = {.sa_sigaction = forge_code_segment, .sa_flags = SA_SIGINFO};
	sigemptyset(&action.sa_mask);
	if (sigaction(SIGUSR1, &action, NULL) != 0)
		return 1;
	raise(SIGUSR1);
	return 2;
}

static int exec_segment_probe(void)
{
	unsigned char ldt[64];
	if (modify_ldt_call(0, ldt, sizeof(ldt)) != 0)
		return 1;
	for (unsigned entry = 12; entry <= 14; ++entry) {
		struct x86_user_desc d = {.entry_number = entry};
		if (syscall(SYS_get_thread_area, &d) != 0 || d.base_addr != 0 || !d.seg_not_present)
			return 2;
	}
	return gs_selector() == 0 ? 0 : 3;
}

static int test_x86_segments(void)
{
	void *low = mmap((void *)LOW_PAGE, 8192, PROT_READ | PROT_WRITE,
	    MAP_PRIVATE | MAP_ANONYMOUS | MAP_FIXED, -1, 0);
	CHECK(low == (void *)LOW_PAGE);
	LOW_DATA[0] = 0x1122334455667788ULL;
	LOW_DATA[1] = 0x99aabbccddeeff00ULL;
	LOW_DATA[2] = 0x0123456789abcdefULL;
	LOW_DATA[3] = 0xfedcba9876543210ULL;

	/* set_thread_area: the first free TLS entry, 12, which GS then reaches
	 * through the selector for it, across syscalls, sleeps and CPUs. */
	struct x86_user_desc tls = {
		.entry_number = (unsigned)-1, .base_addr = (unsigned)(uintptr_t)&LOW_DATA[0],
		.limit = 0xfff, .seg_32bit = 1, .useable = 1,
	};
	CHECK(syscall(SYS_set_thread_area, &tls) == 0);
	CHECK(tls.entry_number == 12);
	load_gs(TLS_SELECTOR(12));
	CHECK(gs_word(0) == LOW_DATA[0] && gs_word(8) == LOW_DATA[1]);
	for (int i = 0; i < 200; ++i) {
		sched_yield();
		if (i % 50 == 0)
			usleep(2000);
		CHECK(gs_selector() == TLS_SELECTOR(12) && gs_word(8) == LOW_DATA[1]);
	}
	struct x86_user_desc got = {.entry_number = 12};
	CHECK(syscall(SYS_get_thread_area, &got) == 0);
	CHECK(got.base_addr == tls.base_addr && got.limit == 0xfff && got.seg_32bit && got.useable);
	CHECK(got.contents == 0 && !got.read_exec_only && !got.limit_in_pages && !got.seg_not_present);
	struct x86_user_desc more = tls;
	more.entry_number = (unsigned)-1;
	CHECK(syscall(SYS_set_thread_area, &more) == 0 && more.entry_number == 13);
	more.entry_number = (unsigned)-1;
	more.base_addr = (unsigned)(uintptr_t)&LOW_DATA[2];
	CHECK(syscall(SYS_set_thread_area, &more) == 0 && more.entry_number == 14);
	more.entry_number = (unsigned)-1;
	errno = 0;
	CHECK(syscall(SYS_set_thread_area, &more) == -1 && errno == ESRCH);
	/* No 16-bit segment, no code and no entry outside the three. */
	more = tls;
	more.entry_number = 13;
	more.seg_32bit = 0;
	errno = 0;
	CHECK(syscall(SYS_set_thread_area, &more) == -1 && errno == EINVAL);
	more.seg_32bit = 1;
	more.contents = 2;
	errno = 0;
	CHECK(syscall(SYS_set_thread_area, &more) == -1 && errno == EINVAL);
	more.contents = 0;
	more.entry_number = 11;
	errno = 0;
	CHECK(syscall(SYS_set_thread_area, &more) == -1 && errno == EINVAL);
	/* A new thread starts with the descriptors and selectors it was made
	 * with. */
	load_gs(TLS_SELECTOR(14));
	pthread_t thread;
	void *result = NULL;
	CHECK(pthread_create(&thread, NULL, inherited_gs, &tls) == 0);
	CHECK(pthread_join(thread, &result) == 0 && result == &tls);
	/* Emptying the entry GS has loads GS null. */
	struct x86_user_desc empty = {.entry_number = 14, .read_exec_only = 1, .seg_not_present = 1};
	CHECK(syscall(SYS_set_thread_area, &empty) == 0);
	CHECK(gs_selector() == 0);
	got.entry_number = 14;
	CHECK(syscall(SYS_get_thread_area, &got) == 0);
	CHECK(got.base_addr == 0 && got.limit == 0 && got.seg_not_present && got.read_exec_only);
	empty.entry_number = 12;
	CHECK(syscall(SYS_set_thread_area, &empty) == 0);
	empty.entry_number = 13;
	CHECK(syscall(SYS_set_thread_area, &empty) == 0);
	/* Each thread has its own, even on one CPU. */
	struct tls_worker workers[2] = {{&LOW_DATA[1], 0}, {&LOW_DATA[3], 0}};
	pthread_t worker_threads[2];
	for (int i = 0; i < 2; ++i)
		CHECK(pthread_create(&worker_threads[i], NULL, tls_worker, &workers[i]) == 0);
	for (int i = 0; i < 2; ++i)
		CHECK(pthread_join(worker_threads[i], NULL) == 0);
	CHECK(workers[0].ok && workers[1].ok);

	/* modify_ldt: nothing to read before there is an LDT, and Linux's
	 * default one is 128 bytes of zeroes. */
	unsigned char ldt[64];
	CHECK(modify_ldt_call(0, ldt, sizeof(ldt)) == 0);
	unsigned char default_ldt[256];
	memset(default_ldt, 0xff, sizeof(default_ldt));
	CHECK(modify_ldt_call(2, default_ldt, sizeof(default_ldt)) == 128);
	for (int i = 0; i < 128; ++i)
		CHECK(default_ldt[i] == 0);
	CHECK(default_ldt[128] == 0xff);
	/* Errors are negative ints, zero-extended, as Linux returns them. */
	struct x86_user_desc d = {.entry_number = 0, .base_addr = 0, .limit = 0xfffff,
		.seg_32bit = 1, .limit_in_pages = 1};
	CHECK(modify_ldt_call(0x11, &d, sizeof(d) - 1) == (long)(unsigned)-EINVAL);
	CHECK(modify_ldt_call(3, &d, sizeof(d)) == (long)(unsigned)-ENOSYS);
	d.entry_number = 8192;
	CHECK(modify_ldt_call(0x11, &d, sizeof(d)) == (long)(unsigned)-EINVAL);
	d.entry_number = 0;
	d.seg_32bit = 0;
	CHECK(modify_ldt_call(0x11, &d, sizeof(d)) == (long)(unsigned)-EINVAL);
	d.seg_32bit = 1;
	d.contents = 3;
	CHECK(modify_ldt_call(0x11, &d, sizeof(d)) == (long)(unsigned)-EINVAL);

	/* A data segment in entry 0, reached through GS and read back. */
	CHECK(set_ldt(0, (uintptr_t)&LOW_DATA[1], 15, 0, 0) == 0);
	load_gs(LDT_SELECTOR(0));
	CHECK(gs_word(0) == LOW_DATA[1] && gs_word(8) == LOW_DATA[2]);
	memset(ldt, 0xff, sizeof(ldt));
	CHECK(modify_ldt_call(0, ldt, sizeof(ldt)) == (long)sizeof(ldt));
	uint64_t descriptor;
	memcpy(&descriptor, ldt, sizeof(descriptor));
	uint32_t base = (uint32_t)(((descriptor >> 16) & 0xffffff) | (((descriptor >> 56) & 0xff) << 24));
	CHECK(base == (uint32_t)(uintptr_t)&LOW_DATA[1]);
	CHECK((descriptor & 0xffff) == 15 && ((descriptor >> 45) & 3) == 3);
	for (size_t i = 8; i < sizeof(ldt); ++i)
		CHECK(ldt[i] == 0);
	load_gs(0);

	/* A flat 32-bit code segment in entry 1, which 64-bit code far-calls
	 * into and back out of. */
	CHECK(set_ldt(1, 0, 0xfffff, 2, 1) == 0);
	CHECK(load_32bit_code(LDT_SELECTOR(1), body_result, sizeof(body_result)) == 0);
	CHECK(run32() == 0x5eebb55e);
	/* Interrupted, switched away from and sent signals while it runs, whose
	 * handlers run in 64-bit mode and return to it. */
	pid_t child = fork();
	CHECK(child >= 0);
	if (child == 0)
		_exit(signals_in_32bit_code_child());
	CHECK(reap_ok(child) == 0);

	/* fork copies the LDT, and what the child changes is its own. */
	child = fork();
	CHECK(child >= 0);
	if (child == 0) {
		unsigned char copy[64];
		if (modify_ldt_call(0, copy, sizeof(copy)) != (long)sizeof(copy))
			_exit(1);
		if (load_32bit_code(LDT_SELECTOR(1), body_result, sizeof(body_result)) != 0
		    || run32() != 0x5eebb55e)
			_exit(2);
		_exit(clear_ldt(1) == 0 && clear_ldt(0) == 0 ? 0 : 3);
	}
	CHECK(reap_ok(child) == 0);
	CHECK(load_32bit_code(LDT_SELECTOR(1), body_result, sizeof(body_result)) == 0);
	CHECK(run32() == 0x5eebb55e);

	/* exec leaves the new program no LDT and no TLS descriptors. */
	child = fork();
	CHECK(child >= 0);
	if (child == 0) {
		struct x86_user_desc mine = tls;
		mine.entry_number = 12;
		if (syscall(SYS_set_thread_area, &mine) != 0)
			_exit(10);
		load_gs(TLS_SELECTOR(12));
		char *const argv[] = {"/sbin/init", "--exec-segment-probe", NULL};
		execv(argv[0], argv);
		_exit(11);
	}
	CHECK(reap_ok(child) == 0);

	/* A segment another thread takes away is loaded null where the thread
	 * next has it, and a code segment taken from under a thread gets it a
	 * SIGSEGV: neither faults the kernel. */
	child = fork();
	CHECK(child >= 0);
	if (child == 0)
		_exit(stale_segments_child());
	CHECK(reap_ok(child) == 0);
	int status;
	for (int one_cpu = 0; one_cpu < 2; ++one_cpu) {
		child = fork();
		CHECK(child >= 0);
		if (child == 0)
			_exit(stale_code_segment_child(one_cpu));
		CHECK(waitpid(child, &status, 0) == child);
		CHECK(WIFSIGNALED(status) && WTERMSIG(status) == SIGSEGV);
	}
	/* None, the kernel's own 64-bit code (gdt.kernel_code_selector), which
	 * sigreturn must not return to with privilege 0, and an empty entry. */
	const unsigned short forged[] = {0, 0x28, LDT_SELECTOR(5)};
	for (size_t i = 0; i < sizeof(forged) / sizeof(forged[0]); ++i) {
		child = fork();
		CHECK(child >= 0);
		if (child == 0)
			_exit(forged_code_segment_child(forged[i]));
		CHECK(waitpid(child, &status, 0) == child);
		CHECK(WIFSIGNALED(status) && WTERMSIG(status) == SIGSEGV);
	}
	/* SYSCALL from 32-bit code has no way back: SIGILL. */
	child = fork();
	CHECK(child >= 0);
	if (child == 0) {
		if (load_32bit_code(LDT_SELECTOR(1), body_syscall, sizeof(body_syscall)) == 0)
			run32();
		_exit(1);
	}
	CHECK(waitpid(child, &status, 0) == child);
	CHECK(WIFSIGNALED(status) && WTERMSIG(status) == SIGILL);

	/* Every change is a new LDT, and the old one is given back. */
	unsigned long before = free_ram();
	for (int i = 0; i < 1000; ++i)
		CHECK(set_ldt(4000, (uintptr_t)&LOW_DATA[i & 3], 7, 0, 0) == 0);
	unsigned long after = free_ram();
	if (after + 8UL * 1024 * 1024 < before) {
		printf("LDT churn: free before %lu, after %lu\n", before, after);
		CHECK(0);
	}

	CHECK(clear_ldt(0) == 0 && clear_ldt(1) == 0 && clear_ldt(4000) == 0);
	CHECK(munmap(low, 8192) == 0);
	puts("QEMU CORE PASS: x86-64 TLS descriptors, LDT and 32-bit code");
	return 0;
}
#endif

static int run_tests(void)
{
	int persistence_boot = verify_persistence_boot();
	CHECK(persistence_boot >= 0);
	if (persistence_boot == 1)
		return 0;
	CHECK(test_random() == 0);
	/* Keep the pipe progress regression ahead of unrelated scheduler stress
	 * cases so a failure there cannot prevent this foundational hand-off from
	 * being exercised. */
	CHECK(test_large_pipe_progress() == 0);
	CHECK(test_empty_pipe_buffers() == 0);
	CHECK(test_sparse_tmpfs_shared_mapping() == 0);
	CHECK(test_cow() == 0);
	CHECK(test_anonymous_first_touch() == 0);
	CHECK(test_syscall_buffers_in_untouched_pages() == 0);
	CHECK(test_partial_munmap_reclaims_pages() == 0);
	CHECK(test_split_keeps_pages_a_sharer_unmaps() == 0);
	CHECK(test_madvise_reclaims_anonymous_pages() == 0);
	CHECK(test_short_lived_process_memory_reclamation() == 0);
	CHECK(test_forked_cow_memory_reclamation() == 0);
	CHECK(test_interrupted_nanosleep_remaining() == 0);
	CHECK(test_anonymous_ipc_memory_reclamation() == 0);
	CHECK(test_socket_interface_box_reclamation() == 0);
	CHECK(test_unix_socket_buffer_growth() == 0);
	CHECK(test_unix_socket_full_write_readiness() == 0);
	CHECK(test_futex_wake_op() == 0);
	CHECK(test_alarm_fires_on_time() == 0);
	CHECK(test_unaligned_protection_changes_fail() == 0);
	CHECK(test_more_waiters_than_an_event_holds() == 0);
	CHECK(test_fork_inherits_process_state() == 0);
	CHECK(test_cpuinfo() == 0);
	CHECK(test_joined_threads_return_their_memory() == 0);
	CHECK(test_console_controls_a_session() == 0);
	CHECK(test_page_table_changes_reach_every_cpu() == 0);
	CHECK(test_fifo_keeps_its_cpu() == 0);
	CHECK(test_frozen_cgroup_stops_its_threads() == 0);
	CHECK(test_wait_ends_for_a_pending_signal() == 0);
	CHECK(test_default_terminating_signals() == 0);
	CHECK(test_signals_reach_a_busy_loop() == 0);
	CHECK(test_syscall_restart() == 0);
	CHECK(test_exit_takes_down_blocked_threads() == 0);
	CHECK(prepare_directory() == 0);
	CHECK(test_ext2_mapping_and_namespace() == 0);
	CHECK(test_private_file_mapping() == 0);
	CHECK(test_partial_munmap_returns_pages() == 0);
	CHECK(test_shared_mapping_visible_to_readers() == 0);
	CHECK(test_released_pid_is_not_reused_while_its_group_lives() == 0);
	CHECK(test_locks() == 0);
	CHECK(test_permissions_and_limits() == 0);
	CHECK(test_inotify() == 0);
	CHECK(test_scheduler_and_accounting() == 0);
	CHECK(test_concurrent_wakeups_queue_once() == 0);
	CHECK(test_posix_timer_thread_notification() == 0);
	CHECK(test_anonymous_descriptor_access() == 0);
	CHECK(test_pollfd_abi() == 0);
	CHECK(test_epoll_abi_and_count() == 0);
	CHECK(test_syscall_int_truncation() == 0);
	CHECK(test_abstract_socket_reuse() == 0);
#if defined(__x86_64__)
	CHECK(test_x86_legacy_file_calls() == 0);
	CHECK(test_x86_segments() == 0);
#endif
	CHECK(unlink(file_a) == 0);
	CHECK(unlink(file_b) == 0);
	CHECK(unlink(file_c) == 0);
	int synced = open(synced_file, O_CREAT | O_EXCL | O_WRONLY, 0600);
	CHECK(synced >= 0);
	CHECK(write(synced, synced_payload, sizeof(synced_payload) - 1) ==
	    (ssize_t)(sizeof(synced_payload) - 1));
	CHECK(close(synced) == 0);
	/* No O_SYNC and no descriptor left open: sync(2) is the only thing that
	 * can still get this to the disk. Written before the O_SYNC marker so the
	 * verification boot cannot pass on that one alone. */
	sync();
	int fd = open(persist_file, O_CREAT | O_EXCL | O_WRONLY | O_SYNC, 0600);
	CHECK(fd >= 0);
	CHECK(write(fd, persist_payload, sizeof(persist_payload) - 1) ==
	    (ssize_t)(sizeof(persist_payload) - 1));
	CHECK(fsync(fd) == 0);
	CHECK(close(fd) == 0);
	puts("QEMU CORE PASS: persistence markers synchronized");
	puts("VINIX QEMU CORE: PASS");
	return 0;
}

/* What an exec'd program finds, checked by the program exec'd in
 * test_short_lived_process_memory_reclamation(): its argument strings laid
 * out as Linux lays them out, argv[0] lowest, and an auxiliary vector both on
 * its stack and in /proc/self/auxv. */
static int exec_probe(char **argv)
{
	if (argv[0] >= argv[1])
		return 1;
	if (getauxval(AT_PAGESZ) == 0 || getauxval(AT_RANDOM) == 0)
		return 2;
	int fd = open("/proc/self/auxv", O_RDONLY);
	if (fd < 0)
		return 3;
	unsigned long entry[2];
	ssize_t got = read(fd, entry, sizeof(entry));
	close(fd);
	return got == (ssize_t)sizeof(entry) ? 0 : 4;
}

int main(int argc, char **argv)
{
	if (argc == 2 && strcmp(argv[1], "--exec-memory-probe") == 0)
		return exec_probe(argv);
#if defined(__x86_64__)
	if (argc == 2 && strcmp(argv[1], "--exec-segment-probe") == 0)
		return exec_segment_probe();
#endif
	setbuf(stdout, NULL);
	setbuf(stderr, NULL);
	if (getpid() != 1)
		return run_tests();
	/* amd64's console is the framebuffer; its serial port is /dev/com1. */
	int console = open("/dev/com1", O_WRONLY | O_NOCTTY);
	if (console < 0)
		console = open("/dev/console", O_WRONLY | O_NOCTTY);
	if (console >= 0) {
		dup2(console, STDOUT_FILENO);
		dup2(console, STDERR_FILENO);
		close(console);
	}
	puts("VINIX QEMU CORE: START");
	pid_t worker = fork();
	if (worker == 0)
		_exit(run_tests());
	if (worker < 0 || reap_ok(worker) != 0)
		puts("VINIX QEMU CORE: FAIL");
	for (;;)
		sleep(1);
}
