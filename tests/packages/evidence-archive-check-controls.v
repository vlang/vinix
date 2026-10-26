// SPDX-License-Identifier: GPL-2.0-or-later
// Exercise the streaming evidence reader without extracting hostile members.
module main

import compress.gzip
import crypto.sha256
import json2
import os

#include <unistd.h>

const fixture_root = 'evidence'
const payload_text = 'sealed payload λ\n'
const scratch_limit = u64(20 * 1024 * 1024)

struct Member {
	name   string
	kind   u8 = `0`
	data   string
	target string
}

struct ArchiveReceipt {
	format           int
	archive          string
	archive_sha256   string
	root             string
	manifest_sha256  string
	sealed_entries   int
	regular_payloads int
	hardlinks        int
	symlinks         int
	directories      int
	gzip             GzipReceipt
	scope            string
}

struct GzipReceipt {
	members       int
	decoded_bytes u64
	zlib_version  string
}

struct CaseResult {
	name            string
	accepted        bool
	exit_code       int
	archive_sha256  string
	manifest_sha256 string
	argv_sha256     string
	log_sha256      string
	expected_reason string
}

struct ControlsReceipt {
	format                 int = 1
	source_revision        string
	runner_source_sha256   string
	runner_binary          string
	runner_binary_sha256   string
	runner_argv            []string
	verifier_source_sha256 string
	verifier_binary        string
	verifier_binary_sha256 string
	tar_binary             string
	tar_binary_sha256      string
	scratch_bytes          u64
	results                []CaseResult
}

fn need(value bool, message string) ! {
	if !value { return error(message) }
}

fn digest(path string) !string {
	mut input := os.open(path)!
	defer { input.close() }
	mut hash := sha256.new()
	defer { unsafe { hash.free() } }
	mut buffer := []u8{len: 128 * 1024}
	for {
		count := input.read(mut buffer) or { if err is os.Eof { break } else { return err } }
		if count == 0 { break }
		hash.write(buffer[..count])!
	}
	return hash.sum([]u8{}).hex()
}

fn invoke(argv []string, log string) !(int, string) {
	os.write_file(log + '.argv.json', json2.encode(argv) + '\n')!
	mut child := os.new_process(argv[0])
	defer { child.close() }
	child.set_args(argv[1..])
	child.set_redirect_stdio_merged()
	child.run()
	C.close(child.stdio_fd[0])
	child.stdio_fd[0] = -1
	text := child.stdout_slurp()
	child.wait()
	os.write_file(log, text)!
	for forbidden in ['V panic:', 'ERROR: AddressSanitizer', 'SUMMARY: AddressSanitizer',
		'UndefinedBehaviorSanitizer', 'runtime error:'] {
		need(!text.contains(forbidden), 'unexpected runtime diagnostic: ' + log)!
	}
	return child.code, text
}

fn field(mut header []u8, offset int, width int, value string) ! {
	need(value.len < width, 'ustar fixture field exceeds bounded width')!
	for index, byte in value { header[offset + index] = byte }
}

fn octal(value u64) string {
	if value == 0 { return '0' }
	mut remaining := value
	mut digits := []u8{}
	for remaining > 0 {
		digits << u8(remaining & 7) + `0`
		remaining >>= 3
	}
	digits.reverse_in_place()
	return digits.bytestr()
}

fn tar_bytes(members []Member) ![]u8 {
	mut archive := []u8{}
	for member in members {
		mut header := []u8{len: 512}
		field(mut header, 0, 100, member.name)!
		field(mut header, 100, 8, if member.kind == `5` { '755' } else { '644' })!
		field(mut header, 108, 8, '0')!
		field(mut header, 116, 8, '0')!
		field(mut header, 124, 12, octal(u64(member.data.len)))!
		field(mut header, 136, 12, '0')!
		for index in 148 .. 156 { header[index] = ` ` }
		header[156] = member.kind
		field(mut header, 157, 100, member.target)!
		field(mut header, 257, 6, 'ustar')!
		field(mut header, 263, 3, '00')!
		mut checksum := u64(0)
		for byte in header { checksum += byte }
		field(mut header, 148, 7, octal(checksum))!
		header[154] = 0
		header[155] = ` `
		archive << header
		archive << member.data.bytes()
		if member.data.len % 512 != 0 { archive << []u8{len: 512 - member.data.len % 512} }
	}
	archive << []u8{len: 1024}
	return archive
}

