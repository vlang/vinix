// SPDX-License-Identifier: GPL-2.0-or-later
module verifiedhost

import bundlehost as bh
import hosttest
import os
import verityimage

fn descriptors() int { return (os.ls('/dev/fd') or { return -1 }).len }

pub fn native_contracts() ! {
	specifications := [hosttest.Option{ name: '--initramfs', value: true },
		hosttest.Option{ name: '--output', value: true }, hosttest.Option{ name: '--developer-unsigned' }]
	parsed := bh.parse(['--init=a b', '--initramfs', "second'file", '--out', 'new',
		'--developer-unsigned'], specifications, ['--initramfs'], 0, '')!
	assert parsed.values['--initramfs'] == ['a b', "second'file"] && parsed.value('--output', '') == 'new'
	for value in ['1', '+1', '0001', '1_0'] {
		assert (bh.Options{ values: {
			'--count': [value]
		} }).count('--count')! > 0
	}
	for value in ['++1', 'x', '1__0', '_1', '1_'] {
		mut rejected := false
		(bh.Options{ values: {
			'--count': [value]
		} }).count('--count') or {
			assert err is bh.ArgumentError
			rejected = true
			u64(0)
		}
		assert rejected
	}
	for value in ['-1', '18446744073709551616', '999999999999999999999999999999999999999999'] {
		mut rejected := false
		(bh.Options{ values: {
			'--count': [value]
		} }).count('--count') or {
			assert err !is bh.ArgumentError
			rejected = true
			u64(0)
		}
		assert rejected
	}
	work := temporary('vinix-verified-contracts-')!
	defer { bh.retire(work) }
	before := descriptors()
	// Repeated verification touches success, malformed geometry, size mismatch
	// and real file errors. Each path must retire its opened descriptors.
	os.write_file_array(work + '/data', []u8{len: 8192, init: `v`})!
	metadata := verityimage.build(work + '/data', work + '/image', false)!
	for _ in 0 .. 100 {
		verityimage.verify(work + '/image', 2, metadata.root_hash)!
		mut rejected := false
		verityimage.verify(work + '/image', 1, metadata.root_hash) or { rejected = true }
		assert rejected
		rejected = false
		verityimage.verify(work + '/missing', 2, metadata.root_hash) or { rejected = true }
		assert rejected
	}
	assert before == descriptors()
	for length in [0, 1, 27, 28, 60, 128] {
		os.write_file_array(work + '/variables', []u8{len: length})!
		mut rejected := false
		enroll_variables(work + '/variables', work + '/missing-cert', work + '/output') or { rejected = true }
		assert rejected && !os.exists(work + '/output')
	}
	os.write_file_array(work + '/tiny', []u8{len: 1})!
	tamper(work + '/tiny', 0)!
	assert (os.read_bytes(work + '/tiny')!) == [u8(1)]
	mut rejected := false
	tamper(work + '/tiny', 1) or { rejected = true }
	assert rejected && descriptors() == before
	assert strip_ansi('\x1b[31mVERIFIED ROOT: PASS\x1b[0m\n') == 'VERIFIED ROOT: PASS\n'
	println('PASS native verified-tool CLI contracts, descriptor retirement, bounded firmware rejection and durable byte mutations')
}
