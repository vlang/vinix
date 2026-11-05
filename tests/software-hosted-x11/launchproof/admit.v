// SPDX-License-Identifier: GPL-2.0-or-later
// Exact supplemental build admission for the explicit launch-options scenario.
module launchproof

import json2
import os
import proof

const scope = 'release-save-policy-repository-hosted-launch-options'
// The complete eleven-source target build is retained separately from the
// historical five/six-source archives; supplied manifests cannot choose trust.
const reviewed_bundle_sha256 = 'c5b72beb336e451695c58094d8f77ed850014ee180fe609bf5d05582b267834d'
// The separately qualified a54cd7 stage predates the current target compiler.
// Its unchanged receipt pins this retained compiler's bytes independently.
const historical_compiler = '/Users/alex/code/vinix/build/package-https-runtime-work/toolchain/v'
const production_names = ['desktop/software_snapshot.v', 'desktop/software_policy_navigation.v',
	'desktop/software_repository_navigation.v', 'desktop/packagecore/release.c.v',
	'desktop/app_selection_migration.v', 'desktop/session_hub.v', 'desktop/software_app.v',
	'desktop/software_launch.v', 'desktop/software_hosted.v',
	'build-support/xorg-server/winehost/core.v', 'build-support/xorg-server/winehost/package.v']

struct ImportReceipt {
	format int = 1
	method string = 'verified copy of sealed hosted launch-options compositor build; no rebuild'
	architecture string
	bundle string
	sealed_manifest string
	sealed_manifest_sha256 string
	compiler_path string
	receipts map[string]string
	desktop_build_sha256 string
}

struct Bundle {
	root string
	seal string
	sealed map[string]string
	sources map[string]string
	tools map[string]string
	compiler string
	head string
	receipts map[string]string
}

fn hex(value string, length int) bool {
	if value.len != length { return false }
	for byte in value {
		if (byte < `0` || byte > `9`) && (byte < `a` || byte > `f`) { return false }
	}
	return true
}

fn relative(name string) ! {
	if name.starts_with('/') || name.contains('\\') || name.contains('\x00') || name.contains('\n') || name.contains('\r') || name.contains('\t') {
		return error('unsafe supplemental path: ' + name)
	}
	for part in name.split('/') {
		if part in ['', '.', '..'] { return error('unsafe supplemental path: ' + name) }
	}
}

fn inventory(root string) !map[string]string {
	mut result := map[string]string{}
	walk(root, '', mut result)!
	return result
}

fn walk(root string, prefix string, mut result map[string]string) ! {
	for name in os.ls(root + '/' + prefix)! {
		rel := prefix + name
		relative(rel)!
		path := root + '/' + rel
		if os.is_link(path) { return error('supplemental archive contains a file alias: ' + rel) }
		if os.is_dir(path) { walk(root, rel + '/', mut result)! }
		else if os.is_file(path) { result[rel] = proof.digest(path)! }
		else { return error('unsupported supplemental input: ' + rel) }
	}
}

fn same(expected map[string]string, actual map[string]string) ! {
	if expected.len == 0 || expected.len != actual.len { return error('supplemental receipt file count differs') }
	for name, digest in expected {
		if !hex(digest, 64) || actual[name] or { '' } != digest { return error('supplemental receipt digest differs: ' + name) }
	}
}

fn read_map(path string) !map[string]string {
	return json2.decode[map[string]string](os.read_file(path)!)
}

fn pair(bundle string, name string) !map[string]string {
	before := read_map(bundle + '/' + name + '-before.json')!
	same(before, read_map(bundle + '/' + name + '-after.json')!)!
	return before
}

fn u16_at(data []u8, offset int) u16 { return u16(data[offset]) | (u16(data[offset + 1]) << 8) }
fn u32_at(data []u8, offset int) u32 {
	mut value := u32(0)
	for index in 0 .. 4 { value |= u32(data[offset + index]) << (8 * index) }
	return value
}
fn u64_at(data []u8, offset int) u64 {
	mut value := u64(0)
	for index in 0 .. 8 { value |= u64(data[offset + index]) << (8 * index) }
	return value
}

