// SPDX-License-Identifier: GPL-2.0-or-later
module gpu

import gpu.agx.fw
import klock
import lib

// The manager fields stats.v reads; the heaps report fixed live sizes.
struct FakeHeap {
	bytes u64
}

fn (mut heap FakeHeap) used() u64 { return heap.bytes }

pub struct GpuManager {
mut:
	lock             klock.Lock
	g13_stats        G13Stats
	allocs           FakeHeap
	g13_private      FakeHeap
	g13_gpu_readonly FakeHeap
	g13_shared       FakeHeap
	g13_readonly     FakeHeap
	g13_rtkit        FakeHeap
	g13_timestamp    FakeHeap
}

const ts_hz = u64(24_000_000)

// A stats message laid out as the firmware writes it: little-endian words at
// the offsets the pinned Rust declaration gives.
struct Wire {
mut:
	bytes [64]u8
}

fn (mut wire Wire) u32_at(offset int, value u32) {
	for index in 0 .. 4 { wire.bytes[offset + index] = u8(value >> (8 * index)) }
}

fn (mut wire Wire) u64_at(offset int, value u64) {
	wire.u32_at(offset, u32(value))
	wire.u32_at(offset + 4, u32(value >> 32))
}

fn (wire &Wire) message() fw.FwStatsMsg {
	return unsafe { *&fw.FwStatsMsg(&wire.bytes[0]) }
}

fn utilization(timestamp u64, util [4]u32) fw.FwStatsMsg {
	mut wire := Wire{}
	wire.u32_at(0, oracle_tag_utilization)
	wire.u64_at(oracle_utilization_timestamp, timestamp)
	wire.u32_at(oracle_utilization_util1, util[0])
	wire.u32_at(oracle_utilization_util2, util[1])
	wire.u32_at(oracle_utilization_util3, util[2])
	wire.u32_at(oracle_utilization_util4, util[3])
	return wire.message()
}

fn lines(text string) ([]string, []u64) {
	mut names := []string{}
	mut values := []u64{}
	for line in text.split_into_lines() {
		names << line.all_before(' ')
		values << line.all_after(' ').u64()
	}
	return names, values
}

pub fn run_checks() {
	mut mgr := GpuManager{
		allocs:        FakeHeap{bytes: 0x4000}
		g13_private:   FakeHeap{bytes: 0x8000}
		g13_shared:    FakeHeap{bytes: 0x10000}
		g13_timestamp: FakeHeap{bytes: 0x4000}
	}
	// The first window only sets the base: nothing has elapsed yet.
	mgr.g13_stats.record(utilization(1000, [u32(40), 75, 3, 0]!), ts_hz, 0)
	assert mgr.g13_stats.busy_ns == 0
	// 2.5 s at 75 % busy is 1.875 s of busy time.
	mgr.g13_stats.record(utilization(1000 + ts_hz * 5 / 2, [u32(40), 75, 3, 0]!), ts_hz, 0)
	assert mgr.g13_stats.busy_ns == 1_875_000_000
	// Values above 100 count as 100; one tick is 41 ns of busy time.
	mgr.g13_stats.record(utilization(1001 + ts_hz * 5 / 2, [u32(0), 0, 101, 0]!), ts_hz, 0)
	assert mgr.g13_stats.busy_ns == 1_875_000_041
	assert mgr.g13_stats.util == [u32(0), 0, 101, 0]!
	// A timestamp that goes back adds nothing, but becomes the new base.
	mgr.g13_stats.record(utilization(500, [u32(100), 0, 0, 0]!), ts_hz, 0)
	assert mgr.g13_stats.busy_ns == 1_875_000_041
	mgr.g13_stats.record(utilization(500 + ts_hz, [u32(100), 0, 0, 0]!), ts_hz, 0)
	assert mgr.g13_stats.busy_ns == 2_875_000_041

	mut wire := Wire{}
	wire.u32_at(0, oracle_tag_powerstate)
	wire.u64_at(oracle_powerstate_timestamp, 0x1234_5678_9abc)
	wire.u32_at(oracle_powerstate_pstate, 5)
	mgr.g13_stats.record(wire.message(), ts_hz, 0)
	wire = Wire{}
	wire.u32_at(0, oracle_tag_avgpower)
	wire.u32_at(oracle_avgpower_avg_power, 1234)
	mgr.g13_stats.record(wire.message(), ts_hz, 0)
	wire = Wire{}
	wire.u32_at(0, oracle_tag_temperature)
	wire.u32_at(oracle_temperature_raw_value, 4567)
	wire.u32_at(oracle_temperature_scale, 100)
	mgr.g13_stats.record(wire.message(), ts_hz, 0)
	assert mgr.g13_stats.pstate == 5 && mgr.g13_stats.avg_power_mw == 1234
	assert mgr.g13_stats.temperature_raw == 4567 && mgr.g13_stats.temperature_scale == 100
	// A tag past the last known one is counted; the snapshot is unchanged.
	wire = Wire{}
	wire.u32_at(0, oracle_unknown_tag)
	wire.u32_at(4, 0xdead)
	mgr.g13_stats.record(wire.message(), ts_hz, 0)
	assert mgr.g13_stats.unknown_messages == 1 && mgr.g13_stats.pstate == 5
	mgr.note_g13_job()
	mgr.note_g13_job()

	// agx_stats prints Asahi's lines in Asahi's order.
	mut text := lib.new_text(512)
	mgr.g13_stats_text(mut text)
	names, values := lines(lib.finish_text(text))
	assert names == oracle_agx_stats, 'agx_stats lines ${names} != ${oracle_agx_stats}'
	assert values == [u64(2_875_000_041), 2, 5, 1234, 100, 0, 0, 0, 4567, 100]
	// gpu_memory: the user total resident in Vinix, the heaps' live bytes, and
	// G13's absent limits.
	mut memory := lib.new_text(512)
	mgr.g13_memory_text(mut memory, 0x30000)
	memory_names, memory_values := lines(lib.finish_text(memory))
	assert memory_names == oracle_gpu_memory, 'gpu_memory lines ${memory_names} != ${oracle_gpu_memory}'
	assert memory_values == [u64(0x30000), 0x30000, 0x20000, 0, 0, 0]
	assert !mgr.lock.is_held()
	run_raw_checks()
	println('AGX stats: Utilization, PowerState, AvgPower and Temperature at the pinned Rust offsets, utilization-weighted busy time, job counts, both sysfs files in Asahi order, and asahi_stats byte for byte as the reference formats it passed')
}

// asahi_stats: the messages of each phase, laid out at the pinned offsets with
// junk in the pads, go through Vinix's decoder; the text must be what the
// reference's own record_raw and format_snapshot, compiled, printed.
fn run_raw_checks() {
	mut mgr := GpuManager{}
	for phase, samples in oracle_raw_phases {
		for sample in samples {
			mut wire := Wire{}
			wire.u32_at(0, sample.tag)
			for write in sample.writes {
				if write.size == 8 {
					wire.u64_at(write.offset, write.value)
				} else {
					wire.u32_at(write.offset, u32(write.value))
				}
			}
			mgr.g13_stats.record(wire.message(), ts_hz, sample.stamp)
		}
		mut text := lib.new_text(1024)
		mgr.g13_raw_stats_text(mut text, 0x206400000, oracle_raw_now[phase])
		got := lib.finish_text(text)
		assert got == oracle_raw_texts[phase], 'asahi_stats after phase ${phase}:\n${got}\nreference:\n${oracle_raw_texts[phase]}'
	}
	assert !mgr.g13_stats.raw_lock.is_held()
}
