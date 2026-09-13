#!/usr/bin/env python3
"""Recover the base-M1 (t8103 / G13G) native boot-data contract.

Read-only host tool.  Vinix boots an M1 GPU only from an m1n1 FDT; the native
Apple DeviceTree path is refused because it was thought to carry nothing the
G13 firmware data needs.  This answers that with evidence instead:

  * What a base-M1 Apple DeviceTree actually carries for the GPU, and how those
    names line up with the ``apple,*`` properties Vinix already reads from an
    m1n1 FDT.  The mapping is not asserted here -- it is derived by a mechanical
    rule and then confirmed against two independent sources: the DeviceTree
    itself and AGXG13G's own string table.
  * Where Apple's AGXG13G gets the figures the DeviceTree does not carry.

Both a staged image and a live capture can be read.  That distinction matters:
a staged DeviceTree is a template whose fused performance table is zero-filled
until iBoot writes it at boot, so names and shapes come from the image and
values come from a machine.  The two agree on which inputs are missing.

Every base-M1 kext and DeviceTree is available on any Mac, not just an M1:
a macOS install stages one kernel collection and one DeviceTree per supported
board under Preboot for restore.

The output is names, shapes, template values, and recovered instruction shapes.
No DeviceTree payload or firmware image is copied into the repository.
"""

from __future__ import annotations

import argparse
import json
import plistlib
import struct
from pathlib import Path

from extract_firmware import unwrap_im4p
from recover_g17_abi import macho_symbols, macho_uuid, symbol_code
from recover_t6050_power import (
    decompress_device_tree,
    parse_adt,
    walk_adt,
)


DEFAULT_PREBOOT = Path("/System/Volumes/Preboot")
# G13G is the base M1 GPU.  mac13g is the staged collection that carries it;
# any of these boards is a base-M1 (t8103) machine whose DeviceTree describes
# the same SGX block.  j313ap is the MacBook Air.
BASE_M1_PLATFORM = "mac13g"
BASE_M1_BOARDS = ("j274ap", "j293ap", "j313ap", "j456ap", "j457ap")
DEFAULT_BOARD = "j313ap"
SGX_PATH = "/device-tree/arm-io/sgx"
AGX_G13G_ENTRY = "com.apple.AGXG13G"
DEFAULT_AGX_G13G = Path("build/kext/g13g/AGXG13G.macho")

# Apple's DeviceTree spells the GPU control loop with a gpu- prefix; m1n1
# republishes the same values as apple,-prefixed FDT properties.  Everything
# Vinix reads follows that one rule, so derive the ADT name rather than listing
# it, and keep only the genuine exceptions below.
FDT_PREFIX = "apple,"
ADT_PREFIX = "gpu-"

# Properties Vinix reads from an m1n1 FDT that do not follow the rule.  An empty
# tuple means the value has no Apple DeviceTree equivalent at all.
MAPPING_EXCEPTIONS: dict[str, tuple[str, ...]] = {
    # m1n1 builds the OPP-v2 table out of perf-states, so the table itself maps
    # to the ADT state counts.  Its three per-state columns are listed
    # separately because they do not all survive the translation: perf-states
    # is {frequency_hz, voltage_mV} pairs and carries no power at all.
    "operating-points-v2": ("perf-state-count", "gpu-num-perf-states"),
    "opp-hz": ("perf-states",),
    "opp-microvolt": ("perf-states",),
    "opp-microwatt": (),
    # The SRAM floor is an m1n1 invention: it clamps the ADT core voltages.
    "apple,min-sram-microvolt": (),
    # Leakage is fused, not published.  See the calculateGPULeakage recovery.
    "apple,core-leak-coef": (),
    "apple,sram-leak-coef": (),
    # One FDT triple per zone against three indexed ADT families.
    "apple,power-zones": (
        "gpu-power-zone-target-0",
        "gpu-power-zone-target-offset-0",
        "gpu-power-zone-filter-tc-0",
    ),
    # m1n1 negotiates the firmware ABI; it is not a DeviceTree fact.
    "apple,firmware-abi": (),
    "apple,firmware-version": (),
}

