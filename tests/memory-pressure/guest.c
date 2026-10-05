#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/epoll.h>
#include <sys/mount.h>
#include <sys/mman.h>
#include <unistd.h>

static void require(int ok, const char *why) {
	if (ok) return;
	printf("VM-PRESSURE FAIL %s errno=%d\n", why, errno);
	fflush(stdout);
	_exit(1);
}

static int ready(int fd) {
	struct pollfd p = {.fd = fd, .events = POLLIN};
	int n = poll(&p, 1, 0);
	require(n >= 0, "poll");
	return n == 1 && (p.revents & POLLIN);
}

static void acknowledge(int fd) {
	char text[512];
	require(lseek(fd, 0, SEEK_SET) == 0, "seek");
	ssize_t count = read(fd, text, sizeof(text) - 1);
	require(count > 0, "read");
	text[count] = 0;
	require(strstr(text, "level ") && strstr(text, "generation ") &&
		strstr(text, "reclaim_runs ") && strstr(text, "allocation_failures "), "fields");
	require(read(fd, text, sizeof(text)) == 0, "snapshot EOF");
}

static unsigned long long field(const char *text, const char *name) {
	const char *start = strstr(text, name);
	require(start != NULL, "numeric field");
	return strtoull(start + strlen(name), NULL, 10);
}

static void pressure_transition(void) {
	int fd = open("/proc/vmpressure", O_RDONLY);
	require(fd >= 0, "transition subscribe");
	char text[512];
	ssize_t count = read(fd, text, sizeof(text) - 1);
	require(count > 0, "transition baseline");
	text[count] = 0;
	unsigned long long free_bytes = field(text, "free_bytes ");
	unsigned long long low = field(text, "low_bytes ");
	require(strstr(text, "level normal\n") != NULL, "normal baseline");
	// Leave 3/4 of low for kernel work and fault bookkeeping. This bounded
	// guest has 1 GiB RAM and no desktop; avoid deliberately exhausting it.
	require(free_bytes > low * 2, "memory reserve");
	size_t length = (size_t)(free_bytes - low * 3 / 4);
	volatile unsigned char *pages = mmap(NULL, length, PROT_READ | PROT_WRITE,
		MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
	require(pages != MAP_FAILED, "pressure mapping");
	for (size_t offset = 0; offset < length; offset += 4096) pages[offset] = 1;
	struct pollfd wait = {.fd = fd, .events = POLLIN};
	require(poll(&wait, 1, 10000) == 1 && (wait.revents & POLLIN), "pressure notification");
	require(lseek(fd, 0, SEEK_SET) == 0, "pressure seek");
	count = read(fd, text, sizeof(text) - 1);
	require(count > 0, "pressure state");
	text[count] = 0;
	require(strstr(text, "level warning\n") || strstr(text, "level critical\n"), "pressure level");
	require(field(text, "reclaim_runs ") > 0, "background reclaim attempts");
	require(munmap((void *)pages, length) == 0, "release pressure mapping");
	wait.revents = 0;
	require(poll(&wait, 1, 10000) == 1 && (wait.revents & POLLIN), "recovery notification");
	require(lseek(fd, 0, SEEK_SET) == 0, "recovery seek");
	count = read(fd, text, sizeof(text) - 1);
	require(count > 0, "recovery read");
	text[count] = 0;
	require(strstr(text, "level normal\n") != NULL, "normal recovery");
	close(fd);
}

int main(void) {
	setvbuf(stdout, NULL, _IONBF, 0);
	if (access("/proc/meminfo", R_OK) < 0)
		require(mount("proc", "/proc", "proc", 0, NULL) == 0, "mount proc");
	int a = open("/proc/vmpressure", O_RDONLY | O_NONBLOCK);
	int b = open("/proc/vmpressure", O_RDONLY);
	require(a >= 0 && b >= 0, "independent opens");
	require(ready(a) && ready(b), "initial readiness");
	acknowledge(a);
	require(!ready(a) && ready(b), "independent consumption");
	int duplicate = dup(b);
	require(duplicate >= 0, "dup");
	acknowledge(duplicate);
	require(!ready(b), "dup shares consumption");
	int ep = epoll_create1(EPOLL_CLOEXEC);
	require(ep >= 0, "epoll create");
	struct epoll_event registration = {.events = EPOLLIN, .data.fd = a};
	require(epoll_ctl(ep, EPOLL_CTL_ADD, a, &registration) == 0, "epoll register");
	struct epoll_event observed;
	require(epoll_wait(ep, &observed, 1, 0) == 0, "epoll consumed state");
	close(a); close(b); close(duplicate); close(ep);
	pressure_transition();

	for (int round = 0; round < 3; round++) {
		int descriptors[64];
		for (int i = 0; i < 64; i++) {
			descriptors[i] = open("/proc/vmpressure", O_RDONLY);
			require(descriptors[i] >= 0, "bounded subscription open");
		}
		errno = 0;
		int extra = open("/proc/vmpressure", O_RDONLY);
		require(extra < 0 && errno == ENOSPC, "subscription cap");
		for (int i = 0; i < 64; i++) close(descriptors[i]);
	}
	puts("VM-PRESSURE PASS independent snapshots, poll/epoll, pressure/recovery, dup, limit and reuse");
	for (;;) pause();
}
