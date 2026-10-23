// SPDX-License-Identifier: GPL-2.0-or-later
// Mission17B qualification only. NFS server provisioning belongs to the parent.
module main

import crypto.sha256
import os
import time

#include <errno.h>
#include <signal.h>
#include <sys/wait.h>

fn C.kill(int, int) int
fn C.waitpid(int, &int, int) int

const big_bytes = u64(104857600)

fn milestone(text string, start u64) {
	println('M17B-HOST:${text} elapsed_ms=${(time.sys_mono_now() - start) / u64(time.millisecond)}')
}

// Some V 0.5.2 libraries mark signal_kill() aborted before wait(), causing
// wait() to skip waitpid and leave a zombie. Own the exact POSIX child lifetime.
fn stop_child(mut p os.Process) ! {
	if p.pid <= 0 || p.status !in [.running, .stopped] || !p.is_alive() { return }
	if C.kill(p.pid, C.SIGKILL) != 0 && C.errno != C.ESRCH {
		return error('kill direct child pid=${p.pid} errno=${C.errno}')
	}
	mut status := 0
	for {
		rc := C.waitpid(p.pid, &status, 0)
		if rc == p.pid || (rc < 0 && C.errno == C.ECHILD) {
			p.status = .aborted
			p.code = 128 + C.SIGKILL
			return
		}
		if rc < 0 && C.errno == C.EINTR { continue
		 }
		return error('waitpid direct child pid=${p.pid} rc=${rc} errno=${C.errno}')
	}
}

fn cleanup_child(mut p os.Process) {
	stop_child(mut p) or {
		eprintln('M17B-HOST:FAIL child-cleanup ${err}')
		exit(1)
	}
}

