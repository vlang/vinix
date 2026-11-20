// SPDX-License-Identifier: GPL-2.0-or-later
/* Repeated syscall paths must not keep kernel memory: procfs and sysfs reads,
 * links, system queries, ioctls, sethostname/uname, and xattrs, locks,
 * inotify and metadata changes on tmpfs and the ext2 /root. Each operation is
 * warmed, then run again between two settled snapshots of every slab class;
 * any class that grows by more than a few one-off objects fails the run. On an ALLOC_TRACK=1 kernel the
 * call sites of what stayed live are printed as PERF-SITE lines. */
#define _GNU_SOURCE
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <sched.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/file.h>
#include <sys/inotify.h>
#include <sys/ioctl.h>
#include <sys/mount.h>
#include <sys/prctl.h>
#include <sys/random.h>
#include <sys/reboot.h>
#include <sys/resource.h>
#include <sys/stat.h>
#include <sys/statfs.h>
#include <sys/sysinfo.h>
#include <sys/utsname.h>
#include <sys/xattr.h>
#include <termios.h>
#include <linux/netlink.h>
#include <linux/rtnetlink.h>
#include <netinet/in.h>
#include <sys/ipc.h>
#include <sys/mman.h>
#include <sys/sem.h>
#include <sys/sendfile.h>
#include <sys/shm.h>
#include <sys/signalfd.h>
#include <sys/socket.h>
#include <sys/uio.h>
#include <sys/wait.h>
#include <signal.h>
#include <time.h>
#include <unistd.h>

#define CHECK(x) do { if (!(x)) { printf("SYSCALL RETENTION FAIL line=%d errno=%d: %s\n", __LINE__, errno, #x); _exit(1); } } while (0)

struct heap { int count; long size[32], objects[32], large; };

static void snapshot(struct heap *h) {
	FILE *file = fopen("/proc/slabinfo", "r");
	CHECK(file != NULL);
	char line[256];
	memset(h, 0, sizeof *h);
	h->large = -1;
	while (fgets(line, sizeof line, file)) {
		long label, size, objects, pages;
		if (sscanf(line, "size-%ld %ld %ld %ld", &label, &size, &objects, &pages) == 4 && label == size) {
			CHECK(h->count < 32);
			h->size[h->count] = size;
			h->objects[h->count++] = objects;
		} else if (sscanf(line, "large - - %ld", &pages) == 1) {
			h->large = pages;
		}
	}
	CHECK(fclose(file) == 0);
	CHECK(h->count > 0 && h->large >= 0);
}

static void track(const char *report) {
	FILE *file = fopen(report ? "/proc/allocsites" : "/proc/allocstart", "r");
	if (!file) return;
	char line[512];
	while (fgets(line, sizeof line, file)) if (report) printf("PERF-SITE %s %s", report, line);
	fclose(file);
}

static void slurp(const char *path) {
	static char buf[65536];
	int fd = open(path, O_RDONLY | O_CLOEXEC);
	if (fd < 0) return;
	while (read(fd, buf, sizeof buf) > 0) {}
	close(fd);
}

static const char *scratch = "/tmp";

static void op_proc_self(int i) {
	(void)i;
	static const char *f[] = {"/proc/self/status", "/proc/self/stat", "/proc/self/statm", "/proc/self/maps",
		"/proc/self/limits", "/proc/self/io", "/proc/self/cgroup", "/proc/self/cmdline", "/proc/self/environ",
		"/proc/self/mountinfo", "/proc/self/mounts", "/proc/self/auxv", "/proc/self/comm"};
	for (unsigned k = 0; k < sizeof f / sizeof f[0]; k++) slurp(f[k]);
}

static void op_proc_system(int i) {
	(void)i;
	static const char *f[] = {"/proc/meminfo", "/proc/stat", "/proc/uptime", "/proc/loadavg", "/proc/version",
		"/proc/filesystems", "/proc/cpuinfo", "/proc/mounts", "/proc/kernel-resources",
		"/proc/sys/kernel/pid_max", "/proc/sys/kernel/hostname", "/proc/sys/kernel/osrelease",
		"/proc/partitions", "/proc/net/dev", "/proc/net/tcp", "/proc/net/udp", "/proc/net/unix"};
	for (unsigned k = 0; k < sizeof f / sizeof f[0]; k++) slurp(f[k]);
}

