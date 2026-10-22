// SPDX-License-Identifier: GPL-2.0-or-later
// Explicit errors remain active in production builds used for source capture.
module main

import crypto.sha256
import json2
import os
import stbi
import proof
import tools.packages.pkgcore

struct TreeInput { root string selected_sources bool entries map[string]string }

struct Qualification {
	format int
	architecture string
	desktop string
	desktop_receipt string
	inputs map[string]string
	outputs map[string]string
	trees map[string]TreeInput
	passed bool
}

fn digest(path string) !string {
	mut file := os.open(path)!
	defer { file.close() }
	mut hash := sha256.new()
	defer { unsafe { hash.free() } }
	mut buffer := []u8{len: 1024 * 1024}
	defer { unsafe { buffer.free() } }
	for {
		count := file.read(mut buffer) or { if err is os.Eof { break } else { return err } }
		if count == 0 { break }
		hash.write(buffer[..count])!
	}
	result := hash.sum([]u8{})
	defer { unsafe { result.free() } }
	return result.hex()
}

fn exact(text string, marker string) !int {
	mut count := 0
	mut offset := 0
	mut found := -1
	for line in text.split_into_lines() {
		if line.trim_right('\r') == marker { count++; found = offset }
		offset += line.len + 1
	}
	if count != 1 { return error('missing or duplicated exact marker: ' + marker) }
	return found
}

fn serial(path string, arch string) ! {
	if (os.stat(path)!).size > 16 * 1024 * 1024 { return error('serial transcript exceeds limit') }
	text := os.read_file(path)!.replace('\x1b[01;01H', '')
	for forbidden in ['SOFTWARE X11 FAIL', 'KERNEL PANIC', 'V panic:', 'FATAL EXCEPTION',
		'sysdisk: running from memory', 'sysdisk: updating the system on'] {
		if text.contains(forbidden) { return error('forbidden serial marker: ' + forbidden) }
	}
	mut previous := -1
	for marker in [
		'SOFTWARE X11 START',
		'SOFTWARE X11 installed disk-root tools trust signed-state digests PASS',
		'SOFTWARE X11 ordinary-compositor uid=1000 home=/home/alex PASS',
		'SOFTWARE X11 signed-client uid=1000 groups=0 generation=1 private-authority exact-socket lease-held PASS',
		'SOFTWARE X11 painted-client ready PASS',
		'SOFTWARE X11 actual-pointer ButtonPress repainted lease-held PASS',
		'SOFTWARE X11 UI-close bridge+Xvfb reaped authority+socket removed live-child-lease-held PASS',
		'SOFTWARE X11 natural-child-exit actual-reap lease-released PASS',
		'SOFTWARE X11 INSTALLED signed-launch painted pointer close-reap lease-lifecycle PASS',
		'SOFTWARE X11 requesting guest poweroff uid=0',
	] {
		position := exact(text, marker)!
		if position <= previous { return error('serial lifecycle marker order differs') }
		previous = position
	}
	if arch == 'aarch64' { exact(text, 'syspower: power off: stopping devices')! }
}

fn admit_shutdown(path string) ! {
	if (os.stat(path)!).size > 1024 * 1024 { return error('shutdown transcript exceeds limit') }
	mut header := 0
	mut greeting := 0
	mut capabilities := 0
	mut stopped := 0
	for line in os.read_file(path)!.split_into_lines() {
		if line == '' { continue }
		record := json2.decode[json2.Any](line)!.as_map()
		if 'graphical_boot' in record {
			if record.len != 1 || record['graphical_boot']! != json2.Any(f64(1)) || greeting != 0 { return error('shutdown boot binding differs') }
			header++
		} else if 'QMP' in record {
			if header != 1 || capabilities != 0 { return error('shutdown greeting order differs') }
			greeting++
		} else if 'return' in record && record['return']!.as_map().len == 0 {
			if greeting != 1 || stopped != 0 { return error('shutdown capabilities order differs') }
			capabilities++
		} else if 'event' in record {
			event := record['event']!.str()
			if event in ['RESET', 'GUEST_PANICKED'] { return error('forbidden QMP shutdown event: ' + event) }
			if event == 'SHUTDOWN' {
				data := record['data']!.as_map()
				if capabilities != 1 || data['guest']! != json2.Any(true) || data['reason']! != json2.Any('guest-shutdown') {
					return error('shutdown was not the guest shutdown event')
				}
				stopped++
			}
		}
	}
	if header != 1 || greeting != 1 || capabilities != 1 || stopped != 1 { return error('shutdown handshake or exact guest event missing/duplicated') }
}

