// SPDX-License-Identifier: GPL-2.0-or-later
// Small, allocation-free ext2 implementation for the initial PPC process.
// On-disk integers are decoded explicitly: the CPU and filesystem differ.
module ext2

pub struct Device {
pub:
	read fn (u32, &u8) bool = unsafe { nil }
	write fn (u32, &u8) bool = unsafe { nil }
	flush fn () bool = unsafe { nil }
	sectors u32
}

pub struct Node {
pub mut:
	number u32
	raw [128]u8
}

pub struct Volume {
pub mut:
	device Device
	blocks u32
	inodes u32
	block_bitmap u32
	inode_bitmap u32
	inode_table u32
	first_data u32
	epoch u32
	failed bool
	mounted bool
}

pub fn le16(p &u8, at u32) u32 { return unsafe { u32(p[at]) | u32(p[at + 1]) << 8 } }
pub fn le32(p &u8, at u32) u32 { return unsafe { le16(p, at) | le16(p, at + 2) << 16 } }
fn put16(p &u8, at u32, x u32) { unsafe { p[at] = u8(x); p[at + 1] = u8(x >> 8) } }
fn put32(p &u8, at u32, x u32) { put16(p, at, x); put16(p, at + 2, x >> 16) }
fn clear(p &u8, count u32) { unsafe { for i := u32(0); i < count; i++ { p[i] = 0 } } }
fn copy_bytes(dst &u8, src &u8, count u32) { unsafe { for i := u32(0); i < count; i++ { dst[i] = src[i] } } }

pub fn (n &Node) mode() u32 { return le16(unsafe { &n.raw[0] }, 0) }
pub fn (n &Node) size() u32 { return le32(unsafe { &n.raw[0] }, 4) }
pub fn (n &Node) links() u32 { return le16(unsafe { &n.raw[0] }, 26) }
pub fn (n &Node) blocks() u32 { return le32(unsafe { &n.raw[0] }, 28) }

fn (mut v Volume) read_block(block u32, p &u8) bool {
	if v.failed || block >= v.blocks { return false }
	for i := u32(0); i < 8; i++ {
		if !v.device.read(block * 8 + i, unsafe { &p[i * 512] }) { v.failed = true; return false }
	}
	return true
}

fn (mut v Volume) write_block(block u32, p &u8) bool {
	if !v.mounted || v.failed || block >= v.blocks { return false }
	for i := u32(0); i < 8; i++ {
		if !v.device.write(block * 8 + i, unsafe { &p[i * 512] }) { v.failed = true; return false }
	}
	return true
}

pub fn (mut v Volume) mount(device Device) bool {
	v = Volume{device: device, blocks: device.sectors / 8}
	mut b := [4096]u8{}
	if v.blocks < 32 || !v.read_block(0, unsafe { &b[0] }) { return false }
	s := unsafe { &b[1024] }
	// Deliberately reject layouts we cannot safely update: one block group,
	// 4 KiB blocks, 128-byte inodes, no journal/ACL/index/extents/checksums.
	if le16(s, 56) != 0xef53 || le32(s, 24) != 2 || le32(s, 20) != 0
		|| le32(s, 76) != 1 || le16(s, 88) != 128 || le32(s, 84) != 11
		|| le32(s, 92) != 0 || le32(s, 96) != 2 || le32(s, 100) & ~u32(3) != 0
		|| le32(s, 32) != 32768 || le32(s, 4) > 32768 || le32(s, 4) > v.blocks
		|| le32(s, 0) < 16 || le32(s, 0) > 32768 || le32(s, 40) != le32(s, 0) { return false }
	v.blocks = le32(s, 4)
	v.inodes = le32(s, 0)
	v.epoch = if le32(s, 48) != 0 { le32(s, 48) } else { u32(1) }
	if !v.read_block(1, unsafe { &b[0] }) { return false }
	v.block_bitmap = le32(unsafe { &b[0] }, 0)
	v.inode_bitmap = le32(unsafe { &b[0] }, 4)
	v.inode_table = le32(unsafe { &b[0] }, 8)
	v.first_data = v.inode_table + (v.inodes + 31) / 32
	if v.block_bitmap < 2 || v.inode_bitmap <= v.block_bitmap || v.inode_table <= v.inode_bitmap
		|| v.first_data >= v.blocks { return false }
	mut root := Node{}
	if !v.inode(2, mut root) || root.mode() & 0xf000 != 0x4000 { return false }
	v.mounted = true
	return true
}

