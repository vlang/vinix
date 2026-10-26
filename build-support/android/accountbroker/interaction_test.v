// SPDX-License-Identifier: GPL-2.0-or-later
module accountbroker

import accountinteraction
import accountipc
import nativeaccountauth
import time

#include <sys/socket.h>

fn C.socketpair(i32, i32, i32, &i32) i32
fn C.shutdown(i32, i32) i32

fn interaction_pair() (int, int) {
	mut fds := [i32(-1), i32(-1)]!
	assert C.socketpair(C.AF_UNIX, C.SOCK_STREAM, 0, &fds[0]) == 0
	return int(fds[0]), int(fds[1])
}

fn interaction_caller() nativeaccountauth.Caller {
	return nativeaccountauth.Caller{'org.vinix.app', 10001, 10001, 1234, 'a'.repeat(64), 'b'.repeat(64)}
}

fn interaction_request() nativeaccountauth.Request {
	bytes := nativeaccountauth.encode_request(nativeaccountauth.Request{
		id:           77
		operation:    .add_account
		account_type: 'com.google'
	}) or { panic(err) }
	defer { unsafe { bytes.free() } }
	return nativeaccountauth.decode_request_bytes(bytes) or { panic(err) }
}

fn interaction_target() accountinteraction.Target {
	return accountinteraction.Target{'com.google.android.gms', 'com.google.android.gms.auth.uiflows.addaccount.AccountIntroActivity'}
}

struct InteractionFixture {
mut:
	broker  &Broker
	service &accountipc.Stream
	client  &accountipc.Stream
	command accountipc.Command
}

// Authentication has already happened at this unit boundary. These exercise
// the actual distinct request, service, result and one-shot redemption frames.
fn interaction_fixture() &InteractionFixture {
	service_fd, service_peer := interaction_pair()
	client_fd, client_peer := interaction_pair()
	assert C.shutdown(i32(client_peer), C.SHUT_WR) == 0
	mut fixture := &InteractionFixture{
		broker:  &Broker{
			incoming: chan Incoming{cap: 32}
			lifetime: -1
			selected: nativeaccountauth.Entry{
				package_name:       'com.google.android.gms'
				uid:                10002
				gid:                10002
				apk_sha256:         'c'.repeat(64)
				certificate_sha256: 'd'.repeat(64)
			}
			pid:      4321
		}
		service: accountipc.open_stream(service_peer) or { panic(err) }
		client:  accountipc.open_stream(client_peer) or { panic(err) }
	}
	fixture.broker.allow_interactions([interaction_target()]) or { panic(err) }
	fixture.broker.service = accountipc.open_stream(service_fd) or { panic(err) }
	fixture.broker.admit(Incoming{
		fd:         client_fd
		ok:         true
		authorized: nativeaccountauth.AuthorizedRequest{interaction_caller(), interaction_request()}
	}) or { panic(err) }
	fixture.broker.pump(0) or { panic(err) }
	packet := fixture.service.read(0) or { panic(err) }
	assert packet.available
	fixture.command = accountipc.decode_command(packet.header, packet.body) or { panic(err) }
	unsafe { packet.body.free() }
	return fixture
}

fn (mut fixture InteractionFixture) close() {
	fixture.broker.close()
	fixture.service.close()
	fixture.client.close()
	accountipc.dispose_command(fixture.command)
}

fn (mut fixture InteractionFixture) offer() []u8 {
	target := interaction_target()
	bytes := accountipc.encode_event(accountipc.Event{
		kind:        .interaction
		id:          fixture.command.session
		capability:  fixture.command.capability
		interaction: accountipc.Interaction{[]u8{len: 32, init: 8}, target.package_name, target.class_name}
	}, true) or { panic(err) }
	defer { unsafe { bytes.free() } }
	fixture.service.enqueue(bytes) or { panic(err) }
	fixture.service.flush() or { panic(err) }
	fixture.broker.pump(0) or { panic(err) }
	packet := fixture.client.read(0) or { panic(err) }
	defer { unsafe { packet.body.free() } }
	assert packet.available
	event := accountipc.decode_event(packet.header, packet.body, false) or { panic(err) }
	defer { accountipc.dispose_event(event) }
	assert event.id == 77
	assert event.kind == .interaction
	assert event.capability.len == 0
	assert event.interaction.target_package == ''
	assert event.interaction.target_class == ''
	assert event.interaction.handle != fixture.command.capability
	assert event.interaction.handle != []u8{len: 32, init: 8}
	return event.interaction.handle.clone()
}