fn painted(path string, phase int) ! {
	image := stbi.load(path, stbi.LoadParams{desired_channels: 3})!
	defer { image.free() }
	if image.width != 1024 || image.height != 768 { return error('framebuffer size differs') }
	mut green := 0
	mut pink := 0
	mut blue := 0
	for i := 0; i + 2 < image.width * image.height * 3; i += 3 {
		unsafe {
			if image.data[i] == 0x21 && image.data[i + 1] == 0x6a && image.data[i + 2] == 0x43 { green++ }
			if image.data[i] == 0xb6 && image.data[i + 1] == 0x42 && image.data[i + 2] == 0x6f { pink++ }
			if image.data[i] == 0x54 && image.data[i + 1] == 0x68 && image.data[i + 2] == 0xc9 { blue++ }
		}
	}
	if (phase == 2 && (green <= 1000 || pink <= 1000 || blue > 1000)) ||
		(phase == 3 && (green <= 1000 || blue <= 1000 || pink > 1000)) ||
		(phase == 4 && (green > 1000 || blue > 1000 || pink > 1000)) {
		return error('painted X11 framebuffer phase differs')
	}
}

fn desktop(receipt Qualification) ! {
	if receipt.desktop_receipt != os.dir(receipt.desktop) + '/desktop-build.json' { return error('desktop receipt path differs') }
	manifest := json2.decode[map[string]string](os.read_file(receipt.desktop_receipt)!)!
	if manifest['vinix-desktop'] or { '' } != digest(receipt.desktop)! { return error('desktop manifest ELF differs') }
	if receipt.inputs[receipt.desktop_receipt] or { '' } != digest(receipt.desktop_receipt)! { return error('desktop manifest input pin absent') }
	for name, expected in manifest {
		if name in ['compiler', 'repository-head'] { continue }
		if name.starts_with('/') || '..' in name.split('/') { return error('invalid desktop manifest path') }
		path := os.dir(receipt.desktop) + if name.starts_with('app/') || name == 'vinix-desktop' { '/' + name } else { '/source/' + name }
		if digest(path)! != expected || receipt.inputs[path] or { '' } != expected { return error('desktop source/build pin differs: ' + name) }
	}
}

fn package(work string, receipt Qualification) ! {
	config := json2.decode[json2.Any](os.read_file(work + '/extras/etc/vinix-packages/config.json')!)!.as_map()
	repositories := config['repositories']!.as_array()
	if config['format']! != json2.Any(f64(1)) || config['architecture']! != json2.Any(receipt.architecture) ||
		config['launch_user']! != json2.Any('alex') || config['policy']!.as_map()['offline']! != json2.Any(true) || repositories.len != 1 {
		return error('installed trust configuration differs')
	}
	repository := repositories[0].as_map()
	key := repository['public_key']!.str()
	if repository['id']! != json2.Any('trusted') || key.len != 64 ||
		repository['url']! != json2.Any('file://' + work + '/publisher/repository') { return error('fixture publisher differs') }
	state := json2.decode[json2.Any](os.read_file(work + '/extras/var/lib/vinix-packages/generations/1/state.json')!)!.as_map()
	if state['format']! != json2.Any(f64(1)) || state['generation']! != json2.Any(f64(1)) ||
		state['previous']! != json2.Any(f64(0)) || state['architecture']! != json2.Any(receipt.architecture) ||
		state['requested']!.as_array().map(it.str()) != ['org.fixture.x11'] || state['packages']!.as_array().len != 1 {
		return error('installed signed generation differs')
	}
	installed := state['packages']!.as_array()[0].as_map()
	if installed['repository']! != json2.Any('trusted') || installed['public_key']! != json2.Any(key) || installed['sequence']! != json2.Any(f64(1)) {
		return error('installed package publisher differs')
	}
	p := installed['package']!.as_map()
	index := pkgcore.verify_index(pkgcore.Repository{id: 'trusted', public_key: key},
		os.read_file(work + '/publisher/repository/index.json')!, os.read_file(work + '/publisher/repository/index.sig')!, 0)!
	if index.sequence != 1 || index.packages.len != 1 || json2.decode[json2.Any](json2.encode(index.packages[0]))! != json2.Any(p) {
		return error('authenticated index package differs from installed generation')
	}
	if p['id']! != json2.Any('org.fixture.x11') || p['version']! != json2.Any('1.0.0') ||
		p['architecture']! != json2.Any(receipt.architecture) || p['kind']! != json2.Any('native') ||
		p['entrypoint']! != json2.Any('bin/client') || p['arguments']!.as_array().map(it.str()) != ['--signed-child'] ||
		p['permissions']!.as_array().map(it.str()) != ['display', 'files'] || p['license']! != json2.Any('MIT') {
		return error('signed hosted application declaration differs')
	}
	guest_proof := json2.decode[map[string]string](os.read_file(work + '/extras/usr/share/software-hosted-x11.json')!)!
	for name in ['/sbin/init', '/usr/bin/vinix-desktop', '/usr/bin/vinix-package', '/usr/bin/vinix-sandbox',
		'/usr/sbin/vinix-account', '/usr/sbin/vinix-authd', '/usr/sbin/vinix-session', '/usr/bin/vinix-wine-host',
		'/usr/bin/Xvfb', '/usr/share/vinix/actions/packages-launch', '/etc/vinix-packages/config.json',
		'/var/lib/vinix-packages/generations/1/state.json', '/var/lib/vinix-packages/catalog.json'] {
		if guest_proof[name] or { '' } != digest(work + '/extras' + name)! { return error('installed guest proof differs: ' + name) }
	}
	if digest(work + '/extras/usr/bin/vinix-desktop')! != digest(receipt.desktop)! { return error('staged compositor differs') }
}

