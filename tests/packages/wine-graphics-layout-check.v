// SPDX-License-Identifier: GPL-2.0-or-later
// Synthetic bytes test layout/provenance only, not fonts or executable semantics.
module main

import crypto.sha256
import os
import tools.packages.wineadapter

fn deny(runtime string, inputs map[string]string) ! {
	wineadapter.admit_graphics_layout(runtime, inputs) or { unsafe { err.free() }; return }
	return error('accepted changed graphics provenance')
}

fn run() ! {
	if os.args.len != 2 || os.exists(os.args[1]) { return error('usage: wine-graphics-layout-check FRESH_OUTPUT') }
	base := os.abs_path(os.args[1])
	distribution := base + '/usr/libexec/vinix-x86_64/root'
	runtime := base + '/runtime'
	for dir in [distribution + '/usr/lib', distribution + '/usr/share/fonts', runtime + '/root/usr/lib', runtime + '/root/usr/share/fonts'] { os.mkdir_all(dir)! }
	mut inputs := map[string]string{}
	mut copies := map[string]string{}
	for library in wineadapter.graphics_libraries() {
		source := distribution + '/usr/lib/' + library.source
		target := runtime + '/root/usr/lib/' + library.name
		os.write_file(source, 'synthetic library ' + library.name)!
		os.cp(source, target)!
		inputs[source] = sha256.hexhash(os.read_file(source)!)
		copies[source] = target
	}
	for name in ['fixture.ttf', '.hidden'] {
		source := distribution + '/usr/share/fonts/' + name
		target := runtime + '/root/usr/share/fonts/' + name
		os.write_file(source, 'synthetic font inventory ' + name)!
		os.cp(source, target)!
		inputs[source] = sha256.hexhash(os.read_file(source)!)
		copies[source] = target
	}
	wineadapter.admit_graphics_layout(runtime, inputs)!
	mut refused := 0
	for path, _ in inputs {
		mut missing := inputs.clone(); missing.delete(path)
		deny(runtime, missing)!; refused++
	}
	for source, target in copies {
		original := os.read_file(target)!
		os.write_file(target, original + 'changed')!
		deny(runtime, inputs)!; refused++
		os.write_file(target, original)!
	}
	extra := runtime + '/root/usr/share/fonts/extra.ttf'
	os.write_file(extra, 'extra')!; deny(runtime, inputs)!; refused++; os.rm(extra)!
	library := distribution + '/usr/lib/libfreetype.so.6.20.2'
	bytes := os.read_file(library)!
	os.write_file(base + '/library-backup', bytes)!
	os.rm(library)!; os.symlink(base + '/library-backup', library)!
	deny(runtime, inputs)!; refused++; os.rm(library)!; os.write_file(library, bytes)!
	copy := copies[library]
	os.rm(copy)!; os.symlink(library, copy)!
	deny(runtime, inputs)!; refused++; os.rm(copy)!; os.write_file(copy, bytes)!
	font := distribution + '/usr/share/fonts/fixture.ttf'
	font_bytes := os.read_file(font)!
	os.write_file(font, 'changed source font')!; deny(runtime, inputs)!; refused++; os.write_file(font, font_bytes)!
	os.rm(font)!; os.rm(copies[font])!; deny(runtime, inputs)!; refused++
	os.write_file(font, font_bytes)!; os.write_file(copies[font], font_bytes)!
	wineadapter.admit_graphics_layout(runtime, inputs)!
	if refused != 13 { return error('graphics control count differs') }
	println('WINE GRAPHICS LAYOUT PASS original/retry and 13 missing/changed/linked/hidden/font-set provenance refusals')
}

fn main() { run() or { eprintln(err); exit(1) } }
