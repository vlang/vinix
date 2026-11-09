// SPDX-License-Identifier: GPL-2.0-or-later
module main

fn C.syscall(i32, ...voidptr) i32

fn check_archive_directory(path &char, name &char, kind u8) {
	unsafe {
		dir := C.opendir(path)
		if dir == nil { fail(c'archive opendir') }
		mut found := false
		error_number := C.__errno_location()
		*error_number = 0
		for {
			e := C.readdir(dir)
			if e == nil { break }
			if C.strcmp(&e.d_name[0], name) == 0 {
				if e.d_ino == 0 || e.d_off == 0 || e.d_reclen < 24 || e.d_reclen % 8 != 0 || e.d_type != kind { fail(c'archive dirent64 layout') }
				found = true
			}
		}
		if !found || *C.__errno_location() != 0 || C.readdir(dir) != nil || C.closedir(dir) != 0 { fail(c'archive readdir EOF') }
	}
}

fn check_archive_directories() {
	unsafe {
		check_archive_directory(c'/bin', c'init', 8)
		check_archive_directory(c'/etc', c'motd', 8)
		fd := C.open(c'/bin', C.O_RDONLY | C.O_DIRECTORY)
		if fd < 0 { fail(c'archive raw open') }
		mut data := [64]u8{}
		if C.syscall(202, fd, &data[0], 1) != -1 || *C.__errno_location() != 22 { fail(c'archive small getdents64') }
		if C.syscall(202, fd, voidptr(1), 32) != -1 || *C.__errno_location() != 14 { fail(c'archive bad getdents64') }
		// One record per read checks that failures do not consume the first entry,
		// and that repeated reads resume and finally return a stable EOF.
		if C.syscall(202, fd, &data[0], 24) != 24 || data[18] != 8 || C.strcmp(&char(&data[19]), c'init') != 0 { fail(c'archive getdents64 resume') }
		if C.syscall(202, fd, &data[0], 24) != 0 || C.syscall(202, fd, &data[0], 24) != 0 { fail(c'archive getdents64 raw EOF') }
		if C.close(fd) != 0 { fail(c'archive raw close') }
		file := C.open(c'/etc/motd', C.O_RDONLY)
		if file < 0 || C.syscall(202, file, &data[0], 64) != -1 || *C.__errno_location() != 20
			|| C.close(file) != 0 { fail(c'archive file getdents64') }
		C.printf(c'VINIX-PPC: PASS archive libc readdir and getdents64 boundaries\n')
	}
}