fn builds(work string, receipt Qualification) ! {
	before := json2.decode[map[string]string](os.read_file(work + '/inputs-before-build.json')!)!
	if before.len < 100 { return error('prebuild input snapshot incomplete') }
	for path, hash in before {
		if receipt.inputs[path] or { '' } != hash { return error('prebuild input snapshot differs') }
	}
	for name, tree in receipt.trees {
		if name == 'staged' { continue }
		for relative, value in tree.entries {
			expected := if value.len == 64 { value } else if value.contains('\nsha256:') { value.all_after('\nsha256:') } else { continue }
			if before[tree.root + '/' + relative] or { '' } != expected { return error('prebuild tree pin absent') }
		}
	}
	for name in ['inputs.json', 'inputs-verified.json'] {
		if json2.decode[map[string]string](os.read_file(work + '/' + name)!)! != receipt.inputs { return error('verified input snapshot differs') }
	}
	for name in ['tools/accounts', 'tools/packages', 'build-support/xorg-server', 'build-support/native-compat-tools'] {
		proof.copied_sources(work + '/source/' + name, receipt.trees['source:' + name]!.entries)!
	}
	proof.copied_sources(work + '/build-bridge/project/winehost', proof.tree(work + '/source/build-support/xorg-server/winehost', true)!)!
	proof.copied_sources(work + '/build-bridge/project/x11auth', proof.tree(work + '/source/tools/packages/x11auth', true)!)!
	for name in ['vinix-account', 'vinix-session', 'vinix-authd', 'vinix-package', 'guest', 'bridge'] {
		directory := 'build-' + name
		for path in [name + '.c', name, 'v.log', 'v.log.argv.json', 'cc.log', 'cc.log.argv.json'] {
			if directory + '/' + path !in receipt.outputs { return error('required fresh build artifact missing: ' + directory + '/' + path) }
		}
		if name != 'bridge' && directory + '/runtime.c' !in receipt.outputs { return error('fresh runtime translation missing') }
		for path in os.walk_ext(work + '/' + directory, '') {
			if os.is_file(path) && !os.is_link(path) {
				relative := path[work.len + 1..]
				hash := receipt.outputs[relative] or { return error('fresh build inventory pin absent') }
				if receipt.inputs[path] or { '' } != hash { return error('fresh build preboot pin differs: ' + relative) }
			}
		}
		binary := work + '/' + directory + '/' + name
		staged := work + '/extras' + match name {
			'vinix-account', 'vinix-session', 'vinix-authd' { '/usr/sbin/' + name }
			'vinix-package' { '/usr/bin/' + name }
			'bridge' { '/usr/bin/vinix-wine-host' }
			else { '/sbin/init' }
		}
		if digest(binary)! != digest(staged)! { return error('fresh build differs from staged ELF: ' + name) }
		vargs := json2.decode[[]string](os.read_file(work + '/' + directory + '/v.log.argv.json')!)!
		ccargs := json2.decode[[]string](os.read_file(work + '/' + directory + '/cc.log.argv.json')!)!
		if vargs.len < 15 || ccargs.len < 15 || vargs[0] !in before || ccargs[0] !in before ||
			'-manualfree' !in vargs || '-gc' !in vargs || '-fuse-ld=lld' !in ccargs ||
			'--sysroot=' + receipt.trees['sysroot']!.root !in ccargs || '--gcc-install-dir=' + receipt.trees['gcc']!.root !in ccargs ||
			work + '/' + directory + '/' + name + '.c' !in ccargs || ccargs[ccargs.len - 2..] != ['-o', binary] {
			return error('fresh build command differs: ' + name)
		}
	}
	if digest(work + '/build-guest/guest')! != digest(work + '/publisher/payload/bin/client')! { return error('signed client differs from fresh guest ELF') }
}

