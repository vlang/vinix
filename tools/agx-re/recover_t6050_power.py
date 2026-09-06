#!/usr/bin/env python3
"""Recover the T6050 GPU power-owner contract from Apple's boot DeviceTree.

This is a read-only host tool.  It emits names, handles, and region metadata;
it never copies the DeviceTree payload into the repository output.
"""

from __future__ import annotations

import argparse
import ctypes
import json
import platform
import struct
from dataclasses import dataclass
from pathlib import Path

from extract_firmware import der_item
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
    return (value + alignment - 1) & -alignment


def device_tree_im4p_payload(blob: bytes) -> bytes:
    outer, end = der_item(blob, 0, 0x30)
    if end != len(blob):
        raise ValueError("trailing data after IMG4 DER sequence")
    kind, offset = der_item(outer, 0, 0x16)
    im4p, _offset = der_item(outer, offset, 0x30)
    if kind != b"IMG4":
        raise ValueError(f"not an IMG4 container (kind={kind!r})")

    inner_kind, inner_offset = der_item(im4p, 0, 0x16)
    image_type, inner_offset = der_item(im4p, inner_offset, 0x16)
    _description, inner_offset = der_item(im4p, inner_offset, 0x16)
    payload, _inner_offset = der_item(im4p, inner_offset, 0x04)
    if inner_kind != b"IM4P" or image_type != b"dtre":
        raise ValueError(
            f"not a DeviceTree IM4P (kind={inner_kind!r}, type={image_type!r})"
        )
    # Signed IMG4s may append compression and payload-signature metadata.  The
    # OCTET STRING remains the complete compressed DeviceTree.
    return payload


def decompress_device_tree(payload: bytes, initial_capacity: int | None = None) -> bytes:
    if not payload.startswith((b"bvx1", b"bvx2")):
        return payload
    if platform.system() != "Darwin":
        raise ValueError("LZFSE DeviceTree extraction requires macOS libcompression")
    try:
        library = ctypes.CDLL("/usr/lib/libcompression.dylib")
    except OSError as error:
        raise ValueError(f"cannot load macOS libcompression: {error}") from error
    decode = library.compression_decode_buffer
    decode.argtypes = (
        ctypes.c_void_p,
        ctypes.c_size_t,
        ctypes.c_void_p,
        ctypes.c_size_t,
        ctypes.c_void_p,
        ctypes.c_int,
    )
    decode.restype = ctypes.c_size_t
    source = ctypes.create_string_buffer(payload)
    capacity = initial_capacity or max(1 << 20, len(payload) * 4)
    while capacity <= MAX_DEVICE_TREE_BYTES:
        destination = ctypes.create_string_buffer(capacity)
        decoded = decode(
            destination,
            capacity,
            source,
            len(payload),
            None,
            COMPRESSION_LZFSE,
        )
        if decoded == 0:
            raise ValueError("macOS libcompression rejected the LZFSE DeviceTree payload")
        if decoded < capacity:
            return destination.raw[:decoded]
        capacity *= 2
    raise ValueError("decompressed DeviceTree exceeds the 64 MiB safety limit")


def parse_adt(blob: bytes) -> AdtNode:
    """Parse Apple's recursive, little-endian DeviceTree representation."""

    def parse_node(offset: int, depth: int) -> tuple[AdtNode, int]:
        if depth > 128:
            raise ValueError("DeviceTree nesting exceeds 128 nodes")
        if offset + 8 > len(blob):
            raise ValueError("truncated DeviceTree node header")
        property_count, child_count = struct.unpack_from("<II", blob, offset)
        offset += 8
        if property_count > 65536 or child_count > 65536:
            raise ValueError("implausible DeviceTree node counts")
        properties: dict[str, AdtProperty] = {}
        for _ in range(property_count):
            header_end = offset + ADT_PROPERTY_NAME_BYTES + 4
            if header_end > len(blob):
                raise ValueError("truncated DeviceTree property header")
            raw_name = blob[offset : offset + ADT_PROPERTY_NAME_BYTES]
            terminator = raw_name.find(b"\0")
            if terminator < 0:
                raise ValueError("unterminated DeviceTree property name")
            try:
                name = raw_name[:terminator].decode("ascii")
            except UnicodeDecodeError as error:
                raise ValueError("non-ASCII DeviceTree property name") from error
            encoded_length = struct.unpack_from("<I", blob, offset + ADT_PROPERTY_NAME_BYTES)[0]
            length = encoded_length & ADT_PROPERTY_LENGTH_MASK
            flags = encoded_length >> 24
            offset = header_end
            padded_length = align_up(length, 4)
            if offset + padded_length > len(blob):
                raise ValueError(f"truncated DeviceTree property {name!r}")
            if name in properties:
                raise ValueError(f"duplicate DeviceTree property {name!r}")
            properties[name] = AdtProperty(blob[offset : offset + length], flags)
            offset += padded_length
        children = []
        for _ in range(child_count):
            child, offset = parse_node(offset, depth + 1)
            children.append(child)
        return AdtNode(properties, tuple(children)), offset

    root, end = parse_node(0, 0)
    if end != len(blob):
        raise ValueError(f"{len(blob) - end} trailing bytes after DeviceTree root")
    return root


def decode_cstring(data: bytes, field: str) -> str:
    value = data.split(b"\0", 1)[0]
    try:
        return value.decode("ascii")
    except UnicodeDecodeError as error:
        raise ValueError(f"non-ASCII {field}") from error


def decode_string_list(data: bytes, field: str) -> list[str]:
    if not data or data[-1] != 0:
        raise ValueError(f"{field} is not a NUL-terminated string list")
    try:
        return [item.decode("ascii") for item in data[:-1].split(b"\0")]
    except UnicodeDecodeError as error:
        raise ValueError(f"non-ASCII {field}") from error


def decode_u32_array(data: bytes, field: str) -> list[int]:
    if len(data) % 4:
        raise ValueError(f"{field} length is not a multiple of four")
    return list(struct.unpack(f"<{len(data) // 4}I", data))


def decode_integer(data: bytes, field: str) -> int:
    if len(data) not in (4, 8):
        raise ValueError(f"{field} is neither a 32-bit nor a 64-bit integer")
    return int.from_bytes(data, "little")


def parse_reg_regions(data: bytes, field: str) -> list[tuple[int, int]]:
    if not data or len(data) % 16:
        raise ValueError(f"{field} is not an array of 64-bit address/size pairs")
    return [
        struct.unpack_from("<QQ", data, offset)
        for offset in range(0, len(data), 16)
    ]


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
    if not data or len(data) % PMGR_DEVICE_BYTES:
        raise ValueError("PMGR devices property is not an array of 48-byte records")
    result = []
    for index, offset in enumerate(range(0, len(data), PMGR_DEVICE_BYTES)):
        record = data[offset : offset + PMGR_DEVICE_BYTES]
        name = decode_cstring(record[PMGR_DEVICE_NAME_OFFSET:], "PMGR device name")
        handle = struct.unpack_from("<H", record, PMGR_DEVICE_HANDLE_OFFSET)[0]
        result.append(
            PmgrDevice(
                index,
                handle,
                name,
                record[0],
                record[3],
                int.from_bytes(record[15:16], "little", signed=True),
            )
        )
    return result


def resolve_gate(handle: int, devices: list[PmgrDevice]) -> dict[str, object]:
    matches = [device for device in devices if device.handle == handle]
    if len(matches) != 1:
        names = ", ".join(device.name for device in matches) or "none"
        raise ValueError(f"power handle {handle:#x} has non-unique PMGR mapping: {names}")
    device = matches[0]
    virtual_device = bool(device.flags & 0x10 and device.pmp_virtual_class >= 0)
    emits_device_state = bool(device.flags & 0x02)
    return {
        "handle": handle,
        "name": device.name,
        "record_index": device.index,
        "pmp_dispatch": {
            "flags": device.flags,
            "selector": device.pmp_selector,
            "virtual_class": device.pmp_virtual_class,
            "emits_device_state": emits_device_state,
            "virtual_device": virtual_device,
            "route_if_emitted": "virtual" if virtual_device else "ordinary",
        },
    }


def parse_pmp_soc_devices(data: bytes) -> list[dict[str, object]]:
    if not data or len(data) % PMP_SOC_DEVICE_BYTES:
        raise ValueError("PMP soc-device property is not an array of 124-byte records")
    result = []
    for index, offset in enumerate(range(0, len(data), PMP_SOC_DEVICE_BYTES)):
        record = data[offset : offset + PMP_SOC_DEVICE_BYTES]
        result.append(
            {
                "index": index,
                "id": struct.unpack_from("<I", record)[0],
                # The stripped PMP firmware shifts this field left by three
                # while assigning each record's SOC-DEV-PKT subrange.
                "packet_bytes": struct.unpack_from("<I", record, 0x0C)[0],
                # Bit 1 requests a PS-ACK synchronization.  Bit 2 suppresses
                # that wait for a transition to state 1 only.
                "state_flags": struct.unpack_from("<I", record, 0x08)[0],
                # ApplePMGR assigns a dense virtual-dashboard index to every
                # record with a nonzero word at +0x2c.
                "virtual_state_config": struct.unpack_from("<I", record, 0x2C)[0],
                "name": decode_cstring(
                    record[PMP_SOC_DEVICE_NAME_OFFSET:], "PMP SoC-device name"
                ),
            }
        )
    return result


def parse_pmp_ptd_ranges(data: bytes) -> list[dict[str, object]]:
    if not data or len(data) % PMP_PTD_RANGE_BYTES:
        raise ValueError("PMP ptd-range property is not an array of 32-byte records")
    result = []
    for index, offset in enumerate(range(0, len(data), PMP_PTD_RANGE_BYTES)):
        record = data[offset : offset + PMP_PTD_RANGE_BYTES]
        range_id, entry_offset, entry_count, doorbell = struct.unpack_from("<4I", record)
        result.append(
            {
                "index": index,
                "id": range_id,
                "entry_offset": entry_offset,
                "entry_count": entry_count,
                "doorbell": doorbell,
                "name": decode_cstring(
                    record[PMP_PTD_RANGE_NAME_OFFSET:], "PMP PTD-range name"
                ),
            }
        )
    return result


def direct_branch_targets(function_address: int, code: bytes) -> set[int]:
    """Return direct AArch64 B/BL targets from one function body."""
    result = set()
    for offset in range(0, len(code) - 3, 4):
        word = struct.unpack_from("<I", code, offset)[0]
        if word & 0x7C000000 != 0x14000000:
            continue
        immediate = word & 0x03FFFFFF
        if immediate & 0x02000000:
            immediate -= 1 << 26
        result.add((function_address + offset + immediate * 4) & 0xFFFFFFFFFFFFFFFF)
    return result


def pc_relative_targets(function_address: int, code: bytes) -> set[int]:
    """Return ADRP+ADD materialized addresses from one function body.

    IOCommandGate actions and registered callbacks are never direct branches,
    so branch scanning alone cannot observe them.  Any instruction that writes
    a tracked register without being one half of an ADRP/ADD pair drops that
    register, so a reused page base cannot fabricate a target.
    """
    result: set[int] = set()
    pages: dict[int, int] = {}
    for offset in range(0, len(code) - 3, 4):
        word = struct.unpack_from("<I", code, offset)[0]
        page = decode_adrp(function_address + offset, word)
        if page is not None:
            pages[page[0]] = page[1]
            continue
        add = decode_add_immediate(word)
        if add is not None:
            destination, source, immediate = add
            if source in pages:
                pages[destination] = (pages[source] + immediate) & 0xFFFFFFFFFFFFFFFF
                result.add(pages[destination])
            else:
                pages.pop(destination, None)
            continue
        pages.pop(word & 0x1F, None)
    return result


def direct_branch_count(function_address: int, code: bytes, target: int) -> int:
    """Count direct AArch64 B/BL instructions to one target."""
    result = 0
    for offset in range(0, len(code) - 3, 4):
        word = struct.unpack_from("<I", code, offset)[0]
        if word & 0x7C000000 != 0x14000000:
            continue
        immediate = word & 0x03FFFFFF
        if immediate & 0x02000000:
            immediate -= 1 << 26
        actual = (function_address + offset + immediate * 4) & 0xFFFFFFFFFFFFFFFF
        result += actual == target
    return result


def direct_branch_target_at(function_address: int, code: bytes, offset: int) -> int | None:
    """Decode one direct AArch64 B/BL at a known function-relative offset."""
    if offset < 0 or offset + 4 > len(code):
        return None
    word = struct.unpack_from("<I", code, offset)[0]
    if word & 0x7C000000 != 0x14000000:
        return None
    immediate = word & 0x03FFFFFF
    if immediate & 0x02000000:
        immediate -= 1 << 26
    return (function_address + offset + immediate * 4) & 0xFFFFFFFFFFFFFFFF


def _has_sub_cmp_window(code: bytes, source: int, first: int, count: int) -> bool:
    """Recognize `sub wN,wSource,#first; cmp wN,#count` without fixing wN."""
    words = [struct.unpack_from("<I", code, offset)[0] for offset in range(0, len(code) - 3, 4)]
    for left, right in zip(words, words[1:]):
        if left & 0xFF000000 != 0x51000000:
            continue
        destination = left & 0x1F
        left_source = (left >> 5) & 0x1F
        immediate = (left >> 10) & 0xFFF
        if left & (1 << 22):
            immediate <<= 12
        if (left_source, immediate) != (source, first):
            continue
        if right & 0xFF00001F != 0x7100001F:
            continue
        right_source = (right >> 5) & 0x1F
        right_immediate = (right >> 10) & 0xFFF
        if right & (1 << 22):
            right_immediate <<= 12
        if (right_source, right_immediate) == (destination, count):
            return True
    return False


def _has_cmp_w_immediate(code: bytes, source: int, immediate: int) -> bool:
    for offset in range(0, len(code) - 3, 4):
        word = struct.unpack_from("<I", code, offset)[0]
        if word & 0xFF00001F != 0x7100001F or (word >> 5) & 0x1F != source:
            continue
        value = (word >> 10) & 0xFFF
        if word & (1 << 22):
            value <<= 12
        if value == immediate:
            return True
    return False


def _has_ldrb(code: bytes, destination: int, base: int, immediate: int) -> bool:
    for offset in range(0, len(code) - 3, 4):
        word = struct.unpack_from("<I", code, offset)[0]
        if word & 0xFFC00000 != 0x39400000:
            continue
        if (
            word & 0x1F,
            (word >> 5) & 0x1F,
            (word >> 10) & 0xFFF,
        ) == (destination, base, immediate):
            return True
    return False


def _has_words_in_order(code: bytes, expected: tuple[int, ...]) -> bool:
    """Recognize a short UUID-pinned instruction slice with no gaps."""
    if not expected:
        return True
    needle = struct.pack(f"<{len(expected)}I", *expected)
    return code.find(needle) >= 0


def _has_ordered_words(code: bytes, expected: tuple[int, ...]) -> bool:
    """Recognize instruction words in program order while allowing a gap."""
    offset = 0
    for word in expected:
        found = code.find(struct.pack("<I", word), offset)
        if found < 0:
            return False
        offset = found + 4
    return True