fn drain_pipes(mut p os.Process, mut log os.File) ! {
	// Bound work per poll while draining bursts from both streams fairly.
	// One block per 20ms throttles verbose children enough to cause false timeouts.
	for _ in 0 .. 64 {
		stdout := p.stdout_read()
		stderr := p.stderr_read()
		if stdout == '' && stderr == '' { break
		 }
		log.write_string(stdout)!
		log.write_string(stderr)!
	}
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
		cleanup_child(mut p)
		p.close()
	}
	deadline := time.sys_mono_now() + u64(seconds) * u64(time.second)
	for p.is_alive() {
		drain_pipes(mut p, mut f)!
		if time.sys_mono_now() >= deadline {
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

fn receipt(serial string, marker string) !string {
	lines := serial.split_into_lines().filter(it.starts_with('M17B:' + marker + ' '))
	check(lines.len == 1, 'expected one serial receipt ${marker}; got ${lines.len}')!
	return lines[0]
}

fn field(line string, key string) !string {
	values := line.split(' ').filter(it.starts_with(key + '='))
	check(values.len == 1, 'missing/duplicate field ${key} in ${line}')!
	return values[0].all_after('=')
}

fn number(line string, key string) !u64 {
	s := field(line, key)!
	check(s.len > 0 && s.len <= 15 && s.bytes().all(it >= `0` && it <= `9`), 'invalid ${key}: ${s}')!
	return s.u64()
}

fn verify(out string, share string, readonly string) ! {
	serial := os.read_file(out + '/m17b-serial.log')!
	check(!serial.contains('M17B:FAIL ') && !serial.contains('M17B:OUTCOME FAIL')
		&& !serial.to_lower().contains('panic'), 'failure or panic in serial log')!
	for marker in ['OUTCOME PASS', 'network-ready PASS', 'mount PASS', 'guest-small PASS',
		'host-small initial', 'guest-ready PASS', 'host-edit PASS', 'host-big PASS',
		'host-roundtrip PASS', 'guest-big PASS', 'directory-list PASS', 'directory-ops PASS',
		'root-list PASS', 'umount PASS', 'remount PASS', 'missing-export PASS', 'readonly-mount-call',
		'server-readonly PASS', 'readonly-umount PASS', 'stop-server-ready', 'stopped-server-call',
		'stopped-server PASS', 'userspace-continues PASS'] {
		receipt(serial, marker)!
	}
	outcome := receipt(serial, 'OUTCOME PASS')!
	check(field(outcome, 'status')! == '0' && field(outcome, 'parked')! == '1', 'bad outcome')!
	sources := os.read_file(out + '/m17b-sources.txt')!.split_into_lines()
	check(sources.len == 3, 'source manifest malformed')!
	mount := receipt(serial, 'mount PASS')!
	check(field(mount, 'source')! == sources[0] && field(mount, 'target')! == '/mnt/nfs' && field(mount, 'fs')! == 'nfs'
		&& field(mount, 'flags')! == '0' && field(mount, 'auth')! == 'AUTH_SYS'
		&& field(mount, 'uid')! == '0' && field(mount, 'euid')! == '0'
		&& field(mount, 'options')! == 'soft,rsize=65536,wsize=65536', 'mount receipt differs')!
	missing := receipt(serial, 'missing-export PASS')!
	check(field(missing, 'source')! == sources[2] && field(missing, 'rc')! == '-1'
		&& field(missing, 'errno')! in ['1', '2', '13'] && field(missing, 'attempts')! == '1',
		'missing export denial differs')!
	ro := receipt(serial, 'server-readonly PASS')!
	ro_mount := receipt(serial, 'readonly-mount-call')!
	check(field(ro_mount, 'source')! == sources[1] && field(ro_mount, 'rc')! == '0'
		&& field(ro_mount, 'errno')! == '0' && field(ro_mount, 'flags')! == '0',
		'RO mount source/flags differ')!
	check(field(ro, 'flags')! == '0' && field(ro, 'write_rc')! == '-1'
		&& field(ro, 'errno')! == '30', 'server RO must deny actual write with EROFS')!
	for marker in ['stopped-server-call', 'stopped-server PASS'] {
		line := receipt(serial, marker)!
		check(field(line, 'operation')! == 'read' && field(line, 'rc')! == '-1'
			&& field(line, 'errno')! in ['5', '32', '100', '101', '103', '104', '107', '110', '111', '112', '113']
			&& number(line, 'elapsed_ms')! <= 20000,
			'stopped server transport failure/latency differs')!
	}
	for key in ['operation', 'rc', 'errno', 'elapsed_ms'] {
		check(field(receipt(serial, 'stopped-server-call')!, key)! == field(receipt(serial,
			'stopped-server PASS')!, key)!, 'stop syscall and PASS differ: ${key}')!
	}
	barrier := receipt(serial, 'stop-server-ready')!
	check(number(barrier, 'quiet_seconds')! >= 2 && number(barrier, 'wait_seconds')! >= 8
		&& field(barrier, 'retained_rw_mount')! == '1', 'stop barrier differs')!
	// Verify stage order; a success-looking line from an earlier stage cannot
	// satisfy a later gate. Every completion follows its actual syscall receipt.
	mut position := -1
	for marker in ['mount PASS', 'guest-small PASS', 'host-small initial', 'guest-ready PASS',
		'host-edit PASS', 'directory-list PASS', 'directory-ops PASS', 'host-big PASS',
		'host-roundtrip PASS', 'guest-big PASS', 'root-list PASS', 'umount PASS', 'remount PASS',
		'missing-export PASS', 'readonly-mount-call', 'server-readonly PASS', 'readonly-umount PASS',
		'stop-server-ready', 'stopped-server-call', 'stopped-server PASS', 'userspace-continues PASS',
		'OUTCOME PASS'] {
		line := receipt(serial, marker)!
		at := serial.index(line) or { return error('receipt disappeared') }
		check(at > position, 'serial gate order differs at ${marker}')!
		position = at
	}
	expected := os.read_file(out + '/m17b-expected-sha256.txt')!
	host_hash := expected.all_after('HOST_BIG:').all_before('\n')
	guest_hash := expected.all_after('GUEST_BIG:').all_before('\n')
	probe_hash := expected.all_after('STOP_PROBE:').all_before('\n')
	check(host_hash.len == 64 && guest_hash.len == 64 && probe_hash.len == 64,
		'invalid expected digests')!
	host := receipt(serial, 'host-big PASS')!
	check(number(host, 'bytes')! == big_bytes && field(host, 'source_sha256')! == host_hash
		&& field(host, 'local_sha256')! == host_hash, 'host-to-local receipt differs')!
	number(host, 'copy_ms')!
	for marker in ['host-roundtrip PASS', 'guest-big PASS'] {
		line := receipt(serial, marker)!
		check(number(line, 'bytes')! == big_bytes, 'transfer length differs')!
		number(line, 'elapsed_ms')!
	}
	check(field(receipt(serial, 'host-roundtrip PASS')!, 'sha256')! == host_hash
		&& field(receipt(serial, 'remount PASS')!, 'roundtrip_sha256')! == host_hash,
		'roundtrip/remount digest differs')!
	guest := receipt(serial, 'guest-big PASS')!
	check(field(guest, 'generated_sha256')! == guest_hash
		&& field(guest, 'readback_sha256')! == guest_hash, 'guest transfer digest differs')!
	number(guest, 'write_ms')!
	for name in ['host-big.bin', 'host-roundtrip.bin', 'guest-big.bin'] {
		check(os.file_size(share + '/' + name) == big_bytes, '${name} must be 104857600 bytes')!
		hash := digest(share + '/' + name)!
		check(hash == if name == 'guest-big.bin' { guest_hash } else { host_hash },
			'host hash differs: ${name}')!
	}
	check(os.read_file(share + '/guest-small.txt')! == 'mission17b guest-small-v1\n'
		&& os.read_file(share + '/host-small.txt')! == 'host-edit-v2\n'
		&& os.read_file(share + '/guest-ready')! == 'ready\n'
		&& os.read_file(share + '/host-updated.txt')! == 'host update complete\n',
		'small files/handshake differ')!
	small_hash := digest(share + '/guest-small.txt')!
	edit_hash := digest(share + '/host-small.txt')!
	initial := receipt(serial, 'host-small initial')!
	check(field(initial, 'sha256')! == sha256.hexhash('host-edit-v1\n')
		&& number(initial, 'bytes')! == 13
		&& field(initial, 'text_hex')! == 'host-edit-v1\n'.bytes().hex(),
		'initial known host fixture differs')!
	check(field(receipt(serial, 'guest-small PASS')!, 'sha256')! == small_hash
		&& field(receipt(serial, 'remount PASS')!, 'marker_sha256')! == small_hash
		&& field(receipt(serial, 'host-edit PASS')!, 'sha256')! == edit_hash,
		'small serial hashes differ')!
	check(os.read_file(readonly + '/m17b-ro.txt')! == 'm17b server readonly fixture\n',
		'RO fixture modified')!
	check(!os.exists(share + '/m17b-directory'), 'directory cleanup failed')!
	check(os.file_size(share + '/m17b-stop-probe.bin') == 8192
		&& digest(share + '/m17b-stop-probe.bin')! == probe_hash, 'fresh read probe differs')!
	stop := os.read_file(out + '/m17b-server-stop.txt')!
	check(stop.starts_with('M17B-HOST:server-stop '), 'missing host stop receipt')!
	mode := field(stop.trim_space(), 'mode')!
	check(mode in ['docker', 'external-controller'], 'unknown host stop mode')!
	if mode == 'docker' {
		check(field(stop.trim_space(), 'name')!.starts_with('m17b-')
			&& field(stop.trim_space(), 'attempts')! == '1'
			&& field(stop.trim_space(), 'rc')! == '0'
			&& number(stop.trim_space(), 'elapsed_ms')! < 7000,
			'host Docker stop did not complete once during quiet window')!
		id := field(stop.trim_space(), 'id')!
		check(id.len == 64 && os.read_file(out + '/m17b-docker-stop.log')!.trim_space() == id,
			'Docker stop output differs from inspected container ID')!
	}
	verification := 'M17B-HOST:VERIFY PASS\nM17B-HOST:HOST_BIG_SHA256=${host_hash}\nM17B-HOST:HOST_ROUNDTRIP_SHA256=${digest(
		share + '/host-roundtrip.bin')!}\nM17B-HOST:GUEST_BIG_SHA256=${digest(share +
		'/guest-big.bin')!}\nM17B-HOST:SMALL_SHA256=${small_hash}\nM17B-HOST:HOST_EDIT_SHA256=${edit_hash}\nM17B-HOST:READONLY_SHA256=${digest(
		readonly + '/m17b-ro.txt')!}\nM17B-HOST:STOP_PROBE_SHA256=${probe_hash}\n'
	os.write_file(out + '/m17b-host-verification.txt', verification)!
	print(verification)
}

