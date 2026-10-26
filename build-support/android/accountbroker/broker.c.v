// SPDX-License-Identifier: GPL-2.0-or-later
// Root-owned request routing. Authentication is from accepted Unix peers;
// response authority is scoped to one service connection and random session.
module accountbroker

import accountipc
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
	service     &accountipc.Stream = unsafe { nil }
	sessions    map[u64]Session
	next        u64 = 1
	pending     int
	workers     []Worker
	next_worker u64 = 1
	closed      bool
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
		return error('account session sequence exhausted')
	}
	id := b.next
	b.next++
	capability := rand.bytes(32) or {
		output.close()
		return err
	}
	b.sessions[id] = Session{
		request:    incoming.authorized.request.id
		operation:  incoming.authorized.request.operation
		capability: capability
		deadline:   time.sys_mono_now() + 5 * time.minute
		output:     output
	}
	if b.service == unsafe { nil } {
		b.finish(id, accountipc.failure(id, 1, 'Account authenticator is unavailable'))!
		return
	}
	// Only addAccount is implemented. Queries require a real authoritative
	// account store; returning an invented empty account list would mask failure.
	if incoming.authorized.request.operation != .add_account {
		b.finish(id, accountipc.failure(id, 6, 'Account storage is not available'))!
		return
	}
	command := accountipc.Command{id, capability, incoming.authorized.caller, incoming.authorized.request}
	bytes := accountipc.encode_command(command)!
	defer { unsafe { bytes.free() } }
	b.service.enqueue(bytes)!
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
	client_event := accountipc.Event{ kind: event.kind, id: session.request, options: event.options, accounts: event.accounts }
	bytes := accountipc.encode_event(client_event, false)!
	defer { unsafe { bytes.free() } }
	session.output.enqueue(bytes)!
	if accountipc.terminal(event.kind) {
		session.terminal = true
		b.sessions[id] = session
	}
}

fn (mut b Broker) callback(packet accountipc.Packet) ! {
	event := accountipc.decode_event(packet.header, packet.body, true)!
	defer { accountipc.dispose_event(event) }
	session := b.sessions[event.id] or { return error('authenticator returned an unknown session') }
	if session.terminal || !same_capability(session.capability, event.capability) {
		return error('authenticator response capability is invalid or consumed')
	}
	if event.kind !in [.result, .failure, .continued] {
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
	b.cancel_service(id)
	session := b.sessions[id] or { return }
	session.output.close()
	unsafe {
		free(session.output)
		session.capability.free()
	}
	b.sessions.delete(id)
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
	now := time.sys_mono_now()
	for id, session in b.sessions {
		if now > session.deadline && !session.terminal {
			b.cancel_service(id)
			b.finish(id, accountipc.failure(id, 4, 'Account request timed out')) or {
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
	unsafe { b.sessions.free() }
	if b.service != unsafe { nil } {
		b.service.close()
		unsafe { free(b.service) }
		b.service = unsafe { nil }
	}
	C.close(i32(b.lifetime))
}
