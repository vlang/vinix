// SPDX-License-Identifier: GPL-2.0-or-later
module proc

import lib

// One owned, NUL-separated snapshot per image. Exec's temporary argv can be
// freed immediately; /proc readers never borrow it or a Process after unlock.
pub fn set_command_line(mut process Process, argv []string) {
	mut capacity := 0
	for argument in argv { capacity += argument.len + 1 }
	mut text := lib.new_text(capacity)
	for argument in argv {
		text.add(argument)
		text.add_byte(0)
	}
	command := lib.finish_text(text) @[freed]
	lock_table()
	unsafe { process.command_line.free() }
	process.command_line = command
	unlock_table()
}

pub fn process_command_line(pid int) string {
	lock_table()
	defer { unlock_table() }
	process := process_at(pid)
	if process == unsafe { nil } || !may_inspect_locked(process) { return '' }
	return process.command_line.clone()
}

pub fn inherit_command_line(mut child Process, parent &Process) {
	lock_table()
	command := parent.command_line.clone() @[freed]
	child.command_line = command
	unlock_table()
}

pub fn clear_command_line(mut process Process) {
	lock_table()
	unsafe { process.command_line.free() }
	process.command_line = ''
	unlock_table()
}
