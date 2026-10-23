import os

fn main() {
	b := 'build/android-maps/'
	out := b + 'framework241-blur-styles'
	assert !os.exists(out)
	os.mkdir_all(out + '/sources/androidtools')!
	for path in os.walk_ext(b + 'framework240-date-ranges/sources/androidtools', '.v') {
		os.cp(path, out + '/sources/androidtools/' + os.base(path))!
	}
	for file in ['framework_startup.v', 'framework_blur_styles.v'] {
		os.cp('tests/native-android-tools/androidtools/' + file, out + '/sources/androidtools/' + file)!
	}
	for name in ['build-framework240-date-ranges', 'snapshot-framework240'] {
		new := name.replace('240-date-ranges', '241-blur-styles').replace('240', '241')
		os.write_file(b + new + '.v', os.read_file(b + name + '.v')!.replace('240-date-ranges', '241-blur-styles').replace('240', '241'))!
	}
	println('FRAMEWORK241 frozen240 plus complete Blur styles')
}
