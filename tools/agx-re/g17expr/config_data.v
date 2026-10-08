module g17expr

import traceanalysis as j

// Checked producer instruction evidence and recovered fixed byte-field maps.
// These literals contain no recovery algorithm; checks and analysis live in
// config_performance.v, config_channels.v and config_late.v.

fn config_symbol(name string) string {
	return match name {
		'AGX_COMMAND_QUEUE_INIT' {
			'__ZN15AGXCommandQueue4initEP5IOGPUP11IOGPUDeviceP30IOGPUDeviceNewCommandQueueArgs'
		}
		'ARM_INIT_FIRMWARE_DATA' { '__ZN14AGXArmFirmware16initFirmwareDataEv' }
		'ARM_SET_CHANNEL_PRIORITY' {
			'__ZN14AGXArmFirmware18setChannelPriorityEP17_AGFIChannelState23eAGXContextPriorityTypej26eIOGPUCommandQueueQosLevel'
		}
		'BASE_CONFIGURE_DEVICE' { '__ZN14AGXAccelerator15configureDeviceEP9IOService' }
		'CONVERT_GPU_VA_TO_FW_VA' { '__ZNK14AGXArmFirmware18convertGPUVAToFWVAEyb' }
		'FAMILY_GET_PROBE_SCORE' { '__ZN20AGXFamilyAccelerator13getProbeScoreEv' }
		'G17_ACCELERATOR_ALLOC' { '__ZNK18AGXAcceleratorG17X9MetaClass5allocEv' }
		'G17_ACCELERATOR_VTABLE' { '__ZTV18AGXAcceleratorG17X' }
		'G17_ARM_FIRMWARE_ASC_META_ALLOC' { '__ZNK17AGXArmFirmwareASC9MetaClass5allocEv' }
		'G17_CALCULATE_VDD_GPU_LEAKAGE' {
			'__ZN32AGX·PI_300·X·A0·AcceleratorX22calculateVddGpuLeakageEddd'
		}
		'G17_CONFIGURE_DEVICE' {
			'__ZN32AGX·PI_300·X·A0·AcceleratorX15configureDeviceEP9IOService'
		}
		'G17_FIRMWARE_VTABLE' { '__ZTV17AGXArmFirmwareASC' }
		'G17_GET_PERF_STATE_CAP' {
			'__ZN32AGX·PI_300·X·A0·AcceleratorX15getPerfStateCapE14AGXClockDomainRb'
		}
		'G17_PARSE_PERF_STATE_MAP_REGS' {
			'__ZN20AGXFamilyAccelerator21parsePerfStateMapRegsEv.8015'
		}
		'G17_POPULATE_CHIP_LEAKAGE_DATA' {
			'__ZN32AGX·PI_300·X·A0·AcceleratorX23populateChipLeakageDataEj'
		}
		'G17_POPULATE_MAX_PERF_POWER_CS' {
			'__ZN32AGX·PI_300·X·A0·AcceleratorX33populateMaximumPerformancePowerCSEv'
		}
		'G17_POPULATE_POWER_ESTIMATION_CONFIG' {
			'__ZN32AGX·PI_300·X·A0·AcceleratorX33populatePowerEstimationConfigDataEj'
		}
		'G17_POPULATE_SRAM_POWER_SCALE_DATA' {
			'__ZN32AGX·PI_300·X·A0·AcceleratorX26populateSRAMPowerScaleDataEv'
		}
		'G17_POPULATE_STATIC_POWER_DATA' { '__ZN14AGXAccelerator23populateStaticPowerDataEv.8120' }
		'G17_READ_CHIP_INFO' {
			'__ZNK32AGX·PI_300·X·A0·AcceleratorX12readChipInfoEP16AGXGPUCoreConfig'
		}
		'GET_CHANNEL_PRIORITY' { '__ZN10AGXChannel11getPriorityEv' }
		'IDLE_POWER_OFF_TIMER' { '__ZN14AGXAccelerator17idlePowerOffTimerEv' }
		'INIT_BASE_SETUP_CONFIG' { '__ZN11AGXFirmware11setupConfigEv' }
		'INIT_POWER_DATA' { '__ZN14AGXArmFirmware27initPowerAndPerformanceDataEv' }
		'KALLOC_TYPE_IMPL' { '_kalloc_type_impl' }
		'MARK_CHANNEL_SUBMITTED_PREFIX' { '__ZN10AGXChannel32markCommandsSubmittedToAccelRingEv' }
		'OS_OBJECT_TYPED_OPERATOR_NEW' { '_OSObject_typed_operator_new' }
		'PI300_READ_CHIP_INFO' {
			'__ZNK31AGX·PI_300·X·A0·Accelerator12readChipInfoEP16AGXGPUCoreConfig'
		}
		'POPULATE_AFR_FAST_DIE_CONFIG' {
			'__ZN14AGXAccelerator34populateAFRFastDieDeviceConfigDataEP32AGXFastDieControllerDeviceConfig'
		}
		'POPULATE_AUX_PERF_STATE_INFO' {
			'__ZN14AGXAccelerator21populatePerfStateInfoILj16ELj2EEEbP9IOService14AGXClockDomainR13PerfStateInfoIXT_EXT0_EE'
		}
		'SET_CHANNEL_PRIORITY' {
			'__ZN10AGXChannel11setPriorityE23eAGXContextPriorityTypej26eIOGPUCommandQueueQosLevel'
		}
		'SUBMIT_COMMAND_TO_FIRMWARE_BLOCK' {
			'____ZN12AGXWorkQueue23submitCommandToFirmwareEP10AGXChannelP20AGXCommandDescriptorb_block_invoke'
		}
		'UNMARK_CHANNEL_SUBMITTED_PREFIX' {
			'__ZN10AGXChannel34unmarkCommandsSubmittedToAccelRingEv'
		}
		else { panic(name) }
	}
}

fn config_feature_mask() u64 { return u64(0x0001000018020000) }

fn config_number(name string) int {
	return match name {
		'FIRMWARE_ADDRESS_CONVERSION_VTABLE_SLOT' { 728 }
		'G17_GET_PERF_STATE_CAP_VTABLE_SLOT' { 4568 }
		'G17_PERF_STATE_MAP_VTABLE_SLOT' { 4632 }
		'G17_POPULATE_CHIP_LEAKAGE_VTABLE_SLOT' { 3248 }
		'G17_POPULATE_POWER_ESTIMATION_VTABLE_SLOT' { 3264 }
		'G17_POPULATE_SRAM_POWER_SCALE_VTABLE_SLOT' { 3312 }
		'G17_POPULATE_STATIC_POWER_VTABLE_SLOT' { 3296 }
		'LC_SEGMENT_64' { 25 }
		else { panic(name) }
	}
}

fn config_submit_channels() j.Value {
	return j.Value(map[string]j.Value{
		'TA': j.Value([
			j.Value('__ZN14AGXArmFirmware15submitTAChannelEP10AGXChannelRK22_AGXChannelSubmitInfo_jjb'),
			j.Value('__ZN11AGXFirmware15submitTAChannelEP10AGXChannelRK22_AGXChannelSubmitInfo_jjb'),
			j.Value(0),
		])
		'3D': j.Value([
			j.Value('__ZN14AGXArmFirmware15submit3DChannelEP10AGXChannelRK22_AGXChannelSubmitInfo_jjbb'),
			j.Value('__ZN11AGXFirmware15submit3DChannelEP10AGXChannelRK22_AGXChannelSubmitInfo_jjbb'),
			j.Value(1),
		])
		'CL': j.Value([
			j.Value('__ZN14AGXArmFirmware15submitCLChannelEP10AGXChannelRK22_AGXChannelSubmitInfo_jjb'),
			j.Value('__ZN11AGXFirmware15submitCLChannelEP10AGXChannelRK22_AGXChannelSubmitInfo_jjb'),
			j.Value(2),
		])
	})
}

