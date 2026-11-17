// SPDX-License-Identifier: GPL-2.0-or-later
import os

fn main() {
	assert os.args.len == 4, 'usage: counterexamples RUNNER BASELINE_DIRECTORY FRESH_OUTPUT'
	repo := os.real_path(os.join_path(os.dir(@FILE), '../..'))
	root := os.abs_path(os.args[3]); assert !root.starts_with(repo + '/') && !os.exists(root); os.mkdir_all(root)!
	allocator := os.read_file(repo + '/kernel/gpu/agx/alloc/alloc.v')!
	manager := os.read_file(repo + '/kernel/gpu/agx/gpu/gpu.v')!
	variants := [
		['baseline', os.read_file(os.args[2] + '/alloc.v')!, os.read_file(os.args[2] + '/gpu.v')!],
		['private-policy', allocator, manager.replace('g13_private: alloc.new_heap_with_explicit_gc(', 'g13_private: alloc.new_heap(')],
		['readonly-policy', allocator, manager.replace('g13_gpu_readonly: alloc.new_heap_with_explicit_gc(', 'g13_gpu_readonly: alloc.new_heap(')],
		['missing-guard', allocator.replace('if !h.gc_on_pressure { return none }', ''), manager],
		['inverted-guard', allocator.replace('if !h.gc_on_pressure { return none }', 'if h.gc_on_pressure { return none }'), manager],
		['constructor-policy', allocator.replace('heap.gc_on_pressure = false', 'heap.gc_on_pressure = true'), manager],
	]
	for item in variants {
		assert item[1] != allocator || item[2] != manager
		dir := root + '/' + item[0]; os.mkdir_all(dir)!
		os.write_file(dir + '/alloc.v', item[1])!; os.write_file(dir + '/gpu.v', item[2])!
		os.setenv('AGX_PRESSURE_C', dir + '/test.c', true); os.setenv('AGX_PRESSURE_BINARY', dir + '/test', true)
		mut p := os.new_process(os.abs_path(os.args[1]))
		p.set_args(['--manager-source', dir + '/gpu.v', '--allocator-source', dir + '/alloc.v']); p.set_redirect_stdio_merged(); p.run()
		out := p.stdout_slurp(); p.wait(); code := p.code; p.close(); os.write_file(dir + '/run.log', out)!
		assert code != 0 && out.contains('allocation pressure must not collect unacknowledged firmware ranges') && !out.contains('error:'), item[0]
		assert os.is_file(dir + '/test.c') && os.is_file(dir + '/test')
		println(item[0] + ': compiled; unacknowledged range reuse rejected')
	}
}
