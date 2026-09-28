// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// pledge(2), as OpenBSD has it. A process promises which groups of system
// calls it will go on making -- "stdio rpath inet", say -- and from then on a
// call outside them kills it with an uncatchable SIGABRT. Promises can only be
// narrowed, and they are kept by children. A second set, the execpromises,
// becomes the promises of whatever program the process executes; a process
// that names none runs its next program unpledged, with its unveil(2) view
// dropped too.
//
// The syscall numbers are Linux's, so which call needs which promise is
// decided per architecture in syscall/table (pledge_*.v); the calls that name
// a file are checked where the file is resolved, in fs/policy.v, against the
// access they ask for. This file holds what is shared: the promise names,
// narrowing, inheritance and what a violation does.
module proc

pub const pledge_stdio = u64(1) << 0
pub const pledge_rpath = u64(1) << 1
pub const pledge_wpath = u64(1) << 2
pub const pledge_cpath = u64(1) << 3
pub const pledge_dpath = u64(1) << 4
pub const pledge_tmppath = u64(1) << 5
pub const pledge_inet = u64(1) << 6
pub const pledge_mcast = u64(1) << 7
pub const pledge_fattr = u64(1) << 8
pub const pledge_chown = u64(1) << 9
pub const pledge_flock = u64(1) << 10
pub const pledge_unix = u64(1) << 11
pub const pledge_dns = u64(1) << 12
pub const pledge_getpw = u64(1) << 13
pub const pledge_sendfd = u64(1) << 14
pub const pledge_recvfd = u64(1) << 15
pub const pledge_tape = u64(1) << 16
pub const pledge_tty = u64(1) << 17
pub const pledge_proc = u64(1) << 18
pub const pledge_exec = u64(1) << 19
pub const pledge_prot_exec = u64(1) << 20
pub const pledge_settime = u64(1) << 21
pub const pledge_ps = u64(1) << 22
pub const pledge_vminfo = u64(1) << 23
pub const pledge_id = u64(1) << 24
pub const pledge_pf = u64(1) << 25
pub const pledge_route = u64(1) << 26
pub const pledge_wroute = u64(1) << 27
pub const pledge_audio = u64(1) << 28
pub const pledge_video = u64(1) << 29
pub const pledge_bpf = u64(1) << 30
pub const pledge_unveil = u64(1) << 31
pub const pledge_error = u64(1) << 32
pub const pledge_vmm = u64(1) << 33
pub const pledge_drm = u64(1) << 34
pub const pledge_disklabel = u64(1) << 35
const pledge_last_bit = 35

// Set in Process.pledge once the process has pledged, and in
// Process.execpledge once it has named execpromises. Zero means "not pledged",
// which is not the same as pledged to nothing: pledge("", NULL) leaves only
// _exit(2).
pub const pledge_set = u64(1) << 63

// The promises every call that names a file needs one of before its access
// is looked at in detail.
pub const pledge_any_path = pledge_rpath | pledge_wpath | pledge_cpath | pledge_dpath | pledge_tmppath | pledge_fattr | pledge_chown | pledge_exec | pledge_unix

// Access a call asks of a file it names, as fs/policy.v passes it to
// pledge_path_verdict() and unveil_verdict().
pub const policy_read = u32(1)
pub const policy_write = u32(2)
pub const policy_exec = u32(4)
// Creates or removes the name.
pub const policy_create = u32(8)
pub const policy_fattr = u32(16)
pub const policy_chown = u32(32)
// mknod(2) of a device or a FIFO.
pub const policy_device = u32(64)
// stat(2) and its relatives: learns that the name exists and what it is.
pub const policy_inspect = u32(128)
// An AF_UNIX socket's name, which pledge covers with "unix" rather than with
// a path promise.
pub const policy_socket = u32(256)

// Errno values; the errno module imports proc, so it cannot be imported here.
const pledge_eperm = u64(1)
const pledge_enoent = u64(2)
const pledge_e2big = u64(7)
const pledge_eacces = u64(13)
const pledge_efault = u64(14)
const pledge_einval = u64(22)
const pledge_enosys = u64(38)

