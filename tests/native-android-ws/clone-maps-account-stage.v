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
	for suffix in ['-clone.json', '-clone-tool', '-clone-source.v'] {
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
	os.write_file(root + '-clone.json', json2.encode({
		'kind': json2.Any('vinix-maps-account-exact-stage-clone-v1'),
		'source': json2.Any(source_root), 'output': json2.Any(root),
		'manifest_sha256': json2.Any(seal), 'verified_files': json2.Any(pins.len),
		'verified_tree_metadata': json2.decode[json2.Any](json2.encode(metadata))!,
		'tool_sha256': json2.Any(stage.hash(root + '-clone-tool')!),
		'source_sha256': json2.Any(stage.hash(root + '-clone-source.v')!),
		'scope': json2.Any('source and copy complete inventories and inode kinds, modes, sizes rechecked; no media mutation or guest execution'),
	}, prettify: true) + '\n')!
	println('MAPS-ACCOUNT-CLONE PASS ' + root)
}

fn main() {
	if os.args.len != 4 { eprintln('usage: clone-maps-account-stage SOURCE MANIFEST_SHA256 FRESH_OUTPUT'); exit(2) }
	run(os.args[1], os.args[2], os.args[3]) or { eprintln(err); exit(1) }
}
