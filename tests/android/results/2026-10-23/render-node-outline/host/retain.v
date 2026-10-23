import os
import json2
import crypto.sha256
import compress.gzip

struct HostRetention {
	result                        string
	baseline_path_clipping_sha256 string
	fixed_path_clipping_sha256    string
	source_sha256                 map[string]string
	artifacts                     map[string]string
	qualification                 string
}

fn hash(path string) !string {
	return sha256.sum(os.read_bytes(path)!).hex()
}

fn main() {
	input := 'build/android-maps/path228'
	out := os.dir(@FILE)
	baseline := hash(input + '/baseline-source/path_clipping.v')!
	fixed := hash(input + '/source/path_clipping.v')!
	assert baseline == '7038637cee5bc0671cbd74f4cff597119a66a621cfd9309376068496b295a9fe'
	assert fixed == '5363c9d9431f1c830e1d04be52343b98bef516ee6b6b6bc7bcd2eeb5a34c99ef'
	for name in ['asan-run-final.log', 'counted-run-final.log'] {
		body := os.read_file(input + '/' + name)!
		assert body.contains('PATH-CLIP-PASS finite huge triangle does not overflow crossings')
		assert body.contains('PATH-CLIP-PASS 64 saved clip levels')
		assert !body.contains('AddressSanitizer:') && !body.contains('FAIL:')
	}
	assert os.read_file(input + '/counted-run-final.log')!.contains('allocated=8177 released=8177')
	assert os.read_file(input + '/huge-run-baseline.log')!.contains('right value: 1')
	assert os.read_file(input + '/raw/path_clipping.v')! == os.read_file(input + '/source/path_clipping.v')!.replace('module atlframework', 'module main')
	assert os.read_file(input + '/raw-huge/path_clipping.v')! == os.read_file(input + '/baseline-source/path_clipping.v')!.replace('module atlframework', 'module main')
	mut sources := map[string]string{}
	mut source_hashes := map[string]string{}
	for folder in ['baseline-source', 'source', 'raw', 'counted', 'raw-huge'] {
		for path in os.walk_ext(input + '/' + folder, '') {
			name := path.all_after(input + '/')
			sources[name] = os.read_file(path)!
			source_hashes[name] = hash(path)!
		}
	}
	os.write_file_array(out + '/sources.json.gz', gzip.compress(json2.encode(sources).bytes())!)!
	for name in ['build_host.v', 'build_huge.v', 'harness.v.txt', 'huge_case.v.txt',
		'asan-build-final.log', 'counted-build-final.log', 'asan-run-final.log', 'counted-run-final.log',
		'huge-build.log', 'huge-run-baseline.log'] {
		os.cp(input + '/' + name, out + '/' + name)!
	}
	os.cp(input + '/retain.v', out + '/validate-live-proof.v')!
	os.cp(input + '/receipt.json', out + '/host-proof.json')!
	mut artifacts := map[string]string{}
	for path in os.walk_ext(out, '') {
		if os.base(path) == 'retention.json' { continue }
		artifacts[path.all_after(out + '/')] = hash(path)!
	}
	receipt := HostRetention{
		result:                        'PASS: baseline huge-triangle failure; final raw and counted ASAN suites'
		baseline_path_clipping_sha256: baseline
		fixed_path_clipping_sha256:    fixed
		source_sha256:                 source_hashes
		artifacts:                     artifacts
		qualification:                 'sources.json.gz contains text-only exact production snapshots and generated harness sources. Raw mode changes only the module declaration of clipping code. Counted mode additionally wraps clipping C allocators for failure injection and exact accounting. Both final suites ran with AddressSanitizer and detect_leaks=0; no invalid-access diagnostics. All 8177 successful clipping allocations were freed. This host proof does not replace guest/JNI/rendering integration tests. No executable binaries retained.'
	}
	os.write_file(out + '/retention.json', json2.encode(receipt, prettify: true) + '\n')!
	println('Retained host proof: ' + fixed)
}
