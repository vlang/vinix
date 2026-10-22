// SPDX-License-Identifier: GPL-2.0-or-later
// Exercise the real producer with private V-only tools and synthetic PE bytes.
module main

import crypto.sha256
import json2
import os

#include <unistd.h>

struct Reply { code int; text string }
struct Control { name string; code int; text string; output_created bool; proof_created bool }
struct Proof {
	format int = 1
	scope string = 'private producer admission controls; synthetic tools do not qualify compilation or Wine execution'
	passed bool
	producer_sha256 string
	driver_sha256 string
	executable_sha256 string
	compiler string
	compiler_sha256 string
	controls []Control
}

fn require(ok bool, message string) ! { if !ok { return error(message) } }
fn digest(path string) !string { return sha256.hexhash(os.read_file(path)!) }
fn run(argv []string, log string) !Reply {
	mut child := os.new_process(argv[0])
	defer { child.close() }
	child.set_args(argv[1..])
	child.set_redirect_stdio_merged()
	child.run()
	C.close(child.stdio_fd[0]); child.stdio_fd[0] = -1
	output := child.stdout_slurp()
	child.wait()
	os.write_file(log, output)!
	os.write_file(log + '.argv.json', json2.encode(argv) + '\n')!
	return Reply{ code: child.code, text: output }
}

const fake_source = 'module main
import os
fn main() {
 name := os.file_name(os.executable())
 if name.contains("objdump") { println("private fake objdump: admission control only"); return }
 mut output := ""
 for i, argument in os.args { if argument == "-o" && i + 1 < os.args.len { output = os.args[i + 1] } }
 if output == "" { eprintln("missing -o"); exit(9) }
 if name == "v" { os.write_file(output, "/* private fake V output */\\n") or { panic(err) }; return }
 kind := os.read_file(os.dir(os.executable()) + "/../case") or { panic(err) }
 mut bytes := []u8{len: 256}
 bytes[0] = `M`; bytes[1] = `Z`; bytes[60] = 64
 bytes[64] = `P`; bytes[65] = `E`
 bytes[68] = 0x64; bytes[69] = 0x86
 bytes[84] = 70; bytes[86] = 2
 bytes[88] = 0x0b; bytes[89] = 2; bytes[156] = 3
 match kind {
  "valid" {}
  "short" { bytes = []u8{len: 255} }
  "empty" { bytes = []u8{} }
  "dos" { bytes[0] = 0 }
  "offset" { for i in 60 .. 64 { bytes[i] = 0xff } }
  "offset-edge" { bytes[60] = 163 }
  "signature" { bytes[65] = 0 }
  "machine" { bytes[68] = 0x4c; bytes[69] = 1 }
  "optional-short" { bytes[84] = 69 }
  "not-executable" { bytes[86] = 0 }
  "dll" { bytes[87] = 0x20 }
  "pe32" { bytes[89] = 1 }
  "gui" { bytes[156] = 2 }
  else { eprintln("unknown private control"); exit(10) }
 }
 os.write_file_array(output, bytes) or { panic(err) }
 for argument in os.args { if argument.starts_with("-Wl,-Map,") { os.write_file(argument[9..], "private fake link map\\n") or { panic(err) } } }
}
'

