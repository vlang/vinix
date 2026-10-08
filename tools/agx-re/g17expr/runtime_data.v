module g17expr

import traceanalysis as j
import json2

// Checked producer instruction evidence and recovered fixed byte-field maps.
// These literals contain no recovery algorithm; checks and analysis live in
// bootstrap.v and the native runtime recovery routines.

fn runtime_symbol(name string) string {
	return match name {
		'ACCELERATOR_GET_GPTBAT_BASE' { '__ZN14AGXAccelerator13getGPTBATBaseEv' }
		'ACCELERATOR_START' { '__ZN14AGXAccelerator5startEP9IOService' }
		'AGX_LEGACY_MEMORY_MAP_VTABLE' { '__ZTV18AGXLegacyMemoryMap' }
		'AGX_SECURE_MEMORY_MAP_VTABLE' { '__ZTV18AGXSecureMemoryMap' }
		'BASE_CONFIGURE_DEVICE' { '__ZN14AGXAccelerator15configureDeviceEP9IOService' }
		'BASE_CONFIGURE_POWER' { '__ZN14AGXAccelerator38configurePowerAndPerformanceControllerEv' }
		'COMPLETE_FIRMWARE_DATA' { '__ZN14AGXArmFirmware20completeFirmwareDataEv' }
		'CONVERT_GPU_VA_TO_FW_VA' { '__ZNK14AGXArmFirmware18convertGPUVAToFWVAEyb' }
		'CREATE_FW_GPU_MAPPING' {
			'__ZN11AGXFirmware18createFWGPUMappingEP18IOMemoryDescriptorb10eGartRange'
		}
		'CREATE_FW_PIO_MAPPING' { '__ZN11AGXFirmware18createFWPIOMappingEPKyjPjbj10eGartRange' }
		'DEVICE_USER_GET_CONFIG' {
			'__ZN19AGXDeviceUserClient15getDeviceConfigEP16AGXGPUCoreConfig'
		}
		'G17_ACCELERATOR_START' { '__ZN32AGX·PI_300·X·A0·AcceleratorX5startEP9IOService' }
		'G17_ACCELERATOR_VTABLE' { '__ZTV18AGXAcceleratorG17X' }
		'G17_ADD_REGISTER_OVERRIDE' { '__ZN14AGXArmFirmware19addRegisterOverrideEjyy' }
		'G17_CONFIGURE_DEVICE' {
			'__ZN32AGX·PI_300·X·A0·AcceleratorX15configureDeviceEP9IOService'
		}
		'G17_CONFIGURE_POWER' {
			'__ZN32AGX·PI_300·X·A0·AcceleratorX38configurePowerAndPerformanceControllerEv'
		}
		'G17_DEFAULT_MCACHE_WRITES' {
			'__ZN32AGX·PI_300·X·A0·AcceleratorX25halGetDefaultMcacheWritesEv.8045'
		}
		'G17_DEFAULT_USC_MAX_TGMEM' {
			'__ZNK31AGX·PI_300·X·A0·Accelerator24halGetDefaultUscMaxTgmemEv'
		}
		'G17_FIRMWARE_VTABLE' { '__ZTV17AGXArmFirmwareASC' }
		'G17_FW_BRN_SIZE' { '__ZNK31AGX·PI_300·X·A0·Accelerator19getSizeOfFWBRNTableEv.8051' }
		'G17_GENERATE_CSC_COEFFICIENTS' {
			'__ZN31AGX·PI_300·X·A0·Accelerator23generateCSCCoefficientsEv'
		}
		'G17_GET_BORDER_COLOR_TABLE_GPU_ADDRESS' {
			'__ZN14AGXAccelerator29getBorderColorTableGPUAddressEv.8074'
		}
		'G17_GET_ENABLED_NUM_USCS' { '__ZNK14AGXAccelerator17getEnabledNumUSCsEv' }
		'G17_GET_SAMPLE_PERIOD' { '__ZN14AGXAccelerator15getSamplePeriodEv.8055' }
		'G17_LEGACY_GART_INIT_INFO' {
			'__ZN48AGX·PI_300·X·A0·LegacySharedGartTableBacking12initGartInfoEv'
		}
		'G17_LEGACY_SHARED_GART_VTABLE' { '__ZTV35AGXLegacySharedGartTableBackingG17X' }
		'G17_PBE_CSC_COEFFICIENTS' {
			'__ZZN31AGX·PI_300·X·A0·Accelerator23generateCSCCoefficientsEvE16pbe_coefficients'
		}
		'G17_PIO_TABLE' { '__ZNK32AGX·PI_300·X·A0·AcceleratorX25getPIORelativeOffsetTableEv' }
		'G17_PIO_TABLE_LENGTH' {
			'__ZNK32AGX·PI_300·X·A0·AcceleratorX31getPIORelativeOffsetTableLengthEv'
		}
		'G17_POPULATE_INIT_SEQUENCE' { '__ZN14AGXAccelerator28populateInitSequenceFirmwareEh.8148' }
		'G17_READ_CHIP_INFO' {
			'__ZNK32AGX·PI_300·X·A0·AcceleratorX12readChipInfoEP16AGXGPUCoreConfig'
		}
		'G17_SETUP_CSC_ALLOCATION' {
			'__ZN31AGX·PI_300·X·A0·Accelerator18setupCSCAllocationEv.8063'
		}
		'G17_TPU_CSC_COEFFICIENTS' {
			'__ZZN31AGX·PI_300·X·A0·Accelerator23generateCSCCoefficientsEvE16tpu_coefficients'
		}
		'GART_RANGES' { '__ZL11gart_ranges.12908' }
		'GET_UMA_MAX_ACTIVE_GTP_KICKS' { '__ZN14AGXAccelerator23getUMAMaxActiveGTPKicksEv' }
		'INIT_BASE_FIRMWARE_DATA' { '__ZN11AGXFirmware16initFirmwareDataEv' }
		'INIT_FIRMWARE_DATA' { '__ZN14AGXArmFirmware16initFirmwareDataEv' }
		'IOGPU_MEMORY_MAP_GPU_VA' { '__ZN14IOGPUMemoryMap20getGPUVirtualAddressEv' }
		'IOGPU_MEMORY_MAP_VTABLE' { '__ZTV14IOGPUMemoryMap' }
		'PERF_COUNTER_LOCK_ACCESS' { '__ZN17AGXPerfCtrSampler10lockAccessEbP9AGXShared' }
		'PERF_COUNTER_SOURCE_STOP' { '__ZN17AGXPerfCtrSampler17sourceSamplerStopEv' }
		'PI300_ACCELERATOR_START' { '__ZN31AGX·PI_300·X·A0·Accelerator5startEP9IOService' }
		'PI300_CONFIGURE_DEVICE' {
			'__ZN31AGX·PI_300·X·A0·Accelerator15configureDeviceEP9IOService'
		}
		'PI300_NEW_SECURE_MONITOR' {
			'__ZN31AGX·PI_300·X·A0·Accelerator19halNewSecureMonitorEv'
		}
		'PI300_READ_CHIP_INFO' {
			'__ZNK31AGX·PI_300·X·A0·Accelerator12readChipInfoEP16AGXGPUCoreConfig'
		}
		'PI300_READ_GPTBAT_BASE' {
			'__ZNK33AGX·PI_300·X·A0·SecureMonitor21readGPTBATBaseAddressEv'
		}
		'PI300_SECURE_MONITOR_VTABLE' { '__ZTV33AGX·PI_300·X·A0·SecureMonitor' }
		'PI300_SETUP_MMU_CONFIG' { '__ZN33AGX·PI_300·X·A0·SecureMonitor14setupMMUConfigEv' }
		'POPULATE_DPE_PPT_CONFIG' {
			'__ZN14AGXAccelerator24populateDPEPPTConfigDataEP19AGFDPEPPTConfigData'
		}
		'PREPARE_FIRMWARE_DATA' { '__ZN14AGXArmFirmware19prepareFirmwareDataEv' }
		'RETRIEVE_CHIP_INFO' { '__ZN14AGXAccelerator16retrieveChipInfoEP12AGXSChipInfo' }
		'SECURE_MONITOR_GET_GPTBAT_DESC' { '__ZN16AGXSecureMonitor13getGPTBATDescEv' }
		'SECURE_MONITOR_INIT' { '__ZN16AGXSecureMonitor4initEP14AGXAccelerator' }
		'SETUP_CONFIG' { '__ZN14AGXArmFirmware11setupConfigEv' }
		'SET_GVDM_MODE' { '__ZN14AGXAccelerator11setGVDMModeEjjj' }
		else { panic(name) }
	}
}

fn runtime_number(name string) int {
	return match name {
		'FIRMWARE_ADDRESS_CONVERSION_VTABLE_SLOT' { 728 }
		'G17_BORDER_COLOR_TABLE_ADDRESS_VTABLE_SLOT' { 3728 }
		'G17_CONFIGURE_DEVICE_VTABLE_SLOT' { 2392 }
		'G17_CONFIGURE_POWER_VTABLE_SLOT' { 2592 }
		'G17_DEFAULT_MCACHE_WRITES_VTABLE_SLOT' { 4080 }
		'G17_DEFAULT_USC_MAX_TGMEM_VTABLE_SLOT' { 4320 }
		'G17_FW_BRN_SIZE_VTABLE_SLOT' { 3984 }
		'G17_GENERATE_CSC_COEFFICIENTS_VTABLE_SLOT' { 4024 }
		'G17_GET_ENABLED_NUM_USCS_VTABLE_SLOT' { 2720 }
		'G17_GET_GPTBAT_BASE_VTABLE_SLOT' { 4560 }
		'G17_GET_SAMPLE_PERIOD_VTABLE_SLOT' { 3952 }
		'G17_INIT_SEQUENCE_VTABLE_SLOT' { 2696 }
		'G17_NEW_SECURE_MONITOR_VTABLE_SLOT' { 3040 }
		'G17_PIO_TABLE_LENGTH_VTABLE_SLOT' { 4464 }
		'G17_PIO_TABLE_VTABLE_SLOT' { 4456 }
		'G17_READ_CHIP_INFO_VTABLE_SLOT' { 4624 }
		'G17_RETRIEVE_CHIP_INFO_VTABLE_SLOT' { 3424 }
		'G17_SETUP_CSC_ALLOCATION_VTABLE_SLOT' { 3904 }
		'GART_INIT_INFO_VTABLE_SLOT' { 376 }
		'IOGPU_MEMORY_MAP_GPU_VA_MEMBER' { 40 }
		'IOGPU_MEMORY_MAP_GPU_VA_SLOT' { 344 }
		'SECURE_MONITOR_GET_GPTBAT_DESC_VTABLE_SLOT' { 344 }
		'SECURE_MONITOR_INIT_VTABLE_SLOT' { 336 }
		'SECURE_MONITOR_READ_GPTBAT_BASE_VTABLE_SLOT' { 312 }
		else { panic(name) }
	}
}

