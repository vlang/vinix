// SPDX-License-Identifier: GPL-2.0-or-later
module verifiedhost

import bootpolicy
import bundlehost as bh
import fixturehost
import hosttest
import json2
import os
import policyhost
import time

struct Runtime {
	arch        string
	loader      string
	kernel      string
	code        string
	vars        string
	work        string
	timeout     int
	qemu        string
	accel       string
	secure      bool
	key         string
	certificate string
	backend     string
}

fn runtime_options(args []string, root bool) !(Runtime, bh.Options) {
	mut specs := options(['--loader', '--firmware-code', '--firmware-vars', '--logs', '--timeout',
		'--virt-fw-vars', '--qemu'])
	specs << [
		hosttest.Option{ name: '--arch', value: true, choices: ['x86_64', 'aarch64'] },
		hosttest.Option{ name: '--backend', value: true, choices: ['sbsign', 'osslsigncode'] },
		hosttest.Option{ name: '--secure-boot' },
	]
	if root {
		specs << options(['--kernel', '--cc', '--mke2fs', '--debugfs'])
		specs << [
			hosttest.Option{ name: '--accel', value: true, choices: ['tcg', 'hvf'] },
			hosttest.Option{ name: '--only-valid' },
		]
	} else {
		specs << options(['--original-reference'])
	}
	parsed := bh.parse(args, specs, [], 0, 'Usage: runtime --arch x86_64|aarch64 --loader EFI --firmware-code FILE --firmware-vars TEMPLATE --logs NEW [--kernel ELF] [--timeout SECONDS] [--secure-boot] [--backend sbsign|osslsigncode]\nNative EDK II variable enrollment is built in. --virt-fw-vars accepts an explicit native editor binary.')!
	parsed.require(['--arch', '--loader', '--firmware-code', '--firmware-vars', '--logs'])!
	if root { parsed.require(['--kernel'])! }
	work := bh.absolute(parsed.value('--logs', ''))
	if os.exists(work) || os.is_link(work) {
		return bh.ArgumentError{ message: 'logs directory already exists' }
	}
	timeout := parsed.integer('--timeout', if root { 90 } else { 40 })!
	if timeout <= 0 { return bh.ArgumentError{ message: 'timeout must be positive' } }
	bh.mkdirs(work)!
	return Runtime{
		arch:    parsed.value('--arch', '')
		loader:  os.real_path(parsed.value('--loader', ''))
		kernel:  if root {
			os.real_path(parsed.value('--kernel', ''))
		} else {
			''
		}
		code:    os.real_path(parsed.value('--firmware-code', ''))
		vars:    os.real_path(parsed.value('--firmware-vars', ''))
		work:    work
		timeout: timeout
		qemu:    parsed.value('--qemu', 'qemu-system-' + parsed.value('--arch', ''))
		accel:   parsed.value('--accel', 'tcg')
		secure:  parsed.has('--secure-boot')
		backend: parsed.value('--backend', 'sbsign')
	}, parsed
}

fn secure_runtime(original Runtime, options bh.Options, root bool) !Runtime {
	if !original.secure { return original }
	key, cert := original.work + '/test.key', original.work + '/test.crt'
	bh.quiet(['openssl', 'req', '-new', '-x509', '-newkey', 'rsa:2048', '-nodes', '-sha256', '-subj',
		'/CN=Vinix temporary ' + if root { 'verified root test' } else { 'UEFI test' }, '-days',
		'1', '-addext', 'extendedKeyUsage=codeSigning', '-keyout', key, '-out', cert])!
	os.chmod(key, 0o600)!
	vars := original.work + '/secure-vars.fd'
	if options.has('--virt-fw-vars') {
		executable := os.find_abs_path_of_executable(options.value('--virt-fw-vars', ''))!
		mut stream := os.open(executable)!
		header := stream.read_bytes(4)
		stream.close()
		if header.len != 4 || header[..2] == [u8(`#`), `!`] {
			return error('--virt-fw-vars must select a native executable; Python editors have been replaced by built-in V enrollment')
		}
		bh.run([executable, '--input', original.vars, '--enroll-cert', cert, '--add-db',
			'd4b396e7-cdd6-4a48-a2d1-d62a4c6e02ce', cert, '--microsoft-db', 'none', '--sb', '--output',
			vars])!
	} else {
		enroll_variables(original.vars, cert, vars)!
	}
	return Runtime{ ...original, key: key, certificate: cert, vars: vars }
}

