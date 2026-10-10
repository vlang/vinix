// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// Frequency control on AArch64: the cluster DVFS of Apple's SoCs.
//
// An AArch64 CPU has no register that says how fast it runs or that changes
// it; that is the SoC's business. On Apple's SoCs each cluster of cores has a
// register block for it, driven as apple_dvfs_arm64.v describes, and the
// device tree says where the blocks are and what their states mean, in the
// bindings Linux's apple-soc-cpufreq.c reads:
//
//	/cpus/cpu@N
//	    performance-domains = <&cluster>     its cluster's register block
//	    operating-points-v2 = <&table>       that cluster's operating points
//	cluster: compatible "apple,t8103-cluster-cpufreq" (or t8112, or only
//	         "apple,cluster-cpufreq"), reg
//	table:   one child per point, with opp-hz and opp-level (the p-state)
//
// One policy is made per cluster, since its cores change speed together.
//
// It is off unless vinix.apple_cpufreq=1 is on the command line. It has not
// been run on a machine: there is none to run it on where this is written,
// and a wrong write to these registers stops a core rather than failing. The
// sequence is tested against a model of the registers on the host
// (tests/cpu-power), which shows that it does what Linux's does, and not that
// either is right for a given board. A device tree in Apple's own format,
// which this kernel also boots from, has none of the properties above, and
// then nothing is found.
//
// Everywhere else -- every virtual machine -- there is no driver, and nothing
// that says what the frequency is: the files in /sys read 0 and "<unknown>".
@[has_globals]
module cpufreq

import devcore
import devicetree
import memory
import aarch64.kio
import aarch64.timer

const max_clusters = 8

// Policy.unit of a CPU that is in no cluster.
const no_cluster = u32(0xffffffff)

// More than any Apple cluster has: the p-state field is five bits wide.
const max_points = 32

struct Cluster {
mut:
	// Its device tree node, which is what its CPUs name it by.
	node voidptr
	info DvfsInfo
	// Operating points in rising order of frequency.
	points [max_points]DvfsPoint
	count  int
	cpus   u64
	// The p-state last asked for, plus one. Zero before the first.
	asked    u32
	failures u32
}

__global (
	cpufreq_apple_clusters [max_clusters]Cluster
	cpufreq_apple_io       [max_clusters]DvfsIo
	cpufreq_apple_count    int
)

fn mmio_read(context voidptr, offset u32) u64 {
	return kio.mmin64(unsafe { &u64(u64(context) + offset) })
}

fn mmio_write(context voidptr, offset u32, value u64) {
	kio.mmout64(unsafe { &u64(u64(context) + offset) }, value)
}

fn mmio_pause(_ voidptr, us u32) {
	timer.busywait_us(us)
}

// The driver's apply(): the operating point for what the governor asked for,
// under the allowed ceiling, written if it is not the one already asked for.
// With the lock.
fn apple_apply(_ int, mut policy Policy) {
	if policy.unit >= u32(cpufreq_apple_count) {
		// A CPU no cluster speaks for.
		return
	}
	mut cluster := unsafe { &cpufreq_apple_clusters[policy.unit] }
	_, highest := allowed_range(policy.limits, thermal_limit())
	step := dvfs_point(&cluster.points[0], cluster.count, policy.wanted_khz, highest)
	if step < 0 {
		return
	}
	pstate := cluster.points[step].pstate
	if cluster.asked == pstate + 1 {
		return
	}
	match dvfs_set(&cpufreq_apple_io[policy.unit], cluster.info, pstate) {
		.done {
			cluster.asked = pstate + 1
		}
		.busy, .invalid {
			// Tried again at the next sample. Said once, not ten times a
			// second.
			cluster.failures++
			if cluster.failures == 1 {
				C.kprintf(c'cpufreq: cluster %llu did not take p-state %llu\n', u64(policy.unit),
					u64(pstate))
			}
		}
	}
}

// The driver's current(): the frequency of the p-state the cluster reports.
fn apple_current(_ int, policy &Policy) u64 {
	if policy.unit >= u32(cpufreq_apple_count) {
		return 0
	}
	cluster := unsafe { &cpufreq_apple_clusters[policy.unit] }
	return dvfs_khz(&cluster.points[0], cluster.count, dvfs_current(&cpufreq_apple_io[policy.unit],
		cluster.info))
}

// The logical number of the CPU a device tree node's `reg` names, or -1.
// Matched on the affinity bits of MPIDR, never on enumeration order.
fn logical_cpu(reg u64) int {
	for entry in cpu_locals {
		if entry.mpidr & u64(0xff00ffffff) == reg & u64(0xff00ffffff) {
			return int(entry.cpu_number)
		}
	}
	return -1
}

