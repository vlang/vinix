// SPDX-License-Identifier: GPL-2.0-or-later
module ext2build

import androidhost as ah
import encoding.hex

fn rounded(value string, unit string) !string {
	added := call('operator.add', o(value), o(unit))!
	return call('operator.floordiv', o(call('operator.sub', o(added), v(ah.Value(1)))!), o(unit))!
}

fn pointer_count(count string) !string {
	mut remaining := call('builtins.max', v(ah.Value(0)), o(call('operator.sub', o(count), v(ah.Value(12)))!))!
	mut total := literal(ah.Value(0))!
	for level in [1, 2, 3] {
		covered := call('builtins.min', o(remaining), o(call('operator.pow', o(call('POINTERS')!), v(ah.Value(level)))!))!
		if truth(covered)! {
			mut additions := []string{}
			for index in 1 .. level + 1 {
				additions << api('rounded', o(covered), o(call('operator.pow', o(call('POINTERS')!), v(ah.Value(index)))!))!
			}
			total = call('operator.add', o(total), o(call('builtins.sum', o(collection('list', additions)!))!))!
		}
		remaining = call('operator.sub', o(remaining), o(covered))!
	}
	if truth(remaining)! {
		failed('ValueError', v(ah.Value("File exceeds ext2's triple-indirect addressing")))!
	}
	return total
}

fn backup_group(group string) !string {
	if compare('eq', group, literal(ah.Value(0))!)! || compare('eq', group, literal(ah.Value(1))!)! {
		return literal(ah.Value(true))!
	}
	for base in [3, 5, 7] {
		mut value := group
		for truth(value)! && !truth(call('operator.mod', o(value), v(ah.Value(base)))!)! {
			value = call('operator.floordiv', o(value), v(ah.Value(base)))!
		}
		if compare('eq', value, literal(ah.Value(1))!)! { return literal(ah.Value(true))! }
	}
	return literal(ah.Value(false))!
}

struct Entry {
	key   string
	index int
	owner string
}

fn scan(path string, existing string) !string {
	info := method(path, 'lstat', [], {})!
	mode := attribute(info, 'st_mode')!
	if truth(call('stat.S_ISDIR', o(mode))!)! {
		node := if truth(existing)! && truth(call('stat.S_ISDIR', o(attribute(attribute(existing, 'info')!, 'st_mode')!))!)! {
			existing
		} else {
			call('Node', o(path), o(info))!
		}
		set_attr(node, 'path', o(path))!
		set_attr(node, 'info', o(info))!
		manager := call('os.scandir', o(path))!
		entries := enter(manager)!
		scan_entries(node, entries) or {
			failure := err
			if retire(manager, failure)! { return node }
			return failure
		}
		retire(manager, none)!
		return node
	}
	if truth(call('stat.S_ISREG', o(mode))!)! {
		if compare('gt', attribute(info, 'st_size')!, call('MAX_FILE')!)! {
			failed('ValueError', v(ah.Value('Vinix cannot read a file larger than 4 GiB: ' + text(path)!)))!
		}
		return call('Node', o(path), o(info))!
	}
	if truth(call('stat.S_ISLNK', o(mode))!)! { return call('Node', o(path), o(info))! }
	failed('ValueError', v(ah.Value('Only directories, regular files and symlinks can be exported: ' + text(path)!)))!
	return ''
}

fn scan_entries(node string, entries string) ! {
	iter := iterator(entries)!
	mut ordered := []Entry{}
	for {
		row := next(iter)!
		if row.done { break }
		encoded := call('os.fsencode', o(attribute(row.value, 'name')!))!
		ordered << Entry{hex.decode(hex_data(encoded)!)!.bytestr(), ordered.len, row.value}
	}
	ordered.sort_with_compare(fn (a &Entry, b &Entry) int {
		if a.key < b.key { return -1 }
		if a.key > b.key { return 1 }
		return a.index - b.index
	})
	for entry in ordered {
		name := call('os.fsencode', o(attribute(entry.owner, 'name')!))!
		if !truth(name)! || size(name)! > 255 {
			failed('ValueError', v(ah.Value('Invalid ext2 filename: ' + text(attribute(entry.owner, 'path')!)!)))!
		}
		children := attribute(node, 'children')!
		child_path := call('Path', o(attribute(entry.owner, 'path')!))!
		child_name := attribute(entry.owner, 'name')!
		existing := method(children, 'get', [o(child_name)], {})!
		child := api('scan', o(child_path), o(existing))!
		set_item(children, o(child_name), o(child))!
	}
}