fn strip_ansi(text string) string {
	mut output := []u8{}
	mut i := 0
	for i < text.len {
		if text[i] == 0x1b && i + 1 < text.len && text[i + 1] == `[` {
			i += 2
			for i < text.len && !(text[i] >= 0x40 && text[i] <= 0x7e) { i++ }
			if i < text.len { i++ }
		} else {
			output << text[i]
			i++
		}
	}
	return output.bytestr()
}

fn tail(text string, count int) string {
	return if text.len > count { text[text.len - count..] } else { text }
}

fn runtime_guest(runtime Runtime, bundle string, scenario string, expected string, attached string, probe ?u64) ! {
	variables := runtime.work + '/' + scenario + '-vars.fd'
	os.cp(runtime.vars, variables)!
	defer { os.rm(variables) or {} }
	log := runtime.work + '/' + scenario + '.log'
	os.write_file(log, '')!
	errors := runtime.work + '/' + scenario + '-qemu.log'
	mut argv := [runtime.qemu, '-m', '512', '-display', 'none', '-monitor', 'none', '-serial',
		'file:' + log, '-no-reboot', '-net', 'none', '-drive',
		'if=pflash,format=raw,readonly=on,file=' + runtime.code, '-drive',
		'if=pflash,format=raw,file=' + variables, '-drive',
		'if=none,id=boot,format=raw,readonly=on,file=fat:ro:' + bundle, '-device',
		'virtio-blk-pci,drive=boot']
	if attached != '' { argv << ['-smp', '2'] }
	if runtime.arch == 'x86_64' {
		argv << ['-machine', 'q35,smm=on', '-accel', 'tcg']
		if runtime.secure { argv << ['-global', 'driver=cfi.pflash01,property=secure,value=on'] }
		if attached != '' {
			argv << ['-device', 'piix3-ide,id=rootcontroller', '-drive',
				'if=none,id=rootdisk,format=raw,file=' + attached, '-device',
				'ide-hd,bus=rootcontroller.0,drive=rootdisk']
		}
	} else {
		argv << ['-machine', if attached != '' { 'virt,gic-version=3' } else { 'virt' }, '-accel',
			runtime.accel, '-cpu', if runtime.accel == 'hvf' { 'host' } else { 'max' }]
		if attached != '' {
			argv << ['-device', 'ramfb', '-drive', 'if=none,id=rootdisk,format=raw,file=' + attached,
				'-device', 'virtio-blk-device,drive=rootdisk']
		}
	}
	mut child := fixturehost.spawn_logged(argv, policyhost.environment(), policyhost.caller_arch(), '', errors)!
	defer { child.close_after(5) }
	deadline := time.sys_mono_now() + u64(runtime.timeout) * u64(time.second)
	mut changed := false
	mut text := ''
	for time.sys_mono_now() < deadline {
		policyhost.command_checkpoint()!
		if child.poll()! { break }
		text = strip_ansi(os.read_file(log)!)
		if attached != '' {
			if text.split('\n')[..text.split('\n').len - 1].any(it.starts_with('VERIFIED ROOT: FAIL')) {
				return error(scenario + ': guest assertion failed\n' + tail(text, 2500))
			}
			if scenario != 'valid' && text.contains('VERIFIED ROOT: START') {
				return error(scenario + ': invalid root reached init\n' + tail(text, 2000))
			}
			if block := probe {
				ready := text.split('\n')[..text.split('\n').len - 1].filter(it.starts_with('VERIFIED ROOT: READY'))
				if !changed && ready.len > 0 {
					if !ready.any(it.contains('mutation=' + block.str())) {
						return error('guest probe block disagrees with independently prepared fixture')
					}
					tamper(attached, block * 4096 + 17)!
					changed = true
				}
			}
		} else if scenario != 'valid' && text.contains('VERIFIED-BOOT: launch accepted') {
			return error(scenario + ': tampered bundle was launched')
		}
		if text.contains(expected) {
			println('PASS ' + runtime.arch + ' ' + scenario + ': ' + expected)
			return
		}
		time.sleep(100 * time.millisecond)
	}
	return error(scenario + ': expected diagnostic missing from ' + log + '\n' + tail(text, 2500) + '\n' + tail(os.read_file(errors) or { '' }, 2500))
}

