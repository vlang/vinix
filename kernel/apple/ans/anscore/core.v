@[translated]
module anscore

#include "apple_ans.h"
#include "apple_platform_io.h"
#include "apple_ans_ext2.h"

// SPDX-License-Identifier: GPL-2.0-or-later

// No format, discard or admin-passthrough API. Writes require a boot-selected
// *Linux-data GPT partition; whole namespaces remain read-only. V owns discovery, lifetime and serialization. DMA memory stays pinned
// *until reboot, including on failed initialization or a command timeout.

// Exact byte read; supports unaligned/partial-sector reads using a private
// *DMA bounce buffer. The caller validates/clamps EOF before invoking this.

// Length-bounded, whitespace-tokenized boot opt-in (not a substring match).

// SPDX-License-Identifier: GPL-2.0-or-later

// Byte-oriented ext2 access. Callbacks transfer exactly count bytes relative
// *to the selected partition or return nonzero. Writable mounts deliberately
// *support only classic, non-journaled ext2; the filesystem is marked dirty
// *before publication and clean only during an orderly shutdown.

pub type Vinix_ext2_reader = fn (voidptr, voidptr, u64, usize) i32
pub type Vinix_ext2_writer = fn (voidptr, voidptr, u64, usize) i32

fn C.vinix_ext2_context_size() usize

fn C.vinix_ext2_open(context voidptr, context_size usize, arg Vinix_ext2_reader, cookie voidptr, partition_bytes u64) i32

fn C.vinix_ext2_open_rw(context voidptr, context_size usize, arg Vinix_ext2_reader, arg_2 Vinix_ext2_writer, cookie voidptr, partition_bytes u64) i32

fn C.vinix_ext2_begin_write(context voidptr) i32

fn C.vinix_ext2_close_clean(context voidptr) i32

// Native-endian u64 fields: size, mode, uid, gid, nlink, blocks(512-byte),
// *atime, mtime, ctime, filesystem block size.

fn C.vinix_ext2_stat(context voidptr, inode u32, fields &u64) i32

fn C.vinix_ext2_read(context voidptr, inode u32, buffer voidptr, offset u64, capacity usize) i64

fn C.vinix_ext2_write(context voidptr, inode u32, buffer voidptr, offset u64, count usize) i64

fn C.vinix_ext2_truncate(context voidptr, inode u32, size u64) i32

// Returns 1 for an entry, 0 for EOF, negative errno on failure. Offset is a
// *directory byte cursor. Name capacity must be at least 256.

fn C.vinix_ext2_next(context voidptr, directory u32, offset &u64, inode &u32, name &char, capacity usize) i32

fn C.vinix_ext2_create(context voidptr, parent u32, name &char, name_length usize, mode u32, inode &u32) i32

fn C.vinix_ext2_symlink(context voidptr, parent u32, name &char, name_length usize, target &char, target_length usize, inode &u32) i32

fn C.vinix_ext2_link(context voidptr, parent u32, name &char, name_length usize, inode u32) i32

fn C.vinix_ext2_unlink(context voidptr, parent u32, name &char, name_length usize, directory i32) i32

fn C.vinix_ext2_drop_link(context voidptr, inode u32) i32

fn C.vinix_ext2_rename(context voidptr, old_parent u32, old_name &char, old_length usize, new_parent u32, new_name &char, new_length usize, replace i32) i32

// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.
// SPDX-License-Identifier: GPL-2.0-or-later
// * *Base-M1 ANS2: bounded, polled NVMe transport with partition-scoped writes.
// *Register/protocol references: Linux drivers/nvme/host/apple.c (Asahi Linux
// *Contributors), U-Boot drivers/nvme/nvme_apple.c (Mark Kettenis), and their
// *RTKit/SART drivers. See docs/apple-ans.md for pinned reference blobs.
// * *Hardware access is injected so host tests run the actual production code.
// *Only the V layer binds hardware; this file never guesses a physical address.
//

fn C.vinix_account_disk_transfer(bytes u64, write i32)

// Internal errors are stable diagnostics, not userspace errno numbers.

// empty enum
pub const ans_ok = 0
pub const ans_config = 1
pub const ans_handoff = 2
pub const ans_timeout = 3
pub const ans_protocol = 4
pub const ans_firmware = 5
pub const ans_sart = 6
pub const ans_completion = 7
pub const ans_capability = 8
pub const ans_namespace = 9
pub const ans_gpt = 10
pub const ans_range = 11
pub const ans_read_only = 12
pub const ans_stopped = 13

pub struct Ans_ops {
pub mut:
	read32  fn (voidptr, u64) u32
	write32 fn (voidptr, u64, u32)
	read64  fn (voidptr, u64) u64
	write64 fn (voidptr, u64, u64)
	now     fn (voidptr) u64
	delay   fn (voidptr, u32)
	// for_cpu=0: clean/invalidate before DMA; 1: invalidate after DMA.
	//     *Both include a full completion barrier. All buffers are exclusive.
	sync fn (voidptr, voidptr, usize, i32)
}

pub struct Ans_partition {
pub mut:
	start      u64
	blocks     u64
	attributes u64
	number     u32
	guid       [16]u8
	type_guid  [16]u8
}

pub struct Ans_namespace {
pub mut:
	id           u32
	sector       u32
	blocks       u64
	nparts       u32
	gpt_complete u32
	gpt_hybrid   u32
	parts        [128]Ans_partition
}

pub struct Ans_queue {
pub mut:
	head  u32
	phase u32
}

pub struct Ans {
pub mut:
	ops               Ans_ops
	cookie            voidptr
	nvme              u64
	asc               u64
	mailbox           u64
	sart              u64
	reset             u64
	dma               &u8
	physical          u64
	queues            [2]Ans_queue
	ns                [8]Ans_namespace
	nns               u32
	max_transfer      u32
	shared_used       u32
	stage             u32
	last_status       u16
	sart_owned        u16
	shared_addr       [9]u64
	shared_request    [9]u64
	endpoints         [8]u32
	hello             u32
	mapped            u32
	ap_requested      u32
	iop_power         u32
	ap_power          u32
	error             i32
	dead              i32
	started           i32
	live              i32
	stopping          u32
	stopped           u32
	ioq_active        u32
	policy_set        u32
	write_enabled     u32
	write_fault       u32
	write_ns          u32
	write_part        u32
	root_selected     u32
	root_ns           u32
	root_part         u32
	write_start       u64
	write_blocks      u64
	writes_completed  u64
	flushes_completed u64
	dirty_namespaces  u16
	sart_pa           [16]u64
	sart_bytes        [16]u32
}

@[export: 'a_le16']
pub fn a_le16(p &u8) u16 {
	unsafe {
		return u16((i32(p[0]) | i32(u16(p[1])) << 8))
	}
}

@[export: 'a_le32']
pub fn a_le32(p &u8) u32 {
	unsafe {
		return u32(a_le16(p)) | u32(a_le16(p + 2)) << 16
	}
}

@[export: 'a_le64']
pub fn a_le64(p &u8) u64 {
	unsafe {
		return u64(a_le32(p)) | u64(a_le32(p + 4)) << 32
	}
}

@[export: 'a_put16']
pub fn a_put16(p &u8, v u16) {
	unsafe {
		p[0] = u8(v)
		p[1] = u8((i32(v) >> 8))
	}
}

@[export: 'a_put32']
pub fn a_put32(p &u8, v u32) {
	unsafe {
		a_put16(p, u16(v))
		a_put16(p + 2, u16((v >> 16)))
	}
}

@[export: 'a_put64']
pub fn a_put64(p &u8, v u64) {
	unsafe {
		a_put32(p, u32(v))
		a_put32(p + 4, u32((v >> 32)))
	}
}

@[export: 'a_zero']
pub fn a_zero(p voidptr, n usize) {
	unsafe {
		b := &u8(p)
		for i := usize(0); i < n; i++ { b[i] = 0 }
	}
}

@[export: 'a_copy']
pub fn a_copy(d voidptr, s voidptr, n usize) {
	unsafe {
		a := &u8(d)
		b := &u8(s)
		for i := usize(0); i < n; i++ { a[i] = b[i] }
	}
}

@[export: 'a_equal']
pub fn a_equal(a &u8, b &u8, n usize) i32 {
	unsafe {
		for i := usize(0); i < n; i++ { if a[i] != b[i] { return 0 } }
		return 1
	}
}

@[export: 'a_fail']
pub fn a_fail(a &Ans, error_ i32) i32 {
	unsafe {
		if !a.dead {
			a.error = error_
		}
		a.dead = 1
		a.live = 0
		return -error_
	}
}

@[export: 'a_r32']
pub fn a_r32(a &Ans, base u64, off u32) u32 {
	unsafe {
		return a.ops.read32(voidptr(a.cookie), base + u64(off))
	}
}

@[export: 'a_w32']
pub fn a_w32(a &Ans, base u64, off u32, v u32) {
	unsafe {
		a.ops.write32(voidptr(a.cookie), base + u64(off), v)
	}
}

@[export: 'a_sync']
pub fn a_sync(a &Ans, off u32, n usize, cpu i32) {
	unsafe {
		a.ops.sync(voidptr(a.cookie), voidptr(a.dma + off), n, cpu)
	}
}

// SPDX-License-Identifier: GPL-2.0-or-later
// *Private boot policy. Parse before MMIO; resolve PARTUUIDs after GPT validation.
//

pub struct Ans_policy {
pub mut:
	flags      u32
	write_guid [16]u8
	root_guid  [16]u8
}

@[export: 'a_hex']
pub fn a_hex(c u8) i32 {
	unsafe {
		if i32(c) >= `0` && i32(c) <= `9` {
			return i32(c) - i32(`0`)
		}
		if i32(c) >= `a` && i32(c) <= `f` {
			return i32(c) - i32(`a`) + 10
		}
		if i32(c) >= `A` && i32(c) <= `F` {
			return i32(c) - i32(`A`) + 10
		}
		return -1
	}
}

pub const a_guid_order = [u8(3), u8(2), u8(1), u8(0), u8(5), u8(4), u8(7), u8(6), u8(8), u8(9),
	u8(10), u8(11), u8(12), u8(13), u8(14), u8(15)]!

@[export: 'a_guid_parse']
pub fn a_guid_parse(s &char, n usize, guid &u8) i32 {
	unsafe {
		out := [16]u8{}
		nonzero := u32(0)
		byte_ := u32(0)

		if (usize(s) == 0) || n != usize(36) {
			return 0
		}
		for i := u32(0); i < u32(36); {
			if i == u32(8) || i == u32(13) || i == u32(18) || i == u32(23) {
				if i32(s[i++]) != i8(`-`) {
					return 0
				}
			} else {
				hi := a_hex(u8(s[i++]))
				lo := a_hex(u8(s[i++]))

				if hi < 0 || lo < 0 || byte_ == u32(16) {
					return 0
				}
				out[a_guid_order[byte_++]] = u8(((hi << 4) | lo))
				nonzero |= u32(((hi << 4) | lo))
			}
		}
		if !nonzero {
			return 0
		}
		a_copy(voidptr(guid), voidptr(&out[0]), usize(16))
		return 1
	}
}

