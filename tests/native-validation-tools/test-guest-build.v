// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module main

import cachecli
import crypto.sha256
import gamehost
import os
import sourcecommand

fn builder_call(builder string, arguments []string) !sourcecommand.Output {
	return sourcecommand.capture_full([builder, ...arguments], os.environ(), -1, 16 * 1024 * 1024, cachecli.cancelled)!
}

fn build_cases(builder string, work string, root string) ! {
	cache := work + '/cache'
	gamehost.mkdir(work)!
	// Other sessions can rebuild the selected compiler while this long test runs.
	// Pin its executable; its source/runtime tree stays covered by the cache key.
	compiler_root := work + '/selected-v'
	gamehost.mkdir(compiler_root)!
	compiler := compiler_root + '/v'
	os.cp(@VEXE, compiler)!
	os.chmod(compiler, 0o755)!
	for name in ['vlib', 'thirdparty', 'cmd'] {
		os.symlink(os.dir(os.real_path(@VEXE)) + '/' + name, compiler_root + '/' + name)!
	}
	for arch in ['aarch64', 'x86_64'] {
		sysroot := root + if arch == 'aarch64' {
			'/build-aarch64-userland/staging'
		} else {
			'/build-amd64-desktop/initramfs-root'
		}
		for static_link in [false, true] {
			directory := work + '/' + arch + if static_link { '-static' } else { '-dynamic' }
			gamehost.mkdir(directory)!
			output := directory + '/validation-guest'
			mut arguments := ['--arch', arch, '--sysroot', sysroot, '--output', output, '--cache',
				cache, '--v', compiler]
			if static_link { arguments << '--static' }
			result := builder_call(builder, arguments)!
			assert result.status == 0, result.stderr
			bytes := os.read_bytes(output)!
			assert bytes[..7] == [u8(127), `E`, `L`, `F`, 2, 1, 1]
			assert bytes[18] == if arch == 'aarch64' { u8(183) } else { u8(62) }
			assert bytes.bytestr().contains('/lib/ld-musl-' + arch + '.so.1') == !static_link
			old := sha256.sum(bytes).hex()
			os.write_file_array(directory + '/original.elf', bytes)!
			warm := builder_call(builder, arguments)!
			assert warm.status == 0 && sha256.sum(os.read_bytes(output)!).hex() == old
			mut cached := ''
			for name in os.ls(cache)! {
				path := cache + '/' + name
				if !name.ends_with('.sha256') && os.is_file(path) && sha256.sum(os.read_bytes(path)!).hex() == old {
					cached = path
					break
				}
			}
			assert cached != ''
			os.write_file(cached, 'corrupt owned cache')!
			repaired := builder_call(builder, arguments)!
			os.write_file(directory + '/repair.stdout', repaired.stdout)!
			os.write_file(directory + '/repair.stderr', repaired.stderr)!
			assert repaired.status == 0, repaired.stderr
			assert sha256.sum(os.read_bytes(output)!).hex() == old
			assert sha256.sum(os.read_bytes(cached)!).hex() == old
			os.write_file(output, 'preserve existing guest executable')!
			failed := builder_call(builder, [...arguments, '--cc', work + '/mock-cc'])!
			assert failed.status != 0 && os.read_file(output)! == 'preserve existing guest executable'
			println('GUEST ELF / warm cache, corrupt cache rebuild and failed publication preservation: PASS ' + arch + if static_link {
				' static'
			} else {
				' musl'
			})
			flush_stdout()
		}
	}
	invalid := builder_call(builder, ['--arch', 'aarch64'])!
	assert invalid.status == 2
}

fn main() {
	if os.executable().ends_with('/mock-cc') {
		if os.args[1..] == ['--version'] {
			println('native controlled compiler failure fixture')
			return
		}
		eprintln('controlled linker failure')
		exit(7)
	}
	guard := cachecli.own_commands()
	defer { guard.close() }
	if os.args.len != 3 { exit(2) }
	work := os.args[2]
	gamehost.mkdir(work) or { panic(err) }
	os.cp(os.executable(), work + '/mock-cc') or { panic(err) }
	os.chmod(work + '/mock-cc', 0o755) or { panic(err) }
	build_cases(os.args[1], work, os.real_path(os.dir(@FILE) + '/../..')) or {
		eprintln(err)
		exit(1)
	}
	os.write_file(work + '/passed', 'PASS\n') or { panic(err) }
}
