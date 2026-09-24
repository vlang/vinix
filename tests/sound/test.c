// PID 1 for the sound regression. It plays two tones through /dev/dsp the way
// SDL's OSS backend drives it, and reports on the console; the host checks
// what QEMU actually recorded.
#include <errno.h>
#include <fcntl.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/soundcard.h>
#include <signal.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#define FAIL(...)                                                          \
	do {                                                                   \
		printf("SOUND TEST FAIL line %d: ", __LINE__);                     \
		printf(__VA_ARGS__);                                               \
		printf(" (errno %d)\n", errno);                                    \
		return 1;                                                          \
	} while (0)

static volatile int alarms;

static void on_alarm(int signal)
{
	(void)signal;
	alarms++;
}

static void set_alarm_interval(long microseconds)
{
	struct itimerval interval = {
		.it_interval = {0, microseconds},
		.it_value = {0, microseconds},
	};
	setitimer(ITIMER_REAL, &interval, NULL);
}

static double now(void)
{
	struct timespec ts;
	clock_gettime(CLOCK_MONOTONIC, &ts);
	return (double)ts.tv_sec + (double)ts.tv_nsec / 1e9;
}

static int set(int fd, unsigned long request, int value, int expected, const char *what)
{
	int answer = value;
	if (ioctl(fd, request, &answer) != 0)
		FAIL("%s(%d) failed", what, value);
	if (answer != expected)
		FAIL("%s(%d) answered %d, expected %d", what, value, answer, expected);
	return 0;
}

// Writes `seconds` of a sine in 4096-byte pieces, as SDL's audio thread does.
static int play(int fd, int rate, int channels, double hz, double seconds, double *elapsed)
{
	static int16_t chunk[2048];
	const int frames_per_chunk = (int)(sizeof(chunk) / sizeof(chunk[0])) / channels;
	const long total = (long)(rate * seconds);
	long frame = 0;
	double start = now();
	while (frame < total) {
		int frames = frames_per_chunk;
		if (total - frame < frames)
			frames = (int)(total - frame);
		for (int i = 0; i < frames; i++) {
			int16_t sample = (int16_t)(8000.0 * sin(2.0 * M_PI * hz * (double)(frame + i) / rate));
			for (int c = 0; c < channels; c++)
				chunk[i * channels + c] = sample;
		}
		size_t bytes = (size_t)frames * (size_t)channels * sizeof(int16_t);
		ssize_t written = write(fd, chunk, bytes);
		if (written != (ssize_t)bytes)
			FAIL("write returned %zd of %zu", written, bytes);
		frame += frames;
	}
	*elapsed = now() - start;
	return 0;
}

