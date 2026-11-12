// SPDX-License-Identifier: GPL-2.0-or-later
// Check complete, disjoint control coverage with identical immutable baselines.
module main

import crypto.sha256
import json2
import os
import tests.packages.winecontrols

struct ShardProof {
	format          int
	architecture    string
	baseline        bool
	copied_baseline bool
	refused         []string
	inputs          map[string]string
	shard           int
	shards          int
	expected        []string
	forksafe        bool
}

struct Coverage {
	format       int = 1
	architecture string
	controls     int
	shards       int
	proofs       map[string]string
	inputs       map[string]string
}

fn digest(path string) !string {
	mut file := os.open(path)!
	defer { file.close() }
	mut hash := sha256.new()
	defer {
		unsafe {
			hash.free()
			free(hash)
		}
	}
	mut buffer := []u8{len: 65536}
	defer { unsafe { buffer.free() } }
	for {
		n := file.read(mut buffer) or {
			if err is os.Eof { break }
			return err
		}
		if n == 0 { break }
		hash.write(buffer[..n])!
	}
	return hash.sum([]u8{}).hex()
}

fn check() ! {
	if os.args.len < 3 || os.args.len > 10 {
		return error('usage: wine-evidence-shards FRESH_OUTPUT SHARD_DIR ... (one to eight shards)')
	}
	out := os.abs_path(os.args[1])
	if os.exists(out) || os.is_link(out) { return error('coverage output must be fresh') }
	mut first := ShardProof{}
	mut seen := map[int]bool{}
	mut proofs := map[string]string{}
	mut count := 0
	cases := os.dir(@FILE) + '/winecontrols/cases.v'
	if digest(cases)! != sha256.hexhash(winecontrols.source()) {
		return error('Wine control cases changed')
	}
	for directory in os.args[2..] {
		path := os.real_path(directory) + '/controls.json'
		if os.is_link(path) || !os.is_file(path) {
			return error('requires an ordinary shard proof')
		}
		proof := json2.decode[ShardProof](os.read_file(path)!)!
		if proof.expected != winecontrols.names(proof.architecture, proof.forksafe)!
			|| proof.inputs[cases] != digest(cases)! {
			return error('shard control contract differs')
		}
		if proof.format != 1 || !proof.baseline || !proof.copied_baseline
			|| proof.shards != os.args.len - 2 || proof.shard < 0 || proof.shard >= proof.shards
			|| proof.shard in seen || proof.expected.len == 0 || proof.inputs.len == 0 {
			return error('invalid, duplicate or incomplete shard')
		}
		if seen.len == 0 {
			first = proof
		} else if proof.architecture != first.architecture || proof.inputs != first.inputs
			|| proof.expected != first.expected {
			return error('shard baselines or expected controls differ')
		}
		mut expected := []string{}
		for index, name in first.expected {
			if index % proof.shards == proof.shard { expected << name }
		}
		if proof.refused != expected {
			return error('missing, duplicated, reordered or wrongly assigned controls')
		}
		seen[proof.shard] = true
		count += proof.refused.len
		proofs[path] = digest(path)!
	}
	if seen.len != first.shards || count != first.expected.len {
		return error('incomplete control coverage')
	}
	for path, expected in first.inputs {
		if digest(path)! != expected { return error('shard baseline input changed: ' + path) }
	}
	for path, expected in proofs {
		if digest(path)! != expected { return error('shard proof changed') }
	}
	os.write_file(out, json2.encode(Coverage{
		architecture: first.architecture
		controls:     count
		shards:       first.shards
		proofs:       proofs
		inputs:       first.inputs
	}) + '\n')!
	println('WINE EVIDENCE SHARDS PASS ${first.architecture}: ${count} controls across ${first.shards} shards')
}

fn main() {
	check() or {
		eprintln(err)
		exit(1)
	}
}
