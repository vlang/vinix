import os
import crypto.sha256

fn main() {
	base := 'build/android-maps/'
	output := base + 'interpolator-resources234'
	os.mkdir_all(output)!
	for name in ['fpA', '4QZ', 'c0L', 'aJ7'] {
		args := ['build/android-native-ws/aapt2', 'dump', 'xmltree', base + 'GoogleMaps.apk', '--file', 'res/' + name + '.xml']
		result := os.exec(args)
		assert result.exit_code == 0, result.output
		os.write_file(output + '/' + name + '.txt', result.output)!
	}
	os.write_file(output + '/apk-sha256.txt', sha256.sum(os.read_bytes(base + 'GoogleMaps.apk')!).hex() + '\n')!
	println('INTERPOLATOR234 Maps four compiled XML resource dumps retained')
}