struct Inodes {
mut:
	next int = 11
}

fn flatten(root string) !string {
	nodes := collection('list', [root])!
	set_attr(root, 'inode', v(ah.Value(2)))!
	set_attr(root, 'parent', v(ah.Value(2)))!
	mut inodes := Inodes{}
	visit(root, nodes, mut inodes)!
	return nodes
}

fn visit(parent string, nodes string, mut inodes Inodes) ! {
	children := method(attribute(parent, 'children')!, 'values', [], {})!
	iter := iterator(children)!
	for {
		row := next(iter)!
		if row.done { break }
		set_attr(row.value, 'inode', v(ah.Value(inodes.next)))!
		set_attr(row.value, 'parent', o(attribute(parent, 'inode')!))!
		inodes.next++
		append(nodes, o(row.value))!
		visit(row.value, nodes, mut inodes)!
	}
}

fn directory_data(node string) !string {
	mut entries := [][]string{}
	entries << [attribute(node, 'inode')!, call('builtins.bytes', v(ah.Value([ah.Value(46)])))!,
		literal(ah.Value(2))!]
	entries << [attribute(node, 'parent')!,
		call('builtins.bytes', v(ah.Value([ah.Value(46), ah.Value(46)])))!, literal(ah.Value(2))!]
	iter := iterator(method(attribute(node, 'children')!, 'items', [], {})!)!
	for {
		row := next(iter)!
		if row.done { break }
		name := item(row.value, v(ah.Value(0)))!
		child := item(row.value, v(ah.Value(1)))!
		mode := attribute(attribute(child, 'info')!, 'st_mode')!
		kind := if truth(call('stat.S_ISDIR', o(mode))!)! {
			2
		} else if truth(call('stat.S_ISLNK', o(mode))!)! {
			7
		} else {
			1
		}
		entries << [attribute(child, 'inode')!, call('os.fsencode', o(name))!,
			literal(ah.Value(kind))!]
	}
	block_size := int(number(call('BLOCK')!)!)
	mut block := call('builtins.bytearray', v(ah.Value(block_size)))!
	mut blocks := []string{}
	mut offset := 0
	mut previous := 0
	for entry in entries {
		name_size := size(entry[1])!
		entry_size := int(number(call('operator.mul', o(api('rounded', v(ah.Value(8 + name_size)), v(ah.Value(4)))!), v(ah.Value(4)))!)!)
		if offset + entry_size > block_size {
			call('struct.pack_into', v(ah.Value('<H')), o(block), v(ah.Value(previous + 4)), v(ah.Value(block_size - previous)))!
			blocks << call('builtins.bytes', o(block))!
			block = call('builtins.bytearray', v(ah.Value(block_size)))!
			offset = 0
		}
		call('struct.pack_into', v(ah.Value('<IHBB')), o(block), v(ah.Value(offset)), o(entry[0]), v(ah.Value(entry_size)), v(ah.Value(name_size)), o(entry[2]))!
		slice := call('builtins.slice', v(ah.Value(offset + 8)), v(ah.Value(offset + 8 + name_size)))!
		set_item(block, o(slice), o(entry[1]))!
		previous = offset
		offset += entry_size
	}
	call('struct.pack_into', v(ah.Value('<H')), o(block), v(ah.Value(previous + 4)), v(ah.Value(block_size - previous)))!
	blocks << call('builtins.bytes', o(block))!
	return method(call('builtins.bytes')!, 'join', [o(collection('list', blocks)!)], {})!
}
