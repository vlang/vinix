// SPDX-License-Identifier: GPL-2.0-or-later
//
// gpucheck: the evidence of the M1 GPU's acceptance sequence
// (docs/m1-agx-bringup.md) from one boot of Vinix, as a report to keep.
//
// It reads what the kernel published about the GPU: the driver's lines in the
// boot log, the render node's identity in /sys, its statistics and memory
// totals, and, as root, the raw firmware statistics. It renders with Vinix's
// Mesa (run-m1-agx-smoke) and, when Omarchy's Mesa root is there, with
// Omarchy's unmodified Mesa in a chroot of that root. It then reads the
// statistics again and counts the recovery lines the driver logged. The
// report goes to standard output and to a file in /root, which is on the M1's
// persistent Vinix disk.
//
//	gpucheck [--root DIR] [--out FILE] [--no-render]
//
// --root is Omarchy's Mesa root, as tests/omarchy-mesa/stage.v stages it
// (default /root/omarchy-mesa). --out is the report file (default
// /root/gpucheck-<seconds>.md). --no-render reads and runs nothing.
// Mounting in the root and rendering need root.
module main

import os
import time

#include <sys/mount.h>
#include <poll.h>

fn C.chroot(path &char) i32
fn C.mount(source &char, target &char, kind &char, flags u64, data voidptr) i32
fn C.umount2(target &char, flags i32) i32
fn C.poll(fds voidptr, count u64, timeout i32) i32

struct C.pollfd {
mut:
	fd      i32
	events  i16
	revents i16
}

const ms_bind = u64(4096)
const pollin = i16(1)
const default_root = '/root/omarchy-mesa'
const smoke = '/usr/bin/run-m1-agx-smoke'
const output_limit = 1 << 20
const shown_lines = 200

// What the driver logs when it recovers, as Asahi does
// (docs/m1-agx-bringup.md, step 6).
const recovery_lines = ['agx: Fault addr=', 'fault event without a valid G13 fault register',
	'GPU firmware did not halt', 'nothing to recover', 'no workqueue for channel error slot',
	'RecoverChannel doorbell send failed', 'timed out waiting for RecoverChannel']

struct Report {
mut:
	lines    []string
	problems int
}

fn (mut r Report) add(line string) {
	r.lines << line
}

fn (mut r Report) problem(text string) {
	r.problems++
	r.lines << '- **problem:** ${text}'
}

// Output, at most shown_lines of it, in a code block.
fn (mut r Report) block(text string) {
	if text.trim_space() == '' {
		r.lines << '(nothing)'
		return
	}
	lines := text.trim_right('\n').split_into_lines()
	shown := if lines.len > shown_lines { shown_lines } else { lines.len }
	r.lines << '```'
	for line in lines[..shown] {
		r.lines << line.replace('```', "'''")
	}
	if lines.len > shown_lines {
		r.lines << '... ${lines.len - shown_lines} more lines'
	}
	r.lines << '```'
}

fn word(path string) string {
	return (os.read_file(path) or { '' }).trim_space()
}

fn listing(path string) []string {
	mut names := os.ls(path) or { []string{} }
	names.sort()
	return names
}

struct Run {
mut:
	started   bool
	timed_out bool
	status    i32
	output    string
	sample    string // the drm- lines of its fdinfo, while it ran
}

fn (run Run) exited() bool {
	return run.started && !run.timed_out && run.status & 0x7f == 0
}

fn (run Run) outcome() string {
	if !run.started {
		return 'could not start'
	}
	if run.timed_out {
		return 'killed at its deadline'
	}
	if run.status & 0x7f == 0 {
		return 'exit ${(run.status >> 8) & 0xff}'
	}
	return 'signal ${run.status & 0x7f}'
}

// The drm- lines of every descriptor of `pid`, Linux's fdinfo client usage.
fn drm_fdinfo(pid int) string {
	mut lines := []string{}
	for fd in listing('/proc/${pid}/fdinfo') {
		text := os.read_file('/proc/${pid}/fdinfo/${fd}') or { continue }
		drm := text.split_into_lines().filter(it.starts_with('drm-'))
		if drm.len > 0 {
			lines << 'fd ${fd}:'
			lines << drm
		}
	}
	return lines.join('\n')
}

