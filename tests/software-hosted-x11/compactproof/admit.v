// SPDX-License-Identifier: GPL-2.0-or-later
// Admit the existing compact compositor without relabelling its five-source build.
module compactproof

import crypto.sha256
import json2
import launchproof
import os
import time

const repository = '/Users/alex/code/vinix'
const evidence = '/Users/alex/Library/Caches/vinix-codex/section14'
const compact_root = evidence + '/compact-launch-entry-20261026'
const target_root = compact_root + '/targets01'
const bundle_root = target_root + '/bundle'
const bootstrap_root = compact_root + '/target-bootstrap01'
const complete_root = compact_root + '/target-complete-seals01'
const bundle_sha256 = '965a08c5e673059fcc4f78f2bf45f0c504767ea651dcf01f7d8f0d2b1e1bf337'
const original_checker = evidence + '/alloc-track-frame-kernel-20261026-seal-02/frame-page-seal'
const checker_sha256 = 'fcc0e1f0d557e980a99dbcaf68d45ed8da851b07bf0810e8c99c931c865001b6'
const checker_source = repository + '/tests/kernel-allocs/frame-page-seal.v'
const checker_source_sha256 = '8cd5e58df42e07760d0e1b73c49807b0ee2c7e353412e7d54aca34a7597577d4'
const original_launchproof_sha256 = 'e8ba120b8b4ac08207bd53be979c5d6ea8085eb11df4689025b107ab0f1aeb94'
const historical_compiler = repository + '/build/package-https-runtime-work/toolchain/v'
const hosted_root = evidence + '/package-hosted-launch-options-native-20261026'
const hosted_bundle = evidence + '/package-section14-hosted-options-target-20261026/full-compositor-hosted-options-v2'
const file_limit = u64(64) << 20
const tree_limit = u64(768) << 20
const scan_ns = i64(120) * time.second

// The callback executes only the supplied fixed original check command. It must
// retain the real argv, merged log and {"exit_code":N} from the actual wait.
// Its caller owns admission, deadlines, output bounds and child cleanup using
// the existing controller/supervisor. This module creates no subprocess owner.
pub struct CheckRun {
pub:
	actual_exit int
	argv_path string
	log_path string
	exit_path string
}

pub type OriginalCheck = fn (argv []string, label string) !CheckRun

// Only check_audits can construct a ready token. Reuse it within one admitted
// phase, and obtain a fresh token after producers and guest exit. Static
// assembled()/import_build() calls do not launch repeated expensive audits.
pub struct Audits {
	ready bool
	started i64
	paths map[string]string
	hashes map[string]string
}

struct AuditRecord {
	format int = 1
	scope string = 'Recorded original complete compact checks; static provenance, no new execution'
	source_sha256 string
	paths map[string]string
	hashes map[string]string
}

struct ExitCode {
	exit_code int
}

struct ImportReceipt {
	format int = 1
	method string = 'verified compact compositor copy with separate original hosted proof; no rebuild'
	architecture string
	bundle string
	sealed_manifest_sha256 string
	complete_manifest_sha256 string
	source_sha256 string
	desktop_build_sha256 string
}

struct Bundle {
	sealed map[string]string
	sources map[string]string
	tools map[string]string
	compiler string
	head string
	inputs map[string]string
}

struct Scan {
	started i64 = time.sys_mono_now()
mut:
	entries int
	bytes u64
}

fn need(ok bool, message string) ! {
	if !ok { return error(message) }
}

fn deadline(started i64) ! {
	need(time.sys_mono_now() - started < scan_ns, 'compact proof scan exceeded120s')!
}

fn same_stat(before os.Stat, after os.Stat) bool {
	return before.dev == after.dev && before.inode == after.inode && before.mode == after.mode
		&& before.uid == after.uid && before.gid == after.gid && before.size == after.size
		&& before.nlink == after.nlink && before.mtime == after.mtime && before.ctime == after.ctime
}

