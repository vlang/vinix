// SPDX-License-Identifier: GPL-2.0-or-later
// Preserve a complete sealed stage before patching or booting a separate copy.
module main

import json2
import mapsaccountstage as stage
import os
import v.embed_file

#include <sys/clonefile.h>
fn C.clonefile(&char, &char, int) int

const source_text = source($embed_file(@FILE))
const retained_sources = {
	'tests/native-android-ws/clone-maps-account-stage.v': source_text
	'tests/native-android-ws/mapsaccountstage/bundle.v': source($embed_file("mapsaccountstage/bundle.v"))
	'tests/native-android-ws/mapsaccountstage/hostsha.v': source($embed_file("mapsaccountstage/hostsha.v"))
	'tests/native-android-ws/mapsaccountstage/elf.v': source($embed_file("mapsaccountstage/elf.v"))
	'tests/native-android-ws/mapsaccountstage/media.v': source($embed_file("mapsaccountstage/media.v"))
	'tests/native-android-ws/mapsaccountstage/headless.v': source($embed_file("mapsaccountstage/headless.v"))
	'build-support/android/modulestream/stream.v': source($embed_file("../../build-support/android/modulestream/stream.v"))
	'build-support/android/modulestream/spawn_abi.h': source($embed_file("../../build-support/android/modulestream/spawn_abi.h"))
	'build-support/tarcore/writer.v': source($embed_file("../../build-support/tarcore/writer.v"))
	'build-support/tarcore/gzip.v': source($embed_file("../../build-support/tarcore/gzip.v"))
	'build-support/tarstream/reader.v': source($embed_file("../../build-support/tarstream/reader.v"))
	'build-support/tarstream/filter_abi.h': source($embed_file("../../build-support/tarstream/filter_abi.h"))
	'build-support/tarstream/sparse.v': source($embed_file("../../build-support/tarstream/sparse.v"))
}

struct Metadata {
	kind string
	mode u32
	size u64
}

fn source(data embed_file.EmbedFileData) string {
	if data.str().all_after('uncompressed: ').trim_right(' }') == '0' {
		panic('clone-maps-account-stage requires -prod embedded source')
	}
	return data.to_string()
}

fn inventory(root string, name string, mut entries map[string]Metadata) ! {
	if entries.len > 20000 { return error('stage metadata exceeds entry bound') }
	path := if name == '' { root } else { root + '/' + name }
	st := os.lstat(path)!
	kind := st.get_filetype()
	if kind !in [.directory, .regular] || st.mode & 0o7022 != 0 {
		return error('stage has an unsafe inode: ' + path)
	}
	entries[name] = Metadata{kind: kind.str(), mode: st.mode & 0o777, size: if kind == .regular { st.size } else { u64(0) }}
	if kind == .directory {
		for child in os.ls(path)! {
			child_name := if name == '' { child } else { name + '/' + child }
			if !stage.relative_file(child_name) { return error('unsafe stage relative path') }
			inventory(root, child_name, mut entries)!
		}
	}
}

fn tree(root string) !map[string]Metadata {
	mut result := map[string]Metadata{}
	inventory(root, '', mut result)!
	return result
}

