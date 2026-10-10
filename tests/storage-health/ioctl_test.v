// SPDX-License-Identifier: GPL-2.0-or-later
module fs

import errno
import file
import resource
import stat

struct TestDisk { mut: stat stat.Stat calls int fail bool }
fn (mut d TestDisk) block_health() ?resource.BlockHealth {
	d.calls++
	if d.fail { errno.set(errno.eio); return none }
	return resource.BlockHealth{protocol:1,flags:15,disk_id:42}
}
struct Unsupported { mut: stat stat.Stat }

fn test_health_dispatch_requires_read_mode_and_mac_and_preserves_faults() {
	mut disk:=&TestDisk{}
	mut box:=resource.Resource(disk)
	mut handle:=file.Handle{resource:&box}
	mut fd:=file.FD{handle:&handle}
	mut report:=resource.BlockHealth{}
	assert (storage_health(mut fd,&report) or { -1 })==0 && report.disk_id==42 && disk.calls==1
	handle.flags=2
	assert (storage_health(mut fd,&report) or { -1 })==0 && disk.calls==2
	for flags in [1,0o10000000,0o10000002]! {
		handle.flags=flags
		assert storage_health(mut fd,&report)==none && errno.get()==errno.ebadf && disk.calls==2
	}
	handle.flags=0; file.deny=true
	assert storage_health(mut fd,&report)==none && errno.get()==errno.eperm && disk.calls==2
	file.deny=false
	assert storage_health(mut fd,unsafe { nil })==none && errno.get()==errno.efault && disk.calls==3
	disk.fail=true
	assert storage_health(mut fd,&report)==none && errno.get()==errno.eio && disk.calls==4
	assert report.disk_id==42
	mut unsupported:=resource.Resource(&Unsupported{})
	handle.resource=&unsupported
	assert storage_health(mut fd,&report)==none && errno.get()==errno.enotty
}
