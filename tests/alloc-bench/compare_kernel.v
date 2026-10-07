module main

import comparecore as common
import kernelcompare
import json2
import os
import encoding.utf8

const usage = 'usage: compare-kernel [-h] [--vinix-config VINIX_CONFIG]\n                      [--xnu-config XNU_CONFIG] vinix_log xnu_log'

fn fail(message string) {
	eprintln(usage)
	eprintln('compare-kernel: error: ' + message)
	exit(2)
}

fn run(paths []string, configs []string) !string {
	left_config := manifest(configs[0])!
	right_config := manifest(configs[1])!
	left := kernelcompare.parse_log(kernelcompare.log_text(os.read_file(paths[0])!), 'vinix')!
	right := kernelcompare.parse_log(kernelcompare.log_text(os.read_file(paths[1])!), 'xnu')!
	return kernelcompare.compare(left, right, left_config, right_config)
}

fn main() {
	mut paths := []string{}
	mut configs := ['', '']
	mut provided := [false, false]
	mut cursor := 1
	mut positional := false
	mut unknown := []string{}
	for cursor < os.args.len {
		argument := os.args[cursor]
		cursor++
		if !positional && ((argument.starts_with('-h') && argument[1..].bytes().all(it == `h`)) || (argument.starts_with('--') && argument != '--' && '--help'.starts_with(argument))) {
			println(usage + '\n\nStrict comparison of paired KALLOC logs from the shared kernel sampler.')
			return
		}
		if !positional && argument == '--' {
			positional = true
			continue
		}
		if !positional && argument.starts_with('--') {
			spelling := argument.all_before('=')
			matches := ['--vinix-config', '--xnu-config', '--macos-config'].filter(it.starts_with(spelling))
			if matches.len != 1 {
				unknown << argument
				continue
			}
			option := matches[0]
			mut value := ''
			if argument.contains('=') {
				value = argument.all_after('=')
			} else {
				if cursor == os.args.len || (os.args[cursor].len > 1 && os.args[cursor][0] == `-` && !negative_number(os.args[cursor])) {
					fail('argument ${option}: expected one argument')
				}
				value = os.args[cursor]
				cursor++
			}
			index := if option == '--vinix-config' { 0 } else { 1 }
			configs[index] = if value == '' { '.' } else { value }
			provided[index] = true
		} else {
			if !positional && argument.len > 1 && argument[0] == `-` && !negative_number(argument) {
				unknown << argument
				continue
			}
			paths << argument
		}
	}
	if paths.len < 2 {
		fail('the following arguments are required: ' + if paths.len == 0 {
			'vinix_log, xnu_log'
		} else {
			'xnu_log'
		})
	}
	if paths.len > 2 { unknown << paths[2..] }
	if unknown.len != 0 { fail('unrecognized arguments: ' + unknown.join(' ')) }
	for index, path in paths {
		if !provided[index] { configs[index] = os.join_path(os.dir(path), 'config.json') }
	}
	output := run(paths, configs) or {
		eprintln('Kernel comparison rejected: ${kernelcompare.log_text(err.msg())}')
		exit(2)
	}
	print(output)
}

fn negative_number(text string) bool {
	if !text.starts_with('-') || text.len < 2 { return false }
	value := text[1..]
	if value.bytes().all(it.is_digit()) { return true }
	if value.count('.') != 1 { return false }
	return value.all_after('.').len > 0 && value.all_before('.').bytes().all(it.is_digit()) && value.all_after('.').bytes().all(it.is_digit())
}

fn manifest(path string) !common.Value {
	text := os.read_file(path)!
	if !utf8.validate_str(text) { return error('invalid UTF-8 in manifest ${path}') }
	return json2.decode[common.Value](text)
}