fn digest(path string, started i64) !string {
	deadline(started)!
	before := os.lstat(path)!
	need(before.mode & 0o170000 == 0o100000 && before.size <= file_limit,
		'compact proof requires a regular file of at most64MiB: ' + path)!
	mut file := os.open(path)!
	defer { file.close() }
	mut hash := sha256.new()
	defer { unsafe { hash.free() } }
	mut buffer := []u8{len: 1024 * 1024}
	defer { unsafe { buffer.free() } }
	mut length := u64(0)
	for {
		deadline(started)!
		count := file.read(mut buffer) or { if err is os.Eof { break }; return err }
		if count == 0 { break }
		length += u64(count)
		need(length <= before.size, 'compact proof file grew during read: ' + path)!
		hash.write(buffer[..count])!
	}
	need(length == before.size && same_stat(before, os.lstat(path)!),
		'compact proof input changed during read: ' + path)!
	return hash.sum([]u8{}).hex()
}

fn text(path string, started i64) !string {
	before := digest(path, started)!
	value := os.read_file(path)!
	deadline(started)!
	need(sha256.hexhash(value) == before && digest(path, started)! == before,
		'compact proof text changed during read: ' + path)!
	return value
}

fn pin(path string, expected string, started i64) ! {
	need(digest(path, started)! == expected, 'compact proof fixed input differs: ' + path)!
}

fn relative(name string) ! {
	need(name != '' && !name.starts_with('/') && !name.contains('\\')
		&& !name.bytes().any(it < 32 || it == 127), 'unsafe compact proof relative path')!
	need(!name.split('/').any(it in ['', '.', '..']), 'unsafe compact proof path component')!
}

fn mutable_output(path string) ! {
	need(os.is_abs_path(path) && os.real_path(path) == path,
		'compact proof output must be an absolute canonical path')!
	for root in [compact_root, hosted_root, hosted_bundle, os.dir(original_checker)] {
		need(path != root && !path.starts_with(root + '/'),
			'compact proof output cannot change frozen original evidence')!
	}
}

fn walk(root string, prefix string, depth int, mut scan Scan, mut result map[string]string) ! {
	deadline(scan.started)!
	need(depth < 128 && scan.entries < 250000, 'compact proof inventory bound')!
	path := if prefix == '' { root } else { root + '/' + prefix }
	before := os.lstat(path)!
	kind := before.mode & 0o170000
	need(kind in [0o040000, 0o100000], 'compact proof aliases and special files refused: ' + path)!
	scan.entries++
	if kind == 0o040000 {
		mut names := os.ls(path)!
		names.sort()
		for name in names {
			rel := if prefix == '' { name } else { prefix + '/' + name }
			relative(rel)!
			walk(root, rel, depth + 1, mut scan, mut result)!
		}
	} else {
		need(before.size <= tree_limit - scan.bytes, 'compact proof inventory exceeds768MiB')!
		scan.bytes += before.size
		result[prefix] = digest(path, scan.started)!
	}
	need(same_stat(before, os.lstat(path)!), 'compact proof namespace changed during scan: ' + path)!
}

fn inventory(root string) !map[string]string {
	mut result := map[string]string{}
	mut scan := Scan{}
	walk(root, '', 0, mut scan, mut result)!
	return result
}

fn read_map(path string) !map[string]string {
	return json2.decode[map[string]string](text(path, time.sys_mono_now())!, strict: true)
}

fn pair(root string, name string) !map[string]string {
	before := read_map(root + '/' + name + '-before.json')!
	need(before.len > 0 && before == read_map(root + '/' + name + '-after.json')!,
		'compact proof before/after map differs: ' + name)!
	return before
}

fn compact_files() map[string]string {
	return {
		'desktop/software_app.v': '407a33a665d0fd6d9b4c94cd892f05b366ee25f8d387d14e9c37ac04f86467ba'
		'desktop/software_launch.v': 'f6e4377a7fd273af5a10d9ac69a33069f981c9aaa308a28371e16be1e6770be7'
		'desktop/software_launch_navigation.v': '41fdec1ad0ca9591447ae5ac394a21094cddef9708f031134d318c5107544450'
		'desktop/software_package_navigation.v': 'd16f074e4aa8b9d425c29623c794676260aab576b2d3adad5365949ef7707f89'
		'desktop/software_hosted.v': '8e366c7f1a1706e736b3982e8bb842d5cde02edec77f49959f9ffbf0ace6938d'
	}
}

