@[has_globals]
module net

import errno
import usercopy

const uts_name_len = 65

__global (
	hostname   [uts_name_len]char
	domainname [uts_name_len]char
)

pub fn syscall_gethostname(_ voidptr, name charptr, len u64) (u64, u64) {
	mut source := charptr(&hostname[0])
	if hostname[0] == 0 {
		source = c'vinix'
	}
	real_len := unsafe { C.strlen(source) }

	if len <= real_len {
		return errno.err, errno.enametoolong
	}

	if !usercopy.copy_to_user(u64(name), voidptr(source), u64(real_len + 1)) {
		return errno.err, errno.efault
	}
	return 0, 0
}

pub fn syscall_sethostname(_ voidptr, name charptr, len u64) (u64, u64) {
	if len > uts_name_len - 1 {
		return errno.err, errno.einval
	}

	mut incoming := [uts_name_len]char{}
	if !usercopy.copy_from_user(voidptr(&incoming[0]), u64(name), len) {
		return errno.err, errno.efault
	}
	incoming[len] = char(`\0`)
	unsafe { C.memcpy(&hostname[0], &incoming[0], uts_name_len) }

	return 0, 0
}

pub fn syscall_setdomainname(_ voidptr, name charptr, len u64) (u64, u64) {
	if len > uts_name_len - 1 {
		return errno.err, errno.einval
	}
	mut incoming := [uts_name_len]char{}
	if !usercopy.copy_from_user(voidptr(&incoming[0]), u64(name), len) {
		return errno.err, errno.efault
	}
	incoming[len] = char(`\0`)
	unsafe { C.memcpy(&domainname[0], &incoming[0], uts_name_len) }
	return 0, 0
}

pub fn copy_hostname(destination u64) {
	if hostname[0] != 0 {
		unsafe { C.memcpy(voidptr(destination), &hostname[0], uts_name_len) }
	}
}

pub fn copy_domainname(destination u64) {
	unsafe { C.memcpy(voidptr(destination), &domainname[0], uts_name_len) }
}
