#!/usr/bin/env python3
"""Recover the T6050 GPU power-owner contract from Apple's boot DeviceTree.

This is a read-only host tool.  It emits names, handles, and region metadata;
it never copies the DeviceTree payload into the repository output.
"""

from __future__ import annotations

import argparse
import json
import struct
from dataclasses import dataclass
from pathlib import Path

import _native_adt
import _native_t6050
from extract_fileset import LC_SEGMENT_64
from recover_g17_abi import (
    decode_add_immediate,
    decode_adrp,
    decode_test_bit_branch,
    macho_symbols,
    macho_uuid,
    read_adrp_add_cstring,
    read_adrp_add_address,
    read_virtual_u32_table,
    recover_vtable_target,
    symbol_code,
    virtual_to_file,
)


DEFAULT_PREBOOT = Path("/System/Volumes/Preboot")
COMPRESSION_LZFSE = 0x801
MAX_DEVICE_TREE_BYTES = 64 << 20
ADT_PROPERTY_NAME_BYTES = 32
ADT_PROPERTY_LENGTH_MASK = 0x00FFFFFF
PMGR_DEVICE_BYTES = 48
# The public DeviceTree handle is the little-endian u16 at +0x1a.  Other
# record fields can contain the same numeric value as a parent dependency, so
# resolving by an arbitrary byte match is not safe.
PMGR_DEVICE_HANDLE_OFFSET = 26
PMGR_DEVICE_NAME_OFFSET = 32
PMP_SOC_DEVICE_BYTES = 124
PMP_SOC_DEVICE_NAME_OFFSET = 116
PMP_PTD_RANGE_BYTES = 32
PMP_PTD_RANGE_NAME_OFFSET = 16
APPLE_PMGR_UUID = "42F1AD20-5320-3803-8A70-05104BD5FBA7"
APPLE_T6050_PMGR_UUID = "0AEACB61-66C5-3D24-AEA2-0A9DFFCF17E2"
APPLE_PMP_UUID = "AA65CE02-93C8-33DE-A7BE-B11E1621F739"
APPLE_PMP_FIRMWARE_UUID = "2AFE4BC5-2371-341F-BD24-3D643EFBAFD0"
RTBUDDY_UUID = "4FEFDDA4-3743-34AC-869D-EAE695595A4C"
APPLE_A7IOP_UUID = "DD46FF2D-6ADD-3A7D-8BCC-7184A5E3398A"
APPLE_ASCWRAP_V6_UUID = "7206DC2B-CA0F-3289-876B-A46F283D5798"
APPLE_T8110_DART_UUID = "4C6C1E5C-04E3-3B6C-98AC-5A64255B8207"
IODART_FAMILY_UUID = "DB9C5931-E7EC-3601-A7FF-E1F3EFBD5BCC"
T6050_KERNEL_UUID = "FF5FFF89-5F93-3D5F-A4FB-74B8C8C313AC"
DEFAULT_APPLE_PMGR = Path("build/kext/g17c/driver.ApplePMGR.macho")
DEFAULT_APPLE_T6050_PMGR = Path("build/kext/g17c/driver.AppleT6050PMGR.macho")
DEFAULT_APPLE_PMP = Path("build/kext/g17c/driver.ApplePMP.macho")
DEFAULT_APPLE_PMP_FIRMWARE = Path(
    "build/kext/g17c/driver.ApplePMPFirmware.macho"
)
DEFAULT_RTBUDDY = Path("build/kext/g17c/driver.RTBuddy.macho")
DEFAULT_APPLE_A7IOP = Path("build/kext/g17c/driver.AppleA7IOP.macho")
DEFAULT_APPLE_ASCWRAP_V6 = Path(
    "build/kext/g17c/driver.AppleA7IOP-ASCWrap-v6.macho"
)
DEFAULT_APPLE_T8110_DART = Path(
    "build/kext/g17c/driver.AppleT8110DART.macho"
)
DEFAULT_IODART_FAMILY = Path("build/kext/g17c/driver.IODARTFamily.macho")
DEFAULT_KERNEL = Path("build/kext/g17c/kernel.macho")
PMP_SEND_COMMAND = "__ZN9ApplePMGR15_sendPMPCommandENS_10PMPCommandEPmj"
PMP_WRITE_DASHBOARD = "__ZN9ApplePMGR18_pmpWriteDashBoardENS_10PMPCommandEPmj"
PMP_SET_DEVICE_STATE = "__ZN9ApplePMGR32_pmpWriteDashBoardSetDeviceStateEtjj"
PMP_SET_VIRTUAL_DEVICE_STATE = (
    "__ZN9ApplePMGR39_pmpWriteDashBoardSetVirtualDeviceStateEtjj"
)
PMP_INIT_V2 = "__ZN9ApplePMGR10_initPMPv2Ev"
PMP_GET_DEVICE_INDEX = "__ZN9ApplePMGR18_getPMPDeviceIndexEtj"
PMP_NOTIFY_INITIAL = "__ZN9ApplePMGR34_notifyPMPInitialDeviceStatusGatedEv"
PMP_WAIT_CLUSTER_POWER_UP = "__ZN9ApplePMGR22_waitForClusterPowerUpEPNS_10DeviceDataEm"
PMP_ENABLE_DEVICE_GATED = "__ZN9ApplePMGR18_enableDeviceGatedEmmmm"
PMP_DEVICE_ID_TO_DATA = "__ZN9ApplePMGR21_deviceIDToDeviceDataEt"
PMP_CHECK_NOTIFY = "__ZN9ApplePMGR15_checkNotifyPMPEt"
PMP_WAIT_READY = "__ZN9ApplePMGR22_waitForPMPReadyActionEm"
PMP_WAIT_READY_V2 = "__ZN9ApplePMGR29_waitForPMPReadyActionGatedv2Ej"
PMP_READY_GATED = "__ZN9ApplePMGR20_pmpReadyActionGatedEj"
PMP_READY_ACTION_V2 = "__ZN9ApplePMGR17_pmpReadyActionv2Em"
PMP_NOTIFY_INITIAL_ENTRY = "__ZN9ApplePMGR28notifyPMPInitialDeviceStatusEv"
PMGR_START = "__ZN9ApplePMGR5startEP9IOService"
PMGR_HANDLE_INTERRUPT_ALL = (
    "__ZN9ApplePMGR19_handleInterruptAllEP22IOInterruptEventSourcei"
)
PMGR_PM_HIBERNATION_STATE = "__ZN9ApplePMGR18pmHibernationStateEv"
PMGR_CURRENT_DRIVER_STATE = "__ZN9ApplePMGR21getCurrentDriverStateEv"
PMGR_UPDATE_HIB_DEVICE_STATUS = "__ZN9ApplePMGR21updateHibDeviceStatusEv"
PMGR_INIT_DRIVER = "__ZN9ApplePMGR10initDriverEP9IOService"
PMGR_CONSTRUCTOR = "__ZN9ApplePMGRC2EPK11OSMetaClass"
PMGR_INTERRUPT_CONFIG_PROPERTY = "interrupt-config"
PMGR_INTERRUPT_CONFIG_BYTES = 20
PMGR_INTERRUPT_CONFIG_NAME_OFFSET = 4
PMP_READY_INTERRUPT_NAME = "PMP_STATUS"
APPLE_PTD_READ = "__ZNK8ApplePTD8_readPTDEPvjPNS_5EntryEj"
APPLE_PTD_WRITE = "__ZNK8ApplePTD9_writePTDEPvjyj"
PMGR_GET_REG_MAP = "__ZN9ApplePMGR9getRegMapENS_6RegMapEj"
PMGR_INIT_REG_MAP = "__ZN9ApplePMGR10initRegMapENS_6RegMapEjjb"
PMGR_WRITE_REG64 = "__ZN9ApplePMGR10writeReg64ENS_6RegMapEjyj"
APPLE_T6050_PMGR_VTABLE = "__ZTV14AppleT6050PMGR"
T6050_INIT_REG_MAPS = "__ZN14AppleT6050PMGR11initRegMapsEv"
T6050_RESTORE_HW = "__ZN14AppleT6050PMGR9restoreHWEb"
T6050_UPDATE_HIB_DEVICE_STATUS = "__ZN14AppleT6050PMGR21updateHibDeviceStatusEv"
PMGR_PMP_V1 = "__ZN9ApplePMGR6_pmpV1Ev"
PMGR_PMP_V2 = "__ZN9ApplePMGR6_pmpV2Ev"
PMGR_GET_NUM_DIES = "__ZN9ApplePMGR10getNumDiesEv"
PMGR_GET_DIE_COUNT = "__ZN9ApplePMGR11getDieCountEv"
APPLE_PMP_V2_START = "__ZN10ApplePMPv25startEP9IOService"
APPLE_PMP_V2_MESSAGE_HANDLER = "__ZN10ApplePMPv214messageHandlerEPvS0_"
APPLE_PMP_V2_HANDLE_MEMORY = "__ZN10ApplePMPv216handleMemMessageEy"
APPLE_PMP_V2_HANDLE_POWER = "__ZN10ApplePMPv215handlePMMessageEy"
APPLE_PMP_V2_HANDLE_REGISTRY = "__ZN10ApplePMPv221handleRegistryMessageEy"
APPLE_PMP_V2_SEND_MESSAGE = "__ZN10ApplePMPv211sendMessageEy"
APPLE_PMP_V2_WRITE_DASHBOARD = "__ZN10ApplePMPv214writeDashboardEjy"
APPLE_PMP_V2_GET_PROPERTY_DATA = "__ZN10ApplePMPv215getPropertyDataEPKc"
APPLE_PMP_V2_PING_GATED = "__ZN10ApplePMPv29pingGatedEPv"
APPLE_PMP_FIRMWARE_VTABLE = "__ZTV16ApplePMPFirmware"
APPLE_PMP_FIRMWARE_START = "__ZN16ApplePMPFirmware5startEP9IOService"
APPLE_PMP_FIRMWARE_PATCH = (
    "__ZN16ApplePMPFirmware13patchFirmwareEP15RTBuddyFirmware"
)
RTBUDDY_FIRMWARE_SERVICE_VTABLE = "__ZTV22RTBuddyFirmwareService"
RTBUDDY_FIRMWARE_VTABLE = "__ZTV15RTBuddyFirmware"
RTBUDDY_FIRMWARE_SERVICE_PRE_LOAD = (
    "__ZN22RTBuddyFirmwareService15preFirmwareLoadEP15RTBuddyFirmware"
)
RTBUDDY_FIRMWARE_SERVICE_PATCH = (
    "__ZN22RTBuddyFirmwareService13patchFirmwareEP15RTBuddyFirmware"
)
RTBUDDY_FIRMWARE_PATCH_U32 = "__ZN15RTBuddyFirmware13patchBayWriteIjEEbjRKT_"
RTBUDDY_FIRMWARE_FIXUP = (
    "__ZN15RTBuddyFirmware5fixupEP7RTBuddyP22RTBuddyFirmwareService"
)
RTBUDDY_FIRMWARE_COPY_TO_TARGET = (
    "__ZN15RTBuddyFirmware12copyToTargetEP7RTBuddy"
)
RTBUDDY_FIRMWARE_CREATE_COREDUMP_MAP = (
    "__ZN15RTBuddyFirmware17createCoredumpMapEP7RTBuddy"
)
RTBUDDY_FIRMWARE_PUBLISH = (
    "__ZN15RTBuddyFirmware19publishToIORegistryEP7RTBuddy"
)
RTBUDDY_FIRMWARE_WRITE_BACK_PATCHBAY = (
    "__ZN15RTBuddyFirmware17writeBackPatchBayEv"
)
RTBUDDY_FIRMWARE_UPDATE_PATCHBAY = (
    "__ZN15RTBuddyFirmware14updatePatchBayEP7RTBuddy"
)
RTBUDDY_FIRMWARE_UPDATE_COREDUMP_PATCHBAY = (
    "__ZN15RTBuddyFirmware26updateCoredumpWithPatchBayEv"
)
RTBUDDY_FIRMWARE_GET_ROLE = "__ZNK15RTBuddyFirmware7getRoleEv"
RTBUDDY_FIRMWARE_ANNOUNCE = "__ZNK15RTBuddyFirmware8announceEv"
RTBUDDY_CALL_PATCHBAY_CALLBACK = (
    "__ZN7RTBuddy20callPatchbayCallbackEP15RTBuddyFirmware"
)
RTBUDDY_POWER_ON = "__ZN7RTBuddy7powerOnEv"
RTBUDDY_LOAD_FIRMWARE = "__ZN7RTBuddy12loadFirmwareEP15RTBuddyFirmware"
RTBUDDY_VTABLE = "__ZTV7RTBuddy"
RTBUDDY_INIT_CONFIG_EDT = "__ZN7RTBuddy14_initConfigEDTEv"
RTBUDDY_ATTEMPT_FIRMWARE_LOAD = "__ZN7RTBuddy20_attemptFirmwareLoadEv"
RTBUDDY_HANDLE_PRELOAD_FIRMWARE = "__ZN7RTBuddy22_handlePreloadFirmwareEv"
RTBUDDY_HANDLE_SERVICE_FIRMWARE = "__ZN7RTBuddy22_handleServiceFirmwareEv"
RTBUDDY_SERVICE_MATCHING_ROLE = (
    "__ZN22RTBuddyFirmwareService26matchingDictionaryWithRoleEP8OSString"
)
RTBUDDY_FIRMWARE_PRELOADED = (
    "__ZN15RTBuddyFirmware17preloadedFirmwareEP7OSArrayP8OSString"
)
RTBUDDY_FIRMWARE_INIT_SEGMENT_MAP = (
    "__ZN15RTBuddyFirmware18initWithSegmentMapEP7OSArrayP8OSString"
)
RTBUDDY_FIRMWARE_IBOOT_LOADED = "__ZNK15RTBuddyFirmware11iBootLoadedEv"
RTBUDDY_FIRMWARE_COPY_ID_BLOCK = (
    "__ZN15RTBuddyFirmware11copyIdBlockEP16RTK_uuid_block_t"
)
RTBUDDY_FIRMWARE_FIND_PATCHBAY = "__ZN15RTBuddyFirmware12findPatchBayEPyPjS1_Pb"
RTBUDDY_FIRMWARE_COPY32_FROM_IOP = (
    "__ZN15RTBuddyFirmware20copy32FromIopVirtualEymPv"
)
RTBUDDY_FIRMWARE_SEGMENT_FOR_IOP = (
    "__ZN15RTBuddyFirmware23getSegmentForIopVirtualEy"
)
RTBUDDY_SEGMENT_IS_WRITABLE = "__ZNK14RTBuddySegment10isWritableEv"
RTBUDDY_SEGMENT_WITH_PHYSICAL_RANGE = (
    "__ZN14RTBuddySegment17withPhysicalRangeEyyyyP8OSStringj"
)
RTBUDDY_GET_SEGMENT_MAP = "__ZNK7RTBuddy13getSegmentMapEv"
RTBUDDY_PATCHBAY_INIT_WITH_DATA = "__ZN15RTBuddyPatchBay12initWithDataEP6OSDatajb"
RTBUDDY_PATCHBAY_FIND = "__ZN15RTBuddyPatchBay4findEj"
RTBUDDY_PATCHBAY_WITH_DATA = "__ZN15RTBuddyPatchBay8withDataEP6OSDatajb"
RTBUDDY_PATCHBAY_GET_BYTES = "__ZN15RTBuddyPatchBay14getBytesNoCopyEv"
RTBUDDY_FIRMWARE_GET_PATCHBAY = "__ZN15RTBuddyFirmware11getPatchBayEv"
RTBUDDY_FIRMWARE_COPY_PATCHBAY_DATA = (
    "__ZN15RTBuddyFirmware16copyPatchBayDataEPjPb"
)
RTBUDDY_FIRMWARE_COPY32_REGION = "__ZN15RTBuddyFirmware20copy32FromIopVirtualEym"
RTBUDDY_COREDUMP_READWRITE_MAP = (
    "__ZN18RTBuddyCoredumpMap25readwriteMapForIopVirtualEyPy"
)
RTBUDDY_MEMCPY_TO32 = (
    "__Z11memcpy_to32NSt3__14spanISt4byteLm18446744073709551615EEE"
    "NS0_IKS1_Lm18446744073709551615EEEm"
)
RTK_ID_BLOCK_MAGIC = 0x64697575  # "uuid" in stored byte order
RTK_ID_BLOCK_BYTES = 0x40
RTK_ID_BLOCK_CANDIDATES = 8
PATCHBAY_HEADER_BYTES = 8
PMP_CHOSEN_PATH = "IODeviceTree:/chosen"
PMP_PMGR_PATH = "IODeviceTree:/arm-io/pmgr"
PMP_PROVIDER_NODE = "the RTBuddy provider nub"
# ApplePMPFirmware::patchFirmware writes exactly these, in this order. The tag
# is the u32 constant read most-significant byte first; the image stores the
# reversed bytes. `length_checked` records a real asymmetry: only the two
# path-resolved nodes reject a property that is not exactly four bytes, while
# the provider reads take the first four bytes of whatever OSData they find.
PMP_MANDATORY_PATCHBAY_INPUTS = (
    ("BDID", "board-id", PMP_CHOSEN_PATH, "value", 0xC8, True),
    ("DVID", "dram-vendor-id", PMP_CHOSEN_PATH, "value", 0xCC, True),
    ("DCAP", "dram-capacity", PMP_PROVIDER_NODE, "value", 0xD0, False),
    ("DCHD", "dram-channel-disable", PMP_PROVIDER_NODE, "value", 0xD4, False),
    ("PMC_", "pmc", PMP_PMGR_PATH, "value", 0xD8, True),
    ("PMCV", "pmc-pmgr", PMP_PMGR_PATH, "value & 1", 0xDC, True),
    ("PMCB", "pmc-pmgr", PMP_PMGR_PATH, "(value >> 3) & 1", 0xE0, True),
    ("PMCX", "pmc-msg-disabled", PMP_PROVIDER_NODE, "value", 0xE4, False),
    ("CVAR", "soc-chip-variant", PMP_PROVIDER_NODE, "value", 0xE8, False),
)
T6050_PMP_IMAGE_ID_UUID = "ed70ac9090873857b454318e50a9223f"
DEFAULT_PMP_IMAGE = Path("build/firmware/t6050pmp.macho")
RTBUDDY_PRELOADED_PROPERTY = "pre-loaded"
RTBUDDY_RUNNING_PROPERTY = "running"
RTBUDDY_NO_FIRMWARE_SERVICE_PROPERTY = "no-firmware-service"
RTBUDDY_LOAD_FIRMWARE_GATED = (
    "__ZN7RTBuddy18_loadFirmwareGatedEP15RTBuddyFirmware"
)
RTBUDDY_WAIT_FOR_FIRMWARE_SERVICE_GATED = (
    "__ZN7RTBuddy28_waitForFirmwareServiceGatedEv"
)
RTBUDDY_PERFORM_POWER_STATE_GATED = (
    "__ZN7RTBuddy29_performPowerStateChangeGatedEPK17RTBuddyPowerState"
)
RTBUDDY_IOP_VALIDATE = "__ZN7RTBuddy12_iopValidateEv"
RTBUDDY_IOP_VALIDATE_POLLING = (
    "__ZN7RTBuddy19_iopValidatePollingE12RtbIopStatus"
)
RTBUDDY_IOP_VALIDATE_BLOCKING = (
    "__ZN7RTBuddy20_iopValidateBlockingE12RtbIopStatus"
)
RTBUDDY_SET_IOP_STATUS = "__ZN7RTBuddy13_setIopStatusE12RtbIopStatus"
RTBUDDY_SET_IOP_STATUS_PUBLIC = "__ZN7RTBuddy12setIopStatusE12RtbIopStatus"
RTBUDDY_MANAGEMENT_HANDLE_HELLO = (
    "__ZN25RTBuddyManagementEndpoint12_handleHelloEy"
)
RTBUDDY_BUILD_ROLL_CALL = "__ZN25RTBuddyManagementEndpoint14_buildRollCallEj"
RTBUDDY_GET_ENDPOINT = "__ZN7RTBuddy11getEndpointEj"
RTBUDDY_MANAGEMENT_HANDLE_EP_ROLLCALL = (
    "__ZN25RTBuddyManagementEndpoint17_handleEPRollCallEy"
)
RTBUDDY_CREATE_ENDPOINT = "__ZN7RTBuddy14createEndpointEj"
RTBUDDY_ENDPOINT_SERVICE_CREATE_NAME = (
    "__ZN22RTBuddyEndpointService10createNameEP9IOServicej"
)
RTBUDDY_ENDPOINT_GET_SLAVE = "__ZN15RTBuddyEndpoint17getSlaveProcessorEv"
RTBUDDY_ENDPOINT_INIT_OWNER = (
    "__ZN15RTBuddyEndpoint12initForOwnerEP8OSObjectPFvS1_PvS2_ES2_"
)
RTBUDDY_ENDPOINT_SET_POWER_ACTION = (
    "__ZN15RTBuddyEndpoint19setPowerStateActionEPFiP8OSObjectmmE"
)
APPLE_WRAPPER_MAILBOX_START = "__ZN19AppleWrapperMailbox5startEP9IOService"
APPLE_WRAPPER_MAILBOX_REG = "__ZN19AppleWrapperMailbox4_regEj"
APPLE_WRAPPER_MAILBOX_PHYSICAL = (
    "__ZN19AppleWrapperMailbox25getWrapperPhysicalAddressEv"
)
APPLE_A7IOP_VTABLE = "__ZTV10AppleA7IOP"
APPLE_A7IOP_START = "__ZN10AppleA7IOP5startEP9IOService"
APPLE_A7IOP_HAS_IBOOT_FIRMWARE = "__ZN10AppleA7IOP17_hasiBootFirmwareEv"
APPLE_A7IOP_SEGMENT_RANGES_PROPERTY = "segment-ranges"
APPLE_A7IOP_START_CPU_OPTIONS = (
    "__ZN10AppleA7IOP19startCPUWithOptionsEP15IOSlaveFirmwarej"
)
APPLE_A7IOP_REG = "__ZN10AppleA7IOP4_regEj"
APPLE_A7IOP_PHYSICAL = "__ZN10AppleA7IOP25getWrapperPhysicalAddressEv"
APPLE_A7IOP_ENABLE_SRAM = "__ZN10AppleA7IOP10enableSRAMEb"
APPLE_A7IOP_ENABLE_POWER = "__ZN10AppleA7IOP12_enablePowerEbj"
APPLE_A7IOP_ENABLE_POWER_VTABLE_SLOT = 0x9C8
APPLE_A7IOP_DART_MAP_IBOOT_FIRMWARE = (
    "__ZN10AppleA7IOP21_dartMapiBootFirmwareEP8IOMapper"
)
IODART_MAPPER_VTABLE = "__ZTV12IODARTMapper"
IODART_MAPPER_GET_PAGE_SIZE = "__ZNK12IODARTMapper11getPageSizeEv"
IODART_MAPPER_IOVM_INSERT = "__ZN12IODARTMapper10iovmInsertEjyyyy"
IODART_MAPPER_IOVM_INSERT_ONE = (
    "__ZN12IODARTMapper11_iovmInsertEP13IODARTVMSpacejjjj"
)
APPLE_T8110_DART_ENABLE_TRANSLATION = (
    "__ZN14AppleT8110DART17enableTranslationEjb"
)
APPLE_T8110_DART_START = "__ZN14AppleT8110DART5startEP9IOService"
APPLE_T8110_DART_SETUP = "__ZN14AppleT8110DART10_dartSetupER19t8110dart_init_data"
APPLE_T8110_DART_GET_SID_PROPERTY = (
    "__ZN14AppleT8110DART15_getSidPropertyEPKcjPm"
)
APPLE_T8110_DART_GET_SID_COUNT = "__ZNK14AppleT8110DART12_getSIDCountEj"
APPLE_T8110_DART_IS_BYPASSED_SID = "__ZNK14AppleT8110DART13isBypassedSIDEj"
APPLE_T8110_DART_SET_TRANSLATION = "__ZN14AppleT8110DART14setTranslationEjjjj"
APPLE_T8110_DART_SET_TRANSLATION_RANGE = (
    "__ZN14AppleT8110DART14setTranslationEP13IODARTVMSpacejPvjjjjjj"
)
APPLE_T8110_DART_INVALIDATE_TLB = (
    "__ZN14AppleT8110DART13invalidateTLBEP13IODARTVMSpacejjj"
)
T8110_DART_MAX_TRANSLATION_LEVELS = "_t8110dart_max_translation_levels"
T8110_DART_VO_TT_INDEX = "_t8110dart_vo_tt_index"
T8110_DART_VO_TTE = "_t8110dart_vo_tte"
APPLE_ASCWRAP_V6_VTABLE = "__ZTV14AppleASCWrapV6"
APPLE_ASCWRAP_V6_INITIALIZE = "__ZN14AppleASCWrapV610initializeEv"
APPLE_ASCWRAP_V6_SET_IORVBAR = "__ZN14AppleASCWrapV611_setIORVBAREy"
APPLE_ASCWRAP_V6_IS_IORVBAR_LOCKED = "__ZN14AppleASCWrapV616_isIORVBARLockedEv"
APPLE_ASCWRAP_V6_MAP_FIRMWARE = (
    "__ZN14AppleASCWrapV612_mapFirmwareEyP18IOMemoryDescriptorj"
)
APPLE_ASCWRAP_V6_RUN_CPU = "__ZN14AppleASCWrapV67_runCPUEb"
APPLE_ASCWRAP_V6_INBOX = "__ZN14AppleASCWrapV66_inboxEPv"
APPLE_ASCWRAP_V6_OUTBOX = "__ZN14AppleASCWrapV67_outboxEPv"
APPLE_ASCWRAP_V6_KIC_INBOX_ENABLED = (
    "__ZN14AppleASCWrapV619_getKICInboxEnabledEv"
)
APPLE_ASCWRAP_V6_INBOX_EMPTY = "__ZN14AppleASCWrapV614_getInboxEmptyEv"
APPLE_ASCWRAP_V6_INBOX_FULL = "__ZN14AppleASCWrapV613_getInboxFullEv"
APPLE_ASCWRAP_V6_OUTBOX_EMPTY = "__ZN14AppleASCWrapV615_getOutboxEmptyEv"
APPLE_ASCWRAP_V6_MAILBOX_ITEM_SIZE = (
    "__ZNK14AppleASCWrapV615mailboxItemSizeEv"
)


