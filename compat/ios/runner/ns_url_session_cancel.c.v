// SPDX-License-Identifier: GPL-2.0-or-later
module main

// A never-resumed task has no socket or transfer worker to cancel. Its one
// pending completion is an owned operation, independent of the caller's pool.
// Network-task cancellation will use the same terminal publication/delivery
// contract when the transfer lifecycle is connected.
struct URLSessionCancellation {
	task u64
	error_object u64
mut:
	ran bool
}
type URLSessionComplete = fn (u64, &char, u64, u64, u64)

fn url_session_cancel_publish(work &URLSessionCancellation) {
	C.ios_objc_initialize_lock()
	mut header := url_session_task_state(work.task)
	if read64(work.task + 232) == 2 {
		header.fields[6] = objc_retain(work.error_object)
		write64(work.task + 240, header.fields[6])
		write64(work.task + 232, 3) // NSURLSessionTaskStateCompleted, before callback.
	}
	C.ios_objc_initialize_unlock()
}

fn url_session_cancel_retire_delegate(object u64) {
	C.ios_objc_initialize_lock()
	mut header := url_session_task_state(object)
	retired := header.fields[4]
	header.fields[4] = 0
	C.ios_objc_initialize_unlock()
	// Native tasks release their task delegate after completion. Retiring it
	// outside the lock also breaks a delegate -> task ownership cycle safely.
	objc_release(retired)
}

fn url_session_cancel_run(context voidptr) {
	mut work := unsafe { &URLSessionCancellation(context) }
	work.ran = true
	url_session_cancel_publish(work)
	C.ios_objc_initialize_lock()
	mut header := url_session_task_state(work.task)
	session := header.fields[3] // The work pins the task, which owns its session.
	mut delegate := header.fields[4]
	if delegate == 0 || native_method(read64(delegate), 'URLSession:task:didCompleteWithError:') == 0 {
		delegate = url_session_state(session).fields[3]
	}
	objc_retain(delegate)
	header.url_session_task_callback_thread = u64(C.pthread_self())
	C.ios_objc_initialize_unlock()
	// Invocation happens without the task/queue state locks.
	if delegate != 0 {
		imp := native_method(read64(delegate), 'URLSession:task:didCompleteWithError:')
		if imp != 0 {
			unsafe { URLSessionComplete(voidptr(imp))(delegate, c'URLSession:task:didCompleteWithError:', session, work.task, work.error_object) }
		}
	}
	url_session_cancel_retire_delegate(work.task)
	objc_release(delegate)
	C.ios_objc_initialize_lock()
	url_session_task_state(work.task).url_session_task_callback_thread = 0
	C.ios_objc_initialize_unlock()
}

fn url_session_cancel_cleanup(context voidptr) {
	work := unsafe { &URLSessionCancellation(context) }
	// The operation executor also calls cleanup when shutdown discards a job.
	// Publish the terminal result without invoking application code in that case.
	C.ios_objc_initialize_lock()
	url_session_task_state(work.task).url_session_task_callback_thread = u64(C.pthread_self())
	C.ios_objc_initialize_unlock()
	if !work.ran {
		url_session_cancel_publish(work)
		url_session_cancel_retire_delegate(work.task)
	}
	objc_release(work.error_object)
	C.ios_objc_initialize_lock()
	url_session_task_state(work.task).url_session_task_callback_thread = 0
	C.ios_objc_initialize_unlock()
	objc_release(work.task)
	C.free(context)
}

fn url_session_task_cancel(object u64) {
	C.ios_objc_initialize_lock()
	header := url_session_task_state(object)
	if header.fields[3] == 0 {
		panic('iOS: cancellation requires a session-created data task')
	}
	state := read64(object + 232)
	if state in [u64(2), 3]! { C.ios_objc_initialize_unlock(); return }
	if state != 1 { panic('iOS: cancellation of a running URL session transfer is not implemented') }
	if dispatch_runtime == unsafe { nil } { panic('iOS: URL session cancellation requires the dispatch runtime') }
	// Reserve the single completion before constructors can reenter or another
	// caller can cancel. The operation's reference survives queue suspension.
	objc_retain(object)
	write64(object + 232, 2) // NSURLSessionTaskStateCanceling.
	session := header.fields[3]
	request := obj_header(header.fields[1]).request
	url := objc_retain(request.refs[0])
	C.ios_objc_initialize_unlock()
	mut work := unsafe { &URLSessionCancellation(C.calloc(1, sizeof(URLSessionCancellation))) }
	if work == unsafe { nil } { panic('iOS: cannot allocate URL session cancellation') }
	error_object := if url == 0 {
		domain := owned_string('NSURLErrorDomain')
		result := ns_error_create(domain, -999, 0)
		objc_release(domain)
		objc_autorelease(result)
	} else { connection_error(url, 'NSURLErrorDomain', -999) }
	objc_release(url)
	unsafe { *work = URLSessionCancellation{task: object, error_object: objc_retain(error_object)} }
	queue := url_session_delegate_queue(session)
	ns_operation_queue_submit(queue, work, url_session_cancel_run, url_session_cancel_cleanup)
}

fn url_session_task_require_shutdown() {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	caller := u64(C.pthread_self())
	for _, header in ios_runtime.objects {
		if header.url_session_task_callback_thread == caller {
			panic('iOS: runtime shutdown inside a URL session task callback is not implemented')
		}
	}
}