fn manifest_paths() map[string]string {
	return {
		'targets01': '8da3c48959340c6f0d0f1aef0ac032a9f398e2ca43b0785cc8532402f5e35999'
		'target-bootstrap01': '577d9f123d39d830d03111f0cabf2cf4128b16153f6975e0d18416173a2c0b99'
	}
}

fn checker_inputs() !map[string]string {
	started := time.sys_mono_now()
	mut paths := {'checker': original_checker, 'checker-source': checker_source}
	pin(original_checker, checker_sha256, started)!
	pin(checker_source, checker_source_sha256, started)!
	for name, hash in manifest_paths() {
		path := complete_root + '/' + name + '/inventory.json'
		pin(path, hash, started)!
		paths['complete/' + name] = path
	}
	return paths
}

// Run before and after the caller's admitted native phase. The unchanged
// original checker always receives the complete original target/bootstrap roots.
pub fn check_audits(check OriginalCheck) !Audits {
	started := time.sys_mono_now()
	checker_paths := checker_inputs()!
	mut paths := checker_paths.clone()
	for name in ['targets01', 'target-bootstrap01'] {
		root := if name == 'targets01' { target_root } else { bootstrap_root }
		argv := [original_checker, 'check', root, paths['complete/' + name]]
		run := check(argv, 'compact-original-' + name)!
		verify_run(run, argv)!
		paths['audit/' + name + '/argv'] = run.argv_path
		paths['audit/' + name + '/log'] = run.log_path
		paths['audit/' + name + '/exit'] = run.exit_path
	}
	need(checker_inputs()! == checker_paths,
		'original compact checker inputs changed during audits')!
	mut hashes := map[string]string{}
	for name, path in paths { hashes[name] = digest(path, time.sys_mono_now())! }
	return Audits{true, started, paths, hashes}
}

fn verify_run(run CheckRun, argv []string) ! {
	need(run.actual_exit == 0, 'original compact complete audit returned nonzero')!
	for path in [run.argv_path, run.log_path, run.exit_path] { mutable_output(path)! }
	need(run.argv_path != run.log_path && run.argv_path != run.exit_path
		&& run.log_path != run.exit_path, 'compact audit receipt paths must differ')!
	need(json2.decode[[]string](text(run.argv_path, time.sys_mono_now())!, strict: true)! == argv,
		'original compact complete audit argv differs')!
	exit_text := text(run.exit_path, time.sys_mono_now())!
	exit_fields := json2.decode[map[string]json2.Any](exit_text, strict: true)!
	need(exit_fields.len == 1 && 'exit_code' in exit_fields
		&& json2.decode[ExitCode](exit_text, strict: true)!.exit_code == 0,
		'original compact complete audit actual-exit receipt differs')!
	need(text(run.log_path, time.sys_mono_now())! == 'FRAME-PAGE COMPLETE STATE CHECK PASS\n',
		'original compact complete audit marker differs')!
}

pub fn (audits Audits) inputs() !map[string]string {
	need(audits.ready && time.sys_mono_now() - audits.started < i64(1800) * time.second,
		'fresh complete compact audit token required')!
	for name, path in audits.paths {
		pin(path, audits.hashes[name], time.sys_mono_now())!
	}
	return audits.paths.clone()
}

// The source-bound producer exports this only after an actual successful audit
// phase. Retention must bind both record hashes to that producer's qualification
// and input maps; a caller-supplied record alone grants no execution authority.
pub fn (audits Audits) write_record(path string) !string {
	paths := audits.inputs()!
	need(os.is_abs_path(path) && os.real_path(os.dir(path)) == os.dir(path)
		&& !os.exists(path) && !os.is_link(path), 'audit record requires fresh canonical output')!
	mutable_output(os.dir(path))!
	record := AuditRecord{source_sha256: sha256.hexhash(source()), paths: paths, hashes: audits.hashes.clone()}
	value := json2.encode(record) + '\n'
	need(value.len <= 65536, 'audit record exceeds64KiB')!
	os.write_file(path, value)!
	pin(path, sha256.hexhash(value), time.sys_mono_now())!
	return sha256.hexhash(value)
}

