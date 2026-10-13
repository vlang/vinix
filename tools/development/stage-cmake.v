// SPDX-License-Identifier: GPL-2.0-or-later
// Prepare a reference SDK from existing native compiler and package inputs.
module main

import devcore
import json2
import os
import sourcecommand
import tests.development.referencecore

struct Receipt {
	schema int = 1
	architecture string
	base_source string
	overlay_source string
	readelf devcore.Pin
mut:
	base_import_sha256 string
	cmake_modules_sha256 string
	files map[string]devcore.Pin
	sdk_sha256 string
	complete bool
}

fn copy_input(source string, target string, base string) ! {
	if source.ends_with('.py') || source.ends_with('.pyc') || source.ends_with('.pyo') || source.ends_with('.py.in') { return }
	st := os.lstat(source)!
	match st.get_filetype() {
		.directory {
			os.mkdir(target, mode: 0o700)!
			for name in os.ls(source)! { copy_input(source + '/' + name, target + '/' + name, base)! }
			os.chmod(target, int(st.mode & 0o777))!
		}
		.regular {
			os.cp(source, target)!
			os.chmod(target, int(st.mode & 0o777))!
			if devcore.file_hash(source)! != devcore.file_hash(target)! { return error('input changed during copy') }
		}
		.symbolic_link {
			link := os.readlink(source)!
			if link == '/lib/libc.so' && os.dir(source) == base + '/lib' {
				os.symlink('libc.so', target)!
			} else {
				resolved := os.real_path(source)
				if link.starts_with('/') || !os.exists(source) || (resolved != base && !resolved.starts_with(base + '/')) {
					return error('input link escapes its closure: ' + source)
				}
				os.symlink(link, target)!
			}
		}
		else { return error('unsupported input type: ' + source) }
	}
}

fn stage() ! {
	if os.args.len == 2 && os.args[1] == '--help' {
		println('Usage: v run stage-cmake.v aarch64|x86_64 PREPARED-C-SDK PREPARED-DEVELOPER-OVERLAY FRESH-STAGING')
		return
	}
	if os.args.len != 5 || os.args[1] !in ['aarch64', 'x86_64'] { return error('invalid arguments; use --help') }
	arch := os.args[1]
	base := referencecore.options(os.args[2], 'ninja', arch)!
	if os.is_link(os.args[3]) || !os.is_dir(os.args[3]) { return error('developer overlay must be an ordinary directory') }
	overlay := os.real_path(os.args[3])
	requested_out := os.abs_path(os.args[4])
	out := os.real_path(os.dir(requested_out)) + '/' + os.base(requested_out)
	if out == base.root || out.starts_with(base.root + '/') || out == overlay || out.starts_with(overlay + '/') {
		return error('staging must be outside its input closures')
	}
	readelf := os.find_abs_path_of_executable(arch + '-linux-musl-readelf')!
	devcore.fresh_directory(out)!
	mut receipt := Receipt{architecture: arch, base_source: base.root, overlay_source: overlay,
		readelf: devcore.Pin{readelf, devcore.file_hash(readelf)!}}
	manifest := out + '/reference-sdk.json'
	os.write_file(manifest, json2.encode(receipt, prettify: true) + '\n')!
	root := out + '/sdk'
	copy_input(base.root, root, base.root)!
	receipt.base_import_sha256 = devcore.tree_hash(root)!
	cmake := overlay + '/usr/bin/cmake'
	if !os.real_path(cmake).starts_with(overlay + '/') || !os.is_file(cmake) { return error('missing ordinary CMake input') }
	copy_input(cmake, root + '/bin/cmake', overlay)!
	os.mkdir_all(root + '/share')!
	for name in os.ls(overlay + '/usr/share')! {
		if name == 'cmake' || name.starts_with('cmake-') {
			copy_input(overlay + '/usr/share/' + name, root + '/share/' + name, overlay)!
		}
	}
	receipt.files['cmake'] = devcore.Pin{cmake, devcore.file_hash(root + '/bin/cmake')!}
	if os.is_dir(root + '/share/cmake') { receipt.cmake_modules_sha256 = devcore.tree_hash(root + '/share/cmake')! }
	mut pending := [root + '/bin/cmake']
	mut seen := map[string]bool{}
	for pending.len > 0 {
		path := pending.pop()
		result := sourcecommand.capture([readelf, '-d', path], devcore.environment(0), 30, 65536, unsafe { nil })!
		if result.status != 0 { return error('library inspection failed: ' + result.stderr) }
		for line in result.stdout.split_into_lines().filter(it.contains('(NEEDED)')) {
			name := line.all_after('[').all_before(']')
			if name == '' || name.contains('/') || name.contains('\x00') { return error('invalid runtime library name') }
			if seen[name] { continue }
			seen[name] = true
			// Preserve the supplied compiler's linker inputs. Newer Alpine
			// libgcc_s may contain RELR sections its older linker cannot read.
			// A missing CMake runtime ABI remains a failing native gate.
			if name == 'libc.so' || name == 'libc.musl-' + arch + '.so.1'
				|| (name == 'libgcc_s.so.1' && os.is_file(root + '/lib/' + name)) {
				receipt.files[name] = devcore.Pin{base.root + '/lib/' + name, devcore.file_hash(root + '/lib/' + name)!}
				continue
			}
			mut source := ''
			for directory in [overlay + '/usr/lib', overlay + '/lib'] {
				candidate := directory + '/' + name
				if os.is_file(candidate) { source = os.real_path(candidate); break }
			}
			if source == '' || !source.starts_with(overlay + '/') { return error('missing contained runtime library: ' + name) }
			target := root + '/lib/' + name
			if os.is_link(target) { os.rm(target)! }
			copy_input(source, target, overlay)!
			receipt.files[name] = devcore.Pin{source, devcore.file_hash(target)!}
			pending << target
		}
	}
	referencecore.options(root, 'cmake', arch)!
	for name, pin in base.tools { devcore.verify(pin)!; devcore.verify(devcore.Pin{root + '/bin/' + name, pin.sha256})! }
	devcore.verify(receipt.readelf)!
	for _, pin in receipt.files { devcore.verify(pin)! }
	receipt.sdk_sha256 = devcore.tree_hash(root)!
	receipt.complete = true
	os.write_file(manifest, json2.encode(receipt, prettify: true) + '\n')!
	println('Prepared CMake reference SDK: ' + root)
}

fn main() { stage() or { eprintln(err); exit(1) } }
