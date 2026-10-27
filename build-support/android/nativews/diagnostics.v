// SPDX-License-Identifier: GPL-2.0-or-later
@[translated]
module atlframework

#include <pthread.h>
@[typedef]
struct C.pthread_t {}

fn C.pthread_create(&C.pthread_t, voidptr, fn (voidptr) voidptr, voidptr) i32
fn C.pthread_detach(C.pthread_t) i32
fn C.exit(i32)

type WsGetEnv = fn (voidptr, &voidptr, i32) i32
type WsObjectClass = fn (voidptr, voidptr) voidptr

__global ws_surface_dump_count i32
__global ws_tree_trace_at i64
__global ws_pointer_trace_count u32
__global ws_cancel_trace WsFrameTrace
__global ws_accepted_trace WsFrameTrace
__global ws_exception_trace WsFrameTrace
__global ws_publication_trace WsFrameTrace

struct WsFrameTrace {
mut:
	events u64
	at i64
}

// These probes use native state only: no Java lookups, callbacks or exception
// handling. Separate counters keep accepted frames from hiding cancellations.
fn ws_trace_frame(trace &WsFrameTrace, stage &char) {
	unsafe {
		if C.getenv(c'VINIX_ANDROID_TRACE_TREE') == nil { return }
		trace.events++
		now := ws_millis()
		if trace.events > 3 && now - trace.at < 30000 { return }
		trace.at = now
		buffer := &char(C.alloca(256))
		count := C.snprintf(buffer, 256, c'ANDROID-WS-FRAME stage=%s mono_ms=%jd sequence=%u events=%ju\n',
			stage, C.intmax_t(now), ws.surface.sequence, C.uintmax_t(trace.events))
		if count > 0 && count < 256 { C.write(2, buffer, usize(count)) }
	}
}

fn ws_trace_traversal(cancelled bool, exception bool) {
	unsafe {
		if exception {
			ws_trace_frame(&ws_exception_trace, c'traversal-exception')
		} else if cancelled {
			ws_trace_frame(&ws_cancel_trace, c'predraw-cancel')
		} else {
			ws_trace_frame(&ws_accepted_trace, c'traversal-accepted')
		}
	}
}

fn ws_trace_publication() {
	unsafe { ws_trace_frame(&ws_publication_trace, c'published') }
}

// Log receipt before entering Java, so a blocked callback still leaves evidence.
// At most 64 DOWN/UP events produce two lines each; movement is never logged.
fn ws_trace_pointer_begin(event &WsEvent) u32 {
	unsafe {
		if event.kind != 2 && event.kind != 3 { return 0 }
		if C.getenv(c'VINIX_ANDROID_TRACE_TREE') == nil || ws_pointer_trace_count >= 64 { return 0 }
		ws_pointer_trace_count++
		buffer := &char(C.alloca(256))
		count := C.snprintf(buffer, 256, c'ANDROID-WS-INPUT event=%u phase=received kind=%u mono_ms=%jd sequence=%u x=%d y=%d capture=%d\n',
			ws_pointer_trace_count, event.kind, C.intmax_t(ws_millis()), ws.surface.sequence,
			event.x, event.y, i32(ws.pressed != nil))
		if count > 0 && count < 256 { C.write(2, buffer, usize(count)) }
		return ws_pointer_trace_count
	}
}

fn ws_trace_pointer_end(event &WsEvent, id u32, outcome &char, handled i32, exception bool) {
	unsafe {
		if id == 0 { return }
		buffer := &char(C.alloca(256))
		count := C.snprintf(buffer, 256, c'ANDROID-WS-INPUT event=%u phase=%s kind=%u mono_ms=%jd sequence=%u handled=%d exception=%d\n',
			id, outcome, event.kind, C.intmax_t(ws_millis()), ws.surface.sequence, handled, i32(exception))
		if count > 0 && count < 256 { C.write(2, buffer, usize(count)) }
	}
}

struct WsPixelTrace {
mut:
	frames usize
	at i64
}

