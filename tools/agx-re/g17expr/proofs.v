module g17expr

import traceanalysis as j

pub const append_provider = '__ZN20AGXKRCEBufferEncoder6appendEjhy'

pub fn producer_names() map[string]string {
	return {
		'3D':       '__ZN33AGX·PI_300·X·A0·3DChannelSKSM25generateRegisterListFor3DEP20AGFIChannelCommand3DP22AGX3DCommandDescriptor'
		'FastBlit': '__ZN33AGX·PI_300·X·A0·3DChannelSKSM31generateRegisterListForFastBlitEP26AGFIChannelCommandFastBlitP22AGX3DCommandDescriptor'
		'CL':       '__ZN33AGX·PI_300·X·A0·CLChannelSKSM20generateRegisterListEP20AGFIChannelCommandCLP22AGXCLCommandDescriptor'
		'TA':       '__ZN33AGX·PI_300·X·A0·TAChannelSKSM20generateRegisterListEP20AGFIChannelCommandTAP22AGXTACommandDescriptor'
	}
}

fn proof_words(label string) map[int]u32 {
	return match label {
		'G17 register-entry append' {
			{
				0x10: u32(0xaa0303e4)
				0x14: u32(0xaa0203e3)
				0x18: u32(0xaa0103e2)
				0x3c: u32(0xf2fdc450)
				0x40: u32(0xd73f0950)
				0x48: u32(0x794e1509)
				0x4c: u32(0x11003129)
				0x50: u32(0x790e1509)
				0x54: u32(0x794e1109)
				0x58: u32(0x11000529)
				0x5c: u32(0x790e1109)
			}
		}
		'G17 3D inline register records' {
			{
				0x100: u32(0xa18014a)
				0x104: u32(0x5282e72b)
				0x108: u32(0x2a0b014a)
				0x10c: u32(0xb900a12a)
				0x114: u32(0x5280002b)
				0x178: u32(0xa180129)
				0x17c: u32(0x5282fc2b)
				0x180: u32(0x2a0b0129)
				0x184: u32(0xb9000109)
				0x188: u32(0xf800410a)
				0x194: u32(0x11003129)
			}
		}
		'G17 TA inline register records' {
			{
				0x88: u32(0xa0a0129)
				0x8c: u32(0x5282fc2b)
				0x90: u32(0x2a0b0129)
				0x94: u32(0xb90062a9)
				0x98: u32(0x52800029)
				0x9c: u32(0xf80642a9)
				0xc8: u32(0xa0a0129)
				0xcc: u32(0x5282fe2a)
				0xd0: u32(0x2a0a0129)
				0xd4: u32(0xb9000109)
				0xdc: u32(0xf8004109)
				0xf4: u32(0x11003129)
			}
		}
		'G17 FastBlit inline register records' {
			{
				0x6c:  u32(0x120e4d29)
				0x70:  u32(0x5282e72a)
				0x74:  u32(0x2a0a0129)
				0x78:  u32(0xb9000109)
				0x80:  u32(0xf8004109)
				0x114: u32(0x5280f21c)
				0x118: u32(0x72a0003c)
				0x124: u32(0x120e4129)
				0x128: u32(0xb1c0129)
				0x12c: u32(0x511e1d29)
				0x130: u32(0xb9000d09)
				0x134: u32(0xf9000916)
				0x140: u32(0x11003129)
			}
		}
		'G17 CL inline register records' {
			{
				0x3c:   u32(0xf9400815)
				0x90:   u32(0xa0b0129)
				0x94:   u32(0x5282fc2a)
				0x98:   u32(0x2a0a0129)
				0x9c:   u32(0xb9004289)
				0xa4:   u32(0xf8044289)
				0xd8:   u32(0xa0b0129)
				0xdc:   u32(0x5282fe2a)
				0xe0:   u32(0x2a0a0129)
				0xe4:   u32(0xb9000109)
				0xec:   u32(0xf8004109)
				0xb8:   u32(0x91404eaa)
				0xbc:   u32(0x91080156)
				0x1330: u32(0xf9420a69)
				0x1334: u32(0xa95b22ea)
				0x1338: u32(0xb944b2ab)
				0x133c: u32(0x9276810c)
				0x1340: u32(0x528000a8)
				0x1344: u32(0xaa08018d)
				0x134c: u32(0xf90001cd)
				0x1360: u32(0x8b0b0569)
				0x1364: u32(0xd375d137)
				0x1368: u32(0x8b0c02e9)
				0x137c: u32(0xa0b014a)
				0x1380: u32(0xb0a02ca)
				0x1384: u32(0x1100254a)
				0x1388: u32(0xb907628a)
				0x139c: u32(0xa0b014a)
				0x13a0: u32(0xb0a02ca)
				0x13a4: u32(0x1100054a)
				0x13a8: u32(0xb9076e8a)
				0x13ac: u32(0xf903ba89)
				0x13b8: u32(0x1100314a)
			}
		}
		else { panic(label) }
	}
}

