// Optional, allocation-free live slab call-site instrumentation.
@[translated]
@[has_globals]
module alloctrack

#include "alloc_track_v.h"

@[c: '__atomic_exchange_n']
fn C.at_exchange(&i32, i32, i32) i32
@[c: '__atomic_store_n']
fn C.at_store(&i32, i32, i32)
@[c: '__atomic_load_n']
fn C.at_load(&i32, i32) i32

struct TrackEntry {
mut:
	ptr u64
	size u64
	pc [10]u64
}

struct AggregateEntry {
mut:
	key u64
	size u64
	count u64
	pc [10]u64
}

__global (
	at_table [65536]TrackEntry
	at_groups [4096]AggregateEntry
	at_enabled i32
	at_lock i32
)

fn try_lock() bool { unsafe { return C.at_exchange(&at_lock, 1, 2) == 0 } }
fn lock() { for !try_lock() {} }
fn unlock() { unsafe { C.at_store(&at_lock, 0, 3) } }

fn slot_of(pointer u64) u64 {
	mut hash := pointer >> 4
	hash ^= hash >> 17
	hash *= u64(0x9e3779b97f4a7c15)
	return (hash >> 20) & 65535
}

@[export: 'vinix_alloc_track_enter']
pub fn track_enter(pointer voidptr, size u64, frame &u64) {
	unsafe {
		if C.at_load(&at_enabled, 0) == 0 || usize(pointer) == 0 { return }
		mut pcs := [10]u64{}
		mut fp := frame
		minimum := kernel_address_min()
		for i := 0; i < 10; i++ {
			if u64(fp) < minimum || (u64(fp) & 7) != 0 { continue }
			pcs[i] = fp[1]
			fp = &u64(fp[0])
		}
		if !try_lock() { return }
		mut slot := slot_of(u64(pointer))
		for n := u64(0); n < 65535; n++ {
			current := at_table[slot].ptr
			if current == u64(pointer) || current == 0 {
				at_table[slot].ptr = u64(pointer)
				at_table[slot].size = size
				for i := 0; i < 10; i++ { at_table[slot].pc[i] = pcs[i] }
				break
			}
			slot = (slot + 1) & 65535
		}
		unlock()
	}
}

@[export: 'alloc_untrack']
pub fn untrack(pointer voidptr) {
	unsafe {
		if C.at_load(&at_enabled, 0) == 0 || usize(pointer) == 0 { return }
		if !try_lock() { return }
		mut index := slot_of(u64(pointer))
		mut n := u64(0)
		for {
			if n == 65536 || at_table[index].ptr == 0 { unlock(); return }
			if at_table[index].ptr == u64(pointer) { break }
			n++
			index = (index + 1) & 65535
		}
		mut next := index
		for {
			next = (next + 1) & 65535
			if at_table[next].ptr == 0 { break }
			origin := slot_of(at_table[next].ptr)
			movable := if index <= next { origin <= index || origin > next } else { origin <= index && origin > next }
			if movable {
				at_table[index] = at_table[next]
				index = next
			}
		}
		at_table[index].ptr = 0
		unlock()
	}
}

@[export: 'alloc_track_start']
pub fn start() {
	unsafe {
		lock()
		C.at_store(&at_enabled, 0, 0)
		for i := 0; i < 65536; i++ { at_table[i].ptr = 0 }
		C.at_store(&at_enabled, 1, 0)
		unlock()
	}
}

fn put_text(out &char, end &char, text &char) &char {
	unsafe {
		mut cursor := out
		mut source := text
		for *source != 0 && usize(cursor) < usize(end) { *cursor = *source; cursor++; source++ }
		return cursor
	}
}

fn put_number(out &char, end &char, input u64, base u64) &char {
	unsafe {
		mut scratch := [21]u8{}
		mut value := input
		mut count := 0
		for {
			scratch[count] = u8(c'0123456789abcdef'[value % base])
			count++
			value /= base
			if value == 0 { break }
		}
		mut cursor := out
		for count != 0 && usize(cursor) < usize(end) { count--; *cursor = char(scratch[count]); cursor++ }
		return cursor
	}
}

@[export: 'alloc_track_dump']
pub fn dump(buffer &char, cap u64, min_count u64) u64 {
	unsafe {
		mut out := buffer
		end := buffer + cap
		lock()
		for i := 0; i < 4096; i++ { at_groups[i].count = 0 }
		mut live := u64(0)
		mut dropped := u64(0)
		for i := 0; i < 65536; i++ {
			entry := &at_table[i]
			if entry.ptr == 0 { continue }
			live++
			mut key := entry.size * u64(0x100000001b3)
			for d := 0; d < 10; d++ { key = (key ^ entry.pc[d]) * u64(0x100000001b3) }
			mut slot := key & 4095
			mut n := 0
			for n < 4096 {
				group := &at_groups[slot]
				if group.count == 0 {
					group.key = key
					group.size = entry.size
					for d := 0; d < 10; d++ { group.pc[d] = entry.pc[d] }
					group.count = 1
					break
				}
				if group.key == key { group.count++; break }
				n++
				slot = (slot + 1) & 4095
			}
			if n == 4096 { dropped++ }
		}
		out = put_text(out, end, c'live ')
		out = put_number(out, end, live, 10)
		out = put_text(out, end, c' dropped ')
		out = put_number(out, end, dropped, 10)
		out = put_text(out, end, c'\n')
		for i := 0; i < 4096; i++ {
			group := &at_groups[i]
			if group.count < min_count { continue }
			out = put_number(out, end, group.count, 10)
			out = put_text(out, end, c' ')
			out = put_number(out, end, group.size, 10)
			for d := 0; d < 10; d++ {
				out = put_text(out, end, c' ')
				out = put_number(out, end, group.pc[d], 16)
			}
			out = put_text(out, end, c'\n')
		}
		unlock()
		return u64(out) - u64(buffer)
	}
}
