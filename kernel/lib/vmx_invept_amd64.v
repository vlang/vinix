// SPDX-License-Identifier: GPL-2.0-only
module lib

@[export: 'vinix_vmx_invept']
fn vmx_invept(kind u64, eptp u64) i32 {
	descriptor := [eptp, u64(0)]!
	mut failed := u8(0)
	asm volatile amd64 {
		invept extent, operand
		setna failed
		; =rm (failed)
		; r (kind) as extent
		  m (descriptor) as operand
		; cc
		  memory
	}
	return if failed != 0 { -1 } else { 0 }
}
