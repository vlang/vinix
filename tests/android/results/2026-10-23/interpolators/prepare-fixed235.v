import os
import json2

fn main() {
	task := os.abs_path('build/android-maps/interpolators234')
	dir := task + '/native-fixed235'
	assert !os.exists(dir)
	os.mkdir_all(dir)!
	for name in os.ls(task + '/native-fixed')! {
		if name == 'libvinix-android-native.so' {
			os.symlink(os.abs_path('build/android-maps/libnative235.so'), dir + '/' + name)!
		} else if name in ['atlframework', 'android-native.c', 'androidfw_c_api.h', 'sqlite3.h',
			'stb_image.h', 'stb_truetype.h'] {
			os.symlink(os.abs_path('build/android-maps/native235/' + name), dir + '/' + name)!
		} else {
			os.symlink(task + '/native-fixed/' + name, dir + '/' + name)!
		}
	}
	mut config := json2.decode[map[string]json2.Any](os.read_file(task + '/fixed.json')!)!
	config['native_dir'] = dir
	config['output'] = task + '/run-fixed235'
	os.write_file(task + '/fixed235.json', json2.encode(config, prettify: true) + '\n')!
	os.write_file(task + '/staged-hashes235.v', os.read_file(task + '/staged-hashes.v')!.replace("os.args[1] in ['baseline', 'fixed']", "os.args[1] == 'fixed235'"))!
	println('INTERPOLATORS-FIXED235 PREPARED same APK/framework234; native235 only')
}
