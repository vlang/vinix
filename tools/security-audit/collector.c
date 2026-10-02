/* SPDX-License-Identifier: GPL-2.0-or-later */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <limits.h>
#include <signal.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

/* The producer never waits for us. Missing sequences and unavailable outcomes
 * must be visible; the kernel's overwritten counter is not collector loss. */
#define CAPACITY 128
#define SNAPSHOT_BYTES 65536
#define OUTPUT_BYTES (CAPACITY * 1024 + 8192)
struct record { uint64_t v[15]; };
struct snapshot {
	uint64_t total, retained, dropped;
	char boot[33];
	struct record records[CAPACITY];
};
struct collector {
	char session[33], boot[33];
	uint64_t epoch, last, total, dropped;
	int started;
	struct record pending[CAPACITY];
	size_t pending_count;
	struct record observed[CAPACITY];
	size_t observed_count;
};
struct output { char bytes[OUTPUT_BYTES]; size_t used; };
static volatile sig_atomic_t stopping, reopening;

static int number(const char *s, uint64_t *out)
{
	if (!*s) return -1;
	uint64_t n = 0;
	for (; *s; ++s) {
		if (*s < '0' || *s > '9' || n > (UINT64_MAX - (unsigned)(*s - '0')) / 10)
			return -1;
		n = n * 10 + (unsigned)(*s - '0');
	}
	*out = n;
	return 0;
}

static int boot_id(const char *s)
{
	if (strlen(s) != 32) return -1;
	for (; *s; ++s) if (!((*s >= '0' && *s <= '9') || (*s >= 'a' && *s <= 'f')))
		return -1;
	return 0;
}

/* Validate the entire bounded snapshot before changing any collector state. */
static int parse_snapshot(char *text, struct snapshot *s)
{
	memset(s, 0, sizeof(*s));
	strcpy(s->boot, "unknown");
	char *line_save, *line = strtok_r(text, "\n", &line_save);
	if (!line) return -1;
	unsigned seen = 0;
	char *token_save;
	for (char *token = strtok_r(line, " ", &token_save); token;
	     token = strtok_r(NULL, " ", &token_save)) {
		char *equals = strchr(token, '=');
		if (!equals) return -1;
		*equals++ = 0;
		unsigned bit;
		uint64_t value;
		if (!strcmp(token, "boot")) {
			bit = 32;
			if (boot_id(equals)) return -1;
			strcpy(s->boot, equals);
		} else {
			if (number(equals, &value)) return -1;
			if (!strcmp(token, "version")) { bit = 1; if (value != 1) return -1; }
			else if (!strcmp(token, "capacity")) { bit = 2; if (value != CAPACITY) return -1; }
			else if (!strcmp(token, "total")) { bit = 4; s->total = value; }
			else if (!strcmp(token, "retained")) { bit = 8; s->retained = value; }
			else if (!strcmp(token, "dropped")) { bit = 16; s->dropped = value; }
			else return -1;
		}
		if (seen & bit) return -1;
		seen |= bit;
	}
	if ((seen & 31) != 31 || s->retained != (s->total < CAPACITY ? s->total : CAPACITY)
	    || s->dropped != s->total - s->retained) return -1;
	line = strtok_r(NULL, "\n", &line_save);
	if (!line || strcmp(line, "# sequence ns arch syscall ip pid tid uid euid gid egid action completed result errno"))
		return -1;
	for (uint64_t i = 0; i < s->retained; ++i) {
		line = strtok_r(NULL, "\n", &line_save);
		if (!line) return -1;
		for (int j = 0; j < 15; ++j) {
			char *token = strtok_r(j ? NULL : line, " ", &token_save);
			if (!token || number(token, &s->records[i].v[j])) return -1;
		}
		if (strtok_r(NULL, " ", &token_save)) return -1;
		uint64_t *v = s->records[i].v;
		if (v[0] != s->total - s->retained + i + 1 || v[12] > 1
		    || v[2] > UINT32_MAX || v[5] > INT_MAX || v[6] > INT_MAX
		    || v[7] > UINT32_MAX || v[8] > UINT32_MAX || v[9] > UINT32_MAX
		    || v[10] > UINT32_MAX || v[11] > UINT32_MAX
		    || (!v[12] && (v[13] || v[14]))) return -1;
	}
	return strtok_r(NULL, "\n", &line_save) ? -1 : 0;
}

