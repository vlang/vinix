// SPDX-License-Identifier: GPL-2.0-or-later
module main

fn C.__builtin_return_address(int) voidptr

struct SwiftAccessFailure {}
fn (_ &SwiftAccessFailure) msg() string { return 'iOS: unsupported Swift access scope or exclusive access conflict' }
fn (_ &SwiftAccessFailure) code() int { return 1 }
__global swift_access_failure_value = SwiftAccessFailure{}
fn swift_access_failure() IError { return unsafe { &swift_access_failure_value } }

// Scratch records are borrowed from the caller, never allocated or freed here.
// The three words are Pointer, diagnostic PC, and Next | action (read=0/write=1).
fn swift_access_thread_exit(head voidptr) {
	if head != unsafe { nil } { panic('iOS: Swift access scopes still live at thread exit') }
}
fn swift_access_start() {
	if C.ios_key_create(unsafe { &ios_runtime.swift_access_key }, unsafe { voidptr(swift_access_thread_exit) }) != 0 {
		panic('iOS: cannot create Swift access TLS')
	}
	ios_runtime.swift_access_key_live = true
}
// Called under the runtime lock. Task-local access-set migration is separate work.
fn swift_access_context_checked() ! {
	if ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired
		|| !ios_runtime.swift_access_key_live || swift_task_current() != 0 { return swift_access_failure() }
}
fn swift_access_buffer_valid(buffer u64, size u64) bool {
	return buffer != 0 && buffer & 7 == 0 && buffer <= ~u64(0) - size
}
fn swift_access_begin_checked(pointer u64, buffer u64, flags u64, pc u64) ! {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	swift_access_context_checked()!
	tracked := flags & 32 != 0
	bytes := if tracked { u64(24) } else { u64(8) }
	if flags & ~u64(33) != 0 || pointer == 0 || !swift_access_buffer_valid(buffer,bytes)
		|| (pointer >= buffer && pointer < buffer + bytes) { return swift_access_failure() }
	head := u64(C.pthread_getspecific(ios_runtime.swift_access_key))
	mut node := head
	mut count := u64(0)
	for node != 0 {
		if count == 4096 || !swift_access_buffer_valid(node,24)
			|| (buffer < node + 24 && node < buffer + bytes) { return swift_access_failure() }
		bits := read64(node + 16)
		if read64(node) == pointer && (flags | bits) & 1 != 0 { return swift_access_failure() }
		node = bits & ~u64(1); count++
	}
	if !tracked { unsafe { *(&u64(buffer)) = 0 }; return }
	if count == 4096 || ios_runtime.swift_access_count == ~u64(0) { return swift_access_failure() }
	unsafe { *(&u64(buffer)) = pointer; *(&u64(buffer + 8)) = pc; *(&u64(buffer + 16)) = head | (flags & 1) }
	if C.pthread_setspecific(ios_runtime.swift_access_key,voidptr(buffer)) != 0 { panic('iOS: cannot install Swift access scope') }
	ios_runtime.swift_access_count++
}
@[noinline]
fn swift_access_begin(pointer u64, buffer u64, flags u64, pc u64) {
	location := if pc == 0 { u64(C.__builtin_return_address(0)) } else { pc }
	swift_access_begin_checked(pointer,buffer,flags,location) or { panic(err) }
}
fn swift_access_end_checked(buffer u64) ! {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	swift_access_context_checked()!
	if !swift_access_buffer_valid(buffer,8) { return swift_access_failure() }
	if read64(buffer) == 0 { return }
	mut node := u64(C.pthread_getspecific(ios_runtime.swift_access_key))
	mut previous := u64(0)
	mut count := u64(0)
	for node != 0 {
		if count == 4096 || !swift_access_buffer_valid(node,24) { return swift_access_failure() }
		next := read64(node + 16) & ~u64(1)
		if node == buffer {
			if ios_runtime.swift_access_count == 0 { return swift_access_failure() }
			if previous == 0 {
				if C.pthread_setspecific(ios_runtime.swift_access_key,voidptr(next)) != 0 { panic('iOS: cannot remove Swift access scope') }
			} else { unsafe { *(&u64(previous + 16)) = next | (read64(previous + 16) & 1) } }
			ios_runtime.swift_access_count--; return
		}
		previous = node; node = next; count++
	}
	return swift_access_failure()
}
fn swift_access_end(buffer u64) { swift_access_end_checked(buffer) or { panic(err) } }
fn swift_access_stop_checked() ! {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if ios_runtime.swift_access_count != 0 { return swift_access_failure() }
	if !ios_runtime.swift_access_key_live { return }
	if C.pthread_getspecific(ios_runtime.swift_access_key) != unsafe { nil } { return swift_access_failure() }
	if C.pthread_key_delete(ios_runtime.swift_access_key) != 0 { panic('iOS: cannot retire Swift access TLS') }
	ios_runtime.swift_access_key_live = false
}
fn swift_access_stop() { swift_access_stop_checked() or { panic(err) } }
