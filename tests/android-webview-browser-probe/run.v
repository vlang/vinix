// SPDX-License-Identifier: GPL-2.0-or-later
// Host lifecycle for one audited, credential-free diagnostic guest.
module main

import crypto.sha256
import json2
import net
import net.unix
import os
import strconv
import time

#include <signal.h>
#include <errno.h>
#include <fcntl.h>
#include <libproc.h>
#include <CommonCrypto/CommonDigest.h>

fn C.kill(int, int) int
fn C.proc_pidpath(int, voidptr, u32) int
@[typedef]
struct C.CC_SHA256_CTX {}
fn C.CC_SHA256_Init(voidptr) i32
fn C.CC_SHA256_Update(voidptr, voidptr, u32) i32
fn C.CC_SHA256_Final(&u8, voidptr) i32

const repo = '/Users/alex/code/vinix'
const qemu = repo + '/build/qemu-horizontal/bin/qemu-system-aarch64'
const firmware = '/opt/homebrew/share/qemu/edk2-aarch64-code.fd'
const source = $embed_file(@FILE).to_string()

struct Ownership {
	pid     int
	command string
	started string
}

struct Stage {
	format                int
	staged_boot_sha256    string
	staged_efivars_sha256 string
}

enum NetworkMode {
	user_default
	ipv4_only
}

// The larger budget is available only through explicitly named CLI selectors.
// It does not change the default policy or the diagnostic guest's resources.
enum CoexistPolicy {
	quarter_host_32g
	half_host_64g
}

fn (policy CoexistPolicy) limit_mib() u64 {
	return if policy == .half_host_64g { u64(65536) } else { u64(32768) }
}

fn (policy CoexistPolicy) host_divisor() u64 {
	return if policy == .half_host_64g { u64(2) } else { u64(4) }
}

fn (policy CoexistPolicy) limits() string {
	budget := if policy == .half_host_64g { '<=64GiB and host/2; host >=128GiB' } else { '<=32GiB and host/4' }
	return 'one foreign QEMU; aggregate RAM ' + budget + '; aggregate CPU <=host logical; sysctl pressure1; disk reserve1GiB; own12GiB/fourCPU unchanged'
}

fn (mode NetworkMode) backend() string {
	return if mode == .ipv4_only { 'user,id=net0,ipv6=off' } else { 'user,id=net0' }
}

fn (mode NetworkMode) evidence() json2.Any {
	return json2.Any({
		'mode': json2.Any(if mode == .ipv4_only { 'ipv4-only' } else { 'user-default' })
		'backend': json2.Any(mode.backend())
	})
}

struct Execution {
	argv   []string
	code   int
	stdout string
	stderr string
}

struct StopReceipt {
	pid           int
	signal        string
	requested_utc string
}

struct ForeignDirectoryIdentity {
	path string
	dev u64
	inode u64
	mode u32
	uid u32
}

struct ForeignResourceIdentity {
	path string
	dev u64
	inode u64
	mode u32
	nlink u64
	uid u32
	absent bool
	socket_parent ForeignDirectoryIdentity
}

struct ForeignAdmission {
	owner Ownership
	executable string
	executable_sha256 string
	memory_mib u64
	cpus u64
	inventory string
	host_memory string
	host_cpus string
	host_pressure string
	disk_available u64
	disk_report string
	sampled_utc string
	referenced_paths map[string]ForeignResourceIdentity
	budget_policy string
	aggregate_limit_mib u64
	host_memory_divisor u64
}

fn positive_decimal(value string) !u64 {
	if value.len == 0 || value.len > 20 || value[0] == `0`
		|| !value.bytes().all(it >= `0` && it <= `9`) {
		return error('plain positive decimal resource value required')
	}
	return strconv.parse_uint(value, 10, 64)
}

fn available_disk_bytes(output string) !u64 {
	rows := output.trim_space().split_into_lines()
	if output.len > 8192 || rows.len != 2 || rows[0].fields() != ['Filesystem', '1024-blocks', 'Used', 'Available', 'Capacity', 'Mounted', 'on'] {
		return error('bounded canonical df -kP report required')
	}
	columns := rows[1].fields()
	if columns.len < 6 || !columns[0].starts_with('/') || !columns[5].starts_with('/') || !columns[4].ends_with('%') {
		return error('invalid df filesystem report')
	}
	mut counts := []u64{}
	for value in columns[1..4] {
		count := if value == '0' { u64(0) } else { positive_decimal(value)! }
		if count > u64(0xffffffffffffffff) / 1024 { return error('df block count overflow') }
		counts << count
	}
	capacity := columns[4][..columns[4].len - 1]
	percent := if capacity == '0' { u64(0) } else { positive_decimal(capacity)! }
	if counts[0] == 0 || counts[1] > counts[0] || counts[2] > counts[0] || percent > 100 { return error('inconsistent df counts') }
	return counts[2] * 1024
}

fn foreign_drive(value string) ! {
	foreign_drive_policy(value, .quarter_host_32g)!
}

fn foreign_drive_policy(value string, policy CoexistPolicy) ! {
	mut fields := map[string]string{}
	for item in value.split(',') {
		key, data := item.all_before('='), item.all_after('=')
		if key == item || key in fields || (key !in ['if', 'format', 'file', 'readonly']
			&& !(policy == .half_host_64g && key in ['discard', 'detect-zeroes'])) {
			return error('unsupported foreign drive configuration')
		}
		fields[key] = data
	}
	if fields['if'] or { '' } !in ['pflash', 'virtio'] || fields['format'] or { '' } !in ['raw', 'qcow2']
		|| !(fields['file'] or { '' }).starts_with('/') || fields['readonly'] or { 'on' } != 'on' {
		return error('simple foreign disk/firmware configuration required')
	}
	for key in ['discard', 'detect-zeroes'] {
		if key in fields && (fields[key] != 'unmap' || fields['if'] != 'virtio'
			|| fields['format'] != 'qcow2' || 'readonly' in fields) {
			return error('foreign unmap options require a writable virtio qcow2 drive')
		}
	}
}

fn foreign_qmp_path(value string) !string {
	if !value.starts_with('unix:/') || !value.ends_with(',server=on,wait=off') {
		return error('foreign QMP requires an exact nonblocking Unix server')
	}
	path := value[5..value.len - ',server=on,wait=off'.len]
	if path.len >= 104 || path.contains_any(' ,\t\r\n\x00') || os.abs_path(path) != path {
		return error('bounded absolute foreign QMP path required')
	}
	return path
}

// This opt-in deliberately accepts only simple, unquoted argv forms. Unknown
// options and alternate memory/CPU configurations are not inferred from ps.
fn foreign_resources(command string) !(u64, u64) {
	return foreign_resources_policy(command, .quarter_host_32g)
}

fn foreign_resources_policy(command string, policy CoexistPolicy) !(u64, u64) {
	if command.contains_any('\t\r\n\x00\'"\\') { return error('unsupported quoted foreign argv') }
	args := command.fields()
	if args.len < 2 || args.join(' ') != command { return error('canonical foreign argv required') }
	mut memory := u64(0)
	mut cpus := u64(0)
	mut machine := 0
	mut daemon := 0
	mut counts := map[string]int{}
	mut at := 1
	for at < args.len {
		flag := args[at]
		at++
		if flag == '-daemonize' {
			daemon++
			if daemon > 1 { return error('duplicate foreign daemon option') }
			continue
		}
		if (flag !in ['-machine', '-cpu', '-m', '-smp', '-drive', '-device', '-netdev',
			'-display', '-serial', '-monitor', '-pidfile', '-D']
			&& !(policy == .half_host_64g && flag == '-qmp')) || at >= args.len
			|| args[at].starts_with('-') { return error('unsupported foreign QEMU option: ' + flag) }
		value := args[at]
		at++
		counts[flag]++
		if counts[flag] > (if flag == '-drive' { 4 } else { 1 }) {
			return error('duplicate or excessive foreign option: ' + flag)
		}
		if value.contains('memory-backend=') || value.contains('pc-dimm') || value.contains('virtio-mem') {
			return error('unsupported foreign memory device')
		}
		match flag {
			'-m' { if memory != 0 { return error('duplicate foreign memory') }; memory = positive_decimal(value)! }
			'-smp' { if cpus != 0 { return error('duplicate foreign CPU count') }; cpus = positive_decimal(value)! }
			'-machine' {
				machine++
				if machine != 1 || value !in ['virt', 'virt,accel=hvf,highmem=on'] {
					return error('unsupported foreign machine configuration')
				}
			}
			'-monitor' { if value != 'none' { return error('foreign monitor must be disabled') } }
			'-display' { if value != 'none' { return error('foreign display must be disabled') } }
			'-cpu' { if value != 'host' { return error('foreign CPU must be host') } }
			'-device' { if value != 'virtio-net-pci,netdev=net0' { return error('unsupported foreign device') } }
			'-drive' { foreign_drive_policy(value, policy)! }
			'-qmp' { foreign_qmp_path(value)! }
			'-netdev' {
				parts := value.split(',')
				if parts.len !in [2, 3] || parts[0] != 'user' || parts[1] != 'id=net0'
					|| (parts.len == 3 && !parts[2].starts_with('hostfwd=tcp:127.0.0.1:')) {
					return error('unsupported foreign user network')
				}
			}
			else {}
		}
	}
	if memory == 0 || cpus == 0 || machine != 1 { return error('explicit foreign memory/CPU/machine required') }
	return memory, cpus
}

