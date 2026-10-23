import os
import json2
import compress.gzip
import crypto.sha256

fn main() {
	b := 'build/android-maps/'
	f := b + 'framework239-insets/'
	manifest := json2.decode[map[string]json2.Any](os.read_file(f + 'framework-manifest.json')!)!
	declared := manifest['sources']!.as_map()
	sources := json2.decode[map[string]string](gzip.decompress(os.read_bytes(f + 'exact-sources.json.gz')!)!.bytestr())!
	assert sources.len == 108 && declared.len == 108
	for path, source in sources {
		assert sha256.sum(source.bytes()).hex() == declared[path]!.str(), path
		if path.starts_with('tests/native-android-tools/androidtools/') {
			assert source == os.read_file(f + 'sources/androidtools/' + os.base(path))!, path
		}
	}
	jar := sha256.sum(os.read_bytes(f + 'api-impl.jar')!).hex()
	assert jar == manifest['output_sha256']!.str()
	native := sha256.sum(os.read_bytes(b + 'libnative235.so')!).hex()
	assert native == '0d6b3cd8dfa5c7f109b1fb5305eac54d1b90f40ffc764a94359d19061345aad9'
	identities := json2.decode[map[string]string](os.read_file(b + 'identity239-inputs/pre-run-sha256.json')!)!
	assert identities.len == 7
	for name in ['vinix', 'limine.conf'] {
		assert sha256.sum(os.read_bytes(b + 'identity239-inputs/' + name)!).hex() == identities['boot/' + name]!
	}
	for _, digest in identities { assert digest.len == 64 }
	println('MAPS239 FROZEN INPUTS PASS sources108 framework=' + jar + ' native235=' + native)
	println('MAPS239 PRE-RUN IDENTITIES PASS 7 hashes with retained kernel and limine.conf')
}
