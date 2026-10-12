// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module main

import agxhost
import cachecli
import encoding.hex
import gamehost
import hosttest
import json2
import math
import os
import perfreport
import renderhost
import sourcecommand
import time

#flag -I @DIR
#include "test-abi.h"
#include <zlib.h>
#flag -lz

fn C.gzopen(&char, &char) voidptr
fn C.gzread(voidptr, voidptr, u32) i32
fn C.gzclose(voidptr) i32

struct C.termios {}

@[typedef]
struct C.vinix_render_test_address {
mut:
	sun_len    u8
	sun_family u16
	sun_path   [108]char
}

fn C.tcgetattr(i32, &C.termios) i32
fn C.tcsetattr(i32, i32, &C.termios) i32
fn C.cfmakeraw(&C.termios)
fn C.raise(i32) i32
fn C.listen(i32, i32) i32
fn C.accept(i32, voidptr, voidptr) i32
fn C.fork() i32

fn emit(text string) ! {
	mut out := os.stdout()
	unsafe { out.write_full_buffer(text.str, usize(text.len))! }
	out.flush()
}

fn raw_terminal() {
	mut settings := C.termios{}
	assert C.tcgetattr(0, &settings) == 0
	C.cfmakeraw(&settings)
	assert C.tcsetattr(0, C.TCSANOW, &settings) == 0
}

fn input_until(last u8) !string {
	mut out := []u8{}
	for {
		mut byte := u8(0)
		count := C.read(0, &byte, 1)
		if count != 1 { return error('mock input ended') }
		out << byte
		if byte == last { return out.bytestr() }
	}
	return ''
}

fn smoke_body() string {
	return 'smp: 4 CPUs online\nVINIX_VIRGL_NETWORK_PASS\nGL_RENDERER=virgl (Apple M2)\ngl-triangle-agx: hardware frame rendered successfully\nVINIX VIRGL RENDER TEST: PASS\n'
}

fn desktop_body() string {
	return 'smp: 4 CPUs online\nvinix-desktop: GPU presentation enabled on virgl (Apple M2)\n' + renderhost.desktop_stages.map('vinix-desktop: GPU init: ' + it + '\n').join('') + 'vinix-desktop: ready\n'
}

fn g17_body() string {
	mut out := 'GL_RENDERER=Vinix Fake G17C (M5 Max ABI)\n'.repeat(8)
	out += 'attachment mode=depth depth=16 stencil=0\nattachment mode=stencil depth=0 stencil=8\n' + 'attachment mode=depth-stencil depth=24 stencil=8\n'.repeat(6)
	out += 'render submit and fence completed successfully; pixels unchecked\n'.repeat(6)
	for bits in ['1 1 0 0', '0 0 1 1', '1 1 1 1', '1 1 1 1', '1 1 1 1', '1 1 1 1'] {
		fields := bits.split(' ')
		out += 'fake-g17: first Mesa render verified; descriptor depth=' + fields[0] + ' depth-meta=' + fields[1] + ' stencil=' + fields[2] + ' stencil-meta=' + fields[3] + '\n'
	}
	for marker in ['overlapping Mesa binding rejected', 'Mesa binding unbound and reused',
		'referenced depth metadata unbound', 'referenced depth metadata made read-only',
		'referenced GEM handle closed while job pending', 'GPU VA reuse blocked while job pending',
		'in-flight unbind rejected', 'in-flight queue destroy rejected',
		'GPU VA reused after retirement'] {
		out += 'vinix-agx-fault: ' + marker + '\n'
	}
	return out + 'vinix-agx-fault: invalid Mesa resource submission rejected\n'.repeat(2)
}

fn qmp_server(listener i32, work string) {
	client := C.accept(listener, unsafe { nil }, unsafe { nil })
	assert client >= 0
	greeting := '{"QMP":{}}\n'
	assert C.write(client, greeting.str, usize(greeting.len)) == greeting.len
	mut buffer := [4096]u8{}
	count := C.read(client, &buffer[0], buffer.len)
	assert count > 0 && buffer[..count].bytestr().contains('qmp_capabilities')
	reply := '{"return":{}}\n'
	assert C.write(client, reply.str, usize(reply.len)) == reply.len
	next := C.read(client, &buffer[0], buffer.len)
	assert next > 0 && buffer[..next].bytestr().contains('quit')
	os.write_file(work + '/qmp-observed', 'capabilities then quit\n') or { panic(err) }
	C.close(client)
	C.close(listener)
	exit(0)
}