fn config_words(label string) map[int]u32 {
	return match label {
		'GPU base performance-state scaling' {
			{
				0x48c: u32(0xf9414e68)
				0x490: u32(0x91404115)
				0x494: u32(0xb94ecea9)
				0x498: u32(0x5290a3ea)
				0x49c: u32(0x72aa3d6a)
				0x4a0: u32(0x9baa7d29)
				0x4a4: u32(0xd365fd36)
				0x4c8: u32(0xf0ff3fc1)
				0x4cc: u32(0x913d0c21)
				0x50c: u32(0xb9400016)
				0x510: u32(0x34004896)
				0x514: u32(0xb94f3668)
				0x518: u32(0x6b160109)
				0x520: u32(0x52800c8a)
				0x53c: u32(0x1b0a7ec9)
				0x540: u32(0xb90ec6a9)
				0x544: u32(0x1b0a7d08)
				0x548: u32(0xb90ecaa8)
				0x54c: u32(0xb90ecea9)
			}
		}
		'G17 relative boost-frequency table' {
			{
				0xce4: u32(0x5283210b)
				0xce8: u32(0x8b0b0134)
				0xcec: u32(0xb94b86a9)
				0xcf0: u32(0x5290a3eb)
				0xcf4: u32(0x72aa3d6b)
				0xcf8: u32(0x9bab7d29)
				0xcfc: u32(0xd365fd3a)
				0xd00: u32(0x91406d08)
				0xd04: u32(0x910c6116)
				0xd08: u32(0x8b1a0ac8)
				0xd0c: u32(0xb9400117)
				0xd10: u32(0xd1000559)
				0xd14: u32(0xd37ef738)
				0xd2c: u32(0xb940011b)
				0xd30: u32(0xd37ef541)
				0xd34: u32(0xaa1403e0)
				0xd3c: u32(0xeb1a033f)
				0xd44: u32(0xcb170368)
				0xd48: u32(0x11000749)
				0xd4c: u32(0x52800c8a)
				0xd68: u32(0xb940018c)
				0xd6c: u32(0xcb17018c)
				0xd84: u32(0x9b0a7d8b)
				0xd88: u32(0x9ac8096b)
				0xd8c: u32(0xb90001ab)
				0xd94: u32(0x11000529)
				0xd98: u32(0xeb1a033f)
				0xd9c: u32(0x54fffda8)
				0xdb4: u32(0x52800c89)
				0xdb8: u32(0xb9000109)
			}
		}
		'G17 power-estimation setup call' {
			{
				0x224: u32(0xf9414e60)
				0x228: u32(0xb94f3661)
				0x22c: u32(0xf9400010)
				0x23c: u32(0xd2819811)
				0x240: u32(0x8b110210)
				0x244: u32(0xf9400208)
				0x24c: u32(0xd73f0910)
			}
		}
		'G17 power-estimation feature bit' {
			{
				0x94: u32(0xf9436a68)
				0x98: u32(0xd2a30049)
				0x9c: u32(0xf2e00029)
				0xa0: u32(0xaa090108)
				0xa4: u32(0xf9036a68)
			}
		}
		'G17 SRAM power-scale dispatch' {
			{
				0x14: u32(0x395b4808)
				0x18: u32(0x36080508)
				0x20: u32(0xf942d808)
				0x24: u32(0x9133c108)
				0x28: u32(0x91404409)
				0x2c: u32(0x91072129)
				0x30: u32(0xf9000128)
				0x44: u32(0xd2819e11)
				0x48: u32(0x8b110210)
				0x4c: u32(0xf9400208)
				0x58: u32(0xd73f0910)
				0x80: u32(0x9132c202)
				0x84: u32(0xf9465a10)
			}
		}
		'G17 SRAM power-scale fill' {
			{
				0x4:  u32(0x91406c08)
				0x8:  u32(0x910c4108)
				0xc:  u32(0xb9400108)
				0x14: u32(0x91404409)
				0x18: u32(0x91072129)
				0x1c: u32(0xf9400129)
				0x44: u32(0x9101412b)
				0x48: u32(0x5291eb8c)
				0x4c: u32(0x72a7f04c)
				0x58: u32(0xad3e8160)
				0x5c: u32(0xad3f8160)
				0x90: u32(0x5291eb8d)
				0x94: u32(0x72a7f04d)
				0x9c: u32(0x3c810580)
				0xbc: u32(0x5291eb8a)
				0xc0: u32(0x72a7f04a)
				0xc4: u32(0xb800452a)
				0xc8: u32(0xf1000508)
				0xcc: u32(0x54ffffc1)
			}
		}
		'G17 power-estimation runtime copy' {
			{
				0x20: u32(0xf9416c00)
				0x24: u32(0x5283ba01)
				0x28: u32(0x72a00021)
				0x2c: u32(0x94aa6439)
				0x30: u32(0xf9416e68)
				0x34: u32(0x91029100)
				0x38: u32(0x9133c261)
				0x3c: u32(0x52802c02)
				0x40: u32(0x94aa63c8)
			}
		}
		'G17 SRAM power-scale firmware copy' {
			{
				0x294: u32(0xf9416e68)
				0x400: u32(0xf9415e6b)
				0x404: u32(0x5282010a)
				0x408: u32(0x8b0a016a)
				0x40c: u32(0x91041108)
				0x410: u32(0x5283110c)
				0x414: u32(0x8b0c016b)
				0x418: u32(0x5280020c)
				0x51c: u32(0xbc5c0100)
				0x520: u32(0xbc1c0160)
				0x524: u32(0x91010129)
				0x528: u32(0xbc404500)
				0x52c: u32(0xbc004560)
				0x530: u32(0x9101014a)
				0x534: u32(0xf100058c)
				0x538: u32(0x54fff721)
			}
		}
		'G17 ASC typed allocation' {
			{
				0x1c: u32(0x910cc000)
				0x20: u32(0x52852401)
				0x28: u32(0xaa0003f3)
			}
		}
		'OSObject zeroed typed allocation' {
			{
				0x14: u32(0xb9402c08)
				0x18: u32(0x92405d08)
				0x1c: u32(0xeb08003f)
				0x20: u32(0x54000129)
				0x44: u32(0x52800081)
			}
		}
		'G17 SRAM/static power row boundary' {
			{
				0xc:  u32(0xb9400108)
				0x1c: u32(0xf9400129)
				0xb4: u32(0x8b0a0929)
				0xb8: u32(0x91008129)
				0xc4: u32(0xb800452a)
			}
		}
		'G17 leakage-data destination ranges' {
			{
				0x2c0: u32(0xf942daba)
				0x2c4: u32(0x91394348)
				0x2c8: u32(0x913a4349)
				0x330: u32(0x913b4348)
				0x334: u32(0x913c4349)
				0x3fc: u32(0x913c8348)
				0x400: u32(0x913ca349)
			}
		}
		'G17 zero static power-scale firmware copy' {
			{
				0x40c: u32(0x91041108)
				0x410: u32(0x5283110c)
				0x414: u32(0x8b0c016b)
				0x418: u32(0x5280020c)
				0x528: u32(0xbc404500)
				0x52c: u32(0xbc004560)
				0x534: u32(0xf100058c)
				0x538: u32(0x54fff721)
			}
		}
		'G17 AFR performance-state record' {
			{
				0x1c: u32(0x91407008)
				0x20: u32(0x9113a114)
				0xdc: u32(0xb9400289)
				0xe4: u32(0x1b082929)
			}
		}
		'G17 AFR relative boost-frequency table' {
			{
				0xdd8: u32(0xf9415e69)
				0xddc: u32(0x5283310a)
				0xde0: u32(0x8b0a0134)
				0xde4: u32(0xb94b86a9)
				0xde8: u32(0x5290a3ea)
				0xdec: u32(0x72aa3d6a)
				0xdf0: u32(0x9baa7d29)
				0xdf4: u32(0xd365fd35)
				0xdf8: u32(0x914072e9)
				0xdfc: u32(0x9113c136)
				0xe00: u32(0x8b150ac9)
				0xe04: u32(0xb9400137)
				0xe08: u32(0xd1000519)
				0xe28: u32(0xd37ef501)
				0xe2c: u32(0xaa1403e0)
				0xe3c: u32(0xcb170348)
				0xe44: u32(0x52800c8a)
				0xe50: u32(0xb940018c)
				0xe54: u32(0xcb17018c)
				0xe58: u32(0x9b0a7d8c)
				0xe5c: u32(0x9ac8098c)
				0xe64: u32(0xb900016c)
				0xe68: u32(0x910006b5)
				0xe6c: u32(0xeb0902bf)
				0xe70: u32(0x54fffec3)
				0xe88: u32(0x52800c89)
				0xe8c: u32(0xb9000109)
			}
		}
		'G17 performance-state map enable-byte preservation' {
			{
				0x20: u32(0xbc089260)
				0x24: u32(0x3902127f)
			}
		}
		'G17 fixed performance-state map fallback' {
			{
				0x6c:  u32(0x6f00e400)
				0x70:  u32(0xad0283e0)
				0x74:  u32(0xad0383e0)
				0x78:  u32(0x3d8027e0)
				0x7c:  u32(0xf90053ff)
				0x80:  u32(0xad0183e0)
				0x84:  u32(0xad0083e0)
				0xb80: u32(0x394257e8)
				0xb84: u32(0x36000148)
				0xbb4: u32(0x91406a68)
				0xbb8: u32(0x91292109)
				0xbbc: u32(0x3d800120)
				0xbc0: u32(0x912a2109)
				0xbc4: u32(0x6f00e400)
				0xbc8: u32(0x3d800120)
				0xbcc: u32(0x91296109)
				0xbd0: u32(0x912a610a)
				0xbdc: u32(0x3d800121)
				0xbe0: u32(0x3d800140)
				0xbe4: u32(0x9129a109)
				0xbe8: u32(0x912aa10a)
				0xbf4: u32(0x3d800121)
				0xbf8: u32(0x3d800140)
				0xbfc: u32(0x9129e109)
				0xc00: u32(0x912ae108)
				0xc0c: u32(0x3d800121)
				0xc10: u32(0x3d800100)
			}
		}
		'G17 performance-state map firmware copy' {
			{
				0x804: u32(0xf9415e68)
				0x808: u32(0x52833909)
				0x80c: u32(0x8b09010a)
				0x810: u32(0xf9414e69)
				0x814: u32(0x91406929)
				0x818: u32(0x6f00e400)
				0x81c: u32(0xad030140)
				0x820: u32(0xad020140)
				0x824: u32(0xad010140)
				0x828: u32(0xad000140)
				0x82c: u32(0xb94a492a)
				0x830: u32(0xb919c90a)
				0x834: u32(0xb94a892a)
				0x838: u32(0xb91a090a)
				0x91c: u32(0xb94a852a)
				0x920: u32(0xb91a050a)
				0x924: u32(0xb94ac529)
				0x928: u32(0xb91a4509)
			}
		}
		'G17 data-master ring matrix' {
			{
				0x524: u32(0x9100a2f7)
				0x528: u32(0xf10282ff)
				0x530: u32(0xd2800016)
				0x55c: u32(0x52800b17)
				0x568: u32(0x8b160278)
				0x56c: u32(0x910ec315)
				0x5dc: u32(0xf81a8100)
				0x64c: u32(0xf81b0100)
				0x6c0: u32(0xf81b8100)
				0x70c: u32(0xf81c0100)
				0x780: u32(0xf81c8100)
				0x7f0: u32(0xf81d0100)
				0x864: u32(0xf81d8100)
				0x8b0: u32(0xf81e0100)
				0x924: u32(0xf81e8100)
				0x994: u32(0xf81f0100)
				0xa08: u32(0xf81f8100)
				0xa54: u32(0xf9000100)
				0xa58: u32(0x910182f7)
				0xa5c: u32(0x9100a2d6)
				0xa60: u32(0xf10762ff)
			}
		}
		'G17 channel-priority getter' {
			{
				0x0: u32(0xd503245f)
				0x4: u32(0xf9402c08)
				0x8: u32(0xb9402900)
				0xc: u32(0xd65f03c0)
			}
		}
		'G17 channel-priority profiles' {
			{
				0x4:   u32(0x7100045f)
				0xc:   u32(0x7100085f)
				0x14:  u32(0x7100105f)
				0x1c:  u32(0x7100145f)
				0x28:  u32(0xb900283f)
				0x30:  u32(0xb9003829)
				0x34:  u32(0x929fffe9)
				0x3c:  u32(0x340003c2)
				0x48:  u32(0x7100049f)
				0x50:  u32(0x34000684)
				0x54:  u32(0x7100049f)
				0x60:  u32(0xb9002828)
				0x68:  u32(0xd2ffffe9)
				0x6c:  u32(0xf9001829)
				0x74:  u32(0xb9004029)
				0x7c:  u32(0x52800028)
				0x80:  u32(0xb9002828)
				0x88:  u32(0xb2607fe9)
				0x8c:  u32(0xf9001829)
				0x94:  u32(0x52800068)
				0x98:  u32(0xb9002828)
				0xa0:  u32(0xf900183f)
				0xa4:  u32(0xb900403f)
				0xa8:  u32(0xb9002c28)
				0xac:  u32(0xb9003c23)
				0xb4:  u32(0x52800008)
				0xb8:  u32(0xb900283f)
				0xc4:  u32(0x929fffea)
				0xc8:  u32(0xf900182a)
				0xcc:  u32(0xb9004029)
				0xd4:  u32(0x7100089f)
				0xe4:  u32(0x52800068)
				0xf0:  u32(0xf900183f)
				0xf8:  u32(0xb9004029)
				0x100: u32(0x52800048)
				0x10c: u32(0xd2ffffe9)
				0x114: u32(0x52800069)
				0x128: u32(0x52800048)
				0x134: u32(0xd2ffffe9)
				0x13c: u32(0xb9004028)
			}
		}
		'G17 default channel subpriority' {
			{
				0x284: u32(0x52800048)
				0x288: u32(0xb9081a68)
			}
		}
		'G17 channel submit-info construction' {
			{
				0x24:  u32(0xa9425013)
				0x28:  u32(0xf9401808)
				0x38:  u32(0xf9403509)
				0x3c:  u32(0xa9017fff)
				0x54:  u32(0xb940de8a)
				0x58:  u32(0xb940528b)
				0x64:  u32(0xf9406a8c)
				0x80:  u32(0xf90001a9)
				0x84:  u32(0x11000549)
				0x88:  u32(0xb900de89)
				0x8c:  u32(0xf940328a)
				0x90:  u32(0xb9404156)
				0xb8:  u32(0x290127f6)
				0xbc:  u32(0xb940f288)
				0xc0:  u32(0xb90013e8)
				0xc4:  u32(0xf9400168)
				0xc8:  u32(0xf9402508)
				0xcc:  u32(0xf9000fe8)
				0x2a8: u32(0xb940ca88)
				0x2bc: u32(0xf9406660)
				0x2c0: u32(0x910023e2)
				0x2c4: u32(0x12000343)
				0x2c8: u32(0xaa1403e1)
				0x2d0: u32(0xd73f0911)
			}
		}
		'G17 channel submitted transition' {
			{
				0x2d4: u32(0x34000160)
				0x2d8: u32(0xf9400290)
				0x2e8: u32(0xd2804011)
				0x2ec: u32(0x8b110210)
				0x2f0: u32(0xf9400208)
				0x2f4: u32(0xaa1403e0)
				0x2fc: u32(0xd73f0910)
			}
		}
		'G17 channel submitted priority reset' {
			{
				0x58: u32(0xf9402e68)
				0x5c: u32(0xb9402909)
				0x60: u32(0x6b09029f)
				0x64: u32(0x540001a0)
				0x68: u32(0x12800009)
				0x6c: u32(0xb9004509)
				0x80: u32(0xd2804111)
				0x84: u32(0x8b110210)
				0x88: u32(0xf9400208)
				0x8c: u32(0xaa1303e0)
				0x94: u32(0xd73f0910)
				0x98: u32(0xd5033bbf)
			}
		}
		'G17 secondary performance block' {
			{
				0x740: u32(0x395416c8)
				0x744: u32(0x36000608)
				0x74c: u32(0xf9415e75)
				0x750: u32(0x52839b08)
				0x758: u32(0x52810901)
				0x760: u32(0xb94b5a88)
				0x764: u32(0x51000509)
				0x768: u32(0xb91cdaa9)
				0x77c: u32(0x52839b8a)
				0x784: u32(0x912e828b)
				0x788: u32(0x5283a38c)
				0x790: u32(0x529bd06d)
				0x794: u32(0x72a8636d)
				0x7a4: u32(0x9101016b)
				0x7a8: u32(0x9101018c)
				0x7b4: u32(0xb868792e)
				0x7b8: u32(0x9bad7dce)
				0x7bc: u32(0xd372fdce)
				0x7c0: u32(0xb828794e)
				0x7c4: u32(0xb94b5e8e)
				0x7e0: u32(0xb9440211)
				0x7e4: u32(0xb90401f1)
			}
		}
		'G17 chip-info gate relay' {
			{
				0xc2c: u32(0x3cc802a0)
				0xc30: u32(0x3d814260)
			}
		}
		'G17 GPU identity register reads' {
			{
				0x3c: u32(0x5288001a)
				0x40: u32(0x72a01a1a)
				0x54: u32(0x52880001)
				0x58: u32(0x72a01a01)
				0x70: u32(0x91004341)
				0x8c: u32(0x91005341)
				0xa8: u32(0x91006341)
				0xc4: u32(0x91007341)
			}
		}
		'G17 chip variant decode' {
			{
				0xec:  u32(0x53187ee8)
				0xf0:  u32(0x71002d1f)
				0xf8:  u32(0x53105ee8)
				0xfc:  u32(0x7100111f)
				0x104: u32(0x71000d1f)
				0x10c: u32(0x7100091f)
				0x114: u32(0x52800148)
				0x118: u32(0xb9007668)
				0x11c: u32(0x52800408)
				0x120: u32(0xb9002268)
				0x564: u32(0x52800288)
				0x56c: u32(0x52800428)
				0x578: u32(0x52800448)
				0x57c: u32(0xb9002268)
			}
		}
		'G17 final late-control fields' {
			{
				0x380:  u32(0xf94d5e61)
				0x394:  u32(0xd2805b11)
				0x3a4:  u32(0x52800002)
				0x3b4:  u32(0x5284d389)
				0x3bc:  u32(0xf9000100)
				0x10f8: u32(0x52800034)
				0x126c: u32(0xb926c114)
			}
		}
		'G17 converted member cleared' {
			{
				0x940: u32(0xf90d5e7f)
			}
		}
		'G17 late-control ones run' {
			{
				0xf38: u32(0x6f07e7e0)
				0xf3c: u32(0xad000120)
				0xf40: u32(0x3d800920)
			}
		}
		'G17 late-control copied bytes' {
			{
				0xf54: u32(0x395bc16a)
				0xf58: u32(0x3904f12a)
				0xf5c: u32(0x395be16a)
				0xf60: u32(0x3904f52a)
			}
		}
		'G17 late-control feature guard' {
			{
				0xf64: u32(0xf9436969)
				0xf68: u32(0xd366fd2a)
				0xf74: u32(0x3600004a)
				0xf7c: u32(0x5284b589)
				0xf84: u32(0xb20003e9)
				0xf88: u32(0xf9000109)
			}
		}
		'G17 cleared copy sources' {
			{
				0x28:  u32(0xaa0003f3)
				0x5f8: u32(0x790de27f)
				0x5fc: u32(0x391be27f)
			}
		}
		'G17 accelerator allocation' {
			{
				0x18: u32(0x52997a01)
				0x1c: u32(0x72a00021)
				0x20: u32(0x94c7ee3e)
			}
		}
		'G17 idle timer derived base' {
			{
				0x2c: u32(0x91404e74)
				0x94: u32(0xf903969f)
			}
		}
		'G17 chip-info nibble products' {
			{
				0x1e8: u32(0x53104f08)
				0x1ec: u32(0x12000f09)
				0x1f0: u32(0xe040f00)
				0x1fc: u32(0x2ea14401)
				0x208: u32(0x2ea24400)
				0x214: u32(0xe221c21)
				0x218: u32(0xe221c00)
				0x224: u32(0x1b097d08)
				0x228: u32(0xea09c20)
				0x238: u32(0xb9004a68)
				0x23c: u32(0x3c84c260)
			}
		}
		'G17 unit mask' {
			{
				0x568: u32(0xb944d12a)
				0x56c: u32(0x9280000b)
				0x570: u32(0x9aca216b)
				0x574: u32(0x7100fd5f)
				0x578: u32(0x1280000a)
				0x57c: u32(0x5a8b814a)
				0x580: u32(0xb925550a)
			}
		}
		'G17 chip-info gate byte' {
			{
				0x258: u32(0x52800036)
				0x348: u32(0x39021a76)
				0x36c: u32(0xa9012269)
			}
		}
		'G17 core-mask register read' {
			{
				0x260: u32(0x5282a017)
				0x264: u32(0x72a01c17)
				0x354: u32(0xcb180008)
				0x358: u32(0x8b170108)
				0x35c: u32(0xb9400109)
				0x360: u32(0xb940050a)
				0x364: u32(0xaa0a8129)
				0x368: u32(0xb9400908)
			}
		}
		'G17 core-count producer select' {
			{
				0x6b4: u32(0x3954190a)
				0x6b8: u32(0x3600024a)
				0x6cc: u32(0x5280020c)
				0x6d0: u32(0xf100017f)
				0x6d4: u32(0x9a8c13eb)
				0x6d8: u32(0x8b0b014a)
				0x6dc: u32(0x6d400141)
			}
		}
		'G17 chip-info topology decode' {
			{
				0x19c: u32(0x53104ea8)
				0x1a0: u32(0xb9006e68)
				0x1a4: u32(0x53083ea9)
				0x1a8: u32(0x1b087d28)
				0x1ac: u32(0xb9006668)
				0x1b0: u32(0x12001ea9)
				0x1b4: u32(0xb9007a69)
				0x1b8: u32(0x1b097d09)
				0x1cc: u32(0x29062a69)
			}
		}
		'G17 chip-info core-mask relay' {
			{
				0x68:  u32(0x910043f5)
				0xc14: u32(0xad4087e0)
				0xc18: u32(0x3d812260)
				0xc1c: u32(0x3d812661)
			}
		}
		'G17 late-control vector constants' {
			{
				0xa4:   u32(0x6f00e400)
				0xa8:   u32(0xfd130120)
				0x1284: u32(0xfd137900)
			}
		}
		else { panic(label) }
	}
}

