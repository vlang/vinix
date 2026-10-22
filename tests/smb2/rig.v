// SPDX-License-Identifier: GPL-2.0-or-later
// Mission17A qualification only. Samba provisioning belongs to the parent.
module main

import crypto.sha256
import os
import time

const big_bytes = u64(104857600)

fn milestone(text string, start u64) {
	println('M17A-HOST:${text} elapsed_ms=${(time.sys_mono_now() - start) / u64(time.millisecond)}')
}

// Poll and drain both pipes: neither a blocked command nor a full pipe may
// defeat the watchdog. Every process here is our direct, non-daemon child.
fn run(argv []string, log string, seconds int) ! {
	mut p := os.new_process(argv[0])
	p.set_args(argv[1..])
	p.set_redirect_stdio()
	mut f := os.create(log)!
	defer { f.close() }
	p.run()
	defer {
		if p.is_alive() {
			p.signal_kill()
			p.wait()
		}
		p.close()
	}
	deadline := time.sys_mono_now() + u64(seconds) * u64(time.second)
	for p.is_alive() {
		f.write_string(p.stdout_read())!
		f.write_string(p.stderr_read())!
		if time.sys_mono_now() >= deadline {
			p.signal_kill()
			p.wait()
			return error('command timeout; see ${log}')
		}
		time.sleep(20 * time.millisecond)
	}
	p.wait()
	f.write_string(p.stdout_slurp())!
	f.write_string(p.stderr_slurp())!
	if p.code != 0 { return error('command exit=${p.code}; see ${log}') }
}

fn digest(path string) !string {
	mut f := os.open(path)!
	defer { f.close() }
	mut hash := sha256.new()
	mut buf := []u8{len: 65536}
	mut count := u64(0)
	size := os.file_size(path)
	for {
		// V reports EOF as an error. Accept only genuine EOF after all bytes;
		// other read failures, truncation and growth must fail verification.
		n := f.read_bytes_into(count, mut buf) or {
			if err is os.Eof && f.eof() && count == size { break
			 }
			return error('hash read failure at ${count}: ${path}: ${err}')
		}
		if n <= 0 {
			if f.eof() && count == size { break
			 }
			return error('unexpected empty read: ${path}')
		}
		count += u64(n)
		if count > size { return error('file grew during hashing: ${path}') }
		hash.write(buf[..n])!
	}
	if count != size || os.file_size(path) != size {
		return error('file size changed during hashing: ${path}')
	}
	return hash.sum([]).hex()
}

fn fixture(path string, guest bool) !string {
	mut f := os.create(path)!
	defer { f.close() }
	mut block := []u8{len: 65536}
	for i in 0 .. block.len {
		block[i] = u8((i * if guest { 31 } else { 13 } + if guest { 17 } else { 7 }) & 255)
	}
	mut hash := sha256.new()
	for _ in 0 .. 1600 {
		if f.write(block)! != block.len { return error('short fixture write') }
		hash.write(block)!
	}
	return hash.sum([]).hex()
}

fn check(ok bool, message string) ! {
	if !ok { return error(message) }
}

