// SPDX-License-Identifier: GPL-2.0-or-later
module accountbroker

import accountinteraction
import accountipc
import accounthandoff
import nativeaccountauth
import time

#include <sys/socket.h>

fn C.socketpair(i32, i32, i32, &i32) i32
fn C.shutdown(i32, i32) i32
fn C.pipe(&i32) i32
fn C.dup(i32) i32
fn C.dup2(i32, i32) i32
fn C.read(i32, voidptr, usize) isize

fn handoff_capture_start() (i32, i32) {
	mut fds := [i32(-1), i32(-1)]!
	assert C.pipe(&fds[0]) == 0
	saved := C.dup(2)
	assert saved >= 0 && C.dup2(fds[1], 2) == 2
	C.close(fds[1])
	return fds[0], saved
}

fn handoff_capture_end(fd i32, saved i32) []accounthandoff.HandoffDiagnostic {
	assert C.dup2(saved, 2) == 2
	C.close(saved)
	mut bytes := []u8{}
	mut buffer := [4096]u8{}
	for {
		count := C.read(fd, &buffer[0], 4096)
		assert count >= 0
		if count == 0 { break }
		bytes << buffer[..int(count)]
	}
	C.close(fd)
	mut records := []accounthandoff.HandoffDiagnostic{}
	for line in bytes.bytestr().split_into_lines() {
		records << accounthandoff.parse_handoff_diagnostic(line) or { panic('unexpected diagnostic output') }
	}
	return records
}

fn handoff_record(stage int, operation int, event int, code int) accounthandoff.HandoffDiagnostic {
	return accounthandoff.HandoffDiagnostic{stage, operation, event, code}
}

fn test_handoff_records_follow_real_redemption_and_terminal_result_without_private_data() {
	for operation in [nativeaccountauth.Operation.add_account, .get_auth_token] {
		fd, saved := handoff_capture_start()
		mut fixture := interaction_fixture_for(operation)
		ticket := fixture.offer()
		wrong := fixture.redeem(nativeaccountauth.Caller{...interaction_caller(), pid: 1235}, ticket)
		assert wrong.kind == .failure && fixture.broker.interactions.len() == 1
		accountipc.dispose_event(wrong)
		ack := fixture.redeem(interaction_caller(), ticket)
		assert ack.kind == .result && fixture.broker.active() == 1
		accountipc.dispose_event(ack)
		// Completion still carries the actual result, including private values;
		// only its kind is available to the diagnostic writer.
		fixture.broker.finish(fixture.command.session, accountipc.Event{
			kind: .result
			options: [nativeaccountauth.Option{'authAccount', nativeaccountauth.Scalar{
				kind: .text
				text: 'private-diagnostic-fixture@example.test'
			}}]
		}) or { panic(err) }
		completed := fixture.broker.sessions[fixture.command.session] or { panic('missing completed session') }
		assert completed.terminal
		fixture.close()
		unsafe { ticket.free() }
		records := handoff_capture_end(fd, saved)
		op := int(operation)
		assert records == [
			handoff_record(1, op, 0, 0), handoff_record(2, op, 0, 0),
			handoff_record(3, op, 0, 0), handoff_record(4, op, 0, 0),
			handoff_record(1, 3, 0, 0), handoff_record(9, 3, 2, 7),
			handoff_record(1, 3, 0, 0), handoff_record(5, op, 0, 0),
			handoff_record(8, op, 0, 0), handoff_record(9, 3, 1, 0),
			handoff_record(9, op, 1, 0),
		]
	}
}

