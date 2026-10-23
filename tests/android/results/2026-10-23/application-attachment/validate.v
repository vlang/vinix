import os
import json2
import crypto.sha256
import compress.gzip

struct Receipt {
	artifacts map[string]string
	inputs    map[string]string
}

fn main() {
	dir := os.dir(@FILE)
	receipt := json2.decode[Receipt](os.read_file(dir + '/receipt.json')!)!
	for name, expected in receipt.artifacts {
		assert sha256.sum(os.read_bytes(dir + '/' + name)!).hex() == expected, name
	}
	sources := json2.decode[map[string]string](gzip.decompress(os.read_bytes(dir + '/sources.json.gz')!)!.bytestr())!
	for name, source in sources {
		if name.starts_with('androidtools/') || name == 'services-fixture.v' || name in [
			'build.v',
			'run.v',
		] {
			assert sha256.sum(source.bytes()).hex() == receipt.inputs['source/' + name], name
		}
	}
	baseline := gzip.decompress(os.read_bytes(dir + '/baseline-serial.log.gz')!)!.bytestr()
	fixed := gzip.decompress(os.read_bytes(dir + '/fixed-serial.log.gz')!)!.bytestr()
	marker := 'APPLICATION-ATTACH-PASS worker-waits owner-reentry initialized-state onCreate-worker-join'
	assert baseline.contains('Application getter escaped incomplete attachment or owner reentry failed')
	assert !baseline.contains(marker)
	assert fixed.contains(marker)
	assert !fixed.contains('ANDROID-WS-FAIL')
	assert !fixed.contains('java.lang.AssertionError')
	assert os.read_file(dir + '/baseline-results.json')!.contains('"outcome": "startup_failed"')
	assert os.read_file(dir + '/fixed-results.json')!.contains('"outcome": "window_observed"')
	assert !sources['baseline/ATLLoadedApp.smali'].contains('vinixCreateApplication')
	assert sources['fixed/ATLLoadedApp.smali'].contains('invoke-direct {p0}, Landroid/atl/ATLLoadedApp;->vinixCreateApplication()Landroid/app/Application;')
	println('APPLICATION-ATTACH-VALIDATION-PASS baseline-reproduced fixed-passed owner-reentry onCreate-worker-join artifact-hashes source-hashes')
}
