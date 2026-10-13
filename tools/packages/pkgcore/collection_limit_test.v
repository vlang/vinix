// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import json2
import os
import time

#include <sys/resource.h>

struct CollectionDescriptorLimit {
	current u64
	maximum u64
}

fn C.getrlimit(int, voidptr) int
fn C.setrlimit(int, voidptr) int

fn collection_limit_fixture() !string {
	work := os.temp_dir() + '/vinix-collection-limit-' + os.getpid().str() + '-' + time.now().unix_micro().str()
	os.mkdir_all(work + '/generations')!
	os.mkdir(work + '/objects')!
	for generation in 1 .. 131 {
		path := work + '/generations/' + generation.str()
		os.mkdir(path)!
		os.write_file(path + '/lease', '')!
		os.write_file(path + '/payload', 'generation ' + generation.str())!
		if generation >= 129 {
			state := State{ generation: u64(generation), previous: if generation == 130 { u64(129) } else { u64(0) }, architecture: 'aarch64' }
			os.write_file(path + '/state.json', json2.encode(state))!
		}
	}
	os.symlink('generations/130', work + '/current')!
	os.write_file(work + '/objects/' + 'a'.repeat(64), 'unused complete object')!
	os.write_file(work + '/objects/' + 'b'.repeat(64) + '.part', 'abandoned partial')!
	return work
}

fn test_collection_handles_128_obsolete_generations_with_32_descriptors_and_protects_live_leases() {
	work := collection_limit_fixture()!
	defer { os.rmdir_all(work) or {} }
	lease := C.open((work + '/generations/64/lease').str, C.O_RDONLY | C.O_CLOEXEC)
	assert lease >= 0 && C.flock(lease, C.LOCK_SH) == 0
	defer { C.close(lease) }
	mut original := CollectionDescriptorLimit{}
	assert C.getrlimit(C.RLIMIT_NOFILE, voidptr(&original)) == 0
	limited := CollectionDescriptorLimit{ current: 32, maximum: original.maximum }
	assert C.setrlimit(C.RLIMIT_NOFILE, voidptr(&limited)) == 0
	defer { assert C.setrlimit(C.RLIMIT_NOFILE, voidptr(&original)) == 0 }
	collect(Config{ architecture: 'aarch64' }, work)!
	assert os.ls(work + '/generations')!.sorted() == ['129', '130', '64']
	assert os.read_file(work + '/generations/64/payload')! == 'generation 64'
	assert os.ls(work + '/objects')!.len == 0
	assert os.readlink(work + '/current')! == 'generations/130'
	assert C.flock(lease, C.LOCK_UN) == 0
	collect(Config{ architecture: 'aarch64' }, work)!
	assert os.ls(work + '/generations')!.sorted() == ['129', '130']
	println('Package collection: 128 obsolete generations under RLIMIT_NOFILE=32; live lease preserved then retired')
}
