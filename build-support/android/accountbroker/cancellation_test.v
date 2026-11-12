// SPDX-License-Identifier: GPL-2.0-or-later
module accountbroker

import accountipc
import nativeaccountauth
import time

#include <sys/socket.h>
fn C.socketpair(i32, i32, i32, &i32) i32

fn cancellation_pair() (int, int) {
	mut fds := [i32(-1), i32(-1)]!
	assert C.socketpair(C.AF_UNIX, C.SOCK_STREAM, 0, &fds[0]) == 0
	return int(fds[0]), int(fds[1])
}

fn cancellation_request(id u64) nativeaccountauth.AuthorizedRequest {
	return nativeaccountauth.AuthorizedRequest{
		caller: nativeaccountauth.Caller{'org.vinix.app', 10001, 10001, 1234, 'a'.repeat(64), 'b'.repeat(64)}
		request: nativeaccountauth.Request{id: id, operation: .get_accounts, account_type: 'com.google'}
	}
}

fn test_cancelled_reply_is_discarded_while_an_unrelated_client_continues() ! {
	sfd, speer := cancellation_pair()
	fd, peer := cancellation_pair()
	other_fd, other_peer := cancellation_pair()
	mut service := accountipc.open_stream(speer)!
	mut other := accountipc.open_stream(other_peer)!
	mut broker := Broker{service: accountipc.open_stream(sfd)!, incoming: chan Incoming{cap: 32}, lifetime: -1}
	defer { broker.close(); service.close(); other.close() }
	broker.admit(Incoming{fd: fd, ok: true, authorized: cancellation_request(77)})!
	broker.admit(Incoming{fd: other_fd, ok: true, authorized: cancellation_request(88)})!
	broker.pump(0)!
	first_packet := service.read(0)!
	first := accountipc.decode_command(first_packet.header, first_packet.body)!
	defer { accountipc.dispose_command(first); unsafe { first_packet.body.free() } }
	second_packet := service.read(0)!
	second := accountipc.decode_command(second_packet.header, second_packet.body)!
	defer { accountipc.dispose_command(second); unsafe { second_packet.body.free() } }
	C.close(i32(peer))
	broker.pump(0)!
	assert broker.active() == 1 && !broker.closed
	broker.pump(0)!
	cancel_packet := service.read(0)!
	cancel := accountipc.decode_event(cancel_packet.header, cancel_packet.body, true)!
	defer { accountipc.dispose_event(cancel); unsafe { cancel_packet.body.free() } }
	assert cancel.kind == .cancel && cancel.id == first.session && cancel.capability == first.capability
	wire := accountipc.encode_event(accountipc.Event{kind: .accounts, id: first.session, capability: first.capability,
		accounts: [accountipc.Account{'private-late-result@example.test', 'com.google'}]}, true)!
	defer { unsafe { wire.free() } }
	service.enqueue(wire)!
	service.flush()!
	broker.pump(0)!
	assert !broker.closed && broker.active() == 1
	assert !other.read(0)!.available
	response := accountipc.encode_event(accountipc.Event{kind: .accounts, id: second.session, capability: second.capability}, true)!
	defer { unsafe { response.free() } }
	service.enqueue(response)!
	service.flush()!
	broker.pump(0)!
	packet := other.read(0)!
	result := accountipc.decode_event(packet.header, packet.body, false)!
	defer { accountipc.dispose_event(result); unsafe { packet.body.free() } }
	assert result.kind == .accounts && result.id == 88 && result.accounts.len == 0
	assert broker.active() == 0 && broker.sessions.len == 0
}

fn test_cancellation_ack_releases_slot_and_wrong_capability_still_closes_service() ! {
	for forged in [false, true] {
		sfd, speer := cancellation_pair()
		fd, peer := cancellation_pair()
		mut service := accountipc.open_stream(speer)!
		mut broker := Broker{service: accountipc.open_stream(sfd)!, incoming: chan Incoming{cap: 32}, lifetime: -1}
		defer { broker.close(); service.close() }
		broker.admit(Incoming{fd: fd, ok: true, authorized: cancellation_request(77)})!
		broker.pump(0)!
		packet := service.read(0)!
		command := accountipc.decode_command(packet.header, packet.body)!
		defer { accountipc.dispose_command(command); unsafe { packet.body.free() } }
		C.close(i32(peer))
		broker.pump(0)!
		assert broker.active() == 0 && broker.sessions.len == 1
		mut capability := command.capability.clone()
		defer { unsafe { capability.free() } }
		if forged { capability[0] ^= 1 }
		ack := accountipc.failure(command.session, 4, 'Account request cancelled')
		defer { unsafe { ack.options.free() } }
		wire := accountipc.encode_event(accountipc.Event{...ack, capability: capability}, true)!
		defer { unsafe { wire.free() } }
		service.enqueue(wire)!
		service.flush()!
		mut rejected := false
		broker.pump(0) or { rejected = true }
		assert rejected == forged && broker.closed == forged
		assert broker.sessions.len == 0
	}
}

fn test_cancelled_slots_keep_the_existing_admission_bound_and_expire() ! {
	mut broker := Broker{incoming: chan Incoming{cap: 32}, lifetime: -1}
	defer { broker.close() }
	for index in 1 .. accountipc.max_sessions + 1 {
		broker.sessions[u64(index)] = Session{capability: []u8{len: 32, init: u8(index)},
			deadline: time.sys_mono_now() - 11 * time.second, cancelled: true, draining: true}
	}
	assert broker.active() == 0
	fd, peer := cancellation_pair()
	defer { C.close(i32(fd)); C.close(i32(peer)) }
	mut rejected := false
	broker.accept_client(fd) or { rejected = true }
	assert rejected
	broker.pump(0)!
	assert broker.sessions.len == 0 && !broker.closed
}

fn test_ack_does_not_replace_the_queued_client_failure_or_allow_replay() ! {
	sfd, speer := cancellation_pair()
	fd, peer := cancellation_pair()
	mut service := accountipc.open_stream(speer)!
	mut client := accountipc.open_stream(peer)!
	mut broker := Broker{service: accountipc.open_stream(sfd)!, incoming: chan Incoming{cap: 32}, lifetime: -1}
	defer { broker.close(); service.close(); client.close() }
	broker.admit(Incoming{fd: fd, ok: true, authorized: cancellation_request(77)})!
	broker.pump(0)!
	packet := service.read(0)!
	command := accountipc.decode_command(packet.header, packet.body)!
	defer { accountipc.dispose_command(command); unsafe { packet.body.free() } }
	broker.cancel_service(command.session)
	broker.fail(command.session, 4, 'Account request timed out')!
	ack := accountipc.failure(command.session, 4, 'Account request cancelled')
	defer { unsafe { ack.options.free() } }
	wire := accountipc.encode_event(accountipc.Event{...ack, capability: command.capability}, true)!
	defer { unsafe { wire.free() } }
	callback := accountipc.Packet{true, accountipc.decode_header(wire[..accountipc.header_size])!, wire[accountipc.header_size..]}
	broker.callback(callback)!
	mut rejected := false
	broker.callback(callback) or { rejected = true }
	assert rejected
	broker.pump(0)!
	returned := client.read(0)!
	result := accountipc.decode_event(returned.header, returned.body, false)!
	defer { accountipc.dispose_event(result); unsafe { returned.body.free() } }
	assert result.kind == .failure && result.id == 77 && result.capability.len == 0
	assert result.options == accountipc.failure(77, 4, 'Account request timed out').options
	assert broker.active() == 0 && broker.sessions.len == 0
}