fn elf_bytes(data []u8, arch string, dynamic bool) ! {
	machine := if arch == 'aarch64' { u16(183) } else if arch == 'x86_64' { u16(62) } else { return error('unsupported supplemental architecture') }
	if data.len < 64 || data[..4] != [u8(0x7f), `E`, `L`, `F`] || data[4] != 2 || data[5] != 1 ||
		u16_at(data, 18) != machine || u16_at(data, 16) != if dynamic { u16(3) } else { u16(2) } {
		return error('supplemental ELF architecture or type differs')
	}
	offset := u64_at(data, 32)
	size := int(u16_at(data, 54))
	count := int(u16_at(data, 56))
	if count == 0 || size < 56 || offset > u64(data.len) || u64(count) * u64(size) > u64(data.len) - offset {
		return error('invalid supplemental ELF program headers')
	}
	mut loads := 0
	mut interpreters := 0
	for index in 0 .. count {
		start := int(offset) + index * size
		kind := u32_at(data, start)
		if kind !in [u32(1), 3] { continue }
		begin := u64_at(data, start + 8)
		length := u64_at(data, start + 32)
		if begin > u64(data.len) || length > u64(data.len) - begin {
			return error('supplemental ELF segment extends beyond the file')
		}
		if kind == 1 {
			if u64_at(data, start + 40) < length { return error('invalid supplemental ELF load segment') }
			if length > 0 { loads++ }
		} else {
			if !dynamic || length == 0 || length > 256 { return error('supplemental ELF interpreter differs') }
			expected := '/lib/ld-musl-' + arch + '.so.1\x00'
			if data[int(begin)..int(begin + length)].bytestr() != expected { return error('supplemental ELF interpreter differs') }
			interpreters++
		}
	}
	if loads == 0 || interpreters != if dynamic { 1 } else { 0 } { return error('supplemental ELF load/interpreter count differs') }
}

fn elf(path string, arch string, dynamic bool) ! { elf_bytes(os.read_bytes(path)!, arch, dynamic)! }

fn admitted_bundle(directory string) !Bundle {
	if !hex(reviewed_bundle_sha256, 64) { return error('hosted launch-options target bundle has no reviewed seal') }
	if !directory.starts_with('/') || os.is_link(directory) { return error('supplemental bundle path must be an absolute directory') }
	root := os.real_path(directory)
	seal := proof.digest(root + '/bundle.sha256')!
	if seal != reviewed_bundle_sha256 { return error('hosted launch-options supplemental seal differs') }
	mut sealed := map[string]string{}
	for line in os.read_file(root + '/bundle.sha256')!.split_into_lines() {
		fields := line.split('\t')
		if fields.len != 2 || !hex(fields[0], 64) || fields[1] in sealed { return error('invalid supplemental sealed manifest') }
		relative(fields[1])!
		sealed[fields[1]] = fields[0]
	}
	mut actual := inventory(root)!
	actual.delete('bundle.sha256')
	same(sealed, actual)!
	if os.read_file(root + '/production-scope.txt')! != scope + '\n' { return error('hosted launch-options production scope differs') }
	sources := pair(root, 'source')!
	same(sources, inventory(root + '/source')!)!
	production := pair(root, 'production')!
	if production.len != production_names.len { return error('hosted launch-options production count differs') }
	for name in production_names {
		matches := production.keys().filter(it == name || it.ends_with('/' + name))
		if matches.len != 1 || production[matches[0]] != sources[name] { return error('hosted launch-options production pin differs: ' + name) }
	}
	tools := pair(root, 'tools')!
	for path, expected in tools {
		if !path.starts_with('/') || proof.digest(path)! != expected { return error('supplemental original tool differs: ' + path) }
	}
	compilers := tools.keys().filter(it.ends_with('/v'))
	if compilers.len != 1 || proof.digest(root + '/tool-executables/v')! != tools[compilers[0]] {
		return error('supplemental frozen V compiler differs')
	}
	for name in ['clang', 'ld.lld'] {
		if proof.digest(root + '/tool-executables/' + name)! !in tools.values() { return error('supplemental frozen tool differs: ' + name) }
	}
	for arch in ['aarch64', 'x86_64'] {
		generated := pair(root, arch + '/generated')!
		if generated.len != 3 { return error('supplemental compositor generated count differs') }
		for name in ['desktop.c', 'execinfo.c', 'presenter.c'] {
			if generated[name] != proof.digest(root + '/' + arch + '/app/' + name)! { return error('supplemental compositor generated pin differs: ' + name) }
		}
		bridge := pair(root, arch + '/bridge-generated')!
		if bridge.len != 1 || bridge['bridge.c'] or { '' } != proof.digest(root + '/' + arch + '/bridge/bridge.c')! {
			return error('supplemental bridge generated pin differs')
		}
		pair(root, arch + '/bridge-runtime')!
		// Runtime aliases are recorded as link targets rather than hashes. The
		// frozen bundle itself contains only ordinary files and directories.
		links := read_map(root + '/' + arch + '/bridge-runtime-links-before.json')!
		if links.len == 0 || links != read_map(root + '/' + arch + '/bridge-runtime-links-after.json')! {
			return error('supplemental bridge runtime aliases differ')
		}
		for name, source in {'winehost': 'build-support/xorg-server/winehost', 'x11auth': 'tools/packages/x11auth'} {
			same(inventory(root + '/source/' + source)!, inventory(root + '/' + arch + '/bridge/project/' + name)!)!
		}
		if arch + '/bridge/link.map' !in sealed { return error('supplemental bridge link map missing') }
		for name in ['generate-command.log', 'clang-command.log', 'gpucore-command.log', 'execinfocore-command.log',
			'bridge-generate-command.log', 'bridge-clang-command.log'] {
			if arch + '/' + name !in sealed { return error('supplemental build command missing: ' + name) }
		}
		elf(root + '/' + arch + '/vinix-desktop', arch, false)!
		elf(root + '/' + arch + '/bridge/bridge', arch, true)!
		if 'tests/packages/software_image_fixture.v' in sources {
			image := read_map(root + '/' + arch + '/image-generated.json')!
			if image.len != 1 || image['software-image.c'] or { '' } != proof.digest(root + '/' + arch + '/image-app/software-image.c')! {
				return error('supplemental image generated pin differs')
			}
			for name in ['image-generate-command.log', 'image-clang-command.log'] {
				if arch + '/' + name !in sealed { return error('supplemental image command missing: ' + name) }
			}
			elf(root + '/' + arch + '/software-image', arch, false)!
		}
	}
	head := os.read_file(root + '/repository-head.log')!.trim_space().split_into_lines().last()
	if !hex(head, 40) { return error('supplemental repository head differs') }
	mut receipts := map[string]string{}
	for name, hash in sealed {
		if name.ends_with('-before.json') || name.ends_with('-after.json') || name in ['repository-head.log', 'production-scope.txt'] {
			receipts[name] = hash
		}
	}
	return Bundle{ root: root, seal: seal, sealed: sealed, sources: sources, tools: tools,
		compiler: compilers[0], head: head, receipts: receipts }
}

