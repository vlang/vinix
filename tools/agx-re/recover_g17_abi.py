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
import _native_g17
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
IOGPU_WEAK_NAMESPACE_GET_OBJECT = "__ZNK18IOGPUWeakNamespace9getObjectEj"
IOGPU_WEAK_NAMESPACE_REMOVE_OBJECT = "__ZN18IOGPUWeakNamespace12removeObjectEj"
IOSURFACE_ROOT_SIGNAL_EVENT_ID = "__ZN13IOSurfaceRoot13signalEventIDEj"
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
ARM_SUBMIT_DEVICE_CONTROL = (
    "__ZN14AGXArmFirmware19submitDeviceControlE"
    "P33AGFIAcceleratorDeviceControlEntryjPj"
)
ACCELERATOR_SUBMIT_DEVICE_CONTROL = (
    "__ZN14AGXAccelerator19submitDeviceControlE"
    "P33AGFIAcceleratorDeviceControlEntryPjS2_"
)
ALLOCATE_PM_MEMORY_EVENT = (
    "__ZN14AGXAccelerator19allocateMemoryEventEP22IOInterruptEventSourcei"
)
ALLOCATE_UMA_MEMORY_EVENT = (
    "__ZN14AGXAccelerator22allocateUMAMemoryEventEP22IOInterruptEventSourcei"
)
HWPB_MANAGER_META_CLASS = "__ZN23AGXHWParamBufferManager10gMetaClassE"
PARAMETER_MANAGEMENT_VTABLE = "__ZTV22AGXParameterManagement"
PARAMETER_MANAGEMENT_VIRTUAL_VTABLE = "__ZTV29AGXParameterManagementVirtual"
PARAMETER_MANAGEMENT_GROW = "__ZN22AGXParameterManagement15growImmediatelyEv"
PARAMETER_MANAGEMENT_VIRTUAL_GROW = (
    "__ZN29AGXParameterManagementVirtual15growImmediatelyEv"
)
USC_PRIV_MEM_FLIST_META_CLASS = "__ZN18AGXUSCPrivMemFList10gMetaClassE"
IMPLICIT_GROW_ENGINE_VTABLE = "__ZTV21AGXImplicitGrowEngine"
USC_PRIV_MEM_RETIRE_GROW_REQUEST = (
    "__ZN24IAGXUSCPrivMemGrowEngine17retireGrowRequestEiiyj"
)
G17_HAL_UPDATE_UMA_DESC = (
    "__ZN31AGX·PI_300·X·A0·Accelerator16halUpdateUMADescE"
    "P18AGXUSCPrivMemFListRK30AGXUSCPrivateMemDescUpdateData"
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
REGISTER_ENTRY_APPEND = "__ZN20AGXKRCEBufferEncoder6appendEjhy"
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
G17_ACCELERATOR_META_ALLOC = "__ZNK18AGXAcceleratorG17X9MetaClass5allocEv"
G17_SET_SMART_IDLE_OFF_ENABLE = "__ZN14AGXArmFirmware21setSmartIdleOffEnableEb"
G17_ACCELERATOR_OBJECT_BYTES = 0x1CBD0
G17_RETRIEVE_CHIP_INFO = "__ZN14AGXAccelerator16retrieveChipInfoEP12AGXSChipInfo"
G17_RETRIEVE_CHIP_INFO_VTABLE_SLOT = 0xD60
G17_ACCELERATOR_FEATURE_FLAGS = 0x6D0
G17_ACCELERATOR_POWER_COLUMN_COUNT = 0x4E4
G17_ACCELERATOR_CHIP_INFO = 0xF7C8
G17_ACCELERATOR_CHIP_INFO_OVERRIDE = 0xF7F0
G17_ACCELERATOR_X_START = "__ZN32AGX·PI_300·X·A0·AcceleratorX5startEP9IOService"
G17_PERF_SAMPLER_VTABLE = "__ZTV22AGXPerfCtrSamplerGen15"
G17_PERF_SAMPLER_INIT = "__ZN17AGXPerfCtrSampler4initEP14AGXAcceleratorP16AGXPerfCtrConfig"
G17_PERF_SAMPLER_START = "__ZN17AGXPerfCtrSampler18sourceSamplerStartEv"
G17_ACCELERATOR_PERF_SAMPLER = 0x111D0
G17_PERF_SAMPLER_RUNNING = 0x54
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
    return _native_g17.macho_uuid(image)


def macho_symbols(image: bytes) -> dict[str, int]:
    return _native_g17.macho_symbols(image)


def virtual_to_file(image: bytes, address: int) -> int:
    return _native_g17.virtual_to_file(image, address)


def read_adrp_add_cstring(
    image: bytes, function_address: int, code: bytes, adrp_offset: int, add_offset: int
) -> str:
    return _native_g17.read_adrp_add_cstring(image, function_address, code, adrp_offset, add_offset)


def read_adrp_add_address(
    function_address: int, code: bytes, adrp_offset: int, add_offset: int
) -> int:
    return _native_g17.read_adrp_add_address(function_address, code, adrp_offset, add_offset)


def read_virtual_u32_table(image: bytes, address: int, count: int) -> tuple[int, ...]:
    return _native_g17.read_virtual_u32_table(image, address, count)


def symbol_code(image: bytes, name: str) -> tuple[int, bytes]:
    return _native_g17.symbol_code(image, name)


def words(code: bytes):
    yield from _native_g17.words(code)


def decode_move_wide(word: int) -> tuple[str, int, int, int] | None:
    return _native_g17.decode("decode_move_wide", word=word)


def find_materialized_constant(code: bytes, target: int) -> list[tuple[int, int, int]]:
    return _native_g17.find_materialized_constant(code, target)


def decode_add_immediate(word: int) -> tuple[int, int, int] | None:
    return _native_g17.decode("decode_add_immediate", word=word)


def decode_ldp_x(word: int) -> tuple[int, int, int, int] | None:
    return _native_g17.decode("decode_ldp_x", word=word)


def decode_str_x(word: int) -> tuple[int, int, int] | None:
    return _native_g17.decode("decode_str_x", word=word)


def decode_ldr_x(word: int) -> tuple[int, int, int] | None:
    return _native_g17.decode("decode_ldr_x", word=word)


def decode_ldr_w(word: int) -> tuple[int, int, int] | None:
    return _native_g17.decode("decode_ldr_w", word=word)


def decode_load_unsigned(word: int) -> tuple[int, int, int, int] | None:
    return _native_g17.decode("decode_load_unsigned", word=word)


def decode_integer_load_unsigned(word: int) -> tuple[int, int, int, int] | None:
    return _native_g17.decode("decode_integer_load_unsigned", word=word)


def decode_integer_store_unsigned(word: int) -> tuple[int, int, int, int] | None:
    return _native_g17.decode("decode_integer_store_unsigned", word=word)


def decode_load_register(word: int) -> tuple[int, int, int, int] | None:
    return _native_g17.decode("decode_load_register", word=word)


def decode_add_register(word: int) -> tuple[int, int, int, int] | None:
    return _native_g17.decode("decode_add_register", word=word)


def decode_cmp_w_immediate(word: int) -> tuple[int, int] | None:
    return _native_g17.decode("decode_cmp_w_immediate", word=word)


def decode_movz_w(word: int) -> tuple[int, int] | None:
    return _native_g17.decode("decode_movz_w", word=word)


def decode_movk_w(word: int) -> tuple[int, int, int] | None:
    return _native_g17.decode("decode_movk_w", word=word)


def decode_movn_w(word: int) -> tuple[int, int] | None:
    return _native_g17.decode("decode_movn_w", word=word)


def decode_add_sub_immediate_w(word: int) -> tuple[str, int, int, int] | None:
    return _native_g17.decode("decode_add_sub_immediate_w", word=word)


def decode_logical_immediate_w(word: int) -> tuple[str, int, int, int] | None:
    return _native_g17.decode("decode_logical_immediate_w", word=word)


def resolve_static_w_register(
    instructions: list[tuple[int, int]], before: int, register: int, depth: int = 0
) -> int | None:
    return _native_g17.resolve_static_w_register(instructions, before, register, depth)


def resolve_static_x_register(
    instructions: list[tuple[int, int]], before: int, register: int, depth: int = 0
) -> int | None:
    return _native_g17.resolve_static_x_register(instructions, before, register, depth)


def decode_register_copy(word: int) -> tuple[int, int, int] | None:
    return _native_g17.decode("decode_register_copy", word=word)


def decode_local_branch_target(address: int, word: int) -> int | None:
    return _native_g17.decode("decode_local_branch_target", address=address, word=word)


def decode_conditional_branch(
    address: int, word: int
) -> tuple[int, str] | None:
    return _native_g17.decode("decode_conditional_branch", address=address, word=word)


def decode_test_bit_branch(address: int, word: int) -> dict[str, object] | None:
    return _native_g17.decode("decode_test_bit_branch", address=address, word=word)


def decode_compare_zero_branch(
    address: int, word: int
) -> dict[str, object] | None:
    return _native_g17.decode("decode_compare_zero_branch", address=address, word=word)


def g17_register_is_written(word: int, register: int) -> bool:
    return _native_g17.g17_register_is_written(word, register)


def find_dominating_g17_register_write(
    instructions: list[tuple[int, int]], use_index: int, register: int
) -> int | None:
    return _native_g17._query(
        b"", 'find_dominating_g17_register_write',
        instructions=instructions, use_index=use_index, register=register
    )


def g17_definition_dominates_use(
    instructions: list[tuple[int, int]], definition_index: int, use_index: int
) -> bool:
    return _native_g17._query(
        b"", 'g17_definition_dominates_use',
        instructions=instructions, definition_index=definition_index, use_index=use_index
    )


def trace_g17_known_call_return(
    instructions: list[tuple[int, int]],
    use_index: int,
    depth: int,
    seen: frozenset[tuple[int, int]],
) -> dict[str, object] | None:
    return _native_g17._query(
        b"", 'trace_g17_known_call_return',
        instructions=instructions, use_index=use_index, depth=depth, seen=list(seen)
    )


def trace_g17_stack_load(
    instructions: list[tuple[int, int]],
    load_index: int,
    member: int,
    width: int,
    depth: int,
    seen: frozenset[tuple[int, int]],
) -> dict[str, object] | None:
    return _native_g17._query(
        b"", 'trace_g17_stack_load',
        instructions=instructions, load_index=load_index, member=member, width=width, depth=depth, seen=list(seen)
    )


def trace_g17_register_copy(
    instructions: list[tuple[int, int]], copy_index: int, source: int
) -> dict[str, object] | None:
    return _native_g17._query(
        b"", 'trace_g17_register_copy',
        instructions=instructions, copy_index=copy_index, source=source
    )


def decode_logical_shifted_register(word: int) -> dict[str, object] | None:
    return _native_g17.decode("decode_logical_shifted_register", word=word)


def decode_logical_immediate_x(word: int) -> tuple[str, int, int, int] | None:
    return _native_g17.decode("decode_logical_immediate_x", word=word)


def decode_add_sub_immediate_value(word: int) -> dict[str, object] | None:
    return _native_g17.decode("decode_add_sub_immediate_value", word=word)


def decode_add_sub_register_value(word: int) -> dict[str, object] | None:
    return _native_g17.decode("decode_add_sub_register_value", word=word)


def decode_bitfield_value(word: int) -> dict[str, object] | None:
    return _native_g17.decode("decode_bitfield_value", word=word)


def decode_conditional_select_value(word: int) -> dict[str, object] | None:
    return _native_g17.decode("decode_conditional_select_value", word=word)


def trace_g17_condition_expression(
    instructions: list[tuple[int, int]],
    use_index: int,
    depth: int,
    seen: frozenset[tuple[int, int]],
) -> dict[str, object] | None:
    return _native_g17._query(
        b"", 'trace_g17_condition_expression',
        instructions=instructions, use_index=use_index, depth=depth, seen=list(seen)
    )


def trace_g17_four_way_compare_merge(
    instructions: list[tuple[int, int]],
    use_index: int,
    register: int,
    depth: int,
    seen: frozenset[tuple[int, int]],
) -> dict[str, object] | None:
    return _native_g17._query(
        b"", 'trace_g17_four_way_compare_merge',
        instructions=instructions, use_index=use_index, register=register, depth=depth, seen=list(seen)
    )


def trace_g17_optional_bit_set_merge(
    instructions: list[tuple[int, int]],
    use_index: int,
    register: int,
    depth: int,
    seen: frozenset[tuple[int, int]],
) -> dict[str, object] | None:
    return _native_g17._query(
        b"", 'trace_g17_optional_bit_set_merge',
        instructions=instructions, use_index=use_index, register=register, depth=depth, seen=list(seen)
    )


def trace_g17_cl_base_merge(
    instructions: list[tuple[int, int]],
    use_index: int,
    register: int,
    depth: int,
    seen: frozenset[tuple[int, int]],
) -> dict[str, object] | None:
    return _native_g17._query(
        b"", 'trace_g17_cl_base_merge',
        instructions=instructions, use_index=use_index, register=register, depth=depth, seen=list(seen)
    )


def trace_g17_cl_mode_bit_merge(
    instructions: list[tuple[int, int]],
    use_index: int,
    register: int,
    depth: int,
    seen: frozenset[tuple[int, int]],
) -> dict[str, object] | None:
    return _native_g17._query(
        b"", 'trace_g17_cl_mode_bit_merge',
        instructions=instructions, use_index=use_index, register=register, depth=depth, seen=list(seen)
    )


def trace_g17_control_flow_merge(
    instructions: list[tuple[int, int]],
    use_index: int,
    register: int,
    depth: int,
    seen: frozenset[tuple[int, int]],
) -> dict[str, object] | None:
    return _native_g17._query(
        b"", 'trace_g17_control_flow_merge',
        instructions=instructions, use_index=use_index, register=register, depth=depth, seen=list(seen)
    )


def trace_g17_value_expression(
    instructions: list[tuple[int, int]],
    use_index: int,
    register: int,
    depth: int = 0,
    seen: frozenset[tuple[int, int]] = frozenset(),
) -> dict[str, object] | None:
    return _native_g17._query(
        b"", 'trace_g17_value_expression',
        instructions=instructions, use_index=use_index, register=register, depth=depth, seen=list(seen)
    )


def classify_g17_value_argument(
    instructions: list[tuple[int, int]], before: int, register: int = 4
) -> dict[str, object]:
    return _native_g17._query(
        b"", 'classify_g17_value_argument',
        instructions=instructions, before=before, register=register
    )


def decode_umaddl(word: int) -> tuple[int, int, int, int] | None:
    return _native_g17.decode("decode_umaddl", word=word)


def decode_bfi_x(word: int) -> tuple[int, int, int, int] | None:
    return _native_g17.decode("decode_bfi_x", word=word)


def decode_ubfiz_x(word: int) -> tuple[int, int, int, int] | None:
    return _native_g17.decode("decode_ubfiz_x", word=word)


def decode_str_unsigned(word: int) -> tuple[int, int, int, int] | None:
    return _native_g17.decode("decode_str_unsigned", word=word)


def decode_stur_x(word: int) -> tuple[int, int, int] | None:
    return _native_g17.decode("decode_stur_x", word=word)


def decode_pair_q(word: int) -> tuple[str, int, int, int, int] | None:
    return _native_g17.decode("decode_pair_q", word=word)


def decode_adrp(address: int, word: int) -> tuple[int, int] | None:
    return _native_g17.decode("decode_adrp", address=address, word=word)


def decode_bl_target(address: int, word: int) -> int | None:
    return _native_g17.decode("decode_bl_target", address=address, word=word)


def decode_b_target(address: int, word: int) -> int | None:
    return _native_g17.decode("decode_b_target", address=address, word=word)


def decode_stp_x(word: int) -> tuple[int, int, int, int] | None:
    return _native_g17.decode("decode_stp_x", word=word)


def decode_ldr_d(word: int) -> tuple[int, int, int] | None:
    return _native_g17.decode("decode_ldr_d", word=word)


def decode_str_d(word: int) -> tuple[int, int, int] | None:
    return _native_g17.decode("decode_str_d", word=word)


def decode_stur_d(word: int) -> tuple[int, int, int] | None:
    return _native_g17.decode("decode_stur_d", word=word)


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
    return _native_g17._query(b"", 'recover_g17_bootstrap_roots', allocation_code=allocation_code.hex(), init_code=init_code.hex(), prepare_code=prepare_code.hex(), complete_code=complete_code.hex(), page_shift_code=page_shift_code.hex())


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
    return _native_g17.require_instruction_sequence(code, label, sequence)


def require_instruction_words_at(
    code: bytes, label: str, expected: dict[int, int]
) -> None:
    return _native_g17.require_instruction_words_at(code, label, expected)


def find_direct_symbol_callers(image: bytes, target: int) -> set[str]:
    return set(_native_g17._query(image, 'find_direct_symbol_callers', target=target))


def find_authenticated_target_references(image: bytes, target: int) -> list[int]:
    return _native_g17.find_authenticated_target_references(image, target)


def decode_kernel_auth_rebase(raw: int) -> int:
    return _native_g17.decode_kernel_auth_rebase(raw)


def recover_vtable_target(image: bytes, vtable_name: str, slot: int) -> int:
    return _native_g17.recover_vtable_target(image, vtable_name, slot)


def recover_g17_constant_virtual_returns(image: bytes) -> dict[str, object]:
    return _native_g17._query(image, 'recover_g17_constant_virtual_returns')


def recover_g17_memory_map_virtual_address(
    driver: bytes, iogpu: bytes
) -> dict[str, object]:
    return _native_g17._query(driver, 'recover_g17_memory_map_virtual_address', iogpu=iogpu.hex())


def read_adrp_load(
    image: bytes,
    function_address: int,
    code: bytes,
    adrp_offset: int,
    load_offset: int,
    expected_width: int,
) -> bytes:
    return _native_g17.read_adrp_load(image, function_address, code, adrp_offset, load_offset, expected_width)


def recover_g17_init_sequence_provider(image: bytes) -> dict[str, object]:
    return _native_g17._query(image, 'recover_g17_init_sequence_provider')


def recover_g17_platform_config(image: bytes, page_shift_code: bytes) -> dict[str, object]:
    return _native_g17._query(image, 'recover_g17_platform_config', page_shift_code=page_shift_code.hex())


def recover_g17_brn_workaround_table(
    image: bytes, allocation_code: bytes
) -> dict[str, object]:
    return _native_g17._query(image, 'recover_g17_brn_workaround_table', allocation_code=allocation_code.hex())


def recover_g17_bootstrap_region(
    allocation_code: bytes,
    prepare_code: bytes,
    page_shift_code: bytes,
    set_64_pa_code: bytes,
    set_64_code: bytes,
    set_32_code: bytes,
) -> dict[str, object]:
    return _native_g17._query(b"", 'recover_g17_bootstrap_region', allocation_code=allocation_code.hex(), prepare_code=prepare_code.hex(), page_shift_code=page_shift_code.hex(), set_64_pa_code=set_64_pa_code.hex(), set_64_code=set_64_code.hex(), set_32_code=set_32_code.hex())


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
    return _native_g17._query(b"", 'recover_g17_small_shared_data', allocations_text=json.dumps(allocations), shared_init_code=shared_init_code.hex(), base_init_code=base_init_code.hex(), ktrace_code=ktrace_code.hex(), wait_power_off_code=wait_power_off_code.hex(), wait_generation_code=wait_generation_code.hex(), snapshot_generation_code=snapshot_generation_code.hex(), get_sleep_code=get_sleep_code.hex(), set_sleep_code=set_sleep_code.hex())


def recover_g17_runtime_controls(
    allocations: list[dict[str, int]], accessor_code: dict[str, bytes]
) -> dict[str, object]:
    return _native_g17._query(b"", 'recover_g17_runtime_controls', allocations_text=json.dumps(allocations), accessor_code={name: code.hex() for name, code in accessor_code.items()})


def recover_g17_runtime_initialization(
    allocations: list[dict[str, int]],
    base_init_code: bytes,
    arm_init_code: bytes,
    base_power_code: bytes,
    arm_power_code: bytes,
) -> dict[str, object]:
    return _native_g17._query(b"", 'recover_g17_runtime_initialization', allocations_text=json.dumps(allocations), base_init_code=base_init_code.hex(), arm_init_code=arm_init_code.hex(), base_power_code=base_power_code.hex(), arm_power_code=arm_power_code.hex())


def recover_g17_runtime_power_policy(
    image: bytes, arm_power_code: bytes, populate_code: bytes
) -> dict[str, object]:
    return _native_g17._query(image, 'recover_g17_runtime_power_policy', arm_power_code=arm_power_code.hex(), populate_code=populate_code.hex())


def recover_g17_runtime_performance_policy(
    setup_code: bytes, arm_power_code: bytes
) -> dict[str, object]:
    return _native_g17._query(b"", 'recover_g17_runtime_performance_policy', setup_code=setup_code.hex(), arm_power_code=arm_power_code.hex())


def recover_g17_runtime_platform_policy(image: bytes) -> dict[str, object]:
    return _native_g17._query(image, 'recover_g17_runtime_platform_policy')


def recover_g17_shared_platform_values(image: bytes) -> dict[str, object]:
    return _native_g17._query(image, 'recover_g17_shared_platform_values')


def recover_g17_zero_initialized_allocations(code: bytes) -> list[dict[str, object]]:
    return _native_g17._query(b"", 'recover_g17_zero_initialized_allocations', code=code.hex())


def recover_g17_role0_bootstrap_regions(code: bytes) -> list[dict[str, object]]:
    return _native_g17._query(b"", 'recover_g17_role0_bootstrap_regions', code=code.hex())


def recover_g17_pio_mappings(image: bytes) -> dict[str, object]:
    return _native_g17._query(image, 'recover_g17_pio_mappings')


def recover_g17_pio_uat_mapping(image: bytes) -> dict[str, object]:
    return _native_g17._query(image, 'recover_g17_pio_uat_mapping')


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
    return _native_g17._query(image, 'recover_g17_address_space_layout', base_init_code=base_init_code.hex())


def recover_g17_color_matrices(image: bytes) -> dict[str, object]:
    return _native_g17._query(image, 'recover_g17_color_matrices')


def recover_g17_hardware_config_constants(
    image: bytes, base_init_code: bytes, arm_init_code: bytes
) -> dict[str, object]:
    return _native_g17._query(image, 'recover_g17_hardware_config_constants', base_init_code=base_init_code.hex(), arm_init_code=arm_init_code.hex())


def recover_g17_setup_config_constants(
    configure_code: bytes, arm_setup_code: bytes
) -> dict[str, object]:
    return _native_g17._query(b"", 'recover_g17_setup_config_constants', configure_code=configure_code.hex(), arm_setup_code=arm_setup_code.hex())


def recover_g17_chip_info(image: bytes, arm_init_code: bytes) -> dict[str, object]:
    return _native_g17._query(image, 'recover_g17_chip_info', arm_init_code=arm_init_code.hex())


def recover_g17_power_sample_period(
    image: bytes, arm_init_code: bytes
) -> dict[str, object]:
    return _native_g17._query(image, 'recover_g17_power_sample_period', arm_init_code=arm_init_code.hex())


def recover_g17_default_mcache_writes(
    image: bytes, arm_init_code: bytes
) -> dict[str, object]:
    return _native_g17._query(image, 'recover_g17_default_mcache_writes', arm_init_code=arm_init_code.hex())


def recover_g17_enabled_usc_config(
    image: bytes, arm_init_code: bytes
) -> dict[str, object]:
    return _native_g17._query(image, 'recover_g17_enabled_usc_config', arm_init_code=arm_init_code.hex())


def recover_g17_uat_config_flag(
    image: bytes, arm_init_code: bytes
) -> dict[str, object]:
    return _native_g17._query(image, 'recover_g17_uat_config_flag', arm_init_code=arm_init_code.hex())


def recover_g17_gptbat_base(
    image: bytes, arm_init_code: bytes
) -> dict[str, object]:
    return _native_g17._query(image, 'recover_g17_gptbat_base', arm_init_code=arm_init_code.hex())


def recover_g17_gpu_identity_config(
    image: bytes, base_init_code: bytes
) -> dict[str, object]:
    return _native_g17._query(image, 'recover_g17_gpu_identity_config', base_init_code=base_init_code.hex())


def recover_g17_feature_defaults(
    image: bytes, base_init_code: bytes
) -> dict[str, object]:
    return _native_g17._query(image, 'recover_g17_feature_defaults', base_init_code=base_init_code.hex())


# Every accelerator site that stores the +0x6d0 feature-flag word. Each is a
# read-modify-write of the word; `sets` names how the bits it can newly set
# are recovered from the pinned instructions ("none" for AND-only sites).
G17_FEATURE_FLAG_WRITERS: tuple[tuple[str, int, dict[int, int], tuple], ...] = (
    (BASE_CONFIGURE_DEVICE, 0x22C,
     {0x208: 0xF9436A68, 0x20C: 0x9261F908, 0x228: 0xB2400108, 0x22C: 0xF9036A68},
     ("orr_immediate", 0x228)),
    # (old & 0xffffffffff061281) | (0x100 or 0) | (6 or 4)
    (BASE_CONFIGURE_DEVICE, 0x310,
     {0x26C: 0xF9436A68, 0x274: 0x52800095, 0x278: 0x528000C9, 0x27C: 0x9A951129,
      0x28C: 0x929DAFCA, 0x290: 0xF2BFE0CA, 0x294: 0x8A0A010A, 0x29C: 0x92620108,
      0x2A4: 0x52802008, 0x2A8: 0x9A9F0108, 0x2AC: 0xAA0A0108, 0x2B0: 0xAA090108,
      0x310: 0xF9036A68},
     ("movz_w", 0x2A4, 0x278, 0x274)),
    (BASE_CONFIGURE_DEVICE, 0x524,
     {0x4F0: 0xF9436A68, 0x4F4: 0x92B7E009, 0x4F8: 0xF2DFFE29, 0x4FC: 0x8A090108,
      0x524: 0xF9036A68},
     ("none",)),
    (BASE_CONFIGURE_DEVICE, 0x60C,
     {0x5A4: 0xF9436A69, 0x5E4: 0x92801008, 0x5E8: 0xF2D003E8, 0x5EC: 0xF2FFBE88,
      0x5F0: 0x8A080128, 0x600: 0xD2C50009, 0x604: 0xF2E04009, 0x608: 0xAA090108,
      0x60C: 0xF9036A68},
     ("move_wide_x", 0x600, 0x604)),
    (BASE_CONFIGURE_DEVICE, 0x684,
     {0x67C: 0xF9436A68, 0x680: 0x925BF908, 0x684: 0xF9036A68}, ("none",)),
    (BASE_CONFIGURE_DEVICE, 0x71C,
     {0x714: 0xF9436A68, 0x718: 0x9246F908, 0x71C: 0xF9036A68}, ("none",)),
    (BASE_CONFIGURE_DEVICE, 0xB8C,
     {0xB7C: 0xF9436A68, 0xB80: 0x92830009, 0xB84: 0xF2BFFD69, 0xB88: 0x8A090108,
      0xB8C: 0xF9036A68},
     ("none",)),
    # Only when the power-column count is at least two.
    (BASE_CONFIGURE_DEVICE, 0xBA0,
     {0xB90: 0xB944E669, 0xB94: 0x7100093F, 0xB9C: 0xB26B0108, 0xBA0: 0xF9036A68},
     ("orr_immediate", 0xB9C)),
    (BASE_CONFIGURE_DEVICE, 0xCD4,
     {0xCCC: 0xF9436A69, 0xCD0: 0x9269F928, 0xCD4: 0xF9036A68}, ("none",)),
    # Copies the old bit 30 into bit 25.
    (BASE_CONFIGURE_DEVICE, 0xD0C,
     {0xCD8: 0xD35EFD35, 0xD04: 0xF9436A68, 0xD08: 0xB36702A8, 0xD0C: 0xF9036A68},
     ("bfi", 0xD08)),
    (BASE_CONFIGURE_DEVICE, 0xD80,
     {0xD38: 0xF9436A68, 0xD7C: 0x924BF908, 0xD80: 0xF9036A68}, ("none",)),
    (BASE_CONFIGURE_DEVICE, 0x1FE8,
     {0x1FE0: 0xF9436A68, 0x1FE4: 0x924AF908, 0x1FE8: 0xF9036A68}, ("none",)),
    (BASE_CONFIGURE_DEVICE, 0x24AC,
     {0x24A4: 0xF9436A68, 0x24A8: 0x9247F908, 0x24AC: 0xF9036A68}, ("none",)),
    (PI300_CONFIGURE_DEVICE, 0xA8,
     {0x84: 0xF9436A68, 0x9C: 0x52909809, 0xA0: 0x72B00029, 0xA4: 0xAA090108,
      0xA8: 0xF9036A68},
     ("move_wide_w", 0x9C, 0xA0)),
    (PI300_CONFIGURE_DEVICE, 0x278,
     {0x224: 0xF9436A69, 0x26C: 0xD2C00C0A, 0x270: 0xF2E0004A, 0x274: 0xAA0A0129,
      0x278: 0xF9036A69},
     ("move_wide_x", 0x26C, 0x270)),
    (G17_CONFIGURE_DEVICE, 0xA4,
     {0x94: 0xF9436A68, 0x98: 0xD2A30049, 0x9C: 0xF2E00029, 0xA0: 0xAA090108,
      0xA4: 0xF9036A68},
     ("move_wide_x", 0x98, 0x9C)),
    (G17_CONFIGURE_DEVICE, 0x62C,
     {0x61C: 0xF9436A6A, 0x620: 0xB25E014A, 0x62C: 0xF9036A6A},
     ("orr_immediate", 0x620)),
    # Reached through firmware +0x298; it can only toggle bit 1.
    (G17_SET_SMART_IDLE_OFF_ENABLE, 0x20,
     {0x08: 0xF9436909, 0x10: 0x5280004A, 0x14: 0x9A9F114A, 0x18: 0x927EF929,
      0x1C: 0xAA0A0129, 0x20: 0xF9036909},
     ("movz_w", 0x10)),
)

# Census entries that write +0x6d0..+0x6d7 of some *other* object, with the
# reason they cannot be the accelerator. Keys are (kind, symbol, offset).
G17_FEATURE_FLAG_OTHER_OBJECTS: dict[tuple[str, str, int], str] = {
    ("store", "__ZN22AGXCLCommandDescriptor4initEP5IOGPUP17IOGPUCommandQueueP9IOGPUTaskPKcyP19AGXDebugBufferShmem", 0x114):
        "this is the AGXCLCommandDescriptor being initialized",
    ("store", "__ZN14AGXArmFirmware27initPowerAndPerformanceDataEv", 0x1A50):
        "zero store to firmware power data [firmware+0x2d8]+0x46d0",
    ("store", "__ZN14AGXArmFirmware27initPowerAndPerformanceDataEv", 0x24F0):
        "firmware runtime data [firmware+0x380]+0x12c+0x5a0",
    ("store", "__ZN14AGXArmFirmware27initPowerAndPerformanceDataEv", 0x24F8):
        "firmware runtime data [firmware+0x380]+0x12c+0x5a8",
    ("store", "__ZN28AGXHardwareKernelCommandUtil27copy3DCommonPassthroughDataEP22AGX3DCommandDescriptorRK21AGX3DCommandCommonRec", 0xF0):
        "the first argument is the AGX3DCommandDescriptor",
    ("global", "__GLOBAL__sub_I_agxk_firmware.cpp", 0x44):
        "static initializer storing an ADRP-addressed global",
    ("global", "__GLOBAL__sub_I_agxk_internal_resource.cpp", 0xBC):
        "static initializer storing an ADRP-addressed global",
    ("memory_routine", BASE_CONFIGURE_DEVICE, 0x25EC):
        "copies into the IOMallocData buffer allocated just before",
    ("memory_routine", BASE_CONFIGURE_DEVICE, 0x26C8):
        "copies into the IOMallocData buffer allocated just before",
    ("memory_routine", "__ZN11AGXFirmware23ensureStatisticsUpdatedEv", 0x1A0):
        "copies into AGXStatistics +0x480, reached through accelerator +0x1cb20",
    ("memory_routine", "__ZN14AGXArmFirmware27initPowerAndPerformanceDataEv", 0x2B64):
        "copies a table into firmware power data",
    ("memory_routine", "__ZN22AGXPerfCtrSamplerGen1123commitSourceCounterListEv", 0x214):
        "refills the 0x800-byte source array cleared at the same address",
    ("memory_routine", "__ZN16AGXRestartReport22finalizeAndSendReportsEP14AGXAccelerator", 0x91C):
        "copies into the IOMallocData report buffer allocated just before",
}

# Escaped interior pointers are accepted by callee when the callee cannot write
# the word: event tokens, noreturn traps, IOGPUEvent members (0x40 bytes; the
# accelerator keeps an 8-byte deadline at +0x6c8, so none sits there) and the
# 8-byte deadline itself.
G17_FEATURE_FLAG_SAFE_CALLEES = {
    "_clock_interval_to_deadline": "writes one u64 deadline ending before the word",
    "_IOLockWakeup": "the pointer is an event token",
    "__ZN14AGXAccelerator16acceleratorSleepEPv": "the pointer is an event token",
    "_panic": "does not return",
    "__ZN9os_detail21panic_trapping_policy4trapEPKc": "does not return",
    "__ZN9os_detail21panic_trapping_policy4trapEPKc.232": "does not return",
    "__ZNK17IOGPUEventMachine9copyEventEPK10IOGPUEventPS0_": "IOGPUEvent member",
    "__ZNK17IOGPUEventMachine10mergeEventEPK10IOGPUEventPS0_": "IOGPUEvent member",
    "__ZNK17IOGPUEventMachine10scrubEventEP10IOGPUEvent": "IOGPUEvent member",
    "__ZN17IOGPUEventMachine9initEventEP10IOGPUEvent": "IOGPUEvent member",
    "__ZNK17IOGPUEventMachine17isStampIdxInEventEP10IOGPUEventiPj": "IOGPUEvent member",
    "__ZNK17IOGPUEventMachine18eventHasStampIndexEPK10IOGPUEventi": "IOGPUEvent member",
    "__ZN15AGXEventMachine10traceEventE18AGXSTraceEventTypeP10IOGPUEventy": "IOGPUEvent member",
    "__ZN13AGXStatistics22updateThrottleCountersEP29AGFPowerThrottleCountersStatsPVj21AGFAControlDomainType":
        "a u32 counter in the firmware statistics object",
    "__ZN15AGXCommandQueue25populateCommandHWDSIDDataERK24AGXHardwareKernelCommandP12IOGPUChanneljP20AGXCommandHWDSIDData":
        "the AGXCommandHWDSIDData of a compute descriptor",
}
# Escapes through a virtual call, which the census cannot name, by site.
G17_FEATURE_FLAG_VIRTUAL_ESCAPES: dict[tuple[str, int], str] = {
    ("__ZN14AGXAccelerator25mcacheApertureBufferSetupER20AGXCommandHWDSIDDataiR25_AGFICommandKSMBufferInfoi", 0xF0):
        "member of the _AGFICommandKSMBufferInfo argument",
    ("__ZN14AGXAccelerator18drainCommandsTimerEv", 0x88):
        "event token for a wakeup; the byte at +0x681 is below the word",
    ("__ZN14AGXAccelerator17drainDeviceEventsEv", 0x124):
        "event token for a wakeup; the byte at +0x681 is below the word",
    ("__ZN16AGXCLChannelSKSM12submitBufferEP22IOGPUCommandDescriptor", 0x6A4):
        "member of the IOGPUCommandDescriptor argument",
}
G17_FEATURE_FLAG_VIRTUAL_ESCAPE_PREFIXES = (
    # Float out-parameters of the firmware power-controller configuration.
    "__ZN14AGXArmFirmware31getPIControllerConfigDictionaryE",
)

# Census entries writing accelerator +0xf7ec..+0xf7ff that are not the chip
# information override, with the reason they cannot change its final value.
G17_CHIP_INFO_OTHER_WRITERS: dict[tuple[str, str, int], str] = {
    ("memory_routine", BASE_CONFIGURE_DEVICE, 0x25EC):
        "copies into the IOMallocData buffer allocated just before",
    ("memory_routine", BASE_CONFIGURE_DEVICE, 0x26C8):
        "copies into the IOMallocData buffer allocated just before",
    ("memory_routine", "__ZN11AGXFirmware27initPowerAndPerformanceDataEv", 0x2C):
        "clears the firmware power data [firmware+0x2d8]",
    ("memory_routine", "__ZN14AGXArmFirmware27initPowerAndPerformanceDataEv", 0xD38):
        "clears a firmware power-data table",
    ("memory_routine", "__ZN14AGXArmFirmware27initPowerAndPerformanceDataEv", 0xE30):
        "clears a firmware power-data table",
    ("memory_routine", "__ZN14AGXArmFirmware27initPowerAndPerformanceDataEv", 0x1F78):
        "clears firmware power data [firmware+0x2d8]+0x52d4",
    ("memory_routine", "__ZN14AGXArmFirmware27initPowerAndPerformanceDataEv", 0x2B64):
        "copies a table into firmware power data",
    ("memory_routine", "__ZN22AGXPerfCtrSamplerGen1123commitSourceCounterListEv", 0x214):
        "refills the 0x800-byte source array cleared at the same address",
    ("memory_routine", "__ZN16AGXRestartReport22finalizeAndSendReportsEP14AGXAccelerator", 0x91C):
        "copies into the IOMallocData report buffer allocated just before",
    # retrieveChipInfo fills AGXSChipInfo at +0xf7c8 from inside the base
    # configureDevice, which returns before the override is stored.
    ("escape", BASE_CONFIGURE_DEVICE, 0x64C):
        "retrieveChipInfo, called before the override",
}


def _feature_flag_set_bits(code: bytes, recipe: tuple) -> int:
    kind = recipe[0]
    word = lambda offset: struct.unpack_from("<I", code, offset)[0]  # noqa: E731
    if kind == "none":
        return 0
    if kind == "orr_immediate":
        decoded = decode_logical_immediate_x(word(recipe[1]))
        if decoded is None or decoded[0] != "orr":
            raise ValueError("feature-flag OR immediate no longer decodes")
        return decoded[3]
    if kind == "movz_w":
        bits = 0
        for offset in recipe[1:]:
            move = decode_movz_w(word(offset))
            if move is None:
                raise ValueError("feature-flag MOVZ no longer decodes")
            bits |= move[1]
        return bits
    if kind == "move_wide_w":
        low = decode_movz_w(word(recipe[1]))
        high = decode_movk_w(word(recipe[2]))
        if low is None or high is None:
            raise ValueError("feature-flag 32-bit constant no longer decodes")
        return (low[1] & ~(0xFFFF << high[2])) | high[1] << high[2]
    if kind == "move_wide_x":
        value = 0
        for offset in recipe[1:]:
            move = decode_move_wide(word(offset))
            if move is None or move[0] not in ("movz", "movk"):
                raise ValueError("feature-flag 64-bit constant no longer decodes")
            _kind, _register, immediate, shift = move
            if move[0] == "movz":
                value = immediate << shift
            else:
                value = (value & ~(0xFFFF << shift)) | immediate << shift
        return value
    if kind == "bfi":
        decoded = decode_bfi_x(word(recipe[1]))
        if decoded is None:
            raise ValueError("feature-flag BFI no longer decodes")
        _destination, _source, lsb, width = decoded
        return ((1 << width) - 1) << lsb
    raise ValueError(f"unknown feature-flag recipe {kind!r}")


def _census_key(entry: dict[str, object]) -> tuple[str, str, int]:
    return str(entry["kind"]), str(entry["symbol"]), int(entry["offset"])


def require_zeroed_accelerator_allocation(image: bytes, kernel_image: bytes) -> dict[str, object]:
    """Prove the G17 accelerator object starts zero-filled."""

    symbols = macho_symbols(image)
    kernel_symbols = macho_symbols(kernel_image)
    if G17_ACCELERATOR_META_ALLOC not in symbols:
        raise ValueError(f"Mach-O has no {G17_ACCELERATOR_META_ALLOC} symbol")
    for name in (OS_OBJECT_TYPED_OPERATOR_NEW, KALLOC_TYPE_IMPL):
        if name not in kernel_symbols:
            raise ValueError(f"kernel Mach-O has no {name} symbol")
    address, code = symbol_code(image, G17_ACCELERATOR_META_ALLOC)
    require_instruction_words_at(
        code,
        "G17 accelerator typed allocation",
        {0x18: 0x52997A01, 0x1C: 0x72A00021},  # w1 = 0x1cbd0
    )
    call = decode_bl_target(address + 0x20, struct.unpack_from("<I", code, 0x20)[0])
    if call != kernel_symbols[OS_OBJECT_TYPED_OPERATOR_NEW]:
        raise ValueError("G17 accelerator is not allocated by OSObject typed operator new")
    new_address, new_code = symbol_code(kernel_image, OS_OBJECT_TYPED_OPERATOR_NEW)
    require_instruction_words_at(
        new_code, "OSObject zeroed typed allocation", {0x44: 0x52800081}
    )
    if decode_bl_target(
        new_address + 0x48, struct.unpack_from("<I", new_code, 0x48)[0]
    ) != kernel_symbols[KALLOC_TYPE_IMPL]:
        raise ValueError("OSObject typed operator new has an unexpected allocator target")
    return {
        "allocator": OS_OBJECT_TYPED_OPERATOR_NEW,
        "object_bytes": G17_ACCELERATOR_OBJECT_BYTES,
        "allocator_flag_name": "Z_ZERO",
    }


def recover_g17_accelerator_channel_inputs(
    image: bytes,
    kernel_image: bytes,
    iogpu_image: bytes,
    chip_info_decode: dict[str, object],
) -> dict[str, object]:
    """Recover the accelerator members the channel register producers read.

    The 3D, TA, FastBlit and CL producers load three accelerator members:
    the power-column count at +0x4e4, bits of the 64-bit feature-flag word at
    +0x6d0, and chip information at +0xf7ec..+0xf7fb. The first is hardware
    topology. For the other two, a census of every instruction in the driver
    that can write those bytes shows which bits can ever become set and that
    AcceleratorX::configureDevice overrides chip-information bytes
    +0x28..+0x37 with a fixed literal after retrieveChipInfo fills them.
    """

    symbols = macho_symbols(image)
    kernel_symbols = macho_symbols(kernel_image)
    required = (
        BASE_CONFIGURE_DEVICE,
        PI300_CONFIGURE_DEVICE,
        G17_CONFIGURE_DEVICE,
        G17_SET_SMART_IDLE_OFF_ENABLE,
        G17_RETRIEVE_CHIP_INFO,
    )
    missing = [name for name in required if name not in symbols]
    if missing:
        raise ValueError(f"Mach-O has no {missing[0]} symbol")
    if recover_vtable_target(
        image, G17_ACCELERATOR_VTABLE, G17_RETRIEVE_CHIP_INFO_VTABLE_SLOT
    ) != symbols[G17_RETRIEVE_CHIP_INFO]:
        raise ValueError("unexpected G17 retrieveChipInfo provider")
    column = chip_info_decode["fields"]["power_column_count"]
    if column.get("accelerator_member") != G17_ACCELERATOR_POWER_COLUMN_COUNT:
        raise ValueError("power-column count is no longer copied to accelerator +0x4e4")
    allocation = require_zeroed_accelerator_allocation(image, kernel_image)

    # Feature flags: every census entry is either a pinned accelerator
    # read-modify-write, a write to another object, or a clear.
    flags = census_g17_member_writes(
        image, G17_ACCELERATOR_FEATURE_FLAGS, G17_ACCELERATOR_FEATURE_FLAGS + 8,
        kernel_symbols,
    )
    writers = {(symbol, offset): (pins, recipe) for symbol, offset, pins, recipe in G17_FEATURE_FLAG_WRITERS}
    may_set = 0
    seen_writers: set[tuple[str, int]] = set()
    other_objects: list[dict[str, object]] = []
    for entry in flags["stores"] + flags["global_stores"] + flags["memory_routines"]:
        key = _census_key(entry)
        if entry["kind"] == "store" and (key[1], key[2]) in writers:
            pins, recipe = writers[(key[1], key[2])]
            _address, code = symbol_code(image, key[1])
            require_instruction_words_at(code, f"feature-flag writer {key[2]:#x}", pins)
            may_set |= _feature_flag_set_bits(code, recipe)
            seen_writers.add((key[1], key[2]))
        elif entry.get("clears_only"):
            other_objects.append({**entry, "reason": "clears only"})
        elif key in G17_FEATURE_FLAG_OTHER_OBJECTS:
            other_objects.append({**entry, "reason": G17_FEATURE_FLAG_OTHER_OBJECTS[key]})
        else:
            raise ValueError(
                f"unclassified write to feature flags: {key[0]} {key[1]}+{key[2]:#x}"
            )
    if seen_writers != set(writers):
        raise ValueError(f"feature-flag writers not found: {sorted(set(writers) - seen_writers)}")
    reverse = {address: name for name, address in kernel_symbols.items()}
    reverse.update({address: name for name, address in macho_symbols(iogpu_image).items()})
    reverse.update({address: name for name, address in symbols.items()})
    for entry in flags["escapes"]:
        callee = reverse.get(entry.get("target"))
        site = (str(entry["symbol"]), int(entry["offset"]))
        if callee in G17_FEATURE_FLAG_SAFE_CALLEES:
            reason = G17_FEATURE_FLAG_SAFE_CALLEES[callee]
        elif site in G17_FEATURE_FLAG_VIRTUAL_ESCAPES:
            reason = G17_FEATURE_FLAG_VIRTUAL_ESCAPES[site]
        elif any(site[0].startswith(prefix) for prefix in G17_FEATURE_FLAG_VIRTUAL_ESCAPE_PREFIXES) and entry["member"] < G17_ACCELERATOR_FEATURE_FLAGS - 4:
            reason = "4-byte float out-parameter below the word"
        else:
            raise ValueError(
                f"unclassified pointer to feature flags passed by {site[0]}+{site[1]:#x}"
            )
        other_objects.append({**entry, "reason": reason, "callee": callee})

    # Chip information: exactly one store, the unconditional override.
    chip = census_g17_member_writes(
        image, G17_ACCELERATOR_CHIP_INFO + 0x24, G17_ACCELERATOR_CHIP_INFO + 0x38,
        kernel_symbols,
    )
    override_sites = [
        entry for entry in chip["stores"]
        if (entry["symbol"], entry["offset"]) == (G17_CONFIGURE_DEVICE, 0x748)
    ]
    others = [entry for entry in chip["stores"] + chip["global_stores"] if entry not in override_sites]
    others += chip["memory_routines"] + chip["escapes"]
    if len(override_sites) != 1:
        raise ValueError("chip-information override store is missing")
    for entry in others:
        if _census_key(entry) not in G17_CHIP_INFO_OTHER_WRITERS:
            raise ValueError(
                f"unclassified write to chip information: {entry['kind']} "
                f"{entry['symbol']}+{entry['offset']:#x}"
            )
    address, code = symbol_code(image, G17_CONFIGURE_DEVICE)
    require_instruction_words_at(
        code,
        "G17 chip-information override",
        {0x744: 0x3DC35500, 0x748: 0x3DBDFE60},  # ldr q0, =literal; str q0, [x19, #0xf7f0]
    )
    _base_address, base_code = symbol_code(image, BASE_CONFIGURE_DEVICE)
    require_instruction_words_at(
        base_code,
        "G17 retrieveChipInfo call",
        {
            0x610: 0x529EF908,  # mov w8, #0xf7c8
            0x638: 0xF946B20A,  # vtable slot 0xd60
            0x63C: 0x8B080261,  # x1 = this + 0xf7c8
            0x640: 0xAA1303E0,  # x0 = this
            0x64C: 0xD73F0951,  # blraa
        },
    )
    page = decode_adrp(address + 0x740, struct.unpack_from("<I", code, 0x740)[0])
    if page is None or page[0] != 8:
        raise ValueError("chip-information override literal is no longer PC-relative")
    literal_address = page[1] + ((0x3DC35500 >> 10) & 0xFFF) * 16
    literal_offset = virtual_to_file(image, literal_address)
    literal = image[literal_offset : literal_offset + 16]
    # The PI_300 base (which runs retrieveChipInfo) returns before the store,
    # and the store is reached on every path that does not panic.
    if decode_bl_target(address + 0x70, struct.unpack_from("<I", code, 0x70)[0]) != symbols[PI300_CONFIGURE_DEVICE]:
        raise ValueError("AcceleratorX configureDevice no longer calls its PI_300 base first")
    panic = kernel_symbols.get("_panic")
    for offset, word in words(code[:0x748]):
        branch_address = address + offset
        if word & 0xFFFFFC1F == 0xD65F0000 or word in (0xD65F0BFF, 0xD65F0FFF):
            raise ValueError("AcceleratorX configureDevice returns before the override")
        if word & 0xFFFFFC1F == 0xD61F0000 or word & 0xFFFFF800 == 0xD71F0800:
            raise ValueError("AcceleratorX configureDevice branches indirectly before the override")
        target = decode_local_branch_target(branch_address, word)
        if target is None or target <= address + 0x748:
            continue
        panic_offset = target - address
        tail = code[panic_offset : panic_offset + 0x30]
        if not any(
            decode_bl_target(target + index, value) == panic
            for index, value in words(tail)
        ):
            raise ValueError(
                f"AcceleratorX configureDevice can skip the override from +{offset:#x}"
            )

    # The 3D, TA and FastBlit producers add two register-entry appends while
    # the performance-counter sampler at +0x111d0 is running.
    for name in (G17_ACCELERATOR_X_START, G17_PERF_SAMPLER_VTABLE, G17_PERF_SAMPLER_INIT, G17_PERF_SAMPLER_START):
        if name not in symbols:
            raise ValueError(f"Mach-O has no {name} symbol")
    start_address, start_code = symbol_code(image, G17_ACCELERATOR_X_START)
    require_instruction_words_at(
        start_code,
        "G17 performance-counter sampler creation",
        {
            0x1E4: 0x91404668,  # x8 = this + 0x11000
            0x1E8: 0x91074116,  # x22 = this + 0x111d0
            0x1F4: 0x52802301,  # a 0x118-byte object
            0x220: 0x91166210,  # vtable page offset
            0x224: 0x91004210,  # past the vtable header
            0x248: 0xF9000010,  # installed as the object's vtable
            0x264: 0xF90002D4,  # object stored at this + 0x111d0
        },
    )
    page = decode_adrp(start_address + 0x21C, struct.unpack_from("<I", start_code, 0x21C)[0])
    if page is None or page[1] + 0x598 != symbols[G17_PERF_SAMPLER_VTABLE]:
        raise ValueError("accelerator +0x111d0 is no longer an AGXPerfCtrSamplerGen15")
    require_instruction_words_at(
        symbol_code(image, G17_PERF_SAMPLER_INIT)[1],
        "performance-counter sampler init",
        {0x88: 0x3901529F},  # running byte cleared
    )
    require_instruction_words_at(
        symbol_code(image, G17_PERF_SAMPLER_START)[1],
        "performance-counter sampler start",
        {0x150: 0x39015268, 0x184: 0x39015268, 0x1AC: 0x39015268},
    )

    never_set = ~may_set & 0xFFFFFFFFFFFFFFFF
    return {
        "power_column_count": {
            "member": G17_ACCELERATOR_POWER_COLUMN_COUNT,
            "bytes": 4,
            "source": "hardware_config.chip_info_decode.fields.power_column_count",
            "hardware_input": "column_count",
        },
        "feature_flags": {
            "member": G17_ACCELERATOR_FEATURE_FLAGS,
            "bytes": 8,
            "initial": allocation,
            "may_set_mask": may_set,
            "never_set_mask": never_set,
            "writers": [
                {"symbol": symbol, "offset": offset} for symbol, offset, _pins, _recipe in G17_FEATURE_FLAG_WRITERS
            ],
            "other_objects": len(other_objects),
            "unbounded": flags["unbounded"][0],
        },
        "chip_information": {
            "member": G17_ACCELERATOR_CHIP_INFO,
            "producer": G17_RETRIEVE_CHIP_INFO,
            "override_member": G17_ACCELERATOR_CHIP_INFO_OVERRIDE,
            "override_bytes": 16,
            "override_value": literal.hex(),
            "override_producer": G17_CONFIGURE_DEVICE,
            "unbounded": chip["unbounded"][0],
        },
        "perf_counter_sampler": {
            "pointer_member": G17_ACCELERATOR_PERF_SAMPLER,
            "vtable": G17_PERF_SAMPLER_VTABLE,
            "object_bytes": 0x118,
            "running_member": G17_PERF_SAMPLER_RUNNING,
            "running_bytes": 1,
            "cleared_by": G17_PERF_SAMPLER_INIT,
            "set_by": G17_PERF_SAMPLER_START,
            # A Vinix decision, not a property of the Apple driver.
            "vinix_policy": {
                "running": 0,
                "reason": "Vinix has no AGX performance-counter sampler, so "
                "sourceSamplerStart never runs",
            },
        },
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
    return _native_g17._query(
        image, "recover_g17_linear_power_transfer_tables", code=arm_power_code.hex()
    )


def stores_covering_any(code: bytes, targets: set[int]) -> dict[int, list[tuple[int, int]]]:
    return _native_g17.stores_covering_any(code, targets)


def stores_covering(code: bytes, base: int, target: int) -> list[int]:
    return _native_g17.stores_covering(code, base, target)


# Store encodings understood by census_g17_member_writes, keyed by the opcode
# bits that fix the access width. The unsigned-offset forms scale imm12.
CENSUS_UNSIGNED_STORES = {
    0x39000000: 1, 0x79000000: 2, 0xB9000000: 4, 0xF9000000: 8,
    0x3D000000: 1, 0x7D000000: 2, 0xBD000000: 4, 0xFD000000: 8, 0x3D800000: 16,
}
# Signed imm9 forms. Bits 11:10 select unscaled (0), post-index (1),
# unprivileged (2) and pre-index (3) addressing.
CENSUS_IMM9_STORES = {
    0x38000000: 1, 0x78000000: 2, 0xB8000000: 4, 0xF8000000: 8,
    0x3C000000: 1, 0x7C000000: 2, 0xBC000000: 4, 0xFC000000: 8, 0x3C800000: 16,
}
CENSUS_REGISTER_STORES = {
    0x38200800: 1, 0x78200800: 2, 0xB8200800: 4, 0xF8200800: 8,
    0x3C200800: 1, 0x7C200800: 2, 0xBC200800: 4, 0xFC200800: 8, 0x3CA00800: 16,
}
CENSUS_PAIR_STORES: dict[int, tuple[int, str]] = {}
for _pair_opcode, _pair_width in (
    (0x28000000, 4), (0xA8000000, 8), (0x2C000000, 4), (0x6C000000, 8), (0xAC000000, 16)
):
    CENSUS_PAIR_STORES[_pair_opcode] = (_pair_width, "offset")  # STNP
    CENSUS_PAIR_STORES[_pair_opcode | 0x00800000] = (_pair_width, "post")
    CENSUS_PAIR_STORES[_pair_opcode | 0x01000000] = (_pair_width, "offset")
    CENSUS_PAIR_STORES[_pair_opcode | 0x01800000] = (_pair_width, "pre")
# Kernel routines that write memory through a pointer argument, with the
# argument registers holding the destination and the byte count.
CENSUS_MEMORY_WRITERS = {
    "_memcpy": (0, 2),
    "_memmove": (0, 2),
    "_memset": (0, 2),
    "_bzero": (0, 1),
    "___bzero": (0, 1),
}
# How far below a member an interior pointer may start and still be reported
# when it escapes into a call: a callee writing through a pointer to a
# neighbouring embedded object is then visible to the reviewer.
CENSUS_ESCAPE_WINDOW = 0x100


def _census_store(word: int) -> tuple[int, int, int, str] | None:
    """Decode a store addressed by base+immediate.

    Returns (base, immediate, bytes written, addressing) where addressing is
    "offset", "pre" or "post". Post-indexed stores write at the base itself.
    """

    width = CENSUS_UNSIGNED_STORES.get(word & 0xFFC00000)
    if width is not None:
        return (word >> 5) & 0x1F, ((word >> 10) & 0xFFF) * width, width, "offset"
    width = CENSUS_IMM9_STORES.get(word & 0xFFE00000)
    if width is not None:
        immediate = (word >> 12) & 0x1FF
        if immediate & 0x100:
            immediate -= 0x200
        form = ("offset", "post", "offset", "pre")[(word >> 10) & 3]
        return (word >> 5) & 0x1F, immediate, width, form
    pair = CENSUS_PAIR_STORES.get(word & 0xFFC00000)
    if pair is not None:
        width, form = pair
        immediate = (word >> 15) & 0x7F
        if immediate & 0x40:
            immediate -= 0x80
        return (word >> 5) & 0x1F, immediate * width, width * 2, form
    size = 1 << (word >> 30)
    if word & 0x3FFFFC00 in (0x089FFC00, 0x089F7C00):  # STLR, STLLR
        return (word >> 5) & 0x1F, 0, size, "offset"
    if word & 0x3FE07C00 == 0x08007C00:  # STXR, STLXR
        return (word >> 5) & 0x1F, 0, size, "offset"
    if word & 0xBFE00000 == 0x88200000:  # STXP, STLXP
        return (word >> 5) & 0x1F, 0, 16 if word & 0x40000000 else 8, "offset"
    if word & 0x3FA07C00 == 0x08A07C00:  # CAS
        return (word >> 5) & 0x1F, 0, size, "offset"
    if word & 0x3F200C00 == 0x38200000:  # LSE atomics and SWP
        return (word >> 5) & 0x1F, 0, size, "offset"
    return None


def _census_register_store(word: int) -> tuple[int, int, int, int] | None:
    """Decode STR [Xn, Rm{, extend #shift}] as (base, index, shift, width)."""

    width = CENSUS_REGISTER_STORES.get(word & 0xFFE00C00)
    if width is None:
        return None
    shift = (width.bit_length() - 1) if word & 0x1000 else 0
    return (word >> 5) & 0x1F, (word >> 16) & 0x1F, shift, width


def _census_written_registers(word: int) -> tuple[int, ...]:
    """General-purpose registers an instruction certainly writes.

    Only confident writers are reported: forgetting a derivation could hide a
    store, while keeping a stale one merely adds a spurious hit.
    """

    destination = word & 0x1F
    second = (word >> 10) & 0x1F
    if word & 0x1C000000 == 0x10000000:  # data processing, immediate
        if word & 0x1F000000 == 0x11000000 and word & 0x20000000 and destination == 31:
            return ()  # CMP/CMN immediate
        if word & 0x1F800000 == 0x12000000 and word & 0x60000000 == 0x60000000 and destination == 31:
            return ()  # TST immediate
        return () if destination == 31 else (destination,)
    if word & 0x0E000000 == 0x0A000000:  # data processing, register
        if word & 0x3FE00000 == 0x3A400000:
            return ()  # CCMP/CCMN
        if word & 0x1F000000 in (0x0A000000,) and word & 0x60000000 == 0x60000000 and destination == 31:
            return ()  # TST shifted register
        if word & 0x1F000000 == 0x0B000000 and word & 0x20000000 and destination == 31:
            return ()  # CMP/CMN register
        return () if destination == 31 else (destination,)
    if word & 0x0A000000 == 0x08000000:  # loads and stores
        vector = bool(word & 0x04000000)
        if word & 0x3B000000 == 0x18000000:  # load literal
            return () if vector or word & 0xC0000000 == 0xC0000000 else (destination,)
        if word & 0x3A000000 == 0x28000000:  # pairs
            if not word & 0x00400000 or vector:
                return ()
            return (destination, second)
        if word & 0x3F000000 == 0x08000000:  # exclusive and ordered
            status = (word >> 16) & 0x1F
            if word & 0x3FA07C00 == 0x08A07C00 or word & 0xBFA07C00 == 0x08207C00:
                return (status,)  # CAS/CASP return the old value in Rs
            if word & 0x00400000:  # loads
                return (destination,) if not word & 0x00200000 else (destination, second)
            if word & 0x3FE07C00 == 0x08007C00 or word & 0xBFE00000 == 0x88200000:
                return (status,)
            return ()
        if word & 0x3B000000 in (0x38000000, 0x39000000):
            if vector:
                return ()
            if word & 0x3F200C00 == 0x38200000:  # LSE atomics return the old value
                return () if destination == 31 else (destination,)
            opc = (word >> 22) & 3
            if opc == 0:
                return ()
            if opc == 2 and word >> 30 == 3:
                return ()  # PRFM
            return (destination,)
        return ()
    if word & 0x1C000000 == 0x14000000:  # branches and system
        if word & 0xFFF00000 == 0xD5300000:  # MRS
            return (destination,)
        return ()
    if word & 0x5F20FC00 == 0x1E200000:  # FP/integer conversion
        if (word >> 16) & 7 in (0, 1, 4, 5, 6):
            return (destination,)
        return ()
    if word & 0xBFE0FC00 in (0x0E003C00, 0x0E002C00):  # UMOV, SMOV
        return (destination,)
    return ()


def _census_is_call(word: int) -> bool:
    return (
        word & 0xFC000000 == 0x94000000  # BL
        or word & 0xFFFFFC1F == 0xD63F0000  # BLR
        or word & 0xFFFFF81F == 0xD63F081F  # BLRAAZ, BLRABZ
        or word & 0xFFFFF800 == 0xD73F0800  # BLRAA, BLRAB
    )


def _census_writeback(word: int) -> tuple[int, int] | None:
    """Base register and increment of a pre- or post-indexed load or store."""

    if word & 0x3B200000 == 0x38000000 and (word >> 10) & 3 in (1, 3):
        immediate = (word >> 12) & 0x1FF
        if immediate & 0x100:
            immediate -= 0x200
        return (word >> 5) & 0x1F, immediate
    if word & 0x3A000000 == 0x28000000 and (word >> 23) & 3 in (1, 3):
        width = 4 << ((word >> 31) & 1)
        if word & 0x04000000:
            width = 4 << ((word >> 30) & 3)
        immediate = (word >> 15) & 0x7F
        if immediate & 0x40:
            immediate -= 0x80
        return (word >> 5) & 0x1F, immediate * width
    return None


def census_g17_member_writes(
    image: bytes, low: int, high: int, kernel_symbols: dict[str, int]
) -> dict[str, list[dict[str, object]]]:
    """Run census_g17_code_member_writes over the image's __TEXT_EXEC."""

    symbols = macho_symbols(image)
    ordered = sorted((address, name) for name, address in symbols.items())
    memory_writers = {
        kernel_symbols[name]: (name, arguments)
        for name, arguments in CENSUS_MEMORY_WRITERS.items()
        if name in kernel_symbols
    }
    for item in load_commands(image):
        if item.command != LC_SEGMENT_64:
            continue
        segment = parse_segment(image, item)
        if segment.name == "__TEXT_EXEC":
            code = image[segment.file_offset : segment.file_offset + segment.file_size]
            return census_g17_code_member_writes(
                code, segment.virtual_address, ordered, low, high, memory_writers
            )
    raise ValueError("Mach-O has no __TEXT_EXEC segment")


def census_g17_code_member_writes(
    code: bytes,
    code_address: int,
    ordered: list[tuple[int, str]],
    low: int,
    high: int,
    memory_writers: dict[int, tuple[str, tuple[int, int]]],
) -> dict[str, list[dict[str, object]]]:
    """Every instruction in __TEXT_EXEC that can write bytes [low, high).

    The census is relative to an object pointer of unknown identity, so it
    reports writes to that member of *any* object; the caller classifies each
    one. A store counts when either its raw base+immediate, or its immediate
    plus an interior-pointer offset tracked from an earlier ADD, reaches the
    range. Tracking follows ADD/SUB immediate, ADD of a MOVZ/MOVK constant,
    register moves and pre/post-index writeback. It is reset at every symbol,
    after calls for the caller-saved registers, and whenever a register is
    certainly overwritten. Each hit carries the pointer's origin: `argN` when
    the base is still derived from argument register N at function entry
    (arg0 is `this` for a C++ method), otherwise `unknown`. ADRP-derived
    (global) and SP-derived bases are reported separately or skipped.

    Calls are checked too: memcpy/memmove/memset/bzero into an interior
    pointer whose constant length reaches the range (bzero, and memset of a
    constant zero, are marked as clearing only), and any interior pointer
    within CENSUS_ESCAPE_WINDOW below the range passed to another call.
    Register-indexed stores and memory-routine calls through an untracked
    base pointer cannot be bounded statically; they are only counted.
    """

    result: dict[str, list[dict[str, object]]] = {
        "stores": [],
        "global_stores": [],
        "memory_routines": [],
        "escapes": [],
    }
    unbounded = {"register_indexed_stores": 0, "untracked_memory_routines": 0}
    result["unbounded_sites"] = []

    def overlaps(start: int, length: int) -> bool:
        return start < high and low < start + length

    def entry_state() -> dict[int, tuple]:
        return {argument: ("offset", 0, f"arg{argument}") for argument in range(8)}

    owner_index = -1
    state: dict[int, tuple] = {}
    for offset, word in words(code):
        address = code_address + offset
        advanced = False
        while owner_index + 1 < len(ordered) and ordered[owner_index + 1][0] <= address:
            owner_index += 1
            advanced = True
        if advanced:
            state = entry_state()
        owner, owner_address = (
            (ordered[owner_index][1], ordered[owner_index][0])
            if owner_index >= 0
            else ("", code_address)
        )

        def site(kind: str, **extra: object) -> dict[str, object]:
            return {
                "symbol": owner,
                "offset": address - owner_address,
                "word": word,
                "kind": kind,
                **extra,
            }

        def pointer(register: int) -> tuple:
            if register == 31:
                return ("stack",)
            return state.get(register, ("offset", 0, "unknown"))

        def write_back() -> None:
            writeback = _census_writeback(word)
            if writeback is None or writeback[0] == 31:
                return
            base, amount = writeback
            origin = pointer(base)
            if origin[0] == "offset":
                state[base] = ("offset", origin[1] + amount, origin[2])

        store = _census_store(word)
        if store is not None:
            base, immediate, width, form = store
            effective = 0 if form == "post" else immediate
            origin = pointer(base)
            if origin[0] in ("absolute", "constant"):
                if overlaps(effective, width):
                    result["global_stores"].append(site("global", bytes=width))
            elif origin[0] == "offset":
                # Check the raw immediate as well as the tracked offset: a
                # stale derivation then only adds a spurious hit.
                for start, derived in ((origin[1] + effective, True), (effective, False)):
                    if derived and origin[1] == 0:
                        continue
                    if overlaps(start, width):
                        result["stores"].append(
                            site(
                                "store",
                                member=start,
                                bytes=width,
                                origin=origin[2] if derived or origin[1] == 0 else "unknown",
                                derived=derived,
                            )
                        )
                        break
            write_back()
            for register in _census_written_registers(word):
                state.pop(register, None)
            continue

        indexed = _census_register_store(word)
        if indexed is not None:
            base, index, shift, width = indexed
            origin = pointer(base)
            known = state.get(index)
            if origin[0] == "offset" and known and known[0] == "constant":
                start = origin[1] + (known[1] << shift)
                if overlaps(start, width):
                    result["stores"].append(
                        site("store", member=start, bytes=width, origin=origin[2], derived=True)
                    )
            elif origin[0] == "offset" and origin[1] != 0:
                if low - CENSUS_ESCAPE_WINDOW <= origin[1] < high:
                    result["stores"].append(
                        site(
                            "indexed_store",
                            member=origin[1],
                            bytes=width,
                            origin=origin[2],
                            derived=True,
                        )
                    )
            elif origin[0] == "offset":
                unbounded["register_indexed_stores"] += 1
                result["unbounded_sites"].append(
                    site("indexed_store", origin=origin[2], index=index)
                )
            continue

        if _census_is_call(word):
            target = decode_bl_target(address, word)
            if target in memory_writers:
                name, (destination, length) = memory_writers[target]
                origin = pointer(destination)
                count = state.get(length)
                clears = name in ("_bzero", "___bzero") or (
                    name == "_memset" and state.get(1) == ("constant", 0)
                )
                if origin[0] == "offset":
                    start = origin[1]
                    if count and count[0] == "constant":
                        if overlaps(start, count[1]):
                            result["memory_routines"].append(
                                site(
                                    "memory_routine",
                                    routine=name,
                                    member=start,
                                    bytes=count[1],
                                    origin=origin[2],
                                    clears_only=clears,
                                )
                            )
                    elif start != 0 and start < high:
                        result["memory_routines"].append(
                            site(
                                "memory_routine",
                                routine=name,
                                member=start,
                                bytes=None,
                                origin=origin[2],
                                clears_only=clears,
                            )
                        )
                    else:
                        unbounded["untracked_memory_routines"] += 1
                        result["unbounded_sites"].append(
                            site("memory_routine", routine=name, origin=origin[2])
                        )
            else:
                for argument in range(8):
                    origin = state.get(argument)
                    if (
                        origin
                        and origin[0] == "offset"
                        and origin[1] != 0
                        and low - CENSUS_ESCAPE_WINDOW <= origin[1] < high
                    ):
                        result["escapes"].append(
                            site(
                                "escape",
                                member=origin[1],
                                argument=argument,
                                origin=origin[2],
                                target=target,
                            )
                        )
            for register in list(range(19)) + [30]:
                state.pop(register, None)
            continue

        written = _census_written_registers(word)
        write_back()
        if not written:
            continue
        destination = written[0]
        update: tuple | None = None
        if decode_adrp(address, word) is not None or word & 0x9F000000 == 0x10000000:
            update = ("absolute",)
        elif word & 0xFF000000 in (0x91000000, 0xD1000000):  # ADD/SUB Xd, Xn, #imm
            source = (word >> 5) & 0x1F
            amount = ((word >> 10) & 0xFFF) << (12 if word & 0x00400000 else 0)
            if word & 0x40000000:
                amount = -amount
            origin = pointer(source)
            if origin[0] == "offset":
                update = ("offset", origin[1] + amount, origin[2])
            elif origin[0] == "constant":
                update = ("constant", (origin[1] + amount) & UINT64_MASK_CENSUS)
            else:
                update = origin
        elif word & 0xFFE0FFE0 == 0xAA0003E0:  # MOV Xd, Xm
            update = state.get((word >> 16) & 0x1F, ("offset", 0, "unknown"))
        elif word & 0xFF200000 == 0x8B000000 or word & 0xFFE00000 == 0x8B200000:
            first = pointer((word >> 5) & 0x1F)
            other = state.get((word >> 16) & 0x1F)
            if word & 0xFF200000 == 0x8B000000:
                shift_kind = (word >> 22) & 3
                shift = (word >> 10) & 0x3F
            else:
                shift_kind = 0
                shift = (word >> 10) & 7
            if other and other[0] == "constant" and shift_kind == 0 and first[0] == "offset":
                amount = (other[1] << shift) & UINT64_MASK_CENSUS
                update = ("offset", first[1] + amount, first[2])
        else:
            move = decode_move_wide(word)
            if move is not None:
                kind, register, immediate, shift = move
                if kind == "movz":
                    update = ("constant", immediate << shift)
                elif kind == "movn":
                    update = ("constant", ~(immediate << shift) & UINT64_MASK_CENSUS)
                else:
                    prior = state.get(register)
                    if prior and prior[0] == "constant":
                        update = (
                            "constant",
                            (prior[1] & ~(0xFFFF << shift)) | (immediate << shift),
                        )
            else:
                move_w = decode_movz_w(word)
                update_w = decode_movk_w(word)
                if move_w is not None:
                    update = ("constant", move_w[1])
                elif update_w is not None:
                    prior = state.get(update_w[0])
                    if prior and prior[0] == "constant":
                        immediate, shift = update_w[1], update_w[2]
                        update = (
                            "constant",
                            (prior[1] & 0xFFFFFFFF & ~(0xFFFF << shift))
                            | (immediate << shift),
                        )
                elif word & 0xFFE0FFE0 == 0x2A0003E0:  # MOV Wd, Wm
                    prior = state.get((word >> 16) & 0x1F)
                    if prior and prior[0] == "constant":
                        update = ("constant", prior[1] & 0xFFFFFFFF)
                elif word == 0x2A1F03E0 | destination or word == 0xAA1F03E0 | destination:
                    update = ("constant", 0)  # MOV Rd, ZR
        for register in written:
            state.pop(register, None)
        if update is not None and destination != 31:
            state[destination] = update

    result["unbounded"] = [unbounded]
    return result


UINT64_MASK_CENSUS = 0xFFFFFFFFFFFFFFFF


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
    return _native_g17.decode("decode_orr_register", word=word)


def decode_ldr_q(word: int) -> tuple[int, int, int] | None:
    return _native_g17.decode("decode_ldr_q", word=word)


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
    return _native_g17._query(image, 'recover_g17_command_stream_format')


def recover_g17_render_payload_format(image: bytes) -> dict[str, object]:
    return _native_g17._query(image, 'recover_g17_render_payload_format')


def recover_g17_3d_common_passthrough(image: bytes) -> dict[str, object]:
    return _native_g17._query(image, 'recover_g17_3d_common_passthrough')


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
    return _native_g17._query(image, 'recover_g17_render_descriptor_fields', iogpu=iogpu.hex(), render_payload_text=json.dumps(render_payload))


def recover_g17_ta_render_passthrough(image: bytes) -> dict[str, object]:
    return _native_g17._query(image, 'recover_g17_ta_render_passthrough')


def recover_g17_3d_descriptor_initialization(image: bytes) -> dict[str, object]:
    return _native_g17._query(image, 'recover_g17_3d_descriptor_initialization')


def recover_g17_channel_command_common_fields(image: bytes) -> dict[str, object]:
    return _native_g17._query(image, 'recover_g17_channel_command_common_fields')


def recover_g17_register_entry_codec(image: bytes) -> dict[str, object]:
    return _native_g17._query(image, 'recover_g17_register_entry_codec')


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
    return _native_g17._query(image, 'recover_g17_register_selectors')


def recover_g17_inline_register_records(image: bytes) -> dict[str, object]:
    return _native_g17._query(image, 'recover_g17_inline_register_records')


def build_g17_emission_cfg(
    instructions: list[tuple[int, int]], event_offsets: set[int]
) -> dict[str, object]:
    return _native_g17._query(b"", 'build_g17_emission_cfg', instructions=instructions, event_offsets=list(event_offsets))


def recover_g17_register_emission_cfg(
    image: bytes,
    selectors: dict[str, object],
    inline_records: dict[str, object],
) -> dict[str, object]:
    return _native_g17._query(image, 'recover_g17_register_emission_cfg', selectors=selectors, inline_records=inline_records)


def recover_g17_3d_register_lists(image: bytes) -> dict[str, object]:
    return _native_g17._query(image, 'recover_g17_3d_register_lists')


def recover_g17_channel_command_pools(image: bytes) -> dict[str, object]:
    return _native_g17._query(image, 'recover_g17_channel_command_pools')


def recover_g17_command_pool_backing(image: bytes) -> dict[str, object]:
    return _native_g17._query(image, 'recover_g17_command_pool_backing')


def recover_g17_3d_command_reclamation(image: bytes) -> dict[str, object]:
    return _native_g17._query(image, 'recover_g17_3d_command_reclamation')


def recover_g17_queue_device_inputs(
    driver: bytes, iogpu: bytes
) -> dict[str, object]:
    return _native_g17._query(driver, 'recover_g17_queue_device_inputs', iogpu=iogpu.hex())


def recover_g17_channel_runtime_resources(
    driver: bytes, iogpu: bytes
) -> dict[str, object]:
    return _native_g17._query(driver, 'recover_g17_channel_runtime_resources', iogpu=iogpu.hex())


def recover_g17_scheduler_state(image: bytes) -> dict[str, object]:
    return _native_g17._query(image, 'recover_g17_scheduler_state')


def recover_g17_channel_state_sources(image: bytes, reset_code: bytes) -> dict[str, object]:
    return _native_g17._query(image, 'recover_g17_channel_state_sources', reset_code=reset_code.hex())


def recover_g17_channel_data_master_types(image: bytes) -> dict[str, object]:
    return _native_g17._query(image, 'recover_g17_channel_data_master_types')


def recover_g17_channel_identity(driver: bytes, iogpu: bytes) -> dict[str, object]:
    return _native_g17._query(driver, 'recover_g17_channel_identity', iogpu=iogpu.hex())


def recover_g17_handoff(code: bytes) -> dict[str, object]:
    return _native_g17._query(code, 'recover_g17_handoff')


def recover_g17_boot_transport(
    notify_code: bytes, receive_code: bytes, boot_code: bytes
) -> dict[str, object]:
    return _native_g17._query(b"", 'recover_g17_boot_transport', notify_code=notify_code.hex(), receive_code=receive_code.hex(), boot_code=boot_code.hex())


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
    driver: bytes, iogpu: bytes, iosurface: bytes
) -> dict[str, object]:
    """Recover the role-local ring consumed by callback interrupt index 4."""

    symbols = macho_symbols(driver)
    iogpu_symbols = macho_symbols(iogpu)
    iosurface_symbols = macho_symbols(iosurface)
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
        IOGPU_WEAK_NAMESPACE_GET_OBJECT,
        IOGPU_WEAK_NAMESPACE_REMOVE_OBJECT,
    ):
        if name not in iogpu_symbols:
            raise ValueError(f"IOGPUFamily Mach-O has no {name} symbol")
    if IOSURFACE_ROOT_SIGNAL_EVENT_ID not in iosurface_symbols:
        raise ValueError(
            f"IOSurface Mach-O has no {IOSURFACE_ROOT_SIGNAL_EVENT_ID} symbol"
        )

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
        iosurface_symbols,
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