# Every apple,* property the t8103 paths in kernel/modules/gpu/agx/driver read.
# Required means load_t8103_* refuses the tree without it.
REQUIRED_FDT_PROPERTIES = (
    "operating-points-v2",
    "opp-hz",
    "opp-microvolt",
    "opp-microwatt",
    "apple,min-sram-microvolt",
    "apple,power-sample-period",
    "apple,core-leak-coef",
    "apple,sram-leak-coef",
    "apple,avg-power-filter-tc-ms",
    "apple,avg-power-ki-only",
    "apple,avg-power-kp",
    "apple,avg-power-min-duty-cycle",
    "apple,avg-power-target-filter-tc",
    "apple,fast-die0-integral-gain",
    "apple,fast-die0-proportional-gain",
    "apple,perf-filter-drop-threshold",
    "apple,perf-filter-time-constant",
    "apple,perf-filter-time-constant2",
    "apple,perf-integral-gain2",
    "apple,perf-integral-min-clamp",
    "apple,perf-proportional-gain2",
    "apple,perf-tgt-utilization",
    "apple,ppm-filter-time-constant-ms",
    "apple,ppm-ki",
    "apple,ppm-kp",
    "apple,pwr-min-duty-cycle",
)
OPTIONAL_FDT_PROPERTIES = (
    "apple,firmware-abi",
    "apple,firmware-version",
    "apple,perf-base-pstate",
    "apple,power-zones",
    "apple,fast-die0-prop-tgt-delta",
    "apple,fast-die0-release-temp",
    "apple,fender-idle-off-delay-ms",
    "apple,fw-early-wake-timeout-ms",
    "apple,idle-off-delay-ms",
    "apple,idleoff-standby-timer",
    "apple,perf-boost-ce-step",
    "apple,perf-boost-min-util",
    "apple,perf-integral-gain",
    "apple,perf-proportional-gain",
    "apple,perf-reset-iters",
    "apple,pwr-filter-time-constant",
    "apple,pwr-integral-gain",
    "apple,pwr-integral-min-clamp",
    "apple,pwr-proportional-gain",
    "apple,pwr-sample-period-aic-clks",
    "apple,se-engagement-criteria",
    "apple,se-filter-time-constant",
    "apple,se-filter-time-constant-1",
    "apple,se-inactive-threshold",
    "apple,se-ki",
    "apple,se-ki-1",
    "apple,se-kp",
    "apple,se-kp-1",
    "apple,se-reset-criteria",
)

# AGXFirmware::setupConfig reads a maximum GPU power straight out of the
# DeviceTree, preferring the device-scoped name, and has no computed fallback
# behind either.  Neither name is in a staged base-M1 tree, and neither is in a
# live one: a MacBookAir10,1 running macOS 26.3.1 publishes 68 sgx properties
# and none of them is a power.  So the figure G13 firmware data needs has no
# Apple DeviceTree source on this chip at all, template or not.
MAX_POWER_PROPERTIES = ("gpu-device-max-power", "gpu-max-power")
SETUP_CONFIG_SYMBOL = "__ZN11AGXFirmware11setupConfigEv"
LEAKAGE_SYMBOLS = (
    "__ZN21AGXAcceleratorG13G_A019calculateGPULeakageEPv",
    "__ZN21AGXAcceleratorG13G_B019calculateGPULeakageEPv",
)


def find_platform_device_tree(preboot: Path, board: str) -> Path:
    candidates = sorted(
        path
        for path in preboot.glob(f"*/restore-staged/Firmware/all_flash/DeviceTree.{board}.im4p")
        if path.is_file()
    )
    if len(candidates) != 1:
        rendered = ", ".join(str(path) for path in candidates) or "none"
        raise ValueError(f"expected one {board} DeviceTree, found: {rendered}")
    return candidates[0]


