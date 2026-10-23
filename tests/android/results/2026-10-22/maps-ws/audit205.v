import os
import json2
import crypto.sha256
import compress.gzip

fn main() {
	root := 'tests/android/results/2026-10-22/maps-ws/'
	current := json2.decode[map[string]json2.Any](os.read_file(root + 'results.json')!)!
	old := os.exec(['git', 'show', 'HEAD:' + root + 'results.json'])
	assert old.exit_code == 0
	previous := json2.decode[map[string]json2.Any](old.output)!
	mut prior := map[string]map[string]json2.Any{}
	for item in previous['applications']!.as_array() {
		a := item.as_map()
		prior[a['run']!.str()] = a
	}
	mut seen := map[string]bool{}
	for item in current['applications']!.as_array() {
		a := item.as_map()
		run := a['run']!.str()
		assert !seen[run]
		seen[run] = true
		if run in prior {
			assert a == prior[run], 'changed historical run: ${run}'
		}
		serial := gzip.decompress(os.read_bytes(root + a['serial_log']!.str())!)!
		assert sha256.sum(serial).hex() == a['serial_sha256']!.str(), run
		for key in a.keys().filter(it.ends_with('_screenshot') || it in ['screenshot', 'network_capture']) {
			if key !in a { continue }
			assert sha256.sum(os.read_bytes(root + a[key]!.str())!).hex() == a[key + '_sha256']!.str(), run + key
		}
		assert a['runtime_sha256']!.as_map().len > 0
	}
	for run, _ in prior { assert seen[run], 'lost ${run}' }
	println('AUDIT-PASS ${seen.len} unique runs; retained serial/framebuffer hashes match; all committed records unchanged')
}
