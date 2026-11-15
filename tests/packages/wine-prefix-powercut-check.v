// SPDX-License-Identifier: GPL-2.0-or-later
module main

import hwhost
import crypto.sha256
import json2
import os
import plainiso
import tests.packages.winesource
import tests.packages.winecutfixture

#include <unistd.h>
fn C.ftruncate(i32, u64) i32

fn tool(command []string, log string) ! {
	mut process := os.new_process(command[0])
	defer { process.close() }
	process.set_args(command[1..]); process.set_redirect_stdio(); process.run()
	output := process.stdout_slurp() + process.stderr_slurp()
	process.wait()
	os.write_file(log, json2.encode(command) + '\n' + output + '\nexit_code=' + process.code.str() + '\n')!
	if process.code != 0 { return error('disk utility failed; see ' + log) }
}

fn run() ! {
	point_option := os.args.len > 1 && os.args.last().starts_with('--point=')
	point_args := if point_option { os.args[..os.args.len - 1] } else { os.args }
	prepared := point_args.len > 1 && point_args.last() == '--prepared'
	mode_args := if prepared { point_args[..point_args.len - 1] } else { point_args }
	all_syncs := mode_args.len > 1 && mode_args.last() == '--all-syncs'
	scaled := mode_args.len > 1 && mode_args.last() == '--scaled'
	args := if all_syncs || scaled { mode_args[..mode_args.len - 1] } else { mode_args }
	if args.len !in [5, 6, 7, 9] || (args.len >= 6 && args[5] != '--vjfs')
		|| (args.len >= 7 && args[6] != '--service') || (args.len >= 9 && args[7] != '--cli') {
		return error('usage: CHECK FRESH_WORK ARCH KERNEL POWERCUT_GUEST [--vjfs [--service [--cli COMPILED_CLI]]] [--all-syncs | --scaled [--prepared]] [--point=N]')
	}
	if prepared && (!scaled || args.len !in [7, 9]) { return error('prepared baseline requires scaled VJFS service or CLI mode') }
	if args.len >= 9 && args[8] == '' { return error('nonempty compiled CLI path required') }
	journaled := args.len >= 6
	service := args.len >= 7
	cli := if args.len >= 9 { args[8] } else { '' }
	mut points := winecutfixture.points(scaled, all_syncs)
	if point_option {
		text := os.args.last().all_after('--point=')
		point := text.int()
		if point !in points || text != point.str() { return error('point must be a canonical member of the selected fixture matrix') }
		points = [point]
	}
	rows := if scaled { 741 } else { 3 }
	image_helper := if journaled { os.getenv_opt('VINIX_WINE_IMAGE_HELPER') or { return error('VJFS requires VINIX_WINE_IMAGE_HELPER') } } else { '' }
	work := os.abs_path(os.args[1]); arch := os.args[2]
	if arch !in ['aarch64', 'x86_64'] || os.exists(work) || os.is_link(work) { return error('fresh work and supported architecture required') }
	if winesource.file_digest(@FILE)! != sha256.hexhash($embed_file('wine-prefix-powercut-check.v').to_string()) {
		return error('compiled powercut controller source differs')
	}
	layout := os.dir(@FILE) + '/winecutfixture/layout.v'
	if winesource.file_digest(layout)! != sha256.hexhash($embed_file('winecutfixture/layout.v').to_string()) {
		return error('compiled powercut fixture layout differs')
	}
	root := os.real_path(os.dir(@FILE) + '/../..')
	host := hwhost.find_host(root, arch, '')!
	formatter := os.getenv_opt('VINIX_MKE2FS') or { '/opt/homebrew/opt/e2fsprogs/sbin/mke2fs' }
	checker := os.getenv_opt('VINIX_E2FSCK') or { '/opt/homebrew/opt/e2fsprogs/sbin/e2fsck' }
	mut inputs := map[string]string{}
	for path in [@FILE, layout, os.executable(), os.args[3], os.args[4], host.qemu, host.firmware, host.firmware_vars, formatter, checker] {
		if path != '' { inputs[path] = winesource.file_digest(path)! }
	}
	if journaled { inputs[image_helper] = winesource.file_digest(image_helper)! }
	if cli != '' { inputs[cli] = winesource.file_digest(cli)! }
	if arch == 'x86_64' {
		for _, path in plainiso.inputs(root)! { inputs[path] = winesource.file_digest(path)! }
	} else {
		loader := os.getenv_opt('VINIX_LIMINE_BOOTAA64') or { hwhost.shared_path(root, 'boot-image/limine-bin/BOOTAA64.EFI') }
		inputs[loader] = winesource.file_digest(loader)!
	}
	os.mkdir_all(work)!
	os.write_file(work + '/selection.json', json2.encode(points))!
	inputs[work + '/selection.json'] = winesource.file_digest(work + '/selection.json')!
	seed := work + '/blank.img'
	if journaled {
		os.mkdir(work + '/seed')!
		tool([image_helper, 'create', work + '/seed', seed, formatter, '32'], work + '/format.log')!
	} else {
		mut file := os.create(seed)!
		if C.ftruncate(file.fd, 32 << 20) != 0 { file.close(); return error('cannot size private ext2 disk') }
		file.close()
		tool([formatter, '-q', '-F', '-t', 'ext2', '-b', '4096', '-I', '128', '-O',
			'filetype,sparse_super,^has_journal,^resize_inode,^dir_index,^extent,^64bit,^metadata_csum', seed], work + '/format.log')!
	}
	os.write_file(work + '/storage.json', json2.encode({'format': if journaled { 'VJFS' } else { 'ext2' },
		'cache': 'writeback', 'cut': 'QEMU SIGKILL', 'host-cache': 'survives'}))!
	inputs[seed] = winesource.file_digest(seed)!
	for point in points {
		config := work + '/extras-' + point.str() + '/etc/wine-cut-point'
		os.mkdir_all(os.dir(config))!
		os.write_file(config, point.str())!
		inputs[config] = winesource.file_digest(config)!
		if cli != '' {
			staged := work + '/extras-' + point.str() + '/usr/bin/vinix-package'
			os.mkdir_all(os.dir(staged))!
			os.cp(cli, staged)!; os.chmod(staged, 0o755)!
			inputs[staged] = winesource.file_digest(staged)!
		}
	}
	boot_host := if arch == 'x86_64' { hwhost.Host{...host, root: plainiso.prepare(root, work)!} } else { host }
	base := hwhost.Scenario{name: 'wine-prefix-powercut', arches: [arch], ending: .poweroff,
		cmdline: if arch == 'aarch64' { 'vinix.qemu_persist=1' } else { '' },
		disks: [hwhost.Disk{name: 'prefix.ext2', size_mib: if journaled { 36 } else { 32 }, image: seed}],
		qemu_x86_64: ['-drive',
			'if=none,id=winecut,format=raw,cache=writeback,file={state}/prefix.ext2', '-device', 'ide-hd,drive=winecut,bus=ide.0'],
		qemu_aarch64: ['-drive', 'if=none,id=winecut,format=raw,cache=writeback,file={state}/prefix.ext2',
			'-device', 'virtio-blk-device,drive=winecut'], forbidden: ['HWTEST FAIL', 'Kernel panic']}
	mut selected_seed := seed
	if prepared {
		extras := work + '/prepare-extras'
		os.mkdir_all(extras + '/etc')!
		for name, value in {'wine-cut-point': points[0].str(), 'wine-cut-prepare': '741'} {
			path := extras + '/etc/' + name
			os.write_file(path, value)!; inputs[path] = winesource.file_digest(path)!
		}
		state := work + '/prepare'
		outcome := hwhost.run_scenario(boot_host, hwhost.Scenario{...base, required: [
			'WINE POWER CUT PROFILE bindings=741',
			'WINE SERVICE POWER CUT STORE point=${points[0]} fresh=true generation=2 signed-root',
			'WINE POWER CUT BASELINE PASS bindings=741', 'HWTEST PASS wine-prefix-powercut']},
			hwhost.Run{kernel: os.args[3], guest: os.args[4], state: state, extras: extras, timeout: 120, keep: true})
		os.write_file(state + '/result.json', json2.encode(outcome))!
		if outcome.interrupted || !outcome.passed { return error('signed baseline preparation failed: ' + outcome.reason) }
		selected_seed = state + '/prefix.ext2'
		tool([image_helper, 'export', selected_seed, state + '/inspection.ext2'], state + '/export.log')!
		tool([checker, '-f', '-n', state + '/inspection.ext2'], state + '/e2fsck.log')!
		inputs[selected_seed] = winesource.file_digest(selected_seed)!
		println('WINE POWERCUT BASELINE PASS arch=${arch} separate-boot cap=120 ext2-check')
	}
	os.write_file(work + '/inputs-before.json', json2.encode(inputs))!
	mut failures := []string{}
	for point in points {
		state := work + '/point-' + point.str()
		marker := 'WINE POWER CUT READY point=${point}'
		mut required := [marker, 'WINE POWER CUT OBSERVED point=${point} ext2 private-data old-new-bindings',
			'WINE POWER CUT PROFILE bindings=${rows}',
			'WINE POWER CUT SETTLED point=${point} grace-seconds=6',
			'WINE POWER CUT RECOVERY PASS point=${point} fresh-capture repeat private-data', 'HWTEST PASS wine-prefix-powercut']
		boundary := winecutfixture.boundary(point, rows - 1)!
		required << 'WINE POWER CUT STATE point=${point} replaced=${boundary.replaced} added=${boundary.added} staged=${boundary.staged}'
		if service {
			required << 'WINE SERVICE POWER CUT STORE point=${point} fresh=true generation=2 signed-root'
			required << 'WINE SERVICE POWER CUT STORE point=${point} fresh=false generation=2 signed-root'
			required << 'WINE SERVICE POWER CUT ADMIT point=${point} generation=2 rows=${rows}'
			required << 'WINE SERVICE POWER CUT PASS point=${point} signed-generation=2 lease-free reader-lock-free'
		}
		if prepared {
			required << 'WINE SERVICE POWER CUT TEMPLATE point=${point} fresh=true rows=741'
			required << 'WINE SERVICE POWER CUT TEMPLATE point=${point} fresh=false rows=741'
		}
		if cli != '' {
			required << 'WINE CLI POWER CUT EXEC point=${point} command=wine-prefix-migrate'
			required << 'WINE CLI POWER CUT PASS point=${point} migrate-repeat review-json'
		}
		outcome := hwhost.run_scenario(boot_host, hwhost.Scenario{...base,
			disks: [hwhost.Disk{name: 'prefix.ext2', size_mib: if journaled { 36 } else { 32 }, image: selected_seed}],
			reboots: [hwhost.Reboot{power_cut_after: marker}],
			required: required},
			hwhost.Run{kernel: os.args[3], guest: os.args[4], state: state, extras: work + '/extras-' + point.str(), timeout: 120, keep: true})
		os.write_file(state + '/result.json', json2.encode(outcome))!
		if outcome.interrupted { return error('powercut guest interrupted') }
		if !outcome.passed {
			failures << 'powercut guest failed at point ' + point.str() + ': ' + outcome.reason
			continue
		}
		inspection := if journaled { state + '/inspection.ext2' } else { state + '/prefix.ext2' }
		if journaled {
			tool([image_helper, 'export', state + '/prefix.ext2', inspection], state + '/export.log') or { failures << err.msg(); continue }
		}
		tool([checker, '-f', '-n', inspection], state + '/e2fsck.log') or { failures << err.msg(); continue }
		println('WINE POWERCUT POINT PASS arch=${arch} point=${point} two-boots SIGKILL ext2-check')
	}
	for path, expected in inputs { if winesource.file_digest(path)! != expected { return error('powercut input changed') } }
	os.write_file(work + '/inputs-verified.json', json2.encode(inputs))!
	os.write_file(work + '/failures.json', json2.encode(failures))!
	if failures.len > 0 { return error(failures.join('\n')) }
	if point_option {
		println('WINE POWERCUT FOCUSED PASS arch=${arch} point=${points[0]}')
	} else { println('WINE POWERCUT GUEST PASS ' + arch) }
}

fn main() {
	if plainiso.requested() { plainiso.build() or { eprintln(err); exit(1) }; return }
	run() or { eprintln(err); exit(1) }
}
