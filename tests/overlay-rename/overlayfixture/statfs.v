// SPDX-License-Identifier: GPL-2.0-or-later
module overlayfixture

#include <native-abi.h>

fn C.fstatfs(int, &C.statfs) int

// This is also the observer used by the out-of-space rollback assertions.
fn statfs_probe() {
	unsafe {
		fd := C.open(c'/tmp/overlay-volume', C.O_RDONLY | C.O_DIRECTORY)
		mut expected := C.statfs{}
		check(fd >= 0 && C.statfs(c'/tmp/overlay-volume', &expected) == 0
			&& expected.f_type == 0xef53 && expected.f_bsize == 4096
			&& expected.f_bfree == 1 && expected.f_ffree == 1005, 230)
		mut from_fd := C.statfs{}
		check(C.fstatfs(fd, &from_fd) == 0 && C.usleep(6500000) == 0, 231)
		sample(20)
		for _ in 0 .. 1000 {
			mut from_path := C.statfs{}
			check(C.statfs(c'/tmp/overlay-volume', &from_path) == 0
				&& C.fstatfs(fd, &from_fd) == 0
				&& from_path.f_type == expected.f_type && from_fd.f_type == expected.f_type
				&& from_path.f_bsize == expected.f_bsize && from_fd.f_bsize == expected.f_bsize
				&& from_path.f_bfree == expected.f_bfree && from_fd.f_bfree == expected.f_bfree
				&& from_path.f_ffree == expected.f_ffree && from_fd.f_ffree == expected.f_ffree, 232)
		}
		check(C.usleep(6500000) == 0, 233)
		sample(21)
		check(C.close(fd) == 0, 234)
		C.puts(c'OVERLAY STATFS: calls=2000 free_blocks=1 free_inodes=1005')
		C.puts(c'OVERLAY STATFS: PASS')
		C.fflush(nil)
	}
}
