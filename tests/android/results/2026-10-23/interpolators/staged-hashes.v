import os
import crypto.sha256
import json2

fn main() {
	assert os.args.len == 2 && os.args[1] in ['baseline', 'fixed']
	run := 'build/android-maps/interpolators234/run-' + os.args[1]
	mut hashes := map[string]string{}
	for path in [
		'opt/vinix-android-aarch64/usr/lib/java/dex/android_translation_layer/api-impl.jar',
		'opt/vinix-android-aarch64/usr/lib/art/libvinix-android-native.so',
		'usr/bin/run-android',
		'usr/bin/run-android-calculator',
		'usr/bin/vinix-desktop',
		'opt/android-test/native-guest',
	] {
		hashes[path] = sha256.sum(os.read_bytes(run + '/module/' + path)!).hex()
	}
	os.write_file(run + '/staged-runtime-sha256.json', json2.encode(hashes, prettify: true) + '\n')!
	os.rmdir_all(run + '/module')!
}