fn foreign_path(path string, root string, readonly bool) !ForeignResourceIdentity {
	if !os.is_abs_path(path) { return error('absolute foreign resource path required') }
	resolved := os.real_path(path)
	if !os.is_file(resolved) || resolved == root || resolved.starts_with(root + '/')
		|| resolved == repo || resolved.starts_with(repo + '/') {
		return error('foreign resource must remain outside audited roots')
	}
	info := os.lstat(resolved)!
	if info.nlink != 1 || (!readonly && resolved != path) {
		return error('single-linked canonical writable foreign resources required')
	}
	for name in ['boot.img', 'efivars.fd'] {
		if !os.exists(root + '/' + name) { continue }
		owned_info := os.lstat(root + '/' + name)!
		if info.dev == owned_info.dev && info.inode == owned_info.inode { return error('foreign resource aliases owned media') }
	}
	return ForeignResourceIdentity{path: resolved, dev: info.dev, inode: info.inode,
		mode: info.mode, nlink: info.nlink, uid: info.uid}
}

fn foreign_paths(command string, root string) !map[string]ForeignResourceIdentity {
	return foreign_paths_policy(command, root, .quarter_host_32g)
}

fn foreign_directory(path string) !ForeignDirectoryIdentity {
	resolved := os.real_path(path)
	info := os.lstat(resolved)!
	if info.get_filetype() != .directory { return error('existing foreign QMP parent directory required') }
	return ForeignDirectoryIdentity{resolved, info.dev, info.inode, info.mode, info.uid}
}

// lstat only: admission never connects to, reads from or writes to foreign QMP.
fn foreign_socket(path string, root string) !ForeignResourceIdentity {
	if !os.is_abs_path(path) { return error('absolute foreign QMP path required') }
	parent := foreign_directory(os.dir(path))!
	resolved := os.join_path(parent.path, os.file_name(path))
	if resolved == root || resolved.starts_with(root + '/')
		|| resolved == repo || resolved.starts_with(repo + '/') {
		return error('separate foreign QMP socket required')
	}
	info := os.lstat(resolved) or {
		if err.code() != C.ENOENT { return error('cannot inspect foreign QMP endpoint: ' + err.msg()) }
		if foreign_directory(os.dir(path))! != parent { return error('foreign QMP parent changed during inspection') }
		// QEMU can retain an unlinked listener. This records only absence in the
		// namespace and its existing parent, never the state of a listener.
		return ForeignResourceIdentity{path: resolved, absent: true, socket_parent: parent}
	}
	if info.get_filetype() != .socket || info.uid != u32(os.geteuid()) || info.nlink != 1 {
		return error('single-linked foreign QMP socket owned by this user required')
	}
	if foreign_directory(os.dir(path))! != parent { return error('foreign QMP parent changed during inspection') }
	return ForeignResourceIdentity{path: resolved, dev: info.dev, inode: info.inode,
		mode: info.mode, nlink: info.nlink, uid: info.uid, socket_parent: parent}
}

fn foreign_paths_policy(command string, root string, policy CoexistPolicy) !map[string]ForeignResourceIdentity {
	args := command.fields()
	mut paths := map[string]ForeignResourceIdentity{}
	mut at := 1
	for at < args.len {
		flag := args[at]
		at++
		if flag == '-daemonize' { continue }
		value := args[at]
		at++
		if flag == '-qmp' {
			if policy != .half_host_64g { return error('foreign QMP requires explicit 64GiB policy') }
			path := foreign_qmp_path(value)!
			paths[path] = foreign_socket(path, root)!
			continue
		}
		mut path := ''
		mut readonly := false
		if flag == '-drive' {
			for item in value.split(',') {
				if item.starts_with('file=') { path = item[5..] }
				if item == 'readonly=on' { readonly = true }
			}
		} else if flag in ['-pidfile', '-D'] { path = value }
		else if flag == '-serial' {
			if !value.starts_with('file:/') { return error('foreign serial must be an absolute file') }
			path = value[5..]
		}
		if path != '' { paths[path] = foreign_path(path, root, readonly)! }
	}
	return paths
}

fn qemu_inventory(output string) ![]int {
	mut pids := []int{}
	for row in output.split_into_lines() {
		line := row.trim_space()
		if line == '' { continue }
		columns := line.fields()
		if columns.len < 2 { return error('invalid process inventory row') }
		name := os.file_name(line.all_after(columns[0]).trim_space())
		if name.starts_with('qemu-system-') || name in ['qemu', 'qemu-kvm'] {
			pid := positive_decimal(columns[0])!
			if pid > 2147483647 || int(pid) in pids { return error('invalid duplicate QEMU PID') }
			pids << int(pid)
		}
	}
	return pids
}

fn admit_resources(memory u64, cpus u64, physical u64, logical u64, pressure u64, available u64) ! {
	admit_resources_policy(memory, cpus, physical, logical, pressure, available, .quarter_host_32g)!
}

fn admit_resources_policy(memory u64, cpus u64, physical u64, logical u64, pressure u64, available u64, policy CoexistPolicy) ! {
	if memory > policy.limit_mib() - 12288 || cpus > 1024 - 4 || logical > 1024
		|| memory == 0 || cpus == 0 || logical == 0 {
		return error('coexisting guest resource bounds exceeded')
	}
	if (policy == .half_host_64g && physical < u64(128) * 1024 * 1024 * 1024)
		|| (memory + 12288) * 1024 * 1024 > physical / policy.host_divisor() || cpus + 4 > logical
		|| pressure != 1 || available < u64(1024) * 1024 * 1024 {
		return error('coexisting guest host admission refused')
	}
}

fn foreign_admission(root string, pid int) !ForeignAdmission {
	return foreign_admission_policy(root, pid, .quarter_host_32g)
}

fn foreign_admission_policy(root string, pid int, policy CoexistPolicy) !ForeignAdmission {
	if pid <= 1 { return error('explicit foreign PID required') }
	inventory := checked(['/bin/ps', '-ww', '-axo', 'pid=,comm='])!
	if qemu_inventory(inventory)! != [pid] { return error('exactly the selected foreign QEMU required') }
	owner := identity(pid)!
	if process_gone(owner)! || owner.command.contains(repo) || owner.command.contains(root) {
		return error('foreign guest must be live and separate from audited roots')
	}
	mut bytes := []u8{len: 4096}
	if C.proc_pidpath(pid, bytes.data, u32(bytes.len)) <= 0 { return error('cannot inspect foreign executable') }
	mut end := 0
	for end < bytes.len && bytes[end] != 0 { end++ }
	if end == bytes.len { return error('unterminated foreign executable') }
	executable := bytes[..end].bytestr()
	if os.file_name(executable) != 'qemu-system-aarch64' || os.real_path(executable) != executable
		|| executable == os.real_path(qemu) || os.real_path(owner.command.all_before(' ')) != executable {
		return error('separate actual aarch64 QEMU executable required')
	}
	foreign_exe := os.lstat(executable)!
	owned_exe := os.lstat(os.real_path(qemu))!
	if foreign_exe.dev == owned_exe.dev && foreign_exe.inode == owned_exe.inode {
		return error('foreign executable aliases audited QEMU')
	}
	memory, cpus := foreign_resources_policy(owner.command, policy)!
	paths := foreign_paths_policy(owner.command, root, policy)!
	physical := checked(['/usr/sbin/sysctl', '-n', 'hw.memsize'])!
	logical := checked(['/usr/sbin/sysctl', '-n', 'hw.logicalcpu'])!
	pressure := checked(['/usr/sbin/sysctl', '-n', 'kern.memorystatus_vm_pressure_level'])!
	disk := checked(['/usr/bin/env', 'LC_ALL=C', '/bin/df', '-kP', root])!
	available := available_disk_bytes(disk)!
	admit_resources_policy(memory, cpus, positive_decimal(physical)!, positive_decimal(logical)!, positive_decimal(pressure)!, available, policy)!
	return ForeignAdmission{owner, executable, hash(executable)!, memory, cpus, inventory,
		physical, logical, pressure, available, disk, time.utc().str(), paths,
		policy.str(), policy.limit_mib(), policy.host_divisor()}
}

fn same_foreign(before ForeignAdmission, after ForeignAdmission) ! {
	if before.owner != after.owner || before.executable != after.executable
		|| before.executable_sha256 != after.executable_sha256 || before.memory_mib != after.memory_mib
		|| before.cpus != after.cpus || before.referenced_paths != after.referenced_paths
		|| before.budget_policy != after.budget_policy || before.aggregate_limit_mib != after.aggregate_limit_mib
		|| before.host_memory_divisor != after.host_memory_divisor {
		return error('foreign guest identity or resources changed during admission')
	}
}

fn strict_guest_check(output string) ! {
	for line in output.split_into_lines() {
		if line.contains('qemu-system-aarch64 ') && line.contains(' -machine ') {
			return error('another aarch64 QEMU guest is live')
		}
	}
}

fn hash(path string) !string {
	mut file := os.open(path)!
	defer { file.close() }
	mut digest := C.CC_SHA256_CTX{}
	mut bytes := []u8{len: 1024 * 1024}
	if C.CC_SHA256_Init(unsafe { &digest }) != 1 { return error('SHA256 initialization') }
	for {
		n := file.read(mut bytes) or {
			if err is os.Eof { break }
			return err
		}
		if n == 0 { break }
		if C.CC_SHA256_Update(unsafe { &digest }, bytes.data, u32(n)) != 1 {
			return error('SHA256 update')
		}
	}
	mut result := [32]u8{}
	if C.CC_SHA256_Final(unsafe { &result[0] }, unsafe { &digest }) != 1 {
		return error('SHA256 finalization')
	}
	return result[..].hex()
}

