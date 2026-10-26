// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import strconv

fn number(line string, key string) !u64 {
	if !line.contains(key + '=0x') { return error('missing ' + key) }
	return strconv.parse_uint(line.all_after(key + '=0x').all_before(' ').trim_space(), 16, 64)
}

fn run() ! {
	if os.args.len != 2 { return error('usage: verify KNOWN_FAULT_LOG') }
	text := os.read_file(os.args[1])!.replace('\r\n', '\n')
	expected := text.split_into_lines().filter(it.starts_with('X11-KNOWN-FAULT-EXPECTED '))
	fault := text.split_into_lines().filter(it.starts_with('X11-FAULT '))
	registers := text.split_into_lines().filter(it.starts_with('X11-REGS '))
	if expected.len != 1 || fault.len != 1 || registers.len != 1 { return error('one complete controlled fault required') }
	if number(expected[0], 'address')! == 0 || number(fault[0], 'address')! != number(expected[0], 'address')!
		|| number(fault[0], 'signal')! != 11 || number(fault[0], 'code')! != 2
		|| number(fault[0], 'pc')! == 0 || number(fault[0], 'sp')! == 0 {
		return error('controlled signal context mismatch')
	}
	for i in 0 .. 31 { _ := number(registers[0], 'x${i:02}')! }
	if number(registers[0], 'x30')! == 0 { return error('missing link register') }
	for marker in ['X11-KNOWN-FAULT-CHAINED\n', 'X11-MAPS-BEGIN\n', 'X11-MAPS-END\n',
		'X11-KNOWN-FAULT-PASS query=preserved restoration=preserved chain=preserved\n'] {
		if !text.contains(marker) { return error('missing ' + marker.trim_space()) }
	}
	println('X11-FAULT-VERIFY-PASS native fault address, PC, SP, LR, 31 registers, chaining and restoration')
}

run() or { eprintln(err); exit(1) }
