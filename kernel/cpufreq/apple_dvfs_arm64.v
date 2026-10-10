// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// Apple SoC cluster DVFS: the register sequence that changes the performance
// state of a cluster of cores.
//
// Each cluster of an Apple SoC -- the efficiency cores, the performance cores
// -- has a block of registers through which its voltage and frequency are
// changed together. A state is a small number, the "p-state"; the frequency
// each one means comes from the device tree. This is a translation of Linux's
// drivers/cpufreq/apple-soc-cpufreq.c, whose sequence is short:
//
//	wait for the command register's BUSY bit to clear, 100 us at most
//	write the p-state into both of its fields, with SET
//
// and reading back the state in force is one read of the status register,
// whose field Apple moved between the M1 (t8103) and the M2 (t8112).
//
// The registers are reached through functions the caller supplies, so that
// the sequence -- the part that must match -- is tested on the host against a
// model of the register block, and the kernel supplies memory-mapped I/O. It
// is not known to be right on a machine: see driver_arm64.v.
module cpufreq

// APPLE_DVFS_CMD and its fields.
pub const dvfs_cmd = u32(0x20)
pub const dvfs_cmd_busy = u64(1) << 31
pub const dvfs_cmd_set = u64(1) << 25
pub const dvfs_cmd_ps2 = u64(0x1f) << 12
pub const dvfs_cmd_ps1 = u64(0x1f)

// APPLE_DVFS_STATUS.
pub const dvfs_status = u32(0x50)

// APPLE_DVFS_TRANSITION_TIMEOUT, and the pause between looks at BUSY, both
// in microseconds, as readq_poll_timeout_atomic() is called.
pub const dvfs_timeout_us = u32(100)
pub const dvfs_poll_us = u32(2)

pub enum DvfsSoc {
	t8103
	t8112
	// "apple,cluster-cpufreq" alone: a newer SoC whose status layout is not
	// known. The command register is the same.
	other
}

// apple_soc_cpufreq_info.
pub struct DvfsInfo {
pub:
	max_pstate u32
	// The current p-state's field in the status register. A zero mask means
	// the field is not known, and the command register is read instead.
	current_mask  u64
	current_shift u32
}

pub fn dvfs_info(soc DvfsSoc) DvfsInfo {
	return match soc {
		.t8103 {
			DvfsInfo{
				max_pstate:    15
				current_mask:  u64(0xf) << 4
				current_shift: 4
			}
		}
		.t8112 {
			DvfsInfo{
				max_pstate:    31
				current_mask:  u64(0x1f) << 5
				current_shift: 5
			}
		}
		.other {
			DvfsInfo{
				max_pstate: 15
			}
		}
	}
}

// Which layout a cluster node's `compatible` entry means: the match table of
// the Linux driver. The caller tries the entries in order, most specific
// first, as the device tree lists them.
pub fn dvfs_soc(compatible string) ?DvfsSoc {
	if compatible == 'apple,t8103-cluster-cpufreq' {
		return DvfsSoc.t8103
	}
	if compatible == 'apple,t8112-cluster-cpufreq' {
		return DvfsSoc.t8112
	}
	if compatible == 'apple,cluster-cpufreq' {
		return DvfsSoc.other
	}
	return none
}

// How a cluster's registers are reached: 64-bit reads and writes at an offset
// into its block, and a pause.
pub struct DvfsIo {
pub:
	read    fn (context voidptr, offset u32) u64         = unsafe { nil }
	write   fn (context voidptr, offset u32, value u64) = unsafe { nil }
	pause   fn (context voidptr, us u32) = unsafe { nil }
	context voidptr
}

pub enum DvfsResult {
	done
	// BUSY did not clear in time; nothing was written. The Linux driver
	// returns -EIO.
	busy
	// Not a p-state this SoC has; nothing was written.
	invalid
}

