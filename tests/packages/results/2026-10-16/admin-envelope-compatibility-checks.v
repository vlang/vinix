module main
import os
fn main() {
	work := os.real_path(os.dir(@FILE)); v := os.real_path('build/package-release-work/v-toolchain/v')
	os.setenv('V_MACOS_V3_NO_FALLBACK', '1', true); os.setenv('V_C_ERROR_BUG_REPORT_DISABLED', '1', true)
	for kind in ['baseline', 'final']! {
		file := work + '/' + kind + '/pkgadmin/compatibility_test.v'
		os.cp(work + '/compatibility.v', file)!
		mut child := os.new_process(v)
		child.set_args(['-keepc', '-nocache', '-no-skip-unused', '-gc', 'none', '-manualfree', '-path', '@vlib|@vmodules|.|tools/accounts', '-o', work + '/compat-' + kind, file])
		child.set_redirect_stdio_merged(); child.run(); output := child.stdout_slurp(); child.wait(); code := child.code; child.close()
		os.write_file(work + '/compat-' + kind + '-compile.txt', output)!
		if code != 0 { print(output); exit(code) }
		result := os.exec([work + '/compat-' + kind]); os.write_file(work + '/compat-' + kind + '-run.txt', result.output)!
		if result.exit_code != 0 { print(result.output); exit(result.exit_code) }
	}
	before := os.read_file(work + '/compat-baseline-run.txt')!; after := os.read_file(work + '/compat-final-run.txt')!
	assert before == after
	println('Identical compatibility rows: ' + after.split_into_lines().len.str())
}
