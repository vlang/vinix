// SPDX-License-Identifier: GPL-2.0-or-later
module boottools

import cachecli
import json2
import os
import qmpclient
import sourcecommand
import strconv
import time

#flag -I @DIR
#flag -lz
#include "sdk.h"

fn C.compressBound(usize) usize
fn C.compress2(&u8, &usize, &u8, usize, i32) i32
fn C.crc32(usize, &u8, u32) usize

pub const ram_base = u64(0x40000000)
pub const ram_bytes = u64(0x80000000)
pub const stub_base = ram_base + 0x100000
pub const scratch_base = ram_base + 0x110000
pub const fake_aic = ram_base + 0x400000
pub const phys_base = ram_base + 0x800000
pub const virt_base = u64(0xfffffe0007004000)
pub const fb_width = 1024
pub const fb_height = 768
pub const fb_stride = fb_width * 4
pub const fb_base = ram_base + ram_bytes - 0x400000
pub const segment_bytes = 0x10000
pub const aic_size = 0x1cc000
pub const aic_mask_set = 0x10000 + 4 * 0x1000 + 8 * (0x1000 / 32)
pub const boot_marker = 'APPLE-BOOT: init reached user space'

fn cstr(text string) []u8 { return (text + '\x00').bytes() }

fn u32le(value u32) []u8 {
	mut data := []u8{}
	append_number(mut data, value, 4, true)
	return data
}

fn u64s(values ...u64) []u8 {
	mut data := []u8{}
	for value in values { append_number(mut data, value, 8, true) }
	return data
}

pub fn adt_node(properties map[string][]u8, children ...[]u8) []u8 {
	mut data := u32le(u32(properties.len))
	data << u32le(u32(children.len))
	for name, value in properties {
		data << name.bytes()
		data << []u8{len: 32 - name.len}
		data << u32le(u32(value.len))
		data << value
		data << []u8{len: (4 - value.len % 4) % 4}
	}
	for child in children { data << child }
	return data
}

pub fn build_adt(segment u64, with_aic bool) []u8 {
	wdt := adt_node({
		'name':        cstr('wdt')
		'compatible':  cstr('wdt,vinix-test')
		'wdt-version': u32le(3)
		'reg':         u64s(0x110000, 0x4000, 0x110200, 0x100, 0x110100, 4)
	})
	mut firmware_ranges := u64s(segment, 0, 0)
	firmware_ranges << u32le(segment_bytes)
	firmware_ranges << u32le(0)
	firmware := adt_node({
		'name':           cstr('test-asc')
		'segment-ranges': firmware_ranges
	})
	aic := adt_node({
		'name':                cstr('aic')
		'compatible':          cstr('aic,3')
		'reg':                 u64s(fake_aic - ram_base, aic_size)
		'aic-iack-offset':     u64s(0x40000)
		'cap0-offset':         u32le(4)
		'maxnumirq-offset':    u32le(0xc)
		'extint-baseaddress':  u32le(0x10000)
		'extintrcfg-stride':   u32le(0x4a00)
		'intmaskset-stride':   u32le(0x4a00)
		'intmaskclear-stride': u32le(0x4a00)
		'aicglbcfg-offset':    u32le(0x14)
	})
	mut children := [wdt, firmware]
	if with_aic { children << aic }
	arm_io := adt_node({
		'name':           cstr('arm-io')
		'#address-cells': u32le(2)
		'#size-cells':    u32le(2)
		'ranges':         u64s(0, ram_base, phys_base - ram_base)
	}, ...children)
	chosen := adt_node({
		'name':      cstr('chosen')
		'dram-base': u64s(ram_base)
		'dram-size': u64s(ram_bytes)
	})
	return adt_node({
		'name':           cstr('device-tree')
		'compatible':     cstr('vinix,qemu-iboot')
		'#address-cells': u32le(2)
		'#size-cells':    u32le(2)
	}, chosen, arm_io)
}

pub fn boot_args(devtree u64, size u32, top u64) ![]u8 {
	if devtree < phys_base || devtree - phys_base > ~u64(0) - virt_base {
		return error('DeviceTree outside boot virtual range')
	}
	mut data := []u8{len: 736}
	put(mut data, 0, 2, 2, true)
	put(mut data, 2, 2, 2, true)
	for index, value in [virt_base, phys_base, fb_base - phys_base, top] {
		put(mut data, 0x08 + index * 8, value, 8, true)
	}
	for index, value in [fb_base, u64(0), u64(fb_stride), u64(fb_width), u64(fb_height), u64(30)] {
		put(mut data, 0x28 + index * 8, value, 8, true)
	}
	put(mut data, 0x60, devtree - phys_base + virt_base, 8, true)
	put(mut data, 0x68, size, 4, true)
	put(mut data, 720, 0, 8, true)
	put(mut data, 728, ram_bytes, 8, true)
	return data
}

