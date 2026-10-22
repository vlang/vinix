// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// The text of passwd, group and shadow. Parsing is strict: a line these
// functions do not understand fails the whole file, since guessing at an
// account record is how a malformed line becomes a second root.
module accountcore

fn line_error(source string, index int, detail string) IError {
	number := (index + 1).str()
	defer { unsafe { number.free() } }
	return error('${source} line ${number}: ${detail}')
}

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
	lines.flags |= .noslices
	mut complete := false
	defer { if !complete { unsafe { lines.free() } } }
	mut start := 0
	for i in 0 .. text.len {
		ch := text[i]
		if ch == 0 || ch == `\r` {
			return line_error('account', lines.len, 'control character')
		}
		if ch == `\n` {
			if i - start > max_line {
				return line_error('account', lines.len, 'too long')
			}
			lines << text[start..i]
			start = i + 1
			if lines.len > max_entries {
				return error('too many lines')
			}
		}
	}
	complete = true
	return lines
}

pub fn parse_passwd(text string) ![]User {
	mut users := []User{}
	users.flags |= .noslices
	mut complete := false
	defer { if !complete { close_users(mut users) } }
	lines := file_lines(text)!
	defer { unsafe { lines.free() } }
	for index, line in lines {
		fields := line.split(':')
		defer { unsafe { fields.free() } }
		if fields.len != 7 {
			return line_error('passwd', index, 'expected 7 fields')
		}
		uid := parse_id(fields[2]) or { unsafe { err.free() }; return line_error('passwd', index, 'invalid uid') }
		gid := parse_id(fields[3]) or { unsafe { err.free() }; return line_error('passwd', index, 'invalid gid') }
		// The second field once held the password. Anything but the marker
		// that says "look in shadow" would be a password these tools never
		// check, so it is not accepted.
		if fields[1] != 'x' {
			return line_error('passwd', index, 'password field must be x')
		}
		users << User{
			name:  fields[0].clone()
			uid:   uid
			gid:   gid
			gecos: fields[4].clone()
			home:  fields[5].clone()
			shell: fields[6].clone()
		}
	}
	complete = true
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
	groups.flags |= .noslices
	mut complete := false
	defer { if !complete { close_groups(mut groups) } }
	lines := file_lines(text)!
	defer { unsafe { lines.free() } }
	for index, line in lines {
		fields := line.split(':')
		defer { unsafe { fields.free() } }
		if fields.len != 4 {
			return line_error('group', index, 'expected 4 fields')
		}
		gid := parse_id(fields[2]) or { unsafe { err.free() }; return line_error('group', index, 'invalid gid') }
		// Group passwords are not a thing here: a field that held one would
		// be a credential nothing checks, and would be lost when the file
		// is next written.
		if fields[1] != 'x' {
			return line_error('group', index, 'password field must be x')
		}
		mut members := []string{}
		if fields[3] != '' {
			members = fields[3].split(',')
		}
		groups << Group{
			name:    fields[0].clone()
			gid:     gid
			members: members
		}
	}
	complete = true
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
	shadows.flags |= .noslices
	mut complete := false
	defer { if !complete { close_shadows(mut shadows) } }
	lines := file_lines(text)!
	defer { unsafe { lines.free() } }
	for index, line in lines {
		fields := line.split(':')
		defer { unsafe { fields.free() } }
		if fields.len != 9 {
			return line_error('shadow', index, 'expected 9 fields')
		}
		mut ageing := []string{cap: 6}
		for i in 3 .. 9 { ageing << fields[i].clone() }
		shadows << Shadow{
			name:    fields[0].clone()
			hash:    fields[1].clone()
			changed: fields[2].clone()
			ageing:  ageing
		}
	}
	complete = true
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
