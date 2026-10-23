import os
import json2
import crypto.sha256
import compress.gzip

const base = 'build/android-maps/'
const dest = 'tests/android/results/2026-10-23/maps-ws/'
const run = base + 'attempt222/'

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
	assert log.contains('No virtual method notifyViewVisibilityChanged(Landroid/view/View;IZ)V')
	assert log.contains('APK-SUITE-EXIT id=google-maps code=10 native_observed=true gtk_x11_absent=true')
	assert !os.exists(run + 'google-maps/skip-later.png')
	mut artifacts := map[string]json2.Any{}
	for source, name in {
		run + 'google-maps/serial.log.gz': 'attempt222-google-maps-serial.log.gz'
		run + 'google-maps/initial.png': 'attempt222-google-maps-initial.png'
		run + 'google-maps/skip.png': 'attempt222-google-maps-skip.png'
		run + 'google-maps/application.png': 'attempt222-google-maps-application.png'
		base + 'attempt222.json': 'attempt222-configuration.json'
		base + 'attempt222-harness.log': 'attempt222-harness.log'
		base + 'interact222.log': 'attempt222-interaction.log'
		base + 'interact222.v': 'attempt222-interaction.v'
		base + 'run222.v': 'attempt222-run.v'
		base + 'prepare222.v': 'attempt222-prepare.v'
		base + 'retain222.v': 'retain222.v'
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
	row['run'] = 'attempt222'
	row['startup_ui_passed'] = false
	row['search_passed'] = false
	row['manual_review'] = 'Initial and Skip screenshots show onboarding; final screenshot shows APK exited. Main thread fails with NoSuchMethodError AutofillManager.notifyViewVisibilityChanged(View,int,boolean), and APK exits10. Input uses settle=0.15 seconds before down, between down/up, and after up, then an explicit10-second wait. Later screenshot was not captured because QEMU closed. Map/search unverified.'
	row['screenshot'] = 'attempt222-google-maps-application.png'
	row['serial_log'] = 'attempt222-google-maps-serial.log.gz'
	row['initial_screenshot'] = 'attempt222-google-maps-initial.png'
	row['skip_screenshot'] = 'attempt222-google-maps-skip.png'
	row['badging_omission'] = 'Only metadata badging strings recursively omitted; remaining result fields retained.'
	os.write_file(dest + 'attempt222-results.json', json2.encode([json2.Any(row)], prettify: true) + '\n')!
	artifacts['attempt222-results.json'] = hash(dest + 'attempt222-results.json')!
	receipt := {
		'artifacts_sha256': json2.Any(artifacts)
		'original_results_sha256': json2.Any(sha256.sum(raw.bytes()).hex())
		'input_identity_receipt': json2.Any('attempt222-input-identities.json')
		'input_identity_receipt_sha256': json2.Any(hash(dest + 'attempt222-input-identities.json')!)
		'shared_input_identity_receipt': json2.Any('attempt218-runtime-identities.json')
		'input_scope': json2.Any('Signed Maps/GMS/Store APK identities verified from result metadata against attempt218 inputs; staged runtime hashes and source identity limitations are retained separately in attempt222-input-identities.json. Kernel/base receipts remain inherited, not measured for attempt222.')
		'interaction_limit': json2.Any('Input222 uses --settle0.15 before down, between down/up, and after up, then an explicit10-second wait. Initial and Skip captures still show onboarding. No later screenshot222:interactor fails after QEMU closes.')
		'functional_outcome': json2.Any('FAILED: main thread throws NoSuchMethodError AutofillManager.notifyViewVisibilityChanged(View,int,boolean); APK exit10, harnessstartup_failed. Initial/Skip screenshots show onboarding; final shows APK exited. Map/search unverified.')
	}
	os.write_file(dest + 'attempt222-runtime-identities.json', json2.encode(receipt, prettify: true) + '\n')!
	println('ATTEMPT222-RETENTION PASS serial/result/APK identities,3 screenshots, input source receipts retained; functional outcome FAILED AutofillManager visibility method, APKexit10; no later screenshot')
}