fn png_chunk(kind string, data []u8) []u8 {
	mut result := []u8{}
	append_number(mut result, u64(data.len), 4, false)
	result << kind.bytes()
	result << data
	crc_data := result[4..].clone()
	append_number(mut result, u64(C.crc32(0, crc_data.data, u32(crc_data.len))), 4, false)
	return result
}

pub fn framebuffer_png(pixels []u8, width int, height int, stride int) ![]u8 {
	if width <= 0 || height <= 0 || width > 10000 || height > 10000 || stride < width * 4 || i64(height - 1) * stride + width * 4 > pixels.len {
		return error('invalid framebuffer dimensions/data')
	}
	mut rows := []u8{cap: height * (1 + width * 3)}
	for y in 0 .. height {
		rows << u8(0)
		for x in 0 .. width {
			pixel := word(pixels, u64(y * stride + x * 4), 4, true)!
			for shift in [22, 12, 2] { rows << u8(pixel >> shift) }
		}
	}
	mut compressed := []u8{len: int(C.compressBound(usize(rows.len)))}
	mut length := usize(compressed.len)
	if C.compress2(compressed.data, &length, rows.data, usize(rows.len), 6) != 0 {
		return error('PNG compression failed')
	}
	mut header := []u8{}
	append_number(mut header, u64(width), 4, false)
	append_number(mut header, u64(height), 4, false)
	header << [u8(8), 2, 0, 0, 0]
	mut output := '\x89PNG\r\n\x1a\n'.bytes()
	output << png_chunk('IHDR', header)
	output << png_chunk('IDAT', compressed[..int(length)])
	output << png_chunk('IEND', []u8{})
	return output
}

pub struct BootOptions {
pub:
	kernel     string
	initramfs  string
	cmdline    string = 'vinix.qemu_platform=1'
	timeout    int    = 300
	keep       string
	screenshot string
	accel      string = 'tcg'
	no_aic     bool
	real_adt   bool
}

pub struct LoadFile {
pub:
	name    string
	address u64
	data    []u8
}

pub struct Preparation {
pub:
	files     []LoadFile
	segment   u64
	args_base u64
	with_aic  bool
}

pub fn prepare(image []u8, real_tree []u8, with_aic bool) !Preparation {
	adt_base := align(phys_base + u64(image.len), 0x4000)!
	provisional := if real_tree.len > 0 { real_tree } else { build_adt(0, with_aic) }
	args_base := align(adt_base + u64(provisional.len), 0x4000)!
	top := args_base + 0x4000
	segment := align(top, 0x200000)! + 0x100000
	adt := if real_tree.len > 0 { real_tree } else { build_adt(segment, with_aic) }
	if adt.len != provisional.len || segment + segment_bytes > fb_base {
		return error('image/DeviceTree exceeds iBoot RAM layout')
	}
	mut files := [LoadFile{'image.bin', phys_base, image}, LoadFile{'adt.bin', adt_base, adt},
		LoadFile{'boot_args.bin', args_base, boot_args(adt_base, u32(adt.len), top)!},
		LoadFile{'scratch.bin', scratch_base, []u8{len: 0x400, init: 0xff}},
		LoadFile{'segment.bin', segment, []u8{len: segment_bytes, init: 0xa5}}]
	if with_aic {
		mut aic := []u8{len: aic_size}
		put(mut aic, 4, 1000, 4, true)
		put(mut aic, 0xc, 0x1000, 4, true)
		files << LoadFile{'aic.bin', fake_aic, aic}
	}
	return Preparation{files, segment, args_base, with_aic}
}

fn build_stub(work string, arguments u64, entry u64) !string {
	object := work + '/fake_iboot.o'
	command([llvm() + '/clang', '--target=aarch64-none-elf', '-c', here() + '/tests/fake_iboot.S',
		'-o', object])!
	raw := work + '/fake_iboot.raw'
	command([llvm() + '/llvm-objcopy', '-O', 'binary', '--only-section=.text', object, raw])!
	mut data := os.read_bytes(raw)!
	if data.len < 16 { return error('truncated iBoot stub') }
	put(mut data, data.len - 16, arguments, 8, true)
	put(mut data, data.len - 8, entry, 8, true)
	path := work + '/fake_iboot.bin'
	os.write_file_array(path, data)!
	return path
}

