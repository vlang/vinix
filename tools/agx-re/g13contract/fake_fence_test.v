// SPDX-License-Identifier: GPL-2.0-or-later
module g13contract

import g13layout

fn check_fake_fences(helper string, driver string) ! {
	require_order(helper, ['syncobj.new_queue_context() or { return none }', 'return syncobj.new_fence(context, 1)'], 'Independent fake submission context, no zero fallback or dependency elision')!
	transaction := section(driver, '\tmut vm_pinned := false\n', '\tstarted := timer.get_count()', 'Fake output publication')!
	require_order(transaction, ['!vm.begin_job()', 'file.inflight_jobs++', 'fence := new_submission_fence() or {',
		'if vm_pinned {', 'vm.finish_job()', 'file.inflight_jobs--', 'file.lock.release()', 'return -12',
		'agxsubmission.install_output_syncs('], 'Context failure after admission, with exact pin unwind before output effects')!
}

fn test_fake_fences_preserve_independent_jobs_and_failure_ownership() {
	r := g13layout.repo_root()
	helper := read(r + '/kernel/gpu/agx/fake/fence.v')!
	driver := read(r + '/kernel/gpu/agx/fake/driver.v')!
	check_fake_fences(helper, driver)!
	for token in ['syncobj.new_queue_context() or { return none }', 'return syncobj.new_fence(context, 1)'] {
		if _ := check_fake_fences(helper.replace(token, ''), driver) { assert false, token }
	}
	for token in ['fence := new_submission_fence() or {', 'vm.finish_job()', 'file.inflight_jobs--', 'return -12'] {
		if _ := check_fake_fences(helper, driver.replace(token, '')) { assert false, token }
	}
}
