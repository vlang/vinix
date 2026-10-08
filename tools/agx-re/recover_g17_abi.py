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
    result = _native_g17._query(
        b"", 'recover_firmware_root',
        layout_options_text=json.dumps({
            'code': code.hex(),
        }))
    return result


def recover_driver_root(code: bytes) -> dict[str, object]:
    result = _native_g17._query(
        b"", 'recover_driver_root',
        layout_options_text=json.dumps({
            'code': code.hex(),
        }))
    return result


def recover_g17_bootstrap_roots(
    allocation_code: bytes,
    init_code: bytes,
    prepare_code: bytes,
    complete_code: bytes,
    page_shift_code: bytes,
) -> dict[str, object]:
    return _native_g17._query(b"", 'recover_g17_bootstrap_roots', allocation_code=allocation_code.hex(), init_code=init_code.hex(), prepare_code=prepare_code.hex(), complete_code=complete_code.hex(), page_shift_code=page_shift_code.hex())


def recover_firmware_allocations(image: bytes, address: int, code: bytes) -> list[dict[str, int]]:
    result = _native_g17._query(
        image, 'recover_firmware_allocations',
        layout_options_text=json.dumps({
            'address': address,
            'code': code.hex(),
        }))
    return result


def recover_root_allocation_sizes(allocations: list[dict[str, int]]) -> dict[str, int]:
    result = _native_g17._query(
        b"", 'recover_root_allocation_sizes',
        layout_options_text=json.dumps({
            'allocations': allocations,
        }))
    return result


def recover_hardware_config(
    allocations: list[dict[str, int]], shared_code: bytes, firmware: bytes
) -> dict[str, object]:
    result = _native_g17._query(
        b"", 'recover_hardware_config',
        layout_options_text=json.dumps({
            'allocations': allocations,
            'shared_code': shared_code.hex(),
            'firmware': firmware.hex(),
        }))
    return result


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
    result = _native_g17._query(
        b"", 'recover_direct_shared_publications',
        layout_options_text=json.dumps({
            'code': code.hex(),
        }))
    return [tuple(row) for row in result]


def recover_auxiliary_shared_publications(code: bytes) -> list[tuple[int, int, int]]:
    result = _native_g17._query(
        b"", 'recover_auxiliary_shared_publications',
        layout_options_text=json.dumps({
            'code': code.hex(),
        }))
    return [tuple(row) for row in result]


def recover_firmware_shared_data_layout(
    allocations: list[dict[str, int]], shared_code: bytes, base_code: bytes
) -> dict[str, object]:
    result = _native_g17._query(
        b"", 'recover_firmware_shared_data_layout',
        layout_options_text=json.dumps({
            'allocations': allocations,
            'shared_code': shared_code.hex(),
            'base_code': base_code.hex(),
        }))
    return result


def recover_firmware_shared_platform_fields(code: bytes) -> dict[str, object]:
    result = _native_g17._query(
        b"", 'recover_firmware_shared_platform_fields',
        layout_options_text=json.dumps({
            'code': code.hex(),
        }))
    return result


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
    result = _native_g17._query(
        b"", 'recover_driver_hardware_config_layout',
        layout_options_text=json.dumps({
            'base_init_code': base_init_code.hex(),
            'base_power_code': base_power_code.hex(),
            'arm_power_code': arm_power_code.hex(),
        }))
    return result


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

# Census entries that write +0x6d0..+0x6d7 of some *other* object, with the
# reason they cannot be the accelerator. Keys are (kind, symbol, offset).

# Escaped interior pointers are accepted by callee when the callee cannot write
# the word: event tokens, noreturn traps, IOGPUEvent members (0x40 bytes; the
# accelerator keeps an 8-byte deadline at +0x6c8, so none sits there) and the
# 8-byte deadline itself.
# Escapes through a virtual call, which the census cannot name, by site.

# Census entries writing accelerator +0xf7ec..+0xf7ff that are not the chip
# information override, with the reason they cannot change its final value.






def require_zeroed_accelerator_allocation(image: bytes, kernel_image: bytes) -> dict[str, object]:
    return _native_g17._query(image, 'require_zeroed_accelerator_allocation', legacy_options_text=json.dumps({'kernel_image': kernel_image.hex()}))