@[export: 'a_guid_format']
pub fn a_guid_format(guid &u8, out &char) {
	unsafe {
		a_guid_format_hex := [i8(48), 49, 50, 51, 52, 53, 54, 55, 56, 57, 97, 98, 99, 100, 101,
			102, 0]!

		pos := u32(0)
		for i := u32(0); i < u32(16); i++ {
			if i == u32(4) || i == u32(6) || i == u32(8) || i == u32(10) {
				out[pos++] = i8(`-`)
			}
			out[pos++] = a_guid_format_hex[i32(guid[a_guid_order[i]]) >> 4]
			out[pos++] = a_guid_format_hex[i32(guid[a_guid_order[i]]) & 15]
		}
		out[pos] = i8(0)
	}
}

@[export: 'a_space']
pub fn a_space(c i8) i32 {
	unsafe {
		return i32(i32(c) == i8(` `) || i32(c) == i8(`\t`) || i32(c) == i8(`\r`) || i32(c) == i8(`\n`))
	}
}

@[export: 'a_token']
pub fn a_token(s &char, n usize, l &char, bytes usize) i32 {
	unsafe {
		return i32(n == bytes && a_equal(&u8(voidptr(s)), &u8(voidptr(l)), bytes))
	}
}

@[export: 'a_prefix']
pub fn a_prefix(s &char, n usize, p &char, bytes usize) i32 {
	unsafe {
		return i32(n >= bytes && a_equal(&u8(voidptr(s)), &u8(voidptr(p)), bytes))
	}
}

@[export: 'a_parse_policy']
pub fn a_parse_policy(s &char, n usize, out &Ans_policy) i32 {
	unsafe {
		p := Ans_policy{}

		disabled := u32(0)
		write := u32(0)
		root := u32(0)
		type_ := u32(0)
		mode := u32(0)

		a_parse_policy_wp := [i8(118), 105, 110, 105, 120, 46, 97, 110, 115, 95, 114, 119, 61,
			80, 65, 82, 84, 85, 85, 73, 68, 61, 0]!
		a_parse_policy_pp := [i8(118), 105, 110, 105, 120, 46, 112, 101, 114, 115, 105, 115, 116,
			61, 80, 65, 82, 84, 85, 85, 73, 68, 61, 0]!

		a_parse_policy_rp := [i8(118), 105, 110, 105, 120, 46, 114, 111, 111, 116, 61, 80, 65,
			82, 84, 85, 85, 73, 68, 61, 0]!

		if (usize(out) == 0) || ((usize(s) == 0) && n) || n > usize(16384) {
			return -ans_config
		}
		for i := usize(0); i < n; {
			for i < n && a_space(i8(s[i])) {
				i++
			}
			start := i
			for i < n && !a_space(i8(s[i])) {
				if !s[i] {
					return -ans_config
				}
				i++
			}
			t := s + start
			len := i - start
			if !len {
				continue
			}
			if a_token(t, len, &char(&c'vinix.apple_ans=1'[0]), sizeof([18]i8) - u64(1)) {
				p.flags |= 1
			} else if a_token(t, len, &char(&c'vinix.apple_ans=0'[0]), sizeof([18]i8) - u64(1)) {
				disabled = u32(1)
			} else if a_prefix(t, len, &char(&c'vinix.ans_rw='[0]), sizeof([14]i8) - u64(1)) {
				if write++ || !a_prefix(t, len, &char(&a_parse_policy_wp[0]), sizeof([23]i8) - u64(1)) || !a_guid_parse(t + sizeof([23]i8) - 1, len - (sizeof([23]i8) - u64(1)), &p.write_guid[0]) {
					return -ans_config
				}
				p.flags |= 2
			} else if a_prefix(t, len, &char(&c'vinix.persist='[0]), sizeof([15]i8) - u64(1)) {
				if write++ || !a_prefix(t, len, &char(&a_parse_policy_pp[0]), sizeof([24]i8) - u64(1)) || !a_guid_parse(t + sizeof([24]i8) - 1, len - (sizeof([24]i8) - u64(1)), &p.write_guid[0]) {
					return -ans_config
				}
				p.flags |= 2 | 16
			} else if a_prefix(t, len, &char(&c'vinix.root='[0]), sizeof([12]i8) - u64(1)) {
				if root++ || !a_prefix(t, len, &char(&a_parse_policy_rp[0]), sizeof([21]i8) - u64(1)) || !a_guid_parse(t + sizeof([21]i8) - 1, len - (sizeof([21]i8) - u64(1)), &p.root_guid[0]) {
					return -ans_config
				}
				p.flags |= 4
			} else if a_prefix(t, len, &char(&c'vinix.rootfstype='[0]), sizeof([18]i8) - u64(1)) {
				if type_++ || !a_token(t, len, &char(&c'vinix.rootfstype=ext2'[0]), sizeof([22]i8) - u64(1)) {
					return -ans_config
				}
			} else if a_prefix(t, len, &char(&c'vinix.rootmode='[0]), sizeof([16]i8) - u64(1)) {
				// Reject, don't silently downgrade, a requested writable root.

				if mode++ || !a_token(t, len, &char(&c'vinix.rootmode=ro'[0]), sizeof([18]i8) - u64(1)) {
					return -ans_config
				}
			} else if a_token(t, len, &char(&c'vinix.rootfallback=initramfs'[0]), sizeof([29]i8) - u64(1)) {
				if p.flags & 8 {
					return -ans_config
				}
				p.flags |= 8
			} else if a_prefix(t, len, &char(&c'vinix.apple_ans='[0]), sizeof([17]i8) - u64(1)) || a_prefix(t, len, &char(&c'vinix.rootfallback='[0]), sizeof([20]i8) - u64(1)) || a_prefix(t, len, &char(&c'vinix.persist='[0]), sizeof([15]i8) - u64(1)) {
				return -ans_config
			}
		}
		if disabled {
			p.flags &= ~1
		}
		if (p.flags & (4 | 2)) && !(p.flags & 1) {
			return -ans_config
		}
		if (type_ || mode || (p.flags & 8)) && !(p.flags & 4) {
			return -ans_config
		}
		if (p.flags & (4 | 2)) == (4 | 2) && a_equal(&p.root_guid[0], &p.write_guid[0], usize(16)) {
			return -ans_config
		}
		*out = p
		return 0
	}
}

@[export: 'a_linux_partition']
pub fn a_linux_partition(p &Ans_partition) i32 {
	unsafe {
		a_linux_partition_type_ := [u8(175), u8(61), u8(198), u8(15), u8(131), u8(132), u8(114),
			u8(71), u8(142), u8(121), u8(61), u8(105), u8(216), u8(71), u8(125), u8(228)]!

		return a_equal(&p.type_guid[0], &a_linux_partition_type_[0], usize(16))
	}
}

@[export: 'a_find_guid']
pub fn a_find_guid(a &Ans, guid &u8, ns &u32, part &u32) i32 {
	unsafe {
		found := u32(0)
		for i := u32(0); i < a.nns; i++ {
			for j := u32(0); j < a.ns[i].nparts; j++ {
				if a_equal(&a.ns[i].parts[j].guid[0], guid, usize(16)) {
					*ns = i
					*part = j
					found++
				}
			}
		}
		return if found == u32(1) { 0 } else { -ans_config }
	}
}

@[export: 'a_apply_policy']
pub fn a_apply_policy(a &Ans, p &Ans_policy) i32 {
	unsafe {
		wn := u32(0)
		wp := u32(0)
		rn := u32(0)
		rp := u32(0)

		if !a.live || a.stopping || a.policy_set || !(p.flags & 1) {
			return -ans_config
		}
		if p.flags & 4 {
			if a_find_guid(a, &p.root_guid[0], &rn, &rp) || !a_linux_partition(&a.ns[rn].parts[0] + rp) {
				return -ans_config
			}
		}
		if p.flags & 2 {
			mut __c2v_condition_0 := false
			mut __c2v_condition_1 := false
			__c2v_condition_1 = a_find_guid(a, &p.write_guid[0], &wn, &wp)
			__c2v_condition_0 = __c2v_condition_1
			if !__c2v_condition_0 {
				mut __c2v_condition_2 := false
				__c2v_condition_2 = !a.ns[wn].gpt_complete
				__c2v_condition_0 = __c2v_condition_2
			}
			if !__c2v_condition_0 {
				mut __c2v_condition_3 := false
				__c2v_condition_3 = a.ns[wn].gpt_hybrid
				__c2v_condition_0 = __c2v_condition_3
			}
			if !__c2v_condition_0 {
				mut __c2v_condition_4 := false
				__c2v_condition_4 = !a_linux_partition(&a.ns[wn].parts[0] + wp)
				__c2v_condition_0 = __c2v_condition_4
			}
			if !__c2v_condition_0 {
				mut __c2v_condition_5 := false
				__c2v_condition_5 = (a.ns[wn].parts[wp].attributes & (u64(1) << 60))
				__c2v_condition_0 = __c2v_condition_5
			}
			if __c2v_condition_0 {
				return -ans_config
			}
			if (p.flags & 4) && wn == rn && wp == rp {
				return -ans_config
			}
		}
		a.policy_set = u32(1)
		a.root_selected = u32(!!(p.flags & 4))
		a.root_ns = rn
		a.root_part = rp
		a.write_enabled = u32(!!(p.flags & 2))
		a.write_ns = wn
		a.write_part = wp
		if a.write_enabled {
			a.write_start = a.ns[wn].parts[wp].start
			a.write_blocks = a.ns[wn].parts[wp].blocks
		}
		return 0
	}
}

pub struct A_deadline {
pub mut:
	start  u64
	last   u64
	stalls u32
}

@[export: 'a_begin']
pub fn a_begin(a &Ans) A_deadline {
	unsafe {
		now := a.ops.now(voidptr(a.cookie))
		return A_deadline{
			start:  now
			last:   now
			stalls: u32(0)
		}
	}
}

@[export: 'a_expired']
pub fn a_expired(a &Ans, d &A_deadline, us u64) i32 {
	unsafe {
		now := a.ops.now(voidptr(a.cookie))
		if now == d.last {
			d.stalls++
		} else {
			d.stalls = u32(0)
		}
		d.last = now
		return i32(now - d.start >= us || d.stalls >= u32(1024))
	}
}

// Allow only a driver's own, aligned shared-memory extent, and never change
// *a firmware/bootloader-owned SART entry. SART is NOT a DART page table.

@[export: 'a_sart_allow']
pub fn a_sart_allow(a &Ans, pa u64, bytes u32) i32 {
	unsafe {
		mut __c2v_condition_6 := false
		mut __c2v_condition_7 := false
		__c2v_condition_7 = !bytes
		__c2v_condition_6 = __c2v_condition_7
		if !__c2v_condition_6 {
			mut __c2v_condition_8 := false
			__c2v_condition_8 = (pa & u64((16384 - u32(1))))
			__c2v_condition_6 = __c2v_condition_8
		}
		if !__c2v_condition_6 {
			mut __c2v_condition_9 := false
			__c2v_condition_9 = (bytes & (16384 - u32(1)))
			__c2v_condition_6 = __c2v_condition_9
		}
		if !__c2v_condition_6 {
			mut __c2v_condition_10 := false
			__c2v_condition_10 = pa > ((u64(1) << 42) - u64(1))
			__c2v_condition_6 = __c2v_condition_10
		}
		if !__c2v_condition_6 {
			mut __c2v_condition_11 := false
			__c2v_condition_11 = u64(bytes - u32(1)) > ((u64(1) << 42) - u64(1)) - pa
			__c2v_condition_6 = __c2v_condition_11
		}
		if !__c2v_condition_6 {
			mut __c2v_condition_12 := false
			__c2v_condition_12 = pa < a.physical + u64(393216)
			__c2v_condition_6 = __c2v_condition_12
		}
		if !__c2v_condition_6 {
			mut __c2v_condition_13 := false
			__c2v_condition_13 = pa - (a.physical + u64(393216)) > u64(4194304)
			__c2v_condition_6 = __c2v_condition_13
		}
		if !__c2v_condition_6 {
			mut __c2v_condition_14 := false
			__c2v_condition_14 = u64(bytes) > u64(4194304) - (pa - (a.physical + u64(393216)))
			__c2v_condition_6 = __c2v_condition_14
		}
		if __c2v_condition_6 {
			return a_fail(a, i32(ans_sart))
		}
		for i := u32(0); i < u32(16); i++ {
			if (u32(a.sart_owned) & (1 << i)) || (a_r32(a, a.sart, i * u32(4)) >> 24) {
				continue
			}
			config := u32(4278190080) | (bytes >> 12)
			a_w32(a, a.sart, u32(64) + i * u32(4), u32((pa >> 12)))
			a_w32(a, a.sart, i * u32(4), config)
			a.sart_owned |= i32(u16((1 << i)))
			a.sart_pa[i] = pa
			a.sart_bytes[i] = bytes
			if a_r32(a, a.sart, i * u32(4)) != config || a_r32(a, a.sart, u32(64) + i * u32(4)) != u32((pa >> 12)) {
				return a_fail(a, i32(ans_sart))
			}
			return 0
		}
		return a_fail(a, i32(ans_sart))
	}
}

