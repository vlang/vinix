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
	flags := ['-prod', '-keepc', '-nocache', '-no-skip-unused', '-gc', 'none', '-manualfree', '-path', '@vlib|@vmodules|.|tools/accounts|tests/hardware-platform']
	mut checks := []Check{}
	checks << task('controller-compile', [v, ...flags, '-o', work + '/controller', 'tests/packages/native-catalog-check.v'], work, 0, '')!
	for mode, scenario in {'legacy': 'packages-native-catalog', 'image': 'packages-native-image', 'software': 'packages-software-image', 'persistent': 'packages-software-persistence', 'installed': 'packages-software-installed'} {
		checks << task('list-' + mode, [work + '/controller', ...if mode == 'legacy' { []string{} } else { ['--' + mode] }, '--list'], work, 0, scenario)!
	}
	os.unsetenv('VINIX_HWTEST_TCG')
	checks << task('installed-input-refusal', [work + '/controller', '--installed', '--arch', 'aarch64', '--kernel', work + '/absent'], work, 2, 'provide VINIX_HWTEST_TCG=1')!
	controller := os.read_file('tests/packages/native-catalog-check.v')!
	begin := controller.index('fn native_artifact(') or { panic('missing artifact function') }
	end := controller.index('\nconst installed_image_id') or { panic('missing artifact boundary') }
	os.write_file(work + '/hash-check.v', os.read_file(work + '/hash-probe.v')! + '\nstruct NativeArtifact { role string bytes u64 sha256 string }\n' + controller[begin..end])!
	checks << task('hash-compile', [v, ...flags, '-o', work + '/hash-check', work + '/hash-check.v'], work, 0, '')!
	checks << task('hash-run', [work + '/hash-check'], work, 0, 'PACKAGE RECEIPT stream SHA-256')!
	os.write_file(work + '/host.json', json2.encode(checks) + '\n')!
}
