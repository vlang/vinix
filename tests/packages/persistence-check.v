// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import hwhost
import json2
import os
import time

struct PersistenceArtifact {
	role   string
	bytes  u64
	sha256 string
}

struct PersistenceReceipt {
	format       int = 1
	architecture string
	completed_at i64
	platform     string = 'qemu-ext2'
	checkpoints  []string
	artifacts    []PersistenceArtifact
}

fn persistence_artifact(role string, path string) !PersistenceArtifact {
	bytes := os.read_bytes(path)!
	return PersistenceArtifact{ role: role, bytes: u64(bytes.len), sha256: sha256.sum(bytes).hex() }
}

fn persistence_suite(image string) hwhost.Suite {
	mut scenarios := []hwhost.Scenario{}
	for phase in ['staged', 'published', 'activated'] {
		name := 'packages-crash-' + phase
		marker := 'PACKAGE CUT ' + phase
		scenarios << hwhost.Scenario{
			name:         name
			arches:       ['aarch64', 'x86_64']
			cmdline:      'vinix.qemu_persist=1'
			about:        'SIGKILL QEMU after ' + phase + ', reboot the same ext2 disk and recover packages'
			disks:        [hwhost.Disk{ name: 'packages.ext2', size_mib: 64, image: image }]
			qemu_aarch64: ['-drive',
				'if=none,id=packages,format=raw,cache=writeback,file={state}/packages.ext2', '-device',
				'virtio-blk-device,drive=packages']
			qemu_x86_64:  ['-drive', 'if=ide,format=raw,cache=writeback,file={state}/packages.ext2']
			required:     ['HWTEST START ' + name, marker, 'PACKAGE RECOVERY ' + phase,
				'HWTEST PASS ' + name]
			reboots:      [hwhost.Reboot{ power_cut_after: marker }]
			ending:       .poweroff
			timeout:      240
		}
	}
	return hwhost.Suite{
		name:         'package-persistence'
		guest:        'tests/accounts/guest'
		module_paths: ['.', 'tools/accounts', 'tools/security-events', 'tools/keyring']
		programs:     [hwhost.Program{ source: 'tools/packages/main.v', path: 'usr/bin/vinix-package' }]
		scenarios:    scenarios
	}
}

fn persistence_check() !int {
	args := os.args[1..]
	options := hwhost.parse_options(args)!
	if options.help || options.list { return hwhost.run_suite(persistence_suite(''), args, @FILE) }
	if !os.is_file(options.kernel) { return error('--kernel is not a file: ${options.kernel}') }
	work := os.temp_dir() + '/vinix-package-persistence-' + os.getpid().str()
	os.mkdir_all(work)!
	defer { os.rmdir_all(work) or {} }
	kernel := work + '/kernel'
	os.cp(options.kernel, kernel)!
	image := work + '/packages.ext2'
	os.write_file(image, '')!
	os.truncate(image, u64(64) << 20)!
	tool := os.getenv_opt('VINIX_MKE2FS') or {
		os.find_abs_path_of_executable('mke2fs') or { '/opt/homebrew/opt/e2fsprogs/sbin/mke2fs' }
	}
	hwhost.run_tool([tool, '-q', '-F', '-t', 'ext2', '-b', '4096', '-I', '128', '-m', '0', '-O',
		'none,filetype,sparse_super,large_file', image], map[string]string{}, work + '/format.log', 60)!
	suite := persistence_suite(image)
	status := hwhost.run_suite(suite, [...args, '--kernel', kernel], @FILE)
	if status == 0 && options.state_dir != '' {
		// Retain the exact formatted input whose digest the receipt records.
		os.cp(image, options.state_dir + '/initial.ext2')!
		selected := hwhost.select_scenarios(suite.scenarios, options.arch, options.scenarios)!.run
		mut artifacts := [persistence_artifact('kernel', kernel)!,
			persistence_artifact('initial-ext2', image)!,
			persistence_artifact('guest', options.state_dir + '/guest/init')!,
			persistence_artifact('package-service', options.state_dir + '/guest/root/usr/bin/vinix-package')!]
		for scenario in selected {
			for name in ['serial.log', 'serial-2.log'] {
				artifacts << persistence_artifact(scenario.name + '/' + name, options.state_dir + '/' + scenario.name + '/' + name)!
			}
		}
		receipt := PersistenceReceipt{
			architecture: options.arch
			completed_at: time.now().unix()
			checkpoints:  selected.map(it.name.all_after_last('-'))
			artifacts:    artifacts
		}
		os.write_file(options.state_dir + '/qualification.json', json2.encode(receipt) + '\n')!
	}
	return status
}

fn main() {
	status := persistence_check() or {
		eprintln(err)
		exit(1)
	}
	exit(status)
}