fn test_handoff_terminal_error_codes_are_bounded_and_queries_stay_silent() {
	fd, saved := handoff_capture_start()
	for code in [-2147483647, -1, 0, 1, 3, 4, 6, 7, 9, 10, 2147483647] {
		event := accountipc.failure(999999, code, 'private-error-message@example.test')
		assert handoff_error_code(event) == if code >= 1 && code <= 9 { code } else { -1 }
		handoff_terminal(.add_account, event)
		unsafe { event.options.free() }
	}
	for options in [
		[]nativeaccountauth.Option{},
		[nativeaccountauth.Option{'errorCode', nativeaccountauth.Scalar{kind: .text, text: 'private@example.test'}}],
		[nativeaccountauth.Option{'errorCode', nativeaccountauth.Scalar{kind: .int64, number: 6}}],
		[nativeaccountauth.Option{'errorCode', nativeaccountauth.Scalar{kind: .int32, number: 6}},
		 nativeaccountauth.Option{'errorCode', nativeaccountauth.Scalar{kind: .int32, number: 7}}],
	] {
		event := accountipc.Event{kind: .failure, options: options}
		assert handoff_error_code(event) == -1
		handoff_terminal(.get_auth_token, event)
	}
	for operation in [nativeaccountauth.Operation.get_accounts, .invalidate_auth_token, .get_authenticator_types] {
		handoff_stage(.admitted, operation)
		handoff_stage(.dispatch_queued, operation)
		handoff_terminal(operation, accountipc.Event{kind: .result})
	}
	records := handoff_capture_end(fd, saved)
	assert records.len == 15
	for record in records {
		assert record.stage == 9 && record.event == 2
		assert record.operation in [2, 4] && (record.code == -1 || record.code in [1, 3, 4, 6, 7, 9])
	}
}

fn interaction_pair() (int, int) {
	mut fds := [i32(-1), i32(-1)]!
	assert C.socketpair(C.AF_UNIX, C.SOCK_STREAM, 0, &fds[0]) == 0
	return int(fds[0]), int(fds[1])
}

fn interaction_caller() nativeaccountauth.Caller {
	return nativeaccountauth.Caller{'org.vinix.app', 10001, 10001, 1234, 'a'.repeat(64), 'b'.repeat(64)}
}

fn interaction_request(operation nativeaccountauth.Operation) nativeaccountauth.Request {
	bytes := nativeaccountauth.encode_request(nativeaccountauth.Request{
		id:           77
		operation:    operation
		account_name: if operation == .get_auth_token { ?string('account@example.test') } else { none }
		account_type: 'com.google'
		auth_token_type: if operation == .get_auth_token { ?string('oauth2:scope') } else { none }
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
	return interaction_fixture_for(.add_account)
}

fn interaction_fixture_for(operation nativeaccountauth.Operation) &InteractionFixture {
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
		authorized: nativeaccountauth.AuthorizedRequest{interaction_caller(), interaction_request(operation)}
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

fn test_token_interaction_reuses_bound_single_use_launch_without_exposing_service_capability() {
	mut fixture := interaction_fixture_for(.get_auth_token)
	defer { fixture.close() }
	assert fixture.command.request.account_name == ?string('account@example.test')
	assert fixture.command.request.auth_token_type == ?string('oauth2:scope')
	ticket := fixture.offer()
	defer { unsafe { ticket.free() } }
	wrong := fixture.redeem(nativeaccountauth.Caller{...interaction_caller(), pid: 1235}, ticket)
	defer { accountipc.dispose_event(wrong) }
	assert wrong.kind == .failure && fixture.broker.interactions.len() == 1
	ack := fixture.redeem(interaction_caller(), ticket)
	defer { accountipc.dispose_event(ack) }
	assert ack.kind == .result && fixture.broker.active() == 1
	packet := fixture.service.read(0)!
	assert packet.available
	defer { unsafe { packet.body.free() } }
	launch := accountipc.decode_launch(packet.header, packet.body)!
	defer { accountipc.dispose_launch(launch) }
	assert launch.session == fixture.command.session
	assert launch.capability == fixture.command.capability
	assert launch.interaction.handle == []u8{len: 32, init: 8}
	replay := fixture.redeem(interaction_caller(), ticket)
	defer { accountipc.dispose_event(replay) }
	assert replay.kind == .failure && !(fixture.service.read(0)!).available
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
