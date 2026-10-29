// SPDX-License-Identifier: GPL-2.0-or-later
module main

import time

// The task's pointer is borrowed. This initial reference keeps the task alive
// until terminal delivery/discard. Workers, jobs and the deferred response
// observation acquire independent references. All state uses the runtime lock;
// application calls, object construction and retirement happen outside it.
@[heap]
struct URLSessionTransfer {
mut:
	refs u64
	task u64
	queue u64
	url u64
	ca string
	snapshot &URLSessionRequestSnapshot = unsafe { nil }
	gate &URLSessionResponseDecision = unsafe { nil }
	body []u8
	worker u64
	timeout i64
	failure HTTPTransportFailure
	cancelled bool
	denied bool
	network_done bool
	finish_queued bool
	delegate_retired bool
	retired bool
}
enum URLSessionTransferJobKind { response finish }
struct URLSessionTransferJob {
	transfer &URLSessionTransfer
	kind URLSessionTransferJobKind
mut:
	ran bool
}
struct URLSessionTransferExchange {
	transfer &URLSessionTransfer
	cancel &u64
}
type URLSessionReceiveResponse = fn (u64, &char, u64, u64, u64, u64)
type URLSessionReceiveData = fn (u64, &char, u64, u64, u64)

fn url_session_transfer_retain(work &URLSessionTransfer) {
	C.ios_objc_initialize_lock()
	mut state := unsafe { &URLSessionTransfer(work) }
	if state.refs == 0 || state.refs == ~u64(0) { panic('iOS: invalid URL session transfer reference count') }
	state.refs++
	C.ios_objc_initialize_unlock()
}

fn url_session_transfer_release(context voidptr) {
	mut work := unsafe { &URLSessionTransfer(context) }
	C.ios_objc_initialize_lock()
	if work.refs == 0 { panic('iOS: URL session transfer reference count underflow') }
	work.refs--
	last := work.refs == 0
	if last && !work.retired { panic('iOS: URL session transfer lost its terminal owner') }
	C.ios_objc_initialize_unlock()
	if !last { return }
	previous := url_session_worker_enter()
	pool := objc_pool_push()
	if work.gate != unsafe { nil } {
		url_session_response_decision_close(work.gate)
		url_session_response_decision_release(work.gate)
	}
	if work.snapshot != unsafe { nil } { work.snapshot.dispose() }
	objc_release(work.url); objc_release(work.queue); objc_release(work.task)
	unsafe { work.ca.free(); work.body.free(); C.free(work) }
	objc_pool_pop(pool)
	url_session_worker_leave(previous)
}

fn url_session_transfer_error(work &URLSessionTransfer, code i64) u64 {
	if code == 0 { return 0 }
	if work.url != 0 { return objc_retain(connection_error(work.url, 'NSURLErrorDomain', code)) }
	domain := owned_string('NSURLErrorDomain')
	result := ns_error_create(domain, code, 0)
	objc_release(domain)
	return result
}

fn url_session_transfer_code(work &URLSessionTransfer) i64 {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if work.cancelled || work.denied { return -999 }
	return match work.failure {
		.none { i64(0) }
		.cancelled { i64(-999) }
		.timed_out { i64(-1001) }
		.invalid_request { i64(-1000) }
		.tls { i64(-1200) }
		else { i64(-1) } // Stage known, exact platform cause unknown.
	}
}

fn url_session_transfer_delegate(work &URLSessionTransfer, selector string) u64 {
	C.ios_objc_initialize_lock()
	header := url_session_task_state(work.task)
	mut delegate := header.fields[4]
	if delegate == 0 || native_method(read64(delegate), selector) == 0 { delegate = url_session_state(header.fields[3]).fields[3] }
	result := objc_retain(delegate)
	C.ios_objc_initialize_unlock()
	return result
}

fn url_session_transfer_queue(work &URLSessionTransfer, kind URLSessionTransferJobKind) {
	url_session_transfer_retain(work)
	job := unsafe { &URLSessionTransferJob(C.calloc(1, sizeof(URLSessionTransferJob))) }
	if job == unsafe { nil } { panic('iOS: cannot allocate URL session delegate operation') }
	unsafe { *job = URLSessionTransferJob{transfer: work, kind: kind} }
	ns_operation_queue_submit(work.queue, job, url_session_transfer_job_run, url_session_transfer_job_cleanup)
}

