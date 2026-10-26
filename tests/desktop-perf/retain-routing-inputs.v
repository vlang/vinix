// SPDX-License-Identifier: GPL-2.0-or-later
// Preserve the two routing assets needed after restoring the full audit archive.
module main

import crypto.sha256
import json2
import os

const original_manifest = '94d603c2e43cff1b9a9c9f86d2dc3c631b60181d0c5d5c363994de4291db4174'
const original_archive = 'f213a60bf7808293598a4cbb45b3bb189b0dced55b0324b6a74fb3f367f7dc7b'
const assets = {
	'desktop-x86_64/vinix-desktop':          '259613b8f95ddde359a70f338baeca27bd96f0ae2b56391f6d6c3cc35de67a83'
	'tools/software-release-routing-bundle': '0bf024564aba9cedfac1fd8f92b3f117e5735511cafb1dfb409f449ca00ca94b'
}

struct CopyReceipt {
	source_path     string
	source_resolved string
	destination     string
	source_before   string
	copied_before   string
	source_after    string
	copied_after    string
	mode            u32
}

struct Receipt {
	format                  int    = 1
	scope                   string = 'byte-identical retained x86 routing desktop and bundle tool; full native archive remains required for historical audit'
	original_root           string
	original_archive_path   string
	original_archive_sha256 string
	archive_digest_status   string = 'historical provenance pin; this copy helper verifies the expanded manifest and selected bytes, not the archive stream'
	manifest_before         string
	manifest_after          string
	inputs                  map[string]CopyReceipt
	arguments               []string
	producer_source         string
	producer_binary         string
	producer_source_base    string
	compiler_path           string
	compiler_sha256         string
}

fn digest(path string) !string {
	mut file := os.open(path)!
	defer { file.close() }
	mut sum := sha256.new()
	defer { unsafe { sum.free() } }
	mut buffer := []u8{len: 65536}
	for {
		count := file.read(mut buffer) or { if err is os.Eof { break } else { return err } }
		if count == 0 { break }
		sum.write(buffer[..count])!
	}
	return sum.sum([]u8{}).hex()
}

fn regular(path string) !u32 {
	mode := os.lstat(path)!.mode
	if mode & 0o170000 != 0o100000 { return error('expected ordinary file: ' + path) }
	return mode & 0o777
}

fn retain(root string, output string) ! {
	if os.exists(output) || os.is_link(output) { return error('output must be fresh') }
	manifest := root + '/bundle.sha256'
	regular(manifest)!
	before := digest(manifest)!
	if before != original_manifest { return error('original complete manifest differs') }
	rows := os.read_file(manifest)!.split_into_lines()
	mut modes := map[string]u32{}
	for relative, expected in assets {
		if rows.filter(it == 'file\t' + expected + '\t' + relative).len != 1 {
			return error('original manifest does not uniquely bind ' + relative)
		}
		modes[relative] = regular(root + '/' + relative)!
		if digest(root + '/' + relative)! != expected {
			return error('source bytes differ: ' + relative)
		}
	}
	os.mkdir_all(output + '/source')!
	os.cp(@FILE, output + '/source/retain-routing-inputs.v', fail_if_exists: true)!
	os.cp(os.executable(), output + '/producer', fail_if_exists: true)!
	os.cp(manifest, output + '/original-manifest.sha256', fail_if_exists: true)!
	mut receipts := map[string]CopyReceipt{}
	for relative, expected in assets {
		source := root + '/' + relative
		destination := output + '/' + relative
		os.mkdir_all(os.dir(destination))!
		os.cp(source, destination, fail_if_exists: true)!
		os.chmod(destination, int(modes[relative]))!
		copied := digest(destination)!
		source_after := digest(source)!
		if regular(source)! != modes[relative] || regular(destination)! != modes[relative]
			|| copied != expected || source_after != expected {
			return error('copy or source changed: ' + relative)
		}
		receipts[relative] = CopyReceipt{source, os.real_path(source), destination, expected, copied, source_after, digest(destination)!, modes[relative]}
	}
	after := digest(manifest)!
	if after != before || digest(output + '/original-manifest.sha256')! != before {
		return error('original manifest changed during copy')
	}
	for relative, item in receipts {
		if digest(item.source_path)! != item.source_after || digest(item.destination)! != item.copied_after {
			return error('retained input changed before receipt: ' + relative)
		}
	}
	source_hash := digest(@FILE)!
	if digest(output + '/source/retain-routing-inputs.v')! != source_hash
		|| source_hash != sha256.sum($embed_file('retain-routing-inputs.v').to_string().bytes()).hex() {
		return error('copy helper source differs from compiled source')
	}
	producer_hash := digest(os.executable())!
	if digest(output + '/producer')! != producer_hash { return error('producer copy differs') }
	repository := os.dir(os.dir(os.dir(os.real_path(@FILE))))
	revision := os.exec(['git', '-C', repository, 'rev-parse', 'HEAD'])
	if revision.exit_code != 0 { return error('cannot record source base') }
	receipt := Receipt{
		original_root:           root
		original_archive_path:   root + '.tar.gz'
		original_archive_sha256: original_archive
		manifest_before:         before
		manifest_after:          after
		inputs:                  receipts
		arguments:               os.args
		producer_source:         source_hash
		producer_binary:         producer_hash
		producer_source_base:    revision.output.trim_space()
		compiler_path:           os.real_path(@VEXE)
		compiler_sha256:         digest(@VEXE)!
	}
	os.write_file(output + '/provenance.json', json2.encode(receipt,
		escape_unicode: true
		time_as_unix:   true
	) + '\n')!
	println('ROUTING INPUTS RETAIN PASS receipt=' + digest(output + '/provenance.json')!)
}

fn main() {
	if os.args.len != 3 {
		eprintln('use ORIGINAL_ROUTING_ROOT FRESH_OUTPUT_DIRECTORY')
		exit(2)
	}
	retain(os.real_path(os.args[1]), os.abs_path(os.args[2])) or {
		eprintln(err)
		exit(1)
	}
}
