module t6050power

import traceanalysis as j

fn controller_uuid_image(identity string) []u8 {
	mut image := encoded_words([u32(0xfeedfacf), 0x100000c, 0, 5, 1, 24, 0, 0, 0x1b, 24])
	image << j.bytes_fromhex(identity.replace('-', '').to_lower()) or { panic(err) }
	return image
}

fn malformed_secondary_request() map[string]j.Value {
	return {
		'rtbuddy_image': j.Value(map[string]j.Value{
			'$bytes': j.Value('x')
		})
	}
}

fn test_controller_secondary_transport_is_unused_for_single_image_operations() {
	for spec in [['recover_apple_pmgr', 'ApplePMGR'], ['recover_apple_t6050_pmgr', 'AppleT6050PMGR'],
		['recover_apple_a7iop', 'AppleA7IOP'], ['recover_iodart_family', 'IODARTFamily'],
		['recover_apple_t8110_dart', 'AppleT8110DART'], ['recover_t8110_kernel', 'T6050 kernel'],
		['recover_apple_ascwrap_v6', 'AppleASCWrapV6']] {
		query_controller_image(controller_uuid_image('00000000-0000-0000-0000-000000000000'), spec[0], malformed_secondary_request()) or {
			assert err.msg() == 'unsupported ${spec[1]} UUID 00000000-0000-0000-0000-000000000000'
			continue
		}
		assert false
	}
}

fn test_paired_controller_primary_identity_precedes_secondary_decoding() {
	for spec in [['recover_apple_pmp', 'ApplePMP'], ['recover_apple_pmp_firmware', 'ApplePMPFirmware']] {
		query_controller_image(controller_uuid_image('00000000-0000-0000-0000-000000000000'), spec[0], malformed_secondary_request()) or {
			assert err.msg() == 'unsupported ${spec[1]} UUID 00000000-0000-0000-0000-000000000000'
			continue
		}
		assert false
	}
}

fn test_paired_controllers_retain_their_distinct_symbol_and_identity_order() {
	mut primary_failed := false
	query_controller_image(controller_uuid_image(apple_pmp_uuid), 'recover_apple_pmp', malformed_secondary_request()) or {
		assert err.msg() == 'Mach-O has no symbol table'
		primary_failed = true
	}
	assert primary_failed
	query_controller_image(controller_uuid_image(apple_pmp_firmware_uuid), 'recover_apple_pmp_firmware', malformed_secondary_request()) or {
		assert err.msg() == 'non-hexadecimal number found in fromhex() arg at position 0'
		return
	}
	assert false
}