@dataclass(frozen=True)
class AdtProperty:
    data: bytes
    flags: int


@dataclass(frozen=True)
class AdtNode:
    properties: dict[str, AdtProperty]
    children: tuple["AdtNode", ...]

    def property(self, name: str) -> bytes:
        try:
            return self.properties[name].data
        except KeyError as error:
            raise ValueError(f"DeviceTree node {node_name(self)!r} has no {name!r} property") from error


@dataclass(frozen=True)
class PmgrDevice:
    index: int
    handle: int
    name: str
    flags: int
    pmp_selector: int
    pmp_virtual_class: int


def align_up(value: int, alignment: int) -> int:
    return _native_adt.query(b"", "align_up", value=value, alignment=alignment)


def device_tree_im4p_payload(blob: bytes) -> bytes:
    return _native_adt.device_tree_im4p_payload(blob)


def decompress_device_tree(payload: bytes, initial_capacity: int | None = None) -> bytes:
    return _native_adt.decompress_device_tree(payload, initial_capacity)


def parse_adt(blob: bytes) -> AdtNode:
    return _native_adt.parse_adt(blob, AdtProperty, AdtNode)


def decode_cstring(data: bytes, field: str) -> str:
    return _native_adt.query(data, "decode_cstring", field=field)


def decode_string_list(data: bytes, field: str) -> list[str]:
    return _native_adt.query(data, "decode_string_list", field=field)


