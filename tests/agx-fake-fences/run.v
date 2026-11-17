// SPDX-License-Identifier: GPL-2.0-or-later
import os

fn run(repo string, source string, state string, expected int) !string {
	os.mkdir_all(state)!
	os.setenv('DRM_FAKE_FENCE_SOURCE', source, true)
	os.setenv('DRM_SYNCOBJ_WAIT_TEST_C', state + '/host.c', true)
	os.setenv('DRM_SYNCOBJ_WAIT_TEST_BINARY', state + '/host', true)
	os.setenv('ASAN_OPTIONS', 'detect_stack_use_after_return=1', true)
	mut p := os.new_process(os.getenv_opt('V') or { 'v' })
	p.set_args(['run', repo + '/tests/drm-syncobj-wait/run.v'])
	p.set_redirect_stdio_merged(); p.run()
	out := p.stdout_slurp(); p.wait()
	os.write_file(state + '/host.log', out)!
	assert p.code == expected, out
	assert os.exists(state + '/host') && os.exists(state + '/host.c'), 'negative must compile'
	p.close()
	return out
}

fn main() {
	assert os.args.len == 3 && os.args[1] in ['host', 'negative']
	repo := os.real_path(os.join_path(os.dir(@FILE), '../..'))
	state := os.abs_path(os.args[2])
	assert !state.starts_with(repo + '/') && !os.exists(state)
	if os.args[1] == 'host' {
		out := run(repo, repo + '/kernel/gpu/agx/fake/fence.v', state, 0)!
		assert out.contains('Fake fences: 48') && out.contains('Asahi sync lookup: 18600 checks')
		println('Sanitized fake-fence permutations, context exhaustion and full DRM regressions pass.')
		return
	}
	os.mkdir_all(state)!
	source := os.read_file(repo + '/kernel/gpu/agx/fake/fence.v')!
	for index, spec in [
		['return syncobj.new_fence(context, 1)', 'return syncobj.new_fence(7, context)', 'independent fake jobs need distinct contexts'],
		['syncobj.new_queue_context() or { return none }', 'syncobj.new_queue_context() or { u64(0) }', 'exhausted contexts must reject fake submission'],
		['syncobj.new_fence(context, 1)', 'syncobj.new_queue_fence(context, 1, context)', 'fake fences cannot elide queue dependencies'],
	] {
		assert source.count(spec[0]) == 1
		path := state + '/mutant-${index}.v'
		os.write_file(path, source.replace(spec[0], spec[1]))!
		out := run(repo, path, state + '/case-${index}', 1)!
		assert out.contains(spec[2]), out
	}
	driver := os.read_file(repo + '/kernel/gpu/agx/fake/driver.v')!
	old := 'fence := new_submission_fence() or {\n\t\tif vm_pinned {\n\t\t\tvm.finish_job()'
	assert driver.count(old) == 1
	path := state + '/missing-vm-unwind.v'
	os.write_file(path, driver.replace(old, old.replace('vm.finish_job()', '')))!
	os.setenv('DRM_FAKE_DRIVER_SOURCE', path, true)
	out := run(repo, repo + '/kernel/gpu/agx/fake/fence.v', state + '/missing-vm-unwind', 1)!
	assert out.contains('context exhaustion must unwind the VM pin'), out
	println('Four compiled negatives reject shared contexts, exhaustion fallback, dependency elision and a missing VM-pin unwind.')
}