def recover_apple_ptd_code_contract(
    functions: dict[str, tuple[int, bytes]], symbols: dict[str, int]
) -> dict[str, object]:
    """Recover ApplePTD's asymmetric read and write MMIO windows."""

    required = (APPLE_PTD_READ, APPLE_PTD_WRITE, PMGR_GET_REG_MAP, PMGR_WRITE_REG64)
    missing = [name for name in required if name not in symbols]
    if missing:
        raise ValueError(f"ApplePMGR is missing ApplePTD symbols: {missing!r}")
    for name in (APPLE_PTD_READ, APPLE_PTD_WRITE, PMGR_WRITE_REG64):
        if name not in functions:
            raise ValueError(f"ApplePMGR has no code body for {name}")

    read_address, read_code = functions[APPLE_PTD_READ]
    if (
        direct_branch_count(read_address, read_code, symbols[PMGR_GET_REG_MAP]) != 1
        or not _has_ordered_words(
            read_code,
            (
                0xB9400828,  # ldr w8, [x1, #8] -- range entry count
                0xF9400000,  # ldr x0, [x0] -- owning ApplePMGR
                0x52800101,  # mov w1, #8 -- PTD RegMap
                0xAA0403E2,  # mov x2, x4 -- die
                0xF9400C08,  # ldr x8, [x0, #0x18] -- mapped base
                0x531C6E89,  # lsl w9, w20, #4 -- entry * 16
                0x8B090108,  # add x8, x8, x9
                0xA9402508,  # ldp x8, x9, [x8] -- data and raw metadata
                0xD341FD2A,  # lsr x10, x9, #1
                0x39403E6B,  # ldrb w11, [x19, #0xf] -- retained tag
                0xD34AFD2C,  # lsr x12, x9, #10
                0xB349012C,  # bfi x12, x9, #55, #1 -- raw bit 0
                0xAA0BE189,  # orr x9, x12, x11, lsl #56
                0xB34A0149,  # bfi x9, x10, #54, #1 -- raw bit 1
                0xA9002668,  # stp x8, x9, [x19] -- decoded Entry
            ),
        )
    ):
        raise ValueError("ApplePTD read window or metadata decoding changed")

    write_address, write_code = functions[APPLE_PTD_WRITE]
    if (
        direct_branch_count(write_address, write_code, symbols[PMGR_WRITE_REG64]) != 1
        or not _has_ordered_words(
            write_code,
            (
                0xB9400828,  # ldr w8, [x1, #8] -- range entry count
                0xF9400000,  # ldr x0, [x0] -- owning ApplePMGR
                0x531D7048,  # lsl w8, w2, #3 -- entry * 8
                0x11404102,  # add w2, w8, #0x10, lsl #12 -- +0x10000
                0x52800101,  # mov w1, #8 -- PTD RegMap
            ),
        )
    ):
        raise ValueError("ApplePTD write portal changed")

    write_reg_address, write_reg_code = functions[PMGR_WRITE_REG64]
    if (
        direct_branch_count(write_reg_address, write_reg_code, symbols[PMGR_GET_REG_MAP])
        != 1
        or not _has_ordered_words(
            write_reg_code,
            (
                0xAA0303F5,  # mov x21, x3 -- value
                0xAA0203F3,  # mov x19, x2 -- byte offset
                0xAA0103F6,  # mov x22, x1 -- RegMap
                0xAA1403E2,  # mov x2, x20 -- die
                0xF9400C08,  # ldr x8, [x0, #0x18] -- mapped base
                0xF8334915,  # str x21, [x8, w19, uxtw]
            ),
        )
    ):
        raise ValueError("ApplePMGR 64-bit register write changed")

    return {
        "reg_map": 8,
        "read": {
            "base_offset": 0,
            "entry_stride": 16,
            "width_bytes": 16,
            "operation": "one 16-byte load of data and raw metadata",
        },
        "write": {
            "base_offset": 0x10000,
            "entry_stride": 8,
            "width_bytes": 8,
            "operation": "one 64-bit store through ApplePMGR::writeReg64",
        },
        "decoded_entry": {
            "data_word": 0,
            "metadata_word": 1,
            "raw_bits_10_63": "decoded metadata bits 0..53",
            "raw_bit_1": "decoded metadata bit 54 (newData)",
            "raw_bit_0": "decoded metadata bit 55",
            "caller_tag": "decoded metadata bits 56..63, retained from output +0xf",
        },
        "range_check": "entry_count must be nonzero; callers supply the entry index",
        "ordering": (
            "no explicit lock or DMB/DSB appears in the UUID-pinned read, write, "
            "or final register-store sequence; ordering depends on the Device MMIO mapping"
        ),
    }


def recover_pmp_readiness_handshake(
    functions: dict[str, tuple[int, bytes]], symbols: dict[str, int]
) -> dict[str, object]:
    """Recover the order between the initial PMP publication and readiness.

    ApplePMGR publishes the complete initial device status from `start`, while
    the PMP itself is still unobservable, and closes the readiness handshake
    later from the per-die PMP interrupt.  Both halves are pinned mechanically
    so an OS change cannot silently turn the publication into a ready-gated
    operation, nor turn the interrupt into the only readiness source.
    """

    start_address, start_code = functions[PMGR_START]
    if symbols[PMP_INIT_V2] not in direct_branch_targets(start_address, start_code):
        raise ValueError("ApplePMGR::start no longer runs the PMP v2 init")

    init_address, init_code = functions[PMP_INIT_V2]
    if symbols[PMP_NOTIFY_INITIAL] not in pc_relative_targets(init_address, init_code):
        raise ValueError("PMP v2 init no longer schedules the initial status walk")
    if not _has_ordered_words(
        init_code,
        (
            0xD2815711,  # mov x17, #0xab8 -- _pmpV2() admission
            0xF94DC260,  # ldr x0, [x19, #0x1b80] -- command gate
            0xD2803D11,  # mov x17, #0x1e8 -- runAction
        ),
    ):
        raise ValueError("PMP v2 init no longer gates the walk on its command gate")

    entry_address, entry_code = functions[PMP_NOTIFY_INITIAL_ENTRY]
    if symbols[PMP_NOTIFY_INITIAL] not in pc_relative_targets(
        entry_address, entry_code
    ):
        raise ValueError("public initial-status entry no longer runs its gated action")
    if not _has_ordered_words(entry_code, (0xF94DC000, 0xD2803D11)):
        raise ValueError("public initial-status entry no longer uses the command gate")

    initial_address, initial_code = functions[PMP_NOTIFY_INITIAL]
    if not _has_ordered_words(
        initial_code,
        (
            0x528C6088,  # mov w8, #0x6304 -- die count
            0x9140F808,  # add x8, x0, #0x3e, lsl #12
            0x9105F517,  # add x23, x8, #0x17d -- per-die device-type bytes
            0x528001D8,  # mov w24, #0xe -- base command
            0x52800039,  # mov w25, #1 -- published state
            0x39400108,  # ldrb w8, [x8] -- device type
            0x71003D1F,  # cmp w8, #0xf -- PMP-managed device type
            0x13001D08,  # sxtb w8, w8 -- signed DeviceData flag byte
            0x3100051F,  # cmn w8, #1
            0x1A98C701,  # cinc w1, w24, le -- command 14 or 15
            0xF10C7F5F,  # cmp x26, #0x31f -- last scanned device ID
            0x910C82F7,  # add x23, x23, #0x320 -- next die
        ),
    ):
        raise ValueError("initial PMP status walk changed")

    ready_wait_slot = struct.pack("<I", 0xD2815811)  # mov x17, #0xac0
    for scope, address, code in (
        ("PMP v2 init", init_address, init_code),
        ("initial PMP state sync", initial_address, initial_code),
    ):
        if ready_wait_slot in code:
            raise ValueError(f"{scope} unexpectedly gained a PMP readiness wait")
        targets = direct_branch_targets(address, code)
        if symbols[PMP_WAIT_READY] in targets or symbols[PMP_READY_GATED] in targets:
            raise ValueError(f"{scope} unexpectedly gained a PMP readiness dependency")
        if symbols[APPLE_PTD_READ] in targets:
            raise ValueError(f"{scope} unexpectedly gained an ApplePTD status read")

    interrupt_address, interrupt_code = functions[PMGR_HANDLE_INTERRUPT_ALL]
    if symbols[PMP_READY_GATED] not in pc_relative_targets(
        interrupt_address, interrupt_code
    ):
        raise ValueError("PMP readiness is no longer closed from the PMGR interrupt")
    if not _has_ordered_words(
        interrupt_code,
        (
            0x9140FE68,  # add x8, x19, #0x3f, lsl #12
            0x91048117,  # add x23, x8, #0x120 -- interrupt configuration block
            0xD2815711,  # mov x17, #0xab8 -- _pmpV2() admission
            0x394042E8,  # ldrb w8, [x23, #0x10] -- PMP ready slot
            0x7103FD1F,  # cmp w8, #0xff -- an absent slot closes nothing
            0xB94002E8,  # ldr w8, [x23] -- interrupts per die
            0x1AC80809,  # udiv w9, w0, w8 -- die
            0x1B088128,  # msub w8, w9, w8, w0 -- slot within the die
            0x394042E9,  # ldrb w9, [x23, #0x10]
            0x6B09011F,  # cmp w8, w9 -- only the PMP ready slot closes it
            0x9141CA68,  # add x8, x19, #0x72, lsl #12
            0x91208118,  # add x24, x8, #0x820 -- PMP-STATUS range
            0xD2803D11,  # mov x17, #0x1e8 -- runAction
        ),
    ):
        raise ValueError("PMP readiness interrupt decode changed")

    ready_v2_address, ready_v2_code = functions[PMP_READY_ACTION_V2]
    if symbols[PMP_READY_GATED] not in pc_relative_targets(
        ready_v2_address, ready_v2_code
    ):
        raise ValueError("per-die PMP ready entry no longer runs its gated action")
    if not _has_ordered_words(
        ready_v2_code,
        (
            0xAA0103E2,  # mov x2, x1 -- die becomes the gated argument
            0xF94DC000,  # ldr x0, [x0, #0x1b80] -- command gate
            0xD2803D11,  # mov x17, #0x1e8 -- runAction
        ),
    ):
        raise ValueError("per-die PMP ready entry no longer forwards its die")

    return {
        "initial_publication": {
            "driver_entry": PMGR_START,
            "scheduler": PMP_INIT_V2,
            "public_entry": PMP_NOTIFY_INITIAL_ENTRY,
            "gated_action": PMP_NOTIFY_INITIAL,
            "command_gate_action_slot": 0x1E8,
            "waits_for_ready": False,
            "reads_ptd_status": False,
            "device_type": 0x0F,
            "device_type_table_object_offset": 0x3E17D,
            "device_type_die_stride": 0x320,
            "first_device_id": 1,
            "last_device_id": 0x31F,
            "die_count_object_offset": 0x6304,
            "published_state": 1,
            "command_selection": (
                "command 14, or 15 when the signed DeviceData flag byte is negative"
            ),
            "order": (
                "ApplePMGR::start runs the whole publication inside _initPMPv2, "
                "so every initial level request precedes the first readiness "
                "observation; it is deliberate, not a race"
            ),
        },
        "ready_close": {
            "source": PMGR_HANDLE_INTERRUPT_ALL,
            "admission": PMGR_PMP_V2,
            "config_block_object_offset": 0x3F120,
            "interrupts_per_die_object_offset": 0x3F120,
            "ready_slot_object_offset": 0x3F130,
            "absent_slot_value": 0xFF,
            "die_selector": "interrupt index / interrupts-per-die",
            "slot_selector": "interrupt index % interrupts-per-die",
            "per_die_entry": PMP_READY_ACTION_V2,
            "gated_action": PMP_READY_GATED,
            "effect": (
                "latch the per-die ready byte, then command-gate wake every waiter"
            ),
            "secondary_source": (
                "_waitForPMPReadyActionGatedv2 latches the same byte on its own "
                "when the PTD PMP-STATUS entry becomes nonzero, so the interrupt "
                "is not the only way the handshake closes"
            ),
        },
    }


