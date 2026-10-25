// SPDX-License-Identifier: GPL-2.0-or-later
// Import a supplemental graphical build by verified copy, without rebuilding it.
module main

import crypto.sha256
import json2
import os

struct ImportReceipt {
	format int = 1
	method string = 'verified copy of sealed supplemental compositor build; no rebuild'
	architecture string
	bundle string
	sealed_manifest string
	sealed_manifest_sha256 string
	compiler_path string
	receipts map[string]string
	desktop_build_sha256 string
}

fn sha(path string) !string {
	mut file := os.open(path)!
	defer { file.close() }
	mut sum := sha256.new()
	defer { unsafe { sum.free() } }
	mut buffer := []u8{len: 1024 * 1024}
	for {
		count := file.read(mut buffer) or { if err is os.Eof { break } else { return err } }
		if count == 0 { break }
		sum.write(buffer[..count])!
	}
	return sum.sum([]u8{}).hex()
}

fn hex(value string, length int) bool {
	if value.len != length { return false }
	for byte in value.bytes() {
		if (byte < `0` || byte > `9`) && (byte < `a` || byte > `f`) { return false }
	}
	return true
}

fn relative(name string) ! {
	if name.starts_with('/') { return error('absolute sealed path') }
	for part in name.split('/') {
		if part in ['', '.', '..'] { return error('unsafe sealed path: ' + name) }
	}
}

fn inventory(root string) !map[string]string {
	mut result := map[string]string{}
	for path in os.walk_ext(root, '') {
		if os.is_file(path) { result[path[root.len + 1..]] = sha(path)! }
	}
	return result
}

fn same(expected map[string]string, actual map[string]string) ! {
	if expected.len == 0 || expected.len != actual.len { return error('receipt file count differs') }
	for name, digest in expected {
		if !hex(digest, 64) || actual[name] != digest { return error('receipt digest differs: ' + name) }
	}
}

fn pair(bundle string, name string) !map[string]string {
	before := json2.decode[map[string]string](os.read_file(bundle + '/' + name + '-before.json')!)!
	after := json2.decode[map[string]string](os.read_file(bundle + '/' + name + '-after.json')!)!
	same(before, after)!
	return before
}

fn static_elf(path string, arch string) ! {
	data := os.read_bytes(path)!
	machine := if arch == 'aarch64' { u16(183) } else { u16(62) }
	if data.len < 64 || data[..4] != [u8(0x7f), `E`, `L`, `F`] || data[4] != 2 || data[5] != 1 ||
		data[16] != 2 || data[17] != 0 || (u16(data[18]) | (u16(data[19]) << 8)) != machine {
		return error('ELF architecture differs')
	}
	mut offset := u64(0)
	for index in 0 .. 8 { offset |= u64(data[32 + index]) << (8 * index) }
	size := int(data[54]) | (int(data[55]) << 8)
	count := int(data[56]) | (int(data[57]) << 8)
	if count == 0 || size < 56 || offset > u64(data.len) || u64(count) * u64(size) > u64(data.len) - offset {
		return error('invalid ELF program headers')
	}
	mut loads := 0
	for index in 0 .. count {
		start := int(offset) + index * size
		kind := u32(data[start]) | (u32(data[start + 1]) << 8) | (u32(data[start + 2]) << 16) | (u32(data[start + 3]) << 24)
		if kind == 3 { return error('supplemental compositor has an ELF interpreter') }
		if kind == 1 { loads++ }
	}
	if loads == 0 { return error('supplemental compositor has no ELF load segment') }
}

fn main() {
	import_build() or { eprintln(err); exit(1) }
}

