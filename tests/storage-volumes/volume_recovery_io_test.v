// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module volumecli

import os

struct VolumeRecoveryIO {
mut:
	derives int
	password &u8 = unsafe { nil }
	wrapping &u8 = unsafe { nil }
}
__global volume_recovery_io VolumeRecoveryIO
__global volume_recovery_model bool

fn volume_recovery_assert_erased() {
	assert volume_recovery_io.derives == 1
	unsafe {
		for i in 0 .. 1024 { assert volume_recovery_io.password[i] == 0 }
		for i in 0 .. 64 { assert volume_recovery_io.wrapping[i] == 0 }
	}
}

// Exercise the real readers, codec and publisher with a bounded deterministic
// KDF substitute. Full-cost production KDFs are measured in both guests.
fn volume_recovery_mock_derive(password &u8, size int, salt &u8, output &u8) bool {
	assert size == 6
	volume_recovery_io.derives++
	volume_recovery_io.password = password; volume_recovery_io.wrapping = output
	unsafe {
		for i in 0 .. 64 { assert output[i] == 0 }
		assert password[0] == 0 && password[1] == 10 && password[2] == 0xe2
		for i in 6 .. 1024 { assert password[i] == 0 }
		if recovery_io.mode == 23 { return false }
		for i in 0 .. 64 { output[i] = if password[5] == 0xff { u8(i * 29 + 41) } else { u8(i * 37 + 23) } }
		if recovery_io.mode == 24 { output[0] ^= 1 }
		if recovery_io.mode == 25 { for i in 0 .. 64 { output[i] = 7 } }
	}
	return true
}

fn volume_recovery_check_output(path string, disk &DiskKey, request &EncryptedRequest, backup bool, recovery &u8) ! {
	bytes := os.read_bytes(path)!
	assert bytes.len == 320 && os.stat(path)!.mode & 0o777 == 0o600
	mut observed := DiskKey{}; mut opened := EncryptedRequest{}
	if backup { assert decode_volume_recovery(bytes.data, 320, recovery, mut observed, mut opened) }
	else {
		wrapping := [64]u8{init: u8(index * 37 + 23)}
		assert decode_volume_seal(bytes.data, 320, &wrapping[0], mut observed, mut opened)
	}
	assert observed == *disk && opened == *request
}

fn test_volume_recovery_io_faults_erasure_no_replacement_and_exact_authenticated_metadata() {
	volume_recovery_model = true; defer { volume_recovery_model = false }
	work := os.join_path(os.temp_dir(), 'vinix-volume-recovery-io-${os.getpid()}')
	os.mkdir(work)!; os.chmod(work, 0o700)!; defer { os.rmdir_all(work) or {} }
	mut disk := DiskKey{bytes: 16777216, sector: 512, kind: 1}; disk.id[0] = 1
	request := EncryptedRequest{data: Request{slot: 63, offset: 8192, length: 4096, flags: 1}, key: [64]u8{init: u8(index * 13 + 7)}}
	recovery := [64]u8{init: u8(index * 17 + 19)}; wrapping := [64]u8{init: u8(index * 29 + 41)}
	random := [28]u8{init: u8(index * 11 + 3)}; mut sealed := [320]u8{}; mut envelope := [320]u8{}
	assert encode_volume_seal(&disk, &request, &wrapping[0], &random[0], &sealed[0])
	assert encode_volume_recovery(&disk, &request, &recovery[0], &random[0], &envelope[0])
	os.write_file_array(work + '/config', sealed[..])!; os.write_file_array(work + '/backup', envelope[..])!
	os.write_file_array(work + '/recovery', recovery[..])!
	os.write_file_array(work + '/old', [u8(0), 10, 0xe2, 0x82, 0xac, 0xff])!
	os.write_file_array(work + '/new', [u8(0), 10, 0xe2, 0x82, 0xac, 0x17])!
	for name in ['config', 'backup', 'recovery', 'old', 'new'] { os.chmod(work + '/' + name, 0o600)! }
	for backup in [true, false] {
		for mode in 0 .. 26 {
			// A wrong derived key rejects source authentication, whereas fresh
			// valid recovery credentials can intentionally produce a new key.
			if !backup && mode == 24 { continue }
			recovery_io = RecoveryIO{mode: mode}; volume_recovery_io = VolumeRecoveryIO{}
			destination := work + '/output'
			result := if backup { backup_volume_seal((work + '/config').str, (work + '/old').str, (work + '/recovery').str, destination.str) }
				else { recover_volume_seal((work + '/backup').str, (work + '/recovery').str, (work + '/new').str, destination.str) }
			assert result == if mode <= 1 { 0 } else { 1 }, mode.str()
			assert recovery_io.opened == recovery_io.closed && recovery_io.volume_wipes == 1 && !recovery_io.locked
			assert os.exists(destination) == (mode <= 1 || mode in [19, 20, 21])
			if os.exists(destination) { volume_recovery_check_output(destination, &disk, &request, backup, &recovery[0])!; os.rm(destination)! }
			assert os.ls(work)!.all(!it.starts_with('.vinix-key-'))
		}
		// Existing output, input alias and dangling output symlink all survive.
		for destination in [work + '/config', work + '/backup', work + '/recovery', work + '/link'] {
			if destination.ends_with('/link') { os.symlink(work + '/absent', destination)! }
			recovery_io = RecoveryIO{}; volume_recovery_io = VolumeRecoveryIO{}
			assert (if backup { backup_volume_seal((work + '/config').str, (work + '/old').str, (work + '/recovery').str, destination.str) }
				else { recover_volume_seal((work + '/backup').str, (work + '/recovery').str, (work + '/new').str, destination.str) }) == 1
			assert recovery_io.opened == recovery_io.closed && recovery_io.volume_wipes == 1
		}
		if os.is_link(work + '/link') { os.rm(work + '/link')! }
	}
	assert os.read_bytes(work + '/config')! == sealed[..] && os.read_bytes(work + '/backup')! == envelope[..]
	assert os.read_bytes(work + '/recovery')! == recovery[..]
	// Canonical format rejection precedes recovery/credential access; tag
	// rejection precedes the new credential/KDF and destination acquisition.
	for at in [0, 24, 124, 144, 192, 288] {
		mut damaged := envelope; damaged[at] ^= 1; os.write_file_array(work + '/bad', damaged[..])!; os.chmod(work + '/bad', 0o600)!
		recovery_io = RecoveryIO{}; volume_recovery_io = VolumeRecoveryIO{}
		assert recover_volume_seal((work + '/bad').str, (work + '/recovery').str, (work + '/missing-password').str, (work + '/output').str) == 1
		assert volume_recovery_io.derives == 0 && recovery_io.directory == -1 && recovery_io.volume_wipes == 1 && recovery_io.opened == recovery_io.closed
		assert !os.exists(work + '/output')
	}
	for path in [work + '/backup', work + '/recovery', work + '/new'] {
		os.chmod(path, 0o644)!
		recovery_io = RecoveryIO{}; volume_recovery_io = VolumeRecoveryIO{}
		assert recover_volume_seal((work + '/backup').str, (work + '/recovery').str, (work + '/new').str, (work + '/output').str) == 1
		assert recovery_io.opened == recovery_io.closed && recovery_io.volume_wipes == 1 && !os.exists(work + '/output')
		os.chmod(path, 0o600)!
	}
}