pub const pledge_max_text = 1024

pub fn pledge_bit(name string) u64 {
	return match name {
		'stdio' { pledge_stdio }
		'rpath' { pledge_rpath }
		'wpath' { pledge_wpath }
		'cpath' { pledge_cpath }
		'dpath' { pledge_dpath }
		'tmppath' { pledge_tmppath }
		'inet' { pledge_inet }
		'mcast' { pledge_mcast }
		'fattr' { pledge_fattr }
		'chown' { pledge_chown }
		'flock' { pledge_flock }
		'unix' { pledge_unix }
		'dns' { pledge_dns }
		'getpw' { pledge_getpw }
		'sendfd' { pledge_sendfd }
		'recvfd' { pledge_recvfd }
		'tape' { pledge_tape }
		'tty' { pledge_tty }
		'proc' { pledge_proc }
		'exec' { pledge_exec }
		'prot_exec' { pledge_prot_exec }
		'settime' { pledge_settime }
		'ps' { pledge_ps }
		'vminfo' { pledge_vminfo }
		'id' { pledge_id }
		'pf' { pledge_pf }
		'route' { pledge_route }
		'wroute' { pledge_wroute }
		'audio' { pledge_audio }
		'video' { pledge_video }
		'bpf' { pledge_bpf }
		'unveil' { pledge_unveil }
		'error' { pledge_error }
		'vmm' { pledge_vmm }
		'drm' { pledge_drm }
		'disklabel' { pledge_disklabel }
		else { u64(0) }
	}
}

// The name of promise number `index`, the bit pledge_bit() gives it.
fn pledge_name_at(index int) string {
	return match index {
		0 { 'stdio' }
		1 { 'rpath' }
		2 { 'wpath' }
		3 { 'cpath' }
		4 { 'dpath' }
		5 { 'tmppath' }
		6 { 'inet' }
		7 { 'mcast' }
		8 { 'fattr' }
		9 { 'chown' }
		10 { 'flock' }
		11 { 'unix' }
		12 { 'dns' }
		13 { 'getpw' }
		14 { 'sendfd' }
		15 { 'recvfd' }
		16 { 'tape' }
		17 { 'tty' }
		18 { 'proc' }
		19 { 'exec' }
		20 { 'prot_exec' }
		21 { 'settime' }
		22 { 'ps' }
		23 { 'vminfo' }
		24 { 'id' }
		25 { 'pf' }
		26 { 'route' }
		27 { 'wroute' }
		28 { 'audio' }
		29 { 'video' }
		30 { 'bpf' }
		31 { 'unveil' }
		32 { 'error' }
		33 { 'vmm' }
		34 { 'drm' }
		35 { 'disklabel' }
		else { '?' }
	}
}

// The promises a pledge string names, separated by spaces, or none when it
// names one OpenBSD does not have. The empty string promises nothing.
pub fn pledge_parse(text string) ?u64 {
	mut promises := u64(0)
	mut start := 0
	for i := 0; i <= text.len; i++ {
		if i < text.len && text[i] != ` ` {
			continue
		}
		if i > start {
			word := text[start..i]
			bit := pledge_bit(word)
			unsafe { word.free() }
			if bit == 0 {
				return none
			}
			promises |= bit
		}
		start = i + 1
	}
	return promises
}

// The names of the promises in `promises`, as pledge(2) spells them.
pub fn pledge_names_text(promises u64) string {
	mut text := []u8{cap: 64}
	defer {
		unsafe { text.free() }
	}
	for i := 0; i <= pledge_last_bit; i++ {
		bit := u64(1) << i
		if promises & bit == 0 {
			continue
		}
		if text.len != 0 {
			text << ` `
		}
		for c in pledge_name_at(i) {
			text << c
		}
	}
	return text.bytestr()
}

