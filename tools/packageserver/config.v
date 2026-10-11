// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module packageserver

import hosttest
import os
import strconv

#include <signal.h>
fn C.signal(i32, voidptr) voidptr
fn C.__atomic_store_n(&i32, i32, i32)
fn C.__atomic_load_n(&i32, i32) i32
__global ( pending_signal i32 )
fn interrupted(signal i32) { unsafe { C.__atomic_store_n(&pending_signal, signal, C.__ATOMIC_RELAXED) } }
pub fn cancelled() bool { return unsafe { C.__atomic_load_n(&pending_signal, C.__ATOMIC_RELAXED) } != 0 }
pub fn interrupt_status() int {
	signal := unsafe { C.__atomic_load_n(&pending_signal, C.__ATOMIC_RELAXED) }
	return if signal == 0 { 0 } else { 128 + int(signal) }
}
pub fn checkpoint() ! { if cancelled() { return error('package service interrupted') } }

pub struct Guard { interrupt voidptr terminate voidptr pipe voidptr }
pub fn own_service() Guard {
	unsafe { C.__atomic_store_n(&pending_signal, 0, C.__ATOMIC_RELAXED) }
	return Guard{unsafe { C.signal(C.SIGINT, voidptr(interrupted)) }, unsafe { C.signal(C.SIGTERM, voidptr(interrupted)) }, unsafe { C.signal(C.SIGPIPE, C.SIG_IGN) }}
}
pub fn (guard Guard) close() { unsafe { C.signal(C.SIGINT, guard.interrupt); C.signal(C.SIGTERM, guard.terminate); C.signal(C.SIGPIPE, guard.pipe) } }

pub struct Config {
pub:
	store string
	port int = 18081
	ready string
	maximum i64 = 1024 * 1024 * 1024
	source string
	extras []string
	ui2 string
	clipboard bool
}

pub fn parse(argv []string) !Config {
	mut values := {'store': '', 'port': '18081', 'ready-file': '', 'max-bytes': '1073741824', 'source-root': '', 'ui2-source': '', 'clipboard': ''}
	mut extras := []string{}
	mut index := 0
	for index < argv.len {
		argument := argv[index]
		if !argument.starts_with('--') { return error('unrecognized argument ' + argument) }
		prefix := argument[2..].all_before('=')
		options := ['store', 'port', 'ready-file', 'max-bytes', 'source-root', 'source-extra', 'ui2-source', 'clipboard']
		matches := options.filter(it.starts_with(prefix))
		if matches.len != 1 { return error('unknown or ambiguous option ' + argument) }
		name := matches[0]
		if name == 'clipboard' {
			if argument.contains('=') { return error('--clipboard takes no value') }
			values[name] = 'true'; index++; continue
		}
		value := if argument.contains('=') { argument.all_after('=') } else {
			index++
			if index >= argv.len || argv[index].starts_with('--') { return error('missing value for --' + name) }
			argv[index]
		}
		if name == 'source-extra' { extras << value } else { values[name] = value }
		index++
	}
	if values['store'] == '' { return error('--store is required') }
	port := strconv.atoi(values['port'])!
	maximum := strconv.parse_int(values['max-bytes'], 10, 64)!
	if port < 0 || port > 65535 { return error('port must be between 0 and 65535') }
	source := if values['source-root'] != '' { hosttest.module_resolve(values['source-root'])! } else { '' }
	ui2 := if values['ui2-source'] != '' { hosttest.module_resolve(values['ui2-source'])! } else if source != '' { source + '/third_party/ui2' } else { '' }
	if ui2 != '' && source == '' { return error('--ui2-source requires --source-root') }
	if source != '' {
		for number, extra in extras {
			if extra != '' && !safe_path(extra) { return error('source extra must stay below source root: ' + extra) }
			parts := extra.split('/').filter(it != '' && it != '.')
			extras[number] = if parts.len == 0 { '.' } else { parts.join('/') }
		}
		if !os.is_dir(source) { return error('source root is not a directory: ' + source) }
		if !os.is_file(ui2 + '/v.mod') { return error('ui2 source is not a checkout: ' + ui2) }
		for extra in extras {
			if !safe_path(extra) { return error('source extra must stay below source root: ' + extra) }
			resolved := hosttest.module_resolve(source + '/' + extra)!
			if resolved != source && !resolved.starts_with(source + '/') { return error('source extra resolves outside source root: ' + extra) }
		}
	}
	return Config{hosttest.module_resolve(values['store'])!, port, values['ready-file'], maximum, source, extras, ui2, values['clipboard'] == 'true'}
}

pub fn safe_path(path string) bool { return path != '' && !path.starts_with('/') && !path.split('/').contains('..') }

pub fn cli(argv []string) int {
	if argv == ['--help'] || argv == ['-h'] { println('qemu-package-store --store PATH [--port PORT] [--ready-file PATH] [--max-bytes N] [--source-root PATH] [--source-extra PATH] [--ui2-source PATH] [--clipboard]'); return 0 }
	config := parse(argv) or { eprintln(err); return 2 }
	guard := own_service(); defer { guard.close() }
	mut server := start(config) or { eprintln(err); return 1 }
	server.serve() or { eprintln(err); return 1 }
	signal := unsafe { C.__atomic_load_n(&pending_signal, C.__ATOMIC_RELAXED) }
	return if signal == 0 { 0 } else { 128 + int(signal) }
}
