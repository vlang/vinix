// SPDX-License-Identifier: GPL-2.0-or-later
// Replace only the kernel in a fresh diagnostic stage; never launch a guest.
module main

import crypto.sha256
import json2
import modulestream
import os
import time

#include <signal.h>

fn C.kill(int, int) int

const baseline_sha = '176094564fba09181b1a2f334f240dc49f0e5f25032696a84db12c2316d0445c'
const source = $embed_file(@FILE).to_string()

struct Stage {
	format                   int
	inputs_sha256            map[string]string
	original_modules_sha256  map[string]string
	preserved_modules_sha256 map[string]string
	overlay_sha256           string
	limine_before_sha256     string
	limine_after_sha256      string
	staged_boot_sha256       string
	staged_efivars_sha256    string
}

struct Build {
	format                    int
	source_revision           string
	architecture              string
	kernel_path               string
	kernel_sha256             string
	kernel_unix_source_sha256 string
	generated_c_sha256        string
	compiler_sha256           string
	guest_executed            bool
	link_seed                 int
}

struct Inventory {
	files map[string]string
	links map[string]string
}

struct Config {
	kernel  string
	modules []string
}

fn hash(path string) !string {
	mut file := os.open(path)!
	defer { file.close() }
	mut digest := sha256.new()
	mut buffer := []u8{len: 1024 * 1024}
	for {
		n := file.read(mut buffer) or {
			if err is os.Eof { break }
			return err
		}
		if n == 0 { break }
		digest.write(buffer[..n])!
	}
	return digest.sum([]u8{}).hex()
}

fn digest_valid(value string) bool {
	return value.len == 64 && value.bytes().all((it >= `0` && it <= `9`) || (it >= `a` && it <= `f`))
}

fn regular(path string) ! {
	if os.lstat(path)!.get_filetype() != .regular {
		return error('regular non-symlink file required: ' + path)
	}
}

fn relative(path string) bool {
	return path != '' && !path.starts_with('/') && !path.contains_any('\x00\r\n\\')
		&& !path.split('/').any(it in ['', '.', '..'])
}

fn member(line string, key string) !string {
	prefix := key + ': boot():/boot/'
	if !line.starts_with(prefix) { return error('unsupported Limine path: ' + line) }
	name := line[prefix.len..]
	if name == '' || name in ['.', '..'] || name.len > 255
		|| !name.bytes().all((it >= `a` && it <= `z`) || (it >= `A` && it <= `Z`)
			|| (it >= `0` && it <= `9`) || it in [`_`, `-`, `.`]) {
		return error('literal FAT basename required')
	}
	return name
}

fn configure(text string) !Config {
	if text == '' || text.contains_any('\x00\r') {
		return error('expected LF-delimited Limine configuration')
	}
	mut entries := 0
	mut kernel := ''
	mut modules := []string{}
	for raw in text.split_into_lines() {
		line := raw.trim_space()
		if line.starts_with('/') || line.starts_with(':') { entries++ }
		if line.starts_with('kernel_path:') {
			if entries != 1 || kernel != '' { return error('ambiguous kernel entry') }
			kernel = member(line, 'kernel_path')!
		}
		if line.starts_with('module_path:') {
			if entries != 1 { return error('ambiguous module entry') }
			name := member(line, 'module_path')!
			if name in modules || !name.ends_with('.tar') {
				return error('duplicate or non-tar module')
			}
			modules << name
		}
	}
	if entries != 1 || kernel != 'vinix' || modules.len == 0 {
		return error('one Vinix kernel entry required')
	}
	return Config{kernel, modules}
}

