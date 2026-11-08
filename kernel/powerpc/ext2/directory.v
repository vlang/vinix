// SPDX-License-Identifier: GPL-2.0-or-later
module ext2

pub struct Entry {
pub mut:
	number u32
	kind u8
	length u32
	name [256]u8
	next u32
}

pub fn (mut v Volume) next(number u32, offset u32, mut e Entry) int {
	mut n := Node{}
	if !v.inode(number, mut n) { return -5 }
	if n.mode() & 0xf000 != 0x4000 { return -20 }
	mut b := [4096]u8{}
	mut pos := offset
	mut cached := u32(0xffffffff)
	for pos < n.size() {
		if pos / 4096 != cached {
			block := v.data_block(unsafe { &n }, pos / 4096, false)
			if block == 0 || !v.read_block(block, unsafe { &b[0] }) { return -5 }
			cached = pos / 4096
		}
		at := pos % 4096
		if at > 4088 { return -5 }
		p := unsafe { &b[at] }
		record := le16(p, 4)
		length := u32(b[at + 6])
		if record < 8 || record % 4 != 0 || record > 4096 - at || length > record - 8 { return -5 }
		pos += record
		id := le32(p, 0)
		if id == 0 { continue }
		if id > v.inodes || length == 0 { return -5 }
		e = Entry{number: id, kind: b[at + 7], length: length, next: pos}
		copy_bytes(unsafe { &e.name[0] }, unsafe { &b[at + 8] }, length)
		return 1
	}
	return 0
}

pub fn (mut v Volume) lookup(parent u32, name &u8, length u32) int {
	mut e := Entry{}
	mut at := u32(0)
	for {
		result := v.next(parent, at, mut e)
		if result <= 0 { return if result == 0 { -2 } else { result } }
		at = e.next
		if e.length != length { continue }
		mut same := true
		for i := u32(0); i < length; i++ { if e.name[i] != unsafe { name[i] } { same = false; break } }
		if same { return int(e.number) }
	}
	return -2
}

// Resolve links without recursion or allocated strings. All paths here are
// volume-relative; the syscall layer chooses the mount and working directory.
pub fn (mut v Volume) walk(path &u8, length u32, follow bool) int {
	if length == 0 { return -2 }
	if length > 511 { return -36 }
	mut pending := [512]u8{}
	copy_bytes(unsafe { &pending[0] }, path, length)
	mut size := length
	mut at := u32(0)
	mut current := u32(2)
	mut links := 0
	for at < size {
		for at < size && pending[at] == `/` { at++ }
		if at == size { break }
		first := at
		for at < size && pending[at] != `/` { at++ }
		if at - first > 255 { return -36 }
		id := v.lookup(current, unsafe { &pending[first] }, at - first)
		if id < 0 { return id }
		mut n := Node{}
		if !v.inode(u32(id), mut n) { return -5 }
		if n.mode() & 0xf000 == 0xa000 && (follow || at < size) {
			links++
			if links > 16 { return -40 }
			mut target := [512]u8{}
			got := v.readlink(u32(id), unsafe { &target[0] }, 511)
			if got <= 0 { return if got == 0 { -2 } else { got } }
			if u32(got) + size - at > 511 { return -36 }
			copy_bytes(unsafe { &target[got] }, unsafe { &pending[at] }, size - at)
			size = u32(got) + size - at
			pending = target
			at = 0
			if pending[0] == `/` { current = 2 }
			continue
		}
		current = u32(id)
		if at < size && n.mode() & 0xf000 != 0x4000 { return -20 }
	}
	return int(current)
}

pub fn (mut v Volume) parent(path &u8, length u32, mut component Entry) int {
	if length == 0 || length > 511 { return -36 }
	mut end := length
	for end > 0 && unsafe { path[end - 1] == `/` } { end-- }
	mut at := end
	for at > 0 && unsafe { path[at - 1] != `/` } { at-- }
	component.length = end - at
	if component.length == 0 || component.length > 255 { return -22 }
	copy_bytes(unsafe { &component.name[0] }, unsafe { &path[at] }, component.length)
	if !valid_name(unsafe { &component.name[0] }, component.length) { return -22 }
	return if at == 0 { 2 } else { v.walk(path, at, true) }
}

fn valid_name(name &u8, length u32) bool {
	if length == 0 || length > 255 { return false }
	unsafe {
		if name[0] == `.` && (length == 1 || (length == 2 && name[1] == `.`)) { return false }
		for i := u32(0); i < length; i++ { if name[i] == 0 || name[i] == `/` { return false } }
	}
	return true
}

fn entry_bytes(p &u8, number u32, record u32, name &u8, length u32, mode u32) {
	put32(p, 0, number); put16(p, 4, record)
	unsafe { p[6] = u8(length); p[7] = if mode & 0xf000 == 0x4000 { u8(2) } else if mode & 0xf000 == 0xa000 { u8(7) } else { u8(1) } }
	copy_bytes(unsafe { &p[8] }, name, length)
}

