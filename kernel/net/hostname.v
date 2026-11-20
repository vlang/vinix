@[has_globals]
module net

import errno
import klock
import proc
import security
import usercopy

const uts_name_len = 65

// The initial UTS namespace's names. Every other UTS namespace keeps its own
// on its proc.Namespace, starting from its creator's.
__global (
	hostname   [uts_name_len]char
	domainname [uts_name_len]char
	domainname_lock klock.Lock
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

// Whether the caller has a UTS namespace of its own, as every container a
// runtime starts does.
pub fn in_own_uts_namespace() bool {
	return uts_namespace() != unsafe { nil }
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

fn copy_name_from_user(name charptr, len u64) ?string {
	if len > uts_name_len - 1 {
		errno.set(errno.einval)
		return none
	}
	// A stack slot: the address of a fixed-array local moved it to the heap.
	incoming := unsafe { &char(C.vinix_stack_alloc(u64(uts_name_len))) }
	if len > 0 && !usercopy.copy_from_user(voidptr(incoming), u64(name), len) {
		errno.set(errno.efault)
		return none
	}
	unsafe { incoming[len] = char(`\0`) }
	return unsafe { cstring_to_vstring(charptr(incoming)) }
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
	// The initial namespace keeps the bytes, not the string: free the copy,
	// as setdomainname does. (A namespace's replaced name is still kept:
	// lockless readers may be copying it, and it changes rarely.)
	unsafe {
		C.memset(&hostname[0], 0, uts_name_len)
		C.memcpy(&hostname[0], text.str, text.len)
		text.free()
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
	defer { unsafe { text.free() } }
	domainname_lock.acquire()
	defer { domainname_lock.release() }
	// Seal an established system domain above insecure mode. Private UTS
	// namespaces retain their own names and may configure them independently.
	if security.securelevel() >= 1 && domainname[0] != 0 {
		return errno.err, errno.eperm
	}
	unsafe {
		C.memset(&domainname[0], 0, uts_name_len)
		C.memcpy(&domainname[0], text.str, text.len)
	}
	return 0, 0
}

// Straight from the global bytes outside a namespace: hostname_text()
// allocates there, and uname(2) left that copy behind on every call.
pub fn copy_hostname(destination u64) {
	unsafe { C.memset(voidptr(destination), 0, uts_name_len) }
	if uts_namespace() != unsafe { nil } || hostname[0] == 0 {
		text := hostname_text()
		unsafe { C.memcpy(voidptr(destination), text.str, text.len) }
		return
	}
	unsafe { C.memcpy(voidptr(destination), &hostname[0], C.strlen(charptr(&hostname[0]))) }
}

pub fn copy_domainname(destination u64) {
	unsafe { C.memset(voidptr(destination), 0, uts_name_len) }
	if uts_namespace() != unsafe { nil } {
		text := domainname_text()
		unsafe { C.memcpy(voidptr(destination), text.str, text.len) }
		return
	}
	unsafe { C.memcpy(voidptr(destination), &domainname[0], C.strlen(charptr(&domainname[0]))) }
}