fn verify(out string, share string) ! {
	serial := os.read_file(out + '/m17a-serial.log')!
	for marker in ['OUTCOME PASS status=0', 'mount PASS source=//10.0.2.2/share',
		'network-ready PASS', 'guest-small PASS', 'host-edit PASS', 'host-big PASS',
		'host-roundtrip PASS', 'guest-big PASS', 'directory-list PASS', 'directory-ops PASS',
		'root-list PASS', 'umount PASS', 'remount PASS',
		'negative-mount PASS case=wrong-password rc=-1 errno=13 attempts=1',
		'negative-mount PASS case=missing-share rc=-1 errno=2 attempts=1',
		'guest-readonly PASS flags=0 write_open=-1 errno=30', 'userspace-continues PASS'] {
		check(serial.contains('M17A:' + marker), 'missing serial receipt: ${marker}')!
	}
	check(!serial.contains('M17A:OUTCOME FAIL') && !serial.to_lower().contains('panic'),
		'failure or panic in serial log')!
	expected := os.read_file(out + '/m17a-expected-sha256.txt')!
	host_hash := expected.all_after('HOST_BIG:').all_before('\n')
	guest_hash := expected.all_after('GUEST_BIG:').all_before('\n')
	check(host_hash.len == 64 && guest_hash.len == 64, 'invalid expected digests')!
	check(serial.contains('source_sha256=' + host_hash)
		&& serial.contains('local_sha256=' + host_hash)
		&& serial.contains('generated_sha256=' + guest_hash)
		&& serial.contains('readback_sha256=' + guest_hash), 'guest digest receipts differ')!
	check(os.file_size(share + '/host-big.bin') == big_bytes
		&& os.file_size(share + '/guest-big.bin') == big_bytes, 'host files must each be 100 MiB')!
	check(digest(share + '/host-big.bin')! == host_hash, 'host source hash mismatch')!
	check(os.file_size(share + '/host-roundtrip.bin') == big_bytes
		&& digest(share + '/host-roundtrip.bin')! == host_hash, 'host same-file roundtrip mismatch')!
	actual := digest(share + '/guest-big.bin')!
	check(actual == guest_hash, 'independent host output hash mismatch')!
	check(os.read_file(share + '/guest-small.txt')! == 'mission17a guest-small-v1\n'
		&& os.read_file(share + '/host-small.txt')! == 'host-edit-v2\n'
		&& os.read_file(share + '/guest-ready')! == 'ready\n'
		&& os.read_file(share + '/host-updated.txt')! == 'host update complete\n',
		'host small file/marker mismatch')!
	check(!os.exists(share + '/m17a-directory'), 'directory cleanup failed')!
	os.write_file(out + '/m17a-host-verification.txt', 'M17A-HOST:VERIFY PASS\nHOST_BIG_SHA256:${host_hash}\nGUEST_BIG_SHA256:${actual}\nSMALL_SHA256:${digest(
		share + '/guest-small.txt')!}\n')!
}

fn prepare(share string, out string, start u64) ! {
	check(os.is_dir(share),
		'--share must be an existing dedicated disposable Samba backing directory')!
	check(os.ls(share)!.len == 0, '--share must be empty; refusing to overwrite prior work')!
	os.write_file(share + '/host-small.txt', 'host-edit-v1\n')!
	host_hash := fixture(share + '/host-big.bin', false)!
	guest_hash := fixture(out + '/m17a-guest-expected.bin', true)!
	check(digest(share + '/host-big.bin')! == host_hash
		&& digest(out + '/m17a-guest-expected.bin')! == guest_hash, 'fixture file hash mismatch')!
	os.write_file(out + '/m17a-expected-sha256.txt',
		'HOST_BIG:${host_hash}\nGUEST_BIG:${guest_hash}\n')!
	os.write_file(out + '/m17a-share-path.txt', share + '\n')!
	milestone('fixtures-ready bytes_each=${big_bytes}', start)
}

fn build_iso(repo string, kernel string, init string, template string, out string) ! {
	for path in [kernel, init, template] {
		check(os.is_file(path), 'required input missing: ${path}')!
	}
	for dir in ['sbin', 'dev', 'proc', 'mnt', 'tmp', 'etc'] {
		os.mkdir_all(out + '/m17a-root/' + dir)!
	}
	os.cp(init, out + '/m17a-root/sbin/init')!
	os.chmod(out + '/m17a-root/sbin/init', 0o755)!
	run(['tar', '--format=ustar', '-cf', out + '/m17a-initramfs.tar', '-C', out + '/m17a-root',
		'.'], out + '/m17a-tar.log', 60)!
	// Replay an existing Limine ISO's boot metadata; replace only boot inputs.
	config := os.read_file(repo + '/build-support/limine.conf')!
	check(config.contains('module_path: boot():/boot/initramfs.tar'), 'unexpected Limine template')!
	os.write_file(out + '/m17a-limine.conf', config)!
	run(['xorriso', '-indev', template, '-outdev', out + '/m17a-smb2.iso', '-boot_image', 'any',
		'replay', '-map', kernel, '/boot/vinix', '-map', out + '/m17a-initramfs.tar',
		'/boot/initramfs.tar', '-map', out + '/m17a-limine.conf', '/boot/limine.conf'], out +
		'/m17a-iso-build.log', 120)!
}

