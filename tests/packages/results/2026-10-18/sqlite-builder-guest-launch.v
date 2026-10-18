module main
import os
fn main() {
	arch := os.args[1]; assert arch in ['aarch64', 'x86_64']
	attempt := if os.args.len > 2 { os.args[2] } else { '1' }
	short := if arch == 'aarch64' { 'arm' } else { 'x86' }; work := os.real_path(os.dir(@FILE))
	os.setenv('V', os.real_path('build/package-release-work/v-toolchain/v'), true)
	os.setenv('VFLAGS', '-nocache', true); os.setenv('VINIX_HWTEST_TCG', '1', true)
	os.setenv('V_MACOS_V3_NO_FALLBACK', '1', true); os.setenv('V_C_ERROR_BUG_REPORT_DISABLED', '1', true)
	os.setenv('VINIX_AMD64_LIMINE_DIR', os.real_path('build/alloc-bench-kernel-before-schema2-1/iso-build/limine'), true)
	if arch == 'aarch64' {
		os.setenv('VINIX_AARCH64_SYSROOT', '/opt/homebrew/opt/musl-cross/libexec/aarch64-linux-musl', true)
		os.setenv('CC_AARCH64', os.real_path('build/package-launch-transport-work/cross-cc'), true)
	}
	if arch == 'x86_64' {
		shadow := work + '/legacy-root'
		os.mkdir_all(shadow + '/build-support')!
		for name in ['tests', 'tools', 'compat', 'desktop', 'build', 'examples']! {
			if os.is_link(shadow + '/' + name) { assert os.real_path(shadow + '/' + name) == os.real_path(name) }
			else { os.symlink(os.real_path(name), shadow + '/' + name)! }
		}
		for name in ['find-v.sh', 'limine.conf']! { os.cp('build-support/' + name, shadow + '/build-support/' + name)! }
		os.cp(work + '/legacy-media', shadow + '/build-support/build-amd64-iso.sh')!; os.chmod(shadow + '/build-support/build-amd64-iso.sh', 0o755)!
		os.setenv('VINIX_ROOT', shadow, true)
		os.setenv('VINIX_WORKSPACE_LEGACY_CONFIG', shadow + '/build-support/limine.conf', true)
		os.setenv('VINIX_WORKSPACE_LEGACY_LIMINE', os.real_path('build/alloc-bench-kernel-before-schema2-1/iso-build/limine'), true)
	}
	mut child := os.new_process(work + '/guest-controller')
	child.set_args(['--arch', arch, '--kernel', os.real_path('build/package-software-persistence-work/kernel-' + short + '/kernel/bin/vinix'),
		'--state-dir', os.real_path('build') + '/sbo-' + short + '-' + attempt])
	child.set_redirect_stdio_merged(); child.run(); output := child.stdout_slurp(); child.wait(); code := child.code; child.close()
	os.write_file(work + '/guest-' + arch + '-' + attempt + '.txt', output)!; print(output); exit(code)
}
