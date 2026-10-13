// SPDX-License-Identifier: GPL-2.0-or-later
module devcore

import json2
import os
import sourcecommand
import time

#include <signal.h>
fn C.kill(int, int) int

struct InterruptCase {
	root string
	signal int
	deadline u64
}

fn interrupt_nested_build(pid int, raw voidptr) ! {
	context := unsafe { &InterruptCase(raw) }
	for !os.exists(context.root + '/compiler-child.pid') {
		if sourcecommand.child_exited(pid)! || time.sys_mono_now() >= context.deadline {
			return error('nested compiler did not start')
		}
		time.sleep(10 * time.millisecond)
	}
	if C.kill(pid, context.signal) != 0 { return error('cannot interrupt owned build') }
	for !sourcecommand.child_exited(pid)! {
		if time.sys_mono_now() >= context.deadline { return error('nested build did not retire') }
		time.sleep(10 * time.millisecond)
	}
}

fn test_build_interruptions_propagate_to_qualifier_and_compiler_groups() {
	root := sourcecommand.temporary('vinix-ci-cancellation')!
	defer { os.rmdir_all(root) or {} }
	repository := os.dir(os.dir(os.dir(os.dir(@FILE))))
	for tool in ['build', 'qualify'] {
		result := sourcecommand.capture([@VEXE, '-gc', 'none', '-cc', 'cc', '-o', root + '/' + tool,
			repository + '/tools/development/' + tool + '.v'], os.environ(), 120, 65536, unsafe { nil })!
		assert result.status == 0, result.stderr
	}
	os.mkdir(root + '/bin')!
	// A compiler and descendant ignore TERM, requiring their own owner to
	// complete its SIGKILL fallback. Their finite lifetime bounds a failed test.
	os.write_file(root + '/compiler.v', 'module main\nimport os\nimport time\n#include <unistd.h>\nfn C.fork() int\nfn ignore(signal os.Signal) {}\nfn main() { os.signal_opt(.term, ignore)!; os.signal_opt(.int, ignore)!; root := os.getenv("PROOF_ROOT"); os.write_file(root + "/compiler.pid", os.getpid().str())!; child := C.fork(); if child == 0 { os.write_file(root + "/compiler-child.pid", os.getpid().str())! }; for _ in 0 .. 200 { time.sleep(100 * time.millisecond) } }\n')!
	source := os.read_file(root + '/compiler.v')!
	for number, signal in [C.SIGTERM, C.SIGINT] {
		case_root := root + '/case-' + number.str()
		os.mkdir(case_root)!
		os.mkdir(case_root + '/source')!
		plan := BuildPlan{source: Pin{case_root + '/source', tree_hash(case_root + '/source')!},
			tools: {'qualifier': Pin{root + '/qualify', file_hash(root + '/qualify')!}}, timeout_seconds: 30,
			environment: {'PATH': root + '/bin', 'PROOF_ROOT': case_root},
			steps: [BuildStep{name: 'qualify', argv: ['{qualifier}', '{work}/qualification', 'go']}]}
		// Embed the proof root since the qualifier sanitizes inherited values.
		os.write_file(root + '/compiler.v', source.replace('root := os.getenv("PROOF_ROOT")',
			'root := "' + case_root + '"'))!
		rebuilt := sourcecommand.capture([@VEXE, '-gc', 'none', '-cc', 'cc', '-o', root + '/bin/go', root + '/compiler.v'],
			os.environ(), 120, 65536, unsafe { nil })!
		assert rebuilt.status == 0, rebuilt.stderr
		os.write_file(case_root + '/plan.json', json2.encode(plan))!
		context := InterruptCase{case_root, signal, time.sys_mono_now() + u64(8 * time.second)}
		result := sourcecommand.run_logged_owned([root + '/build', 'build', case_root + '/plan.json', case_root + '/output'],
			environment(0), unsafe { nil }, case_root + '/outer.log', false, root,
			interrupt_nested_build, unsafe { &context }, 8)!
		assert result.status == 1
		receipt := json2.decode[BuildReceipt](os.read_file(case_root + '/output/receipt.json')!)!
		assert !receipt.complete && receipt.steps.len == 1
		assert receipt.steps[0].exit_code == -1 && receipt.steps[0].detail == 'command interrupted'
		for file in ['compiler.pid', 'compiler-child.pid'] {
			observed := os.read_file(case_root + '/' + file)!.int()
			assert observed > 1
			deadline := time.sys_mono_now() + u64(2 * time.second)
			for C.kill(observed, 0) == 0 {
				assert time.sys_mono_now() < deadline, 'compiler descendant survived cancellation'
				time.sleep(10 * time.millisecond)
			}
			assert C.errno == C.ESRCH
		}
	}
}
