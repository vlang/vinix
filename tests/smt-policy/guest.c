#define _GNU_SOURCE
#include <cpuid.h>
#include <fcntl.h>
#include <sched.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/reboot.h>
#include <unistd.h>

int main(void) {
    int console = open("/dev/com1", O_WRONLY);
    if (console >= 0) { dup2(console, 1); dup2(console, 2); close(console); }
    setvbuf(stdout, NULL, _IONBF, 0);
    FILE *request = fopen("/smt-request", "r");
    int enabled = request ? fgetc(request) == '1' : 1;
    if (request) fclose(request);
    unsigned a, b, c, d, threads = 0;
    const unsigned leaves[] = {0x1f, 0xb};
    for (unsigned leaf = 0; leaf < 2 && !threads; leaf++) {
        for (unsigned level = 0; level < 32; level++) {
            if (!__get_cpuid_count(leaves[leaf], level, &a, &b, &c, &d) || !(b & 65535)) break;
            if (((c >> 8) & 255) == 1 && (b & 65535) <= (1U << (a & 31))) {
                threads = b & 65535;
                break;
            }
        }
    }
    // The runner exposes one socket, two cores and two SMT threads per core.
    int expected = enabled ? 4 : threads ? 4 / (int)threads : 1;
    cpu_set_t mask;
    CPU_ZERO(&mask);
    int result = sched_getaffinity(0, sizeof(mask), &mask);
    int count = result ? -1 : CPU_COUNT(&mask);
    printf("SMT POLICY: enabled=%d topology_threads=%u online=%d expected=%d\n",
           enabled, threads, count, expected);
    puts(count == expected ? "SMT POLICY: PASS" : "SMT POLICY: FAIL");
    reboot(RB_POWER_OFF);
    for (;;) pause();
}
