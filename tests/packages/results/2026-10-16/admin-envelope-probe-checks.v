module main
import os
fn main() {
	work := os.real_path(os.dir(@FILE)); phase := os.args[1]
	base := work + '/' + phase + '/pkgadmin'
	os.mkdir_all(base)!
	os.write_file(work + '/' + phase + '/v.mod', "Module { name: 'admin-protocol-probes' }\n")!
	if phase != 'baseline' || !os.is_file(base + '/protocol.v') {
		for name in os.ls('tools/packages/pkgadmin')! { if name.ends_with('.v') && !name.ends_with('_test.v') { os.cp('tools/packages/pkgadmin/' + name, base + '/' + name)! } }
	}
	os.write_file(base + '/comparison_test.v', os.read_file(work + '/comparison.v')!.replace('@VMODROOT/../../../desktop/tools/tests/heap_tracker.h', os.real_path('desktop/tools/tests/heap_tracker.h')))!
	os.setenv('V_MACOS_V3_NO_FALLBACK', '1', true); os.setenv('V_C_ERROR_BUG_REPORT_DISABLED', '1', true)
	mut child := os.new_process(os.real_path('build/package-release-work/v-toolchain/v'))
	child.set_args(['-keepc', '-nocache', '-no-skip-unused', '-gc', 'none', '-manualfree', '-d', 'track_heap',
		'-path', '@vlib|@vmodules|.|tools/accounts', '-o', work + '/' + phase + '-fixture', base + '/comparison_test.v'])
	child.set_redirect_stdio_merged(); child.run(); output := child.stdout_slurp(); child.wait(); code := child.code; child.close()
	os.write_file(work + '/' + phase + '-compile.txt', output)!
	if code != 0 { print(output); exit(code) }
	result := os.exec([work + '/' + phase + '-fixture'])
	os.write_file(work + '/' + phase + '-run.txt', result.output)!
	print(result.output); exit(result.exit_code)
}
