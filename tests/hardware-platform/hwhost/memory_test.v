// SPDX-License-Identifier: GPL-2.0-or-later
module hwhost

fn test_workload_memory_is_explicit_for_both_architectures() {
	assert Run{}.memory_mib == 1024
	for arch in ['aarch64', 'x86_64'] {
		host := Host{arch: arch, qemu: '/qemu'}
		for memory in [1024, 3072] {
			command := qemu_command(host, Scenario{}, [], '/state', 0, memory)!
			assert command.filter(it == '-m').len == 1
			assert command[command.index('-m') + 1] == memory.str()
		}
		for memory in [0, -1] {
			mut rejected := false
			qemu_command(host, Scenario{}, [], '/state', 0, memory) or { rejected = true }
			assert rejected
		}
	}
}
