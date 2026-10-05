// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
@[translated]
module ext2core

#include "apple_ans_ext2.h"

pub type Vinix_ext2_reader = fn (voidptr, voidptr, u64, usize) i32
pub type Vinix_ext2_writer = fn (voidptr, voidptr, u64, usize) i32

// Native-endian u64 fields: size, mode, uid, gid, nlink, blocks(512-byte),
// *atime, mtime, ctime, filesystem block size.

// Returns 1 for an entry, 0 for EOF, negative errno on failure. Offset is a
// *directory byte cursor. Name capacity must be at least 256.

// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.
// SPDX-License-Identifier: GPL-2.0-or-later
// *Bounded classic-ext2 reader/writer. Layout references:
// *docs.kernel.org/filesystems/ext2.html and ext4/{super,inodes,directory}.html.
// *Does not invoke Vinix's legacy ext2 allocator or assume 512-byte device LBAs.
// *Writable operation is intentionally limited to non-journaled, non-indexed
// *ext2. Metadata is written in leak-before-corruption order and a dirty mount
// *is refused; recovery after an interrupted mutation belongs to an external
// *fsck, not to this small kernel driver.
//

pub struct E2_fs {
pub mut:
	read_       Vinix_ext2_reader
	write_      Vinix_ext2_writer
	cookie      voidptr
	bytes       u64
	block_size  u32
	inode_size  u32
	blocks      u32
	inodes      u32
	first       u32
	bpg         u32
	ipg         u32
	groups      u32
	first_inode u32
	filetype    u32
	largefile   u32
	opened      u32
	writable    u32
	active      u32
	failed      u32
}

pub struct E2_inode {
pub mut:
	size      u64
	mode      u32
	uid       u32
	gid       u32
	links     u32
	sectors   u32
	flags     u32
	times     [3]u32
	ptr       [15]u32
	data      [60]u8
	fast_link i32
}

@[export: 'e2_u16']
pub fn e2_u16(p &u8) u16 {
	unsafe {
		return u16((i32(p[0]) | i32(u16(p[1])) << 8))
	}
}

@[export: 'e2_u32']
pub fn e2_u32(p &u8) u32 {
	unsafe {
		return u32(e2_u16(p)) | u32(e2_u16(p + 2)) << 16
	}
}

@[export: 'e2_p16']
pub fn e2_p16(p &u8, v u16) {
	unsafe {
		p[0] = u8(v)
		p[1] = u8((i32(v) >> 8))
	}
}

@[export: 'e2_p32']
pub fn e2_p32(p &u8, v u32) {
	unsafe {
		e2_p16(p, u16(v))
		e2_p16(p + 2, u16((v >> 16)))
	}
}

@[export: 'e2_zero']
pub fn e2_zero(p voidptr, n usize) {
	unsafe {
		b := &u8(p)
		for i := usize(0); i < n; i++ { b[i] = 0 }
	}
}

@[export: 'e2_copy']
pub fn e2_copy(d voidptr, s voidptr, n usize) {
	unsafe {
		a := &u8(d)
		b := &u8(s)
		for i := usize(0); i < n; i++ { a[i] = b[i] }
	}
}

@[export: 'e2_disk']
pub fn e2_disk(fs &E2_fs, p voidptr, off u64, n usize) i32 {
	unsafe {
		if (usize(fs) == 0) || !fs.opened || (usize(fs.read_) == 0) || ((usize(p) == 0) && n) || off > fs.bytes || u64(n) > fs.bytes - off {
			return -22
		}
		return if fs.read_(voidptr(fs.cookie), voidptr(p), off, n) { (-5) } else { 0 }
	}
}

@[export: 'e2_store']
pub fn e2_store(fs &E2_fs, p voidptr, off u64, n usize) i32 {
	unsafe {
		if (usize(fs) == 0) || !fs.opened || !fs.writable || !fs.active || (usize(fs.write_) == 0) || ((usize(p) == 0) && n) || off > fs.bytes || u64(n) > fs.bytes - off {
			return -30
		}
		if fs.write_(voidptr(fs.cookie), voidptr(p), off, n) {
			// A failed metadata or data transfer may have reached the SSD only in
			//         *part. Freeze this mount and keep the superblock dirty for fsck.

			fs.failed = u32(1)
			fs.active = u32(0)
			return -5
		}
		return 0
	}
}

@[export: 'e2_block_valid']
pub fn e2_block_valid(fs &E2_fs, block u32) i32 {
	unsafe {
		return i32(block >= fs.first && block < fs.blocks && block != u32(0))
	}
}

@[export: 'e2_inode_get']
pub fn e2_inode_get(fs &E2_fs, ino u32, out &E2_inode) i32 {
	unsafe {
		desc := [32]u8{}
		raw := [128]u8{}

		if (usize(fs) == 0) || !fs.opened || (usize(out) == 0) || !ino || ino > fs.inodes {
			return -22
		}
		group := (ino - u32(1)) / fs.ipg
		slot := (ino - u32(1)) % fs.ipg

		if group >= fs.groups {
			return -22
		}
		bgdt := u64((fs.first + u32(1))) * u64(fs.block_size)
		if e2_disk(fs, voidptr(&desc[0]), bgdt + u64(group) * u64(32), sizeof([32]u8)) {
			return -5
		}
		table := e2_u32(&desc[0] + 8)
		group_first := u64(fs.first) + u64(group) * u64(fs.bpg)
		group_end := group_first + u64(fs.bpg)
		if group_end > u64(fs.blocks) {
			group_end = u64(fs.blocks)
		}
		table_blocks := (u64(fs.ipg) * u64(fs.inode_size) + u64(fs.block_size) - u64(1)) / u64(fs.block_size)
		if !e2_block_valid(fs, table) || u64(table) < group_first || u64(table) >= group_end || table_blocks > group_end - u64(table) {
			return -22
		}
		if e2_disk(fs, voidptr(&raw[0]), u64(table) * u64(fs.block_size) + u64(slot) * u64(fs.inode_size), sizeof([128]u8)) {
			return -5
		}
		v := E2_inode{}

		v.mode = u32(e2_u16(&raw[0]))
		v.links = u32(e2_u16(&raw[0] + 26))
		kind := v.mode & 61440
		flags := e2_u32(&raw[0] + 32)

		// Reject encodings this reader does not implement, not just extents.

		if (kind != 16384 && kind != 32768 && kind != 40960) || !v.links || e2_u32(&raw[0] + 20) || (flags & ~(16 | 32 | 64 | 128 | 4096)) {
			return -95
		}
		v.flags = flags
		v.size = u64(e2_u32(&raw[0] + 4))
		if kind == 32768 {
			high := e2_u32(&raw[0] + 108)
			if high && !fs.largefile {
				return -95
			}
			v.size |= u64(high) << 32
		}
		per := u64(fs.block_size / u32(4))
		max_blocks := u64(12) + per + per * per + per * per * per
		if (v.size > max_blocks * u64(fs.block_size)) || (v.size > u64(9223372036854775807)) || (kind == 16384 && (v.size > u64(67108864) || v.size % u64(fs.block_size))) || (kind == 40960 && (!v.size || v.size > u64(4095))) {
			return -22
		}
		v.uid = u32(e2_u16(&raw[0] + 2)) | u32(e2_u16(&raw[0] + 120)) << 16
		v.gid = u32(e2_u16(&raw[0] + 24)) | u32(e2_u16(&raw[0] + 122)) << 16
		v.sectors = e2_u32(&raw[0] + 28)
		v.times[0] = e2_u32(&raw[0] + 8)
		v.times[1] = e2_u32(&raw[0] + 16)
		v.times[2] = e2_u32(&raw[0] + 12)
		for i := u32(0); i < u32(15); i++ {
			v.ptr[i] = e2_u32(&raw[0] + 40 + (i * u32(4)))
		}
		e2_copy(v.data, voidptr(&raw[0] + 40), usize(60))
		acl := e2_u32(&raw[0] + 104)
		if acl && !e2_block_valid(fs, acl) {
			return -22
		}
		v.fast_link = kind == 40960 && v.size <= u64(60) && v.sectors == (if acl {
			fs.block_size / u32(512)
		} else {
			u32(0)
		})
		*out = v
		return 0
	}
}

