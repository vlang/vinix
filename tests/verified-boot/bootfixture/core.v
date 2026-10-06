// SPDX-License-Identifier: GPL-2.0-or-later
// Bootloader protocol fixture; the module response gates the handoff marker.
@[has_globals; translated]
module bootfixture

#include <boot-native-abi.h>

struct C.vvb_response {
mut:
	revision u64
	count    u64
	modules  voidptr
}

struct C.vvb_uart_word {
mut:
	value u32
}

struct Request {
mut:
	id       [4]u64
	revision u64
	response &C.vvb_response
}

@[_linker_section: '.requests']
@[cinit]
__global (
	volatile boot_base_revision = [u64(0xf9562b2d5c95a6c8), 0x6a7b384944536bdc, 2]!
)

@[_linker_section: '.requests']
@[cinit]
__global (
	volatile boot_modules = Request{
		id:       [u64(0xc7b1dd30df4c8b88), 0x0a82e883a194f07b, 0x3e7e279702be32af, 0xca1c4f3bd1280cee]!
		response: unsafe { nil }
	}
)

@[_linker_section: '.requests']
@[cinit]
__global (
	volatile boot_hhdm = Request{
		id:       [u64(0xc7b1dd30df4c8b88), 0x0a82e883a194f07b, 0x48dcf1cb8ad2b852, 0x63984e959a98244b]!
		response: unsafe { nil }
	}
)

fn put_byte(value u8) {
	$if amd64 {
		port := u16(0x3f8)
		asm volatile amd64 {
   out port, value
   ; ; a (value)
       Nd (port)
  }
	} $else {
		unsafe {
			uart := &C.vvb_uart_word(usize(boot_hhdm.response.count) + 0x09000000)
			for (uart[6].value & u32(1 << 5)) != 0 {
			}
			uart[0].value = u32(value)
		}
	}
}

@[export: 'main__kmain']
pub fn boot_entry() {
	unsafe {
		mut message := &char(c'VERIFIED-BOOT: missing module\n')
		if boot_modules.response != nil && boot_modules.response.count == 1 {
			message = &char(c'VERIFIED-BOOT: launch accepted\n')
		}
		for message[0] != 0 {
			put_byte(u8(message[0]))
			message++
		}
		for {
			$if amd64 {
				asm volatile amd64 {
     cli
     hlt
    }
			} $else {
				asm volatile arm64 { wfi }
			}
		}
	}
}
