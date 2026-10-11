// SPDX-License-Identifier: GPL-2.0-or-later
module nativehost

import fixturehost
import guesthost
import hosttest
import json2
import os
import policyhost

pub struct Pin {
pub:
	source          string
	resolved_source string
	bytes           i64
	sha256          string
}

pub fn elf_input(path string, machine int, limit i64) !Pin {
	resolved := resolve(path)!
	size := os.file_size(resolved)
	if !os.is_file(resolved) || size < 64 || size > limit {
		return argument('Expected a bounded ELF file: ' + path)
	}
	mut file := os.open(resolved)!
	defer { file.close() }
	header := file.read_bytes(64)
	if header.len != 64 || header[..6] != [u8(0x7f), `E`, `L`, `F`, 2, 1]
		|| int(header[16]) + (int(header[17]) << 8) !in [2, 3]
		|| int(header[18]) + (int(header[19]) << 8) != machine {
		return argument('ELF architecture or type does not match: ' + path)
	}
	return Pin{path, resolved, size, hosttest.sha(resolved)!}
}

pub fn install_pin(pin Pin, destination string) ! {
	install(pin.resolved_source, destination)!
	if os.file_size(destination) != pin.bytes || hosttest.sha(destination)! != pin.sha256 {
		return error('Input changed while preparing the fixture: ' + pin.source)
	}
}

pub fn install(source string, destination string) ! {
	os.mkdir_all(os.dir(destination))!
	if os.is_link(destination) { os.rm(destination)! }
	if os.real_path(source) == os.real_path(destination) && os.exists(destination) { return }
	if os.is_file(destination) { os.chmod(destination, 0o600)! }
	hosttest.module_copy_file_preserving_stat(source, destination)!
}

fn root() string { return hosttest.root() }

fn here() string { return root() + '/tests/dota2' }

fn resolve(path string) !string { return hosttest.module_resolve(path)! }

struct ArgumentError {
	message string
}

fn (failure ArgumentError) msg() string { return failure.message }

fn (failure ArgumentError) code() int { return 2 }

fn argument(message string) IError { return ArgumentError{message} }

fn required(options guesthost.Options, names []string) ! {
	for name in names { if !options.has(name) { return argument('missing required ' + name) } }
}

fn parse(args []string, specifications []hosttest.Option, repeated []string, usage string) !guesthost.Options {
	return guesthost.parse(args, specifications, repeated, usage) or { return argument(err.msg()) }
}

fn positive(options guesthost.Options, key string, fallback int) !int {
	value := options.integer(key, fallback) or { return argument('invalid integer for ' + key) }
	if value <= 0 { return argument(key + ' must be positive') }
	return value
}

fn separate(work string, sources []string) ! {
	for source in sources {
		path := resolve(source)!
		if work == path || work.starts_with(path.trim_right('/') + '/') || path.starts_with(work.trim_right('/') + '/') {
			return argument('Fixture must be separate from every source directory')
		}
	}
}

fn fresh(work string) ! {
	if os.exists(work) || os.is_link(work) {
		return argument('Use a fresh work directory to preserve previous evidence')
	}
	os.mkdir_all(work)!
}

fn directories(rootfs string, paths []string) ! {
	for name in paths { os.mkdir_all(rootfs + '/' + name)! }
}

fn links(rootfs string, names []string) ! {
	for name in names { os.symlink('busybox', rootfs + '/bin/' + name)! }
	os.symlink('../lib/x86_64-linux-gnu/ld-linux-x86-64.so.2', rootfs + '/runtime/lib64/ld-linux-x86-64.so.2')!
}

fn run(argv []string) ! { policyhost.inherited(argv)! }

fn capture(argv []string) !string {
	result := fixturehost.capture_owned_bounded(argv, policyhost.environment(), policyhost.caller_arch(), '', -1, policyhost.command_interrupted, false)!
	if result.status != 0 {
		return error('Command failed: ' + hosttest.shell_join(argv) + '\n' + result.stdout + result.stderr)
	}
	return result.stdout
}

fn write_json(path string, value json2.Any) ! { hosttest.write_json(path, value)! }

fn print_json(value json2.Any) { println(json2.encode(value, prettify: true)) }

// Preserve arbitrary integer fields from transcript verdicts as JSON numbers.
fn merge_report(report map[string]json2.Any, verdict string) string {
	encoded := json2.encode(json2.Any(report))
	return encoded[..encoded.len - 1] + ',' + verdict[1..]
}

fn archive(rootfs string, work string, compressed bool) !string {
	path := guesthost.archive_tree(rootfs, work + '/initramfs.tar')!
	if !compressed { return path }
	run(['gzip', '-1', path])!
	return path + '.gz'
}

fn launch(work string, archive string, memory int, cpus int, runner string, network bool) !guesthost.Launch {
	// The native ISO producer appends its boot assets to an uncompressed tar.
	// Keep the captured compressed archive intact and provide a private copy.
	mut boot_archive := archive
	if archive.ends_with('.gz') {
		boot_archive = work + '/boot-initramfs.tar'
		run(['gzip', '-dk', archive])!
		os.mv(archive.trim_string_right('.gz'), boot_archive)!
	}
	configured := guesthost.launch_from('', boot_archive, work, work + '/kernel', 'aarch64', !network, runner)!
	mut argv := configured.command.clone()
	argv[argv.index('-m') + 1] = memory.str()
	argv[argv.index('-smp') + 1] = cpus.str()
	boot := argv.index('virtio-blk-device,drive=guest-iso')
	if boot >= 0 { argv[boot] = 'virtio-blk-pci,drive=guest-iso' }
	return guesthost.Launch{argv, configured.env}
}

fn hashes(rootfs string, files map[string]string) !map[string]string {
	mut result := map[string]string{}
	for name, _ in files { result[name] = hosttest.sha(rootfs + '/' + name)! }
	return result
}

fn copy_files(rootfs string, files map[string]string) ! {
	for name, source in files { install(source, rootfs + '/' + name)! }
}

pub fn command(family string, args []string) int {
	guard := policyhost.own_commands()
	defer { guard.close() }
	return dispatch(family, args) or {
		eprintln(err.msg())
		return if err.msg() in ['Guest run interrupted', 'Host test interrupted'] {
			130
		} else if err is ArgumentError {
			2
		} else {
			1
		}
	}
}

fn dispatch(family string, args []string) !int {
	return match family {
		'environment' { environment(args)! }
		'lavapipe' { lavapipe(args)! }
		'wake' { wake(args)! }
		'mmap' { mmap(args)! }
		'steam' { steam(args)! }
		'game' { game(args)! }
		else { return argument('Unknown Dota controller') }
	}
}
