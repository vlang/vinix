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
    return _native_g17._query(image, 'recover_g17_perf_state_map_block', arm_power_code=arm_power_code.hex())


def recover_g17_aux_performance_layout(
    image: bytes, arm_power_code: bytes
) -> dict[str, object]:
    return _native_g17._query(image, 'recover_g17_aux_performance_layout', arm_power_code=arm_power_code.hex())


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
    return _native_g17._query(b"", 'recover_g17_data_master_ring_bindings', allocations_text=json.dumps(allocations), init_code=init_code.hex())


def recover_g17_data_master_doorbells(image: bytes) -> dict[str, object]:
    return _native_g17._query(image, 'recover_g17_data_master_doorbells')


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