@[export: 'a_send']
pub fn a_send(a &Ans, ep u32, msg u64) i32 {
	unsafe {
		deadline := a_begin(a)
		for i := u32(0); i < u32(4000); i++ {
			if !(a_r32(a, a.mailbox, 272) & (1 << 16)) {
				a.ops.write64(voidptr(a.cookie), a.mailbox + u64(2048), msg)
				a.ops.write64(voidptr(a.cookie), a.mailbox + u64(2056), u64(ep))
				return 0
			}
			if a_expired(a, &deadline, u64(20000)) {
				break
			}
			a.ops.delay(voidptr(a.cookie), u32(10))
		}
		return a_fail(a, i32(ans_timeout))
	}
}

@[export: 'a_buffer_request']
pub fn a_buffer_request(a &Ans, ep u32, msg u64) i32 {
	unsafe {
		size := u64(0)
		address := u64(0)

		if ep == u32(8) {
			size = (msg >> 36) & u64(1048575)
			address = (msg & ((u64(1) << 36) - u64(1))) << 12
		} else {
			size = ((msg >> 44) & u64(255)) << 12
			// Reject unsupported/reserved address bits too; do not truncate.

			address = msg & ((u64(1) << 44) - u64(1))
		}
		if !size || address || size > u64(1048576) || a.shared_addr[ep] {
			return a_fail(a, if ep == u32(1) && a.shared_addr[ep] {
				ans_firmware
			} else {
				ans_protocol
			})
		}
		rounded := (u32(size) + 16384 - u32(1)) & ~(16384 - u32(1))
		if rounded > 4194304 - a.shared_used {
			return a_fail(a, i32(ans_sart))
		}
		off := 393216 + a.shared_used
		pa := a.physical + u64(off)
		a_zero(voidptr(a.dma + off), usize(rounded))
		a_sync(a, off, usize(rounded), 0)
		if a_sart_allow(a, pa, rounded) {
			return -a.error
		}
		a.shared_used += rounded
		a.shared_addr[ep] = pa
		a.shared_request[ep] = msg
		reply := if ep == u32(8) {
			(u64(1) << 56) | (size << 36) | (pa >> 12)
		} else {
			(u64(1) << 52) | ((size >> 12) << 44) | pa
		}
		return a_send(a, ep, reply)
	}
}

// One nonblocking message receive, with bounded replies. Returns 1 if a
// *message was serviced, 0 if empty, negative on an unrecoverable error.

@[export: 'a_pump']
pub fn a_pump(a &Ans) i32 {
	unsafe {
		if a.dead {
			return -a.error
		}
		if a_r32(a, a.mailbox, 276) & (1 << 17) {
			return 0
		}
		msg := a.ops.read64(voidptr(a.cookie), a.mailbox + u64(2096))
		flags := a.ops.read64(voidptr(a.cookie), a.mailbox + u64(2104))
		ep := u32(flags & u64(255))
		type_ := u32((msg >> 52)) & 255

		rc := i32(0)
		if ep == u32(0) {
			match type_ {
				u32(1) {
					// case comp stmt
					min := u32(msg & u64(65535))
					max := u32((msg >> 16) & u64(65535))

					if a.hello || min > max || min > u32(12) || max < u32(11) {
						return a_fail(a, i32(ans_protocol))
					}
					version := if max > u32(12) { u32(12) } else { max }
					a.hello = u32(1)
					rc = a_send(a, u32(0), (u64(2) << 52) | u64(version) | u64(version) << 16)
				}
				u32(8) {
					// case comp stmt
					if !a.hello || a.mapped {
						return a_fail(a, i32(ans_protocol))
					}
					group := u32((msg >> 32)) & 7
					if (msg >> 35) & u64(65535) {
						return a_fail(a, i32(ans_protocol))
					}
					a.endpoints[group] |= u32(msg)
					last := i32(!!(msg & (u64(1) << 51)))
					rc = a_send(a, u32(0), (u64(8) << 52) | u64(group) << 32 | (if last {
						u64(1) << 51
					} else {
						u64(1)
					}))
					if rc {
						goto c2v_switch_end_0
					}
					if last {
						a_pump_supported := [u32(1), u32(2), u32(4), u32(8)]!

						for i := u32(0); u64(i) < 4; i++ {
							id := a_pump_supported[i]
							if a.endpoints[0] & (1 << id) {
								rc = a_send(a, u32(0), (u64(5) << 52) | u64(id) << 32 | u64(2))
								if rc {
									return rc
								}
							}
						}
						a.mapped = u32(1)
						rc = a_send(a, u32(0), (u64(11) << 52) | u64(32))
						a.ap_requested = u32(!rc)
					}
				}
				u32(7) { // case comp body kind=BinaryOperator is_enum=false
					a.iop_power = u32(msg & u64(65535))
				}
				u32(11) { // case comp body kind=BinaryOperator is_enum=false
					a.ap_power = u32(msg & u64(65535))

					// Unknown management messages are not DMA requests.
				}
				else {
					goto c2v_switch_end_0
				}
			}
			c2v_switch_end_0:
		} else if ep == u32(1) || ep == u32(2) || ep == u32(4) || ep == u32(8) {
			if !a.mapped || !(a.endpoints[0] & (1 << ep)) {
				return a_fail(a, i32(ans_protocol))
			}
			kind := if ep == u32(8) { u32((msg >> 56)) } else { type_ }
			if kind == u32(1) {
				rc = a_buffer_request(a, ep, msg)
			} else if ep == u32(1) {
				return a_fail(a, i32(ans_firmware))
			} else if (ep == u32(2) && kind == u32(5)) || (ep == u32(4) && (kind == u32(8) || kind == u32(12))) {
				rc = a_send(a, ep, msg)
			}
			// SYSLOG init/OSLOG notifications are intentionally discarded.
		}
		return if rc { rc } else { 1 }
	}
}

@[export: 'a_boot_rtkit']
pub fn a_boot_rtkit(a &Ans) i32 {
	unsafe {
		if a_send(a, u32(0), (u64(6) << 52) | u64(544)) {
			return -a.error
		}
		deadline := a_begin(a)
		for i := u32(0); i < u32(1000000); i++ {
			if a_pump(a) < 0 {
				return -a.error
			}
			if a.mapped && a.ap_requested && (a.ap_power & 255) == u32(32) && (a.iop_power & 255) == u32(32) {
				return 0
			}
			if a_expired(a, &deadline, u64(10000000)) {
				break
			}
			a.ops.delay(voidptr(a.cookie), u32(10))
		}
		return a_fail(a, i32(ans_timeout))
	}
}

@[export: 'a_wait32']
pub fn a_wait32(a &Ans, reg u32, mask u32, value u32, timeout u64) i32 {
	unsafe {
		deadline := a_begin(a)
		for i := u32(0); i < u32(4000000); i++ {
			if a_pump(a) < 0 {
				return -a.error
			}
			v := a_r32(a, a.nvme, reg)
			if reg == 28 && (v & 2) {
				return a_fail(a, i32(ans_firmware))
			}
			if (v & mask) == value {
				return 0
			}
			if a_expired(a, &deadline, timeout) {
				break
			}
			a.ops.delay(voidptr(a.cookie), u32(10))
		}
		return a_fail(a, i32(ans_timeout))
	}
}

// Whitelist at the lowest command submission layer, not merely at write().

@[export: 'a_command_allowed']
pub fn a_command_allowed(q u32, c &u8) i32 {
	unsafe {
		if q == u32(1) {
			return i32(i32(c[0]) <= 2)
		}
		// NVM Flush, Write, Read

		if q {
			return 0
		}
		match i32(c[0]) {
			0, 4, 1, 5 {
				return i32(i32(a_le16(c + 40)) == 1)
				// Create I/O SQ/CQ 1
			}
			6 { // case comp body kind=ReturnStmt is_enum=false
				return i32(a_le32(c + 40) <= u32(2))
				// Identify NS/ans_controller/active list
			}
			9 { // case comp body kind=ReturnStmt is_enum=false
				return i32(a_le32(c + 40) == u32(7) && a_le32(c + 44) == u32(0))
				// one queue
			}
			else {
				return 0
			}
		}
		return 0
	}
}

// Media authorization directly above the doorbell; never authorize a raw disk.

@[export: 'a_authorize']
pub fn a_authorize(a &Ans, q u32, c &u8) i32 {
	unsafe {
		if !a_command_allowed(q, c) {
			return 0
		}
		if !q {
			if i32(c[0]) == 0 || i32(c[0]) == 4 {
				return i32(a.stopping && a.ioq_active)
			}
			return i32(!a.stopping)
		}
		if i32(c[0]) == 2 {
			return i32(!a.stopping)
		}
		i := u32(0)
		for ; i < a.nns && a.ns[i].id != a_le32(c + 4); i++ {
		}
		if i == a.nns {
			return 0
		}
		if i32(c[0]) == 0 {
			for j := u32(8); j < u32(64); j++ {
				if c[j] {
					return 0
				}
			}
			return i32(i32(c[1]) == 0)
		}
		if !a.write_enabled || a.write_fault || a.stopping || i != a.write_ns || i32(c[1]) || a_le64(c + 16) || a_le64(c + 24) != a.physical + u64(131072) || u32(a_le16(c + 50)) != 16384 {
			return 0
		}
		for j := u32(8); j < u32(16); j++ {
			if c[j] {
				return 0
			}
		}
		for j := u32(52); j < u32(64); j++ {
			if c[j] {
				return 0
			}
		}
		lba := a_le64(c + 40)
		n := u64(a_le16(c + 48)) + u64(1)

		if lba < a.write_start || lba - a.write_start >= a.write_blocks || n > a.write_blocks - (lba - a.write_start) || n > u64(a.max_transfer / a.ns[i].sector) {
			return 0
		}
		bytes := u32(n) * a.ns[i].sector
		prp2 := if bytes <= 4096 {
			u64(0)
		} else {
			a.physical + u64((if bytes <= u32(2) * 4096 { 131072 + 4096 } else { 98304 }))
		}
		if a_le64(c + 32) != prp2 {
			return 0
		}
		if bytes > u32(2) * 4096 {
			for page := u32(1); page < (bytes + 4096 - u32(1)) / 4096; page++ {
				if a_le64(a.dma + 98304 + ((page - u32(1)) * u32(8))) != a.physical + u64(131072) + u64(page * 4096) {
					return 0
				}
			}
		}
		return 1
	}
}

