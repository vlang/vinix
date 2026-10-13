// SPDX-License-Identifier: GPL-2.0-or-later
import os

fn run(program string, arguments []string) !(int, string) {
	mut process := os.new_process(program)
	process.set_args(arguments)
	process.set_redirect_stdio_merged()
	process.run()
	output := process.stdout_slurp()
	process.wait()
	code := process.code
	process.close()
	return code, output
}

fn main() {
	root := os.dir(os.dir(os.dir(@FILE)))
	if os.args.len != 3 { panic('usage: signing-source-check V_GIT_CHECKOUT WORK_DIRECTORY') }
	checkout := os.abs_path(os.args[1])
	work := os.abs_path(os.args[2]) + '/signing-source-' + os.getpid().str()
	assert !os.exists(work)
	os.mkdir_all(work + '/tools/packages')!
	defer { os.rmdir_all(work) or {} }
	os.cp(root + '/tools/packages/vendor-signing.v', work + '/tools/packages/vendor-signing.v')!
	copy := work + '/tools/packages/signing'
	os.cp_all(root + '/tools/packages/signing', copy, false)!
	compiler := os.find_abs_path_of_executable(os.getenv_opt('V') or { 'v' })!
	code, output := run(compiler, ['-no-skip-unused', '-o', work + '/validator', work + '/tools/packages/vendor-signing.v'])!
	assert code == 0, output
	arguments := ['--check', checkout]
	ok, initial := run(work + '/validator', arguments)!
	assert ok == 0, initial
	original := os.read_file(copy + '/signing.v')!
	os.write_file(copy + '/signing.v', original + '// changed\n')!
	changed, changed_text := run(work + '/validator', arguments)!
	assert changed != 0 && changed_text.contains('differs'), changed_text
	os.write_file(copy + '/signing.v', original)!
	os.write_file(copy + '/unexpected.v', 'module signing\n')!
	extra, extra_text := run(work + '/validator', arguments)!
	assert extra != 0 && extra_text.contains('unrecorded'), extra_text
	os.rm(copy + '/unexpected.v')!
	os.write_file(work + '/external.v', original)!
	os.rm(copy + '/signing.v')!
	os.symlink(work + '/external.v', copy + '/signing.v')!
	linked, linked_text := run(work + '/validator', arguments)!
	assert linked != 0 && linked_text.contains('symlink'), linked_text
	os.rm(copy + '/signing.v')!
	os.write_file(copy + '/signing.v', original)!
	os.rename(copy, work + '/actual')!
	os.symlink(work + '/actual', copy)!
	root_linked, root_text := run(work + '/validator', arguments)!
	assert root_linked != 0 && root_text.contains('ordinary directory'), root_text
	os.rm(copy)!
	os.rename(work + '/actual', copy)!
	println('Signing source checks: pinned bytes, mutation, extra implementation and file/root symlink refusal passed')
}
