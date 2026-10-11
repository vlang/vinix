// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// The fuzzer finds what it is for: a complaint, a crash and a hang, each
// pinned to the one input that causes it, and the same input again from the
// same three numbers. Build with -gc none: the targets run in forked
// processes.
module fuzzcore

fn complains(data []u8) ! {
	if data.len > 3 && data[0] == `b` && data[1] == `a` && data[2] == `d` {
		return error('starts with bad')
	}
}

fn crashes(data []u8) ! {
	if data.len == 5 {
		empty := []u8{}
		// Out of bounds on purpose.
		_ = empty[data.len]
	}
}

fn hangs(data []u8) ! {
	if data.len == 2 {
		for {
		}
	}
}

fn fine(data []u8) ! {
	if data.len > 100000 {
		return error('an input grew without bound')
	}
}

fn test_inputs_are_reproducible() {
	target := Target{
		name:  'fine'
		seeds: ['seed one', 'another seed']
		run:   fine
	}
	assert input(target, 7, 0) == 'seed one'.bytes()
	assert input(target, 7, 1) == 'another seed'.bytes()
	mut different := 0
	for iteration in 2 .. 200 {
		first := input(target, 7, iteration)
		assert first == input(target, 7, iteration)
		if first != input(target, 8, iteration) {
			different++
		}
	}
	// Another seed is another run.
	assert different > 150
}

fn test_a_clean_target_passes() {
	target := Target{
		name:  'fine'
		seeds: ['seed one', 'another seed']
		run:   fine
	}
	if finding := fuzz(target, iterations: 3000) {
		assert false, finding.what
	}
}

fn test_a_complaint_is_pinned() {
	target := Target{
		name:  'complains'
		seeds: ['bat and ball', 'mad']
		run:   complains
	}
	finding := fuzz(target, iterations: 50000) or {
		assert false, 'not found'
		return
	}
	assert finding.what == 'starts with bad'
	assert finding.input.len > 3 && finding.input[..3] == 'bad'.bytes()
	assert finding.input == input(target, 1, finding.iteration)
	// The one iteration again, alone.
	again := fuzz(target, only: finding.iteration) or {
		assert false, 'not reproduced'
		return
	}
	assert again.iteration == finding.iteration && again.what == 'starts with bad'
	// And the one before it is clean.
	if before := fuzz(target, only: finding.iteration - 1) {
		assert false, before.what
	}
}

fn test_a_crash_is_pinned() {
	target := Target{
		name:  'crashes'
		seeds: ['abcdefgh']
		run:   crashes
	}
	finding := fuzz(target, iterations: 20000) or {
		assert false, 'not found'
		return
	}
	assert finding.what == 'crash'
	assert finding.input.len == 5
}

fn test_a_hang_is_pinned() {
	target := Target{
		name:  'hangs'
		seeds: ['abcd']
		run:   hangs
	}
	finding := fuzz(target, iterations: 20000, window_seconds: 1) or {
		assert false, 'not found'
		return
	}
	assert finding.what == 'hang'
	assert finding.input.len == 2
}

fn test_show() {
	assert show('a:b\n\x00\xff\\'.bytes()) == 'a:b\\n\\x00\\xff\\x5c'
	assert show([]u8{len: 500, init: `a`}).ends_with(' ...')
}
