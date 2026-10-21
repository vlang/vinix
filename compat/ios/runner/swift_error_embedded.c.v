// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Error's default implementation returns Optional<AnyObject>.none in x0.
// The installed Swift entry is MOV x0,#0; RET: it does not read indirect
// Self (x20), metadata (x0), witnesses (x1), or an indirect result (x8).
// Concrete Error witnesses may override it; this entry neither dispatches
// those witnesses nor bridges/retains/releases an NSError or Swift error box.
fn swift_error_embedded() u64 { return 0 }
