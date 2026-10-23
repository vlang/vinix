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
		mut actual := sources[mode + '/notifications.v.txt']!.replace('module atlframework', 'module main')
		for name in ['socket', 'connect', 'getsockopt', 'send', 'recv', 'poll', 'close', 'getuid',
			'getenv', '__errno_location'] {
			actual = actual.replace('fn C.' + name + '(', 'fn UNUSED_' + name + '(')
			actual = actual.replace('C.' + name + '(', 'host_' + name + '(')
		}
		actual = actual.split_into_lines().filter(!it.starts_with('fn UNUSED_')).join('\n') + '\n'
		assert actual == sources[mode + '/actual_notifications.v']!
	}
	assert os.read_file(dir + '/baseline.log')!.contains('cancel must tolerate an absent optional broker')
	log := os.read_file(dir + '/fixed.log')!
	assert log.count('NOTIFICATION-HOST PASS ') == 11
	assert log.contains('NOTIFICATION-HOST ALL PASS') && log.count('native-service=absent') == 4
	println('NOTIFICATION-CANCEL retained proof PASS')
}
