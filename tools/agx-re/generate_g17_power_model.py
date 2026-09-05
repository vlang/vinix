#!/usr/bin/env python3
"""Generate Vinix's no-FPU G17C leakage-model lookup tables.

The selected Apple host driver evaluates a four-pow double-precision leakage
equation at a fixed 110 C.  Vinix's ARM64 kernel is built with no floating
point, so this tool evaluates the version-pinned equation off-line and emits
Q24.40 factors.  Runtime inputs remain the per-die fuse values and native
DeviceTree voltage/frequency tables.
"""

from __future__ import annotations

import argparse
import ctypes
import json
import math
from pathlib import Path
import struct

import recover_g17_abi


SCRIPT_DIR = Path(__file__).resolve().parent
DEFAULT_DRIVER = SCRIPT_DIR / "build/kext/g17c/AGXG17X.macho"
DEFAULT_DEVICE_TREE = SCRIPT_DIR / "build/live_macos.json"
DEFAULT_OUTPUT = (
    SCRIPT_DIR.parent.parent / "kernel/modules/gpu/agx/fw/g17_power_tables.v"
)
Q_BITS = 40
TEMPERATURE_C = 110.0


def f32(value: float) -> float:
    return struct.unpack("<f", struct.pack("<f", value))[0]


def f32_bits(value: float) -> int:
    return struct.unpack("<I", struct.pack("<f", f32(value)))[0]


def bits_f32(value: int) -> float:
    return struct.unpack("<f", struct.pack("<I", value))[0]


_libm = ctypes.CDLL(None)
_libm.powf.argtypes = [ctypes.c_float, ctypes.c_float]
_libm.powf.restype = ctypes.c_float


def powf(base: float, exponent: float) -> float:
    """Call the platform libm's float pow, matching Apple's producer."""

    return float(_libm.powf(ctypes.c_float(base), ctypes.c_float(exponent)))


def f32_mul(left: float, right: float) -> float:
    return f32(f32(left) * f32(right))


def voltage_f32(millivolts: int) -> float:
    # The producer performs UCVTF S followed by FDIV S with 1000.0f.
    return f32(f32(float(millivolts)) / f32(1000.0))


def leakage_factor(record: list[float], millivolts: int) -> float:
    """Evaluate applyLeakageEquation with its fused input factored out."""

    if len(record) != 11:
        raise ValueError("G17 leakage record no longer has 11 doubles")
    _threshold, c1, c2, c3, c4, c5, c6, c7, c8, c9, c10 = record
    voltage = float(voltage_f32(millivolts))
    temperature = TEMPERATURE_C
    delta = temperature - 105.0
    return (
        math.pow(2.0, delta / c1)
        * math.pow(
            min(voltage, c7) / min(c7, 0.75),
            c4 * (1.0 - c5 * delta / 20.0),
        )
        * (min(voltage, c7, c6) / min(c7, c6, 0.75))
        * math.pow(
            1.0 + c2 * (1.0 - c3 * delta / 20.0),
            (max(voltage, c6) - max(c6, 0.75)) / 0.05,
        )
        * math.pow(
            c9,
            c8
            * max(voltage - 1.06, 0.0)
            * (1.0 + c10 * delta * delta / (temperature + 273.15)),
        )
    )


def q40(value: float) -> int:
    encoded = round(value * (1 << Q_BITS))
    if encoded < 0 or encoded > 0xFFFF_FFFF_FFFF_FFFF:
        raise ValueError(f"Q24.40 value is out of range: {value}")
    return encoded


def q40_to_f32_bits(value: int) -> int:
    """Round a positive Q24.40 value to IEEE-754 binary32."""

    if value == 0:
        return 0
    position = value.bit_length() - 1
    exponent = position - Q_BITS
    if not -126 <= exponent <= 127:
        raise ValueError("Q24.40 value is outside the normal binary32 range")
    if position <= 23:
        significand = value << (23 - position)
    else:
        shift = position - 23
        significand = value >> shift
        remainder = value & ((1 << shift) - 1)
        halfway = 1 << (shift - 1)
        if remainder > halfway or (remainder == halfway and significand & 1):
            significand += 1
            if significand == 1 << 24:
                significand >>= 1
                exponent += 1
    return ((exponent + 127) << 23) | (significand & 0x7F_FFFF)


def f32_bits_to_q40(value: int) -> int:
    """Convert a positive normal binary32 value exactly to Q24.40."""

    if value == 0:
        return 0
    if value >> 31 or (value >> 23) & 0xFF in (0, 0xFF):
        raise ValueError("only positive normal binary32 values are supported")
    significand = (1 << 23) | (value & 0x7F_FFFF)
    shift = ((value >> 23) & 0xFF) - 110
    if shift >= 0:
        return significand << shift
    discarded = significand & ((1 << -shift) - 1)
    if discarded:
        raise ValueError("binary32 value is not exactly representable in Q24.40")
    return significand >> -shift


def q40_mul(left: int, right: int) -> int:
    return (left * right) >> Q_BITS


