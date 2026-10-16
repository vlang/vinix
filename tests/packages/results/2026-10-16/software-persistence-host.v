module main
import json2
import os
import time
struct Check { name string code int seconds f64 }
fn task(name string, argv []string, work string, expected int, marker string) !Check {
	mut child := os.new_process(argv[0]); child.set_args(argv[1..]); child.set_redirect_stdio_merged()
	started := time.now(); child.run(); output := child.stdout_slurp(); child.wait(); code := child.code; child.close()
	os.write_file(work + '/' + name + '.txt', output)!
	assert code == expected && output.contains(marker) && !output.contains('V panic:'), output
	println(name + ' PASS')
	return Check{ name: name, code: 0, seconds: f64(time.since(started).milliseconds()) / 1000.0 }
}
fn main() {
	work := os.real_path(os.dir(@FILE)); v := os.real_path('build/package-release-work/v-toolchain/v')
	os.setenv('V_MACOS_V3_NO_FALLBACK', '1', true); os.setenv('V_C_ERROR_BUG_REPORT_DISABLED', '1', true)
	mut checks := []Check{}
	checks << task('controller-compile', [v, '-keepc', '-nocache', '-no-skip-unused', '-gc', 'none', '-manualfree',
		'-path', '@vlib|@vmodules|.|tools/accounts|tests/hardware-platform', '-o', work + '/controller', 'tests/packages/native-catalog-check.v'], work, 0, '')!
	for mode, scenario in {'legacy': 'packages-native-catalog', 'image': 'packages-native-image', 'software': 'packages-software-image', 'persistent': 'packages-software-persistence'} {
		checks << task('list-' + mode, [work + '/controller', ...if mode == 'legacy' { []string{} } else { ['--' + mode] }, '--list'], work, 0, scenario)!
	}
	os.unsetenv('VINIX_HWTEST_TCG')
	checks << task('persistent-input-refusal', [work + '/controller', '--persistent', '--arch', 'aarch64', '--kernel', work + '/absent'], work, 2, 'provide VINIX_HWTEST_TCG=1')!
	os.write_file(work + '/host.json', json2.encode(checks) + '\n')!
}
