import os
import json2
import crypto.sha256
import compress.gzip

const base = 'build/android-maps/'
const dest = 'tests/android/results/2026-10-23/maps-ws/'
const run = base + 'attempt223/'

fn hash(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }

fn without_badging(value json2.Any) json2.Any {
	if value is map[string]json2.Any {
		mut result := map[string]json2.Any{}
		for key, item in value { if key != 'badging' { result[key] = without_badging(item) } }
		return result
	}
	if value is []json2.Any {
		mut result := []json2.Any{}
		for item in value { result << without_badging(item) }
		return result
	}
	return value
}

fn main() {
	raw := os.read_file(run + 'results.json')!
	mut row := without_badging(json2.decode[[]json2.Any](raw)![0]).as_map()
	serial := gzip.decompress(os.read_bytes(run + 'google-maps/serial.log.gz')!)!
	assert sha256.sum(serial).hex() == row['serial_sha256']!.str()
	log := serial.bytestr()
	assert row['outcome']!.str() == 'startup_failed' && row['backend_ready']!.bool()
	assert log.contains('java.lang.UnsupportedOperationException: Native WS bitmap storage requires ARGB_8888')
	assert log.contains('APK-SUITE-EXIT id=google-maps code=1 native_observed=true gtk_x11_absent=true')
	assert !os.exists(run + 'google-maps/skip-later.png')
	mut artifacts := map[string]json2.Any{}
	for source, name in {
		run + 'google-maps/serial.log.gz': 'attempt223-google-maps-serial.log.gz'
		run + 'google-maps/initial.png': 'attempt223-google-maps-initial.png'
		run + 'google-maps/skip.png': 'attempt223-google-maps-skip.png'
		run + 'google-maps/application.png': 'attempt223-google-maps-application.png'
		base + 'attempt223.json': 'attempt223-configuration.json'
		base + 'attempt223-harness.log': 'attempt223-harness.log'
		base + 'interact223.log': 'attempt223-interaction.log'
		base + 'interact223.v': 'attempt223-interaction.v'
		base + 'run223.v': 'attempt223-run.v'
		base + 'prepare223.v': 'attempt223-prepare.v'
		base + 'retain223.v': 'retain223.v'
	} {
		if name.ends_with('.smali.gz') {
			os.write_file_array(dest + name, gzip.compress(os.read_bytes(source)!)!)!
		} else { os.cp(source, dest + name)! }
		artifacts[name] = hash(dest + name)!
	}
	prior := json2.decode[map[string]json2.Any](os.read_file(dest + 'attempt218-runtime-identities.json')!)!
	inputs := prior['input_files_sha256']!.as_map()
	assert row['metadata']!.as_map()['apk_sha256']!.str() == inputs[base + 'GoogleMaps.apk']!.str()
	for entry in row['companion_packages']!.as_array() {
		companion := entry.as_map()
		assert companion['metadata']!.as_map()['apk_sha256']!.str() == inputs[companion['apk']!.str()]!.str()
	}
	row['run'] = 'attempt223'
	row['startup_ui_passed'] = false
	row['search_passed'] = false
	row['manual_review'] = 'Initial screenshot shows onboarding; Skip/final screenshots show APK exited. Rendering fails with UnsupportedOperationException: Native WS bitmap storage requires ARGB_8888 in Bitmap.getSnapshot through Canvas construction, and APK exits1. Input uses settle=0.15 seconds before down, between down/up, and after up, then an explicit10-second wait. Later screenshot was not captured because QEMU closed. Map/search unverified.'
	row['screenshot'] = 'attempt223-google-maps-application.png'
	row['serial_log'] = 'attempt223-google-maps-serial.log.gz'
	row['initial_screenshot'] = 'attempt223-google-maps-initial.png'
	row['skip_screenshot'] = 'attempt223-google-maps-skip.png'
	row['badging_omission'] = 'Only metadata badging strings recursively omitted; remaining result fields retained.'
	os.write_file(dest + 'attempt223-results.json', json2.encode([json2.Any(row)], prettify: true) + '\n')!
	artifacts['attempt223-results.json'] = hash(dest + 'attempt223-results.json')!
	receipt := {
		'artifacts_sha256': json2.Any(artifacts)
		'original_results_sha256': json2.Any(sha256.sum(raw.bytes()).hex())
		'input_identity_receipt': json2.Any('attempt223-input-identities.json')
		'input_identity_receipt_sha256': json2.Any(hash(dest + 'attempt223-input-identities.json')!)
		'shared_input_identity_receipt': json2.Any('attempt218-runtime-identities.json')
		'input_scope': json2.Any('Signed Maps/GMS/Store APK identities verified from result metadata against attempt218 inputs; staged runtime hashes and source identity limitations are retained separately in attempt223-input-identities.json. Kernel/base receipts remain inherited, not measured for attempt223.')
		'interaction_limit': json2.Any('Input223 uses --settle0.15 before down, between down/up, and after up, then an explicit10-second wait. Initial capture shows onboarding; Skip capture shows APK exited. No later screenshot223:interactor fails after QEMU closes.')
		'functional_outcome': json2.Any('FAILED: render path throws UnsupportedOperationException Native WS bitmap storage requires ARGB_8888; APK exit1, harnessstartup_failed. Initial screenshot shows onboarding; Skip/final show APK exited. Map/search unverified.')
	}
	os.write_file(dest + 'attempt223-runtime-identities.json', json2.encode(receipt, prettify: true) + '\n')!
	println('ATTEMPT223-RETENTION PASS serial/result/APK identities,3 screenshots, input source receipts retained; functional outcome FAILED unsupported bitmap configuration, APKexit1; no later screenshot')
}
