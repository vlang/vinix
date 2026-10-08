// SPDX-License-Identifier: GPL-2.0-or-later
module ext2build

import androidhost as ah

fn field_number(id string, name string) !i64 { return number(attribute(id, name)!)! }

fn constant(name string) !i64 { return number(call(name)!)! }

fn round_number(value i64, unit i64) !i64 {
	return number(api('rounded', v(ah.Value(value)), v(ah.Value(unit)))!)!
}

fn backup(group i64) !bool { return truth(api('backup_group', v(ah.Value(group)))!)! }

fn initialize(self string, state string, nodes string) ! {
	set_attr(self, 'nodes', o(nodes))!
	set_attr(self, 'state', o(state))!
	block := constant('BLOCK')!
	group_blocks := constant('GROUP_BLOCKS')!
	inode_size := constant('INODE_SIZE')!
	mut required := i64(0)
	iter := iterator(nodes)!
	for {
		row := next(iter)!
		if row.done { break }
		info := attribute(row.value, 'info')!
		mode := attribute(info, 'st_mode')!
		mut count := literal(ah.Value(0))!
		if truth(call('stat.S_ISDIR', o(mode))!)! {
			count = literal(ah.Value(i64(size(api('directory_data', o(row.value))!)!) / block))!
		} else if truth(call('stat.S_ISLNK', o(mode))!)! {
			link := call('os.fsencode', o(call('os.readlink', o(attribute(row.value, 'path')!))!))!
			link_size := size(link)!
			if link_size > 60 {
				count = api('rounded', v(ah.Value(link_size)), v(ah.Value(block)))!
			}
		} else {
			count = api('rounded', o(attribute(info, 'st_size')!), v(ah.Value(block)))!
		}
		indirect := api('pointer_count', o(count))!
		required += number(count)! + number(indirect)!
	}
	mut groups := round_number(required + 16, group_blocks - 8)!
	if groups < 1 { groups = 1 }
	set_attr(self, 'groups', v(ah.Value(groups)))!
	for {
		mut inodes_per_group := round_number(i64(size(nodes)!) + 9, groups * 32)! * 32
		if inodes_per_group < 32 { inodes_per_group = 32 }
		gdt_blocks := round_number(groups * 32, block)!
		table_blocks := inodes_per_group * inode_size / block
		set_attr(self, 'inodes_per_group', v(ah.Value(inodes_per_group)))!
		set_attr(self, 'gdt_blocks', v(ah.Value(gdt_blocks)))!
		set_attr(self, 'table_blocks', v(ah.Value(table_blocks)))!
		used := call('builtins.list')!
		tables := call('builtins.list')!
		set_attr(self, 'used', o(used))!
		set_attr(self, 'tables', o(tables))!
		mut allocated := i64(0)
		for group := i64(0); group < groups; group++ {
			prefix := if backup(group)! { 1 + gdt_blocks } else { i64(0) }
			value := prefix + 2 + table_blocks
			append(used, v(ah.Value(value)))!
			append(tables, v(ah.Value(group * group_blocks + prefix + 2)))!
			allocated += value
		}
		if groups * group_blocks - allocated >= required { break }
		groups++
		set_attr(self, 'groups', v(ah.Value(groups)))!
	}
	block_count := groups * group_blocks
	set_attr(self, 'block_count', v(ah.Value(block_count)))!
	if block_count > 0xffffffff || field_number(self, 'inodes_per_group')! > group_blocks {
		failed('ValueError', v(ah.Value("Export exceeds this ext2 layout's limits")))!
	}
	set_attr(self, 'group', v(ah.Value(0)))!
	set_attr(self, 'files', o(call('builtins.list')!))!
	set_attr(self, 'regions', o(call('builtins.list')!))!
}

fn allocate(self string, count string) !string {
	runs := call('builtins.list')!
	mut remaining := count
	for truth(remaining)! {
		group := attribute(self, 'group')!
		if compare('ge', group, attribute(self, 'groups')!)! {
			failed('ValueError', v(ah.Value('Export ran out of blocks')))!
		}
		used := attribute(self, 'used')!
		current := item(used, o(group))!
		available := call('operator.sub', o(call('GROUP_BLOCKS')!), o(current))!
		if !truth(available)! {
			set_attr(self, 'group', o(call('operator.add', o(group), v(ah.Value(1)))!))!
			continue
		}
		take := call('builtins.min', o(remaining), o(available))!
		start := call('operator.add', o(call('operator.mul', o(group), o(call('GROUP_BLOCKS')!))!), o(current))!
		append(runs, o(collection('tuple', [start, take])!))!
		set_item(used, o(group), o(call('operator.add', o(current), o(take))!))!
		remaining = call('operator.sub', o(remaining), o(take))!
	}
	return runs
}

