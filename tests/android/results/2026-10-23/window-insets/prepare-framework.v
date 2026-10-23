import os

fn main() {
	b := 'build/android-maps/'
	out := b + 'framework239-insets'
	assert !os.exists(out)
	os.mkdir_all(out + '/sources/androidtools')!
	for path in os.walk_ext(b + 'framework237-lookup/sources/androidtools', '.v') {
		os.cp(path, out + '/sources/androidtools/' + os.base(path))!
	}
	for file in ['framework_startup.v', 'framework_insets.v'] {
		os.cp('tests/native-android-tools/androidtools/' + file, out + '/sources/androidtools/' + file)!
	}
	assert os.exists(out + '/sources/androidtools/framework.v')
	assert os.exists(out + '/sources/androidtools/framework_lookup_trace.v')
	for name in ['build-framework238-insets', 'snapshot-framework238'] {
		os.write_file(b + name.replace('238', '239') + '.v', os.read_file(b + name + '.v')!.replace('238', '239'))!
	}
	println('FRAMEWORK239 frozen lookup237 plus corrected Insets overlay')
}