fn runtime_accessors() j.Value {
	return j.Value(map[string]j.Value{
		'dm_pause_mode':                          j.Value([
			j.Value('__ZN14AGXArmFirmware14setDMPauseModeEj'),
			j.Value([j.Value([j.Value(12), j.Value(4)])]),
		])
		'dm_pause_timer':                         j.Value([
			j.Value('__ZN14AGXArmFirmware15setDMPauseTimerEj'),
			j.Value([j.Value([j.Value(20), j.Value(4)])]),
		])
		'frg_task_timeout':                       j.Value([
			j.Value('__ZN14AGXArmFirmware17setFRGTaskTimeoutEj'),
			j.Value([j.Value([j.Value(40), j.Value(4)])]),
		])
		'smart_idle_enabled':                     j.Value([
			j.Value('__ZN14AGXArmFirmware21setSmartIdleOffEnableEb'),
			j.Value([j.Value([j.Value(52), j.Value(4)])]),
		])
		'cpms_window_size':                       j.Value([
			j.Value('__ZN14AGXArmFirmware17setCPMSWindowSizeEj'),
			j.Value([j.Value([j.Value(64), j.Value(4)])]),
		])
		'cpms_tfca_size':                         j.Value([
			j.Value('__ZN14AGXArmFirmware15setCPMSTFCASizeEj'),
			j.Value([j.Value([j.Value(68), j.Value(4)])]),
		])
		'command_submission_enabled':             j.Value([
			j.Value('__ZN14AGXArmFirmware27setCommandSubmissionEnabledEb.4234'),
			j.Value([j.Value([j.Value(120), j.Value(4)])]),
		])
		'performance_controller_target':          j.Value([
			j.Value('__ZN14AGXArmFirmware30setPerformanceControllerTargetEj'),
			j.Value([j.Value([j.Value(164), j.Value(4)])]),
		])
		'performance_controller_dead_zone':       j.Value([
			j.Value('__ZN14AGXArmFirmware32setPerformanceControllerDeadZoneEj'),
			j.Value([j.Value([j.Value(168), j.Value(4)])]),
		])
		'performance_controller_transfer_output': j.Value([
			j.Value('__ZN14AGXArmFirmware38setPerformanceControllerTransferOutputEj'),
			j.Value([j.Value([j.Value(172), j.Value(4)])]),
		])
		'performance_controller_dual_filter':     j.Value([
			j.Value('__ZN14AGXArmFirmware34setPerformanceControllerDualFilterEb'),
			j.Value([j.Value([j.Value(213), j.Value(1)]), j.Value([j.Value(220), j.Value(1)])]),
		])
		'clpc_deadline_control_effort':           j.Value([
			j.Value('__ZN14AGXArmFirmware28setCLPCDeadlineControlEffortEj'),
			j.Value([j.Value([j.Value(228), j.Value(4)])]),
		])
		'smart_idle_standby_timer_us':            j.Value([
			j.Value('__ZN14AGXArmFirmware29setSmartIdleOffStandbyTimerUSEj'),
			j.Value([j.Value([j.Value(1988), j.Value(4)])]),
		])
		'smart_idle_probability_initial':         j.Value([
			j.Value('__ZN14AGXArmFirmware26setSmartIdleOffProbInitValEf'),
			j.Value([j.Value([j.Value(1992), j.Value(4)])]),
		])
		'smart_idle_fn_hit':                      j.Value([
			j.Value('__ZN14AGXArmFirmware20setSmartIdleOffFnHitEf'),
			j.Value([j.Value([j.Value(1996), j.Value(4)])]),
		])
		'smart_idle_fi_hit':                      j.Value([
			j.Value('__ZN14AGXArmFirmware20setSmartIdleOffFiHitEf'),
			j.Value([j.Value([j.Value(2000), j.Value(4)])]),
		])
		'smart_idle_fn_miss':                     j.Value([
			j.Value('__ZN14AGXArmFirmware21setSmartIdleOffFnMissEf'),
			j.Value([j.Value([j.Value(2004), j.Value(4)])]),
		])
		'smart_idle_fi_miss':                     j.Value([
			j.Value('__ZN14AGXArmFirmware21setSmartIdleOffFiMissEf'),
			j.Value([j.Value([j.Value(2008), j.Value(4)])]),
		])
		'smart_idle_neighbor_hit':                j.Value([
			j.Value('__ZN14AGXArmFirmware21setSmartIdleOffNeiHitEf'),
			j.Value([j.Value([j.Value(2012), j.Value(4)])]),
		])
		'smart_idle_gpu_min_confidence':          j.Value([
			j.Value('__ZN14AGXArmFirmware31setSmartIdleOffGPUMinConfidenceEf'),
			j.Value([j.Value([j.Value(2016), j.Value(4)])]),
		])
		'smart_idle_gpu_high_confidence':         j.Value([
			j.Value('__ZN14AGXArmFirmware32setSmartIdleOffGPUHighConfidenceEf'),
			j.Value([j.Value([j.Value(2020), j.Value(4)])]),
		])
		'smart_idle_reset_iterations':            j.Value([
			j.Value('__ZN14AGXArmFirmware30setSmartIdleOffResetIterationsEj'),
			j.Value([j.Value([j.Value(2024), j.Value(4)])]),
		])
		'ut_engagement':                          j.Value([
			j.Value('__ZN14AGXArmFirmware18enableUTEngagementEb'),
			j.Value([j.Value([j.Value(2028), j.Value(4)]), j.Value([j.Value(2032), j.Value(4)])]),
		])
		'pmu_engagement':                         j.Value([
			j.Value('__ZN14AGXArmFirmware19enablePMUEngagementEb'),
			j.Value([j.Value([j.Value(2036), j.Value(4)])]),
		])
		'register_override_count':                j.Value([
			j.Value('__ZN14AGXArmFirmware22resetRegisterOverridesEv'),
			j.Value([j.Value([j.Value(2436), j.Value(4)])]),
		])
		'progress_check_interval_3d':             j.Value([
			j.Value('__ZN14AGXArmFirmware26setProgressCheckInterval3DEj'),
			j.Value([j.Value([j.Value(2460), j.Value(4)])]),
		])
		'progress_check_interval_ta':             j.Value([
			j.Value('__ZN14AGXArmFirmware26setProgressCheckIntervalTAEj'),
			j.Value([j.Value([j.Value(2464), j.Value(4)])]),
		])
		'progress_check_interval_cl':             j.Value([
			j.Value('__ZN14AGXArmFirmware26setProgressCheckIntervalCLEj'),
			j.Value([j.Value([j.Value(2468), j.Value(4)])]),
		])
		'progress_check_threshold':               j.Value([
			j.Value('__ZN14AGXArmFirmware25setProgressCheckThresholdEj'),
			j.Value([j.Value([j.Value(2472), j.Value(4)])]),
		])
		'progress_check_dm_config':               j.Value([
			j.Value('__ZN14AGXArmFirmware24setProgressCheckDmConfigE16AGXSLockupConfig19_AGFIDataMasterType'),
			j.Value([j.Value([j.Value(2476), j.Value(4)])]),
		])
		'gpu_idle_off_delay':                     j.Value([
			j.Value('__ZN14AGXArmFirmware18setGPUIdleOffDelayEjj'),
			j.Value([j.Value([j.Value(2492), j.Value(4)])]),
		])
		'fender_idle_off_delay':                  j.Value([
			j.Value('__ZN14AGXArmFirmware21setFenderIdleOffDelayEjj'),
			j.Value([j.Value([j.Value(2496), j.Value(4)])]),
		])
		'firmware_early_wake_timeout':            j.Value([
			j.Value('__ZN14AGXArmFirmware21setFWEarlyWakeTimeoutEjj'),
			j.Value([j.Value([j.Value(2500), j.Value(4)])]),
		])
		'gvdm_timer_interval':                    j.Value([
			j.Value('__ZN14AGXArmFirmware20setGVDMTimerIntervalEj'),
			j.Value([j.Value([j.Value(2504), j.Value(4)])]),
		])
		'cl_context_switch_timeout':              j.Value([
			j.Value('__ZN14AGXArmFirmware25setCLContextSwitchTimeoutEj'),
			j.Value([j.Value([j.Value(2508), j.Value(4)])]),
		])
		'cl_kill_timeout':                        j.Value([
			j.Value('__ZN14AGXArmFirmware16setCLKillTimeoutEj'),
			j.Value([j.Value([j.Value(2512), j.Value(4)])]),
		])
		'phase_one_cdm_context_switch_timeout':   j.Value([
			j.Value('__ZN14AGXArmFirmware34setPhaseOneCDMContextSwitchTimeoutEj'),
			j.Value([j.Value([j.Value(2516), j.Value(4)])]),
		])
		'frg_context_switch_timeout':             j.Value([
			j.Value('__ZN14AGXArmFirmware26setFRGContextSwitchTimeoutEj'),
			j.Value([j.Value([j.Value(2520), j.Value(4)])]),
		])
		'frg_kill_timeout':                       j.Value([
			j.Value('__ZN14AGXArmFirmware17setFRGKillTimeoutEj'),
			j.Value([j.Value([j.Value(2524), j.Value(4)])]),
		])
		'fw_util_default_fab_pstate':             j.Value([
			j.Value('__ZN14AGXArmFirmware25setFwUtilDefaultFabPStateEy'),
			j.Value([j.Value([j.Value(2536), j.Value(1)]), j.Value([j.Value(2537), j.Value(1)])]),
		])
		'fw_util_timer_period':                   j.Value([
			j.Value('__ZN14AGXArmFirmware20setFwUtilTimerPeriodEy'),
			j.Value([j.Value([j.Value(2538), j.Value(1)])]),
		])
		'fw_util_debounce_periods':               j.Value([
			j.Value('__ZN14AGXArmFirmware24setFwUtilDebouncePeriodsEy'),
			j.Value([j.Value([j.Value(2539), j.Value(1)]), j.Value([j.Value(2540), j.Value(1)])]),
		])
		'fw_util_pstate_threshold':               j.Value([
			j.Value('__ZN14AGXArmFirmware24setFwUtilPStateThresholdEy'),
			j.Value([j.Value([j.Value(2541), j.Value(1)]), j.Value([j.Value(2542), j.Value(1)])]),
		])
		'fw_util_pstate_step_size':               j.Value([
			j.Value('__ZN14AGXArmFirmware23setFwUtilPStateStepSizeEy'),
			j.Value([j.Value([j.Value(2543), j.Value(1)]), j.Value([j.Value(2544), j.Value(1)])]),
		])
		'gpu_keepalive_override':                 j.Value([
			j.Value('__ZN14AGXArmFirmware23setGPUKeepAliveOverrideE13AGXSKeepAlive'),
			j.Value([j.Value([j.Value(7216), j.Value(4)])]),
		])
		'gfxc_keepalive_override':                j.Value([
			j.Value('__ZN14AGXArmFirmware24setGFXCKeepAliveOverrideE13AGXSKeepAlive'),
			j.Value([j.Value([j.Value(7220), j.Value(4)])]),
		])
		'gpu_keepalive_perf_mode_threshold':      j.Value([
			j.Value('__ZN14AGXArmFirmware32setGPUKeepAlivePerfModeThresholdEj'),
			j.Value([j.Value([j.Value(7224), j.Value(4)])]),
		])
		'gpu_keepalive_off_mode_threshold':       j.Value([
			j.Value('__ZN14AGXArmFirmware31setGPUKeepAliveOffModeThresholdEj'),
			j.Value([j.Value([j.Value(7228), j.Value(4)])]),
		])
	})
}

fn runtime_virtual_returns() j.Value {
	return j.Value(map[string]j.Value{
		'4344': j.Value([j.Value('dup_min_count'),
			j.Value('__ZNK31AGX·PI_300·X·A0·Accelerator33halGetAgxCrUmaDefaultDupmMinCountEv.8028'),
			j.Value(1)])
		'4352': j.Value([j.Value('dup_max_count'),
			j.Value('__ZNK31AGX·PI_300·X·A0·Accelerator33halGetAgxCrUmaDefaultDupmMaxCountEv.8027'),
			j.Value(2)])
	})
}