static void op_proc_links(int i) {
	(void)i;
	static const char *f[] = {"/proc/self/exe", "/proc/self/cwd", "/proc/self/root", "/proc/self/fd/0",
		"/proc/self/ns/mnt", "/proc/self/ns/pid", "/proc/self/ns/net", "/proc/self/ns/uts"};
	char target[512];
	for (unsigned k = 0; k < sizeof f / sizeof f[0]; k++) (void)readlink(f[k], target, sizeof target);
}

static int sysfs_budget;
static void sysfs_walk(const char *dir, int depth) {
	if (depth > 4 || sysfs_budget <= 0) return;
	DIR *d = opendir(dir);
	if (!d) return;
	struct dirent *e;
	char path[1024];
	while ((e = readdir(d)) && sysfs_budget > 0) {
		if (e->d_name[0] == '.') continue;
		snprintf(path, sizeof path, "%s/%s", dir, e->d_name);
		struct stat st;
		if (lstat(path, &st) != 0) continue;
		if (S_ISDIR(st.st_mode)) sysfs_walk(path, depth + 1);
		else if (S_ISREG(st.st_mode) && (st.st_mode & 0444)) { slurp(path); sysfs_budget--; }
	}
	closedir(d);
}
static void op_sysfs(int i) { (void)i; sysfs_budget = 48; sysfs_walk("/sys", 0); }

static void op_queries(int i) {
	(void)i;
	struct statfs s; statfs(scratch, &s);
	struct sysinfo si; sysinfo(&si);
	struct utsname u; uname(&u);
	char r[64]; (void)getrandom(r, sizeof r, 0);
	struct rlimit rl; getrlimit(RLIMIT_NOFILE, &rl); prlimit(0, RLIMIT_NOFILE, NULL, &rl);
	struct rusage ru; getrusage(RUSAGE_SELF, &ru);
	cpu_set_t set; sched_getaffinity(0, sizeof set, &set);
	char name[16]; prctl(PR_SET_NAME, "retention", 0, 0, 0); prctl(PR_GET_NAME, name, 0, 0, 0);
	char cwd[256]; (void)getcwd(cwd, sizeof cwd);
	gethostname(name, sizeof name);
}

static void op_ioctl(int i) {
	(void)i;
	int p[2];
	if (pipe(p) == 0) { int n; ioctl(p[0], FIONREAD, &n); close(p[0]); close(p[1]); }
	int fd = open("/dev/console", O_RDWR | O_NOCTTY);
	if (fd >= 0) { struct termios t; tcgetattr(fd, &t); struct winsize w; ioctl(fd, TIOCGWINSZ, &w); close(fd); }
	slurp("/dev/null");
	int z = open("/dev/urandom", O_RDONLY);
	if (z >= 0) { char b[256]; (void)read(z, b, sizeof b); close(z); }
}

/* sethostname kept its copy, and uname then copied the name anew. */
static void op_hostname(int i) {
	(void)i;
	CHECK(sethostname("retention-host", 14) == 0);
	struct utsname u;
	CHECK(uname(&u) == 0 && strcmp(u.nodename, "retention-host") == 0);
}

static void op_xattr(int i) {
	char path[256]; snprintf(path, sizeof path, "%s/x-%d", scratch, i);
	int fd = open(path, O_CREAT | O_RDWR | O_CLOEXEC, 0600);
	CHECK(fd >= 0);
	char value[64] = "value", list[256];
	fsetxattr(fd, "user.retention", value, 16, 0);
	fgetxattr(fd, "user.retention", value, sizeof value);
	flistxattr(fd, list, sizeof list);
	fsetxattr(fd, "user.retention", value, 32, XATTR_REPLACE);
	fremovexattr(fd, "user.retention");
	CHECK(close(fd) == 0 && unlink(path) == 0);
}

static void op_locks(int i) {
	char path[256]; snprintf(path, sizeof path, "%s/l-%d", scratch, i);
	int fd = open(path, O_CREAT | O_RDWR | O_CLOEXEC, 0600);
	CHECK(fd >= 0);
	flock(fd, LOCK_EX); flock(fd, LOCK_UN);
	struct flock l = {.l_type = F_WRLCK, .l_whence = SEEK_SET, .l_start = 0, .l_len = 10};
	fcntl(fd, F_SETLK, &l); l.l_type = F_UNLCK; fcntl(fd, F_SETLK, &l);
	struct flock o = {.l_type = F_RDLCK, .l_whence = SEEK_SET, .l_start = 0, .l_len = 0};
	fcntl(fd, F_OFD_SETLK, &o); o.l_type = F_UNLCK; fcntl(fd, F_OFD_SETLK, &o);
	CHECK(close(fd) == 0 && unlink(path) == 0);
}