// Run argv, chrooted into `root` unless it is empty, for at most `seconds`.
// After `sample_after` seconds, if it is still running, its fdinfo is read.
fn run(root string, argv []string, env []string, seconds int, sample_after int) Run {
	mut result := Run{}
	mut fds := [2]i32{}
	if C.pipe(&fds[0]) != 0 {
		return result
	}
	// Everything the child uses is made before fork: it only execs.
	mut cargv := []&char{}
	for arg in argv {
		cargv << &char(arg.str)
	}
	cargv << unsafe { &char(nil) }
	mut cenv := []&char{}
	for entry in env {
		cenv << &char(entry.str)
	}
	cenv << unsafe { &char(nil) }
	pid := C.fork()
	if pid < 0 {
		C.close(fds[0])
		C.close(fds[1])
		return result
	}
	if pid == 0 {
		C.dup2(fds[1], 1)
		C.dup2(fds[1], 2)
		C.close(fds[0])
		C.close(fds[1])
		if root != '' && (C.chroot(&char(root.str)) != 0 || C.chdir(c'/') != 0) {
			C._exit(126)
		}
		C.execve(cargv[0], cargv.data, cenv.data)
		C._exit(127)
	}
	C.close(fds[1])
	result.started = true
	start := time.now()
	mut sampled := sample_after <= 0
	mut output := []u8{}
	for {
		elapsed := time.since(start).milliseconds()
		if !sampled && elapsed >= i64(sample_after) * 1000 {
			result.sample = drm_fdinfo(int(pid))
			sampled = true
		}
		if elapsed >= i64(seconds) * 1000 {
			C.kill(pid, 9)
			result.timed_out = true
			break
		}
		mut poll := C.pollfd{
			fd:     fds[0]
			events: pollin
		}
		if C.poll(&poll, 1, 200) <= 0 {
			continue
		}
		chunk, n := os.fd_read(int(fds[0]), 4096)
		if n <= 0 {
			break
		}
		if output.len < output_limit {
			output << chunk.bytes()
		}
	}
	C.close(fds[0])
	mut status := i32(0)
	C.waitpid(pid, unsafe { &int(&status) }, 0)
	result.status = status
	result.output = output.bytestr()
	return result
}

fn show_run(mut r Report, title string, run Run) {
	r.add('`${title}`: ${run.outcome()}')
	r.add('')
	r.block(run.output)
	r.add('')
}

// /proc, /sys, /dev and fresh /tmp and /run in the root, as a chroot needs.
fn mount_root(root string) []string {
	mut mounted := []string{}
	for entry in [['proc', 'proc', 'proc'], ['sysfs', 'sys', 'sysfs'], ['/dev', 'dev', ''],
		['tmpfs', 'tmp', 'tmpfs'], ['tmpfs', 'run', 'tmpfs']] {
		target := '${root}/${entry[1]}'
		kind := if entry[2] == '' { unsafe { &char(nil) } } else { &char(entry[2].str) }
		flags := if entry[2] == '' { ms_bind } else { u64(0) }
		if C.mount(&char(entry[0].str), &char(target.str), kind, flags, unsafe { nil }) == 0 {
			mounted << target
		}
	}
	return mounted
}

fn unmount_root(mounted []string) {
	for index := mounted.len - 1; index >= 0; index-- {
		C.umount2(&char(mounted[index].str), 0)
	}
}

struct Telemetry {
mut:
	jobs     u64
	busy_ns  u64
	messages u64
	stats    string
	memory   string
	raw      string
}

fn read_telemetry(node string, minor string) Telemetry {
	device := '/sys/class/drm/${node}/device'
	mut t := Telemetry{
		stats:  word(device + '/agx_stats')
		memory: word(device + '/gpu_memory')
		raw:    word('/sys/kernel/debug/dri/${minor}/asahi_stats')
	}
	for line in t.stats.split_into_lines() {
		if line.starts_with('jobs ') {
			t.jobs = line.all_after(' ').u64()
		} else if line.starts_with('busy_ns ') {
			t.busy_ns = line.all_after(' ').u64()
		}
	}
	for line in t.raw.split_into_lines() {
		if line.starts_with('messages count=') {
			t.messages = line.all_after('=').u64()
		}
	}
	return t
}

