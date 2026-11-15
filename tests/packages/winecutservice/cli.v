// SPDX-License-Identifier: GPL-2.0-or-later
module winecutservice

import json2
import os
import tools.packages.wineadapter
import tests.packages.winecutfixture

fn C.execv(&char, &&char) i32

struct CliReview {
	format int
	generation u64
	prior_generation u64
	runtime_id string
	bindings []wineadapter.BuiltinBinding
}

pub fn exec_cut(data string, point int) ! {
	os.write_file('/tmp/wine-cli-cut', point.str())!
	args := ['/usr/bin/vinix-package', 'wine-prefix-migrate', 'app', data]
	mut pointers := []&char{cap: args.len + 1}
	for arg in args { pointers << arg.str }
	pointers << &char(unsafe { nil })
	C.execv(args[0].str, pointers.data)
	return error('cannot exec public migration CLI')
}

pub fn reply(command string, data string) ! {
	names := winecutfixture.names($if wine_cut_scaled ? { true } $else { false })
	mut child := os.new_process('/usr/bin/vinix-package')
	defer { child.close() }
	child.set_args([command, 'app', data]); child.set_redirect_stdio_merged(); child.run()
	output := child.stdout_slurp()
	defer { unsafe { output.free() } }
	child.wait()
	if child.code != 0 { return error('public recovery command failed: ' + command + ': ' + output) }
	report := json2.decode[CliReview](output)!
	defer {
		unsafe {
			for row in report.bindings { row.name.free(); row.observed.free(); row.replacement.free() }
			report.runtime_id.free(); (&array(&report.bindings)).free()
		}
	}
	if report.format != 1 || report.generation != 2 || report.prior_generation != 0 || report.runtime_id != 'wine'
		|| report.bindings.len != names.len || !report.bindings.all(it.operation == .keep) { return error('public recovery JSON inventory differs') }
	for index, name in names {
		expected := '/var/lib/vinix-packages/generations/2/apps/wine/root/usr/lib/wine/x86_64-windows/' + name
		if report.bindings[index].name != name || report.bindings[index].observed != expected
			|| report.bindings[index].replacement != expected { return error('public recovery JSON target differs') }
	}
	println('WINE CLI JSON command=${command} ' + output.trim_space())
}
