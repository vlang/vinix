// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct NSStringCompareCursor {
mut:
	raw CFStringCompareCursor
	folded []u32
	at int
}

fn (cursor &NSStringCompareCursor) unit() u32 {
	if cursor.at < cursor.folded.len { return cursor.folded[cursor.at] }
	mut raw := cursor.raw
	unit := raw.next()
	return if unit == 0x10000 { u32(0x110000) } else { unit }
}

fn (mut cursor NSStringCompareCursor) advance() {
	if cursor.at < cursor.folded.len { cursor.at++ }
	else { cursor.raw.next() }
}

fn ns_string_compare_scalar(mut raw CFStringCompareCursor) u32 {
	mut scalar := raw.next()
	if scalar == 0x10000 { return 0x110000 }
	if scalar >= 0xd800 && scalar <= 0xdbff {
		scalar = 0x10000 + ((scalar - 0xd800) << 10) + raw.next() - 0xdc00
	}
	return scalar
}

// Fold only a differing canonical cluster, then resume literal UTF-16 reads.
// This preserves Foundation's common-high-surrogate behavior even after an
// earlier pair of differently encoded clusters compared equal.
fn (mut cursor NSStringCompareCursor) fold() u32 {
	if cursor.at < cursor.folded.len { return cursor.folded[cursor.at] }
	cursor.folded.clear()
	cursor.at = 0
	swift_nfc_decompose(ns_string_compare_scalar(mut cursor.raw), mut cursor.folded)
	for {
		mut next := cursor.raw
		scalar := ns_string_compare_scalar(mut next)
		if scalar == 0x110000 || swift_grapheme_property(scalar) & 15 != 4 { break }
		swift_nfc_decompose(scalar, mut cursor.folded)
		cursor.raw = next
	}
	// Foundation priority-sorts the collected marks, including class-zero
	// extenders such as CGJ. NFC ordering deliberately keeps those barriers.
	mut counts := [256]int{}
	for scalar in cursor.folded { counts[swift_nfc_class(scalar)]++ }
	mut offset := 0
	for i in 0 .. 256 { count := counts[i]; counts[i] = offset; offset += count }
	mut ordered := []u32{len: cursor.folded.len}
	for scalar in cursor.folded {
		class := swift_nfc_class(scalar)
		ordered[counts[class]] = scalar
		counts[class]++
	}
	for i, scalar in ordered { cursor.folded[i] = scalar }
	unsafe { ordered.free() }
	return cursor.folded[0]
}

// compare: is case-sensitive and nonnumeric. Its canonical suffix comparison
// differs from the literal UTF-16 CF comparison profile.
fn ns_string_compare(left u64, right u64) !i64 {
	if ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired { return cf_string_compare_failure() }
	C.ios_objc_initialize_lock()
	a := cf_string_compare_text(left) or {
		C.ios_objc_initialize_unlock()
		return err
	}
	b := cf_string_compare_text(right) or {
		C.ios_objc_initialize_unlock()
		return err
	}
	mut ascii := true
	for byte in a { if byte >= 128 { ascii = false; break } }
	if ascii { for byte in b { if byte >= 128 { ascii = false; break } } }
	if ascii {
		defer { C.ios_objc_initialize_unlock() }
		count := if a.len < b.len { a.len } else { b.len }
		order := if count == 0 { 0 } else { C.memcmp(a.str, b.str, usize(count)) }
		if order != 0 { return if order < 0 { i64(-1) } else { i64(1) } }
		return if a.len == b.len { i64(0) } else if a.len < b.len { i64(-1) } else { i64(1) }
	}
	// Mutable arguments must be snapshotted together. No borrowed bytes escape
	// the lock and no application callbacks run while normalization is active.
	first := a.clone()
	second := b.clone()
	C.ios_objc_initialize_unlock()
	defer { unsafe { first.free(); second.free() } }
	mut x := NSStringCompareCursor{raw: CFStringCompareCursor{text: first}, folded: []u32{cap: 8}}
	mut y := NSStringCompareCursor{raw: CFStringCompareCursor{text: second}, folded: []u32{cap: 8}}
	x.folded.flags |= .noslices
	y.folded.flags |= .noslices
	defer { unsafe { x.folded.free(); y.folded.free() } }
	for {
		a_unit := x.unit(); b_unit := y.unit()
		if a_unit == 0x110000 { return if b_unit == 0x110000 { i64(0) } else { i64(-1) } }
		if b_unit == 0x110000 { return i64(1) }
		if a_unit != b_unit {
			a_scalar := x.fold(); b_scalar := y.fold()
			if a_scalar != b_scalar { return if a_scalar < b_scalar { i64(-1) } else { i64(1) } }
		}
		x.advance(); y.advance()
	}
	return i64(0)
}