def recover_g17_accelerator_channel_inputs(
    image: bytes,
    kernel_image: bytes,
    iogpu_image: bytes,
    chip_info_decode: dict[str, object],
) -> dict[str, object]:
    return _native_g17._query(image, 'recover_g17_accelerator_channel_inputs', legacy_options_text=json.dumps({'kernel_image': kernel_image.hex(), 'iogpu_image': iogpu_image.hex(), 'chip_info_decode': chip_info_decode}))


def recover_g17_relative_boost_frequency_table(
    image: bytes, arm_power_code: bytes
) -> dict[str, object]:
    return _native_g17._query(image, 'recover_g17_relative_boost_frequency_table', arm_power_code=arm_power_code.hex())


def recover_g17_sram_power_scale_table(
    image: bytes, base_power_code: bytes, arm_power_code: bytes
) -> dict[str, object]:
    return _native_g17._query(image, 'recover_g17_sram_power_scale_table', base_power_code=base_power_code.hex(), arm_power_code=arm_power_code.hex())


def recover_g17_static_power_scale_table(
    image: bytes, kernel_image: bytes, arm_power_code: bytes
) -> dict[str, object]:
    return _native_g17._query(image, 'recover_g17_static_power_scale_table', kernel_image=kernel_image.hex(), arm_power_code=arm_power_code.hex())


def recover_g17_afr_relative_boost_frequency_table(
    image: bytes, arm_power_code: bytes
) -> dict[str, object]:
    return _native_g17._query(image, 'recover_g17_afr_relative_boost_frequency_table', arm_power_code=arm_power_code.hex())


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
def census_g17_member_writes(
    image: bytes, low: int, high: int, kernel_symbols: dict[str, int]
) -> dict[str, list[dict[str, object]]]:
    return _native_g17._query(
        image, "census_g17_member_writes", low=low, high=high,
        kernel_symbols=kernel_symbols,
    )


def census_g17_code_member_writes(
    code: bytes, code_address: int, ordered: list[tuple[int, str]],
    low: int, high: int, memory_writers: dict[int, tuple[str, tuple[int, int]]],
) -> dict[str, list[dict[str, object]]]:
    return _native_g17._query(
        b"", "census_g17_code_member_writes", code=code.hex(),
        code_address=code_address, ordered=ordered, low=low, high=high,
        memory_writer_pairs=list(memory_writers.items()),
    )


def recover_g17_perf_state_map_block(
    image: bytes, arm_power_code: bytes
) -> dict[str, object]:
    return _native_g17._query(image, 'recover_g17_perf_state_map_block', arm_power_code=arm_power_code.hex())


def recover_g17_aux_performance_layout(
    image: bytes, arm_power_code: bytes
) -> dict[str, object]:
    return _native_g17._query(image, 'recover_g17_aux_performance_layout', arm_power_code=arm_power_code.hex())


def recover_firmware_config_reads(firmware: bytes) -> dict[str, object]:
    result = _native_g17._query(
        b"", 'recover_firmware_config_reads',
        layout_options_text=json.dumps({
            'firmware': firmware.hex(),
        }))
    return result


def recover_device_control_ring_bindings(
    allocations: list[dict[str, int]], code: bytes
) -> list[dict[str, object]]:
    return _native_g17._query(b"", 'recover_device_control_ring_bindings', legacy_options_text=json.dumps({'allocations': allocations, 'code': code.hex()}))


def recover_ring_accessor(code: bytes) -> tuple[int, int]:
    return tuple(_native_g17._query(b"", 'recover_ring_accessor', legacy_options_text=json.dumps({'code': code.hex()})))


def recover_entry_stride(code: bytes) -> int:
    return _native_g17._query(b"", 'recover_entry_stride', legacy_options_text=json.dumps({'code': code.hex()}))


def recover_accelerator_command_fields(code: bytes) -> dict[str, dict[str, int]]:
    return _native_g17._query(b"", 'recover_accelerator_command_fields', legacy_options_text=json.dumps({'code': code.hex()}))


def recover_accelerator_command_contract(code: bytes) -> dict[str, object]:
    # This is the complete pinned G17C encoder, not just a sample of its
    # stores. In particular, it proves that the first qword is preserved.
    return _native_g17._query(b"", 'recover_accelerator_command_contract', legacy_options_text=json.dumps({'code': code.hex()}))


def recover_data_master_submission_sequence(
    code: bytes, command_type: int
) -> dict[str, object]:
    # The three producers have the same publication tail. The only changing
    # instruction is the immediate command type passed to the virtual encoder.
    return _native_g17._query(b"", 'recover_data_master_submission_sequence', legacy_options_text=json.dumps({'code': code.hex(), 'command_type': command_type}))


