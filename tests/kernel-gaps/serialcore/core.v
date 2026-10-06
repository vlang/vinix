// Route PID 1's native verdicts to QEMU's serial console on x86.
module serialcore

#include <fcntl.h>
#include <unistd.h>
fn C.open(&char, i32, ...) i32
fn C.dup2(i32, i32) i32
fn C.close(i32) i32

fn init() {
	$if amd64 {
		serial := C.open(c'/dev/com1', C.O_WRONLY)
		if serial >= 0 {
			C.dup2(serial, C.STDOUT_FILENO)
			C.dup2(serial, C.STDERR_FILENO)
			if serial > C.STDERR_FILENO { C.close(serial) }
		}
	}
}