@[export: 'e2_map']
pub fn e2_map(fs &E2_fs, in_ &E2_inode, logical u64, out &u32) i32 {
	unsafe {
		if logical < u64(12) {
			*out = in_.ptr[logical]
			return if !(*out) || e2_block_valid(fs, (*out)) { 0 } else { (-22) }
		}
		per := u64(fs.block_size / u32(4))
		span := per

		logical -= u64(12)
		level := u32(1)
		for level < u32(3) && logical >= span {
			logical -= span
			span *= per
			level++
		}
		if logical >= span {
			return -22
		}
		block := in_.ptr[u32(11) + level]
		for ; level; level-- {
			if !block {
				*out = u32(0)
				return 0
			}
			if !e2_block_valid(fs, block) {
				return -22
			}
			span /= per
			index := logical / span
			logical %= span
			raw := [4]u8{}
			if e2_disk(fs, voidptr(&raw[0]), u64(block) * u64(fs.block_size) + index * u64(4), usize(4)) {
				return -5
			}
			block = e2_u32(&raw[0])
		}
		if block && !e2_block_valid(fs, block) {
			return -22
		}
		*out = block
		return 0
	}
}

@[export: 'e2_read_inode']
pub fn e2_read_inode(fs &E2_fs, in_ &E2_inode, buffer voidptr, offset u64, count usize) i64 {
	unsafe {
		if ((usize(buffer) == 0) && count) || offset > in_.size {
			return i64((-22))
		}
		if u64(count) > in_.size - offset {
			count = usize((in_.size - offset))
		}
		if count > usize(1048576) {
			count = usize(1048576)
		}
		p := &u8(buffer)
		if in_.fast_link {
			e2_copy(voidptr(p), voidptr(&in_.data[0] + offset), count)
			return i64(count)
		}
		done := usize(0)
		for done < count {
			pos := offset + u64(done)
			within := u32((pos % u64(fs.block_size)))
			n := usize(fs.block_size - within)
			if n > count - done {
				n = count - done
			}
			block := u32(0)
			rc := e2_map(fs, in_, pos / u64(fs.block_size), &block)
			if rc {
				return i64(rc)
			}
			if !block {
				e2_zero(voidptr(p + done), n)
			} else if e2_disk(fs, voidptr(p + done), u64(block) * u64(fs.block_size) + u64(within), n) {
				return i64((-5))
			}
			done += n
		}
		return i64(done)
	}
}

@[export: 'vinix_ext2_context_size']
pub fn vinix_ext2_context_size() usize {
	unsafe {
		return usize(sizeof(E2_fs))
	}
}

@[export: 'e2_open']
pub fn e2_open(context voidptr, size usize, read Vinix_ext2_reader, write Vinix_ext2_writer, cookie voidptr, bytes u64) i32 {
	unsafe {
		if (usize(context) == 0) || size < sizeof(E2_fs) || (usize(read) == 0) || bytes < u64(4096) {
			return -22
		}
		e2_zero(voidptr(context), sizeof(E2_fs))
		sb := [1024]u8{}
		if read(voidptr(cookie), voidptr(&sb[0]), u64(1024), sizeof([1024]u8)) {
			return -5
		}
		revision := e2_u32(&sb[0] + 76)
		shift := e2_u32(&sb[0] + 24)

		if (i32(e2_u16(&sb[0] + 56)) != 61267) || (revision > u32(1)) || (shift > u32(2)) || (e2_u32(&sb[0] + 72) != u32(0)) || (i32(e2_u16(&sb[0] + 58)) != 1) || (e2_u32(&sb[0] + 232)) || (e2_u32(&sb[0] + 28) != shift) {
			return -95
		}
		compat := if revision { e2_u32(&sb[0] + 92) } else { u32(0) }
		incompat := if revision { e2_u32(&sb[0] + 96) } else { u32(0) }
		rocompat := if revision { e2_u32(&sb[0] + 100) } else { u32(0) }
		// Classic ext2 only: ext_attr, resize_inode, dir_index, FILETYPE,
		//     *sparse_super and large_file. No journal/recovery, extents or checksums.

		if (compat & ~56) || (incompat & ~2) || (rocompat & ~3) || (!(usize(write) == 0) && ((compat & ~8) || !(incompat & 2))) {
			return -95
		}
		fs := E2_fs{}

		fs.block_size = 1024 << shift
		fs.inode_size = u32(if revision { i32(e2_u16(&sb[0] + 88)) } else { 128 })
		fs.blocks = e2_u32(&sb[0] + 4)
		fs.inodes = e2_u32(&sb[0])
		fs.first = e2_u32(&sb[0] + 20)
		fs.bpg = e2_u32(&sb[0] + 32)
		fs.ipg = e2_u32(&sb[0] + 40)
		fs.first_inode = if revision { e2_u32(&sb[0] + 84) } else { u32(11) }
		// Older read-only fixtures and revision-1 images produced by early tools
		//     *sometimes leave s_first_ino zero. Never accept that ambiguity for a
		//     *writable mount, but retain the established read-only compatibility.

		if (usize(write) == 0) && !fs.first_inode {
			fs.first_inode = u32(11)
		}
		if (fs.first != (if shift { 0 } else { 1 })) || (fs.blocks <= fs.first + u32(2)) || (fs.inodes < u32(2)) || (!fs.bpg) || (fs.bpg > fs.block_size * u32(8)) || (!fs.ipg) || (fs.ipg > fs.block_size * u32(8)) || (fs.inode_size < u32(128)) || (fs.inode_size > fs.block_size) || (fs.inode_size & (fs.inode_size - u32(1))) || (e2_u32(&sb[0] + 36) != fs.bpg) || (fs.first_inode < u32(11)) || (fs.first_inode > fs.inodes) || (u64(fs.blocks) * u64(fs.block_size) > bytes) {
			return -22
		}
		fs.groups = u32(((u64(fs.blocks) - u64(fs.first) + u64(fs.bpg) - u64(1)) / u64(fs.bpg)))
		if (u64(fs.inodes) + u64(fs.ipg) - u64(1)) / u64(fs.ipg) > u64(fs.groups) || u64((fs.first + u32(1))) * u64(fs.block_size) + u64(fs.groups) * u64(32) > u64(fs.blocks) * u64(fs.block_size) {
			return -22
		}
		fs.bytes = u64(fs.blocks) * u64(fs.block_size)
		fs.cookie = cookie
		fs.read_ = read
		fs.write_ = write
		fs.opened = u32(1)
		fs.writable = u32(write != (voidptr(0)))
		fs.filetype = incompat & u32(2)
		fs.largefile = rocompat & u32(2)
		root := E2_inode{}
		rc := e2_inode_get(&fs, u32(2), &root)
		if rc || (root.mode & 61440) != 16384 || !root.size {
			return if rc { rc } else { (-22) }
		}
		e2_copy(voidptr(context), voidptr(&fs), sizeof(fs))
		return 0
	}
}

