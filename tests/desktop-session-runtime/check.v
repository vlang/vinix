// SPDX-License-Identifier: GPL-2.0-or-later
// Fresh production compositor and services, with external ordinary clients.
module main

import crypto.sha256
import hwhost
import json2
import os
import plainiso

fn required(options map[string]string, name string) !string {
	value := options[name] or { return error('required: ' + name) }
	if value == '' { return error('empty option: ' + name) }
	return os.abs_path(value)
}

fn invoke(program string, arguments []string) ! {
	mut child := os.new_process(program)
	defer { child.close() }
	child.set_args(arguments)
	child.run()
	child.wait()
	if child.code != 0 { return error(program + ' failed (' + child.code.str() + ')') }
}

fn digest(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }

fn helper_sources() map[string]string {
	return {
		'boot.v': $embed_file('../hardware-platform/hwhost/boot.v').to_string()
		'host.v': $embed_file('../hardware-platform/hwhost/host.v').to_string()
		'vm.v': $embed_file('../hardware-platform/hwhost/vm.v').to_string()
		'process.v': $embed_file('../hardware-platform/hwhost/process.v').to_string()
		'scenario.v': $embed_file('../hardware-platform/hwhost/scenario.v').to_string()
		'markers.v': $embed_file('../hardware-platform/hwhost/markers.v').to_string()
		'qmp.v': $embed_file('../hardware-platform/hwhost/qmp.v').to_string()
		'qmp_client.v': $embed_file('../hardware-platform/hwhost/qmp_client.v').to_string()
		'screen.v': $embed_file('../hardware-platform/hwhost/screen.v').to_string()
		'sound.v': $embed_file('../hardware-platform/hwhost/sound.v').to_string()
		'aml.v': $embed_file('../hardware-platform/hwhost/aml.v').to_string()
		'suite.v': $embed_file('../hardware-platform/hwhost/suite.v').to_string()
		'cli.v': $embed_file('../hardware-platform/hwhost/cli.v').to_string()
		'acpi_bench.v': $embed_file('../hardware-platform/hwhost/acpi_bench.v').to_string()
		'thermal_bench.v': $embed_file('../hardware-platform/hwhost/thermal_bench.v').to_string()
	}
}

fn build_commands(host hwhost.Host, source string, directory string, name string, flags []string, cc string) ! {
	arch := if host.arch == 'aarch64' { 'arm64' } else { 'amd64' }
	mut commands := [][]string{}
	mut v := [host.v, '-os', 'linux', '-arch', arch, '-gc', 'none', '-d', 'no_backtrace', '-d', 'no_segfault_handler']
	v << flags
	v << ['-o', directory + '/' + name + '.c', source]
	commands << v
	if host.arch == 'aarch64' {
		sysroot := os.getenv('VINIX_AARCH64_SYSROOT')
		if sysroot == '' { return error('set VINIX_AARCH64_SYSROOT explicitly for recorded builds') }
		commands << [cc, '--target=aarch64-linux-musl', '--sysroot=' + sysroot,
			'-static', '-O1', '-w', '-D_GNU_SOURCE', '-fno-stack-protector', '-L' + sysroot + '/lib',
			'-fuse-ld=lld', '-o', directory + '/' + name, directory + '/' + name + '.c', '-lm', '-lpthread']
	} else {
		commands << [cc, '-static', '-O1', '-w', '-fpermissive', '-D_GNU_SOURCE', '-o',
			directory + '/' + name, directory + '/' + name + '.c', '-lm', '-lpthread']
	}
	os.mkdir_all(directory)!
	os.write_file(directory + '/commands.json', json2.encode(commands))!
}

fn admit_desktop(desktop string, compiler string) ! {
	directory := os.dir(desktop)
	manifest := json2.decode[map[string]string](os.read_file(directory + '/desktop-build.json')!)!
	if manifest['vinix-desktop'] != digest(desktop)! || manifest['compiler'] != digest(compiler)! {
		return error('desktop or compiler does not match the frozen build receipt')
	}
	for name, expected in manifest {
		if name in ['compiler', 'repository-head'] { continue }
		if name.starts_with('/') || '..' in name.split('/') { return error('invalid manifest path') }
		input := directory + if name.starts_with('app/') || name == 'vinix-desktop' {
			'/' + name
		} else { '/source/' + name }
		if digest(input)! != expected { return error('frozen build input changed: ' + name) }
	}
	for name in ['desktop/sessionruntime/runtime.c.v', 'desktop/sessionipc/client.c.v',
		'desktop/windowfb/transport.c.v'] {
		if name !in manifest { return error('desktop receipt is missing runtime source: ' + name) }
	}
}

