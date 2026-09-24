module lib

// Text a kernel file makes afresh on every read, built in one byte buffer.
// Interpolating a value into a string leaves the value's own string behind in
// this kernel, `+=` the string it replaced, and an array that outgrows its
// buffer the old buffer: a /proc file read in a loop leaked with every read.
// The buffer here grows by moving to a bigger one and freeing the old, and
// str() hands its bytes over as one string.
pub struct Text {
mut:
	bytes []u8
}

pub fn new_text(capacity int) Text {
	return Text{
		bytes: []u8{cap: if capacity > 16 { capacity } else { 16 }}
	}
}

fn (mut t Text) reserve(extra int) {
	if t.bytes.len + extra <= t.bytes.cap {
		return
	}
	mut capacity := t.bytes.cap * 2
	if capacity < t.bytes.len + extra {
		capacity = t.bytes.len + extra
	}
	mut bigger := []u8{cap: capacity}
	for c in t.bytes {
		bigger << c
	}
	unsafe { t.bytes.free() }
	t.bytes = bigger
}

pub fn (mut t Text) add(s string) {
	t.reserve(s.len)
	for i in 0 .. s.len {
		t.bytes << s[i]
	}
}

pub fn (mut t Text) add_byte(c u8) {
	t.reserve(1)
	t.bytes << c
}

pub fn (mut t Text) add_unsigned(value u64) {
	mut digits := [20]u8{}
	mut n := 0
	mut rest := value
	for {
		digits[n] = u8(`0` + rest % 10)
		n++
		rest /= 10
		if rest == 0 {
			break
		}
	}
	t.reserve(n)
	for n > 0 {
		n--
		t.bytes << digits[n]
	}
}

pub fn (mut t Text) add_decimal(value i64) {
	if value < 0 {
		t.add_byte(`-`)
		t.add_unsigned(u64(-(value + 1)) + 1)
		return
	}
	t.add_unsigned(u64(value))
}

// `value` in base `base` (8 or 16), padded with zeros to `width` digits.
pub fn (mut t Text) add_radix(value u64, base u64, width int) {
	mut digits := [24]u8{}
	mut n := 0
	mut rest := value
	for {
		digit := rest % base
		digits[n] = if digit < 10 { u8(`0` + digit) } else { u8(`a` + digit - 10) }
		n++
		rest /= base
		if rest == 0 || n == digits.len {
			break
		}
	}
	for n < width && n < digits.len {
		digits[n] = `0`
		n++
	}
	t.reserve(n)
	for n > 0 {
		n--
		t.bytes << digits[n]
	}
}

// The text as one string. The buffer is gone afterwards.
pub fn (mut t Text) str() string {
	s := t.bytes.bytestr()
	unsafe { t.bytes.free() }
	t.bytes = []u8{}
	return s
}
