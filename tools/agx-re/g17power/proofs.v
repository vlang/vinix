module g17power

// UUID-pinned provider names and instruction words are recovery proof data.
const accelerator_vtable = '__ZTV18AGXAcceleratorG17X'
const linear_provider = '__ZN14AGXAccelerator32populateLinearPowerTransferTableEPjj'
const main_provider = '__ZN32AGX·PI_300·X·A0·AcceleratorX31populateMaximumPerformancePowerEv'
const afr_provider = '__ZN32AGX·PI_300·X·A0·AcceleratorX33populateMaximumPerformancePowerCSEv'
const vdd_leakage_provider = '__ZN32AGX·PI_300·X·A0·AcceleratorX22calculateVddGpuLeakageEddd'
const afr_leakage_provider = '__ZN32AGX·PI_300·X·A0·AcceleratorX19calculateAFRLeakageEddd'
const equation_provider = '__ZN32AGX·PI_300·X·A0·AcceleratorX20applyLeakageEquationERK17LeakageParameters'
const chip_leakage_provider = '__ZN32AGX·PI_300·X·A0·AcceleratorX23populateChipLeakageDataEj'
const main_power_slot = 0xfd0
const afr_power_slot = 0xfd8
const vdd_leakage_slot = 0xa28
const afr_leakage_slot = 0xa30
const equation_slot = 0xa38
const chip_leakage_slot = 0xcb0

fn proof_words(label string) map[int]u32 {
	return match label {
		'G17 linear power-transfer call' {
			map[int]u32{
				0x948: u32(0xf9415e68)
				0x94c: u32(0x52831909)
				0x950: u32(0x8b090101)
				0x954: u32(0x52800002)
				0x958: u32(0x97feaa33)
			}
		}
		'G17 inlined AFR linear power-transfer producer' {
			map[int]u32{
				0x95c: u32(0xf9414e68)
				0x960: u32(0x91407109)
				0x964: u32(0x9113a12a)
				0x968: u32(0xf9415e69)
				0x96c: u32(0xb940014e)
				0x974: u32(0x710041df)
				0x97c: u32(0x5283290b)
				0x980: u32(0x8b0b012b)
				0x984: u32(0xb944ed0c)
				0x98c: u32(0x5299460d)
				0x990: u32(0x72a0002d)
				0x994: u32(0x510005cf)
				0x998: u32(0xd37df1ee)
				0xb8c: u32(0x4b0e01ef)
				0xb94: u32(0x52800c91)
				0xba0: u32(0x4b0e0040)
				0xba4: u32(0x1b117c00)
				0xba8: u32(0x1acf0800)
				0xbac: u32(0xb82c7960)
				0xbb8: u32(0x91002210)
				0xbbc: u32(0x910021ad)
			}
		}
		'G17 linear power-transfer normalisation' {
			map[int]u32{
				0x010: u32(0x91406c08)
				0x014: u32(0x910c4108)
				0x018: u32(0xb940010b)
				0x01c: u32(0x7100417f)
				0x024: u32(0x5298c609)
				0x028: u32(0x72a00029)
				0x02c: u32(0xb944e40d)
				0x034: u32(0x5100056c)
				0x038: u32(0xd37ae58a)
				0x2dc: u32(0x4b0a018b)
				0x2f0: u32(0x52800c8e)
				0x300: u32(0x1b0e7def)
				0x304: u32(0x1acb09ef)
				0x320: u32(0xb900022f)
			}
		}
		'G17 maximum-performance power matrix' {
			map[int]u32{
				0x034: u32(0xb944e415)
				0x038: u32(0xb944ec18)
				0x088: u32(0x9118c131)
				0x090: u32(0x9128c121)
				0x0a4: u32(0x52a88f44)
				0x0a8: u32(0x529bd065)
				0x0ac: u32(0x72a86365)
				0x0b8: u32(0x1ad80aba)
				0x244: u32(0x529ae148)
				0x248: u32(0x72a7f468)
				0x258: u32(0x52866668)
				0x25c: u32(0x72a83428)
				0x278: u32(0x528e8009)
				0x27c: u32(0x72a8e7a9)
				0x308: u32(0xb912db08)
			}
		}
		'G17 CS maximum-performance power matrix' {
			map[int]u32{
				0x030: u32(0xb944a009)
				0x034: u32(0x7100853f)
				0x038: u32(0x52933348)
				0x03c: u32(0x72a835a8)
				0x044: u32(0x52947ae8)
				0x048: u32(0x72a82888)
				0x068: u32(0x5292d90a)
				0x06c: u32(0x528c1c0b)
				0x080: u32(0x9128c14d)
				0x084: u32(0x9114e2b7)
				0x1d0: u32(0xb90502e8)
			}
		}
		'G17 chip-leakage fuse decode' {
			map[int]u32{
				0x14c: u32(0xb944e6bb)
				0x1a0: u32(0xb9400210)
				0x1a4: u32(0x29444620)
				0x1ac: u32(0x9ad12210)
				0x1b0: u32(0x9ace25ad)
				0x1b4: u32(0x8a0f01ad)
				0x1b8: u32(0xaa0d020d)
				0x1bc: u32(0x9e2301a0)
				0x1c0: u32(0x1e202800)
				0x1c8: u32(0xb9419f0d)
				0x1cc: u32(0x53043dad)
				0x1d0: u32(0x1e03fda0)
				0x260: u32(0x9e2301a1)
				0x264: u32(0x1e212821)
				0x268: u32(0x1e200821)
				0x270: u32(0xb9419f0d)
				0x274: u32(0x53043dad)
				0x278: u32(0x1e03f9a1)
				0x398: u32(0xb944eeb5)
				0x3ac: u32(0xb9419f08)
				0x3b0: u32(0xb941a309)
				0x3b4: u32(0x13886528)
				0x3b8: u32(0x531f2d08)
			}
		}
		else { panic('unknown power recovery proof ' + label) }
	}
}
