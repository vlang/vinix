// SPDX-License-Identifier: GPL-2.0-or-later
module mapsaccountstage

import os

type InventoryBatchAudit = fn (map[string]string) !

// Each public image contract supplies its exact count. The private sixty-five
// case exercises the boundary immediately above the unchanged helper limit.
fn inventory_batch_plan(pins map[string]string, expected int) ![]map[string]string {
	if expected !in [65, 70, 73, 76, 79, 82, 84, 86, 89, 91, 94, 96, 98, 100, 103, 106, 108, 110, 112, 114, 116, 119, 121, 123, 125, 127, 129, 131, 134, 137, 140, 142, 145] || pins.len != expected {
		return error('exact bounded inventory batch count required')
	}
	mut roots := pins.keys()
	roots.sort()
	mut first := map[string]string{}
	mut second := map[string]string{}
	mut third := map[string]string{}
	for index, root in roots {
		if !os.is_abs_path(root) || os.norm_path(root) != root || root.contains_any('\\\x00\r\n\t')
			|| !valid_pin(pins[root]!) { return error('canonical absolute inventory selector and exact pin required') }
		if index < 64 {
			first[root.clone()] = pins[root]!.clone()
		} else if index < 128 {
			second[root.clone()] = pins[root]!.clone()
		} else {
			third[root.clone()] = pins[root]!.clone()
		}
	}
	if first.len != 64 || second.len != (if expected in [129, 131, 134, 137, 140, 142, 145] { 64 } else { expected - 64 })
		|| third.len != (if expected in [129, 131, 134, 137, 140, 142, 145] { expected - 128 } else { 0 }) { return error('exact inventory batch partition required') }
	batches := if expected in [129, 131, 134, 137, 140, 142, 145] { [first, second, third] } else { [first, second] }
	mut combined := map[string]string{}
	for batch in batches {
		for root, pin in batch {
			if root in combined { return error('inventory batches overlap') }
			combined[root] = pin
		}
	}
	if combined != pins { return error('complete inventory batch union differs') }
	return batches
}

fn audit_inventory_batches_with(pins map[string]string, expected int, audit InventoryBatchAudit) ! {
	batches := inventory_batch_plan(pins, expected)!
	// Each call joins every worker it started before returning. Do not spawn
	// these calls: every later batch starts only after its predecessor succeeds.
	for batch in batches { audit(batch)! }
}

// Both image audit phases call this afresh. Every root and complete inventory
// is read again; no inventory or successful result survives between calls.
pub fn audit_seventy_inventories(pins map[string]string) ! {
	audit_inventory_batches_with(pins, 70, audit_inventories_parallel)!
}

// The bitmap-drawable successor inherits all seventy-three sealed roots.
pub fn audit_seventy_three_inventories(pins map[string]string) ! {
	audit_inventory_batches_with(pins, 73, audit_inventories_parallel)!
}

// The Window animation successor inherits all seventy-six sealed roots.
pub fn audit_seventy_six_inventories(pins map[string]string) ! {
	audit_inventory_batches_with(pins, 76, audit_inventories_parallel)!
}

// The Layout alignment successor inherits all seventy-nine sealed roots.
pub fn audit_seventy_nine_inventories(pins map[string]string) ! {
	audit_inventory_batches_with(pins, 79, audit_inventories_parallel)!
}

// The UserManager restrictions successor inherits all eighty-two sealed roots.
pub fn audit_eighty_two_inventories(pins map[string]string) ! {
	audit_inventory_batches_with(pins, 82, audit_inventories_parallel)!
}

// The Bundle/CrossProfileApps successor inherits all eighty-four sealed roots.
pub fn audit_eighty_four_inventories(pins map[string]string) ! {
	audit_inventory_batches_with(pins, 84, audit_inventories_parallel)!
}

// The Resources float successor inherits all eighty-six sealed roots.
pub fn audit_eighty_six_inventories(pins map[string]string) ! {
	audit_inventory_batches_with(pins, 86, audit_inventories_parallel)!
}

// The PaintDrawable successor inherits all eighty-nine sealed roots.
pub fn audit_eighty_nine_inventories(pins map[string]string) ! {
	audit_inventory_batches_with(pins, 89, audit_inventories_parallel)!
}

// The Dialog theme successor inherits all ninety-one sealed roots.
pub fn audit_ninety_one_inventories(pins map[string]string) ! {
	audit_inventory_batches_with(pins, 91, audit_inventories_parallel)!
}

// The Intent extras successor inherits all ninety-four sealed roots.
pub fn audit_ninety_four_inventories(pins map[string]string) ! {
	audit_inventory_batches_with(pins, 94, audit_inventories_parallel)!
}

// The resource-lock successor inherits all ninety-six sealed roots.
pub fn audit_ninety_six_inventories(pins map[string]string) ! {
	audit_inventory_batches_with(pins, 96, audit_inventories_parallel)!
}

