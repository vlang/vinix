module g17expr

import traceanalysis as j

// Checked producer instructions and fixed record contracts. Analysis and
// ordered checks live in events.v, events_resources.v and events_actions.v.

fn event_symbol(name string) string {
	return match name {
		'ACCELERATOR_HANDLE_INTERRUPT' {
			'__ZN14AGXAccelerator15handleInterruptEP22IOInterruptEventSourcei'
		}
		'ACCELERATOR_START' { '__ZN14AGXAccelerator5startEP9IOService' }
		'ACCELERATOR_SUBMIT_DEVICE_CONTROL' {
			'__ZN14AGXAccelerator19submitDeviceControlEP33AGFIAcceleratorDeviceControlEntryPjS2_'
		}
		'ALLOCATE_PM_MEMORY_EVENT' {
			'__ZN14AGXAccelerator19allocateMemoryEventEP22IOInterruptEventSourcei'
		}
		'ALLOCATE_UMA_MEMORY_EVENT' {
			'__ZN14AGXAccelerator22allocateUMAMemoryEventEP22IOInterruptEventSourcei'
		}
		'ARM_SUBMIT_DEVICE_CONTROL' {
			'__ZN14AGXArmFirmware19submitDeviceControlEP33AGFIAcceleratorDeviceControlEntryjPj'
		}
		'BASE_CONFIGURE_DEVICE' { '__ZN14AGXAccelerator15configureDeviceEP9IOService' }
		'FIRMWARE_DRAIN_EVENT_RING' { '__ZN11AGXFirmware22drainFirmwareEventRingEv' }
		'FIRMWARE_DRAIN_EVENT_RING_ROLE' {
			'__ZN11AGXFirmware22drainFirmwareEventRingE16AGFIFirmwareRole'
		}
		'FIRMWARE_HANDLE_EVENT' { '__ZN11AGXFirmware11handleEventE17AGXInterruptIndex' }
		'FIRMWARE_INIT' { '__ZN11AGXFirmware4initEP14AGXAccelerator' }
		'FIRMWARE_RING_FETCH' {
			'__ZN24AGXFirmwareRingValidator14fetchNextEntryEP26AGFIFirmwareEventRingEntry'
		}
		'G17_ACCELERATOR_VTABLE' { '__ZTV18AGXAcceleratorG17X' }
		'G17_CLEAR_FIRMWARE_INTERRUPTS' {
			'__ZN14AGXArmFirmware34clearOutstandingFirmwareInterruptsEv.4213'
		}
		'G17_FIRMWARE_VTABLE' { '__ZTV17AGXArmFirmwareASC' }
		'G17_HAL_UPDATE_UMA_DESC' {
			'__ZN31AGX·PI_300·X·A0·Accelerator16halUpdateUMADescEP18AGXUSCPrivMemFListRK30AGXUSCPrivateMemDescUpdateData'
		}
		'G17_HANDLE_FIRMWARE_CONTROLLER_EVENT' {
			'__ZN14AGXArmFirmware29handleFirmwareControllerEventEPK26AGFIFirmwareEventRingEntry'
		}
		'HWPB_MANAGER_META_CLASS' { '__ZN23AGXHWParamBufferManager10gMetaClassE' }
		'IMPLICIT_GROW_ENGINE_VTABLE' { '__ZTV21AGXImplicitGrowEngine' }
		'IOFILTER_INTERRUPT_EVENT_SOURCE_FACTORY' {
			'__ZN28IOFilterInterruptEventSource26filterInterruptEventSourceEP8OSObjectPFvS1_P22IOInterruptEventSourceiEPFbS1_PS_EP9IOServicei'
		}
		'IOFILTER_INTERRUPT_EVENT_SOURCE_VTABLE' { '__ZTV28IOFilterInterruptEventSource' }
		'IOFILTER_SIGNAL_INTERRUPT' { '__ZN28IOFilterInterruptEventSource15signalInterruptEv' }
		'IOGPU_EVENT_GET_NUM_STAMPS' { '__ZN17IOGPUEventMachine12getNumStampsEv' }
		'IOGPU_EVENT_SIGNAL_STAMP' { '__ZN17IOGPUEventMachine11signalStampEij' }
		'IOGPU_EVENT_TEST_ALL_STAMPS' { '__ZNK17IOGPUEventMachine13testAllStampsEv' }
		'IOGPU_FENCE_INTERRUPT_OCCURRED' { '__ZN17IOGPUFenceMachine24iofenceInterruptOccurredEv' }
		'IOGPU_FENCE_NOTIFY_CLPC' { '__ZN17IOGPUFenceMachine23notifyCLPCIOPerfControlEy' }
		'IOGPU_SCHEDULER_SIGNAL_HARDWARE_ERROR' {
			'__ZN14IOGPUScheduler19signalHardwareErrorE15eRestartRequesti'
		}
		'IOGPU_SIGNAL_STAMPS_UPDATED' { '__ZN5IOGPU19signalStampsUpdatedEv' }
		'IOGPU_WEAK_NAMESPACE_GET_OBJECT' { '__ZNK18IOGPUWeakNamespace9getObjectEj' }
		'IOGPU_WEAK_NAMESPACE_REMOVE_OBJECT' { '__ZN18IOGPUWeakNamespace12removeObjectEj' }
		'IOINTERRUPT_GET_INDEX' { '__ZNK22IOInterruptEventSource11getIntIndexEv' }
		'IOSURFACE_ROOT_SIGNAL_EVENT_ID' { '__ZN13IOSurfaceRoot13signalEventIDEj' }
		'PARAMETER_MANAGEMENT_GROW' { '__ZN22AGXParameterManagement15growImmediatelyEv' }
		'PARAMETER_MANAGEMENT_VIRTUAL_GROW' {
			'__ZN29AGXParameterManagementVirtual15growImmediatelyEv'
		}
		'PARAMETER_MANAGEMENT_VIRTUAL_VTABLE' { '__ZTV29AGXParameterManagementVirtual' }
		'PARAMETER_MANAGEMENT_VTABLE' { '__ZTV22AGXParameterManagement' }
		'RECEIVED_MESSAGE_FROM_AKF' {
			'__ZN14AGXArmFirmware22receivedMessageFromAKFEy16AGFIFirmwareRole'
		}
		'SUBMIT_DEVICE_CONTROL' {
			'__ZN11AGXFirmware19submitDeviceControlEP33AGFIAcceleratorDeviceControlEntryjPj'
		}
		'USC_PRIV_MEM_FLIST_META_CLASS' { '__ZN18AGXUSCPrivMemFList10gMetaClassE' }
		'USC_PRIV_MEM_RETIRE_GROW_REQUEST' {
			'__ZN24IAGXUSCPrivMemGrowEngine17retireGrowRequestEiiyj'
		}
		'DRAIN_FIRMWARE_RINGS' { '__ZN11AGXFirmware18drainFirmwareRingsEb' }
		else { panic(name) }
	}
}

