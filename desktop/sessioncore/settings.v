// SPDX-License-Identifier: GPL-2.0-or-later
module sessioncore

pub struct Control {
pub mut:
	action  Text
	label   Text
	enabled bool
	checked bool
}

pub struct SettingsStatus {
pub mut:
	lines         [8]Text
	count         int
	controls      [8]Control
	control_count int
}

pub fn (mut s SettingsStatus) line(value string) {
	if s.count == s.lines.len { return }
	s.lines[s.count].set(value) or { return }
	s.count++
}

pub fn (mut s SettingsStatus) control(action string, label string, enabled bool, checked bool) {
	if s.control_count == s.controls.len { return }
	s.controls[s.control_count] = Control{ action: text(action) or { return }, label: text(label) or { return }, enabled: enabled, checked: checked }
	s.control_count++
}

pub fn (s &SettingsStatus) encode() string {
	mut w := Writer{}
	w.add('vinix-settings-status\t1\n')
	for i in 0 .. s.count {
		w.add('line\t')
		w.field(s.lines[i].str())
		w.add('\n')
	}
	for i in 0 .. s.control_count {
		c := s.controls[i]
		w.add('control\t')
		w.field(c.action.str())
		w.add('\t')
		w.field(c.label.str())
		w.add('\t')
		w.number(int(c.enabled))
		w.add('\t')
		w.number(int(c.checked))
		w.add('\n')
	}
	return w.finish()
}

pub fn decode_settings_status(record string) !SettingsStatus {
	mut s := SettingsStatus{}
	mut header := false
	mut start := 0
	for end in 0 .. record.len + 1 {
		if end < record.len && record[end] != `\n` { continue }
		if end == start {
			start = end + 1
			continue
		}
		f := fields(unsafe { tos(&record.str[start], end - start) })!
		start = end + 1
		if !header {
			if f.count != 2 || f.values[0] != 'vinix-settings-status' || f.values[1] != '1' {
				return error('invalid settings status')
			}
			header = true
		} else if f.count == 2 && f.values[0] == 'line' && s.count < 8 {
			s.lines[s.count] = unfield(f.values[1])!
			s.count++
		} else if f.count == 5 && f.values[0] == 'control' && s.control_count < 8 {
			s.controls[s.control_count] = Control{ action: unfield(f.values[1])!, label: unfield(f.values[2])!, enabled: number(f.values[3], 0, 1)! == 1, checked: number(f.values[4], 0, 1)! == 1 }
			s.control_count++
		} else {
			return error('invalid settings status entry')
		}
	}
	if !header { return error('missing settings header') }
	return s
}