@[export: 'vinix_ext2_open']
pub fn vinix_ext2_open(context voidptr, size usize, read Vinix_ext2_reader, cookie voidptr, bytes u64) i32 {
	unsafe {
		return e2_open(voidptr(context), size, read, (voidptr(0)), voidptr(cookie), bytes)
	}
}

@[export: 'vinix_ext2_open_rw']
pub fn vinix_ext2_open_rw(context voidptr, size usize, read Vinix_ext2_reader, write Vinix_ext2_writer, cookie voidptr, bytes u64) i32 {
	unsafe {
		if usize(write) == 0 {
			return -22
		}
		return e2_open(voidptr(context), size, read, write, voidptr(cookie), bytes)
	}
}

@[export: 'vinix_ext2_begin_write']
pub fn vinix_ext2_begin_write(context voidptr) i32 {
	unsafe {
		fs := &E2_fs(context)
		if (usize(fs) == 0) || !fs.opened || !fs.writable || fs.active {
			return -22
		}
		state := [2]u8{}
		e2_p16(&state[0], u16(2))
		fs.active = u32(1)
		rc := e2_store(fs, voidptr(&state[0]), u64(1024 + 58), sizeof([2]u8))
		if rc {
			fs.active = u32(0)
		}
		return rc
	}
}

@[export: 'vinix_ext2_close_clean']
pub fn vinix_ext2_close_clean(context voidptr) i32 {
	unsafe {
		fs := &E2_fs(context)
		if (usize(fs) == 0) || !fs.opened || !fs.writable {
			return -22
		}
		if fs.failed {
			return -5
		}
		if !fs.active {
			return 0
		}
		state := [2]u8{}
		e2_p16(&state[0], u16(1))
		rc := e2_store(fs, voidptr(&state[0]), u64(1024 + 58), sizeof([2]u8))
		if !rc {
			fs.active = u32(0)
		}
		return rc
	}
}

@[export: 'vinix_ext2_stat']
pub fn vinix_ext2_stat(context voidptr, ino u32, fields &u64) i32 {
	unsafe {
		if usize(fields) == 0 {
			return -22
		}
		fs := &E2_fs(context)
		in_ := E2_inode{}
		rc := e2_inode_get(fs, ino, &in_)
		if rc {
			return rc
		}
		fields[0] = in_.size
		fields[1] = u64(in_.mode)
		fields[2] = u64(in_.uid)
		fields[3] = u64(in_.gid)
		fields[4] = u64(in_.links)
		fields[5] = u64(in_.sectors)
		for i := u32(0); i < u32(3); i++ {
			fields[u32(6) + i] = u64(in_.times[i])
		}
		fields[9] = u64(fs.block_size)
		return 0
	}
}

@[export: 'vinix_ext2_read']
pub fn vinix_ext2_read(context voidptr, ino u32, buffer voidptr, offset u64, n usize) i64 {
	unsafe {
		in_ := E2_inode{}
		fs := &E2_fs(context)
		rc := e2_inode_get(fs, ino, &in_)
		if rc {
			return i64(rc)
		}
		return e2_read_inode(fs, &in_, voidptr(buffer), offset, n)
	}
}

@[export: 'vinix_ext2_next']
pub fn vinix_ext2_next(context voidptr, directory u32, offset &u64, inode &u32, name &char, capacity usize) i32 {
	unsafe {
		if (usize(offset) == 0) || (usize(inode) == 0) || (usize(name) == 0) || capacity < usize(256) {
			return -22
		}
		fs := &E2_fs(context)
		in_ := E2_inode{}
		rc := e2_inode_get(fs, directory, &in_)
		if rc {
			return rc
		}
		if (in_.mode & 61440) != 16384 {
			return -20
		}
		if (*offset) > in_.size || ((*offset) & u64(3)) {
			return -22
		}
		pos := (*offset)
		for pos < in_.size {
			h := [8]u8{}
			if e2_read_inode(fs, &in_, voidptr(&h[0]), pos, usize(8)) != i64(8) {
				return -5
			}
			rec := u32(e2_u16(&h[0] + 4))
			len := u32(if fs.filetype { i32(h[6]) } else { i32(e2_u16(&h[0] + 6)) })

			ino := e2_u32(&h[0])
			if rec < u32(8) || (rec & u32(3)) || u64(rec) > u64(fs.block_size) - pos % u64(fs.block_size) || u64(rec) > in_.size - pos || len > u32(255) || len > rec - u32(8) || ino > fs.inodes {
				return -22
			}
			if !ino {
				pos += u64(rec)
				continue
			}
			if !len || (fs.filetype && i32(h[7]) > 7) {
				return -22
			}
			if e2_read_inode(fs, &in_, voidptr(name), pos + u64(8), usize(len)) != i64(len) {
				return -5
			}
			for i := u32(0); i < len; i++ {
				if !name[i] || i32(name[i]) == i8(`/`) {
					return -22
				}
			}
			name[len] = i8(0)
			*inode = ino
			*offset = pos + u64(rec)
			return 1
		}
		*offset = pos
		return 0
	}
}

// Writable classic-ext2 support.  The routines below intentionally keep the
// *mutation surface small: regular files use direct and singly-indirect blocks,
// *directory entries are linear, and all allocation bitmaps remain one block.
// *Those limits are validated before changing media.

@[export: 'e2_bgdt']
pub fn e2_bgdt(fs &E2_fs) u64 {
	unsafe {
		return u64((fs.first + u32(1))) * u64(fs.block_size)
	}
}

@[export: 'e2_desc_get']
pub fn e2_desc_get(fs &E2_fs, group u32, raw &u8) i32 {
	unsafe {
		if group >= fs.groups {
			return -22
		}
		return e2_disk(fs, voidptr(raw), e2_bgdt(fs) + u64(group) * u64(32), usize(32))
	}
}

@[export: 'e2_desc_put']
pub fn e2_desc_put(fs &E2_fs, group u32, raw &u8) i32 {
	unsafe {
		if group >= fs.groups {
			return -22
		}
		return e2_store(fs, voidptr(raw), e2_bgdt(fs) + u64(group) * u64(32), usize(32))
	}
}

@[export: 'e2_inode_offset']
pub fn e2_inode_offset(fs &E2_fs, ino u32, off &u64) i32 {
	unsafe {
		if !ino || ino > fs.inodes || (usize(off) == 0) {
			return -22
		}
		group := (ino - u32(1)) / fs.ipg
		slot := (ino - u32(1)) % fs.ipg

		desc := [32]u8{}
		rc := e2_desc_get(fs, group, &desc[0])
		if rc {
			return rc
		}
		table := e2_u32(&desc[0] + 8)
		if !e2_block_valid(fs, table) {
			return -22
		}
		*off = u64(table) * u64(fs.block_size) + u64(slot) * u64(fs.inode_size)
		return if (*off) <= fs.bytes && u64(128) <= fs.bytes - (*off) {
			0
		} else {
			(-22)
		}
	}
}

