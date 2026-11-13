// SPDX-License-Identifier: GPL-2.0-or-later
// Exercise actual controller admission; candidates are deliberately incomplete.
module main

import crypto.sha256
import hwhost
import json2
import os
import time
import tests.packages.wineoverlay

#include <sys/stat.h>
#define wine_receipt_test_fifo mkfifo
fn C.wine_receipt_test_fifo(&char, u32) int

const runner_path = 'prepared/x86_64/runtime/bin/wine-runner'
const receipt_files = ['owned-manager.json', 'outputs.json', 'logs/v.log.argv.json', runner_path]

fn invoke(argv []string, log string, pass bool, wanted string) ! {
	os.write_file(log + '.argv.json', json2.encode(argv))!
	mut child := hwhost.start_child(argv, map[string]string{}, log)!
	defer { child.stop() }
	deadline := hwhost.now_ms() + 10000
	for !child.poll() {
		if hwhost.interrupted() { return hwhost.Interrupted{} }
		if hwhost.now_ms() >= deadline { return error('receipt control timed out: ' + log) }
		time.sleep(10 * time.millisecond)
	}
	code := child.exit_code()
	os.write_file(log + '.exit.json', json2.encode({'exit_code': code}))!
	if code != (if pass { 0 } else { 1 }) || !os.read_file(log)!.contains(wanted) {
		return error('receipt control reached wrong gate: ' + log)
	}
}

fn copy_candidate(prepared string, destination string) ! {
	for name in receipt_files {
		os.mkdir_all(os.dir(destination + '/' + name))!
		wineoverlay.clone_fresh(prepared + '/' + name, destination + '/' + name)!
	}
}

fn compile_control(v string, root string, source string, output string, prod bool) ! {
	mut argv := [v, '-backend', 'c', '-gc', 'none', '-manualfree', '-path',
		'@vlib|' + root + '|' + root + '/tests/hardware-platform|@vmodules', '-o', output, source]
	if prod { argv.insert(1, '-prod') }
	os.write_file(output + '.build.log.argv.json', json2.encode(argv))!
	hwhost.run_tool(argv, map[string]string{}, output + '.build.log', 120)!
}

