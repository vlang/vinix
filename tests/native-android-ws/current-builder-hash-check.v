// SPDX-License-Identifier: GPL-2.0-or-later
// Exercise the actual builder hashing CLI; retain all evidence outside Git.
module main

import crypto.sha256
import json2
import os
import time

const repo = '/Users/alex/code/vinix'
const source = $embed_file(@FILE).to_string()
const pass_prefix = 'CURRENT-BUILDER-HASH-PASS '
const repetitions = 4096
const rss_limit = i64(256 * 1024 * 1024)
const rss_growth_limit = i64(64 * 1024 * 1024)

struct Command {
	argv       []string
	exit_code  int
	elapsed_ns i64
	output     string
}

struct Fixture {
	path                 string
	bytes                int
	sha256               string
	reference_elapsed_ns i64
	shasum_elapsed_ns    i64
	builder_elapsed_ns   i64
}

struct Receipt {
	kind                            string = 'vinix-current-builder-hash-check-v1'
	argv                            []string
	builder                         string
	inputs_sha256                   map[string]string
	checker_source_sha256           string
	repository_revision             string
	fixtures                        []Fixture
	fixture_pattern                 string = '(position * 131 + (position >> 8) * 17 + 0x5a) & 0xff'
	repetitions                     int
	rss_units                       string = 'bytes; macOS /usr/bin/time -l maximum resident set size'
	baseline_max_rss                i64
	repeated_max_rss                i64
	absolute_rss_limit              i64
	rss_growth_limit                i64
	throughput_bytes                int
	throughput_builder_elapsed_ns   i64
	throughput_reference_elapsed_ns i64
	throughput_shasum_elapsed_ns    i64
	started_utc                     string
	completed_utc                   string
	scope                           string = 'Exact actual CLI digests match pure V and shasum; bounded RSS for this workload and measured 32 MiB wall time. Returned-string ownership still requires source/generated-C review; no guest or Google login claim.'
}

// This oracle deliberately uses pure V, including on Darwin. It owns every
// allocation except the returned hex string, which the caller retains or frees.
fn reference_hash(path string) !string {
	mut input := os.open(path)!
	defer { input.close() }
	mut digest := sha256.new()
	defer { unsafe {
		digest.free()
		free(digest)
	}
	 }
	mut buffer := []u8{len: 1024 * 1024}
	defer { unsafe { buffer.free() } }
	for {
		n := input.read(mut buffer) or {
			if err is os.Eof { break }
			return err
		}
		if n == 0 { break }
		if digest.write(buffer[..n])! != n { return error('reference SHA256 short write') }
	}
	mut checksum := []u8{len: 32}
	defer { unsafe { checksum.free() } }
	digest.checksum_into(mut checksum)
	return checksum.hex()
}

fn write_json[T](path string, value T) ! {
	os.write_file(path, json2.encode(value, prettify: true) + '\n')!
}

fn valid_pin(value string) bool {
	return value.len == 64
		&& value.bytes().all((it >= `0` && it <= `9`) || (it >= `a` && it <= `f`))
}

fn regular(path string) ! {
	if os.lstat(path)!.get_filetype() != .regular { return error('regular file required: ' + path) }
}

fn command(root string, label string, argv []string) !Command {
	regular(argv[0])!
	pin := reference_hash(argv[0])!
	defer { unsafe { pin.free() } }
	write_json(root + '/commands/' + label + '-before.json', {
		'argv':              json2.Any(argv)
		'executable_sha256': json2.Any(pin)
		'started_utc':       json2.Any(time.utc().str())
	})!
	watch := time.new_stopwatch()
	result := os.exec(argv)
	elapsed := watch.elapsed().nanoseconds()
	os.write_file(root + '/commands/' + label + '.log', result.output)!
	write_json(root + '/commands/' + label + '.json', {
		'argv':              json2.Any(argv)
		'executable_sha256': json2.Any(pin)
		'exit_code':         json2.Any(result.exit_code)
		'elapsed_ns':        json2.Any(elapsed)
		'completed_utc':     json2.Any(time.utc().str())
	})!
	actual := reference_hash(argv[0])!
	defer { unsafe { actual.free() } }
	if actual != pin { return error('command executable changed: ' + argv[0]) }
	return Command{argv, result.exit_code, elapsed, result.output}
}

