module main
import os
fn main() {
	work := os.real_path(os.dir(@FILE)); arch := os.args[1]; phase := os.args[2]
	short := if arch == 'aarch64' { 'arm' } else { 'x86' }
	os.setenv('V', os.real_path('build/package-release-work/v-toolchain/v'), true)
	os.setenv('VFLAGS', '-nocache', true); os.setenv('VINIX_HWTEST_TCG', '1', true)
	if arch == 'aarch64' {
		os.setenv('VINIX_AARCH64_SYSROOT', '/opt/homebrew/opt/musl-cross/libexec/aarch64-linux-musl', true)
		os.setenv('CC_AARCH64', os.real_path('build/package-launch-transport-work/cross-cc'), true)
	}
	mut child := os.new_process(work + if phase == 'client' { '/controller' } else { '/admin-controller' })
	mut args := ['--arch', arch, '--kernel', os.real_path('build/package-socket-work/' + short + '/kernel/bin/vinix'), '--state-dir', os.real_path('build') + '/ae-' + phase + '-' + short]
	if phase != 'client' { args << ['--scenario', 'packages-admin'] }
	child.set_args(args); child.set_redirect_stdio_merged(); child.run()
	output := child.stdout_slurp(); child.wait(); code := child.code; child.close()
	os.write_file(work + '/' + phase + '-' + arch + '.txt', output)!
	print(output); exit(code)
}