fn mock() !bool {
	if os.args.len == 3 && os.args[1..] == ['-device', 'help'] {
		println(if os.getenv('VINIX_RENDER_DEVICE') == 'bad' {
			'unrelated-device'
		} else {
			'virtio-gpu-gl-device'
		})
		return true
	}
	if os.executable().ends_with('/run-native') {
		assert os.args[1] == '--arch' && os.args[2] in ['aarch64', 'x86_64']
		assert '--prebuilt-init' in os.args && '--timeout' in os.args
		assert !os.args.any(it.ends_with('.py'))
		init := os.args[os.args.index('--prebuilt-init') + 1]
		data := os.read_bytes(init)!
		assert data.len > 20 && data[..4] == [u8(127), `E`, `L`, `F`]
		assert data[18] == if os.args[2] == 'aarch64' { 183 } else { 62 }
		assert os.args[os.args.index('--timeout') + 1] == '600'
		state := gamehost.parent(os.args[os.args.index('--state-dir') + 1])
		os.write_file(state + '/native-boot-argv.json', json2.encode(os.args[1..]))!
		return true
	}
	if os.args.len < 2 || os.args[1] !in ['mock-virgl', '--no-build'] { return false }
	mode := os.getenv('VINIX_RENDER_MODE')
	family := os.getenv('VINIX_RENDER_FAMILY')
	work := os.getenv('VINIX_RENDER_WORK')
	raw_terminal()
	if mode == 'kill' { unsafe { C.signal(C.SIGTERM, C.SIG_IGN) } }
	os.write_file(work + '/child.pid', os.getpid().str())!
	if mode == 'descendant' {
		pid := C.fork()
		assert pid >= 0
		if pid == 0 {
			unsafe { C.signal(C.SIGTERM, C.SIG_IGN) }
			os.write_file(work + '/descendant.pid', os.getpid().str())!
			for { time.sleep(10 * time.millisecond) }
		}
		for !os.exists(work + '/descendant.pid') { time.sleep(time.millisecond) }
	}
	if mode == 'early' { exit(7) }
	if family == 'g17' {
		assert os.args[1..] == ['--no-build', '--serial', '--fake-g17', '--no-persist', '--mem=8192']
		assert os.getenv('VINIX_QEMU_PACKAGE_STORE_PORT').int() > 0
		assert os.getenv('VINIX_BOOT_DISK').ends_with('/boot.img') && os.getenv('VINIX_EFIVARS').ends_with('/efivars.fd')
		if mode == 'qmp' {
			path := os.getenv('VINIX_QEMU_EXTRA').all_after('-qmp unix:').all_before(',server=on')
			listener := C.socket(C.AF_UNIX, C.SOCK_STREAM, 0)
			assert listener >= 0
			mut address := C.vinix_render_test_address{}
			address.sun_family = C.AF_UNIX
			$if darwin {
				address.sun_len = u8(sizeof(C.vinix_render_test_address))
			}
			unsafe { C.memcpy(&address.sun_path[0], path.str, usize(path.len)) }
			assert C.bind(listener, &address, u32(sizeof(C.vinix_render_test_address))) == 0
			assert C.listen(listener, 1) == 0
			spawn qmp_server(listener, work)
		}
		if mode !in ['timeout', 'interrupt', 'terminate'] {
			emit('\x1b[?2004h')!
			command := input_until(`\n`)!
			assert command.starts_with('rc=0; for mode in --depth --stencil --depth-stencil;')
			assert command.contains('for fault in overlap rebind lifetime;') && command.contains('for fault in unbind readonly;')
			os.write_file(work + '/guest-command', command)!
			if mode == 'large' { emit('native diagnostic\n'.repeat(80000))! }
			emit(g17_body())!
			emit(if mode == 'fail' {
				'VINIX_FAKE_G17_VM_FAIL:3\n'
			} else {
				'VINIX_FAKE_G17_VM_PASS\n'
			})!
		}
	} else if mode !in ['timeout', 'interrupt', 'terminate', 'kill'] {
		if mode == 'large' { emit('native diagnostic\n'.repeat(80000))! }
		emit(if mode == 'desktop' { desktop_body() } else { smoke_body() })!
		marker := if mode == 'desktop' {
			'VINIX_GPU_DESKTOP_VM_PASS\n'
		} else if mode == 'fail' {
			'VINIX_VIRGL_VM_FAIL:5\n'
		} else if mode == 'invalid' {
			'prefix VINIX_VIRGL_VM_PASS\n'
		} else {
			'VINIX_VIRGL_VM_PASS\n'
		}
		if mode == 'split' {
			for ch in marker.bytes() {
				emit([ch].bytestr())!
				time.sleep(time.millisecond)
			}
		} else {
			emit(marker)!
		}
	}
	if mode in ['timeout', 'invalid', 'interrupt', 'terminate', 'kill'] {
		for { time.sleep(10 * time.millisecond) }
	}
	if mode == 'qmp' {
		for { time.sleep(10 * time.millisecond) }
	}
	shutdown := input_until(`x`)!
	assert shutdown.ends_with('\x01x')
	os.write_file(work + '/shutdown-observed', hex.encode(shutdown.bytes()))!
	exit(if mode == 'nonzero' { 7 } else { 0 })
	return true
}

