// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module main

import cachecli
import cachekey
import crypto.sha256
import os
import sourcecommand

fn checked_command(argv []string, directory string) !string {
	result := sourcecommand.capture_in(argv, os.environ(), directory, false, cachecli.cancelled, '')!
	if result.status != 0 || result.stdout.contains('retrying with') || result.stderr.contains('retrying with') {
		return error('Guest validation build failed: ' + argv.str() + '\n' + result.stdout + result.stderr)
	}
	return result.stdout
}

fn verify_elf(path string, machine int) ! {
	bytes := os.read_bytes(path)!
	if bytes.len < 64 || bytes[..7] != [u8(127), `E`, `L`, `F`, 2, 1, 1] || int(bytes[18]) | (int(bytes[19]) << 8) != machine {
		return error('Guest validation ELF architecture mismatch')
	}
}

fn guest_input_key(paths []string, vlib string) !string {
	mut inputs := paths.map(cachekey.BuildInput{ path: it, label: it })
	inputs << cachekey.BuildInput{ path: vlib, label: 'selected-vlib', policy: 'vlib' }
	return cachekey.build_tree_key('vinix-validation-guest-source-v1', [], inputs)!
}

fn build_guest(argv []string) ! {
	args := cachecli.arguments(argv, ['--arch', '--sysroot', '--output', '--cc', '--v', '--cache'], [], ['--static'], 0, 0, 'Build the V guest smoke, DNS and X11 commands.\nUsage: build-validation-guest --arch aarch64|x86_64 --output PATH [--sysroot DIR --cc CLANG --v V --cache DIR --static]') or { return error_with_code(err.msg(), 2) }
	arch := args.required('--arch') or { return error_with_code(err.msg(), 2) }
	output := os.abs_path(args.required('--output') or { return error_with_code(err.msg(), 2) })
	if arch !in ['aarch64', 'x86_64'] {
		return error_with_code('unsupported guest architecture', 2)
	}
	root := os.real_path(os.dir(@FILE) + '/../..')
	default_sysroot := if arch == 'aarch64' {
		root + '/build-aarch64-userland/staging'
	} else {
		root + '/build-amd64-userland/staging'
	}
	sysroot := os.abs_path(args.value('--sysroot', os.getenv_opt(if arch == 'aarch64' {
		'VINIX_AARCH64_SYSROOT'
	} else {
		'VINIX_AMD64_SYSROOT'
	}) or { default_sysroot }))
	gcc_root := sysroot + '/usr/lib/gcc/' + arch + '-alpine-linux-musl'
	mut versions := os.ls(gcc_root)!
	versions = versions.filter(os.is_file(gcc_root + '/' + it + '/libgcc.a'))
	versions.sort()
	if versions.len == 0 { return error('Alpine GCC runtime missing: ' + gcc_root) }
	gcc := gcc_root + '/' + versions.last()
	cc := args.value('--cc', os.getenv_opt('VINIX_VALIDATION_CLANG') or {
		if os.is_executable('/opt/homebrew/opt/llvm/bin/clang') {
			'/opt/homebrew/opt/llvm/bin/clang'
		} else {
			'clang'
		}
	})
	v := args.value('--v', @VEXE)
	vroot := os.dir(os.real_path(v))
	static_link := '--static' in args.options
	mut inputs := [@FILE, root + '/tests/native-validation-tools/guest.v',
		root + '/tests/native-validation-tools/guestvalidation', root + '/build-support/cachecli',
		root + '/build-support/cachekey', root + '/tools/sourcecommand',
		root + '/build-support/aarch64-cc-shim', v, sysroot + '/usr/include', gcc]
	for name in ['crt1.o', 'crti.o', 'crtn.o', 'libc.a', 'libc.so'] {
		inputs << sysroot + '/usr/lib/' + name
	}
	inputs << sysroot + '/lib/ld-musl-' + arch + '.so.1'
	input_key := guest_input_key(inputs, vroot + '/vlib')!
	key := sha256.hexhash(input_key + '\n' + checked_command([
		cc,
		'--version',
	], root)! + '\n' + arch + '\nstatic=' + static_link.str())
	cache := os.abs_path(args.value('--cache', os.getenv_opt('VINIX_VALIDATION_GUEST_CACHE') or { os.getenv('HOME') + '/.cache/vinix-validation-guest' }))
	os.mkdir_all(cache)!
	cached := cache + '/' + key
	state := cached + '.sha256'
	valid := os.is_file(cached) && (os.read_file(state) or { '' }).trim_space() == sha256.sum(os.read_bytes(cached)!).hex()
	if !valid {
		private := sourcecommand.temporary('vinix-validation-guest-')!
		defer { os.rmdir_all(private) or {} }
		source := private + '/guest.c'
		checked_command([v, '-nocache', '-new-compiler', '-os', 'linux', '-arch',
			if arch == 'aarch64' { 'arm64' } else { 'amd64' }, '-gc', 'none', '-manualfree',
			'-enable-globals', '-prod', '-d', 'glibc', '-d', 'no_backtrace', '-d', 'no_segfault_handler',
			'-o', source, root + '/tests/native-validation-tools/guest.v'], root)!
		binary := private + '/validation-guest'
		mut flags := [cc, '--target=' + arch + '-linux-musl', '-nostdinc', '-nostdlib', '-isystem',
			gcc + '/include', '-isystem', sysroot + '/usr/include', '-I',
			root + '/tools/sourcecommand', '-D_GNU_SOURCE', '-O2', '-fno-stack-protector', '-w',
			'-no-pie']
		if arch == 'aarch64' { flags << ['-isystem', root + '/build-support/aarch64-cc-shim'] }
		if static_link {
			flags << '-static'
		} else {
			flags << '-Wl,--dynamic-linker=/lib/ld-musl-' + arch + '.so.1'
		}
		flags << [sysroot + '/usr/lib/crt1.o', sysroot + '/usr/lib/crti.o',
			gcc + if static_link { '/crtbeginT.o' } else { '/crtbegin.o' }, source,
			'-L' + sysroot + '/usr/lib', '-L' + gcc, '-lgcc_eh', '-lc', '-lgcc', '-lm',
			gcc + '/crtend.o', sysroot + '/usr/lib/crtn.o', '-fuse-ld=lld', '-o', binary]
		checked_command(flags, root)!
		verify_elf(binary, if arch == 'aarch64' { 183 } else { 62 })!
		if guest_input_key(inputs, vroot + '/vlib')! != input_key {
			return error('Guest validation build inputs changed during compilation')
		}
		os.chmod(binary, 0o755)!
		temporary := cache + '/.publish-' + os.getpid().str()
		defer { os.rm(temporary) or {} }
		os.cp(binary, temporary)!
		cachecli.replace_file(temporary, cached)!
		cachecli.publish(state, sha256.sum(os.read_bytes(cached)!).hex() + '\n')!
	}
	verify_elf(cached, if arch == 'aarch64' { 183 } else { 62 })!
	os.mkdir_all(os.dir(output))!
	// Publish on the destination filesystem so an image never observes a partial executable.
	mut pattern := (output + '.XXXXXX\x00').bytes()
	descriptor := C.mkstemp(pattern.data)
	if descriptor < 0 { return os.error_posix() }
	C.close(descriptor)
	destination := pattern[..pattern.len - 1].bytestr()
	defer { os.rm(destination) or {} }
	os.cp(cached, destination)!
	os.chmod(destination, 0o755)!
	cachecli.replace_file(destination, output)!
	println('Built V guest validation (' + arch + if static_link {
		', static): '
	} else {
		', musl): '
	} + output)
}

fn main() {
	guard := cachecli.own_commands()
	defer { guard.close() }
	build_guest(os.args[1..]) or {
		eprintln(err)
		exit(if cachecli.cancelled() {
			cachecli.interrupt_status()
		} else if err.code() == 2 {
			2
		} else {
			1
		})
	}
}