fn mutate(root string, name string) !string {
	mode_path := root + '/owned-manager.json'
	output_path := root + '/outputs.json'
	argv_path := root + '/logs/v.log.argv.json'
	mut mode := json2.decode[map[string]string](os.read_file(mode_path)!)!
	mut outputs := json2.decode[map[string]string](os.read_file(output_path)!)!
	mut wanted := 'owned Wine runtime build receipt differs'
	match name {
		'architecture' { mode['architecture'] = 'aarch64' }
		'mode' { mode['mode'] = 'legacy' }
		'source' { mode['runner_source_sha256'] = '0'.repeat(64) }
		'extra-field' { mode['unknown'] = 'unexpected' }
		'missing-field' { mode.delete('runner_source_sha256') }
		'marker-hash' { outputs['owned-manager.json'] = '0'.repeat(64) }
		'runner-hash' { outputs[runner_path] = '0'.repeat(64) }
		'missing-runner-hash' { outputs.delete(runner_path) }
		'runner-bytes' { os.write_file(root + '/' + runner_path, 'changed runner')! }
		'flag' { os.write_file(argv_path, json2.encode(['v', '-d', 'wine_owned_manager_extra']))! }
		'joined-flag' { os.write_file(argv_path, json2.encode(['v', '-d wine_owned_manager']))! }
		'empty-argv' { os.write_file(argv_path, '[]')!; wanted = 'compiler arguments outside bound' }
		'many-argv' { os.write_file(argv_path, json2.encode([]string{len: 513, init: 'v'}))!; wanted = 'compiler arguments outside bound' }
		'bad-mode-json' { os.write_file(mode_path, '{')!; return 'owned Wine mode JSON invalid' }
		'bad-output-json' { os.write_file(output_path, '{')!; return 'owned Wine outputs JSON invalid' }
		'bad-argv-json' { os.write_file(argv_path, '{}')!; return 'owned Wine compiler arguments JSON invalid' }
		'large-mode' { os.write_file(mode_path, 'x'.repeat(8193))!; return 'not bounded and regular' }
		'large-output' { os.write_file(output_path, 'x'.repeat(1024 * 1024 + 1))!; return 'not bounded and regular' }
		'large-argv' { os.write_file(argv_path, 'x'.repeat(65537))!; return 'not bounded and regular' }
		'empty-mode' { os.write_file(mode_path, '')!; return 'not bounded and regular' }
		'missing-mode', 'missing-output', 'missing-argv', 'missing-runner' {
			index := ['missing-mode', 'missing-output', 'missing-argv', 'missing-runner'].index(name)
			os.rm(root + '/' + receipt_files[index])!
			return 'requires captured ordinary files'
		}
		'link-mode', 'link-output', 'link-argv', 'link-runner' {
			index := ['link-mode', 'link-output', 'link-argv', 'link-runner'].index(name)
			path := root + '/' + receipt_files[index]
			os.mv(path, path + '.real')!
			os.symlink(os.file_name(path) + '.real', path)!
			return 'requires captured ordinary files'
		}
		'link-logs', 'link-bin' {
			path := root + if name == 'link-logs' { '/logs' } else { '/prepared/x86_64/runtime/bin' }
			os.mv(path, path + '-real')!
			os.symlink(os.file_name(path) + '-real', path)!
			return 'requires captured ordinary files'
		}
		'directory-output' { os.rm(output_path)!; os.mkdir(output_path)!; return 'not bounded and regular' }
		'fifo-output' {
			os.rm(output_path)!
			if C.wine_receipt_test_fifo(output_path.str, 0o600) != 0 { return error('cannot create FIFO control') }
			return 'not bounded and regular'
		}
		else { return error('unknown receipt mutation') }
	}
	if name in ['architecture', 'mode', 'source', 'extra-field', 'missing-field'] {
		os.write_file(mode_path, json2.encode(mode))!
		outputs['owned-manager.json'] = wineoverlay.digest(mode_path)!
	}
	os.write_file(output_path, json2.encode(outputs))!
	return wanted
}

