// SPDX-License-Identifier: GPL-2.0-or-later
module systemhost

pub fn features(family string) []string {
	return match family {
		'security' {
			['OPENBSD SECURITY PASS: pledge promises and violations',
				'OPENBSD SECURITY PASS: pledge proc, prot_exec and tmppath',
				'OPENBSD SECURITY PASS: pledge sockets and descriptor passing',
				'OPENBSD SECURITY PASS: pledge execpromises',
				'OPENBSD SECURITY PASS: unveil hides and limits paths',
				'OPENBSD SECURITY PASS: unveil across exec and pledge',
				'OPENBSD SECURITY PASS: signal frames are signed',
				'OPENBSD SECURITY PASS: process ids are random',
				'OPENBSD SECURITY PASS: the program break is random',
				'OPENBSD SECURITY PASS: minherit and fork-time wiping',
				'OPENBSD SECURITY PASS: ports, sequence numbers and IP IDs are random',
				'OPENBSD SECURITY PASS: memory layouts are private',
				'OPENBSD SECURITY PASS: read-only files stay read-only',
				'OPENBSD SECURITY PASS: immutable and append-only files',
				'OPENBSD SECURITY PASS: bad user pointers fault rather than panic',
				"OPENBSD SECURITY PASS: a process's buffers are never taken for the kernel's"]
		}
		'mount' {
			['MOUNT POLICY PASS: noexec images, scripts, symlinks and ELF interpreters',
				'MOUNT POLICY PASS: noexec mmap and protection ceilings survive split, fork and remap',
				'MOUNT POLICY PASS: bind aliases retain independent policy through cwd, fds and proc links',
				'MOUNT POLICY PASS: nodev blocks character and block devices, with O_PATH and ordinary files usable',
				'MOUNT POLICY PASS: namespace remounts and self binds preserve mount identity',
				'MOUNT POLICY PASS: W^X exceptions require administrator launch or executable mount policy',
				'MOUNT POLICY PASS: nested shared mounts retain the alias used to enter them',
				'MOUNT POLICY PASS: bounded mount context overflow fails closed with ELOOP',
				'MOUNT POLICY PASS: shared cwd, root and mount moves keep node and policy snapshots consistent']
		}
		'ipv6' {
			['IPV6 PASS: TCP and UDP loopback, names and tcp6', 'IPV6 PASS: mapped addresses and V6ONLY',
				'IPV6 PASS: IGMP multicast interface=1', 'IPV6 PASS: MLD multicast interface=1',
				'IPV6 PASS: IGMP multicast interface=2', 'IPV6 PASS: MLD multicast interface=2',
				'IPV6 PASS: physical TCP/UDP and SLAAC', 'IPV6 PASS: link-local interface scopes',
				'IPV6 PASS: repeated memberships and close stay flat']
		}
		'numa' {
			['QEMU NUMA PASS: sysfs reports two nodes, two CPUs each, 1 GiB each',
				'QEMU NUMA PASS: getcpu reports the node of the CPU a thread is pinned to',
				'QEMU NUMA PASS: mempolicy reports and validates what it is given',
				'QEMU NUMA PASS: a bound process takes its pages from the node it asked for',
				'QEMU NUMA PASS: mbind places the pages of the range it named',
				'QEMU NUMA PASS: first touch takes pages from the node that faulted them']
		}
		else { []string{} }
	}
}

pub fn numa_kernel_markers() []string {
	return ['numa: 2 memory nodes from acpi', 'numa: node 0 holds cpus 0x3',
		'numa: node 1 holds cpus 0xc', 'numa:   node 0 distances 10 20',
		'numa:   node 1 distances 20 10']
}
