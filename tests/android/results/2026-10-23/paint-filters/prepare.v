import os
import json2
import crypto.sha256

fn main() {
	b := os.abs_path('build/android-maps')
	output := b + '/paint226-apk'
	if !os.exists(output) { os.cp_all(b + '/alpha224-apk', output, false)! }
	sources := b + '/paint226/source/startupfixture'
	os.mkdir_all(sources)!
	for file in os.walk_ext('tests/native-android-ws/startupfixture', '.v') {
		os.cp(file, sources + '/' + os.base(file))!
	}
	os.write_file(b + '/finalize-paint226.v', os.read_file(b + '/finalize-autofill-manager223.v')!.replace('autofill-manager223-apk', 'paint226-apk'))!
	task := b + '/paint226'
	for mode in ['baseline', 'fixed'] {
		native := task + '/native-' + mode
		os.mkdir_all(native)!
		for item in os.ls(b + '/alpha224/native-fixed')! {
			if item == 'api-impl.jar' { continue }
			if !os.exists(native + '/' + item) { os.symlink(b + '/alpha224/native-fixed/' + item, native + '/' + item)! }
		}
		jar := b + if mode == 'baseline' { '/framework223-autofill/api-impl.jar' } else { '/framework226-filters/api-impl.jar' }
		if !os.exists(native + '/api-impl.jar') { os.symlink(jar, native + '/api-impl.jar')! }
		mut config := json2.decode[map[string]json2.Any](os.read_file(b + '/alpha224/fixed.json')!)!
		config['native_dir'] = native
		config['output'] = task + '/run-' + mode
		mut apps := config['applications']!.as_array()
		mut app := apps[0].as_map()
		app['apk'] = output + '/bootstrap.apk'
		apps[0] = app
		config['applications'] = apps
		os.write_file(task + '/' + mode + '.json', json2.encode(config, prettify: true))!
	}
	os.write_file(task + '/staged-hashes.v', os.read_file(b + '/autofill-manager223/staged-hashes.v')!.replace('autofill-manager223', 'paint226'))!
	println('PAINT226-APK ' + sha256.sum(os.read_bytes(output + '/bootstrap.apk')!).hex())
}
