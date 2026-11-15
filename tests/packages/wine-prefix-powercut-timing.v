// SPDX-License-Identifier: GPL-2.0-or-later
// Diagnostic only: guest monotonic deltas within each boot, not host deadlines.
module main

import os
import strconv

fn run() ! {
	if os.args.len < 2 { return error('usage: TIMING SERIAL_LOG...') }
	for path in os.args[1..] {
		mut previous := u64(0)
		mut point := ''
		mut found := false
		for line in os.read_lines(path)! {
			if !line.starts_with('WINE POWER CUT TIME ') { continue }
			fields := line.trim_space().split(' ')
			if fields.len != 7 || !fields[4].starts_with('point=') || !fields[5].starts_with('phase=') || !fields[6].starts_with('ns=') {
				return error('malformed timing marker in ' + path)
			}
			stamp := strconv.parse_uint(fields[6].all_after('ns='), 10, 64)!
			if !found {
				if fields[5] != 'phase=store-setup-begin' { return error('timing log must begin at store setup') }
				previous = stamp; point = fields[4]; found = true
			}
			if fields[4] != point || stamp < previous { return error('mixed cut points or non-monotonic timing log') }
			println('${path} ${point} ${fields[5]} delta-ms=${(stamp - previous) / 1_000_000}')
			previous = stamp
		}
		if !found { return error('no timing markers in ' + path) }
	}
}

fn main() { run() or { eprintln(err); exit(1) } }