fn boot(out string, share string, qemu string, accel string, firmware string, seconds int, start u64) ! {
	mut argv := ['-name', 'm17a-smb2-qualification', '-M', 'q35,smm=off', '-accel', accel, '-cpu',
		if accel == 'kvm' { 'host' } else { 'max' }, '-smp', '4', '-m', '2048', '-vga', 'std',
		'-cdrom', out + '/m17a-smb2.iso', '-boot', 'd', '-display', 'none', '-serial',
		'file:' +
			out + '/m17a-serial.log', '-monitor', 'none', '-netdev',
		'user,id=m17anet,net=10.0.2.0/24,host=10.0.2.2,dhcpstart=10.0.2.15', '-device',
		'virtio-net-pci,netdev=m17anet', '-no-reboot']
	if firmware != '' {
		check(os.is_file(firmware), 'firmware missing')!
		argv << ['-drive', 'if=pflash,format=raw,unit=0,readonly=on,file=' + firmware]
	}
	os.write_file(out + '/m17a-qemu-argv.txt', qemu + '\n' + argv.join('\n') + '\n')!
	mut q := os.new_process(qemu)
	q.set_args(argv)
	q.set_redirect_stdio()
	mut log := os.create(out + '/m17a-qemu.log')!
	q.run()
	defer {
		// Exact child handle, never a process-name or shared PID-file kill.
		if q.is_alive() { q.signal_kill() }
		q.wait()
		log.write_string(q.stdout_slurp() + q.stderr_slurp()) or {}
		log.close()
		q.close()
	}
	check(q.pid > 0, 'QEMU failed to start')!
	os.write_file(out + '/m17a-qemu.pid', '${q.pid}\n')!
	milestone('qemu-started pid=${q.pid} watchdog_seconds=${seconds}', start)
	mut edited := false
	mut reported := 0
	mut next_progress := time.sys_mono_now() + u64(10 * time.second)
	deadline := time.sys_mono_now() + u64(seconds) * u64(time.second)
	for time.sys_mono_now() < deadline {
		log.write_string(q.stdout_read() + q.stderr_read())!
		serial := os.read_file(out + '/m17a-serial.log') or { '' }
		lines := serial.split_into_lines()
		for i in reported .. lines.len {
			if lines[i].starts_with('M17A:') { milestone('guest ${lines[i]}', start) }
		}
		reported = lines.len
		if !edited && os.exists(share + '/guest-ready')
			&& os.read_file(share + '/guest-ready')! == 'ready\n' {
			// Same-length overwrite on the existing inode, never replacement.
			mut f := os.open_file(share + '/host-small.txt', 'r+')!
			if f.write_string('host-edit-v2\n')! != 13 {
				f.close()
				return error('short host edit')
			}
			f.close()
			os.write_file(share + '/host-updated.txt', 'host update complete\n')!
			edited = true
			milestone('host-edit-applied in_place=1', start)
		}
		if serial.contains('M17A:OUTCOME FAIL') || serial.to_lower().contains('panic') {
			return error('guest failed; see ${out}/m17a-serial.log')
		}
		if serial.contains('M17A:OUTCOME PASS status=0') {
			check(edited, 'host edit handshake missing')!
			verify(out, share)!
			milestone('VERIFY PASS independent_host_sha256=1', start)
			return
		}
		if !q.is_alive() { return error('QEMU exited before outcome; see ${out}/m17a-qemu.log') }
		if time.sys_mono_now() >= next_progress {
			milestone('waiting-for-guest', start)
			next_progress += u64(10 * time.second)
		}
		time.sleep(100 * time.millisecond)
	}
	return error('guest deadline exceeded after ${seconds}s')
}

