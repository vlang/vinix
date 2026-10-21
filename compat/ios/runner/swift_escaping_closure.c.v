// SPDX-License-Identifier: GPL-2.0-or-later
module main

fn C.__atomic_load_n(&u64, int) u64

struct SwiftEscapingClosureFailure {}
fn (_ &SwiftEscapingClosureFailure) msg() string { return 'iOS: unsupported Swift escaping closure arguments or refcount header' }
fn (_ &SwiftEscapingClosureFailure) code() int { return 1 }
__global swift_escaping_closure_failure_value = SwiftEscapingClosureFailure{}
fn swift_escaping_closure_failure() IError { return unsafe { &swift_escaping_closure_failure_value } }

fn swift_escaping_closure_number(value u32) {
	storage := unsafe { &u8(C.__builtin_alloca(10)) }
	mut number := value
	mut start := u64(10)
	for {
		start--
		unsafe { storage[start] = u8(48 + number % 10) }
		number /= 10
		if number == 0 { break }
	}
	swift_fatal_write(u64(storage) + start, 10 - start)
}

// SwiftObject.mm and SwiftShims/swift/shims/RefCount.h define this C ABI.
// Borrow the caller's live, readable 16-byte header without registering it
// for ARC or reading its metadata. Stack closures have refcount word 5;
// uniqueness ignores the low 32 bits (unowned count and deallocation flag).
fn swift_escaping_closure_checked(object u64, filename u64, length i32, line i32, column i32, verification u32) !bool {
	if verification > 1 { return swift_escaping_closure_failure() }
	if object == 0 { return false }
	if object & 7 != 0 || object > ~u64(0) - 16 { return swift_escaping_closure_failure() }
	bits := C.__atomic_load_n(unsafe { &u64(object + 8) }, 2)
	immortal := bits & 0xffffffff == 0xffffffff
	if (bits >> 63 != 0 && !immortal) || bits & (u64(1) << 32) != 0 {
		// Side-table ARC is not implemented. Never guess its uniqueness or
		// follow an encoded pointer into an unsupported layout.
		return swift_escaping_closure_failure()
	}
	if bits >> 32 == 0 { return false }
	if length < 0 || (length != 0 && (filename == 0 || filename > ~u64(0) - u64(length))) {
		return swift_escaping_closure_failure()
	}
	message := if verification == 0 { 'closure argument was escaped in withoutActuallyEscaping block' }
		else { 'closure argument passed as @noescape to Objective-C has escaped' }
	swift_fatal_write(u64(message.str), u64(message.len))
	swift_fatal_write(u64(c': file '), 7)
	swift_fatal_text(SwiftFatalBytes{ address: filename, count: u64(length), valid: true })
	swift_fatal_write(u64(c', line '), 7)
	swift_escaping_closure_number(u32(line))
	swift_fatal_write(u64(c', column '), 9)
	swift_escaping_closure_number(u32(column))
	swift_fatal_write(u64(c' \n'), 2)
	// Like Swift, report and return true; the caller decides whether to trap.
	// Host debugger crash annotations/backtraces are not available on Vinix.
	return true
}

fn swift_escaping_closure(object u64, filename u64, length i32, line i32, column i32, verification u32) bool {
	return swift_escaping_closure_checked(object, filename, length, line, column, verification) or { panic(err) }
}
