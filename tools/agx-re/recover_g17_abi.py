#!/usr/bin/env python3
"""Recover checked G17 bootstrap anchors from the local Apple binaries.

This intentionally implements only the small AArch64 subset needed to follow
the top-level bootstrap object.  It is not a general disassembler.  Every
reported field must be present in both the M5 Max firmware and the symbolized
host driver's initFirmwareData routine before it is emitted.
"""

from __future__ import annotations

import argparse
import json
import struct
from pathlib import Path

from extract_fileset import LC_SEGMENT_64, LC_SYMTAB, LC_UUID, load_commands, parse_segment


DRIVER_UUID = "680ACC23-AB13-301C-B28A-3A2A257F7977"
FIRMWARE_UUID = "0EDFE976-E37B-3E68-9D64-E3ABF7772D11"
RTBUDDY_UUID = "93F44AA7-63B3-3D75-8A9E-E4095ABBDD1D"
INTERFACE_MAGIC = 0x0C8BC322072804C0
INIT_FIRMWARE_DATA = "__ZN14AGXArmFirmware16initFirmwareDataEv"
INIT_BASE_FIRMWARE_DATA = "__ZN11AGXFirmware16initFirmwareDataEv"
INIT_FIRMWARE_SHARED_DATA = "__ZN14AGXArmFirmware22initFirmwareSharedDataEv"
ALLOC_ARM_FIRMWARE_DATA = "__ZN14AGXArmFirmware17allocFirmwareDataEv"
PREPARE_FIRMWARE_BOOT = "__ZN14AGXArmFirmware22prepareFirmwareForBootEv"
NOTIFY_FIRMWARE_STARTED = (
    "__ZN14AGXArmFirmware21notifyFirmwareStartedE16AGFIFirmwareRole"
)
RECEIVED_MESSAGE_FROM_AKF = (
    "__ZN14AGXArmFirmware22receivedMessageFromAKFEy16AGFIFirmwareRole"
)
ACCELERATOR_HANDLE_INTERRUPT = (
    "__ZN14AGXAccelerator15handleInterruptEP22IOInterruptEventSourcei"
)
FIRMWARE_HANDLE_EVENT = "__ZN11AGXFirmware11handleEventE17AGXInterruptIndex"
FIRMWARE_DRAIN_EVENT_RING = "__ZN11AGXFirmware22drainFirmwareEventRingEv"
FIRMWARE_DRAIN_EVENT_RING_ROLE = (
    "__ZN11AGXFirmware22drainFirmwareEventRingE16AGFIFirmwareRole"
)
G17_HANDLE_FIRMWARE_CONTROLLER_EVENT = (
    "__ZN14AGXArmFirmware29handleFirmwareControllerEventEPK26AGFIFirmwareEventRingEntry"
)
FIRMWARE_INIT = "__ZN11AGXFirmware4initEP14AGXAccelerator"
FIRMWARE_RING_FETCH = (
    "__ZN24AGXFirmwareRingValidator14fetchNextEntryEP26AGFIFirmwareEventRingEntry"
)
IOGPU_EVENT_SIGNAL_STAMP = "__ZN17IOGPUEventMachine11signalStampEij"
IOGPU_EVENT_GET_NUM_STAMPS = "__ZN17IOGPUEventMachine12getNumStampsEv"
IOGPU_EVENT_TEST_ALL_STAMPS = "__ZNK17IOGPUEventMachine13testAllStampsEv"
IOGPU_FENCE_INTERRUPT_OCCURRED = "__ZN17IOGPUFenceMachine24iofenceInterruptOccurredEv"
IOGPU_FENCE_NOTIFY_CLPC = "__ZN17IOGPUFenceMachine23notifyCLPCIOPerfControlEy"
IOGPU_SCHEDULER_SIGNAL_HARDWARE_ERROR = (
    "__ZN14IOGPUScheduler19signalHardwareErrorE15eRestartRequesti"
)
IOGPU_SIGNAL_STAMPS_UPDATED = "__ZN5IOGPU19signalStampsUpdatedEv"
G17_CLEAR_FIRMWARE_INTERRUPTS = (
    "__ZN14AGXArmFirmware34clearOutstandingFirmwareInterruptsEv.4213"
)
IOFILTER_INTERRUPT_EVENT_SOURCE_VTABLE = "__ZTV28IOFilterInterruptEventSource"
IOFILTER_INTERRUPT_EVENT_SOURCE_FACTORY = (
    "__ZN28IOFilterInterruptEventSource26filterInterruptEventSourceEP8OSObject"
    "PFvS1_P22IOInterruptEventSourceiEPFbS1_PS_EP9IOServicei"
)
IOFILTER_SIGNAL_INTERRUPT = "__ZN28IOFilterInterruptEventSource15signalInterruptEv"
IOINTERRUPT_GET_INDEX = "__ZNK22IOInterruptEventSource11getIntIndexEv"
BOOT_FIRMWARE = "__ZN14AGXArmFirmware12bootFirmwareEv"
RTBUDDY_READ_MESSAGE = "__ZN22AGXFirmwareKextRTBuddy18readMessageFromAKFEPy"
RTBUDDY_SEND_MESSAGE_GATED = (
    "__ZN22AGXFirmwareKextRTBuddy26sendMessageToFirmwareGatedEPy"
)
RTBUDDY_MATCHED_ENDPOINT_GATED = (
    "__ZN22AGXFirmwareKextRTBuddy23matchedGFXEndpointGatedEPv"
)
RTBUDDY_ENABLE_ENDPOINTS = "__ZN22AGXFirmwareKextRTBuddy15enableEndpointsEv"
RTBUDDY_RECEIVED_MESSAGE = "__ZN22AGXFirmwareKextRTBuddy22receivedMessageFromAKFEy"
PREPARE_FIRMWARE_DATA = "__ZN14AGXArmFirmware19prepareFirmwareDataEv"
COMPLETE_FIRMWARE_DATA = "__ZN14AGXArmFirmware20completeFirmwareDataEv"
ARM_FIRMWARE_PAGE_SHIFT = "__ZNK17AGXArmFirmwareASC14getFWPageShiftEv"
SET_INIT_REGISTER_64_PA = "__ZN14AGXArmFirmware14setInitReg64PAEtyjh.4231"
SET_INIT_REGISTER_64 = "__ZN14AGXArmFirmware12setInitReg64Etyh.4232"
SET_INIT_REGISTER_32 = "__ZN14AGXArmFirmware12setInitReg32Etjh.4233"
G17_ACCELERATOR_VTABLE = "__ZTV18AGXAcceleratorG17X"
G17_POPULATE_INIT_SEQUENCE = "__ZN14AGXAccelerator28populateInitSequenceFirmwareEh.8148"
G17_FW_BRN_SIZE = "__ZNK31AGX·PI_300·X·A0·Accelerator19getSizeOfFWBRNTableEv.8051"
G17_FIRMWARE_VTABLE = "__ZTV17AGXArmFirmwareASC"
G17_ARM_FIRMWARE_ASC_META_ALLOC = "__ZNK17AGXArmFirmwareASC9MetaClass5allocEv"
OS_OBJECT_TYPED_OPERATOR_NEW = "_OSObject_typed_operator_new"
KALLOC_TYPE_IMPL = "_kalloc_type_impl"
CONVERT_GPU_VA_TO_FW_VA = "__ZNK14AGXArmFirmware18convertGPUVAToFWVAEyb"
G17_LEGACY_SHARED_GART_VTABLE = "__ZTV35AGXLegacySharedGartTableBackingG17X"
G17_LEGACY_GART_INIT_INFO = (
    "__ZN48AGX·PI_300·X·A0·LegacySharedGartTableBacking12initGartInfoEv"
)
INIT_BASE_POWER_DATA = "__ZN11AGXFirmware27initPowerAndPerformanceDataEv"
INIT_POWER_DATA = "__ZN14AGXArmFirmware27initPowerAndPerformanceDataEv"
SETUP_CONFIG = "__ZN14AGXArmFirmware11setupConfigEv"
INIT_BASE_SETUP_CONFIG = "__ZN11AGXFirmware11setupConfigEv"
POPULATE_DPE_PPT_CONFIG = (
    "__ZN14AGXAccelerator24populateDPEPPTConfigDataEP19AGFDPEPPTConfigData"
)
BASE_CONFIGURE_DEVICE = "__ZN14AGXAccelerator15configureDeviceEP9IOService"
RETRIEVE_CHIP_INFO = "__ZN14AGXAccelerator16retrieveChipInfoEP12AGXSChipInfo"
G17_GET_SAMPLE_PERIOD = "__ZN14AGXAccelerator15getSamplePeriodEv.8055"
G17_DEFAULT_MCACHE_WRITES = (
    "__ZN32AGX·PI_300·X·A0·AcceleratorX25halGetDefaultMcacheWritesEv.8045"
)
G17_GET_ENABLED_NUM_USCS = "__ZNK14AGXAccelerator17getEnabledNumUSCsEv"
PI300_READ_CHIP_INFO = (
    "__ZNK31AGX·PI_300·X·A0·Accelerator12readChipInfoEP16AGXGPUCoreConfig"
)
G17_READ_CHIP_INFO = (
    "__ZNK32AGX·PI_300·X·A0·AcceleratorX12readChipInfoEP16AGXGPUCoreConfig"
)
FAMILY_GET_PROBE_SCORE = "__ZN20AGXFamilyAccelerator13getProbeScoreEv"
G17_PARSE_PERF_STATE_MAP_REGS = (
    "__ZN20AGXFamilyAccelerator21parsePerfStateMapRegsEv.8015"
)
DEVICE_USER_GET_CONFIG = (
    "__ZN19AGXDeviceUserClient15getDeviceConfigEP16AGXGPUCoreConfig"
)
ACCELERATOR_GET_GPTBAT_BASE = "__ZN14AGXAccelerator13getGPTBATBaseEv"
PI300_NEW_SECURE_MONITOR = (
    "__ZN31AGX·PI_300·X·A0·Accelerator19halNewSecureMonitorEv"
)
PI300_SECURE_MONITOR_VTABLE = "__ZTV33AGX·PI_300·X·A0·SecureMonitor"
SECURE_MONITOR_INIT = "__ZN16AGXSecureMonitor4initEP14AGXAccelerator"
SECURE_MONITOR_GET_GPTBAT_DESC = "__ZN16AGXSecureMonitor13getGPTBATDescEv"
PI300_READ_GPTBAT_BASE = (
    "__ZNK33AGX·PI_300·X·A0·SecureMonitor21readGPTBATBaseAddressEv"
)
PI300_SETUP_MMU_CONFIG = (
    "__ZN33AGX·PI_300·X·A0·SecureMonitor14setupMMUConfigEv"
)
PI300_ACCELERATOR_START = "__ZN31AGX·PI_300·X·A0·Accelerator5startEP9IOService"
G17_ACCELERATOR_START = (
    "__ZN32AGX·PI_300·X·A0·AcceleratorX5startEP9IOService"
)
ACCELERATOR_START = "__ZN14AGXAccelerator5startEP9IOService"
PI300_CONFIGURE_DEVICE = (
    "__ZN31AGX·PI_300·X·A0·Accelerator15configureDeviceEP9IOService"
)
G17_CONFIGURE_DEVICE = (
    "__ZN32AGX·PI_300·X·A0·AcceleratorX15configureDeviceEP9IOService"
)
G17_RETRIEVE_CHIP_INFO_VTABLE_SLOT = 0xD60
G17_GET_SAMPLE_PERIOD_VTABLE_SLOT = 0xF70
G17_DEFAULT_MCACHE_WRITES_VTABLE_SLOT = 0xFF0
G17_GET_ENABLED_NUM_USCS_VTABLE_SLOT = 0xAA0
G17_READ_CHIP_INFO_VTABLE_SLOT = 0x1210
G17_PERF_STATE_MAP_VTABLE_SLOT = 0x1218
G17_DUPM_MIN_COUNT = (
    "__ZNK31AGX·PI_300·X·A0·Accelerator33halGetAgxCrUmaDefaultDupmMinCountEv.8028"
)
G17_DUPM_MAX_COUNT = (
    "__ZNK31AGX·PI_300·X·A0·Accelerator33halGetAgxCrUmaDefaultDupmMaxCountEv.8027"
)
G17_CONSTANT_VIRTUAL_RETURNS = {
    0x10F8: ("dup_min_count", G17_DUPM_MIN_COUNT, 1),
    0x1100: ("dup_max_count", G17_DUPM_MAX_COUNT, 2),
}
IOGPU_MEMORY_MAP_VTABLE = "__ZTV14IOGPUMemoryMap"
AGX_LEGACY_MEMORY_MAP_VTABLE = "__ZTV18AGXLegacyMemoryMap"
AGX_SECURE_MEMORY_MAP_VTABLE = "__ZTV18AGXSecureMemoryMap"
IOGPU_MEMORY_MAP_GPU_VA = "__ZN14IOGPUMemoryMap20getGPUVirtualAddressEv"
IOGPU_MEMORY_MAP_GPU_VA_SLOT = 0x158
IOGPU_MEMORY_MAP_GPU_VA_MEMBER = 0x28
G17_POPULATE_POWER_ESTIMATION_VTABLE_SLOT = 0xCC0
G17_POPULATE_CHIP_LEAKAGE_VTABLE_SLOT = 0xCB0
G17_POPULATE_SRAM_POWER_SCALE_VTABLE_SLOT = 0xCF0
G17_POPULATE_STATIC_POWER_VTABLE_SLOT = 0xCE0
G17_POPULATE_CHIP_LEAKAGE_VTABLE_SLOT = 0xCB0
G17_POPULATE_MAX_PERF_POWER_VTABLE_SLOT = 0xFD0
G17_POPULATE_MAX_PERF_POWER_CS_VTABLE_SLOT = 0xFD8
G17_CALCULATE_VDD_GPU_LEAKAGE_VTABLE_SLOT = 0xA28
G17_CALCULATE_AFR_LEAKAGE_VTABLE_SLOT = 0xA30
G17_APPLY_LEAKAGE_EQUATION_VTABLE_SLOT = 0xA38
G17_NEW_SECURE_MONITOR_VTABLE_SLOT = 0xBE0
G17_GET_GPTBAT_BASE_VTABLE_SLOT = 0x11D0
SECURE_MONITOR_INIT_VTABLE_SLOT = 0x150
SECURE_MONITOR_GET_GPTBAT_DESC_VTABLE_SLOT = 0x158
SECURE_MONITOR_READ_GPTBAT_BASE_VTABLE_SLOT = 0x138
BASE_CONFIGURE_POWER = (
    "__ZN14AGXAccelerator38configurePowerAndPerformanceControllerEv"
)
G17_CONFIGURE_POWER = (
    "__ZN32AGX·PI_300·X·A0·AcceleratorX38configurePowerAndPerformanceControllerEv"
)
G17_PIO_TABLE_LENGTH = (
    "__ZNK32AGX·PI_300·X·A0·AcceleratorX31getPIORelativeOffsetTableLengthEv"
)
G17_PIO_TABLE = (
    "__ZNK32AGX·PI_300·X·A0·AcceleratorX25getPIORelativeOffsetTableEv"
)
CREATE_FW_PIO_MAPPING = (
    "__ZN11AGXFirmware18createFWPIOMappingEPKyjPjbj10eGartRange"
)
CREATE_FW_GPU_MAPPING = (
    "__ZN11AGXFirmware18createFWGPUMappingEP18IOMemoryDescriptorb10eGartRange"
)
GART_RANGES = "__ZL11gart_ranges.12908"
G17_DEFAULT_USC_MAX_TGMEM = (
    "__ZNK31AGX·PI_300·X·A0·Accelerator24halGetDefaultUscMaxTgmemEv"
)
POPULATE_AUX_PERF_STATE_INFO = (
    "__ZN14AGXAccelerator21populatePerfStateInfoILj16ELj2EEEbP9IOService"
    "14AGXClockDomainR13PerfStateInfoIXT_EXT0_EE"
)
G17_GET_PERF_STATE_CAP = (
    "__ZN32AGX·PI_300·X·A0·AcceleratorX15getPerfStateCapE14AGXClockDomainRb"
)
G17_SETUP_CSC_ALLOCATION = (
    "__ZN31AGX·PI_300·X·A0·Accelerator18setupCSCAllocationEv.8063"
)
G17_GENERATE_CSC_COEFFICIENTS = (
    "__ZN31AGX·PI_300·X·A0·Accelerator23generateCSCCoefficientsEv"
)
POPULATE_AFR_FAST_DIE_CONFIG = (
    "__ZN14AGXAccelerator34populateAFRFastDieDeviceConfigDataEP32AGXFastDieControllerDeviceConfig"
)
G17_POPULATE_POWER_ESTIMATION_CONFIG = (
    "__ZN32AGX·PI_300·X·A0·AcceleratorX33populatePowerEstimationConfigDataEj"
)
G17_POPULATE_SRAM_POWER_SCALE_DATA = (
    "__ZN32AGX·PI_300·X·A0·AcceleratorX26populateSRAMPowerScaleDataEv"
)
G17_POPULATE_CHIP_LEAKAGE_DATA = (
    "__ZN32AGX·PI_300·X·A0·AcceleratorX23populateChipLeakageDataEj"
)
G17_POPULATE_STATIC_POWER_DATA = (
    "__ZN14AGXAccelerator23populateStaticPowerDataEv.8120"
)

G17_ACCELERATOR_X = "__ZN32AGX·PI_300·X·A0·AcceleratorX"
G17_POPULATE_LINEAR_POWER_TRANSFER = (
    "__ZN14AGXAccelerator32populateLinearPowerTransferTableEPjj"
)
G17_POPULATE_MAX_PERF_POWER = (
    G17_ACCELERATOR_X + "31populateMaximumPerformancePowerEv"
)
G17_POPULATE_MAX_PERF_POWER_CS = (
    G17_ACCELERATOR_X + "33populateMaximumPerformancePowerCSEv"
)
G17_CALCULATE_VDD_GPU_LEAKAGE = G17_ACCELERATOR_X + "22calculateVddGpuLeakageEddd"
G17_CALCULATE_AFR_LEAKAGE = G17_ACCELERATOR_X + "19calculateAFRLeakageEddd"
G17_APPLY_LEAKAGE_EQUATION = (
    G17_ACCELERATOR_X + "20applyLeakageEquationERK17LeakageParameters"
)
G17_POPULATE_CHIP_LEAKAGE = G17_ACCELERATOR_X + "23populateChipLeakageDataEj"
G17_TPU_CSC_COEFFICIENTS = (
    "__ZZN31AGX·PI_300·X·A0·Accelerator23generateCSCCoefficientsEvE16tpu_coefficients"
)
G17_PBE_CSC_COEFFICIENTS = (
    "__ZZN31AGX·PI_300·X·A0·Accelerator23generateCSCCoefficientsEvE16pbe_coefficients"
)
G17_GET_BORDER_COLOR_TABLE_GPU_ADDRESS = (
    "__ZN14AGXAccelerator29getBorderColorTableGPUAddressEv.8074"
)
SET_GVDM_MODE = "__ZN14AGXAccelerator11setGVDMModeEjjj"
GET_UMA_MAX_ACTIVE_GTP_KICKS = "__ZN14AGXAccelerator23getUMAMaxActiveGTPKicksEv"
PERF_COUNTER_SOURCE_STOP = "__ZN17AGXPerfCtrSampler17sourceSamplerStopEv"
PERF_COUNTER_LOCK_ACCESS = "__ZN17AGXPerfCtrSampler10lockAccessEbP9AGXShared"
ALLOC_FIRMWARE_DATA = "__ZN11AGXFirmware17allocFirmwareDataEv"
KTRACE_FIRMWARE_CALLBACK = "__ZN11AGXFirmware16ktraceFwCallbackE16kd_callback_typePv16AGFIFirmwareRole"
WAIT_FIRMWARE_POWER_OFF = "__ZN14AGXArmFirmware23waitForFirmwarePowerOffEv"
WAIT_NEXT_ASC_POWER_GENERATION = "__ZN14AGXArmFirmware29waitForNextASCPowerGenerationEv"
SNAPSHOT_ASC_POWER_GENERATION = "__ZN14AGXArmFirmware26snapshotASCPowerGenerationEv"
GET_SYSTEM_SLEEP_NOTIFICATION = "__ZN14AGXArmFirmware35isSystemSleepNotificationInProgressEv.4221"
SET_SYSTEM_SLEEP_NOTIFICATION = "__ZN14AGXArmFirmware36setSystemSleepNotificationInProgressEb.4222"
G17_ADD_REGISTER_OVERRIDE = "__ZN14AGXArmFirmware19addRegisterOverrideEjyy"
G17_RUNTIME_ACCESSORS = {
    "dm_pause_mode": (
        "__ZN14AGXArmFirmware14setDMPauseModeEj",
        ((0x00C, 4),),
    ),
    "dm_pause_timer": (
        "__ZN14AGXArmFirmware15setDMPauseTimerEj",
        ((0x014, 4),),
    ),
    "frg_task_timeout": (
        "__ZN14AGXArmFirmware17setFRGTaskTimeoutEj",
        ((0x028, 4),),
    ),
    "smart_idle_enabled": (
        "__ZN14AGXArmFirmware21setSmartIdleOffEnableEb",
        ((0x034, 4),),
    ),
    "cpms_window_size": (
        "__ZN14AGXArmFirmware17setCPMSWindowSizeEj",
        ((0x040, 4),),
    ),
    "cpms_tfca_size": (
        "__ZN14AGXArmFirmware15setCPMSTFCASizeEj",
        ((0x044, 4),),
    ),
    "command_submission_enabled": (
        "__ZN14AGXArmFirmware27setCommandSubmissionEnabledEb.4234",
        ((0x078, 4),),
    ),
    "performance_controller_target": (
        "__ZN14AGXArmFirmware30setPerformanceControllerTargetEj",
        ((0x0A4, 4),),
    ),
    "performance_controller_dead_zone": (
        "__ZN14AGXArmFirmware32setPerformanceControllerDeadZoneEj",
        ((0x0A8, 4),),
    ),
    "performance_controller_transfer_output": (
        "__ZN14AGXArmFirmware38setPerformanceControllerTransferOutputEj",
        ((0x0AC, 4),),
    ),
    "performance_controller_dual_filter": (
        "__ZN14AGXArmFirmware34setPerformanceControllerDualFilterEb",
        ((0x0D5, 1), (0x0DC, 1)),
    ),
    "clpc_deadline_control_effort": (
        "__ZN14AGXArmFirmware28setCLPCDeadlineControlEffortEj",
        ((0x0E4, 4),),
    ),
    "smart_idle_standby_timer_us": (
        "__ZN14AGXArmFirmware29setSmartIdleOffStandbyTimerUSEj",
        ((0x7C4, 4),),
    ),
    "smart_idle_probability_initial": (
        "__ZN14AGXArmFirmware26setSmartIdleOffProbInitValEf",
        ((0x7C8, 4),),
    ),
    "smart_idle_fn_hit": (
        "__ZN14AGXArmFirmware20setSmartIdleOffFnHitEf",
        ((0x7CC, 4),),
    ),
    "smart_idle_fi_hit": (
        "__ZN14AGXArmFirmware20setSmartIdleOffFiHitEf",
        ((0x7D0, 4),),
    ),
    "smart_idle_fn_miss": (
        "__ZN14AGXArmFirmware21setSmartIdleOffFnMissEf",
        ((0x7D4, 4),),
    ),
    "smart_idle_fi_miss": (
        "__ZN14AGXArmFirmware21setSmartIdleOffFiMissEf",
        ((0x7D8, 4),),
    ),
    "smart_idle_neighbor_hit": (
        "__ZN14AGXArmFirmware21setSmartIdleOffNeiHitEf",
        ((0x7DC, 4),),
    ),
    "smart_idle_gpu_min_confidence": (
        "__ZN14AGXArmFirmware31setSmartIdleOffGPUMinConfidenceEf",
        ((0x7E0, 4),),
    ),
    "smart_idle_gpu_high_confidence": (
        "__ZN14AGXArmFirmware32setSmartIdleOffGPUHighConfidenceEf",
        ((0x7E4, 4),),
    ),
    "smart_idle_reset_iterations": (
        "__ZN14AGXArmFirmware30setSmartIdleOffResetIterationsEj",
        ((0x7E8, 4),),
    ),
    "ut_engagement": (
        "__ZN14AGXArmFirmware18enableUTEngagementEb",
        ((0x7EC, 4), (0x7F0, 4)),
    ),
    "pmu_engagement": (
        "__ZN14AGXArmFirmware19enablePMUEngagementEb",
        ((0x7F4, 4),),
    ),
    "register_override_count": (
        "__ZN14AGXArmFirmware22resetRegisterOverridesEv",
        ((0x984, 4),),
    ),
    "progress_check_interval_3d": (
        "__ZN14AGXArmFirmware26setProgressCheckInterval3DEj",
        ((0x99C, 4),),
    ),
    "progress_check_interval_ta": (
        "__ZN14AGXArmFirmware26setProgressCheckIntervalTAEj",
        ((0x9A0, 4),),
    ),
    "progress_check_interval_cl": (
        "__ZN14AGXArmFirmware26setProgressCheckIntervalCLEj",
        ((0x9A4, 4),),
    ),
    "progress_check_threshold": (
        "__ZN14AGXArmFirmware25setProgressCheckThresholdEj",
        ((0x9A8, 4),),
    ),
    "progress_check_dm_config": (
        "__ZN14AGXArmFirmware24setProgressCheckDmConfigE16AGXSLockupConfig19_AGFIDataMasterType",
        ((0x9AC, 4),),
    ),
    "gpu_idle_off_delay": (
        "__ZN14AGXArmFirmware18setGPUIdleOffDelayEjj",
        ((0x9BC, 4),),
    ),
    "fender_idle_off_delay": (
        "__ZN14AGXArmFirmware21setFenderIdleOffDelayEjj",
        ((0x9C0, 4),),
    ),
    "firmware_early_wake_timeout": (
        "__ZN14AGXArmFirmware21setFWEarlyWakeTimeoutEjj",
        ((0x9C4, 4),),
    ),
    "gvdm_timer_interval": (
        "__ZN14AGXArmFirmware20setGVDMTimerIntervalEj",
        ((0x9C8, 4),),
    ),
    "cl_context_switch_timeout": (
        "__ZN14AGXArmFirmware25setCLContextSwitchTimeoutEj",
        ((0x9CC, 4),),
    ),
    "cl_kill_timeout": (
        "__ZN14AGXArmFirmware16setCLKillTimeoutEj",
        ((0x9D0, 4),),
    ),
    "phase_one_cdm_context_switch_timeout": (
        "__ZN14AGXArmFirmware34setPhaseOneCDMContextSwitchTimeoutEj",
        ((0x9D4, 4),),
    ),
    "frg_context_switch_timeout": (
        "__ZN14AGXArmFirmware26setFRGContextSwitchTimeoutEj",
        ((0x9D8, 4),),
    ),
    "frg_kill_timeout": (
        "__ZN14AGXArmFirmware17setFRGKillTimeoutEj",
        ((0x9DC, 4),),
    ),
    "fw_util_default_fab_pstate": (
        "__ZN14AGXArmFirmware25setFwUtilDefaultFabPStateEy",
        ((0x9E8, 1), (0x9E9, 1)),
    ),
    "fw_util_timer_period": (
        "__ZN14AGXArmFirmware20setFwUtilTimerPeriodEy",
        ((0x9EA, 1),),
    ),
    "fw_util_debounce_periods": (
        "__ZN14AGXArmFirmware24setFwUtilDebouncePeriodsEy",
        ((0x9EB, 1), (0x9EC, 1)),
    ),
    "fw_util_pstate_threshold": (
        "__ZN14AGXArmFirmware24setFwUtilPStateThresholdEy",
        ((0x9ED, 1), (0x9EE, 1)),
    ),
    "fw_util_pstate_step_size": (
        "__ZN14AGXArmFirmware23setFwUtilPStateStepSizeEy",
        ((0x9EF, 1), (0x9F0, 1)),
    ),
    "gpu_keepalive_override": (
        "__ZN14AGXArmFirmware23setGPUKeepAliveOverrideE13AGXSKeepAlive",
        ((0x1C30, 4),),
    ),
    "gfxc_keepalive_override": (
        "__ZN14AGXArmFirmware24setGFXCKeepAliveOverrideE13AGXSKeepAlive",
        ((0x1C34, 4),),
    ),
    "gpu_keepalive_perf_mode_threshold": (
        "__ZN14AGXArmFirmware32setGPUKeepAlivePerfModeThresholdEj",
        ((0x1C38, 4),),
    ),
    "gpu_keepalive_off_mode_threshold": (
        "__ZN14AGXArmFirmware31setGPUKeepAliveOffModeThresholdEj",
        ((0x1C3C, 4),),
    ),
}
ROOT_FIELDS = (0x18, 0x20, 0xA8, 0xB0, 0xB8, 0xC0)
DATA_MASTER_RING = "__ZN18AGXAcceleratorRingI30AGFIAcceleratorDataMasterEntryE"
DEVICE_CONTROL_RING = "__ZN18AGXAcceleratorRingI33AGFIAcceleratorDeviceControlEntryE"
RING_ACCESSORS = {
    "read_index": "12getReadIndexEv",
    "cfi_index": "11getCFIIndexEv",
    "write_index": "13getWriteIndexEv",
}
NEXT_DATA_MASTER_ENTRY = DATA_MASTER_RING + "9nextEntryEP13IOCommandGate"
ENCODE_ACCELERATOR_COMMAND = (
    "__ZN14AGXArmFirmware28encodeAcceleratorRingCommandE"
    "P30AGFIAcceleratorDataMasterEntry26AGFIAcceleratorCommandTypeP10AGXChannelj"
)
SUBMIT_DATA_MASTER_CHANNELS = {
    "TA": (
        "__ZN11AGXFirmware15submitTAChannelE"
        "P10AGXChannelRK22_AGXChannelSubmitInfo_jjb",
        0,
    ),
    "3D": (
        "__ZN11AGXFirmware15submit3DChannelE"
        "P10AGXChannelRK22_AGXChannelSubmitInfo_jjbb",
        1,
    ),
    "CL": (
        "__ZN11AGXFirmware15submitCLChannelE"
        "P10AGXChannelRK22_AGXChannelSubmitInfo_jjb",
        2,
    ),
}
ARM_SUBMIT_DATA_MASTER_CHANNELS = {
    "TA": (
        "__ZN14AGXArmFirmware15submitTAChannelE"
        "P10AGXChannelRK22_AGXChannelSubmitInfo_jjb",
        SUBMIT_DATA_MASTER_CHANNELS["TA"][0],
        0,
    ),
    "3D": (
        "__ZN14AGXArmFirmware15submit3DChannelE"
        "P10AGXChannelRK22_AGXChannelSubmitInfo_jjbb",
        SUBMIT_DATA_MASTER_CHANNELS["3D"][0],
        1,
    ),
    "CL": (
        "__ZN14AGXArmFirmware15submitCLChannelE"
        "P10AGXChannelRK22_AGXChannelSubmitInfo_jjb",
        SUBMIT_DATA_MASTER_CHANNELS["CL"][0],
        2,
    ),
}
SUBMIT_DEVICE_CONTROL = (
    "__ZN11AGXFirmware19submitDeviceControlE"
    "P33AGFIAcceleratorDeviceControlEntryjPj"
)
RESET_CHANNEL_STATE = "__ZN10AGXChannel17resetChannelStateEv"
GET_CHANNEL_PRIORITY = "__ZN10AGXChannel11getPriorityEv"
ARM_SET_CHANNEL_PRIORITY = (
    "__ZN14AGXArmFirmware18setChannelPriorityE"
    "P17_AGFIChannelState23eAGXContextPriorityTypej26eIOGPUCommandQueueQosLevel"
)
SUBMIT_COMMAND_TO_FIRMWARE_BLOCK = (
    "____ZN12AGXWorkQueue23submitCommandToFirmwareE"
    "P10AGXChannelP20AGXCommandDescriptorb_block_invoke"
)
MARK_CHANNEL_SUBMITTED_PREFIX = (
    "__ZN10AGXChannel32markCommandsSubmittedToAccelRingEv"
)
UNMARK_CHANNEL_SUBMITTED_PREFIX = (
    "__ZN10AGXChannel34unmarkCommandsSubmittedToAccelRingEv"
)
SET_CHANNEL_PRIORITY = (
    "__ZN10AGXChannel11setPriorityE"
    "23eAGXContextPriorityTypej26eIOGPUCommandQueueQosLevel"
)
WRITE_CHANNEL_COMMAND_POINTER = (
    "__ZN10AGXChannel26writeChannelCommandPointerEyP22AGFIChannelCommandTypey"
)
SUBMIT_NOP_UNPREPARED = (
    "__ZN10AGXChannel19submitNopUnpreparedEP22IOGPUCommandDescriptor"
    "22AGFIChannelCommandType19_AGFIDataMasterType"
)
CHANNEL_INIT = (
    "__ZN10AGXChannel4initEPK15AGXCommandQueueP12AGXWorkQueueiiy19_AGFIDataMasterType"
)
G17_CHANNEL_INITIALIZERS = {
    "TA": "__ZN12AGXTAChannel4initEPK15AGXCommandQueueP12AGXWorkQueueiiy",
    "3D": "__ZN12AGX3DChannel4initEPK15AGXCommandQueueP12AGXWorkQueueiiy",
    "CL": "__ZN12AGXCLChannel4initEPK15AGXCommandQueueP12AGXWorkQueueiiy",
}
SET_KICK_CHANNEL_QOS = "__ZN14AGXArmFirmware17setKickChannelQosEjj"
ARM_ALLOC_FIRMWARE_DATA = "__ZN14AGXArmFirmware17allocFirmwareDataEv"
ALLOCATE_SCHEDULER_STATE = "__ZN15AGXCommandQueue22allocateSchedulerStateEv"
SCHEDULER_STATE_STACK = (
    "__ZN24AGXFirmwareResourceStackI19_AGFISchedulerState15AGXCommandQueue"
    "Lj64ELj256EE"
)
SCHEDULER_STATE_STACK_INIT = (
    SCHEDULER_STATE_STACK
    + "4initEP14AGXAcceleratoryPKcy17AGXCachingOptionsP9IOGPUTask19AGXFWPoolShrinkMode"
)
SCHEDULER_STATE_STACK_VTABLE = "__ZTV" + SCHEDULER_STATE_STACK.removeprefix("__ZN")
SCHEDULER_STATE_STACK_INIT_SLOT = 0x20
IOGPU_COMMAND_QUEUE_INIT = (
    "__ZN17IOGPUCommandQueue4initEP5IOGPUP11IOGPUDeviceP30IOGPUDeviceNewCommandQueueArgs"
)
IOGPU_COMMAND_DESCRIPTOR_INIT = (
    "__ZN22IOGPUCommandDescriptor4initEP5IOGPUP17IOGPUCommandQueueP9IOGPUTask"
)
AGX_COMMAND_QUEUE_INIT = (
    "__ZN15AGXCommandQueue4initEP5IOGPUP11IOGPUDeviceP30IOGPUDeviceNewCommandQueueArgs"
)
IOGPU_DEVICE_INIT = "__ZN11IOGPUDevice4initEP5IOGPUP4task"
IOGPU_CHANNEL_INIT = "__ZN12IOGPUChannel4initEP5IOGPUi"
IOGPU_WORK_QUEUE_INIT = "__ZN14IOGPUWorkQueue4initEP5IOGPUPK17IOGPUCommandQueuei"
AGX_WORK_QUEUE_INIT = "__ZN12AGXWorkQueue4initEP5IOGPUPK17IOGPUCommandQueueiiy"
ALLOCATE_3D_WORK_QUEUE = "__ZN15AGXCommandQueue24allocate3DWorkQueueInnerEbj"
ALLOCATE_CL_WORK_QUEUE = "__ZN15AGXCommandQueue24allocateCLWorkQueueInnerEj"
TIMESTAMP_QUEUE_INIT = "__ZN17AGXTimeStampQueue4initEP14AGXAccelerator"
RESET_TIMESTAMP_QUEUE = "__ZN17AGXTimeStampQueue24resetTimeStampQueueStateEv"
AGX_SHARED_INIT = "__ZN9AGXShared4initEP5IOGPUP4tasky"
AGX_SHARED_SET_APP_GPU_ROLE = "__ZN9AGXShared16set_app_gpu_roleEi13eIOGPUAppRole"
CONFIGURE_POOL_ELEMENT_SIZES = "__ZN11AGXFirmware25configurePoolElementSizesEv"
BASE_ALLOC_FIRMWARE_DATA = "__ZN11AGXFirmware17allocFirmwareDataEv"
COMMAND_POOL_CREATE_BACKING = (
    "__ZN9PoolClassI20AGFIChannelCommand3DE13createBackingE"
    "jP14AGXAcceleratoryb"
)
REQUEST_CHANNEL_COMMAND_BARRIER = "__ZN11AGXFirmware28requestChannelCommandBarrierEPy"
TA_COMMAND_POOL = 0x1648
GENERATE_REGISTER_LIST_3D = (
    "__ZN33AGX·PI_300·X·A0·3DChannelSKSM25generateRegisterListFor3D"
    "EP20AGFIChannelCommand3DP22AGX3DCommandDescriptor"
)
G17_COMMAND_3D_BYTES = 0x2240
COMPLETE_COMMAND_3D = "__ZN22AGX3DCommandDescriptor8completeEv"
G17_SELECTOR_TEMPLATE_MASK = 0xFFFC0006
SELECTOR_ARGUMENT_WINDOW = 10
VALUE_ARGUMENT_WINDOW = 20
G17_VALUE_EXPRESSION_MAX_DEPTH = 20
G17_CL_RANDOM_CALL_OFFSET = 0x3D8
G17_CL_RANDOM_CALL_WORD = 0x94B3CB9D
KERNEL_RANDOM = "_random"
RCE_ENCODE_ENTRY = "__ZNK36AGX·PI_300·X·A0·RCEBufferEncoder11encodeEntryEPvjhy"
ARM_INIT_FIRMWARE_DATA = "__ZN14AGXArmFirmware16initFirmwareDataEv"
G17_ACCELERATOR_ALLOC = "__ZNK18AGXAcceleratorG17X9MetaClass5allocEv"
IDLE_POWER_OFF_TIMER = "__ZN14AGXAccelerator17idlePowerOffTimerEv"
G17_FEATURE_MASK = 0x0001000018020000
PARSE_HARDWARE_KERNEL_COMMAND = (
    "__ZN24AGXHardwareKernelCommand16parseAndValidateER21AGXSharedStreamParserS1_"
)
PARSE_RENDER_HARDWARE_KERNEL_COMMAND = (
    "__ZN30AGXRenderHardwareKernelCommand16parseAndValidateER21AGXSharedStreamParser"
)
COPY_3D_COMMON_PASSTHROUGH = (
    "__ZN28AGXHardwareKernelCommandUtil27copy3DCommonPassthroughData"
    "EP22AGX3DCommandDescriptorRK21AGX3DCommandCommonRec"
)
PROCESS_RENDER_SETUP = (
    "__ZN15AGXCommandQueue18processRenderSetupERK24AGXHardwareKernelCommand"
    "RK30AGXRenderHardwareKernelCommandRK23AGXSegmentKernelCommandyy"
    "P21CompositeSubtypeStateR22AGXTACommandDescriptorR22AGX3DCommandDescriptor"
    "P18AGXAllocationList2bP11AGXResourceR10IOGPUEventPPSJ_SM_"
    "P14AGX3DWorkQueuePPN12AGXWorkQueue9HashEntryEbbR13AGXUMADescRec"
    "P20AGXUniqueResourceSet"
)
ALLOC_3D_COMMAND_DESCRIPTOR = "__ZNK22AGX3DCommandDescriptor9MetaClass5allocEv"
INIT_3D_COMMAND_DESCRIPTOR = (
    "__ZN22AGX3DCommandDescriptor4initEP5IOGPUP17IOGPUCommandQueueP9IOGPUTask"
    "PKcyP19AGXDebugBufferShmem"
)
ALLOC_TA_COMMAND_DESCRIPTOR = "__ZNK22AGXTACommandDescriptor9MetaClass5allocEv"
INIT_TA_COMMAND_DESCRIPTOR = (
    "__ZN22AGXTACommandDescriptor4initEP5IOGPUP17IOGPUCommandQueueP9IOGPUTask"
    "PKcyP19AGXDebugBufferShmem"
)
REGISTER_LIST_PRODUCERS = {
    "3D": GENERATE_REGISTER_LIST_3D,
    "FastBlit": (
        "__ZN33AGX·PI_300·X·A0·3DChannelSKSM31generateRegisterListForFastBlit"
        "EP26AGFIChannelCommandFastBlitP22AGX3DCommandDescriptor"
    ),
    "CL": (
        "__ZN33AGX·PI_300·X·A0·CLChannelSKSM20generateRegisterList"
        "EP20AGFIChannelCommandCLP22AGXCLCommandDescriptor"
    ),
    "TA": (
        "__ZN33AGX·PI_300·X·A0·TAChannelSKSM20generateRegisterList"
        "EP20AGFIChannelCommandTAP22AGXTACommandDescriptor"
    ),
}
INIT_UAT_HANDOFF = "__ZN27AGXUnifiedAddressTranslator11initHandoffEv"
KERNEL_COLLECTION_BASE = 0xFFFFFE0007004000
G17_INIT_SEQUENCE_VTABLE_SLOT = 0xA88
G17_FW_BRN_SIZE_VTABLE_SLOT = 0xF90
G17_CONFIGURE_DEVICE_VTABLE_SLOT = 0x958
G17_CONFIGURE_POWER_VTABLE_SLOT = 0xA20
G17_PIO_TABLE_VTABLE_SLOT = 0x1168
G17_PIO_TABLE_LENGTH_VTABLE_SLOT = 0x1170
G17_DEFAULT_USC_MAX_TGMEM_VTABLE_SLOT = 0x10E0
G17_GET_PERF_STATE_CAP_VTABLE_SLOT = 0x11D8
G17_SETUP_CSC_ALLOCATION_VTABLE_SLOT = 0xF40
G17_GENERATE_CSC_COEFFICIENTS_VTABLE_SLOT = 0xFB8
G17_BORDER_COLOR_TABLE_ADDRESS_VTABLE_SLOT = 0xE90
FIRMWARE_ADDRESS_CONVERSION_VTABLE_SLOT = 0x2D8
GART_INIT_INFO_VTABLE_SLOT = 0x178
G17_FIRMWARE_EVENT_VALIDATORS = {
    0: (0x1494, "AGFIFirmwareEventAlive", "kAGFIFirmwareEventTypeFirmwareAlive"),
    1: (0x147C, "AGFIFirmwareEventStampUpdate", "kAGFIFirmwareEventTypeStampsUpdated"),
    4: (0x1488, "AGFIFirmwareEventHWRecovery", "kAGFIFirmwareEventTypeGPURestart"),
    6: (0x1570, "AGFIFirmwareEventPMRequestMemory", "kAGFIFirmwareEventTypeAllocatePMMemory"),
    7: (0x14D0, "AGFIChannelErrorEventArgs", "kAGFIFirmwareEventTypeChannelError"),
    8: (0x14A0, "AGFIFirmwareEventMetrologyAging", "kAGFIFirmwareEventTypeMtrResult"),
    9: (0x14DC, "AGFIFirmwareEventUMARequestMemory", "kAGFIFirmwareEventTypeUMAAsyncAlloc"),
    10: (
        0x14C4,
        "AGFIFirmwareEventSharedEventSignalComplete",
        "kAGFIFirmwareEventTypeSharedEventSignalComplete",
    ),
    12: (
        0x14B8,
        "AGFIFirmwareEventProcessExitComplete",
        "kAGFIFirmwareEventTypeProcessExitComplete",
    ),
    13: (
        0x1470,
        "AGFIFirmwareEventUMAGrowPool",
        "kAGFIFirmwareEventTypeUMAAsyncGrowRequestComplete",
    ),
    14: (
        0x14AC,
        "AGFIFirmwareEventRTCompletionInfo",
        "kAGFIFirmwareEventTypeRTCompletionEvent",
    ),
    15: (
        0x1464,
        "AGFIFirmwareEventUMAThresholdInterrupt",
        "kAGFIFirmwareEventTypeUMAThresholdInterrupt",
    ),
}


def macho_uuid(image: bytes) -> str | None:
    for item in load_commands(image):
        if item.command == LC_UUID:
            if item.size < 24:
                raise ValueError("truncated LC_UUID")
            raw = image[item.offset + 8 : item.offset + 24].hex().upper()
            return f"{raw[:8]}-{raw[8:12]}-{raw[12:16]}-{raw[16:20]}-{raw[20:]}"
    return None


def macho_symbols(image: bytes) -> dict[str, int]:
    result: dict[str, int] = {}
    for item in load_commands(image):
        if item.command != LC_SYMTAB:
            continue
        if item.size < 24:
            raise ValueError("truncated LC_SYMTAB")
        symbol_offset, count, string_offset, string_size = struct.unpack_from(
            "<IIII", image, item.offset + 8
        )
        if symbol_offset + count * 16 > len(image):
            raise ValueError("Mach-O symbol table extends past the image")
        if string_offset + string_size > len(image):
            raise ValueError("Mach-O string table extends past the image")
        string_end = string_offset + string_size
        for index in range(count):
            name_offset, _kind, _section, _description, value = struct.unpack_from(
                "<IBBHQ", image, symbol_offset + index * 16
            )
            if not name_offset or name_offset >= string_size:
                continue
            start = string_offset + name_offset
            end = image.find(b"\0", start, string_end)
            if end < 0:
                raise ValueError("unterminated Mach-O symbol name")
            result[image[start:end].decode("utf-8", "replace")] = value
        return result
    raise ValueError("Mach-O has no symbol table")


def virtual_to_file(image: bytes, address: int) -> int:
    for item in load_commands(image):
        if item.command != LC_SEGMENT_64:
            continue
        segment = parse_segment(image, item)
        if segment.virtual_address <= address < segment.virtual_address + segment.file_size:
            return segment.file_offset + address - segment.virtual_address
    raise ValueError(f"virtual address {address:#x} is not backed by a Mach-O segment")


def read_adrp_add_cstring(
    image: bytes, function_address: int, code: bytes, adrp_offset: int, add_offset: int
) -> str:
    if adrp_offset + 4 > len(code) or add_offset + 4 > len(code):
        raise ValueError("truncated PC-relative C string reference")
    page = decode_adrp(
        function_address + adrp_offset,
        struct.unpack_from("<I", code, adrp_offset)[0],
    )
    add = decode_add_immediate(struct.unpack_from("<I", code, add_offset)[0])
    if page is None or add is None or page[0] != add[1]:
        raise ValueError("invalid PC-relative C string reference")
    offset = virtual_to_file(image, page[1] + add[2])
    end = image.find(b"\0", offset)
    if end < 0:
        raise ValueError("unterminated PC-relative C string")
    return image[offset:end].decode("utf-8", "replace")


def symbol_code(image: bytes, name: str) -> tuple[int, bytes]:
    symbols = macho_symbols(image)
    if name not in symbols:
        raise ValueError(f"Mach-O has no {name} symbol")
    address = symbols[name]
    offset = virtual_to_file(image, address)
    following = sorted(value for value in symbols.values() if value > address)
    end_address = following[0] if following else address + 0x10000
    try:
        end = virtual_to_file(image, end_address - 1) + 1
    except ValueError:
        end = min(len(image), offset + 0x10000)
    return address, image[offset:end]


def words(code: bytes):
    for offset in range(0, len(code) - 3, 4):
        yield offset, struct.unpack_from("<I", code, offset)[0]


def decode_move_wide(word: int) -> tuple[str, int, int, int] | None:
    opcode = word & 0xFF800000
    if opcode == 0x92800000:
        kind = "movn"
    elif opcode == 0xD2800000:
        kind = "movz"
    elif opcode == 0xF2800000:
        kind = "movk"
    else:
        return None
    register = word & 0x1F
    shift = ((word >> 21) & 0x3) * 16
    immediate = (word >> 5) & 0xFFFF
    return kind, register, immediate, shift


def find_materialized_constant(code: bytes, target: int) -> list[tuple[int, int, int]]:
    result = []
    decoded = list(words(code))
    for index, (offset, word) in enumerate(decoded):
        move = decode_move_wide(word)
        if move is None or move[0] != "movz":
            continue
        _kind, register, immediate, shift = move
        value = immediate << shift
        end = offset + 4
        for next_offset, next_word in decoded[index + 1 : index + 5]:
            if next_offset != end:
                break
            update = decode_move_wide(next_word)
            if update is None or update[0] != "movk" or update[1] != register:
                break
            _kind, _register, immediate, shift = update
            mask = 0xFFFF << shift
            value = (value & ~mask) | immediate << shift
            end += 4
            if value == target:
                result.append((offset, end, register))
        if value == target and not result:
            result.append((offset, end, register))
    return result


def decode_add_immediate(word: int) -> tuple[int, int, int] | None:
    if word & 0xFF000000 != 0x91000000:
        return None
    destination = word & 0x1F
    source = (word >> 5) & 0x1F
    immediate = (word >> 10) & 0xFFF
    if word & (1 << 22):
        immediate <<= 12
    return destination, source, immediate


def decode_ldp_x(word: int) -> tuple[int, int, int, int] | None:
    if word & 0xFFC00000 != 0xA9400000:
        return None
    first = word & 0x1F
    base = (word >> 5) & 0x1F
    second = (word >> 10) & 0x1F
    immediate = (word >> 15) & 0x7F
    if immediate & 0x40:
        immediate -= 0x80
    return first, second, base, immediate * 8


def decode_str_x(word: int) -> tuple[int, int, int] | None:
    if word & 0xFFC00000 != 0xF9000000:
        return None
    source = word & 0x1F
    base = (word >> 5) & 0x1F
    immediate = ((word >> 10) & 0xFFF) * 8
    return source, base, immediate


def decode_ldr_x(word: int) -> tuple[int, int, int] | None:
    if word & 0xFFC00000 != 0xF9400000:
        return None
    destination = word & 0x1F
    base = (word >> 5) & 0x1F
    immediate = ((word >> 10) & 0xFFF) * 8
    return destination, base, immediate


def decode_ldr_w(word: int) -> tuple[int, int, int] | None:
    if word & 0xFFC00000 != 0xB9400000:
        return None
    destination = word & 0x1F
    base = (word >> 5) & 0x1F
    immediate = ((word >> 10) & 0xFFF) * 4
    return destination, base, immediate


def decode_load_unsigned(word: int) -> tuple[int, int, int, int] | None:
    kinds = {
        0x39400000: 1,
        0x79400000: 2,
        0xB9400000: 4,
        0xF9400000: 8,
        0xBD400000: 4,
        0xFD400000: 8,
        0x3DC00000: 16,
    }
    width = kinds.get(word & 0xFFC00000)
    if width is None:
        return None
    destination = word & 0x1F
    base = (word >> 5) & 0x1F
    immediate = ((word >> 10) & 0xFFF) * width
    return destination, base, immediate, width


def decode_integer_load_unsigned(word: int) -> tuple[int, int, int, int] | None:
    if word & 0xFFC00000 not in (
        0x39400000,
        0x79400000,
        0xB9400000,
        0xF9400000,
    ):
        return None
    return decode_load_unsigned(word)


def decode_integer_store_unsigned(word: int) -> tuple[int, int, int, int] | None:
    if word & 0xFFC00000 not in (
        0x39000000,
        0x79000000,
        0xB9000000,
        0xF9000000,
    ):
        return None
    source = word & 0x1F
    base = (word >> 5) & 0x1F
    width = 1 << ((word >> 30) & 0x3)
    immediate = ((word >> 10) & 0xFFF) * width
    return source, base, immediate, width


def decode_load_register(word: int) -> tuple[int, int, int, int] | None:
    kinds = {
        0x38600800: 1,
        0x78600800: 2,
        0xB8600800: 4,
        0xF8600800: 8,
    }
    width = kinds.get(word & 0xFFE00C00)
    if width is None:
        return None
    destination = word & 0x1F
    base = (word >> 5) & 0x1F
    offset = (word >> 16) & 0x1F
    return destination, base, offset, width


def decode_add_register(word: int) -> tuple[int, int, int, int] | None:
    if word & 0xFF200000 != 0x8B000000:
        return None
    destination = word & 0x1F
    first = (word >> 5) & 0x1F
    second = (word >> 16) & 0x1F
    shift = (word >> 10) & 0x3F
    return destination, first, second, shift


def decode_cmp_w_immediate(word: int) -> tuple[int, int] | None:
    if word & 0xFF00001F != 0x7100001F:
        return None
    source = (word >> 5) & 0x1F
    immediate = (word >> 10) & 0xFFF
    if word & (1 << 22):
        immediate <<= 12
    return source, immediate


def decode_movz_w(word: int) -> tuple[int, int] | None:
    if word & 0xFF800000 != 0x52800000:
        return None
    register = word & 0x1F
    shift = ((word >> 21) & 0x1) * 16
    immediate = ((word >> 5) & 0xFFFF) << shift
    return register, immediate


def decode_movk_w(word: int) -> tuple[int, int, int] | None:
    if word & 0xFF800000 != 0x72800000:
        return None
    register = word & 0x1F
    shift = ((word >> 21) & 0x1) * 16
    immediate = (word >> 5) & 0xFFFF
    return register, immediate, shift


def decode_movn_w(word: int) -> tuple[int, int] | None:
    if word & 0xFF800000 != 0x12800000:
        return None
    register = word & 0x1F
    shift = ((word >> 21) & 0x1) * 16
    immediate = ((word >> 5) & 0xFFFF) << shift
    return register, (~immediate) & 0xFFFFFFFF


def decode_add_sub_immediate_w(word: int) -> tuple[str, int, int, int] | None:
    opcode = word & 0xFF000000
    if opcode == 0x11000000:
        kind = "add"
    elif opcode == 0x51000000:
        kind = "sub"
    else:
        return None
    destination = word & 0x1F
    source = (word >> 5) & 0x1F
    immediate = (word >> 10) & 0xFFF
    if word & (1 << 22):
        immediate <<= 12
    return kind, destination, source, immediate


def decode_logical_immediate_w(word: int) -> tuple[str, int, int, int] | None:
    """Decode a 32-bit logical-immediate instruction and expand its mask."""

    opcode = word & 0xFF800000
    kinds = {
        0x12000000: "and",
        0x32000000: "orr",
        0x52000000: "eor",
        0x72000000: "ands",
    }
    kind = kinds.get(opcode)
    if kind is None:
        return None
    destination = word & 0x1F
    source = (word >> 5) & 0x1F
    immr = (word >> 16) & 0x3F
    imms = (word >> 10) & 0x3F

    # ARM's DecodeBitMasks algorithm. N is necessarily zero for the W form.
    length_source = (~imms) & 0x3F
    length = length_source.bit_length() - 1
    if length < 1:
        return None
    levels = (1 << length) - 1
    rotation = immr & levels
    ones = imms & levels
    if ones == levels:
        return None
    element_bits = 1 << length
    element_mask = (1 << element_bits) - 1
    element = (1 << (ones + 1)) - 1
    if rotation:
        element = (
            (element >> rotation) | (element << (element_bits - rotation))
        ) & element_mask
    immediate = 0
    for shift in range(0, 32, element_bits):
        immediate |= element << shift
    return kind, destination, source, immediate


def resolve_static_w_register(
    instructions: list[tuple[int, int]], before: int, register: int, depth: int = 0
) -> int | None:
    """Resolve the local constant feeding a 32-bit register use.

    The G17 register-list producers keep a few selector bases in callee-saved
    registers and derive individual selectors with ADD/SUB immediates. This
    deliberately narrow backwards slice handles only those forms and rejects
    loads or calls which could make the value runtime-dependent.
    """

    if depth > 8:
        return None

    use_offset = instructions[before][0] if before < len(instructions) else 1 << 63
    for index in range(before - 1, -1, -1):
        offset, word = instructions[index]
        inverted = decode_movn_w(word)
        if inverted is not None and inverted[0] == register:
            return inverted[1]
        materialized = decode_movz_w(word)
        if materialized is not None and materialized[0] == register:
            return materialized[1] & 0xFFFFFFFF
        updated = decode_movk_w(word)
        if updated is not None and updated[0] == register:
            base = resolve_static_w_register(instructions, index, register, depth + 1)
            if base is None:
                return None
            _destination, immediate, shift = updated
            mask = 0xFFFF << shift
            return ((base & ~mask) | immediate << shift) & 0xFFFFFFFF
        arithmetic = decode_add_sub_immediate_w(word)
        if arithmetic is not None and arithmetic[1] == register:
            kind, _destination, source, immediate = arithmetic
            base = resolve_static_w_register(instructions, index, source, depth + 1)
            if base is None:
                return None
            if kind == "add":
                return (base + immediate) & 0xFFFFFFFF
            return (base - immediate) & 0xFFFFFFFF

        logical = decode_logical_immediate_w(word)
        if logical is not None and logical[1] == register:
            kind, _destination, source, immediate = logical
            base = 0 if source == 31 else resolve_static_w_register(
                instructions, index, source, depth + 1
            )
            if base is None:
                return None
            if kind == "and" or kind == "ands":
                return base & immediate
            if kind == "orr":
                return base | immediate
            return base ^ immediate

        logical_register = decode_orr_register(word)
        if logical_register is not None and logical_register[0] == register:
            _destination, first, second = logical_register
            first_value = 0 if first == 31 else resolve_static_w_register(
                instructions, index, first, depth + 1
            )
            second_value = 0 if second == 31 else resolve_static_w_register(
                instructions, index, second, depth + 1
            )
            if first_value is None or second_value is None:
                return None
            return first_value | second_value

        # A load makes the value data-dependent. Direct and authenticated
        # calls clobber the caller-saved registers under AAPCS64.
        load = decode_load_unsigned(word)
        if load is not None and load[0] == register:
            return None
        load = decode_load_register(word)
        if load is not None and load[0] == register:
            return None

        # Reject instruction families which write the register but are not in
        # the intentionally small constant-expression language above. This is
        # especially important for callee-saved selector bases: several are
        # reused for runtime data later in the same producer.
        destination = word & 0x1F
        instruction_class = word & 0x1F000000
        if destination == register and instruction_class in (
            0x0A000000,  # logical shifted-register, including shifted ORR
            0x0B000000,  # add/subtract shifted or extended register
            0x10000000,  # PC-relative address generation
            0x11000000,  # other add/subtract immediate forms
            0x12000000,  # other logical-immediate forms
            0x13000000,  # bitfield/extract forms
            0x1A000000,  # conditional/data-processing register forms
            0x1B000000,  # multiply-add forms
        ):
            return None
        wide = decode_move_wide(word)
        if wide is not None and wide[1] == register:
            return None
        if register <= 18 and (
            decode_bl_target(offset, word) is not None
            or word & 0xFFFFFC00 == 0xD73F0800
        ):
            # The producers occasionally lower two mutually exclusive call
            # paths as call; b join; call; join. The first call cannot clobber
            # the second path when its following unconditional branch skips
            # the current use, so continue through that dead linear range.
            skipped = any(
                (target := decode_b_target(branch_offset, branch_word)) is not None
                and target > use_offset
                for branch_offset, branch_word in instructions[index + 1 : before]
            )
            if not skipped:
                return None
    return None


def resolve_static_x_register(
    instructions: list[tuple[int, int]], before: int, register: int, depth: int = 0
) -> int | None:
    """Resolve a move-wide constant feeding a 64-bit argument register."""

    if depth > 8:
        return None
    for index in range(before - 1, -1, -1):
        _offset, word = instructions[index]
        inverted_w = decode_movn_w(word)
        if inverted_w is not None and inverted_w[0] == register:
            return inverted_w[1]
        materialized_w = decode_movz_w(word)
        if materialized_w is not None and materialized_w[0] == register:
            return materialized_w[1] & 0xFFFFFFFF
        updated_w = decode_movk_w(word)
        if updated_w is not None and updated_w[0] == register:
            return resolve_static_w_register(instructions, before, register)

        wide = decode_move_wide(word)
        if wide is not None and wide[1] == register:
            kind, _destination, immediate, shift = wide
            if kind == "movn":
                return (~(immediate << shift)) & 0xFFFFFFFFFFFFFFFF
            if kind == "movz":
                return immediate << shift
            base = resolve_static_x_register(instructions, index, register, depth + 1)
            if base is None:
                return None
            mask = 0xFFFF << shift
            return ((base & ~mask) | immediate << shift) & 0xFFFFFFFFFFFFFFFF

        load = decode_load_unsigned(word)
        if load is not None and load[0] == register:
            return None
        load = decode_load_register(word)
        if load is not None and load[0] == register:
            return None
        destination = word & 0x1F
        if destination == register and word & 0x1F000000 in (
            0x0A000000,
            0x0B000000,
            0x11000000,
            0x12000000,
            0x13000000,
            0x1A000000,
            0x1B000000,
        ):
            return None
        if register <= 18 and (
            decode_bl_target(0, word) is not None
            or word & 0xFFFFFC00 == 0xD73F0800
        ):
            return None
    return None


def decode_register_copy(word: int) -> tuple[int, int, int] | None:
    """Decode the MOV alias of ORR with the zero register."""

    # sf | 01 | 01010 | 0 | 00 | Rm | 000000 | 11111 | Rd
    if word & 0x7FE0FFE0 != 0x2A0003E0:
        return None
    width = 8 if word & 0x80000000 else 4
    return word & 0x1F, (word >> 16) & 0x1F, width


def decode_local_branch_target(address: int, word: int) -> int | None:
    """Decode direct intra-function branches used by dominance checks."""

    target = decode_b_target(address, word)
    if target is not None:
        return target
    if word & 0xFF000010 == 0x54000000:  # B.cond
        immediate = (word >> 5) & 0x7FFFF
        bits = 19
    elif word & 0x7E000000 == 0x34000000:  # CBZ / CBNZ
        immediate = (word >> 5) & 0x7FFFF
        bits = 19
    elif word & 0x7E000000 == 0x36000000:  # TBZ / TBNZ
        immediate = (word >> 5) & 0x3FFF
        bits = 14
    else:
        return None
    if immediate & (1 << (bits - 1)):
        immediate -= 1 << bits
    return address + immediate * 4


def decode_conditional_branch(
    address: int, word: int
) -> tuple[int, str] | None:
    if word & 0xFF000010 != 0x54000000:
        return None
    target = decode_local_branch_target(address, word)
    if target is None:
        return None
    condition = (
        "eq",
        "ne",
        "cs",
        "cc",
        "mi",
        "pl",
        "vs",
        "vc",
        "hi",
        "ls",
        "ge",
        "lt",
        "gt",
        "le",
        "al",
        "nv",
    )[word & 0xF]
    if condition in ("al", "nv"):
        return None
    return target, condition


def decode_test_bit_branch(address: int, word: int) -> dict[str, object] | None:
    if word & 0x7E000000 != 0x36000000:
        return None
    target = decode_local_branch_target(address, word)
    if target is None:
        return None
    bit = ((word >> 31) & 0x1) << 5 | (word >> 19) & 0x1F
    return {
        "target": target,
        "condition": "bit_set" if word & (1 << 24) else "bit_clear",
        "register": word & 0x1F,
        "bit": bit,
        "bytes": 8 if bit >= 32 else 4,
    }


def decode_compare_zero_branch(
    address: int, word: int
) -> dict[str, object] | None:
    if word & 0x7E000000 != 0x34000000:
        return None
    target = decode_local_branch_target(address, word)
    if target is None:
        return None
    return {
        "target": target,
        "condition": "nonzero" if word & (1 << 24) else "zero",
        "register": word & 0x1F,
        "bytes": 8 if word & (1 << 31) else 4,
    }


def g17_register_is_written(word: int, register: int) -> bool:
    """Recognize the integer writers present in the register-list producers."""

    load = decode_integer_load_unsigned(word)
    if load is not None and load[0] == register:
        return True
    load = decode_load_register(word)
    if load is not None and load[0] == register:
        return True
    if word & 0xFFC0001F == 0xB9800000 | register:  # LDRSW Xt, [Xn, #imm]
        return True
    pair = decode_ldp_x(word)
    if pair is not None and register in pair[:2]:
        return True
    move = decode_move_wide(word)
    if move is not None and move[1] == register:
        return True
    move_w = decode_movz_w(word)
    if move_w is not None and move_w[0] == register:
        return True
    move_n_w = decode_movn_w(word)
    if move_n_w is not None and move_n_w[0] == register:
        return True
    update_w = decode_movk_w(word)
    if update_w is not None and update_w[0] == register:
        return True
    return word & 0x1F == register and word & 0x1F000000 in (
        0x0A000000,
        0x0B000000,
        0x10000000,
        0x11000000,
        0x12000000,
        0x13000000,
        0x1A000000,
        0x1B000000,
    )


def find_dominating_g17_register_write(
    instructions: list[tuple[int, int]], use_index: int, register: int
) -> int | None:
    """Find a reaching integer definition without choosing across a CFG join."""

    definition_index = next(
        (
            index
            for index in range(use_index - 1, -1, -1)
            if g17_register_is_written(instructions[index][1], register)
        ),
        None,
    )
    if definition_index is None:
        return None

    definition_offset = instructions[definition_index][0]
    use_offset = (
        instructions[use_index][0]
        if use_index < len(instructions)
        else instructions[-1][0] + 4
    )
    for branch_index, (offset, word) in enumerate(instructions):
        target = decode_local_branch_target(offset, word)
        if (
            target is not None
            and definition_offset < target <= use_offset
            and branch_index < definition_index
        ):
            return None

    # AAPCS64 calls may replace every caller-saved register. Callee-saved
    # values are precisely why the copy tracing above is useful across calls.
    if register <= 18:
        for offset, word in instructions[definition_index + 1 : use_index]:
            if (
                decode_bl_target(offset, word) is not None
                or word & 0xFFFFFC00 == 0xD73F0800
            ):
                return None
    return definition_index


def g17_definition_dominates_use(
    instructions: list[tuple[int, int]], definition_index: int, use_index: int
) -> bool:
    """Reject a definition when an earlier forward edge can skip it."""

    definition_offset = instructions[definition_index][0]
    use_offset = (
        instructions[use_index][0]
        if use_index < len(instructions)
        else instructions[-1][0] + 4
    )
    return not any(
        target is not None
        and definition_offset < target <= use_offset
        and branch_index < definition_index
        for branch_index, (offset, word) in enumerate(instructions)
        for target in (decode_local_branch_target(offset, word),)
    )


def trace_g17_known_call_return(
    instructions: list[tuple[int, int]],
    use_index: int,
    depth: int,
    seen: frozenset[tuple[int, int]],
) -> dict[str, object] | None:
    """Recognize the narrow set of UUID-pinned virtual return values."""

    for call_index in range(use_index - 1, -1, -1):
        call_offset, call_word = instructions[call_index]
        if g17_register_is_written(call_word, 0):
            return None
        direct_call = decode_bl_target(call_offset, call_word)
        authenticated_call = call_word & 0xFFFFFC00 == 0xD73F0800
        if direct_call is None and not authenticated_call:
            continue
        if direct_call is not None:
            if (
                call_offset == G17_CL_RANDOM_CALL_OFFSET
                and call_word == G17_CL_RANDOM_CALL_WORD
                and g17_definition_dominates_use(
                    instructions, call_index, use_index
                )
            ):
                return {
                    "kind": "call_result",
                    "producer_offset": call_offset,
                    "method": "random",
                    "provider": KERNEL_RANDOM,
                    "bytes": 4,
                }
            return None
        if not authenticated_call or not g17_definition_dominates_use(
            instructions, call_index, use_index
        ):
            return None

        target_register = (call_word >> 5) & 0x1F
        target_index = find_dominating_g17_register_write(
            instructions, call_index, target_register
        )
        if target_index is None:
            return None
        target_load = decode_integer_load_unsigned(instructions[target_index][1])
        if target_load is None:
            return None
        destination, base, member, width = target_load
        if destination != target_register or base != 16 or width != 8:
            return None
        method = G17_CONSTANT_VIRTUAL_RETURNS.get(member)
        if method is None:
            if member != IOGPU_MEMORY_MAP_GPU_VA_SLOT:
                return None
            receiver = trace_g17_value_expression(
                instructions,
                call_index,
                0,
                depth + 1,
                seen | {(use_index, 0)},
            )
            if (
                receiver is None
                or receiver.get("kind") != "object_load"
                or receiver.get("member") != 0x68
                or not isinstance(receiver.get("base"), dict)
                or receiver["base"].get("kind") != "object_load"
                or receiver["base"].get("member") != 0x30
            ):
                return None
            return {
                "kind": "virtual_load",
                "producer_offset": call_offset,
                "vtable_slot": member,
                "method": "gpu_virtual_address",
                "provider": IOGPU_MEMORY_MAP_GPU_VA,
                "member": IOGPU_MEMORY_MAP_GPU_VA_MEMBER,
                "receiver": receiver,
            }
        label, provider, value = method
        return {
            "kind": "constant_call",
            "producer_offset": call_offset,
            "vtable_slot": member,
            "method": label,
            "provider": provider,
            "value": value,
        }
    return None


def trace_g17_stack_load(
    instructions: list[tuple[int, int]],
    load_index: int,
    member: int,
    width: int,
    depth: int,
    seen: frozenset[tuple[int, int]],
) -> dict[str, object] | None:
    """Trace a fixed SP-relative reload to one unambiguous integer store."""

    load_end = member + width
    for index in range(load_index - 1, -1, -1):
        offset, word = instructions[index]

        # A different SP value makes offsets on the two sides incomparable.
        arithmetic = decode_add_sub_immediate_value(word)
        if (
            arithmetic is not None
            and arithmetic["bytes"] == 8
            and arithmetic["destination_register"] == 31
            and arithmetic["source_register"] == 31
        ):
            return None

        stores: list[tuple[int | None, int, int]] = []
        store = decode_str_unsigned(word)
        if store is not None and store[1] == 31:
            source, _base, store_member, store_width = store
            integer_store = decode_integer_store_unsigned(word)
            stores.append(
                (
                    source if integer_store is not None else None,
                    store_member,
                    store_width,
                )
            )
        unscaled = decode_stur_x(word)
        if unscaled is not None and unscaled[1] == 31:
            source, _base, store_member = unscaled
            stores.append((source, store_member, 8))
        pair = decode_stp_x(word)
        if pair is not None and pair[2] == 31:
            first, second, _base, store_member = pair
            stores.extend(
                ((first, store_member, 8), (second, store_member + 8, 8))
            )
        vector_pair = decode_pair_q(word)
        if (
            vector_pair is not None
            and vector_pair[0] == "store"
            and vector_pair[3] == 31
        ):
            _kind, _first, _second, _base, store_member = vector_pair
            stores.extend(
                ((None, store_member, 16), (None, store_member + 16, 16))
            )

        for source, store_member, store_width in stores:
            store_end = store_member + store_width
            if store_member >= load_end or member >= store_end:
                continue
            if (
                source is None
                or store_member != member
                or store_width != width
                or not g17_definition_dominates_use(instructions, index, load_index)
            ):
                return None
            source_value = (
                {"kind": "constant", "value": 0}
                if source == 31
                else trace_g17_value_expression(
                    instructions, index, source, depth + 1, seen
                )
            )
            if source_value is None:
                return None
            return {
                "kind": "stack_reload",
                "producer_offset": instructions[load_index][0],
                "slot": member,
                "bytes": width,
                "store_offset": offset,
                "source": source_value,
            }
    return None


def trace_g17_register_copy(
    instructions: list[tuple[int, int]], copy_index: int, source: int
) -> dict[str, object] | None:
    """Trace a callee-saved value copy to a dominating load or constant."""

    if not 19 <= source <= 28:
        return None
    definition_index = find_dominating_g17_register_write(
        instructions, copy_index, source
    )
    if definition_index is None:
        return None

    definition_offset, definition = instructions[definition_index]
    copy_offset = instructions[copy_index][0]

    load = decode_integer_load_unsigned(definition)
    if load is not None and load[0] == source and load[1] == 19:
        _destination, base, member, width = load
        return {
            "kind": "descriptor_load",
            "producer_offset": copy_offset,
            "source_offset": definition_offset,
            "via_register": source,
            "base_register": base,
            "member": member,
            "bytes": width,
            "signed": False,
        }
    if definition & 0xFFC0001F == 0xB9800000 | source:
        base = (definition >> 5) & 0x1F
        if base == 19:
            return {
                "kind": "descriptor_load",
                "producer_offset": copy_offset,
                "source_offset": definition_offset,
                "via_register": source,
                "base_register": base,
                "member": ((definition >> 10) & 0xFFF) * 4,
                "bytes": 4,
                "signed": True,
            }
    if (
        decode_move_wide(definition) is not None
        or decode_movn_w(definition) is not None
        or decode_movz_w(definition) is not None
        or decode_movk_w(definition) is not None
    ):
        value = resolve_static_x_register(instructions, copy_index, source)
        if value is not None:
            return {
                "kind": "constant",
                "producer_offset": copy_offset,
                "source_offset": definition_offset,
                "via_register": source,
                "value": value,
            }
    return None


def decode_logical_shifted_register(word: int) -> dict[str, object] | None:
    if word & 0x1F000000 != 0x0A000000:
        return None
    width = 8 if word & 0x80000000 else 4
    amount = (word >> 10) & 0x3F
    if width == 4 and amount >= 32:
        return None
    kinds = ("and", "orr", "eor", "ands")
    kind = kinds[(word >> 29) & 0x3]
    if word & (1 << 21):
        kind = {"and": "bic", "orr": "orn", "eor": "eon", "ands": "bics"}[
            kind
        ]
    return {
        "operation": kind,
        "destination_register": word & 0x1F,
        "first_register": (word >> 5) & 0x1F,
        "second_register": (word >> 16) & 0x1F,
        "shift": ("lsl", "lsr", "asr", "ror")[(word >> 22) & 0x3],
        "amount": amount,
        "bytes": width,
    }


def decode_logical_immediate_x(word: int) -> tuple[str, int, int, int] | None:
    kinds = {
        0x92000000: "and",
        0xB2000000: "orr",
        0xD2000000: "eor",
        0xF2000000: "ands",
    }
    kind = kinds.get(word & 0xFF800000)
    if kind is None:
        return None
    destination = word & 0x1F
    source = (word >> 5) & 0x1F
    n = (word >> 22) & 0x1
    immr = (word >> 16) & 0x3F
    imms = (word >> 10) & 0x3F
    length_source = n << 6 | (~imms & 0x3F)
    length = length_source.bit_length() - 1
    if length < 1:
        return None
    levels = (1 << length) - 1
    rotation = immr & levels
    ones = imms & levels
    if ones == levels:
        return None
    element_bits = 1 << length
    element_mask = (1 << element_bits) - 1
    element = (1 << (ones + 1)) - 1
    if rotation:
        element = (
            (element >> rotation) | (element << (element_bits - rotation))
        ) & element_mask
    immediate = 0
    for shift in range(0, 64, element_bits):
        immediate |= element << shift
    return kind, destination, source, immediate


def decode_add_sub_immediate_value(word: int) -> dict[str, object] | None:
    if word & 0x1F000000 != 0x11000000:
        return None
    immediate = (word >> 10) & 0xFFF
    if word & (1 << 22):
        immediate <<= 12
    return {
        "operation": "sub" if word & (1 << 30) else "add",
        "destination_register": word & 0x1F,
        "source_register": (word >> 5) & 0x1F,
        "immediate": immediate,
        "bytes": 8 if word & 0x80000000 else 4,
    }


def decode_add_sub_register_value(word: int) -> dict[str, object] | None:
    if word & 0x1F000000 != 0x0B000000:
        return None
    result: dict[str, object] = {
        "operation": "sub" if word & (1 << 30) else "add",
        "destination_register": word & 0x1F,
        "first_register": (word >> 5) & 0x1F,
        "second_register": (word >> 16) & 0x1F,
        "bytes": 8 if word & 0x80000000 else 4,
    }
    if word & (1 << 21):
        result["extend"] = (
            "uxtb",
            "uxth",
            "uxtw",
            "uxtx",
            "sxtb",
            "sxth",
            "sxtw",
            "sxtx",
        )[(word >> 13) & 0x7]
        result["amount"] = (word >> 10) & 0x7
    else:
        shift = (word >> 22) & 0x3
        if shift == 3:
            return None
        result["shift"] = ("lsl", "lsr", "asr")[shift]
        result["amount"] = (word >> 10) & 0x3F
    return result


def decode_bitfield_value(word: int) -> dict[str, object] | None:
    if word & 0x1F800000 != 0x13000000:
        return None
    opcode = (word >> 29) & 0x3
    if opcode == 3:
        return None
    width = 8 if word & 0x80000000 else 4
    if ((word >> 22) & 0x1) != (width == 8):
        return None
    return {
        "operation": ("sbfm", "bfm", "ubfm")[opcode],
        "destination_register": word & 0x1F,
        "source_register": (word >> 5) & 0x1F,
        "rotate": (word >> 16) & 0x3F,
        "mask_end": (word >> 10) & 0x3F,
        "bytes": width,
    }


def decode_conditional_select_value(word: int) -> dict[str, object] | None:
    if word & 0x1FE00000 != 0x1A800000:
        return None
    op2 = (word >> 10) & 0x3
    if op2 > 1:
        return None
    operation = (
        ("csel", "csinc"),
        ("csinv", "csneg"),
    )[(word >> 30) & 0x1][op2]
    return {
        "operation": operation,
        "destination_register": word & 0x1F,
        "first_register": (word >> 5) & 0x1F,
        "second_register": (word >> 16) & 0x1F,
        "condition": (
            "eq",
            "ne",
            "cs",
            "cc",
            "mi",
            "pl",
            "vs",
            "vc",
            "hi",
            "ls",
            "ge",
            "lt",
            "gt",
            "le",
            "al",
            "nv",
        )[(word >> 12) & 0xF],
        "bytes": 8 if word & 0x80000000 else 4,
    }


def trace_g17_condition_expression(
    instructions: list[tuple[int, int]],
    use_index: int,
    depth: int,
    seen: frozenset[tuple[int, int]],
) -> dict[str, object] | None:
    """Recover the compare/test which supplies a conditional select's NZCV."""

    for definition_index in range(use_index - 1, -1, -1):
        offset, word = instructions[definition_index]
        immediate = decode_add_sub_immediate_value(word)
        logical_x = decode_logical_immediate_x(word)
        logical_w = decode_logical_immediate_w(word)
        register = decode_add_sub_register_value(word)
        logical_register = decode_logical_shifted_register(word)
        logical = logical_x if logical_x is not None else logical_w
        sets_flags = bool(
            immediate is not None and word & (1 << 29)
            or logical is not None and logical[0] == "ands"
            or register is not None and word & (1 << 29)
            or logical_register is not None
            and logical_register["operation"] in ("ands", "bics")
        )
        if not sets_flags:
            continue
        if not (
            immediate is not None
            or logical_x is not None
            or logical_w is not None
            or register is not None
            or logical_register is not None
        ):
            return None

        use_offset = instructions[use_index][0]
        for branch_index, (branch_offset, branch_word) in enumerate(instructions):
            target = decode_local_branch_target(branch_offset, branch_word)
            if (
                target is not None
                and offset < target <= use_offset
                and branch_index < definition_index
            ):
                return None
        for call_offset, call_word in instructions[definition_index + 1 : use_index]:
            if (
                decode_bl_target(call_offset, call_word) is not None
                or call_word & 0xFFFFFC00 == 0xD73F0800
            ):
                return None

        if immediate is not None:
            source = int(immediate["source_register"])
            if source == 31:
                return None
            source_value = trace_g17_value_expression(
                instructions, definition_index, source, depth + 1, seen
            )
            if source_value is None:
                return None
            return {
                "kind": "condition",
                "producer_offset": offset,
                "operation": "cmp" if immediate["operation"] == "sub" else "cmn",
                "bytes": immediate["bytes"],
                "source": source_value,
                "immediate": immediate["immediate"],
            }

        if logical is not None:
            _operation, _destination, source, value = logical
            source_value = (
                {"kind": "constant", "value": 0}
                if source == 31
                else trace_g17_value_expression(
                    instructions, definition_index, source, depth + 1, seen
                )
            )
            if source_value is None:
                return None
            return {
                "kind": "condition",
                "producer_offset": offset,
                "operation": "tst",
                "bytes": 8 if logical_x is not None else 4,
                "source": source_value,
                "immediate": value,
            }

        if register is not None:
            operands = []
            for source in (register["first_register"], register["second_register"]):
                if source == 31:
                    return None
                source_value = trace_g17_value_expression(
                    instructions, definition_index, int(source), depth + 1, seen
                )
                if source_value is None:
                    return None
                operands.append(source_value)
            return {
                "kind": "condition",
                "producer_offset": offset,
                "operation": "cmp" if register["operation"] == "sub" else "cmn",
                "bytes": register["bytes"],
                "modifier": register.get("extend", register.get("shift")),
                "amount": register["amount"],
                "first": operands[0],
                "second": operands[1],
            }

        if logical_register is not None:
            operands = []
            for source in (
                logical_register["first_register"],
                logical_register["second_register"],
            ):
                source_value = (
                    {"kind": "constant", "value": 0}
                    if source == 31
                    else trace_g17_value_expression(
                        instructions, definition_index, int(source), depth + 1, seen
                    )
                )
                if source_value is None:
                    return None
                operands.append(source_value)
            return {
                "kind": "condition",
                "producer_offset": offset,
                "operation": "tst",
                "bytes": logical_register["bytes"],
                "shift": logical_register["shift"],
                "amount": logical_register["amount"],
                "first": operands[0],
                "second": operands[1],
            }
    return None


def trace_g17_four_way_compare_merge(
    instructions: list[tuple[int, int]],
    use_index: int,
    register: int,
    depth: int,
    seen: frozenset[tuple[int, int]],
) -> dict[str, object] | None:
    """Recover Apple's compact 8/4/2/default register initialization."""

    definition_index = next(
        (
            index
            for index in range(use_index - 1, -1, -1)
            if g17_register_is_written(instructions[index][1], register)
        ),
        None,
    )
    if definition_index is None or definition_index < 10:
        return None
    start = definition_index - 10
    block = instructions[start : definition_index + 2]
    if len(block) != 12:
        return None
    join = block[11][0]

    compares = []
    for relative, immediate in ((0, 8), (2, 4), (4, 2)):
        decoded = decode_add_sub_immediate_value(block[relative][1])
        if (
            decoded is None
            or decoded["operation"] != "sub"
            or decoded["destination_register"] != 31
            or decoded["immediate"] != immediate
            or decoded["bytes"] != 4
            or not block[relative][1] & (1 << 29)
        ):
            return None
        compares.append(int(decoded["source_register"]))
    if len(set(compares)) != 1 or compares[0] == 31:
        return None

    expected_branches = (
        (1, "eq", block[10][0]),
        (3, "eq", block[8][0]),
        (5, "ne", join),
    )
    for relative, condition, target in expected_branches:
        decoded = decode_conditional_branch(*block[relative])
        if decoded != (target, condition):
            return None
    if decode_b_target(*block[7]) != join or decode_b_target(*block[9]) != join:
        return None

    for relative, immediate in ((6, 1), (8, 2), (10, 3)):
        logical = decode_logical_immediate_x(block[relative][1])
        if (
            logical is None
            or logical[:3] != ("orr", register, register)
            or logical[3] != immediate
        ):
            return None

    selector = trace_g17_value_expression(
        instructions, start, compares[0], depth + 1, seen
    )
    base = trace_g17_value_expression(
        instructions, start, register, depth + 1, seen
    )
    if selector is None or base is None:
        return None

    def value_with_bits(immediate: int) -> dict[str, object]:
        return {
            "kind": "expression",
            "producer_offset": block[{1: 6, 2: 8, 3: 10}[immediate]][0],
            "operation": "orr",
            "bytes": 8,
            "immediate": immediate,
            "source": base,
        }

    return {
        "kind": "expression",
        "producer_offset": block[0][0],
        "operation": "multiway_select",
        "selector": selector,
        "cases": [
            {"equals": 8, "value": value_with_bits(3)},
            {"equals": 4, "value": value_with_bits(2)},
            {"equals": 2, "value": value_with_bits(1)},
        ],
        "default": base,
        "join_offset": join,
    }


def trace_g17_optional_bit_set_merge(
    instructions: list[tuple[int, int]],
    use_index: int,
    register: int,
    depth: int,
    seen: frozenset[tuple[int, int]],
) -> dict[str, object] | None:
    """Recover the nested test/CBNZ/compare guard around one ORR bit set."""

    definition_index = next(
        (
            index
            for index in range(use_index - 1, -1, -1)
            if g17_register_is_written(instructions[index][1], register)
        ),
        None,
    )
    if definition_index is None or definition_index < 6:
        return None
    definition_offset, definition = instructions[definition_index]
    logical = decode_logical_immediate_x(definition)
    if (
        logical is None
        or logical[0] != "orr"
        or logical[1] != register
        or logical[2] != register
    ):
        return None
    join = (
        instructions[definition_index + 1][0]
        if definition_index + 1 < len(instructions)
        else definition_offset + 4
    )
    outer_index = definition_index - 6
    compare_zero_index = definition_index - 4
    inner_index = definition_index - 1
    outer_offset, outer_word = instructions[outer_index]
    compare_zero_offset, compare_zero_word = instructions[compare_zero_index]
    inner_offset, inner_word = instructions[inner_index]
    outer = decode_test_bit_branch(outer_offset, outer_word)
    compare_zero = decode_compare_zero_branch(
        compare_zero_offset, compare_zero_word
    )
    inner = decode_conditional_branch(inner_offset, inner_word)
    if (
        outer is None
        or int(outer["target"]) != join
        or compare_zero is None
        or compare_zero["condition"] != "nonzero"
        or int(compare_zero["target"]) != definition_offset
        or inner is None
        or inner[0] != join
    ):
        return None

    base = trace_g17_value_expression(
        instructions, definition_index, register, depth + 1, seen
    )
    outer_source = trace_g17_value_expression(
        instructions,
        outer_index,
        int(outer["register"]),
        depth + 1,
        seen,
    )
    compare_zero_source = trace_g17_value_expression(
        instructions,
        compare_zero_index,
        int(compare_zero["register"]),
        depth + 1,
        seen,
    )
    inner_predicate = trace_g17_condition_expression(
        instructions, inner_index, depth + 1, seen
    )
    if (
        base is None
        or outer_source is None
        or compare_zero_source is None
        or inner_predicate is None
    ):
        return None

    modified = {
        "kind": "expression",
        "producer_offset": definition_offset,
        "operation": "orr",
        "bytes": 8,
        "immediate": logical[3],
        "source": base,
    }
    inner_select = {
        "kind": "expression",
        "producer_offset": inner_offset,
        "operation": "branch_select",
        "condition": inner[1],
        "target_offset": join,
        "predicate": inner_predicate,
        "taken": base,
        "fallthrough": modified,
    }
    compare_zero_select = {
        "kind": "expression",
        "producer_offset": compare_zero_offset,
        "operation": "branch_select",
        "condition": "nonzero",
        "target_offset": definition_offset,
        "predicate": {
            "kind": "condition",
            "producer_offset": compare_zero_offset,
            "operation": "compare_zero",
            "bytes": compare_zero["bytes"],
            "source": compare_zero_source,
        },
        "taken": modified,
        "fallthrough": inner_select,
    }
    return {
        "kind": "expression",
        "producer_offset": outer_offset,
        "operation": "branch_select",
        "condition": outer["condition"],
        "target_offset": join,
        "predicate": {
            "kind": "condition",
            "producer_offset": outer_offset,
            "operation": "test_bit",
            "bytes": outer["bytes"],
            "bit": outer["bit"],
            "source": outer_source,
        },
        "taken": base,
        "fallthrough": compare_zero_select,
    }


def trace_g17_cl_base_merge(
    instructions: list[tuple[int, int]],
    use_index: int,
    register: int,
    depth: int,
    seen: frozenset[tuple[int, int]],
) -> dict[str, object] | None:
    """Recover CL's table/fallback base selected by two descriptor fields."""

    definition_index = next(
        (
            index
            for index in range(use_index - 1, -1, -1)
            if g17_register_is_written(instructions[index][1], register)
        ),
        None,
    )
    if definition_index is None or definition_index < 28:
        return None
    start = definition_index - 28
    block = instructions[start : definition_index + 2]
    if len(block) != 30:
        return None
    join = block[29][0]
    outer = decode_test_bit_branch(*block[1])
    inner = decode_conditional_branch(*block[5])
    if (
        outer is None
        or outer["condition"] != "bit_clear"
        or outer["target"] != block[16][0]
        or inner != (block[20][0], "hi")
        or decode_b_target(*block[15]) != block[23][0]
        or decode_b_target(*block[19]) != join
    ):
        return None
    packed = decode_logical_shifted_register(block[24][1])
    masked = decode_logical_shifted_register(block[28][1])
    if (
        packed is None
        or packed["operation"] != "orr"
        or packed["destination_register"] != 10
        or packed["first_register"] != 10
        or packed["second_register"] != 11
        or packed["shift"] != "lsl"
        or packed["amount"] != 17
        or masked is None
        or masked["operation"] != "and"
        or masked["destination_register"] != register
        or masked["first_register"] != 10
        or masked["second_register"] != 11
        or masked["amount"] != 0
    ):
        return None

    def load_value(relative: int) -> dict[str, object] | None:
        load = decode_integer_load_unsigned(block[relative][1])
        if load is None:
            return None
        _destination, base, member, width = load
        if base == 19:
            return {
                "kind": "descriptor_load",
                "producer_offset": block[relative][0],
                "member": member,
                "bytes": width,
                "signed": False,
            }
        base_value = trace_g17_value_expression(
            instructions, start + relative, base, depth + 1, seen
        )
        if base_value is None:
            return None
        return {
            "kind": "object_load",
            "producer_offset": block[relative][0],
            "member": member,
            "bytes": width,
            "signed": False,
            "base": base_value,
        }

    flag = load_value(0)
    predicate = trace_g17_condition_expression(
        instructions, start + 5, depth + 1, seen
    )
    table_value = trace_g17_value_expression(
        instructions, start + 15, 10, depth + 1, seen
    )
    descriptor_bits = load_value(23)
    constant_base = resolve_static_x_register(instructions, start + 19, register)
    fallback = resolve_static_x_register(instructions, start + 23, 10)
    mask = resolve_static_x_register(instructions, start + 28, 11)
    if (
        flag is None
        or predicate is None
        or table_value is None
        or descriptor_bits is None
        or constant_base is None
        or fallback is None
        or mask is None
    ):
        return None

    selected = {
        "kind": "expression",
        "producer_offset": block[5][0],
        "operation": "branch_select",
        "condition": "hi",
        "target_offset": block[20][0],
        "predicate": predicate,
        "taken": {
            "kind": "constant",
            "producer_offset": block[22][0],
            "value": fallback,
        },
        "fallthrough": table_value,
    }
    dynamic = {
        "kind": "expression",
        "producer_offset": block[28][0],
        "operation": "and",
        "bytes": 8,
        "first": {
            "kind": "expression",
            "producer_offset": block[24][0],
            "operation": "orr",
            "bytes": 8,
            "shift": "lsl",
            "amount": 17,
            "first": selected,
            "second": descriptor_bits,
        },
        "second": {
            "kind": "constant",
            "producer_offset": block[27][0],
            "value": mask,
        },
    }
    return {
        "kind": "expression",
        "producer_offset": block[1][0],
        "operation": "branch_select",
        "condition": "bit_clear",
        "target_offset": block[16][0],
        "predicate": {
            "kind": "condition",
            "producer_offset": block[1][0],
            "operation": "test_bit",
            "bytes": outer["bytes"],
            "bit": outer["bit"],
            "source": flag,
        },
        "taken": {
            "kind": "constant",
            "producer_offset": block[18][0],
            "value": constant_base,
        },
        "fallthrough": dynamic,
    }


def trace_g17_cl_mode_bit_merge(
    instructions: list[tuple[int, int]],
    use_index: int,
    register: int,
    depth: int,
    seen: frozenset[tuple[int, int]],
) -> dict[str, object] | None:
    """Recover CL's mode-selected descriptor, counter, or random low bit."""

    definition_index = next(
        (
            index
            for index in range(use_index - 1, -1, -1)
            if g17_register_is_written(instructions[index][1], register)
        ),
        None,
    )
    if definition_index is None or definition_index < 32:
        return None
    mode_index = definition_index - 32
    block = instructions[mode_index : definition_index + 2]
    if len(block) != 34:
        return None
    join = block[33][0]

    def compare_immediate(relative: int, immediate: int) -> bool:
        decoded = decode_add_sub_immediate_value(block[relative][1])
        return bool(
            decoded is not None
            and decoded["operation"] == "sub"
            and decoded["destination_register"] == 31
            and decoded["source_register"] == register
            and decoded["immediate"] == immediate
            and decoded["bytes"] == 4
            and block[relative][1] & (1 << 29)
        )

    if not compare_immediate(1, 2) or not compare_immediate(3, 1):
        return None
    if decode_conditional_branch(*block[2]) != (block[18][0], "eq"):
        return None
    if decode_conditional_branch(*block[4]) != (block[12][0], "eq"):
        return None
    default_branch = decode_compare_zero_branch(*block[5])
    if (
        default_branch is None
        or default_branch["condition"] != "nonzero"
        or default_branch["register"] != register
        or default_branch["target"] != block[23][0]
    ):
        return None
    for relative, target in ((11, join), (17, block[25][0]), (22, join), (23, join), (31, join)):
        if decode_b_target(*block[relative]) != target:
            return None

    flag_zero = decode_test_bit_branch(*block[7])
    flag_one = decode_test_bit_branch(*block[13])
    if (
        flag_zero is None
        or flag_zero["target"] != block[32][0]
        or flag_one is None
        or flag_one["target"] != block[24][0]
    ):
        return None
    random_mask = decode_logical_immediate_w(block[19][1])
    counter_load = decode_integer_load_unsigned(block[26][1])
    counter_increment = decode_add_sub_immediate_value(block[27][1])
    counter_store = decode_str_unsigned(block[28][1])
    counter_add = decode_add_sub_register_value(block[29][1])
    counter_mask = decode_logical_immediate_w(block[30][1])
    if (
        block[18][0] != G17_CL_RANDOM_CALL_OFFSET
        or block[18][1] != G17_CL_RANDOM_CALL_WORD
        or random_mask != ("and", register, 0, 1)
        or counter_load is None
        or counter_increment is None
        or counter_increment["operation"] != "add"
        or counter_increment["source_register"] != counter_load[0]
        or counter_increment["immediate"] != 1
        or counter_increment["bytes"] != 4
        or counter_store is None
        or counter_store[0] != counter_increment["destination_register"]
        or counter_store[1:] != counter_load[1:]
        or counter_add is None
        or counter_add["operation"] != "add"
        or counter_add["destination_register"] != register
        or counter_add["first_register"] != register
        or counter_add["second_register"] != counter_load[0]
        or counter_add["amount"] != 0
        or counter_mask != ("and", register, register, 1)
    ):
        return None

    def load_value(relative: int) -> dict[str, object] | None:
        load = decode_integer_load_unsigned(block[relative][1])
        if load is None or load[0] == 31:
            return None
        destination, base, member, width = load
        if base == 19:
            return {
                "kind": "descriptor_load",
                "producer_offset": block[relative][0],
                "member": member,
                "bytes": width,
                "signed": False,
            }
        base_value = trace_g17_value_expression(
            instructions,
            mode_index + relative,
            base,
            depth + 1,
            seen,
        )
        if base_value is None:
            return None
        return {
            "kind": "object_load",
            "producer_offset": block[relative][0],
            "member": member,
            "bytes": width,
            "signed": False,
            "base": base_value,
        }

    selector = load_value(0)
    zero_flag = load_value(6)
    zero_fallthrough = trace_g17_value_expression(
        instructions, mode_index + 11, register, depth + 1, seen
    )
    zero_taken = load_value(32)
    one_flag = load_value(12)
    one_fallthrough = trace_g17_value_expression(
        instructions, mode_index + 17, register, depth + 1, seen
    )
    one_taken = load_value(24)
    random_value = trace_g17_value_expression(
        instructions, mode_index + 20, register, depth + 1, seen
    )
    counter_register = int(counter_add["second_register"])
    counter = load_value(26)
    values = (
        selector,
        zero_flag,
        zero_fallthrough,
        zero_taken,
        one_flag,
        one_fallthrough,
        one_taken,
        random_value,
        counter,
    )
    if any(value is None for value in values) or counter_register == 31:
        return None

    def test_bit_predicate(
        relative: int, decoded: dict[str, object], source: dict[str, object]
    ) -> dict[str, object]:
        return {
            "kind": "condition",
            "producer_offset": block[relative][0],
            "operation": "test_bit",
            "bytes": decoded["bytes"],
            "bit": decoded["bit"],
            "source": source,
        }

    mode_zero = {
        "kind": "expression",
        "producer_offset": block[7][0],
        "operation": "branch_select",
        "condition": flag_zero["condition"],
        "target_offset": block[32][0],
        "predicate": test_bit_predicate(7, flag_zero, zero_flag),
        "taken": zero_taken,
        "fallthrough": zero_fallthrough,
    }
    mode_one_selected = {
        "kind": "expression",
        "producer_offset": block[13][0],
        "operation": "branch_select",
        "condition": flag_one["condition"],
        "target_offset": block[24][0],
        "predicate": test_bit_predicate(13, flag_one, one_flag),
        "taken": one_taken,
        "fallthrough": one_fallthrough,
    }
    mode_one = {
        "kind": "expression",
        "producer_offset": block[30][0],
        "operation": "and",
        "bytes": 4,
        "immediate": 1,
        "source": {
            "kind": "expression",
            "producer_offset": block[29][0],
            "operation": "add",
            "bytes": 4,
            "modifier": counter_add.get("extend", counter_add.get("shift")),
            "amount": counter_add["amount"],
            "first": mode_one_selected,
            "second": {
                **counter,
                "update": "postincrement",
                "update_offset": block[28][0],
            },
        },
    }
    return {
        "kind": "expression",
        "producer_offset": block[1][0],
        "operation": "multiway_select",
        "selector": selector,
        "cases": [
            {"equals": 2, "value": random_value},
            {"equals": 1, "value": mode_one},
            {"equals": 0, "value": mode_zero},
        ],
        "default": selector,
        "join_offset": join,
    }


def trace_g17_control_flow_merge(
    instructions: list[tuple[int, int]],
    use_index: int,
    register: int,
    depth: int,
    seen: frozenset[tuple[int, int]],
) -> dict[str, object] | None:
    """Recover one forward conditional edge around the last definition."""

    definition_index = next(
        (
            index
            for index in range(use_index - 1, -1, -1)
            if g17_register_is_written(instructions[index][1], register)
        ),
        None,
    )
    if definition_index is None:
        return None
    definition_offset = instructions[definition_index][0]
    use_offset = (
        instructions[use_index][0]
        if use_index < len(instructions)
        else instructions[-1][0] + 4
    )
    candidates: list[dict[str, object]] = []
    for branch_index, (branch_offset, branch_word) in enumerate(
        instructions[:definition_index]
    ):
        decoded = decode_conditional_branch(branch_offset, branch_word)
        test_bit = decode_test_bit_branch(branch_offset, branch_word)
        compare_zero = decode_compare_zero_branch(branch_offset, branch_word)
        if decoded is not None:
            target, condition = decoded
            branch: dict[str, object] = {
                "index": branch_index,
                "offset": branch_offset,
                "target": target,
                "condition": condition,
                "kind": "flags",
            }
        elif test_bit is not None:
            branch = {
                "index": branch_index,
                "offset": branch_offset,
                **test_bit,
                "kind": "test_bit",
            }
            target = int(test_bit["target"])
        elif compare_zero is not None:
            branch = {
                "index": branch_index,
                "offset": branch_offset,
                **compare_zero,
                "kind": "compare_zero",
            }
            target = int(compare_zero["target"])
        else:
            continue

        if definition_offset < target <= use_offset:
            branch["shape"] = "skip"
            candidates.append(branch)
            continue
        target_index = next(
            (
                index
                for index, (offset, _word) in enumerate(instructions)
                if offset == target
            ),
            None,
        )
        if target_index is None or target_index > definition_index:
            continue
        bridges = [
            (index, bridge_target)
            for index, (offset, word) in enumerate(
                instructions[branch_index + 1 : target_index], branch_index + 1
            )
            for bridge_target in (decode_b_target(offset, word),)
            if bridge_target is not None
            and definition_offset < bridge_target <= use_offset
        ]
        if len(bridges) == 1:
            bridge_index, join = bridges[0]
            branch.update(
                {
                    "shape": "diamond",
                    "target_index": target_index,
                    "bridge_index": bridge_index,
                    "join": join,
                }
            )
            candidates.append(branch)

    if len(candidates) != 1:
        return None
    branch = candidates[0]
    branch_index = int(branch["index"])
    branch_offset = int(branch["offset"])
    target = int(branch["target"])
    condition = str(branch["condition"])

    if branch["kind"] == "flags":
        predicate = trace_g17_condition_expression(
            instructions, branch_index, depth + 1, seen
        )
    elif branch["kind"] == "test_bit":
        predicate_source = trace_g17_value_expression(
            instructions,
            branch_index,
            int(branch["register"]),
            depth + 1,
            seen,
        )
        predicate = (
            None
            if predicate_source is None
            else {
                "kind": "condition",
                "producer_offset": branch_offset,
                "operation": "test_bit",
                "bytes": branch["bytes"],
                "bit": branch["bit"],
                "source": predicate_source,
            }
        )
    else:
        predicate_source = trace_g17_value_expression(
            instructions,
            branch_index,
            int(branch["register"]),
            depth + 1,
            seen,
        )
        predicate = (
            None
            if predicate_source is None
            else {
                "kind": "condition",
                "producer_offset": branch_offset,
                "operation": "compare_zero",
                "bytes": branch["bytes"],
                "source": predicate_source,
            }
        )
    if predicate is None:
        return None

    if branch["shape"] == "skip":
        taken = trace_g17_value_expression(
            instructions, branch_index, register, depth + 1, seen
        )
        fallthrough_instructions = list(instructions)
        fallthrough_instructions[branch_index] = (branch_offset, 0xD503201F)
    else:
        target_index = int(branch["target_index"])
        join = int(branch["join"])
        join_index = next(
            (
                index
                for index, (offset, _word) in enumerate(instructions)
                if offset == join
            ),
            None,
        )
        if join_index is None:
            return None
        taken_instructions = list(instructions)
        for index in range(branch_index, target_index):
            offset, _word = taken_instructions[index]
            taken_instructions[index] = (offset, 0xD503201F)
        taken = trace_g17_value_expression(
            taken_instructions, use_index, register, depth + 1, seen
        )
        fallthrough_instructions = list(instructions)
        fallthrough_instructions[branch_index] = (branch_offset, 0xD503201F)
        for index in range(target_index, join_index):
            offset, _word = fallthrough_instructions[index]
            fallthrough_instructions[index] = (offset, 0xD503201F)
    if taken is None:
        return None
    fallthrough = trace_g17_value_expression(
        fallthrough_instructions, use_index, register, depth + 1, seen
    )
    if fallthrough is None:
        return None
    return {
        "kind": "expression",
        "producer_offset": branch_offset,
        "operation": "branch_select",
        "condition": condition,
        "target_offset": target,
        "predicate": predicate,
        "taken": taken,
        "fallthrough": fallthrough,
    }


def trace_g17_value_expression(
    instructions: list[tuple[int, int]],
    use_index: int,
    register: int,
    depth: int = 0,
    seen: frozenset[tuple[int, int]] = frozenset(),
) -> dict[str, object] | None:
    """Build a conservative expression tree for one integer register value."""

    key = (use_index, register)
    if depth > G17_VALUE_EXPRESSION_MAX_DEPTH or key in seen:
        return None
    if register == 0:
        known_call = trace_g17_known_call_return(
            instructions, use_index, depth, seen
        )
        if known_call is not None:
            return known_call
    definition_index = find_dominating_g17_register_write(
        instructions, use_index, register
    )
    if definition_index is None:
        merge = trace_g17_four_way_compare_merge(
            instructions, use_index, register, depth, seen
        )
        if merge is None:
            merge = trace_g17_optional_bit_set_merge(
                instructions, use_index, register, depth, seen
            )
        if merge is None:
            merge = trace_g17_cl_base_merge(
                instructions, use_index, register, depth, seen
            )
        if merge is None:
            merge = trace_g17_cl_mode_bit_merge(
                instructions, use_index, register, depth, seen
            )
        if merge is None:
            merge = trace_g17_control_flow_merge(
                instructions, use_index, register, depth, seen
            )
        if merge is not None:
            return merge
        if (
            0 <= register <= 7
            and not any(
                g17_register_is_written(word, register)
                for _offset, word in instructions[:use_index]
            )
            and not any(
                decode_bl_target(offset, word) is not None
                or word & 0xFFFFFC00 == 0xD73F0800
                for offset, word in instructions[:use_index]
            )
        ):
            names = ("channel", "command", "descriptor")
            return {
                "kind": "argument",
                "register": register,
                "name": names[register] if register < len(names) else "unknown",
            }
        return None
    offset, word = instructions[definition_index]
    next_seen = seen | {key}

    load = decode_integer_load_unsigned(word)
    if load is not None and load[0] == register:
        _destination, base, member, width = load
        if base == 19:
            return {
                "kind": "descriptor_load",
                "producer_offset": offset,
                "member": member,
                "bytes": width,
                "signed": False,
            }
        if base == 31:
            return trace_g17_stack_load(
                instructions,
                definition_index,
                member,
                width,
                depth,
                next_seen,
            )
        base_value = trace_g17_value_expression(
            instructions, definition_index, base, depth + 1, next_seen
        )
        if base_value is None:
            return None
        return {
            "kind": "object_load",
            "producer_offset": offset,
            "member": member,
            "bytes": width,
            "signed": False,
            "base": base_value,
        }
    pair = decode_ldp_x(word)
    if pair is not None and register in pair[:2]:
        first, _second, base, member = pair
        member += 8 if register != first else 0
        if base == 19:
            return {
                "kind": "descriptor_load",
                "producer_offset": offset,
                "member": member,
                "bytes": 8,
                "signed": False,
            }
        if base == 31:
            return trace_g17_stack_load(
                instructions,
                definition_index,
                member,
                8,
                depth,
                next_seen,
            )
        base_value = trace_g17_value_expression(
            instructions, definition_index, base, depth + 1, next_seen
        )
        if base_value is None:
            return None
        return {
            "kind": "object_load",
            "producer_offset": offset,
            "member": member,
            "bytes": 8,
            "signed": False,
            "base": base_value,
        }
    if word & 0xFFC0001F == 0xB9800000 | register:
        base = (word >> 5) & 0x1F
        if base == 19:
            return {
                "kind": "descriptor_load",
                "producer_offset": offset,
                "member": ((word >> 10) & 0xFFF) * 4,
                "bytes": 4,
                "signed": True,
            }
        if base != 31:
            base_value = trace_g17_value_expression(
                instructions, definition_index, base, depth + 1, next_seen
            )
            if base_value is not None:
                return {
                    "kind": "object_load",
                    "producer_offset": offset,
                    "member": ((word >> 10) & 0xFFF) * 4,
                    "bytes": 4,
                    "signed": True,
                    "base": base_value,
                }

    pc_relative = decode_adrp(offset, word)
    if pc_relative is not None and pc_relative[0] == register:
        return {
            "kind": "pc_relative_page",
            "producer_offset": offset,
            "page_delta": pc_relative[1] - (offset & ~0xFFF),
        }

    wide = decode_move_wide(word)
    update_w = decode_movk_w(word)
    if (
        wide is not None
        or decode_movn_w(word) is not None
        or decode_movz_w(word) is not None
        or update_w is not None
    ):
        value = resolve_static_x_register(instructions, use_index, register)
        if value is not None:
            return {
                "kind": "constant",
                "producer_offset": offset,
                "value": value,
            }
        update = (
            (wide[2], wide[3], 8)
            if wide is not None and wide[0] == "movk"
            else (update_w[1], update_w[2], 4)
            if update_w is not None
            else None
        )
        if update is not None:
            immediate, shift, width = update
            source_value = trace_g17_value_expression(
                instructions,
                definition_index,
                register,
                depth + 1,
                next_seen,
            )
            if source_value is not None:
                return {
                    "kind": "expression",
                    "producer_offset": offset,
                    "operation": "movk",
                    "bytes": width,
                    "immediate": immediate,
                    "shift": shift,
                    "source": source_value,
                }

    copy = decode_register_copy(word)
    if copy is not None and copy[0] == register:
        _destination, source, width = copy
        if source == 31:
            return {"kind": "constant", "producer_offset": offset, "value": 0}
        source_value = trace_g17_value_expression(
            instructions, definition_index, source, depth + 1, next_seen
        )
        if source_value is None:
            return None
        return {
            "kind": "expression",
            "producer_offset": offset,
            "operation": "copy",
            "bytes": width,
            "source": source_value,
        }

    immediate = decode_logical_immediate_x(word)
    width = 8
    if immediate is None:
        immediate = decode_logical_immediate_w(word)
        width = 4
    if immediate is not None and immediate[1] == register:
        operation, _destination, source, value = immediate
        source_value = (
            {"kind": "constant", "value": 0}
            if source == 31
            else trace_g17_value_expression(
                instructions, definition_index, source, depth + 1, next_seen
            )
        )
        if source_value is None:
            return None
        return {
            "kind": "expression",
            "producer_offset": offset,
            "operation": operation,
            "bytes": width,
            "immediate": value,
            "source": source_value,
        }

    logical = decode_logical_shifted_register(word)
    if logical is not None and logical["destination_register"] == register:
        operands = []
        for source in (logical["first_register"], logical["second_register"]):
            source_value = (
                {"kind": "constant", "value": 0}
                if source == 31
                else trace_g17_value_expression(
                    instructions, definition_index, int(source), depth + 1, next_seen
                )
            )
            if source_value is None:
                return None
            operands.append(source_value)
        return {
            "kind": "expression",
            "producer_offset": offset,
            "operation": logical["operation"],
            "bytes": logical["bytes"],
            "shift": logical["shift"],
            "amount": logical["amount"],
            "first": operands[0],
            "second": operands[1],
        }

    arithmetic = decode_add_sub_immediate_value(word)
    if arithmetic is not None and arithmetic["destination_register"] == register:
        source = int(arithmetic["source_register"])
        if source == 31:
            return None  # SP is not a value root for register entries.
        source_value = trace_g17_value_expression(
            instructions, definition_index, source, depth + 1, next_seen
        )
        if source_value is None:
            return None
        return {
            "kind": "expression",
            "producer_offset": offset,
            "operation": arithmetic["operation"],
            "bytes": arithmetic["bytes"],
            "immediate": arithmetic["immediate"],
            "source": source_value,
        }

    arithmetic_register = decode_add_sub_register_value(word)
    if (
        arithmetic_register is not None
        and arithmetic_register["destination_register"] == register
    ):
        operands = []
        for source in (
            arithmetic_register["first_register"],
            arithmetic_register["second_register"],
        ):
            if source == 31:
                return None
            source_value = trace_g17_value_expression(
                instructions, definition_index, int(source), depth + 1, next_seen
            )
            if source_value is None:
                return None
            operands.append(source_value)
        return {
            "kind": "expression",
            "producer_offset": offset,
            "operation": arithmetic_register["operation"],
            "bytes": arithmetic_register["bytes"],
            "modifier": arithmetic_register.get(
                "extend", arithmetic_register.get("shift")
            ),
            "amount": arithmetic_register["amount"],
            "first": operands[0],
            "second": operands[1],
        }

    bitfield = decode_bitfield_value(word)
    if bitfield is not None and bitfield["destination_register"] == register:
        source = int(bitfield["source_register"])
        source_value = (
            {"kind": "constant", "value": 0}
            if source == 31
            else trace_g17_value_expression(
                instructions, definition_index, source, depth + 1, next_seen
            )
        )
        if source_value is None:
            return None
        result = {
            "kind": "expression",
            "producer_offset": offset,
            "operation": bitfield["operation"],
            "bytes": bitfield["bytes"],
            "rotate": bitfield["rotate"],
            "mask_end": bitfield["mask_end"],
            "source": source_value,
        }
        if bitfield["operation"] == "bfm":
            destination_value = trace_g17_value_expression(
                instructions,
                definition_index,
                register,
                depth + 1,
                next_seen,
            )
            if destination_value is None:
                return None
            result["destination"] = destination_value
        return result

    conditional = decode_conditional_select_value(word)
    if conditional is not None and conditional["destination_register"] == register:
        operands = []
        for source in (
            conditional["first_register"],
            conditional["second_register"],
        ):
            source_value = (
                {"kind": "constant", "value": 0}
                if source == 31
                else trace_g17_value_expression(
                    instructions, definition_index, int(source), depth + 1, next_seen
                )
            )
            if source_value is None:
                return None
            operands.append(source_value)
        condition = trace_g17_condition_expression(
            instructions, definition_index, depth + 1, next_seen
        )
        if condition is None:
            return None
        return {
            "kind": "expression",
            "producer_offset": offset,
            "operation": conditional["operation"],
            "bytes": conditional["bytes"],
            "condition": conditional["condition"],
            "predicate": condition,
            "first": operands[0],
            "second": operands[1],
        }
    return None


def classify_g17_value_argument(
    instructions: list[tuple[int, int]], before: int
) -> dict[str, object]:
    """Classify the last x4/w4 writer before one register encoder call."""

    classes = {
        0x0A000000: "logical_register",
        0x0B000000: "add_sub_register",
        0x11000000: "add_sub_immediate",
        0x12000000: "logical_immediate",
        0x13000000: "bitfield",
        0x1A000000: "conditional",
        0x1B000000: "multiply",
    }
    start = max(0, before - VALUE_ARGUMENT_WINDOW)
    for index in range(before - 1, start - 1, -1):
        offset, word = instructions[index]
        load = decode_integer_load_unsigned(word)
        if load is not None and load[0] == 4:
            _destination, base, member, width = load
            return {
                "kind": "descriptor_load" if base == 19 else "indirect_load",
                "producer_offset": offset,
                "base_register": base,
                "member": member,
                "bytes": width,
                "signed": False,
            }
        if word & 0xFFC0001F == 0xB9800004:  # LDRSW x4, [xn, #imm]
            base = (word >> 5) & 0x1F
            member = ((word >> 10) & 0xFFF) * 4
            return {
                "kind": "descriptor_load" if base == 19 else "indirect_load",
                "producer_offset": offset,
                "base_register": base,
                "member": member,
                "bytes": 4,
                "signed": True,
            }

        move_w = decode_movz_w(word)
        move_n_w = decode_movn_w(word)
        update_w = decode_movk_w(word)
        wide = decode_move_wide(word)
        if (
            move_w is not None and move_w[0] == 4
            or move_n_w is not None and move_n_w[0] == 4
            or update_w is not None and update_w[0] == 4
            or wide is not None and wide[1] == 4
        ):
            value = resolve_static_x_register(instructions, before, 4)
            if value is None:
                raise ValueError(
                    f"G17 value at producer +{offset:#x} is no longer constant"
                )
            return {
                "kind": "constant",
                "producer_offset": offset,
                "value": value,
            }

        copy = decode_register_copy(word)
        if copy is not None and copy[0] == 4:
            _destination, source, width = copy
            traced = trace_g17_register_copy(instructions, index, source)
            if traced is not None:
                return traced
            result: dict[str, object] = {
                "kind": "computed",
                "producer_offset": offset,
                "operation": "register_copy",
                "source_register": source,
                "bytes": width,
                "instruction": word,
            }
            expression = trace_g17_value_expression(instructions, before, 4)
            if expression is not None:
                result["expression"] = expression
            return result

        instruction_class = word & 0x1F000000
        if word & 0x1F == 4 and instruction_class in classes:
            result: dict[str, object] = {
                "kind": "computed",
                "producer_offset": offset,
                "operation": classes[instruction_class],
                "instruction": word,
            }
            expression = trace_g17_value_expression(instructions, before, 4)
            if expression is not None:
                result["expression"] = expression
            return result
    raise ValueError("G17 register-entry value has no nearby x4 writer")


def decode_umaddl(word: int) -> tuple[int, int, int, int] | None:
    if word & 0xFFE08000 != 0x9BA00000:
        return None
    destination = word & 0x1F
    first = (word >> 5) & 0x1F
    addend = (word >> 10) & 0x1F
    second = (word >> 16) & 0x1F
    return destination, first, second, addend


def decode_bfi_x(word: int) -> tuple[int, int, int, int] | None:
    """Decode the 64-bit BFI alias of BFM."""
    if word & 0xFFC00000 != 0xB3400000:
        return None
    destination = word & 0x1F
    source = (word >> 5) & 0x1F
    immr = (word >> 16) & 0x3F
    imms = (word >> 10) & 0x3F
    if imms >= immr:
        return None
    lsb = (-immr) & 0x3F
    width = imms + 1
    return destination, source, lsb, width


def decode_ubfiz_x(word: int) -> tuple[int, int, int, int] | None:
    """Decode the 64-bit UBFIZ alias, including the LSL immediate alias."""
    if word & 0xFFC00000 != 0xD3400000:
        return None
    destination = word & 0x1F
    source = (word >> 5) & 0x1F
    immr = (word >> 16) & 0x3F
    imms = (word >> 10) & 0x3F
    if imms >= immr:
        return None
    lsb = (-immr) & 0x3F
    width = imms + 1
    return destination, source, lsb, width


def decode_str_unsigned(word: int) -> tuple[int, int, int, int] | None:
    kinds = {
        0x39000000: 1,
        0x79000000: 2,
        0xB9000000: 4,
        0xF9000000: 8,
        0xBD000000: 4,
        0xFD000000: 8,
        0x3D800000: 16,
    }
    width = kinds.get(word & 0xFFC00000)
    if width is None:
        return None
    source = word & 0x1F
    base = (word >> 5) & 0x1F
    immediate = ((word >> 10) & 0xFFF) * width
    return source, base, immediate, width


def decode_stur_x(word: int) -> tuple[int, int, int] | None:
    if word & 0xFFE00C00 != 0xF8000000:
        return None
    source = word & 0x1F
    base = (word >> 5) & 0x1F
    immediate = (word >> 12) & 0x1FF
    if immediate & 0x100:
        immediate -= 0x200
    return source, base, immediate


def decode_pair_q(word: int) -> tuple[str, int, int, int, int] | None:
    opcode = word & 0xFFC00000
    if opcode == 0xAD400000:
        kind = "load"
    elif opcode == 0xAD000000:
        kind = "store"
    else:
        return None
    first = word & 0x1F
    base = (word >> 5) & 0x1F
    second = (word >> 10) & 0x1F
    immediate = (word >> 15) & 0x7F
    if immediate & 0x40:
        immediate -= 0x80
    return kind, first, second, base, immediate * 16


def decode_adrp(address: int, word: int) -> tuple[int, int] | None:
    if word & 0x9F000000 != 0x90000000:
        return None
    register = word & 0x1F
    immediate = ((word >> 5) & 0x7FFFF) << 2 | ((word >> 29) & 0x3)
    if immediate & (1 << 20):
        immediate -= 1 << 21
    target = (address & ~0xFFF) + (immediate << 12)
    return register, target & 0xFFFFFFFFFFFFFFFF


def decode_bl_target(address: int, word: int) -> int | None:
    if word & 0xFC000000 != 0x94000000:
        return None
    immediate = word & 0x03FFFFFF
    if immediate & (1 << 25):
        immediate -= 1 << 26
    return (address + immediate * 4) & 0xFFFFFFFFFFFFFFFF


def decode_b_target(address: int, word: int) -> int | None:
    if word & 0xFC000000 != 0x14000000:
        return None
    immediate = word & 0x03FFFFFF
    if immediate & (1 << 25):
        immediate -= 1 << 26
    return (address + immediate * 4) & 0xFFFFFFFFFFFFFFFF


def decode_stp_x(word: int) -> tuple[int, int, int, int] | None:
    if word & 0xFFC00000 != 0xA9000000:
        return None
    first = word & 0x1F
    base = (word >> 5) & 0x1F
    second = (word >> 10) & 0x1F
    immediate = (word >> 15) & 0x7F
    if immediate & 0x40:
        immediate -= 0x80
    return first, second, base, immediate * 8


def decode_ldr_d(word: int) -> tuple[int, int, int] | None:
    if word & 0xFFC00000 != 0xFD400000:
        return None
    destination = word & 0x1F
    base = (word >> 5) & 0x1F
    immediate = ((word >> 10) & 0xFFF) * 8
    return destination, base, immediate


def decode_str_d(word: int) -> tuple[int, int, int] | None:
    if word & 0xFFC00000 != 0xFD000000:
        return None
    source = word & 0x1F
    base = (word >> 5) & 0x1F
    immediate = ((word >> 10) & 0xFFF) * 8
    return source, base, immediate


def decode_stur_d(word: int) -> tuple[int, int, int] | None:
    if word & 0xFFE00C00 != 0xFC000000:
        return None
    source = word & 0x1F
    base = (word >> 5) & 0x1F
    immediate = (word >> 12) & 0x1FF
    if immediate & 0x100:
        immediate -= 0x200
    return source, base, immediate


def recover_firmware_root(code: bytes) -> dict[str, object]:
    magic = find_materialized_constant(code, INTERFACE_MAGIC)
    if len(magic) != 1:
        raise ValueError(f"expected one firmware interface magic sequence, found {len(magic)}")
    magic_start, magic_end, _register = magic[0]
    window = code[magic_end : magic_end + 0x100]
    additions: list[tuple[int, int, int, int]] = []
    for offset, word in words(window):
        decoded = decode_add_immediate(word)
        if decoded is not None:
            additions.append((magic_end + offset, *decoded))
    copy_base = next((item for item in additions if item[3] == 0x3A8), None)
    consume_base = next((item for item in additions if item[3] == 0x3C0), None)
    if copy_base is None or consume_base is None:
        raise ValueError("could not recover copied-root and consumer addresses")
    root_bias = consume_base[3] - copy_base[3]
    consume_register = consume_base[1]
    pair_offsets = []
    for offset, word in words(code[consume_base[0] : consume_base[0] + 0x40]):
        decoded = decode_ldp_x(word)
        if decoded is not None and decoded[2] == consume_register:
            pair_offsets.append(decoded[3])
    fields = sorted(
        root_bias + pair_offset + element
        for pair_offset in pair_offsets
        for element in (0, 8)
    )
    if tuple(fields) != ROOT_FIELDS:
        raise ValueError(f"unexpected firmware root pointers: {[hex(field) for field in fields]}")
    return {
        "interface_magic": INTERFACE_MAGIC,
        "magic_code_offset": magic_start,
        "copied_bytes": 0xC8,
        "pointer_offsets": fields,
    }


def recover_driver_root(code: bytes) -> dict[str, object]:
    magic = find_materialized_constant(code, INTERFACE_MAGIC)
    if len(magic) != 1:
        raise ValueError(f"expected one driver interface magic sequence, found {len(magic)}")
    magic_start, _magic_end, _register = magic[0]
    found: set[int] = set()
    for _offset, word in words(code[magic_start : magic_start + 0x500]):
        decoded = decode_str_x(word)
        if decoded is not None and decoded[2] in ROOT_FIELDS:
            found.add(decoded[2])
    if tuple(sorted(found)) != ROOT_FIELDS:
        raise ValueError(f"unexpected driver root stores: {[hex(field) for field in sorted(found)]}")

    instructions = list(words(code))
    bindings: list[tuple[int, int]] = []
    for index, (_offset, word) in enumerate(instructions):
        load = decode_ldr_x(word)
        if load is None or load[0] != 1 or load[1] != 19:
            continue
        for _following_offset, following_word in instructions[index + 1 : index + 28]:
            following_load = decode_ldr_x(following_word)
            if following_load is not None and following_load[0] == 1 and following_load[1] == 19:
                break
            store = decode_str_x(following_word)
            if store is not None and store[0] == 0 and store[2] in ROOT_FIELDS:
                bindings.append((load[2], store[2]))
                break
    expected_bindings = [
        (0xAB8, 0x18),
        (0x388, 0x20),
        (0xAD0, 0xA8),
        (0xBE8, 0x18),
        (0x388, 0x20),
        (0xC00, 0xA8),
        (0xCE0, 0xB0),
        (0xCE8, 0xB8),
        (0x398, 0xC0),
    ]
    if bindings != expected_bindings:
        raise ValueError(
            "unexpected driver root allocation bindings: "
            f"{[(hex(member), hex(offset)) for member, offset in bindings]}"
        )

    bootstrap_publication = struct.pack(
        "<32I",
        0xF94D2E60,  # ldr x0, [x19, #0x1a58]
        0xAA0003F1,
        0xF9400010,
        0xF2F9B431,
        0xDAC11A30,
        0xAA1003F1,
        0xDAC147F1,
        0xEB11021F,
        0x54000040,
        0xD4388E40,
        0x91056208,  # mapping vtable + 0x158
        0xF940AE09,
        0xAA0803F1,
        0xF2E63531,
        0xD73F0931,
        0xAA0003E1,  # mapping address becomes conversion argument
        0xAA1603F1,
        0xF9400270,
        0xDAC11A30,
        0xAA1003F1,
        0xDAC147F1,
        0xEB11021F,
        0x54000040,
        0xD4388E40,
        0x910B6208,  # firmware vtable + 0x2d8
        0xF9416E09,
        0xAA1303E0,
        0x52800002,
        0xAA0803F1,
        0xF2F24A11,
        0xD73F0931,
        0xF9000680,  # str x0, [x20, #8]
    )
    if code.count(bootstrap_publication) != 2:
        raise ValueError("driver root bootstrap mapping is not converted for both roles")

    require_instruction_sequence(
        code,
        "root platform-data copy",
        (
            0xF9414E68,  # ldr x8, [x19, #0x298]
            0x52952917,  # mov w23, #0xa948
            0x72A00037,  # movk w23, #1, lsl #16
            0x8B170108,  # add x8, x8, x23
            0xF9400108,  # ldr x8, [x8]
            0x3CC18100,
            0x3CC28101,
            0x3CC38102,
            0xAD020A81,  # first 0x30 bytes to root+0x30
            0x3D800E80,
            0x3CC48100,
            0x3CC58101,
            0x3CC68102,
            0xF9403D08,
            0xF9004A88,  # final qword at root+0x90
            0xAD038A81,
            0x3D801A80,  # vector data through root+0x8f
        ),
    )
    if code.count(struct.pack("<I", 0xFD001680)) != 2:  # str d0, [x20, #0x28]
        raise ValueError("driver root role/host-mapping words were not both written")
    if struct.pack("<I", 0x0F000420) not in code:  # movi v0.2s, #1
        raise ValueError("driver secondary root role word was not found")

    return {
        "interface_magic": INTERFACE_MAGIC,
        "magic_code_offset": magic_start,
        "pointer_offsets": sorted(found),
        "firmware_role_offset": 0x28,
        "host_mapped_allocations_offset": 0x2C,
        "bootstrap_provider_host_member": 0x1A58,
        "bootstrap_region": {
            "root_offset": 8,
            "host_cpu_member": 0x1A50,
            "host_gpu_mapping_member": 0x1A58,
            "mapping_address_vtable_offset": 0x158,
            "firmware_address_conversion_vtable_offset": 0x2D8,
        },
        "platform_config": {
            "host_platform_member": 0x298,
            "host_platform_pointer_offset": 0x1A948,
            "root_offset": 0x30,
            "bytes": 0x68,
        },
        "roles": [
            {
                "role": 0,
                "bindings": [
                    {"host_gpu_member": member, "root_offset": offset}
                    for member, offset in expected_bindings[:3] + expected_bindings[6:7]
                ],
            },
            {
                "role": 1,
                "bindings": [
                    {"host_gpu_member": member, "root_offset": offset}
                    for member, offset in expected_bindings[3:6] + expected_bindings[7:]
                ],
            },
        ],
    }


def recover_g17_bootstrap_roots(
    allocation_code: bytes,
    init_code: bytes,
    prepare_code: bytes,
    complete_code: bytes,
    page_shift_code: bytes,
) -> dict[str, object]:
    expected_page_shift = struct.pack(
        "<3I", 0xD503245F, 0x528001C0, 0xD65F03C0
    )
    if page_shift_code != expected_page_shift:
        raise ValueError("G17 bootstrap roots do not use the checked 14-bit page shift")

    # Each root's requested size is one firmware page rounded up to the host
    # kernel page, with the host page also supplied as the allocation alignment.
    size_calculation_tail = (
        0x1AC82308,  # host page bytes
        0x1AC02329,  # -firmware page bytes
        0x4B0803EA,
        0x4B080129,
        0x0A290141,  # rounded allocation bytes in w1
        0x93407D02,  # host page alignment in x2
        0x52800260,  # I/O memory allocation options 0x13
    )
    first_size_calculation = struct.pack(
        "<10I",
        0xB94002E8,  # load host kernel page shift
        0x52800038,  # initialize one in w24
        size_calculation_tail[0],
        0x12800019,  # initialize -1 in w25
        *size_calculation_tail[1:],
    )
    repeated_size_calculation = struct.pack(
        "<8I", 0xB94002E8, *size_calculation_tail
    )
    if (
        allocation_code.count(first_size_calculation) != 1
        or allocation_code.count(repeated_size_calculation) != 1
    ):
        raise ValueError("expected two G17 bootstrap-root size calculations")

    roles = (
        (0, 0x19E0, 0x19E8),
        (1, 0x1A18, 0x1A20),
    )
    allocation_words = [word for _offset, word in words(allocation_code)]
    init_words = [word for _offset, word in words(init_code)]

    def require_root_allocation(cpu_member: int, gpu_member: int) -> None:
        cpu_store = 0xF9000000 | (cpu_member // 8) << 10 | 19 << 5
        gpu_store = 0xF9000000 | (gpu_member // 8) << 10 | 19 << 5
        candidates = [
            index for index, word in enumerate(allocation_words) if word == cpu_store
        ]
        if len(candidates) != 1:
            raise ValueError(
                f"unexpected root CPU mapping stores for host member {cpu_member:#x}"
            )
        index = candidates[0]
        cpu_mapping = (
            0xD2804511,  # descriptor vtable + 0x228
            0x8B110210,
            0xF9400208,
            0x52800001,  # mapping options 0
            0xF2E7DAD0,
            0xD73F0910,
            cpu_store,
        )
        encoded_cpu_mapping = struct.pack(f"<{len(cpu_mapping)}I", *cpu_mapping)
        if encoded_cpu_mapping not in allocation_code:
            raise ValueError(
                f"missing root CPU mapping at host member {cpu_member:#x}"
            )
        expected_tail = (
            0xAA1303E0,  # this
            0xAA1403E1,  # memory descriptor
            0x52800002,  # not read-only
            0x52800103,  # firmware GART range 8
        )
        if tuple(allocation_words[index + 2 : index + 6]) != expected_tail:
            raise ValueError(
                f"unexpected root GPU mapping arguments for host member {gpu_member:#x}"
            )
        if allocation_words[index + 6] & 0xFC000000 != 0x94000000:
            raise ValueError("root GPU mapping is not made by a direct call")
        if allocation_words[index + 7] != gpu_store:
            raise ValueError(
                f"missing root GPU mapping at host member {gpu_member:#x}"
            )

        cpu_load = 0xF9400000 | (cpu_member // 8) << 10 | 19 << 5
        for load_index, word in enumerate(init_words):
            if word != cpu_load:
                continue
            window = init_words[load_index + 1 : load_index + 16]
            if 0x9104E208 in window and 0xF9409E09 in window:
                break
        else:
            raise ValueError(
                f"root CPU address accessor was not used for host member {cpu_member:#x}"
            )

    def require_mapping_lifecycle(code: bytes, member: int, operation: str) -> None:
        instruction_words = [word for _offset, word in words(code)]
        expected_load = 0xF9400000 | (member // 8) << 10 | 19 << 5
        for index, word in enumerate(instruction_words[:-1]):
            if word == expected_load and instruction_words[index + 1] & 0xFC000000 == 0x94000000:
                return
        raise ValueError(
            f"root GPU mapping at host member {member:#x} is not {operation}"
        )

    recovered_roles = []
    for role, cpu_member, gpu_member in roles:
        require_root_allocation(cpu_member, gpu_member)
        require_mapping_lifecycle(prepare_code, gpu_member, "prepared")
        require_mapping_lifecycle(complete_code, gpu_member, "completed")
        recovered_roles.append(
            {
                "role": role,
                "host_cpu_mapping_member": cpu_member,
                "host_gpu_mapping_member": gpu_member,
            }
        )

    return {
        "bytes": 0x4000,
        "firmware_page_shift": 14,
        "host_page_aligned": True,
        "memory_options": 0x13,
        "cpu_mapping_vtable_offset": 0x228,
        "cpu_address_vtable_offset": 0x138,
        "firmware_gart_range": 8,
        "prepared_by": PREPARE_FIRMWARE_DATA,
        "completed_by": COMPLETE_FIRMWARE_DATA,
        "roles": recovered_roles,
    }


def recover_firmware_allocations(image: bytes, address: int, code: bytes) -> list[dict[str, int]]:
    registers: dict[int, tuple[str, int]] = {19: ("this", 0)}
    vectors: dict[int, int] = {}
    stack: dict[int, tuple[str, int] | int] = {}
    frame: dict[int, tuple[str, int] | int] = {}
    allocations: set[tuple[int, int, int]] = set()

    def collect(storage: dict[int, tuple[str, int] | int], size_offset: int) -> None:
        cpu = storage.get(size_offset - 16)
        gpu = storage.get(size_offset - 8)
        size = storage.get(size_offset)
        if (
            isinstance(cpu, tuple)
            and cpu[0] == "this"
            and isinstance(gpu, tuple)
            and gpu[0] == "this"
            and isinstance(size, int)
        ):
            allocations.add((cpu[1], gpu[1], size))

    for offset, word in words(code):
        pc = address + offset
        page = decode_adrp(pc, word)
        if page is not None:
            registers[page[0]] = ("absolute", page[1])
            continue
        addition = decode_add_immediate(word)
        if addition is not None:
            destination, source, immediate = addition
            if source in registers:
                kind, value = registers[source]
                registers[destination] = (kind, value + immediate)
            continue
        load_d = decode_ldr_d(word)
        if load_d is not None:
            destination, base, immediate = load_d
            if base in registers and registers[base][0] == "absolute":
                location = registers[base][1] + immediate
                file_offset = virtual_to_file(image, location)
                vectors[destination] = struct.unpack_from("<Q", image, file_offset)[0]
            continue
        pair = decode_stp_x(word)
        if pair is not None and pair[2] in (29, 31):
            first, second, _base, stack_offset = pair
            storage = frame if pair[2] == 29 else stack
            if first in registers:
                storage[stack_offset] = registers[first]
            if second in registers:
                storage[stack_offset + 8] = registers[second]
            continue
        store_x = decode_str_x(word)
        if store_x is not None and store_x[1] == 31 and store_x[0] in registers:
            stack[store_x[2]] = registers[store_x[0]]
            continue
        store_d = decode_str_d(word)
        if store_d is not None and store_d[1] == 31 and store_d[0] in vectors:
            stack[store_d[2]] = vectors[store_d[0]]
            collect(stack, store_d[2])
            continue
        store_unscaled_d = decode_stur_d(word)
        if (
            store_unscaled_d is not None
            and store_unscaled_d[1] == 29
            and store_unscaled_d[0] in vectors
        ):
            frame[store_unscaled_d[2]] = vectors[store_unscaled_d[0]]
            collect(frame, store_unscaled_d[2])

    return [
        {"host_cpu_member": cpu, "host_gpu_member": gpu, "bytes": size}
        for cpu, gpu, size in sorted(allocations)
    ]


def recover_root_allocation_sizes(allocations: list[dict[str, int]]) -> dict[str, int]:
    by_gpu_member = {item["host_gpu_member"]: item["bytes"] for item in allocations}
    expected = {
        "firmware_shared_data": (0xAB8, 0x4C0),
        "secondary_firmware_shared_data": (0xBE8, 0x4C0),
        "runtime_data": (0x388, 0x1CA0),
        "small_shared_data": (0xAD0, 0x20),
        "secondary_small_shared_data": (0xC00, 0x20),
        "primary_region": (0xCE0, 0xE440),
        "secondary_region": (0xCE8, 0x6F0),
        "secondary_aux": (0x398, 0xA8),
    }
    result = {}
    for name, (member, expected_size) in expected.items():
        size = by_gpu_member.get(member)
        if size != expected_size:
            raise ValueError(
                f"unexpected {name} allocation through host member {member:#x}: {size}"
            )
        result[name] = size
    return result


def recover_hardware_config(
    allocations: list[dict[str, int]], shared_code: bytes, firmware: bytes
) -> dict[str, object]:
    expected_cpu_member = 0x2B8
    expected_gpu_member = 0x300
    expected_size = 0x2710
    size = next(
        (
            item["bytes"]
            for item in allocations
            if item["host_cpu_member"] == expected_cpu_member
            and item["host_gpu_member"] == expected_gpu_member
        ),
        None,
    )
    if size != expected_size:
        raise ValueError(f"unexpected hardware config allocation size: {size}")

    instructions = list(words(shared_code))
    published: set[int] = set()
    for index, (_offset, word) in enumerate(instructions):
        source = decode_ldr_x(word)
        if source != (1, 19, expected_gpu_member):
            continue
        for following_index in range(index + 1, min(index + 24, len(instructions))):
            load = decode_ldr_x(instructions[following_index][1])
            if load is None or load[0] != 8 or load[1] != 19:
                continue
            shared_cpu_member = load[2]
            for _store_offset, store_word in instructions[
                following_index + 1 : following_index + 18
            ]:
                store = decode_str_x(store_word)
                if store == (0, 8, 0):
                    published.add(shared_cpu_member)
                    break
    if published != {0xA98, 0xBC8}:
        raise ValueError(
            "hardware config address was not published to both firmware roles: "
            f"{[hex(member) for member in sorted(published)]}"
        )

    reads = recover_firmware_config_reads(firmware)
    return {
        "bytes": expected_size,
        "host_cpu_member": expected_cpu_member,
        "host_gpu_member": expected_gpu_member,
        "firmware_shared_offset": 0,
        "published_shared_cpu_members": sorted(published),
        **reads,
    }


def require_instruction_sequence(code: bytes, label: str, sequence: tuple[int, ...]) -> None:
    encoded = struct.pack(f"<{len(sequence)}I", *sequence)
    if encoded not in code:
        raise ValueError(f"missing {label} instruction sequence")


def require_instruction_words_at(
    code: bytes, label: str, expected: dict[int, int]
) -> None:
    for offset, wanted in expected.items():
        if offset + 4 > len(code):
            raise ValueError(f"truncated {label} at {offset:#x}")
        actual = struct.unpack_from("<I", code, offset)[0]
        if actual != wanted:
            raise ValueError(
                f"unexpected {label} instruction at {offset:#x}: "
                f"{actual:#010x}, expected {wanted:#010x}"
            )


def find_direct_symbol_callers(image: bytes, target: int) -> set[str]:
    symbols = macho_symbols(image)
    ordered = sorted((address, name) for name, address in symbols.items())
    callers: set[str] = set()
    for item in load_commands(image):
        if item.command != LC_SEGMENT_64:
            continue
        segment = parse_segment(image, item)
        if segment.name != "__TEXT_EXEC":
            continue
        code = image[segment.file_offset : segment.file_offset + segment.file_size]
        owner_index = 0
        for offset, word in words(code):
            address = segment.virtual_address + offset
            while owner_index + 1 < len(ordered) and ordered[owner_index + 1][0] <= address:
                owner_index += 1
            if decode_bl_target(address, word) == target and ordered:
                callers.add(ordered[owner_index][1])
    return callers


def find_authenticated_target_references(image: bytes, target: int) -> list[int]:
    references = []
    for offset in range(0, len(image) - 7, 8):
        raw = struct.unpack_from("<Q", image, offset)[0]
        try:
            decoded = decode_kernel_auth_rebase(raw)
        except ValueError:
            continue
        if decoded == target:
            references.append(offset)
    return references


def decode_kernel_auth_rebase(raw: int) -> int:
    """Decode the target field of an arm64e kernel authenticated rebase."""

    if raw & 0xC000000000000000 != 0x8000000000000000:
        raise ValueError(f"not an authenticated kernel rebase: {raw:#x}")
    return KERNEL_COLLECTION_BASE + (raw & 0xFFFFFFFF)


def recover_vtable_target(image: bytes, vtable_name: str, slot: int) -> int:
    symbols = macho_symbols(image)
    if vtable_name not in symbols:
        raise ValueError(f"Mach-O has no {vtable_name} symbol")
    # A C++ vtable symbol begins with two header pointers before virtual slot 0.
    entry_address = symbols[vtable_name] + 0x10 + slot
    entry_offset = virtual_to_file(image, entry_address)
    if entry_offset + 8 > len(image):
        raise ValueError(f"truncated {vtable_name} entry at slot {slot:#x}")
    raw_entry = struct.unpack_from("<Q", image, entry_offset)[0]
    return decode_kernel_auth_rebase(raw_entry)


def recover_g17_constant_virtual_returns(image: bytes) -> dict[str, object]:
    """Validate constant-returning methods used by register value slices."""

    symbols = macho_symbols(image)
    methods: dict[str, object] = {}
    for slot, (label, provider, value) in G17_CONSTANT_VIRTUAL_RETURNS.items():
        if provider not in symbols:
            raise ValueError(f"Mach-O has no {provider} symbol")
        target = recover_vtable_target(image, G17_ACCELERATOR_VTABLE, slot)
        if target != symbols[provider]:
            raise ValueError(
                f"unexpected G17 {label} provider {target:#x}; "
                f"expected {symbols[provider]:#x}"
            )
        _address, code = symbol_code(image, provider)
        expected = struct.pack(
            "<3I",
            0xD503245F,  # bti c
            0x52800000 | value << 5,  # mov w0, #value
            0xD65F03C0,  # ret
        )
        if code != expected:
            raise ValueError(f"G17 {label} is not the checked constant stub")
        methods[label] = {
            "vtable_slot": slot,
            "provider": provider,
            "provider_address": target,
            "value": value,
        }
    return {
        "accelerator_vtable": G17_ACCELERATOR_VTABLE,
        "methods": methods,
    }


def recover_g17_memory_map_virtual_address(
    driver: bytes, iogpu: bytes
) -> dict[str, object]:
    """Validate the inherited IOGPUMemoryMap GPU-address accessor."""

    driver_symbols = macho_symbols(driver)
    iogpu_symbols = macho_symbols(iogpu)
    for vtable in (AGX_LEGACY_MEMORY_MAP_VTABLE, AGX_SECURE_MEMORY_MAP_VTABLE):
        if vtable not in driver_symbols:
            raise ValueError(f"AGX driver has no {vtable} symbol")
    for symbol in (IOGPU_MEMORY_MAP_VTABLE, IOGPU_MEMORY_MAP_GPU_VA):
        if symbol not in iogpu_symbols:
            raise ValueError(f"IOGPUFamily has no {symbol} symbol")

    provider_address = iogpu_symbols[IOGPU_MEMORY_MAP_GPU_VA]
    targets = {
        IOGPU_MEMORY_MAP_VTABLE: recover_vtable_target(
            iogpu, IOGPU_MEMORY_MAP_VTABLE, IOGPU_MEMORY_MAP_GPU_VA_SLOT
        ),
        AGX_LEGACY_MEMORY_MAP_VTABLE: recover_vtable_target(
            driver, AGX_LEGACY_MEMORY_MAP_VTABLE, IOGPU_MEMORY_MAP_GPU_VA_SLOT
        ),
        AGX_SECURE_MEMORY_MAP_VTABLE: recover_vtable_target(
            driver, AGX_SECURE_MEMORY_MAP_VTABLE, IOGPU_MEMORY_MAP_GPU_VA_SLOT
        ),
    }
    if any(target != provider_address for target in targets.values()):
        raise ValueError(
            "G17 memory-map vtables do not share the checked GPU-address accessor"
        )

    _address, code = symbol_code(iogpu, IOGPU_MEMORY_MAP_GPU_VA)
    expected = struct.pack(
        "<3I",
        0xD503245F,  # bti c
        0xF9401400,  # ldr x0, [x0, #0x28]
        0xD65F03C0,  # ret
    )
    if code != expected:
        raise ValueError("IOGPUMemoryMap GPU-address accessor has changed")
    return {
        "vtable_slot": IOGPU_MEMORY_MAP_GPU_VA_SLOT,
        "provider": IOGPU_MEMORY_MAP_GPU_VA,
        "provider_address": provider_address,
        "object_member": IOGPU_MEMORY_MAP_GPU_VA_MEMBER,
        "inherited_by": sorted(targets),
    }


def read_adrp_load(
    image: bytes,
    function_address: int,
    code: bytes,
    adrp_offset: int,
    load_offset: int,
    expected_width: int,
) -> bytes:
    if min(adrp_offset, load_offset) < 0 or max(adrp_offset, load_offset) + 4 > len(code):
        raise ValueError("PC-relative load is outside its function")
    adrp = decode_adrp(
        function_address + adrp_offset,
        struct.unpack_from("<I", code, adrp_offset)[0],
    )
    load = decode_load_unsigned(struct.unpack_from("<I", code, load_offset)[0])
    if adrp is None or load is None:
        raise ValueError("expected ADRP/load pair was not found")
    page_register, page = adrp
    _destination, base, immediate, width = load
    if base != page_register or width != expected_width:
        raise ValueError("unexpected PC-relative load shape")
    file_offset = virtual_to_file(image, page + immediate)
    return image[file_offset : file_offset + width]


def recover_g17_init_sequence_provider(image: bytes) -> dict[str, object]:
    symbols = macho_symbols(image)
    if G17_POPULATE_INIT_SEQUENCE not in symbols:
        raise ValueError(f"Mach-O has no {G17_POPULATE_INIT_SEQUENCE} symbol")
    target = recover_vtable_target(
        image, G17_ACCELERATOR_VTABLE, G17_INIT_SEQUENCE_VTABLE_SLOT
    )
    if target != symbols[G17_POPULATE_INIT_SEQUENCE]:
        raise ValueError(
            f"unexpected G17 init-sequence provider {target:#x}; "
            f"expected {symbols[G17_POPULATE_INIT_SEQUENCE]:#x}"
        )

    _address, provider_code = symbol_code(image, G17_POPULATE_INIT_SEQUENCE)
    expected_stub = struct.pack("<2I", 0xD503245F, 0xD65F03C0)  # bti c; ret
    if provider_code != expected_stub:
        raise ValueError("G17 init-sequence provider is not the checked no-op stub")
    return {
        "accelerator_vtable": G17_ACCELERATOR_VTABLE,
        "vtable_slot": G17_INIT_SEQUENCE_VTABLE_SLOT,
        "provider": G17_POPULATE_INIT_SEQUENCE,
        "provider_address": target,
        "entries_appended": 0,
    }


def recover_g17_platform_config(image: bytes, page_shift_code: bytes) -> dict[str, object]:
    symbols = macho_symbols(image)
    if G17_LEGACY_GART_INIT_INFO not in symbols:
        raise ValueError(f"Mach-O has no {G17_LEGACY_GART_INIT_INFO} symbol")
    provider = recover_vtable_target(
        image, G17_LEGACY_SHARED_GART_VTABLE, GART_INIT_INFO_VTABLE_SLOT
    )
    if provider != symbols[G17_LEGACY_GART_INIT_INFO]:
        raise ValueError(f"unexpected G17 legacy shared-GART initializer {provider:#x}")
    function_address, code = symbol_code(image, G17_LEGACY_GART_INIT_INFO)

    if page_shift_code != struct.pack("<3I", 0xD503245F, 0x528001C0, 0xD65F03C0):
        raise ValueError("G17 shared-GART layout does not have a checked 14-bit page shift")
    require_instruction_sequence(
        code,
        "G17 shared-GART scalar fields",
        (
            0xF9003C1F,  # clear object+0x78 through +0x7f
            0xD001D588,
            0xB94C1108,
            0x79003008,  # object+0x18
            0xD001D588,
            0xB94C0108,
            0x39006808,  # object+0x1a
        ),
    )
    require_instruction_sequence(
        code,
        "G17 shared-GART page geometry",
        (
            0xF0FFA3E8,
            0xF941D908,
            0xB9400108,
            0x52800029,
            0x1AC82128,
            0x79004408,  # object+0x22
            0x79008408,  # object+0x42
            0x7900C408,  # object+0x62
            0x52800809,  # 0x40
            0x79004009,  # object+0x20
            0x53037D08,  # page size >> 3
            0x79008008,  # object+0x40
            0x7900C008,  # object+0x60
        ),
    )
    require_instruction_sequence(
        code,
        "G17 shared-GART fixed ranges",
        (
            0xD2C07E08,  # 0x3f000000000
            0xF8034008,  # object+0x34
            0xB2672BE8,  # 0xffe000000
            0xF8054008,  # object+0x54
            0x32122BE8,  # 0x1ffc000
            0xF8074008,  # object+0x74
        ),
    )

    value_000 = int.from_bytes(read_adrp_load(image, function_address, code, 0x08, 0x0C, 4), "little")
    value_002 = int.from_bytes(read_adrp_load(image, function_address, code, 0x14, 0x18, 4), "little")
    value_003 = int.from_bytes(read_adrp_load(image, function_address, code, 0x54, 0x58, 8)[:4], "little")
    descriptor = read_adrp_load(image, function_address, code, 0x60, 0x64, 16)
    value_024 = int.from_bytes(read_adrp_load(image, function_address, code, 0x7C, 0x80, 8)[:4], "little")
    value_044 = int.from_bytes(read_adrp_load(image, function_address, code, 0x88, 0x8C, 8)[:4], "little")
    expected = (0x1000, 0x0C, 0x0E0E0803, 0x190E0E08, 0x0E0E0E08)
    if (value_000, value_002, value_003, value_024, value_044) != expected:
        raise ValueError("unexpected G17 shared-GART scalar literals")
    if descriptor != bytes.fromhex("010000000000000000c0ffffff030000"):
        raise ValueError("unexpected G17 shared-GART range descriptor")

    config = bytearray(0x68)
    struct.pack_into("<HBI", config, 0x00, value_000, value_002, value_003)
    config[0x07] = 0x24
    struct.pack_into("<HH", config, 0x08, 0x40, 0x4000)
    config[0x0C:0x1C] = descriptor
    struct.pack_into("<QIHH", config, 0x1C, 0x3F000000000, value_024, 0x800, 0x4000)
    config[0x2C:0x3C] = descriptor
    struct.pack_into("<QIHH", config, 0x3C, 0xFFE000000, value_044, 0x800, 0x4000)
    config[0x4C:0x5C] = descriptor
    struct.pack_into("<Q", config, 0x5C, 0x1FFC000)
    return {
        "bytes": len(config),
        "source_object_offset": 0x18,
        "accelerator_host_member": 0x1A948,
        "provider_vtable": G17_LEGACY_SHARED_GART_VTABLE,
        "provider_vtable_slot": GART_INIT_INFO_VTABLE_SLOT,
        "provider": G17_LEGACY_GART_INIT_INFO,
        "page_shift": 14,
        "descriptor": descriptor.hex(),
        "initial_bytes": config.hex(),
    }


def recover_g17_brn_workaround_table(
    image: bytes, allocation_code: bytes
) -> dict[str, object]:
    require_instruction_sequence(
        allocation_code,
        "firmware BRN workaround-table descriptor",
        (
            0x910BC268,  # add x8, x19, #0x2f0 (CPU output)
            0x910CE269,  # add x9, x19, #0x338 (GPU output)
            0xA90C27E8,
            0xF9414E60,  # accelerator at host member 0x298
            0xF9400010,
            0xAA0003F1,
            0xF2F9B431,
            0xDAC11A30,
            0xAA1003F1,
            0xDAC147F1,
            0xEB11021F,
            0x54000040,
            0xD4388E40,
            0x913E4208,  # accelerator vtable + 0xf90
            0xF947CA09,
            0xAA0803F1,
            0xF2FDDD51,
            0xD73F0931,
            0xAA1503F1,
            0x291A7FE0,  # descriptor size = returned w0
        ),
    )

    symbols = macho_symbols(image)
    for name in (G17_FW_BRN_SIZE, CONVERT_GPU_VA_TO_FW_VA):
        if name not in symbols:
            raise ValueError(f"Mach-O has no {name} symbol")
    size_provider = recover_vtable_target(
        image, G17_ACCELERATOR_VTABLE, G17_FW_BRN_SIZE_VTABLE_SLOT
    )
    if size_provider != symbols[G17_FW_BRN_SIZE]:
        raise ValueError(f"unexpected G17 firmware BRN size provider {size_provider:#x}")
    _address, size_code = symbol_code(image, G17_FW_BRN_SIZE)
    if size_code != struct.pack("<3I", 0xD503245F, 0xD2800000, 0xD65F03C0):
        raise ValueError("G17 firmware BRN table size provider does not return zero")

    converter = recover_vtable_target(
        image, G17_FIRMWARE_VTABLE, FIRMWARE_ADDRESS_CONVERSION_VTABLE_SLOT
    )
    if converter != symbols[CONVERT_GPU_VA_TO_FW_VA]:
        raise ValueError(f"unexpected G17 firmware address converter {converter:#x}")
    _address, converter_code = symbol_code(image, CONVERT_GPU_VA_TO_FW_VA)
    if converter_code != struct.pack("<3I", 0xD503245F, 0xAA0103E0, 0xD65F03C0):
        raise ValueError("G17 firmware address conversion is not the checked identity mapping")

    return {
        "bytes": 0,
        "host_cpu_member": 0x2F0,
        "host_gpu_member": 0x338,
        "accelerator_vtable_slot": G17_FW_BRN_SIZE_VTABLE_SLOT,
        "size_provider": G17_FW_BRN_SIZE,
        "firmware_shared_offset": 8,
        "firmware_address_conversion_vtable_slot": (
            FIRMWARE_ADDRESS_CONVERSION_VTABLE_SLOT
        ),
        "firmware_address_conversion": CONVERT_GPU_VA_TO_FW_VA,
    }


def recover_g17_bootstrap_region(
    allocation_code: bytes,
    prepare_code: bytes,
    page_shift_code: bytes,
    set_64_pa_code: bytes,
    set_64_code: bytes,
    set_32_code: bytes,
) -> dict[str, object]:
    expected_page_shift = struct.pack(
        "<3I",
        0xD503245F,  # bti c
        0x528001C0,  # mov w0, #14
        0xD65F03C0,  # ret
    )
    if page_shift_code != expected_page_shift:
        raise ValueError("G17 firmware page shift is not the checked 14-bit value")

    require_instruction_sequence(
        allocation_code,
        "bootstrap-region allocation",
        (
            0x52800029,  # mov w9, #1
            0x1AC0212A,  # lsl w10, w9, w0 (firmware page shift)
            0x113FFD4B,  # add w11, w10, #0xfff
            0x4B0A03EA,  # neg w10, w10
            0x0A0A0161,  # and w1, w11, w10
            0x1AC82128,  # lsl w8, w9, w8 (host page shift)
            0x93407D02,  # sxtw x2, w8
            0x52800260,  # mov w0, #0x13
        ),
    )
    require_instruction_sequence(
        allocation_code,
        "bootstrap-region CPU/GPU mapping pair",
        (
            0xF90D2A60,  # str x0, [x19, #0x1a50]
            0xB4005BA0,
            0xAA1303E0,
            0xAA1403E1,
            0x52800002,
            0x52800103,
            0x97FF8F6B,
            0xF90D2E60,  # str x0, [x19, #0x1a58]
        ),
    )
    require_instruction_sequence(
        prepare_code,
        "bootstrap-region cursor reset",
        (
            0xAA0003F3,
            0xB91AC01F,  # str wzr, [x0, #0x1ac0]
        ),
    )
    require_instruction_sequence(
        prepare_code,
        "bootstrap-region accelerator hook",
        (
            0xD2815111,  # mov x17, #0xa88
            0x8B110210,
            0xF9400208,
            0x52800021,  # role 1
        ),
    )
    require_instruction_sequence(
        prepare_code,
        "bootstrap-region terminator",
        (
            0xB95AC268,  # ldr w8, [x19, #0x1ac0]
            0x8B080009,
            0xB900113F,  # kind = 0
            0xA9007D3F,  # zero value, register, and auxiliary fields
            0x11006108,  # add cursor, #0x18
            0xB91AC268,
        ),
    )
    require_instruction_sequence(
        set_64_pa_code,
        "64-bit physical-address init-register record",
        (
            0x5280006A,  # kind = 3
            0x2901A933,  # auxiliary + kind
            0xF9000135,  # 64-bit value
            0xB9000936,  # register
            0x11006108,
            0xB91AC288,
        ),
    )
    require_instruction_sequence(
        set_64_code,
        "64-bit init-register record",
        (
            0xB9000935,  # register
            0xF9000134,  # 64-bit value
            0xF0FF3E2A,
            0xFD43C540,  # literal { auxiliary = 0, kind = 2 }
            0xFC00C120,
            0x11006108,
            0xB91AC268,
        ),
    )
    require_instruction_sequence(
        set_32_code,
        "32-bit init-register record",
        (
            0xB9000934,  # register
            0xF9000135,  # zero-extended 32-bit value
            0xF0FF3E2A,
            0xFD43F140,  # literal { auxiliary = 0, kind = 1 }
            0xFC00C120,
            0x11006108,
            0xB91AC268,
        ),
    )

    return {
        "bytes": 0x4000,
        "requested_bytes": 0x1000,
        "page_shift": 14,
        "host_cpu_member": 0x1A50,
        "host_gpu_mapping_member": 0x1A58,
        "cursor_host_member": 0x1AC0,
        "entry": {
            "bytes": 0x18,
            "value_offset": 0,
            "register_offset": 8,
            "auxiliary_offset": 0xC,
            "kind_offset": 0x10,
            "padding_offset": 0x14,
            "kinds": {
                "terminator": 0,
                "write_32": 1,
                "write_64": 2,
                "write_64_physical_address": 3,
            },
        },
        "terminator": {
            "offset": 0,
            "zeroed_bytes": 0x14,
            "padding_bytes": 4,
        },
    }


def recover_direct_shared_publications(code: bytes) -> list[tuple[int, int, int]]:
    """Recover {shared CPU member, source GPU member, shared offset} stores.

    The virtual-address conversion helper takes an allocation GPU address in
    x1 and returns the firmware-visible address in x0. The pinned driver then
    stores x0 through a direct shared-object pointer or a biased interior
    pointer.
    """

    instructions = list(words(code))
    publications: set[tuple[int, int, int]] = set()
    current_shared: int | None = None
    shared_members = {0xA98, 0xBC8}

    for index, (_offset, word) in enumerate(instructions):
        load = decode_ldr_x(word)
        if (
            load is not None
            and load[0] == 21
            and load[1] in (0, 19)
            and load[2] in shared_members
        ):
            current_shared = load[2]
        if load is None or load[0] != 1 or load[1] not in (0, 19):
            continue

        source_member = load[2]
        for following_index, (_following_offset, following_word) in enumerate(
            instructions[index + 1 : index + 36], index + 1
        ):
            following_load = decode_ldr_x(following_word)
            if (
                following_load is not None
                and following_load[0] == 1
                and following_load[1] in (0, 19)
            ):
                break
            store = decode_str_x(following_word)
            if store is None or store[0] != 0 or current_shared is None:
                continue

            _source, base, target_offset = store
            if base == 22:
                publications.add((current_shared, source_member, 0x254 + target_offset))
                break
            if base == 21:
                publications.add((current_shared, source_member, target_offset))
                break
            if base != 8:
                continue

            target_shared = None
            target_bias = 0
            for _prior_offset, prior_word in reversed(
                instructions[index + 1 : following_index]
            ):
                prior_load = decode_ldr_x(prior_word)
                if (
                    prior_load is not None
                    and prior_load[0] == 8
                    and prior_load[1] == 19
                    and prior_load[2] in shared_members
                ):
                    target_shared = prior_load[2]
                    break
                prior_add = decode_add_immediate(prior_word)
                if (
                    prior_add is not None
                    and prior_add[0] == 8
                    and prior_add[1] == 21
                ):
                    target_shared = current_shared
                    target_bias = prior_add[2]
                    break
            if target_shared is not None:
                publications.add(
                    (target_shared, source_member, target_bias + target_offset)
                )
                break

    return sorted(publications)


def recover_auxiliary_shared_publications(code: bytes) -> list[tuple[int, int, int]]:
    instructions = list(words(code))
    target_members = {0xAA8: (0xA98, 0x1C0), 0xBD8: (0xBC8, 0x1C0)}
    publications: set[tuple[int, int, int]] = set()

    for index, (_offset, word) in enumerate(instructions):
        source = decode_ldr_x(word)
        if source is None or source[0] != 1 or source[1] != 19:
            continue
        for following_index, (_following_offset, following_word) in enumerate(
            instructions[index + 1 : index + 36], index + 1
        ):
            following_source = decode_ldr_x(following_word)
            if (
                following_source is not None
                and following_source[0] == 1
                and following_source[1] == 19
            ):
                break
            store = decode_str_x(following_word)
            if store is None or store[0] != 0 or store[1] != 8:
                continue
            for _prior_offset, prior_word in reversed(
                instructions[index + 1 : following_index]
            ):
                target = decode_ldr_x(prior_word)
                if (
                    target is not None
                    and target[0] == 8
                    and target[1] == 19
                    and target[2] in target_members
                ):
                    shared_member, bias = target_members[target[2]]
                    publications.add((shared_member, source[2], bias + store[2]))
                    break
            break

    return sorted(publications)


def recover_firmware_shared_data_layout(
    allocations: list[dict[str, int]], shared_code: bytes, base_code: bytes
) -> dict[str, object]:
    direct = recover_direct_shared_publications(shared_code)
    expected_direct = sorted(
        (
            (0xA98, 0x300, 0x000),
            (0xA98, 0x338, 0x008),
            (0xA98, 0x340, 0x010),
            (0xA98, 0xAC0, 0x200),
            (0xA98, 0x308, 0x254),
            (0xA98, 0x310, 0x25C),
            (0xA98, 0x318, 0x264),
            (0xA98, 0x328, 0x26C),
            (0xA98, 0x330, 0x274),
            (0xBC8, 0x300, 0x000),
            (0xBC8, 0x338, 0x008),
            (0xBC8, 0x340, 0x010),
            (0xBC8, 0xBF0, 0x200),
            (0xBC8, 0x320, 0x471),
        )
    )
    if direct != expected_direct:
        raise ValueError(
            "unexpected direct firmware-shared publications: "
            f"{[(hex(shared), hex(source), hex(offset)) for shared, source, offset in direct]}"
        )

    auxiliary = recover_auxiliary_shared_publications(base_code)
    expected_auxiliary = sorted(
        (shared, source, 0x1C0 + index * 8)
        for shared, sources in (
            (0xA98, (0xB40, 0xB60, 0xB48, 0xB68, 0xB50, 0xB70, 0xB58, 0xB78)),
            (0xBC8, (0xC70, 0xC90, 0xC78, 0xC98, 0xC80, 0xCA0, 0xC88, 0xCA8)),
        )
        for index, source in enumerate(sources)
    )
    if auxiliary != expected_auxiliary:
        raise ValueError(
            "unexpected auxiliary firmware-shared publications: "
            f"{[(hex(shared), hex(source), hex(offset)) for shared, source, offset in auxiliary]}"
        )

    require_instruction_sequence(
        shared_code,
        "conditional platform shared-address source",
        (
            0xF9414E68,  # ldr x8, [x19, #0x298]
            0x529EEA89,  # mov w9, #0xf754
            0x8B090109,  # add x9, x8, x9
            0xB9400129,  # ldr w9, [x9]
        ),
    )
    require_instruction_sequence(
        shared_code,
        "conditional platform shared-address pointer",
        (
            0x91404D08,  # add x8, x8, #0x13000
            0x911DA108,  # add x8, x8, #0x768
            0xF9400101,  # ldr x1, [x8]
        ),
    )
    if struct.pack("<I", 0xF9016AA0) not in shared_code:  # str x0, [x21, #0x2d0]
        raise ValueError("missing conditional platform shared-address publication")

    allocation_sizes = {
        item["host_gpu_member"]: item["bytes"] for item in allocations
    }
    expected_sizes = {
        0x300: 0x2710,
        0x308: 0xC18,
        0x310: 0x1048,
        0x318: 0xE10,
        0x320: 0x11DD0,
        0x328: 0x68,
        0x330: 0x800,
        0x338: 0,
        0x340: 0x88,
        0xAC0: 0x79800,
        0xBF0: 0x79800,
        0xB40: 0x30,
        0xB48: 0x1B0,
        0xB50: 0x30,
        0xB58: 0x30,
        0xB60: 0x4800,
        0xB68: 0x28800,
        0xB70: 0x9000,
        0xB78: 0x4800,
        0xC70: 0x30,
        0xC78: 0x1B0,
        0xC80: 0x30,
        0xC88: 0x30,
        0xC90: 0x4800,
        0xC98: 0x28800,
        0xCA0: 0x9000,
        0xCA8: 0x4800,
    }
    mismatched = {
        member: (allocation_sizes.get(member), size)
        for member, size in expected_sizes.items()
        if allocation_sizes.get(member) != size
    }
    if mismatched:
        raise ValueError(
            "unexpected firmware-shared target allocations: "
            f"{[(hex(member), actual, expected) for member, (actual, expected) in mismatched.items()]}"
        )

    def render(items: list[tuple[int, int, int]]) -> list[dict[str, int]]:
        return [
            {
                "shared_cpu_member": shared,
                "source_gpu_member": source,
                "shared_offset": offset,
                **(
                    {"source_bytes": allocation_sizes[source]}
                    if source in allocation_sizes
                    else {}
                ),
            }
            for shared, source, offset in items
        ]

    return {
        "bytes": 0x4C0,
        "roles": [
            {
                "role": role,
                "shared_cpu_member": shared,
                "shared_gpu_member": gpu,
                "direct_publications": render(
                    [item for item in direct if item[0] == shared]
                ),
                "auxiliary_publications": render(
                    [item for item in auxiliary if item[0] == shared]
                ),
            }
            for role, shared, gpu in ((0, 0xA98, 0xAB8), (1, 0xBC8, 0xBE8))
        ],
        "conditional_platform_publication": {
            "host_platform_member": 0x298,
            "enabled_offset": 0xF754,
            "pointer_offset": 0x13768,
            "shared_cpu_member": 0xA98,
            "shared_offset": 0x2D0,
        },
    }


def recover_firmware_shared_platform_fields(code: bytes) -> dict[str, object]:
    require_instruction_sequence(
        code,
        "primary shared platform service pair",
        (
            0xF9454E75,  # ldr x21, [x19, #0xa98]
            0x91404408,  # add x8, x0, #0x11000
            0x91158108,  # add x8, x8, #0x560
            0xF9400108,  # ldr x8, [x8]
        ),
    )
    require_instruction_sequence(
        code,
        "primary shared second platform service pair",
        (
            0x91404408,  # add x8, x0, #0x11000
            0x9115A108,  # add x8, x8, #0x568
            0xF9400108,  # ldr x8, [x8]
        ),
    )
    for instruction, label in (
        (0xF9016EA0, "primary platform address 0x2d8"),
        (0xF90172A0, "primary platform address 0x2e0"),
        (0xF90176A0, "primary platform address 0x2e8"),
        (0xF9017AA0, "primary platform address 0x2f0"),
        (0xF9017EBF, "primary reserved address 0x2f8"),
    ):
        if struct.pack("<I", instruction) not in code:
            raise ValueError(f"missing {label} store")

    for instruction, label in (
        (0xF9016EBF, "nullable primary platform address 0x2d8"),
        (0xF90176BF, "nullable primary platform address 0x2e8"),
    ):
        if struct.pack("<I", instruction) not in code:
            raise ValueError(f"missing {label} zero store")
    if code.count(struct.pack("<I", 0xD2800000)) < 2:  # mov x0, #0
        raise ValueError("missing nullable secondary platform-service addresses")

    require_instruction_sequence(
        code,
        "secondary shared platform mirrors",
        (
            0xF945E669,  # ldr x9, [x19, #0xbc8]
            0xF9416EAA,  # ldr x10, [x21, #0x2d8]
            0xF9016D2A,  # str x10, [x9, #0x2d8]
            0xF9017528,  # str x8, [x9, #0x2e8]
            0xF9017D3F,  # str xzr, [x9, #0x2f8]
        ),
    )
    require_instruction_sequence(
        code,
        "role-specific shared platform scalars",
        (
            0x91403D09,  # add x9, x8, #0xf000
            0xB947C12A,  # ldr w10, [x9, #0x7c0]
            0xF945E66B,  # ldr x11, [x19, #0xbc8]
            0xB903016A,  # str w10, [x11, #0x300]
            0xB9483529,  # ldr w9, [x9, #0x834]
            0xB90306A9,  # str w9, [x21, #0x304]
        ),
    )
    require_instruction_sequence(
        code,
        "primary shared calibration copy",
        (
            0xF9454E69,  # ldr x9, [x19, #0xa98]
            0x9111E529,  # add x9, x9, #0x479
            0x3DFDE500,  # ldr q0, [x8, #0xf790]
            0x3D800120,  # str q0, [x9]
        ),
    )
    require_instruction_sequence(
        code,
        "secondary shared calibration copy",
        (
            0xF9414E68,  # ldr x8, [x19, #0x298]
            0xF945E669,  # ldr x9, [x19, #0xbc8]
            0x9111E529,  # add x9, x9, #0x479
            0x3DFDE500,  # ldr q0, [x8, #0xf790]
            0x3D800120,  # str q0, [x9]
        ),
    )
    require_instruction_sequence(
        code,
        "primary shared state initialization",
        (
            0x52801FE8,  # mov w8, #0xff
            0x390F82A8,  # strb w8, [x21, #0x3e0]
            0x910F86A8,  # add x8, x21, #0x3e1
            0x6F00E400,  # movi v0.2d, #0
            0xAD000100,
            0xAD010100,
            0xAD020100,
            0xAD030100,
            0x3D802100,
        ),
    )

    return {
        "platform_host_member": 0x298,
        "primary_service_sources": [
            {
                "platform_pointer_offset": 0x11560,
                "primary_shared_offsets": [0x2D8, 0x2E0],
                "primary_object_member": 0x68,
                "secondary_object_member": 0x58,
                "mapping_address_vtable_offset": 0x158,
                "nullable": True,
            },
            {
                "platform_pointer_offset": 0x11568,
                "primary_shared_offsets": [0x2E8, 0x2F0],
                "primary_object_member": 0x68,
                "secondary_object_member": 0x58,
                "mapping_address_vtable_offset": 0x158,
                "nullable": True,
            },
        ],
        "secondary_mirrors": [
            {"primary_shared_offset": 0x2D8, "secondary_shared_offset": 0x2D8},
            {"primary_shared_offset": 0x2E8, "secondary_shared_offset": 0x2E8},
        ],
        "scalars": [
            {"platform_offset": 0xF7C0, "role": 1, "shared_offset": 0x300},
            {"platform_offset": 0xF834, "role": 0, "shared_offset": 0x304},
        ],
        "calibration": {
            "platform_offset": 0xF790,
            "shared_offset": 0x479,
            "bytes": 0x10,
            "roles": [0, 1],
        },
        "primary_state": {
            "state_offset": 0x3E0,
            "state_initial": 0xFF,
            "status_offset": 0x3E1,
            "status_bytes": 0x90,
        },
    }


def recover_g17_small_shared_data(
    allocations: list[dict[str, int]],
    shared_init_code: bytes,
    base_init_code: bytes,
    ktrace_code: bytes,
    wait_power_off_code: bytes,
    wait_generation_code: bytes,
    snapshot_generation_code: bytes,
    get_sleep_code: bytes,
    set_sleep_code: bytes,
) -> dict[str, object]:
    by_pair = {
        (item["host_cpu_member"], item["host_gpu_member"]): item["bytes"]
        for item in allocations
    }
    roles = (
        (0, 0xAC8, 0xAD0, 0xB8C),
        (1, 0xBF8, 0xC00, 0xCBC),
    )
    for role, cpu_member, gpu_member, trace_member in roles:
        if by_pair.get((cpu_member, gpu_member)) != 0x20:
            raise ValueError(f"unexpected role {role} small-shared allocation")
        require_instruction_sequence(
            shared_init_code,
            f"role {role} small-shared trace-state publication",
            (
                0xB9400000 | (trace_member // 4) << 10 | 19 << 5 | 8,
                0xF9400000 | (cpu_member // 8) << 10 | 19 << 5 | 9,
                0xB9000128,  # str w8, [x9]
            ),
        )

    require_instruction_sequence(
        base_init_code,
        "small-shared host-ready initialization",
        (
            0xF945666B,  # role 0 CPU member 0xac8
            0xB9000576,  # +0x04 = 1
            0xF945FE6B,  # role 1 CPU member 0xbf8
            0xB9000576,
        ),
    )
    if struct.pack("<I", 0x52800036) not in base_init_code:  # mov w22, #1
        raise ValueError("small-shared host-ready value is not one")

    require_instruction_sequence(
        ktrace_code,
        "small-shared trace-state update",
        (
            0x52802608,  # per-role host stride 0x130
            0x9BA80068,
            0x52800029,
            0x392E1109,
            0xB94B8909,
            0xB90B8D09,
            0xF9456508,
            0xB9000109,  # publish trace state to +0x00
        ),
    )
    require_instruction_sequence(
        wait_power_off_code,
        "small-shared firmware-power-state polling",
        (
            0xF9456408,  # role 0 CPU member
            0xB9401108,  # +0x10
        ),
    )
    require_instruction_sequence(
        wait_power_off_code,
        "secondary small-shared firmware-power-state polling",
        (
            0xF945FE68,  # role 1 CPU member
            0xB9401108,  # +0x10
        ),
    )
    require_instruction_sequence(
        wait_generation_code,
        "role 0 ASC power-generation wait",
        (0xF9456408, 0xB9401D08),  # CPU member 0xac8, +0x1c
    )
    require_instruction_sequence(
        wait_generation_code,
        "role 1 ASC power-generation wait",
        (0xF945FE68, 0xB9401D08),  # CPU member 0xbf8, +0x1c
    )
    require_instruction_sequence(
        snapshot_generation_code,
        "role 0 ASC power-generation snapshot",
        (0xF9456408, 0xB9401D08),
    )
    require_instruction_sequence(
        snapshot_generation_code,
        "role 1 ASC power-generation snapshot",
        (0xF945FC08, 0xB9401D08),  # CPU member through x0, +0x1c
    )
    require_instruction_sequence(
        get_sleep_code,
        "small-shared sleep-notification read",
        (0xF9456408, 0xB9400908),  # role 0 CPU member, +0x08
    )
    require_instruction_sequence(
        get_sleep_code,
        "secondary small-shared sleep-notification read",
        (0xF945FC09, 0xB9400929),  # role 1 CPU member, +0x08
    )
    require_instruction_sequence(
        set_sleep_code,
        "small-shared sleep-notification publication",
        (
            0xF9456408,
            0x52800029,
            0xB9000909,  # role 0 +0x08 = 1
            0xF945FC08,
            0xB9000909,  # role 1 +0x08 = 1
        ),
    )

    return {
        "bytes": 0x20,
        "roles": [
            {
                "role": role,
                "host_cpu_member": cpu_member,
                "host_gpu_member": gpu_member,
                "trace_state_host_member": trace_member,
            }
            for role, cpu_member, gpu_member, trace_member in roles
        ],
        "fields": [
            {"offset": 0x00, "bytes": 4, "name": "ktrace_state", "owner": "host"},
            {"offset": 0x04, "bytes": 4, "name": "host_ready", "initial": 1},
            {"offset": 0x08, "bytes": 4, "name": "system_sleep_notification"},
            {"offset": 0x0C, "bytes": 4, "name": "reserved_00c"},
            {"offset": 0x10, "bytes": 4, "name": "firmware_power_state", "owner": "firmware"},
            {"offset": 0x14, "bytes": 4, "name": "reserved_014"},
            {"offset": 0x18, "bytes": 4, "name": "reserved_018"},
            {"offset": 0x1C, "bytes": 4, "name": "asc_power_generation", "owner": "firmware"},
        ],
    }


def recover_g17_runtime_controls(
    allocations: list[dict[str, int]], accessor_code: dict[str, bytes]
) -> dict[str, object]:
    expected_cpu_member = 0x380
    expected_gpu_member = 0x388
    expected_size = 0x1CA0
    allocation_size = next(
        (
            item["bytes"]
            for item in allocations
            if item["host_cpu_member"] == expected_cpu_member
            and item["host_gpu_member"] == expected_gpu_member
        ),
        None,
    )
    if allocation_size != expected_size:
        raise ValueError(f"unexpected G17 runtime-data allocation size: {allocation_size}")

    recovered_fields = []
    for field_name, (symbol, expected_accesses) in G17_RUNTIME_ACCESSORS.items():
        code = accessor_code.get(symbol)
        if code is None:
            raise ValueError(f"missing G17 runtime accessor {symbol}")
        instructions = list(words(code))
        runtime_loads = [
            (index, load[0])
            for index, (_offset, word) in enumerate(instructions)
            if (load := decode_ldr_x(word)) is not None
            and load[2] == expected_cpu_member
        ]
        if not runtime_loads:
            raise ValueError(f"{field_name} does not load the G17 runtime object")
        actual_accesses: set[tuple[int, int]] = set()
        for load_index, runtime_register in runtime_loads:
            for _offset, word in instructions[load_index + 1 : load_index + 13]:
                store = decode_str_unsigned(word)
                if store is not None and store[1] == runtime_register:
                    actual_accesses.add((store[2], store[3]))
        if not set(expected_accesses).issubset(actual_accesses):
            raise ValueError(
                f"unexpected {field_name} runtime stores: "
                f"{sorted(actual_accesses)}"
            )
        recovered_fields.append(
            {
                "name": field_name,
                "accessor": symbol,
                "stores": [
                    {"offset": offset, "bytes": width}
                    for offset, width in expected_accesses
                ],
            }
        )

    for field_name in (
        "fw_util_debounce_periods",
        "fw_util_pstate_threshold",
        "fw_util_pstate_step_size",
    ):
        symbol = G17_RUNTIME_ACCESSORS[field_name][0]
        require_instruction_sequence(
            accessor_code[symbol],
            f"{field_name} four-entry stride",
            (
                0x528000CC,  # mov w12, #6
                0x9240042D,  # and x13, x1, #3
                0x9BAC25A9,  # umaddl x9, w13, w12, x9
            ),
        )

    register_override_code = accessor_code.get(G17_ADD_REGISTER_OVERRIDE)
    if register_override_code is None:
        raise ValueError(f"missing G17 runtime accessor {G17_ADD_REGISTER_OVERRIDE}")
    require_instruction_sequence(
        register_override_code,
        "register-override record selection",
        (
            0x8B0A054A,  # count * 3
            0xD37DF14A,  # byte stride 24
            0x8B0A012B,
            0xB9081561,  # register at record +0x10
            0x91201129,  # table base runtime +0x804
        ),
    )
    require_instruction_sequence(
        register_override_code,
        "register-override values",
        (
            0xF9000182,  # first u64 at record +0x00
            0x91203169,
            0xF9000123,  # second u64 at record +0x08
        ),
    )
    require_instruction_sequence(
        register_override_code,
        "register-override count publication",
        (
            0xF941C108,
            0xB9498509,
            0x11000529,
            0xB9098509,
        ),
    )

    return {
        "bytes": expected_size,
        "host_cpu_member": expected_cpu_member,
        "host_gpu_member": expected_gpu_member,
        "fields": recovered_fields,
        "register_overrides": {
            "offset": 0x804,
            "entries": 16,
            "stride": 0x18,
            "count_offset": 0x984,
            "fields": [
                {"offset": 0x00, "bytes": 8, "name": "value"},
                {"offset": 0x08, "bytes": 8, "name": "mask"},
                {"offset": 0x10, "bytes": 4, "name": "register"},
            ],
        },
        "fw_util_pstate_controls": {
            "offset": 0x9EB,
            "entries": 4,
            "stride": 6,
            "fields": [
                {"offset": 0, "bytes": 2, "name": "debounce_periods"},
                {"offset": 2, "bytes": 2, "name": "pstate_threshold"},
                {"offset": 4, "bytes": 2, "name": "pstate_step_size"},
            ],
        },
    }


def recover_g17_runtime_initialization(
    allocations: list[dict[str, int]],
    base_init_code: bytes,
    arm_init_code: bytes,
    base_power_code: bytes,
    arm_power_code: bytes,
) -> dict[str, object]:
    """Recover the parts of the G17 runtime object written during startup.

    The power-controller payload is assembled from a temporary host object in
    a deliberately non-linear order. This records the complete destination
    range without pretending that Vinix knows how to produce its source
    policy yet.
    """

    expected_cpu_member = 0x380
    expected_gpu_member = 0x388
    expected_size = 0x1CA0
    allocation_size = next(
        (
            item["bytes"]
            for item in allocations
            if item["host_cpu_member"] == expected_cpu_member
            and item["host_gpu_member"] == expected_gpu_member
        ),
        None,
    )
    if allocation_size != expected_size:
        raise ValueError(f"unexpected G17 runtime-data allocation size: {allocation_size}")

    require_instruction_sequence(
        base_init_code,
        "runtime base-state initialization",
        (
            0xB900010C,  # +0x00 = platform feature mask or zero
            0xB900051F,  # +0x04 = 0
            0xB900091F,  # +0x08 = 0
            0xB900191F,  # +0x18 = 0
            0xB9001D1F,  # +0x1c = 0
        ),
    )
    require_instruction_sequence(
        base_init_code,
        "runtime virtual-device state",
        (
            0xF941C268,  # runtime CPU member 0x380
            0xB805E100,  # callback result at unaligned +0x5e
            0xB845E11F,  # force the volatile read
        ),
    )
    require_instruction_sequence(
        base_init_code,
        "runtime platform feature state",
        (
            0xF941C26A,
            0xB8062149,  # platform feature result at +0x62
            0xB9400109,
            0xB9002149,  # platform value at +0x20
        ),
    )
    require_instruction_sequence(
        base_init_code,
        "runtime state-48 default",
        (
            0xF941C26A,
            0xB900495F,  # +0x48 = 0
        ),
    )
    require_instruction_sequence(
        base_init_code,
        "runtime RIART defaults",
        (
            0xF941C268,
            0x52839029,
            0x8B090109,
            0x5280002A,
            0xB900012A,  # +0x1c81 = 1
            0x528390A9,
            0x8B090109,
            0xB900013F,  # +0x1c85 = 0
            0x52839129,
            0x8B090109,
            0xB900013F,  # +0x1c89 = 0
            0x528391A9,
            0x8B090108,
            0xB900011F,  # +0x1c8d = 0
        ),
    )

    require_instruction_sequence(
        arm_init_code,
        "runtime platform halfword copy",
        (
            0xF941C269,
            0xB900153F,  # +0x14 = 0
            0xF9414E68,
            0x9140390A,
            0x794ED10B,
            0x7900A92B,  # platform +0x768 -> runtime +0x54
            0x794ED50B,
            0x7900AD2B,  # platform +0x76a -> runtime +0x56
            0x794ED90B,
            0x7900B12B,  # platform +0x76c -> runtime +0x58
        ),
    )
    require_instruction_sequence(
        arm_init_code,
        "runtime early defaults",
        (
            0xF941C269,
            0xB909C93F,  # +0x9c8 = 0
        ),
    )
    require_instruction_sequence(
        arm_init_code,
        "runtime unaligned state-5a default",
        (
            0xF941C268,
            0xB805A11F,  # +0x5a = 0
        ),
    )
    require_instruction_sequence(
        arm_init_code,
        "runtime kick-channel defaults",
        (
            0xF9466A6B,
            0x5298E50C,
            0x8B0C016B,
            0xB900017F,
            0xB900513F,  # +0x50 = 0
            0xB9004D3F,  # +0x4c = 0
            0xB940016C,
            0x3400008C,
            0xB940017F,
            0xB940513F,
            0xB9404D3F,
            0xB909E13F,  # +0x9e0 = 0
        ),
    )
    require_instruction_sequence(
        arm_init_code,
        "runtime Smart Idle policy copy",
        (
            0xBD495140,
            0xBD07CD20,  # +0x950 -> +0x7cc
            0xBD495540,
            0xBD07D120,
            0xBD495940,
            0xBD07D520,
            0xBD495D40,
            0xBD07D920,
            0xBD496140,
            0xBD07DD20,
            0xBD496540,
            0xBD07E120,
            0xBD496940,
            0xBD07E520,  # +0x968 -> +0x7e4
            0xBD496D40,
            0x7E21D800,
            0x1E39000B,
            0xB907E92B,  # converted +0x96c -> +0x7e8
            0xB949494B,
            0xB907C52B,  # +0x948 -> +0x7c4
            0xBD494D40,
            0xBD07C920,  # +0x94c -> +0x7c8
        ),
    )
    require_instruction_sequence(
        arm_init_code,
        "runtime role-state zero source",
        (
            0x6F00E400,  # v0 = 0
            0xFD07A960,
            0xB90F5D7F,
            0xFD07B160,
            0xB90F957F,
            0xB946D109,
            0x53186129,
            0xB90F8169,
            0xB94ED569,
            0x7100053F,
            0x1A9F8529,
            0xF941C26A,
            0xB806A149,  # +0x6a = normalized role count
            0x5283882C,
            0x8B0C014C,
            0xB9000189,  # +0x1c41 mirrors +0x6a
            0x528388A9,
            0x8B090149,
            0xFD000120,  # +0x1c45 = 0
            0x528389A9,
            0x8B090149,
            0xB900013F,  # +0x1c4d = 0
        ),
    )
    require_instruction_sequence(
        arm_init_code,
        "runtime CPMS defaults",
        (
            0xB925B93F,
            0xB900411F,  # +0x40 = 0
            0xB900451F,  # +0x44 = 0
        ),
    )
    require_instruction_sequence(
        arm_init_code,
        "runtime late callback state",
        (
            0xF941C269,
            0xB91C2D28,  # callback result at +0x1c2c
        ),
    )

    require_instruction_sequence(
        base_power_code,
        "runtime base power defaults",
        (
            0xF941C269,
            0x91281128,  # runtime +0xa04
            0xB900312B,  # +0x30 = platform feature bit
            0xB947014B,
            0xB9002D2B,  # platform +0x700 -> +0x2c
            0xB946FD4A,
            0x3400006A,
            0xB900952A,  # optional platform +0x6fc -> +0x94
            0xB900AD2A,  # and +0xac
            0x6F00E400,
            0xAD000100,
            0xF900111F,  # clear +0xa04..+0xa2b
        ),
    )

    require_instruction_sequence(
        arm_power_code,
        "runtime host policy snapshot",
        (
            0xF941C008,
            0x5284F909,
            0x8B090009,  # host object +0x27c8
            0xAD410121,
            0xAD400D22,
            0x3C8B4103,
            0x3C8C4101,
            0x3C8D4100,
            0x3C8A4102,  # complete runtime +0xa4..+0xe3
        ),
    )
    require_instruction_sequence(
        arm_power_code,
        "runtime power-controller prefix",
        (
            0xF941C268,
            0x9104B109,  # destination base runtime +0x12c
            0xB940628A,
            0xB900ED0A,  # source +0x60 -> runtime +0xec
            0xB940668A,
            0xB900F10A,
        ),
    )
    require_instruction_sequence(
        arm_power_code,
        "runtime twin power-controller tables",
        (
            0x914046AA,
            0x9107814A,  # source platform +0x111e0
            0x9112D10B,  # upper destination runtime +0x4b4
            0x5280080C,  # 64 qwords per table
            0xF940014D,
            0xD109216E,  # lower destination runtime +0x26c
            0xF90001CD,
            0xF941254D,
            0xF800856D,
            0x9100214A,
            0xF100058C,
            0x54FFFF21,
        ),
    )
    require_instruction_sequence(
        arm_power_code,
        "runtime power-controller tail",
        (
            0xF943168A,  # source +0x628
            0xF902C52A,  # destination base +0x588 == runtime +0x6b4
            0xF9431A8A,
            0xF902C92A,
        ),
    )
    require_instruction_sequence(
        arm_power_code,
        "runtime power-controller tail end",
        (
            0xF943968A,
            0xF903452A,
            0xF9439A8A,  # source +0x730
            0xF903492A,  # destination base +0x690 == runtime +0x7bc
        ),
    )
    require_instruction_sequence(
        arm_power_code,
        "runtime power-controller completion",
        (
            0xF941C268,
            0xB9009D1F,  # +0x9c = 0
            0xB900A11F,  # +0xa0 = 0
        ),
    )

    return {
        "bytes": expected_size,
        "host_cpu_member": expected_cpu_member,
        "host_gpu_member": expected_gpu_member,
        "zero_initialized": [
            {"offset": offset, "bytes": width, "value": value}
            for offset, width, value in (
                (0x004, 4, 0),
                (0x008, 4, 0),
                (0x014, 4, 0),
                (0x018, 4, 0),
                (0x01C, 4, 0),
                (0x040, 4, 0),
                (0x044, 4, 0),
                (0x048, 4, 0),
                (0x04C, 4, 0),
                (0x050, 4, 0),
                (0x05A, 4, 0),
                (0x09C, 4, 0),
                (0x0A0, 4, 0),
                (0x9C8, 4, 0),
                (0x9E0, 4, 0),
                (0xA04, 0x28, 0),
                (0x1C45, 8, 0),
                (0x1C4D, 4, 0),
                (0x1C81, 4, 1),
                (0x1C85, 4, 0),
                (0x1C89, 4, 0),
                (0x1C8D, 4, 0),
            )
        ],
        "platform_copies": [
            {
                "destination_offset": 0x054,
                "bytes": 6,
                "source": "platform_config+0x768",
            },
            {
                "destination_offset": 0x0A4,
                "bytes": 0x40,
                "source": "firmware_host_object+0x27c8",
            },
            {
                "destination_offset": 0x0EC,
                "bytes": 0x6D8,
                "source": "power_controller_snapshot",
                "complete_destination_range": True,
            },
            {
                "destination_offset": 0x7C4,
                "bytes": 0x28,
                "source": "accelerator+0xe948",
                "converted_tail": True,
            },
        ],
        "power_controller_tables": [
            {
                "destination_offset": 0x26C,
                "source_offset": 0,
                "bytes": 0x200,
            },
            {
                "destination_offset": 0x4B4,
                "source_offset": 0x248,
                "bytes": 0x200,
            },
        ],
        "dynamic_fields": [
            {"offset": 0x000, "bytes": 4, "source": "platform_feature_mask"},
            {"offset": 0x020, "bytes": 4, "source": "platform_config+0x131f8"},
            {"offset": 0x02C, "bytes": 4, "source": "platform_config+0x700"},
            {"offset": 0x030, "bytes": 4, "source": "platform_feature_bit_0"},
            {"offset": 0x05E, "bytes": 4, "source": "virtual_device_callback"},
            {"offset": 0x062, "bytes": 4, "source": "platform_feature_state"},
            {"offset": 0x06A, "bytes": 4, "source": "normalized_role_count"},
            {"offset": 0x1C2C, "bytes": 4, "source": "firmware_callback"},
            {"offset": 0x1C41, "bytes": 4, "source": "normalized_role_count"},
        ],
    }


def recover_g17_runtime_power_policy(
    image: bytes, arm_power_code: bytes, populate_code: bytes
) -> dict[str, object]:
    """Prove that the G17 runtime power-controller payload starts as zero.

    The G17 accelerator inherits the generic DPE/PPT producer.  Its vtable
    target clears 0x6e0 bytes, and the arm-firmware initializer rearranges a
    subset of that cleared block into the complete runtime payload.  Keep the
    vtable and call-site checks together so an Apple driver update cannot turn
    this fact into an unsafe assumption.
    """

    target = recover_vtable_target(image, G17_ACCELERATOR_VTABLE, 0xD80)
    symbols = macho_symbols(image)
    expected_target = symbols.get(POPULATE_DPE_PPT_CONFIG)
    if expected_target is None or target != expected_target:
        raise ValueError(
            f"unexpected G17 DPE/PPT producer target {target:#x}"
        )

    instructions = [word for _offset, word in words(populate_code)]
    if (
        len(instructions) != 4
        or instructions[:3] != [0xD503245F, 0xAA0103E0, 0x5280DC01]
        or instructions[3] & 0xFC000000 != 0x14000000
    ):
        raise ValueError("G17 DPE/PPT producer is not the checked 0x6e0-byte clear")

    require_instruction_sequence(
        arm_power_code,
        "G17 DPE/PPT runtime source",
        (
            0xF9416E75,  # firmware host object at this + 0x2d8
            0x914046B4,  # source base host object + 0x11000
            0xF9414E60,  # accelerator/platform object at this + 0x298
        ),
    )
    require_instruction_sequence(
        arm_power_code,
        "G17 DPE/PPT producer call",
        (
            0x91360208,  # accelerator vtable + 0xd80
            0xF946C209,
            0x914046AA,  # firmware host object + 0x11000
            0x91017141,  # producer destination + 0x5c
        ),
    )

    source_base = 0x11000
    clear_offset = 0x5C
    clear_bytes = 0x6E0
    copied_source_start = 0x60
    copied_source_end = 0x738
    if not (
        clear_offset <= copied_source_start
        and copied_source_end <= clear_offset + clear_bytes
    ):
        raise ValueError("G17 runtime power-policy source escapes the cleared block")

    return {
        "producer": POPULATE_DPE_PPT_CONFIG,
        "accelerator_vtable_slot": 0xD80,
        "host_object_base": source_base,
        "cleared_source_offset": clear_offset,
        "cleared_source_bytes": clear_bytes,
        "copied_source_range": {
            "offset": copied_source_start,
            "bytes": copied_source_end - copied_source_start,
        },
        "runtime_range": {"offset": 0xEC, "bytes": 0x6D8, "value": 0},
    }


def recover_g17_runtime_performance_policy(
    setup_code: bytes, arm_power_code: bytes
) -> dict[str, object]:
    """Recover the zeroed G17 performance-controller startup policy.

    setupConfig explicitly clears the 57 named bytes at firmware-host-object
    offsets 0x27c8..0x2800.  initPowerAndPerformanceData later copies a
    complete 64-byte slot beginning at 0x27c8 to runtime 0xa4.  The trailing
    seven bytes are alignment padding, which Vinix clears deterministically.
    Keep both instruction sequences pinned so a future driver cannot silently
    turn an assumed zero override into an active controller setting.
    """

    require_instruction_sequence(
        setup_code,
        "G17 performance-controller policy clear",
        (
            0x911FA708,  # host object +0x27e9
            0x911FC709,  # host object +0x27f1
            0x911F870A,  # host object +0x27e1
            0xB900011F,
            0xB900013F,
            0xB900015F,
            0x391FEB1F,  # +0x27fa
            0x391FF31F,  # +0x27fc
            0x391FFB1F,  # +0x27fe
            0x911FB708,  # +0x27ed
            0xB900011F,
            0x911FD708,  # +0x27f5
            0xB900011F,
            0x911F9708,  # +0x27e5
            0xB900011F,
            0x391FEF1F,  # +0x27fb
            0x391FF71F,  # +0x27fd
            0x391FFF1F,  # +0x27ff
            0x391FE71F,  # +0x27f9
            0x3920031F,  # +0x2800
            0xB927CA7F,  # +0x27c8
            0xB927D27F,  # +0x27d0
            0xB927D67F,  # +0x27d4
            0x391F831F,  # +0x27e0
            0xB927DA7F,  # +0x27d8
            0xB927CE7F,  # +0x27cc
            0xB927DE7F,  # +0x27dc
        ),
    )
    require_instruction_sequence(
        arm_power_code,
        "G17 performance-controller policy snapshot",
        (
            0xF941C008,
            0x5284F909,
            0x8B090009,  # firmware host object +0x27c8
            0xAD410121,
            0xAD400D22,
            0x3C8B4103,
            0x3C8C4101,
            0x3C8D4100,
            0x3C8A4102,  # complete runtime +0xa4..+0xe3
        ),
    )

    return {
        "producer": SETUP_CONFIG,
        "host_object_offset": 0x27C8,
        "cleared_source_bytes": 0x39,
        "copied_source_bytes": 0x40,
        "runtime_range": {"offset": 0xA4, "bytes": 0x40},
        "initial_value": 0,
        "reserved_tail_bytes": 7,
    }


def recover_g17_runtime_platform_policy(image: bytes) -> dict[str, object]:
    """Recover the G17C platform halfwords and Smart Idle startup policy.

    These values are installed by the configureDevice and
    configurePowerAndPerformanceController virtual paths selected by the G17
    accelerator.  Validate both vtable targets and their base-class call
    chains before accepting constants from the implementation.
    """

    symbols = macho_symbols(image)
    required = (
        BASE_CONFIGURE_DEVICE,
        PI300_CONFIGURE_DEVICE,
        G17_CONFIGURE_DEVICE,
        BASE_CONFIGURE_POWER,
        G17_CONFIGURE_POWER,
    )
    missing = [name for name in required if name not in symbols]
    if missing:
        raise ValueError(f"Mach-O has no {missing[0]} symbol")

    device_target = recover_vtable_target(
        image, G17_ACCELERATOR_VTABLE, G17_CONFIGURE_DEVICE_VTABLE_SLOT
    )
    if device_target != symbols[G17_CONFIGURE_DEVICE]:
        raise ValueError(f"unexpected G17 configureDevice target {device_target:#x}")
    power_target = recover_vtable_target(
        image, G17_ACCELERATOR_VTABLE, G17_CONFIGURE_POWER_VTABLE_SLOT
    )
    if power_target != symbols[G17_CONFIGURE_POWER]:
        raise ValueError(
            f"unexpected G17 power-controller configure target {power_target:#x}"
        )

    g17_device_address, g17_device_code = symbol_code(image, G17_CONFIGURE_DEVICE)
    pi_device_address, pi_device_code = symbol_code(image, PI300_CONFIGURE_DEVICE)
    base_power_address, base_power_code = symbol_code(image, BASE_CONFIGURE_POWER)
    g17_power_address, g17_power_code = symbol_code(image, G17_CONFIGURE_POWER)

    def checked_call(
        function_address: int,
        code: bytes,
        offset: int,
        expected_target: int,
        label: str,
    ) -> None:
        if offset + 4 > len(code):
            raise ValueError(f"missing {label} call")
        word = struct.unpack_from("<I", code, offset)[0]
        target = decode_bl_target(function_address + offset, word)
        if target != expected_target:
            target_text = "non-BL" if target is None else f"{target:#x}"
            raise ValueError(
                f"unexpected {label} target {target_text}; expected {expected_target:#x}"
            )

    checked_call(
        g17_device_address,
        g17_device_code,
        0x70,
        symbols[PI300_CONFIGURE_DEVICE],
        "G17 configureDevice base",
    )
    checked_call(
        pi_device_address,
        pi_device_code,
        0x48,
        symbols[BASE_CONFIGURE_DEVICE],
        "PI300 configureDevice base",
    )
    checked_call(
        g17_power_address,
        g17_power_code,
        0x20,
        symbols[BASE_CONFIGURE_POWER],
        "G17 power-controller configure base",
    )

    require_instruction_sequence(
        pi_device_code,
        "G17 runtime platform halfword install",
        (
            0xF0FF3DC8,  # ADRP of the checked eight-byte constant
            0xFD448900,
            0x12800008,
            0xB9077268,
            0xD0FF3E48,
            0x9111A508,
            0xF9344268,
            0x90FFA439,
            0xF941DB39,
            0xB9400328,
            0x1AC82308,
            0x528FFFE9,
            0x0B090109,
            0x4B0803E8,
            0x0A080128,
            0x3906629F,
            0xFD03B660,  # constant -> accelerator +0x768
        ),
    )
    platform_bytes = read_adrp_load(
        image, pi_device_address, pi_device_code, 0xBC, 0xC0, 8
    )[:6]
    if len(platform_bytes) != 6:
        raise ValueError("truncated G17 runtime platform halfword constant")

    require_instruction_sequence(
        base_power_code,
        "base Smart Idle policy install",
        (
            0xF0FF41C8,
            0x3DC29500,
            0x3C8142E0,
            0x528000C8,
            0xB90026E8,
            0x52805788,
            0xB90002E8,
            0xF0FF41C8,
            0x3DC29900,
            0x3C8042E0,
        ),
    )
    smart_high = read_adrp_load(
        image, base_power_address, base_power_code, 0x384, 0x388, 16
    )
    smart_low = read_adrp_load(
        image, base_power_address, base_power_code, 0x3A0, 0x3A4, 16
    )
    if len(smart_high) != 16 or len(smart_low) != 16:
        raise ValueError("truncated base Smart Idle policy constant")

    # w8 is materialized as float 0.6 and remains live through the intervening
    # x9/x10-only setup before it overwrites source offset +0x1c.
    require_instruction_sequence(
        g17_power_code,
        "G17 Smart Idle minimum-confidence override",
        (
            0x52933348,
            0x72A7E328,
            0xB902E688,
            0x52801F09,
            0xB902BA89,
            0xB942B28A,
            0x1ACA0929,
            0xB902B689,
            0x91093289,
            0xD0FF3D6A,
            0xFD44B940,
            0xFD000120,
            0x52933349,
            0x72A7D329,
            0xB9002E89,
            0x52A83109,
            0xB9002289,
            0x52800209,
            0xB9000289,
            0xD0FF3D69,
            0xFD44BD20,
            0xFD0002A0,
            0xD0FF3D69,
            0xFD44C120,
            0xFD04CEA0,
            0xB9001EC8,
            0x5280BB88,
            0xB90002C8,
        ),
    )

    source = bytearray(0x28)
    struct.pack_into("<I", source, 0x00, 700)
    source[0x04:0x14] = smart_low
    source[0x14:0x24] = smart_high
    struct.pack_into("<I", source, 0x24, 6)
    # The G17 override replaces the generic 700 us delay and 0.7 confidence.
    struct.pack_into("<I", source, 0x00, 1500)
    struct.pack_into("<I", source, 0x1C, 0x3F19999A)

    runtime = bytearray(source)
    reset_iterations = struct.unpack_from("<I", source, 0x24)[0]
    struct.pack_into("<f", runtime, 0x24, float(reset_iterations))
    field_names = (
        "standby_timer_us",
        "probability_initial_bits",
        "fn_hit_bits",
        "fi_hit_bits",
        "fn_miss_bits",
        "fi_miss_bits",
        "neighbor_hit_bits",
        "gpu_min_confidence_bits",
        "gpu_high_confidence_bits",
        "reset_iterations_float_bits",
    )
    runtime_words = struct.unpack("<10I", runtime)

    return {
        "configure_device_vtable_slot": G17_CONFIGURE_DEVICE_VTABLE_SLOT,
        "configure_power_vtable_slot": G17_CONFIGURE_POWER_VTABLE_SLOT,
        "platform_halfwords": {
            "source_offset": 0x768,
            "runtime_offset": 0x054,
            "values": list(struct.unpack("<3H", platform_bytes)),
            "bytes": platform_bytes.hex(),
        },
        "smart_idle": {
            "source_offset": 0xE948,
            "runtime_offset": 0x7C4,
            "bytes": 0x28,
            "source_bytes": source.hex(),
            "runtime_bytes": runtime.hex(),
            "runtime_fields": dict(zip(field_names, runtime_words)),
        },
    }


def recover_g17_shared_platform_values(image: bytes) -> dict[str, object]:
    """Recover initial values copied into the two firmware-shared objects."""

    symbols = macho_symbols(image)
    required = (
        BASE_CONFIGURE_DEVICE,
        G17_DEFAULT_USC_MAX_TGMEM,
        SET_GVDM_MODE,
        GET_UMA_MAX_ACTIVE_GTP_KICKS,
        PERF_COUNTER_SOURCE_STOP,
        PERF_COUNTER_LOCK_ACCESS,
    )
    missing = [name for name in required if name not in symbols]
    if missing:
        raise ValueError(f"Mach-O has no {missing[0]} symbol")

    default_target = recover_vtable_target(
        image,
        G17_ACCELERATOR_VTABLE,
        G17_DEFAULT_USC_MAX_TGMEM_VTABLE_SLOT,
    )
    if default_target != symbols[G17_DEFAULT_USC_MAX_TGMEM]:
        raise ValueError(
            f"unexpected G17 default USC max TGMEM target {default_target:#x}"
        )
    _default_address, default_code = symbol_code(image, G17_DEFAULT_USC_MAX_TGMEM)
    if default_code[:12] != struct.pack("<3I", 0xD503245F, 0x52800180, 0xD65F03C0):
        raise ValueError("unexpected G17 default USC max TGMEM provider")

    _base_address, base_code = symbol_code(image, BASE_CONFIGURE_DEVICE)
    require_instruction_words_at(
        base_code,
        "G17 shared platform source initialization",
        {
            # Virtual call at slot 0x10e0, followed by accelerator+0xf7c0.
            0x444: 0x52821C08,
            0x448: 0x8B080208,
            0x44C: 0xF9487209,
            0x45C: 0xD73F0931,
            0x464: 0xB9009B00,
            # Explicit 16-byte clear of accelerator+0xf790.
            0x68C: 0x6F00E400,
            0x690: 0x3DBDE660,
        },
    )

    _getter_address, getter_code = symbol_code(image, GET_UMA_MAX_ACTIVE_GTP_KICKS)
    if getter_code[:0x24] != struct.pack(
        "<9I",
        0xD503245F,
        0x529F0688,
        0x8B080008,
        0xB9400108,
        0x34000068,
        0xB944E800,
        0xD65F03C0,
        0x52800020,
        0xD65F03C0,
    ):
        raise ValueError("unexpected GVDM zero-sentinel consumer")

    _setter_address, setter_code = symbol_code(image, SET_GVDM_MODE)
    require_instruction_words_at(
        setter_code,
        "GVDM runtime mode writer",
        {
            0x2C: 0x529F0688,
            0x30: 0x8B080016,
            0x34: 0x2A010048,
            0x38: 0x7100011F,
            0x3C: 0x1A8303F8,
            0x40: 0xB94002C8,
            0x44: 0x6B01011F,
            0xE8: 0xAA1403E1,
            0xEC: 0xF2F303B0,
            0xF0: 0xD73F0910,
            0xF4: 0xB90002D4,
        },
    )
    callers = find_direct_symbol_callers(image, symbols[SET_GVDM_MODE])
    expected_callers = {PERF_COUNTER_SOURCE_STOP, PERF_COUNTER_LOCK_ACCESS}
    if callers != expected_callers:
        raise ValueError(f"unexpected GVDM mode writers: {sorted(callers)}")
    if find_authenticated_target_references(image, symbols[SET_GVDM_MODE]):
        raise ValueError("GVDM mode writer unexpectedly appears in a virtual table")

    return {
        "scalars": [
            {
                "role": 1,
                "platform_offset": 0xF7C0,
                "shared_offset": 0x300,
                "value": 12,
                "producer": G17_DEFAULT_USC_MAX_TGMEM,
                "vtable_slot": G17_DEFAULT_USC_MAX_TGMEM_VTABLE_SLOT,
            },
            {
                "role": 0,
                "platform_offset": 0xF834,
                "shared_offset": 0x304,
                "value": 0,
                "producer": "zero/default GVDM mode before performance-counter access",
                "runtime_writer": SET_GVDM_MODE,
                "runtime_writer_callers": sorted(callers),
            },
        ],
        "calibration": {
            "platform_offset": 0xF790,
            "shared_offset": 0x479,
            "roles": [0, 1],
            "bytes": 0x10,
            "initial_bytes": bytes(0x10).hex(),
        },
    }


def recover_g17_zero_initialized_allocations(code: bytes) -> list[dict[str, object]]:
    require_instruction_sequence(
        code,
        "role-0 0x68-byte region clear",
        (
            0xF9417268,  # ldr x8, [x19, #0x2e0]
            0xF900311F,  # str xzr, [x8, #0x60]
            0x6F00E400,
            0xAD020100,
            0xAD010100,
            0xAD000100,
        ),
    )
    require_instruction_sequence(
        code,
        "role-0 0x800-byte region clear",
        (
            0xF9417660,  # ldr x0, [x19, #0x2e8]
            0x52810001,  # mov w1, #0x800
            0x94AA5CC1,  # bzero
        ),
    )
    require_instruction_sequence(
        code,
        "shared 0x88-byte control block clear",
        (
            0xF9417E68,  # ldr x8, [x19, #0x2f8]
            0xF900411F,  # str xzr, [x8, #0x80]
            0x6F00E400,
            0xAD030100,
            0xAD020100,
            0xAD010100,
            0xAD000100,
        ),
    )
    return [
        {
            "name": "role0_region_26c",
            "bytes": 0x68,
            "host_cpu_member": 0x2E0,
            "host_gpu_member": 0x328,
            "firmware_shared_offsets": [{"role": 0, "offset": 0x26C}],
        },
        {
            "name": "role0_region_274",
            "bytes": 0x800,
            "host_cpu_member": 0x2E8,
            "host_gpu_member": 0x330,
            "firmware_shared_offsets": [{"role": 0, "offset": 0x274}],
        },
        {
            "name": "shared_control",
            "bytes": 0x88,
            "host_cpu_member": 0x2F8,
            "host_gpu_member": 0x340,
            "firmware_shared_offsets": [
                {"role": 0, "offset": 0x10},
                {"role": 1, "offset": 0x10},
            ],
        },
    ]


def recover_g17_role0_bootstrap_regions(code: bytes) -> list[dict[str, object]]:
    require_instruction_sequence(
        code,
        "role-0 bootstrap region clears",
        (
            0xF9416260,  # ldr x0, [x19, #0x2c0]
            0x52818301,  # mov w1, #0xc18
            0x94AA5EB6,  # bzero
            0xF9416660,  # ldr x0, [x19, #0x2c8]
            0x52820901,  # mov w1, #0x1048
            0x94AA5EB3,  # bzero
            0xF9416A60,  # ldr x0, [x19, #0x2d0]
            0x5281C201,  # mov w1, #0xe10
            0x94AA5EB0,  # bzero
        ),
    )
    require_instruction_sequence(
        code,
        "role-0 bootstrap sentinels",
        (
            0xF9416668,  # ldr x8, [x19, #0x2c8]
            0x12800009,  # mov w9, #-1
            0xB90A1909,  # str w9, [x8, #0xa18]
            0xB90A3109,  # str w9, [x8, #0xa30]
        ),
    )
    return [
        {
            "name": "role0_region_254",
            "bytes": 0xC18,
            "host_cpu_member": 0x2C0,
            "host_gpu_member": 0x308,
            "firmware_shared_offset": 0x254,
            "initial": "zero",
        },
        {
            "name": "role0_region_25c",
            "bytes": 0x1048,
            "host_cpu_member": 0x2C8,
            "host_gpu_member": 0x310,
            "firmware_shared_offset": 0x25C,
            "initial": "zero_with_sentinels",
            "sentinels": [
                {"offset": 0xA18, "bytes": 4, "value": 0xFFFFFFFF},
                {"offset": 0xA30, "bytes": 4, "value": 0xFFFFFFFF},
            ],
        },
        {
            "name": "role0_region_264",
            "bytes": 0xE10,
            "host_cpu_member": 0x2D0,
            "host_gpu_member": 0x318,
            "firmware_shared_offset": 0x264,
            "initial": "zero",
        },
    ]


def recover_g17_pio_mappings(image: bytes) -> dict[str, object]:
    """Recover G17C firmware PIO records from the selected virtual table.

    The table itself identifies accelerator PIO descriptor indices and
    offsets inside IODeviceMemory range zero.  The base configureDevice path
    turns each primary table entry into a physical address and the later
    initFirmwareData loop copies the descriptor into the 0x28-byte firmware
    record.  Pin all three links before reporting the records.
    """

    symbols = macho_symbols(image)
    required = (BASE_CONFIGURE_DEVICE, G17_PIO_TABLE, G17_PIO_TABLE_LENGTH)
    missing = [name for name in required if name not in symbols]
    if missing:
        raise ValueError(f"Mach-O has no {missing[0]} symbol")

    table_target = recover_vtable_target(
        image, G17_ACCELERATOR_VTABLE, G17_PIO_TABLE_VTABLE_SLOT
    )
    if table_target != symbols[G17_PIO_TABLE]:
        raise ValueError(f"unexpected G17 PIO table target {table_target:#x}")
    length_target = recover_vtable_target(
        image, G17_ACCELERATOR_VTABLE, G17_PIO_TABLE_LENGTH_VTABLE_SLOT
    )
    if length_target != symbols[G17_PIO_TABLE_LENGTH]:
        raise ValueError(f"unexpected G17 PIO table length target {length_target:#x}")

    length_address, length_code = symbol_code(image, G17_PIO_TABLE_LENGTH)
    del length_address
    if length_code[:12] != struct.pack("<3I", 0xD503245F, 0x52800260, 0xD65F03C0):
        raise ValueError("unexpected G17 PIO table length provider")

    table_address, table_code = symbol_code(image, G17_PIO_TABLE)
    if len(table_code) < 16:
        raise ValueError("truncated G17 PIO table provider")
    getter_words = struct.unpack_from("<4I", table_code)
    if getter_words[0] != 0xD503245F or getter_words[3] != 0xD65F03C0:
        raise ValueError("unexpected G17 PIO table provider prologue")
    page = decode_adrp(table_address + 4, getter_words[1])
    addition = decode_add_immediate(getter_words[2])
    if page is None or addition is None:
        raise ValueError("G17 PIO table provider has no ADRP/add address")
    page_register, page_address = page
    destination, source, immediate = addition
    if page_register != 0 or destination != 0 or source != 0:
        raise ValueError("G17 PIO table provider uses an unexpected register")
    data_address = page_address + immediate

    expected_table = (
        (17, 0x000000, 0x21500, 0, 0x00000000, 0, 0, 0),
        (47, 0x023D00, 0x00200, 0, 0x00000000, 0, 0, 0),
        (26, 0xD04000, 0x08000, 0, 0xDADADADA, 0, 0, 0),
        (29, 0xD10000, 0x04000, 0, 0xDADADADA, 0, 0, 0),
        (31, 0xD40000, 0x04000, 0, 0xDADADADA, 0, 0, 0),
        (33, 0xD44000, 0x04000, 0, 0xDADADADA, 0, 0, 0),
        (34, 0xD4C000, 0x00200, 0, 0xDADADADA, 0, 0, 0),
        (28, 0xD50000, 0x10000, 0, 0xDADADADA, 0, 0, 0),
        (32, 0xD60000, 0x20000, 0, 0xDADADADA, 0, 0, 0),
        (35, 0xE00000, 0x04000, 0, 0xDADADADA, 0, 0, 0),
        (37, 0xE40000, 0x04000, 0, 0xDADADADA, 0, 0, 0),
        (43, 0xE60000, 0x00058, 0, 0xDADADADA, 0, 0, 0),
        (20, 0xFFFFFFFF, 0, 0, 0, 0, 0, 0),
        (21, 0xFFFFFFFF, 0, 0, 0, 0, 0, 0),
        (18, 0xFFFFFFFF, 0, 0, 0, 0, 0, 0),
        (19, 0xFFFFFFFF, 0, 0, 0, 0, 0, 0),
        (24, 0xFFFFFFFF, 0, 0, 0, 0, 0, 0),
        (23, 0xFFFFFFFF, 0, 0, 0, 0, 0, 0),
        (44, 0xFFFFFFFF, 0, 0, 0xD24000, 0x100, 0, 0),
    )
    data_offset = virtual_to_file(image, data_address)
    data_bytes = len(expected_table) * 0x20
    if data_offset + data_bytes > len(image):
        raise ValueError("truncated G17 PIO relative-offset table")
    actual_table = tuple(
        struct.unpack_from("<8I", image, data_offset + index * 0x20)
        for index in range(len(expected_table))
    )
    if actual_table != expected_table:
        raise ValueError("unexpected G17 PIO relative-offset table contents")

    _configure_address, configure_code = symbol_code(image, BASE_CONFIGURE_DEVICE)
    # These exact sites establish the descriptor-array clear, default flag 2,
    # all twelve active descriptor flags, both virtual dispatches, and the
    # primary IODeviceMemory-to-source-record copy path.
    require_instruction_words_at(
        configure_code,
        "G17 PIO source producer",
        {
            0x1010: 0x911E0276,
            0x1014: 0xAA1603E0,
            0x1018: 0x529C3601,
            0x101C: 0x94AB642B,
            0x1020: 0x52800054,
            0x1024: 0xB90CAAB4,
            0x1064: 0xB9044314,
            0x1094: 0xB9000354,
            0x10FC: 0xB9087354,
            0x1130: 0xB90CAB54,
            0x1198: 0xB9044334,
            0x11CC: 0xB9087B34,
            0x1200: 0xB90CB334,
            0x1234: 0xB9000B94,
            0x1268: 0xB9044394,
            0x12B8: 0xB90CB394,
            0x1464: 0xB90442F4,
            0x17EC: 0x52822D08,
            0x17F4: 0xF948B609,
            0x1804: 0xD73F0931,
            0x182C: 0x52822E08,
            0x1834: 0xF948BA09,
            0x1844: 0xD73F0931,
            0x1848: 0xB4000BC0,
            0x1850: 0x52808714,
            0x1854: 0x529B5B5A,
            0x1858: 0x72BB5B5A,
            0x187C: 0xB9400708,
            0x1888: 0xB9400308,
            0x18A4: 0x39400128,
            0x18BC: 0xF9400208,
            0x18C4: 0x52800001,
            0x18CC: 0xD73F0910,
            0x18D0: 0x29402309,
            0x18D4: 0x9BB47D29,
            0x18EC: 0x8B080009,
            0x18F0: 0xF9000549,
            0x18F4: 0xF9400709,
            0x18F8: 0xB9020949,
            0x18FC: 0xF9010948,
            0x1900: 0xB900055C,
        },
    )

    records = [
        {
            "index": kind,
            "relative_offset": relative_offset,
            "total_size": size,
            "element_size": size,
            "flags": 2,
            "writable": True,
        }
        for kind, relative_offset, size, *_tail in expected_table
        if relative_offset != 0xFFFFFFFF
    ]
    return {
        "table_vtable_slot": G17_PIO_TABLE_VTABLE_SLOT,
        "length_vtable_slot": G17_PIO_TABLE_LENGTH_VTABLE_SLOT,
        "table_address": data_address,
        "table_entries": len(expected_table),
        "source_record_stride": 0x438,
        "firmware_record_offset": 0x640,
        "firmware_record_stride": 0x28,
        "records": records,
        "alternate_entries": [
            {
                "index": entry[0],
                "primary_offset": entry[1],
                "alternate_offset": entry[4],
                "alternate_size": entry[5],
            }
            for entry in expected_table
            if entry[1] == 0xFFFFFFFF
        ],
    }


def recover_g17_pio_uat_mapping(image: bytes) -> dict[str, object]:
    """Recover the checked G17 firmware-PIO UAT mapping contract."""

    symbols = macho_symbols(image)
    required = (
        ACCELERATOR_START,
        INIT_FIRMWARE_DATA,
        CREATE_FW_PIO_MAPPING,
        CREATE_FW_GPU_MAPPING,
        GART_RANGES,
    )
    missing = [name for name in required if name not in symbols]
    if missing:
        raise ValueError(f"Mach-O has no {missing[0]} symbol")

    start_address, start_code = symbol_code(image, ACCELERATOR_START)
    require_instruction_words_at(
        start_code,
        "G17 GART range table initialization",
        {
            0xEA0: 0x5293F018,  # mov w24, #0x9f80: ranges 7..12 and 15
            0xEA4: 0xB0FF41B9,  # adrp x25, gart_ranges
            0xEA8: 0x911D8339,  # add x25, x25, #0x760
            0xECC: 0x8B081728,  # select 0x20-byte record by range number
            0xED8: 0xA9402909,  # load base and size
            0xEDC: 0x9ADC2536,  # base >> UAT page shift
            0xEE0: 0x9ADC2549,  # size >> UAT page shift
        },
    )
    page = decode_adrp(start_address + 0xEA4, 0xB0FF41B9)
    addition = decode_add_immediate(0x911D8339)
    if page is None or addition is None:
        raise ValueError("G17 GART range table address is not materialized")
    page_register, page_address = page
    destination, source, immediate = addition
    table_address = page_address + immediate
    if (page_register, destination, source) != (25, 25, 25):
        raise ValueError("G17 GART range table uses unexpected registers")
    if table_address != symbols[GART_RANGES]:
        raise ValueError(f"unexpected G17 GART range table {table_address:#x}")

    range_number = 10
    range_offset = virtual_to_file(image, table_address + range_number * 0x20)
    if range_offset + 0x20 > len(image):
        raise ValueError("truncated G17 firmware-PIO GART range")
    va_start, va_size, range_flags, reserved = struct.unpack_from(
        "<4Q", image, range_offset
    )
    expected_range = (0xFFFFFC2180000000, 0x01400000, 0x18, 0)
    if (va_start, va_size, range_flags, reserved) != expected_range:
        raise ValueError("unexpected G17 firmware-PIO GART range")

    pio_address, pio_code = symbol_code(image, CREATE_FW_PIO_MAPPING)
    require_instruction_words_at(
        pio_code,
        "G17 firmware-PIO physical alignment",
        {
            0x30: 0x710004BF,  # cmp count, #1
            0x38: 0xF9400028,  # load the sole physical address
            0x50: 0x0A2A010A,  # recover its low-page offset
            0x54: 0xB900006A,  # publish low-page offset
            0x6C: 0x8A0A0100,  # align physical address down
            0x74: 0x8B224108,  # add requested element size
            0x84: 0x8A090108,  # align mapping end up
            0x88: 0xCB000101,  # obtain aligned mapping length
            0x8C: 0x7100029F,  # writable flag
            0x90: 0x52800068,  # writable IOMemoryDescriptor options = 3
            0x94: 0x1A9F1502,  # read-only options = 1
            0xA4: 0xAA1503E0,
            0xA8: 0xAA1603E1,
            0xAC: 0xAA1403E2,
            0xB0: 0xAA1303E3,
        },
    )
    mapping_call = decode_bl_target(
        pio_address + 0xB4, struct.unpack_from("<I", pio_code, 0xB4)[0]
    )
    if mapping_call != symbols[CREATE_FW_GPU_MAPPING]:
        raise ValueError(f"unexpected G17 firmware-PIO mapper target {mapping_call}")

    _gpu_address, gpu_code = symbol_code(image, CREATE_FW_GPU_MAPPING)
    require_instruction_words_at(
        gpu_code,
        "G17 firmware-PIO mapping options",
        {
            0x38: 0xD3607EC8,  # GART range number in bits 35:32
            0x3C: 0x710026DF,  # special-case range 9 only
            0x48: 0x710002BF,  # writable flag
            0x4C: 0x528000E9,  # writable mapping options = 7
            0x50: 0xD28000AA,
            0x54: 0xF2C0200A,  # read-only options = 0x10000000005
            0x58: 0x9A8A1129,
            0x90: 0xAA080122,  # range tag | mapping options
        },
    )

    _init_address, init_code = symbol_code(image, INIT_FIRMWARE_DATA)
    require_instruction_sequence(
        init_code,
        "G17 firmware-PIO virtual-address publication",
        (
            0x928108F5,  # destination starts at config +0x648
            0x52835917,  # host mapping-object array at +0x1ac8
            0x52838E18,  # physical low-page offsets at +0x1c70
            0x14000009,
            0xF9415E68,
            0x8B150108,
            0xF907491F,
            0x910022F7,
            0x91001318,
            0x9110E294,
            0xB100A2B5,
            0x540005A0,
            0xF9400688,
            0xB4FFFEE8,
            0xB9420A88,
            0x34FFFEA8,
            0x39400288,
            0x3707FE68,
        ),
    )
    require_instruction_sequence(
        init_code,
        "G17 firmware-PIO mapped-address conversion",
        (
            0x8B170268,  # load mapping object by record index
            0xF9400100,
            0xF9400010,
            0xAA0003F1,
            0xF2F9B431,
            0xDAC11A30,
            0xD2802B11,  # mapping getGPUVirtualAddress vtable slot 0x158
            0x8B110210,
            0xF9400208,
            0xF2E63530,
            0xD73F0910,
            0xAA1603F1,
            0x8B180268,
            0xB9400108,  # add the physical low-page offset
            0xF9400270,
            0xDAC11A30,
            0xAA1003F1,
            0xDAC147F1,
            0xEB11021F,
            0x54000040,
            0xD4388E40,
            0x910B6209,  # firmware VA conversion vtable slot 0x2d8
            0xF9416E0A,
            0x8B080001,
            0xAA1303E0,
            0x52800002,
            0xAA0903F1,
            0xF2F24A11,
            0xD73F0951,
            0xF9415E68,
            0x8B150108,
            0xF9074900,  # store converted VA in config record +0x08
        ),
    )

    return {
        "gart_range": range_number,
        "va_start": va_start,
        "va_size": va_size,
        "va_end": va_start + va_size,
        "range_flags": range_flags,
        "uat_page_bytes": 0x4000,
        "single_element_mapping": "align_down_physical_and_round_up_end",
        "writable_descriptor_options": 3,
        "read_only_descriptor_options": 1,
        "writable_gpu_mapping_options": 7,
        "read_only_gpu_mapping_options": 0x10000000005,
        "firmware_virtual_address": "mapping_gpu_va_plus_physical_page_offset",
    }


def recover_driver_hardware_config_layout(
    base_init_code: bytes, base_power_code: bytes, arm_power_code: bytes
) -> dict[str, object]:
    """Recover table boundaries written by the pinned G17 host driver.

    Validate loop instructions as well as constants so a coincidental use of
    an offset elsewhere cannot become a claimed firmware structure field.
    """

    require_instruction_sequence(
        base_init_code,
        "color-matrix copy loop",
        (
            0x5280040A,  # mov w10, #32
            0xF940010B,  # ldr x11, [x8]
            0xF9001D2B,  # str x11, [x9, #0x38]
            0xF941810B,  # ldr x11, [x8, #0x300]
            0xF9019D2B,  # str x11, [x9, #0x338]
            0xF940050B,
            0xF900212B,
            0xF941850B,
            0xF901A12B,
            0xF940090B,
            0xF900252B,
            0xF941890B,
            0xF901A52B,
            0x91006108,  # add x8, x8, #0x18
            0x91006129,  # add x9, x9, #0x18
            0xF100054A,  # subs x10, x10, #1
            0x54FFFE21,  # b.ne
        ),
    )
    require_instruction_sequence(
        base_init_code,
        "I/O-mapping copy loop",
        (
            0xD2800008,  # mov x8, #0
            0xD280000A,  # mov x10, #0
            0xF9415E69,  # ldr config CPU address, [x19, #0x2b8]
            0xF9129520,
            0xF9414E60,
            0x8B08000B,
            0xB949896C,
            0xB947856D,
            0x1B0C7DAD,
            0x8B0A012E,
            0xB90651CD,  # record +0x10
            0xF943C56D,
            0xF90321CD,  # config +0x640 + record
            0xF944C96D,
            0xF9032DCD,  # record +0x18
            0xB90655CC,  # record +0x14
            0xB947816B,
            0x121F016B,
            0xB90661CB,  # record +0x20
            0xF90325DF,  # record +0x08
            0x9100A14A,  # add x10, x10, #0x28
            0x9110E108,  # add x8, x8, #0x438
            0xF121215F,  # cmp x10, #0x848
            0x54FFFDC1,  # b.ne
        ),
    )

    base_stores = {
        immediate
        for _offset, word in words(base_power_code)
        if (store := decode_str_unsigned(word)) is not None
        for _source, base, immediate, width in (store,)
        if base == 8 and width == 4
    }
    frequency_offsets = set(range(0xFC8, 0x1008, 4))
    secondary_frequency_offsets = set(range(0x1808, 0x1848, 4))
    required_base_stores = {0xFC4} | frequency_offsets | secondary_frequency_offsets
    if not required_base_stores.issubset(base_stores):
        missing = sorted(required_base_stores - base_stores)
        raise ValueError(
            "hardware-config producer has incomplete performance tables: "
            f"{[hex(offset) for offset in missing]}"
        )

    require_instruction_sequence(
        base_power_code,
        "primary and SRAM frequency-table conversion",
        (
            0xF9415E68,  # hardware config at firmware object +0x2b8
            0xB90FC509,  # maximum performance-state index -> +0xfc4
            0xF9414E69,  # accelerator at firmware object +0x298
            0x91406D29,  # accelerator +0x1b000
            0xB943192B,  # primary frequency[0] at +0x1b318
            0x529BD06A,
            0x72A8636A,  # reciprocal multiplier 0x431bde83
            0x9BAA7D6B,
            0xD372FD6B,  # unsigned product >> 50: Hz to MHz
            0xB90FC90B,  # primary frequency[0] -> config +0xfc8
            0xB94B612B,  # SRAM frequency[0] at +0x1bb60
            0x9BAA7D6B,
            0xD372FD6B,
            0xB918090B,  # SRAM frequency[0] -> config +0x1808
        ),
    )

    require_instruction_sequence(
        arm_power_code,
        "voltage-table loop setup",
        (
            0xF9415E6B,  # ldr config CPU address, [x19, #0x2b8]
            0x5282010A,  # mov w10, #0x1008
            0x8B0A016A,  # add x10, x11, x10
            0x91041108,
            0x5283110C,  # mov w12, #0x1888
            0x8B0C016B,  # add x11, x11, x12
            0x5280020C,  # mov w12, #16
        ),
    )
    arm_stores = {
        (base, immediate, width)
        for _offset, word in words(arm_power_code)
        if (store := decode_str_unsigned(word)) is not None
        for _source, base, immediate, width in (store,)
    }
    voltage_columns = {
        (10, offset, 4) for offset in range(0, 0x40, 4)
    } | {(10, 0x400 + offset, 4) for offset in range(0, 0x40, 4)}
    if not voltage_columns.issubset(arm_stores):
        raise ValueError("hardware-config producer has incomplete 16-column voltage rows")
    require_instruction_sequence(
        arm_power_code,
        "voltage-table row advance",
        (
            0xBC5C0100,
            0xBC1C0160,  # table at 0x1848 through x11 - 0x40
            0x91010129,  # add source row, #0x40
            0xBC404500,
            0xBC004560,  # table at 0x1888, post-increment #4
            0x9101014A,  # add destination row, #0x40
            0xF100058C,  # subs x12, x12, #1
            0x54FFF721,  # b.ne
        ),
    )
    require_instruction_sequence(
        arm_power_code,
        "linear-power table binding",
        (
            0xF9415E68,
            0x52831909,  # mov w9, #0x18c8
            0x8B090101,  # add x1, x8, x9
            0x52800002,  # mov w2, #0
        ),
    )
    for offset, materialization in (
        (0x1908, (0x5283210B, 0x8B0B0134)),
        (0x1948, (0x5283290B, 0x8B0B012B)),
        (0x19C8, (0x52833909, 0x8B09010A)),
    ):
        require_instruction_sequence(
            arm_power_code,
            f"table binding at {offset:#x}",
            materialization,
        )

    return {
        "color_matrices": {
            "offset": 0x38,
            "records": 64,
            "record_bytes": 0x18,
            "banks": 2,
        },
        "io_mappings": {"offset": 0x640, "records": 53, "record_bytes": 0x28},
        "performance_states": {
            "capacity": 16,
            "max_state_offset": 0xFC4,
            "frequency_offset": 0xFC8,
            "voltage_offset": 0x1008,
            "sram_voltage_offset": 0x1408,
            "secondary_frequency_offset": 0x1808,
            "primary_frequency_source_offset": 0x1B318,
            "secondary_frequency_source_offset": 0x1BB60,
            "frequency_conversion": {
                "input": "Hz",
                "output": "MHz",
                "multiplier": 0x431BDE83,
                "right_shift": 50,
            },
            "derived_table_offsets": [0x1848, 0x1888, 0x18C8, 0x1908, 0x1948],
        },
    }


def recover_g17_address_space_layout(
    image: bytes, base_init_code: bytes
) -> dict[str, object]:
    """Recover the complete fixed 0x38-byte hardware-config prefix.

    The final word is the optional YUV CSC allocation.  G17 selects a stub
    which returns success without allocating it, and initFirmwareData writes
    zero when that mapping is absent.
    """

    symbols = macho_symbols(image)
    required = (G17_SETUP_CSC_ALLOCATION, CONVERT_GPU_VA_TO_FW_VA)
    missing = [name for name in required if name not in symbols]
    if missing:
        raise ValueError(f"Mach-O is missing G17 address-space symbols: {missing}")

    csc_provider = recover_vtable_target(
        image,
        G17_ACCELERATOR_VTABLE,
        G17_SETUP_CSC_ALLOCATION_VTABLE_SLOT,
    )
    if csc_provider != symbols[G17_SETUP_CSC_ALLOCATION]:
        raise ValueError(f"unexpected G17 CSC allocation provider {csc_provider:#x}")
    _address, csc_code = symbol_code(image, G17_SETUP_CSC_ALLOCATION)
    if csc_code != struct.pack(
        "<3I",
        0xD503245F,  # bti c
        0x52800020,  # mov w0, #1
        0xD65F03C0,  # ret
    ):
        raise ValueError("G17 CSC allocation provider is not the checked no-op")

    converter = recover_vtable_target(
        image, G17_FIRMWARE_VTABLE, FIRMWARE_ADDRESS_CONVERSION_VTABLE_SLOT
    )
    if converter != symbols[CONVERT_GPU_VA_TO_FW_VA]:
        raise ValueError(f"unexpected G17 firmware address converter {converter:#x}")
    _address, converter_code = symbol_code(image, CONVERT_GPU_VA_TO_FW_VA)
    if converter_code != struct.pack("<3I", 0xD503245F, 0xAA0103E0, 0xD65F03C0):
        raise ValueError("G17 firmware address conversion is not the checked identity mapping")

    # The constant vector supplies offsets 0x00 and 0x08.  Keep its
    # PC-relative load tied to the checked instruction offsets so a driver
    # update cannot silently reuse unrelated read-only data.
    fixed_pair = read_adrp_load(
        image,
        symbols[INIT_BASE_FIRMWARE_DATA],
        base_init_code,
        0x147C,
        0x1480,
        16,
    )
    if len(fixed_pair) != 16:
        raise ValueError("truncated G17 hardware-config address constant")
    userspace_va_map, userspace_va_limit = struct.unpack("<QQ", fixed_pair)
    if (userspace_va_map, userspace_va_limit) != (0x6F00000000, 0xFFC00000):
        raise ValueError(
            "unexpected G17 hardware-config userspace VA constants: "
            f"{userspace_va_map:#x}, {userspace_va_limit:#x}"
        )

    require_instruction_words_at(
        base_init_code,
        "G17 hardware-config address-space prefix",
        {
            0x1478: 0xF9415E68,  # hardware-config CPU address
            0x1480: 0x3DC35920,  # load checked 16-byte constant
            0x1484: 0xD2C00209,  # 0x10_00000000
            0x1488: 0x4E080D21,  # duplicate into both USC words
            0x148C: 0xAD000500,  # config +0x00 through +0x1f
            0x1490: 0xB27143E9,  # begin 0x2ff_ffff8000
            0x1494: 0xF2C05FE9,
            0x1498: 0xF9001109,  # config +0x20
        },
    )
    require_instruction_words_at(
        base_init_code,
        "G17 optional CSC address publication",
        {
            0x1538: 0x91406808,  # accelerator +0x1a000
            0x153C: 0x910D0108,  # optional mapping member +0x340
            0x1540: 0xF9400108,
            0x1544: 0xB40001C8,  # skip getGPUVirtualAddress when null
            0x1558: 0xD2802B11,  # mapping vtable slot 0x158
            0x1570: 0xAA0003E8,
            0x1574: 0xF9415E69,  # hardware-config CPU address
            0x157C: 0xF9001928,  # config +0x30, including zero path
        },
    )
    require_instruction_words_at(
        base_init_code,
        "G17 timestamp-area address publication",
        {
            0x16A8: 0x910B6208,  # firmware converter vtable slot 0x2d8
            0x16B0: 0xD2B02801,
            0x16B4: 0xF2DF8421,
            0x16B8: 0xF2FFFFE1,  # 0xfffffc2181400000
            0x16BC: 0xAA1303E0,
            0x16C0: 0x52800002,
            0x16F0: 0xF9001500,  # config +0x28
        },
    )

    return {
        "offset": 0,
        "bytes": 0x38,
        "userspace_va_map": userspace_va_map,
        "userspace_va_limit": userspace_va_limit,
        "usc_start": [0x1000000000, 0x1000000000],
        "unknown_page": 0x2FFFFFF8000,
        "timestamp_area_base": 0xFFFFFC2181400000,
        "yuv_csc_table_address": 0,
        "csc_allocation_vtable_slot": G17_SETUP_CSC_ALLOCATION_VTABLE_SLOT,
        "csc_allocation_provider": G17_SETUP_CSC_ALLOCATION,
        "firmware_address_conversion": CONVERT_GPU_VA_TO_FW_VA,
    }


def recover_g17_color_matrices(image: bytes) -> dict[str, object]:
    """Recover both 32-record CSC coefficient banks selected by G17."""

    symbols = macho_symbols(image)
    required = (
        G17_GENERATE_CSC_COEFFICIENTS,
        G17_TPU_CSC_COEFFICIENTS,
        G17_PBE_CSC_COEFFICIENTS,
    )
    missing = [name for name in required if name not in symbols]
    if missing:
        raise ValueError(f"Mach-O is missing G17 CSC coefficient symbols: {missing}")

    provider = recover_vtable_target(
        image,
        G17_ACCELERATOR_VTABLE,
        G17_GENERATE_CSC_COEFFICIENTS_VTABLE_SLOT,
    )
    if provider != symbols[G17_GENERATE_CSC_COEFFICIENTS]:
        raise ValueError(f"unexpected G17 CSC coefficient provider {provider:#x}")

    function_address, code = symbol_code(image, G17_GENERATE_CSC_COEFFICIENTS)
    if len(code) != 0x74:
        raise ValueError(f"unexpected G17 CSC coefficient producer size {len(code):#x}")
    expected_words = {
        0x00: 0xD503245F,
        0x04: 0xD2800008,
        0x08: 0x91406809,
        0x0C: 0x910D2129,
        0x10: 0x9140680A,
        0x14: 0x910D614A,
        0x18: 0x9140680B,
        0x1C: 0x9119616B,
        0x30: 0x8B08018E,
        0x34: 0x8B08012F,
        0x38: 0x8B0801B0,
        0x3C: 0x3DC001C0,
        0x40: 0x3D8001E0,
        0x44: 0x3DC00200,
        0x48: 0x3D80C1E0,
        0x4C: 0x8B08014F,
        0x50: 0x8B080171,
        0x54: 0xFD4009C0,
        0x58: 0xFD0001E0,
        0x5C: 0xFD400A00,
        0x60: 0xFD000220,
        0x64: 0x91006108,
        0x68: 0xF10C011F,
        0x6C: 0x54FFFE21,
        0x70: 0xD65F03C0,
    }
    require_instruction_words_at(code, "G17 CSC coefficient producer", expected_words)

    # Resolve both ADRP/add pairs instead of trusting their symbol names alone.
    for adrp_offset, add_offset, symbol in (
        (0x20, 0x24, G17_TPU_CSC_COEFFICIENTS),
        (0x28, 0x2C, G17_PBE_CSC_COEFFICIENTS),
    ):
        adrp = decode_adrp(
            function_address + adrp_offset,
            struct.unpack_from("<I", code, adrp_offset)[0],
        )
        add = decode_add_immediate(struct.unpack_from("<I", code, add_offset)[0])
        if adrp is None or add is None:
            raise ValueError(f"missing G17 CSC source address for {symbol}")
        page_register, page = adrp
        destination, source, immediate = add
        if destination != page_register or source != page_register:
            raise ValueError(f"malformed G17 CSC source address for {symbol}")
        if page + immediate != symbols[symbol]:
            raise ValueError(f"G17 CSC producer does not reference {symbol}")

    banks = []
    for name in (G17_TPU_CSC_COEFFICIENTS, G17_PBE_CSC_COEFFICIENTS):
        _address, blob = symbol_code(image, name)
        if len(blob) != 0x300:
            raise ValueError(f"unexpected G17 CSC bank size for {name}: {len(blob):#x}")
        values = struct.unpack("<384h", blob)
        nonzero_records = []
        for index in range(32):
            coefficients = list(values[index * 12 : (index + 1) * 12])
            if any(coefficients):
                nonzero_records.append(
                    {"index": index, "coefficients": coefficients}
                )
        banks.append(
            {
                "source": name,
                "records": 32,
                "record_bytes": 0x18,
                "nonzero_records": nonzero_records,
            }
        )

    return {
        "offset": 0x38,
        "records": 64,
        "record_bytes": 0x18,
        "provider_vtable_slot": G17_GENERATE_CSC_COEFFICIENTS_VTABLE_SLOT,
        "provider": G17_GENERATE_CSC_COEFFICIENTS,
        "banks": banks,
    }


def recover_g17_hardware_config_constants(
    image: bytes, base_init_code: bytes, arm_init_code: bytes
) -> dict[str, object]:
    """Recover fixed scalar defaults and the absent G17 border-color table."""

    feature_defaults = recover_g17_feature_defaults(image, base_init_code)

    symbols = macho_symbols(image)
    required = (
        G17_GET_BORDER_COLOR_TABLE_GPU_ADDRESS,
        INIT_BASE_FIRMWARE_DATA,
        INIT_FIRMWARE_DATA,
    )
    missing = [name for name in required if name not in symbols]
    if missing:
        raise ValueError(f"Mach-O is missing G17 hardware-config symbols: {missing}")

    provider = recover_vtable_target(
        image,
        G17_ACCELERATOR_VTABLE,
        G17_BORDER_COLOR_TABLE_ADDRESS_VTABLE_SLOT,
    )
    if provider != symbols[G17_GET_BORDER_COLOR_TABLE_GPU_ADDRESS]:
        raise ValueError(
            f"unexpected G17 border-color table address provider {provider:#x}"
        )
    _address, provider_code = symbol_code(
        image, G17_GET_BORDER_COLOR_TABLE_GPU_ADDRESS
    )
    if provider_code != struct.pack(
        "<3I", 0xD503245F, 0xD2800000, 0xD65F03C0
    ):
        raise ValueError("G17 border-color table address provider does not return zero")

    base_address = symbols[INIT_BASE_FIRMWARE_DATA]
    base_vector = read_adrp_load(
        image, base_address, base_init_code, 0x13B0, 0x13B4, 16
    )
    arm_vector = read_adrp_load(
        image,
        symbols[INIT_FIRMWARE_DATA],
        arm_init_code,
        0xAC,
        0xB0,
        16,
    )
    debug_flags = read_adrp_load(
        image, base_address, base_init_code, 0x13DC, 0x13E0, 1
    )
    if base_vector != struct.pack("<4I", 0, 0, 0, 1):
        raise ValueError("unexpected G17 base hardware-config constant vector")
    if arm_vector != struct.pack("<4I", 0, 1, 1, 0):
        raise ValueError("unexpected G17 ARM hardware-config constant vector")
    if debug_flags != b"\0":
        raise ValueError("G17 hardware-config debug flags do not start disabled")

    require_instruction_words_at(
        base_init_code,
        "G17 base hardware-config scalar constants",
        {
            0x1264: 0xF9415E68,
            0x1268: 0xB90EBD1F,  # config +0xebc = 0
            0x126C: 0x52800036,
            0x1270: 0xB90EC916,  # config +0xec8 = 1
            0x13AC: 0x913AB128,  # config +0xeac
            0x13B4: 0x3DC35540,
            0x13B8: 0x3D800100,
            0x13E4: 0x721C017F,
            0x13E8: 0x5280190B,
            0x13EC: 0x1A9F156B,  # disabled debug flags select 1
            0x13F0: 0xB90ED52B,  # config +0xed4
            0x165C: 0xF9415E68,
            0x1660: 0xF9031D00,  # config +0x638 = border-color address
            0x1664: 0x3968A6A9,
            0x1668: 0x5301052A,
            0x166C: 0xB90EA10A,  # debug bit 1 -> config +0xea0
            0x1670: 0x53041129,
            0x1674: 0xB90EA909,  # debug bit 4 -> config +0xea8
        },
    )
    require_instruction_words_at(
        arm_init_code,
        "G17 ARM hardware-config scalar constants",
        {
            0x4C: 0x528BB808,  # 24 MHz in kHz
            0x50: 0xB90ED128,  # config +0xed0
            0x58: 0x913B9128,  # config +0xee4
            0x5C: 0xB20003EA,  # two adjacent one-valued words
            0x60: 0xF900010A,
            0x64: 0x528003E8,
            0x68: 0xB90F0528,  # config +0xf04 = 31
            0xB0: 0x3DC35100,
            0xB4: 0x3D83CD20,  # config +0xf30 constant vector
            0x4E0: 0x52800029,
            0x4E4: 0xB90EE109,  # config +0xee0 = 1
        },
    )

    return {
        "border_color_table_address": {
            "offset": 0x638,
            "value": 0,
            "provider_vtable_slot": G17_BORDER_COLOR_TABLE_ADDRESS_VTABLE_SLOT,
            "provider": G17_GET_BORDER_COLOR_TABLE_GPU_ADDRESS,
        },
        "scalar_block": {
            "offset": 0xE90,
            "bytes": 0x134,
            "debug_flags_initial": 0,
            "fixed_u32": {
                "0xeb8": 1,
                **feature_defaults["fixed_u32"],
                "0xec8": 1,
                "0xed0": 24000,
                "0xed4": 1,
                "0xee0": 1,
                "0xee4": 1,
                "0xee8": 1,
                "0xf04": 31,
                "0xf34": 1,
                "0xf38": 1,
            },
            "feature_defaults": feature_defaults,
        },
    }


def recover_g17_setup_config_constants(
    configure_code: bytes, arm_setup_code: bytes
) -> dict[str, object]:
    """Recover scalar defaults published by AGXArmFirmware::setupConfig."""

    # configureDevice uses accelerator +0xf728 as the base for these source
    # fields. It clears the 16-byte source at +0xf7d8 and the word at
    # +0xf76c, then deliberately replaces the latter with 0x31.
    require_instruction_words_at(
        configure_code,
        "G17 setupConfig scalar sources",
        {
            0x34: 0x529EE508,
            0x38: 0x8B080018,
            0x52C: 0xB907067F,  # accelerator +0x704 = 0
            0x5A8: 0x6F00E401,
            0x5AC: 0x3D802F01,  # accelerator +0xf7d8..0xf7e7 = 0
            0x5B8: 0xFC044301,  # accelerator +0xf76c..0xf773 = 0
            0x918: 0x52800008,
            0x91C: 0x52800629,  # replacement value 0x31
            0x920: 0xB9004709,  # -> accelerator +0xf76c
        },
    )
    require_instruction_words_at(
        arm_setup_code,
        "G17 setupConfig scalar publication",
        {
            0x28: 0xF9414E68,
            0x34: 0x529EED8A,
            0x38: 0x8B0A010A,  # accelerator +0xf76c
            0x44: 0xF9415E6C,
            0x5C: 0xB940014B,
            0x60: 0xB90F4D8B,  # -> config +0xf4c
            0x64: 0x3CC6C140,  # accelerator +0xf7d8
            0x68: 0x3D83DD80,  # -> config +0xf70..0xf7f
            0x2FA0: 0xB9470509,  # accelerator +0x704
            0x2FA4: 0xF9415E6A,
            0x2FA8: 0xB90EDD49,  # -> config +0xedc
        },
    )
    return {
        "fixed_u32": {
            "offset": 0xF4C,
            "source_offset": 0xF76C,
            "value": 0x31,
        },
        "zero_u32": {
            "0xedc": {"source_offset": 0x704},
            "0xf70": {"source_offset": 0xF7D8},
            "0xf74": {"source_offset": 0xF7DC},
            "0xf78": {"source_offset": 0xF7E0},
            "0xf7c": {"source_offset": 0xF7E4},
        },
    }


def recover_g17_chip_info(image: bytes, arm_init_code: bytes) -> dict[str, object]:
    """Recover the DeviceTree chip identity copied into config +0xe90."""

    symbols = macho_symbols(image)
    required = (BASE_CONFIGURE_DEVICE, RETRIEVE_CHIP_INFO)
    missing = [name for name in required if name not in symbols]
    if missing:
        raise ValueError(f"Mach-O has no {missing[0]} symbol")
    target = recover_vtable_target(
        image, G17_ACCELERATOR_VTABLE, G17_RETRIEVE_CHIP_INFO_VTABLE_SLOT
    )
    if target != symbols[RETRIEVE_CHIP_INFO]:
        raise ValueError(f"unexpected G17 retrieveChipInfo target {target:#x}")

    _address, configure_code = symbol_code(image, BASE_CONFIGURE_DEVICE)
    _address, retrieve_code = symbol_code(image, RETRIEVE_CHIP_INFO)
    require_instruction_words_at(
        configure_code,
        "G17 chip-info destination",
        {
            0x610: 0x529EF908,
            0x634: 0x91358209,
            0x638: 0xF946B20A,
            0x63C: 0x8B080261,
            0x640: 0xAA1303E0,
            0x64C: 0xD73F0951,
        },
    )
    require_instruction_words_at(
        retrieve_code,
        "G17 DeviceTree chip-info extraction",
        {
            0xBC: 0xB9400008,
            0xC0: 0xB9000288,
            0x154: 0xB9400008,
            0x158: 0x53047D09,
            0x15C: 0x12000908,
            0x160: 0x2900A289,
        },
    )
    require_instruction_words_at(
        arm_init_code,
        "G17 hardware-config chip-info publication",
        {
            0x20: 0xF9414E68,
            0x24: 0x529EF909,
            0x28: 0x8B090108,
            0x2C: 0xF9415E69,
            0x30: 0x3DC00100,
            0x34: 0x3D83A520,
        },
    )
    for property_name in (b"chip-id\0", b"chip-revision\0"):
        if property_name not in image:
            raise ValueError(f"missing {property_name[:-1].decode()} property name")

    return {
        "offset": 0xE90,
        "bytes": 16,
        "source_record_offset": 0xF7C8,
        "retrieve_vtable_slot": G17_RETRIEVE_CHIP_INFO_VTABLE_SLOT,
        "retrieve_provider": RETRIEVE_CHIP_INFO,
        "fields": [
            {"offset": 0, "property": "chip-id", "formula": "value"},
            {
                "offset": 4,
                "property": "chip-revision",
                "formula": "value >> 4",
            },
            {
                "offset": 8,
                "property": "chip-revision",
                "formula": "value & 7",
            },
            {"offset": 12, "value": 0},
        ],
    }


def recover_g17_power_sample_period(
    image: bytes, arm_init_code: bytes
) -> dict[str, object]:
    """Recover the DeviceTree power sample period published at config +0xed8."""

    symbols = macho_symbols(image)
    required = (BASE_CONFIGURE_DEVICE, G17_GET_SAMPLE_PERIOD)
    missing = [name for name in required if name not in symbols]
    if missing:
        raise ValueError(f"Mach-O has no {missing[0]} symbol")
    target = recover_vtable_target(
        image, G17_ACCELERATOR_VTABLE, G17_GET_SAMPLE_PERIOD_VTABLE_SLOT
    )
    if target != symbols[G17_GET_SAMPLE_PERIOD]:
        raise ValueError(f"unexpected G17 getSamplePeriod target {target:#x}")

    configure_address, configure_code = symbol_code(image, BASE_CONFIGURE_DEVICE)
    _getter_address, getter_code = symbol_code(image, G17_GET_SAMPLE_PERIOD)
    if len(getter_code) != 0x14:
        raise ValueError(
            f"unexpected G17 getSamplePeriod size {len(getter_code):#x}"
        )

    property_name = b"gpu-power-sample-period\0"
    adrp = decode_adrp(
        configure_address + 0x7C4,
        struct.unpack_from("<I", configure_code, 0x7C4)[0],
    )
    add = decode_add_immediate(struct.unpack_from("<I", configure_code, 0x7C8)[0])
    if adrp is None or add is None:
        raise ValueError("missing GPU power sample-period property reference")
    page_register, page = adrp
    destination, source, immediate = add
    if destination != page_register or source != page_register:
        raise ValueError("malformed GPU power sample-period property reference")
    property_offset = virtual_to_file(image, page + immediate)
    if image[property_offset : property_offset + len(property_name)] != property_name:
        raise ValueError("GPU power sample-period property reference changed")

    require_instruction_words_at(
        configure_code,
        "G17 power sample-period DeviceTree producer",
        {
            0x34: 0x529EE508,  # accelerator +0xf728 base
            0x38: 0x8B080018,
            0x5CC: 0x91049317,  # accelerator +0xf84c destination
            0x7C4: 0xB0FF41E1,
            0x7C8: 0x9115E821,
            0x808: 0xB9400008,
            0x80C: 0xB90002E8,  # property value copied unchanged
        },
    )
    require_instruction_words_at(
        getter_code,
        "G17 getSamplePeriod provider",
        {
            0x00: 0xD503245F,
            0x04: 0x529F0988,
            0x08: 0x8B080008,
            0x0C: 0xB9400100,
            0x10: 0xD65F03C0,
        },
    )
    require_instruction_words_at(
        arm_init_code,
        "G17 power sample-period firmware publication",
        {
            0xDC: 0x913DC208,
            0xE0: 0xF947BA09,
            0xE4: 0xAA0803F1,
            0xE8: 0xF2EDFA71,
            0xEC: 0xD73F0931,
            0xF0: 0xF9415E68,
            0xF4: 0xB90ED900,
        },
    )

    return {
        "offset": 0xED8,
        "property": property_name[:-1].decode(),
        "accelerator_offset": 0xF84C,
        "formula": "value",
        "provider_vtable_slot": G17_GET_SAMPLE_PERIOD_VTABLE_SLOT,
        "provider": G17_GET_SAMPLE_PERIOD,
    }


def recover_g17_default_mcache_writes(
    image: bytes, arm_init_code: bytes
) -> dict[str, object]:
    """Recover the fixed G17 memory-cache write mask at config +0xf24."""

    symbols = macho_symbols(image)
    required = (BASE_CONFIGURE_DEVICE, G17_DEFAULT_MCACHE_WRITES)
    missing = [name for name in required if name not in symbols]
    if missing:
        raise ValueError(f"Mach-O has no {missing[0]} symbol")
    target = recover_vtable_target(
        image, G17_ACCELERATOR_VTABLE, G17_DEFAULT_MCACHE_WRITES_VTABLE_SLOT
    )
    if target != symbols[G17_DEFAULT_MCACHE_WRITES]:
        raise ValueError(f"unexpected G17 default mcache-write target {target:#x}")

    _configure_address, configure_code = symbol_code(image, BASE_CONFIGURE_DEVICE)
    _getter_address, getter_code = symbol_code(image, G17_DEFAULT_MCACHE_WRITES)
    if len(getter_code) != 0x14:
        raise ValueError(
            f"unexpected G17 default mcache-write provider size {len(getter_code):#x}"
        )
    require_instruction_words_at(
        getter_code,
        "G17 default mcache-write provider",
        {
            0x00: 0xD503245F,
            0x04: 0xD2800080,
            0x08: 0xF2A0F000,
            0x0C: 0xF2C000C0,
            0x10: 0xD65F03C0,
        },
    )
    value = 4 | (0x780 << 16) | (6 << 32)
    require_instruction_words_at(
        configure_code,
        "G17 default mcache-write host publication",
        {
            0x34: 0x529EE508,  # accelerator +0xf728 base
            0x38: 0x8B080018,
            0x4D0: 0x913FC208,
            0x4D4: 0xF947FA09,  # vtable slot +0xff0
            0x4D8: 0xAA1303E0,
            0x4E4: 0xD73F0931,
            0x4EC: 0xF9000700,  # result -> accelerator +0xf730
        },
    )
    require_instruction_words_at(
        arm_init_code,
        "G17 default mcache-write firmware publication",
        {
            0x6A4: 0xF9414E68,
            0x6B0: 0x91403D09,  # accelerator +0xf000 base
            0x714: 0xF943992A,  # accelerator +0xf730
            0x718: 0x913C916C,  # config +0xf24
            0x71C: 0xF900018A,
        },
    )
    return {
        "offset": 0xF24,
        "bytes": 8,
        "value": value,
        "source_offset": 0xF730,
        "provider_vtable_slot": G17_DEFAULT_MCACHE_WRITES_VTABLE_SLOT,
        "provider": G17_DEFAULT_MCACHE_WRITES,
    }


def recover_g17_enabled_usc_config(
    image: bytes, arm_init_code: bytes
) -> dict[str, object]:
    """Recover enabled-USC and adjacent fixed configuration at +0xf88."""

    symbols = macho_symbols(image)
    required = (BASE_CONFIGURE_DEVICE, G17_GET_ENABLED_NUM_USCS)
    missing = [name for name in required if name not in symbols]
    if missing:
        raise ValueError(f"Mach-O has no {missing[0]} symbol")
    target = recover_vtable_target(
        image, G17_ACCELERATOR_VTABLE, G17_GET_ENABLED_NUM_USCS_VTABLE_SLOT
    )
    if target != symbols[G17_GET_ENABLED_NUM_USCS]:
        raise ValueError(f"unexpected G17 enabled-USC target {target:#x}")

    _configure_address, configure_code = symbol_code(image, BASE_CONFIGURE_DEVICE)
    _getter_address, getter_code = symbol_code(image, G17_GET_ENABLED_NUM_USCS)
    if len(getter_code) != 0x44:
        raise ValueError(f"unexpected G17 enabled-USC getter size {len(getter_code):#x}")
    require_instruction_words_at(
        getter_code,
        "G17 enabled-USC getter",
        {
            0x00: 0xD503245F,
            0x04: 0xF9424008,
            0x08: 0xF9424409,
            0x0C: 0xAA08012A,
            0x10: 0xB400016A,
            0x14: 0x9E670120,
            0x18: 0x0E205800,
            0x1C: 0x0E31B800,
            0x20: 0x1E260009,
            0x24: 0x9E670100,
            0x28: 0x0E205800,
            0x2C: 0x0E31B800,
            0x30: 0x1E260008,
            0x34: 0x0B080120,
            0x38: 0xD65F03C0,
            0x3C: 0xB944B000,
            0x40: 0xD65F03C0,
        },
    )

    # configureDevice materializes 0x00000000fffeae80 in x20 and publishes it
    # at accelerator +0xf740. This is separate from the enabled-USC getter.
    fixed_value = 0x00000000FFFEAE80
    require_instruction_words_at(
        configure_code,
        "G17 fixed +0xf740 configuration producer",
        {
            0x34: 0x529EE508,  # accelerator +0xf728 base
            0x38: 0x8B080018,
            0x44: 0x5295D014,
            0x48: 0x72BFFFD4,
            0x50C: 0xF9000F14,  # x20 -> accelerator +0xf740
        },
    )
    require_instruction_words_at(
        arm_init_code,
        "G17 enabled-USC firmware publication",
        {
            0xED4: 0xF9414E60,
            0xEE8: 0xD2815411,
            0xEEC: 0x8B110210,
            0xEF0: 0xF9400208,  # vtable slot +0xaa0
            0xEF8: 0xD73F0910,
            0xEFC: 0xF9415E68,
            0xF08: 0x913E310A,  # config +0xf8c
            0xF0C: 0xB90F8900,  # enabled USC count -> config +0xf88
            0xF10: 0xF9414E6B,
            0xF14: 0x529EE80C,
            0xF18: 0x8B0C016C,
            0xF1C: 0xF940018C,  # accelerator +0xf740
            0xF20: 0xF900014C,
        },
    )
    return {
        "enabled_usc_count": {
            "offset": 0xF88,
            "core_mask_offsets": [0x480, 0x488],
            "fallback_core_count_offset": 0x4B0,
            "formula": "popcount(core_mask_0) + popcount(core_mask_1), else core_count",
            "provider_vtable_slot": G17_GET_ENABLED_NUM_USCS_VTABLE_SLOT,
            "provider": G17_GET_ENABLED_NUM_USCS,
        },
        "fixed_value": {
            "offset": 0xF8C,
            "bytes": 8,
            "value": fixed_value,
            "source_offset": 0xF740,
        },
    }


def recover_g17_uat_config_flag(
    image: bytes, arm_init_code: bytes
) -> dict[str, object]:
    """Recover the nonzero-UAT-configuration flag at config +0xfac."""

    symbols = macho_symbols(image)
    required = (PI300_ACCELERATOR_START, G17_ACCELERATOR_START)
    missing = [name for name in required if name not in symbols]
    if missing:
        raise ValueError(f"Mach-O has no {missing[0]} symbol")
    pi_address, pi_code = symbol_code(image, PI300_ACCELERATOR_START)
    g17_address, g17_code = symbol_code(image, G17_ACCELERATOR_START)
    call_target = decode_bl_target(
        g17_address + 0x1DC, struct.unpack_from("<I", g17_code, 0x1DC)[0]
    )
    if call_target != pi_address:
        raise ValueError("G17 start no longer directly calls PI_300 start")
    require_instruction_words_at(
        g17_code,
        "G17 PI_300 start call",
        {
            0x1D4: 0xAA1303E0,
            0x1D8: 0xAA1403E1,
            0x1DC: struct.unpack_from("<I", g17_code, 0x1DC)[0],
            0x1E0: 0x340012E0,
        },
    )
    require_instruction_words_at(
        pi_code,
        "G17 UAT configuration producer",
        {
            0x18: 0x91407008,
            0x1C: 0x912E8108,
            0x20: 0x529EEE89,
            0x24: 0x8B090009,  # accelerator +0xf774
            0x3C: 0x52800088,
            0x40: 0xB9000128,  # UAT configuration = 4
            0x44: 0x52800028,
            0x48: 0x39001528,
        },
    )
    require_instruction_words_at(
        arm_init_code,
        "G17 UAT configuration flag publication",
        {
            0x498: 0x529EEE89,
            0x49C: 0x8B090009,
            0x4A0: 0xB9400129,
            0x4A4: 0x7100013F,
            0x4A8: 0x1A9F07E9,
            0x4AC: 0xB90FAD09,
        },
    )
    return {
        "offset": 0xFAC,
        "value": 1,
        "source_offset": 0xF774,
        "source_value": 4,
        "formula": "source != 0",
        "producer": PI300_ACCELERATOR_START,
        "g17_caller": G17_ACCELERATOR_START,
    }


def recover_g17_gptbat_base(
    image: bytes, arm_init_code: bytes
) -> dict[str, object]:
    """Recover the physical GPTBAT address published at config +0xfb0."""

    symbols = macho_symbols(image)
    required = (
        ACCELERATOR_GET_GPTBAT_BASE,
        PI300_NEW_SECURE_MONITOR,
        SECURE_MONITOR_INIT,
        SECURE_MONITOR_GET_GPTBAT_DESC,
        PI300_READ_GPTBAT_BASE,
        PI300_SETUP_MMU_CONFIG,
    )
    missing = [name for name in required if name not in symbols]
    if missing:
        raise ValueError(f"Mach-O has no {missing[0]} symbol")

    selected_targets = (
        (
            G17_ACCELERATOR_VTABLE,
            G17_NEW_SECURE_MONITOR_VTABLE_SLOT,
            PI300_NEW_SECURE_MONITOR,
        ),
        (
            G17_ACCELERATOR_VTABLE,
            G17_GET_GPTBAT_BASE_VTABLE_SLOT,
            ACCELERATOR_GET_GPTBAT_BASE,
        ),
        (
            PI300_SECURE_MONITOR_VTABLE,
            SECURE_MONITOR_INIT_VTABLE_SLOT,
            SECURE_MONITOR_INIT,
        ),
        (
            PI300_SECURE_MONITOR_VTABLE,
            SECURE_MONITOR_READ_GPTBAT_BASE_VTABLE_SLOT,
            PI300_READ_GPTBAT_BASE,
        ),
        (
            PI300_SECURE_MONITOR_VTABLE,
            SECURE_MONITOR_GET_GPTBAT_DESC_VTABLE_SLOT,
            SECURE_MONITOR_GET_GPTBAT_DESC,
        ),
    )
    for vtable, slot, expected_name in selected_targets:
        target = recover_vtable_target(image, vtable, slot)
        if target != symbols[expected_name]:
            raise ValueError(
                f"unexpected {vtable} target {target:#x} at slot {slot:#x}; "
                f"expected {symbols[expected_name]:#x}"
            )

    getter_address, getter_code = symbol_code(image, ACCELERATOR_GET_GPTBAT_BASE)
    if len(getter_code) != 0x60:
        raise ValueError(f"unexpected GPTBAT-base getter size {len(getter_code):#x}")
    require_instruction_words_at(
        getter_code,
        "G17 GPTBAT-base getter",
        {
            0x00: 0xD503245F,
            0x04: 0x91407008,  # accelerator +0x1c000
            0x08: 0x912CC108,  # secure-monitor member +0x1cb30
            0x0C: 0xF9400100,
            0x30: 0xD2802B11,
            0x34: 0x8B110210,
            0x38: 0xF9400208,  # secure-monitor getGPTBATDesc slot +0x158
            0x40: 0xD73F0910,
            0x58: struct.unpack_from("<I", getter_code, 0x58)[0],
            0x5C: 0xD65F03C0,
        },
    )

    setup_address, setup_code = symbol_code(image, PI300_SETUP_MMU_CONFIG)
    require_instruction_words_at(
        setup_code,
        "G17 GPTBAT physical-address consumer",
        {
            0x8C: 0xD2802B11,
            0x90: 0x8B110210,
            0x94: 0xF9400208,  # secure-monitor getGPTBATDesc slot +0x158
            0x98: 0xAA1303E0,
            0xA0: 0xD73F0910,
            0xA4: struct.unpack_from("<I", setup_code, 0xA4)[0],
            0xA8: 0xD34EA402,  # descriptor physical address -> 16-KiB PFN
        },
    )
    descriptor_physical_address = decode_b_target(
        getter_address + 0x58, struct.unpack_from("<I", getter_code, 0x58)[0]
    )
    setup_physical_address = decode_bl_target(
        setup_address + 0xA4, struct.unpack_from("<I", setup_code, 0xA4)[0]
    )
    if (
        descriptor_physical_address is None
        or setup_physical_address != descriptor_physical_address
    ):
        raise ValueError("GPTBAT getter no longer returns descriptor physical address")

    monitor_init_address, monitor_init_code = symbol_code(image, SECURE_MONITOR_INIT)
    property_name = b"gptbat-ready\0"
    property_page = decode_adrp(
        monitor_init_address + 0xDC,
        struct.unpack_from("<I", monitor_init_code, 0xDC)[0],
    )
    property_add = decode_add_immediate(
        struct.unpack_from("<I", monitor_init_code, 0xE0)[0]
    )
    if (
        property_page is None
        or property_add is None
        or property_page[0] != 1
        or property_add[0] != 1
        or property_add[1] != 1
    ):
        raise ValueError("malformed gptbat-ready property reference")
    property_offset = virtual_to_file(image, property_page[1] + property_add[2])
    if image[property_offset : property_offset + len(property_name)] != property_name:
        raise ValueError("gptbat-ready property reference changed")
    require_instruction_words_at(
        monitor_init_code,
        "G17 preinitialized GPTBAT mapping",
        {
            0xF0: 0xAA0003F7,
            0xF4: 0xB4000220,
            0xF8: 0xF9400270,
            0x108: 0xD2802711,
            0x10C: 0x8B110210,
            0x110: 0xF9400208,  # readGPTBATBaseAddress slot +0x138
            0x114: 0xAA1303E0,
            0x11C: 0xD73F0910,
            0x120: 0xAA1503E1,
            0x124: 0x52800062,
            0x128: struct.unpack_from("<I", monitor_init_code, 0x128)[0],
            0x12C: 0xAA0003F4,
            0x130: 0xB5000140,
            0x1F8: 0xB40000D7,
            0x1FC: 0xA9015A74,  # descriptor and mapping
            0x200: 0xF9001260,  # mapped CPU pointer
        },
    )

    _read_address, read_code = symbol_code(image, PI300_READ_GPTBAT_BASE)
    if len(read_code) != 0x44:
        raise ValueError(f"unexpected GPTBAT register-reader size {len(read_code):#x}")
    require_instruction_words_at(
        read_code,
        "G17 GPTBAT register reader",
        {
            0x1C: 0xD2803A11,
            0x20: 0x8B110210,
            0x24: 0xF9400208,
            0x28: 0x52900581,
            0x2C: 0x72A01A01,  # register 0xd0802c
            0x34: 0xD73F0910,
            0x38: 0xD3727C00,  # low 32-bit PFN << 14
            0x40: 0xD65F0FFF,
        },
    )

    require_instruction_words_at(
        arm_init_code,
        "G17 GPTBAT firmware publication",
        {
            0x4B0: 0xF9400010,
            0x4C0: 0xD2823A11,
            0x4C4: 0x8B110210,
            0x4C8: 0xF9400208,  # accelerator getGPTBATBase slot +0x11d0
            0x4D0: 0xD73F0910,
            0x4D4: 0xF9415E68,
            0x4D8: 0x9140090A,
            0x4DC: 0xF907D900,  # physical GPTBAT address -> config +0xfb0
        },
    )
    return {
        "offset": 0xFB0,
        "bytes": 8,
        "formula": "physical_address(gptbat_descriptor)",
        "ready_property": property_name[:-1].decode(),
        "hardware_register": 0xD0802C,
        "register_formula": "u32(register) << 14",
        "uat_page_shift": 14,
        "accelerator_vtable_slot": G17_GET_GPTBAT_BASE_VTABLE_SLOT,
        "accelerator_provider": ACCELERATOR_GET_GPTBAT_BASE,
        "secure_monitor_vtable_slot": SECURE_MONITOR_READ_GPTBAT_BASE_VTABLE_SLOT,
        "secure_monitor_provider": PI300_READ_GPTBAT_BASE,
    }


def recover_g17_gpu_identity_config(
    image: bytes, base_init_code: bytes
) -> dict[str, object]:
    """Recover the G17 core/revision/count tuple at config +0xfb8."""

    symbols = macho_symbols(image)
    required = (PI300_READ_CHIP_INFO, G17_READ_CHIP_INFO, DEVICE_USER_GET_CONFIG)
    missing = [name for name in required if name not in symbols]
    if missing:
        raise ValueError(f"Mach-O has no {missing[0]} symbol")
    selected = recover_vtable_target(
        image, G17_ACCELERATOR_VTABLE, G17_READ_CHIP_INFO_VTABLE_SLOT
    )
    if selected != symbols[G17_READ_CHIP_INFO]:
        raise ValueError(f"unexpected G17 readChipInfo target {selected:#x}")

    pi_address, pi_code = symbol_code(image, PI300_READ_CHIP_INFO)
    g17_address, g17_code = symbol_code(image, G17_READ_CHIP_INFO)
    if len(g17_code) != 0x34:
        raise ValueError(f"unexpected G17 readChipInfo size {len(g17_code):#x}")
    call_target = decode_bl_target(
        g17_address + 0x14, struct.unpack_from("<I", g17_code, 0x14)[0]
    )
    if call_target != pi_address:
        raise ValueError("G17 readChipInfo no longer calls the PI_300 provider")
    require_instruction_words_at(
        g17_code,
        "G17 readChipInfo wrapper",
        {
            0x10: 0xAA0103F3,
            0x14: struct.unpack_from("<I", g17_code, 0x14)[0],
            0x20: 0xBC089260,
            0x24: 0x3902127F,
            0x30: 0xD65F0FFF,
        },
    )

    # PI_300 maps ID_VERSION's version selector 4 to core type 0x22. Its
    # revision decoder maps the 1/1 major/minor encoding to revision ID 4.
    require_instruction_words_at(
        pi_code,
        "G17 GPU core/revision identity decoder",
        {
            0xEC: 0x53187EE8,
            0xF0: 0x71002D1F,
            0xF8: 0x53105EE8,
            0xFC: 0x7100111F,
            0x16C: 0x7100053F,
            0x170: 0x540000A1,
            0x174: 0x7100051F,
            0x178: 0x54000061,
            0x17C: 0x52800088,
            0x180: 0x14000005,
            0x194: 0xB9002668,
            0x578: 0x52800448,
            0x57C: 0xB9002268,
        },
    )

    _config_address, config_code = symbol_code(image, DEVICE_USER_GET_CONFIG)
    if len(config_code) != 0x50:
        raise ValueError(f"unexpected getDeviceConfig size {len(config_code):#x}")
    require_instruction_words_at(
        config_code,
        "G17 core-config export",
        {
            0x08: 0x3DC12100,
            0x0C: 0x3DC12501,
            0x10: 0x3DC12902,  # accelerator +0x4a0 -> output +0x20
            0x14: 0x3DC12D03,  # accelerator +0x4b0 -> output +0x30
            0x3C: 0xAD019023,
            0x40: 0xAD008821,
            0x44: 0x3D800020,
            0x4C: 0xD65F03C0,
        },
    )
    require_instruction_words_at(
        base_init_code,
        "G17 GPU identity firmware publication",
        {
            0x1678: 0xF9414E69,
            0x167C: 0xFD425120,  # core type/revision from accelerator +0x4a0
            0x1680: 0xFD07DD00,  # -> config +0xfb8
            0x1684: 0xB944B129,  # active cores from accelerator +0x4b0
            0x1688: 0xB90FC109,  # -> config +0xfc0
        },
    )
    return {
        "core_type": {
            "offset": 0xFB8,
            "source_offset": 0x4A0,
            "device_config_offset": 0x20,
            "id_version_selector": 4,
            "selector_value": 0x22,
        },
        "revision_id": {
            "offset": 0xFBC,
            "source_offset": 0x4A4,
            "device_config_offset": 0x24,
            "c0_decoder_value": 4,
        },
        "active_core_count": {
            "offset": 0xFC0,
            "source_offset": 0x4B0,
            "device_config_offset": 0x30,
            "formula": "active core count decoded from GPU identification registers",
        },
        "provider_vtable_slot": G17_READ_CHIP_INFO_VTABLE_SLOT,
        "provider": G17_READ_CHIP_INFO,
    }


def recover_g17_feature_defaults(
    image: bytes, base_init_code: bytes
) -> dict[str, object]:
    """Recover deterministic G17 accelerator feature-derived config words."""

    symbols = macho_symbols(image)
    required = (BASE_CONFIGURE_DEVICE, PI300_CONFIGURE_DEVICE, G17_CONFIGURE_DEVICE)
    missing = [name for name in required if name not in symbols]
    if missing:
        raise ValueError(f"Mach-O has no {missing[0]} symbol")

    target = recover_vtable_target(
        image, G17_ACCELERATOR_VTABLE, G17_CONFIGURE_DEVICE_VTABLE_SLOT
    )
    if target != symbols[G17_CONFIGURE_DEVICE]:
        raise ValueError(f"unexpected G17 configureDevice target {target:#x}")

    g17_address, g17_code = symbol_code(image, G17_CONFIGURE_DEVICE)
    pi_address, pi_code = symbol_code(image, PI300_CONFIGURE_DEVICE)
    for address, code, offset, expected, label in (
        (
            g17_address,
            g17_code,
            0x70,
            symbols[PI300_CONFIGURE_DEVICE],
            "G17 configureDevice PI_300 base",
        ),
        (
            pi_address,
            pi_code,
            0x48,
            symbols[BASE_CONFIGURE_DEVICE],
            "PI_300 configureDevice base",
        ),
    ):
        if offset + 4 > len(code):
            raise ValueError(f"missing {label} call")
        call_target = decode_bl_target(
            address + offset, struct.unpack_from("<I", code, offset)[0]
        )
        if call_target != expected:
            target_text = "non-BL" if call_target is None else f"{call_target:#x}"
            raise ValueError(
                f"unexpected {label} target {target_text}; expected {expected:#x}"
            )

    # Both masks are installed unconditionally after the checked base calls.
    # The PI_300 mask supplies bit 10, which initFirmwareData publishes at
    # hardware-config +0xec0. The G17 mask is retained in the report so later
    # feature-derived fields can be tied to the same selected producer.
    pi_mask = 0x00000000800184C0
    g17_mask = 0x0001000018020000
    require_instruction_words_at(
        pi_code,
        "PI_300 fixed accelerator feature mask",
        {
            0x84: 0xF9436A68,
            0x9C: 0x52909809,
            0xA0: 0x72B00029,
            0xA4: 0xAA090108,
            0xA8: 0xF9036A68,
        },
    )
    require_instruction_words_at(
        g17_code,
        "G17 fixed accelerator feature mask",
        {
            0x94: 0xF9436A68,
            0x98: 0xD2A30049,
            0x9C: 0xF2E00029,
            0xA0: 0xAA090108,
            0xA4: 0xF9036A68,
        },
    )
    require_instruction_words_at(
        base_init_code,
        "G17 feature bit 10 hardware-config publication",
        {
            0x1398: 0xF9414E60,
            0x139C: 0xB946D008,
            0x13CC: 0xB946D00B,
            0x13D0: 0x530A296B,
            0x13D4: 0xB90EC12B,
        },
    )
    if (pi_mask >> 10) & 1 != 1:
        raise ValueError("PI_300 fixed feature mask does not supply bit 10")

    return {
        "source_offset": 0x6D0,
        "configure_device_vtable_slot": G17_CONFIGURE_DEVICE_VTABLE_SLOT,
        "pi300_unconditional_mask": pi_mask,
        "g17_unconditional_mask": g17_mask,
        "fixed_u32": {"0xec0": 1},
    }


def recover_g17_relative_boost_frequency_table(
    image: bytes, arm_power_code: bytes
) -> dict[str, object]:
    """Recover the DeviceTree-backed relative boost-frequency table."""

    symbols = macho_symbols(image)
    if INIT_BASE_SETUP_CONFIG not in symbols:
        raise ValueError(f"Mach-O has no {INIT_BASE_SETUP_CONFIG} symbol")
    setup_address, setup_code = symbol_code(image, INIT_BASE_SETUP_CONFIG)

    property_name = b"gpu-perf-base-pstate\0"
    adrp = decode_adrp(
        setup_address + 0x4C8, struct.unpack_from("<I", setup_code, 0x4C8)[0]
    )
    add = decode_add_immediate(struct.unpack_from("<I", setup_code, 0x4CC)[0])
    if adrp is None or add is None:
        raise ValueError("missing GPU base performance-state property reference")
    page_register, page = adrp
    destination, source, immediate = add
    if destination != page_register or source != page_register:
        raise ValueError("malformed GPU base performance-state property reference")
    property_offset = virtual_to_file(image, page + immediate)
    if image[property_offset : property_offset + len(property_name)] != property_name:
        raise ValueError("GPU base performance-state property reference changed")

    # setupConfig checks that the property is nonzero and no larger than the
    # maximum state, then records base_state * 100 at accelerator +0x10ecc.
    require_instruction_words_at(
        setup_code,
        "GPU base performance-state scaling",
        {
            0x48C: 0xF9414E68,
            0x490: 0x91404115,
            0x494: 0xB94ECEA9,
            0x498: 0x5290A3EA,
            0x49C: 0x72AA3D6A,
            0x4A0: 0x9BAA7D29,
            0x4A4: 0xD365FD36,
            0x4C8: 0xF0FF3FC1,
            0x4CC: 0x913D0C21,
            0x50C: 0xB9400016,
            0x510: 0x34004896,
            0x514: 0xB94F3668,
            0x518: 0x6B160109,
            0x520: 0x52800C8A,
            0x53C: 0x1B0A7EC9,
            0x540: 0xB90EC6A9,
            0x544: 0x1B0A7D08,
            0x548: 0xB90ECAA8,
            0x54C: 0xB90ECEA9,
        },
    )

    # The ARM producer divides the saved scaled state by 100, clears one word
    # per performance state, and computes 100 * (freq - base) / (max - base).
    require_instruction_words_at(
        arm_power_code,
        "G17 relative boost-frequency table",
        {
            0xCE4: 0x5283210B,
            0xCE8: 0x8B0B0134,
            0xCEC: 0xB94B86A9,
            0xCF0: 0x5290A3EB,
            0xCF4: 0x72AA3D6B,
            0xCF8: 0x9BAB7D29,
            0xCFC: 0xD365FD3A,
            0xD00: 0x91406D08,
            0xD04: 0x910C6116,
            0xD08: 0x8B1A0AC8,
            0xD0C: 0xB9400117,
            0xD10: 0xD1000559,
            0xD14: 0xD37EF738,
            0xD2C: 0xB940011B,
            0xD30: 0xD37EF541,
            0xD34: 0xAA1403E0,
            0xD3C: 0xEB1A033F,
            0xD44: 0xCB170368,
            0xD48: 0x11000749,
            0xD4C: 0x52800C8A,
            0xD68: 0xB940018C,
            0xD6C: 0xCB17018C,
            0xD84: 0x9B0A7D8B,
            0xD88: 0x9AC8096B,
            0xD8C: 0xB90001AB,
            0xD94: 0x11000529,
            0xD98: 0xEB1A033F,
            0xD9C: 0x54FFFDA8,
            0xDB4: 0x52800C89,
            0xDB8: 0xB9000109,
        },
    )

    return {
        "offset": 0x1908,
        "entries": 16,
        "base_state_property": property_name[:-1].decode(),
        "base_state_scaled_source_offset": 0x10ECC,
        "frequency_source_offset": 0x1B318,
        "formula": "100 * (frequency - base_frequency) / (max_frequency - base_frequency)",
        "states_at_or_below_base": 0,
        "maximum_state_value": 100,
    }


def recover_g17_sram_power_scale_table(
    image: bytes, base_power_code: bytes, arm_power_code: bytes
) -> dict[str, object]:
    """Recover the G17 SRAM power-scale row copied to config +0x1848."""

    symbols = macho_symbols(image)
    required = (
        INIT_BASE_SETUP_CONFIG,
        G17_CONFIGURE_DEVICE,
        G17_POPULATE_POWER_ESTIMATION_CONFIG,
        G17_POPULATE_SRAM_POWER_SCALE_DATA,
        G17_POPULATE_CHIP_LEAKAGE_DATA,
    )
    missing = [name for name in required if name not in symbols]
    if missing:
        raise ValueError(f"Mach-O has no {missing[0]} symbol")

    selected_targets = (
        (
            G17_POPULATE_POWER_ESTIMATION_VTABLE_SLOT,
            G17_POPULATE_POWER_ESTIMATION_CONFIG,
        ),
        (
            G17_POPULATE_SRAM_POWER_SCALE_VTABLE_SLOT,
            G17_POPULATE_SRAM_POWER_SCALE_DATA,
        ),
        (
            G17_POPULATE_CHIP_LEAKAGE_VTABLE_SLOT,
            G17_POPULATE_CHIP_LEAKAGE_DATA,
        ),
    )
    for slot, name in selected_targets:
        target = recover_vtable_target(image, G17_ACCELERATOR_VTABLE, slot)
        if target != symbols[name]:
            raise ValueError(f"unexpected G17 vtable target at {slot:#x}: {target:#x}")

    # setupConfig invokes the selected power-estimation producer with the
    # maximum performance-state index previously saved at firmware +0xf34.
    _setup_address, setup_code = symbol_code(image, INIT_BASE_SETUP_CONFIG)
    require_instruction_words_at(
        setup_code,
        "G17 power-estimation setup call",
        {
            0x224: 0xF9414E60,
            0x228: 0xB94F3661,
            0x22C: 0xF9400010,
            0x23C: 0xD2819811,
            0x240: 0x8B110210,
            0x244: 0xF9400208,
            0x24C: 0xD73F0910,
        },
    )

    # G17 configureDevice unconditionally adds feature bit 17. The selected
    # producer tests that bit through byte +0x6d2 before binding its private
    # firmware config at +0xcf0 and dispatching the SRAM and leakage writers.
    _configure_address, configure_code = symbol_code(image, G17_CONFIGURE_DEVICE)
    require_instruction_words_at(
        configure_code,
        "G17 power-estimation feature bit",
        {
            0x94: 0xF9436A68,
            0x98: 0xD2A30049,
            0x9C: 0xF2E00029,
            0xA0: 0xAA090108,
            0xA4: 0xF9036A68,
        },
    )
    g17_feature_mask = 0x0001000018020000
    if not g17_feature_mask & (1 << 17):
        raise ValueError("G17 fixed feature mask does not supply bit 17")

    _producer_address, producer_code = symbol_code(
        image, G17_POPULATE_POWER_ESTIMATION_CONFIG
    )
    require_instruction_words_at(
        producer_code,
        "G17 SRAM power-scale dispatch",
        {
            0x14: 0x395B4808,
            0x18: 0x36080508,
            0x20: 0xF942D808,
            0x24: 0x9133C108,
            0x28: 0x91404409,
            0x2C: 0x91072129,
            0x30: 0xF9000128,
            0x44: 0xD2819E11,
            0x48: 0x8B110210,
            0x4C: 0xF9400208,
            0x58: 0xD73F0910,
            0x80: 0x9132C202,
            0x84: 0xF9465A10,
        },
    )

    _sram_address, sram_code = symbol_code(
        image, G17_POPULATE_SRAM_POWER_SCALE_DATA
    )
    if len(sram_code) != 0xD4:
        raise ValueError(
            f"unexpected G17 SRAM power-scale producer size {len(sram_code):#x}"
        )
    require_instruction_words_at(
        sram_code,
        "G17 SRAM power-scale fill",
        {
            0x04: 0x91406C08,
            0x08: 0x910C4108,
            0x0C: 0xB9400108,
            0x14: 0x91404409,
            0x18: 0x91072129,
            0x1C: 0xF9400129,
            0x44: 0x9101412B,
            0x48: 0x5291EB8C,
            0x4C: 0x72A7F04C,
            0x58: 0xAD3E8160,
            0x5C: 0xAD3F8160,
            0x90: 0x5291EB8D,
            0x94: 0x72A7F04D,
            0x9C: 0x3C810580,
            0xBC: 0x5291EB8A,
            0xC0: 0x72A7F04A,
            0xC4: 0xB800452A,
            0xC8: 0xF1000508,
            0xCC: 0x54FFFFC1,
        },
    )

    # The base firmware producer zeroes its runtime object and copies the
    # accelerator-populated 0xcf0 block to runtime +0xa4. The ARM producer
    # then copies runtime +0xc4 (0xcf0 + 0x20) to hardware config +0x1848.
    require_instruction_words_at(
        base_power_code,
        "G17 power-estimation runtime copy",
        {
            0x20: 0xF9416C00,
            0x24: 0x5283BA01,
            0x28: 0x72A00021,
            0x2C: 0x94AA6439,
            0x30: 0xF9416E68,
            0x34: 0x91029100,
            0x38: 0x9133C261,
            0x3C: 0x52802C02,
            0x40: 0x94AA63C8,
        },
    )
    require_instruction_words_at(
        arm_power_code,
        "G17 SRAM power-scale firmware copy",
        {
            0x294: 0xF9416E68,
            0x400: 0xF9415E6B,
            0x404: 0x5282010A,
            0x408: 0x8B0A016A,
            0x40C: 0x91041108,
            0x410: 0x5283110C,
            0x414: 0x8B0C016B,
            0x418: 0x5280020C,
            0x51C: 0xBC5C0100,
            0x520: 0xBC1C0160,
            0x524: 0x91010129,
            0x528: 0xBC404500,
            0x52C: 0xBC004560,
            0x530: 0x9101014A,
            0x534: 0xF100058C,
            0x538: 0x54FFF721,
        },
    )

    raw_value = 0x3F828F5C
    return {
        "offset": 0x1848,
        "entries": 16,
        "active_entries": "gpu-perf-state-count",
        "state_count_source_offset": 0x1B310,
        "accelerator_config_offset": 0xD10,
        "runtime_source_offset": 0xC4,
        "raw_float": raw_value,
        "value": struct.unpack("<f", struct.pack("<I", raw_value))[0],
        "feature_bit": 17,
        "producer_vtable_slot": G17_POPULATE_POWER_ESTIMATION_VTABLE_SLOT,
        "producer": G17_POPULATE_POWER_ESTIMATION_CONFIG,
    }


def recover_g17_static_power_scale_table(
    image: bytes, kernel_image: bytes, arm_power_code: bytes
) -> dict[str, object]:
    """Prove that G17 leaves the static power-scale row at +0x1888 zero."""

    symbols = macho_symbols(image)
    kernel_symbols = macho_symbols(kernel_image)
    required = (
        G17_ARM_FIRMWARE_ASC_META_ALLOC,
        G17_POPULATE_SRAM_POWER_SCALE_DATA,
        G17_POPULATE_CHIP_LEAKAGE_DATA,
        G17_POPULATE_STATIC_POWER_DATA,
    )
    missing = [name for name in required if name not in symbols]
    if missing:
        raise ValueError(f"Mach-O has no {missing[0]} symbol")
    kernel_required = (OS_OBJECT_TYPED_OPERATOR_NEW, KALLOC_TYPE_IMPL)
    kernel_missing = [name for name in kernel_required if name not in kernel_symbols]
    if kernel_missing:
        raise ValueError(f"kernel Mach-O has no {kernel_missing[0]} symbol")

    # The ASC OSObject has a 0x2920-byte typed-allocation view. Its MetaClass
    # alloc routine requests exactly that size from OSObject's typed operator
    # new, so the normal fixed-type branch is necessarily selected.
    alloc_address, alloc_code = symbol_code(image, G17_ARM_FIRMWARE_ASC_META_ALLOC)
    if len(alloc_code) != 0x9B0:
        raise ValueError(f"unexpected G17 ASC allocator size {len(alloc_code):#x}")
    require_instruction_words_at(
        alloc_code,
        "G17 ASC typed allocation",
        {
            0x1C: 0x910CC000,
            0x20: 0x52852401,
            0x28: 0xAA0003F3,
        },
    )
    adrp = decode_adrp(
        alloc_address + 0x18, struct.unpack_from("<I", alloc_code, 0x18)[0]
    )
    addition = decode_add_immediate(struct.unpack_from("<I", alloc_code, 0x1C)[0])
    if adrp is None or addition is None:
        raise ValueError("malformed G17 ASC typed-allocation view reference")
    page_register, page = adrp
    destination, source, immediate = addition
    if (page_register, destination, source) != (0, 0, 0):
        raise ValueError("G17 ASC typed-allocation view no longer uses x0")
    type_view_address = page + immediate
    type_view_offset = virtual_to_file(image, type_view_address)
    type_size = struct.unpack_from("<I", image, type_view_offset + 0x2C)[0] & 0xFFFFFF
    if type_size != 0x2920:
        raise ValueError(f"unexpected G17 ASC typed-allocation size {type_size:#x}")
    alloc_call = decode_bl_target(
        alloc_address + 0x24, struct.unpack_from("<I", alloc_code, 0x24)[0]
    )
    if alloc_call != kernel_symbols[OS_OBJECT_TYPED_OPERATOR_NEW]:
        raise ValueError("G17 ASC allocator does not call OSObject typed operator new")

    # This live kernel's operator-new fixed-type branch passes literal flag 4
    # to kalloc_type_impl. XNU defines flag 4 as Z_ZERO, establishing the
    # initial value of every byte not subsequently written by the constructor.
    new_address, new_code = symbol_code(kernel_image, OS_OBJECT_TYPED_OPERATOR_NEW)
    if len(new_code) != 0x64:
        raise ValueError(f"unexpected OSObject typed operator-new size {len(new_code):#x}")
    require_instruction_words_at(
        new_code,
        "OSObject zeroed typed allocation",
        {
            0x14: 0xB9402C08,
            0x18: 0x92405D08,
            0x1C: 0xEB08003F,
            0x20: 0x54000129,
            0x44: 0x52800081,
        },
    )
    kalloc_call = decode_bl_target(
        new_address + 0x48, struct.unpack_from("<I", new_code, 0x48)[0]
    )
    if kalloc_call != kernel_symbols[KALLOC_TYPE_IMPL]:
        raise ValueError("OSObject typed operator new has an unexpected allocator target")

    # The only G17 writer before the copied row is the checked SRAM producer.
    # With the driver's 16-state capacity its +0x20 row ends at +0x60, exactly
    # where the untouched static row begins. The leakage writer starts at
    # firmware-object +0xe50, well after the source at +0xd50.
    _sram_address, sram_code = symbol_code(
        image, G17_POPULATE_SRAM_POWER_SCALE_DATA
    )
    require_instruction_words_at(
        sram_code,
        "G17 SRAM/static power row boundary",
        {
            0x0C: 0xB9400108,
            0x1C: 0xF9400129,
            0xB4: 0x8B0A0929,
            0xB8: 0x91008129,
            0xC4: 0xB800452A,
        },
    )
    _leakage_address, leakage_code = symbol_code(
        image, G17_POPULATE_CHIP_LEAKAGE_DATA
    )
    if len(leakage_code) != 0x540:
        raise ValueError(f"unexpected G17 chip-leakage producer size {len(leakage_code):#x}")
    require_instruction_words_at(
        leakage_code,
        "G17 leakage-data destination ranges",
        {
            0x2C0: 0xF942DABA,
            0x2C4: 0x91394348,
            0x2C8: 0x913A4349,
            0x330: 0x913B4348,
            0x334: 0x913C4349,
            0x3FC: 0x913C8348,
            0x400: 0x913CA349,
        },
    )
    static_target = recover_vtable_target(
        image, G17_ACCELERATOR_VTABLE, G17_POPULATE_STATIC_POWER_VTABLE_SLOT
    )
    if static_target != symbols[G17_POPULATE_STATIC_POWER_DATA]:
        raise ValueError(f"unexpected G17 static-power provider {static_target:#x}")
    _static_address, static_code = symbol_code(image, G17_POPULATE_STATIC_POWER_DATA)
    if static_code != struct.pack("<2I", 0xD503245F, 0xD65F03C0):
        raise ValueError("G17 static-power provider is not a no-op")

    require_instruction_words_at(
        arm_power_code,
        "G17 zero static power-scale firmware copy",
        {
            0x40C: 0x91041108,
            0x410: 0x5283110C,
            0x414: 0x8B0C016B,
            0x418: 0x5280020C,
            0x528: 0xBC404500,
            0x52C: 0xBC004560,
            0x534: 0xF100058C,
            0x538: 0x54FFF721,
        },
    )

    return {
        "offset": 0x1888,
        "entries": 16,
        "values": [0] * 16,
        "accelerator_config_offset": 0xD50,
        "runtime_source_offset": 0x104,
        "allocator": OS_OBJECT_TYPED_OPERATOR_NEW,
        "allocator_flag": 4,
        "allocator_flag_name": "Z_ZERO",
        "type_view_address": type_view_address,
        "type_bytes": type_size,
        "static_provider_vtable_slot": G17_POPULATE_STATIC_POWER_VTABLE_SLOT,
        "static_provider": G17_POPULATE_STATIC_POWER_DATA,
    }


def recover_g17_afr_relative_boost_frequency_table(
    image: bytes, arm_power_code: bytes
) -> dict[str, object]:
    """Recover the AFR-domain relative boost-frequency table."""

    symbols = macho_symbols(image)
    if POPULATE_AFR_FAST_DIE_CONFIG not in symbols:
        raise ValueError(f"Mach-O has no {POPULATE_AFR_FAST_DIE_CONFIG} symbol")
    _address, afr_config_code = symbol_code(image, POPULATE_AFR_FAST_DIE_CONFIG)

    # The independently named AFR fast-die producer binds its performance-state
    # record at accelerator +0x1c4e8. The record starts with the state count and
    # places its frequency array at +8 (accelerator +0x1c4f0).
    require_instruction_words_at(
        afr_config_code,
        "G17 AFR performance-state record",
        {
            0x1C: 0x91407008,
            0x20: 0x9113A114,
            0xDC: 0xB9400289,
            0xE4: 0x1B082929,
        },
    )
    if b"afr-perf-states\0" not in image:
        raise ValueError("missing afr-perf-states property name")

    # The ARM firmware-data producer uses the same scaled base state as the
    # primary GPU curve, clears the complete destination, and normalizes AFR
    # frequencies between that base and the final AFR state.
    require_instruction_words_at(
        arm_power_code,
        "G17 AFR relative boost-frequency table",
        {
            0xDD8: 0xF9415E69,
            0xDDC: 0x5283310A,
            0xDE0: 0x8B0A0134,
            0xDE4: 0xB94B86A9,
            0xDE8: 0x5290A3EA,
            0xDEC: 0x72AA3D6A,
            0xDF0: 0x9BAA7D29,
            0xDF4: 0xD365FD35,
            0xDF8: 0x914072E9,
            0xDFC: 0x9113C136,
            0xE00: 0x8B150AC9,
            0xE04: 0xB9400137,
            0xE08: 0xD1000519,
            0xE28: 0xD37EF501,
            0xE2C: 0xAA1403E0,
            0xE3C: 0xCB170348,
            0xE44: 0x52800C8A,
            0xE50: 0xB940018C,
            0xE54: 0xCB17018C,
            0xE58: 0x9B0A7D8C,
            0xE5C: 0x9AC8098C,
            0xE64: 0xB900016C,
            0xE68: 0x910006B5,
            0xE6C: 0xEB0902BF,
            0xE70: 0x54FFFEC3,
            0xE88: 0x52800C89,
            0xE8C: 0xB9000109,
        },
    )

    return {
        "offset": 0x1988,
        "entries": 16,
        "domain": "AFR",
        "state_property": "afr-perf-states",
        "base_state_scaled_source_offset": 0x10ECC,
        "state_count_source_offset": 0x1C4E8,
        "frequency_source_offset": 0x1C4F0,
        "formula": "100 * (frequency - base_frequency) / (max_frequency - base_frequency)",
        "states_at_or_below_base": 0,
        "maximum_state_value": 100,
    }


def recover_g17_linear_power_transfer_tables(
    image: bytes, arm_power_code: bytes
) -> dict[str, object]:
    """Recover the two linear power-transfer tables at config +0x18c8/+0x1948.

    Unlike every other recovered hardware-configuration row, these two are not
    constants.  Both are 0..100 curves normalised from per-state power matrices
    that Apple computes with an analog leakage model, and that model is seeded
    with per-die calibration read from an eFuse aperture.  The structure, the
    normalisation and every model constant are recovered here; the row values
    themselves can only be produced on the target machine.
    """

    symbols = macho_symbols(image)
    required = (
        G17_POPULATE_LINEAR_POWER_TRANSFER,
        G17_POPULATE_MAX_PERF_POWER,
        G17_POPULATE_MAX_PERF_POWER_CS,
        G17_CALCULATE_VDD_GPU_LEAKAGE,
        G17_CALCULATE_AFR_LEAKAGE,
        G17_APPLY_LEAKAGE_EQUATION,
        G17_POPULATE_CHIP_LEAKAGE,
    )
    missing = [name for name in required if name not in symbols]
    if missing:
        raise ValueError(f"Mach-O is missing G17 power-model symbols: {missing}")

    # G17 selects the real power producers, not the no-op stubs it selects for
    # the neighbouring static-power row.
    for slot, name in (
        (G17_POPULATE_MAX_PERF_POWER_VTABLE_SLOT, G17_POPULATE_MAX_PERF_POWER),
        (G17_POPULATE_MAX_PERF_POWER_CS_VTABLE_SLOT, G17_POPULATE_MAX_PERF_POWER_CS),
        (G17_CALCULATE_VDD_GPU_LEAKAGE_VTABLE_SLOT, G17_CALCULATE_VDD_GPU_LEAKAGE),
        (G17_CALCULATE_AFR_LEAKAGE_VTABLE_SLOT, G17_CALCULATE_AFR_LEAKAGE),
        (G17_APPLY_LEAKAGE_EQUATION_VTABLE_SLOT, G17_APPLY_LEAKAGE_EQUATION),
        (G17_POPULATE_CHIP_LEAKAGE_VTABLE_SLOT, G17_POPULATE_CHIP_LEAKAGE),
    ):
        target = recover_vtable_target(image, G17_ACCELERATOR_VTABLE, slot)
        if target != symbols[name]:
            raise ValueError(
                f"unexpected G17 power vtable target at {slot:#x}: {target:#x}"
            )

    # The +0x18c8 row is produced by a direct call that passes the destination
    # and a base state of zero; the +0x1948 row is the same algorithm inlined
    # against the AFR matrix.
    require_instruction_words_at(
        arm_power_code,
        "G17 linear power-transfer call",
        {
            0x948: 0xF9415E68,  # hardware config CPU address
            0x94C: 0x52831909,  # mov w9, #0x18c8
            0x950: 0x8B090101,  # add x1, x8, x9
            0x954: 0x52800002,  # base state 0
            0x958: 0x97FEAA33,  # bl populateLinearPowerTransferTable
        },
    )
    call = decode_bl_target(symbols[INIT_POWER_DATA] + 0x958, 0x97FEAA33)
    if call != symbols[G17_POPULATE_LINEAR_POWER_TRANSFER]:
        raise ValueError(
            f"linear power-transfer call does not reach the producer: {call:#x}"
        )

    require_instruction_words_at(
        arm_power_code,
        "G17 inlined AFR linear power-transfer producer",
        {
            0x95C: 0xF9414E68,  # accelerator
            0x960: 0x91407109,  # accelerator +0x1c000
            0x964: 0x9113A12A,  # AFR state count at +0x1c4e8
            0x968: 0xF9415E69,  # hardware config CPU address
            0x96C: 0xB940014E,
            0x974: 0x710041DF,  # reject more than 16 states
            0x97C: 0x5283290B,  # mov w11, #0x1948
            0x980: 0x8B0B012B,  # add x11, x9, x11
            0x984: 0xB944ED0C,  # AFR column count at +0x4ec
            0x98C: 0x5299460D,  # mov w13, #0xca30
            0x990: 0x72A0002D,  # matrix at accelerator +0x1ca30
            0x994: 0x510005CF,  # maximum state index
            0x998: 0xD37DF1EE,  # 8-byte row stride
            0xB8C: 0x4B0E01EF,  # maximum row sum - base row sum
            0xB94: 0x52800C91,  # mov w17, #100
            0xBA0: 0x4B0E0040,  # row sum - base row sum
            0xBA4: 0x1B117C00,  # * 100
            0xBA8: 0x1ACF0800,  # / (maximum - base)
            0xBAC: 0xB82C7960,  # str into config +0x1948
            0xBB8: 0x91002210,
            0xBBC: 0x910021AD,
        },
    )

    # The shared producer sums one matrix row per performance state and scales
    # the result into 0..100 exactly like the relative boost-frequency tables.
    _address, linear_code = symbol_code(image, G17_POPULATE_LINEAR_POWER_TRANSFER)
    require_instruction_words_at(
        linear_code,
        "G17 linear power-transfer normalisation",
        {
            0x010: 0x91406C08,  # accelerator +0x1b000
            0x014: 0x910C4108,  # state count at +0x1b310
            0x018: 0xB940010B,
            0x01C: 0x7100417F,  # reject more than 16 states
            0x024: 0x5298C609,  # mov w9, #0xc630
            0x028: 0x72A00029,  # matrix at accelerator +0x1c630
            0x02C: 0xB944E40D,  # column count at +0x4e4
            0x034: 0x5100056C,  # maximum state index
            0x038: 0xD37AE58A,  # 0x40-byte row stride
            0x2DC: 0x4B0A018B,  # maximum row sum - base row sum
            0x2F0: 0x52800C8E,  # mov w14, #100
            0x300: 0x1B0E7DEF,  # * 100
            0x304: 0x1ACB09EF,  # / (maximum - base)
            0x320: 0xB900022F,
        },
    )

    # Both matrices are filled by the selected G17X power producers.
    _address, power_code = symbol_code(image, G17_POPULATE_MAX_PERF_POWER)
    require_instruction_words_at(
        power_code,
        "G17 maximum-performance power matrix",
        {
            0x034: 0xB944E415,  # core count at +0x4e4
            0x038: 0xB944EC18,  # group count at +0x4ec
            0x088: 0x9118C131,  # destination matrix at +0x1c630
            0x090: 0x9128C121,  # AFR matrix at +0x1ca30
            0x0A4: 0x52A88F44,  # 1000.0f millivolt divisor
            0x0A8: 0x529BD065,  # Hz to MHz reciprocal
            0x0AC: 0x72A86365,
            0x0B8: 0x1AD80ABA,  # cores per group
            0x244: 0x529AE148,  # 1.28f voltage exponent
            0x248: 0x72A7F468,
            0x258: 0x52866668,  # 20.15f dynamic-power coefficient
            0x25C: 0x72A83428,
            0x278: 0x528E8009,  # 48500.0f clamp
            0x27C: 0x72A8E7A9,
            0x308: 0xB912DB08,  # store into the +0x1c630 matrix
        },
    )
    _address, cs_code = symbol_code(image, G17_POPULATE_MAX_PERF_POWER_CS)
    require_instruction_words_at(
        cs_code,
        "G17 CS maximum-performance power matrix",
        {
            0x030: 0xB944A009,  # chip variant at +0x4a0
            0x034: 0x7100853F,
            0x038: 0x52933348,  # 21.7f default coefficient
            0x03C: 0x72A835A8,
            0x044: 0x52947AE8,  # 12.29f variant coefficient
            0x048: 0x72A82888,
            0x068: 0x5292D90A,  # 38600 default clamp
            0x06C: 0x528C1C0B,  # 24800 variant clamp
            0x080: 0x9128C14D,  # destination matrix at +0x1ca30
            0x084: 0x9114E2B7,  # AFR voltages at +0x1c538
            0x1D0: 0xB90502E8,  # store into the +0x1ca30 matrix
        },
    )

    # The leakage seed is per-die calibration mapped from a fuse aperture.
    _leak_address, leak_code = symbol_code(image, G17_POPULATE_CHIP_LEAKAGE)
    physical = 0
    for offset in (0xB8, 0xBC, 0xC0):
        decoded = decode_move_wide(struct.unpack_from("<I", leak_code, offset)[0])
        if decoded is None:
            raise ValueError("chip-leakage fuse aperture is no longer materialized")
        kind, register, immediate, shift = decoded
        if register != 0:
            raise ValueError("chip-leakage fuse aperture uses an unexpected register")
        physical |= immediate << shift
    aperture_bytes = struct.unpack_from("<I", leak_code, 0xC4)[0]
    if aperture_bytes != 0x52820001:
        raise ValueError("chip-leakage fuse aperture size changed")
    if decode_bl_target(0xCC, struct.unpack_from("<I", leak_code, 0xCC)[0]) is None:
        raise ValueError("chip-leakage aperture is not mapped by a direct call")

    # Recover the fuse-field descriptor table rather than treating the mapped
    # aperture as an opaque per-die input. The selected G17 producer has eight
    # core selectors followed immediately by four 0x28-byte descriptors. Each
    # descriptor names a primary word/shift/mask and, optionally, a second
    # word/mask/left-shift whose bits are joined to it.
    require_instruction_words_at(
        leak_code,
        "G17 chip-leakage fuse decode",
        {
            0x14C: 0xB944E6BB,  # active core selector count at accelerator +0x4e4
            0x1A0: 0xB9400210,  # optional second fuse word
            0x1A4: 0x29444620,  # optional second mask and left shift
            0x1AC: 0x9AD12210,  # optional field shifted into place
            0x1B0: 0x9ACE25AD,  # primary word >> descriptor shift
            0x1B4: 0x8A0F01AD,  # primary descriptor mask
            0x1B8: 0xAA0D020D,  # join optional and primary fields
            0x1BC: 0x9E2301A0,  # integer primary field -> float
            0x1C0: 0x1E202800,  # G17B scale x2
            0x1C8: 0xB9419F0D,  # secondary source word at fuse +0x19c
            0x1CC: 0x53043DAD,  # secondary bits 4..15
            0x1D0: 0x1E03FDA0,  # G17B secondary scale /2
            0x260: 0x9E2301A1,  # G17C integer primary field -> float
            0x264: 0x1E212821,
            0x268: 0x1E200821,  # x2 then x0.5 leaves x1
            0x270: 0xB9419F0D,
            0x274: 0x53043DAD,
            0x278: 0x1E03F9A1,  # G17C secondary scale /4
            0x398: 0xB944EEB5,  # active group count at accelerator +0x4ec
            0x3AC: 0xB9419F08,  # group low word at fuse +0x19c
            0x3B0: 0xB941A309,  # group high word at fuse +0x1a0
            0x3B4: 0x13886528,  # extract across bit 25 of the word pair
            0x3B8: 0x531F2D08,  # retain twelve bits and multiply by two
        },
    )

    def referenced_table(adrp_offset: int, add_offset: int, register: int) -> int:
        adrp = decode_adrp(
            _leak_address + adrp_offset,
            struct.unpack_from("<I", leak_code, adrp_offset)[0],
        )
        add = decode_add_immediate(
            struct.unpack_from("<I", leak_code, add_offset)[0]
        )
        if adrp is None or add is None:
            raise ValueError("chip-leakage fuse table reference changed")
        adrp_register, page = adrp
        destination, source, immediate = add
        if adrp_register != register or destination != register or source != register:
            raise ValueError("chip-leakage fuse table register changed")
        return page + immediate

    descriptor_table = referenced_table(0x170, 0x174, 8)
    selector_table = referenced_table(0x18C, 0x190, 12)
    selector_bytes = descriptor_table - selector_table
    if selector_bytes != 0x20:
        raise ValueError(
            f"unexpected chip-leakage core selector bytes {selector_bytes:#x}"
        )
    selector_offset = virtual_to_file(image, selector_table)
    selectors = list(struct.unpack_from("<8I", image, selector_offset))
    if selectors != [0, 1, 2, 3, 0, 1, 2, 3]:
        raise ValueError(f"unexpected chip-leakage core selectors {selectors}")
    descriptor_count = max(selectors) + 1
    descriptor_offset = virtual_to_file(image, descriptor_table)
    descriptors = []
    for index in range(descriptor_count):
        fields = struct.unpack_from("<10I", image, descriptor_offset + index * 0x28)
        descriptors.append(
            {
                "index": index,
                "record_bytes": 0x28,
                "tag": fields[0],
                "has_secondary": bool(fields[1]),
                "primary_word_offset": fields[2],
                "primary_shift": fields[3],
                "primary_mask": fields[4],
                "secondary_word_offset": fields[6],
                "secondary_shift": fields[7],
                "secondary_mask": fields[8],
                "secondary_left_shift": fields[9],
            }
        )
    expected_descriptors = [
        (False, 0x198, 8, 0x3FFF, 0, 0, 0, 0),
        (True, 0x198, 22, 0x3FF, 0x19C, 0, 0xF, 10),
        (True, 0x198, 22, 0x3FF, 0x19C, 0, 0xF, 10),
        (False, 0x198, 8, 0x3FFF, 0, 0, 0, 0),
    ]
    actual_descriptors = [
        (
            item["has_secondary"],
            item["primary_word_offset"],
            item["primary_shift"],
            item["primary_mask"],
            item["secondary_word_offset"],
            item["secondary_shift"],
            item["secondary_mask"],
            item["secondary_left_shift"],
        )
        for item in descriptors
    ]
    if actual_descriptors != expected_descriptors:
        raise ValueError("G17 chip-leakage fuse descriptors changed")

    # Each leakage evaluation selects one bucket from a static parameter table
    # and returns a value directly proportional to the fused input.
    def leakage_table(name: str) -> dict[str, object]:
        address, code = symbol_code(image, name)
        buckets = []
        for offset in (0x10, 0x38):
            adrp = decode_adrp(address + offset, struct.unpack_from("<I", code, offset)[0])
            add = decode_add_immediate(struct.unpack_from("<I", code, offset + 4)[0])
            if adrp is None or add is None:
                raise ValueError(f"{name} no longer references a parameter table")
            _register, page = adrp
            _destination, _source, immediate = add
            buckets.append(page + immediate)
        count_load = decode_ldr_d(struct.unpack_from("<I", code, 0x20)[0])
        if count_load is None:
            raise ValueError(f"{name} no longer loads a bucket count")
        adrp = decode_adrp(address + 0x1C, struct.unpack_from("<I", code, 0x1C)[0])
        if adrp is None:
            raise ValueError(f"{name} no longer references the bucket count")
        _register, page = adrp
        _destination, _base, immediate = count_load
        count_offset = virtual_to_file(image, page + immediate)
        count = struct.unpack_from("<I", image, count_offset)[0]
        records = []
        for table in buckets:
            offset = virtual_to_file(image, table)
            records.append(
                [
                    list(struct.unpack_from("<11d", image, offset + index * 0x58))
                    for index in range(count)
                ]
            )
        if records[0][-1][0] != -1.0 or records[1][-1][0] != -1.0:
            raise ValueError(f"{name} parameter table lost its catch-all bucket")
        return {
            "buckets": count,
            "record_bytes": 0x58,
            "default_table": buckets[0],
            "variant_table": buckets[1],
            "default_thresholds": [record[0] for record in records[0]],
            "variant_thresholds": [record[0] for record in records[1]],
            "default_records": records[0],
            "variant_records": records[1],
        }

    return {
        "die_dependent": True,
        "producer": G17_POPULATE_LINEAR_POWER_TRANSFER,
        "formula": (
            "100 * (row_sum(state) - row_sum(base_state)) / "
            "(row_sum(maximum_state) - row_sum(base_state))"
        ),
        "maximum_state_value": 100,
        "state_count_source_offset": 0x1B310,
        "afr_state_count_source_offset": 0x1C4E8,
        "tables": [
            {
                "offset": 0x18C8,
                "entries": 16,
                "base_state": 0,
                "matrix_source_offset": 0x1C630,
                "matrix_row_bytes": 0x40,
                "matrix_column_count_offset": 0x4E4,
                "matrix_producer": G17_POPULATE_MAX_PERF_POWER,
                "matrix_producer_vtable_slot": G17_POPULATE_MAX_PERF_POWER_VTABLE_SLOT,
                "leakage": G17_CALCULATE_VDD_GPU_LEAKAGE,
                "voltage_exponent": 1.28,
                "dynamic_coefficient": 20.15,
                "clamp": 48500.0,
            },
            {
                "offset": 0x1948,
                "entries": 16,
                "base_state": 0,
                "matrix_source_offset": 0x1CA30,
                "matrix_row_bytes": 8,
                "matrix_column_count_offset": 0x4EC,
                "matrix_producer": G17_POPULATE_MAX_PERF_POWER_CS,
                "matrix_producer_vtable_slot": G17_POPULATE_MAX_PERF_POWER_CS_VTABLE_SLOT,
                "voltage_source_offset": 0x1C538,
                "leakage": G17_CALCULATE_AFR_LEAKAGE,
                "voltage_exponent": 1.0,
                "dynamic_coefficient": [21.7, 12.29],
                "clamp": [38600.0, 24800.0],
                "chip_variant_offset": 0x4A0,
            },
        ],
        "chip_leakage": {
            "producer": G17_POPULATE_CHIP_LEAKAGE,
            "fuse_physical_address": physical,
            "fuse_bytes": 0x1000,
            "fuse_word_offsets": [0x198, 0x19C, 0x1A0],
            "core_selector_table": selector_table,
            "core_selectors": selectors,
            "core_descriptors": descriptors,
            "variant_scales": {
                "0x21": {"primary_multiplier": 2, "secondary_divisor": 2},
                "other_g17": {"primary_multiplier": 1, "secondary_divisor": 4},
            },
            "group_field": {
                "low_word_offset": 0x19C,
                "high_word_offset": 0x1A0,
                "right_shift": 25,
                "width": 12,
                "multiplier": 2,
            },
            "core_leakage_offset": 0xE50,
            "core_leakage_second_offset": 0xED0,
            "group_leakage_offset": 0xF20,
            "holder_member": 0x5B0,
        },
        "leakage_model": {
            "equation": G17_APPLY_LEAKAGE_EQUATION,
            "temperature": 110.0,
            "input_linear": True,
            "pow_terms": 4,
            "factor_formula": (
                "pow(2,(T-105)/c1) * "
                "pow(min(V,c7)/min(c7,.75),c4*(1-c5*(T-105)/20)) * "
                "min(V,c7,c6)/min(c7,c6,.75) * "
                "pow(1+c2*(1-c3*(T-105)/20),"
                "(max(V,c6)-max(c6,.75))/.05) * "
                "pow(c9,c8*max(V-1.06,0)*(1+c10*(T-105)^2/(T+273.15)))"
            ),
            "vdd_gpu": leakage_table(G17_CALCULATE_VDD_GPU_LEAKAGE),
            "afr": leakage_table(G17_CALCULATE_AFR_LEAKAGE),
        },
    }


def stores_covering_any(code: bytes, targets: set[int]) -> dict[int, list[tuple[int, int]]]:
    """One decode pass returning covering stores for every target and base.

    Same coverage rules as stores_covering, but sweeping each base register
    separately costs a full rescan per register; this walks the code once.
    """

    unscaled_widths = {
        0x38000000: 1, 0x78000000: 2, 0xB8000000: 4, 0xF8000000: 8,
        0xBC000000: 4, 0xFC000000: 8, 0x3C800000: 16,
    }
    pair_widths = {
        0x29000000: 4, 0xA9000000: 8, 0x2D000000: 4, 0x6D000000: 8, 0xAD000000: 16,
    }
    hits: dict[int, list[tuple[int, int]]] = {}

    def record(base: int, low: int, high: int, site: int) -> None:
        for target in targets:
            if low <= target < high:
                hits.setdefault(target, []).append((base, site))

    for offset, word in words(code):
        store = decode_str_unsigned(word)
        if store is not None:
            _source, base, immediate, width = store
            record(base, immediate, immediate + width, offset)
            continue
        width = unscaled_widths.get(word & 0xFFE00C00)
        if width is not None:
            immediate = (word >> 12) & 0x1FF
            if immediate & 0x100:
                immediate -= 0x200
            record((word >> 5) & 0x1F, immediate, immediate + width, offset)
            continue
        width = pair_widths.get(word & 0xFFC00000)
        if width is not None:
            immediate = (word >> 15) & 0x7F
            if immediate & 0x40:
                immediate -= 0x80
            immediate *= width
            record((word >> 5) & 0x1F, immediate, immediate + width * 2, offset)
    return hits


def stores_covering(code: bytes, base: int, target: int) -> list[int]:
    """Offsets of any store through `base` whose bytes cover `target`.

    Used to prove a struct byte is never written, so it keeps whatever cleared
    it. Widths matter: a byte can be covered by a wider store at a lower
    offset, or by either half of a store pair.
    """

    hits: list[int] = []
    unscaled_widths = {
        0x38000000: 1,
        0x78000000: 2,
        0xB8000000: 4,
        0xF8000000: 8,
        0xBC000000: 4,
        0xFC000000: 8,
        0x3C800000: 16,
    }
    pair_widths = {
        0x29000000: 4,
        0xA9000000: 8,
        0x2D000000: 4,
        0x6D000000: 8,
        0xAD000000: 16,
    }
    for offset, word in words(code):
        store = decode_str_unsigned(word)
        if store is not None:
            _source, store_base, immediate, width = store
            if store_base == base and immediate <= target < immediate + width:
                hits.append(offset)
            continue
        width = unscaled_widths.get(word & 0xFFE00C00)
        if width is not None and (word >> 5) & 0x1F == base:
            immediate = (word >> 12) & 0x1FF
            if immediate & 0x100:
                immediate -= 0x200
            if immediate <= target < immediate + width:
                hits.append(offset)
            continue
        width = pair_widths.get(word & 0xFFC00000)
        if width is not None and (word >> 5) & 0x1F == base:
            immediate = (word >> 15) & 0x7F
            if immediate & 0x40:
                immediate -= 0x80
            immediate *= width
            if immediate <= target < immediate + width * 2:
                hits.append(offset)
    return hits


def recover_g17_perf_state_map_block(
    image: bytes, arm_power_code: bytes
) -> dict[str, object]:
    """Recover the fixed two-bank performance-state map at config +0x19c8."""

    symbols = macho_symbols(image)
    required = (
        FAMILY_GET_PROBE_SCORE,
        PI300_READ_CHIP_INFO,
        G17_READ_CHIP_INFO,
        G17_PARSE_PERF_STATE_MAP_REGS,
    )
    missing = [name for name in required if name not in symbols]
    if missing:
        raise ValueError(f"Mach-O has no {missing[0]} symbol")

    parser = recover_vtable_target(
        image, G17_ACCELERATOR_VTABLE, G17_PERF_STATE_MAP_VTABLE_SLOT
    )
    if parser != symbols[G17_PARSE_PERF_STATE_MAP_REGS]:
        raise ValueError(f"unexpected G17 performance-state map parser {parser:#x}")
    _address, parser_code = symbol_code(image, G17_PARSE_PERF_STATE_MAP_REGS)
    if parser_code != struct.pack("<2I", 0xD503245F, 0xD65F03C0):
        raise ValueError("G17 performance-state map parser is not a no-op")

    pi_address, pi_code = symbol_code(image, PI300_READ_CHIP_INFO)
    g17_address, g17_code = symbol_code(image, G17_READ_CHIP_INFO)
    if len(pi_code) != 0x61C or len(g17_code) != 0x34:
        raise ValueError("unexpected G17 chip-info producer size")
    require_instruction_words_at(
        g17_code,
        "G17 performance-state map enable-byte preservation",
        {
            0x20: 0xBC089260,  # unaligned float at core config +0x89
            0x24: 0x3902127F,  # clear adjacent byte +0x84 only
        },
    )
    call = decode_bl_target(
        g17_address + 0x14, struct.unpack_from("<I", g17_code, 0x14)[0]
    )
    if call != pi_address:
        raise ValueError("G17 chip-info producer does not call its PI_300 base")

    # getProbeScore clears the complete temporary AGXGPUCoreConfig before the
    # selected readChipInfo chain. Neither checked producer writes byte +0x85,
    # so the later TBZ always selects the fixed fallback on G17C.
    for label, code in (("PI_300", pi_code), ("G17", g17_code)):
        if hits := stores_covering(code, 19, 0x85):
            raise ValueError(
                f"{label} chip-info producer writes map enable byte at {hits[0]:#x}"
            )

    probe_address, probe_code = symbol_code(image, FAMILY_GET_PROBE_SCORE)
    if len(probe_code) != 0xC78:
        raise ValueError("unexpected AGX family probe-score producer size")
    require_instruction_words_at(
        probe_code,
        "G17 fixed performance-state map fallback",
        {
            0x6C: 0x6F00E400,
            0x70: 0xAD0283E0,
            0x74: 0xAD0383E0,
            0x78: 0x3D8027E0,
            0x7C: 0xF90053FF,
            0x80: 0xAD0183E0,
            0x84: 0xAD0083E0,
            0xB80: 0x394257E8,
            0xB84: 0x36000148,
            0xBB4: 0x91406A68,
            0xBB8: 0x91292109,
            0xBBC: 0x3D800120,
            0xBC0: 0x912A2109,
            0xBC4: 0x6F00E400,
            0xBC8: 0x3D800120,
            0xBCC: 0x91296109,
            0xBD0: 0x912A610A,
            0xBDC: 0x3D800121,
            0xBE0: 0x3D800140,
            0xBE4: 0x9129A109,
            0xBE8: 0x912AA10A,
            0xBF4: 0x3D800121,
            0xBF8: 0x3D800140,
            0xBFC: 0x9129E109,
            0xC00: 0x912AE108,
            0xC0C: 0x3D800121,
            0xC10: 0x3D800100,
        },
    )
    vectors = b"".join(
        read_adrp_load(image, probe_address, probe_code, adrp, load, 16)
        for adrp, load in (
            (0xBAC, 0xBB0),
            (0xBD4, 0xBD8),
            (0xBEC, 0xBF0),
            (0xC04, 0xC08),
        )
    )
    first_bank = list(struct.unpack("<16I", vectors))
    if first_bank != list(range(16)):
        raise ValueError("unexpected G17 fixed performance-state map values")

    # The ARM firmware-data producer clears the whole destination and then
    # copies the two 16-word accelerator banks to +0x19c8 and +0x1a08.
    require_instruction_words_at(
        arm_power_code,
        "G17 performance-state map firmware copy",
        {
            0x804: 0xF9415E68,
            0x808: 0x52833909,
            0x80C: 0x8B09010A,
            0x810: 0xF9414E69,
            0x814: 0x91406929,
            0x818: 0x6F00E400,
            0x81C: 0xAD030140,
            0x820: 0xAD020140,
            0x824: 0xAD010140,
            0x828: 0xAD000140,
            0x82C: 0xB94A492A,
            0x830: 0xB919C90A,
            0x834: 0xB94A892A,
            0x838: 0xB91A090A,
            0x91C: 0xB94A852A,
            0x920: 0xB91A050A,
            0x924: 0xB94AC529,
            0x928: 0xB91A4509,
        },
    )

    return {
        "offset": 0x19C8,
        "bytes": 0x80,
        "entries_per_bank": 16,
        "source_offsets": [0x1AA48, 0x1AA88],
        "enable_byte_offset": 0x85,
        "enable_byte_value": 0,
        "parser_vtable_slot": G17_PERF_STATE_MAP_VTABLE_SLOT,
        "parser": G17_PARSE_PERF_STATE_MAP_REGS,
        "banks": [
            {"offset": 0x19C8, "values": first_bank},
            {"offset": 0x1A08, "values": [0] * 16},
        ],
    }


def recover_g17_aux_performance_layout(
    image: bytes, arm_power_code: bytes
) -> dict[str, object]:
    """Recover the G17 CS/AFR DeviceTree and firmware block layouts."""

    symbols = macho_symbols(image)
    required = (POPULATE_AUX_PERF_STATE_INFO, G17_GET_PERF_STATE_CAP)
    missing = [name for name in required if name not in symbols]
    if missing:
        raise ValueError(f"Mach-O has no {missing[0]} symbol")
    target = recover_vtable_target(
        image, G17_ACCELERATOR_VTABLE, G17_GET_PERF_STATE_CAP_VTABLE_SLOT
    )
    if target != symbols[G17_GET_PERF_STATE_CAP]:
        raise ValueError(f"unexpected G17 performance-state cap target {target:#x}")

    _address, parser_code = symbol_code(image, POPULATE_AUX_PERF_STATE_INFO)
    _address, cap_code = symbol_code(image, G17_GET_PERF_STATE_CAP)
    for property_name in (b"cs-perf-states\0", b"afr-perf-states\0"):
        if property_name not in image:
            raise ValueError(f"missing {property_name[:-1].decode()} property name")

    require_instruction_sequence(
        parser_code,
        "G17 auxiliary performance property selector",
        (
            0x7100045F,  # clock domain 1 selects CS, 2 selects AFR
            0x5280A128,  # feature byte +0x509
            0x9A880508,  # domain 2 selects +0x50a
            0x8B080008,
            0x39400108,
            0xF900A07F,  # clear the complete 0x148-byte destination
            0x6F00E400,
            0xAD090060,
            0xAD080060,
            0xAD070060,
            0xAD060060,
            0xAD050060,
            0xAD040060,
            0xAD030060,
            0xAD020060,
            0xAD010060,
            0xAD000060,
            0x36000588,
        ),
    )
    require_instruction_sequence(
        parser_code,
        "G17 auxiliary performance dimensions",
        (
            0xA9402ACB,  # rail count, state count
            0x52800108,
            0x2A0A1108,
            0x52800209,
            0x1B0B2508,  # exact record byte count
            0x51004549,
            0x6B08001F,
            0x3A4F2920,
            0x54001043,
            0xB944EEA8,
            0x7100097F,  # at most two voltage rails
            0x7A4B9100,
            0x54000FC1,
            0x29002E8A,  # publish state count and rail count
            0x340007AB,
        ),
    )
    require_instruction_sequence(
        parser_code,
        "G17 auxiliary voltage and frequency conversion",
        (
            0xA9400E30,  # voltage_uV, frequency_Hz
            0xD343FE10,
            0x9BCC7E10,
            0xD344FE10,  # exact unsigned division by 1000
            0xB8008410,  # state-major two-column voltage table
            0x91004230,
            0xB8004423,  # frequency table
        ),
    )
    require_instruction_sequence(
        parser_code,
        "G17 auxiliary SRAM voltage clamp",
        (
            0xB840458F,  # per-rail default SRAM voltage
            0xB85801B0,  # corresponding core voltage
            0x6B0F021F,
            0x1A8F820F,  # max(core, default)
            0xB80045AF,
        ),
    )
    if cap_code[:24] != struct.pack(
        "<6I",
        0xD503245F,
        0x721E783F,  # only CS/AFR domains are accepted
        0x54000081,
        0x3900005F,
        0x528001C0,  # both domains have cap 14 on G17C
        0xD65F03C0,
    ):
        raise ValueError("unexpected G17 auxiliary performance-state cap provider")

    for label, sequence in (
        (
            "CS",
            (
                0xB943A109,
                0x5100052B,
                0xB91A49AB,  # config +0x1a48 = state_count - 1
                0xB94F3E6B,
                0xB91A4DAB,  # config +0x1a4c = domain cap
                0x34000489,
                0xD2800009,
                0x9140714A,
                0x910EA14A,  # source frequency table
                0x52834A0B,
                0x8B0B01AB,  # destination +0x1a50
                0x9111A10C,  # source SRAM table
                0x5283620E,
                0x8B0E01AD,  # destination +0x1b10
            ),
        ),
        (
            "AFR",
            (
                0xB944E909,
                0x5100052B,
                0xB91B91AB,  # config +0x1b90 = state_count - 1
                0xB94F426B,
                0xB91B95AB,  # config +0x1b94 = domain cap
                0x34000489,
                0xD2800009,
                0x9140714A,
                0x9113C14A,  # source frequency table
                0x5283730B,
                0x8B0B01AB,  # destination +0x1b98
                0x9116C10C,  # source SRAM table
                0x52838B0E,
                0x8B0E01AD,  # destination +0x1c58
            ),
        ),
    ):
        require_instruction_sequence(
            arm_power_code, f"G17 {label} performance block binding", sequence
        )
    require_instruction_sequence(
        arm_power_code,
        "G17 auxiliary voltage row copy",
        (
            0xB8580200,  # source core voltage at SRAM pointer - 0x80
            0xB8180220,  # destination core voltage at SRAM pointer - 0x80
            0xB8404600,
            0xB8004620,  # source/destination SRAM voltage
        ),
    )

    return {
        "properties": ["cs-perf-states", "afr-perf-states"],
        "device_tree_encoding": {
            "word_bytes": 8,
            "header": ["rail_count", "state_count"],
            "records": ["voltage_uv", "frequency_hz"],
            "trailer": "default_sram_voltage_uv_per_rail",
            "voltage_divisor": 1000,
            "sram_policy": "max(core_mv, default_sram_mv)",
        },
        "source_layout": {
            "bytes": 0x148,
            "state_capacity": 16,
            "rail_capacity": 2,
            "state_count_offset": 0,
            "rail_count_offset": 4,
            "frequency_offset": 8,
            "voltage_offset": 0x48,
            "sram_voltage_offset": 0xC8,
        },
        "firmware_blocks": [
            {"domain": "CS", "offset": 0x1A48, "bytes": 0x148},
            {"domain": "AFR", "offset": 0x1B90, "bytes": 0x148},
        ],
        "firmware_layout": {
            "max_state_offset": 0,
            "domain_cap_offset": 4,
            "frequency_offset": 8,
            "voltage_offset": 0x48,
            "sram_voltage_offset": 0xC8,
        },
        "domain_cap": 14,
        "cap_vtable_slot": G17_GET_PERF_STATE_CAP_VTABLE_SLOT,
    }


def recover_firmware_config_reads(firmware: bytes) -> dict[str, object]:
    magic = find_materialized_constant(firmware, INTERFACE_MAGIC)
    if len(magic) != 1:
        raise ValueError(f"expected one firmware interface magic sequence, found {len(magic)}")
    _magic_start, magic_end, _register = magic[0]
    code = firmware[magic_end : magic_end + 0x800]
    origins: dict[int, tuple[int, bool]] = {}
    constants: dict[int, int] = {}
    reads: set[tuple[int, int, bool]] = set()

    for _offset, word in words(code):
        move_x = decode_move_wide(word)
        move_w = decode_movz_w(word)
        if move_x is not None and move_x[0] == "movz":
            constants[move_x[1]] = move_x[2] << move_x[3]
            origins.pop(move_x[1], None)
            continue
        if move_w is not None:
            constants[move_w[0]] = move_w[1]
            origins.pop(move_w[0], None)
            continue

        load = decode_load_unsigned(word)
        if load is not None:
            destination, base, immediate, width = load
            if base in origins:
                base_offset, indexed = origins[base]
                reads.add((base_offset + immediate, width, indexed))
            if width == 8 and base == 19 and immediate == 0:
                origins[destination] = (0, False)
            else:
                origins.pop(destination, None)
            constants.pop(destination, None)
            continue

        register_load = decode_load_register(word)
        if register_load is not None:
            destination, base, offset_register, width = register_load
            if base in origins and offset_register in constants:
                base_offset, indexed = origins[base]
                reads.add((base_offset + constants[offset_register], width, indexed))
            origins.pop(destination, None)
            constants.pop(destination, None)
            continue

        addition = decode_add_immediate(word)
        if addition is not None:
            destination, source, immediate = addition
            if source in origins:
                base_offset, indexed = origins[source]
                origins[destination] = (base_offset + immediate, indexed)
            else:
                origins.pop(destination, None)
            if source in constants:
                constants[destination] = constants[source] + immediate
            else:
                constants.pop(destination, None)
            continue

        register_add = decode_add_register(word)
        if register_add is not None:
            destination, first, second, shift = register_add
            if first in origins:
                base_offset, indexed = origins[first]
                if second in constants:
                    origins[destination] = (
                        base_offset + (constants[second] << shift), indexed
                    )
                else:
                    origins[destination] = (base_offset, True)
            else:
                origins.pop(destination, None)
            constants.pop(destination, None)
            continue

        pair = decode_pair_q(word)
        if pair is not None and pair[0] == "load" and pair[3] in origins:
            _kind, _first, _second, base, immediate = pair
            base_offset, indexed = origins[base]
            reads.add((base_offset + immediate, 32, indexed))

    required = {
        (0x8F0, 8, False),
        (0xE90, 16, False),
        (0xFC8, 4, True),
        (0x1008, 4, True),
        (0x1408, 4, True),
        (0x19C8, 32, False),
        (0x2610, 8, False),
        (0x26F9, 1, False),
    }
    if not required.issubset(reads):
        raise ValueError(f"incomplete firmware hardware-config read map: {required - reads}")

    copied_pattern = struct.pack(
        "<5I",
        0xF9400268,  # ldr x8, [x19]
        0x52837209,  # mov w9, #0x1b90
        0x911442C0,  # add x0, x22, #0x510
        0x8B090101,  # add x1, x8, x9
        0x52802902,  # mov w2, #0x148
    )
    if copied_pattern not in code:
        raise ValueError("firmware 0x1b90 configuration copy was not found")

    return {
        "firmware_direct_reads": [
            {"offset": offset, "bytes": width, "indexed": indexed}
            for offset, width, indexed in sorted(reads)
        ],
        "firmware_bulk_reads": [
            {"offset": 0x19C8, "bytes": 0x80},
            {"offset": 0x1B90, "bytes": 0x148},
        ],
    }


def recover_device_control_ring_bindings(
    allocations: list[dict[str, int]], code: bytes
) -> list[dict[str, object]]:
    by_members = {
        (item["host_cpu_member"], item["host_gpu_member"]): item["bytes"]
        for item in allocations
    }
    roles = (
        (0, 0xAD8, 0xAE0, 0xAE8, 0xAF0, 0xAF8, 0xAA0),
        (1, 0xC08, 0xC10, 0xC18, 0xC20, 0xC28, 0xBD0),
    )
    published: dict[int, set[int]] = {}
    instructions = list(words(code))
    for index, (_offset, word) in enumerate(instructions):
        store = decode_str_x(word)
        if store is None or store[0] != 0 or store[1] != 8:
            continue
        for _previous_offset, previous_word in instructions[max(0, index - 3) : index]:
            load = decode_ldr_x(previous_word)
            if load is not None and load[0] == 8 and load[1] == 19:
                published.setdefault(load[2], set()).add(store[2])

    result = []
    for role, obj, state_cpu, state_gpu, entries_cpu, entries_gpu, shared in roles:
        if by_members.get((state_cpu, state_gpu)) != 0x30:
            raise ValueError(
                f"role {role} device-control state allocation is not 0x30 bytes"
            )
        if by_members.get((entries_cpu, entries_gpu)) != 0x4000:
            raise ValueError(
                f"role {role} device-control entries allocation is not 0x4000 bytes"
            )
        offsets = published.get(shared, set())
        expected = {0x180, 0x188, 0x190, 0x198}
        if not expected.issubset(offsets):
            raise ValueError(
                f"role {role} device-control addresses are not published through "
                f"host member {shared:#x}: {sorted(offsets)}"
            )
        result.append(
            {
                "role": role,
                "host_object_member": obj,
                "host_state_cpu_member": state_cpu,
                "host_state_gpu_member": state_gpu,
                "host_entries_cpu_member": entries_cpu,
                "host_entries_gpu_member": entries_gpu,
                "state_bytes": 0x30,
                "entries_bytes": 0x4000,
                "firmware_shared_offsets": {
                    "read_index_address": 0x1A0,
                    "cfi_index_address": 0x1A8,
                    "write_index_address": 0x1B0,
                    "entries_address": 0x1B8,
                },
            }
        )
    return result


def recover_ring_accessor(code: bytes) -> tuple[int, int]:
    loads = []
    bounds = []
    for _offset, word in words(code):
        load = decode_ldr_w(word)
        if load is not None and load[0] == 0:
            loads.append(load)
        compare = decode_cmp_w_immediate(word)
        if compare is not None and compare[0] == 0:
            bounds.append(compare[1])
    if len(loads) != 1 or len(bounds) != 1:
        raise ValueError("accelerator ring accessor is not a single checked load")
    return loads[0][2], bounds[0]


def recover_entry_stride(code: bytes) -> int:
    candidates = []
    previous: tuple[int, int] | None = None
    for _offset, word in words(code):
        move = decode_movz_w(word)
        if move is not None:
            previous = move
            continue
        multiply = decode_umaddl(word)
        if multiply is not None and multiply[3] == 31 and previous is not None:
            register, value = previous
            if register in multiply[1:3]:
                candidates.append(value)
        previous = None
    if len(candidates) != 1:
        raise ValueError(f"expected one ring entry stride, found {candidates}")
    return candidates[0]


def recover_accelerator_command_fields(code: bytes) -> dict[str, dict[str, int]]:
    expected = {
        0x08: (8, "channel_data_address"),
        0x10: (4, "command_type"),
        0x14: (2, "submission_index"),
        0x16: (1, "channel_id"),
        0x17: (1, "flags"),
    }
    fields: dict[str, dict[str, int]] = {}
    for _offset, word in words(code):
        store = decode_str_unsigned(word)
        if store is None or store[1] != 1 or store[2] not in expected:
            continue
        _source, _base, field_offset, width = store
        expected_width, name = expected[field_offset]
        if width != expected_width:
            raise ValueError(f"unexpected width for accelerator command field {field_offset:#x}")
        fields[name] = {"offset": field_offset, "bytes": width}
    if set(fields) != {item[1] for item in expected.values()}:
        raise ValueError(f"incomplete accelerator command fields: {sorted(fields)}")
    return fields


def recover_accelerator_command_contract(code: bytes) -> dict[str, object]:
    # This is the complete pinned G17C encoder, not just a sample of its
    # stores. In particular, it proves that the first qword is preserved.
    require_instruction_sequence(
        code,
        "complete accelerator data-master encoder",
        (
            0xD503245F,  # bti c
            0xB9001022,  # command type -> entry +0x10
            0xF9404068,  # channel state GPU address <- channel +0x80
            0xF9000428,  # -> entry +0x08
            0x79002824,  # submission index -> entry +0x14
            0xB9401868,  # channel ID <- channel +0x18
            0x39005828,  # -> entry +0x16
            0x3940F068,  # channel flag <- channel +0x3c
            0x52800029,  # 1
            0x0A280128,  # flags = 1 & ~channel_flag
            0x39005C28,  # -> entry +0x17
            0xD65F03C0,  # ret
        ),
    )
    return {
        "reserved_000": {
            "offset": 0,
            "bytes": 8,
            "encoder_action": "preserved",
            "vinix_policy": "zero_before_encode",
        },
        "channel_sources": {
            "channel_data_address": {"channel_offset": 0x80, "bytes": 8},
            "channel_id": {"channel_offset": 0x18, "bytes": 4},
            "channel_flag": {"channel_offset": 0x3C, "bytes": 1},
        },
        "flags_formula": "1 & ~channel_flag",
    }


def recover_data_master_submission_sequence(
    code: bytes, command_type: int
) -> dict[str, object]:
    # The three producers have the same publication tail. The only changing
    # instruction is the immediate command type passed to the virtual encoder.
    if not 0 <= command_type <= 2:
        raise ValueError(f"invalid data-master command type {command_type}")
    type_instruction = 0x52800002 | (command_type << 5)
    require_instruction_sequence(
        code,
        f"data-master command type {command_type} publication",
        (
            0xB9400284,  # submission index
            0xF94002B0,
            0xAA1503F1,
            0xF2F9B431,
            0xDAC11A30,
            0xD2804F11,  # encoder vtable slot 0x278
            0x8B110210,
            0xF9400208,
            0xAA1503E0,
            0xF94007E1,  # entry returned by nextEntry
            type_instruction,
            0xAA1303E3,  # channel
            0xF2E058F0,
            0xD73F0910,  # encodeAcceleratorRingCommand
            0xD5033BBF,  # dmb ish before publishing the index
            0xF94002D0,
            0xAA1603F1,
            0xF2F3D511,
            0xDAC11A30,
            0xF8438E08,  # getWriteIndex vtable slot 0x38
            0xAA1603E0,
            0xF2F0EB70,
            0xD73F0910,
            0x11000408,  # write + 1
            0xF94002D0,
            0xAA1603F1,
            0xF2F3D511,
            0xDAC11A30,
            0xF8410E09,  # setWriteIndex vtable slot 0x10
            0x12001D01,  # & 0xff
            0xAA1603E0,
            0xF2E27510,
            0xD73F0930,
        ),
    )
    return {
        "command_type": command_type,
        "publish_barrier": "dmb ish",
        "next_write_index": "(write_index + 1) & 0xff",
    }


def recover_data_master_submission_protocol(
    image: bytes, next_entry_address: int
) -> dict[str, object]:
    commands = {}
    for label, (symbol, command_type) in SUBMIT_DATA_MASTER_CHANNELS.items():
        _address, code = symbol_code(image, symbol)
        if not any(
            decode_bl_target(_address + offset, word) == next_entry_address
            for offset, word in words(code)
        ):
            raise ValueError(f"{label} submission does not reserve a data-master entry")
        commands[label] = recover_data_master_submission_sequence(code, command_type)

    return {
        "serialized_by": "IOCommandGate",
        "usable_entries": 255,
        "full_condition": "((write_index + 1) & 0xff) == read_index",
        "commands": commands,
    }


def recover_g17_data_master_ring_bindings(
    allocations: list[dict[str, int]], init_code: bytes
) -> dict[str, object]:
    """Recover the 3 command-type x 4 priority data-master ring matrix.

    These are distinct from the two role-local device-control rings at host
    members 0xad8 and 0xc08. Each data-master object has a 0x28-byte host
    stride and owns exact 0x30/0x1800-byte state/entry allocations. The host
    publishes the twelve address records into the primary 0x79800-byte shared
    region as four 0x60-byte priority records.
    """

    by_members = {
        (item["host_cpu_member"], item["host_gpu_member"]): item["bytes"]
        for item in allocations
    }
    command_bases = {"TA": 0x3B0, "3D": 0x450, "CL": 0x4F0}
    bindings = []
    for priority in range(4):
        for command_type, (label, base) in enumerate(command_bases.items()):
            host_object = base + priority * 0x28
            state_pair = (host_object + 0x08, host_object + 0x10)
            entries_pair = (host_object + 0x18, host_object + 0x20)
            if by_members.get(state_pair) != 0x30:
                raise ValueError(
                    f"G17 {label} priority {priority} state allocation is not 0x30 bytes"
                )
            if by_members.get(entries_pair) != 0x1800:
                raise ValueError(
                    f"G17 {label} priority {priority} entry allocation is not 0x1800 bytes"
                )
            bindings.append(
                {
                    "priority": priority,
                    "command": label,
                    "command_type": command_type,
                    "host_object_member": host_object,
                    "host_state_cpu_member": state_pair[0],
                    "host_state_gpu_member": state_pair[1],
                    "host_entries_cpu_member": entries_pair[0],
                    "host_entries_gpu_member": entries_pair[1],
                    "state_bytes": 0x30,
                    "entries_bytes": 0x1800,
                    "primary_large_region_offset": priority * 0x60
                    + command_type * 0x20,
                }
            )

    # initFirmwareData first resets all four 0x28-byte objects in each type,
    # then publishes read/CFI/write/entry addresses in 0x20-byte subrecords.
    # Pin the loop extents and every first-priority store so a changed matrix
    # cannot silently retain this derived layout.
    require_instruction_words_at(
        init_code,
        "G17 data-master ring matrix",
        {
            0x524: 0x9100A2F7,  # next 0x28-byte ring object
            0x528: 0xF10282FF,  # four objects, total 0xa0 bytes
            0x530: 0xD2800016,  # publication priority/object offset
            0x55C: 0x52800B17,  # first record store cursor 0x58
            0x568: 0x8B160278,  # object = firmware + priority * 0x28
            0x56C: 0x910EC315,  # TA object base 0x3b0
            0x5DC: 0xF81A8100,  # TA read address -> record +0x00
            0x64C: 0xF81B0100,  # TA CFI address -> record +0x08
            0x6C0: 0xF81B8100,  # TA write address -> record +0x10
            0x70C: 0xF81C0100,  # TA entries address -> record +0x18
            0x780: 0xF81C8100,  # 3D read address -> record +0x20
            0x7F0: 0xF81D0100,  # 3D CFI address -> record +0x28
            0x864: 0xF81D8100,  # 3D write address -> record +0x30
            0x8B0: 0xF81E0100,  # 3D entries address -> record +0x38
            0x924: 0xF81E8100,  # CL read address -> record +0x40
            0x994: 0xF81F0100,  # CL CFI address -> record +0x48
            0xA08: 0xF81F8100,  # CL write address -> record +0x50
            0xA54: 0xF9000100,  # CL entries address -> record +0x58
            0xA58: 0x910182F7,  # next 0x60-byte priority record
            0xA5C: 0x9100A2D6,  # next 0x28-byte object in each type
            0xA60: 0xF10762FF,  # four records, total 0x180 bytes
        },
    )
    return {
        "priorities": 4,
        "command_types": 3,
        "host_object_stride": 0x28,
        "address_record_bytes": 0x20,
        "priority_record_bytes": 0x60,
        "primary_large_region_offset": 0,
        "primary_large_region_bytes": 0x180,
        "bindings": bindings,
    }


def recover_g17_data_master_doorbells(image: bytes) -> dict[str, object]:
    """Recover the work-doorbell message encoded by each ARM submit wrapper."""

    symbols = macho_symbols(image)
    commands = {}
    for label, (wrapper, base, command_type) in ARM_SUBMIT_DATA_MASTER_CHANNELS.items():
        if wrapper not in symbols or base not in symbols:
            raise ValueError(f"Mach-O is missing G17 {label} submit wrapper")
        address, code = symbol_code(image, wrapper)
        if not any(
            decode_bl_target(address + offset, word) == symbols[base]
            for offset, word in words(code)
        ):
            raise ValueError(f"G17 {label} wrapper no longer calls the base submitter")

        type_words = (
            (0xD2E01069,)
            if command_type == 0
            else (0xD2800009 | (command_type << 5), 0xF2E01069)
        )
        require_instruction_sequence(
            code,
            f"G17 {label} work doorbell",
            (
                0x531E0A68,  # priority[2:0] -> message bits [4:2]
                0xF94CEE80,  # primary role transport at host +0x19d8
                *type_words,  # command type in message bits [1:0], type 0x83
                0xF9400010,
                0xAA0003F1,
                0xF2F9B431,
                0xDAC11A30,
                0xD2811511,  # transport doorbell-send slot 0x8a8
                0x8B110210,
                0xF940020A,
                0xAA1003E3,
                0xAA090101,  # message = (0x83 << 48) | priority | type
                0xAA0A03F0,
                0x52800002,
            ),
        )
        commands[label] = {
            "command_type": command_type,
            "low_bits": command_type,
        }

    return {
        "message_type": 0x83,
        "transport_host_member": 0x19D8,
        "transport_role": 0,
        "transport_send_vtable_slot": 0x8A8,
        "priority_shift": 2,
        "priority_bits": 3,
        "formula": "(0x83 << 48) | (priority << 2) | command_type",
        "commands": commands,
    }


def recover_vector_copy_size(code: bytes) -> int:
    ranges: dict[tuple[str, int], set[int]] = {}
    for _offset, word in words(code):
        pair = decode_pair_q(word)
        if pair is None:
            continue
        kind, _first, _second, base, immediate = pair
        ranges.setdefault((kind, base), set()).add(immediate)
    complete = [
        max(offsets) + 32
        for offsets in ranges.values()
        if offsets == {0, 0x20}
    ]
    if complete.count(0x40) < 2:
        raise ValueError("device-control path does not contain matching 64-byte vector copies")
    return 0x40


def recover_driver_accelerator_layouts(image: bytes) -> dict[str, object]:
    layouts = []
    for entry, prefix in (
        ("data_master", DATA_MASTER_RING),
        ("device_control", DEVICE_CONTROL_RING),
    ):
        offsets = {}
        limits = set()
        for field, suffix in RING_ACCESSORS.items():
            _address, code = symbol_code(image, prefix + suffix)
            offset, limit = recover_ring_accessor(code)
            offsets[field] = offset
            limits.add(limit)
        if offsets != {"read_index": 0, "cfi_index": 0x10, "write_index": 0x20}:
            raise ValueError(f"unexpected {entry} ring offsets: {offsets}")
        if limits != {256}:
            raise ValueError(f"unexpected {entry} ring entry limits: {limits}")
        layouts.append({"entry": entry, "indices": offsets, "entries": 256})

    next_entry_address, next_entry = symbol_code(image, NEXT_DATA_MASTER_ENTRY)
    data_master_size = recover_entry_stride(next_entry)
    _address, encoder = symbol_code(image, ENCODE_ACCELERATOR_COMMAND)
    fields = recover_accelerator_command_fields(encoder)
    contract = recover_accelerator_command_contract(encoder)
    submission = recover_data_master_submission_protocol(image, next_entry_address)
    _address, submit_control = symbol_code(image, SUBMIT_DEVICE_CONTROL)
    device_control_size = recover_vector_copy_size(submit_control)
    if data_master_size != 0x18 or device_control_size != 0x40:
        raise ValueError(
            f"unexpected accelerator entry sizes: {data_master_size:#x}, "
            f"{device_control_size:#x}"
        )
    return {
        "rings": layouts,
        "state_bytes": 0x30,
        "data_master_entry_bytes": data_master_size,
        "data_master_fields": fields,
        "data_master_contract": contract,
        "data_master_submission": submission,
        "device_control_entry_bytes": device_control_size,
    }


def recover_g17_channel_pool_geometry(code: bytes) -> dict[str, object]:
    """Recover the three per-channel firmware resource-pool geometries."""
    instructions = list(words(code))

    def initializer(member: int) -> tuple[int, list[tuple[int, int]]]:
        for index, (_offset, word) in enumerate(instructions):
            move = decode_movz_w(word)
            if move is not None and move[1] == member:
                following = [
                    item
                    for _next_offset, next_word in instructions[index + 1 : index + 24]
                    if (item := decode_movz_w(next_word)) is not None
                ]
                return index, following
        raise ValueError(f"missing G17 channel resource pool {member:#x}")

    _state_index, state_args = initializer(0x11C8)
    if (2, 0xC0) not in state_args or (4, 9) not in state_args or (5, 1) not in state_args:
        raise ValueError("unexpected G17 channel-state pool initializer")

    uncached_index, uncached_args = initializer(0x1348)
    cached_index, cached_args = initializer(0x1408)
    if (4, 9) not in uncached_args or (5, 0) not in uncached_args:
        raise ValueError("unexpected G17 uncached-channel pool initializer")
    if (4, 9) not in cached_args or (5, 1) not in cached_args:
        raise ValueError("unexpected G17 cached-channel pool initializer")

    formula_window = instructions[max(0, uncached_index - 12) : uncached_index]
    base = next(
        (
            value
            for _offset, word in formula_window
            if (move := decode_movz_w(word)) is not None
            for register, value in (move,)
            if register == 20
        ),
        None,
    )
    insertion = next(
        (
            decoded
            for _offset, word in formula_window
            if (decoded := decode_bfi_x(word)) is not None and decoded[0] == 20
        ),
        None,
    )
    if base != 0x70 or insertion is None or insertion[2:] != (7, 28):
        raise ValueError("unexpected G17 channel-memory pool size formula")
    if cached_index <= uncached_index:
        raise ValueError("cached G17 channel pool precedes uncached pool")

    return {
        "channel_state": {
            "host_pool_member": 0x11C8,
            "element_bytes": 0xC0,
            "caching": 1,
        },
        "uncached_memory": {
            "host_pool_member": 0x1348,
            "element_base_bytes": base,
            "bytes_per_configured_queue": 1 << insertion[2],
            "caching": 0,
        },
        "cached_memory": {
            "host_pool_member": 0x1408,
            "element_base_bytes": base,
            "bytes_per_configured_queue": 1 << insertion[2],
            "caching": 1,
        },
    }


def recover_g17_channel_priority(image: bytes) -> dict[str, object]:
    """Recover the firmware channel-priority fields and canonical profiles.

    The outer data-master ring is selected from state +0x28. Apple's setter
    writes the full 0x1c-byte priority block, so initializing only that selector
    would leave mutually dependent firmware policy fields inconsistent.
    """

    symbols = macho_symbols(image)
    required = (
        GET_CHANNEL_PRIORITY,
        ARM_SET_CHANNEL_PRIORITY,
        AGX_COMMAND_QUEUE_INIT,
    )
    missing = [name for name in required if name not in symbols]
    if missing:
        raise ValueError(f"Mach-O is missing G17 channel-priority symbols: {missing}")

    _address, getter = symbol_code(image, GET_CHANNEL_PRIORITY)
    if len(getter) != 0x10:
        raise ValueError(f"unexpected G17 priority getter size {len(getter):#x}")
    require_instruction_words_at(
        getter,
        "G17 channel-priority getter",
        {
            0x00: 0xD503245F,  # bti c
            0x04: 0xF9402C08,  # channel +0x58 -> shared state
            0x08: 0xB9402900,  # state +0x28 -> data-master priority
            0x0C: 0xD65F03C0,
        },
    )

    _address, setter = symbol_code(image, ARM_SET_CHANNEL_PRIORITY)
    if len(setter) != 0x144:
        raise ValueError(f"unexpected G17 priority setter size {len(setter):#x}")
    require_instruction_words_at(
        setter,
        "G17 channel-priority profiles",
        {
            0x04: 0x7100045F,  # context priority 0/1 split
            0x0C: 0x7100085F,  # context priority 2
            0x14: 0x7100105F,  # context priority 4
            0x1C: 0x7100145F,  # context priority 5
            0x28: 0xB900283F,  # type 5: ring priority 0
            0x30: 0xB9003829,
            0x34: 0x929FFFE9,
            0x3C: 0x340003C2,  # type 0
            0x48: 0x7100049F,  # type 1 QoS cases
            0x50: 0x34000684,
            0x54: 0x7100049F,
            0x60: 0xB9002828,
            0x68: 0xD2FFFFE9,
            0x6C: 0xF9001829,
            0x74: 0xB9004029,
            0x7C: 0x52800028,  # context priority 4/default
            0x80: 0xB9002828,
            0x88: 0xB2607FE9,
            0x8C: 0xF9001829,
            0x94: 0x52800068,  # context priority 2
            0x98: 0xB9002828,
            0xA0: 0xF900183F,
            0xA4: 0xB900403F,
            0xA8: 0xB9002C28,  # duplicate ring priority
            0xAC: 0xB9003C23,  # caller-provided subpriority
            0xB4: 0x52800008,  # context priority 0
            0xB8: 0xB900283F,
            0xC4: 0x929FFFEA,
            0xC8: 0xF900182A,
            0xCC: 0xB9004029,
            0xD4: 0x7100089F,  # QoS 2
            0xE4: 0x52800068,  # QoS 4 selects ring priority 3
            0xF0: 0xF900183F,
            0xF8: 0xB9004029,
            0x100: 0x52800048,  # other QoS values stay on priority 2
            0x10C: 0xD2FFFFE9,
            0x114: 0x52800069,
            0x128: 0x52800048,  # QoS 2 canonical medium profile
            0x134: 0xD2FFFFE9,
            0x13C: 0xB9004028,
        },
    )

    _address, queue_init = symbol_code(image, AGX_COMMAND_QUEUE_INIT)
    require_instruction_words_at(
        queue_init,
        "G17 default channel subpriority",
        {
            0x284: 0x52800048,  # mov w8, #2
            0x288: 0xB9081A68,  # -> command queue +0x818
        },
    )

    # These are the canonical contexts whose state +0x28 values cover all four
    # data-master rings. Context 1 uses Apple's default QoS level 2. A default
    # subpriority of 2 is independently established by AGXCommandQueue::init.
    profiles = [
        {
            "priority": 0,
            "context_priority": 0,
            "qos": 2,
            "fields": [0, 0, 0xFFFFFFFFFFFF0000, 1, 2, 1],
        },
        {
            "priority": 1,
            "context_priority": 4,
            "qos": 2,
            "fields": [1, 1, 0xFFFFFFFF00000000, 0, 2, 0],
        },
        {
            "priority": 2,
            "context_priority": 1,
            "qos": 2,
            "fields": [2, 2, 0xFFFF000000000000, 0, 2, 2],
        },
        {
            "priority": 3,
            "context_priority": 2,
            "qos": 2,
            "fields": [3, 3, 0, 0, 2, 0],
        },
    ]
    return {
        "state_offset": 0x28,
        "bytes": 0x1C,
        "reset_priority": 4,
        "field_offsets": [0x28, 0x2C, 0x30, 0x38, 0x3C, 0x40],
        "field_bytes": [4, 4, 8, 4, 4, 4],
        "default_subpriority": 2,
        "profiles": profiles,
    }


def recover_g17_channel_submit_info(image: bytes) -> dict[str, object]:
    """Recover the 24-byte host submit-info record and its ring-index source."""

    symbols = macho_symbols(image)
    if SUBMIT_COMMAND_TO_FIRMWARE_BLOCK not in symbols:
        raise ValueError("Mach-O is missing G17 submit-to-firmware block")
    _address, code = symbol_code(image, SUBMIT_COMMAND_TO_FIRMWARE_BLOCK)
    if len(code) != 0x32C:
        raise ValueError(f"unexpected G17 submit block size {len(code):#x}")
    require_instruction_words_at(
        code,
        "G17 channel submit-info construction",
        {
            0x24: 0xA9425013,  # captured work queue and channel
            0x28: 0xF9401808,  # captured command descriptor
            0x38: 0xF9403509,  # command GPU address at descriptor +0x68
            0x3C: 0xA9017FFF,  # zero submit-info bytes +0x08..+0x17
            0x54: 0xB940DE8A,  # channel host sequence at +0xdc
            0x58: 0xB940528B,  # host tracking-ring entries at +0x50
            0x64: 0xF9406A8C,  # host tracking-ring pointer at +0xd0
            0x80: 0xF90001A9,  # retain the command address before submission
            0x84: 0x11000549,  # increment the host sequence
            0x88: 0xB900DE89,
            0x8C: 0xF940328A,  # uncached channel-control CPU address
            0x90: 0xB9404156,  # published write index at control +0x40
            0xB8: 0x290127F6,  # info +0x00/+0x04
            0xBC: 0xB940F288,  # channel counter at +0xf0
            0xC0: 0xB90013E8,  # info +0x08
            0xC4: 0xF9400168,
            0xC8: 0xF9402508,  # selected metadata object +0x48
            0xCC: 0xF9000FE8,  # info +0x10
            0x2A8: 0xB940CA88,  # channel data-master type at +0xc8
            0x2BC: 0xF9406660,  # owning accelerator at work queue +0xc8
            0x2C0: 0x910023E2,  # x2 = &submit_info at stack +0x08
            0x2C4: 0x12000343,  # caller flag
            0x2C8: 0xAA1403E1,  # x1 = channel
            0x2D0: 0xD73F0911,  # dispatch TA/3D/CL submit wrapper
        },
    )
    return {
        "bytes": 0x18,
        "fields": {
            "submission_index": {
                "offset": 0x00,
                "bytes": 4,
                "source": "uncached_control.write_index_after_pointer_publication",
                "outer_entry_bytes": 2,
            },
            "host_sequence": {
                "offset": 0x04,
                "bytes": 4,
                "source": "channel.host_sequence_after_increment",
            },
            "channel_counter": {
                "offset": 0x08,
                "bytes": 4,
                "source_channel_member": 0xF0,
            },
            "reserved_00c": {"offset": 0x0C, "bytes": 4, "value": 0},
            "metadata": {
                "offset": 0x10,
                "bytes": 8,
                "selected_object_member": 0x48,
            },
        },
        "dispatch": {
            "data_master_type_channel_member": 0xC8,
            "accelerator_work_queue_member": 0xC8,
        },
    }


def recover_g17_channel_submission_flag(image: bytes) -> dict[str, object]:
    """Recover the first-versus-following submission flag transition.

    The outer-ring encoder samples AGXChannel +0x3c before the work-queue
    block invokes the channel's mark method.  A successful first submission
    therefore encodes flags=1 and marks the channel; following submissions
    encode flags=0 until a priority change invokes the matching unmark method.
    """

    symbols = macho_symbols(image)
    required = (SUBMIT_COMMAND_TO_FIRMWARE_BLOCK, SET_CHANNEL_PRIORITY)
    missing = [name for name in required if name not in symbols]
    if missing:
        raise ValueError(f"Mach-O is missing G17 submission-flag symbols: {missing}")

    mark_symbols = sorted(
        name for name in symbols if name.startswith(MARK_CHANNEL_SUBMITTED_PREFIX)
    )
    unmark_symbols = sorted(
        name for name in symbols if name.startswith(UNMARK_CHANNEL_SUBMITTED_PREFIX)
    )
    if not mark_symbols or len(mark_symbols) != len(unmark_symbols):
        raise ValueError(
            "G17 channel mark/unmark implementations are missing or unbalanced"
        )
    for name in mark_symbols:
        _address, code = symbol_code(image, name)
        require_instruction_sequence(
            code,
            "G17 channel submitted mark",
            (0xD503245F, 0x52800028, 0x3900F008, 0xD65F03C0),
        )
    for name in unmark_symbols:
        _address, code = symbol_code(image, name)
        require_instruction_sequence(
            code,
            "G17 channel submitted unmark",
            (0xD503245F, 0x3900F01F, 0xD65F03C0),
        )

    _address, submit_code = symbol_code(image, SUBMIT_COMMAND_TO_FIRMWARE_BLOCK)
    require_instruction_words_at(
        submit_code,
        "G17 channel submitted transition",
        {
            0x2D4: 0x34000160,  # failed outer submission skips the transition
            0x2D8: 0xF9400290,  # channel vtable
            0x2E8: 0xD2804011,  # mark slot 0x200
            0x2EC: 0x8B110210,
            0x2F0: 0xF9400208,
            0x2F4: 0xAA1403E0,  # channel object
            0x2FC: 0xD73F0910,
        },
    )

    _address, priority_code = symbol_code(image, SET_CHANNEL_PRIORITY)
    require_instruction_words_at(
        priority_code,
        "G17 channel submitted priority reset",
        {
            0x58: 0xF9402E68,  # shared channel state
            0x5C: 0xB9402909,  # current priority at state +0x28
            0x60: 0x6B09029F,
            0x64: 0x540001A0,  # unchanged priority skips the reset
            0x68: 0x12800009,
            0x6C: 0xB9004509,  # invalidate state +0x44
            0x80: 0xD2804111,  # unmark slot 0x208
            0x84: 0x8B110210,
            0x88: 0xF9400208,
            0x8C: 0xAA1303E0,  # channel object
            0x94: 0xD73F0910,
            0x98: 0xD5033BBF,  # state/flag update barrier
        },
    )

    return {
        "channel_member": 0x3C,
        "bytes": 1,
        "initial": 0,
        "outer_flags_formula": "1 & ~channel_flag",
        "first_submission_flags": 1,
        "following_submission_flags": 0,
        "mark_vtable_slot": 0x200,
        "mark_after_successful_outer_submission": True,
        "unmark_vtable_slot": 0x208,
        "unmark_on_priority_change": True,
        "implementations": len(mark_symbols),
    }


def recover_g17_channel_layout(reset_code: bytes, write_code: bytes) -> dict[str, object]:
    """Recover the shared state/control layout used by a G17 work channel."""
    reset_instructions = list(words(reset_code))
    write_instructions = list(words(write_code))

    channel_loads = {
        load[2]
        for _offset, word in reset_instructions + write_instructions
        if (load := decode_ldr_x(word)) is not None and load[1] == 0
    }
    expected_individual_cpu_members = {0x68}
    if not expected_individual_cpu_members.issubset(channel_loads):
        raise ValueError(f"missing G17 channel CPU bindings: {sorted(channel_loads)}")

    state_pair = next(
        (
            pair
            for _offset, word in reset_instructions
            if (pair := decode_ldp_x(word)) is not None
            and pair[2] == 0
            and pair[3] == 0x58
        ),
        None,
    )
    if state_pair is None:
        raise ValueError("missing G17 state/uncached CPU binding pair")

    state_clear_offsets = {
        pair[4]
        for _offset, word in reset_instructions
        if (pair := decode_pair_q(word)) is not None
        and pair[0] == "store"
        and pair[3] == 8
    }
    if state_clear_offsets != {0, 0x20, 0x40, 0x60, 0x80, 0xA0}:
        raise ValueError(f"unexpected G17 channel-state clear: {sorted(state_clear_offsets)}")

    state_stores = {
        (store[2], store[3])
        for _offset, word in reset_instructions
        if (store := decode_str_unsigned(word)) is not None and store[1] == 9
    }
    state_stores.update(
        (store[2], 8)
        for _offset, word in reset_instructions
        if (store := decode_stur_x(word)) is not None and store[1] == 9
    )
    expected_state_stores = {
        (0x00, 8),
        (0x08, 8),
        (0x10, 8),
        (0x18, 4),
        (0x1C, 4),
        (0x20, 4),
        (0x24, 4),
        (0x28, 4),
        (0x44, 4),
        (0x48, 4),
        (0x84, 4),
        (0x9C, 8),
    }
    if not expected_state_stores.issubset(state_stores):
        raise ValueError(f"incomplete G17 channel-state stores: {sorted(state_stores)}")

    uncached_stores = {
        (store[2], store[3])
        for _offset, word in reset_instructions
        if (store := decode_str_unsigned(word)) is not None and store[1] == 10
    }
    expected_uncached_stores = {
        (0x00, 4),
        (0x10, 4),
        (0x20, 4),
        (0x30, 4),
        (0x40, 4),
        (0x50, 4),
        (0x60, 4),
    }
    if not expected_uncached_stores.issubset(uncached_stores):
        raise ValueError(f"incomplete G17 uncached-channel stores: {sorted(uncached_stores)}")

    write_loads = {
        (load[2], load[3])
        for _offset, word in write_instructions
        if (load := decode_load_unsigned(word)) is not None
    }
    expected_write_loads = {(0x00, 4), (0x40, 4), (0x54, 4), (0x60, 4), (0x68, 8)}
    if not expected_write_loads.issubset(write_loads):
        raise ValueError(f"incomplete G17 channel enqueue accesses: {sorted(write_loads)}")
    if not any(
        decoded[2] == 3
        for _offset, word in write_instructions
        if (decoded := decode_ubfiz_x(word)) is not None
    ):
        raise ValueError("G17 cached command-pointer array does not use an 8-byte stride")

    pointer_store_index = next(
        (
            index
            for index, (_offset, word) in enumerate(write_instructions)
            if (store := decode_str_unsigned(word)) is not None
            and store[0] == 1
            and store[2:] == (0, 8)
        ),
        None,
    )
    barrier_index = next(
        (
            index
            for index, (_offset, word) in enumerate(write_instructions)
            if word == 0xD5033BBF  # dmb ish
        ),
        None,
    )
    write_index_store = next(
        (
            index
            for index, (_offset, word) in enumerate(write_instructions)
            if (store := decode_str_unsigned(word)) is not None
            and store[2:] == (0x40, 4)
        ),
        None,
    )
    if (
        pointer_store_index is None
        or barrier_index is None
        or write_index_store is None
        or not pointer_store_index < barrier_index < write_index_store
    ):
        raise ValueError("unexpected G17 channel-pointer publication order")

    return {
        "host_channel_members": {
            "state_cpu": 0x58,
            "uncached_cpu": 0x60,
            "cached_cpu": 0x68,
            "ring_entries": 0x54,
            "state_gpu": 0x80,
            "uncached_gpu": 0x88,
            "cached_gpu": 0x90,
        },
        "state": {
            "bytes": 0xC0,
            "uncached_gpu_address": 0x00,
            "cached_gpu_address": 0x08,
            "context_cookie": 0x10,
            "mode": 0x28,
            "value_048": 0x48,
            "flag_084": 0x84,
            "address_09c": 0x9C,
        },
        "uncached_control": {
            "header_bytes": 0x70,
            "read_index": 0x00,
            "write_index": 0x40,
            "sentinel": 0x50,
            "ring_entries": 0x60,
        },
        "cached_command_pointer_bytes": 8,
        "enqueue": {
            "reserved_entries": 1,
            "pointer_barrier": "dmb ish",
            "write_index_published_last": True,
        },
    }


def decode_orr_register(word: int) -> tuple[int, int, int] | None:
    """Decode the 32-bit register form of ORR (shifted register, no shift)."""
    if word & 0xFFE0FC00 != 0x2A000000:
        return None
    return word & 0x1F, (word >> 5) & 0x1F, (word >> 16) & 0x1F


def decode_ldr_q(word: int) -> tuple[int, int, int] | None:
    """Decode LDR (immediate, unsigned offset) for a 128-bit SIMD register."""
    if word & 0xFFC00000 != 0x3DC00000:
        return None
    destination = word & 0x1F
    base = (word >> 5) & 0x1F
    immediate = ((word >> 10) & 0xFFF) * 16
    return destination, base, immediate


def recover_g17_secondary_performance_block(image: bytes) -> dict[str, object]:
    """Recover the second performance-state block at config +0x1cd8.

    The 0x868 bytes after the AFR block are not opaque.  When the accelerator's
    gate byte is set, initPowerAndPerformanceData zeroes 0x848 bytes at +0x1cd8
    and refills them with a maximum state index, one frequency per state
    converted from Hz to MHz, and two 16-column voltage matrices -- the same
    shape as the primary block at +0xfc4, sourced from the SRAM arrays instead.
    """

    symbols = macho_symbols(image)
    if INIT_POWER_DATA not in symbols:
        raise ValueError(f"Mach-O is missing {INIT_POWER_DATA}")

    _address, code = symbol_code(image, INIT_POWER_DATA)
    require_instruction_words_at(
        code,
        "G17 secondary performance block",
        {
            0x740: 0x395416C8,  # gate byte at accelerator +0x505
            0x744: 0x36000608,  # skipped entirely when clear
            0x74C: 0xF9415E75,  # hardware config
            0x750: 0x52839B08,  # mov w8, #0x1cd8
            0x758: 0x52810901,  # zero 0x848 bytes
            0x760: 0xB94B5A88,  # state count at accelerator +0x1bb58
            0x764: 0x51000509,
            0x768: 0xB91CDAA9,  # count - 1 -> config +0x1cd8
            0x77C: 0x52839B8A,  # frequency table at config +0x1cdc
            0x784: 0x912E828B,  # voltage source at accelerator +0x1bba0
            0x788: 0x5283A38C,  # voltage table at config +0x1d1c
            0x790: 0x529BD06D,  # Hz to MHz reciprocal
            0x794: 0x72A8636D,
            0x7A4: 0x9101016B,  # 0x40-byte source row stride
            0x7A8: 0x9101018C,  # 0x40-byte destination row stride
            0x7B4: 0xB868792E,  # frequency[state]
            0x7B8: 0x9BAD7DCE,
            0x7BC: 0xD372FDCE,
            0x7C0: 0xB828794E,  # -> config frequency table
            0x7C4: 0xB94B5E8E,  # column count at accelerator +0x1bb5c
            0x7E0: 0xB9440211,  # second matrix is 0x400 further on
            0x7E4: 0xB90401F1,
        },
    )

    # The gate byte is chip-info +0x85 relayed through the accelerator.
    # getProbeScore zeroes the whole chip-info record and neither selected
    # G17C reader writes that byte -- the same fact the performance-state map
    # fallback rests on -- so the gate is clear and Apple never fills this
    # block on G17. The layout is recovered; the contents stay zero.
    probe_address, probe_code = symbol_code(image, FAMILY_GET_PROBE_SCORE)
    require_instruction_words_at(
        probe_code,
        "G17 chip-info gate relay",
        {
            0xC2C: 0x3CC802A0,  # chip info +0x80..0x8f
            0xC30: 0x3D814260,  # -> accelerator +0x500..0x50f
        },
    )
    gate_source = 0x500 + (0x85 - 0x80)
    if gate_source != 0x505:
        raise ValueError("chip-info gate byte no longer lands on accelerator +0x505")

    zeroed = 0x848
    block = {
        "populated_on_g17": False,
        "gate_chip_info_byte": 0x85,
        "gate_reason": (
            "getProbeScore clears the chip-info record and no selected G17C "
            "reader writes +0x85, so the producer's TBZ always skips"
        ),
        "offset": 0x1CD8,
        "zeroed_bytes": zeroed,
        "gate_byte": 0x505,
        "max_state_offset": 0x1CD8,
        "frequency_offset": 0x1CDC,
        "voltage_offset": 0x1D1C,
        "sram_voltage_offset": 0x1D1C + 0x400,
        "row_bytes": 0x40,
        "state_count_source": 0x1BB58,
        "column_count_source": 0x1BB5C,
        "frequency_source": 0x1BB60,
        "voltage_source": 0x1BBA0,
        "frequency_conversion": {
            "input": "Hz",
            "output": "MHz",
            "multiplier": 0x431BDE83,
            "right_shift": 50,
        },
    }
    used = (block["sram_voltage_offset"] + 0x400) - block["offset"]
    if used > zeroed:
        raise ValueError("G17 secondary performance block overruns its cleared span")
    block["trailing_bytes"] = zeroed - used
    return block


def config_pointer_stores(
    code: bytes, low: int, high: int
) -> list[dict[str, object]]:
    """List stores into a hardware-config window, following computed bases.

    Matching a store's immediate offset alone is wrong twice over: it
    attributes other objects' fields to the config, and it misses every write
    that materializes its offset into a register first.  Both mistakes were
    made before this existed.  Here the config pointer is tracked from firmware
    member 0x2b8 and through `add` into scratch registers.
    """

    config: set[int] = set()
    immediates: dict[int, int] = {}
    derived: dict[int, int] = {}
    found: list[dict[str, object]] = []

    def kill(register: int) -> None:
        config.discard(register)
        derived.pop(register, None)

    for offset, word in words(code):
        load = decode_ldr_x(word)
        if load is not None and load[1] == 19 and load[2] == 0x2B8:
            derived.pop(load[0], None)
            config.add(load[0])
            continue

        movz = decode_movz_w(word)
        if movz is not None:
            immediates[movz[0]] = movz[1]
            kill(movz[0])
            continue

        register_add = decode_add_register(word)
        if register_add is not None:
            destination, first, second, _shift = register_add
            if first in config and second in immediates:
                kill(destination)
                derived[destination] = immediates[second]
                continue

        immediate_add = decode_add_immediate(word)
        if immediate_add is not None:
            destination, source, immediate = immediate_add
            if source in config:
                kill(destination)
                derived[destination] = immediate
                continue

        target = None
        store = decode_str_unsigned(word)
        if store is not None:
            source, base, immediate, _width = store
            target = (source, base, immediate)
        if target is None:
            store = decode_str_x(word) or decode_stur_x(word)
            if store is not None:
                target = store
        if target is None:
            pair = decode_pair_q(word)
            if pair is not None and pair[0] == "store":
                target = (pair[1], pair[3], pair[4])
        if target is not None:
            source, base, immediate = target
            position = None
            if base in config:
                position = immediate
            elif base in derived:
                position = derived[base] + immediate
            if position is not None and low <= position < high:
                found.append(
                    {
                        "offset": position,
                        "site": offset,
                        "zero_source": source == 31,
                    }
                )
            continue

        for decoder in (decode_ldr_x, decode_ldr_w, decode_add_immediate):
            decoded = decoder(word)
            if decoded is not None:
                kill(decoded[0])
                break

    return found


def recover_g17_chip_info_registers(image: bytes) -> dict[str, object]:
    """Recover the GPU ID registers the chip-info record is decoded from.

    The chip-info fields that feed the late-control block are not opaque
    accelerator state: readChipInfo builds them from the GPU ID register block
    at 0xd04000.  The version register's byte 3 must be 0xb, and its byte 2
    selects the chip variant that later steers the whole power model.
    """

    symbols = macho_symbols(image)
    if PI300_READ_CHIP_INFO not in symbols:
        raise ValueError(f"Mach-O is missing {PI300_READ_CHIP_INFO}")

    _address, code = symbol_code(image, PI300_READ_CHIP_INFO)
    require_instruction_words_at(
        code,
        "G17 GPU identity register reads",
        {
            0x03C: 0x5288001A,  # register block base 0xd04000
            0x040: 0x72A01A1A,
            0x054: 0x52880001,  # version register read
            0x058: 0x72A01A01,
            0x070: 0x91004341,  # block +0x10
            0x08C: 0x91005341,  # block +0x14
            0x0A8: 0x91006341,  # block +0x18
            0x0C4: 0x91007341,  # block +0x1c
        },
    )
    require_instruction_words_at(
        code,
        "G17 chip variant decode",
        {
            0x0EC: 0x53187EE8,  # version >> 24
            0x0F0: 0x71002D1F,  # must be 0xb
            0x0F8: 0x53105EE8,  # (version >> 16) & 0xff
            0x0FC: 0x7100111F,
            0x104: 0x71000D1F,
            0x10C: 0x7100091F,
            0x114: 0x52800148,
            0x118: 0xB9007668,
            0x11C: 0x52800408,  # selector 2 -> variant 0x20
            0x120: 0xB9002268,
            0x564: 0x52800288,
            0x56C: 0x52800428,  # selector 3 -> variant 0x21
            0x578: 0x52800448,  # selector 4 -> variant 0x22
            0x57C: 0xB9002268,
        },
    )

    base = 0xD04000
    return {
        "register_block": base,
        "registers": {
            "version": base,
            "count": base + 0x08,
            "cluster_config": base + 0x10,
            "identity_14": base + 0x14,
            "identity_18": base + 0x18,
            "identity_1c": base + 0x1C,
        },
        "version_family_byte": {"shift": 24, "value": 0xB},
        "variant_selector": {"shift": 16, "mask": 0xFF},
        "variants": {2: 0x20, 3: 0x21, 4: 0x22},
        "companion_values": {2: 0x0A, 3: 0x14, 4: 0x28},
        "chip_info_variant_offset": 0x20,
        "chip_info_companion_offset": 0x74,
        # The relay puts the variant where the power model reads it.
        "accelerator_variant_member": 0x480 + 0x20,
        "variant_consumers": [
            G17_POPULATE_MAX_PERF_POWER_CS,
            G17_CALCULATE_VDD_GPU_LEAKAGE,
        ],
    }


def recover_g17_final_late_controls(image: bytes) -> dict[str, object]:
    """Settle the last two late-control fields.

    +0x26c0 takes a literal one. +0x269c passes firmware member 0x1ab8 through
    the address converter, and both ends of that are known: the converter is
    the identity, and the member is only ever written by the constructor
    clearing it, so the field is zero.
    """

    symbols = macho_symbols(image)
    required = (ARM_INIT_FIRMWARE_DATA, CONVERT_GPU_VA_TO_FW_VA, G17_ARM_FIRMWARE_ASC_META_ALLOC)
    missing = [name for name in required if name not in symbols]
    if missing:
        raise ValueError(f"Mach-O is missing final late-control symbols: {missing}")

    _address, producer = symbol_code(image, ARM_INIT_FIRMWARE_DATA)
    require_instruction_words_at(
        producer,
        "G17 final late-control fields",
        {
            0x0380: 0xF94D5E61,  # firmware +0x1ab8
            0x0394: 0xD2805B11,  # the address-conversion vtable slot
            0x03A4: 0x52800002,
            0x03B4: 0x5284D389,  # config +0x269c
            0x03BC: 0xF9000100,
            0x10F8: 0x52800034,  # w20 = 1
            0x126C: 0xB926C114,  # -> config +0x26c0
        },
    )
    # Nothing may reassign w20 between the literal and the store.
    for offset, word in words(producer):
        if not 0x10F8 < offset < 0x126C:
            continue
        for decoder in (decode_ldr_x, decode_ldr_w, decode_add_immediate, decode_movz_w):
            decoded = decoder(word)
            if decoded is not None and decoded[0] == 20:
                raise ValueError(f"w20 is reassigned at {offset:#x} before the store")

    # The converter is the identity, so the field is whatever the member holds.
    converter = recover_vtable_target(
        image, G17_FIRMWARE_VTABLE, FIRMWARE_ADDRESS_CONVERSION_VTABLE_SLOT
    )
    if converter != symbols[CONVERT_GPU_VA_TO_FW_VA]:
        raise ValueError(f"unexpected firmware address converter {converter:#x}")
    _address, convert = symbol_code(image, CONVERT_GPU_VA_TO_FW_VA)
    if convert != struct.pack("<3I", 0xD503245F, 0xAA0103E0, 0xD65F03C0):
        raise ValueError("firmware address converter is no longer the identity")

    # And the member is only ever cleared.
    _address, alloc = symbol_code(image, G17_ARM_FIRMWARE_ASC_META_ALLOC)
    require_instruction_words_at(
        alloc, "G17 converted member cleared", {0x940: 0xF90D5E7F}
    )
    writers = []
    for item in load_commands(image):
        if item.command != LC_SEGMENT_64:
            continue
        segment = parse_segment(image, item)
        if segment.name != "__TEXT_EXEC":
            continue
        code = image[segment.file_offset : segment.file_offset + segment.file_size]
        writers.extend(stores_covering_any(code, {0x1AB8}).get(0x1AB8, []))
    if len(writers) != 1:
        raise ValueError(
            f"firmware +0x1ab8 has {len(writers)} writers; it may no longer be zero"
        )

    return {
        "converted_field": {
            "config": 0x269C,
            "firmware_member": 0x1AB8,
            "converter": CONVERT_GPU_VA_TO_FW_VA,
            "identity": True,
            "value": 0,
        },
        "literal_field": {"config": 0x26C0, "value": 1},
    }


def recover_g17_remaining_late_controls(image: bytes) -> dict[str, object]:
    """Settle the late-control fields that are neither zero nor register-fed.

    Three take fixed non-zero content: a 48-byte run of ones, and a pair of
    bytes copied from accelerator members configureDevice deliberately clears.
    A fourth is guarded by a feature bit that is clear, so its store never runs.
    """

    symbols = macho_symbols(image)
    required = (ARM_INIT_FIRMWARE_DATA, BASE_CONFIGURE_DEVICE)
    missing = [name for name in required if name not in symbols]
    if missing:
        raise ValueError(f"Mach-O is missing remaining late-control symbols: {missing}")

    _address, producer = symbol_code(image, ARM_INIT_FIRMWARE_DATA)
    require_instruction_words_at(
        producer,
        "G17 late-control ones run",
        {
            0xF38: 0x6F07E7E0,  # every lane set
            0xF3C: 0xAD000120,  # 32 bytes from config +0x25bc
            0xF40: 0x3D800920,  # 16 more
        },
    )
    require_instruction_words_at(
        producer,
        "G17 late-control copied bytes",
        {
            0xF54: 0x395BC16A,  # accelerator +0x6f0
            0xF58: 0x3904F12A,  # -> config +0x26f8
            0xF5C: 0x395BE16A,  # accelerator +0x6f8
            0xF60: 0x3904F52A,  # -> config +0x26f9
        },
    )
    require_instruction_words_at(
        producer,
        "G17 late-control feature guard",
        {
            0xF64: 0xF9436969,  # the fixed feature mask
            0xF68: 0xD366FD2A,
            0xF74: 0x3600004A,  # bit 0x26 clear skips both stores
            0xF7C: 0x5284B589,  # config +0x25ac
            0xF84: 0xB20003E9,  # would take a pair of ones
            0xF88: 0xF9000109,
        },
    )
    if (G17_FEATURE_MASK >> 0x26) & 1:
        raise ValueError("late-control guard bit is now set; +0x25ac would be written")

    # The copied bytes read members configureDevice clears; the only other
    # writers are fence and submission paths that run long after this.
    _address, configure = symbol_code(image, BASE_CONFIGURE_DEVICE)
    require_instruction_words_at(
        configure,
        "G17 cleared copy sources",
        {
            0x028: 0xAA0003F3,  # x19 is the accelerator
            0x5F8: 0x790DE27F,  # clears +0x6f0
            0x5FC: 0x391BE27F,  # clears +0x6f8
        },
    )

    return {
        "ones_run": {"offset": 0x25BC, "bytes": 0x30, "value": 0xFF},
        "copied_bytes": {0x26F8: 0x6F0, 0x26F9: 0x6F8},
        "guarded": {
            "offset": 0x25AC,
            "feature_bit": 0x26,
            "would_be": 0x100000001,
            "written": bool((G17_FEATURE_MASK >> 0x26) & 1),
        },
    }


def recover_g17_cleared_accelerator_inputs(image: bytes) -> dict[str, object]:
    """Show the late-control fields whose accelerator sources are never set.

    Five of the outstanding fields read accelerator members that nothing in the
    extracted binaries ever writes. The accelerator is allocated through the
    same zeroing operator new the ASC uses, so those members keep zero and the
    fields they feed do too.
    """

    symbols = macho_symbols(image)
    required = (G17_ACCELERATOR_ALLOC, IDLE_POWER_OFF_TIMER)
    missing = [name for name in required if name not in symbols]
    if missing:
        raise ValueError(f"Mach-O is missing cleared-input symbols: {missing}")

    _address, alloc = symbol_code(image, G17_ACCELERATOR_ALLOC)
    require_instruction_words_at(
        alloc,
        "G17 accelerator allocation",
        {
            0x018: 0x52997A01,  # registered type size 0x1cbd0
            0x01C: 0x72A00021,
            0x020: 0x94C7EE3E,  # the zeroing typed operator new
        },
    )
    accelerator_bytes = 0x1CBD0

    sources = {
        0x2544: 0x72C,
        0x25F4: 0x730,
        0x25F8: 0xF91C,
        0x26A4: 0xF914,
        0x26BC: 0xF958,
    }
    for offset in sources.values():
        if offset >= accelerator_bytes:
            raise ValueError(f"accelerator member {offset:#x} is outside the object")

    # A sweep over every base register finds any store whose bytes cover the
    # member, so a wider or paired store cannot hide one.
    # Scan the executable segment once. Doing this per symbol would re-parse
    # and re-sort the symbol table on every call, which is quadratic.
    members = set(sources.values()) | {0xF91D}
    covering: dict[int, list[tuple[int, int]]] = {}
    for item in load_commands(image):
        if item.command != LC_SEGMENT_64:
            continue
        segment = parse_segment(image, item)
        if segment.name != "__TEXT_EXEC":
            continue
        code = image[segment.file_offset : segment.file_offset + segment.file_size]
        for member, sites in stores_covering_any(code, members).items():
            covering.setdefault(member, []).extend(sites)

    # The only hits are through bases that are not the accelerator. The one in
    # an AGXAccelerator method is a pointer offset a whole 0x13000 further on,
    # so its 0x728 store lands at +0x13728.
    _address, timer = symbol_code(image, IDLE_POWER_OFF_TIMER)
    require_instruction_words_at(
        timer,
        "G17 idle timer derived base",
        {
            0x02C: 0x91404E74,  # x20 = accelerator + 0x13000
            0x094: 0xF903969F,  # so this store targets +0x13728
        },
    )
    for member in (0xF914, 0xF91C, 0xF91D, 0xF958):
        if covering.get(member):
            raise ValueError(
                f"accelerator member {member:#x} is now written at "
                f"{covering[member][0]}"
            )

    return {
        "accelerator_bytes": accelerator_bytes,
        "zeroed_allocation": True,
        "cleared_members": sorted(set(sources.values())),
        "fields": {config: member for config, member in sorted(sources.items())},
        "guarded_field": {
            "config": 0x2544,
            "note": "only written when its source is nonzero, so it stays clear",
        },
    }


def recover_g17_unit_mask_field(image: bytes) -> dict[str, object]:
    """Recover config +0x2554, a bit mask sized by a chip-info nibble product.

    readChipInfo splits identity register 0xd04018 into six nibbles and stores
    three pairwise products. The third of those reaches accelerator +0x4d0, and
    the late-control producer turns it into a mask of that many bits, saturating
    to all ones once the count passes 63.
    """

    symbols = macho_symbols(image)
    required = (PI300_READ_CHIP_INFO, ARM_INIT_FIRMWARE_DATA)
    missing = [name for name in required if name not in symbols]
    if missing:
        raise ValueError(f"Mach-O is missing unit-mask symbols: {missing}")

    address, reader = symbol_code(image, PI300_READ_CHIP_INFO)
    require_instruction_words_at(
        reader,
        "G17 chip-info nibble products",
        {
            0x1E8: 0x53104F08,  # (identity >> 16) & 0xf
            0x1EC: 0x12000F09,  # identity & 0xf
            0x1F0: 0x0E040F00,  # both lanes get the identity word
            0x1FC: 0x2EA14401,  # high nibble pair
            0x208: 0x2EA24400,  # low nibble pair
            0x214: 0x0E221C21,
            0x218: 0x0E221C00,
            0x224: 0x1B097D08,  # first product
            0x228: 0x0EA09C20,  # remaining two products
            0x238: 0xB9004A68,  # -> chip info +0x48
            0x23C: 0x3C84C260,  # -> chip info +0x4c and +0x50
        },
    )

    shifts: list[tuple[int, int]] = [(0, 16)]
    for load_offset in (0x1F8, 0x204):
        adrp = decode_adrp(
            address + load_offset - 4,
            struct.unpack_from("<I", reader, load_offset - 4)[0],
        )
        load = decode_ldr_d(struct.unpack_from("<I", reader, load_offset)[0])
        if adrp is None or load is None:
            raise ValueError("nibble shift vector is no longer a literal load")
        _register, page = adrp
        _destination, _base, immediate = load
        offset = virtual_to_file(image, page + immediate)
        lanes = struct.unpack_from("<2i", image, offset)
        if any(lane > 0 for lane in lanes):
            raise ValueError(f"nibble shift vector {lanes} is not a right shift")
        shifts.append(lanes)

    # shifts[1] is the high nibble of each pair, shifts[2] the low one.
    high, low = shifts[1], shifts[2]
    products = [
        {"chip_info": 0x48, "shifts": [0, 16]},
        {"chip_info": 0x4C, "shifts": [-low[0], -high[0]]},
        {"chip_info": 0x50, "shifts": [-low[1], -high[1]]},
    ]

    _producer_address, producer = symbol_code(image, ARM_INIT_FIRMWARE_DATA)
    require_instruction_words_at(
        producer,
        "G17 unit mask",
        {
            0x568: 0xB944D12A,  # accelerator +0x4d0
            0x56C: 0x9280000B,
            0x570: 0x9ACA216B,  # -1 << count
            0x574: 0x7100FD5F,  # saturate past 63
            0x578: 0x1280000A,
            0x57C: 0x5A8B814A,
            0x580: 0xB925550A,  # -> config +0x2554
        },
    )

    return {
        "config_offset": 0x2554,
        "identity_register": 0xD04018,
        "nibble_products": products,
        "count_chip_info": 0x50,
        "count_accelerator_member": 0x480 + 0x50,
        "saturate_above": 63,
        "formula": "count >= 64 ? 0xffffffff : low32(~(~0 << count))",
    }


def recover_g17_core_count_gate(image: bytes) -> dict[str, object]:
    """Determine which source config +0x2570 takes on G17.

    The field has two producers picked by accelerator byte +0x506. That byte is
    chip-info +0x86, which readChipInfo writes from w22 -- and w22 is
    unconditionally reassigned to 1 before that store, so the bit is always set
    and the popcount producer always wins. The scaled core count at
    accelerator +0x4b0 is the path *not* taken.

    The popcount then reads the second mask pair, because the first is the
    cleared head of the chip-info record and the select falls through to a
    0x10-byte offset.
    """

    symbols = macho_symbols(image)
    required = (PI300_READ_CHIP_INFO, ARM_INIT_FIRMWARE_DATA)
    missing = [name for name in required if name not in symbols]
    if missing:
        raise ValueError(f"Mach-O is missing core-count gate symbols: {missing}")

    _address, reader = symbol_code(image, PI300_READ_CHIP_INFO)
    require_instruction_words_at(
        reader,
        "G17 chip-info gate byte",
        {
            0x258: 0x52800036,  # w22 = 1, well before the store
            0x348: 0x39021A76,  # -> chip info +0x86
            0x36C: 0xA9012269,  # the mask pair at chip info +0x10/+0x18
        },
    )
    # Nothing may jump over the reassignment, or the byte could still hold the
    # identity register read that reaches w22 earlier.
    for offset, word in words(reader):
        if not 0x1E8 <= offset < 0x258:
            continue
        for decoder in (decode_b_target, decode_bl_target):
            target = decoder(offset, word)
            if target is not None and target > 0x258:
                raise ValueError(
                    f"branch at {offset:#x} can skip the chip-info gate assignment"
                )

    require_instruction_words_at(
        reader,
        "G17 core-mask register read",
        {
            0x260: 0x5282A017,  # register offset 0xe01500
            0x264: 0x72A01C17,
            0x354: 0xCB180008,  # mapping base minus the page-aligned offset
            0x358: 0x8B170108,  # plus the register offset
            0x35C: 0xB9400109,  # word 0
            0x360: 0xB940050A,  # word 1
            0x364: 0xAA0A8129,  # combined into a 64-bit mask
            0x368: 0xB9400908,  # word 2
        },
    )

    _address, producer = symbol_code(image, ARM_INIT_FIRMWARE_DATA)
    require_instruction_words_at(
        producer,
        "G17 core-count producer select",
        {
            0x6B4: 0x3954190A,  # accelerator +0x506
            0x6B8: 0x3600024A,  # bit clear would take the scaled fallback
            0x6CC: 0x5280020C,
            0x6D0: 0xF100017F,  # first mask pair zero?
            0x6D4: 0x9A8C13EB,  # then step on by 0x10
            0x6D8: 0x8B0B014A,
            0x6DC: 0x6D400141,  # popcount source
        },
    )

    return {
        "config_offset": 0x2570,
        "gate": {
            "accelerator_byte": 0x506,
            "chip_info_byte": 0x86,
            "value": 1,
            "always_set": True,
        },
        "selected": "popcount",
        "unused_fallback": {
            "accelerator_member": 0x4B0,
            "chip_info": 0x30,
            "reason": "gate bit is always set, so this producer never runs",
        },
        "popcount_source": {
            "accelerator_member": 0x490,
            "chip_info": 0x10,
            "words": 3,
            "note": "first pair is the cleared record head, so the select steps on by 0x10",
        },
        "mask_registers": {
            # readChipInfo maps this separately from the ordinary register
            # accessor, but the base is getGPUPhysicalAddress(), which probe
            # sets to the physical address of device-memory range 0 -- the same
            # SGX aperture sgx_read32 addresses.
            "base": "getGPUPhysicalAddress",
            "base_source": "IOMemoryDescriptor::getPhysicalAddress of device memory 0",
            "offset": 0xE01500,
            "words": [0xE01500, 0xE01504, 0xE01508],
            "layout": "words 0 and 1 form a 64-bit mask, word 2 a 32-bit mask",
        },
        "formula": "popcount(mask0) + popcount(mask1)",
        "resolved": True,
    }


def recover_g17_chip_info_decode(image: bytes) -> dict[str, object]:
    """Recover how the chip-info power dimensions come out of cluster config.

    readChipInfo derives internal dimensions from the cluster-configuration
    register with plain integer arithmetic. The power-model producers consume
    the +0x64/+0x6c fields through accelerator +0x4e4/+0x4ec. They are not the
    public num_cores/num_mgpus values in GPUConfigurationVariable.
    """

    symbols = macho_symbols(image)
    if PI300_READ_CHIP_INFO not in symbols:
        raise ValueError(f"Mach-O is missing {PI300_READ_CHIP_INFO}")

    _address, code = symbol_code(image, PI300_READ_CHIP_INFO)
    require_instruction_words_at(
        code,
        "G17 chip-info topology decode",
        {
            0x19C: 0x53104EA8,  # (cluster_config >> 16) & 0xf
            0x1A0: 0xB9006E68,  # -> chip info +0x6c
            0x1A4: 0x53083EA9,  # (cluster_config >> 8) & 0xff
            0x1A8: 0x1B087D28,  # multiplied together
            0x1AC: 0xB9006668,  # -> chip info +0x64, power column count
            0x1B0: 0x12001EA9,  # cluster_config & 0xff
            0x1B4: 0xB9007A69,  # -> chip info +0x78
            0x1B8: 0x1B097D09,  # core count * that
            0x1CC: 0x29062A69,  # -> chip info +0x30
        },
    )

    return {
        "source_register": 0xD04010,
        "fields": {
            "power_group_count": {
                "chip_info": 0x6C,
                "accelerator_member": 0x4EC,
                "shift": 16,
                "mask": 0xF,
            },
            "columns_per_group": {
                "shift": 8,
                "mask": 0xFF,
            },
            "power_column_count": {
                "chip_info": 0x64,
                "accelerator_member": 0x4E4,
                "formula": "columns_per_group * power_group_count",
            },
            "units_per_column": {
                "chip_info": 0x78,
                "shift": 0,
                "mask": 0xFF,
            },
            "scaled_column_count": {
                "chip_info": 0x30,
                "formula": "power_column_count * units_per_column",
                # This is the value the late-control +0x2570 fallback reads,
                # relayed to accelerator +0x4b0.
                "accelerator_member": 0x480 + 0x30,
            },
        },
    }


def recover_g17_core_mask_relay(image: bytes) -> dict[str, object]:
    """Show the accelerator's core-mask pair is the cleared chip-info head.

    getProbeScore builds the chip-info record on its own stack at sp+0x10 and
    copies it to accelerator +0x480 with a uniform +0x480 delta, so accelerator
    +0x480 and +0x488 are chip-info +0x00 and +0x08.
    """

    symbols = macho_symbols(image)
    required = (FAMILY_GET_PROBE_SCORE, PI300_READ_CHIP_INFO, G17_READ_CHIP_INFO)
    missing = [name for name in required if name not in symbols]
    if missing:
        raise ValueError(f"Mach-O is missing chip-info relay symbols: {missing}")

    _address, probe_code = symbol_code(image, FAMILY_GET_PROBE_SCORE)
    require_instruction_words_at(
        probe_code,
        "G17 chip-info core-mask relay",
        {
            0x068: 0x910043F5,  # add x21, sp, #0x10 -- the record itself
            0xC14: 0xAD4087E0,  # ldp q0, q1, [sp, #0x10] -- its first 0x20 bytes
            0xC18: 0x3D812260,  # -> accelerator +0x480
            0xC1C: 0x3D812661,  # -> accelerator +0x490
        },
    )

    writers = []
    for label, name in (("PI_300", PI300_READ_CHIP_INFO), ("G17", G17_READ_CHIP_INFO)):
        _reader_address, reader_code = symbol_code(image, name)
        for target in (0x00, 0x08):
            if hits := stores_covering(reader_code, 19, target):
                writers.append({"reader": label, "byte": target, "site": hits[0]})

    return {
        "record_delta": 0x480,
        "accelerator_members": [0x480, 0x488],
        "chip_info_bytes": [0x00, 0x08],
        "written": bool(writers),
        "writers": writers,
    }


def recover_g17_late_controls(image: bytes) -> dict[str, object]:
    """Recover the statically determined part of the late-control block.

    AGXArmFirmware::initFirmwareData writes into hardware-config offsets
    0x2540..0x270f.  The write set is derived here rather than listed, because
    a hand-built list missed every store that materializes its offset into a
    register first.  Fields stored straight from a zero register are fixed, as
    are two ones, a 64-bit literal, and four tests of the fixed feature mask
    that all come out clear.
    """

    symbols = macho_symbols(image)
    if ARM_INIT_FIRMWARE_DATA not in symbols:
        raise ValueError(f"Mach-O is missing {ARM_INIT_FIRMWARE_DATA}")

    _address, code = symbol_code(image, ARM_INIT_FIRMWARE_DATA)
    stores = config_pointer_stores(code, 0x2540, 0x2710)
    if not stores:
        raise ValueError("no late-control writes reach the hardware config")
    offsets = sorted({store["offset"] for store in stores})

    if G17_FEATURE_MASK & (1 << 17) == 0:
        raise ValueError("G17 feature mask lost the power-estimation bit")
    feature_fields = {0x259C: 0x25, 0x25A4: 0x26, 0x25B4: 0x07, 0x26C4: 0x35}
    feature_values = {
        offset: (G17_FEATURE_MASK >> bit) & 1 for offset, bit in feature_fields.items()
    }
    if any(feature_values.values()):
        raise ValueError(
            "a G17 late-control feature bit is now set; its field is no longer zero"
        )
    # +0x2548 is also a pure function of the mask.
    low = G17_FEATURE_MASK & 0xFFFFFFFF
    feature_values[0x2548] = ((low >> 4) & 4) | ((low >> 6) & 2)

    # Two more are fixed but store through a vector register, so the scan
    # cannot see the value; pin the producing instructions instead.
    require_instruction_words_at(
        code,
        "G17 late-control vector constants",
        {
            0x00A4: 0x6F00E400,  # movi v0.2d, #0
            0x00A8: 0xFD130120,  # -> config +0x2600
            0x1284: 0xFD137900,  # 64-bit literal -> config +0x26f0
        },
    )
    literal = decode_ldr_d(struct.unpack_from("<I", code, 0x1280)[0])
    if literal is None:
        raise ValueError("late-control literal is no longer a direct load")

    # +0x2560 copies the accelerator's core-mask pair, but only when either
    # half is nonzero. getProbeScore stages the chip-info record at sp+0x10 and
    # relays it to accelerator +0x480 one-for-one, so those halves are chip-info
    # +0x00 and +0x08 -- and neither selected reader writes them, so the guard
    # never passes and the field keeps the zero the config was cleared to.
    core_mask = recover_g17_core_mask_relay(image)
    if core_mask["written"]:
        raise ValueError("G17 chip-info core-mask pair is no longer left clear")

    fixed = {store["offset"]: 0 for store in stores if store["zero_source"]}
    fixed.update({0x2578: 1, 0x25A0: 1, 0x2600: 0, 0x26F0: 1, 0x2560: 0})
    cleared = recover_g17_cleared_accelerator_inputs(image)
    fixed.update({offset: 0 for offset in cleared["fields"]})
    remaining = recover_g17_remaining_late_controls(image)
    fixed.update({0x25AC: 0, 0x26F8: 0, 0x26F9: 0})
    fixed[remaining["ones_run"]["offset"]] = remaining["ones_run"]["value"]
    fixed[0x25DC] = remaining["ones_run"]["value"]
    final = recover_g17_final_late_controls(image)
    fixed[final["converted_field"]["config"]] = final["converted_field"]["value"]
    fixed[final["literal_field"]["config"]] = final["literal_field"]["value"]
    # +0x2570 is not a constant, but its producer and inputs are settled, so it
    # is emitted rather than outstanding. Track it separately from the fixed
    # values so the accounting still distinguishes the two.
    derived_offsets = [0x2554, 0x2570]
    fixed.update(feature_values)
    undetermined = [
        offset for offset in offsets if offset not in fixed and offset not in derived_offsets
    ]

    return {
        "region": {"offset": 0x2540, "bytes": 0x1D0},
        "producer": ARM_INIT_FIRMWARE_DATA,
        "written_offsets": len(offsets),
        "feature_mask": G17_FEATURE_MASK,
        "feature_bit_fields": feature_fields,
        "fixed": dict(sorted(fixed.items())),
        "wide_fixed": {0x2560: 16, 0x2600: 8, 0x26F0: 8},
        "core_mask_relay": core_mask,
        "cleared_accelerator_inputs": cleared,
        "remaining_late_controls": remaining,
        "final_late_controls": final,
        "derived": derived_offsets,
        "runtime_dependent": undetermined,
        "complete": not undetermined,
    }


def recover_g17_command_stream_format(image: bytes) -> dict[str, object]:
    """Recover the userspace command-stream record format.

    AGXHardwareKernelCommand::parseAndValidate reads the stream through an
    AGXSharedStreamParser cursor: it copies a fixed 0xc0-byte header out of the
    stream, then takes the following payload's length from a field inside that
    header.  This is the format Mesa has to emit, so it is the one piece of the
    work-command path that is userspace-visible.
    """

    symbols = macho_symbols(image)
    if PARSE_HARDWARE_KERNEL_COMMAND not in symbols:
        raise ValueError(f"Mach-O is missing {PARSE_HARDWARE_KERNEL_COMMAND}")

    _address, code = symbol_code(image, PARSE_HARDWARE_KERNEL_COMMAND)
    require_instruction_words_at(
        code,
        "G17 command-stream record parse",
        {
            0x004: 0xF9400829,  # cursor at parser +0x10
            0x008: 0xF9400028,  # start at parser +0x00
            0x00C: 0xEB08013F,  # cursor must not precede the start
            0x014: 0xB1030128,  # fixed header is 0xc0 bytes
            0x01C: 0xF940042A,  # end at parser +0x08
            0x058: 0xF9000828,  # cursor advanced past the header
            0x070: 0x52802009,  # terminator marker 0x100
            0x074: 0xB9000C09,  # stored at command +0xc
            0x080: 0xB940AC09,  # payload length at command +0xac
            0x084: 0xAB090109,  # payload follows the header
            0x098: 0xF9000829,  # cursor advanced past the payload
            0x0A4: 0x3D803400,  # payload bounds at command +0xd0
            0x0A8: 0xF9007008,  # payload start at command +0xe0
            0x0B4: 0xB940A009,  # bytes after the primary extension header
            0x0DC: 0x91004129,  # its count header is 0x10 bytes
            0x11C: 0x3DC00100,  # copy the extension count header
            0x120: 0x3C8E8000,  # to command +0xe8
            0x124: 0xB940E80A,  # first count at extension +0x00
            0x128: 0xAB0A056A,  # first array contains 2-byte elements
            0x158: 0xB940EC08,  # second count at extension +0x04
            0x15C: 0x8B080508,  # multiply it by three
            0x160: 0xAB080D48,  # then by eight: 24-byte elements
            0x170: 0xF900800A,  # first array pointer at command +0x100
            0x17C: 0xB9409809,  # record +0x88 gates the u16 aux extension
            0x194: 0xB9409C0B,  # record +0x8c is its byte length
            0x23C: 0x3DC00100,  # copy its four-count header
            0x240: 0x3D804800,  # to command +0x120
            0x244: 0xB941200B,  # first count at extension +0x00
            0x264: 0xF900980A,  # first u16-array pointer at command +0x130
            0x278: 0xB941240B,  # second count at extension +0x04
            0x298: 0xF9009C0B,  # second pointer at command +0x138
            0x2AC: 0xB941280D,  # third count at extension +0x08
            0x2CC: 0xF900A00D,  # third pointer at command +0x140
            0x2D8: 0xB9412C08,  # fourth count at extension +0x0c
            0x2F4: 0xF900A408,  # fourth pointer at command +0x148
            0x1C4: 0xB940A409,  # record +0x94 gates the u64 aux extension
            0x1E0: 0xB940A80C,  # record +0x98 is its byte length
            0x370: 0x3DC00160,  # copy its four-count header
            0x374: 0x3D805400,  # to command +0x150
            0x378: 0xB941580A,  # third count at extension +0x08
            0x37C: 0xB9415C0C,  # fourth count at extension +0x0c
            0x380: 0xB941540D,  # second count at extension +0x04
            0x384: 0xB941500E,  # first count at extension +0x00
            0x388: 0x0B0E01AD,  # first group count is count0 + count1
            0x3A8: 0xF900B008,  # first u64-group pointer at command +0x160
            0x3B4: 0x0B0A0188,  # second group count is count2 + count3
            0x3D0: 0xF900B408,  # second pointer at command +0x168
            0x3D4: 0x52800028,  # successful parse sets byte one
            0x3D8: 0x39002008,  # at command +0x08
            0x3EC: 0x52802049,  # auxiliary parse error marker 0x102
        },
    )

    header_bytes = 0xC0
    command_header_offset = 0x10
    payload_length_member = 0xAC
    payload_length_offset = payload_length_member - command_header_offset
    if not 0 <= payload_length_offset < header_bytes:
        raise ValueError("payload length field falls outside the record header")

    return {
        "parser": {"start": 0x00, "end": 0x08, "cursor": 0x10},
        "header_bytes": header_bytes,
        "command_header_offset": command_header_offset,
        "payload_length_offset": payload_length_offset,
        "payload_bounds_member": 0xD0,
        "payload_start_member": 0xE0,
        "primary_extension": {
            "stream_length_offset": 0x90,
            "header_bytes": 0x10,
            "count_offsets": [0x00, 0x04],
            "element_bytes": [0x02, 0x18],
            "header_member": 0xE8,
            "first_array_member": 0xF8,
            "second_array_member": 0x100,
        },
        "auxiliary_stream_extensions": {
            "u16_arrays": {
                "flag_offset": 0x88,
                "stream_length_offset": 0x8C,
                "header_bytes": 0x10,
                "count_offsets": [0x00, 0x04, 0x08, 0x0C],
                "element_bytes": [0x02, 0x02, 0x02, 0x02],
                "header_member": 0x120,
                "array_members": [0x130, 0x138, 0x140, 0x148],
            },
            "u64_groups": {
                "flag_offset": 0x94,
                "stream_length_offset": 0x98,
                "header_bytes": 0x10,
                "count_offsets": [0x00, 0x04, 0x08, 0x0C],
                "element_bytes": 0x08,
                "group_count_indices": [[0, 1], [2, 3]],
                "header_member": 0x150,
                "group_array_members": [0x160, 0x168],
            },
        },
        "success": {"member": 0x08, "value": 1},
        "error_markers": {
            "member": 0x0C,
            "terminator": 0x100,
            "auxiliary_stream": 0x102,
        },
        "terminator_marker": 0x100,
        "terminator_member": 0x0C,
        "producer": PARSE_HARDWARE_KERNEL_COMMAND,
    }


def recover_g17_render_payload_format(image: bytes) -> dict[str, object]:
    """Recover the fixed render payload and its normalized command fields.

    The base hardware-command parser exposes a payload cursor. The render
    subtype consumes exactly 0x9d0 bytes from it, retains the source pointer,
    copies the fields used by processRender into a compact command object and
    enforces two cross-field bit invariants. Record both the source ranges and
    normalized destinations so a future encoder need not guess either ABI.
    """

    symbols = macho_symbols(image)
    if PARSE_RENDER_HARDWARE_KERNEL_COMMAND not in symbols:
        raise ValueError(f"Mach-O is missing {PARSE_RENDER_HARDWARE_KERNEL_COMMAND}")

    _address, code = symbol_code(image, PARSE_RENDER_HARDWARE_KERNEL_COMMAND)
    require_instruction_words_at(
        code,
        "G17 render command payload parse",
        {
            0x004: 0xF9400828,  # cursor at parser +0x10
            0x008: 0xF9400029,  # start at parser +0x00
            0x014: 0xF9000C1F,  # clear retained payload on framing error
            0x020: 0xB9000C09,  # error marker at command +0x0c
            0x02C: 0xB1274109,  # consume exactly 0x9d0 bytes
            0x040: 0xF9000829,  # publish the advanced cursor
            0x044: 0xF9000C08,  # retain payload pointer at command +0x18
            0x04C: 0x91032109,  # first source range begins at payload +0xc8
            0x064: 0xAD010400,  # -> command +0x20
            0x070: 0xF9409D09,  # final qword at payload +0x138
            0x074: 0xF9004809,  # -> command +0x90
            0x07C: 0x3D801800,  # completes command +0x20..+0x97
            0x080: 0x91136109,  # source range at payload +0x4d8
            0x0B4: 0x3C898000,  # -> command +0x98
            0x0B8: 0x3DC05100,  # source range at payload +0x140
            0x0BC: 0x3D804400,  # -> command +0x110
            0x0C8: 0xF940C109,  # final qword at payload +0x180
            0x0CC: 0xF900A809,  # -> command +0x150
            0x0DC: 0x3DC15500,  # source range at payload +0x550
            0x0E0: 0x3D800120,  # -> command +0x158
            0x0F0: 0xF942C90A,  # final qword at payload +0x590
            0x0F4: 0xF900CC0A,  # -> command +0x198
            0x100: 0x91093109,  # payload +0x24c
            0x10C: 0xB901A80A,  # payload +0x254 -> command +0x1a8
            0x118: 0xF9432D0A,  # payload +0x658
            0x124: 0xF900012A,  # -> unaligned command +0x1ac
            0x12C: 0x12000169,  # payload +0x240 is reduced to bit zero
            0x134: 0x3962C109,  # payload +0x8b0
            0x138: 0x12000129,  # is reduced to bit zero
            0x144: 0xB901BC09,  # payload +0x234 -> command +0x1bc
            0x184: 0xAD000520,  # payload +0x25f..+0x27e -> command +0x1db
            0x188: 0xF9433509,  # payload +0x668
            0x18C: 0xF9010009,  # -> command +0x200
            0x190: 0x39608509,  # payload +0x821
            0x194: 0x39082009,  # -> command +0x208
            0x1A8: 0x3D808400,  # payload +0x840..+0x86f -> command +0x210
            0x1C0: 0xAD120400,  # payload +0x870..+0x8af -> command +0x240
            0x1C8: 0x12000149,  # payload +0x23c -> command +0x280 bit zero
            0x1D4: 0x1200012C,  # payload +0x646 -> command +0x281 bit zero
            0x1E0: 0x1200018C,  # payload +0x248 -> command +0x282 bit zero
            0x1EC: 0x1200018C,  # payload +0x650 -> command +0x283 bit zero
            0x1F4: 0x395F8108,  # validation compares payload +0x7e0
            0x1F8: 0x4A0B0108,  # with payload +0x240
            0x200: 0x3600004A,  # payload +0x23c gates the second invariant
            0x204: 0x360000A9,  # which requires payload +0x646
            0x208: 0x52800028,  # successful parse sets byte one
            0x20C: 0x39002008,  # at command +0x08
            0x21C: 0x52800149,  # invariant error marker 0x0a
        },
    )

    copy_ranges = [
        {"payload_offset": 0x0C8, "command_member": 0x020, "bytes": 0x78},
        {"payload_offset": 0x4D8, "command_member": 0x098, "bytes": 0x78},
        {"payload_offset": 0x140, "command_member": 0x110, "bytes": 0x48},
        {"payload_offset": 0x550, "command_member": 0x158, "bytes": 0x48},
        {"payload_offset": 0x24C, "command_member": 0x1A0, "bytes": 0x0C},
        {"payload_offset": 0x658, "command_member": 0x1AC, "bytes": 0x0C},
        {"payload_offset": 0x234, "command_member": 0x1BC, "bytes": 0x04},
        {"payload_offset": 0x25F, "command_member": 0x1DB, "bytes": 0x20},
        {"payload_offset": 0x668, "command_member": 0x200, "bytes": 0x08},
        {"payload_offset": 0x821, "command_member": 0x208, "bytes": 0x01},
        {"payload_offset": 0x840, "command_member": 0x210, "bytes": 0x70},
    ]
    bit_fields = [
        {"payload_offset": 0x240, "command_member": 0x1B8},
        {"payload_offset": 0x8B0, "command_member": 0x1B9},
        {"payload_offset": 0x247, "command_member": 0x1C0},
        {"payload_offset": 0x25C, "command_member": 0x1D8},
        {"payload_offset": 0x25D, "command_member": 0x1D9},
        {"payload_offset": 0x25E, "command_member": 0x1DA},
        {"payload_offset": 0x23C, "command_member": 0x280},
        {"payload_offset": 0x646, "command_member": 0x281},
        {"payload_offset": 0x248, "command_member": 0x282},
        {"payload_offset": 0x650, "command_member": 0x283},
    ]
    payload_bytes = 0x9D0
    if any(
        field["payload_offset"] + field.get("bytes", 1) > payload_bytes
        for field in copy_ranges + bit_fields
    ):
        raise ValueError("render command field falls outside its fixed payload")

    return {
        "parser": {"start": 0x00, "end": 0x08, "cursor": 0x10},
        "payload_bytes": payload_bytes,
        "payload_pointer_member": 0x18,
        "copy_ranges": copy_ranges,
        "bit_fields": [dict(field, mask=1) for field in bit_fields],
        "validation": [
            {
                "operation": "equal_bits",
                "left": {"payload_offset": 0x7E0, "bit": 0},
                "right": {"payload_offset": 0x240, "bit": 0},
            },
            {
                "operation": "implies",
                "condition": {"payload_offset": 0x23C, "bit": 0},
                "required": {"payload_offset": 0x646, "bit": 0},
            },
        ],
        "success": {"member": 0x08, "value": 1},
        "error_markers": {
            "member": 0x0C,
            "framing": 0x100,
            "validation": 0x0A,
        },
        "producer": PARSE_RENDER_HARDWARE_KERNEL_COMMAND,
    }


def recover_g17_3d_common_passthrough(image: bytes) -> dict[str, object]:
    """Recover the raw render-record fields copied into a 3D descriptor.

    processRenderSetup passes retained_payload + 0x2d0 to the leaf copy
    helper.  That helper is a fixed scatter-copy into the 0xc40-byte internal
    descriptor, with eight source bytes reduced to bit zero.  Keep the map
    explicit because the destination is subsequently consumed by the HAL300
    register-list producer and is not a firmware wire structure by itself.
    """

    symbols = macho_symbols(image)
    required = (
        COPY_3D_COMMON_PASSTHROUGH,
        PROCESS_RENDER_SETUP,
        ALLOC_3D_COMMAND_DESCRIPTOR,
    )
    missing = [name for name in required if name not in symbols]
    if missing:
        raise ValueError(f"Mach-O is missing 3D descriptor producers: {missing}")

    copy_address, copy_code = symbol_code(image, COPY_3D_COMMON_PASSTHROUGH)
    require_instruction_words_at(
        copy_code,
        "G17 3D common passthrough copy",
        {
            0x004: 0x9106E029,  # source alias at common record +0x1b8
            0x008: 0x9117A008,  # destination alias at descriptor +0x5e8
            0x00C: 0xF940002A,  # first qword from common +0
            0x010: 0xF902740A,  # -> descriptor +0x4e8
            0x090: 0x3D800100,  # common +0x80 -> descriptor +0x5e8
            0x0A8: 0xF9025C0A,  # common +0xe0 -> descriptor +0x4b8
            0x0AC: 0xF902580B,  # common +0xe8 -> descriptor +0x4b0
            0x140: 0x3D81D400,  # common +0x1c8 -> descriptor +0x750
            0x19C: 0x3D81D000,  # common +0x1b8 -> descriptor +0x740
            0x1A4: 0xB9088809,  # common +0x370 -> descriptor +0x888
            0x1B4: 0x3D82BC00,  # common +0x3b0 -> descriptor +0xaf0
            0x1BC: 0x3D82C000,  # common +0x3c0 -> descriptor +0xb00
            0x1C4: 0x12000129,  # common +0x37f reduced to bit zero
            0x1C8: 0x391F8009,  # -> descriptor +0x7e0
            0x20C: 0xB9041009,  # common +0x384 -> descriptor +0x410
            0x228: 0x3D815101,  # common +0x3d0 -> descriptor +0xb28
            0x230: 0xFD059C00,  # common +0x3e0 -> descriptor +0xb38
            0x238: 0xB90B4008,  # common +0x3e8 -> descriptor +0xb40
            0x24C: 0xD65F03C0,
        },
    )
    if len(copy_code) != 0x250:
        raise ValueError(f"unexpected 3D passthrough producer length {len(copy_code):#x}")

    setup_address, setup_code = symbol_code(image, PROCESS_RENDER_SETUP)
    require_instruction_words_at(
        setup_code,
        "G17 3D common passthrough source",
        {
            0x1F28: 0xF9400F48,  # retained render-payload pointer at command +0x18
            0x1F70: 0x910B4101,  # common record is payload +0x2d0
            0x1F74: 0xAA1903E0,  # 3D descriptor argument
        },
    )
    call_word = struct.unpack_from("<I", setup_code, 0x1F78)[0]
    if decode_bl_target(setup_address + 0x1F78, call_word) != copy_address:
        raise ValueError("G17 render setup no longer calls the passthrough producer")

    _alloc_address, alloc_code = symbol_code(image, ALLOC_3D_COMMAND_DESCRIPTOR)
    require_instruction_words_at(
        alloc_code,
        "G17 3D descriptor allocation",
        {0x018: 0x52818801},  # typed allocation size 0xc40
    )

    copy_ranges = [
        (0x000, 0x4E8, 0x80),
        (0x080, 0x5E8, 0x30),
        (0x0E0, 0x4B8, 0x08),
        (0x0E8, 0x4B0, 0x08),
        (0x0F8, 0x648, 0x10),
        (0x108, 0x658, 0x08),
        (0x110, 0x660, 0x10),
        (0x120, 0x698, 0x08),
        (0x128, 0x6C8, 0x08),
        (0x130, 0x6E8, 0x08),
        (0x138, 0x700, 0x08),
        (0x140, 0x670, 0x08),
        (0x148, 0x6A0, 0x08),
        (0x150, 0x6D0, 0x08),
        (0x158, 0x6F0, 0x08),
        (0x160, 0x708, 0x08),
        (0x168, 0x680, 0x08),
        (0x170, 0x6B0, 0x08),
        (0x178, 0x6D8, 0x08),
        (0x180, 0x710, 0x08),
        (0x188, 0x728, 0x08),
        (0x190, 0x688, 0x08),
        (0x198, 0x6B8, 0x08),
        (0x1A0, 0x6E0, 0x08),
        (0x1A8, 0x718, 0x08),
        (0x1B0, 0x730, 0x08),
        (0x1B8, 0x740, 0x10),
        (0x1C8, 0x750, 0x10),
        (0x1D8, 0x738, 0x08),
        (0x0F0, 0x4E0, 0x08),
        (0x1E0, 0x7F8, 0x08),
        (0x1E8, 0xAD0, 0x04),
        (0x1F0, 0xAD8, 0x08),
        (0x1F8, 0x7B0, 0x08),
        (0x200, 0x7C0, 0x04),
        (0x2A8, 0x7E8, 0x08),
        (0x368, 0x7A8, 0x08),
        (0x0B0, 0x790, 0x08),
        (0x0B8, 0x798, 0x04),
        (0x0C0, 0x760, 0x10),
        (0x0D0, 0x770, 0x10),
        (0x370, 0x888, 0x04),
        (0x384, 0x410, 0x04),
        (0x3A0, 0xAE0, 0x10),
        (0x3B0, 0xAF0, 0x10),
        (0x3C0, 0xB00, 0x10),
        (0x3D0, 0xB28, 0x10),
        (0x3E0, 0xB38, 0x08),
        (0x3E8, 0xB40, 0x04),
    ]
    bit_fields = [
        (0x375, 0x88C),
        (0x378, 0x895),
        (0x379, 0x896),
        (0x37B, 0x898),
        (0x37C, 0x962),
        (0x37D, 0x963),
        (0x37E, 0x899),
        (0x37F, 0x7E0),
    ]

    # Count the real masking operations rather than inferring a count from
    # nearby byte fields. Every selected G17C boolean copy is exactly one
    # LDRB -> AND #1 -> STRB chain. This also makes a stale prose count fail
    # against the binary instead of becoming part of the recovered ABI.
    mask_operations = []
    for instruction_offset, word in words(copy_code):
        logical = decode_logical_immediate_w(word)
        if logical is None or logical[0] != "and" or logical[3] != 1:
            continue
        if instruction_offset < 4 or instruction_offset + 8 > len(copy_code):
            raise ValueError("truncated G17 common boolean mask chain")
        load = decode_integer_load_unsigned(
            struct.unpack_from("<I", copy_code, instruction_offset - 4)[0]
        )
        store = decode_integer_store_unsigned(
            struct.unpack_from("<I", copy_code, instruction_offset + 4)[0]
        )
        _kind, destination_register, source_register, _mask = logical
        if (
            load is None
            or store is None
            or load[:2] != (source_register, 1)
            or load[3] != 1
            or store[:2] != (destination_register, 0)
            or store[3] != 1
        ):
            raise ValueError("malformed G17 common boolean mask chain")
        mask_operations.append(
            {
                "producer_offset": instruction_offset,
                "source_offset": load[2],
                "descriptor_member": store[2],
                "mask": 1,
            }
        )
    if len(mask_operations) != len(bit_fields) or {
        (entry["source_offset"], entry["descriptor_member"])
        for entry in mask_operations
    } != set(bit_fields):
        raise ValueError("G17 common boolean copy map does not match mask chains")

    source_bytes = 0x3EC
    descriptor_bytes = 0xC40
    if any(source + size > source_bytes or destination + size > descriptor_bytes
           for source, destination, size in copy_ranges):
        raise ValueError("3D passthrough copy falls outside its source or descriptor")
    if any(source >= source_bytes or destination >= descriptor_bytes
           for source, destination in bit_fields):
        raise ValueError("3D passthrough bit field falls outside its object")

    return {
        "descriptor_bytes": descriptor_bytes,
        "source": {
            "payload_pointer_member": 0x18,
            "payload_offset": 0x2D0,
            "bytes": source_bytes,
        },
        "copy_ranges": [
            {
                "source_offset": source,
                "descriptor_member": destination,
                "bytes": size,
            }
            for source, destination, size in copy_ranges
        ],
        "bit_fields": [
            {
                "source_offset": source,
                "descriptor_member": destination,
                "mask": 1,
            }
            for source, destination in bit_fields
        ],
        "mask_operations": mask_operations,
        "producer": COPY_3D_COMMON_PASSTHROUGH,
        "caller": PROCESS_RENDER_SETUP,
    }


def explain_g17_3d_common_boolean_accounting(
    render_payload: dict[str, object], common_passthrough: dict[str, object]
) -> dict[str, object]:
    """Reconcile parser booleans with the common descriptor-copy helper."""

    source = common_passthrough["source"]
    common_start = int(source["payload_offset"])
    common_bytes = int(source["bytes"])
    common_end = common_start + common_bytes
    helper_fields = common_passthrough["bit_fields"]
    mask_operations = common_passthrough["mask_operations"]
    helper_sources = {
        common_start + int(field["source_offset"]) for field in helper_fields
    }
    helper_destinations = {
        int(field["descriptor_member"]) for field in helper_fields
    }

    def mentions_payload_offset(value: object, target: int) -> bool:
        if isinstance(value, dict):
            if value.get("payload_offset") == target:
                return True
            return any(mentions_payload_offset(item, target) for item in value.values())
        if isinstance(value, list):
            return any(mentions_payload_offset(item, target) for item in value)
        return False

    validation = render_payload["validation"]
    parser_only = []
    for field in render_payload["bit_fields"]:
        payload_offset = int(field["payload_offset"])
        if not common_start <= payload_offset < common_end:
            continue
        if payload_offset in helper_sources:
            continue
        parser_only.append(
            {
                "payload_offset": payload_offset,
                "common_source_offset": payload_offset - common_start,
                "command_member": int(field["command_member"]),
                "mask": int(field["mask"]),
                "validation_operand": mentions_payload_offset(validation, payload_offset),
            }
        )

    combined_sources = helper_sources | {
        int(field["payload_offset"]) for field in parser_only
    }
    if (
        len(mask_operations) != 8
        or len(helper_sources) != 8
        or len(helper_destinations) != 8
        or {field["payload_offset"] for field in parser_only} != {0x646, 0x650}
        or len(combined_sources) != 10
    ):
        raise ValueError("unexpected G17 common-record boolean accounting")

    return {
        "counting_rule": "one field per LDRB -> AND #1 -> STRB chain in the helper",
        "helper": {
            "mask_operations": len(mask_operations),
            "unique_source_fields": len(helper_sources),
            "unique_descriptor_fields": len(helper_destinations),
            "one_to_one": len(mask_operations)
            == len(helper_sources)
            == len(helper_destinations),
        },
        "parser_only_fields_within_common_record": parser_only,
        "combined_distinct_raw_boolean_sources": len(combined_sources),
        "nine_field_count": {
            "supported": False,
            "reason": (
                "the helper maps eight sources to eight destinations; including the "
                "two parser-only fields in the same raw record yields ten, not nine"
            ),
        },
    }


def recover_g17_render_descriptor_fields(
    image: bytes, iogpu: bytes, render_payload: dict[str, object]
) -> dict[str, object]:
    """Recover normalized render-command fields copied after raw passthrough.

    processRenderSetup consumes both the retained raw payload and the compact
    AGXRenderHardwareKernelCommand built by parseAndValidate. Keep this block
    separate from copy3DCommonPassthroughData: it contains eight direct
    descriptor writes and one conditional write, and is therefore a genuine
    nine-write stage rather than a ninth boolean in the common copy helper.
    """

    symbols = macho_symbols(image)
    required = (PROCESS_RENDER_SETUP, BASE_CONFIGURE_DEVICE)
    missing = [name for name in required if name not in symbols]
    if missing:
        raise ValueError(f"Mach-O is missing {missing[0]}")
    iogpu_symbols = macho_symbols(iogpu)
    if IOGPU_COMMAND_DESCRIPTOR_INIT not in iogpu_symbols:
        raise ValueError(
            f"IOGPUFamily is missing {IOGPU_COMMAND_DESCRIPTOR_INIT}"
        )
    _address, code = symbol_code(image, PROCESS_RENDER_SETUP)
    require_instruction_words_at(
        code,
        "G17 normalized render descriptor fields",
        {
            0x0048: 0x911E70B7,  # descriptor alias is argument 5 +0x79c
            0x0244: 0xF90033F7,  # preserve it across the setup body
            0x1804: 0xF94033F7,  # restore before the normalized writes
            0x1CEC: 0x394A0B48,  # command +0x282
            0x1CF4: 0x12000108,  # reduced to bit zero
            0x1CF8: 0x3937F2E8,  # -> descriptor +0x1598
            0x20E0: 0xFD400120,  # command +0x25c
            0x20E4: 0xFD025320,  # -> descriptor +0x4a0
            0x20E8: 0xB9426749,  # command +0x264
            0x20EC: 0xB904AB29,  # -> descriptor +0x4a8
            0x2134: 0x3946E349,  # command +0x1b8
            0x2138: 0x12000129,
            0x213C: 0x392642E9,  # -> descriptor +0x112c
            0x2140: 0x394A0349,  # command +0x280
            0x2144: 0x12000129,
            0x2148: 0x392632E9,  # -> descriptor +0x1128
            0x2190: 0x3946E348,  # command +0x1b8 again
            0x2194: 0x12000108,
            0x2198: 0x39225F28,  # -> descriptor +0x897
            0x219C: 0x394A0748,  # command +0x281
            0x21A0: 0x12000108,
            0x21A4: 0x39224F28,  # -> descriptor +0x893
            0x21A8: 0x39482348,  # command +0x208
            0x21AC: 0x39258328,  # -> descriptor +0x960
            0x21B0: 0x394A0F48,  # command +0x283 condition
            0x21B4: 0x36000068,  # nonzero selects literal one
            0x21B8: 0x52800028,
            0x21C0: 0xF9400B28,  # otherwise follow descriptor +0x10
            0x21C4: 0x529EFD29,  # object byte +0xf7e9
            0x21C8: 0x8B090108,
            0x21CC: 0x39400108,
            0x21D0: 0x12000108,
            0x21D4: 0x3930E328,  # -> descriptor +0xc38
        },
    )

    # IOGPUCommandDescriptor::init retains its IOGPU* first argument at
    # descriptor +0x10. AGX passes the accelerator there. configureDevice
    # explicitly clears accelerator +0xf7e8..+0xf7e9 before the descriptor
    # readers run, so the conditional fallback byte is a checked zero for
    # this selected driver rather than an input Vinix must invent.
    _address, descriptor_init = symbol_code(iogpu, IOGPU_COMMAND_DESCRIPTOR_INIT)
    require_instruction_words_at(
        descriptor_init,
        "G17 descriptor accelerator retention",
        {
            0x020: 0xAA0103F7,  # retain the IOGPU* first argument
            0x024: 0xAA0003F4,  # descriptor base
            0x060: 0xAA1403F8,
            0x064: 0xF8038F1F,  # descriptor +0x38, post-indexed
            0x068: 0xF81D8317,  # IOGPU* -> descriptor +0x10
        },
    )
    _address, configure_code = symbol_code(image, BASE_CONFIGURE_DEVICE)
    require_instruction_words_at(
        configure_code,
        "G17 descriptor fallback device bit",
        {
            0x034: 0x529EE508,  # accelerator member block +0xf728
            0x038: 0x8B080018,
            0x5A8: 0x6F00E401,  # zero vector
            0x5AC: 0x3D802F01,  # accelerator +0xf7d8..+0xf7e7
            0x5B0: 0x7901831F,  # zero +0xf7e8..+0xf7e9
        },
    )

    def payload_source(command_member: int, size: int) -> tuple[int, bool]:
        matches: list[tuple[int, bool]] = []
        for field in render_payload["copy_ranges"]:
            member = int(field["command_member"])
            field_size = int(field["bytes"])
            if member <= command_member and command_member + size <= member + field_size:
                matches.append(
                    (
                        int(field["payload_offset"]) + command_member - member,
                        False,
                    )
                )
        for field in render_payload["bit_fields"]:
            if int(field["command_member"]) == command_member and size == 1:
                matches.append((int(field["payload_offset"]), True))
        if len(matches) != 1:
            raise ValueError(
                f"G17 normalized field {command_member:#x}+{size:#x} has "
                f"{len(matches)} raw-payload sources"
            )
        return matches[0]

    direct_specs = [
        (0x282, 0x1598, 1, True, 0x1CF8),
        (0x25C, 0x04A0, 8, False, 0x20E4),
        (0x264, 0x04A8, 4, False, 0x20EC),
        (0x1B8, 0x112C, 1, True, 0x213C),
        (0x280, 0x1128, 1, True, 0x2148),
        (0x1B8, 0x0897, 1, True, 0x2198),
        (0x281, 0x0893, 1, True, 0x21A4),
        (0x208, 0x0960, 1, False, 0x21AC),
    ]
    direct_fields = []
    for command_member, descriptor_member, size, masked, producer_offset in direct_specs:
        payload_offset, parser_masked = payload_source(command_member, size)
        if parser_masked != masked:
            raise ValueError("G17 render descriptor mask provenance changed")
        field = {
            "command_member": command_member,
            "payload_offset": payload_offset,
            "descriptor_member": descriptor_member,
            "bytes": size,
            "producer_offset": producer_offset,
        }
        if masked:
            field["mask"] = 1
        direct_fields.append(field)

    conditional_member = 0x283
    conditional_payload, parser_masked = payload_source(conditional_member, 1)
    if not parser_masked or conditional_payload != 0x650:
        raise ValueError("G17 conditional render field provenance changed")

    return {
        "source_stage": "normalized_render_command",
        "command_bytes": 0x284,
        "descriptor_bytes": 0x15B0,
        "descriptor_alias": {"source_argument": 5, "addend": 0x79C},
        "direct_write_count": len(direct_fields),
        "direct_fields": direct_fields,
        "conditional_field": {
            "command_member": conditional_member,
            "payload_offset": conditional_payload,
            "descriptor_member": 0xC38,
            "bytes": 1,
            "condition_mask": 1,
            "nonzero_value": 1,
            "zero_source": {
                "descriptor_object_pointer_member": 0x10,
                "object_role": "IOGPU_accelerator",
                "accelerator_member": 0xF7E9,
                "mask": 1,
                "value": 0,
                "producer": BASE_CONFIGURE_DEVICE,
                "producer_offset": 0x5B0,
            },
            "producer_offset": 0x21D4,
        },
        "total_descriptor_writes": len(direct_fields) + 1,
        "counting_note": (
            "this stage has nine descriptor writes; it is separate from the "
            "eight boolean mask chains in copy3DCommonPassthroughData"
        ),
        "producer": PROCESS_RENDER_SETUP,
    }


def recover_g17_ta_render_passthrough(image: bytes) -> dict[str, object]:
    """Recover the raw render-payload copies around the 3D common helper."""

    symbols = macho_symbols(image)
    required = (PROCESS_RENDER_SETUP, COPY_3D_COMMON_PASSTHROUGH)
    missing = [name for name in required if name not in symbols]
    if missing:
        raise ValueError(f"Mach-O is missing TA render passthrough producers: {missing}")

    setup_address, setup_code = symbol_code(image, PROCESS_RENDER_SETUP)
    copy_address = symbols[COPY_3D_COMMON_PASSTHROUGH]
    call_word = struct.unpack_from("<I", setup_code, 0x1F78)[0]
    if decode_bl_target(setup_address + 0x1F78, call_word) != copy_address:
        raise ValueError("G17 TA render setup no longer calls the 3D common helper")
    require_instruction_words_at(
        setup_code,
        "G17 TA render passthrough",
        {
            0x1D64: 0xF9400F48,  # retained raw payload at parsed command +0x18
            0x1D68: 0x3DC00100,  # payload +0 -> descriptor +0xfe0
            0x1D80: 0xF9401909,  # payload +0x30 -> descriptor +0x1050
            0x1DB0: 0x3DC01900,  # payload +0x60 completes the 0x40-byte range
            0x1DC0: 0x3DC07D00,  # payload +0x1f0 -> descriptor +0x1010
            0x1E44: 0x39491909,  # payload +0x246, reduced to bit zero
            0x1E60: 0x3948F509,  # payload +0x23d, reduced to bit zero
            0x1ECC: 0xB9423909,  # payload +0x238 -> descriptor +0x13b0
            0x1EE8: 0x3DC0A100,  # payload +0x280 -> descriptor +0x14d0
            0x1F1C: 0x39492908,  # payload +0x24a -> descriptor +0x15a8
            0x1F28: 0xF9400F48,  # reload retained payload
            0x1F38: 0xB948110A,  # payload +0x810 -> descriptor +0x86c
            0x1F70: 0x910B4101,  # common record at payload +0x2d0
            0x1F78: call_word,
            0x1F7C: 0xF9400F48,  # reload after helper
            0x1F80: 0xF9436109,  # payload +0x6c0 -> descriptor +0x4c0
            0x1FA8: 0xF9439509,  # payload +0x728 -> descriptor +0x568
            0x2058: 0xFD437D00,  # payload +0x6f8 -> derived +0x79c prefix
            0x2068: 0x911C2109,  # payload +0x708 vector source
            0x2084: 0xBD47D900,  # four packed flags at payload +0x7d8
            0x2088: 0x2F08A400,
            0x208C: 0x2F0797C0,
            0x2090: 0x0E001800,
            0x20BC: 0xB9480909,  # payload +0x808 -> descriptor +0xaa8
            0x20CC: 0x39200328,  # payload +0x80c bit -> descriptor +0x800
        },
    )

    pre_common_copy_ranges = [
        (0x000, 0xFE0, 0x30),
        (0x030, 0x1050, 0x40),
        (0x1F0, 0x1010, 0x20),
        (0x210, 0x1030, 0x08),
        (0x220, 0x1038, 0x10),
        (0x230, 0x1048, 0x04),
        (0x0B8, 0x10C0, 0x0C),
        (0x070, 0x1090, 0x30),
        (0x1E4, 0x10E0, 0x0C),
        (0x168, 0x1110, 0x08),
        (0x0A0, 0x1108, 0x08),
        (0x238, 0x13B0, 0x04),
        (0x258, 0xF60, 0x04),
        (0x280, 0x14D0, 0x30),
        (0x2B0, 0x1518, 0x10),
        (0x2C0, 0x1528, 0x0C),
        (0x810, 0x86C, 0x04),
        (0x818, 0x870, 0x08),
        (0x822, 0x961, 0x01),
        (0x830, 0x950, 0x0C),
    ]
    pre_common_bit_fields = [
        (0x246, 0x1100, 4),
        (0x23D, 0x1129, 1),
        (0x243, 0x1130, 1),
        (0x23E, 0x112A, 1),
        (0x23F, 0x112B, 1),
        (0x241, 0x112D, 1),
        (0x242, 0x112F, 1),
        (0x249, 0x1132, 1),
        (0x244, 0x1270, 1),
        (0x245, 0x1271, 1),
        (0x24B, 0x1539, 1),
        (0x24A, 0x15A8, 1),
        (0x820, 0x112E, 1),
        (0x814, 0x868, 1),
        (0x820, 0x88D, 1),
    ]
    post_common_copy_ranges = [
        (0x6C0, 0x4C0, 0x08),
        (0x6C8, 0x618, 0x30),
        (0x728, 0x568, 0x80),
        (0x7A8, 0x678, 0x08),
        (0x7B0, 0x6F8, 0x08),
        (0x7B8, 0x690, 0x08),
        (0x7C0, 0x720, 0x08),
        (0x7C8, 0x6A8, 0x08),
        (0x7D0, 0x6C0, 0x08),
        (0x6F8, 0x79C, 0x0C),
        (0x708, 0x780, 0x10),
        (0x7E8, 0x4C8, 0x18),
        (0x808, 0xAA8, 0x04),
    ]
    post_common_bit_fields = [
        (0x7D8, 0x88E, 1),
        (0x7D9, 0x88F, 1),
        (0x7DA, 0x890, 1),
        (0x7DB, 0x891, 1),
        (0x7DC, 0x892, 1),
        (0x7DD, 0x89A, 1),
        (0x7DE, 0x89B, 1),
        (0x80C, 0x800, 1),
    ]
    payload_bytes = 0x9D0
    descriptor_bytes = 0x15B0
    ranges = pre_common_copy_ranges + post_common_copy_ranges
    fields = pre_common_bit_fields + post_common_bit_fields
    if any(source + size > payload_bytes or destination + size > descriptor_bytes
           for source, destination, size in ranges):
        raise ValueError("TA render passthrough copy falls outside its objects")
    if any(source >= payload_bytes or destination + size > descriptor_bytes
           for source, destination, size in fields):
        raise ValueError("TA render passthrough bit field falls outside its objects")

    def encode_ranges(values: list[tuple[int, int, int]]) -> list[dict[str, int]]:
        return [
            {
                "source_offset": source,
                "descriptor_member": destination,
                "bytes": size,
            }
            for source, destination, size in values
        ]

    def encode_fields(values: list[tuple[int, int, int]]) -> list[dict[str, int]]:
        return [
            {
                "source_offset": source,
                "descriptor_member": destination,
                "destination_bytes": size,
                "mask": 1,
            }
            for source, destination, size in values
        ]

    return {
        "payload_bytes": payload_bytes,
        "descriptor_bytes": descriptor_bytes,
        "pre_common_copy_ranges": encode_ranges(pre_common_copy_ranges),
        "pre_common_bit_fields": encode_fields(pre_common_bit_fields),
        "common": COPY_3D_COMMON_PASSTHROUGH,
        "post_common_copy_ranges": encode_ranges(post_common_copy_ranges),
        "post_common_bit_fields": encode_fields(post_common_bit_fields),
        "producer": PROCESS_RENDER_SETUP,
    }


def recover_g17_3d_descriptor_initialization(image: bytes) -> dict[str, object]:
    """Recover the selected TA subclass size and its scalar staging defaults."""

    symbols = macho_symbols(image)
    required = (
        ALLOC_3D_COMMAND_DESCRIPTOR,
        INIT_3D_COMMAND_DESCRIPTOR,
        ALLOC_TA_COMMAND_DESCRIPTOR,
        INIT_TA_COMMAND_DESCRIPTOR,
    )
    missing = [name for name in required if name not in symbols]
    if missing:
        raise ValueError(f"Mach-O is missing 3D descriptor initializers: {missing}")

    _alloc_address, alloc_code = symbol_code(image, ALLOC_3D_COMMAND_DESCRIPTOR)
    require_instruction_words_at(
        alloc_code,
        "G17 3D descriptor allocation defaults",
        {
            0x018: 0x52818801,  # typed allocation size 0xc40
            0x098: 0xB9096808,  # -1 at +0x968
            0x0A8: 0x2F00E5E1,  # synthesize 0x00000000ffffffff
            0x0AC: 0xFD055001,  # -> +0xaa0
            0x0B4: 0xB90B6008,  # -1 at +0xb60
            0x0D8: 0x3930E01F,  # final allocation-owned byte at +0xc38
        },
    )

    _init_address, init_code = symbol_code(image, INIT_3D_COMMAND_DESCRIPTOR)
    require_instruction_words_at(
        init_code,
        "G17 3D descriptor initialization defaults",
        {
            0x114: 0x9112C260,  # clear descriptor +0x4b0
            0x118: 0x52806A01,  # for 0x350 bytes
            0x128: 0xB9090274,  # -1 at +0x900
            0x188: 0xB9014674,  # -1 at +0x144
            0x1D0: 0xF9461668,  # mask existing +0xc28
            0x1D4: 0x9254A508,
            0x1D8: 0xF9061668,
            0x1E0: 0x52802029,  # 0x101
            0x1E4: 0x79000109,  # -> unaligned halfword +0x1c1
            0x1EC: 0xB9040275,  # one at +0x400
            0x230: 0xB9041268,  # two at +0x410
            0x234: 0xB90C3275,  # one at +0xc30
            0x238: 0xB902D674,  # -1 at +0x2d4
        },
    )

    _ta_alloc_address, ta_alloc_code = symbol_code(image, ALLOC_TA_COMMAND_DESCRIPTOR)
    require_instruction_words_at(
        ta_alloc_code,
        "G17 TA descriptor allocation defaults",
        {
            0x018: 0x5282B601,  # selected typed allocation size 0x15b0
            0x07C: 0xB9096808,  # inherited -1 at +0x968
            0x08C: 0x2F00E5E1,  # inherited 0x00000000ffffffff
            0x090: 0xFD055001,  # -> +0xaa0
            0x098: 0xB90B6008,  # inherited -1 at +0xb60
            0x114: 0xB9126C08,  # -1 at +0x126c
            0x124: 0xFD09D401,  # 0x00000000ffffffff at +0x13a8
            0x134: 0xB913E808,  # -1 at +0x13e8
        },
    )
    if len(ta_alloc_code) != 0x1A8:
        raise ValueError(
            f"unexpected G17 TA descriptor allocator size {len(ta_alloc_code):#x}"
        )

    ta_init_address, ta_init_code = symbol_code(image, INIT_TA_COMMAND_DESCRIPTOR)
    base_init_address = symbols[INIT_3D_COMMAND_DESCRIPTOR]
    base_call_word = struct.unpack_from("<I", ta_init_code, 0x18)[0]
    if decode_bl_target(ta_init_address + 0x18, base_call_word) != base_init_address:
        raise ValueError("G17 TA descriptor init no longer calls its 3D base init")
    require_instruction_words_at(
        ta_init_code,
        "G17 TA descriptor initialization defaults",
        {
            0x018: base_call_word,
            0x0DC: 0x12800015,  # literal -1 used by derived defaults
            0x0E0: 0xB9120A75,  # -> +0x1208
            0x164: 0xB9126675,  # -> +0x1264
            0x168: 0xB9014675,  # inherited +0x144
            0x1A8: 0x52800048,  # literal two
            0x1AC: 0xB90F6268,  # -> +0xf60
            0x1B0: 0xF94A5A68,  # mask existing +0x14b0
            0x1B4: 0x9254A508,
            0x1B8: 0xF90A5A68,
            0x1BC: 0xB90E1A75,  # -1 at +0xe18
        },
    )
    if len(ta_init_code) != 0x1D4:
        raise ValueError(
            f"unexpected G17 TA descriptor init size {len(ta_init_code):#x}"
        )

    return {
        "base_descriptor_bytes": 0xC40,
        "descriptor_bytes": 0x15B0,
        "selected_class": "AGXTACommandDescriptor",
        # Vinix staging does not instantiate the C++ base classes or their
        # retained OSObject pointers. A full clear is a host-side invariant;
        # these are the nonzero scalar defaults the selected derived
        # allocation/init path installs before processRenderSetup.
        "staging_clear": True,
        "cleared_range": {"offset": 0x4B0, "bytes": 0x350},
        "initial_values": [
            {"member": 0x144, "bytes": 4, "value": 0xFFFFFFFF},
            {"member": 0x1C1, "bytes": 2, "value": 0x101},
            {"member": 0x2D4, "bytes": 4, "value": 0xFFFFFFFF},
            {"member": 0x400, "bytes": 4, "value": 1},
            {"member": 0x410, "bytes": 4, "value": 2},
            {"member": 0x900, "bytes": 4, "value": 0xFFFFFFFF},
            {"member": 0x968, "bytes": 4, "value": 0xFFFFFFFF},
            {"member": 0xAA0, "bytes": 8, "value": 0xFFFFFFFF},
            {"member": 0xB60, "bytes": 4, "value": 0xFFFFFFFF},
            {"member": 0xC30, "bytes": 4, "value": 1},
            {"member": 0xE18, "bytes": 4, "value": 0xFFFFFFFF},
            {"member": 0xF60, "bytes": 4, "value": 2},
            {"member": 0x1208, "bytes": 4, "value": 0xFFFFFFFF},
            {"member": 0x1264, "bytes": 4, "value": 0xFFFFFFFF},
            {"member": 0x126C, "bytes": 4, "value": 0xFFFFFFFF},
            {"member": 0x13A8, "bytes": 8, "value": 0xFFFFFFFF},
            {"member": 0x13E8, "bytes": 4, "value": 0xFFFFFFFF},
        ],
        "masked_defaults": [
            {
                "member": 0xC28,
                "bytes": 8,
                "mask": 0xFFFFF000003FFFFF,
            },
            {
                "member": 0x14B0,
                "bytes": 8,
                "mask": 0xFFFFF000003FFFFF,
            },
        ],
        "base_allocator": ALLOC_3D_COMMAND_DESCRIPTOR,
        "base_initializer": INIT_3D_COMMAND_DESCRIPTOR,
        "allocator": ALLOC_TA_COMMAND_DESCRIPTOR,
        "initializer": INIT_TA_COMMAND_DESCRIPTOR,
    }


def recover_g17_channel_command_common_fields(image: bytes) -> dict[str, object]:
    """Recover the common host-written fields in every channel command.

    submitNopUnprepared selects the command pool by AGFIChannelCommandType,
    then writes the same four packed fields before it publishes the command.
    The final qword ends at 0x6a, which is inside even the smallest 0x80-byte
    channel command.  Other bytes are deliberately left opaque: pool backing
    construction may have installed per-command templates there.
    """

    symbols = macho_symbols(image)
    if SUBMIT_NOP_UNPREPARED not in symbols:
        raise ValueError(f"Mach-O is missing {SUBMIT_NOP_UNPREPARED}")

    _address, code = symbol_code(image, SUBMIT_NOP_UNPREPARED)
    require_instruction_words_at(
        code,
        "G17 common channel-command fields",
        {
            0x024: 0xAA0303F6,  # data-master type argument preserved in w22
            0x218: 0xB80222F6,  # -> packed command +0x22
            0x21C: 0x52800028,  # literal one
            0x220: 0xB801A2E8,  # -> packed command +0x1a
            0x224: 0xB80322FF,  # zero -> packed command +0x32
            0x228: 0xF80622FF,  # zero -> packed command +0x62
        },
    )

    fields = {
        "control_01a": {"offset": 0x1A, "bytes": 4, "value": 1},
        "data_master_type": {"offset": 0x22, "bytes": 4, "source_argument": 3},
        "control_032": {"offset": 0x32, "bytes": 4, "value": 0},
        "control_062": {"offset": 0x62, "bytes": 8, "value": 0},
    }
    end = max(field["offset"] + field["bytes"] for field in fields.values())
    if end != 0x6A or end > 0x80:
        raise ValueError(f"unexpected common command prefix extent {end:#x}")

    return {
        "known_prefix_bytes": end,
        "smallest_command_bytes": 0x80,
        "preserve_other_bytes": True,
        "fields": fields,
        "producer": SUBMIT_NOP_UNPREPARED,
    }


def recover_g17_register_entry_codec(image: bytes) -> dict[str, object]:
    """Recover the HAL300 register-entry encoder's exact three-field split."""

    symbols = macho_symbols(image)
    if RCE_ENCODE_ENTRY not in symbols:
        raise ValueError(f"Mach-O is missing {RCE_ENCODE_ENTRY}")
    _address, code = symbol_code(image, RCE_ENCODE_ENTRY)
    require_instruction_words_at(
        code,
        "G17 register-entry codec",
        {
            0x004: 0xB9400028,  # existing template word
            0x008: 0x121F7908,  # clear encoded mode bit 0
            0x00C: 0x120E4108,  # preserve 0xfffc0007 after that clear
            0x010: 0x121D3849,  # selector argument & 0x3fff8
            0x014: 0x33000069,  # insert mode argument bit 0
            0x018: 0x2A080128,
            0x01C: 0xB9000028,  # encoded word at +0
            0x020: 0xF8004024,  # unaligned 64-bit value at +4
            0x024: 0xD65F03C0,
        },
    )
    return {
        "entry_bytes": 12,
        "selector_argument": 2,
        "selector_mask": 0x0003FFF8,
        "mode_argument": 3,
        "mode_mask": 0x1,
        "preserved_template_mask": 0xFFFC0006,
        "value_argument": 4,
        "value_offset": 4,
        "producer": RCE_ENCODE_ENTRY,
    }


def recover_g17_random_provider(driver: bytes, kernel: bytes) -> dict[str, object]:
    """Cross-check the CL mode-2 low-bit source against the kernel image."""

    symbols = macho_symbols(kernel)
    if KERNEL_RANDOM not in symbols:
        raise ValueError(f"Mach-O is missing {KERNEL_RANDOM}")
    function_address, code = symbol_code(
        driver, REGISTER_LIST_PRODUCERS["CL"]
    )
    require_instruction_words_at(
        code,
        "G17 CL random-bit provider",
        {G17_CL_RANDOM_CALL_OFFSET: G17_CL_RANDOM_CALL_WORD},
    )
    target = decode_bl_target(
        function_address + G17_CL_RANDOM_CALL_OFFSET,
        G17_CL_RANDOM_CALL_WORD,
    )
    if target != symbols[KERNEL_RANDOM]:
        raise ValueError(
            f"G17 CL random call targets {target:#x}, not "
            f"{KERNEL_RANDOM} at {symbols[KERNEL_RANDOM]:#x}"
        )
    return {
        "provider": KERNEL_RANDOM,
        "call_offset": G17_CL_RANDOM_CALL_OFFSET,
        "return_mask": 1,
    }


def recover_g17_register_selectors(image: bytes) -> dict[str, object]:
    """Recover the selector encoding and the set each work producer emits.

    The encoded word keeps the template bits under 0xfffc0006. Virtual encoder
    calls supply an 8-byte-aligned selector in w2 (bits 3..17) and a separate
    one-bit mode in w3, which becomes encoded bit 0. Inline paths construct
    the combined word directly.

    In addition to the literal audit, a narrow backwards slice resolves the w2
    selector argument at every virtual encoder call.  That recovers the
    ADD/SUB-derived and OR-composed values which dominate the producers.  The
    complete flag remains false because a two-record CL inline sequence has
    runtime-dependent selector words and the producers' control-flow ordering
    is not classified yet.  What the selectors name is also not established;
    they are not SGX MMIO offsets.
    """

    symbols = macho_symbols(image)
    missing = [name for name in REGISTER_LIST_PRODUCERS.values() if name not in symbols]
    if missing:
        raise ValueError(f"Mach-O is missing register-list producers: {missing}")

    settable = ~G17_SELECTOR_TEMPLATE_MASK & 0xFFFFFFFF
    if settable != 0x0003FFF9:
        raise ValueError(f"unexpected G17 selector field {settable:#x}")
    encoder_selector_field = settable & ~0x1

    producers: dict[str, object] = {}
    literal_encoded_union: set[int] = set()
    literal_selector_union: set[int] = set()
    static_union: set[int] = set()
    for label, name in sorted(REGISTER_LIST_PRODUCERS.items()):
        _address, code = symbol_code(image, name)
        buffered = list(words(code))
        immediates: dict[int, int] = {}
        recency: dict[int, int] = {}
        found: set[int] = set()
        context = -SELECTOR_ARGUMENT_WINDOW
        encoder_calls: list[dict[str, object]] = []
        for index, (offset, word) in enumerate(buffered):
            # The producers materialize selectors with the 32-bit move forms.
            opcode = word & 0xFF800000
            if opcode in (0x52800000, 0x72800000):
                register = word & 0x1F
                immediate = (word >> 5) & 0xFFFF
                shift = ((word >> 21) & 0x3) * 16
                if opcode == 0x52800000:
                    immediates[register] = immediate << shift
                else:
                    immediates[register] = (
                        immediates.get(register, 0) & ~(0xFFFF << shift)
                    ) | (immediate << shift)
                recency[register] = index
                continue
            selector = decode_orr_register(word)
            if selector is not None:
                _destination, _first, source = selector
                candidate = immediates.get(source)
                if candidate is not None and not candidate & ~settable:
                    found.add(candidate)
                continue
            # The encoder helper takes its context in x0 as a stack address
            # and the selector in w2. Requiring the stack argument keeps
            # ordinary virtual calls, which pass an object in x0, out.
            if word & 0xFFC003FF == 0x910003E0:
                context = index
                continue
            if word & 0xFFFFFC00 == 0xD73F0800:
                candidate = immediates.get(2)
                if (
                    candidate is not None
                    and not candidate & ~settable
                    and index - recency.get(2, -SELECTOR_ARGUMENT_WINDOW)
                    < SELECTOR_ARGUMENT_WINDOW
                    and index - context < SELECTOR_ARGUMENT_WINDOW
                ):
                    found.add(candidate)

                # A real encoder call is followed by publication of one
                # 12-byte entry. Requiring both the stack encoder context and
                # that publication excludes the three unrelated virtual calls
                # present in every producer.
                publishes_entry = False
                for following_index, (_following_offset, following) in enumerate(
                    buffered[index + 1 : index + 20], index + 1
                ):
                    arithmetic = decode_add_sub_immediate_w(following)
                    if (
                        arithmetic is None
                        or arithmetic[0] != "add"
                        or arithmetic[3] != 12
                    ):
                        continue
                    if any(
                        store & 0xFFFFFC00 == 0x790E1400
                        for _store_offset, store in buffered[
                            following_index + 1 : following_index + 3
                        ]
                    ):
                        publishes_entry = True
                        break
                if index - context <= SELECTOR_ARGUMENT_WINDOW and publishes_entry:
                    resolved = resolve_static_w_register(buffered, index, 2)
                    if resolved is None:
                        raise ValueError(
                            f"{label} selector at producer +{offset:#x} is no "
                            "longer statically resolvable"
                        )
                    mode = resolve_static_w_register(buffered, index, 3)
                    if mode not in (0, 1):
                        raise ValueError(
                            f"{label} mode at producer +{offset:#x} is no "
                            "longer a static bit"
                        )
                    encoder_calls.append(
                        {
                            "producer_offset": offset,
                            "selector": resolved,
                            "mode": mode,
                            "value_source": classify_g17_value_argument(
                                buffered, index
                            ),
                        }
                    )
        if not found:
            raise ValueError(f"{label} producer emits no register selectors")
        for candidate in found:
            if candidate & 0x6:
                raise ValueError(
                    f"{label} selector {candidate:#x} sets a template-owned bit"
                )
            if candidate & ~0x1 & 0x7:
                raise ValueError(f"{label} selector {candidate:#x} is not 8-byte aligned")
        # Every entry emission advances the byte-length counter by 12, so the
        # number of those sites bounds how many selectors a producer can use.
        emission_sites = 0
        for index, (_offset, word) in enumerate(buffered):
            # 32-bit ADD immediate of 12, i.e. one entry's worth of bytes.
            if word & 0xFFC00000 != 0x11000000 or (word >> 10) & 0xFFF != 0xC:
                continue
            for _following_offset, following in buffered[index + 1 : index + 3]:
                if following & 0xFFFFFC00 == 0x790E1400:
                    emission_sites += 1
                    break
        if emission_sites <= len(found):
            raise ValueError(
                f"{label} selector sample is no longer smaller than its "
                f"{emission_sites} emission sites"
            )
        resolved = {int(entry["selector"]) for entry in encoder_calls}
        for candidate in resolved:
            if candidate & ~encoder_selector_field:
                raise ValueError(
                    f"{label} resolved selector {candidate:#x} exceeds the field"
                )
        if not encoder_calls:
            raise ValueError(f"{label} producer has no classified encoder calls")

        literal_selectors = {encoded & ~0x1 for encoded in found}
        static = literal_selectors | resolved
        literal_encoded_union |= found
        literal_selector_union |= literal_selectors
        static_union |= static
        producers[label] = {
            "producer": name,
            "literal_encoded_fields": len(found),
            "literal_selectors": len(literal_selectors),
            "entry_emission_sites": emission_sites,
            "encoded_fields": sorted(found),
            "selectors": sorted(literal_selectors),
            "encoder_call_sites": len(encoder_calls),
            "statically_resolved_encoder_calls": len(encoder_calls),
            "mode_0_calls": sum(
                entry["mode"] == 0 for entry in encoder_calls
            ),
            "mode_1_calls": sum(
                entry["mode"] == 1 for entry in encoder_calls
            ),
            "constant_value_calls": sum(
                entry["value_source"]["kind"] == "constant"
                for entry in encoder_calls
            ),
            "descriptor_value_calls": sum(
                entry["value_source"]["kind"] == "descriptor_load"
                for entry in encoder_calls
            ),
            "indirect_value_calls": sum(
                entry["value_source"]["kind"] == "indirect_load"
                for entry in encoder_calls
            ),
            "computed_value_calls": sum(
                entry["value_source"]["kind"] == "computed"
                for entry in encoder_calls
            ),
            "traced_copy_value_calls": sum(
                "via_register" in entry["value_source"]
                for entry in encoder_calls
            ),
            "copy_value_calls": sum(
                entry["value_source"].get("operation") == "register_copy"
                for entry in encoder_calls
            ),
            "recovered_copy_expression_calls": sum(
                entry["value_source"].get("operation") == "register_copy"
                and "expression" in entry["value_source"]
                for entry in encoder_calls
            ),
            "unresolved_copy_value_calls": sum(
                entry["value_source"].get("operation") == "register_copy"
                and "expression" not in entry["value_source"]
                for entry in encoder_calls
            ),
            "recovered_expression_calls": sum(
                "expression" in entry["value_source"]
                for entry in encoder_calls
            ),
            "recovered_conditional_calls": sum(
                entry["value_source"].get("operation") == "conditional"
                and "expression" in entry["value_source"]
                for entry in encoder_calls
            ),
            "resolved_encoder_selectors": sorted(resolved),
            "static_selectors": sorted(static),
            "encoder_entries": encoder_calls,
        }

    return {
        "template_mask": G17_SELECTOR_TEMPLATE_MASK,
        "encoded_field": settable,
        "selector_field": encoder_selector_field,
        "mode_bit": 0x1,
        "flag_bit": 0x1,
        "alignment": 8,
        "address_space_identified": False,
        "selectors_complete": False,
        "selector_formulas_complete": False,
        "completeness_note": (
            "every virtual encoder selector argument is statically resolved, "
            "but the finite static selector set excludes two inline CL words "
            "whose complete formulas are runtime-dependent"
        ),
        "distinct_literal_encoded_fields": len(literal_encoded_union),
        "distinct_literal_selectors": len(literal_selector_union),
        "distinct_static_selectors": len(static_union),
        "maximum_selector": max(static_union),
        "producers": producers,
    }


def recover_g17_inline_register_records(image: bytes) -> dict[str, object]:
    """Recover register records emitted without the virtual encoder helper.

    Three producers seed their stream with a record and may append a second
    one directly. FastBlit does the same with a computed static selector. CL
    additionally constructs two adjacent records from the low 32 bits of its
    accelerator base; those remain symbolic rather than being misreported as
    static selector constants. Their two descriptor/channel value formulas
    are recovered exactly as structured expressions.
    """

    symbols = macho_symbols(image)
    missing = [name for name in REGISTER_LIST_PRODUCERS.values() if name not in symbols]
    if missing:
        raise ValueError(f"Mach-O is missing register-list producers: {missing}")

    code = {
        label: symbol_code(image, name)[1]
        for label, name in REGISTER_LIST_PRODUCERS.items()
    }
    require_instruction_words_at(
        code["3D"],
        "G17 3D inline register records",
        {
            0x100: 0x0A18014A,  # preserve template bits
            0x104: 0x5282E72B,  # selector 0x1739
            0x108: 0x2A0B014A,
            0x10C: 0xB900A12A,
            0x114: 0x5280002B,  # value one
            0x178: 0x0A180129,
            0x17C: 0x5282FC2B,  # selector 0x17e1
            0x180: 0x2A0B0129,
            0x184: 0xB9000109,
            0x188: 0xF800410A,  # value one at header +4
            0x194: 0x11003129,  # publish one 12-byte record
        },
    )
    require_instruction_words_at(
        code["TA"],
        "G17 TA inline register records",
        {
            0x088: 0x0A0A0129,
            0x08C: 0x5282FC2B,  # selector 0x17e1
            0x090: 0x2A0B0129,
            0x094: 0xB90062A9,
            0x098: 0x52800029,
            0x09C: 0xF80642A9,
            0x0C8: 0x0A0A0129,
            0x0CC: 0x5282FE2A,  # selector 0x17f1
            0x0D0: 0x2A0A0129,
            0x0D4: 0xB9000109,
            0x0DC: 0xF8004109,
            0x0F4: 0x11003129,
        },
    )
    require_instruction_words_at(
        code["FastBlit"],
        "G17 FastBlit inline register records",
        {
            0x06C: 0x120E4D29,  # preserve template and six low control bits
            0x070: 0x5282E72A,  # selector 0x1739
            0x074: 0x2A0A0129,
            0x078: 0xB9000109,
            0x080: 0xF8004109,  # value one
            0x114: 0x5280F21C,  # selector base 0x790
            0x118: 0x72A0003C,  # selector base 0x10790
            0x124: 0x120E4129,  # preserve template bits
            0x128: 0x0B1C0129,  # add static base 0x10790
            0x12C: 0x511E1D29,  # subtract 0x787 -> selector 0x10009
            0x130: 0xB9000D09,
            0x134: 0xF9000916,  # computed blit-control value
            0x140: 0x11003129,
        },
    )
    require_instruction_words_at(
        code["CL"],
        "G17 CL inline register records",
        {
            0x03C: 0xF9400815,  # accelerator base from owner +0x10
            0x090: 0x0A0B0129,
            0x094: 0x5282FC2A,  # selector 0x17e1
            0x098: 0x2A0A0129,
            0x09C: 0xB9004289,
            0x0A4: 0xF8044289,
            0x0D8: 0x0A0B0129,
            0x0DC: 0x5282FE2A,  # selector 0x17f1
            0x0E0: 0x2A0A0129,
            0x0E4: 0xB9000109,
            0x0EC: 0xF8004109,
            0x0B8: 0x91404EAA,  # accelerator base +0x13000
            0x0BC: 0x91080156,  # dynamic selector base +0x200
            0x1330: 0xF9420A69,  # descriptor +0x410
            0x1334: 0xA95B22EA,  # channel words at +0x1b0/+0x1b8
            0x1338: 0xB944B2AB,  # accelerator index at +0x4b0
            0x133C: 0x9276810C,  # channel[0x1b8] & 0x7fffffffc00
            0x1340: 0x528000A8,
            0x1344: 0xAA08018D,  # first value: masked word | 5
            0x134C: 0xF90001CD,  # first value -> command +0x764
            0x1360: 0x8B0B0569,  # index * 3
            0x1364: 0xD375D137,  # then * 2048
            0x1368: 0x8B0C02E9,  # second value: scaled index + masked word
            0x137C: 0x0A0B014A,
            0x1380: 0x0B0A02CA,
            0x1384: 0x1100254A,  # dynamic base +9
            0x1388: 0xB907628A,
            0x139C: 0x0A0B014A,
            0x13A0: 0x0B0A02CA,
            0x13A4: 0x1100054A,  # dynamic base +1
            0x13A8: 0xB9076E8A,
            0x13AC: 0xF903BA89,
            0x13B8: 0x1100314A,
        },
    )

    static_records = {
        "3D": [
            {
                "producer_offset": 0x104,
                "selector": 0x1738,
                "mode": 1,
                "value": 1,
            },
            {
                "producer_offset": 0x17C,
                "selector": 0x17E0,
                "mode": 1,
                "value": 1,
            },
        ],
        "TA": [
            {"producer_offset": 0x08C, "selector": 0x17E0, "mode": 1, "value": 1},
            {"producer_offset": 0x0CC, "selector": 0x17F0, "mode": 1, "value": 1},
        ],
        "FastBlit": [
            {"producer_offset": 0x070, "selector": 0x1738, "mode": 1, "value": 1},
            {
                "producer_offset": 0x128,
                "selector": 0x10008,
                "mode": 1,
                "value_source": "computed_blit_control",
            },
        ],
        "CL": [
            {
                "producer_offset": 0x094,
                "selector": 0x17E0,
                "mode": 1,
                "value": 1,
            },
            {
                "producer_offset": 0x0DC,
                "selector": 0x17F0,
                "mode": 1,
                "value": 1,
            },
        ],
    }
    dynamic_records = {
        "CL": [
            {
                "producer_offset": 0x1380,
                "selector_expression": "low32(accelerator_base + 0x13200) + 0x8",
                "mode": 1,
                "value_expression": {
                    "operation": "orr",
                    "bytes": 8,
                    "immediate": 5,
                    "source": {
                        "operation": "and",
                        "bytes": 8,
                        "mask": 0x7FFFFFFFC00,
                        "source": {
                            "kind": "channel_load",
                            "member": 0x1B8,
                            "bytes": 8,
                        },
                    },
                },
            },
            {
                "producer_offset": 0x13A0,
                "selector_expression": "low32(accelerator_base + 0x13200)",
                "mode": 1,
                "value_expression": {
                    "operation": "add",
                    "bytes": 8,
                    "first": {
                        "operation": "multiply",
                        "bytes": 8,
                        "factor": 0x1800,
                        "source": {
                            "kind": "accelerator_load",
                            "member": 0x4B0,
                            "bytes": 4,
                        },
                    },
                    "second": {
                        "operation": "and",
                        "bytes": 8,
                        "mask": 0x7FFFFFFFC00,
                        "source": {
                            "kind": "channel_load",
                            "member": 0x1B8,
                            "bytes": 8,
                        },
                    },
                },
            },
        ]
    }
    return {
        "static_record_count": sum(len(records) for records in static_records.values()),
        "dynamic_record_count": sum(
            len(records) for records in dynamic_records.values()
        ),
        "all_inline_forms_located": True,
        "all_inline_values_recovered": True,
        "control_flow_complete": False,
        "static_records": static_records,
        "dynamic_records": dynamic_records,
    }


def build_g17_emission_cfg(
    instructions: list[tuple[int, int]], event_offsets: set[int]
) -> dict[str, object]:
    """Collapse a producer CFG to its externally visible record emissions."""

    if not instructions:
        raise ValueError("G17 emission CFG has no instructions")
    index_by_offset = {offset: index for index, (offset, _word) in enumerate(instructions)}
    if len(index_by_offset) != len(instructions):
        raise ValueError("G17 emission CFG has duplicate instruction offsets")
    missing = sorted(event_offsets - index_by_offset.keys())
    if missing:
        raise ValueError(f"G17 emission offsets are not instructions: {missing}")

    def is_break(word: int) -> bool:
        return word & 0xFFE0001F == 0xD4200000

    def is_return(word: int) -> bool:
        return word in (0xD65F03C0, 0xD65F0BFF, 0xD65F0FFF)

    def successors(index: int) -> tuple[int, ...]:
        offset, word = instructions[index]
        target = decode_b_target(offset, word)
        if target is not None:
            if target not in index_by_offset:
                raise ValueError(f"G17 branch at {offset:#x} leaves its producer")
            return (index_by_offset[target],)
        target = decode_local_branch_target(offset, word)
        if target is not None:
            if target not in index_by_offset:
                raise ValueError(f"G17 branch at {offset:#x} leaves its producer")
            following = index + 1
            return (
                (index_by_offset[target], following)
                if following < len(instructions)
                else (index_by_offset[target],)
            )
        if is_break(word):  # authenticated-call failure
            return ()
        if is_return(word):
            return ()
        return (index + 1,) if index + 1 < len(instructions) else ()

    reachable: set[int] = set()
    pending = [0]
    while pending:
        index = pending.pop()
        if index in reachable:
            continue
        reachable.add(index)
        pending.extend(successors(index))
    unreachable_events = sorted(
        offset for offset in event_offsets if index_by_offset[offset] not in reachable
    )
    if unreachable_events:
        raise ValueError(f"G17 emission events are unreachable: {unreachable_events}")

    def next_events(
        start_indices: tuple[int, ...]
    ) -> tuple[list[int], bool, bool]:
        found: set[int] = set()
        returns = False
        traps = False
        seen: set[int] = set()
        pending = list(start_indices)
        while pending:
            index = pending.pop()
            if index in seen:
                continue
            seen.add(index)
            offset = instructions[index][0]
            if offset in event_offsets:
                found.add(offset)
                continue
            following = successors(index)
            if not following:
                word = instructions[index][1]
                traps |= is_break(word)
                returns |= is_return(word) or index + 1 == len(instructions)
            else:
                pending.extend(following)
        return sorted(found), returns, traps

    first, empty_return_path, pre_emission_trap = next_events((0,))
    nodes = []
    loop_edges = 0
    for offset in sorted(event_offsets):
        index = index_by_offset[offset]
        following, returns, traps = next_events(successors(index))
        loop_edges += sum(target <= offset for target in following)
        nodes.append(
            {
                "producer_offset": offset,
                "next": following,
                "can_return": returns,
                "can_trap": traps,
            }
        )
    decisions = []
    trap_guard_count = 0
    for index in sorted(reachable):
        offset, word = instructions[index]
        target = decode_local_branch_target(offset, word)
        if target is None or decode_b_target(offset, word) is not None:
            continue
        branch_successors = successors(index)
        if len(branch_successors) != 2:
            continue
        taken = next_events((branch_successors[0],))
        fallthrough = next_events((branch_successors[1],))
        if taken == fallthrough:
            continue

        def trap_only(outcome: tuple[list[int], bool, bool]) -> bool:
            return not outcome[0] and not outcome[1] and outcome[2]

        if trap_only(taken) or trap_only(fallthrough):
            trap_guard_count += 1
            continue
        flags = decode_conditional_branch(offset, word)
        compare_zero = decode_compare_zero_branch(offset, word)
        test_bit = decode_test_bit_branch(offset, word)
        decoded = compare_zero if compare_zero is not None else test_bit
        decisions.append(
            {
                "producer_offset": offset,
                "target_offset": target,
                "kind": "flags" if flags is not None else "compare_zero"
                if compare_zero is not None
                else "test_bit",
                "condition": flags[1] if flags is not None else decoded["condition"],
                "register": None if flags is not None else decoded["register"],
                "taken": {
                    "next": taken[0],
                    "can_return": taken[1],
                },
                "fallthrough": {
                    "next": fallthrough[0],
                    "can_return": fallthrough[1],
                },
            }
        )
    return {
        "entry": first,
        "empty_return_path": empty_return_path,
        "pre_emission_trap": pre_emission_trap,
        "event_count": len(event_offsets),
        "edge_count": sum(len(node["next"]) for node in nodes),
        "loop_edge_count": loop_edges,
        "semantic_decision_count": len(decisions),
        "trap_guard_count": trap_guard_count,
        "decisions": decisions,
        "nodes": nodes,
    }


def recover_g17_register_emission_cfg(
    image: bytes,
    selectors: dict[str, object],
    inline_records: dict[str, object],
) -> dict[str, object]:
    """Recover possible register-record ordering from all producer branches."""

    result: dict[str, object] = {}
    static_records = inline_records["static_records"]
    dynamic_records = inline_records["dynamic_records"]
    for label, name in REGISTER_LIST_PRODUCERS.items():
        _address, code = symbol_code(image, name)
        calls = selectors["producers"][label]["encoder_entries"]
        events = {int(entry["producer_offset"]) for entry in calls}
        events.update(
            int(entry["producer_offset"])
            for entry in static_records.get(label, [])
        )
        events.update(
            int(entry["producer_offset"])
            for entry in dynamic_records.get(label, [])
        )
        graph = build_g17_emission_cfg(list(words(code)), events)
        instructions = list(words(code))
        index_by_offset = {
            offset: index for index, (offset, _word) in enumerate(instructions)
        }
        recovered_predicates = 0
        for decision in graph["decisions"]:
            offset = int(decision["producer_offset"])
            index = index_by_offset[offset]
            word = instructions[index][1]
            flags = decode_conditional_branch(offset, word)
            compare_zero = decode_compare_zero_branch(offset, word)
            test_bit = decode_test_bit_branch(offset, word)
            if flags is not None:
                predicate = trace_g17_condition_expression(
                    instructions, index, 0, frozenset()
                )
            else:
                decoded = compare_zero if compare_zero is not None else test_bit
                source = trace_g17_value_expression(
                    instructions, index, int(decoded["register"])
                )
                if source is None and label == "3D" and offset == 0xF8:
                    require_instruction_words_at(
                        code,
                        "G17 3D register-list pass induction",
                        {
                            0x030: 0xD2800017,  # pass = 0
                            0x0BC: 0x910006F7,  # pass++
                            0x0C4: 0xF10012FF,  # four passes
                            0x0C8: 0x540134A0,
                            0x0F8: 0x35000317,  # first pass differs
                        },
                    )
                    source = {
                        "kind": "loop_induction",
                        "name": "pass",
                        "initial": 0,
                        "step": 1,
                        "limit": 4,
                        "bytes": 4,
                    }
                predicate = (
                    None
                    if source is None
                    else {
                        "kind": "condition",
                        "producer_offset": offset,
                        "operation": "compare_zero"
                        if compare_zero is not None
                        else "test_bit",
                        "bytes": decoded["bytes"],
                        **({"bit": decoded["bit"]} if test_bit is not None else {}),
                        "source": source,
                    }
                )
            if predicate is not None:
                decision["predicate"] = predicate
                recovered_predicates += 1
        graph["recovered_predicate_count"] = recovered_predicates
        graph["predicates_complete"] = (
            recovered_predicates == graph["semantic_decision_count"]
        )
        graph["virtual_call_events"] = len(calls)
        graph["inline_events"] = len(events) - len(calls)
        result[label] = graph
    return {
        "machine_order_complete": True,
        "predicate_expressions_complete": all(
            graph["predicates_complete"] for graph in result.values()
        ),
        "producers": result,
    }


def recover_g17_3d_register_lists(image: bytes) -> dict[str, object]:
    """Recover the register-list layout of the 0x2240-byte 3D command.

    generateRegisterListFor3D runs four passes with a 0x720 stride.  Pass i
    holds its stream at i * 0x720 + 0xa0 and its metadata -- GPU address, then
    16-bit entry and byte counters -- at i * 0x720 + 0x7a0, so each pass owns
    0x700 stream bytes and the next pass begins 0x14 bytes after the previous
    metadata ends.  The function's exit block confirms the spacing by copying
    all four metadata records into the descriptor as a 0x10-byte array.
    """

    symbols = macho_symbols(image)
    if GENERATE_REGISTER_LIST_3D not in symbols:
        raise ValueError(f"Mach-O is missing {GENERATE_REGISTER_LIST_3D}")

    _address, code = symbol_code(image, GENERATE_REGISTER_LIST_3D)
    require_instruction_words_at(
        code,
        "G17 3D register-list framing",
        {
            0x034: 0x528000D8,  # preserved selector-template mask, low half
            0x038: 0x72BFFF98,  # and high half: 0xfffc0006
            0x0C0: 0x911C82B5,  # sub-block stride 0x720
            0x0C4: 0xF10012FF,  # four sub-blocks
            0x0CC: 0x8B150329,  # command + sub-block offset
            0x0D0: 0x91028128,  # stream starts at sub-block +0xa0
            0x0D4: 0xB907A93F,  # entry counter cleared at +0x7a8
            0x0D8: 0xF942226A,  # command GPU base from descriptor +0x440
            0x0E4: 0xF903D12A,  # stream GPU address -> sub-block +0x7a0
            0x100: 0x0A18014A,  # selector template preserved
            0x188: 0xF800410A,  # 64-bit value follows the selector word
            0x190: 0x794E1509,  # byte length at stream +0x70a
            0x194: 0x11003129,  # advanced by 12
            0x198: 0x790E1509,
            0x19C: 0x794E110A,  # entry count at stream +0x708
            0x1A0: 0x1100054A,  # advanced by one
            0x1A4: 0x790E110A,
        },
    )

    # The exit block publishes every pass's metadata into the descriptor,
    # which pins both the stride and the per-pass metadata offset.
    require_instruction_words_at(
        code,
        "G17 3D register-list publication",
        {
            0x2560: 0x794F532A,  # pass 0 entry count
            0x2564: 0x7901032A,  # staged at command +0x80
            0x275C: 0x7910627F,
            0x2760: 0xF9041E7F,
            0x2764: 0x91210268,  # descriptor summary array at +0x840
            0x277C: 0xF943D329,  # pass 0 GPU address at command +0x7a0
            0x2780: 0xF9041669,  # -> descriptor +0x828
            0x2784: 0x79410329,
            0x2788: 0x79106269,  # -> descriptor +0x830
            0x278C: 0x913B2329,  # pass 1 metadata at command +0xec8
            0x2790: 0x5280006A,  # three further passes
            0x2794: 0xF85F812B,
            0x2798: 0xF81F810B,
            0x279C: 0x7940012B,
            0x27A0: 0x7801050B,  # 0x10-byte summary stride
            0x27A4: 0x911C8129,  # 0x720 command stride
        },
    )

    stream_offset = 0xA0
    metadata_offset = 0x7A0
    stride = 0x720
    passes = 4
    stream_bytes = metadata_offset - stream_offset
    metadata_bytes = 0xC
    # Each pass must end before the next one's stream begins.
    if stream_offset + stream_bytes + metadata_bytes > stride + stream_offset:
        raise ValueError("G17 3D register-list passes overlap")
    if (passes - 1) * stride + metadata_offset + metadata_bytes > G17_COMMAND_3D_BYTES:
        raise ValueError("G17 3D register-list metadata falls outside the command")

    return {
        "command_bytes": G17_COMMAND_3D_BYTES,
        "passes": passes,
        "stride": stride,
        "stream_offset": stream_offset,
        "stream_bytes": stream_bytes,
        "gpu_address_offset": metadata_offset,
        "entry_count_offset": 0x7A8,
        "byte_length_offset": 0x7AA,
        "entry_bytes": 0xC,
        "inter_pass_gap": stride + stream_offset - (metadata_offset + metadata_bytes),
        "selector_template_mask": 0xFFFC0006,
        "gpu_base_descriptor_member": 0x440,
        "descriptor_summary": {
            "offset": 0x828,
            "stride": 0x10,
            "records": passes,
            "gpu_address": 0x00,
            "entry_count": 0x08,
        },
        "record_framing_resolved": True,
        "producer": GENERATE_REGISTER_LIST_3D,
    }


def recover_g17_channel_command_pools(image: bytes) -> dict[str, object]:
    """Recover the channel-command pools and their per-type command sizes.

    Every work command is taken from a preallocated slot ring.  Each ring is a
    0x40-byte control block in the firmware object, the slot size is one entry
    of the table configurePoolElementSizes installs, and each
    requestChannelCommandX binds one specific block.  Together these give the
    exact byte size of every channel command type.
    """

    symbols = macho_symbols(image)
    required = (CONFIGURE_POOL_ELEMENT_SIZES, BASE_ALLOC_FIRMWARE_DATA)
    missing = [name for name in required if name not in symbols]
    if missing:
        raise ValueError(f"Mach-O is missing channel-command pool symbols: {missing}")

    # The size table is a fixed sequence of literals and vector loads.
    sizes_address, sizes_code = symbol_code(image, CONFIGURE_POOL_ELEMENT_SIZES)
    if len(sizes_code) != 0x54:
        raise ValueError(f"unexpected pool size producer length {len(sizes_code):#x}")
    require_instruction_words_at(
        sizes_code,
        "G17 channel-command pool sizes",
        {
            0x04: 0x52813808,  # mov w8, #0x9c0
            0x08: 0xF9010C08,  # -> firmware +0x218
            0x1C: 0xAD110400,  # -> firmware +0x220
            0x20: 0x52800808,  # mov w8, #0x40
            0x24: 0xF9012408,  # -> firmware +0x248
            0x30: 0x3D809400,  # -> firmware +0x250
            0x34: 0x52801009,  # mov w9, #0x80
            0x38: 0x4E080D00,  # both halves 0x40
            0x3C: 0xF9013409,  # -> firmware +0x268
            0x48: 0xAD138400,  # -> firmware +0x270 and +0x280
            0x4C: 0xF9014808,  # -> firmware +0x290
        },
    )
    element_sizes = {0x218: 0x9C0, 0x248: 0x40, 0x268: 0x80, 0x270: 0x40, 0x278: 0x40, 0x290: 0x40}
    for load_offset, member in ((0x10, 0x220), (0x18, 0x230), (0x2C, 0x250), (0x44, 0x280)):
        adrp = decode_adrp(
            sizes_address + load_offset - 4,
            struct.unpack_from("<I", sizes_code, load_offset - 4)[0],
        )
        load = decode_ldr_q(struct.unpack_from("<I", sizes_code, load_offset)[0])
        if adrp is None or load is None:
            raise ValueError("pool size table is no longer a literal vector load")
        _register, page = adrp
        _destination, _base, immediate = load
        offset = virtual_to_file(image, page + immediate)
        low, high = struct.unpack_from("<QQ", image, offset)
        element_sizes[member] = low
        element_sizes[member + 8] = high

    # allocFirmwareData binds each block to one entry of that table.
    _address, alloc_code = symbol_code(image, BASE_ALLOC_FIRMWARE_DATA)
    alloc_words = list(words(alloc_code))
    pool_sizes: dict[int, int] = {}
    for index, (_offset, word) in enumerate(alloc_words):
        materialized = decode_movz_w(word)
        if materialized is None or materialized[0] != 8:
            continue
        base = materialized[1]
        if not 0x1600 <= base <= 0x1A00:
            continue
        for _next_offset, following in alloc_words[index : index + 8]:
            load = decode_ldr_x(following)
            if load is not None and load[0] == 9 and load[1] == 19:
                pool_sizes[base] = load[2]
                break
    # The TA block is bound before the loop body and uses the leading literal.
    pool_sizes.setdefault(TA_COMMAND_POOL, 0x218)
    if len(pool_sizes) < 13:
        raise ValueError(f"recovered only {len(pool_sizes)} channel-command pools")

    # Each request function opens with the in-use byte array at block +0x18.
    commands = {}
    for name in sorted(symbols):
        if "requestChannelCommand" not in name:
            continue
        _address, request_code = symbol_code(image, name)
        block = None
        for _offset, word in list(words(request_code))[:12]:
            load = decode_ldr_x(word)
            if load is not None and load[0] == 8 and load[1] == 0:
                block = load[2] - 0x18
                break
        if block is None:
            raise ValueError(f"{name} does not open with its pool block")
        member = pool_sizes.get(block)
        if member is None or member not in element_sizes:
            raise ValueError(f"{name} binds an unknown pool block {block:#x}")
        label = name.split("requestChannelCommand")[1].split("E")[0]
        commands[label] = {
            "block": block,
            "size_member": member,
            "command_bytes": element_sizes[member],
        }

    # The allocator itself is identical for every type; check one in full.
    _address, barrier_code = symbol_code(image, REQUEST_CHANNEL_COMMAND_BARRIER)
    require_instruction_words_at(
        barrier_code,
        "G17 channel-command slot allocation",
        {
            0x014: 0xF94BB008,  # in-use bytes at block +0x18
            0x024: 0xF94BC000,  # block lock at +0x38
            0x02C: 0xB9577268,  # slot count at +0x28
            0x034: 0xB9577669,  # slot cursor at +0x2c
            0x078: 0xB9576A68,  # element size at +0x20
            0x07C: 0x1B087EB6,  # slot * element size
            0x0AC: 0x8B160008,  # GPU base + offset
            0x0B0: 0xF9000288,  # -> caller's output
            0x0DC: 0xB9177668,  # advanced cursor
            0x0EC: 0xF94BAE68,  # CPU base at block +0x10
            0x0F0: 0x8B160114,  # returned CPU pointer
        },
    )

    return {
        "block_bytes": 0x40,
        "block_layout": {
            "resource": 0x08,
            "cpu_base": 0x10,
            "in_use_bytes": 0x18,
            "element_bytes": 0x20,
            "slot_count": 0x28,
            "slot_cursor": 0x2C,
            "exhausted": 0x30,
            "lock": 0x38,
        },
        "gpu_address_vtable_slot": 0x158,
        "size_producer": CONFIGURE_POOL_ELEMENT_SIZES,
        "commands": commands,
    }


def recover_g17_command_pool_backing(image: bytes) -> dict[str, object]:
    """Recover capacity selection and backing geometry for work-command pools.

    allocFirmwareData selects a device-provided capacity or the PI-300
    fallback, triples it for TA/3D/FastBlit/CL, and passes that requested count
    to the shared PoolClass::createBacking implementation.  createBacking
    rounds element_bytes * requested_slots to the kernel page size and exposes
    every complete element in that allocation, so page padding can add slots.
    """

    symbols = macho_symbols(image)
    required = (
        BASE_ALLOC_FIRMWARE_DATA,
        COMMAND_POOL_CREATE_BACKING,
        PI300_CONFIGURE_DEVICE,
        G17_CONFIGURE_DEVICE,
    )
    missing = [name for name in required if name not in symbols]
    if missing:
        raise ValueError(f"Mach-O is missing command-pool backing symbols: {missing}")

    _address, pi_configure = symbol_code(image, PI300_CONFIGURE_DEVICE)
    require_instruction_words_at(
        pi_configure,
        "G17 command-pool fallback capacity",
        {
            0x88: 0x52800A09,  # mov w9, #0x50
            0x8C: 0xB9071A69,  # str w9, [x19, #0x718]
        },
    )

    # The G17 override lives in the generation-specific tail of the
    # accelerator.  A zero override selects the PI-300 fallback; the selected
    # value is also cached at +0x728 by configureDevice.
    _address, g17_configure = symbol_code(image, G17_CONFIGURE_DEVICE)
    require_instruction_words_at(
        g17_configure,
        "G17 command-pool capacity selection",
        {
            0x30: 0x91404408,  # accelerator +0x11000
            0x34: 0x91058114,  # +0x160 -> override at +0x11160
            0xA8: 0xB9400288,  # load override
            0xAC: 0x35000048,  # keep it when nonzero
            0xB0: 0xB9471A68,  # otherwise load fallback at +0x718
            0xC4: 0xB9072A68,  # cache selected capacity at +0x728
        },
    )

    alloc_address, alloc = symbol_code(image, BASE_ALLOC_FIRMWARE_DATA)
    require_instruction_words_at(
        alloc,
        "G17 work-command pool count",
        {
            0x38: 0xF9414C01,  # accelerator at firmware +0x298
            0x3C: 0x91404428,  # accelerator +0x11000
            0x40: 0x91058108,  # +0x160 -> capacity override
            0x44: 0xB9400119,  # load override into w25
            0x48: 0x35000059,  # keep it when nonzero
            0x4C: 0xB9471839,  # otherwise fallback at +0x718
            0x300: 0x0B190734,  # w20 = w25 + (w25 << 1)
            0x580: 0x5282D108,  # 3D pool block +0x1688
            0x594: 0xAA1403E1,  # requested count = w20
            0x5A0: 0x5282D908,  # FastBlit pool block +0x16c8
            0x5B4: 0xAA1403E1,  # requested count = w20
            0x5C0: 0x5282E108,  # CL pool block +0x1708
            0x5D4: 0xAA1403E1,  # requested count = w20
        },
    )
    create_address = symbols[COMMAND_POOL_CREATE_BACKING]
    for call_offset in (0x598, 0x5B8, 0x5D8):
        call = struct.unpack_from("<I", alloc, call_offset)[0]
        if decode_bl_target(alloc_address + call_offset, call) != create_address:
            raise ValueError(
                f"G17 work-command pool call at {call_offset:#x} no longer "
                "targets the shared createBacking"
            )

    _address, create = symbol_code(image, COMMAND_POOL_CREATE_BACKING)
    require_instruction_words_at(
        create,
        "G17 command-pool backing geometry",
        {
            0x28: 0xF9000002,  # accelerator at block +0x00
            0x2C: 0xF9401017,  # element bytes at block +0x20
            0x68: 0x2A1503E8,  # requested count
            0x6C: 0x52800029,  # one page unit
            0x70: 0x1AD82129,  # page bytes = 1 << page_shift
            0x78: 0x9B0826E8,  # count * element bytes + one page
            0x7C: 0xD1000508,  # page-rounding bias
            0x80: 0xCB0903E9,  # page-alignment mask
            0x84: 0x8A090115,  # rounded backing bytes
            0x29C: 0xF9000674,  # backing resource at block +0x08
            0x2C8: 0xF9000A60,  # CPU base at block +0x10
            0x2D0: 0xF9401268,  # element bytes at block +0x20
            0x2D4: 0x9AC80AA8,  # slots = backing bytes / element bytes
            0x2D8: 0xB9002A68,  # slot count at block +0x28
            0x2E4: 0xF9000E60,  # in-use bytes at block +0x18
        },
    )

    fallback_capacity = 0x50
    multiplier = 3
    return {
        "capacity_override_member": 0x11160,
        "capacity_fallback_member": 0x718,
        "selected_capacity_member": 0x728,
        "fallback_capacity": fallback_capacity,
        "work_pool_multiplier": multiplier,
        "fallback_work_requested_slots": fallback_capacity * multiplier,
        "backing_alignment": "1 << kernel_page_shift",
        "backing_bytes_formula":
            "align_up(element_bytes * requested_slots, kernel_page_bytes)",
        "slot_count_formula": "backing_bytes / element_bytes",
        "in_use_bytes_formula": "slot_count",
        "producer": COMMAND_POOL_CREATE_BACKING,
    }


def recover_g17_3d_command_reclamation(image: bytes) -> dict[str, object]:
    """Recover how a completed 3D descriptor releases its command slot.

    The descriptor retains the command's CPU pointer.  complete subtracts the
    pool CPU base, divides by the element size, decrements the matching in-use
    byte under the pool lock, and finally clears the retained pointer.  This
    independently ties the 3D completion path to the 0x1688 pool block.
    """

    symbols = macho_symbols(image)
    if COMPLETE_COMMAND_3D not in symbols:
        raise ValueError(f"Mach-O is missing {COMPLETE_COMMAND_3D}")

    _address, code = symbol_code(image, COMPLETE_COMMAND_3D)
    require_instruction_words_at(
        code,
        "G17 3D command reclamation",
        {
            0x16C: 0xF9421E68,  # retained command CPU pointer at descriptor +0x438
            0x1F4: 0xF942D934,  # firmware object at channel +0x5b0
            0x1F8: 0xB9569A89,  # pool CPU base at block +0x10
            0x1FC: 0x4B090108,  # command CPU - pool CPU base
            0x200: 0xF94B5689,  # element size at block +0x20
            0x204: 0x9AC90915,  # slot = byte offset / element size
            0x208: 0xF94B6280,  # pool lock at block +0x38
            0x210: 0xF94B5288,  # in-use bytes at block +0x18
            0x214: 0x8B150109,  # address of the selected in-use byte
            0x218: 0x39400129,  # load in-use byte
            0x21C: 0x34000069,  # leave an already-clear slot clear
            0x220: 0x51000529,  # decrement by one
            0x224: 0x38356909,  # store selected in-use byte
            0x238: 0xF9021E7F,  # clear descriptor +0x438 after unlock
        },
    )

    block = 0x1688
    return {
        "descriptor_command_cpu_member": 0x438,
        "pool_block": block,
        "pool_cpu_base_member": block + 0x10,
        "pool_in_use_member": block + 0x18,
        "pool_element_bytes_member": block + 0x20,
        "pool_exhausted_member": block + 0x30,
        "pool_lock_member": block + 0x38,
        "slot_formula": "(command_cpu - pool_cpu_base) / element_bytes",
        "decrement_if_nonzero": True,
        "clear_descriptor_pointer": True,
        "producer": COMPLETE_COMMAND_3D,
    }


def recover_g17_queue_device_inputs(
    driver: bytes, iogpu: bytes
) -> dict[str, object]:
    """Resolve the last two channel/scheduler inputs to producible values.

    AGXCommandQueue never writes +0x490 or +0x498 itself: it inherits both from
    IOGPUCommandQueue::init, which stores the owning IOGPUDevice and copies the
    device's +0x60.  IOGPUDevice::init sets that word to the creating process
    ID, and the AGXShared device byte the scheduler element copies is the app
    GPU role.  Both are values Vinix can produce for its own clients.
    """

    iogpu_symbols = macho_symbols(iogpu)
    driver_symbols = macho_symbols(driver)
    if IOGPU_COMMAND_QUEUE_INIT not in iogpu_symbols:
        raise ValueError("IOGPUFamily is missing IOGPUCommandQueue::init")
    if IOGPU_DEVICE_INIT not in iogpu_symbols:
        raise ValueError("IOGPUFamily is missing IOGPUDevice::init")
    for name in (AGX_SHARED_INIT, AGX_SHARED_SET_APP_GPU_ROLE):
        if name not in driver_symbols:
            raise ValueError(f"AGXG17X is missing {name}")

    _address, queue_code = symbol_code(iogpu, IOGPU_COMMAND_QUEUE_INIT)
    require_instruction_words_at(
        queue_code,
        "IOGPU command-queue device binding",
        {
            0x0F8: 0xF9024A74,  # IOGPUDevice -> queue +0x490
            0x0FC: 0xB9406288,  # device +0x60
            0x100: 0xB9049A68,  # -> queue +0x498
        },
    )

    device_address, device_code = symbol_code(iogpu, IOGPU_DEVICE_INIT)
    require_instruction_words_at(
        device_code,
        "IOGPU device process identifier",
        {
            0x0E4: 0xB9006260,  # proc_pid result -> device +0x60
            0x108: 0xB9006260,  # same store on the 32-bit path
        },
    )
    pids = set()
    for offset in (0xE0, 0x104):
        target = decode_bl_target(
            device_address + offset, struct.unpack_from("<I", device_code, offset)[0]
        )
        if target is None:
            raise ValueError("IOGPUDevice::init no longer calls a direct producer")
        pids.add(target)
    if len(pids) != 1:
        raise ValueError("IOGPUDevice::init uses two different producers for +0x60")

    _address, shared_code = symbol_code(driver, AGX_SHARED_INIT)
    require_instruction_words_at(
        shared_code,
        "AGXShared default app GPU role",
        {
            0x100: 0x52800048,  # mov w8, #2
            0x104: 0x39048268,  # -> device byte +0x120
        },
    )
    _address, role_code = symbol_code(driver, AGX_SHARED_SET_APP_GPU_ROLE)
    require_instruction_words_at(
        role_code,
        "AGXShared app GPU role bound",
        {
            0x2EC: 0x7100111F,  # cmp w8, #4
            0x2F0: 0x54000D22,  # reject 4 and above
            0x2F8: 0x39048118,  # accepted role -> device byte +0x120
        },
    )

    return {
        "queue_device_member": 0x490,
        "queue_value_member": 0x498,
        "device_class": "AGXShared",
        "process_id": {
            "device_member": 0x60,
            "channel_state_offset": 0x48,
            "producer": "proc_pid(get_bsdtask_info(task))",
            "producer_address": sorted(pids)[0],
        },
        "app_gpu_role": {
            "device_member": 0x120,
            "bytes": 1,
            "scheduler_state_offset": 0x26,
            "default": 2,
            "maximum": 3,
            "setter": AGX_SHARED_SET_APP_GPU_ROLE,
        },
    }


def recover_g17_channel_runtime_resources(
    driver: bytes, iogpu: bytes
) -> dict[str, object]:
    """Recover the per-command-queue timestamp and channel ring inputs.

    The channel pool geometry alone does not say how much of each element is
    live, nor what state +0x10 points at.  This follows the configured queue
    count through AGXCommandQueue and IOGPUWorkQueue, and follows the shared
    timestamp allocation which every concrete channel receives as x5.
    """

    driver_symbols = macho_symbols(driver)
    iogpu_symbols = macho_symbols(iogpu)
    driver_required = (
        PI300_CONFIGURE_DEVICE,
        BASE_ALLOC_FIRMWARE_DATA,
        AGX_COMMAND_QUEUE_INIT,
        AGX_WORK_QUEUE_INIT,
        ALLOCATE_3D_WORK_QUEUE,
        ALLOCATE_CL_WORK_QUEUE,
        TIMESTAMP_QUEUE_INIT,
        RESET_TIMESTAMP_QUEUE,
    )
    missing = [name for name in driver_required if name not in driver_symbols]
    if missing:
        raise ValueError(f"AGXG17X is missing channel runtime symbols: {missing}")
    if IOGPU_WORK_QUEUE_INIT not in iogpu_symbols:
        raise ValueError("IOGPUFamily is missing IOGPUWorkQueue::init")

    # PI_300 installs 80 as the device default.  Both firmware-pool setup and
    # command-queue construction prefer the optional device override at
    # accelerator +0x11160 and otherwise read this +0x718 default.
    _address, configure_code = symbol_code(driver, PI300_CONFIGURE_DEVICE)
    require_instruction_words_at(
        configure_code,
        "G17 configured work-queue default",
        {
            0x084: 0xF9436A68,
            0x088: 0x52800A09,  # mov w9, #80
            0x08C: 0xB9071A69,  # -> accelerator +0x718
        },
    )
    _address, alloc_code = symbol_code(driver, BASE_ALLOC_FIRMWARE_DATA)
    require_instruction_words_at(
        alloc_code,
        "G17 timestamp-state pool",
        {
            0x038: 0xF9414C01,  # accelerator at firmware +0x298
            0x03C: 0x91404428,
            0x040: 0x91058108,
            0x044: 0xB9400119,  # optional +0x11160 queue-count override
            0x048: 0x35000059,
            0x04C: 0xB9471839,  # fallback accelerator +0x718
            0x050: 0x52825108,  # timestamp stack at firmware +0x1288
            0x054: 0x8B080274,
            0x074: 0xAA1403E0,
            0x078: 0x52800302,  # 0x18-byte timestamp state
            0x07C: 0x52800124,  # alignment shift 9
            0x080: 0x52800005,  # uncached
            0x084: 0xD2800006,  # no owning task
            0x088: 0x52800007,  # no shrinking
        },
    )

    _address, queue_code = symbol_code(driver, AGX_COMMAND_QUEUE_INIT)
    require_instruction_words_at(
        queue_code,
        "G17 command-queue ring request",
        {
            0x0C8: 0xF9429E68,  # accelerator at queue +0x538
            0x0CC: 0x91404509,
            0x0D0: 0x91058129,
            0x0D4: 0xB9400129,  # optional accelerator +0x11160 override
            0x0D8: 0x35000049,
            0x0DC: 0xB9471909,  # fallback accelerator +0x718
            0x0E0: 0xB9088269,  # -> command queue +0x880
        },
    )
    _address, work_code = symbol_code(driver, AGX_WORK_QUEUE_INIT)
    require_instruction_words_at(
        work_code,
        "G17 AGX work-queue base initialization",
        {
            0x02C: 0xF940A908,
            0x030: 0xAA0903F1,
            0x034: 0xF2E76F11,
            0x038: 0xD73F0911,  # forwards x3 to IOGPUWorkQueue::init
        },
    )
    _address, iogpu_work_code = symbol_code(iogpu, IOGPU_WORK_QUEUE_INIT)
    require_instruction_words_at(
        iogpu_work_code,
        "IOGPU work-queue ring request",
        {
            0x018: 0xAA0303F7,  # preserve x3
            0x050: 0xF9002268,
            0x054: 0xB9005677,  # -> work queue +0x54
        },
    )

    # Render and compute work queues both pass command queue +0x880 as x3.
    # Their concrete channels then receive timestamp_queue->gpu_address (+0x28)
    # as x5.  The render path has two branches because TA can be allocated
    # lazily, but both load the same timestamp address.
    _address, work_3d_code = symbol_code(driver, ALLOCATE_3D_WORK_QUEUE)
    require_instruction_words_at(
        work_3d_code,
        "G17 render work-channel inputs",
        {
            0x058: 0xF9429E81,
            0x05C: 0xB9488283,  # command queue +0x880 -> x3
            0x0A0: 0xF9434288,  # timestamp object at queue +0x680
            0x0A4: 0xF9401515,  # timestamp GPU VA at object +0x28
            0x12C: 0xAA1503E5,  # -> channel initializer x5
            0x1A8: 0xF9434288,
            0x1AC: 0xF9401501,  # same address for lazy TA allocation
        },
    )
    _address, work_cl_code = symbol_code(driver, ALLOCATE_CL_WORK_QUEUE)
    require_instruction_words_at(
        work_cl_code,
        "G17 compute work-channel inputs",
        {
            0x04C: 0xF9429E81,
            0x050: 0xB9488283,  # command queue +0x880 -> x3
            0x08C: 0xF9434288,  # timestamp object at queue +0x680
            0x090: 0xF9401515,  # timestamp GPU VA at object +0x28
            0x118: 0xAA1503E5,  # -> channel initializer x5
        },
    )

    # The timestamp object keeps CPU and GPU addresses separately.  The GPU
    # address is the channel context cookie; reset writes that address back
    # into the shared element at +0x08, while all CPU stores use object +0x20.
    _address, timestamp_code = symbol_code(driver, TIMESTAMP_QUEUE_INIT)
    if len(timestamp_code) != 0x490:
        raise ValueError(f"unexpected timestamp-queue init size {len(timestamp_code):#x}")
    require_instruction_words_at(
        timestamp_code,
        "G17 timestamp-queue mappings",
        {
            0x058: 0xB9003A7F,  # update mode starts disabled at object +0x38
            0x05C: 0xF942DA95,  # firmware object at accelerator +0x5b0
            0x064: 0x8B0802B4,  # timestamp stack at +0x1288
            0x24C: 0x8B160008,
            0x250: 0xF9001668,  # GPU VA -> timestamp object +0x28
            0x2C0: 0x8B160008,
            0x2D4: 0xF9001268,  # CPU VA -> timestamp object +0x20
        },
    )
    _address, reset_code = symbol_code(driver, RESET_TIMESTAMP_QUEUE)
    if len(reset_code) != 0x38:
        raise ValueError(f"unexpected timestamp reset size {len(reset_code):#x}")
    require_instruction_words_at(
        reset_code,
        "G17 timestamp-state reset",
        {
            0x004: 0xF9401008,  # CPU VA at object +0x20
            0x008: 0xA9007D1F,
            0x00C: 0xF900091F,  # clear all 0x18 bytes
            0x018: 0xA9422009,  # CPU/GPU VA pair at +0x20/+0x28
            0x01C: 0xF9000528,  # self GPU VA -> shared +0x08
            0x020: 0xB9403808,  # update mode at object +0x38
            0x024: 0x7100091F,
            0x028: 0x1A9F17E8,
            0x02C: 0xF9401009,
            0x030: 0x29027D28,  # mode flag and zero -> +0x10/+0x14
        },
    )

    configured_queues = 80
    pointers_per_queue = 16
    maximum_queue_request = 0x80
    ring_entries = min(configured_queues, maximum_queue_request) * pointers_per_queue
    return {
        "configured_queues": {
            "default": configured_queues,
            "accelerator_default_member": 0x718,
            "accelerator_override_member": 0x11160,
            "command_queue_member": 0x880,
        },
        "work_queue": {
            "request_argument": 3,
            "request_member": 0x54,
        },
        "channel_ring": {
            "maximum_queue_request": maximum_queue_request,
            "pointers_per_queue": pointers_per_queue,
            "default_entries": ring_entries,
            "pointer_bytes": 8,
            "default_pointer_bytes": ring_entries * 8,
        },
        "timestamp_state": {
            "firmware_stack_member": 0x1288,
            "bytes": 0x18,
            "alignment_shift": 9,
            "caching": 0,
            "object_cpu_member": 0x20,
            "object_gpu_member": 0x28,
            "self_gpu_address_offset": 0x08,
            "update_mode_flag_offset": 0x10,
            "initial_update_mode": 0,
            "context_cookie_state_offset": 0x10,
            "command_queue_owner_member": 0x680,
        },
    }


def recover_g17_scheduler_state(image: bytes) -> dict[str, object]:
    """Recover the per-queue _AGFISchedulerState element and its pool.

    Channel state +0x9c is copied from command queue +0x8b8, which
    AGXCommandQueue::allocateSchedulerState fills with the GPU address of one
    element of the AGFICmdQueueSchedState firmware pool.  That pool, its
    element size and the element's initial content are all fixed, so the whole
    path is recoverable even though the queue object is not modelled yet.
    """

    symbols = macho_symbols(image)
    required = (
        ARM_ALLOC_FIRMWARE_DATA,
        SCHEDULER_STATE_STACK_INIT,
        ALLOCATE_SCHEDULER_STATE,
        SCHEDULER_STATE_STACK_VTABLE,
    )
    missing = [name for name in required if name not in symbols]
    if missing:
        raise ValueError(f"Mach-O is missing G17 scheduler-state symbols: {missing}")

    # allocFirmwareData binds the pool through the stack's own vtable, so the
    # element size is the literal it passes rather than a stored constant.
    init_target = recover_vtable_target(
        image, SCHEDULER_STATE_STACK_VTABLE, SCHEDULER_STATE_STACK_INIT_SLOT
    )
    if init_target != symbols[SCHEDULER_STATE_STACK_INIT]:
        raise ValueError(f"unexpected scheduler-state stack init {init_target:#x}")

    alloc_address, alloc_code = symbol_code(image, ARM_ALLOC_FIRMWARE_DATA)
    require_instruction_words_at(
        alloc_code,
        "G17 scheduler-state pool binding",
        {
            0xD54: 0xF9414E61,  # accelerator at firmware +0x298
            0xD58: 0x52829908,  # mov w8, #0x14c8
            0xD5C: 0x8B080274,  # stack object at ASC +0x14c8
            0xD7C: 0xAA1403E0,
            0xD80: 0x52800802,  # element size 0x40
            0xD84: 0x52800124,  # alignment shift 9
            0xD88: 0x52800025,  # caching option 1
            0xD8C: 0xD2800006,  # no owning task
            0xD90: 0x52800007,  # shrink mode 0
        },
    )
    adrp = decode_adrp(
        alloc_address + 0xD74, struct.unpack_from("<I", alloc_code, 0xD74)[0]
    )
    add = decode_add_immediate(struct.unpack_from("<I", alloc_code, 0xD78)[0])
    if adrp is None or add is None:
        raise ValueError("scheduler-state pool no longer names itself")
    _register, page = adrp
    _destination, _source, immediate = add
    name_offset = virtual_to_file(image, page + immediate)
    pool_name = image[name_offset : image.index(b"\0", name_offset)].decode()
    if pool_name != "AGFICmdQueueSchedState":
        raise ValueError(f"unexpected scheduler-state pool name {pool_name!r}")

    # The stack derives its block geometry from the element size and page size.
    _address, stack_code = symbol_code(image, SCHEDULER_STATE_STACK_INIT)
    require_instruction_words_at(
        stack_code,
        "G17 scheduler-state pool geometry",
        {
            0x20: 0xAA0203F5,  # element size argument
            0x68: 0xF9005275,  # -> stack +0xa0
            0x7C: 0x8B150509,  # page bytes + 2 * element size
            0x80: 0xD1000529,
            0x84: 0xCB0803E8,
            0x88: 0x8A080128,  # rounded down to a page multiple
            0x8C: 0xF9002E68,  # -> stack +0x58
            0x90: 0x9AD50908,  # block bytes / element size
            0x94: 0xB9006268,  # -> stack +0x60
        },
    )

    # allocateSchedulerState publishes four members of the owning queue.
    _address, queue_code = symbol_code(image, ALLOCATE_SCHEDULER_STATE)
    require_instruction_words_at(
        queue_code,
        "G17 scheduler-state queue publication",
        {
            0x028: 0xF9429C08,  # accelerator at queue +0x538
            0x02C: 0xF942D915,  # ASC at accelerator +0x5b0
            0x030: 0x52829908,
            0x0EC: 0xB9552ABB,  # elements per block
            0x0F0: 0x1ADB0B1C,  # block index
            0x144: 0xF9045660,  # owning resource -> queue +0x8a8
            0x1E8: 0x1B1BE389,  # index within the block
            0x1EC: 0x9B097ED6,  # * element size
            0x220: 0x8B160008,
            0x224: 0xF9045E68,  # GPU address -> queue +0x8b8
            0x2A8: 0xF9045268,  # CPU address -> queue +0x8a0
            0x348: 0xB908B278,  # allocation index -> queue +0x8b0
        },
    )

    # The element is zeroed through +0x37 and then given its fixed defaults.
    require_instruction_words_at(
        queue_code,
        "G17 scheduler-state initial content",
        {
            0x3BC: 0xF9445268,
            0x3C0: 0xF900191F,  # zero +0x30..+0x37
            0x3C8: 0xAD008100,  # zero +0x10..+0x2f
            0x3CC: 0x3D800100,  # zero +0x00..+0x0f
            0x3D0: 0xF9445268,
            0x3D4: 0x529FFFE9,
            0x3D8: 0x79000109,  # 0xffff -> +0x00
            0x3DC: 0x52800020,
            0x3E0: 0x39001500,  # 1 -> +0x05
            0x3E4: 0x52801FE9,
            0x3E8: 0x3900CD09,  # 0xff -> +0x33
            0x3EC: 0xB802211F,  # 0 -> +0x22
            0x3F0: 0xF9424A69,  # queue +0x490
            0x3F4: 0x39448129,  # its byte +0x120
            0x3F8: 0x39009909,  # -> +0x26
        },
    )

    return {
        "pool_name": pool_name,
        "element_bytes": 0x40,
        "alignment_shift": 9,
        "caching_option": 1,
        "shrink_mode": 0,
        "stack_host_member": 0x14C8,
        "stack_element_size_member": 0xA0,
        "stack_block_bytes_member": 0x58,
        "stack_elements_per_block_member": 0x60,
        "block_bytes": "(page_bytes + 2 * element_bytes - 1) & -page_bytes",
        "queue_accelerator_member": 0x538,
        "accelerator_asc_member": 0x5B0,
        "queue_bindings": {
            "cpu_address": 0x8A0,
            "resource": 0x8A8,
            "allocation_index": 0x8B0,
            "gpu_address": 0x8B8,
        },
        "zeroed_bytes": 0x38,
        "initial_fields": [
            {"offset": 0x00, "bytes": 2, "value": 0xFFFF},
            {"offset": 0x05, "bytes": 1, "value": 1},
            {"offset": 0x22, "bytes": 4, "value": 0},
            {"offset": 0x26, "bytes": 1, "source": {"queue_member": 0x490, "offset": 0x120}},
            {"offset": 0x33, "bytes": 1, "value": 0xFF},
        ],
    }


def recover_g17_channel_state_sources(image: bytes, reset_code: bytes) -> dict[str, object]:
    """Trace the two channel-state inputs that resetChannelState only copies.

    The reset path reads both from its own object, so they look opaque there.
    AGXChannel::init seeds them from the owning AGXCommandQueue, at +0x498 and
    +0x8b8, which makes them queue properties rather than platform constants.
    setKickChannelQos is checked here too, but only to keep it separated: it
    writes +0x4c/+0x50 of the runtime object at firmware member 0x380, not of
    a channel, so it is unrelated to channel state +0x48 despite the offset.
    """

    symbols = macho_symbols(image)
    required = (CHANNEL_INIT, SET_KICK_CHANNEL_QOS)
    missing = [name for name in required if name not in symbols]
    if missing:
        raise ValueError(f"Mach-O is missing G17 channel-source symbols: {missing}")

    # resetChannelState copies channel +0x4c to state +0x48, channel +0xf8 to
    # state +0x9c, and channel +0x54 to the uncached ring-entry count.
    require_instruction_words_at(
        reset_code,
        "G17 channel-state input copies",
        {
            0x05C: 0xB9404C08,
            0x064: 0xB9004928,
            0x078: 0xF9407C0A,
            0x07C: 0xF809C12A,
            0x088: 0xB940540B,
            0x08C: 0xB900614B,
        },
    )

    # The QoS setter writes the runtime object at firmware member 0x380, which
    # already models +0x4c/+0x50 as its kick-channel QoS pair. It is asserted
    # here so that the identical offset is not mistaken for the channel input
    # above if either producer changes.
    _address, qos_code = symbol_code(image, SET_KICK_CHANNEL_QOS)
    if len(qos_code) != 0x28:
        raise ValueError(f"unexpected kick-channel QoS setter size {len(qos_code):#x}")
    require_instruction_words_at(
        qos_code,
        "G17 kick-channel QoS setter",
        {
            0x04: 0xF9466808,  # runtime object at firmware +0xcd0
            0x08: 0x5298E509,  # mov w9, #0xc728
            0x0C: 0x8B090108,
            0x10: 0x52800029,  # publish the QoS update flag
            0x14: 0xB9000109,
            0x18: 0xF941C008,  # runtime object at firmware +0x380
            0x1C: 0xB9005101,  # first QoS word -> channel +0x50
            0x20: 0xB9004D02,  # second QoS word -> channel +0x4c
        },
    )

    # AGXChannel::init seeds both members from the owning command queue and
    # derives the ring-entry count from its requested depth.
    _address, init_code = symbol_code(image, CHANNEL_INIT)
    require_instruction_words_at(
        init_code,
        "G17 channel input seeding",
        {
            0x068: 0xB9449AA8,  # command queue +0x498
            0x078: 0xF9445EA9,  # command queue +0x8b8
            0x07C: 0xF9007E69,  # -> channel +0xf8
            0x094: 0x12800009,
            0x098: 0x29092269,  # -0x1 and the QoS seed -> channel +0x48/+0x4c
            0x5B8: 0x52801009,  # mov w9, #0x80
            0x5BC: 0x710202DF,
            0x5C0: 0x1A8932C9,  # min(requested, 0x80)
            0x5C4: 0x531C6D29,  # * 16
            0x5C8: 0xB9005669,  # -> channel +0x54
        },
    )

    return {
        "queue_value": {
            "state_offset": 0x48,
            "channel_member": 0x4C,
            "queue_seed_member": 0x498,
        },
        "queue_address": {
            "state_offset": 0x9C,
            "channel_member": 0xF8,
            "queue_seed_member": 0x8B8,
        },
        "runtime_kick_channel_qos": {
            "setter": SET_KICK_CHANNEL_QOS,
            "runtime_host_member": 0x380,
            "runtime_members": [0x50, 0x4C],
            "update_flag_runtime_offset": 0xC728,
            "distinct_from_channel_state": True,
        },
        "ring_entries": {
            "control_offset": 0x60,
            "channel_member": 0x54,
            "maximum_request": 0x80,
            "multiplier": 16,
        },
    }


def recover_g17_channel_data_master_types(image: bytes) -> dict[str, object]:
    """Recover the AGFI data-master type supplied by each channel subclass.

    Each concrete G17 channel initializer is a small wrapper around the base
    AGXChannel::init method.  The seventh argument is materialized in w6
    immediately before that direct call, so this does not depend on a guessed
    C++ enum declaration or on type names found in strings.
    """

    symbols = macho_symbols(image)
    required = (CHANNEL_INIT, *G17_CHANNEL_INITIALIZERS.values())
    missing = [name for name in required if name not in symbols]
    if missing:
        raise ValueError(f"Mach-O is missing G17 channel initializer symbols: {missing}")

    base_address = symbols[CHANNEL_INIT]
    recovered = {}
    for kind, symbol in G17_CHANNEL_INITIALIZERS.items():
        address, code = symbol_code(image, symbol)
        decoded = list(words(code))
        matches = []
        for index, (offset, word) in enumerate(decoded[:-1]):
            move = decode_movz_w(word)
            next_offset, next_word = decoded[index + 1]
            if (
                move is not None
                and move[0] == 6
                and next_offset == offset + 4
                and decode_bl_target(address + next_offset, next_word) == base_address
            ):
                matches.append(move[1])
        if len(matches) != 1:
            raise ValueError(
                f"expected one G17 {kind} data-master initializer call, "
                f"found {len(matches)}"
            )
        recovered[kind] = {
            "initializer": symbol,
            "data_master_type": matches[0],
        }

    observed = {kind: item["data_master_type"] for kind, item in recovered.items()}
    expected = {"TA": 0, "3D": 1, "CL": 2}
    if observed != expected:
        raise ValueError(f"unexpected G17 channel data-master types: {observed}")
    return {
        "base_initializer": CHANNEL_INIT,
        "subclasses": recovered,
    }


def recover_g17_channel_identity(driver: bytes, iogpu: bytes) -> dict[str, object]:
    """Recover the work-channel ID inherited from IOGPUChannel.

    AGXChannel::init calls the IOGPUChannel base initializer through its
    imported vtable with the accelerator from command-queue member +0x538 and
    a fixed second argument of 0x80.  The separately symbolized IOGPUFamily
    implementation stores that second argument at channel +0x18, the same
    field consumed by the G17 outer-ring encoder.
    """

    driver_symbols = macho_symbols(driver)
    iogpu_symbols = macho_symbols(iogpu)
    if CHANNEL_INIT not in driver_symbols:
        raise ValueError("driver is missing AGXChannel::init")
    if IOGPU_CHANNEL_INIT not in iogpu_symbols:
        raise ValueError("IOGPUFamily is missing IOGPUChannel::init")

    _address, channel_code = symbol_code(driver, CHANNEL_INIT)
    require_instruction_words_at(
        channel_code,
        "G17 IOGPU channel initialization",
        {
            0x048: 0x91052109,  # imported IOGPUChannel vtable slot +0x148
            0x04C: 0xF940A508,
            0x050: 0xF9429C21,  # command queue +0x538 -> base owner
            0x054: 0x52801002,  # fixed channel ID 0x80
            0x060: 0xD73F0911,  # authenticated indirect base-init call
        },
    )
    _address, base_code = symbol_code(iogpu, IOGPU_CHANNEL_INIT)
    require_instruction_words_at(
        base_code,
        "IOGPU channel identity store",
        {
            0x018: 0xAA0203F4,  # preserve the second init argument
            0x040: 0xF9000A75,  # owner -> channel +0x10
            0x044: 0xB9001A74,  # ID -> channel +0x18
        },
    )
    return {
        "value": 0x80,
        "channel_member": 0x18,
        "bytes": 4,
        "base_owner": {"command_queue_member": 0x538, "channel_member": 0x10},
        "base_initializer": IOGPU_CHANNEL_INIT,
        "outer_entry_bytes": 1,
    }


def recover_g17_handoff(code: bytes) -> dict[str, object]:
    magic = find_materialized_constant(code, INTERFACE_MAGIC)
    if magic:
        raise ValueError("UAT handoff unexpectedly contains the firmware interface magic")
    ppl_magic = 0x4B1D000000000002
    materialized = find_materialized_constant(code, ppl_magic)
    if len(materialized) != 1:
        raise ValueError(f"expected one uPPL magic sequence, found {len(materialized)}")
    magic_start, magic_end, magic_register = materialized[0]
    stores = set()
    for _offset, word in words(code[magic_end:]):
        store = decode_str_unsigned(word)
        if store is not None:
            stores.add(store)
    expected = {
        (magic_register, 0, 0x000, 8),
        (31, 0, 0x010, 1),
        (31, 0, 0x011, 1),
        (31, 0, 0x014, 4),
        (9, 0, 0x018, 4),
        (8, 0, 0x638, 1),
        (31, 0, 0x640, 8),
    }
    if not expected.issubset(stores):
        missing = sorted(expected - stores, key=lambda item: item[2])
        raise ValueError(f"missing G17 handoff stores: {missing}")

    clear_loop = struct.pack(
        "<6I",
        0x52800829,  # mov w9, #65
        0xB81F011F,  # stur wzr, [x8, #-16]
        0xF81F811F,  # stur xzr, [x8, #-8]
        0xF801851F,  # str xzr, [x8], #24
        0xF1000529,  # subs x9, x9, #1
        0x54FFFF81,  # b.ne to the first store
    )
    if code.find(clear_loop, magic_start) < 0:
        raise ValueError("G17 handoff does not contain the 65-record clear loop")
    return {
        "bytes": 0x648,
        "magic": ppl_magic,
        "magic_offset": 0,
        "firmware_magic_offset": 8,
        "lock_offsets": [0x10, 0x11],
        "turn_offset": 0x14,
        "current_slot_offset": 0x18,
        "current_slot_initial": 0xFFFFFFFF,
        "flush_offset": 0x20,
        "flush_records": 65,
        "flush_record_bytes": 0x18,
        "mismatch_flag_offset": 0x638,
        "tail_offset": 0x640,
    }


def recover_g17_boot_transport(
    notify_code: bytes, receive_code: bytes, boot_code: bytes
) -> dict[str, object]:
    """Recover the dual-role AKF bootstrap and ready-message contract.

    G17C does not expose one interchangeable INIT acknowledgment.  The host
    owns two role records 0x38 bytes apart, boots both transports, and sends a
    distinct bootstrap-root address when each role reports that it started.
    The ready message is decoded from a six-bit type field and acknowledged
    through both role transports under a one-shot guard.
    """

    require_instruction_words_at(
        notify_code,
        "G17 firmware-start notification",
        {
            0x018: 0x52833B08,  # role records start at host +0x19d8
            0x01C: 0x8B080008,
            0x020: 0x52800709,  # one role record is 0x38 bytes
            0x024: 0x9BA97C29,
            0x02C: 0x8B29C114,
            0x03C: 0x52800035,
            0x040: 0x3900A295,  # role started byte at record +0x28
            0x048: 0xF9001A80,  # start timestamp at record +0x30
            0x0FC: 0xF9400288,  # role transport at record +0
            0x100: 0xD2E01021,  # 0x81 << 48
            0x104: 0xB340AC01,  # insert root IOVA bits 43:0
            0x12C: 0x91226202,  # transport send-message slot 0x898
            0x130: 0xF9444E10,
        },
    )
    require_instruction_words_at(
        receive_code,
        "G17 AKF message handling",
        {
            0x014: 0xD370D428,  # message[53:48]
            0x018: 0xF100251F,  # ready type 9
            0x020: 0xF100091F,  # callback type 2
            0x060: 0x52834908,  # one-shot state at host +0x1a48
            0x068: 0x8B080000,
            0x080: 0xB91A4A7F,  # consume the one-shot state
            0x088: 0xD2E01128,  # 0x89 << 48
            0x08C: 0xF90003E8,
            0x090: 0xF94CEE60,  # role 0 transport at +0x19d8
            0x0A4: 0xD2811611,  # transport send slot 0x8b0
            0x0A8: 0x8B110210,
            0x0AC: 0xF9400208,
            0x0C0: 0xF94D0A60,  # role 1 transport at +0x1a10
            0x0E8: 0x9122C208,
            0x0EC: 0xF9445A09,
        },
    )
    require_instruction_words_at(
        boot_code,
        "G17 dual-role firmware boot",
        {
            0x01C: 0x91400415,
            0x020: 0x392802BF,  # clear role 0 started (+0x1a00)
            0x024: 0x3928E2BF,  # clear role 1 started (+0x1a38)
            0x028: 0x392B16BF,  # clear shared ready flag (+0x1ac5)
            0x02C: 0xF94CEC00,  # boot role 0 transport (+0x19d8)
            0x030: 0xF94CFE61,  # with role 0 root mapping (+0x19f8)
            0x044: 0xD2811111,  # transport boot slot 0x888
            0x048: 0x8B110210,
            0x04C: 0xF9400208,
            0x05C: 0xF94D0A60,  # boot role 1 transport (+0x1a10)
            0x060: 0xF94D1A61,  # with role 1 root mapping (+0x1a30)
            0x088: 0x91222208,
            0x08C: 0xF9444609,
            0x09C: 0x7100029F,  # first transport result
            0x0A0: 0x7A401804,  # second transport result
            0x0A8: 0x396B16A8,  # wait for shared ready flag
        },
    )

    role_base = 0x19D8
    role_stride = 0x38
    return {
        "role_count": 2,
        "role_record_host_member": role_base,
        "role_record_stride": role_stride,
        "transport_member": 0,
        "root_mapping_member": 0x20,
        "started_member": 0x28,
        "start_timestamp_member": 0x30,
        "transport_host_members": [role_base, role_base + role_stride],
        "root_mapping_host_members": [
            role_base + 0x20,
            role_base + role_stride + 0x20,
        ],
        "transport_boot_vtable_slot": 0x888,
        "init_message": 0x81 << 48,
        "init_address_bits": 44,
        "init_send_vtable_slot": 0x898,
        "receive_type_shift": 48,
        "receive_type_bits": 6,
        "callback_type": 2,
        "ready_type": 9,
        "ready_ack_message": 0x89 << 48,
        "ready_ack_guard_host_member": 0x1A48,
        "ready_ack_transport_vtable_slot": 0x8B0,
        "ready_ack_transport_count": 2,
        "shared_ready_flag_host_member": 0x1AC5,
        "requires_both_transport_boots": True,
    }


def g17_callback_interrupt_index(interrupt_count: int) -> int:
    """Apply AGXAccelerator::configureDevice's callback-source selection."""

    if 5 <= interrupt_count <= 8:
        return 4
    if interrupt_count in (1, 4):
        return 0
    raise ValueError(f"unsupported AGX interrupt count {interrupt_count}")


def recover_g17_akf_callback(driver: bytes, kernel: bytes) -> dict[str, object]:
    """Recover the type-2 AKF callback's host interrupt dispatch.

    The callback word carries no event body. Apple indexes the accelerator's
    IOFilterInterruptEventSource array with a selector chosen from the
    ``interrupts`` property, calls signalInterrupt(), recovers the source's
    interrupt index in the normal action, and forwards that index to
    AGXFirmware::handleEvent(). An eight-interrupt t6050 therefore selects
    index 4, which clears outstanding firmware interrupts and drains the
    role-specific firmware rings.
    """

    driver_symbols = macho_symbols(driver)
    kernel_symbols = macho_symbols(kernel)
    driver_required = (
        RECEIVED_MESSAGE_FROM_AKF,
        ACCELERATOR_START,
        BASE_CONFIGURE_DEVICE,
        ACCELERATOR_HANDLE_INTERRUPT,
        FIRMWARE_HANDLE_EVENT,
        FIRMWARE_DRAIN_EVENT_RING,
        G17_CLEAR_FIRMWARE_INTERRUPTS,
        G17_FIRMWARE_VTABLE,
        "__ZN11AGXFirmware18drainFirmwareRingsEb",
    )
    kernel_required = (
        IOFILTER_INTERRUPT_EVENT_SOURCE_VTABLE,
        IOFILTER_INTERRUPT_EVENT_SOURCE_FACTORY,
        IOFILTER_SIGNAL_INTERRUPT,
        IOINTERRUPT_GET_INDEX,
    )
    for name in driver_required:
        if name not in driver_symbols:
            raise ValueError(f"driver Mach-O has no {name} symbol")
    for name in kernel_required:
        if name not in kernel_symbols:
            raise ValueError(f"kernel Mach-O has no {name} symbol")

    _receive_address, receive_code = symbol_code(driver, RECEIVED_MESSAGE_FROM_AKF)
    start_address, start_code = symbol_code(driver, ACCELERATOR_START)
    _configure_address, configure_code = symbol_code(driver, BASE_CONFIGURE_DEVICE)
    _interrupt_address, interrupt_code = symbol_code(
        driver, ACCELERATOR_HANDLE_INTERRUPT
    )
    event_address, event_code = symbol_code(driver, FIRMWARE_HANDLE_EVENT)

    require_instruction_words_at(
        receive_code,
        "G17 type-2 callback dispatch",
        {
            0x014: 0xD370D428,  # message[53:48]
            0x020: 0xF100091F,  # callback type 2
            0x028: 0xF9414C08,  # firmware +0x298 -> accelerator
            0x02C: 0x395D3109,  # callback selector at accelerator +0x74c
            0x030: 0x8B090D08,  # select one pointer with an 8-byte stride
            0x034: 0xF942E900,  # event-source array at accelerator +0x5d0
            0x048: 0xD2804B11,  # signalInterrupt virtual slot 0x258
            0x04C: 0x8B110210,
            0x050: 0xF9400208,
            0x058: 0xD73F0910,
        },
    )
    require_instruction_words_at(
        start_code,
        "G17 interrupt-event-source construction",
        {
            0x3460: 0x7100051F,  # require at least one interrupt
            0x3468: 0xD2800015,  # interrupt index starts at zero
            0x346C: 0x91174277,  # event-source array starts at +0x5d0
            0x347C: 0x910006B5,  # increment interrupt index
            0x3480: 0x910022F7,  # increment event-source slot
            0x348C: 0xF90002FF,  # clear the selected array slot
            0x35E8: 0xAA1303E0,  # owner
            0x35EC: 0xAA1603E1,  # interrupt action
            0x35F0: 0xAA1003E2,  # interrupt filter
            0x35F4: 0xAA1903E3,  # provider
            0x35F8: 0xAA1503E4,  # interrupt index
            0x3600: 0xF90002E0,  # retain source in the indexed array
        },
    )
    factory_call = struct.unpack_from("<I", start_code, 0x35FC)[0]
    if decode_bl_target(start_address + 0x35FC, factory_call) != kernel_symbols[
        IOFILTER_INTERRUPT_EVENT_SOURCE_FACTORY
    ]:
        raise ValueError("G17 interrupt source is not created by the checked factory")

    require_instruction_words_at(
        configure_code,
        "G17 callback interrupt selection",
        {
            0x9D0: 0x53027C08,  # interrupt property byte count / 4
            0x9D4: 0x51001509,  # first multi-interrupt count is 5
            0x9D8: 0x7100113F,  # counts 5..8 use callback index 4
            0x9E0: 0x52802089,  # selector/flag halfword 0x104
            0x9E4: 0x790E9A69,  # accelerator +0x74c
            0x9F4: 0x7100111F,  # four interrupts use index 0
            0x9FC: 0x7100051F,  # one interrupt also uses index 0
            0xA04: 0x790E9A7F,
            0xA08: 0x391D3A68,  # retain interrupt count at +0x74e
            0xA38: 0xB9075268,  # retain interrupts-valid mask at +0x750
        },
    )
    require_instruction_words_at(
        interrupt_code,
        "G17 interrupt action forwarding",
        {
            0x010: 0xF942D813,  # accelerator +0x5b0 -> firmware
            0x024: 0xD2803D11,  # getIntIndex virtual slot 0x1e8
            0x060: 0x910CA202,  # firmware handleEvent slot 0x328
            0x064: 0xF9419610,
            0x068: 0x12001C01,  # forward the low 8-bit interrupt index
            0x06C: 0xAA1303E0,
        },
    )
    require_instruction_words_at(
        event_code,
        "G17 firmware-ring callback event",
        {
            0x080: 0x7100103F,  # interrupt index 4
            0x084: 0x54000700,  # enters common firmware-ring drain path
            0x174: 0xD2811011,  # clearOutstandingFirmwareInterrupts slot 0x880
            0x178: 0x8B110210,
            0x17C: 0xF9400208,
            0x190: 0x52800021,  # drainFirmwareRings(true)
        },
    )
    drain_branch = struct.unpack_from("<I", event_code, 0x1B8)[0]
    if decode_b_target(event_address + 0x1B8, drain_branch) != driver_symbols[
        "__ZN11AGXFirmware18drainFirmwareRingsEb"
    ]:
        raise ValueError("G17 callback event no longer drains firmware rings")

    kernel_slots = {
        0x1E8: IOINTERRUPT_GET_INDEX,
        0x258: IOFILTER_SIGNAL_INTERRUPT,
    }
    for slot, expected in kernel_slots.items():
        target = recover_vtable_target(
            kernel, IOFILTER_INTERRUPT_EVENT_SOURCE_VTABLE, slot
        )
        if target != kernel_symbols[expected]:
            raise ValueError(
                f"unexpected IOFilterInterruptEventSource slot {slot:#x} target"
            )
    firmware_slots = {
        0x328: FIRMWARE_HANDLE_EVENT,
        0x880: G17_CLEAR_FIRMWARE_INTERRUPTS,
        0x888: FIRMWARE_DRAIN_EVENT_RING,
    }
    for slot, expected in firmware_slots.items():
        target = recover_vtable_target(driver, G17_FIRMWARE_VTABLE, slot)
        if target != driver_symbols[expected]:
            raise ValueError(f"unexpected G17 firmware slot {slot:#x} target")
    _clear_address, clear_code = symbol_code(driver, G17_CLEAR_FIRMWARE_INTERRUPTS)
    if clear_code != struct.pack("<2I", 0xD503245F, 0xD65F03C0):
        raise ValueError("G17 clearOutstandingFirmwareInterrupts is no longer a no-op")

    return {
        "message_type": 2,
        "message_payload_consumed": False,
        "firmware_role_consumed": False,
        "accelerator_host_member": 0x298,
        "callback_selector_member": 0x74C,
        "event_source_array_member": 0x5D0,
        "event_source_stride": 8,
        "signal_interrupt_vtable_slot": 0x258,
        "get_interrupt_index_vtable_slot": 0x1E8,
        "handle_event_vtable_slot": 0x328,
        "interrupt_count_property": "interrupts",
        "interrupt_specifier_bytes": 4,
        "selector_rules": {"1_or_4": 0, "5_through_8": 4},
        "t6050_interrupt_count": 8,
        "t6050_callback_interrupt_index": g17_callback_interrupt_index(8),
        "clear_interrupts_vtable_slot": 0x880,
        "drain_event_ring_vtable_slot": 0x888,
        "drains_both_firmware_roles": True,
    }


def recover_g17_firmware_event_ring(
    driver: bytes, iogpu: bytes
) -> dict[str, object]:
    """Recover the role-local ring consumed by callback interrupt index 4."""

    symbols = macho_symbols(driver)
    iogpu_symbols = macho_symbols(iogpu)
    required = (
        ACCELERATOR_START,
        FIRMWARE_INIT,
        FIRMWARE_DRAIN_EVENT_RING,
        FIRMWARE_DRAIN_EVENT_RING_ROLE,
        FIRMWARE_RING_FETCH,
        G17_FIRMWARE_VTABLE,
        G17_HANDLE_FIRMWARE_CONTROLLER_EVENT,
    )
    for name in required:
        if name not in symbols:
            raise ValueError(f"driver Mach-O has no {name} symbol")
    for name in (
        IOGPU_EVENT_GET_NUM_STAMPS,
        IOGPU_EVENT_SIGNAL_STAMP,
        IOGPU_EVENT_TEST_ALL_STAMPS,
        IOGPU_FENCE_INTERRUPT_OCCURRED,
        IOGPU_FENCE_NOTIFY_CLPC,
        IOGPU_SCHEDULER_SIGNAL_HARDWARE_ERROR,
        IOGPU_SIGNAL_STAMPS_UPDATED,
    ):
        if name not in iogpu_symbols:
            raise ValueError(f"IOGPUFamily Mach-O has no {name} symbol")

    init_address, init_code = symbol_code(driver, FIRMWARE_INIT)
    _wrapper_address, wrapper_code = symbol_code(driver, FIRMWARE_DRAIN_EVENT_RING)
    role_address, role_code = symbol_code(driver, FIRMWARE_DRAIN_EVENT_RING_ROLE)
    _fetch_address, fetch_code = symbol_code(driver, FIRMWARE_RING_FETCH)

    require_instruction_words_at(
        init_code,
        "G17 firmware event-ring validator",
        {
            0x118: 0x9129C275,  # role records start at firmware +0xa70
            0x128: 0x9117C276,  # validators start at firmware +0x5f0
            0x130: 0x52802617,  # role record stride 0x130
            0x190: 0xF9414E6B,  # validator owner is the accelerator
            0x194: 0x5280480A,  # role validator stride 0x240
            0x198: 0x9B0A5B0A,
            0x19C: 0xA949312D,  # event state CPU/GPU pair at role +0x90
            0x1A4: 0xA94B3D2E,  # event entries CPU/GPU pair at role +0xb0
            0x284: 0xF901094B,  # validator +0x210 owner
            0x288: 0x3D808D40,  # validator +0x230 mask/count pair
            0x28C: 0xF9010D4D,  # validator +0x218 state CPU address
            0x290: 0xF901114E,  # validator +0x220 entries CPU address
        },
    )
    mask_count = struct.unpack(
        "<2Q", read_adrp_load(driver, init_address, init_code, 0x168, 0x16C, 16)
    )
    if mask_count != (0x2000FFD3, 0x100):
        raise ValueError(f"unexpected G17 firmware event mask/count {mask_count}")

    require_instruction_words_at(
        wrapper_code,
        "G17 dual-role firmware event drain",
        {
            0x014: 0x52800001,  # drain role 0
            0x018: 0x9400000A,
            0x020: 0x52800021,  # then drain role 1
        },
    )
    require_instruction_words_at(
        role_code,
        "G17 role firmware event drain",
        {
            0x028: 0x0B010C28,  # role * 9
            0x02C: 0x531A6508,  # role * 0x240
            0x030: 0x8B080009,
            0x034: 0xF9440928,  # validator entries CPU address at +0x810
            0x03C: 0x91200134,  # selected validator at role base +0x800
            0x040: 0xF9400689,  # state CPU address at validator +8
            0x044: 0xB940012B,  # shared read index at state +0
            0x048: 0xB9001A8B,  # snapshot read index
            0x04C: 0xB9402129,  # shared write index at state +0x20
            0x050: 0xB9001E89,  # snapshot write index
            0x054: 0xF940168A,  # entry count at validator +0x28
            0x0E8: 0xAA1403E0,
            0x0EC: 0x940054F6,  # fetch one 0x48-byte event entry
        },
    )
    table_page = decode_adrp(
        role_address + 0x104, struct.unpack_from("<I", role_code, 0x104)[0]
    )
    table_add = decode_add_immediate(struct.unpack_from("<I", role_code, 0x108)[0])
    if table_page is None or table_add is None or table_page[0] != table_add[1]:
        raise ValueError("G17 firmware event dispatch table address changed")
    table_address = table_page[1] + table_add[2]
    table_offset = virtual_to_file(driver, table_address)
    dispatch_offsets = struct.unpack_from("<16i", driver, table_offset)
    event_actions = recover_g17_firmware_event_actions(
        driver,
        role_address,
        role_code,
        dispatch_offsets,
        symbols,
        iogpu_symbols,
    )
    require_instruction_words_at(
        role_code,
        "G17 firmware completion event",
        {
            0x368: 0xB94053E8,  # event type at entry +0
            0x36C: 0x7100051F,  # completion event type 1
            0x374: 0x7940CBE8,  # checked halfword at entry +0x14
            0x378: 0x7100611F,  # checked halfword must be below 0x18
            0x384: 0xF84543F7,  # firing bits 0..63 at entry +4
            0x388: 0xF845C3F9,  # firing bits 64..127 at entry +0xc
            0x3B0: 0xF940A300,  # accelerator event machine at +0x140
            0x3B4: 0xAA1603E1,  # bit index
            0x3E0: 0x321B0341,  # second word starts at stamp index 32
            0x468: 0xB9404FE9,  # remember whether any stamp fired
            0x470: 0xB9004FE9,
            0x12A8: 0xB9404FE8,  # no global notification without firing bits
            0x12AC: 0x36000A28,
            0x12B0: 0xF9414E74,  # firmware +0x298 -> accelerator
            0x12B4: 0xF940AA80,  # accelerator fence machine at +0x150
            0x12BC: 0xAA1403E0,
            0x12C4: 0xF940A280,  # accelerator event machine at +0x140
        },
    )
    for call_offset in (0x3BC, 0x3E8, 0x414, 0x440):
        call = struct.unpack_from("<I", role_code, call_offset)[0]
        if decode_bl_target(role_address + call_offset, call) != iogpu_symbols[
            IOGPU_EVENT_SIGNAL_STAMP
        ]:
            raise ValueError("G17 completion event no longer signals every firing bit")
    completion_calls = {
        0x12B8: IOGPU_FENCE_INTERRUPT_OCCURRED,
        0x12C0: IOGPU_SIGNAL_STAMPS_UPDATED,
        0x12C8: IOGPU_EVENT_TEST_ALL_STAMPS,
    }
    for call_offset, expected in completion_calls.items():
        call = struct.unpack_from("<I", role_code, call_offset)[0]
        if decode_bl_target(role_address + call_offset, call) != iogpu_symbols[expected]:
            raise ValueError(f"G17 completion callback no longer calls {expected}")
    require_instruction_words_at(
        fetch_code,
        "G17 firmware event-ring fetch",
        {
            0x010: 0xF9400808,  # entries CPU address at validator +0x10
            0x018: 0x2943240A,  # cached read/write indices at +0x18/+0x1c
            0x024: 0xF9401409,  # entry count at +0x28
            0x030: 0x8B0A0D4A,  # read index * 9
            0x034: 0xD37DF14A,  # then * 8: 0x48-byte entries
            0x050: 0xB9000028,  # first entry word is the event type
            0x0D8: 0xB900442A,  # copy through entry +0x44
            0x0DC: 0xF940100A,  # accepted-event mask at validator +0x20
            0x0E0: 0x9AC8254A,  # select the event-type bit
            0x0E4: 0x3600058A,
            0x0EC: 0x1100054A,  # advance read index
            0x0F0: 0x9AC9094B,  # modulo entry count
            0x0F8: 0xB9001809,  # update cached read index
            0x0FC: 0xD5033BBF,  # publish after consuming the entry
            0x104: 0xF940040A,  # shared state address at validator +8
            0x108: 0xB9000149,  # publish shared read index at state +0
        },
    )

    return {
        "role_count": 2,
        "role_record_host_member": 0xA70,
        "role_record_stride": 0x130,
        "validator_host_member": 0x5F0,
        "validator_role_stride": 0x240,
        "event_validator_member": 0x210,
        "state_auxiliary_index": 0,
        "entries_auxiliary_index": 1,
        "state_bytes": 0x30,
        "state_read_index_offset": 0,
        "state_cfi_index_offset": 0x10,
        "state_write_index_offset": 0x20,
        "entry_bytes": 0x48,
        "entries": mask_count[1],
        "entries_bytes": 0x4800,
        "accepted_event_mask": mask_count[0],
        **event_actions,
        "completion_event": {
            "type": 1,
            "firing_masks_offset": 4,
            "firing_mask_words": 4,
            "firing_stamp_slots": 128,
            "checked_halfword_offset": 0x14,
            "checked_halfword_limit": 0x18,
            "signals_each_firing_stamp": True,
            "signals_stamps_updated": True,
            "tests_all_stamps_after_drain": True,
        },
        "read_index_publish_barrier": "dmb ish",
    }


def recover_g17_firmware_event_actions(
    driver: bytes,
    role_address: int,
    role_code: bytes,
    dispatch_offsets: tuple[int, ...],
    driver_symbols: dict[str, int],
    iogpu_symbols: dict[str, int],
) -> dict[str, object]:
    """Classify only event actions proven by the selected G17 host binaries."""

    if len(dispatch_offsets) != 16:
        raise ValueError("G17 firmware event dispatch table is not 16 entries")
    dispatch_anchor = role_address + 0x110
    drain_loop = role_address + 0xBC
    direct_noop_types = (2, 3, 5, 11)
    if any(
        dispatch_anchor + dispatch_offsets[event_type] != drain_loop
        for event_type in direct_noop_types
    ):
        raise ValueError("G17 firmware event direct host no-op dispatch changed")
    validated_event_types = recover_g17_firmware_event_validators(
        driver, role_address, role_code
    )

    # Type 0 does execute a virtual call, but the selected G17 firmware class
    # resolves that call to a two-instruction no-op. Keep it separate from the
    # jump-table no-ops so the generated accounting explains the distinction.
    if dispatch_anchor + dispatch_offsets[0] != role_address + 0x11C:
        raise ValueError("G17 firmware-controller event dispatch changed")
    require_instruction_words_at(
        role_code,
        "G17 firmware-controller event dispatch",
        {
            0x120: 0xB94053E8,  # event type at entry +0
            0x124: 0x35009B88,  # type 0 required
            0x138: 0xD2810F11,  # firmware vtable slot 0x878
            0x13C: 0x8B110210,
            0x140: 0xF9400208,
            0x144: 0x910143E1,  # complete event entry at stack +0x50
            0x148: 0xAA1303E0,
            0x150: 0xD73F0910,
        },
    )
    controller_target = recover_vtable_target(driver, G17_FIRMWARE_VTABLE, 0x878)
    if controller_target != driver_symbols[G17_HANDLE_FIRMWARE_CONTROLLER_EVENT]:
        raise ValueError("G17 firmware-controller event vtable target changed")
    _controller_address, controller_code = symbol_code(
        driver, G17_HANDLE_FIRMWARE_CONTROLLER_EVENT
    )
    if controller_code != struct.pack("<2I", 0xD503245F, 0xD65F03C0):
        raise ValueError("G17 firmware-controller event handler is no longer a no-op")

    # Type 14 only forwards its unaligned u64 payload to IOGPU's optional CLPC
    # performance-control observers. Vinix has no CLPC policy/observer layer,
    # so consuming this advisory record has no command or fence side effect.
    if dispatch_anchor + dispatch_offsets[14] != role_address + 0x15C:
        raise ValueError("G17 CLPC notification event dispatch changed")
    require_instruction_words_at(
        role_code,
        "G17 CLPC notification event",
        {
            0x160: 0xB94053E8,  # event type at entry +0
            0x164: 0x7100391F,  # event type 14
            0x16C: 0xF84543E1,  # unaligned u64 payload at entry +4
            0x170: 0xF9414E68,  # firmware +0x298 -> accelerator
            0x174: 0xF940A900,  # accelerator +0x150 -> fence machine
        },
    )
    clpc_call = struct.unpack_from("<I", role_code, 0x178)[0]
    if decode_bl_target(role_address + 0x178, clpc_call) != iogpu_symbols[
        IOGPU_FENCE_NOTIFY_CLPC
    ]:
        raise ValueError("G17 CLPC notification target changed")

    # Type 8 is a metrology-aging result sent only to the optional platform
    # reliability monitor retained at firmware +0xfb0. With that service
    # absent, Apple itself returns directly to the drain loop.
    if dispatch_anchor + dispatch_offsets[8] != role_address + 0x290:
        raise ValueError("G17 metrology-aging event dispatch changed")
    require_instruction_words_at(
        role_code,
        "G17 metrology-aging event",
        {
            0x294: 0xB94053E8,  # event type at entry +0
            0x298: 0x7100211F,  # event type 8
            0x2A0: 0xB94057E8,  # u32 result at entry +4
            0x2A4: 0xB81503A8,
            0x2A8: 0xF947DA60,  # optional firmware +0xfb0 service
            0x2AC: 0xB4FFF080,  # absent service returns to the drain loop
            0x2B0: 0x52800048,  # reliability-monitor message type 2
            0x2B4: 0x390283E8,
            0x2C8: 0xD2802811,  # service vtable slot 0x140
            0x2D4: 0x910283E1,
            0x2D8: 0xD102C3A2,
            0x2DC: 0xD2800003,
        },
    )
    start_address, start_code = symbol_code(driver, ACCELERATOR_START)
    require_instruction_words_at(
        start_code,
        "G17 reliability-monitor service binding",
        {
            0x2CA4: 0xB0FF41A1,
            0x2CA8: 0x91378021,
            0x2CAC: 0xAA1603E0,
            0x2CB4: 0xF942DA68,  # accelerator +0x5b0 -> firmware
            0x2CB8: 0xF907D900,  # retain service at firmware +0xfb0
        },
    )
    reliability_service = read_adrp_add_cstring(
        driver, start_address, start_code, 0x2CA4, 0x2CA8
    )
    if reliability_service != "function-reliability_monitor":
        raise ValueError("G17 metrology-aging reliability service changed")

    # Type 4 is the firmware's GPU-restart record. Apple validates its stamp
    # slot and ultimately requests a hardware-error restart from IOGPU's
    # scheduler. Vinix has no equivalent recovery engine, so its safe current
    # policy is to stop callback processing and transition the GPU to error.
    if dispatch_anchor + dispatch_offsets[4] != role_address + 0x180:
        raise ValueError("G17 GPU-restart event dispatch changed")
    require_instruction_words_at(
        role_code,
        "G17 GPU-restart event",
        {
            0x184: 0xB94053E8,  # event type at entry +0
            0x188: 0x7100111F,  # event type 4
            0x190: 0xB9405FF6,  # signed stamp slot at entry +0xc
            0x194: 0xF9400288,
            0x198: 0xF940A100,  # accelerator event machine at +0x140
            0x1CC: 0xD2803A11,  # firmware validation vtable slot 0x1d0
            0x1D8: 0x910143E9,
            0x1DC: 0xB27E0121,  # pass event payload at entry +4
            0x27C: 0xF940AD20,  # accelerator scheduler at +0x158
            0x280: 0x52800021,  # eRestartRequest = 1
        },
    )
    stamp_count_call = struct.unpack_from("<I", role_code, 0x19C)[0]
    if decode_bl_target(role_address + 0x19C, stamp_count_call) != iogpu_symbols[
        IOGPU_EVENT_GET_NUM_STAMPS
    ]:
        raise ValueError("G17 GPU-restart stamp-count target changed")
    restart_call = struct.unpack_from("<I", role_code, 0x284)[0]
    if decode_bl_target(role_address + 0x284, restart_call) != iogpu_symbols[
        IOGPU_SCHEDULER_SIGNAL_HARDWARE_ERROR
    ]:
        raise ValueError("G17 GPU-restart scheduler target changed")

    # Type 7 is a channel error. Apple's recovery path is much larger, but
    # these leading checks establish the complete fixed header that Vinix
    # must validate before taking its conservative whole-GPU failure path.
    if dispatch_anchor + dispatch_offsets[7] != role_address + 0x590:
        raise ValueError("G17 channel-error event dispatch changed")
    require_instruction_words_at(
        role_code,
        "G17 channel-error event",
        {
            0x594: 0xB94053E8,  # event type at entry +0
            0x598: 0x71001D1F,  # event type 7
            0x5A0: 0xB94057E8,  # channel-error subtype at entry +4
            0x5A4: 0x7100151F,  # subtype below 5
            0x5AC: 0xB9405BE8,  # data-master type at entry +8
            0x5B0: 0x71000D1F,  # data-master type below 3
            0x5B8: 0xB9405FF6,  # signed stamp slot at entry +0xc
            0x5BC: 0xF9400288,
            0x5C0: 0xF940A100,  # accelerator event machine at +0x140
        },
    )
    channel_stamp_count_call = struct.unpack_from("<I", role_code, 0x5C4)[0]
    if decode_bl_target(
        role_address + 0x5C4, channel_stamp_count_call
    ) != iogpu_symbols[IOGPU_EVENT_GET_NUM_STAMPS]:
        raise ValueError("G17 channel-error stamp-count target changed")

    accepted_types = [
        event_type
        for event_type in range(32)
        if 0x2000FFD3 & (1 << event_type)
    ]
    accepted_direct_noops = [
        event_type for event_type in (*direct_noop_types, 29) if event_type in accepted_types
    ]
    rejected_noop_slots = [
        event_type for event_type in direct_noop_types if event_type not in accepted_types
    ]
    effective_noops = [0, *accepted_direct_noops]
    implemented = {*effective_noops, 1, 4, 7, 8, 14}
    return {
        "jump_table_function_offsets": {
            str(event_type): dispatch_anchor + offset - role_address
            for event_type, offset in enumerate(dispatch_offsets)
        },
        "jump_table_host_noop_event_types": list(direct_noop_types),
        # Types 2, 3 and 5 have no-op jump-table slots but cannot pass the
        # selected validator mask. Type 11 can, and type 29 is accepted above
        # the table range before returning directly to the drain loop.
        "validator_rejected_noop_event_types": rejected_noop_slots,
        "direct_host_noop_event_types": accepted_direct_noops,
        "resolved_host_noop_events": [
            {
                "type": 0,
                "dispatch": "firmware_vtable",
                "vtable_slot": 0x878,
                "target": G17_HANDLE_FIRMWARE_CONTROLLER_EVENT,
                "implementation": "bti_c_ret",
            }
        ],
        "host_noop_event_types": effective_noops,
        "validated_event_types": validated_event_types,
        "fatal_events": [
            {
                "type": 4,
                "record": "AGFIFirmwareEventHWRecovery",
                "stamp_slot_offset": 0xC,
                "invalid_stamp_slot": -1,
                "host_action": "IOGPUScheduler::signalHardwareError",
                "restart_request": 1,
                "vinix_policy": "stop_gpu_without_recovery_engine",
            },
            {
                "type": 7,
                "record": "AGFIChannelErrorEventArgs",
                "subtype_offset": 4,
                "subtype_limit": 5,
                "data_master_offset": 8,
                "data_master_limit": 3,
                "stamp_slot_offset": 0xC,
                "invalid_stamp_slot": -1,
                "host_action": "AGXFirmware::handleChannelErrorEvent",
                "vinix_policy": "stop_gpu_without_channel_recovery",
            },
        ],
        "advisory_events": [
            {
                "type": 8,
                "record": "AGFIFirmwareEventMetrologyAging",
                "payload_offset": 4,
                "payload_bytes": 4,
                "host_action": "function-reliability_monitor",
                "host_action_optional": True,
                "vinix_policy": "consume_without_reliability_monitor",
            },
            {
                "type": 14,
                "record": "AGFIFirmwareEventRTCompletionInfo",
                "payload_offset": 4,
                "payload_bytes": 8,
                "host_action": "IOGPUFenceMachine::notifyCLPCIOPerfControl",
                "vinix_policy": "consume_without_clpc_observers",
            }
        ],
        "unimplemented_action_event_types": [
            event_type for event_type in accepted_types if event_type not in implemented
        ],
    }


def recover_g17_firmware_event_validators(
    driver: bytes, role_address: int, role_code: bytes
) -> dict[str, object]:
    """Recover Apple's internal record and enum names for typed event arms."""

    recovered: dict[str, object] = {}
    prefix = (
        "const RET *AGXFirmwareRingValidator::validateType("
        "const AGFIFirmwareEventRingEntry *) const "
    )
    for event_type, (reference_offset, record, event_name) in (
        G17_FIRMWARE_EVENT_VALIDATORS.items()
    ):
        actual = read_adrp_add_cstring(
            driver,
            role_address,
            role_code,
            reference_offset,
            reference_offset + 4,
        )
        expected = (
            f"{prefix}[RET = {record}, FWET1 = {event_name}, "
            "FWET2 = kAGFIFirmwareEventNone]"
        )
        if actual != expected:
            raise ValueError(
                f"G17 firmware event type {event_type} validator identity changed"
            )
        recovered[str(event_type)] = {"record": record, "enum": event_name}
    return recovered


def recover_g17_rtbuddy_endpoints(
    read_code: bytes,
    send_code: bytes,
    matched_code: bytes,
    enable_code: bytes,
    received_code: bytes,
) -> dict[str, object]:
    """Recover the endpoint objects used by the G17 RTBuddy wrapper."""

    require_instruction_words_at(
        matched_code,
        "G17 RTBuddy endpoint matching",
        {
            0x01C: 0xB9408828,  # RTBuddyEndpointService endpoint ID at +0x88
            0x020: 0x7100851F,  # endpoint 0x21
            0x028: 0x7100811F,  # endpoint 0x20
            0x030: 0xF9009674,  # endpoint 0x20 object -> host +0x128
            0x100: 0xF9009A74,  # endpoint 0x21 object -> host +0x130
        },
    )
    require_instruction_words_at(
        read_code,
        "G17 RTBuddy message receive",
        {
            0x00C: 0xF9409400,  # read exclusively through endpoint 0x20 object
            0x010: 0x52800002,
        },
    )
    require_instruction_words_at(
        send_code,
        "G17 RTBuddy message send",
        {
            0x008: 0xF9409400,  # send exclusively through endpoint 0x20 object
            0x028: 0xD2803D11,  # RTBuddy endpoint send slot 0x1e8
            0x02C: 0x8B110210,
            0x030: 0xF9400208,
            0x03C: 0xD2800002,
            0x040: 0x52800023,
        },
    )
    require_instruction_words_at(
        enable_code,
        "G17 RTBuddy endpoint enable",
        {
            0x014: 0xF9409400,  # endpoint 0x20 object
            0x028: 0xD2802E11,  # endpoint enable slot 0x170
            0x02C: 0x8B110210,
            0x030: 0xF9400208,
            0x03C: 0xF9409A60,  # endpoint 0x21 object
            0x064: 0x9105C208,
            0x068: 0xF940BA09,
            0x078: 0xF940BA60,  # AGXArmFirmware owner at host +0x170
            0x07C: 0xB9412261,  # firmware role at host +0x120
        },
    )
    require_instruction_words_at(
        received_code,
        "G17 RTBuddy receive forwarding",
        {
            0x004: 0xF940B808,  # AGXArmFirmware owner at host +0x170
            0x008: 0xB9412002,  # firmware role at host +0x120
        },
    )

    return {
        "message_endpoint": 0x20,
        "doorbell_endpoint": 0x21,
        "endpoint_service_id_member": 0x88,
        "message_endpoint_host_member": 0x128,
        "doorbell_endpoint_host_member": 0x130,
        "endpoint_enable_vtable_slot": 0x170,
        "message_send_vtable_slot": 0x1E8,
        "firmware_role_host_member": 0x120,
        "arm_firmware_host_member": 0x170,
        "receive_forwards_role": True,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--driver", type=Path, default=Path("build/kext/g17c/AGXG17X.macho")
    )
    parser.add_argument(
        "--kernel", type=Path, default=Path("build/kext/g17c/kernel.macho")
    )
    parser.add_argument(
        "--firmware", type=Path, default=Path("build/firmware/g17c/armfw.bin")
    )
    parser.add_argument(
        "--iogpu", type=Path, default=Path("build/kext/g17c/iokit.IOGPUFamily.macho")
    )
    parser.add_argument(
        "--rtbuddy",
        type=Path,
        default=Path("build/kext/g17c/AGXFirmwareKextG17XRTBuddy.macho"),
    )
    args = parser.parse_args()
    try:
        driver = args.driver.read_bytes()
        kernel = args.kernel.read_bytes()
        firmware = args.firmware.read_bytes()
        iogpu = args.iogpu.read_bytes()
        rtbuddy = args.rtbuddy.read_bytes()
        driver_uuid = macho_uuid(driver)
        firmware_uuid = macho_uuid(firmware)
        rtbuddy_uuid = macho_uuid(rtbuddy)
        if driver_uuid != DRIVER_UUID:
            raise ValueError(f"unsupported AGXG17X UUID {driver_uuid}")
        if firmware_uuid != FIRMWARE_UUID:
            raise ValueError(f"unsupported G17 firmware UUID {firmware_uuid}")
        if rtbuddy_uuid != RTBUDDY_UUID:
            raise ValueError(f"unsupported G17 RTBuddy UUID {rtbuddy_uuid}")
        function_address, function = symbol_code(driver, INIT_FIRMWARE_DATA)
        driver_root = recover_driver_root(function)
        driver_root["function"] = INIT_FIRMWARE_DATA
        driver_root["function_address"] = function_address
        accelerator = recover_driver_accelerator_layouts(driver)
        init_sequence_provider = recover_g17_init_sequence_provider(driver)
        _address, handoff_code = symbol_code(driver, INIT_UAT_HANDOFF)
        handoff = recover_g17_handoff(handoff_code)
        _address, arm_allocation_code = symbol_code(driver, ALLOC_ARM_FIRMWARE_DATA)
        _address, prepare_data_code = symbol_code(driver, PREPARE_FIRMWARE_DATA)
        _address, complete_data_code = symbol_code(driver, COMPLETE_FIRMWARE_DATA)
        _address, prepare_code = symbol_code(driver, PREPARE_FIRMWARE_BOOT)
        _address, notify_started_code = symbol_code(driver, NOTIFY_FIRMWARE_STARTED)
        _address, received_akf_code = symbol_code(driver, RECEIVED_MESSAGE_FROM_AKF)
        _address, boot_firmware_code = symbol_code(driver, BOOT_FIRMWARE)
        boot_transport = recover_g17_boot_transport(
            notify_started_code, received_akf_code, boot_firmware_code
        )
        boot_transport["callback_dispatch"] = recover_g17_akf_callback(
            driver, kernel
        )
        boot_transport["callback_dispatch"]["firmware_event_ring"] = (
            recover_g17_firmware_event_ring(driver, iogpu)
        )
        rtbuddy_endpoints = recover_g17_rtbuddy_endpoints(
            symbol_code(rtbuddy, RTBUDDY_READ_MESSAGE)[1],
            symbol_code(rtbuddy, RTBUDDY_SEND_MESSAGE_GATED)[1],
            symbol_code(rtbuddy, RTBUDDY_MATCHED_ENDPOINT_GATED)[1],
            symbol_code(rtbuddy, RTBUDDY_ENABLE_ENDPOINTS)[1],
            symbol_code(rtbuddy, RTBUDDY_RECEIVED_MESSAGE)[1],
        )
        _address, page_shift_code = symbol_code(driver, ARM_FIRMWARE_PAGE_SHIFT)
        _address, set_64_pa_code = symbol_code(driver, SET_INIT_REGISTER_64_PA)
        _address, set_64_code = symbol_code(driver, SET_INIT_REGISTER_64)
        _address, set_32_code = symbol_code(driver, SET_INIT_REGISTER_32)
        bootstrap_region = recover_g17_bootstrap_region(
            arm_allocation_code,
            prepare_code,
            page_shift_code,
            set_64_pa_code,
            set_64_code,
            set_32_code,
        )
        bootstrap_region["accelerator_provider"] = init_sequence_provider
        bootstrap_roots = recover_g17_bootstrap_roots(
            arm_allocation_code,
            function,
            prepare_data_code,
            complete_data_code,
            page_shift_code,
        )
        platform_config = recover_g17_platform_config(driver, page_shift_code)
        allocation_address, allocation_code = symbol_code(driver, ALLOC_FIRMWARE_DATA)
        allocations = recover_firmware_allocations(
            driver, allocation_address, allocation_code
        )
        brn_workaround_table = recover_g17_brn_workaround_table(
            driver, allocation_code
        )
        if any(item["host_gpu_member"] == 0x338 for item in allocations):
            raise ValueError("zero-sized firmware BRN table was unexpectedly allocated")
        allocations.append(
            {
                "host_cpu_member": brn_workaround_table["host_cpu_member"],
                "host_gpu_member": brn_workaround_table["host_gpu_member"],
                "bytes": brn_workaround_table["bytes"],
            }
        )
        root_allocation_sizes = recover_root_allocation_sizes(allocations)
        _address, base_init_code = symbol_code(driver, INIT_BASE_FIRMWARE_DATA)
        _address, configure_code = symbol_code(driver, BASE_CONFIGURE_DEVICE)
        zero_initialized_allocations = recover_g17_zero_initialized_allocations(
            base_init_code
        )
        role0_bootstrap_regions = recover_g17_role0_bootstrap_regions(base_init_code)
        accelerator["device_control_bindings"] = recover_device_control_ring_bindings(
            allocations, base_init_code
        )
        _address, reset_channel_code = symbol_code(driver, RESET_CHANNEL_STATE)
        _address, write_channel_code = symbol_code(
            driver, WRITE_CHANNEL_COMMAND_POINTER
        )
        channels = recover_g17_channel_layout(reset_channel_code, write_channel_code)
        channels["pools"] = recover_g17_channel_pool_geometry(allocation_code)
        channels["state_sources"] = recover_g17_channel_state_sources(
            driver, reset_channel_code
        )
        channels["priority"] = recover_g17_channel_priority(driver)
        channels["submit_info"] = recover_g17_channel_submit_info(driver)
        channels["submission_flag"] = recover_g17_channel_submission_flag(driver)
        channels["data_master_types"] = recover_g17_channel_data_master_types(driver)
        channels["data_master_rings"] = recover_g17_data_master_ring_bindings(
            allocations, base_init_code
        )
        channels["data_master_doorbells"] = recover_g17_data_master_doorbells(
            driver
        )
        channels["identity"] = recover_g17_channel_identity(driver, iogpu)
        channels["scheduler_state"] = recover_g17_scheduler_state(driver)
        channels["queue_device_inputs"] = recover_g17_queue_device_inputs(
            driver, iogpu
        )
        channels["runtime_resources"] = recover_g17_channel_runtime_resources(
            driver, iogpu
        )
        channels["command_pools"] = recover_g17_channel_command_pools(driver)
        channels["command_pools"]["backing"] = (
            recover_g17_command_pool_backing(driver)
        )
        channels["command_3d_reclamation"] = (
            recover_g17_3d_command_reclamation(driver)
        )
        channels["command_common_fields"] = (
            recover_g17_channel_command_common_fields(driver)
        )
        channels["command_3d_register_lists"] = (
            recover_g17_3d_register_lists(driver)
        )
        channels["register_entry_codec"] = recover_g17_register_entry_codec(driver)
        channels["constant_virtual_returns"] = (
            recover_g17_constant_virtual_returns(driver)
        )
        channels["memory_map_virtual_address"] = (
            recover_g17_memory_map_virtual_address(driver, iogpu)
        )
        channels["random_provider"] = recover_g17_random_provider(
            driver, kernel
        )
        register_selectors = recover_g17_register_selectors(driver)
        inline_register_records = recover_g17_inline_register_records(driver)
        channels["register_selectors"] = register_selectors
        channels["inline_register_records"] = inline_register_records
        register_emission_cfg = recover_g17_register_emission_cfg(
            driver, register_selectors, inline_register_records
        )
        register_selectors["selector_formulas_complete"] = (
            inline_register_records["all_inline_forms_located"]
        )
        inline_register_records["control_flow_complete"] = (
            register_emission_cfg["predicate_expressions_complete"]
        )
        channels["register_emission_cfg"] = register_emission_cfg
        channels["command_stream_format"] = (
            recover_g17_command_stream_format(driver)
        )
        render_payload_format = recover_g17_render_payload_format(driver)
        channels["render_payload_format"] = render_payload_format
        channels["descriptor_render_command_fields"] = (
            recover_g17_render_descriptor_fields(driver, iogpu, render_payload_format)
        )
        descriptor_3d_common = recover_g17_3d_common_passthrough(driver)
        descriptor_3d_common["boolean_accounting"] = (
            explain_g17_3d_common_boolean_accounting(
                render_payload_format, descriptor_3d_common
            )
        )
        channels["descriptor_3d_common_passthrough"] = descriptor_3d_common
        channels["descriptor_ta_render_passthrough"] = (
            recover_g17_ta_render_passthrough(driver)
        )
        channels["descriptor_3d_initialization"] = (
            recover_g17_3d_descriptor_initialization(driver)
        )
        _address, base_power_code = symbol_code(driver, INIT_BASE_POWER_DATA)
        _address, power_code = symbol_code(driver, INIT_POWER_DATA)
        _address, setup_code = symbol_code(driver, SETUP_CONFIG)
        _address, shared_init_code = symbol_code(driver, INIT_FIRMWARE_SHARED_DATA)
        _address, ktrace_code = symbol_code(driver, KTRACE_FIRMWARE_CALLBACK)
        _address, wait_power_off_code = symbol_code(driver, WAIT_FIRMWARE_POWER_OFF)
        _address, wait_generation_code = symbol_code(
            driver, WAIT_NEXT_ASC_POWER_GENERATION
        )
        _address, snapshot_generation_code = symbol_code(
            driver, SNAPSHOT_ASC_POWER_GENERATION
        )
        _address, get_sleep_code = symbol_code(driver, GET_SYSTEM_SLEEP_NOTIFICATION)
        _address, set_sleep_code = symbol_code(driver, SET_SYSTEM_SLEEP_NOTIFICATION)
        small_shared_data = recover_g17_small_shared_data(
            allocations,
            shared_init_code,
            base_init_code,
            ktrace_code,
            wait_power_off_code,
            wait_generation_code,
            snapshot_generation_code,
            get_sleep_code,
            set_sleep_code,
        )
        runtime_controls = recover_g17_runtime_controls(
            allocations,
            {
                symbol: symbol_code(driver, symbol)[1]
                for symbol, _accesses in G17_RUNTIME_ACCESSORS.values()
            }
            | {
                G17_ADD_REGISTER_OVERRIDE: symbol_code(
                    driver, G17_ADD_REGISTER_OVERRIDE
                )[1]
            },
        )
        runtime_initialization = recover_g17_runtime_initialization(
            allocations,
            base_init_code,
            function,
            base_power_code,
            power_code,
        )
        dpe_ppt_target = recover_vtable_target(
            driver, G17_ACCELERATOR_VTABLE, 0xD80
        )
        dpe_ppt_symbol = next(
            (
                name
                for name, address in macho_symbols(driver).items()
                if address == dpe_ppt_target and name == POPULATE_DPE_PPT_CONFIG
            ),
            None,
        )
        if dpe_ppt_symbol is None:
            raise ValueError("could not resolve the G17 DPE/PPT producer symbol")
        _address, dpe_ppt_code = symbol_code(driver, dpe_ppt_symbol)
        runtime_power_policy = recover_g17_runtime_power_policy(
            driver, power_code, dpe_ppt_code
        )
        runtime_performance_policy = recover_g17_runtime_performance_policy(
            setup_code, power_code
        )
        runtime_platform_policy = recover_g17_runtime_platform_policy(driver)
        firmware_shared_data = recover_firmware_shared_data_layout(
            allocations, shared_init_code, base_init_code
        )
        firmware_shared_data["platform_fields"] = (
            recover_firmware_shared_platform_fields(function)
        )
        firmware_shared_data["platform_values"] = (
            recover_g17_shared_platform_values(driver)
        )
        hardware_config = recover_hardware_config(
            allocations, shared_init_code, firmware
        )
        hardware_config["host_layout"] = recover_driver_hardware_config_layout(
            base_init_code, base_power_code, power_code
        )
        hardware_config["address_space_layout"] = recover_g17_address_space_layout(
            driver, base_init_code
        )
        hardware_config["color_matrices"] = recover_g17_color_matrices(driver)
        hardware_config["fixed_constants"] = recover_g17_hardware_config_constants(
            driver, base_init_code, function
        )
        hardware_config["setup_constants"] = recover_g17_setup_config_constants(
            configure_code, setup_code
        )
        hardware_config["chip_info"] = recover_g17_chip_info(driver, function)
        hardware_config["power_sample_period"] = recover_g17_power_sample_period(
            driver, function
        )
        hardware_config["default_mcache_writes"] = (
            recover_g17_default_mcache_writes(driver, function)
        )
        hardware_config["enabled_usc_config"] = recover_g17_enabled_usc_config(
            driver, function
        )
        hardware_config["uat_config_flag"] = recover_g17_uat_config_flag(
            driver, function
        )
        hardware_config["gptbat_base"] = recover_g17_gptbat_base(
            driver, function
        )
        hardware_config["gpu_identity"] = recover_g17_gpu_identity_config(
            driver, base_init_code
        )
        hardware_config["aux_performance_states"] = (
            recover_g17_aux_performance_layout(driver, power_code)
        )
        hardware_config["relative_boost_frequency_table"] = (
            recover_g17_relative_boost_frequency_table(driver, power_code)
        )
        hardware_config["sram_power_scale_table"] = (
            recover_g17_sram_power_scale_table(
                driver, base_power_code, power_code
            )
        )
        hardware_config["static_power_scale_table"] = (
            recover_g17_static_power_scale_table(driver, kernel, power_code)
        )
        hardware_config["afr_relative_boost_frequency_table"] = (
            recover_g17_afr_relative_boost_frequency_table(driver, power_code)
        )
        hardware_config["secondary_performance_block"] = (
            recover_g17_secondary_performance_block(driver)
        )
        hardware_config["unit_mask_field"] = (
            recover_g17_unit_mask_field(driver)
        )
        hardware_config["core_count_gate"] = (
            recover_g17_core_count_gate(driver)
        )
        hardware_config["chip_info_decode"] = (
            recover_g17_chip_info_decode(driver)
        )
        hardware_config["chip_info_registers"] = (
            recover_g17_chip_info_registers(driver)
        )
        hardware_config["late_controls"] = recover_g17_late_controls(driver)
        hardware_config["linear_power_transfer_tables"] = (
            recover_g17_linear_power_transfer_tables(driver, power_code)
        )
        hardware_config["performance_state_map_block"] = (
            recover_g17_perf_state_map_block(driver, power_code)
        )
        hardware_config["pio_mappings"] = recover_g17_pio_mappings(driver)
        hardware_config["pio_uat_mapping"] = recover_g17_pio_uat_mapping(driver)
        firmware_root = recover_firmware_root(firmware)
    except (OSError, ValueError) as error:
        parser.error(str(error))
    print(
        json.dumps(
            {
                "schema": 1,
                "driver_uuid": driver_uuid,
                "firmware_uuid": firmware_uuid,
                "rtbuddy_uuid": rtbuddy_uuid,
                "driver_root": driver_root,
                "firmware_root": firmware_root,
                "bootstrap_roots": bootstrap_roots,
                "boot_transport": boot_transport,
                "rtbuddy_endpoints": rtbuddy_endpoints,
                "bootstrap_region": bootstrap_region,
                "platform_config": platform_config,
                "brn_workaround_table": brn_workaround_table,
                "zero_initialized_allocations": zero_initialized_allocations,
                "role0_bootstrap_regions": role0_bootstrap_regions,
                "small_shared_data": small_shared_data,
                "runtime_controls": runtime_controls,
                "runtime_initialization": runtime_initialization,
                "runtime_power_policy": runtime_power_policy,
                "runtime_performance_policy": runtime_performance_policy,
                "runtime_platform_policy": runtime_platform_policy,
                "accelerator": accelerator,
                "channels": channels,
                "firmware_shared_data": firmware_shared_data,
                "hardware_config": hardware_config,
                "uat_handoff": handoff,
                "root_allocation_bytes": root_allocation_sizes,
            },
            indent=2,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
