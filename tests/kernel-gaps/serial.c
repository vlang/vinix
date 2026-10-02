/* Guest PID 1 uses the framebuffer console on x86-64. Send test verdicts to
 * the serial port that QEMU captures, before the test's main function runs. */
#if defined(__x86_64__)
#include <fcntl.h>
#include <unistd.h>
__attribute__((constructor)) static void kernel_gap_serial_output(void)
{
    int serial = open("/dev/com1", O_WRONLY);
    if (serial >= 0) {
        dup2(serial, STDOUT_FILENO);
        dup2(serial, STDERR_FILENO);
        if (serial > STDERR_FILENO) close(serial);
    }
}
#endif