fn signal_ready(path string, signal i32) {
	until := time.sys_mono_now() + 5 * time.second
	for !os.exists(path) && time.sys_mono_now() < until { time.sleep(10 * time.millisecond) }
	assert os.exists(path)
	time.sleep(30 * time.millisecond)
	C.raise(signal)
}

fn policy(corpus string) ! {
	guard := cachecli.own_commands()
	defer { guard.close() }
	archive := C.gzopen(corpus.str, c'rb')
	if archive == unsafe { nil } { return error('cannot open original corpus') }
	defer { C.gzclose(archive) }
	mut buffer := []u8{len: 65536}
	mut pending := ''
	mut n := 0
	for {
		count := C.gzread(archive, buffer.data, u32(buffer.len))
		if count < 0 { return error('original corpus decompression failed') }
		if count == 0 { break }
		pending += buffer[..count].bytestr()
		lines := pending.split('\n')
		pending = lines.last().clone()
		for line in lines[..lines.len - 1] {
			pair := json2.decode[[]json2.Any](line)!
			assert pair.len == 2
			input := pair[0].as_map()
			expected := pair[1]
			if n == 0 {
				println('frozen original fields: ' + input.keys().str() + ' result: ' + expected.as_map().keys().str())
			}
			text := hex.decode(input['text_hex']!.str())!.bytestr()
			actual := {
				'prompt':    json2.Any(agxhost.vm_shell_prompt(text))
				'pass':      json2.Any(agxhost.vm_line_marker(text, false))
				'fail':      json2.Any(agxhost.vm_line_marker(text, true))
				'resources': json2.Any(agxhost.vm_resource_states(text).map(json2.Any(it)))
				'missing':   json2.Any(agxhost.vm_missing(text, input['command_sent']!.bool(), input['pass_seen']!.bool(), input['fail_seen']!.bool(), input['forced_stop']!.bool(), input['status']!.int(), input['has_status']!.bool()).map(json2.Any(it)))
				'exit_code': json2.Any(agxhost.vm_child_exit_code(input['status']!.int()))
			}
			wanted := expected.as_map()
			for key in ['prompt', 'pass', 'fail'] {
				assert actual[key]!.bool() == wanted[key]!.bool(), n.str() + '/' + key
			}
			for key in ['resources', 'missing'] {
				assert actual[key]!.as_array().map(it.str()) == wanted[key]!.as_array().map(it.str()), n.str() + '/' + key
			}
			assert actual['exit_code']!.int() == wanted['exit_code']!.int(), n.str()
			n++
		}
	}
	assert pending == ''
	assert n == 71944
	for desktop in [false, true] {
		for failed in [false, true] {
			name := (if desktop { 'VINIX_GPU_DESKTOP_VM_' } else { 'VINIX_VIRGL_VM_' }) + if failed {
				'FAIL:7'
			} else {
				'PASS'
			}
			for prefix in ['', '\n', '\r\n', '\r\r\n', 'x', '\r', '\nx'] {
				for suffix in ['', '\r', '\r\n', '\n', 'junk', '\rjunk'] {
					starts := prefix == '' || prefix.ends_with('\n')
					ends := !desktop || suffix in ['', '\r', '\r\n', '\n']
					assert renderhost.virgl_line(prefix + name + suffix, desktop, failed) == (starts && ends)
				}
			}
		}
	}
	assert renderhost.virgl_missing(smoke_body(), false, true, false, false, true, 0).len == 0
	assert renderhost.virgl_missing(desktop_body(), true, true, false, false, true, 0).len == 0
	assert renderhost.virgl_missing(smoke_body(), false, false, true, true, true, -15) == [
		'guest test-init PASS marker',
		'guest test-init reported failure',
		'VM did not exit after the result',
		'VM exit status 143',
	]
	assert renderhost.virgl_missing('', true, false, false, false, false, 0)[2] == "desktop stage 'entered main'"
	for text, quoted in {
		'plain':                              "'plain'"
		"it's":                               '"it\'s"'
		'\t\x00\u00a0\u200b\ue000\U0001ffff': "'\\t\\x00\\xa0\\u200b\\ue000\\U0001ffff'"
		'雪😀':                               "'雪😀'"
	} {
		assert perfreport.quoted(text) == quoted
	}
	assert perfreport.integer_text('  +٠١_２３  ')! == '123'
	assert perfreport.integer_text('9'.repeat(400))! == '9'.repeat(400)
	assert perfreport.integer_text('-000')! == '0'
	println('PASS 71944 frozen original G17 cases and native VirGL marker/report controls')
}

