// SPDX-License-Identifier: GPL-2.0-or-later
module slabreport

// Borrowed output for one synchronous read. Skip/count are kept separately so
// offsets and counts near UINT64_MAX cannot wrap an end-position calculation.
pub struct Writer {
mut:
	buffer &u8 = unsafe { nil }
	skip u64
	left u64
	written u64
}

pub fn writer(buffer voidptr, offset u64, count u64) Writer {
	return Writer{buffer: buffer, skip: offset, left: count}
}

pub fn (w &Writer) count() u64 {
	return w.written
}

fn (mut w Writer) byte(value u8) {
	if w.skip != 0 {
		w.skip--
	} else if w.left != 0 {
		unsafe { w.buffer[w.written] = value }
		w.written++
		w.left--
	}
}

fn (mut w Writer) text(value string) {
	for i in 0 .. value.len { w.byte(value[i]) }
}

fn (mut w Writer) unsigned(value u64) {
	mut digits := [20]u8{}
	mut rest := value
	mut n := 0
	for {
		digits[n] = u8(`0` + rest % 10)
		n++
		rest /= 10
		if rest == 0 { break }
	}
	for n > 0 {
		n--
		w.byte(digits[n])
	}
}

pub fn (mut w Writer) header() {
	w.text('# class      size    objects   pages\n')
}

pub fn (mut w Writer) class(size u64, live u64, pages u64) {
	w.text('size-')
	w.unsigned(size)
	w.byte(` `)
	w.unsigned(size)
	w.byte(` `)
	w.unsigned(live)
	w.byte(` `)
	w.unsigned(pages)
	w.byte(`\n`)
}

pub fn (mut w Writer) footer(large u64, written_after_free u64) {
	w.text('large - - ')
	w.unsigned(large)
	w.text('\n# written after free ')
	w.unsigned(written_after_free)
	w.byte(`\n`)
}