def load_device_tree(path: Path):
    image_type, payload, _extra = unwrap_im4p(path.read_bytes())
    if image_type != b"dtre":
        raise ValueError(f"not a DeviceTree IM4P (type={image_type!r})")
    return parse_adt(decompress_device_tree(payload))


def adt_name_for(fdt_property: str) -> tuple[str, ...]:
    if fdt_property in MAPPING_EXCEPTIONS:
        return MAPPING_EXCEPTIONS[fdt_property]
    if not fdt_property.startswith(FDT_PREFIX):
        raise ValueError(f"{fdt_property} is neither an apple, property nor an exception")
    return (ADT_PREFIX + fdt_property.removeprefix(FDT_PREFIX),)


def describe_value(data: bytes) -> dict[str, object]:
    described: dict[str, object] = {"bytes": len(data), "all_zero": data == bytes(len(data))}
    if len(data) == 4:
        described["u32"] = struct.unpack("<I", data)[0]
    elif len(data) == 8:
        described["u64"] = struct.unpack("<Q", data)[0]
    return described


def sgx_inventory(root) -> dict[str, dict[str, object]]:
    nodes = dict(walk_adt(root))
    if SGX_PATH not in nodes:
        raise ValueError(f"DeviceTree has no {SGX_PATH} node")
    node = nodes[SGX_PATH]
    return {
        name: describe_value(prop.data)
        for name, prop in sorted(node.properties.items())
    }


def live_sgx_inventory(plist_path: Path) -> dict[str, dict[str, object]]:
    """Inventory an sgx node captured from a running M1's IORegistry.

    A staged DeviceTree is only a template, so the fused performance table can
    be read nowhere but a live machine.  Capture it with:

        ioreg -rw0 -p IODeviceTree -n sgx -d1 -a > sgx.plist

    IORegistry adds its own IO* bookkeeping keys to the node; those are not
    DeviceTree properties and are dropped here.
    """
    with plist_path.open("rb") as handle:
        loaded = plistlib.load(handle)
    node = loaded[0] if isinstance(loaded, list) else loaded
    return {
        name: describe_value(value)
        for name, value in sorted(node.items())
        if isinstance(value, bytes) and not name.startswith("IO")
    }


def read_perf_states(plist_path: Path) -> bytes | None:
    with plist_path.open("rb") as handle:
        loaded = plistlib.load(handle)
    node = loaded[0] if isinstance(loaded, list) else loaded
    value = node.get("perf-states")
    return value if isinstance(value, bytes) else None


def decode_perf_states(data: bytes) -> list[dict[str, int]]:
    """Decode perf-states, which is {frequency_hz, voltage_mV} pairs.

    There is no third column.  This is the whole reason the native path cannot
    build a G13 performance table: m1n1's opp-microwatt has no source here.
    """
    if len(data) % 8:
        raise ValueError("perf-states is not an array of 32-bit pairs")
    states = []
    for offset in range(0, len(data), 8):
        frequency_hz, voltage_mv = struct.unpack_from("<II", data, offset)
        states.append({"frequency_hz": frequency_hz, "voltage_mv": voltage_mv})
    return states


def recover_mapping(
    inventory: dict[str, dict[str, object]], driver_strings: set[str]
) -> list[dict[str, object]]:
    recovered = []
    for fdt_property in REQUIRED_FDT_PROPERTIES + OPTIONAL_FDT_PROPERTIES:
        adt_names = adt_name_for(fdt_property)
        entries = []
        for name in adt_names:
            entries.append(
                {
                    "adt_property": name,
                    "in_device_tree": name in inventory,
                    "in_driver_strings": name in driver_strings,
                    "value": inventory.get(name),
                }
            )
        recovered.append(
            {
                "fdt_property": fdt_property,
                "required_by_vinix": fdt_property in REQUIRED_FDT_PROPERTIES,
                "has_adt_equivalent": bool(adt_names),
                "adt": entries,
            }
        )
    return recovered