// The PendingIntent successor inherits all ninety-eight sealed roots.
pub fn audit_ninety_eight_inventories(pins map[string]string) ! {
	audit_inventory_batches_with(pins, 98, audit_inventories_parallel)!
}

// The stable-display successor inherits all one hundred sealed roots.
pub fn audit_one_hundred_inventories(pins map[string]string) ! {
	audit_inventory_batches_with(pins, 100, audit_inventories_parallel)!
}

// The asset-locales successor inherits all one hundred three sealed roots.
pub fn audit_one_hundred_three_inventories(pins map[string]string) ! {
	audit_inventory_batches_with(pins, 103, audit_inventories_parallel)!
}

// The unmanaged-queries successor inherits all one hundred six sealed roots.
pub fn audit_one_hundred_six_inventories(pins map[string]string) ! {
	audit_inventory_batches_with(pins, 106, audit_inventories_parallel)!
}

// The stats-unavailable successor inherits all one hundred eight sealed roots.
pub fn audit_one_hundred_eight_inventories(pins map[string]string) ! {
	audit_inventory_batches_with(pins, 108, audit_inventories_parallel)!
}

// The subscription-service successor inherits all one hundred ten sealed roots.
pub fn audit_one_hundred_ten_inventories(pins map[string]string) ! {
	audit_inventory_batches_with(pins, 110, audit_inventories_parallel)!
}

// The autofill-service successor inherits all one hundred twelve sealed roots.
pub fn audit_one_hundred_twelve_inventories(pins map[string]string) ! {
	audit_inventory_batches_with(pins, 112, audit_inventories_parallel)!
}

// The keyguard-policy successor inherits all one hundred fourteen sealed roots.
pub fn audit_one_hundred_fourteen_inventories(pins map[string]string) ! {
	audit_inventory_batches_with(pins, 114, audit_inventories_parallel)!
}

// The broadcast-permission successor inherits all one hundred sixteen sealed roots.
pub fn audit_one_hundred_sixteen_inventories(pins map[string]string) ! {
	audit_inventory_batches_with(pins, 116, audit_inventories_parallel)!
}

// The secure-settings successor inherits all one hundred nineteen sealed roots.
pub fn audit_one_hundred_nineteen_inventories(pins map[string]string) ! {
	audit_inventory_batches_with(pins, 119, audit_inventories_parallel)!
}

// The usage-inactive successor inherits all one hundred twenty-one sealed roots.
pub fn audit_one_hundred_twenty_one_inventories(pins map[string]string) ! {
	audit_inventory_batches_with(pins, 121, audit_inventories_parallel)!
}

// The messenger-binder successor inherits all one hundred twenty-three sealed roots.
pub fn audit_one_hundred_twenty_three_inventories(pins map[string]string) ! {
	audit_inventory_batches_with(pins, 123, audit_inventories_parallel)!
}

// The component-parcel successor inherits all one hundred twenty-five sealed roots.
pub fn audit_one_hundred_twenty_five_inventories(pins map[string]string) ! {
	audit_inventory_batches_with(pins, 125, audit_inventories_parallel)!
}

// The EventLog successor inherits all one hundred twenty-seven sealed roots.
pub fn audit_one_hundred_twenty_seven_inventories(pins map[string]string) ! {
	audit_inventory_batches_with(pins, 127, audit_inventories_parallel)!
}

// The Build ABI successor crosses the second helper boundary: 64 + 64 + 1.
pub fn audit_one_hundred_twenty_nine_inventories(pins map[string]string) ! {
	audit_inventory_batches_with(pins, 129, audit_inventories_parallel)!
}

// The WebView package successor retains 64 + 64 + 3 complete inventories.
pub fn audit_one_hundred_thirty_one_inventories(pins map[string]string) ! {
	audit_inventory_batches_with(pins, 131, audit_inventories_parallel)!
}

// The framework boot successor retains 64 + 64 + 6 complete inventories.
pub fn audit_one_hundred_thirty_four_inventories(pins map[string]string) ! {
	audit_inventory_batches_with(pins, 134, audit_inventories_parallel)!
}

// The framework JNI-load successor retains 64 + 64 + 9 complete inventories.
pub fn audit_one_hundred_thirty_seven_inventories(pins map[string]string) ! {
	audit_inventory_batches_with(pins, 137, audit_inventories_parallel)!
}

// The TrafficStats successor retains 64 + 64 + 12 complete inventories.
pub fn audit_one_hundred_forty_inventories(pins map[string]string) ! {
	audit_inventory_batches_with(pins, 140, audit_inventories_parallel)!
}

// The process-package successor retains 64 + 64 + 14 complete inventories.
pub fn audit_one_hundred_forty_two_inventories(pins map[string]string) ! {
	audit_inventory_batches_with(pins, 142, audit_inventories_parallel)!
}

// The Global string successor retains 64 + 64 + 17 complete inventories.
pub fn audit_one_hundred_forty_five_inventories(pins map[string]string) ! {
	audit_inventory_batches_with(pins, 145, audit_inventories_parallel)!
}