def decode_u32_array(data: bytes, field: str) -> list[int]:
    return _native_adt.query(data, "decode_u32_array", field=field)


def decode_integer(data: bytes, field: str) -> int:
    return _native_adt.query(data, "decode_integer", field=field)


def parse_reg_regions(data: bytes, field: str) -> list[tuple[int, int]]:
    return _native_adt.parse_reg_regions(data, field)


def node_name(node: AdtNode) -> str:
    value = node.properties.get("name")
    return decode_cstring(value.data, "node name") if value else "<anonymous>"


def walk_adt(node: AdtNode, parent_path: str = ""):
    name = node_name(node)
    path = f"{parent_path}/{name}" if parent_path else f"/{name}"
    yield path, node
    for child in node.children:
        yield from walk_adt(child, path)


def find_one(root: AdtNode, description: str, predicate) -> tuple[str, AdtNode]:
    matches = [(path, node) for path, node in walk_adt(root) if predicate(node)]
    if len(matches) != 1:
        paths = ", ".join(path for path, _node in matches) or "none"
        raise ValueError(f"expected one {description}, found: {paths}")
    return matches[0]


def compatible_with(node: AdtNode, value: str) -> bool:
    compatible = node.properties.get("compatible")
    return bool(compatible and value in decode_string_list(compatible.data, "compatible"))


def parse_pmgr_devices(data: bytes) -> list[PmgrDevice]:
    return _native_adt.parse_pmgr_devices(data, PmgrDevice)


def resolve_gate(handle: int, devices: list[PmgrDevice]) -> dict[str, object]:
    return _native_adt.resolve_gate(handle, devices)


def parse_pmgr_interrupt_config(data: bytes, field: str) -> list[dict[str, object]]:
    return _native_adt.query(data, "parse_pmgr_interrupt_config", field=field)


def parse_pmp_soc_devices(data: bytes) -> list[dict[str, object]]:
    return _native_adt.query(data, "parse_pmp_soc_devices")


def parse_pmp_ptd_ranges(data: bytes) -> list[dict[str, object]]:
    return _native_adt.query(data, "parse_pmp_ptd_ranges")


def direct_branch_targets(function_address: int, code: bytes) -> set[int]:
    return _native_adt.direct_branch_targets(function_address, code)


def pc_relative_targets(function_address: int, code: bytes) -> set[int]:
    return _native_adt.pc_relative_targets(function_address, code)


def direct_branch_count(function_address: int, code: bytes, target: int) -> int:
    return _native_adt.query(code, "direct_branch_count", function_address=function_address, target=target)


def direct_branch_target_at(function_address: int, code: bytes, offset: int) -> int | None:
    return _native_adt.query(code, "direct_branch_target_at", function_address=function_address, offset=offset)


def _has_sub_cmp_window(code: bytes, source: int, first: int, count: int) -> bool:
    return _native_adt.query(code, "_has_sub_cmp_window", source=source, first=first, count=count)


def _has_cmp_w_immediate(code: bytes, source: int, immediate: int) -> bool:
    return _native_adt.query(code, "_has_cmp_w_immediate", source=source, immediate=immediate)


def _has_ldrb(code: bytes, destination: int, base: int, immediate: int) -> bool:
    return _native_adt.query(code, "_has_ldrb", destination=destination, base=base, immediate=immediate)


def _has_words_in_order(code: bytes, expected: tuple[int, ...]) -> bool:
    return _native_adt.query(code, "_has_words_in_order", expected=expected)


def _has_ordered_words(code: bytes, expected: tuple[int, ...]) -> bool:
    return _native_adt.query(code, "_has_ordered_words", expected=expected)


def recover_apple_ptd_code_contract(
    functions: dict[str, tuple[int, bytes]], symbols: dict[str, int]
) -> dict[str, object]:
    return _native_t6050.contract("recover_apple_ptd_code_contract", functions, symbols=symbols)


def recover_pmgr_interrupt_config(
    image: bytes, functions: dict[str, tuple[int, bytes]]
) -> dict[str, object]:
    return _native_t6050.image_contract("recover_pmgr_interrupt_config", image, functions)


def recover_pmp_readiness_handshake(
    functions: dict[str, tuple[int, bytes]],
    symbols: dict[str, int],
    interrupt_config: dict[str, object],
) -> dict[str, object]:
    return _native_t6050.contract("recover_pmp_readiness_handshake", functions, symbols=symbols, interrupt_config=interrupt_config)


def recover_pmp_code_contract(
    functions: dict[str, tuple[int, bytes]],
    symbols: dict[str, int],
    interrupt_config: dict[str, object],
) -> dict[str, object]:
    return _native_t6050.contract("recover_pmp_code_contract", functions, symbols=symbols, interrupt_config=interrupt_config)


