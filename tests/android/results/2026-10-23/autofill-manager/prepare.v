import os
import json2

fn main() {
	b := os.abs_path('build/android-maps')
	output := b + '/autofill-manager223-apk'
	if !os.exists(output) { os.cp_all(b + '/autofill222-apk', output, false)! }
	sources := b + '/autofill-manager223-source/startupfixture'
	os.mkdir_all(sources)!
	for path in os.walk_ext('tests/native-android-ws/startupfixture', '.v') { os.cp(path, sources + '/' + os.base(path))! }
	startup := sources + '/startup.v'
	os.write_file(startup, os.read_file(startup)!.replace(' install_autofill_probe(dir)!', ' install_autofill_probe(dir)!\n install_autofill_manager_probe(dir)!').replace('invoke-static {}, Lorg/vinix/bootstrap/AutofillProbe;->check()V', 'invoke-static {}, Lorg/vinix/bootstrap/AutofillProbe;->check()V\ninvoke-static {p0}, Lorg/vinix/bootstrap/AutofillManagerProbe;->check(Landroid/content/Context;)V'))!
	finalizer := os.read_file(b + '/finalize-autofill222.v')!.replace('autofill222-apk', 'autofill-manager223-apk')
	os.write_file(b + '/finalize-autofill-manager223.v', finalizer)!
	task := b + '/autofill-manager223'
	os.mkdir_all(task)!
	for mode in ['baseline', 'fixed'] {
		native := task + '/native-' + mode
		os.mkdir_all(native)!
		for item in os.ls(b + '/native')! {
			if item in ['api-impl.jar', 'libvinix-android-native.so', 'popular-launcher'] { continue }
			if !os.exists(native + '/' + item) { os.symlink(b + '/native/' + item, native + '/' + item)! }
		}
		jar := b + if mode == 'baseline' { '/framework222-autofill/api-impl.jar' } else { '/framework223-autofill/api-impl.jar' }
		for name, path in {'api-impl.jar': jar, 'libvinix-android-native.so': b + '/libnative204.so', 'popular-launcher': b + '/launcher200'} {
			if !os.exists(native + '/' + name) { os.symlink(path, native + '/' + name)! }
		}
		mut config := json2.decode[map[string]json2.Any](os.read_file(b + '/autofill222/fixed.json')!)!
		config['native_dir'] = native
		config['output'] = task + '/run-' + mode
		mut apps := config['applications']!.as_array()
		mut app := apps[0].as_map()
		app['apk'] = output + '/bootstrap.apk'
		apps[0] = app
		config['applications'] = apps
		os.write_file(task + '/' + mode + '.json', json2.encode(config, prettify:true))!
	}
}