fn prepare(share string, readonly string, out string, start u64) ! {
	for path in [share, readonly] {
		check(os.is_dir(path) && os.ls(path)!.len == 0,
			'fixture directories must exist and be empty; refusing overwrite: ${path}')!
	}
	os.write_file(share + '/host-small.txt', 'host-edit-v1\n')!
	os.write_file(readonly + '/m17b-ro.txt', 'm17b server readonly fixture\n')!
	host_hash := fixture(share + '/host-big.bin', false)!
	guest_hash := fixture(out + '/m17b-guest-expected.bin', true)!
	// Unique real bytes, never read by the guest before shutdown. The parent
	// can independently hash this fixture after nfsd stops.
	mut probe := []u8{cap: 8192}
	mut counter := 0
	for probe.len < 8192 {
		probe << sha256.sum('${start}:${counter}:m17b-stop-probe'.bytes())
		counter++
	}
	os.write_file_array(share + '/m17b-stop-probe.bin', probe)!
	check(digest(share + '/host-big.bin')! == host_hash
		&& digest(out + '/m17b-guest-expected.bin')! == guest_hash,
		'independent fixture hash mismatch')!
	os.write_file(out + '/m17b-expected-sha256.txt', 'HOST_BIG:${host_hash}\nGUEST_BIG:${guest_hash}\nSTOP_PROBE:${digest(
		share + '/m17b-stop-probe.bin')!}\n')!
	os.write_file(out + '/m17b-fixture-paths.txt',
		'M17B-HOST:share=${share}\nM17B-HOST:readonly=${readonly}\n')!
	milestone('fixtures-ready bytes_each=${big_bytes} host_sha256=${host_hash} guest_sha256=${guest_hash}',
		start)
}

