// SPDX-License-Identifier: GPL-2.0-or-later
import os

fn main() {
	assert os.args.len == 4, 'usage: counterexamples RUNNER BASELINE_DIRECTORY FRESH_OUTPUT'
	repo := os.real_path(os.join_path(os.dir(@FILE), '../..')); root := os.abs_path(os.args[3])
	assert !root.starts_with(repo + '/') && !os.exists(root); os.mkdir_all(root)!
	allocator := os.read_file(repo + '/kernel/gpu/agx/alloc/alloc.v')!
	manager := os.read_file(repo + '/kernel/gpu/agx/gpu/gpu.v')!
	variants := [
		['baseline-rollback', allocator, os.read_file(os.args[2] + '/gpu.v')!, 'rollback', 'rollback must preserve unrelated pending ranges'],
		['missing-cancel', allocator, manager.replace('heap.cancel_unpublished(va)', '// omitted cancellation'), 'rollback', 'unpublished metadata must retire before physical backing'],
		['pending-owner', allocator.replace('record.va != va || !record.in_use', 'record.va != va'), manager, 'model', 'record.release_order == 0'],
		['missing-free', allocator.replace('unsafe { free(record) }', '// omitted metadata retirement'), manager, 'model', 'cancellation must retire only its live unpublished owner'],
		['missing-unlink', allocator.replace('h.allocations.delete(index)', '// omitted unlink'), manager, 'model', 'heap-use-after-free'],
		['missing-frontier', allocator.replace('if record.va + record.size == h.top {', 'if false {'), manager, 'model', 'heap.top == model.top()'],
		['early-physical-free', allocator, manager.replace('heap.cancel_unpublished(va)\n\t\tmemory.pmm_free(voidptr(phys), pages)', 'memory.pmm_free(voidptr(phys), pages)\n\t\theap.cancel_unpublished(va)'), 'rollback', 'unpublished metadata must retire before physical backing'],
		['pending-count', allocator.replace('h.allocations.delete(index)', 'h.garbage_count = 0\n\t\th.allocations.delete(index)'), manager, 'model', 'pending count must match the release FIFO'],
	]
	for item in variants {
		assert item[1] != allocator || item[2] != manager
		dir := root + '/' + item[0]; os.mkdir_all(dir)!
		os.write_file(dir + '/alloc.v', item[1])!; os.write_file(dir + '/gpu.v', item[2])!
		os.setenv('AGX_CANCEL_C', dir + '/test.c', true); os.setenv('AGX_CANCEL_BINARY', dir + '/test', true)
		mut p := os.new_process(os.abs_path(os.args[1])); p.set_args(['--manager-source', dir + '/gpu.v', '--allocator-source', dir + '/alloc.v', '--case', item[3]])
		p.set_redirect_stdio_merged(); p.run(); out := p.stdout_slurp(); p.wait(); code := p.code; p.close()
		os.write_file(dir + '/run.log', out)!
		assert code != 0 && out.contains(item[4]) && !out.contains('error:'), item[0]
		assert os.is_file(dir + '/test.c') && os.is_file(dir + '/test')
		println(item[0] + ': compiled; designated cancellation/ownership assertion rejected')
	}
}
