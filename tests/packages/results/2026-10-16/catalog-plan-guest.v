module main
import os
fn main() {
	work := os.real_path(os.dir(@FILE)); arch := os.args[1]; attempt := os.args[2]
	assert arch in ['aarch64', 'x86_64']
	short := if arch == 'aarch64' { 'arm' } else { 'x86' }
	os.setenv('V', os.real_path('build/package-release-work/v-toolchain/v'), true)
	os.setenv('VFLAGS', '-nocache', true); os.setenv('VINIX_HWTEST_TCG', '1', true)
	os.setenv('V_MACOS_V3_NO_FALLBACK', '1', true); os.setenv('V_C_ERROR_BUG_REPORT_DISABLED', '1', true)
	os.setenv('VINIX_AMD64_LIMINE_DIR', os.real_path('build/alloc-bench-kernel-before-schema2-1/iso-build/limine'), true)
	if arch == 'aarch64' {
		os.setenv('VINIX_AARCH64_SYSROOT', '/opt/homebrew/opt/musl-cross/libexec/aarch64-linux-musl', true)
		os.setenv('CC_AARCH64', os.real_path('build/package-launch-transport-work/cross-cc'), true)
	}
	mut child := os.new_process(work + '/controller')
	child.set_args(['--arch', arch, '--kernel', os.real_path('build/package-software-persistence-work/kernel-' + short + '/kernel/bin/vinix'),
		'--state-dir', os.real_path('build') + '/pcp-' + short + '-' + attempt])
	child.set_redirect_stdio_merged(); child.run(); output := child.stdout_slurp(); child.wait(); code := child.code; child.close()
	os.write_file(work + '/guest-' + arch + '-' + attempt + '.txt', output)!; print(output); exit(code)
}