def recover_pmp_code_contract(
    functions: dict[str, tuple[int, bytes]], symbols: dict[str, int]
) -> dict[str, object]:
    required = (
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
        PMP_DEVICE_ID_TO_DATA,
        PMP_CHECK_NOTIFY,
        PMP_WAIT_READY,
        PMP_WAIT_READY_V2,
        PMP_READY_GATED,
        PMP_READY_ACTION_V2,
        PMGR_START,
        PMGR_HANDLE_INTERRUPT_ALL,
        APPLE_PTD_READ,
        APPLE_PTD_WRITE,
        PMGR_GET_REG_MAP,
        PMGR_WRITE_REG64,
    )
    missing = [name for name in required if name not in symbols]
    if missing:
        raise ValueError(f"ApplePMGR is missing power symbols: {missing!r}")
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
        APPLE_PTD_READ,
        APPLE_PTD_WRITE,
        PMGR_WRITE_REG64,
    ):
        if name not in functions:
            raise ValueError(f"ApplePMGR has no code body for {name}")

    ptd_transport = recover_apple_ptd_code_contract(functions, symbols)

    send_address, send_code = functions[PMP_SEND_COMMAND]
    if symbols[PMP_WRITE_DASHBOARD] not in direct_branch_targets(send_address, send_code):
        raise ValueError("sendPMPCommand no longer routes to the PMP dashboard")

    dispatch_address, dispatch_code = functions[PMP_WRITE_DASHBOARD]
    dispatch_targets = direct_branch_targets(dispatch_address, dispatch_code)
    if not _has_sub_cmp_window(dispatch_code, source=1, first=14, count=2):
        raise ValueError("PMP dashboard no longer selects the command-14/15 window")
    for target in (PMP_SET_DEVICE_STATE, PMP_SET_VIRTUAL_DEVICE_STATE):
        if symbols[target] not in dispatch_targets:
            raise ValueError(f"PMP dashboard no longer dispatches to {target}")
    if not _has_ordered_words(
        dispatch_code,
        (
            0x39400008,  # ldrb w8, [x0] -- DeviceData flags
            0x362003C8,  # tbz w8, #4 -- ordinary-device fallback
            0x39C03C08,  # ldrsb w8, [x0, #0xf] -- virtual class
            0x37F80388,  # tbnz w8, #31 -- ordinary-device fallback
        ),
    ):
        raise ValueError("PMP dashboard virtual-device dispatch predicate changed")

    state_address, state_code = functions[PMP_SET_DEVICE_STATE]
    state_targets = direct_branch_targets(state_address, state_code)
    if not _has_cmp_w_immediate(state_code, source=3, immediate=2):
        raise ValueError("PMP device dashboard no longer bounds state to 0/1")
    if not _has_ldrb(state_code, destination=8, base=0, immediate=3):
        raise ValueError("PMP device dashboard index is no longer DeviceData byte 3")
    for target in (APPLE_PTD_READ, APPLE_PTD_WRITE):
        if symbols[target] not in state_targets:
            raise ValueError(f"PMP device dashboard no longer calls {target}")
    if direct_branch_count(state_address, state_code, symbols[APPLE_PTD_WRITE]) != 1:
        raise ValueError("PMP device dashboard request write count changed")
    if not _has_ordered_words(
        state_code,
        (
            0x39400C08,  # ldrb w8, [x0, #3] -- DeviceData selector
            0xB9406B69,  # ldr w9, [x27, #0x68] -- selector die stride
            0x1B162128,  # madd w8, w9, w22, w8 -- selector + stride*die
            0xB9400153,  # ldr w19, [x10] -- mapped soc-device record index
            0x52837B88,  # mov w8, #0x1bdc -- multi-PMP flag byte
            0x39400108,  # ldrb w8, [x8]
            0x7200011F,  # tst w8, #1
            0x1A9F12D5,  # csel w21, w22, wzr, ne -- selected PTD die
        ),
    ):
        raise ValueError("PMP device-state selector or PTD die selection changed")
    if not _has_ordered_words(
        state_code,
        (
            0x52800029,  # mov w9, #1
            0x9AD3213A,  # lsl x26, x9, x19 -- 1 << soc-device index
            0xF9401B61,  # ldr x1, [x27, #0x30] -- PS-REQ range
            0xAA1A0109,  # orr x9, x8, x26 -- requested state 1
            0x8A3A0108,  # bic x8, x8, x26 -- requested state 0
            0x7100033F,  # cmp w25, #0
            0x9A890103,  # csel x3, x8, x9, eq -- select request value
            0xF9401B61,  # ldr x1, [x27, #0x30] -- write PS-REQ
        ),
    ):
        raise ValueError("PMP device-state request encoding changed")
    if not _has_ordered_words(
        state_code,
        (
            0xB9400148,  # ldr w8, [x10] -- soc-device state flags at +8
            0x360812C8,  # tbz w8, #1 -- no acknowledgement required
            0x53020908,  # ubfx w8, w8, #2, #1 -- skip-enable-ack flag
            0x52800C80,  # mov w0, #100
            0x52884801,  # mov w1, #0x4240
            0x72A001E1,  # movk w1, #0xf -- 1,000,000 (100 ms)
            0x528001E0,  # mov w0, #15
            0x52994001,  # mov w1, #0xca00
            0x72A77341,  # movk w1, #0x3b9a -- 1,000,000,000 (15 s)
            0xF9402B61,  # ldr x1, [x27, #0x50] -- PMP-STATUS range
            0xF9401F61,  # ldr x1, [x27, #0x38] -- PS-ACK range
            0xA979A3B3,  # ldp x19, x8, [x29, #-0x68] -- ack data/metadata
            0x924A0114,  # and x20, x8, #0x40000000000000 -- newData bit 54
            0xB4FFF234,  # cbz x20 -- poll until newData
            0xCA080268,  # eor x8, x19, x8 -- ack versus requested value
            0x8A1A0108,  # and x8, x8, x26 -- compare this device bit
            0xB5FFF1A8,  # cbnz x8 -- poll until requested value matches
            0xF9402F68,  # ldr x8, [x27, #0x58] -- PMPTOOL diagnostics
        ),
    ):
        raise ValueError("PMP device-state acknowledgement loop changed")

    # The initial state publisher deliberately runs before PMP readiness.  Its
    # safety depends on this exact state-machine edge: the level request is
    # written first, then PMP-STATUS is sampled.  A zero status latches the
    # per-die ready byte to zero and branches to the successful return without
    # touching PS-ACK.  Once status is nonzero, the fallthrough reads PS-ACK.
    status_prefix = struct.pack(
        "<5I",
        0xF9400380,  # ldr x0, [x28] -- ApplePTD owner
        0xF9402B61,  # ldr x1, [x27, #0x50] -- PMP-STATUS range
        0xB9400422,  # ldr w2, [x1, #4] -- status PTD entry
        0xD101A3A3,  # sub x3, x29, #0x68 -- returned Entry
        0xAA1503E4,  # mov x4, x21 -- selected PTD die
    )
    status_offset = state_code.find(status_prefix)
    status_suffix = struct.pack(
        "<4I",
        0xF85983A8,  # ldur x8, [x29, #-0x68] -- status data
        0xF100011F,  # cmp x8, #0
        0x1A9F07E8,  # cset w8, ne
        0x39000328,  # strb w8, [x25] -- per-die ready byte
    )
    if (
        status_offset < 0
        or direct_branch_target_at(state_address, state_code, status_offset + 20)
        != symbols[APPLE_PTD_READ]
        or state_code[status_offset + 24 : status_offset + 40] != status_suffix
    ):
        raise ValueError("PMP device-state status probe changed")

    ready_offset = state_code.find(struct.pack("<I", 0x39400328), status_offset + 40)
    ready_branch = (
        decode_test_bit_branch(
            state_address + ready_offset + 4,
            struct.unpack_from("<I", state_code, ready_offset + 4)[0],
        )
        if ready_offset >= 0 and ready_offset + 8 <= len(state_code)
        else None
    )
    ack_prefix = struct.pack(
        "<5I",
        0xF9400380,  # ldr x0, [x28] -- ApplePTD owner
        0xF9401F61,  # ldr x1, [x27, #0x38] -- PS-ACK range
        0xB9400422,  # ldr w2, [x1, #4] -- ack PTD entry
        0xD101A3A3,  # sub x3, x29, #0x68 -- returned Entry
        0xAA1503E4,  # mov x4, x21 -- selected PTD die
    )
    success_target = ready_branch["target"] if ready_branch is not None else -1
    success_offset = success_target - state_address
    if (
        ready_branch is None
        or ready_branch != {
            "target": success_target,
            "condition": "bit_clear",
            "register": 8,
            "bit": 0,
            "bytes": 4,
        }
        or state_code[ready_offset + 8 : ready_offset + 28] != ack_prefix
        or direct_branch_target_at(state_address, state_code, ready_offset + 28)
        != symbols[APPLE_PTD_READ]
        or success_offset < ready_offset + 32
        or success_offset + 4 > len(state_code)
        or struct.unpack_from("<I", state_code, success_offset)[0] != 0x52800014
    ):
        raise ValueError("PMP device-state pre-ready acknowledgement bypass changed")

    write_offsets = [
        offset
        for offset in range(0, len(state_code) - 3, 4)
        if direct_branch_target_at(state_address, state_code, offset)
        == symbols[APPLE_PTD_WRITE]
    ]
    if len(write_offsets) != 1:
        raise ValueError("PMP device-state request write ownership changed")
    if not write_offsets[0] < status_offset < ready_offset:
        raise ValueError("PMP device-state request/status ordering changed")

    _init_address, init_code = functions[PMP_INIT_V2]
    # this+0x72848; memset(..., 0xff, 0x404).  The 0x404-byte allocation is
    # 257 signed u32 entries.  Lookups admit only selectors below 256; the
    # purpose of the extra initialized word is deliberately not inferred.
    if not _has_words_in_order(
        init_code,
        (
            0x9141CA68,  # add x8, x19, #0x72000
            0x91212117,  # add x23, x8, #0x848
            0xAA1703E0,  # mov x0, x23
            0x52801FE1,  # mov w1, #0xff
            0x52808082,  # mov w2, #0x404
        ),
    ):
        raise ValueError("initPMPv2 no longer initializes the device-index table")
    if not _has_words_in_order(
        init_code,
        (
            0x9141CA68,  # add x8, x19, #0x72000
            0x91313118,  # add x24, x8, #0xc4c
            0xAA1803E0,  # mov x0, x24
            0x52801FE1,  # mov w1, #0xff
            0x52808082,  # mov w2, #0x404
        ),
    ):
        raise ValueError("initPMPv2 no longer initializes the virtual-state table")
    if not _has_words_in_order(
        init_code,
        (
            0xB94002CB,  # ldr w11, [x22] -- soc-device ID
            0xD37EF56B,  # lsl x11, x11, #2
        ),
    ) or not _has_ordered_words(
        init_code,
        (
            0xB9000188,  # str w8, [x12] -- table[ID] = record index
            0x91000508,  # add x8, x8, #1
            0x9101F2D6,  # add x22, x22, #0x7c
        ),
    ):
        raise ValueError("initPMPv2 no longer maps SoC-device IDs to record indices")
    if not _has_ordered_words(
        init_code,
        (
            0xB9402ECB,  # ldr w11, [x22, #0x2c]
            0xB94002CB,  # ldr w11, [x22] -- soc-device ID
            0xB9000189,  # str w9, [x12] -- dense virtual-state index
            0x11000529,  # add w9, w9, #1
        ),
    ):
        raise ValueError("initPMPv2 no longer constructs the virtual-state table")

    _lookup_address, lookup_code = functions[PMP_GET_DEVICE_INDEX]
    if not _has_words_in_order(
        lookup_code,
        (
            0x39400C08,  # ldrb w8, [x0, #3]
            0x9141CA69,  # add x9, x19, #0x72000
            0x9120E129,  # add x9, x9, #0x838
            0xB9400129,  # ldr w9, [x9]
            0x1B142128,  # madd w8, w9, w20, w8
            0x7104011F,  # cmp w8, #0x100
        ),
    ) or not _has_words_in_order(
        lookup_code,
        (
            0x9141CA69,  # add x9, x19, #0x72000
            0x91212129,  # add x9, x9, #0x848
        ),
    ):
        raise ValueError("getPMPDeviceIndex no longer uses selector + die*stride")

    virtual_address, virtual_code = functions[PMP_SET_VIRTUAL_DEVICE_STATE]
    virtual_targets = direct_branch_targets(virtual_address, virtual_code)
    if not _has_cmp_w_immediate(virtual_code, source=3, immediate=2):
        raise ValueError("PMP virtual-device dashboard no longer bounds state to 0/1")
    if not _has_ldrb(virtual_code, destination=8, base=0, immediate=3):
        raise ValueError("PMP virtual-device selector is no longer DeviceData byte 3")
    if not _has_ordered_words(
        virtual_code,
        (
            0x9131314A,  # add x10, x10, #0xc4c -- virtual-state table
            0xB9400179,  # ldr w25, [x11] -- dense PTD entry index
        ),
    ):
        raise ValueError("PMP virtual-device dashboard no longer uses its dense map")
    if symbols[APPLE_PTD_WRITE] not in virtual_targets:
        raise ValueError("PMP virtual-device dashboard no longer writes ApplePTD")

    initial_address, initial_code = functions[PMP_NOTIFY_INITIAL]
    initial_targets = direct_branch_targets(initial_address, initial_code)
    for target in (PMP_DEVICE_ID_TO_DATA, PMP_WAIT_CLUSTER_POWER_UP, PMP_SEND_COMMAND):
        if symbols[target] not in initial_targets:
            raise ValueError(f"initial PMP state sync no longer calls {target}")
    if not _has_ordered_words(
        initial_code,
        (
            0x394002A8,  # ldrb w8, [x21] -- DeviceData flags
            0x360801A8,  # tbz w8, #1 -- skip records that do not notify PMP
            0x794036A8,  # ldrh w8, [x21, #0x1a] -- public handle
            0x35000048,  # cbnz w8 -- prefer a nonzero public handle
            0x39400EA8,  # ldrb w8, [x21, #3] -- selector fallback
            0xA900E7E8,  # stp x8, x25, [sp, #8] -- target and state 1
        ),
    ):
        raise ValueError("initial PMP state-notification filter changed")

    cluster_address, cluster_code = functions[PMP_WAIT_CLUSTER_POWER_UP]
    cluster_targets = direct_branch_targets(cluster_address, cluster_code)
    if (
        symbols[APPLE_PTD_READ] in cluster_targets
        or symbols[PMP_WAIT_READY] in cluster_targets
        or not _has_ordered_words(
            cluster_code,
            (
                0x79403437,  # ldrh w23, [x1, #0x1a] -- public handle
                0x35000057,  # cbnz w23 -- otherwise selector byte
                0x39400C37,  # ldrb w23, [x1, #3]
                0x394026CD,  # ldrb w13, [x22, #9] -- cluster transition byte
                0x370000ED,  # tbnz w13, #0 -- sleep while transitioning
                0xD2804011,  # mov x17, #0x200 -- command-gate sleep slot
                0x910026C1,  # add x1, x22, #9 -- sleep event
                0x52800002,  # mov w2, #0
                0x384092C8,  # ldurb w8, [x22, #9]
                0x3707FE68,  # tbnz w8, #0 -- retry until cluster is stable
            ),
        )
    ):
        raise ValueError("initial PMP cluster-power wait changed")

    enable_address, enable_code = functions[PMP_ENABLE_DEVICE_GATED]
    enable_targets = direct_branch_targets(enable_address, enable_code)
    for target in (PMP_DEVICE_ID_TO_DATA, PMP_CHECK_NOTIFY, PMP_SEND_COMMAND):
        if symbols[target] not in enable_targets:
            raise ValueError(f"dynamic PMP state sync no longer calls {target}")
    notify_test = struct.pack("<I", 0x360801C8)  # tbz w8, #1
    wait_slot = struct.pack("<I", 0xD2815811)  # mov x17, #0xac0
    if (
        enable_code.count(notify_test) != 2
        or enable_code.count(wait_slot) != 1
        or enable_code.find(wait_slot) > enable_code.find(notify_test)
        or not _has_ordered_words(
            enable_code,
            (
                0x794002A1,  # ldrh w1, [x21] -- changed device ID
                0x39400008,  # ldrb w8, [x0] -- DeviceData flags
                0x360801C8,  # tbz w8, #1 -- skip non-notifying records
            ),
        )
    ):
        raise ValueError("dynamic PMP state-notification filter changed")

    _wait_address, wait_code = functions[PMP_WAIT_READY]
    if not _has_ordered_words(
        wait_code,
        (
            0xD2815611,  # mov x17, #0xab0 -- pmpV1 predicate slot
            0xD2803D11,  # mov x17, #0x1e8 -- command-gate action
            0xD2815711,  # mov x17, #0xab8 -- pmpV2 predicate slot
            0xD2803D11,  # mov x17, #0x1e8 -- command-gate action
        ),
    ):
        raise ValueError("PMP readiness version/command-gate dispatch changed")

    wait_v2_address, wait_v2_code = functions[PMP_WAIT_READY_V2]
    wait_v2_targets = direct_branch_targets(wait_v2_address, wait_v2_code)
    if symbols[APPLE_PTD_READ] not in wait_v2_targets or not _has_ordered_words(
        wait_v2_code,
        (
            0xB95BF000,  # ldr w0, [x0, #0x1bf0] -- timeout seconds
            0x9141CA88,  # add x8, x20, #0x72000
            0x9120F108,  # add x8, x8, #0x83c -- per-die ready bytes
            0x394002A8,  # ldrb w8, [x21] -- already ready
            0x9141CE88,  # add x8, x20, #0x73000
            0x9121C117,  # add x23, x8, #0x870 -- ApplePTD pointer
            0x9141CA88,  # add x8, x20, #0x72000
            0x91208118,  # add x24, x8, #0x820 -- PMP-STATUS range pointer
            0xF94DC280,  # ldr x0, [x20, #0x1b80] -- command gate
            0x91084208,  # add x8, x16, #0x210 -- deadline sleep slot
            0xF94002E0,  # ldr x0, [x23] -- ApplePTD
            0xF9400301,  # ldr x1, [x24] -- PMP-STATUS range
            0xB9400422,  # ldr w2, [x1, #4] -- PTD entry offset
            0xF94023E8,  # ldr x8, [sp, #0x40] -- returned PTD value
            0xB5000188,  # cbnz x8 -- a nonzero status is ready
            0x52800028,  # mov w8, #1
            0x390002A8,  # strb w8, [x21] -- latch per-die ready
        ),
    ):
        raise ValueError("PMPv2 PTD readiness wait changed")

    _ready_address, ready_code = functions[PMP_READY_GATED]
    if not _has_ordered_words(
        ready_code,
        (
            0xD2815611,  # mov x17, #0xab0 -- pmpV1 predicate slot
            0xD2815711,  # mov x17, #0xab8 -- pmpV2 predicate slot
            0x9141CA68,  # add x8, x19, #0x72000
            0x9120F108,  # add x8, x8, #0x83c -- per-die ready bytes
            0x52800028,  # mov w8, #1
            0x39000028,  # strb w8, [x1] -- latch ready
            0xF94DC260,  # ldr x0, [x19, #0x1b80] -- command gate
            0xD2804111,  # mov x17, #0x208 -- wakeup slot
            0x52800002,  # mov w2, #0 -- wake one/all mode
        ),
    ):
        raise ValueError("PMP readiness callback changed")
    readiness_handshake = recover_pmp_readiness_handshake(functions, symbols)

    return {
        "device_state_commands": [14, 15],
        "device_states": [0, 1],
        "device_index_field": 3,
        "device_dispatch": {
            "virtual_flag": 0x10,
            "virtual_class_field": 15,
            "virtual_class_minimum": 0,
        },
        "ordinary_request_ack": {
            "request_range_object_offset": 0x72800,
            "ack_range_object_offset": 0x72808,
            "status_range_object_offset": 0x72820,
            "diagnostic_range_object_offset": 0x72828,
            "device_mask": "1 << soc-device record index",
            "device_index_lookup": (
                "table[DeviceData selector + selector-die-stride * requested die]"
            ),
            "selector_die_stride_object_offset": 0x72838,
            "multi_pmp_flag": {"object_offset": 0x1BDC, "bit": 0},
            "ptd_die": "requested die when multi-PMP bit 0 is set; otherwise die 0",
            "request": "read-modify-write; clear for state 0, set for state 1",
            "ack_required_flag": 0x02,
            "skip_state_1_ack_flag": 0x04,
            "ack_new_data": {"metadata_word": 1, "bit": 54},
            "success": "newData is set and the selected ack bit equals the request",
            "timeout_seconds": 15,
            "computed_poll_deadline_ms": 100,
            "poll_deadline_observed_use": (
                "recomputed in the loop but never read by this function"
            ),
            "request_after_success": "preserved; there is no second PTD write",
            "pre_ready_behavior": (
                "publish the persistent request, sample PMP-STATUS, and return success "
                "without reading PS-ACK when status is zero"
            ),
            "ready_behavior": (
                "latch the per-die ready byte and poll PS-ACK when PMP-STATUS is nonzero"
            ),
            "timeout": "dump the PMPTOOL PTD range and panic",
        },
        "state_notification": {
            "flag": 0x02,
            "flags_field": 0,
            "initial_sync": PMP_NOTIFY_INITIAL,
            "dynamic_sync": PMP_ENABLE_DEVICE_GATED,
            "target": "public handle at +0x1a, selector byte at +3 if zero",
            "initial_precondition": (
                "wait for dependent cluster transition bytes to become stable"
            ),
            "initial_precondition_scope": (
                "cluster power only; it does not read ApplePTD or call the PMP-ready wait"
            ),
        },
        "readiness": {
            "scope": "per die",
            "virtual_wait_slot": 0xAC0,
            "command_gate_object_offset": 0x1B80,
            "command_gate_action_slot": 0x1E8,
            "command_gate_sleep_deadline_slot": 0x210,
            "command_gate_wakeup_slot": 0x208,
            "timeout_seconds_object_offset": 0x1BF0,
            "ready_bytes_object_offset": 0x7283C,
            "ptd_driver_object_offset": 0x73870,
            "status_range_object_offset": 0x72820,
            "ready_value": "nonzero 64-bit PMP-STATUS entry",
            "dynamic_transition_order": (
                "checkNotifyPMP, wait until ready, mutate device state, "
                "then emit command 14/15"
            ),
            "initial_sync": (
                "scheduled separately; it may publish level requests before ready, and "
                "the ordinary transaction then bypasses PS-ACK while status is zero"
            ),
        },
        "readiness_handshake": readiness_handshake,
        "device_index_map": {
            "source": "soc-device",
            "key_offset": 0,
            "value": "record index",
            "record_stride": PMP_SOC_DEVICE_BYTES,
            "initial_value": -1,
            "allocated_entries": 257,
            "lookup_entries": 256,
            "selector_field": 3,
            "die_stride_object_offset": 0x72838,
            "table_object_offset": 0x72848,
        },
        "virtual_state_map": {
            "source": "nonzero soc-device word at +0x2c",
            "key": "soc-device id",
            "value": "dense PTD entry index",
            "initial_value": -1,
            "allocated_entries": 257,
            "table_object_offset": 0x72C4C,
        },
        "ptd_transport": ptd_transport,
        "transport": "PTD dashboard request/ack bitsets",
    }


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
            APPLE_PTD_READ,
            APPLE_PTD_WRITE,
            PMGR_WRITE_REG64,
        )
    }
    return {
        "uuid": identity,
        "pmp_v2": recover_pmp_code_contract(functions, symbols),
    }


