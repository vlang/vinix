// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// A small mutation fuzzer for parsers that can be built on the host.
//
// A target is a name, some inputs that are valid or nearly so, and a
// function that is given bytes. The function must do one of two things with
// any bytes at all: refuse them, or accept them and have what it accepted
// hold together (it returns an error when it does not). It must never
// crash, hang or read outside the buffer. The fuzzer feeds it the seeds and
// then inputs made from them by a handful of blunt changes.
//
// Everything is derived from three numbers -- the run's seed, the target's
// name and the iteration -- so any input can be made again: a finding is
// reported as the command that reproduces it. A target runs in a process of
// its own; when that process dies the fuzzer finds the iteration that
// killed it by running the last few again one process each.
module fuzzcore

import os

#include <unistd.h>
#include <sys/wait.h>

fn C.fork() int
fn C.pipe(fds &i32) int
fn C.waitpid(pid int, status &i32, options int) int
fn C._exit(status int)
fn C.alarm(seconds u32) u32

pub struct Target {
pub:
	name  string
	about string
	seeds []string
	run   fn (data []u8) ! = unsafe { nil }
}

pub struct Options {
pub:
	seed       u64 = 1
	iterations int = 20000
	only       int = -1 // run this one iteration and nothing else
	// Seconds one window of iterations may take before it counts as a hang.
	window_seconds int = 20
}

pub struct Finding {
pub:
	target    string
	iteration int
	what      string // 'crash', 'hang' or the target's own complaint
	input     []u8
}

const window = 256
// Bytes a text format is likely to give meaning to.
const interesting = [u8(0), 0xff, 0x7f, 0x80, `\n`, `\r`, ` `, `:`, `=`, `,`, `$`, `/`, `-`, `0`,
	`9`, `x`, `#`, `!`, `*`, `.`]

struct Random {
mut:
	state u64
}

fn (mut r Random) next() u64 {
	// splitmix64.
	r.state += 0x9e3779b97f4a7c15
	mut z := r.state
	z = (z ^ (z >> 30)) * 0xbf58476d1ce4e5b9
	z = (z ^ (z >> 27)) * 0x94d049bb133111eb
	return z ^ (z >> 31)
}

fn (mut r Random) below(limit int) int {
	return if limit <= 0 { 0 } else { int(r.next() % u64(limit)) }
}

fn name_hash(name string) u64 {
	mut hash := u64(0xcbf29ce484222325)
	for i in 0 .. name.len {
		hash = (hash ^ u64(name[i])) * 0x100000001b3
	}
	return hash
}

// The input of an iteration. The first few are the seeds as they are.
pub fn input(target Target, seed u64, iteration int) []u8 {
	if target.seeds.len == 0 {
		return []u8{}
	}
	if iteration < target.seeds.len {
		return target.seeds[iteration].bytes()
	}
	mut random := Random{
		state: seed ^ name_hash(target.name) ^ (u64(iteration) * 0xd1342543de82ef95)
	}
	mut data := target.seeds[random.below(target.seeds.len)].bytes()
	for _ in 0 .. random.below(4) + 1 {
		match random.below(9) {
			0 {
				if data.len > 0 {
					data[random.below(data.len)] ^= u8(1) << u8(random.below(8))
				}
			}
			1 {
				if data.len > 0 {
					data[random.below(data.len)] = u8(random.next())
				}
			}
			2 {
				if data.len > 0 {
					data[random.below(data.len)] = interesting[random.below(interesting.len)]
				}
			}
			3 {
				data.insert(random.below(data.len + 1), interesting[random.below(interesting.len)])
			}
			4 {
				if data.len > 0 {
					start := random.below(data.len)
					count := random.below(data.len - start) + 1
					data.delete_many(start, if count > 16 { 16 } else { count })
				}
			}
			5 {
				// The same stretch twice: repeated fields, repeated lines.
				if data.len > 0 && data.len < 16384 {
					start := random.below(data.len)
					count := random.below(data.len - start) + 1
					piece := data[start..start + count].clone()
					data.insert(start, piece)
				}
			}
			6 {
				data = data[..random.below(data.len + 1)].clone()
			}
			7 {
				// The head of one seed and the tail of another.
				other := target.seeds[random.below(target.seeds.len)].bytes()
				cut := random.below(data.len + 1)
				from := random.below(other.len + 1)
				mut joined := data[..cut].clone()
				joined << other[from..]
				data = joined.clone()
			}
			else {
				// A number made large.
				for i in 0 .. data.len {
					if data[i] >= `0` && data[i] <= `9` && random.below(4) == 0 {
						data[i] = `9`
					}
				}
			}
		}
	}
	return data
}