fn hash_self_test(root string) ! {
	path := root + '/sha256-input'
	defer { os.rm(path) or {} }
	for input, expected in {
		'': 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'
		'abc': 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad'
	} {
		os.write_file(path, input)!
		assert hash(path)! == expected
	}
	mut bytes := []u8{len: 2 * 1024 * 1024 + 65}
	for i in 0 .. bytes.len { bytes[i] = u8((i * 29 + 11) % 251) }
	for size in [55, 56, 63, 64, 65, 1024 * 1024 - 1, 1024 * 1024, 1024 * 1024 + 1, bytes.len] {
		os.write_file_array(path, bytes[..size])!
		assert hash(path)! == sha256.sum(bytes[..size]).hex()
	}
	println('HOST-SHA256 SELF-TEST PASS known-vectors block-padding streaming-boundaries V-reference')
}

fn execute(argv []string) !Execution {
	mut process := os.new_process(argv[0])
	process.set_args(argv[1..])
	process.set_stdin_path('/dev/null')
	process.set_redirect_stdio()
	process.run()
	defer { process.close() }
	mut stdout := ''
	mut stderr := ''
	deadline := time.sys_mono_now() + 15 * time.second
	for {
		stdout += process.stdout_read()
		stderr += process.stderr_read()
		if stdout.len + stderr.len > 1024 * 1024 || time.sys_mono_now() >= deadline {
			process.signal_kill()
			process.wait()
			return error('command output/deadline limit')
		}
		if !process.is_alive() { break }
		time.sleep(10 * time.millisecond)
	}
	process.wait()
	for {
		out := process.stdout_read()
		err := process.stderr_read()
		stdout += out
		stderr += err
		if stdout.len + stderr.len > 1024 * 1024 {
			return error('command output limit')
		}
		if out == '' && err == '' { break }
	}
	return Execution{argv, process.code, stdout, stderr}
}

fn checked(argv []string) !string {
	result := execute(argv)!
	if result.code != 0 { return error('command failed: ' + argv[0] + ': ' + result.stderr) }
	return result.stdout.trim_space()
}

fn canonical_root(path string) !string {
	absolute := os.abs_path(path)
	if !os.is_dir(absolute) || os.real_path(absolute) != absolute || absolute.contains_any(' \t\r\n,\x00') {
		return error('canonical directory without whitespace/comma required')
	}
	if absolute == repo || absolute.starts_with(repo + '/') {
		return error('external staged directory required')
	}
	if !os.is_file(absolute + '/stage.json') { return error('browser stage receipt required') }
	return absolute
}

fn qmp_check(root string) ! {
	if (root + '/qmp.sock').len >= 104 {
		return error('QMP Unix socket path must be shorter than 104 bytes')
	}
}

fn identity(pid int) !Ownership {
	if pid <= 1 { return error('invalid process ID') }
	return Ownership{pid, checked(['/bin/ps', '-ww', '-p', pid.str(), '-o', 'command='])!, checked([
		'/bin/ps',
		'-p',
		pid.str(),
		'-o',
		'lstart=',
	])!}
}

fn recorded_owner(root string) !Ownership {
	recorded := json2.decode[Ownership](os.read_file(root + '/ownership.json')!)!
	if recorded.pid <= 1 || recorded.started == '' || !recorded.command.starts_with(qemu + ' ')
		|| !recorded.command.contains('unix:' + root + '/qmp.sock,server=on,wait=off')
		|| !recorded.command.ends_with('-pidfile ' + root + '/qemu.pid') {
		return error('invalid recorded guest ownership')
	}
	return recorded
}

// One ps snapshot avoids the command/start-time race when a process exits.
// The immutable ownership receipt remains authoritative after QEMU unlinks its
// transient pidfile; only an initial signal additionally requires that pidfile.
fn process_gone(recorded Ownership) !bool {
	if recorded.pid <= 1 { return error('invalid process ID') }
	result := execute(['/bin/ps', '-ww', '-p', recorded.pid.str(), '-o', 'lstart=,command='])!
	output := result.stdout.trim_space()
	if result.code == 1 && output == '' && result.stderr.trim_space() == '' { return true }
	if result.code != 0 {
		return error('could not inspect guest process: ps exit ' + result.code.str())
	}
	if !output.starts_with(recorded.started + ' ')
		|| output[recorded.started.len..].trim_space() != recorded.command {
		return error('live process ownership differs; refusing signal or disappearance receipt')
	}
	return false
}

fn owned(root string) !Ownership {
	recorded := recorded_owner(root)!
	if strconv.atoi(os.read_file(root + '/qemu.pid')!.trim_space())! != recorded.pid {
		return error('PID receipt differs')
	}
	if process_gone(recorded)! { return error('owned guest is no longer live') }
	return recorded
}

fn write_json(path string, value json2.Any) ! {
	mut file := os.open_file(path, 'wx', 0o600)!
	defer { file.close() }
	file.write_string(json2.encode(value, prettify: true) + '\n')!
}

fn fresh_launch(root string) ! {
	// QEMU interprets %d in -D paths as a filename template.
	if root.contains('%') { return error('literal daemon log path required') }
	for name in ['launch.json', 'launch-result.json', 'ownership.json', 'qemu.pid', 'qmp.sock',
		'serial.log', 'network.pcap', 'qemu.log', 'stop.json', 'gone.json', 'run-source.v', 'runner'] {
		if os.exists(root + '/' + name) || os.is_link(root + '/' + name) {
			return error('guest can be launched once only: ' + name)
		}
	}
}

fn verify_daemon_log(root string, before os.Stat) ! {
	info := os.lstat(root + '/qemu.log')!
	if info.get_filetype() != .regular || info.uid != u32(os.geteuid())
		|| info.nlink != 1 || info.mode & 0o777 != 0o600
		|| info.dev != before.dev || info.inode != before.inode {
		return error('same private single-linked daemon log required')
	}
}

fn create_daemon_log(root string) !os.Stat {
	if root.contains('%') { return error('literal daemon log path required') }
	path := root + '/qemu.log'
	// This pinned V library ignores x in open_file's mode string.
	fd := C.open(path.str, C.O_WRONLY | C.O_CREAT | C.O_EXCL | C.O_NOFOLLOW | C.O_CLOEXEC, 0o600)
	if fd < 0 { return error('cannot exclusively create private daemon log') }
	defer { C.close(fd) }
	before := os.lstat(root + '/qemu.log')!
	verify_daemon_log(root, before)!
	return before
}

fn launch_args(root string) []string {
	return ['-qmp', 'unix:' + root + '/qmp.sock,server=on,wait=off', '-machine', 'virt,gic-version=3',
		'-accel', 'hvf', '-cpu', 'host', '-m', '12288', '-smp', '4', '-object',
		'rng-random,filename=/dev/urandom,id=vinix-rng', '-device', 'virtio-rng-device', '-drive',
		'if=pflash,format=raw,readonly=on,file=' + firmware, '-drive',
		'if=pflash,format=raw,file=' + root + '/efivars.fd', '-drive',
		'format=raw,file=' + root + '/boot.img', '-device', 'virtio-keyboard-device', '-device',
		'virtio-tablet-device', '-device', 'ramfb', '-netdev', 'user,id=net0', '-device',
		'virtio-net-device,netdev=net0', '-object',
		'filter-dump,id=capture,netdev=net0,file=' + root + '/network.pcap', '-display', 'none',
		'-monitor', 'none', '-serial', 'file:' + root + '/serial.log', '-daemonize', '-D',
		root + '/qemu.log', '-pidfile',
		root + '/qemu.pid']
}

fn network_launch_args(root string, mode NetworkMode) []string {
	mut args := launch_args(root)
	args[args.index('-netdev') + 1] = mode.backend()
	return args
}

fn start(root string, mode NetworkMode) ! {
	start_admitted(root, mode, 0)!
}

fn start_admitted(root string, mode NetworkMode, foreign_pid int) ! {
	start_admitted_policy(root, mode, foreign_pid, .quarter_host_32g)!
}