// The cluster `domain` is, added if this is the first CPU to name it. -1 if
// it cannot be used.
fn cluster_of(domain &devicetree.DTNode, table &devicetree.DTNode) int {
	for i in 0 .. cpufreq_apple_count {
		if cpufreq_apple_clusters[i].node == voidptr(domain) {
			return i
		}
	}
	if cpufreq_apple_count >= max_clusters {
		return -1
	}
	// The layout, from the first `compatible` entry that names one.
	names := devicetree.get_string_list(domain, 'compatible') or { return -1 }
	mut soc := DvfsSoc.other
	mut known := false
	for name in names {
		if !known {
			if found := dvfs_soc(name) {
				soc = found
				known = true
			}
		}
		unsafe { name.free() }
	}
	unsafe { names.free() }
	if !known {
		return -1
	}
	ranges := devicetree.get_translated_reg_ranges(domain) or { return -1 }
	if ranges.len == 0 || ranges[0].base == 0 {
		unsafe { ranges.free() }
		return -1
	}
	base := ranges[0].base
	size := if ranges[0].size == 0 { u64(0x1000) } else { ranges[0].size }
	unsafe { ranges.free() }

	index := cpufreq_apple_count
	mut cluster := unsafe { &cpufreq_apple_clusters[index] }
	cluster.count = 0
	for point in table.children {
		hz := devicetree.get_u64(point, 'opp-hz') or { continue }
		level := devicetree.get_u32(point, 'opp-level') or { continue }
		if cluster.count >= max_points || hz < 1000 {
			continue
		}
		cluster.points[cluster.count] = DvfsPoint{
			khz:    hz / 1000
			pstate: level
		}
		cluster.count++
	}
	if cluster.count == 0 {
		return -1
	}
	dvfs_sort(voidptr(&cluster.points[0]), cluster.count)
	cluster.node = voidptr(domain)
	cluster.info = dvfs_info(soc)
	cluster.cpus = 0
	cluster.asked = 0
	cpufreq_apple_io[index] = DvfsIo{
		read:    mmio_read
		write:   mmio_write
		pause:   mmio_pause
		context: voidptr(memory.map_mmio(base, size))
	}
	cpufreq_apple_count = index + 1
	return index
}

// Find the clusters and which CPUs are in each. True if there is one.
fn apple_discover() bool {
	cpus := devicetree.find_node('/cpus') or { return false }
	for node in cpus.children {
		domain := devicetree.get_phandle_node(node, 'performance-domains', 0) or { continue }
		table := devicetree.get_phandle_node(node, 'operating-points-v2', 0) or { continue }
		reg := devicetree.get_reg(node) or { continue }
		if reg.len == 0 {
			unsafe { reg.free() }
			continue
		}
		number := logical_cpu(reg[0])
		unsafe { reg.free() }
		if number < 0 || number >= max_cpus {
			continue
		}
		index := cluster_of(domain, table)
		if index < 0 {
			continue
		}
		cpufreq_apple_clusters[index].cpus |= u64(1) << u32(number)
	}
	return cpufreq_apple_count > 0
}

// Find this machine's frequency control. `cpus` is how many CPUs there are.
fn driver_start(cpus int) {
	cpufreq_driver.name = 'none'
	if devcore.boot_flag('vinix.apple_cpufreq=', false) {
		if devicetree.is_available() && apple_discover() {
			for i in 0 .. cpufreq_apple_count {
				cluster := unsafe { &cpufreq_apple_clusters[i] }
				top := cluster.points[cluster.count - 1].khz
				add_policy(cluster.cpus, Limits{
					hw_min_khz:  cluster.points[0].khz
					hw_max_khz:  top
					nominal_khz: top
				}, .ondemand, .balance_performance, u32(i))
				C.kprintf(c'cpufreq: cluster %llu: CPUs 0x%llx, %llu points, %llu to %llu kHz\n',
					u64(i), cluster.cpus, u64(cluster.count), cluster.points[0].khz, top)
			}
			cpufreq_driver.name = 'apple_dvfs'
			cpufreq_driver.settable = true
			cpufreq_driver.apply = apple_apply
			cpufreq_driver.current = apple_current
			print('cpufreq: Apple cluster DVFS by vinix.apple_cpufreq=1; untested on hardware\n')
		} else {
			print('cpufreq: vinix.apple_cpufreq=1, but the device tree describes no cluster\n')
		}
	}
	// A CPU no cluster speaks for, and every CPU of a machine without the
	// driver: nothing can be set, and nothing says how fast it runs.
	for cpu_number in 0 .. cpus {
		if cpu_number < max_cpus && cpufreq_policy_of[cpu_number] == 0 {
			add_policy(u64(1) << u32(cpu_number), Limits{}, .performance, .performance,
				no_cluster)
		}
	}
}