def _decode_movz_w(word: int, register: int) -> int | None:
    if word & 0xFFE0001F != 0x52800000 | register:
        return None
    return (word >> 5) & 0xFFFF


def recover_t6050_pmgr_code_contract(
    functions: dict[str, tuple[int, bytes]],
    symbols: dict[str, int],
    apple_pmgr_symbols: dict[str, int],
    vtable_targets: dict[int, int],
) -> dict[str, object]:
    """Recover the T6050-specific PMGR version and RegMap dispatch."""

    required = (
        T6050_INIT_REG_MAPS,
        PMGR_PMP_V1,
        PMGR_PMP_V2,
        PMGR_GET_NUM_DIES,
        PMGR_GET_DIE_COUNT,
    )
    missing = [name for name in required if name not in symbols]
    if missing:
        raise ValueError(f"AppleT6050PMGR is missing symbols: {missing!r}")
    for name in (
        T6050_INIT_REG_MAPS,
        PMGR_PMP_V1,
        PMGR_PMP_V2,
        T6050_RESTORE_HW,
        T6050_UPDATE_HIB_DEVICE_STATUS,
    ):
        if name not in functions:
            raise ValueError(f"AppleT6050PMGR has no code body for {name}")
    base_required = (
        PMGR_INIT_REG_MAP,
        PMP_WAIT_READY,
        PMP_NOTIFY_INITIAL_ENTRY,
        PMGR_PM_HIBERNATION_STATE,
        PMGR_CURRENT_DRIVER_STATE,
        PMGR_UPDATE_HIB_DEVICE_STATUS,
    )
    base_missing = [name for name in base_required if name not in apple_pmgr_symbols]
    if base_missing:
        raise ValueError(f"ApplePMGR is missing T6050 base symbols: {base_missing!r}")

    expected_slots = {
        0xAB0: symbols[PMGR_PMP_V1],
        0xAB8: symbols[PMGR_PMP_V2],
        0xAC0: apple_pmgr_symbols[PMP_WAIT_READY],
        0xAC8: symbols[PMGR_GET_NUM_DIES],
        0xB30: symbols[PMGR_GET_DIE_COUNT],
    }
    for slot, expected in expected_slots.items():
        actual = vtable_targets.get(slot)
        if actual != expected:
            raise ValueError(
                f"AppleT6050PMGR vtable slot {slot:#x} changed: "
                f"{actual!r} != {expected:#x}"
            )

    _v1_address, v1_code = functions[PMGR_PMP_V1]
    _v2_address, v2_code = functions[PMGR_PMP_V2]
    if v1_code != struct.pack(
        "<5I", 0xD503245F, 0xB95BD808, 0x7100051F, 0x1A9F17E0, 0xD65F03C0
    ):
        raise ValueError("AppleT6050PMGR PMP-v1 predicate changed")
    if v2_code != struct.pack(
        "<5I", 0xD503245F, 0xB95BD808, 0x7100091F, 0x1A9F17E0, 0xD65F03C0
    ):
        raise ValueError("AppleT6050PMGR PMP-v2 predicate changed")

    init_address, init_code = functions[T6050_INIT_REG_MAPS]
    words = [
        struct.unpack_from("<I", init_code, offset)[0]
        for offset in range(0, len(init_code) - 3, 4)
    ]
    reg_map_calls: list[tuple[int, int]] = []
    for index, word in enumerate(words):
        if index < 5 or word & 0x7C000000 != 0x14000000:
            continue
        immediate = word & 0x03FFFFFF
        if immediate & 0x02000000:
            immediate -= 1 << 26
        target = (init_address + index * 4 + immediate * 4) & 0xFFFFFFFFFFFFFFFF
        if target != apple_pmgr_symbols[PMGR_INIT_REG_MAP]:
            continue
        prefix = words[index - 5 : index]
        reg_map = _decode_movz_w(prefix[1], 1)
        reg_index = _decode_movz_w(prefix[2], 2)
        if (
            prefix[0] != 0xAA1303E0  # mov x0, x19 -- this
            or reg_map is None
            or reg_index is None
            or prefix[3] != 0xAA1403E3  # mov x3, x20 -- die
            or prefix[4] != 0x52800004  # mov w4, #0
        ):
            raise ValueError("AppleT6050PMGR initRegMap call ABI changed")
        reg_map_calls.append((reg_map, reg_index))

    if len(reg_map_calls) != 60:
        raise ValueError(
            f"AppleT6050PMGR RegMap call count changed: {len(reg_map_calls)}"
        )
    if [reg_index for _reg_map, reg_index in reg_map_calls] != list(range(60)):
        raise ValueError("AppleT6050PMGR DeviceTree reg-index order changed")
    ptd_calls = [item for item in reg_map_calls if item[0] == 8]
    if ptd_calls != [(8, 7)]:
        raise ValueError(f"AppleT6050PMGR PTD RegMap dispatch changed: {ptd_calls!r}")
    restore_address, restore_code = functions[T6050_RESTORE_HW]
    restore_targets = direct_branch_targets(restore_address, restore_code)
    for name in (
        PMGR_PM_HIBERNATION_STATE,
        PMGR_CURRENT_DRIVER_STATE,
        PMGR_UPDATE_HIB_DEVICE_STATUS,
    ):
        if apple_pmgr_symbols[name] not in restore_targets:
            raise ValueError(f"AppleT6050PMGR restoreHW no longer calls {name}")
    republications = direct_branch_count(
        restore_address, restore_code, apple_pmgr_symbols[PMP_NOTIFY_INITIAL_ENTRY]
    )
    if republications != 2 or not _has_ordered_words(
        restore_code,
        (
            0x7100081F,  # cmp w0, #2 -- hibernation resume
            0x7100081F,  # cmp w0, #2 -- restored driver state
        ),
    ):
        raise ValueError(
            "AppleT6050PMGR restoreHW initial-status republication changed: "
            f"{republications}"
        )

    hib_address, hib_code = functions[T6050_UPDATE_HIB_DEVICE_STATUS]
    hib_targets = direct_branch_targets(hib_address, hib_code)
    if (
        apple_pmgr_symbols[PMGR_UPDATE_HIB_DEVICE_STATUS] not in hib_targets
        or apple_pmgr_symbols[PMP_NOTIFY_INITIAL_ENTRY] not in hib_targets
    ):
        raise ValueError(
            "AppleT6050PMGR hibernation status update no longer republishes"
        )

    if not _has_ordered_words(
        init_code,
        (
            0xD2816611,  # mov x17, #0xb30 -- getDieCount vtable slot
            0x52800014,  # mov w20, #0 -- first die
            0xAA1403E3,  # every initRegMap call receives die in x3
            0x11000694,  # add w20, w20, #1
            0x912CC208,  # add x8, x16, #0xb30 -- getDieCount again
            0xF9459A09,  # ldr x9, [x16, #0xb30]
            0x54FFD103,  # b.lo -- repeat the complete map table per die
        ),
    ):
        raise ValueError("AppleT6050PMGR per-die RegMap loop changed")

    return {
        "pmp_version": {
            "object_offset": 0x1BD8,
            "v1_value": 1,
            "v2_value": 2,
        },
        "vtable_slots": {
            "pmp_v1": 0xAB0,
            "pmp_v2": 0xAB8,
            "wait_for_ready": 0xAC0,
            "get_num_dies": 0xAC8,
            "get_die_count": 0xB30,
        },
        "initial_publication": {
            "republication_sites": [
                T6050_RESTORE_HW,
                T6050_UPDATE_HIB_DEVICE_STATUS,
            ],
            "restore_hw_calls": republications,
            "restore_hw_guards": [
                PMGR_PM_HIBERNATION_STATE,
                PMGR_CURRENT_DRIVER_STATE,
            ],
            "guard_value": 2,
            "entry": PMP_NOTIFY_INITIAL_ENTRY,
            "scope": (
                "resume republishes the same pre-ready device status that "
                "ApplePMGR::start published; it is never conditioned on PMP "
                "readiness"
            ),
        },
        "reg_maps": {
            "initialization_calls_per_die": len(reg_map_calls),
            "device_tree_indices": [item[1] for item in reg_map_calls],
            "ptd": {"enum": 8, "device_tree_reg_index": 7},
            "scope": "the complete 60-call table is repeated for every die",
        },
    }


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
    """Recover the RTBuddy mailbox and ping-completion contract.

    ApplePMPv2's PM subtype-1 message is sometimes tempting to label a global
    PMP-ready notification.  The producer/consumer code proves a narrower
    meaning: it completes a class-2 ping, clears the ping's in-flight byte,
    and wakes the thread sleeping on that byte.  Keep that distinction in the
    generated report so it cannot accidentally open the AGX power gate.
    """

    required = (
        APPLE_PMP_V2_START,
        APPLE_PMP_V2_MESSAGE_HANDLER,
        APPLE_PMP_V2_HANDLE_MEMORY,
        APPLE_PMP_V2_HANDLE_POWER,
        APPLE_PMP_V2_HANDLE_REGISTRY,
        APPLE_PMP_V2_SEND_MESSAGE,
        APPLE_PMP_V2_WRITE_DASHBOARD,
        APPLE_PMP_V2_GET_PROPERTY_DATA,
        APPLE_PMP_V2_PING_GATED,
    )
    missing = [name for name in required if name not in symbols]
    if missing:
        raise ValueError(f"ApplePMP is missing PMPv2 symbols: {missing!r}")
    missing_rtbuddy = [
        name
        for name in (
            RTBUDDY_ENDPOINT_GET_SLAVE,
            RTBUDDY_ENDPOINT_INIT_OWNER,
            RTBUDDY_ENDPOINT_SET_POWER_ACTION,
        )
        if name not in rtbuddy_symbols
    ]
    if missing_rtbuddy:
        raise ValueError(f"RTBuddy is missing ApplePMP attach symbols: {missing_rtbuddy!r}")
    for name in (
        APPLE_PMP_V2_START,
        APPLE_PMP_V2_MESSAGE_HANDLER,
        APPLE_PMP_V2_HANDLE_POWER,
        APPLE_PMP_V2_SEND_MESSAGE,
        APPLE_PMP_V2_WRITE_DASHBOARD,
        APPLE_PMP_V2_PING_GATED,
    ):
        if name not in functions:
            raise ValueError(f"ApplePMP has no code body for {name}")

    start_address, start_code = functions[APPLE_PMP_V2_START]
    start_targets = direct_branch_targets(start_address, start_code)
    for target in (
        RTBUDDY_ENDPOINT_GET_SLAVE,
        RTBUDDY_ENDPOINT_INIT_OWNER,
        RTBUDDY_ENDPOINT_SET_POWER_ACTION,
    ):
        if rtbuddy_symbols[target] not in start_targets:
            raise ValueError(f"ApplePMPv2 start no longer calls {target}")

    def one_start_call_offset(target: str) -> int:
        offsets = [
            offset
            for offset in range(0, len(start_code) - 3, 4)
            if direct_branch_target_at(start_address, start_code, offset)
            == rtbuddy_symbols[target]
        ]
        if len(offsets) != 1:
            raise ValueError(f"ApplePMPv2 start call count changed for {target}")
        return offsets[0]

    get_slave_offset = one_start_call_offset(RTBUDDY_ENDPOINT_GET_SLAVE)
    init_owner_offset = one_start_call_offset(RTBUDDY_ENDPOINT_INIT_OWNER)
    set_power_offset = one_start_call_offset(RTBUDDY_ENDPOINT_SET_POWER_ACTION)
    if not get_slave_offset < init_owner_offset < set_power_offset:
        raise ValueError("ApplePMPv2 RTBuddy attach ordering changed")
    if not _has_ordered_words(
        start_code,
        (
            0xF9404400,  # ldr x0, [x0, #0x88] -- endpoint from endpoint service
            0xF9004660,  # str x0, [x19, #0x88] -- retained endpoint
            0xB9408808,  # ldr w8, [x0, #0x88] -- endpoint identifier
            0xB9009268,  # str w8, [x19, #0x90]
            0xF9004E60,  # str x0, [x19, #0x98] -- slave processor
            0xF9005A60,  # str x0, [x19, #0xb0] -- AppleA7IOPNub
            0xF9404800,  # ldr x0, [x0, #0x90] -- wrapper service
            0xF9005E60,  # str x0, [x19, #0xb8]
            0xB9400001,  # ldr w1, [x0] -- ptd-update-reg-index value
            0xF9405E60,  # ldr x0, [x19, #0xb8] -- wrapper service
            0x52800002,  # mov w2, #0 -- getDeviceMemoryWithIndex options
            0xF9006260,  # str x0, [x19, #0xc0] -- PTD update memory
            0xF9405E60,  # ldr x0, [x19, #0xb8] -- wrapper service
            0x52800021,  # mov w1, #1 -- mapper index
            0xF9006675,  # str x21, [x19, #0xc8] -- retained mapper
        ),
    ):
        raise ValueError("ApplePMPv2 wrapper resource attachment changed")
    # The RTBuddy service lives at this+0x88.  start() installs the static
    # message callback with (service, this, callback, 0).
    if not _has_words_in_order(
        start_code,
        (
            0xF9404660,  # ldr x0, [x19, #0x88]
            0xB0FFFFB0,  # adrp x16, page(messageHandler)
            0x91270210,  # add x16, x16, #0x9c0
            0xD2830211,  # mov x17, #0x1810
            0xDAC10230,  # pacia x16, x17
            0xAA1003E2,  # mov x2, x16
            0xAA1303E1,  # mov x1, x19
            0xD2800003,  # mov x3, #0
        ),
    ):
        raise ValueError("ApplePMPv2 no longer installs its RTBuddy message handler")

    handler_address, handler_code = functions[APPLE_PMP_V2_MESSAGE_HANDLER]
    handler_targets = direct_branch_targets(handler_address, handler_code)
    for target in (
        APPLE_PMP_V2_HANDLE_MEMORY,
        APPLE_PMP_V2_HANDLE_POWER,
        APPLE_PMP_V2_HANDLE_REGISTRY,
    ):
        if symbols[target] not in handler_targets:
            raise ValueError(
                f"ApplePMPv2 message handler no longer dispatches to {target}"
            )
    if not _has_ordered_words(
        handler_code,
        (
            0xD374DC28,  # ubfx x8, x1, #52, #4 -- message class
            0x51000D09,  # sub w9, w8, #3
            0x7100093F,  # cmp w9, #2 -- registry classes 3/4
            0x7100091F,  # cmp w8, #2 -- power class
            0x7100051F,  # cmp w8, #1 -- memory class
        ),
    ):
        raise ValueError("ApplePMPv2 message-class decoder changed")

    _power_address, power_code = functions[APPLE_PMP_V2_HANDLE_POWER]
    if not _has_words_in_order(
        power_code,
        (
            0x92500C28,  # and x8, x1, #0xf000000000000 -- PM subtype
            0xD2E00029,  # mov x9, #0x1000000000000 -- subtype 1
            0xEB09011F,  # cmp x8, x9
        ),
    ) or not _has_ordered_words(
        power_code,
        (
            0x3904201F,  # strb wzr, [x0, #0x108] -- ping no longer busy
            0x91042001,  # add x1, x0, #0x108 -- wakeup event
        ),
    ):
        raise ValueError("ApplePMPv2 ping-completion message changed")

    _send_address, send_code = functions[APPLE_PMP_V2_SEND_MESSAGE]
    if not _has_ordered_words(
        send_code,
        (
            0xF90007E1,  # str x1, [sp, #8] -- one 64-bit mailbox word
            0xF9404400,  # ldr x0, [x0, #0x88] -- RTBuddy service
            0xD2803D11,  # mov x17, #0x1e8 -- send vtable slot
            0x910023E1,  # add x1, sp, #8
            0xD2800002,  # mov x2, #0
            0x52800023,  # mov w3, #1 -- one word
        ),
    ):
        raise ValueError("ApplePMPv2 RTBuddy send-message ABI changed")

    _ping_address, ping_code = functions[APPLE_PMP_V2_PING_GATED]
    if not _has_ordered_words(
        ping_code,
        (
            0x39442008,  # ldrb w8, [x0, #0x108] -- reject overlapping ping
            0xD2E00417,  # mov x23, #0x20000000000000 -- class 2
            0xB3407C17,  # bfxil x23, x0, #0, #32 -- timestamp payload
            0x390422B7,  # strb w23, [x21, #0x108] -- mark in flight
            0x910422A1,  # add x1, x21, #0x108 -- sleep event
        ),
    ):
        raise ValueError("ApplePMPv2 ping request/wait protocol changed")

    dashboard_address, dashboard_code = functions[APPLE_PMP_V2_WRITE_DASHBOARD]
    dashboard_targets = direct_branch_targets(dashboard_address, dashboard_code)
    if (
        symbols[APPLE_PMP_V2_GET_PROPERTY_DATA] not in dashboard_targets
        or not _has_ordered_words(
            dashboard_code,
            (
                0xF9406000,  # ldr x0, [x0, #0xc0] -- PTD/dashboard object
                0xAA0203F4,  # mov x20, x2 -- 64-bit value
                0xAA0103F5,  # mov x21, x1 -- dashboard index
                0xD0FF05A1,  # adrp x1, page("pmptool-config")
                0x910C0021,  # add x1, x1, #0x300
                0xF9000134,  # str x20, [x9] -- indexed 64-bit write
            ),
        )
    ):
        raise ValueError("ApplePMPv2 diagnostic dashboard write contract changed")

    return {
        "attachment": {
            "provider": "RTBuddyEndpointService",
            "provider_endpoint_offset": 0x88,
            "endpoint_identifier_offset": 0x88,
            "slave_processor_object_offset": 0x98,
            "wrapper_service_object_offset": 0xB8,
            "ptd_update_property": "ptd-update-reg-index",
            "ptd_update_memory_object_offset": 0xC0,
            "mapper_index": 1,
            "mapper_object_offset": 0xC8,
            "ordering": [
                "resolve endpoint and slave processor",
                "resolve wrapper PTD-update memory and mapper",
                "install message callback",
                "install power-state callback",
            ],
            "scope": "host attachment only; does not start or prove PMP firmware ready",
        },
        "mailbox": {
            "word_bits": 64,
            "message_class": {"shift": 52, "bits": 4},
            "classes": {
                "memory": [1],
                "power": [2],
                "registry": [3, 4],
            },
            "rtbuddy_object_offset": 0x88,
            "send_vtable_slot": 0x1E8,
            "send_word_count": 1,
        },
        "ping": {
            "request_class": 2,
            "request_payload": "low 32 bits of host timestamp",
            "completion_power_subtype": 1,
            "power_subtype": {"shift": 48, "bits": 4},
            "in_flight_byte_offset": 0x108,
            "completion": "clear in-flight byte and wake its sleepers",
            "scope": "ping completion, not proof of AGX dashboard readiness",
        },
        "diagnostic_dashboard": {
            "object_offset": 0xC0,
            "configuration_property": "pmptool-config",
            "index_unit_bits": 64,
            "write_bits": 64,
            "scope": "diagnostic API, not the ApplePMGR AGX state request",
        },
    }


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
    """Recover PMP's mandatory patchbay inputs and RTBuddy fixup order.

    This deliberately stops at RTBuddy's firmware-loaded bookkeeping.  That
    byte and the subsequent IORegistry announcement are not a PMP run-state or
    dashboard-ready acknowledgement and must not open the hardware write gate.
    """

    required_pmp = (
        APPLE_PMP_FIRMWARE_START,
        APPLE_PMP_FIRMWARE_PATCH,
        RTBUDDY_FIRMWARE_PATCH_U32,
    )
    missing_pmp = [name for name in required_pmp if name not in pmp_symbols]
    if missing_pmp:
        raise ValueError(
            f"ApplePMPFirmware is missing firmware symbols: {missing_pmp!r}"
        )
    for name in (APPLE_PMP_FIRMWARE_START, APPLE_PMP_FIRMWARE_PATCH):
        if name not in pmp_functions:
            raise ValueError(f"ApplePMPFirmware has no code body for {name}")

    required_rtbuddy = (
        RTBUDDY_FIRMWARE_SERVICE_PRE_LOAD,
        RTBUDDY_FIRMWARE_SERVICE_PATCH,
        RTBUDDY_FIRMWARE_FIXUP,
        RTBUDDY_FIRMWARE_COPY_TO_TARGET,
        RTBUDDY_FIRMWARE_CREATE_COREDUMP_MAP,
        RTBUDDY_FIRMWARE_PUBLISH,
        RTBUDDY_FIRMWARE_WRITE_BACK_PATCHBAY,
        RTBUDDY_FIRMWARE_UPDATE_PATCHBAY,
        RTBUDDY_FIRMWARE_UPDATE_COREDUMP_PATCHBAY,
        RTBUDDY_FIRMWARE_GET_ROLE,
        RTBUDDY_FIRMWARE_ANNOUNCE,
        RTBUDDY_CALL_PATCHBAY_CALLBACK,
        RTBUDDY_POWER_ON,
        RTBUDDY_LOAD_FIRMWARE_GATED,
        RTBUDDY_WAIT_FOR_FIRMWARE_SERVICE_GATED,
    )
    missing_rtbuddy = [
        name for name in required_rtbuddy if name not in rtbuddy_symbols
    ]
    if missing_rtbuddy:
        raise ValueError(
            f"RTBuddy is missing PMP firmware-load symbols: {missing_rtbuddy!r}"
        )
    for name in (RTBUDDY_FIRMWARE_FIXUP, RTBUDDY_LOAD_FIRMWARE_GATED):
        if name not in rtbuddy_functions:
            raise ValueError(f"RTBuddy has no code body for {name}")

    expected_pmp_slots = {
        0x5F0: pmp_symbols[APPLE_PMP_FIRMWARE_START],
        0x898: pmp_symbols[APPLE_PMP_FIRMWARE_PATCH],
    }
    if pmp_vtable_targets != expected_pmp_slots:
        raise ValueError("ApplePMPFirmware vtable overrides changed")
    expected_service_slots = {
        0x890: rtbuddy_symbols[RTBUDDY_FIRMWARE_SERVICE_PRE_LOAD],
        0x898: rtbuddy_symbols[RTBUDDY_FIRMWARE_SERVICE_PATCH],
    }
    if service_vtable_targets != expected_service_slots:
        raise ValueError("RTBuddyFirmwareService fixup slots changed")
    expected_firmware_slots = {
        0x8A8: rtbuddy_symbols[RTBUDDY_FIRMWARE_UPDATE_PATCHBAY],
        0x8B0: rtbuddy_symbols[RTBUDDY_FIRMWARE_UPDATE_COREDUMP_PATCHBAY],
    }
    if firmware_vtable_targets != expected_firmware_slots:
        raise ValueError("RTBuddyFirmware patchbay slots changed")

    _start_address, start_code = pmp_functions[APPLE_PMP_FIRMWARE_START]
    if not _has_ordered_words(
        start_code,
        (
            0xB900CA88,  # board-id -> this+0xc8
            0xB900CE88,  # dram-vendor-id -> this+0xcc
            0xB900D288,  # dram-capacity -> this+0xd0
            0xB900D688,  # dram-channel-disable -> this+0xd4
            0xB900DA88,  # pmc -> this+0xd8
            0x291BA289,  # pmc-pmgr bits 0/3 -> this+0xdc/+0xe0
            0xB900E688,  # pmc-msg-disabled -> this+0xe4
            0xB900EA88,  # soc-chip-variant -> this+0xe8
            0xF9405E82,  # Role property object from this+0xb8
        ),
    ):
        raise ValueError("ApplePMPFirmware mandatory property collection changed")

    patch_address, patch_code = pmp_functions[APPLE_PMP_FIRMWARE_PATCH]
    # These are the nine unconditional u32 writes at the head of
    # ApplePMPFirmware::patchFirmware.  Later boot-argument-driven writes are
    # optional and are intentionally outside this invariant.
    mandatory_words = {
        0x20: 0x52886855,  # mov w21, #0x4342
        0x24: 0x72AA09B5,  # movk w21, #0x504d, lsl #16
        0x28: 0x52882A16,  # mov w22, #0x4150
        0x2C: 0x72A88876,  # movk w22, #0x4443, lsl #16
        0x34: 0x91032002,  # add x2, x0, #0xc8
        0x3C: 0x52892881,  # BDID low half
        0x40: 0x72A84881,  # BDID high half
        0x48: 0x91033282,  # add x2, x20, #0xcc
        0x50: 0x52892881,  # DVID low half
        0x54: 0x72A88AC1,  # DVID high half
        0x5C: 0x91034282,  # add x2, x20, #0xd0
        0x64: 0x52882A01,  # DCAP low half
        0x68: 0x72A88861,  # DCAP high half
        0x70: 0x111BD2C1,  # DCHD = DCAP + 0x6f4
        0x74: 0x91035282,  # add x2, x20, #0xd4
        0x80: 0x528003A8,  # PMC_ suffix
        0x84: 0x2A0802A1,  # PMC_ = PMCB | 0x1d
        0x88: 0x91036282,  # add x2, x20, #0xd8
        0x94: 0x52800288,  # PMCV suffix
        0x98: 0x2A0802A1,  # PMCV = PMCB | 0x14
        0x9C: 0x91037282,  # add x2, x20, #0xdc
        0xA8: 0x91038282,  # add x2, x20, #0xe0
        0xB0: 0x52886841,  # PMCB low half
        0xB4: 0x72AA09A1,  # PMCB high half
        0xBC: 0x11005AA1,  # PMCX = PMCB + 0x16
        0xC0: 0x91039282,  # add x2, x20, #0xe4
        0xCC: 0x9103A282,  # add x2, x20, #0xe8
        0xD4: 0x52882A41,  # CVAR low half
        0xD8: 0x72A86AC1,  # CVAR high half
    }
    if len(patch_code) < 0xE0 or any(
        struct.unpack_from("<I", patch_code, offset)[0] != expected
        for offset, expected in mandatory_words.items()
    ):
        raise ValueError("ApplePMPFirmware mandatory patchbay writes changed")
    mandatory_call_offsets = (
        0x44,
        0x58,
        0x6C,
        0x7C,
        0x90,
        0xA4,
        0xB8,
        0xC8,
        0xDC,
    )
    if any(
        direct_branch_target_at(patch_address, patch_code, offset)
        != pmp_symbols[RTBUDDY_FIRMWARE_PATCH_U32]
        for offset in mandatory_call_offsets
    ):
        raise ValueError("ApplePMPFirmware mandatory patchbay call targets changed")

    fixup_address, fixup_code = rtbuddy_functions[RTBUDDY_FIRMWARE_FIXUP]
    fixup_direct_order = (
        RTBUDDY_POWER_ON,
        RTBUDDY_FIRMWARE_COPY_TO_TARGET,
        RTBUDDY_FIRMWARE_CREATE_COREDUMP_MAP,
        RTBUDDY_CALL_PATCHBAY_CALLBACK,
        RTBUDDY_FIRMWARE_PUBLISH,
        RTBUDDY_FIRMWARE_WRITE_BACK_PATCHBAY,
    )
    fixup_offsets: list[int] = []
    for name in fixup_direct_order:
        offsets = [
            offset
            for offset in range(0, len(fixup_code) - 3, 4)
            if direct_branch_target_at(fixup_address, fixup_code, offset)
            == rtbuddy_symbols[name]
        ]
        if len(offsets) != 1:
            raise ValueError(f"RTBuddy firmware fixup call count changed for {name}")
        fixup_offsets.append(offsets[0])
    virtual_slot_words = (
        0xD2811211,  # service slot 0x890: preFirmwareLoad
        0xD2811311,  # service slot 0x898: patchFirmware
        0xD2811511,  # firmware slot 0x8a8: updatePatchBay
        0xD2811611,  # firmware slot 0x8b0: updateCoredumpWithPatchBay
    )
    virtual_offsets: list[int] = []
    for word in virtual_slot_words:
        needle = struct.pack("<I", word)
        offsets = [
            offset
            for offset in range(0, len(fixup_code) - 3, 4)
            if fixup_code[offset : offset + 4] == needle
        ]
        if len(offsets) != 1:
            raise ValueError("RTBuddy firmware virtual fixup slots changed")
        virtual_offsets.append(offsets[0])
    complete_fixup_offsets = (
        fixup_offsets[0],
        virtual_offsets[0],
        fixup_offsets[1],
        fixup_offsets[2],
        virtual_offsets[1],
        fixup_offsets[3],
        virtual_offsets[2],
        virtual_offsets[3],
        fixup_offsets[4],
        fixup_offsets[5],
    )
    if list(complete_fixup_offsets) != sorted(complete_fixup_offsets):
        raise ValueError("RTBuddy firmware fixup ordering changed")

    load_address, load_code = rtbuddy_functions[RTBUDDY_LOAD_FIRMWARE_GATED]
    load_direct_order = (
        RTBUDDY_FIRMWARE_GET_ROLE,
        RTBUDDY_WAIT_FOR_FIRMWARE_SERVICE_GATED,
        RTBUDDY_FIRMWARE_FIXUP,
        RTBUDDY_FIRMWARE_ANNOUNCE,
    )
    load_offsets: list[int] = []
    for name in load_direct_order:
        offsets = [
            offset
            for offset in range(0, len(load_code) - 3, 4)
            if direct_branch_target_at(load_address, load_code, offset)
            == rtbuddy_symbols[name]
        ]
        if len(offsets) != 1:
            raise ValueError(f"RTBuddy gated load call count changed for {name}")
        load_offsets.append(offsets[0])
    load_words = (
        0xF910F674,  # selected firmware -> RTBuddy+0x21e8
        0xF950BA62,  # firmware service from RTBuddy+0x2170
        0x52800028,  # mov w8, #1 after fixup
        0x39042E68,  # firmware-loaded byte at RTBuddy+0x10b
        0xF950F660,  # reload selected firmware before announce
    )
    load_word_offsets = [
        load_code.find(struct.pack("<I", word)) for word in load_words
    ]
    complete_load_offsets = (
        load_offsets[0],
        load_offsets[1],
        load_word_offsets[0],
        load_word_offsets[1],
        load_offsets[2],
        load_word_offsets[2],
        load_word_offsets[3],
        load_word_offsets[4],
        load_offsets[3],
    )
    if -1 in load_word_offsets or list(complete_load_offsets) != sorted(
        complete_load_offsets
    ):
        raise ValueError("RTBuddy gated firmware-load completion changed")

    mandatory_patches = (
        ("BDID", "board-id", 0xC8),
        ("DVID", "dram-vendor-id", 0xCC),
        ("DCAP", "dram-capacity", 0xD0),
        ("DCHD", "dram-channel-disable", 0xD4),
        ("PMC_", "pmc", 0xD8),
        ("PMCV", "pmc-pmgr bit 0", 0xDC),
        ("PMCB", "pmc-pmgr bit 3", 0xE0),
        ("PMCX", "pmc-msg-disabled", 0xE4),
        ("CVAR", "soc-chip-variant", 0xE8),
    )
    return {
        "service": {
            "start_vtable_slot": 0x5F0,
            "pre_firmware_load_vtable_slot": 0x890,
            "patch_firmware_vtable_slot": 0x898,
            "patch_override": "ApplePMPFirmware::patchFirmware",
        },
        "mandatory_patchbay_writes": [
            {
                "tag": tag,
                "source": source,
                "service_object_offset": offset,
                "value_bits": 32,
            }
            for tag, source, offset in mandatory_patches
        ],
        "rtbuddy_fixup": {
            "ordering": [
                "power on RTBuddy target",
                "service preFirmwareLoad",
                "copy firmware to target when required",
                "create coredump map when required",
                "service patchFirmware",
                "invoke registered patchbay callback",
                "firmware updatePatchBay",
                "firmware updateCoredumpWithPatchBay when required",
                "publish firmware to IORegistry",
                "write patchbay back to the target image",
            ],
            "firmware_object_offset": 0x21E8,
            "firmware_service_object_offset": 0x2170,
            "firmware_loaded_byte_offset": 0x10B,
            "completion": "set firmware-loaded byte, then announce firmware",
            "scope": (
                "image preparation and RTBuddy bookkeeping only; no PMP "
                "run-state or dashboard-ready acknowledgement is established"
            ),
        },
    }