fn processes(work string) ! {
	gamehost.mkdir(work)!
	child_exe := work + '/child'
	os.cp(os.executable(), child_exe)!
	os.chmod(child_exe, 0o755)!
	before := os.ls('/dev/fd')!.len
	for family in ['virgl', 'g17'] {
		for index, mode in if family == 'g17' {
			['pass', 'qmp', 'fail', 'early', 'timeout', 'large', 'descendant', 'kill', 'overflow',
				'interrupt', 'terminate']
		} else {
			['pass', 'desktop', 'split', 'large', 'descendant', 'fail', 'nonzero', 'early', 'invalid',
				'timeout', 'kill', 'overflow', 'interrupt', 'terminate']
		} {
			directory := work + '/' + family + '-' + index.str()
			gamehost.mkdir(directory + '/kernel/bin')!
			gamehost.mkdir(directory + '/scripts')!
			os.write_file(directory + '/kernel/bin/vinix', 'unchanged controlled kernel input')!
			os.cp(child_exe, directory + '/scripts/run-aarch64.sh')!
			os.chmod(directory + '/scripts/run-aarch64.sh', 0o755)!
			for key, value in {
				'VINIX_RENDER_WORK':   directory
				'VINIX_RENDER_FAMILY': family
				'VINIX_RENDER_MODE':   mode
			} {
				os.setenv(key, value, true)
			}
			guard := cachecli.own_commands()
			mut worker := []thread{}
			if mode in ['interrupt', 'terminate'] {
				worker << spawn signal_ready(directory + '/child.pid', i32(if mode == 'interrupt' {
					C.SIGINT
				} else {
					C.SIGTERM
				}))
			}
			timeout := if mode in ['timeout', 'invalid', 'kill'] { 0.2 } else { 8.0 }
			mut signal_code := 0
			mut output := ''
			status := if family == 'g17' {
				mut out := agxhost.Transcript{}
				result := out.vm_native_test(directory, if mode == 'overflow' {
					'9'.repeat(400)
				} else {
					timeout.str()
				}) or {
					signal_code = err.code()
					1
				}
				output = out.stdout
				result
			} else {
				result, bytes := renderhost.virgl_capture(renderhost.VirglLaunch{
					command:     [
						child_exe,
						'mock-virgl',
					]
					environment: os.environ()
					desktop:     mode == 'desktop'
				}, directory, if mode == 'overflow' { math.inf(1) } else { timeout }, false) or {
					signal_code = err.code()
					1, ''
				}
				output = bytes
				result
			}
			worker.wait()
			guard.close()
			assert (status == 0) == (mode in ['pass', 'qmp', 'desktop', 'split', 'large', 'descendant']), family + '/' + mode
			if mode in ['interrupt', 'terminate'] {
				assert signal_code == if mode == 'interrupt' { 130 } else { 143 }
			}
			pid := os.read_file(directory + '/child.pid')!.int()
			assert C.kill(i32(pid), 0) != 0 && C.errno == C.ESRCH
			if mode == 'descendant' {
				descendant := os.read_file(directory + '/descendant.pid')!.int()
				until := time.sys_mono_now() + 5 * time.second
				for C.kill(i32(descendant), 0) == 0 && time.sys_mono_now() < until {
					time.sleep(10 * time.millisecond)
				}
				assert C.kill(i32(descendant), 0) != 0 && C.errno == C.ESRCH
			}
			assert os.ls('/dev/fd')!.len == before
			if mode == 'large' {
				assert output.len > 1024 * 1024
			}
			if mode == 'qmp' {
				assert os.read_file(directory + '/qmp-observed')! == 'capabilities then quit\n'
			}
			if mode in ['pass', 'split', 'desktop', 'large', 'fail', 'nonzero'] {
				assert os.read_file(directory + '/shutdown-observed')!.ends_with('0178')
			}
			println('PASS whole native child ' + family + '/' + mode + ', exact PID/FD retirement')
			flush_stdout()
		}
	}
	for key in ['VINIX_RENDER_WORK', 'VINIX_RENDER_FAMILY', 'VINIX_RENDER_MODE'] {
		os.unsetenv(key)
	}
	os.write_file(work + '/passed', 'PASS 25 real child cases\n')!
}

