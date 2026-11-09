// SPDX-License-Identifier: GPL-2.0-or-later
module main

fn check_path_mutations() {
	unsafe {
		if C.mkdir(c'/root/paths/', 0o700) != 0 { fail(c'mkdir trailing slash') }
		source := C.open(c'/root/paths/source', C.O_WRONLY | C.O_CREAT | C.O_EXCL, 0o600)
		target := C.open(c'/root/paths/target', C.O_WRONLY | C.O_CREAT | C.O_EXCL, 0o600)
		if source < 0 || target < 0 || C.write(source, c's', 1) != 1 || C.write(target, c't', 1) != 1
			|| C.close(source) != 0 || C.close(target) != 0 { fail(c'path fixtures') }
		if C.unlink(c'/root/paths/source///') != -1 || *C.__errno_location() != 20 { fail(c'unlink trailing file') }
		if C.rmdir(c'/root/paths/source/') != -1 || *C.__errno_location() != 20 { fail(c'rmdir trailing file') }
		if C.rename(c'/root/paths/source/', c'/root/paths/target') != -1 || *C.__errno_location() != 20 { fail(c'rename trailing source') }
		if C.rename(c'/root/paths/source', c'/root/paths/target/') != -1 || *C.__errno_location() != 20 { fail(c'rename trailing target') }
		if C.rename(c'/root/paths/source', c'/root/paths/missing/') != -1 || *C.__errno_location() != 20 { fail(c'rename trailing missing target') }
		if C.open(c'/root/paths/source/', C.O_WRONLY | C.O_CREAT, 0o600) != -1 || *C.__errno_location() != 20 { fail(c'create trailing existing file') }
		if C.open(c'/root/paths/missing/', C.O_WRONLY | C.O_CREAT, 0o600) != -1 || *C.__errno_location() != 21 { fail(c'create trailing missing file') }
		mut st := C.stat{}
		if C.lstat(c'/root/paths/missing', &st) != -1 || *C.__errno_location() != 2 { fail(c'trailing path created file') }
		// Rejected mutations must preserve both names and their original contents.
		mut byte := u8(0)
		for i, path in [c'/root/paths/source', c'/root/paths/target']! {
			fd := C.open(path, C.O_RDONLY)
			if fd < 0 || C.read(fd, &byte, 1) != 1 || byte != (if i == 0 { u8(`s`) } else { u8(`t`) })
				|| C.close(fd) != 0 { fail(c'rejected mutation changed data') }
		}
		if C.mkdir(c'/root/paths/child///', 0o700) != 0 { fail(c'mkdir repeated slash') }
		dir := C.open(c'/root/paths/child/', C.O_RDONLY | C.O_DIRECTORY)
		if dir < 0 || C.close(dir) != 0 { fail(c'open trailing directory') }
		if C.unlink(c'/root/paths/child/') != -1 || *C.__errno_location() != 21 { fail(c'unlink trailing directory') }
		if C.rmdir(c'/root/paths/child///') != 0 { fail(c'rmdir trailing directory') }
		if C.rename(c'/root/paths/source', c'/root/paths/renamed') != 0
			|| C.unlink(c'/root/paths/renamed') != 0 || C.unlink(c'/root/paths/target') != 0
			|| C.rmdir(c'/root/paths/') != 0 { fail(c'path cleanup') }
		C.printf(c'VINIX-PPC: PASS trailing-slash mutations preserve files\n')
	}
}

fn check_dangling_creation() {
	unsafe {
		if C.mkdir(c'/root/links', 0o700) != 0 { fail(c'links mkdir') }
		if C.symlink(c'target', c'/root/links/relative') != 0 { fail(c'dangling relative link') }
		if C.open(c'/root/links/relative', C.O_CREAT | C.O_EXCL | C.O_WRONLY, 0o600) != -1
			|| *C.__errno_location() != 17 { fail(c'dangling exclusive') }
		if C.open(c'/root/links/relative', C.O_CREAT | C.O_NOFOLLOW | C.O_WRONLY, 0o600) != -1
			|| *C.__errno_location() != 40 { fail(c'dangling nofollow') }
		mut st := C.stat{}
		if C.lstat(c'/root/links/target', &st) != -1 || *C.__errno_location() != 2 { fail(c'denied open created target') }
		if C.symlink(c'/root/links/relative', c'/root/links/absolute') != 0 { fail(c'dangling absolute link') }
		fd := C.open(c'/root/links/absolute', C.O_CREAT | C.O_RDWR, 0o600)
		if fd < 0 || C.write(fd, c'link', 4) != 4 || C.close(fd) != 0 { fail(c'create resolved target') }
		if C.lstat(c'/root/links/relative', &st) != 0 || st.st_mode & 0xf000 != 0xa000
			|| C.lstat(c'/root/links/absolute', &st) != 0 || st.st_mode & 0xf000 != 0xa000
			|| C.lstat(c'/root/links/target', &st) != 0 || st.st_mode != 0x8180 || st.st_size != 4 { fail(c'resolved creation metadata') }
		mut bytes := [4]u8{}
		readback := C.open(c'/root/links/target', C.O_RDONLY)
		if readback < 0 || C.read(readback, &bytes[0], 4) != 4 || bytes != [u8(`l`), `i`, `n`, `k`]!
			|| C.close(readback) != 0 { fail(c'resolved target contents') }
		if C.symlink(c'absent/child', c'/root/links/intermediate') != 0
			|| C.open(c'/root/links/intermediate', C.O_CREAT | C.O_WRONLY, 0o600) != -1
			|| *C.__errno_location() != 2 { fail(c'create missing intermediate') }
		if C.symlink(c'absent/', c'/root/links/slash') != 0
			|| C.open(c'/root/links/slash', C.O_CREAT | C.O_WRONLY, 0o600) != -1
			|| *C.__errno_location() != 21 { fail(c'create slash link target') }
		if C.lstat(c'/root/links/absent', &st) != -1 || *C.__errno_location() != 2 { fail(c'created absent directory') }
		for path in [c'/root/links/relative', c'/root/links/absolute', c'/root/links/target', c'/root/links/intermediate', c'/root/links/slash']! {
			if C.unlink(path) != 0 { fail(c'link cleanup') }
		}
		if C.rmdir(c'/root/links') != 0 { fail(c'links rmdir') }
		C.printf(c'VINIX-PPC: PASS dangling symlink creation and open flags\n')
	}
}
