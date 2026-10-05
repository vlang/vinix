/* tmpfs keeps a file of up to 2 KiB in one small allocation and anything
 * larger in pages. PID 1 checks that a file reads back what was written to it
 * whichever of the two it is in and however it got from one to the other, and
 * that many files cost about what they hold. */
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

#define MIB (1024ULL * 1024ULL)
#define KIB 1024ULL

static void require_at(int ok, const char *why, int line) {
	if (ok) return;
	printf("TMPFS-LAYOUT FAIL %s (line %d) errno=%d\n", why, line, errno);
	fflush(stdout);
	_exit(1);
}
#define require(ok, why) require_at((ok), (why), __LINE__)

static unsigned long long meminfo(const char *name) {
	char text[4096];
	int fd = open("/proc/meminfo", O_RDONLY);
	require(fd >= 0, "open meminfo");
	ssize_t count = read(fd, text, sizeof(text) - 1);
	require(count > 0, "read meminfo");
	close(fd);
	text[count] = 0;
	const char *line = strstr(text, name);
	require(line != NULL, "meminfo field");
	return strtoull(line + strlen(name), NULL, 10) * 1024ULL;
}

/* Byte `at` of a file's contents, different for each file and never zero, so
 * that a zero read back is a hole and nothing else. */
static unsigned char pattern(size_t seed, size_t at) {
	return (unsigned char)(1 + (seed * 131 + at * 7 + at / 251) % 255);
}

static unsigned char *buffer;
static unsigned char *check;
#define BUFFER_SIZE (2 * MIB)

static void expect_contents(const char *path, size_t seed, size_t size) {
	struct stat st;
	require(stat(path, &st) == 0 && (size_t)st.st_size == size, "size");
	int fd = open(path, O_RDONLY);
	require(fd >= 0, "open for reading");
	size_t total = 0;
	for (;;) {
		ssize_t count = read(fd, check + total, BUFFER_SIZE - total);
		require(count >= 0, "read");
		if (count == 0) break;
		total += (size_t)count;
	}
	close(fd);
	require(total == size, "read to the end");
	for (size_t at = 0; at < size; at++)
		if (check[at] != pattern(seed, at)) {
			printf("TMPFS-LAYOUT size=%zu at=%zu got=%u want=%u\n", size, at, check[at],
				pattern(seed, at));
			require(0, "contents");
		}
}

/* A file of `size` bytes written `chunk` at a time. */
static void written_in_chunks(size_t size, size_t chunk) {
	const char *path = "/tmp/layout";
	size_t seed = size * 31 + chunk;
	for (size_t at = 0; at < size; at++) buffer[at] = pattern(seed, at);
	int fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0600);
	require(fd >= 0, "create");
	for (size_t at = 0; at < size; at += chunk) {
		size_t length = size - at < chunk ? size - at : chunk;
		require(write(fd, buffer + at, length) == (ssize_t)length, "write a chunk");
	}
	close(fd);
	expect_contents(path, seed, size);
	/* Written over in place, back to front, a piece at a time. */
	seed++;
	for (size_t at = 0; at < size; at++) buffer[at] = pattern(seed, at);
	fd = open(path, O_WRONLY);
	require(fd >= 0, "reopen");
	for (size_t end = size; end > 0;) {
		size_t length = end < chunk ? end : chunk;
		end -= length;
		require(pwrite(fd, buffer + end, length, (off_t)end) == (ssize_t)length, "overwrite");
	}
	close(fd);
	expect_contents(path, seed, size);
	require(unlink(path) == 0, "unlink");
}

static void expect_bytes(int fd, off_t from, size_t length, int value, const char *why) {
	require(pread(fd, check, length, from) == (ssize_t)length, why);
	for (size_t at = 0; at < length; at++) require(check[at] == (unsigned char)value, why);
}

/* Holes, and bytes left behind a truncation, read as zeroes on both sides of
 * the size at which a file moves into pages. */