fn config_sequence(label string) []u32 {
	return match label {
		'G17 auxiliary performance property selector' {
			[u32(0x7100045f), 0x5280a128, 0x9a880508, 0x8b080008, 0x39400108, 0xf900a07f, 0x6f00e400,
				0xad090060, 0xad080060, 0xad070060, 0xad060060, 0xad050060, 0xad040060, 0xad030060,
				0xad020060, 0xad010060, 0xad000060, 0x36000588]
		}
		'G17 auxiliary performance dimensions' {
			[u32(0xa9402acb), 0x52800108, 0x2a0a1108, 0x52800209, 0x1b0b2508, 0x51004549, 0x6b08001f,
				0x3a4f2920, 0x54001043, 0xb944eea8, 0x7100097f, 0x7a4b9100, 0x54000fc1, 0x29002e8a,
				0x340007ab]
		}
		'G17 auxiliary voltage and frequency conversion' {
			[u32(0xa9400e30), 0xd343fe10, 0x9bcc7e10, 0xd344fe10, 0xb8008410, 0x91004230, 0xb8004423]
		}
		'G17 auxiliary SRAM voltage clamp' {
			[u32(0xb840458f), 0xb85801b0, 0x6b0f021f, 0x1a8f820f, 0xb80045af]
		}
		'G17 auxiliary voltage row copy' { [u32(0xb8580200), 0xb8180220, 0xb8404600, 0xb8004620] }
		'G17 channel submitted mark' { [u32(0xd503245f), 0x52800028, 0x3900f008, 0xd65f03c0] }
		'G17 channel submitted unmark' { [u32(0xd503245f), 0x3900f01f, 0xd65f03c0] }
		'G17 CS performance block binding' {
			[u32(0xb943a109), 0x5100052b, 0xb91a49ab, 0xb94f3e6b, 0xb91a4dab, 0x34000489, 0xd2800009,
				0x9140714a, 0x910ea14a, 0x52834a0b, 0x8b0b01ab, 0x9111a10c, 0x5283620e, 0x8b0e01ad]
		}
		'G17 AFR performance block binding' {
			[u32(0xb944e909), 0x5100052b, 0xb91b91ab, 0xb94f426b, 0xb91b95ab, 0x34000489, 0xd2800009,
				0x9140714a, 0x9113c14a, 0x5283730b, 0x8b0b01ab, 0x9116c10c, 0x52838b0e, 0x8b0e01ad]
		}
		else { panic(label) }
	}
}

