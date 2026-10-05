/* SPDX-License-Identifier: GPL-2.0-only */
#define _GNU_SOURCE
#include "../../base-files/usr/include/vinix/hypervisor.h"
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/ioctl.h>
#include <unistd.h>

#define CHECK(test) do { if (!(test)) { \
    printf("HYPERVISOR FAIL: line %d errno %d\n", __LINE__, errno); \
    fflush(stdout); _exit(1); \
} } while (0)

int main(void)
{
    setvbuf(stdout, NULL, _IONBF, 0);
    int fd = open("/dev/hypervisor", O_RDWR);
    if (fd < 0) {
        CHECK(errno == ENOENT || errno == ENODEV);
        puts("HYPERVISOR UNAVAILABLE: device absent; VM entry was not exercised");
    } else {
        /* A registered device has already passed the kernel's VMX self-test.
         * Exercise the public ABI and guest register preservation repeatedly. */
        for (unsigned iteration = 0; iteration < 5; iteration++) {
            if (iteration) fd = open("/dev/hypervisor", O_RDWR);
            CHECK(fd >= 0 && ioctl(fd, VINIX_HV_GET_API_VERSION, NULL) == VINIX_HV_API_VERSION);
            struct vinix_hv_create create = {0x10000};
            CHECK(ioctl(fd, VINIX_HV_CREATE_VM, &create) == 0);
            /* mov dx,0xe9; mov al,'V'; out dx,al; hlt (16-bit real mode). */
            const unsigned char code[] = {0xba, 0xe9, 0, 0xb0, 0x56, 0xee, 0xf4};
            CHECK(pwrite(fd, code, sizeof(code), 0x1000) == sizeof(code));
            uint64_t seed[15];
            for (unsigned i = 0; i < 15; i++) seed[i] = UINT64_C(0x1234567800000000) | (i + iteration);
            struct vinix_hv_registers expected, actual;
            memcpy(&expected, seed, sizeof(expected));
            CHECK(ioctl(fd, VINIX_HV_SET_REGISTERS, &expected) == 0);
            struct vinix_hv_entry entry = {0x1000, 0x8000, 2};
            CHECK(ioctl(fd, VINIX_HV_SET_ENTRY, &entry) == 0);
            struct vinix_hv_exit exit = {0};
            CHECK(ioctl(fd, VINIX_HV_RUN, &exit) == 0);
            CHECK(exit.reason == VINIX_HV_EXIT_IO && exit.instruction_length == 1);
            CHECK((uint16_t)(exit.qualification >> 16) == 0xe9);
            expected.rax = (expected.rax & ~UINT64_C(0xff)) | 0x56;
            expected.rdx = (expected.rdx & ~UINT64_C(0xffff)) | 0xe9;
            CHECK(ioctl(fd, VINIX_HV_GET_REGISTERS, &actual) == 0);
            CHECK(!memcmp(&actual, &expected, sizeof(actual)));
            CHECK(ioctl(fd, VINIX_HV_ADVANCE_RIP, &exit.instruction_length) == 0);
            CHECK(ioctl(fd, VINIX_HV_RUN, &exit) == 0 && exit.reason == VINIX_HV_EXIT_HLT);
            CHECK(close(fd) == 0);
        }
        puts("HYPERVISOR EXECUTION PASS: five guests, IO/HLT exits and all GPRs");
    }
    /* Also require a working native syscall path after hypervisor setup. */
    fd = open("/proc/meminfo", O_RDONLY);
    char memory[128];
    CHECK(fd >= 0 && read(fd, memory, sizeof(memory)) > 0 && close(fd) == 0);
    puts("HYPERVISOR GUEST PASS");
    for (;;) pause();
}
