/* SPDX-License-Identifier: GPL-2.0-or-later */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <limits.h>
#include <signal.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>
#include "../../tools/security-audit/collector_v.h"
#define number vka_number
#define parse_snapshot vka_parse_snapshot
#define collect vka_collect
#define end_pending vka_end_pending
#define log_stat vka_log_stat
#define directory_stat vka_directory_stat
#define open_log_at vka_open_log_at
#define open_log vka_open_log
#define append vka_append
#define read_snapshot vka_read_snapshot
#define collector_main vka_main
#define add vka_add

#define CHECK(x) do { if (!(x)) { fprintf(stderr, "collector test line %d: %s (errno=%d)\n", __LINE__, #x, errno); return 1; } } while (0)

static void fixture(struct snapshot *s, uint64_t total)
{
	memset(s, 0, sizeof(*s));
	strcpy(s->boot, "00112233445566778899aabbccddeeff");
	s->total = total;
	s->retained = total < CAPACITY ? total : CAPACITY;
	s->dropped = total - s->retained;
	for (size_t i = 0; i < s->retained; ++i) {
		uint64_t *v = s->records[i].v;
		v[0] = total - s->retained + i + 1;
		v[1] = v[0] * 100;
		v[2] = 3221225534;
		v[3] = 39;
		v[4] = 123456;
		v[5] = v[6] = 42;
		v[7] = v[8] = v[9] = v[10] = 1000;
		v[11] = 0x7ffc0000;
		v[12] = 1;
		v[13] = 42;
	}
}

static size_t occurrences(const char *s, const char *needle)
{
	size_t count = 0;
	while ((s = strstr(s, needle))) { ++count; s += strlen(needle); }
	return count;
}

static int collection_tests(void)
{
	struct collector c = {0};
	strcpy(c.session, "ffeeddccbbaa99887766554433221100");
	struct snapshot s;
	struct output o;
	fixture(&s, 1);
	s.records[0].v[12] = s.records[0].v[13] = 0;
	CHECK(collect(&c, &s, &o) == 0);
	CHECK(occurrences(o.bytes, "decision ") == 1 && strstr(o.bytes, "reason=collector_start"));
	CHECK(c.pending_count == 1);
	CHECK(collect(&c, &s, &o) == 0 && o.used == 0);
	s.records[0].v[12] = 1;
	s.records[0].v[13] = UINT64_MAX;
	s.records[0].v[14] = 1;
	CHECK(collect(&c, &s, &o) == 0 && occurrences(o.bytes, "completion ") == 1);
	CHECK(!strstr(o.bytes, "decision ") && strstr(o.bytes, "result=18446744073709551615 errno=1"));
	CHECK(c.pending_count == 0);
	CHECK(collect(&c, &s, &o) == 0 && o.used == 0);
	struct collector next = c;
	s.records[0].v[12] = s.records[0].v[13] = s.records[0].v[14] = 0;
	CHECK(collect(&next, &s, &o) == -1 && errno == EPROTO);
	CHECK(c.pending_count == 0 && c.last == 1);
	fixture(&s, 120);
	/* Make the previously completed record immutable, including its outcome. */
	s.records[0].v[13] = UINT64_MAX; s.records[0].v[14] = 1;
	s.records[119].v[12] = s.records[119].v[13] = 0;
	CHECK(collect(&c, &s, &o) == 0 && occurrences(o.bytes, "decision ") == 119);
	CHECK(!strstr(o.bytes, "loss ") && c.pending_count == 1);
	fixture(&s, 300);
	CHECK(collect(&c, &s, &o) == 0);
	CHECK(strstr(o.bytes, "first=121 last=172 count=52 reason=not_observed"));
	CHECK(strstr(o.bytes, "sequence=120 reason=ring_eviction"));
	CHECK(occurrences(o.bytes, "decision ") == 128);
	CHECK(strstr(o.bytes, "overwritten=172"));
	CHECK(collect(&c, &s, &o) == 0 && o.used == 0);
	/* Ring overwrites observed in the preceding snapshot are not lost events. */
	fixture(&s, 301);
	CHECK(collect(&c, &s, &o) == 0 && occurrences(o.bytes, "decision ") == 1);
	CHECK(!strstr(o.bytes, "loss "));
	fixture(&s, 1);
	CHECK(collect(&c, &s, &o) == 0 && c.epoch == 2);
	CHECK(strstr(o.bytes, "reason=source_reset") && occurrences(o.bytes, "decision ") == 1);
	strcpy(s.boot, "10112233445566778899aabbccddeeff");
	CHECK(collect(&c, &s, &o) == 0 && c.epoch == 3 && strstr(o.bytes, "reason=source_reset"));
	memset(&c, 0, sizeof(c)); strcpy(c.session, "test");
	fixture(&s, 300);
	CHECK(collect(&c, &s, &o) == 0 && strstr(o.bytes, "first=1 last=172 count=172"));
	fixture(&s, 301);
	s.records[127].v[12] = s.records[127].v[13] = 0;
	CHECK(collect(&c, &s, &o) == 0);
	o.used = 0;
	CHECK(end_pending(&o, &c, "collector_stop") == 0 && strstr(o.bytes, "sequence=301 reason=collector_stop"));
	return 0;
}

