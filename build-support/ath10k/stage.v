// SPDX-License-Identifier: ISC
// Stage the pinned, licensed QCA9377 firmware and native control utility.
module main

import os

fn main() {
	if os.args.len != 3 {
		eprintln('Usage: stage.v MUSL_SYSROOT STAGING_DIRECTORY')
		exit(2)
	}
	root := os.real_path(os.join_path(os.dir(@FILE), '..', '..'))
	sysroot := os.real_path(os.args[1])
	staging := os.real_path(os.args[2])
	if staging == '/' || !os.is_dir(staging) {
		eprintln('staging must be an existing image root')
		exit(2)
	}
	cache := os.abs_path(os.getenv_opt('VINIX_ATH10K_BUILD_DIR') or { root + '/build/ath10k' })
	mut builder := os.new_process(os.getenv_opt('V') or { @VEXE })
	builder.set_args(['-cc', 'cc', 'run', root + '/tools/ath10k/build.v', sysroot, cache])
	builder.run()
	builder.wait()
	code := builder.code
	builder.close()
	if code != 0 { exit(code) }
	// Refuse to put a host or wrong-architecture executable onto the image.
	binary := os.read_bytes(cache + '/rootfs/usr/bin/wifi-ctl') or { panic(err) }
	if binary.len < 20 || binary[..6] != [u8(0x7f), `E`, `L`, `F`, 2, 1] ||
		binary[18] != 62 || binary[19] != 0 {
		panic('wifi-ctl must be a little-endian x86-64 ELF executable')
	}
	for path in ['lib/firmware/ath10k/QCA9377/hw1.0/firmware-6.bin',
		'lib/firmware/ath10k/QCA9377/hw1.0/board-2.bin',
		'usr/share/licenses/ath10k/LICENSE.QualcommAtheros_ath10k',
		'usr/share/licenses/ath10k/notice_ath10k_firmware-6.txt', 'usr/bin/wifi-ctl'] {
		target := staging + '/' + path
		os.mkdir_all(os.dir(target)) or { panic(err) }
		os.cp(cache + '/rootfs/' + path, target) or { panic(err) }
		os.chmod(target, if path == 'usr/bin/wifi-ctl' { 0o755 } else { 0o644 }) or { panic(err) }
	}
	println('Staged QCA9377 firmware, licences and wifi-ctl (x86_64).')
}
