// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

// Transfer each existing discovery pin directly to the shared owner. A later
// failed participant leaves all acquired pins for the caller's normal cleanup.
// Physical ID and mode stay bound to discovery through every shared recheck.
@[direct_array_access]
fn discover_data_pins(set &PlanSet, mut pins DataPins) bool {
	if pins.count != 0 || !data_ranges_valid(set) { return false }
	pins.automatic = true
	for disk in 0 .. set.count {
		mut name := [256]char{}; mut status := Status{}
		fd := discover_disk_key(unsafe { &set.plans[disk].key }, c'/dev', false, &name[0], mut status)
		if fd < 0 { return false }
		pins.descriptors[disk] = fd; pins.disks[disk] = u32(disk); pins.ids[disk] = status.disk_id
		pins.readonly[disk] = status.flags & 1; pins.count++
		for earlier in 0 .. disk {
			if pins.ids[earlier] == status.disk_id { plan_error(c'checksum discovery participants repeat a physical disk'); return false }
		}
	}
	return true
}