static int parsing_tests(void)
{
	const char *header = "version=1 boot=00112233445566778899aabbccddeeff capacity=128 total=1 retained=1 dropped=0\n"
		"# sequence ns arch syscall ip pid tid uid euid gid egid action completed result errno\n";
	char text[2048];
	struct snapshot s;
	const char *valid = "1 99 3221225534 39 123456 42 42 1000 1000 1000 1000 2147221504 1 18446744073709551615 1\n";
	snprintf(text, sizeof(text), "%s%s", header, valid);
	CHECK(parse_snapshot(text, &s) == 0 && s.records[0].v[13] == UINT64_MAX);
	const char *invalid[] = {
		"2 99 3221225534 39 123456 42 42 1000 1000 1000 1000 2147221504 1 42 0\n",
		"1 99 3221225534 39 123456 42 42 1000 1000 1000 1000 2147221504 2 42 0\n",
		"1 99 3221225534 39 123456 42 42 1000 1000 1000 1000 2147221504 0 42 0\n",
		"1 99 3221225534 39 123456 42 42 1000 1000 1000 1000 2147221504 1 18446744073709551616 0\n",
		"1 99 3221225534 39 123456 42 42 1000 1000 1000 1000 2147221504 1 -1 0\n",
		"1 99 3221225534 39 123456 42 42 1000 1000 1000 1000 2147221504 1 42\n",
		"1 99 3221225534 39 123456 42 42 1000 1000 1000 1000 2147221504 1 42 0 extra\n"
	};
	for (size_t i = 0; i < sizeof(invalid) / sizeof(*invalid); ++i) {
		snprintf(text, sizeof(text), "%s%s", header, invalid[i]);
		CHECK(parse_snapshot(text, &s) == -1);
	}
	snprintf(text, sizeof(text), "%s%s%s", header, valid, valid);
	CHECK(parse_snapshot(text, &s) == -1);
	strcpy(text, "version=1 capacity=128 total=0 retained=0 dropped=0\n"
		"# sequence ns arch syscall ip pid tid uid euid gid egid action completed result errno\n");
	CHECK(parse_snapshot(text, &s) == 0 && !strcmp(s.boot, "unknown"));
	strcpy(text, "version=1 capacity=128 total=1 retained=0 dropped=1\n"
		"# sequence ns arch syscall ip pid tid uid euid gid egid action completed result errno\n");
	CHECK(parse_snapshot(text, &s) == -1);
	strcpy(text, "version=1 boot=not-a-boot-id capacity=128 total=0 retained=0 dropped=0\n"
		"# sequence ns arch syscall ip pid tid uid euid gid egid action completed result errno\n");
	CHECK(parse_snapshot(text, &s) == -1);
	uint64_t n;
	CHECK(number("+1", &n) == -1 && number("", &n) == -1 && number("1x", &n) == -1);
	return 0;
}

