// SPDX-License-Identifier: GPL-2.0-or-later
module accountbroker

import accountipc
import nativeaccountauth

#include <sys/socket.h>

fn C.socketpair(i32, i32, i32, &i32) i32

fn pair() (int, int) {
	mut fds := [i32(-1), i32(-1)]!
	assert C.socketpair(C.AF_UNIX, C.SOCK_STREAM, 0, &fds[0]) == 0
	return int(fds[0]), int(fds[1])
}

fn caller() nativeaccountauth.Caller {
	return nativeaccountauth.Caller{'org.vinix.app', 10001, 10001, 1234, 'a'.repeat(64), 'b'.repeat(64)}
}

fn request(op nativeaccountauth.Operation) nativeaccountauth.Request {
	bytes := nativeaccountauth.encode_request(nativeaccountauth.Request{ id: 77, operation: op, account_type: 'com.google' }) or { panic(err) }
	defer { unsafe { bytes.free() } }
	return nativeaccountauth.decode_request_bytes(bytes) or { panic(err) }
}

// This unit fixture starts after production peer/registry authentication; it
// exercises actual stream bytes, session binding and callback routing only.
fn test_real_stream_callback_translates_ids_and_consumes_authority_once() {
	service_fd, service_peer := pair()
	client_fd, client_peer := pair()
	mut service := accountipc.open_stream(service_peer) or { panic(err) }
	mut client := accountipc.open_stream(client_peer) or { panic(err) }
	mut broker := Broker{ service: accountipc.open_stream(service_fd) or { panic(err) }, incoming: chan Incoming{cap: 32}, lifetime: -1 }
	defer {
		broker.close()
		service.close()
		client.close()
	}
	broker.admit(Incoming{ fd: client_fd, ok: true, authorized: nativeaccountauth.AuthorizedRequest{caller(), request(.add_account)} }) or { panic(err) }
	broker.pump(0) or { panic(err) }
	packet := service.read(0) or { panic(err) }
	assert packet.available
	command := accountipc.decode_command(packet.header, packet.body) or { panic(err) }
	assert command.session == 1
	assert command.request.id == 77
	assert command.caller == caller()
	assert command.capability.len == 32
	service.enqueue(accountipc.encode_event(accountipc.Event{ kind: .continued, id: command.session, capability: command.capability }, true) or { panic(err) }) or { panic(err) }
	service.flush() or { panic(err) }
	broker.pump(0) or { panic(err) }
	continued := client.read(0) or { panic(err) }
	assert continued.available
	assert continued.header.kind == .continued
	assert continued.header.session == 77
	assert continued.body.len == 0 // never disclose service response capability
	result := accountipc.Event{
		kind:       .result
		id:         command.session
		capability: command.capability
		options:    [nativeaccountauth.Option{'authAccount', nativeaccountauth.Scalar{ kind: .text, text: 'fixture-result-only' }}]
	}
	response := accountipc.encode_event(result, true) or { panic(err) }
	service.enqueue(response) or { panic(err) }
	service.flush() or { panic(err) }
	broker.pump(0) or { panic(err) }
	returned := client.read(0) or { panic(err) }
	decoded := accountipc.decode_event(returned.header, returned.body, false) or { panic(err) }
	assert decoded.kind == .result
	assert decoded.id == 77
	assert decoded.capability.len == 0
	assert decoded.options == result.options
	assert broker.active() == 0
	broker.callback(accountipc.Packet{true, accountipc.decode_header(response[..accountipc.header_size]) or { panic(err) }, response[accountipc.header_size..]}) or { return }
	assert false, 'terminal response replay must not regain authority'
}

fn test_wrong_capability_closes_backend_and_all_outstanding_sessions() {
	service_fd, service_peer := pair()
	client_fd, client_peer := pair()
	mut service := accountipc.open_stream(service_peer) or { panic(err) }
	mut client := accountipc.open_stream(client_peer) or { panic(err) }
	mut broker := Broker{ service: accountipc.open_stream(service_fd) or { panic(err) }, incoming: chan Incoming{cap: 32}, lifetime: -1 }
	defer {
		broker.close()
		service.close()
		client.close()
	}
	broker.admit(Incoming{ fd: client_fd, ok: true, authorized: nativeaccountauth.AuthorizedRequest{caller(), request(.add_account)} }) or { panic(err) }
	broker.pump(0) or { panic(err) }
	packet := service.read(0) or { panic(err) }
	command := accountipc.decode_command(packet.header, packet.body) or { panic(err) }
	mut forged := command.capability.clone()
	forged[0] ^= 1
	service.enqueue(accountipc.encode_event(accountipc.Event{ kind: .continued, id: command.session, capability: forged }, true) or { panic(err) }) or { panic(err) }
	service.flush() or { panic(err) }
	broker.pump(0) or {
		assert broker.closed
		assert broker.active() == 0
		return
	}
	assert false, 'forged response capability must fail closed'
}

fn test_no_backend_and_account_storage_fail_explicitly() {
	for operation in [nativeaccountauth.Operation.add_account, .get_accounts] {
		client_fd, client_peer := pair()
		mut client := accountipc.open_stream(client_peer) or { panic(err) }
		mut broker := Broker{ incoming: chan Incoming{cap: 32}, lifetime: -1 }
		broker.admit(Incoming{ fd: client_fd, ok: true, authorized: nativeaccountauth.AuthorizedRequest{caller(), request(operation)} }) or { panic(err) }
		broker.pump(0) or { panic(err) }
		packet := client.read(0) or { panic(err) }
		assert packet.available
		event := accountipc.decode_event(packet.header, packet.body, false) or { panic(err) }
		assert event.kind == .failure
		assert event.id == 77
		assert event.accounts.len == 0
		assert event.options[0].key == 'errorCode'
		assert broker.active() == 0
		broker.close()
		client.close()
	}
}

fn test_client_disconnect_revokes_service_session() {
	service_fd, service_peer := pair()
	client_fd, client_peer := pair()
	mut service := accountipc.open_stream(service_peer) or { panic(err) }
	mut broker := Broker{ service: accountipc.open_stream(service_fd) or { panic(err) }, incoming: chan Incoming{cap: 32}, lifetime: -1 }
	defer {
		broker.close()
		service.close()
	}
	broker.admit(Incoming{ fd: client_fd, ok: true, authorized: nativeaccountauth.AuthorizedRequest{caller(), request(.add_account)} }) or { panic(err) }
	broker.pump(0) or { panic(err) }
	packet := service.read(0) or { panic(err) }
	command := accountipc.decode_command(packet.header, packet.body) or { panic(err) }
	C.close(i32(client_peer))
	service.enqueue(accountipc.encode_event(accountipc.Event{ kind: .continued, id: command.session, capability: command.capability }, true) or { panic(err) }) or { panic(err) }
	service.flush() or { panic(err) }
	broker.pump(0) or { panic(err) }
	assert broker.active() == 0
	broker.pump(0) or { panic(err) }
	cancel := service.read(0) or { panic(err) }
	event := accountipc.decode_event(cancel.header, cancel.body, true) or { panic(err) }
	assert event.kind == .cancel
	assert event.id == command.session
	assert event.capability == command.capability
}