@[export: 'a_submit']
pub fn a_submit(a &Ans, qid u32, c &u8, result &u32) i32 {
	unsafe {
		if a.dead {
			return -a.error
		}
		if a.stopped {
			return -ans_stopped
		}
		if !a_authorize(a, qid, c) {
			return -ans_read_only
		}
		// Fixed, disjoint tags: ANS shares one 0..63 tag space across both queues.
		//     *Single-flight serialization is held by V across the entire operation.

		cid := u32(if qid { 1 } else { 0 })
		sq := u32(if qid { 49152 } else { 0 })
		cq := u32(if qid { 65536 } else { 16384 })

		tcb := (if qid { 81920 } else { 32768 }) + cid * u32(128)
		// ANS2 linear slots are 64 bytes for BOTH queues, even with
		//     *CC.IOSQES=7. The 128-byte stride belongs to non-linear ANS queues.

		stride := u32(64)
		a_put16(c + 2, u16(cid))
		a_zero(voidptr(a.dma + sq + (cid * stride)), usize(stride))
		a_copy(voidptr(a.dma + sq + (cid * stride)), voidptr(c), usize(64))
		a_zero(voidptr(a.dma + tcb), usize(128))
		t := a.dma + tcb
		// Match the Linux ANS2 NVMMU contract: opcode is zero, and flags
		//     *describe the DMA direction (bit 0 from device, bit 1 to device).

		t[0] = u8(0)
		t[1] = u8(if !a_le64(c + 24) {
			0
		} else {
			if u32(c[0]) & 1 { 2 } else { 1 }
		})
		t[2] = u8(cid)
		a_put16(t + 4, a_le16(c + 48))
		a_put64(t + 24, a_le64(c + 24))
		a_put64(t + 32, a_le64(c + 32))
		a_sync(a, sq + cid * stride, usize(stride), 0)
		a_sync(a, tcb, usize(128), 0)
		a_w32(a, a.nvme, if qid { 149776 } else { 149772 }, cid)
		q := &a.queues[0] + qid
		off := cq + q.head * u32(16)
		deadline := a_begin(a)
		for i := u32(0); i < u32(500000); i++ {
			if a_pump(a) < 0 {
				return -a.error
			}
			csts := a_r32(a, a.nvme, 28)
			if (csts & 3) != 1 {
				return a_fail(a, i32(ans_firmware))
			}
			a_sync(a, off, usize(16), 1)
			e := a.dma + off
			status := a_le16(e + 14)
			if (u32(status) & 1) == q.phase {
				// Do not accept stale, wrong-queue or wrong-tag completions.

				if u32(a_le16(e + 12)) != cid || u32(a_le16(e + 10)) != qid || u32(a_le16(e + 8)) >= (if qid {
					64
				} else {
					u32(2)
				}) {
					return a_fail(a, i32(ans_protocol))
				}
				res := a_le32(e)
				a.last_status = u16((i32(status) >> 1))
				q.head++
				if q.head == (if qid { 64 } else { u32(2) }) {
					q.head = u32(0)
					q.phase ^= u32(1)
				}
				a_w32(a, a.nvme, if qid { 4108 } else { 4100 }, q.head)
				a_zero(voidptr(a.dma + tcb), usize(128))
				a_sync(a, tcb, usize(128), 0)
				a_w32(a, a.nvme, 164120, cid)
				if a_r32(a, a.nvme, 164128) {
					return a_fail(a, i32(ans_protocol))
				}
				if result {
					*result = res
				}
				// DNR/More are flags, not success codes. A nonzero SC/SCT fails.

				return if u32(a.last_status) & 2047 { -ans_completion } else { 0 }
			}
			if a_expired(a, &deadline, u64(5000000)) {
				break
			}
			a.ops.delay(voidptr(a.cookie), u32(10))
		}
		// Never recycle a tag or DMA storage following an uncompleted command.

		return a_fail(a, i32(ans_timeout))
	}
}

@[export: 'a_data_prps']
pub fn a_data_prps(a &Ans, c &u8, bytes u32) {
	unsafe {
		a_put64(c + 24, a.physical + u64(131072))
		a_put64(c + 32, u64(0))
		if bytes <= 4096 {
			return
		}
		if bytes <= u32(2) * 4096 {
			a_put64(c + 32, a.physical + u64(131072) + u64(4096))
			return
		}
		a_zero(voidptr(a.dma + 98304), usize(4096))
		for page := u32(1); page < (bytes + 4096 - u32(1)) / 4096; page++ {
			a_put64(a.dma + 98304 + ((page - u32(1)) * u32(8)), a.physical + u64(131072) + u64(page * 4096))
		}
		a_sync(a, 98304, usize(4096), 0)
		a_put64(c + 32, a.physical + u64(98304))
	}
}

@[export: 'a_identify']
pub fn a_identify(a &Ans, id u32, cns u32) i32 {
	unsafe {
		c := [64]u8{}
		c[0] = u8(6)
		a_put32(&c[0] + 4, id)
		a_put32(&c[0] + 40, cns)
		a_data_prps(a, &c[0], 4096)
		a_zero(voidptr(a.dma + 131072), usize(4096))
		a_sync(a, 131072, usize(4096), 0)
		rc := a_submit(a, u32(0), &c[0], (voidptr(0)))
		if !rc {
			a_sync(a, 131072, usize(4096), 1)
		}
		return rc
	}
}

@[export: 'a_parse_namespace']
pub fn a_parse_namespace(ns &Ans_namespace, id u32, p &u8) i32 {
	unsafe {
		blocks := a_le64(p)
		capacity := a_le64(p + 8)

		format := u32(p[26]) & 15
		if !id || id == u32(4294967295) || !blocks || !capacity || capacity > blocks || (u32(p[26]) & 240) || (u32(p[29]) & 7) || format > u32(p[25]) || i32(p[25]) >= 16 {
			return -ans_namespace
		}
		lbaf := p + 128 + (format * u32(4))
		shift := u32(lbaf[2])
		if i32(a_le16(lbaf)) || (shift != u32(9) && shift != u32(12)) || blocks > u64(9223372036854775807) >> shift {
			return -ans_namespace
		}
		a_zero(voidptr(ns), sizeof(Ans_namespace))
		ns.id = id
		ns.sector = 1 << shift
		ns.blocks = blocks
		return 0
	}
}

@[export: 'a_read_bytes']
pub fn a_read_bytes(a &Ans, index u32, buffer voidptr, offset u64, count usize) i32 {
	unsafe {
		if a.dead {
			return -a.error
		}
		if a.stopping || a.stopped {
			return -ans_stopped
		}
		if index >= a.nns || ((usize(buffer) == 0) && count) {
			return -ans_range
		}
		ns := &a.ns[0] + index
		size := ns.blocks * u64(ns.sector)
		if offset > size || u64(count) > size - offset {
			return -ans_range
		}
		out := &u8(buffer)
		for count {
			within := u32((offset % u64(ns.sector)))
			n := usize(a.max_transfer - within)
			if n > count {
				n = count
			}
			sectors := u32(((usize(within) + n + usize(ns.sector) - usize(1)) / usize(ns.sector)))
			bytes := sectors * ns.sector
			c := [64]u8{}
			c[0] = u8(2)
			a_put32(&c[0] + 4, ns.id)
			a_put64(&c[0] + 40, offset / u64(ns.sector))
			a_put16(&c[0] + 48, u16((sectors - u32(1))))
			a_data_prps(a, &c[0], bytes)
			a_sync(a, 131072, usize(bytes), 0)
			rc := a_submit(a, u32(1), &c[0], (voidptr(0)))
			if rc {
				return rc
			}
			C.vinix_account_disk_transfer(u64(bytes), 0)
			a_sync(a, 131072, usize(bytes), 1)
			a_copy(voidptr(out), voidptr(a.dma + 131072 + within), n)
			offset += u64(n)
			out += n
			count -= n
		}
		return 0
	}
}

// SPDX-License-Identifier: GPL-2.0-or-later
// *Single-flight partition writes, real Flush and ordered ans_controller shutdown.
//

@[export: 'a_flush_ns']
pub fn a_flush_ns(a &Ans, index u32) i32 {
	unsafe {
		if a.dead {
			return -a.error
		}
		if a.stopped || index >= a.nns {
			return -ans_stopped
		}
		c := [64]u8{}
		a_put32(&c[0] + 4, a.ns[index].id)
		rc := a_submit(a, u32(1), &c[0], (voidptr(0)))
		if rc {
			a.write_fault = u32(1)
			return a_fail(a, -rc)
		}
		a.dirty_namespaces &= i32(u16(~(1 << index)))
		a.flushes_completed++
		return 0
	}
}

@[export: 'a_flush_all']
pub fn a_flush_all(a &Ans) i32 {
	unsafe {
		if !a.started || a.stopped {
			return 0
		}
		if a.dead {
			return -a.error
		}
		if !a.ioq_active {
			return -ans_stopped
		}
		for i := u32(0); i < a.nns; i++ {
			rc := a_flush_ns(a, i)
			if rc {
				return rc
			}
		}
		return 0
	}
}

@[export: 'a_write_partition']
pub fn a_write_partition(a &Ans, index u32, part u32, buffer voidptr, offset u64, count usize) i32 {
	unsafe {
		if a.dead {
			return -a.error
		}
		if !a.live || a.stopping || a.stopped {
			return -ans_stopped
		}
		if !a.write_enabled || a.write_fault || index != a.write_ns || part != a.write_part {
			return -ans_read_only
		}
		if index >= a.nns || part >= a.ns[index].nparts || ((usize(buffer) == 0) && count) {
			return -ans_range
		}
		ns := &a.ns[0] + index
		p := &ns.parts[0] + part
		limit := p.blocks * u64(ns.sector)
		if offset > limit || u64(count) > limit - offset {
			return -ans_range
		}
		if !count {
			return 0
		}
		in_ := &u8(buffer)
		absolute := p.start * u64(ns.sector) + offset
		for count {
			within := u32((absolute % u64(ns.sector)))
			bytes := usize(a.max_transfer - within)
			if bytes > count {
				bytes = count
			}
			sectors := u32(((usize(within) + bytes + usize(ns.sector) - usize(1)) / usize(ns.sector)))
			transfer := sectors * ns.sector
			lba := absolute / u64(ns.sector)
			// The V lock spans the RMW. Complete boundary LBAs remain inside the
			//         *selected partition. Full-LBA writes never read stale bounce data.

			if within || bytes != usize(transfer) {
				rc := a_read_bytes(a, index, voidptr(a.dma + 131072), lba * u64(ns.sector), usize(transfer))
				if rc {
					a.write_fault = u32(1)
					return a_fail(a, -rc)
				}
			}
			a_copy(voidptr(a.dma + 131072 + within), voidptr(in_), bytes)
			c := [64]u8{}
			c[0] = u8(1)
			a_put32(&c[0] + 4, ns.id)
			a_put64(&c[0] + 40, lba)
			a_put16(&c[0] + 48, u16((sectors - u32(1))))
			a_put16(&c[0] + 50, u16(16384))
			// FUA

			a_data_prps(a, &c[0], transfer)
			a_sync(a, 131072, usize(transfer), 0)
			a.dirty_namespaces |= i32(u16((1 << index)))
			rc := a_submit(a, u32(1), &c[0], (voidptr(0)))
			if rc {
				// An error can mean a partial media change. Never retry or recycle
				//             *the failed request; don't pretend to have rolled it back.

				a.write_fault = u32(1)
				return a_fail(a, -rc)
			}
			a.writes_completed++
			C.vinix_account_disk_transfer(u64(transfer), 1)
			absolute += u64(bytes)
			in_ += bytes
			count -= bytes
		}
		return a_flush_ns(a, index)
		// no success before persistence barrier
	}
}