fn show_telemetry(mut r Report, t Telemetry) {
	r.add('agx_stats:')
	r.add('')
	r.block(t.stats)
	r.add('')
	r.add('gpu_memory:')
	r.add('')
	r.block(t.memory)
	r.add('')
	if t.raw == '' {
		r.add('asahi_stats could not be read (it needs root).')
	} else {
		r.add('asahi_stats:')
		r.add('')
		r.block(t.raw)
	}
	r.add('')
}

// The render node of the asahi driver, and its minor number.
fn render_node() (string, string) {
	for name in listing('/sys/class/drm') {
		if !name.starts_with('renderD') {
			continue
		}
		if word('/sys/class/drm/${name}/device/uevent').split_into_lines().any(it == 'DRIVER=asahi') {
			return name, name.all_after('renderD')
		}
	}
	return '', ''
}

fn boot_evidence(mut r Report) {
	r.add('## Boot evidence')
	r.add('')
	log := os.read_file('/proc/bootlog') or {
		r.problem('/proc/bootlog cannot be read: ${err}')
		return
	}
	lines := log.split_into_lines()
	driver := lines.filter(it.contains('agx:') && !it.contains('agx: FWLog'))
	firmware := lines.filter(it.contains('agx: FWLog')).len
	if driver.len == 0 {
		r.problem('the boot log has no agx lines: the GPU driver did not run, or its lines have left the 256 KiB boot log')
	} else if !driver.any(it.contains('agx: Apple GPU driver initialized successfully')) {
		r.problem('the GPU driver did not finish initializing')
	}
	r.block(driver.join('\n'))
	r.add('')
	r.add('${firmware} firmware log lines (`agx: FWLog`) are not shown.')
	r.add('')
}

fn identity(mut r Report, node string, minor string) {
	r.add('## Render node')
	r.add('')
	r.add('/dev/dri: ${listing('/dev/dri').join(', ')}')
	r.add('')
	if node == '' {
		r.problem('there is no render node of the asahi driver')
		r.add('')
		return
	}
	device := '/sys/class/drm/${node}/device'
	subsystem := os.readlink(device + '/subsystem') or { '' }
	uevent := word(device + '/uevent')
	char_entry := if os.exists('/sys/dev/char/226:${minor}') { 'is there' } else { 'is missing' }
	r.add('${node}: subsystem `${subsystem}`; `/sys/dev/char/226:${minor}` ${char_entry}')
	r.add('')
	r.block(uevent)
	r.add('')
	if !subsystem.ends_with('bus/platform') {
		r.problem('${node} is not on the platform bus, so Honeykrisp will not take it')
	}
	if !uevent.contains('OF_COMPATIBLE_0=apple,agx-t8103') {
		r.problem('the GPU device does not name apple,agx-t8103')
	}
}

const child_env = ['PATH=/usr/bin:/usr/sbin:/bin:/sbin', 'HOME=/tmp', 'XDG_RUNTIME_DIR=/run', 'LANG=C']

fn vinix_mesa(mut r Report) {
	r.add("## Rendering with Vinix's Mesa")
	r.add('')
	if !os.exists(smoke) {
		r.add('${smoke} is not installed in this image.')
		r.add('')
		return
	}
	result := run('', [smoke], child_env, 180, 0)
	show_run(mut r, smoke, result)
	if !result.output.contains('VINIX M1 AGX RENDER TEST: PASS') {
		r.problem("Vinix's Mesa did not render the triangle on the GPU")
	}
}

fn omarchy_mesa(mut r Report, root string) {
	r.add("## Rendering with Omarchy's Mesa")
	r.add('')
	if !os.exists(root + '/usr/bin/vulkaninfo') {
		r.add('No Omarchy Mesa root at ${root}; stage one with tests/omarchy-mesa/stage.v to run this part.')
		r.add('')
		return
	}
	mounted := mount_root(root)
	r.add('Root ${root}, ${mounted.len} of 5 mounts made in it.')
	r.add('')
	vulkan := run(root, ['/usr/bin/vulkaninfo', '--summary'], child_env, 120, 0)
	show_run(mut r, 'vulkaninfo --summary', vulkan)
	if !vulkan.output.contains('Apple M1') {
		r.problem('Honeykrisp found no Apple M1 GPU')
	}
	egl := run(root, ['/usr/bin/eglinfo', '-B'], child_env, 120, 0)
	show_run(mut r, 'eglinfo -B', egl)
	if !egl.output.contains('renderer: Apple M1') {
		r.problem(if egl.output.contains('llvmpipe') {
			'EGL rendered with llvmpipe, the software renderer, not the Apple GPU'
		} else {
			'EGL has no Apple M1 renderer'
		})
	}
	mut gears_env := child_env.clone()
	gears_env << 'EGL_PLATFORM=surfaceless'
	gears := run(root, ['/usr/bin/peglgears'], gears_env, 30, 2)
	show_run(mut r, 'peglgears', gears)
	r.add('Its DRM client usage two seconds in:')
	r.add('')
	r.block(gears.sample)
	r.add('')
	if !gears.output.contains('frames in') {
		r.problem('peglgears drew no frames')
	}
	if !gears.sample.contains('asahi') {
		r.problem('peglgears held no memory on the asahi device while it ran')
	}
	unmount_root(mounted)
}

