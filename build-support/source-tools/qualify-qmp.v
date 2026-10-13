// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module main

import cachecli
import crypto.sha256
import hosttest
import json2
import os
import sourcecommand

fn checked(argv []string, env map[string]string, log string) !sourcecommand.Output {
	r:=sourcecommand.capture_full(argv,env,300,32*1024*1024,cachecli.cancelled) or {
		os.write_file(log,err.msg()+'\n')!
		return error('qualification command did not complete: '+log+': '+err.msg())
	}
	text:=r.stdout+r.stderr
	os.write_file(log,text)!
	if r.status!=0 || ['retrying with',': fn ','V panic:','runtime error:','ERROR: AddressSanitizer'].any(text.contains(it)) {return error('QMP/source qualification failed: '+log)}
	return r
}

fn qualify() ! {
	if os.args.len!=4 {return error('expected COMPILER NEW_EVIDENCE arm|x86|san')}
	compiler,work,profile:=os.args[1],os.args[2],os.args[3]
	if os.exists(work) || profile !in ['arm','x86','san'] {return error('expected new evidence and profile')}
	os.mkdir_all(work)!
	os.mkdir(work+'/tmp')!
	root:=os.real_path(os.dir(@FILE)+'/../..')
	mut env:=os.environ()
	for key,value in {'V':compiler,'VINIX_V_COMPILER':compiler,'VTMP':work+'/tmp','TMPDIR':work+'/tmp',
		'V_C_ERROR_BUG_REPORT_DISABLED':'1','V_MACOS_V3_NO_FALLBACK':'1',
		'ASAN_OPTIONS':'detect_leaks=0:detect_stack_use_after_return=1:abort_on_error=1','UBSAN_OPTIONS':'halt_on_error=1:print_stacktrace=1'} {env[key]=value}
	mut flags:=[]string{}
	mut wrapper_flags:=''
	if profile=='x86' {
		flags=['-arch','amd64','-cflags','--target=x86_64-apple-macos13','-ldflags','--target=x86_64-apple-macos13']
		wrapper_flags='-arch amd64 -cflags --target=x86_64-apple-macos13 -ldflags --target=x86_64-apple-macos13 '
	}
	if profile=='san' {
		flags=['-gc','none','-cflags','-fsanitize=address,undefined','-cflags','-fno-omit-frame-pointer','-cflags','-O1','-ldflags','-fsanitize=address,undefined']
		wrapper_flags='-gc none -cflags -fsanitize=address,undefined -cflags -fno-omit-frame-pointer -cflags -O1 -ldflags -fsanitize=address,undefined '
	}
	mut receipts:=[]json2.Any{}
	for name,path in {'main':root+'/build-support/source-tools/main.v','check':root+'/build-support/source-tools/check-qmp.v',
		'trim':root+'/build-support/source-tools/trim-cmake.v','stage':root+'/build-support/source-tools/stage-trimmer.v',
		'core-test':root+'/tools/qmpclient/core_test.v','owned-test':root+'/tools/qmpclient/owned_test.v',
		'source-check':root+'/build-support/source-tools/check.v','host-check':root+'/build-support/source-tools/check-host.v'} {
		checked([compiler,'-nocache','-cc','/usr/bin/clang',...flags,'-o',work+'/'+name,path],env,work+'/'+name+'-build.log')!
		receipts<<json2.Any({'name':json2.Any(name),'sha256':json2.Any(sha256.sum(os.read_bytes(work+'/'+name)!).hex())})
	}
	checked([work+'/check',work+'/main',work+'/trim',work+'/fixtures'],env,work+'/check.log')!
	os.setenv('TMPDIR','/private/tmp',true)
	short:=hosttest.work_dir('','qmp-regress-')!
	defer {hosttest.remove_work_dir(short) or {}}
	for name in ['core-test','owned-test'] {
		mut test_env:=env.clone();test_env['TMPDIR']=short
		checked([work+'/'+name],test_env,work+'/'+name+'.log')!
	}
	checked([work+'/source-check',work+'/source-fixtures',root],env,work+'/source-check.log')!
	checked([work+'/host-check',work+'/host-fixtures',root],env,work+'/host-check.log')!
	// Install exactly once before exercising the public caller's socket path.
	wrapper:=work+'/v-compiler'
	os.write_file(wrapper,'#!/bin/sh\nexec /usr/bin/env -u CFLAGS -u LDFLAGS "'+compiler+'" -nocache -cc /usr/bin/clang '+wrapper_flags+'"$@"\n')!
	os.chmod(wrapper,0o755)!
	env['V']=wrapper;env['VINIX_V_COMPILER']=wrapper
	checked([work+'/main','install-qmp',work+'/installed-qmp'],env,work+'/install.log')!
	checked([work+'/check',work+'/installed-qmp',work+'/trim',work+'/installed-fixtures'],env,work+'/installed-check.log')!
	os.write_file(work+'/preserved-qmp','old QMP output')!
	mut failed_env:=env.clone();failed_env['V']='/usr/bin/false'
	failed:=sourcecommand.capture_full([work+'/main','install-qmp',work+'/preserved-qmp'],failed_env,20,65536,cachecli.cancelled)!
	assert failed.status!=0 && os.read_file(work+'/preserved-qmp')! == 'old QMP output'
	// Each host architecture builds the static guest tool from ordinary Linux
	// V C generation; the existing musl SDK supplies compiler/runtime objects.
	env['V']=compiler;env['VINIX_V_COMPILER']=compiler
	env['CC']='/opt/homebrew/opt/llvm/bin/clang'
	checked([work+'/stage',work+'/guest/trim-cmake'],env,work+'/guest-build.log')!
	checked(['/opt/homebrew/opt/llvm/bin/llvm-readelf','-h','-l',work+'/guest/trim-cmake'],env,work+'/guest-elf.log')!
	os.write_file(work+'/preserved-trimmer','old guest output')!
	failed_env=env.clone();failed_env['V']='/usr/bin/false'
	failed_guest:=sourcecommand.capture_full([work+'/stage',work+'/preserved-trimmer'],failed_env,20,65536,cachecli.cancelled)!
	assert failed_guest.status!=0 && os.read_file(work+'/preserved-trimmer')! == 'old guest output'
	checked(['/bin/bash','-n',root+'/scripts/test-iso.sh'],env,work+'/iso-syntax.log')!
	checked(['/bin/sh','-n',root+'/tests/opengothic/kekvm-guest.sh'],env,work+'/guest-syntax.log')!
	checked(['/bin/bash',root+'/scripts/test-iso.sh','--help'],env,work+'/iso-help.log')!
	inputs:=hosttest.hashes([root+'/tools/qmpclient/core.v',root+'/tools/qmpclient/raw.v',root+'/tools/qmpclient/owned.v',
		root+'/build-support/source-tools/main.v',root+'/build-support/source-tools/sourcefixture/core.v',
		root+'/build-support/source-tools/check-qmp.v',root+'/build-support/source-tools/stage-trimmer.v',root+'/build-support/source-tools/trim-cmake.v'])!
	os.write_file(work+'/qualification.json',json2.encode(json2.Any({'status':json2.Any('PASS'),'profile':json2.Any(profile),
		'receipts':json2.Any(receipts),'inputs':json2.Any(hosttest.string_map(inputs)),
		'limits':json2.Any('Native Unix-socket exchanges, installed CLI, interruption/descriptor/error/JSON policies and existing QMP/source/host regressions. Static AArch64/Linux ELF built with the existing musl SDK; no target ELF, guest, ISO boot or GUI application executes. No Python or foreign SDK interpreter initialization. QMP JSON must be standard objects; error desc accepts text, null, booleans and signed integer exit statuses.')}),prettify:true)+'\n')!
	println('PASS native ISO QMP and guest-source qualification '+profile)
}

fn main() {
	guard:=cachecli.own_commands()
	defer {guard.close()}
	qualify() or {eprintln(err);exit(1)}
}
