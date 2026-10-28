// SPDX-License-Identifier: GPL-2.0-or-later
// Root-owned request routing. Authentication is from accepted Unix peers;
// response authority is scoped to one service connection and random session.
module accountbroker

import accountipc
import accountinteraction
import accountuifd
import crypto.rand
import nativeaccountauth
import time

#include <unistd.h>

fn C.close(i32) i32
fn C.getuid() u32
fn C.geteuid() u32

struct Incoming {
	worker     u64
	fd         int
	ok         bool
	authorized nativeaccountauth.AuthorizedRequest
}

struct Worker {
	id   u64
	task thread
}

struct Session {
	request    u64
	operation  nativeaccountauth.Operation
	capability []u8
	deadline   i64
	output     &accountipc.Stream = unsafe { nil }
	caller     nativeaccountauth.Caller
mut:
	terminal  bool
	cancelled bool
}

@[heap]
pub struct Broker {
	registry nativeaccountauth.Registry
	selected nativeaccountauth.Entry
	pid      int
	lifetime int
	incoming chan Incoming
mut:
	service      &accountipc.Stream        = unsafe { nil }
	interactions &accountinteraction.Table = unsafe { nil }
	ui           &accountuifd.Controller   = unsafe { nil }
	ui_launch    []u8
	ui_ack       u64
	ui_session   u64
	sessions     map[u64]Session
	next         u64 = 1
	pending      int
	workers      []Worker
	next_worker  u64 = 1
	closed       bool
}

fn (b &Broker) origin() nativeaccountauth.Caller {
	return nativeaccountauth.Caller{b.selected.package_name, b.selected.uid, b.selected.gid, b.pid, b.selected.apk_sha256, b.selected.certificate_sha256}
}

// Only administrator-selected components declared by the pinned APK may be
// supplied here. Configure before accepting any application or service peer.
pub fn (mut b Broker) allow_interactions(targets []accountinteraction.Target) ! {
	if b.closed || b.service != unsafe { nil } || b.active() != 0
		|| b.interactions != unsafe { nil } {
		return error('account interaction policy is already fixed')
	}
	b.interactions = accountinteraction.create(b.origin(), targets)!
}

// Takes ownership on success. Only the administrator's root launcher supplies
// this dedicated channel, helper executable, desktop identity and socket path.
pub fn (mut b Broker) configure_ui(controller &accountuifd.Controller) ! {
	if b.closed || b.service != unsafe { nil } || b.active() != 0 || b.ui != unsafe { nil }
		|| controller == unsafe { nil } {
		return error('account UI configuration is already fixed')
	}
	b.ui = controller
}

pub fn create(registry nativeaccountauth.Registry, selected nativeaccountauth.Entry, pid int, lifetime int) !&Broker {
	if C.getuid() != 0 || C.geteuid() != 0 || pid <= 0 || lifetime < 0 {
		return error('account broker requires root, selected service PID and lifetime descriptor')
	}
	nativeaccountauth.peer_credentials(lifetime)!
	return &Broker{ registry: registry, selected: selected, pid: pid, lifetime: lifetime, incoming: chan Incoming{cap: 32} }
}

// The launcher connects only after dropping to the registered service IDs.
// A socketpair made while root is not a substitute for this peer identity.
pub fn (mut b Broker) attach_service(fd int) ! {
	if b.closed || b.service != unsafe { nil } || fd == b.lifetime {
		return error('authenticator service already selected')
	}
	caller := b.registry.authenticate(fd, nativeaccountauth.Claims{ package_name: b.selected.package_name, pid: b.pid })!
	if caller.uid != b.selected.uid || caller.gid != b.selected.gid
		|| caller.apk_sha256 != b.selected.apk_sha256 || caller.certificate_sha256 != b.selected.certificate_sha256 {
		return error('authenticator peer does not match selected service')
	}
	b.service = accountipc.open_stream(fd)!
}

fn receive(registry nativeaccountauth.Registry, fd int, lifetime int, incoming chan Incoming, worker u64) {
	authorized := registry.receive_request(fd, lifetime) or {
		incoming <- Incoming{ worker: worker, fd: fd }
		return
	}
	incoming <- Incoming{ worker: worker, fd: fd, ok: true, authorized: authorized }
}