// Ask the cluster for `pstate`: apple_soc_cpufreq_set_target().
//
// The wait is readq_poll_timeout_atomic(addr, reg, !(reg & BUSY), 2, 100)
// step for step: read; if BUSY is clear, go on; if the time is up, read once
// more and decide on that; otherwise pause 2 us and read again. The time is
// counted in pauses, as that macro counts it, so a block that stays busy is
// given 50 pauses and 52 reads.
//
// The write keeps every bit of the command register that was read except the
// two p-state fields, sets both to `pstate`, and sets SET. It does not wait
// for the change to take place; the status register says when it has.
//
// One difference from Linux 6.6: a `pstate` above the SoC's highest is
// refused here. There the check compares and clamps the table index, after
// the p-state has already been taken from the table, and so has no effect.
pub fn dvfs_set(io &DvfsIo, info DvfsInfo, pstate u32) DvfsResult {
	if pstate > info.max_pstate {
		return .invalid
	}
	mut waited := u32(0)
	mut command := u64(0)
	for {
		command = io.read(io.context, dvfs_cmd)
		if command & dvfs_cmd_busy == 0 {
			break
		}
		if waited >= dvfs_timeout_us {
			command = io.read(io.context, dvfs_cmd)
			break
		}
		io.pause(io.context, dvfs_poll_us)
		waited += dvfs_poll_us
	}
	if command & dvfs_cmd_busy != 0 {
		return .busy
	}
	command &= ~(dvfs_cmd_ps1 | dvfs_cmd_ps2)
	command |= u64(pstate) & dvfs_cmd_ps1
	command |= (u64(pstate) << 12) & dvfs_cmd_ps2
	command |= dvfs_cmd_set
	io.write(io.context, dvfs_cmd, command)
	return .done
}

// The p-state the cluster is in: apple_soc_cpufreq_get_rate(), up to the
// lookup of its frequency. From the status register where its layout is
// known; otherwise the state last asked for, from the command register.
pub fn dvfs_current(io &DvfsIo, info DvfsInfo) u32 {
	if info.current_mask != 0 {
		status := io.read(io.context, dvfs_status)
		return u32((status & info.current_mask) >> info.current_shift)
	}
	return u32(io.read(io.context, dvfs_cmd) & dvfs_cmd_ps1)
}

// One operating point of a cluster, from its device tree table.
pub struct DvfsPoint {
pub mut:
	khz    u64
	pstate u32
}

// Put `count` points in rising order of frequency. The device tree lists
// them that way, and nothing downstream may depend on it.
pub fn dvfs_sort(table voidptr, count int) {
	mut points := unsafe { &DvfsPoint(table) }
	for i := 1; i < count; i++ {
		point := unsafe { points[i] }
		mut j := i
		for j > 0 && unsafe { points[j - 1] }.khz > point.khz {
			unsafe {
				points[j] = points[j - 1]
			}
			j--
		}
		unsafe {
			points[j] = point
		}
	}
}

// The point to use for a governor's target of `wanted_khz` under a ceiling of
// `highest_khz`: the slowest that is fast enough, unless that is over the
// ceiling, when the fastest under it. `points` are in rising order. -1 for an
// empty table.
pub fn dvfs_point(points &DvfsPoint, count int, wanted_khz u64, highest_khz u64) int {
	if count <= 0 {
		return -1
	}
	mut chosen := count - 1
	for i in 0 .. count {
		if unsafe { points[i] }.khz >= wanted_khz {
			chosen = i
			break
		}
	}
	for chosen > 0 && unsafe { points[chosen] }.khz > highest_khz {
		chosen--
	}
	return chosen
}

// The frequency of `pstate`, or 0 for one the table does not have.
pub fn dvfs_khz(points &DvfsPoint, count int, pstate u32) u64 {
	for i in 0 .. count {
		if unsafe { points[i] }.pstate == pstate {
			return unsafe { points[i] }.khz
		}
	}
	return 0
}