@[export: 'e2_inode_put']
pub fn e2_inode_put(fs &E2_fs, ino u32, in_ &E2_inode) i32 {
	unsafe {
		off := u64(0)
		raw := [128]u8{}
		rc := e2_inode_offset(fs, ino, &off)
		if rc {
			return rc
		}
		rc = e2_disk(fs, voidptr(&raw[0]), off, sizeof([128]u8))
		if rc {
			return rc
		}
		e2_p16(&raw[0], u16(in_.mode))
		e2_p16(&raw[0] + 2, u16(in_.uid))
		e2_p32(&raw[0] + 4, u32(in_.size))
		e2_p32(&raw[0] + 8, in_.times[0])
		e2_p32(&raw[0] + 12, in_.times[2])
		e2_p32(&raw[0] + 16, in_.times[1])
		e2_p32(&raw[0] + 20, u32(0))
		e2_p16(&raw[0] + 24, u16(in_.gid))
		e2_p16(&raw[0] + 26, u16(in_.links))
		e2_p32(&raw[0] + 28, in_.sectors)
		e2_p32(&raw[0] + 32, in_.flags)
		for i := u32(0); i < u32(15); i++ {
			e2_p32(&raw[0] + 40 + (i * u32(4)), in_.ptr[i])
		}
		e2_p32(&raw[0] + 108, if (in_.mode & 61440) == 32768 {
			u32((in_.size >> 32))
		} else {
			u32(0)
		})
		e2_p16(&raw[0] + 120, u16((in_.uid >> 16)))
		e2_p16(&raw[0] + 122, u16((in_.gid >> 16)))
		return e2_store(fs, voidptr(&raw[0]), off, sizeof([128]u8))
	}
}

@[export: 'e2_super_count']
pub fn e2_super_count(fs &E2_fs, offset u32, delta i32) i32 {
	unsafe {
		raw := [4]u8{}
		rc := e2_disk(fs, voidptr(&raw[0]), u64(u32(1024) + offset), usize(4))
		if rc {
			return rc
		}
		value := e2_u32(&raw[0])
		if (delta < 0 && value < u32(-delta)) || (delta > 0 && value > u32(4294967295) - u32(delta)) {
			return -22
		}
		value = if delta < 0 { value - u32(-delta) } else { value + u32(delta) }
		e2_p32(&raw[0], value)
		return e2_store(fs, voidptr(&raw[0]), u64(u32(1024) + offset), usize(4))
	}
}

@[export: 'e2_block_allocate']
pub fn e2_block_allocate(fs &E2_fs, out &u32) i32 {
	unsafe {
		if usize(out) == 0 {
			return -22
		}
		for group := u32(0); group < fs.groups; group++ {
			desc := [32]u8{}
			bitmap := [4096]u8{}

			rc := e2_desc_get(fs, group, &desc[0])
			if rc {
				return rc
			}
			free_count := e2_u16(&desc[0] + 12)
			if !free_count {
				continue
			}
			map_ := e2_u32(&desc[0])
			group_first := fs.first + group * fs.bpg

			group_end := group_first + fs.bpg
			if group_end < group_first || group_end > fs.blocks {
				group_end = fs.blocks
			}
			if !e2_block_valid(fs, map_) || group_first >= group_end {
				return -22
			}
			rc = e2_disk(fs, voidptr(&bitmap[0]), u64(map_) * u64(fs.block_size), usize(fs.block_size))
			if rc {
				return rc
			}
			for bit := u32(0); bit < group_end - group_first; bit++ {
				if i32(bitmap[bit >> 3]) & i32(u8((1 << (bit & u32(7))))) {
					continue
				}
				block := group_first + bit
				inode_map := e2_u32(&desc[0] + 4)
				table := e2_u32(&desc[0] + 8)

				table_blocks := (u64(fs.ipg) * u64(fs.inode_size) + u64(fs.block_size) - u64(1)) / u64(fs.block_size)
				if block == map_ || block == inode_map || (block >= table && u64(block) < u64(table) + table_blocks) {
					return -22
				}
				// corrupt bitmap tried to allocate metadata

				bitmap[bit >> 3] |= i32(u8((1 << (bit & u32(7)))))
				rc = e2_store(fs, voidptr(&bitmap[0]), u64(map_) * u64(fs.block_size), usize(fs.block_size))
				if rc {
					return rc
				}
				e2_p16(&desc[0] + 12, u16((i32(free_count) - 1)))
				rc = e2_desc_put(fs, group, &desc[0])
				if rc {
					return rc
				}
				rc = e2_super_count(fs, u32(12), -1)
				if rc {
					return rc
				}
				e2_zero(voidptr(&bitmap[0]), usize(fs.block_size))
				rc = e2_store(fs, voidptr(&bitmap[0]), u64(block) * u64(fs.block_size), usize(fs.block_size))
				if rc {
					return rc
				}
				*out = block
				return 0
			}
			return -22
			// descriptor and bitmap free counts disagree
		}
		return -28
	}
}

@[export: 'e2_block_free']
pub fn e2_block_free(fs &E2_fs, block u32) i32 {
	unsafe {
		if !e2_block_valid(fs, block) {
			return -22
		}
		group := (block - fs.first) / fs.bpg
		group_first := fs.first + group * fs.bpg
		bit := block - group_first

		desc := [32]u8{}
		bitmap := [4096]u8{}

		rc := e2_desc_get(fs, group, &desc[0])
		if rc {
			return rc
		}
		map_ := e2_u32(&desc[0])
		if !e2_block_valid(fs, map_) || bit >= fs.block_size * u32(8) {
			return -22
		}
		rc = e2_disk(fs, voidptr(&bitmap[0]), u64(map_) * u64(fs.block_size), usize(fs.block_size))
		if rc {
			return rc
		}
		if !(i32(bitmap[bit >> 3]) & i32(u8((1 << (bit & u32(7)))))) {
			return -22
		}
		bitmap[bit >> 3] &= i32(u8(~(1 << (bit & u32(7)))))
		rc = e2_store(fs, voidptr(&bitmap[0]), u64(map_) * u64(fs.block_size), usize(fs.block_size))
		if rc {
			return rc
		}
		count := e2_u16(&desc[0] + 12)
		if u32(count) == 65535 {
			return -22
		}
		e2_p16(&desc[0] + 12, u16((i32(count) + 1)))
		rc = e2_desc_put(fs, group, &desc[0])
		if rc {
			return rc
		}
		return e2_super_count(fs, u32(12), 1)
	}
}