fn recorded_inputs(path string) !map[string]string {
	value := text(path, time.sys_mono_now())!
	need(value.len <= 65536, 'recorded compact audit exceeds64KiB')!
	record := json2.decode[AuditRecord](value, strict: true)!
	need(value == json2.encode(record) + '\n' && record.format == 1
		&& record.scope == 'Recorded original complete compact checks; static provenance, no new execution'
		&& record.source_sha256 == sha256.hexhash(source()), 'recorded compact audit header differs')!
	checker_paths := checker_inputs()!
	mut wanted := checker_paths.keys()
	for name in ['targets01', 'target-bootstrap01'] {
		for part in ['argv', 'log', 'exit'] { wanted << 'audit/' + name + '/' + part }
	}
	wanted.sort()
	mut actual := record.paths.keys()
	actual.sort()
	mut hashed := record.hashes.keys()
	hashed.sort()
	need(actual == wanted && hashed == wanted, 'recorded compact audit roles differ')!
	for name, expected in checker_paths {
		need(record.paths[name] == expected, 'recorded original complete input path differs')!
	}
	for name, input in record.paths { pin(input, record.hashes[name], time.sys_mono_now())! }
	for name in ['targets01', 'target-bootstrap01'] {
		root := if name == 'targets01' { target_root } else { bootstrap_root }
		verify_run(CheckRun{
			actual_exit: 0
			argv_path: record.paths['audit/' + name + '/argv']
			log_path: record.paths['audit/' + name + '/log']
			exit_path: record.paths['audit/' + name + '/exit']
		}, [original_checker, 'check', root, checker_paths['complete/' + name]])!
	}
	return record.paths
}

fn sealed_manifest(root string, wanted string) !map[string]string {
	started := time.sys_mono_now()
	pin(root + '/bundle.sha256', wanted, started)!
	mut expected := map[string]string{}
	for line in text(root + '/bundle.sha256', started)!.split_into_lines() {
		fields := line.split('\t')
		need(fields.len == 2 && fields[0].len == 64
			&& fields[0].bytes().all((it >= `0` && it <= `9`) || (it >= `a` && it <= `f`)),
			'invalid compact bundle manifest')!
		relative(fields[1])!
		need(fields[1] !in expected, 'duplicate compact bundle manifest path')!
		expected[fields[1]] = fields[0]
	}
	mut actual := inventory(root)!
	actual.delete('bundle.sha256')
	need(expected.len > 0 && actual == expected, 'complete compact bundle differs')!
	return expected
}

fn u16_at(data []u8, offset int) u16 {
	return u16(data[offset]) | (u16(data[offset + 1]) << 8)
}

fn elf_bytes(data []u8, arch string) ! {
	need(arch in ['aarch64', 'x86_64'], 'unsupported compact ELF architecture')!
	machine := if arch == 'aarch64' { u16(183) } else { u16(62) }
	need(data.len >= 64 && data[..4] == [u8(0x7f), `E`, `L`, `F`] && data[4] == 2
		&& data[5] == 1 && u16_at(data, 16) == 2 && u16_at(data, 18) == machine,
		'compact compositor ELF architecture/type differs')!
	mut offset := u64(0)
	for index in 0 .. 8 { offset |= u64(data[32 + index]) << (8 * index) }
	size := int(data[54]) | (int(data[55]) << 8)
	count := int(data[56]) | (int(data[57]) << 8)
	need(count > 0 && size >= 56 && offset <= u64(data.len)
		&& u64(count) * u64(size) <= u64(data.len) - offset, 'compact ELF program headers differ')!
	mut loads := 0
	for index in 0 .. count {
		start := int(offset) + index * size
		mut kind := u32(0)
		for byte in 0 .. 4 { kind |= u32(data[start + byte]) << (8 * byte) }
		need(kind != 3, 'compact static compositor has PT_INTERP')!
		if kind != 1 { continue }
		mut begin := u64(0)
		mut length := u64(0)
		mut memory := u64(0)
		for byte in 0 .. 8 {
			begin |= u64(data[start + 8 + byte]) << (8 * byte)
			length |= u64(data[start + 32 + byte]) << (8 * byte)
			memory |= u64(data[start + 40 + byte]) << (8 * byte)
		}
		need(begin <= u64(data.len) && length <= u64(data.len) - begin && memory >= length,
			'compact ELF load segment differs')!
		if length > 0 { loads++ }
	}
	need(loads > 0, 'compact compositor has no file-backed load')!
}

