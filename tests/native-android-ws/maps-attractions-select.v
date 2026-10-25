// SPDX-License-Identifier: GPL-2.0-or-later
// Select actual Maps classes from its retained qualified DEX inputs.
module main

import crypto.sha256
import json2
import os

const cache = '/Users/alex/.local/state/vinix/android/nine-patch-tint-sourceproof315-qualified-2026-10-25'
const seal = '3fc905f97a238bd3916840b8ee4ec3ac3e172117d59ed29a1049ffd16169740b'
const java = '/opt/homebrew/Cellar/openjdk@25/25.0.4.1/libexec/openjdk.jdk/Contents/Home/bin/java'
const tools = 'build/android-framework/tools'

fn hash(path string) !string {
	mut file := os.open(path)!
	defer { file.close() }
	mut digest := sha256.new()
	mut buffer := []u8{len: 1024 * 1024}
	for {
		n := file.read(mut buffer) or {
			if err is os.Eof { break }
			return err
		}
		if n == 0 { break }
		digest.write(buffer[..n])!
	}
	return digest.sum([]u8{}).hex()
}

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
			else { return error('nonregular selector evidence: ' + path) }
		}
	}
}

fn main() {
	$if prod {
		panic('assertions required')
	}
	assert os.args.len >= 5, 'OUT BUILD_ROOT BUILD_SEAL CLASS [CLASS ...] (bare descriptors)'
	out := os.abs_path(os.args[1])
	build := os.abs_path(os.args[2])
	assert hash(build + '/sha256.json')! == os.args[3]
	built := json2.decode[map[string]string](os.read_file(build + '/sha256.json')!)!
	assert hash(os.executable())! == built['selector']!
	assert hash('tests/native-android-ws/maps-attractions-select.v')! == built['source/selector.v']!
	assert !os.exists(out) && !os.is_link(out)
	assert hash(cache + '/sha256.json')! == seal
	reference := json2.decode[map[string]string](os.read_file(cache + '/sha256.json')!)!
	mut wanted := []string{}
	for name in os.args[4..] {
		assert name != '' && !name.starts_with('/') && !name.contains(';') && !name.contains(',') && !name.contains('..')
		assert 'L' + name + ';' !in wanted
		wanted << 'L' + name + ';'
	}
	os.mkdir_all(out + '/selected')!
	os.cp('tests/native-android-ws/maps-attractions-select.v', out + '/selector.v')!
	os.cp(os.executable(), out + '/selector')!
	os.cp(build + '/sha256.json', out + '/selector-build-sha256.json')!
	os.cp(cache + '/sha256.json', out + '/dex-origin-sha256.json')!
	for name in ['inputs.json', 'maps-dex-extract-receipt.json'] {
		assert hash(cache + '/' + name)! == reference[name]!
		os.cp(cache + '/' + name, out + '/dex-origin-' + name)!
	}
	mut inputs := map[string]string{}
	inputs[java] = hash(java)!
	os.mkdir_all(out + '/tools/jars')!
	os.cp(java, out + '/tools/java')!
	for name in os.ls(tools)!.filter(it.ends_with('.jar')) {
		inputs[os.abs_path(tools + '/' + name)] = hash(tools + '/' + name)!
		os.cp(tools + '/' + name, out + '/tools/jars/' + name)!
		assert hash(out + '/tools/jars/' + name)! == inputs[os.abs_path(tools + '/' + name)]!
	}
	for index in 1 .. 11 {
		name := if index == 1 { 'classes.dex' } else { 'classes' + index.str() + '.dex' }
		path := cache + '/entries/' + name
		inputs[path] = hash(path)!
		assert inputs[path]! == reference['entries/' + name]!
		argv := [java, '-cp', out + '/tools/jars/*', 'org.jf.baksmali.Main', 'disassemble', '--jobs',
			'2', '--classes', wanted.join(','), '-o', out + '/selected', path]
		result := os.exec(argv)
		save(out + '/' + name + '-command.json', {
			'argv':      json2.Any(argv)
			'exit_code': json2.Any(result.exit_code)
			'output':    json2.Any(result.output)
		})!
		assert result.exit_code == 0, result.output
	}
	assert hash(out + '/tools/java')! == inputs[java]!
	for path, pin in inputs {
		assert hash(path)! == pin, path
	}
	save(out + '/inputs.json', inputs)!
	save(out + '/requested.json', wanted)!
	mut selected := map[string]string{}
	inventory(out + '/selected', '', mut selected)!
	assert selected.len == wanted.len
	for name in os.args[4..] {
		assert name + '.smali' in selected, name
	}
	save(out + '/selected.json', selected)!
	mut all := map[string]string{}
	inventory(out, '', mut all)!
	save(out + '/sha256.json', all)!
	println('MAPS-SELECTED-PASS classes=' + selected.len.str() + ' manifest=' + hash(out + '/sha256.json')!)
}
