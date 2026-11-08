// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import os

fn capture(args []string) !string {
	mut child := os.new_process(args[0])
	child.set_args(args[1..])
	child.set_redirect_stdio_merged()
	child.run()
	text := child.stdout_slurp()
	child.wait()
	defer { child.close() }
	if child.code != 0 { return error('${args[0]} failed: ${text}') }
	return text.trim_space()
}

fn preserve_sources(root string, output string, compiler string, zig string) ! {
	mut files := []string{}
	for folder in ['powerpc-boot', 'kernel/powerpc', 'tools/powerpc', 'tests/powerpc',
		'userland/powerpc'] {
		for suffix in ['.v', '.mod', '.ld'] { files << os.walk_ext(root + '/' + folder, suffix) }
	}
	files.sort()
	mut checksums := ''
	for path in files {
		relative := path[root.len + 1..]
		destination := output + '/sources/' + relative
		os.mkdir_all(os.dir(destination))!
		data := os.read_bytes(path)!
		os.write_file_array(destination, data)!
		checksums += sha256.hexhash(data.bytestr()) + '  sources/' + relative + '\n'
	}
	os.write_file(output + '/sources.sha256', checksums)!
	git := os.find_abs_path_of_executable('git')!
	revision := capture([git, '-C', root, 'rev-parse', 'HEAD'])!
	v_version := capture([compiler, 'version'])!
	zig_version := capture([zig, 'version'])!
	os.write_file(output + '/build.txt', 'Base revision: ${revision}\nV: ${v_version}\nZig: ${zig_version}\nExact inputs: sources.sha256\n')!
}

fn seal_results(output string) ! {
	mut checksums := ''
	for file in ['build.txt', 'sources.sha256', 'loader.c', 'probe.c', 'handoff-probe.elf', 'kernel.c',
		'init.c', 'init-ppc.elf', 'ramfs.tar', 'vinix-ppc.elf', 'kernel-boot.log', 'vinix-of.elf',
		'vinix-of.bin', 'vinix-ppc-boot.iso', 'firmware.dtb', 'boot.log', 'media-boot.log', 'shell-commands.log'] {
		if !os.is_file(output + '/' + file) { continue }
		data := os.read_bytes(output + '/' + file)!
		checksums += sha256.hexhash(data.bytestr()) + '  ' + file + '\n'
	}
	os.write_file(output + '/SHA256SUMS', checksums)!
}