fn start_admitted_policy(root string, mode NetworkMode, foreign_pid int, policy CoexistPolicy) ! {
	qmp_check(root)!
	fresh_launch(root)!
	mut initial := ForeignAdmission{}
	if foreign_pid != 0 {
		if mode != .user_default { return error('coexistence requires the unchanged default network') }
		initial = foreign_admission_policy(root, foreign_pid, policy)!
	} else {
		strict_guest_check(checked(['/bin/ps', '-axo', 'pid=,command='])!)!
	}
	stage := json2.decode[Stage](os.read_file(root + '/stage.json')!)!
	if stage.format != 1 || hash(root + '/boot.img')! != stage.staged_boot_sha256
		|| hash(root + '/efivars.fd')! != stage.staged_efivars_sha256 {
		return error('staged media changed')
	}
	mut argv := [qemu]
	argv << network_launch_args(root, mode)
	qemu_sha := hash(qemu)!
	firmware_sha := hash(firmware)!
	runner_sha := hash(os.executable())!
	mut final := ForeignAdmission{}
	if foreign_pid != 0 {
		final = foreign_admission_policy(root, foreign_pid, policy)!
		same_foreign(initial, final)!
	}
	log_before := create_daemon_log(root)!
	os.write_file(root + '/run-source.v', source)!
	os.cp(os.executable(), root + '/runner')!
	mut launch := {
		'argv':                 json2.Any(argv)
		'network':              mode.evidence()
		'started_utc':          json2.Any(time.utc().str())
		'stage_sha256':         json2.Any(hash(root + '/stage.json')!)
		'qemu_sha256':          json2.Any(qemu_sha)
		'firmware_sha256':      json2.Any(firmware_sha)
		'runner_sha256':        json2.Any(runner_sha)
		'runner_source_sha256': json2.Any(sha256.sum(source.bytes()).hex())
		'daemon_stderr_path':   json2.Any(root + '/qemu.log')
		'daemon_stderr_before': json2.decode[json2.Any](json2.encode(log_before))!
		'daemon_stderr_scope':  json2.Any('QEMU -D retains normal daemon stderr; no -d tracing; exit cause requires observed evidence.')
		'scope':                json2.Any('Separate credential-free real-engine diagnostic; no Google authentication proof.')
	}
	if foreign_pid != 0 {
		launch['coexistence'] = json2.decode[json2.Any](json2.encode({
			'initial': json2.decode[json2.Any](json2.encode(initial))!
			'final': json2.decode[json2.Any](json2.encode(final))!
			'scope': json2.Any('Read-only admission snapshots; foreign guest is never signalled or modified. Not continuous resource monitoring.')
			'limits': json2.Any(policy.limits())
		}))!
	}
	write_json(root + '/launch.json', json2.Any(launch))!
	result := execute(argv)!
	write_json(root + '/launch-result.json', json2.decode[json2.Any](json2.encode(result))!)!
	if result.code != 0 { return error('QEMU launch failed: ' + result.stderr) }
	verify_daemon_log(root, log_before)!
	pid := strconv.atoi(os.read_file(root + '/qemu.pid')!.trim_space())!
	write_json(root + '/ownership.json', json2.decode[json2.Any](json2.encode(identity(pid)!))!)!
	println('BROWSER-RUN STARTED pid=' + owned(root)!.pid.str() + ' state=' + root)
}

fn stopped(root string) !bool {
	return process_gone(recorded_owner(root)!)
}

// Observe an already absent guest without attributing an exit status or signal.
// A requested stop has its separate reconciliation path and receipt chain.
fn observe_gone(root string) ! {
	for name in ['stop.json', 'gone.json'] {
		if os.exists(root + '/' + name) || os.is_link(root + '/' + name) {
			return error('read-only disappearance observation requires no ' + name)
		}
	}
	ownership_sha := hash(root + '/ownership.json')!
	owner := recorded_owner(root)!
	if !process_gone(owner)! { return error('owned guest remains live; no signal sent') }
	if hash(root + '/ownership.json')! != ownership_sha {
		return error('guest ownership changed during disappearance observation')
	}
	write_json(root + '/gone.json', json2.decode[json2.Any](json2.encode({
		'pid':              json2.Any(owner.pid)
		'checked_utc':      json2.Any(time.utc().str())
		'check':            json2.Any('one ps snapshot returned exit1 with empty stdout and stderr for recorded owned PID')
		'ownership_sha256': json2.Any(ownership_sha)
		'stop_requested':   json2.Any(false)
		'exit_status':      json2.Any('unknown')
		'cause':            json2.Any('unobserved; this command sent no signal')
	}))!)!
	println('BROWSER-RUN OBSERVED-GONE pid=' + owner.pid.str() + ' exit=unknown cause=unobserved')
}

fn observed_receipt(root string, owner Ownership, ownership_sha string) !string {
	for name in ['ownership.json', 'gone.json'] {
		if os.lstat(root + '/' + name)!.get_filetype() != .regular {
			return error('regular non-symlink receipt required for cleanup: ' + name)
		}
	}
	if os.exists(root + '/stop.json') || os.is_link(root + '/stop.json') {
		return error('cleanup-gone requires an unrequested disappearance')
	}
	text := os.read_file(root + '/gone.json')!
	fields := json2.decode[map[string]json2.Any](text)!
	mut names := fields.keys()
	names.sort()
	if names != ['cause', 'check', 'checked_utc', 'exit_status', 'ownership_sha256', 'pid',
		'stop_requested']
		|| json2.encode(fields['pid']!) != owner.pid.str()
		|| fields['ownership_sha256']!.str() != ownership_sha
		|| fields['checked_utc']!.str() == ''
		|| json2.encode(fields['stop_requested']!) != 'false'
		|| json2.encode(fields['exit_status']!) != '"unknown"'
		|| json2.encode(fields['cause']!) != '"unobserved; this command sent no signal"'
		|| json2.encode(fields['check']!) != '"one ps snapshot returned exit1 with empty stdout and stderr for recorded owned PID"' {
		return error('exact observed-absence receipt required for cleanup')
	}
	return sha256.sum(text.bytes()).hex()
}

fn refused_socket(path string) ! {
	addresses := net.resolve_addrs(path, .unix, .tcp)!
	if addresses.len != 1 { return error('one exact Unix socket address required') }
	address := addresses[0]
	fd := C.socket(C.AF_UNIX, C.SOCK_STREAM, 0)
	if fd < 0 { return error('cannot create cleanup socket probe') }
	defer { C.close(fd) }
	net.set_blocking(fd, false)!
	if C.connect(fd, voidptr(&address), address.len()) == 0 {
		return error('QMP socket has an active listener; refusing cleanup')
	}
	if net.error_code() != C.ECONNREFUSED {
		return error('QMP socket probe did not return ECONNREFUSED; refusing cleanup')
	}
}

// Remove only the exact stale socket of an already observed absent guest.
// A separate request survives failures; no signal or exit status is inferred.
fn cleanup_gone(root string) ! {
	for name in ['qmp-cleanup-request.json', 'qmp-cleanup.json', 'qmp-cleanup-source.v',
		'qmp-cleanup-runner'] {
		if os.exists(root + '/' + name) || os.is_link(root + '/' + name) {
			return error('cleanup evidence already exists: ' + name)
		}
	}
	ownership_sha := hash(root + '/ownership.json')!
	owner := recorded_owner(root)!
	gone_sha := observed_receipt(root, owner, ownership_sha)!
	if !process_gone(owner)! { return error('owned guest remains live; no signal sent') }
	path := root + '/qmp.sock'
	before := os.lstat(path)!
	if before.get_filetype() != .socket || before.uid != u32(os.geteuid()) {
		return error('exact non-symlink socket owned by this user required')
	}
	refused_socket(path)!
	os.write_file(root + '/qmp-cleanup-source.v', source)!
	os.cp(os.executable(), root + '/qmp-cleanup-runner')!
	write_json(root + '/qmp-cleanup-request.json', json2.Any({
		'action': json2.Any('unlink exact stale QMP socket after observed guest disappearance')
		'path': json2.Any(path)
		'path_kind': json2.Any('socket; lstat did not follow a symlink')
		'socket_before': json2.decode[json2.Any](json2.encode(before))!
		'pid': json2.Any(owner.pid)
		'ownership_sha256': json2.Any(ownership_sha)
		'gone_sha256': json2.Any(gone_sha)
		'socket_check': json2.Any('nonblocking AF_UNIX connect returned ECONNREFUSED')
		'requested_utc': json2.Any(time.utc().str())
		'runner_sha256': json2.Any(hash(root + '/qmp-cleanup-runner')!)
		'runner_source_sha256': json2.Any(hash(root + '/qmp-cleanup-source.v')!)
		'signal_sent': json2.Any(false)
	}))!
	if !process_gone(owner)! || hash(root + '/ownership.json')! != ownership_sha
		|| observed_receipt(root, owner, ownership_sha)! != gone_sha {
		return error('guest ownership or disappearance changed before cleanup')
	}
	refused_socket(path)!
	current := os.lstat(path)!
	if current != before { return error('QMP socket identity changed before cleanup') }
	os.rm(path)!
	if os.exists(path) || os.is_link(path) { return error('QMP socket remains after cleanup') }
	if hash(root + '/ownership.json')! != ownership_sha
		|| observed_receipt(root, owner, ownership_sha)! != gone_sha {
		return error('guest ownership or disappearance changed during cleanup')
	}
	write_json(root + '/qmp-cleanup.json', json2.Any({
		'path': json2.Any(path)
		'removed': json2.Any(true)
		'completed_utc': json2.Any(time.utc().str())
		'request_sha256': json2.Any(hash(root + '/qmp-cleanup-request.json')!)
		'ownership_sha256': json2.Any(ownership_sha)
		'gone_sha256': json2.Any(gone_sha)
		'signal_sent': json2.Any(false)
	}))!
	println('BROWSER-RUN CLEANED-GONE-QMP pid=' + owner.pid.str() + ' path=' + path + ' signal=none')
}