fn execute(root string, label string, argv []string) !string {
	mut child := os.new_process(argv[0])
	child.use_pgroup = true
	child.set_args(argv[1..])
	child.set_stdin_path('/dev/null')
	child.set_redirect_stdio()
	child.run()
	defer { child.close() }
	mut finished := false
	defer {
		if !finished {
			if child.pid > 0 { C.kill(-child.pid, 9) }
			child.wait()
		}
	}
	mut stdout := ''
	mut stderr := ''
	deadline := time.sys_mono_now() + 120 * time.second
	for {
		stdout += child.stdout_read()
		stderr += child.stderr_read()
		if stdout.len + stderr.len > 1024 * 1024 { return error('oversized command output') }
		if !child.is_alive() { break }
		if time.sys_mono_now() >= deadline { return error('command deadline: ' + label) }
		time.sleep(10 * time.millisecond)
	}
	for {
		out := child.stdout_read()
		err := child.stderr_read()
		if out == '' && err == '' { break }
		stdout += out
		stderr += err
		if stdout.len + stderr.len > 1024 * 1024 { return error('oversized command output') }
	}
	child.wait()
	finished = true
	os.write_file(root + '/kernel-patch-commands/' + label + '.json', json2.encode({
		'argv':      json2.decode[json2.Any](json2.encode(argv))!
		'exit_code': json2.Any(child.code)
		'stdout':    json2.Any(stdout)
		'stderr':    json2.Any(stderr)
	},
		prettify: true
	))!
	if child.code != 0 { return error(label + ' failed: ' + stderr) }
	return stdout
}

fn fat_hash(root string, label string, image string, name string) !string {
	result := modulestream.hash_member(image, name, root + '/kernel-patch-commands/' + label + '.sha256')!
	if result.statuses.producer != 0 || result.statuses.consumer != 0 || !digest_valid(result.sha256) {
		return error('FAT hash stream failed: ' + name)
	}
	return result.sha256
}

fn unlaunched(root string) ! {
	for name in ['launch.json', 'launch-result.json', 'ownership.json', 'qemu.pid', 'qmp.sock',
		'serial.log', 'network.pcap', 'stop.json', 'gone.json', 'run-source.v', 'runner'] {
		if os.exists(root + '/' + name) || os.is_link(root + '/' + name) {
			return error('fresh unlaunched browser stage required: ' + name)
		}
	}
}

fn verify_inventory(root string, inventory Inventory) ! {
	if inventory.files.len == 0 { return error('empty frozen build inventory') }
	for name, expected in inventory.files {
		if !relative(name) || !digest_valid(expected) {
			return error('unsafe frozen build inventory member')
		}
		path := root + '/' + name
		regular(path)!
		if !os.real_path(path).starts_with(root + '/') || hash(path)! != expected {
			return error('frozen build file differs: ' + name)
		}
	}
	for name, target in inventory.links {
		if !relative(name) || target == '' || target.contains_any('\x00\r\n')
			|| !os.is_link(root + '/' + name) || os.readlink(root + '/' + name)! != target {
			return error('frozen build symlink differs: ' + name)
		}
	}
}

