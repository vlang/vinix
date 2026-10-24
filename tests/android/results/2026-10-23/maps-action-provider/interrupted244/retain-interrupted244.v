import os
import json2
import crypto.sha256
import compress.gzip
import time

fn hash(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }

fn copy_file(source string, target string) ! {
	os.mkdir_all(os.dir(target))!
	os.cp(source, target)!
}

fn main() {
	b := 'build/android-maps/'
	out := 'tests/android/results/2026-10-23/maps-action-provider/interrupted244/'
	assert !os.exists(out + 'interruption.json'), 'Interruption snapshot is immutable'
	os.mkdir_all(out)!
	app := b + 'attempt244/google-maps/'
	serial := os.read_bytes(app + 'serial.log')!
	log := serial.bytestr()
	assert !log.contains('APK-SUITE-EXIT id=google-maps')
	assert !log.contains('ANDROID-WS-FAIL')
	assert !os.exists(b + 'attempt244/results.json')
	os.write_file_array(out + 'serial.log.gz', gzip.compress(serial)!)!
	for name in os.ls(app)! {
		if name in ['serial.log', 'serial.log.gz'] { continue }
		if os.file_ext(name) in ['.png', '.log', '.txt', '.json'] || name == 'qemu.pid' {
			copy_file(app + name, out + 'run/' + name)!
		}
	}
	for name in ['attempt244.json', 'run244-console.log', 'manual244-map-wait.log',
		'retain244-inputs.log'] {
		if os.exists(b + name) { copy_file(b + name, out + name)! }
	}
	copy_file(b + 'attempt244/companion-packages.json', out + 'companion-packages.json')!
	copy_file(@FILE, out + 'retain-interrupted244.v')!
	mut record := map[string]json2.Any{}
	record['captured_utc'] = time.utc().str() + ' UTC'
	record['serial_sha256'] = sha256.sum(serial).hex()
	record['serial_bytes'] = i64(serial.len)
	record['network_pcap_sha256'] = hash(app + 'network.pcap')!
	record['results_json_present'] = false
	record['application_exit_marker_present'] = false
	record['framework_failure_marker_present'] = false
	record['observed_end'] = 'Raw serial stops at15:34:30UTC. Onboarding/Skip was reached, but no later map workflow or completed900-second observation is established. The former QEMU/suite/root processes were absent at recovery. A later screenshot request failed Connection refused. This is an interrupted run, with no app outcome inferred.'
	record['helper_identity_qualification'] = 'Inputs and helper files were recovered after interruption. Infrastructure pre-run7 hashes were recorded before the original launch; other helper and module identities were completed at recovery and are not asserted to be pre-launch hashes.'
	os.write_file(out + 'interruption.json', json2.encode(record, prettify: true) + '\n')!
	println('MAPS244 INTERRUPTED retained raw serial/screenshots/logs; no completion or app exit inferred')
}