fn elf(path string, arch string) ! {
	before := digest(path, time.sys_mono_now())!
	data := os.read_bytes(path)!
	defer { unsafe { data.free() } }
	need(sha256.sum(data).hex() == before && digest(path, time.sys_mono_now())! == before,
		'compact ELF changed during read')!
	elf_bytes(data, arch)!
}

fn admitted(audit_paths map[string]string) !Bundle {
	mut inputs := audit_paths.clone()
	need(sha256.hexhash(launchproof.source()) == original_launchproof_sha256,
		'unchanged original hosted launch proof required')!
	sealed := sealed_manifest(bundle_root, bundle_sha256)!
	need(text(bundle_root + '/production-scope.txt', time.sys_mono_now())! == 'release-save-policy\n',
		'compact build historical five-source scope differs')!
	sources := pair(bundle_root, 'source')!
	need(inventory(bundle_root + '/source')! == sources, 'complete compact captured source differs')!
	production := pair(bundle_root, 'production')!
	need(production.len == 5, 'compact historical production scope count differs')!
	for name in ['desktop/app_selection_migration.v', 'desktop/packagecore/release.c.v',
		'desktop/session_hub.v', 'desktop/software_policy_navigation.v', 'desktop/software_snapshot.v'] {
		matches := production.keys().filter(it == name || it.ends_with('/' + name))
		need(matches.len == 1 && production[matches[0]] == sources[name],
			'compact historical production binding differs')!
	}
	owner := pair(target_root, 'owner-inputs')!
	need(inventory(target_root + '/owner-inputs')! == owner, 'complete compact owner source differs')!
	for name, hash in compact_files() {
		need(sources[name] == hash, 'current compact/hosted source pin differs: ' + name)!
		if name != 'desktop/software_hosted.v' {
			need(owner[name] == hash, 'compact outer four-source binding differs: ' + name)!
		}
		for arch in ['aarch64', 'x86_64'] {
			pin(bundle_root + '/' + arch + '/app/' + os.file_name(name), hash, time.sys_mono_now())!
		}
	}
	for name, hash in {
		'tests/packages/software-compact-target-check.v': 'b3fea2349f41945e55d38c4bf56c38d952a5d0b919538c9670c11aa7ac0cce95'
		'tests/packages/section14-target-build.v': '10dba3cb899c2e86dd58289c38bef94aeea946371859a2f3623ff50e9194b178'
	} { need(owner[name] == hash, 'original compact owner/recipe differs')! }
	pin(bundle_root + '/runner.v', owner['tests/packages/section14-target-build.v'], time.sys_mono_now())!
	pin(bootstrap_root + '/owner', 'd49821560a91a989a14507a8ff6e11d7a30e780355f7def37856a891a13f2c0d', time.sys_mono_now())!
	pin(target_root + '/result.json', '046d39b7b0311e609c7d040637140e7b63916f51a33a8efd3551245a0b8fe7fb', time.sys_mono_now())!
	for name, limit in {'runner.build.log': '240', 'target.log': '1800', 'original-check.log': '240'} {
		receipt := read_map(target_root + '/' + name + '.exit.json')!
		need(receipt['exit'] == '0' && receipt['refusal'] == '' && receipt['limit_seconds'] == limit
			&& receipt['cleanup'] == 'private group absent; sole reap complete; ECHILD',
			'compact original phase/cleanup receipt differs')!
	}
	need(text(target_root + '/original-check.log', time.sys_mono_now())!
		== 'SECTION14 TARGET bundle verified ' + bundle_sha256 + '\n',
		'compact original recipe check marker differs')!
	tools := pair(bundle_root, 'tools')!
	owner_tools := pair(target_root, 'owner-tools')!
	for values in [tools, owner_tools] {
		for path, hash in values { pin(os.real_path(path), hash, time.sys_mono_now())! }
	}
	compilers := tools.keys().filter(it.ends_with('/v'))
	need(compilers.len == 1, 'compact original compiler binding differs')!
	pin(bundle_root + '/tool-executables/v', tools[compilers[0]], time.sys_mono_now())!
	for name in ['clang', 'ld.lld'] {
		need(digest(bundle_root + '/tool-executables/' + name, time.sys_mono_now())! in tools.values(),
			'compact captured executable differs')!
	}
	for arch in ['aarch64', 'x86_64'] {
		generated := pair(bundle_root, arch + '/generated')!
		need(generated.len == 3, 'compact generated source count differs')!
		for name in ['desktop.c', 'execinfo.c', 'presenter.c'] {
			pin(bundle_root + '/' + arch + '/app/' + name, generated[name], time.sys_mono_now())!
		}
		elf(bundle_root + '/' + arch + '/vinix-desktop', arch)!
	}
	for name in ['owner-inputs-before.json', 'owner-inputs-after.json', 'owner-tools-before.json',
		'owner-tools-after.json', 'result.json', 'original-check.log'] {
		inputs['compact/outer/' + name] = target_root + '/' + name
	}
	for name in sealed.keys() { inputs['compact/bundle/' + name] = bundle_root + '/' + name }
	inputs['compact/bundle.sha256'] = bundle_root + '/bundle.sha256'
	inputs['compact/original-owner'] = bootstrap_root + '/owner'
	for path in tools.keys() { inputs['compact/original-tool/' + path] = path }
	head := text(bundle_root + '/repository-head.log', time.sys_mono_now())!.trim_space().split_into_lines().last()
	need(head.len == 40 && head.bytes().all((it >= `0` && it <= `9`) || (it >= `a` && it <= `f`)),
		'compact original repository revision differs')!
	return Bundle{sealed, sources, tools, compilers[0], head, inputs}
}

