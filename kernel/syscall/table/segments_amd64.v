// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
module table

// modify_ldt(2), set_thread_area(2) and get_thread_area(2): the x86 segments
// a process can make for itself, described to the kernel in a struct
// user_desc, as on Linux. Wine and DOSEMU run 32-bit code from an LDT code
// segment, and a program can reach TLS through a selector in FS or GS rather
// than an FS base. How a CPU comes to have them loaded is sched's business;
// see sched/segments_amd64.v.

import errno
import proc
import sched
import usercopy
import x86.gdt

// struct user_desc: an entry number, a base, a limit and these bits.
struct UserDesc {
mut:
	entry_number u32
	base_addr    u32
	limit        u32
	flags        u32
}

const desc_seg_32bit = u32(1) << 0
const desc_contents_shift = 1 // two bits: data, expand-down data, code, conforming code
const desc_read_exec_only = u32(1) << 3
const desc_limit_in_pages = u32(1) << 4
const desc_seg_not_present = u32(1) << 5
const desc_useable = u32(1) << 6
const desc_lm = u32(1) << 7

const user_desc_size = u64(16)

@[inline]
fn (d UserDesc) contents() u32 {
	return (d.flags >> desc_contents_shift) & 3
}

// Linux's LDT_empty() on x86-64: what asks for no segment at all.
fn (d UserDesc) is_empty() bool {
	return d.base_addr == 0 && d.limit == 0
		&& d.flags & (desc_lm | (desc_lm - 1)) == desc_read_exec_only | desc_seg_not_present
}

// Linux's LDT_zero(): all zeroes, which programs take to mean no segment too.
fn (d UserDesc) is_zero() bool {
	return d.base_addr == 0 && d.limit == 0 && d.flags & (desc_lm - 1) == 0
}

// The descriptor Linux's fill_ldt() makes of `d`: of privilege 3, never a
// system descriptor, and never 64-bit code, which SYSRET would not return to.
// Accessed already, so that the CPU never has to write it back.
fn (d UserDesc) descriptor() u64 {
	base := u64(d.base_addr)
	limit := u64(d.limit)
	mut kind := u64(1) | (u64(d.contents()) << 2)
	if d.flags & desc_read_exec_only == 0 {
		kind |= 2
	}
	mut desc := (limit & 0xffff) | ((base & 0xffffff) << 16) | (kind << 40)
	desc |= u64(1) << 44 // a code or data segment
	desc |= u64(3) << 45 // of privilege 3
	if d.flags & desc_seg_not_present == 0 {
		desc |= u64(1) << 47
	}
	desc |= ((limit >> 16) & 0xf) << 48
	if d.flags & desc_useable != 0 {
		desc |= u64(1) << 52
	}
	if d.flags & desc_seg_32bit != 0 {
		desc |= u64(1) << 54
	}
	if d.flags & desc_limit_in_pages != 0 {
		desc |= u64(1) << 55
	}
	desc |= ((base >> 24) & 0xff) << 56
	return desc
}

// The struct user_desc Linux's fill_user_desc() makes of entry `index`,
// holding `desc`.
fn user_desc_of(index u32, desc u64) UserDesc {
	mut flags := u32(0)
	if desc & (u64(1) << 54) != 0 {
		flags |= desc_seg_32bit
	}
	flags |= u32((desc >> 42) & 3) << desc_contents_shift
	if desc & (u64(1) << 41) == 0 {
		flags |= desc_read_exec_only
	}
	if desc & (u64(1) << 55) != 0 {
		flags |= desc_limit_in_pages
	}
	if desc & (u64(1) << 47) == 0 {
		flags |= desc_seg_not_present
	}
	if desc & (u64(1) << 52) != 0 {
		flags |= desc_useable
	}
	if desc & (u64(1) << 53) != 0 {
		flags |= desc_lm
	}
	return UserDesc{
		entry_number: index
		base_addr:    u32(((desc >> 16) & 0xffffff) | (((desc >> 56) & 0xff) << 24))
		limit:        u32((desc & 0xffff) | (((desc >> 48) & 0xf) << 16))
		flags:        flags
	}
}

// Linux's tls_desc_okay(): a TLS descriptor is none at all, or a present
// 32-bit data segment.
fn tls_descriptor_ok(d UserDesc) bool {
	if d.is_empty() || d.is_zero() {
		return true
	}
	return d.flags & desc_seg_32bit != 0 && d.contents() <= 1
		&& d.flags & desc_seg_not_present == 0
}