def recover_apple_pmgr(image: bytes) -> dict[str, object]:
    identity = macho_uuid(image)
    if identity != APPLE_PMGR_UUID:
        raise ValueError(f"unsupported ApplePMGR UUID {identity}")
    symbols = macho_symbols(image)
    functions = {
        name: symbol_code(image, name)
        for name in (
            PMP_SEND_COMMAND,
            PMP_WRITE_DASHBOARD,
            PMP_SET_DEVICE_STATE,
            PMP_SET_VIRTUAL_DEVICE_STATE,
            PMP_INIT_V2,
            PMP_GET_DEVICE_INDEX,
            PMP_NOTIFY_INITIAL,
            PMP_NOTIFY_INITIAL_ENTRY,
            PMP_WAIT_CLUSTER_POWER_UP,
            PMP_ENABLE_DEVICE_GATED,
            PMP_WAIT_READY,
            PMP_WAIT_READY_V2,
            PMP_READY_GATED,
            PMP_READY_ACTION_V2,
            PMGR_START,
            PMGR_HANDLE_INTERRUPT_ALL,
            PMGR_INIT_DRIVER,
            PMGR_CONSTRUCTOR,
            APPLE_PTD_READ,
            APPLE_PTD_WRITE,
            PMGR_WRITE_REG64,
        )
    }
    interrupt_config = recover_pmgr_interrupt_config(image, functions)
    return {
        "uuid": identity,
        "pmp_v2": recover_pmp_code_contract(functions, symbols, interrupt_config),
    }


def _decode_movz_w(word: int, register: int) -> int | None:
    return _native_t6050.contract("_decode_movz_w", {}, word=word, register=register)


def recover_t6050_pmgr_code_contract(
    functions: dict[str, tuple[int, bytes]],
    symbols: dict[str, int],
    apple_pmgr_symbols: dict[str, int],
    vtable_targets: dict[int, int],
) -> dict[str, object]:
    return _native_t6050.contract("recover_t6050_pmgr_code_contract", functions, symbols=symbols, apple_pmgr_symbols=apple_pmgr_symbols, vtable_targets=vtable_targets)


def recover_apple_t6050_pmgr(
    image: bytes, apple_pmgr_symbols: dict[str, int]
) -> dict[str, object]:
    identity = macho_uuid(image)
    if identity != APPLE_T6050_PMGR_UUID:
        raise ValueError(f"unsupported AppleT6050PMGR UUID {identity}")
    symbols = macho_symbols(image)
    functions = {
        name: symbol_code(image, name)
        for name in (
            T6050_INIT_REG_MAPS,
            PMGR_PMP_V1,
            PMGR_PMP_V2,
            T6050_RESTORE_HW,
            T6050_UPDATE_HIB_DEVICE_STATUS,
        )
    }
    slots = {
        slot: recover_vtable_target(image, APPLE_T6050_PMGR_VTABLE, slot)
        for slot in (0xAB0, 0xAB8, 0xAC0, 0xAC8, 0xB30)
    }
    return {
        "uuid": identity,
        "power": recover_t6050_pmgr_code_contract(
            functions, symbols, apple_pmgr_symbols, slots
        ),
    }


def recover_apple_pmp_code_contract(
    functions: dict[str, tuple[int, bytes]],
    symbols: dict[str, int],
    rtbuddy_symbols: dict[str, int],
) -> dict[str, object]:
    return _native_t6050.contract("recover_apple_pmp_code_contract", functions, symbols=symbols, rtbuddy_symbols=rtbuddy_symbols)


def recover_apple_pmp(image: bytes, rtbuddy_image: bytes) -> dict[str, object]:
    identity = macho_uuid(image)
    if identity != APPLE_PMP_UUID:
        raise ValueError(f"unsupported ApplePMP UUID {identity}")
    symbols = macho_symbols(image)
    rtbuddy_identity = macho_uuid(rtbuddy_image)
    if rtbuddy_identity != RTBUDDY_UUID:
        raise ValueError(f"unsupported RTBuddy UUID {rtbuddy_identity}")
    rtbuddy_symbols = macho_symbols(rtbuddy_image)
    functions = {
        name: symbol_code(image, name)
        for name in (
            APPLE_PMP_V2_START,
            APPLE_PMP_V2_MESSAGE_HANDLER,
            APPLE_PMP_V2_HANDLE_POWER,
            APPLE_PMP_V2_SEND_MESSAGE,
            APPLE_PMP_V2_WRITE_DASHBOARD,
            APPLE_PMP_V2_PING_GATED,
        )
    }
    start_address, start_code = functions[APPLE_PMP_V2_START]
    expected_start_strings = {
        (0x94, 0x98): "role",
        (0x154, 0x158): "ptd-update-reg-index",
        (0x260, 0x264): "setActive",
        (0x328, 0x32C): "PMP workloop",
        (0x3F8, 0x3FC): "wait-for",
    }
    for (adrp_offset, add_offset), expected in expected_start_strings.items():
        actual = read_adrp_add_cstring(
            image, start_address, start_code, adrp_offset, add_offset
        )
        if actual != expected:
            raise ValueError(
                f"ApplePMPv2 start string changed at {adrp_offset:#x}: {actual!r}"
            )
    return {
        "uuid": identity,
        "rtbuddy_uuid": rtbuddy_identity,
        "pmp_v2": recover_apple_pmp_code_contract(
            functions, symbols, rtbuddy_symbols
        ),
    }


def recover_apple_pmp_firmware_code_contract(
    pmp_functions: dict[str, tuple[int, bytes]],
    pmp_symbols: dict[str, int],
    rtbuddy_functions: dict[str, tuple[int, bytes]],
    rtbuddy_symbols: dict[str, int],
    pmp_vtable_targets: dict[int, int],
    service_vtable_targets: dict[int, int],
    firmware_vtable_targets: dict[int, int],
) -> dict[str, object]:
    return _native_t6050.contract("recover_apple_pmp_firmware_code_contract", {}, pmp_functions=pmp_functions, pmp_symbols=pmp_symbols, rtbuddy_functions=rtbuddy_functions, rtbuddy_symbols=rtbuddy_symbols, pmp_vtable_targets=pmp_vtable_targets, service_vtable_targets=service_vtable_targets, firmware_vtable_targets=firmware_vtable_targets)


def recover_rtbuddy_patchbay_contract(
    image: bytes,
    functions: dict[str, tuple[int, bytes]],
    symbols: dict[str, int],
) -> dict[str, object]:
    return _native_t6050.image_contract("recover_rtbuddy_patchbay_contract", image, functions, symbols=symbols)


def _macho_segment_table(image: bytes) -> list[dict[str, object]]:
    """Return the segment table with protection, which extract_fileset drops."""
    if len(image) < 32:
        raise ValueError("truncated Mach-O header")
    count = struct.unpack_from("<I", image, 16)[0]
    offset = 32
    segments = []
    for _index in range(count):
        command, size = struct.unpack_from("<II", image, offset)
        if size < 8 or offset + size > len(image):
            raise ValueError("malformed Mach-O load command")
        if command == LC_SEGMENT_64:
            name = image[offset + 8 : offset + 24].rstrip(b"\0").decode("ascii")
            virtual, virtual_size, file_offset, file_size = struct.unpack_from(
                "<QQQQ", image, offset + 24
            )
            _maximum, initial = struct.unpack_from("<ii", image, offset + 56)
            segments.append(
                {
                    "name": name,
                    "virtual_address": virtual,
                    "virtual_size": virtual_size,
                    "file_offset": file_offset,
                    "file_size": file_size,
                    "writable": bool(initial & 2),
                }
            )
        offset += size
    if not segments:
        raise ValueError("Mach-O has no segments")
    return segments


def recover_t6050_pmp_patchbay(
    image: bytes, contract: dict[str, object]
) -> dict[str, object]:
    """Apply the recovered patchbay format to the real t6050pmp image.

    Every field used here comes from `recover_rtbuddy_patchbay_contract`, so a
    changed OS invalidates this result rather than silently re-deriving it.
    """

    identity = contract["identity_block"]
    record = contract["record"]
    segments = _macho_segment_table(image)
    base = min(segment["virtual_address"] for segment in segments)

    def read(address: int, size: int) -> bytes | None:
        for segment in segments:
            start = segment["virtual_address"]
            if start <= address and address + size <= start + segment["file_size"]:
                offset = segment["file_offset"] + address - start
                return image[offset : offset + size]
        return None

    matches = []
    for candidate in identity["candidate_iop_offsets"]:
        block = read(base + candidate, identity["size"])
        if block is None:
            continue
        magic, version = struct.unpack_from("<II", block, 0)
        if magic != identity["magic"] or version & ~1 != 4:
            continue
        matches.append((candidate, version, block))
    if len(matches) != 1:
        raise ValueError(
            f"t6050pmp identity block is ambiguous or absent: "
            f"{[item[0] for item in matches]!r}"
        )
    candidate, version, block = matches[0]
    if block[0x10:0x20].hex() != T6050_PMP_IMAGE_ID_UUID:
        raise ValueError(f"t6050pmp image identity changed: {block[0x10:0x20].hex()}")

    fields = identity["patchbay_fields"][str(version)]
    patch_offset = struct.unpack_from("<I", block, fields["offset"])[0]
    patch_size = struct.unpack_from("<I", block, fields["size"])[0]
    unaligned = base + patch_offset
    pad = unaligned & 3
    aligned = unaligned & ~3
    padded_size = (pad + patch_size + 3) & ~3

    owner = next(
        (
            segment
            for segment in segments
            if segment["virtual_address"]
            <= aligned
            < segment["virtual_address"] + segment["file_size"]
        ),
        None,
    )
    if owner is None:
        raise ValueError("t6050pmp patchbay is outside every mapped segment")

    blob = read(aligned, padded_size)
    if blob is None:
        raise ValueError("t6050pmp patchbay extends past its segment")

    records: list[dict[str, object]] = []
    cursor = pad
    header = record["header_bytes"]
    while cursor + header <= pad + patch_size:
        tag, length = struct.unpack_from("<II", blob, cursor)
        if cursor + header + length > pad + patch_size:
            raise ValueError(f"t6050pmp patchbay record at {cursor:#x} overruns")
        records.append(
            {
                "offset": cursor - pad,
                "tag": struct.pack(">I", tag).decode("ascii", "replace"),
                "stored_bytes": struct.pack("<I", tag).decode("ascii", "replace"),
                "value_bytes": length,
            }
        )
        cursor += header + length
    if cursor != pad + patch_size:
        raise ValueError(
            f"t6050pmp patchbay records do not tile its region: "
            f"{cursor - pad:#x} != {patch_size:#x}"
        )

    by_tag = {item["tag"]: item for item in records}
    if len(by_tag) != len(records):
        raise ValueError("t6050pmp patchbay repeats a tag")
    for tag, _property, _node, _derivation, _offset, _checked in (
        PMP_MANDATORY_PATCHBAY_INPUTS
    ):
        entry = by_tag.get(tag)
        if entry is None:
            raise ValueError(f"t6050pmp patchbay is missing mandatory tag {tag}")
        if entry["value_bytes"] != 4:
            raise ValueError(
                f"t6050pmp patchbay tag {tag} is not a 32-bit value: "
                f"{entry['value_bytes']}"
            )

    return {
        "image_uuid": T6050_PMP_IMAGE_ID_UUID,
        "iop_virtual_base": base,
        "identity_block": {
            "candidate_offset": candidate,
            "iop_virtual": base + candidate,
            "version": version,
        },
        "region": {
            "offset": patch_offset,
            "iop_virtual": aligned,
            "align_pad": pad,
            "size": patch_size,
            "padded_size": padded_size,
            "segment": owner["name"],
            "writable": owner["writable"],
        },
        "record_count": len(records),
        "mandatory_tags_present": [
            item[0] for item in PMP_MANDATORY_PATCHBAY_INPUTS
        ],
        "records": records,
    }


