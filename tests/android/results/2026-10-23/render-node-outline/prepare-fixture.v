import os
import json2

fn main() {
	b := os.abs_path('build/android-maps')
	task := b + '/outline228'
	output := b + '/outline228-apk'
	assert !os.exists(output)
	os.cp_all(b + '/canvas227-apk', output, false)!
	for file in ['classes.dex', 'bootstrap.apk', 'bootstrap.apk.idsig'] {
		if os.exists(output + '/' + file) { os.rm(output + '/' + file)! }
	}
	sources := task + '/source/startupfixture'
	os.mkdir_all(sources)!
	for file in os.walk_ext('tests/native-android-ws/startupfixture', '.v') {
		os.cp(file, sources + '/' + os.base(file))!
	}
	os.write_file(b + '/finalize-outline228.v', os.read_file(b + '/finalize-canvas227.v')!.replace('canvas227-apk', 'outline228-apk'))!
	for mode in ['baseline', 'fixed'] {
		native := task + '/native-' + mode
		os.mkdir_all(native)!
		for item in os.ls(b + '/canvas227/native-fixed')! {
			if item in ['api-impl.jar', 'libvinix-android-native.so'] { continue }
			os.symlink(b + '/canvas227/native-fixed/' + item, native + '/' + item)!
		}
		jar := b + if mode == 'baseline' { '/framework227-canvas-z/api-impl.jar' } else { '/framework228-outline/api-impl.jar' }
		library := b + if mode == 'baseline' { '/libnative225.so' } else { '/libnative228.so' }
		os.symlink(jar, native + '/api-impl.jar')!
		os.symlink(library, native + '/libvinix-android-native.so')!
		mut config := json2.decode[map[string]json2.Any](os.read_file(b + '/canvas227/fixed.json')!)!
		config['native_dir'] = native
		config['output'] = task + '/run-' + mode
		mut apps := config['applications']!.as_array()
		mut app := apps[0].as_map()
		app['apk'] = output + '/bootstrap.apk'
		apps[0] = app
		config['applications'] = apps
		os.write_file(task + '/' + mode + '.json', json2.encode(config, prettify: true) + '\n')!
	}
	os.write_file(task + '/staged-hashes.v', os.read_file(b + '/canvas227/staged-hashes.v')!.replace('canvas227', 'outline228'))!
	println('Outline228 fixture sources frozen')
}
