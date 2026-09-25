// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

/* SPDX-License-Identifier: GPL-2.0-or-later
 * Copyright (c) 2026 Alexander Medvednikov
 *
 * A large write must not stop the machine, as PID 1 on a disk root. A desktop
 * froze while vinix-host-sync downloaded a 5 GB archive into /tmp: the block
 * cache of the system disk filled with dirty pages, and writing them back held
 * the lock every read of the disk waits for, with interrupts off, for seconds
 * at a time. Launching an application meant reading its executable, so it
 * timed out, and the CPUs waiting for that lock took the desktop down with it.
 *
 * One thread streams a file far larger than the cache while others do what
 * the rest of a desktop does meanwhile -- read a file already in the cache,
 * create and remove small files, sleep for a tick -- and each records the
 * longest it had to wait. The writeback thread's passes over the dirty cache
 * are what the waits are measured against.
 */
#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/reboot.h>
#include <time.h>
#include <unistd.h>

#define MIB (1024ul * 1024ul)
#define CHUNK (64ul * 1024ul)
#define READERS 2

static const char *probe_path = "/tmp/vinix-writeback-probe";
static const char *stream_path = "/tmp/vinix-writeback-stream";

static unsigned long stream_mib = 768;
/* Longest any one of the others may be kept waiting. A writeback pass that
 * held the disk for the whole of its flush kept them waiting 25 s on a quiet
 * host and over 100 s on a busy one. Waits of a few seconds remain on a busy
 * host: every change to a directory still flushes what is dirty, up to the
 * cache's dirty limit, with the filesystem's lock held. */
static unsigned long limit_ms = 10000;

static atomic_int stopping;

struct watch {
	const char *name;
	unsigned long long worst_ns;
	unsigned long long total_ns;
	unsigned long count;
	int failed;
};

static struct watch readers[READERS];
static struct watch creator = { .name = "create+unlink" };
static struct watch ticker = { .name = "2 ms sleep" };

static unsigned long long now_ns(void)
{
	struct timespec ts;
	clock_gettime(CLOCK_MONOTONIC, &ts);
	return (unsigned long long)ts.tv_sec * 1000000000ull + (unsigned long long)ts.tv_nsec;
}

static void note(struct watch *w, unsigned long long took)
{
	if (took > w->worst_ns)
		w->worst_ns = took;
	w->total_ns += took;
	w->count++;
}

static void pause_ms(long ms)
{
	struct timespec ts = { .tv_sec = ms / 1000, .tv_nsec = (ms % 1000) * 1000000l };
	nanosleep(&ts, NULL);
}

static void *read_probe(void *argument)
{
	struct watch *w = argument;
	int fd = open(probe_path, O_RDONLY);
	if (fd < 0) {
		w->failed = errno;
		return NULL;
	}
	char block[4096];
	unsigned long round = 0;
	while (!atomic_load(&stopping)) {
		unsigned long long start = now_ns();
		ssize_t got = pread(fd, block, sizeof block, (off_t)((round % 16) * sizeof block));
		note(w, now_ns() - start);
		if (got != (ssize_t)sizeof block) {
			w->failed = got < 0 ? errno : EIO;
			break;
		}
		round++;
		pause_ms(1);
	}
	close(fd);
	return NULL;
}

/* A file created, written, closed and removed: what an application does with
 * a log or a lock file, and each step asks EXT2 to put its metadata on disk. */
static void *create_files(void *argument)
{
	struct watch *w = argument;
	char path[64];
	unsigned long round = 0;
	while (!atomic_load(&stopping)) {
		snprintf(path, sizeof path, "/tmp/vinix-writeback-small-%lu", round % 4);
		unsigned long long start = now_ns();
		int fd = open(path, O_CREAT | O_TRUNC | O_WRONLY, 0644);
		if (fd < 0) {
			w->failed = errno;
			break;
		}
		ssize_t wrote = write(fd, path, strlen(path));
		close(fd);
		unlink(path);
		note(w, now_ns() - start);
		if (wrote != (ssize_t)strlen(path)) {
			w->failed = EIO;
			break;
		}
		round++;
		pause_ms(250);
	}
	return NULL;
}

/* Needs nothing from the disk: only for the scheduler to still be running. */
static void *tick(void *argument)
{
	struct watch *w = argument;
	while (!atomic_load(&stopping)) {
		unsigned long long start = now_ns();
		pause_ms(2);
		unsigned long long slept = now_ns() - start;
		note(w, slept > 2000000ull ? slept - 2000000ull : 0);
	}
	return NULL;
}