fn runtime_words(label string) map[int]u32 {
	return match label {
		'G17 shared platform source initialization' {
			{
				0x444: u32(0x52821c08)
				0x448: u32(0x8b080208)
				0x44c: u32(0xf9487209)
				0x45c: u32(0xd73f0931)
				0x464: u32(0xb9009b00)
				0x68c: u32(0x6f00e400)
				0x690: u32(0x3dbde660)
			}
		}
		'GVDM runtime mode writer' {
			{
				0x2c: u32(0x529f0688)
				0x30: u32(0x8b080016)
				0x34: u32(0x2a010048)
				0x38: u32(0x7100011f)
				0x3c: u32(0x1a8303f8)
				0x40: u32(0xb94002c8)
				0x44: u32(0x6b01011f)
				0xe8: u32(0xaa1403e1)
				0xec: u32(0xf2f303b0)
				0xf0: u32(0xd73f0910)
				0xf4: u32(0xb90002d4)
			}
		}
		'G17 PIO source producer' {
			{
				0x1010: u32(0x911e0276)
				0x1014: u32(0xaa1603e0)
				0x1018: u32(0x529c3601)
				0x101c: u32(0x94ab642b)
				0x1020: u32(0x52800054)
				0x1024: u32(0xb90caab4)
				0x1064: u32(0xb9044314)
				0x1094: u32(0xb9000354)
				0x10fc: u32(0xb9087354)
				0x1130: u32(0xb90cab54)
				0x1198: u32(0xb9044334)
				0x11cc: u32(0xb9087b34)
				0x1200: u32(0xb90cb334)
				0x1234: u32(0xb9000b94)
				0x1268: u32(0xb9044394)
				0x12b8: u32(0xb90cb394)
				0x1464: u32(0xb90442f4)
				0x17ec: u32(0x52822d08)
				0x17f4: u32(0xf948b609)
				0x1804: u32(0xd73f0931)
				0x182c: u32(0x52822e08)
				0x1834: u32(0xf948ba09)
				0x1844: u32(0xd73f0931)
				0x1848: u32(0xb4000bc0)
				0x1850: u32(0x52808714)
				0x1854: u32(0x529b5b5a)
				0x1858: u32(0x72bb5b5a)
				0x187c: u32(0xb9400708)
				0x1888: u32(0xb9400308)
				0x18a4: u32(0x39400128)
				0x18bc: u32(0xf9400208)
				0x18c4: u32(0x52800001)
				0x18cc: u32(0xd73f0910)
				0x18d0: u32(0x29402309)
				0x18d4: u32(0x9bb47d29)
				0x18ec: u32(0x8b080009)
				0x18f0: u32(0xf9000549)
				0x18f4: u32(0xf9400709)
				0x18f8: u32(0xb9020949)
				0x18fc: u32(0xf9010948)
				0x1900: u32(0xb900055c)
			}
		}
		'G17 GART range table initialization' {
			{
				0xea0: u32(0x5293f018)
				0xea4: u32(0xb0ff41b9)
				0xea8: u32(0x911d8339)
				0xecc: u32(0x8b081728)
				0xed8: u32(0xa9402909)
				0xedc: u32(0x9adc2536)
				0xee0: u32(0x9adc2549)
			}
		}
		'G17 firmware-PIO physical alignment' {
			{
				0x30: u32(0x710004bf)
				0x38: u32(0xf9400028)
				0x50: u32(0xa2a010a)
				0x54: u32(0xb900006a)
				0x6c: u32(0x8a0a0100)
				0x74: u32(0x8b224108)
				0x84: u32(0x8a090108)
				0x88: u32(0xcb000101)
				0x8c: u32(0x7100029f)
				0x90: u32(0x52800068)
				0x94: u32(0x1a9f1502)
				0xa4: u32(0xaa1503e0)
				0xa8: u32(0xaa1603e1)
				0xac: u32(0xaa1403e2)
				0xb0: u32(0xaa1303e3)
			}
		}
		'G17 firmware-PIO mapping options' {
			{
				0x38: u32(0xd3607ec8)
				0x3c: u32(0x710026df)
				0x48: u32(0x710002bf)
				0x4c: u32(0x528000e9)
				0x50: u32(0xd28000aa)
				0x54: u32(0xf2c0200a)
				0x58: u32(0x9a8a1129)
				0x90: u32(0xaa080122)
			}
		}
		'G17 hardware-config address-space prefix' {
			{
				0x1478: u32(0xf9415e68)
				0x1480: u32(0x3dc35920)
				0x1484: u32(0xd2c00209)
				0x1488: u32(0x4e080d21)
				0x148c: u32(0xad000500)
				0x1490: u32(0xb27143e9)
				0x1494: u32(0xf2c05fe9)
				0x1498: u32(0xf9001109)
			}
		}
		'G17 optional CSC address publication' {
			{
				0x1538: u32(0x91406808)
				0x153c: u32(0x910d0108)
				0x1540: u32(0xf9400108)
				0x1544: u32(0xb40001c8)
				0x1558: u32(0xd2802b11)
				0x1570: u32(0xaa0003e8)
				0x1574: u32(0xf9415e69)
				0x157c: u32(0xf9001928)
			}
		}
		'G17 timestamp-area address publication' {
			{
				0x16a8: u32(0x910b6208)
				0x16b0: u32(0xd2b02801)
				0x16b4: u32(0xf2df8421)
				0x16b8: u32(0xf2ffffe1)
				0x16bc: u32(0xaa1303e0)
				0x16c0: u32(0x52800002)
				0x16f0: u32(0xf9001500)
			}
		}
		'G17 CSC coefficient producer' {
			{
				0x0:  u32(0xd503245f)
				0x4:  u32(0xd2800008)
				0x8:  u32(0x91406809)
				0xc:  u32(0x910d2129)
				0x10: u32(0x9140680a)
				0x14: u32(0x910d614a)
				0x18: u32(0x9140680b)
				0x1c: u32(0x9119616b)
				0x30: u32(0x8b08018e)
				0x34: u32(0x8b08012f)
				0x38: u32(0x8b0801b0)
				0x3c: u32(0x3dc001c0)
				0x40: u32(0x3d8001e0)
				0x44: u32(0x3dc00200)
				0x48: u32(0x3d80c1e0)
				0x4c: u32(0x8b08014f)
				0x50: u32(0x8b080171)
				0x54: u32(0xfd4009c0)
				0x58: u32(0xfd0001e0)
				0x5c: u32(0xfd400a00)
				0x60: u32(0xfd000220)
				0x64: u32(0x91006108)
				0x68: u32(0xf10c011f)
				0x6c: u32(0x54fffe21)
				0x70: u32(0xd65f03c0)
			}
		}
		'G17 base hardware-config scalar constants' {
			{
				0x1264: u32(0xf9415e68)
				0x1268: u32(0xb90ebd1f)
				0x126c: u32(0x52800036)
				0x1270: u32(0xb90ec916)
				0x13ac: u32(0x913ab128)
				0x13b4: u32(0x3dc35540)
				0x13b8: u32(0x3d800100)
				0x13e4: u32(0x721c017f)
				0x13e8: u32(0x5280190b)
				0x13ec: u32(0x1a9f156b)
				0x13f0: u32(0xb90ed52b)
				0x165c: u32(0xf9415e68)
				0x1660: u32(0xf9031d00)
				0x1664: u32(0x3968a6a9)
				0x1668: u32(0x5301052a)
				0x166c: u32(0xb90ea10a)
				0x1670: u32(0x53041129)
				0x1674: u32(0xb90ea909)
			}
		}
		'G17 ARM hardware-config scalar constants' {
			{
				0x4c:  u32(0x528bb808)
				0x50:  u32(0xb90ed128)
				0x58:  u32(0x913b9128)
				0x5c:  u32(0xb20003ea)
				0x60:  u32(0xf900010a)
				0x64:  u32(0x528003e8)
				0x68:  u32(0xb90f0528)
				0xb0:  u32(0x3dc35100)
				0xb4:  u32(0x3d83cd20)
				0x4e0: u32(0x52800029)
				0x4e4: u32(0xb90ee109)
			}
		}
		'G17 setupConfig scalar sources' {
			{
				0x34:  u32(0x529ee508)
				0x38:  u32(0x8b080018)
				0x52c: u32(0xb907067f)
				0x5a8: u32(0x6f00e401)
				0x5ac: u32(0x3d802f01)
				0x5b8: u32(0xfc044301)
				0x918: u32(0x52800008)
				0x91c: u32(0x52800629)
				0x920: u32(0xb9004709)
			}
		}
		'G17 setupConfig scalar publication' {
			{
				0x28:   u32(0xf9414e68)
				0x34:   u32(0x529eed8a)
				0x38:   u32(0x8b0a010a)
				0x44:   u32(0xf9415e6c)
				0x5c:   u32(0xb940014b)
				0x60:   u32(0xb90f4d8b)
				0x64:   u32(0x3cc6c140)
				0x68:   u32(0x3d83dd80)
				0x2fa0: u32(0xb9470509)
				0x2fa4: u32(0xf9415e6a)
				0x2fa8: u32(0xb90edd49)
			}
		}
		'G17 chip-info destination' {
			{
				0x610: u32(0x529ef908)
				0x634: u32(0x91358209)
				0x638: u32(0xf946b20a)
				0x63c: u32(0x8b080261)
				0x640: u32(0xaa1303e0)
				0x64c: u32(0xd73f0951)
			}
		}
		'G17 DeviceTree chip-info extraction' {
			{
				0xbc:  u32(0xb9400008)
				0xc0:  u32(0xb9000288)
				0x154: u32(0xb9400008)
				0x158: u32(0x53047d09)
				0x15c: u32(0x12000908)
				0x160: u32(0x2900a289)
			}
		}
		'G17 hardware-config chip-info publication' {
			{
				0x20: u32(0xf9414e68)
				0x24: u32(0x529ef909)
				0x28: u32(0x8b090108)
				0x2c: u32(0xf9415e69)
				0x30: u32(0x3dc00100)
				0x34: u32(0x3d83a520)
			}
		}
		'G17 power sample-period DeviceTree producer' {
			{
				0x34:  u32(0x529ee508)
				0x38:  u32(0x8b080018)
				0x5cc: u32(0x91049317)
				0x7c4: u32(0xb0ff41e1)
				0x7c8: u32(0x9115e821)
				0x808: u32(0xb9400008)
				0x80c: u32(0xb90002e8)
			}
		}
		'G17 getSamplePeriod provider' {
			{
				0x0:  u32(0xd503245f)
				0x4:  u32(0x529f0988)
				0x8:  u32(0x8b080008)
				0xc:  u32(0xb9400100)
				0x10: u32(0xd65f03c0)
			}
		}
		'G17 power sample-period firmware publication' {
			{
				0xdc: u32(0x913dc208)
				0xe0: u32(0xf947ba09)
				0xe4: u32(0xaa0803f1)
				0xe8: u32(0xf2edfa71)
				0xec: u32(0xd73f0931)
				0xf0: u32(0xf9415e68)
				0xf4: u32(0xb90ed900)
			}
		}
		'G17 default mcache-write provider' {
			{
				0x0:  u32(0xd503245f)
				0x4:  u32(0xd2800080)
				0x8:  u32(0xf2a0f000)
				0xc:  u32(0xf2c000c0)
				0x10: u32(0xd65f03c0)
			}
		}
		'G17 default mcache-write host publication' {
			{
				0x34:  u32(0x529ee508)
				0x38:  u32(0x8b080018)
				0x4d0: u32(0x913fc208)
				0x4d4: u32(0xf947fa09)
				0x4d8: u32(0xaa1303e0)
				0x4e4: u32(0xd73f0931)
				0x4ec: u32(0xf9000700)
			}
		}
		'G17 default mcache-write firmware publication' {
			{
				0x6a4: u32(0xf9414e68)
				0x6b0: u32(0x91403d09)
				0x714: u32(0xf943992a)
				0x718: u32(0x913c916c)
				0x71c: u32(0xf900018a)
			}
		}
		'G17 enabled-USC getter' {
			{
				0x0:  u32(0xd503245f)
				0x4:  u32(0xf9424008)
				0x8:  u32(0xf9424409)
				0xc:  u32(0xaa08012a)
				0x10: u32(0xb400016a)
				0x14: u32(0x9e670120)
				0x18: u32(0xe205800)
				0x1c: u32(0xe31b800)
				0x20: u32(0x1e260009)
				0x24: u32(0x9e670100)
				0x28: u32(0xe205800)
				0x2c: u32(0xe31b800)
				0x30: u32(0x1e260008)
				0x34: u32(0xb080120)
				0x38: u32(0xd65f03c0)
				0x3c: u32(0xb944b000)
				0x40: u32(0xd65f03c0)
			}
		}
		'G17 fixed +0xf740 configuration producer' {
			{
				0x34:  u32(0x529ee508)
				0x38:  u32(0x8b080018)
				0x44:  u32(0x5295d014)
				0x48:  u32(0x72bfffd4)
				0x50c: u32(0xf9000f14)
			}
		}
		'G17 enabled-USC firmware publication' {
			{
				0xed4: u32(0xf9414e60)
				0xee8: u32(0xd2815411)
				0xeec: u32(0x8b110210)
				0xef0: u32(0xf9400208)
				0xef8: u32(0xd73f0910)
				0xefc: u32(0xf9415e68)
				0xf08: u32(0x913e310a)
				0xf0c: u32(0xb90f8900)
				0xf10: u32(0xf9414e6b)
				0xf14: u32(0x529ee80c)
				0xf18: u32(0x8b0c016c)
				0xf1c: u32(0xf940018c)
				0xf20: u32(0xf900014c)
			}
		}
		'G17 PI_300 start call' {
			{
				0x1d4: u32(0xaa1303e0)
				0x1d8: u32(0xaa1403e1)
				0x1e0: u32(0x340012e0)
			}
		}
		'G17 UAT configuration producer' {
			{
				0x18: u32(0x91407008)
				0x1c: u32(0x912e8108)
				0x20: u32(0x529eee89)
				0x24: u32(0x8b090009)
				0x3c: u32(0x52800088)
				0x40: u32(0xb9000128)
				0x44: u32(0x52800028)
				0x48: u32(0x39001528)
			}
		}
		'G17 UAT configuration flag publication' {
			{
				0x498: u32(0x529eee89)
				0x49c: u32(0x8b090009)
				0x4a0: u32(0xb9400129)
				0x4a4: u32(0x7100013f)
				0x4a8: u32(0x1a9f07e9)
				0x4ac: u32(0xb90fad09)
			}
		}
		'G17 GPTBAT-base getter' {
			{
				0x0:  u32(0xd503245f)
				0x4:  u32(0x91407008)
				0x8:  u32(0x912cc108)
				0xc:  u32(0xf9400100)
				0x30: u32(0xd2802b11)
				0x34: u32(0x8b110210)
				0x38: u32(0xf9400208)
				0x40: u32(0xd73f0910)
				0x5c: u32(0xd65f03c0)
			}
		}
		'G17 GPTBAT physical-address consumer' {
			{
				0x8c: u32(0xd2802b11)
				0x90: u32(0x8b110210)
				0x94: u32(0xf9400208)
				0x98: u32(0xaa1303e0)
				0xa0: u32(0xd73f0910)
				0xa8: u32(0xd34ea402)
			}
		}
		'G17 preinitialized GPTBAT mapping' {
			{
				0xf0:  u32(0xaa0003f7)
				0xf4:  u32(0xb4000220)
				0xf8:  u32(0xf9400270)
				0x108: u32(0xd2802711)
				0x10c: u32(0x8b110210)
				0x110: u32(0xf9400208)
				0x114: u32(0xaa1303e0)
				0x11c: u32(0xd73f0910)
				0x120: u32(0xaa1503e1)
				0x124: u32(0x52800062)
				0x12c: u32(0xaa0003f4)
				0x130: u32(0xb5000140)
				0x1f8: u32(0xb40000d7)
				0x1fc: u32(0xa9015a74)
				0x200: u32(0xf9001260)
			}
		}
		'G17 GPTBAT register reader' {
			{
				0x1c: u32(0xd2803a11)
				0x20: u32(0x8b110210)
				0x24: u32(0xf9400208)
				0x28: u32(0x52900581)
				0x2c: u32(0x72a01a01)
				0x34: u32(0xd73f0910)
				0x38: u32(0xd3727c00)
				0x40: u32(0xd65f0fff)
			}
		}
		'G17 GPTBAT firmware publication' {
			{
				0x4b0: u32(0xf9400010)
				0x4c0: u32(0xd2823a11)
				0x4c4: u32(0x8b110210)
				0x4c8: u32(0xf9400208)
				0x4d0: u32(0xd73f0910)
				0x4d4: u32(0xf9415e68)
				0x4d8: u32(0x9140090a)
				0x4dc: u32(0xf907d900)
			}
		}
		'G17 readChipInfo wrapper' {
			{
				0x10: u32(0xaa0103f3)
				0x20: u32(0xbc089260)
				0x24: u32(0x3902127f)
				0x30: u32(0xd65f0fff)
			}
		}
		'G17 GPU core/revision identity decoder' {
			{
				0xec:  u32(0x53187ee8)
				0xf0:  u32(0x71002d1f)
				0xf8:  u32(0x53105ee8)
				0xfc:  u32(0x7100111f)
				0x16c: u32(0x7100053f)
				0x170: u32(0x540000a1)
				0x174: u32(0x7100051f)
				0x178: u32(0x54000061)
				0x17c: u32(0x52800088)
				0x180: u32(0x14000005)
				0x194: u32(0xb9002668)
				0x578: u32(0x52800448)
				0x57c: u32(0xb9002268)
			}
		}
		'G17 core-config export' {
			{
				0x8:  u32(0x3dc12100)
				0xc:  u32(0x3dc12501)
				0x10: u32(0x3dc12902)
				0x14: u32(0x3dc12d03)
				0x3c: u32(0xad019023)
				0x40: u32(0xad008821)
				0x44: u32(0x3d800020)
				0x4c: u32(0xd65f03c0)
			}
		}
		'G17 GPU identity firmware publication' {
			{
				0x1678: u32(0xf9414e69)
				0x167c: u32(0xfd425120)
				0x1680: u32(0xfd07dd00)
				0x1684: u32(0xb944b129)
				0x1688: u32(0xb90fc109)
			}
		}
		'PI_300 fixed accelerator feature mask' {
			{
				0x84: u32(0xf9436a68)
				0x9c: u32(0x52909809)
				0xa0: u32(0x72b00029)
				0xa4: u32(0xaa090108)
				0xa8: u32(0xf9036a68)
			}
		}
		'G17 fixed accelerator feature mask' {
			{
				0x94: u32(0xf9436a68)
				0x98: u32(0xd2a30049)
				0x9c: u32(0xf2e00029)
				0xa0: u32(0xaa090108)
				0xa4: u32(0xf9036a68)
			}
		}
		'G17 feature bit 10 hardware-config publication' {
			{
				0x1398: u32(0xf9414e60)
				0x139c: u32(0xb946d008)
				0x13cc: u32(0xb946d00b)
				0x13d0: u32(0x530a296b)
				0x13d4: u32(0xb90ec12b)
			}
		}
		else { panic(label) }
	}
}

