// SPDX-License-Identifier: GPL-2.0-or-later
// A selected copy of one reviewed build. The original complete audit is required.
module main

import crypto.sha256
import json2
import os
import time

const audit_root = '/Users/alex/Library/Caches/vinix-codex/section14/matched-peer-frame-atomic-20261026'
const manifest = '/Users/alex/Library/Caches/vinix-codex/section14/matched-peer-frame-atomic-20261026-seal-01/complete/inventory.json'
const manifest_sum = 'd7764b47d4c617550ed67af5eee5167392f818ea51e884d1a6abaf3469acf118'
const checker = '/Users/alex/Library/Caches/vinix-codex/section14/alloc-track-frame-kernel-20261026-seal-02/frame-page-seal'
const checker_sum = 'fcc0e1f0d557e980a99dbcaf68d45ed8da851b07bf0810e8c99c931c865001b6'
const checker_source = '/Users/alex/code/vinix/tests/kernel-allocs/frame-page-seal.v'
const checker_source_sum = '8cd5e58df42e07760d0e1b73c49807b0ee2c7e353412e7d54aca34a7597577d4'
const source_revision = '9acefa77bee69247c837e97987a2377536aa41cc'
const critical_sources = {
	'kernel/alloctrack/frame_page.v': 'be2b4cee4283cc4c5275cd5a1cb668a12ab2e08300c18a15b4731ca185dad48d'
	'kernel/alloctrack/track_d_alloc_track.v': '23aacc0a9c15cb1f22a6fd808c7b849d7ac203975c10118dbf9a0a509660302e'
	'kernel/file/locks.v': '74067cb8deb1f7d41bfc1deeee51af94b48ece3761078c179ed06a90d7a6a1b6'
	'kernel/memory/slab.v': '5c476a01dab2e01d8b13bcddce5be7fa6505f4e98f51875219bb360ce35a1aa4'
	'kernel/socket/public/public.v': '19b4b0a8fceaf0bbb78957d69025e7a6e8d805b1557d5f9c924067f82a3e372a'
	'kernel/socket/socket.v': '98588cce3eb94e72a89baf181178b92ea4de2a2b304d139c0f79af2571c7c3a8'
	'kernel/socket/unix/unix.v': 'c869568959cd09e16b58dbcc5400b49fdb0a1cb27275d0b73c430dce8f82f810'
}

struct Build {
	elf_path string
	elf_sha256 string
	generated_c_path string
	generated_c_sha256 string
	build_log_path string
	build_log_sha256 string
	build_flags []string
}

struct Audit {
	root string
	manifest_path string
	manifest_sha256 string
	checker_path string
	checker_sha256 string
	checker_source_path string
	checker_source_sha256 string
}

struct Seal {
	format int = 2
	profile string = 'matched-peer-frame-atomic-20261026'
	source_revision string
	source_patch_path string = 'source.patch'
	source_patch_sha256 string
	source_inventory_path string = 'source-inputs.sha256'
	source_inventory_sha256 string
	critical_sources map[string]string
	kernels map[string]Build
	audit Audit
}

fn digest(path string) !string {
	if os.real_path(path) != path || os.lstat(path)!.mode & 0o170000 != 0o100000 {
		return error('requires canonical ordinary file: ' + path)
	}
	mut file := os.open(path)!
	defer { file.close() }
	mut hash := sha256.new()
	defer { unsafe { hash.free() } }
	mut buffer := []u8{len: 1024 * 1024}
	defer { unsafe { buffer.free() } }
	for {
		n := file.read(mut buffer) or { if err is os.Eof { break } else { return err } }
		if n == 0 { break }
		hash.write(buffer[..n])!
	}
	return hash.sum([]u8{}).hex()
}

fn pinned(path string, sum string) ! {
	if digest(path)! != sum { return error('reviewed artifact differs: ' + path) }
}

fn audit_pins() ! {
	pinned(manifest, manifest_sum)!
	pinned(checker, checker_sum)!
	pinned(checker_source, checker_source_sum)!
}

// The pinned checker is a leaf. The qualified V's Process implementation uses
// i32 for waitpid status; polling reaps it, and timeout kills then waits for it.
fn check_audit(output string) ! {
	audit_pins()!
	argv := [checker, 'check', audit_root, manifest]
	os.write_file(output + '/original-check.argv.json', json2.encode(argv) + '\n')!
	mut process := os.new_process(checker)
	defer { process.close() }
	process.set_args(argv[1..])
	process.set_redirect_stdio()
	process.run()
	started := time.sys_mono_now()
	mut timed_out := false
	for process.is_alive() {
		if time.sys_mono_now() - started > i64(300) * time.second {
			timed_out = true
			process.signal_kill()
			break
		}
		time.sleep(10 * time.millisecond)
	}
	process.wait()
	stdout := process.stdout_slurp()
	stderr := process.stderr_slurp()
	os.write_file(output + '/original-check.log', stdout + stderr)!
	os.write_file(output + '/original-check.status.json', json2.encode({
		'exit_code': process.code.str(), 'timed_out': timed_out.str(),
		'pid': process.pid.str(), 'status': process.status.str(),
		'elapsed_ms': ((time.sys_mono_now() - started) / time.millisecond).str()
	}) + '\n')!
	if timed_out || process.code != 0 || stdout != 'FRAME-PAGE COMPLETE STATE CHECK PASS\n' || stderr != '' {
		return error('original complete audit refused; selected copy is incomplete')
	}
	audit_pins()!
}

