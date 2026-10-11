// SPDX-License-Identifier: GPL-2.0-or-later
module systemhost

import diskhost
import fixturehost
import guesthost
import hosttest
import json2
import math
import os
import policyhost
import strconv
import time

pub const pci_config_marker = 'pci: ARM checked config widths, bounds and interrupt masks passed'
pub const pci_topology_marker = 'pci: native bounded topology, read-only capabilities and rollback passed; no pages or heap objects retained'
pub const pci_mmap_marker = 'mmap: retained fault owners, concurrent removal and deferred reclamation passed; no pages retained'
pub const pci_init_marker = 'PCI ARM GUEST: Linux ABI PID1 PASS'

pub struct PciPolicy {
pub:
	config   bool = true
	mmap     bool
	topology bool
}

pub fn pci_failed(text string, policy PciPolicy) bool {
	return ['KERNEL PANIC', 'FATAL EXCEPTION', 'PCI ARM GUEST: FAIL'].any(text.contains(it))
		|| (!policy.config && text.contains(pci_config_marker)) || (!policy.mmap && text.contains(pci_mmap_marker))
		|| (!policy.topology && text.contains(pci_topology_marker))
}

pub fn pci_ready(text string, policy PciPolicy) bool {
	return text.contains(pci_init_marker) && (!policy.config || text.contains(pci_config_marker))
		&& (!policy.mmap || text.contains(pci_mmap_marker)) && (!policy.topology || text.contains(pci_topology_marker))
}

fn pci_serial(path string) !string {
	return if os.exists(path) { guesthost.replacement_text(os.read_bytes(path)!) } else { '' }
}

