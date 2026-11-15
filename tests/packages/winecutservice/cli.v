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
	runtime_version string
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
	checked_reply(command, data, names.len - 1, true)!
}

fn checked_reply(command string, data string, replaced int, added bool) ! {
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
			report.runtime_id.free(); report.runtime_version.free(); (&array(&report.bindings)).free()
		}
	}
	prior := if replaced < names.len - 1 { u64(1) } else { u64(0) }
	if report.format != 1 || report.generation != 2 || report.prior_generation != prior || report.runtime_id != 'wine'
		|| report.runtime_version != '2.0.0' || report.bindings.len != names.len
		{ return error('public recovery JSON inventory differs') }
	for index, name in names {
		expected := '/var/lib/vinix-packages/generations/2/apps/wine/root/usr/lib/wine/x86_64-windows/' + name
		operation := if index == names.len - 1 && !added { wineadapter.BindingOperation.create }
			else if index < names.len - 1 && index >= replaced { wineadapter.BindingOperation.replace }
			else { wineadapter.BindingOperation.keep }
		observed := if operation == .create { '' } else if operation == .replace {
			'/var/lib/vinix-packages/generations/1/apps/wine/root/usr/lib/wine/x86_64-windows/' + name
		} else { expected }
		if report.bindings[index].operation != operation || report.bindings[index].name != name || report.bindings[index].observed != observed
			|| report.bindings[index].replacement != expected { return error('public recovery JSON target differs') }
	}
	println('WINE CLI JSON command=${command} ' + output.trim_space())
}

// Inspect through the public API before any repair. Additions must refuse while
// old-generation bindings remain, including when a durable stage is present.
pub fn preview(data string, point int) ! {
	names := winecutfixture.names($if wine_cut_scaled ? { true } $else { false })
	boundary := winecutfixture.boundary(point, names.len - 1)!
	checked_reply('wine-prefix-review', data, boundary.replaced, boundary.added)!
	check_unchanged(data, point, names, boundary)!
	if boundary.replaced < names.len - 1 {
		mut child := os.new_process('/usr/bin/vinix-package')
		defer { child.close() }
		child.set_args(['wine-prefix-additions', 'app', data])
		child.set_redirect_stdio_merged(); child.run()
		output := child.stdout_slurp()
		defer { unsafe { output.free() } }
		child.wait()
		if child.code == 0 || !output.contains('all existing links') {
			return error('public additions did not refuse interrupted replacements: ' + output)
		}
		check_unchanged(data, point, names, boundary)!
		println('WINE CLI ADDITIONS REFUSED point=${point} prefix-unchanged')
	}
	println('WINE CLI PREVIEW PASS point=${point} runtime-version=2.0.0 prefix-unchanged')
}

fn check_unchanged(data string, point int, names []string, boundary winecutfixture.Boundary) ! {
	system := data + '/wine/drive_c/windows/system32'
	if os.ls(system)!.len != names.len - if boundary.added { 0 } else { 1 } {
		return error('public preview changed builtin namespace')
	}
	for index, name in names {
		path := system + '/' + name
		if index == names.len - 1 && !boundary.added {
			if os.exists(path) || os.is_link(path) { return error('public preview created missing builtin') }
			continue
		}
		generation := if index < boundary.replaced || index == names.len - 1 { '2' } else { '1' }
		target := '/var/lib/vinix-packages/generations/' + generation + '/apps/wine/root/usr/lib/wine/x86_64-windows/' + name
		if os.readlink(path)! != target { return error('public preview changed builtin target') }
	}
	stage := data + '/wine/.vinix-builtin-next'
	if boundary.staged {
		if os.readlink(stage)! != '/var/lib/vinix-packages/generations/2/apps/wine/root/usr/lib/wine/x86_64-windows/' + names[point / 3] {
			return error('public preview changed durable stage')
		}
	} else if os.exists(stage) || os.is_link(stage) { return error('public preview created stage') }
	if os.read_file(data + '/sentinel')! != 'private contents' { return error('public preview changed private data') }
}
