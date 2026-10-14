// SPDX-License-Identifier: GPL-2.0-or-later
module sched

// Keep QUERY honest until an x86 instruction-pipeline rendezvous is supplied.
pub fn sync_core_supported() bool { return false }

pub fn synchronize_core() {}
