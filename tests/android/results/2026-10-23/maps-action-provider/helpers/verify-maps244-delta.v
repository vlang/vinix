import os
import json2
import compress.gzip
import crypto.sha256

fn main() {
	b := 'build/android-maps/'
	previous := json2.decode[map[string]string](gzip.decompress(os.read_bytes(b + 'framework243-popup-menus/exact-sources.json.gz')!)!.bytestr())!
	current := json2.decode[map[string]string](gzip.decompress(os.read_bytes(b + 'framework244-action-provider/exact-sources.json.gz')!)!.bytestr())!
	assert current.len == 113 && previous.len == 112
	mut changed := []string{}
	for path, source in current {
		if source == previous[path] { continue }
		assert path in ['tests/native-android-tools/androidtools/framework_classes.v',
			'tests/native-android-tools/androidtools/framework_action_provider.v'], path
		changed << path
	}
	assert changed.len == 2
	for path in previous.keys() { assert path in current, path }
	native_previous := json2.decode[map[string]string](gzip.decompress(os.read_bytes('tests/android/results/2026-10-23/maps-popup-menus/native/exact-sources.json.gz')!)!.bytestr())!
	native_current := json2.decode[map[string]string](gzip.decompress(os.read_bytes(b + 'native236-exact-sources.json.gz')!)!.bytestr())!
	assert native_current.len == 83 && native_current == native_previous
	assert sha256.sum(os.read_bytes(b + 'libnative236.so')!).hex() == '78da0707dc12d4cc8a55e3b3efa3e94ee202ec5c36babbf2470f259423a59d3d'
	println('MAPS244 DELTA PASS framework 112→113: classes + ActionProvider; native236 unchanged 83 sources')
}