static void op_inotify(int i) {
	int fd = inotify_init1(IN_NONBLOCK | IN_CLOEXEC);
	CHECK(fd >= 0);
	int w = inotify_add_watch(fd, scratch, IN_CREATE | IN_DELETE);
	char path[256]; snprintf(path, sizeof path, "%s/n-%d", scratch, i);
	int f = open(path, O_CREAT | O_RDWR | O_CLOEXEC, 0600);
	if (f >= 0) close(f);
	unlink(path);
	char events[1024]; (void)read(fd, events, sizeof events);
	if (w >= 0) inotify_rm_watch(fd, w);
	CHECK(close(fd) == 0);
}

static void op_metadata(int i) {
	char path[256]; snprintf(path, sizeof path, "%s/m-%d", scratch, i);
	int fd = open(path, O_CREAT | O_RDWR | O_CLOEXEC, 0600);
	CHECK(fd >= 0);
	fchmod(fd, 0640); fchown(fd, 0, 0); chmod(path, 0600);
	struct timespec t[2] = {{1, 0}, {2, 0}};
	futimens(fd, t); utimensat(AT_FDCWD, path, t, 0);
	CHECK(ftruncate(fd, 8192) == 0 && truncate(path, 100) == 0);
	fsync(fd); fdatasync(fd);
	CHECK(close(fd) == 0 && unlink(path) == 0);
}

static void op_sysv_sem(int i) {
	(void)i;
	int id = semget(IPC_PRIVATE, 2, IPC_CREAT | 0600);
	CHECK(id >= 0);
	struct sembuf b = {.sem_num = 0, .sem_op = 1};
	semop(id, &b, 1); semctl(id, 0, GETVAL);
	CHECK(semctl(id, 0, IPC_RMID) == 0);
}

static void op_sysv_shm(int i) {
	(void)i;
	int id = shmget(IPC_PRIVATE, 8192, IPC_CREAT | 0600);
	CHECK(id >= 0);
	void *p = shmat(id, NULL, 0);
	if (p != (void *)-1) { ((char *)p)[0] = 1; shmdt(p); }
	CHECK(shmctl(id, IPC_RMID, NULL) == 0);
}

static void op_pty(int i) {
	(void)i;
	int m = posix_openpt(O_RDWR | O_NOCTTY);
	CHECK(m >= 0);
	grantpt(m); unlockpt(m);
	char *name = ptsname(m);
	int s = name ? open(name, O_RDWR | O_NOCTTY) : -1;
	if (s >= 0) { (void)write(m, "x\n", 2); char c[8]; (void)read(s, c, sizeof c); close(s); }
	close(m);
}

static void op_signalfd(int i) {
	(void)i;
	sigset_t set; sigemptyset(&set); sigaddset(&set, SIGUSR2);
	sigprocmask(SIG_BLOCK, &set, NULL);
	int fd = signalfd(-1, &set, SFD_NONBLOCK | SFD_CLOEXEC);
	CHECK(fd >= 0);
	kill(getpid(), SIGUSR2);
	struct signalfd_siginfo info; (void)read(fd, &info, sizeof info);
	close(fd);
}

static void op_posix_timer(int i) {
	(void)i;
	timer_t t; struct sigevent ev = {.sigev_notify = SIGEV_NONE};
	CHECK(timer_create(CLOCK_MONOTONIC, &ev, &t) == 0);
	struct itimerspec spec = {.it_value = {10, 0}};
	timer_settime(t, 0, &spec, NULL); timer_gettime(t, &spec);
	CHECK(timer_delete(t) == 0);
}

static void op_netlink(int i) {
	(void)i;
	int fd = socket(AF_NETLINK, SOCK_RAW | SOCK_CLOEXEC, NETLINK_ROUTE);
	if (fd < 0) return;
	struct { struct nlmsghdr h; struct ifinfomsg m; } req = {
		.h = {.nlmsg_len = sizeof req, .nlmsg_type = RTM_GETLINK, .nlmsg_flags = NLM_F_REQUEST | NLM_F_DUMP, .nlmsg_seq = 1}};
	send(fd, &req, sizeof req, 0);
	char buf[8192];
	for (int k = 0; k < 8; k++) if (recv(fd, buf, sizeof buf, MSG_DONTWAIT) <= 0) break;
	close(fd);
}

