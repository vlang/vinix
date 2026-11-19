// SPDX-License-Identifier: GPL-2.0-or-later
module gpu

// The latest G13 firmware statistics and the GPU's memory totals, as Asahi
// keeps them for the agx_stats and gpu_memory sysfs files, and the raw
// snapshot it keeps for asahi_stats in debugfs.
//
// The event worker is the only writer of the firmware values; job counts
// come from the submission reaper. Readers of the agx_stats values take no
// lock, so each is read and written whole with katomic. The raw snapshot is
// kept under its own short lock, as Asahi keeps it under a spinlock, and a
// reader copies it out before formatting.

import gpu.agx.fw
import katomic
import klock
import lib

// Stats message tags (Asahi's StatsMsg discriminants).
const stats_utilization = u32(0x04)
const stats_avg_power = u32(0x09)
const stats_temperature = u32(0x0a)
const stats_power_state = u32(0x0b)
const stats_max = u32(0x0e)

pub struct G13Stats {
mut:
	util              [4]u32
	pstate            u32
	avg_power_mw      u32
	temperature_raw   u32
	temperature_scale u32
	busy_ns           u64
	jobs              u64
	last_util_ts      u64 // written by the event worker only
	unknown_messages  u64
	raw_lock          klock.Lock
	raw               G13RawStats // under raw_lock
}

// Asahi's StatsKind, in export order, and the firmware tag of each.
const raw_kind_names = ['power', 'power_on', 'power_off', 'utilization', 'avg_power', 'temperature',
	'power_state', 'fw_busy', 'pstate', 'temp_sensor']!
const raw_kind_tags = [u32(0x00), 0x02, 0x03, 0x04, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e]!
const raw_kinds = 10

// The last statistics message of each kind exactly as the firmware sent it,
// for asahi_stats (Asahi's RawStatsSnapshot): a sample count and the
// monotonic time it was captured, per kind, and the message's words, decoded
// only when shown. Fixed size: recording never allocates.
pub struct G13RawStats {
mut:
	messages    u64
	count       [10]u64
	captured_ns [10]u64
	payload     [10][11]u32
}

fn saturating_mul(a u64, b u64) u64 {
	if a != 0 && b > max_u64 / a { return max_u64 }
	return a * b
}

fn saturating_add(a u64, b u64) u64 {
	return if a > max_u64 - b { max_u64 } else { a + b }
}

// Record one stats message, as Asahi's StatsChannel::poll does. Every field
// follows the tag directly: the firmware's 64-bit fields are unaligned. Only
// the values the export shows are kept; the rest are read and dropped.
fn (mut stats G13Stats) record(message fw.FwStatsMsg, ts_hz u64, now_ns u64) {
	stats.record_raw(message, now_ns)
	payload := message.payload
	match message.tag {
		stats_utilization {
			timestamp := u64(payload[0]) | (u64(payload[1]) << 32)
			mut busiest := u32(0)
			for index in 0 .. 4 {
				value := payload[2 + index]
				katomic.store(mut &stats.util[index], value)
				if value > busiest { busiest = value }
			}
			util := u64(if busiest > 100 { u32(100) } else { busiest })
			// Busy time: each window's length, in base-clock ticks, scaled by
			// the busiest subqueue's percentage. Whole seconds and the tick
			// remainder are converted separately so nothing overflows.
			if stats.last_util_ts != 0 && timestamp > stats.last_util_ts && ts_hz != 0 {
				delta := timestamp - stats.last_util_ts
				whole_s := delta / ts_hz
				rem := delta % ts_hz
				busy := saturating_add(saturating_mul(saturating_mul(whole_s, util), 10_000_000),
					rem * util * 1_000_000_000 / (100 * ts_hz))
				// The event worker is the only writer; readers see whole values.
				katomic.store(mut &stats.busy_ns, katomic.load(&stats.busy_ns) + busy)
			}
			stats.last_util_ts = timestamp
		}
		stats_power_state {
			katomic.store(mut &stats.pstate, payload[7])
		}
		stats_avg_power {
			katomic.store(mut &stats.avg_power_mw, payload[5])
		}
		stats_temperature {
			katomic.store(mut &stats.temperature_raw, payload[2])
			katomic.store(mut &stats.temperature_scale, payload[3])
		}
		else {
			if message.tag > stats_max {
				// Asahi warns for each one; a count says as much without
				// flooding the console.
				katomic.inc(mut &stats.unknown_messages)
			}
		}
	}
}