fn runtime_sequence(label string) []u32 {
	return match label {
		'G17 shared-GART scalar fields' {
			[u32(0xf9003c1f), 0xd001d588, 0xb94c1108, 0x79003008, 0xd001d588, 0xb94c0108, 0x39006808]
		}
		'G17 shared-GART page geometry' {
			[u32(0xf0ffa3e8), 0xf941d908, 0xb9400108, 0x52800029, 0x1ac82128, 0x79004408, 0x79008408,
				0x7900c408, 0x52800809, 0x79004009, 0x53037d08, 0x79008008, 0x7900c008]
		}
		'G17 shared-GART fixed ranges' {
			[u32(0xd2c07e08), 0xf8034008, 0xb2672be8, 0xf8054008, 0x32122be8, 0xf8074008]
		}
		'firmware BRN workaround-table descriptor' {
			[u32(0x910bc268), 0x910ce269, 0xa90c27e8, 0xf9414e60, 0xf9400010, 0xaa0003f1, 0xf2f9b431,
				0xdac11a30, 0xaa1003f1, 0xdac147f1, 0xeb11021f, 0x54000040, 0xd4388e40, 0x913e4208,
				0xf947ca09, 0xaa0803f1, 0xf2fddd51, 0xd73f0931, 0xaa1503f1, 0x291a7fe0]
		}
		'bootstrap-region allocation' {
			[u32(0x52800029), 0x1ac0212a, 0x113ffd4b, 0x4b0a03ea, 0xa0a0161, 0x1ac82128, 0x93407d02,
				0x52800260]
		}
		'bootstrap-region CPU/GPU mapping pair' {
			[u32(0xf90d2a60), 0xb4005ba0, 0xaa1303e0, 0xaa1403e1, 0x52800002, 0x52800103, 0x97ff8f6b,
				0xf90d2e60]
		}
		'bootstrap-region cursor reset' { [u32(0xaa0003f3), 0xb91ac01f] }
		'bootstrap-region accelerator hook' { [u32(0xd2815111), 0x8b110210, 0xf9400208, 0x52800021] }
		'bootstrap-region terminator' {
			[u32(0xb95ac268), 0x8b080009, 0xb900113f, 0xa9007d3f, 0x11006108, 0xb91ac268]
		}
		'64-bit physical-address init-register record' {
			[u32(0x5280006a), 0x2901a933, 0xf9000135, 0xb9000936, 0x11006108, 0xb91ac288]
		}
		'64-bit init-register record' {
			[u32(0xb9000935), 0xf9000134, 0xf0ff3e2a, 0xfd43c540, 0xfc00c120, 0x11006108, 0xb91ac268]
		}
		'32-bit init-register record' {
			[u32(0xb9000934), 0xf9000135, 0xf0ff3e2a, 0xfd43f140, 0xfc00c120, 0x11006108, 0xb91ac268]
		}
		'small-shared host-ready initialization' {
			[u32(0xf945666b), 0xb9000576, 0xf945fe6b, 0xb9000576]
		}
		'small-shared trace-state update' {
			[u32(0x52802608), 0x9ba80068, 0x52800029, 0x392e1109, 0xb94b8909, 0xb90b8d09, 0xf9456508,
				0xb9000109]
		}
		'small-shared firmware-power-state polling' { [u32(0xf9456408), 0xb9401108] }
		'secondary small-shared firmware-power-state polling' { [u32(0xf945fe68), 0xb9401108] }
		'role 0 ASC power-generation wait' { [u32(0xf9456408), 0xb9401d08] }
		'role 1 ASC power-generation wait' { [u32(0xf945fe68), 0xb9401d08] }
		'role 0 ASC power-generation snapshot' { [u32(0xf9456408), 0xb9401d08] }
		'role 1 ASC power-generation snapshot' { [u32(0xf945fc08), 0xb9401d08] }
		'small-shared sleep-notification read' { [u32(0xf9456408), 0xb9400908] }
		'secondary small-shared sleep-notification read' { [u32(0xf945fc09), 0xb9400929] }
		'small-shared sleep-notification publication' {
			[u32(0xf9456408), 0x52800029, 0xb9000909, 0xf945fc08, 0xb9000909]
		}
		'register-override record selection' {
			[u32(0x8b0a054a), 0xd37df14a, 0x8b0a012b, 0xb9081561, 0x91201129]
		}
		'register-override values' { [u32(0xf9000182), 0x91203169, 0xf9000123] }
		'register-override count publication' { [u32(0xf941c108), 0xb9498509, 0x11000529, 0xb9098509] }
		'runtime base-state initialization' {
			[u32(0xb900010c), 0xb900051f, 0xb900091f, 0xb900191f, 0xb9001d1f]
		}
		'runtime virtual-device state' { [u32(0xf941c268), 0xb805e100, 0xb845e11f] }
		'runtime platform feature state' { [u32(0xf941c26a), 0xb8062149, 0xb9400109, 0xb9002149] }
		'runtime state-48 default' { [u32(0xf941c26a), 0xb900495f] }
		'runtime RIART defaults' {
			[u32(0xf941c268), 0x52839029, 0x8b090109, 0x5280002a, 0xb900012a, 0x528390a9, 0x8b090109,
				0xb900013f, 0x52839129, 0x8b090109, 0xb900013f, 0x528391a9, 0x8b090108, 0xb900011f]
		}
		'runtime platform halfword copy' {
			[u32(0xf941c269), 0xb900153f, 0xf9414e68, 0x9140390a, 0x794ed10b, 0x7900a92b, 0x794ed50b,
				0x7900ad2b, 0x794ed90b, 0x7900b12b]
		}
		'runtime early defaults' { [u32(0xf941c269), 0xb909c93f] }
		'runtime unaligned state-5a default' { [u32(0xf941c268), 0xb805a11f] }
		'runtime kick-channel defaults' {
			[u32(0xf9466a6b), 0x5298e50c, 0x8b0c016b, 0xb900017f, 0xb900513f, 0xb9004d3f, 0xb940016c,
				0x3400008c, 0xb940017f, 0xb940513f, 0xb9404d3f, 0xb909e13f]
		}
		'runtime Smart Idle policy copy' {
			[u32(0xbd495140), 0xbd07cd20, 0xbd495540, 0xbd07d120, 0xbd495940, 0xbd07d520, 0xbd495d40,
				0xbd07d920, 0xbd496140, 0xbd07dd20, 0xbd496540, 0xbd07e120, 0xbd496940, 0xbd07e520,
				0xbd496d40, 0x7e21d800, 0x1e39000b, 0xb907e92b, 0xb949494b, 0xb907c52b, 0xbd494d40,
				0xbd07c920]
		}
		'runtime role-state zero source' {
			[u32(0x6f00e400), 0xfd07a960, 0xb90f5d7f, 0xfd07b160, 0xb90f957f, 0xb946d109, 0x53186129,
				0xb90f8169, 0xb94ed569, 0x7100053f, 0x1a9f8529, 0xf941c26a, 0xb806a149, 0x5283882c,
				0x8b0c014c, 0xb9000189, 0x528388a9, 0x8b090149, 0xfd000120, 0x528389a9, 0x8b090149,
				0xb900013f]
		}
		'runtime CPMS defaults' { [u32(0xb925b93f), 0xb900411f, 0xb900451f] }
		'runtime late callback state' { [u32(0xf941c269), 0xb91c2d28] }
		'runtime base power defaults' {
			[u32(0xf941c269), 0x91281128, 0xb900312b, 0xb947014b, 0xb9002d2b, 0xb946fd4a, 0x3400006a,
				0xb900952a, 0xb900ad2a, 0x6f00e400, 0xad000100, 0xf900111f]
		}
		'runtime host policy snapshot' {
			[u32(0xf941c008), 0x5284f909, 0x8b090009, 0xad410121, 0xad400d22, 0x3c8b4103, 0x3c8c4101,
				0x3c8d4100, 0x3c8a4102]
		}
		'runtime power-controller prefix' {
			[u32(0xf941c268), 0x9104b109, 0xb940628a, 0xb900ed0a, 0xb940668a, 0xb900f10a]
		}
		'runtime twin power-controller tables' {
			[u32(0x914046aa), 0x9107814a, 0x9112d10b, 0x5280080c, 0xf940014d, 0xd109216e, 0xf90001cd,
				0xf941254d, 0xf800856d, 0x9100214a, 0xf100058c, 0x54ffff21]
		}
		'runtime power-controller tail' { [u32(0xf943168a), 0xf902c52a, 0xf9431a8a, 0xf902c92a] }
		'runtime power-controller tail end' { [u32(0xf943968a), 0xf903452a, 0xf9439a8a, 0xf903492a] }
		'runtime power-controller completion' { [u32(0xf941c268), 0xb9009d1f, 0xb900a11f] }
		'G17 DPE/PPT runtime source' { [u32(0xf9416e75), 0x914046b4, 0xf9414e60] }
		'G17 DPE/PPT producer call' { [u32(0x91360208), 0xf946c209, 0x914046aa, 0x91017141] }
		'G17 performance-controller policy clear' {
			[u32(0x911fa708), 0x911fc709, 0x911f870a, 0xb900011f, 0xb900013f, 0xb900015f, 0x391feb1f,
				0x391ff31f, 0x391ffb1f, 0x911fb708, 0xb900011f, 0x911fd708, 0xb900011f, 0x911f9708,
				0xb900011f, 0x391fef1f, 0x391ff71f, 0x391fff1f, 0x391fe71f, 0x3920031f, 0xb927ca7f,
				0xb927d27f, 0xb927d67f, 0x391f831f, 0xb927da7f, 0xb927ce7f, 0xb927de7f]
		}
		'G17 performance-controller policy snapshot' {
			[u32(0xf941c008), 0x5284f909, 0x8b090009, 0xad410121, 0xad400d22, 0x3c8b4103, 0x3c8c4101,
				0x3c8d4100, 0x3c8a4102]
		}
		'G17 runtime platform halfword install' {
			[u32(0xf0ff3dc8), 0xfd448900, 0x12800008, 0xb9077268, 0xd0ff3e48, 0x9111a508, 0xf9344268,
				0x90ffa439, 0xf941db39, 0xb9400328, 0x1ac82308, 0x528fffe9, 0xb090109, 0x4b0803e8,
				0xa080128, 0x3906629f, 0xfd03b660]
		}
		'base Smart Idle policy install' {
			[u32(0xf0ff41c8), 0x3dc29500, 0x3c8142e0, 0x528000c8, 0xb90026e8, 0x52805788, 0xb90002e8,
				0xf0ff41c8, 0x3dc29900, 0x3c8042e0]
		}
		'G17 Smart Idle minimum-confidence override' {
			[u32(0x52933348), 0x72a7e328, 0xb902e688, 0x52801f09, 0xb902ba89, 0xb942b28a, 0x1aca0929,
				0xb902b689, 0x91093289, 0xd0ff3d6a, 0xfd44b940, 0xfd000120, 0x52933349, 0x72a7d329,
				0xb9002e89, 0x52a83109, 0xb9002289, 0x52800209, 0xb9000289, 0xd0ff3d69, 0xfd44bd20,
				0xfd0002a0, 0xd0ff3d69, 0xfd44c120, 0xfd04cea0, 0xb9001ec8, 0x5280bb88, 0xb90002c8]
		}
		'role-0 0x68-byte region clear' {
			[u32(0xf9417268), 0xf900311f, 0x6f00e400, 0xad020100, 0xad010100, 0xad000100]
		}
		'role-0 0x800-byte region clear' { [u32(0xf9417660), 0x52810001, 0x94aa5cc1] }
		'shared 0x88-byte control block clear' {
			[u32(0xf9417e68), 0xf900411f, 0x6f00e400, 0xad030100, 0xad020100, 0xad010100, 0xad000100]
		}
		'role-0 bootstrap region clears' {
			[u32(0xf9416260), 0x52818301, 0x94aa5eb6, 0xf9416660, 0x52820901, 0x94aa5eb3, 0xf9416a60,
				0x5281c201, 0x94aa5eb0]
		}
		'role-0 bootstrap sentinels' { [u32(0xf9416668), 0x12800009, 0xb90a1909, 0xb90a3109] }
		'G17 firmware-PIO virtual-address publication' {
			[u32(0x928108f5), 0x52835917, 0x52838e18, 0x14000009, 0xf9415e68, 0x8b150108, 0xf907491f,
				0x910022f7, 0x91001318, 0x9110e294, 0xb100a2b5, 0x540005a0, 0xf9400688, 0xb4fffee8,
				0xb9420a88, 0x34fffea8, 0x39400288, 0x3707fe68]
		}
		'G17 firmware-PIO mapped-address conversion' {
			[u32(0x8b170268), 0xf9400100, 0xf9400010, 0xaa0003f1, 0xf2f9b431, 0xdac11a30, 0xd2802b11,
				0x8b110210, 0xf9400208, 0xf2e63530, 0xd73f0910, 0xaa1603f1, 0x8b180268, 0xb9400108,
				0xf9400270, 0xdac11a30, 0xaa1003f1, 0xdac147f1, 0xeb11021f, 0x54000040, 0xd4388e40,
				0x910b6209, 0xf9416e0a, 0x8b080001, 0xaa1303e0, 0x52800002, 0xaa0903f1, 0xf2f24a11,
				0xd73f0951, 0xf9415e68, 0x8b150108, 0xf9074900]
		}
		else { panic(label) }
	}
}

fn runtime_proofs(operation string) [][]string {
	return match operation {
		'recover_g17_platform_config' {
			[['require_instruction_sequence', 'G17 shared-GART scalar fields', 'code'],
				['require_instruction_sequence', 'G17 shared-GART page geometry', 'code'],
				['require_instruction_sequence', 'G17 shared-GART fixed ranges', 'code']]
		}
		'recover_g17_brn_workaround_table' {
			[['require_instruction_sequence', 'firmware BRN workaround-table descriptor',
				'allocation_code']]
		}
		'recover_g17_bootstrap_region' {
			[
				['require_instruction_sequence', 'bootstrap-region allocation', 'allocation_code'],
				['require_instruction_sequence', 'bootstrap-region CPU/GPU mapping pair',
					'allocation_code'],
				['require_instruction_sequence', 'bootstrap-region cursor reset', 'prepare_code'],
				['require_instruction_sequence', 'bootstrap-region accelerator hook', 'prepare_code'],
				['require_instruction_sequence', 'bootstrap-region terminator', 'prepare_code'],
				['require_instruction_sequence', '64-bit physical-address init-register record',
					'set_64_pa_code'],
				['require_instruction_sequence', '64-bit init-register record', 'set_64_code'],
				['require_instruction_sequence', '32-bit init-register record', 'set_32_code'],
			]
		}
		'recover_g17_small_shared_data' {
			[
				['require_instruction_sequence', 'small-shared host-ready initialization',
					'base_init_code'],
				['require_instruction_sequence', 'small-shared trace-state update', 'ktrace_code'],
				['require_instruction_sequence', 'small-shared firmware-power-state polling',
					'wait_power_off_code'],
				['require_instruction_sequence', 'secondary small-shared firmware-power-state polling',
					'wait_power_off_code'],
				['require_instruction_sequence', 'role 0 ASC power-generation wait',
					'wait_generation_code'],
				['require_instruction_sequence', 'role 1 ASC power-generation wait',
					'wait_generation_code'],
				['require_instruction_sequence', 'role 0 ASC power-generation snapshot',
					'snapshot_generation_code'],
				['require_instruction_sequence', 'role 1 ASC power-generation snapshot',
					'snapshot_generation_code'],
				['require_instruction_sequence', 'small-shared sleep-notification read',
					'get_sleep_code'],
				['require_instruction_sequence', 'secondary small-shared sleep-notification read',
					'get_sleep_code'],
				['require_instruction_sequence', 'small-shared sleep-notification publication',
					'set_sleep_code'],
			]
		}
		'recover_g17_runtime_controls' {
			[
				['require_instruction_sequence', 'register-override record selection',
					'register_override_code'],
				['require_instruction_sequence', 'register-override values', 'register_override_code'],
				['require_instruction_sequence', 'register-override count publication',
					'register_override_code'],
			]
		}
		'recover_g17_runtime_initialization' {
			[
				['require_instruction_sequence', 'runtime base-state initialization', 'base_init_code'],
				['require_instruction_sequence', 'runtime virtual-device state', 'base_init_code'],
				['require_instruction_sequence', 'runtime platform feature state', 'base_init_code'],
				['require_instruction_sequence', 'runtime state-48 default', 'base_init_code'],
				['require_instruction_sequence', 'runtime RIART defaults', 'base_init_code'],
				['require_instruction_sequence', 'runtime platform halfword copy', 'arm_init_code'],
				['require_instruction_sequence', 'runtime early defaults', 'arm_init_code'],
				['require_instruction_sequence', 'runtime unaligned state-5a default', 'arm_init_code'],
				['require_instruction_sequence', 'runtime kick-channel defaults', 'arm_init_code'],
				['require_instruction_sequence', 'runtime Smart Idle policy copy', 'arm_init_code'],
				['require_instruction_sequence', 'runtime role-state zero source', 'arm_init_code'],
				['require_instruction_sequence', 'runtime CPMS defaults', 'arm_init_code'],
				['require_instruction_sequence', 'runtime late callback state', 'arm_init_code'],
				['require_instruction_sequence', 'runtime base power defaults', 'base_power_code'],
				['require_instruction_sequence', 'runtime host policy snapshot', 'arm_power_code'],
				['require_instruction_sequence', 'runtime power-controller prefix', 'arm_power_code'],
				['require_instruction_sequence', 'runtime twin power-controller tables',
					'arm_power_code'],
				['require_instruction_sequence', 'runtime power-controller tail', 'arm_power_code'],
				['require_instruction_sequence', 'runtime power-controller tail end', 'arm_power_code'],
				['require_instruction_sequence', 'runtime power-controller completion', 'arm_power_code'],
			]
		}
		'recover_g17_runtime_power_policy' {
			[
				['require_instruction_sequence', 'G17 DPE/PPT runtime source', 'arm_power_code'],
				['require_instruction_sequence', 'G17 DPE/PPT producer call', 'arm_power_code'],
			]
		}
		'recover_g17_runtime_performance_policy' {
			[
				['require_instruction_sequence', 'G17 performance-controller policy clear', 'setup_code'],
				['require_instruction_sequence', 'G17 performance-controller policy snapshot',
					'arm_power_code'],
			]
		}
		'recover_g17_runtime_platform_policy' {
			[
				['require_instruction_sequence', 'G17 runtime platform halfword install',
					'pi_device_code'],
				['require_instruction_sequence', 'base Smart Idle policy install', 'base_power_code'],
				['require_instruction_sequence', 'G17 Smart Idle minimum-confidence override',
					'g17_power_code'],
			]
		}
		'recover_g17_shared_platform_values' {
			[
				['require_instruction_words_at', 'G17 shared platform source initialization',
					'base_code'],
				['require_instruction_words_at', 'GVDM runtime mode writer', 'setter_code'],
			]
		}
		'recover_g17_zero_initialized_allocations' {
			[['require_instruction_sequence', 'role-0 0x68-byte region clear', 'code'],
				['require_instruction_sequence', 'role-0 0x800-byte region clear', 'code'],
				['require_instruction_sequence', 'shared 0x88-byte control block clear', 'code']]
		}
		'recover_g17_role0_bootstrap_regions' {
			[['require_instruction_sequence', 'role-0 bootstrap region clears', 'code'],
				['require_instruction_sequence', 'role-0 bootstrap sentinels', 'code']]
		}
		'recover_g17_pio_mappings' {
			[['require_instruction_words_at', 'G17 PIO source producer', 'configure_code']]
		}
		'recover_g17_pio_uat_mapping' {
			[
				['require_instruction_words_at', 'G17 GART range table initialization', 'start_code'],
				['require_instruction_words_at', 'G17 firmware-PIO physical alignment', 'pio_code'],
				['require_instruction_words_at', 'G17 firmware-PIO mapping options', 'gpu_code'],
				['require_instruction_sequence', 'G17 firmware-PIO virtual-address publication',
					'init_code'],
				['require_instruction_sequence', 'G17 firmware-PIO mapped-address conversion',
					'init_code'],
			]
		}
		'recover_g17_address_space_layout' {
			[
				['require_instruction_words_at', 'G17 hardware-config address-space prefix',
					'base_init_code'],
				['require_instruction_words_at', 'G17 optional CSC address publication',
					'base_init_code'],
				['require_instruction_words_at', 'G17 timestamp-area address publication',
					'base_init_code'],
			]
		}
		'recover_g17_color_matrices' {
			[['require_instruction_words_at', 'G17 CSC coefficient producer', 'code']]
		}
		'recover_g17_hardware_config_constants' {
			[
				['require_instruction_words_at', 'G17 base hardware-config scalar constants',
					'base_init_code'],
				['require_instruction_words_at', 'G17 ARM hardware-config scalar constants',
					'arm_init_code'],
			]
		}
		'recover_g17_setup_config_constants' {
			[
				['require_instruction_words_at', 'G17 setupConfig scalar sources', 'configure_code'],
				['require_instruction_words_at', 'G17 setupConfig scalar publication', 'arm_setup_code'],
			]
		}
		'recover_g17_chip_info' {
			[
				['require_instruction_words_at', 'G17 chip-info destination', 'configure_code'],
				['require_instruction_words_at', 'G17 DeviceTree chip-info extraction', 'retrieve_code'],
				['require_instruction_words_at', 'G17 hardware-config chip-info publication',
					'arm_init_code'],
			]
		}
		'recover_g17_power_sample_period' {
			[
				['require_instruction_words_at', 'G17 power sample-period DeviceTree producer',
					'configure_code'],
				['require_instruction_words_at', 'G17 getSamplePeriod provider', 'getter_code'],
				['require_instruction_words_at', 'G17 power sample-period firmware publication',
					'arm_init_code'],
			]
		}
		'recover_g17_default_mcache_writes' {
			[
				['require_instruction_words_at', 'G17 default mcache-write provider', 'getter_code'],
				['require_instruction_words_at', 'G17 default mcache-write host publication',
					'configure_code'],
				['require_instruction_words_at', 'G17 default mcache-write firmware publication',
					'arm_init_code'],
			]
		}
		'recover_g17_enabled_usc_config' {
			[['require_instruction_words_at', 'G17 enabled-USC getter', 'getter_code'],
				['require_instruction_words_at', 'G17 fixed +0xf740 configuration producer',
					'configure_code'],
				['require_instruction_words_at', 'G17 enabled-USC firmware publication', 'arm_init_code']]
		}
		'recover_g17_uat_config_flag' {
			[['require_instruction_words_at', 'G17 PI_300 start call', 'g17_code'],
				['require_instruction_words_at', 'G17 UAT configuration producer', 'pi_code'],
				['require_instruction_words_at', 'G17 UAT configuration flag publication',
					'arm_init_code']]
		}
		'recover_g17_gptbat_base' {
			[['require_instruction_words_at', 'G17 GPTBAT-base getter', 'getter_code'],
				['require_instruction_words_at', 'G17 GPTBAT physical-address consumer', 'setup_code'],
				['require_instruction_words_at', 'G17 preinitialized GPTBAT mapping',
					'monitor_init_code'],
				['require_instruction_words_at', 'G17 GPTBAT register reader', 'read_code'],
				['require_instruction_words_at', 'G17 GPTBAT firmware publication', 'arm_init_code']]
		}
		'recover_g17_gpu_identity_config' {
			[['require_instruction_words_at', 'G17 readChipInfo wrapper', 'g17_code'],
				['require_instruction_words_at', 'G17 GPU core/revision identity decoder', 'pi_code'],
				['require_instruction_words_at', 'G17 core-config export', 'config_code'],
				['require_instruction_words_at', 'G17 GPU identity firmware publication',
					'base_init_code']]
		}
		'recover_g17_feature_defaults' {
			[
				['require_instruction_words_at', 'PI_300 fixed accelerator feature mask', 'pi_code'],
				['require_instruction_words_at', 'G17 fixed accelerator feature mask', 'g17_code'],
				['require_instruction_words_at', 'G17 feature bit 10 hardware-config publication',
					'base_init_code'],
			]
		}
		else { [][]string{} }
	}
}