def recover_rtbuddy_boot_handshake_code_contract(
    functions: dict[str, tuple[int, bytes]],
    symbols: dict[str, int],
) -> dict[str, object]:
    """Recover the CPU-start to RTKit endpoint-roll-call state machine.

    Status 6 is the first transport-level milestone after CPU start: it is
    published only after a valid Hello and a successfully replied endpoint
    roll call.  It still says nothing about ApplePMGR's PMP dashboard state.
    """

    required = (
        RTBUDDY_LOAD_FIRMWARE,
        RTBUDDY_PERFORM_POWER_STATE_GATED,
        RTBUDDY_IOP_VALIDATE,
        RTBUDDY_IOP_VALIDATE_POLLING,
        RTBUDDY_IOP_VALIDATE_BLOCKING,
        RTBUDDY_SET_IOP_STATUS,
        RTBUDDY_SET_IOP_STATUS_PUBLIC,
        RTBUDDY_MANAGEMENT_HANDLE_HELLO,
        RTBUDDY_MANAGEMENT_HANDLE_EP_ROLLCALL,
        RTBUDDY_CREATE_ENDPOINT,
        RTBUDDY_ENDPOINT_SERVICE_CREATE_NAME,
    )
    missing_symbols = [name for name in required if name not in symbols]
    if missing_symbols:
        raise ValueError(
            f"RTBuddy is missing boot-handshake symbols: {missing_symbols!r}"
        )
    missing_functions = [name for name in required if name not in functions]
    if missing_functions:
        raise ValueError(
            f"RTBuddy has no boot-handshake code body for {missing_functions!r}"
        )

    _load_address, load_code = functions[RTBUDDY_LOAD_FIRMWARE]
    if not _has_ordered_words(
        load_code,
        (
            0x39443668,  # power-transition suppression byte at RTBuddy+0x10d
            0x37000168,  # skip the power transition when it is set
            0xD2810311,  # RTBuddy setPowerState vtable slot 0x818
            0xAA1303E0,
            0x52800021,  # requested RTBuddy power state 1
            0xD2800002,  # no provider override
            0xD73F0910,
        ),
    ):
        raise ValueError("RTBuddy firmware-load power transition changed")

    perform_address, perform_code = functions[RTBUDDY_PERFORM_POWER_STATE_GATED]
    if direct_branch_count(
        perform_address, perform_code, symbols[RTBUDDY_SET_IOP_STATUS]
    ) != 2 or direct_branch_count(
        perform_address, perform_code, symbols[RTBUDDY_IOP_VALIDATE]
    ) != 1:
        raise ValueError("RTBuddy managed boot status calls changed")
    status_four_offset = perform_code.find(struct.pack("<I", 0x52800081))
    validate_offsets = [
        offset
        for offset in range(0, len(perform_code) - 3, 4)
        if direct_branch_target_at(perform_address, perform_code, offset)
        == symbols[RTBUDDY_IOP_VALIDATE]
    ]
    if (
        status_four_offset < 0
        or direct_branch_target_at(
            perform_address, perform_code, status_four_offset + 4
        )
        != symbols[RTBUDDY_SET_IOP_STATUS]
        or len(validate_offsets) != 1
        or not _has_ordered_words(
            perform_code[status_four_offset : validate_offsets[0] + 4],
            (
                0x52800081,  # status 4 before starting the IOP
                0xF9405A60,  # concrete AppleA7IOP wrapper at RTBuddy+0xb0
                0xF950F661,  # selected firmware at RTBuddy+0x21e8
                0xD2811111,  # AppleA7IOP startCPUWithOptions slot 0x888
                0xD73F0910,
            ),
        )
    ):
        raise ValueError("RTBuddy managed CPU-start ordering changed")

    validate_address, validate_code = functions[RTBUDDY_IOP_VALIDATE]
    if (
        direct_branch_count(
            validate_address,
            validate_code,
            symbols[RTBUDDY_IOP_VALIDATE_POLLING],
        )
        != 1
        or direct_branch_count(
            validate_address,
            validate_code,
            symbols[RTBUDDY_IOP_VALIDATE_BLOCKING],
        )
        != 1
        or not _has_ordered_words(
            validate_code,
            (
                0x39440008,  # validation mode byte at RTBuddy+0x100
                0x39442268,  # wrapper-running byte at RTBuddy+0x108
                0x528000D4,  # ordinary initial target status 6
                0x52800114,  # alternate target status 8
                0xF9009A60,  # validation start timestamp at RTBuddy+0x130
                0x52844B08,  # polling selector byte at RTBuddy+0x2258
            ),
        )
    ):
        raise ValueError("RTBuddy IOP validation dispatch changed")

    _polling_address, polling_code = functions[RTBUDDY_IOP_VALIDATE_POLLING]
    validation_result_words = (
        0xB9412800,  # timeout configuration at RTBuddy+0x128
        0xD2813D11,  # pollHardwareForMessage vtable slot 0x9e8
        0xB9415A88,  # current IOP status at RTBuddy+0x158
        0x6B08027F,  # success when current status equals the target
        0x7140211F,  # terminal failure status 0x8000
        0x528058E9,  # base error 0xe00002c7
        0x72BC0009,
        0x11003D2A,  # timeout error = base + 0xf = 0xe00002d6
    )
    if not _has_ordered_words(polling_code, validation_result_words):
        raise ValueError("RTBuddy polling validation loop changed")

    _blocking_address, blocking_code = functions[RTBUDDY_IOP_VALIDATE_BLOCKING]
    if not _has_ordered_words(
        blocking_code,
        (
            0x91056015,  # address of status word at RTBuddy+0x158
            0xB9412A80,  # timeout configuration at RTBuddy+0x128
            0x91084208,  # command-gate sleep vtable slot 0x210
            0xB9415A88,  # current IOP status
            0x6B08027F,  # success when current status equals the target
            0x7140211F,  # terminal failure status 0x8000
            0x528058E9,
            0x72BC0009,
            0x11003D2A,
        ),
    ):
        raise ValueError("RTBuddy blocking validation loop changed")

    set_public_address, set_public_code = functions[RTBUDDY_SET_IOP_STATUS_PUBLIC]
    if direct_branch_count(
        set_public_address, set_public_code, symbols[RTBUDDY_SET_IOP_STATUS]
    ) != 1 or not _has_ordered_words(
        set_public_code,
        (
            0xD2811111,  # obtain the RTBuddy command gate
            0x91056261,  # status word at RTBuddy+0x158
            0x52800002,  # wake every waiter for that word
        ),
    ):
        raise ValueError("RTBuddy IOP status publication changed")

    hello_address, hello_code = functions[RTBUDDY_MANAGEMENT_HANDLE_HELLO]
    hello_status_offsets = [
        offset
        for offset in range(0, len(hello_code) - 3, 4)
        if direct_branch_target_at(hello_address, hello_code, offset)
        == symbols[RTBUDDY_SET_IOP_STATUS_PUBLIC]
    ]
    if (
        len(hello_status_offsets) != 2
        or struct.unpack_from("<I", hello_code, hello_status_offsets[0] - 4)[0]
        != 0x528000A1
        or struct.unpack_from("<I", hello_code, hello_status_offsets[1] - 4)[0]
        != 0x52900001
        or not _has_ordered_words(
            hello_code,
            (
                0xB9415808,  # current IOP status
                0x7100111F,  # Hello is expected while status is 4
                0x7140211F,  # also handle the 0x8000 failure sentinel
                0xB9010661,  # save the Hello word
                0x12003C28,  # peer minimum protocol, low 16 bits
                0x7100311F,  # peer minimum must be <= 12
                0xD350FC28,  # peer maximum protocol, high 16 bits
                0x12003D08,
                0x7100311F,  # peer maximum must be >= 12
                0x528000A1,  # accepted Hello advances to status 5
            ),
        )
    ):
        raise ValueError("RTBuddy management Hello negotiation changed")

    roll_address, roll_code = functions[RTBUDDY_MANAGEMENT_HANDLE_EP_ROLLCALL]
    if direct_branch_count(
        roll_address, roll_code, symbols[RTBUDDY_CREATE_ENDPOINT]
    ) != 1 or not _has_ordered_words(
        roll_code,
        (
            0xD3609436,  # bitmap group is bits 32..37
            0x531B6AD5,  # first wire endpoint is group * 32
            0x36000097,  # create an endpoint for each set bitmap bit
            0x110006B5,  # advance to the next wire endpoint
            0x53017EF7,  # advance to the next bitmap bit
        ),
    ):
        raise ValueError("RTBuddy endpoint roll-call bitmap decoder changed")

    _create_name_address, create_name_code = functions[
        RTBUDDY_ENDPOINT_SERVICE_CREATE_NAME
    ]
    if not _has_ordered_words(
        create_name_code,
        (
            0x51007C33,  # generic service suffix = wire endpoint - 0x1f
            0xA9004FE0,  # format(provider-name, suffix)
        ),
    ):
        raise ValueError("RTBuddy application endpoint service-name mapping changed")

    roll_status_offsets = [
        offset
        for offset in range(0, len(roll_code) - 3, 4)
        if direct_branch_target_at(roll_address, roll_code, offset)
        == symbols[RTBUDDY_SET_IOP_STATUS_PUBLIC]
    ]
    if (
        len(roll_status_offsets) != 1
        or struct.unpack_from("<I", roll_code, roll_status_offsets[0] - 4)[0]
        != 0x528000C1
        or not _has_ordered_words(
            roll_code,
            (
                0xB9415808,  # current IOP status
                0x7100151F,  # endpoint roll call is expected at status 5
                0xD73F0910,  # send the roll-call reply
                0x35000180,  # do not advance when the reply send fails
                0xF9403A60,  # owning RTBuddy
                0x528000C1,  # successful roll call advances to status 6
            ),
        )
    ):
        raise ValueError("RTBuddy endpoint roll-call readiness changed")

    return {
        "firmware_load_power_transition": {
            "set_power_state_vtable_slot": 0x818,
            "requested_state": 1,
            "transition_suppression_byte_offset": 0x10D,
        },
        "managed_cpu_start": {
            "status_before_start": 4,
            "wrapper_object_offset": 0xB0,
            "firmware_object_offset": 0x21E8,
            "start_cpu_with_options_vtable_slot": 0x888,
            "completion": "enter IOP validation immediately after CPU start",
        },
        "rtkit_handshake": {
            "status_object_offset": 0x158,
            "timeout_object_offset": 0x128,
            "protocol_version": 12,
            "states": [
                {"status": 4, "meaning": "CPU start issued; awaiting Hello"},
                {"status": 5, "meaning": "Hello accepted at protocol 12"},
                {
                    "status": 6,
                    "meaning": "endpoint roll-call reply sent successfully",
                },
                {"status": 8, "meaning": "alternate power-state target"},
                {"status": 0x8000, "meaning": "terminal validation failure"},
            ],
            "validation_modes": ["poll mailbox", "block on status word"],
            "validation_target_selection": (
                "status 6 when RTBuddy byte 0x100 or 0x108 is set; "
                "otherwise status 8"
            ),
            "validation_success": "target status reached",
            "validation_failure": "status 0x8000 or configured timeout",
            "transport_ready_status": 6,
            "endpoint_roll_call": {
                "bitmap_word_bits": 32,
                "group_field": {"shift": 32, "bits": 6},
                "wire_endpoint": "group * 32 + set-bit index",
                "application_service_suffix": "wire endpoint - 0x1f",
                "endpoint1_wire_endpoint": 0x20,
                "scope": (
                    "Endpoint1 is a service-name suffix, not RTKit wire "
                    "endpoint 1"
                ),
            },
            "scope": (
                "RTBuddy transport and endpoint discovery only; it does not "
                "prove ApplePMGR observed PMP-STATUS or an AGX dashboard ack"
            ),
        },
    }


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
        RTBUDDY_CREATE_ENDPOINT,
        RTBUDDY_ENDPOINT_SERVICE_CREATE_NAME,
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
        "rtkit_boot": recover_rtbuddy_boot_handshake_code_contract(
            rtbuddy_functions, rtbuddy_symbols
        ),
    }