fn run() ! {
	$if prod {} $else { return error('compile receipt controls with -prod') }
	if wineoverlay.digest(@FILE)! != sha256.hexhash($embed_file('wine-owned-receipt-check.v').to_string()) {
		return error('compiled receipt control source differs')
	}
	if os.args.len != 5 { return error('usage: CHECK FRESH_OUTPUT CONTROLLER V OWNED_PREPARED') }
	work := os.abs_path(os.args[1]); native := os.real_path(os.args[2]); v := os.real_path(os.args[3]); prepared := os.real_path(os.args[4])
	if os.exists(work) || os.is_link(work) { return error('fresh receipt-check output required') }
	os.mkdir_all(work)!
	root := os.real_path(os.dir(@FILE) + '/../..')
	source := root + '/tests/packages/wine-native-check.v'
	mut inputs := map[string]string{}
	for path in [@FILE, os.executable(), native, v, source, root + '/tests/packages/winesource/closure.v',
		root + '/tools/packages/wine-runner.v'] {
		inputs[path] = wineoverlay.digest(path)!
	}
	for name in receipt_files { inputs[prepared + '/' + name] = wineoverlay.digest(prepared + '/' + name)! }
	os.write_file(work + '/inputs-before.json', json2.encode(inputs))!
	invoke([native, '--check-owned-build', 'x86_64', prepared], work + '/baseline.log', true, 'WINE OWNED BUILD PREFLIGHT PASS')!
	stale_source := work + '/stale-source/wine-native-check.v'
	os.mkdir_all(work + '/stale-source/winesource')!
	os.cp(source, stale_source)!
	os.cp(source, work + '/stale-source-before.v')!
	os.cp(root + '/tests/packages/winesource/closure.v', work + '/stale-source/winesource/closure.v')!
	stale := work + '/stale-controller'
	nonprod := work + '/nonprod-controller'
	compile_control(v, root, stale_source, stale, true)!
	compile_control(v, root, source, nonprod, false)!
	os.write_file(stale_source, os.read_file(stale_source)! + '\n// intentional stale-source control\n')!
	invoke([stale, '--check-owned-build', 'x86_64', prepared], work + '/stale.log', false, 'compiled Wine native controller source differs')!
	invoke([nonprod, '--check-owned-build', 'x86_64', prepared], work + '/nonprod.log', false, 'compile Wine native controller with -prod')!
	invoke([native, '--check-owned-build', 'aarch64', prepared], work + '/arm.log', false, 'requires x86_64')!
	mut count := 0
	for name in ['architecture', 'mode', 'source', 'extra-field', 'missing-field', 'marker-hash',
		'runner-hash', 'missing-runner-hash', 'runner-bytes', 'flag', 'joined-flag', 'empty-argv', 'many-argv',
		'bad-mode-json', 'bad-output-json', 'bad-argv-json', 'large-mode', 'large-output', 'large-argv',
		'empty-mode', 'missing-mode', 'missing-output', 'missing-argv', 'missing-runner',
		'link-mode', 'link-output', 'link-argv', 'link-runner', 'link-logs', 'link-bin', 'directory-output', 'fifo-output'] {
		candidate := work + '/' + name
		copy_candidate(prepared, candidate)!
		wanted := mutate(candidate, name)!
		invoke([native, '--check-owned-build', 'x86_64', candidate], candidate + '.preflight.log', false, wanted)!
		output := candidate + '-native'
		invoke([native, 'x86_64', output, candidate, '/missing', '/missing', '/missing', '/missing', '/missing', '--owned-manager'], candidate + '.native.log', false,
			if name == 'missing-mode' { 'ownership modes differ' } else { wanted })!
		if os.exists(output) && os.ls(output)!.len != 0 { return error('receipt refusal created signing/build output') }
		if name == 'fifo-output' {
			// A stopped FIFO has no evidence payload. Keep its metadata and the
			// refusal logs, then retire the IPC node so the bundle is archivable.
			os.write_file(candidate + '/retired-fifo.json', json2.encode(os.lstat(candidate + '/outputs.json')!))!
			os.rm(candidate + '/outputs.json')!
		}
		count++
	}
	for kind in ['directory', 'broken-link', 'fifo'] {
		candidate := work + '/default-' + kind
		os.mkdir(candidate)!
		marker := candidate + '/owned-manager.json'
		if kind == 'directory' { os.mkdir(marker)! }
		else if kind == 'broken-link' { os.symlink('absent', marker)! }
		else if C.wine_receipt_test_fifo(marker.str, 0o600) != 0 { return error('cannot create marker FIFO') }
		output := candidate + '-native'
		invoke([native, 'x86_64', output, candidate, '/missing', '/missing', '/missing', '/missing', '/missing'], candidate + '.log', false, 'ownership modes differ')!
		if os.exists(output) && os.ls(output)!.len != 0 { return error('default mode admitted a nonregular ownership marker') }
		if kind == 'fifo' {
			os.write_file(candidate + '/retired-fifo.json', json2.encode(os.lstat(marker)!))!
			os.rm(marker)!
		}
	}
	invoke([native, '--check-owned-build', 'x86_64', prepared], work + '/baseline-after.log', true, 'WINE OWNED BUILD PREFLIGHT PASS')!
	for path, hash in inputs { if wineoverlay.digest(path)! != hash { return error('receipt control input changed: ' + path) } }
	os.write_file(work + '/inputs-verified.json', json2.encode(inputs))!
	println('WINE OWNED RECEIPT PASS ' + count.str() + ' mutations through preflight and actual controller, source/build/architecture and nonregular default-mode controls')
}

fn main() {
	hwhost.watch_interrupts()
	run() or { eprintln(err); exit(1) }
}
