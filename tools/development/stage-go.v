// SPDX-License-Identifier: GPL-2.0-or-later
// Materialize an existing native Go installation as a portable reference SDK.
module main

import devcore
import json2
import os
import tests.development.referencecore

struct Receipt {
	schema int = 1
	architecture string
	overlay_source string
mut:
	go_source_sha256 string
	go_import_sha256 string
	runtime devcore.Pin
	go devcore.Pin
	sdk_sha256 string
	complete bool
}

fn copy_go(source string, target string, base string) ! {
	if source.ends_with('.py') || source.ends_with('.pyc') || source.ends_with('.pyo') { return }
	st := os.lstat(source)!
	if st.mode & 0o6000 != 0 { return error('set-ID input refused: ' + source) }
	match st.get_filetype() {
		.directory {
			os.mkdir(target, mode: 0o700)!
			for name in os.ls(source)! { copy_go(source + '/' + name, target + '/' + name, base)! }
			os.chmod(target, int(st.mode & 0o777))!
		}
		.regular {
			os.cp(source, target)!
			os.chmod(target, int(st.mode & 0o777))!
			if devcore.file_hash(source)! != devcore.file_hash(target)! { return error('Go input changed during copy') }
		}
		.symbolic_link {
			link := os.readlink(source)!
			resolved := os.real_path(source)
			if link.starts_with('/') || !os.exists(source) || (resolved != base && !resolved.starts_with(base + '/')) {
				return error('Go input link escapes its closure: ' + source)
			}
			os.symlink(link, target)!
		}
		else { return error('unsupported Go input type: ' + source) }
	}
}

fn stage() ! {
	if os.args.len == 2 && os.args[1] == '--help' {
		println('Usage: v run stage-go.v aarch64|x86_64 PREPARED-GO-OVERLAY FRESH-STAGING')
		return
	}
	if os.args.len != 4 || os.args[1] !in ['aarch64', 'x86_64'] { return error('invalid arguments; use --help') }
	arch := os.args[1]
	if os.is_link(os.args[2]) || !os.is_dir(os.args[2]) { return error('Go overlay must be an ordinary directory') }
	overlay := os.real_path(os.args[2])
	requested := os.abs_path(os.args[3])
	out := os.real_path(os.dir(requested)) + '/' + os.base(requested)
	if out == overlay || out.starts_with(overlay + '/') { return error('staging must be outside its input closure') }
	source := overlay + '/usr/lib/go'
	if os.is_link(source) || !os.is_dir(source) || !os.real_path(source).starts_with(overlay + '/') {
		return error('missing contained ordinary Go installation')
	}
	// Record the entire supplied installation as well as the filtered import.
	// Only the imported closure enters the guest; no Python file is copied.
	before := devcore.tree_hash(source)!
	runtime := overlay + '/lib/ld-musl-' + arch + '.so.1'
	if os.lstat(runtime)!.get_filetype() != .regular || !os.real_path(runtime).starts_with(overlay + '/') {
		return error('musl runtime must be a contained ordinary file')
	}
	devcore.fresh_directory(out)!
	mut receipt := Receipt{architecture: arch, overlay_source: overlay, go_source_sha256: before}
	manifest := out + '/reference-sdk.json'
	os.write_file(manifest, json2.encode(receipt, prettify: true) + '\n')!
	root := out + '/sdk'
	for directory in [root, root + '/bin', root + '/lib', root + '/share'] { os.mkdir(directory, mode: 0o755)! }
	copy_go(source, root + '/share/go', source)!
	copy_go(runtime, root + '/lib/libc.so', overlay)!
	os.symlink('../share/go/bin/go', root + '/bin/go')!
	referencecore.options(root, 'go', arch)!
	receipt.go_import_sha256 = devcore.tree_hash(root + '/share/go')!
	receipt.runtime = devcore.Pin{runtime, devcore.file_hash(root + '/lib/libc.so')!}
	receipt.go = devcore.Pin{source + '/bin/go', devcore.file_hash(root + '/bin/go')!}
	if devcore.tree_hash(source)! != before { return error('Go installation changed during preparation') }
	devcore.verify(receipt.runtime)!
	devcore.verify(receipt.go)!
	receipt.sdk_sha256 = devcore.tree_hash(root)!
	receipt.complete = true
	os.write_file(manifest, json2.encode(receipt, prettify: true) + '\n')!
	println('Prepared Go reference SDK: ' + root)
}

fn main() { stage() or { eprintln(err); exit(1) } }