pub fn (mut v Volume) sync() bool {
	if v.failed || !v.mounted || !v.device.flush() { v.failed = true; return false }
	return true
}

pub fn (mut v Volume) inode(number u32, mut n Node) bool {
	if number == 0 || number > v.inodes { return false }
	mut b := [4096]u8{}
	if !v.read_block(v.inode_table + (number - 1) / 32, unsafe { &b[0] }) { return false }
	n.number = number
	copy_bytes(unsafe { &n.raw[0] }, unsafe { &b[((number - 1) % 32) * 128] }, 128)
	return le32(unsafe { &n.raw[0] }, 104) == 0 && le32(unsafe { &n.raw[0] }, 108) == 0
		&& (n.mode() & 0xf000 != 0x8000 || n.size() <= 1036 * 4096)
}

fn (mut v Volume) save(n &Node) bool {
	if n.number == 0 || n.number > v.inodes { return false }
	mut b := [4096]u8{}
	block := v.inode_table + (n.number - 1) / 32
	if !v.read_block(block, unsafe { &b[0] }) { return false }
	copy_bytes(unsafe { &b[((n.number - 1) % 32) * 128] }, unsafe { &n.raw[0] }, 128)
	return v.write_block(block, unsafe { &b[0] })
}

// Persist both redundant free-space counts whenever a bitmap changes.
fn (mut v Volume) accounting(inodes bool, delta int, directories int) bool {
	mut b := [4096]u8{}
	if !v.read_block(0, unsafe { &b[0] }) { return false }
	at := if inodes { u32(1040) } else { u32(1036) }
	old := le32(unsafe { &b[0] }, at)
	if (delta < 0 && old == 0) || (delta > 0 && old >= if inodes { v.inodes } else { v.blocks }) { v.failed = true; return false }
	put32(unsafe { &b[0] }, at, u32(int(old) + delta))
	if !v.write_block(0, unsafe { &b[0] }) || !v.read_block(1, unsafe { &b[0] }) { return false }
	offset := if inodes { u32(14) } else { u32(12) }
	put16(unsafe { &b[0] }, offset, u32(int(le16(unsafe { &b[0] }, offset)) + delta))
	if directories != 0 { put16(unsafe { &b[0] }, 16, u32(int(le16(unsafe { &b[0] }, 16)) + directories)) }
	return v.write_block(1, unsafe { &b[0] })
}

fn (mut v Volume) allocate(inodes bool, directory bool) u32 {
	mut b := [4096]u8{}
	bitmap := if inodes { v.inode_bitmap } else { v.block_bitmap }
	if !v.read_block(bitmap, unsafe { &b[0] }) { return 0 }
	first := if inodes { u32(10) } else { v.first_data }
	limit := if inodes { v.inodes } else { v.blocks }
	for i := first; i < limit; i++ {
		mask := u8(1 << (i & 7))
		if b[i / 8] & mask != 0 { continue }
		b[i / 8] |= mask
		if !v.write_block(bitmap, unsafe { &b[0] }) || !v.accounting(inodes, -1, if directory { 1 } else { 0 }) { return 0 }
		if inodes { return i + 1 }
		clear(unsafe { &b[0] }, 4096)
		if !v.write_block(i, unsafe { &b[0] }) { return 0 }
		return i
	}
	return 0
}

fn (mut v Volume) release(number u32, inodes bool, directory bool) bool {
	i := if inodes { number - 1 } else { number }
	if (inodes && (number < 11 || number > v.inodes)) || (!inodes && (number < v.first_data || number >= v.blocks)) { return false }
	mut b := [4096]u8{}
	bitmap := if inodes { v.inode_bitmap } else { v.block_bitmap }
	if !v.read_block(bitmap, unsafe { &b[0] }) { return false }
	mask := u8(1 << (i & 7))
	if b[i / 8] & mask == 0 { v.failed = true; return false }
	b[i / 8] &= ~mask
	return v.write_block(bitmap, unsafe { &b[0] }) && v.accounting(inodes, 1, if directory { -1 } else { 0 })
}