fn pci_prepare(options guesthost.Options, state string, mut report map[string]json2.Any, mut commands [][]string) ![]string {
	qemu := os.find_abs_path_of_executable(options.value('--qemu', 'qemu-system-aarch64'))!
	share := os.dir(os.dir(qemu)) + '/share/qemu'
	sources := {
		'kernel':           options.value('--kernel', '')
		'firmware':         options.value('--firmware', share + '/edk2-aarch64-code.fd')
		'vars_template':    options.value('--vars-template', share + '/edk2-arm-vars.fd')
		'bootloader':       options.value('--bootloader', root() + '/boot-image/limine-bin/BOOTAA64.EFI')
		'init_source':      root() + '/tests/pci-config/armfixture/core.v'
		'init_abi':         root() + '/tests/pci-config/armfixture/pci-arm-fixture-native-abi.h'
		'init_syscall':     root() + '/tests/pci-config/armfixture/syscall3.S'
		'module_generator': root() + '/tests/linuxkpi/generate_module.v'
	}
	mut copies := map[string]string{}
	mut inputs := map[string]json2.Any{}
	mut originals := map[string]json2.Any{}
	for name, original in sources {
		source := resolve(original)!
		if !os.is_file(source) { return error('required read-only input unavailable: ' + source) }
		before := hosttest.sha(source)!
		target := state + '/inputs/' + if name.starts_with('init_') {
			'armfixture/' + os.file_name(source)
		} else {
			name
		}
		diskhost.mkdir(os.dir(target))!
		os.cp(source, target)!
		if hosttest.sha(source)! != before || hosttest.sha(target)! != before {
			return error('input changed while freezing: ' + source)
		}
		copies[name] = target
		originals[name] = json2.Any(source)
		inputs[name] = json2.Any({
			'path':   json2.Any(target)
			'sha256': json2.Any(before)
		})
	}
	cc := os.find_abs_path_of_executable(options.value('--cc', 'clang'))!
	ld := os.find_abs_path_of_executable('ld.lld')!
	sdk := resolve(options.value('--sysroot', os.getenv_opt('VINIX_AARCH64_SYSROOT') or { root() + '/build-aarch64-userland/sysroot' }))!
	diskhost.mkdir(state + '/rootfs/sbin')!
	for directory in ['dev', 'proc', 'sys', 'root', 'tmp'] {
		diskhost.mkdir(state + '/rootfs/' + directory)!
	}
	generated := state + '/arm_init.c'
	init := state + '/rootfs/sbin/init'
	build := [root() + '/build-support/compile-v-module', state + '/inputs/armfixture', generated,
		'--arch', 'arm64', '-d', 'nofloat']
	compile := [cc, '--target=aarch64-linux-musl', '--sysroot=' + sdk, '-std=gnu11', '-O2', '-Wall',
		'-Wextra', '-Werror', '-nostdlib', '-ffreestanding', '-fno-stack-protector', '-fno-pie',
		'-Wno-unused-function', '-Wno-unused-parameter', '-I', state + '/inputs/armfixture', '-c',
		generated, '-o', state + '/arm_init.o']
	syscall := [cc, '--target=aarch64-linux-musl', '-c', copies['init_syscall'], '-o',
		state + '/syscall3.o']
	link := [ld, '-m', 'aarch64elf', '--nostdlib', '-static', '-e', '_start', '--build-id=none',
		state + '/arm_init.o', state + '/syscall3.o', '-o', init]
	mut log := os.create(state + '/preparation.log')!
	defer { log.close() }
	for command in [build, compile, syscall, link] {
		commands << command
		result := capture(command)!
		log.write_string(result.stdout + result.stderr)!
		log.flush()
		if result.status != 0 {
			return error('Preparation command failed: ' + hosttest.shell_join(command) + '\n' + result.stdout + result.stderr)
		}
	}
	for name, copy in copies {
		record := inputs[name]!.as_map()
		if hosttest.sha(copy)! != record['sha256']!.str() || hosttest.sha(originals[name]!.str())! != record['sha256']!.str() {
			return error('fixture input changed during generation: ' + name)
		}
	}
	os.chmod(init, 0o755)!
	archive := guesthost.archive_tree(state + '/rootfs', state + '/initramfs.tar')!
	conf := state + '/limine.conf'
	os.write_file(conf, 'timeout: 0\nverbose: yes\n\n/Vinix PCI configuration\n    protocol: limine\n    kernel_path: boot():/boot/vinix\n    module_path: boot():/boot/initramfs.tar\n    resolution: 1024x768x32\n    kaslr: no\n    cmdline: vinix.qemu_platform=1\n')!
	disk := state + '/boot.img'
	diskhost.sparse_file(disk, 256 * 1024 * 1024)!
	mut populate := [[os.find_abs_path_of_executable('mformat')!, '-F', '-i', disk, '::']]
	for directory in ['::/EFI', '::/EFI/BOOT', '::/boot'] {
		populate << [os.find_abs_path_of_executable('mmd')!, '-i', disk, directory]
	}
	for row in [[copies['bootloader'], '::/EFI/BOOT/BOOTAA64.EFI'],
		[copies['kernel'], '::/boot/vinix'], [conf, '::/boot/limine.conf'],
		[archive, '::/boot/initramfs.tar']] {
		populate << [os.find_abs_path_of_executable('mcopy')!, '-i', disk, row[0], row[1]]
	}
	for command in populate {
		commands << command
		result := capture(command)!
		log.write_string(result.stdout + result.stderr)!
		if result.status != 0 {
			return error('Boot image command failed: ' + hosttest.shell_join(command))
		}
	}
	os.cp(copies['vars_template'], state + '/efivars.fd')!
	for name, path in {
		'generated_init_source': generated
		'init':                  init
		'initramfs':             archive
		'limine_conf':           conf
	} {
		inputs[name] = json2.Any({
			'path':   json2.Any(path)
			'sha256': json2.Any(hosttest.sha(path)!)
		})
	}
	report['inputs'] = json2.Any(inputs)
	report['original_input_paths'] = json2.Any(originals)
	return [qemu, '-machine', 'virt,gic-version=3', '-accel', 'tcg', '-cpu', 'max', '-m', '1024',
		'-smp', '4', '-display', 'none', '-monitor', 'none', '-device', 'ramfb', '-drive',
		'if=pflash,format=raw,unit=0,readonly=on,file=' + copies['firmware'], '-drive',
		'if=pflash,format=raw,unit=1,file=' + state + '/efivars.fd', '-drive',
		'if=none,id=bootdisk,format=raw,file=' + disk, '-device', 'virtio-blk-pci,drive=bootdisk',
		'-device', 'e1000', '-nic', 'none', '-serial', 'file:' + state + '/serial.log', '-no-reboot']
}

