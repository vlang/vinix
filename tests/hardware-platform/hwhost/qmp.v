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

// Which events a machine has sent, and how often: what a scenario that names
// events it must have seen is judged by.
pub struct EventLog {
mut:
	names  []string
	counts []int
}

pub fn (mut log EventLog) note(event string) {
	if event == '' {
		return
	}
	for i, name in log.names {
		if name == event {
			log.counts[i]++
			return
		}
	}
	log.names << event
	log.counts << 1
}

// How many times the event arrived.
pub fn (log &EventLog) count(event string) int {
	for i, name in log.names {
		if name == event {
			return log.counts[i]
		}
	}
	return 0
}

// The events of `wanted` that did not arrive as often as it lists them: an
// event named twice must have arrived twice.
pub fn (log &EventLog) missing(wanted []string) []string {
	mut missing := []string{}
	for event in wanted {
		if event in missing {
			continue
		}
		if log.count(event) < wanted.filter(it == event).len {
			missing << event
		}
	}
	return missing
}
