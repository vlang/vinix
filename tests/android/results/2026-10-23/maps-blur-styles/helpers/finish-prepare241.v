import os

fn main() {
	b := 'build/android-maps/'
	path := b + 'verify-maps241-inputs.v'
	source := os.read_file(path)!
	assert source.count('__FRAMEWORK241_EXPECTED_SHA256__') == 1
	os.write_file(path, source.replace('__FRAMEWORK241_EXPECTED_SHA256__', '60c171c45dd4a3a2179f6402ce7fdabd72ef3d19ea8596031e58086adc400c04'))!
	r := os.exec(['/Users/alex/code/v/v_old', '-nocache', '-cc', 'cc', '-o', b + 'verify-maps241-inputs', path])
	os.write_file(b + 'verify-maps241-inputs-build.log', r.output)!
	assert r.exit_code == 0, r.output
	release := os.read_file(b + 'release239.v')!.replace('239', '240').replace('maps-window-insets', 'maps-date-ranges')
	os.write_file(b + 'release240.v', release)!
	println('MAPS241 root JAR hash verifier compiled; completed240 cleanup helper prepared')
}
