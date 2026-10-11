// SPDX-License-Identifier: GPL-2.0-or-later
module guesthost

import fixturehost
import hosttest
import json2
import os
import policyhost
import strconv

struct AbiSpec {
	family      string
	module_name string
	features    []string
	pass        string
	failures    []string
}

pub struct AbiBuild {
pub:
	family          string
	arch            string = 'aarch64'
	source          string
	prebuilt        string
	expect_readable bool
	baseline        bool
	case_name       string = 'full'
	runner_root     string
	timeout         int = 300
}

fn abi_validate_elf(path string, arch string) ! {
	bytes := os.read_bytes(path)!
	if bytes.len < 20 || bytes[..6] != [u8(0x7f), `E`, `L`, `F`, 2, 1]
		|| int(bytes[18]) + (int(bytes[19]) << 8) != if arch == 'aarch64' { 183 } else { 62 } {
		return error('Expected little-endian ELF64 for ' + arch + ': ' + path)
	}
}

fn abi_compiler(build AbiBuild) !([]string, []string) {
	if build.arch != 'aarch64' {
		return hosttest.shell_split(os.getenv_opt('CC_AMD64') or { 'x86_64-linux-musl-gcc' })!, []string{}
	}
	repo := if build.family == 'procfs-mount' && build.runner_root != '' {
		build.runner_root
	} else {
		root()
	}
	sdk := os.getenv_opt('VINIX_AARCH64_SYSROOT') or { repo + '/build-aarch64-userland/sysroot' }
	mut compiler := hosttest.shell_split(os.getenv_opt('CC') or { 'clang' })!
	compiler << ['--target=aarch64-linux-musl', '--sysroot=' + sdk]
	if build.family == 'procfs-mount' {
		gcc := repo + '/build-aarch64-userland/staging/usr/lib/gcc/aarch64-alpine-linux-musl'
		if os.is_dir(gcc) {
			mut versions := os.ls(gcc)!
			versions.sort()
			if versions.len > 0 { compiler << '--gcc-install-dir=' + gcc + '/' + versions.last() }
		}
	}
	return compiler, ['-L' + sdk + '/lib', '-fuse-ld=lld']
}

fn abi_source_hashes(spec AbiSpec, source string) !json2.Any {
	if source != '' { return json2.Any(digest(source)!) }
	if spec.module_name == '' {
		mut values := {
			'guest.c': json2.Any(digest(root() + '/tests/' + spec.family + '/guest.c')!)
		}
		if spec.family in ['stack-policy', 'syscall-policy'] {
			values['switch.S'] = json2.Any(digest(root() + '/tests/' + spec.family + '/switch.S')!)
		}
		return json2.Any(values)
	}
	module_path := root() + '/tests/' + spec.family + '/' + spec.module_name
	mut names := os.ls(module_path)!
	names.sort()
	mut values := map[string]json2.Any{}
	for name in names {
		if os.is_file(module_path + '/' + name) {
			values[name] = json2.Any(digest(module_path + '/' + name)!)
		}
	}
	return json2.Any(values)
}

