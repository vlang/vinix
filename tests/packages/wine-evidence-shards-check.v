// SPDX-License-Identifier: GPL-2.0-or-later
// Synthetic collection controls; these do not qualify Wine execution.
module main

import crypto.sha256
import json2
import os
import tests.packages.winecontrols

struct Fixture {
	format          int    = 1
	architecture    string = 'aarch64'
	baseline        bool   = true
	copied_baseline bool   = true
mut:
	refused  []string
	inputs   map[string]string
	shard    int
	shards   int = 2
	expected []string
	forksafe bool = true
}

fn invoke(checker string, out string, first string, second string, log string) !int {
	mut child := os.new_process(checker)
	defer { child.close() }
	child.set_args([out, first, second])
	child.set_redirect_stdio_merged()
	child.run()
	C.close(child.stdio_fd[0])
	child.stdio_fd[0] = -1
	text := child.stdout_slurp()
	defer { unsafe { text.free() } }
	child.wait()
	os.write_file(log, text)!
	return child.code
}

fn run() ! {
	if os.args.len != 3 { return error('usage: wine-evidence-shards-check CHECKER FRESH_OUTPUT') }
	checker := os.real_path(os.args[1])
	work := os.abs_path(os.args[2])
	if os.exists(work) { return error('output must be fresh') }
	os.mkdir_all(work)!
	cases := os.dir(@FILE) + '/winecontrols/cases.v'
	input := work + '/input'
	os.write_file(input, 'original')!
	expected := winecontrols.names('aarch64', true)!
	modes := ['baseline', 'missing-case', 'duplicate-case', 'duplicate-shard', 'wrong-assignment',
		'missing-baseline', 'changed-contract', 'changed-input', 'wrong-count', 'changed-baseline-bytes',
		'retry']
	mut refusals := 0
	for mode in modes {
		directory := work + '/' + mode
		os.mkdir_all(directory + '/0')!
		os.mkdir_all(directory + '/1')!
		for index in 0 .. 2 {
			mut fixture := Fixture{
				shard:    index
				expected: expected.clone()
				inputs:   {
					cases: sha256.hexhash(os.read_file(cases)!)
					input: sha256.hexhash('original')
				}
			}
			for at, name in expected { if at % 2 == index { fixture.refused << name } }
			if index == 1 {
				match mode {
					'missing-case' { fixture.refused.pop() }
					'duplicate-case' { fixture.refused << fixture.refused[0] }
					'duplicate-shard' { fixture.shard = 0 }
					'wrong-assignment' { fixture.refused[0] = expected[0] }
					'missing-baseline' { fixture = Fixture{ ...fixture, baseline: false } }
					'changed-contract' { fixture.expected.pop() }
					'changed-input' { fixture.inputs[input] = '0'.repeat(64) }
					'wrong-count' { fixture.shards = 3 }
					else {}
				}
			}
			os.write_file(directory + '/' + index.str() + '/controls.json', json2.encode(fixture))!
		}
		if mode == 'changed-baseline-bytes' { os.write_file(input, 'changed')! }
		out := directory + '/coverage.json'
		code := invoke(checker, out, directory + '/0', directory + '/1', directory + '/check.log')!
		if mode in ['baseline', 'retry'] {
			if code != 0 || !os.is_file(out) {
				return error('synthetic shard baseline/retry refused')
			}
		} else {
			if code == 0 || os.exists(out) {
				return error('accepted invalid shard collection: ' + mode)
			}
			refusals++
		}
		os.write_file(input, 'original')!
	}
	if refusals != 9 { return error('shard refusal count differs') }
	println('WINE SHARD CHECKER PASS baseline, exact retry and 9 refusal controls')
}

fn main() {
	run() or {
		eprintln(err)
		exit(1)
	}
}