static void op_scm_rights(int i) {
	(void)i;
	int sv[2];
	CHECK(socketpair(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0, sv) == 0);
	int passed = open("/dev/null", O_RDONLY | O_CLOEXEC);
	char byte = 'x'; struct iovec iov = {&byte, 1};
	char control[CMSG_SPACE(sizeof(int))] = {0};
	struct msghdr msg = {.msg_iov = &iov, .msg_iovlen = 1, .msg_control = control, .msg_controllen = sizeof control};
	struct cmsghdr *c = CMSG_FIRSTHDR(&msg);
	c->cmsg_level = SOL_SOCKET; c->cmsg_type = SCM_RIGHTS; c->cmsg_len = CMSG_LEN(sizeof(int));
	memcpy(CMSG_DATA(c), &passed, sizeof(int));
	CHECK(sendmsg(sv[0], &msg, 0) == 1);
	char rcontrol[CMSG_SPACE(sizeof(int))];
	struct msghdr r = {.msg_iov = &iov, .msg_iovlen = 1, .msg_control = rcontrol, .msg_controllen = sizeof rcontrol};
	if (recvmsg(sv[1], &r, MSG_CMSG_CLOEXEC) > 0) {
		struct cmsghdr *rc = CMSG_FIRSTHDR(&r);
		if (rc) { int got; memcpy(&got, CMSG_DATA(rc), sizeof got); close(got); }
	}
	close(passed); close(sv[0]); close(sv[1]);
}

static void op_sockopt(int i) {
	(void)i;
	int fd = socket(AF_INET, SOCK_DGRAM | SOCK_CLOEXEC, 0);
	CHECK(fd >= 0);
	int v = 1; socklen_t l = sizeof v;
	setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &v, sizeof v); getsockopt(fd, SOL_SOCKET, SO_RCVBUF, &v, &l);
	struct timeval tv = {1, 0}; setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof tv);
	struct sockaddr_in a = {.sin_family = AF_INET, .sin_port = 0, .sin_addr = {htonl(0x7f000001)}};
	bind(fd, (struct sockaddr *)&a, sizeof a); l = sizeof a; getsockname(fd, (struct sockaddr *)&a, &l);
	close(fd);
}

