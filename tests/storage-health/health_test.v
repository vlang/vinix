// SPDX-License-Identifier: GPL-2.0-or-later
module ahci

import errno
import resource
import klock
import stat

fn setup() &AHCIDevice {
	calls=0; supported=true; enabled=true; broken_checksum=false; short_call=0; fail_call=0
	support_valid=true; enabled_valid=true
	status_type=0x34; status_bits=0x50; status_mid=0x4f; status_high=0xc2
	header := unsafe { &AHCIHBACommand(calloc(1,sizeof(AHCIHBACommand))) }
	table := u64(unsafe { calloc(1,sizeof(AHCIHBACommandTable)) })
	unsafe { header.ctba=u32(table); header.ctbau=u32(table >> 32) }
	return &AHCIDevice{stat:stat.Stat{rdev:17},parent_controller:&AHCIController{cmd_slots:1,regs:unsafe { nil }},
		regs:&AHCIPortRegisters{clb:u32(u64(header)),clbu:u32(u64(header) >> 32)},
		bounce:unsafe { calloc(1,512) },fis_base:u64(unsafe { calloc(1,256) })}
}

fn test_complete_report_and_threshold_warning_keep_buffers_and_counts() {
	mut device:=setup()
	buffer:=device.bounce
	report:=device.block_health() or { assert false; return }
	assert sizeof(report)==1088 && report.version==1 && report.protocol==resource.health_ata
	assert report.disk_id==17 && report.flags==15 && calls==3 && klock.depth==0
	assert report.identify[20]==0x42 && report.data[2]==190 && report.data[7]==31
	assert device.bounce==buffer && device.metrics.failures==0 && !device.failed
	for value in report.reserved { assert value==0 }
	calls=0; status_mid=0xf4; status_high=0x2c
	warning:=device.block_health() or { assert false; return }
	assert warning.flags==31 && device.metrics.failures==0 && !device.failed && klock.depth==0
}

fn test_disabled_or_unsupported_smart_only_identifies() {
	mut device:=setup(); enabled=false
	report:=device.block_health() or { assert false; return }
	assert calls==1 && report.flags==1 && device.metrics.failures==0
	for value in report.data { assert value==0 }
	calls=0; supported=false; enabled=true
	unsupported:=device.block_health() or { assert false; return }
	assert calls==1 && unsupported.flags==0 && !device.failed && klock.depth==0
	calls=0; supported=true; support_valid=false
	invalid:=device.block_health() or { assert false; return }
	assert calls==1 && invalid.flags==0
	calls=0; support_valid=true; enabled_valid=false
	invalid_enabled:=device.block_health() or { assert false; return }
	assert calls==1 && invalid_enabled.flags==1 && device.metrics.failures==0 && klock.depth==0
}

fn test_short_transfers_bad_checksums_and_failed_ports_propagate_once() {
	for stage in 1 .. 4 {
		mut device:=setup(); fail_call=stage
		assert device.block_health()==none
		assert device.failed && calls==stage && device.metrics.failures==1 && errno.get()==errno.eio && klock.depth==0
		assert device.block_health()==none && calls==stage && errno.get()==errno.enodev
	}
	for stage in 1 .. 3 {
		mut device:=setup(); short_call=stage
		assert device.block_health()==none
		assert calls==stage && !device.failed && device.metrics.failures==1 && errno.get()==errno.eio && klock.depth==0
	}
	mut device:=setup(); broken_checksum=true
	assert device.block_health()==none
	assert calls==2 && !device.failed && device.metrics.failures==1 && errno.get()==errno.eio && klock.depth==0
}

fn test_invalid_status_never_becomes_healthy() {
	for bits in [u8(0x80),0x20,8,1]! {
		mut device:=setup(); status_bits=bits
		assert device.block_health()==none && calls==3 && device.metrics.failures==1 && klock.depth==0
	}
	mut device:=setup(); status_type=0
	assert device.block_health()==none && errno.get()==errno.eio
	device=setup(); status_mid=0; status_high=0
	assert device.block_health()==none && errno.get()==errno.eio && klock.depth==0
}
