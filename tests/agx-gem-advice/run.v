// SPDX-License-Identifier: GPL-2.0-or-later
import os

fn execute(repo string, args []string, state string, expected int) !string {
	os.mkdir_all(state)!
	os.setenv('AGX_CLOSE_TEST_C', state + '/host.c', true)
	os.setenv('AGX_CLOSE_TEST_BINARY', state + '/host', true)
	os.setenv('ASAN_OPTIONS', 'detect_stack_use_after_return=1', true)
	mut p := os.new_process(os.getenv_opt('V') or { 'v' })
	mut arguments := ['run', repo + '/tests/agx-file-close/run.v']
	arguments << args
	p.set_args(arguments)
	p.set_redirect_stdio_merged(); p.run()
	out := p.stdout_slurp(); p.wait()
	os.write_file(state + '/host.log', out)!
	assert p.code == expected, out
	assert os.exists(state + '/host') && os.exists(state + '/host.c'), 'negative must compile'
	p.close(); return out
}

fn main() {
	assert os.args.len == 3 && os.args[1] in ['host', 'negative', 'measure', 'trace']
	repo := os.real_path(os.join_path(os.dir(@FILE), '../..')); state := os.abs_path(os.args[2])
	assert !state.starts_with(repo + '/') && !os.exists(state)
	if os.args[1] == 'trace' {
		_ = execute(repo, ['--advice-trace'], state, 0)!
		println('Native resident advice trace retained.')
		return
	}
	if os.args[1] == 'measure' {
		out := execute(repo, ['--advice-measure'], state, 0)!
		assert out.count('retained_blocks=0 retained_bytes=0') == 3
		println('Three warmed 10000-operation advice batches retain zero host malloc blocks/bytes.')
		return
	}
	if os.args[1] == 'host' {
		out := execute(repo, [], state, 0)!
		assert out.contains('GEM advice: 96') && out.contains('AGX modern VM_BIND: 1200')
		println('Sanitized GEM advice, modern transport and file/VM/queue lifetime regressions pass.')
		return
	}
	os.mkdir_all(state)!
	for index, spec in [
		['kernel/gpu/agx/file/modern.v', 'data.pad != 0 || data.madv > 1', 'data.madv > 1', 'advice validation and ownership precedence'],
		['kernel/drm/gem/advice.v', 'object.vm_private_identity == 0 || ', '', 'advice validation and ownership precedence'],
		['kernel/gpu/agx/file/modern.v', 'defer { gem.unref(object) }', '', 'advice lookup reference must be released on every exit'],
		['kernel/drm/gem/advice.v', 'owned.advice_dontneed = dontneed', 'owned.advice_dontneed = !dontneed', 'advice state must change only on success'],
	] {
		source := os.read_file(repo + '/' + spec[0])!
		assert source.count(spec[1]) == 1
		path := state + '/mutant-${index}.v'
		os.write_file(path, source.replace(spec[1], spec[2]))!
		mut args := []string{}
		if spec[0].ends_with('/modern.v') { args = ['--modern-source', path] }
		else { os.setenv('AGX_MADVISE_SOURCE', path, true) }
		out := execute(repo, args, state + '/case-${index}', 1)!
		assert out.contains(spec[3]), out
		os.unsetenv('AGX_MADVISE_SOURCE')
	}
	println('Four compiled advice negatives fail header/private eligibility, reference-unwind and state assertions.')
}
