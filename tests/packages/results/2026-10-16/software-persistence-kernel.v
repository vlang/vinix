module main
import os
fn main() {
	root := os.real_path('.'); work := os.real_path(os.dir(@FILE)); arch := os.args[1]
	short := if arch == 'aarch64' { 'arm' } else { 'x86' }
	base := work + '/kernel-' + short + '/kernel'
	for name in ['freestnd-c-hdrs', 'cc-runtime', 'c/flanterm', 'c/nanoprintf.h', 'c/uacpi', 'uacpi-repository', 'c/lwip', 'lwip-repository']! {
		if !os.exists(base + '/' + name) && os.exists(root + '/kernel/' + name) { os.symlink(root + '/kernel/' + name, base + '/' + name)! }
	}
	os.cp(root + '/kernel/fs/ext2/ext2.v', base + '/fs/ext2/ext2.v')!
	os.setenv('V_MACOS_V3_NO_FALLBACK', '1', true); os.setenv('V_C_ERROR_BUG_REPORT_DISABLED', '1', true)
	mut child := os.new_process('/usr/bin/make'); child.set_work_folder(base)
	child.set_args(['-j4', 'ARCH=' + arch, 'CC=/usr/bin/clang', 'AR=/opt/homebrew/opt/llvm/bin/llvm-ar',
		'V=' + root + '/build/package-release-work/v-toolchain/v', 'VFLAGS=-nocache', 'ALLOC_TRACK=1',
		...if arch == 'aarch64' { ['LIMINE_MP=1', 'LD_AARCH64=/opt/homebrew/bin/ld.lld'] } else { ['LD_X86_64=/opt/homebrew/bin/ld.lld'] }])
	child.set_redirect_stdio_merged(); child.run(); output := child.stdout_slurp(); child.wait(); code := child.code; child.close()
	os.write_file(work + '/kernel-' + arch + '.txt', output)!
	if code == 0 { println('Kernel ' + arch + ' PASS') } else { print(output) }
	exit(code)
}
