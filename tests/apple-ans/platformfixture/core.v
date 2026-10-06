// SPDX-License-Identifier: GPL-2.0-or-later
// Injected hardware callbacks own all accesses; direct MMIO is forbidden.
@[translated]
module platformfixture
#include <assert.h>
fn C.assert(bool)
@[export: 'vinix_mmio_read32']
pub fn read32(address voidptr) u32 { C.assert(usize(c'unexpected MMIO')==0); return 0 }
@[export: 'vinix_mmio_read64']
pub fn read64(address voidptr) u64 { C.assert(usize(c'unexpected MMIO')==0); return 0 }
@[export: 'vinix_mmio_write32']
pub fn write32(address voidptr, value u32) { C.assert(usize(c'unexpected MMIO')==0) }
@[export: 'vinix_mmio_write64']
pub fn write64(address voidptr, value u64) { C.assert(usize(c'unexpected MMIO')==0) }
@[export: 'vinix_account_disk_transfer']
pub fn account(bytes u64, write i32) {}
