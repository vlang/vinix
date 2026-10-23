module main

import os
import json2
import crypto.sha256

struct Receipt {
	result string
	baseline_path_clipping_sha256 string
	fixed_path_clipping_sha256 string
	compiler string
	commands []string
	asan_options string
	qualification string
	allocation_result string
	artifacts map[string]string
}

fn digest(path string) !string {
	return sha256.sum(os.read_bytes(path)!).hex()
}

fn main() {
	dir := os.getwd() + '/build/android-maps/path228'
	assert os.read_file(dir + '/huge-run-baseline.log')!.contains('right value: 1')
	for name in ['asan-run-final.log', 'counted-run-final.log'] {
		log := os.read_file(dir + '/' + name)!
		assert log.contains('PATH-CLIP-PASS finite huge triangle does not overflow crossings')
		assert log.contains('PATH-CLIP-PASS 64 saved clip levels')
		assert !log.contains('AddressSanitizer:')
		assert !log.contains('FAIL:')
	}
	assert os.read_file(dir + '/counted-run-final.log')!.contains('allocated=8177 released=8177')
	mut artifacts := map[string]string{}
	for name in ['build_host.v', 'build_huge.v', 'harness.v.txt', 'huge_case.v.txt',
		'baseline-source/path_clipping.v', 'source/path_clipping.v', 'source/graphics.v',
		'source/affine.v', 'source/paths.v', 'source/canvases.v', 'raw/main.v',
		'raw/path_clipping.v', 'raw/actual_support.v', 'counted/main.v',
		'counted/path_clipping.v', 'counted/actual_support.v', 'raw-huge/main.v',
		'raw-huge/path_clipping.v', 'raw-huge/actual_support.v',
		'asan-build-final.log', 'counted-build-final.log', 'asan-run-final.log',
		'counted-run-final.log', 'huge-build.log', 'huge-run-baseline.log'] {
		artifacts[name] = digest(dir + '/' + name)!
	}
	receipt := Receipt{
		result: 'PASS: real-source ASAN and counted allocator suites; finite huge triangle baseline fails and fixed passes'
		baseline_path_clipping_sha256: digest(dir + '/baseline-source/path_clipping.v')!
		fixed_path_clipping_sha256: digest(dir + '/source/path_clipping.v')!
		compiler: '/Users/alex/code/v/v_old 0.5.2 b5bcdbb; /usr/bin/clang'
		commands: [
			'/Users/alex/code/v/v_old -nocache -cc cc run build/android-maps/path228/build_host.v raw',
			'/Users/alex/code/v/v_old -nocache -cc cc run build/android-maps/path228/build_host.v counted',
			'/Users/alex/code/v/v_old -nocache -cc clang -gc none -enable-globals -cflags "-fsanitize=address -fno-omit-frame-pointer" -ldflags "-fsanitize=address" -o build/android-maps/path228/host-clip-asan build/android-maps/path228/raw',
			'/Users/alex/code/v/v_old -nocache -cc clang -gc none -enable-globals -cflags "-fsanitize=address -fno-omit-frame-pointer" -ldflags "-fsanitize=address" -o build/android-maps/path228/host-clip-counted build/android-maps/path228/counted',
			'ASAN_OPTIONS=detect_leaks=0:halt_on_error=1 build/android-maps/path228/host-clip-asan',
			'ASAN_OPTIONS=detect_leaks=0:halt_on_error=1 build/android-maps/path228/host-clip-counted',
		]
		asan_options: 'detect_leaks=0:halt_on_error=1'
		qualification: 'Raw mode compiles the actual frozen clipping source with only module adaptation, plus extracted actual transform/affine/save/restore code and small state/JNI/path stubs. Counted mode changes only clipping allocator call names to counters with allocation-failure injection, then calls real C allocators. ASAN checks invalid accesses, use-after-free and double-free; global leak detection is disabled because the V harness uses unmanaged runtime allocations. Exact clipping allocation accounting independently verifies all clipping nodes/vertices are freed. Full guest/JNI pixel integration is a separate paired fixture.'
		allocation_result: '8177 successful clipping allocations, 8177 frees, zero remaining; both calloc-node and malloc-points failures tested'
		artifacts: artifacts
	}
	os.write_file(dir + '/receipt.json', json2.encode(receipt, prettify: true))!
	println('Retained path228/receipt.json: ' + receipt.fixed_path_clipping_sha256)
}
