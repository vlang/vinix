// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// The Apple cluster DVFS sequence against a model of the register block, on
// the host. apple_dvfs.v beside this file is the kernel's apple_dvfs_arm64.v.
//
// The model is what drivers/cpufreq/apple-soc-cpufreq.c relies on, no more:
// a command register whose BUSY bit is set while a change is under way, and a
// status register whose current-state field follows the command once it is
// done. Every access is recorded, so a test can say exactly which the
// sequence made.
module cpufreq

struct Block {
mut:
	command u64
	status  u64
	// BUSY reads as set for this many more reads of the command register.
	busy_reads int
	// Never clears.
	stuck bool
	layout DvfsInfo
	// What was done to it.
	command_reads int
	status_reads  int
	writes        int
	last_write    u64
	paused_us     u32
	pauses        int
	other         int
}

fn block_read(context voidptr, offset u32) u64 {
	mut b := unsafe { &Block(context) }
	if offset == dvfs_cmd {
		b.command_reads++
		if b.stuck {
			return b.command | dvfs_cmd_busy
		}
		if b.busy_reads > 0 {
			b.busy_reads--
			return b.command | dvfs_cmd_busy
		}
		return b.command & ~dvfs_cmd_busy
	}
	if offset == dvfs_status {
		b.status_reads++
		return b.status
	}
	b.other++
	return 0
}

fn block_write(context voidptr, offset u32, value u64) {
	mut b := unsafe { &Block(context) }
	if offset != dvfs_cmd {
		b.other++
		return
	}
	b.writes++
	b.last_write = value
	b.command = value
	if value & dvfs_cmd_set != 0 && b.layout.current_mask != 0 {
		// The change takes place; the status register shows the new state.
		b.status = (b.status & ~b.layout.current_mask) | ((value & dvfs_cmd_ps1) << b.layout.current_shift)
	}
}

fn block_pause(context voidptr, us u32) {
	mut b := unsafe { &Block(context) }
	b.pauses++
	b.paused_us += us
}

fn io_for(b &Block) DvfsIo {
	return DvfsIo{
		read:    block_read
		write:   block_write
		pause:   block_pause
		context: voidptr(b)
	}
}

fn test_layouts_are_the_linux_driver_s() {
	// soc_t8103_info, soc_t8112_info, soc_default_info.
	m1 := dvfs_info(.t8103)
	assert m1.max_pstate == 15 && m1.current_mask == 0xf0 && m1.current_shift == 4
	m2 := dvfs_info(.t8112)
	assert m2.max_pstate == 31 && m2.current_mask == 0x3e0 && m2.current_shift == 5
	other := dvfs_info(.other)
	assert other.max_pstate == 15 && other.current_mask == 0
	assert dvfs_soc('apple,t8103-cluster-cpufreq')? == DvfsSoc.t8103
	assert dvfs_soc('apple,t8112-cluster-cpufreq')? == DvfsSoc.t8112
	assert dvfs_soc('apple,cluster-cpufreq')? == DvfsSoc.other
	if _ := dvfs_soc('apple,t8103-pmgr') {
		assert false
	}
	// APPLE_DVFS_CMD and its fields.
	assert dvfs_cmd == 0x20 && dvfs_status == 0x50
	assert dvfs_cmd_busy == 0x80000000 && dvfs_cmd_set == 0x02000000
	assert dvfs_cmd_ps1 == 0x1f && dvfs_cmd_ps2 == 0x1f000
}

fn test_set_on_an_idle_block() {
	mut b := Block{
		layout: dvfs_info(.t8103)
	}
	io := io_for(&b)
	assert dvfs_set(&io, b.layout, 7) == .done
	// One look at BUSY, no waiting, one write: both fields and SET.
	assert b.command_reads == 1
	assert b.pauses == 0
	assert b.writes == 1
	assert b.last_write == u64(0x02007007)
	assert b.other == 0
	assert dvfs_current(&io, b.layout) == 7
}

