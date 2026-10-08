module g17expr

import traceanalysis as j
import json2

// Checked producer instruction evidence and recovered fixed byte-field maps.
// These literals contain no recovery algorithm; checks and analysis live in
// command.v, emission.v, pool.v, render.v and transport.v.

fn command_symbol(name string) string {
	return match name {
		'AGX_COMMAND_QUEUE_INIT' {
			'__ZN15AGXCommandQueue4initEP5IOGPUP11IOGPUDeviceP30IOGPUDeviceNewCommandQueueArgs'
		}
		'AGX_SHARED_INIT' { '__ZN9AGXShared4initEP5IOGPUP4tasky' }
		'AGX_SHARED_SET_APP_GPU_ROLE' { '__ZN9AGXShared16set_app_gpu_roleEi13eIOGPUAppRole' }
		'AGX_WORK_QUEUE_INIT' { '__ZN12AGXWorkQueue4initEP5IOGPUPK17IOGPUCommandQueueiiy' }
		'ALLOCATE_3D_WORK_QUEUE' { '__ZN15AGXCommandQueue24allocate3DWorkQueueInnerEbj' }
		'ALLOCATE_CL_WORK_QUEUE' { '__ZN15AGXCommandQueue24allocateCLWorkQueueInnerEj' }
		'ALLOCATE_SCHEDULER_STATE' { '__ZN15AGXCommandQueue22allocateSchedulerStateEv' }
		'ALLOC_3D_COMMAND_DESCRIPTOR' { '__ZNK22AGX3DCommandDescriptor9MetaClass5allocEv' }
		'ALLOC_TA_COMMAND_DESCRIPTOR' { '__ZNK22AGXTACommandDescriptor9MetaClass5allocEv' }
		'ARM_ALLOC_FIRMWARE_DATA' { '__ZN14AGXArmFirmware17allocFirmwareDataEv' }
		'BASE_ALLOC_FIRMWARE_DATA' { '__ZN11AGXFirmware17allocFirmwareDataEv' }
		'BASE_CONFIGURE_DEVICE' { '__ZN14AGXAccelerator15configureDeviceEP9IOService' }
		'CHANNEL_INIT' {
			'__ZN10AGXChannel4initEPK15AGXCommandQueueP12AGXWorkQueueiiy19_AGFIDataMasterType'
		}
		'COMMAND_POOL_CREATE_BACKING' {
			'__ZN9PoolClassI20AGFIChannelCommand3DE13createBackingEjP14AGXAcceleratoryb'
		}
		'COMPLETE_COMMAND_3D' { '__ZN22AGX3DCommandDescriptor8completeEv' }
		'CONFIGURE_POOL_ELEMENT_SIZES' { '__ZN11AGXFirmware25configurePoolElementSizesEv' }
		'COPY_3D_COMMON_PASSTHROUGH' {
			'__ZN28AGXHardwareKernelCommandUtil27copy3DCommonPassthroughDataEP22AGX3DCommandDescriptorRK21AGX3DCommandCommonRec'
		}
		'G17_CONFIGURE_DEVICE' {
			'__ZN32AGX·PI_300·X·A0·AcceleratorX15configureDeviceEP9IOService'
		}
		'GENERATE_REGISTER_LIST_3D' {
			'__ZN33AGX·PI_300·X·A0·3DChannelSKSM25generateRegisterListFor3DEP20AGFIChannelCommand3DP22AGX3DCommandDescriptor'
		}
		'INIT_3D_COMMAND_DESCRIPTOR' {
			'__ZN22AGX3DCommandDescriptor4initEP5IOGPUP17IOGPUCommandQueueP9IOGPUTaskPKcyP19AGXDebugBufferShmem'
		}
		'INIT_TA_COMMAND_DESCRIPTOR' {
			'__ZN22AGXTACommandDescriptor4initEP5IOGPUP17IOGPUCommandQueueP9IOGPUTaskPKcyP19AGXDebugBufferShmem'
		}
		'IOGPU_CHANNEL_INIT' { '__ZN12IOGPUChannel4initEP5IOGPUi' }
		'IOGPU_COMMAND_DESCRIPTOR_INIT' {
			'__ZN22IOGPUCommandDescriptor4initEP5IOGPUP17IOGPUCommandQueueP9IOGPUTask'
		}
		'IOGPU_COMMAND_QUEUE_INIT' {
			'__ZN17IOGPUCommandQueue4initEP5IOGPUP11IOGPUDeviceP30IOGPUDeviceNewCommandQueueArgs'
		}
		'IOGPU_DEVICE_INIT' { '__ZN11IOGPUDevice4initEP5IOGPUP4task' }
		'IOGPU_WORK_QUEUE_INIT' { '__ZN14IOGPUWorkQueue4initEP5IOGPUPK17IOGPUCommandQueuei' }
		'PARSE_HARDWARE_KERNEL_COMMAND' {
			'__ZN24AGXHardwareKernelCommand16parseAndValidateER21AGXSharedStreamParserS1_'
		}
		'PARSE_RENDER_HARDWARE_KERNEL_COMMAND' {
			'__ZN30AGXRenderHardwareKernelCommand16parseAndValidateER21AGXSharedStreamParser'
		}
		'PI300_CONFIGURE_DEVICE' {
			'__ZN31AGX·PI_300·X·A0·Accelerator15configureDeviceEP9IOService'
		}
		'PROCESS_RENDER_SETUP' {
			'__ZN15AGXCommandQueue18processRenderSetupERK24AGXHardwareKernelCommandRK30AGXRenderHardwareKernelCommandRK23AGXSegmentKernelCommandyyP21CompositeSubtypeStateR22AGXTACommandDescriptorR22AGX3DCommandDescriptorP18AGXAllocationList2bP11AGXResourceR10IOGPUEventPPSJ_SM_P14AGX3DWorkQueuePPN12AGXWorkQueue9HashEntryEbbR13AGXUMADescRecP20AGXUniqueResourceSet'
		}
		'RCE_ENCODE_ENTRY' { '__ZNK36AGX·PI_300·X·A0·RCEBufferEncoder11encodeEntryEPvjhy' }
		'REQUEST_CHANNEL_COMMAND_BARRIER' { '__ZN11AGXFirmware28requestChannelCommandBarrierEPy' }
		'RESET_TIMESTAMP_QUEUE' { '__ZN17AGXTimeStampQueue24resetTimeStampQueueStateEv' }
		'SCHEDULER_STATE_STACK_INIT' {
			'__ZN24AGXFirmwareResourceStackI19_AGFISchedulerState15AGXCommandQueueLj64ELj256EE4initEP14AGXAcceleratoryPKcy17AGXCachingOptionsP9IOGPUTask19AGXFWPoolShrinkMode'
		}
		'SCHEDULER_STATE_STACK_VTABLE' {
			'__ZTV24AGXFirmwareResourceStackI19_AGFISchedulerState15AGXCommandQueueLj64ELj256EE'
		}
		'SET_KICK_CHANNEL_QOS' { '__ZN14AGXArmFirmware17setKickChannelQosEjj' }
		'SUBMIT_NOP_UNPREPARED' {
			'__ZN10AGXChannel19submitNopUnpreparedEP22IOGPUCommandDescriptor22AGFIChannelCommandType19_AGFIDataMasterType'
		}
		'TIMESTAMP_QUEUE_INIT' { '__ZN17AGXTimeStampQueue4initEP14AGXAccelerator' }
		else { panic(name) }
	}
}

fn command_number(name string) int {
	return match name {
		'G17_COMMAND_3D_BYTES' { 8768 }
		'INTERFACE_MAGIC' { 904030701134283968 }
		'SCHEDULER_STATE_STACK_INIT_SLOT' { 32 }
		'TA_COMMAND_POOL' { 5704 }
		else { panic(name) }
	}
}

fn command_initializers() map[string]string {
	return {
		'TA': '__ZN12AGXTAChannel4initEPK15AGXCommandQueueP12AGXWorkQueueiiy'
		'3D': '__ZN12AGX3DChannel4initEPK15AGXCommandQueueP12AGXWorkQueueiiy'
		'CL': '__ZN12AGXCLChannel4initEPK15AGXCommandQueueP12AGXWorkQueueiiy'
	}
}

