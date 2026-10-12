// SPDX-License-Identifier: GPL-2.0-only
module lib

@[export: 'vinix_vmx_invept']
fn vmx_invept(_kind u64, _eptp u64) i32 { return -1 }