fn event_words(label string) map[int]u32 {
	return match label {
		'G17 type-2 callback dispatch' {
			{
				0x14: u32(0xd370d428)
				0x20: u32(0xf100091f)
				0x28: u32(0xf9414c08)
				0x2c: u32(0x395d3109)
				0x30: u32(0x8b090d08)
				0x34: u32(0xf942e900)
				0x48: u32(0xd2804b11)
				0x4c: u32(0x8b110210)
				0x50: u32(0xf9400208)
				0x58: u32(0xd73f0910)
			}
		}
		'G17 interrupt-event-source construction' {
			{
				0x3460: u32(0x7100051f)
				0x3468: u32(0xd2800015)
				0x346c: u32(0x91174277)
				0x347c: u32(0x910006b5)
				0x3480: u32(0x910022f7)
				0x348c: u32(0xf90002ff)
				0x35e8: u32(0xaa1303e0)
				0x35ec: u32(0xaa1603e1)
				0x35f0: u32(0xaa1003e2)
				0x35f4: u32(0xaa1903e3)
				0x35f8: u32(0xaa1503e4)
				0x3600: u32(0xf90002e0)
			}
		}
		'G17 callback interrupt selection' {
			{
				0x9d0: u32(0x53027c08)
				0x9d4: u32(0x51001509)
				0x9d8: u32(0x7100113f)
				0x9e0: u32(0x52802089)
				0x9e4: u32(0x790e9a69)
				0x9f4: u32(0x7100111f)
				0x9fc: u32(0x7100051f)
				0xa04: u32(0x790e9a7f)
				0xa08: u32(0x391d3a68)
				0xa38: u32(0xb9075268)
			}
		}
		'G17 interrupt action forwarding' {
			{
				0x10: u32(0xf942d813)
				0x24: u32(0xd2803d11)
				0x60: u32(0x910ca202)
				0x64: u32(0xf9419610)
				0x68: u32(0x12001c01)
				0x6c: u32(0xaa1303e0)
			}
		}
		'G17 firmware-ring callback event' {
			{
				0x80:  u32(0x7100103f)
				0x84:  u32(0x54000700)
				0x174: u32(0xd2811011)
				0x178: u32(0x8b110210)
				0x17c: u32(0xf9400208)
				0x190: u32(0x52800021)
			}
		}
		'G17 firmware event-ring validator' {
			{
				0x118: u32(0x9129c275)
				0x128: u32(0x9117c276)
				0x130: u32(0x52802617)
				0x190: u32(0xf9414e6b)
				0x194: u32(0x5280480a)
				0x198: u32(0x9b0a5b0a)
				0x19c: u32(0xa949312d)
				0x1a4: u32(0xa94b3d2e)
				0x284: u32(0xf901094b)
				0x288: u32(0x3d808d40)
				0x28c: u32(0xf9010d4d)
				0x290: u32(0xf901114e)
			}
		}
		'G17 dual-role firmware event drain' {
			{
				0x14: u32(0x52800001)
				0x18: u32(0x9400000a)
				0x20: u32(0x52800021)
			}
		}
		'G17 role firmware event drain' {
			{
				0x28: u32(0xb010c28)
				0x2c: u32(0x531a6508)
				0x30: u32(0x8b080009)
				0x34: u32(0xf9440928)
				0x3c: u32(0x91200134)
				0x40: u32(0xf9400689)
				0x44: u32(0xb940012b)
				0x48: u32(0xb9001a8b)
				0x4c: u32(0xb9402129)
				0x50: u32(0xb9001e89)
				0x54: u32(0xf940168a)
				0xe8: u32(0xaa1403e0)
				0xec: u32(0x940054f6)
			}
		}
		'G17 firmware completion event' {
			{
				0x368:  u32(0xb94053e8)
				0x36c:  u32(0x7100051f)
				0x374:  u32(0x7940cbe8)
				0x378:  u32(0x7100611f)
				0x384:  u32(0xf84543f7)
				0x388:  u32(0xf845c3f9)
				0x3b0:  u32(0xf940a300)
				0x3b4:  u32(0xaa1603e1)
				0x3e0:  u32(0x321b0341)
				0x468:  u32(0xb9404fe9)
				0x470:  u32(0xb9004fe9)
				0x12a8: u32(0xb9404fe8)
				0x12ac: u32(0x36000a28)
				0x12b0: u32(0xf9414e74)
				0x12b4: u32(0xf940aa80)
				0x12bc: u32(0xaa1403e0)
				0x12c4: u32(0xf940a280)
			}
		}
		'G17 firmware event-ring fetch' {
			{
				0x10:  u32(0xf9400808)
				0x18:  u32(0x2943240a)
				0x24:  u32(0xf9401409)
				0x30:  u32(0x8b0a0d4a)
				0x34:  u32(0xd37df14a)
				0x50:  u32(0xb9000028)
				0xd8:  u32(0xb900442a)
				0xdc:  u32(0xf940100a)
				0xe0:  u32(0x9ac8254a)
				0xe4:  u32(0x3600058a)
				0xec:  u32(0x1100054a)
				0xf0:  u32(0x9ac9094b)
				0xf8:  u32(0xb9001809)
				0xfc:  u32(0xd5033bbf)
				0x104: u32(0xf940040a)
				0x108: u32(0xb9000149)
			}
		}
		'G17 PM-memory event' {
			{
				0xaf0: u32(0xb94053e8)
				0xaf4: u32(0x7100191f)
				0xafc: u32(0xb94057f6)
				0xb14: u32(0xd2815611)
				0xb44: u32(0xb9405bf6)
				0xb48: u32(0x7101fedf)
				0xb50: u32(0xb94063f7)
				0xb54: u32(0x710102ff)
				0xb5c: u32(0xb94057fa)
				0xb60: u32(0xb9405ffb)
				0xb64: u32(0xf84643f9)
				0xb68: u32(0xf9414e7c)
				0xb6c: u32(0x52935d08)
				0xb70: u32(0x72a00028)
				0xbb8: u32(0x8b080388)
				0xbd8: u32(0xf900015f)
				0xbdc: u32(0x29016956)
				0xbe0: u32(0x29025d5b)
				0xbe4: u32(0xf9000d59)
				0xbf0: u32(0x12000908)
				0xc00: u32(0xf9414e68)
				0xc04: u32(0xf9423500)
				0xc2c: u32(0x9107e208)
				0xc30: u32(0xf940fe09)
			}
		}
		'G17 PM-memory worker registration' {
			{
				0x3850: u32(0xd2825ef1)
				0x3854: u32(0xdac10230)
				0x3858: u32(0xaa1003e1)
				0x385c: u32(0xaa1303e0)
				0x3860: u32(0xd2800002)
				0x3864: u32(0x52800003)
				0x386c: u32(0xf9023660)
			}
		}
		'G17 PM-memory allocation worker' {
			{
				0x28:  u32(0x91406408)
				0x2c:  u32(0x912ba119)
				0x60:  u32(0x9100e3e8)
				0x64:  u32(0x6f00e400)
				0x68:  u32(0xad010100)
				0x6c:  u32(0x52800108)
				0x70:  u32(0x29075fe8)
				0x74:  u32(0x3cc082a0)
				0x78:  u32(0x3c8403e0)
				0x7c:  u32(0xf9400ea8)
				0x80:  u32(0xf9002be8)
				0x88:  u32(0x52800328)
				0xe4:  u32(0x9107a208)
				0xe8:  u32(0xf940f609)
				0xfc:  u32(0xaa1003e1)
				0x100: u32(0x9100e3e2)
				0x104: u32(0xd10153a3)
				0x108: u32(0xd10163a4)
				0x17c: u32(0xb94002a8)
				0x180: u32(0x35000e48)
				0x1c0: u32(0xb9400ab6)
				0x210: u32(0xaa1703e0)
				0x21c: u32(0x94c9d252)
				0x24c: u32(0xf9404ed8)
				0x250: u32(0xf9409b00)
				0x268: u32(0xd2803211)
				0x27c: u32(0xd73f0910)
				0x280: u32(0xaa0003f7)
			}
		}
		'G17 accelerator device-control callback' {
			{
				0x58: u32(0xf942dac0)
				0x6c: u32(0xf9400010)
				0x70: u32(0xaa0003f1)
				0x74: u32(0xf2f9b431)
				0x78: u32(0xdac11a30)
				0x7c: u32(0xd2805011)
				0x80: u32(0x8b110210)
				0x84: u32(0xf9400208)
				0x90: u32(0xaa1403e1)
				0x94: u32(0xaa1303e3)
				0xb4: u32(0xaa0403f1)
				0xbc: u32(0xd71f0a11)
			}
		}
		'G17 PM-memory device-control submission' {
			{
				0x2c:  u32(0xb9400038)
				0x30:  u32(0x36180102)
				0x34:  u32(0x7100231f)
				0x3c:  u32(0xf9414e88)
				0x40:  u32(0xf9434508)
				0x44:  u32(0xf9400c29)
				0x48:  u32(0xeb09011f)
				0x68:  u32(0xd37ef709)
				0x80:  u32(0xb940015a)
				0x134: u32(0x12000668)
				0x138: u32(0x34000508)
				0x13c: u32(0x52833b08)
				0x140: u32(0x8b080294)
				0x160: u32(0x53041273)
				0x178: u32(0xd2811511)
				0x184: u32(0xd2800221)
				0x188: u32(0xf2e01081)
				0x194: u32(0xd73f0910)
			}
		}
		'G17 UMA grow-completion event' {
			{
				0x628: u32(0xb94053e8)
				0x62c: u32(0x7100351f)
				0x634: u32(0xb9405be8)
				0x638: u32(0x7104011f)
				0x640: u32(0xf845c3e8)
				0x644: u32(0xb4006e88)
				0x648: u32(0xf84643e8)
				0x64c: u32(0xb4006e48)
				0x650: u32(0xb94057f6)
				0x668: u32(0xd2815611)
				0x698: u32(0xf846c3f9)
				0x69c: u32(0xb94077f6)
				0x6a0: u32(0x294aebfb)
				0x768: u32(0xaa1703e0)
				0x778: u32(0xb4002d40)
				0x780: u32(0xf9402800)
				0x794: u32(0xd2803011)
				0x7a0: u32(0xaa1b03e1)
				0x7a4: u32(0xaa1a03e2)
				0x7a8: u32(0xaa1903e3)
				0x7ac: u32(0xaa1603e4)
				0x7b4: u32(0xd73f0910)
			}
		}
		'G17 UMA threshold event' {
			{
				0x2f4: u32(0xb94053e8)
				0x2f8: u32(0x71003d1f)
				0x300: u32(0xb94057f8)
				0x304: u32(0x7104031f)
				0x30c: u32(0xf9414e7b)
				0x310: u32(0x91404f77)
				0x314: u32(0xf942defa)
				0x320: u32(0xb945c2e8)
				0x32c: u32(0xf942e6e8)
				0x810: u32(0xaa1603e0)
				0x820: u32(0xb4001be0)
				0x8cc: u32(0xb9401328)
				0x8d0: u32(0x7104011f)
				0x908: u32(0xb9408329)
				0x90c: u32(0xb940eb28)
				0x924: u32(0xb9008328)
				0x938: u32(0xd2822411)
				0x944: u32(0xd102c3a2)
				0x94c: u32(0xaa1903e1)
				0x968: u32(0xd102c3a8)
				0x96c: u32(0xf803811f)
				0x970: u32(0x6f00e400)
				0x974: u32(0x3c828100)
				0x978: u32(0x3c818100)
				0x97c: u32(0x3c808100)
				0x980: u32(0x52800428)
				0x984: u32(0x292a63a8)
				0xa38: u32(0x94000329)
			}
		}
		'G17 UMA async-allocation event' {
			{
				0x47c: u32(0xd503249f)
				0x480: u32(0xf9414e68)
				0x484: u32(0x52952c09)
				0x488: u32(0x72a00029)
				0x490: u32(0x39400108)
				0x494: u32(0x35ffe148)
				0x498: u32(0xb94053e8)
				0x49c: u32(0x7100251f)
				0x4a4: u32(0xf845c3e8)
				0x4a8: u32(0xb4007b68)
				0x4ac: u32(0xb94057e8)
				0x4b0: u32(0x7104011f)
				0x4b4: u32(0x54007b02)
				0x4b8: u32(0xb94067f6)
				0x4d0: u32(0xd2815611)
				0x4fc: u32(0x360078c8)
				0x500: u32(0xb94057f9)
				0x504: u32(0xf845c3f7)
				0x508: u32(0xfc4643e9)
				0x50c: u32(0xb9406ff8)
				0x510: u32(0xf9414e7a)
				0x514: u32(0x91406b56)
				0x518: u32(0x34003a38)
				0x51c: u32(0xb942f6c8)
				0x520: u32(0x11000508)
				0x524: u32(0x12001508)
				0x528: u32(0xb942f2c9)
				0x52c: u32(0x6b09011f)
				0x534: u32(0x52800c80)
				0xc5c: u32(0xb942f6c8)
				0xc60: u32(0x11000508)
				0xc64: u32(0x12001508)
				0xc68: u32(0xb942f2c9)
				0xc6c: u32(0x6b09011f)
				0xc70: u32(0x54ffa260)
				0xc7c: u32(0x52935e08)
				0xc80: u32(0x72a00028)
				0xc88: u32(0xb942f6c9)
				0xc8c: u32(0xd37be929)
				0xca4: u32(0x29007d59)
				0xca8: u32(0xf9000557)
				0xcac: u32(0xfd000949)
				0xcb0: u32(0x29037d58)
				0xcb4: u32(0xb942f6c8)
				0xcb8: u32(0x11000508)
				0xcbc: u32(0x12001508)
				0xcc0: u32(0xb902f6c8)
				0xccc: u32(0xf9414e68)
				0xcd0: u32(0xf9423900)
				0xcf8: u32(0x9107e208)
				0xcfc: u32(0xf940fe09)
				0xd00: u32(0xd2800001)
				0xd04: u32(0xd2800002)
				0xd08: u32(0x52800003)
				0xd14: u32(0xd73f0931)
			}
		}
		'G17 UMA allocation worker registration' {
			{
				0x38ac: u32(0xd2825ef1)
				0x38b0: u32(0xdac10230)
				0x38b4: u32(0xaa1003e1)
				0x38b8: u32(0xaa1303e0)
				0x38bc: u32(0xd2800002)
				0x38c0: u32(0x52800003)
				0x38c8: u32(0xf9023a60)
			}
		}
		'G17 firmware-controller event dispatch' {
			{
				0x120: u32(0xb94053e8)
				0x124: u32(0x35009b88)
				0x138: u32(0xd2810f11)
				0x13c: u32(0x8b110210)
				0x140: u32(0xf9400208)
				0x144: u32(0x910143e1)
				0x148: u32(0xaa1303e0)
				0x150: u32(0xd73f0910)
			}
		}
		'G17 CLPC notification event' {
			{
				0x160: u32(0xb94053e8)
				0x164: u32(0x7100391f)
				0x16c: u32(0xf84543e1)
				0x170: u32(0xf9414e68)
				0x174: u32(0xf940a900)
			}
		}
		'G17 metrology-aging event' {
			{
				0x294: u32(0xb94053e8)
				0x298: u32(0x7100211f)
				0x2a0: u32(0xb94057e8)
				0x2a4: u32(0xb81503a8)
				0x2a8: u32(0xf947da60)
				0x2ac: u32(0xb4fff080)
				0x2b0: u32(0x52800048)
				0x2b4: u32(0x390283e8)
				0x2c8: u32(0xd2802811)
				0x2d4: u32(0x910283e1)
				0x2d8: u32(0xd102c3a2)
				0x2dc: u32(0xd2800003)
			}
		}
		'G17 reliability-monitor service binding' {
			{
				0x2ca4: u32(0xb0ff41a1)
				0x2ca8: u32(0x91378021)
				0x2cac: u32(0xaa1603e0)
				0x2cb4: u32(0xf942da68)
				0x2cb8: u32(0xf907d900)
			}
		}
		'G17 GPU-restart event' {
			{
				0x184: u32(0xb94053e8)
				0x188: u32(0x7100111f)
				0x190: u32(0xb9405ff6)
				0x194: u32(0xf9400288)
				0x198: u32(0xf940a100)
				0x1cc: u32(0xd2803a11)
				0x1d8: u32(0x910143e9)
				0x1dc: u32(0xb27e0121)
				0x27c: u32(0xf940ad20)
				0x280: u32(0x52800021)
			}
		}
		'G17 channel-error event' {
			{
				0x594: u32(0xb94053e8)
				0x598: u32(0x71001d1f)
				0x5a0: u32(0xb94057e8)
				0x5a4: u32(0x7100151f)
				0x5ac: u32(0xb9405be8)
				0x5b0: u32(0x71000d1f)
				0x5b8: u32(0xb9405ff6)
				0x5bc: u32(0xf9400288)
				0x5c0: u32(0xf940a100)
			}
		}
		'G17 shared-event signal completion' {
			{
				0x544: u32(0xb94053e8)
				0x548: u32(0x7100291f)
				0x54c: u32(0x54007bc1)
				0x550: u32(0xf84543e1)
				0x554: u32(0xb4007601)
				0x558: u32(0xb94067e8)
				0x55c: u32(0x34000108)
				0x560: u32(0xf9414e68)
				0x564: u32(0x5286aa09)
				0x568: u32(0x72a00029)
				0x56c: u32(0x8b090108)
				0x570: u32(0xf9400108)
				0x574: u32(0x91003108)
				0x578: u32(0x89ffd15)
				0x57c: u32(0xf9414e68)
				0x580: u32(0xf9407900)
			}
		}
		'G17 process-exit completion' {
			{
				0x94:  u32(0x5299701c)
				0x98:  u32(0x72a0003c)
				0x6f8: u32(0xb94053e8)
				0x6fc: u32(0x7100311f)
				0x700: u32(0x54006dc1)
				0x704: u32(0xf9414e68)
				0x708: u32(0x8b1c0108)
				0x70c: u32(0xf9400100)
				0x710: u32(0xb4ffcd60)
				0x714: u32(0xf84543f9)
				0x718: u32(0xaa1903e1)
				0x720: u32(0xaa0003f6)
				0x724: u32(0xf9414e68)
				0x728: u32(0x8b1c0108)
				0x72c: u32(0xf9400100)
				0x730: u32(0xaa1903e1)
				0x738: u32(0xb4ffcc36)
			}
		}
		else { panic(label) }
	}
}