fn validate_build(root string, receipt_sha string) !Build {
	for name in ['build.json', 'input-pins.json', 'sha256.json'] { regular(root + '/' + name)! }
	if !digest_valid(receipt_sha) || hash(root + '/build.json')! != receipt_sha {
		return error('kernel build receipt pin differs')
	}
	build := json2.decode[Build](os.read_file(root + '/build.json')!)!
	if build.format != 1 || build.architecture != 'aarch64' || build.guest_executed
		|| build.source_revision.len != 40 || !build.source_revision.bytes().all((it >= `0` && it <= `9`) || (it >= `a` && it <= `f`))
		|| !digest_valid(build.kernel_sha256) || !digest_valid(build.kernel_unix_source_sha256)
		|| !digest_valid(build.generated_c_sha256) || !digest_valid(build.compiler_sha256)
		|| build.link_seed != 20261026 || !os.is_abs_path(build.kernel_path)
		|| !os.real_path(build.kernel_path).starts_with(root + '/') {
		return error('unsupported or incomplete frozen kernel build receipt')
	}
	regular(build.kernel_path)!
	if hash(build.kernel_path)! != build.kernel_sha256 {
		return error('frozen kernel hash differs')
	}
	mut file := os.open(build.kernel_path)!
	mut header := []u8{len: 20}
	n := file.read(mut header)!
	file.close()
	if n != 20 || header[..6] != [u8(0x7f), `E`, `L`, `F`, 2, 1]
		|| header[16..20] != [u8(2), 0, 183, 0] {
		return error('AArch64 ELF64 executable kernel required')
	}
	inventory := json2.decode[Inventory](os.read_file(root + '/sha256.json')!)!
	verify_inventory(root, inventory)!
	kernel_relative := os.real_path(build.kernel_path)[root.len + 1..]
	if inventory.files[kernel_relative] or { '' } != build.kernel_sha256 {
		return error('frozen kernel is absent from build inventory')
	}
	pins := json2.decode[map[string]json2.Any](os.read_file(root + '/input-pins.json')!)!
	kernel_pins := json2.decode[map[string]string](json2.encode(pins['kernel']!))!
	if kernel_pins['kernel/socket/unix/unix.v'] or { '' } != build.kernel_unix_source_sha256 {
		return error('Unix socket source pin differs from kernel inputs')
	}
	mut unix_source_present := false
	for name, expected in inventory.files {
		if (name == 'kernel/socket/unix/unix.v' || name.ends_with('/kernel/socket/unix/unix.v'))
			&& expected == build.kernel_unix_source_sha256 {
			unix_source_present = true
		}
	}
	if !unix_source_present {
		return error('frozen Unix socket source is absent from build inventory')
	}
	return build
}