fn copy_pinned(source string, destination string, sum string) ! {
	pinned(source, sum)!
	os.mkdir_all(os.dir(destination))!
	os.cp(source, destination)!
	os.chmod(destination, int(os.lstat(source)!.mode & 0o7777))!
	if os.lstat(destination)!.nlink != 1 { return error('copy must be independent') }
	pinned(destination, sum)!
	pinned(source, sum)!
}

fn run() ! {
	if os.args.len != 2 { return error('usage: matched-kernel-retain NEW-CANONICAL-OUT') }
	out := os.args[1]
	if !os.is_abs_path(out) || os.exists(out) || os.is_link(out)
		|| os.real_path(os.dir(out)) != os.dir(out) || os.base(out) in ['', '.', '..']
		|| out.starts_with(audit_root + '/') || out.bytes().any(it < 32 || it == 127) {
		return error('requires fresh canonical output outside original audit')
	}
	os.mkdir(out)!
	check_audit(out)!
	build := audit_root + '/build-02'
	if os.read_file(build + '/source-revision.txt')! != source_revision + '\n' {
		return error('reviewed source revision differs')
	}
	// This is deliberately a small selected copy, not a replacement complete
	// bundle. Charge every pathname once, irrespective of physical sharing.
	mut selected_bytes := u64(0)
	for arch in ['aarch64', 'x86_64'] {
		for name in ['bin/vinix', 'obj/blob.c', 'build.log'] {
			selected_bytes += os.lstat(build + '/' + arch + '/' + name)!.size
		}
	}
	for name, _ in critical_sources { selected_bytes += os.lstat(build + '/source/' + name)!.size }
	selected_bytes += os.lstat(build + '/source.patch')!.size + (u64(2) << 20)
	if selected_bytes >= u64(128) << 20 { return error('selected copy exceeds 128MiB admission including 2MiB metadata reserve') }
	patch_sum := 'c1891d5ffe3823d9d7bfe9b3b47ba14fab590f8e8e12f2afb0d47b28cc2bb5f6'
	copy_pinned(build + '/source.patch', out + '/source.patch', patch_sum)!
	mut inventory := []string{}
	mut names := critical_sources.keys()
	names.sort()
	for name in names {
		sum := critical_sources[name]
		copy_pinned(build + '/source/' + name, out + '/source/' + name, sum)!
		inventory << sum + '  ' + name
	}
	os.write_file(out + '/source-inputs.sha256', inventory.join('\n') + '\n')!
	mut kernels := map[string]Build{}
	for arch in ['aarch64', 'x86_64'] {
		arm := arch == 'aarch64'
		entry := Build{
			elf_path: 'kernel-' + arch + '/bin/vinix'
			elf_sha256: if arm { '1111f8d6451a0ab94361c3ebf006e9ceed62baea9dd395ac0a5c3caa7fb3a254' } else { '162008b2cd4bde3cfa5110dacb8caa604c8e27b620a92e3cdec6ef51755dc9b7' }
			generated_c_path: 'kernel-' + arch + '/obj/blob.c'
			generated_c_sha256: if arm { '87166ca286e94f5cf9b827e1ffd09bc8c1b6aebf5994188de0b0e3e30a454855' } else { '1ac1984e66fc210b3049b3e35e93fa4fb922ebf57de734c9fff02e294ded1d34' }
			build_log_path: 'build-' + arch + '.log'
			build_log_sha256: if arm { 'b1b2f3ffb277984da4839f1e0dda970617728c864f44a33960c41ad204b421e7' } else { '3f05a12ff588e2f8ed00a94253a27dc60af6c88741342022042f7177d335b2da' }
			build_flags: ['ARCH=' + arch, 'ALLOC_TRACK=1', 'PROD=true', if arm { 'LIMINE_MP=1' } else { 'LIMINE_MP=0' }]
		}
		actual_argv := json2.decode[[]string](os.read_file(build + '/' + arch + '/build.argv.json')!)!
		for flag in entry.build_flags {
			prefix := flag.all_before('=') + '='
			if actual_argv.filter(it.starts_with(prefix)) != [flag] {
				return error('original build flag differs: ' + flag)
			}
		}
		status := json2.decode[map[string]string](os.read_file(build + '/' + arch + '/build.status.json')!)!
		if status['exit_code'] != '0' || status['reason'] != '' || status['cleanup'] != 'leader reaped; group absent' {
			return error('original build or cleanup did not pass: ' + arch)
		}
		copy_pinned(build + '/' + arch + '/bin/vinix', out + '/' + entry.elf_path, entry.elf_sha256)!
		copy_pinned(build + '/' + arch + '/obj/blob.c', out + '/' + entry.generated_c_path, entry.generated_c_sha256)!
		copy_pinned(build + '/' + arch + '/build.log', out + '/' + entry.build_log_path, entry.build_log_sha256)!
		kernels[arch] = entry
	}
	audit_pins()!
	seal := Seal{
		source_revision: source_revision, source_patch_sha256: patch_sum,
		source_inventory_sha256: digest(out + '/source-inputs.sha256')!,
		critical_sources: critical_sources, kernels: kernels,
		audit: Audit{root: audit_root, manifest_path: manifest, manifest_sha256: manifest_sum,
			checker_path: checker, checker_sha256: checker_sum,
			checker_source_path: checker_source, checker_source_sha256: checker_source_sum}
	}
	os.write_file(out + '/kernel-seal.json', json2.encode(seal) + '\n')!
	println('MATCHED KERNEL SELECTED COPY PASS ' + digest(out + '/kernel-seal.json')!)
}

fn main() { run() or { eprintln(err); exit(1) } }
