# Intel VT-x hypervisor

Vinix enables Intel VT-x on every x86_64 CPU during SMP bring-up. If the CPU,
firmware, or outer hypervisor does not provide VMX, Vinix logs the reason and
continues booting normally. On supported systems an EPT-backed real-mode guest
is run as a boot-time self-test before `/dev/hypervisor` is registered.

The initial interface intentionally targets small firmware, boot-loader, and
device-model experiments. Each VM has one vCPU and up to 2 MiB of contiguous,
identity-mapped guest-physical memory. Guest execution stops for `HLT`, I/O,
CPUID, external interrupts, EPT faults, and the other architectural VM exits;
userspace decides how to emulate each exit.

## Userspace API

Include `<vinix/hypervisor.h>`, open `/dev/hypervisor` once per VM, then:

1. Check `VINIX_HV_GET_API_VERSION`.
2. Pass `struct vinix_hv_create` to `VINIX_HV_CREATE_VM`.
3. Load guest bytes with `write(2)` or a shared `mmap(2)` of the descriptor.
4. Set the initial RIP, RSP, and RFLAGS with `VINIX_HV_SET_ENTRY`.
5. Set general registers if needed with `VINIX_HV_SET_REGISTERS`.
6. Call `VINIX_HV_RUN` and emulate the returned `struct vinix_hv_exit`.
7. For an emulated instruction, pass its reported length to
   `VINIX_HV_ADVANCE_RIP` before running again.

The VM and all pinned pages are released after the final descriptor or mapping
is closed. VMCS ownership is cleared after every exit, so a vCPU may resume on
a different Vinix scheduler CPU.

This example executes an `OUT 0xe9, AL` followed by `HLT`:

```c
#include <fcntl.h>
#include <stdint.h>
#include <sys/ioctl.h>
#include <unistd.h>
#include <vinix/hypervisor.h>

int main(void) {
    static const uint8_t guest[] = {
        0xba, 0xe9, 0x00,       /* mov dx, 0xe9 */
        0xb0, 0x56,             /* mov al, 'V' */
        0xee,                   /* out dx, al */
        0xf4                    /* hlt */
    };
    int fd = open("/dev/hypervisor", O_RDWR);
    struct vinix_hv_create create = { .memory_size = 64 * 1024 };
    struct vinix_hv_entry entry = { .rip = 0x1000, .rsp = 0x8000, .rflags = 2 };
    struct vinix_hv_exit exit;

    if (fd < 0 || ioctl(fd, VINIX_HV_GET_API_VERSION) != VINIX_HV_API_VERSION)
        return 1;
    if (ioctl(fd, VINIX_HV_CREATE_VM, &create) ||
        lseek(fd, 0x1000, SEEK_SET) < 0 ||
        write(fd, guest, sizeof(guest)) != sizeof(guest) ||
        ioctl(fd, VINIX_HV_SET_ENTRY, &entry))
        return 1;

    for (;;) {
        if (ioctl(fd, VINIX_HV_RUN, &exit))
            return 1;
        if (exit.reason == VINIX_HV_EXIT_HLT)
            break;
        if (exit.reason != VINIX_HV_EXIT_IO)
            return 1;
        if (ioctl(fd, VINIX_HV_ADVANCE_RIP, &exit.instruction_length))
            return 1;
    }
    close(fd);
    return 0;
}
```

AMD SVM, multi-vCPU guests, interrupt injection, and a complete device model
are outside this first backend and can be added without changing the VMX
entry/exit ABI.
