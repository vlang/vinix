// SPDX-License-Identifier: GPL-2.0-only
// Copyright (c) 2026 Alexander Medvednikov
//
// A kernel with a made-up SMC, for testing the driver on a machine that has
// none: every emulator. Only in a kernel built with -d applesmc_selftest.
//
// In such a kernel no device tree is looked at, no mailbox register is read
// or written and no SRAM is mapped, on any machine: the simulated SMC of
// core/sim_d_applesmc_selftest.v answers the protocol core's mailbox
// callbacks instead, on the real clock. Everything above those callbacks is
// the code a Mac runs: the RTKit start-up, the key commands and their
// deadlines, the thread, what it publishes, the power supply and thermal
// classes, the device nodes and /sys.
//
// The SMC starts out as a laptop on its charger with one fan and a charge
// limit key (core.Sim.laptop). With `vinix.apple_smc_sim=bare` on the command
// line it has no fan and no charge limit, and its remaining charge is stored
// the newer way round.
//
// The test drives it through two files beside the driver's own:
//
//	/sys/devices/platform/apple-smc/smc/selftest        (write)
//	    scene charging|unplugged|low|critical|full
//	                               move the battery to that moment of its day
//	    set <key> <hex bytes>      give a key that is there a new value, in
//	                               the order the SMC holds its bytes
//	    once <key> <hex bytes>     answer the next read of the key, and only
//	                               that one, with these bytes
//	    remove <key>               take a key away
//	    protect <key>              make a key one that may not be written
//	    fault none|silent|ignore-writes
//	                               answer nothing from now on; take a written
//	                               value and keep the old one
//	/sys/devices/platform/apple-smc/smc/selftest_state  (read)
//	    what the SMC was asked, the key last written and its first byte, and
//	    how often the driver broke the protocol towards it
@[has_globals]
module smc

import apple.smc.core as smccore
import devcore
import errno
import fs
import klock
import lib
import memory

__global (
	smc_sim      smccore.Sim
	// The thread's exchanges and the test's commands come from two threads.
	smc_sim_lock klock.Lock
)

fn sim_send(_ voidptr, word u64, endpoint u8) i32 {
	smc_sim_lock.acquire()
	taken := smc_sim.send(word, endpoint)
	smc_sim_lock.release()
	return if taken { i32(1) } else { i32(0) }
}

fn sim_recv(_ voidptr, word &u64, endpoint &u8) i32 {
	smc_sim_lock.acquire()
	got, value, from := smc_sim.receive()
	smc_sim_lock.release()
	if !got {
		return 0
	}
	unsafe {
		*word = value
		*endpoint = from
	}
	return 1
}

fn sim_shmem(_ voidptr, write i32, offset u32, buffer &u8, length u32) i32 {
	smc_sim_lock.acquire()
	done := smc_sim.shared(write != 0, offset, buffer, length)
	smc_sim_lock.release()
	return if done { i32(1) } else { i32(0) }
}

// Give the core the simulated SMC's shared memory.
fn selftest_shmem(state voidptr) bool {
	return smccore.vinix_smc_set_shmem(state, sim_shmem) == 0
}

// Make the SMC and start the driver on it. Called in place of the search of
// the device tree.
fn selftest_initialise() {
	mut bare := false
	if choice := devcore.boot_option('vinix.apple_smc_sim=') {
		bare = has_word(choice, 'bare')
	}
	smc_sim.laptop(!bare, !bare, !bare)
	print('apple-smc: self-test kernel: the SMC is simulated, no mailbox is touched\n')
	mut dev := &Battery{
		state:     memory.malloc(u64(smccore.vinix_smc_state_size()))
		snapshots: map[u64]Snapshot{}
	}
	start(mut dev, sim_send, sim_recv, smccore.sim_sram_base, smccore.sim_sram_size, true)
}

// The first word of `text` and what follows it: views, not copies.
fn first_word(text string) (string, string) {
	mut from := 0
	for from < text.len && text[from] == ` ` {
		from++
	}
	mut end := from
	for end < text.len && text[end] != ` ` {
		end++
	}
	word := unsafe { tos(text.str + from, end - from) }
	rest := unsafe { tos(text.str + end, text.len - end) }
	return word, rest
}

// The value of a hexadecimal digit, or 16 for anything else.
fn hex_value(c u8) u8 {
	if c >= `0` && c <= `9` {
		return c - `0`
	}
	if c >= `a` && c <= `f` {
		return c - `a` + 10
	}
	if c >= `A` && c <= `F` {
		return c - `A` + 10
	}
	return 16
}

