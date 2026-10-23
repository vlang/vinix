import os

fn main() {
	output := os.abs_path('build/android-maps/framework228-outline')
	os.mkdir_all(output + '/sources/androidtools')!
	for file in os.walk_ext('tests/native-android-tools/androidtools', '.v') {
		os.cp(file, output + '/sources/androidtools/' + os.base(file))!
	}
	builder := os.read_file('build/android-maps/build-framework227-canvas-z.v')!
		.replace('framework227-canvas-z', 'framework228-outline')
		.replace('FRAMEWORK227-CANVAS-Z', 'FRAMEWORK228-OUTLINE')
	os.write_file('build/android-maps/build-framework228-outline.v', builder)!
	println('framework228 snapshot prepared')
}