fn expected_line(pin string, count int, bytes int) string {
	return pass_prefix + 'sha256=${pin} iterations=${count} bytes=${bytes}'
}

fn check_output(result Command, pin string, count int, bytes int) ! {
	if result.exit_code != 0 || result.output != expected_line(pin, count, bytes) + '\n' {
		return error('builder hash CLI exit or exact output differs: ' + result.argv.str())
	}
}

fn measured_rss(result Command, pin string, count int, bytes int) !i64 {
	if result.exit_code != 0 { return error('timed builder hash command failed') }
	mut passes := 0
	mut readings := 0
	mut rss := i64(0)
	for line in result.output.split_into_lines() {
		if line.starts_with(pass_prefix) {
			if line != expected_line(pin, count, bytes) {
				return error('timed hash output differs')
			}
			passes++
		}
		fields := line.fields()
		if fields.len >= 5 && fields[1..].join(' ') == 'maximum resident set size' {
			if !fields[0].bytes().all(it >= `0` && it <= `9`) {
				return error('invalid RSS reading')
			}
			rss = fields[0].i64()
			readings++
		}
	}
	if passes != 1 || readings != 1 || rss <= 0 {
		return error('ambiguous timed hash or RSS output')
	}
	return rss
}

fn make_fixture(path string, bytes int) ! {
	mut output := os.create(path)!
	defer { output.close() }
	mut buffer := []u8{len: 65536}
	defer { unsafe { buffer.free() } }
	mut offset := 0
	for offset < bytes {
		n := if bytes - offset < buffer.len { bytes - offset } else { buffer.len }
		for index in 0 .. n {
			position := u64(offset + index)
			buffer[index] = u8((position * 131 + (position >> 8) * 17 + 0x5a) & 0xff)
		}
		if output.write(buffer[..n])! != n { return error('fixture short write') }
		offset += n
	}
}

fn inventory(root string, relative string, mut entries map[string]string) ! {
	mut names := os.ls(root + '/' + relative)!
	names.sort()
	for name in names {
		key := if relative == '' { name } else { relative + '/' + name }
		path := root + '/' + key
		match os.lstat(path)!.get_filetype() {
			.directory { inventory(root, key, mut entries)! }
			.regular { entries[key] = reference_hash(path)! }
			else { return error('nonregular evidence member: ' + key) }
		}
	}
}

