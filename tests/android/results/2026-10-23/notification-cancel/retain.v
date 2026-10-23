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
	qualification          string
}

fn hash(body string) string { return sha256.sum(body.bytes()).hex() }

fn main() {
	dir := os.dir(@FILE)
	base := 'build/android-maps/notifications233/'
	mut sources := map[string]string{}
	for mode in ['baseline', 'fixed'] {
		prefix := base + mode + '/'
		sources[mode + '/notifications.v.txt'] = os.read_file(prefix + 'notifications.v.txt')!
		sources[mode + '/actual_notifications.v'] = os.read_file(prefix + 'src/actual_notifications.v')!
		assert os.read_file(prefix + 'src/main.v')! == os.read_file('tests/native-android-ws/notificationshost/harness.v.txt')!
		log := os.read_file(base + mode + '.log')!
		if mode == 'baseline' {
			assert log.contains('cancel must tolerate an absent optional broker')
			assert log.contains('FAIL:') && !log.contains('NOTIFICATION-HOST ALL PASS')
		} else {
			assert log.count('NOTIFICATION-HOST PASS ') == 11
			assert log.contains('NOTIFICATION-HOST ALL PASS')
			assert log.count('native-service=absent') == 4
		}
		os.write_file(dir + '/' + mode + '.log', log)!
	}
	sources['harness.v'] = os.read_file('tests/native-android-ws/notificationshost/harness.v.txt')!
	sources['runner.v'] = os.read_file('tests/native-android-ws/notifications-host.v')!
	baseline := hash(sources['baseline/notifications.v.txt']!)
	fixed := hash(sources['fixed/notifications.v.txt']!)
	assert baseline == '115ec73f2c5c62962ea92d459cd57763d494ca374f0de1f67fa04dc75fa83e5b'
	assert fixed == '8ace71948daff8b7e93ac144728a4593f4d94406f5ed94bc2261d3b9b1c2694c'
	assert fixed == hash(os.read_file('build-support/android/nativews/notifications.v')!)
	os.write_file_array(dir + '/sources.json.gz', gzip.compress(json2.encode(sources).bytes())!)!
	mut source_hashes := map[string]string{}
	for name, source in sources { source_hashes[name] = hash(source) }
	mut artifacts := map[string]string{}
	for name in ['README.md', 'retain.v', 'validate.v', 'replay.v', 'sources.json.gz', 'baseline.log',
		'fixed.log'] {
		artifacts[name] = sha256.sum(os.read_bytes(dir + '/' + name)!).hex()
	}
	os.write_file(dir + '/receipt.json', json2.encode(Receipt{
		baseline_source_sha256: baseline
		fixed_source_sha256:    fixed
		source_sha256:          source_hashes
		artifact_sha256:        artifacts
		exit_codes:             {
			'baseline': 1
			'fixed':    0
		}
		qualification:          'Actual production notification code with deterministic socket/clock/Java exception helpers. Covers absent endpoint classification including EINPROGRESS/SO_ERROR, preserved real failures, wire payloads, selected invalid framing cases, posting and socket cleanup. Live broker and Java integration are outside this host proof.'
	}, prettify: true) + '\n')!
	println('NOTIFICATION-CANCEL retention PASS')
}
