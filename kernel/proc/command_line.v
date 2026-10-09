// SPDX-License-Identifier: GPL-2.0-or-later
module proc

import lib
import kbudget

// One owned, NUL-separated snapshot per image. Exec's temporary argv can be
// freed immediately; /proc readers never borrow it or a Process after unlock.
pub struct CommandLine {
pub:
	text   string
	charge kbudget.Charge
}

pub fn prepare_command_line(owner kbudget.Owner, argv []string) ?CommandLine {
	mut capacity := 0
	for argument in argv { capacity += argument.len + 1 }
	charge := reserve_kernel_for(owner, .process, u64(capacity) * 2 + 128)?
	// Keep the builder on the caller's stack under -manualfree.
	mut text := unsafe { &lib.Text(C.vinix_stack_alloc(sizeof(lib.Text))) }
	unsafe { *text = lib.new_text(capacity) }
	for argument in argv {
		text.add(argument)
		text.add_byte(0)
	}
	return CommandLine{ text: lib.finish_text(*text), charge: charge }
}

pub fn discard_command_line(command CommandLine) {
	unsafe { command.text.free() }
	kbudget.release(command.charge)
}

pub fn install_command_line(mut process Process, command CommandLine) {
	lock_table()
	unsafe { process.command_line.free() }
	kbudget.release(process.command_charge)
	process.command_line = command.text
	process.command_charge = command.charge
	unlock_table()
}

pub fn set_command_line(mut process Process, argv []string) ? {
	install_command_line(mut process, prepare_command_line(process.kernel_owner, argv)?)
}

pub fn process_command_line(pid int) string {
	lock_table()
	defer { unlock_table() }
	process := process_at(pid)
	if process == unsafe { nil } || !may_inspect_locked(process) { return '' }
	return process.command_line.clone()
}

pub fn inherit_command_line(mut child Process, parent &Process) ? {
	lock_table()
	charge := reserve_kernel_for(child.kernel_owner, .process, u64(parent.command_line.len) * 2 + 128) or {
		unlock_table()
		return none
	}
	command := parent.command_line.clone() @[freed]
	child.command_line = command
	child.command_charge = charge
	unlock_table()
}

pub fn clear_command_line(mut process Process) {
	lock_table()
	unsafe { process.command_line.free() }
	process.command_line = ''
	kbudget.release(process.command_charge)
	process.command_charge = kbudget.Charge{}
	unlock_table()
}
