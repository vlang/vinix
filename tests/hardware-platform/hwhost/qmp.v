// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// The QEMU Machine Protocol as text: what goes on the wire for a command and
// what a line that comes back means.
//
// QMP is one JSON object per line in each direction. QEMU greets, the client
// answers with qmp_capabilities, and from then on each command gets one line
// with "return" or "error" -- with lines carrying "event" arriving in between
// whenever the machine does something. The socket itself is in qmp_client.v;
// this half reads no socket, so it is what the unit tests cover.
module hwhost

import x.json2

// The line to send for a command given as JSON text. A scenario's command is
// written by hand, so it is checked here rather than left for QEMU to answer
// with a parse error, or with nothing at all for half a line.
pub fn qmp_frame(command string) !string {
	text := command.replace_each(['\r', ' ', '\n', ' ']).trim_space()
	value := json2.decode[json2.Any](text) or {
		return error('QMP command is not JSON: ${command}')
	}
	if value !is map[string]json2.Any {
		return error('QMP command is not a JSON object: ${command}')
	}
	fields := value.as_map()
	name := fields['execute'] or { return error('QMP command has no "execute": ${command}') }
	if name !is string || name.str() == '' {
		return error('QMP command has no "execute" name: ${command}')
	}
	return text + '\n'
}

pub enum QmpKind {
	greeting // the first line QEMU sends
	reply    // "return": the command was carried out
	failure  // "error": it was not
	event    // something happened in the machine
	unknown
}

pub struct QmpMessage {
pub:
	kind   QmpKind
	text   string // the line as received
	event  string // the event's name
	reason string // for SHUTDOWN: who ended the machine
	detail string // for a failure: QEMU's description
}

pub fn qmp_parse(line string) QmpMessage {
	text := line.trim_space()
	value := json2.decode[json2.Any](text) or {
		return QmpMessage{
			kind: .unknown
			text: text
		}
	}
	if value !is map[string]json2.Any {
		return QmpMessage{
			kind: .unknown
			text: text
		}
	}
	fields := value.as_map()
	if 'QMP' in fields {
		return QmpMessage{
			kind: .greeting
			text: text
		}
	}
	if 'return' in fields {
		return QmpMessage{
			kind: .reply
			text: text
		}
	}
	if failure := fields['error'] {
		mut detail := ''
		if failure is map[string]json2.Any {
			if description := failure.as_map()['desc'] {
				detail = description.str()
			}
		}
		return QmpMessage{
			kind:   .failure
			text:   text
			detail: detail
		}
	}
	if name := fields['event'] {
		mut reason := ''
		if data := fields['data'] {
			if data is map[string]json2.Any {
				if value_reason := data.as_map()['reason'] {
					reason = value_reason.str()
				}
			}
		}
		return QmpMessage{
			kind:   .event
			text:   text
			event:  name.str()
			reason: reason
		}
	}
	return QmpMessage{
		kind: .unknown
		text: text
	}
}

// Replaces `{state}` in a QEMU argument or a QMP command. Anything else in
// braces that looks like a placeholder is a mistake in the scenario table,
// and is reported instead of being handed to QEMU as a file name.
pub fn substitute(text string, state string) !string {
	replaced := text.replace('{state}', state)
	mut i := 0
	for i < replaced.len {
		if replaced[i] != `{` {
			i++
			continue
		}
		mut end := i + 1
		for end < replaced.len && (replaced[end].is_letter() || replaced[end] == `_`) {
			end++
		}
		if end > i + 1 && end < replaced.len && replaced[end] == `}` {
			return error('unknown placeholder ${replaced[i..end + 1]} in "${text}"')
		}
		i++
	}
	return replaced
}

pub fn substitute_all(arguments []string, state string) ![]string {
	mut out := []string{cap: arguments.len}
	for argument in arguments {
		out << substitute(argument, state)!
	}
	return out
}

// A state directory ends up inside QEMU options, where a comma separates
// fields, and inside QMP JSON. Rather than quote it three ways, refuse the
// few characters that would need it.
pub fn check_state_path(path string) ! {
	for c in path {
		if c in [`,`, `"`, `\\`, `{`, `}`] || c < 0x20 {
			return error('the state directory path may not contain , " \\ { } or control characters: ${path}')
		}
	}
}