// At most 32 parse workers, each with the transport's single 5 second deadline.
// Slow application requests never block authenticator callback processing.
pub fn (mut b Broker) accept_client(fd int) ! {
	if b.closed || fd == b.lifetime || b.pending + b.sessions.len >= accountipc.max_sessions {
		return error('account broker request limit reached')
	}
	b.registry.authenticate(fd, nativeaccountauth.Claims{})!
	if b.next_worker == 0 { return error('account parse sequence exhausted') }
	worker := b.next_worker
	b.next_worker++
	b.pending++
	b.workers << Worker{worker, spawn receive(b.registry, fd, b.lifetime, b.incoming, worker)}
}

fn (mut b Broker) admit(incoming Incoming) ! {
	if !incoming.ok {
		C.close(i32(incoming.fd))
		return
	}
	defer { nativeaccountauth.dispose_request(incoming.authorized.request) }
	mut output := accountipc.open_stream(incoming.fd) or {
		C.close(i32(incoming.fd))
		return err
	}
	if b.next == 0 {
		output.close()
		unsafe { free(output) }
		return error('account session sequence exhausted')
	}
	id := b.next
	b.next++
	capability := rand.bytes(32) or {
		output.close()
		unsafe { free(output) }
		return err
	}
	b.sessions[id] = Session{
		request:    incoming.authorized.request.id
		operation:  incoming.authorized.request.operation
		capability: capability
		deadline:   time.sys_mono_now() + 5 * time.minute
		output:     output
		caller:     incoming.authorized.caller
	}
	handoff_stage(.admitted, incoming.authorized.request.operation)
	// Metadata belongs to the trusted APK registry, not the authenticator
	// process. Admission has already authenticated the socket's kernel peer.
	if incoming.authorized.request.operation == .get_authenticator_types {
		descriptions := b.registry.authenticator_descriptions(b.selected) or {
			b.fail(id, 1, 'Account authenticator metadata is unavailable')!
			return
		}
		defer { nativeaccountauth.dispose_authenticator_descriptions(descriptions) }
		b.finish(id, accountipc.Event{kind: .authenticators, id: id, authenticators: descriptions})!
		return
	}
	if b.service == unsafe { nil } {
		b.fail(id, 1, 'Account authenticator is unavailable')!
		return
	}
	if incoming.authorized.request.operation == .redeem_interaction {
		b.redeem(id, incoming.authorized)!
		return
	}
	// The selected service owns its private account database. Its query sees
	// the same authenticated caller as addAccount, never an option claim.
	if incoming.authorized.request.operation !in [.add_account, .get_accounts, .get_auth_token, .invalidate_auth_token] {
		b.fail(id, 6, 'Account operation is not available')!
		return
	}
	command := accountipc.Command{id, capability, incoming.authorized.caller, incoming.authorized.request}
	bytes := accountipc.encode_command(command)!
	defer { unsafe { bytes.free() } }
	b.service.enqueue(bytes)!
	handoff_stage(.dispatch_queued, incoming.authorized.request.operation)
}

fn (mut b Broker) fail(id u64, code int, message string) ! {
	event := accountipc.failure(id, code, message)
	defer { unsafe { event.options.free() } } // keys and message are borrowed
	b.finish(id, event)!
}

fn (mut b Broker) redeem(id u64, authorized nativeaccountauth.AuthorizedRequest) ! {
	if b.interactions == unsafe { nil } {
		b.fail(id, 6, 'Account interaction is unavailable')!
		return
	}
	redemption := authorized.request.redemption or {
		b.fail(id, 7, 'Account interaction ticket is invalid')!
		return
	}
	mut launch := b.interactions.redeem(authorized.caller, redemption.request,
		redemption.capability) or {
		b.fail(id, 7, 'Account interaction ticket is invalid or expired')!
		return
	}
	defer { launch.dispose() }
	session := b.sessions[launch.session] or {
		b.fail(id, 7, 'Account request has ended')!
		return
	}
	if session.terminal || session.output.peer_gone() || time.sys_mono_now() >= session.deadline
		|| !same_capability(session.capability, launch.response_capability) {
		b.revoke(launch.session)
		b.fail(id, 7, 'Account request has ended')!
		return
	}
	handoff_stage(.redeemed, session.operation)
	bytes := accountipc.encode_launch(accountipc.Launch{
		session:     launch.session
		capability:  launch.response_capability
		interaction: accountipc.Interaction{launch.local_handle, launch.target.package_name, launch.target.class_name}
	})!
	defer { unsafe { bytes.free() } }
	if b.ui != unsafe { nil } {
		b.ui.begin(launch.session, launch.response_capability) or {
			handoff_stage(.ui_begin_failed, session.operation)
			b.cancel_service(launch.session)
			b.fail(launch.session, 6, 'Account sign-in window is unavailable')!
			b.fail(id, 6, 'Account sign-in window is unavailable')!
			return
		}
		handoff_stage(.ui_begin, session.operation)
		b.ui_launch = bytes.clone()
		b.ui_ack = id
		b.ui_session = launch.session
		return
	}
	b.service.enqueue(bytes)!
	handoff_stage(.launch_queued, session.operation)
	// This acknowledges delivery of a launch command only. The original
	// addAccount request still waits for an actual authenticator result.
	b.finish(id, accountipc.Event{ kind: .result, id: id })!
}