fn (mut v Volume) insert(parent u32, name &u8, length u32, n &Node) int {
	mut dir := Node{}
	if !valid_name(name, length) { return -22 }
	if !v.inode(parent, mut dir) { return -5 }
	if dir.mode() & 0xf000 != 0x4000 { return -20 }
	needed := (8 + length + 3) & ~u32(3)
	mut b := [4096]u8{}
	for index := u32(0); index <= dir.size() / 4096 && index < 12; index++ {
		fresh := index * 4096 == dir.size()
		block := v.data_block(unsafe { &dir }, index, fresh)
		if block == 0 { return if v.failed { -5 } else { -28 } }
		if fresh {
			clear(unsafe { &b[0] }, 4096)
			put16(unsafe { &b[0] }, 4, 4096)
		} else if !v.read_block(block, unsafe { &b[0] }) { return -5 }
		for at := u32(0); at < 4096; {
			if at > 4088 { return -5 }
			p := unsafe { &b[at] }
			record := le16(p, 4)
			if record < 8 || record % 4 != 0 || record > 4096 - at || u32(b[at + 6]) > record - 8 { return -5 }
			used := if le32(p, 0) == 0 { u32(0) } else { (8 + u32(b[at + 6]) + 3) & ~u32(3) }
			if record - used >= needed {
				if used != 0 { put16(p, 4, used) }
				entry_bytes(unsafe { &b[at + used] }, n.number, record - used, name, length, n.mode())
				if !v.write_block(block, unsafe { &b[0] }) { return -5 }
				if fresh { put32(unsafe { &dir.raw[0] }, 4, dir.size() + 4096) }
				return if v.save(unsafe { &dir }) { 0 } else { -5 }
			}
			at += record
		}
	}
	return -28
}

fn (mut v Volume) erase(parent u32, name &u8, length u32, replacement u32) int {
	mut dir := Node{}
	if !valid_name(name, length) { return -22 }
	if !v.inode(parent, mut dir) { return -5 }
	mut e := Entry{}
	mut at := u32(0)
	for {
		found := v.next(parent, at, mut e)
		if found <= 0 { return if found == 0 { -2 } else { found } }
		// next may skip unused records; recover the current record from its end.
		if e.length == length {
			mut same := true
			for i := u32(0); i < length; i++ { if e.name[i] != unsafe { name[i] } { same = false; break } }
			if same {
				mut b := [4096]u8{}
				block := v.data_block(unsafe { &dir }, (e.next - 1) / 4096, false)
				if block == 0 || !v.read_block(block, unsafe { &b[0] }) { return -5 }
				for pos := u32(0); pos < 4096; {
					record := le16(unsafe { &b[0] }, pos + 4)
					if record < 8 || record > 4096 - pos { return -5 }
					if (e.next - 1) / 4096 * 4096 + pos + record == e.next {
						put32(unsafe { &b[0] }, pos, replacement)
						if replacement != 0 {
							mut target := Node{}
							if !v.inode(replacement, mut target) { return -5 }
							b[pos + 7] = if target.mode() & 0xf000 == 0xa000 { u8(7) } else { u8(1) }
						}
						return if v.write_block(block, unsafe { &b[0] }) { 0 } else { -5 }
					}
					pos += record
				}
				return -5
			}
		}
		at = e.next
	}
	return -2
}

pub fn (mut v Volume) create(parent u32, name &u8, length u32, mode u32) int {
	if !valid_name(name, length) { return -22 }
	existing := v.lookup(parent, name, length)
	if existing != -2 { return if existing < 0 { existing } else { -17 } }
	directory := mode & 0xf000 == 0x4000
	mut n := Node{number: v.allocate(true, directory)}
	if n.number == 0 { return if v.failed { -5 } else { -28 } }
	put16(unsafe { &n.raw[0] }, 0, mode)
	put32(unsafe { &n.raw[0] }, 8, v.epoch)
	put32(unsafe { &n.raw[0] }, 12, v.epoch)
	put32(unsafe { &n.raw[0] }, 16, v.epoch)
	put16(unsafe { &n.raw[0] }, 26, if directory { u32(2) } else { u32(1) })
	if !v.save(unsafe { &n }) { return -5 }
	if directory {
		mut b := [4096]u8{}
		block := v.data_block(unsafe { &n }, 0, true)
		if block == 0 { v.abandon(unsafe { &n }); return -28 }
		entry_bytes(unsafe { &b[0] }, n.number, 12, unsafe { &u8(c'.') }, 1, 0x4000)
		entry_bytes(unsafe { &b[12] }, parent, 4084, unsafe { &u8(c'..') }, 2, 0x4000)
		put32(unsafe { &n.raw[0] }, 4, 4096)
		if !v.write_block(block, unsafe { &b[0] }) || !v.save(unsafe { &n }) { return -5 }
	}
	result := v.insert(parent, name, length, unsafe { &n })
	if result != 0 { v.abandon(unsafe { &n }); return result }
	if directory {
		mut dir := Node{}
		if !v.inode(parent, mut dir) { return -5 }
		put16(unsafe { &dir.raw[0] }, 26, dir.links() + 1)
		if !v.save(unsafe { &dir }) { return -5 }
	}
	return int(n.number)
}