def recover_g17_pm_memory_event_action(
    driver: bytes,
    role_address: int,
    role_code: bytes,
    dispatch_offsets: tuple[int, ...],
    driver_symbols: dict[str, int],
) -> dict[str, object]:
    """Recover the complete host dispatch contract for firmware event type 6."""

    required = (
        ALLOCATE_PM_MEMORY_EVENT,
        ACCELERATOR_SUBMIT_DEVICE_CONTROL,
        ARM_SUBMIT_DEVICE_CONTROL,
        SUBMIT_DEVICE_CONTROL,
        HWPB_MANAGER_META_CLASS,
        PARAMETER_MANAGEMENT_GROW,
        PARAMETER_MANAGEMENT_VIRTUAL_GROW,
    )
    missing = [name for name in required if name not in driver_symbols]
    if missing:
        raise ValueError(f"Mach-O is missing G17 PM-memory symbols: {missing}")

    # The interrupt path validates the five-field payload, copies it into a
    # private eight-entry/32-byte host ring, and wakes the allocation worker.
    # It deliberately does not allocate from interrupt context.
    # Type 6 first passes through the role-independent accelerator guard at
    # +0xa0; the actual typed arm starts at +0xaf0 when that guard is clear.
    if 0x110 + dispatch_offsets[6] != 0x0A0:
        raise ValueError("G17 PM-memory event dispatch changed")
    require_instruction_words_at(
        role_code,
        "G17 PM-memory event",
        {
            0xAF0: 0xB94053E8,  # event type at entry +0
            0xAF4: 0x7100191F,  # event type 6
            0xAFC: 0xB94057F6,  # signed stamp slot at entry +4
            0xB14: 0xD2815611,  # stamp-count vtable slot 0xab0
            0xB44: 0xB9405BF6,  # manager index at entry +8
            0xB48: 0x7101FEDF,  # manager index below 0x7f
            0xB50: 0xB94063F7,  # request kind at entry +0x10
            0xB54: 0x710102FF,  # request kind below 0x40
            0xB5C: 0xB94057FA,
            0xB60: 0xB9405FFB,  # request value at entry +0x0c
            0xB64: 0xF84643F9,  # unaligned token at entry +0x14
            0xB68: 0xF9414E7C,  # firmware +0x298 -> accelerator
            0xB6C: 0x52935D08,
            0xB70: 0x72A00028,  # host ring control at accelerator +0x19ae8
            0xBB8: 0x8B080388,  # entries at accelerator +0x199e8
            0xBD8: 0xF900015F,  # record +0 = 0
            0xBDC: 0x29016956,  # entry +8, entry +4 -> record +8
            0xBE0: 0x29025D5B,  # entry +0xc, entry +0x10 -> record +0x10
            0xBE4: 0xF9000D59,  # entry +0x14 -> record +0x18
            0xBF0: 0x12000908,  # eight-entry host-ring wrap
            0xC00: 0xF9414E68,
            0xC04: 0xF9423500,  # allocation event source at accelerator +0x468
            0xC2C: 0x9107E208,
            0xC30: 0xF940FE09,  # signal-work-available vtable slot 0x1f8
        },
    )

    # start() binds the exact worker to the event source retained at +0x468.
    start_address, start_code = symbol_code(driver, ACCELERATOR_START)
    require_instruction_words_at(
        start_code,
        "G17 PM-memory worker registration",
        {
            0x3850: 0xD2825EF1,
            0x3854: 0xDAC10230,
            0x3858: 0xAA1003E1,
            0x385C: 0xAA1303E0,
            0x3860: 0xD2800002,
            0x3864: 0x52800003,
            0x386C: 0xF9023660,  # event source -> accelerator +0x468
        },
    )
    registered_worker = read_adrp_add_address(
        start_address, start_code, 0x3848, 0x384C
    )
    if registered_worker != driver_symbols[ALLOCATE_PM_MEMORY_EVENT]:
        raise ValueError("G17 PM-memory event source worker changed")

    worker_address, worker_code = symbol_code(driver, ALLOCATE_PM_MEMORY_EVENT)
    require_instruction_words_at(
        worker_code,
        "G17 PM-memory allocation worker",
        {
            0x028: 0x91406408,
            0x02C: 0x912BA119,  # host ring control +0x19ae8
            0x060: 0x9100E3E8,
            0x064: 0x6F00E400,
            0x068: 0xAD010100,  # zero device-control bytes +0x20..+0x3f
            0x06C: 0x52800108,  # command type 8
            0x070: 0x29075FE8,  # command type and request kind at +0/+4
            0x074: 0x3CC082A0,  # host request +8..+0x17
            0x078: 0x3C8403E0,  # -> device control +8..+0x17
            0x07C: 0xF9400EA8,  # host request +0x18
            0x080: 0xF9002BE8,  # -> device control +0x18
            0x088: 0x52800328,  # submission flags 0x19
            0x0E4: 0x9107A208,  # firmware submit callback slot 0x1e8
            0x0E8: 0xF940F609,
            0x0FC: 0xAA1003E1,  # callback argument
            0x100: 0x9100E3E2,  # complete 0x40-byte device-control entry
            0x104: 0xD10153A3,  # flags/result word
            0x108: 0xD10163A4,  # completion index
            0x17C: 0xB94002A8,  # private host record discriminator
            0x180: 0x35000E48,  # nonzero records are rejected
            0x1C0: 0xB9400AB6,  # manager index from host record +8
            0x210: 0xAA1703E0,
            0x21C: 0x94C9D252,  # OSMetaClassBase::safeMetaCast
            0x24C: 0xF9404ED8,  # parameter manager at HWPB manager +0x98
            0x250: 0xF9409B00,  # its lock at +0x130
            0x268: 0xD2803211,  # parameter-manager vtable slot 0x190
            0x27C: 0xD73F0910,
            0x280: 0xAA0003F7,  # growImmediately result
        },
    )
    callback = read_adrp_add_address(worker_address, worker_code, 0x0EC, 0x0F0)
    if callback != driver_symbols[ACCELERATOR_SUBMIT_DEVICE_CONTROL]:
        raise ValueError("G17 PM-memory device-control callback changed")
    meta_class = read_adrp_add_address(worker_address, worker_code, 0x214, 0x218)
    if meta_class != driver_symbols[HWPB_MANAGER_META_CLASS]:
        raise ValueError("G17 PM-memory manager class changed")

    callback_address, callback_code = symbol_code(
        driver, ACCELERATOR_SUBMIT_DEVICE_CONTROL
    )
    require_instruction_words_at(
        callback_code,
        "G17 accelerator device-control callback",
        {
            0x058: 0xF942DAC0,  # selected firmware object
            0x06C: 0xF9400010,  # firmware vtable
            0x070: 0xAA0003F1,
            0x074: 0xF2F9B431,
            0x078: 0xDAC11A30,  # authenticate vtable
            0x07C: 0xD2805011,  # submitDeviceControl slot 0x280
            0x080: 0x8B110210,
            0x084: 0xF9400208,
            0x090: 0xAA1403E1,  # complete device-control entry
            0x094: 0xAA1303E3,  # result word
            0x0B4: 0xAA0403F1,
            0x0BC: 0xD71F0A11,  # authenticated tail call
        },
    )
    if callback_address != driver_symbols[ACCELERATOR_SUBMIT_DEVICE_CONTROL]:
        raise ValueError("G17 accelerator device-control callback symbol moved")

    physical_grow = recover_vtable_target(driver, PARAMETER_MANAGEMENT_VTABLE, 0x190)
    virtual_grow = recover_vtable_target(
        driver, PARAMETER_MANAGEMENT_VIRTUAL_VTABLE, 0x190
    )
    if physical_grow != driver_symbols[PARAMETER_MANAGEMENT_GROW]:
        raise ValueError("G17 physical parameter-memory grow action changed")
    if virtual_grow != driver_symbols[PARAMETER_MANAGEMENT_VIRTUAL_GROW]:
        raise ValueError("G17 virtual parameter-memory grow action changed")

    # The callback resolves through the selected firmware vtable to the ARM
    # submitter. Its command-to-role table sends type 8 through role zero, and
    # flags 0x19 produce one 0x84/0x11 doorbell with the wait bit set.
    arm_target = recover_vtable_target(driver, G17_FIRMWARE_VTABLE, 0x280)
    if arm_target != driver_symbols[ARM_SUBMIT_DEVICE_CONTROL]:
        raise ValueError("G17 PM-memory device-control submitter changed")
    arm_address, arm_code = symbol_code(driver, ARM_SUBMIT_DEVICE_CONTROL)
    require_instruction_words_at(
        arm_code,
        "G17 PM-memory device-control submission",
        {
            0x02C: 0xB9400038,  # command discriminator
            0x030: 0x36180102,  # flags bit 3 enables type-8 token check
            0x034: 0x7100231F,
            0x03C: 0xF9414E88,
            0x040: 0xF9434508,  # expected token at accelerator +0x688
            0x044: 0xF9400C29,  # submitted token at command +0x18
            0x048: 0xEB09011F,
            0x068: 0xD37EF709,  # command type * 4
            0x080: 0xB940015A,  # role selected by the table
            0x134: 0x12000668,  # flags & 3 requests a doorbell
            0x138: 0x34000508,
            0x13C: 0x52833B08,
            0x140: 0x8B080294,  # transports at firmware +0x19d8
            0x160: 0x53041273,  # flags bit 4 -> synchronous/wait argument
            0x178: 0xD2811511,  # transport slot 0x8a8
            0x184: 0xD2800221,
            0x188: 0xF2E01081,  # doorbell 0x8400000000000011
            0x194: 0xD73F0910,
        },
    )
    base_call = struct.unpack_from("<I", arm_code, 0x08C)[0]
    if decode_bl_target(arm_address + 0x08C, base_call) != driver_symbols[
        SUBMIT_DEVICE_CONTROL
    ]:
        raise ValueError("G17 PM-memory base device-control submit target changed")
    role_table_address = read_adrp_add_address(arm_address, arm_code, 0x060, 0x064)
    # Command discriminators 0..57 are valid in this producer. The words
    # immediately following are a different constant table (100, 200, ...),
    # so do not accidentally absorb them into the role map.
    role_table = read_virtual_u32_table(driver, role_table_address, 58)
    if any(role > 1 for role in role_table) or role_table[8] != 0:
        raise ValueError("G17 PM-memory device-control role mapping changed")

    return {
        "type": 6,
        "record": "AGFIFirmwareEventPMRequestMemory",
        "stamp_slot_offset": 4,
        "invalid_stamp_slot": -1,
        "manager_index_offset": 8,
        "manager_index_limit": 0x7F,
        "request_value_offset": 0xC,
        "request_kind_offset": 0x10,
        "request_kind_limit": 0x40,
        "firmware_token_offset": 0x14,
        "firmware_token_bytes": 8,
        "interrupt_action": "enqueue_host_request_and_wake_worker",
        "host_request_ring": {
            "control_accelerator_member": 0x19AE8,
            "entries_accelerator_member": 0x199E8,
            "entries": 8,
            "entry_bytes": 0x20,
            "worker_event_source_accelerator_member": 0x468,
            "record_layout": {
                "discriminator_offset": 0,
                "discriminator": 0,
                "manager_index_offset": 8,
                "stamp_slot_offset": 0xC,
                "request_value_offset": 0x10,
                "request_kind_offset": 0x14,
                "firmware_token_offset": 0x18,
            },
        },
        "device_control_response": {
            "command_type": 8,
            "submission_flags": 0x19,
            "role": 0,
            "entry_bytes": 0x40,
            "request_kind_offset": 4,
            "copied_host_request_range": {
                "source_offset": 8,
                "target_offset": 8,
                "bytes": 0x18,
            },
            "zero_range": {"offset": 0x20, "bytes": 0x20},
            "token_check": {
                "entry_offset": 0x18,
                "accelerator_member": 0x688,
            },
            "doorbell": 0x8400000000000011,
            "doorbell_count": 1,
            "doorbell_wait_argument": 1,
        },
        "manager_class": "AGXHWParamBufferManager",
        "parameter_manager_member": 0x98,
        "host_action": "AGXParameterManagement::growImmediately",
        "host_action_vtable_slot": 0x190,
        "vinix_policy": "stop_gpu_without_parameter_memory_manager",
    }


