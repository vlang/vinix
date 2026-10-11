// SPDX-License-Identifier: GPL-2.0-or-later
module emulatorbuild

import hosttest
import json2
import os
import policyhost
import runtime
import strconv

const ps1_revision = 'c8816799b50388e61cfe237fe2cdbb7d8175f20a'
const ps1_digest = 'edeb21fdeef8815521cb9d4488d2cd35746607c968ca9b26cce4e42c09f2dc99'

fn ps1_homebrew(output string) ! {
	mkdir(output)!
	release := 'https://github.com/Logan-Campbell/Tetrade/releases/download/v1.0/'
	for item in [
		['tetrade.exe', release + 'tetrade.exe', '1b67678b7b4ab8a2f22b5a6d10090093e2a659189f29936de7d1792a68a2a8d4', '636928'],
		['TETRADE_PSX.bin', release + 'TETRADE_PSX.bin', '2f41feba2023cbdcd9c1c3d4cfc3d8d1a7f1a2de0afea2e7a050b84640d6eaf8', '3196368'],
		['TETRADE_PSX.cue', release + 'TETRADE_PSX.cue', '98cb45d15241900c8459176e833be5edee78120763ac4d91d79d24020b10d67a', '74'],
		['TETRADE-LICENSE', 'https://raw.githubusercontent.com/Logan-Campbell/Tetrade/5155664152162a0dc04dc1f0d4f3c807c1e15388/LICENSE',
			'ced947f24012b2a5bb3352db81f3f186058fabe219013d26cdcdd20a7ba6e173', '1070'],
	] { fetch(output + '/' + item[0], item[1], item[2], item[3].i64())! }
	bytes := os.read_bytes(output + '/tetrade.exe')!
	if bytes.len < 8 || bytes[..8].bytestr() != 'PS-X EXE' { return error('Tetrade executable has no PlayStation EXE header') }
	println('Verified Tetrade 1.0 homebrew by Logan Campbell (MIT): ' + output)
}

pub fn notices(source string, output string) ! {
	mut entries := []string{}
	for item in [
		['libretro API (MIT)', 'deps/libretro-common/include/libretro.h', '@paragraph LICENSE'],
		['libchdr (BSD-3-Clause)', 'deps/libchdr/LICENSE.txt', ''],
		['CHD/MAME (BSD-3-Clause)', 'deps/libchdr/include/libchdr/chd.h', 'Copyright Aaron Giles'],
		['miniz (MIT)', 'deps/libchdr/deps/miniz-3.1.2/miniz.c', 'Copyright 2013-2014'],
		['LZMA SDK (public domain)', 'deps/libchdr/deps/lzma-26.02/LICENSE', ''],
		['dr_flac (public domain or MIT-0)', 'deps/libchdr/include/dr_libs/dr_flac.h', 'This software is available as a choice'],
		['Zstandard (GPLv2 option; see PCSX-ReARMed-COPYING)', 'deps/libchdr/deps/zstd-1.5.7/zstddeclib.c', 'Copyright (c) Meta Platforms'],
		['xxHash (GPLv2 option; see PCSX-ReARMed-COPYING)', 'deps/libchdr/deps/zstd-1.5.7/zstddeclib.c', 'Copyright (c) Yann Collet - Meta'],
	] {
		mut text := hosttest.module_read_text(source + '/' + item[1])!
		if item[2] != '' {
			marker := text.index(item[2]) or { return error('Missing license marker: ' + item[1]) }
			start := text[..marker].last_index('/*') or { return error('Missing license opening: ' + item[1]) }
			end := text[marker..].index('*/') or { return error('Missing license closing: ' + item[1]) }
			text = text[start..marker + end + 2]
		}
		entries << item[0] + '\nSource: ' + item[1] + '\n' + text + '\n'
	}
	destination := output + '/staging/usr/share/licenses/vinix-ps1'
	mkdir(destination)!
	hosttest.module_write_text(destination + '/THIRD-PARTY-NOTICES', entries.join('\n'))!
}