fn build_manifest(bundle Bundle, arch string) !map[string]string {
	need(arch in ['aarch64', 'x86_64'], 'unsupported compact architecture')!
	mut result := bundle.sources.clone()
	result['compiler'] = bundle.tools[bundle.compiler]
	result['repository-head'] = bundle.head
	for name in ['app/desktop.c', 'app/execinfo.c', 'app/presenter.c', 'vinix-desktop'] {
		result[name] = bundle.sealed[arch + '/' + name] or { return error('missing compact compositor output') }
	}
	return result
}

// Copy current compact compositor/source bytes. The original hosted proof and
// bridge remain separate inputs, and neither original bundle is rewritten.
pub fn import_build(arch string, destination string, audits Audits) !string {
	bundle := admitted(audits.inputs()!)!
	expected := build_manifest(bundle, arch)!
	need(os.is_abs_path(destination) && os.real_path(os.dir(destination)) == os.dir(destination)
		&& !os.exists(destination) && !os.is_link(destination), 'compact import requires a new canonical ordinary parent')!
	need(destination != compact_root && !destination.starts_with(compact_root + '/')
		&& destination != hosted_bundle && !destination.starts_with(hosted_bundle + '/'),
		'compact import cannot write inside original evidence')!
	for root in [hosted_root, os.dir(original_checker)] {
		need(destination != root && !destination.starts_with(root + '/'),
			'compact import cannot change frozen original evidence')!
	}
	os.mkdir(destination, mode: 0o700)!
	// Failed copies stay available for diagnosis; no evidence is auto-deleted.
	os.cp_all(bundle_root + '/source', destination + '/source', false)!
	need(inventory(destination + '/source')! == bundle.sources, 'copied compact sources differ')!
	os.mkdir(destination + '/app')!
	for name in ['app/desktop.c', 'app/execinfo.c', 'app/presenter.c', 'vinix-desktop'] {
		os.cp(bundle_root + '/' + arch + '/' + name, destination + '/' + name)!
		pin(destination + '/' + name, expected[name], time.sys_mono_now())!
	}
	os.write_file(destination + '/desktop-build.json', json2.encode(expected) + '\n')!
	os.write_file(destination + '/import.json', json2.encode(ImportReceipt{
		architecture: arch
		bundle: bundle_root
		sealed_manifest_sha256: bundle_sha256
		complete_manifest_sha256: manifest_paths()['targets01']
		source_sha256: sha256.hexhash(source())
		desktop_build_sha256: digest(destination + '/desktop-build.json', time.sys_mono_now())!
	}) + '\n')!
	pin(bundle_root + '/bundle.sha256', bundle_sha256, time.sys_mono_now())!
	return bundle_sha256
}

