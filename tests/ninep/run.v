// SPDX-License-Identifier: GPL-2.0-or-later
// Disposable fecv3 qualification controller. No PVE or network access.
module main

import crypto.sha256
import os
import time

fn run(argv []string, env map[string]string, log string) ! {
	mut p := os.new_process(argv[0])
	p.set_args(argv[1..])
	p.set_environment(env)
	p.set_redirect_stdio()
	p.run()
	stdout := p.stdout_slurp()
	stderr := p.stderr_slurp()
	p.wait()
	code := p.code
	p.close()
	os.write_file(log, stdout + stderr)!
	if code != 0 { return error('command exit ${code}: ${argv}; see ${log}') }
}

fn digest(path string) !string {
	mut f := os.open(path)!
	defer { f.close() }
	mut hash := sha256.new()
	mut buffer := []u8{len: 65536}
	for {
		n := f.read(mut buffer)!
		if n == 0 { break }
		hash.write(buffer[..n])!
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

fn qualify(repo string, kernel string, init string, out string) ! {
	if os.exists(out) { return error('refusing existing output directory ${out}') }
	for d in ['root/sbin', 'root/dev', 'root/proc', 'root/mnt', 'root/tmp', 'share'] {
		os.mkdir_all(out + '/' + d)!
	}
	os.cp(init, out + '/root/sbin/init')!
	os.chmod(out + '/root/sbin/init', 0o755)!
	os.write_file(out + '/share/host-small.txt', 'host-edit-v1\n')!
	host_hash := fixture(out + '/share/host-big.bin', false)!
	// Independent expected guest stream, retained outside the exported tree.
	guest_hash := fixture(out + '/guest-expected.bin', true)!
	os.write_file(out + '/expected-sha256.txt', 'HOST_BIG:${host_hash}\nGUEST_BIG:${guest_hash}\n')!
	run(['tar', '--format=ustar', '-cf', out + '/initramfs.tar', '-C', out + '/root', '.'], os.environ(), out + '/tar.log')!
	mut env := os.environ()
	env['VINIX_AMD64_ISO_BUILD_DIR'] = out + '/iso-build'
	env['VINIX_AMD64_KERNEL'] = kernel
	env['VINIX_AMD64_INITRAMFS'] = out + '/initramfs.tar'
	env['VINIX_AMD64_ISO'] = out + '/m16a-9p.iso'
	run([repo + '/build-support/build-amd64-iso.sh'], env, out + '/iso-build.log')!
	argv := ['qemu-system-x86_64', '-name', 'm16a-9p-qualification', '-M', 'q35,smm=off', '-enable-kvm',
		'-cpu', 'host', '-smp', '4', '-m', '2048', '-vga', 'std', '-drive',
		'if=pflash,format=raw,unit=0,readonly=on,file=/usr/share/edk2/x64/OVMF_CODE.4m.fd', '-cdrom',
		out + '/m16a-9p.iso', '-nic', 'none', '-virtfs',
		'local,path=' + out + '/share,mount_tag=share,security_model=mapped-xattr,multidevs=remap',
		'-display', 'none', '-serial', 'file:' + out + '/serial.log', '-qmp',
		'unix:' + out + '/qmp.sock,server=on,wait=off', '-monitor', 'none', '-pidfile',
		out + '/qemu.pid', '-daemonize']
	os.write_file(out + '/qemu-argv.txt', argv.join('\n') + '\n')!
	run(argv, os.environ(), out + '/qemu-launch.log')!
	defer {
		// QMP is local and unique. Never kill other lanes by process name.
		run(['/home/agent/build/vinix-net-rig/qmp', out + '/qmp.sock', 'raw', '{"execute":"quit"}'], os.environ(), out + '/qemu-stop.log') or { eprintln('owned QEMU stop failed: ${err}') }
	}
	mut edited := false
	deadline := time.sys_mono_now() + u64(300 * time.second)
	for time.sys_mono_now() < deadline {
		serial := os.read_file(out + '/serial.log') or { '' }
		if !edited && os.exists(out + '/share/guest-ready') {
			if os.read_file(out + '/share/guest-ready')! != 'ready\n' {
				return error('host observed corrupt ready marker')
			}
			os.write_file(out + '/share/host-small.txt', 'host-edit-v2\n')!
			os.write_file(out + '/share/host-updated.txt', 'host update complete\n')!
			edited = true
			println('HOST:edited existing host-small.txt in place')
		}
		if serial.contains('M16A:OUTCOME FAIL') || serial.contains('KERNEL PANIC') {
			return error('guest failed; see ${out}/serial.log')
		}
		if serial.contains('M16A:OUTCOME PASS') {
			if !edited { return error('host edit handshake missing') }
			if !serial.contains('source_sha256=' + host_hash) {
				return error('guest source digest differs from host fixture')
			}
			if !serial.contains('generated_sha256=' + guest_hash) {
				return error('guest deterministic digest differs from host expectation')
			}
			actual := digest(out + '/share/guest-big.bin')!
			if actual != guest_hash || os.file_size(out + '/share/guest-big.bin') != 104857600 {
				return error('host guest-big size/hash mismatch')
			}
			if os.read_file(out + '/share/guest-small.txt')! != 'mission16-a guest-small-v1\n' {
				return error('host small file mismatch')
			}
			if digest(out + '/share/host-big.bin')! != host_hash {
				return error('host source changed')
			}
			os.write_file(out + '/host-verification.txt', 'HOST_VERIFY:PASS\nHOST_BIG_SHA256:${host_hash}\nGUEST_BIG_SHA256:${actual}\nSMALL_SHA256:${digest(out + '/share/guest-small.txt')!}\n')!
			println(os.read_file(out + '/host-verification.txt')!)
			return
		}
		time.sleep(500 * time.millisecond)
	}
	return error('qualification timed out after 300 seconds')
}

fn main() {
	if os.args.len != 5 {
		eprintln('usage: run REPO KERNEL INIT NEW_OUTPUT_DIR')
		exit(2)
	}
	qualify(os.abs_path(os.args[1]), os.abs_path(os.args[2]), os.abs_path(os.args[3]), os.abs_path(os.args[4])) or {
		eprintln('M16A-HOST:FAIL ${err}')
		exit(1)
	}
	println('M16A-HOST:PASS')
}