fn retain() ! {
	$if prod {} $else { return error('compile retainer with -prod for frozen source admission') }
	if digest(@FILE)! != sha256.hexhash($embed_file('retain.v').to_string()) { return error('retainer source changed after compilation') }
	if digest(os.dir(@FILE) + '/proof/admit.v')! != sha256.hexhash(proof.source()) { return error('proof source changed after compilation') }
	mut options := map[string]string{}
	for arg in os.args[1..] {
		if !arg.starts_with('--') || !arg.contains('=') { return error('expected --name=value') }
		name := arg.all_before('=')
		if name !in ['--work', '--out'] || name in options || arg.all_after('=') == '' { return error('unknown, duplicate or empty retainer option') }
		options[name] = arg.all_after('=')
	}
	work := os.abs_path(options['--work'] or { return error('required --work') })
	out := os.abs_path(options['--out'] or { return error('required --out') })
	if os.exists(out) { return error('retained output already exists') }
	receipt := json2.decode[Qualification](os.read_file(work + '/qualification.json')!)!
	if receipt.format != 1 || receipt.architecture !in ['aarch64', 'x86_64'] || !receipt.passed { return error('native qualification header differs') }
	if receipt.inputs.len < 100 || receipt.outputs.len < 15 { return error('native qualification pins incomplete') }
	for name in ['compiler-vlib', 'compiler-thirdparty', 'sysroot', 'gcc', 'rootfs', 'stage', 'staged', 'xkb', 'clang-resource', 'lld-libraries',
		'desktop-sysroot-include', 'desktop-sysroot-lib', 'desktop-shim',
		'archived-desktop-source', 'archived-stage-source',
		'source:tools/accounts', 'source:tools/packages', 'source:build-support/xorg-server', 'source:build-support/native-compat-tools',
		'source:tools/qmpclient', 'source:build-support/screenshotcore', 'source:tests/hardware-platform/hwhost',
		'source:tests/hardware-platform/plainiso', 'source:tests/software-hosted-x11/proof'] {
		tree := receipt.trees[name] or { return error('required complete input tree missing: ' + name) }
		if tree.selected_sources != name.starts_with('source:') { return error('required input tree selection mode differs: ' + name) }
		if tree.entries.len == 0 { return error('empty input tree') }
		for relative, value in tree.entries {
			expected := if value.len == 64 { value } else if value.contains('\nsha256:') { value.all_after('\nsha256:') } else { continue }
			if receipt.inputs[tree.root + '/' + relative] or { '' } != expected { return error('tree file input pin absent') }
		}
	}
	if receipt.trees['staged']!.root != work + '/extras' || receipt.trees['staged']!.entries['usr/bin/vinix-software'] or { '' } != 'link:/usr/bin/vinix-desktop' {
		return error('staged Software link or root differs')
	}
	mut controllers := 0
	mut guests := 0
	for path, expected in receipt.inputs {
		if expected.len != 64 { return error('input pin differs: ' + path) }
		if path.ends_with('/tests/software-hosted-x11/check.v') {
			if expected != sha256.hexhash($embed_file('check.v').to_string()) { return error('frozen controller source differs') }
			controllers++
		}
		if path.ends_with('/tests/software-hosted-x11/guest/main.v') {
			if expected != sha256.hexhash($embed_file('guest/main.v').to_string()) { return error('frozen guest source differs') }
			guests++
		}
	}
	if controllers != 2 || guests != 2 { return error('original and staged fixture source pins missing') }
	mut names := ['serial.log', 'shutdown-1.jsonl', 'qemu-exit.json', 'system.vjfs', 'initramfs.tar', 'qemu-arguments.json',
		'01-catalog.png', '02-painted.png', '03-pointer.png', '04-closed.png',
		'extras/usr/share/software-hosted-x11.json', 'extras/etc/vinix-packages/config.json', 'extras/sbin/init',
		'publisher/manifest.json', 'publisher/repository/index.json', 'publisher/repository/index.sig']
	if receipt.architecture == 'x86_64' { names << 'test.iso' }
	names << ['inputs-before-build.json', 'inputs.json', 'inputs-verified.json']
	for name in names {
		if (receipt.outputs[name] or { '' }).len != 64 { return error('output pin differs: ' + name) }
	}
	// Refuse cheap transcript/phase errors before rehashing entire toolchains
	// and disk media. All byte and inventory checks still precede mkdir/copy.
	if receipt.outputs['serial.log']! != digest(work + '/serial.log')! { return error('output pin differs: serial.log') }
	status := json2.decode[json2.Any](os.read_file(work + '/qemu-exit.json')!)!.as_map()
	if status.len != 3 || status['exit_code']! != json2.Any(f64(0)) || status['reaped']! != json2.Any(true) || status['guest_shutdown']! != json2.Any(true) { return error('actual QEMU exit0/reap record differs') }
	serial(work + '/serial.log', receipt.architecture)!
	admit_shutdown(work + '/shutdown-1.jsonl')!
	for phase in [2, 3, 4] { painted(work + '/' + ['02-painted.png', '03-pointer.png', '04-closed.png'][phase - 2], phase)! }
	builds(work, receipt)!
	desktop(receipt)!
	for name, hash in receipt.outputs {
		if name.starts_with('/') || '..' in name.split('/') { return error('native output pin differs: ' + name) }
		if name !in names && !['build-vinix-account/', 'build-vinix-session/', 'build-vinix-authd/', 'build-vinix-package/', 'build-guest/', 'build-bridge/'].any(name.starts_with(it)) { return error('unexpected native output: ' + name) }
	}
	mut compiler := ''
	for path, _ in receipt.inputs { if path.ends_with('/toolchain/v') { compiler = path; break } }
	if compiler == '' { return error('pinned compiler absent') }
	for _, path in proof.assembled(os.dir(receipt.desktop), os.dir(receipt.trees['stage']!.root), receipt.architecture, compiler)! {
		if receipt.inputs[path] or { '' } != digest(path)! { return error('anchored assembled input pin absent') }
	}
	package(work, receipt)!
	for _, tree in receipt.trees { proof.tree_unchanged(tree.root, tree.selected_sources, tree.entries)! }
	for path, expected in receipt.inputs {
		if digest(path)! != expected { return error('input pin differs: ' + path) }
	}
	for name, expected in receipt.outputs {
		if digest(work + '/' + name)! != expected { return error('native output pin differs: ' + name) }
	}
	os.mkdir_all(out)!
	for name in ['qualification.json', 'serial.log', 'shutdown-1.jsonl', 'qemu-exit.json', '01-catalog.png', '02-painted.png', '03-pointer.png', '04-closed.png'] {
		os.cp(work + '/' + name, out + '/' + name)!
	}
	os.write_file(out + '/retention.json', json2.encode({
		'architecture': receipt.architecture, 'qualification': digest(work + '/qualification.json')!,
		'retainer': digest(os.executable())!, 'retainer_source': digest(@FILE)!,
		'scope': 'ordinary installed Software Launch; pointer-enabled compositor snapshot and historical assembled stage; authenticated painted X11; pointer repaint; actual close/reap and lease lifecycle; guest shutdown and QEMU exit0',
	}))!
	println('SOFTWARE HOSTED X11 RETAIN PASS ' + receipt.architecture)
}

fn main() { retain() or { eprintln(err); exit(1) } }
