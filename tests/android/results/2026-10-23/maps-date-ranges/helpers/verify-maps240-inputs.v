import os
import json2
import compress.gzip
import crypto.sha256

fn main() {
	b := 'build/android-maps/'
	f := b + 'framework240-date-ranges/'
	manifest := json2.decode[map[string]json2.Any](os.read_file(f + 'framework-manifest.json')!)!
	declared := manifest['sources']!.as_map()
	sources := json2.decode[map[string]string](gzip.decompress(os.read_bytes(f + 'exact-sources.json.gz')!)!.bytestr())!
	assert sources.len == 109 && declared.len == 109
	for path, source in sources {
		assert sha256.sum(source.bytes()).hex() == declared[path]!.str(), path
		if path.starts_with('tests/native-android-tools/androidtools/') {
			assert source == os.read_file(f + 'sources/androidtools/' + os.base(path))!, path
		}
	}
	jar := sha256.sum(os.read_bytes(f + 'api-impl.jar')!).hex()
	assert jar == manifest['output_sha256']!.str()
	assert jar == '02aee982892b05c5f950e63d5a5652813386dd48d2532063ba02f90cdf8b75b1'
	native := sha256.sum(os.read_bytes(b + 'libnative235.so')!).hex()
	assert native == '0d6b3cd8dfa5c7f109b1fb5305eac54d1b90f40ffc764a94359d19061345aad9'
	identities := json2.decode[map[string]string](os.read_file(b + 'identity240-inputs/pre-run-sha256.json')!)!
	assert identities.len == 7
	assert identities[b + 'suite239-stream'] == sha256.sum(os.read_bytes(b + 'suite239-stream')!).hex()
	for name in ['vinix', 'limine.conf'] {
		assert sha256.sum(os.read_bytes(b + 'identity240-inputs/' + name)!).hex() == identities['boot/' + name]!
	}
	for _, digest in identities { assert digest.len == 64 }
	println('MAPS240 FROZEN INPUTS PASS sources109 framework=' + jar + ' native235=' + native)
	println('MAPS240 PRE-RUN IDENTITIES PASS 7 hashes with retained kernel and limine.conf')
}
