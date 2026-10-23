import os
import json2
import compress.gzip
import crypto.sha256

fn main() {
	b := 'build/android-maps/'
	f := b + 'framework242-canvas-save/'
	manifest := json2.decode[map[string]json2.Any](os.read_file(f + 'framework-manifest.json')!)!
	declared := manifest['sources']!.as_map()
	sources := json2.decode[map[string]string](gzip.decompress(os.read_bytes(f + 'exact-sources.json.gz')!)!.bytestr())!
	assert sources.len == 111 && declared.len == 111
	for path, source in sources {
		assert sha256.sum(source.bytes()).hex() == declared[path]!.str(), path
		if path.starts_with('tests/native-android-tools/androidtools/') {
			assert source == os.read_file(f + 'sources/androidtools/' + os.base(path))!, path
		}
	}
	jar := sha256.sum(os.read_bytes(f + 'api-impl.jar')!).hex()
	assert jar == manifest['output_sha256']!.str()
	assert jar == '8e6eb74104871e7b3391a75bd5160c0b74bb1951a45ab9b6626a26e46c965f74'
	native := sha256.sum(os.read_bytes(b + 'libnative235.so')!).hex()
	assert native == '0d6b3cd8dfa5c7f109b1fb5305eac54d1b90f40ffc764a94359d19061345aad9'
	identities := json2.decode[map[string]string](os.read_file(b + 'identity242-inputs/pre-run-sha256.json')!)!
	assert identities.len == 7
	assert identities[b + 'suite239-stream'] == sha256.sum(os.read_bytes(b + 'suite239-stream')!).hex()
	for name in ['vinix', 'limine.conf'] {
		assert sha256.sum(os.read_bytes(b + 'identity242-inputs/' + name)!).hex() == identities['boot/' + name]!
	}
	for _, digest in identities { assert digest.len == 64 }
	println('MAPS242 FROZEN INPUTS PASS sources111 framework=' + jar + ' native235=' + native)
	println('MAPS242 PRE-RUN IDENTITIES PASS 7 hashes with retained kernel and limine.conf')
}