fn command_words(label string) map[int]u32 {
	return match label {
		'G17 command-stream record parse' {
			{
				0x4:   u32(0xf9400829)
				0x8:   u32(0xf9400028)
				0xc:   u32(0xeb08013f)
				0x14:  u32(0xb1030128)
				0x1c:  u32(0xf940042a)
				0x58:  u32(0xf9000828)
				0x70:  u32(0x52802009)
				0x74:  u32(0xb9000c09)
				0x80:  u32(0xb940ac09)
				0x84:  u32(0xab090109)
				0x98:  u32(0xf9000829)
				0xa4:  u32(0x3d803400)
				0xa8:  u32(0xf9007008)
				0xb4:  u32(0xb940a009)
				0xdc:  u32(0x91004129)
				0x11c: u32(0x3dc00100)
				0x120: u32(0x3c8e8000)
				0x124: u32(0xb940e80a)
				0x128: u32(0xab0a056a)
				0x158: u32(0xb940ec08)
				0x15c: u32(0x8b080508)
				0x160: u32(0xab080d48)
				0x170: u32(0xf900800a)
				0x17c: u32(0xb9409809)
				0x194: u32(0xb9409c0b)
				0x23c: u32(0x3dc00100)
				0x240: u32(0x3d804800)
				0x244: u32(0xb941200b)
				0x264: u32(0xf900980a)
				0x278: u32(0xb941240b)
				0x298: u32(0xf9009c0b)
				0x2ac: u32(0xb941280d)
				0x2cc: u32(0xf900a00d)
				0x2d8: u32(0xb9412c08)
				0x2f4: u32(0xf900a408)
				0x1c4: u32(0xb940a409)
				0x1e0: u32(0xb940a80c)
				0x370: u32(0x3dc00160)
				0x374: u32(0x3d805400)
				0x378: u32(0xb941580a)
				0x37c: u32(0xb9415c0c)
				0x380: u32(0xb941540d)
				0x384: u32(0xb941500e)
				0x388: u32(0xb0e01ad)
				0x3a8: u32(0xf900b008)
				0x3b4: u32(0xb0a0188)
				0x3d0: u32(0xf900b408)
				0x3d4: u32(0x52800028)
				0x3d8: u32(0x39002008)
				0x3ec: u32(0x52802049)
			}
		}
		'G17 render command payload parse' {
			{
				0x4:   u32(0xf9400828)
				0x8:   u32(0xf9400029)
				0x14:  u32(0xf9000c1f)
				0x20:  u32(0xb9000c09)
				0x2c:  u32(0xb1274109)
				0x40:  u32(0xf9000829)
				0x44:  u32(0xf9000c08)
				0x4c:  u32(0x91032109)
				0x64:  u32(0xad010400)
				0x70:  u32(0xf9409d09)
				0x74:  u32(0xf9004809)
				0x7c:  u32(0x3d801800)
				0x80:  u32(0x91136109)
				0xb4:  u32(0x3c898000)
				0xb8:  u32(0x3dc05100)
				0xbc:  u32(0x3d804400)
				0xc8:  u32(0xf940c109)
				0xcc:  u32(0xf900a809)
				0xdc:  u32(0x3dc15500)
				0xe0:  u32(0x3d800120)
				0xf0:  u32(0xf942c90a)
				0xf4:  u32(0xf900cc0a)
				0x100: u32(0x91093109)
				0x10c: u32(0xb901a80a)
				0x118: u32(0xf9432d0a)
				0x124: u32(0xf900012a)
				0x12c: u32(0x12000169)
				0x134: u32(0x3962c109)
				0x138: u32(0x12000129)
				0x144: u32(0xb901bc09)
				0x184: u32(0xad000520)
				0x188: u32(0xf9433509)
				0x18c: u32(0xf9010009)
				0x190: u32(0x39608509)
				0x194: u32(0x39082009)
				0x1a8: u32(0x3d808400)
				0x1c0: u32(0xad120400)
				0x1c8: u32(0x12000149)
				0x1d4: u32(0x1200012c)
				0x1e0: u32(0x1200018c)
				0x1ec: u32(0x1200018c)
				0x1f4: u32(0x395f8108)
				0x1f8: u32(0x4a0b0108)
				0x200: u32(0x3600004a)
				0x204: u32(0x360000a9)
				0x208: u32(0x52800028)
				0x20c: u32(0x39002008)
				0x21c: u32(0x52800149)
			}
		}
		'G17 3D common passthrough copy' {
			{
				0x4:   u32(0x9106e029)
				0x8:   u32(0x9117a008)
				0xc:   u32(0xf940002a)
				0x10:  u32(0xf902740a)
				0x90:  u32(0x3d800100)
				0xa8:  u32(0xf9025c0a)
				0xac:  u32(0xf902580b)
				0x140: u32(0x3d81d400)
				0x19c: u32(0x3d81d000)
				0x1a4: u32(0xb9088809)
				0x1b4: u32(0x3d82bc00)
				0x1bc: u32(0x3d82c000)
				0x1c4: u32(0x12000129)
				0x1c8: u32(0x391f8009)
				0x20c: u32(0xb9041009)
				0x228: u32(0x3d815101)
				0x230: u32(0xfd059c00)
				0x238: u32(0xb90b4008)
				0x24c: u32(0xd65f03c0)
			}
		}
		'G17 3D common passthrough source' {
			{
				0x1f28: u32(0xf9400f48)
				0x1f70: u32(0x910b4101)
				0x1f74: u32(0xaa1903e0)
			}
		}
		'G17 3D descriptor allocation' { {
			0x18: u32(0x52818801)
		} }
		'G17 normalized render descriptor fields' {
			{
				0x48:   u32(0x911e70b7)
				0x244:  u32(0xf90033f7)
				0x1804: u32(0xf94033f7)
				0x1cec: u32(0x394a0b48)
				0x1cf4: u32(0x12000108)
				0x1cf8: u32(0x3937f2e8)
				0x20e0: u32(0xfd400120)
				0x20e4: u32(0xfd025320)
				0x20e8: u32(0xb9426749)
				0x20ec: u32(0xb904ab29)
				0x2134: u32(0x3946e349)
				0x2138: u32(0x12000129)
				0x213c: u32(0x392642e9)
				0x2140: u32(0x394a0349)
				0x2144: u32(0x12000129)
				0x2148: u32(0x392632e9)
				0x2190: u32(0x3946e348)
				0x2194: u32(0x12000108)
				0x2198: u32(0x39225f28)
				0x219c: u32(0x394a0748)
				0x21a0: u32(0x12000108)
				0x21a4: u32(0x39224f28)
				0x21a8: u32(0x39482348)
				0x21ac: u32(0x39258328)
				0x21b0: u32(0x394a0f48)
				0x21b4: u32(0x36000068)
				0x21b8: u32(0x52800028)
				0x21c0: u32(0xf9400b28)
				0x21c4: u32(0x529efd29)
				0x21c8: u32(0x8b090108)
				0x21cc: u32(0x39400108)
				0x21d0: u32(0x12000108)
				0x21d4: u32(0x3930e328)
			}
		}
		'G17 descriptor accelerator retention' {
			{
				0x20: u32(0xaa0103f7)
				0x24: u32(0xaa0003f4)
				0x60: u32(0xaa1403f8)
				0x64: u32(0xf8038f1f)
				0x68: u32(0xf81d8317)
			}
		}
		'G17 descriptor fallback device bit' {
			{
				0x34:  u32(0x529ee508)
				0x38:  u32(0x8b080018)
				0x5a8: u32(0x6f00e401)
				0x5ac: u32(0x3d802f01)
				0x5b0: u32(0x7901831f)
			}
		}
		'G17 TA render passthrough' {
			{
				0x1d64: u32(0xf9400f48)
				0x1d68: u32(0x3dc00100)
				0x1d80: u32(0xf9401909)
				0x1db0: u32(0x3dc01900)
				0x1dc0: u32(0x3dc07d00)
				0x1e44: u32(0x39491909)
				0x1e60: u32(0x3948f509)
				0x1ecc: u32(0xb9423909)
				0x1ee8: u32(0x3dc0a100)
				0x1f1c: u32(0x39492908)
				0x1f28: u32(0xf9400f48)
				0x1f38: u32(0xb948110a)
				0x1f70: u32(0x910b4101)
				0x1f7c: u32(0xf9400f48)
				0x1f80: u32(0xf9436109)
				0x1fa8: u32(0xf9439509)
				0x2058: u32(0xfd437d00)
				0x2068: u32(0x911c2109)
				0x2084: u32(0xbd47d900)
				0x2088: u32(0x2f08a400)
				0x208c: u32(0x2f0797c0)
				0x2090: u32(0xe001800)
				0x20bc: u32(0xb9480909)
				0x20cc: u32(0x39200328)
			}
		}
		'G17 3D descriptor allocation defaults' {
			{
				0x18: u32(0x52818801)
				0x98: u32(0xb9096808)
				0xa8: u32(0x2f00e5e1)
				0xac: u32(0xfd055001)
				0xb4: u32(0xb90b6008)
				0xd8: u32(0x3930e01f)
			}
		}
		'G17 3D descriptor initialization defaults' {
			{
				0x114: u32(0x9112c260)
				0x118: u32(0x52806a01)
				0x128: u32(0xb9090274)
				0x188: u32(0xb9014674)
				0x1d0: u32(0xf9461668)
				0x1d4: u32(0x9254a508)
				0x1d8: u32(0xf9061668)
				0x1e0: u32(0x52802029)
				0x1e4: u32(0x79000109)
				0x1ec: u32(0xb9040275)
				0x230: u32(0xb9041268)
				0x234: u32(0xb90c3275)
				0x238: u32(0xb902d674)
			}
		}
		'G17 TA descriptor allocation defaults' {
			{
				0x18:  u32(0x5282b601)
				0x7c:  u32(0xb9096808)
				0x8c:  u32(0x2f00e5e1)
				0x90:  u32(0xfd055001)
				0x98:  u32(0xb90b6008)
				0x114: u32(0xb9126c08)
				0x124: u32(0xfd09d401)
				0x134: u32(0xb913e808)
			}
		}
		'G17 TA descriptor initialization defaults' {
			{
				0xdc:  u32(0x12800015)
				0xe0:  u32(0xb9120a75)
				0x164: u32(0xb9126675)
				0x168: u32(0xb9014675)
				0x1a8: u32(0x52800048)
				0x1ac: u32(0xb90f6268)
				0x1b0: u32(0xf94a5a68)
				0x1b4: u32(0x9254a508)
				0x1b8: u32(0xf90a5a68)
				0x1bc: u32(0xb90e1a75)
			}
		}
		'G17 common channel-command fields' {
			{
				0x24:  u32(0xaa0303f6)
				0x218: u32(0xb80222f6)
				0x21c: u32(0x52800028)
				0x220: u32(0xb801a2e8)
				0x224: u32(0xb80322ff)
				0x228: u32(0xf80622ff)
			}
		}
		'G17 register-entry codec' {
			{
				0x4:  u32(0xb9400028)
				0x8:  u32(0x121f7908)
				0xc:  u32(0x120e4108)
				0x10: u32(0x121d3849)
				0x14: u32(0x33000069)
				0x18: u32(0x2a080128)
				0x1c: u32(0xb9000028)
				0x20: u32(0xf8004024)
				0x24: u32(0xd65f03c0)
			}
		}
		'G17 3D register-list pass induction' {
			{
				0x30: u32(0xd2800017)
				0xbc: u32(0x910006f7)
				0xc4: u32(0xf10012ff)
				0xc8: u32(0x540134a0)
				0xf8: u32(0x35000317)
			}
		}
		'G17 3D register-list framing' {
			{
				0x34:  u32(0x528000d8)
				0x38:  u32(0x72bfff98)
				0xc0:  u32(0x911c82b5)
				0xc4:  u32(0xf10012ff)
				0xcc:  u32(0x8b150329)
				0xd0:  u32(0x91028128)
				0xd4:  u32(0xb907a93f)
				0xd8:  u32(0xf942226a)
				0xe4:  u32(0xf903d12a)
				0x100: u32(0xa18014a)
				0x188: u32(0xf800410a)
				0x190: u32(0x794e1509)
				0x194: u32(0x11003129)
				0x198: u32(0x790e1509)
				0x19c: u32(0x794e110a)
				0x1a0: u32(0x1100054a)
				0x1a4: u32(0x790e110a)
			}
		}
		'G17 3D register-list publication' {
			{
				0x2560: u32(0x794f532a)
				0x2564: u32(0x7901032a)
				0x275c: u32(0x7910627f)
				0x2760: u32(0xf9041e7f)
				0x2764: u32(0x91210268)
				0x277c: u32(0xf943d329)
				0x2780: u32(0xf9041669)
				0x2784: u32(0x79410329)
				0x2788: u32(0x79106269)
				0x278c: u32(0x913b2329)
				0x2790: u32(0x5280006a)
				0x2794: u32(0xf85f812b)
				0x2798: u32(0xf81f810b)
				0x279c: u32(0x7940012b)
				0x27a0: u32(0x7801050b)
				0x27a4: u32(0x911c8129)
			}
		}
		'G17 channel-command pool sizes' {
			{
				0x4:  u32(0x52813808)
				0x8:  u32(0xf9010c08)
				0x1c: u32(0xad110400)
				0x20: u32(0x52800808)
				0x24: u32(0xf9012408)
				0x30: u32(0x3d809400)
				0x34: u32(0x52801009)
				0x38: u32(0x4e080d00)
				0x3c: u32(0xf9013409)
				0x48: u32(0xad138400)
				0x4c: u32(0xf9014808)
			}
		}
		'G17 channel-command slot allocation' {
			{
				0x14: u32(0xf94bb008)
				0x24: u32(0xf94bc000)
				0x2c: u32(0xb9577268)
				0x34: u32(0xb9577669)
				0x78: u32(0xb9576a68)
				0x7c: u32(0x1b087eb6)
				0xac: u32(0x8b160008)
				0xb0: u32(0xf9000288)
				0xdc: u32(0xb9177668)
				0xec: u32(0xf94bae68)
				0xf0: u32(0x8b160114)
			}
		}
		'G17 command-pool fallback capacity' { {
			0x88: u32(0x52800a09)
			0x8c: u32(0xb9071a69)
		} }
		'G17 command-pool capacity selection' {
			{
				0x30: u32(0x91404408)
				0x34: u32(0x91058114)
				0xa8: u32(0xb9400288)
				0xac: u32(0x35000048)
				0xb0: u32(0xb9471a68)
				0xc4: u32(0xb9072a68)
			}
		}
		'G17 work-command pool count' {
			{
				0x38:  u32(0xf9414c01)
				0x3c:  u32(0x91404428)
				0x40:  u32(0x91058108)
				0x44:  u32(0xb9400119)
				0x48:  u32(0x35000059)
				0x4c:  u32(0xb9471839)
				0x300: u32(0xb190734)
				0x580: u32(0x5282d108)
				0x594: u32(0xaa1403e1)
				0x5a0: u32(0x5282d908)
				0x5b4: u32(0xaa1403e1)
				0x5c0: u32(0x5282e108)
				0x5d4: u32(0xaa1403e1)
			}
		}
		'G17 command-pool backing geometry' {
			{
				0x28:  u32(0xf9000002)
				0x2c:  u32(0xf9401017)
				0x68:  u32(0x2a1503e8)
				0x6c:  u32(0x52800029)
				0x70:  u32(0x1ad82129)
				0x78:  u32(0x9b0826e8)
				0x7c:  u32(0xd1000508)
				0x80:  u32(0xcb0903e9)
				0x84:  u32(0x8a090115)
				0x29c: u32(0xf9000674)
				0x2c8: u32(0xf9000a60)
				0x2d0: u32(0xf9401268)
				0x2d4: u32(0x9ac80aa8)
				0x2d8: u32(0xb9002a68)
				0x2e4: u32(0xf9000e60)
			}
		}
		'G17 3D command reclamation' {
			{
				0x16c: u32(0xf9421e68)
				0x1f4: u32(0xf942d934)
				0x1f8: u32(0xb9569a89)
				0x1fc: u32(0x4b090108)
				0x200: u32(0xf94b5689)
				0x204: u32(0x9ac90915)
				0x208: u32(0xf94b6280)
				0x210: u32(0xf94b5288)
				0x214: u32(0x8b150109)
				0x218: u32(0x39400129)
				0x21c: u32(0x34000069)
				0x220: u32(0x51000529)
				0x224: u32(0x38356909)
				0x238: u32(0xf9021e7f)
			}
		}
		'IOGPU command-queue device binding' {
			{
				0xf8:  u32(0xf9024a74)
				0xfc:  u32(0xb9406288)
				0x100: u32(0xb9049a68)
			}
		}
		'IOGPU device process identifier' { {
			0xe4:  u32(0xb9006260)
			0x108: u32(0xb9006260)
		} }
		'AGXShared default app GPU role' { {
			0x100: u32(0x52800048)
			0x104: u32(0x39048268)
		} }
		'AGXShared app GPU role bound' {
			{
				0x2ec: u32(0x7100111f)
				0x2f0: u32(0x54000d22)
				0x2f8: u32(0x39048118)
			}
		}
		'G17 configured work-queue default' {
			{
				0x84: u32(0xf9436a68)
				0x88: u32(0x52800a09)
				0x8c: u32(0xb9071a69)
			}
		}
		'G17 timestamp-state pool' {
			{
				0x38: u32(0xf9414c01)
				0x3c: u32(0x91404428)
				0x40: u32(0x91058108)
				0x44: u32(0xb9400119)
				0x48: u32(0x35000059)
				0x4c: u32(0xb9471839)
				0x50: u32(0x52825108)
				0x54: u32(0x8b080274)
				0x74: u32(0xaa1403e0)
				0x78: u32(0x52800302)
				0x7c: u32(0x52800124)
				0x80: u32(0x52800005)
				0x84: u32(0xd2800006)
				0x88: u32(0x52800007)
			}
		}
		'G17 command-queue ring request' {
			{
				0xc8: u32(0xf9429e68)
				0xcc: u32(0x91404509)
				0xd0: u32(0x91058129)
				0xd4: u32(0xb9400129)
				0xd8: u32(0x35000049)
				0xdc: u32(0xb9471909)
				0xe0: u32(0xb9088269)
			}
		}
		'G17 AGX work-queue base initialization' {
			{
				0x2c: u32(0xf940a908)
				0x30: u32(0xaa0903f1)
				0x34: u32(0xf2e76f11)
				0x38: u32(0xd73f0911)
			}
		}
		'IOGPU work-queue ring request' {
			{
				0x18: u32(0xaa0303f7)
				0x50: u32(0xf9002268)
				0x54: u32(0xb9005677)
			}
		}
		'G17 render work-channel inputs' {
			{
				0x58:  u32(0xf9429e81)
				0x5c:  u32(0xb9488283)
				0xa0:  u32(0xf9434288)
				0xa4:  u32(0xf9401515)
				0x12c: u32(0xaa1503e5)
				0x1a8: u32(0xf9434288)
				0x1ac: u32(0xf9401501)
			}
		}
		'G17 compute work-channel inputs' {
			{
				0x4c:  u32(0xf9429e81)
				0x50:  u32(0xb9488283)
				0x8c:  u32(0xf9434288)
				0x90:  u32(0xf9401515)
				0x118: u32(0xaa1503e5)
			}
		}
		'G17 timestamp-queue mappings' {
			{
				0x58:  u32(0xb9003a7f)
				0x5c:  u32(0xf942da95)
				0x64:  u32(0x8b0802b4)
				0x24c: u32(0x8b160008)
				0x250: u32(0xf9001668)
				0x2c0: u32(0x8b160008)
				0x2d4: u32(0xf9001268)
			}
		}
		'G17 timestamp-state reset' {
			{
				0x4:  u32(0xf9401008)
				0x8:  u32(0xa9007d1f)
				0xc:  u32(0xf900091f)
				0x18: u32(0xa9422009)
				0x1c: u32(0xf9000528)
				0x20: u32(0xb9403808)
				0x24: u32(0x7100091f)
				0x28: u32(0x1a9f17e8)
				0x2c: u32(0xf9401009)
				0x30: u32(0x29027d28)
			}
		}
		'G17 scheduler-state pool binding' {
			{
				0xd54: u32(0xf9414e61)
				0xd58: u32(0x52829908)
				0xd5c: u32(0x8b080274)
				0xd7c: u32(0xaa1403e0)
				0xd80: u32(0x52800802)
				0xd84: u32(0x52800124)
				0xd88: u32(0x52800025)
				0xd8c: u32(0xd2800006)
				0xd90: u32(0x52800007)
			}
		}
		'G17 scheduler-state pool geometry' {
			{
				0x20: u32(0xaa0203f5)
				0x68: u32(0xf9005275)
				0x7c: u32(0x8b150509)
				0x80: u32(0xd1000529)
				0x84: u32(0xcb0803e8)
				0x88: u32(0x8a080128)
				0x8c: u32(0xf9002e68)
				0x90: u32(0x9ad50908)
				0x94: u32(0xb9006268)
			}
		}
		'G17 scheduler-state queue publication' {
			{
				0x28:  u32(0xf9429c08)
				0x2c:  u32(0xf942d915)
				0x30:  u32(0x52829908)
				0xec:  u32(0xb9552abb)
				0xf0:  u32(0x1adb0b1c)
				0x144: u32(0xf9045660)
				0x1e8: u32(0x1b1be389)
				0x1ec: u32(0x9b097ed6)
				0x220: u32(0x8b160008)
				0x224: u32(0xf9045e68)
				0x2a8: u32(0xf9045268)
				0x348: u32(0xb908b278)
			}
		}
		'G17 scheduler-state initial content' {
			{
				0x3bc: u32(0xf9445268)
				0x3c0: u32(0xf900191f)
				0x3c8: u32(0xad008100)
				0x3cc: u32(0x3d800100)
				0x3d0: u32(0xf9445268)
				0x3d4: u32(0x529fffe9)
				0x3d8: u32(0x79000109)
				0x3dc: u32(0x52800020)
				0x3e0: u32(0x39001500)
				0x3e4: u32(0x52801fe9)
				0x3e8: u32(0x3900cd09)
				0x3ec: u32(0xb802211f)
				0x3f0: u32(0xf9424a69)
				0x3f4: u32(0x39448129)
				0x3f8: u32(0x39009909)
			}
		}
		'G17 channel-state input copies' {
			{
				0x5c: u32(0xb9404c08)
				0x64: u32(0xb9004928)
				0x78: u32(0xf9407c0a)
				0x7c: u32(0xf809c12a)
				0x88: u32(0xb940540b)
				0x8c: u32(0xb900614b)
			}
		}
		'G17 kick-channel QoS setter' {
			{
				0x4:  u32(0xf9466808)
				0x8:  u32(0x5298e509)
				0xc:  u32(0x8b090108)
				0x10: u32(0x52800029)
				0x14: u32(0xb9000109)
				0x18: u32(0xf941c008)
				0x1c: u32(0xb9005101)
				0x20: u32(0xb9004d02)
			}
		}
		'G17 channel input seeding' {
			{
				0x68:  u32(0xb9449aa8)
				0x78:  u32(0xf9445ea9)
				0x7c:  u32(0xf9007e69)
				0x94:  u32(0x12800009)
				0x98:  u32(0x29092269)
				0x5b8: u32(0x52801009)
				0x5bc: u32(0x710202df)
				0x5c0: u32(0x1a8932c9)
				0x5c4: u32(0x531c6d29)
				0x5c8: u32(0xb9005669)
			}
		}
		'G17 IOGPU channel initialization' {
			{
				0x48: u32(0x91052109)
				0x4c: u32(0xf940a508)
				0x50: u32(0xf9429c21)
				0x54: u32(0x52801002)
				0x60: u32(0xd73f0911)
			}
		}
		'IOGPU channel identity store' {
			{
				0x18: u32(0xaa0203f4)
				0x40: u32(0xf9000a75)
				0x44: u32(0xb9001a74)
			}
		}
		'G17 firmware-start notification' {
			{
				0x18:  u32(0x52833b08)
				0x1c:  u32(0x8b080008)
				0x20:  u32(0x52800709)
				0x24:  u32(0x9ba97c29)
				0x2c:  u32(0x8b29c114)
				0x3c:  u32(0x52800035)
				0x40:  u32(0x3900a295)
				0x48:  u32(0xf9001a80)
				0xfc:  u32(0xf9400288)
				0x100: u32(0xd2e01021)
				0x104: u32(0xb340ac01)
				0x12c: u32(0x91226202)
				0x130: u32(0xf9444e10)
			}
		}
		'G17 AKF message handling' {
			{
				0x14: u32(0xd370d428)
				0x18: u32(0xf100251f)
				0x20: u32(0xf100091f)
				0x60: u32(0x52834908)
				0x68: u32(0x8b080000)
				0x80: u32(0xb91a4a7f)
				0x88: u32(0xd2e01128)
				0x8c: u32(0xf90003e8)
				0x90: u32(0xf94cee60)
				0xa4: u32(0xd2811611)
				0xa8: u32(0x8b110210)
				0xac: u32(0xf9400208)
				0xc0: u32(0xf94d0a60)
				0xe8: u32(0x9122c208)
				0xec: u32(0xf9445a09)
			}
		}
		'G17 dual-role firmware boot' {
			{
				0x1c: u32(0x91400415)
				0x20: u32(0x392802bf)
				0x24: u32(0x3928e2bf)
				0x28: u32(0x392b16bf)
				0x2c: u32(0xf94cec00)
				0x30: u32(0xf94cfe61)
				0x44: u32(0xd2811111)
				0x48: u32(0x8b110210)
				0x4c: u32(0xf9400208)
				0x5c: u32(0xf94d0a60)
				0x60: u32(0xf94d1a61)
				0x88: u32(0x91222208)
				0x8c: u32(0xf9444609)
				0x9c: u32(0x7100029f)
				0xa0: u32(0x7a401804)
				0xa8: u32(0x396b16a8)
			}
		}
		'G17 RTBuddy endpoint matching' {
			{
				0x1c:  u32(0xb9408828)
				0x20:  u32(0x7100851f)
				0x28:  u32(0x7100811f)
				0x30:  u32(0xf9009674)
				0x100: u32(0xf9009a74)
			}
		}
		'G17 RTBuddy message receive' { {
			0xc:  u32(0xf9409400)
			0x10: u32(0x52800002)
		} }
		'G17 RTBuddy message send' {
			{
				0x8:  u32(0xf9409400)
				0x28: u32(0xd2803d11)
				0x2c: u32(0x8b110210)
				0x30: u32(0xf9400208)
				0x3c: u32(0xd2800002)
				0x40: u32(0x52800023)
			}
		}
		'G17 RTBuddy endpoint enable' {
			{
				0x14: u32(0xf9409400)
				0x28: u32(0xd2802e11)
				0x2c: u32(0x8b110210)
				0x30: u32(0xf9400208)
				0x3c: u32(0xf9409a60)
				0x64: u32(0x9105c208)
				0x68: u32(0xf940ba09)
				0x78: u32(0xf940ba60)
				0x7c: u32(0xb9412261)
			}
		}
		'G17 RTBuddy receive forwarding' { {
			0x4: u32(0xf940b808)
			0x8: u32(0xb9412002)
		} }
		else { panic(label) }
	}
}

