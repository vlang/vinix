// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module main

import cachecli
import crypto.sha256
import gamehost
import json2
import os
import qemubuild
import runtimehost
import sourcecommand

struct BuildFixture {
	root string
	work string
	base string
	bin  string
mut:
	prepares int
	builds   int
	fail     bool
}

fn write(file string, content string) ! {
	gamehost.mkdir(gamehost.parent(file))!
	os.write_file(file, content)!
}

fn elf(arm bool) []u8 {
	mut bytes := []u8{len: 128}
	for i, value in [u8(127), `E`, `L`, `F`, 2, 1, 1] { bytes[i] = value }
	bytes[16] = if arm { 2 } else { 3 }
	bytes[18] = if arm { 183 } else { 62 }
	bytes[32] = 64
	bytes[54] = 56
	bytes[56] = 1
	bytes[64] = 1
	return bytes
}

fn mesa_command(argv []string, _ bool, pointer voidptr) !sourcecommand.Output {
	mut f := unsafe { &BuildFixture(pointer) }
	name := argv[0].all_after_last('/')
	if name == 'clang' {
		assert argv[1..] == ['--version']
		return sourcecommand.Output{ stdout: 'fixture clang' }
	}
	if name == 'cp' {
		assert argv[1] == '-cRp'
		gamehost.copy_tree(argv[2], argv[3], false)!
	} else if name == 'tar' {
		f.prepares++
		assert argv[1] == 'xzf' && argv.last() == '--strip-components=1'
		write(argv[argv.index('-C') + 1] + '/debian/patches/series', '')!
	} else if name == 'gzip' {
		assert argv[1] == '-dc'
		return sourcecommand.Output{ stdout: 'fixture Debian patch' }
	} else if name == 'patch' {
		assert argv[1..5] == ['-p1', '--batch', '--forward', '-d']
		assert '-i' in argv
	} else if name == 'run-v-tool.sh' {
		assert argv[2] == '--install'
		write(argv[3], 'fixture native LLVM config')!
	} else if name == 'meson' {
		assert argv[1] == 'setup' && '--cross-file' in argv && '-Dvulkan-drivers=swrast' in argv && '-Dshared-llvm=enabled' in argv
		write(argv[2] + '/build.ninja', 'native configuration')!
	} else if name == 'ninja' {
		f.builds++
		assert argv[1..5] == ['-C', f.work + '/obj', '-j', '3']
		assert argv.last() == 'src/gallium/targets/lavapipe/libvulkan_lvp.so'
		file := f.work + '/obj/' + argv.last()
		gamehost.mkdir(gamehost.parent(file))!
		os.write_file_array(file, if f.fail { 'invalid ELF'.bytes() } else { elf(false) })!
	} else if name == 'llvm-readelf' {
		assert argv[1..3] == ['-d', '--dyn-syms']
		return sourcecommand.Output{ stdout: 'vk_icdNegotiateLoaderICDInterfaceVersion\n(NEEDED) [libc.so.6]\n' }
	} else {
		return error('unexpected driver command: ' + argv.str())
	}
	return sourcecommand.Output{}
}

