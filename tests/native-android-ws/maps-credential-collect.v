// SPDX-License-Identifier: GPL-2.0-or-later
// Retain completed credential experiments without extracting or hashing media.
module main

import crypto.sha256
import json2
import net.unix
import os

fn digest(path string) !string {
	mut file := os.open(path)!
	defer { file.close() }
	mut hash := sha256.new()
	mut buffer := []u8{len: 1024 * 1024}
	for {
		n := file.read(mut buffer) or { if err is os.Eof { break }; return err }
		if n == 0 { break }
		hash.write(buffer[..n])!
	}
	return hash.sum([]u8{}).hex()
}

fn read_map(path string) !map[string]string {
	return json2.decode[map[string]string](os.read_file(path)!)!
}

fn absent(path string) {
	assert !os.exists(path) && !os.is_link(path), 'destination already exists: ' + path
}

fn copy_file(from string, to string) ! {
	absent(to)
	os.mkdir_all(os.dir(to))!
	typ := os.lstat(from)!.get_filetype()
	if typ == .symbolic_link { os.symlink(os.readlink(from)!, to)! }
	else {
		if typ != .regular { return error('not an ordinary file: ' + from) }
		$if macos {
			result := os.exec(['cp', '-c', from, to])
			assert result.exit_code == 0, result.output
		} $else { os.cp(from, to)! }
	}
}

fn validate_tree(from string, sockets bool) ! {
	assert os.lstat(from)!.get_filetype() == .directory, from
	for name in os.ls(from)! {
		path := from + '/' + name
		match os.lstat(path)!.get_filetype() {
			.regular, .symbolic_link {}
			.directory { validate_tree(path, sockets)! }
			.socket {
				if !sockets || name != 'qmp.sock' { return error('unexpected socket: ' + path) }
			}
			else { return error('unexpected special file: ' + path) }
		}
	}
}

fn copy_tree(from string, to string, sockets bool) ![]string {
	os.mkdir_all(to)!
	mut omitted := []string{}
	for name in os.ls(from)! {
		source := from + '/' + name
		target := to + '/' + name
		match os.lstat(source)!.get_filetype() {
			.regular, .symbolic_link { copy_file(source, target)! }
			.directory {
				for child in copy_tree(source, target, sockets)! { omitted << name + '/' + child }
			}
			.socket {
				if !sockets || name != 'qmp.sock' { return error('unexpected socket: ' + source) }
				omitted << name
			}
			else { return error('unexpected special file: ' + source) }
		}
	}
	return omitted
}

fn tree_self_test(root string) ! {
	assert os.is_abs_path(root) && !os.exists(root) && !os.is_link(root)
	repository := os.real_path(os.getwd())
	parent := os.real_path(os.dir(root))
	assert parent != repository && !parent.starts_with(repository + '/')
	source := root + '/source'
	os.mkdir_all(source + '/nested/empty')!
	os.write_file(source + '/.hidden', 'retained hidden bytes\n')!
	os.symlink('.hidden', source + '/relative-link')!
	os.symlink('missing', source + '/dangling-link')!
	mut listener := unix.listen_stream(source + '/nested/qmp.sock', unix.ListenOptions{})!
	validate_tree(source, true)!
	mut rejected := false
	validate_tree(source, false) or { rejected = true }
	assert rejected, 'module socket must be rejected'
	assert copy_tree(source, root + '/copy', true)! == ['nested/qmp.sock']
	assert os.read_file(root + '/copy/.hidden')! == 'retained hidden bytes\n'
	assert os.readlink(root + '/copy/relative-link')! == '.hidden'
	assert os.readlink(root + '/copy/dangling-link')! == 'missing'
	assert os.is_dir(root + '/copy/nested/empty')
	assert !os.exists(root + '/copy/nested/qmp.sock')
	listener.close()!
	fifo := os.exec(['mkfifo', source + '/nested/qmp.sock'])
	assert fifo.exit_code == 0, fifo.output
	rejected = false
	validate_tree(source, true) or { rejected = true }
	assert rejected, 'a FIFO named qmp.sock must be rejected before collection'
	rejected = false
	_ := copy_tree(source, root + '/fifo-copy', true) or { rejected = true; []string{} }
	assert rejected, 'copy must reject a FIFO without opening it'
	os.rm(source + '/nested/qmp.sock')!
	mut other := unix.listen_stream(source + '/other.sock', unix.ListenOptions{})!
	rejected = false
	validate_tree(source, true) or { rejected = true }
	assert rejected, 'only qmp.sock sockets may be omitted'
	other.close()!
	result := 'MAPS-CREDENTIAL-COLLECT SELF-TEST PASS actual qmp socket omitted; FIFO and other socket rejected; hidden bytes, relative and dangling links, empty directories retained\n'
	os.write_file(root + '/result.txt', result)!
	print(result)
}

fn frozen_file(root string, manifest map[string]string, path string) !string {
	result := root + '/inputs/' + path
	assert digest(result)! == manifest[path]!, 'frozen input differs: ' + path
	return result
}