fn check(builder string, root string) ! {
	$if !macos {
		return error('requires macOS /usr/bin/time -l RSS readings in bytes')
	}
	if builder.contains_any('\x00\r\n') || os.real_path(builder) != builder {
		return error('canonical builder executable required')
	}
	regular(builder)!
	if root.contains_any('\x00\r\n') || root == repo || root.starts_with(repo + '/')
		|| os.exists(root) || os.is_link(root) || os.real_path(os.dir(root)) != os.dir(root) {
		return error('fresh external directory with canonical existing parent required')
	}
	started := time.utc().str()
	mut input_pins := map[string]string{}
	for path in [builder, os.real_path(os.executable()), '/usr/bin/time', '/usr/bin/shasum',
		'/usr/bin/perl', '/usr/bin/git'] {
		regular(path)!
		input_pins[path] = reference_hash(path)!
	}
	os.mkdir(root)!
	for directory in ['commands', 'fixtures', 'source'] { os.mkdir(root + '/' + directory)! }
	os.write_file(root + '/source/current-builder-hash-check.v', source)!
	write_json(root + '/inputs-before.json', input_pins)!
	git := command(root, 'source-revision', ['/usr/bin/git', '-C', repo, 'rev-parse', 'HEAD'])!
	revision := git.output.trim_space()
	if git.exit_code != 0 || revision.len != 40
		|| !revision.bytes().all((it >= `0` && it <= `9`) || (it >= `a` && it <= `f`)) {
		return error('source revision unavailable')
	}
	mut fixtures := []Fixture{}
	lengths := [0, 1, 55, 56, 63, 64, 65, 1048575, 1048576, 1048577, 3 * 1048576, 32 * 1048576]
	for bytes in lengths {
		path := root + '/fixtures/bytes-${bytes}.bin'
		make_fixture(path, bytes)!
		watch := time.new_stopwatch()
		pin := reference_hash(path)!
		reference_ns := watch.elapsed().nanoseconds()
		if !valid_pin(pin) { return error('reference hash framing') }
		shasum := command(root, 'shasum-${bytes}', ['/usr/bin/shasum', '-a', '256', path])!
		if shasum.exit_code != 0 || shasum.output != pin + '  ' + path + '\n' {
			return error('independent shasum differs for fixture ' + bytes.str())
		}
		result := command(root, 'builder-${bytes}', [builder, '--hash-file', path, '1'])!
		check_output(result, pin, 1, bytes)!
		fixtures << Fixture{path, bytes, pin, reference_ns, shasum.elapsed_ns, result.elapsed_ns}
	}
	missing := command(root, 'missing-file', [builder, '--hash-file', root + '/fixtures/missing.bin',
		'1'])!
	if missing.exit_code == 0 || missing.output.contains(pass_prefix) {
		return error('builder accepted a missing input or emitted a success marker')
	}
	one := fixtures[1]
	baseline := command(root, 'rss-baseline', ['/usr/bin/time', '-l', builder, '--hash-file', one.path,
		'1'])!
	baseline_rss := measured_rss(baseline, one.sha256, 1, one.bytes)!
	repeated := command(root, 'rss-repeated', ['/usr/bin/time', '-l', builder, '--hash-file', one.path,
		repetitions.str()])!
	repeated_rss := measured_rss(repeated, one.sha256, repetitions, one.bytes)!
	if baseline_rss > rss_limit || repeated_rss > rss_limit
		|| repeated_rss - baseline_rss > rss_growth_limit {
		return error('builder hashing RSS exceeds absolute or growth limit')
	}
	for fixture in fixtures {
		regular(fixture.path)!
		actual := reference_hash(fixture.path)!
		defer { unsafe { actual.free() } }
		if os.file_size(fixture.path) != u64(fixture.bytes) || actual != fixture.sha256 {
			return error('fixture changed during check: ' + fixture.path)
		}
	}
	for path, pin in input_pins {
		regular(path)!
		actual := reference_hash(path)!
		defer { unsafe { actual.free() } }
		if actual != pin { return error('checker input changed: ' + path) }
	}
	write_json(root + '/check.json', Receipt{
		argv:                            os.args
		builder:                         builder
		inputs_sha256:                   input_pins
		checker_source_sha256:           reference_hash(root + '/source/current-builder-hash-check.v')!
		repository_revision:             git.output.trim_space()
		fixtures:                        fixtures
		repetitions:                     repetitions
		baseline_max_rss:                baseline_rss
		repeated_max_rss:                repeated_rss
		absolute_rss_limit:              rss_limit
		rss_growth_limit:                rss_growth_limit
		throughput_bytes:                32 * 1048576
		throughput_builder_elapsed_ns:   fixtures.last().builder_elapsed_ns
		throughput_reference_elapsed_ns: fixtures.last().reference_elapsed_ns
		throughput_shasum_elapsed_ns:    fixtures.last().shasum_elapsed_ns
		started_utc:                     started
		completed_utc:                   time.utc().str()
	})!
	mut entries := map[string]string{}
	inventory(root, '', mut entries)!
	write_json(root + '/sha256.json', entries)!
	println('CURRENT-BUILDER-HASH-CHECK-PASS fixtures=${fixtures.len} iterations=${repetitions} bundle=${root} seal=' + reference_hash(root + '/sha256.json')!)
}

fn main() {
	if os.args.len != 3 {
		eprintln('usage: current-builder-hash-check BUILDER_EXECUTABLE FRESH_EXTERNAL_DIRECTORY')
		exit(2)
	}
	check(os.abs_path(os.args[1]), os.abs_path(os.args[2])) or {
		eprintln(err)
		exit(1)
	}
}
