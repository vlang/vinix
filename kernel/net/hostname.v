@[has_globals]
module net

import errno
import proc
import security
import usercopy

const uts_name_len = 65

// The initial UTS namespace's names. Every other UTS namespace keeps its own
// on its proc.Namespace, starting from its creator's.
__global (
	hostname   [uts_name_len]char
	domainname [uts_name_len]char
)

fn uts_namespace() &proc.Namespace {
	current := proc.current_thread()
	if current == unsafe { nil } || unsafe { current.process == nil } {
		return unsafe { nil }
	}
	ns := current.process.ns.uts
	if proc.is_initial_namespace(ns) {
		return unsafe { nil }
	}
	return ns
}

// The caller's hostname, as uname(2) reports it.
pub fn hostname_text() string {
	ns := uts_namespace()
	if ns != unsafe { nil } {
		return ns.hostname
	}
	if hostname[0] == 0 {
		return 'vinix'
	}
	return unsafe { cstring_to_vstring(charptr(&hostname[0])) }
}

pub fn domainname_text() string {
	ns := uts_namespace()
	if ns != unsafe { nil } {
		return ns.domainname
	}
	return unsafe { cstring_to_vstring(charptr(&domainname[0])) }
}

pub fn syscall_gethostname(_ voidptr, name charptr, len u64) (u64, u64) {
	source := hostname_text()
	if len <= u64(source.len) {
		return errno.err, errno.enametoolong
	}
	if !usercopy.copy_to_user(u64(name), voidptr(source.str), u64(source.len + 1)) {
		return errno.err, errno.efault
	}
	return 0, 0
}

fn copy_name_from_user(name charptr, len u64) ?string {
	if len > uts_name_len - 1 {
		errno.set(errno.einval)
		return none
	}
	mut incoming := [uts_name_len]char{}
	if len > 0 && !usercopy.copy_from_user(unsafe { voidptr(&incoming[0]) }, u64(name), len) {
		errno.set(errno.efault)
		return none
	}
	incoming[len] = char(`\0`)
	return unsafe { cstring_to_vstring(charptr(&incoming[0])) }
}

pub fn syscall_sethostname(_ voidptr, name charptr, len u64) (u64, u64) {
	if !security.permitted(security.system_hostname_set) {
		return errno.err, errno.eperm
	}
	text := copy_name_from_user(name, len) or { return errno.err, errno.get() }
	mut ns := uts_namespace()
	if ns != unsafe { nil } {
		ns.hostname = text
		return 0, 0
	}
	unsafe {
		C.memset(&hostname[0], 0, uts_name_len)
		C.memcpy(&hostname[0], text.str, text.len)
	}
	return 0, 0
}

pub fn syscall_setdomainname(_ voidptr, name charptr, len u64) (u64, u64) {
	if !security.permitted(security.system_domainname_set) {
		return errno.err, errno.eperm
	}
	text := copy_name_from_user(name, len) or { return errno.err, errno.get() }
	mut ns := uts_namespace()
	if ns != unsafe { nil } {
		ns.domainname = text
		return 0, 0
	}
	unsafe {
		C.memset(&domainname[0], 0, uts_name_len)
		C.memcpy(&domainname[0], text.str, text.len)
	}
	return 0, 0
}

pub fn copy_hostname(destination u64) {
	text := hostname_text()
	unsafe {
		C.memset(voidptr(destination), 0, uts_name_len)
		C.memcpy(voidptr(destination), text.str, text.len)
	}
}

pub fn copy_domainname(destination u64) {
	text := domainname_text()
	unsafe {
		C.memset(voidptr(destination), 0, uts_name_len)
		C.memcpy(voidptr(destination), text.str, text.len)
	}
}
