/* SPDX-License-Identifier: BSD-2-Clause
 * In-guest regression coverage for the VM, VFS, and Linux ABI fundamentals.
 * The binary is linked statically and installed as PID 1 by run-aarch64.sh's
 * --guest-init hook. */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <sched.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/file.h>
#include <sys/inotify.h>
#include <sys/mman.h>
#include <sys/random.h>
#include <sys/resource.h>
#include <sys/stat.h>
#include <sys/eventfd.h>
#include <sys/socket.h>
#include <sys/statfs.h>
#include <sys/sysinfo.h>
#include <sys/uio.h>
#include <sys/un.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

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

static void posix_timer_callback(union sigval value)
{
	if (value.sival_int == 0x5649)
		posix_timer_callbacks++;
}

static int reap_ok(pid_t child)
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

static int test_locks(void)
{
	int fd = open(file_c, O_RDWR);
	CHECK(fd >= 0);
	struct flock lock = {
		.l_type = F_WRLCK, .l_whence = SEEK_SET, .l_start = 0, .l_len = 0
	};
	CHECK(fcntl(fd, F_SETLK, &lock) == 0);
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

static int run_tests(void)
{
	int persistence_boot = verify_persistence_boot();
	CHECK(persistence_boot >= 0);
	if (persistence_boot == 1)
		return 0;
	CHECK(test_random() == 0);
	CHECK(test_cow() == 0);
	CHECK(prepare_directory() == 0);
	CHECK(test_ext2_mapping_and_namespace() == 0);
	CHECK(test_shared_mapping_visible_to_readers() == 0);
	CHECK(test_locks() == 0);
	CHECK(test_permissions_and_limits() == 0);
	CHECK(test_inotify() == 0);
	CHECK(test_scheduler_and_accounting() == 0);
	CHECK(test_posix_timer_thread_notification() == 0);
	CHECK(test_anonymous_descriptor_access() == 0);
	CHECK(test_abstract_socket_reuse() == 0);
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

int main(void)
{
	setbuf(stdout, NULL);
	setbuf(stderr, NULL);
	if (getpid() != 1)
		return run_tests();
	int console = open("/dev/console", O_WRONLY);
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