// Pairs of hexadecimal digits into `out`, at most 32 bytes. The count, or -1
// for anything that is not that.
fn hex_bytes(word string, out &u8) int {
	if word.len == 0 || word.len % 2 != 0 || word.len > 64 {
		return -1
	}
	for i in 0 .. word.len / 2 {
		high := hex_value(word[2 * i])
		low := hex_value(word[2 * i + 1])
		if high > 15 || low > 15 {
			return -1
		}
		unsafe {
			out[i] = (high << 4) | low
		}
	}
	return word.len / 2
}

// A key's four characters as its number, or 0.
fn key_of(word string) u32 {
	if word.len != 4 {
		return 0
	}
	return (u32(word[0]) << 24) | (u32(word[1]) << 16) | (u32(word[2]) << 8) | u32(word[3])
}

fn store_selftest(_ voidptr, data &u8, length u64) u64 {
	command, after := first_word(fs.sysfs_word(data, length))
	first, after_first := first_word(after)
	second, _ := first_word(after_first)
	mut bytes := [32]u8{}
	mut result := u64(errno.einval)
	smc_sim_lock.acquire()
	if command == 'scene' {
		result = 0
		if first == 'charging' {
			smc_sim.scene(.charging)
		} else if first == 'unplugged' {
			smc_sim.scene(.unplugged)
		} else if first == 'low' {
			smc_sim.scene(.low)
		} else if first == 'critical' {
			smc_sim.scene(.critical)
		} else if first == 'full' {
			smc_sim.scene(.full)
		} else {
			result = u64(errno.einval)
		}
	} else if command == 'set' || command == 'once' {
		key := key_of(first)
		count := hex_bytes(second, &bytes[0])
		if key != 0 && count > 0 {
			mut done := false
			if command == 'set' {
				done = smc_sim.update_bytes(key, &bytes[0], count)
			} else {
				done = smc_sim.once_bytes(key, &bytes[0], count)
			}
			result = if done { u64(0) } else { u64(errno.enoent) }
		}
	} else if command == 'remove' {
		key := key_of(first)
		if key != 0 {
			result = if smc_sim.remove(key) { u64(0) } else { u64(errno.enoent) }
		}
	} else if command == 'protect' {
		index := smc_sim.find(key_of(first))
		if index >= 0 {
			smc_sim.keys[index].flags &= ~smccore.flag_writable
			result = 0
		} else {
			result = u64(errno.enoent)
		}
	} else if command == 'fault' {
		result = 0
		if first == 'none' {
			smc_sim.silent = false
			smc_sim.ignore_writes = false
		} else if first == 'silent' {
			smc_sim.silent = true
		} else if first == 'ignore-writes' {
			smc_sim.ignore_writes = true
		} else {
			result = u64(errno.einval)
		}
	}
	smc_sim_lock.release()
	return result
}

fn show_selftest_state(_ voidptr, mut text lib.Text) {
	smc_sim_lock.acquire()
	commands := smc_sim.commands
	reads := smc_sim.reads
	writes := smc_sim.writes
	infos := smc_sim.infos
	unknown := smc_sim.unknown
	violations := smc_sim.violations
	last_written := smc_sim.last_written
	last_byte := smc_sim.last_byte
	limit := smc_sim.value_of(smccore.key_chwa)
	smc_sim_lock.release()
	status_line(mut text, 'commands', commands)
	status_line(mut text, 'reads', reads)
	status_line(mut text, 'writes', writes)
	status_line(mut text, 'infos', infos)
	status_line(mut text, 'unknown', unknown)
	status_line(mut text, 'violations', violations)
	text.add('last_written ')
	if last_written != 0 {
		add_code(mut text, last_written)
	} else {
		text.add('none')
	}
	text.add_byte(`\n`)
	status_line(mut text, 'last_byte', u64(last_byte))
	status_line(mut text, 'chwa', limit)
}

// The two files, beside the driver's own. Called from publish_status().
fn selftest_publish() {
	control := status_path('selftest')
	fs.sysfs_attribute(control, 0o200, unsafe { nil }, store_selftest, unsafe { nil })
	unsafe { control.free() }
	state := status_path('selftest_state')
	fs.sysfs_attribute(state, 0o444, show_selftest_state, unsafe { nil }, unsafe { nil })
	unsafe { state.free() }
}
