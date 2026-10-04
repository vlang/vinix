/* Running out of memory must cost a file write or a process, never the
 * machine. PID 1 of a 1 GiB guest fills the RAM-backed root, then has children
 * take more memory than there is in each way a process can, and checks after
 * each that the system still starts processes and takes writes. */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <sys/statfs.h>
#include <sys/wait.h>
#include <unistd.h>

#define MIB (1024ULL * 1024ULL)
#define GIB (1024ULL * MIB)
/* <linux/kd.h>: take the console's screen for drawing. */
#define VINIX_KDSETMODE 0x4b3a
#define VINIX_KD_GRAPHICS 1
/* Past the size below which arm64 fills an anonymous mapping in at mmap(). */
#define LAZY (128 * MIB)

static void require(int ok, const char *why) {
	if (ok) return;
	printf("OOM FAIL %s errno=%d\n", why, errno);
	fflush(stdout);
	_exit(1);
}

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

/* Write until the filesystem refuses, and return what it took. */
static unsigned long long fill(const char *path) {
	static char block[1 << 20];
	memset(block, 0x5a, sizeof(block));
	int fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0600);
	require(fd >= 0, "create fill file");
	unsigned long long written = 0;
	for (;;) {
		ssize_t count = write(fd, block, sizeof(block));
		if (count < 0) {
			require(errno == ENOSPC, "a full tmpfs reports ENOSPC");
			break;
		}
		require(count > 0, "fill write made progress");
		written += (unsigned long long)count;
		require(written < 8192 * MIB, "tmpfs took more than the guest's memory");
	}
	close(fd);
	return written;
}

/* The same with files of `size` bytes each, as installing a package writes
 * them. Returns how many it made; the last, refused, is removed again. */
static unsigned small_files(const char *directory, size_t size, unsigned limit) {
	static char block[64 * 1024];
	char path[128];
	require(size <= sizeof(block), "small file size");
	memset(block, 0x33, sizeof(block));
	mkdir(directory, 0700);
	unsigned made = 0;
	while (made < limit) {
		snprintf(path, sizeof(path), "%s/%u", directory, made);
		int fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0600);
		require(fd >= 0, "create small file");
		ssize_t count = write(fd, block, size);
		close(fd);
		if (count < 0) {
			require(errno == ENOSPC, "a full tmpfs reports ENOSPC for a small file");
			unlink(path);
			break;
		}
		require((size_t)count == size, "small file written whole");
		made++;
	}
	return made;
}

static void remove_small_files(const char *directory, unsigned made) {
	char path[128];
	for (unsigned i = 0; i < made; i++) {
		snprintf(path, sizeof(path), "%s/%u", directory, i);
		require(unlink(path) == 0, "remove small file");
	}
	require(rmdir(directory) == 0, "remove small file directory");
}

/* A child that starts, runs and is reaped: what launching an application
 * needs of the kernel. It touches `megabytes` of fresh memory on the way. */
