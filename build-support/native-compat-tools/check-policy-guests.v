// SPDX-License-Identifier: GPL-2.0-or-later
module main

import fixturehost
import guesthost
import hosttest
import os
import policyhost

fn checked(binary string, profile string, cache string) ! {
	mut env := policyhost.environment()
	env['ASAN_OPTIONS'] = 'detect_leaks=0'
	for family in ['resource-groups', 'speculation-policy'] {
		for pair in [['--help', '0'], ['--unknown', '2']] {
			result := fixturehost.capture_both_preferred([binary, family, pair[0]], env, policyhost.caller_arch())!
			if result.status.str() != pair[1] { return error('CLI status differs: ' + family) }
		}
		for arch in ['aarch64', 'x86_64'] {
			kernel := cache + if arch == 'aarch64' { '/kernel-arm' } else { '/kernel-x86' }
			work := cache + '/policy-' + profile + '-' + family + '-' + arch
			mut argv := [binary, family, '--arch', arch, '--kernel-dir', kernel, '--state-dir', work, '--build-only']
			if family == 'speculation-policy' { argv << ['--guest-state-dir', work + '-guest'] }
			result := fixturehost.capture_both_preferred(argv, env, policyhost.caller_arch())!
			os.write_file(work + '.log', result.stdout + result.stderr)!
			if result.status != 0 { return error('Native target build failed: ' + family + ' ' + arch + '\n' + result.stderr) }
			init := work + if family == 'resource-groups' { '/init' } else { '/native/test' }
			bytes := os.read_bytes(init)!
			if bytes.len < 64 || bytes[..6] != [u8(0x7f), `E`, `L`, `F`, 2, 1] || int(bytes[18]) + (int(bytes[19]) << 8) != if arch == 'aarch64' { 183 } else { 62 } { return error('Invalid ELF') }
			manifest := hosttest.decode_json(os.read_file(work + if family == 'resource-groups' { '/inputs.json' } else { '/native/inputs.json' })!)!.as_map()
			mut recipe := (manifest['compile_command'] or { return error('Missing recipe') }).as_array().map(it.str())
			if family == 'resource-groups' {
				mut expected := []string{}
				if arch == 'aarch64' {
					sdk := os.getenv_opt('VINIX_AARCH64_SYSROOT') or { hosttest.root() + '/build-aarch64-userland/sysroot' }
					expected = [os.getenv_opt('CC') or { 'clang' }, '--target=aarch64-linux-musl', '--sysroot=' + sdk, '-L' + sdk + '/lib', '-fuse-ld=lld', '-fno-stack-protector']
				} else { expected = [os.getenv_opt('CC_AMD64') or { 'x86_64-linux-musl-gcc' }] }
				expected << ['-static', '-pthread', '-O2', '-Wall', '-Wextra', '-Werror', work + '/serial.o', hosttest.root() + '/tests/resource-groups/guest.c', '-o', init]
				if recipe != expected { return error('Original resource-group recipe differs') }
				if os.file_size(work + '/swap.img') != u64(256 * 1024 * 1024) { return error('Wrong swap size') }
				mut file := os.open(work + '/swap.img')!
				header := file.read_bytes(4096)
				file.close()
				if header.len != 4096 || header[1024..1036].hex() != '01000000ffff000000000000' || header[4086..].bytestr() != 'SWAPSPACE2' || !header[..1024].all(it == 0) || !header[1036..4086].all(it == 0) { return error('Original swap-header bytes differ') }
			}
			recipe[recipe.len - 1] = init + '-original-recipe'
			fixturehost.inherited_command_environment_preferred(recipe, env, policyhost.caller_arch())!
			if bytes != os.read_bytes(init + '-original-recipe')! { return error('Native original recipe replay differs') }
			println('Native ELF, original recipe and swap header PASS: ' + profile + ' ' + family + ' ' + arch)
		}
	}
	reference := cache + '/speculation-original.c'
	raw := policyhost.capture(['git', '-C', hosttest.root(), 'show', '5ecc81c0^:tests/speculation-policy/policy.c'])!
	if os.exists(reference) && os.read_file(reference)! != raw { return error('Frozen C control differs') }
	os.write_file(reference, raw)!
	for arch in ['arm64', 'amd64'] {
		work := cache + '/policy-' + profile + '-host-' + arch
		result := fixturehost.capture_both_preferred([binary, 'speculation-policy', '--host-arch', arch,
			'--original-reference', reference, '--state-dir', work], env, policyhost.caller_arch())!
		os.write_file(work + '.log', result.stdout + result.stderr)!
		if result.status != 0 || result.stdout != 'SPECULATION POLICY PASS (6144 cases)\n' { return error('C/V sanitized host oracle differs: ' + arch + '\n' + result.stderr) }
		if os.read_file(work + '/stdout')! != result.stdout || os.read_file(work + '/stderr')! != '' { return error('Host evidence differs') }
		println('Independent C/V 6144-case sanitized host oracle PASS: ' + profile + ' ' + arch)
	}
}