@[export: 'a_power_state']
pub fn a_power_state(a &Ans, ap i32, state u32) i32 {
	unsafe {
		if ap {
			a.ap_power = u32(4294967295)
		} else {
			a.iop_power = u32(4294967295)
		}
		if a_send(a, u32(0), (u64((if ap { 11 } else { 6 })) << 52) | u64(state)) {
			return -a.error
		}
		deadline := a_begin(a)
		for i := u32(0); i < u32(1000000); i++ {
			if a_pump(a) < 0 {
				return -a.error
			}
			if (if ap { a.ap_power } else { a.iop_power }) == state {
				return 0
			}
			if a_expired(a, &deadline, u64(10000000)) {
				break
			}
			a.ops.delay(voidptr(a.cookie), u32(10))
		}
		return a_fail(a, i32(ans_timeout))
	}
}

@[export: 'a_shutdown']
pub fn a_shutdown(a &Ans) i32 {
	unsafe {
		if !a.started || a.stopped {
			return 0
		}
		if a.dead {
			return -a.error
		}
		if !a.live || a.stopping {
			return -ans_stopped
		}
		a.stopping = u32(1)
		a.stage = u32(8)
		rc := a_flush_all(a)
		if rc {
			return rc
		}
		if a.ioq_active {
			c := [64]u8{}
			a_put16(&c[0] + 40, u16(1))
			// Delete SQ 1

			rc = a_submit(a, u32(0), &c[0], (voidptr(0)))
			if rc {
				return a_fail(a, -rc)
			}
			c[0] = u8(4)
			rc = a_submit(a, u32(0), &c[0], (voidptr(0)))
			if rc {
				return a_fail(a, -rc)
			}
			a.ioq_active = u32(0)
		}
		a.stage = u32(9)
		cc := a_r32(a, a.nvme, 20)
		// SHN=normal -> SHST=complete -> EN=0 -> RDY=0, never a reset.

		a_w32(a, a.nvme, 20, (cc & ~(3 << 14)) | (1 << 14))
		if a_wait32(a, 28, 3 << 2, 2 << 2, 30000000) {
			return -a.error
		}
		a_w32(a, a.nvme, 20, cc & ~(1 | (3 << 14)))
		if a_wait32(a, 28, u32(1), u32(0), u64(5000000)) {
			return -a.error
		}
		a.stage = u32(10)
		if a_power_state(a, 1, u32(16)) || a_power_state(a, 0, u32(1)) {
			return -a.error
		}
		a_w32(a, a.asc, 68, a_r32(a, a.asc, 68) & ~(1 << 4))
		if a_r32(a, a.asc, 68) & (1 << 4) {
			return a_fail(a, i32(ans_firmware))
		}
		// Revoke only extents still matching our ownership record. All DMA memory
		//     *remains pinned even on successful shutdown; failures must not free it.

		for i := u32(0); i < u32(16); i++ {
			if !(u32(a.sart_owned) & (1 << i)) {
				continue
			}
			if a_r32(a, a.sart, i * u32(4)) != (u32(4278190080) | (a.sart_bytes[i] >> 12)) || a_r32(a, a.sart, u32(64) + i * u32(4)) != u32((a.sart_pa[i] >> 12)) {
				return a_fail(a, i32(ans_sart))
			}
		}
		for i := u32(0); i < u32(16); i++ {
			if !(u32(a.sart_owned) & (1 << i)) {
				continue
			}
			a_w32(a, a.sart, i * u32(4), u32(0))
			if a_r32(a, a.sart, i * u32(4)) {
				return a_fail(a, i32(ans_sart))
			}
			a_w32(a, a.sart, u32(64) + i * u32(4), u32(0))
		}
		a.sart_owned = u16(0)
		a.live = 0
		a.stopped = u32(1)
		a.stage = u32(11)
		return 0
	}
}

// SPDX-License-Identifier: GPL-2.0-or-later
// *Private, byte-oriented GPT decoder for the ANS block views.
// *Included by apple_ans.c; no packed-struct or unaligned integer accesses.
//

pub struct Ans_gpt {
pub mut:
	first      u64
	last       u64
	table      u64
	entries    u32
	entry_size u32
	table_crc  u32
	guid       [16]u8
}

@[export: 'a_crc32']
pub fn a_crc32(p &u8, n usize) u32 {
	unsafe {
		mut crc := u32(-1)
		for i := usize(0); i < n; i++ {
			crc ^= u32(p[i])
			for b := u32(0); b < 8; b++ {
				crc = (crc >> 1) ^ if crc & 1 != 0 { u32(0xedb88320) } else { u32(0) }
			}
		}
		return ~crc
	}
}

@[export: 'a_gpt_header']
pub fn a_gpt_header(ns &Ans_namespace, p &u8, lba u64, out &Ans_gpt) i32 {
	unsafe {
		a_gpt_header_signature := [u8(`E`), u8(`F`), u8(`I`), u8(` `), u8(`P`), u8(`A`), u8(`R`),
			u8(`T`)]!

		mut __c2v_condition_15 := false
		mut __c2v_condition_16 := false
		__c2v_condition_16 = ns.blocks < u64(6)
		__c2v_condition_15 = __c2v_condition_16
		if !__c2v_condition_15 {
			mut __c2v_condition_17 := false
			__c2v_condition_17 = !a_equal(p, &a_gpt_header_signature[0], usize(8))
			__c2v_condition_15 = __c2v_condition_17
		}
		if !__c2v_condition_15 {
			mut __c2v_condition_18 := false
			__c2v_condition_18 = a_le32(p + 8) != 65536
			__c2v_condition_15 = __c2v_condition_18
		}
		if !__c2v_condition_15 {
			mut __c2v_condition_19 := false
			__c2v_condition_19 = a_le32(p + 20)
			__c2v_condition_15 = __c2v_condition_19
		}
		if !__c2v_condition_15 {
			mut __c2v_condition_20 := false
			__c2v_condition_20 = a_le64(p + 24) != lba
			__c2v_condition_15 = __c2v_condition_20
		}
		if !__c2v_condition_15 {
			mut __c2v_condition_21 := false
			__c2v_condition_21 = a_le64(p + 32) != (if lba == u64(1) {
				ns.blocks - u64(1)
			} else {
				u64(1)
			})
			__c2v_condition_15 = __c2v_condition_21
		}
		if __c2v_condition_15 {
			return -ans_gpt
		}
		bytes := a_le32(p + 12)
		if bytes < u32(92) || bytes > ns.sector {
			return -ans_gpt
		}
		expected := a_le32(p + 16)
		a_put32(p + 16, u32(0))
		actual := a_crc32(p, usize(bytes))
		a_put32(p + 16, expected)
		if actual != expected {
			return -ans_gpt
		}
		h := Ans_gpt{}

		h.first = a_le64(p + 40)
		h.last = a_le64(p + 48)
		h.table = a_le64(p + 72)
		h.entries = a_le32(p + 80)
		h.entry_size = a_le32(p + 84)
		h.table_crc = a_le32(p + 88)
		a_copy(h.guid, voidptr(p + 56), usize(16))
		mut __c2v_condition_22 := false
		mut __c2v_condition_23 := false
		__c2v_condition_23 = !h.entries
		__c2v_condition_22 = __c2v_condition_23
		if !__c2v_condition_22 {
			mut __c2v_condition_24 := false
			__c2v_condition_24 = h.entries > 128
			__c2v_condition_22 = __c2v_condition_24
		}
		if !__c2v_condition_22 {
			mut __c2v_condition_25 := false
			__c2v_condition_25 = h.entry_size < u32(128)
			__c2v_condition_22 = __c2v_condition_25
		}
		if !__c2v_condition_22 {
			mut __c2v_condition_26 := false
			__c2v_condition_26 = h.entry_size > u32(1024)
			__c2v_condition_22 = __c2v_condition_26
		}
		if !__c2v_condition_22 {
			mut __c2v_condition_27 := false
			__c2v_condition_27 = (h.entry_size & (h.entry_size - u32(1)))
			__c2v_condition_22 = __c2v_condition_27
		}
		if !__c2v_condition_22 {
			mut __c2v_condition_28 := false
			__c2v_condition_28 = h.first < u64(2)
			__c2v_condition_22 = __c2v_condition_28
		}
		if !__c2v_condition_22 {
			mut __c2v_condition_29 := false
			__c2v_condition_29 = h.first > h.last
			__c2v_condition_22 = __c2v_condition_29
		}
		if !__c2v_condition_22 {
			mut __c2v_condition_30 := false
			__c2v_condition_30 = h.last >= ns.blocks - u64(1)
			__c2v_condition_22 = __c2v_condition_30
		}
		if __c2v_condition_22 {
			return -ans_gpt
		}
		table_bytes := u64(h.entries) * u64(h.entry_size)
		table_blocks := (table_bytes + u64(ns.sector) - u64(1)) / u64(ns.sector)
		if table_bytes > u64(131072) || h.table >= ns.blocks || table_blocks > ns.blocks - h.table {
			return -ans_gpt
		}
		if lba == u64(1) {
			if h.table < u64(2) || h.table >= h.first || table_blocks > h.first - h.table {
				return -ans_gpt
			}
		} else if h.table <= h.last || h.table >= lba || table_blocks > lba - h.table {
			return -ans_gpt
		}
		*out = h
		return 0
	}
}

@[export: 'a_gpt_entries']
pub fn a_gpt_entries(ns &Ans_namespace, h &Ans_gpt, table &u8) i32 {
	unsafe {
		zero_guid := [16]u8{}
		if a_crc32(table, usize(h.entries) * usize(h.entry_size)) != h.table_crc {
			return -ans_gpt
		}
		// Validate the entire array before publishing even its first entry.

		for i := u32(0); i < h.entries; i++ {
			p := table + (i * h.entry_size)
			if a_equal(p, &zero_guid[0], usize(16)) {
				continue
			}
			first := a_le64(p + 32)
			last := a_le64(p + 40)

			if a_equal(p + 16, &zero_guid[0], usize(16)) || first < h.first || last > h.last || first > last {
				return -ans_gpt
			}
			for j := u32(0); j < i; j++ {
				q := table + (j * h.entry_size)
				if a_equal(q, &zero_guid[0], usize(16)) {
					continue
				}
				if a_equal(p + 16, q + 16, usize(16)) || (first <= a_le64(q + 40) && a_le64(q + 32) <= last) {
					return -ans_gpt
				}
			}
		}
		ns.nparts = u32(0)
		for i := u32(0); i < h.entries; i++ {
			p := table + (i * h.entry_size)
			if a_equal(p, &zero_guid[0], usize(16)) {
				continue
			}
			part := &ns.parts[0] + ns.nparts++
			a_copy(part.type_guid, voidptr(p), usize(16))
			a_copy(part.guid, voidptr(p + 16), usize(16))
			part.attributes = a_le64(p + 48)
			part.number = i + u32(1)
			// GPT slot numbers, including unused holes

			part.start = a_le64(p + 32)
			part.blocks = a_le64(p + 40) - part.start + u64(1)
			// inclusive end
		}
		return 0
	}
}

