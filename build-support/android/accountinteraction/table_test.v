// SPDX-License-Identifier: GPL-2.0-or-later
module accountinteraction

import nativeaccountauth
import time

fn origin() nativeaccountauth.Caller {
	return nativeaccountauth.Caller{'com.google.android.gms', 10002, 10002, 9876, 'a'.repeat(64), 'b'.repeat(64)}
}

fn caller() nativeaccountauth.Caller {
	return nativeaccountauth.Caller{'com.google.android.apps.maps', 10003, 10003, 7654, 'c'.repeat(64), 'd'.repeat(64)}
}

fn target() Target {
	return Target{'com.google.android.gms', 'com.google.android.gms.auth.AccountIntroActivity'}
}

fn fixture() Offer {
	return Offer{
		origin:              origin()
		caller:              caller()
		session:             12
		request:             77
		response_capability: []u8{len: 32, init: u8(0xa1)}
		local_handle:        []u8{len: 32, init: u8(0xb2)}
		target:              target()
		deadline:            1000
	}
}

fn reject_offer(mut table Table, offer Offer, now i64) {
	ticket := table.offer_at(offer, now) or { return }
	unsafe { ticket.free() }
	assert false, 'invalid offer accepted'
}

fn reject_redemption(mut table Table, identity nativeaccountauth.Caller, request u64, ticket []u8, now i64) {
	mut launch := table.redeem_at(identity, request, ticket, now) or { return }
	launch.dispose()
	assert false, 'invalid redemption accepted'
}

fn reject_configuration(identity nativeaccountauth.Caller, targets []Target) {
	mut table := create(identity, targets) or { return }
	table.close()
	assert false, 'invalid origin or allowlist accepted'
}

fn test_exactly_once_launch_preserves_owned_response_handle_and_target() {
	mut selected := [target()]
	mut table := create(origin(), selected) or { panic(err) }
	defer { table.close() }
	selected[0] = Target{'com.google.android.gms', 'com.google.android.gms.OtherActivity'}
	mut response := fixture().response_capability.clone()
	mut handle := fixture().local_handle.clone()
	offer := Offer{ ...fixture(), response_capability: response, local_handle: handle }
	mut ticket := table.offer_at(offer, 100) or { panic(err) }
	saved_ticket := ticket.clone()
	assert ticket.len == 32
	assert ticket != response
	assert ticket != handle
	assert table.len() == 1
	// The broker owns copies, including the public ticket retained for lookup.
	response[0] ^= 1
	handle[0] ^= 1
	ticket[0] ^= 1
	reject_redemption(mut table, caller(), 77, ticket, 101)
	assert table.len() == 1
	mut launch := table.redeem_at(caller(), 77, saved_ticket, 102) or { panic(err) }
	assert table.len() == 0
	table.close()
	assert launch.session == 12
	assert launch.request == 77
	assert launch.response_capability == fixture().response_capability
	assert launch.local_handle == fixture().local_handle
	assert launch.target == target()
	launch.dispose()
	launch.dispose()
	reject_redemption(mut table, caller(), 77, saved_ticket, 103)
}

