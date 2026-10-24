import os

fn main() {
	b := 'build/android-maps/'
	assert !os.exists(b + 'attempt244/google-maps/qmp.sock')
	for path in [b + 'verify-maps244-inputs.v',
		'tests/android/results/2026-10-23/maps-action-provider/retain.v',
		'tests/android/results/2026-10-23/maps-action-provider/validate.v'] {
		source := os.read_file(path)!
		assert source.count('__FRAMEWORK244_EXPECTED_SHA256__') == 1, path
		os.write_file(path, source.replace('__FRAMEWORK244_EXPECTED_SHA256__', '933fc7db4267d123a33bb1e4e064ea3b69450fd065bb4d8e4f5898b91cf842b8'))!
	}
	r := os.exec(['/Users/alex/code/v/v_old', '-nocache', '-cc', 'cc', '-o', b + 'verify-maps244-inputs', b + 'verify-maps244-inputs.v'])
	os.write_file(b + 'verify-maps244-inputs-build.log', r.output)!
	assert r.exit_code == 0, r.output
	println('MAPS244 root JAR hash verifier compiled; helpers frozen')
}