fn main() {
	start := time.sys_mono_now()
	mut opts := map[string]string{}
	mut i := 1
	for i < os.args.len {
		if os.args[i] == '--help' {
			println('rig --repo PATH --kernel ELF --init STATIC_ELF --template ISO --share EMPTY_DIR --out NEW_M17A_DIR [--qemu PATH] [--accel kvm|tcg] [--firmware OVMF] [--timeout 600]')
			println('rig --verify EXISTING_M17A_DIR --share SAME_DIR (host audit only)')
			println('rig --hash FILE (stream SHA256 only, no qualification claim)')
			return
		}
		if i + 1 >= os.args.len
			|| os.args[i] !in ['--repo', '--kernel', '--init', '--template', '--share', '--out', '--qemu', '--accel', '--firmware', '--timeout', '--verify', '--hash'] {
			eprintln('M17A-HOST:FAIL invalid option; use --help')
			exit(2)
		}
		opts[os.args[i]] = os.args[i + 1]
		i += 2
	}
	if '--hash' in opts {
		path := os.abs_path(opts['--hash'])
		hash := digest(path) or {
			eprintln('M17A-HOST:FAIL ${err}')
			exit(1)
		}
		println('${hash}  ${path}')
		return
	}
	if '--verify' in opts {
		if opts['--share'] == '' {
			eprintln('M17A-HOST:FAIL --verify requires --share')
			exit(2)
		}
		verify(os.abs_path(opts['--verify']), os.abs_path(opts['--share'])) or {
			eprintln('M17A-HOST:FAIL ${err}')
			exit(1)
		}
		milestone('VERIFY PASS audit-only no-reboot', start)
		return
	}
	for key in ['--repo', '--kernel', '--init', '--template', '--share', '--out'] {
		if opts[key] == '' {
			eprintln('M17A-HOST:FAIL missing ${key}; use --help')
			exit(2)
		}
	}
	out := os.abs_path(opts['--out'])
	share := os.real_path(opts['--share'])
	accel := if opts['--accel'] == '' { 'kvm' } else { opts['--accel'] }
	seconds := if opts['--timeout'] == '' { 600 } else { opts['--timeout'].int() }
	if accel !in ['kvm', 'tcg'] || seconds < 30 || seconds > 3600 || os.exists(out)
		|| !os.file_name(out).starts_with('m17a-') || share == '' || share == '/' {
		eprintln('M17A-HOST:FAIL require new m17a-* output dir, dedicated share, accel kvm|tcg, timeout 30..3600')
		exit(2)
	}
	os.mkdir_all(out) or {
		eprintln(err)
		exit(1)
	}
	os.chmod(out, 0o700) or {
		eprintln(err)
		exit(1)
	}
	prepare(share, out, start) or {
		eprintln('M17A-HOST:FAIL ${err}')
		exit(1)
	}
	build_iso(os.abs_path(opts['--repo']), os.abs_path(opts['--kernel']),
		os.abs_path(opts['--init']), os.abs_path(opts['--template']), out) or {
		eprintln('M17A-HOST:FAIL ${err}')
		exit(1)
	}
	milestone('iso-ready', start)
	boot(out, share, if opts['--qemu'] == '' { 'qemu-system-x86_64' } else { opts['--qemu'] },
		accel, opts['--firmware'], seconds, start) or {
		eprintln('M17A-HOST:FAIL ${err}')
		exit(1)
	}
	milestone('OUTCOME PASS qemu-stopped=1', start)
}
