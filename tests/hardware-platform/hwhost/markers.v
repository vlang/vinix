// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// Serial output as lines, and the markers looked for in them.
//
// The serial log is what the firmware, the boot loader, the kernel and the
// guest all write to, so it arrives with cursor movements and carriage
// returns in it and in pieces that end anywhere. A marker is only looked for
// in a whole line with those removed: half a line read between two polls must
// not match, and neither must a marker the terminal codes happen to split.
module hwhost

// Removes what a terminal would act on instead of show: escape sequences,
// carriage returns and the other control bytes. A tab is kept.
pub fn clean_line(raw string) string {
	mut out := []u8{cap: raw.len}
	mut i := 0
	for i < raw.len {
		c := raw[i]
		if c != 0x1b {
			if c == `\t` || (c >= 0x20 && c != 0x7f) {
				out << c
			}
			i++
			continue
		}
		i++
		if i >= raw.len {
			break
		}
		if raw[i] == `[` {
			// A control sequence: parameters and intermediates, then one
			// final byte in @..~. OVMF's `ESC [ = 3 h` has `=` as a parameter.
			i++
			for i < raw.len && raw[i] >= 0x20 && raw[i] <= 0x3f {
				i++
			}
			if i < raw.len && raw[i] >= 0x40 && raw[i] <= 0x7e {
				i++
			}
		} else if raw[i] == `]` {
			// An operating system command runs to BEL or to ESC \.
			i++
			for i < raw.len && raw[i] != 0x07 && raw[i] != 0x1b {
				i++
			}
			if i < raw.len && raw[i] == 0x1b {
				i++
			}
			if i < raw.len {
				i++
			}
		} else {
			// The two-byte escapes, such as ESC c.
			i++
		}
	}
	return out.bytestr()
}

// Bytes in, whole lines out. What follows the last newline waits for the
// rest of its line.
pub struct LineSplitter {
mut:
	pending []u8
}

pub fn (mut s LineSplitter) feed(data []u8) []string {
	mut lines := []string{}
	for c in data {
		if c == `\n` {
			lines << s.pending.bytestr()
			s.pending.clear()
		} else {
			s.pending << c
		}
	}
	return lines
}

// The unfinished last line, once nothing more will be written.
pub fn (mut s LineSplitter) rest() ?string {
	if s.pending.len == 0 {
		return none
	}
	line := s.pending.bytestr()
	s.pending.clear()
	return line
}

// The serial port of one boot.
pub struct SerialLines {
mut:
	splitter LineSplitter
pub mut:
	lines []string // every whole line so far, cleaned
}

// Returns the lines these bytes completed.
pub fn (mut s SerialLines) feed(data []u8) []string {
	mut fresh := []string{}
	for raw in s.splitter.feed(data) {
		fresh << clean_line(raw)
	}
	s.lines << fresh
	return fresh
}

// The machine is gone: what it wrote last without ending the line is as
// whole as it will get.
pub fn (mut s SerialLines) finish() []string {
	raw := s.splitter.rest() or { return []string{} }
	line := clean_line(raw)
	s.lines << line
	return [line]
}

pub fn (s &SerialLines) tail(count int) []string {
	if s.lines.len <= count {
		return s.lines
	}
	return s.lines[s.lines.len - count..]
}

// Which required markers have appeared, and the first forbidden one.
pub struct MarkerWatch {
pub:
	required  []string
	forbidden []string
mut:
	seen []bool
pub mut:
	forbidden_marker string // the first forbidden marker seen
	forbidden_line   string // and the line it was on
}

pub fn new_marker_watch(required []string, forbidden []string) MarkerWatch {
	return MarkerWatch{
		required:  required
		forbidden: forbidden
		seen:      []bool{len: required.len}
	}
}

pub fn (mut w MarkerWatch) line(line string) {
	for index, marker in w.required {
		if !w.seen[index] && line.contains(marker) {
			w.seen[index] = true
		}
	}
	if w.forbidden_marker != '' {
		return
	}
	for marker in w.forbidden {
		if line.contains(marker) {
			w.forbidden_marker = marker
			w.forbidden_line = line
			return
		}
	}
}

pub fn (w &MarkerWatch) missing() []string {
	mut missing := []string{}
	for index, marker in w.required {
		if !w.seen[index] {
			missing << marker
		}
	}
	return missing
}

pub fn (w &MarkerWatch) complete() bool {
	return w.missing().len == 0
}

pub fn (w &MarkerWatch) failed() bool {
	return w.forbidden_marker != ''
}

// Where the host is in a scenario's list of actions.
//
// An action becomes due when its marker is seen on a line printed after the
// one that triggered the action before it, and its delay has passed. Time is
// passed in rather than read, so the order of events can be tested.
pub struct ActionCursor {
pub:
	actions []Action
mut:
	next      int  // the action waiting for its marker, or being delayed
	triggered bool // its marker has been seen
	due_at    i64  // when to send it, in the caller's milliseconds
	held      []HeldLine
}

// A line printed while an action was being delayed. It belongs to the action
// after, which is not being looked for yet.
struct HeldLine {
	text string
	at   i64
}

pub fn new_action_cursor(actions []Action) ActionCursor {
	return ActionCursor{
		actions: actions
	}
}

// A line was printed at `now_ms`. A line that triggers an action is used up:
// it cannot also trigger the next one.
pub fn (mut c ActionCursor) line(line string, now_ms i64) {
	if c.next >= c.actions.len {
		return
	}
	if c.triggered {
		c.held << HeldLine{
			text: line
			at:   now_ms
		}
		return
	}
	action := c.actions[c.next]
	if line.contains(action.after) {
		c.triggered = true
		c.due_at = now_ms + action.delay_ms
	}
}

// The action to perform now, if one is due. Each is returned once.
pub fn (mut c ActionCursor) take_due(now_ms i64) ?Action {
	if c.next >= c.actions.len || !c.triggered || now_ms < c.due_at {
		return none
	}
	action := c.actions[c.next]
	c.next++
	c.triggered = false
	held := c.held.clone()
	c.held.clear()
	for line in held {
		c.line(line.text, line.at)
	}
	return action
}

pub fn (c &ActionCursor) done() bool {
	return c.next >= c.actions.len
}

// The marker the next action is still waiting for, for the failure report.
pub fn (c &ActionCursor) waiting_for() string {
	if c.next >= c.actions.len || c.triggered {
		return ''
	}
	return c.actions[c.next].after
}