static int make_probe(void)
{
	int fd = open(probe_path, O_CREAT | O_TRUNC | O_RDWR, 0644);
	if (fd < 0)
		return -1;
	char block[4096];
	for (int i = 0; i < 16; i++) {
		memset(block, 'a' + i, sizeof block);
		if (write(fd, block, sizeof block) != (ssize_t)sizeof block) {
			close(fd);
			return -1;
		}
	}
	fsync(fd);
	/* Leave it in the cache: what is measured is waiting, not reading. */
	for (int i = 0; i < 16; i++)
		if (pread(fd, block, sizeof block, (off_t)(i * sizeof block)) != (ssize_t)sizeof block) {
			close(fd);
			return -1;
		}
	close(fd);
	return 0;
}

static int stream(unsigned long long *took)
{
	char *chunk = malloc(CHUNK);
	if (chunk == NULL)
		return -1;
	int fd = open(stream_path, O_CREAT | O_TRUNC | O_WRONLY, 0644);
	if (fd < 0) {
		free(chunk);
		return -1;
	}
	unsigned long long start = now_ns();
	unsigned long total = stream_mib * MIB;
	unsigned long reported = 0;
	for (unsigned long done = 0; done < total; done += CHUNK) {
		memset(chunk, (int)(done / CHUNK), CHUNK);
		if (write(fd, chunk, CHUNK) != (ssize_t)CHUNK) {
			int saved = errno;
			close(fd);
			free(chunk);
			errno = saved;
			return -1;
		}
		if (done / (128 * MIB) != reported) {
			reported = done / (128 * MIB);
			printf("VINIX WRITEBACK: streamed %lu MiB\n", done / MIB);
			fflush(stdout);
		}
	}
	*took = now_ns() - start;
	/* No fsync and no close yet: the dirty pages are the writeback thread's. */
	pause_ms(12000);
	close(fd);
	free(chunk);
	return 0;
}

static void show(const struct watch *w)
{
	unsigned long long mean_us = w->count ? w->total_ns / w->count / 1000ull : 0;
	printf("VINIX WRITEBACK: %-14s worst %llu ms, mean %llu us over %lu\n", w->name,
	       w->worst_ns / 1000000ull, mean_us, w->count);
}

static int judge(const struct watch *w)
{
	unsigned long long worst_ms = w->worst_ns / 1000000ull;
	if (w->failed) {
		printf("VINIX WRITEBACK: FAIL %s stopped with errno %d\n", w->name, w->failed);
		return 1;
	}
	if (w->count == 0) {
		printf("VINIX WRITEBACK: FAIL %s never ran\n", w->name);
		return 1;
	}
	if (worst_ms > limit_ms) {
		printf("VINIX WRITEBACK: FAIL %s waited %llu ms, limit %lu ms\n", w->name, worst_ms,
		       limit_ms);
		return 1;
	}
	return 0;
}

int main(void)
{
	setvbuf(stdout, NULL, _IOLBF, 0);
	printf("VINIX WRITEBACK: START\n");
	if (make_probe() != 0) {
		printf("VINIX WRITEBACK: FAIL cannot make %s errno=%d\n", probe_path, errno);
		return 1;
	}

	pthread_t threads[READERS + 2];
	for (int i = 0; i < READERS; i++) {
		readers[i].name = i == 0 ? "cached read 1" : "cached read 2";
		pthread_create(&threads[i], NULL, read_probe, &readers[i]);
	}
	pthread_create(&threads[READERS], NULL, create_files, &creator);
	pthread_create(&threads[READERS + 1], NULL, tick, &ticker);

	unsigned long long took = 0;
	int streamed = stream(&took);
	int saved = errno;
	atomic_store(&stopping, 1);
	for (int i = 0; i < READERS + 2; i++)
		pthread_join(threads[i], NULL);
	if (streamed != 0) {
		printf("VINIX WRITEBACK: FAIL streaming %s errno=%d\n", stream_path, saved);
		return 1;
	}
	printf("VINIX WRITEBACK: streamed %lu MiB in %llu ms\n", stream_mib, took / 1000000ull);

	unsigned long long start = now_ns();
	sync();
	printf("VINIX WRITEBACK: final sync %llu ms\n", (now_ns() - start) / 1000000ull);
	unlink(stream_path);
	unlink(probe_path);

	/* Every measurement first: the runner stops reading at the first FAIL. */
	const struct watch *watches[] = { &readers[0], &readers[1], &creator, &ticker };
	int failures = 0;
	for (unsigned i = 0; i < sizeof watches / sizeof watches[0]; i++)
		show(watches[i]);
	for (unsigned i = 0; i < sizeof watches / sizeof watches[0]; i++)
		failures += judge(watches[i]);
	if (failures == 0)
		printf("VINIX WRITEBACK: PASS\n");
	sync();
	reboot(RB_POWER_OFF);
	printf("VINIX WRITEBACK: FAIL power off refused\n");
	return 1;
}