// Asahi's record_raw: every message with a known tag is counted, and each of
// the ten kinds it decodes keeps its words and capture time.
fn (mut stats G13Stats) record_raw(message fw.FwStatsMsg, now_ns u64) {
	if message.tag > stats_max { return }
	mut kind := -1
	for index in 0 .. raw_kinds {
		if raw_kind_tags[index] == message.tag { kind = index }
	}
	stats.raw_lock.acquire()
	stats.raw.messages++
	if kind >= 0 {
		stats.raw.count[kind]++
		stats.raw.captured_ns[kind] = now_ns
		for word in 0 .. 11 {
			stats.raw.payload[kind][word] = message.payload[word]
		}
	}
	stats.raw_lock.release()
}

// A submission whose commands have all completed on the GPU.
pub fn (mut mgr GpuManager) note_g13_job() {
	katomic.inc(mut &mgr.g13_stats.jobs)
}

// The agx_stats text (Asahi's agx_stats_show).
pub fn (mgr &GpuManager) g13_stats_text(mut text lib.Text) {
	stats := &mgr.g13_stats
	add_stat(mut text, 'busy_ns', katomic.load(&stats.busy_ns))
	add_stat(mut text, 'jobs', katomic.load(&stats.jobs))
	add_stat(mut text, 'pstate', u64(katomic.load(&stats.pstate)))
	add_stat(mut text, 'power_mw', u64(katomic.load(&stats.avg_power_mw)))
	add_stat(mut text, 'util1', u64(katomic.load(&stats.util[0])))
	add_stat(mut text, 'util2', u64(katomic.load(&stats.util[1])))
	add_stat(mut text, 'util3', u64(katomic.load(&stats.util[2])))
	add_stat(mut text, 'util4', u64(katomic.load(&stats.util[3])))
	add_stat(mut text, 'temperature_raw', u64(katomic.load(&stats.temperature_raw)))
	add_stat(mut text, 'temperature_scale', u64(katomic.load(&stats.temperature_scale)))
}

fn raw_wide(low u32, high u32) u64 {
	return u64(low) | (u64(high) << 32)
}

fn add_raw_field(mut text lib.Text, name string, value u64) {
	text.add(name)
	text.add_unsigned(value)
}

