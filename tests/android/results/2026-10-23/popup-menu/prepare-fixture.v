import os
import json2
import crypto.sha256

fn main() {
	b := os.abs_path('build/android-maps/popup243')
	os.mkdir_all(b + '/source')!
	source := os.read_file('tests/native-android-ws/popup-menu-fixture.v')!
	os.write_file(b + '/source/popup-menu-fixture.v', source)!
	os.write_file(b + '/fixture-source-sha256.txt', sha256.sum(source.bytes()).hex() + '\n')!
	for mode in ['baseline', 'fixed'] {
		dir := b + '/native-' + mode
		os.mkdir_all(dir)!
		for name in os.ls('build/android-maps/interpolators234/native-fixed235')! {
			if name in ['api-impl.jar', 'libvinix-android-native.so'] { continue }
			os.symlink(os.abs_path('build/android-maps/interpolators234/native-fixed235/' + name), dir + '/' + name)!
		}
		jar := if mode == 'baseline' { 'framework242-canvas-save' } else { 'framework243-popup-menus' }
		os.symlink(os.abs_path('build/android-maps/' + jar + '/api-impl.jar'), dir + '/api-impl.jar')!
		native := if mode == 'baseline' { 'build/android-maps/libnative235.so' } else { 'build/android-maps/libnative236.so' }
		os.symlink(os.abs_path(native), dir + '/libvinix-android-native.so')!
		mut config := json2.decode[map[string]json2.Any](os.read_file('build/android-maps/canvas242/fixed.json')!)!
		mut apps := config['applications']!.as_array()
		mut app := apps[0].as_map()
		app['apk'] = os.abs_path('build/android-maps/popup243-apk/probe.apk')
		app['source'] = os.abs_path('tests/native-android-ws/popup-menu-fixture.v')
		app['startup_seconds'] = 180
		apps[0] = json2.Any(app)
		config['applications'] = json2.Any(apps)
		config['native_dir'] = dir
		config['output'] = b + '/run-' + mode
		os.write_file(b + '/' + mode + '.json', json2.encode(config, prettify: true) + '\n')!
	}
	os.write_file(b + '/staged-hashes.v', os.read_file('build/android-maps/canvas242/staged-hashes.v')!.replace('canvas242', 'popup243'))!
	println('POPUP243 PREPARED independent fixture VM and pinned framework/native pairs')
}
