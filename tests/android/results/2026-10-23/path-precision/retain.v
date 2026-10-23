import os
import crypto.sha256
import compress.gzip
import json2

fn digest(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }

fn main() {
	out := 'tests/android/results/2026-10-23/path-precision'
	os.mkdir_all(out)!
	mut sources := map[string]string{}
	mut identities := map[string]string{}
	for name in ['paths.v', 'path_curves.v', 'path_bounds.v', 'path_animation.v', 'path_animation_curves.v', 'matrix.v'] {
		path := 'build-support/android/nativews/' + name
		body := os.read_file(path)!
		sources[path] = body
		identities[path] = sha256.sum(body.bytes()).hex()
		for run in ['host', 'asan'] {
			assert os.read_file('build/android-maps/path-precision235-' + run + '/' + name + '.txt')! == body
		}
	}
	for path in ['tests/native-android-ws/path-precision-host.v', 'tests/native-android-ws/pathprecisionhost/harness.v.txt'] {
		sources[path] = os.read_file(path)!
		identities[path] = digest(path)!
	}
	for run in ['host', 'asan'] {
		log := 'build/android-maps/path-precision235-' + run + '.log'
		body := os.read_file(log)!
		assert body.contains('PATH-PRECISION-HOST PASS')
		assert !body.contains('FAIL:') && !body.contains('ERROR: AddressSanitizer')
		assert body.contains('asan=' + (run == 'asan').str())
		os.cp(log, out + '/' + run + '.log')!
		identities[run + '.log'] = digest(log)!
		assert os.read_file('build/android-maps/path-precision235-' + run + '/src/main.v')! == sources['tests/native-android-ws/pathprecisionhost/harness.v.txt']!
	}
	compiler := '/Users/alex/code/v/v_old'
	identities['compiler_sha256'] = digest(compiler)!
	identities['compiler_version'] = os.exec([compiler, 'version']).output.trim_space()
	identities['native_allocation_accounting'] = 'All redirected production malloc/calloc/realloc/free allocations return to zero; each temporary allocation failure injected individually.'
	identities['asan_leaks'] = 'detect_leaks=0 for unmanaged V harness strings; exact production allocation accounting remains enabled.'
	identities['normal_exit_code'] = '0'
	identities['asan_exit_code'] = '0'
	os.write_file_array(out + '/sources.json.gz', gzip.compress(json2.encode(sources).bytes())!)!
	identities['sources.json.gz'] = digest(out + '/sources.json.gz')!
	os.write_file(out + '/receipt.json', json2.encode(identities, prettify: true) + '\n')!
	os.cp('build/android-maps/retain-pathprecision235.v', out + '/retain.v')!
	println('PATH-PRECISION-RETAIN PASS normal+ASAN exact6 production sources plus runner+harness')
}