fn manifest(bundle Bundle, arch string) !map[string]string {
	if arch !in ['aarch64', 'x86_64'] { return error('unsupported supplemental architecture') }
	mut result := bundle.sources.clone()
	result['compiler'] = bundle.tools[bundle.compiler]
	result['repository-head'] = bundle.head
	for name in ['app/desktop.c', 'app/execinfo.c', 'app/presenter.c', 'vinix-desktop'] {
		result[name] = bundle.sealed[arch + '/' + name] or { return error('required supplemental compositor output absent') }
	}
	return result
}

// Import is a byte-for-byte verified copy. It never reruns or relabels a build.
pub fn import_build(directory string, arch string, destination string) !string {
	bundle := admitted_bundle(directory)!
	expected := manifest(bundle, arch)!
	out := os.abs_path(destination)
	if destination == '' || os.exists(out) || os.is_link(out) { return error('supplemental output must be new') }
	mut ancestor := os.dir(out)
	for !os.exists(ancestor) { ancestor = os.dir(ancestor) }
	parent := os.real_path(ancestor)
	if parent == bundle.root || parent.starts_with(bundle.root + '/') { return error('supplemental output resolves inside sealed bundle') }
	os.mkdir_all(os.dir(out))!
	os.mkdir(out)!
	mut complete := false
	defer { if !complete { os.rmdir_all(out) or {} } }
	os.cp_all(bundle.root + '/source', out + '/source', true)!
	same(bundle.sources, inventory(out + '/source')!)!
	os.mkdir(out + '/app')!
	for name in ['app/desktop.c', 'app/execinfo.c', 'app/presenter.c', 'vinix-desktop'] {
		os.cp(bundle.root + '/' + arch + '/' + name, out + '/' + name)!
		if proof.digest(out + '/' + name)! != expected[name] { return error('copied supplemental output differs: ' + name) }
	}
	if proof.digest(bundle.root + '/bundle.sha256')! != bundle.seal { return error('supplemental seal changed during import') }
	os.write_file(out + '/desktop-build.json', json2.encode(expected) + '\n')!
	os.write_file(out + '/import.json', json2.encode(ImportReceipt{ architecture: arch, bundle: bundle.root,
		sealed_manifest: bundle.root + '/bundle.sha256', sealed_manifest_sha256: bundle.seal,
		compiler_path: bundle.compiler, receipts: bundle.receipts,
		desktop_build_sha256: proof.digest(out + '/desktop-build.json')! }) + '\n')!
	complete = true
	return bundle.seal
}