fn event_validator_records() j.Value {
	return j.Value([
		j.Value([j.Value(0), j.Value(5268), j.Value('AGFIFirmwareEventAlive'),
			j.Value('kAGFIFirmwareEventTypeFirmwareAlive')]),
		j.Value([j.Value(1), j.Value(5244), j.Value('AGFIFirmwareEventStampUpdate'),
			j.Value('kAGFIFirmwareEventTypeStampsUpdated')]),
		j.Value([j.Value(4), j.Value(5256), j.Value('AGFIFirmwareEventHWRecovery'),
			j.Value('kAGFIFirmwareEventTypeGPURestart')]),
		j.Value([j.Value(6), j.Value(5488), j.Value('AGFIFirmwareEventPMRequestMemory'),
			j.Value('kAGFIFirmwareEventTypeAllocatePMMemory')]),
		j.Value([j.Value(7), j.Value(5328), j.Value('AGFIChannelErrorEventArgs'),
			j.Value('kAGFIFirmwareEventTypeChannelError')]),
		j.Value([j.Value(8), j.Value(5280), j.Value('AGFIFirmwareEventMetrologyAging'),
			j.Value('kAGFIFirmwareEventTypeMtrResult')]),
		j.Value([j.Value(9), j.Value(5340), j.Value('AGFIFirmwareEventUMARequestMemory'),
			j.Value('kAGFIFirmwareEventTypeUMAAsyncAlloc')]),
		j.Value([j.Value(10), j.Value(5316), j.Value('AGFIFirmwareEventSharedEventSignalComplete'),
			j.Value('kAGFIFirmwareEventTypeSharedEventSignalComplete')]),
		j.Value([j.Value(12), j.Value(5304), j.Value('AGFIFirmwareEventProcessExitComplete'),
			j.Value('kAGFIFirmwareEventTypeProcessExitComplete')]),
		j.Value([j.Value(13), j.Value(5232), j.Value('AGFIFirmwareEventUMAGrowPool'),
			j.Value('kAGFIFirmwareEventTypeUMAAsyncGrowRequestComplete')]),
		j.Value([j.Value(14), j.Value(5292), j.Value('AGFIFirmwareEventRTCompletionInfo'),
			j.Value('kAGFIFirmwareEventTypeRTCompletionEvent')]),
		j.Value([j.Value(15), j.Value(5220), j.Value('AGFIFirmwareEventUMAThresholdInterrupt'),
			j.Value('kAGFIFirmwareEventTypeUMAThresholdInterrupt')]),
	])
}