fn main() {
	if os.args.len == 2 && os.args[1] == '--fronts' {
		for family in ['resource-groups', 'speculation-policy'] {
			text := fixturehost.capture_in_preferred([hosttest.root() + '/tests/' + family + '/run', '--help'],
				'', policyhost.environment(), false, '/tmp', false, policyhost.caller_arch()) or { panic(err) }
			assert text.contains('Usage:')
			println('Cold native front outside checkout PASS: ' + family)
		}
		return
	}
	if os.args.len == 3 && os.args[1] == '--disks' {
		disk_diagnostic(os.args[2]) or { eprintln(err.msg()); exit(1) }
		return
	}
	if os.args.len != 4 { eprintln('Usage: check-policy-guests.v CONTROLLER PROFILE CACHE'); exit(2) }
	checked(os.args[1], os.args[2], os.args[3]) or { eprintln(err.msg()); exit(1) }
}

fn disk_diagnostic(cache string) ! {
	for arch in ['aarch64', 'x86_64'] {
		state := cache + '/swap-diagnostic-' + arch
		os.mkdir_all(state)!
		module_path := state + '/fixture'
		os.mkdir_all(module_path)!
		os.write_file(module_path + '/core.v', "module fixture\n#include <fcntl.h>\n#include <unistd.h>\n#include <stdio.h>\n#include <sys/reboot.h>\nfn C.open(&char, i32, ...) i32\nfn C.read(i32, voidptr, usize) i64\nfn C.lseek(i32, i64, i32) i64\nfn C.close(i32) i32\nfn C.printf(&char, ...) i32\nfn C.fflush(voidptr) i32\nfn C.reboot(i32) i32\n@[export: 'main']\npub fn run() i32 {\n unsafe {\n paths := [&char(c'/dev/vda'), &char(c'/dev/vdb'), &char(c'/dev/vdc'), &char(c'/dev/sd0'), &char(c'/dev/ata0')]!\n for index in 0 .. 5 {\n  path := paths[index]\n  fd := C.open(path, C.O_RDONLY)\n  if fd < 0 { continue }\n  mut header := [4096]u8{}\n  got := C.read(fd, &header[0], 4096)\n  size := C.lseek(fd, 0, C.SEEK_END)\n  C.printf(c'DISK DIAG path=%s size=%ld read=%ld signature=%.10s version=%u last=%u,%u,%u,%u\\n', path, size, got, &header[4086], u32(header[1024]), u32(header[1028]), u32(header[1029]), u32(header[1030]), u32(header[1031]))\n  C.close(fd)\n }\n C.printf(c'DISK DIAG DONE\\n'); C.fflush(nil)\n C.reboot(C.RB_POWER_OFF)\n return 0\n }\n}\n")!
		init := guesthost.compile_init(module_path + '/core.v', state, arch, false)!
		archive := guesthost.image(init, state)!
		kernel := cache + if arch == 'aarch64' { '/kernel-arm' } else { '/kernel-x86' }
		configured := guesthost.launch(init, archive, state, kernel, arch, true)!
		mut argv := configured.command.clone()
		disk := cache + '/actual-resource-groups-' + arch + '/swap.img'
		if arch == 'aarch64' {
			argv << ['-drive', 'if=none,format=raw,file=' + disk + ',snapshot=on,id=paging-swap', '-device', 'virtio-blk-device,drive=paging-swap']
		} else { argv << ['-drive', 'if=ide,format=raw,file=' + disk + ',snapshot=on'] }
		code := guesthost.boot(argv, configured.env, state, ['DISK DIAG DONE'], ['KERNEL PANIC', 'FATAL EXCEPTION'], 120, true)!
		if code != 0 { return error('Swap device diagnostic did not finish') }
	}
}
