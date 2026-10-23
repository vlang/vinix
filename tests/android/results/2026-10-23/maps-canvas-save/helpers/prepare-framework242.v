import os

fn main() {
	b := 'build/android-maps/'
	out := b + 'framework242-canvas-save'
	assert !os.exists(out)
	os.mkdir_all(out + '/sources/androidtools')!
	for path in os.walk_ext(b + 'framework241-blur-styles/sources/androidtools', '.v') {
		os.cp(path, out + '/sources/androidtools/' + os.base(path))!
	}
	for file in ['framework_startup.v', 'framework_canvas_save_flags.v'] {
		os.cp('tests/native-android-tools/androidtools/' + file, out + '/sources/androidtools/' + file)!
	}
	for name in ['build-framework241-blur-styles', 'snapshot-framework241'] {
		new := name.replace('241-blur-styles', '242-canvas-save').replace('241', '242')
		os.write_file(b + new + '.v', os.read_file(b + name + '.v')!.replace('241-blur-styles', '242-canvas-save').replace('241', '242'))!
	}
	println('FRAMEWORK242 frozen241 plus Canvas saveLayer overload')
}