// The compile and link warning policies are unchanged. Only V-generated
// objects receive the existing unused-helper and unused-parameter exceptions.
pub fn build_abi_guest(state string, build AbiBuild) !string {
	spec := abi_spec(build.family)!
	if build.arch !in ['aarch64', 'x86_64'] || build.case_name !in ['full', 'reuse'] {
		return error('Invalid ABI build architecture or case')
	}
	init := state + '/init'
	mut command := []string{}
	if build.prebuilt != '' {
		abi_validate_elf(build.prebuilt, build.arch)!
		os.cp(build.prebuilt, init)!
	} else {
		compiler, linker := abi_compiler(build)!
		mut flags := ['-static', '-O2']
		if build.family in ['posix-timer', 'socket-io', 'terminal-jobs'] { flags << '-pthread' }
		if build.arch == 'aarch64' && build.family != 'syscall-policy' {
			flags << '-fno-stack-protector'
		}
		flags << ['-Wall', '-Wextra', '-Werror']
		if build.family == 'syscall-policy' { flags << '-pthread' }
		if build.expect_readable { flags.insert(0, '-DEXECUTE_ONLY_EXPECT_READABLE') }
		mut input := if build.source != '' {
			build.source
		} else {
			root() + '/tests/' + build.family + '/guest.c'
		}
		if spec.module_name != '' && build.source == '' {
			module_path := root() + '/tests/' + build.family + '/' + spec.module_name
			input = state + '/fixture.o'
			if build.family == 'terminal-jobs' { input = state + '/guest.o' }
			if build.family == 'procfs-mount' {
				mut generate := [root() + '/build-support/compile-v-module', module_path,
					state + '/fixture.c', '--arch',
					if build.arch == 'aarch64' { 'arm64' } else { 'amd64' }, '-d', 'nofloat']
				if build.case_name == 'reuse' { generate << ['-d', 'proc_mount_reuse_only'] }
				run(generate)!
				run([...compiler, '-O2', '-fno-stack-protector', '-Wall', '-Wextra', '-Werror',
					'-D_GNU_SOURCE', '-fno-strict-aliasing', '-Wno-unused-function',
					'-Wno-unused-parameter', '-I', module_path, '-c', state + '/fixture.c', '-o',
					input])!
				flags = ['-static']
			} else {
				mut compile_flags := [...compiler, ...flags, ...linker]
				if build.family in ['dumpability', 'shared-streams', 'posix-timer', 'socket-io',
					'clock-control'] {
					flags << ['-D_GNU_SOURCE', '-fno-strict-aliasing']
					compile_flags = [...compiler, ...flags, ...linker]
				}
				compile_module(module_path, input, build.arch, compile_flags)!
			}
		}
		mut objects := [input]
		if build.source == '' && spec.module_name == '' && build.family in [
			'stack-policy',
			'syscall-policy',
		] {
			objects << root() + '/tests/' + build.family + '/switch.S'
		}
		command = [...compiler, ...flags, ...objects, ...linker, '-o', init]
		run(command)!
	}
	abi_validate_elf(init, build.arch)!
	os.chmod(init, 0o755)!
	rootfs := state + '/rootfs'
	mut directories := ['root', 'sbin', 'proc', 'sys']
	if build.family != 'clock-control' { directories << 'dev' }
	if build.family in ['execute-only', 'procfs-mount'] { directories << 'tmp' }
	for name in directories { os.mkdir_all(rootfs + '/' + name)! }
	os.cp(init, rootfs + '/sbin/init')!
	if build.baseline {
		os.write_file(rootfs + if build.family == 'socket-io' {
			'/socket-io-baseline'
		} else {
			'/proc-leaks-baseline'
		}, '')!
	}
	if build.family == 'procfs-allocs' {
		os.mkdir(rootfs + '/many')!
		for index in 0 .. 1400 { os.write_file(rootfs + '/many/f${index:04}', '')! }
	}
	mut env := policyhost.environment()
	env['COPYFILE_DISABLE'] = '1'
	fixturehost.inherited_command_environment_preferred(['tar', '--format=ustar', '-cf',
		state + '/initramfs.tar', '-C', rootfs, '.'], env, policyhost.caller_arch())!
	mut receipt := {
		'arch':                         json2.Any(if build.arch == 'aarch64' {
			'aarch64'
		} else {
			'amd64'
		})
		'suite':                        json2.Any(build.family)
		'timeout':                      json2.Any(build.timeout)
		'independent_C_control':        json2.Any(build.source != '')
		'source_sha256':                abi_source_hashes(spec, build.source)!
		'fixture_elf_sha256':           json2.Any(digest(init)!)
		'controller_executable_sha256': json2.Any(digest(os.executable())!)
		'native_link_command':          json2.Any(command.map(json2.Any(it)))
		'runner_sha256':                json2.Any(digest(root() + '/tests/native-guest-tools/guesthost/abi.v')!)
		'suite_registry_sha256':        json2.Any(digest(root() + '/tests/native-guest-tools/guesthost/abi_suites.v')!)
		'supervisor_sha256':            json2.Any(digest(root() + '/tests/native-guest-tools/guesthost/abi_pty.v')!)
		'image_policy_sha256':          json2.Any(digest(root() + '/tests/native-guest-tools/guesthost/abi_image.v')!)
		'baseline':                     json2.Any(build.baseline)
		'case':                         json2.Any(build.case_name)
		'kernel_rebuilt_by_runner':     json2.Any(false)
	}
	if build.family == 'execute-only' {
		receipt['expect_readable'] = json2.Any(build.expect_readable)
	}
	if build.prebuilt != '' { receipt['prebuilt_init_sha256'] = json2.Any(digest(build.prebuilt)!) }
	os.write_file(state + '/inputs.json', json2.encode(json2.Any(receipt), prettify: true) + '\n')!
	return init
}