static void holes_and_truncation(void) {
	const char *path = "/tmp/holes";
	static const size_t offsets[] = {10, 1000, 2047, 2048, 5000, 70000};
	for (unsigned i = 0; i < sizeof(offsets) / sizeof(offsets[0]); i++) {
		int fd = open(path, O_RDWR | O_CREAT | O_TRUNC, 0600);
		require(fd >= 0, "create");
		require(pwrite(fd, "x", 1, (off_t)offsets[i]) == 1, "write past the start");
		expect_bytes(fd, 0, offsets[i], 0, "a hole reads as zeroes");
		expect_bytes(fd, (off_t)offsets[i], 1, 'x', "the byte after the hole");
		close(fd);
	}

	static const size_t sizes[] = {300, 2048, 3000, 100000};
	for (unsigned i = 0; i < sizeof(sizes) / sizeof(sizes[0]); i++) {
		size_t size = sizes[i];
		int fd = open(path, O_RDWR | O_CREAT | O_TRUNC, 0600);
		require(fd >= 0, "create");
		memset(buffer, 'a', size);
		require(write(fd, buffer, size) == (ssize_t)size, "fill");
		require(ftruncate(fd, 50) == 0, "shrink");
		require(ftruncate(fd, (off_t)size) == 0, "grow back");
		expect_bytes(fd, 0, 50, 'a', "what a truncation kept");
		expect_bytes(fd, 50, size - 50, 0, "what a truncation cut reads as zeroes");
		require(ftruncate(fd, 20) == 0, "shrink again");
		require(pwrite(fd, "z", 1, (off_t)size - 1) == 1, "write past the new end");
		expect_bytes(fd, 20, size - 21, 0, "a write past the end leaves zeroes behind it");
		expect_bytes(fd, (off_t)size - 1, 1, 'z', "the byte written past the end");
		close(fd);
	}
	require(unlink(path) == 0, "unlink");
}

/* A small file that grows past the limit a write, an append and a truncation
 * at a time keeps what it held. */
static void growth_across_the_limit(void) {
	const char *path = "/tmp/grow";
	size_t seed = 77;
	for (size_t at = 0; at < 200000; at++) buffer[at] = pattern(seed, at);

	int fd = open(path, O_RDWR | O_CREAT | O_TRUNC | O_APPEND, 0600);
	require(fd >= 0, "create");
	require(write(fd, buffer, 2000) == 2000, "below the limit");
	require(write(fd, buffer + 2000, 100) == 100, "across the limit");
	require(write(fd, buffer + 2100, 197900) == 197900, "well past the limit");
	close(fd);
	expect_contents(path, seed, 200000);

	fd = open(path, O_RDWR | O_CREAT | O_TRUNC, 0600);
	require(fd >= 0, "recreate");
	require(write(fd, buffer, 1500) == 1500, "below the limit");
	require(ftruncate(fd, 9000) == 0, "grow past the limit");
	expect_bytes(fd, 1500, 7500, 0, "grown past the limit reads as zeroes");
	require(pwrite(fd, buffer + 1500, 7500, 1500) == 7500, "fill what was grown");
	close(fd);
	expect_contents(path, seed, 9000);
	require(unlink(path) == 0, "unlink");
}

/* A mapping of a small file sees its bytes, and a shared one writes them. */
static void mappings(void) {
	const char *path = "/tmp/mapped";
	size_t seed = 5;
	static const size_t sizes[] = {100, 2048, 6000};
	for (unsigned i = 0; i < sizeof(sizes) / sizeof(sizes[0]); i++) {
		size_t size = sizes[i];
		for (size_t at = 0; at < size; at++) buffer[at] = pattern(seed, at);
		int fd = open(path, O_RDWR | O_CREAT | O_TRUNC, 0600);
		require(fd >= 0, "create");
		require(write(fd, buffer, size) == (ssize_t)size, "fill");

		unsigned char *view = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_PRIVATE, fd, 0);
		require(view != MAP_FAILED, "private mapping");
		require(memcmp(view, buffer, size) == 0, "a private mapping sees the file");
		view[0] ^= 0xff;
		expect_bytes(fd, 0, 1, buffer[0], "a private mapping's write stays its own");
		require(munmap(view, size) == 0, "unmap");

		view = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
		require(view != MAP_FAILED, "shared mapping");
		require(memcmp(view, buffer, size) == 0, "a shared mapping sees the file");
		view[size - 1] = 0;
		buffer[size - 1] = 0;
		expect_bytes(fd, (off_t)size - 1, 1, 0, "a shared mapping's write reaches the file");
		/* And the file's own writes reach the mapping. */
		require(pwrite(fd, "q", 1, 3) == 1, "write under a shared mapping");
		require(view[3] == 'q', "a write reaches a shared mapping");
		require(munmap(view, size) == 0, "unmap");
		close(fd);
	}
	require(unlink(path) == 0, "unlink");
}