@[export: 'a_scan_gpt']
pub fn a_scan_gpt(a &Ans, index u32) i32 {
	unsafe {
		ns := &a.ns[0] + index
		sector := [4096]u8{}
		h := [2]Ans_gpt{}
		valid := [2]i32{}
		ns.nparts = u32(0)
		ns.gpt_complete = u32(0)
		ns.gpt_hybrid = u32(0)
		if ns.blocks < u64(6) || a_read_bytes(a, index, voidptr(&sector[0]), u64(0), usize(ns.sector)) {
			return -ans_gpt
		}
		if i32(sector[510]) != 85 || i32(sector[511]) != 170 {
			return -ans_gpt
		}
		protective := i32(0)
		for i := u32(0); i < u32(4); i++ {
			p := &sector[0] + 446 + (i * u32(16))
			if i32(p[4]) == 238 && a_le32(p + 8) == u32(1) && a_le32(p + 12) {
				protective = 1
			} else if p[4] {
				ns.gpt_hybrid = u32(1)
			}
		}
		if !protective {
			return -ans_gpt
		}
		for i := u32(0); i < u32(2); i++ {
			lba := if i { ns.blocks - u64(1) } else { u64(1) }
			if !a_read_bytes(a, index, voidptr(&sector[0]), lba * u64(ns.sector), usize(ns.sector)) {
				valid[i] = !a_gpt_header(ns, &sector[0], lba, &h[0] + i)
			}
			if a.dead {
				return -a.error
			}
		}
		mut __c2v_condition_31 := false
		mut __c2v_condition_32 := false
		__c2v_condition_32 = valid[0]
		if __c2v_condition_32 {
			__c2v_condition_32 = valid[1]
		}
		if __c2v_condition_32 {
			__c2v_condition_32 = (h[0].first != h[1].first || h[0].last != h[1].last || h[0].entries != h[1].entries || h[0].entry_size != h[1].entry_size || h[0].table_crc != h[1].table_crc || !a_equal(&h[0].guid[0], &h[1].guid[0], usize(16)))
		}
		__c2v_condition_31 = __c2v_condition_32
		if __c2v_condition_31 {
			return -ans_gpt
		}
		// Never guess between two valid but conflicting GPTs.

		for i := u32(0); i < u32(2); i++ {
			if !valid[i] {
				continue
			}
			if a_read_bytes(a, index, voidptr(a.dma + 196608), h[i].table * u64(ns.sector), usize(h[i].entries) * usize(h[i].entry_size)) {
				if a.dead {
					return -a.error
				}
				continue
			}
			if !a_gpt_entries(ns, &h[0] + i, a.dma + 196608) {
				// Write opt-in requires both tables to be byte-identical, not just
				//             *equal CRC32s. A single intact copy still permits read-only recovery.

				if valid[0] && valid[1] {
					total := usize(h[i].entries) * usize(h[i].entry_size)
					off := usize(0)

					for off < total {
						n := total - off
						if n > sizeof([4096]u8) {
							n = sizeof([4096]u8)
						}
						if a_read_bytes(a, index, voidptr(&sector[0]), h[u32(1) - i].table * u64(ns.sector) + u64(off), n) || !a_equal(&sector[0], a.dma + 196608 + off, n) {
							break
						}
						off += n
					}
					if a.dead {
						ns.nparts = u32(0)
						return -a.error
					}
					ns.gpt_complete = u32(off == total)
				}
				return 0
			}
		}
		return -ans_gpt
	}
}

// GPT includes both CRCs and overlap checks.

@[export: 'a_start']
pub fn a_start(a &Ans) i32 {
	unsafe {
		mut __c2v_condition_33 := false
		mut __c2v_condition_34 := false
		__c2v_condition_34 = !a.nvme
		__c2v_condition_33 = __c2v_condition_34
		if !__c2v_condition_33 {
			mut __c2v_condition_35 := false
			__c2v_condition_35 = !a.asc
			__c2v_condition_33 = __c2v_condition_35
		}
		if !__c2v_condition_33 {
			mut __c2v_condition_36 := false
			__c2v_condition_36 = !a.mailbox
			__c2v_condition_33 = __c2v_condition_36
		}
		if !__c2v_condition_33 {
			mut __c2v_condition_37 := false
			__c2v_condition_37 = !a.sart
			__c2v_condition_33 = __c2v_condition_37
		}
		if !__c2v_condition_33 {
			mut __c2v_condition_38 := false
			__c2v_condition_38 = !a.reset
			__c2v_condition_33 = __c2v_condition_38
		}
		if !__c2v_condition_33 {
			mut __c2v_condition_39 := false
			__c2v_condition_39 = (usize(a.dma) == 0)
			__c2v_condition_33 = __c2v_condition_39
		}
		if !__c2v_condition_33 {
			mut __c2v_condition_40 := false
			__c2v_condition_40 = (a.nvme | a.asc | a.mailbox | a.sart) & u64(7)
			__c2v_condition_33 = __c2v_condition_40
		}
		if !__c2v_condition_33 {
			mut __c2v_condition_41 := false
			__c2v_condition_41 = (a.reset & u64(3))
			__c2v_condition_33 = __c2v_condition_41
		}
		if !__c2v_condition_33 {
			mut __c2v_condition_42 := false
			__c2v_condition_42 = (a.physical & u64((16384 - u32(1))))
			__c2v_condition_33 = __c2v_condition_42
		}
		if !__c2v_condition_33 {
			mut __c2v_condition_43 := false
			__c2v_condition_43 = (usize(voidptr(a.dma)) & usize((16384 - u32(1))))
			__c2v_condition_33 = __c2v_condition_43
		}
		if !__c2v_condition_33 {
			mut __c2v_condition_44 := false
			__c2v_condition_44 = !a.physical
			__c2v_condition_33 = __c2v_condition_44
		}
		if !__c2v_condition_33 {
			mut __c2v_condition_45 := false
			__c2v_condition_45 = a.physical > ((u64(1) << 42) - u64(1)) - u64((4587520 - u32(1)))
			__c2v_condition_33 = __c2v_condition_45
		}
		if !__c2v_condition_33 {
			mut __c2v_condition_46 := false
			__c2v_condition_46 = (usize(a.ops.read32) == 0)
			__c2v_condition_33 = __c2v_condition_46
		}
		if !__c2v_condition_33 {
			mut __c2v_condition_47 := false
			__c2v_condition_47 = (usize(a.ops.write32) == 0)
			__c2v_condition_33 = __c2v_condition_47
		}
		if !__c2v_condition_33 {
			mut __c2v_condition_48 := false
			__c2v_condition_48 = (usize(a.ops.read64) == 0)
			__c2v_condition_33 = __c2v_condition_48
		}
		if !__c2v_condition_33 {
			mut __c2v_condition_49 := false
			__c2v_condition_49 = (usize(a.ops.write64) == 0)
			__c2v_condition_33 = __c2v_condition_49
		}
		if !__c2v_condition_33 {
			mut __c2v_condition_50 := false
			__c2v_condition_50 = (usize(a.ops.now) == 0)
			__c2v_condition_33 = __c2v_condition_50
		}
		if !__c2v_condition_33 {
			mut __c2v_condition_51 := false
			__c2v_condition_51 = (usize(a.ops.delay) == 0)
			__c2v_condition_33 = __c2v_condition_51
		}
		if !__c2v_condition_33 {
			mut __c2v_condition_52 := false
			__c2v_condition_52 = (usize(a.ops.sync) == 0)
			__c2v_condition_33 = __c2v_condition_52
		}
		if !__c2v_condition_33 {
			mut __c2v_condition_53 := false
			__c2v_condition_53 = a.started
			__c2v_condition_33 = __c2v_condition_53
		}
		if __c2v_condition_33 {
			return a_fail(a, i32(ans_config))
		}
		a.started = 1
		a.stage = u32(1)
		// Only the clean, stopped U-Boot/m1n1 handoff is supported. Never reset
		//     *a running firmware instance whose DMA ownership belongs to someone else.

		if a_r32(a, a.asc, 68) & (1 << 4) {
			return a_fail(a, i32(ans_handoff))
		}
		reset := a_r32(a, a.reset, u32(0))
		if (reset & 240) != 240 {
			return a_fail(a, i32(ans_config))
		}
		a_w32(a, a.reset, u32(0), (reset & ~(3 << 8)) | (1 << 10))
		a_w32(a, a.reset, u32(0), (reset & ~(3 << 8)) | (1 << 10) | (u32(1) << 31))
		a.ops.delay(voidptr(a.cookie), u32(10))
		a_w32(a, a.reset, u32(0), (reset & ~((3 << 8) | (u32(1) << 31))) | (1 << 10))
		a_w32(a, a.reset, u32(0), reset & ~((3 << 8) | (u32(1) << 31) | (1 << 10)))
		a_zero(voidptr(a.dma), usize(393216))
		a_sync(a, u32(0), usize(393216), 0)
		a_w32(a, a.asc, 68, (1 << 4))
		a.stage = u32(2)
		if a_boot_rtkit(a) {
			return -a.error
		}
		a.stage = u32(3)
		if a_wait32(a, 4864, u32(4294967295), u32(3732000341), u64(5000000)) {
			return -a.error
		}
		// With stopped firmware the previous loader must also have disabled NVMe.

		if (a_r32(a, a.nvme, 20) & 1) || (a_r32(a, a.nvme, 28) & 1) {
			return a_fail(a, i32(ans_handoff))
		}
		cap := a.ops.read64(voidptr(a.cookie), a.nvme + u64(0))
		// 4-KiB ans_controller pages, NVM command set, 64 slots, 4-byte doorbells.

		if (cap & u64(65535)) < u64(64 - u32(1)) || ((cap >> 32) & u64(15)) || ((cap >> 48) & u64(15)) || !(cap & (u64(1) << 37)) {
			return a_fail(a, i32(ans_capability))
		}
		a_w32(a, a.nvme, 12, u32(4294967295))
		a_w32(a, a.nvme, 149768, u32(1))
		a_w32(a, a.nvme, 4624, 64 | (64 << 16))
		a_w32(a, a.nvme, 164096, 64 - u32(1))
		// U-Boot's M1 bring-up disables the spurious PRP2-null check and selects
		//     *mode 0. All our PRPs are still built/validated before submission.

		a_w32(a, a.nvme, 147464, a_r32(a, a.nvme, 147464) & ~(1 << 11))
		a_w32(a, a.nvme, 4868, u32(0))
		a_w32(a, a.nvme, 36, 1 | (1 << 16))
		a.ops.write64(voidptr(a.cookie), a.nvme + u64(40), a.physical + u64(0))
		a.ops.write64(voidptr(a.cookie), a.nvme + u64(48), a.physical + u64(16384))
		a.ops.write64(voidptr(a.cookie), a.nvme + u64(164104), a.physical + u64(32768))
		a.ops.write64(voidptr(a.cookie), a.nvme + u64(164112), a.physical + u64(81920))
		a.queues[1].phase = u32(1)
		a.queues[0].phase = a.queues[1].phase
		a.stage = u32(4)
		a_w32(a, a.nvme, 20, 1 | (7 << 16) | (4 << 20))
		if a_wait32(a, 28, u32(1), u32(1), u64(5000000)) {
			return -a.error
		}
		rc := a_identify(a, u32(0), u32(1))
		if rc {
			return a_fail(a, -rc)
		}
		id := a.dma + 131072
		nn := a_le32(id + 516)
		if !nn || u32(a_le16(id)) != 4203 {
			return a_fail(a, i32(ans_capability))
		}
		a.max_transfer = 65536
		mdts := u32(id[77])
		if mdts && mdts < u32(4) {
			a.max_transfer = 4096 << mdts
		}
		// All supported LBAs fit even the smallest MDTS (4 KiB).

		c := [64]u8{}
		c[0] = u8(9)
		a_put32(&c[0] + 40, u32(7))
		rc = a_submit(a, u32(0), &c[0], (voidptr(0)))
		if rc {
			return a_fail(a, -rc)
		}
		a_zero(voidptr(&c[0]), sizeof([64]u8))
		c[0] = u8(5)
		a_put64(&c[0] + 24, a.physical + u64(65536))
		a_put16(&c[0] + 40, u16(1))
		a_put16(&c[0] + 42, u16(64 - u32(1)))
		a_put16(&c[0] + 44, u16(1))
		rc = a_submit(a, u32(0), &c[0], (voidptr(0)))
		if rc {
			return a_fail(a, -rc)
		}
		a_zero(voidptr(&c[0]), sizeof([64]u8))
		c[0] = u8(1)
		a_put64(&c[0] + 24, a.physical + u64(49152))
		a_put16(&c[0] + 40, u16(1))
		a_put16(&c[0] + 42, u16(64 - u32(1)))
		a_put16(&c[0] + 44, u16(1))
		a_put16(&c[0] + 46, u16(1))
		rc = a_submit(a, u32(0), &c[0], (voidptr(0)))
		if rc {
			return a_fail(a, -rc)
		}
		a.ioq_active = u32(1)
		a.stage = u32(5)
		rc = a_identify(a, u32(0), u32(2))
		if rc {
			return a_fail(a, -rc)
		}
		ids := [8]u32{}
		nids := u32(0)
		for i := u32(0); i < 4096 / u32(4); i++ {
			nsid := a_le32(a.dma + 131072 + (i * u32(4)))
			if !nsid {
				break
			}
			if nsid == u32(4294967295) || nsid > nn || (nids && nsid <= ids[nids - u32(1)]) || nids == 8 {
				return a_fail(a, i32(ans_namespace))
			}
			ids[nids++] = nsid
		}
		if !nids {
			return a_fail(a, i32(ans_namespace))
		}
		for i := u32(0); i < nids; i++ {
			rc = a_identify(a, ids[i], u32(0))
			if rc {
				return a_fail(a, -rc)
			}
			rc = a_parse_namespace(&a.ns[0] + a.nns, ids[i], a.dma + 131072)
			if rc {
				return a_fail(a, -rc)
			}
			a.nns++
		}
		a.stage = u32(6)
		for i := u32(0); i < a.nns; i++ {
			// Bad/missing GPT only suppresses partition views, not the raw disk.

			a_scan_gpt(a, i)
			if a.dead {
				return -a.error
			}
		}
		a.stage = u32(7)
		a.live = 1
		return 0
	}
}

