// SPDX-License-Identifier: GPL-2.0-or-later
module main

// XPACLRI is a backwards-compatible architectural hint on processors without
// pointer authentication. Preserve LR while stripping a saved return PC.
fn backtrace_strip_pc(value u64) u64 {
	$if arm64 {
		mut result := u64(0)
		asm volatile arm64 {
			mov x16, x30
			mov x30, value
			xpaclri
			mov result, x30
			mov x30, x16
			; =r (result)
			; r (value)
			; x16
		}
		return result
	} $else {
		return value
	}
}

fn backtrace_frame_pointer(value u64) u64 {
	// Frame links may carry a top-byte tag. They still must resolve inside
	// the current stack before either word of the record can be read.
	return backtrace_strip_pc(value) & 0x00ffffffffffffff
}

fn backtrace_walk(output &u64, capacity i32, start u64, caller u64, low u64, high u64) i32 {
	if capacity <= 0 || output == unsafe { nil }
		|| u64(output) > ~u64(0) - u64(capacity) * 8 {
		return 0
	}
	unsafe { output[0] = backtrace_strip_pc(caller) }
	mut count := i32(1)
	mut frame := backtrace_frame_pointer(start)
	for count < capacity {
		if frame == 0 || high < 16 || frame < low || frame > high - 16 || frame & 7 != 0 { break }
		pc := backtrace_strip_pc(read64(frame + 8))
		next := backtrace_frame_pointer(read64(frame))
		unsafe { output[count] = pc }
		count++
		if next <= frame { break }
		frame = next
	}
	// Native backtrace removes trailing null return PCs without changing any
	// earlier slot. A null PC in the middle is still a captured frame.
	for count > 0 && unsafe { output[count - 1] } == 0 { count-- }
	return count
}

// Capture the application's FP, LR and SP before a compiler-generated frame
// can obscure them. All anonymous/platform frames remain ordinary records;
// no ELF unwind metadata is needed for mapped Mach-O/JIT code.
$if arm64 {
	$if macos {
		@[_naked]
		fn darwin_backtrace() {
			asm volatile arm64 {
				mov x2, x29
				mov x3, x30
				mov x4, sp
				b '_ios_backtrace_capture'
			}
		}
	} $else {
		@[_naked]
		fn darwin_backtrace() {
			asm volatile arm64 {
				mov x2, x29
				mov x3, x30
				mov x4, sp
				b 'ios_backtrace_capture'
			}
		}
	}
} $else {
	fn darwin_backtrace() { panic('iOS: backtrace capture requires ARM64') }
}

@[export: 'ios_backtrace_capture']
fn backtrace_capture(output &u64, capacity i32, frame u64, caller u64, stack u64) i32 {
	if capacity <= 0 || output == unsafe { nil } { return 0 }
	previous := unsafe { *C.ios_errno_address() }
	defer { darwin_set_errno(previous) }
	mut bounds := [2]u64{}
	if C.ios_current_stack_bounds(unsafe { &bounds[0] }) != 0
		|| stack < bounds[0] || stack >= bounds[1] {
		return backtrace_walk(output, capacity, 0, caller, 0, 0)
	}
	// ARM64 stacks grow downwards; never follow a record below the caller's
	// live SP, even if it lies within the thread's reserved stack allocation.
	return backtrace_walk(output, capacity, frame, caller, stack, bounds[1])
}

fn backtrace_symbol(symbol string) ?u64 {
	return match symbol {
		'_backtrace' { u64(unsafe { voidptr(darwin_backtrace) }) }
		else { return none }
	}
}
