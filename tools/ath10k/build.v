// SPDX-License-Identifier: ISC
// Build the native V control utility and a pinned, licensed firmware bundle.
module main

import os
import crypto.sha256
import encoding.hex

fn run(program string, args []string) {
	mut p := os.new_process(program)
	p.set_args(args)
	p.run()
	p.wait()
	code := p.code
	p.close()
	if code != 0 { panic('${program} failed with ${code}') }
}

fn digest(path string) string {
	bytes := os.read_bytes(path) or { panic(err) }
	return hex.encode(sha256.sum(bytes))
}

fn main() {
	if os.args.len != 3 {
		println('Usage: v run tools/ath10k/build.v MUSL_SYSROOT OUTPUT_DIRECTORY')
		exit(1)
	}
	root := os.real_path(os.join_path(os.dir(@FILE), '..', '..'))
	sysroot := os.real_path(os.args[1])
	out := os.abs_path(os.args[2])
	os.mkdir_all(out + '/rootfs/usr/bin') or { panic(err) }
	firmware := out + '/rootfs/lib/firmware/ath10k/QCA9377/hw1.0'
	os.mkdir_all(firmware) or { panic(err) }
	license := out + '/rootfs/usr/share/licenses/ath10k'
	os.mkdir_all(license) or { panic(err) }
	ref := '711d3297bac870af42088a467459a0634c1970ca'
	base := 'https://raw.githubusercontent.com/wkennington/linux-firmware/' + ref + '/'
	names := ['ath10k/QCA9377/hw1.0/firmware-6.bin', 'ath10k/QCA9377/hw1.0/board-2.bin',
		'LICENSE.QualcommAtheros_ath10k', 'ath10k/QCA9377/hw1.0/notice_ath10k_firmware-6.txt']
	hashes := ['8f8b002fccfe81d42238f27dd1f56d189604f180bd4772c7c8e75ae1fef16f01',
		'0fdcc7838f478da81704de88f7b33e28862110c6d5decf7818543f8e37e6cd98',
		'337a55102138d7baa143ee4a4c6c91693e0113fece35d380b2a12109e8c23b3f',
		'8ce5c6ea0542bf4aac31fc3ae16a39792ad22d0eae4543063fac56fb3380f021']
	for i, name in names {
		path := if i < 2 {
			firmware + '/' + os.file_name(name)
		} else {
			license + '/' + os.file_name(name)
		}
		if !os.exists(path) || digest(path) != hashes[i] {
			run('curl', ['--fail', '--location', '--retry', '2', '--silent', '--show-error', '--output',
				path, base + name])
		}
		if digest(path) != hashes[i] { panic('Checksum mismatch: ' + name) }
	}
	compiler := os.getenv_opt('V') or { @VEXE }
	generated := out + '/wifi-ctl.c'
	run(compiler, ['-nocache', '-os', 'linux', '-gc', 'none', '-autofree', '-d', 'no_backtrace',
		'-d', 'no_segfault_handler', '-o', generated, root + '/tools/ath10k/wifi-ctl.v'])
	mut gcc := ''
	for name in os.ls(sysroot + '/usr/lib/gcc/x86_64-alpine-linux-musl') or { panic(err) } {
		path := sysroot + '/usr/lib/gcc/x86_64-alpine-linux-musl/' + name
		if os.exists(path + '/libgcc.a') {
			gcc = path
			break
		}
	}
	if gcc == '' { panic('No x86_64 musl libgcc in sysroot') }
	linker := os.getenv_opt('LD_LLD') or { '/opt/homebrew/bin/ld.lld' }
	run('clang', ['--target=x86_64-linux-musl', '--sysroot=' + sysroot, '-fuse-ld=' + linker, '-static',
		'-Os', '-pthread', '-Wno-pointer-sign', '-Wno-incompatible-pointer-types', '-L' + gcc,
		'-B' + gcc + '/', generated, '-o', out + '/rootfs/usr/bin/wifi-ctl'])
	os.cp(root + '/tools/ath10k/README.md', out + '/README.md') or { panic(err) }
	mut sums := ''
	for path in os.walk_ext(out + '/rootfs', '') {
		if os.is_file(path) { sums += digest(path) + '  ' + path.all_after(out + '/') + '\n' }
	}
	os.write_file(out + '/SHA256SUMS', sums) or { panic(err) }
	run('tar', ['-czf', out + '/qca9377-firmware-and-tools.tar.gz', '-C', out + '/rootfs', '.'])
	println('Built ' + out + '/qca9377-firmware-and-tools.tar.gz')
}