def f32_mul_bits(left: int, right: int) -> int:
    return q40_to_f32_bits(q40_mul(f32_bits_to_q40(left), f32_bits_to_q40(right)))


def f32_add_bits(left: int, right: int) -> int:
    return q40_to_f32_bits(f32_bits_to_q40(left) + f32_bits_to_q40(right))


def u32_to_f32_bits(value: int) -> int:
    return q40_to_f32_bits(value << Q_BITS) if value else 0


def f32_bits_to_u32_trunc(value: int) -> int:
    if value == 0:
        return 0
    exponent = ((value >> 23) & 0xFF) - 127
    significand = (1 << 23) | (value & 0x7F_FFFF)
    if exponent < 0:
        return 0
    if exponent >= 23:
        return significand << (exponent - 23)
    return significand >> (23 - exponent)


def leakage_bucket(records: list[list[float]], quarters: int) -> int:
    for index, record in enumerate(records):
        threshold = threshold_quarters(record)
        if threshold == 0xFFFF_FFFF or quarters < threshold:
            return index
    raise ValueError("leakage model has no catch-all bucket")


def fixed_leakage_q40(
    records: list[list[float]], quarters: int, millivolts: int
) -> int:
    record = records[leakage_bucket(records, quarters)]
    return q40(leakage_factor(record, millivolts)) * quarters // 4


def reference_afr_power(
    records: list[list[float]], quarters: int, millivolts: int, megahertz: int
) -> int:
    voltage = voltage_f32(millivolts)
    leakage = f32(quarters / 4.0) * leakage_factor(
        records[leakage_bucket(records, quarters)], millivolts
    )
    dynamic = f32_mul(f32_mul(powf(voltage, f32(1.0)), f32(12.29)), megahertz)
    return int(f32(min(leakage + dynamic, 24800.0) * voltage))


def fixed_afr_power(
    records: list[list[float]], quarters: int, millivolts: int, megahertz: int
) -> int:
    voltage = f32_bits(voltage_f32(millivolts))
    dynamic = f32_mul_bits(
        f32_mul_bits(voltage, f32_bits(12.29)), u32_to_f32_bits(megahertz)
    )
    total = fixed_leakage_q40(records, quarters, millivolts)
    total += f32_bits_to_q40(dynamic)
    total = min(total, 24800 << Q_BITS)
    scaled = q40_mul(total, f32_bits_to_q40(voltage))
    return f32_bits_to_u32_trunc(q40_to_f32_bits(scaled))


def reference_main_power(
    records: list[list[float]],
    quarters: int,
    millivolts: int,
    megahertz: int,
    enabled_units: int,
    afr_share: int,
) -> int:
    voltage = voltage_f32(millivolts)
    leakage = f32(quarters / 4.0) * leakage_factor(
        records[leakage_bucket(records, quarters)], millivolts
    )
    enabled_scale = f32(f32(float(enabled_units)) / f32(10.0))
    dynamic = f32_mul(
        f32_mul(
            f32_mul(powf(voltage, f32(1.28)), f32(20.15)), megahertz
        ),
        enabled_scale,
    )
    total = min(f32(leakage + dynamic), f32(48500.0))
    return int(f32(f32(total * voltage) + f32(float(afr_share))))