def recover_rtbuddy_segment_flag_contract(
    functions: dict[str, tuple[int, bytes]], symbols: dict[str, int]
) -> dict[str, object]:
    return _native_t6050.contract("recover_rtbuddy_segment_flag_contract", functions, symbols=symbols)


def recover_rtbuddy_patchbay_write_contract(
    functions: dict[str, tuple[int, bytes]], symbols: dict[str, int]
) -> dict[str, object]:
    return _native_t6050.contract("recover_rtbuddy_patchbay_write_contract", functions, symbols=symbols)


def recover_rtbuddy_firmware_source_contract(
    image: bytes,
    functions: dict[str, tuple[int, bytes]],
    symbols: dict[str, int],
    preload_vtable_target: int,
) -> dict[str, object]:
    return _native_t6050.image_contract("recover_rtbuddy_firmware_source_contract", image, functions, symbols=symbols, preload_vtable_target=preload_vtable_target)


def recover_rtbuddy_boot_handshake_code_contract(
    functions: dict[str, tuple[int, bytes]],
    symbols: dict[str, int],
) -> dict[str, object]:
    return _native_t6050.contract("recover_rtbuddy_boot_handshake_code_contract", functions, symbols=symbols)


def recover_apple_pmp_firmware(
    image: bytes, rtbuddy_image: bytes
) -> dict[str, object]:
    identity = macho_uuid(image)
    if identity != APPLE_PMP_FIRMWARE_UUID:
        raise ValueError(f"unsupported ApplePMPFirmware UUID {identity}")
    rtbuddy_identity = macho_uuid(rtbuddy_image)
    if rtbuddy_identity != RTBUDDY_UUID:
        raise ValueError(f"unsupported RTBuddy UUID {rtbuddy_identity}")
    pmp_symbols = macho_symbols(image)
    rtbuddy_symbols = macho_symbols(rtbuddy_image)
    pmp_functions = {
        name: symbol_code(image, name)
        for name in (APPLE_PMP_FIRMWARE_START, APPLE_PMP_FIRMWARE_PATCH)
    }
    rtbuddy_function_names = (
        RTBUDDY_FIRMWARE_FIXUP,
        RTBUDDY_LOAD_FIRMWARE_GATED,
        RTBUDDY_LOAD_FIRMWARE,
        RTBUDDY_PERFORM_POWER_STATE_GATED,
        RTBUDDY_IOP_VALIDATE,
        RTBUDDY_IOP_VALIDATE_POLLING,
        RTBUDDY_IOP_VALIDATE_BLOCKING,
        RTBUDDY_SET_IOP_STATUS,
        RTBUDDY_SET_IOP_STATUS_PUBLIC,
        RTBUDDY_MANAGEMENT_HANDLE_HELLO,
        RTBUDDY_MANAGEMENT_HANDLE_EP_ROLLCALL,
        RTBUDDY_BUILD_ROLL_CALL,
        RTBUDDY_GET_ENDPOINT,
        RTBUDDY_CREATE_ENDPOINT,
        RTBUDDY_ENDPOINT_SERVICE_CREATE_NAME,
        RTBUDDY_INIT_CONFIG_EDT,
        RTBUDDY_ATTEMPT_FIRMWARE_LOAD,
        RTBUDDY_HANDLE_PRELOAD_FIRMWARE,
        RTBUDDY_FIRMWARE_PRELOADED,
        RTBUDDY_FIRMWARE_IBOOT_LOADED,
        RTBUDDY_FIRMWARE_COPY_ID_BLOCK,
        RTBUDDY_FIRMWARE_FIND_PATCHBAY,
        RTBUDDY_PATCHBAY_INIT_WITH_DATA,
        RTBUDDY_PATCHBAY_FIND,
        RTBUDDY_FIRMWARE_GET_PATCHBAY,
        RTBUDDY_FIRMWARE_COPY_PATCHBAY_DATA,
        RTBUDDY_FIRMWARE_PATCH_U32,
        RTBUDDY_FIRMWARE_WRITE_BACK_PATCHBAY,
        RTBUDDY_MEMCPY_TO32,
        RTBUDDY_GET_SEGMENT_MAP,
        RTBUDDY_SEGMENT_IS_WRITABLE,
    )
    rtbuddy_functions = {
        name: symbol_code(rtbuddy_image, name) for name in rtbuddy_function_names
    }
    start_address, start_code = pmp_functions[APPLE_PMP_FIRMWARE_START]
    expected_start_strings = {
        (0xE0, 0xE4): "role",
        (0x128, 0x12C): "firmware-name",
        (0x1C8, 0x1CC): "IODeviceTree:/chosen",
        (0x210, 0x214): "board-id",
        (0x2A0, 0x2A4): "dram-vendor-id",
        (0x358, 0x35C): "dram-capacity",
        (0x3C0, 0x3C4): "dram-channel-disable",
        (0x408, 0x40C): "IODeviceTree:/arm-io/pmgr",
        (0x450, 0x454): "pmc",
        (0x4E0, 0x4E4): "pmc-pmgr",
        (0x5A0, 0x5A4): "pmc-msg-disabled",
        (0x608, 0x60C): "soc-chip-variant",
        (0x670, 0x674): "Role",
    }
    for (adrp_offset, add_offset), expected in expected_start_strings.items():
        actual = read_adrp_add_cstring(
            image, start_address, start_code, adrp_offset, add_offset
        )
        if actual != expected:
            raise ValueError(
                "ApplePMPFirmware start string changed at "
                f"{adrp_offset:#x}: {actual!r}"
            )
    pmp_vtable_targets = {
        slot: recover_vtable_target(image, APPLE_PMP_FIRMWARE_VTABLE, slot)
        for slot in (0x5F0, 0x898)
    }
    service_vtable_targets = {
        slot: recover_vtable_target(
            rtbuddy_image, RTBUDDY_FIRMWARE_SERVICE_VTABLE, slot
        )
        for slot in (0x890, 0x898)
    }
    firmware_vtable_targets = {
        slot: recover_vtable_target(rtbuddy_image, RTBUDDY_FIRMWARE_VTABLE, slot)
        for slot in (0x8A8, 0x8B0)
    }
    return {
        "uuid": identity,
        "rtbuddy_uuid": rtbuddy_identity,
        "firmware_load": recover_apple_pmp_firmware_code_contract(
            pmp_functions,
            pmp_symbols,
            rtbuddy_functions,
            rtbuddy_symbols,
            pmp_vtable_targets,
            service_vtable_targets,
            firmware_vtable_targets,
        ),
        "segment_flags": recover_rtbuddy_segment_flag_contract(
            rtbuddy_functions, rtbuddy_symbols
        ),
        "patchbay_write": recover_rtbuddy_patchbay_write_contract(
            rtbuddy_functions, rtbuddy_symbols
        ),
        "patchbay_format": recover_rtbuddy_patchbay_contract(
            rtbuddy_image, rtbuddy_functions, rtbuddy_symbols
        ),
        "firmware_source": recover_rtbuddy_firmware_source_contract(
            rtbuddy_image,
            rtbuddy_functions,
            rtbuddy_symbols,
            recover_vtable_target(rtbuddy_image, RTBUDDY_VTABLE, 0x9D8),
        ),
        "rtkit_boot": recover_rtbuddy_boot_handshake_code_contract(
            rtbuddy_functions, rtbuddy_symbols
        ),
    }


def recover_apple_a7iop_code_contract(
    image: bytes,
    functions: dict[str, tuple[int, bytes]],
    vtable_targets: dict[int, int],
) -> dict[str, object]:
    return _native_t6050.image_contract("recover_apple_a7iop_code_contract", image, functions, vtable_targets=vtable_targets)


def recover_apple_a7iop(image: bytes) -> dict[str, object]:
    identity = macho_uuid(image)
    if identity != APPLE_A7IOP_UUID:
        raise ValueError(f"unsupported AppleA7IOP UUID {identity}")
    functions = {
        name: symbol_code(image, name)
        for name in (
            APPLE_WRAPPER_MAILBOX_START,
            APPLE_WRAPPER_MAILBOX_REG,
            APPLE_WRAPPER_MAILBOX_PHYSICAL,
            APPLE_A7IOP_START,
            APPLE_A7IOP_START_CPU_OPTIONS,
            APPLE_A7IOP_REG,
            APPLE_A7IOP_PHYSICAL,
            APPLE_A7IOP_ENABLE_SRAM,
            APPLE_A7IOP_ENABLE_POWER,
            APPLE_A7IOP_DART_MAP_IBOOT_FIRMWARE,
            APPLE_A7IOP_HAS_IBOOT_FIRMWARE,
        )
    }
    a7_start_address, a7_start_code = functions[APPLE_A7IOP_START]
    for (adrp_offset, add_offset), expected in {
        (0x794, 0x798): "sram-index",
        (0x80C, 0x810): "should-control-sram",
        (0x88C, 0x890): "cpu-ctrl-filtered",
    }.items():
        actual = read_adrp_add_cstring(
            image, a7_start_address, a7_start_code, adrp_offset, add_offset
        )
        if actual != expected:
            raise ValueError(
                f"AppleA7IOP start string changed at {adrp_offset:#x}: {actual!r}"
            )
    vtable_targets = {
        APPLE_A7IOP_ENABLE_POWER_VTABLE_SLOT: recover_vtable_target(
            image, APPLE_A7IOP_VTABLE, APPLE_A7IOP_ENABLE_POWER_VTABLE_SLOT
        )
    }
    return {
        "uuid": identity,
        **recover_apple_a7iop_code_contract(image, functions, vtable_targets),
    }


def recover_iodart_family_code_contract(
    functions: dict[str, tuple[int, bytes]],
    vtable_targets: dict[int, int],
    direction_lookup: tuple[int, ...],
) -> dict[str, object]:
    return _native_t6050.contract("recover_iodart_family_code_contract", functions, vtable_targets=vtable_targets, direction_lookup=direction_lookup)


def recover_iodart_family(image: bytes) -> dict[str, object]:
    identity = macho_uuid(image)
    if identity != IODART_FAMILY_UUID:
        raise ValueError(f"unsupported IODARTFamily UUID {identity}")
    functions = {
        name: symbol_code(image, name)
        for name in (
            IODART_MAPPER_GET_PAGE_SIZE,
            IODART_MAPPER_IOVM_INSERT,
            IODART_MAPPER_IOVM_INSERT_ONE,
        )
    }
    vtable_targets = {
        slot: recover_vtable_target(image, IODART_MAPPER_VTABLE, slot)
        for slot in (0x888, 0x8A0)
    }
    insert_address, insert_code = functions[IODART_MAPPER_IOVM_INSERT]
    table_address = read_adrp_add_address(
        insert_address, insert_code, 0x34, 0x38
    )
    direction_lookup = read_virtual_u32_table(image, table_address, 4)
    return {
        "uuid": identity,
        **recover_iodart_family_code_contract(
            functions, vtable_targets, direction_lookup
        ),
    }