static void run_child(unsigned megabytes, const char *why) {
	pid_t pid = fork();
	require(pid >= 0, why);
	if (pid == 0) {
		size_t length = (size_t)megabytes * MIB;
		volatile unsigned char *pages = mmap(NULL, length, PROT_READ | PROT_WRITE,
			MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
		if (pages == MAP_FAILED) _exit(2);
		for (size_t offset = 0; offset < length; offset += 4096) pages[offset] = 1;
		_exit(0);
	}
	int status = 0;
	require(waitpid(pid, &status, 0) == pid, why);
	require(WIFEXITED(status) && WEXITSTATUS(status) == 0, why);
}

enum hog_kind {
	HOG_SMALL_MAPPINGS, /* a megabyte at a time, as malloc() asks for memory */
	HOG_PAGE_FAULTS,    /* one large mapping, touched a page at a time */
	HOG_SYSCALL,        /* one large mapping the kernel fills, in read(2) */
	HOG_THREADS,        /* four threads touching one large mapping each */
};

static int hog_report;

static void hog_mark(void) {
	if (write(hog_report, "m", 1) != 1) _exit(4);
}

static volatile unsigned char *hog_mapping(size_t length) {
	volatile unsigned char *pages = mmap(NULL, length, PROT_READ | PROT_WRITE,
		MAP_PRIVATE | MAP_ANONYMOUS | MAP_NORESERVE, -1, 0);
	if (pages == MAP_FAILED) _exit(3);
	return pages;
}

static void *hog_thread(void *unused) {
	(void)unused;
	for (;;) {
		volatile unsigned char *pages = hog_mapping(LAZY);
		for (size_t offset = 0; offset < LAZY; offset += 4096) {
			pages[offset] = 1;
			if (offset % MIB == 0) hog_mark();
		}
	}
	return NULL;
}

/* Take memory until stopped, a mark through the pipe for each megabyte. */
static void hog_body(enum hog_kind kind) {
	if (kind == HOG_THREADS) {
		pthread_t thread;
		for (int i = 0; i < 3; i++)
			if (pthread_create(&thread, NULL, hog_thread, NULL) != 0) _exit(6);
		hog_thread(NULL);
	}
	int zero = kind == HOG_SYSCALL ? open("/dev/zero", O_RDONLY) : -1;
	if (kind == HOG_SYSCALL && zero < 0) _exit(7);
	for (;;) {
		if (kind == HOG_SMALL_MAPPINGS) {
			volatile unsigned char *pages = hog_mapping(MIB);
			for (size_t offset = 0; offset < MIB; offset += 4096) pages[offset] = 1;
			hog_mark();
			continue;
		}
		volatile unsigned char *pages = hog_mapping(LAZY);
		for (size_t offset = 0; offset < LAZY; offset += MIB) {
			if (kind == HOG_SYSCALL) {
				/* The kernel pages the buffer in to copy into it. With no
				 * memory for that the read fails or comes up short, and the
				 * process is killed before it sees which. */
				ssize_t count = read(zero, (void *)(pages + offset), MIB);
				if (count != (ssize_t)MIB) _exit(5);
			} else {
				for (size_t page = 0; page < MIB; page += 4096) pages[offset + page] = 1;
			}
			hog_mark();
		}
	}
}

static pid_t start_hog(enum hog_kind kind, int *report) {
	int ends[2];
	require(pipe(ends) == 0, "hog pipe");
	pid_t pid = fork();
	require(pid >= 0, "fork hog");
	if (pid == 0) {
		close(ends[0]);
		hog_report = ends[1];
		hog_body(kind);
		_exit(8);
	}
	close(ends[1]);
	*report = ends[0];
	return pid;
}

/* Megabytes a hog reported before its pipe closed: it is dead by then. */
static unsigned long long drain(int report) {
	unsigned long long touched = 0;
	char marks[256];
	for (;;) {
		ssize_t count = read(report, marks, sizeof(marks));
		if (count <= 0) break;
		touched += (unsigned long long)count * MIB;
	}
	close(report);
	return touched;
}

/* A hog, run until it is stopped. Returns how much it had touched. */
static unsigned long long hog(enum hog_kind kind, int *status) {
	int report;
	pid_t pid = start_hog(kind, &report);
	unsigned long long touched = drain(report);
	require(waitpid(pid, status, 0) == pid, "wait for hog");
	return touched;
}

static void require_killed(int status, const char *why) {
	if (!(WIFSIGNALED(status) && WTERMSIG(status) == SIGKILL))
		printf("OOM status=0x%x\n", status);
	require(WIFSIGNALED(status) && WTERMSIG(status) == SIGKILL, why);
}

/* A process that takes `percent` of free memory and then does nothing. */
static pid_t start_sleeper(unsigned long long free_bytes, unsigned percent) {
	int ready[2];
	require(pipe(ready) == 0, "sleeper pipe");
	pid_t sleeper = fork();
	require(sleeper >= 0, "fork sleeper");
	if (sleeper == 0) {
		close(ready[0]);
		size_t length = (size_t)(free_bytes / 100 * percent);
		volatile unsigned char *pages = hog_mapping(length);
		for (size_t offset = 0; offset < length; offset += 4096) pages[offset] = 1;
		if (write(ready[1], "r", 1) != 1) _exit(4);
		for (;;) pause();
	}
	close(ready[1]);
	char mark;
	require(read(ready[0], &mark, 1) == 1, "sleeper holds its memory");
	close(ready[0]);
	return sleeper;
}

/* A process holding most of memory and doing nothing, and a small one that
 * goes on asking for more. The large one is killed for it; the small one,
 * which had to wait for that memory, carries on with it. */
static void bystander(unsigned long long free_bytes) {
	pid_t sleeper = start_sleeper(free_bytes, 80);
	int report;
	pid_t grower = start_hog(HOG_PAGE_FAULTS, &report);
	int status = 0;
	require(waitpid(sleeper, &status, 0) == sleeper, "wait for sleeper");
	require_killed(status, "the process holding the most memory is killed first");
	unsigned long long touched = drain(report);
	require(waitpid(grower, &status, 0) == grower, "wait for grower");
	require_killed(status, "the grower is killed once it holds the most");
	printf("OOM grower touched %lluM past a %lluM sleeper\n", touched / MIB,
		free_bytes / 100 * 80 / MIB);
	require(touched > free_bytes / 2, "the grower went on with the sleeper's memory");
}

/* The same with the two nearer in size: the one asking holds more than half
 * of what the idle one does by the time memory runs out, and is the one
 * killed. The idle one is left alone. */
static void requester_preferred(unsigned long long free_bytes) {
	pid_t sleeper = start_sleeper(free_bytes, 55);
	int status = 0;
	unsigned long long touched = hog(HOG_PAGE_FAULTS, &status);
	require_killed(status, "the process asking is killed");
	printf("OOM grower touched %lluM beside a %lluM sleeper\n", touched / MIB,
		free_bytes / 100 * 55 / MIB);
	require(touched < free_bytes / 2, "the grower never had the sleeper's memory");
	require(waitpid(sleeper, &status, WNOHANG) == 0, "the idle process is still running");
	require(kill(sleeper, SIGKILL) == 0, "stop the sleeper");
	require(waitpid(sleeper, &status, 0) == sleeper, "wait for sleeper");
}

/* A file filled through a shared mapping rather than by write(2), as a linker
 * writes its output: 2 GiB of it, which the guest does not have. One with a
 * name is file data whichever way it is written, and stops where write(2)
 * does, with a fault for the writer in place of ENOSPC and nobody killed. A
 * memfd is its mapper's own memory, and its mapper is killed for it. */
static int mapped_writer(const char *path) {
	pid_t pid = fork();
	require(pid >= 0, "fork mapped writer");
	if (pid == 0) {
		int fd = path ? open(path, O_RDWR | O_CREAT | O_TRUNC, 0600)
			: memfd_create("oom", 0);
		if (fd < 0 || ftruncate(fd, (off_t)(2 * GIB)) != 0) _exit(11);
		volatile unsigned char *pages = mmap(NULL, 2 * GIB, PROT_READ | PROT_WRITE,
			MAP_SHARED, fd, 0);
		if (pages == MAP_FAILED) _exit(12);
		for (size_t offset = 0; offset < 2 * GIB; offset += 4096) pages[offset] = 1;
		_exit(13);
	}
	int status = 0;
	require(waitpid(pid, &status, 0) == pid, "wait for mapped writer");
	return status;
}

/* A process that has taken the screen, as the desktop does, and holds most of
 * memory. It is the last to be chosen: the small process asking for more is
 * killed in its place, though it holds less. */
static void screen_owner_spared(unsigned long long free_bytes) {
	int ready[2];
	require(pipe(ready) == 0, "desktop pipe");
	pid_t desktop = fork();
	require(desktop >= 0, "fork desktop");
	if (desktop == 0) {
		close(ready[0]);
		int console = open("/dev/console", O_RDWR | O_NOCTTY);
		if (console < 0 || ioctl(console, VINIX_KDSETMODE, VINIX_KD_GRAPHICS) != 0) _exit(10);
		size_t length = (size_t)(free_bytes / 100 * 60);
		volatile unsigned char *pages = hog_mapping(length);
		for (size_t offset = 0; offset < length; offset += 4096) pages[offset] = 1;
		if (write(ready[1], "r", 1) != 1) _exit(4);
		for (;;) pause();
	}
	close(ready[1]);
	char mark;
	require(read(ready[0], &mark, 1) == 1, "desktop holds its memory");
	close(ready[0]);

	int status = 0;
	unsigned long long touched = hog(HOG_PAGE_FAULTS, &status);
	require_killed(status, "the process beside the desktop is killed");
	printf("OOM hog beside a %lluM desktop touched %lluM\n", free_bytes / 100 * 60 / MIB,
		touched / MIB);
	require(touched < free_bytes / 2, "the hog never had the desktop's memory");
	require(waitpid(desktop, &status, WNOHANG) == 0, "the desktop is still running");
	require(kill(desktop, SIGKILL) == 0, "stop the desktop");
	require(waitpid(desktop, &status, 0) == desktop, "wait for desktop");
}

int main(void) {
	setvbuf(stdout, NULL, _IONBF, 0);
	if (access("/proc/meminfo", R_OK) < 0)
		require(mount("proc", "/proc", "proc", 0, NULL) == 0, "mount proc");
	mkdir("/tmp", 0777);

	unsigned long long total = meminfo("MemTotal:");
	unsigned long long free_at_start = meminfo("MemFree:");
	printf("OOM total=%lluM free=%lluM\n", total / MIB, free_at_start / MIB);

	/* 1. A file that fills the RAM-backed root. */
	unsigned long long written = fill("/tmp/fill");
	unsigned long long free_when_full = meminfo("MemFree:");
	printf("OOM filled tmpfs with %lluM, %lluM left free\n", written / MIB,
		free_when_full / MIB);
	require(written > free_at_start / 2, "tmpfs holds most of free memory");
	require(free_when_full >= 8 * MIB, "a full tmpfs leaves memory to work in");
	struct statfs space;
	require(statfs("/tmp", &space) == 0, "statfs");
	require((unsigned long long)space.f_bavail * space.f_bsize < 2 * MIB,
		"a full tmpfs reports no space");
	run_child(1, "start a process on a full tmpfs");
	puts("OOM PASS full tmpfs: ENOSPC, and processes still start");

	/* 2. On top of that, a process that takes whatever memory is left. */
	int status = 0;
	unsigned long long touched = hog(HOG_SMALL_MAPPINGS, &status);
	printf("OOM hog on a full tmpfs touched %lluM\n", touched / MIB);
	require_killed(status, "the hog on a full tmpfs is killed");
	run_child(1, "start a process after the hog");
	puts("OOM PASS full tmpfs: the hog is killed, the machine runs on");

	/* 3. Deleting the file gives the memory back. */
	require(unlink("/tmp/fill") == 0, "remove fill file");
	unsigned long long free_after_unlink = meminfo("MemFree:");
	printf("OOM %lluM free after removing the file\n", free_after_unlink / MIB);
	require(free_after_unlink + 64 * MIB > free_at_start, "memory returns with the file");

	/* 4. Small files, as a package's are: first ones of a few hundred bytes,
	 * then ones of tens of kilobytes until there is no room. */
	unsigned tiny = small_files("/tmp/tiny", 600, 20000);
	require(tiny == 20000, "small files fit");
	unsigned medium = small_files("/tmp/medium", 60 * 1024, 1000000);
	unsigned long long free_small = meminfo("MemFree:");
	printf("OOM %u files of 60K and %u of 600 bytes, %lluM left free\n", medium, tiny,
		free_small / MIB);
	require(medium > 1000, "files of 60K fill the tmpfs");
	require(free_small >= 8 * MIB, "small files leave memory to work in");
	run_child(1, "start a process on a tmpfs full of small files");
	remove_small_files("/tmp/medium", medium);
	remove_small_files("/tmp/tiny", tiny);
	unsigned long long free_after_small = meminfo("MemFree:");
	printf("OOM %lluM free after removing them\n", free_after_small / MIB);
	require(free_after_small + 64 * MIB > free_at_start, "memory returns with the small files");
	puts("OOM PASS small files: ENOSPC, and their memory returns");

	/* 5. Anonymous memory alone, each way a process comes by it. What a kill
	 * frees comes back each time. */
	static const struct {
		enum hog_kind kind;
		const char *name;
	} hogs[] = {
		{HOG_SMALL_MAPPINGS, "small mappings"},
		{HOG_PAGE_FAULTS, "page faults"},
		{HOG_SYSCALL, "read(2) into fresh memory"},
		{HOG_THREADS, "four threads"},
	};
	for (unsigned i = 0; i < sizeof(hogs) / sizeof(hogs[0]); i++) {
		touched = hog(hogs[i].kind, &status);
		printf("OOM hog by %s touched %lluM\n", hogs[i].name, touched / MIB);
		require_killed(status, hogs[i].name);
		require(touched > free_at_start / 2, "the hog had most of memory first");
		run_child(16, "start a process after the hog");
	}
	unsigned long long free_after_hogs = meminfo("MemFree:");
	printf("OOM %lluM free after the hogs\n", free_after_hogs / MIB);
	require(free_after_hogs + 64 * MIB > free_at_start, "killed hogs return their memory");
	puts("OOM PASS anonymous memory: hogs are killed and their memory returns");

	/* 6. The process killed is the one holding the memory, not the one that
	 * happened to ask. */
	bystander(free_after_hogs);
	run_child(16, "start a process after the bystander round");
	puts("OOM PASS the largest process is the one killed");
	requester_preferred(meminfo("MemFree:"));
	run_child(16, "start a process after the requester round");
	puts("OOM PASS the process asking is killed when it is near the largest");

	/* 7. Whoever draws the screen is killed last. */
	screen_owner_spared(meminfo("MemFree:"));
	run_child(16, "start a process after the desktop round");
	puts("OOM PASS the process that owns the screen is spared");

	/* 8. A file written through a mapping. */
	status = mapped_writer("/tmp/mapped");
	unsigned long long free_mapped = meminfo("MemFree:");
	printf("OOM named file filled through a mapping: writer status=0x%x, %lluM left free\n",
		status, free_mapped / MIB);
	require(WIFSIGNALED(status) && (WTERMSIG(status) == SIGBUS || WTERMSIG(status) == SIGSEGV),
		"the writer of a full mapped file takes a fault");
	require(free_mapped >= 8 * MIB, "a mapped file leaves memory to work in");
	run_child(1, "start a process beside a full mapped file");
	require(unlink("/tmp/mapped") == 0, "remove mapped file");
	require(meminfo("MemFree:") + 64 * MIB > free_at_start, "memory returns with the mapped file");
	status = mapped_writer(NULL);
	require_killed(status, "the mapper of a memfd is killed for it");
	run_child(16, "start a process after the memfd");
	puts("OOM PASS mapped files: a named one is file data, a memfd is its mapper's");

	/* 9. The filesystem takes writes again, and the memory is all back. */
	written = fill("/tmp/fill");
	require(written > free_at_start / 2, "tmpfs fills again");
	require(unlink("/tmp/fill") == 0, "remove second fill file");
	unsigned long long free_at_end = meminfo("MemFree:");
	printf("OOM %lluM free at the end\n", free_at_end / MIB);
	require(free_at_end + 64 * MIB > free_at_start, "nothing is lost by the end");
	puts("OOM PASS all");
	for (;;) pause();
}