fn cleanup_self_test(root string) ! {
	owner_text := os.read_file(root + '/ownership.json')!
	gone_text := os.read_file(root + '/gone.json')!
	path := root + '/qmp.sock'
	if _ := cleanup_gone(root) { return error('missing QMP socket accepted') }
	os.write_file(path, 'regular evidence')!
	if _ := cleanup_gone(root) { return error('regular QMP path accepted') }
	if os.read_file(path)! != 'regular evidence' { return error('regular QMP evidence changed') }
	os.rm(path)!
	os.mkdir(path)!
	if _ := cleanup_gone(root) { return error('directory QMP path accepted') }
	if !os.is_dir(path) { return error('directory QMP evidence changed') }
	os.rmdir(path)!
	mut listener := unix.listen_stream(path)!
	if _ := cleanup_gone(root) { return error('active replacement QMP listener accepted') }
	if os.lstat(path)!.get_filetype() != .socket { return error('active QMP socket changed') }
	// Drain the rejected connection before closing this test listener.
	mut accepted := listener.accept()!
	accepted.close()!
	unix.shutdown(listener.sock.handle)
	if C.close(listener.sock.handle) != 0 { return error('cannot close test QMP listener') }
	os.mv(path, root + '/actual.sock')!
	os.symlink(root + '/actual.sock', path)!
	if _ := cleanup_gone(root) { return error('QMP symlink accepted') }
	if !os.is_link(path) || os.lstat(root + '/actual.sock')!.get_filetype() != .socket {
		return error('symlink QMP evidence changed')
	}
	os.rm(path)!
	os.mv(root + '/actual.sock', path)!
	mut live_owner := json2.decode[Ownership](owner_text)!
	live_identity := identity(os.getpid())!
	live_owner = Ownership{ pid: live_identity.pid, started: live_identity.started, command: live_owner.command }
	os.write_file(root + '/ownership.json', json2.encode(live_owner))!
	mut live_gone := json2.decode[map[string]json2.Any](gone_text)!
	live_gone['pid'] = live_owner.pid
	live_gone['ownership_sha256'] = hash(root + '/ownership.json')!
	os.write_file(root + '/gone.json', json2.encode(live_gone))!
	if _ := cleanup_gone(root) { return error('reused live PID accepted for QMP cleanup') }
	if os.lstat(path)!.get_filetype() != .socket || os.exists(root + '/qmp-cleanup-request.json') {
		return error('live PID caused cleanup mutation')
	}
	os.write_file(root + '/ownership.json', owner_text)!
	os.write_file(root + '/gone.json', gone_text)!
	for action in ['wrong-owner', 'wrong-pid', 'missing-false', 'signal-claim', 'true-stop'] {
		mut fields := json2.decode[map[string]json2.Any](gone_text)!
		match action {
			'wrong-owner' { fields['ownership_sha256'] = '0'.repeat(64) }
			'wrong-pid' { fields['pid'] = os.getpid() }
			'missing-false' { fields.delete('stop_requested') }
			'signal-claim' { fields['signal'] = 'SIGTERM' }
			'true-stop' { fields['stop_requested'] = true }
			else {}
		}
		os.write_file(root + '/gone.json', json2.encode(fields))!
		if _ := cleanup_gone(root) { return error('QMP cleanup accepted ' + action) }
		if os.lstat(path)!.get_filetype() != .socket || os.exists(root + '/qmp-cleanup-request.json') {
			return error('invalid disappearance caused cleanup mutation')
		}
	}
	os.write_file(root + '/gone.json', gone_text)!
	for name in ['ownership.json', 'gone.json'] {
		os.mv(root + '/' + name, root + '/' + name + '.saved')!
		os.symlink(root + '/' + name + '.saved', root + '/' + name)!
		if _ := cleanup_gone(root) { return error('symlink cleanup receipt accepted') }
		os.rm(root + '/' + name)!
		os.mv(root + '/' + name + '.saved', root + '/' + name)!
	}
	os.symlink(root + '/absent-stop', root + '/stop.json')!
	if _ := cleanup_gone(root) { return error('stop symlink accepted for cleanup') }
	os.rm(root + '/stop.json')!
	os.write_file(root + '/qmp-cleanup-request.json', 'previous request')!
	if _ := cleanup_gone(root) { return error('previous cleanup request accepted') }
	if os.read_file(root + '/qmp-cleanup-request.json')! != 'previous request' {
		return error('previous cleanup request changed')
	}
	os.rm(root + '/qmp-cleanup-request.json')!
	os.symlink(root + '/absent-cleanup', root + '/qmp-cleanup.json')!
	if _ := cleanup_gone(root) { return error('cleanup receipt symlink accepted') }
	os.rm(root + '/qmp-cleanup.json')!
	if os.read_file(root + '/ownership.json')! != owner_text || os.read_file(root + '/gone.json')! != gone_text {
		return error('rejected cleanup changed original ownership or disappearance')
	}
	os.write_file(root + '/retained-serial.log', 'unchanged UART evidence\x00exact')!
	before := os.lstat(path)!
	cleanup_gone(root)!
	if os.exists(path) || os.is_link(path) || os.read_file(root + '/ownership.json')! != owner_text
		|| os.read_file(root + '/gone.json')! != gone_text
		|| os.read_file(root + '/retained-serial.log')! != 'unchanged UART evidence\x00exact' {
		return error('cleanup failed to remove only the stale socket')
	}
	request := json2.decode[map[string]json2.Any](os.read_file(root + '/qmp-cleanup-request.json')!)!
	if request['path']!.str() != path || request['signal_sent']!.bool()
		|| request['ownership_sha256']!.str() != hash(root + '/ownership.json')!
		|| request['gone_sha256']!.str() != hash(root + '/gone.json')!
		|| json2.decode[os.Stat](json2.encode(request['socket_before']!))! != before {
		return error('cleanup request receipt differs from observed socket or ownership')
	}
	completion := json2.decode[map[string]json2.Any](os.read_file(root + '/qmp-cleanup.json')!)!
	if !completion['removed']!.bool() || completion['signal_sent']!.bool()
		|| completion['request_sha256']!.str() != hash(root + '/qmp-cleanup-request.json')! {
		return error('cleanup completion receipt differs')
	}
	mut files := os.ls(root)!
	files.sort()
	if files != ['gone.json', 'ownership.json', 'qmp-cleanup-request.json',
		'qmp-cleanup-runner', 'qmp-cleanup-source.v', 'qmp-cleanup.json', 'retained-serial.log'] {
		return error('cleanup changed the exact evidence file allowlist')
	}
	if _ := cleanup_gone(root) { return error('repeated cleanup accepted') }
}

fn reconcile_stop(root string) ! {
	owner := recorded_owner(root)!
	stop_receipt := json2.decode[StopReceipt](os.read_file(root + '/stop.json')!)!
	if stop_receipt.pid != owner.pid || stop_receipt.signal != 'SIGTERM'
		|| stop_receipt.requested_utc == '' {
		return error('stop receipt differs from recorded guest')
	}
	if os.exists(root + '/gone.json') || os.is_link(root + '/gone.json') {
		return error('disappearance receipt already exists')
	}
	deadline := time.sys_mono_now() + 5 * time.second
	for {
		if stopped(root)! {
			write_json(root + '/gone.json', json2.decode[json2.Any](json2.encode({
				'pid':              json2.Any(owner.pid)
				'checked_utc':      json2.Any(time.utc().str())
				'check':            json2.Any('one ps snapshot returned exit1 with empty stdout and stderr for recorded owned PID')
				'ownership_sha256': json2.Any(hash(root + '/ownership.json')!)
				'stop_sha256':      json2.Any(hash(root + '/stop.json')!)
			}))!)!
			println('BROWSER-RUN STOPPED pid=' + owner.pid.str())
			return
		}
		if time.sys_mono_now() >= deadline {
			return error('owned guest remains after SIGTERM; no further signal sent')
		}
		time.sleep(100 * time.millisecond)
	}
}

fn stop(root string) ! {
	if os.exists(root + '/stop.json') || os.is_link(root + '/stop.json') {
		return error('stop already requested; reconcile-stop sends no additional signal')
	}
	owner := owned(root)!
	if C.kill(owner.pid, C.SIGTERM) != 0 { return error('could not signal owned guest') }
	write_json(root + '/stop.json', json2.decode[json2.Any](json2.encode(StopReceipt{
		pid:           owner.pid
		signal:        'SIGTERM'
		requested_utc: time.utc().str()
	}))!)!
	reconcile_stop(root)!
}

fn daemon_log_self_test(root string) ! {
	fresh_launch(root)!
	if _ := fresh_launch(root + '%d') { return error('QEMU log template accepted') }
	if _ := create_daemon_log(root + '%d') { return error('QEMU log template created') }
	if _ := verify_daemon_log(root, os.Stat{}) { return error('missing daemon log accepted') }
	args := launch_args(root)
	assert args.filter(it == '-D').len == 1 && '-d' !in args
	assert args[args.index('-D') + 1] == root + '/qemu.log'
	assert '-daemonize' in args
	assert args[0..2] == ['-qmp', 'unix:' + root + '/qmp.sock,server=on,wait=off']
	assert args[args.len - 2..] == ['-pidfile', root + '/qemu.pid']
	before := create_daemon_log(root)!
	assert before.size == 0
	if _ := fresh_launch(root) { return error('existing daemon log accepted by launch') }
	if _ := create_daemon_log(root) { return error('existing daemon log overwritten') }
	// A child reopens the production -D destination and redirects real fd 2,
	// matching the reviewed QEMU daemon code without starting a guest.
	fixture := execute([os.executable(), '--self-test-daemon-log', ...args])!
	assert fixture.code == 0 && fixture.stdout == '' && fixture.stderr == ''
	assert os.read_file(root + '/qemu.log')! == 'BROWSER-RUN DAEMON-STDERR-FIXTURE\n'
	verify_daemon_log(root, before)!
	os.chmod(root + '/qemu.log', 0o644)!
	if _ := verify_daemon_log(root, before) { return error('public daemon log accepted') }
	os.chmod(root + '/qemu.log', 0o600)!
	os.link(root + '/qemu.log', root + '/log-hardlink')!
	if _ := verify_daemon_log(root, before) { return error('hard-linked daemon log accepted') }
	os.rm(root + '/log-hardlink')!
	os.mv(root + '/qemu.log', root + '/log-original')!
	create_daemon_log(root)!
	if _ := verify_daemon_log(root, before) { return error('replacement daemon log accepted') }
	os.rm(root + '/qemu.log')!
	os.symlink(root + '/absent-log', root + '/qemu.log')!
	if _ := fresh_launch(root) { return error('dangling daemon log symlink accepted') }
	if _ := create_daemon_log(root) { return error('daemon log symlink overwritten') }
	if _ := verify_daemon_log(root, before) { return error('daemon log symlink accepted') }
	os.rm(root + '/qemu.log')!
	os.mkdir(root + '/qemu.log')!
	if _ := verify_daemon_log(root, before) { return error('daemon log directory accepted') }
	os.rmdir(root + '/qemu.log')!
	os.mv(root + '/log-original', root + '/qemu.log')!
	verify_daemon_log(root, before)!
	os.rm(root + '/qemu.log')!
	if _ := verify_daemon_log(root, before) { return error('removed daemon log accepted') }
	println('DAEMON-STDERR SELF-TEST PASS literal-exact-argv no-debug-tracing exclusive-private-file real-fd2-destination missing-existing-symlink-directory-hardlink-permissions-replacement-rejection')
}