@[export: 'e2_inode_allocate']
pub fn e2_inode_allocate(fs &E2_fs, out &u32) i32 {
	unsafe {
		if usize(out) == 0 {
			return -22
		}
		for group := u32(0); group < fs.groups; group++ {
			desc := [32]u8{}
			bitmap := [4096]u8{}

			rc := e2_desc_get(fs, group, &desc[0])
			if rc {
				return rc
			}
			free_count := e2_u16(&desc[0] + 14)
			if !free_count {
				continue
			}
			map_ := e2_u32(&desc[0] + 4)
			if !e2_block_valid(fs, map_) {
				return -22
			}
			rc = e2_disk(fs, voidptr(&bitmap[0]), u64(map_) * u64(fs.block_size), usize(fs.block_size))
			if rc {
				return rc
			}
			slots := fs.inodes - group * fs.ipg
			if slots > fs.ipg {
				slots = fs.ipg
			}
			for bit := u32(0); bit < slots; bit++ {
				ino := group * fs.ipg + bit + u32(1)
				if ino < fs.first_inode || (i32(bitmap[bit >> 3]) & i32(u8((1 << (bit & u32(7)))))) {
					continue
				}
				bitmap[bit >> 3] |= i32(u8((1 << (bit & u32(7)))))
				rc = e2_store(fs, voidptr(&bitmap[0]), u64(map_) * u64(fs.block_size), usize(fs.block_size))
				if rc {
					return rc
				}
				e2_p16(&desc[0] + 14, u16((i32(free_count) - 1)))
				rc = e2_desc_put(fs, group, &desc[0])
				if rc {
					return rc
				}
				rc = e2_super_count(fs, u32(16), -1)
				if rc {
					return rc
				}
				off := u64(0)
				rc = e2_inode_offset(fs, ino, &off)
				if rc {
					return rc
				}
				e2_zero(voidptr(&bitmap[0]), usize(fs.inode_size))
				rc = e2_store(fs, voidptr(&bitmap[0]), off, usize(fs.inode_size))
				if rc {
					return rc
				}
				*out = ino
				return 0
			}
			return -22
		}
		return -28
	}
}

@[export: 'e2_inode_free']
pub fn e2_inode_free(fs &E2_fs, ino u32) i32 {
	unsafe {
		if ino < fs.first_inode || ino > fs.inodes {
			return -22
		}
		group := (ino - u32(1)) / fs.ipg
		bit := (ino - u32(1)) % fs.ipg

		desc := [32]u8{}
		bitmap := [4096]u8{}

		rc := e2_desc_get(fs, group, &desc[0])
		if rc {
			return rc
		}
		map_ := e2_u32(&desc[0] + 4)
		if !e2_block_valid(fs, map_) {
			return -22
		}
		rc = e2_disk(fs, voidptr(&bitmap[0]), u64(map_) * u64(fs.block_size), usize(fs.block_size))
		if rc {
			return rc
		}
		if !(i32(bitmap[bit >> 3]) & i32(u8((1 << (bit & u32(7)))))) {
			return -22
		}
		bitmap[bit >> 3] &= i32(u8(~(1 << (bit & u32(7)))))
		rc = e2_store(fs, voidptr(&bitmap[0]), u64(map_) * u64(fs.block_size), usize(fs.block_size))
		if rc {
			return rc
		}
		count := e2_u16(&desc[0] + 14)
		if u32(count) == 65535 {
			return -22
		}
		e2_p16(&desc[0] + 14, u16((i32(count) + 1)))
		rc = e2_desc_put(fs, group, &desc[0])
		if rc {
			return rc
		}
		return e2_super_count(fs, u32(16), 1)
	}
}

@[export: 'e2_write_limit']
pub fn e2_write_limit(fs &E2_fs) u64 {
	unsafe {
		return u64((12 + fs.block_size / 4)) * u64(fs.block_size)
	}
}

@[export: 'e2_map_write']
pub fn e2_map_write(fs &E2_fs, in_ &E2_inode, logical u64, allocate i32, out &u32) i32 {
	unsafe {
		if usize(out) == 0 {
			return -22
		}
		if logical < u64(12) {
			if !in_.ptr[logical] && allocate {
				rc := e2_block_allocate(fs, &in_.ptr[0] + logical)
				if rc {
					return rc
				}
				in_.sectors += fs.block_size / u32(512)
			}
			*out = in_.ptr[logical]
			return 0
		}
		logical -= u64(12)
		per := fs.block_size / u32(4)
		if logical >= u64(per) {
			return -27
		}
		if !in_.ptr[12] {
			if !allocate {
				*out = u32(0)
				return 0
			}
			rc := e2_block_allocate(fs, &in_.ptr[0] + 12)
			if rc {
				return rc
			}
			in_.sectors += fs.block_size / u32(512)
		}
		raw := [4]u8{}
		off := u64(in_.ptr[12]) * u64(fs.block_size) + logical * u64(4)
		rc := e2_disk(fs, voidptr(&raw[0]), off, usize(4))
		if rc {
			return rc
		}
		block := e2_u32(&raw[0])
		if block && !e2_block_valid(fs, block) {
			return -22
		}
		if !block && allocate {
			rc = e2_block_allocate(fs, &block)
			if rc {
				return rc
			}
			e2_p32(&raw[0], block)
			rc = e2_store(fs, voidptr(&raw[0]), off, usize(4))
			if rc {
				return rc
			}
			in_.sectors += fs.block_size / u32(512)
		}
		*out = block
		return 0
	}
}

@[export: 'e2_zero_tail']
pub fn e2_zero_tail(fs &E2_fs, in_ &E2_inode, size u64) i32 {
	unsafe {
		if !size || !(size % u64(fs.block_size)) {
			return 0
		}
		block := u32(0)
		rc := e2_map(fs, in_, size / u64(fs.block_size), &block)
		if rc || !block {
			return rc
		}
		zero := [256]u8{}
		e2_zero(voidptr(&zero[0]), sizeof([256]u8))
		pos := u32((size % u64(fs.block_size)))
		for pos < fs.block_size {
			n := usize(fs.block_size - pos)
			if n > sizeof([256]u8) {
				n = sizeof([256]u8)
			}
			rc = e2_store(fs, voidptr(&zero[0]), u64(block) * u64(fs.block_size) + u64(pos), n)
			if rc {
				return rc
			}
			pos += u32(n)
		}
		return 0
	}
}

@[export: 'e2_zero_range']
pub fn e2_zero_range(fs &E2_fs, in_ &E2_inode, start u64, end u64) i32 {
	unsafe {
		zero := [4096]u8{}
		e2_zero(voidptr(&zero[0]), usize(fs.block_size))
		for start < end {
			within := u32((start % u64(fs.block_size)))
			block := u32(0)

			n := usize(fs.block_size - within)
			if u64(n) > end - start {
				n = usize((end - start))
			}
			rc := e2_map(fs, in_, start / u64(fs.block_size), &block)
			if rc {
				return rc
			}
			if block {
				rc = e2_store(fs, voidptr(&zero[0]), u64(block) * u64(fs.block_size) + u64(within), n)
				if rc {
					return rc
				}
			}
			start += u64(n)
		}
		return 0
	}
}