// The asahi_stats text (Asahi's format_snapshot): one line per record of
// key=value pairs. A kind never received shows count=0 and no payload, so a
// missing sample is not mistaken for a zero. now_ns and captured_ns are
// monotonic nanoseconds; every other value is a raw firmware word. The
// device is named as Linux names the GPU's platform device, after its unit
// address: 206400000.gpu. The snapshot is copied out before formatting, as
// Asahi does.
pub fn (mut mgr GpuManager) g13_raw_stats_text(mut text lib.Text, unit_address u64, now_ns u64) {
	mgr.g13_stats.raw_lock.acquire()
	snapshot := mgr.g13_stats.raw
	mgr.g13_stats.raw_lock.release()
	text.add('asahi_stats_v1\ndevice=')
	text.add_radix(unit_address, 16, 0)
	text.add('.gpu\nnow_ns=')
	text.add_unsigned(now_ns)
	text.add('\nmessages count=')
	text.add_unsigned(snapshot.messages)
	text.add_byte(`\n`)
	for kind in 0 .. raw_kinds {
		text.add(raw_kind_names[kind])
		add_raw_field(mut text, ' count=', snapshot.count[kind])
		if snapshot.count[kind] != 0 {
			add_raw_field(mut text, ' captured_ns=', snapshot.captured_ns[kind])
			// Each field at its offset in Asahi's StatsMsg, in words after
			// the tag; 64-bit fields are two words, low first.
			w := snapshot.payload[kind]
			match kind {
				0 {
					add_raw_field(mut text, ' power=', raw_wide(w[6], w[7]))
				}
				1 {
					add_raw_field(mut text, ' off_time=', raw_wide(w[0], w[1]))
				}
				2 {
					add_raw_field(mut text, ' on_time=', raw_wide(w[0], w[1]))
				}
				3 {
					add_raw_field(mut text, ' timestamp=', raw_wide(w[0], w[1]))
					add_raw_field(mut text, ' util1=', w[2])
					add_raw_field(mut text, ' util2=', w[3])
					add_raw_field(mut text, ' util3=', w[4])
					add_raw_field(mut text, ' util4=', w[5])
				}
				4 {
					add_raw_field(mut text, ' active_cs=', raw_wide(w[0], w[1]))
					add_raw_field(mut text, ' unk2=', w[2])
					add_raw_field(mut text, ' unk3=', w[3])
					add_raw_field(mut text, ' unk4=', w[4])
					add_raw_field(mut text, ' avg_power=', w[5])
				}
				5 {
					add_raw_field(mut text, ' raw_value=', w[2])
					add_raw_field(mut text, ' scale=', w[3])
					add_raw_field(mut text, ' tmin=', w[4])
					add_raw_field(mut text, ' tmax=', w[5])
				}
				6 {
					add_raw_field(mut text, ' timestamp=', raw_wide(w[0], w[1]))
					add_raw_field(mut text, ' last_busy_ts=', raw_wide(w[2], w[3]))
					add_raw_field(mut text, ' active=', w[4])
					add_raw_field(mut text, ' poweroff=', w[5])
					add_raw_field(mut text, ' unk1=', w[6])
					add_raw_field(mut text, ' pstate=', w[7])
					add_raw_field(mut text, ' unk2=', w[8])
					add_raw_field(mut text, ' unk3=', w[9])
				}
				7 {
					add_raw_field(mut text, ' timestamp=', raw_wide(w[0], w[1]))
					add_raw_field(mut text, ' busy=', w[2])
				}
				8 {
					add_raw_field(mut text, ' ps_min=', w[2])
					add_raw_field(mut text, ' unk1=', w[3])
					add_raw_field(mut text, ' ps_max=', w[4])
					add_raw_field(mut text, ' unk2=', w[5])
				}
				else {
					add_raw_field(mut text, ' sensor_id=', w[1])
					add_raw_field(mut text, ' raw_value=', w[2])
					add_raw_field(mut text, ' scale=', w[3])
					add_raw_field(mut text, ' tmin=', w[4])
					add_raw_field(mut text, ' tmax=', w[5])
				}
			}
		}
		text.add_byte(`\n`)
	}
}

// The gpu_memory text (Asahi's gpu_memory_show). G13 has no limits, so the
// last three lines are zero, as Asahi prints them there.
pub fn (mut mgr GpuManager) g13_memory_text(mut text lib.Text, user_committed u64) {
	add_stat(mut text, 'user_committed', user_committed)
	add_stat(mut text, 'user_resident', user_committed)
	add_stat(mut text, 'kernel_resident', mgr.g13_kernel_resident())
	add_stat(mut text, 'limit', 0)
	add_stat(mut text, 'client_limit', 0)
	add_stat(mut text, 'refused', 0)
}

// Live allocations of the firmware heaps the driver allocates from. Under
// mgr.lock: a fatal error's shutdown retires the timestamp heap's table
// holding only that lock, and a sysfs read must not walk it meanwhile.
fn (mut mgr GpuManager) g13_kernel_resident() u64 {
	mgr.lock.acquire()
	defer { mgr.lock.release() }
	return mgr.allocs.used() + mgr.g13_private.used() + mgr.g13_gpu_readonly.used()
		+ mgr.g13_shared.used() + mgr.g13_readonly.used() + mgr.g13_rtkit.used()
		+ mgr.g13_timestamp.used()
}

fn add_stat(mut text lib.Text, name string, value u64) {
	text.add(name)
	text.add_byte(` `)
	text.add_unsigned(value)
	text.add_byte(`\n`)
}
