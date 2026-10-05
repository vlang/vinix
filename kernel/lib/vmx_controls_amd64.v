// SPDX-License-Identifier: GPL-2.0-only
// Copyright (c) 2026 Alexander Medvednikov
module lib

$if vmx_test ? {
	// Host fixture adapts only the privileged instruction, including its flags.
	fn C.vinix_vmx_test_instruction(operation u32, operand u64, value u64, result &u64) u8
}

fn vmx_on_status(physical_address u64) u8 {
	$if vmx_test ? {
		return C.vinix_vmx_test_instruction(0, physical_address, 0, unsafe { nil })
	} $else {
		mut failed := u8(0)
		asm volatile amd64 {
			vmxon address
			setna failed
			; =rm (failed)
			; m (physical_address) as address
			; cc
			  memory
		}
		return failed
	}
}

fn vmx_clear_status(physical_address u64) u8 {
	$if vmx_test ? {
		return C.vinix_vmx_test_instruction(2, physical_address, 0, unsafe { nil })
	} $else {
		mut failed := u8(0)
		asm volatile amd64 {
			vmclear address
			setna failed
			; =rm (failed)
			; m (physical_address) as address
			; cc
			  memory
		}
		return failed
	}
}

fn vmx_load_status(physical_address u64) u8 {
	$if vmx_test ? {
		return C.vinix_vmx_test_instruction(3, physical_address, 0, unsafe { nil })
	} $else {
		mut failed := u8(0)
		asm volatile amd64 {
			vmptrld address
			setna failed
			; =rm (failed)
			; m (physical_address) as address
			; cc
			  memory
		}
		return failed
	}
}

fn vmx_off_status() u8 {
	$if vmx_test ? {
		return C.vinix_vmx_test_instruction(1, 0, 0, unsafe { nil })
	} $else {
		mut failed := u8(0)
		asm volatile amd64 {
			vmxoff
			setna failed
			; =rm (failed)
			; ; cc
			    memory
		}
		return failed
	}
}

fn vmx_write_status(field u64, value u64) u8 {
	$if vmx_test ? {
		return C.vinix_vmx_test_instruction(4, field, value, unsafe { nil })
	} $else {
		mut failed := u8(0)
		asm volatile amd64 {
			vmwrite field, value
			setna failed
			; =rm (failed)
			; r (value)
			  r (field)
			; cc
			  memory
		}
		return failed
	}
}

fn vmx_read_status(field u64, value &u64) u8 {
	$if vmx_test ? {
		return C.vinix_vmx_test_instruction(5, field, 0, value)
	} $else {
		mut result := u64(0)
		mut failed := u8(0)
		asm volatile amd64 {
			vmread result, field
			setna failed
			; =rm (failed)
			  =r (result)
			; r (field)
			; cc
			  memory
		}
		if failed == 0 {
			unsafe { *value = result }
		}
		return failed
	}
}