fn file_line(name string, contents string) string {
	return 'file\t' + sha256.hexhash(contents) + '\t' + name
}

fn link_line(name string, target string) string {
	return 'link\t' + sha256.hexhash(target) + '\t' + name + '\t' + target
}

fn seal_lines(lines []string) string { return lines.join('\n') + '\n' }

fn minimal_manifest() string { return seal_lines([file_line('payload', payload_text)]) }

fn members_with_manifest(manifest string, payload []Member) []Member {
	mut members := [Member{ name: fixture_root + '/', kind: `5` },
		Member{ name: fixture_root + '/bundle.sha256', data: manifest }]
	members << payload
	return members
}

fn check_case(binary string, output string, name string, archive_bytes []u8, manifest string,
	accept bool, reason string, counts []int, wrong_archive_hash bool) !CaseResult {
	archive := output + '/' + name + '.tar.gz'
	manifest_path := output + '/' + name + '.manifest'
	os.write_file_array(archive, archive_bytes)!
	os.write_file(manifest_path, manifest)!
	return run_case(binary, output, name, archive, manifest_path, accept, reason, counts,
		wrong_archive_hash)
}

fn run_case(binary string, output string, name string, archive string, manifest_path string,
	accept bool, reason string, counts []int, wrong_archive_hash bool) !CaseResult {
	archive_hash := digest(archive)!
	manifest_hash := digest(manifest_path)!
	bound_hash := if wrong_archive_hash { '0'.repeat(64) } else { archive_hash }
	argv := [binary, 'check', archive, fixture_root, manifest_path, bound_hash]
	log := output + '/' + name + '.log'
	code, text := invoke(argv, log)!
	if accept {
		need(code == 0, 'valid archive refused: ' + name + '; see ' + log)!
		lines := text.trim_space().split_into_lines()
		need(lines.len == 2 && lines[1] == 'EVIDENCE ARCHIVE CHECK PASS',
			'success output lacks exact JSON/PASS contract: ' + name)!
		receipt := json2.decode[ArchiveReceipt](lines[0])!
		expected_gzip_members := if counts.len >= 6 { counts[5] } else { 1 }
		need(counts.len in [5, 6, 7] && receipt.format == 1 && receipt.archive == os.abs_path(archive)
			&& receipt.archive_sha256 == archive_hash && receipt.root == fixture_root
			&& receipt.manifest_sha256 == manifest_hash && receipt.sealed_entries == counts[0]
			&& receipt.regular_payloads == counts[1] && receipt.hardlinks == counts[2]
			&& receipt.symlinks == counts[3] && receipt.directories == counts[4]
			&& receipt.gzip.members == expected_gzip_members && receipt.gzip.decoded_bytes > 0
			&& (counts.len < 7 || receipt.gzip.decoded_bytes == u64(counts[6]))
			&& receipt.gzip.zlib_version != ''
			&& receipt.scope == 'Exact sealed regular-file bytes and literal symlink targets; canonical directory headers permitted. Directory existence, modes, owners and timestamps are not authenticated by this historical manifest format.',
			'success receipt differs from observed fixture: ' + name)!
	} else {
		need(code == 1 && !text.contains('EVIDENCE ARCHIVE CHECK PASS')
			&& (reason == '' || text.contains(reason)), 'invalid archive accepted or unexpected refusal: ' + name + '; see ' + log)!
	}
	need(digest(archive)! == archive_hash && digest(manifest_path)! == manifest_hash,
		'control input changed: ' + name)!
	println('EVIDENCE ARCHIVE CONTROL ' + name + ' PASS')
	return CaseResult{
		name:            name
		accepted:        accept
		exit_code:       code
		archive_sha256:  archive_hash
		manifest_sha256: manifest_hash
		argv_sha256:     digest(log + '.argv.json')!
		log_sha256:      digest(log)!
		expected_reason: reason
	}
}