// Assemble a private minimal CD using only template bootloader files. No shell
// generator, source ISO mutation, persistent disk or hybrid metadata replay.
fn build_iso(kernel string, init string, template string, out string, sources []string) ! {
	for path in [kernel, init, template] {
		check(os.is_file(path), 'missing input: ${path}')!
	}
	root := out + '/m17b-root'
	stage := out + '/m17b-iso-root'
	for dir in ['sbin', 'dev', 'proc', 'mnt/nfs', 'mnt-ro', 'mnt-negative', 'tmp', 'etc'] {
		os.mkdir_all(root + '/' + dir)!
	}
	for dir in ['boot', 'EFI/BOOT'] {
		os.mkdir_all(stage + '/' + dir)!
	}
	os.cp(init, root + '/sbin/init')!
	os.chmod(root + '/sbin/init', 0o755)!
	os.write_file(root + '/etc/hosts', '127.0.0.1 localhost\n10.0.2.2 fecv3\n')!
	os.write_file(root + '/etc/m17b-sources', sources.join('\n') + '\n')!
	os.write_file(out + '/m17b-sources.txt', sources.join('\n') + '\n')!
	os.setenv('COPYFILE_DISABLE', '1', true)
	run(['tar', '--format=ustar', '-cf', stage + '/boot/initramfs.tar', '-C', root, '.'], out +
		'/m17b-tar.log', 60)!
	os.cp(kernel, stage + '/boot/vinix')!
	for name in ['boot/limine-bios-cd.bin', 'boot/limine-bios.sys', 'boot/limine-uefi-cd.bin',
		'EFI/BOOT/BOOTX64.EFI'] {
		run(['xorriso', '-osirrox', 'on', '-indev', template, '-extract', '/' + name,
			stage + '/' + name], out + '/m17b-extract-' + os.file_name(name) + '.log', 60)!
		check(os.is_file(stage + '/' + name), 'template missing ${name}')!
	}
	os.write_file(stage + '/boot/limine.conf',
		'timeout: 0\nverbose: yes\n\n/M17B NFSv3 qualification\n    protocol: limine\n    kernel_path: boot():/boot/vinix\n    module_path: boot():/boot/initramfs.tar\n    resolution: 1024x768x32\n    kaslr: no\n')!
	run(['xorriso', '-as', 'mkisofs', '-iso-level', '3', '-R', '-r', '-J', '-b',
		'boot/limine-bios-cd.bin', '-no-emul-boot', '-boot-load-size', '4', '-boot-info-table',
		'--efi-boot', 'boot/limine-uefi-cd.bin', '--efi-boot-part', '--efi-boot-image',
		'--protective-msdos-label', stage, '-o', out + '/m17b-nfs.iso'], out + '/m17b-iso.log', 120)!
	// CD-only boot does not require the Limine bios-install used for USB disks.
	check(os.file_size(out + '/m17b-nfs.iso') > 0, 'ISO was not created')!
	os.write_file(out + '/m17b-input-sha256.txt', 'M17B-HOST:KERNEL_SHA256=${digest(kernel)!}\nM17B-HOST:INIT_SHA256=${digest(init)!}\nM17B-HOST:TEMPLATE_SHA256=${digest(template)!}\nM17B-HOST:ISO_SHA256=${digest(
		out + '/m17b-nfs.iso')!}\n')!
}