pub fn launch_command(work string, socket string, stub string, preparation Preparation, accel string) ![]string {
	mut argv := ['qemu-system-aarch64', '-machine', 'virt,gic-version=3,virtualization=on', '-cpu',
		'max', '-accel', accel, '-smp', '1', '-m', (ram_bytes >> 20).str() + 'M', '-display', 'none',
		'-nodefaults', '-serial', 'file:' + work + '/serial.log', '-qmp',
		'unix:' + socket + ',server=on,wait=off', '-device', 'virtio-keyboard-device', '-device',
		'loader,file=' + stub + ',addr=0x' + stub_base.hex() + ',cpu-num=0,force-raw=on']
	for file in preparation.files {
		path := work + '/' + file.name
		os.write_file_array(path, file.data)!
		argv << ['-device', 'loader,file=' + path + ',addr=0x' + file.address.hex() + ',force-raw=on']
	}
	return argv
}

fn exited(pid int) !bool {
	return sourcecommand.child_exited(pid)
}

struct Run {
	work        string
	socket      string
	preparation Preparation
	options     BootOptions
mut:
	failures []string
	quit     bool
}

pub fn check_dumps(work string, preparation Preparation, real_adt bool, serial string) ![]string {
	mut failures := []string{}
	scratch := os.read_bytes(work + '/scratch.dump')!
	if !real_adt {
		if scratch.len < 0x20 || scratch[0x1c..0x20] != []u8{len: 4} {
			failures << "the watchdog's control register was not cleared"
		}
		if scratch.len < 0x104 || scratch[0x100..0x104] != []u8{len: 4} {
			failures << "the watchdog's second control word was not cleared"
		}
		if os.read_bytes(work + '/segment.dump')! != []u8{len: segment_bytes, init: 0xa5} {
			failures << 'the reserved firmware segment was overwritten'
		}
	}
	if preparation.with_aic {
		aic := os.read_bytes(work + '/aic.dump')!
		words := (1000 + 31) / 32
		if aic.len < aic_mask_set + 4 * words || aic[aic_mask_set..aic_mask_set + 4 * words] != []u8{len: 4 * words, init: 0xff} {
			failures << 'the kernel did not mask every AIC IRQ'
		}
		if aic.len <= 0x14 || aic[0x14] & 1 == 0 { failures << 'the kernel did not enable the AIC' }
		if !serial.contains('aic: masked') { failures << 'the kernel did not take the AICv3 path' }
	}
	return failures
}

fn monitor(pid int, context voidptr) ! {
	mut run := unsafe { &Run(context) }
	deadline := time.sys_mono_now() + u64(int_max(run.options.timeout, 0)) * u64(time.second)
	serial_path := run.work + '/serial.log'
	mut passed := false
	for time.sys_mono_now() < deadline && !exited(pid)! {
		cachecli.checkpoint()!
		if os.exists(serial_path) && os.read_file(serial_path)!.contains(boot_marker) {
			passed = true
			break
		}
		// Preserve one-second marker polling, with interrupt checkpoints inside.
		for _ in 0 .. 20 {
			cachecli.checkpoint()!
			time.sleep(50 * time.millisecond)
		}
	}
	if !passed { run.failures << 'PID 1 never printed its marker' }
	if exited(pid)! { return }
	mut dumps := [LoadFile{'scratch', scratch_base, []u8{len: 0x400}},
		LoadFile{'segment', run.preparation.segment, []u8{len: segment_bytes}}]
	if run.preparation.with_aic { dumps << LoadFile{'aic', fake_aic, []u8{len: aic_size}} }
	if run.options.screenshot != '' {
		dumps << LoadFile{'framebuffer', fb_base, []u8{len: fb_stride * fb_height}}
	}
	mut qmp := qmpclient.connect_checked(run.socket, time.sys_mono_now() + u64(60 * time.second), cachecli.cancelled)!
	defer { qmp.close() }
	for memory in dumps {
		qmp.set_deadline(time.sys_mono_now() + u64(60 * time.second))
		qmp.command('pmemsave', {
			'val':      json2.Any(memory.address)
			'size':     json2.Any(memory.data.len)
			'filename': json2.Any(run.work + '/' + memory.name + '.dump')
		})!
	}
	qmp.set_deadline(time.sys_mono_now() + u64(60 * time.second))
	qmp.command('quit', {})!
	quit_deadline := time.sys_mono_now() + u64(30 * time.second)
	for !exited(pid)! {
		cachecli.checkpoint()!
		if time.sys_mono_now() >= quit_deadline {
			return error('QEMU did not quit within 30 seconds')
		}
		time.sleep(50 * time.millisecond)
	}
	run.quit = true
	serial := if os.exists(serial_path) { os.read_file(serial_path)! } else { '' }
	run.failures << check_dumps(run.work, run.preparation, run.options.real_adt, serial)!
	if run.options.screenshot != '' {
		os.write_file_array(run.options.screenshot, framebuffer_png(os.read_bytes(run.work + '/framebuffer.dump')!, fb_width, fb_height, fb_stride)!)!
		println('framebuffer: ' + run.options.screenshot)
	}
}

