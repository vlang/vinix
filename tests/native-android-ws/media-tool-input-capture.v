module main

import crypto.sha256
import json2
import os

fn digest(path string) !string {
	mut file := os.open(path)!
	defer { file.close() }
	mut hash := sha256.new()
	mut bytes := []u8{len: 1024 * 1024}
	for {
		n := file.read(mut bytes) or {
			if err is os.Eof { break }
			return err
		}
		if n == 0 { break }
		hash.write(bytes[..n])!
	}
	return hash.sum([]u8{}).hex()
}

fn main() {
	if os.args.len < 4 { panic('usage: capture-inputs FRESH_CLOSURE INPUT_LIST...') }
	run() or { eprintln(err); exit(1) }
}

fn run() ! {
	root := os.args[1]
	if os.exists(root) || os.is_link(root) || os.real_path(os.dir(root)) != os.dir(root) {
		return error('fresh canonical output required')
	}
	mut selected := map[string]bool{}
	for listing in os.args[2..] {
		for path in os.read_file(listing)!.split_into_lines() {
			if path != '' { selected[path] = true }
		}
	}
	for path in ['/Users/alex/code/v-tccbin-bootstrap-20261026/v', '/usr/bin/cc', '/usr/bin/make',
		'/Library/Developer/CommandLineTools/usr/bin/clang', os.executable(), @FILE] {
		selected[path] = true
	}
	if selected.len == 0 || selected.len > 20000 { return error('bounded closure required') }
	mut names := selected.keys()
	names.sort()
	os.mkdir(root, mode: 0o700)!
	mut pins := map[string]string{}
	mut resolved := map[string]string{}
	for path in names {
		if !path.starts_with('/') || path.contains_any('\x00\r\n') { return error('absolute input required') }
		actual := os.real_path(path)
		if os.lstat(actual)!.get_filetype() != .regular { return error('regular input required: ' + path) }
		pin := digest(actual)!
		target := root + '/files/' + path.trim_left('/')
		os.mkdir_all(os.dir(target), mode: 0o700)!
		os.cp(actual, target)!
		if digest(target)! != pin || digest(actual)! != pin || os.real_path(path) != actual {
			return error('input changed while capturing: ' + path)
		}
		pins[path] = pin
		resolved[path] = actual
	}
	os.write_file(root + '/inputs.json', json2.encode(pins, prettify: true) + '\n')!
	os.write_file(root + '/resolved.json', json2.encode(resolved, prettify: true) + '\n')!
	println('CAPTURE-INPUTS PASS files=' + pins.len.str())
}
