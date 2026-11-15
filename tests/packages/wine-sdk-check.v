// SPDX-License-Identifier: GPL-2.0-or-later
// Layer an SDK declaration audit on the retained original host checker.
module main

import os
import json2
import tests.packages.winesdk
import tests.packages.winelink
import tests.packages.winesource

struct Host {
	format int
	builder string
	inputs map[string]string
	outputs map[string]string
}

struct Receipt {
	format int = 1
	build string
	checker string
	checker_sha256 string
	host_proof_sha256 string
	archive_sha256 string
	graph winesdk.Graph
}

fn run() ! {
	if os.args.len != 4 { return error('usage: SDK_CHECK ORIGINAL_HOST_BUILDER HOST_BUILD FRESH_OUTPUT') }
	tool := os.real_path(os.args[1]); build := os.real_path(os.args[2]); output := os.abs_path(os.args[3])
	if os.exists(output) || os.is_link(output) { return error('fresh SDK audit output required') }
	proof := build + '/host-build.json'
	if os.lstat(proof)!.get_filetype() != .regular { return error('ordinary host receipt required') }
	proof_hash := winesource.file_digest(proof)!
	host := json2.decode[Host](os.read_file(proof)!)!
	hash := winesource.file_digest(tool)!
	if host.format != 3 || tool != host.builder || hash != host.inputs[tool] { return error('original format-3 host checker required') }
	mut child := os.new_process(tool)
	defer { child.close() }
	child.set_args(['check', build]); child.set_redirect_stdio_merged(); child.run()
	C.close(child.stdio_fd[0]); child.stdio_fd[0] = -1
	text := child.stdout_slurp(); child.wait()
	if child.code != 0 || text != 'WINE HOST BUILD ADMISSION PASS\n' { return error('original host admission refused: ' + text) }
	archive_path := build + '/link-inputs.tar'
	st := os.lstat(archive_path)!
	if st.get_filetype() != .regular || st.size > 512 * 1024 * 1024 { return error('bounded ordinary link archive required') }
	archive_hash := winesource.file_digest(archive_path)!
	if archive_hash != host.outputs['link-inputs.tar'] { return error('host link archive pin differs') }
	bytes := os.read_bytes(archive_path)!
	graph := winesdk.graph(winelink.parse(bytes)!, bytes)!
	winesdk.verify_sources(graph)!
	if winesource.file_digest(proof)! != proof_hash || winesource.file_digest(archive_path)! != archive_hash
		|| winesource.file_digest(tool)! != hash { return error('SDK audit host inputs changed') }
	os.mkdir_all(output)!
	os.write_file(output + '/host-check.log', text)!
	os.write_file(output + '/receipt.json', json2.encode(Receipt{build: build, checker: tool, checker_sha256: hash,
		host_proof_sha256: proof_hash, archive_sha256: archive_hash, graph: graph}) + '\n')!
	println('WINE SDK DECLARATIONS PASS stubs=' + graph.stubs.len.str() + ' documents=' + graph.edges.len.str())
}

fn main() { run() or { eprintln(err); exit(1) } }