def recover_apple_t8110_dart_code_contract(
    functions: dict[str, tuple[int, bytes]],
    bypass_property_prefix: str,
    sid_property_format: str,
) -> dict[str, object]:
    return _native_t6050.contract("recover_apple_t8110_dart_code_contract", functions, bypass_property_prefix=bypass_property_prefix, sid_property_format=sid_property_format)


def recover_apple_t8110_dart(image: bytes) -> dict[str, object]:
    identity = macho_uuid(image)
    if identity != APPLE_T8110_DART_UUID:
        raise ValueError(f"unsupported AppleT8110DART UUID {identity}")
    functions = {
        name: symbol_code(image, name)
        for name in (
            APPLE_T8110_DART_START,
            APPLE_T8110_DART_SETUP,
            APPLE_T8110_DART_GET_SID_PROPERTY,
            APPLE_T8110_DART_GET_SID_COUNT,
            APPLE_T8110_DART_IS_BYPASSED_SID,
            APPLE_T8110_DART_ENABLE_TRANSLATION,
            APPLE_T8110_DART_SET_TRANSLATION,
            APPLE_T8110_DART_SET_TRANSLATION_RANGE,
            APPLE_T8110_DART_INVALIDATE_TLB,
        )
    }
    setup_address, setup_code = functions[APPLE_T8110_DART_SETUP]
    bypass_property_prefix = read_adrp_add_cstring(
        image, setup_address, setup_code, 0xDE8, 0xDEC
    )
    property_address, property_code = functions[
        APPLE_T8110_DART_GET_SID_PROPERTY
    ]
    sid_property_format = read_adrp_add_cstring(
        image, property_address, property_code, 0x3C, 0x40
    )
    return {
        "uuid": identity,
        **recover_apple_t8110_dart_code_contract(
            functions, bypass_property_prefix, sid_property_format
        ),
    }


def recover_t8110_kernel_code_contract(
    functions: dict[str, tuple[int, bytes]],
    index_masks: tuple[int, ...],
    index_shifts: tuple[int, ...],
) -> dict[str, object]:
    return _native_t6050.contract("recover_t8110_kernel_code_contract", functions, index_masks=index_masks, index_shifts=index_shifts)


def recover_t8110_kernel(image: bytes) -> dict[str, object]:
    identity = macho_uuid(image)
    if identity != T6050_KERNEL_UUID:
        raise ValueError(f"unsupported T6050 kernel UUID {identity}")
    functions = {
        name: symbol_code(image, name)
        for name in (
            T8110_DART_MAX_TRANSLATION_LEVELS,
            T8110_DART_VO_TT_INDEX,
            T8110_DART_VO_TTE,
        )
    }
    index_address, index_code = functions[T8110_DART_VO_TT_INDEX]
    masks_address = read_adrp_add_address(index_address, index_code, 0x78, 0x7C)
    shifts_address = read_adrp_add_address(index_address, index_code, 0x88, 0x8C)
    masks_offset = virtual_to_file(image, masks_address)
    index_masks = struct.unpack_from("<4Q", image, masks_offset)
    index_shifts = read_virtual_u32_table(image, shifts_address, 4)
    return {
        "uuid": identity,
        **recover_t8110_kernel_code_contract(
            functions, index_masks, index_shifts
        ),
    }


def recover_apple_ascwrap_v6_code_contract(
    functions: dict[str, tuple[int, bytes]],
    vtable_targets: dict[int, int],
) -> dict[str, object]:
    return _native_t6050.contract("recover_apple_ascwrap_v6_code_contract", functions, vtable_targets=vtable_targets)


def recover_apple_ascwrap_v6(image: bytes) -> dict[str, object]:
    identity = macho_uuid(image)
    if identity != APPLE_ASCWRAP_V6_UUID:
        raise ValueError(f"unsupported AppleASCWrapV6 UUID {identity}")
    functions = {
        name: symbol_code(image, name)
        for name in (
            APPLE_ASCWRAP_V6_INITIALIZE,
            APPLE_ASCWRAP_V6_SET_IORVBAR,
            APPLE_ASCWRAP_V6_IS_IORVBAR_LOCKED,
            APPLE_ASCWRAP_V6_MAP_FIRMWARE,
            APPLE_ASCWRAP_V6_RUN_CPU,
            APPLE_ASCWRAP_V6_INBOX,
            APPLE_ASCWRAP_V6_OUTBOX,
            APPLE_ASCWRAP_V6_KIC_INBOX_ENABLED,
            APPLE_ASCWRAP_V6_INBOX_EMPTY,
            APPLE_ASCWRAP_V6_INBOX_FULL,
            APPLE_ASCWRAP_V6_OUTBOX_EMPTY,
            APPLE_ASCWRAP_V6_MAILBOX_ITEM_SIZE,
        )
    }
    initialize_address, initialize_code = functions[APPLE_ASCWRAP_V6_INITIALIZE]
    for (adrp_offset, add_offset), expected in {
        (0x84, 0x88): "nmi-ext-irq",
        (0xA4, 0xA8): "ext-irq-reg-index",
        (0x21C, 0x220): "idle-ctrl-check",
    }.items():
        actual = read_adrp_add_cstring(
            image, initialize_address, initialize_code, adrp_offset, add_offset
        )
        if actual != expected:
            raise ValueError(
                "AppleASCWrapV6 initialize string changed at "
                f"{adrp_offset:#x}: {actual!r}"
            )
    vtable_targets = {
        slot: recover_vtable_target(image, APPLE_ASCWRAP_V6_VTABLE, slot)
        for slot in (0x970, 0xA18, 0xA28)
    }
    return {
        "uuid": identity,
        "wrapper_v6": recover_apple_ascwrap_v6_code_contract(
            functions, vtable_targets
        ),
    }


def recover_t6050_pmp_darts(
    root: AdtNode,
    pmp_wrappers: dict[str, tuple[str, AdtNode]],
    die_stride: int,
) -> list[dict[str, object]]:
    expected_sids = [0, 1, 2, 5, 6, 7, 8, 9]
    expected_bypassed_sids = [2, 5, 6, 7, 8, 9]
    expected_translated_sids = [0, 1]
    result = []
    for die, role in enumerate(("PMP0", "PMP1")):
        dart_name = f"dart-pmp{die}"
        dart_path, dart = find_one(
            root,
            dart_name,
            lambda node, expected=dart_name: (
                node_name(node) == expected and compatible_with(node, "dart,t8110")
            ),
        )
        registers = parse_reg_regions(dart.property("reg"), f"{dart_name} reg")
        expected_registers = [
            (0x841A0000 + die * die_stride, 0xC000),
            (0x841B0000 + die * die_stride, 0x4000),
        ]
        sids = decode_u32_array(dart.property("sid"), f"{dart_name} sid")
        page_size = decode_integer(dart.property("page-size"), f"{dart_name} page-size")
        sid_count = decode_integer(dart.property("sid-count"), f"{dart_name} sid-count")
        options = decode_integer(dart.property("dart-options"), f"{dart_name} dart-options")
        flush_by_dva = decode_integer(
            dart.property("flush-by-dva"), f"{dart_name} flush-by-dva"
        )
        vm_base = decode_integer(dart.property("vm-base"), f"{dart_name} vm-base")
        vm_size = decode_integer(dart.property("vm-size"), f"{dart_name} vm-size")
        bypassed_sids = [
            sid for sid in range(sid_count) if f"bypass-{sid}" in dart.properties
        ]
        for sid in bypassed_sids:
            if dart.property(f"bypass-{sid}"):
                raise ValueError(
                    f"T6050 {dart_name} bypass-{sid} is no longer an empty boolean"
                )
        translated_sids = [sid for sid in sids if sid not in bypassed_sids]
        if (
            registers != expected_registers
            or sids != expected_sids
            or bypassed_sids != expected_bypassed_sids
            or translated_sids != expected_translated_sids
            or page_size != 0x4000
            or sid_count != 16
            or options != 0x65
            or flush_by_dva != 0
            or vm_base != 0x10000000000
            or vm_size != 0x1000000000
        ):
            raise ValueError(
                f"T6050 {dart_name} contract changed: regs={registers!r}, "
                f"sids={sids!r}, bypassed={bypassed_sids!r}, "
                f"translated={translated_sids!r}, page={page_size:#x}, count={sid_count}, "
                f"options={options:#x}, flush={flush_by_dva}, "
                f"vm={vm_base:#x}+{vm_size:#x}"
            )

        mapper_name = f"mapper-pmp{die}"
        mapper_path, mapper = find_one(
            dart,
            mapper_name,
            lambda node, expected=mapper_name: (
                node_name(node) == expected
                and compatible_with(node, "iommu-mapper")
            ),
        )
        if mapper_path.startswith(f"/{dart_name}"):
            mapper_path = dart_path + mapper_path[len(f'/{dart_name}') :]
        mapper_index = decode_integer(mapper.property("reg"), f"{mapper_name} reg")
        mapper_phandle = decode_integer(
            mapper.property("AAPL,phandle"), f"{mapper_name} phandle"
        )
        _wrapper_path, wrapper = pmp_wrappers[role]
        wrapper_parent = decode_integer(
            wrapper.property("iommu-parent"), f"{role} iommu-parent"
        )
        if mapper_index != 0 or wrapper_parent != mapper_phandle:
            raise ValueError(
                f"T6050 {role} mapper binding changed: index={mapper_index}, "
                f"wrapper={wrapper_parent:#x}, mapper={mapper_phandle:#x}"
            )
        result.append(
            {
                "die": die,
                "path": dart_path,
                "compatible": "dart,t8110",
                "registers": [
                    {"index": index, "base": base, "size": size}
                    for index, (base, size) in enumerate(registers)
                ],
                "page_size": page_size,
                "sid_count": sid_count,
                "active_sids": sids,
                "bypassed_sids": bypassed_sids,
                "translated_sids": translated_sids,
                "mapper": {
                    "path": mapper_path,
                    "index": mapper_index,
                    "phandle": mapper_phandle,
                    "wrapper_iommu_parent": wrapper_parent,
                },
                "managed_vm": {"base": vm_base, "size": vm_size},
                "iboot_firmware_iova_below_managed_vm": 0x1000000 < vm_base,
                "dart_options": options,
                "flush_by_dva": bool(flush_by_dva),
            }
        )
    return result