static int add(struct output *o, const char *format, ...)
{
	va_list args;
	va_start(args, format);
	int n = vsnprintf(o->bytes + o->used, sizeof(o->bytes) - o->used, format, args);
	va_end(args);
	if (n < 0 || (size_t)n >= sizeof(o->bytes) - o->used) { errno = EOVERFLOW; return -1; }
	o->used += (size_t)n;
	return 0;
}

static int unavailable(struct output *o, const struct collector *c, uint64_t sequence,
	const char *reason)
{
	return add(o, "outcome_unavailable session=%s epoch=%" PRIu64 " sequence=%" PRIu64 " reason=%s\n",
		c->session, c->epoch, sequence, reason);
}

static int end_pending(struct output *o, const struct collector *c, const char *reason)
{
	for (size_t i = 0; i < c->pending_count; ++i)
		if (unavailable(o, c, c->pending[i].v[0], reason)) return -1;
	return 0;
}

static int row(struct output *o, const struct collector *c, const struct record *r,
	const char *kind)
{
	const uint64_t *v = r->v;
	return add(o, "%s session=%s epoch=%" PRIu64 " sequence=%" PRIu64
		" ns=%" PRIu64 " arch=%" PRIu64 " syscall=%" PRIu64 " ip=%" PRIu64
		" pid=%" PRIu64 " tid=%" PRIu64 " uid=%" PRIu64 " euid=%" PRIu64
		" gid=%" PRIu64 " egid=%" PRIu64 " action=%" PRIu64 " completed=%" PRIu64
		" result=%" PRIu64 " errno=%" PRIu64 "\n", kind, c->session, c->epoch,
		v[0], v[1], v[2], v[3], v[4], v[5], v[6], v[7], v[8], v[9], v[10],
		v[11], v[12], v[13], v[14]);
}

/* Work on a copy. Only commit it after the append and fsync both succeeded. */
static int collect(struct collector *c, const struct snapshot *s, struct output *o)
{
	o->used = 0;
	int reset = c->started && (strcmp(c->boot, s->boot) || s->total < c->total);
	if (reset && end_pending(o, c, "source_reset")) return -1;
	if (!c->started || reset) {
		++c->epoch;
		strcpy(c->boot, s->boot);
		c->last = c->total = c->dropped = 0;
		c->pending_count = 0;
		c->observed_count = 0;
		if (add(o, "boundary session=%s epoch=%" PRIu64 " boot=%s reason=%s\n",
		    c->session, c->epoch, c->boot, reset ? "source_reset" : "collector_start")) return -1;
		c->started = 1;
	}
	uint64_t first = s->total - s->retained + 1;
	for (size_t i = 0; i < c->observed_count; ++i) {
		const struct record *old = &c->observed[i];
		uint64_t seq = old->v[0];
		if (seq < first || seq > s->total) continue;
		const struct record *now = &s->records[seq - first];
		if (memcmp(old->v, now->v, 12 * sizeof(uint64_t))
		    || (old->v[12] && memcmp(old->v + 12, now->v + 12, 3 * sizeof(uint64_t)))) {
			errno = EPROTO; return -1;
		}
	}
	if (s->retained && first > c->last && first - c->last > 1) {
		if (add(o, "loss session=%s epoch=%" PRIu64 " first=%" PRIu64
		    " last=%" PRIu64 " count=%" PRIu64 " reason=not_observed\n",
		    c->session, c->epoch, c->last + 1, first - 1, first - c->last - 1)) return -1;
	}
	/* A record already emitted as incomplete can change once at syscall exit. */
	for (size_t i = 0; i < c->pending_count; ++i) {
		const struct record *old = &c->pending[i];
		uint64_t seq = old->v[0];
		if (seq < first || seq > s->total) {
			if (unavailable(o, c, seq, "ring_eviction")) return -1;
			continue;
		}
		const struct record *now = &s->records[seq - first];
		if (memcmp(old->v, now->v, 12 * sizeof(uint64_t))) { errno = EPROTO; return -1; }
		if (now->v[12] && row(o, c, now, "completion")) return -1;
	}
	uint64_t previous = c->last;
	c->pending_count = 0;
	for (size_t i = 0; i < s->retained; ++i) {
		const struct record *r = &s->records[i];
		if (r->v[0] > previous && row(o, c, r, "decision")) return -1;
		if (!r->v[12]) c->pending[c->pending_count++] = *r;
	}
	if (o->used || s->total != c->total || s->dropped != c->dropped)
		if (add(o, "snapshot session=%s epoch=%" PRIu64 " total=%" PRIu64
		    " retained=%" PRIu64 " overwritten=%" PRIu64 "\n", c->session, c->epoch,
		    s->total, s->retained, s->dropped)) return -1;
	c->last = s->total;
	c->total = s->total;
	c->dropped = s->dropped;
	c->observed_count = (size_t)s->retained;
	memcpy(c->observed, s->records, c->observed_count * sizeof(struct record));
	return 0;
}

