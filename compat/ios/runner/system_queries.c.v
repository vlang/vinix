// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <pwd.h>
#include <sys/resource.h>

fn C.getdtablesize() i32
fn C.getgid() i32
fn C.getegid() i32
fn C.gethostname(&char, usize) i32
fn C.getpwuid_r(u32, &C.passwd, &char, usize, &&C.passwd) i32
fn C.getprotobyname(&char) &C.protoent
fn C.getrusage(i32, &C.rusage) i32

// Native structures use the platform headers, including musl's trailing
// reserved words in rusage. Never write these into an application's buffer.
struct C.passwd {
mut:
	pw_name &char
	pw_passwd &char
	pw_uid u32
	pw_gid u32
	pw_gecos &char
	pw_dir &char
	pw_shell &char
	// These members are accessed only in the macOS branch below.
	pw_change i64
	pw_class &char
	pw_expire i64
}

struct C.protoent {
	p_name &char
	p_aliases &&char
	p_proto i32
}

struct C.rusage {
mut:
	ru_utime C.timeval
	ru_stime C.timeval
	ru_maxrss i64
	ru_ixrss i64
	ru_idrss i64
	ru_isrss i64
	ru_minflt i64
	ru_majflt i64
	ru_nswap i64
	ru_inblock i64
	ru_oublock i64
	ru_msgsnd i64
	ru_msgrcv i64
	ru_nsignals i64
	ru_nvcsw i64
	ru_nivcsw i64
}

struct DarwinPasswd {
mut:
	name &char
	password &char
	uid u32
	gid u32
	change i64
	class &char
	gecos &char
	directory &char
	shell &char
	expire i64
}

struct DarwinProtocol {
mut:
	name &char = unsafe { nil }
	aliases &&char = unsafe { nil }
	number i32
}

struct DarwinUsageTime {
	seconds i64
	microseconds i32
	padding i32
}

struct DarwinRusage {
	user DarwinUsageTime
	system DarwinUsageTime
	maxrss i64
	ixrss i64
	idrss i64
	isrss i64
	minflt i64
	majflt i64
	nswap i64
	inblock i64
	oublock i64
	msgsnd i64
	msgrcv i64
	nsignals i64
	nvcsw i64
	nivcsw i64
}

struct SystemQueryStorage {
mut:
	account DarwinPasswd
	account_buffer &char
	account_capacity usize
	protocol DarwinProtocol
}

fn system_protocol_clear(mut protocol DarwinProtocol) {
	if protocol.aliases != unsafe { nil } {
		mut index := usize(0)
		unsafe {
			for protocol.aliases[index] != nil {
				C.free(protocol.aliases[index])
				index++
			}
		}
		C.free(protocol.aliases)
	}
	C.free(protocol.name)
	protocol = DarwinProtocol{}
}

fn system_query_storage_free(pointer voidptr) {
	if pointer == unsafe { nil } { return }
	mut storage := unsafe { &SystemQueryStorage(pointer) }
	system_protocol_clear(mut storage.protocol)
	C.free(storage.account_buffer)
	C.free(storage)
}

fn system_queries_start() ! {
	system_data.query_lock = C.calloc(1, C.ios_sizeof_mutex())
	if system_data.query_lock == unsafe { nil } { return error('iOS: cannot allocate query lock') }
	if C.ios_mutex_create(system_data.query_lock, 0) != 0 {
		C.free(system_data.query_lock)
		system_data.query_lock = unsafe { nil }
		return error('iOS: cannot initialize query lock')
	}
	if C.ios_key_create(&system_data.query_key, unsafe { voidptr(system_query_storage_free) }) != 0 {
		return error('iOS: cannot initialize query storage')
	}
	system_data.query_key_active = true
}

fn system_queries_stop() {
	// Dispatch workers have joined; application threads must also have joined
	// before image shutdown. pthread destructors reclaim each worker's state.
	if system_data.query_key_active {
		system_query_storage_free(C.pthread_getspecific(system_data.query_key))
		C.pthread_setspecific(system_data.query_key, unsafe { nil })
		C.pthread_key_delete(system_data.query_key)
	}
	if system_data.query_lock != unsafe { nil } {
		C.pthread_mutex_destroy(system_data.query_lock)
		C.free(system_data.query_lock)
	}
}