fn write(self string, offset string, data string) ! {
	mut position := offset
	mut remaining := data
	for truth(remaining)! {
		written := call('os.pwrite', o(attribute(self, 'fd')!), o(remaining), o(position))!
		if !truth(written)! { failed('OSError', v(ah.Value('Short metadata write')))! }
		position = call('operator.add', o(position), o(written))!
		remaining = item(remaining, o(call('builtins.slice', o(written), o(null()!))!))!
	}
}

struct Blocks {
mut:
	runs     string
	active   string
	values   []ah.Value
	index    int
	indirect i64
}

fn (mut blocks Blocks) next() !ah.Value {
	for {
		if blocks.index < blocks.values.len {
			value := blocks.values[blocks.index]
			blocks.index++
			return value
		}
		if blocks.active != '' {
			chunk := call('itertools.islice', o(blocks.active), v(ah.Value(1024)))!
			blocks.values = datum('builtins.list', [o(chunk)])!.items()
			blocks.index = 0
			if blocks.values.len > 0 { continue }
			blocks.active = ''
		}
		row := next(blocks.runs)!
		if row.done { break }
		fields := unpack2(row.value)!
		start := fields[0]
		count := fields[1]
		end := call('operator.add', o(start), o(count))!
		blocks.active = iterator(call('builtins.range', o(start), o(end))!)!
	}
	failed('StopIteration')!
	return ah.Value(0)
}

fn packed(format string, values []ah.Value) !string {
	mut args := [v(ah.Value(format))]
	for value in values { args << value }
	return invoke('struct.pack', args, {})!
}

fn pack_into(format string, target string, offset i64, values []ah.Value) ! {
	mut args := [v(ah.Value(format)), o(target), v(ah.Value(offset))]
	for value in values { args << value }
	invoke('struct.pack_into', args, {})!
}

fn address_tree(self string, runs string) !string {
	mut lengths := []string{}
	iter := iterator(runs)!
	for {
		row := next(iter)!
		if row.done { break }
		lengths << unpack2(row.value)![1]
	}
	count := call('builtins.sum', o(collection('list', lengths)!))!
	mut blocks := Blocks{ runs: iterator(runs)! }
	mut pointers := []string{}
	direct := iterator(call('builtins.range', o(call('builtins.min', o(count), v(ah.Value(12)))!))!)!
	for {
		row := next(direct)!
		if row.done { break }
		pointers << literal(blocks.next()!)!
	}
	for pointers.len < 12 { pointers << literal(ah.Value(0))! }
	mut remaining := call('builtins.max', v(ah.Value(0)), o(call('operator.sub', o(count), v(ah.Value(12)))!))!
	for level in [1, 2, 3] {
		capacity := call('operator.pow', o(call('POINTERS')!), v(ah.Value(level)))!
		take := call('builtins.min', o(remaining), o(capacity))!
		pointers << if truth(take)! {
			address_level(self, level, take, mut blocks)!
		} else {
			literal(ah.Value(0))!
		}
		remaining = call('operator.sub', o(remaining), o(take))!
	}
	return collection('tuple', [collection('list', pointers)!, literal(ah.Value(blocks.indirect))!])!
}

fn address_level(self string, level int, length string, mut blocks Blocks) !string {
	run := item(api_method(self, 'allocate', [v(ah.Value(1))])!, v(ah.Value(0)))!
	block := item(run, v(ah.Value(0)))!
	blocks.indirect++
	mut values := []ah.Value{}
	if level == 1 {
		iter := iterator(call('builtins.range', o(length))!)!
		for {
			row := next(iter)!
			if row.done { break }
			values << v(blocks.next()!)
		}
	} else {
		capacity := call('operator.pow', o(call('POINTERS')!), v(ah.Value(level - 1)))!
		iter := iterator(call('builtins.range', v(ah.Value(0)), o(length), o(capacity))!)!
		for {
			row := next(iter)!
			if row.done { break }
			left := call('operator.sub', o(length), o(row.value))!
			take := call('builtins.min', o(capacity), o(left))!
			values << o(address_level(self, level - 1, take, mut blocks)!)
		}
	}
	width := constant('POINTERS')!
	for i := i64(values.len); i < width; i++ { values << v(ah.Value(0)) }
	data := packed('<1024I', values)!
	api_method(self, 'write', [o(call('operator.mul', o(block), o(call('BLOCK')!))!), o(data)])!
	return block
}