static int run_tests(void)
{
	struct stat st;
	if (stat("/dev/dsp", &st) != 0 || !S_ISCHR(st.st_mode))
		FAIL("/dev/dsp is not a character device");

	// SDL opens non-blocking, then clears the flag before playing.
	int fd = open("/dev/dsp", O_WRONLY | O_NONBLOCK);
	if (fd < 0)
		FAIL("open /dev/dsp");
	if (fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) & ~O_NONBLOCK) != 0)
		FAIL("clear O_NONBLOCK");

	int formats = 0;
	if (ioctl(fd, SNDCTL_DSP_GETFMTS, &formats) != 0 || !(formats & AFMT_S16_LE))
		FAIL("GETFMTS 0x%x has no AFMT_S16_LE", formats);
	if (set(fd, SNDCTL_DSP_SETFMT, AFMT_S16_LE, AFMT_S16_LE, "SETFMT") ||
	    set(fd, SNDCTL_DSP_CHANNELS, 2, 2, "CHANNELS") ||
	    set(fd, SNDCTL_DSP_SPEED, 44000, 44100, "SPEED") ||
	    set(fd, SNDCTL_DSP_SPEED, 44100, 44100, "SPEED"))
		return 1;
	int fragments = 12 | (2 << 16);
	if (ioctl(fd, SNDCTL_DSP_SETFRAGMENT, &fragments) != 0)
		FAIL("SETFRAGMENT");
	puts("SOUND TEST PASS: OSS parameters");

	// A second opener, like SDL probing /dev/dsp0, must not stop playback,
	// and cannot take the device over while its owner has it.
	int probe = open("/dev/dsp0", O_WRONLY | O_NONBLOCK);
	if (probe < 0)
		FAIL("open /dev/dsp0");
	int busy = 22050;
	if (ioctl(probe, SNDCTL_DSP_SPEED, &busy) == 0 || errno != EBUSY)
		FAIL("a second opener reconfigured a device in use");
	int16_t silence[64] = {0};
	if (write(probe, silence, sizeof(silence)) != -1 || errno != EBUSY)
		FAIL("a second opener wrote to a device in use");
	puts("SOUND TEST PASS: the device has one owner at a time");

	// A handled signal must not cut a write short: Linux restarts the write,
	// and SDL treats any failed write as a lost sound card.
	struct sigaction action = {.sa_handler = on_alarm};
	sigaction(SIGALRM, &action, NULL);
	set_alarm_interval(5000);
	double elapsed = 0;
	int played = play(fd, 44100, 2, 440.0, 2.0, &elapsed);
	set_alarm_interval(0);
	if (played)
		return 1;
	printf("SOUND TEST: %d signals handled during playback\n", alarms);
	if (alarms < 50)
		FAIL("only %d timer signals arrived", alarms);
	puts("SOUND TEST PASS: handled signals do not interrupt writes");
	close(probe);
	printf("SOUND TEST: 2.0 s of audio written in %.3f s\n", elapsed);
	// Writes block on the device, so they take about as long as the audio
	// lasts, less what the driver and QEMU hold in flight.
	if (elapsed < 1.5 || elapsed > 3.0)
		FAIL("writes were not paced by playback (%.3f s)", elapsed);
	puts("SOUND TEST PASS: writes are paced by playback");

	double closing = now();
	close(fd);
	closing = now() - closing;
	printf("SOUND TEST: close drained in %.3f s\n", closing);
	if (closing > 1.0)
		FAIL("close took %.3f s", closing);

	// A process blocked in a long write still dies promptly, and its exit
	// frees the device for the next one.
	pid_t child = fork();
	if (child == 0) {
		static int16_t tone[44100 * 2 * 2];
		for (int i = 0; i < 44100 * 2; i++)
			tone[2 * i] = tone[2 * i + 1] =
				(int16_t)(8000.0 * sin(2.0 * M_PI * 660.0 * i / 44100));
		int dsp = open("/dev/dsp", O_WRONLY);
		int value = AFMT_S16_LE;
		ioctl(dsp, SNDCTL_DSP_SETFMT, &value);
		value = 2;
		ioctl(dsp, SNDCTL_DSP_CHANNELS, &value);
		value = 44100;
		ioctl(dsp, SNDCTL_DSP_SPEED, &value);
		write(dsp, tone, sizeof(tone));
		_exit(0);
	}
	usleep(300000);
	double killed = now();
	kill(child, SIGKILL);
	waitpid(child, NULL, 0);
	killed = now() - killed;
	printf("SOUND TEST: a writer died %.3f s after SIGKILL\n", killed);
	if (killed > 0.5)
		FAIL("SIGKILL took %.3f s to end a blocked write", killed);
	puts("SOUND TEST PASS: a blocked writer can be killed");

	// A fresh open starts from the OSS defaults and can be reconfigured.
	fd = open("/dev/dsp", O_WRONLY);
	if (fd < 0)
		FAIL("reopen /dev/dsp");
	if (set(fd, SNDCTL_DSP_SETFMT, AFMT_QUERY, AFMT_U8, "SETFMT query") ||
	    set(fd, SNDCTL_DSP_SETFMT, AFMT_S16_LE, AFMT_S16_LE, "SETFMT") ||
	    set(fd, SNDCTL_DSP_CHANNELS, 1, 1, "CHANNELS") ||
	    set(fd, SNDCTL_DSP_SPEED, 22050, 22050, "SPEED"))
		return 1;
	if (play(fd, 22050, 1, 880.0, 0.5, &elapsed))
		return 1;
	if (ioctl(fd, SNDCTL_DSP_SYNC, 0) != 0)
		FAIL("SYNC");
	close(fd);
	puts("SOUND TEST PASS: reopened at another rate");
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
	puts("VINIX SOUND TEST: START");
	pid_t worker = fork();
	int status = 0;
	if (worker == 0)
		_exit(run_tests());
	if (worker > 0 && waitpid(worker, &status, 0) == worker && WIFEXITED(status) &&
	    WEXITSTATUS(status) == 0)
		puts("VINIX SOUND TEST: GUEST DONE");
	else
		puts("VINIX SOUND TEST: FAIL");
	for (;;)
		sleep(1);
}