pub fn (mut v Volume) reap(number u32) bool {
	mut n := Node{}
	if !v.inode(number, mut n) || n.links() != 0 { return false }
	if !(n.mode() & 0xf000 == 0xa000 && n.blocks() == 0) && !v.clear_blocks(unsafe { &n }) { return false }
	put32(unsafe { &n.raw[0] }, 20, v.epoch)
	if !v.save(unsafe { &n }) { return false }
	return v.release(number, true, n.mode() & 0xf000 == 0x4000)
}

fn (mut v Volume) abandon(n &Node) {
	put16(unsafe { &n.raw[0] }, 26, 0)
	if v.save(n) { v.reap(n.number) }
}

pub fn (mut v Volume) unlink(parent u32, name &u8, length u32, directory bool, keep_open bool) int {
	id := v.lookup(parent, name, length)
	if id < 0 { return id }
	mut n := Node{}
	if !v.inode(u32(id), mut n) { return -5 }
	if directory != (n.mode() & 0xf000 == 0x4000) { return if directory { -20 } else { -21 } }
	if directory {
		mut e := Entry{}
		mut at := u32(0)
		for {
			result := v.next(n.number, at, mut e)
			if result < 0 { return result }
			if result == 0 { break }
			at = e.next
			if !(e.name[0] == `.` && (e.length == 1 || (e.length == 2 && e.name[1] == `.`))) { return -39 }
		}
	}
	result := v.erase(parent, name, length, 0)
	if result != 0 { return result }
	put16(unsafe { &n.raw[0] }, 26, if directory { u32(0) } else { n.links() - 1 })
	if !v.save(unsafe { &n }) { return -5 }
	if directory {
		mut dir := Node{}
		if !v.inode(parent, mut dir) { return -5 }
		put16(unsafe { &dir.raw[0] }, 26, dir.links() - 1)
		if !v.save(unsafe { &dir }) { return -5 }
	}
	if n.links() == 0 && !keep_open && !v.reap(n.number) { return -5 }
	return 0
}

pub fn (mut v Volume) rename(old_parent u32, old_name &u8, old_length u32, new_parent u32, new_name &u8, new_length u32, keep_replaced bool) int {
	id := v.lookup(old_parent, old_name, old_length)
	if id < 0 { return id }
	mut n := Node{}
	if !v.inode(u32(id), mut n) { return -5 }
	if n.mode() & 0xf000 == 0x4000 { return -95 } // directory moves need parent-cycle checks
	target := v.lookup(new_parent, new_name, new_length)
	if target == id { return 0 }
	if target < 0 && target != -2 { return target }
	if target > 0 {
		mut other := Node{}
		if !v.inode(u32(target), mut other) { return -5 }
		if other.mode() & 0xf000 == 0x4000 { return -21 }
	}
	// Namespace updates are serialized by the single-process kernel. fsync
	// flushes all metadata; ext2 itself is not a power-loss journal.
	result := if target > 0 { v.erase(new_parent, new_name, new_length, n.number) }
		else { v.insert(new_parent, new_name, new_length, unsafe { &n }) }
	if result != 0 { return result }
	removed := v.erase(old_parent, old_name, old_length, 0)
	if removed != 0 { return removed }
	if target > 0 {
		mut other := Node{}
		if !v.inode(u32(target), mut other) { return -5 }
		put16(unsafe { &other.raw[0] }, 26, other.links() - 1)
		if !v.save(unsafe { &other }) || (other.links() == 0 && !keep_replaced && !v.reap(other.number)) { return -5 }
	}
	return 0
}

pub fn (mut v Volume) symlink(parent u32, name &u8, length u32, target &u8, size u32) int {
	if size == 0 || size > 60 { return -36 }
	id := v.create(parent, name, length, 0xa1ff)
	if id < 0 { return id }
	mut n := Node{}
	if !v.inode(u32(id), mut n) { return -5 }
	copy_bytes(unsafe { &n.raw[40] }, target, size)
	put32(unsafe { &n.raw[0] }, 4, size)
	return if v.save(unsafe { &n }) { 0 } else { -5 }
}

pub fn (mut v Volume) readlink(number u32, target &u8, capacity u32) int {
	mut n := Node{}
	if !v.inode(number, mut n) { return -5 }
	if n.mode() & 0xf000 != 0xa000 { return -22 }
	if n.size() > 60 || n.blocks() != 0 { return -95 }
	count := if n.size() < capacity { n.size() } else { capacity }
	copy_bytes(target, unsafe { &n.raw[40] }, count)
	return int(count)
}