fn static_records() j.Value {
	return j.Value(map[string]j.Value{
		'3D':       j.Value([
			j.Value(map[string]j.Value{
				'producer_offset': j.Value(260)
				'selector':        j.Value(5944)
				'mode':            j.Value(1)
				'value':           j.Value(1)
			}),
			j.Value(map[string]j.Value{
				'producer_offset': j.Value(380)
				'selector':        j.Value(6112)
				'mode':            j.Value(1)
				'value':           j.Value(1)
			}),
		])
		'TA':       j.Value([
			j.Value(map[string]j.Value{
				'producer_offset': j.Value(140)
				'selector':        j.Value(6112)
				'mode':            j.Value(1)
				'value':           j.Value(1)
			}),
			j.Value(map[string]j.Value{
				'producer_offset': j.Value(204)
				'selector':        j.Value(6128)
				'mode':            j.Value(1)
				'value':           j.Value(1)
			}),
		])
		'FastBlit': j.Value([
			j.Value(map[string]j.Value{
				'producer_offset': j.Value(112)
				'selector':        j.Value(5944)
				'mode':            j.Value(1)
				'value':           j.Value(1)
			}),
			j.Value(map[string]j.Value{
				'producer_offset': j.Value(296)
				'selector':        j.Value(65544)
				'mode':            j.Value(1)
				'value_source':    j.Value('computed_blit_control')
			}),
		])
		'CL':       j.Value([
			j.Value(map[string]j.Value{
				'producer_offset': j.Value(148)
				'selector':        j.Value(6112)
				'mode':            j.Value(1)
				'value':           j.Value(1)
			}),
			j.Value(map[string]j.Value{
				'producer_offset': j.Value(220)
				'selector':        j.Value(6128)
				'mode':            j.Value(1)
				'value':           j.Value(1)
			}),
		])
	})
}

fn dynamic_records() j.Value {
	return j.Value(map[string]j.Value{
		'CL': j.Value([
			j.Value(map[string]j.Value{
				'producer_offset':     j.Value(4992)
				'selector_expression': j.Value('low32(accelerator_base + 0x13200) + 0x8')
				'mode':                j.Value(1)
				'value_expression':    j.Value(map[string]j.Value{
					'operation': j.Value('orr')
					'bytes':     j.Value(8)
					'immediate': j.Value(5)
					'source':    j.Value(map[string]j.Value{
						'operation': j.Value('and')
						'bytes':     j.Value(8)
						'mask':      j.Value(u64(8796093021184))
						'source':    j.Value(map[string]j.Value{
							'kind':   j.Value('channel_load')
							'member': j.Value(440)
							'bytes':  j.Value(8)
						})
					})
				})
			}),
			j.Value(map[string]j.Value{
				'producer_offset':     j.Value(5024)
				'selector_expression': j.Value('low32(accelerator_base + 0x13200)')
				'mode':                j.Value(1)
				'value_expression':    j.Value(map[string]j.Value{
					'operation': j.Value('add')
					'bytes':     j.Value(8)
					'first':     j.Value(map[string]j.Value{
						'operation': j.Value('multiply')
						'bytes':     j.Value(8)
						'factor':    j.Value(6144)
						'source':    j.Value(map[string]j.Value{
							'kind':   j.Value('accelerator_load')
							'member': j.Value(1200)
							'bytes':  j.Value(4)
						})
					})
					'second':    j.Value(map[string]j.Value{
						'operation': j.Value('and')
						'bytes':     j.Value(8)
						'mask':      j.Value(u64(8796093021184))
						'source':    j.Value(map[string]j.Value{
							'kind':   j.Value('channel_load')
							'member': j.Value(440)
							'bytes':  j.Value(8)
						})
					})
				})
			}),
		])
	})
}