fn runtime_metadata(operation string) j.Value {
	return match operation {
		'recover_g17_bootstrap_region' {
			j.Value(map[string]j.Value{
				'bytes':                   j.Value(16384)
				'requested_bytes':         j.Value(4096)
				'page_shift':              j.Value(14)
				'host_cpu_member':         j.Value(6736)
				'host_gpu_mapping_member': j.Value(6744)
				'cursor_host_member':      j.Value(6848)
				'entry':                   j.Value(map[string]j.Value{
					'bytes':            j.Value(24)
					'value_offset':     j.Value(0)
					'register_offset':  j.Value(8)
					'auxiliary_offset': j.Value(12)
					'kind_offset':      j.Value(16)
					'padding_offset':   j.Value(20)
					'kinds':            j.Value(map[string]j.Value{
						'terminator':                j.Value(0)
						'write_32':                  j.Value(1)
						'write_64':                  j.Value(2)
						'write_64_physical_address': j.Value(3)
					})
				})
				'terminator':              j.Value(map[string]j.Value{
					'offset':        j.Value(0)
					'zeroed_bytes':  j.Value(20)
					'padding_bytes': j.Value(4)
				})
			})
		}
		'recover_g17_bootstrap_roots' {
			j.Value(map[string]j.Value{
				'bytes':                     j.Value(16384)
				'firmware_page_shift':       j.Value(14)
				'host_page_aligned':         j.Value(true)
				'memory_options':            j.Value(19)
				'cpu_mapping_vtable_offset': j.Value(552)
				'cpu_address_vtable_offset': j.Value(312)
				'firmware_gart_range':       j.Value(8)
				'prepared_by':               j.Value('__ZN14AGXArmFirmware19prepareFirmwareDataEv')
				'completed_by':              j.Value('__ZN14AGXArmFirmware20completeFirmwareDataEv')
				'roles':                     j.Value([
					j.Value(map[string]j.Value{
						'role':                    j.Value(0)
						'host_cpu_mapping_member': j.Value(6624)
						'host_gpu_mapping_member': j.Value(6632)
					}),
					j.Value(map[string]j.Value{
						'role':                    j.Value(1)
						'host_cpu_mapping_member': j.Value(6680)
						'host_gpu_mapping_member': j.Value(6688)
					}),
				])
			})
		}
		'recover_g17_small_shared_data' {
			j.Value(map[string]j.Value{
				'bytes':  j.Value(32)
				'roles':  j.Value([
					j.Value(map[string]j.Value{
						'role':                    j.Value(0)
						'host_cpu_member':         j.Value(2760)
						'host_gpu_member':         j.Value(2768)
						'trace_state_host_member': j.Value(2956)
					}),
					j.Value(map[string]j.Value{
						'role':                    j.Value(1)
						'host_cpu_member':         j.Value(3064)
						'host_gpu_member':         j.Value(3072)
						'trace_state_host_member': j.Value(3260)
					}),
				])
				'fields': j.Value([
					j.Value(map[string]j.Value{
						'offset': j.Value(0)
						'bytes':  j.Value(4)
						'name':   j.Value('ktrace_state')
						'owner':  j.Value('host')
					}),
					j.Value(map[string]j.Value{
						'offset':  j.Value(4)
						'bytes':   j.Value(4)
						'name':    j.Value('host_ready')
						'initial': j.Value(1)
					}),
					j.Value(map[string]j.Value{
						'offset': j.Value(8)
						'bytes':  j.Value(4)
						'name':   j.Value('system_sleep_notification')
					}),
					j.Value(map[string]j.Value{
						'offset': j.Value(12)
						'bytes':  j.Value(4)
						'name':   j.Value('reserved_00c')
					}),
					j.Value(map[string]j.Value{
						'offset': j.Value(16)
						'bytes':  j.Value(4)
						'name':   j.Value('firmware_power_state')
						'owner':  j.Value('firmware')
					}),
					j.Value(map[string]j.Value{
						'offset': j.Value(20)
						'bytes':  j.Value(4)
						'name':   j.Value('reserved_014')
					}),
					j.Value(map[string]j.Value{
						'offset': j.Value(24)
						'bytes':  j.Value(4)
						'name':   j.Value('reserved_018')
					}),
					j.Value(map[string]j.Value{
						'offset': j.Value(28)
						'bytes':  j.Value(4)
						'name':   j.Value('asc_power_generation')
						'owner':  j.Value('firmware')
					}),
				])
			})
		}
		'recover_g17_runtime_controls' {
			j.Value(map[string]j.Value{
				'bytes':                   j.Value(7328)
				'host_cpu_member':         j.Value(896)
				'host_gpu_member':         j.Value(904)
				'fields':                  j.Value([
					j.Value(map[string]j.Value{
						'name':     j.Value('dm_pause_mode')
						'accessor': j.Value('__ZN14AGXArmFirmware14setDMPauseModeEj')
						'stores':   j.Value([j.Value(map[string]j.Value{
							'offset': j.Value(12)
							'bytes':  j.Value(4)
						})])
					}),
					j.Value(map[string]j.Value{
						'name':     j.Value('dm_pause_timer')
						'accessor': j.Value('__ZN14AGXArmFirmware15setDMPauseTimerEj')
						'stores':   j.Value([j.Value(map[string]j.Value{
							'offset': j.Value(20)
							'bytes':  j.Value(4)
						})])
					}),
					j.Value(map[string]j.Value{
						'name':     j.Value('frg_task_timeout')
						'accessor': j.Value('__ZN14AGXArmFirmware17setFRGTaskTimeoutEj')
						'stores':   j.Value([j.Value(map[string]j.Value{
							'offset': j.Value(40)
							'bytes':  j.Value(4)
						})])
					}),
					j.Value(map[string]j.Value{
						'name':     j.Value('smart_idle_enabled')
						'accessor': j.Value('__ZN14AGXArmFirmware21setSmartIdleOffEnableEb')
						'stores':   j.Value([j.Value(map[string]j.Value{
							'offset': j.Value(52)
							'bytes':  j.Value(4)
						})])
					}),
					j.Value(map[string]j.Value{
						'name':     j.Value('cpms_window_size')
						'accessor': j.Value('__ZN14AGXArmFirmware17setCPMSWindowSizeEj')
						'stores':   j.Value([j.Value(map[string]j.Value{
							'offset': j.Value(64)
							'bytes':  j.Value(4)
						})])
					}),
					j.Value(map[string]j.Value{
						'name':     j.Value('cpms_tfca_size')
						'accessor': j.Value('__ZN14AGXArmFirmware15setCPMSTFCASizeEj')
						'stores':   j.Value([j.Value(map[string]j.Value{
							'offset': j.Value(68)
							'bytes':  j.Value(4)
						})])
					}),
					j.Value(map[string]j.Value{
						'name':     j.Value('command_submission_enabled')
						'accessor': j.Value('__ZN14AGXArmFirmware27setCommandSubmissionEnabledEb.4234')
						'stores':   j.Value([j.Value(map[string]j.Value{
							'offset': j.Value(120)
							'bytes':  j.Value(4)
						})])
					}),
					j.Value(map[string]j.Value{
						'name':     j.Value('performance_controller_target')
						'accessor': j.Value('__ZN14AGXArmFirmware30setPerformanceControllerTargetEj')
						'stores':   j.Value([j.Value(map[string]j.Value{
							'offset': j.Value(164)
							'bytes':  j.Value(4)
						})])
					}),
					j.Value(map[string]j.Value{
						'name':     j.Value('performance_controller_dead_zone')
						'accessor': j.Value('__ZN14AGXArmFirmware32setPerformanceControllerDeadZoneEj')
						'stores':   j.Value([j.Value(map[string]j.Value{
							'offset': j.Value(168)
							'bytes':  j.Value(4)
						})])
					}),
					j.Value(map[string]j.Value{
						'name':     j.Value('performance_controller_transfer_output')
						'accessor': j.Value('__ZN14AGXArmFirmware38setPerformanceControllerTransferOutputEj')
						'stores':   j.Value([j.Value(map[string]j.Value{
							'offset': j.Value(172)
							'bytes':  j.Value(4)
						})])
					}),
					j.Value(map[string]j.Value{
						'name':     j.Value('performance_controller_dual_filter')
						'accessor': j.Value('__ZN14AGXArmFirmware34setPerformanceControllerDualFilterEb')
						'stores':   j.Value([
							j.Value(map[string]j.Value{
								'offset': j.Value(213)
								'bytes':  j.Value(1)
							}),
							j.Value(map[string]j.Value{
								'offset': j.Value(220)
								'bytes':  j.Value(1)
							}),
						])
					}),
					j.Value(map[string]j.Value{
						'name':     j.Value('clpc_deadline_control_effort')
						'accessor': j.Value('__ZN14AGXArmFirmware28setCLPCDeadlineControlEffortEj')
						'stores':   j.Value([j.Value(map[string]j.Value{
							'offset': j.Value(228)
							'bytes':  j.Value(4)
						})])
					}),
					j.Value(map[string]j.Value{
						'name':     j.Value('smart_idle_standby_timer_us')
						'accessor': j.Value('__ZN14AGXArmFirmware29setSmartIdleOffStandbyTimerUSEj')
						'stores':   j.Value([j.Value(map[string]j.Value{
							'offset': j.Value(1988)
							'bytes':  j.Value(4)
						})])
					}),
					j.Value(map[string]j.Value{
						'name':     j.Value('smart_idle_probability_initial')
						'accessor': j.Value('__ZN14AGXArmFirmware26setSmartIdleOffProbInitValEf')
						'stores':   j.Value([j.Value(map[string]j.Value{
							'offset': j.Value(1992)
							'bytes':  j.Value(4)
						})])
					}),
					j.Value(map[string]j.Value{
						'name':     j.Value('smart_idle_fn_hit')
						'accessor': j.Value('__ZN14AGXArmFirmware20setSmartIdleOffFnHitEf')
						'stores':   j.Value([j.Value(map[string]j.Value{
							'offset': j.Value(1996)
							'bytes':  j.Value(4)
						})])
					}),
					j.Value(map[string]j.Value{
						'name':     j.Value('smart_idle_fi_hit')
						'accessor': j.Value('__ZN14AGXArmFirmware20setSmartIdleOffFiHitEf')
						'stores':   j.Value([j.Value(map[string]j.Value{
							'offset': j.Value(2000)
							'bytes':  j.Value(4)
						})])
					}),
					j.Value(map[string]j.Value{
						'name':     j.Value('smart_idle_fn_miss')
						'accessor': j.Value('__ZN14AGXArmFirmware21setSmartIdleOffFnMissEf')
						'stores':   j.Value([j.Value(map[string]j.Value{
							'offset': j.Value(2004)
							'bytes':  j.Value(4)
						})])
					}),
					j.Value(map[string]j.Value{
						'name':     j.Value('smart_idle_fi_miss')
						'accessor': j.Value('__ZN14AGXArmFirmware21setSmartIdleOffFiMissEf')
						'stores':   j.Value([j.Value(map[string]j.Value{
							'offset': j.Value(2008)
							'bytes':  j.Value(4)
						})])
					}),
					j.Value(map[string]j.Value{
						'name':     j.Value('smart_idle_neighbor_hit')
						'accessor': j.Value('__ZN14AGXArmFirmware21setSmartIdleOffNeiHitEf')
						'stores':   j.Value([j.Value(map[string]j.Value{
							'offset': j.Value(2012)
							'bytes':  j.Value(4)
						})])
					}),
					j.Value(map[string]j.Value{
						'name':     j.Value('smart_idle_gpu_min_confidence')
						'accessor': j.Value('__ZN14AGXArmFirmware31setSmartIdleOffGPUMinConfidenceEf')
						'stores':   j.Value([j.Value(map[string]j.Value{
							'offset': j.Value(2016)
							'bytes':  j.Value(4)
						})])
					}),
					j.Value(map[string]j.Value{
						'name':     j.Value('smart_idle_gpu_high_confidence')
						'accessor': j.Value('__ZN14AGXArmFirmware32setSmartIdleOffGPUHighConfidenceEf')
						'stores':   j.Value([j.Value(map[string]j.Value{
							'offset': j.Value(2020)
							'bytes':  j.Value(4)
						})])
					}),
					j.Value(map[string]j.Value{
						'name':     j.Value('smart_idle_reset_iterations')
						'accessor': j.Value('__ZN14AGXArmFirmware30setSmartIdleOffResetIterationsEj')
						'stores':   j.Value([j.Value(map[string]j.Value{
							'offset': j.Value(2024)
							'bytes':  j.Value(4)
						})])
					}),
					j.Value(map[string]j.Value{
						'name':     j.Value('ut_engagement')
						'accessor': j.Value('__ZN14AGXArmFirmware18enableUTEngagementEb')
						'stores':   j.Value([
							j.Value(map[string]j.Value{
								'offset': j.Value(2028)
								'bytes':  j.Value(4)
							}),
							j.Value(map[string]j.Value{
								'offset': j.Value(2032)
								'bytes':  j.Value(4)
							}),
						])
					}),
					j.Value(map[string]j.Value{
						'name':     j.Value('pmu_engagement')
						'accessor': j.Value('__ZN14AGXArmFirmware19enablePMUEngagementEb')
						'stores':   j.Value([j.Value(map[string]j.Value{
							'offset': j.Value(2036)
							'bytes':  j.Value(4)
						})])
					}),
					j.Value(map[string]j.Value{
						'name':     j.Value('register_override_count')
						'accessor': j.Value('__ZN14AGXArmFirmware22resetRegisterOverridesEv')
						'stores':   j.Value([j.Value(map[string]j.Value{
							'offset': j.Value(2436)
							'bytes':  j.Value(4)
						})])
					}),
					j.Value(map[string]j.Value{
						'name':     j.Value('progress_check_interval_3d')
						'accessor': j.Value('__ZN14AGXArmFirmware26setProgressCheckInterval3DEj')
						'stores':   j.Value([j.Value(map[string]j.Value{
							'offset': j.Value(2460)
							'bytes':  j.Value(4)
						})])
					}),
					j.Value(map[string]j.Value{
						'name':     j.Value('progress_check_interval_ta')
						'accessor': j.Value('__ZN14AGXArmFirmware26setProgressCheckIntervalTAEj')
						'stores':   j.Value([j.Value(map[string]j.Value{
							'offset': j.Value(2464)
							'bytes':  j.Value(4)
						})])
					}),
					j.Value(map[string]j.Value{
						'name':     j.Value('progress_check_interval_cl')
						'accessor': j.Value('__ZN14AGXArmFirmware26setProgressCheckIntervalCLEj')
						'stores':   j.Value([j.Value(map[string]j.Value{
							'offset': j.Value(2468)
							'bytes':  j.Value(4)
						})])
					}),
					j.Value(map[string]j.Value{
						'name':     j.Value('progress_check_threshold')
						'accessor': j.Value('__ZN14AGXArmFirmware25setProgressCheckThresholdEj')
						'stores':   j.Value([j.Value(map[string]j.Value{
							'offset': j.Value(2472)
							'bytes':  j.Value(4)
						})])
					}),
					j.Value(map[string]j.Value{
						'name':     j.Value('progress_check_dm_config')
						'accessor': j.Value('__ZN14AGXArmFirmware24setProgressCheckDmConfigE16AGXSLockupConfig19_AGFIDataMasterType')
						'stores':   j.Value([j.Value(map[string]j.Value{
							'offset': j.Value(2476)
							'bytes':  j.Value(4)
						})])
					}),
					j.Value(map[string]j.Value{
						'name':     j.Value('gpu_idle_off_delay')
						'accessor': j.Value('__ZN14AGXArmFirmware18setGPUIdleOffDelayEjj')
						'stores':   j.Value([j.Value(map[string]j.Value{
							'offset': j.Value(2492)
							'bytes':  j.Value(4)
						})])
					}),
					j.Value(map[string]j.Value{
						'name':     j.Value('fender_idle_off_delay')
						'accessor': j.Value('__ZN14AGXArmFirmware21setFenderIdleOffDelayEjj')
						'stores':   j.Value([j.Value(map[string]j.Value{
							'offset': j.Value(2496)
							'bytes':  j.Value(4)
						})])
					}),
					j.Value(map[string]j.Value{
						'name':     j.Value('firmware_early_wake_timeout')
						'accessor': j.Value('__ZN14AGXArmFirmware21setFWEarlyWakeTimeoutEjj')
						'stores':   j.Value([j.Value(map[string]j.Value{
							'offset': j.Value(2500)
							'bytes':  j.Value(4)
						})])
					}),
					j.Value(map[string]j.Value{
						'name':     j.Value('gvdm_timer_interval')
						'accessor': j.Value('__ZN14AGXArmFirmware20setGVDMTimerIntervalEj')
						'stores':   j.Value([j.Value(map[string]j.Value{
							'offset': j.Value(2504)
							'bytes':  j.Value(4)
						})])
					}),
					j.Value(map[string]j.Value{
						'name':     j.Value('cl_context_switch_timeout')
						'accessor': j.Value('__ZN14AGXArmFirmware25setCLContextSwitchTimeoutEj')
						'stores':   j.Value([j.Value(map[string]j.Value{
							'offset': j.Value(2508)
							'bytes':  j.Value(4)
						})])
					}),
					j.Value(map[string]j.Value{
						'name':     j.Value('cl_kill_timeout')
						'accessor': j.Value('__ZN14AGXArmFirmware16setCLKillTimeoutEj')
						'stores':   j.Value([j.Value(map[string]j.Value{
							'offset': j.Value(2512)
							'bytes':  j.Value(4)
						})])
					}),
					j.Value(map[string]j.Value{
						'name':     j.Value('phase_one_cdm_context_switch_timeout')
						'accessor': j.Value('__ZN14AGXArmFirmware34setPhaseOneCDMContextSwitchTimeoutEj')
						'stores':   j.Value([j.Value(map[string]j.Value{
							'offset': j.Value(2516)
							'bytes':  j.Value(4)
						})])
					}),
					j.Value(map[string]j.Value{
						'name':     j.Value('frg_context_switch_timeout')
						'accessor': j.Value('__ZN14AGXArmFirmware26setFRGContextSwitchTimeoutEj')
						'stores':   j.Value([j.Value(map[string]j.Value{
							'offset': j.Value(2520)
							'bytes':  j.Value(4)
						})])
					}),
					j.Value(map[string]j.Value{
						'name':     j.Value('frg_kill_timeout')
						'accessor': j.Value('__ZN14AGXArmFirmware17setFRGKillTimeoutEj')
						'stores':   j.Value([j.Value(map[string]j.Value{
							'offset': j.Value(2524)
							'bytes':  j.Value(4)
						})])
					}),
					j.Value(map[string]j.Value{
						'name':     j.Value('fw_util_default_fab_pstate')
						'accessor': j.Value('__ZN14AGXArmFirmware25setFwUtilDefaultFabPStateEy')
						'stores':   j.Value([
							j.Value(map[string]j.Value{
								'offset': j.Value(2536)
								'bytes':  j.Value(1)
							}),
							j.Value(map[string]j.Value{
								'offset': j.Value(2537)
								'bytes':  j.Value(1)
							}),
						])
					}),
					j.Value(map[string]j.Value{
						'name':     j.Value('fw_util_timer_period')
						'accessor': j.Value('__ZN14AGXArmFirmware20setFwUtilTimerPeriodEy')
						'stores':   j.Value([j.Value(map[string]j.Value{
							'offset': j.Value(2538)
							'bytes':  j.Value(1)
						})])
					}),
					j.Value(map[string]j.Value{
						'name':     j.Value('fw_util_debounce_periods')
						'accessor': j.Value('__ZN14AGXArmFirmware24setFwUtilDebouncePeriodsEy')
						'stores':   j.Value([
							j.Value(map[string]j.Value{
								'offset': j.Value(2539)
								'bytes':  j.Value(1)
							}),
							j.Value(map[string]j.Value{
								'offset': j.Value(2540)
								'bytes':  j.Value(1)
							}),
						])
					}),
					j.Value(map[string]j.Value{
						'name':     j.Value('fw_util_pstate_threshold')
						'accessor': j.Value('__ZN14AGXArmFirmware24setFwUtilPStateThresholdEy')
						'stores':   j.Value([
							j.Value(map[string]j.Value{
								'offset': j.Value(2541)
								'bytes':  j.Value(1)
							}),
							j.Value(map[string]j.Value{
								'offset': j.Value(2542)
								'bytes':  j.Value(1)
							}),
						])
					}),
					j.Value(map[string]j.Value{
						'name':     j.Value('fw_util_pstate_step_size')
						'accessor': j.Value('__ZN14AGXArmFirmware23setFwUtilPStateStepSizeEy')
						'stores':   j.Value([
							j.Value(map[string]j.Value{
								'offset': j.Value(2543)
								'bytes':  j.Value(1)
							}),
							j.Value(map[string]j.Value{
								'offset': j.Value(2544)
								'bytes':  j.Value(1)
							}),
						])
					}),
					j.Value(map[string]j.Value{
						'name':     j.Value('gpu_keepalive_override')
						'accessor': j.Value('__ZN14AGXArmFirmware23setGPUKeepAliveOverrideE13AGXSKeepAlive')
						'stores':   j.Value([j.Value(map[string]j.Value{
							'offset': j.Value(7216)
							'bytes':  j.Value(4)
						})])
					}),
					j.Value(map[string]j.Value{
						'name':     j.Value('gfxc_keepalive_override')
						'accessor': j.Value('__ZN14AGXArmFirmware24setGFXCKeepAliveOverrideE13AGXSKeepAlive')
						'stores':   j.Value([j.Value(map[string]j.Value{
							'offset': j.Value(7220)
							'bytes':  j.Value(4)
						})])
					}),
					j.Value(map[string]j.Value{
						'name':     j.Value('gpu_keepalive_perf_mode_threshold')
						'accessor': j.Value('__ZN14AGXArmFirmware32setGPUKeepAlivePerfModeThresholdEj')
						'stores':   j.Value([j.Value(map[string]j.Value{
							'offset': j.Value(7224)
							'bytes':  j.Value(4)
						})])
					}),
					j.Value(map[string]j.Value{
						'name':     j.Value('gpu_keepalive_off_mode_threshold')
						'accessor': j.Value('__ZN14AGXArmFirmware31setGPUKeepAliveOffModeThresholdEj')
						'stores':   j.Value([j.Value(map[string]j.Value{
							'offset': j.Value(7228)
							'bytes':  j.Value(4)
						})])
					}),
				])
				'register_overrides':      j.Value(map[string]j.Value{
					'offset':       j.Value(2052)
					'entries':      j.Value(16)
					'stride':       j.Value(24)
					'count_offset': j.Value(2436)
					'fields':       j.Value([
						j.Value(map[string]j.Value{
							'offset': j.Value(0)
							'bytes':  j.Value(8)
							'name':   j.Value('value')
						}),
						j.Value(map[string]j.Value{
							'offset': j.Value(8)
							'bytes':  j.Value(8)
							'name':   j.Value('mask')
						}),
						j.Value(map[string]j.Value{
							'offset': j.Value(16)
							'bytes':  j.Value(4)
							'name':   j.Value('register')
						}),
					])
				})
				'fw_util_pstate_controls': j.Value(map[string]j.Value{
					'offset':  j.Value(2539)
					'entries': j.Value(4)
					'stride':  j.Value(6)
					'fields':  j.Value([
						j.Value(map[string]j.Value{
							'offset': j.Value(0)
							'bytes':  j.Value(2)
							'name':   j.Value('debounce_periods')
						}),
						j.Value(map[string]j.Value{
							'offset': j.Value(2)
							'bytes':  j.Value(2)
							'name':   j.Value('pstate_threshold')
						}),
						j.Value(map[string]j.Value{
							'offset': j.Value(4)
							'bytes':  j.Value(2)
							'name':   j.Value('pstate_step_size')
						}),
					])
				})
			})
		}
		'recover_g17_runtime_initialization' {
			j.Value(map[string]j.Value{
				'bytes':                   j.Value(7328)
				'host_cpu_member':         j.Value(896)
				'host_gpu_member':         j.Value(904)
				'zero_initialized':        j.Value([
					j.Value(map[string]j.Value{
						'offset': j.Value(4)
						'bytes':  j.Value(4)
						'value':  j.Value(0)
					}),
					j.Value(map[string]j.Value{
						'offset': j.Value(8)
						'bytes':  j.Value(4)
						'value':  j.Value(0)
					}),
					j.Value(map[string]j.Value{
						'offset': j.Value(20)
						'bytes':  j.Value(4)
						'value':  j.Value(0)
					}),
					j.Value(map[string]j.Value{
						'offset': j.Value(24)
						'bytes':  j.Value(4)
						'value':  j.Value(0)
					}),
					j.Value(map[string]j.Value{
						'offset': j.Value(28)
						'bytes':  j.Value(4)
						'value':  j.Value(0)
					}),
					j.Value(map[string]j.Value{
						'offset': j.Value(64)
						'bytes':  j.Value(4)
						'value':  j.Value(0)
					}),
					j.Value(map[string]j.Value{
						'offset': j.Value(68)
						'bytes':  j.Value(4)
						'value':  j.Value(0)
					}),
					j.Value(map[string]j.Value{
						'offset': j.Value(72)
						'bytes':  j.Value(4)
						'value':  j.Value(0)
					}),
					j.Value(map[string]j.Value{
						'offset': j.Value(76)
						'bytes':  j.Value(4)
						'value':  j.Value(0)
					}),
					j.Value(map[string]j.Value{
						'offset': j.Value(80)
						'bytes':  j.Value(4)
						'value':  j.Value(0)
					}),
					j.Value(map[string]j.Value{
						'offset': j.Value(90)
						'bytes':  j.Value(4)
						'value':  j.Value(0)
					}),
					j.Value(map[string]j.Value{
						'offset': j.Value(156)
						'bytes':  j.Value(4)
						'value':  j.Value(0)
					}),
					j.Value(map[string]j.Value{
						'offset': j.Value(160)
						'bytes':  j.Value(4)
						'value':  j.Value(0)
					}),
					j.Value(map[string]j.Value{
						'offset': j.Value(2504)
						'bytes':  j.Value(4)
						'value':  j.Value(0)
					}),
					j.Value(map[string]j.Value{
						'offset': j.Value(2528)
						'bytes':  j.Value(4)
						'value':  j.Value(0)
					}),
					j.Value(map[string]j.Value{
						'offset': j.Value(2564)
						'bytes':  j.Value(40)
						'value':  j.Value(0)
					}),
					j.Value(map[string]j.Value{
						'offset': j.Value(7237)
						'bytes':  j.Value(8)
						'value':  j.Value(0)
					}),
					j.Value(map[string]j.Value{
						'offset': j.Value(7245)
						'bytes':  j.Value(4)
						'value':  j.Value(0)
					}),
					j.Value(map[string]j.Value{
						'offset': j.Value(7297)
						'bytes':  j.Value(4)
						'value':  j.Value(1)
					}),
					j.Value(map[string]j.Value{
						'offset': j.Value(7301)
						'bytes':  j.Value(4)
						'value':  j.Value(0)
					}),
					j.Value(map[string]j.Value{
						'offset': j.Value(7305)
						'bytes':  j.Value(4)
						'value':  j.Value(0)
					}),
					j.Value(map[string]j.Value{
						'offset': j.Value(7309)
						'bytes':  j.Value(4)
						'value':  j.Value(0)
					}),
				])
				'platform_copies':         j.Value([
					j.Value(map[string]j.Value{
						'destination_offset': j.Value(84)
						'bytes':              j.Value(6)
						'source':             j.Value('platform_config+0x768')
					}),
					j.Value(map[string]j.Value{
						'destination_offset': j.Value(164)
						'bytes':              j.Value(64)
						'source':             j.Value('firmware_host_object+0x27c8')
					}),
					j.Value(map[string]j.Value{
						'destination_offset':         j.Value(236)
						'bytes':                      j.Value(1752)
						'source':                     j.Value('power_controller_snapshot')
						'complete_destination_range': j.Value(true)
					}),
					j.Value(map[string]j.Value{
						'destination_offset': j.Value(1988)
						'bytes':              j.Value(40)
						'source':             j.Value('accelerator+0xe948')
						'converted_tail':     j.Value(true)
					}),
				])
				'power_controller_tables': j.Value([
					j.Value(map[string]j.Value{
						'destination_offset': j.Value(620)
						'source_offset':      j.Value(0)
						'bytes':              j.Value(512)
					}),
					j.Value(map[string]j.Value{
						'destination_offset': j.Value(1204)
						'source_offset':      j.Value(584)
						'bytes':              j.Value(512)
					}),
				])
				'dynamic_fields':          j.Value([
					j.Value(map[string]j.Value{
						'offset': j.Value(0)
						'bytes':  j.Value(4)
						'source': j.Value('platform_feature_mask')
					}),
					j.Value(map[string]j.Value{
						'offset': j.Value(32)
						'bytes':  j.Value(4)
						'source': j.Value('platform_config+0x131f8')
					}),
					j.Value(map[string]j.Value{
						'offset': j.Value(44)
						'bytes':  j.Value(4)
						'source': j.Value('platform_config+0x700')
					}),
					j.Value(map[string]j.Value{
						'offset': j.Value(48)
						'bytes':  j.Value(4)
						'source': j.Value('platform_feature_bit_0')
					}),
					j.Value(map[string]j.Value{
						'offset': j.Value(94)
						'bytes':  j.Value(4)
						'source': j.Value('virtual_device_callback')
					}),
					j.Value(map[string]j.Value{
						'offset': j.Value(98)
						'bytes':  j.Value(4)
						'source': j.Value('platform_feature_state')
					}),
					j.Value(map[string]j.Value{
						'offset': j.Value(106)
						'bytes':  j.Value(4)
						'source': j.Value('normalized_role_count')
					}),
					j.Value(map[string]j.Value{
						'offset': j.Value(7212)
						'bytes':  j.Value(4)
						'source': j.Value('firmware_callback')
					}),
					j.Value(map[string]j.Value{
						'offset': j.Value(7233)
						'bytes':  j.Value(4)
						'source': j.Value('normalized_role_count')
					}),
				])
			})
		}
		'recover_g17_runtime_power_policy' {
			j.Value(map[string]j.Value{
				'producer':                j.Value('__ZN14AGXAccelerator24populateDPEPPTConfigDataEP19AGFDPEPPTConfigData')
				'accelerator_vtable_slot': j.Value(3456)
				'host_object_base':        j.Value(69632)
				'cleared_source_offset':   j.Value(92)
				'cleared_source_bytes':    j.Value(1760)
				'copied_source_range':     j.Value(map[string]j.Value{
					'offset': j.Value(96)
					'bytes':  j.Value(1752)
				})
				'runtime_range':           j.Value(map[string]j.Value{
					'offset': j.Value(236)
					'bytes':  j.Value(1752)
					'value':  j.Value(0)
				})
			})
		}
		'recover_g17_runtime_performance_policy' {
			j.Value(map[string]j.Value{
				'producer':             j.Value('__ZN14AGXArmFirmware11setupConfigEv')
				'host_object_offset':   j.Value(10184)
				'cleared_source_bytes': j.Value(57)
				'copied_source_bytes':  j.Value(64)
				'runtime_range':        j.Value(map[string]j.Value{
					'offset': j.Value(164)
					'bytes':  j.Value(64)
				})
				'initial_value':        j.Value(0)
				'reserved_tail_bytes':  j.Value(7)
			})
		}
		'recover_g17_runtime_platform_policy' {
			j.Value(map[string]j.Value{
				'configure_device_vtable_slot': j.Value(2392)
				'configure_power_vtable_slot':  j.Value(2592)
				'platform_halfwords':           j.Value(map[string]j.Value{
					'source_offset':  j.Value(1896)
					'runtime_offset': j.Value(84)
					'values':         j.Value([j.Value(65535), j.Value(40), j.Value(65535)])
					'bytes':          j.Value('ffff2800ffff')
				})
				'smart_idle':                   j.Value(map[string]j.Value{
					'source_offset':  j.Value(59720)
					'runtime_offset': j.Value(1988)
					'bytes':          j.Value(40)
					'source_bytes':   j.Value('dc0500000000803fcdcc4c3fcdcc4c3e6666663fcdcccc3d0000803e9a99193f6666663f06000000')
					'runtime_bytes':  j.Value('dc0500000000803fcdcc4c3fcdcc4c3e6666663fcdcccc3d0000803e9a99193f6666663f0000c040')
					'runtime_fields': j.Value(map[string]j.Value{
						'standby_timer_us':            j.Value(1500)
						'probability_initial_bits':    j.Value(1065353216)
						'fn_hit_bits':                 j.Value(1061997773)
						'fi_hit_bits':                 j.Value(1045220557)
						'fn_miss_bits':                j.Value(1063675494)
						'fi_miss_bits':                j.Value(1036831949)
						'neighbor_hit_bits':           j.Value(1048576000)
						'gpu_min_confidence_bits':     j.Value(1058642330)
						'gpu_high_confidence_bits':    j.Value(1063675494)
						'reset_iterations_float_bits': j.Value(1086324736)
					})
				})
			})
		}
		'recover_g17_zero_initialized_allocations' {
			j.Value([
				j.Value(map[string]j.Value{
					'name':                    j.Value('role0_region_26c')
					'bytes':                   j.Value(104)
					'host_cpu_member':         j.Value(736)
					'host_gpu_member':         j.Value(808)
					'firmware_shared_offsets': j.Value([j.Value(map[string]j.Value{
						'role':   j.Value(0)
						'offset': j.Value(620)
					})])
				}),
				j.Value(map[string]j.Value{
					'name':                    j.Value('role0_region_274')
					'bytes':                   j.Value(2048)
					'host_cpu_member':         j.Value(744)
					'host_gpu_member':         j.Value(816)
					'firmware_shared_offsets': j.Value([j.Value(map[string]j.Value{
						'role':   j.Value(0)
						'offset': j.Value(628)
					})])
				}),
				j.Value(map[string]j.Value{
					'name':                    j.Value('shared_control')
					'bytes':                   j.Value(136)
					'host_cpu_member':         j.Value(760)
					'host_gpu_member':         j.Value(832)
					'firmware_shared_offsets': j.Value([
						j.Value(map[string]j.Value{
							'role':   j.Value(0)
							'offset': j.Value(16)
						}),
						j.Value(map[string]j.Value{
							'role':   j.Value(1)
							'offset': j.Value(16)
						}),
					])
				}),
			])
		}
		'recover_g17_role0_bootstrap_regions' {
			j.Value([
				j.Value(map[string]j.Value{
					'name':                   j.Value('role0_region_254')
					'bytes':                  j.Value(3096)
					'host_cpu_member':        j.Value(704)
					'host_gpu_member':        j.Value(776)
					'firmware_shared_offset': j.Value(596)
					'initial':                j.Value('zero')
				}),
				j.Value(map[string]j.Value{
					'name':                   j.Value('role0_region_25c')
					'bytes':                  j.Value(4168)
					'host_cpu_member':        j.Value(712)
					'host_gpu_member':        j.Value(784)
					'firmware_shared_offset': j.Value(604)
					'initial':                j.Value('zero_with_sentinels')
					'sentinels':              j.Value([
						j.Value(map[string]j.Value{
							'offset': j.Value(2584)
							'bytes':  j.Value(4)
							'value':  j.Value(u64(4294967295))
						}),
						j.Value(map[string]j.Value{
							'offset': j.Value(2608)
							'bytes':  j.Value(4)
							'value':  j.Value(u64(4294967295))
						}),
					])
				}),
				j.Value(map[string]j.Value{
					'name':                   j.Value('role0_region_264')
					'bytes':                  j.Value(3600)
					'host_cpu_member':        j.Value(720)
					'host_gpu_member':        j.Value(792)
					'firmware_shared_offset': j.Value(612)
					'initial':                j.Value('zero')
				}),
			])
		}
		'recover_g17_shared_platform_values' {
			j.Value(map[string]j.Value{
				'scalars':     j.Value([
					j.Value(map[string]j.Value{
						'role':            j.Value(1)
						'platform_offset': j.Value(63424)
						'shared_offset':   j.Value(768)
						'value':           j.Value(12)
						'producer':        j.Value('__ZNK31AGX·PI_300·X·A0·Accelerator24halGetDefaultUscMaxTgmemEv')
						'vtable_slot':     j.Value(4320)
					}),
					j.Value(map[string]j.Value{
						'role':                   j.Value(0)
						'platform_offset':        j.Value(63540)
						'shared_offset':          j.Value(772)
						'value':                  j.Value(0)
						'producer':               j.Value('zero/default GVDM mode before performance-counter access')
						'runtime_writer':         j.Value('__ZN14AGXAccelerator11setGVDMModeEjjj')
						'runtime_writer_callers': j.Value([
							j.Value('__ZN17AGXPerfCtrSampler10lockAccessEbP9AGXShared'),
							j.Value('__ZN17AGXPerfCtrSampler17sourceSamplerStopEv'),
						])
					}),
				])
				'calibration': j.Value(map[string]j.Value{
					'platform_offset': j.Value(63376)
					'shared_offset':   j.Value(1145)
					'roles':           j.Value([j.Value(0), j.Value(1)])
					'bytes':           j.Value(16)
					'initial_bytes':   j.Value('00000000000000000000000000000000')
				})
			})
		}
		'recover_g17_address_space_layout' {
			j.Value(map[string]j.Value{
				'offset':                      j.Value(0)
				'bytes':                       j.Value(56)
				'userspace_va_map':            j.Value(u64(476741369856))
				'userspace_va_limit':          j.Value(u64(4290772992))
				'usc_start':                   j.Value([j.Value(u64(68719476736)),
					j.Value(u64(68719476736))])
				'unknown_page':                j.Value(u64(3298534850560))
				'timestamp_area_base':         j.Value(u64(18446739819565416448))
				'yuv_csc_table_address':       j.Value(0)
				'csc_allocation_vtable_slot':  j.Value(3904)
				'csc_allocation_provider':     j.Value('__ZN31AGX·PI_300·X·A0·Accelerator18setupCSCAllocationEv.8063')
				'firmware_address_conversion': j.Value('__ZNK14AGXArmFirmware18convertGPUVAToFWVAEyb')
			})
		}
		'recover_g17_color_matrices' {
			j.Value(map[string]j.Value{
				'offset':               j.Value(56)
				'records':              j.Value(64)
				'record_bytes':         j.Value(24)
				'provider_vtable_slot': j.Value(4024)
				'provider':             j.Value('__ZN31AGX·PI_300·X·A0·Accelerator23generateCSCCoefficientsEv')
				'banks':                j.Value([
					j.Value(map[string]j.Value{
						'source':          j.Value('__ZZN31AGX·PI_300·X·A0·Accelerator23generateCSCCoefficientsEvE16tpu_coefficients')
						'records':         j.Value(32)
						'record_bytes':    j.Value(24)
						'nonzero_records': j.Value([j.Value(map[string]j.Value{
							'index':        j.Value(7)
							'coefficients': j.Value([j.Value(8200), j.Value(0), j.Value(0), j.Value(0),
								j.Value(0), j.Value(8200), j.Value(0), j.Value(0), j.Value(0),
								j.Value(0), j.Value(8200), j.Value(0)])
						})])
					}),
					j.Value(map[string]j.Value{
						'source':          j.Value('__ZZN31AGX·PI_300·X·A0·Accelerator23generateCSCCoefficientsEvE16pbe_coefficients')
						'records':         j.Value(32)
						'record_bytes':    j.Value(24)
						'nonzero_records': j.Value([j.Value(map[string]j.Value{
							'index':        j.Value(28)
							'coefficients': j.Value([j.Value(9797), j.Value(19235), j.Value(3736),
								j.Value(0), j.Value(-5537), j.Value(-10846), j.Value(16383),
								j.Value(16384), j.Value(16384), j.Value(-13730), j.Value(-2654),
								j.Value(16384)])
						})])
					}),
				])
			})
		}
		'recover_g17_hardware_config_constants' {
			j.Value(map[string]j.Value{
				'border_color_table_address': j.Value(map[string]j.Value{
					'offset':               j.Value(1592)
					'value':                j.Value(0)
					'provider_vtable_slot': j.Value(3728)
					'provider':             j.Value('__ZN14AGXAccelerator29getBorderColorTableGPUAddressEv.8074')
				})
				'scalar_block':               j.Value(map[string]j.Value{
					'offset':              j.Value(3728)
					'bytes':               j.Value(308)
					'debug_flags_initial': j.Value(0)
					'fixed_u32':           j.Value(map[string]j.Value{
						'0xeb8': j.Value(1)
						'0xec0': j.Value(1)
						'0xec8': j.Value(1)
						'0xed0': j.Value(24000)
						'0xed4': j.Value(1)
						'0xee0': j.Value(1)
						'0xee4': j.Value(1)
						'0xee8': j.Value(1)
						'0xf04': j.Value(31)
						'0xf34': j.Value(1)
						'0xf38': j.Value(1)
					})
					'feature_defaults':    j.Value(map[string]j.Value{
						'fixed_u32': j.Value(map[string]j.Value{
							'0xec0': j.Value(1)
						})
					})
				})
			})
		}
		'recover_g17_chip_info' {
			j.Value(map[string]j.Value{
				'offset':               j.Value(3728)
				'bytes':                j.Value(16)
				'source_record_offset': j.Value(63432)
				'retrieve_vtable_slot': j.Value(3424)
				'retrieve_provider':    j.Value('__ZN14AGXAccelerator16retrieveChipInfoEP12AGXSChipInfo')
				'fields':               j.Value([
					j.Value(map[string]j.Value{
						'offset':   j.Value(0)
						'property': j.Value('chip-id')
						'formula':  j.Value('value')
					}),
					j.Value(map[string]j.Value{
						'offset':   j.Value(4)
						'property': j.Value('chip-revision')
						'formula':  j.Value('value >> 4')
					}),
					j.Value(map[string]j.Value{
						'offset':   j.Value(8)
						'property': j.Value('chip-revision')
						'formula':  j.Value('value & 7')
					}),
					j.Value(map[string]j.Value{
						'offset': j.Value(12)
						'value':  j.Value(0)
					}),
				])
			})
		}
		'recover_g17_power_sample_period' {
			j.Value(map[string]j.Value{
				'offset':               j.Value(3800)
				'property':             j.Value('gpu-power-sample-period')
				'accelerator_offset':   j.Value(63564)
				'formula':              j.Value('value')
				'provider_vtable_slot': j.Value(3952)
				'provider':             j.Value('__ZN14AGXAccelerator15getSamplePeriodEv.8055')
			})
		}
		'recover_g17_default_mcache_writes' {
			j.Value(map[string]j.Value{
				'offset':               j.Value(3876)
				'bytes':                j.Value(8)
				'value':                j.Value(u64(25895632900))
				'source_offset':        j.Value(63280)
				'provider_vtable_slot': j.Value(4080)
				'provider':             j.Value('__ZN32AGX·PI_300·X·A0·AcceleratorX25halGetDefaultMcacheWritesEv.8045')
			})
		}
		'recover_g17_enabled_usc_config' {
			j.Value(map[string]j.Value{
				'enabled_usc_count': j.Value(map[string]j.Value{
					'offset':                     j.Value(3976)
					'core_mask_offsets':          j.Value([j.Value(1152), j.Value(1160)])
					'fallback_core_count_offset': j.Value(1200)
					'formula':                    j.Value('popcount(core_mask_0) + popcount(core_mask_1), else core_count')
					'provider_vtable_slot':       j.Value(2720)
					'provider':                   j.Value('__ZNK14AGXAccelerator17getEnabledNumUSCsEv')
				})
				'fixed_value':       j.Value(map[string]j.Value{
					'offset':        j.Value(3980)
					'bytes':         j.Value(8)
					'value':         j.Value(u64(4294880896))
					'source_offset': j.Value(63296)
				})
			})
		}
		'recover_g17_setup_config_constants' {
			j.Value(map[string]j.Value{
				'fixed_u32': j.Value(map[string]j.Value{
					'offset':        j.Value(3916)
					'source_offset': j.Value(63340)
					'value':         j.Value(49)
				})
				'zero_u32':  j.Value(map[string]j.Value{
					'0xedc': j.Value(map[string]j.Value{
						'source_offset': j.Value(1796)
					})
					'0xf70': j.Value(map[string]j.Value{
						'source_offset': j.Value(63448)
					})
					'0xf74': j.Value(map[string]j.Value{
						'source_offset': j.Value(63452)
					})
					'0xf78': j.Value(map[string]j.Value{
						'source_offset': j.Value(63456)
					})
					'0xf7c': j.Value(map[string]j.Value{
						'source_offset': j.Value(63460)
					})
				})
			})
		}
		'recover_g17_uat_config_flag' {
			j.Value(map[string]j.Value{
				'offset':        j.Value(4012)
				'value':         j.Value(1)
				'source_offset': j.Value(63348)
				'source_value':  j.Value(4)
				'formula':       j.Value('source != 0')
				'producer':      j.Value('__ZN31AGX·PI_300·X·A0·Accelerator5startEP9IOService')
				'g17_caller':    j.Value('__ZN32AGX·PI_300·X·A0·AcceleratorX5startEP9IOService')
			})
		}
		'recover_g17_gptbat_base' {
			j.Value(map[string]j.Value{
				'offset':                     j.Value(4016)
				'bytes':                      j.Value(8)
				'formula':                    j.Value('physical_address(gptbat_descriptor)')
				'ready_property':             j.Value('gptbat-ready')
				'hardware_register':          j.Value(13664300)
				'register_formula':           j.Value('u32(register) << 14')
				'uat_page_shift':             j.Value(14)
				'accelerator_vtable_slot':    j.Value(4560)
				'accelerator_provider':       j.Value('__ZN14AGXAccelerator13getGPTBATBaseEv')
				'secure_monitor_vtable_slot': j.Value(312)
				'secure_monitor_provider':    j.Value('__ZNK33AGX·PI_300·X·A0·SecureMonitor21readGPTBATBaseAddressEv')
			})
		}
		'recover_g17_gpu_identity_config' {
			j.Value(map[string]j.Value{
				'core_type':            j.Value(map[string]j.Value{
					'offset':               j.Value(4024)
					'source_offset':        j.Value(1184)
					'device_config_offset': j.Value(32)
					'id_version_selector':  j.Value(4)
					'selector_value':       j.Value(34)
				})
				'revision_id':          j.Value(map[string]j.Value{
					'offset':               j.Value(4028)
					'source_offset':        j.Value(1188)
					'device_config_offset': j.Value(36)
					'c0_decoder_value':     j.Value(4)
				})
				'active_core_count':    j.Value(map[string]j.Value{
					'offset':               j.Value(4032)
					'source_offset':        j.Value(1200)
					'device_config_offset': j.Value(48)
					'formula':              j.Value('active core count decoded from GPU identification registers')
				})
				'provider_vtable_slot': j.Value(4624)
				'provider':             j.Value('__ZNK32AGX·PI_300·X·A0·AcceleratorX12readChipInfoEP16AGXGPUCoreConfig')
			})
		}
		'recover_g17_feature_defaults' {
			j.Value(map[string]j.Value{
				'source_offset':                j.Value(1744)
				'configure_device_vtable_slot': j.Value(2392)
				'pi300_unconditional_mask':     j.Value(u64(2147583168))
				'g17_unconditional_mask':       j.Value(u64(281475379494912))
				'fixed_u32':                    j.Value(map[string]j.Value{
					'0xec0': j.Value(1)
				})
			})
		}
		'recover_g17_constant_virtual_returns' {
			j.Value(map[string]j.Value{
				'accelerator_vtable': j.Value('__ZTV18AGXAcceleratorG17X')
				'methods':            j.Value(map[string]j.Value{
					'dup_min_count': j.Value(map[string]j.Value{
						'vtable_slot':      j.Value(4344)
						'provider':         j.Value('__ZNK31AGX·PI_300·X·A0·Accelerator33halGetAgxCrUmaDefaultDupmMinCountEv.8028')
						'provider_address': j.Value(8454144)
						'value':            j.Value(1)
					})
					'dup_max_count': j.Value(map[string]j.Value{
						'vtable_slot':      j.Value(4352)
						'provider':         j.Value('__ZNK31AGX·PI_300·X·A0·Accelerator33halGetAgxCrUmaDefaultDupmMaxCountEv.8027')
						'provider_address': j.Value(8454156)
						'value':            j.Value(2)
					})
				})
			})
		}
		'recover_g17_memory_map_virtual_address' {
			j.Value(map[string]j.Value{
				'vtable_slot':      j.Value(344)
				'provider':         j.Value('__ZN14IOGPUMemoryMap20getGPUVirtualAddressEv')
				'provider_address': j.Value(172505964)
				'object_member':    j.Value(40)
				'inherited_by':     j.Value([j.Value('__ZTV14IOGPUMemoryMap'),
					j.Value('__ZTV18AGXLegacyMemoryMap'), j.Value('__ZTV18AGXSecureMemoryMap')])
			})
		}
		'recover_g17_pio_mappings' {
			j.Value(map[string]j.Value{
				'table_vtable_slot':      j.Value(4456)
				'length_vtable_slot':     j.Value(4464)
				'table_address':          j.Value(9344)
				'table_entries':          j.Value(19)
				'source_record_stride':   j.Value(1080)
				'firmware_record_offset': j.Value(1600)
				'firmware_record_stride': j.Value(40)
				'records':                j.Value([
					j.Value(map[string]j.Value{
						'index':           j.Value(17)
						'relative_offset': j.Value(0)
						'total_size':      j.Value(136448)
						'element_size':    j.Value(136448)
						'flags':           j.Value(2)
						'writable':        j.Value(true)
					}),
					j.Value(map[string]j.Value{
						'index':           j.Value(47)
						'relative_offset': j.Value(146688)
						'total_size':      j.Value(512)
						'element_size':    j.Value(512)
						'flags':           j.Value(2)
						'writable':        j.Value(true)
					}),
					j.Value(map[string]j.Value{
						'index':           j.Value(26)
						'relative_offset': j.Value(13647872)
						'total_size':      j.Value(32768)
						'element_size':    j.Value(32768)
						'flags':           j.Value(2)
						'writable':        j.Value(true)
					}),
					j.Value(map[string]j.Value{
						'index':           j.Value(29)
						'relative_offset': j.Value(13697024)
						'total_size':      j.Value(16384)
						'element_size':    j.Value(16384)
						'flags':           j.Value(2)
						'writable':        j.Value(true)
					}),
					j.Value(map[string]j.Value{
						'index':           j.Value(31)
						'relative_offset': j.Value(13893632)
						'total_size':      j.Value(16384)
						'element_size':    j.Value(16384)
						'flags':           j.Value(2)
						'writable':        j.Value(true)
					}),
					j.Value(map[string]j.Value{
						'index':           j.Value(33)
						'relative_offset': j.Value(13910016)
						'total_size':      j.Value(16384)
						'element_size':    j.Value(16384)
						'flags':           j.Value(2)
						'writable':        j.Value(true)
					}),
					j.Value(map[string]j.Value{
						'index':           j.Value(34)
						'relative_offset': j.Value(13942784)
						'total_size':      j.Value(512)
						'element_size':    j.Value(512)
						'flags':           j.Value(2)
						'writable':        j.Value(true)
					}),
					j.Value(map[string]j.Value{
						'index':           j.Value(28)
						'relative_offset': j.Value(13959168)
						'total_size':      j.Value(65536)
						'element_size':    j.Value(65536)
						'flags':           j.Value(2)
						'writable':        j.Value(true)
					}),
					j.Value(map[string]j.Value{
						'index':           j.Value(32)
						'relative_offset': j.Value(14024704)
						'total_size':      j.Value(131072)
						'element_size':    j.Value(131072)
						'flags':           j.Value(2)
						'writable':        j.Value(true)
					}),
					j.Value(map[string]j.Value{
						'index':           j.Value(35)
						'relative_offset': j.Value(14680064)
						'total_size':      j.Value(16384)
						'element_size':    j.Value(16384)
						'flags':           j.Value(2)
						'writable':        j.Value(true)
					}),
					j.Value(map[string]j.Value{
						'index':           j.Value(37)
						'relative_offset': j.Value(14942208)
						'total_size':      j.Value(16384)
						'element_size':    j.Value(16384)
						'flags':           j.Value(2)
						'writable':        j.Value(true)
					}),
					j.Value(map[string]j.Value{
						'index':           j.Value(43)
						'relative_offset': j.Value(15073280)
						'total_size':      j.Value(88)
						'element_size':    j.Value(88)
						'flags':           j.Value(2)
						'writable':        j.Value(true)
					}),
				])
				'alternate_entries':      j.Value([
					j.Value(map[string]j.Value{
						'index':            j.Value(20)
						'primary_offset':   j.Value(u64(4294967295))
						'alternate_offset': j.Value(0)
						'alternate_size':   j.Value(0)
					}),
					j.Value(map[string]j.Value{
						'index':            j.Value(21)
						'primary_offset':   j.Value(u64(4294967295))
						'alternate_offset': j.Value(0)
						'alternate_size':   j.Value(0)
					}),
					j.Value(map[string]j.Value{
						'index':            j.Value(18)
						'primary_offset':   j.Value(u64(4294967295))
						'alternate_offset': j.Value(0)
						'alternate_size':   j.Value(0)
					}),
					j.Value(map[string]j.Value{
						'index':            j.Value(19)
						'primary_offset':   j.Value(u64(4294967295))
						'alternate_offset': j.Value(0)
						'alternate_size':   j.Value(0)
					}),
					j.Value(map[string]j.Value{
						'index':            j.Value(24)
						'primary_offset':   j.Value(u64(4294967295))
						'alternate_offset': j.Value(0)
						'alternate_size':   j.Value(0)
					}),
					j.Value(map[string]j.Value{
						'index':            j.Value(23)
						'primary_offset':   j.Value(u64(4294967295))
						'alternate_offset': j.Value(0)
						'alternate_size':   j.Value(0)
					}),
					j.Value(map[string]j.Value{
						'index':            j.Value(44)
						'primary_offset':   j.Value(u64(4294967295))
						'alternate_offset': j.Value(13778944)
						'alternate_size':   j.Value(256)
					}),
				])
			})
		}
		'recover_g17_pio_uat_mapping' {
			j.Value(map[string]j.Value{
				'gart_range':                    j.Value(10)
				'va_start':                      j.Value(u64(18446739819544444928))
				'va_size':                       j.Value(20971520)
				'va_end':                        j.Value(u64(18446739819565416448))
				'range_flags':                   j.Value(24)
				'uat_page_bytes':                j.Value(16384)
				'single_element_mapping':        j.Value('align_down_physical_and_round_up_end')
				'writable_descriptor_options':   j.Value(3)
				'read_only_descriptor_options':  j.Value(1)
				'writable_gpu_mapping_options':  j.Value(7)
				'read_only_gpu_mapping_options': j.Value(u64(1099511627781))
				'firmware_virtual_address':      j.Value('mapping_gpu_va_plus_physical_page_offset')
			})
		}
		'recover_g17_init_sequence_provider' {
			j.Value(map[string]j.Value{
				'accelerator_vtable': j.Value('__ZTV18AGXAcceleratorG17X')
				'vtable_slot':        j.Value(2696)
				'provider':           j.Value('__ZN14AGXAccelerator28populateInitSequenceFirmwareEh.8148')
				'provider_address':   j.Value(u64(18446741874830529704))
				'entries_appended':   j.Value(0)
			})
		}
		'recover_g17_platform_config' {
			j.Value(map[string]j.Value{
				'bytes':                   j.Value(104)
				'source_object_offset':    j.Value(24)
				'accelerator_host_member': j.Value(108872)
				'provider_vtable':         j.Value('__ZTV35AGXLegacySharedGartTableBackingG17X')
				'provider_vtable_slot':    j.Value(376)
				'provider':                j.Value('__ZN48AGX·PI_300·X·A0·LegacySharedGartTableBacking12initGartInfoEv')
				'page_shift':              j.Value(14)
				'descriptor':              j.Value('010000000000000000c0ffffff030000')
				'initial_bytes':           j.Value('00100c03080e0e2440000040010000000000000000c0ffffff03000000000000f0030000080e0e1900080040010000000000000000c0ffffff030000000000fe0f000000080e0e0e00080040010000000000000000c0ffffff03000000c0ff010000000000000000')
			})
		}
		'recover_g17_brn_workaround_table' {
			j.Value(map[string]j.Value{
				'bytes':                                   j.Value(0)
				'host_cpu_member':                         j.Value(752)
				'host_gpu_member':                         j.Value(824)
				'accelerator_vtable_slot':                 j.Value(3984)
				'size_provider':                           j.Value('__ZNK31AGX·PI_300·X·A0·Accelerator19getSizeOfFWBRNTableEv.8051')
				'firmware_shared_offset':                  j.Value(8)
				'firmware_address_conversion_vtable_slot': j.Value(728)
				'firmware_address_conversion':             j.Value('__ZNK14AGXArmFirmware18convertGPUVAToFWVAEyb')
			})
		}
		else {
			panic(operation)
			j.Value(json2.null)
		}
	}
}