fn url_session_transfer_maybe_finish(work &URLSessionTransfer) {
	C.ios_objc_initialize_lock()
	mut state := unsafe { &URLSessionTransfer(work) }
	mut ready := state.network_done && !state.finish_queued && !state.retired && !ios_runtime.url_session_workers_stopping
	if ready && state.gate != unsafe { nil } { settled, _ := url_session_response_decision_status(state.gate); ready = settled }
	if ready { state.finish_queued = true }
	C.ios_objc_initialize_unlock()
	if ready { url_session_transfer_queue(work, .finish) }
}

fn url_session_transfer_decision(context voidptr) {
	mut work := unsafe { &URLSessionTransfer(context) }
	_, allow := url_session_response_decision_status(work.gate)
	C.ios_objc_initialize_lock()
	if !allow && !work.retired {
		work.denied = true
		write64(work.task + 232, 2)
	}
	C.ios_objc_initialize_unlock()
	url_session_transfer_maybe_finish(work)
}

fn url_session_transfer_response(context voidptr, head HTTPTransportResponseHead, deadline i64) bool {
	exchange := unsafe { &URLSessionTransferExchange(context) }
	mut work := exchange.transfer
	if head.status in [301, 302, 303, 307, 308] && head.field('Location') != none {
		panic('iOS: URL session redirect delegate and request rewriting are not implemented')
	}
	if head.status in [401, 407] && (head.field('WWW-Authenticate') != none || head.field('Proxy-Authenticate') != none) {
		panic('iOS: URL session authentication challenges are not implemented')
	}
	response := url_session_response_object(work.url, head)
	if response == 0 { return false }
	gate := url_session_response_decision_new()
	C.ios_objc_initialize_lock()
	mut header := url_session_task_state(work.task)
	work.gate = gate
	retired := header.fields[5]
	header.fields[5] = response
	write64(work.task + 160, response)
	length := response_header_value(obj_header(response).response.refs[3], 'Content-Length')
	write64(work.task + 224, u64(if length == 0 { i64(-1) } else { response_length(string_text(length)) }))
	C.ios_objc_initialize_unlock()
	objc_release(retired)
	url_session_transfer_retain(work)
	url_session_response_decision_observe(gate, URLSessionDecisionObservation{context: work,
		notify: url_session_transfer_decision, cleanup: url_session_transfer_release})
	url_session_transfer_queue(work, .response)
	return url_session_response_decision_wait(gate, exchange.cancel, deadline)
}

fn url_session_transfer_run(context voidptr, cancel &u64) {
	mut work := unsafe { &URLSessionTransfer(context) }
	exchange := unsafe { &URLSessionTransferExchange(C.calloc(1, sizeof(URLSessionTransferExchange))) }
	if exchange == unsafe { nil } { panic('iOS: cannot allocate URL session exchange context') }
	unsafe { *exchange = URLSessionTransferExchange{transfer: work, cancel: cancel} }
	defer { C.free(exchange) }
	// The policy context and cancellation cell are borrowed only during this
	// synchronous exchange. Delegate jobs capture the transfer and gate only.
	if result := http_transport_exchange_observed(work.snapshot.url, work.snapshot.borrowed_request(), work.ca,
		work.timeout, cancel, exchange, url_session_transfer_response, unsafe { &work.failure },
		unsafe { &u64(work.task + 208) }, unsafe { &u64(work.task + 184) }) {
		C.ios_objc_initialize_lock()
		work.body = result.body
		C.ios_objc_initialize_unlock()
		result.dispose_fields()
	}
}

fn url_session_transfer_worker_cleanup(context voidptr, outcome URLSessionWorkerOutcome) {
	mut work := unsafe { &URLSessionTransfer(context) }
	C.ios_objc_initialize_lock()
	if outcome != .completed {
		work.failure = if outcome == .rejected { HTTPTransportFailure.connection } else { HTTPTransportFailure.cancelled }
	}
	work.network_done = true
	C.ios_objc_initialize_unlock()
	url_session_transfer_maybe_finish(work)
	url_session_transfer_release(context)
}

fn url_session_transfer_retire(work &URLSessionTransfer) {
	C.ios_objc_initialize_lock()
	mut state := unsafe { &URLSessionTransfer(work) }
	if state.retired { C.ios_objc_initialize_unlock(); return }
	state.retired = true
	mut header := url_session_task_state(state.task)
	header.url_session_transfer = unsafe { nil }
	C.ios_objc_initialize_unlock()
	if state.gate != unsafe { nil } {
		url_session_response_decision_close(state.gate)
		url_session_response_decision_unobserve(state.gate)
	}
	url_session_transfer_retire_delegate(state)
	url_session_transfer_release(state) // The initial terminal owner.
}

