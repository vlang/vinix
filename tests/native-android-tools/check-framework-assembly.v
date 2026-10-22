// SPDX-License-Identifier: GPL-2.0-or-later
module main

import androidtools
import os

fn main() {
	assert os.args.len == 3, 'usage: check-framework-assembly TOOLS JAVA'
	work := os.join_path(os.temp_dir(), 'vinix-framework-assembly-' + os.getpid().str())
	os.mkdir_all(work + '/smali')!
	defer { os.rmdir_all(work) or {} }
	dex := work + '/classes.dex'
	source := '.class public LProbe;\n.super Ljava/lang/Object;\n'
	os.write_file(work + '/smali/Probe.smali', source)!
	androidtools.framework_assemble(work + '/smali', dex, os.real_path(os.args[1]), os.args[2])!
	assert os.read_bytes(dex)!.len > 112
	// Real Smali exits zero for this parse error. The previous valid DEX must
	// be removed, and the failure must contain the assembler diagnostic.
	os.write_file(work + '/smali/Probe.smali', source + '// invalid comment\n')!
	mut rejected := false
	androidtools.framework_assemble(work + '/smali', dex, os.real_path(os.args[1]), os.args[2]) or {
		assert err.msg().contains('Invalid text')
		rejected = true
	}
	assert rejected
	assert !os.exists(dex)
	println('FRAMEWORK-ASSEMBLY-PASS valid-dex syntax-error stale-output-rejected')
}
