// SPDX-License-Identifier: GPL-2.0-or-later
module sessioncore

pub struct Binding {
pub mut:
	key    Text
	action Text
}

pub struct Policy {
pub mut:
	bindings          [64]Binding
	count             int
	corners           [4]Text
	gestures          bool = true
	clipboard_history bool = true
	clipboard_apps    bool = true
	allow_capture     bool = true
	timezone_minutes  int
	timezone          Text
}

pub fn (mut p Policy) bind(key string, action string) ! {
	if key.len < 2 || key.len > 32 || key[0] != 27 || !identifier(action) {
		return error('invalid shortcut')
	}
	mut index := p.count
	for i in 0 .. p.count {
		if p.bindings[i].action.str() == action {
			index = i
		} else if p.bindings[i].key.str() == key {
			return error('shortcut already assigned')
		}
	}
	if index == p.bindings.len { return error('too many shortcuts') }
	p.bindings[index] = Binding{ key: text(key)!, action: text(action)! }
	if index == p.count { p.count++ }
}

pub fn (p &Policy) encode() string {
	mut w := &Writer{}
	defer { unsafe { free(w) } }
	w.add('vinix-shell-policy\t2')
	for value in [int(p.gestures), int(p.clipboard_history), int(p.clipboard_apps),
		int(p.allow_capture), p.timezone_minutes]! {
		w.add('\t')
		w.number(value)
	}
	w.add('\t')
	w.field(p.timezone.str())
	w.add('\n')
	for i in 0 .. p.count {
		w.add('key\t')
		w.field(p.bindings[i].key.str())
		w.add('\t')
		w.field(p.bindings[i].action.str())
		w.add('\n')
	}
	for i in 0 .. 4 {
		w.add('corner\t')
		w.number(i)
		w.add('\t')
		w.field(p.corners[i].str())
		w.add('\n')
	}
	return w.finish()
}

pub fn decode_policy(record string) !Policy {
	// bind() borrows inline records. Release the parser's explicit scratch
	// allocation after the snapshot is copied into the result.
	mut p := &Policy{}
	defer { unsafe { free(p) } }
	mut start := 0
	mut header := false
	mut corners := u8(0)
	for end in 0 .. record.len + 1 {
		if end < record.len && record[end] != `\n` { continue }
		if end == start {
			start = end + 1
			continue
		}
		f := fields(unsafe { tos(record.str + start, end - start) })!
		start = end + 1
		if !header {
			if f.values[0] != 'vinix-shell-policy' || (f.values[1] == '1' && f.count != 7) || (f.values[1] == '2' && f.count != 8) || f.values[1] !in [
				'1',
				'2',
			] {
				return error('invalid shell policy')
			}
			p.gestures = number(f.values[2], 0, 1)! == 1
			p.clipboard_history = number(f.values[3], 0, 1)! == 1
			p.clipboard_apps = number(f.values[4], 0, 1)! == 1
			p.allow_capture = number(f.values[5], 0, 1)! == 1
			p.timezone_minutes = int(number(f.values[6], -720, 840)!)
			if f.count == 8 {
				p.timezone = unfield(f.values[7])!
				if p.timezone.len > 0 && !timezone_name(p.timezone.str()) {
					return error('invalid timezone name')
				}
			}
			header = true
		} else if f.values[0] == 'key' && f.count == 3 {
			if p.count == p.bindings.len { return error('too many shortcuts') }
			p.bindings[p.count] = Binding{ key: unfield(f.values[1])!, action: unfield(f.values[2])! }
			binding := unsafe { &p.bindings[p.count] }
			for i in 0 .. p.count {
				if p.bindings[i].action == binding.action { return error('duplicate shortcut action') }
			}
			p.bind(binding.key.str(), binding.action.str())!
		} else if f.values[0] == 'corner' && f.count == 3 {
			i := int(number(f.values[1], 0, 3)!)
			if corners & (u8(1) << i) != 0 { return error('duplicate hot corner') }
			p.corners[i] = unfield(f.values[2])!
			if p.corners[i].len > 0 && !identifier(p.corners[i].str()) {
				return error('invalid hot corner action')
			}
			corners |= u8(1) << i
		} else {
			return error('invalid shell policy entry')
		}
	}
	if !header || corners != 15 { return error('incomplete shell policy') }
	return *p
}

pub fn timezone_name(name string) bool {
	if name.len == 0 || name.len > 128 || name.starts_with('/') || name.contains('..') || name.ends_with('/') {
		return false
	}
	for byte in name {
		if !byte.is_letter() && !byte.is_digit() && byte !in [`/`, `_`, `-`, `+`] { return false }
	}
	return true
}