def recover_g17_uma_flist_event_actions(
    driver: bytes,
    role_address: int,
    role_code: bytes,
    dispatch_offsets: tuple[int, ...],
    driver_symbols: dict[str, int],
) -> list[dict[str, object]]:
    """Recover G17 USC-private-memory FList completion/threshold events."""

    required = (
        USC_PRIV_MEM_FLIST_META_CLASS,
        IMPLICIT_GROW_ENGINE_VTABLE,
        USC_PRIV_MEM_RETIRE_GROW_REQUEST,
        G17_HAL_UPDATE_UMA_DESC,
    )
    missing = [name for name in required if name not in driver_symbols]
    if missing:
        raise ValueError(f"Mach-O is missing G17 UMA FList symbols: {missing}")

    dispatch_anchor = 0x110
    if dispatch_anchor + dispatch_offsets[13] != 0x624:
        raise ValueError("G17 UMA grow-completion dispatch changed")
    if dispatch_anchor + dispatch_offsets[15] != 0x2F0:
        raise ValueError("G17 UMA threshold dispatch changed")

    # Type 13 validates both non-null 64-bit payloads and the same dynamic
    # stamp namespace used by the other firmware completion records. It then
    # resolves the FList by its bounded 8-bit index and passes the trailing
    # result pair to the grow engine retained at FList +0x50.
    require_instruction_words_at(
        role_code,
        "G17 UMA grow-completion event",
        {
            0x628: 0xB94053E8,  # event type at +0
            0x62C: 0x7100351F,  # type 13
            0x634: 0xB9405BE8,  # FList index at +8
            0x638: 0x7104011F,  # below 256
            0x640: 0xF845C3E8,  # nonzero value at +0x0c
            0x644: 0xB4006E88,
            0x648: 0xF84643E8,  # nonzero value at +0x14
            0x64C: 0xB4006E48,
            0x650: 0xB94057F6,  # signed stamp slot at +4
            0x668: 0xD2815611,  # stamp-count vtable slot 0xab0
            0x698: 0xF846C3F9,  # grow result value at +0x1c
            0x69C: 0xB94077F6,  # grow result flags at +0x24
            0x6A0: 0x294AEBFB,  # stamp slot and FList index
            0x768: 0xAA1703E0,  # candidate FList
            0x778: 0xB4002D40,  # fail when the typed object is absent
            0x780: 0xF9402800,  # grow engine at FList +0x50
            0x794: 0xD2803011,  # grow-engine vtable slot 0x180
            0x7A0: 0xAA1B03E1,  # stamp slot
            0x7A4: 0xAA1A03E2,  # FList index
            0x7A8: 0xAA1903E3,  # result value
            0x7AC: 0xAA1603E4,  # result flags
            0x7B4: 0xD73F0910,
        },
    )
    grow_flist_class = read_adrp_add_address(
        role_address, role_code, 0x76C, 0x770
    )
    if grow_flist_class != driver_symbols[USC_PRIV_MEM_FLIST_META_CLASS]:
        raise ValueError("G17 UMA grow-completion FList class changed")

    retire_grow = recover_vtable_target(driver, IMPLICIT_GROW_ENGINE_VTABLE, 0x180)
    if retire_grow != driver_symbols[USC_PRIV_MEM_RETIRE_GROW_REQUEST]:
        raise ValueError("G17 UMA grow-completion action changed")

    # Type 15 looks up the same FList index. When its firmware threshold is
    # above the host's current value, Apple updates the descriptor through the
    # selected accelerator, then sends device-control command 0x21 carrying
    # the FList index. Vinix cannot emit that acknowledgement without owning
    # the FList state it describes.
    require_instruction_words_at(
        role_code,
        "G17 UMA threshold event",
        {
            0x2F4: 0xB94053E8,  # event type at +0
            0x2F8: 0x71003D1F,  # type 15
            0x300: 0xB94057F8,  # FList index at +4
            0x304: 0x7104031F,  # below 256
            0x30C: 0xF9414E7B,  # firmware +0x298 -> accelerator
            0x310: 0x91404F77,  # FList registry at accelerator +0x13000
            0x314: 0xF942DEFA,  # registry lock at +0x135b8
            0x320: 0xB945C2E8,  # registry count at +0x135c0
            0x32C: 0xF942E6E8,  # registry entries at +0x135c8
            0x810: 0xAA1603E0,  # candidate FList
            0x820: 0xB4001BE0,  # fail when the typed object is absent
            0x8CC: 0xB9401328,  # FList identity/index below 256
            0x8D0: 0x7104011F,
            0x908: 0xB9408329,  # current threshold at FList +0x80
            0x90C: 0xB940EB28,  # requested threshold at FList +0xe8
            0x924: 0xB9008328,  # publish the new host threshold
            0x938: 0xD2822411,  # accelerator vtable slot 0x1120
            0x944: 0xD102C3A2,  # descriptor-update record
            0x94C: 0xAA1903E1,  # FList argument
            0x968: 0xD102C3A8,
            0x96C: 0xF803811F,
            0x970: 0x6F00E400,
            0x974: 0x3C828100,
            0x978: 0x3C818100,
            0x97C: 0x3C808100,  # zero complete 0x40-byte response
            0x980: 0x52800428,  # device-control command 0x21
            0x984: 0x292A63A8,  # command and FList index at +0/+4
            0xA38: 0x94000329,  # optional synchronous completion wait
        },
    )
    threshold_flist_class = read_adrp_add_address(
        role_address, role_code, 0x814, 0x818
    )
    if threshold_flist_class != driver_symbols[USC_PRIV_MEM_FLIST_META_CLASS]:
        raise ValueError("G17 UMA threshold FList class changed")

    update_uma = recover_vtable_target(driver, G17_ACCELERATOR_VTABLE, 0x1120)
    if update_uma != driver_symbols[G17_HAL_UPDATE_UMA_DESC]:
        raise ValueError("G17 UMA threshold descriptor action changed")

    common = {
        "manager_class": "AGXUSCPrivMemFList",
        "flist_index_limit": 0x100,
        "vinix_policy": "stop_gpu_without_usc_private_memory_manager",
    }
    return [
        {
            **common,
            "type": 13,
            "record": "AGFIFirmwareEventUMAGrowPool",
            "stamp_slot_offset": 4,
            "invalid_stamp_slot": -1,
            "flist_index_offset": 8,
            "required_nonzero_u64_offsets": [0xC, 0x14],
            "grow_result_value_offset": 0x1C,
            "grow_result_flags_offset": 0x24,
            "grow_engine_member": 0x50,
            "host_action": "IAGXUSCPrivMemGrowEngine::retireGrowRequest",
            "host_action_vtable_slot": 0x180,
        },
        {
            **common,
            "type": 15,
            "record": "AGFIFirmwareEventUMAThresholdInterrupt",
            "flist_index_offset": 4,
            "current_threshold_member": 0x80,
            "requested_threshold_member": 0xE8,
            "host_action": "Accelerator::halUpdateUMADesc",
            "host_action_vtable_slot": 0x1120,
            "device_control_response": {
                "command_type": 0x21,
                "entry_bytes": 0x40,
                "flist_index_offset": 4,
                "zero_range": {"offset": 8, "bytes": 0x38},
            },
        },
    ]


