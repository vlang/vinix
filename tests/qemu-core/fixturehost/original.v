// SPDX-License-Identifier: BSD-2-Clause
module fixturehost

import crypto.sha256
import hosttest
import os

const reference = 'bbf1e243e21ab58b46a4853c0e88383ff45b290a'
const reference_path = 'tests/qemu-core/test.c'
const reference_blob = 'f6868d5ad82b92c66d62ac8cedfe37892b121b3a'
const reference_sha = '3430d064beaef7fde111162176c7fe360def3cd3c8161cfc0898dfdd745cbedb'

// Normal production generation uses maintained V inputs, never this oracle.
pub fn original_source() !string {
	root := hosttest.root()
	blob := capture_in(['git', 'rev-parse', reference + ':' + reference_path], '', os.environ(), false, root, false)!.trim_space()
	source := capture_in(['git', 'show', reference + ':' + reference_path], '', os.environ(), false, root, true)!
	if blob != reference_blob || sha256.sum(source.bytes()).hex() != reference_sha {
		return error('Immutable independent C oracle provenance changed')
	}
	return source
}

pub fn outside_checkout(output string, message string) ! {
	path := hosttest.module_resolve(output)!
	root := hosttest.module_resolve(hosttest.root())!
	if path == root || path.starts_with(root.trim_right('/') + '/') { return error(message) }
}

pub fn stage_pending(source string, target string) ! {
	mkdir_all(target)!
	if source.contains('\x00') { return error('embedded null byte') }
	mut names := map[string]bool{}
	mut entries := os.ls(source) or { return file_error(source, err.code()) }
	entries.sort()
	for item in entries {
		name := if item.ends_with('.pending') { item[..item.len - '.pending'.len] } else { item }
		if !['.v', '.h', '.S'].any(name.ends_with(it)) { continue }
		if name in names {
			return error('Duplicate maintained/pending input: ' + source + '/' + name)
		}
		names[name] = true
		copyfile(source + '/' + item, target + '/' + name)!
	}
}

fn original_lines(source string) []string {
	mut lines := []string{}
	mut start := 0
	for index, ch in source.bytes() {
		if ch == `\n` {
			lines << source[start..index + 1]
			start = index + 1
		}
	}
	if start < source.len { lines << source[start..] }
	return lines
}

struct LineRange {
	first int
	last  int
}

fn original_reference(kind string, source string, guest bool) string {
	lines := original_lines(source)
	header := if kind == 'touch' {
		if guest { 'touchfixture_v_contract.h' } else { 'touch-model-native-abi.h' }
	} else {
		kind + '-oracle-native-abi.h'
	}
	mut text := '#include "' + header + '"\n'
	mut ranges := [LineRange{52, 58}]
	if kind in ['signal', 'touch', 'restart', 'nanosleep', 'blocked'] {
		ranges << LineRange{88, 95}
	}
	ranges << match kind {
		'signal' { [LineRange{543, 619}] }
		'touch' { [LineRange{169, 281}] }
		'restart' { [LineRange{620, 670}] }
		'nanosleep' { [LineRange{74, 74}, LineRange{82, 86}, LineRange{710, 743}] }
		'blocked' { [LineRange{671, 708}, LineRange{3377, 3390}] }
		'poll' { [LineRange{2404, 2425}] }
		'epoll' { [LineRange{2501, 2530}] }
		'int' { [LineRange{2535, 2544}] }
		else { []LineRange{} }
	}
	for span in ranges {
		text += '#line ' + span.first.str() + ' "test.c"\n' + lines[span.first - 1..span.last].join('')
	}
	text = text.replace('static int reap_ok(', 'int original_reap_ok(')
	if kind != 'blocked' { text = text.replace('reap_ok(child)', 'original_reap_ok(child)') }
	functions := match kind {
		'signal' { ['test_default_terminating_signals', 'test_signals_reach_a_busy_loop'] }
		'touch' { ['test_anonymous_first_touch'] }
		'restart' { ['test_syscall_restart'] }
		'nanosleep' { ['test_interrupted_nanosleep_remaining'] }
		'blocked' { ['exec_probe', 'test_exit_takes_down_blocked_threads'] }
		'poll' { ['test_pollfd_abi'] }
		'epoll' { ['test_epoll_abi_and_count'] }
		'int' { ['test_syscall_int_truncation'] }
		else { []string{} }
	}
	for name in functions {
		text = text.replace('static int ' + name + '(', 'int original_' + name + '(')
	}
	return text
}

fn reference_name(kind string) string {
	return if kind == 'signal' { 'original-signals' } else { 'original-' + kind }
}

fn provider_name(kind string, guest bool) string {
	return kind + if kind == 'touch' && !guest { 'model' } else { 'oracle' }
}

pub fn prepare(kind string, output string, arch string, guest bool) ! {
	outside_checkout(output, 'Recover immutable C only outside the maintained checkout')!
	mkdir_all(output)!
	source := original_source()!
	for name in [kind + 'fixture', provider_name(kind, guest)] {
		stage_pending(hosttest.root() + '/tests/qemu-core/' + name, output + '/' + name)!
		defines := if guest && kind != 'touch' { [kind + '_guest'] } else { []string{} }
		hosttest.generate_module(output + '/' + name, output + '/' + name + '.c', arch, defines)!
	}
	hosttest.emit_module_header(output + '/' + kind + 'fixture', output + '/' + kind + 'fixture.c', output + '/' + kind + 'fixture-api.h')!
	write(output + '/' + reference_name(kind) + '.c', original_reference(kind, source, guest))!
	write_schema(output + '/original-source.json', source_schema(kind))!
}

pub fn generate(output string, arch string) ! {
	outside_checkout(output, 'Generate ephemeral C artifacts outside the maintained checkout')!
	mkdir_all(output)!
	for kind in ['signal', 'touch', 'restart', 'nanosleep', 'blocked', 'poll', 'epoll', 'int'] {
		name := kind + 'fixture'
		stage_pending(hosttest.root() + '/tests/qemu-core/' + name, output + '/' + name)!
		hosttest.generate_module(output + '/' + name, output + '/' + name + '.c', arch, []string{})!
		hosttest.emit_module_header(output + '/' + name, output + '/' + name + '.c', output + '/' + name + '-api.h')!
	}
}
