// SPDX-License-Identifier: GPL-2.0-or-later
import os

fn main() {
	assert os.args.len == 2, 'usage: v run tests/drm-timeline-chain/run.v FRESH_EXTERNAL_STATE'
	os.setenv('V_C_ERROR_BUG_REPORT_DISABLED', '1', true)
	repo := os.real_path(os.join_path(os.dir(@FILE), '../..'))
	state := os.abs_path(os.args[1])
	assert !os.exists(state) && !state.starts_with(repo + '/')
	os.mkdir_all(state + '/drm')!
	os.cp_all(repo + '/kernel/drm/syncobj', state + '/drm/syncobj', false)!
	if path := os.getenv_opt('CHAIN_SOURCE') { os.cp(path, state + '/drm/syncobj/chain.v')! }
	os.cp(repo + '/tests/drm-timeline-chain/checks.v', state + '/drm/syncobj/checks.v')!
	for name in ['katomic', 'sched', 'time', 'memory', 'event'] {
		os.cp_all(repo + '/tests/agx-async/fixture/' + name, state + '/' + name, false)!
	}
	os.cp_all(repo + '/tests/agx-file-close/fixture/klock', state + '/klock', false)!
	os.write_file(state + '/main.v', 'import drm.syncobj\nimport os\nfn main() { if os.args.len > 1 { syncobj.run_chain_trace(); return }; syncobj.run_chain_checks() or { panic("chain check option failed") } }\n')!
	for output in ['check', 'check.c'] {
		mut p := os.new_process(os.getenv_opt('V') or { 'v' })
		p.set_args(['-nocache', '-no-parallel', '-cc', 'cc', '-enable-globals', '-gc', 'none', '-manualfree',
			'-path', state + '|@vlib|@vmodules', '-cflags', '-fsanitize=address,undefined -fno-omit-frame-pointer',
			'-ldflags', '-fsanitize=address,undefined', '-o', state + '/' + output, state + '/main.v'])
		p.run(); p.wait()
		assert p.code == 0
	}
	mut p := os.new_process(state + '/check')
	p.set_redirect_stdio_merged(); p.run()
	result := p.stdout_slurp(); p.wait()
	os.write_file(state + '/check.log', result)!
	print(result)
	assert p.code == 0
}