fn mesa_cases(work string) ! {
	root := work + '/mesa-repo'
	base := work + '/mesa-base'
	build := work + '/mesa-work'
	bin := work + '/tools'
	gamehost.mkdir(base + '/usr/lib/gcc/x86_64-linux-gnu/12')!
	write(base + '/usr/lib/x86_64-linux-gnu/libLLVM-15.so.1', 'fixture LLVM')!
	write(base + '/lib/x86_64-linux-gnu/libc.so.6', 'fixture libc')!
	for name in ['clang', 'clang++', 'llvm-ar', 'llvm-strip', 'llvm-readelf', 'meson'] {
		write(bin + '/' + name, 'fixture tool ' + name)!
		os.chmod(bin + '/' + name, 0o755)!
	}
	write(root + '/tests/native-runtime-tools/main.v', 'native builder')!
	for name in ['find-v.sh', 'run-v-tool.sh'] {
		write(root + '/build-support/' + name, 'native launcher identity')!
	}
	write(root + '/build-support/dota2/mesa/fixture.patch', 'fixture patch')!
	gamehost.mkdir(build + '/downloads')!
	write(build + '/downloads/source.gz', 'source archive')!
	write(build + '/downloads/diff.gz', 'Debian archive')!
	inputs := json2.Any({
		'format':                json2.Any(2)
		'debian_version':        json2.Any('fixture version')
		'mirror':                json2.Any('https://fixture.invalid')
		'source':                json2.Any({
			'filename': json2.Any('source.gz')
			'sha256':   json2.Any(sha256.hexhash('source archive'))
		})
		'debian_diff':           json2.Any({
			'filename': json2.Any('diff.gz')
			'sha256':   json2.Any(sha256.hexhash('Debian archive'))
		})
		'debian_patches':        json2.Any(map[string]json2.Any{})
		'debian_source_sha256':  json2.Any(map[string]json2.Any{})
		'patched_source_sha256': json2.Any(map[string]json2.Any{})
		'patches':               json2.Any({
			'fixture.patch': json2.Any(sha256.hexhash('fixture patch'))
		})
		'packages':              json2.Any([]json2.Any{})
		'llvm_runtime_sha256':   json2.Any(sha256.hexhash('fixture LLVM'))
		'llvm_version':          json2.Any('15.0.6')
	})
	write(root + '/build-support/dota2/mesa/inputs.json', json2.encode(inputs))!
	os.setenv('VINIX_DOTA2_LLVM_BIN', bin, true)
	os.setenv('VINIX_DOTA2_MESON', bin + '/meson', true)
	mut f := BuildFixture{ root: root, base: base, work: build, bin: bin }
	tools := gamehost.Tools{ root: root, command_hook: mesa_command, context: &f }
	output := runtimehost.build_driver(tools, false, base, build, 3, false)!
	assert output == [build + '/out/libvulkan_lvp.so'] && f.prepares == 1 && f.builds == 1
	hash := gamehost.digest(output[0])!
	runtimehost.build_driver(tools, false, base, build, 3, false)!
	assert f.prepares == 1 && f.builds == 1
	os.write_file(output[0], 'damaged driver')!
	runtimehost.build_driver(tools, false, base, build, 3, false)!
	assert f.prepares == 1 && f.builds == 2 && gamehost.digest(output[0])! == hash
	f.fail = true
	mut refused := false
	runtimehost.build_driver(tools, false, base, build, 3, true) or {
		refused = true
		assert err.msg().contains('x86-64 shared library')
	}
	assert refused && gamehost.digest(output[0])! == hash
	cross := os.read_file(build + '/cross.ini')!
	assert cross.contains('--target=x86_64-linux-gnu') && cross.contains('--gcc-install-dir=') && cross.contains('llvm-config = ') && cross.contains('needs_exe_wrapper = true')
	runtimehost.write_driver_configuration(tools, build, inputs.as_map(), bin, true)!
	assert os.read_file(build + '/cross.ini')!.contains("c_args = ['-D__vinix__']") && !os.read_file(build + '/cross.ini')!.contains('llvm-config = ')
	os.unsetenv('VINIX_DOTA2_LLVM_BIN')
	os.unsetenv('VINIX_DOTA2_MESON')
}

fn qemu_command(argv []string, directory string, log string, capture bool, _ bool, _ map[string]string, pointer voidptr) !sourcecommand.Output {
	mut f := unsafe { &BuildFixture(pointer) }
	name := argv[0].all_after_last('/')
	assert name !in ['python', 'python3', 'pip'], 'upstream interpreter must not run during native qualification'
	if capture {
		if name.contains('readelf') {
			return sourcecommand.Output{ stdout: if f.fail {
				'(NEEDED) [libc.so]'
			} else {
				'There is no dynamic section.'
			} }
		}
		assert argv.last() == '--version'
		return sourcecommand.Output{ stdout: 'fixture host compiler' }
	}
	if log != '' { write(log, 'native build output\n')! }
	if name == 'tar' {
		assert argv[1] == 'xf'
		f.prepares++
		write(f.work + '/qemu-fixture/mmap.c', 'patched mapper')!
	} else if name == 'git' {
		assert 'apply' in argv
	} else if name == 'configure' {
		assert directory == f.work + '/build' && '--static' in argv && '--target-list=x86_64-linux-user' in argv
		assert argv.last() == '--python=' + f.bin + '/upstream-interpreter'
		write(directory + '/build.ninja', 'configured')!
	} else if name == 'ninja' {
		assert directory == f.work + '/build' && argv[1..] == ['-j', '3', 'qemu-x86_64']
		f.builds++
		os.write_file_array(directory + '/qemu-x86_64', elf(true))!
	} else {
		return error('unexpected QEMU command: ' + argv.str())
	}
	return sourcecommand.Output{}
}