pub fn run_prepared(argv []string, work string, socket string, preparation Preparation, options BootOptions) !int {
	defer { os.rm(socket) or {} }
	mut run := Run{ work: work, socket: socket, preparation: preparation, options: options }
	println('==> ' + argv[..int_min(12, argv.len)].join(' ') + ' ...')
	result := sourcecommand.run_owned(argv, os.environ(), cachecli.cancelled, monitor, unsafe { &run })!
	print(result.stdout)
	eprint(result.stderr)
	if !run.quit { run.failures << 'QEMU exited with status ' + result.status.str() }
	log := if os.exists(work + '/serial.log') { os.read_file(work + '/serial.log')! } else { '' }
	println('---- serial (last 60 lines) ----')
	lines := log.split_into_lines()
	println(lines[int_max(0, lines.len - 60)..].join('\n'))
	println('--------------------------------')
	for failure in run.failures { println('FAIL: ' + failure) }
	if run.failures.len == 0 { println('PASS: iBoot-style hand-off reached user space') }
	return if run.failures.len > 0 { 1 } else { 0 }
}

fn run_boot(options BootOptions) !int {
	command(['make', '-C', here(), '-s'])!
	work := sourcecommand.temporary('vinix-apple-boot')!
	defer { os.rmdir_all(work) or {} }
	result := boot_work(work, options) or {
		cause := err
		if options.keep != '' { retain_work(work, options.keep)! }
		return cause
	}
	if options.keep != '' { retain_work(work, options.keep)! }
	return result
}

pub fn retain_work(work string, destination string) ! {
	source := os.real_path(work)
	target := os.real_path(destination)
	if target == source || target.starts_with(source + '/') {
		return error('retained work destination is inside its source')
	}
	os.mkdir_all(destination)!
	os.cp_all(work, destination, true)!
}

fn boot_work(work string, options BootOptions) !int {
	initramfs := if options.initramfs != '' { options.initramfs } else { build_initramfs(work)! }
	data := packed_image(options.kernel, initramfs, options.cmdline, 1, u64(time.now().unix()))!
	adt := if options.real_adt { ioreg(true)!.data } else { []u8{} }
	preparation := prepare(data, adt, !options.no_aic && !options.real_adt)!
	stub := build_stub(work, preparation.args_base, phys_base + 0x800)!
	socket := os.temp_dir() + '/vinix-apple-boot-' + os.getpid().str() + '.sock'
	argv := launch_command(work, socket, stub, preparation, options.accel)!
	return run_prepared(argv, work, socket, preparation, options)
}

pub fn iboot_cli(argv []string) int {
	args := cachecli.arguments(argv, ['--kernel', '--initramfs', '--cmdline', '--timeout', '--keep',
		'--screenshot', '--accel'], []string{}, ['--no-aic', '--real-adt'], 0, 0, 'usage: qemu_iboot [--kernel ELF --initramfs TAR --cmdline TEXT --timeout SECONDS --keep DIR --screenshot PNG --accel NAME --no-aic --real-adt]') or {
		eprintln(err)
		return 2
	}
	timeout := strconv.atoi(args.value('--timeout', '300')) or {
		eprintln(err)
		return 2
	}
	guard := cachecli.own_commands()
	defer { guard.close() }
	return run_boot(BootOptions{ kernel: path_option(args, '--kernel', path_env('VINIX_KERNEL_DIR', repo() + '/kernel') + '/bin/vinix'), initramfs: path_option(args, '--initramfs', ''), cmdline: args.value('--cmdline', 'vinix.qemu_platform=1'), timeout: timeout, keep: path_option(args, '--keep', ''), screenshot: path_option(args, '--screenshot', ''), accel: args.value('--accel', 'tcg'), no_aic: '--no-aic' in args.options, real_adt: '--real-adt' in args.options }) or {
		eprintln(err)
		return if cachecli.cancelled() { cachecli.interrupt_status() } else { 1 }
	}
}
