// SPDX-License-Identifier: ISC
module wifihost

import os

const mac_core = '  |   "FirmwareLoaded" = Yes
  |   "ChipSet" = 4378
  |   "ModuleInfo" = "chip=\'s=B1\' module=\'M=RASP m=6.11  V=m\' prod=\'17445\' manuf=\'5348\'"
  |   "FirmwareVersion" = "18.20.480.2.7.8.187"
  |   "RequestedFiles" = ({"Firmware"="C-4378__s-B1/shikoku.trx","TxCap"="C-4378__s-B1/shikoku-X3.txcb","Regulatory"="C-4378__s-B1/shikoku-X3.clmb","NVRAM"="C-4378__s-B1/P-shikoku-X3_M-RASP_V-m__m-6.11.txt"})'
const mac_tree = '    "module-instance" = <"shikoku">
    "wifi-antenna-sku-info" = <01000000000000005833000000000000>'

fn test_live_macos_identity_and_manifest() {
	i := macos_wifi('MacBookAir10,1\n', mac_core, mac_tree)!
	assert i.revision == 3 && i.module_name == 'RASP' && i.vendor == 'm'
	assert i.module_revision == '6.11' && i.antenna == 'X3' && i.board == 'apple,shikoku'
	assert i.files[0] == 'C-4378__s-B1/shikoku.trx'
	b3 := macos_wifi('MacBookAir10,1', mac_core.replace('s=B1', 's=B3').replace('s-B1', 's-B3'), mac_tree)!
	assert b3.revision == 5
	work := os.join_path(os.temp_dir(), 'vinix-macos-wifi-test-${os.getpid()}')
	os.mkdir(work)!
	defer { os.rmdir_all(work) or {} }
	// Raw Apple firmware is accepted without manufacturing a RAMS header.
	os.write_file_array(work + '/raw', []u8{len: 128, init: 0xfa})!
	os.write_file(work + '/nvram', 'boardrev=0x1600\n')!
	os.write_file(work + '/blob', 'blob')!
	package_macos(PackageOptions{ firmware: work + '/raw', nvram: work + '/nvram', clm: work + '/blob', txcap: work + '/blob', output: work + '/bundle' }, i)!
	manifest := os.read_bytes(work + '/bundle/manifest.bin')!
	assert manifest.len == 128 && manifest[0] == 3
	for offset, value in {
		8:  'RASP'
		24: 'm'
		40: '6.11'
		56: 'X3'
		72: 'apple,shikoku'
	} {
		assert manifest[offset..offset + value.len].bytestr() == value
		assert manifest[offset + value.len] == 0
	}
	assert manifest[104..].all(it == 0)
	assert os.read_bytes(work + '/bundle/firmware.bin')! == os.read_bytes(work + '/raw')!
	assert os.read_file(work + '/bundle/provenance.json')!.contains('macOS:/usr/share/firmware/wifi/C-4378__s-B1/shikoku.trx')
}

fn test_reject_ambiguous_or_mismatched_macos_selection() {
	for core in [mac_core.replace('= Yes', '= No'), mac_core.replace('= 4378', '= 4387'),
		mac_core.replace('s=B1', 's=C0'), mac_core.replace('M=RASP', 'M=RASP M=OTHER'),
		mac_core.replace('/shikoku.trx', '/../shikoku.trx'), mac_core.replace('s-B1/', 's-B3/'),
		mac_core.replace('shikoku-X3.clmb', 'shikoku-X2.clmb'),
		mac_core.replace('m-6.11.txt', 'm-6.10.txt'), mac_core + '\n "ChipSet" = 4378',
		mac_core.replace('({', '({{')] {
		macos_wifi('MacBookAir10,1', core, mac_tree) or { continue }
		assert false, 'Accepted mismatched macOS properties'
	}
	for tree in [mac_tree.replace('shikoku', 'honshu'),
		mac_tree.replace('5833000000000000', '5833583358335833'), mac_tree.replace('5833', '0020'),
		mac_tree + '\n "module-instance" = <"shikoku">'] {
		macos_wifi('MacBookAir10,1', mac_core, tree) or { continue }
		assert false, 'Accepted invalid antenna/board data'
	}
	macos_wifi('MacBookPro17,1', mac_core, mac_tree) or { return }
	assert false, 'Accepted another model'
}
