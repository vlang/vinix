module main
import json2
import os
import time
struct Result { name string code int seconds f64 }
fn task(name string, argv []string, work string) !Result {
	mut child := os.new_process(argv[0]); child.set_args(argv[1..]); child.set_redirect_stdio_merged()
	started := time.now(); child.run(); output := child.stdout_slurp(); child.wait(); code := child.code; child.close()
	os.write_file(work + '/' + name + '.txt', output)!
	assert code == 0 && !output.contains('V panic:') && !output.contains(': fn test_'), name + ': ' + output
	println(name + ' PASS')
	return Result{ name: name, code: code, seconds: f64(time.since(started).milliseconds()) / 1000.0 }
}
fn main() {
	work := os.real_path(os.dir(@FILE)); v := os.real_path('build/package-release-work/v-toolchain/v')
	os.setenv('V_MACOS_V3_NO_FALLBACK', '1', true); os.setenv('V_C_ERROR_BUG_REPORT_DISABLED', '1', true)
	mut results := []Result{}
	for mode, expected in {'legacy': 'packages-native-catalog', 'image': 'packages-native-image', 'software': 'packages-software-image'} {
		mut argv := [os.real_path('build/package-image-configuration-work/software-controller')]
		if mode != 'legacy' { argv << '--' + mode }
		argv << '--list'
		results << task('list-' + mode, argv, work)!
		assert os.read_file(work + '/list-' + mode + '.txt')!.contains(expected)
	}
	for name in ['boot', 'suite']! {
		results << task(name + '-compile', [v, '-nocache', '-no-skip-unused', '-o', work + '/' + name,
			'tests/hardware-platform/hwhost/' + name + '_test.v'], work)!
		results << task(name + '-run', [work + '/' + name], work)!
	}
	os.write_file(work + '/host.json', json2.encode(results) + '\n')!
}
