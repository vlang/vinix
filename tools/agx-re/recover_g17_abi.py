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
INTERFACE_MAGIC = 0x0C8BC322072804C0
INIT_FIRMWARE_DATA = "__ZN14AGXArmFirmware16initFirmwareDataEv"
INIT_BASE_FIRMWARE_DATA = "__ZN11AGXFirmware16initFirmwareDataEv"
INIT_FIRMWARE_SHARED_DATA = "__ZN14AGXArmFirmware22initFirmwareSharedDataEv"
ALLOC_ARM_FIRMWARE_DATA = "__ZN14AGXArmFirmware17allocFirmwareDataEv"
PREPARE_FIRMWARE_BOOT = "__ZN14AGXArmFirmware22prepareFirmwareForBootEv"
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
SUBMIT_DEVICE_CONTROL = (
    "__ZN11AGXFirmware19submitDeviceControlE"
    "P33AGFIAcceleratorDeviceControlEntryjPj"
)
RESET_CHANNEL_STATE = "__ZN10AGXChannel17resetChannelStateEv"
WRITE_CHANNEL_COMMAND_POINTER = (
    "__ZN10AGXChannel26writeChannelCommandPointerEyP22AGFIChannelCommandTypey"
)
CHANNEL_INIT = (
    "__ZN10AGXChannel4initEPK15AGXCommandQueueP12AGXWorkQueueiiy19_AGFIDataMasterType"
)
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
IOGPU_DEVICE_INIT = "__ZN11IOGPUDevice4initEP5IOGPUP4task"
AGX_SHARED_INIT = "__ZN9AGXShared4initEP5IOGPUP4tasky"
AGX_SHARED_SET_APP_GPU_ROLE = "__ZN9AGXShared16set_app_gpu_roleEi13eIOGPUAppRole"
CONFIGURE_POOL_ELEMENT_SIZES = "__ZN11AGXFirmware25configurePoolElementSizesEv"
BASE_ALLOC_FIRMWARE_DATA = "__ZN11AGXFirmware17allocFirmwareDataEv"
REQUEST_CHANNEL_COMMAND_BARRIER = "__ZN11AGXFirmware28requestChannelCommandBarrierEPy"
TA_COMMAND_POOL = 0x1648
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
    if opcode == 0xD2800000:
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
            "core_leakage_offset": 0xE50,
            "core_leakage_second_offset": 0xED0,
            "group_leakage_offset": 0xF20,
            "holder_member": 0x5B0,
        },
        "leakage_model": {
            "equation": G17_APPLY_LEAKAGE_EQUATION,
            "temperature": 110.0,
            "vdd_gpu": leakage_table(G17_CALCULATE_VDD_GPU_LEAKAGE),
            "afr": leakage_table(G17_CALCULATE_AFR_LEAKAGE),
        },
    }


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
    def stores_covering(code: bytes, base: int, target: int) -> list[int]:
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


def recover_accelerator_ring_bindings(
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
            raise ValueError(f"role {role} accelerator state allocation is not 0x30 bytes")
        if by_members.get((entries_cpu, entries_gpu)) != 0x4000:
            raise ValueError(f"role {role} accelerator entries allocation is not 0x4000 bytes")
        offsets = published.get(shared, set())
        expected = {0x180, 0x188, 0x190, 0x198}
        if not expected.issubset(offsets):
            raise ValueError(
                f"role {role} accelerator addresses are not published through "
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

    _address, next_entry = symbol_code(image, NEXT_DATA_MASTER_ENTRY)
    data_master_size = recover_entry_stride(next_entry)
    _address, encoder = symbol_code(image, ENCODE_ACCELERATOR_COMMAND)
    fields = recover_accelerator_command_fields(encoder)
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


def decode_ldr_q(word: int) -> tuple[int, int, int] | None:
    """Decode LDR (immediate, unsigned offset) for a 128-bit SIMD register."""
    if word & 0xFFC00000 != 0x3DC00000:
        return None
    destination = word & 0x1F
    base = (word >> 5) & 0x1F
    immediate = ((word >> 10) & 0xFFF) * 16
    return destination, base, immediate


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
    args = parser.parse_args()
    try:
        driver = args.driver.read_bytes()
        kernel = args.kernel.read_bytes()
        firmware = args.firmware.read_bytes()
        iogpu = args.iogpu.read_bytes()
        driver_uuid = macho_uuid(driver)
        firmware_uuid = macho_uuid(firmware)
        if driver_uuid != DRIVER_UUID:
            raise ValueError(f"unsupported AGXG17X UUID {driver_uuid}")
        if firmware_uuid != FIRMWARE_UUID:
            raise ValueError(f"unsupported G17 firmware UUID {firmware_uuid}")
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
        accelerator["bindings"] = recover_accelerator_ring_bindings(
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
        channels["scheduler_state"] = recover_g17_scheduler_state(driver)
        channels["queue_device_inputs"] = recover_g17_queue_device_inputs(
            driver, iogpu
        )
        channels["command_pools"] = recover_g17_channel_command_pools(driver)
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
                "driver_root": driver_root,
                "firmware_root": firmware_root,
                "bootstrap_roots": bootstrap_roots,
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
