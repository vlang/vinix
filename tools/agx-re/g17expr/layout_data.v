module g17expr

import traceanalysis as j

// Literal producer proofs and record metadata, independent of recovery state.
fn layout_sequence(label string) []u32 {
	return match label {
		'root platform-data copy' {
			[u32(0xf9414e68), u32(0x52952917), u32(0x72a00037), u32(0x8b170108), u32(0xf9400108),
				u32(0x3cc18100), u32(0x3cc28101), u32(0x3cc38102), u32(0xad020a81), u32(0x3d800e80),
				u32(0x3cc48100), u32(0x3cc58101), u32(0x3cc68102), u32(0xf9403d08), u32(0xf9004a88),
				u32(0xad038a81), u32(0x3d801a80)]
		}
		'conditional platform shared-address source' {
			[u32(0xf9414e68), u32(0x529eea89), u32(0x8b090109), u32(0xb9400129)]
		}
		'conditional platform shared-address pointer' {
			[u32(0x91404d08), u32(0x911da108), u32(0xf9400101)]
		}
		'primary shared platform service pair' {
			[u32(0xf9454e75), u32(0x91404408), u32(0x91158108), u32(0xf9400108)]
		}
		'primary shared second platform service pair' {
			[u32(0x91404408), u32(0x9115a108), u32(0xf9400108)]
		}
		'secondary shared platform mirrors' {
			[u32(0xf945e669), u32(0xf9416eaa), u32(0xf9016d2a), u32(0xf9017528), u32(0xf9017d3f)]
		}
		'role-specific shared platform scalars' {
			[u32(0x91403d09), u32(0xb947c12a), u32(0xf945e66b), u32(0xb903016a), u32(0xb9483529),
				u32(0xb90306a9)]
		}
		'primary shared calibration copy' {
			[u32(0xf9454e69), u32(0x9111e529), u32(0x3dfde500), u32(0x3d800120)]
		}
		'secondary shared calibration copy' {
			[u32(0xf9414e68), u32(0xf945e669), u32(0x9111e529), u32(0x3dfde500), u32(0x3d800120)]
		}
		'primary shared state initialization' {
			[u32(0x52801fe8), u32(0x390f82a8), u32(0x910f86a8), u32(0x6f00e400), u32(0xad000100),
				u32(0xad010100), u32(0xad020100), u32(0xad030100), u32(0x3d802100)]
		}
		'color-matrix copy loop' {
			[u32(0x5280040a), u32(0xf940010b), u32(0xf9001d2b), u32(0xf941810b), u32(0xf9019d2b),
				u32(0xf940050b), u32(0xf900212b), u32(0xf941850b), u32(0xf901a12b), u32(0xf940090b),
				u32(0xf900252b), u32(0xf941890b), u32(0xf901a52b), u32(0x91006108), u32(0x91006129),
				u32(0xf100054a), u32(0x54fffe21)]
		}
		'I/O-mapping copy loop' {
			[u32(0xd2800008), u32(0xd280000a), u32(0xf9415e69), u32(0xf9129520), u32(0xf9414e60),
				u32(0x8b08000b), u32(0xb949896c), u32(0xb947856d), u32(0x1b0c7dad), u32(0x8b0a012e),
				u32(0xb90651cd), u32(0xf943c56d), u32(0xf90321cd), u32(0xf944c96d), u32(0xf9032dcd),
				u32(0xb90655cc), u32(0xb947816b), u32(0x121f016b), u32(0xb90661cb), u32(0xf90325df),
				u32(0x9100a14a), u32(0x9110e108), u32(0xf121215f), u32(0x54fffdc1)]
		}
		'primary and SRAM frequency-table conversion' {
			[u32(0xf9415e68), u32(0xb90fc509), u32(0xf9414e69), u32(0x91406d29), u32(0xb943192b),
				u32(0x529bd06a), u32(0x72a8636a), u32(0x9baa7d6b), u32(0xd372fd6b), u32(0xb90fc90b),
				u32(0xb94b612b), u32(0x9baa7d6b), u32(0xd372fd6b), u32(0xb918090b)]
		}
		'voltage-table loop setup' {
			[u32(0xf9415e6b), u32(0x5282010a), u32(0x8b0a016a), u32(0x91041108), u32(0x5283110c),
				u32(0x8b0c016b), u32(0x5280020c)]
		}
		'voltage-table row advance' {
			[u32(0xbc5c0100), u32(0xbc1c0160), u32(0x91010129), u32(0xbc404500), u32(0xbc004560),
				u32(0x9101014a), u32(0xf100058c), u32(0x54fff721)]
		}
		'linear-power table binding' {
			[u32(0xf9415e68), u32(0x52831909), u32(0x8b090101), u32(0x52800002)]
		}
		'table binding at 0x1908' { [u32(0x5283210b), 0x8b0b0134] }
		'table binding at 0x1948' { [u32(0x5283290b), 0x8b0b012b] }
		'table binding at 0x19c8' { [u32(0x52833909), 0x8b09010a] }
		else { panic(label) }
	}
}

