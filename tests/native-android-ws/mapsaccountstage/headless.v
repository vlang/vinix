// SPDX-License-Identifier: GPL-2.0-or-later
module mapsaccountstage

import json2

pub const headless_guest_sha256 = 'd518cfc5145924479b5ad630aac2a3d3ef7dcea66f53515c03df03735e88ce05'
pub const headless_fixture_sha256 = '4df9e3cd757b463259c73dc038eb84d149d7ec1461a1889bc8f2d531f6980634'
pub const headless_guest_source_sha256 = '7e25b7643ac71502e8b3fefd982113390605de700a5d4e35e4f506264ea63610'

const headless_prefix = '/opt/vinix-headless-service/'
const headless_runtime = '/opt/vinix-android-aarch64/'

fn headless_baseline_inputs() map[string]string {
	return {
		headless_runtime + 'usr/bin/run-android': '7f2778c013203581cccd7fd9b5aabf59607d0580c39a3b63876fb3a5926133e1'
		headless_runtime + 'usr/bin/vinix-android-native': 'f8b55b3aacadd45168b13e18fb91b9a58a56da1a73a1749ab0f9873f9c2fdb65'
		headless_runtime + 'usr/lib/art/libvinix-android-native.so': '66ad7731707c9eeb4639d75838a002a680180e19f75aa13ccb75bbe23ef1d371'
		headless_runtime + 'usr/lib/java/dex/android_translation_layer/api-impl.jar': '86278c9cbe1f25904b760250f34f859206d719cbb23cf5ff5411a75c480ac36f'
		headless_prefix + 'bin/headless-service-controller': 'eb30bb51147019c5b77d7a7a7029958efe922fd7a1cef24692d22916d59a0d75'
		headless_prefix + 'bin/headless-service-guest': headless_guest_sha256
		headless_prefix + 'fixture.apk': headless_fixture_sha256
	}
}

// Regenerate the existing guest's seven-path contract for a new runtime. The
// stager separately verifies each source artifact and its deployment readback.
// The synthetic APK and guest stay byte-identical to the unbooted r4 baseline;
// this lifecycle probe supplies no account or Google authentication evidence.
pub fn repin_headless_inputs(original string, replacements map[string]string) !string {
	if original.len > 16384 { return error('headless input receipt exceeds bound') }
	outer := json2.decode[map[string]json2.Any](original)!
	if outer.len != 1 || 'inputs_sha256' !in outer {
		return error('headless input receipt must contain only inputs_sha256')
	}
	value := outer['inputs_sha256']!
	if value !is map[string]json2.Any { return error('headless input pins must be an object') }
	mut previous := map[string]string{}
	for path, field in value {
		if field !is string { return error('headless input pin must be a string') }
		previous[path] = field
	}
	if previous != headless_baseline_inputs() {
		return error('headless input pins differ from the exact unbooted r4 baseline')
	}
	if replacements.len != 5 { return error('exactly five runtime/controller replacement pins required') }
	mut updated := previous.clone()
	for path, pin in replacements {
		if path !in previous || path in [headless_prefix + 'bin/headless-service-guest',
			headless_prefix + 'fixture.apk'] {
			return error('headless replacement path is not a runtime/controller input: ' + path)
		}
		if pin.len != 64 || !pin.bytes().all((it >= `0` && it <= `9`) || (it >= `a` && it <= `f`)) {
			return error('headless replacement pin must be lowercase SHA-256: ' + path)
		}
		updated[path] = pin
	}
	return json2.encode({'inputs_sha256': updated}, prettify: true) + '\n'
}