fn abi_launch(init string, state string, kernel string, runner_root string, build AbiBuild) !Launch {
	if build.family == 'procfs-mount' {
		cache := os.getenv_opt('VINIX_LIMINE_CACHE') or { runner_root + '/build-amd64-iso/limine' }
		if build.arch != 'aarch64' && os.is_dir(cache) {
			os.mkdir_all(state + '/iso-build')!
			os.cp_all(cache, state + '/iso-build/limine', false)!
		}
	}
	configured := launch_at(init, state + '/initramfs.tar', state, os.dir(os.dir(kernel)), build.arch, false, runner_root)!
	mut command := configured.command.clone()
	command[command.index('-m') + 1] = if build.arch == 'aarch64' { '2048' } else { '1024' }
	if build.family == 'terminal-jobs' { command[command.index('-smp') + 1] = '4' }
	if build.arch == 'x86_64' {
		command[command.index('-accel') + 1] = os.getenv_opt('VINIX_QEMU_ACCEL') or { 'tcg' }
		firmware := os.getenv_opt('VINIX_OVMF_CODE_AMD64') or {
			os.dir(os.dir(command[0])) + '/share/qemu/edk2-x86_64-code.fd'
		}
		command[command.index('-drive') + 1] = 'if=pflash,format=raw,unit=0,readonly=on,file=' + firmware
		command[command.index('-serial') + 1] = 'stdio'
		command << ['-netdev', 'user,id=net0', '-device', 'e1000,netdev=net0,mac=52:54:00:12:34:56',
			'-object', 'filter-dump,id=vinixdump,netdev=net0,file=' + state +
				if build.family == 'network-options' { '/network.pcap' } else { '/unused.pcap' }]
	}
	if build.arch == 'aarch64' {
		if os.getenv('VINIX_QEMU_EXTRA') != '' {
			command.insert(1, hosttest.shell_split(os.getenv('VINIX_QEMU_EXTRA'))!)
		}
		// The imported ARM runner always supplied a private 64 MiB ext2
		// /root. Keep that filesystem and its command line for these tests.
		abi_home_volume(state)!
		abi_arm_config(state, runner_root)!
		command.insert(command.index('-device'), ['-drive', 'if=none,format=raw,file=' + state +
			'/root.ext2,id=abi-home', '-device', 'virtio-blk-device,drive=abi-home'])
	}
	if build.family == 'securelevel' && build.arch != 'aarch64' {
		// The fixture opens a writable disk before raising the secure level.
		// Own a disposable disk; the boot ISO stays read-only.
		disk := state + '/policy-disk.img'
		os.write_file(disk, '')!
		if unsafe { C.truncate(disk.str, i64(64 * 1024 * 1024)) } < 0 { return posix_error() }
		at := command.index('-cdrom')
		command.insert(at, ['-drive', 'if=none,format=raw,file=' + disk + ',id=abi-disk', '-device',
			'virtio-blk-pci,drive=abi-disk'])
	}
	return Launch{command, configured.env}
}

pub fn abi_command(arguments []string, family string) int {
	result := abi_checked(arguments, family) or {
		eprintln(err.msg())
		if err.msg() == 'Guest run interrupted' { return 130 }
		return if err.code() == 2 { 2 } else { 1 }
	}
	return result
}