fn url_session_transfer_retire_delegate(work &URLSessionTransfer) {
	C.ios_objc_initialize_lock()
	mut state := unsafe { &URLSessionTransfer(work) }
	mut retired := u64(0)
	if !state.delegate_retired {
		state.delegate_retired = true
		mut header := url_session_task_state(state.task)
		retired = header.fields[4]; header.fields[4] = 0
	}
	C.ios_objc_initialize_unlock()
	objc_release(retired)
}

fn url_session_transfer_publish(work &URLSessionTransfer, error_object u64) {
	C.ios_objc_initialize_lock()
	mut header := url_session_task_state(work.task)
	retired := header.fields[6]
	header.fields[6] = objc_retain(error_object)
	write64(work.task + 240, error_object)
	write64(work.task + 232, 3)
	C.ios_objc_initialize_unlock()
	objc_release(retired)
}

fn url_session_transfer_terminal_error(work &URLSessionTransfer) u64 {
	for {
		code := url_session_transfer_code(work)
		error_object := url_session_transfer_error(work, code)
		// Cancellation can race object construction. Publish the checked error
		// and completed state in the same critical section that excludes cancel.
		C.ios_objc_initialize_lock()
		if url_session_transfer_code(work) != code {
			C.ios_objc_initialize_unlock(); objc_release(error_object); continue
		}
		mut header := url_session_task_state(work.task)
		retired := header.fields[6]
		header.fields[6] = objc_retain(error_object)
		write64(work.task + 240, error_object); write64(work.task + 232, 3)
		C.ios_objc_initialize_unlock()
		objc_release(retired)
		return error_object
	}
	return 0
}

fn url_session_transfer_job_run(context voidptr) {
	mut job := unsafe { &URLSessionTransferJob(context) }
	work := job.transfer
	previous := url_session_worker_enter()
	defer { url_session_worker_leave(previous) }
	C.ios_objc_initialize_lock()
	stopping := ios_runtime.url_session_workers_stopping
	if !stopping { url_session_task_state(work.task).url_session_task_callback_thread = u64(C.pthread_self()) }
	C.ios_objc_initialize_unlock()
	if stopping { return }
	job.ran = true
	defer {
		C.ios_objc_initialize_lock()
		url_session_task_state(work.task).url_session_task_callback_thread = 0
		C.ios_objc_initialize_unlock()
	}
	session := url_session_task_state(work.task).fields[3]
	if job.kind == .response {
		delegate := url_session_transfer_delegate(work, 'URLSession:dataTask:didReceiveResponse:completionHandler:')
		block := url_session_response_decision_block(work.gate)
		imp := if delegate == 0 { u64(0) } else { native_method(read64(delegate), 'URLSession:dataTask:didReceiveResponse:completionHandler:') }
		if imp != 0 {
			unsafe { URLSessionReceiveResponse(voidptr(imp))(delegate, c'URLSession:dataTask:didReceiveResponse:completionHandler:', session, work.task,
				url_session_task_state(work.task).fields[5], block) }
		} else { url_session_response_decision_invoke(block, 1) }
		block_release(block); objc_release(delegate)
		return
	}
	if url_session_transfer_code(work) == 0 && work.body.len != 0 {
		data := url_session_data_object(work.body)
		if data == 0 { panic('iOS: URL session data construction failed') }
		if url_session_transfer_code(work) == 0 {
			delegate := url_session_transfer_delegate(work, 'URLSession:dataTask:didReceiveData:')
			imp := if delegate == 0 { u64(0) } else { native_method(read64(delegate), 'URLSession:dataTask:didReceiveData:') }
			if imp != 0 { unsafe { URLSessionReceiveData(voidptr(imp))(delegate, c'URLSession:dataTask:didReceiveData:', session, work.task, data) } }
			objc_release(delegate)
		}
		objc_release(data)
	}
	error_object := url_session_transfer_terminal_error(work)
	delegate := url_session_transfer_delegate(work, 'URLSession:task:didCompleteWithError:')
	imp := if delegate == 0 { u64(0) } else { native_method(read64(delegate), 'URLSession:task:didCompleteWithError:') }
	if imp != 0 { unsafe { URLSessionComplete(voidptr(imp))(delegate, c'URLSession:task:didCompleteWithError:', session, work.task, error_object) } }
	url_session_transfer_retire_delegate(work)
	objc_release(delegate); objc_release(error_object)
}

fn url_session_transfer_job_cleanup(context voidptr) {
	job := unsafe { &URLSessionTransferJob(context) }
	work := job.transfer
	previous := url_session_worker_enter()
	pool := objc_pool_push()
	if job.kind == .finish {
		if !job.ran {
			error_object := url_session_transfer_error(work, -999)
			url_session_transfer_publish(work, error_object); objc_release(error_object)
		}
		url_session_transfer_retire(work)
	}
	url_session_transfer_release(work)
	C.free(job)
	objc_pool_pop(pool)
	url_session_worker_leave(previous)
}