// Inspect the existing readback/front buffer without issuing GL calls or
// changing its state. The caller holds the surface/window lock. Counters are
// per surface; only the first three frames and one per 30 seconds are scanned.
fn ws_trace_pixels(stage &char, trace &WsPixelTrace, width i32, height i32, pixels &u8) {
	unsafe {
		if C.getenv(c'VINIX_ANDROID_TRACE_TREE') == nil { return }
		trace.frames++
		now := ws_millis()
		if trace.frames > 3 && now - trace.at < 30000 { return }
		trace.at = now
		if pixels == nil || width <= 0 || height <= 0 { return }
		mut different := i32(0)
		mut opaque := i32(0)
		mut transparent := i32(0)
		for i in 0 .. width * height {
			p := pixels + usize(i) * 4
			if p[0] != pixels[0] || p[1] != pixels[1] || p[2] != pixels[2] { different++ }
			if p[3] == 255 { opaque++ }
			if p[3] == 0 { transparent++ }
		}
		center := pixels + usize((height / 2) * width + width / 2) * 4
		C.printf(c'ANDROID-WS-PIXELS stage=%s frame=%zu size=%dx%d different_rgb=%d opaque=%d transparent=%d first=%02x%02x%02x%02x center=%02x%02x%02x%02x\n',
			stage, trace.frames, width, height, different, opaque, transparent,
			u32(pixels[0]), u32(pixels[1]), u32(pixels[2]), u32(pixels[3]),
			u32(center[0]), u32(center[1]), u32(center[2]), u32(center[3]))
	}
}

// Rendering can run continuously. Sample the tree so diagnostics do not drown
// the serial port or hold up the same UI/render callbacks being investigated.
fn ws_trace_tree(e voidptr, root voidptr) {
	unsafe {
		if C.getenv(c'VINIX_ANDROID_TRACE_TREE') == nil { return }
		now := ws_millis()
		if ws_tree_trace_at != 0 && now - ws_tree_trace_at < 30000 { return }
		ws_tree_trace_at = now
		ws_debug_tree(e, root, 0)
	}
}

// An explicitly selected application diagnostic method, with the usual
// (String, PrintWriter) dump signature. Never enabled by production launchers.
fn ws_dump_surface(e voidptr, view voidptr) {
	unsafe {
		name := C.getenv(c'VINIX_ANDROID_TRACE_SURFACE_DUMP')
		if name == nil || ws_surface_dump_count >= 3 || pending(e) { return }
		ws_surface_dump_count++
		class_object := WsObjectClass(slot(e, 31))(e, view)
		m := Member(slot(e, 33))(e, class_object, name, c'(Ljava/lang/String;Ljava/io/PrintWriter;)V')
		defer { Drop(slot(e, 23))(e, class_object) }
		if pending(e) { ExceptionClear(slot(e, 17))(e); return }
		stream := static_object(e, c'java/lang/System', c'out', c'Ljava/io/PrintStream;')
		args := [Value{ l: stream }, Value{ i: 1 }]!
		writer := new_object(e, c'java/io/PrintWriter', c'(Ljava/io/OutputStream;Z)V', &args[0])
		dump_args := [Value{ l: WsNewUtf(slot(e, 167))(e, c'ANDROID-WS-SURFACE-DUMP ') }, Value{ l: writer }]!
		VoidCall(slot(e, 63))(e, view, m, &dump_args[0])
		call(e, writer, c'java/io/PrintWriter', c'flush', c'()V', nil)
	}
}

fn ws_vm_exit(status i32) {
	unsafe {
		C.printf(c'ANDROID-WS-VM-EXIT status=%d\n', status)
		if ws != nil && ws.vm != nil && C.getenv(c'VINIX_ANDROID_TRACE_THREADS') != nil {
			mut e := voidptr(nil)
			if WsGetEnv(slot(ws.vm, 6))(ws.vm, &e, 0x10006) == 0 { ws_dump_threads(e) }
		}
		C.exit(status)
	}
}

// Android reports uncaught exceptions before invoking an app's own crash
// handler, which may terminate the process without printing its cause.
fn ws_uncaught(e voidptr, worker voidptr, failure voidptr) {
	unsafe {
		name := obj(e, worker, c'java/lang/Thread', c'getName', c'()Ljava/lang/String;', nil)
		chars := ws_utf(e, name)
		C.printf(c'ANDROID-WS-UNCAUGHT thread=%s\n', chars)
		ws_release(e, name, chars)
		call(e, failure, c'java/lang/Throwable', c'printStackTrace', c'()V', nil)
	}
}

fn ws_install_exception_reporter(e voidptr) {
	unsafe {
		handler := new_object(e, c'android/atl/VinixUncaughtException', c'()V', nil)
		args := [Value{ l: handler }]!
		static_void(e, c'java/lang/Thread', c'setUncaughtExceptionPreHandler', c'(Ljava/lang/Thread$UncaughtExceptionHandler;)V', &args[0])
		Drop(slot(e, 23))(e, handler)
	}
}