fn same_capability(a []u8, b []u8) bool {
	if a.len != 32 || b.len != 32 { return false }
	mut difference := u8(0)
	for index in 0 .. 32 { difference |= a[index] ^ b[index] }
	return difference == 0
}

fn (mut b Broker) finish(id u64, event accountipc.Event) ! {
	mut session := b.sessions[id] or { return error('unknown account session') }
	if session.terminal { return error('account session already completed') }
	client_event := accountipc.Event{
		kind:        event.kind
		id:          session.request
		options:     event.options
		accounts:    event.accounts
		authenticators: event.authenticators
		interaction: event.interaction
	}
	bytes := accountipc.encode_event(client_event, false)!
	defer { unsafe { bytes.free() } }
	session.output.enqueue(bytes)!
	if accountipc.terminal(event.kind) {
		if b.ui != unsafe { nil } { b.ui.end(id) }
		if b.interactions != unsafe { nil } { b.interactions.revoke(id) }
		session.terminal = true
		b.sessions[id] = session
		handoff_terminal(session.operation, event)
	}
}

fn (mut b Broker) callback(packet accountipc.Packet) ! {
	event := accountipc.decode_event(packet.header, packet.body, true)!
	defer { accountipc.dispose_event(event) }
	session := b.sessions[event.id] or { return error('authenticator returned an unknown session') }
	if session.terminal || !same_capability(session.capability, event.capability) {
		return error('authenticator response capability is invalid or consumed')
	}
	if event.kind == .interaction {
		if session.operation !in [.add_account, .get_auth_token] { return error('account query cannot start an interaction') }
		handoff_stage(.interaction_received, session.operation)
		if b.interactions == unsafe { nil } {
			b.cancel_service(event.id)
			b.fail(event.id, 6, 'Account interaction is unavailable')!
			return
		}
		ticket := b.interactions.offer(accountinteraction.Offer{
			origin:              b.origin()
			caller:              session.caller
			session:             event.id
			request:             session.request
			response_capability: session.capability
			local_handle:        event.interaction.handle
			target:              accountinteraction.Target{event.interaction.target_package, event.interaction.target_class}
			deadline:            session.deadline
		})!
		defer { unsafe { ticket.free() } }
		b.finish(event.id, accountipc.Event{
			kind:        .interaction
			id:          event.id
			interaction: accountipc.Interaction{ handle: ticket }
		})!
		handoff_stage(.interaction_delivered, session.operation)
		return
	}
	if event.kind !in [.result, .failure, .continued, .accounts]
		|| (event.kind == .accounts && session.operation != .get_accounts)
		|| (event.kind == .result && session.operation == .get_accounts) {
		return error('unsupported authenticator callback')
	}
	b.finish(event.id, event)!
}

fn (mut b Broker) cancel_service(id u64) {
	mut session := b.sessions[id] or { return }
	if b.service != unsafe { nil } && !session.terminal && !session.cancelled {
		bytes := accountipc.encode_event(accountipc.Event{ kind: .cancel, id: id, capability: session.capability }, true) or { []u8{} }
		if bytes.len > 0 {
			b.service.enqueue(bytes) or {
				unsafe { bytes.free() }
				return
			}
			unsafe { bytes.free() }
			session.cancelled = true
			b.sessions[id] = session
		}
	}
}

fn (mut b Broker) revoke(id u64) {
	if b.ui != unsafe { nil } { b.ui.end(id) }
	if b.interactions != unsafe { nil } { b.interactions.revoke(id) }
	b.cancel_service(id)
	session := b.sessions[id] or { return }
	session.output.close()
	unsafe {
		free(session.output)
		session.capability.free()
	}
	b.sessions.delete(id)
}

fn (mut b Broker) clear_ui_launch() {
	unsafe { b.ui_launch.free() }
	b.ui_launch = []u8{}
	b.ui_ack = 0
	b.ui_session = 0
}

