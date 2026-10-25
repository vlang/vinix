// SPDX-License-Identifier: GPL-2.0-or-later
// Retain the selected-class reader's compiler, V closure, generated C and receipt.
module main

import crypto.sha256
import json2
import os
import time

const compiler = 'build/android-maps/queue284-tools/v_old276'
const compiler_pin = '109a0bad877cf42cd19382a87d3e3d62e9c153e3d74a566b2b3e650a1aec318e'
const selector = 'tests/native-android-ws/maps-attractions-select.v'

fn hash(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }

fn save[T](path string, value T) ! {
	os.write_file(path, json2.encode(value, prettify: true) + '\n')!
}

fn inventory(root string, relative string, mut pins map[string]string) ! {
	for name in os.ls(root + '/' + relative)! {
		key := if relative == '' { name } else { relative + '/' + name }
		if key == 'sha256.json' { continue }
		path := root + '/' + key
		match os.lstat(path)!.get_filetype() {
			.directory { inventory(root, key, mut pins)! }
			.regular { pins[key] = hash(path)! }
			else { return error('nonregular build evidence: ' + path) }
		}
	}
}

fn command(out string, label string, argv []string) !string {
	mut receipt := {
		'argv':                  json2.Any(argv)
		'cwd':                   json2.Any(os.getwd())
		'started_utc':           json2.Any(time.utc().str())
		'program_sha256_before': json2.Any(hash(argv[0])!)
		'VROOT':                 json2.Any(os.getenv('VROOT'))
		'VTMP':                  json2.Any(os.getenv('VTMP'))
	}
	r := os.exec(argv)
	os.write_file(out + '/' + label + '.log', r.output)!
	receipt['exit_code'] = r.exit_code
	receipt['completed_utc'] = time.utc().str()
	receipt['program_sha256_after'] = hash(argv[0])!
	save(out + '/' + label + '.json', receipt)!
	assert receipt['program_sha256_before']! == receipt['program_sha256_after']!
	assert r.exit_code == 0, r.output
	return r.output
}

fn closure(out string, label string, cc string) !map[string]string {
	listing := command(out, label, [os.abs_path(compiler), '-print-v-files', '-nocache',
		'-enable-globals', '-cc', cc, out + '/source/selector.v'])!
	mut pins := map[string]string{}
	for line in listing.split_into_lines() {
		path := line.trim_space()
		if path.ends_with('.v') {
			assert path.starts_with('/') && path !in pins
			pins[path] = hash(path)!
		}
	}
	assert pins.len > 10
	save(out + '/' + label + '-hashes.json', pins)!
	return pins
}

fn main() {
	$if prod {
		panic('assertions required')
	}
	assert os.args.len == 2, 'FRESH_BUILD_ROOT'
	out := os.abs_path(os.args[1])
	assert !os.exists(out) && !os.is_link(out)
	assert hash(compiler)! == compiler_pin
	cc := os.real_path(os.find_abs_path_of_executable('cc')!)
	cc_pin := hash(cc)!
	source_pin := hash(selector)!
	os.mkdir_all(out + '/source')!
	os.mkdir_all(out + '/generated-c')!
	os.cp(selector, out + '/source/selector.v')!
	os.cp(@FILE, out + '/source/build.v')!
	os.cp(os.executable(), out + '/bootstrap')!
	os.cp(compiler, out + '/compiler')!
	os.cp(cc, out + '/cc')!
	os.setenv('VROOT', '/Users/alex/code/v', true)
	os.setenv('VTMP', out + '/generated-c', true)
	before := closure(out, 'closure-before', cc)!
	for path, pin in before {
		target := out + '/inputs/' + path.trim_left('/')
		os.mkdir_all(os.dir(target))!
		os.cp(path, target)!
		assert hash(target)! == pin
	}
	command(out, 'build', [os.abs_path(compiler), '-nocache', '-keepc', '-showcc', '-enable-globals',
		'-cc', cc, '-o', out + '/selector', out + '/source/selector.v'])!
	after := closure(out, 'closure-after', cc)!
	assert before == after
	assert hash(compiler)! == compiler_pin && hash(cc)! == cc_pin
	assert hash(selector)! == source_pin && hash(out + '/source/selector.v')! == source_pin
	assert os.walk_ext(out + '/generated-c', '.c').len > 0
	save(out + '/outputs.json', {
		'source_sha256':   source_pin
		'binary_sha256':   hash(out + '/selector')!
		'compiler_sha256': compiler_pin
		'cc_sha256':       cc_pin
	})!
	mut pins := map[string]string{}
	inventory(out, '', mut pins)!
	save(out + '/sha256.json', pins)!
	println('MAPS-ATTRACTIONS-TOOL-BUILD-PASS manifest=' + hash(out + '/sha256.json')!)
}