def recover_apple_a7iop_code_contract(
    functions: dict[str, tuple[int, bytes]],
    vtable_targets: dict[int, int],
) -> dict[str, object]:
    """Recover the AppleA7IOP wrapper-MMIO and SRAM-power contracts."""

    required = (
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
    )
    missing = [name for name in required if name not in functions]
    if missing:
        raise ValueError(f"AppleA7IOP has no code body for {missing!r}")

    _start_address, start_code = functions[APPLE_WRAPPER_MAILBOX_START]
    if not _has_ordered_words(
        start_code,
        (
            0xF9407E80,  # ldr x0, [x20, #0xf8] -- wrapper provider
            0x911C4208,  # add x8, x16, #0x710 -- mapDeviceMemoryWithIndex slot
            0xF9438A09,  # ldr x9, [x16, #0x710]
            0x52800001,  # mov w1, #0 -- device-memory index
            0x52800002,  # mov w2, #0 -- map options
            0xD73F0931,  # blraa x9, x17
            0xF900A280,  # str x0, [x20, #0x140] -- retained memory map
            0xD2802711,  # mov x17, #0x138 -- getVirtualAddress slot
            0x8B110210,  # add x16, x16, x17
            0xF9400208,  # ldr x8, [x16]
            0xD73F0910,  # blraa x8, x16
            0xF9008280,  # str x0, [x20, #0x100] -- mapped register VA
        ),
    ):
        raise ValueError("AppleWrapperMailbox device-memory mapping changed")

    _reg_address, reg_code = functions[APPLE_WRAPPER_MAILBOX_REG]
    expected_reg = struct.pack(
        "<4I",
        0xD503245F,  # bti c
        0xF9408008,  # ldr x8, [x0, #0x100] -- mapped register VA
        0xB8614900,  # ldr w0, [x8, w1, uxtw] -- byte offset, 32-bit access
        0xD65F03C0,  # ret
    )
    if reg_code != expected_reg:
        raise ValueError("AppleWrapperMailbox register accessor changed")

    physical_address, physical_code = functions[APPLE_WRAPPER_MAILBOX_PHYSICAL]
    if (
        len(physical_code) < 0x20
        or struct.unpack_from("<I", physical_code, 0x0C)[0] != 0xF940A000
        or struct.unpack_from("<I", physical_code, 0x10)[0] != 0xB40000A0
        or struct.unpack_from("<I", physical_code, 0x14)[0] & 0xFC000000
        != 0x94000000
        or direct_branch_target_at(physical_address, physical_code, 0x14) is None
    ):
        raise ValueError("AppleWrapperMailbox physical-address accessor changed")

    _a7_start_address, a7_start_code = functions[APPLE_A7IOP_START]
    if not _has_ordered_words(
        a7_start_code,
        (
            0xF9407E80,  # ldr x0, [x20, #0xf8] -- wrapper provider
            0x911C4208,  # add x8, x16, #0x710 -- mapDeviceMemoryWithIndex slot
            0xF9438A09,  # ldr x9, [x16, #0x710]
            0x52800001,  # mov w1, #0 -- device-memory index
            0x52800002,  # mov w2, #0 -- map options
            0xD73F0931,  # blraa x9, x17
            0xF900B680,  # str x0, [x20, #0x168] -- retained memory map
            0xD2802711,  # mov x17, #0x138 -- getVirtualAddress slot
            0x8B110210,  # add x16, x16, x17
            0xF9400208,  # ldr x8, [x16]
            0xD73F0910,  # blraa x8, x16
            0xF9008280,  # str x0, [x20, #0x100] -- mapped register VA
            0xB9400008,  # ldr w8, [x0] -- sram-index OSData payload
            0xB9015E88,  # str w8, [x20, #0x15c] -- SRAM power selector
            0x7100011F,  # cmp w8, #0
            0x1A9F07E2,  # cset w2, ne -- should-control-sram value
        ),
    ):
        raise ValueError("AppleA7IOP device-memory or SRAM-property mapping changed")
    if not _has_ordered_words(
        a7_start_code,
        (
            0x52800028,  # CPU-control writes are enabled by default
            0x3904CA88,  # strb w8, [x20, #0x132]
            0xD2805B11,  # provider property lookup slot 0x2d8
            0xB4000040,  # no cpu-ctrl-filtered property: retain default
            0x3904CA9F,  # property present: suppress CPU-control writes
        ),
    ):
        raise ValueError("AppleA7IOP CPU-control filter handling changed")

    _start_cpu_address, start_cpu_code = functions[APPLE_A7IOP_START_CPU_OPTIONS]
    if not _has_ordered_words(
        start_cpu_code,
        (
            0xD2814511,  # _runCPU vtable slot 0xa28
            0x8B110210,
            0xF9400208,
            0xAA1303E0,
            0x52800021,  # requested run state = true
            0xD73F0910,
        ),
    ):
        raise ValueError("AppleA7IOP startCPU run-control dispatch changed")

    _dart_map_address, dart_map_code = functions[
        APPLE_A7IOP_DART_MAP_IBOOT_FIRMWARE
    ]
    if not _has_ordered_words(
        dart_map_code,
        (
            0x3944C008,  # ldrb w8, [x0, #0x130] -- map-complete latch
            0xF9409408,  # ldr x8, [x0, #0x128] -- iBoot segment records
            0xD2811111,  # mov x17, #0x888 -- IOMapper::getPageSize
            0xD2811211,  # mov x17, #0x890 -- reserve/check mapper range
            0xB9401D0A,  # ldr w10, [x8, #0x1c] -- segment flags
            0x370805EA,  # tbnz w10, #1 -- skip non-mapped segment
            0xF9400909,  # ldr x9, [x8, #0x10] -- segment IOVA
            0xB940190B,  # ldr w11, [x8, #0x18] -- segment byte size
            0x7200015F,  # tst w10, #1 -- executable/read-only flag
            0x5280006A,  # mov w10, #3 -- read/write direction
            0x1A9F0541,  # csinc w1, w10, wzr, eq -- 1 or 3
            0xF9400104,  # ldr x4, [x8] -- physical base
            0xD2811411,  # mov x17, #0x8a0 -- IOMapper::iovmInsert
            0x8A160145,  # and x5, x10, x22 -- page-aligned byte size
            0xD2800003,  # mov x3, #0 -- no IOVA displacement
            0xD73F0910,  # blraa x8, x16
            0x3904C268,  # strb w8, [x19, #0x130] -- mapping complete
        ),
    ):
        raise ValueError("AppleA7IOP iBoot firmware DART mapping changed")

    _a7_reg_address, a7_reg_code = functions[APPLE_A7IOP_REG]
    if a7_reg_code != expected_reg:
        raise ValueError("AppleA7IOP register accessor changed")

    a7_physical_address, a7_physical_code = functions[APPLE_A7IOP_PHYSICAL]
    if (
        len(a7_physical_code) < 0x20
        or struct.unpack_from("<I", a7_physical_code, 0x0C)[0] != 0xF940B400
        or struct.unpack_from("<I", a7_physical_code, 0x10)[0] != 0xB40000A0
        or struct.unpack_from("<I", a7_physical_code, 0x14)[0] & 0xFC000000
        != 0x94000000
        or direct_branch_target_at(a7_physical_address, a7_physical_code, 0x14)
        is None
    ):
        raise ValueError("AppleA7IOP physical-address accessor changed")

    _enable_sram_address, enable_sram_code = functions[APPLE_A7IOP_ENABLE_SRAM]
    if not _has_ordered_words(
        enable_sram_code,
        (
            0xB9415C02,  # ldr w2, [x0, #0x15c] -- sram-index value
            0x34000222,  # cbz w2 -- zero means unsupported
            0xD2813911,  # mov x17, #0x9c8 -- _enablePower slot
            0x8B110210,  # add x16, x16, x17
            0xF9400208,  # ldr x8, [x16]
            0xD73F0910,  # blraa x8, x16; x1 remains requested state
            0x52805C40,  # mov w0, #0x2e2 -- unsupported error low half
            0x72BC0000,  # movk w0, #0xe000, lsl #16
        ),
    ):
        raise ValueError("AppleA7IOP SRAM-power dispatch changed")
    if vtable_targets.get(APPLE_A7IOP_ENABLE_POWER_VTABLE_SLOT) != functions[
        APPLE_A7IOP_ENABLE_POWER
    ][0]:
        raise ValueError("AppleA7IOP SRAM-power vtable target changed")

    _enable_power_address, enable_power_code = functions[APPLE_A7IOP_ENABLE_POWER]
    if not _has_ordered_words(
        enable_power_code,
        (
            0xAA0203F3,  # mov x19, x2 -- power-domain selector
            0xAA0103F4,  # mov x20, x1 -- requested state
            0xF9407C00,  # ldr x0, [x0, #0xf8] -- wrapper provider
            0xD2811511,  # mov x17, #0x8a8 -- prepare power transition
            0xD73F0910,  # blraa x8, x16
            0xF9407EA0,  # ldr x0, [x21, #0xf8] -- wrapper provider again
            0x9122C208,  # add x8, x16, #0x8b0 -- set power state
            0xF9445A09,  # ldr x9, [x16, #0x8b0]
            0xAA1403E1,  # mov x1, x20 -- requested state
            0xD2800002,  # mov x2, #0
            0xAA1303E3,  # mov x3, x19 -- sram-index power selector
            0xD73F0931,  # blraa x9, x17
        ),
    ):
        raise ValueError("AppleA7IOP provider power transition changed")

    return {
        "apple_a7iop": {
            "device_memory_index": 0,
            "map_options": 0,
            "provider_object_offset": 0xF8,
            "memory_map_object_offset": 0x168,
            "mapped_virtual_address_offset": 0x100,
            "register_access": {
                "width_bits": 32,
                "offset_unit": "bytes",
                "address": "mapped virtual address + zero-extended offset",
            },
            "physical_address_source": "retained device-memory map",
            "sram_power": {
                "selector_property": "sram-index",
                "selector_object_offset": 0x15C,
                "zero_means_unsupported": True,
                "published_capability_property": "should-control-sram",
                "enable_power_vtable_slot": APPLE_A7IOP_ENABLE_POWER_VTABLE_SLOT,
                "provider_prepare_power_vtable_slot": 0x8A8,
                "provider_set_power_vtable_slot": 0x8B0,
                "provider_selector_argument": "x3",
                "meaning": "provider power-domain selector; not a reg[] index",
            },
            "cpu_control": {
                "filter_property": "cpu-ctrl-filtered",
                "filter_absent_behavior": "permit concrete wrapper CPU-control writes",
                "start_cpu_run_vtable_slot": 0xA28,
                "start_cpu_run_argument": True,
            },
            "iboot_firmware_mapping": {
                "mapper_get_page_size_vtable_slot": 0x888,
                "mapper_reserve_vtable_slot": 0x890,
                "mapper_insert_vtable_slot": 0x8A0,
                "segment_record_size": 0x20,
                "physical_offset": 0,
                "iova_offset": 0x10,
                "size_offset": 0x18,
                "flags_offset": 0x1C,
                "skip_flag_bit": 1,
                "text_direction": 1,
                "data_direction": 3,
                "meaning": (
                    "records with flag bit 1 clear are page-aligned and inserted "
                    "into the supplied IOMapper before wrapper CPU release; bit 1 "
                    "marks an iBoot-installed mapping that this path preserves"
                ),
            },
            "scope": (
                "resource and power-domain ownership only; does not start or "
                "prove the IOP ready"
            ),
        },
        "wrapper_mailbox": {
            "device_memory_index": 0,
            "map_options": 0,
            "provider_object_offset": 0xF8,
            "map_device_memory_vtable_slot": 0x710,
            "memory_map_object_offset": 0x140,
            "get_virtual_address_vtable_slot": 0x138,
            "mapped_virtual_address_offset": 0x100,
            "register_access": {
                "width_bits": 32,
                "offset_unit": "bytes",
                "address": "mapped virtual address + zero-extended offset",
            },
            "physical_address_source": "retained device-memory map",
            "scope": (
                "wrapper mailbox/control resource ownership only; does not start "
                "or prove the IOP ready"
            ),
        }
    }


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
        **recover_apple_a7iop_code_contract(functions, vtable_targets),
    }