def recover_t6050_power(root: AdtNode) -> dict[str, object]:
    sgx_path, sgx = find_one(
        root,
        "gpu,t6050 SGX node",
        lambda node: node_name(node) == "sgx" and compatible_with(node, "gpu,t6050"),
    )
    _pmgr_path, pmgr = find_one(root, "PMGR node", lambda node: node_name(node) == "pmgr")
    devices = parse_pmgr_devices(pmgr.property("devices"))
    pmp_version = decode_integer(pmgr.property("pmp"), "pmgr pmp")
    if pmp_version != 2:
        raise ValueError(f"T6050 PMGR PMP version changed: {pmp_version}")
    ptd_range_ids = decode_u32_array(pmgr.property("ptd-ranges"), "pmgr ptd-ranges")
    if ptd_range_ids != [10, 11, 12, 13, 2, 4]:
        raise ValueError(f"T6050 PMGR PTD range bindings changed: {ptd_range_ids!r}")
    reg_regions = parse_reg_regions(pmgr.property("reg"), "pmgr reg")
    if len(reg_regions) != 60:
        raise ValueError(f"T6050 PMGR register-region count changed: {len(reg_regions)}")
    ptd_reg_index = 7
    ptd_region = reg_regions[ptd_reg_index]
    if ptd_region != (0x84240000, 0x40000):
        raise ValueError(f"T6050 ApplePTD register region changed: {ptd_region!r}")
    die_stride = decode_integer(pmgr.property("die-stride"), "pmgr die-stride")
    if die_stride != 0x4000000000:
        raise ValueError(f"T6050 PMGR die stride changed: {die_stride:#x}")

    # iBoot merges the selected chip-variant overlay into this node before the
    # OS reads it, so the base records are a prefix of the runtime property
    # rather than the whole of it.  Report both instead of guessing the count.
    base_interrupts = parse_pmgr_interrupt_config(
        pmgr.property(PMGR_INTERRUPT_CONFIG_PROPERTY), "pmgr interrupt-config"
    )
    variant_interrupts: dict[str, list[dict[str, object]]] = {}
    for child in pmgr.children:
        if PMGR_INTERRUPT_CONFIG_PROPERTY not in child.properties:
            continue
        name = node_name(child)
        variant_interrupts[name] = parse_pmgr_interrupt_config(
            child.property(PMGR_INTERRUPT_CONFIG_PROPERTY),
            f"pmgr {name} interrupt-config",
        )
    ready_records = [
        record
        for record in base_interrupts
        if record["name"] == PMP_READY_INTERRUPT_NAME
    ]
    if len(ready_records) != 1:
        raise ValueError(
            f"T6050 PMGR PMP readiness interrupt records changed: {ready_records!r}"
        )
    ready_slot = ready_records[0]["slot"]
    for name, records in variant_interrupts.items():
        for record in records:
            if record["name"] == PMP_READY_INTERRUPT_NAME:
                raise ValueError(
                    f"T6050 PMGR variant {name} redefines the PMP readiness interrupt"
                )
            if record["slot"] < len(base_interrupts):
                raise ValueError(
                    f"T6050 PMGR variant {name} reuses a base interrupt slot"
                )

    pmp_wrappers: dict[str, tuple[str, AdtNode]] = {}
    for path, node in walk_adt(root):
        role_property = node.properties.get("role")
        if role_property is None or not compatible_with(node, "iop,ascwrap-v6"):
            continue
        role = decode_cstring(role_property.data, "PMP role")
        if role not in ("PMP0", "PMP1"):
            continue
        if role in pmp_wrappers:
            raise ValueError(f"duplicate T6050 {role} wrapper")
        pmp_wrappers[role] = (path, node)
    if set(pmp_wrappers) != {"PMP0", "PMP1"}:
        raise ValueError(f"unexpected T6050 PMP die roles: {sorted(pmp_wrappers)!r}")
    ptd_die_bases = [ptd_region[0] + die * die_stride for die in range(2)]
    pmp_darts = recover_t6050_pmp_darts(root, pmp_wrappers, die_stride)

    wrapper_registers: dict[str, list[tuple[int, int]]] = {}
    wrapper_interrupts: dict[str, list[int]] = {}
    expected_wrapper_regs = [
        (0x84E00000, 0x88000),
        (0x84850000, 0x4000),
        (0x84500000, 0x100000),
        (0x84250000, 0x4000),
    ]
    expected_wrapper_interrupts = {
        "PMP0": [0x18D, 0x18C, 0x18F, 0x18E],
        "PMP1": [0xDAD, 0xDAC, 0xDAF, 0xDAE],
    }
    expected_wrapper_gates = {
        "PMP0": [0x1B, 0x1C],
        "PMP1": [0x1000001B, 0x1000001C],
    }
    for die, role in enumerate(("PMP0", "PMP1")):
        _path, wrapper = pmp_wrappers[role]
        registers = parse_reg_regions(wrapper.property("reg"), f"{role} reg")
        expected_registers = [
            (base + die * die_stride, size) for base, size in expected_wrapper_regs
        ]
        interrupts = decode_u32_array(wrapper.property("interrupts"), f"{role} interrupts")
        power_gates = decode_u32_array(wrapper.property("power-gates"), f"{role} power-gates")
        clock_gates = decode_u32_array(wrapper.property("clock-gates"), f"{role} clock-gates")
        if registers != expected_registers:
            raise ValueError(f"T6050 {role} wrapper registers changed: {registers!r}")
        if interrupts != expected_wrapper_interrupts[role]:
            raise ValueError(f"T6050 {role} interrupts changed: {interrupts!r}")
        if power_gates != expected_wrapper_gates[role] or clock_gates != power_gates:
            raise ValueError(
                f"T6050 {role} gate bindings changed: "
                f"power={power_gates!r}, clock={clock_gates!r}"
            )
        if (
            decode_integer(wrapper.property("iop-version"), f"{role} iop-version") != 1
            or decode_integer(
                wrapper.property("ptd-update-reg-index"),
                f"{role} ptd-update-reg-index",
            )
            != 3
            or decode_integer(wrapper.property("sram-index"), f"{role} sram-index")
            != 1
        ):
            raise ValueError(f"T6050 {role} wrapper control properties changed")
        if "cpu-ctrl-filtered" in wrapper.properties:
            raise ValueError(f"T6050 {role} unexpectedly filters CPU control")
        wrapper_registers[role] = registers
        wrapper_interrupts[role] = interrupts

    power_handles = decode_u32_array(sgx.property("power-gates"), "sgx power-gates")
    clock_handles = decode_u32_array(sgx.property("clock-gates"), "sgx clock-gates")
    power_gates = [resolve_gate(handle, devices) for handle in power_handles]
    clock_gates = [resolve_gate(handle, devices) for handle in clock_handles]
    expected_gates = [(0x268, "GFX_SGX"), (0x267, "GFX_BUSY")]
    actual_power = [(int(gate["handle"]), str(gate["name"])) for gate in power_gates]
    actual_clock = [(int(gate["handle"]), str(gate["name"])) for gate in clock_gates]
    if actual_power != expected_gates or actual_clock != expected_gates:
        raise ValueError(
            "T6050 SGX gate order changed: "
            f"power={actual_power!r}, clock={actual_clock!r}"
        )

    pmp_path, pmp = find_one(
        root,
        "T6050 PMP wrapper",
        lambda node: (
            node.properties.get("role") is not None
            and decode_cstring(node.property("role"), "PMP role") == "PMP1"
            and compatible_with(node, "iop,ascwrap-v6")
        ),
    )
    nub_path, nub = find_one(
        pmp,
        "t6050pmp RTKit nub",
        lambda node: (
            node.properties.get("firmware-name") is not None
            and decode_cstring(node.property("firmware-name"), "firmware-name") == "t6050pmp"
            and compatible_with(node, "iop-nub,rtbuddy-v2")
        ),
    )
    # find_one() starts paths at its supplied root; retain an absolute path in
    # the report without leaking the Preboot volume path.
    if nub_path.startswith(f"/{node_name(pmp)}"):
        nub_path = pmp_path + nub_path[len(f'/{node_name(pmp)}') :]

    pmp0_path, pmp0 = pmp_wrappers["PMP0"]
    pmp0_nub_path, pmp0_nub = find_one(
        pmp0,
        "t6050pmp PMP0 RTKit nub",
        lambda node: (
            node.properties.get("firmware-name") is not None
            and decode_cstring(node.property("firmware-name"), "firmware-name")
            == "t6050pmp"
            and compatible_with(node, "iop-nub,rtbuddy-v2")
        ),
    )
    if pmp0_nub_path.startswith(f"/{node_name(pmp0)}"):
        pmp0_nub_path = pmp0_path + pmp0_nub_path[len(f'/{node_name(pmp0)}') :]
    for property_name in ("soc-device", "ptd-range", "pm-ptd-ranges"):
        if pmp0_nub.property(property_name) != nub.property(property_name):
            raise ValueError(f"T6050 PMP die {property_name} tables differ")
    pmp_regions = [
        (
            decode_integer(pmp0_nub.property("region-base"), "PMP0 region-base"),
            decode_integer(pmp0_nub.property("region-size"), "PMP0 region-size"),
        ),
        (
            decode_integer(nub.property("region-base"), "PMP1 region-base"),
            decode_integer(nub.property("region-size"), "PMP1 region-size"),
        ),
    ]
    if pmp_regions != [(0x284500000, 0x100000), (0x4284500000, 0x100000)]:
        raise ValueError(f"T6050 PMP shared regions changed: {pmp_regions!r}")
    if pmp_regions[1][0] - pmp_regions[0][0] != die_stride:
        raise ValueError("T6050 PMP shared-region delta no longer matches die stride")

    soc_devices = parse_pmp_soc_devices(nub.property("soc-device"))
    agx_devices = [device for device in soc_devices if device["name"] == "AGX"]
    if (
        len(agx_devices) != 1
        or agx_devices[0]["id"] != 0x10
        or agx_devices[0]["index"] != 15
    ):
        raise ValueError(f"unexpected PMP AGX SoC-device records: {agx_devices!r}")

    ptd_ranges = parse_pmp_ptd_ranges(nub.property("ptd-range"))
    ptd_by_name = {str(item["name"]): item for item in ptd_ranges}
    if len(ptd_by_name) != len(ptd_ranges):
        raise ValueError("PMP ptd-range property contains duplicate names")
    expected_dashboard = {
        "SOC-DEV-PKT": (9, 0x90, 0x150),
        "SOC-DEV-PS-REQ": (10, 0x1E0, 8),
        "SOC-DEV-PS-ACK": (11, 0x1E8, 8),
    }
    readiness_range = ptd_by_name.get("PMP-STATUS")
    if readiness_range is None:
        raise ValueError("PMP DeviceTree has no PMP-STATUS PTD range")
    readiness_actual = (
        readiness_range["id"],
        readiness_range["entry_offset"],
        readiness_range["entry_count"],
        readiness_range["doorbell"],
    )
    if readiness_actual != (2, 1, 1, 16):
        raise ValueError(f"PMP readiness range changed: {readiness_actual!r}")
    dashboard: dict[str, dict[str, object]] = {}
    for name, expected in expected_dashboard.items():
        item = ptd_by_name.get(name)
        if item is None:
            raise ValueError(f"PMP DeviceTree has no {name} PTD range")
        actual = (item["id"], item["entry_offset"], item["entry_count"])
        if actual != expected:
            raise ValueError(f"PMP {name} PTD range changed: {actual!r}")
        dashboard[name] = item
    power_range_ids = decode_u32_array(nub.property("pm-ptd-ranges"), "pm-ptd-ranges")
    if power_range_ids != [1, 2, 3, 4, 5, 6, 7, 8, 40, 9, 10, 11, 12, 13, 14]:
        raise ValueError(f"T6050 PMP power PTD bindings changed: {power_range_ids!r}")
    if any(item["id"] not in power_range_ids for item in dashboard.values()):
        raise ValueError("PMP power PTD list omits a device-state dashboard range")
    if readiness_range["id"] not in power_range_ids:
        raise ValueError("PMP power PTD list omits the readiness status range")

    packet_range = dashboard["SOC-DEV-PKT"]
    packet_cursor = int(packet_range["entry_offset"])
    virtual_state_index = 0
    for device in soc_devices:
        packet_bits = int(device["packet_bytes"]) * 8
        device["packet_bit_offset"] = packet_cursor
        device["packet_bit_count"] = packet_bits
        packet_cursor += packet_bits
        if int(device["virtual_state_config"]):
            device["virtual_state_index"] = virtual_state_index
            virtual_state_index += 1
        else:
            device["virtual_state_index"] = None
    packet_end = int(packet_range["entry_offset"]) + int(packet_range["entry_count"])
    if packet_cursor > packet_end:
        raise ValueError("PMP SoC-device packet slices exceed SOC-DEV-PKT")
    agx_device = agx_devices[0]
    expected_agx_layout = (0x1C0, 8, 3, 3)
    actual_agx_layout = (
        agx_device["packet_bit_offset"],
        agx_device["packet_bit_count"],
        agx_device["virtual_state_index"],
        agx_device["state_flags"],
    )
    if actual_agx_layout != expected_agx_layout:
        raise ValueError(f"PMP AGX packet layout changed: {actual_agx_layout!r}")
    if packet_end - packet_cursor != 16:
        raise ValueError(
            f"PMP SOC-DEV-PKT trailing reserve changed: {packet_end - packet_cursor} bits"
        )

    gfx_handles: dict[str, dict[str, object]] = {}
    for handle, expected_name in ((0x266, "GFX_ASC"), (0x291, "GFX_ASC1")):
        gate = resolve_gate(handle, devices)
        if gate["name"] != expected_name:
            raise ValueError(
                f"T6050 handle {handle:#x} changed from {expected_name} to {gate['name']}"
            )
        gfx_handles[expected_name] = gate

    all_leaf_gates = power_gates + list(gfx_handles.values())
    for gate in all_leaf_gates:
        dispatch = gate["pmp_dispatch"]
        actual = (
            dispatch["flags"],
            dispatch["selector"],
            dispatch["virtual_class"],
            dispatch["emits_device_state"],
            dispatch["virtual_device"],
        )
        if actual != (0x10, 0, 0, False, True):
            raise ValueError(
                f"T6050 {gate['name']} leaf PMP flags changed: {actual!r}"
            )

    gfx_devices = [device for device in devices if device.name == "GFX"]
    if len(gfx_devices) != 1:
        raise ValueError(f"unexpected aggregate GFX PMGR records: {gfx_devices!r}")
    gfx_device = gfx_devices[0]
    device_state_target = resolve_gate(gfx_device.handle, devices)
    target_dispatch = device_state_target["pmp_dispatch"]
    actual_target = (
        device_state_target["handle"],
        target_dispatch["flags"],
        target_dispatch["selector"],
        target_dispatch["virtual_class"],
        target_dispatch["emits_device_state"],
        target_dispatch["virtual_device"],
    )
    if actual_target != (0x16A, 0x02, 0x10, 0, True, False):
        raise ValueError(f"T6050 aggregate GFX PMP proxy changed: {actual_target!r}")
    if target_dispatch["selector"] != agx_device["id"]:
        raise ValueError("aggregate GFX selector no longer targets PMP AGX")

    return {
        "schema": 23,
        "chip": "t6050",
        "pmgr_interrupts": {
            "property": PMGR_INTERRUPT_CONFIG_PROPERTY,
            "base_records": base_interrupts,
            "variant_records": variant_interrupts,
            "ready_interrupt_name": PMP_READY_INTERRUPT_NAME,
            "ready_slot": ready_slot,
            "runtime_interrupts_per_die": (
                "length of the merged base+variant property / 20; only the "
                "running system observes the selected variant"
            ),
        },
        "sgx": {
            "path": sgx_path,
            "power_gates": power_gates,
            "clock_gates": clock_gates,
        },
        "gfx_asc_gates": gfx_handles,
        "apple_ptd_mmio": {
            "reg_map": 8,
            "device_tree_reg_index": ptd_reg_index,
            "region_size": ptd_region[1],
            "die_stride": die_stride,
            "die_bases": ptd_die_bases,
            "mapping": "Device MMIO; never normal-cacheable memory",
        },
        "pmp": {
            "path": pmp_path,
            "nub_path": nub_path,
            "role": "PMP1",
            "firmware": "t6050pmp",
            "version": pmp_version,
            "region_base": decode_integer(nub.property("region-base"), "PMP region-base"),
            "region_size": decode_integer(nub.property("region-size"), "PMP region-size"),
            "dies": [
                {
                    "die": 0,
                    "role": "PMP0",
                    "path": pmp0_path,
                    "nub_path": pmp0_nub_path,
                    "region_base": pmp_regions[0][0],
                    "region_size": pmp_regions[0][1],
                    "wrapper_registers": [
                        {"index": index, "base": base, "size": size}
                        for index, (base, size) in enumerate(wrapper_registers["PMP0"])
                    ],
                    "interrupts": wrapper_interrupts["PMP0"],
                    "iop_version": 1,
                    "cpu_control_filtered": False,
                    "ptd_update_reg_index": 3,
                    "sram_power_domain": {
                        "property": "sram-index",
                        "selector": 1,
                        "not_a_register_index": True,
                    },
                },
                {
                    "die": 1,
                    "role": "PMP1",
                    "path": pmp_path,
                    "nub_path": nub_path,
                    "region_base": pmp_regions[1][0],
                    "region_size": pmp_regions[1][1],
                    "wrapper_registers": [
                        {"index": index, "base": base, "size": size}
                        for index, (base, size) in enumerate(wrapper_registers["PMP1"])
                    ],
                    "interrupts": wrapper_interrupts["PMP1"],
                    "iop_version": 1,
                    "cpu_control_filtered": False,
                    "ptd_update_reg_index": 3,
                    "sram_power_domain": {
                        "property": "sram-index",
                        "selector": 1,
                        "not_a_register_index": True,
                    },
                },
            ],
            "darts": pmp_darts,
            "agx_soc_device": agx_device,
            "soc_device_count": len(soc_devices),
            "soc_device_packet": {
                "unit": "bits",
                "consumed_bits": packet_cursor - int(packet_range["entry_offset"]),
                "trailing_reserved_bits": packet_end - packet_cursor,
            },
            "device_index_map": {
                "key": "soc-device id",
                "value": "soc-device record index",
                "agx_key": agx_device["id"],
                "agx_value": agx_device["index"],
            },
            "device_state_target": device_state_target,
            "leaf_gate_state_notifications": False,
            "readiness_status_range": readiness_range,
            "device_state_dashboard": dashboard,
        },
    }