fn (mut fixture InteractionFixture) redeem(peer nativeaccountauth.Caller, ticket []u8) accountipc.Event {
	fd, remote := interaction_pair()
	mut output := accountipc.open_stream(remote) or { panic(err) }
	defer { output.close() }
	bytes := nativeaccountauth.encode_request(nativeaccountauth.Request{
		id:         88
		operation:  .redeem_interaction
		redemption: nativeaccountauth.Redemption{77, ticket}
	}) or { panic(err) }
	defer { unsafe { bytes.free() } }
	decoded := nativeaccountauth.decode_request_bytes(bytes) or { panic(err) }
	fixture.broker.admit(Incoming{
		fd:         fd
		ok:         true
		authorized: nativeaccountauth.AuthorizedRequest{peer, decoded}
	}) or { panic(err) }
	fixture.broker.pump(0) or { panic(err) }
	packet := output.read(0) or { panic(err) }
	defer { unsafe { packet.body.free() } }
	assert packet.available
	assert packet.header.session == 88
	return accountipc.decode_event(packet.header, packet.body, false) or { panic(err) }
}

fn test_interaction_redeems_only_for_original_caller_once_and_preserves_actual_result() {
	mut fixture := interaction_fixture()
	defer { fixture.close() }
	ticket := fixture.offer()
	defer { unsafe { ticket.free() } }
	wrong := fixture.redeem(nativeaccountauth.Caller{ ...interaction_caller(), pid: 1235 }, ticket)
	defer { accountipc.dispose_event(wrong) }
	assert wrong.kind == .failure
	assert fixture.broker.interactions.len() == 1
	ack := fixture.redeem(interaction_caller(), ticket)
	defer { accountipc.dispose_event(ack) }
	assert ack.kind == .result
	assert fixture.broker.active() == 1
	assert fixture.broker.interactions.len() == 0
	packet := fixture.service.read(0) or { panic(err) }
	defer { unsafe { packet.body.free() } }
	assert packet.available
	launch := accountipc.decode_launch(packet.header, packet.body) or { panic(err) }
	defer { accountipc.dispose_launch(launch) }
	assert launch.session == fixture.command.session
	assert launch.capability == fixture.command.capability
	assert launch.interaction.handle == []u8{len: 32, init: 8}
	assert launch.interaction.target_class == interaction_target().class_name
	replay := fixture.redeem(interaction_caller(), ticket)
	defer { accountipc.dispose_event(replay) }
	assert replay.kind == .failure
	assert !(fixture.service.read(0) or { panic(err) }).available
	result := accountipc.encode_event(accountipc.Event{
		kind:       .result
		id:         fixture.command.session
		capability: fixture.command.capability
		options:    [nativeaccountauth.Option{'authAccount', nativeaccountauth.Scalar{
			kind: .text
			text: 'actual-fixture-authenticator-result'
		}}]
	}, true) or { panic(err) }
	defer { unsafe { result.free() } }
	fixture.service.enqueue(result) or { panic(err) }
	fixture.service.flush() or { panic(err) }
	fixture.broker.pump(0) or { panic(err) }
	returned := fixture.client.read(0) or { panic(err) }
	defer { unsafe { returned.body.free() } }
	event := accountipc.decode_event(returned.header, returned.body, false) or { panic(err) }
	defer { accountipc.dispose_event(event) }
	assert event.id == 77
	assert event.options[0].value.text == 'actual-fixture-authenticator-result'
	assert fixture.broker.active() == 0
}

fn test_pending_interaction_is_revoked_on_disconnect_timeout_and_completion() {
	for reason in 0 .. 3 {
		mut fixture := interaction_fixture()
		ticket := fixture.offer()
		assert fixture.broker.interactions.len() == 1
		if reason == 0 {
			fixture.client.close()
		} else if reason == 1 {
			session := fixture.broker.sessions[fixture.command.session] or { panic('missing session') }
			fixture.broker.sessions[fixture.command.session] = Session{
				...session
				deadline: time.sys_mono_now() - 1
			}
		} else {
			fixture.broker.finish(fixture.command.session, accountipc.Event{ kind: .result }) or { panic(err) }
		}
		fixture.broker.pump(0) or { panic(err) }
		assert fixture.broker.interactions.len() == 0, 'revocation reason=${reason}'
		rejected := fixture.redeem(interaction_caller(), ticket)
		assert rejected.kind == .failure
		accountipc.dispose_event(rejected)
		unsafe { ticket.free() }
		fixture.close()
	}
}

fn test_unlisted_activity_cannot_become_public_interaction() {
	mut fixture := interaction_fixture()
	defer { fixture.close() }
	bytes := accountipc.encode_event(accountipc.Event{
		kind:        .interaction
		id:          fixture.command.session
		capability:  fixture.command.capability
		interaction: accountipc.Interaction{[]u8{len: 32, init: 8}, 'com.google.android.gms', 'com.google.android.gms.UnselectedActivity'}
	}, true) or { panic(err) }
	defer { unsafe { bytes.free() } }
	fixture.service.enqueue(bytes) or { panic(err) }
	fixture.service.flush() or { panic(err) }
	fixture.broker.pump(0) or {
		assert fixture.broker.closed
		return
	}
	assert false, 'unselected Activity must fail closed'
}