fn generated_case(binary string, output string, name string, manifest string, members []Member,
	accept bool, reason string, counts []int) !CaseResult {
	return check_case(binary, output, name, gzip.compress(tar_bytes(members)!)!, manifest,
		accept, reason, counts, false)
}

fn scratch_bytes(directory string) !u64 {
	mut total := u64(0)
	for name in os.ls(directory)! {
		path := directory + '/' + name
		if os.is_link(path) { continue }
		if os.is_dir(path) {
			total += scratch_bytes(path)!
		} else {
			total += os.lstat(path)!.size
		}
		need(total <= scratch_limit, 'controls exceed 20 MiB scratch budget')!
	}
	return total
}

fn sparse_case(binary string, output string) !CaseResult {
	root := output + '/sparse-tree/' + fixture_root
	os.mkdir_all(root)!
	mut sparse := os.create(root + '/sparse')!
	need(sparse.write_string('head\n')! == 5, 'cannot seed sparse header')!
	sparse.seek(1024 * 1024 - 5, .start)!
	need(sparse.write_string('tail\n')! == 5, 'cannot seed sparse tail')!
	sparse.close()
	os.write_file(root + '/bundle.sha256', 'file\t' + digest(root + '/sparse')! + '\tsparse\n')!
	archive := output + '/actual-sparse.tar.gz'
	os.setenv('COPYFILE_DISABLE', '1', true)
	code, _ := invoke(['/usr/bin/tar', '-czf', archive, '-C', os.dir(root), '--', fixture_root],
		output + '/sparse-tar.log')!
	need(code == 0, 'system tar could not encode sparse fixture')!
	raw := gzip.decompress(os.read_bytes(archive)!)!
	text := raw.bytestr()
	need(text.contains('GNU.sparse') || text.contains('SCHILY.sparse'),
		'system tar did not encode sparse extents; sparse baseline not qualified')!
	return run_case(binary, output, 'actual-sparse', archive, root + '/bundle.sha256', true,
		'', [1, 1, 0, 0, 1], false)
}

fn large_cases(binary string, output string) ![]CaseResult {
	// Deterministic incompressible bytes exercise both compressed and decoded
	// streams across the verifier's 1 MiB buffers without large disk fixtures.
	mut data := []u8{len: 2 * 1024 * 1024}
	mut state := u32(0x6d2b79f5)
	for index in 0 .. data.len {
		state ^= state << 13
		state ^= state >> 17
		state ^= state << 5
		data[index] = u8(state >> 24)
	}
	contents := data.bytestr()
	manifest := seal_lines([file_line('bulk', contents)])
	raw := tar_bytes(members_with_manifest(manifest,
		[Member{ name: fixture_root + '/bulk', data: contents }]))!
	compressed := gzip.compress(raw)!
	need(raw.len > 1024 * 1024 && compressed.len > 1024 * 1024,
		'multi-chunk baseline does not cross both buffer sizes')!
	mut results := [check_case(binary, output, 'multi-chunk-payload', compressed, manifest,
		true, '', [1, 1, 0, 0, 1, 1, raw.len], false)!]
	cut := 960 * 1024
	first := gzip.compress(raw[..cut])!
	need(first.len >= 18 && first[3] == 0, 'gzip fixture unexpectedly has optional header fields')!
	padding := 1024 * 1024 - first.len - 2
	need(padding >= 4 && padding <= 65535, 'gzip extra field cannot reach exact chunk boundary')!
	// FEXTRA contributes XLEN and a well-formed private VX subfield.
	mut boundary := first[..10].clone()
	boundary[3] = 4
	boundary << [u8(padding & 255), u8(padding >> 8)]
	boundary << [u8(`V`), `X`, u8((padding - 4) & 255), u8((padding - 4) >> 8)]
	boundary << []u8{len: padding - 4}
	boundary << first[10..]
	need(boundary.len == 1024 * 1024, 'first gzip member misses exact compressed boundary')!
	boundary << gzip.compress(raw[cut..])!
	results << check_case(binary, output, 'exact-compressed-member-boundary', boundary,
		manifest, true, '', [1, 1, 0, 0, 1, 2, raw.len], false)!
	return results
}

