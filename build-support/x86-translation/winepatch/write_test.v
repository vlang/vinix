// SPDX-License-Identifier: GPL-2.0-or-later
module winepatch

import encoding.hex
import os

fn test_explicit_write_abi_and_atomic_replacement() {
	work := os.temp_dir() + '/wine-write-abi-' + os.getpid().str()
	os.mkdir(work)!
	defer { os.rmdir_all(work) or {} }
	path := work + '/services.exe'
	old := hex.decode('01c0d4010060ea00001027000002')!
	new := hex.decode('01c0d4010060ea000060ea000002')!
	for mode in [0o644, 0o751] {
		os.write_file_array(path, old)!; os.chmod(path, mode)!
		inode := os.stat(path)!.inode
		message := patch_file('wine-service-timeout', path)!
		if !message.starts_with('extended translated-service') || os.read_bytes(path)! != new
			|| int(os.stat(path)!.mode) & 0o7777 != mode || os.stat(path)!.inode == inode { panic('atomic patch write differs') }
		patched := os.stat(path)!.inode
		patch_file('wine-service-timeout', path)!
		if os.stat(path)!.inode != patched { panic('idempotent patch rewrote file') }
	}
	for _ in 0 .. 50 {
		os.write_file_array(path, old)!
		patch_file('wine-service-timeout', path)!
		if os.read_bytes(path)! != new || os.ls(work)!.len != 1 { panic('repeated atomic patch write differs') }
	}
	println('WINE PATCH WRITE PASS explicit ABI; atomic modes; idempotence; repeated replacement')
}