fn (mut v Volume) data_block(mut n Node, index u32, create bool) u32 {
	if index >= 1036 { return 0 }
	mut indirect := [4096]u8{}
	mut p := unsafe { &n.raw[0] }
	mut offset := 40 + index * 4
	mut table := u32(0)
	if index >= 12 {
		table = le32(p, 88)
		if table == 0 && create {
			table = v.allocate(false, false)
			if table == 0 { return 0 }
			put32(p, 88, table); put32(p, 28, n.blocks() + 8)
			if !v.save(n) { return 0 }
		}
		if table < v.first_data || table >= v.blocks || !v.read_block(table, unsafe { &indirect[0] }) { return 0 }
		p = unsafe { &indirect[0] }; offset = (index - 12) * 4
	}
	mut block := le32(p, offset)
	if block == 0 && create {
		block = v.allocate(false, false)
		if block == 0 { return 0 }
		put32(p, offset, block)
		put32(unsafe { &n.raw[0] }, 28, n.blocks() + 8)
		if table != 0 && !v.write_block(table, p) { return 0 }
		if !v.save(n) { return 0 }
	}
	return if block >= v.first_data && block < v.blocks { block } else { u32(0) }
}

pub fn (mut v Volume) read(number u32, offset u32, data &u8, count u32) int {
	mut n := Node{}
	if !v.inode(number, mut n) { return -5 }
	if n.mode() & 0xf000 == 0x4000 { return -21 }
	if n.mode() & 0xf000 != 0x8000 { return -22 }
	if offset >= n.size() { return 0 }
	actual := if count < n.size() - offset { count } else { n.size() - offset }
	mut b := [4096]u8{}
	mut done := u32(0)
	for done < actual {
		pos := offset + done
		block := v.data_block(mut n, pos / 4096, false)
		if block == 0 { clear(unsafe { &b[0] }, 4096) }
		else if !v.read_block(block, unsafe { &b[0] }) { return -5 }
		amount := if actual - done < 4096 - pos % 4096 { actual - done } else { 4096 - pos % 4096 }
		copy_bytes(unsafe { &data[done] }, unsafe { &b[pos % 4096] }, amount)
		done += amount
	}
	return int(done)
}

pub fn (mut v Volume) write(number u32, offset u32, data &u8, count u32) int {
	mut n := Node{}
	if !v.inode(number, mut n) { return -5 }
	if n.mode() & 0xf000 != 0x8000 { return -21 }
	if offset > 1036 * 4096 || count > 1036 * 4096 - offset { return -27 }
	mut b := [4096]u8{}
	mut done := u32(0)
	for done < count {
		pos := offset + done
		block := v.data_block(mut n, pos / 4096, true)
		if block == 0 { return if done > 0 { int(done) } else if v.failed { -5 } else { -28 } }
		if !v.read_block(block, unsafe { &b[0] }) { return if done > 0 { int(done) } else { -5 } }
		amount := if count - done < 4096 - pos % 4096 { count - done } else { 4096 - pos % 4096 }
		copy_bytes(unsafe { &b[pos % 4096] }, unsafe { &data[done] }, amount)
		if !v.write_block(block, unsafe { &b[0] }) { return -5 }
		done += amount
		if offset + done > n.size() { put32(unsafe { &n.raw[0] }, 4, offset + done) }
		if !v.save(&n) { return -5 }
	}
	return int(done)
}

pub fn (mut v Volume) chmod(number u32, mode u32) int {
	mut n := Node{}
	if !v.inode(number, mut n) { return -5 }
	put16(unsafe { &n.raw[0] }, 0, (n.mode() & 0xf000) | (mode & 0xfff))
	return if v.save(&n) { 0 } else { -5 }
}

pub fn (mut v Volume) truncate(number u32) int {
	mut n := Node{}
	if !v.inode(number, mut n) || n.mode() & 0xf000 != 0x8000 { return -5 }
	return if v.clear_blocks(mut n) && v.save(&n) { 0 } else { -5 }
}

fn (mut v Volume) clear_blocks(mut n Node) bool {
	if le32(unsafe { &n.raw[0] }, 92) != 0 || le32(unsafe { &n.raw[0] }, 96) != 0 { return false }
	for i := u32(0); i < 1036; i++ {
		block := v.data_block(mut n, i, false)
		if block != 0 && !v.release(block, false, false) { return false }
		if i == 11 && le32(unsafe { &n.raw[0] }, 88) == 0 { break }
	}
	table := le32(unsafe { &n.raw[0] }, 88)
	if table != 0 && !v.release(table, false, false) { return false }
	clear(unsafe { &n.raw[40] }, 60)
	put32(unsafe { &n.raw[0] }, 4, 0); put32(unsafe { &n.raw[0] }, 28, 0)
	return true
}