def fixed_main_power(
    records: list[list[float]],
    quarters: int,
    millivolts: int,
    megahertz: int,
    enabled_units: int,
    afr_share: int,
) -> int:
    voltage = f32_bits(voltage_f32(millivolts))
    coefficient = f32_bits(
        f32_mul(powf(bits_f32(voltage), f32(1.28)), f32(20.15))
    )
    dynamic = f32_mul_bits(coefficient, u32_to_f32_bits(megahertz))
    enabled_scale = q40_to_f32_bits((enabled_units << Q_BITS) // 10)
    dynamic = f32_mul_bits(dynamic, enabled_scale)
    total = fixed_leakage_q40(records, quarters, millivolts)
    total += f32_bits_to_q40(dynamic)
    total_bits = q40_to_f32_bits(total)
    total_bits = min(total_bits, f32_bits(48500.0))
    scaled = f32_mul_bits(total_bits, voltage)
    scaled = f32_add_bits(scaled, u32_to_f32_bits(afr_share))
    return f32_bits_to_u32_trunc(scaled)


def threshold_quarters(record: list[float]) -> int:
    threshold = record[0]
    if threshold < 0:
        return 0xFFFF_FFFF
    # Runtime fuse inputs are exact multiples of 0.25.  `q < ceil(4*t)` is
    # equivalent to Apple's double-precision `q/4 < t` comparison.
    return math.ceil(threshold * 4.0)


def recover_variant_records(driver: bytes) -> tuple[str, list[list[float]], list[list[float]]]:
    uuid = recover_g17_abi.macho_uuid(driver)
    if uuid != recover_g17_abi.DRIVER_UUID:
        raise ValueError(f"unsupported AGXG17X UUID {uuid}")
    power_code = recover_g17_abi.symbol_code(
        driver, recover_g17_abi.INIT_POWER_DATA
    )[1]
    recovered = recover_g17_abi.recover_g17_linear_power_transfer_tables(
        driver, power_code
    )
    model = recovered["leakage_model"]
    if model["temperature"] != TEMPERATURE_C:
        raise ValueError("G17 leakage-model temperature changed")
    return (
        uuid,
        model["vdd_gpu"]["variant_records"],
        model["afr"]["variant_records"],
    )


def device_voltages(path: Path) -> list[int]:
    """Return every millivolt value observed on this Mac17,6."""

    document = json.loads(path.read_text())
    tree = document["device_tree"]
    values: set[int] = set()
    for table in tree["perf_states"]:
        values.update(int(state["voltage_mv"]) for state in table)
    for domain in ("cs_perf_states", "afr_perf_states"):
        for table in tree[domain]["tables"]:
            values.update(int(state["voltage_uv"]) // 1000 for state in table)
    if not values or min(values) <= 0:
        raise ValueError("live DeviceTree contains no usable GPU voltages")
    return sorted(values)


def generated_source(
    uuid: str,
    voltages: list[int],
    vdd_records: list[list[float]],
    afr_records: list[list[float]],
) -> str:
    if len(vdd_records) != 8 or len(afr_records) != 8:
        raise ValueError("G17C variant leakage model no longer has eight buckets")

    voltage_bits = [f32_bits(voltage_f32(mv)) for mv in voltages]
    main_dynamic_bits = [
        f32_bits(f32_mul(powf(voltage_f32(mv), f32(1.28)), f32(20.15)))
        for mv in voltages
    ]
    vdd_factors = [
        q40(leakage_factor(record, mv))
        for record in vdd_records
        for mv in voltages
    ]
    afr_factors = [
        q40(leakage_factor(record, mv))
        for record in afr_records
        for mv in voltages
    ]

    # V infers fixed-array lengths from `[u32(...), ...]!`; keep the cast on
    # the first element rather than trying to spell a type inside `[`.
    def fixed_array(name: str, kind: str, values: list[int], width: int) -> str:
        per_line = 6 if width == 8 else 10
        lines = []
        for offset in range(0, len(values), per_line):
            chunk = values[offset : offset + per_line]
            tokens = []
            for index, value in enumerate(chunk):
                literal = f"0x{value:016x}" if width == 8 else f"0x{value:08x}"
                if offset == 0 and index == 0:
                    literal = f"{kind}({literal})"
                tokens.append(literal)
            lines.append("\t" + ", ".join(tokens) + ",")
        return f"const {name} = [\n" + "\n".join(lines) + "\n]!\n"

    source = """// Code generated by tools/agx-re/generate_g17_power_model.py; DO NOT EDIT.
// Source AGXG17X UUID: {uuid}
// Voltage set: the native Mac17,6 DeviceTree captured by inspect_macos.py.
// Factors are Q24.40 evaluations of applyLeakageEquation at 110 C.

module fw

pub const g17_power_model_q_bits = u32(40)
pub const g17_power_model_voltage_count = {voltage_count}
pub const g17_power_model_bucket_count = 8

{voltages}
{voltage_bits}
{main_dynamic_bits}
{vdd_thresholds}
{afr_thresholds}
{vdd_factors}
{afr_factors}
""".format(
        uuid=uuid,
        voltage_count=len(voltages),
        voltages=fixed_array("g17_power_model_voltages_mv", "u32", voltages, 4),
        voltage_bits=fixed_array(
            "g17_power_model_voltage_f32_bits", "u32", voltage_bits, 4
        ),
        main_dynamic_bits=fixed_array(
            "g17_power_model_main_dynamic_f32_bits", "u32", main_dynamic_bits, 4
        ),
        vdd_thresholds=fixed_array(
            "g17_power_model_vdd_threshold_quarters",
            "u32",
            [threshold_quarters(record) for record in vdd_records],
            4,
        ),
        afr_thresholds=fixed_array(
            "g17_power_model_afr_threshold_quarters",
            "u32",
            [threshold_quarters(record) for record in afr_records],
            4,
        ),
        vdd_factors=fixed_array(
            "g17_power_model_vdd_factor_q40", "u64", vdd_factors, 8
        ),
        afr_factors=fixed_array(
            "g17_power_model_afr_factor_q40", "u64", afr_factors, 8
        ),
    )
    return source.rstrip() + "\n"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--driver", type=Path, default=DEFAULT_DRIVER)
    parser.add_argument("--device-tree", type=Path, default=DEFAULT_DEVICE_TREE)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()

    driver = args.driver.read_bytes()
    uuid, vdd_records, afr_records = recover_variant_records(driver)
    source = generated_source(
        uuid, device_voltages(args.device_tree), vdd_records, afr_records
    )
    if args.check:
        if not args.output.exists() or args.output.read_text() != source:
            raise SystemExit(f"stale generated G17 power model: {args.output}")
    else:
        args.output.write_text(source)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