@[inline]
pub fn (p &Process) is_pledged() bool {
	return p.pledge & pledge_set != 0
}

// Whether the process may make a call that any one of `promises` allows.
@[inline]
pub fn pledge_allows_any(p &Process, promises u64) bool {
	return p.pledge & pledge_set == 0 || p.pledge & promises & ~pledge_set != 0
}

// pledge(2) with its strings already parsed. `has_promises` and `has_exec`
// say whether each was given at all: NULL leaves that set as it is. Answers an
// errno, or 0.
pub fn pledge_apply(mut process Process, has_promises bool, promises u64, has_exec bool,
	execpromises u64) u64 {
	// Only ever narrower: a promise that has been given up stays given up.
	if has_promises && process.pledge & pledge_set != 0
		&& promises & ~process.pledge & ~pledge_set != 0 {
		return pledge_eperm
	}
	if has_exec && process.execpledge & pledge_set != 0
		&& execpromises & ~process.execpledge & ~pledge_set != 0 {
		return pledge_eperm
	}
	if has_exec {
		process.execpledge = execpromises | pledge_set
	}
	if has_promises {
		process.pledge = promises | pledge_set
	}
	return 0
}

// A child gets its parent's promises, execpromises and unveil(2) view.
pub fn pledge_inherit(mut child Process, parent &Process) {
	child.pledge = parent.pledge
	child.execpledge = parent.execpledge
	child.unveil = unveil_copy(parent.unveil)
}

// What execve(2) does to a pledged process. The promises it made for the
// programs it runs become the new program's, and its unveil view carries over
// with them. A process that made none runs the new program unpledged, with
// the whole filesystem in view again, as OpenBSD does.
pub fn pledge_after_exec(mut process Process) {
	if process.execpledge & pledge_set != 0 {
		process.pledge = process.execpledge
		return
	}
	process.pledge = 0
	unveil_release(mut process)
}

// Records that the current call broke the process's promises: it needed one
// of `needed`, which the process no longer has. The call fails with EPERM and
// the process is killed with SIGABRT on its way back to userspace, once the
// call has let go of whatever it holds; see pledge_violation_pending(). A
// process that promised "error" is not killed, and the call fails with ENOSYS
// instead. Answers the errno the call returns.
pub fn pledge_fail(needed u64) u64 {
	mut t := current_thread()
	process := t.process
	if process.pledge & pledge_error != 0 {
		return pledge_enosys
	}
	if t.pledge_violation == 0 {
		// The first broken promise is the one worth reporting; a call that
		// goes on to break more is dead already.
		names := pledge_names_text(needed & ~pledge_set)
		print('${process.name}: pledge "${names}", syscall ${t.pledge_syscall}\n')
		unsafe { names.free() }
	}
	t.pledge_violation = needed | pledge_set
	return pledge_eperm
}

// For a check made inside a call: 0 when the process may do what `promise`
// covers, or the errno the call fails with, the violation recorded.
pub fn pledge_check(promise u64) u64 {
	process := current_thread().process
	if process.pledge & pledge_set == 0 || process.pledge & promise != 0 {
		return 0
	}
	return pledge_fail(promise)
}

// Where an IPv4 socket may send to or connect to, given the destination port
// as it is in the sockaddr, in network order. A process that promised "dns"
// but not "inet" may only reach name servers, on port 53. Answers 0 or the
// errno the call fails with.
pub fn pledge_check_inet_destination(port_be u16) u64 {
	process := current_thread().process
	if process.pledge & pledge_set == 0 || process.pledge & pledge_inet != 0 {
		return 0
	}
	if process.pledge & pledge_dns != 0 && port_be == u16(0x3500) {
		return 0
	}
	return pledge_fail(pledge_inet)
}

// Whether the current thread broke a promise during the call it is leaving,
// and has to be killed before it gets back to userspace.
@[inline]
pub fn pledge_violation_pending() bool {
	t := current_thread()
	return t != unsafe { nil } && t.pledge_violation != 0
}