fn network_self_test() ! {
	root := '/tmp/browser-network-profile'
	baseline := launch_args(root)
	standard := network_launch_args(root, .user_default)
	ipv4 := network_launch_args(root, .ipv4_only)
	assert standard == baseline
	assert baseline.filter(it == '-netdev').len == 1
	position := baseline.index('-netdev') + 1
	assert baseline[position] == 'user,id=net0'
	assert ipv4.len == baseline.len && ipv4[position] == 'user,id=net0,ipv6=off'
	for i, arg in baseline {
		if i != position { assert ipv4[i] == arg }
	}
	for mode in [NetworkMode.user_default, NetworkMode.ipv4_only] {
		recorded := json2.decode[map[string]string](json2.encode(mode.evidence()))!
		assert recorded.len == 2
		assert recorded['mode']! == if mode == .ipv4_only { 'ipv4-only' } else { 'user-default' }
		assert recorded['backend']! == network_launch_args(root, mode)[position]
	}
	println('NETWORK-PROFILE SELF-TEST PASS unchanged-default exact-ipv4-only-argv explicit-network-provenance')
}

fn coexist_self_test(temporary_root string) ! {
	root := os.real_path(temporary_root)
	defer {
		os.rmdir_all(root + '/owned-media') or {}
		for name in ['foreign-disk', 'readonly-firmware', 'foreign-alias', 'foreign-hardlink'] { os.rm(root + '/' + name) or {} }
	}
	command := '/foreign/qemu-system-aarch64 -machine virt,accel=hvf,highmem=on -cpu host -m 16384 -smp 4 -drive if=virtio,file=/foreign/disk,format=qcow2 -device virtio-net-pci,netdev=net0 -display none -monitor none -daemonize'
	memory, cpus := foreign_resources(command)!
	assert memory == 16384 && cpus == 4
	strict_guest_check('12 /bin/true')!
	if _ := strict_guest_check('99 ' + command) { return error('legacy strict guest check weakened') }
	assert qemu_inventory('12 /bin/true\n99 /foreign/qemu-system-aarch64')! == [99]
	assert qemu_inventory('99 /foreign/qemu-system-aarch64\n100 /foreign/qemu-system-x86_64')! == [99, 100]
	if _ := qemu_inventory('99 /foreign/qemu-system-aarch64\n99 /foreign/qemu-system-aarch64') { return error('duplicate inventory PID accepted') }
	mut refusals := 1
	for suffix in [' -m 1', ' -smp 1', ' -m1', ' -smp1', ' -object memory-backend-ram,id=m,size=64G',
		' -numa node,memdev=m', ' -mem-path /tmp/m', ' -mem-prealloc', ' -readconfig /tmp/c',
		' -qmp unix:/foreign/qmp', ' -device pc-dimm,memdev=m', ' -device virtio-mem-pci,memdev=m',
		' -machine virt', ' -daemonize', ' disk.img', ' -device virtio-gpu,hostmem=128G',
		' -device unknown', ' -drive if=virtio,file=/foreign/disk,format=qcow2,l2-cache-size=512G',
		' -drive if=virtio,file=/foreign/disk,format=qcow2,cache-size=512G',
		' -drive if=virtio,file=/foreign/disk,file=/other,format=qcow2',
		' -drive if=virtio,file=relative,format=qcow2', ' -display cocoa', ' -cpu max'] {
		if _, _ := foreign_resources(command + suffix) { return error('unsafe foreign option accepted: ' + suffix) }
		refusals++
	}
	for value in ['', '0', '01', '-1', '+1', '1G', '1.5', 'size=16384', '16384,slots=2,maxmem=64G', '18446744073709551616'] {
		if _, _ := foreign_resources(command.replace('-m 16384', '-m ' + value)) { return error('unsafe foreign memory accepted: ' + value) }
		if _, _ := foreign_resources(command.replace('-smp 4', '-smp ' + value)) { return error('unsafe foreign CPU count accepted: ' + value) }
		refusals += 2
	}
	for value in [command.replace(' -m 16384', ''), command.replace(' -smp 4', ''),
		command.replace(' -machine virt,accel=hvf,highmem=on', ''), command.replace(' -monitor none', ' -monitor stdio'),
		command.replace(' -machine virt,accel=hvf,highmem=on', ' -machine virt,memory-backend=m'),
		command.replace(' -cpu host', ' -cpu "host"'), command.replace(' -cpu host', '  -cpu host')] {
		if _, _ := foreign_resources(value) { return error('unsupported foreign grammar accepted') }
		refusals++
	}
	gi := u64(1024) * 1024 * 1024
	admit_resources(16384, 4, 128 * gi, 18, 1, gi)!
	admit_resources(20480, 14, 128 * gi, 18, 1, gi)!
	for values in [[u64(20481), 4, 128 * gi, 18, 1, gi], [u64(16384), 4, 112 * gi - 1, 18, 1, gi],
		[u64(16384), 15, 128 * gi, 18, 1, gi], [u64(16384), 4, 128 * gi, 18, 0, gi],
		[u64(16384), 4, 128 * gi, 18, 2, gi], [u64(16384), 4, 128 * gi, 18, 4, gi],
		[u64(16384), 4, 128 * gi, 18, 1, gi - 1], [u64(0), 4, 128 * gi, 18, 1, gi],
		[u64(16384), 0, 128 * gi, 18, 1, gi], [u64(16384), 4, 128 * gi, 0, 1, gi]] {
		admit_resources(values[0], values[1], values[2], values[3], values[4], values[5]) or { refusals++; continue }
		return error('unsafe host resource boundary accepted')
	}
	before := ForeignAdmission{owner: Ownership{pid: 99, command: command, started: 'fixed'}, executable: '/foreign/qemu-system-aarch64', executable_sha256: 'fixed', memory_mib: memory, cpus: cpus}
	same_foreign(before, before)!
	for changed in [ForeignAdmission{...before, owner: Ownership{...before.owner, pid: 100}},
		ForeignAdmission{...before, owner: Ownership{...before.owner, started: 'changed'}},
		ForeignAdmission{...before, owner: Ownership{...before.owner, command: command + ' changed'}},
		ForeignAdmission{...before, executable: '/changed'}, ForeignAdmission{...before, executable_sha256: 'changed'},
		ForeignAdmission{...before, memory_mib: memory + 1}, ForeignAdmission{...before, cpus: cpus + 1},
		ForeignAdmission{...before, referenced_paths: {'/foreign/disk': ForeignResourceIdentity{path: '/changed'}}}] {
		if _ := same_foreign(before, changed) { return error('foreign identity mutation accepted') }
		refusals++
	}
	os.mkdir(root + '/owned-media')!
	os.write_file(root + '/owned-media/boot.img', 'owned')!
	os.write_file(root + '/foreign-disk', 'foreign')!
	reference := foreign_path(root + '/foreign-disk', root + '/owned-media', false)!
	assert reference.path == root + '/foreign-disk'
	os.write_file(root + '/foreign-disk', 'ordinary mutable foreign contents changed')!
	assert foreign_path(root + '/foreign-disk', root + '/owned-media', false)! == reference
	resource_before := ForeignAdmission{...before, referenced_paths: {'disk': reference}}
	for changed in [ForeignResourceIdentity{...reference, path: '/changed'}, ForeignResourceIdentity{...reference, dev: reference.dev + 1},
		ForeignResourceIdentity{...reference, inode: reference.inode + 1}, ForeignResourceIdentity{...reference, mode: reference.mode ^ 0o002},
		ForeignResourceIdentity{...reference, nlink: reference.nlink + 1}] {
		if _ := same_foreign(resource_before, ForeignAdmission{...resource_before, referenced_paths: {'disk': changed}}) { return error('foreign resource identity mutation accepted') }
		refusals++
	}
	os.symlink(root + '/foreign-disk', root + '/readonly-firmware')!
	assert foreign_path(root + '/readonly-firmware', root + '/owned-media', true)!.path == root + '/foreign-disk'
	os.symlink(root + '/owned-media/boot.img', root + '/foreign-alias')!
	os.link(root + '/owned-media/boot.img', root + '/foreign-hardlink')!
	for path in ['relative', root + '/foreign-alias', root + '/foreign-hardlink', root + '/owned-media/boot.img', root + '/absent', root + '/readonly-firmware'] {
		if _ := foreign_path(path, root + '/owned-media', false) { return error('unsafe foreign resource path accepted') }
		refusals++
	}
	if _ := foreign_path(root + '/foreign-hardlink', root + '/owned-media', true) { return error('readonly hardlink alias accepted') }
	df := 'Filesystem 1024-blocks Used Available Capacity Mounted on\n/dev/disk1 4000000 2000000 1048576 66% /System/Volumes/Data\n'
	assert available_disk_bytes(df)! == gi
	assert available_disk_bytes(df.replace('1048576', '0'))! == 0
	for changed in [df.replace('1048576', '18446744073709551615'), df.replace('1048576', '-1'), df.replace('1048576', '4000001'),
		df.replace('66%', '101%'), df.replace('1024-blocks', 'unexpected'), df + '/dev/disk2 1 1 0 100% /tmp\n'] {
		if _ := available_disk_bytes(changed) { return error('malformed disk report accepted') }
		refusals++
	}
	println('COEXISTENCE SELF-TEST PASS refusals=' + refusals.str() + ' unchanged-default explicit-single-foreign canonical-argv bounded-host-resources identity-recheck')
}