fn check() ! {
	$if prod {} $else { return error('compile the runtime controller with -prod to freeze its embedded source') }
	mut options := map[string]string{}
	for argument in os.args[1..] {
		if !argument.starts_with('--') || !argument.contains('=') { return error('expected --name=value') }
		options[argument.all_before('=')] = argument.all_after('=')
	}
	arch := options['--arch'] or { 'aarch64' }
	if arch !in ['aarch64', 'x86_64'] { return error('unsupported architecture') }
	root := hwhost.find_root(@FILE)!
	work := required(options, '--out')!
	if os.exists(work) { return error('output already exists') }
	desktop := required(options, '--desktop')!
	kernel := required(options, '--kernel')!
	rootfs := required(options, '--rootfs')!
	os.mkdir_all(work)!
	host := hwhost.find_host(root, arch, '')!
	cc_name := if arch == 'aarch64' { 'CC_AARCH64' } else { 'CC_AMD64' }
	cc_default := if arch == 'aarch64' { 'clang' } else { 'x86_64-linux-musl-gcc' }
	cc := os.find_abs_path_of_executable(if os.getenv(cc_name) != '' { os.getenv(cc_name) } else { cc_default })!
	os.setenv(cc_name, cc, true)
	driver := if '--cross-driver' in options { required(options, '--cross-driver')! } else { cc }
	os.setenv('V_MACOS_V3_NO_FALLBACK', '1', true)
	os.setenv('V_C_ERROR_BUG_REPORT_DISABLED', '1', true)
	os.setenv('VEXE', host.v, true)
	os.setenv('V_MACOS_V3_CALLER_VEXE', host.v, true)
	os.setenv('V_MACOS_V3_CALLER_VEXE_PRESENT', '1', true)
	os.setenv('V_MACOS_V3_CALLER_VCHILD_PRESENT', '0', true)
	admit_desktop(desktop, host.v)!
	controller_source := root + '/tests/desktop-session-runtime/check.v'
	guest_source := root + '/tests/desktop-session-runtime/guest/main.v'
	embedded_controller := $embed_file('check.v').to_string()
	if sha256.sum(embedded_controller.bytes()).hex() != digest(controller_source)! {
		return error('controller source changed after controller compilation')
	}
	os.mkdir_all(work + '/source/guest')!
	os.write_file(work + '/source/check.v', embedded_controller)!
	os.cp(guest_source, work + '/source/guest/main.v')!
	mut hashes := map[string]string{}
	os.mkdir_all(work + '/source/hwhost')!
	for name, source in helper_sources() {
		if sha256.sum(source.bytes()).hex() != digest(root + '/tests/hardware-platform/hwhost/' + name)! {
			return error('hwhost source changed after controller compilation: ' + name)
		}
		os.write_file(work + '/source/hwhost/' + name, source)!
		hashes['hwhost/' + name] = sha256.sum(source.bytes()).hex()
	}
	image_source := root + '/tests/hardware-platform/plainiso/iso.v'
	if sha256.sum(plainiso.source().bytes()).hex() != digest(image_source)! {
		return error('plain ISO source changed after controller compilation')
	}
	os.write_file(work + '/source/plainiso.v', plainiso.source())!
	mut image_inputs := {'plain-iso-source': image_source}
	if arch == 'x86_64' {
		for name, path in plainiso.inputs(root)! { image_inputs[name] = path }
	}
	for name, path in image_inputs { hashes[name] = digest(path)! }
	for name, path in {'controller-source': controller_source, 'guest-source': guest_source,
		'controller': os.executable(), 'desktop': desktop,
		'desktop-build-receipt': os.dir(desktop) + '/desktop-build.json',
		'compiler': host.v, 'c-compiler': cc, 'cross-driver': driver,
		'kernel': kernel, 'qemu': host.qemu, 'firmware': host.firmware} {
		hashes[name] = digest(path)!
	}
	if host.firmware_vars != '' { hashes['firmware-vars'] = digest(host.firmware_vars)! }
	os.write_file(work + '/inputs-before-build.json', json2.encode(hashes))!
	frozen := os.dir(desktop) + '/source'
	flags := ['-new-compiler', '-manualfree', '-enable-globals', '-path', '@vlib|' + frozen + '|@vmodules']
	extras := work + '/extras'
	os.mkdir_all(extras)!
	invoke('cp', ['-Rp', rootfs + '/.', extras])!
	os.cp(desktop, extras + '/usr/bin/vinix-desktop')!
	os.chmod(extras + '/usr/bin/vinix-desktop', 0o755)!
	for name in ['session', 'timesync', 'runner'] {
		build_commands(host, frozen + '/desktop/services/' + name, work + '/build-' + name,
			'vinix-' + if name == 'runner' { 'service-runner' } else { name }, flags, cc)!
		binary := hwhost.build_program_with_flags(host, frozen + '/desktop/services/' + name,
			work + '/build-' + name, 'vinix-' + if name == 'runner' { 'service-runner' } else { name }, [], flags)!
		os.cp(binary, extras + '/usr/bin/' + os.base(binary))!
		os.chmod(extras + '/usr/bin/' + os.base(binary), 0o755)!
		hashes[os.base(binary)] = digest(binary)!
		hashes[os.base(binary) + '.c'] = digest(binary + '.c')!
	}
	build_commands(host, work + '/source/guest/main.v', work + '/build-guest', 'guest', flags, cc)!
	guest := hwhost.build_program_with_flags(host, work + '/source/guest/main.v', work + '/build-guest', 'guest', [], flags)!
	hashes['guest'] = digest(guest)!
	hashes['guest.c'] = digest(guest + '.c')!
	os.write_file(work + '/inputs.json', json2.encode(hashes))!
	scenario := hwhost.Scenario{
		name: 'session-runtime'
		about: 'Ordinary default broker and framebuffer sockets, actual external clients and account isolation'
		arches: [arch]
		qemu_x86_64: ['-cpu', 'max', '-vga', 'std']
		required: ['ordinary-desktop ready uid=1000 account-runtime PASS',
			'external-broker uid=1000 ping=ok PASS',
			'external-framebuffer uid=1000 frames=3 acknowledged PASS',
			'account-isolation uid=1001 broker+framebuffer refused PASS',
			'numeric-runtime private owners=1000,1001 legacy-ordinary-paths=absent PASS',
			'HWTEST PASS session-runtime']
		forbidden: ['HWTEST FAIL']
		ending: .running
	}
	runtime_host := if arch == 'x86_64' {
		hwhost.Host{...host, root: plainiso.prepare(root, work)!}
	} else { host }
	outcome := hwhost.run_scenario(runtime_host, scenario, hwhost.Run{
		kernel: kernel, guest: guest, extras: extras, state: work + '/boot', timeout: 1200, keep: true
	})
	os.write_file(work + '/result.json', json2.encode(outcome))!
	for name, path in {'controller-source': controller_source, 'guest-source': guest_source,
		'controller': os.executable(), 'desktop': desktop,
		'desktop-build-receipt': os.dir(desktop) + '/desktop-build.json',
		'compiler': host.v, 'c-compiler': cc, 'cross-driver': driver,
		'kernel': kernel, 'qemu': host.qemu, 'firmware': host.firmware} {
		if digest(path)! != hashes[name] { return error('input changed during qualification: ' + name) }
	}
	if host.firmware_vars != '' && digest(host.firmware_vars)! != hashes['firmware-vars'] {
		return error('firmware variables input changed during qualification')
	}
	for name, path in image_inputs {
		if digest(path)! != hashes[name] { return error('image input changed during qualification: ' + name) }
	}
	admit_desktop(desktop, host.v)!
	for name, source in helper_sources() {
		if sha256.sum(source.bytes()).hex() != digest(root + '/tests/hardware-platform/hwhost/' + name)! {
			return error('hwhost source changed during qualification: ' + name)
		}
	}
	os.write_file(work + '/inputs-verified.json', json2.encode(hashes))!
	mut outputs := map[string]string{}
	for entry in ['source/check.v', 'source/guest/main.v', 'source/plainiso.v', 'inputs-before-build.json', 'inputs.json',
		'inputs-verified.json', 'result.json', 'boot/initramfs.tar', 'boot/serial.log',
		'boot/qemu.log', 'boot/qmp.log', 'boot/image.log'] {
		outputs[entry] = digest(work + '/' + entry)!
	}
	for media in ['boot/boot.img', 'boot/test.iso', 'boot/vars.fd', 'boot/limine.conf'] {
		if os.exists(work + '/' + media) { outputs[media] = digest(work + '/' + media)! }
	}
	if arch == 'x86_64' {
		for entry in ['boot/image-commands.json', 'boot/iso/iso-root/boot/limine.conf'] {
			outputs[entry] = digest(work + '/' + entry)!
		}
	}
	for name in ['session', 'timesync', 'runner', 'guest'] {
		binary := if name == 'guest' { 'guest' } else if name == 'runner' { 'vinix-service-runner' } else { 'vinix-' + name }
		for file in [binary, binary + '.c', 'commands.json', 'build.log'] {
			entry := 'build-' + name + '/' + file
			outputs[entry] = digest(work + '/' + entry)!
		}
	}
	for name, _ in helper_sources() { outputs['source/hwhost/' + name] = digest(work + '/source/hwhost/' + name)! }
	os.write_file(work + '/outputs.json', json2.encode(outputs))!
	for line in outcome.notes { println(line) }
	if !outcome.passed { return error(outcome.reason + '\n' + outcome.tail.join('\n')) }
	println('PASS ' + arch + ' ordinary session runtime: ' + work)
}

fn main() {
	if plainiso.requested() { plainiso.build() or { eprintln(err); exit(1) }; return }
	check() or { eprintln(err); exit(1) }
}
