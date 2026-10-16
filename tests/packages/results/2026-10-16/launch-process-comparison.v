module pkgcore
import os
#include "@VMODROOT/../../../desktop/tools/tests/heap_tracker.h"
fn C.vinix_heap_begin()
fn C.vinix_heap_end() u64
// The plan is borrowed; this probe measures only execution storage.
fn baseline_run(launch Launch) int {
	$if !launch_process_baseline ? { return run_launch_process(launch) or { panic(err) } }
	$else {
	mut process := os.new_process(launch.program)
	process.set_args(launch.arguments); process.set_work_folder(launch.directory)
	process.wait(); code := process.code; process.close()
	return code
	}
}
fn test_execution_retention() {
	child := os.getenv('VINIX_PACKAGE_LAUNCH_CHILD')
	assert child != ''
	for mode in ['exit', 'signal']! {
		plan := Launch{ program: child, arguments: if mode == 'exit' { ['exit', '37'] } else { ['signal'] }, directory: '/tmp' }
		assert baseline_run(plan) == if mode == 'exit' { 37 } else { 143 }
		C.vinix_heap_begin()
		for _ in 0 .. 5 { assert baseline_run(plan) == if mode == 'exit' { 37 } else { 143 } }
		kept := C.vinix_heap_end()
		$if !launch_process_baseline ? { assert kept == 0 }
		println('PROCESS ' + mode + ': five waits/closes retained ' + kept.str() + ' bytes')
	}
}