fn ps1_build(output string, options map[string]string) ! {
	root := hosttest.root()
	sdk := hosttest.module_resolve(options['--sysroot'] or { root + '/build-aarch64-userland/staging' })!
	llvm := hosttest.module_resolve(options['--llvm-bin'] or { os.getenv_opt('LLVM_BIN') or { '/opt/homebrew/opt/llvm/bin' } })!
	jobs := strconv.atoi(options['--jobs'] or { (if runtime.nr_cpus() < 8 { runtime.nr_cpus() } else { 8 }).str() }) or { return ArgumentError{'invalid integer for --jobs'} }
	if jobs < 1 { return ArgumentError{'--jobs must be positive'} }
	base := sdk + '/usr/lib/gcc/aarch64-alpine-linux-musl'
	mut versions := os.ls(base) or { return ArgumentError{'ARM64 musl sysroot missing; run scripts/build-userland-aarch64.sh'} }
	versions.sort()
	if versions.len == 0 || !os.is_file(sdk + '/usr/lib/libc.a') {
		return ArgumentError{'ARM64 musl sysroot missing; run scripts/build-userland-aarch64.sh'}
	}
	gcc := base + '/' + versions.last()
	for name in ['clang', 'llvm-ar'] {
		if !os.is_file(llvm + '/' + name) { return ArgumentError{'LLVM tool missing: ' + llvm + '/' + name} }
	}
	linker := if os.is_file(llvm + '/ld.lld') { llvm + '/ld.lld' } else {
		os.find_abs_path_of_executable('ld.lld') or { return ArgumentError{'LLVM linker missing: ld.lld'} }
	}
	mkdir(output)!
	archive, source := output + '/pcsx-source.tar.gz', output + '/source'
	fetch(archive, 'https://codeload.github.com/libretro/pcsx_rearmed/tar.gz/' + ps1_revision, ps1_digest, 6 * 1024 * 1024)!
	stamp := source + '/.vinix-source'
	if !os.exists(stamp) || hosttest.module_read_text(stamp)! != ps1_digest {
		work := private_directory(output, 'pcsx-source-')!
		defer { if os.exists(work) { retire(work) } }
		unpack(archive, work)!
		hosttest.module_write_text(work + '/.vinix-source', ps1_digest)!
		if os.exists(source) { hosttest.remove_work_dir(source)! }
		os.rename(work, source)!
	}
	compiler := [llvm + '/clang', '--target=aarch64-linux-musl', '--sysroot=' + sdk, '--gcc-install-dir=' + gcc]
	keys := ['platform', 'STATIC_LINKING', 'TARGET', 'DYNAREC', 'HAVE_CHD', 'HAVE_PHYSICAL_CDROM',
		'USE_ASYNC_CDROM', 'USE_ASYNC_GPU', 'USE_ASYNC_SPU', 'NDRC_THREAD', 'USE_RTHREADS',
		'USE_LIBRETRO_VFS', 'GIT_VERSION', 'CC', 'AR', 'LD']
	values := ['arm64', '1', 'pcsx_rearmed_libretro.a', '0', '1', '0', '0', '0', '0', '0', '0', '0',
		'" ' + ps1_revision[..7] + '"', compiler.map(shell_word(it)).join(' '), llvm + '/llvm-ar', linker]
	mut make := ['make', '-C', source, '-f', 'Makefile.libretro']
	mut build_options := map[string]json2.Any{}
	for i, key in keys { make << key + '=' + values[i]; build_options[key] = json2.Any(values[i]) }
	version := policyhost.capture([llvm + '/clang', '--version'])!
	build_stamp := cache_json(json2.Any({
		'options': json2.Any(build_options)
		'compiler': json2.Any(version)
		'source': json2.Any(ps1_digest)
		'libc': json2.Any(hosttest.file_digest(sdk + '/usr/lib/libc.a')!)
	}))
	stamp_file := output + '/core-build-stamp'
	if !os.exists(stamp_file) || hosttest.module_read_text(stamp_file)! != build_stamp {
		if logged([...make, 'clean'], output + '/core-clean.log')! != 0 { return error('PCSX-ReARMed clean failed; see ' + output + '/core-clean.log') }
	}
	log := output + '/core-build.log'
	if logged([...make, '-j' + jobs.str()], log)! != 0 {
		text := hosttest.module_read_text(log)!.runes()
		start := if text.len < 8000 { 0 } else { text.len - 8000 }
		return error('PCSX-ReARMed build failed; see ' + log + '\n' + text[start..].map(it.str()).join(''))
	}
	hosttest.module_write_text(stamp_file, build_stamp)!
	notices(source, output)!
	println('Built PCSX-ReARMed ' + ps1_revision[..7] + ' (interpreter): ' + source + '/pcsx_rearmed_libretro.a')
}