def macho_cstrings(image: bytes) -> set[str]:
    """Collect the driver's NUL-terminated gpu-/perf- property name strings."""
    found = set()
    for chunk in image.split(b"\0"):
        if not chunk or len(chunk) > 64:
            continue
        try:
            text = chunk.decode("ascii")
        except UnicodeDecodeError:
            continue
        if text.startswith(("gpu-", "perf-", "gfx-")) and all(
            character.isalnum() or character in "-_" for character in text
        ):
            found.add(text)
    return found


def decode_add_immediate_64(word: int) -> tuple[int, int, int] | None:
    if word & 0xFF000000 != 0x91000000:
        return None
    immediate = (word >> 10) & 0xFFF
    if word & (1 << 22):
        immediate <<= 12
    return word & 0x1F, (word >> 5) & 0x1F, immediate


def decode_ldr_unsigned(word: int, opcode: int, scale: int) -> tuple[int, int, int] | None:
    if word & 0xFFC00000 != opcode:
        return None
    return word & 0x1F, (word >> 5) & 0x1F, ((word >> 10) & 0xFFF) * scale


def recover_gpu_leakage_read(image: bytes, symbol: str) -> dict[str, object]:
    """Recover AGXAcceleratorG13G_*::calculateGPULeakage(void *fuses).

    The whole body is: read one 64-bit word from the fuse aperture at a
    driver-held byte offset, shift it right, mask it, add one, convert to float
    and scale by a driver-held f32.  Leakage is therefore a per-die fused
    value, which is why no DeviceTree carries a leakage coefficient.
    """
    address, code = symbol_code(image, symbol)
    words = [
        struct.unpack_from("<I", code, offset)[0] for offset in range(0, len(code) & ~3, 4)
    ]
    if len(words) < 14:
        raise ValueError(f"{symbol} is too short to be the recovered leakage read")

    if words[0] != 0xD503245F:
        raise ValueError(f"{symbol} does not open with bti c")
    scaled_base = decode_add_immediate_64(words[1])
    if scaled_base is None or scaled_base[1] != 0 or not words[1] & (1 << 22):
        raise ValueError(f"{symbol} does not derive a shifted field base from this")
    base_register, _source, base_offset = scaled_base

    fields: dict[str, int] = {}
    for name, index, opcode, scale in (
        ("fuse_byte_offset", 2, 0xB9400000, 4),
        ("shift", 5, 0xB9400000, 4),
        ("mask", 7, 0xB9400000, 4),
        ("scale_f32", 11, 0xBD400000, 4),
    ):
        decoded = decode_ldr_unsigned(words[index], opcode, scale)
        if decoded is None or decoded[1] != base_register:
            raise ValueError(f"{symbol} field load {name} does not match the recovery")
        fields[name] = base_offset + decoded[2]

    expected = {
        3: 0x8B010129,  # add x9, x9, x1        -- fuse aperture + byte offset
        4: 0xF9400129,  # ldr x9, [x9]
        6: 0x9ACA2529,  # lsr x9, x9, x10
        8: 0x8A0A0129,  # and x9, x9, x10
        9: 0x91000529,  # add x9, x9, #1
        10: 0x9E230120,  # ucvtf s0, x9
        12: 0x1E200820,  # fmul s0, s1, s0
        13: 0xD65F03C0,  # ret
    }
    for index, word in expected.items():
        if words[index] != word:
            raise ValueError(f"{symbol} word {index} is not the recovered leakage read")

    return {
        "symbol": symbol,
        "address": address,
        "field_base": base_offset,
        "fields": fields,
        "equation": "leakage = scale_f32 * (((fuses[fuse_byte_offset] >> shift) & mask) + 1)",
        "inputs": "one fused 64-bit word; no DeviceTree or temperature input",
    }


