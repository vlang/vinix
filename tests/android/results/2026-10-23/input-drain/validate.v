module main

import os
import json2
import crypto.sha256
import compress.gzip

fn main() {
	dir := os.dir(@FILE)
	receipt := json2.decode[map[string]json2.Any](os.read_file(dir + '/receipt.json')!)!
	for name, expected in receipt['artifact_sha256']!.as_map() {
		assert sha256.sum(os.read_bytes(dir + '/' + name)!).hex() == expected.str(), name
	}
	sources := json2.decode[map[string]string](gzip.decompress(os.read_bytes(dir + '/sources.json.gz')!)!.bytestr())!
	for name, expected in receipt['source_sha256']!.as_map() {
		assert sha256.sum(sources[name]!.bytes()).hex() == expected.str(), name
	}
	for mode in ['baseline', 'fixed'] {
		body := sources[mode + '/ws_views.v.txt']!
		start := body.index('fn ws_input(e voidptr) {') or { panic('missing decoder') }
		assert sources[mode + '/actual_input.v']! == 'module main\n' + body[start..]
	}
	assert os.read_file(dir + '/baseline.log')!.contains("left value: recorded = ['pointer:2:10:20:0']")
	for mode in ['fixed', 'fixed-asan'] {
		log := os.read_file(dir + '/' + mode + '.log')!
		assert log.count('INPUT-HOST PASS ') == 11
		assert log.contains('INPUT-HOST ALL PASS')
		assert !log.contains('ERROR: AddressSanitizer')
	}
	println('INPUT-DRAIN retained proof PASS')
}
