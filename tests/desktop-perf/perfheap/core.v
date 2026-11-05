// SPDX-License-Identifier: GPL-2.0-or-later
// Fixed-storage observer for the source-pinned 4 KiB Vinix slab schema.
module perfheap

#include <errno.h>
#include <fcntl.h>
#include <string.h>
#include <unistd.h>

fn C.open(&char, i32, ...voidptr) i32
fn C.read(i32, voidptr, usize) isize
fn C.close(i32) i32
fn C.memmove(voidptr, voidptr, usize) voidptr

pub const class_sizes = [u64(16), 32, 48, 64, 96, 128, 192, 256, 384, 512, 768,
	1024, 1536, 2048]!
pub const raw_capacity = 4096
pub const page_size = 4096
pub const kernel_revision = '9acefa77bee69247c837e97987a2377536aa41cc'
pub const procfs_sha256 = 'd6c9bddf457cc46c9b588749768e9e4bdce43a51ac540d52b696a6447298d1b1'
const unsigned_max = u64(18446744073709551615)
const signed_max = i64(9223372036854775807)
const signed_min = i64(-9223372036854775807 - 1)
const schema_header = '# class      size    objects   pages\n'

pub struct ClassSnapshot {
pub:
	size u64
	objects u64
	pages u64
}

pub struct Snapshot {
pub mut:
	raw [4096]u8
	raw_len int
	classes [14]ClassSnapshot
	large_pages u64
	written_after_free u64
	valid bool
}

pub struct ClassDelta {
pub:
	size u64
	objects i64
	pages i64
}

pub struct Delta {
pub mut:
	classes [14]ClassDelta
	large_pages i64
	written_after_free i64
	// Object bytes plus large-allocation pages, as in the original observer.
	// Backing-page deltas are separate; adding them here would double-count.
	bytes i64
	valid bool
}

struct Cursor {
	data &u8 = unsafe { nil }
	length int
mut:
	position int
}

fn require(ok bool, message string) ! {
	if !ok { return error(message) }
}

fn literal(cursor Cursor, text string) !Cursor {
	mut position := cursor.position
	for byte in text {
		require(position < cursor.length
			&& unsafe { cursor.data[position] } == byte, 'slab schema literal differs')!
		position++
	}
	return Cursor{...cursor, position: position}
}

fn natural(cursor Cursor) !(u64, Cursor) {
	start := cursor.position
	mut position := start
	mut value := u64(0)
	for position < cursor.length {
		byte := unsafe { cursor.data[position] }
		if byte < `0` || byte > `9` { break }
		digit := u64(byte - `0`)
		require(value <= (unsigned_max - digit) / 10, 'slab counter overflow')!
		value = value * 10 + digit
		position++
	}
	require(position > start, 'slab counter is missing or signed')!
	require(position - start == 1 || unsafe { cursor.data[start] } != `0`,
		'slab counter has a noncanonical leading zero')!
	return value, Cursor{...cursor, position: position}
}

// Both outputs and their raw storage are borrowed. The caller must keep input
// bytes alive for the call; input may be out.raw itself. No slice is constructed.
pub fn parse_snapshot(data &u8, length int, out &Snapshot) ! {
	unsafe { out.valid = false; out.raw_len = 0 }
	require(data != unsafe { nil } && length > 0 && length <= raw_capacity,
		'empty, absent or oversized slab snapshot')!
	// Pass parser state by value: even addressed fixed arrays are heap-promoted.
	mut cursor := literal(Cursor{data: data, length: length}, schema_header)!
	for index, expected in class_sizes {
		cursor = literal(cursor, 'size-')!
		identity, after_identity := natural(cursor)!
		cursor = literal(after_identity, ' ')!
		size, after_size := natural(cursor)!
		cursor = literal(after_size, ' ')!
		objects, after_objects := natural(cursor)!
		cursor = literal(after_objects, ' ')!
		pages, after_pages := natural(cursor)!
		cursor = literal(after_pages, '\n')!
		require(identity == expected && size == expected,
			'missing, duplicate, reordered or mismatching slab class')!
		unsafe { out.classes[index] = ClassSnapshot{size: size, objects: objects, pages: pages} }
	}
	cursor = literal(cursor, 'large - - ')!
	large_pages, after_large := natural(cursor)!
	cursor = literal(after_large, '\n# written after free ')!
	written_after_free, after_footer := natural(cursor)!
	cursor = literal(after_footer, '\n')!
	require(cursor.position == length, 'extra or trailing slab snapshot data')!
	unsafe {
		C.memmove(&out.raw[0], data, usize(length))
		out.raw_len = length
		out.large_pages = large_pages
		out.written_after_free = written_after_free
		out.valid = true
	}
}

