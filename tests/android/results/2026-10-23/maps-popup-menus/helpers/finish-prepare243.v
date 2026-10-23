import os

fn main() {
	b := 'build/android-maps/'
	path := b + 'verify-maps243-inputs.v'
	source := os.read_file(path)!
	assert source.count('__FRAMEWORK243_EXPECTED_SHA256__') == 1
	os.write_file(path, source.replace('__FRAMEWORK243_EXPECTED_SHA256__', '0eb5f294900d7ef1683c7444c97ebd59d96d6dc7e2c372731e358ce9c6bde0cc'))!
	r := os.exec(['/Users/alex/code/v/v_old', '-nocache', '-cc', 'cc', '-o', b + 'verify-maps243-inputs', path])
	os.write_file(b + 'verify-maps243-inputs-build.log', r.output)!
	assert r.exit_code == 0, r.output
	println('MAPS243 root JAR hash verifier compiled; helpers frozen')
}