static int storage_tests(void)
{
	char path[] = "/tmp/vinix-audit-tests.XXXXXX";
	CHECK(mkdtemp(path) != NULL);
	int dir = open(path, O_RDONLY | O_DIRECTORY);
	CHECK(dir >= 0);
	uid_t owner = geteuid();
	int fd = open_log_at(dir, "audit.log", owner, -1);
	CHECK(fd >= 0 && log_stat(fd, owner) == 0);
	CHECK(open_log_at(dir, "audit.log", owner, -1) == -1);
	int again = open_log_at(dir, "audit.log", owner, fd);
	CHECK(again >= 0); close(again);
	struct output o = {0};
	CHECK(add(&o, "first\n") == 0 && append(fd, &o, owner) == 0);
	o.used = 0;
	CHECK(add(&o, "second\n") == 0 && append(fd, &o, owner) == 0);
	int reader = openat(dir, "audit.log", O_RDONLY);
	char buffer[32] = {0};
	CHECK(read(reader, buffer, sizeof(buffer)) == 13 && !strcmp(buffer, "first\nsecond\n"));
	close(reader);
	CHECK(log_stat(fd, owner + 1) == -1);
	CHECK(fchmod(fd, 0644) == 0 && append(fd, &o, owner) == -1);
	CHECK(fchmod(fd, 0600) == 0);
	CHECK(linkat(dir, "audit.log", dir, "hardlink", 0) == 0);
	CHECK(append(fd, &o, owner) == -1);
	CHECK(unlinkat(dir, "hardlink", 0) == 0);
	CHECK(symlinkat("audit.log", dir, "symlink") == 0);
	CHECK(open_log_at(dir, "symlink", owner, -1) == -1);
	CHECK(mkfifoat(dir, "fifo", 0600) == 0 && open_log_at(dir, "fifo", owner, -1) == -1);
	CHECK(open_log_at(dir, "../escape", owner, -1) == -1);
	CHECK(fchmod(dir, 0770) == 0 && open_log_at(dir, "bad.log", owner, -1) == -1);
	CHECK(fchmod(dir, 0700) == 0);
	/* Unsafe ancestors fail even for a root caller, before touching a file. */
	CHECK(open_log("/tmp/should-not-be-created-vinix-audit.log", -1) == -1);
	CHECK(renameat(dir, "audit.log", dir, "rotated.log") == 0);
	int rotated = open_log_at(dir, "audit.log", owner, fd);
	CHECK(rotated >= 0 && append(rotated, &o, owner) == 0);
	close(rotated);
	CHECK(unlinkat(dir, "rotated.log", 0) == 0 && append(fd, &o, owner) == -1);
	close(fd);
	CHECK(unlinkat(dir, "audit.log", 0) == 0 && unlinkat(dir, "symlink", 0) == 0 && unlinkat(dir, "fifo", 0) == 0);
	/* A snapshot must end with a newline, fit the bound and contain no NUL. */
	fd = openat(dir, "snapshot", O_WRONLY | O_CREAT | O_EXCL, 0600);
	CHECK(fd >= 0 && write(fd, "version=1", 9) == 9); close(fd);
	char snapshot_path[PATH_MAX];
	snprintf(snapshot_path, sizeof(snapshot_path), "%s/snapshot", path);
	struct snapshot s;
	CHECK(read_snapshot(snapshot_path, &s) == -1 && errno == EPROTO);
	CHECK(unlinkat(dir, "snapshot", 0) == 0);
	close(dir);
	CHECK(rmdir(path) == 0);
	return 0;
}

int main(void)
{
	if (collection_tests() || parsing_tests() || storage_tests()) return 1;
	puts("SECURITY AUDIT COLLECTOR PASS");
	return 0;
}
