// SPDX-License-Identifier: GPL-2.0-or-later
module accountbroker

import accountipc
import nativeaccountauth

#include <sys/socket.h>

fn C.socketpair(i32, i32, i32, &i32) i32
fn C.recv(i32, voidptr, uint, i32) i32

fn descriptions_pair() (int, int) {
	mut fds := [i32(-1), i32(-1)]!
	assert C.socketpair(C.AF_UNIX, C.SOCK_STREAM, 0, &fds[0]) == 0
	return int(fds[0]), int(fds[1])
}

fn descriptions_caller() nativeaccountauth.Caller {
	return nativeaccountauth.Caller{'com.example.maps', 10001, 10001, 1234, 'a'.repeat(64), 'b'.repeat(64)}
}

fn test_metadata_wire_does_not_bypass_registered_kernel_peer_admission() {
	client_fd, peer_fd := descriptions_pair()
	defer {
		C.close(i32(client_fd))
		C.close(i32(peer_fd))
	}
	mut broker := Broker{ incoming: chan Incoming{cap: 32}, lifetime: -1 }
	defer { broker.close() }
	wire := nativeaccountauth.encode_request(nativeaccountauth.Request{
		id:        55
		operation: .get_authenticator_types
	})!
	defer { unsafe { wire.free() } }
	assert C.send(i32(peer_fd), wire.data, uint(wire.len), 0) == wire.len
	mut rejected := false
	broker.accept_client(client_fd) or { rejected = true }
	// There is no registered kernel peer in this empty registry. Merely
	// presenting a valid metadata frame must not start even a parser worker.
	assert rejected && broker.next_worker == 1
	assert broker.pending == 0 && broker.workers.len == 0 && broker.active() == 0
}

fn test_unauthorized_metadata_admission_closes_without_creating_session() {
	client_fd, peer_fd := descriptions_pair()
	defer { C.close(i32(peer_fd)) }
	mut broker := Broker{ incoming: chan Incoming{cap: 32}, lifetime: -1 }
	defer { broker.close() }
	// A request-shaped object and caller claims do not replace receive_request's
	// authenticated result. In particular no registry read or session occurs.
	broker.admit(Incoming{
		fd:         client_fd
		ok:         false
		authorized: nativeaccountauth.AuthorizedRequest{
			caller:  descriptions_caller()
			request: nativeaccountauth.Request{ id: 999, operation: .get_authenticator_types }
		}
	})!
	assert broker.next == 1 && broker.active() == 0
	mut byte := u8(0)
	assert C.recv(i32(peer_fd), &byte, 1, C.MSG_DONTWAIT) == 0
}

fn descriptions_unavailable(attached bool) ! {
	service_fd, service_peer := descriptions_pair()
	client_fd, client_peer := descriptions_pair()
	mut service := accountipc.open_stream(service_peer)!
	mut client := accountipc.open_stream(client_peer)!
	mut broker := Broker{
		service:  if attached { accountipc.open_stream(service_fd)! } else { unsafe { nil } }
		incoming: chan Incoming{cap: 32}
		lifetime: -1
	}
	defer {
		broker.close()
		service.close()
		client.close()
		if !attached { C.close(i32(service_fd)) }
		unsafe {
			free(service)
			free(client)
		}
	}
	// An empty registry can never attest a selected APK. The failure must come
	// from registry metadata lookup, including before any service attaches.
	broker.admit(Incoming{
		fd:         client_fd
		ok:         true
		authorized: nativeaccountauth.AuthorizedRequest{
			caller:  descriptions_caller()
			request: nativeaccountauth.Request{ id: 77, operation: .get_authenticator_types }
		}
	})!
	broker.pump(0)!
	packet := client.read(0)!
	assert packet.available
	event := accountipc.decode_event(packet.header, packet.body, false)!
	defer {
		accountipc.dispose_event(event)
		unsafe { packet.body.free() }
	}
	assert event.id == 77 && event.kind == .failure
	assert event.capability.len == 0 && event.authenticators.len == 0
	assert event.options.len == 2
	assert event.options[0].key == 'errorCode' && event.options[0].value.number == 1
	assert event.options[1].key == 'errorMessage'
	assert event.options[1].value.text == 'Account authenticator metadata is unavailable'
	assert broker.active() == 0
	if attached {
		assert !service.read(0)!.available
	}
}

fn test_metadata_failure_is_registry_owned_before_and_after_service_attachment() {
	descriptions_unavailable(false)!
	descriptions_unavailable(true)!
}

fn test_live_service_capability_cannot_forge_authenticator_metadata() {
	service_fd, service_peer := descriptions_pair()
	client_fd, client_peer := descriptions_pair()
	mut service := accountipc.open_stream(service_peer)!
	mut client := accountipc.open_stream(client_peer)!
	mut broker := Broker{
		service:  accountipc.open_stream(service_fd)!
		incoming: chan Incoming{cap: 32}
		lifetime: -1
	}
	defer {
		broker.close()
		service.close()
		client.close()
		unsafe {
			free(service)
			free(client)
		}
	}
	broker.admit(Incoming{
		fd:         client_fd
		ok:         true
		authorized: nativeaccountauth.AuthorizedRequest{
			caller:  descriptions_caller()
			request: nativeaccountauth.Request{ id: 88, operation: .get_accounts }
		}
	})!
	broker.service.flush()!
	packet := service.read(0)!
	assert packet.available
	command := accountipc.decode_command(packet.header, packet.body)!
	defer {
		accountipc.dispose_command(command)
		unsafe { packet.body.free() }
	}
	assert command.request.operation == .get_accounts
	// Bypass the service encoder's prohibition: a compromised authenticator
	// can write arbitrary bytes, including its valid capability and a kind9.
	mut forged := accountipc.encode_header(accountipc.Header{.authenticators, command.session, command.capability.len + 2})!
	defer { unsafe { forged.free() } }
	forged << command.capability
	forged << [u8(0), 0] // Empty description list, otherwise well formed.
	service.enqueue(forged)!
	service.flush()!
	mut rejected := false
	broker.pump(0) or { rejected = true }
	// The production pump closes a compromised service and all pending client
	// sessions. It must never forward the forged metadata, even as an error.
	assert rejected && broker.closed && broker.active() == 0
	mut disconnected := false
	_ := client.read(0) or {
		disconnected = true
		accountipc.Packet{}
	}
	assert disconnected
}
