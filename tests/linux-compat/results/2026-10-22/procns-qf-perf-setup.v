import os

#include <CommonCrypto/CommonDigest.h>
@[typedef]
struct C.CC_SHA256_CTX {}
fn C.CC_SHA256_Init(&C.CC_SHA256_CTX) int
fn C.CC_SHA256_Update(&C.CC_SHA256_CTX, voidptr, u32) int
fn C.CC_SHA256_Final(&u8, &C.CC_SHA256_CTX) int

const area = '/Users/alex/.cache/vinix-linux-compat/procns-resume-20261022'
const root = '/Users/alex/code/vinix'
const compiler = '/Users/alex/.cache/vinix-linux-compat/proctask-20261014/compiler/v'

fn digest(path string) !string {
	expected := os.file_size(path)
	mut file := os.open(path)!
	defer { file.close() }
	mut context := C.CC_SHA256_CTX{}
	assert C.CC_SHA256_Init(&context) == 1
	mut buffer := []u8{len: 1024 * 1024}
	mut total := u64(0)
	for {
		n := file.read(mut buffer) or { break }
		if n == 0 { break }
		total += u64(n)
		assert C.CC_SHA256_Update(&context, buffer.data, u32(n)) == 1
	}
	assert total == expected && os.file_size(path) == expected
	mut result := [32]u8{}
	assert C.CC_SHA256_Final(&result[0], &context) == 1
	return result[..].hex()
}

fn command(program string, args []string, log string) ! {
	mut process := os.new_process(program)
	process.set_args(args)
	process.set_redirect_stdio_merged()
	process.run()
	output := process.stdout_slurp()
	process.wait()
	code := process.code
	process.close()
	os.write_file(log, output)!
	os.write_file(log + '.status', '${code}\n')!
	assert code == 0, log
}

fn main() {
	assert os.args.len == 2
	if os.args[1] == 'prepare' {
		for kind in ['compat', 'drag'] {
			original := area + '/frozen-perf-' + kind
			target := area + '/qf-frozen-perf-' + kind
			assert !os.exists(target)
			os.cp_all(original, target, false)!
			filename := 'desktop-retention-' + kind + '.v'
			source := os.read_file(target + '/' + filename)!
			modified := source.replace('/arm-track/kernel', '/queue-fix/arm-track/kernel')
				.replace('/frozen-perf-' + kind, '/qf-frozen-perf-' + kind)
				.replace('/perf-' + kind + '-', '/qf-perf-' + kind + '-')
			assert modified != source
			os.write_file(target + '/' + filename, modified)!
			command(compiler, ['-enable-globals', '-path', target + '|@vlib|@vmodules', '-o', area + '/qf-desktop-retention-' + kind, target + '/' + filename], area + '/qf-perf-compile-' + kind + '.log')!
		}
		println('Prepared separate frozen queue-fix perf harnesses')
		return
	}
	assert os.args[1] in ['pin', 'verify']
	mut paths := []string{}
	for kind in ['compat', 'drag'] {
		folder := area + '/qf-frozen-perf-' + kind
		paths << os.walk_ext(folder, '.v')
		paths << os.walk_ext(folder, '.h')
		paths << [folder + '/measure.c', folder + '/perf-init.sh', area + '/qf-desktop-retention-' + kind]
	}
	paths << [area + '/queue-fix/arm-track/kernel/bin/vinix', root + '/logs/desktop-ram-fix/vinix-desktop-arm64', root + '/logs/m1-gpu-deploy-20261018/build-support/init-aarch64/initramfs-desktop.tar', root + '/boot-image/edk2-aarch64-code-2048x1536.fd', root + '/scripts/run-aarch64.sh', root + '/build-support/qemu-storage.sh', root + '/tools/build-qemu-module-iso', root + '/tools/build-qemu-module-iso.v', compiler, os.executable(), area + '/qf-perf-setup.v']
	paths.sort()
	mut pins := []string{}
	for path in paths { pins << digest(path)! + '  ' + path }
	content := pins.join('\n') + '\n'
	manifest := area + '/qf-perf-inputs.sha256'
	if os.args[1] == 'pin' {
		assert !os.exists(manifest)
		os.write_file(manifest, content)!
	} else {
		assert os.read_file(manifest)! == content, 'queue-fix perf inputs changed'
	}
	println('Queue-fix perf ' + os.args[1] + ': PASS ' + paths.len.str() + ' inputs')
}
