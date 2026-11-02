// SPDX-License-Identifier: GPL-2.0-or-later
module mapsaccountstage

import os

type InventoryBatchAudit = fn (map[string]string) !

// Each public image contract supplies its exact count. The private sixty-five
// case exercises the boundary immediately above the unchanged helper limit.
fn inventory_batch_plan(pins map[string]string, expected int) ![]map[string]string {
	if expected !in [65, 70, 73, 76, 79, 82, 84, 86, 89, 91, 94, 96, 98, 100] || pins.len != expected {
		return error('exact bounded inventory batch count required')
	}
	mut roots := pins.keys()
	roots.sort()
	mut first := map[string]string{}
	mut second := map[string]string{}
	for index, root in roots {
		if !os.is_abs_path(root) || os.norm_path(root) != root || root.contains_any('\\\x00\r\n\t')
			|| !valid_pin(pins[root]!) { return error('canonical absolute inventory selector and exact pin required') }
		if index < 64 {
			first[root.clone()] = pins[root]!.clone()
		} else {
			second[root.clone()] = pins[root]!.clone()
		}
	}
	if first.len != 64 || second.len != expected - 64 { return error('exact inventory batch partition required') }
	mut combined := map[string]string{}
	for batch in [first, second] {
		for root, pin in batch {
			if root in combined { return error('inventory batches overlap') }
			combined[root] = pin
		}
	}
	if combined != pins { return error('complete inventory batch union differs') }
	return [first, second]
}

fn audit_inventory_batches_with(pins map[string]string, expected int, audit InventoryBatchAudit) ! {
	batches := inventory_batch_plan(pins, expected)!
	// Each call joins every worker it started before returning. Do not spawn
	// these calls: the second batch starts only after the first succeeds.
	audit(batches[0])!
	audit(batches[1])!
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
