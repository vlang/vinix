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