def recover_data_master_submission_protocol(
    image: bytes, next_entry_address: int
) -> dict[str, object]:
    return _native_g17._query(image, 'recover_data_master_submission_protocol', legacy_options_text=json.dumps({'next_entry_address': next_entry_address}))


def recover_g17_data_master_ring_bindings(
    allocations: list[dict[str, int]], init_code: bytes
) -> dict[str, object]:
    return _native_g17._query(b"", 'recover_g17_data_master_ring_bindings', allocations_text=json.dumps(allocations), init_code=init_code.hex())


def recover_g17_data_master_doorbells(image: bytes) -> dict[str, object]:
    return _native_g17._query(image, 'recover_g17_data_master_doorbells')


def recover_vector_copy_size(code: bytes) -> int:
    return _native_g17._query(b"", 'recover_vector_copy_size', legacy_options_text=json.dumps({'code': code.hex()}))


def recover_driver_accelerator_layouts(image: bytes) -> dict[str, object]:
    return _native_g17._query(image, 'recover_driver_accelerator_layouts', legacy_options_text=json.dumps({}))


def recover_g17_channel_pool_geometry(code: bytes) -> dict[str, object]:
    return _native_g17._query(b"", 'recover_g17_channel_pool_geometry', code=code.hex())


def recover_g17_channel_priority(image: bytes) -> dict[str, object]:
    return _native_g17._query(image, 'recover_g17_channel_priority')


def recover_g17_channel_submit_info(image: bytes) -> dict[str, object]:
    return _native_g17._query(image, 'recover_g17_channel_submit_info')


def recover_g17_channel_submission_flag(image: bytes) -> dict[str, object]:
    return _native_g17._query(image, 'recover_g17_channel_submission_flag')


def recover_g17_channel_layout(reset_code: bytes, write_code: bytes) -> dict[str, object]:
    return _native_g17._query(b"", 'recover_g17_channel_layout', reset_code=reset_code.hex(), write_code=write_code.hex())


def decode_orr_register(word: int) -> tuple[int, int, int] | None:
    return _native_g17.decode("decode_orr_register", word=word)


def decode_ldr_q(word: int) -> tuple[int, int, int] | None:
    return _native_g17.decode("decode_ldr_q", word=word)


def recover_g17_secondary_performance_block(image: bytes) -> dict[str, object]:
    return _native_g17._query(image, 'recover_g17_secondary_performance_block')


def config_pointer_stores(
    code: bytes, low: int, high: int
) -> list[dict[str, object]]:
    return _native_g17._query(b"", 'config_pointer_stores', code=code.hex(), bounds_text=json.dumps([low, high]))


def recover_g17_chip_info_registers(image: bytes) -> dict[str, object]:
    return _native_g17._integer_keys(_native_g17._query(image, 'recover_g17_chip_info_registers'))


def recover_g17_final_late_controls(image: bytes) -> dict[str, object]:
    return _native_g17._query(image, 'recover_g17_final_late_controls')


def recover_g17_remaining_late_controls(image: bytes) -> dict[str, object]:
    return _native_g17._integer_keys(_native_g17._query(image, 'recover_g17_remaining_late_controls'))


def recover_g17_cleared_accelerator_inputs(image: bytes) -> dict[str, object]:
    return _native_g17._integer_keys(_native_g17._query(image, 'recover_g17_cleared_accelerator_inputs'))


def recover_g17_unit_mask_field(image: bytes) -> dict[str, object]:
    return _native_g17._query(image, 'recover_g17_unit_mask_field')


def recover_g17_core_count_gate(image: bytes) -> dict[str, object]:
    return _native_g17._query(image, 'recover_g17_core_count_gate')


def recover_g17_chip_info_decode(image: bytes) -> dict[str, object]:
    return _native_g17._query(image, 'recover_g17_chip_info_decode')


def recover_g17_core_mask_relay(image: bytes) -> dict[str, object]:
    return _native_g17._query(image, 'recover_g17_core_mask_relay')


def recover_g17_late_controls(image: bytes) -> dict[str, object]:
    return _native_g17._integer_keys(_native_g17._query(image, 'recover_g17_late_controls'))


def recover_g17_command_stream_format(image: bytes) -> dict[str, object]:
    return _native_g17._query(image, 'recover_g17_command_stream_format')


def recover_g17_render_payload_format(image: bytes) -> dict[str, object]:
    return _native_g17._query(image, 'recover_g17_render_payload_format')


