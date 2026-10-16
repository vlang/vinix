module main
import os
fn main() {
	work := os.real_path(os.dir(@FILE)); arch := os.args[1]; image := os.args[2] == 'image'
	attempt := if os.args.len > 3 { '-' + os.args[3] } else { '' }
	short := if arch == 'aarch64' { 'arm' } else { 'x86' }
	os.setenv('V', os.real_path('build/package-release-work/v-toolchain/v'), true)
	os.setenv('VFLAGS', '-nocache', true); os.setenv('VINIX_HWTEST_TCG', '1', true)
	os.setenv('V_MACOS_V3_NO_FALLBACK', '1', true); os.setenv('V_C_ERROR_BUG_REPORT_DISABLED', '1', true)
	os.setenv('VINIX_NATIVE_CATALOG_INPUTS', os.real_path('build/package-native-catalog-work/inputs'), true)
	os.setenv('VINIX_NATIVE_CATALOG_SANDBOX', os.real_path('build/package-native-catalog-work/' + if arch == 'aarch64' { 'a3' } else { 'x3' } + '/guest/root/usr/bin/vinix-sandbox'), true)
	if arch == 'aarch64' {
		os.setenv('VINIX_AARCH64_SYSROOT', '/opt/homebrew/opt/musl-cross/libexec/aarch64-linux-musl', true)
		os.setenv('CC_AARCH64', os.real_path('build/package-launch-transport-work/cross-cc'), true)
	}
	mut args := ['--arch', arch, '--kernel', os.real_path('build/package-socket-work/' + short + '/kernel/bin/vinix'),
		'--state-dir', os.real_path('build') + '/pic-' + os.args[2] + attempt + '-' + short]
	if image { args << '--image' }
	mut child := os.new_process(work + '/controller'); child.set_args(args); child.set_redirect_stdio_merged(); child.run()
	output := child.stdout_slurp(); child.wait(); code := child.code; child.close()
	os.write_file(work + '/' + os.args[2] + '-' + arch + '.txt', output)!
	print(output); exit(code)
}
