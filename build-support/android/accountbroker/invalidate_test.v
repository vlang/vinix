// SPDX-License-Identifier: GPL-2.0-or-later
module accountbroker

import accountipc
import nativeaccountauth

#include <sys/socket.h>
fn C.socketpair(i32, i32, i32, &i32) i32

fn invalidation_pair() (int, int) {
	mut fds := [i32(-1), i32(-1)]!
	assert C.socketpair(C.AF_UNIX, C.SOCK_STREAM, 0, &fds[0]) == 0
	return int(fds[0]), int(fds[1])
}

fn test_invalidation_routes_authenticated_identity_and_waits_for_service_ack() {
	service_fd, service_peer := invalidation_pair()
	client_fd, client_peer := invalidation_pair()
	mut service := accountipc.open_stream(service_peer)!
	mut client := accountipc.open_stream(client_peer)!
	mut broker := Broker{service: accountipc.open_stream(service_fd)!, incoming: chan Incoming{cap: 32}, lifetime: -1}
	defer { broker.close(); service.close(); client.close() }
	caller := nativeaccountauth.Caller{'com.google.android.apps.maps', 10001, 10001, 1234, 'a'.repeat(64), 'b'.repeat(64)}
	broker.admit(Incoming{fd: client_fd, ok: true, authorized: nativeaccountauth.AuthorizedRequest{
		caller, nativeaccountauth.Request{id: 92, operation: .invalidate_auth_token,
			account_type: 'com.google'.clone(), token_value: 'stored-fixture-value'.clone()}}})!
	broker.pump(0)!
	packet := service.read(0)!
	assert packet.available
	command := accountipc.decode_command(packet.header, packet.body)!
	defer { accountipc.dispose_command(command); unsafe { packet.body.free() } }
	assert command.request.operation == .invalidate_auth_token
	assert command.request.account_type == ?string('com.google')
	assert command.request.token_value == ?string('stored-fixture-value')
	assert command.caller == caller && broker.active() == 1
	assert !client.read(0)!.available
	// A guessed session or UI interaction cannot acknowledge deletion.
	for event in [
		accountipc.Event{kind: .result, id: command.session, capability: []u8{len: 32, init: 0x55}},
		accountipc.Event{kind: .interaction, id: command.session, capability: command.capability,
			interaction: accountipc.Interaction{handle: []u8{len: 32, init: 0x22},
				target_package: 'com.google.android.gms', target_class: 'com.google.android.gms.auth.Fixture'}},
	] {
		wire := accountipc.encode_event(event, true)!
		mut rejected := false
		broker.callback(accountipc.Packet{true, accountipc.decode_header(wire[..accountipc.header_size])!, wire[accountipc.header_size..]}) or { rejected = true }
		assert rejected && broker.active() == 1 && !client.read(0)!.available
		unsafe { wire.free() }
	}
	wire := accountipc.encode_event(accountipc.Event{kind: .result, id: command.session,
		capability: command.capability}, true)!
	defer { unsafe { wire.free() } }
	service.enqueue(wire)!; service.flush()!; broker.pump(0)!
	returned := client.read(0)!
	assert returned.available
	event := accountipc.decode_event(returned.header, returned.body, false)!
	defer { accountipc.dispose_event(event); unsafe { returned.body.free() } }
	assert event.kind == .result && event.id == 92 && event.options.len == 0
	assert event.capability.len == 0 && broker.active() == 0
}
