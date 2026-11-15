// SPDX-License-Identifier: GPL-2.0-or-later
module winecsource

import os
import json2
import tests.packages.winesource

pub struct File {
pub:
	path string
	resolved string
	sha256 string
}

pub struct Proof {
pub:
	format int = 1
	sources []File
	includes []File
}

fn record(path string) !string {
	st := os.lstat(path)!
	if st.get_filetype() != .regular || st.size < 1 || st.size > 16 * 1024 * 1024 {
		return error('C closure evidence must be a bounded ordinary file')
	}
	return os.read_file(path)
}

// Preserve include order and repetitions across both translation units. Other
// compiler diagnostics are retained verbatim but are not include observations.
pub fn trace(text string) ![]string {
	if text.contains('\r') || text.contains('\x00') { return error('invalid C include trace control byte') }
	mut paths := []string{}
	for line in text.split_into_lines() {
		mut depth := 0
		for depth < line.len && line[depth] == `.` { depth++ }
		if depth == 0 || depth >= line.len || line[depth] != ` ` { continue }
		path := line[depth + 1..]
		if !os.is_abs_path(path) || path.len > 4096 || paths.len >= 100000 {
			return error('invalid or oversized C include observation')
		}
		paths << path.clone()
	}
	if paths.len == 0 { return error('C include trace is empty') }
	return paths
}

fn capture(path string) !File {
	if !os.is_abs_path(path) || path.contains('\r') || path.contains('\n') || path.contains('\x00') {
		return error('C input path must be absolute without control bytes')
	}
	resolved := os.real_path(path)
	if os.lstat(resolved)!.get_filetype() != .regular {
		return error('C input must resolve to an ordinary file')
	}
	return File{path, resolved, winesource.file_digest(resolved)!}
}

fn discovery(command []string) ![]string {
	if command.len < 9 || command[1] != '-H' || command.filter(it == '-H').len != 1
		|| command[command.len - 4..command.len - 1] != ['-lm', '-lpthread', '-o']
		|| '-fsyntax-only' in command { return error('C closure compile argv differs') }
	mut result := command[..command.len - 4].clone()
	result.insert(1, '-fsyntax-only')
	return result
}

fn snapshot(command []string, text string) !Proof {
	mut sources := []File{}
	for path in command[command.len - 6..command.len - 4] { sources << capture(path)! }
	mut includes := []File{}
	for path in trace(text)! { includes << capture(path)! }
	return Proof{sources: sources, includes: includes}
}

fn invoke(command []string, log string) !string {
	os.write_file(log + '.argv.json', json2.encode(command) + '\n')!
	mut child := os.new_process(command[0])
	defer { child.close() }
	child.set_args(command[1..])
	child.set_redirect_stdio_merged()
	child.run()
	C.close(child.stdio_fd[0]); child.stdio_fd[0] = -1
	text := child.stdout_slurp()
	child.wait()
	os.write_file(log, text)!
	if child.code != 0 { return error('C closure command failed: ' + log) }
	return text
}

pub fn build(base []string, directory string, logs string) ! {
	mut command := base.clone()
	command.insert(1, '-H')
	discover := discovery(command)!
	before := snapshot(command, invoke(discover, logs + '/c-discover.log')!)!
	os.write_file(directory + '/c-inputs-before.json', json2.encode(before) + '\n')!
	actual := snapshot(command, invoke(command, logs + '/cc.log')!)!
	if before != actual { return error('C observed inputs changed during compilation') }
	os.write_file(directory + '/c-inputs-verified.json', json2.encode(actual) + '\n')!
	admit(directory, logs)!
}

pub fn admit(directory string, logs string) ! {
	before := json2.decode[Proof](record(directory + '/c-inputs-before.json')!)!
	verified := json2.decode[Proof](record(directory + '/c-inputs-verified.json')!)!
	if before.format != 1 || before.sources.len != 2 || before.includes.len == 0 || before != verified {
		return error('C closure input receipts differ')
	}
	command := json2.decode[[]string](record(logs + '/cc.log.argv.json')!)!
	if json2.decode[[]string](record(logs + '/c-discover.log.argv.json')!)! != discovery(command)! {
		return error('C closure discovery argv differs')
	}
	observed := trace(record(logs + '/cc.log')!)!
	if observed != trace(record(logs + '/c-discover.log')!)! || observed != before.includes.map(it.path) {
		return error('C closure include observations differ')
	}
	if command[command.len - 6..command.len - 4] != before.sources.map(it.path) {
		return error('C closure translation units differ')
	}
	for file in [...before.sources, ...before.includes] {
		if capture(file.path)! != file { return error('C closure input target or bytes changed: ' + file.path) }
	}
}

// Include these byte-bearing inputs in the retainer's artifact map as well.
pub fn inputs(directory string) !map[string]string {
	proof := json2.decode[Proof](record(directory + '/c-inputs-before.json')!)!
	mut result := map[string]string{}
	for file in [...proof.sources, ...proof.includes] { result[file.path] = file.sha256 }
	return result
}