def recover_max_power_properties(image: bytes) -> dict[str, object]:
    """Recover the DeviceTree names AGXFirmware::setupConfig reads for max power.

    Both are looked up in order with no computed fallback: when neither exists
    the field is left alone, so a maximum GPU power is a published figure on
    this chip, never a derived one.
    """
    address, code = symbol_code(image, SETUP_CONFIG_SYMBOL)
    strings = macho_cstrings(image)
    order = [name for name in MAX_POWER_PROPERTIES if name in strings]
    return {
        "symbol": SETUP_CONFIG_SYMBOL,
        "address": address,
        "bytes": len(code),
        "read_order": order,
        "computed_fallback": False,
    }


def recover(
    inventory: dict[str, dict[str, object]],
    source: str,
    live: bool,
    agx_g13g: Path | None,
    perf_states: bytes | None = None,
) -> dict[str, object]:
    driver_strings: set[str] = set()
    driver: dict[str, object] = {"available": False}
    if agx_g13g is not None and agx_g13g.is_file():
        image = agx_g13g.read_bytes()
        driver_strings = macho_cstrings(image)
        symbols = macho_symbols(image)
        driver = {
            "available": True,
            "uuid": macho_uuid(image),
            "leakage": [
                recover_gpu_leakage_read(image, symbol)
                for symbol in LEAKAGE_SYMBOLS
                if symbol in symbols
            ],
            "max_power": recover_max_power_properties(image),
        }

    mapping = recover_mapping(inventory, driver_strings)
    unmapped = sorted(
        name
        for name in inventory
        if name.startswith(ADT_PREFIX)
        and not any(
            entry["adt_property"] == name for record in mapping for entry in record["adt"]
        )
    )
    # A record with no ADT equivalent at all is missing; an empty "all" is
    # vacuously true and would report the real gaps as satisfied.
    missing_required = [
        record["fdt_property"]
        for record in mapping
        if record["required_by_vinix"]
        and (
            not record["has_adt_equivalent"]
            or not all(entry["in_device_tree"] for entry in record["adt"])
        )
    ]
    perf_states_described = inventory.get("perf-states")
    return {
        "schema": 2,
        "source": source,
        "live": live,
        "platform": BASE_M1_PLATFORM,
        "sgx_property_count": len(inventory),
        "sgx_properties": inventory,
        "mapping": mapping,
        "adt_properties_vinix_ignores": unmapped,
        "missing_required_inputs": missing_required,
        # A staged DeviceTree is a template: iBoot fills the fused performance
        # table in at boot.  An all-zero perf-states here is the image saying so,
        # not a parse failure, and it is why no real frequency or voltage can be
        # read out of this file.
        "perf_states_is_template": bool(
            perf_states_described and perf_states_described["all_zero"]
        ),
        "perf_states": decode_perf_states(perf_states) if perf_states else None,
        "driver": driver,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--preboot", type=Path, default=DEFAULT_PREBOOT)
    parser.add_argument(
        "--board",
        default=DEFAULT_BOARD,
        choices=BASE_M1_BOARDS,
        help="base-M1 board whose staged DeviceTree to read",
    )
    parser.add_argument("--device-tree", type=Path, help="override the DeviceTree image")
    parser.add_argument(
        "--live-sgx",
        type=Path,
        help="an sgx node captured on a running M1 with "
        "`ioreg -rw0 -p IODeviceTree -n sgx -d1 -a`; the only place the fused "
        "performance table exists",
    )
    parser.add_argument(
        "--agx-g13g",
        type=Path,
        default=DEFAULT_AGX_G13G,
        help=f"AGXG13G Mach-O, from extract_fileset.py --platform {BASE_M1_PLATFORM}",
    )
    args = parser.parse_args()

    try:
        if args.live_sgx:
            source = str(args.live_sgx)
            live = True
            inventory = live_sgx_inventory(args.live_sgx)
            perf_states = read_perf_states(args.live_sgx)
        else:
            source = str(
                args.device_tree or find_platform_device_tree(args.preboot, args.board)
            )
            live = False
            inventory = sgx_inventory(load_device_tree(Path(source)))
            perf_states = None
        recovered = recover(inventory, source, live, args.agx_g13g, perf_states)
    except (OSError, ValueError) as error:
        parser.error(str(error))

    print(json.dumps(recovered, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