fn test_set_keeps_the_rest_of_the_command_register() {
	// reg &= ~(PS1 | PS2); reg |= ...: what else is in it stays.
	mut b := Block{
		layout:  dvfs_info(.t8103)
		command: u64(0x0000_00a5_4001_f01f)
	}
	io := io_for(&b)
	assert dvfs_set(&io, b.layout, 3) == .done
	assert b.last_write == u64(0x0000_00a5_4200_3003)
	// P-state 0 clears both fields.
	assert dvfs_set(&io, b.layout, 0) == .done
	assert b.last_write == u64(0x0000_00a5_4200_0000)
}

fn test_set_waits_for_busy() {
	mut b := Block{
		layout:     dvfs_info(.t8103)
		busy_reads: 5
	}
	io := io_for(&b)
	assert dvfs_set(&io, b.layout, 15) == .done
	// Five busy reads, a 2 us pause after each, and the read that saw it clear.
	assert b.command_reads == 6
	assert b.pauses == 5
	assert b.paused_us == 10
	assert b.writes == 1
	// BUSY itself is never written back.
	assert b.last_write & dvfs_cmd_busy == 0
	assert b.last_write == u64(0x0200f00f)
}

fn test_set_gives_up_after_the_timeout() {
	mut b := Block{
		layout: dvfs_info(.t8103)
		stuck:  true
	}
	io := io_for(&b)
	assert dvfs_set(&io, b.layout, 4) == .busy
	// readq_poll_timeout_atomic(.., 2, 100): 50 pauses of 2 us, a read before
	// each, the read that finds the time up and the last look after it.
	assert b.pauses == 50
	assert b.paused_us == 100
	assert b.command_reads == 52
	// And nothing written: -EIO before the write in the Linux driver.
	assert b.writes == 0
}

fn test_set_succeeds_when_busy_clears_at_the_last_look() {
	// The one read after the time is up is what decides.
	mut b := Block{
		layout:     dvfs_info(.t8103)
		busy_reads: 51
	}
	io := io_for(&b)
	assert dvfs_set(&io, b.layout, 4) == .done
	assert b.command_reads == 52
	assert b.writes == 1
	mut late := Block{
		layout:     dvfs_info(.t8103)
		busy_reads: 52
	}
	late_io := io_for(&late)
	assert dvfs_set(&late_io, late.layout, 4) == .busy
	assert late.writes == 0
}

fn test_set_refuses_a_state_the_soc_does_not_have() {
	mut b := Block{
		layout: dvfs_info(.t8103)
	}
	io := io_for(&b)
	assert dvfs_set(&io, b.layout, 16) == .invalid
	assert b.command_reads == 0 && b.writes == 0
	assert dvfs_set(&io, b.layout, 15) == .done
	// The M2 has twice as many.
	mut m2 := Block{
		layout: dvfs_info(.t8112)
	}
	m2_io := io_for(&m2)
	assert dvfs_set(&m2_io, m2.layout, 31) == .done
	assert m2.last_write == u64(0x0201f01f)
	assert dvfs_set(&m2_io, m2.layout, 32) == .invalid
}

fn test_readback_uses_the_soc_s_status_field() {
	// The same status word means different states on the two SoCs.
	mut m1 := Block{
		layout: dvfs_info(.t8103)
		status: 0x1a5
	}
	m1_io := io_for(&m1)
	assert dvfs_current(&m1_io, m1.layout) == 0xa
	assert m1.status_reads == 1 && m1.command_reads == 0
	mut m2 := Block{
		layout: dvfs_info(.t8112)
		status: 0x1a5
	}
	m2_io := io_for(&m2)
	assert dvfs_current(&m2_io, m2.layout) == 0xd
	// Set, then read back, through the model's status register.
	assert dvfs_set(&m2_io, m2.layout, 22) == .done
	assert dvfs_current(&m2_io, m2.layout) == 22
	// The target field below the current one is left alone.
	assert m2.status & 0x1f == 0x05
}

