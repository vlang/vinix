// SPDX-License-Identifier: GPL-2.0-or-later
@[translated]
module assetprobe

fn C.ATrace_isEnabled() bool
fn C.ATrace_beginSection(&char)
fn C.ATrace_endSection()
fn C.ATrace_beginAsyncSection(&char, i32)
fn C.ATrace_endAsyncSection(&char, i32)
fn C.ATrace_setCounter(&char, i64)

fn trace_events() bool {
	unsafe {
		if C.ATrace_isEnabled() { return false }
		for _ in 0 .. 128 {
			C.ATrace_beginSection(c'outer')
			C.ATrace_beginSection(c'inner')
			C.ATrace_endSection()
			C.ATrace_endSection()
			C.ATrace_beginAsyncSection(c'work', -2147483647 - 1)
			C.ATrace_beginAsyncSection(c'work', 2147483647)
			C.ATrace_endAsyncSection(c'work', -2147483647 - 1)
			C.ATrace_endAsyncSection(c'work', 2147483647)
			C.ATrace_setCounter(c'count', i64(-9223372036854775807) - 1)
			C.ATrace_setCounter(c'count', i64(9223372036854775807))
		}
		return !C.ATrace_isEnabled()
	}
}

fn trace_worker(data voidptr) voidptr {
	return unsafe { voidptr(usize(trace_events())) }
}

fn trace_check() bool {
	unsafe {
		mut worker := C.pthread_t{}
		C.ATrace_beginSection(c'main-thread')
		if C.pthread_create(&worker, nil, trace_worker, nil) != 0 { return false }
		valid := trace_events()
		mut result := voidptr(nil)
		joined := C.pthread_join(worker, &result)
		C.ATrace_endSection()
		if !valid || joined != 0 || usize(result) != 1 { return false }
		C.puts(c'BOOTSTRAP-NDK-TRACE-PASS disabled nested async counters worker')
		return true
	}
}