struct RandomControl {
	root         string
	kernel       string
	compiler     string
	state        string
	primary      bool
	fail         bool
	guest_status int
mut:
	calls int
}

fn random_command(argv []string, environment map[string]string, pointer voidptr) !sourcecommand.Output {
	mut control := unsafe { &RandomControl(pointer) }
	control.calls++
	if argv[0] == 'git' {
		assert argv[1..] == ['-C', gamehost.parent(control.kernel), 'rev-parse', '--git-common-dir']
		return sourcecommand.Output{
			stdout: if control.primary {
				'.git\n'
			} else {
				control.root + '/primary/.git\n'
			}
		}
	}
	assert environment['VEXE'] == control.compiler
	if argv[0] == 'make' {
		assert argv[..9] == ['make', '-C', control.kernel, '-j4', 'CC=clang', 'V=' + control.compiler,
			'ARCH=aarch64', 'PROD=false', 'VFLAGS=-d krandom_selftest']
		for name in ['blob.c', 'blob.c.o', 'blob.c.d'] {
			assert !os.exists(control.kernel + '/obj/' + name)
		}
		return sourcecommand.Output{ status: if control.fail { 7 } else { 0 }, stdout: 'merged compiler log\n' }
	}
	assert argv == [control.root + '/tests/kernel-gaps/run-native', '--kernel-dir', control.kernel,
		'--arch', 'aarch64', '--source', control.root + '/tests/kernel-gaps/smokefixture/core.v',
		'--state-dir', control.state + '/guest', '--timeout', '240', '--expect',
		'RANDOM-RESEED: 10000 reseeds and partial reads PASS', '--expect', 'KERNEL GUEST RUNNER: PASS']
	return sourcecommand.Output{ status: control.guest_status }
}