// TLS clients often catch connection errors and expose only a generic status.
// JUL diagnostics preserve those causes without changing the app's TLS policy.
fn ws_trace_tls_logging(e voidptr) {
	unsafe {
		trace := C.getenv(c'VINIX_ANDROID_TRACE_TLS')
		if trace == nil || trace[0] != `1` { return }
		push_frame(e)
		defer { pop_frame(e) }
		args := [Value{ l: WsNewUtf(slot(e, 167))(e, c'') }]!
		logger := static_obj(e, c'java/util/logging/Logger', c'getLogger', c'(Ljava/lang/String;)Ljava/util/logging/Logger;', &args[0])
		level := static_object(e, c'java/util/logging/Level', c'FINE', c'Ljava/util/logging/Level;')
		level_args := [Value{ l: level }]!
		call(e, logger, c'java/util/logging/Logger', c'setLevel', c'(Ljava/util/logging/Level;)V', &level_args[0])
		handlers := obj(e, logger, c'java/util/logging/Logger', c'getHandlers', c'()[Ljava/util/logging/Handler;', nil)
		if ws_failure(e, c'ANDROID-WS-TLS-TRACE-FAIL logger') { return }
		for i := i32(0); i < ws_array_len(e, handlers); i++ {
			handler := WsArrayGet(slot(e, 173))(e, handlers, i)
			call(e, handler, c'java/util/logging/Handler', c'setLevel', c'(Ljava/util/logging/Level;)V', &level_args[0])
		}
		if !ws_failure(e, c'ANDROID-WS-TLS-TRACE-FAIL handlers') {
			C.puts(c'ANDROID-WS-TLS-TRACE wolfjsse=enabled jul=FINE')
		}
	}
}

// Opt-in startup diagnostics use a separate JNI environment. This also works
// before the application's main Looper starts, when a UI callback cannot run.
fn ws_dump_threads(e voidptr) {
	unsafe {
		push_frame(e)
		defer { pop_frame(e) }
		C.puts(c'ANDROID-WS-THREADS-BEGIN')
		traces := static_obj(e, c'java/lang/Thread', c'getAllStackTraces', c'()Ljava/util/Map;', nil)
		if ws_failure(e, c'ANDROID-WS-THREADS-FAIL get traces') { return }
		keys := obj(e, traces, c'java/util/Map', c'keySet', c'()Ljava/util/Set;', nil)
		threads := obj(e, keys, c'java/util/Set', c'toArray', c'()[Ljava/lang/Object;', nil)
		if ws_failure(e, c'ANDROID-WS-THREADS-FAIL enumerate') { return }
		for i := i32(0); i < ws_array_len(e, threads); i++ {
			push_frame(e)
			worker := WsArrayGet(slot(e, 173))(e, threads, i)
			name := obj(e, worker, c'java/lang/Thread', c'getName', c'()Ljava/lang/String;', nil)
			text := ws_utf(e, name)
			C.printf(c'ANDROID-WS-THREAD %s\n', text)
			ws_release(e, name, text)
			args := [Value{ l: worker }]!
			stack := obj(e, traces, c'java/util/Map', c'get', c'(Ljava/lang/Object;)Ljava/lang/Object;', &args[0])
			if ws_failure(e, c'ANDROID-WS-THREADS-FAIL stack') {
				pop_frame(e)
				return
			}
			for n := i32(0); n < ws_array_len(e, stack); n++ {
				frame := WsArrayGet(slot(e, 173))(e, stack, n)
				line := obj(e, frame, c'java/lang/StackTraceElement', c'toString', c'()Ljava/lang/String;', nil)
				if ws_failure(e, c'ANDROID-WS-THREADS-FAIL frame') {
					pop_frame(e)
					return
				}
				chars := ws_utf(e, line)
				C.printf(c'  at %s\n', chars)
				ws_release(e, line, chars)
				Drop(slot(e, 23))(e, line)
				Drop(slot(e, 23))(e, frame)
			}
			pop_frame(e)
		}
		C.puts(c'ANDROID-WS-THREADS-END')
	}
}

fn ws_trace_threads(vm voidptr) voidptr {
	unsafe {
		mut e := voidptr(nil)
		if WsTextureAttach(slot(vm, 7))(vm, &e, nil) != 0 { return nil }
		defer { WsTextureDetach(slot(vm, 5))(vm) }
		for _ in 0 .. 10 {
			C.usleep(30000000)
			ws_dump_threads(e)
		}
		return nil
	}
}

fn ws_start_diagnostics(vm voidptr) {
	unsafe {
		if C.getenv(c'VINIX_ANDROID_TRACE_THREADS') == nil { return }
		mut worker := C.pthread_t{}
		if C.pthread_create(&worker, nil, ws_trace_threads, vm) == 0 {
			C.pthread_detach(worker)
		} else {
			C.puts(c'ANDROID-WS-THREADS-FAIL create thread')
		}
	}
}
