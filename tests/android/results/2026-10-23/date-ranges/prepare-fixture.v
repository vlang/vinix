import os
import json2
import crypto.sha256

fn main() {
	b := os.abs_path('build/android-maps/dates240')
	apk := os.abs_path('build/android-maps/dates240-apk')
	assert !os.exists(b) && !os.exists(apk)
	os.mkdir_all(b + '/source/startupfixture')!
	os.cp_all(os.abs_path('build/android-maps/insets239-apk'), apk, false)!
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
		for name in os.ls('build/android-maps/interpolators234/native-fixed235')! {
			if name == 'api-impl.jar' { continue }
			os.symlink(os.abs_path('build/android-maps/interpolators234/native-fixed235/' + name), dir + '/' + name)!
		}
		jar := if mode == 'baseline' { 'framework239-insets' } else { 'framework240-date-ranges' }
		os.symlink(os.abs_path('build/android-maps/' + jar + '/api-impl.jar'), dir + '/api-impl.jar')!
		mut config := json2.decode[map[string]json2.Any](os.read_file('build/android-maps/insets239/fixed.json')!)!
		mut apps := config['applications']!.as_array()
		mut app := apps[0].as_map()
		app['apk'] = apk + '/bootstrap.apk'
		apps[0] = json2.Any(app)
		config['applications'] = json2.Any(apps)
		config['native_dir'] = dir
		config['output'] = b + '/run-' + mode
		os.write_file(b + '/' + mode + '.json', json2.encode(config, prettify: true) + '\n')!
	}
	os.write_file(b + '/staged-hashes.v', os.read_file('build/android-maps/insets239/staged-hashes.v')!.replace('insets239', 'dates240'))!
	os.write_file('build/android-maps/build-dates240.v', os.read_file('build/android-maps/build-insets239.v')!.replace('insets239-apk', 'dates240-apk').replace('INSETS239 APK', 'DATES240 APK'))!
	println('DATES240 PREPARED native235 unchanged, same signed APK for baseline239/fixed240')
}
