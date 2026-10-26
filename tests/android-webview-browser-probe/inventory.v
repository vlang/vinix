// SPDX-License-Identifier: GPL-2.0-or-later
// Inventory a prepared browser bundle without following runtime symlinks.
module main

import crypto.sha256
import json2
import os

fn inventory_tree(root string, relative string, mut entries map[string]string) ! {
	mut names := os.ls(root + '/' + relative)!
	names.sort()
	for name in names {
		key := if relative == '' { name } else { relative + '/' + name }
		path := root + '/' + key
		st := os.lstat(path)!
		mode := (st.mode & 0o7777).str()
		match st.get_filetype() {
			.directory {
				entries[key] = mode + ':directory'
				inventory_tree(root, key, mut entries)!
			}
			.regular {
				entries[key] = mode + ':sha256:' + sha256.sum(os.read_bytes(path)!).hex()
			}
			.symbolic_link { entries[key] = mode + ':symlink:' + os.readlink(path)! }
			else { return error('special file in browser bundle: ' + key) }
		}
	}
}

fn inventory_text(root string) !string {
	if os.is_link(root) || !os.is_dir(root) { return error('bundle must be a real directory') }
	mut entries := map[string]string{}
	inventory_tree(root, '', mut entries)!
	return json2.encode(entries, prettify: true) + '\n'
}

fn inventory_self_test() ! {
	root := os.join_path(os.temp_dir(), 'vinix-browser-inventory-' + os.getpid().str())
	os.mkdir(root)!
	defer { os.rmdir_all(root) or {} }
	os.mkdir(root + '/bin')!
	os.write_file(root + '/bin/helper', 'helper')!
	os.chmod(root + '/bin/helper', 0o751)!
	os.symlink('bin/helper', root + '/helper')!
	original := inventory_text(root)!
	if !original.contains('489:sha256:') || !original.contains('symlink:bin/helper') {
		return error('inventory lost file mode or symlink target')
	}
	os.write_file(root + '/bin/helper', 'changed')!
	if original == inventory_text(root)! { return error('content change was not detected') }
	os.write_file(root + '/bin/helper', 'helper')!
	os.chmod(root + '/bin/helper', 0o750)!
	if original == inventory_text(root)! { return error('mode change was not detected') }
	os.chmod(root + '/bin/helper', 0o751)!
	os.rm(root + '/helper')!
	os.symlink('bin/absent', root + '/helper')!
	if original == inventory_text(root)! { return error('symlink change was not detected') }
	println('BROWSER-INVENTORY-SELF-TEST-PASS files modes symlinks tamper')
}

fn main() {
	if os.args.len == 2 && os.args[1] == '--self-test' {
		inventory_self_test() or { eprintln(err); exit(1) }
		return
	}
	if os.args.len != 4 || os.args[1] !in ['--write', '--check'] {
		eprintln('usage: inventory --write|--check BUNDLE EXTERNAL-MANIFEST')
		exit(2)
	}
	root := os.abs_path(os.args[2])
	if os.real_path(root) != root { eprintln('bundle path must be canonical'); exit(2) }
	manifest := os.real_path(os.dir(os.args[3])) + '/' + os.file_name(os.args[3])
	if manifest.starts_with(root + '/') { eprintln('manifest must be outside bundle'); exit(2) }
	if os.is_link(manifest) { eprintln('manifest must not be a symlink'); exit(2) }
	actual := inventory_text(root) or { eprintln(err); exit(1) }
	if os.args[1] == '--write' {
		if os.exists(manifest) { eprintln('manifest already exists'); exit(1) }
		os.write_file(manifest, actual) or { eprintln(err); exit(1) }
	} else {
		expected := os.read_file(manifest) or { eprintln(err); exit(1) }
		if actual != expected { eprintln('bundle inventory differs'); exit(1) }
	}
	println('BROWSER-INVENTORY-PASS sha256=' + sha256.sum(actual.bytes()).hex())
}
