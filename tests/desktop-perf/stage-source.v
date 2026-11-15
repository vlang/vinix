// SPDX-License-Identifier: GPL-2.0-or-later
module main

import json2
import os
import perfsources

fn run() ! {
	if os.args.len == 3 && os.args[1] == 'selfcheck' {
		perfsources.selfcheck(os.abs_path(os.args[2]))!; return
	}
	if os.args.len == 3 && os.args[1] == 'verify' {
		receipt := json2.decode[perfsources.Receipt](os.read_file(os.args[2])!)!
		if receipt.selected != perfsources.seeds { return error('fixed adapter source selection required') }
		perfsources.verify(receipt)!
		println('PERF SOURCE snapshot verification PASS'); return
	}
	if os.args.len != 5 || os.args[1] != 'stage' {
		return error('usage: stage-source selfcheck FRESH-STATE | stage SOURCE FRESH-DEST FRESH-RECEIPT | verify RECEIPT')
	}
	source := os.real_path(os.args[2])
	destination := os.abs_path(os.args[3])
	receipt_path := os.abs_path(os.args[4])
	if os.exists(receipt_path) || os.is_link(receipt_path) { return error('fresh source receipt required') }
	receipt := perfsources.stage(source, destination, perfsources.seeds)!
	perfsources.save(receipt, receipt_path)!
	println('PERF SOURCE snapshot PASS ' + receipt.entries.len.str() + ' typed entries')
}

fn main() { run() or { eprintln(err); exit(1) } }
