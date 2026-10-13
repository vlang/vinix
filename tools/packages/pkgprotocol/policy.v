// SPDX-License-Identifier: GPL-2.0-or-later
// SDK 1 policy presentation. No configuration writes or privileged operations.
module pkgprotocol

pub struct PolicyPin {
pub:
	id      string
	minimum string
	before  string
}

pub struct PolicySettings {
pub:
	offline        bool
	allowed        []string
	pins           []PolicyPin
	permissions    []string
	licenses       []string
	allow_firmware bool
	reserve_bytes  u64
}

pub struct PolicyDocument {
pub:
	format       int
	architecture string
	policy       PolicySettings
}

pub struct PolicyImpact {
pub:
	id                string
	name              string
	version           string
	kind              string
	license           string
	proprietary       bool
	firmware          bool
	repository        string
	public_key        string
	requested         bool
	diagnostic_before string
	diagnostic_after  string
}

pub struct PolicyReview {
pub:
	format       int
	architecture string
	generation   u64
	fingerprint  string
	previous     PolicySettings
	proposed     PolicySettings
	rows         []PolicyImpact
}

fn policy_sorted_strings(values []string, kind int) ! {
	mut previous := ''
	for value in values {
		if value == '' || !printable(value, 256) || value <= previous
			|| (kind == 0 && !identifier(value))
			|| (kind == 1 && value !in ['audio', 'display', 'files', 'network', 'process']!) {
			return error('invalid, duplicate or noncanonical policy entry')
		}
		previous = value
	}
}

// Version components follow the package contract: three canonical decimal
// components, at most nine digits each. Compare without allocating substrings.
fn policy_version_components(text string) [3]u32 {
	mut parts := [3]u32{}
	mut index := 0
	for byte in text {
		if byte == `.` { index++ } else { parts[index] = parts[index] * 10 + u32(byte - `0`) }
	}
	return parts
}

fn policy_range_valid(minimum string, before string) bool {
	if (minimum != '' && !version(minimum)) || (before != '' && !version(before)) { return false }
	if minimum == '' || before == '' { return true }
	left := policy_version_components(minimum)
	right := policy_version_components(before)
	for index in 0 .. 3 {
		if left[index] != right[index] { return left[index] < right[index] }
	}
	return false
}

pub fn (policy &PolicySettings) validate() ! {
	if policy.allowed.len > 4096 || policy.pins.len > 4096 || policy.licenses.len > 4096
		|| policy.permissions.len > 5 || policy.reserve_bytes > u64(1) << 40 {
		return error('policy presentation exceeds supported bounds')
	}
	policy_sorted_strings(policy.allowed, 0)!
	policy_sorted_strings(policy.permissions, 1)!
	policy_sorted_strings(policy.licenses, 2)!
	mut previous := ''
	for pin in policy.pins {
		if !identifier(pin.id) || pin.id <= previous || !policy_range_valid(pin.minimum, pin.before) {
			return error('invalid, duplicate or noncanonical policy pin')
		}
		previous = pin.id
	}
}

pub fn (document &PolicyDocument) validate() ! {
	if document.format != 1 || document.architecture !in ['aarch64', 'x86_64']! { return error('unsupported policy document') }
	document.policy.validate()!
}

pub fn (review &PolicyReview) validate() ! {
	if review.format != 1 || review.architecture !in ['aarch64', 'x86_64']! || !digest(review.fingerprint)
		|| review.rows.len > 4096 || (review.generation == 0 && review.rows.len != 0) { return error('unsupported policy review') }
	review.previous.validate()!
	review.proposed.validate()!
	mut previous := ''
	for row in review.rows {
		if !identifier(row.id) || row.id <= previous || row.name == '' || !printable(row.name, 256)
			|| !version(row.version) || row.kind !in ['native', 'linux', 'windows', 'apple', 'runtime', 'data']!
			|| row.license == '' || !printable(row.license, 256) || !identifier(row.repository)
			|| !digest(row.public_key) || !printable(row.diagnostic_before, 4096) || !printable(row.diagnostic_after, 4096) {
			return error('invalid installed package in policy review')
		}
		previous = row.id
	}
}

pub fn (mut policy PolicySettings) close() {
	unsafe {
		for value in policy.allowed { value.free() }; (&array(&policy.allowed)).free()
		for value in policy.permissions { value.free() }; (&array(&policy.permissions)).free()
		for value in policy.licenses { value.free() }; (&array(&policy.licenses)).free()
		for pin in policy.pins { pin.id.free(); pin.minimum.free(); pin.before.free() }
		(&array(&policy.pins)).free()
	}
	policy = PolicySettings{}
}

pub fn (mut document PolicyDocument) close() {
	unsafe { document.architecture.free() }
	document.policy.close()
	document = PolicyDocument{}
}

fn close_policy_impacts(rows []PolicyImpact) {
	unsafe {
		for row in rows {
			row.id.free(); row.name.free(); row.version.free(); row.kind.free(); row.license.free()
			row.repository.free(); row.public_key.free(); row.diagnostic_before.free(); row.diagnostic_after.free()
		}
		(&array(&rows)).free()
	}
}

pub fn (mut review PolicyReview) close() {
	unsafe { review.architecture.free(); review.fingerprint.free() }
	review.previous.close(); review.proposed.close()
	close_policy_impacts(review.rows)
	review = PolicyReview{}
}