fn coexist_64g_self_test(temporary_root string) ! {
	root := os.real_path(temporary_root)
	policy := CoexistPolicy.half_host_64g
	gi := u64(1024) * 1024 * 1024
	command := '/foreign/qemu-system-aarch64 -machine virt,accel=hvf,highmem=on -cpu host -m 32768 -smp 8 -drive if=virtio,file=/foreign/disk,format=qcow2,discard=unmap,detect-zeroes=unmap -device virtio-net-pci,netdev=net0 -display none -monitor none -qmp unix:/tmp/foreign.sock,server=on,wait=off -daemonize'
	memory, cpus := foreign_resources_policy(command, policy)!
	assert memory == 32768 && cpus == 8
	mut refusals := 0
	for legacy in [command, command.replace(' -qmp unix:/tmp/foreign.sock,server=on,wait=off', ''),
		command.replace(',discard=unmap,detect-zeroes=unmap', '')] {
		if _, _ := foreign_resources(legacy) { return error('legacy parser accepted 64GiB extensions') }
		refusals++
	}
	if _ := admit_resources(memory, cpus, 128 * gi, 18, 1, gi) { return error('legacy RAM cap changed') }
	refusals++
	admit_resources_policy(memory, cpus, 128 * gi, 18, 1, gi, policy)!
	admit_resources_policy(53248, 14, 128 * gi, 18, 1, gi, policy)!
	for values in [[u64(53249), 8, 128 * gi, 18, 1, gi], [u64(32768), 8, 128 * gi - 1, 18, 1, gi],
		[u64(32768), 8, 128 * gi, 11, 1, gi], [u64(32768), 15, 128 * gi, 18, 1, gi],
		[u64(32768), 8, 128 * gi, 18, 0, gi], [u64(32768), 8, 128 * gi, 18, 2, gi],
		[u64(32768), 8, 128 * gi, 18, 4, gi], [u64(32768), 8, 128 * gi, 18, 1, gi - 1],
		[u64(0), 8, 128 * gi, 18, 1, gi], [u64(32768), 0, 128 * gi, 18, 1, gi],
		[u64(32768), 8, 128 * gi, 0, 1, gi], [u64(32768), 8, 128 * gi, 1025, 1, gi],
		[u64(18446744073709551615), 8, 128 * gi, 18, 1, gi],
		[u64(32768), 18446744073709551615, 128 * gi, 18, 1, gi]] {
		admit_resources_policy(values[0], values[1], values[2], values[3], values[4], values[5], policy) or { refusals++; continue }
		return error('64GiB resource boundary accepted')
	}
	for changed in [command + ' -qmp unix:/tmp/other.sock,server=on,wait=off',
		command.replace('discard=unmap', 'discard=ignore'), command.replace('detect-zeroes=unmap', 'detect-zeroes=on'),
		command.replace('discard=unmap', 'discard=unmap,discard=unmap'),
		command.replace('if=virtio', 'if=pflash'), command.replace('format=qcow2', 'format=raw'),
		command.replace('discard=unmap', 'readonly=on,discard=unmap'),
		command.replace('discard=unmap', 'cache-size=64G'), command + ' -object memory-backend-ram,id=m,size=64G',
		command + ' -device pc-dimm,memdev=m', command + ' -m 1', command + ' -smp 1'] {
		if _, _ := foreign_resources_policy(changed, policy) { return error('unsafe 64GiB grammar accepted') }
		refusals++
	}
	for value in ['tcp:127.0.0.1:4444,server=on,wait=off', 'unix:relative,server=on,wait=off',
		'unix:/tmp/sock', 'unix:/tmp/sock,server=on', 'unix:/tmp/sock,server=on,wait=on',
		'unix:/tmp/sock,wait=off,server=on', 'unix:/tmp/sock,server=on,wait=off,nowait',
		'unix:/tmp/sock,server=on,server=on,wait=off', 'unix:/tmp/../sock,server=on,wait=off',
		'unix:/' + 's'.repeat(103) + ',server=on,wait=off'] {
		if _, _ := foreign_resources_policy(command.replace('unix:/tmp/foreign.sock,server=on,wait=off', value), policy) {
			return error('unsupported QMP configuration accepted')
		}
		refusals++
	}
	before := ForeignAdmission{budget_policy: policy.str(), aggregate_limit_mib: policy.limit_mib(), host_memory_divisor: policy.host_divisor()}
	for changed in [ForeignAdmission{...before, budget_policy: CoexistPolicy.quarter_host_32g.str()},
		ForeignAdmission{...before, aggregate_limit_mib: 32768}, ForeignAdmission{...before, host_memory_divisor: 4}] {
		if _ := same_foreign(before, changed) { return error('mixed admission policies accepted') }
		refusals++
	}
	owned_root := root + '/socket-owned'
	path := root + '/foreign.sock'
	os.mkdir(owned_root)!
	defer {
		for name in ['foreign.sock', 'foreign-link.sock', 'foreign-parent', 'foreign-regular'] { os.rm(root + '/' + name) or {} }
		os.rmdir_all(owned_root) or {}
	}
	mut listener := unix.listen_stream(path)!
	defer {
		unix.shutdown(listener.sock.handle)
		C.close(listener.sock.handle)
	}
	reference := foreign_socket(path, owned_root)!
	assert reference.path == path
	// An alias of the parent is safe for read-only identity inspection; the
	// endpoint itself cannot be a symlink. No connection to the listener occurs.
	os.symlink(root, root + '/foreign-parent')!
	assert foreign_socket(root + '/foreign-parent/foreign.sock', owned_root)! == reference
	if _ := foreign_paths_policy(command.replace('/tmp/foreign.sock', path).replace('/foreign/disk', root + '/foreign-regular'), owned_root, policy) {
		return error('missing foreign drive skipped during QMP admission')
	}
	refusals++
	os.write_file(root + '/foreign-regular', 'not a socket')!
	full_paths := foreign_paths_policy(command.replace('/tmp/foreign.sock', path).replace('/foreign/disk', root + '/foreign-regular'), owned_root, policy)!
	assert full_paths[path]! == reference && full_paths.len == 2
	os.symlink(path, root + '/foreign-link.sock')!
	for bad in ['relative', root + '/foreign-link.sock', root + '/foreign-regular', root + '/missing-parent/sock',
		root + '/foreign-regular/sock', owned_root, repo + '/qmp.sock'] {
		if _ := foreign_socket(bad, owned_root) { return error('unsafe foreign socket accepted') }
		refusals++
	}
	mut owned_listener := unix.listen_stream(owned_root + '/qmp.sock')!
	defer {
		unix.shutdown(owned_listener.sock.handle)
		C.close(owned_listener.sock.handle)
	}
	if _ := foreign_socket(owned_root + '/qmp.sock', owned_root) { return error('owned socket accepted') }
	refusals++
	socket_before := ForeignAdmission{...before, referenced_paths: {path: reference}}
	for changed in [ForeignResourceIdentity{...reference, path: '/changed'}, ForeignResourceIdentity{...reference, dev: reference.dev + 1},
		ForeignResourceIdentity{...reference, inode: reference.inode + 1}, ForeignResourceIdentity{...reference, mode: reference.mode ^ 0o002},
		ForeignResourceIdentity{...reference, nlink: reference.nlink + 1}, ForeignResourceIdentity{...reference, uid: reference.uid + 1},
		ForeignResourceIdentity{...reference, absent: true}] {
		if _ := same_foreign(socket_before, ForeignAdmission{...socket_before, referenced_paths: {path: changed}}) {
			return error('changed foreign socket identity accepted')
		}
		refusals++
	}
	missing_path := root + '/unlinked.sock'
	missing := foreign_socket(missing_path, owned_root)!
	assert missing.absent && missing.path == missing_path
	assert missing.socket_parent == reference.socket_parent
	assert foreign_socket(root + '/foreign-parent/unlinked.sock', owned_root)! == missing
	missing_before := ForeignAdmission{...before, referenced_paths: {missing_path: missing}}
	for changed_parent in [ForeignDirectoryIdentity{...missing.socket_parent, path: '/changed'},
		ForeignDirectoryIdentity{...missing.socket_parent, dev: missing.socket_parent.dev + 1},
		ForeignDirectoryIdentity{...missing.socket_parent, inode: missing.socket_parent.inode + 1},
		ForeignDirectoryIdentity{...missing.socket_parent, mode: missing.socket_parent.mode ^ 0o002},
		ForeignDirectoryIdentity{...missing.socket_parent, uid: missing.socket_parent.uid + 1}] {
		if _ := same_foreign(missing_before, ForeignAdmission{...missing_before, referenced_paths: {
			missing_path: ForeignResourceIdentity{...missing, socket_parent: changed_parent}
		}}) { return error('changed absent socket parent accepted') }
		refusals++
	}
	os.symlink(root + '/does-not-exist', missing_path)!
	if _ := foreign_socket(missing_path, owned_root) { return error('dangling QMP symlink treated as absent') }
	os.rm(missing_path)!
	refusals++
	mut appeared := unix.listen_stream(missing_path)!
	present := foreign_socket(missing_path, owned_root)!
	unix.shutdown(appeared.sock.handle)
	C.close(appeared.sock.handle)
	os.rm(missing_path)!
	if _ := same_foreign(missing_before, ForeignAdmission{...missing_before, referenced_paths: {missing_path: present}}) {
		return error('socket appearance during admission accepted')
	}
	refusals++
	if _ := same_foreign(ForeignAdmission{...before, referenced_paths: {missing_path: present}}, missing_before) {
		return error('socket disappearance during admission accepted')
	}
	refusals++
	assert CoexistPolicy.quarter_host_32g.limit_mib() == 32768
	assert CoexistPolicy.quarter_host_32g.host_divisor() == 4
	assert policy.limits().contains('host >=128GiB')
	println('COEXISTENCE-64G SELF-TEST PASS refusals=' + refusals.str() + ' unchanged-32g-default explicit-64g host-128g-minimum bounded-parser socket-lstat-only explicit-absence-parent-identity policy-recheck')
}

