// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os

fn require(good bool, reason string) ! { if !good { return error(reason) } }
fn run() ! {
	if os.args.len != 6 { return error('Usage: ppollsignal-alloc-check TRACE-GENERATOR SLAB-GENERATOR DELTA ROOT FRESH-STATE') }
	state := os.args[5]
	require(!os.exists(state),'Fresh state required')!
	os.mkdir_all(state)!
	trace := os.exec([os.args[1],os.args[4],state+'/generated'])
	os.write_file(state+'/generate.log',trace.output)!
	require(trace.exit_code == 0,'Trace generator failed')!
	procfs := os.read_file(os.args[4]+'/kernel/fs/procfs.v')!
	require(os.read_file(state+'/generated/procfs.v')! == procfs.replace('C.alloc_track_dump(unsafe { &char(buf) }, cap, 50)','C.alloc_track_dump(unsafe { &char(buf) }, cap, 1)'), 'Trace changed unrelated kernel source')!
	for file in ['storage.v','bounds.v'] {
		source := os.read_file(os.args[4]+'/tests/linux-compat/ppollsignalfixture/'+file)!
		generated := os.read_file(state+'/generated/probe-root/tests/linux-compat/ppollsignalfixture/'+file)!
		if file == 'bounds.v' { require(source == generated,'Bounds changed')! }
		else { require(generated.contains('if !snapshot(fd,before) { fatal(32) }') && generated.contains('if !snapshot(fd,after) { fatal(33) }') && generated.contains('for _ in 0 .. 200'), 'Storage guards changed')! }
	}
	slab := os.exec([os.args[2],os.args[4]+'/kernel/fs/procfs.v',state+'/slab.v'])
	os.write_file(state+'/slab.log',slab.output)!
	require(slab.exit_code == 0 && os.read_file(state+'/slab.v')!.contains('slab_attribution_sample()'),'Slab generator failed')!
	mut positives := 2
	mut negatives := 0
	for command in [[os.args[1],os.args[4],state+'/generated'],[os.args[2],os.args[4]+'/kernel/fs/procfs.v',state+'/slab.v']] {
		require(os.exec(command).exit_code != 0,'Existing output accepted')!
		negatives++
	}
	os.write_file(state+'/wrong.v',procfs.replace('.slabinfo {','.different {'))!
	require(os.exec([os.args[2],state+'/wrong.v',state+'/bad-slab.v']).exit_code != 0,'Different slab layout accepted')!
	negatives++
	pcs := '100 200 300 400 500 600 700 800 900 a00'
	before := 'PERF-SITE ppollsignal phase=before '
	after := 'PERF-SITE ppollsignal phase=after '
	good := before+'live 3 dropped 0\n'+before+'2 64 '+pcs+'\n'+before+'1 192 '+pcs+'\n'+after+'live 3 dropped 0\n'+after+'3 64 '+pcs+'\n'
	path := state+'/control.log'
	os.write_file(path,good)!
	valid := os.exec([os.args[3],path])
	os.write_file(state+'/delta.log',valid.output)!
	require(valid.exit_code == 0 && valid.output.contains('before=2 after=3 delta=1 3 64 ') && valid.output.contains('before=1 after=0 delta=-1 0 192 '),'Delta arithmetic rejected')!
	positives++
	variants := [good.replace(after+'live 3 dropped 0\n',''),good+before+'live 3 dropped 0\n',
		good.replace('dropped 0','dropped 1'),good.replace('live 3','live 4'),
		good.replace(before+'1 192 '+pcs+'\n',''),good+after+'3 64 '+pcs+'\n',
		good.replace('a00','xyz'),good.replace('a00',''),good.replace('2 64','0 64'),
		good.replace('2 64','65537 64'),good.replace('before','unknown'),good.replace('live 3','live 9223372036854775808')]
	for i,variant in variants {
		bad := state+'/negative-'+i.str()+'.log'
		os.write_file(bad,variant)!
		require(os.exec([os.args[3],bad]).exit_code != 0,'Malformed dump accepted: '+i.str())!
		negatives++
	}
	println('Ppoll allocation controls: PASS ('+positives.str()+' positive, '+negatives.str()+' negative)')
}
fn main() { run() or { eprintln(err.msg()); exit(1) } }
