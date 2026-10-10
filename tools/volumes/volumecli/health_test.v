// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

fn test_health_validation_and_exit_status() {
	mut report:=Health{version:1,protocol:1,disk_id:42,flags:15}
	assert health_valid(&report) && health_exit(&report)==0
	report.flags=31
	assert health_valid(&report) && health_exit(&report)==3
	report.flags=1
	assert health_valid(&report) && health_exit(&report)==4
	for flags in [u64(2),4,8,16,32,5,9]! {
		report.flags=flags
		assert !health_valid(&report)
	}
	report.flags=15; report.data[509]=1
	assert !health_valid(&report)
	report.data[511]=255
	assert health_valid(&report)
	report.reserved[3]=1
	assert !health_valid(&report)
	report.reserved[3]=0; report.version=2
	assert !health_valid(&report)
	report.version=1; report.protocol=2
	assert !health_valid(&report)
	report.protocol=1; report.disk_id=0
	assert !health_valid(&report)
}

fn test_identity_text_is_bounded_swapped_and_sanitized_and_raw_keeps_all_bytes() {
	mut bytes:=[512]u8{}
	mut output:=[43]u8{}
	for i in 0 .. 40 { bytes[54+i]=` ` }
	bytes[54]=`O`; bytes[55]=`M`; bytes[56]=`E`; bytes[57]=`D`; bytes[58]=0; bytes[59]=27
	output[41]=0xad; output[42]=0xae
	ata_text(&bytes[0],54,40,&output[0])
	assert unsafe { output[..7].bytestr() } == 'MODE??\x00'
	assert output[41]==0xad && output[42]==0xae
	for i in 0 .. 6 { bytes[i]=255 }
	assert attribute_raw(&bytes[0])==0xffffffffffff
	for i in 0 .. 6 { bytes[i]=u8(i+1) }
	assert attribute_raw(&bytes[0])==0x060504030201
}
