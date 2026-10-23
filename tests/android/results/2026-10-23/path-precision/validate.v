import os
import crypto.sha256
import compress.gzip
import json2

fn hash(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }

fn main() {
	root := os.dir(@FILE)
	receipt := json2.decode[map[string]string](os.read_file(root + '/receipt.json')!)!
	assert hash(root + '/sources.json.gz')! == receipt['sources.json.gz']!
	sources := json2.decode[map[string]string](gzip.decompress(os.read_bytes(root + '/sources.json.gz')!)!.bytestr())!
	assert sources.len == 8
	for path, body in sources {
		assert sha256.sum(body.bytes()).hex() == receipt[path]!, path
	}
	for run in ['host', 'asan'] {
		assert hash(root + '/' + run + '.log')! == receipt[run + '.log']!
		log := os.read_file(root + '/' + run + '.log')!
		assert log.contains('PATH-PRECISION-HOST PASS') && !log.contains('FAIL:') && !log.contains('ERROR: AddressSanitizer')
		exit_key := if run == 'host' { 'normal_exit_code' } else { 'asan_exit_code' }
		assert receipt[exit_key]! == '0'
		for path, body in sources {
			if path.starts_with('build-support/') {
				assert log.contains(sha256.sum(body.bytes()).hex() + '  ' + os.base(path)), path
			}
		}
	}
	assert sources['tests/native-android-ws/pathprecisionhost/harness.v.txt']!.contains('assert live_allocations == 0')
	assert sources['tests/native-android-ws/path-precision-host.v']!.contains('-fsanitize=address')
	println('PATH-PRECISION-VALIDATE PASS six exact production inputs, runner/harness, normal+ASAN logs')
}