// set_thread_area(u_info): TLS descriptor u_info->entry_number of the calling
// thread, 12 to 14, or the first free one for -1, whose number is then
// written back. The selector for entry n is n * 8 + 3.
fn syscall_linux_set_thread_area(_ voidptr, u_info u64) (u64, u64) {
	mut info := UserDesc{}
	if !usercopy.copy_from_user(voidptr(&info), u_info, user_desc_size) {
		return errno.err, errno.efault
	}
	if !tls_descriptor_ok(info) {
		return errno.err, errno.einval
	}
	mut index := info.entry_number
	if index == u32(0xffffffff) {
		t := proc.current_thread()
		mut free := -1
		for i := 0; i < gdt.tls_entry_count; i++ {
			if t.tls[i] == 0 {
				free = i
				break
			}
		}
		if free < 0 {
			return errno.err, errno.esrch
		}
		index = u32(gdt.tls_first_entry + free)
		if !usercopy.copy_to_user(u_info, voidptr(&index), sizeof(u32)) {
			return errno.err, errno.efault
		}
	}
	if index < u32(gdt.tls_first_entry)
		|| index >= u32(gdt.tls_first_entry + gdt.tls_entry_count) {
		return errno.err, errno.einval
	}
	descriptor := if info.is_empty() || info.is_zero() { u64(0) } else { info.descriptor() }
	sched.set_tls_descriptor(int(index) - gdt.tls_first_entry, descriptor)
	return 0, 0
}

// get_thread_area(u_info): TLS descriptor u_info->entry_number of the calling
// thread, as a struct user_desc.
fn syscall_linux_get_thread_area(_ voidptr, u_info u64) (u64, u64) {
	index := usercopy.read_u32(u_info) or { return errno.err, errno.efault }
	if index < u32(gdt.tls_first_entry)
		|| index >= u32(gdt.tls_first_entry + gdt.tls_entry_count) {
		return errno.err, errno.einval
	}
	info := user_desc_of(index, proc.current_thread().tls[index - u32(gdt.tls_first_entry)])
	if !usercopy.copy_to_user(u_info, voidptr(&info), user_desc_size) {
		return errno.err, errno.efault
	}
	return 0, 0
}

// modify_ldt(func, ptr, bytecount). Linux declares the result an int and
// returns it as one, zero-extended: an error is a negative 32-bit number, not
// a negative 64-bit one, and a caller that keeps the long syscall() returns
// sees it as positive. Kept, as programs made for Linux read it as an int.
fn syscall_linux_modify_ldt(_ voidptr, func int, ptr u64, bytecount u64) (u64, u64) {
	result, err := modify_ldt(func, ptr, bytecount)
	if err != 0 {
		return u64(u32(-i32(err))), 0
	}
	return result, 0
}

fn modify_ldt(func int, ptr u64, bytecount u64) (u64, u64) {
	match func {
		0 { return read_ldt(ptr, bytecount) }
		1 { return write_ldt(ptr, bytecount, true) }
		2 { return read_default_ldt(ptr, bytecount) }
		0x11 { return write_ldt(ptr, bytecount, false) }
		else { return errno.err, errno.enosys }
	}
}

// Function 0: the LDT, 64 KiB of it at most and zeroes past its last entry,
// or nothing when the process has none.
fn read_ldt(ptr u64, bytecount u64) (u64, u64) {
	mut size := bytecount
	if size > u64(sched.ldt_max_entries) * 8 {
		size = u64(sched.ldt_max_entries) * 8
	}
	if size == 0 {
		return 0, 0
	}
	buf := unsafe { malloc(size) }
	if buf == unsafe { nil } {
		return errno.err, errno.enomem
	}
	unsafe { C.memset(buf, 0, size) }
	if sched.read_ldt(buf, size) < 0 {
		unsafe { free(buf) }
		return 0, 0
	}
	copied := usercopy.copy_to_user(ptr, buf, size)
	unsafe { free(buf) }
	if !copied {
		return errno.err, errno.efault
	}
	return size, 0
}

// Function 2: Linux's default LDT, 128 bytes of zeroes on x86-64.
fn read_default_ldt(ptr u64, bytecount u64) (u64, u64) {
	size := if bytecount > 128 { u64(128) } else { bytecount }
	zeroes := [128]u8{}
	if size != 0 && !usercopy.copy_to_user(ptr, voidptr(&zeroes[0]), size) {
		return errno.err, errno.efault
	}
	return size, 0
}

// Functions 1 and 0x11: set an entry. The old mode, function 1, clears one
// for a base and limit of zero, and ignores the available bit.
//
// 16-bit segments are refused, as Linux built without CONFIG_X86_16BIT
// refuses them: an IRETQ to a 16-bit stack segment restores only the low half
// of ESP and leaves the rest of the kernel stack's address in the high half,
// which Linux has espfix to cover up and this kernel does not.
fn write_ldt(ptr u64, bytecount u64, old_mode bool) (u64, u64) {
	if bytecount != user_desc_size {
		return errno.err, errno.einval
	}
	mut info := UserDesc{}
	if !usercopy.copy_from_user(voidptr(&info), ptr, user_desc_size) {
		return errno.err, errno.efault
	}
	if info.entry_number >= sched.ldt_max_entries {
		return errno.err, errno.einval
	}
	if info.contents() == 3 && (old_mode || info.flags & desc_seg_not_present == 0) {
		return errno.err, errno.einval
	}
	mut descriptor := u64(0)
	if !(old_mode && info.base_addr == 0 && info.limit == 0) && !info.is_empty() {
		if info.flags & desc_seg_32bit == 0 {
			return errno.err, errno.einval
		}
		descriptor = info.descriptor()
		if old_mode {
			descriptor &= ~(u64(1) << 52)
		}
	}
	if !sched.set_ldt_entry(info.entry_number, descriptor) {
		return errno.err, errno.enomem
	}
	return 0, 0
}