fn inspect_container(name string, log string) !string {
	check(name.starts_with('m17b-') && name.len > 5 && name.len <= 100
		&& name.bytes().all((it >= `a` && it <= `z`) || (it >= `A` && it <= `Z`)
		|| (it >= `0` && it <= `9`) || it in [`-`, `_`, `.`]),
		'--stop-container requires an exact dedicated m17b-* container name')!
	run(['docker', 'inspect', '--type', 'container', '--format',
		'{{.Id}}\n{{.Name}}\n{{.HostConfig.NetworkMode}}\n{{.State.Running}}', name], log, 5)!
	lines := os.read_file(log)!.trim_space().split_into_lines()
	check(lines.len == 4 && lines[0].len == 64 && lines[0].bytes().all((it >= `0` && it <= `9`)
		|| (it >= `a` && it <= `f`)) && lines[1] == '/' + name && lines[2] !in ['host', 'none', '']
		&& !lines[2].starts_with('container:') && lines[3] == 'true',
		'require named running container in separate network namespace; see ${log}')!
	return lines[0]
}

fn edit_in_place(path string) ! {
	mut f := os.open_file(path, 'r+')!
	defer { f.close() }
	check(f.write_string('host-edit-v2\n')! == 13, 'short host edit')!
}

fn boot(out string, share string, readonly string, qemu string, accel string, firmware string,
	seconds int, container string, container_id string, start u64) ! {
	mut argv := ['-name', 'm17b-nfs-qualification', '-M', 'q35,smm=off', '-accel', accel, '-cpu',
		if accel == 'kvm' { 'host' } else { 'max' }, '-smp', '4', '-m', '2048', '-vga', 'std',
		'-cdrom', out + '/m17b-nfs.iso', '-boot', 'd', '-display', 'none', '-serial',
		'file:' + out +
			'/m17b-serial.log', '-monitor', 'none', '-netdev',
		'user,id=m17bnet,net=10.0.2.0/24,host=10.0.2.2,dhcpstart=10.0.2.15', '-device',
		'virtio-net-pci,netdev=m17bnet', '-no-reboot']
	if firmware != '' {
		check(os.is_file(firmware), 'firmware missing')!
		argv << ['-drive', 'if=pflash,format=raw,unit=0,readonly=on,file=' + firmware]
	}
	os.write_file(out + '/m17b-qemu-argv.txt', qemu + '\n' + argv.join('\n') + '\n')!
	mut q := os.new_process(qemu)
	q.set_args(argv)
	q.set_redirect_stdio()
	mut log := os.create(out + '/m17b-qemu.log')!
	defer { log.close() }
	q.run()
	defer {
		// Exact direct child handle, never a process name, shared pidfile or group.
		cleanup_child(mut q)
		log.write_string(q.stdout_slurp() + q.stderr_slurp()) or {}
		q.close()
	}
	check(q.pid > 0, 'QEMU failed to start')!
	os.write_file(out + '/m17b-qemu.pid', '${q.pid}\n')!
	milestone('qemu-started pid=${q.pid} watchdog_seconds=${seconds}', start)
	mut edited := false
	mut stopped := false
	mut reported := 0
	mut pending := ''
	mut next_progress := time.sys_mono_now() + u64(10 * time.second)
	deadline := time.sys_mono_now() + u64(seconds) * u64(time.second)
	for time.sys_mono_now() < deadline {
		drain_pipes(mut q, mut log)!
		serial := os.read_file(out + '/m17b-serial.log') or { '' }
		// Consume complete serial lines only; a partial write must not swallow
		// a barrier or outcome forever. The file remains the audit source.
		check(serial.len >= reported, 'serial log truncated')!
		pending += serial[reported..]
		reported = serial.len
		for pending.contains('\n') {
			line := pending.all_before('\n').trim_right('\r')
			pending = pending.all_after('\n')
			if line.starts_with('M17B:') { milestone('guest ${line}', start) }
			if line.starts_with('M17B:stop-server-ready ') {
				check(!stopped && edited, 'duplicate/early stop barrier')!
				check(line == 'M17B:stop-server-ready quiet_seconds=2 wait_seconds=8 retained_rw_mount=1',
					'malformed stop barrier; refusing container stop')!
				stop_start := time.sys_mono_now()
				if container != '' {
					// Stop by immutable ID so a name replacement cannot target another service.
					run(['docker', 'stop', '--timeout', '1', container_id], out +
						'/m17b-docker-stop.log', 6)!
					check(time.sys_mono_now() - stop_start < u64(7 * time.second),
						'docker stop exceeded guest quiet window')!
					os.write_file(out + '/m17b-server-stop.txt',
						'M17B-HOST:server-stop mode=docker name=${container} id=${container_id} attempts=1 rc=0 elapsed_ms=${(time.sys_mono_now() - stop_start) / u64(time.millisecond)}\n')!
					milestone('server-stopped name=${container} id=${container_id} attempts=1',
						start)
				} else {
					os.write_file(out + '/m17b-server-stop.txt',
						'M17B-HOST:server-stop mode=external-controller action=serial-barrier stop-not-performed-by-rig=1\n')!
					milestone('stop-server-manually-now quiet_window_seconds=8 dedicated_container_only=1',
						start)
				}
				stopped = true
			}
		}
		if !edited && os.exists(share + '/guest-ready')
			&& os.read_file(share + '/guest-ready')! == 'ready\n' {
			edit_in_place(share + '/host-small.txt')!
			os.write_file(share + '/host-updated.txt', 'host update complete\n')!
			edited = true
			milestone('host-edit-applied in_place=1 sha256=${digest(share + '/host-small.txt')!}',
				start)
		}
		if serial.contains('M17B:OUTCOME FAIL') || serial.to_lower().contains('panic') {
			return error('guest failure/panic; see ${out}/m17b-serial.log')
		}
		if serial.contains('M17B:OUTCOME PASS status=0 ') && pending == '' {
			check(edited && stopped, 'host handshake/barrier missing')!
			verify(out, share, readonly)!
			// PID1 must remain alive and parked after the verdict as well.
			grace := time.sys_mono_now() + u64(2 * time.second)
			for time.sys_mono_now() < grace {
				drain_pipes(mut q, mut log)!
				check(q.is_alive(), 'QEMU exited during post-outcome grace period')!
				latest := os.read_file(out + '/m17b-serial.log')!
				check(!latest.to_lower().contains('panic') && !latest.contains('M17B:OUTCOME FAIL'),
					'guest failure/panic after outcome')!
				time.sleep(50 * time.millisecond)
			}
			return
		}
		if !q.is_alive() { return error('QEMU exited before outcome; see ${out}/m17b-qemu.log') }
		if time.sys_mono_now() >= next_progress {
			milestone('waiting-for-guest', start)
			next_progress += u64(10 * time.second)
		}
		time.sleep(50 * time.millisecond)
	}
	return error('guest watchdog exceeded ${seconds}s; direct QEMU child killed/reaped')
}