fn (mut b Broker) fail_ui(session u64, message string) {
	ack := b.ui_ack
	b.ui.end(session)
	if current := b.sessions[session] {
		if !current.terminal {
			b.cancel_service(session)
			b.fail(session, 4, message) or { b.revoke(session) }
		}
	}
	if current := b.sessions[ack] {
		if !current.terminal { b.fail(ack, 4, message) or { b.revoke(ack) } }
	}
	b.clear_ui_launch()
}

fn (mut b Broker) pump_ui() ! {
	if b.ui == unsafe { nil } { return }
	if b.ui_session != 0 {
		current := b.sessions[b.ui_session] or {
			b.fail_ui(b.ui_session, 'Account request has ended')
			return
		}
		if current.terminal || current.output.peer_gone() || time.sys_mono_now() >= current.deadline {
			handoff_stage(.ui_request_ended, current.operation)
			b.fail_ui(b.ui_session, 'Account request has ended')
			return
		}
	}
	session := b.ui.active_session()
	tick := b.ui.tick() or {
		if current := b.sessions[session] { handoff_stage(.ui_tick_failed, current.operation) }
		b.fail_ui(session, 'Account sign-in window failed')
		return
	}
	if tick.ended {
		if current := b.sessions[tick.session] { handoff_stage(.ui_closed, current.operation) }
		b.fail_ui(tick.session, 'Account sign-in window closed')
		return
	}
	if tick.ready {
		if tick.session != b.ui_session || b.ui_ack == 0 || b.ui_launch.len == 0 {
			return error('unexpected account UI readiness')
		}
		// The SCM_RIGHTS attachment has completed before this launch enters
		// the separate account-command stream. The original result stays pending.
		if current := b.sessions[tick.session] { handoff_stage(.ui_ready, current.operation) }
		b.service.enqueue(b.ui_launch)!
		if current := b.sessions[tick.session] { handoff_stage(.launch_queued, current.operation) }
		b.finish(b.ui_ack, accountipc.Event{ kind: .result, id: b.ui_ack })!
		b.clear_ui_launch()
	}
}

// One root event loop owns this object. Persistent service input/output and
// every client write are nonblocking and have bounded queues/deadlines.
pub fn (mut b Broker) pump(timeout int) ! {
	if b.closed || timeout < 0 || timeout > 1000 { return error('account broker unavailable') }
	for _ in 0 .. accountipc.max_sessions {
		select {
			incoming := <-b.incoming {
				b.pending--
				for index, worker in b.workers {
					if worker.id == incoming.worker {
						worker.task.wait()
						b.workers.delete(index)
						break
					}
				}
				b.admit(incoming)!
			}
			else {
				break
			}
		}
	}
	if b.service != unsafe { nil } {
		packet := b.service.read(timeout) or {
			b.close()
			return err
		}
		if packet.available {
			b.callback(packet) or {
				unsafe { packet.body.free() }
				b.close()
				return err
			}
			unsafe { packet.body.free() }
		}
	}
	b.pump_ui()!
	now := time.sys_mono_now()
	for id, session in b.sessions {
		if session.output.peer_gone() {
			b.revoke(id)
			continue
		}
		if now > session.deadline && !session.terminal {
			b.cancel_service(id)
			b.fail(id, 4, 'Account request timed out') or {
				b.revoke(id)
				continue
			}
		}
		session.output.flush() or {
			b.revoke(id)
			continue
		}
		updated := b.sessions[id] or { continue }
		if updated.terminal && !updated.output.pending_output() { b.revoke(id) }
	}
}

pub fn (b &Broker) active() int { return b.pending + b.sessions.len }

pub fn (mut b Broker) close() {
	if b.closed { return }
	b.closed = true
	// Workers are bounded by one common 5 second request deadline. Joining
	// before disposing the channel avoids a send into freed broker state.
	for worker in b.workers { worker.task.wait() }
	for _ in 0 .. b.pending {
		incoming := <-b.incoming
		C.close(i32(incoming.fd))
		if incoming.ok { nativeaccountauth.dispose_request(incoming.authorized.request) }
	}
	b.pending = 0
	unsafe { b.workers.free() }
	for id, _ in b.sessions { b.revoke(id) }
	b.clear_ui_launch()
	if b.ui != unsafe { nil } {
		b.ui.close()
		unsafe { free(b.ui) }
		b.ui = unsafe { nil }
	}
	unsafe { b.sessions.free() }
	if b.interactions != unsafe { nil } {
		b.interactions.close()
		unsafe { free(b.interactions) }
		b.interactions = unsafe { nil }
	}
	if b.service != unsafe { nil } {
		b.service.close()
		unsafe { free(b.service) }
		b.service = unsafe { nil }
	}
	C.close(i32(b.lifetime))
}
