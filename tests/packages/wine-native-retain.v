// SPDX-License-Identifier: GPL-2.0-or-later
// Independently admit real Wine evidence before writing any retained output.
module main

import crypto.sha256
import hwhost
import json2
import os
import plainiso
import tools.packages.wineadapter

struct WineOutcome {
	scenario    string
	passed      bool
	interrupted bool
	reason      string
}

struct WineReceipt {
	format         int = 1
	architecture   string
	scope          string = 'local-only signed Wine Win64 console probe under an ordinary Vinix account; actual Windows APIs, private prefix/socket, generation lease release, natural child exit; harness stops guest after PASS; no Calculator UI or redistribution qualification'
	markers        []string
	artifacts      map[string]string
	artifact_paths map[string]string
}

fn digest(path string) !string {
	text := os.read_file(path)!
	defer { unsafe { text.free() } }
	return sha256.hexhash(text)
}

fn hashes(path string) !map[string]string {
	result := json2.decode[map[string]string](os.read_file(path)!)!
	if result.len == 0 || result.len > 100000 { return error('invalid evidence digest inventory') }
	return result
}

fn add(mut paths map[string]string, name string, path string) ! {
	if !os.is_file(path) { return error('missing required artifact: ' + name) }
	paths[name] = path
}

fn require_input(inputs map[string]string, path string) ! {
	if path !in inputs { return error('missing required input: ' + path) }
}

fn tree(inputs map[string]string, directory string) ! {
	mut count := 0
	for path in os.walk_ext(directory, '') {
		if os.is_file(path) {
			require_input(inputs, path)!
			count++
		}
	}
	mut admitted := 0
	for path, _ in inputs { if path.starts_with(directory + '/') { admitted++ } }
	if count == 0 || count != admitted {
		return error('input tree inventory differs: ' + directory)
	}
}

fn verify(inputs map[string]string) ! {
	for path, expected in inputs {
		if !os.is_abs_path(path) || expected.len != 64 || digest(path)! != expected {
			return error('input digest mismatch: ' + path)
		}
	}
}

fn argv(path string) ![]string {
	return json2.decode[[]string](os.read_file(path)!)!
}

fn producer_argv(vargv string, ccargv string, compiler string, architecture string, cfile string, runtime string, output string, source string, root string, sysroot string, gcc string, native bool) ! {
	v := argv(vargv)!
	c := argv(ccargv)!
	mut expected_v := [compiler, '-backend', 'c', '-prod', '-os', 'linux', '-arch',
		if architecture == 'aarch64' { 'arm64' } else { 'amd64' }, '-gc', 'none', '-manualfree']
	if native { expected_v << '-enable-globals' }
	expected_v << ['-d', 'no_backtrace', '-d', 'no_segfault_handler']
	if native {
		expected_v << ['-path', '@vlib|' + root + '|' + root + '/tools/accounts|@vmodules']
	}
	expected_v << ['-o', cfile, source]
	if v != expected_v {
		return error('V producer argv differs')
	}
	if c != ['/opt/homebrew/opt/llvm/bin/clang', '--target=' + architecture + '-linux-musl',
		'--sysroot=' + sysroot, '--gcc-install-dir=' + gcc, '-fuse-ld=lld',
		if native { '-O1' } else { '-O2' }, '-w', '-fno-stack-protector', '-static', '-D_GNU_SOURCE',
		'-Wno-error=incompatible-pointer-types', cfile, runtime, '-lm', '-lpthread', '-o', output] {
		return error('C producer argv differs')
	}
}