fn distinct(a string, b string) bool {
	return a != b && !a.starts_with(b + '/') && !b.starts_with(a + '/')
}

fn usage() {
	println('M17B-HOST:rig --kernel ELF --init STATIC_ELF --template BOOTABLE_ISO --share EMPTY_DIR --readonly EMPTY_DIR --out NEW_m17b_DIR [--qemu PATH] [--accel kvm|tcg] [--firmware OVMF] [--timeout 900] [--stop-container m17b-NAME]')
	println('M17B-HOST:optional --source 10.0.2.2:/export/share --ro-source 10.0.2.2:/export/readonly --missing-source 10.0.2.2:/export/m17b-not-exported')
	println('M17B-HOST:rig --verify EXISTING_m17b_DIR --share SAME_DIR --readonly SAME_RO_DIR')
	println('M17B-HOST:rig --hash FILE (host SHA256 only, no qualification claim)')
}

fn qualify_host(start u64) ! {
	mut opts := map[string]string{}
	mut i := 1
	for i < os.args.len {
		if os.args[i] == '--help' {
			usage()
			return
		}
		key := os.args[i]
		check(i + 1 < os.args.len && key !in opts
			&& key in ['--kernel', '--init', '--template', '--share', '--readonly', '--out', '--qemu', '--accel', '--firmware', '--timeout', '--stop-container', '--source', '--ro-source', '--missing-source', '--verify', '--hash', '--repo'],
			'invalid/duplicate option ${key}; use --help')!
		opts[key] = os.args[i + 1]
		i += 2
	}
	if '--hash' in opts {
		check(opts.len == 1, '--hash accepts only one file')!
		path := os.abs_path(opts['--hash'])
		println('M17B-HOST:SHA256=${digest(path)!} path=${path}')
		return
	}
	for key in ['--share', '--readonly'] {
		check(opts[key] != '', 'missing ${key}')!
	}
	share := os.real_path(opts['--share'])
	readonly := os.real_path(opts['--readonly'])
	check(share != '' && readonly != '' && share != '/' && readonly != '/'
		&& distinct(share, readonly),
		'--share and --readonly must be distinct dedicated directories without nesting')!
	if '--verify' in opts {
		check(opts.len == 3, '--verify requires only --share and --readonly')!
		verify(os.abs_path(opts['--verify']), share, readonly)!
		milestone('VERIFY PASS audit-only no-reboot', start)
		return
	}
	for key in ['--kernel', '--init', '--template', '--out'] {
		check(opts[key] != '', 'missing ${key}')!
	}
	out := os.abs_path(opts['--out'])
	check(!os.exists(out) && os.file_name(out).starts_with('m17b-') && distinct(out, share)
		&& distinct(out, readonly), 'require new m17b-* output directory outside fixtures')!
	accel := if opts['--accel'] == '' { 'kvm' } else { opts['--accel'] }
	seconds_text := if opts['--timeout'] == '' { '900' } else { opts['--timeout'] }
	check(seconds_text.bytes().all(it >= `0` && it <= `9`) && seconds_text.len <= 3,
		'--timeout must be an integer 30..900')!
	seconds := seconds_text.int()
	check(accel in ['kvm', 'tcg'] && seconds >= 30 && seconds <= 900,
		'require accel kvm|tcg and timeout 30..900')!
	sources := [if opts['--source'] == '' { '10.0.2.2:/export/share' } else { opts['--source'] },
		if opts['--ro-source'] == '' { '10.0.2.2:/export/readonly' } else { opts['--ro-source'] },
		if opts['--missing-source'] == '' {
			'10.0.2.2:/export/m17b-not-exported'
		} else {
			opts['--missing-source']
		}]
	for source in sources {
		check(source.contains(':/') && !source.bytes().any(it <= 32 || it == 127),
			'invalid NFS source ${source}')!
	}
	// Validate all non-mutating prerequisites before creating fixture files.
	for key in ['--kernel', '--init', '--template'] {
		check(os.is_file(opts[key]), 'missing ${key} input')!
	}
	for tool in ['tar', 'xorriso', if opts['--qemu'] == '' {
		'qemu-system-x86_64'
	} else {
		opts['--qemu']
	}] {
		os.find_abs_path_of_executable(tool)!
	}
	for path in [share, readonly] {
		check(os.is_dir(path) && os.ls(path)!.len == 0, 'fixture directory not empty: ${path}')!
	}
	os.mkdir(out)!
	os.chmod(out, 0o700)!
	container := opts['--stop-container']
	container_id := if container != '' {
		inspect_container(container, out + '/m17b-container-inspect.log')!
	} else {
		''
	}
	prepare(share, readonly, out, start)!
	build_iso(os.abs_path(opts['--kernel']), os.abs_path(opts['--init']),
		os.abs_path(opts['--template']), out, sources)!
	milestone('iso-ready path=${out}/m17b-nfs.iso', start)
	boot(out, share, readonly, if opts['--qemu'] == '' {
		'qemu-system-x86_64'
	} else {
		opts['--qemu']
	}, accel, opts['--firmware'], seconds, container, container_id, start)!
	milestone('OUTCOME PASS qemu-stopped=1', start)
}

fn main() {
	start := time.sys_mono_now()
	qualify_host(start) or {
		eprintln('M17B-HOST:FAIL ${err} elapsed_ms=${(time.sys_mono_now() - start) / u64(time.millisecond)}')
		exit(1)
	}
}
