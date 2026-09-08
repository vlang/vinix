module main

import ui2

fn sample_list_json() string {
	return '{"WholeDisks":["disk0","disk4","disk5"],"AllDisksAndPartitions":[{"DeviceIdentifier":"disk0","Size":500000000000,"Partitions":[{"Content":"Apple_APFS_ISC"}]},{"DeviceIdentifier":"disk4","Size":128000000000,"Partitions":[]},{"DeviceIdentifier":"disk5","Size":64000000000,"Partitions":[]}]}'
}

fn test_decode_disk_listing_keeps_startup_and_bootable_usb_only() {
	info := {
		'disk0': '{"DeviceIdentifier":"disk0","MediaName":"APPLE SSD","BusProtocol":"Apple Fabric","DeviceTreePath":"IODeviceTree:/arm-io/ans","VirtualOrPhysical":"Unknown","Size":500000000000,"Internal":true,"Writable":true,"WholeDisk":true}'
		'disk4': '{"DeviceIdentifier":"disk4","MediaName":"USB SSD","BusProtocol":"USB","DeviceTreePath":"IODeviceTree:/arm-io/usb-drd0/usb","VirtualOrPhysical":"Physical","Size":128000000000,"Internal":false,"Writable":true,"WholeDisk":true}'
		'disk5': '{"DeviceIdentifier":"disk5","MediaName":"SD Card","BusProtocol":"Secure Digital","DeviceTreePath":"IODeviceTree:/arm-io/sdart","VirtualOrPhysical":"Physical","Size":64000000000,"Internal":false,"Writable":true,"WholeDisk":true}'
	}
	disks := decode_disk_listing(sample_list_json(), info) or { panic(err) }
	assert disks.len == 2
	assert disks[0].id == 'disk0'
	assert disks[0].is_system
	assert disks[1].id == 'disk4'
	assert !disks[1].is_system
}

fn test_decode_disk_listing_requires_isc_startup_marker() {
	decode_disk_listing('{"WholeDisks":["disk0"],"AllDisksAndPartitions":[]}', {}) or {
		assert err.msg().contains('startup disk')
		return
	}
	assert false
}

fn test_allocation_validation_preserves_macos_headroom() {
	internal := InstallDisk{
		id: 'disk0'
		size: 100 * decimal_gb
		is_system: true
	}
	assert allocation_gb('32', internal)! == 32
	allocation_gb('61', internal) or {
		assert err.msg().contains('40 GB')
		return
	}
	assert false
}

fn test_allocation_validation_rejects_small_and_non_numeric_values() {
	external := InstallDisk{
		id: 'disk4'
		size: 64 * decimal_gb
	}
	for invalid in ['15', '32.5', 'lots'] {
		if _ := allocation_gb(invalid, external) {
			assert false
		}
	}
}

fn test_shell_quote_handles_spaces_and_apostrophes() {
	assert shell_quote("/Volumes/Alex's Disk") == '\'/Volumes/Alex\'"\'"\'s Disk\''
}

fn test_installer_screen_has_valid_ui2_identity() {
	mut state := unsafe { installer_state }
	state.disks = [InstallDisk{
		id: 'disk0'
		name: 'APPLE SSD'
		size: 500 * decimal_gb
		internal: true
		is_system: true
	}]
	state.selected = 0
	state.space_text = '32'
	state.acknowledged = true
	state.supported = true
	state.payload_dir = '/test/payload'
	state.status = 'Ready.'
	state.status_error = false
	root := build_screen()
	ui2.validate_element_tree(root) or { panic(err) }
	assert install_ready(state)
}