// A few files libc reaches for on its own: tzset() reads /etc/localtime,
// getpwnam() /etc/passwd, the resolver /etc/resolv.conf. OpenBSD lets a
// pledged process read them without "rpath", as long as it holds the promise
// the libc function belongs to, and without unveiling them. The Linux names
// are added where Linux's libcs use different files: glibc reads
// /etc/nsswitch.conf before either database, and both libcs size their thread
// pools from /sys/devices/system/cpu/online.
//
// Answers -1 when the whitelist does not cover the access, 0 to allow it, or
// an errno to refuse it without calling it a violation.
fn pledge_whitelist(promises u64, path string, access u32) i64 {
	read_only := access & ~(policy_read | policy_inspect) == 0
	read_write := access & ~(policy_read | policy_write | policy_inspect) == 0
	if read_write && path == '/dev/null' {
		return 0
	}
	if read_write && promises & pledge_tty != 0 && path == '/dev/tty' {
		return 0
	}
	if !read_only {
		return -1
	}
	if path == '/etc/localtime' || path.starts_with('/usr/share/zoneinfo/') {
		return 0
	}
	if path == '/dev/urandom' || path == '/dev/random' || path == '/sys/devices/system/cpu/online'
		|| path == '/sys/devices/system/cpu/possible' {
		return 0
	}
	if promises & pledge_getpw != 0 {
		if path == '/etc/shadow' || path == '/etc/gshadow' {
			return i64(pledge_eperm)
		}
		if path == '/etc/passwd' || path == '/etc/group' || path == '/etc/nsswitch.conf' {
			return 0
		}
	}
	if promises & pledge_dns != 0 {
		if path == '/etc/resolv.conf' || path == '/etc/hosts' || path == '/etc/services'
			|| path == '/etc/protocols' || path == '/etc/nsswitch.conf'
			|| path == '/etc/host.conf' || path == '/etc/gai.conf' {
			return 0
		}
	}
	return -1
}

// The promises `access` to a file needs, all of them.
pub fn pledge_path_promises(access u32) u64 {
	if access & policy_socket != 0 {
		return pledge_unix
	}
	// stat(2), access(2) and the like ask only "rpath", whatever access they
	// ask about.
	if access & policy_inspect != 0 {
		return pledge_rpath
	}
	mut needed := u64(0)
	if access & policy_read != 0 {
		needed |= pledge_rpath
	}
	if access & policy_write != 0 {
		needed |= pledge_wpath
	}
	if access & policy_create != 0 {
		needed |= pledge_cpath
	}
	if access & policy_fattr != 0 {
		needed |= pledge_fattr
	}
	if access & policy_chown != 0 {
		needed |= pledge_chown
	}
	if access & policy_device != 0 {
		needed |= pledge_dpath
	}
	if access & policy_exec != 0 {
		needed |= pledge_exec
	}
	return needed
}

// Whether the pledged process may make `access` to the file at `path`, as
// the process itself names it. Answers (errno or 0, whether unveil(2) is to
// be skipped). A refusal other than a whitelisted file's is a violation.
pub fn pledge_path_verdict(process &Process, path string, access u32) (u64, bool) {
	promises := process.pledge & ~pledge_set
	needed := pledge_path_promises(access)
	if needed & ~promises == 0 {
		return 0, false
	}
	whitelisted := pledge_whitelist(promises, path, access)
	if whitelisted == 0 {
		return 0, true
	}
	if whitelisted > 0 {
		return u64(whitelisted), false
	}
	// mkstemp(3) and unlinking what it made: "tmppath" stands in for the
	// path promises under /tmp. unveil(2) still has its say.
	if promises & pledge_tmppath != 0 && path.starts_with('/tmp/')
		&& access & policy_create != 0
		&& access & ~(policy_read | policy_write | policy_create | policy_inspect) == 0 {
		return 0, false
	}
	return pledge_fail(needed & ~promises), false
}
