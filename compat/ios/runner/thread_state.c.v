// SPDX-License-Identifier: GPL-2.0-or-later
module main

$if macos { fn C.thread_get_state(u32, i32, voidptr, voidptr) i32 }

// ARM64 counts are numbers of 32-bit words, including native struct padding.
// The accepted native flavor set was measured on the prepared ARM64 host.
fn thread_state_words(flavor i32) u32 {
	return match flavor {
		0, 7, 10, 128 { u32(4) }
		1 { u32(70) }
		2 { u32(65) }
		6 { u32(68) }
		15 { u32(130) }
		17 { u32(132) }
		27 { u32(1) }
		28 { u32(6) }
		131 { u32(5) }
		else { u32(0) }
	}
}

// Capture the executing thread's hardware state at this instruction sequence.
// No signal disposition, signal mask or other thread's registers are changed.
// The final eight bytes are native alignment padding, not vector registers.
@[noinline]
fn thread_state_neon_snapshot(output voidptr) {
	$if arm64 {
		asm arm64 raw {
			"stp q0, q1, [%[output], #0]\n\t"
			"stp q2, q3, [%[output], #32]\n\t"
			"stp q4, q5, [%[output], #64]\n\t"
			"stp q6, q7, [%[output], #96]\n\t"
			"stp q8, q9, [%[output], #128]\n\t"
			"stp q10, q11, [%[output], #160]\n\t"
			"stp q12, q13, [%[output], #192]\n\t"
			"stp q14, q15, [%[output], #224]\n\t"
			"stp q16, q17, [%[output], #256]\n\t"
			"stp q18, q19, [%[output], #288]\n\t"
			"stp q20, q21, [%[output], #320]\n\t"
			"stp q22, q23, [%[output], #352]\n\t"
			"stp q24, q25, [%[output], #384]\n\t"
			"stp q26, q27, [%[output], #416]\n\t"
			"stp q28, q29, [%[output], #448]\n\t"
			"stp q30, q31, [%[output], #480]\n\t"
			"mrs x16, fpsr\n\tstr w16, [%[output], #512]\n\t"
			"mrs x16, fpcr\n\tstr w16, [%[output], #516]\n\t"
			"str xzr, [%[output], #520]"
			;
			; [output] "r" (output)
			; x16
			  memory
		}
	}
}

fn darwin_thread_get_state(name u32, flavor i32, output voidptr, count voidptr) i32 {
	previous := unsafe { *C.ios_errno_address() }
	defer { darwin_set_errno(previous) }
	// Native MIG reads this input count before resolving the destination.
	mut requested := u32(0)
	C.memcpy(unsafe { voidptr(&requested) }, count, 4)
	C.ios_mach_threads_lock()
	result := thread_exception_destination(name)
	mut own := false
	$if linux {
		if result == 0 { own = mach_thread_find(name).handle == u64(C.pthread_self()) }
	}
	C.ios_mach_threads_unlock()
	if result != 0 { return result }
	$if macos { return C.thread_get_state(name, flavor, output, count) }
	$if linux {
		length := thread_state_words(flavor)
		if length == 0 || requested < length { return 4 }
		// Do not manufacture general registers, kernel exception/debug state,
		// page-in counters or SME state, or inspect a remote executing pthread.
		if !own || flavor != 17 { return 46 }
		$if arm64 {
			state := C.__builtin_alloca(528)
			thread_state_neon_snapshot(state)
			C.memcpy(output, state, 528)
			C.memcpy(count, unsafe { voidptr(&length) }, 4)
			return 0
		}
		return 46
	}
}