fn command_metadata(operation string) map[string]j.Value {
	return match operation {
		'recover_g17_boot_transport' {
			j.Value(map[string]j.Value{
				'role_count':                      j.Value(2)
				'role_record_host_member':         j.Value(6616)
				'role_record_stride':              j.Value(56)
				'transport_member':                j.Value(0)
				'root_mapping_member':             j.Value(32)
				'started_member':                  j.Value(40)
				'start_timestamp_member':          j.Value(48)
				'transport_host_members':          j.Value([j.Value(6616), j.Value(6672)])
				'root_mapping_host_members':       j.Value([j.Value(6648), j.Value(6704)])
				'transport_boot_vtable_slot':      j.Value(2184)
				'init_message':                    j.Value(u64(36310271995674624))
				'init_address_bits':               j.Value(44)
				'init_send_vtable_slot':           j.Value(2200)
				'receive_type_shift':              j.Value(48)
				'receive_type_bits':               j.Value(6)
				'callback_type':                   j.Value(2)
				'ready_type':                      j.Value(9)
				'ready_ack_message':               j.Value(u64(38562071809359872))
				'ready_ack_guard_host_member':     j.Value(6728)
				'ready_ack_transport_vtable_slot': j.Value(2224)
				'ready_ack_transport_count':       j.Value(2)
				'shared_ready_flag_host_member':   j.Value(6853)
				'requires_both_transport_boots':   j.Value(true)
			}).as_map()
		}
		'recover_g17_rtbuddy_endpoints' {
			j.Value(map[string]j.Value{
				'message_endpoint':              j.Value(32)
				'doorbell_endpoint':             j.Value(33)
				'endpoint_service_id_member':    j.Value(136)
				'message_endpoint_host_member':  j.Value(296)
				'doorbell_endpoint_host_member': j.Value(304)
				'endpoint_enable_vtable_slot':   j.Value(368)
				'message_send_vtable_slot':      j.Value(488)
				'firmware_role_host_member':     j.Value(288)
				'arm_firmware_host_member':      j.Value(368)
				'receive_forwards_role':         j.Value(true)
			}).as_map()
		}
		'recover_g17_handoff' {
			j.Value(map[string]j.Value{
				'bytes':                 j.Value(1608)
				'magic':                 j.Value(u64(5412482327169204226))
				'magic_offset':          j.Value(0)
				'firmware_magic_offset': j.Value(8)
				'lock_offsets':          j.Value([j.Value(16), j.Value(17)])
				'turn_offset':           j.Value(20)
				'current_slot_offset':   j.Value(24)
				'current_slot_initial':  j.Value(u64(4294967295))
				'flush_offset':          j.Value(32)
				'flush_records':         j.Value(65)
				'flush_record_bytes':    j.Value(24)
				'mismatch_flag_offset':  j.Value(1592)
				'tail_offset':           j.Value(1600)
			}).as_map()
		}
		'recover_g17_command_stream_format' {
			j.Value(map[string]j.Value{
				'parser':                      j.Value(map[string]j.Value{
					'start':  j.Value(0)
					'end':    j.Value(8)
					'cursor': j.Value(16)
				})
				'header_bytes':                j.Value(192)
				'command_header_offset':       j.Value(16)
				'payload_length_offset':       j.Value(156)
				'payload_bounds_member':       j.Value(208)
				'payload_start_member':        j.Value(224)
				'primary_extension':           j.Value(map[string]j.Value{
					'stream_length_offset': j.Value(144)
					'header_bytes':         j.Value(16)
					'count_offsets':        j.Value([j.Value(0), j.Value(4)])
					'element_bytes':        j.Value([j.Value(2), j.Value(24)])
					'header_member':        j.Value(232)
					'first_array_member':   j.Value(248)
					'second_array_member':  j.Value(256)
				})
				'auxiliary_stream_extensions': j.Value(map[string]j.Value{
					'u16_arrays': j.Value(map[string]j.Value{
						'flag_offset':          j.Value(136)
						'stream_length_offset': j.Value(140)
						'header_bytes':         j.Value(16)
						'count_offsets':        j.Value([j.Value(0), j.Value(4), j.Value(8),
							j.Value(12)])
						'element_bytes':        j.Value([j.Value(2), j.Value(2), j.Value(2),
							j.Value(2)])
						'header_member':        j.Value(288)
						'array_members':        j.Value([j.Value(304), j.Value(312), j.Value(320),
							j.Value(328)])
					})
					'u64_groups': j.Value(map[string]j.Value{
						'flag_offset':          j.Value(148)
						'stream_length_offset': j.Value(152)
						'header_bytes':         j.Value(16)
						'count_offsets':        j.Value([j.Value(0), j.Value(4), j.Value(8),
							j.Value(12)])
						'element_bytes':        j.Value(8)
						'group_count_indices':  j.Value([
							j.Value([j.Value(0), j.Value(1)]),
							j.Value([j.Value(2), j.Value(3)]),
						])
						'header_member':        j.Value(336)
						'group_array_members':  j.Value([j.Value(352), j.Value(360)])
					})
				})
				'success':                     j.Value(map[string]j.Value{
					'member': j.Value(8)
					'value':  j.Value(1)
				})
				'error_markers':               j.Value(map[string]j.Value{
					'member':           j.Value(12)
					'terminator':       j.Value(256)
					'auxiliary_stream': j.Value(258)
				})
				'terminator_marker':           j.Value(256)
				'terminator_member':           j.Value(12)
				'producer':                    j.Value('__ZN24AGXHardwareKernelCommand16parseAndValidateER21AGXSharedStreamParserS1_')
			}).as_map()
		}
		'recover_g17_render_payload_format' {
			j.Value(map[string]j.Value{
				'parser':                 j.Value(map[string]j.Value{
					'start':  j.Value(0)
					'end':    j.Value(8)
					'cursor': j.Value(16)
				})
				'payload_bytes':          j.Value(2512)
				'payload_pointer_member': j.Value(24)
				'copy_ranges':            j.Value([
					j.Value(map[string]j.Value{
						'payload_offset': j.Value(200)
						'command_member': j.Value(32)
						'bytes':          j.Value(120)
					}),
					j.Value(map[string]j.Value{
						'payload_offset': j.Value(1240)
						'command_member': j.Value(152)
						'bytes':          j.Value(120)
					}),
					j.Value(map[string]j.Value{
						'payload_offset': j.Value(320)
						'command_member': j.Value(272)
						'bytes':          j.Value(72)
					}),
					j.Value(map[string]j.Value{
						'payload_offset': j.Value(1360)
						'command_member': j.Value(344)
						'bytes':          j.Value(72)
					}),
					j.Value(map[string]j.Value{
						'payload_offset': j.Value(588)
						'command_member': j.Value(416)
						'bytes':          j.Value(12)
					}),
					j.Value(map[string]j.Value{
						'payload_offset': j.Value(1624)
						'command_member': j.Value(428)
						'bytes':          j.Value(12)
					}),
					j.Value(map[string]j.Value{
						'payload_offset': j.Value(564)
						'command_member': j.Value(444)
						'bytes':          j.Value(4)
					}),
					j.Value(map[string]j.Value{
						'payload_offset': j.Value(607)
						'command_member': j.Value(475)
						'bytes':          j.Value(32)
					}),
					j.Value(map[string]j.Value{
						'payload_offset': j.Value(1640)
						'command_member': j.Value(512)
						'bytes':          j.Value(8)
					}),
					j.Value(map[string]j.Value{
						'payload_offset': j.Value(2081)
						'command_member': j.Value(520)
						'bytes':          j.Value(1)
					}),
					j.Value(map[string]j.Value{
						'payload_offset': j.Value(2112)
						'command_member': j.Value(528)
						'bytes':          j.Value(112)
					}),
				])
				'bit_fields':             j.Value([
					j.Value(map[string]j.Value{
						'payload_offset': j.Value(576)
						'command_member': j.Value(440)
						'mask':           j.Value(1)
					}),
					j.Value(map[string]j.Value{
						'payload_offset': j.Value(2224)
						'command_member': j.Value(441)
						'mask':           j.Value(1)
					}),
					j.Value(map[string]j.Value{
						'payload_offset': j.Value(583)
						'command_member': j.Value(448)
						'mask':           j.Value(1)
					}),
					j.Value(map[string]j.Value{
						'payload_offset': j.Value(604)
						'command_member': j.Value(472)
						'mask':           j.Value(1)
					}),
					j.Value(map[string]j.Value{
						'payload_offset': j.Value(605)
						'command_member': j.Value(473)
						'mask':           j.Value(1)
					}),
					j.Value(map[string]j.Value{
						'payload_offset': j.Value(606)
						'command_member': j.Value(474)
						'mask':           j.Value(1)
					}),
					j.Value(map[string]j.Value{
						'payload_offset': j.Value(572)
						'command_member': j.Value(640)
						'mask':           j.Value(1)
					}),
					j.Value(map[string]j.Value{
						'payload_offset': j.Value(1606)
						'command_member': j.Value(641)
						'mask':           j.Value(1)
					}),
					j.Value(map[string]j.Value{
						'payload_offset': j.Value(584)
						'command_member': j.Value(642)
						'mask':           j.Value(1)
					}),
					j.Value(map[string]j.Value{
						'payload_offset': j.Value(1616)
						'command_member': j.Value(643)
						'mask':           j.Value(1)
					}),
				])
				'validation':             j.Value([
					j.Value(map[string]j.Value{
						'operation': j.Value('equal_bits')
						'left':      j.Value(map[string]j.Value{
							'payload_offset': j.Value(2016)
							'bit':            j.Value(0)
						})
						'right':     j.Value(map[string]j.Value{
							'payload_offset': j.Value(576)
							'bit':            j.Value(0)
						})
					}),
					j.Value(map[string]j.Value{
						'operation': j.Value('implies')
						'condition': j.Value(map[string]j.Value{
							'payload_offset': j.Value(572)
							'bit':            j.Value(0)
						})
						'required':  j.Value(map[string]j.Value{
							'payload_offset': j.Value(1606)
							'bit':            j.Value(0)
						})
					}),
				])
				'success':                j.Value(map[string]j.Value{
					'member': j.Value(8)
					'value':  j.Value(1)
				})
				'error_markers':          j.Value(map[string]j.Value{
					'member':     j.Value(12)
					'framing':    j.Value(256)
					'validation': j.Value(10)
				})
				'producer':               j.Value('__ZN30AGXRenderHardwareKernelCommand16parseAndValidateER21AGXSharedStreamParser')
			}).as_map()
		}
		'recover_g17_render_descriptor_fields' {
			j.Value(map[string]j.Value{
				'source_stage':            j.Value('normalized_render_command')
				'command_bytes':           j.Value(644)
				'descriptor_bytes':        j.Value(5552)
				'descriptor_alias':        j.Value(map[string]j.Value{
					'source_argument': j.Value(5)
					'addend':          j.Value(1948)
				})
				'direct_write_count':      j.Value(8)
				'direct_fields':           j.Value([
					j.Value(map[string]j.Value{
						'command_member':    j.Value(642)
						'payload_offset':    j.Value(584)
						'descriptor_member': j.Value(5528)
						'bytes':             j.Value(1)
						'producer_offset':   j.Value(7416)
						'mask':              j.Value(1)
					}),
					j.Value(map[string]j.Value{
						'command_member':    j.Value(604)
						'payload_offset':    j.Value(2188)
						'descriptor_member': j.Value(1184)
						'bytes':             j.Value(8)
						'producer_offset':   j.Value(8420)
					}),
					j.Value(map[string]j.Value{
						'command_member':    j.Value(612)
						'payload_offset':    j.Value(2196)
						'descriptor_member': j.Value(1192)
						'bytes':             j.Value(4)
						'producer_offset':   j.Value(8428)
					}),
					j.Value(map[string]j.Value{
						'command_member':    j.Value(440)
						'payload_offset':    j.Value(576)
						'descriptor_member': j.Value(4396)
						'bytes':             j.Value(1)
						'producer_offset':   j.Value(8508)
						'mask':              j.Value(1)
					}),
					j.Value(map[string]j.Value{
						'command_member':    j.Value(640)
						'payload_offset':    j.Value(572)
						'descriptor_member': j.Value(4392)
						'bytes':             j.Value(1)
						'producer_offset':   j.Value(8520)
						'mask':              j.Value(1)
					}),
					j.Value(map[string]j.Value{
						'command_member':    j.Value(440)
						'payload_offset':    j.Value(576)
						'descriptor_member': j.Value(2199)
						'bytes':             j.Value(1)
						'producer_offset':   j.Value(8600)
						'mask':              j.Value(1)
					}),
					j.Value(map[string]j.Value{
						'command_member':    j.Value(641)
						'payload_offset':    j.Value(1606)
						'descriptor_member': j.Value(2195)
						'bytes':             j.Value(1)
						'producer_offset':   j.Value(8612)
						'mask':              j.Value(1)
					}),
					j.Value(map[string]j.Value{
						'command_member':    j.Value(520)
						'payload_offset':    j.Value(2081)
						'descriptor_member': j.Value(2400)
						'bytes':             j.Value(1)
						'producer_offset':   j.Value(8620)
					}),
				])
				'conditional_field':       j.Value(map[string]j.Value{
					'command_member':    j.Value(643)
					'payload_offset':    j.Value(1616)
					'descriptor_member': j.Value(3128)
					'bytes':             j.Value(1)
					'condition_mask':    j.Value(1)
					'nonzero_value':     j.Value(1)
					'zero_source':       j.Value(map[string]j.Value{
						'descriptor_object_pointer_member': j.Value(16)
						'object_role':                      j.Value('IOGPU_accelerator')
						'accelerator_member':               j.Value(63465)
						'mask':                             j.Value(1)
						'value':                            j.Value(0)
						'producer':                         j.Value('__ZN14AGXAccelerator15configureDeviceEP9IOService')
						'producer_offset':                  j.Value(1456)
					})
					'producer_offset':   j.Value(8660)
				})
				'total_descriptor_writes': j.Value(9)
				'counting_note':           j.Value('this stage has nine descriptor writes; it is separate from the eight boolean mask chains in copy3DCommonPassthroughData')
				'producer':                j.Value('__ZN15AGXCommandQueue18processRenderSetupERK24AGXHardwareKernelCommandRK30AGXRenderHardwareKernelCommandRK23AGXSegmentKernelCommandyyP21CompositeSubtypeStateR22AGXTACommandDescriptorR22AGX3DCommandDescriptorP18AGXAllocationList2bP11AGXResourceR10IOGPUEventPPSJ_SM_P14AGX3DWorkQueuePPN12AGXWorkQueue9HashEntryEbbR13AGXUMADescRecP20AGXUniqueResourceSet')
			}).as_map()
		}
		'recover_g17_3d_common_passthrough' {
			j.Value(map[string]j.Value{
				'descriptor_bytes': j.Value(3136)
				'source':           j.Value(map[string]j.Value{
					'payload_pointer_member': j.Value(24)
					'payload_offset':         j.Value(720)
					'bytes':                  j.Value(1004)
				})
				'copy_ranges':      j.Value([
					j.Value(map[string]j.Value{
						'source_offset':     j.Value(0)
						'descriptor_member': j.Value(1256)
						'bytes':             j.Value(128)
					}),
					j.Value(map[string]j.Value{
						'source_offset':     j.Value(128)
						'descriptor_member': j.Value(1512)
						'bytes':             j.Value(48)
					}),
					j.Value(map[string]j.Value{
						'source_offset':     j.Value(224)
						'descriptor_member': j.Value(1208)
						'bytes':             j.Value(8)
					}),
					j.Value(map[string]j.Value{
						'source_offset':     j.Value(232)
						'descriptor_member': j.Value(1200)
						'bytes':             j.Value(8)
					}),
					j.Value(map[string]j.Value{
						'source_offset':     j.Value(248)
						'descriptor_member': j.Value(1608)
						'bytes':             j.Value(16)
					}),
					j.Value(map[string]j.Value{
						'source_offset':     j.Value(264)
						'descriptor_member': j.Value(1624)
						'bytes':             j.Value(8)
					}),
					j.Value(map[string]j.Value{
						'source_offset':     j.Value(272)
						'descriptor_member': j.Value(1632)
						'bytes':             j.Value(16)
					}),
					j.Value(map[string]j.Value{
						'source_offset':     j.Value(288)
						'descriptor_member': j.Value(1688)
						'bytes':             j.Value(8)
					}),
					j.Value(map[string]j.Value{
						'source_offset':     j.Value(296)
						'descriptor_member': j.Value(1736)
						'bytes':             j.Value(8)
					}),
					j.Value(map[string]j.Value{
						'source_offset':     j.Value(304)
						'descriptor_member': j.Value(1768)
						'bytes':             j.Value(8)
					}),
					j.Value(map[string]j.Value{
						'source_offset':     j.Value(312)
						'descriptor_member': j.Value(1792)
						'bytes':             j.Value(8)
					}),
					j.Value(map[string]j.Value{
						'source_offset':     j.Value(320)
						'descriptor_member': j.Value(1648)
						'bytes':             j.Value(8)
					}),
					j.Value(map[string]j.Value{
						'source_offset':     j.Value(328)
						'descriptor_member': j.Value(1696)
						'bytes':             j.Value(8)
					}),
					j.Value(map[string]j.Value{
						'source_offset':     j.Value(336)
						'descriptor_member': j.Value(1744)
						'bytes':             j.Value(8)
					}),
					j.Value(map[string]j.Value{
						'source_offset':     j.Value(344)
						'descriptor_member': j.Value(1776)
						'bytes':             j.Value(8)
					}),
					j.Value(map[string]j.Value{
						'source_offset':     j.Value(352)
						'descriptor_member': j.Value(1800)
						'bytes':             j.Value(8)
					}),
					j.Value(map[string]j.Value{
						'source_offset':     j.Value(360)
						'descriptor_member': j.Value(1664)
						'bytes':             j.Value(8)
					}),
					j.Value(map[string]j.Value{
						'source_offset':     j.Value(368)
						'descriptor_member': j.Value(1712)
						'bytes':             j.Value(8)
					}),
					j.Value(map[string]j.Value{
						'source_offset':     j.Value(376)
						'descriptor_member': j.Value(1752)
						'bytes':             j.Value(8)
					}),
					j.Value(map[string]j.Value{
						'source_offset':     j.Value(384)
						'descriptor_member': j.Value(1808)
						'bytes':             j.Value(8)
					}),
					j.Value(map[string]j.Value{
						'source_offset':     j.Value(392)
						'descriptor_member': j.Value(1832)
						'bytes':             j.Value(8)
					}),
					j.Value(map[string]j.Value{
						'source_offset':     j.Value(400)
						'descriptor_member': j.Value(1672)
						'bytes':             j.Value(8)
					}),
					j.Value(map[string]j.Value{
						'source_offset':     j.Value(408)
						'descriptor_member': j.Value(1720)
						'bytes':             j.Value(8)
					}),
					j.Value(map[string]j.Value{
						'source_offset':     j.Value(416)
						'descriptor_member': j.Value(1760)
						'bytes':             j.Value(8)
					}),
					j.Value(map[string]j.Value{
						'source_offset':     j.Value(424)
						'descriptor_member': j.Value(1816)
						'bytes':             j.Value(8)
					}),
					j.Value(map[string]j.Value{
						'source_offset':     j.Value(432)
						'descriptor_member': j.Value(1840)
						'bytes':             j.Value(8)
					}),
					j.Value(map[string]j.Value{
						'source_offset':     j.Value(440)
						'descriptor_member': j.Value(1856)
						'bytes':             j.Value(16)
					}),
					j.Value(map[string]j.Value{
						'source_offset':     j.Value(456)
						'descriptor_member': j.Value(1872)
						'bytes':             j.Value(16)
					}),
					j.Value(map[string]j.Value{
						'source_offset':     j.Value(472)
						'descriptor_member': j.Value(1848)
						'bytes':             j.Value(8)
					}),
					j.Value(map[string]j.Value{
						'source_offset':     j.Value(240)
						'descriptor_member': j.Value(1248)
						'bytes':             j.Value(8)
					}),
					j.Value(map[string]j.Value{
						'source_offset':     j.Value(480)
						'descriptor_member': j.Value(2040)
						'bytes':             j.Value(8)
					}),
					j.Value(map[string]j.Value{
						'source_offset':     j.Value(488)
						'descriptor_member': j.Value(2768)
						'bytes':             j.Value(4)
					}),
					j.Value(map[string]j.Value{
						'source_offset':     j.Value(496)
						'descriptor_member': j.Value(2776)
						'bytes':             j.Value(8)
					}),
					j.Value(map[string]j.Value{
						'source_offset':     j.Value(504)
						'descriptor_member': j.Value(1968)
						'bytes':             j.Value(8)
					}),
					j.Value(map[string]j.Value{
						'source_offset':     j.Value(512)
						'descriptor_member': j.Value(1984)
						'bytes':             j.Value(4)
					}),
					j.Value(map[string]j.Value{
						'source_offset':     j.Value(680)
						'descriptor_member': j.Value(2024)
						'bytes':             j.Value(8)
					}),
					j.Value(map[string]j.Value{
						'source_offset':     j.Value(872)
						'descriptor_member': j.Value(1960)
						'bytes':             j.Value(8)
					}),
					j.Value(map[string]j.Value{
						'source_offset':     j.Value(176)
						'descriptor_member': j.Value(1936)
						'bytes':             j.Value(8)
					}),
					j.Value(map[string]j.Value{
						'source_offset':     j.Value(184)
						'descriptor_member': j.Value(1944)
						'bytes':             j.Value(4)
					}),
					j.Value(map[string]j.Value{
						'source_offset':     j.Value(192)
						'descriptor_member': j.Value(1888)
						'bytes':             j.Value(16)
					}),
					j.Value(map[string]j.Value{
						'source_offset':     j.Value(208)
						'descriptor_member': j.Value(1904)
						'bytes':             j.Value(16)
					}),
					j.Value(map[string]j.Value{
						'source_offset':     j.Value(880)
						'descriptor_member': j.Value(2184)
						'bytes':             j.Value(4)
					}),
					j.Value(map[string]j.Value{
						'source_offset':     j.Value(900)
						'descriptor_member': j.Value(1040)
						'bytes':             j.Value(4)
					}),
					j.Value(map[string]j.Value{
						'source_offset':     j.Value(928)
						'descriptor_member': j.Value(2784)
						'bytes':             j.Value(16)
					}),
					j.Value(map[string]j.Value{
						'source_offset':     j.Value(944)
						'descriptor_member': j.Value(2800)
						'bytes':             j.Value(16)
					}),
					j.Value(map[string]j.Value{
						'source_offset':     j.Value(960)
						'descriptor_member': j.Value(2816)
						'bytes':             j.Value(16)
					}),
					j.Value(map[string]j.Value{
						'source_offset':     j.Value(976)
						'descriptor_member': j.Value(2856)
						'bytes':             j.Value(16)
					}),
					j.Value(map[string]j.Value{
						'source_offset':     j.Value(992)
						'descriptor_member': j.Value(2872)
						'bytes':             j.Value(8)
					}),
					j.Value(map[string]j.Value{
						'source_offset':     j.Value(1000)
						'descriptor_member': j.Value(2880)
						'bytes':             j.Value(4)
					}),
				])
				'bit_fields':       j.Value([
					j.Value(map[string]j.Value{
						'source_offset':     j.Value(885)
						'descriptor_member': j.Value(2188)
						'mask':              j.Value(1)
					}),
					j.Value(map[string]j.Value{
						'source_offset':     j.Value(888)
						'descriptor_member': j.Value(2197)
						'mask':              j.Value(1)
					}),
					j.Value(map[string]j.Value{
						'source_offset':     j.Value(889)
						'descriptor_member': j.Value(2198)
						'mask':              j.Value(1)
					}),
					j.Value(map[string]j.Value{
						'source_offset':     j.Value(891)
						'descriptor_member': j.Value(2200)
						'mask':              j.Value(1)
					}),
					j.Value(map[string]j.Value{
						'source_offset':     j.Value(892)
						'descriptor_member': j.Value(2402)
						'mask':              j.Value(1)
					}),
					j.Value(map[string]j.Value{
						'source_offset':     j.Value(893)
						'descriptor_member': j.Value(2403)
						'mask':              j.Value(1)
					}),
					j.Value(map[string]j.Value{
						'source_offset':     j.Value(894)
						'descriptor_member': j.Value(2201)
						'mask':              j.Value(1)
					}),
					j.Value(map[string]j.Value{
						'source_offset':     j.Value(895)
						'descriptor_member': j.Value(2016)
						'mask':              j.Value(1)
					}),
				])
				'mask_operations':  j.Value([
					j.Value(map[string]j.Value{
						'producer_offset':   j.Value(452)
						'source_offset':     j.Value(895)
						'descriptor_member': j.Value(2016)
						'mask':              j.Value(1)
					}),
					j.Value(map[string]j.Value{
						'producer_offset':   j.Value(464)
						'source_offset':     j.Value(894)
						'descriptor_member': j.Value(2201)
						'mask':              j.Value(1)
					}),
					j.Value(map[string]j.Value{
						'producer_offset':   j.Value(476)
						'source_offset':     j.Value(885)
						'descriptor_member': j.Value(2188)
						'mask':              j.Value(1)
					}),
					j.Value(map[string]j.Value{
						'producer_offset':   j.Value(488)
						'source_offset':     j.Value(888)
						'descriptor_member': j.Value(2197)
						'mask':              j.Value(1)
					}),
					j.Value(map[string]j.Value{
						'producer_offset':   j.Value(500)
						'source_offset':     j.Value(889)
						'descriptor_member': j.Value(2198)
						'mask':              j.Value(1)
					}),
					j.Value(map[string]j.Value{
						'producer_offset':   j.Value(512)
						'source_offset':     j.Value(891)
						'descriptor_member': j.Value(2200)
						'mask':              j.Value(1)
					}),
					j.Value(map[string]j.Value{
						'producer_offset':   j.Value(532)
						'source_offset':     j.Value(892)
						'descriptor_member': j.Value(2402)
						'mask':              j.Value(1)
					}),
					j.Value(map[string]j.Value{
						'producer_offset':   j.Value(544)
						'source_offset':     j.Value(893)
						'descriptor_member': j.Value(2403)
						'mask':              j.Value(1)
					}),
				])
				'producer':         j.Value('__ZN28AGXHardwareKernelCommandUtil27copy3DCommonPassthroughDataEP22AGX3DCommandDescriptorRK21AGX3DCommandCommonRec')
				'caller':           j.Value('__ZN15AGXCommandQueue18processRenderSetupERK24AGXHardwareKernelCommandRK30AGXRenderHardwareKernelCommandRK23AGXSegmentKernelCommandyyP21CompositeSubtypeStateR22AGXTACommandDescriptorR22AGX3DCommandDescriptorP18AGXAllocationList2bP11AGXResourceR10IOGPUEventPPSJ_SM_P14AGX3DWorkQueuePPN12AGXWorkQueue9HashEntryEbbR13AGXUMADescRecP20AGXUniqueResourceSet')
			}).as_map()
		}
		'recover_g17_ta_render_passthrough' {
			j.Value(map[string]j.Value{
				'payload_bytes':           j.Value(2512)
				'descriptor_bytes':        j.Value(5552)
				'pre_common_copy_ranges':  j.Value([
					j.Value(map[string]j.Value{
						'source_offset':     j.Value(0)
						'descriptor_member': j.Value(4064)
						'bytes':             j.Value(48)
					}),
					j.Value(map[string]j.Value{
						'source_offset':     j.Value(48)
						'descriptor_member': j.Value(4176)
						'bytes':             j.Value(64)
					}),
					j.Value(map[string]j.Value{
						'source_offset':     j.Value(496)
						'descriptor_member': j.Value(4112)
						'bytes':             j.Value(32)
					}),
					j.Value(map[string]j.Value{
						'source_offset':     j.Value(528)
						'descriptor_member': j.Value(4144)
						'bytes':             j.Value(8)
					}),
					j.Value(map[string]j.Value{
						'source_offset':     j.Value(544)
						'descriptor_member': j.Value(4152)
						'bytes':             j.Value(16)
					}),
					j.Value(map[string]j.Value{
						'source_offset':     j.Value(560)
						'descriptor_member': j.Value(4168)
						'bytes':             j.Value(4)
					}),
					j.Value(map[string]j.Value{
						'source_offset':     j.Value(184)
						'descriptor_member': j.Value(4288)
						'bytes':             j.Value(12)
					}),
					j.Value(map[string]j.Value{
						'source_offset':     j.Value(112)
						'descriptor_member': j.Value(4240)
						'bytes':             j.Value(48)
					}),
					j.Value(map[string]j.Value{
						'source_offset':     j.Value(484)
						'descriptor_member': j.Value(4320)
						'bytes':             j.Value(12)
					}),
					j.Value(map[string]j.Value{
						'source_offset':     j.Value(360)
						'descriptor_member': j.Value(4368)
						'bytes':             j.Value(8)
					}),
					j.Value(map[string]j.Value{
						'source_offset':     j.Value(160)
						'descriptor_member': j.Value(4360)
						'bytes':             j.Value(8)
					}),
					j.Value(map[string]j.Value{
						'source_offset':     j.Value(568)
						'descriptor_member': j.Value(5040)
						'bytes':             j.Value(4)
					}),
					j.Value(map[string]j.Value{
						'source_offset':     j.Value(600)
						'descriptor_member': j.Value(3936)
						'bytes':             j.Value(4)
					}),
					j.Value(map[string]j.Value{
						'source_offset':     j.Value(640)
						'descriptor_member': j.Value(5328)
						'bytes':             j.Value(48)
					}),
					j.Value(map[string]j.Value{
						'source_offset':     j.Value(688)
						'descriptor_member': j.Value(5400)
						'bytes':             j.Value(16)
					}),
					j.Value(map[string]j.Value{
						'source_offset':     j.Value(704)
						'descriptor_member': j.Value(5416)
						'bytes':             j.Value(12)
					}),
					j.Value(map[string]j.Value{
						'source_offset':     j.Value(2064)
						'descriptor_member': j.Value(2156)
						'bytes':             j.Value(4)
					}),
					j.Value(map[string]j.Value{
						'source_offset':     j.Value(2072)
						'descriptor_member': j.Value(2160)
						'bytes':             j.Value(8)
					}),
					j.Value(map[string]j.Value{
						'source_offset':     j.Value(2082)
						'descriptor_member': j.Value(2401)
						'bytes':             j.Value(1)
					}),
					j.Value(map[string]j.Value{
						'source_offset':     j.Value(2096)
						'descriptor_member': j.Value(2384)
						'bytes':             j.Value(12)
					}),
				])
				'pre_common_bit_fields':   j.Value([
					j.Value(map[string]j.Value{
						'source_offset':     j.Value(582)
						'descriptor_member': j.Value(4352)
						'destination_bytes': j.Value(4)
						'mask':              j.Value(1)
					}),
					j.Value(map[string]j.Value{
						'source_offset':     j.Value(573)
						'descriptor_member': j.Value(4393)
						'destination_bytes': j.Value(1)
						'mask':              j.Value(1)
					}),
					j.Value(map[string]j.Value{
						'source_offset':     j.Value(579)
						'descriptor_member': j.Value(4400)
						'destination_bytes': j.Value(1)
						'mask':              j.Value(1)
					}),
					j.Value(map[string]j.Value{
						'source_offset':     j.Value(574)
						'descriptor_member': j.Value(4394)
						'destination_bytes': j.Value(1)
						'mask':              j.Value(1)
					}),
					j.Value(map[string]j.Value{
						'source_offset':     j.Value(575)
						'descriptor_member': j.Value(4395)
						'destination_bytes': j.Value(1)
						'mask':              j.Value(1)
					}),
					j.Value(map[string]j.Value{
						'source_offset':     j.Value(577)
						'descriptor_member': j.Value(4397)
						'destination_bytes': j.Value(1)
						'mask':              j.Value(1)
					}),
					j.Value(map[string]j.Value{
						'source_offset':     j.Value(578)
						'descriptor_member': j.Value(4399)
						'destination_bytes': j.Value(1)
						'mask':              j.Value(1)
					}),
					j.Value(map[string]j.Value{
						'source_offset':     j.Value(585)
						'descriptor_member': j.Value(4402)
						'destination_bytes': j.Value(1)
						'mask':              j.Value(1)
					}),
					j.Value(map[string]j.Value{
						'source_offset':     j.Value(580)
						'descriptor_member': j.Value(4720)
						'destination_bytes': j.Value(1)
						'mask':              j.Value(1)
					}),
					j.Value(map[string]j.Value{
						'source_offset':     j.Value(581)
						'descriptor_member': j.Value(4721)
						'destination_bytes': j.Value(1)
						'mask':              j.Value(1)
					}),
					j.Value(map[string]j.Value{
						'source_offset':     j.Value(587)
						'descriptor_member': j.Value(5433)
						'destination_bytes': j.Value(1)
						'mask':              j.Value(1)
					}),
					j.Value(map[string]j.Value{
						'source_offset':     j.Value(586)
						'descriptor_member': j.Value(5544)
						'destination_bytes': j.Value(1)
						'mask':              j.Value(1)
					}),
					j.Value(map[string]j.Value{
						'source_offset':     j.Value(2080)
						'descriptor_member': j.Value(4398)
						'destination_bytes': j.Value(1)
						'mask':              j.Value(1)
					}),
					j.Value(map[string]j.Value{
						'source_offset':     j.Value(2068)
						'descriptor_member': j.Value(2152)
						'destination_bytes': j.Value(1)
						'mask':              j.Value(1)
					}),
					j.Value(map[string]j.Value{
						'source_offset':     j.Value(2080)
						'descriptor_member': j.Value(2189)
						'destination_bytes': j.Value(1)
						'mask':              j.Value(1)
					}),
				])
				'common':                  j.Value('__ZN28AGXHardwareKernelCommandUtil27copy3DCommonPassthroughDataEP22AGX3DCommandDescriptorRK21AGX3DCommandCommonRec')
				'post_common_copy_ranges': j.Value([
					j.Value(map[string]j.Value{
						'source_offset':     j.Value(1728)
						'descriptor_member': j.Value(1216)
						'bytes':             j.Value(8)
					}),
					j.Value(map[string]j.Value{
						'source_offset':     j.Value(1736)
						'descriptor_member': j.Value(1560)
						'bytes':             j.Value(48)
					}),
					j.Value(map[string]j.Value{
						'source_offset':     j.Value(1832)
						'descriptor_member': j.Value(1384)
						'bytes':             j.Value(128)
					}),
					j.Value(map[string]j.Value{
						'source_offset':     j.Value(1960)
						'descriptor_member': j.Value(1656)
						'bytes':             j.Value(8)
					}),
					j.Value(map[string]j.Value{
						'source_offset':     j.Value(1968)
						'descriptor_member': j.Value(1784)
						'bytes':             j.Value(8)
					}),
					j.Value(map[string]j.Value{
						'source_offset':     j.Value(1976)
						'descriptor_member': j.Value(1680)
						'bytes':             j.Value(8)
					}),
					j.Value(map[string]j.Value{
						'source_offset':     j.Value(1984)
						'descriptor_member': j.Value(1824)
						'bytes':             j.Value(8)
					}),
					j.Value(map[string]j.Value{
						'source_offset':     j.Value(1992)
						'descriptor_member': j.Value(1704)
						'bytes':             j.Value(8)
					}),
					j.Value(map[string]j.Value{
						'source_offset':     j.Value(2000)
						'descriptor_member': j.Value(1728)
						'bytes':             j.Value(8)
					}),
					j.Value(map[string]j.Value{
						'source_offset':     j.Value(1784)
						'descriptor_member': j.Value(1948)
						'bytes':             j.Value(12)
					}),
					j.Value(map[string]j.Value{
						'source_offset':     j.Value(1800)
						'descriptor_member': j.Value(1920)
						'bytes':             j.Value(16)
					}),
					j.Value(map[string]j.Value{
						'source_offset':     j.Value(2024)
						'descriptor_member': j.Value(1224)
						'bytes':             j.Value(24)
					}),
					j.Value(map[string]j.Value{
						'source_offset':     j.Value(2056)
						'descriptor_member': j.Value(2728)
						'bytes':             j.Value(4)
					}),
				])
				'post_common_bit_fields':  j.Value([
					j.Value(map[string]j.Value{
						'source_offset':     j.Value(2008)
						'descriptor_member': j.Value(2190)
						'destination_bytes': j.Value(1)
						'mask':              j.Value(1)
					}),
					j.Value(map[string]j.Value{
						'source_offset':     j.Value(2009)
						'descriptor_member': j.Value(2191)
						'destination_bytes': j.Value(1)
						'mask':              j.Value(1)
					}),
					j.Value(map[string]j.Value{
						'source_offset':     j.Value(2010)
						'descriptor_member': j.Value(2192)
						'destination_bytes': j.Value(1)
						'mask':              j.Value(1)
					}),
					j.Value(map[string]j.Value{
						'source_offset':     j.Value(2011)
						'descriptor_member': j.Value(2193)
						'destination_bytes': j.Value(1)
						'mask':              j.Value(1)
					}),
					j.Value(map[string]j.Value{
						'source_offset':     j.Value(2012)
						'descriptor_member': j.Value(2194)
						'destination_bytes': j.Value(1)
						'mask':              j.Value(1)
					}),
					j.Value(map[string]j.Value{
						'source_offset':     j.Value(2013)
						'descriptor_member': j.Value(2202)
						'destination_bytes': j.Value(1)
						'mask':              j.Value(1)
					}),
					j.Value(map[string]j.Value{
						'source_offset':     j.Value(2014)
						'descriptor_member': j.Value(2203)
						'destination_bytes': j.Value(1)
						'mask':              j.Value(1)
					}),
					j.Value(map[string]j.Value{
						'source_offset':     j.Value(2060)
						'descriptor_member': j.Value(2048)
						'destination_bytes': j.Value(1)
						'mask':              j.Value(1)
					}),
				])
				'producer':                j.Value('__ZN15AGXCommandQueue18processRenderSetupERK24AGXHardwareKernelCommandRK30AGXRenderHardwareKernelCommandRK23AGXSegmentKernelCommandyyP21CompositeSubtypeStateR22AGXTACommandDescriptorR22AGX3DCommandDescriptorP18AGXAllocationList2bP11AGXResourceR10IOGPUEventPPSJ_SM_P14AGX3DWorkQueuePPN12AGXWorkQueue9HashEntryEbbR13AGXUMADescRecP20AGXUniqueResourceSet')
			}).as_map()
		}
		'recover_g17_3d_descriptor_initialization' {
			j.Value(map[string]j.Value{
				'base_descriptor_bytes': j.Value(3136)
				'descriptor_bytes':      j.Value(5552)
				'selected_class':        j.Value('AGXTACommandDescriptor')
				'staging_clear':         j.Value(true)
				'cleared_range':         j.Value(map[string]j.Value{
					'offset': j.Value(1200)
					'bytes':  j.Value(848)
				})
				'initial_values':        j.Value([
					j.Value(map[string]j.Value{
						'member': j.Value(324)
						'bytes':  j.Value(4)
						'value':  j.Value(u64(4294967295))
					}),
					j.Value(map[string]j.Value{
						'member': j.Value(449)
						'bytes':  j.Value(2)
						'value':  j.Value(257)
					}),
					j.Value(map[string]j.Value{
						'member': j.Value(724)
						'bytes':  j.Value(4)
						'value':  j.Value(u64(4294967295))
					}),
					j.Value(map[string]j.Value{
						'member': j.Value(1024)
						'bytes':  j.Value(4)
						'value':  j.Value(1)
					}),
					j.Value(map[string]j.Value{
						'member': j.Value(1040)
						'bytes':  j.Value(4)
						'value':  j.Value(2)
					}),
					j.Value(map[string]j.Value{
						'member': j.Value(2304)
						'bytes':  j.Value(4)
						'value':  j.Value(u64(4294967295))
					}),
					j.Value(map[string]j.Value{
						'member': j.Value(2408)
						'bytes':  j.Value(4)
						'value':  j.Value(u64(4294967295))
					}),
					j.Value(map[string]j.Value{
						'member': j.Value(2720)
						'bytes':  j.Value(8)
						'value':  j.Value(u64(4294967295))
					}),
					j.Value(map[string]j.Value{
						'member': j.Value(2912)
						'bytes':  j.Value(4)
						'value':  j.Value(u64(4294967295))
					}),
					j.Value(map[string]j.Value{
						'member': j.Value(3120)
						'bytes':  j.Value(4)
						'value':  j.Value(1)
					}),
					j.Value(map[string]j.Value{
						'member': j.Value(3608)
						'bytes':  j.Value(4)
						'value':  j.Value(u64(4294967295))
					}),
					j.Value(map[string]j.Value{
						'member': j.Value(3936)
						'bytes':  j.Value(4)
						'value':  j.Value(2)
					}),
					j.Value(map[string]j.Value{
						'member': j.Value(4616)
						'bytes':  j.Value(4)
						'value':  j.Value(u64(4294967295))
					}),
					j.Value(map[string]j.Value{
						'member': j.Value(4708)
						'bytes':  j.Value(4)
						'value':  j.Value(u64(4294967295))
					}),
					j.Value(map[string]j.Value{
						'member': j.Value(4716)
						'bytes':  j.Value(4)
						'value':  j.Value(u64(4294967295))
					}),
					j.Value(map[string]j.Value{
						'member': j.Value(5032)
						'bytes':  j.Value(8)
						'value':  j.Value(u64(4294967295))
					}),
					j.Value(map[string]j.Value{
						'member': j.Value(5096)
						'bytes':  j.Value(4)
						'value':  j.Value(u64(4294967295))
					}),
				])
				'masked_defaults':       j.Value([
					j.Value(map[string]j.Value{
						'member': j.Value(3112)
						'bytes':  j.Value(8)
						'mask':   j.Value(u64(18446726481527701503))
					}),
					j.Value(map[string]j.Value{
						'member': j.Value(5296)
						'bytes':  j.Value(8)
						'mask':   j.Value(u64(18446726481527701503))
					}),
				])
				'base_allocator':        j.Value('__ZNK22AGX3DCommandDescriptor9MetaClass5allocEv')
				'base_initializer':      j.Value('__ZN22AGX3DCommandDescriptor4initEP5IOGPUP17IOGPUCommandQueueP9IOGPUTaskPKcyP19AGXDebugBufferShmem')
				'allocator':             j.Value('__ZNK22AGXTACommandDescriptor9MetaClass5allocEv')
				'initializer':           j.Value('__ZN22AGXTACommandDescriptor4initEP5IOGPUP17IOGPUCommandQueueP9IOGPUTaskPKcyP19AGXDebugBufferShmem')
			}).as_map()
		}
		'recover_g17_channel_command_common_fields' {
			j.Value(map[string]j.Value{
				'known_prefix_bytes':     j.Value(106)
				'smallest_command_bytes': j.Value(128)
				'preserve_other_bytes':   j.Value(true)
				'fields':                 j.Value(map[string]j.Value{
					'control_01a':      j.Value(map[string]j.Value{
						'offset': j.Value(26)
						'bytes':  j.Value(4)
						'value':  j.Value(1)
					})
					'data_master_type': j.Value(map[string]j.Value{
						'offset':          j.Value(34)
						'bytes':           j.Value(4)
						'source_argument': j.Value(3)
					})
					'control_032':      j.Value(map[string]j.Value{
						'offset': j.Value(50)
						'bytes':  j.Value(4)
						'value':  j.Value(0)
					})
					'control_062':      j.Value(map[string]j.Value{
						'offset': j.Value(98)
						'bytes':  j.Value(8)
						'value':  j.Value(0)
					})
				})
				'producer':               j.Value('__ZN10AGXChannel19submitNopUnpreparedEP22IOGPUCommandDescriptor22AGFIChannelCommandType19_AGFIDataMasterType')
			}).as_map()
		}
		'recover_g17_register_entry_codec' {
			j.Value(map[string]j.Value{
				'entry_bytes':             j.Value(12)
				'selector_argument':       j.Value(2)
				'selector_mask':           j.Value(262136)
				'mode_argument':           j.Value(3)
				'mode_mask':               j.Value(1)
				'preserved_template_mask': j.Value(u64(4294705158))
				'value_argument':          j.Value(4)
				'value_offset':            j.Value(4)
				'producer':                j.Value('__ZNK36AGX·PI_300·X·A0·RCEBufferEncoder11encodeEntryEPvjhy')
			}).as_map()
		}
		'recover_g17_3d_register_lists' {
			j.Value(map[string]j.Value{
				'command_bytes':              j.Value(8768)
				'passes':                     j.Value(4)
				'stride':                     j.Value(1824)
				'stream_offset':              j.Value(160)
				'stream_bytes':               j.Value(1792)
				'gpu_address_offset':         j.Value(1952)
				'entry_count_offset':         j.Value(1960)
				'byte_length_offset':         j.Value(1962)
				'entry_bytes':                j.Value(12)
				'inter_pass_gap':             j.Value(20)
				'selector_template_mask':     j.Value(u64(4294705158))
				'gpu_base_descriptor_member': j.Value(1088)
				'descriptor_summary':         j.Value(map[string]j.Value{
					'offset':      j.Value(2088)
					'stride':      j.Value(16)
					'records':     j.Value(4)
					'gpu_address': j.Value(0)
					'entry_count': j.Value(8)
				})
				'record_framing_resolved':    j.Value(true)
				'producer':                   j.Value('__ZN33AGX·PI_300·X·A0·3DChannelSKSM25generateRegisterListFor3DEP20AGFIChannelCommand3DP22AGX3DCommandDescriptor')
			}).as_map()
		}
		'recover_g17_channel_command_pools' {
			j.Value(map[string]j.Value{
				'block_bytes':             j.Value(64)
				'block_layout':            j.Value(map[string]j.Value{
					'resource':      j.Value(8)
					'cpu_base':      j.Value(16)
					'in_use_bytes':  j.Value(24)
					'element_bytes': j.Value(32)
					'slot_count':    j.Value(40)
					'slot_cursor':   j.Value(44)
					'exhausted':     j.Value(48)
					'lock':          j.Value(56)
				})
				'gpu_address_vtable_slot': j.Value(344)
				'size_producer':           j.Value('__ZN11AGXFirmware25configurePoolElementSizesEv')
				'commands':                j.Value(map[string]j.Value{
					'3D':      j.Value(map[string]j.Value{
						'block':         j.Value(5768)
						'size_member':   j.Value(544)
						'command_bytes': j.Value(8768)
					})
					'TA':      j.Value(map[string]j.Value{
						'block':         j.Value(5704)
						'size_member':   j.Value(536)
						'command_bytes': j.Value(2496)
					})
					'Barrier': j.Value(map[string]j.Value{
						'block':         j.Value(5960)
						'size_member':   j.Value(568)
						'command_bytes': j.Value(128)
					})
				})
			}).as_map()
		}
		'recover_g17_command_pool_backing' {
			j.Value(map[string]j.Value{
				'capacity_override_member':      j.Value(69984)
				'capacity_fallback_member':      j.Value(1816)
				'selected_capacity_member':      j.Value(1832)
				'fallback_capacity':             j.Value(80)
				'work_pool_multiplier':          j.Value(3)
				'fallback_work_requested_slots': j.Value(240)
				'backing_alignment':             j.Value('1 << kernel_page_shift')
				'backing_bytes_formula':         j.Value('align_up(element_bytes * requested_slots, kernel_page_bytes)')
				'slot_count_formula':            j.Value('backing_bytes / element_bytes')
				'in_use_bytes_formula':          j.Value('slot_count')
				'producer':                      j.Value('__ZN9PoolClassI20AGFIChannelCommand3DE13createBackingEjP14AGXAcceleratoryb')
			}).as_map()
		}
		'recover_g17_3d_command_reclamation' {
			j.Value(map[string]j.Value{
				'descriptor_command_cpu_member': j.Value(1080)
				'pool_block':                    j.Value(5768)
				'pool_cpu_base_member':          j.Value(5784)
				'pool_in_use_member':            j.Value(5792)
				'pool_element_bytes_member':     j.Value(5800)
				'pool_exhausted_member':         j.Value(5816)
				'pool_lock_member':              j.Value(5824)
				'slot_formula':                  j.Value('(command_cpu - pool_cpu_base) / element_bytes')
				'decrement_if_nonzero':          j.Value(true)
				'clear_descriptor_pointer':      j.Value(true)
				'producer':                      j.Value('__ZN22AGX3DCommandDescriptor8completeEv')
			}).as_map()
		}
		'recover_g17_queue_device_inputs' {
			j.Value(map[string]j.Value{
				'queue_device_member': j.Value(1168)
				'queue_value_member':  j.Value(1176)
				'device_class':        j.Value('AGXShared')
				'process_id':          j.Value(map[string]j.Value{
					'device_member':        j.Value(96)
					'channel_state_offset': j.Value(72)
					'producer':             j.Value('proc_pid(get_bsdtask_info(task))')
					'producer_address':     j.Value(5505024)
				})
				'app_gpu_role':        j.Value(map[string]j.Value{
					'device_member':          j.Value(288)
					'bytes':                  j.Value(1)
					'scheduler_state_offset': j.Value(38)
					'default':                j.Value(2)
					'maximum':                j.Value(3)
					'setter':                 j.Value('__ZN9AGXShared16set_app_gpu_roleEi13eIOGPUAppRole')
				})
			}).as_map()
		}
		'recover_g17_channel_runtime_resources' {
			j.Value(map[string]j.Value{
				'configured_queues': j.Value(map[string]j.Value{
					'default':                     j.Value(80)
					'accelerator_default_member':  j.Value(1816)
					'accelerator_override_member': j.Value(69984)
					'command_queue_member':        j.Value(2176)
				})
				'work_queue':        j.Value(map[string]j.Value{
					'request_argument': j.Value(3)
					'request_member':   j.Value(84)
				})
				'channel_ring':      j.Value(map[string]j.Value{
					'maximum_queue_request': j.Value(128)
					'pointers_per_queue':    j.Value(16)
					'default_entries':       j.Value(1280)
					'pointer_bytes':         j.Value(8)
					'default_pointer_bytes': j.Value(10240)
				})
				'timestamp_state':   j.Value(map[string]j.Value{
					'firmware_stack_member':       j.Value(4744)
					'bytes':                       j.Value(24)
					'alignment_shift':             j.Value(9)
					'caching':                     j.Value(0)
					'object_cpu_member':           j.Value(32)
					'object_gpu_member':           j.Value(40)
					'self_gpu_address_offset':     j.Value(8)
					'update_mode_flag_offset':     j.Value(16)
					'initial_update_mode':         j.Value(0)
					'context_cookie_state_offset': j.Value(16)
					'command_queue_owner_member':  j.Value(1664)
				})
			}).as_map()
		}
		'recover_g17_scheduler_state' {
			j.Value(map[string]j.Value{
				'pool_name':                       j.Value('AGFICmdQueueSchedState')
				'element_bytes':                   j.Value(64)
				'alignment_shift':                 j.Value(9)
				'caching_option':                  j.Value(1)
				'shrink_mode':                     j.Value(0)
				'stack_host_member':               j.Value(5320)
				'stack_element_size_member':       j.Value(160)
				'stack_block_bytes_member':        j.Value(88)
				'stack_elements_per_block_member': j.Value(96)
				'block_bytes':                     j.Value('(page_bytes + 2 * element_bytes - 1) & -page_bytes')
				'queue_accelerator_member':        j.Value(1336)
				'accelerator_asc_member':          j.Value(1456)
				'queue_bindings':                  j.Value(map[string]j.Value{
					'cpu_address':      j.Value(2208)
					'resource':         j.Value(2216)
					'allocation_index': j.Value(2224)
					'gpu_address':      j.Value(2232)
				})
				'zeroed_bytes':                    j.Value(56)
				'initial_fields':                  j.Value([
					j.Value(map[string]j.Value{
						'offset': j.Value(0)
						'bytes':  j.Value(2)
						'value':  j.Value(65535)
					}),
					j.Value(map[string]j.Value{
						'offset': j.Value(5)
						'bytes':  j.Value(1)
						'value':  j.Value(1)
					}),
					j.Value(map[string]j.Value{
						'offset': j.Value(34)
						'bytes':  j.Value(4)
						'value':  j.Value(0)
					}),
					j.Value(map[string]j.Value{
						'offset': j.Value(38)
						'bytes':  j.Value(1)
						'source': j.Value(map[string]j.Value{
							'queue_member': j.Value(1168)
							'offset':       j.Value(288)
						})
					}),
					j.Value(map[string]j.Value{
						'offset': j.Value(51)
						'bytes':  j.Value(1)
						'value':  j.Value(255)
					}),
				])
			}).as_map()
		}
		'recover_g17_channel_state_sources' {
			j.Value(map[string]j.Value{
				'queue_value':              j.Value(map[string]j.Value{
					'state_offset':      j.Value(72)
					'channel_member':    j.Value(76)
					'queue_seed_member': j.Value(1176)
				})
				'queue_address':            j.Value(map[string]j.Value{
					'state_offset':      j.Value(156)
					'channel_member':    j.Value(248)
					'queue_seed_member': j.Value(2232)
				})
				'runtime_kick_channel_qos': j.Value(map[string]j.Value{
					'setter':                      j.Value('__ZN14AGXArmFirmware17setKickChannelQosEjj')
					'runtime_host_member':         j.Value(896)
					'runtime_members':             j.Value([j.Value(80), j.Value(76)])
					'update_flag_runtime_offset':  j.Value(50984)
					'distinct_from_channel_state': j.Value(true)
				})
				'ring_entries':             j.Value(map[string]j.Value{
					'control_offset':  j.Value(96)
					'channel_member':  j.Value(84)
					'maximum_request': j.Value(128)
					'multiplier':      j.Value(16)
				})
			}).as_map()
		}
		'recover_g17_channel_data_master_types' {
			j.Value(map[string]j.Value{
				'base_initializer': j.Value('__ZN10AGXChannel4initEPK15AGXCommandQueueP12AGXWorkQueueiiy19_AGFIDataMasterType')
				'subclasses':       j.Value(map[string]j.Value{
					'TA': j.Value(map[string]j.Value{
						'initializer':      j.Value('__ZN12AGXTAChannel4initEPK15AGXCommandQueueP12AGXWorkQueueiiy')
						'data_master_type': j.Value(0)
					})
					'3D': j.Value(map[string]j.Value{
						'initializer':      j.Value('__ZN12AGX3DChannel4initEPK15AGXCommandQueueP12AGXWorkQueueiiy')
						'data_master_type': j.Value(1)
					})
					'CL': j.Value(map[string]j.Value{
						'initializer':      j.Value('__ZN12AGXCLChannel4initEPK15AGXCommandQueueP12AGXWorkQueueiiy')
						'data_master_type': j.Value(2)
					})
				})
			}).as_map()
		}
		'recover_g17_channel_identity' {
			j.Value(map[string]j.Value{
				'value':             j.Value(128)
				'channel_member':    j.Value(24)
				'bytes':             j.Value(4)
				'base_owner':        j.Value(map[string]j.Value{
					'command_queue_member': j.Value(1336)
					'channel_member':       j.Value(16)
				})
				'base_initializer':  j.Value('__ZN12IOGPUChannel4initEP5IOGPUi')
				'outer_entry_bytes': j.Value(1)
			}).as_map()
		}
		else { panic(operation) }
	}
}
