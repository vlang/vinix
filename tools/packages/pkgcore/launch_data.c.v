// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

fn C.mkdirat(int, &char, u32) int

// Each name is a fixed parent component or a previously validated package ID.
// Never use mkdir_all or chmod on a path through account-writable entries.
fn personal_data_child(parent int, name string, uid u32, create bool) !int {
	if create && C.mkdirat(parent, name.str, 0o700) != 0 && C.errno != C.EEXIST {
		return error('cannot create personal application data directory: ${name}')
	}
	child := C.openat(parent, name.str, C.O_RDONLY | C.O_DIRECTORY | C.O_NOFOLLOW | C.O_CLOEXEC | C.O_NONBLOCK)
	if child < 0 {
		if !create && C.errno == C.ENOENT { return -1 }
		return error('personal application data must use an ordinary directory: ${name}')
	}
	purge_directory_info(child, uid, true) or { C.close(child); return err }
	return child
}

fn prepare_launch_data(home string, id string, uid u32) ! {
	if !identifier(id) { return error('launch data requires a valid application ID') }
	parent := personal_data_parent_mode(home, uid, true)!
	defer { C.close(parent) }
	data := personal_data_child(parent, id, uid, true)!
	defer { C.close(data) }
	parent_info := purge_directory_info(parent, uid, true)!
	data_info := purge_directory_info(data, uid, true)!
	if data_info.st_dev != parent_info.st_dev { return error('application data directory is on another filesystem') }
	temporary := personal_data_child(data, 'tmp', uid, true)!
	defer { C.close(temporary) }
	temporary_info := purge_directory_info(temporary, uid, true)!
	if temporary_info.st_dev != data_info.st_dev { return error('application temporary directory is on another filesystem') }
	// Validate both existing entries before changing either mode. Captured
	// descriptors ensure chmod cannot follow a concurrently replaced link.
	if C.fchmod(data, 0o700) != 0 || C.fchmod(temporary, 0o700) != 0 {
		return error('cannot make application data and temporary directories private')
	}
}