fn system_query_storage() &SystemQueryStorage {
	mut storage := unsafe { &SystemQueryStorage(C.pthread_getspecific(system_data.query_key)) }
	if storage != unsafe { nil } { return storage }
	storage = unsafe { &SystemQueryStorage(C.calloc(1, sizeof(SystemQueryStorage))) }
	if storage == unsafe { nil } { darwin_set_errno(12); return unsafe { nil } }
	result := C.pthread_setspecific(system_data.query_key, storage)
	if result != 0 {
		C.free(storage)
		darwin_set_errno(darwin_native_error(result))
		return unsafe { nil }
	}
	return storage
}

fn darwin_gethostname(destination &char, capacity usize) i32 {
	previous := unsafe { *C.ios_errno_address() }
	if capacity == 0 { return 0 }
	if destination == unsafe { nil } { darwin_set_errno(14); return -1 }
	mut buffer := [256]char{}
	if C.gethostname(unsafe { &buffer[0] }, sizeof(buffer)) != 0 {
		darwin_set_errno(darwin_native_error(unsafe { *C.ios_errno_address() }))
		return -1
	}
	length := C.strnlen(unsafe { &buffer[0] }, sizeof(buffer))
	count := if length < capacity { length } else { capacity - 1 }
	unsafe { C.memcpy(destination, &buffer[0], count); destination[count] = 0 }
	darwin_set_errno(previous)
	return 0
}

fn darwin_getpwuid(uid u32) &DarwinPasswd {
	previous := unsafe { *C.ios_errno_address() }
	mut storage := system_query_storage()
	if storage == unsafe { nil } { return unsafe { nil } }
	mut native := C.passwd{}
	mut found := unsafe { &C.passwd(nil) }
	for {
		if storage.account_capacity == 0 {
			storage.account_capacity = 4096
			storage.account_buffer = C.malloc(storage.account_capacity)
			if storage.account_buffer == unsafe { nil } {
				storage.account_capacity = 0
				darwin_set_errno(12); return unsafe { nil }
			}
		}
		result := C.getpwuid_r(uid, &native, storage.account_buffer, storage.account_capacity, &found)
		if result == C.ERANGE {
			if storage.account_capacity > ~usize(0) / 2 { darwin_set_errno(12); return unsafe { nil } }
			buffer := C.realloc(storage.account_buffer, storage.account_capacity * 2)
			if buffer == unsafe { nil } { darwin_set_errno(12); return unsafe { nil } }
			storage.account_buffer = buffer
			storage.account_capacity *= 2
			continue
		}
		if result != 0 { darwin_set_errno(darwin_native_error(result)); return unsafe { nil } }
		if found == unsafe { nil } { darwin_set_errno(previous); return unsafe { nil } }
		break
	}
	storage.account = DarwinPasswd{
		name: native.pw_name, password: native.pw_passwd, uid: native.pw_uid, gid: native.pw_gid
		class: c'', gecos: native.pw_gecos, directory: native.pw_dir, shell: native.pw_shell
	}
	$if macos {
		storage.account.change = native.pw_change
		storage.account.class = native.pw_class
		storage.account.expire = native.pw_expire
	}
	darwin_set_errno(previous)
	return unsafe { &storage.account }
}

