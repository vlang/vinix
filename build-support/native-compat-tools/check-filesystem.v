// SPDX-License-Identifier: GPL-2.0-or-later
module main

import fixturehost
import hosttest
import os
import policyhost

fn checked(binary string, profile string, cache string) ! {
	mut env := policyhost.environment()
	env['ASAN_OPTIONS'] = 'detect_leaks=0'
	for family in ['resource-accounting', 'pagecache', 'ext2-sparse'] {
		for pair in [['--help', '0'], ['--unknown', '2']] {
			result := fixturehost.capture_both_preferred([binary, family, pair[0]], env, policyhost.caller_arch())!
			if result.status.str() != pair[1] { return error('CLI status differs: ' + family) }
		}
		for arch in ['aarch64', 'amd64'] {
			for retention in if family == 'resource-accounting' { [false, true] } else { [false] } {
				kernel := cache + if arch == 'aarch64' { '/kernel-arm' } else { '/kernel-x86' }
				work := cache + '/filesystem-' + profile + '-' + family + '-' + arch + '-' + retention.str()
				mut argv := [binary, family, '--arch', arch, '--kernel', kernel, '--state-dir', work, '--build-only']
				if retention { argv << '--retention-only' }
				result := fixturehost.capture_both_preferred(argv, env, policyhost.caller_arch())!
				os.write_file(work + '.log', result.stdout + result.stderr)!
				if result.status != 0 { return error('Target build failed: ' + work + '\n' + result.stderr) }
				init := work + '/init'
				bytes := os.read_bytes(init)!
				if bytes.len < 64 || bytes[..6] != [u8(0x7f), `E`, `L`, `F`, 2, 1] || int(bytes[18]) + (int(bytes[19]) << 8) != if arch == 'aarch64' { 183 } else { 62 } { return error('Wrong ELF') }
				manifest := hosttest.decode_json(os.read_file(work + '/inputs.json')!)!.as_map()
				mut recipe := manifest['compile_command']!.as_array().map(it.str())
				mut cc := []string{}
				if arch == 'aarch64' {
					sdk := os.getenv_opt('VINIX_AARCH64_SYSROOT') or { hosttest.root() + '/build-aarch64-userland/sysroot' }
					cc = [os.getenv_opt('CC') or { 'clang' }, '--target=aarch64-linux-musl', '--sysroot=' + sdk, '-L' + sdk + '/lib', '-fuse-ld=lld']
				} else { cc = [os.getenv_opt('CC_AMD64') or { 'x86_64-linux-musl-gcc' }] }
				mut expected := cc.clone()
				if family == 'resource-accounting' {
					expected << ['-static', '-O2', '-Wall', '-Wextra', '-Werror', '-fno-stack-protector', '-pthread']
					if retention { expected << '-DACCOUNTING_RETENTION_ONLY' }
					expected << [hosttest.root() + '/tests/resource-accounting/guest.c', '-o', init]
				} else { expected << ['-static', work + '/fixture.o', '-o', init] }
				if recipe != expected { return error('Original compiler/linker recipe differs') }
				recipe[recipe.len - 1] = init + '-original-recipe'
				fixturehost.inherited_command_environment_preferred(recipe, env, policyhost.caller_arch())!
				if bytes != os.read_bytes(init + '-original-recipe')! { return error('Byte-identical recipe replay differs') }
				if manifest['kernel_sha256']!.str() != hosttest.sha(kernel + '/bin/vinix')! { return error('Kernel snapshot differs') }
				for block in if family == 'ext2-sparse' { ['1024', '4096'] } else { ['4096'] } {
					disk := work + if family == 'ext2-sparse' { '/root-' + block + '.ext2' } else { '/root.ext2' }
					if os.file_size(disk) != u64(64 * 1024 * 1024) { return error('Wrong physical disk size') }
					format := hosttest.decode_json(os.read_file(work + '/format-' + block + '.json')!)!.as_map()['command']!.as_array().map(it.str())
					if format[format.index('-b') + 1] != block || format[format.index('-I') + 1] != '128' { return error('Wrong format geometry') }
					if format[format.index('-O') + 1].contains('^large_file') != (family == 'ext2-sparse') { return error('Sparse feature precondition differs') }
					check := fixturehost.capture_both_preferred([os.dir(format[0]) + '/e2fsck', '-f', '-n', disk], env, policyhost.caller_arch())!
					if check.status != 0 { return error('Initial physical ext2 image inconsistent') }
				}
				if arch == 'amd64' && os.read_file(work + '/seed/.vinix-image-id')! != manifest['archive_sha256']!.str()[..16] + '\n' { return error('Exact ISO/root identity differs') }
				if arch == 'aarch64' && os.ls(work + '/seed')!.len != 0 { return error('ARM home must start empty') }
				println('Native target, exact recipe replay and physical ext2 images PASS: ' + profile + ' ' + family + ' ' + arch + ' retention=' + retention.str())
			}
		}
	}
}

fn main() {
	if os.args.len == 5 && os.args[1] == '--owners' {
		owners(os.args[2], os.args[3], os.args[4]) or { eprintln(err.msg()); exit(1) }
		return
	}
	if os.args.len == 2 && os.args[1] == '--fronts' {
		for path in ['tests/resource-accounting/run', 'tests/pagecache/run-guest', 'tests/ext2-sparse/run'] {
			text := fixturehost.capture_in_preferred([hosttest.root() + '/' + path, '--help'], '', policyhost.environment(), false, '/tmp', false, policyhost.caller_arch()) or { panic(err) }
			assert text.contains('Usage:')
			println('Cold native front outside checkout PASS: ' + path)
		}
		return
	}
	if os.args.len != 4 { eprintln('Usage: check-filesystem.v CONTROLLER PROFILE CACHE'); exit(2) }
	checked(os.args[1], os.args[2], os.args[3]) or { eprintln(err.msg()); exit(1) }
}

fn owners(binary string, profile string, cache string) ! {
	parent := cache + '/filesystem-owner-' + profile
	os.mkdir(parent)!
	mut env := policyhost.environment()
	env['TMPDIR'] = parent
	env['ASAN_OPTIONS'] = 'detect_leaks=0'
	for family in ['resource-accounting', 'pagecache', 'ext2-sparse'] {
		for _ in 0 .. 4 {
			result := fixturehost.capture_both_preferred([binary, family, '--arch', 'aarch64', '--kernel', parent + '/absent', '--build-only'], env, policyhost.caller_arch())!
			if result.status == 0 || os.ls(parent)!.len != 0 { return error('Failed default workspace was not retired: ' + family) }
		}
		state := parent + '/preserved'
		os.mkdir(state)!
		os.write_file(state + '/sentinel', 'unchanged')!
		result := fixturehost.capture_both_preferred([binary, family, '--state-dir', state, '--build-only'], env, policyhost.caller_arch())!
		if result.status == 0 || os.read_file(state + '/sentinel')! != 'unchanged' || os.ls(state)!.len != 1 { return error('Existing evidence was overwritten: ' + family) }
		os.rm(state + '/sentinel')!
		os.rmdir(state)!
	}
	os.rmdir(parent)!
	println('Twelve failed default workspace retirements and three existing-state guards PASS: ' + profile)
}
