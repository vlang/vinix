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
