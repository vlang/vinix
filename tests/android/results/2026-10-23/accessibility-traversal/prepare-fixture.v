import os
import json2
import crypto.sha256

fn main() {
	b := os.abs_path('build/android-maps/accessibility235')
	apk := os.abs_path('build/android-maps/accessibility235-apk')
	assert !os.exists(b) && !os.exists(apk)
	assert sha256.sum(os.read_bytes('build/android-maps/interpolators234-apk/bootstrap.apk')!).hex() == '6dc384bc7cd0ace193317c5ebb45adb5d691a475e5e0a91756710320d0cde447'
	os.mkdir_all(b + '/source/startupfixture')!
	os.cp_all(os.abs_path('build/android-maps/interpolators234-apk'), apk, false)!
	mut hashes := map[string]string{}
	for path in os.walk_ext('tests/native-android-ws/startupfixture', '.v') {
		text := os.read_file(path)!
		name := os.base(path)
		os.write_file(b + '/source/startupfixture/' + name, text)!
		hashes[name] = sha256.sum(text.bytes()).hex()
	}
	os.write_file(b + '/fixture-source-sha256.json', json2.encode(hashes, prettify: true) + '\n')!
	for mode in ['baseline', 'fixed'] {
		dir := b + '/native-' + mode
		os.mkdir_all(dir)!
		for name in os.ls('build/android-maps/interpolators234/native-fixed')! {
			if name == 'api-impl.jar' { continue }
			os.symlink(os.abs_path('build/android-maps/interpolators234/native-fixed/' + name), dir + '/' + name)!
		}
		jar := if mode == 'baseline' {
			'framework234-interpolators'
		} else {
			'framework235-accessibility'
		}
		os.symlink(os.abs_path('build/android-maps/' + jar + '/api-impl.jar'), dir + '/api-impl.jar')!
		mut config := json2.decode[map[string]json2.Any](os.read_file('build/android-maps/interpolators234/fixed.json')!)!
		mut apps := config['applications']!.as_array()
		mut app := apps[0].as_map()
		app['apk'] = apk + '/bootstrap.apk'
		apps[0] = json2.Any(app)
		config['applications'] = json2.Any(apps)
		config['native_dir'] = dir
		config['output'] = b + '/run-' + mode
		os.write_file(b + '/' + mode + '.json', json2.encode(config, prettify: true) + '\n')!
	}
	os.write_file(b + '/staged-hashes.v', os.read_file('build/android-maps/interpolators234/staged-hashes.v')!.replace('interpolators234', 'accessibility235'))!
	println('ACCESSIBILITY235 PREPARED frozen startupfixture; native233 unchanged; framework234 to235')
}
