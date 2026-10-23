import os

fn main() {
	from := 'tests/android/results/2026-10-23/maps-accessibility/'
	out := 'tests/android/results/2026-10-23/maps-texture-transform/'
	os.mkdir_all(out)!
	for name in ['retain.v', 'validate.v'] {
		mut source := os.read_file(from + name)!
		source = source.replace('235', '236')
			.replace('framework236-accessibility', 'framework236-texture')
			.replace('6810384e4ccc548adcf16a9d9cbc57d70c3250b50bda912fa32edf2af5874dfd', '9f5ddfbb7a17cff8265c0c1a4dba752b59a9ac12e88801e15c26b17654f0c584')
			.replace('native233', 'native235')
			.replace('e94ca96bf9809c65392741964e3dcab985d17a5ae660c4d5fef46ef5cb19bd04', '0d6b3cd8dfa5c7f109b1fb5305eac54d1b90f40ffc764a94359d19061345aad9')
			.replace('== 82', '== 83').replace('native=82', 'native=83')
			.replace('== 105', '== 106')
			.replace('../maps-interpolators/', '../maps-accessibility/')
			.replace('source-delta-from234', 'source-delta-from235')
			.replace("'android/view/View.smali'", "'android/view/View.smali', 'android/view/TextureView.smali'")
			.replace('assert smali.len == 15', 'assert smali.len == 16')
		if name == 'retain.v' {
			source = source.replace("'snapshot-framework236.v', 'prepare-framework236.v.generated', 'prepare236.v'", "'snapshot-framework236.v', 'prepare-texture236.v', 'prepare236.v'")
			source = source.replace("'interact236.v', 'manual236.v', 'keys236.v', 'zoom236.v', 'identity236.v', 'trace-input.v',", "'interact236.v', 'manual236.v', 'identity236.v', 'trace-input.v',")
			source = source.replace("'prepare-maps236-receipt.v', 'compare-framework236.v'", "'prepare-maps236-receipt.v'")
			source = source.replace('Maps236 reuses native235 with framework236 accessibility traversal state and XML support.', 'Maps236 uses the independently tested native235 path precision implementation and framework236 TextureView content transform state.')
		} else {
			source = source.replace('../maps-input-latency/233/native-exact-sources.json.gz', '../interpolators/fixed-native-sources.json.gz')
		}
		os.write_file(out + name, source)!
	}
	println('MAPS236 receipt templates prepared; no staging or results read')
}
