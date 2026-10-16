module main
import os
fn main() {
	work := os.real_path(os.dir(@FILE)); attempt := os.args[1]
	os.setenv('V', os.real_path('build/package-release-work/v-toolchain/v'), true)
	os.setenv('VFLAGS', '-nocache', true); os.setenv('VINIX_HWTEST_TCG', '1', true)
	os.setenv('V_MACOS_V3_NO_FALLBACK', '1', true); os.setenv('V_C_ERROR_BUG_REPORT_DISABLED', '1', true)
	os.setenv('VINIX_AARCH64_SYSROOT', '/opt/homebrew/opt/musl-cross/libexec/aarch64-linux-musl', true)
	os.setenv('CC_AARCH64', os.real_path('build/package-launch-transport-work/cross-cc'), true)
	os.setenv('VINIX_APPLE_RUNTIME', os.real_path('build/paf-3/run-ios'), true)
	os.setenv('VINIX_APPLE_SANDBOX', os.real_path('build/package-native-catalog-work/a3/guest/root/usr/bin/vinix-sandbox'), true)
	mut child := os.new_process(work + '/controller')
	child.set_args(['--arch', 'aarch64', '--kernel', os.real_path('build/package-software-persistence-work/kernel-arm/kernel/bin/vinix'),
		'--state-dir', os.real_path('build') + '/pct-' + attempt])
	child.set_redirect_stdio_merged(); child.run(); output := child.stdout_slurp(); child.wait(); code := child.code; child.close()
	os.write_file(work + '/guest-' + attempt + '.txt', output)!; print(output); exit(code)
}
