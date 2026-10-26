// SPDX-License-Identifier: GPL-2.0-or-later
module browserclosure

import os
import tarcore

#include <stdlib.h>
fn C.mkdtemp(&char) &char

fn workspace() !string {
	mut template := (os.temp_dir() + '/vinix-browser-closure-XXXXXX\x00').bytes()
	unsafe {
		result := C.mkdtemp(&char(template.data))
		if result == nil { return error('cannot make closure test directory') }
		return result.vstring().clone()
	}
}

// Also handles directories sealed by a deployment builder after materialization.
fn remove_tree(path string) {
	if os.is_link(path) { os.rm(path) or {}; return }
	if os.is_dir(path) {
		os.chmod(path, 0o755) or {}
		for name in os.ls(path) or { []string{} } { remove_tree(path + '/' + name) }
		os.rmdir(path) or {}
	} else { os.rm(path) or {} }
}

fn test_path_selection_and_unsafe_paths() {
	for name in ['lib/ld-musl-aarch64.so.1', 'usr/lib/libwebkitgtk-6.0.so.4',
		'usr/lib/gio/modules/libgiognutls.so', 'usr/share/fonts/a.ttf',
		'usr/share/X11/xkb/rules/evdev', 'etc/ssl/certs/ca-certificates.crt', 'etc/ssl/cert.pem'] {
		assert approved(name)
	}
	for name in ['../lib/a', '/lib/a', 'usr//lib/a', 'usr/lib/../secret',
		'usr/lib/lib.a', 'usr/lib/art/libart.so', 'usr/lib/llvm21/lib.so',
		'usr/lib/pkgconfig/webkit.pc', 'usr/bin/sh', '.PKGINFO', 'usr/lib/tab\tname'] {
		assert !approved(name)
	}
}

fn test_extract_flattens_absolute_links_and_archive_hardlinks_independently() {
	work := workspace()!
	defer { remove_tree(work) }
	archive := work + '/payload.tar'
	mut writer := tarcore.create(archive)!
	writer.add(tarcore.Member{name: 'lib/ld-musl-aarch64.so.1', mode: 0o755, size: 3}, 'elf'.bytes())!
	writer.add(tarcore.Member{name: 'lib/libc.musl-aarch64.so.1', kind: `1`, linkname: 'lib/ld-musl-aarch64.so.1'}, []u8{})!
	writer.add(tarcore.Member{name: 'usr/lib/libc.so', kind: `2`, linkname: '/lib/libc.musl-aarch64.so.1'}, []u8{})!
	writer.add(tarcore.Member{name: 'usr/bin/ignored', size: 4}, 'skip'.bytes())!
	writer.finish()!
	writer.close()
	os.mkdir(work + '/scratch')!
	mut extracted := map[string]string{}
	extract(archive, work + '/scratch', mut extracted)!
	assert extracted.len == 3
	assert extracted['lib/libc.musl-aarch64.so.1'] == 'symlink:ld-musl-aarch64.so.1'
	assert extracted['usr/lib/libc.so'] == 'symlink:../../lib/libc.musl-aarch64.so.1'
	// A shared package can repeat byte-identical files and links.
	extract(archive, work + '/scratch', mut extracted)!
	result := materialize(work + '/scratch', work + '/sealed')!
	assert result.len == 3
	mut inodes := []u64{}
	for name, digest in result {
		path := work + '/sealed/' + name
		st := os.lstat(path)!
		assert st.get_filetype() == .regular && st.nlink == 1
		assert st.mode & 0o7777 == 0o555
		assert os.read_file(path)! == 'elf' && hash(path)! == digest
		assert st.inode !in inodes
		inodes << st.inode
	}
}

fn test_reject_escaping_cycle_and_excluded_link_targets() {
	for target in ['../../outside', '/etc/passwd', 'b'] {
		work := workspace()!
		defer { remove_tree(work) }
		os.mkdir(work + '/scratch')!
		os.symlink(target, work + '/scratch/a')!
		if target == 'b' { os.symlink('a', work + '/scratch/b')! }
		mut failed := false
		materialize(work + '/scratch', work + '/sealed') or { failed = true }
		assert failed
	}
	work := workspace()!
	defer { remove_tree(work) }
	mut writer := tarcore.create(work + '/bad.tar')!
	writer.add(tarcore.Member{name: 'usr/lib/escape.so', kind: `2`, linkname: '../../../secret'}, []u8{})!
	writer.finish()!
	writer.close()
	os.mkdir(work + '/scratch')!
	mut inventory := map[string]string{}
	mut failed := false
	extract(work + '/bad.tar', work + '/scratch', mut inventory) or { failed = true }
	assert failed
}

fn test_materialize_internal_directory_link_and_readonly_data() {
	work := workspace()!
	defer { remove_tree(work) }
	os.mkdir_all(work + '/scratch/actual')!
	os.write_file(work + '/scratch/actual/data', 'font')!
	os.chmod(work + '/scratch/actual/data', 0o644)!
	os.link(work + '/scratch/actual/data', work + '/scratch/hardlink')!
	os.symlink('actual', work + '/scratch/alias')!
	result := materialize(work + '/scratch', work + '/sealed')!
	assert result.len == 3
	assert result['alias/data'] == result['actual/data']
	assert result['hardlink'] == result['actual/data']
	assert os.lstat(work + '/sealed/hardlink')!.nlink == 1
	assert os.lstat(work + '/sealed/hardlink')!.inode != os.lstat(work + '/sealed/actual/data')!.inode
	assert os.lstat(work + '/sealed/alias')!.get_filetype() == .directory
	assert os.lstat(work + '/sealed/alias/data')!.mode & 0o777 == 0o444
}

fn test_extract_rejects_differing_collision_and_symlink_parent() {
	work := workspace()!
	defer { remove_tree(work) }
	os.mkdir(work + '/scratch')!
	mut inventory := map[string]string{}
	for value in ['first', 'other'] {
		archive := work + '/' + value + '.tar'
		mut writer := tarcore.create(archive)!
		writer.add(tarcore.Member{name: 'usr/lib/a.so', size: value.len}, value.bytes())!
		writer.finish()!
		writer.close()
		if value == 'first' { extract(archive, work + '/scratch', mut inventory)! }
		else {
			mut failed := false
			extract(archive, work + '/scratch', mut inventory) or { failed = true }
			assert failed
		}
	}
	os.mkdir(work + '/outside')!
	os.mkdir(work + '/linked')!
	os.symlink('../outside', work + '/linked/usr')!
	mut other := map[string]string{}
	mut rejected := false
	extract(work + '/first.tar', work + '/linked', mut other) or { rejected = true }
	assert rejected
}

fn test_extract_rejects_excluded_link_targets_and_traversal_metadata() {
	for malicious in ['../.PKGINFO', 'usr/lib/excluded.so'] {
		work := workspace()!
		defer { remove_tree(work) }
		mut writer := tarcore.create(work + '/bad.tar')!
		writer.add(tarcore.Member{name: malicious, kind: `2`, linkname: '/etc/passwd'}, []u8{})!
		writer.finish()!
		writer.close()
		os.mkdir(work + '/scratch')!
		mut inventory := map[string]string{}
		mut rejected := false
		extract(work + '/bad.tar', work + '/scratch', mut inventory) or { rejected = true }
		assert rejected
	}
}
