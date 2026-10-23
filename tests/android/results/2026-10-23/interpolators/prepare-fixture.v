import os
import json2

fn main() {
	b := os.abs_path('build/android-maps/interpolators234')
	apk := os.abs_path('build/android-maps/interpolators234-apk')
	os.mkdir_all(b + '/source/startupfixture')!
	if !os.is_dir(apk) { os.cp_all(os.abs_path('build/android-maps/outline228-apk'), apk, false)! }
	for file in os.walk_ext('tests/native-android-ws/startupfixture', '.v') {
		os.cp(file, b + '/source/startupfixture/' + os.file_name(file))!
	}
	os.write_file(b + '/source/startupfixture/interpolators_entry.v', 'module startupfixture\npub fn interpolators(output string) ! { install_interpolator_probe(output)! }\n')!
	startup := apk + '/smali/org/vinix/bootstrap/StartupProbe.smali'
	mut source := os.read_file(startup)!
	old := 'invoke-static {}, Lorg/vinix/bootstrap/RenderNodeOutlineProbe;->check()V'
	assert source.count(old) == 1
	if !source.contains('InterpolatorProbe;->check') {
		source = source.replace(old, old + '\ninvoke-static {p0}, Lorg/vinix/bootstrap/InterpolatorProbe;->check(Landroid/content/Context;)V')
		os.write_file(startup, source)!
	}
	for mode in ['baseline', 'fixed'] {
		dir := b + '/native-' + mode
		os.mkdir_all(dir)!
		for name in os.ls('build/android-maps/outline228/native-fixed')! {
			if name in ['api-impl.jar', 'libvinix-android-native.so'] { continue }
			if !os.exists(dir + '/' + name) {
				os.symlink(os.abs_path('build/android-maps/outline228/native-fixed/' + name), dir + '/' + name)!
			}
		}
		os.symlink(os.abs_path('build/android-maps/libnative233.so'), dir + '/libvinix-android-native.so')!
		jar := if mode == 'baseline' { 'framework228-outline' } else { 'framework234-interpolators' }
		os.symlink(os.abs_path('build/android-maps/' + jar + '/api-impl.jar'), dir + '/api-impl.jar')!
		mut config := json2.decode[map[string]json2.Any](os.read_file('build/android-maps/outline228/fixed.json')!)!
		mut apps := config['applications']!.as_array()
		mut app := apps[0].as_map()
		app['apk'] = apk + '/bootstrap.apk'
		apps[0] = json2.Any(app)
		config['applications'] = json2.Any(apps)
		config['native_dir'] = dir
		config['output'] = b + '/run-' + mode
		os.write_file(b + '/' + mode + '.json', json2.encode(config, prettify: true) + '\n')!
	}
}
