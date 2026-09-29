// A short, deliberately quiet playback test for the base M1 Air speakers.
// It runs as PID 1 in the sound diagnostic initramfs and leaves its result on
// the framebuffer console. Hearing the tone is still a physical check.
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/soundcard.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

static long long milliseconds(void)
{
    struct timespec now;
    if (clock_gettime(CLOCK_MONOTONIC, &now) != 0)
        return 0;
    return (long long)now.tv_sec * 1000 + now.tv_nsec / 1000000;
}

static int configure(int fd)
{
    int value = 0;
    if (ioctl(fd, SNDCTL_DSP_GETFMTS, &value) != 0 || !(value & AFMT_S16_LE))
        return -1;
    value = AFMT_S16_LE;
    if (ioctl(fd, SNDCTL_DSP_SETFMT, &value) != 0 || value != AFMT_S16_LE)
        return -1;
    value = 2;
    if (ioctl(fd, SNDCTL_DSP_CHANNELS, &value) != 0 || value != 2)
        return -1;
    value = 48000;
    if (ioctl(fd, SNDCTL_DSP_SPEED, &value) != 0 || value != 48000)
        return -1;
    return 0;
}

static int tone(int fd)
{
    int16_t samples[2048];
    const int frames = 48000 * 2;
    long long start = milliseconds();
    for (int frame = 0; frame < frames;) {
        int count = frames - frame;
        if (count > 1024)
            count = 1024;
        for (int i = 0; i < count; i++) {
            // 800 Hz triangle at roughly 12% full scale. The kernel starts
            // the amplifiers another 20 dB down until sense data is valid.
            int phase = (frame + i) % 60;
            int sample = phase < 30 ? -4000 + phase * 8000 / 30
                                    : 4000 - (phase - 30) * 8000 / 30;
            samples[i * 2] = (int16_t)sample;
            samples[i * 2 + 1] = (int16_t)sample;
        }
        size_t bytes = (size_t)count * 2 * sizeof(samples[0]);
        size_t done = 0;
        while (done < bytes) {
            ssize_t n = write(fd, (char *)samples + done, bytes - done);
            if (n <= 0) {
                printf("VINIX M1 SOUND: write failed (%d)\n", errno);
                return -1;
            }
            done += (size_t)n;
        }
        frame += count;
    }
    if (ioctl(fd, SNDCTL_DSP_SYNC, 0) != 0) {
        printf("VINIX M1 SOUND: drain failed (%d)\n", errno);
        return -1;
    }
    long long elapsed = milliseconds() - start;
    printf("VINIX M1 SOUND: 2 seconds of PCM drained in %lld ms\n", elapsed);
    if (elapsed < 1400 || elapsed > 10000) {
        puts("VINIX M1 SOUND: playback pacing is wrong");
        return -1;
    }
    return 0;
}

int main(void)
{
    setvbuf(stdout, NULL, _IONBF, 0);
    puts("VINIX M1 SOUND: starting speaker test in 3 seconds");
    sleep(3);

    struct stat st;
    if (stat("/dev/dsp", &st) != 0 || !S_ISCHR(st.st_mode)) {
        puts("VINIX M1 SOUND: FAIL - no /dev/dsp; see apple-speakers boot log");
        puts("VINIX M1 SOUND: no apple-speakers line at all = kernel lacks the driver");
        goto hold;
    }
    puts("VINIX M1 SOUND: opening DSP");
    int fd = open("/dev/dsp", O_WRONLY);
    if (fd < 0 || configure(fd) != 0) {
        printf("VINIX M1 SOUND: FAIL - OSS setup (%d)\n", errno);
        if (fd >= 0)
            close(fd);
        goto hold;
    }
    for (int pass = 1; pass <= 3; pass++) {
        printf("VINIX M1 SOUND: tone %d/3 (800 Hz, low level)\n", pass);
        if (tone(fd) != 0) {
            close(fd);
            goto hold;
        }
        if (pass < 3) {
            puts("VINIX M1 SOUND: waiting 2 seconds");
            sleep(2);
            puts("VINIX M1 SOUND: wait finished");
        }
    }
    puts("VINIX M1 SOUND: three streams drained; closing DSP");
    if (close(fd) != 0) {
        printf("VINIX M1 SOUND: FAIL - close (%d)\n", errno);
        goto hold;
    }
    puts("VINIX M1 SOUND: DSP closed; checking reopen");
    fd = open("/dev/dsp", O_WRONLY);
    if (fd < 0 || configure(fd) != 0) {
        printf("VINIX M1 SOUND: FAIL - reopen (%d)\n", errno);
        if (fd >= 0)
            close(fd);
        goto hold;
    }
    if (close(fd) != 0) {
        printf("VINIX M1 SOUND: FAIL - reclose (%d)\n", errno);
        goto hold;
    }
    puts("VINIX M1 SOUND: PCM and reopen passed; confirm the tones were audible");

hold:
    for (;;)
        sleep(60);
}
