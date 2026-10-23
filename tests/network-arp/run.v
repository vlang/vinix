// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os

fn checked(args []string) {
	r := os.exec(args)
	assert r.exit_code == 0, r.output
	if r.output.trim_space() != '' { println(r.output.trim_space()) }
}

fn main() {
	repo := os.real_path(os.dir(@FILE) + '/../..')
	work := os.join_path(repo, 'build/network-arp')
	os.mkdir_all(work + '/arch')!
	mut options := os.read_file(repo + '/kernel/c/lwipopts.h')!.replace('#define LWIP_STATS 0', '#define LWIP_STATS 1')
	if '--baseline' in os.args {
		options = options.replace('#define ARP_QUEUEING 1', '#define ARP_QUEUEING 0')
	}
	os.write_file(work + '/lwipopts.h', options)!
	os.cp(repo + '/kernel/c/arch/cc.h', work + '/arch/cc.h')!
	lwip := repo + '/kernel/c/lwip'
	mut sources := os.walk_ext(lwip + '/core', '.c')
	sources << lwip + '/netif/ethernet.c'
	mut objects := []string{}
	for i, source in sources {
		object := work + '/part${i}.o'
		checked(['cc', '-O2', '-Wno-macro-redefined', '-DVINIX_V_RUNTIME', '-I' + work,
			'-I' + lwip + '/include', '-c', source, '-o', object])
		objects << object
	}
	checked(['ar', 'rcs', work + '/lwip.a', ...objects])
	checked([@VEXE, '-enable-globals', '-nocache', '-cc', 'cc', '-cflags',
		'-O2 -DVINIX_V_RUNTIME -Wno-macro-redefined -I' + work + ' -I' + lwip + '/include', '-ldflags',
		work + '/lwip.a', '-o', work + '/fixture', repo + '/tests/network-arp/fixture.v'])
	checked([work + '/fixture'])
	println('Network ARP regression passed')
}