def find_device_tree(preboot: Path) -> Path:
    candidates = sorted(
        path
        for path in preboot.glob("*/boot/*/usr/standalone/firmware/devicetree.img4")
        if path.is_file()
    )
    if len(candidates) != 1:
        rendered = ", ".join(str(path) for path in candidates) or "none"
        raise ValueError(f"expected one boot DeviceTree, found: {rendered}")
    return candidates[0]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device-tree", type=Path, help="override devicetree.img4")
    parser.add_argument("--preboot", type=Path, default=DEFAULT_PREBOOT)
    parser.add_argument("--pmgr", type=Path, default=DEFAULT_APPLE_PMGR)
    parser.add_argument(
        "--t6050-pmgr", type=Path, default=DEFAULT_APPLE_T6050_PMGR
    )
    parser.add_argument("--pmp", type=Path, default=DEFAULT_APPLE_PMP)
    parser.add_argument(
        "--pmp-firmware", type=Path, default=DEFAULT_APPLE_PMP_FIRMWARE
    )
    parser.add_argument("--rtbuddy", type=Path, default=DEFAULT_RTBUDDY)
    parser.add_argument("--apple-a7iop", type=Path, default=DEFAULT_APPLE_A7IOP)
    parser.add_argument(
        "--ascwrap-v6", type=Path, default=DEFAULT_APPLE_ASCWRAP_V6
    )
    parser.add_argument(
        "--t8110-dart", type=Path, default=DEFAULT_APPLE_T8110_DART
    )
    parser.add_argument(
        "--iodart-family", type=Path, default=DEFAULT_IODART_FAMILY
    )
    parser.add_argument("--kernel", type=Path, default=DEFAULT_KERNEL)
    parser.add_argument("--pmp-image", type=Path, default=DEFAULT_PMP_IMAGE)
    parser.add_argument("--output", type=Path, default=Path("build/t6050-power.json"))
    args = parser.parse_args()
    try:
        source = args.device_tree or find_device_tree(args.preboot)
        payload = device_tree_im4p_payload(source.read_bytes())
        root = parse_adt(decompress_device_tree(payload))
        manifest = recover_t6050_power(root)
        pmgr_image = args.pmgr.read_bytes()
        pmgr_symbols = macho_symbols(pmgr_image)
        manifest["apple_pmgr"] = recover_apple_pmgr(pmgr_image)
        manifest["apple_t6050_pmgr"] = recover_apple_t6050_pmgr(
            args.t6050_pmgr.read_bytes(), pmgr_symbols
        )
        manifest["apple_pmp"] = recover_apple_pmp(
            args.pmp.read_bytes(), args.rtbuddy.read_bytes()
        )
        manifest["apple_pmp_firmware"] = recover_apple_pmp_firmware(
            args.pmp_firmware.read_bytes(), args.rtbuddy.read_bytes()
        )
        manifest["t6050pmp_patchbay"] = recover_t6050_pmp_patchbay(
            args.pmp_image.read_bytes(),
            manifest["apple_pmp_firmware"]["patchbay_format"],
        )
        manifest["apple_a7iop"] = recover_apple_a7iop(args.apple_a7iop.read_bytes())
        manifest["apple_ascwrap_v6"] = recover_apple_ascwrap_v6(
            args.ascwrap_v6.read_bytes()
        )
        manifest["apple_t8110_dart"] = recover_apple_t8110_dart(
            args.t8110_dart.read_bytes()
        )
        manifest["iodart_family"] = recover_iodart_family(
            args.iodart_family.read_bytes()
        )
        manifest["t8110_kernel"] = recover_t8110_kernel(
            args.kernel.read_bytes()
        )
    except (OSError, ValueError) as error:
        parser.error(str(error))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(manifest, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