fn patch(root string, build_root string, receipt_sha string, baseline_pin string) ! {
	unlaunched(root)!
	for name in ['kernel-patch.json', 'kernel-patch-request.json', 'kernel-patch-commands',
		'kernel-patch-build', 'stage-before-kernel.json', 'kernel-patch-source.v', 'kernel-patch-tool'] {
		if os.exists(root + '/' + name) || os.is_link(root + '/' + name) {
			return error('kernel patch is once-only: ' + name)
		}
	}
	for name in ['stage.json', 'boot.img', 'efivars.fd', 'limine-before.conf', 'limine-after.conf'] {
		regular(root + '/' + name)!
	}
	stage_text := os.read_file(root + '/stage.json')!
	stage := json2.decode[Stage](stage_text)!
	mut stage_map := json2.decode[map[string]json2.Any](stage_text)!
	if 'kernel_patch' in stage_map { return error('stage already declares a kernel patch') }
	if stage.format != 1 || hash(root + '/boot.img')! != stage.staged_boot_sha256
		|| hash(root + '/efivars.fd')! != stage.staged_efivars_sha256
		|| hash(root + '/limine-before.conf')! != stage.limine_before_sha256
		|| hash(root + '/limine-after.conf')! != stage.limine_after_sha256 {
		return error('fresh stage media or configuration pin differs')
	}
	mut baseline := ''
	for path, expected in stage.inputs_sha256 {
		if os.file_name(path) == 'boot.img' && expected == baseline_pin {
			if baseline != '' { return error('ambiguous baseline boot input') }
			baseline = path
		}
	}
	if baseline == '' || baseline == root + '/boot.img' {
		return error('audited original baseline boot input required')
	}
	regular(baseline)!
	if hash(baseline)! != baseline_pin { return error('baseline boot bytes differ') }
	build := validate_build(build_root, receipt_sha)!
	before_text := os.read_file(root + '/limine-before.conf')!
	after_text := os.read_file(root + '/limine-after.conf')!
	before := configure(before_text)!
	after := configure(after_text)!
	mut expected_modules := before.modules.clone()
	expected_modules << 'browser-probe.tar'
	if after.kernel != before.kernel || after.modules != expected_modules
		|| stage.original_modules_sha256.len != before.modules.len
		|| stage.original_modules_sha256 != stage.preserved_modules_sha256
		|| !digest_valid(stage.overlay_sha256) {
		return error('stage baseline/module manifest differs')
	}
	for name in before.modules {
		if !digest_valid(stage.original_modules_sha256[name] or { '' }) {
			return error('module manifest member absent')
		}
	}
	mcopy := os.find_abs_path_of_executable('mcopy')!
	mtype := os.find_abs_path_of_executable('mtype')!
	os.setenv('PATH', os.dir(mcopy) + ':' + os.getenv('PATH'), true)
	os.mkdir(root + '/kernel-patch-commands')!
	for line in execute(root, 'process-check', ['/bin/ps', '-axo', 'pid=,command='])!.split_into_lines() {
		if line.contains('qemu-system-') && line.contains(root + '/') {
			return error('QEMU references this stage; refusing kernel replacement')
		}
	}
	if execute(root, 'baseline-limine', [mtype, '-i', baseline, '::/boot/limine.conf'])! != before_text
		|| execute(root, 'stage-limine-before', [mtype, '-i', root + '/boot.img', '::/boot/limine.conf'])! != after_text {
		return error('FAT Limine configuration differs')
	}
	old_kernel := fat_hash(root, 'baseline-kernel', baseline, before.kernel)!
	if fat_hash(root, 'staged-kernel-before', root + '/boot.img', after.kernel)! != old_kernel {
		return error('fresh staged kernel differs from original baseline')
	}
	if old_kernel == build.kernel_sha256 {
		return error('replacement kernel equals baseline kernel')
	}
	mut preserved := map[string]string{}
	for name in before.modules {
		expected := stage.original_modules_sha256[name]!
		if fat_hash(root, 'baseline-' + name, baseline, name)! != expected
			|| fat_hash(root, 'before-' + name, root + '/boot.img', name)! != expected {
			return error('original module differs before patch: ' + name)
		}
		preserved[name] = expected
	}
	if fat_hash(root, 'before-browser-probe.tar', root + '/boot.img', 'browser-probe.tar')! != stage.overlay_sha256 {
		return error('browser payload differs before patch')
	}
	preserved['browser-probe.tar'] = stage.overlay_sha256
	os.mkdir(root + '/kernel-patch-build')!
	mut build_receipts := map[string]string{}
	for name in ['build.json', 'input-pins.json', 'sha256.json'] {
		os.cp(build_root + '/' + name, root + '/kernel-patch-build/' + name)!
		build_receipts[name] = hash(root + '/kernel-patch-build/' + name)!
	}
	os.write_file(root + '/stage-before-kernel.json', stage_text)!
	os.write_file(root + '/kernel-patch-source.v', source)!
	os.cp(os.executable(), root + '/kernel-patch-tool')!
	os.write_file(root + '/kernel-patch-request.json', json2.encode({
		'created_utc':                 json2.Any(time.utc().str())
		'original_stage_sha256':       json2.Any(sha256.sum(stage_text.bytes()).hex())
		'baseline_boot_sha256':        json2.Any(baseline_pin)
		'kernel_build_receipt_sha256': json2.Any(receipt_sha)
		'original_kernel_sha256':      json2.Any(old_kernel)
		'replacement_kernel_sha256':   json2.Any(build.kernel_sha256)
	}, prettify: true))!
	unlaunched(root)!
	if hash(build_root + '/build.json')! != receipt_sha || hash(build.kernel_path)! != build.kernel_sha256 {
		return error('kernel build changed before installation')
	}
	execute(root, 'install-kernel', [mcopy, '-o', '-i', root + '/boot.img', build.kernel_path,
		'::/boot/' + after.kernel])!
	if fat_hash(root, 'staged-kernel-after', root + '/boot.img', after.kernel)! != build.kernel_sha256 {
		return error('installed kernel readback differs')
	}
	for name, expected in preserved {
		if fat_hash(root, 'after-' + name, root + '/boot.img', name)! != expected {
			return error('module changed during kernel replacement: ' + name)
		}
	}
	if execute(root, 'stage-limine-after', [mtype, '-i', root + '/boot.img', '::/boot/limine.conf'])! != after_text
		|| hash(root + '/efivars.fd')! != stage.staged_efivars_sha256
		|| hash(baseline)! != baseline_pin || hash(build.kernel_path)! != build.kernel_sha256
		|| os.read_file(root + '/stage.json')! != stage_text {
		return error('preserved input changed during replacement')
	}
	for name, expected in build_receipts {
		if hash(build_root + '/' + name)! != expected {
			return error('frozen build receipt changed')
		}
	}
	unlaunched(root)!
	provenance := json2.decode[json2.Any](json2.encode({
		'format':                       json2.Any(1)
		'scope':                        json2.Any('Fresh diagnostic stage only; unchanged r8 browser payload; no guest execution or Google login evidence.')
		'created_utc':                  json2.Any(time.utc().str())
		'baseline_boot_path':           json2.Any(baseline)
		'baseline_boot_sha256':         json2.Any(baseline_pin)
		'original_stage_sha256':        json2.Any(sha256.sum(stage_text.bytes()).hex())
		'original_kernel_sha256':       json2.Any(old_kernel)
		'kernel_member':                json2.Any(after.kernel)
		'kernel_sha256':                json2.Any(build.kernel_sha256)
		'kernel_build_root':            json2.Any(build_root)
		'kernel_build_receipt_sha256':  json2.Any(receipt_sha)
		'kernel_build_receipts_sha256': json2.decode[json2.Any](json2.encode(build_receipts))!
		'kernel_source_revision':       json2.Any(build.source_revision)
		'kernel_unix_source_sha256':    json2.Any(build.kernel_unix_source_sha256)
		'preserved_modules_sha256':     json2.decode[json2.Any](json2.encode(preserved))!
		'limine_sha256':                json2.Any(stage.limine_after_sha256)
		'efivars_sha256':               json2.Any(stage.staged_efivars_sha256)
		'staged_boot_sha256':           json2.Any(hash(root + '/boot.img')!)
		'tool_sha256':                  json2.Any(hash(root + '/kernel-patch-tool')!)
		'tool_source_sha256':           json2.Any(hash(root + '/kernel-patch-source.v')!)
		'mcopy_sha256':                 json2.Any(hash(mcopy)!)
		'mtype_sha256':                 json2.Any(hash(mtype)!)
	}, prettify: true))!
	os.write_file(root + '/kernel-patch.json', json2.encode(provenance, prettify: true) + '\n')!
	stage_map['kernel_patch'] = provenance
	stage_map['kernel_patch_receipt_sha256'] = json2.Any(hash(root + '/kernel-patch.json')!)
	stage_map['staged_boot_sha256'] = json2.Any(hash(root + '/boot.img')!)
	os.write_file(root + '/stage.json', json2.encode(stage_map, prettify: true) + '\n')!
	println('BROWSER-KERNEL-PATCH PASS ' + root + '/kernel-patch.json')
}