fn qemu_cases(work string) ! {
	root := work + '/qemu-repo'
	build := work + '/qemu-work'
	base := work + '/qemu-base'
	support := root + '/build-support/dota2/qemu'
	bin := work + '/tools'
	for directory in ['build-support/dota2/qemubuild', 'build-support/cachekey',
		'tests/qemu-core/fixturehost'] {
		gamehost.mkdir(root + '/' + directory)!
	}
	write(root + '/build-support/dota2/qemu_builder.v', 'native producer')!
	write(root + '/tests/native-runtime-tools/main.v', 'native front')!
	for name in ['find-v.sh', 'run-v-tool.sh'] {
		write(root + '/build-support/' + name, 'native launcher identity')!
	}
	for pair in [['usr/include/elf.h', 'elf'], ['usr/lib/libc.a', 'libc'],
		['usr/lib/libglib-2.0.a', 'glib'], ['usr/lib/libpcre2-8.a', 'pcre'],
		['usr/lib/libintl.a', 'intl']] {
		write(base + '/' + pair[0], pair[1])!
	}
	write(root + '/build-aarch64-userland/staging/usr/lib/gcc/aarch64-alpine-linux-musl/12.2/libgcc.a', 'gcc')!
	write(root + '/build-aarch64-userland/staging/usr/lib/libatomic.a', 'atomic')!
	for name in ['noreplace.patch', 'wake-op.patch', 'internal-fault.patch', 'drm-passthrough.patch'] {
		write(support + '/' + name, name)!
	}
	write(bin + '/upstream-interpreter', 'external interpreter identity')!
	write(bin + '/aarch64-linux-musl-readelf', 'readelf')!
	os.chmod(bin + '/aarch64-linux-musl-readelf', 0o755)!
	write(support + '/inputs.json', json2.encode(json2.Any({
		'version':               json2.Any('fixture')
		'source_url':            json2.Any('https://fixture.invalid/qemu.tar.xz')
		'source_sha256':         json2.Any(sha256.hexhash('cached archive'))
		'alpine_patches':        json2.Any([]json2.Any{})
		'packages':              json2.Any([]json2.Any{})
		'patched_source_sha256': json2.Any({
			'mmap.c': json2.Any(sha256.hexhash('patched mapper'))
		})
	})))!
	write(build + '/downloads/qemu-fixture.tar.xz', 'cached archive')!
	mut f := BuildFixture{ root: root, base: base, work: build, bin: bin }
	mut environment := os.environ()
	environment['PATH'] = bin + ':' + os.getenv('PATH')
	environment['VINIX_DOTA2_QEMU_CLANG'] = bin + '/clang'
	environment['VINIX_DOTA2_QEMU_HOST_CC'] = bin + '/clang'
	options := qemubuild.Options{ native: true, native_sources: [root + '/tests/native-runtime-tools/main.v'], command_hook: qemu_command, command_context: &f, repo: root, support: support, builder: root + '/tests/native-runtime-tools/main.v', work: build, staging: work + '/qemu-stage', base: base, jobs: '3', platform: 'linux', python: bin + '/upstream-interpreter', python_version: 'fixture external tool identity', environment: environment, inherited_environment: environment }
	qemubuild.build(options)!
	assert f.prepares == 1 && f.builds == 1
	destination := work + '/qemu-stage/usr/bin/qemu-x86_64'
	hash := gamehost.digest(destination)!
	qemubuild.build(options)!
	assert f.prepares == 1 && f.builds == 2
	f.fail = true
	mut refused := false
	qemubuild.build(options) or {
		refused = true
		assert err.msg().contains('static native AArch64 ELF')
	}
	assert refused && gamehost.digest(destination)! == hash
	assert !os.exists(build + '/host-venv') && os.is_file(work + '/qemu-stage/usr/libexec/vinix-dota2/qemu-build.json')
}

fn sdk_cases(work string) ! {
	directory := work + '/sdk directory'
	gamehost.mkdir(directory)!
	before := os.ls('/dev/fd')!.len
	for _ in 0 .. 100 {
		result := sourcecommand.capture_in(['/bin/sh', '-c', 'printf "%s" "$PWD"; printf error >&2'], os.environ(), directory, false, cachecli.cancelled, '')!
		assert result.status == 0 && result.stdout == directory && result.stderr == 'error'
	}
	assert os.ls('/dev/fd')!.len == before
	assert sourcecommand.run_in(['/bin/sh', '-c', 'test "$PWD" = "$EXPECTED"'], {
		'PATH':     '/usr/bin:/bin'
		'EXPECTED': directory
	}, directory, cachecli.cancelled, '')!.status == 0
	mut refused := false
	sourcecommand.capture_in(['/bin/pwd'], os.environ(), directory + '/missing', true, cachecli.cancelled, '') or { refused = true }
	assert refused && os.ls('/dev/fd')!.len == before
}

fn main() {
	guard := cachecli.own_commands()
	defer { guard.close() }
	if os.args.len != 2 { exit(2) }
	work := os.args[1]
	gamehost.mkdir(work) or { panic(err) }
	sdk_cases(work) or {
		eprintln(err)
		exit(1)
	}
	mesa_cases(work) or {
		eprintln(err)
		exit(1)
	}
	qemu_cases(work) or {
		eprintln(err)
		exit(1)
	}
	os.write_file(work + '/passed', 'PASS\n') or { panic(err) }
	eprintln('NATIVE BUILD / Mesa configure/build/cache/damage/failure publication, both cross configurations, QEMU source/cache/external-tool recipe/static validation, SDK cwd/output/100 FD controls: PASS')
}