/* Anonymous remapping and protection changes, and a sealed, synced memfd. */
static void op_vm(int i) {
	(void)i;
	char *p = mmap(NULL, 65536, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
	CHECK(p != MAP_FAILED);
	p[0] = 1; mprotect(p, 16384, PROT_READ); madvise(p, 65536, MADV_DONTNEED);
	char *q = mremap(p, 65536, 131072, MREMAP_MAYMOVE);
	if (q != MAP_FAILED) p = q;
	munmap(p, 131072);
	int fd = memfd_create("seal", MFD_ALLOW_SEALING | MFD_CLOEXEC);
	CHECK(fd >= 0);
	CHECK(ftruncate(fd, 4096) == 0 && fcntl(fd, F_ADD_SEALS, F_SEAL_SHRINK) == 0 && fcntl(fd, F_GET_SEALS) >= 0);
	char *m = mmap(NULL, 4096, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
	if (m != MAP_FAILED) { m[0] = 1; msync(m, 4096, MS_SYNC); munmap(m, 4096); }
	close(fd);
}

static void op_cgroup(int i) {
	char path[128]; snprintf(path, sizeof path, "/sys/fs/cgroup/retention-%d", i);
	if (mkdir(path, 0755) != 0) return;
	char procs[192]; snprintf(procs, sizeof procs, "%s/cgroup.procs", path); slurp(procs);
	CHECK(rmdir(path) == 0);
}

/* sendfile, copy_file_range and splice between two files. */
static void op_copy(int i) {
	char a[256], b[256];
	snprintf(a, sizeof a, "%s/ca-%d", scratch, i); snprintf(b, sizeof b, "%s/cb-%d", scratch, i);
	int in = open(a, O_CREAT | O_RDWR | O_CLOEXEC, 0600), out = open(b, O_CREAT | O_RDWR | O_CLOEXEC, 0600);
	CHECK(in >= 0 && out >= 0);
	char data[8192]; memset(data, 'y', sizeof data);
	CHECK(write(in, data, sizeof data) == (ssize_t)sizeof data);
	off_t off = 0; sendfile(out, in, &off, sizeof data);
	loff_t o1 = 0, o2 = 0; copy_file_range(in, &o1, out, &o2, 4096, 0);
	int pp[2];
	if (pipe(pp) == 0) { loff_t o3 = 0; splice(in, &o3, pp[1], NULL, 4096, 0); splice(pp[0], NULL, out, NULL, 4096, 0); close(pp[0]); close(pp[1]); }
	close(in); close(out);
	CHECK(unlink(a) == 0 && unlink(b) == 0);
}

struct op { const char *name; void (*run)(int); int count; };

static int failures;

static void measure(const struct op *op) {
	for (int i = 0; i < op->count; i++) op->run(i);
	/* Removal and namespace releases finish after up to two grace periods. */
	sleep(13);
	struct heap before, after;
	snapshot(&before);
	track(NULL);
	for (int i = 0; i < op->count; i++) op->run(i);
	sleep(13);
	snapshot(&after);
	CHECK(after.count == before.count);
	long bytes = (after.large - before.large) * sysconf(_SC_PAGESIZE);
	/* A leak repeats with the operation: one object per call is +count. Allow
	 * a few one-off objects, such as state built on first use in the window. */
	int grew = after.large > before.large + 1;
	char classes[512] = "";
	for (int c = 0; c < after.count; c++) {
		long delta = after.objects[c] - before.objects[c];
		if (delta == 0) continue;
		bytes += delta * after.size[c];
		if (delta > 8) grew = 1;
		char part[48];
		snprintf(part, sizeof part, " size-%ld:%+ld", after.size[c], delta);
		strncat(classes, part, sizeof classes - strlen(classes) - 1);
	}
	printf("SYSCALL-RETENTION op=%s dir=%s count=%d bytes_per_op=%ld%s\n", op->name, scratch, op->count,
		bytes / op->count, classes);
	if (grew) {
		char label[128];
		snprintf(label, sizeof label, "op=%s dir=%s", op->name, scratch);
		track(label);
		failures++;
	}
}

int main(void) {
	setvbuf(stdout, NULL, _IONBF, 0);
	puts("SYSCALL RETENTION: START");
	/* With x86 booting its root from the ext2 volume, /tmp is a directory on
	 * it; make it the tmpfs this half of the test means. */
	struct statfs tmp;
	if (statfs("/tmp", &tmp) != 0 || tmp.f_type != 0x01021994) CHECK(mount("tmpfs", "/tmp", "tmpfs", 0, NULL) == 0);
	static const struct op system[] = {
		{"proc_self", op_proc_self, 200}, {"proc_system", op_proc_system, 200},
		{"proc_links", op_proc_links, 200}, {"sysfs", op_sysfs, 100}, {"queries", op_queries, 200},
		{"ioctl", op_ioctl, 200}, {"hostname", op_hostname, 200},
		{"sysv_sem", op_sysv_sem, 200}, {"sysv_shm", op_sysv_shm, 200}, {"pty", op_pty, 200},
		{"signalfd", op_signalfd, 200}, {"posix_timer", op_posix_timer, 200}, {"netlink", op_netlink, 200},
		{"scm_rights", op_scm_rights, 200}, {"sockopt", op_sockopt, 200}, {"vm", op_vm, 200},
		{"cgroup", op_cgroup, 200},
	};
	static const struct op files[] = {
		{"xattr", op_xattr, 200}, {"locks", op_locks, 200}, {"inotify", op_inotify, 200},
		{"metadata", op_metadata, 200}, {"copy", op_copy, 200},
	};
	for (unsigned t = 0; t < sizeof system / sizeof system[0]; t++) measure(&system[t]);
	static const char *dirs[] = {"/tmp", "/root"};
	for (unsigned d = 0; d < sizeof dirs / sizeof dirs[0]; d++) {
		scratch = dirs[d];
		struct statfs fs;
		if (d == 1 && (statfs(scratch, &fs) != 0 || fs.f_type != 0xEF53)) {
			puts("SYSCALL-RETENTION NOTE /root is not the ext2 volume; its file operations were skipped");
			continue;
		}
		for (unsigned t = 0; t < sizeof files / sizeof files[0]; t++) measure(&files[t]);
	}
	if (failures) printf("SYSCALL RETENTION FAIL: %d operations kept kernel memory\n", failures);
	else puts("SYSCALL RETENTION: PASS");
	sync();
	reboot(RB_POWER_OFF);
	return 0;
}
