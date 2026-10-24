import os
import json2
import compress.gzip
import crypto.sha256

fn main() {
	b := 'build/android-maps/'
	f := b + 'framework244-action-provider/'
	manifest := json2.decode[map[string]json2.Any](os.read_file(f + 'framework-manifest.json')!)!
	declared := manifest['sources']!.as_map()
	sources := json2.decode[map[string]string](gzip.decompress(os.read_bytes(f + 'exact-sources.json.gz')!)!.bytestr())!
	assert sources.len == 113 && declared.len == 113
	for path, source in sources {
		assert sha256.sum(source.bytes()).hex() == declared[path]!.str(), path
		if path.starts_with('tests/native-android-tools/androidtools/') {
			assert source == os.read_file(f + 'sources/androidtools/' + os.base(path))!, path
		}
	}
	jar := sha256.sum(os.read_bytes(f + 'api-impl.jar')!).hex()
	assert jar == manifest['output_sha256']!.str()
	assert jar == '933fc7db4267d123a33bb1e4e064ea3b69450fd065bb4d8e4f5898b91cf842b8'
	native := sha256.sum(os.read_bytes(b + 'libnative236.so')!).hex()
	assert native == '78da0707dc12d4cc8a55e3b3efa3e94ee202ec5c36babbf2470f259423a59d3d'
	identities := json2.decode[map[string]string](os.read_file(b + 'identity244-inputs/pre-run-sha256.json')!)!
	assert identities.len == 7
	assert identities[b + 'suite239-stream'] == sha256.sum(os.read_bytes(b + 'suite239-stream')!).hex()
	for name in ['vinix', 'limine.conf'] {
		assert sha256.sum(os.read_bytes(b + 'identity244-inputs/' + name)!).hex() == identities['boot/' + name]!
	}
	for _, digest in identities { assert digest.len == 64 }
	println('MAPS244 FROZEN INPUTS PASS sources113 framework=' + jar + ' native236=' + native)
	println('MAPS244 PRE-RUN IDENTITIES PASS 7 hashes with retained kernel and limine.conf')
}
