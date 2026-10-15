// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import guesthost
import json2
import os
import tests.development.coldbootcore
import tests.development.servicecore
import tools.development.devcore
import tools.development.jobcore

#include <unistd.h>
fn C.truncate(&char, i64) i32

struct Stage {
	schema int
	architecture string
	complete bool
	binaries map[string]string
}

struct Boot {
	phase int
	command []string
	iso_sha256 string
	disk_before string
	disk_after string
	native_receipts map[string]string
	passed bool
}

struct Receipt {
	schema int = 1
	architecture string
	uid int = 1000
	context string = 'native Vinix; three fresh QEMU processes sharing one private ext2 home; seven-second deferred-cleanup quiescence before unmount'
	inputs map[string]string
	plan_sha256 string
mut:
	boots []Boot
	complete bool
}

fn digest(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }

fn utility(variable string, candidates []string) !string {
	if value := os.getenv_opt(variable) { return os.find_abs_path_of_executable(value)! }
	for candidate in candidates {
		return os.find_abs_path_of_executable(candidate) or { continue }
	}
	return error('missing filesystem utility: ' + variable)
}

fn checked(argv []string, directory string, log string) ! {
	if devcore.run(argv, directory, devcore.environment(0), 120, log)! != 0 {
		return error('filesystem check/format failed; see ' + log)
	}
}

fn receipts(path string) !map[string]string {
	mut values := map[string]string{}
	for line in os.read_lines(path)! {
		if !line.starts_with('DEVELOPMENT RECEIPT ') { continue }
		entry := line.all_after('DEVELOPMENT RECEIPT ').trim_space()
		name := entry.all_before(' ')
		if name !in ['/home/developer/service-state/state.json', '/home/developer/service-after.json',
			'/home/developer/service-cold-proof.json'] || name in values {
			return error('unexpected or duplicate cold boot receipt')
		}
		body := entry.all_after(' ')
		json2.decode[json2.Any](body)!
		values[name] = body
	}
	return values
}

