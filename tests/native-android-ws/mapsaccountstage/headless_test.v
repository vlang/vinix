// SPDX-License-Identifier: GPL-2.0-or-later
module mapsaccountstage

import json2

fn headless_replacements() map[string]string {
	mut result := headless_baseline_inputs()
	result.delete(headless_prefix + 'bin/headless-service-guest')
	result.delete(headless_prefix + 'fixture.apk')
	for path, _ in result { result[path] = 'a'.repeat(64) }
	return result
}

fn test_headless_repin_preserves_fixture_and_guest() ! {
	previous := headless_baseline_inputs()
	input := json2.encode({'inputs_sha256': previous})
	replacements := headless_replacements()
	output := repin_headless_inputs(input, replacements)!
	decoded := json2.decode[map[string]map[string]string](output)!
	assert decoded.len == 1
	updated := decoded['inputs_sha256']!.clone()
	assert updated.len == 7
	assert updated[headless_prefix + 'fixture.apk']! == headless_fixture_sha256
	assert updated[headless_prefix + 'bin/headless-service-guest']! == headless_guest_sha256
	for path, pin in replacements { assert updated[path]! == pin }
	assert json2.decode[map[string]map[string]string](input)!['inputs_sha256']! == previous
}

fn test_headless_repin_rejects_changed_baseline_or_schema() ! {
	replacements := headless_replacements()
	for path, _ in headless_baseline_inputs() {
		mut changed := headless_baseline_inputs()
		changed[path] = 'b'.repeat(64)
		if _ := repin_headless_inputs(json2.encode({'inputs_sha256': changed}), replacements) {
			assert false, 'changed baseline input accepted: ' + path
		}
	}
	for original in ['{}', '[]', '{"inputs_sha256":7}', '{"inputs_sha256":{}}',
		'{"inputs_sha256":{"path":7}}',
		json2.encode({'inputs_sha256': headless_baseline_inputs(), 'unexpected': map[string]string{}}),
		' '.repeat(16385)] {
		if _ := repin_headless_inputs(original, replacements) {
			assert false, 'malformed baseline receipt accepted'
		}
	}
}

fn test_headless_repin_rejects_missing_extra_and_immutable_replacements() ! {
	original := json2.encode({'inputs_sha256': headless_baseline_inputs()})
	mut changed := headless_replacements()
	changed.delete(headless_runtime + 'usr/bin/run-android')
	if _ := repin_headless_inputs(original, changed) { assert false, 'missing replacement accepted' }
	for path in ['/tmp/foreign', headless_prefix + 'fixture.apk',
		headless_prefix + 'bin/headless-service-guest'] {
		mut invalid := changed.clone()
		invalid[path] = 'a'.repeat(64)
		if _ := repin_headless_inputs(original, invalid) { assert false, 'foreign/immutable replacement accepted' }
	}
	changed = headless_replacements()
	changed['/tmp/extra'] = 'a'.repeat(64)
	if _ := repin_headless_inputs(original, changed) { assert false, 'extra replacement accepted' }
	for pin in ['', 'a'.repeat(63), 'a'.repeat(65), 'A'.repeat(64), 'g'.repeat(64)] {
		mut invalid := headless_replacements()
		invalid[headless_runtime + 'usr/bin/run-android'] = pin
		if _ := repin_headless_inputs(original, invalid) { assert false, 'invalid replacement SHA-256 accepted' }
	}
}
