// SPDX-License-Identifier: GPL-2.0-or-later
module sessioncore

fn test_policy_validation_and_roundtrip() {
	mut p := Policy{}
	p.bind('\x1b[110;9u', 'shell') or { assert false }
	p.corners[0] = text('overview') or { panic(err) }
	p.timezone_minutes = 180
	assert decode_policy(p.encode()) or { Policy{} } == p
	if _ := p.bind('\x1b[110;9u', 'help') {
		assert false
	}
	if _ := decode_policy('vinix-shell-policy\t1\t1\t1\t1\t1\t9999\n') {
		assert false
	}
}