fn layout_metadata(operation string) j.Value {
	return match operation {
		'recover_driver_root' {
			j.Value(map[string]j.Value{
				'interface_magic':                j.Value(u64(904030701134283968))
				'pointer_offsets':                j.Value([j.Value(24), j.Value(32), j.Value(168),
					j.Value(176), j.Value(184), j.Value(192)])
				'firmware_role_offset':           j.Value(40)
				'host_mapped_allocations_offset': j.Value(44)
				'bootstrap_provider_host_member': j.Value(6744)
				'bootstrap_region':               j.Value(map[string]j.Value{
					'root_offset':                               j.Value(8)
					'host_cpu_member':                           j.Value(6736)
					'host_gpu_mapping_member':                   j.Value(6744)
					'mapping_address_vtable_offset':             j.Value(344)
					'firmware_address_conversion_vtable_offset': j.Value(728)
				})
				'platform_config':                j.Value(map[string]j.Value{
					'host_platform_member':         j.Value(664)
					'host_platform_pointer_offset': j.Value(108872)
					'root_offset':                  j.Value(48)
					'bytes':                        j.Value(104)
				})
				'roles':                          j.Value([
					j.Value(map[string]j.Value{
						'role':     j.Value(0)
						'bindings': j.Value([
							j.Value(map[string]j.Value{
								'host_gpu_member': j.Value(2744)
								'root_offset':     j.Value(24)
							}),
							j.Value(map[string]j.Value{
								'host_gpu_member': j.Value(904)
								'root_offset':     j.Value(32)
							}),
							j.Value(map[string]j.Value{
								'host_gpu_member': j.Value(2768)
								'root_offset':     j.Value(168)
							}),
							j.Value(map[string]j.Value{
								'host_gpu_member': j.Value(3296)
								'root_offset':     j.Value(176)
							}),
						])
					}),
					j.Value(map[string]j.Value{
						'role':     j.Value(1)
						'bindings': j.Value([
							j.Value(map[string]j.Value{
								'host_gpu_member': j.Value(3048)
								'root_offset':     j.Value(24)
							}),
							j.Value(map[string]j.Value{
								'host_gpu_member': j.Value(904)
								'root_offset':     j.Value(32)
							}),
							j.Value(map[string]j.Value{
								'host_gpu_member': j.Value(3072)
								'root_offset':     j.Value(168)
							}),
							j.Value(map[string]j.Value{
								'host_gpu_member': j.Value(3304)
								'root_offset':     j.Value(184)
							}),
							j.Value(map[string]j.Value{
								'host_gpu_member': j.Value(920)
								'root_offset':     j.Value(192)
							}),
						])
					}),
				])
			})
		}
		'recover_firmware_shared_platform_fields' {
			j.Value(map[string]j.Value{
				'platform_host_member':    j.Value(664)
				'primary_service_sources': j.Value([
					j.Value(map[string]j.Value{
						'platform_pointer_offset':       j.Value(71008)
						'primary_shared_offsets':        j.Value([j.Value(728), j.Value(736)])
						'primary_object_member':         j.Value(104)
						'secondary_object_member':       j.Value(88)
						'mapping_address_vtable_offset': j.Value(344)
						'nullable':                      j.Value(true)
					}),
					j.Value(map[string]j.Value{
						'platform_pointer_offset':       j.Value(71016)
						'primary_shared_offsets':        j.Value([j.Value(744), j.Value(752)])
						'primary_object_member':         j.Value(104)
						'secondary_object_member':       j.Value(88)
						'mapping_address_vtable_offset': j.Value(344)
						'nullable':                      j.Value(true)
					}),
				])
				'secondary_mirrors':       j.Value([
					j.Value(map[string]j.Value{
						'primary_shared_offset':   j.Value(728)
						'secondary_shared_offset': j.Value(728)
					}),
					j.Value(map[string]j.Value{
						'primary_shared_offset':   j.Value(744)
						'secondary_shared_offset': j.Value(744)
					}),
				])
				'scalars':                 j.Value([
					j.Value(map[string]j.Value{
						'platform_offset': j.Value(63424)
						'role':            j.Value(1)
						'shared_offset':   j.Value(768)
					}),
					j.Value(map[string]j.Value{
						'platform_offset': j.Value(63540)
						'role':            j.Value(0)
						'shared_offset':   j.Value(772)
					}),
				])
				'calibration':             j.Value(map[string]j.Value{
					'platform_offset': j.Value(63376)
					'shared_offset':   j.Value(1145)
					'bytes':           j.Value(16)
					'roles':           j.Value([j.Value(0), j.Value(1)])
				})
				'primary_state':           j.Value(map[string]j.Value{
					'state_offset':  j.Value(992)
					'state_initial': j.Value(255)
					'status_offset': j.Value(993)
					'status_bytes':  j.Value(144)
				})
			})
		}
		'recover_driver_hardware_config_layout' {
			j.Value(map[string]j.Value{
				'color_matrices':     j.Value(map[string]j.Value{
					'offset':       j.Value(56)
					'records':      j.Value(64)
					'record_bytes': j.Value(24)
					'banks':        j.Value(2)
				})
				'io_mappings':        j.Value(map[string]j.Value{
					'offset':       j.Value(1600)
					'records':      j.Value(53)
					'record_bytes': j.Value(40)
				})
				'performance_states': j.Value(map[string]j.Value{
					'capacity':                          j.Value(16)
					'max_state_offset':                  j.Value(4036)
					'frequency_offset':                  j.Value(4040)
					'voltage_offset':                    j.Value(4104)
					'sram_voltage_offset':               j.Value(5128)
					'secondary_frequency_offset':        j.Value(6152)
					'primary_frequency_source_offset':   j.Value(111384)
					'secondary_frequency_source_offset': j.Value(113504)
					'frequency_conversion':              j.Value(map[string]j.Value{
						'input':       j.Value('Hz')
						'output':      j.Value('MHz')
						'multiplier':  j.Value(1125899907)
						'right_shift': j.Value(50)
					})
					'derived_table_offsets':             j.Value([j.Value(6216), j.Value(6280),
						j.Value(6344), j.Value(6408), j.Value(6472)])
				})
			})
		}
		else {
			panic(operation)
			j.Value(false)
		}
	}
}