fn test_forgery_and_all_caller_identity_fields_leave_original_ticket_live() {
	mut table := create(origin(), [target()]) or { panic(err) }
	defer { table.close() }
	ticket := table.offer_at(fixture(), 100) or { panic(err) }
	for wrong in [
		nativeaccountauth.Caller{ ...caller(), package_name: 'org.vinix.other' },
		nativeaccountauth.Caller{ ...caller(), uid: 10004 },
		nativeaccountauth.Caller{ ...caller(), gid: 10004 },
		nativeaccountauth.Caller{ ...caller(), pid: 7655 },
		nativeaccountauth.Caller{ ...caller(), apk_sha256: 'e'.repeat(64) },
		nativeaccountauth.Caller{ ...caller(), certificate_sha256: 'f'.repeat(64) },
	] {
		reject_redemption(mut table, wrong, 77, ticket, 101)
		assert table.len() == 1
	}
	reject_redemption(mut table, caller(), 78, ticket, 101)
	reject_redemption(mut table, caller(), 0, ticket, 101)
	reject_redemption(mut table, caller(), 77, fixture().response_capability, 101)
	reject_redemption(mut table, caller(), 77, fixture().local_handle, 101)
	reject_redemption(mut table, caller(), 77, []u8{len: 32}, 101)
	reject_redemption(mut table, caller(), 77, ticket[..31], 101)
	mut forged := ticket.clone()
	forged[31] ^= 1
	reject_redemption(mut table, caller(), 77, forged, 101)
	assert table.len() == 1
	mut launch := table.redeem_at(caller(), 77, ticket, 102) or { panic(err) }
	launch.dispose()
	reject_redemption(mut table, caller(), 77, ticket, 103)
	assert table.len() == 0
}

fn test_offers_require_selected_origin_exact_target_and_bounded_valid_fields() {
	mut table := create(origin(), [target()]) or { panic(err) }
	defer { table.close() }
	for wrong in [
		nativeaccountauth.Caller{ ...origin(), package_name: 'org.vinix.other' },
		nativeaccountauth.Caller{ ...origin(), uid: 10004 },
		nativeaccountauth.Caller{ ...origin(), gid: 10004 },
		nativeaccountauth.Caller{ ...origin(), pid: 9877 },
		nativeaccountauth.Caller{ ...origin(), apk_sha256: 'e'.repeat(64) },
		nativeaccountauth.Caller{ ...origin(), certificate_sha256: 'f'.repeat(64) },
	] {
		reject_offer(mut table, Offer{ ...fixture(), origin: wrong }, 100)
	}
	for invalid in [
		Offer{ ...fixture(), caller: nativeaccountauth.Caller{ ...caller(), pid: 0 } },
		Offer{ ...fixture(), caller: nativeaccountauth.Caller{ ...caller(), apk_sha256: 'bad' } },
		Offer{ ...fixture(), session: 0 },
		Offer{ ...fixture(), request: 0 },
		Offer{ ...fixture(), response_capability: []u8{len: 31, init: u8(1)} },
		Offer{ ...fixture(), response_capability: []u8{len: 32} },
		Offer{ ...fixture(), local_handle: []u8{len: 33, init: u8(1)} },
		Offer{ ...fixture(), local_handle: []u8{len: 32} },
		Offer{ ...fixture(), local_handle: fixture().response_capability },
		Offer{ ...fixture(), target: Target{'org.vinix.other', target().class_name} },
		Offer{ ...fixture(), target: Target{'com.google.android.gms', 'com.google.android.gms.OtherActivity'} },
		Offer{ ...fixture(), deadline: 100 },
		Offer{ ...fixture(), deadline: 99 },
		Offer{ ...fixture(), deadline: 100 + 5 * time.minute + 1 },
	] {
		reject_offer(mut table, invalid, 100)
		assert table.len() == 0
	}
	reject_offer(mut table, fixture(), -1)
	ticket := table.offer_at(Offer{ ...fixture(), deadline: 100 + 5 * time.minute }, 100) or { panic(err) }
	reject_offer(mut table, fixture(), 101)
	assert table.len() == 1
	mut launch := table.redeem_at(caller(), 77, ticket, 102) or { panic(err) }
	launch.dispose()
}

fn test_new_offer_cannot_reuse_an_existing_public_ticket_as_an_internal_secret() {
	mut table := create(origin(), [target()]) or { panic(err) }
	defer { table.close() }
	ticket := table.offer_at(fixture(), 100) or { panic(err) }
	reject_offer(mut table, Offer{ ...fixture(), session: 13, local_handle: ticket }, 101)
	reject_offer(mut table, Offer{ ...fixture(), session: 13, response_capability: ticket }, 101)
	assert table.len() == 1
	mut launch := table.redeem_at(caller(), 77, ticket, 102) or { panic(err) }
	launch.dispose()
}

