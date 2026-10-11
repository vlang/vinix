// SPDX-License-Identifier: GPL-2.0-or-later
module compathost

import guesthost

fn test_optin_counted_markers_and_fatal_override() {
	for arch in ['aarch64', 'x86_64'] {
		normal := stack_guard_policy(arch, false, false)
		assert normal.expected.len == 3 && normal.expected.last() == normal.pass
		assert guesthost.abi_verdict(normal.expected.join('\n'), arch, normal.expected, normal.failures, true, false, 0) == 0
		assert guesthost.abi_verdict(normal.expected.join('\n') + '\n' + normal.pass, arch, normal.expected, normal.failures, true, false, 0) == 1
		runtime := stack_guard_policy(arch, true, false)
		assert runtime.expected == ['STACK-GUARD GUEST: PASS']
		fatal := stack_guard_policy(arch, true, true)
		assert fatal.expected[0] == 'STACK-GUARD state sp=0x'
		assert fatal.pass == 'STACK-GUARD FATAL ' + if arch == 'aarch64' { 'emergency-stack exhaustion' } else { 'kernel-stack exhaustion' }
		assert guesthost.abi_verdict(fatal.expected.join('\n') + '\nFATAL EXCEPTION\nKERNEL PANIC', arch, fatal.expected, fatal.failures, true, false, 0) == 0
		assert guesthost.abi_verdict(fatal.expected.join('\n') + '\nSTACK-GUARD GUEST: PASS', arch, fatal.expected, fatal.failures, true, false, 0) == 1
	}
	assert mitigation_policy(false).expected.len == 5
	assert mitigation_policy(true).expected == ['QEMU CORE PASS: x86-64 TLS descriptors, LDT and 32-bit code', 'CPU MITIGATION GUEST: PASS']
}

fn test_optin_x86_verdict_status_and_finish_contract() {
	assert guesthost.abi_verdict('PASS', 'x86_64', ['PASS'], [], true, true, 73) == 0
	assert guesthost.abi_verdict('PASS', 'x86_64', ['PASS'], [], false, false, 0) == 1
	assert guesthost.abi_verdict('PASS', 'aarch64', ['PASS'], [], true, true, 0) == 1
	assert guesthost.abi_verdict('PASS', 'aarch64', ['PASS'], [], true, false, 73) == 1
}

fn test_optin_launch_topology_and_acpi_recipe() {
	base := ['/usr/bin/qemu', '-m', '1024', '-smp', '2', '-cpu', 'max', '-serial', 'mon:stdio']
	argv := optin_launch(base, 'x86_64', '/state', 'qemu64', '4,sockets=1,cores=2,threads=2', 'VINIX_OVMF_CODE')
	assert argv[..base.len] == ['/usr/bin/qemu', '-m', '1024', '-smp', '4,sockets=1,cores=2,threads=2', '-cpu', 'qemu64', '-serial', 'stdio']
	assert argv[base.len..] == ['-netdev', 'user,id=net0', '-device', 'e1000,netdev=net0,mac=52:54:00:12:34:56', '-object', 'filter-dump,id=vinixdump,netdev=net0,file=/state/unused.pcap']
	assert base[4] == '2'
	assert acpi_build_command('/kernel', '/v', 'aarch64', '/ld', '/ar') == ['make', '-C', '/kernel', '-j4', 'CC=clang', 'V=/v', 'ARCH=aarch64', 'ACPI_SYNC_TEST=1', 'STACK_GUARD_TEST=0', 'AR=/ar', 'LIMINE_MP=1', 'LD_AARCH64=/ld']
	assert acpi_build_command('/kernel', '/v', 'x86_64', '/ld', '').last() == 'LD_X86_64=/ld'
	assert 'LIMINE_MP=1' !in acpi_build_command('/kernel', '/v', 'x86_64', '/ld', '')
}