fn self_test() ! {
	network_self_test()!
	qmp_check('/tmp/browser-probe')!
	if _ := qmp_check('/' + 'x'.repeat(103)) { return error('oversized QMP path accepted') }
	if _ := canonical_root(repo) { return error('repository output accepted') }
	if _ := identity(1) { return error('unsafe PID accepted') }
	result := execute(['/bin/ps', '-p', os.getpid().str(), '-o', 'pid='])!
	assert result.code == 0 && result.stdout.trim_space() == os.getpid().str()
	output := execute([os.executable(), '--self-test-output'])!
	assert output.code == 0 && output.stdout == 'o'.repeat(65536) + '\n'
	assert output.stderr == 'e'.repeat(65536) + '\n'
	failed := execute([os.executable(), '--self-test-exit'])!
	assert failed.code == 7 && failed.stdout == '' && failed.stderr == ''
	root := os.join_path(os.temp_dir(), 'vinix-browser-run-selftest-' + os.getpid().str())
	if os.exists(root) || os.is_link(root) { return error('selftest output exists') }
	os.mkdir(root)!
	defer { os.rmdir_all(root) or {} }
	coexist_self_test(root)!
	coexist_64g_self_test(root)!
	daemon_log_self_test(root)!
	hash_self_test(root)!
	os.write_file(root + '/qemu.pid', os.getpid().str())!
	write_json(root + '/ownership.json', json2.decode[json2.Any](json2.encode(identity(os.getpid())!))!)!
	if _ := owned(root) { return error('non-QEMU process accepted as owned guest') }
	if _ := observe_gone(root) { return error('non-QEMU ownership accepted for disappearance') }
	assert !os.exists(root + '/gone.json')
	mut child := os.new_process(os.executable())
	child.set_args(['--self-test-child'])
	child.run()
	defer {
		if child.is_alive() { child.signal_kill() }
		child.wait()
		child.close()
	}
	live := identity(child.pid)!
	os.rm(root + '/qemu.pid')!
	assert !process_gone(live)!
	if _ := process_gone(Ownership{ pid: live.pid, started: live.started, command: live.command + ' changed' }) {
		return error('changed live command accepted')
	}
	child.wait()
	assert process_gone(live)!
	missing := execute(['/bin/ps', '-ww', '-p', child.pid.str(), '-o', 'lstart=,command='])!
	assert missing.code == 1 && missing.stdout.trim_space() == '' && missing.stderr.trim_space() == ''
	assert !os.exists(root + '/qemu.pid')
	os.rm(root + '/ownership.json')!
	fake := Ownership{
		pid:     child.pid
		started: live.started
		command: qemu + ' -qmp unix:' + root + '/qmp.sock,server=on,wait=off -pidfile ' + root + '/qemu.pid'
	}
	write_json(root + '/ownership.json', json2.decode[json2.Any](json2.encode(fake))!)!
	assert stopped(root)!
	if _ := reconcile_stop(root) { return error('missing stop receipt accepted') }
	observe_gone(root)!
	observed := json2.decode[json2.Any](os.read_file(root + '/gone.json')!)!
	assert observed.as_map()['stop_requested']!.bool() == false
	assert observed.as_map()['exit_status']!.str() == 'unknown'
	assert !os.exists(root + '/stop.json')
	if _ := observe_gone(root) { return error('existing disappearance observation accepted') }
	cleanup_self_test(root)!
	os.rm(root + '/gone.json')!
	write_json(root + '/stop.json', json2.decode[json2.Any](json2.encode(StopReceipt{
		pid:           child.pid
		signal:        'SIGTERM'
		requested_utc: time.utc().str()
	}))!)!
	if _ := observe_gone(root) { return error('stop request accepted for read-only disappearance') }
	assert !os.exists(root + '/gone.json')
	reconcile_stop(root)!
	assert os.is_file(root + '/gone.json')
	if _ := reconcile_stop(root) { return error('existing disappearance receipt accepted') }
	println('BROWSER-RUN SELF-TEST PASS qmp-length external-directory unsafe-pid bounded-command complete-output foreign-owner nonzero-exit live-without-pidfile reaped-child absent-ps reconcile-stop observe-gone no-invented-signal stale-socket-cleanup active-socket-rejection exact-cleanup-allowlist')
}

fn main() {
	if os.args.len > 2 && os.args[1] == '--self-test-daemon-log' {
		args := os.args[2..]
		assert args.filter(it == '-D').len == 1 && '-daemonize' in args && '-d' !in args
		mut file := os.open_file(args[args.index('-D') + 1], 'w')!
		if C.dup2(file.fd, 2) != 2 { exit(1) }
		file.close()
		eprintln('BROWSER-RUN DAEMON-STDERR-FIXTURE')
		return
	}
	if os.args.len == 2 && os.args[1] == '--self-test-output' {
		println('o'.repeat(65536))
		eprintln('e'.repeat(65536))
		return
	}
	if os.args.len == 2 && os.args[1] == '--self-test-exit' { exit(7) }
	if os.args.len == 2 && os.args[1] == '--self-test-child' {
		time.sleep(time.second)
		return
	}
	if os.args.len == 2 && os.args[1] == '--self-test' {
		self_test() or {
			eprintln(err.msg())
			exit(1)
		}
		return
	}
	if os.args.len == 4 && os.args[1] in ['start-coexisting', 'admit-coexisting', 'start-coexisting-64g', 'admit-coexisting-64g'] {
		root := canonical_root(os.args[2]) or { eprintln(err.msg()); exit(1) }
		value := positive_decimal(os.args[3]) or { eprintln(err.msg()); exit(1) }
		if value <= 1 || value > 2147483647 { eprintln('explicit safe foreign PID required'); exit(1) }
		policy := if os.args[1].ends_with('-64g') { CoexistPolicy.half_host_64g } else { CoexistPolicy.quarter_host_32g }
		if os.args[1] in ['admit-coexisting', 'admit-coexisting-64g'] {
			admission := foreign_admission_policy(root, int(value), policy) or { eprintln(err.msg()); exit(1) }
			println(json2.encode(admission, prettify: true))
		} else {
			start_admitted_policy(root, .user_default, int(value), policy) or { eprintln(err.msg()); exit(1) }
		}
		return
	}
	if os.args.len != 3 || os.args[1] !in ['start', 'start-ipv4', 'status', 'stop', 'reconcile-stop', 'observe-gone', 'cleanup-gone'] {
		eprintln('usage: run start|start-ipv4|status|stop|reconcile-stop|observe-gone|cleanup-gone STAGED_EXTERNAL_DIRECTORY')
		eprintln('       run start-coexisting|admit-coexisting STAGED_EXTERNAL_DIRECTORY FOREIGN_PID')
		eprintln('       run start-coexisting-64g|admit-coexisting-64g STAGED_EXTERNAL_DIRECTORY FOREIGN_PID (explicit opt-in; host >=128GiB)')
		exit(2)
	}
	root := canonical_root(os.args[2]) or {
		eprintln(err.msg())
		exit(1)
	}
	match os.args[1] {
		'start', 'start-ipv4' {
			mode := if os.args[1] == 'start-ipv4' { NetworkMode.ipv4_only } else { NetworkMode.user_default }
			start(root, mode) or {
				eprintln(err.msg())
				exit(1)
			}
		}
		'stop' {
			stop(root) or {
				eprintln(err.msg())
				exit(1)
			}
		}
		'reconcile-stop' {
			reconcile_stop(root) or {
				eprintln(err.msg())
				exit(1)
			}
		}
		'observe-gone' {
			observe_gone(root) or {
				eprintln(err.msg())
				exit(1)
			}
		}
		'cleanup-gone' {
			cleanup_gone(root) or {
				eprintln(err.msg())
				exit(1)
			}
		}
		'status' {
			gone := stopped(root) or {
				eprintln(err.msg())
				exit(1)
			}
			println(if gone {
				'BROWSER-RUN STOPPED'
			} else {
				'BROWSER-RUN LIVE pid=' + recorded_owner(root) or {
					eprintln(err.msg())
					exit(1)
				}.pid.str()
			})
		}
		else {}
	}
}