fn recipes(work string) ! {
	host_guards(work + '/host')!
	gamehost.mkdir(work + '/isolated/kernel/obj')!
	compiler := work + '/v'
	os.write_file(compiler, 'native compiler controlled fixture')!
	for i, mode in ['primary', 'missing-compiler', 'success', 'failure', 'existing-state',
		'guest-failure', 'guest-signal'] {
		state := work + '/state-' + i.str()
		for name in ['blob.c', 'blob.c.o', 'blob.c.d'] {
			os.write_file(work + '/isolated/kernel/obj/' + name, 'old ordinary-build object')!
		}
		if mode == 'existing-state' { os.mkdir(state)! }
		mut control := RandomControl{
			root:         work
			kernel:       work + '/isolated/kernel'
			compiler:     if mode == 'missing-compiler' {
				compiler + '.missing'
			} else {
				compiler
			}
			state:        state
			primary:      mode == 'primary'
			fail:         mode == 'failure'
			guest_status: if mode == 'guest-failure' {
				7
			} else if mode == 'guest-signal' {
				-15
			} else {
				0
			}
		}
		tools := renderhost.Tools{ root: work, command_hook: random_command, context: &control }
		mut failed := false
		status := renderhost.krandom_cli(tools, ['--kernel-dir', control.kernel, '--v',
			control.compiler, '--state-dir', state, '--arch', 'aarch64']) or {
			failed = true
			if mode == 'failure' {
				assert err.code() == 7
			}
			1
		}
		assert failed == (mode !in ['success', 'guest-failure', 'guest-signal'])
		assert status == if mode == 'guest-failure' {
			7
		} else if mode == 'guest-signal' {
			-15
		} else if mode == 'success' {
			0
		} else {
			1
		}
		assert control.calls == if mode in ['primary', 'missing-compiler', 'existing-state'] {
			1
		} else if mode == 'failure' {
			2
		} else {
			3
		}
		if mode in ['success', 'failure', 'guest-failure', 'guest-signal'] {
			assert os.read_file(state + '/build.log')! == 'merged compiler log\n'
		}
	}
	println('PASS isolated kernel guard, exclusive state, stale-object eviction, build flags, logs and native guest delegation')
}

fn rejected(tools renderhost.Tools, machine string, system string, message string) ! {
	renderhost.virgl_prepare(tools, false, machine, system) or {
		assert err.code() == 2 && err.msg().contains(message), err.msg()
		return
	}
	return error('expected host guard: ' + message)
}

fn host_guards(work string) ! {
	gamehost.mkdir(work)!
	qemu := work + '/qemu'
	old_qemu := os.getenv_opt('VINIX_VIRGL_QEMU')
	defer {
		if value := old_qemu {
			os.setenv('VINIX_VIRGL_QEMU', value, true)
		} else {
			os.unsetenv('VINIX_VIRGL_QEMU')
		}
		os.unsetenv('VINIX_RENDER_DEVICE')
	}
	os.setenv('VINIX_VIRGL_QEMU', qemu, true)
	tools := renderhost.Tools{ root: work }
	rejected(tools, 'x86_64', 'Darwin', 'Apple-silicon')!
	rejected(tools, 'arm64', 'Linux', 'Apple-silicon')!
	rejected(tools, 'arm64', 'Darwin', 'VirGL QEMU is missing')!
	os.cp(os.executable(), qemu)!
	os.chmod(qemu, 0o644)!
	rejected(tools, 'arm64', 'Darwin', 'VirGL QEMU is missing')!
	os.chmod(qemu, 0o755)!
	os.setenv('VINIX_RENDER_DEVICE', 'bad', true)
	rejected(tools, 'arm64', 'Darwin', 'no MMIO virtio-gpu-gl-device')!
	os.unsetenv('VINIX_RENDER_DEVICE')
	rejected(tools, 'arm64', 'Darwin', 'Vinix kernel is missing')!
	gamehost.mkdir(work + '/kernel/bin')!
	os.write_file(work + '/kernel/bin/vinix', 'controlled kernel input')!
	rejected(tools, 'arm64', 'Darwin', 'Vinix initramfs is missing')!
	gamehost.mkdir(work + '/build-support/init-aarch64')!
	os.write_file(work + '/build-support/init-aarch64/initramfs.tar', 'controlled image input')!
	prepared := renderhost.virgl_prepare(tools, false, 'arm64', 'Darwin')!
	assert prepared.command == [work + '/scripts/run-aarch64.sh', '--no-build', '--no-persist',
		'--ephemeral', '--virgl', '--guest-init=' + work + '/tests/virtio-gpu-virgl/guest-init.sh']
	mut env := {
		'VINIX_QEMU_MEM':  ''
		'VINIX_INITRAMFS': 'inherited image'
		'unrelated':       'keep'
	}
	removed := ['QEMU_DISPLAY_BACKEND', 'VINIX_QEMU_PERSIST', 'VINIX_QEMU_PERSIST_DISK',
		'VINIX_QEMU_PERSIST_SEED', 'VINIX_QEMU_PERSIST_SIZE_MB', 'VINIX_QEMU_ROOT_DISK',
		'VINIX_QEMU_ROOT_IMAGE', 'VINIX_BOOT_DISK', 'VINIX_EFIVARS', 'VINIX_QEMU_PACKAGE_STORE']
	for key in removed { env[key] = 'remove' }
	for desktop in [false, true] {
		launch := renderhost.virgl_launch(work, qemu, 'selected image', 'guest init', desktop, 'scratch', env)
		assert launch.environment['VINIX_QEMU_MEM'] == '' && launch.environment['unrelated'] == 'keep'
		assert launch.environment['VINIX_INITRAMFS'] == if desktop {
			'inherited image'
		} else {
			'selected image'
		}
		assert launch.environment['TMPDIR'] == 'scratch' && removed.all(it !in launch.environment)
		fallback := renderhost.virgl_launch(work, qemu, 'image', 'guest', desktop, 'scratch', {})
		assert fallback.environment['VINIX_QEMU_MEM'] == if desktop { '12288' } else { '8192' }
	}
	println('PASS ordered host/device/input guards and both original launch environments')
}