def recover_iodart_family_code_contract(
    functions: dict[str, tuple[int, bytes]],
    vtable_targets: dict[int, int],
    direction_lookup: tuple[int, ...],
) -> dict[str, object]:
    required = (
        IODART_MAPPER_GET_PAGE_SIZE,
        IODART_MAPPER_IOVM_INSERT,
        IODART_MAPPER_IOVM_INSERT_ONE,
    )
    missing = [name for name in required if name not in functions]
    if missing:
        raise ValueError(f"IODARTFamily has no code body for {missing!r}")
    expected_slots = {
        0x888: functions[IODART_MAPPER_GET_PAGE_SIZE][0],
        0x8A0: functions[IODART_MAPPER_IOVM_INSERT][0],
    }
    for slot, expected in expected_slots.items():
        if vtable_targets.get(slot) != expected:
            raise ValueError(f"IODARTMapper vtable slot {slot:#x} changed")
    if direction_lookup != (0, 2, 1, 3):
        raise ValueError(
            f"IODARTMapper direction lookup changed: {direction_lookup!r}"
        )

    _page_address, page_code = functions[IODART_MAPPER_GET_PAGE_SIZE]
    if page_code != struct.pack(
        "<4I", 0xD503245F, 0xF9409008, 0xF9401900, 0xD65F03C0
    ):
        raise ValueError("IODARTMapper page-size accessor changed")

    _insert_address, insert_code = functions[IODART_MAPPER_IOVM_INSERT]
    if not _has_ordered_words(
        insert_code,
        (
            0x12000428,  # and w8, w1, #3 -- IODirection index
            0xB8685937,  # ldr w23, [direction lookup, w8, uxtw #2]
            0xF9408408,  # ldr x8, [x0, #0x108] -- mapper DVA prefix
            0xAA020108,  # orr x8, x8, x2 -- requested DVA
            0x8B030118,  # add x24, x8, x3 -- DVA displacement
            0xF9401908,  # ldr x8, [x8, #0x30] -- page size
            0xB9411668,  # ldr w8, [x19, #0x114] -- page shift
            0x9AC82716,  # lsr x22, x24, x8 -- DVA page
            0x9AC8269B,  # lsr x27, x20, x8 -- physical page
            0x97FFFF63,  # call the per-page insertion path
        ),
    ):
        raise ValueError("IODARTMapper iovmInsert argument conversion changed")

    _one_address, one_code = functions[IODART_MAPPER_IOVM_INSERT_ONE]
    if not _has_ordered_words(
        one_code,
        (
            0xAA1503E1,  # mapper virtual page
            0xAA1703E2,  # physical page number
            0x52800043,  # page type 2
            0xAA1603E4,  # protection from direction lookup
            0x94000C12,  # IODARTVMSpace::setTranslation
            0x52800022,  # invalidate one page after insertion
        ),
    ):
        raise ValueError("IODARTMapper per-page insertion changed")

    return {
        "mapper": {
            "get_page_size_vtable_slot": 0x888,
            "iovm_insert_vtable_slot": 0x8A0,
            "direction_lookup": list(direction_lookup),
            "direction_1_protection": direction_lookup[1],
            "direction_3_protection": direction_lookup[3],
            "page_type": 2,
            "invalidation": "one DART page after each inserted page",
        }
    }


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
    required = (
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
    missing = [name for name in required if name not in functions]
    if missing:
        raise ValueError(f"AppleT8110DART has no code body for {missing!r}")

    _start_address, start_code = functions[APPLE_T8110_DART_START]
    if not _has_ordered_words(
        start_code,
        (
            0x947625EC,  # _t8110dart_get_desc()
            0xF9461A61,  # log context at object +0xc30
            0x9100A3E2,  # t8110dart_init_data on the stack
            0x91314264,  # output context at object +0xc50
            0x52812D03,  # init-data bytes = 0x968
            0x94757EC7,  # _pmap_iommu_init(...)
        ),
    ):
        raise ValueError("AppleT8110DART protected-IOMMU initialization changed")

    _setup_address, setup_code = functions[APPLE_T8110_DART_SETUP]
    if not _has_ordered_words(
        setup_code,
        (
            0x52800108,  # eight-byte optional bypass-address result
            0xF9004FE8,
            0x910263E3,
            0xAA1803E2,  # current SID
            0x94000FDF,  # _getSidProperty("bypass", SID, &size)
            0x3900A2E8,  # mark the per-SID record bypassed
            0xAA1A0108,  # add the SID to the bypass bitset
        ),
    ):
        raise ValueError("AppleT8110DART per-SID bypass setup changed")
    if bypass_property_prefix != "bypass":
        raise ValueError(
            f"AppleT8110DART bypass property prefix changed: {bypass_property_prefix!r}"
        )

    _property_address, property_code = functions[
        APPLE_T8110_DART_GET_SID_PROPERTY
    ]
    if not _has_ordered_words(
        property_code,
        (
            0xA9000BE1,  # property prefix and SID are snprintf arguments
            0x910083E0,  # 32-byte formatted-property buffer
            0x52800401,
        ),
    ):
        raise ValueError("AppleT8110DART SID-property formatter changed")
    if sid_property_format != "%s-%d":
        raise ValueError(
            f"AppleT8110DART SID-property format changed: {sid_property_format!r}"
        )

    _count_address, count_code = functions[APPLE_T8110_DART_GET_SID_COUNT]
    if not _has_ordered_words(
        count_code,
        (
            0x91008108,  # first hardware-instance record at owner +0x20
            0x52800E09,  # hardware-instance stride 0x70
            0x9BA97C29,  # mapper index selects that instance
            0xB9400D08,  # PARAMS4 at instance MMIO +0xc
            0x12002100,  # SID count is PARAMS4[8:0]
        ),
    ):
        raise ValueError("AppleT8110DART mapper/SID-count selection changed")

    _bypassed_address, bypassed_code = functions[
        APPLE_T8110_DART_IS_BYPASSED_SID
    ]
    if not _has_ordered_words(
        bypassed_code,
        (
            0x7100803F,  # SID 32 boundary for extended-bypass support
            0xF9448129,  # per-SID bypass bitset at object +0x900
            0x9AC82528,
            0x12000100,
        ),
    ):
        raise ValueError("AppleT8110DART bypass lookup changed")

    _enable_address, enable_code = functions[APPLE_T8110_DART_ENABLE_TRANSLATION]
    if not _has_ordered_words(
        enable_code,
        (
            0x7100005F,  # cmp w2, #0 -- requested translation state
            0x52902288,  # mov w8, #0x8114 -- disable selector
            0x9A880501,  # cinc x1, x8, ne -- enable selector 0x8115
            0x52800083,  # four-byte SID payload
        ),
    ):
        raise ValueError("AppleT8110DART translation-control transport changed")

    _set_address, set_code = functions[APPLE_T8110_DART_SET_TRANSLATION]
    if not _has_ordered_words(
        set_code,
        (
            0xD3727D1A,  # physical page number -> byte address, shift 14
            0x52880002,  # iovmalloc request bytes = one 0x4000 DART page
            0xD3727F08,  # DVA page number -> byte address, shift 14
            0xA905A3FA,  # one ppl_iommu_segm: physical then DVA
            0xA906FFE8,  # byte length then zeroed protection/reserved pair
            0xF9003FFF,  # reserved word at segment +0x20
            0x52800068,  # protection value 3
            0xB90073E8,  # store protection at segment +0x18
            0x52800022,  # pmap_iommu_map segment count = 1
        ),
    ):
        raise ValueError("AppleT8110DART 16 KiB translation path changed")

    _range_address, range_code = functions[
        APPLE_T8110_DART_SET_TRANSLATION_RANGE
    ]
    if not _has_ordered_words(
        range_code,
        (
            0xB94C8669,  # byte-range alignment at object +0xc84
            0x1AC90B48,  # start offset / alignment
            0x1B09E908,  # require zero start remainder
            0x1AC9090A,  # inclusive end offset / alignment
            0x1B09A14A,
            0x51000529,  # require end remainder == alignment - 1
            0x6B1A011B,  # byte length minus one = end - start
            0xD3727EA8,  # physical 16-KiB page number -> byte address
            0x8B3A4108,  # add byte-range start
            0xD3727F29,  # DVA 16-KiB page number -> byte address
            0x8B3A4129,  # add the same byte-range start
            0x11000768,  # segment byte length = end - start + 1
            0x52800022,  # pmap_iommu_map segment count = 1
        ),
    ):
        raise ValueError("AppleT8110DART partial-range translation path changed")

    _invalidate_address, invalidate_code = functions[
        APPLE_T8110_DART_INVALIDATE_TLB
    ]
    if invalidate_code != struct.pack("<2I", 0xD503245F, 0xD65F03C0):
        raise ValueError("AppleT8110DART invalidate ownership changed")
    return {
        "translation": {
            "page_shift": 14,
            "page_size": 0x4000,
            "disable_selector": 0x8114,
            "enable_selector": 0x8115,
            "sid_payload_bytes": 4,
            "driver_invalidate_method": "no-op",
            "hardware_update_owner": "kernel PPL/SPTM IOMMU request",
            "protected_context": {
                "descriptor_source": "_t8110dart_get_desc",
                "initializer": "_pmap_iommu_init",
                "init_data_bytes": 0x968,
                "object_context_offset": 0xC50,
            },
            "map_request": {
                "segment_bytes": 0x28,
                "segment_count": 1,
                "physical_offset": 0,
                "iova_offset": 8,
                "byte_length_offset": 0x10,
                "protection_offset": 0x18,
                "protection": 3,
                "reserved_offset": 0x20,
                "meaning_of_3": "read/write protection, not segment count",
            },
            "partial_range": {
                "alignment_object_offset": 0xC84,
                "start_must_be_aligned": True,
                "end_is_inclusive": True,
                "end_remainder": "alignment - 1",
                "byte_length": "end - start + 1",
                "entry_encoding_owner": "kernel PPL/SPTM IOMMU request",
            },
            "mapper_index_semantics": "DART hardware instance, not SID",
            "hardware_instance_stride": 0x70,
            "sid_count_register_offset": 0xC,
            "sid_count_mask": 0x1FF,
            "sid_property_format": sid_property_format,
            "bypass_property_prefix": bypass_property_prefix,
            "bypass_bitset_object_offset": 0x900,
        }
    }


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
    required = (
        T8110_DART_MAX_TRANSLATION_LEVELS,
        T8110_DART_VO_TT_INDEX,
        T8110_DART_VO_TTE,
    )
    missing = [name for name in required if name not in functions]
    if missing:
        raise ValueError(f"kernel has no T8110 DART code body for {missing!r}")
    if index_masks != (0x3E00000000, 0x1FFC00000, 0x3FF800, 0x7FF):
        raise ValueError(f"T8110 DART index masks changed: {index_masks!r}")
    if index_shifts != (33, 22, 11, 0):
        raise ValueError(f"T8110 DART index shifts changed: {index_shifts!r}")

    _levels_address, levels_code = functions[T8110_DART_MAX_TRANSLATION_LEVELS]
    if not _has_ordered_words(levels_code, (0x52800068, 0x1A880500)):
        raise ValueError("T8110 DART maximum-level selection changed")
    _tte_address, tte_code = functions[T8110_DART_VO_TTE]
    if not _has_ordered_words(
        tte_code,
        (
            0x360003EA,  # bit 0 is the valid bit
            0xD37CED4A,  # encoded address << 4
            0x92726D40,  # retain physical bits through 0x3ffffffc000
        ),
    ):
        raise ValueError("T8110 DART table-entry decoding changed")
    return {
        "page_table": {
            "max_levels": 4,
            "valid_bit": 0,
            "physical_decode_shift": 4,
            "physical_decode_mask": 0x3FFFFFFC000,
            "index_masks_on_page_number": list(index_masks),
            "index_shifts_on_page_number": list(index_shifts),
        }
    }


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
    """Recover the concrete ASCWrap-v6 firmware and CPU-control registers."""

    required = (
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
    missing = [name for name in required if name not in functions]
    if missing:
        raise ValueError(f"AppleASCWrapV6 has no code body for {missing!r}")
    expected_slots = {
        0x970: functions[APPLE_ASCWRAP_V6_INITIALIZE][0],
        0xA18: functions[APPLE_ASCWRAP_V6_MAP_FIRMWARE][0],
        0xA28: functions[APPLE_ASCWRAP_V6_RUN_CPU][0],
    }
    if vtable_targets != expected_slots:
        raise ValueError("AppleASCWrapV6 firmware/run vtable targets changed")

    _initialize_address, initialize_code = functions[APPLE_ASCWRAP_V6_INITIALIZE]
    if not _has_ordered_words(
        initialize_code,
        (
            0xF9407C00,  # wrapper provider at this+0xf8
            0xD280E211,  # mapDeviceMemoryWithIndex slot 0x710
            0x52800021,  # device-memory index 1
            0x52800002,  # mapping options 0
            0xD73F0910,
            0xF900C660,  # retained map at this+0x188
            0xD2802711,  # getVirtualAddress slot 0x138
            0xD73F0910,
            0xF900CA60,  # mapped VA at this+0x190
        ),
    ):
        raise ValueError("AppleASCWrapV6 IORVBAR resource mapping changed")

    _set_address, set_code = functions[APPLE_ASCWRAP_V6_SET_IORVBAR]
    expected_set = struct.pack(
        "<7I",
        0xD503245F,  # bti c
        0xB9418008,  # ldr w8, [x0, #0x180] -- register byte offset
        0xB2400029,  # orr x9, x1, #1 -- address plus lock bit
        0xF940C80A,  # ldr x10, [x0, #0x190] -- device-memory index 1 VA
        0x8B080148,  # add x8, x10, x8
        0xF9000109,  # str x9, [x8]
        0xD65F03C0,  # ret
    )
    if set_code != expected_set:
        raise ValueError("AppleASCWrapV6 IORVBAR writer changed")

    _locked_address, locked_code = functions[APPLE_ASCWRAP_V6_IS_IORVBAR_LOCKED]
    expected_locked = struct.pack(
        "<7I",
        0xD503245F,  # bti c
        0xB9418008,  # ldr w8, [x0, #0x180] -- register byte offset
        0xF940C809,  # ldr x9, [x0, #0x190] -- device-memory index 1 VA
        0x8B080128,  # add x8, x9, x8
        0xF9400108,  # ldr x8, [x8]
        0x12000100,  # and w0, w8, #1
        0xD65F03C0,  # ret
    )
    if locked_code != expected_locked:
        raise ValueError("AppleASCWrapV6 IORVBAR lock test changed")

    _map_address, map_code = functions[APPLE_ASCWRAP_V6_MAP_FIRMWARE]
    if not _has_ordered_words(
        map_code,
        (
            0x37080243,  # options bit 1 skips this mapping path
            0x94000EB4,  # _hasiBootFirmware()
            0x34000140,  # no iBoot firmware: check inherited IORVBAR lock
            0xF9409E61,  # iBoot firmware: mapper at object +0x138
            0xB9418268,  # register byte offset at this+0x180
            0xF940CA69,  # device-memory index 1 VA at this+0x190
            0x8B080128,
            0xF9400108,  # read IORVBAR
            0x36000088,  # fail closed when lock bit 0 is clear
        ),
    ):
        raise ValueError("AppleASCWrapV6 firmware-map lock requirement changed")

    _run_address, run_code = functions[APPLE_ASCWRAP_V6_RUN_CPU]
    if not _has_ordered_words(
        run_code,
        (
            0x3944C808,  # CPU-control permission byte at this+0x132
            0x36000528,  # no permission means no register access
            0xD2813511,  # _reg vtable slot 0x9a8
            0x52800881,  # register byte offset 0x44
            0xD73F0910,
            0xF9408268,  # device-memory index 0 VA at this+0x100
            0x34000094,  # branch between run and stop sequences
            0x321C0009,  # run: set bit 4
            0xB9004509,  # store wrapper register 0x44
            0x121B780A,  # stop phase 1: clear bit 4
            0xB900450A,
            0xD2813511,  # reread register 0x44
            0x52800881,
            0xD73F0910,
            0x121A7808,  # stop phase 2: clear bit 5
            0xB9004528,
        ),
    ):
        raise ValueError("AppleASCWrapV6 CPU run-control sequence changed")

    _inbox_address, inbox_code = functions[APPLE_ASCWRAP_V6_INBOX]
    expected_inbox = struct.pack(
        "<7I",
        0xD503245F,  # bti c
        0xA9402428,  # ldp x8, x9, [x1] -- complete 16-byte item
        0xF940800A,  # ldr x10, [x0, #0x100] -- reg[0] mapped VA
        0x5291000B,  # mov w11, #0x8800
        0x8B0B014A,  # add x10, x10, x11
        0xA9002548,  # stp x8, x9, [x10]
        0xD65F03C0,  # ret
    )
    if inbox_code != expected_inbox:
        raise ValueError("AppleASCWrapV6 mailbox inbox layout changed")

    _outbox_address, outbox_code = functions[APPLE_ASCWRAP_V6_OUTBOX]
    expected_outbox = struct.pack(
        "<7I",
        0xD503245F,  # bti c
        0xF9408008,  # ldr x8, [x0, #0x100] -- reg[0] mapped VA
        0x52910609,  # mov w9, #0x8830
        0x8B090108,  # add x8, x8, x9
        0xA9402508,  # ldp x8, x9, [x8]
        0xA9002428,  # stp x8, x9, [x1] -- complete 16-byte item
        0xD65F03C0,  # ret
    )
    if outbox_code != expected_outbox:
        raise ValueError("AppleASCWrapV6 mailbox outbox layout changed")

    _size_address, item_size_code = functions[APPLE_ASCWRAP_V6_MAILBOX_ITEM_SIZE]
    if item_size_code != struct.pack("<3I", 0xD503245F, 0x52800200, 0xD65F03C0):
        raise ValueError("AppleASCWrapV6 mailbox item size changed")

    status_contracts = (
        (APPLE_ASCWRAP_V6_KIC_INBOX_ENABLED, 0x52902201, 0x12000000),
        (APPLE_ASCWRAP_V6_INBOX_EMPTY, 0x52902201, 0x53114400),
        (APPLE_ASCWRAP_V6_INBOX_FULL, 0x52902201, 0x53104280),
        (APPLE_ASCWRAP_V6_OUTBOX_EMPTY, 0x52902281, 0x53114680),
    )
    for name, register_offset, bit_extract in status_contracts:
        _address, code = functions[name]
        if not _has_ordered_words(
            code,
            (
                0xD2813511,  # _reg vtable slot 0x9a8
                register_offset,
                0xD73F0910,
                bit_extract,
            ),
        ):
            raise ValueError(f"AppleASCWrapV6 mailbox status accessor changed: {name}")

    return {
        "iorvbar": {
            "device_memory_index": 1,
            "map_options": 0,
            "memory_map_object_offset": 0x188,
            "mapped_virtual_address_offset": 0x190,
            "register_offset_object_offset": 0x180,
            "t6050_register_offset": 0,
            "access_width_bits": 64,
            "write_value": "firmware address OR lock bit 0",
            "map_firmware": {
                "options_skip_bit": 1,
                "iboot_probe": "_hasiBootFirmware",
                "iboot_behavior": (
                    "process segment records through mapper; do not access IORVBAR"
                ),
                "non_iboot_requirement": "IORVBAR lock bit 0 must already be set",
            },
        },
        "cpu_run_control": {
            "device_memory_index": 0,
            "register_offset": 0x44,
            "access_width_bits": 32,
            "run": "read-modify-write setting bit 4",
            "stop": (
                "read-modify-write clearing bit 4, then reread and clear bit 5"
            ),
            "permission_object_offset": 0x132,
            "filter_property": "cpu-ctrl-filtered",
            "t6050_filter_property_present": False,
        },
        "mailbox_v4": {
            "device_memory_index": 0,
            "window_offset": 0x8000,
            "window_size": 0x1000,
            "item_size": 16,
            "access_width_bits": 64,
            "registers": {
                "a2i_control": 0x110,
                "i2a_control": 0x114,
                "a2i_message": 0x800,
                "i2a_message": 0x830,
            },
            "status_bits": {
                "kic_inbox_enabled": 0,
                "full": 16,
                "empty": 17,
            },
            "message_words": 2,
            "endpoint": "low byte of the second 64-bit word",
        },
        "vtable_slots": {
            "initialize": 0x970,
            "map_firmware": 0xA18,
            "run_cpu": 0xA28,
            "register_read": 0x9A8,
        },
        "scope": (
            "concrete firmware/run register contract only; it does not prove "
            "that PMP reached RTKit or dashboard readiness"
        ),
    }


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
        "schema": 22,
        "chip": "t6050",
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
