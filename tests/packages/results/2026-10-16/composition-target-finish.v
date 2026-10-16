module main
import crypto.sha256
import json2
import os
import time
struct Pin { path string bytes u64 sha256 string }
struct Build { name string seconds f64 artifacts []Pin }
fn task(name string, argv []string, work string, expected int, marker string) ! {
	mut child := os.new_process(argv[0]); child.set_args(argv[1..]); child.set_redirect_stdio_merged()
	child.run(); output := child.stdout_slurp(); child.wait(); code := child.code; child.close()
	os.write_file(work + '/' + name + '.txt', output)!
	assert code == expected && output.contains(marker), output
	println(name + ' PASS')
}
fn main() {
	work := os.real_path(os.dir(@FILE)); controller := work + '/controller'
	task('list-aarch64', [controller, '--arch', 'aarch64', '--list'], work, 0, 'packages-apple')!
	task('list-x86_64', [controller, '--arch', 'x86_64', '--list'], work, 0, '')!
	assert !os.read_file(work + '/list-x86_64.txt')!.contains('packages-apple')
	task('reject-x86_64', [controller, '--arch', 'x86_64', '--kernel', work + '/absent'], work, 2, 'no x86-64 translation runtime is supplied')!
	os.unsetenv('VINIX_HWTEST_TCG')
	task('reject-inputs', [controller, '--arch', 'aarch64', '--kernel', work + '/absent'], work, 2, 'VINIX_HWTEST_TCG=1')!
	os.setenv('V', os.real_path('build/package-release-work/v-toolchain/v'), true); os.setenv('VFLAGS', '-nocache', true)
	os.setenv('V_MACOS_V3_NO_FALLBACK', '1', true); os.setenv('V_C_ERROR_BUG_REPORT_DISABLED', '1', true)
	os.unsetenv('VINIX_PACKAGE_IMAGE_CONFIG'); os.unsetenv('VINIX_PACKAGE_IMAGE_REPOSITORIES')
	root := work + '/x86-root'; assert !os.exists(root); os.mkdir(root)!
	start := time.now()
	task('x86-stage', [work + '/stage', '--arch', 'x86_64', '--cc', '/opt/homebrew/bin/x86_64-linux-musl-gcc', '--staging', root], work, 0, '')!
	mut artifacts := []Pin{}
	for path in ['usr/bin/vinix-package', 'usr/sbin/vinix-session', 'usr/libexec/vinix/vinix-linux-runner'] {
		bytes := os.read_bytes(root + '/' + path)!
		assert bytes[..6] == [u8(127), `E`, `L`, `F`, 2, 1] && bytes[18] == 62 && bytes[19] == 0
		artifacts << Pin{ path: root + '/' + path, bytes: u64(bytes.len), sha256: sha256.sum(bytes).hex() }
	}
	os.write_file(work + '/x86-stage.json', json2.encode(Build{ name: 'x86_64 production staging; Apple runtime execution remains unsupported', seconds: f64(time.since(start).milliseconds()) / 1000.0, artifacts: artifacts }) + '\n')!
}