// Internal borrowed-descriptor reader. A successful read always observes EOF;
// reaching capacity alone is not accepted. Tests use already-closed pipe writers.
fn read_from_fd(fd i32, out &Snapshot) ! {
	unsafe { out.valid = false; out.raw_len = 0 }
	mut used := 0
	for {
		if used == raw_capacity {
			mut extra := u8(0)
			amount := C.read(fd, unsafe { &extra }, 1)
			if amount < 0 {
				if C.errno == C.EINTR { continue }
				return error('slab EOF probe failed')
			}
			require(amount == 0, 'slab snapshot exceeds fixed storage')!
			break
		}
		amount := C.read(fd, unsafe { &out.raw[used] }, usize(raw_capacity - used))
		if amount < 0 {
			if C.errno == C.EINTR { continue }
			return error('slab snapshot read failed')
		}
		if amount == 0 { break }
		require(amount > 0 && amount <= raw_capacity - used, 'invalid slab read result')!
		used += int(amount)
	}
	parse_snapshot(unsafe { &out.raw[0] }, used, out)!
}

// Owns exactly the descriptor it opens. A failed close invalidates the snapshot;
// close is never retried, because an interrupted close may already retire the fd.
pub fn read_snapshot(path string, out &Snapshot) ! {
	unsafe { out.valid = false; out.raw_len = 0 }
	fd := C.open(path.str, C.O_RDONLY | C.O_CLOEXEC)
	require(fd >= 0, 'cannot open slab snapshot')!
	mut closed := false
	defer { if !closed { C.close(fd) } }
	read_from_fd(fd, out)!
	closed = true
	if C.close(fd) != 0 {
		unsafe { out.valid = false; out.raw_len = 0 }
		return error('slab snapshot close failed')
	}
}

fn difference(before u64, after u64) !i64 {
	if after >= before {
		amount := after - before
		require(amount <= u64(signed_max), 'positive slab delta exceeds signed storage')!
		return i64(amount)
	}
	amount := before - after
	require(amount <= u64(signed_max) + 1, 'negative slab delta exceeds signed storage')!
	return if amount == u64(signed_max) + 1 { signed_min } else { -i64(amount) }
}

fn scaled(value i64, factor i64) !i64 {
	require(factor > 0 && (value <= 0 || value <= signed_max / factor)
		&& (value >= 0 || value >= signed_min / factor), 'slab byte multiplication overflow')!
	return value * factor
}

fn sum(left i64, right i64) !i64 {
	require((right <= 0 || left <= signed_max - right)
		&& (right >= 0 || left >= signed_min - right), 'slab byte sum overflow')!
	return left + right
}

// Complete class identity is checked again rather than trusting a valid flag.
// Nonzero deltas are returned, including reclamation; the caller applies policy.
pub fn compare(before &Snapshot, after &Snapshot, out &Delta) ! {
	unsafe { out.valid = false }
	require(before.valid && after.valid && before.raw_len > 0 && after.raw_len > 0,
		'cannot compare an unadmitted slab snapshot')!
	mut bytes := i64(0)
	for index, expected in class_sizes {
		require(before.classes[index].size == expected && after.classes[index].size == expected,
			'compared slab class identity differs')!
		objects := difference(before.classes[index].objects, after.classes[index].objects)!
		pages := difference(before.classes[index].pages, after.classes[index].pages)!
		bytes = sum(bytes, scaled(objects, i64(expected))!)!
		unsafe { out.classes[index] = ClassDelta{size: expected, objects: objects, pages: pages} }
	}
	large_pages := difference(before.large_pages, after.large_pages)!
	bytes = sum(bytes, scaled(large_pages, page_size)!)!
	written_after_free := difference(before.written_after_free, after.written_after_free)!
	unsafe {
		out.large_pages = large_pages
		out.written_after_free = written_after_free
		out.bytes = bytes
		out.valid = true
	}
}

// Qualification policy is separate from observation: producers must retain
// nonflat and already-corrupt snapshots rather than stop collecting cohorts.
// A positive preexisting after-free counter can never be reported as clean.
pub fn qualify_flatness(before &Snapshot, after &Snapshot) ! {
	mut delta := Delta{}
	compare(before, after, unsafe { &delta })!
	require(before.written_after_free == 0 && after.written_after_free == 0,
		'written-after-free evidence prevents clean heap qualification')!
	for row in delta.classes {
		require(row.objects == 0 && row.pages == 0,
			'nonzero exact class object or backing-page delta')!
	}
	require(delta.large_pages == 0, 'nonzero exact large-allocation page delta')!
}
