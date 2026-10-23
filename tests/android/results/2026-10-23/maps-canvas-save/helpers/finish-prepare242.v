import os

fn main() {
	b := 'build/android-maps/'
	path := b + 'verify-maps242-inputs.v'
	source := os.read_file(path)!
	assert source.count('__FRAMEWORK242_EXPECTED_SHA256__') == 1
	os.write_file(path, source.replace('__FRAMEWORK242_EXPECTED_SHA256__', '8e6eb74104871e7b3391a75bd5160c0b74bb1951a45ab9b6626a26e46c965f74'))!
	r := os.exec(['/Users/alex/code/v/v_old', '-nocache', '-cc', 'cc', '-o', b + 'verify-maps242-inputs', path])
	os.write_file(b + 'verify-maps242-inputs-build.log', r.output)!
	assert r.exit_code == 0, r.output
	println('MAPS242 root JAR hash verifier compiled; helpers frozen')
}
