module androidhost

import encoding.hex
import json2
import os

fn remove_fixture(path string) ! {
	if os.is_link(path) || !os.is_dir(path) {
		os.rm(path)!
		return
	}
	for name in os.ls(path)! { remove_fixture(path_join(path, name))! }
	os.rmdir(path)!
}

fn runtime_fixture() !map[string]Value {
	return json2.decode[Value](os.read_file(path_join(os.dir(@FILE), 'testdata/runtime.json'))!)!.object()
}

fn fixture_overlay(directory string, fixture map[string]Value) !string {
	overlay := path_join(directory, 'overlay')
	mkdir_parents(overlay)!
	for value in field(field(fixture, 'manifest').object(), 'files').items() {
		name := field(value.object(), 'path').text()
		path := path_join(overlay, name)
		mkdir_parents(path_parent(path))!
		os.write_file_array(path, hex.decode(field(fixture, if name.ends_with('.h') {
			'header'
		} else {
			'elf'
		}).text())!)!
		os.chmod(path, if name.ends_with('.h') { 0o644 } else { 0o755 })!
	}
	return overlay
}

fn test_original_runtime_fixture_validates_and_replaces_hardlinks() {
	directory := path_join(os.temp_dir(), 'vinix-android-install-${os.getpid()}')
	mkdir_parents(directory)!
	defer { remove_fixture(directory) or { panic(err) } }
	fixture := runtime_fixture()!
	manifest := field(fixture, 'manifest')
	overlay := fixture_overlay(directory, fixture)!
	support := path_parent(os.dir(@FILE))
	assert validate_runtime(overlay, support, manifest, false, false)!.len == 24
	runtime := path_join(directory, 'runtime')
	target := path_join(runtime, 'usr/lib/art/libart.so')
	mkdir_parents(path_parent(target))!
	os.write_file(target, 'original runtime')!
	alias := path_join(directory, 'old-alias.so')
	os.link(target, alias)!
	install_runtime(overlay, runtime, manifest, false, false)!
	assert os.read_file(alias)! == 'original runtime'
	assert os.read_bytes(target)! == hex.decode(field(fixture, 'elf').text())!
	assert os.stat(target)!.inode != os.stat(alias)!.inode
	assert os.stat(path_join(runtime, art_headers[0]))!.mode & 0o777 == 0o644
	assert os.walk_ext(runtime, '').all(!os.file_name(it).starts_with('.vinix-art-'))
}

fn test_destination_preflight_checks_all_parents_before_publication() {
	directory := path_join(os.temp_dir(), 'vinix-android-preflight-${os.getpid()}')
	mkdir_parents(directory)!
	defer { remove_fixture(directory) or { panic(err) } }
	fixture := runtime_fixture()!
	overlay := fixture_overlay(directory, fixture)!
	runtime := path_join(directory, 'runtime')
	target := path_join(runtime, 'usr/lib/art/libart.so')
	mkdir_parents(path_parent(target))!
	os.write_file(target, 'untouched')!
	outside := path_join(directory, 'outside')
	mkdir_parents(outside)!
	os.symlink(outside, path_join(runtime, 'usr/bin'))!
	mut failed := false
	install_runtime(overlay, runtime, field(fixture, 'manifest'), false, false) or {
		assert err.msg() == 'ART overlay has a symlink parent: ' + path_join(runtime, 'usr/bin')
		failed = true
	}
	assert failed
	assert os.read_file(target)! == 'untouched'
	assert os.ls(outside)! == []string{}
}

fn test_literal_backslashes_missing_parents_and_symlink_loops() {
	directory := path_join(os.temp_dir(), 'vinix-android-paths-${os.getpid()}')
	mkdir_parents(directory)!
	defer { remove_fixture(directory) or { panic(err) } }
	root := path_join(directory, 'root\\literal')
	mkdir_parents(root)!
	assert inside(root, 'usr/back\\slash/file')! == path_join(root, 'usr/back\\slash/file')
	assert resolved_path(path_join(root, 'absent/../next'))! == path_join(resolved_path(root)!, 'next')
	loop := path_join(directory, 'loop')
	os.symlink(loop, loop)!
	mut failed := false
	inside(path_join(loop, 'child'), 'usr/file') or {
		assert err is SymlinkLoop
		assert err.path == path_join(resolved_path(directory)!, 'loop')
		failed = true
	}
	assert failed
}

fn test_failed_copy_retires_temporary_files_and_descriptors() {
	directory := path_join(os.temp_dir(), 'vinix-android-retirement-${os.getpid()}')
	mkdir_parents(directory)!
	defer { remove_fixture(directory) or { panic(err) } }
	fixture := runtime_fixture()!
	overlay := fixture_overlay(directory, fixture)!
	mut record := field(field(fixture, 'manifest').object(), 'files').items()[0].object().clone()
	record['sha256'] = Value('b'.repeat(64))
	manifest := Value(map[string]Value{
		'files': Value([Value(record)])
	})
	runtime := path_join(directory, 'runtime')
	before := os.ls('/dev/fd')!.len
	for _ in 0 .. 100 {
		mut failed := false
		install_runtime(overlay, runtime, manifest, false, false) or {
			assert err.msg() == 'ART runtime file changed during installation: usr/lib/art/libart.so'
			failed = true
		}
		assert failed
	}
	assert os.ls('/dev/fd')!.len == before
	assert os.walk_ext(runtime, '').all(!os.file_name(it).starts_with('.vinix-art-'))
	assert !os.exists(path_join(runtime, 'usr/lib/art/libart.so'))
}
