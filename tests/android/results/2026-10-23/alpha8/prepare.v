import os
import json2

fn main() {
	b := os.abs_path('build/android-maps')
	output := b + '/alpha224-apk'
	if !os.exists(output) { os.cp_all(b + '/autofill-manager223-apk', output, false)! }
	sources := b + '/alpha224/source/startupfixture'
	os.mkdir_all(sources)!
	for path in os.walk_ext('tests/native-android-ws/startupfixture', '.v') {
		os.cp(path, sources + '/' + os.base(path))!
	}
	os.write_file(b + '/finalize-alpha224.v', os.read_file(b + '/finalize-autofill222.v')!.replace('autofill222-apk', 'alpha224-apk').replace(' startupfixture.install(output, resources)!', " startupfixture.install(output, resources)!\n if os.is_file(output + '/classes.dex') { os.rm(output + '/classes.dex')! }"))!
	task := b + '/alpha224'
	for mode in ['baseline', 'fixed'] {
		native := task + '/native-' + mode
		os.mkdir_all(native)!
		for item in os.ls(b + '/native')! {
			if item in ['api-impl.jar', 'libvinix-android-native.so', 'popular-launcher'] {
				continue
			}
			if !os.exists(native + '/' + item) {
				os.symlink(b + '/native/' + item, native + '/' + item)!
			}
		}
		for name, path in {
			'api-impl.jar':               b + '/framework223-autofill/api-impl.jar'
			'libvinix-android-native.so': b + '/libnative' + if mode == 'baseline' {
				'221.so'
			} else {
				'225.so'
			}
			'popular-launcher':           b + '/launcher200'
		} {
			if !os.exists(native + '/' + name) { os.symlink(path, native + '/' + name)! }
		}
		mut config := json2.decode[map[string]json2.Any](os.read_file(b + '/autofill-manager223/fixed.json')!)!
		config['native_dir'] = native
		config['output'] = task + '/run-' + mode
		mut apps := config['applications']!.as_array()
		mut app := apps[0].as_map()
		app['apk'] = output + '/bootstrap.apk'
		apps[0] = app
		config['applications'] = apps
		os.write_file(task + '/' + mode + '.json', json2.encode(config, prettify: true))!
	}
	os.write_file(task + '/staged-hashes.v', os.read_file(b + '/autofill-manager223/staged-hashes.v')!.replace('autofill-manager223', 'alpha224'))!
}
