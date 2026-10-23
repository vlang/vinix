import os

fn main() {
	b := 'build/android-maps/'
	out := b + 'framework240-date-ranges'
	assert !os.exists(out)
	os.mkdir_all(out + '/sources/androidtools')!
	for path in os.walk_ext(b + 'framework239-insets/sources/androidtools', '.v') {
		os.cp(path, out + '/sources/androidtools/' + os.base(path))!
	}
	for file in ['framework_startup.v', 'framework_date_ranges.v'] {
		os.cp('tests/native-android-tools/androidtools/' + file, out + '/sources/androidtools/' + file)!
	}
	for name in ['build-framework239-insets', 'snapshot-framework239'] {
		new := name.replace('239-insets', '240-date-ranges').replace('239', '240')
		os.write_file(b + new + '.v', os.read_file(b + name + '.v')!.replace('239-insets', '240-date-ranges').replace('239', '240'))!
	}
	println('FRAMEWORK240 frozen239 plus DateUtils range formatting')
}