fn native_inputs(root string, work string) ! {
	gamehost.mkdir(work + '/root/kernel/lib')!
	for name in ['agx_fake_g17.v', 'agx_fake_g17_encode.v'] {
		os.cp(root + '/kernel/lib/' + name, work + '/root/kernel/lib/' + name)!
	}
	gamehost.mkdir(work + '/root/kernel/c')!
	for name in ['agx_fake_g17.h', 'agx_fake_g17_encode.h'] {
		os.cp(root + '/kernel/c/' + name, work + '/root/kernel/c/' + name)!
	}
	gamehost.mkdir(work + '/root/tests/agx-fake-g17')!
	gamehost.mkdir(work + '/root/tests/kernel-gaps')!
	for name in ['encodefixture', 'verifyfixture'] {
		hosttest.module_copy_tree(root + '/tests/agx-fake-g17/' + name, work + '/root/tests/agx-fake-g17/' + name)!
	}
	for name in ['fixturedriver', 'serialcore'] {
		hosttest.module_copy_tree(root + '/tests/kernel-gaps/' + name, work + '/root/tests/kernel-gaps/' + name)!
	}
	os.cp(os.executable(), work + '/root/tests/kernel-gaps/run-native')!
	os.chmod(work + '/root/tests/kernel-gaps/run-native', 0o755)!
	for arch in ['aarch64', 'x86_64'] {
		for fixture in ['encoder', 'verifier'] {
			state := work + '/' + arch + '-' + fixture
			mut out := agxhost.Transcript{}
			status := out.native_fixture(work + '/root', arch, '/unchanged/kernel', state, '', fixture, '600', '', os.environ()) or {
				os.write_file(work + '/failed.stdout', out.stdout)!
				os.write_file(work + '/failed.stderr', out.stderr)!
				return err
			}
			assert status == 0
			args := json2.decode[[]string](os.read_file(state + '/native-boot-argv.json')!)!
			assert args[args.index('--kernel-dir') + 1] == '/unchanged/kernel'
			assert args.count(it == 'INDEPENDENT FIXTURE PASS') == 1 && args.count(it == 'INDEPENDENT FIXTURE FAIL') == 1
			expected_marker := if fixture == 'encoder' {
				'fake G17 recovered 3D encoder tests passed'
			} else {
				'fake G17 HAL300 verifier tests passed'
			}
			assert args.count(it == expected_marker) == 1
			println('PASS real native G17 static ELF and native boot delegation ' + arch + '/' + fixture)
			os.write_file(work + '/' + arch + '-' + fixture + '.stdout', out.stdout)!
			os.write_file(work + '/' + arch + '-' + fixture + '.stderr', out.stderr)!
		}
	}
	os.write_file(work + '/passed', 'PASS 4 real static ELFs; boot controlled, no guest run\n')!
}

fn main() {
	if mock() or { panic(err) } { return }
	if os.args.len < 3 { exit(2) }
	match os.args[1] {
		'policy' { policy(os.args[2]) or { panic(err) } }
		'processes' { processes(os.args[2]) or { panic(err) } }
		'recipes' { recipes(os.args[2]) or { panic(err) } }
		'native-inputs' {
			native_inputs(os.real_path(os.dir(@FILE) + '/../..'), os.args[2]) or { panic(err) }
		}
		else { exit(2) }
	}
}