@[export: 'vinix_ext2_truncate']
pub fn vinix_ext2_truncate(context voidptr, ino u32, size u64) i32 {
	unsafe {
		fs := &E2_fs(context)
		in_ := E2_inode{}
		if (usize(fs) == 0) || !fs.active {
			return -30
		}
		if size > e2_write_limit(fs) {
			return -27
		}
		rc := e2_inode_get(fs, ino, &in_)
		if rc {
			return rc
		}
		if (in_.mode & 61440) != 32768 || (in_.flags & (16 | 32)) {
			return -95
		}
		if in_.size > e2_write_limit(fs) {
			return -27
		}
		if size < in_.size {
			rc = e2_zero_tail(fs, &in_, size)
			if rc {
				return rc
			}
			first_free := (size + u64(fs.block_size) - u64(1)) / u64(fs.block_size)
			old_blocks := (in_.size + u64(fs.block_size) - u64(1)) / u64(fs.block_size)
			per := fs.block_size / u32(4)
			for logical := first_free; logical < old_blocks; logical++ {
				block := u32(0)
				rc = e2_map_write(fs, &in_, logical, 0, &block)
				if rc {
					return rc
				}
				if !block {
					continue
				}
				rc = e2_block_free(fs, block)
				if rc {
					return rc
				}
				if in_.sectors < fs.block_size / u32(512) {
					return -22
				}
				in_.sectors -= fs.block_size / u32(512)
				if logical < u64(12) {
					in_.ptr[logical] = u32(0)
				} else {
					zero := [4]u8{}
					rc = e2_store(fs, voidptr(&zero[0]), u64(in_.ptr[12]) * u64(fs.block_size) + (logical - u64(12)) * u64(4), usize(4))
					if rc {
						return rc
					}
				}
			}
			if in_.ptr[12] {
				pointers := [4096]u8{}
				rc = e2_disk(fs, voidptr(&pointers[0]), u64(in_.ptr[12]) * u64(fs.block_size), usize(fs.block_size))
				if rc {
					return rc
				}
				used := u32(0)
				for i := u32(0); i < per; i++ {
					used |= e2_u32(&pointers[0] + (i * u32(4)))
				}
				if !used {
					rc = e2_block_free(fs, in_.ptr[12])
					if rc {
						return rc
					}
					in_.ptr[12] = u32(0)
					if in_.sectors < fs.block_size / u32(512) {
						return -22
					}
					in_.sectors -= fs.block_size / u32(512)
				}
			}
		}
		in_.size = size
		return e2_inode_put(fs, ino, &in_)
	}
}

@[export: 'vinix_ext2_write']
pub fn vinix_ext2_write(context voidptr, ino u32, buffer voidptr, offset u64, count usize) i64 {
	unsafe {
		fs := &E2_fs(context)
		in_ := E2_inode{}
		if (usize(fs) == 0) || !fs.active || ((usize(buffer) == 0) && count) {
			return i64((-30))
		}
		if offset > e2_write_limit(fs) || u64(count) > e2_write_limit(fs) - offset {
			return i64((-27))
		}
		rc := e2_inode_get(fs, ino, &in_)
		if rc {
			return i64(rc)
		}
		if (in_.mode & 61440) != 32768 {
			return i64((-21))
		}
		if in_.flags & (16 | 32) {
			return i64((-95))
		}
		if offset > in_.size {
			rc = e2_zero_range(fs, &in_, in_.size, offset)
			if rc {
				return i64(rc)
			}
		}
		p := &u8(buffer)
		done := usize(0)
		for done < count {
			pos := offset + u64(done)
			within := u32((pos % u64(fs.block_size)))
			block := u32(0)

			n := usize(fs.block_size - within)
			if n > count - done {
				n = count - done
			}
			rc = e2_map_write(fs, &in_, pos / u64(fs.block_size), 1, &block)
			if rc {
				return i64(rc)
			}
			rc = e2_store(fs, voidptr(p + done), u64(block) * u64(fs.block_size) + u64(within), n)
			if rc {
				return i64(rc)
			}
			done += n
		}
		if offset + u64(done) > in_.size {
			in_.size = offset + u64(done)
		}
		rc = e2_inode_put(fs, ino, &in_)
		return if rc { i64(rc) } else { i64(done) }
	}
}

@[export: 'e2_name_valid']
pub fn e2_name_valid(name &char, n usize) i32 {
	unsafe {
		if (usize(name) == 0) || !n {
			return -22
		}
		if n > usize(255) {
			return -36
		}
		if (n == usize(1) && i32(name[0]) == i8(`.`)) || (n == usize(2) && i32(name[0]) == i8(`.`) && i32(name[1]) == i8(`.`)) {
			return -22
		}
		for i := usize(0); i < n; i++ {
			if !name[i] || i32(name[i]) == i8(`/`) {
				return -22
			}
		}
		return 0
	}
}

@[export: 'e2_name_equal']
pub fn e2_name_equal(a &char, an usize, b &char, bn usize) i32 {
	unsafe {
		if an != bn {
			return 0
		}
		for i := usize(0); i < an; i++ {
			if i32(a[i]) != i32(b[i]) {
				return 0
			}
		}
		return 1
	}
}

@[export: 'e2_lookup']
pub fn e2_lookup(fs &E2_fs, dir u32, name &char, n usize, ino &u32, type_ &u8) i32 {
	unsafe {
		pos := u64(0)
		found := [256]char{}
		child := u32(0)
		for {
			rc := vinix_ext2_next(voidptr(fs), dir, &pos, &child, &char(&found[0]), sizeof([256]char))
			if rc <= 0 {
				return if rc { rc } else { -2 }
			}
			length := usize(0)
			for length < sizeof([256]char) && i32(found[length]) {
				length++
			}
			if e2_name_equal(&char(&found[0]), length, name, n) {
				if ino {
					*ino = child
				}
				if type_ {
					in_ := E2_inode{}
					rc = e2_inode_get(fs, child, &in_)
					if rc {
						return rc
					}
					kind := in_.mode & 61440
					*type_ = u8(if kind == 16384 {
						2
					} else {
						if kind == 40960 { 7 } else { 1 }
					})
				}
				return 0
			}
		}
		return -22
	}
}

@[export: 'e2_dir_add']
pub fn e2_dir_add(fs &E2_fs, dir u32, name &char, n usize, child u32, type_ u8) i32 {
	unsafe {
		rc := e2_name_valid(name, n)
		if rc {
			return rc
		}
		ignored := u32(0)
		rc = e2_lookup(fs, dir, name, n, &ignored, (voidptr(0)))
		if !rc {
			return -17
		}
		if rc != -2 {
			return rc
		}
		in_ := E2_inode{}
		rc = e2_inode_get(fs, dir, &in_)
		if rc {
			return rc
		}
		if (in_.mode & 61440) != 16384 || (in_.flags & 4096) {
			return -20
		}
		needed := u16(((usize(8) + n + usize(3)) & usize(~3)))
		block_data := [4096]u8{}
		blocks := in_.size / u64(fs.block_size)
		for logical := u64(0); logical < blocks; logical++ {
			block := u32(0)
			rc = e2_map(fs, &in_, logical, &block)
			if rc || !block {
				return if rc { rc } else { (-22) }
			}
			rc = e2_disk(fs, voidptr(&block_data[0]), u64(block) * u64(fs.block_size), usize(fs.block_size))
			if rc {
				return rc
			}
			for pos := u32(0); pos < fs.block_size; {
				rec := e2_u16(&block_data[0] + pos + 4)
				len := block_data[pos + u32(6)]
				if i32(rec) < 8 || (i32(rec) & 3) || u32(rec) > fs.block_size - pos || i32(len) > i32(rec) - 8 {
					return -22
				}
				actual := u16((u32((8 + i32(len) + 3)) & ~3))
				if i32(rec) >= i32(actual) + i32(needed) {
					e2_p16(&block_data[0] + pos + 4, actual)
					entry := &block_data[0] + pos + i32(actual)
					e2_zero(voidptr(entry), usize(i32(rec) - i32(actual)))
					e2_p32(entry, child)
					e2_p16(entry + 4, u16(i32(rec) - i32(actual)))
					entry[6] = u8(n)
					entry[7] = u8(if fs.filetype { i32(type_) } else { 0 })
					e2_copy(voidptr(entry + 8), voidptr(name), n)
					return e2_store(fs, voidptr(&block_data[0]), u64(block) * u64(fs.block_size), usize(fs.block_size))
				}
				pos += u32(rec)
			}
		}
		if in_.size > e2_write_limit(fs) - u64(fs.block_size) {
			return -27
		}
		block := u32(0)
		rc = e2_map_write(fs, &in_, blocks, 1, &block)
		if rc {
			return rc
		}
		e2_zero(voidptr(&block_data[0]), usize(fs.block_size))
		e2_p32(&block_data[0], child)
		e2_p16(&block_data[0] + 4, u16(fs.block_size))
		block_data[6] = u8(n)
		block_data[7] = u8(if fs.filetype { i32(type_) } else { 0 })
		e2_copy(voidptr(&block_data[0] + 8), voidptr(name), n)
		rc = e2_store(fs, voidptr(&block_data[0]), u64(block) * u64(fs.block_size), usize(fs.block_size))
		if rc {
			return rc
		}
		in_.size += u64(fs.block_size)
		return e2_inode_put(fs, dir, &in_)
	}
}

