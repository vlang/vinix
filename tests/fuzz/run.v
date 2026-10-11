// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// The fuzzer's command line. README.md says what it is for and how to add a
// target; targets.v is the list.
//
//	tests/fuzz/run                         every target, 20000 inputs each
//	tests/fuzz/run --list
//	tests/fuzz/run --target passwd --iterations 2000000 --seed 7
//	tests/fuzz/run --target passwd --seed 7 --only 4711      one input again
module main

import fuzzcore
import os

fn main() {
	mut wanted := []string{}
	mut seed := u64(1)
	mut iterations := 20000
	mut only := -1
	mut keep := ''
	mut args := os.args[1..].clone()
	for args.len > 0 {
		option := args[0]
		if option == '--list' {
			for target in targets {
				println('${target.name:-18} ${target.about}')
			}
			return
		}
		if args.len < 2 {
			eprintln('fuzz: ${option} needs a value')
			exit(2)
		}
		match option {
			'--target' { wanted << args[1] }
			'--seed' { seed = args[1].u64() }
			'--iterations' { iterations = args[1].int() }
			'--only' { only = args[1].int() }
			'--keep' { keep = args[1] }
			else {
				eprintln('fuzz: unknown option ${option}')
				exit(2)
			}
		}
		args = args[2..].clone()
	}
	for name in wanted {
		if targets.filter(it.name == name).len == 0 {
			eprintln('fuzz: no target ${name}; --list shows them')
			exit(2)
		}
	}
	mut found := 0
	for target in targets {
		if wanted.len > 0 && target.name !in wanted {
			continue
		}
		finding := fuzzcore.fuzz(target, seed: seed, iterations: iterations, only: only) or {
			println('ok    ${target.name:-18} ${if only >= 0 { 1 } else { iterations }} inputs')
			continue
		}
		found++
		println('FOUND ${target.name}: ${finding.what}')
		println('  again: tests/fuzz/run --target ${target.name} --seed ${seed} --only ${finding.iteration}')
		println('  input: ${fuzzcore.show(finding.input)}')
		if keep != '' {
			println('  kept:  ${fuzzcore.save(finding, keep)}')
		}
	}
	exit(if found == 0 { 0 } else { 1 })
}