fn abi_checked(arguments []string, family string) !int {
	abi_spec(family)!
	mut options := [hosttest.Option{
		name:    '--arch'
		value:   true
		choices: if family == 'clock-control' {
			['aarch64']
		} else {
			['aarch64', 'amd64', 'x86_64']
		}
	}, hosttest.Option{ name: '--state-dir', value: true },
		hosttest.Option{ name: '--kernel-dir', value: true },
		hosttest.Option{ name: '--timeout', value: true }, hosttest.Option{ name: '--build-only' }]
	if family in ['socket-io', 'procfs-allocs'] { options << hosttest.Option{ name: '--baseline' } }
	if family in ['securelevel', 'execute-only'] {
		options << hosttest.Option{ name: '--source', value: true }
	}
	if family == 'execute-only' { options << hosttest.Option{ name: '--expect-readable' } }
	if family == 'procfs-mount' {
		options << [
			hosttest.Option{ name: '--case', value: true, choices: ['full', 'reuse'] },
			hosttest.Option{ name: '--work', value: true },
			hosttest.Option{ name: '--prebuilt-init', value: true },
		]
	}
	mut usage := 'Usage: tests/' + family + '/run [--arch aarch64|amd64] [--state-dir FRESH-DIR] [--kernel-dir DIR] [--timeout SECONDS] [--build-only]'
	if family in ['socket-io', 'procfs-allocs'] {
		usage += '\n  --baseline                  Report allocations without enforcing flatness.'
	}
	if family in ['securelevel', 'execute-only'] {
		usage += '\n  --source FILE               Compile an independent C control.'
	}
	if family == 'execute-only' {
		usage += '\n  --expect-readable           Verify the fallback without enhanced PAN.'
	}
	if family == 'procfs-mount' {
		usage += '\n  --case full|reuse           Select all checks or inactive-view reuse.\n  --work FRESH-DIR            Retain artifacts (alias of --state-dir).\n  --prebuilt-init FILE        Use an existing matching guest ELF.'
	}
	parsed := parse(arguments, options, []string{}, usage) or {
		return error_with_code(err.msg(), 2)
	}
	if parsed.has('--state-dir') && parsed.has('--work') {
		return error_with_code('choose --state-dir or --work', 2)
	}
	if parsed.has('--build-only') && !parsed.has('--state-dir') && !parsed.has('--work') {
		return error_with_code('--build-only needs --state-dir or --work to retain artifacts', 2)
	}
	default_timeout := strconv.atoi(if parsed.has('--timeout') {
		'300'
	} else {
		os.getenv_opt('VINIX_QEMU_TIMEOUT') or { '300' }
	}) or {
		return error_with_code('invalid VINIX_QEMU_TIMEOUT', 2)
	}
	timeout := parsed.integer('--timeout', default_timeout) or { return error_with_code('invalid --timeout', 2) }
	if timeout <= 0 { return error_with_code('timeout must be positive', 2) }
	source := if parsed.has('--source') { path_option(parsed, '--source', '')! } else { '' }
	if source != '' && !os.is_file(source) {
		return error_with_code('--source must name an existing C control', 2)
	}
	arch := if parsed.value('--arch', 'aarch64') == 'aarch64' { 'aarch64' } else { 'x86_64' }
	runner_root := resolve(os.getenv_opt('VINIX_VM_RUNNER_ROOT') or { root() })!
	build := AbiBuild{
		family:          family
		arch:            arch
		source:          source
		expect_readable: parsed.has('--expect-readable')
		baseline:        parsed.has('--baseline')
		case_name:       parsed.value('--case', 'full')
		runner_root:     runner_root
		prebuilt:        if parsed.has('--prebuilt-init') {
			path_option(parsed, '--prebuilt-init', '')!
		} else {
			''
		}
		timeout:         timeout
	}
	mut kernel := ''
	if !parsed.has('--build-only') {
		kernel = if parsed.has('--kernel-dir') {
			path_option(parsed, '--kernel-dir', '')! + '/bin/vinix'
		} else if arch == 'aarch64' {
			resolve(os.getenv_opt('VINIX_KERNEL_DIR') or { root() + '/kernel' })! + '/bin/vinix'
		} else {
			resolve(os.getenv_opt('VINIX_AMD64_KERNEL') or {
				root() + if family == 'procfs-mount' {
					'/build-amd64-kernel/bin/vinix'
				} else {
					'/kernel/bin/vinix'
				}
			})!
		}
		abi_validate_elf(kernel, arch) or {
			if parsed.has('--kernel-dir') { return error_with_code(err.msg(), 2) }
			return err
		}
	}
	state_arg := parsed.value('--state-dir', parsed.value('--work', ''))
	state := hosttest.work_dir(state_arg, 'vinix-' + family + '-vm-')!
	defer { if state_arg == '' { hosttest.remove_work_dir(state) or { eprintln(err.msg()) } } }
	build_abi_guest(state, build)!
	if parsed.has('--build-only') {
		println('Guest artifacts: ' + state)
		return 0
	}
	return run_abi_guest(state, kernel, build, true)!
}

pub fn run_abi_guest(state string, source_kernel string, build AbiBuild, inherit bool) !int {
	spec := abi_spec(build.family)!
	abi_validate_elf(source_kernel, build.arch)!
	os.mkdir_all(state + '/kernel/bin')!
	kernel := state + '/kernel/bin/vinix'
	os.cp(source_kernel, kernel)!
	runner_root := if build.runner_root != '' { build.runner_root } else { root() }
	configured := abi_launch(state + '/init', state, kernel, runner_root, build)!
	mut receipt := (hosttest.decode_json(os.read_file(state + '/inputs.json')!)!).as_map()
	receipt[if build.family == 'securelevel' {
		'immutable_kernel_sha256'
	} else {
		'selected_kernel_sha256'
	}] = json2.Any(digest(kernel)!)
	receipt['command'] = json2.Any(configured.command.map(json2.Any(it)))
	receipt['iso_sha256'] = json2.Any(digest(state + '/test.iso')!)
	receipt['kernel_command_line'] = json2.Any(os.getenv('VINIX_CMDLINE'))
	if build.arch == 'aarch64' {
		receipt['initial_ext2_sha256'] = json2.Any(digest(state + '/root.ext2')!)
	}
	os.write_file(state + '/inputs.json', json2.encode(json2.Any(receipt), prettify: true) + '\n')!
	println('Guest artifacts: ' + state)
	expected := if build.family == 'procfs-mount' && build.case_name == 'reuse' {
		[spec.features[2], spec.pass]
	} else {
		[...spec.features, spec.pass]
	}
	result := boot_abi(configured.command, configured.env, state, build.arch, expected, spec.pass, spec.failures, build.timeout, inherit)!
	receipt['native_guest_returncode'] = json2.Any(result)
	os.write_file(state + '/inputs.json', json2.encode(json2.Any(receipt), prettify: true) + '\n')!
	return result
}
