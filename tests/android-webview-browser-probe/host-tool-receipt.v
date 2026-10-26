// SPDX-License-Identifier: GPL-2.0-or-later
// Capture source, optimization, executable and test receipts for existing host builds.
module main

import crypto.sha256
import json2
import os

const pinned_compiler_sha = '109a0bad877cf42cd19382a87d3e3d62e9c153e3d74a566b2b3e650a1aec318e'

struct Tool {
	name           string
	source         string
	source_sha256  string
	executable_sha256 string
	build_log_sha256 string
	self_test_log_sha256 string
}

struct Receipt {
	format int = 1
	kind string = 'vinix-optimized-browser-host-tools-v1'
	source_revision string
	compiler string
	compiler_sha256 string
	optimization string = '-prod -cc clang; retained clang commands require -O3 -flto'
	tools []Tool
	retained_link_objects map[string]string
	qualification string = 'Unchanged entry sources and existing self-tests; no guest or Google login result. The original complete compiler dependency bundle remains required; this receipt is not a complete compiler source closure.'
}

fn digest(path string) !string {
	return sha256.sum256(os.read_bytes(path)!).hex()
}

fn capture(root string, compiler string, native_sha bool) ! {
	if os.real_path(root) != root || !os.is_dir(root) || os.is_link(root)
		|| root.starts_with(os.getwd() + '/') || os.exists(root + '/build.json') {
		return error('fresh external canonical build directory required')
	}
	if digest(compiler)! != pinned_compiler_sha { return error('pinned old V compiler mismatch') }
	git := os.exec(['git', 'rev-parse', 'HEAD'])
	if git.exit_code != 0 || git.output.trim_space().len != 40 { return error('source revision') }
	mut tools := []Tool{}
	mut objects := map[string]string{}
	mut pins := {
		'patch-kernel': '1cc14f493bef51f955d85252c543ab3722c3d3fc7fe9851ad73a938741968a0d'
		'run': '7953d7540600aa37daa3b721eaa974c3d08d1fb9b687fe362d521f986bbbcfd9'
		'seal': '9b990d6c2bc849f7732a8e18662f84564dc8adb833f148888004e628c28cec6a'
	}
	if native_sha {
		pins = {
			'patch-kernel': '2186c55bfc784169d923cd4e83e0e2911850b9f81a32a807d8acc82a2cd9d3a1'
			'run': 'f8e15d06651efaafee55c0ee92093b577d9f7dfd800c17dee01ebd1fe7b64741'
		}
	}
	os.mkdir(root + '/source')!
	os.mkdir(root + '/link-objects')!
	for name, expected in pins {
		path := 'tests/android-webview-browser-probe/' + name + '.v'
		source := os.read_file(path)!
		if digest(path)! != expected || !os.read_file(root + '/' + name)!.contains(source) {
			return error('entry source or exact embedded source mismatch: ' + name)
		}
		log := os.read_file(root + '/' + name + '-build.log')!
		if !log.contains('clang -std=gnu11 -O3 -flto ') { return error('optimization receipt missing') }
		test_log := os.read_file(root + '/' + name + '-self-test.log')!
		if !test_log.contains('SELF-TEST PASS ') || !test_log.contains('real ') {
			return error('self-test receipt missing: ' + name)
		}
		if native_sha && test_log.split_into_lines().filter(it == 'HOST-SHA256 SELF-TEST PASS known-vectors block-padding streaming-boundaries V-reference').len != 1 {
			return error('native SHA256 regression receipt missing: ' + name)
		}
		os.write_file(root + '/source/' + name + '.v', source)!
		for word in log.split_any(' \n\t') {
			if word.starts_with('/') && word.ends_with('.o') && os.is_file(word) {
				pin := digest(word)!
				objects[word] = pin
				if !os.exists(root + '/link-objects/' + pin + '.o') {
					os.cp(word, root + '/link-objects/' + pin + '.o')!
				}
			}
		}
		tools << Tool{
			name: name
			source: path
			source_sha256: expected
			executable_sha256: digest(root + '/' + name)!
			build_log_sha256: digest(root + '/' + name + '-build.log')!
			self_test_log_sha256: digest(root + '/' + name + '-self-test.log')!
		}
	}
	os.write_file(root + '/build.json', json2.encode(Receipt{
		kind: if native_sha { 'vinix-native-sha-browser-host-tools-v1' } else { 'vinix-optimized-browser-host-tools-v1' }
		source_revision: git.output.trim_space()
		compiler: compiler
		compiler_sha256: pinned_compiler_sha
		tools: tools
		retained_link_objects: objects
		qualification: if native_sha {
			'Darwin CommonCrypto streaming SHA256 entry sources, V reference digest regressions and existing validation self-tests; no guest or Google login result. The original complete compiler dependency bundle remains required; this receipt is not a complete compiler source closure.'
		} else {
			'Unchanged entry sources and existing self-tests; no guest or Google login result. The original complete compiler dependency bundle remains required; this receipt is not a complete compiler source closure.'
		}
	}) + '\n')!
	println('BROWSER-HOST-TOOLS RECEIPT PASS ' + digest(root + '/build.json')!)
}

fn main() {
	native_sha := os.args.len == 4 && os.args[1] == '--native-sha'
	if os.args.len != 3 && !native_sha {
		eprintln('usage: host-tool-receipt [--native-sha] EXTERNAL_BUILD_DIRECTORY PINNED_OLD_V')
		exit(2)
	}
	offset := if native_sha { 1 } else { 0 }
	capture(os.args[1 + offset], os.args[2 + offset], native_sha) or {
		eprintln(err)
		exit(1)
	}
}
