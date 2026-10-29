// SPDX-License-Identifier: GPL-2.0-or-later
module main

import time

type URLSessionDecisionObserver = fn (voidptr)
struct URLSessionDecisionObservation {
	context voidptr
	notify URLSessionDecisionObserver = unsafe { nil }
	cleanup URLSessionDecisionObserver = unsafe { nil }
}

// A response completion may be copied and invoked after the request's worker
// has stopped waiting. Each promoted block owns this independent gate and its
// embedded ABI descriptor. An optional owned observation connects a task's
// lifetime without borrowing any worker storage; teardown must disconnect it.
// The transfer owner must close the gate before dropping its reference.
@[heap]
struct URLSessionResponseDecision {
mut:
	mutex voidptr
	condition voidptr
	refs u64
	settled bool
	closed bool
	allow bool
	descriptor [5]u64 // reserved, size, copy, dispose, signature
	observation URLSessionDecisionObservation
}

struct URLSessionDecisionBlock {
	isa u64
	flags u32
	reserved u32
	invoke u64
	descriptor u64
	gate &URLSessionResponseDecision = unsafe { nil }
}

fn url_session_response_decision_new() &URLSessionResponseDecision {
	mut gate := unsafe { &URLSessionResponseDecision(C.calloc(1, sizeof(URLSessionResponseDecision))) }
	if gate == unsafe { nil } { panic('iOS: cannot allocate response decision') }
	gate.mutex = C.calloc(1, C.ios_sizeof_mutex())
	gate.condition = C.calloc(1, C.ios_sizeof_cond())
	if gate.mutex == unsafe { nil } || gate.condition == unsafe { nil }
		|| C.ios_mutex_create(gate.mutex, 0) != 0 || C.pthread_cond_init(gate.condition, unsafe { nil }) != 0 {
		panic('iOS: cannot initialize response decision')
	}
	gate.refs = 1
	gate.descriptor[1] = sizeof(URLSessionDecisionBlock)
	gate.descriptor[2] = u64(unsafe { voidptr(url_session_response_decision_copy) })
	gate.descriptor[3] = u64(unsafe { voidptr(url_session_response_decision_dispose) })
	gate.descriptor[4] = u64(c'v16@?0q8')
	return gate
}

fn url_session_response_decision_retain(gate &URLSessionResponseDecision) {
	mut state := unsafe { &URLSessionResponseDecision(gate) }
	C.pthread_mutex_lock(state.mutex)
	if state.refs == 0 || state.refs == ~u64(0) { panic('iOS: invalid response decision reference count') }
	state.refs++
	C.pthread_mutex_unlock(state.mutex)
}

fn url_session_response_decision_release(gate &URLSessionResponseDecision) {
	mut state := unsafe { &URLSessionResponseDecision(gate) }
	C.pthread_mutex_lock(state.mutex)
	if state.refs == 0 { panic('iOS: response decision reference count underflow') }
	state.refs--
	last := state.refs == 0
	observation := if last { state.observation } else { URLSessionDecisionObservation{} }
	C.pthread_mutex_unlock(state.mutex)
	if !last { return }
	C.pthread_cond_destroy(state.condition); C.pthread_mutex_destroy(state.mutex)
	C.free(state.condition); C.free(state.mutex); C.free(state)
	if observation.cleanup != unsafe { nil } { observation.cleanup(observation.context) }
}

fn url_session_response_decision_copy(destination u64, source u64) {
	gate := unsafe { (&URLSessionDecisionBlock(source)).gate }
	url_session_response_decision_retain(gate)
	unsafe { (&URLSessionDecisionBlock(destination)).gate = gate }
}

fn url_session_response_decision_dispose(block u64) {
	url_session_response_decision_release(unsafe { (&URLSessionDecisionBlock(block)).gate })
}

fn url_session_response_decision_invoke(block u64, disposition i64) {
	mut gate := unsafe { (&URLSessionDecisionBlock(block)).gate }
	C.pthread_mutex_lock(gate.mutex)
	if gate.settled { C.pthread_mutex_unlock(gate.mutex); return }
	if disposition !in [i64(0), 1]! {
		if gate.closed { C.pthread_mutex_unlock(gate.mutex); return }
		panic('iOS: response conversion to a download/stream task and invalid dispositions are not implemented')
	}
	// Closing the transport does not erase the first application decision.
	// A task adapter can still observe that its deferred handler was called;
	// closed remains true, so this can never restart body delivery.
	gate.allow = disposition == 1
	gate.settled = true
	observation := gate.observation
	gate.observation = URLSessionDecisionObservation{}
	C.pthread_cond_broadcast(gate.condition)
	C.pthread_mutex_unlock(gate.mutex)
	url_session_response_decision_notify(observation, true)
}

