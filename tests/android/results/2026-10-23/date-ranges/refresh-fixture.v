import os
import crypto.sha256
import json2

fn main() {
	b := 'build/android-maps/dates240/'
	assert !os.exists(b + 'run-baseline') && !os.exists(b + 'run-fixed')
	mut hashes := map[string]string{}
	for path in os.walk_ext('tests/native-android-ws/startupfixture', '.v') {
		text := os.read_file(path)!
		name := os.base(path)
		os.write_file(b + 'source/startupfixture/' + name, text)!
		hashes[name] = sha256.sum(text.bytes()).hex()
	}
	os.write_file(b + 'fixture-source-sha256.json', json2.encode(hashes, prettify: true) + '\n')!
	println('DATES240 final sources frozen before signed APK build')
}