static int log_stat(int fd, uid_t owner)
{
	struct stat st;
	if (fstat(fd, &st)) return -1;
	if (!S_ISREG(st.st_mode) || st.st_uid != owner || (st.st_mode & 07777) != 0600
	    || st.st_nlink != 1) { errno = EACCES; return -1; }
	return 0;
}

static int directory_stat(int fd, uid_t owner)
{
	struct stat st;
	if (fstat(fd, &st)) return -1;
	if (!S_ISDIR(st.st_mode) || st.st_uid != owner || (st.st_mode & 0022)) {
		errno = EACCES; return -1;
	}
	return 0;
}

static int open_log_at(int parent, const char *name, uid_t owner, int previous)
{
	if (directory_stat(parent, owner)) return -1;
	if (!*name || strchr(name, '/') || !strcmp(name, ".") || !strcmp(name, "..")) {
		errno = EINVAL; return -1;
	}
	int flags = O_WRONLY | O_APPEND | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC;
	int fd = openat(parent, name, flags | O_CREAT | O_EXCL, 0600);
	int created = fd >= 0;
	if (fd < 0 && errno == EEXIST) fd = openat(parent, name, flags);
	if (fd < 0) return -1;
	if (created && fsync(parent)) {
		int error = errno; close(fd); errno = error; return -1;
	}
	if (log_stat(fd, owner)) {
		int error = errno; close(fd); errno = error; return -1;
	}
	/* flock locks open descriptions. Reopening our existing inode needs a
	 * duplicate of the original description rather than a second lock. */
	if (previous >= 0) {
		struct stat old_st, new_st;
		if (fstat(previous, &old_st) || fstat(fd, &new_st)) {
			int error = errno; close(fd); errno = error; return -1;
		}
		if (old_st.st_dev == new_st.st_dev && old_st.st_ino == new_st.st_ino) {
			close(fd);
			return fcntl(previous, F_DUPFD_CLOEXEC, 3);
		}
	}
	if (flock(fd, LOCK_EX | LOCK_NB)) {
		int error = errno; close(fd); errno = error; return -1;
	}
	return fd;
}

/* Walk each component by descriptor. O_NOFOLLOW on the final file alone does
 * not prevent an unprivileged user replacing a writable ancestor directory. */