fn test_readback_without_a_known_status_layout() {
	// The fallback reads PS1 of the command register.
	mut b := Block{
		layout:  dvfs_info(.other)
		command: 0x0200b00b
	}
	io := io_for(&b)
	assert dvfs_current(&io, b.layout) == 0xb
	assert b.status_reads == 0 && b.command_reads == 1
}

// The efficiency cluster of an M1, from Asahi's t8103.dtsi.
fn icestorm() [5]DvfsPoint {
	return [DvfsPoint{600000, 1}, DvfsPoint{972000, 2}, DvfsPoint{1332000, 3},
		DvfsPoint{1704000, 4}, DvfsPoint{2064000, 5}]!
}

fn test_points_are_sorted() {
	mut points := [DvfsPoint{1704000, 4}, DvfsPoint{600000, 1}, DvfsPoint{2064000, 5},
		DvfsPoint{972000, 2}, DvfsPoint{1332000, 3}]!
	dvfs_sort(voidptr(&points[0]), 5)
	sorted := icestorm()
	for i in 0 .. 5 {
		assert points[i].khz == sorted[i].khz && points[i].pstate == sorted[i].pstate
	}
	dvfs_sort(voidptr(&points[0]), 0)
	dvfs_sort(voidptr(&points[0]), 1)
	assert points[0].pstate == 1
}

fn test_point_for_a_target() {
	points := icestorm()
	// The slowest point that is fast enough.
	assert dvfs_point(&points[0], 5, 0, 2064000) == 0
	assert dvfs_point(&points[0], 5, 600000, 2064000) == 0
	assert dvfs_point(&points[0], 5, 600001, 2064000) == 1
	assert dvfs_point(&points[0], 5, 1500000, 2064000) == 3
	assert dvfs_point(&points[0], 5, 2064000, 2064000) == 4
	// More than there is: the fastest.
	assert dvfs_point(&points[0], 5, 9000000, 9000000) == 4
	// Under a ceiling: never a point above it, though one below the target.
	assert dvfs_point(&points[0], 5, 2064000, 1500000) == 2
	assert dvfs_point(&points[0], 5, 1500000, 1500000) == 2
	// A ceiling below every point: the slowest there is.
	assert dvfs_point(&points[0], 5, 2064000, 100000) == 0
	assert dvfs_point(&points[0], 0, 1000000, 2064000) == -1
}

fn test_frequency_of_a_state() {
	points := icestorm()
	assert dvfs_khz(&points[0], 5, 1) == 600000
	assert dvfs_khz(&points[0], 5, 5) == 2064000
	assert dvfs_khz(&points[0], 5, 0) == 0
	assert dvfs_khz(&points[0], 5, 9) == 0
}

fn test_governor_to_register() {
	// The whole way: a load, the governor's target, the point, the write.
	points := icestorm()
	mut b := Block{
		layout: dvfs_info(.t8103)
	}
	io := io_for(&b)
	lowest := points[0].khz
	highest := points[4].khz
	// Half busy with the usual headroom asks for 1.29 GHz: the 1.332 GHz point.
	wanted := target_khz(.ondemand, .balance_performance, 500, lowest, highest)
	assert wanted == 1290000
	step := dvfs_point(&points[0], 5, wanted, highest)
	assert points[step].khz == 1332000
	assert dvfs_set(&io, b.layout, points[step].pstate) == .done
	assert b.last_write == u64(0x02003003)
	assert dvfs_khz(&points[0], 5, dvfs_current(&io, b.layout)) == 1332000
	// Under a thermal limit of 60 % the performance governor gets 972 MHz.
	limits := Limits{
		hw_min_khz:   lowest
		hw_max_khz:   highest
		user_min_khz: lowest
		user_max_khz: highest
	}
	_, capped := allowed_range(limits, 60)
	hot := dvfs_point(&points[0], 5, target_khz(.performance, .performance, 1000, lowest,
		capped), capped)
	assert points[hot].khz == 972000
}