fn run(source_root string, seal string, output string) ! {
	$if !macos { return error('clonefile requires macOS') }
	if source_root != os.real_path(source_root) { return error('canonical source required') }
	root := stage.external(output)!
	stage.disjoint(root, [source_root])!
	for suffix in ['-clone.json', '-clone-tool', '-clone-source.v', '-clone-sources'] {
		if os.exists(root + suffix) || os.is_link(root + suffix) { return error('fresh clone evidence paths required') }
	}
	// The complete historical checker rejects any extra patch or run evidence.
	pins := stage.load_inventory(source_root, seal)!
	metadata := tree(source_root)!
	mut names := metadata.keys()
	names.sort()
	for name in names {
		entry := metadata[name]!
		selected := if name == '' { source_root } else { source_root + '/' + name }
		destination := if name == '' { root } else { root + '/' + name }
		if entry.kind == 'directory' {
			os.mkdir(destination, mode: entry.mode)!
			os.chmod(destination, int(entry.mode))!
		} else if C.clonefile(selected.str, destination.str, 0) != 0 {
			return error('cannot clone selected regular inode: ' + name)
		}
	}
	if stage.load_inventory(root, seal)! != pins || stage.load_inventory(source_root, seal)! != pins
		|| tree(root)! != metadata || tree(source_root)! != metadata {
		return error('source or cloned complete stage differs')
	}
	os.cp(os.executable(), root + '-clone-tool')!
	os.chmod(root + '-clone-tool', 0o755)!
	os.write_file(root + '-clone-source.v', source_text)!
	mut source_pins := map[string]string{}
	for name, text in retained_sources {
		path := root + '-clone-sources/' + name
		os.mkdir_all(os.dir(path), mode: 0o700)!
		os.write_file(path, text)!
		source_pins[name] = stage.hash(path)!
	}
	os.write_file(root + '-clone.json', json2.encode({
		'kind': json2.Any('vinix-maps-account-exact-stage-clone-v1'),
		'source': json2.Any(source_root), 'output': json2.Any(root),
		'manifest_sha256': json2.Any(seal), 'verified_files': json2.Any(pins.len),
		'verified_tree_metadata': json2.decode[json2.Any](json2.encode(metadata))!,
		'tool_sha256': json2.Any(stage.hash(root + '-clone-tool')!),
		'source_sha256': json2.Any(stage.hash(root + '-clone-source.v')!),
		'source_closure': json2.Any(root + '-clone-sources'),
		'source_closure_sha256': json2.decode[json2.Any](json2.encode(source_pins))!,
		'scope': json2.Any('source and copy complete inventories and inode kinds, modes, sizes rechecked; no media mutation or guest execution'),
	}, prettify: true) + '\n')!
	println('MAPS-ACCOUNT-CLONE PASS ' + root)
}

fn main() {
	if os.args.len == 3 && os.args[1] == '--self-test' {
		self_test(os.args[2]) or { eprintln(err); exit(1) }
		return
	}
	if os.args.len != 4 { eprintln('usage: clone-maps-account-stage SOURCE MANIFEST_SHA256 FRESH_OUTPUT | --self-test FRESH_EXTERNAL_OUTPUT'); exit(2) }
	run(os.args[1], os.args[2], os.args[3]) or { eprintln(err); exit(1) }
}

fn self_test(output string) ! {
	root := stage.external(output)!
	source_root := stage.external(root + '-source')!
	os.mkdir(source_root, mode: 0o700)!
	os.mkdir(source_root + '/nested', mode: 0o700)!
	os.write_file(source_root + '/nested/payload', 'clone binary fixture\x00\xff')!
	os.write_file(source_root + '/empty', '')!
	os.chmod(source_root + '/nested/payload', 0o700)!
	pins := {
		'nested/payload': stage.hash(source_root + '/nested/payload')!
		'empty': stage.hash(source_root + '/empty')!
	}
	os.write_file(source_root + '/sha256.json', json2.encode(pins))!
	seal := stage.hash(source_root + '/sha256.json')!
	run(source_root, seal, root)!
	receipt := json2.decode[map[string]json2.Any](os.read_file(root + '-clone.json')!)!
	retained_pins := json2.decode[map[string]string](json2.encode(receipt['source_closure_sha256']!))!
	if retained_pins.len != retained_sources.len || receipt['source_closure']!.str() != root + '-clone-sources' {
		return error('clone source closure receipt differs')
	}
	for name, text in retained_sources {
		path := root + '-clone-sources/' + name
		if os.read_file(path)! != text || stage.hash(path)! != retained_pins[name]! {
			return error('clone retained source differs: ' + name)
		}
	}
	if _ := run(source_root, seal, root) { return error('existing clone accepted') }
	os.mkdir(root + '-blocked-clone-sources', mode: 0o700)!
	if _ := run(source_root, seal, root + '-blocked') { return error('existing source closure accepted') }
	if os.exists(root + '-blocked') { return error('blocked clone created output') }
	os.write_file(source_root + '/nested/payload', 'changed')!
	if _ := run(source_root, seal, root + '-tampered') { return error('modified source accepted') }
	if os.exists(root + '-tampered') { return error('unverified source created output') }
	println('MAPS-ACCOUNT-CLONE SELF-TEST PASS')
}
