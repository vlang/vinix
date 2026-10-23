import os

fn main() {
	b := 'build/android-maps/'
	output := b + 'framework234-interpolators'
	assert !os.exists(output), 'Do not replace frozen framework sources'
	os.mkdir_all(output + '/sources/androidtools')!
	for path in os.walk_ext('tests/native-android-tools/androidtools', '.v') {
		os.cp(path, output + '/sources/androidtools/' + os.base(path))!
	}
	builder := os.read_file(b + 'build-framework228-outline.v')!
		.replace('framework228-outline', 'framework234-interpolators')
		.replace('FRAMEWORK228-OUTLINE', 'FRAMEWORK234-INTERPOLATORS')
	os.write_file(b + 'build-framework234-interpolators.v', builder)!
	snapshot := os.read_file(b + 'snapshot-framework228.v')!
		.replace('framework228-outline', 'framework234-interpolators')
		.replace("assert hash(b + 'api-impl.jar')! == '26b21262b67e92c77bcf57b9480bc881b0683ac0e8d6f97dba105ef453f3fe5a'", "assert hash(b + 'api-impl.jar')! == manifest['output_sha256']!.str()")
		.replace('FRAMEWORK228', 'FRAMEWORK234')
	os.write_file(b + 'snapshot-framework234.v', snapshot)!
	println('FRAMEWORK234 PREPARED frozen androidtools module')
}
