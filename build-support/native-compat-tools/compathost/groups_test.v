// SPDX-License-Identifier: GPL-2.0-or-later
module compathost

fn test_swap_version_one_golden_and_sparse_size_bounds() {
	header := groups_swap_header(i64(256 * 1024 * 1024)) or { panic(err) }
	assert header.len == 4096
	assert header[1024..1036].hex() == '01000000ffff000000000000'
	assert header[..1024].all(it == 0) && header[1036..4086].all(it == 0)
	assert header[4086..].bytestr() == 'SWAPSPACE2'
	for invalid in [i64(0), 4096, 8193, (i64(0xffffffff) + 2) * 4096] {
		if _ := groups_swap_header(invalid) { assert false } else { assert err.msg().contains('Invalid') }
	}
}

fn test_group_disk_registration_and_x86_entropy_device() {
	base := ['/qemu', '-m', '1024', '-smp', '2', '-cpu', 'max', '-device', 'virtio-rng-device', '-device', 'virtio-blk-device,drive=guest-iso']
	arm := groups_launch(base, 'aarch64', '/swap', 4096, 8)
	assert arm[arm.index('-m') + 1] == '4096' && arm[arm.index('-smp') + 1] == '8'
	assert arm[arm.index('-device') + 1] == 'virtio-rng-device'
	assert arm[base.len..] == ['-drive', 'if=none,format=raw,file=/swap,id=paging-swap', '-device', 'virtio-blk-device,drive=paging-swap']
	assert arm[arm.index('-drive') + 1] == 'if=none,format=raw,file=/swap,id=paging-swap'
	x86 := groups_launch(base, 'x86_64', '/swap', 512, 4)
	assert x86[base.len..] == ['-drive', 'if=ide,format=raw,file=/swap', '-object', 'rng-random,filename=/dev/urandom,id=paging-rng', '-device', 'virtio-rng-pci,rng=paging-rng']
	assert base[2] == '1024'
}