fn add_node(self string, node string) ! {
	info := attribute(node, 'info')!
	mode := call('operator.and_', o(call('operator.and_', o(attribute(info, 'st_mode')!), v(ah.Value(0xffff)))!), v(ah.Value(~i64(0o222))))!
	mut data := null()!
	mut inline := null()!
	mut data_size := attribute(info, 'st_size')!
	mut links := literal(ah.Value(1))!
	if truth(call('stat.S_ISDIR', o(mode))!)! {
		data = api('directory_data', o(node))!
		data_size = call('builtins.len', o(data))!
		mut directories := []string{}
		iter := iterator(method(attribute(node, 'children')!, 'values', [], {})!)!
		for {
			row := next(iter)!
			if row.done { break }
			directories << call('stat.S_ISDIR', o(attribute(attribute(row.value, 'info')!, 'st_mode')!))!
		}
		links = call('operator.add', v(ah.Value(2)), o(call('builtins.sum', o(collection('list', directories)!))!))!
	} else if truth(call('stat.S_ISLNK', o(mode))!)! {
		data = call('os.fsencode', o(call('os.readlink', o(attribute(node, 'path')!))!))!
		data_size = call('builtins.len', o(data))!
		if compare('le', data_size, literal(ah.Value(60))!)! {
			inline = data
			data = null()!
		}
	}
	count := if !compare('is_', inline, null()!)! {
		literal(ah.Value(0))!
	} else {
		api('rounded', o(data_size), o(call('BLOCK')!))!
	}
	runs := api_method(self, 'allocate', [o(count)])!
	if !compare('is_', data, null()!)! {
		mut position := i64(0)
		iter := iterator(runs)!
		for {
			row := next(iter)!
			if row.done { break }
			start := number(item(row.value, v(ah.Value(0)))!)!
			length := number(item(row.value, v(ah.Value(1)))!)! * constant('BLOCK')!
			chunk := item(data, o(call('builtins.slice', v(ah.Value(position)), v(ah.Value(position + length)))!))!
			api_method(self, 'write', [v(ah.Value(start * constant('BLOCK')!)), o(chunk)])!
			position += length
		}
	} else if truth(call('stat.S_ISREG', o(mode))!)! {
		files := attribute(self, 'files')!
		index := size(files)!
		entry := literal(ah.Value(map[string]ah.Value{}))!
		set_item(entry, v(ah.Value('path')), o(call('builtins.str', o(attribute(node, 'path')!))!))!
		set_item(entry, v(ah.Value('identity')), o(call('identity', o(info))!))!
		append(files, o(entry))!
		mut position := i64(0)
		iter := iterator(runs)!
		for {
			row := next(iter)!
			if row.done { break }
			start := number(item(row.value, v(ah.Value(0)))!)!
			length := number(item(row.value, v(ah.Value(1)))!)! * constant('BLOCK')!
			append(attribute(self, 'regions')!, v(ah.Value([
				ah.Value(start * constant('BLOCK')!),
				ah.Value(length),
				ah.Value(index),
				ah.Value(position),
			])))!
			position += length
		}
	}
	addresses := api_method(self, 'address_tree', [o(runs)])!
	pointers := item(addresses, v(ah.Value(0)))!
	indirect := item(addresses, v(ah.Value(1)))!
	inode := call('builtins.bytearray', o(call('INODE_SIZE')!))!
	timestamp := call('builtins.max', v(ah.Value(0)), o(call('builtins.min', v(ah.Value(i64(0xffffffff))), o(call('builtins.int', o(attribute(info, 'st_mtime')!))!))!))!
	sectors := call('operator.mul', o(call('operator.add', o(count), o(indirect))!), v(ah.Value(8)))!
	pack_into('<HHIIIIIHHIII', inode, 0, [o(mode), v(ah.Value(0)), o(data_size), o(timestamp),
		o(timestamp), o(timestamp), v(ah.Value(0)), v(ah.Value(0)), o(links), o(sectors),
		v(ah.Value(0)), v(ah.Value(0))])!
	if !compare('is_', inline, null()!)! {
		set_item(inode, o(call('builtins.slice', v(ah.Value(40)), v(ah.Value(40 + size(inline)!)))!), o(inline))!
	} else {
		mut values := []ah.Value{}
		iter := iterator(pointers)!
		for {
			row := next(iter)!
			if row.done { break }
			values << o(row.value)
		}
		pack_into('<15I', inode, 40, values)!
	}
	position := call('builtins.divmod', o(call('operator.sub', o(attribute(node, 'inode')!), v(ah.Value(1)))!), o(attribute(self, 'inodes_per_group')!))!
	group := item(position, v(ah.Value(0)))!
	index := item(position, v(ah.Value(1)))!
	table := item(attribute(self, 'tables')!, o(group))!
	offset := call('operator.add', o(call('operator.mul', o(table), o(call('BLOCK')!))!), o(call('operator.mul', o(index), o(call('INODE_SIZE')!))!))!
	api_method(self, 'write', [o(offset), o(inode)])!
}