fn enroll(runtime Runtime, bundle string, text string) ! {
	config := bundle + '/boot/limine.conf'
	os.write_file(config, text)!
	mut data := os.read_bytes(runtime.loader)!
	pe := bootpolicy.pe_info(data, runtime.arch)!
	for i, b in bootpolicy.digest(config)!.bytes() { data[int(pe.field) + i] = b }
	image := bundle + '/EFI/BOOT/' + bootpolicy.architecture(runtime.arch)!.loader
	if runtime.secure {
		unsigned := runtime.work + '/enrolled.efi'
		os.write_file_array(unsigned, data)!
		os.rm(image)!
		bh.sign(unsigned, image, runtime.key, runtime.certificate, runtime.backend)!
	} else {
		os.write_file_array(image, data)!
	}
}

pub fn tamper(image string, offset u64) ! {
	mut stream := os.open_file(image, 'r+b')!
	defer { stream.close() }
	stream.seek(i64(offset), .start)!
	mut byte := []u8{len: 1}
	if stream.read(mut byte)! != 1 { return error('tamper offset outside image') }
	byte[0] ^= 1
	stream.seek(i64(offset), .start)!
	if stream.write(byte)! != 1 { return error('tamper write stopped') }
	stream.flush()
	if C.fsync(stream.fd) != 0 { return os.error_posix() }
}

fn boot_fixture(work string, arch string, original string) !string {
	object := work + '/kernel.o'
	target := if arch == 'x86_64' { 'x86_64-unknown-none' } else { 'aarch64-unknown-none' }
	mut command := [os.getenv_opt('CC') or { 'clang' }, '-target', target, '-ffreestanding',
		'-fno-stack-protector', '-fno-pic', '-O2']
	command << if arch == 'x86_64' {
		['-mcmodel=kernel', '-mno-red-zone']
	} else {
		['-mgeneral-regs-only']
	}
	source := work + '/fixture.c'
	module_path := bh.root() + '/tests/verified-boot/bootfixture'
	if original != '' {
		os.cp(original, source)!
		bh.run(joined(command, ['-c', source, '-o', object]))!
	} else {
		hosttest.generate_module_with_capture(module_path, source, arch, [], module_capture)!
		sdk := os.getenv_opt(if arch == 'aarch64' {
			'VINIX_AARCH64_SYSROOT'
		} else {
			'VINIX_AMD64_SYSROOT'
		}) or {
			bh.root() + '/' + if arch == 'aarch64' {
				'build-aarch64-userland/sysroot'
			} else {
				'build-amd64-userland/sysroot'
			}
		}
		includes := if os.is_dir(sdk + '/include') {
			sdk + '/include'
		} else {
			sdk + '/usr/include'
		}
		if !os.is_file(includes + '/inttypes.h') {
			return error('Fixture sysroot has no inttypes.h: ' + sdk)
		}
		bh.run(joined(command, ['-I', includes, '-I', module_path, '-Wno-unused-function',
			'-Wno-unused-parameter', '-c', source, '-o', object]))!
	}
	executable := work + '/fixture.elf'
	linker := bh.root() + '/kernel/' + if arch == 'x86_64' {
		'linker.ld'
	} else {
		'linker-aarch64.ld'
	}
	bh.run([os.getenv_opt('LD') or { 'ld.lld' }, '-T', linker, '-z', 'max-page-size=0x4000', '-o',
		executable, object])!
	imports := bh.capture([os.getenv_opt('NM') or { 'nm' }, '-u', executable])!
	if imports.trim_space() != '' {
		return error('standalone boot fixture has unresolved symbols:\n' + imports)
	}
	hosttest.write_json(work + '/fixture-inputs.json', json2.Any({
		'arch':               json2.Any(arch)
		'original':           if original != '' {
			json2.Any(original)
		} else {
			json2.Any(json2.Null{})
		}
		'freestanding_flags': json2.Any(hosttest.strings(command))
		'source_sha256':      json2.Any(hosttest.file_digest(source)!)
		'elf_sha256':         json2.Any(hosttest.file_digest(executable)!)
		'undefined_symbols':  json2.Any([]json2.Any{})
	}))!
	return executable
}

