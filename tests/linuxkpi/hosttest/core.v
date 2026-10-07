// SPDX-License-Identifier: GPL-2.0-or-later
// Native host orchestration for the independent LinuxKPI compiler fixtures.
module hosttest

import os
import time
import crypto.sha256
import json2
import strconv

#include <signal.h>
#include <stdlib.h>
fn C.kill(i32, i32) i32
fn C.mkdtemp(&char) &char

pub struct Result {
pub:
	stdout string
	stderr string
	code   int
}

pub fn root() string {
	return os.dir(os.dir(os.dir(os.dir(@FILE))))
}

pub fn sha(path string) !string {
	return sha256.sum(os.read_bytes(path)!).hex()
}

pub fn text_sha(text string) string {
	return sha256.sum(text.bytes()).hex()
}

pub fn strings(items []string) []json2.Any {
	return items.map(json2.Any(it))
}

pub fn string_map(items map[string]string) map[string]json2.Any {
	mut result := map[string]json2.Any{}
	for key, value in items {
		result[key] = value
	}
	return result
}

pub fn hashes(paths []string) !map[string]string {
	mut result := map[string]string{}
	for path in paths {
		result[path] = sha(path)!
	}
	return result
}

pub fn write_json(path string, value json2.Any) ! {
	os.write_file(path, json2.encode(value, prettify: true, indent_string: '  ') + '\n')!
}

struct ExactNumber {
mut:
	value json2.Any
}

fn (mut number ExactNumber) from_json_number(raw string) ! {
	// Parse the original token, never a rounded f64. The integer parsers
	// reject values outside their native widths rather than narrowing them.
	number.value = if raw.contains('.') || raw.contains('e') || raw.contains('E') {
		json2.Any(strconv.atof64(raw)!)
	} else if raw.starts_with('-') {
		json2.Any(strconv.parse_int(raw, 10, 64)!)
	} else {
		json2.Any(strconv.parse_uint(raw, 10, 64)!)
	}
}

type ExactJson = []ExactJson | bool | ExactNumber | map[string]ExactJson | string | json2.Null

fn exact_any(value ExactJson) json2.Any {
	return match value {
		[]ExactJson { json2.Any(value.map(exact_any(it))) }
		map[string]ExactJson {
			mut result := map[string]json2.Any{}
			for key, item in value { result[key] = exact_any(item) }
			json2.Any(result)
		}
		ExactNumber { value.value }
		bool { json2.Any(value) }
		string { json2.Any(value) }
		json2.Null { json2.Any(value) }
	}
}

// Dynamic json2.Any prefers floats. Native file-state receipts include integer
// nanoseconds above 2^53, so decode the wire tokens as integers first.
pub fn decode_json(text string) !json2.Any {
	return exact_any(json2.decode[ExactJson](text, strict: true)!)
}

pub fn tool(name string) string {
	return os.find_abs_path_of_executable(name) or {
		os.join_path('/opt/homebrew/opt/llvm/bin', name)
	}
}

pub fn env_default(name string, fallback string) string {
	return os.getenv_opt(name) or { fallback }
}

// Capture both streams while the child runs, so neither pipe can fill and
// prevent the other from being read. The timeout uses a monotonic clock.
// kill(2) leaves Process running until wait() reaps it; signal_kill() marks it
// aborted before wait(), which would leave a timed-out child unreaped.
pub fn capture(argv []string, log string, timeout int, env map[string]string) !Result {
	if argv.len == 0 {
		return error('Empty command')
	}
	mut child := os.new_process(argv[0])
	child.set_args(argv[1..])
	child.set_environment(env)
	child.set_redirect_stdio()
	defer { child.close() }
	child.run()
	if child.pid <= 0 {
		return error('Cannot start command: ${argv[0]}')
	}
	started := time.sys_mono_now()
	mut stdout := ''
	mut stderr := ''
	mut timed_out := false
	for {
		stdout += child.stdout_read()
		stderr += child.stderr_read()
		if !child.is_alive() {
			break
		}
		if time.sys_mono_now() - started >= u64(timeout) * u64(time.second) {
			unsafe { C.kill(i32(child.pid), 9) }
			child.wait()
			timed_out = true
			break
		}
		time.sleep(time.millisecond)
	}
	stdout += child.stdout_slurp()
	stderr += child.stderr_slurp()
	if log != '' {
		os.write_file(log, json2.encode(argv) + '\n' + stdout + stderr)!
	}
	if timed_out {
		return error('Command timed out after ${timeout} seconds: see ${log}')
	}
	return Result{stdout: stdout, stderr: stderr, code: child.code}
}

pub fn command(argv []string, log string, timeout int, env map[string]string) !Result {
	result := capture(argv, log, timeout, env)!
	if result.code != 0 {
		return error('Command failed: see ${log}')
	}
	return result
}

pub fn run(argv []string, log string) !Result {
	return command(argv, log, 120, os.environ())
}

pub fn work_dir(keep string, prefix string) !string {
	if keep != '' {
		path := os.abs_path(keep)
		if os.exists(path) {
			return error('Output directory already exists: ${path}')
		}
		os.mkdir_all(os.dir(path))!
		os.mkdir(path)!
		return os.real_path(path)
	}
	mut pattern := (os.join_path(os.temp_dir(), prefix + 'XXXXXX') + '\x00').bytes()
	unsafe {
		result := C.mkdtemp(&char(pattern.data))
		if result == nil {
			return error('Cannot create private temporary directory')
		}
		return result.vstring()
	}
}

pub fn replace_suffix(path string, suffix string) string {
	return path[..path.len - os.file_ext(path).len] + suffix
}

pub fn word_char(ch u8) bool {
	return ch.is_alnum() || ch == `_`
}

pub fn has_word(text string, word string) bool {
	mut start := 0
	for start < text.len {
		offset := text[start..].index(word) or { return false }
		position := start + offset
		end := position + word.len
		if (position == 0 || !word_char(text[position - 1])) &&
			(end == text.len || !word_char(text[end])) {
			return true
		}
		start = position + 1
	}
	return false
}

// Preserve the exact slices selected by the original top-level C function
// pattern: a signature on one line, followed by its closing brace at column 0.
pub fn c_bodies(text string) []string {
	mut result := []string{}
	mut start := 0
	for start < text.len {
		end := start + (text[start..].index('\n') or { text.len - start })
		line := text[start..end]
		if line.contains('(') && !line.contains(';') && line.ends_with(' {') {
			if stop := text[end..].index('\n}') {
				result << text[start..end + stop + 2]
				start = end + stop + 2
				continue
			}
		}
		start = end + 1
	}
	return result
}

pub fn named_body(body string, name string) bool {
	line := body.all_before('\n')
	needle := name + '('
	position := line.index(needle) or { return false }
	return position == 0 || !word_char(line[position - 1])
}

pub fn record(text string, name string) !string {
	needle := 'struct ${name} {'
	start := text.index(needle) or { return error('Missing generated record ${name}') }
	end := start + (text[start..].index('\n};') or {
		return error('Unterminated generated record ${name}')
	}) + 3
	return text[start..end]
}

pub fn undefined_symbols(text string) []string {
	mut symbols := []string{}
	for line in text.split_into_lines() {
		fields := line.fields()
		if fields.len >= 2 && fields[fields.len - 2] == 'U' {
			symbols << fields.last()
		}
	}
	return symbols
}
