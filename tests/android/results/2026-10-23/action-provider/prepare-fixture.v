import os
import json2
import crypto.sha256

fn main() {
	b := os.abs_path('build/android-maps/action244')
	os.mkdir_all(b + '/source')!
	source := os.read_file('tests/native-android-ws/action-provider-fixture.v')!
	os.write_file(b + '/source/action-provider-fixture.v', source)!
	os.write_file(b + '/fixture-source-sha256.txt', sha256.sum(source.bytes()).hex() + '\n')!
	for mode in ['baseline', 'fixed'] {
		dir := b + '/native-' + mode
		os.mkdir_all(dir)!
		for name in os.ls('build/android-maps/popup243/native-fixed')! {
			if name in ['api-impl.jar', 'libvinix-android-native.so'] { continue }
			os.symlink(os.abs_path('build/android-maps/popup243/native-fixed/' + name), dir + '/' + name)!
		}
		jar := if mode == 'baseline' { 'framework243-popup-menus' } else { 'framework244-action-provider' }
		os.symlink(os.abs_path('build/android-maps/' + jar + '/api-impl.jar'), dir + '/api-impl.jar')!
		os.symlink(os.abs_path('build/android-maps/libnative236.so'), dir + '/libvinix-android-native.so')!
		mut config := json2.decode[map[string]json2.Any](os.read_file('build/android-maps/popup243/fixed.json')!)!
		mut apps := config['applications']!.as_array()
		mut app := apps[0].as_map()
		app['apk'] = os.abs_path('build/android-maps/action244-apk/probe.apk')
		app['source'] = os.abs_path('tests/native-android-ws/action-provider-fixture.v')
		app['startup_seconds'] = 120
		apps[0] = json2.Any(app)
		config['applications'] = json2.Any(apps)
		config['native_dir'] = dir
		config['output'] = b + '/run-' + mode
		os.write_file(b + '/' + mode + '.json', json2.encode(config, prettify: true) + '\n')!
	}
	os.write_file(b + '/staged-hashes.v', os.read_file('build/android-maps/popup243/staged-hashes.v')!.replace('popup243', 'action244'))!
	println('ACTION244 PREPARED immutable fixture source; native236 identical in both runs')
}