fn url_session_response_decision_notify(observation URLSessionDecisionObservation, notify bool) {
	// Move the owned context out of the gate before entering caller code. This
	// includes cleanup, which may retire its last reference to the gate owner.
	if notify && observation.notify != unsafe { nil } { observation.notify(observation.context) }
	if observation.cleanup != unsafe { nil } { observation.cleanup(observation.context) }
}

// Consumes an independently owned context through exactly one cleanup. The
// observer fires once on the first valid decision, including a late decision
// after transport cancellation. A settled gate notifies synchronously.
fn url_session_response_decision_observe(gate &URLSessionResponseDecision, observation URLSessionDecisionObservation) {
	if observation.notify == unsafe { nil } || observation.cleanup == unsafe { nil } { panic('iOS: response observation requires notification and cleanup') }
	mut state := unsafe { &URLSessionResponseDecision(gate) }
	C.pthread_mutex_lock(state.mutex)
	if state.observation.cleanup != unsafe { nil } { panic('iOS: response decision already has an observer') }
	settled := state.settled
	if !settled { state.observation = observation }
	C.pthread_mutex_unlock(state.mutex)
	if settled { url_session_response_decision_notify(observation, true) }
}

fn url_session_response_decision_unobserve(gate &URLSessionResponseDecision) {
	mut state := unsafe { &URLSessionResponseDecision(gate) }
	C.pthread_mutex_lock(state.mutex)
	observation := state.observation
	state.observation = URLSessionDecisionObservation{}
	C.pthread_mutex_unlock(state.mutex)
	url_session_response_decision_notify(observation, false)
}

fn url_session_response_decision_status(gate &URLSessionResponseDecision) (bool, bool) {
	C.pthread_mutex_lock(gate.mutex)
	settled := gate.settled; allow := gate.allow
	C.pthread_mutex_unlock(gate.mutex)
	return settled, allow
}

// The returned heap block has one owned reference. Its descriptor is inside
// the gate, whose reference is acquired by the standard block copy helper.
fn url_session_response_decision_block(gate &URLSessionResponseDecision) u64 {
	block := URLSessionDecisionBlock{isa: block_isa(0), flags: (u32(1) << 25) | (u32(1) << 30),
		invoke: u64(unsafe { voidptr(url_session_response_decision_invoke) }),
		descriptor: u64(unsafe { &gate.descriptor[0] }), gate: gate}
	return block_copy(u64(unsafe { &block }))
}

fn url_session_response_decision_close(gate &URLSessionResponseDecision) {
	mut state := unsafe { &URLSessionResponseDecision(gate) }
	C.pthread_mutex_lock(state.mutex)
	state.closed = true
	C.pthread_cond_broadcast(state.condition)
	C.pthread_mutex_unlock(state.mutex)
}

// Exactly one worker waits per exchange and owns a reference until return.
// Cancellation wins over an allow decision. Bounded condition waits observe
// a borrowed cancellation cell without requiring cancellation to own the gate.
fn url_session_response_decision_wait(gate &URLSessionResponseDecision, cancel &u64, deadline i64) bool {
	mut state := unsafe { &URLSessionResponseDecision(gate) }
	C.pthread_mutex_lock(state.mutex)
	defer { C.pthread_mutex_unlock(state.mutex) }
	for !state.closed && !state.settled && !data_http_cancelled(cancel) && time.sys_mono_now() < deadline {
		remaining := deadline - time.sys_mono_now()
		if remaining <= 0 { break }
		dispatch_wait_interval(state.condition, state.mutex, u64(if remaining > 50 * time.millisecond { 50 * time.millisecond } else { remaining }))
	}
	allowed := !state.closed && state.settled && state.allow && !data_http_cancelled(cancel) && time.sys_mono_now() < deadline
	state.closed = true
	C.pthread_cond_broadcast(state.condition)
	return allowed
}