fn collect(experiment string, requested_root string, pin string) ! {
	assert experiment.int() > 0 && experiment.int().str() == experiment, 'decimal experiment required'
	assert os.is_abs_path(requested_root) && os.is_dir(requested_root), 'existing absolute external bundle required'
	root := os.real_path(requested_root)
	repository := os.real_path(os.getwd())
	assert root != repository && !root.starts_with(repository + '/'), 'bundle must be outside the repository'
	assert pin.len == 64 && digest(root + '/frozen-inputs.json')! == pin, 'prelaunch input freeze differs'
	manifest := read_map(root + '/frozen-inputs.json')!
	base := 'build/android-maps/'
	fixture := base + 'maps' + experiment
	attempt := base + 'attempt' + experiment
	for name in ['run', 'runtime', 'media', 'toolchain'] { absent(root + '/' + name) }
	for name in ['maps-credential-collect.v', 'collection.json'] { absent(root + '/audit/' + name) }
	assert os.lstat(attempt + '/results.json')!.get_filetype() == .regular, 'wait for completed suite results'
	rows := json2.decode[[]json2.Any](os.read_file(attempt + '/results.json')!)!
	assert rows.len == 1 && rows[0].as_map()['id']!.str() == 'google-maps'
	assert os.lstat(attempt + '-harness.log')!.get_filetype() == .regular, 'complete harness stdout required'
	for name in ['omitted-special-files.json', 'harness.log'] {
		assert !os.exists(attempt + '/' + name) && !os.is_link(attempt + '/' + name), 'reserved raw filename: ' + name
	}
	validate_tree(attempt, true)!
	validate_tree(fixture + '/module', false)!
	for name in ['boot.img', 'efivars.fd'] { assert os.lstat(fixture + '/vm/' + name)!.get_filetype() == .regular }
	receipt := read_map(frozen_file(root, manifest, fixture + '/launcher-build-receipt.json')!)!
	assert digest(frozen_file(root, manifest, receipt['source_path']!)!)! == receipt['source_sha256']!
	assert digest(frozen_file(root, manifest, receipt['binary_path']!)!)! == receipt['binary_sha256']!
	mut compilers := map[string]string{}
	mut compiler_hashes := map[string]string{}
	for key, name in {'compiler': 'v_old', 'cross_compiler': 'aarch64-linux-musl-gcc'} {
		path := os.real_path(receipt[key + '_path']!)
		assert digest(path)! == receipt[key + '_sha256']!, 'build compiler identity changed: ' + path
		compilers[name] = path
		compiler_hashes[name] = receipt[key + '_sha256']!
	}
	production := read_map(frozen_file(root, manifest, fixture + '/production-launcher-receipt.json')!)!
	production_v := '/Users/alex/code/v/v'
	compilers['v_production'] = frozen_file(root, manifest, production_v)!
	compiler_hashes['v_production'] = production[production_v]!
	assert digest(compilers['v_production']!)! == compiler_hashes['v_production']!
	assert compiler_hashes['aarch64-linux-musl-gcc']! == production['/opt/homebrew/bin/aarch64-linux-musl-gcc']!
	collector_hash := digest(@FILE)!
	// No media extraction, full media digest or runtime digest occurs in this phase.
	omitted := copy_tree(attempt, root + '/run', true)!
	os.write_file(root + '/run/omitted-special-files.json', json2.encode(omitted))!
	copy_file(attempt + '-harness.log', root + '/run/harness.log')!
	assert copy_tree(fixture + '/module', root + '/runtime', false)!.len == 0
	copy_file(fixture + '/vm/boot.img', root + '/media/boot-after-run.img')!
	copy_file(fixture + '/vm/efivars.fd', root + '/media/efivars-after-run.fd')!
	for name, path in compilers {
		copy_file(path, root + '/toolchain/' + name)!
		assert digest(root + '/toolchain/' + name)! == compiler_hashes[name]!
	}
	copy_file(@FILE, root + '/audit/maps-credential-collect.v')!
	assert digest(root + '/audit/maps-credential-collect.v')! == collector_hash
	os.write_file(root + '/audit/collection.json', json2.encode({
		'experiment': experiment
		'frozen_inputs_sha256': pin
		'collector_source_sha256': collector_hash
		'scope': 'Clone-only retention of complete ordinary raw files, hidden files, symlinks, module and post-run private media. Listed qmp.sock IPC endpoints are omitted. Compiler bytes match frozen receipts. No media extraction, complete inventory audit, launch identity measurement or functional pass is inferred.'
	}, prettify: true) + '\n')!
	println('MAPS${experiment} COLLECTED raw, harness, runtime, media, compiler identities and collector source; full audit remains required')
}

fn main() {
	$if prod {
		eprintln('Maps credential collection requires assertions; compile without -prod')
		exit(2)
	}
	if os.args.len == 3 && os.args[1] == '--tree-self-test' { tree_self_test(os.args[2])!; return }
	if os.args.len != 4 { panic('usage: maps-credential-collect EXP EXTERNAL_BUNDLE FROZEN_MANIFEST_SHA256 | --tree-self-test FRESH_EXTERNAL_DIRECTORY') }
	collect(os.args[1], os.args[2], os.args[3])!
}
