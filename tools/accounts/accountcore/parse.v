// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// The text of passwd, group and shadow. Parsing is strict: a line these
// functions do not understand fails the whole file, since guessing at an
// account record is how a malformed line becomes a second root.
module accountcore

fn parse_id(text string) !u32 {
	if text.len == 0 || text.len > 10 {
		return error('invalid number')
	}
	mut value := u64(0)
	for i in 0 .. text.len {
		ch := text[i]
		if ch < `0` || ch > `9` {
			return error('invalid number')
		}
		value = value * 10 + u64(ch - `0`)
	}
	// A leading zero is another spelling of the same id: refuse it, so that
	// two lines cannot name one id differently.
	if text.len > 1 && text[0] == `0` {
		return error('invalid number')
	}
	if value > u64(0xfffffffe) {
		return error('number out of range')
	}
	return u32(value)
}

// The lines of a file: no NUL, no carriage return, nothing after the last
// line break, and every line within max_line.
fn file_lines(text string) ![]string {
	if text.len > max_file {
		return error('file too large')
	}
	if text.len == 0 {
		return []string{}
	}
	if text[text.len - 1] != `\n` {
		return error('last line is not terminated')
	}
	mut lines := []string{}
	mut start := 0
	for i in 0 .. text.len {
		ch := text[i]
		if ch == 0 || ch == `\r` {
			return error('line ${lines.len + 1}: control character')
		}
		if ch == `\n` {
			if i - start > max_line {
				return error('line ${lines.len + 1}: too long')
			}
			lines << text[start..i]
			start = i + 1
			if lines.len > max_entries {
				return error('too many lines')
			}
		}
	}
	return lines
}

pub fn parse_passwd(text string) ![]User {
	mut users := []User{}
	for index, line in file_lines(text)! {
		fields := line.split(':')
		if fields.len != 7 {
			return error('passwd line ${index + 1}: expected 7 fields')
		}
		uid := parse_id(fields[2]) or { return error('passwd line ${index + 1}: invalid uid') }
		gid := parse_id(fields[3]) or { return error('passwd line ${index + 1}: invalid gid') }
		// The second field once held the password. Anything but the marker
		// that says "look in shadow" would be a password these tools never
		// check, so it is not accepted.
		if fields[1] != 'x' {
			return error('passwd line ${index + 1}: password field must be x')
		}
		users << User{
			name:  fields[0]
			uid:   uid
			gid:   gid
			gecos: fields[4]
			home:  fields[5]
			shell: fields[6]
		}
	}
	return users
}

pub fn format_passwd(users []User) string {
	mut out := []string{cap: users.len + 1}
	for user in users {
		out << '${user.name}:x:${user.uid}:${user.gid}:${user.gecos}:${user.home}:${user.shell}'
	}
	out << ''
	return out.join('\n')
}

pub fn parse_group(text string) ![]Group {
	mut groups := []Group{}
	for index, line in file_lines(text)! {
		fields := line.split(':')
		if fields.len != 4 {
			return error('group line ${index + 1}: expected 4 fields')
		}
		gid := parse_id(fields[2]) or { return error('group line ${index + 1}: invalid gid') }
		mut members := []string{}
		if fields[3] != '' {
			members = fields[3].split(',')
		}
		groups << Group{
			name:    fields[0]
			gid:     gid
			members: members
		}
	}
	return groups
}

pub fn format_group(groups []Group) string {
	mut out := []string{cap: groups.len + 1}
	for group in groups {
		out << '${group.name}:x:${group.gid}:${group.members.join(',')}'
	}
	out << ''
	return out.join('\n')
}

pub fn parse_shadow(text string) ![]Shadow {
	mut shadows := []Shadow{}
	for index, line in file_lines(text)! {
		fields := line.split(':')
		if fields.len != 9 {
			return error('shadow line ${index + 1}: expected 9 fields')
		}
		shadows << Shadow{
			name:    fields[0]
			hash:    fields[1]
			changed: fields[2]
			ageing:  fields[3..9].clone()
		}
	}
	return shadows
}

pub fn format_shadow(shadows []Shadow) string {
	mut out := []string{cap: shadows.len + 1}
	for shadow in shadows {
		out << '${shadow.name}:${shadow.hash}:${shadow.changed}:${shadow.ageing.join(':')}'
	}
	out << ''
	return out.join('\n')
}