@[export: 'e2_dir_remove']
pub fn e2_dir_remove(fs &E2_fs, dir u32, name &char, n usize, removed &u32) i32 {
	unsafe {
		in_ := E2_inode{}
		rc := e2_inode_get(fs, dir, &in_)
		if rc {
			return rc
		}
		if (in_.mode & 61440) != 16384 {
			return -20
		}
		data := [4096]u8{}
		blocks := in_.size / u64(fs.block_size)
		for logical := u64(0); logical < blocks; logical++ {
			block := u32(0)
			rc = e2_map(fs, &in_, logical, &block)
			if rc || !block {
				return if rc { rc } else { (-22) }
			}
			rc = e2_disk(fs, voidptr(&data[0]), u64(block) * u64(fs.block_size), usize(fs.block_size))
			if rc {
				return rc
			}
			previous := u32(4294967295)
			for pos := u32(0); pos < fs.block_size; {
				child := e2_u32(&data[0] + pos)
				rec := e2_u16(&data[0] + pos + 4)
				len := data[pos + u32(6)]
				if i32(rec) < 8 || (i32(rec) & 3) || u32(rec) > fs.block_size - pos || i32(len) > i32(rec) - 8 {
					return -22
				}
				if child && e2_name_equal(&char(voidptr(&data[0])) + pos + 8, usize(len), name, n) {
					if previous != u32(4294967295) {
						e2_p16(&data[0] + previous + 4, u16((i32(e2_u16(&data[0] + previous + 4)) + i32(rec))))
					} else {
						e2_p32(&data[0] + pos, u32(0))
					}
					rc = e2_store(fs, voidptr(&data[0]), u64(block) * u64(fs.block_size), usize(fs.block_size))
					if !rc && !(usize(removed) == 0) {
						*removed = child
					}
					return rc
				}
				previous = pos
				pos += u32(rec)
			}
		}
		return -2
	}
}

@[export: 'e2_dir_empty']
pub fn e2_dir_empty(fs &E2_fs, ino u32) i32 {
	unsafe {
		pos := u64(0)
		child := u32(0)
		name := [256]char{}
		for {
			rc := vinix_ext2_next(voidptr(fs), ino, &pos, &child, &char(&name[0]), sizeof([256]char))
			if rc < 0 {
				return rc
			}
			if !rc {
				return 1
			}
			if !((i32(name[0]) == i8(`.`) && !name[1]) || (i32(name[0]) == i8(`.`) && i32(name[1]) == i8(`.`) && !name[2])) {
				return 0
			}
		}
		return -22
	}
}

@[export: 'e2_release_inode']
pub fn e2_release_inode(fs &E2_fs, ino u32, in_ &E2_inode) i32 {
	unsafe {
		kind := in_.mode & 61440
		rc := i32(0)
		if kind == 32768 || kind == 16384 || (kind == 40960 && !in_.fast_link) {
			// The public truncate operation is regular-file-only. Once the name
			//         *is gone, temporarily use that path to release a directory or a
			//         *block-backed symlink without teaching it special-file semantics.

			in_.mode = 32768 | u32(384)
			rc = e2_inode_put(fs, ino, in_)
			if rc {
				return rc
			}
			rc = vinix_ext2_truncate(voidptr(fs), ino, u64(0))
			if rc {
				return rc
			}
			rc = e2_inode_get(fs, ino, in_)
			if rc {
				return rc
			}
		}
		in_.mode = u32(0)
		in_.size = u64(0)
		in_.links = u32(0)
		in_.sectors = u32(0)
		for i := u32(0); i < u32(15); i++ {
			in_.ptr[i] = u32(0)
		}
		rc = e2_inode_put(fs, ino, in_)
		if rc {
			return rc
		}
		return e2_inode_free(fs, ino)
	}
}

@[export: 'vinix_ext2_create']
pub fn vinix_ext2_create(context voidptr, parent u32, name &char, name_length usize, mode u32, created &u32) i32 {
	unsafe {
		fs := &E2_fs(context)
		if (usize(fs) == 0) || !fs.active || (usize(created) == 0) {
			return -30
		}
		kind := mode & 61440
		if kind != 32768 && kind != 16384 {
			return -95
		}
		rc := e2_name_valid(name, name_length)
		if rc {
			return rc
		}
		exists := u32(0)
		rc = e2_lookup(fs, parent, name, name_length, &exists, (voidptr(0)))
		if !rc {
			return -17
		}
		if rc != -2 {
			return rc
		}
		ino := u32(0)
		rc = e2_inode_allocate(fs, &ino)
		if rc {
			return rc
		}
		in_ := E2_inode{}
		e2_zero(voidptr(&in_), sizeof(in_))
		in_.mode = mode
		in_.links = u32(if kind == 16384 { 2 } else { 1 })
		if kind == 16384 {
			block := u32(0)
			rc = e2_map_write(fs, &in_, u64(0), 1, &block)
			if rc {
				return rc
			}
			data := [4096]u8{}
			e2_zero(voidptr(&data[0]), usize(fs.block_size))
			e2_p32(&data[0], ino)
			e2_p16(&data[0] + 4, u16(12))
			data[6] = u8(1)
			data[7] = u8(if fs.filetype { 2 } else { 0 })
			data[8] = u8(`.`)
			e2_p32(&data[0] + 12, parent)
			e2_p16(&data[0] + 16, u16((fs.block_size - u32(12))))
			data[18] = u8(2)
			data[19] = u8(if fs.filetype { 2 } else { 0 })
			data[20] = u8(`.`)
			data[21] = u8(`.`)
			rc = e2_store(fs, voidptr(&data[0]), u64(block) * u64(fs.block_size), usize(fs.block_size))
			if rc {
				return rc
			}
			in_.size = u64(fs.block_size)
		}
		rc = e2_inode_put(fs, ino, &in_)
		if rc {
			return rc
		}
		rc = e2_dir_add(fs, parent, name, name_length, ino, u8(if kind == 16384 { 2 } else { 1 }))
		if rc {
			return rc
		}
		if kind == 16384 {
			p := E2_inode{}
			rc = e2_inode_get(fs, parent, &p)
			if rc {
				return rc
			}
			p.links++
			rc = e2_inode_put(fs, parent, &p)
			if rc {
				return rc
			}
			group := (ino - u32(1)) / fs.ipg
			desc := [32]u8{}
			rc = e2_desc_get(fs, group, &desc[0])
			if rc {
				return rc
			}
			dirs := e2_u16(&desc[0] + 16)
			if u32(dirs) == 65535 {
				return -22
			}
			e2_p16(&desc[0] + 16, u16((i32(dirs) + 1)))
			rc = e2_desc_put(fs, group, &desc[0])
			if rc {
				return rc
			}
		}
		*created = ino
		return 0
	}
}

