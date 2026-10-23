import os
import json2
import crypto.sha256

fn main() {
	b := os.abs_path('build/android-maps/texture236')
	apk := os.abs_path('build/android-maps/texture236-apk')
	assert !os.exists(b) && !os.exists(apk)
	assert sha256.sum(os.read_bytes('build/android-maps/accessibility235-apk/bootstrap.apk')!).hex() == 'a6941021c172b2e9fef91e64c03405996df8b6f87a6f4cb30d2c0269b949001e'
	os.mkdir_all(b + '/source/startupfixture')!
	os.cp_all(os.abs_path('build/android-maps/accessibility235-apk'), apk, false)!
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
		jar := if mode == 'baseline' {
			'framework235-accessibility'
		} else {
			'framework236-texture'
		}
		os.symlink(os.abs_path('build/android-maps/' + jar + '/api-impl.jar'), dir + '/api-impl.jar')!
		mut config := json2.decode[map[string]json2.Any](os.read_file('build/android-maps/interpolators234/fixed235.json')!)!
		mut apps := config['applications']!.as_array()
		mut app := apps[0].as_map()
		app['apk'] = apk + '/bootstrap.apk'
		apps[0] = json2.Any(app)
		config['applications'] = json2.Any(apps)
		config['native_dir'] = dir
		config['output'] = b + '/run-' + mode
		os.write_file(b + '/' + mode + '.json', json2.encode(config, prettify: true) + '\n')!
	}
	os.write_file(b + '/staged-hashes.v', os.read_file('build/android-maps/interpolators234/staged-hashes.v')!.replace('interpolators234', 'texture236'))!
	mut builder := os.read_file('build/android-maps/build-accessibility235.v')!.replace('accessibility235-apk', 'texture236-apk')
	start := builder.index('\tstartup := output') or { panic('missing focused exclusion start') }
	end := builder.index("\tfor name in ['classes.dex'") or { panic('missing focused exclusion end') }
	builder = builder[..start] + builder[end..]
	builder = builder.replace('ACCESSIBILITY235 APK', 'TEXTURE236 APK')
	os.write_file(os.abs_path('build/android-maps/build-texture236.v'), builder)!
	println('TEXTURE236 PREPARED all startup probes included; native235 unchanged; framework235 to236')
}
