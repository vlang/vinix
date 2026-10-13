// SPDX-License-Identifier: GPL-2.0-or-later
module overlayfixture

#include <native-abi.h>

struct C.statfs {
	f_type  u64
	f_bsize u64
	f_bfree u64
	f_ffree u64
}

fn C.statfs(&char, &C.statfs) int

fn prepare_opaque_full() {
	owned_directory(c'/tmp/overlay-state/disklower/opaque-blocked', 180)
	owned_directory(c'/tmp/overlay-state/disklower/opaque-rename-blocked', 181)
}

fn opaque_full_prepare_worker() {
	check(C.rmdir(c'/tmp/overlay-state/diskmerged/opaque-blocked') == 0
		&& C.rmdir(c'/tmp/overlay-state/diskmerged/opaque-rename-blocked') == 0
		&& C.mkdir(c'/tmp/overlay-state/diskmerged/full-incoming', 0o700) == 0, 182)
	write_file(c'/tmp/overlay-state/diskmerged/full-incoming/fresh', c'BBBBBBBB', 183)
}

fn full_drop_identity() {
	check(C.setgroups(0, unsafe { nil }) == 0 && C.setgid(1000) == 0 && C.setuid(1000) == 0, 184)
}

fn full_wait(worker int) {
	mut status := 0
	check(worker > 0 && C.waitpid(worker, unsafe { &status }, 0) == worker
		&& C.WIFEXITED(status) != 0 && C.WEXITSTATUS(status) == 0, 185)
}

fn opaque_full() {
	unsafe {
		// Mount-refusal setup retired temporary backing entries. Let those
		// settle before comparing the candidate's block/inode rollback.
		check(C.usleep(6500000) == 0, 179)
		mut space := C.statfs{}
		mut data := [4096]u8{}
		fd := C.open(c'/tmp/overlay-volume/fill-space', C.O_WRONLY | C.O_CREAT | C.O_EXCL, u32(0o600))
		check(fd >= 0, 186)
		mut written := 0
		for {
			check(C.statfs(c'/tmp/overlay-volume', &space) == 0 && space.f_bfree >= 1, 187)
			if space.f_bfree == 1 { break }
			check(written < 2048 && C.write(fd, &data[0], 4096) == 4096, 188)
			written++
		}
		check(C.fsync(fd) == 0 && C.close(fd) == 0, 189)
		worker := C.fork()
		check(worker >= 0, 190)
		if worker == 0 {
			full_drop_identity()
			statfs_probe()
			for iteration in 0 .. 3 {
				mut before := C.statfs{}
				mut after := C.statfs{}
				check(C.statfs(c'/tmp/overlay-volume', &before) == 0 && before.f_bfree == 1, 191)
				check(C.mkdir(c'/tmp/overlay-state/diskmerged/opaque-blocked', 0o700) == -1
					&& *C.__errno_location() == C.ENOSPC, 192)
				check(C.open(c'/tmp/overlay-state/diskmerged/opaque-blocked', C.O_RDONLY) == -1
					&& *C.__errno_location() == C.ENOENT && C.usleep(6500000) == 0, 193)
				check(C.statfs(c'/tmp/overlay-volume', &after) == 0, 194)
				C.printf(c'OVERLAY OPAQUE FULL: iteration=%d free_blocks=%lu->%lu free_inodes=%lu->%lu\n',
					iteration, before.f_bfree, after.f_bfree, before.f_ffree, after.f_ffree)
				C.fflush(nil)
				check(after.f_bfree == before.f_bfree && after.f_ffree == before.f_ffree, 205)
				if iteration == 0 { sample(10) }
				if iteration == 2 { sample(11) }
			}
			C._exit(0)
		}
		full_wait(worker)
		last := C.open(c'/tmp/overlay-volume/fill-space', C.O_WRONLY | C.O_APPEND)
		check(last >= 0 && C.write(last, &data[0], 4096) == 4096
			&& C.fsync(last) == 0 && C.close(last) == 0
			&& C.statfs(c'/tmp/overlay-volume', &space) == 0 && space.f_bfree == 0, 195)
		rename_worker := C.fork()
		check(rename_worker >= 0, 196)
		if rename_worker == 0 {
			full_drop_identity()
			check(C.rename(c'/tmp/overlay-state/diskmerged/full-incoming',
				c'/tmp/overlay-state/diskmerged/opaque-rename-blocked') == -1
				&& *C.__errno_location() == C.ENOSPC
				&& contents(c'/tmp/overlay-state/diskmerged/full-incoming/fresh', c'BBBBBBBB'), 197)
			check(C.open(c'/tmp/overlay-state/diskmerged/opaque-rename-blocked', C.O_RDONLY) == -1
				&& *C.__errno_location() == C.ENOENT, 198)
			C._exit(0)
		}
		full_wait(rename_worker)
		check(C.unlink(c'/tmp/overlay-volume/fill-space') == 0 && C.usleep(6500000) == 0, 199)
		recovery := C.fork()
		check(recovery >= 0, 200)
		if recovery == 0 {
			full_drop_identity()
			check(C.mkdir(c'/tmp/overlay-state/diskmerged/opaque-blocked', 0o700) == 0
				&& C.rename(c'/tmp/overlay-state/diskmerged/full-incoming',
					c'/tmp/overlay-state/diskmerged/opaque-rename-blocked') == 0
				&& contents(c'/tmp/overlay-state/diskmerged/opaque-rename-blocked/fresh', c'BBBBBBBB'), 201)
			C._exit(0)
		}
		full_wait(recovery)
		check(C.usleep(6500000) == 0, 206)
		C.sync()
		check(C.umount(c'/tmp/overlay-state/diskmerged') == 0 && C.umount(c'/tmp/overlay-volume') == 0
			&& C.mount(volume_device(), c'/tmp/overlay-volume', c'ext2', 0, nil) == 0, 202)
		check_upper_links()
		for path in [&char(c'/tmp/overlay-volume/upper/opaque-blocked'),
			&char(c'/tmp/overlay-volume/upper/opaque-rename-blocked')]! {
			mut marker := [64]u8{}
			check(C.getxattr(path, c'trusted.overlay.opaque', &marker[0], 64) == 1
				&& marker[0] == u8(`y`), 203)
		}
		check(C.umount(c'/tmp/overlay-volume') == 0, 204)
		C.puts(c'OVERLAY OPAQUE STORAGE FULL: PASS')
		C.fflush(nil)
	}
}