@[export: 'vinix_ext2_symlink']
pub fn vinix_ext2_symlink(context voidptr, parent u32, name &char, name_length usize, target &char, target_length usize, created &u32) i32 {
	unsafe {
		fs := &E2_fs(context)
		if (usize(fs) == 0) || !fs.active || (usize(created) == 0) || (usize(target) == 0) || !target_length {
			return -30
		}
		if target_length > usize(60) {
			return -36
		}
		rc := e2_name_valid(name, name_length)
		if rc {
			return rc
		}
		exists := u32(0)
		rc = e2_lookup(fs, parent, name, name_length, &exists, (voidptr(0)))
		if !rc {
			return -17
		}
		if rc != -2 {
			return rc
		}
		ino := u32(0)
		rc = e2_inode_allocate(fs, &ino)
		if rc {
			return rc
		}
		in_ := E2_inode{}
		e2_zero(voidptr(&in_), sizeof(in_))
		in_.mode = 40960 | u32(511)
		in_.links = u32(1)
		in_.size = u64(target_length)
		e2_copy(in_.ptr, voidptr(target), target_length)
		rc = e2_inode_put(fs, ino, &in_)
		if rc {
			return rc
		}
		rc = e2_dir_add(fs, parent, name, name_length, ino, u8(7))
		if rc {
			return rc
		}
		*created = ino
		return 0
	}
}

@[export: 'vinix_ext2_link']
pub fn vinix_ext2_link(context voidptr, parent u32, name &char, name_length usize, ino u32) i32 {
	unsafe {
		fs := &E2_fs(context)
		in_ := E2_inode{}
		if (usize(fs) == 0) || !fs.active {
			return -30
		}
		rc := e2_inode_get(fs, ino, &in_)
		if rc {
			return rc
		}
		if (in_.mode & 61440) == 16384 || in_.links == 65535 {
			return -95
		}
		in_.links++
		rc = e2_inode_put(fs, ino, &in_)
		if rc {
			return rc
		}
		rc = e2_dir_add(fs, parent, name, name_length, ino, u8(if (in_.mode & 61440) == 40960 {
			7
		} else {
			1
		}))
		if rc {
			in_.links--
			e2_inode_put(fs, ino, &in_)
		}
		return rc
	}
}

@[export: 'vinix_ext2_drop_link']
pub fn vinix_ext2_drop_link(context voidptr, ino u32) i32 {
	unsafe {
		fs := &E2_fs(context)
		in_ := E2_inode{}
		if (usize(fs) == 0) || !fs.active {
			return -30
		}
		rc := e2_inode_get(fs, ino, &in_)
		if rc {
			return rc
		}
		if !in_.links {
			return -22
		}
		if in_.links > u32(1) {
			in_.links--
			return e2_inode_put(fs, ino, &in_)
		}
		return e2_release_inode(fs, ino, &in_)
	}
}

@[export: 'vinix_ext2_unlink']
pub fn vinix_ext2_unlink(context voidptr, parent u32, name &char, name_length usize, directory i32) i32 {
	unsafe {
		fs := &E2_fs(context)
		ino := u32(0)
		type_ := u8(0)
		if (usize(fs) == 0) || !fs.active {
			return -30
		}
		rc := e2_name_valid(name, name_length)
		if rc {
			return rc
		}
		rc = e2_lookup(fs, parent, name, name_length, &ino, &type_)
		if rc {
			return rc
		}
		if directory && i32(type_) != 2 {
			return -20
		}
		if !directory && i32(type_) == 2 {
			return -21
		}
		if directory {
			empty := e2_dir_empty(fs, ino)
			if empty <= 0 {
				return if empty < 0 { empty } else { (-39) }
			}
		}
		removed := u32(0)
		rc = e2_dir_remove(fs, parent, name, name_length, &removed)
		if rc {
			return rc
		}
		in_ := E2_inode{}
		rc = e2_inode_get(fs, removed, &in_)
		if rc {
			return rc
		}
		if directory {
			p := E2_inode{}
			rc = e2_inode_get(fs, parent, &p)
			if rc {
				return rc
			}
			if p.links {
				p.links--
			}
			rc = e2_inode_put(fs, parent, &p)
			if rc {
				return rc
			}
			group := (removed - u32(1)) / fs.ipg
			desc := [32]u8{}
			rc = e2_desc_get(fs, group, &desc[0])
			if rc {
				return rc
			}
			dirs := e2_u16(&desc[0] + 16)
			if !dirs {
				return -22
			}
			e2_p16(&desc[0] + 16, u16((i32(dirs) - 1)))
			rc = e2_desc_put(fs, group, &desc[0])
			if rc {
				return rc
			}
			return e2_release_inode(fs, removed, &in_)
		}
		return vinix_ext2_drop_link(voidptr(fs), removed)
	}
}

@[export: 'vinix_ext2_rename']
pub fn vinix_ext2_rename(context voidptr, old_parent u32, old_name &char, old_length usize, new_parent u32, new_name &char, new_length usize, replace i32) i32 {
	unsafe {
		fs := &E2_fs(context)
		source := u32(0)
		destination := u32(0)

		type_ := u8(0)
		if (usize(fs) == 0) || !fs.active {
			return -30
		}
		rc := e2_name_valid(old_name, old_length)
		if rc {
			return rc
		}
		rc = e2_name_valid(new_name, new_length)
		if rc {
			return rc
		}
		rc = e2_lookup(fs, old_parent, old_name, old_length, &source, &type_)
		if rc {
			return rc
		}
		if old_parent == new_parent && e2_name_equal(old_name, old_length, new_name, new_length) {
			return 0
		}
		if i32(type_) == 2 && old_parent != new_parent {
			return -95
		}
		rc = e2_lookup(fs, new_parent, new_name, new_length, &destination, (voidptr(0)))
		if !rc {
			// POSIX requires rename(a, b) to do nothing when both names are hard
			//         *links to the same inode. In particular, neither name is removed.

			if destination == source {
				return 0
			}
			if !replace {
				return -17
			}
			target := E2_inode{}
			rc = e2_inode_get(fs, destination, &target)
			if rc {
				return rc
			}
			if (target.mode & 61440) == 16384 {
				return -95
			}
			rc = e2_dir_remove(fs, new_parent, new_name, new_length, (voidptr(0)))
			if rc {
				return rc
			}
			rc = vinix_ext2_drop_link(voidptr(fs), destination)
			if rc {
				return rc
			}
		} else if rc != -2 {
			return rc
		}
		rc = e2_dir_add(fs, new_parent, new_name, new_length, source, type_)
		if rc {
			return rc
		}
		rc = e2_dir_remove(fs, old_parent, old_name, old_length, (voidptr(0)))
		if rc {
			return rc
		}
		return 0
	}
}