fn historical_stage(stage string, arch string, compiler string) !map[string]string {
	if arch !in ['aarch64', 'x86_64'] { return error('unsupported assembled architecture') }
	expected := if arch == 'aarch64' { '687011a8471aa12689300e7932ca3f7bc18359817a7c37ae90ac2c5d010ba40e' }
		else { 'a967f7bbd29690cc74e63193545199d1dd7676274de29d2dad91f03c0fdd0762' }
	if proof.digest(stage + '/stage-build.json')! != expected { return error('assembled input digest differs: stage receipt') }
	mut result := {'assembled/stage/stage-build.json': stage + '/stage-build.json'}
	for name, hash in read_map(stage + '/stage-build.json')! {
		if name == 'repository-head' {
			if hash != 'a54cd7cf7b32d2aebd3df32e236522f3d614a4f0' { return error('unexpected assembled source commit') }
			continue
		}
		relative(name)!
		path := if name == 'compiler' { compiler } else if name == 'driver' { stage + '/cross-shim' }
			else if name.starts_with('usr/') { stage + '/root/' + name } else { stage + '/' + name }
		if proof.digest(path)! != hash { return error('assembled input digest differs: stage/' + name) }
		result['assembled/stage/' + name] = path
	}
	mut expected_sources := map[string]string{}
	for name, hash in read_map(stage + '/source.json')! {
		relative(name)!
		path := stage + '/source/' + name
		if proof.digest(path)! != hash { return error('assembled input digest differs: stage/source/' + name) }
		expected_sources[name] = path
		result['assembled/stage/source/' + name] = path
	}
	mut actual_sources := map[string]string{}
	proof.inventory(stage + '/source', '', mut actual_sources)!
	for generated in ['tools/accounts/stage.c', 'tools/packages/stage.c'] { actual_sources.delete(generated) }
	if actual_sources != expected_sources { return error('assembled stage source inventory differs') }
	return result
}

// The new imported desktop and the unchanged historical stage are admitted
// separately. Every returned path must enter the caller's before/after pins.
pub fn assembled(desktop string, stage string, arch string, compiler string) !map[string]string {
	if arch !in ['aarch64', 'x86_64'] { return error('unsupported supplemental architecture') }
	text := os.read_file(desktop + '/import.json')!
	fields := json2.decode[map[string]json2.Any](text)!
	if fields.len != 9 || fields.keys().any(it !in ['format', 'method', 'architecture', 'bundle', 'sealed_manifest',
		'sealed_manifest_sha256', 'compiler_path', 'receipts', 'desktop_build_sha256']) {
		return error('hosted launch-options import fields differ')
	}
	receipt := json2.decode[ImportReceipt](text)!
	if receipt.format != 1 || receipt.method != 'verified copy of sealed hosted launch-options compositor build; no rebuild' || receipt.architecture != arch {
		return error('hosted launch-options import header differs')
	}
	bundle := admitted_bundle(receipt.bundle)!
	if receipt.sealed_manifest != bundle.root + '/bundle.sha256' || receipt.sealed_manifest_sha256 != bundle.seal ||
		receipt.compiler_path != bundle.compiler || receipt.receipts != bundle.receipts ||
		receipt.desktop_build_sha256 != proof.digest(desktop + '/desktop-build.json')! ||
		proof.digest(compiler)! != bundle.tools[bundle.compiler] {
		return error('hosted launch-options import binding differs')
	}
	expected := manifest(bundle, arch)!
	if read_map(desktop + '/desktop-build.json')! != expected { return error('hosted launch-options imported desktop manifest differs') }
	same(bundle.sources, inventory(desktop + '/source')!)!
	mut result := historical_stage(stage, arch, historical_compiler)!
	result['supplemental/import.json'] = desktop + '/import.json'
	result['supplemental/desktop-build.json'] = desktop + '/desktop-build.json'
	result['supplemental/bundle.sha256'] = bundle.root + '/bundle.sha256'
	for name in bundle.sealed.keys() { result['supplemental/bundle/' + name] = bundle.root + '/' + name }
	for name in bundle.sources.keys() { result['supplemental/desktop/source/' + name] = desktop + '/source/' + name }
	for name in ['app/desktop.c', 'app/execinfo.c', 'app/presenter.c', 'vinix-desktop'] {
		path := desktop + '/' + name
		if proof.digest(path)! != expected[name] { return error('hosted launch-options imported output differs: ' + name) }
		result['supplemental/desktop/' + name] = path
	}
	for path in bundle.tools.keys() { result['supplemental/original-tool/' + path] = path }
	return result
}

pub fn source() string { return $embed_file('admit.v').to_string() }
