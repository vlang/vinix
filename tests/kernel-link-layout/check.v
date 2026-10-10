// SPDX-License-Identifier: GPL-2.0-or-later
module main

import hosttest
import os

fn command(argv []string) !hosttest.Result {
	result := hosttest.capture(argv, '', -1, os.environ())!
	if result.code != 0 {
		return error(result.stdout + result.stderr)
	}
	return result
}

fn check(kernel string, arch string) ! {
	root := hosttest.module_resolve(kernel)!
	linker := os.getenv_opt('LD') or { os.find_abs_path_of_executable('ld.lld') or { '' } }
	nm := os.getenv_opt('NM') or { os.find_abs_path_of_executable('llvm-nm') or { '' } }
	if linker == '' || nm == '' {
		return error('ld.lld and llvm-nm are required')
	}
	mut c_objects := os.walk_ext(root + '/obj/c', '.o')
	mut asm_objects := os.walk_ext(root + '/obj/asm', '.o')
	c_objects.sort()
	asm_objects.sort()
	arm := arch == 'aarch64'
	mut base := [linker, '-m', if arm { 'aarch64elf' } else { 'elf_x86_64' }, '--build-id=none',
		'--nostdlib', '--static', '-z', 'max-page-size=' + if arm { '0x4000' } else { '0x1000' },
		'--gc-sections', '-T', root + '/' + if arm { 'linker-aarch64.ld' } else { 'linker.ld' },
		root + '/obj/blob.c.o']
	base << c_objects
	base << asm_objects
	base << root + '/cc-runtime-${arch}/cc-runtime.a'
	work := hosttest.work_dir('', 'vinix-link-layout-')!
	defer { hosttest.remove_work_dir(work) or { eprintln(err) } }
	mut images := [][]u8{}
	mut symbols := [][]string{}
	for index, seed in [12345, 12345, 67890, 0, 0] {
		image := work + '/' + index.str()
		mut argv := base.clone()
		argv << ['--shuffle-sections=.text.*=${seed}', '-o', image]
		linked := command(argv)!
		print(linked.stdout)
		eprint(linked.stderr)
		images << os.read_bytes(image)!
		rows := command([nm, '-n', image])!.stdout.split_into_lines()
		mut names := []string{}
		for row in rows {
			fields := row.fields()
			if fields.len == 3 && fields[1] in ['t', 'T'] {
				names << fields[2]
			}
		}
		symbols << names
	}
	if images[0] != images[1] {
		return error('fixed seed must reproduce the identical ELF')
	}
	if symbols[0] == symbols[2] {
		return error('different seeds must alter function order')
	}
	if symbols[3] == symbols[4] {
		return error('fresh links must choose different layouts')
	}
	if symbols.any('main__kmain' !in it) {
		return error('kernel entry must be retained')
	}
	println('Kernel link layout ${arch}: PASS (fixed seed reproducible; distinct/random seeds differ)')
}

fn main() {
	args := hosttest.parse_arguments(os.args[1..], [
		hosttest.Option{'--kernel', true, []string{}},
		hosttest.Option{'--arch', true, ['aarch64', 'x86_64']},
	], 0, 'Usage: check --kernel PATH --arch aarch64|x86_64',
		'Relink actual kernel objects to verify shuffled and reproducible layouts.') or {
		eprintln(err)
		exit(2)
	}
	if '--kernel' !in args.options || '--arch' !in args.options {
		eprintln('--kernel and --arch are required')
		exit(2)
	}
	check(args.options['--kernel'], args.options['--arch']) or {
		eprintln(err)
		exit(1)
	}
}
