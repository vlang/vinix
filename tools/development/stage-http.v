// SPDX-License-Identifier: GPL-2.0-or-later
// Stage existing native server/runtime inputs; do not fetch or install packages.
module main
import devcore
import json2
import os
import tests.development.referencecore

struct Receipt {
	schema int = 1
	architecture string
	server devcore.Pin
	runtime devcore.Pin
	sdk_sha256 string
	complete bool
}

fn ordinary_input(path string) !string {
	if os.lstat(path)!.get_filetype() != .regular || os.stat(path)!.mode & 0o6000 != 0 {
		return error('HTTP inputs must be ordinary files without set-ID bits')
	}
	return os.real_path(path)
}

fn stage() ! {
	if os.args.len == 2 && os.args[1] == '--help' {
		println('Usage: v run stage-http.v aarch64|x86_64 PREPARED-BUSYBOX-ELF PREPARED-MUSL-ELF FRESH-STAGING')
		return
	}
	if os.args.len != 5 || os.args[1] !in ['aarch64', 'x86_64'] { return error('invalid arguments; use --help') }
	arch := os.args[1]
	server := ordinary_input(os.args[2])!
	runtime := ordinary_input(os.args[3])!
	requested := os.abs_path(os.args[4])
	out := os.real_path(os.dir(requested)) + '/' + os.base(requested)
	if out == server || out == runtime { return error('staging cannot overwrite an input') }
	devcore.fresh_directory(out)!
	root := out + '/sdk'
	for path in [root, root + '/bin', root + '/lib'] { os.mkdir(path, mode: 0o755)! }
	server_pin := devcore.Pin{server, devcore.file_hash(server)!}
	runtime_pin := devcore.Pin{runtime, devcore.file_hash(runtime)!}
	os.cp(server, root + '/bin/busybox')!
	os.cp(runtime, root + '/lib/libc.so')!
	for path in [root + '/bin/busybox', root + '/lib/libc.so'] { os.chmod(path, 0o755)! }
	os.symlink('libc.so', root + '/lib/libc.musl-' + arch + '.so.1')!
	referencecore.options(root, 'http', arch)!
	devcore.verify(server_pin)!
	devcore.verify(runtime_pin)!
	devcore.verify(devcore.Pin{root + '/bin/busybox', server_pin.sha256})!
	devcore.verify(devcore.Pin{root + '/lib/libc.so', runtime_pin.sha256})!
	os.write_file(out + '/reference-sdk.json', json2.encode(Receipt{architecture: arch, server: server_pin,
		runtime: runtime_pin, sdk_sha256: devcore.tree_hash(root)!, complete: true}, prettify: true) + '\n')!
	println('Prepared HTTP reference SDK: ' + root)
}
fn main() { stage() or { eprintln(err); exit(1) } }
