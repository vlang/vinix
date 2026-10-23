module main

import os
import json2
import crypto.sha256
import compress.gzip

struct Receipt {
	baseline_source_sha256 string
	fixed_source_sha256    string
	source_sha256          map[string]string
	artifact_sha256        map[string]string
	exit_codes             map[string]int
	asan_options           string
	qualification          string
}

fn hash(body string) string {
	return sha256.sum(body.bytes()).hex()
}

fn main() {
	dir := os.dir(@FILE)
	b := 'build/android-maps/input231/'
	mut sources := map[string]string{}
	for mode in ['baseline', 'fixed'] {
		prefix := b + 'permanent-' + mode + '/'
		sources[mode + '/ws_views.v.txt'] = os.read_file(prefix + 'ws_views.v.txt')!
		sources[mode + '/actual_input.v'] = os.read_file(prefix + 'src/actual_input.v')!
		body := sources[mode + '/ws_views.v.txt']!
		start := body.index('fn ws_input(e voidptr) {') or { panic('missing decoder') }
		assert sources[mode + '/actual_input.v']! == 'module main\n' + body[start..]
	}
	sources['harness.v'] = os.read_file('tests/native-android-ws/inputbatchhost/harness.v.txt')!
	sources['runner.v'] = os.read_file('tests/native-android-ws/input-batch-host.v')!
	sources['protocol.v'] = os.read_file(b + 'permanent-fixed/src/actual_protocol.v')!
	for mode in ['baseline', 'fixed', 'fixed-asan'] {
		prefix := b + 'permanent-' + mode + '/src/'
		assert os.read_file(prefix + 'main.v')! == sources['harness.v']!
		assert os.read_file(prefix + 'actual_protocol.v')! == sources['protocol.v']!
		if mode == 'fixed-asan' {
			assert os.read_file(prefix + 'actual_input.v')! == sources['fixed/actual_input.v']!
		}
		log := os.read_file(b + 'permanent-' + mode + '.log')!
		if mode == 'baseline' {
			assert log.contains('queued DOWN/MOVE/UP/text/wheel must drain in exact order')
			assert log.contains("left value: recorded = ['pointer:2:10:20:0']")
			assert !log.contains('INPUT-HOST ALL PASS')
		} else {
			assert log.count('INPUT-HOST PASS ') == 11
			assert log.contains('INPUT-HOST ALL PASS')
			assert !log.contains('ERROR: AddressSanitizer')
		}
		os.write_file(dir + '/' + mode + '.log', log)!
	}
	baseline := hash(sources['baseline/ws_views.v.txt']!)
	fixed := hash(sources['fixed/ws_views.v.txt']!)
	assert baseline == 'd239ed014e46f244c7e167bfc923aeae7ab3586f5fe2bc41529023382e24f1dc'
	assert fixed == '8cd7980f5a565a1228cc5d09ba0c53f7fe1386d0a82cfd5211e27331ad7c7bc5'
	assert fixed == hash(os.read_file('build-support/android/nativews/ws_views.v')!)
	os.write_file_array(dir + '/sources.json.gz', gzip.compress(json2.encode(sources).bytes())!)!
	mut source_hashes := map[string]string{}
	for name, source in sources { source_hashes[name] = hash(source) }
	mut artifacts := map[string]string{}
	for name in ['README.md', 'retain.v', 'validate.v', 'replay.v', 'sources.json.gz', 'baseline.log',
		'fixed.log', 'fixed-asan.log'] {
		artifacts[name] = sha256.sum(os.read_bytes(dir + '/' + name)!).hex()
	}
	receipt := Receipt{
		baseline_source_sha256: baseline
		fixed_source_sha256:    fixed
		source_sha256:          source_hashes
		artifact_sha256:        artifacts
		exit_codes:             {
			'baseline':   1
			'fixed':      0
			'fixed-asan': 0
		}
		asan_options:           'detect_leaks=0'
		qualification:          'Actual production input functions and protocol structures run against real OS pipes with stubbed Java dispatch/JNI local frames. ASAN checks host memory safety; JNI frame/reference assertions use stubs. Unmanaged V harness allocations exclude whole-process leak checking. Maps latency and interaction evidence is retained separately in ../maps-input-latency/.'
	}
	os.write_file(dir + '/receipt.json', json2.encode(receipt, prettify: true) + '\n')!
	println('INPUT-DRAIN retention PASS')
}
