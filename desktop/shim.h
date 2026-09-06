/* Thin wrappers over the handful of system calls the desktop makes.
 *
 * They exist for two reasons. The names are prefixed so nothing here can
 * collide with the C declarations vlib's own modules make for the same
 * functions, which V rejects when the signatures differ. And the flag
 * constants stay in C, where the target's headers define them, instead of
 * being copied into V as numbers that would silently rot. */
#ifndef VINIX_DESKTOP_SHIM_H
#define VINIX_DESKTOP_SHIM_H

#include <fcntl.h>
#include <stdint.h>
#include <stddef.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <termios.h>
#include <time.h>
#include <unistd.h>

static inline int vd_open_rw(const char *path) {
	return open(path, O_RDWR);
}

static inline int vd_open_ro_nonblock(const char *path) {
	return open(path, O_RDONLY | O_NONBLOCK);
}

static inline int vd_close(int fd) {
	return close(fd);
}

static inline int64_t vd_read(int fd, void *buf, uint64_t count) {
	return (int64_t)read(fd, buf, (size_t)count);
}

static inline int vd_ioctl(int fd, uint64_t request, void *argp) {
	return ioctl(fd, request, argp);
}

/* Returns NULL rather than MAP_FAILED so the caller has one failure value. */
static inline void *vd_mmap_shared(int fd, uint64_t length) {
	void *mapping = mmap(NULL, (size_t)length, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
	return mapping == MAP_FAILED ? NULL : mapping;
}

static inline int vd_munmap(void *addr, uint64_t length) {
	return munmap(addr, (size_t)length);
}

static inline int vd_set_nonblocking(int fd) {
	return fcntl(fd, F_SETFL, O_NONBLOCK);
}

/* The terminal state is handled entirely here so V never has to model
 * struct termios, whose layout is the target libc's business. */
static inline uint64_t vd_termios_size(void) {
	return (uint64_t)sizeof(struct termios);
}

static inline int vd_term_save(int fd, void *saved) {
	return tcgetattr(fd, (struct termios *)saved);
}

/* Raw enough for a compositor: no echo (the console would otherwise draw
 * keystrokes into the framebuffer being composed), no line buffering, no
 * signal generation, and a read that returns whatever is already there. */
static inline int vd_term_raw(int fd, const void *saved) {
	struct termios raw = *(const struct termios *)saved;
	raw.c_lflag &= ~(tcflag_t)(ICANON | ECHO | ISIG);
	raw.c_cc[VMIN] = 0;
	raw.c_cc[VTIME] = 0;
	return tcsetattr(fd, TCSANOW, &raw);
}

static inline int vd_term_restore(int fd, const void *saved) {
	return tcsetattr(fd, TCSANOW, (const struct termios *)saved);
}

/* int64_t, not long long: it is what V's i64 maps to, and the pointer has to
 * match exactly or the compiler rejects the call. */
static inline int64_t vd_realtime_seconds(int64_t *nanoseconds) {
	struct timespec ts;
	if (clock_gettime(CLOCK_REALTIME, &ts) != 0) {
		*nanoseconds = 0;
		return -1;
	}
	*nanoseconds = (int64_t)ts.tv_nsec;
	return (int64_t)ts.tv_sec;
}

static inline void vd_sleep_ms(int64_t milliseconds) {
	struct timespec request;
	request.tv_sec = (time_t)(milliseconds / 1000);
	request.tv_nsec = (long)((milliseconds % 1000) * 1000000);
	nanosleep(&request, NULL);
}

#endif /* VINIX_DESKTOP_SHIM_H */
