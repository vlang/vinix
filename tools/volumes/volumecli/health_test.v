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
	report.version=1; report.protocol=3
	assert !health_valid(&report)
	report.protocol=1; report.disk_id=0
	assert !health_valid(&report)
}

fn test_nvme_health_validation_warning_bits_and_full_128_bit_counters() {
	mut report := Health{version:1,protocol:2,disk_id:99,flags:15}
	assert health_valid(&report) && health_exit(&report)==0
	// NVMe has no ATA checksum; preserve counters above 64 bits and unknown
	// warning bits rather than truncating either to the current known set.
	report.data[47]=0xfa
	assert health_valid(&report)
	for warning in [u8(1),2,4,8,16,32,64,128,255]! {
		report.data[0]=warning; report.flags=31
		assert health_valid(&report) && health_exit(&report)==3
		report.flags=15
		assert !health_valid(&report)
	}
	report.data[0]=0; report.flags=31
	assert !health_valid(&report)
	for flags in [u64(0),1,3,7,11,16,47]! {
		report.flags=flags
		assert !health_valid(&report)
	}
	mut bytes:=[16]u8{}
	mut output:=[35]u8{}
	for i in 0 .. 16 { bytes[i]=u8(i) }
	output[33]=0xad; output[34]=0xae
	nvme_counter(&bytes[0],&output[0])
	assert unsafe { output[..33].bytestr() } == '0f0e0d0c0b0a09080706050403020100\x00'
	assert output[33]==0xad && output[34]==0xae
	for i in 0 .. 16 { bytes[i]=255 }
	nvme_counter(&bytes[0],&output[0])
	assert unsafe { output[..33].bytestr() } == 'ffffffffffffffffffffffffffffffff\x00'
}

fn test_nvme_identity_text_is_bounded_unswapped_and_sanitized() {
	mut bytes:=[512]u8{}
	mut output:=[43]u8{}
	for i in 0 .. 40 { bytes[24+i]=` ` }
	bytes[24]=`M`; bytes[25]=`O`; bytes[26]=`D`; bytes[27]=`E`; bytes[28]=0; bytes[29]=27; bytes[30]=255
	output[41]=0xad; output[42]=0xae
	nvme_text(&bytes[0],24,40,&output[0])
	assert unsafe { output[..8].bytestr() } == 'MODE???\x00'
	assert output[41]==0xad && output[42]==0xae
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