def recover_g17_uma_async_alloc_event_action(
    driver: bytes,
    role_address: int,
    role_code: bytes,
    dispatch_offsets: tuple[int, ...],
    driver_symbols: dict[str, int],
) -> dict[str, object]:
    """Recover G17 event type 9 and prove its selected worker is a no-op."""

    if ALLOCATE_UMA_MEMORY_EVENT not in driver_symbols:
        raise ValueError("Mach-O is missing the G17 UMA allocation worker")
    if 0x110 + dispatch_offsets[9] != 0x47C:
        raise ValueError("G17 UMA async-allocation event dispatch changed")

    # The interrupt handler validates the packed request, then either waits
    # for room (when +0x1c is nonzero) or drops a full-ring request. A request
    # that fits is copied into a private 64-entry host ring before +0x470 is
    # signalled. Event +0x08 is not part of the copied host record.
    require_instruction_words_at(
        role_code,
        "G17 UMA async-allocation event",
        {
            0x47C: 0xD503249F,
            0x480: 0xF9414E68,  # firmware +0x298 -> accelerator
            0x484: 0x52952C09,
            0x488: 0x72A00029,  # disabled guard at accelerator +0x1a960
            0x490: 0x39400108,
            0x494: 0x35FFE148,  # a set guard consumes the event directly
            0x498: 0xB94053E8,  # event type at entry +0
            0x49C: 0x7100251F,  # event type 9
            0x4A4: 0xF845C3E8,  # required nonzero u64 at entry +0x0c
            0x4A8: 0xB4007B68,
            0x4AC: 0xB94057E8,  # request index at entry +0x04
            0x4B0: 0x7104011F,  # request index below 256
            0x4B4: 0x54007B02,
            0x4B8: 0xB94067F6,  # signed stamp slot at entry +0x14
            0x4D0: 0xD2815611,  # stamp-count vtable slot 0xab0
            0x4FC: 0x360078C8,
            0x500: 0xB94057F9,  # request index at entry +0x04
            0x504: 0xF845C3F7,  # required value at entry +0x0c
            0x508: 0xFC4643E9,  # packed value at entry +0x14
            0x50C: 0xB9406FF8,  # wait-for-room flag at entry +0x1c
            0x510: 0xF9414E7A,
            0x514: 0x91406B56,  # host-ring control at accelerator +0x1a2f0
            0x518: 0x34003A38,  # zero flag selects nonblocking full handling
            0x51C: 0xB942F6C8,
            0x520: 0x11000508,
            0x524: 0x12001508,  # 64-entry host-ring wrap
            0x528: 0xB942F2C9,
            0x52C: 0x6B09011F,
            0x534: 0x52800C80,  # wait 100 microseconds while full
            0xC5C: 0xB942F6C8,
            0xC60: 0x11000508,
            0xC64: 0x12001508,
            0xC68: 0xB942F2C9,
            0xC6C: 0x6B09011F,
            0xC70: 0x54FFA260,  # nonblocking mode drops a full-ring request
            0xC7C: 0x52935E08,
            0xC80: 0x72A00028,  # entries at accelerator +0x1a9af0
            0xC88: 0xB942F6C9,
            0xC8C: 0xD37BE929,  # 0x20-byte record stride
            0xCA4: 0x29007D59,  # entry +4 and zero -> record +0/+4
            0xCA8: 0xF9000557,  # entry +0x0c -> record +8
            0xCAC: 0xFD000949,  # entry +0x14 -> record +0x10
            0xCB0: 0x29037D58,  # entry +0x1c and zero -> record +0x18/+0x1c
            0xCB4: 0xB942F6C8,
            0xCB8: 0x11000508,
            0xCBC: 0x12001508,
            0xCC0: 0xB902F6C8,
            0xCCC: 0xF9414E68,
            0xCD0: 0xF9423900,  # UMA event source at accelerator +0x470
            0xCF8: 0x9107E208,
            0xCFC: 0xF940FE09,  # signal-work-available vtable slot 0x1f8
            0xD00: 0xD2800001,
            0xD04: 0xD2800002,
            0xD08: 0x52800003,
            0xD14: 0xD73F0931,
        },
    )

    # start() binds allocateUMAMemoryEvent to that exact +0x470 source. In
    # this UUID-pinned G17 binary the complete callback is only `bti c; ret`:
    # it neither drains the private queue nor allocates or acknowledges
    # anything. Preserve this surprising result as an executable assertion.
    start_address, start_code = symbol_code(driver, ACCELERATOR_START)
    require_instruction_words_at(
        start_code,
        "G17 UMA allocation worker registration",
        {
            0x38AC: 0xD2825EF1,
            0x38B0: 0xDAC10230,
            0x38B4: 0xAA1003E1,
            0x38B8: 0xAA1303E0,
            0x38BC: 0xD2800002,
            0x38C0: 0x52800003,
            0x38C8: 0xF9023A60,  # event source -> accelerator +0x470
        },
    )
    registered_worker = read_adrp_add_address(
        start_address, start_code, 0x38A4, 0x38A8
    )
    if registered_worker != driver_symbols[ALLOCATE_UMA_MEMORY_EVENT]:
        raise ValueError("G17 UMA allocation event source worker changed")
    worker_address, worker_code = symbol_code(driver, ALLOCATE_UMA_MEMORY_EVENT)
    if worker_address != driver_symbols[ALLOCATE_UMA_MEMORY_EVENT]:
        raise ValueError("G17 UMA allocation worker symbol moved")
    if worker_code != struct.pack("<2I", 0xD503245F, 0xD65F03C0):
        raise ValueError("G17 UMA allocation worker is no longer a no-op")

    return {
        "type": 9,
        "record": "AGFIFirmwareEventUMARequestMemory",
        "request_index_offset": 4,
        "request_index_limit": 0x100,
        "ignored_event_offsets": [8],
        "required_nonzero_u64_offset": 0xC,
        "stamp_slot_offset": 0x14,
        "invalid_stamp_slot": -1,
        "request_value_offset": 0x18,
        "wait_for_host_ring_offset": 0x1C,
        "disabled_guard_accelerator_member": 0x1A960,
        "interrupt_action": "enqueue_host_request_and_wake_worker",
        "host_request_ring": {
            "control_accelerator_member": 0x1A2F0,
            "entries_accelerator_member": 0x1A9AF0,
            "entries": 64,
            "entry_bytes": 0x20,
            "worker_event_source_accelerator_member": 0x470,
            "full_policy": {
                "wait_flag_offset": 0x1C,
                "wait_microseconds": 100,
                "zero_flag": "drop_request",
                "nonzero_flag": "wait_for_room",
            },
            "record_layout": {
                "request_index_offset": 0,
                "reserved_004": 0,
                "required_value_offset": 8,
                "stamp_and_request_value_offset": 0x10,
                "wait_for_host_ring_offset": 0x18,
                "reserved_01c": 0,
            },
        },
        "registered_worker": ALLOCATE_UMA_MEMORY_EVENT,
        "worker_implementation": "bti_c_ret",
        "device_control_response": "none",
        "vinix_policy": "validate_and_consume_without_private_host_queue",
    }