fn boot_runtime(args []string) ! {
	original, options := runtime_options(args, false)!
	defer { os.rm(original.work + '/test.key') or {} }
	runtime := secure_runtime(original, options, false)!
	kernel := boot_fixture(runtime.work, runtime.arch, options.value('--original-reference', ''))!
	os.write_file_array(runtime.work + '/archive', bytes_joined('authenticated module contents\n'.bytes(), []u8{len: 1024}))!
	build := bh.Build{ arch: runtime.arch, loader: runtime.loader, kernel: kernel, initramfs: [runtime.work + '/archive'], output: runtime.work + '/valid', developer: !runtime.secure, key: runtime.key, certificate: runtime.certificate, backend: runtime.backend }
	bh.build(build)!
	runtime_guest(runtime, build.output, 'valid', 'VERIFIED-BOOT: launch accepted', '', none)!
	for scenario, filename in {
		'config':    'boot/limine.conf'
		'kernel':    'boot/vinix'
		'initramfs': 'boot/root-0.tar'
	} {
		bundle := runtime.work + '/' + scenario
		os.cp_all(build.output, bundle, false)!
		path := bundle + '/' + filename
		mut data := os.read_bytes(path)!
		data << 'tamper'.bytes()
		os.write_file_array(path, data)!
		runtime_guest(runtime, bundle, scenario, if scenario == 'config' {
			'CHECKSUM MISMATCH FOR CONFIG FILE'
		} else {
			'does not match!'
		}, '', none)!
	}
	if runtime.secure {
		bundle := runtime.work + '/unhashed'
		os.cp_all(build.output, bundle, false)!
		mut lines := os.read_file(bundle + '/boot/limine.conf')!.split('\n')
		for i, line in lines {
			if line.contains('module_path: ') { lines[i] = line.all_before('#') }
		}
		enroll(runtime, bundle, lines.join('\n').replace('hash_mismatch_panic: yes', 'hash_mismatch_panic: no'))!
		runtime_guest(runtime, bundle, 'unhashed', 'has no associated hash', '', none)!
		unsigned := bh.Build{ ...build, output: runtime.work + '/unsigned', developer: true, key: '', certificate: '' }
		bh.build(unsigned)!
		runtime_guest(runtime, unsigned.output, 'unsigned', 'Access Denied', '', none)!
		loader_bundle := runtime.work + '/loader'
		os.cp_all(build.output, loader_bundle, false)!
		path := loader_bundle + '/EFI/BOOT/' + bootpolicy.architecture(runtime.arch)!.loader
		mut data := os.read_bytes(path)!
		field := int(bootpolicy.pe_info(data, runtime.arch)!.field)
		data[field] = if data[field] != `a` { `a` } else { `b` }
		os.write_file_array(path, data)!
		runtime_guest(runtime, loader_bundle, 'loader', 'Access Denied', '', none)!
		println('PASS: temporary firmware trust anchor accepted signed boot and rejected unsigned/modified loaders.')
	} else {
		println('These tests exercise Limine enforcement with Secure Boot disabled; they do not verify firmware trust enrollment.')
	}
}