fn qualify() ! {
	need(os.args.len == 3, 'usage: evidence-archive-check-controls VERIFIER_BINARY NEW_EXTERNAL_DIRECTORY')!
	binary := os.real_path(os.args[1])
	output := os.abs_path(os.args[2])
	project := os.real_path(os.join_path(os.dir(@FILE), '../..'))
	need(os.is_file(binary) && !os.is_link(os.args[1]) && !os.exists(output)
		&& !os.is_link(output) && !output.starts_with(project + '/'),
		'provide an existing verifier binary and a fresh external output directory')!
	source := os.dir(@FILE) + '/evidence-archive-check.v'
	verifier_source := digest(source)!
	verifier_binary := digest(binary)!
	runner_hash := sha256.sum($embed_file('evidence-archive-check-controls.v').to_bytes()).hex()
	need(digest(@FILE)! == runner_hash, 'runner source differs from compiled runner')!
	os.mkdir_all(output)!
	os.cp(source, output + '/evidence-archive-check.v')!
	os.cp(@FILE, output + '/evidence-archive-check-controls.v')!
	revision_code, revision_text := invoke(['git', '-C', project, 'rev-parse', 'HEAD'], output + '/source-revision.log')!
	need(revision_code == 0, 'cannot bind source revision')!
	identity := ControlsReceipt{
		source_revision:        revision_text.trim_space()
		runner_source_sha256:   runner_hash
		runner_binary:          os.executable()
		runner_binary_sha256:   digest(os.executable())!
		runner_argv:            os.args
		verifier_source_sha256: verifier_source
		verifier_binary:        binary
		verifier_binary_sha256: verifier_binary
		tar_binary:             '/usr/bin/tar'
		tar_binary_sha256:      digest('/usr/bin/tar')!
	}
	// Preserve identities even when a strict control exposes an acceptance bug.
	os.write_file(output + '/inputs.json', json2.encode(identity) + '\n')!
	manifest := minimal_manifest()
	base := members_with_manifest(manifest, [Member{ name: fixture_root + '/payload', data: payload_text }])
	mut results := []CaseResult{}
	baseline_manifest := seal_lines([file_line('payload', payload_text),
		file_line('hard', payload_text), file_line('.hidden', 'hidden\n'), file_line('empty', ''),
		link_line('relative-link', 'payload'), link_line('external-link', '../../outside'),
		link_line('cycle-link', 'cycle-link')])
	results << generated_case(binary, output, 'regular-hardlink-symlinks', baseline_manifest,
		members_with_manifest(baseline_manifest, [
			Member{ name: fixture_root + '/payload', data: payload_text },
			Member{ name: fixture_root + '/hard', kind: `1`, target: fixture_root + '/payload' },
			Member{ name: fixture_root + '/.hidden', data: 'hidden\n' },
			Member{ name: fixture_root + '/empty' },
			Member{ name: fixture_root + '/relative-link', kind: `2`, target: 'payload' },
			Member{ name: fixture_root + '/external-link', kind: `2`, target: '../../outside' },
			Member{ name: fixture_root + '/cycle-link', kind: `2`, target: 'cycle-link' },
			Member{ name: fixture_root + '/empty-directory/', kind: `5` },
		]), true, '', [7, 3, 1, 3, 2])!
	forward_manifest := seal_lines([file_line('hard', payload_text),
		file_line('payload', payload_text)])
	results << generated_case(binary, output, 'forward-hardlink', forward_manifest,
		members_with_manifest(forward_manifest, [
			Member{ name: fixture_root + '/hard', kind: `1`, target: fixture_root + '/payload' },
			Member{ name: fixture_root + '/payload', data: payload_text },
		]), true, '', [2, 1, 1, 0, 1])!
	results << sparse_case(binary, output)!
	results << large_cases(binary, output)!
	// A single tar stream may span multiple complete gzip members.
	valid_tar := tar_bytes(base)!
	mut valid_concatenated := gzip.compress(valid_tar[..valid_tar.len / 2])!
	valid_concatenated << gzip.compress(valid_tar[valid_tar.len / 2..])!
	results << check_case(binary, output, 'valid-concatenated-gzip', valid_concatenated,
		manifest, true, '', [1, 1, 0, 0, 1, 2], false)!
	results << generated_case(binary, output, 'payload-tamper', manifest,
		members_with_manifest(manifest, [Member{ name: fixture_root + '/payload', data: 'tampered\n' }]),
		false, 'archive payload hash or type differs', [])!
	bad_hash_manifest := seal_lines(['file\t' + '0'.repeat(64) + '\tpayload'])
	results << generated_case(binary, output, 'manifest-hash-tamper', bad_hash_manifest,
		members_with_manifest(bad_hash_manifest, [Member{ name: fixture_root + '/payload', data: payload_text }]),
		false, 'archive payload hash or type differs', [])!
	results << check_case(binary, output, 'archive-hash-tamper', gzip.compress(tar_bytes(base)!)!, manifest,
		false, 'archive digest differs before reading', [], true)!
	results << generated_case(binary, output, 'missing-member', manifest,
		members_with_manifest(manifest, []), false, 'missing sealed archive payload', [])!
	mut extra := base.clone()
	extra << Member{ name: fixture_root + '/extra', data: 'extra\n' }
	results << generated_case(binary, output, 'extra-member', manifest, extra,
		false, 'unexpected archive payload', [])!
	mut duplicate := base.clone()
	duplicate << Member{ name: fixture_root + '/payload', data: payload_text }
	results << generated_case(binary, output, 'duplicate-member', manifest, duplicate,
		false, 'duplicate archive member', [])!
	// A valid AppleDouble resource fork must remain visible as an unsealed file.
	apple_double := [u8(0), 5, 22, 7, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
		0, 0, 1, 0, 0, 0, 2, 0, 0, 0, 38, 0, 0, 0, 4, `f`, `o`, `r`, `k`].bytestr()
	mut hidden_extra := base.clone()
	hidden_extra << Member{ name: fixture_root + '/._payload', data: apple_double }
	results << generated_case(binary, output, 'appledouble-hidden-extra', manifest, hidden_extra,
		false, 'unexpected archive payload', [])!
	unexpected_tar := tar_bytes([Member{ name: fixture_root + '/appended', data: 'unexpected\n' }])!
	mut appended_tar := tar_bytes(base)!
	appended_tar << unexpected_tar
	results << check_case(binary, output, 'appended-second-tar', gzip.compress(appended_tar)!,
		manifest, false, 'unexpected archive payload', [], false)!
	mut appended_gzip := gzip.compress(tar_bytes(base)!)!
	appended_gzip << gzip.compress(unexpected_tar)!
	results << check_case(binary, output, 'concatenated-second-gzip', appended_gzip,
		manifest, false, 'unexpected archive payload', [], false)!
	for index, path in ['evidence/../outside', '/evidence/absolute', 'elsewhere/payload',
		'evidence/./payload', 'evidence//payload'] {
		results << generated_case(binary, output, 'path-escape-' + index.str(), manifest,
			members_with_manifest(manifest, [Member{ name: path, data: payload_text }]),
			false, 'archive member escapes canonical root', [])!
	}
	compressed := gzip.compress(tar_bytes(base)!)!
	results << check_case(binary, output, 'truncated-gzip', compressed[..compressed.len / 2], manifest,
		false, 'truncated gzip stream', [], false)!
	mut corrupt := compressed.clone()
	corrupt[corrupt.len - 8] ^= 0xff
	results << check_case(binary, output, 'corrupt-gzip-checksum', corrupt, manifest,
		false, 'gzip integrity validation failed', [], false)!
	mut corrupt_size := compressed.clone()
	corrupt_size[corrupt_size.len - 4] ^= 0xff
	results << check_case(binary, output, 'corrupt-gzip-size', corrupt_size, manifest,
		false, 'gzip integrity validation failed', [], false)!
	results << check_case(binary, output, 'missing-gzip-trailer', compressed[..compressed.len - 8], manifest,
		false, 'truncated gzip stream', [], false)!
	results << generated_case(binary, output, 'missing-embedded-seal', manifest,
		[Member{ name: fixture_root + '/', kind: `5` },
			Member{ name: fixture_root + '/payload', data: payload_text }],
		false, 'missing embedded sealed manifest', [])!
	results << generated_case(binary, output, 'changed-embedded-seal', manifest,
		members_with_manifest(manifest + '\n', [Member{ name: fixture_root + '/payload', data: payload_text }]),
		false, 'embedded sealed manifest differs', [])!
	results << generated_case(binary, output, 'hardlink-absent-target', manifest,
		members_with_manifest(manifest, [Member{ name: fixture_root + '/payload', kind: `1`, target: fixture_root + '/absent' }]),
		false, 'hardlink target absent from seal', [])!
	results << generated_case(binary, output, 'hardlink-escape-target', manifest,
		members_with_manifest(manifest, [Member{ name: fixture_root + '/payload', kind: `1`, target: fixture_root + '/../outside' }]),
		false, 'invalid archive hardlink', [])!
	results << generated_case(binary, output, 'hardlink-self-target', manifest,
		members_with_manifest(manifest, [Member{ name: fixture_root + '/payload', kind: `1`, target: fixture_root + '/payload' }]),
		false, 'hardlink target type or hash differs', [])!
	cycle_manifest := seal_lines([file_line('left', payload_text), file_line('right', payload_text)])
	results << generated_case(binary, output, 'hardlink-cycle', cycle_manifest,
		members_with_manifest(cycle_manifest, [
			Member{ name: fixture_root + '/left', kind: `1`, target: fixture_root + '/right' },
			Member{ name: fixture_root + '/right', kind: `1`, target: fixture_root + '/left' },
		]),
		false, 'hardlink target is not an observed regular payload', [])!
	chain_manifest := seal_lines([file_line('first', payload_text), file_line('second', payload_text),
		file_line('payload', payload_text)])
	results << generated_case(binary, output, 'hardlink-chain', chain_manifest,
		members_with_manifest(chain_manifest, [
			Member{ name: fixture_root + '/first', kind: `1`, target: fixture_root + '/second' },
			Member{ name: fixture_root + '/second', kind: `1`, target: fixture_root + '/payload' },
			Member{ name: fixture_root + '/payload', data: payload_text },
		]),
		false, 'hardlink target is not an observed regular payload', [])!
	symlink_manifest := seal_lines([file_line('hard', payload_text), link_line('link', 'payload')])
	results << generated_case(binary, output, 'hardlink-symlink-target', symlink_manifest,
		members_with_manifest(symlink_manifest, [
			Member{ name: fixture_root + '/link', kind: `2`, target: 'payload' },
			Member{ name: fixture_root + '/hard', kind: `1`, target: fixture_root + '/link' },
		]),
		false, 'hardlink target type or hash differs', [])!
	results << generated_case(binary, output, 'special-fifo', manifest,
		members_with_manifest(manifest, [Member{ name: fixture_root + '/payload', kind: `6` }]),
		false, 'unsupported archive special member', [])!
	need(digest(binary)! == verifier_binary && digest(source)! == verifier_source && digest(@FILE)! == runner_hash,
		'bound verifier or controls source changed during qualification')!
	bytes := scratch_bytes(output)!
	receipt := ControlsReceipt{
		...identity
		scratch_bytes: bytes
		results:       results
	}
	os.write_file(output + '/results.json', json2.encode(receipt) + '\n')!
	need(scratch_bytes(output)! <= scratch_limit, 'final controls exceed scratch budget')!
	os.write_file(output + '/results.json.sha256', digest(output + '/results.json')! + '  results.json\n')!
	println('EVIDENCE ARCHIVE CONTROLS PASS cases=' + results.len.str() + ' results=' + digest(output + '/results.json')!)
}

fn main() {
	qualify() or {
		eprintln(err)
		exit(1)
	}
}
