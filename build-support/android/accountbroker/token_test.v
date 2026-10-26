// SPDX-License-Identifier: GPL-2.0-or-later
module accountbroker

import accountipc
import nativeaccountauth

#include <sys/socket.h>
fn C.socketpair(i32, i32, i32, &i32) i32

fn token_pair() (int, int) {
	mut fds := [i32(-1), i32(-1)]!
	assert C.socketpair(C.AF_UNIX, C.SOCK_STREAM, 0, &fds[0]) == 0
	return int(fds[0]), int(fds[1])
}

fn token_caller() nativeaccountauth.Caller {
	return nativeaccountauth.Caller{'org.vinix.app', 10001, 10001, 1234, 'a'.repeat(64), 'b'.repeat(64)}
}

fn test_token_route_preserves_exact_identity_and_only_returns_authenticated_result() {
	service_fd, service_peer := token_pair()
	client_fd, client_peer := token_pair()
	mut service := accountipc.open_stream(service_peer)!
	mut client := accountipc.open_stream(client_peer)!
	mut broker := Broker{service: accountipc.open_stream(service_fd)!, incoming: chan Incoming{cap: 32}, lifetime: -1}
	defer { broker.close(); service.close(); client.close() }
	broker.admit(Incoming{fd: client_fd, ok: true, authorized: nativeaccountauth.AuthorizedRequest{
		token_caller(), nativeaccountauth.Request{id: 91, operation: .get_auth_token,
			account_name: 'account@example.test'.clone(), account_type: 'com.google'.clone(),
			auth_token_type: 'oauth2:scope'.clone()}}})!
	broker.pump(0)!
	packet := service.read(0)!
	assert packet.available
	command := accountipc.decode_command(packet.header, packet.body)!
	defer { accountipc.dispose_command(command); unsafe { packet.body.free() } }
	assert command.request.operation == .get_auth_token
	assert command.request.account_name == ?string('account@example.test')
	assert command.request.account_type == ?string('com.google')
	assert command.request.auth_token_type == ?string('oauth2:scope')
	assert command.caller == token_caller()
	// A session number alone does not authorize a token response.
	wrong := accountipc.encode_event(accountipc.Event{kind: .result, id: command.session,
		capability: []u8{len: 32, init: 0x55}}, true)!
	defer { unsafe { wrong.free() } }
	mut rejected := false
	broker.callback(accountipc.Packet{true, accountipc.decode_header(wrong[..accountipc.header_size])!, wrong[accountipc.header_size..]}) or { rejected = true }
	assert rejected && broker.active() == 1
	// Fixture values exercise byte preservation; no token is minted by broker.
	values := [nativeaccountauth.Option{'authtoken', nativeaccountauth.Scalar{kind: .text, text: 'service-fixture-value'}},
		nativeaccountauth.Option{'android.accounts.expiry', nativeaccountauth.Scalar{kind: .int64, number: 1234567890000}}]
	wire := accountipc.encode_event(accountipc.Event{kind: .result, id: command.session,
		capability: command.capability, options: values}, true)!
	defer { unsafe { wire.free() } }
	service.enqueue(wire)!; service.flush()!; broker.pump(0)!
	returned := client.read(0)!
	assert returned.available
	event := accountipc.decode_event(returned.header, returned.body, false)!
	defer { accountipc.dispose_event(event); unsafe { returned.body.free() } }
	assert event.kind == .result && event.id == 91 && event.options == values
	assert event.capability.len == 0 && broker.active() == 0
}