fn run() ! {
	if os.args.len != 6 || os.args[1] !in ['aarch64', 'x86_64'] {
		return error('usage: service-cold-boot ARCH KERNEL-DIR STAGED-TOOLS NATIVE-DESKTOP FRESH-STATE')
	}
	arch := os.args[1]
	kernel := os.real_path(os.args[2])
	stage := os.real_path(os.args[3])
	broker := os.real_path(os.args[4])
	state := os.abs_path(os.args[5])
	formatter := utility('VINIX_MKE2FS', ['mke2fs', 'mkfs.ext2', '/opt/homebrew/opt/e2fsprogs/sbin/mke2fs'])!
	checker := utility('VINIX_E2FSCK', ['e2fsck', '/opt/homebrew/opt/e2fsprogs/sbin/e2fsck'])!
	manifest := json2.decode[Stage](os.read_file(stage + '/development-tools.json')!)!
	if manifest.schema != 1 || !manifest.complete || manifest.architecture != arch
		|| digest(stage + '/usr/bin/vinix-jobs')! != manifest.binaries['vinix-jobs'] {
		return error('scheduler staging manifest is incomplete, changed or for another architecture')
	}
	devcore.fresh_directory(state)!
	os.mkdir_all(state + '/kernel/bin')!
	os.cp(kernel + '/bin/vinix', state + '/kernel/bin/vinix')!
	os.mkdir_all(state + '/fixture')!
	init := guesthost.compile_init(guesthost.root() + '/tests/development/guestfixture/core.v', state + '/fixture', arch, false)!
	os.mkdir_all(state + '/inputs/usr/bin')!
	broker_hash := servicecore.stage(broker, state + '/inputs', arch)!
	jobs := os.read_bytes(stage + '/usr/bin/vinix-jobs')!
	if jobs.len < 20 || jobs[..6] != [u8(0x7f), `E`, `L`, `F`, 2, 1]
		|| (u16(jobs[18]) | (u16(jobs[19]) << 8)) != if arch == 'aarch64' { u16(183) } else { u16(62) } {
		return error('scheduler has the wrong native ELF target')
	}
	jobs_hash := sha256.sum(jobs).hex()
	if jobs_hash != manifest.binaries['vinix-jobs'] { return error('scheduler changed during staging') }
	os.write_file_array(state + '/inputs/usr/bin/vinix-jobs', jobs)!
	os.chmod(state + '/inputs/usr/bin/vinix-jobs', 0o755)!
	plan := json2.encode(jobcore.Plan{uid: 1000, jobs: [jobcore.Job{
		id: 'fixture', executable: devcore.Pin{'/usr/bin/development-payload', digest(init)!},
		directory: '/home/developer', interval_seconds: 1, timeout_seconds: 30,
		environment: {'VINIX_DEVELOPMENT_PAYLOAD': 'service-linger', 'VINIX_JOB_PROOF_PREFIX': '/home/developer/service'},
		credential_files: {'TEST_TOKEN': '/home/developer/token'}
	}]})
	mut receipt := Receipt{architecture: arch, plan_sha256: sha256.sum(plan.bytes()).hex(), inputs: {
		'kernel': digest(state + '/kernel/bin/vinix')!, 'fixture': digest(init)!,
		'vinix-jobs': jobs_hash, 'vinix-desktop': broker_hash,
		'mke2fs': digest(formatter)!, 'e2fsck': digest(checker)!
	}}
	defer {
		os.write_file(state + '/receipt.json', json2.encode(receipt, prettify: true) + '\n') or { eprintln(err) }
	}
	disk := state + '/home.ext2'
	os.write_file(disk, '')!
	if unsafe { C.truncate(disk.str, 64 * 1024 * 1024) } != 0 { return error('could not size private ext2 home') }
	checked([formatter, '-q', '-F', '-t', 'ext2', '-b', '4096', '-I', '128', '-O',
		'filetype,sparse_super,^has_journal,^resize_inode,^dir_index,^extent,^64bit,^metadata_csum', disk], state, state + '/format.log')!
	mut previous_state := ''
	mut previous_disk := ''
	// x86 brings up its SATA disk drivers only for the installed-disk boot mode.
	// This private 64 MiB test volume is too small to become a system install.
	if arch == 'x86_64' { os.setenv('VINIX_CMDLINE', 'vinix.disk=auto', true) }
	for phase in 1 .. 4 {
		boot := state + '/boot-' + phase.str()
		os.mkdir_all(boot + '/rootfs/usr/bin')!
		os.mkdir_all(boot + '/rootfs/home/developer')!
		os.mkdir_all(boot + '/rootfs/fixture')!
		for name, hash in {'vinix-jobs': jobs_hash, 'vinix-desktop': broker_hash} {
			source := state + '/inputs/usr/bin/' + name
			if digest(source)! != hash { return error('cold boot executable input changed') }
			os.cp(source, boot + '/rootfs/usr/bin/' + name)!
		}
		os.cp(init, boot + '/rootfs/usr/bin/development-payload')!
		os.write_file(boot + '/rootfs/fixture/service-jobs.json', plan)!
		os.write_file(boot + '/rootfs/fixture/service-cold-phase', phase.str())!
		os.write_file(boot + '/rootfs/fixture/service-cold-device', if arch == 'aarch64' { '/dev/vda' } else { '/dev/sd0' })!
		archive := guesthost.image(init, boot)!
		os.rmdir_all(boot + '/rootfs')!
		launch := guesthost.launch(init, archive, boot, state + '/kernel', arch, true)!
		os.rm(archive)!
		mut command := launch.command.clone()
		if arch == 'aarch64' {
			command << ['-drive', 'if=none,format=raw,file=' + disk + ',id=service-home', '-device', 'virtio-blk-device,drive=service-home']
		} else { command << ['-drive', 'if=ide,format=raw,file=' + disk] }
		before := digest(disk)!
		iso_hash := digest(boot + '/test.iso')!
		if phase > 1 && before != previous_disk { return error('home volume changed between cold boots') }
		code := guesthost.boot(command, launch.env, boot,
			['DEVELOPMENT SERVICE COLD BOOT PASS: phase=' + phase.str() + ','],
			['DEVELOPMENT GUEST FAIL', 'KERNEL PANIC', 'vinix-native-fixture-secret'], 180, true)!
		values := receipts(boot + '/serial.log')!
		after := digest(disk)!
		receipt.boots << Boot{phase, command, iso_hash, before, after, values, false}
		if code != 0 { return error('native cold boot gate failed') }
		coldbootcore.verify(values, phase, receipt.plan_sha256)!
		if phase > 1 && values['/home/developer/service-state/state.json'] != previous_state {
			return error('cold boot did not recover the exact previous schedule state')
		}
		if before == after { return error('cold boot did not modify the persistent home') }
		checked([checker, '-f', '-n', disk], state, boot + '/fsck.log')!
		receipt.boots[receipt.boots.len - 1] = Boot{...receipt.boots.last(), passed: true}
		previous_state = values['/home/developer/service-after.json']
		previous_disk = digest(disk)!
		if previous_disk != after { return error('read-only filesystem check changed the home volume') }
		// Logs, receipts and the one persistent home remain; each ISO is reproducible.
		os.rm(boot + '/test.iso')!
	}
	receipt.complete = true
}

fn main() {
	run() or { eprintln(err); exit(1) }
}