fn event_metadata(operation string) j.Value {
	match operation {
		'recover_g17_akf_callback' {
			return j.Value(map[string]j.Value{
				'message_type':                    j.Value(2)
				'message_payload_consumed':        j.Value(false)
				'firmware_role_consumed':          j.Value(false)
				'accelerator_host_member':         j.Value(664)
				'callback_selector_member':        j.Value(1868)
				'event_source_array_member':       j.Value(1488)
				'event_source_stride':             j.Value(8)
				'signal_interrupt_vtable_slot':    j.Value(600)
				'get_interrupt_index_vtable_slot': j.Value(488)
				'handle_event_vtable_slot':        j.Value(808)
				'interrupt_count_property':        j.Value('interrupts')
				'interrupt_specifier_bytes':       j.Value(4)
				'selector_rules':                  j.Value(map[string]j.Value{
					'1_or_4':      j.Value(0)
					'5_through_8': j.Value(4)
				})
				't6050_interrupt_count':           j.Value(8)
				't6050_callback_interrupt_index':  j.Value(4)
				'clear_interrupts_vtable_slot':    j.Value(2176)
				'drain_event_ring_vtable_slot':    j.Value(2184)
				'drains_both_firmware_roles':      j.Value(true)
			})
		}
		'recover_g17_pm_memory_event_action' {
			return j.Value(map[string]j.Value{
				'type':                     j.Value(6)
				'record':                   j.Value('AGFIFirmwareEventPMRequestMemory')
				'stamp_slot_offset':        j.Value(4)
				'invalid_stamp_slot':       j.Value(-1)
				'manager_index_offset':     j.Value(8)
				'manager_index_limit':      j.Value(127)
				'request_value_offset':     j.Value(12)
				'request_kind_offset':      j.Value(16)
				'request_kind_limit':       j.Value(64)
				'firmware_token_offset':    j.Value(20)
				'firmware_token_bytes':     j.Value(8)
				'interrupt_action':         j.Value('enqueue_host_request_and_wake_worker')
				'host_request_ring':        j.Value(map[string]j.Value{
					'control_accelerator_member':             j.Value(105192)
					'entries_accelerator_member':             j.Value(104936)
					'entries':                                j.Value(8)
					'entry_bytes':                            j.Value(32)
					'worker_event_source_accelerator_member': j.Value(1128)
					'record_layout':                          j.Value(map[string]j.Value{
						'discriminator_offset':  j.Value(0)
						'discriminator':         j.Value(0)
						'manager_index_offset':  j.Value(8)
						'stamp_slot_offset':     j.Value(12)
						'request_value_offset':  j.Value(16)
						'request_kind_offset':   j.Value(20)
						'firmware_token_offset': j.Value(24)
					})
				})
				'device_control_response':  j.Value(map[string]j.Value{
					'command_type':              j.Value(8)
					'submission_flags':          j.Value(25)
					'role':                      j.Value(0)
					'entry_bytes':               j.Value(64)
					'request_kind_offset':       j.Value(4)
					'copied_host_request_range': j.Value(map[string]j.Value{
						'source_offset': j.Value(8)
						'target_offset': j.Value(8)
						'bytes':         j.Value(24)
					})
					'zero_range':                j.Value(map[string]j.Value{
						'offset': j.Value(32)
						'bytes':  j.Value(32)
					})
					'token_check':               j.Value(map[string]j.Value{
						'entry_offset':       j.Value(24)
						'accelerator_member': j.Value(1672)
					})
					'doorbell':                  j.Value(u64(9511602413006487569))
					'doorbell_count':            j.Value(1)
					'doorbell_wait_argument':    j.Value(1)
				})
				'manager_class':            j.Value('AGXHWParamBufferManager')
				'parameter_manager_member': j.Value(152)
				'host_action':              j.Value('AGXParameterManagement::growImmediately')
				'host_action_vtable_slot':  j.Value(400)
				'vinix_policy':             j.Value('stop_gpu_without_parameter_memory_manager')
			})
		}
		'recover_g17_uma_async_alloc_event_action' {
			return j.Value(map[string]j.Value{
				'type':                              j.Value(9)
				'record':                            j.Value('AGFIFirmwareEventUMARequestMemory')
				'request_index_offset':              j.Value(4)
				'request_index_limit':               j.Value(256)
				'ignored_event_offsets':             j.Value([j.Value(8)])
				'required_nonzero_u64_offset':       j.Value(12)
				'stamp_slot_offset':                 j.Value(20)
				'invalid_stamp_slot':                j.Value(-1)
				'request_value_offset':              j.Value(24)
				'wait_for_host_ring_offset':         j.Value(28)
				'disabled_guard_accelerator_member': j.Value(108896)
				'interrupt_action':                  j.Value('enqueue_host_request_and_wake_worker')
				'host_request_ring':                 j.Value(map[string]j.Value{
					'control_accelerator_member':             j.Value(107248)
					'entries_accelerator_member':             j.Value(1743600)
					'entries':                                j.Value(64)
					'entry_bytes':                            j.Value(32)
					'worker_event_source_accelerator_member': j.Value(1136)
					'full_policy':                            j.Value(map[string]j.Value{
						'wait_flag_offset':  j.Value(28)
						'wait_microseconds': j.Value(100)
						'zero_flag':         j.Value('drop_request')
						'nonzero_flag':      j.Value('wait_for_room')
					})
					'record_layout':                          j.Value(map[string]j.Value{
						'request_index_offset':           j.Value(0)
						'reserved_004':                   j.Value(0)
						'required_value_offset':          j.Value(8)
						'stamp_and_request_value_offset': j.Value(16)
						'wait_for_host_ring_offset':      j.Value(24)
						'reserved_01c':                   j.Value(0)
					})
				})
				'registered_worker':                 j.Value('__ZN14AGXAccelerator22allocateUMAMemoryEventEP22IOInterruptEventSourcei')
				'worker_implementation':             j.Value('bti_c_ret')
				'device_control_response':           j.Value('none')
				'vinix_policy':                      j.Value('validate_and_consume_without_private_host_queue')
			})
		}
		'recover_g17_uma_flist_event_actions' {
			return j.Value([
				j.Value(map[string]j.Value{
					'manager_class':                j.Value('AGXUSCPrivMemFList')
					'flist_index_limit':            j.Value(256)
					'vinix_policy':                 j.Value('stop_gpu_without_usc_private_memory_manager')
					'type':                         j.Value(13)
					'record':                       j.Value('AGFIFirmwareEventUMAGrowPool')
					'stamp_slot_offset':            j.Value(4)
					'invalid_stamp_slot':           j.Value(-1)
					'flist_index_offset':           j.Value(8)
					'required_nonzero_u64_offsets': j.Value([j.Value(12), j.Value(20)])
					'grow_result_value_offset':     j.Value(28)
					'grow_result_flags_offset':     j.Value(36)
					'grow_engine_member':           j.Value(80)
					'host_action':                  j.Value('IAGXUSCPrivMemGrowEngine::retireGrowRequest')
					'host_action_vtable_slot':      j.Value(384)
				}),
				j.Value(map[string]j.Value{
					'manager_class':              j.Value('AGXUSCPrivMemFList')
					'flist_index_limit':          j.Value(256)
					'vinix_policy':               j.Value('stop_gpu_without_usc_private_memory_manager')
					'type':                       j.Value(15)
					'record':                     j.Value('AGFIFirmwareEventUMAThresholdInterrupt')
					'flist_index_offset':         j.Value(4)
					'current_threshold_member':   j.Value(128)
					'requested_threshold_member': j.Value(232)
					'host_action':                j.Value('Accelerator::halUpdateUMADesc')
					'host_action_vtable_slot':    j.Value(4384)
					'device_control_response':    j.Value(map[string]j.Value{
						'command_type':       j.Value(33)
						'entry_bytes':        j.Value(64)
						'flist_index_offset': j.Value(4)
						'zero_range':         j.Value(map[string]j.Value{
							'offset': j.Value(8)
							'bytes':  j.Value(56)
						})
					})
				}),
			])
		}
		'recover_g17_firmware_event_actions' {
			return j.Value(map[string]j.Value{
				'jump_table_host_noop_event_types':    j.Value([j.Value(2), j.Value(3), j.Value(5),
					j.Value(11)])
				'validator_rejected_noop_event_types': j.Value([j.Value(2), j.Value(3), j.Value(5)])
				'direct_host_noop_event_types':        j.Value([j.Value(11), j.Value(29)])
				'resolved_host_noop_events':           j.Value([j.Value(map[string]j.Value{
					'type':           j.Value(0)
					'dispatch':       j.Value('firmware_vtable')
					'vtable_slot':    j.Value(2168)
					'target':         j.Value('__ZN14AGXArmFirmware29handleFirmwareControllerEventEPK26AGFIFirmwareEventRingEntry')
					'implementation': j.Value('bti_c_ret')
				})])
				'host_noop_event_types':               j.Value([j.Value(0), j.Value(11), j.Value(29)])
				'fatal_events':                        j.Value([
					j.Value(map[string]j.Value{
						'type':               j.Value(4)
						'record':             j.Value('AGFIFirmwareEventHWRecovery')
						'stamp_slot_offset':  j.Value(12)
						'invalid_stamp_slot': j.Value(-1)
						'host_action':        j.Value('IOGPUScheduler::signalHardwareError')
						'restart_request':    j.Value(1)
						'vinix_policy':       j.Value('stop_gpu_without_recovery_engine')
					}),
					j.Value(map[string]j.Value{
						'type':               j.Value(7)
						'record':             j.Value('AGFIChannelErrorEventArgs')
						'subtype_offset':     j.Value(4)
						'subtype_limit':      j.Value(5)
						'data_master_offset': j.Value(8)
						'data_master_limit':  j.Value(3)
						'stamp_slot_offset':  j.Value(12)
						'invalid_stamp_slot': j.Value(-1)
						'host_action':        j.Value('AGXFirmware::handleChannelErrorEvent')
						'vinix_policy':       j.Value('stop_gpu_without_channel_recovery')
					}),
				])
				'advisory_events':                     j.Value([
					j.Value(map[string]j.Value{
						'type':                 j.Value(8)
						'record':               j.Value('AGFIFirmwareEventMetrologyAging')
						'payload_offset':       j.Value(4)
						'payload_bytes':        j.Value(4)
						'host_action':          j.Value('function-reliability_monitor')
						'host_action_optional': j.Value(true)
						'vinix_policy':         j.Value('consume_without_reliability_monitor')
					}),
					j.Value(map[string]j.Value{
						'type':           j.Value(14)
						'record':         j.Value('AGFIFirmwareEventRTCompletionInfo')
						'payload_offset': j.Value(4)
						'payload_bytes':  j.Value(8)
						'host_action':    j.Value('IOGPUFenceMachine::notifyCLPCIOPerfControl')
						'vinix_policy':   j.Value('consume_without_clpc_observers')
					}),
				])
				'host_service_events':                 j.Value([j.Value(map[string]j.Value{
					'type':                           j.Value(10)
					'record':                         j.Value('AGFIFirmwareEventSharedEventSignalComplete')
					'event_id_offset':                j.Value(4)
					'event_id_bytes':                 j.Value(8)
					'event_id_nonzero':               j.Value(true)
					'pre_signal_release_flag_offset': j.Value(20)
					'host_action':                    j.Value('IOSurfaceRoot::signalEventID')
					'host_action_id_bits':            j.Value(32)
					'vinix_policy':                   j.Value('consume_without_iosurface_registry')
				})])
				'host_lifecycle_events':               j.Value([j.Value(map[string]j.Value{
					'type':                         j.Value(12)
					'record':                       j.Value('AGFIFirmwareEventProcessExitComplete')
					'object_id_offset':             j.Value(4)
					'object_id_bytes':              j.Value(8)
					'namespace_accelerator_member': j.Value(117632)
					'host_actions':                 j.Value([
						j.Value('IOGPUWeakNamespace::getObject'),
						j.Value('IOGPUWeakNamespace::removeObject'),
					])
					'vinix_policy':                 j.Value('consume_without_iogpu_object_namespace')
				})])
				'unimplemented_action_event_types':    j.Value([j.Value(6), j.Value(13), j.Value(15)])
			})
		}
		'recover_g17_firmware_event_ring' {
			return j.Value(map[string]j.Value{
				'role_count':                 j.Value(2)
				'role_record_host_member':    j.Value(2672)
				'role_record_stride':         j.Value(304)
				'validator_host_member':      j.Value(1520)
				'validator_role_stride':      j.Value(576)
				'event_validator_member':     j.Value(528)
				'state_auxiliary_index':      j.Value(0)
				'entries_auxiliary_index':    j.Value(1)
				'state_bytes':                j.Value(48)
				'state_read_index_offset':    j.Value(0)
				'state_cfi_index_offset':     j.Value(16)
				'state_write_index_offset':   j.Value(32)
				'entry_bytes':                j.Value(72)
				'entries':                    j.Value(256)
				'entries_bytes':              j.Value(18432)
				'accepted_event_mask':        j.Value(536936403)
				'completion_event':           j.Value(map[string]j.Value{
					'type':                         j.Value(1)
					'firing_masks_offset':          j.Value(4)
					'firing_mask_words':            j.Value(4)
					'firing_stamp_slots':           j.Value(128)
					'checked_halfword_offset':      j.Value(20)
					'checked_halfword_limit':       j.Value(24)
					'signals_each_firing_stamp':    j.Value(true)
					'signals_stamps_updated':       j.Value(true)
					'tests_all_stamps_after_drain': j.Value(true)
				})
				'read_index_publish_barrier': j.Value('dmb ish')
			})
		}
		else { panic(operation) }
	}
}
