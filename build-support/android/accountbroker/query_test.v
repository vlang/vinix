// SPDX-License-Identifier: GPL-2.0-or-later
module accountbroker

import accountipc
import nativeaccountauth

#include <sys/socket.h>
fn C.socketpair(i32, i32, i32, &i32) i32

fn query_pair() (int, int) {
	mut fds := [i32(-1), i32(-1)]!
	assert C.socketpair(C.AF_UNIX, C.SOCK_STREAM, 0, &fds[0]) == 0
	return int(fds[0]), int(fds[1])
}

fn query_caller() nativeaccountauth.Caller {
	return nativeaccountauth.Caller{'org.vinix.app', 10001, 10001, 1234, 'a'.repeat(64), 'b'.repeat(64)}
}

fn query_request(op nativeaccountauth.Operation) nativeaccountauth.Request {
	return nativeaccountauth.Request{id: 77, operation: op, account_type: 'com.google'}
}

fn test_query_preserves_authenticated_caller_and_returns_only_accounts() {
	service_fd, service_peer := query_pair()
	client_fd, client_peer := query_pair()
	mut service := accountipc.open_stream(service_peer)!
	mut client := accountipc.open_stream(client_peer)!
	mut broker := Broker{service: accountipc.open_stream(service_fd)!, incoming: chan Incoming{cap: 32}, lifetime: -1}
	defer { broker.close(); service.close(); client.close() }
	broker.admit(Incoming{fd: client_fd, ok: true, authorized: nativeaccountauth.AuthorizedRequest{query_caller(), query_request(.get_accounts)}})!
	broker.pump(0)!
	packet := service.read(0)!
	assert packet.available
	command := accountipc.decode_command(packet.header, packet.body)!
	defer { accountipc.dispose_command(command); unsafe { packet.body.free() } }
	assert command.request.operation == .get_accounts
	assert command.caller == query_caller()
	for kind in [accountipc.Kind.result, .interaction] {
		// Even a correctly authenticated service cannot change query shape.
		mut bytes := []u8{}
		if kind == .result {
			bytes = accountipc.encode_event(accountipc.Event{kind: kind, id: command.session, capability: command.capability}, true)!
		} else {
			bytes = accountipc.encode_event(accountipc.Event{kind: kind, id: command.session, capability: command.capability, interaction: accountipc.Interaction{[]u8{len:32,init:7}, 'com.example.auth', 'com.example.auth.Login'}}, true)!
		}
		mut rejected := false
		broker.callback(accountipc.Packet{true, accountipc.decode_header(bytes[..accountipc.header_size])!, bytes[accountipc.header_size..]}) or { rejected = true }
		assert rejected
		unsafe { bytes.free() }
	}
	accounts := [accountipc.Account{'test@example.invalid', 'com.google'}]
	wire := accountipc.encode_event(accountipc.Event{kind: .accounts, id: command.session, capability: command.capability, accounts: accounts}, true)!
	defer { unsafe { wire.free() } }
	service.enqueue(wire)!; service.flush()!
	broker.pump(0)!
	returned := client.read(0)!
	assert returned.available
	event := accountipc.decode_event(returned.header, returned.body, false)!
	defer { accountipc.dispose_event(event); unsafe { returned.body.free() } }
	assert event.kind == .accounts && event.id == 77
	assert event.accounts == accounts && event.capability.len == 0
	assert broker.active() == 0
}

fn test_addition_cannot_reply_with_account_snapshot() {
	service_fd, service_peer := query_pair()
	client_fd, client_peer := query_pair()
	mut service := accountipc.open_stream(service_peer)!
	mut client := accountipc.open_stream(client_peer)!
	mut broker := Broker{service: accountipc.open_stream(service_fd)!, incoming: chan Incoming{cap: 32}, lifetime: -1}
	defer { broker.close(); service.close(); client.close() }
	broker.admit(Incoming{fd: client_fd, ok: true, authorized: nativeaccountauth.AuthorizedRequest{query_caller(), query_request(.add_account)}})!
	broker.pump(0)!
	packet := service.read(0)!
	command := accountipc.decode_command(packet.header, packet.body)!
	defer { accountipc.dispose_command(command); unsafe { packet.body.free() } }
	wire := accountipc.encode_event(accountipc.Event{kind: .accounts, id: command.session, capability: command.capability}, true)!
	defer { unsafe { wire.free() } }
	mut rejected := false
	broker.callback(accountipc.Packet{true, accountipc.decode_header(wire[..accountipc.header_size])!, wire[accountipc.header_size..]}) or { rejected = true }
	assert rejected
}