fn pci_observe(argv []string, state string, seconds f64, policy PciPolicy, mut report map[string]json2.Any) ! {
	mut child := fixturehost.spawn_logged(argv, policyhost.environment(), policyhost.caller_arch(), '', state + '/qemu.log')!
	defer {
		child.close_after(5)
		report['owned_process_exit'] = json2.Any(child.wait_for(0, policyhost.command_interrupted) or { -9 })
	}
	report['owned_pid'] = json2.Any(child.pid)
	report['status'] = json2.Any('running')
	hosttest.write_json(state + '/result.json', json2.Any(report))!
	serial := state + '/serial.log'
	deadline := time.sys_mono_now() + u64(seconds * 1e9)
	mut failure_started := u64(0)
	mut passed_started := u64(0)
	for time.sys_mono_now() < deadline || failure_started != 0 {
		policyhost.command_checkpoint()!
		text := pci_serial(serial)!
		if pci_failed(text, policy) || failure_started != 0 {
			if failure_started == 0 { failure_started = time.sys_mono_now() }
			if time.sys_mono_now() - failure_started >= u64(time.second) || child.poll()! {
				return error('ARM guest failed; see ' + serial)
			}
		} else if pci_ready(text, policy) {
			if passed_started == 0 { passed_started = time.sys_mono_now() }
			if time.sys_mono_now() - passed_started >= u64(time.second) {
				if child.poll()! { return error('QEMU exited after the guest marker') }
				child.close_after(5)
				if pci_failed(pci_serial(serial)!, policy) {
					return error('ARM guest failed during final drain; see ' + serial)
				}
				report['serial_sha256'] = json2.Any(hosttest.sha(serial)!)
				report['status'] = json2.Any('passed')
				println(if policy.config {
					'ARM PCI guest: PASS (ECAM/full-DAIF controller fixture, Linux ABI PID1)'
				} else {
					'Default ARM guest: PASS (Linux ABI PID1; config fixture disabled)'
				})
				println('Serial log: ' + serial)
				return
			}
		}
		if child.poll()! { return error('QEMU exited; see ' + state + '/qemu.log') }
		time.sleep(100 * time.millisecond)
	}
	return error('ARM guest timed out; see ' + serial)
}

fn pci_arm(args []string) !int {
	options := parse(args, [hosttest.Option{ name: '--kernel', value: true },
		hosttest.Option{ name: '--state-dir', value: true },
		hosttest.Option{ name: '--qemu', value: true }, hosttest.Option{ name: '--cc', value: true },
		hosttest.Option{ name: '--sysroot', value: true },
		hosttest.Option{ name: '--firmware', value: true },
		hosttest.Option{ name: '--vars-template', value: true },
		hosttest.Option{ name: '--bootloader', value: true },
		hosttest.Option{ name: '--timeout', value: true }, hosttest.Option{ name: '--no-config-test' },
		hosttest.Option{ name: '--mmap-lease-test' }, hosttest.Option{ name: '--pci-topology-test' },
		hosttest.Option{ name: '--build-only' }], [], 'Usage: arm_vm --kernel ELF --state-dir NEW_DIR [--timeout 120] [--no-config-test]')!
	required(options, ['--kernel', '--state-dir'])!
	seconds := strconv.atof64(options.value('--timeout', '120')) or { return argument('--timeout must be finite and positive') }
	if math.is_nan(seconds) || math.is_inf(seconds, 0) || seconds <= 0 || seconds > 9e9 {
		return argument('--timeout must be finite and positive')
	}
	state := resolve(options.value('--state-dir', ''))!
	if os.exists(state) || os.is_link(state) { return error('Use a fresh state directory') }
	diskhost.mkdir(state)!
	policy := PciPolicy{!options.has('--no-config-test'), options.has('--mmap-lease-test'), options.has('--pci-topology-test')}
	mut report := {
		'status':                     json2.Any('preparing')
		'state_dir':                  json2.Any(state)
		'config_test_expected':       json2.Any(policy.config)
		'mmap_lease_test_expected':   json2.Any(policy.mmap)
		'pci_topology_test_expected': json2.Any(policy.topology)
		'configured_cpus':            json2.Any(4)
		'scope':                      json2.Any((if policy.mmap {
			'Native mapping races and temporary page/heap recovery with a resident actor; '
		} else {
			''
		}) + (if policy.config {
			'ECAM reads and full-DAIF controller vectors; '
		} else {
			'Linux ABI startup; '
		}) + 'configured QEMU CPUs do not prove native SMP.')
	}
	mut commands := [][]string{}
	defer {
		hosttest.write_json(state + '/result.json', json2.Any(report)) or { eprintln(err.msg()) }
		hosttest.write_json(state + '/commands.json', json2.Any(commands.map(json2.Any(hosttest.strings(it))))) or { eprintln(err.msg()) }
	}
	argv := pci_prepare(options, state, mut report, mut commands) or {
		report['status'] = json2.Any('failed')
		report['error'] = json2.Any(err.msg())
		return err
	}
	commands << argv
	if options.has('--build-only') {
		report['status'] = json2.Any('prepared')
		return 0
	}
	pci_observe(argv, state, seconds, policy, mut report) or {
		report['status'] = json2.Any('failed')
		report['error'] = json2.Any(err.msg())
		return err
	}
	return 0
}