fn runtime_pio_table() [][]u32 {
	return [[u32(0x11), 0x0, 0x21500, 0x0, 0x0, 0x0, 0x0, 0x0],
		[u32(0x2f), 0x23d00, 0x200, 0x0, 0x0, 0x0, 0x0, 0x0],
		[u32(0x1a), 0xd04000, 0x8000, 0x0, 0xdadadada, 0x0, 0x0, 0x0],
		[u32(0x1d), 0xd10000, 0x4000, 0x0, 0xdadadada, 0x0, 0x0, 0x0],
		[u32(0x1f), 0xd40000, 0x4000, 0x0, 0xdadadada, 0x0, 0x0, 0x0],
		[u32(0x21), 0xd44000, 0x4000, 0x0, 0xdadadada, 0x0, 0x0, 0x0],
		[u32(0x22), 0xd4c000, 0x200, 0x0, 0xdadadada, 0x0, 0x0, 0x0],
		[u32(0x1c), 0xd50000, 0x10000, 0x0, 0xdadadada, 0x0, 0x0, 0x0],
		[u32(0x20), 0xd60000, 0x20000, 0x0, 0xdadadada, 0x0, 0x0, 0x0],
		[u32(0x23), 0xe00000, 0x4000, 0x0, 0xdadadada, 0x0, 0x0, 0x0],
		[u32(0x25), 0xe40000, 0x4000, 0x0, 0xdadadada, 0x0, 0x0, 0x0],
		[u32(0x2b), 0xe60000, 0x58, 0x0, 0xdadadada, 0x0, 0x0, 0x0],
		[u32(0x14), 0xffffffff, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0],
		[u32(0x15), 0xffffffff, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0],
		[u32(0x12), 0xffffffff, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0],
		[u32(0x13), 0xffffffff, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0],
		[u32(0x18), 0xffffffff, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0],
		[u32(0x17), 0xffffffff, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0],
		[u32(0x2c), 0xffffffff, 0x0, 0x0, 0xd24000, 0x100, 0x0, 0x0]]
}
