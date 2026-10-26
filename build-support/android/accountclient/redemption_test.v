// SPDX-License-Identifier: GPL-2.0-or-later
module accountclient

import nativeaccountauth
import accountipc
import net.unix
import os

fn test_redemption_client_owns_encoded_ticket_and_fresh_connection() {
	path := os.join_path(os.temp_dir(), 'vinix-account-redeem-${os.getpid()}.sock')
	mut listener := unix.listen_stream(path)!
	defer {
		listener.close() or {}
		os.rm(path) or {}
	}
	mut ticket := []u8{len: 32, init: u8(index + 1)}
	mut first := redeem(91, 17, ticket, path)!
	defer { first.close() }
	mut second := redeem(92, 17, ticket, path)!
	defer { second.close() }
	assert first.fd != second.fd
	ticket[0] = 255
	request := nativeaccountauth.decode_request_bytes(first.request)!
	defer { nativeaccountauth.dispose_request(request) }
	assert request.id == 91 && request.operation == .redeem_interaction
	value := request.redemption or { panic('missing ticket') }
	assert value.request == 17 && value.capability[0] == 1
	assert !first.verified && first.used == 0
	// Identity verification remains in pump_request, before any request byte.
}

fn test_redemption_abi_rejects_invalid_tickets_and_identifiers_before_connect() {
	path := os.join_path(os.temp_dir(), 'vinix-account-redeem-invalid-${os.getpid()}.sock')
	mut listener := unix.listen_stream(path)!
	defer {
		listener.close() or {}
		os.rm(path) or {}
	}
	ticket := []u8{len: 32, init: 1}
	assert abi_redeem(1, 2, unsafe { nil }, 32, path.str) == unsafe { nil }
	for length in [u32(0), 31, 33, 0xffffffff] {
		assert abi_redeem(1, 2, ticket.data, length, path.str) == unsafe { nil }
	}
	assert abi_redeem(0, 2, ticket.data, 32, path.str) == unsafe { nil }
	assert abi_redeem(1, 0, ticket.data, 32, path.str) == unsafe { nil }
	assert abi_redeem(1, 2, ticket.data, 32, unsafe { nil }) == unsafe { nil }
	assert abi_redeem(1, 2, ticket.data, 32, c'relative') == unsafe { nil }
	zero := []u8{len: 32}
	assert abi_redeem(1, 2, zero.data, 32, path.str) == unsafe { nil }
	mut ready := ClientPoll{fd: i32(listener.sock.handle), events: i16(C.POLLIN)}
	assert C.poll(voidptr(&ready), 1, 0) == 0
}

fn test_interaction_abi_copies_only_the_public_current_ticket() {
	ticket := []u8{len: 32, init: u8(index + 1)}
	mut client := Client{
		current: accountipc.Event{
			kind: .interaction
			id: 17
			interaction: accountipc.Interaction{handle: ticket}
		}
	}
	mut output := [32]u8{}
	assert abi_interaction(&client, &output[0], 32) == 0
	assert output[0] == 1 && output[31] == 32
	// The consumer owns its copy across the next read/disposal of current.
	client.current = accountipc.Event{}
	assert output[0] == 1 && output[31] == 32
	assert abi_interaction(&client, &output[0], 32) == -1
	client.current = accountipc.Event{kind: .result}
	assert abi_interaction(&client, &output[0], 32) == -1
	client.current = accountipc.Event{kind: .interaction, interaction: accountipc.Interaction{handle: ticket[..31]}}
	assert abi_interaction(&client, &output[0], 32) == -1
	client.current = accountipc.Event{kind: .interaction, interaction: accountipc.Interaction{handle: ticket}}
	assert abi_interaction(unsafe { nil }, &output[0], 32) == -1
	assert abi_interaction(&client, unsafe { nil }, 32) == -1
	for length in [u32(0), 31, 33, 0xffffffff] {
		assert abi_interaction(&client, &output[0], length) == -1
	}
}