fn url_session_task_resume(object u64) { url_session_task_resume_with_ca(object, '/etc/ssl/cert.pem') }

// Private CA injection is used only by the loopback fixture. Public resume
// always uses the production CA path; no environment trust override exists.
fn url_session_task_resume_with_ca(object u64, ca string) {
	previous := url_session_worker_enter()
	pool := objc_pool_push()
	defer { objc_pool_pop(pool); url_session_worker_leave(previous) }
	C.ios_objc_initialize_lock()
	mut header := url_session_task_state(object)
	if header.fields[3] == 0 { panic('iOS: resume requires a session-created data task') }
	if read64(object + 232) in [u64(0), 2, 3]! { C.ios_objc_initialize_unlock(); return }
	if ios_runtime.url_session_workers_stopping || dispatch_runtime == unsafe { nil } || system_data == unsafe { nil } { panic('iOS: URL session resume requires a live transfer and dispatch runtime') }
	mut work := unsafe { &URLSessionTransfer(C.calloc(1, sizeof(URLSessionTransfer))) }
	if work == unsafe { nil } { panic('iOS: cannot allocate URL session transfer') }
	work.refs = 2 // Initial terminal owner and this setup scope.
	work.task = objc_retain(object)
	work.url = objc_retain(obj_header(header.fields[2]).request.refs[0])
	header.url_session_transfer = work
	write64(object + 232, 0)
	request := header.fields[2]
	session := header.fields[3]
	configuration := url_session_state(session).fields[2]
	C.ios_objc_initialize_unlock()
	work.snapshot = url_session_request_snapshot(request, configuration)
	profile := work.snapshot.transport_profile()
	if profile != .supported { panic('iOS: URL session request transport profile is not implemented: ' + profile.str()) }
	if work.snapshot.request.timeout != work.snapshot.configuration.request_timeout {
		panic('iOS: URL session distinct request/configuration timeouts are not implemented')
	}
	seconds := if work.snapshot.request.timeout < work.snapshot.configuration.resource_timeout { work.snapshot.request.timeout } else { work.snapshot.configuration.resource_timeout }
	if seconds < 0.000000001 || seconds > 86400 { panic('iOS: URL session timeout exceeds the bounded transport profile') }
	work.timeout = i64(seconds * f64(time.second))
	work.ca = ca.clone()
	work.queue = objc_retain(url_session_delegate_queue(session))
	C.ios_objc_initialize_lock()
	for delegate in [url_session_task_state(object).fields[4], url_session_state(session).fields[3]]! {
		if delegate != 0 && (native_method(read64(delegate), 'URLSession:didReceiveChallenge:completionHandler:') != 0
			|| native_method(read64(delegate), 'URLSession:task:didReceiveChallenge:completionHandler:') != 0) {
			panic('iOS: URL session authentication challenge delegates are not implemented')
		}
	}
	write64(object + 216, u64(work.snapshot.body.len))
	write64(object + 224, ~u64(0))
	C.ios_objc_initialize_unlock()
	url_session_transfer_retain(work) // Submission consumes this reference.
	identity := url_session_workers_submit(work, url_session_transfer_run, url_session_transfer_worker_cleanup)
	C.ios_objc_initialize_lock()
	if !work.retired { work.worker = identity }
	cancelled := work.cancelled
	C.ios_objc_initialize_unlock()
	if cancelled { url_session_workers_cancel(identity) }
	url_session_transfer_release(work)
}

// Called after transport joins and dispatch shutdown/discard, before object
// teardown. Break the pending-handler observation cycle without invoking it.
fn url_session_transfers_stop() {
	pool := objc_pool_push()
	for {
		C.ios_objc_initialize_lock()
		mut selected := unsafe { &URLSessionTransfer(nil) }
		for _, header in ios_runtime.objects {
			if header.url_session_transfer != unsafe { nil } { selected = header.url_session_transfer; url_session_transfer_retain(selected); break }
		}
		C.ios_objc_initialize_unlock()
		if selected == unsafe { nil } { break }
		previous := url_session_worker_enter()
		error_object := url_session_transfer_error(selected, -999)
		url_session_transfer_publish(selected, error_object); objc_release(error_object)
		url_session_transfer_retire(selected)
		url_session_transfer_release(selected)
		url_session_worker_leave(previous)
	}
	objc_pool_pop(pool)
}