def recover_g17_3d_common_passthrough(image: bytes) -> dict[str, object]:
    return _native_g17._query(image, 'recover_g17_3d_common_passthrough')


def explain_g17_3d_common_boolean_accounting(
    render_payload: dict[str, object], common_passthrough: dict[str, object]
) -> dict[str, object]:
    return _native_g17._query(b"", 'explain_g17_3d_common_boolean_accounting', legacy_options_text=json.dumps({'render_payload': render_payload, 'common_passthrough': common_passthrough}))


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
    return _native_g17._query(driver, 'recover_g17_random_provider', legacy_options_text=json.dumps({'kernel': kernel.hex()}))


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
    return _native_g17._query(
        b"", 'g17_callback_interrupt_index',
        event_options_text=json.dumps({
            'interrupt_count': interrupt_count,
        }))


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
    return _native_g17._query(
        driver, 'recover_g17_akf_callback',
        event_options_text=json.dumps({
            'kernel': kernel.hex(),
        }))


def recover_g17_firmware_event_ring(
    driver: bytes, iogpu: bytes, iosurface: bytes
) -> dict[str, object]:
    """Recover the role-local ring consumed by callback interrupt index 4."""
    return _native_g17._query(
        driver, 'recover_g17_firmware_event_ring',
        event_options_text=json.dumps({
            'iogpu': iogpu.hex(),
            'iosurface': iosurface.hex(),
        }))


def recover_g17_pm_memory_event_action(
    driver: bytes,
    role_address: int,
    role_code: bytes,
    dispatch_offsets: tuple[int, ...],
    driver_symbols: dict[str, int],
) -> dict[str, object]:
    """Recover the complete host dispatch contract for firmware event type 6."""
    return _native_g17._query(
        driver, 'recover_g17_pm_memory_event_action',
        event_options_text=json.dumps({
            'role_address': role_address,
            'role_code': role_code.hex(),
            'dispatch_offsets': dispatch_offsets,
            'driver_symbols': driver_symbols,
            "dispatch_offsets_kind": "tuple" if isinstance(dispatch_offsets, tuple) else "list",
        }))


def recover_g17_uma_flist_event_actions(
    driver: bytes,
    role_address: int,
    role_code: bytes,
    dispatch_offsets: tuple[int, ...],
    driver_symbols: dict[str, int],
) -> list[dict[str, object]]:
    """Recover G17 USC-private-memory FList completion/threshold events."""
    return _native_g17._query(
        driver, 'recover_g17_uma_flist_event_actions',
        event_options_text=json.dumps({
            'role_address': role_address,
            'role_code': role_code.hex(),
            'dispatch_offsets': dispatch_offsets,
            'driver_symbols': driver_symbols,
            "dispatch_offsets_kind": "tuple" if isinstance(dispatch_offsets, tuple) else "list",
        }))


def recover_g17_uma_async_alloc_event_action(
    driver: bytes,
    role_address: int,
    role_code: bytes,
    dispatch_offsets: tuple[int, ...],
    driver_symbols: dict[str, int],
) -> dict[str, object]:
    """Recover G17 event type 9 and prove its selected worker is a no-op."""
    return _native_g17._query(
        driver, 'recover_g17_uma_async_alloc_event_action',
        event_options_text=json.dumps({
            'role_address': role_address,
            'role_code': role_code.hex(),
            'dispatch_offsets': dispatch_offsets,
            'driver_symbols': driver_symbols,
            "dispatch_offsets_kind": "tuple" if isinstance(dispatch_offsets, tuple) else "list",
        }))


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
    return _native_g17._query(
        driver, 'recover_g17_firmware_event_actions',
        event_options_text=json.dumps({
            'role_address': role_address,
            'role_code': role_code.hex(),
            'dispatch_offsets': dispatch_offsets,
            'driver_symbols': driver_symbols,
            'iogpu_symbols': iogpu_symbols,
            'iosurface_symbols': iosurface_symbols,
            "dispatch_offsets_kind": "tuple" if isinstance(dispatch_offsets, tuple) else "list",
        }))


def recover_g17_firmware_event_validators(
    driver: bytes, role_address: int, role_code: bytes
) -> dict[str, object]:
    """Recover Apple's internal record and enum names for typed event arms."""
    return _native_g17._query(
        driver, 'recover_g17_firmware_event_validators',
        event_options_text=json.dumps({
            'role_address': role_address,
            'role_code': role_code.hex(),
        }))


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