@[export: 'vinix_ans_boot_flags']
pub fn vinix_ans_boot_flags(s &char, n usize) i32 {
	unsafe {
		p := Ans_policy{}
		return if a_parse_policy(s, n, &p) { -ans_config } else { i32(p.flags) }
	}
}

@[export: 'vinix_ans_requested']
pub fn vinix_ans_requested(s &char, n usize) i32 {
	unsafe {
		vinix_ans_requested_yes := [i8(118), 105, 110, 105, 120, 46, 97, 112, 112, 108, 101, 95,
			97, 110, 115, 61, 49, 0]!
		vinix_ans_requested_no := [i8(118), 105, 110, 105, 120, 46, 97, 112, 112, 108, 101, 95,
			97, 110, 115, 61, 48, 0]!

		found := i32(0)
		if (usize(s) == 0) || n > usize(16384) {
			return 0
		}
		for i := usize(0); i < n; {
			for i < n && (i32(s[i]) == i8(` `) || i32(s[i]) == i8(`\t`) || i32(s[i]) == i8(`\n`) || i32(s[i]) == i8(`\r`)) {
				i++
			}
			start := i
			for i < n && i32(s[i]) != i8(` `) && i32(s[i]) != i8(`\t`) && i32(s[i]) != i8(`\n`) && i32(s[i]) != i8(`\r`) {
				i++
			}
			if i - start == sizeof([18]i8) - u64(1) && a_equal(&u8(voidptr(s)) + start, &u8(voidptr(&vinix_ans_requested_no[0])), sizeof([18]i8) - u64(1)) {
				return 0
			}
			// disable wins

			if i - start == sizeof([18]i8) - u64(1) && a_equal(&u8(voidptr(s)) + start, &u8(voidptr(&vinix_ans_requested_yes[0])), sizeof([18]i8) - u64(1)) {
				found = 1
			}
		}
		return found
	}
}

@[export: 'a_root_disk']
pub fn a_root_disk(cookie voidptr, buffer voidptr, offset u64, count usize) i32 {
	unsafe {
		a := &Ans(cookie)
		if !a.live || !a.root_selected {
			return -ans_stopped
		}
		ns := &a.ns[0] + a.root_ns
		p := &ns.parts[0] + a.root_part
		bytes := p.blocks * u64(ns.sector)
		if offset > bytes || u64(count) > bytes - offset {
			return -ans_range
		}
		return a_read_bytes(a, a.root_ns, voidptr(buffer), p.start * u64(ns.sector) + offset, count)
	}
}

@[export: 'a_open_root']
pub fn a_open_root(a &Ans, context voidptr, size usize) i32 {
	unsafe {
		if !a.live || !a.root_selected {
			return -ans_stopped
		}
		ns := &a.ns[0] + a.root_ns
		return C.vinix_ext2_open(voidptr(context), size, a_root_disk, voidptr(a), ns.parts[a.root_part].blocks * u64(ns.sector))
	}
}

@[export: 'a_data_disk']
pub fn a_data_disk(cookie voidptr, buffer voidptr, offset u64, count usize) i32 {
	unsafe {
		a := &Ans(cookie)
		if !a.live || !a.write_enabled {
			return -ans_stopped
		}
		ns := &a.ns[0] + a.write_ns
		p := &ns.parts[0] + a.write_part
		bytes := p.blocks * u64(ns.sector)
		if offset > bytes || u64(count) > bytes - offset {
			return -ans_range
		}
		return a_read_bytes(a, a.write_ns, voidptr(buffer), p.start * u64(ns.sector) + offset, count)
	}
}

@[export: 'a_data_store']
pub fn a_data_store(cookie voidptr, buffer voidptr, offset u64, count usize) i32 {
	unsafe {
		a := &Ans(cookie)
		return a_write_partition(a, a.write_ns, a.write_part, voidptr(buffer), offset, count)
	}
}

fn C.vinix_mmio_read32(arg voidptr) u32

fn C.vinix_mmio_read64(arg voidptr) u64

fn C.vinix_mmio_write32(arg voidptr, arg_2 u32)

fn C.vinix_mmio_write64(arg voidptr, arg_2 u64)

__global ans_controller Ans

__global a_counter_frequency u64

__global a_cache_line u32

@[export: 'a_kernel_read32']
pub fn a_kernel_read32(cookie voidptr, p u64) u32 {
	unsafe {
		v := C.vinix_mmio_read32(voidptr(usize(p)))
		asm volatile aarch64 {
		dmb sy
		; ; ; memory
	}
		return v
	}
}

@[export: 'a_kernel_read64']
pub fn a_kernel_read64(cookie voidptr, p u64) u64 {
	unsafe {
		v := C.vinix_mmio_read64(voidptr(usize(p)))
		asm volatile aarch64 {
		dmb sy
		; ; ; memory
	}
		return v
	}
}

@[export: 'a_kernel_write32']
pub fn a_kernel_write32(cookie voidptr, p u64, v u32) {
	unsafe {
		asm volatile aarch64 {
		dmb sy
		; ; ; memory
	}
		C.vinix_mmio_write32(voidptr(usize(p)), v)
	}
}

@[export: 'a_kernel_write64']
pub fn a_kernel_write64(cookie voidptr, p u64, v u64) {
	unsafe {
		asm volatile aarch64 {
		dmb sy
		; ; ; memory
	}
		C.vinix_mmio_write64(voidptr(usize(p)), v)
	}
}

@[export: 'a_kernel_now']
pub fn a_kernel_now(cookie voidptr) u64 {
	unsafe {
		mut n := u64(0)
		asm volatile aarch64 { mrs n, cntvct_el0 ; =r (n) ; ; memory }
		return n / a_counter_frequency * u64(1000000) + n % a_counter_frequency * u64(1000000) / a_counter_frequency
	}
}

@[export: 'a_kernel_delay']
pub fn a_kernel_delay(cookie voidptr, us u32) {
	unsafe {
		start := a_kernel_now(voidptr(cookie))
		// Cap even a stopped architectural counter; never execute WFE here.

		for i := u32(0); i < u32(4096) && a_kernel_now(voidptr(cookie)) - start < u64(us); i++ {
			asm volatile aarch64 {
		yield
		; ; ; memory
	}
		}
	}
}

@[export: 'a_kernel_sync']
pub fn a_kernel_sync(cookie voidptr, buffer voidptr, n usize, cpu i32) {
	unsafe {
		begin := usize(buffer)
		end := begin + n
		asm volatile aarch64 {
		dsb sy
		; ; ; memory
	}
		for p := begin & ~usize((a_cache_line - u32(1))); p < end; p += usize(a_cache_line) {
			if cpu {
				asm volatile aarch64 { dc ivac, p ; ; r (p) ; memory }
			} else {
				asm volatile aarch64 { dc civac, p ; ; r (p) ; memory }
			}
		}
		asm volatile aarch64 {
		dsb sy
		; ; ; memory
	}
	}
}

@[export: 'vinix_ans_init']
pub fn vinix_ans_init(nvme u64, asc u64, mailbox u64, sart u64, reset u64, dma voidptr, physical u64, bytes usize) i32 {
	unsafe {
		if ans_controller.started || bytes < usize(4587520) || (usize(dma) == 0) || usize(dma) > u64(-1) - u64(4587520) {
			return -ans_config
		}
		mut ctr := u64(0)
		mut frequency := u64(0)
		asm volatile aarch64 { mrs frequency, cntfrq_el0 ; =r (frequency) }
		asm volatile aarch64 { mrs ctr, ctr_el0 ; =r (ctr) }
		a_counter_frequency = frequency
		if !a_counter_frequency || a_counter_frequency > u64(u32(4294967295)) {
			return -ans_config
		}
		a_cache_line = 4 << ((ctr >> 16) & u64(15))
		if a_cache_line > 16384 {
			return -ans_config
		}
		ans_controller = Ans{}

		ans_controller.ops = Ans_ops{
			read32:  a_kernel_read32
			write32: a_kernel_write32
			read64:  a_kernel_read64
			write64: a_kernel_write64
			now:     a_kernel_now
			delay:   a_kernel_delay
			sync:    a_kernel_sync
		}

		ans_controller.nvme = nvme
		ans_controller.asc = asc
		ans_controller.mailbox = mailbox
		ans_controller.sart = sart
		ans_controller.reset = reset
		ans_controller.dma = &u8(dma)
		ans_controller.physical = physical
		return a_start(&ans_controller)
	}
}