// Run iterations [from, to) in this process; exit status 0 when none
// complained, 3 when one did (its number and complaint go down `report`).
fn run_window(target Target, options Options, from int, to int, report int) {
	C.alarm(u32(options.window_seconds))
	for iteration in from .. to {
		data := input(target, options.seed, iteration)
		target.run(data) or {
			line := '${iteration} ${err.msg()}\n'
			C.write(report, line.str, usize(line.len))
			C._exit(3)
		}
	}
	C._exit(0)
}

// How a window ended: '' for well, otherwise the iteration and what went
// wrong.
fn try_window(target Target, options Options, from int, to int) (int, string) {
	mut report := [2]i32{}
	if C.pipe(&report[0]) != 0 {
		return from, 'cannot make a pipe'
	}
	child := C.fork()
	if child == 0 {
		C.close(report[0])
		run_window(target, options, from, to, int(report[1]))
	}
	C.close(report[1])
	mut buffer := []u8{len: 512}
	got := C.read(report[0], buffer.data, 512)
	C.close(report[0])
	mut status := i32(0)
	C.waitpid(child, &status, 0)
	if status == 0 {
		return -1, ''
	}
	if (status >> 8) & 0xff == 3 && got > 0 {
		line := buffer[..got].bytestr().trim_space()
		return line.all_before(' ').int(), line.all_after(' ')
	}
	// Died without a word: a crash, or the alarm.
	return -2, if status & 0x7f == 14 { 'hang' } else { 'crash' }
}

// Fuzz one target. Returns what was found, at most one finding: the first.
pub fn fuzz(target Target, options Options) ?Finding {
	if options.only >= 0 {
		iteration, what := try_window(target, options, options.only, options.only + 1)
		if iteration == -1 {
			return none
		}
		return Finding{
			target:    target.name
			iteration: options.only
			what:      what
			input:     input(target, options.seed, options.only)
		}
	}
	mut from := 0
	for from < options.iterations {
		to := if from + window < options.iterations { from + window } else { options.iterations }
		iteration, what := try_window(target, options, from, to)
		if iteration == -1 {
			from = to
			continue
		}
		if iteration >= 0 {
			return Finding{
				target:    target.name
				iteration: iteration
				what:      what
				input:     input(target, options.seed, iteration)
			}
		}
		// Which one of the window killed the process.
		for single in from .. to {
			one, how := try_window(target, options, single, single + 1)
			if one != -1 {
				return Finding{
					target:    target.name
					iteration: single
					what:      how
					input:     input(target, options.seed, single)
				}
			}
		}
		// It did not happen again one at a time: say so rather than pass.
		return Finding{
			target:    target.name
			iteration: from
			what:      '${what} somewhere in iterations ${from}..${to - 1}, not reproduced singly'
			input:     []u8{}
		}
	}
	return none
}

// An input in a form that can be pasted: text where it is text.
pub fn show(data []u8) string {
	mut out := []u8{}
	for index, ch in data {
		if index == 400 {
			out << ' ...'.bytes()
			break
		}
		if ch == `\n` {
			out << `\\`
			out << `n`
		} else if ch >= 0x20 && ch < 0x7f && ch != `\\` {
			out << ch
		} else {
			out << '\\x${ch:02x}'.bytes()
		}
	}
	return out.bytestr()
}

// Keep the input of a finding where it can be picked up.
pub fn save(finding Finding, directory string) string {
	os.mkdir_all(directory) or { return '' }
	path := os.join_path(directory, '${finding.target}-${finding.iteration}.bin')
	os.write_file_array(path, finding.input) or { return '' }
	return path
}