/* `count` files of `size` bytes each may take `limit` bytes of memory. */
static void cost_of_files(unsigned count, size_t size, unsigned long long limit) {
	char path[64];
	memset(buffer, 0x6b, size);
	mkdir("/tmp/many", 0700);
	unsigned long long before = meminfo("MemFree:");
	for (unsigned i = 0; i < count; i++) {
		snprintf(path, sizeof(path), "/tmp/many/%u", i);
		int fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0600);
		require(fd >= 0, "create one of many");
		require(write(fd, buffer, size) == (ssize_t)size, "write one of many");
		close(fd);
	}
	unsigned long long after = meminfo("MemFree:");
	unsigned long long cost = before > after ? before - after : 0;
	printf("TMPFS-LAYOUT %u files of %zu bytes hold %lluK and cost %lluK\n", count, size,
		(unsigned long long)count * size / KIB, cost / KIB);
	require(cost <= limit, "files cost about what they hold");
	for (unsigned i = 0; i < count; i++) {
		snprintf(path, sizeof(path), "/tmp/many/%u", i);
		require(unlink(path) == 0, "remove one of many");
	}
	require(rmdir("/tmp/many") == 0, "remove the directory");
}

int main(void) {
	setvbuf(stdout, NULL, _IONBF, 0);
	if (access("/proc/meminfo", R_OK) < 0)
		require(mount("proc", "/proc", "proc", 0, NULL) == 0, "mount proc");
	mkdir("/tmp", 0777);
	buffer = malloc(BUFFER_SIZE);
	check = malloc(BUFFER_SIZE);
	require(buffer != NULL && check != NULL, "buffers");

	static const size_t sizes[] = {0, 1, 63, 64, 65, 100, 1000, 2047, 2048, 2049, 4095, 4096,
		4097, 16384, 65536, 70000, 1048576, 1048577};
	static const size_t chunks[] = {1, 7, 100, 4096, 2 * 1024 * 1024};
	for (unsigned i = 0; i < sizeof(sizes) / sizeof(sizes[0]); i++)
		for (unsigned j = 0; j < sizeof(chunks) / sizeof(chunks[0]); j++) {
			/* A byte at a time is for the sizes near the limit. */
			if (chunks[j] < 100 && sizes[i] > 5000) continue;
			written_in_chunks(sizes[i], chunks[j]);
		}
	puts("TMPFS-LAYOUT PASS files of every size read back what was written");

	holes_and_truncation();
	puts("TMPFS-LAYOUT PASS holes and truncated tails read as zeroes");
	growth_across_the_limit();
	puts("TMPFS-LAYOUT PASS a file growing into pages keeps what it held");
	mappings();
	puts("TMPFS-LAYOUT PASS mappings of small files");

	/* A hundred bytes took two pages each, 32 KiB of them where a page is
	 * 16 KiB; 70 KiB took 132 KiB. Now: the file, its name and its inode. */
	cost_of_files(10000, 100, 48 * MIB);
	cost_of_files(2000, 70 * KIB, 2000 * 70 * KIB / 100 * 130);
	puts("TMPFS-LAYOUT PASS files cost about what they hold");
	puts("TMPFS-LAYOUT PASS all");
	for (;;) pause();
}
