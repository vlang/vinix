// SPDX-License-Identifier: GPL-2.0-or-later
module ext2build

import androidhost as ah

fn finish(self string) !string {
	own(self, 'close_builder_fd')!
	result := finish_metadata(self) or {
		failure := err
		retire(self, failure)!
		return failure
	}
	retire(self, none)!
	return result
}

fn finish_metadata(self string) !string {
	nodes := attribute(self, 'nodes')!
	iter := iterator(nodes)!
	for {
		row := next(iter)!
		if row.done { break }
		api_method(self, 'add_node', [o(row.value)])!
	}
	block := constant('BLOCK')!
	group_blocks := constant('GROUP_BLOCKS')!
	gdt := call('builtins.bytearray', v(ah.Value(field_number(self, 'gdt_blocks')! * block)))!
	last_inode := i64(size(nodes)!) + 9
	groups := field_number(self, 'groups')!
	inodes_per_group := field_number(self, 'inodes_per_group')!
	mut directory_counts := []i64{len: int(groups)}
	iter2 := iterator(nodes)!
	for {
		row := next(iter2)!
		if row.done { break }
		if truth(call('stat.S_ISDIR', o(attribute(attribute(row.value, 'info')!, 'st_mode')!))!)! {
			group := (field_number(row.value, 'inode')! - 1) / inodes_per_group
			directory_counts[int(group)]++
		}
	}
	mut free_inodes := i64(0)
	for group := i64(0); group < groups; group++ {
		prefix := if backup(group)! { 1 + field_number(self, 'gdt_blocks')! } else { i64(0) }
		base := group * group_blocks
		mut used_inodes := last_inode - group * inodes_per_group
		if used_inodes > inodes_per_group { used_inodes = inodes_per_group }
		if used_inodes < 0 { used_inodes = 0 }
		available_inodes := inodes_per_group - used_inodes
		free_inodes += available_inodes
		used := number(item(attribute(self, 'used')!, v(ah.Value(group)))!)!
		table := item(attribute(self, 'tables')!, v(ah.Value(group)))!
		pack_into('<IIIHHH', gdt, group * 32, [v(ah.Value(base + prefix)),
			v(ah.Value(base + prefix + 1)), o(table), v(ah.Value(group_blocks - used)),
			v(ah.Value(available_inodes)), v(ah.Value(directory_counts[int(group)]))])!
		mut bitmap := []u8{len: int(block)}
		full := used / 8
		tail := used % 8
		for i := i64(0); i < full; i++ { bitmap[int(i)] = 0xff }
		if tail != 0 { bitmap[int(full)] = u8((i64(1) << tail) - 1) }
		api_method(self, 'write', [v(ah.Value((base + prefix) * block)), b(bitmap.hex())])!
		bitmap = []u8{len: int(block), init: 0xff}
		for index := used_inodes; index < inodes_per_group; index++ {
			bitmap[int(index / 8)] &= ~u8(1 << (index % 8))
		}
		api_method(self, 'write', [v(ah.Value((base + prefix + 1) * block)), b(bitmap.hex())])!
	}
	superblock := call('builtins.bytearray', v(ah.Value(1024)))!
	used_total := number(call('builtins.sum', o(attribute(self, 'used')!))!)!
	block_count := field_number(self, 'block_count')!
	pack_into('<11I', superblock, 0, [v(ah.Value(groups * inodes_per_group)), v(ah.Value(block_count)),
		v(ah.Value(0)), v(ah.Value(block_count - used_total)), v(ah.Value(free_inodes)),
		v(ah.Value(0)), v(ah.Value(2)), v(ah.Value(2)), v(ah.Value(group_blocks)),
		v(ah.Value(group_blocks)), v(ah.Value(inodes_per_group))])!
	pack_into('<HHHHHH', superblock, 52, [v(ah.Value(0)), v(ah.Value(0xffff)), v(ah.Value(0xef53)),
		v(ah.Value(1)), v(ah.Value(1)), v(ah.Value(0))])!
	pack_into('<IIIIHH', superblock, 64, [v(ah.Value(0)), v(ah.Value(0)), v(ah.Value(0)),
		v(ah.Value(1)), v(ah.Value(0)), v(ah.Value(0))])!
	pack_into('<IHHIII', superblock, 84, [v(ah.Value(11)), o(call('INODE_SIZE')!), v(ah.Value(0)),
		v(ah.Value(0)), v(ah.Value(2)), v(ah.Value(3))])!
	set_item(superblock, o(call('builtins.slice', v(ah.Value(104)), v(ah.Value(120)))!), o(attribute(call('uuid.uuid4')!, 'bytes')!))!
	set_item(superblock, o(call('builtins.slice', v(ah.Value(120)), v(ah.Value(136)))!), b('Vinix game data\x00'.bytes().hex()))!
	for group := i64(0); group < groups; group++ {
		if backup(group)! {
			pack_into('<H', superblock, 90, [v(ah.Value(group))])!
			api_method(self, 'write', [
				v(ah.Value(group * group_blocks * block + if group == 0 { 1024 } else { 0 })),
				o(superblock),
			])!
			api_method(self, 'write', [
				v(ah.Value((group * group_blocks + 1) * block)),
				o(gdt),
			])!
		}
	}
	call('os.fsync', o(attribute(self, 'fd')!))!
	manifest := literal(ah.Value(map[string]ah.Value{}))!
	set_item(manifest, v(ah.Value('version')), v(ah.Value(1)))!
	set_item(manifest, v(ah.Value('size')), v(ah.Value(block_count * block)))!
	set_item(manifest, v(ah.Value('files')), o(attribute(self, 'files')!))!
	set_item(manifest, v(ah.Value('regions')), o(call('builtins.sorted', o(attribute(self, 'regions')!))!))!
	manager := method(join(attribute(self, 'state')!, 'manifest.json')!, 'open', [v(ah.Value('x'))], {})!
	output := enter(manager)!
	invoke('json.dump', [o(manifest), o(output)], {
		'separators': o(collection('tuple', [literal(ah.Value(','))!, literal(ah.Value(':'))!])!)
	}) or {
		failure := err
		if !retire(manager, failure)! { return failure }
		return manifest
	}
	retire(manager, none)!
	return manifest
}

fn build(source string, state_argument string, overlays string) !string {
	state := method(state_argument, 'resolve', [], {})!
	mut roots := [method(source, 'resolve', [], {})!]
	iter := iterator(overlays)!
	for {
		row := next(iter)!
		if row.done { break }
		roots << method(row.value, 'resolve', [], {})!
	}
	for path in roots {
		if !truth(method(path, 'is_dir', [], {})!)! {
			failed('ValueError', v(ah.Value('Export root is not a directory: ' + text(path)!)))!
		}
		if truth(method(state, 'is_relative_to', [o(path)], {})!)! {
			failed('ValueError', v(ah.Value('Metadata directory must be outside every exported root')))!
		}
	}
	mut root := api('scan', o(roots[0]))!
	for path in roots[1..] { root = api('scan', o(path), o(root))! }
	nodes := api('flatten', o(root))!
	method(state, 'mkdir', [], {
		'parents':  v(ah.Value(true))
		'exist_ok': v(ah.Value(true))
	})!
	if truth(method(join(state, 'metadata.ext2')!, 'exists', [], {})!)! || truth(method(join(state, 'manifest.json')!, 'exists', [], {})!)! {
		failed('ValueError', v(ah.Value('Use a fresh export state directory')))!
	}
	return api_method(call('Builder', o(state), o(nodes))!, 'finish', [])!
}