@[export: 'vinix_ans_namespace_count']
pub fn vinix_ans_namespace_count() i32 {
	unsafe {
		return if ans_controller.live { i32(ans_controller.nns) } else { 0 }
	}
}

@[export: 'vinix_ans_namespace_id']
pub fn vinix_ans_namespace_id(i u32) u32 {
	unsafe {
		return if i < ans_controller.nns { ans_controller.ns[i].id } else { u32(0) }
	}
}

@[export: 'vinix_ans_sector_size']
pub fn vinix_ans_sector_size(i u32) u32 {
	unsafe {
		return if i < ans_controller.nns { ans_controller.ns[i].sector } else { u32(0) }
	}
}

@[export: 'vinix_ans_sector_count']
pub fn vinix_ans_sector_count(i u32) u64 {
	unsafe {
		return if i < ans_controller.nns { ans_controller.ns[i].blocks } else { u64(0) }
	}
}

@[export: 'vinix_ans_partition_count']
pub fn vinix_ans_partition_count(i u32) i32 {
	unsafe {
		return if i < ans_controller.nns { i32(ans_controller.ns[i].nparts) } else { 0 }
	}
}

@[export: 'vinix_ans_partition_number']
pub fn vinix_ans_partition_number(i u32, p u32) u32 {
	unsafe {
		return if i < ans_controller.nns && p < ans_controller.ns[i].nparts {
			ans_controller.ns[i].parts[p].number
		} else {
			u32(0)
		}
	}
}

@[export: 'vinix_ans_partition_start']
pub fn vinix_ans_partition_start(i u32, p u32) u64 {
	unsafe {
		return if i < ans_controller.nns && p < ans_controller.ns[i].nparts {
			ans_controller.ns[i].parts[p].start
		} else {
			u64(0)
		}
	}
}

@[export: 'vinix_ans_partition_blocks']
pub fn vinix_ans_partition_blocks(i u32, p u32) u64 {
	unsafe {
		return if i < ans_controller.nns && p < ans_controller.ns[i].nparts {
			ans_controller.ns[i].parts[p].blocks
		} else {
			u64(0)
		}
	}
}

@[export: 'vinix_ans_read']
pub fn vinix_ans_read(i u32, buf voidptr, offset u64, count usize) i32 {
	unsafe {
		return if ans_controller.live {
			a_read_bytes(&ans_controller, i, voidptr(buf), offset, count)
		} else {
			-ans_firmware
		}
	}
}

@[export: 'vinix_ans_apply_policy']
pub fn vinix_ans_apply_policy(s &char, n usize) i32 {
	unsafe {
		p := Ans_policy{}
		rc := a_parse_policy(s, n, &p)
		return if rc { rc } else { a_apply_policy(&ans_controller, &p) }
	}
}

@[export: 'vinix_ans_partition_writable']
pub fn vinix_ans_partition_writable(i u32, p u32) i32 {
	unsafe {
		return i32(ans_controller.live && ans_controller.write_enabled && !ans_controller.write_fault && !ans_controller.stopping && i == ans_controller.write_ns && p == ans_controller.write_part)
	}
}

@[export: 'vinix_ans_partition_uuid']
pub fn vinix_ans_partition_uuid(i u32, p u32, out &char, n usize) i32 {
	unsafe {
		if (usize(out) == 0) || n < usize(37) || i >= ans_controller.nns || p >= ans_controller.ns[i].nparts {
			return -ans_range
		}
		a_guid_format(&ans_controller.ns[i].parts[p].guid[0], out)
		return 0
	}
}

@[export: 'vinix_ans_write']
pub fn vinix_ans_write(i u32, p u32, buf voidptr, off u64, n usize) i32 {
	unsafe {
		return a_write_partition(&ans_controller, i, p, voidptr(buf), off, n)
	}
}

@[export: 'vinix_ans_flush']
pub fn vinix_ans_flush() i32 {
	unsafe {
		return a_flush_all(&ans_controller)
	}
}

@[export: 'vinix_ans_shutdown']
pub fn vinix_ans_shutdown() i32 {
	unsafe {
		return a_shutdown(&ans_controller)
	}
}

@[export: 'vinix_ans_root_ns']
pub fn vinix_ans_root_ns() i32 {
	unsafe {
		return if ans_controller.root_selected { i32(ans_controller.root_ns) } else { -1 }
	}
}

@[export: 'vinix_ans_root_part']
pub fn vinix_ans_root_part() i32 {
	unsafe {
		return if ans_controller.root_selected { i32(ans_controller.root_part) } else { -1 }
	}
}

// Only this adapter turns an ext2 byte offset into a namespace offset. It
// *cannot read beyond the selected root partition, including during mount.

__global a_root_context AlignedContext

__global a_data_context AlignedContext

@[aligned: 16]
struct AlignedContext {
	bytes [256]u8
}

@[export: 'vinix_ans_root_open']
pub fn vinix_ans_root_open() i32 {
	unsafe {
		return a_open_root(&ans_controller, voidptr(&a_root_context.bytes[0]), sizeof([256]u8))
	}
}

@[export: 'vinix_ans_root_stat']
pub fn vinix_ans_root_stat(ino u32, fields &u64) i32 {
	unsafe {
		return if ans_controller.live {
			C.vinix_ext2_stat(voidptr(&a_root_context.bytes[0]), ino, fields)
		} else {
			-ans_stopped
		}
	}
}

@[export: 'vinix_ans_root_read']
pub fn vinix_ans_root_read(ino u32, buffer voidptr, offset u64, count usize) i64 {
	unsafe {
		return if ans_controller.live {
			C.vinix_ext2_read(voidptr(&a_root_context.bytes[0]), ino, voidptr(buffer), offset, count)
		} else {
			i64(-ans_stopped)
		}
	}
}

@[export: 'vinix_ans_root_next']
pub fn vinix_ans_root_next(dir u32, offset &u64, ino &u32, name &char, cap usize) i32 {
	unsafe {
		return if ans_controller.live {
			C.vinix_ext2_next(voidptr(&a_root_context.bytes[0]), dir, offset, ino, name, cap)
		} else {
			-ans_stopped
		}
	}
}

@[export: 'vinix_ans_data_open']
pub fn vinix_ans_data_open() i32 {
	unsafe {
		if !ans_controller.live || !ans_controller.write_enabled || C.vinix_ext2_context_size() > sizeof([256]u8) {
			return -ans_stopped
		}
		ns := &ans_controller.ns[0] + ans_controller.write_ns
		return C.vinix_ext2_open_rw(voidptr(&a_data_context.bytes[0]), sizeof([256]u8), a_data_disk, a_data_store, voidptr(&ans_controller), ns.parts[ans_controller.write_part].blocks * u64(ns.sector))
	}
}

@[export: 'vinix_ans_data_begin']
pub fn vinix_ans_data_begin() i32 {
	unsafe {
		return C.vinix_ext2_begin_write(voidptr(&a_data_context.bytes[0]))
	}
}

@[export: 'vinix_ans_data_close']
pub fn vinix_ans_data_close() i32 {
	unsafe {
		return C.vinix_ext2_close_clean(voidptr(&a_data_context.bytes[0]))
	}
}

@[export: 'vinix_ans_data_stat']
pub fn vinix_ans_data_stat(ino u32, fields &u64) i32 {
	unsafe {
		return if ans_controller.live {
			C.vinix_ext2_stat(voidptr(&a_data_context.bytes[0]), ino, fields)
		} else {
			-ans_stopped
		}
	}
}

@[export: 'vinix_ans_data_read']
pub fn vinix_ans_data_read(ino u32, buffer voidptr, offset u64, count usize) i64 {
	unsafe {
		return if ans_controller.live {
			C.vinix_ext2_read(voidptr(&a_data_context.bytes[0]), ino, voidptr(buffer), offset, count)
		} else {
			i64(-ans_stopped)
		}
	}
}

@[export: 'vinix_ans_data_write']
pub fn vinix_ans_data_write(ino u32, buffer voidptr, offset u64, count usize) i64 {
	unsafe {
		return if ans_controller.live {
			C.vinix_ext2_write(voidptr(&a_data_context.bytes[0]), ino, voidptr(buffer), offset, count)
		} else {
			i64(-ans_stopped)
		}
	}
}

@[export: 'vinix_ans_data_truncate']
pub fn vinix_ans_data_truncate(ino u32, size u64) i32 {
	unsafe {
		return if ans_controller.live {
			C.vinix_ext2_truncate(voidptr(&a_data_context.bytes[0]), ino, size)
		} else {
			-ans_stopped
		}
	}
}

@[export: 'vinix_ans_data_next']
pub fn vinix_ans_data_next(dir u32, offset &u64, ino &u32, name &char, cap usize) i32 {
	unsafe {
		return if ans_controller.live {
			C.vinix_ext2_next(voidptr(&a_data_context.bytes[0]), dir, offset, ino, name, cap)
		} else {
			-ans_stopped
		}
	}
}

@[export: 'vinix_ans_data_create']
pub fn vinix_ans_data_create(parent u32, name &char, n usize, mode u32, ino &u32) i32 {
	unsafe {
		return if ans_controller.live {
			C.vinix_ext2_create(voidptr(&a_data_context.bytes[0]), parent, name, n, mode, ino)
		} else {
			-ans_stopped
		}
	}
}

@[export: 'vinix_ans_data_symlink']
pub fn vinix_ans_data_symlink(parent u32, name &char, n usize, target &char, target_n usize, ino &u32) i32 {
	unsafe {
		return if ans_controller.live {
			C.vinix_ext2_symlink(voidptr(&a_data_context.bytes[0]), parent, name, n, target, target_n, ino)
		} else {
			-ans_stopped
		}
	}
}

@[export: 'vinix_ans_data_link']
pub fn vinix_ans_data_link(parent u32, name &char, n usize, ino u32) i32 {
	unsafe {
		return if ans_controller.live {
			C.vinix_ext2_link(voidptr(&a_data_context.bytes[0]), parent, name, n, ino)
		} else {
			-ans_stopped
		}
	}
}

@[export: 'vinix_ans_data_unlink']
pub fn vinix_ans_data_unlink(parent u32, name &char, n usize, directory i32) i32 {
	unsafe {
		return if ans_controller.live {
			C.vinix_ext2_unlink(voidptr(&a_data_context.bytes[0]), parent, name, n, directory)
		} else {
			-ans_stopped
		}
	}
}

@[export: 'vinix_ans_data_drop_link']
pub fn vinix_ans_data_drop_link(ino u32) i32 {
	unsafe {
		return if ans_controller.live {
			C.vinix_ext2_drop_link(voidptr(&a_data_context.bytes[0]), ino)
		} else {
			-ans_stopped
		}
	}
}

@[export: 'vinix_ans_data_rename']
pub fn vinix_ans_data_rename(old_parent u32, old_name &char, old_n usize, new_parent u32, new_name &char, new_n usize, replace i32) i32 {
	unsafe {
		return if ans_controller.live {
			C.vinix_ext2_rename(voidptr(&a_data_context.bytes[0]), old_parent, old_name, old_n, new_parent, new_name, new_n, replace)
		} else {
			-ans_stopped
		}
	}
}

@[export: 'vinix_ans_error']
pub fn vinix_ans_error() i32 {
	unsafe {
		return ans_controller.error
	}
}

@[export: 'vinix_ans_stage']
pub fn vinix_ans_stage() u32 {
	unsafe {
		return ans_controller.stage
	}
}

@[export: 'vinix_ans_completion_status']
pub fn vinix_ans_completion_status() u16 {
	unsafe {
		return ans_controller.last_status
	}
}