fn external(path string) !string {
	abs := os.abs_path(path)
	root := os.real_path(path)
	repo := os.real_path(os.dir(os.dir(os.dir(@FILE))))
	if abs != root || !os.is_dir(root) || root == repo || root.starts_with(repo + '/')
		|| root.contains_any('\x00\r\n') {
		return error('canonical external stage/build directory required')
	}
	return root
}

fn fat_self_test(root string) ! {
	os.mkdir(root + '/kernel-patch-commands')!
	os.mkdir(root + '/baseline')!
	os.mkdir(root + '/stage')!
	os.mkdir_all(root + '/build/kernel/socket/unix')!
	baseline := root + '/baseline/boot.img'
	config := '/Vinix\n kernel_path: boot():/boot/vinix\n module_path: boot():/boot/runtime.tar\n'
	updated := config + ' module_path: boot():/boot/browser-probe.tar\n'
	os.write_file(root + '/config', config)!
	os.write_file(root + '/old-kernel', 'old baseline kernel')!
	os.write_file(root + '/runtime', 'original module\x00exact bytes')!
	os.write_file(root + '/overlay', 'unchanged r8 browser overlay\x00exact bytes')!
	mcopy := os.find_abs_path_of_executable('mcopy')!
	execute(root, 'fixture-format', [os.find_abs_path_of_executable('mformat')!, '-i', baseline,
		'-C', '-f', '1440', '::'])!
	execute(root, 'fixture-mkdir', [os.find_abs_path_of_executable('mmd')!, '-i', baseline, '::/boot'])!
	for pair in [['config', 'limine.conf'], ['old-kernel', 'vinix'], ['runtime', 'runtime.tar']] {
		execute(root, 'fixture-install-' + pair[0], [mcopy, '-i', baseline, root + '/' + pair[0],
			'::/boot/' + pair[1]])!
	}
	os.cp(baseline, root + '/stage/boot.img')!
	os.write_file(root + '/config-after', updated)!
	execute(root, 'fixture-update-limine', [mcopy, '-o', '-i', root + '/stage/boot.img',
		root + '/config-after', '::/boot/limine.conf'])!
	execute(root, 'fixture-install-overlay', [mcopy, '-i', root + '/stage/boot.img', root + '/overlay',
		'::/boot/browser-probe.tar'])!
	os.write_file(root + '/stage/efivars.fd', 'unchanged firmware state')!
	os.write_file(root + '/stage/limine-before.conf', config)!
	os.write_file(root + '/stage/limine-after.conf', updated)!
	original_modules := {
		'runtime.tar': hash(root + '/runtime')!
	}
	stage := Stage{
		format:                   1
		inputs_sha256:            {
			baseline: hash(baseline)!
		}
		original_modules_sha256:  original_modules
		preserved_modules_sha256: original_modules
		overlay_sha256:           hash(root + '/overlay')!
		limine_before_sha256:     hash(root + '/stage/limine-before.conf')!
		limine_after_sha256:      hash(root + '/stage/limine-after.conf')!
		staged_boot_sha256:       hash(root + '/stage/boot.img')!
		staged_efivars_sha256:    hash(root + '/stage/efivars.fd')!
	}
	stage_text := json2.encode(stage, prettify: true)
	os.write_file(root + '/stage/stage.json', stage_text)!
	mut kernel := []u8{len: 64}
	for index, value in [u8(0x7f), `E`, `L`, `F`, 2, 1] { kernel[index] = value }
	kernel[16] = 2
	kernel[18] = 183
	os.write_file_array(root + '/build/vinix', kernel)!
	os.write_file(root + '/build/kernel/socket/unix/unix.v', 'frozen Unix socket source')!
	kernel_hash := hash(root + '/build/vinix')!
	unix_hash := hash(root + '/build/kernel/socket/unix/unix.v')!
	os.write_file(root + '/build/build.json', json2.encode(Build{
		format:                    1
		source_revision:           'a'.repeat(40)
		architecture:              'aarch64'
		kernel_path:               root + '/build/vinix'
		kernel_sha256:             kernel_hash
		kernel_unix_source_sha256: unix_hash
		generated_c_sha256:        'b'.repeat(64)
		compiler_sha256:           'c'.repeat(64)
		link_seed:                 20261026
	}))!
	os.write_file(root + '/build/input-pins.json', json2.encode({
		'kernel': {
			'kernel/socket/unix/unix.v': unix_hash
		}
	}))!
	os.write_file(root + '/build/sha256.json', json2.encode(Inventory{
		files: {
			'vinix':                     kernel_hash
			'kernel/socket/unix/unix.v': unix_hash
		}
	}))!
	receipt_sha := hash(root + '/build/build.json')!
	if _ := patch(root + '/stage', root + '/build', '0'.repeat(64), hash(baseline)!) {
		return error('wrong build receipt pin accepted')
	}
	assert os.read_file(root + '/stage/stage.json')! == stage_text
	assert hash(root + '/stage/boot.img')! == stage.staged_boot_sha256
	patch(root + '/stage', root + '/build', receipt_sha, hash(baseline)!)!
	updated_stage := json2.decode[Stage](os.read_file(root + '/stage/stage.json')!)!
	assert updated_stage.staged_boot_sha256 != stage.staged_boot_sha256
	assert updated_stage.inputs_sha256 == stage.inputs_sha256
	assert updated_stage.original_modules_sha256 == stage.original_modules_sha256
	assert updated_stage.preserved_modules_sha256 == stage.preserved_modules_sha256
	assert updated_stage.overlay_sha256 == stage.overlay_sha256
	assert updated_stage.staged_efivars_sha256 == stage.staged_efivars_sha256
	assert os.read_file(root + '/stage/stage-before-kernel.json')! == stage_text
	assert os.is_file(root + '/stage/kernel-patch.json')
	if _ := patch(root + '/stage', root + '/build', receipt_sha, hash(baseline)!) {
		return error('second patch of same stage accepted')
	}
	println('BROWSER-KERNEL-PATCH FAT-SELF-TEST PASS pinned build rejection exact kernel readback baseline modules overlay firmware receipts once-only')
}