fn recovery(mut r Report) {
	r.add('## Recovery')
	r.add('')
	log := os.read_file('/proc/bootlog') or { '' }
	mut seen := []string{}
	for line in recovery_lines {
		count := log.count(line)
		if count > 0 {
			seen << '`${line}` ${count} times'
		}
	}
	r.add(if seen.len == 0 {
		'The driver logged no recovery.'
	} else {
		'The driver logged: ${seen.join('; ')}. Keep the serial log.'
	})
	r.add('')
}

fn main() {
	mut root := default_root
	mut out := ''
	mut render := true
	mut index := 1
	for index < os.args.len {
		match os.args[index] {
			'--root', '--out' {
				if index + 1 >= os.args.len {
					eprintln('${os.args[index]} needs a value')
					exit(2)
				}
				if os.args[index] == '--root' {
					root = os.args[index + 1]
				} else {
					out = os.args[index + 1]
				}
				index += 2
			}
			'--no-render' {
				render = false
				index++
			}
			else {
				eprintln('usage: gpucheck [--root DIR] [--out FILE] [--no-render]')
				exit(2)
			}
		}
	}
	if out == '' && os.is_dir('/root') {
		out = '/root/gpucheck-${time.now().unix()}.md'
	}

	mut r := Report{}
	r.add('# M1 GPU check')
	r.add('')
	system := os.uname()
	mut about := ['kernel ${system.sysname} ${system.release} (${system.machine})']
	release := word('/etc/vinix-release')
	if release != '' {
		about << 'release ${release}'
	}
	for path in ['/sys/firmware/devicetree/base/model', '/proc/device-tree/model'] {
		model := word(path).trim('\0')
		if model != '' {
			about << model
			break
		}
	}
	r.add(about.join(', '))
	if os.getuid() != 0 {
		r.add('')
		r.add("Not run as root: the raw statistics cannot be read, and Omarchy's Mesa cannot be chrooted into.")
	}
	r.add('')
	boot_evidence(mut r)
	node, minor := render_node()
	identity(mut r, node, minor)
	r.add('## Telemetry before')
	r.add('')
	before := read_telemetry(node, minor)
	if node != '' {
		show_telemetry(mut r, before)
	} else {
		r.add('No render node, so no telemetry.')
		r.add('')
	}
	if render {
		vinix_mesa(mut r)
		omarchy_mesa(mut r, root)
		r.add('## Telemetry after')
		r.add('')
		if node != '' {
			after := read_telemetry(node, minor)
			show_telemetry(mut r, after)
			r.add('Jobs ${before.jobs} -> ${after.jobs}, busy ${before.busy_ns} -> ${after.busy_ns} ns, firmware statistics messages ${before.messages} -> ${after.messages}.')
			r.add('')
			if after.jobs <= before.jobs {
				r.problem('no job completed on the GPU while rendering')
			}
		} else {
			r.add('No render node, so no telemetry.')
			r.add('')
		}
	}
	recovery(mut r)
	r.add(if r.problems == 0 { 'No problems found.' } else { '${r.problems} problem(s) found.' })
	text := r.lines.join('\n') + '\n'
	print(text)
	if out != '' {
		os.write_file(out, text) or { eprintln('gpucheck: cannot write ${out}: ${err}') }
		eprintln('gpucheck: report written to ${out}')
	}
	exit(if r.problems == 0 { 0 } else { 1 })
}