fn import_build() ! {
	mut options := map[string]string{}
	for argument in os.args[1..] {
		name := argument.all_before('=')
		if !argument.contains('=') || name !in ['--bundle', '--arch', '--out'] || name in options {
			return error('use --bundle=ABS --arch=aarch64|x86_64 --out=NEW')
		}
		options[name] = argument.all_after('=')
	}
	if options.len != 3 || !options['--bundle'].starts_with('/') || options['--arch'] !in ['aarch64', 'x86_64'] {
		return error('use --bundle=ABS --arch=aarch64|x86_64 --out=NEW')
	}
	bundle := os.real_path(options['--bundle'])
	out := os.abs_path(options['--out'])
	arch := options['--arch']
	if options['--out'] == '' || os.exists(out) || os.is_link(out) || out.starts_with(bundle + '/') {
		return error('output must be new and outside the sealed bundle')
	}
	mut ancestor := os.dir(out)
	for !os.exists(ancestor) { ancestor = os.dir(ancestor) }
	parent := os.real_path(ancestor)
	if parent == bundle || parent.starts_with(bundle + '/') { return error('output resolves inside the sealed bundle') }
	seal := sha(bundle + '/bundle.sha256')!
	mut sealed := map[string]string{}
	for line in os.read_file(bundle + '/bundle.sha256')!.split_into_lines() {
		fields := line.split('\t')
		if fields.len != 2 || !hex(fields[0], 64) || fields[1] in sealed { return error('invalid sealed manifest') }
		relative(fields[1])!
		sealed[fields[1]] = fields[0]
	}
	mut actual := inventory(bundle)!
	actual.delete('bundle.sha256')
	same(sealed, actual)!
	if os.read_file(bundle + '/production-scope.txt')!.trim_space() != 'release-save-policy-repository' {
		return error('requires the complete six-source sibling bundle')
	}
	sources := pair(bundle, 'source')!
	same(sources, inventory(bundle + '/source')!)!
	production := pair(bundle, 'production')!
	if production.len != 6 { return error('requires six production source pins') }
	for name in ['software_snapshot.v', 'software_policy_navigation.v', 'software_repository_navigation.v',
		'packagecore/release.c.v', 'app_selection_migration.v', 'session_hub.v'] {
		matches := production.keys().filter(it.ends_with('/desktop/' + name))
		if matches.len != 1 || production[matches[0]] != sources['desktop/' + name] { return error('production pin differs: ' + name) }
	}
	tools := pair(bundle, 'tools')!
	for path, digest in tools {
		if !path.starts_with('/') || sha(path)! != digest { return error('original tool differs: ' + path) }
	}
	compilers := tools.keys().filter(it.ends_with('/v'))
	if compilers.len != 1 { return error('requires exactly one frozen V compiler') }
	if sha(bundle + '/tool-executables/v')! != tools[compilers[0]] { return error('frozen V compiler copy differs') }
	for name in ['v', 'clang', 'ld.lld'] {
		if sha(bundle + '/tool-executables/' + name)! !in tools.values() { return error('frozen tool copy differs: ' + name) }
	}
	for target in ['aarch64', 'x86_64'] {
		generated := pair(bundle, target + '/generated')!
		if generated.len != 3 { return error('requires three generated compositor files') }
		for name in ['desktop.c', 'execinfo.c', 'presenter.c'] {
			if generated[name] != sha(bundle + '/' + target + '/app/' + name)! { return error('generated file differs: ' + name) }
		}
		static_elf(bundle + '/' + target + '/vinix-desktop', target)!
	}
	head := os.read_file(bundle + '/repository-head.log')!.trim_space().split_into_lines().last()
	if !hex(head, 40) { return error('repository head receipt differs') }
	os.mkdir_all(os.dir(out))!
	os.mkdir(out)!
	mut complete := false
	defer { if !complete { os.rmdir_all(out) or {} } }
	os.cp_all(bundle + '/source', out + '/source', true)!
	same(sources, inventory(out + '/source')!)!
	os.mkdir(out + '/app')!
	mut manifest := sources.clone()
	manifest['compiler'] = tools[compilers[0]]
	manifest['repository-head'] = head
	for name in ['app/desktop.c', 'app/execinfo.c', 'app/presenter.c', 'vinix-desktop'] {
		os.cp(bundle + '/' + arch + '/' + name, out + '/' + name)!
		manifest[name] = sha(out + '/' + name)!
		if manifest[name] != sealed[arch + '/' + name] { return error('copied artifact differs: ' + name) }
	}
	if sha(bundle + '/bundle.sha256')! != seal { return error('sealed manifest changed during import') }
	os.write_file(out + '/desktop-build.json', json2.encode(manifest) + '\n')!
	mut receipts := map[string]string{}
	for name in sealed.keys().filter(it.ends_with('-before.json') || it.ends_with('-after.json') || it == 'repository-head.log' || it == 'production-scope.txt') {
		if sha(bundle + '/' + name)! != sealed[name] { return error('input receipt changed during import: ' + name) }
		receipts[name] = sealed[name]
	}
	os.write_file(out + '/import.json', json2.encode(ImportReceipt{ architecture: arch, bundle: bundle,
		sealed_manifest: bundle + '/bundle.sha256', sealed_manifest_sha256: seal, compiler_path: compilers[0],
		receipts: receipts, desktop_build_sha256: sha(out + '/desktop-build.json')! }) + '\n')!
	complete = true
	println('SOFTWARE RELEASE ROUTING IMPORT PASS ' + arch + ': verified sealed supplemental build ' + seal)
}