fn retain() ! {
	$if prod {
	} $else {
		return error('compile Wine retention with -prod for embedded source admission')
	}
	if os.args.len != 5 {
		return error('usage: wine-native-retain RUN PREPARED_BUILD ARCH NEW_OUTPUT')
	}
	root := hwhost.find_root(@FILE)!
	run := os.abs_path(os.args[1])
	prepared := os.abs_path(os.args[2])
	arch := os.args[3]
	out := os.abs_path(os.args[4])
	if arch !in ['aarch64', 'x86_64'] || os.exists(out) {
		return error('unsupported architecture or existing retention output')
	}
	expected_sources := {
		'tests/packages/wine-native-retain.v':     $embed_file('wine-native-retain.v').to_string()
		'tests/packages/wine-native-check.v':      $embed_file('wine-native-check.v').to_string()
		'tests/packages/wine-native/main.v':       $embed_file('wine-native/main.v').to_string()
		'tools/packages/wine-build.v':             $embed_file('../../tools/packages/wine-build.v').to_string()
		'tools/packages/wine-runner.v':            $embed_file('../../tools/packages/wine-runner.v').to_string()
		'tools/packages/wineadapter/prefix.c.v':   $embed_file('../../tools/packages/wineadapter/prefix.c.v').to_string()
		'tools/packages/wineadapter/patch.v':      $embed_file('../../tools/packages/wineadapter/patch.v').to_string()
		'tools/packages/wineadapter/pe_proof.c.v': $embed_file('../../tools/packages/wineadapter/pe_proof.c.v').to_string()
		'tools/packages/wineadapter/pe_reader.v':  $embed_file('../../tools/packages/wineadapter/pe_reader.v').to_string()
		'tests/hardware-platform/plainiso/iso.v':  plainiso.source()
	}
	for name, source in expected_sources {
		if digest(root + '/' + name)! != sha256.hexhash(source) {
			return error('compiled Wine fixture source differs: ' + name)
		}
	}
	declaration := json2.decode[map[string]string](os.read_file(run + '/declaration.json')!)!
	if declaration['architecture'] != arch || declaration['source_root'] != root || declaration['prepared'] != prepared {
		return error('Wine declaration binding differs')
	}
	// A disposable evidence copy retains the build's absolute argv namespace.
	// Every copied output is still required and hashed against its input pin.
	recorded_run := declaration['run']
	recorded_prepared := declaration['prepared_namespace']
	if !os.is_abs_path(recorded_run) || !os.is_abs_path(recorded_prepared) {
		return error('Wine recorded build namespace is missing')
	}
	inputs := hashes(run + '/inputs.json')!
	if inputs != hashes(run + '/inputs-before-build.json')! || inputs != hashes(run + '/inputs-verified.json')! {
		return error('Wine input verification differs')
	}
	for name in ['compiler', 'kernel', 'qemu', 'firmware', 'sandbox', 'controller']! {
		require_input(inputs, declaration[name])!
	}
	for path in ['/opt/homebrew/opt/llvm/bin/clang', '/opt/homebrew/bin/ld.lld']! {
		require_input(inputs, path)!
	}
	if arch == 'x86_64' {
		if declaration['firmware_vars'] != '' || declaration['arm_loader'] != '' {
			return error('x86 ARM loader/variable-store declaration must be empty')
		}
		for name in ['iso_xorriso', 'iso_bootx64', 'iso_limine_cd']! {
			require_input(inputs, declaration[name])!
		}
	} else {
		for name in ['arm_loader', 'firmware_vars']! {
			if declaration[name] == '' {
				return error('missing ARM boot input declaration: ' + name)
			}
			require_input(inputs, declaration[name])!
		}
	}
	for name in ['tests/packages/wine-native-check.v', 'tests/packages/wine-native/main.v']! {
		require_input(inputs, root + '/' + name)!
	}
	for directory in [root + '/tools/packages', root + '/tools/accounts',
		root + '/tests/hardware-platform/hwhost', root + '/tests/hardware-platform/plainiso',
		os.dir(declaration['compiler']) + '/vlib', os.dir(declaration['compiler']) + '/thirdparty',
		declaration['sysroot'] + '/usr/include', declaration['sysroot'] + '/usr/lib',
		declaration['sysroot'] + '/lib', declaration['gcc_runtime'], prepared] {
		tree(inputs, directory)!
	}
	verify(inputs)!
	producer_inputs := hashes(prepared + '/inputs-before-build.json')!
	if producer_inputs != hashes(prepared + '/inputs-verified.json')! {
		return error('Wine producer input verification differs')
	}
	verify(producer_inputs)!
	for name in ['tools/packages/wine-build.v', 'tools/packages/wine-runner.v']! {
		require_input(producer_inputs, root + '/' + name)!
	}
	build_record := json2.decode[map[string]string](os.read_file(prepared + '/build-producer.json')!)!
	if build_record.len != 3 || build_record['source'] != root + '/tools/packages/wine-build.v'
		|| build_record['compiler'] != declaration['compiler'] {
		return error('Wine producer executable declaration differs')
	}
	require_input(producer_inputs, build_record['executable'])!
	require_input(producer_inputs, '/opt/homebrew/opt/llvm/bin/llvm-readelf')!
	for directory in [root + '/tools/packages/wineadapter', root + '/tools/packages/appsdk',
		root + '/tools/packages/pkgprotocol', os.dir(declaration['compiler']) + '/vlib',
		os.dir(declaration['compiler']) + '/thirdparty'] {
		tree(producer_inputs, directory)!
	}
	pe_record := json2.decode[map[string]string](os.read_file(prepared + '/pe-producer.json')!)!
	if pe_record.len != 4 || pe_record['program_source'] != root + '/tests/packages/wine-native/program.v'
		|| pe_record['producer_source'] != root + '/tests/packages/wine-pe-check.v' {
		return error('Wine PE source binding differs')
	}
	mut pe := wineadapter.admit_local_pe_proof(pe_record['directory'], pe_record['program_source'], pe_record['producer_source'])!
	defer { pe.close() }
	if pe_record['executable'] != pe.executable {
		return error('Wine PE executable binding differs')
	}
	for path, expected in pe.artifacts {
		if producer_inputs[path] != expected {
			return error('Wine PE producer artifact is not an admitted input: ' + path)
		}
	}
	if digest(prepared + '/prepared/' + arch + '/application/bin/program.exe')! != pe.artifacts[pe.executable] {
		return error('Wine prepared PE differs from its admitted producer')
	}
	mut paths := map[string]string{}
	for path, _ in inputs { paths['input/' + path] = path }
	for path, _ in producer_inputs { paths['producer-input/' + path] = path }
	outputs := hashes(prepared + '/outputs.json')!
	for name in ['build/wine-runner.c', 'build/runtime.c', 'logs/v.log', 'logs/v.log.argv.json',
		'logs/cc.log', 'logs/cc.log.argv.json', 'application.json', 'runtime.json',
		'build-producer.json', 'pe-producer.json', 'publisher-notices/source-offer.json',
		'prepared/' + arch + '/runtime/bin/wine-runner', 'prepared/' + arch + '/runtime/bin/wine64',
		'prepared/' + arch + '/runtime/bin/wineserver',
		'prepared/' + arch + '/runtime/root/usr/bin/wineserver',
		'prepared/' + arch + '/runtime/root/usr/lib/wine/x86_64-unix/ntdll.so',
		'prepared/' + arch + '/application/bin/program.exe',
		'prepared/' + arch + '/runtime/root/usr/share/wine/nls/locale.nls',
		'prepared/' + arch + '/runtime/root/usr/share/wine/nls/l_intl.nls',
		'prepared/' + arch + '/runtime/root/usr/share/wine/wine.inf',
		'prepared/' + arch + '/runtime/licenses/local-source-evidence.tar'] {
		if name !in outputs { return error('missing required producer output: ' + name) }
	}
	for name, expected in outputs {
		if os.is_abs_path(name) || '..' in name.split('/') || digest(prepared + '/' + name)! != expected
			|| inputs[prepared + '/' + name] != expected {
			return error('producer output differs from native input: ' + name)
		}
		add(mut paths, 'producer-output/' + name, prepared + '/' + name)!
	}
	for name in ['nls/locale.nls', 'nls/l_intl.nls', 'wine.inf']! {
		suffix := '/usr/libexec/vinix-x86_64/root/usr/share/wine/' + name
		mut matches := 0
		mut expected := ''
		for path, hash in producer_inputs {
			if path.ends_with(suffix) {
				matches++
				expected = hash
			}
		}
		if matches != 1 || digest(prepared + '/prepared/' + arch + '/runtime/root/usr/share/wine/' + name)! != expected {
			return error('Wine data resource differs from its distribution input: ' + name)
		}
	}
	for part in ['/usr/bin/wineserver', '/usr/lib/wine/x86_64-unix/ntdll.so']! {
		suffix := '/usr/libexec/vinix-x86_64/root' + part
		mut original := ''
		mut matches := 0
		for path, _ in producer_inputs {
			if path.ends_with(suffix) {
				original = path
				matches++
			}
		}
		if matches != 1 {
			return error('Wine private-server original input is missing or ambiguous')
		}
		text := os.read_file(original)!
		defer { unsafe { text.free() } }
		patched := wineadapter.private_server_patch(text, part.ends_with('ntdll.so'))!
		defer { unsafe { patched.free() } }
		consumed := os.read_file(prepared + '/prepared/' + arch + '/runtime/root' + part)!
		defer { unsafe { consumed.free() } }
		if patched != consumed {
			return error('Wine binary differs from the exact private-server patch: ' + part)
		}
	}
	mut offer := wineadapter.admit_local_source_offer(prepared + '/publisher-notices', 'org.vinix.wine-runtime', '9.17-r1', arch)!
	offer.close()
	if arch == 'aarch64' {
		original := declaration['translator_original']
		busybox := os.dir(os.dir(os.dir(original))) + '/usr/libexec/vinix-x86_64/root/bin/busybox'
		if declaration['translator_busybox'] != busybox || inputs[original] != wineadapter.qemu_splitwx_input
			|| producer_inputs[original] != wineadapter.qemu_splitwx_input || busybox !in inputs {
			return error('Wine translator original/smoke input binding differs')
		}
		patch := json2.decode[map[string]string](os.read_file(prepared + '/translator-patch.json')!)!
		patched_file := prepared + '/prepared/' + arch + '/runtime/bin/qemu-x86_64'
		if patch != {
			'input':         original
			'input_sha256':  wineadapter.qemu_splitwx_input
			'output':        recorded_prepared + '/prepared/' + arch + '/runtime/bin/qemu-x86_64'
			'output_sha256': digest(patched_file)!
			'scope':         'local-qualification-only: exact AArch64 tcg_init_machine argument instruction forces splitwx=1; no RWX fallback'
			'offset':        '0x85c64'
			'before':        '612e40b9'
			'after':         '21008052'
		} {
			return error('Wine translator patch declaration differs')
		}
		if 'translator-patch.json' !in outputs {
			return error('missing required translator patch output')
		}
		original_text := os.read_file(original)!
		patched := wineadapter.splitwx_patch(original_text)!
		consumed := os.read_file(patched_file)!
		defer {
			unsafe {
				original_text.free()
				patched.free()
				consumed.free()
			}
		}
		if patched != consumed {
			return error('Wine translator differs from the exact split-WX patch')
		}
	}
	generated := hashes(run + '/generated-before-boot.json')!
	mut required := []string{}
	for program in ['guest', 'package']! {
		for name in [program, program + '.c', 'runtime.c', 'v.log', 'v.log.argv.json', 'cc.log',
			'cc.log.argv.json'] {
			required << 'build-' + program + '/' + name
		}
	}
	for name in ['usr/bin/vinix-package', 'usr/sbin/vinix-account', 'usr/sbin/vinix-session',
		'usr/bin/vinix-sandbox', 'etc/vinix/auth.conf', 'etc/vinix-packages/config.json']! {
		required << 'extras/' + name
	}
	if arch == 'aarch64' {
		for name in ['qemu-original', 'busybox']! {
			required << 'extras/usr/libexec/wine-qualification/' + name
		}
		if generated['extras/usr/libexec/wine-qualification/qemu-original'] != inputs[declaration['translator_original']]
			|| generated['extras/usr/libexec/wine-qualification/busybox'] != inputs[declaration['translator_busybox']] {
			return error('Wine translator smoke output differs from its input')
		}
	}
	if generated.len != required.len { return error('required generated output inventory differs') }
	for name in required {
		if name !in generated || digest(run + '/' + name)! != generated[name] {
			return error('required generated output differs: ' + name)
		}
		add(mut paths, 'native-output/' + name, run + '/' + name)!
	}
	for name in ['usr/sbin/vinix-account', 'usr/sbin/vinix-session']! {
		if generated['extras/' + name] != inputs[declaration['stage'] + '/' + name] {
			return error('staged account/package tool differs')
		}
	}
	if generated['extras/usr/bin/vinix-package'] != generated['build-package/package'] {
		return error('staged package CLI differs from its captured producer')
	}
	if generated['extras/usr/bin/vinix-sandbox'] != inputs[declaration['sandbox']] {
		return error('staged sandbox differs')
	}
	producer_argv(run + '/build-guest/v.log.argv.json', run + '/build-guest/cc.log.argv.json', declaration['compiler'], arch,
		recorded_run + '/build-guest/guest.c', recorded_run + '/build-guest/runtime.c', recorded_run + '/build-guest/guest', root + '/tests/packages/wine-native/main.v', root, declaration['sysroot'], declaration['gcc_runtime'], true)!
	producer_argv(run + '/build-package/v.log.argv.json', run + '/build-package/cc.log.argv.json', declaration['compiler'], arch,
		recorded_run + '/build-package/package.c', recorded_run + '/build-package/runtime.c', recorded_run + '/build-package/package', root + '/tools/packages/main.v', root, declaration['sysroot'], declaration['gcc_runtime'], true)!
	producer_argv(prepared + '/logs/v.log.argv.json', prepared + '/logs/cc.log.argv.json', declaration['compiler'], arch,
		recorded_prepared + '/build/wine-runner.c', recorded_prepared + '/build/runtime.c', recorded_prepared + '/prepared/' + arch + '/runtime/bin/wine-runner', root + '/tools/packages/wine-runner.v', root, declaration['sysroot'], declaration['gcc_runtime'], false)!
	result := json2.decode[WineOutcome](os.read_file(run + '/result.json')!)!
	if result.scenario != 'packaged-Wine' || !result.passed || result.interrupted || result.reason != '' {
		return error('requires uninterrupted passing native Wine outcome')
	}
	serial := os.read_file(run + '/boot/serial.log')!
	for forbidden in [...hwhost.always_forbidden, 'Kernel panic'] {
		if serial.contains(forbidden) { return error('forbidden serial marker: ' + forbidden) }
	}
	mut markers := ['HWTEST START packaged-Wine']
	if arch == 'aarch64' {
		markers << 'HWTEST INFO Wine translated BusyBox true ordinary split-WX control PASS'
	}
	markers << ['VINIX SIGNED REAL WIN64 READY', 'VINIX SIGNED REAL WIN64 PASS',
		'HWTEST INFO Wine signed-real-Win64 ordinary-private-prefix socket lease Windows-API outside-write-refused natural-exit PASS',
		'HWTEST PASS packaged-Wine']
	lines := serial.split_into_lines().map(it.trim_space())
	mut previous := -1
	for marker in markers {
		if lines.filter(it == marker).len != 1 {
			return error('missing or duplicated exact marker: ' + marker)
		}
		position := lines.index(marker)
		if position <= previous { return error('native Wine marker order differs') }
		previous = position
	}
	for name in ['inputs-before-build.json', 'inputs.json', 'inputs-verified.json',
		'generated-before-boot.json', 'declaration.json', 'result.json', 'boot/serial.log',
		'boot/qemu.log', 'boot/image.log', 'boot/qmp.log', 'boot/initramfs.tar'] {
		add(mut paths, 'native-evidence/' + name, run + '/' + name)!
	}
	if arch == 'x86_64' {
		image_argv := argv(run + '/boot/image-commands.json')!
		if image_argv != [declaration['iso_xorriso'], '-as', 'mkisofs', '-iso-level', '3', '-R',
			'-r', '-J', '--efi-boot', 'boot/limine-uefi-cd.bin', '-efi-boot-part', '--efi-boot-image',
			'--protective-msdos-label', recorded_run + '/boot/iso/iso-root', '-o',
			recorded_run + '/boot/test.iso'] {
			return error('Wine ISO producer argv differs')
		}
		for name, source in {
			'boot/vinix':              declaration['kernel']
			'boot/initramfs.tar':      run + '/boot/initramfs.tar'
			'EFI/BOOT/BOOTX64.EFI':    declaration['iso_bootx64']
			'boot/limine-uefi-cd.bin': declaration['iso_limine_cd']
		} {
			path := run + '/boot/iso/iso-root/' + name
			if digest(path)! != digest(source)! {
				return error('Wine ISO staged input differs: ' + name)
			}
			add(mut paths, 'iso-staged/' + name, path)!
		}
		add(mut paths, 'native-evidence/boot/image-commands.json', run + '/boot/image-commands.json')!
	}
	add(mut paths, 'producer-output-receipt', prepared + '/outputs.json')!
	add(mut paths, 'retainer-source', @FILE)!
	add(mut paths, 'retainer-controller', os.executable())!
	mut artifacts := map[string]string{}
	for name, path in paths { artifacts[name] = digest(path)! }
	for name, source in expected_sources {
		if digest(root + '/' + name)! != sha256.hexhash(source) {
			return error('compiled Wine fixture source changed during admission: ' + name)
		}
	}
	os.mkdir_all(out)!
	os.write_file(out + '/wine-' + arch + '.json', json2.encode(WineReceipt{ architecture: arch, markers: markers, artifacts: artifacts, artifact_paths: paths }) + '\n')!
	os.cp(run + '/boot/serial.log', out + '/wine-' + arch + '.serial.txt')!
	println('WINE RETAIN PASS ' + arch + ': exact native outcome, source/input/output and local-only source-evidence admission')
}

fn main() {
	retain() or {
		eprintln(err)
		exit(1)
	}
}