static int open_log(const char *path, int previous)
{
	if (*path != '/' || strlen(path) >= PATH_MAX) { errno = EINVAL; return -1; }
	char copy[PATH_MAX];
	strcpy(copy, path + 1);
	int dir = open("/", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
	if (dir < 0) return -1;
	char *save, *part = strtok_r(copy, "/", &save);
	if (!part) { close(dir); errno = EINVAL; return -1; }
	for (;;) {
		char *next = strtok_r(NULL, "/", &save);
		if (directory_stat(dir, 0)) break;
		if (!strcmp(part, ".") || !strcmp(part, "..")) { errno = EINVAL; break; }
		if (!next) {
			int fd = open_log_at(dir, part, 0, previous);
			int error = errno; close(dir); errno = error; return fd;
		}
		int child = openat(dir, part, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
		if (child < 0 && errno == ENOENT) {
			if (mkdirat(dir, part, 0700)) break;
			/* Persist the new directory entry before relying on this log. */
			if (fsync(dir)) break;
			child = openat(dir, part, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
		}
		if (child < 0) break;
		close(dir); dir = child; part = next;
	}
	int error = errno ? errno : EINVAL;
	close(dir); errno = error; return -1;
}

static int append(int fd, const struct output *o, uid_t owner)
{
	if (!o->used) return 0;
	if (log_stat(fd, owner)) return -1;
	for (size_t done = 0; done < o->used;) {
		ssize_t n = write(fd, o->bytes + done, o->used - done);
		if (n < 0 && errno == EINTR) continue;
		if (n <= 0) { if (!n) errno = EIO; return -1; }
		done += (size_t)n;
	}
	return fsync(fd);
}

static int read_snapshot(const char *path, struct snapshot *s)
{
	int fd = open(path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC);
	if (fd < 0) return -1;
	char buffer[SNAPSHOT_BYTES];
	size_t used = 0;
	for (;;) {
		ssize_t n = read(fd, buffer + used, sizeof(buffer) - used - 1);
		if (n < 0 && errno == EINTR) continue;
		if (n < 0) { int error = errno; close(fd); errno = error; return -1; }
		if (!n) break;
		used += (size_t)n;
		if (used == sizeof(buffer) - 1) { close(fd); errno = EOVERFLOW; return -1; }
	}
	if (close(fd)) return -1;
	if (!used || buffer[used - 1] != '\n' || memchr(buffer, 0, used)) {
		errno = EPROTO; return -1;
	}
	buffer[used] = 0;
	if (parse_snapshot(buffer, s)) { errno = EPROTO; return -1; }
	return 0;
}

static uint64_t wall_ns(void)
{
	struct timespec now;
	if (clock_gettime(CLOCK_REALTIME, &now)) return 0;
	return (uint64_t)now.tv_sec * 1000000000 + (uint64_t)now.tv_nsec;
}

static int session_id(char out[33])
{
	int fd = open("/dev/urandom", O_RDONLY | O_NOFOLLOW | O_CLOEXEC);
	if (fd < 0) return -1;
	unsigned char bytes[16];
	for (size_t done = 0; done < sizeof(bytes);) {
		ssize_t n = read(fd, bytes + done, sizeof(bytes) - done);
		if (n < 0 && errno == EINTR) continue;
		if (n <= 0) { int error = n ? errno : EIO; close(fd); errno = error; return -1; }
		done += (size_t)n;
	}
	close(fd);
	const char hex[] = "0123456789abcdef";
	for (size_t i = 0; i < sizeof(bytes); ++i) {
		out[i * 2] = hex[bytes[i] >> 4];
		out[i * 2 + 1] = hex[bytes[i] & 15];
	}
	out[32] = 0;
	return 0;
}

static void signal_handler(int signal)
{
	if (signal == SIGHUP) reopening = 1;
	else stopping = 1;
}

static void usage(void)
{
	fputs("usage: vinix-security-audit [--log /var/log/vinix-audit/seccomp.log] "
	      "[--source /proc/security_audit] [--interval-ms 250] [--once]\n", stderr);
}

int main(int argc, char **argv)
{
	const char *path = "/var/log/vinix-audit/seccomp.log", *source = "/proc/security_audit";
	uint64_t interval = 250;
	int once = 0;
	for (int i = 1; i < argc; ++i) {
		if (!strcmp(argv[i], "--once")) once = 1;
		else if (!strcmp(argv[i], "--log") && i + 1 < argc) path = argv[++i];
		else if (!strcmp(argv[i], "--source") && i + 1 < argc) source = argv[++i];
		else if (!strcmp(argv[i], "--interval-ms") && i + 1 < argc) {
			if (number(argv[++i], &interval) || interval < 10 || interval > 60000) { usage(); return 2; }
		} else { usage(); return 2; }
	}
	if (getuid() || geteuid()) { fputs("vinix-security-audit: initial-namespace root required\n", stderr); return 1; }
	umask(077);
	struct sigaction action = {0};
	action.sa_handler = signal_handler;
	sigemptyset(&action.sa_mask);
	if (sigaction(SIGTERM, &action, NULL) || sigaction(SIGINT, &action, NULL)
	    || sigaction(SIGHUP, &action, NULL)) { perror("vinix-security-audit: signals"); return 1; }
	struct collector c = {0};
	if (session_id(c.session)) { perror("vinix-security-audit: session entropy"); return 1; }
	struct snapshot s;
	/* Always ask the canonical kernel endpoint for initial-namespace audit
	 * authority. A diagnostic source override must not bypass that gate. */
	if (read_snapshot("/proc/security_audit", &s)
	    || (strcmp(source, "/proc/security_audit") && read_snapshot(source, &s))) {
		perror("vinix-security-audit: snapshot"); return 1;
	}
	int fd = open_log(path, -1);
	if (fd < 0) { perror("vinix-security-audit: secure log"); return 1; }
	struct output o = {0};
	int failed = 0;
	if (add(&o, "\nsession_start session=%s wall_ns=%" PRIu64 " pid=%ld source=seccomp\n",
	    c.session, wall_ns(), (long)getpid()) || append(fd, &o, 0)) goto error;
	for (;;) {
		struct collector next = c;
		if (collect(&next, &s, &o) || append(fd, &o, 0)) goto error;
		c = next;
		if (once || stopping) break;
		struct timespec delay = { (time_t)(interval / 1000), (long)(interval % 1000) * 1000000 };
		while (nanosleep(&delay, &delay) < 0) {
			if (errno != EINTR) goto error;
			if (stopping || reopening) break;
		}
		if (reopening) {
			reopening = 0;
			int new_fd = open_log(path, fd);
			if (new_fd < 0) goto error;
			close(fd); fd = new_fd;
			o.used = 0;
			if (add(&o, "\nlog_reopen session=%s epoch=%" PRIu64 " boot=%s last=%" PRIu64
			    " wall_ns=%" PRIu64 "\n", c.session, c.epoch, c.boot, c.last,
			    wall_ns()) || append(fd, &o, 0)) goto error;
		}
		if (read_snapshot(source, &s)) goto error;
	}
	o.used = 0;
	if (end_pending(&o, &c, "collector_stop") || add(&o,
	    "session_end session=%s wall_ns=%" PRIu64 " last=%" PRIu64 " reason=%s\n",
	    c.session, wall_ns(), c.last, once ? "one_shot" : "signal") || append(fd, &o, 0)) goto error;
	goto done;
error:
	{
		int error = errno;
		fprintf(stderr, "vinix-security-audit: collection stopped: %s\n", strerror(error));
		o.used = 0;
		/* Best effort only: log errors are always also sent to the supervisor. */
		if (!add(&o, "\ncollector_error session=%s wall_ns=%" PRIu64 " errno=%d\n",
		    c.session, wall_ns(), error)) (void)append(fd, &o, 0);
		failed = 1;
	}
done:
	if (close(fd)) { perror("vinix-security-audit: log close"); failed = 1; }
	return failed;
}