def recover_g17_firmware_event_actions(
    driver: bytes,
    role_address: int,
    role_code: bytes,
    dispatch_offsets: tuple[int, ...],
    driver_symbols: dict[str, int],
    iogpu_symbols: dict[str, int],
    iosurface_symbols: dict[str, int],
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
    pm_memory_event = recover_g17_pm_memory_event_action(
        driver, role_address, role_code, dispatch_offsets, driver_symbols
    )
    uma_async_alloc_event = recover_g17_uma_async_alloc_event_action(
        driver, role_address, role_code, dispatch_offsets, driver_symbols
    )
    uma_flist_events = recover_g17_uma_flist_event_actions(
        driver, role_address, role_code, dispatch_offsets, driver_symbols
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

    # Type 10 acknowledges an IOSurface shared-event signal. The record's
    # nonzero u64 ID is narrowed by IOSurfaceRoot::signalEventID(unsigned int),
    # which is a no-op when that ID has no registered IOSurfaceSharedEvent.
    # Vinix has no IOSurface registry and never emits this Apple-only command,
    # so consuming a validated completion matches the empty-registry path.
    if dispatch_anchor + dispatch_offsets[10] != role_address + 0x540:
        raise ValueError("G17 shared-event completion dispatch changed")
    require_instruction_words_at(
        role_code,
        "G17 shared-event signal completion",
        {
            0x544: 0xB94053E8,  # event type at entry +0
            0x548: 0x7100291F,  # event type 10
            0x54C: 0x54007BC1,
            0x550: 0xF84543E1,  # unaligned u64 event ID at entry +4
            0x554: 0xB4007601,  # event ID must be nonzero
            0x558: 0xB94067E8,  # pre-signal release flag at entry +0x14
            0x55C: 0x34000108,
            0x560: 0xF9414E68,  # firmware +0x298 -> accelerator
            0x564: 0x5286AA09,
            0x568: 0x72A00029,  # accelerator member 0x13550
            0x56C: 0x8B090108,
            0x570: 0xF9400108,
            0x574: 0x91003108,  # pointed object byte +0xc
            0x578: 0x089FFD15,  # release-store byte 1
            0x57C: 0xF9414E68,
            0x580: 0xF9407900,  # accelerator IOSurfaceRoot at +0xf0
        },
    )
    shared_event_call = struct.unpack_from("<I", role_code, 0x584)[0]
    if decode_bl_target(
        role_address + 0x584, shared_event_call
    ) != iosurface_symbols[IOSURFACE_ROOT_SIGNAL_EVENT_ID]:
        raise ValueError("G17 shared-event completion target changed")

    # Type 12 removes a process object from an IOGPUWeakNamespace. Apple
    # returns immediately when getObject() finds no entry. Vinix never creates
    # this Apple-only namespace, so its complete current path is the same
    # empty-namespace lifecycle acknowledgement.
    if dispatch_anchor + dispatch_offsets[12] != role_address + 0x6F4:
        raise ValueError("G17 process-exit completion dispatch changed")
    require_instruction_words_at(
        role_code,
        "G17 process-exit completion",
        {
            0x094: 0x5299701C,
            0x098: 0x72A0003C,  # accelerator weak namespace at +0x1cb80
            0x6F8: 0xB94053E8,  # event type at entry +0
            0x6FC: 0x7100311F,  # event type 12
            0x700: 0x54006DC1,
            0x704: 0xF9414E68,  # firmware +0x298 -> accelerator
            0x708: 0x8B1C0108,
            0x70C: 0xF9400100,  # weak namespace pointer
            0x710: 0xB4FFCD60,  # absent namespace returns to drain loop
            0x714: 0xF84543F9,  # unaligned u64 object ID at entry +4
            0x718: 0xAA1903E1,
            0x720: 0xAA0003F6,  # retain lookup result
            0x724: 0xF9414E68,
            0x728: 0x8B1C0108,
            0x72C: 0xF9400100,
            0x730: 0xAA1903E1,
            0x738: 0xB4FFCC36,  # missing object returns after removal
        },
    )
    process_get_call = struct.unpack_from("<I", role_code, 0x71C)[0]
    if decode_bl_target(
        role_address + 0x71C, process_get_call
    ) != iogpu_symbols[IOGPU_WEAK_NAMESPACE_GET_OBJECT]:
        raise ValueError("G17 process-exit namespace lookup target changed")
    process_remove_call = struct.unpack_from("<I", role_code, 0x734)[0]
    if decode_bl_target(
        role_address + 0x734, process_remove_call
    ) != iogpu_symbols[IOGPU_WEAK_NAMESPACE_REMOVE_OBJECT]:
        raise ValueError("G17 process-exit namespace removal target changed")

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
    implemented = {*effective_noops, 1, 4, 7, 8, 9, 10, 12, 14}
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
        "host_service_events": [
            {
                "type": 10,
                "record": "AGFIFirmwareEventSharedEventSignalComplete",
                "event_id_offset": 4,
                "event_id_bytes": 8,
                "event_id_nonzero": True,
                "pre_signal_release_flag_offset": 0x14,
                "host_action": "IOSurfaceRoot::signalEventID",
                "host_action_id_bits": 32,
                "vinix_policy": "consume_without_iosurface_registry",
            }
        ],
        "host_lifecycle_events": [
            {
                "type": 12,
                "record": "AGFIFirmwareEventProcessExitComplete",
                "object_id_offset": 4,
                "object_id_bytes": 8,
                "namespace_accelerator_member": 0x1CB80,
                "host_actions": [
                    "IOGPUWeakNamespace::getObject",
                    "IOGPUWeakNamespace::removeObject",
                ],
                "vinix_policy": "consume_without_iogpu_object_namespace",
            }
        ],
        "deferred_host_noop_events": [uma_async_alloc_event],
        "host_resource_events": [pm_memory_event, *uma_flist_events],
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
    return _native_g17._query(b"", 'recover_g17_rtbuddy_endpoints', read_code=read_code.hex(), send_code=send_code.hex(), matched_code=matched_code.hex(), enable_code=enable_code.hex(), received_code=received_code.hex())


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
        "--iosurface",
        type=Path,
        default=Path("build/kext/g17c/iokit.IOSurface.macho"),
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
        iosurface = args.iosurface.read_bytes()
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
            recover_g17_firmware_event_ring(driver, iogpu, iosurface)
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
        channels["accelerator_inputs"] = recover_g17_accelerator_channel_inputs(
            driver, kernel, iogpu, hardware_config["chip_info_decode"]
        )
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
