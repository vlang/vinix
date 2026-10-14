// SPDX-License-Identifier: GPL-2.0-or-later
module main

// ARM64 iOS ObjCBool wraps Swift Bool, unlike the signed-byte Catalyst
// representation. These free scalar entries receive and return bit 0 in x0;
// other register bits are not part of the Boolean value. They borrow no owner
// and require no running Objective-C runtime or Swift metadata allocation.
fn swift_bool_to_objc_bool(value u64) u64 { return value & 1 }
fn swift_objc_bool_to_bool(value u64) u64 { return value & 1 }

fn swift_objc_bool_symbol(symbol string) ?u64 {
	if symbol in ['_$s10ObjectiveC8ObjCBoolVMa', '_$s10ObjectiveC8ObjCBoolVMn', '_$s10ObjectiveC8ObjCBoolVN']! {
		base := swift_objc_bool_arena_checked() or { return none }
		return match symbol {
			'_$s10ObjectiveC8ObjCBoolVMa' { base }
			'_$s10ObjectiveC8ObjCBoolVMn' { base + u64(C.getpagesize()) + 160 }
			else { base + u64(C.getpagesize()) + 16 }
		}
	}
	return match symbol {
		'_$s10ObjectiveC22_convertBoolToObjCBoolyAA0eF0VSbF' {
			u64(unsafe { voidptr(swift_bool_to_objc_bool) })
		}
		'_$s10ObjectiveC22_convertObjCBoolToBoolySbAA0cD0VF' {
			u64(unsafe { voidptr(swift_objc_bool_to_bool) })
		}
		else { none }
	}
}