fn self_test() ! {
	config := '/Vinix\n kernel_path: boot():/boot/vinix\n module_path: boot():/boot/runtime.tar\n'
	assert configure(config)!.modules == ['runtime.tar']
	for bad in [config + '/Other\n', config + ' kernel_path: boot():/boot/vinix\n',
		config + ' module_path: boot():/boot/runtime.tar\n', config.replace('/vinix', '/../vinix'),
		config.replace('/runtime.tar', '/runtime')] {
		if _ := configure(bad) { return error('ambiguous or unsafe configuration accepted') }
	}
	assert !relative('../escape') && !relative('a//b') && !digest_valid('a'.repeat(63))
	root := os.join_path(os.real_path(os.temp_dir()), 'vinix-browser-kernel-patch-' + os.getpid().str())
	if os.exists(root) { return error('self-test path exists') }
	os.mkdir(root)!
	defer { os.rmdir_all(root) or {} }
	os.write_file(root + '/payload', 'exact frozen input\x00bytes')!
	verify_inventory(root, Inventory{ files: {
		'payload': hash(root + '/payload')!
	} })!
	for bad in [Inventory{}, Inventory{ files: {
		'../escape': hash(root + '/payload')!
	} }, Inventory{ files: {
		'payload': '0'.repeat(64)
	} }] {
		if _ := verify_inventory(root, bad) { return error('invalid frozen inventory accepted') }
	}
	os.symlink('payload', root + '/link')!
	if _ := verify_inventory(root, Inventory{ files: {
		'link': hash(root + '/payload')!
	} }) {
		return error('symlink substituted for regular frozen input')
	}
	unlaunched(root)!
	os.write_file(root + '/launch.json', '{}')!
	if _ := unlaunched(root) { return error('historical launched stage accepted') }
	fat_self_test(root)!
	println('BROWSER-KERNEL-PATCH SELF-TEST PASS configuration inventory digest symlink launched-stage guards')
}

fn main() {
	if os.args.len == 2 && os.args[1] == '--self-test' {
		self_test() or {
			eprintln(err)
			exit(1)
		}
		return
	}
	if os.args.len != 4 {
		eprintln('usage: patch-kernel FRESH_STAGE FROZEN_KERNEL_BUILD BUILD_JSON_SHA256')
		exit(2)
	}
	root := external(os.args[1]) or {
		eprintln(err)
		exit(1)
	}
	build_root := external(os.args[2]) or {
		eprintln(err)
		exit(1)
	}
	patch(root, build_root, os.args[3], baseline_sha) or {
		eprintln(err)
		exit(1)
	}
}