fn test_allowlist_validation_and_size_bound() {
	reject_configuration(nativeaccountauth.Caller{ ...origin(), uid: 0 }, [target()])
	reject_configuration(nativeaccountauth.Caller{ ...origin(), gid: 20000 }, [target()])
	reject_configuration(nativeaccountauth.Caller{ ...origin(), pid: -1 }, [target()])
	reject_configuration(nativeaccountauth.Caller{ ...origin(), package_name: 'bad..package' }, [target()])
	reject_configuration(nativeaccountauth.Caller{ ...origin(), certificate_sha256: 'A'.repeat(64) }, [target()])
	reject_configuration(origin(), []Target{})
	reject_configuration(origin(), [target(), target()])
	for class_name in ['', 'SingleClass', '.leading', 'trailing.', 'a..b', 'a.1Class', 'a.b/c',
		'a.b\x00c', 'a.' + 'b'.repeat(254)] {
		reject_configuration(origin(), [Target{'com.google.android.gms', class_name}])
	}
	reject_configuration(origin(), [Target{'org.vinix.other', target().class_name}])
	mut targets := []Target{cap: 257}
	for index in 0 .. 256 {
		targets << Target{'com.google.android.gms', 'a.b.Activity${index}'}
	}
	mut table := create(origin(), targets) or { panic(err) }
	table.close()
	targets << Target{'com.google.android.gms', 'a.b.Activity256'}
	reject_configuration(origin(), targets)
	mut nested := create(origin(), [Target{'com.google.android.gms', 'a.b.Activity$Nested'}]) or { panic(err) }
	nested.close()
}

fn test_capacity_expiry_revocation_and_close_release_records() {
	mut table := create(origin(), [target()]) or { panic(err) }
	defer { table.close() }
	mut tickets := [][]u8{cap: 32}
	for session in 1 .. 33 {
		ticket := table.offer_at(Offer{ ...fixture(), session: u64(session) }, 100) or { panic(err) }
		for previous in tickets {
			assert previous != ticket
		}
		tickets << ticket
	}
	assert table.len() == 32
	reject_offer(mut table, Offer{ ...fixture(), session: 33 }, 100)
	table.revoke(1)
	table.revoke(1)
	table.revoke(999)
	reject_redemption(mut table, caller(), 77, tickets[0], 101)
	assert table.len() == 31
	ticket33 := table.offer_at(Offer{ ...fixture(), session: 33 }, 101) or { panic(err) }
	table.expire_at(999)
	assert table.len() == 32
	table.expire_at(1000)
	assert table.len() == 0
	reject_redemption(mut table, caller(), 77, ticket33, 1000)
	// offer expires old records before checking capacity; no explicit sweep needed.
	for session in 1 .. 33 {
		table.offer_at(Offer{ ...fixture(), session: u64(session), deadline: 2000 }, 1000) or { panic(err) }
	}
	ticket := table.offer_at(Offer{ ...fixture(), session: 33, deadline: 3000 }, 2000) or { panic(err) }
	assert table.len() == 1
	table.close()
	table.close()
	table.expire()
	table.revoke(33)
	assert table.len() == 0
	reject_redemption(mut table, caller(), 77, ticket, 2001)
	reject_offer(mut table, Offer{ ...fixture(), deadline: 3000 }, 2001)
}

fn test_public_methods_use_absolute_monotonic_deadlines() {
	mut table := create(origin(), [target()]) or { panic(err) }
	defer { table.close() }
	ticket := table.offer(Offer{ ...fixture(), deadline: time.sys_mono_now() + time.second }) or { panic(err) }
	mut launch := table.redeem(caller(), 77, ticket) or { panic(err) }
	launch.dispose()
	assert table.len() == 0
}
