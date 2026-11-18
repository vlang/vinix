// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module cpu

__global snapshot_barriers = u32(0)

pub fn wfe() {}
pub fn dmb_ishld() { snapshot_barriers++ }
pub fn barriers() u32 { return snapshot_barriers }