fn check() ! {
	$if prod {} $else { return error('compile wine-pe-refusals with -prod to bind its source') }
	driver_hash := sha256.hexhash($embed_file('wine-pe-refusals.v').to_string())
	require(digest(@FILE)! == driver_hash, 'refusal driver source differs from its executable')!
	if os.args.len != 3 || os.args[1] == '' || os.args[2] == '' {
		return error('usage: wine-pe-refusals V NEW_OUTPUT')
	}
	v := os.real_path(os.args[1])
	require(os.is_file(v), 'V executable must be an existing ordinary file')!
	v_hash := digest(v)!
	requested := os.abs_path(os.args[2])
	require(!os.exists(requested) && !os.is_link(requested), 'control output must be new')!
	parent := os.real_path(os.dir(requested))
	require(os.is_dir(parent), 'control output parent must already exist')!
	work := parent + '/' + os.file_name(requested)
	producer := os.real_path(os.dir(@FILE) + '/wine-pe-check.v')
	producer_hash := digest(producer)!
	original := os.read_file(producer)!
	os.mkdir(work, mode: 0o700)!
	private := work + '/wine-pe-check.v'
	os.write_file(private, original)!
	os.cp(@FILE, work + '/control-driver.v')!
	os.write_file(work + '/fake-tool.v', fake_source)!
	for key in ['V', 'VEXE', 'V_MACOS_V3_CALLER_VEXE'] { os.setenv(key, v, true) }
	os.setenv('V_MACOS_V3_CALLER_VEXE_PRESENT', '1', true)
	os.setenv('V_MACOS_V3_CALLER_VCHILD_PRESENT', '0', true)
	os.setenv('V_MACOS_V3_NO_FALLBACK', '1', true)
	os.setenv('V_C_ERROR_BUG_REPORT_DISABLED', '1', true)
	for mode in ['prod', 'normal', 'fake'] {
		mut argv := [v, '-backend', 'c', '-keepc', '-gc', 'none', '-manualfree']
		if mode != 'normal' { argv << '-prod' }
		argv << ['-o', work + '/' + mode, if mode == 'fake' { work + '/fake-tool.v' } else { private }]
		reply := run(argv, work + '/compile-' + mode + '.log')!
		require(reply.code == 0, 'private compiler failed: ' + mode)!
	}
	fake_vroot := work + '/fake-vroot'
	mingw := work + '/fake-mingw'
	for path in [fake_vroot, fake_vroot + '/vlib', fake_vroot + '/thirdparty', mingw, mingw + '/bin'] { os.mkdir(path)! }
	os.write_file(fake_vroot + '/vlib/inventory', 'private fake compiler tree')!
	for path in [fake_vroot + '/v', mingw + '/bin/x86_64-w64-mingw32-gcc', mingw + '/bin/x86_64-w64-mingw32-objdump'] { os.cp(work + '/fake', path)!; os.chmod(path, 0o700)! }
	program := work + '/program.v'
	os.write_file(program, 'module main\nfn main() {}\n')!
	mut controls := []Control{}
	for kind in ['valid', 'short', 'empty', 'dos', 'offset', 'offset-edge', 'signature', 'machine', 'optional-short', 'not-executable', 'dll', 'pe32', 'gui'] {
		os.write_file(mingw + '/case', kind)!
		output := work + '/output-' + kind
		reply := run([work + '/prod', fake_vroot + '/v', mingw, program, output, '--local-qualification-only'], work + '/' + kind + '.log')!
		proof := os.is_file(output + '/proof.json')
		if kind == 'valid' {
			require(reply.code == 0 && proof, 'private valid PE-header baseline must pass')!
			require(digest(output + '/producer.v')! == producer_hash, 'retained producer copy differs')!
		} else {
			require(reply.code != 0 && !proof && (reply.text.contains('Win64 output lacks its DOS header') || reply.text.contains('Win64 PE header is outside the file') || reply.text.contains('output must be an executable AMD64 PE32+ Windows console program')), 'malformed PE accepted or wrong refusal: ' + kind)!
		}
		controls << Control{ name: kind, code: reply.code, text: reply.text, output_created: os.exists(output), proof_created: proof }
	}
	for kind in ['stale-source', 'non-production'] {
		if kind == 'stale-source' { os.write_file(private, original + '\n// private stale-source control\n')! }
		output := work + '/output-' + kind
		reply := run([work + if kind == 'stale-source' { '/prod' } else { '/normal' }, fake_vroot + '/v', mingw, program, output, '--local-qualification-only'], work + '/' + kind + '.log')!
		require(reply.code != 0 && !os.exists(output) && reply.text.contains(if kind == 'stale-source' { 'Win64 producer source differs from its executable' } else { 'compile wine-pe-check with -prod to bind its source' }), 'source/prod guard did not refuse before output creation: ' + kind)!
		controls << Control{ name: kind, code: reply.code, text: reply.text }
		os.write_file(private, original)!
	}
	require(digest(producer)! == producer_hash, 'live producer changed during independent checks')!
	require(digest(@FILE)! == driver_hash && digest(work + '/control-driver.v')! == driver_hash,
		'control driver changed during independent checks')!
	require(digest(v)! == v_hash, 'V executable changed during independent checks')!
	os.write_file(work + '/controls.json', json2.encode(Proof{passed: true, producer_sha256: producer_hash,
		driver_sha256: driver_hash, executable_sha256: digest(os.executable())!, compiler: v,
		compiler_sha256: v_hash, controls: controls}) + '\n')!
	println('WINE PE private -prod baseline, 12 malformed PE refusals, stale source and non-production refusal PASS: ' + work)
}

fn main() { check() or { eprintln(err); exit(1) } }