// Admit current compact compositor and, independently, the unchanged original
// hosted bundle/import and historical assembled stage. All returned paths must
// enter the controller's before/after input maps. The caller also records the
// fresh complete-audit token's argv/log/actual-exit paths.
pub fn assembled(desktop string, stage string, arch string, compiler string, audits Audits) !map[string]string {
	bundle := admitted(audits.inputs()!)!
	return assembled_inputs(bundle, desktop, stage, arch, compiler)
}

fn assembled_inputs(bundle Bundle, desktop string, stage string, arch string, compiler string) !map[string]string {
	expected := build_manifest(bundle, arch)!
	receipt_text := text(desktop + '/import.json', time.sys_mono_now())!
	receipt := json2.decode[ImportReceipt](receipt_text, strict: true)!
	need(receipt_text == json2.encode(receipt) + '\n' && receipt == ImportReceipt{
		architecture: arch
		bundle: bundle_root
		sealed_manifest_sha256: bundle_sha256
		complete_manifest_sha256: manifest_paths()['targets01']
		source_sha256: sha256.hexhash(source())
		desktop_build_sha256: digest(desktop + '/desktop-build.json', time.sys_mono_now())!
	}, 'compact imported receipt differs')!
	need(read_map(desktop + '/desktop-build.json')! == expected
		&& inventory(desktop + '/source')! == bundle.sources, 'compact imported sources/build receipt differ')!
	mut result := launchproof.assembled(hosted_root + '/import-' + arch, stage, arch, compiler)!
	for name, path in bundle.inputs { result[name] = path }
	result['compact/import.json'] = desktop + '/import.json'
	result['compact/desktop-build.json'] = desktop + '/desktop-build.json'
	for name in bundle.sources.keys() { result['compact/desktop/source/' + name] = desktop + '/source/' + name }
	for name in ['app/desktop.c', 'app/execinfo.c', 'app/presenter.c', 'vinix-desktop'] {
		pin(desktop + '/' + name, expected[name], time.sys_mono_now())!
		result['compact/desktop/' + name] = desktop + '/' + name
	}
	return result
}

// Static retention/replay of a source-bound producer's distinct pre/post audit
// records. This launches no checker and makes no claim of new audit execution.
// The retainer must first bind these exact record hashes to the producer's
// successful qualification and complete input maps, as it does every new proof.
pub fn recorded_assembled(desktop string, stage string, arch string, compiler string,
	before_record string, before_sha256 string, after_record string, after_sha256 string) !map[string]string {
	need(before_record != after_record, 'distinct producer pre/post audit records required')!
	pin(before_record, before_sha256, time.sys_mono_now())!
	pin(after_record, after_sha256, time.sys_mono_now())!
	before := recorded_inputs(before_record)!
	after := recorded_inputs(after_record)!
	for name, path in before {
		if name.starts_with('audit/') {
			need(path != after[name], 'producer pre/post audits reused an output path')!
		}
	}
	bundle := admitted(before)!
	mut result := assembled_inputs(bundle, desktop, stage, arch, compiler)!
	result['compact/audit-record/before'] = before_record
	result['compact/audit-record/after'] = after_record
	for name, path in after { result['compact/post/' + name] = path }
	return result
}

// Optional reuse of the separately qualified real bridge. This validates the
// entire unchanged hosted proof and its restored historical stage first.
pub fn bridge(arch string, audits Audits) !string {
	audits.inputs()!
	need(arch in ['aarch64', 'x86_64']
		&& sha256.hexhash(launchproof.source()) == original_launchproof_sha256,
		'unsupported bridge architecture or changed original hosted proof')!
	launchproof.assembled(hosted_root + '/import-' + arch,
		hosted_root + '/restored-stage-' + arch, arch, historical_compiler)!
	path := hosted_bundle + '/' + arch + '/bridge/bridge'
	pin(path, if arch == 'aarch64' { '7f3f29c0b40ff3a7d841386f7833a94f7d4cdfec4a5b98f1c7e5dd9e50fcc019' }
		else { '5d63f0d9fdc31b74b92f2658e5244320e46090c4ee344dcc9d2b183215e87c7e' }, time.sys_mono_now())!
	return path
}

pub fn source() string { return $embed_file('admit.v').to_string() }