fn config_metadata(operation string) j.Value {
	match operation {
		'recover_g17_data_master_ring_bindings' {
			return j.Value(map[string]j.Value{
				'priorities':                  j.Value(4)
				'command_types':               j.Value(3)
				'host_object_stride':          j.Value(40)
				'address_record_bytes':        j.Value(32)
				'priority_record_bytes':       j.Value(96)
				'primary_large_region_offset': j.Value(0)
				'primary_large_region_bytes':  j.Value(384)
				'bindings':                    j.Value([
					j.Value(map[string]j.Value{
						'priority':                    j.Value(0)
						'command':                     j.Value('TA')
						'command_type':                j.Value(0)
						'host_object_member':          j.Value(944)
						'host_state_cpu_member':       j.Value(952)
						'host_state_gpu_member':       j.Value(960)
						'host_entries_cpu_member':     j.Value(968)
						'host_entries_gpu_member':     j.Value(976)
						'state_bytes':                 j.Value(48)
						'entries_bytes':               j.Value(6144)
						'primary_large_region_offset': j.Value(0)
					}),
					j.Value(map[string]j.Value{
						'priority':                    j.Value(0)
						'command':                     j.Value('3D')
						'command_type':                j.Value(1)
						'host_object_member':          j.Value(1104)
						'host_state_cpu_member':       j.Value(1112)
						'host_state_gpu_member':       j.Value(1120)
						'host_entries_cpu_member':     j.Value(1128)
						'host_entries_gpu_member':     j.Value(1136)
						'state_bytes':                 j.Value(48)
						'entries_bytes':               j.Value(6144)
						'primary_large_region_offset': j.Value(32)
					}),
					j.Value(map[string]j.Value{
						'priority':                    j.Value(0)
						'command':                     j.Value('CL')
						'command_type':                j.Value(2)
						'host_object_member':          j.Value(1264)
						'host_state_cpu_member':       j.Value(1272)
						'host_state_gpu_member':       j.Value(1280)
						'host_entries_cpu_member':     j.Value(1288)
						'host_entries_gpu_member':     j.Value(1296)
						'state_bytes':                 j.Value(48)
						'entries_bytes':               j.Value(6144)
						'primary_large_region_offset': j.Value(64)
					}),
					j.Value(map[string]j.Value{
						'priority':                    j.Value(1)
						'command':                     j.Value('TA')
						'command_type':                j.Value(0)
						'host_object_member':          j.Value(984)
						'host_state_cpu_member':       j.Value(992)
						'host_state_gpu_member':       j.Value(1000)
						'host_entries_cpu_member':     j.Value(1008)
						'host_entries_gpu_member':     j.Value(1016)
						'state_bytes':                 j.Value(48)
						'entries_bytes':               j.Value(6144)
						'primary_large_region_offset': j.Value(96)
					}),
					j.Value(map[string]j.Value{
						'priority':                    j.Value(1)
						'command':                     j.Value('3D')
						'command_type':                j.Value(1)
						'host_object_member':          j.Value(1144)
						'host_state_cpu_member':       j.Value(1152)
						'host_state_gpu_member':       j.Value(1160)
						'host_entries_cpu_member':     j.Value(1168)
						'host_entries_gpu_member':     j.Value(1176)
						'state_bytes':                 j.Value(48)
						'entries_bytes':               j.Value(6144)
						'primary_large_region_offset': j.Value(128)
					}),
					j.Value(map[string]j.Value{
						'priority':                    j.Value(1)
						'command':                     j.Value('CL')
						'command_type':                j.Value(2)
						'host_object_member':          j.Value(1304)
						'host_state_cpu_member':       j.Value(1312)
						'host_state_gpu_member':       j.Value(1320)
						'host_entries_cpu_member':     j.Value(1328)
						'host_entries_gpu_member':     j.Value(1336)
						'state_bytes':                 j.Value(48)
						'entries_bytes':               j.Value(6144)
						'primary_large_region_offset': j.Value(160)
					}),
					j.Value(map[string]j.Value{
						'priority':                    j.Value(2)
						'command':                     j.Value('TA')
						'command_type':                j.Value(0)
						'host_object_member':          j.Value(1024)
						'host_state_cpu_member':       j.Value(1032)
						'host_state_gpu_member':       j.Value(1040)
						'host_entries_cpu_member':     j.Value(1048)
						'host_entries_gpu_member':     j.Value(1056)
						'state_bytes':                 j.Value(48)
						'entries_bytes':               j.Value(6144)
						'primary_large_region_offset': j.Value(192)
					}),
					j.Value(map[string]j.Value{
						'priority':                    j.Value(2)
						'command':                     j.Value('3D')
						'command_type':                j.Value(1)
						'host_object_member':          j.Value(1184)
						'host_state_cpu_member':       j.Value(1192)
						'host_state_gpu_member':       j.Value(1200)
						'host_entries_cpu_member':     j.Value(1208)
						'host_entries_gpu_member':     j.Value(1216)
						'state_bytes':                 j.Value(48)
						'entries_bytes':               j.Value(6144)
						'primary_large_region_offset': j.Value(224)
					}),
					j.Value(map[string]j.Value{
						'priority':                    j.Value(2)
						'command':                     j.Value('CL')
						'command_type':                j.Value(2)
						'host_object_member':          j.Value(1344)
						'host_state_cpu_member':       j.Value(1352)
						'host_state_gpu_member':       j.Value(1360)
						'host_entries_cpu_member':     j.Value(1368)
						'host_entries_gpu_member':     j.Value(1376)
						'state_bytes':                 j.Value(48)
						'entries_bytes':               j.Value(6144)
						'primary_large_region_offset': j.Value(256)
					}),
					j.Value(map[string]j.Value{
						'priority':                    j.Value(3)
						'command':                     j.Value('TA')
						'command_type':                j.Value(0)
						'host_object_member':          j.Value(1064)
						'host_state_cpu_member':       j.Value(1072)
						'host_state_gpu_member':       j.Value(1080)
						'host_entries_cpu_member':     j.Value(1088)
						'host_entries_gpu_member':     j.Value(1096)
						'state_bytes':                 j.Value(48)
						'entries_bytes':               j.Value(6144)
						'primary_large_region_offset': j.Value(288)
					}),
					j.Value(map[string]j.Value{
						'priority':                    j.Value(3)
						'command':                     j.Value('3D')
						'command_type':                j.Value(1)
						'host_object_member':          j.Value(1224)
						'host_state_cpu_member':       j.Value(1232)
						'host_state_gpu_member':       j.Value(1240)
						'host_entries_cpu_member':     j.Value(1248)
						'host_entries_gpu_member':     j.Value(1256)
						'state_bytes':                 j.Value(48)
						'entries_bytes':               j.Value(6144)
						'primary_large_region_offset': j.Value(320)
					}),
					j.Value(map[string]j.Value{
						'priority':                    j.Value(3)
						'command':                     j.Value('CL')
						'command_type':                j.Value(2)
						'host_object_member':          j.Value(1384)
						'host_state_cpu_member':       j.Value(1392)
						'host_state_gpu_member':       j.Value(1400)
						'host_entries_cpu_member':     j.Value(1408)
						'host_entries_gpu_member':     j.Value(1416)
						'state_bytes':                 j.Value(48)
						'entries_bytes':               j.Value(6144)
						'primary_large_region_offset': j.Value(352)
					}),
				])
			})
		}
		'recover_g17_data_master_doorbells' {
			return j.Value(map[string]j.Value{
				'message_type':               j.Value(131)
				'transport_host_member':      j.Value(6616)
				'transport_role':             j.Value(0)
				'transport_send_vtable_slot': j.Value(2216)
				'priority_shift':             j.Value(2)
				'priority_bits':              j.Value(3)
				'formula':                    j.Value('(0x83 << 48) | (priority << 2) | command_type')
				'commands':                   j.Value(map[string]j.Value{
					'TA': j.Value(map[string]j.Value{
						'command_type': j.Value(0)
						'low_bits':     j.Value(0)
					})
					'3D': j.Value(map[string]j.Value{
						'command_type': j.Value(1)
						'low_bits':     j.Value(1)
					})
					'CL': j.Value(map[string]j.Value{
						'command_type': j.Value(2)
						'low_bits':     j.Value(2)
					})
				})
			})
		}
		'recover_g17_channel_priority' {
			return j.Value(map[string]j.Value{
				'state_offset':        j.Value(40)
				'bytes':               j.Value(28)
				'reset_priority':      j.Value(4)
				'field_offsets':       j.Value([j.Value(40), j.Value(44), j.Value(48), j.Value(56),
					j.Value(60), j.Value(64)])
				'field_bytes':         j.Value([j.Value(4), j.Value(4), j.Value(8), j.Value(4),
					j.Value(4), j.Value(4)])
				'default_subpriority': j.Value(2)
				'profiles':            j.Value([
					j.Value(map[string]j.Value{
						'priority':         j.Value(0)
						'context_priority': j.Value(0)
						'qos':              j.Value(2)
						'fields':           j.Value([j.Value(0), j.Value(0),
							j.Value(u64(18446744073709486080)), j.Value(1), j.Value(2), j.Value(1)])
					}),
					j.Value(map[string]j.Value{
						'priority':         j.Value(1)
						'context_priority': j.Value(4)
						'qos':              j.Value(2)
						'fields':           j.Value([j.Value(1), j.Value(1),
							j.Value(u64(18446744069414584320)), j.Value(0), j.Value(2), j.Value(0)])
					}),
					j.Value(map[string]j.Value{
						'priority':         j.Value(2)
						'context_priority': j.Value(1)
						'qos':              j.Value(2)
						'fields':           j.Value([j.Value(2), j.Value(2),
							j.Value(u64(18446462598732840960)), j.Value(0), j.Value(2), j.Value(2)])
					}),
					j.Value(map[string]j.Value{
						'priority':         j.Value(3)
						'context_priority': j.Value(2)
						'qos':              j.Value(2)
						'fields':           j.Value([j.Value(3), j.Value(3), j.Value(0), j.Value(0),
							j.Value(2), j.Value(0)])
					}),
				])
			})
		}
		'recover_g17_channel_submit_info' {
			return j.Value(map[string]j.Value{
				'bytes':    j.Value(24)
				'fields':   j.Value(map[string]j.Value{
					'submission_index': j.Value(map[string]j.Value{
						'offset':            j.Value(0)
						'bytes':             j.Value(4)
						'source':            j.Value('uncached_control.write_index_after_pointer_publication')
						'outer_entry_bytes': j.Value(2)
					})
					'host_sequence':    j.Value(map[string]j.Value{
						'offset': j.Value(4)
						'bytes':  j.Value(4)
						'source': j.Value('channel.host_sequence_after_increment')
					})
					'channel_counter':  j.Value(map[string]j.Value{
						'offset':                j.Value(8)
						'bytes':                 j.Value(4)
						'source_channel_member': j.Value(240)
					})
					'reserved_00c':     j.Value(map[string]j.Value{
						'offset': j.Value(12)
						'bytes':  j.Value(4)
						'value':  j.Value(0)
					})
					'metadata':         j.Value(map[string]j.Value{
						'offset':                 j.Value(16)
						'bytes':                  j.Value(8)
						'selected_object_member': j.Value(72)
					})
				})
				'dispatch': j.Value(map[string]j.Value{
					'data_master_type_channel_member': j.Value(200)
					'accelerator_work_queue_member':   j.Value(200)
				})
			})
		}
		'recover_g17_channel_submission_flag' {
			return j.Value(map[string]j.Value{
				'channel_member':                         j.Value(60)
				'bytes':                                  j.Value(1)
				'initial':                                j.Value(0)
				'outer_flags_formula':                    j.Value('1 & ~channel_flag')
				'first_submission_flags':                 j.Value(1)
				'following_submission_flags':             j.Value(0)
				'mark_vtable_slot':                       j.Value(512)
				'mark_after_successful_outer_submission': j.Value(true)
				'unmark_vtable_slot':                     j.Value(520)
				'unmark_on_priority_change':              j.Value(true)
				'implementations':                        j.Value(1)
			})
		}
		'recover_g17_channel_pool_geometry' {
			return j.Value(map[string]j.Value{
				'channel_state':   j.Value(map[string]j.Value{
					'host_pool_member': j.Value(4552)
					'element_bytes':    j.Value(192)
					'caching':          j.Value(1)
				})
				'uncached_memory': j.Value(map[string]j.Value{
					'host_pool_member':           j.Value(4936)
					'element_base_bytes':         j.Value(112)
					'bytes_per_configured_queue': j.Value(128)
					'caching':                    j.Value(0)
				})
				'cached_memory':   j.Value(map[string]j.Value{
					'host_pool_member':           j.Value(5128)
					'element_base_bytes':         j.Value(112)
					'bytes_per_configured_queue': j.Value(128)
					'caching':                    j.Value(1)
				})
			})
		}
		'recover_g17_channel_layout' {
			return j.Value(map[string]j.Value{
				'host_channel_members':         j.Value(map[string]j.Value{
					'state_cpu':    j.Value(88)
					'uncached_cpu': j.Value(96)
					'cached_cpu':   j.Value(104)
					'ring_entries': j.Value(84)
					'state_gpu':    j.Value(128)
					'uncached_gpu': j.Value(136)
					'cached_gpu':   j.Value(144)
				})
				'state':                        j.Value(map[string]j.Value{
					'bytes':                j.Value(192)
					'uncached_gpu_address': j.Value(0)
					'cached_gpu_address':   j.Value(8)
					'context_cookie':       j.Value(16)
					'mode':                 j.Value(40)
					'value_048':            j.Value(72)
					'flag_084':             j.Value(132)
					'address_09c':          j.Value(156)
				})
				'uncached_control':             j.Value(map[string]j.Value{
					'header_bytes': j.Value(112)
					'read_index':   j.Value(0)
					'write_index':  j.Value(64)
					'sentinel':     j.Value(80)
					'ring_entries': j.Value(96)
				})
				'cached_command_pointer_bytes': j.Value(8)
				'enqueue':                      j.Value(map[string]j.Value{
					'reserved_entries':           j.Value(1)
					'pointer_barrier':            j.Value('dmb ish')
					'write_index_published_last': j.Value(true)
				})
			})
		}
		'recover_g17_relative_boost_frequency_table' {
			return j.Value(map[string]j.Value{
				'offset':                          j.Value(6408)
				'entries':                         j.Value(16)
				'base_state_property':             j.Value('gpu-perf-base-pstate')
				'base_state_scaled_source_offset': j.Value(69324)
				'frequency_source_offset':         j.Value(111384)
				'formula':                         j.Value('100 * (frequency - base_frequency) / (max_frequency - base_frequency)')
				'states_at_or_below_base':         j.Value(0)
				'maximum_state_value':             j.Value(100)
			})
		}
		'recover_g17_sram_power_scale_table' {
			return j.Value(map[string]j.Value{
				'offset':                    j.Value(6216)
				'entries':                   j.Value(16)
				'active_entries':            j.Value('gpu-perf-state-count')
				'state_count_source_offset': j.Value(111376)
				'accelerator_config_offset': j.Value(3344)
				'runtime_source_offset':     j.Value(196)
				'raw_float':                 j.Value(1065520988)
				'value':                     j.Value(j.Number{'1.0199999809265137'})
				'feature_bit':               j.Value(17)
				'producer_vtable_slot':      j.Value(3264)
				'producer':                  j.Value('__ZN32AGX·PI_300·X·A0·AcceleratorX33populatePowerEstimationConfigDataEj')
			})
		}
		'recover_g17_static_power_scale_table' {
			return j.Value(map[string]j.Value{
				'offset':                      j.Value(6280)
				'entries':                     j.Value(16)
				'values':                      j.Value([j.Value(0), j.Value(0), j.Value(0), j.Value(0),
					j.Value(0), j.Value(0), j.Value(0), j.Value(0), j.Value(0), j.Value(0), j.Value(0),
					j.Value(0), j.Value(0), j.Value(0), j.Value(0), j.Value(0)])
				'accelerator_config_offset':   j.Value(3408)
				'runtime_source_offset':       j.Value(260)
				'allocator':                   j.Value('_OSObject_typed_operator_new')
				'allocator_flag':              j.Value(4)
				'allocator_flag_name':         j.Value('Z_ZERO')
				'type_view_address':           j.Value(2097968)
				'type_bytes':                  j.Value(10528)
				'static_provider_vtable_slot': j.Value(3296)
				'static_provider':             j.Value('__ZN14AGXAccelerator23populateStaticPowerDataEv.8120')
			})
		}
		'recover_g17_secondary_performance_block' {
			return j.Value(map[string]j.Value{
				'populated_on_g17':     j.Value(false)
				'gate_chip_info_byte':  j.Value(133)
				'gate_reason':          j.Value("getProbeScore clears the chip-info record and no selected G17C reader writes +0x85, so the producer's TBZ always skips")
				'offset':               j.Value(7384)
				'zeroed_bytes':         j.Value(2120)
				'gate_byte':            j.Value(1285)
				'max_state_offset':     j.Value(7384)
				'frequency_offset':     j.Value(7388)
				'voltage_offset':       j.Value(7452)
				'sram_voltage_offset':  j.Value(8476)
				'row_bytes':            j.Value(64)
				'state_count_source':   j.Value(113496)
				'column_count_source':  j.Value(113500)
				'frequency_source':     j.Value(113504)
				'voltage_source':       j.Value(113568)
				'frequency_conversion': j.Value(map[string]j.Value{
					'input':       j.Value('Hz')
					'output':      j.Value('MHz')
					'multiplier':  j.Value(1125899907)
					'right_shift': j.Value(50)
				})
				'trailing_bytes':       j.Value(4)
			})
		}
		'recover_g17_final_late_controls' {
			return j.Value(map[string]j.Value{
				'converted_field': j.Value(map[string]j.Value{
					'config':          j.Value(9884)
					'firmware_member': j.Value(6840)
					'converter':       j.Value('__ZNK14AGXArmFirmware18convertGPUVAToFWVAEyb')
					'identity':        j.Value(true)
					'value':           j.Value(0)
				})
				'literal_field':   j.Value(map[string]j.Value{
					'config': j.Value(9920)
					'value':  j.Value(1)
				})
			})
		}
		'recover_g17_remaining_late_controls' {
			return j.Value(map[string]j.Value{
				'ones_run':     j.Value(map[string]j.Value{
					'offset': j.Value(9660)
					'bytes':  j.Value(48)
					'value':  j.Value(255)
				})
				'copied_bytes': j.Value(map[string]j.Value{
					'9976': j.Value(1776)
					'9977': j.Value(1784)
				})
				'guarded':      j.Value(map[string]j.Value{
					'offset':      j.Value(9644)
					'feature_bit': j.Value(38)
					'would_be':    j.Value(u64(4294967297))
					'written':     j.Value(false)
				})
			})
		}
		'recover_g17_cleared_accelerator_inputs' {
			return j.Value(map[string]j.Value{
				'accelerator_bytes': j.Value(117712)
				'zeroed_allocation': j.Value(true)
				'cleared_members':   j.Value([j.Value(1836), j.Value(1840), j.Value(63764),
					j.Value(63772), j.Value(63832)])
				'fields':            j.Value(map[string]j.Value{
					'9540': j.Value(1836)
					'9716': j.Value(1840)
					'9720': j.Value(63772)
					'9892': j.Value(63764)
					'9916': j.Value(63832)
				})
				'guarded_field':     j.Value(map[string]j.Value{
					'config': j.Value(9540)
					'note':   j.Value('only written when its source is nonzero, so it stays clear')
				})
			})
		}
		'recover_g17_unit_mask_field' {
			return j.Value(map[string]j.Value{
				'config_offset':            j.Value(9556)
				'identity_register':        j.Value(13647896)
				'nibble_products':          j.Value([
					j.Value(map[string]j.Value{
						'chip_info': j.Value(72)
						'shifts':    j.Value([j.Value(0), j.Value(16)])
					}),
					j.Value(map[string]j.Value{
						'chip_info': j.Value(76)
						'shifts':    j.Value([j.Value(4), j.Value(20)])
					}),
					j.Value(map[string]j.Value{
						'chip_info': j.Value(80)
						'shifts':    j.Value([j.Value(8), j.Value(24)])
					}),
				])
				'count_chip_info':          j.Value(80)
				'count_accelerator_member': j.Value(1232)
				'saturate_above':           j.Value(63)
				'formula':                  j.Value('count >= 64 ? 0xffffffff : low32(~(~0 << count))')
			})
		}
		'recover_g17_core_count_gate' {
			return j.Value(map[string]j.Value{
				'config_offset':   j.Value(9584)
				'gate':            j.Value(map[string]j.Value{
					'accelerator_byte': j.Value(1286)
					'chip_info_byte':   j.Value(134)
					'value':            j.Value(1)
					'always_set':       j.Value(true)
				})
				'selected':        j.Value('popcount')
				'unused_fallback': j.Value(map[string]j.Value{
					'accelerator_member': j.Value(1200)
					'chip_info':          j.Value(48)
					'reason':             j.Value('gate bit is always set, so this producer never runs')
				})
				'popcount_source': j.Value(map[string]j.Value{
					'accelerator_member': j.Value(1168)
					'chip_info':          j.Value(16)
					'words':              j.Value(3)
					'note':               j.Value('first pair is the cleared record head, so the select steps on by 0x10')
				})
				'mask_registers':  j.Value(map[string]j.Value{
					'base':        j.Value('getGPUPhysicalAddress')
					'base_source': j.Value('IOMemoryDescriptor::getPhysicalAddress of device memory 0')
					'offset':      j.Value(14685440)
					'words':       j.Value([j.Value(14685440), j.Value(14685444), j.Value(14685448)])
					'layout':      j.Value('words 0 and 1 form a 64-bit mask, word 2 a 32-bit mask')
				})
				'formula':         j.Value('popcount(mask0) + popcount(mask1)')
				'resolved':        j.Value(true)
			})
		}
		'recover_g17_chip_info_decode' {
			return j.Value(map[string]j.Value{
				'source_register': j.Value(13647888)
				'fields':          j.Value(map[string]j.Value{
					'power_group_count':   j.Value(map[string]j.Value{
						'chip_info':          j.Value(108)
						'accelerator_member': j.Value(1260)
						'shift':              j.Value(16)
						'mask':               j.Value(15)
					})
					'columns_per_group':   j.Value(map[string]j.Value{
						'shift': j.Value(8)
						'mask':  j.Value(255)
					})
					'power_column_count':  j.Value(map[string]j.Value{
						'chip_info':          j.Value(100)
						'accelerator_member': j.Value(1252)
						'formula':            j.Value('columns_per_group * power_group_count')
					})
					'units_per_column':    j.Value(map[string]j.Value{
						'chip_info': j.Value(120)
						'shift':     j.Value(0)
						'mask':      j.Value(255)
					})
					'scaled_column_count': j.Value(map[string]j.Value{
						'chip_info':          j.Value(48)
						'formula':            j.Value('power_column_count * units_per_column')
						'accelerator_member': j.Value(1200)
					})
				})
			})
		}
		'recover_g17_chip_info_registers' {
			return j.Value(map[string]j.Value{
				'register_block':             j.Value(13647872)
				'registers':                  j.Value(map[string]j.Value{
					'version':        j.Value(13647872)
					'count':          j.Value(13647880)
					'cluster_config': j.Value(13647888)
					'identity_14':    j.Value(13647892)
					'identity_18':    j.Value(13647896)
					'identity_1c':    j.Value(13647900)
				})
				'version_family_byte':        j.Value(map[string]j.Value{
					'shift': j.Value(24)
					'value': j.Value(11)
				})
				'variant_selector':           j.Value(map[string]j.Value{
					'shift': j.Value(16)
					'mask':  j.Value(255)
				})
				'variants':                   j.Value(map[string]j.Value{
					'2': j.Value(32)
					'3': j.Value(33)
					'4': j.Value(34)
				})
				'companion_values':           j.Value(map[string]j.Value{
					'2': j.Value(10)
					'3': j.Value(20)
					'4': j.Value(40)
				})
				'chip_info_variant_offset':   j.Value(32)
				'chip_info_companion_offset': j.Value(116)
				'accelerator_variant_member': j.Value(1184)
				'variant_consumers':          j.Value([
					j.Value('__ZN32AGX·PI_300·X·A0·AcceleratorX33populateMaximumPerformancePowerCSEv'),
					j.Value('__ZN32AGX·PI_300·X·A0·AcceleratorX22calculateVddGpuLeakageEddd'),
				])
			})
		}
		'recover_g17_core_mask_relay' {
			return j.Value(map[string]j.Value{
				'record_delta':        j.Value(1152)
				'accelerator_members': j.Value([j.Value(1152), j.Value(1160)])
				'chip_info_bytes':     j.Value([j.Value(0), j.Value(8)])
				'written':             j.Value(false)
				'writers':             j.Value([]j.Value{})
			})
		}
		'recover_g17_late_controls' {
			return j.Value(map[string]j.Value{
				'region':                     j.Value(map[string]j.Value{
					'offset': j.Value(9536)
					'bytes':  j.Value(464)
				})
				'producer':                   j.Value('__ZN14AGXArmFirmware16initFirmwareDataEv')
				'written_offsets':            j.Value(36)
				'feature_mask':               j.Value(u64(281475379494912))
				'feature_bit_fields':         j.Value(map[string]j.Value{
					'9628': j.Value(37)
					'9636': j.Value(38)
					'9652': j.Value(7)
					'9924': j.Value(53)
				})
				'fixed':                      j.Value(map[string]j.Value{
					'9536': j.Value(0)
					'9540': j.Value(0)
					'9544': j.Value(0)
					'9564': j.Value(0)
					'9568': j.Value(0)
					'9588': j.Value(0)
					'9592': j.Value(1)
					'9612': j.Value(0)
					'9628': j.Value(0)
					'9632': j.Value(1)
					'9636': j.Value(0)
					'9640': j.Value(0)
					'9644': j.Value(0)
					'9652': j.Value(0)
					'9656': j.Value(0)
					'9660': j.Value(255)
					'9692': j.Value(255)
					'9708': j.Value(0)
					'9712': j.Value(0)
					'9716': j.Value(0)
					'9720': j.Value(0)
					'9728': j.Value(0)
					'9884': j.Value(0)
					'9892': j.Value(0)
					'9896': j.Value(0)
					'9916': j.Value(0)
					'9920': j.Value(1)
					'9924': j.Value(0)
					'9952': j.Value(0)
					'9968': j.Value(1)
					'9976': j.Value(0)
					'9977': j.Value(0)
					'9990': j.Value(0)
					'9994': j.Value(0)
				})
				'wide_fixed':                 j.Value(map[string]j.Value{
					'9568': j.Value(16)
					'9728': j.Value(8)
					'9968': j.Value(8)
				})
				'core_mask_relay':            j.Value(map[string]j.Value{
					'record_delta':        j.Value(1152)
					'accelerator_members': j.Value([j.Value(1152), j.Value(1160)])
					'chip_info_bytes':     j.Value([j.Value(0), j.Value(8)])
					'written':             j.Value(false)
					'writers':             j.Value([]j.Value{})
				})
				'cleared_accelerator_inputs': j.Value(map[string]j.Value{
					'accelerator_bytes': j.Value(117712)
					'zeroed_allocation': j.Value(true)
					'cleared_members':   j.Value([j.Value(1836), j.Value(1840), j.Value(63764),
						j.Value(63772), j.Value(63832)])
					'fields':            j.Value(map[string]j.Value{
						'9540': j.Value(1836)
						'9716': j.Value(1840)
						'9720': j.Value(63772)
						'9892': j.Value(63764)
						'9916': j.Value(63832)
					})
					'guarded_field':     j.Value(map[string]j.Value{
						'config': j.Value(9540)
						'note':   j.Value('only written when its source is nonzero, so it stays clear')
					})
				})
				'remaining_late_controls':    j.Value(map[string]j.Value{
					'ones_run':     j.Value(map[string]j.Value{
						'offset': j.Value(9660)
						'bytes':  j.Value(48)
						'value':  j.Value(255)
					})
					'copied_bytes': j.Value(map[string]j.Value{
						'9976': j.Value(1776)
						'9977': j.Value(1784)
					})
					'guarded':      j.Value(map[string]j.Value{
						'offset':      j.Value(9644)
						'feature_bit': j.Value(38)
						'would_be':    j.Value(u64(4294967297))
						'written':     j.Value(false)
					})
				})
				'final_late_controls':        j.Value(map[string]j.Value{
					'converted_field': j.Value(map[string]j.Value{
						'config':          j.Value(9884)
						'firmware_member': j.Value(6840)
						'converter':       j.Value('__ZNK14AGXArmFirmware18convertGPUVAToFWVAEyb')
						'identity':        j.Value(true)
						'value':           j.Value(0)
					})
					'literal_field':   j.Value(map[string]j.Value{
						'config': j.Value(9920)
						'value':  j.Value(1)
					})
				})
				'derived':                    j.Value([j.Value(9556), j.Value(9584)])
				'runtime_dependent':          j.Value([]j.Value{})
				'complete':                   j.Value(true)
			})
		}
		'recover_g17_afr_relative_boost_frequency_table' {
			return j.Value(map[string]j.Value{
				'offset':                          j.Value(6536)
				'entries':                         j.Value(16)
				'domain':                          j.Value('AFR')
				'state_property':                  j.Value('afr-perf-states')
				'base_state_scaled_source_offset': j.Value(69324)
				'state_count_source_offset':       j.Value(115944)
				'frequency_source_offset':         j.Value(115952)
				'formula':                         j.Value('100 * (frequency - base_frequency) / (max_frequency - base_frequency)')
				'states_at_or_below_base':         j.Value(0)
				'maximum_state_value':             j.Value(100)
			})
		}
		'recover_g17_perf_state_map_block' {
			return j.Value(map[string]j.Value{
				'offset':             j.Value(6600)
				'bytes':              j.Value(128)
				'entries_per_bank':   j.Value(16)
				'source_offsets':     j.Value([j.Value(109128), j.Value(109192)])
				'enable_byte_offset': j.Value(133)
				'enable_byte_value':  j.Value(0)
				'parser_vtable_slot': j.Value(4632)
				'parser':             j.Value('__ZN20AGXFamilyAccelerator21parsePerfStateMapRegsEv.8015')
				'banks':              j.Value([
					j.Value(map[string]j.Value{
						'offset': j.Value(6600)
						'values': j.Value([j.Value(0), j.Value(1), j.Value(2), j.Value(3), j.Value(4),
							j.Value(5), j.Value(6), j.Value(7), j.Value(8), j.Value(9), j.Value(10),
							j.Value(11), j.Value(12), j.Value(13), j.Value(14), j.Value(15)])
					}),
					j.Value(map[string]j.Value{
						'offset': j.Value(6664)
						'values': j.Value([j.Value(0), j.Value(0), j.Value(0), j.Value(0), j.Value(0),
							j.Value(0), j.Value(0), j.Value(0), j.Value(0), j.Value(0), j.Value(0),
							j.Value(0), j.Value(0), j.Value(0), j.Value(0), j.Value(0)])
					}),
				])
			})
		}
		'recover_g17_aux_performance_layout' {
			return j.Value(map[string]j.Value{
				'properties':           j.Value([j.Value('cs-perf-states'), j.Value('afr-perf-states')])
				'device_tree_encoding': j.Value(map[string]j.Value{
					'word_bytes':      j.Value(8)
					'header':          j.Value([j.Value('rail_count'), j.Value('state_count')])
					'records':         j.Value([j.Value('voltage_uv'), j.Value('frequency_hz')])
					'trailer':         j.Value('default_sram_voltage_uv_per_rail')
					'voltage_divisor': j.Value(1000)
					'sram_policy':     j.Value('max(core_mv, default_sram_mv)')
				})
				'source_layout':        j.Value(map[string]j.Value{
					'bytes':               j.Value(328)
					'state_capacity':      j.Value(16)
					'rail_capacity':       j.Value(2)
					'state_count_offset':  j.Value(0)
					'rail_count_offset':   j.Value(4)
					'frequency_offset':    j.Value(8)
					'voltage_offset':      j.Value(72)
					'sram_voltage_offset': j.Value(200)
				})
				'firmware_blocks':      j.Value([
					j.Value(map[string]j.Value{
						'domain': j.Value('CS')
						'offset': j.Value(6728)
						'bytes':  j.Value(328)
					}),
					j.Value(map[string]j.Value{
						'domain': j.Value('AFR')
						'offset': j.Value(7056)
						'bytes':  j.Value(328)
					}),
				])
				'firmware_layout':      j.Value(map[string]j.Value{
					'max_state_offset':    j.Value(0)
					'domain_cap_offset':   j.Value(4)
					'frequency_offset':    j.Value(8)
					'voltage_offset':      j.Value(72)
					'sram_voltage_offset': j.Value(200)
				})
				'domain_cap':           j.Value(14)
				'cap_vtable_slot':      j.Value(4568)
			})
		}
		else { panic(operation) }
	}
}
