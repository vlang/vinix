// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module main

import agxhost
import cachecli
import encoding.hex
import gamehost
import json2
import os
import time

fn C.raise(i32) i32

fn signal_when_ready(path string, signal i32) {
	deadline := time.now().unix_milli() + 4000
	for !os.exists(path) && time.now().unix_milli() < deadline {
		time.sleep(10 * time.millisecond)
	}
	assert os.exists(path)
	C.raise(signal)
}

struct VmFixture {
	root string
	work string
	mode string
}

fn generated(source string, output string, arch string, defines []string, pointer voidptr) !bool {
	context := unsafe { &VmFixture(pointer) }
	assert source == context.root + '/tests/linuxkpi/initfixture' && arch == 'amd64' && defines == ['nofloat']
	os.write_file(output, 'native generated init fixture')!
	return true
}

fn prepare_command(argv []string, environment map[string]string, _ bool, pointer voidptr) !bool {
	context := unsafe { &VmFixture(pointer) }
	if argv[0] == 'tar' {
		assert '--format=ustar' in argv && environment['COPYFILE_DISABLE'] == '1'
		os.write_file(argv[argv.index('-cf') + 1], 'controlled native archive fixture')!
	} else {
		assert '--target=x86_64-linux-musl' in argv && '-Wl,-e,_start' in argv
		os.write_file(argv[argv.index('-o') + 1], 'controlled native ELF fixture')!
	}
	assert !argv.any(it.ends_with('.py'))
	assert context.work != ''
	return true
}

fn prepare_iso(root string, environment map[string]string, pointer voidptr) !bool {
	context := unsafe { &VmFixture(pointer) }
	assert root == context.root && environment['VINIX_AMD64_INITRAMFS'].ends_with('/initramfs.tar') && environment['VINIX_AMD64_KERNEL'] == context.work + '/kernel'
	os.write_file(environment['VINIX_AMD64_ISO'], 'controlled native image fixture')!
	return true
}

fn mock_qemu() !bool {
	if !os.executable().ends_with('/mock-qemu') { return false }
	work := os.getenv('VINIX_KPI_VM_WORK')
	mode := os.getenv('VINIX_KPI_VM_MODE')
	assert os.args[1..4] == ['-M', 'q35,smm=off', '-m']
	assert '-smp' in os.args && os.args[os.args.index('-smp') + 1] == '4'
	serial := os.args[os.args.index('-serial') + 1].all_after('file:')
	os.write_file(work + '/qemu.pid', os.getpid().str())!
	if mode == 'early-exit' { exit(7) }
	metadata := agxhost.guest_metadata()!
	mut text := ''
	if mode == 'default' {
		text = metadata['MARKERS']!.as_array().last().str() + '\n'
	} else if mode !in ['timeout', 'interrupt', 'terminate'] {
		text = metadata['MARKERS']!.as_array().map(it.str()).join('\n') + '\n'
	}
	if mode in ['topology', 'unexpected-topology'] {
		text += metadata['TOPOLOGY_MARKER']!.str() + '\n'
	}
	if mode in ['mmap', 'unexpected-mmap'] { text += metadata['MMAP_LEASE_MARKER']!.str() + '\n' }
	if mode == 'failure' { text += 'self-test failed\n' }
	if mode == 'panic' { text += 'KERNEL PANIC\n' }
	if mode == 'large' {
		mut output := os.stdout()
		data := 'mock serial diagnostic\n'.repeat(60000)
		unsafe { output.write_full_buffer(data.str, usize(data.len))! }
	}
	os.write_file(serial, text)!
	for { time.sleep(10 * time.millisecond) }
	return true
}

fn cases(work string) ! {
	root := os.real_path(os.dir(@FILE) + '/../..')
	gamehost.mkdir(work)!
	os.write_file(work + '/kernel', 'unchanged kernel fixture')!
	executable := work + '/mock-qemu'
	os.cp(os.executable(), executable)!
	os.chmod(executable, 0o755)!
	before := os.ls('/dev/fd')!.len
	for index, mode in ['complete', 'default', 'topology', 'mmap', 'unexpected-topology',
		'unexpected-mmap', 'failure', 'panic', 'early-exit', 'timeout', 'large', 'interrupt',
		'terminate'] {
		state := work + '/case-' + index.str()
		os.rm(work + '/qemu.pid') or {}
		mut environment := os.environ()
		environment['VINIX_KPI_VM_WORK'] = work
		environment['VINIX_KPI_VM_MODE'] = mode
		encoded := environment.keys().map(it + '=' + environment[it]).join('\x00')
		// The real process primitive inherits the caller's environment.
		os.setenv('VINIX_KPI_VM_WORK', work, true)
		os.setenv('VINIX_KPI_VM_MODE', mode, true)
		row := {
			'root':              json2.Any(hex.encode(root.bytes()))
			'kernel':            json2.Any(hex.encode((work + '/kernel').bytes()))
			'state_dir':         json2.Any(hex.encode(state.bytes()))
			'firmware':          json2.Any(hex.encode((work + '/firmware.fd').bytes()))
			'limine_dir':        json2.Any(json2.Null{})
			'environment':       json2.Any(hex.encode(encoded.bytes()))
			'timeout_text':      json2.Any(if mode == 'timeout' { '0.3' } else { '5' })
			'qemu':              json2.Any(executable)
			'cc':                json2.Any('controlled-cc')
			'cpu':               json2.Any('max')
			'no_linuxkpi':       json2.Any(mode == 'default')
			'mmap_lease_test':   json2.Any(mode == 'mmap')
			'pci_topology_test': json2.Any(mode == 'topology')
		}
		context := VmFixture{ root: root, work: work, mode: mode }
		hooks := agxhost.LinuxGuestNativeHooks{ generate: generated, run: prepare_command, iso: prepare_iso, context: &context }
		mut failed := false
		mut signal_code := 0
		mut worker := []thread{}
		if mode in ['interrupt', 'terminate'] {
			worker << spawn signal_when_ready(work + '/qemu.pid', i32(if mode == 'interrupt' {
				C.SIGINT
			} else {
				C.SIGTERM
			}))
		}
		status := agxhost.linux_guest_native_with_hooks(row, hooks) or {
			failed = true
			signal_code = err.code()
			1
		}
		worker.wait()
		if mode in ['interrupt', 'terminate'] {
			assert signal_code == if mode == 'interrupt' { 130 } else { 143 }
		}
		expected := mode in ['complete', 'default', 'topology', 'mmap', 'large']
		assert (status == 0 && !failed) == expected, mode
		pid := os.read_file(work + '/qemu.pid')!.int()
		assert C.kill(i32(pid), 0) != 0 && C.errno == C.ESRCH
		if mode == 'large' {
			assert os.file_size(state + '/qemu.log') >= 1024 * 1024
		}
		assert os.ls('/dev/fd')!.len == before
		println('WHOLE NATIVE LINUX GUEST / original flags, marker policy, failure and PID/FD retirement: PASS ' + mode)
		flush_stdout()
	}
	os.unsetenv('VINIX_KPI_VM_WORK')
	os.unsetenv('VINIX_KPI_VM_MODE')
	os.write_file(work + '/passed', 'PASS 13\n')!
}

fn main() {
	if mock_qemu() or {
		eprintln(err)
		exit(1)
	} {
		return
	}
	guard := cachecli.own_commands()
	defer { guard.close() }
	if os.args.len != 2 { exit(2) }
	cases(os.args[1]) or {
		eprintln(err)
		exit(1)
	}
}