fn darwin_getprotobyname(name &char) &DarwinProtocol {
	previous := unsafe { *C.ios_errno_address() }
	if name == unsafe { nil } { darwin_set_errno(14); return unsafe { nil } }
	mut storage := system_query_storage()
	if storage == unsafe { nil } { return unsafe { nil } }
	$if linux {
		mut protocol := DarwinProtocol{}
		result := system_protocol_file(c'/etc/protocols', name, &protocol)
		if result < 0 {
			darwin_set_errno(darwin_native_error(unsafe { *C.ios_errno_address() }))
			return unsafe { nil }
		}
		darwin_set_errno(previous)
		if result != 0 { return unsafe { nil } }
		system_protocol_clear(mut storage.protocol)
		storage.protocol = protocol
		return unsafe { &storage.protocol }
	}
	// Copy the Mac's native record before another lookup can change it.
	C.pthread_mutex_lock(system_data.query_lock)
	defer { C.pthread_mutex_unlock(system_data.query_lock) }
	darwin_set_errno(0)
	native := C.getprotobyname(name)
	if native == unsafe { nil } {
		native_error := unsafe { *C.ios_errno_address() }
		darwin_set_errno(if native_error == 0 { int(previous) } else { darwin_native_error(native_error) })
		return unsafe { nil }
	}
	mut protocol := DarwinProtocol{number: native.p_proto}
	mut completed := false
	defer { if !completed { system_protocol_clear(mut protocol) } }
	mut count := usize(0)
	unsafe { if native.p_aliases != nil { for native.p_aliases[count] != nil { count++ } } }
	protocol.name = C.strdup(native.p_name)
	protocol.aliases = C.calloc(count + 1, sizeof(voidptr))
	if protocol.name == unsafe { nil } || protocol.aliases == unsafe { nil } {
		darwin_set_errno(12); return unsafe { nil }
	}
	for index in usize(0) .. count {
		unsafe { protocol.aliases[index] = C.strdup(native.p_aliases[index]) }
		if unsafe { protocol.aliases[index] == nil } { darwin_set_errno(12); return unsafe { nil } }
	}
	system_protocol_clear(mut storage.protocol)
	storage.protocol = protocol
	completed = true
	darwin_set_errno(previous)
	return unsafe { &storage.protocol }
}

fn darwin_getrusage(who i32, output &DarwinRusage) i32 {
	if who !in [i32(0), -1] { darwin_set_errno(22); return -1 }
	if output == unsafe { nil } { darwin_set_errno(14); return -1 }
	previous := unsafe { *C.ios_errno_address() }
	mut native := C.rusage{}
	if C.getrusage(who, &native) != 0 {
		darwin_set_errno(darwin_native_error(unsafe { *C.ios_errno_address() }))
		return -1
	}
	mut maxrss := native.ru_maxrss
	$if linux {
		// Linux supplies KiB, Darwin supplies bytes. Saturate signed overflow.
		maxrss = if maxrss > 0x7fffffffffffffff / 1024 { i64(0x7fffffffffffffff) } else { maxrss * 1024 }
	}
	unsafe { *output = DarwinRusage{
		user: DarwinUsageTime{seconds: i64(native.ru_utime.tv_sec), microseconds: i32(native.ru_utime.tv_usec)}
		system: DarwinUsageTime{seconds: i64(native.ru_stime.tv_sec), microseconds: i32(native.ru_stime.tv_usec)}
		maxrss: maxrss, ixrss: native.ru_ixrss, idrss: native.ru_idrss, isrss: native.ru_isrss
		minflt: native.ru_minflt, majflt: native.ru_majflt, nswap: native.ru_nswap
		inblock: native.ru_inblock, oublock: native.ru_oublock, msgsnd: native.ru_msgsnd
		msgrcv: native.ru_msgrcv, nsignals: native.ru_nsignals, nvcsw: native.ru_nvcsw, nivcsw: native.ru_nivcsw
	} }
	darwin_set_errno(previous)
	return 0
}

fn system_queries_symbol(symbol string) ?u64 {
	return match symbol {
		'_getdtablesize' { u64(unsafe { voidptr(C.getdtablesize) }) }
		'_getgid' { u64(unsafe { voidptr(C.getgid) }) }
		'_getegid' { u64(unsafe { voidptr(C.getegid) }) }
		'_gethostname' { u64(unsafe { voidptr(darwin_gethostname) }) }
		'_getpwuid' { u64(unsafe { voidptr(darwin_getpwuid) }) }
		'_getprotobyname' { u64(unsafe { voidptr(darwin_getprotobyname) }) }
		'_getrusage' { u64(unsafe { voidptr(darwin_getrusage) }) }
		else { return none }
	}
}
