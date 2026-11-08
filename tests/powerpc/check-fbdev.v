// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import os

fn execute(args []string) !string {
	mut child := os.new_process(args[0])
	child.set_args(args[1..])
	child.set_redirect_stdio_merged()
	child.run()
	output := child.stdout_slurp()
	child.wait()
	defer { child.close() }
	if child.code != 0 { return error(args.join(' ') + '\n' + output) }
	return output
}

fn main() {
	if os.args.len != 3 {
		eprintln('Usage: v run tests/powerpc/check-fbdev.v UAPI_INCLUDE OUTPUT_DIRECTORY')
		exit(2)
	}
	check(os.real_path(os.args[1]), os.abs_path(os.args[2])) or {
		eprintln(err)
		exit(1)
	}
}

fn check(headers string, output string) ! {
	root := os.real_path(@VMODROOT + '/../..')
	v := os.find_abs_path_of_executable(os.getenv_opt('VINIX_V_COMPILER') or { 'v' })!
	zig := os.find_abs_path_of_executable(os.getenv_opt('VINIX_PPC_ZIG') or { 'zig' })!
	if !os.is_file(headers + '/linux/fb.h') {
		return error('UAPI_INCLUDE must contain upstream linux/fb.h')
	}
	os.mkdir_all(output)!
	mut manifest := ''
	for relative in ['desktop/fbdevabi/layout.v', 'desktop/framebuffer.v', 'desktop/session_displays.v',
		'tests/powerpc/fbdevabi/main.v', 'tests/powerpc/check-fbdev.v'] {
		data := os.read_bytes(root + '/' + relative)!
		os.mkdir_all(output + '/sources/' + os.dir(relative))!
		os.write_file_array(output + '/sources/' + relative, data)!
		manifest += sha256.hexhash(data.bytestr()) + '  sources/' + relative + '\n'
	}
	header := os.read_bytes(headers + '/linux/fb.h')!
	os.write_file_array(output + '/fb.h', header)!
	manifest += sha256.hexhash(header.bytestr()) + '  fb.h\n'
	mut log := execute(['git', '-C', root, 'rev-parse', 'HEAD'])!
	log += execute([v, 'version'])! + execute([zig, 'version'])!
	mut zig_lib := ''
	for line in execute([zig, 'env'])!.split_into_lines() {
		if line.trim_space().starts_with('.lib_dir = ') || line.trim_space().starts_with('"lib_dir":') {
			zig_lib = line.all_after(if line.contains('=') { '=' } else { ':' }).trim_space().trim_right(',').trim('"')
		}
	}
	if zig_lib == '' { return error('Cannot locate Zig Linux type headers') }
	for pair in [['ppc', 'powerpc-linux-musl'], ['amd64', 'x86_64-linux-musl'],
		['arm64', 'aarch64-linux-musl']] {
		generated := output + '/fbdev-' + pair[0] + '.c'
		log += execute([v, '-shared', '-no-builtin', '-no-closures', '-os', 'vinix', '-arch', pair[0],
			'-target-libc-headers', '-gc', 'none', '-manualfree', '-path', '@vlib|' + root, '-o',
			generated, root + '/tests/powerpc/fbdevabi'])!
		log += execute([zig, 'cc', '-target', pair[1], '-I', headers, '-isystem',
			zig_lib + '/libc/include/' + pair[1], '-isystem', zig_lib + '/libc/include/generic-musl',
			'-isystem', zig_lib + '/libc/include/' + pair[1].replace('-musl', '-any'), '-isystem',
			zig_lib + '/libc/include/any-linux-any', '-c', generated, '-o',
			output + '/fbdev-' + pair[0] + '.o'])!
		line := 'PASS fbdev ABI: ' + pair[1] + '\n'
		print(line)
		log += line
		for extension in ['c', 'o'] {
			name := 'fbdev-' + pair[0] + '.' + extension
			manifest += sha256.hexhash(os.read_bytes(output + '/' + name)!.bytestr()) + '  ' + name + '\n'
		}
	}
	os.write_file(output + '/check.log', log)!
	manifest += sha256.hexhash(log) + '  check.log\n'
	os.write_file(output + '/SHA256SUMS', manifest)!
}
