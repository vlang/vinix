import json
import struct
from pathlib import Path
import unittest
from unittest import mock

import recover_g17_abi


def movz(register: int, immediate: int, shift: int = 0) -> int:
    return 0xD2800000 | (shift // 16) << 21 | immediate << 5 | register


def movk(register: int, immediate: int, shift: int) -> int:
    return 0xF2800000 | (shift // 16) << 21 | immediate << 5 | register


def add_immediate(destination: int, source: int, immediate: int) -> int:
    return 0x91000000 | immediate << 10 | source << 5 | destination


def bl(source: int, target: int) -> int:
    return 0x94000000 | (((target - source) // 4) & 0x03FFFFFF)


def b(source: int, target: int) -> int:
    return 0x14000000 | (((target - source) // 4) & 0x03FFFFFF)


def b_cond(source: int, target: int, condition: int) -> int:
    return (
        0x54000000
        | (((target - source) // 4) & 0x7FFFF) << 5
        | condition
    )


def tbz(source: int, target: int, register: int, bit: int) -> int:
    return (
        0x36000000
        | (bit >> 5) << 31
        | (bit & 0x1F) << 19
        | (((target - source) // 4) & 0x3FFF) << 5
        | register
    )


def cbz(
    source: int,
    target: int,
    register: int,
    *,
    nonzero: bool = False,
    width: int = 8,
) -> int:
    return (
        0x34000000
        | (width == 8) << 31
        | nonzero << 24
        | (((target - source) // 4) & 0x7FFFF) << 5
        | register
    )


def adrp(source: int, target: int, register: int) -> int:
    pages = ((target & ~0xFFF) - (source & ~0xFFF)) >> 12
    immediate = pages & 0x1FFFFF
    return (
        0x90000000
        | (immediate & 3) << 29
        | ((immediate >> 2) & 0x7FFFF) << 5
        | register
    )


def ldp_x(first: int, second: int, base: int, immediate: int) -> int:
    return (
        0xA9400000
        | ((immediate // 8) & 0x7F) << 15
        | second << 10
        | base << 5
        | first
    )


def ldrb(destination: int, base: int, immediate: int) -> int:
    return 0x39400000 | immediate << 10 | base << 5 | destination


def stp_x(first: int, second: int, base: int, immediate: int) -> int:
    return (
        0xA9000000
        | ((immediate // 8) & 0x7F) << 15
        | second << 10
        | base << 5
        | first
    )


def str_x(source: int, base: int, immediate: int) -> int:
    return 0xF9000000 | (immediate // 8) << 10 | base << 5 | source


def ldr_w(destination: int, base: int, immediate: int) -> int:
    return 0xB9400000 | (immediate // 4) << 10 | base << 5 | destination


def ldr_x(destination: int, base: int, immediate: int) -> int:
    return 0xF9400000 | (immediate // 8) << 10 | base << 5 | destination


def ldr_q(destination: int, base: int, immediate: int) -> int:
    return 0x3DC00000 | (immediate // 16) << 10 | base << 5 | destination


def ldrb_register(destination: int, base: int, offset: int) -> int:
    return 0x38606800 | offset << 16 | base << 5 | destination


def add_register(destination: int, first: int, second: int) -> int:
    return 0x8B000000 | second << 16 | first << 5 | destination


def cmp_w_immediate(source: int, immediate: int) -> int:
    return 0x7100001F | immediate << 10 | source << 5


def movz_w(register: int, immediate: int) -> int:
    return 0x52800000 | immediate << 5 | register


def umaddl(destination: int, first: int, second: int, addend: int = 31) -> int:
    return 0x9BA00000 | second << 16 | addend << 10 | first << 5 | destination


def bfi_x(destination: int, source: int, lsb: int, width: int) -> int:
    immr = (-lsb) & 0x3F
    imms = width - 1
    return 0xB3400000 | immr << 16 | imms << 10 | source << 5 | destination


def ubfiz_x(destination: int, source: int, lsb: int, width: int) -> int:
    immr = (-lsb) & 0x3F
    imms = width - 1
    return 0xD3400000 | immr << 16 | imms << 10 | source << 5 | destination


def str_unsigned(source: int, base: int, immediate: int, width: int) -> int:
    opcode = {1: 0x39000000, 2: 0x79000000, 4: 0xB9000000, 8: 0xF9000000}[width]
    return opcode | (immediate // width) << 10 | base << 5 | source


def stur_x(source: int, base: int, immediate: int) -> int:
    return 0xF8000000 | (immediate & 0x1FF) << 12 | base << 5 | source


def pair_q(kind: str, first: int, second: int, base: int, immediate: int) -> int:
    opcode = {"load": 0xAD400000, "store": 0xAD000000}[kind]
    return (
        opcode
        | ((immediate // 16) & 0x7F) << 15
        | second << 10
        | base << 5
        | first
    )


def encode(*instructions: int) -> bytes:
    return struct.pack(f"<{len(instructions)}I", *instructions)


def magic(register: int) -> tuple[int, ...]:
    value = recover_g17_abi.INTERFACE_MAGIC
    return (
        movz(register, value & 0xFFFF),
        movk(register, (value >> 16) & 0xFFFF, 16),
        movk(register, (value >> 32) & 0xFFFF, 32),
        movk(register, (value >> 48) & 0xFFFF, 48),
    )


def driver_root_code() -> bytes:
    bindings = (
        (0xAB8, 0x18),
        (0x388, 0x20),
        (0xAD0, 0xA8),
        (0xBE8, 0x18),
        (0x388, 0x20),
        (0xC00, 0xA8),
        (0xCE0, 0xB0),
        (0xCE8, 0xB8),
        (0x398, 0xC0),
    )
    platform_copy = (
        0xF9414E68,
        0x52952917,
        0x72A00037,
        0x8B170108,
        0xF9400108,
        0x3CC18100,
        0x3CC28101,
        0x3CC38102,
        0xAD020A81,
        0x3D800E80,
        0x3CC48100,
        0x3CC58101,
        0x3CC68102,
        0xF9403D08,
        0xF9004A88,
        0xAD038A81,
        0x3D801A80,
    )
    bootstrap_publication = (
        0xF94D2E60,
        0xAA0003F1,
        0xF9400010,
        0xF2F9B431,
        0xDAC11A30,
        0xAA1003F1,
        0xDAC147F1,
        0xEB11021F,
        0x54000040,
        0xD4388E40,
        0x91056208,
        0xF940AE09,
        0xAA0803F1,
        0xF2E63531,
        0xD73F0931,
        0xAA0003E1,
        0xAA1603F1,
        0xF9400270,
        0xDAC11A30,
        0xAA1003F1,
        0xDAC147F1,
        0xEB11021F,
        0x54000040,
        0xD4388E40,
        0x910B6208,
        0xF9416E09,
        0xAA1303E0,
        0x52800002,
        0xAA0803F1,
        0xF2F24A11,
        0xD73F0931,
        0xF9000680,
    )
    return encode(
        *magic(21),
        *bootstrap_publication,
        *bootstrap_publication,
        *platform_copy,
        0xFD001680,
        0x0F000420,
        0xFD001680,
        *sum(
            ((ldr_x(1, 19, member), str_x(0, 20, offset)) for member, offset in bindings),
            (),
        ),
    )


def firmware_shared_allocations() -> list[dict[str, int]]:
    sizes = {
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
        0xAD0: 0x20,
        0xBF0: 0x79800,
        0xC00: 0x20,
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
    return [
        {
            "host_cpu_member": member - 8,
            "host_gpu_member": member,
            "bytes": size,
        }
        for member, size in sizes.items()
    ]


def firmware_shared_code() -> bytes:
    def direct(source: int, target: int, offset: int) -> tuple[int, ...]:
        return (ldr_x(1, 19, source), ldr_x(8, 19, target), str_x(0, 8, offset))

    return encode(
        ldr_x(21, 0, 0xA98),
        add_immediate(22, 21, 0x254),
        ldr_x(1, 0, 0x308),
        str_x(0, 22, 0),
        *sum(
            (
                (ldr_x(1, 19, source), str_x(0, 22, offset - 0x254))
                for source, offset in (
                    (0x310, 0x25C),
                    (0x318, 0x264),
                    (0x328, 0x26C),
                    (0x330, 0x274),
                )
            ),
            (),
        ),
        *direct(0x340, 0xA98, 0x10),
        *direct(0x338, 0xA98, 0x08),
        *direct(0x300, 0xA98, 0x00),
        *direct(0xAC0, 0xA98, 0x200),
        0xF9414E68,
        0x529EEA89,
        0x8B090109,
        0xB9400129,
        0x91404D08,
        0x911DA108,
        0xF9400101,
        0xF9016AA0,
        ldr_x(21, 19, 0xBC8),
        ldr_x(1, 19, 0x320),
        add_immediate(8, 21, 0x471),
        str_x(0, 8, 0),
        *direct(0x340, 0xBC8, 0x10),
        *direct(0x338, 0xBC8, 0x08),
        *direct(0x300, 0xBC8, 0x00),
        *direct(0xBF0, 0xBC8, 0x200),
    )


def auxiliary_shared_code() -> bytes:
    return encode(
        *sum(
            (
                (ldr_x(1, 19, source), ldr_x(8, 19, target), str_x(0, 8, index * 8))
                for target, sources in (
                    (0xAA8, (0xB40, 0xB60, 0xB48, 0xB68, 0xB50, 0xB70, 0xB58, 0xB78)),
                    (0xBD8, (0xC70, 0xC90, 0xC78, 0xC98, 0xC80, 0xCA0, 0xC88, 0xCA8)),
                )
                for index, source in enumerate(sources)
            ),
            (),
        )
    )


def firmware_shared_platform_code() -> bytes:
    return encode(
        0xF9454E75,
        0x91404408,
        0x91158108,
        0xF9400108,
        0xF9016EA0,
        0xF9016EBF,
        0xD2800000,
        0xF90172A0,
        0x91404408,
        0x9115A108,
        0xF9400108,
        0xF90176A0,
        0xF90176BF,
        0xD2800000,
        0xF9017AA0,
        0xF9017EBF,
        0xF945E669,
        0xF9416EAA,
        0xF9016D2A,
        0xF9017528,
        0xF9017D3F,
        0x91403D09,
        0xB947C12A,
        0xF945E66B,
        0xB903016A,
        0xB9483529,
        0xB90306A9,
        0xF9454E69,
        0x9111E529,
        0x3DFDE500,
        0x3D800120,
        0xF9414E68,
        0xF945E669,
        0x9111E529,
        0x3DFDE500,
        0x3D800120,
        0x52801FE8,
        0x390F82A8,
        0x910F86A8,
        0x6F00E400,
        0xAD000100,
        0xAD010100,
        0xAD020100,
        0xAD030100,
        0x3D802100,
    )


def bootstrap_region_code() -> tuple[bytes, bytes, bytes, bytes, bytes, bytes]:
    allocation = encode(
        0x52800029,
        0x1AC0212A,
        0x113FFD4B,
        0x4B0A03EA,
        0x0A0A0161,
        0x1AC82128,
        0x93407D02,
        0x52800260,
        0xF90D2A60,
        0xB4005BA0,
        0xAA1303E0,
        0xAA1403E1,
        0x52800002,
        0x52800103,
        0x97FF8F6B,
        0xF90D2E60,
    )
    prepare = encode(
        0xAA0003F3,
        0xB91AC01F,
        0xD2815111,
        0x8B110210,
        0xF9400208,
        0x52800021,
        0xB95AC268,
        0x8B080009,
        0xB900113F,
        0xA9007D3F,
        0x11006108,
        0xB91AC268,
    )
    page_shift = encode(0xD503245F, 0x528001C0, 0xD65F03C0)
    set_64_pa = encode(
        0x5280006A,
        0x2901A933,
        0xF9000135,
        0xB9000936,
        0x11006108,
        0xB91AC288,
    )
    set_64 = encode(
        0xB9000935,
        0xF9000134,
        0xF0FF3E2A,
        0xFD43C540,
        0xFC00C120,
        0x11006108,
        0xB91AC268,
    )
    set_32 = encode(
        0xB9000934,
        0xF9000135,
        0xF0FF3E2A,
        0xFD43F140,
        0xFC00C120,
        0x11006108,
        0xB91AC268,
    )
    return allocation, prepare, page_shift, set_64_pa, set_64, set_32


def bootstrap_roots_code() -> tuple[bytes, bytes, bytes, bytes, bytes]:
    size_calculation_tail = (
        0x1AC82308,
        0x1AC02329,
        0x4B0803EA,
        0x4B080129,
        0x0A290141,
        0x93407D02,
        0x52800260,
    )
    first_size_calculation = (
        0xB94002E8,
        0x52800038,
        size_calculation_tail[0],
        0x12800019,
        *size_calculation_tail[1:],
    )
    repeated_size_calculation = (0xB94002E8, *size_calculation_tail)
    cpu_mapping_prefix = (
        0xD2804511,
        0x8B110210,
        0xF9400208,
        0x52800001,
        0xF2E7DAD0,
        0xD73F0910,
    )
    mapping_tail = (
        0xB4000000,
        0xAA1303E0,
        0xAA1403E1,
        0x52800002,
        0x52800103,
        0x94000000,
    )
    allocation = encode(
        *first_size_calculation,
        *cpu_mapping_prefix,
        str_x(0, 19, 0x19E0),
        *mapping_tail,
        str_x(0, 19, 0x19E8),
        *repeated_size_calculation,
        *cpu_mapping_prefix,
        str_x(0, 19, 0x1A18),
        *mapping_tail,
        str_x(0, 19, 0x1A20),
    )
    cpu_address = (0x9104E208, 0xF9409E09)
    init = encode(
        ldr_x(0, 19, 0x19E0),
        *cpu_address,
        ldr_x(0, 19, 0x1A18),
        *cpu_address,
    )
    prepare = encode(
        ldr_x(0, 19, 0x19E8),
        0x94000000,
        ldr_x(0, 19, 0x1A20),
        0x94000000,
    )
    complete = prepare
    page_shift = encode(0xD503245F, 0x528001C0, 0xD65F03C0)
    return allocation, init, prepare, complete, page_shift


def small_shared_data_code() -> tuple[bytes, bytes, bytes, bytes, bytes, bytes, bytes, bytes]:
    shared_init = encode(
        0xB94B8E68,
        0xF9456669,
        0xB9000128,
        0xB94CBE68,
        0xF945FE69,
        0xB9000128,
    )
    base_init = encode(
        0x52800036,
        0xF945666B,
        0xB9000576,
        0xF945FE6B,
        0xB9000576,
    )
    ktrace = encode(
        0x52802608,
        0x9BA80068,
        0x52800029,
        0x392E1109,
        0xB94B8909,
        0xB90B8D09,
        0xF9456508,
        0xB9000109,
    )
    wait_power_off = encode(
        0xF9456408,
        0xB9401108,
        0xF945FE68,
        0xB9401108,
    )
    wait_generation = encode(
        0xF9456408,
        0xB9401D08,
        0xF945FE68,
        0xB9401D08,
    )
    snapshot_generation = encode(
        0xF9456408,
        0xB9401D08,
        0xF945FC08,
        0xB9401D08,
    )
    get_sleep = encode(
        0xF9456408,
        0xB9400908,
        0xF945FC09,
        0xB9400929,
    )
    set_sleep = encode(
        0xF9456408,
        0x52800029,
        0xB9000909,
        0xF945FC08,
        0xB9000909,
    )
    return (
        shared_init,
        base_init,
        ktrace,
        wait_power_off,
        wait_generation,
        snapshot_generation,
        get_sleep,
        set_sleep,
    )


def runtime_control_code() -> dict[str, bytes]:
    result = {}
    strided = {
        "fw_util_debounce_periods",
        "fw_util_pstate_threshold",
        "fw_util_pstate_step_size",
    }
    for field_name, (symbol, accesses) in recover_g17_abi.G17_RUNTIME_ACCESSORS.items():
        runtime_register = 9 if field_name in strided else 8
        instructions = [ldr_x(runtime_register, 0, 0x380)]
        if field_name in strided:
            instructions.extend((0x528000CC, 0x9240042D, 0x9BAC25A9))
        instructions.extend(
            str_unsigned(1, runtime_register, offset, width)
            for offset, width in accesses
        )
        result[symbol] = encode(*instructions)
    result[recover_g17_abi.G17_ADD_REGISTER_OVERRIDE] = encode(
        0x8B0A054A,
        0xD37DF14A,
        0x8B0A012B,
        0xB9081561,
        0x91201129,
        0xF9000182,
        0x91203169,
        0xF9000123,
        0xF941C108,
        0xB9498509,
        0x11000529,
        0xB9098509,
    )
    return result


def runtime_initialization_code() -> tuple[bytes, bytes, bytes, bytes]:
    base_init = encode(
        0xB900010C,
        0xB900051F,
        0xB900091F,
        0xB900191F,
        0xB9001D1F,
        0xF941C268,
        0xB805E100,
        0xB845E11F,
        0xF941C26A,
        0xB8062149,
        0xB9400109,
        0xB9002149,
        0xF941C26A,
        0xB900495F,
        0xF941C268,
        0x52839029,
        0x8B090109,
        0x5280002A,
        0xB900012A,
        0x528390A9,
        0x8B090109,
        0xB900013F,
        0x52839129,
        0x8B090109,
        0xB900013F,
        0x528391A9,
        0x8B090108,
        0xB900011F,
    )
    arm_init = encode(
        0xF941C269,
        0xB909C93F,
        0xF941C268,
        0xB805A11F,
        0xF941C269,
        0xB900153F,
        0xF9414E68,
        0x9140390A,
        0x794ED10B,
        0x7900A92B,
        0x794ED50B,
        0x7900AD2B,
        0x794ED90B,
        0x7900B12B,
        0xF9466A6B,
        0x5298E50C,
        0x8B0C016B,
        0xB900017F,
        0xB900513F,
        0xB9004D3F,
        0xB940016C,
        0x3400008C,
        0xB940017F,
        0xB940513F,
        0xB9404D3F,
        0xB909E13F,
        0xBD495140,
        0xBD07CD20,
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
        0xBD07E520,
        0xBD496D40,
        0x7E21D800,
        0x1E39000B,
        0xB907E92B,
        0xB949494B,
        0xB907C52B,
        0xBD494D40,
        0xBD07C920,
        0x6F00E400,
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
        0xB806A149,
        0x5283882C,
        0x8B0C014C,
        0xB9000189,
        0x528388A9,
        0x8B090149,
        0xFD000120,
        0x528389A9,
        0x8B090149,
        0xB900013F,
        0xB925B93F,
        0xB900411F,
        0xB900451F,
        0xF941C269,
        0xB91C2D28,
    )
    base_power = encode(
        0xF941C269,
        0x91281128,
        0xB900312B,
        0xB947014B,
        0xB9002D2B,
        0xB946FD4A,
        0x3400006A,
        0xB900952A,
        0xB900AD2A,
        0x6F00E400,
        0xAD000100,
        0xF900111F,
    )
    arm_power = encode(
        0xF941C008,
        0x5284F909,
        0x8B090009,
        0xAD410121,
        0xAD400D22,
        0x3C8B4103,
        0x3C8C4101,
        0x3C8D4100,
        0x3C8A4102,
        0xF941C268,
        0x9104B109,
        0xB940628A,
        0xB900ED0A,
        0xB940668A,
        0xB900F10A,
        0x914046AA,
        0x9107814A,
        0x9112D10B,
        0x5280080C,
        0xF940014D,
        0xD109216E,
        0xF90001CD,
        0xF941254D,
        0xF800856D,
        0x9100214A,
        0xF100058C,
        0x54FFFF21,
        0xF943168A,
        0xF902C52A,
        0xF9431A8A,
        0xF902C92A,
        0xF943968A,
        0xF903452A,
        0xF9439A8A,
        0xF903492A,
        0xF941C268,
        0xB9009D1F,
        0xB900A11F,
    )
    return base_init, arm_init, base_power, arm_power


def runtime_power_policy_code() -> tuple[bytes, bytes]:
    arm_power = encode(
        0xF9416E75,
        0x914046B4,
        0xF9414E60,
        0x91360208,
        0xF946C209,
        0x914046AA,
        0x91017141,
    )
    populate = encode(0xD503245F, 0xAA0103E0, 0x5280DC01, 0x14000000)
    return arm_power, populate


def runtime_performance_policy_code() -> tuple[bytes, bytes]:
    setup = encode(
        0x911FA708,
        0x911FC709,
        0x911F870A,
        0xB900011F,
        0xB900013F,
        0xB900015F,
        0x391FEB1F,
        0x391FF31F,
        0x391FFB1F,
        0x911FB708,
        0xB900011F,
        0x911FD708,
        0xB900011F,
        0x911F9708,
        0xB900011F,
        0x391FEF1F,
        0x391FF71F,
        0x391FFF1F,
        0x391FE71F,
        0x3920031F,
        0xB927CA7F,
        0xB927D27F,
        0xB927D67F,
        0x391F831F,
        0xB927DA7F,
        0xB927CE7F,
        0xB927DE7F,
    )
    arm_power = encode(
        0xF941C008,
        0x5284F909,
        0x8B090009,
        0xAD410121,
        0xAD400D22,
        0x3C8B4103,
        0x3C8C4101,
        0x3C8D4100,
        0x3C8A4102,
    )
    return setup, arm_power


def runtime_platform_policy_code() -> tuple[
    dict[str, int], dict[str, tuple[int, bytes]]
]:
    addresses = {
        recover_g17_abi.BASE_CONFIGURE_DEVICE: 0x100000,
        recover_g17_abi.PI300_CONFIGURE_DEVICE: 0x101000,
        recover_g17_abi.G17_CONFIGURE_DEVICE: 0x102000,
        recover_g17_abi.BASE_CONFIGURE_POWER: 0x103000,
        recover_g17_abi.G17_CONFIGURE_POWER: 0x104000,
    }

    def code_with(size: int, inserts: dict[int, tuple[int, ...]]) -> bytes:
        result = bytearray(size)
        for offset, values in inserts.items():
            struct.pack_into(f"<{len(values)}I", result, offset, *values)
        return bytes(result)

    base_device = addresses[recover_g17_abi.BASE_CONFIGURE_DEVICE]
    pi_device = addresses[recover_g17_abi.PI300_CONFIGURE_DEVICE]
    g17_device = addresses[recover_g17_abi.G17_CONFIGURE_DEVICE]
    base_power = addresses[recover_g17_abi.BASE_CONFIGURE_POWER]
    g17_power = addresses[recover_g17_abi.G17_CONFIGURE_POWER]
    pi_platform_sequence = (
        0xF0FF3DC8,
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
        0xFD03B660,
    )
    base_smart_idle_sequence = (
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
    )
    g17_smart_idle_sequence = (
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
    )
    functions = {
        recover_g17_abi.BASE_CONFIGURE_DEVICE: (base_device, bytes(4)),
        recover_g17_abi.PI300_CONFIGURE_DEVICE: (
            pi_device,
            code_with(
                0x100,
                {
                    0x48: (bl(pi_device + 0x48, base_device),),
                    0xBC: pi_platform_sequence,
                },
            ),
        ),
        recover_g17_abi.G17_CONFIGURE_DEVICE: (
            g17_device,
            code_with(
                0x74, {0x70: (bl(g17_device + 0x70, pi_device),)}
            ),
        ),
        recover_g17_abi.BASE_CONFIGURE_POWER: (
            base_power, code_with(0x3AC, {0x384: base_smart_idle_sequence})
        ),
        recover_g17_abi.G17_CONFIGURE_POWER: (
            g17_power,
            code_with(
                0x184,
                {
                    0x20: (bl(g17_power + 0x20, base_power),),
                    0x114: g17_smart_idle_sequence,
                },
            ),
        ),
    }
    return addresses, functions


def zero_initialized_allocations_code() -> bytes:
    return encode(
        0xF9417268,
        0xF900311F,
        0x6F00E400,
        0xAD020100,
        0xAD010100,
        0xAD000100,
        0xF9417660,
        0x52810001,
        0x94AA5CC1,
        0xF9417E68,
        0xF900411F,
        0x6F00E400,
        0xAD030100,
        0xAD020100,
        0xAD010100,
        0xAD000100,
    )


def role0_bootstrap_regions_code() -> bytes:
    return encode(
        0xF9416260,
        0x52818301,
        0x94AA5EB6,
        0xF9416660,
        0x52820901,
        0x94AA5EB3,
        0xF9416A60,
        0x5281C201,
        0x94AA5EB0,
        0xF9416668,
        0x12800009,
        0xB90A1909,
        0xB90A3109,
    )


def g17_pio_mapping_fixture() -> tuple[
    bytes, dict[str, int], dict[str, tuple[int, bytes]]
]:
    table = (
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
    image = b"".join(struct.pack("<8I", *entry) for entry in table)
    symbols = {
        recover_g17_abi.BASE_CONFIGURE_DEVICE: 0x100000,
        recover_g17_abi.G17_PIO_TABLE: 0x2000,
        recover_g17_abi.G17_PIO_TABLE_LENGTH: 0x2100,
    }
    configure = bytearray(0x1904)
    words_at = {
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
    }
    for offset, word in words_at.items():
        struct.pack_into("<I", configure, offset, word)
    functions = {
        recover_g17_abi.BASE_CONFIGURE_DEVICE: (0x100000, bytes(configure)),
        recover_g17_abi.G17_PIO_TABLE: (
            0x2000,
            encode(
                0xD503245F,
                0x90000000,
                add_immediate(0, 0, 0x480),
                0xD65F03C0,
            ),
        ),
        recover_g17_abi.G17_PIO_TABLE_LENGTH: (
            0x2100, encode(0xD503245F, movz_w(0, 0x13), 0xD65F03C0)
        ),
    }
    return image, symbols, functions


def g17_pio_uat_fixture() -> tuple[
    bytes, dict[str, int], dict[str, tuple[int, bytes]]
]:
    addresses = {
        recover_g17_abi.ACCELERATOR_START: 0xFFFFFE0008907C1C,
        recover_g17_abi.INIT_FIRMWARE_DATA: 0xFFFFFE000896CA9C,
        recover_g17_abi.CREATE_FW_PIO_MAPPING: 0xFFFFFE0008951F7C,
        recover_g17_abi.CREATE_FW_GPU_MAPPING: 0xFFFFFE0008952154,
        recover_g17_abi.GART_RANGES: 0xFFFFFE000713D760,
    }

    start = bytearray(0xEE4)
    for offset, word in {
        0xEA0: 0x5293F018,
        0xEA4: 0xB0FF41B9,
        0xEA8: 0x911D8339,
        0xECC: 0x8B081728,
        0xED8: 0xA9402909,
        0xEDC: 0x9ADC2536,
        0xEE0: 0x9ADC2549,
    }.items():
        struct.pack_into("<I", start, offset, word)

    pio = bytearray(0xB8)
    for offset, word in {
        0x30: 0x710004BF,
        0x38: 0xF9400028,
        0x50: 0x0A2A010A,
        0x54: 0xB900006A,
        0x6C: 0x8A0A0100,
        0x74: 0x8B224108,
        0x84: 0x8A090108,
        0x88: 0xCB000101,
        0x8C: 0x7100029F,
        0x90: 0x52800068,
        0x94: 0x1A9F1502,
        0xA4: 0xAA1503E0,
        0xA8: 0xAA1603E1,
        0xAC: 0xAA1403E2,
        0xB0: 0xAA1303E3,
        0xB4: 0x94000049,
    }.items():
        struct.pack_into("<I", pio, offset, word)

    gpu = bytearray(0x94)
    for offset, word in {
        0x38: 0xD3607EC8,
        0x3C: 0x710026DF,
        0x48: 0x710002BF,
        0x4C: 0x528000E9,
        0x50: 0xD28000AA,
        0x54: 0xF2C0200A,
        0x58: 0x9A8A1129,
        0x90: 0xAA080122,
    }.items():
        struct.pack_into("<I", gpu, offset, word)

    publication = (
        0x928108F5,
        0x52835917,
        0x52838E18,
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
    )
    conversion = (
        0x8B170268,
        0xF9400100,
        0xF9400010,
        0xAA0003F1,
        0xF2F9B431,
        0xDAC11A30,
        0xD2802B11,
        0x8B110210,
        0xF9400208,
        0xF2E63530,
        0xD73F0910,
        0xAA1603F1,
        0x8B180268,
        0xB9400108,
        0xF9400270,
        0xDAC11A30,
        0xAA1003F1,
        0xDAC147F1,
        0xEB11021F,
        0x54000040,
        0xD4388E40,
        0x910B6209,
        0xF9416E0A,
        0x8B080001,
        0xAA1303E0,
        0x52800002,
        0xAA0903F1,
        0xF2F24A11,
        0xD73F0951,
        0xF9415E68,
        0x8B150108,
        0xF9074900,
    )
    functions = {
        recover_g17_abi.ACCELERATOR_START: (
            addresses[recover_g17_abi.ACCELERATOR_START],
            bytes(start),
        ),
        recover_g17_abi.INIT_FIRMWARE_DATA: (
            addresses[recover_g17_abi.INIT_FIRMWARE_DATA],
            encode(*publication, *conversion),
        ),
        recover_g17_abi.CREATE_FW_PIO_MAPPING: (
            addresses[recover_g17_abi.CREATE_FW_PIO_MAPPING],
            bytes(pio),
        ),
        recover_g17_abi.CREATE_FW_GPU_MAPPING: (
            addresses[recover_g17_abi.CREATE_FW_GPU_MAPPING],
            bytes(gpu),
        ),
    }
    image = struct.pack("<4Q", 0xFFFFFC2180000000, 0x01400000, 0x18, 0)
    return image, addresses, functions


class RecoverG17AbiTests(unittest.TestCase):
    def test_decodes_kernel_authenticated_rebase(self) -> None:
        raw = 0x80114229019894A8
        self.assertEqual(
            recover_g17_abi.decode_kernel_auth_rebase(raw),
            0xFFFFFE000898D4A8,
        )
        with self.assertRaisesRegex(ValueError, "not an authenticated"):
            recover_g17_abi.decode_kernel_auth_rebase(0x019894A8)

    def test_recovers_bootstrap_region(self) -> None:
        recovered = recover_g17_abi.recover_g17_bootstrap_region(
            *bootstrap_region_code()
        )
        self.assertEqual(recovered["bytes"], 0x4000)
        self.assertEqual(recovered["host_gpu_mapping_member"], 0x1A58)
        self.assertEqual(recovered["entry"]["bytes"], 0x18)
        self.assertEqual(recovered["entry"]["kinds"]["terminator"], 0)
        self.assertEqual(recovered["entry"]["kinds"]["write_64"], 2)
        self.assertEqual(recovered["terminator"]["zeroed_bytes"], 0x14)

    def test_rejects_incomplete_bootstrap_region(self) -> None:
        allocation, _prepare, page_shift, set_64_pa, set_64, set_32 = (
            bootstrap_region_code()
        )
        with self.assertRaisesRegex(ValueError, "cursor reset"):
            recover_g17_abi.recover_g17_bootstrap_region(
                allocation, b"", page_shift, set_64_pa, set_64, set_32
            )

    def test_recovers_bootstrap_root_mappings(self) -> None:
        recovered = recover_g17_abi.recover_g17_bootstrap_roots(
            *bootstrap_roots_code()
        )
        self.assertEqual(recovered["bytes"], 0x4000)
        self.assertEqual(recovered["firmware_page_shift"], 14)
        self.assertEqual(recovered["memory_options"], 0x13)
        self.assertEqual(
            recovered["roles"][0]["host_cpu_mapping_member"], 0x19E0
        )
        self.assertEqual(
            recovered["roles"][1]["host_gpu_mapping_member"], 0x1A20
        )

    def test_rejects_incomplete_bootstrap_root_mappings(self) -> None:
        _allocation, init, prepare, complete, page_shift = bootstrap_roots_code()
        with self.assertRaisesRegex(ValueError, "two G17 bootstrap-root"):
            recover_g17_abi.recover_g17_bootstrap_roots(
                b"", init, prepare, complete, page_shift
            )

    def test_recovers_small_shared_data(self) -> None:
        recovered = recover_g17_abi.recover_g17_small_shared_data(
            firmware_shared_allocations(), *small_shared_data_code()
        )
        self.assertEqual(recovered["bytes"], 0x20)
        self.assertEqual(recovered["roles"][0]["host_gpu_member"], 0xAD0)
        self.assertEqual(recovered["roles"][1]["trace_state_host_member"], 0xCBC)
        self.assertEqual(recovered["fields"][1]["initial"], 1)
        self.assertEqual(recovered["fields"][-1]["offset"], 0x1C)

    def test_rejects_incomplete_small_shared_data(self) -> None:
        codes = small_shared_data_code()
        with self.assertRaisesRegex(ValueError, "sleep-notification publication"):
            recover_g17_abi.recover_g17_small_shared_data(
                firmware_shared_allocations(), *codes[:-1], b""
            )

    def test_recovers_runtime_controls(self) -> None:
        allocations = firmware_shared_allocations() + [
            {"host_cpu_member": 0x380, "host_gpu_member": 0x388, "bytes": 0x1CA0}
        ]
        recovered = recover_g17_abi.recover_g17_runtime_controls(
            allocations, runtime_control_code()
        )
        self.assertEqual(recovered["bytes"], 0x1CA0)
        self.assertEqual(recovered["host_gpu_member"], 0x388)
        fields = {item["name"]: item for item in recovered["fields"]}
        self.assertEqual(
            fields["progress_check_interval_3d"]["stores"][0]["offset"], 0x99C
        )
        self.assertEqual(
            fields["gpu_keepalive_off_mode_threshold"]["stores"][0]["offset"],
            0x1C3C,
        )
        self.assertEqual(recovered["register_overrides"]["entries"], 16)
        self.assertEqual(recovered["register_overrides"]["stride"], 0x18)
        self.assertEqual(recovered["fw_util_pstate_controls"]["entries"], 4)
        self.assertEqual(recovered["fw_util_pstate_controls"]["stride"], 6)

    def test_rejects_incomplete_runtime_controls(self) -> None:
        allocations = firmware_shared_allocations() + [
            {"host_cpu_member": 0x380, "host_gpu_member": 0x388, "bytes": 0x1CA0}
        ]
        accessors = runtime_control_code()
        missing = recover_g17_abi.G17_RUNTIME_ACCESSORS[
            "gpu_keepalive_override"
        ][0]
        del accessors[missing]
        with self.assertRaisesRegex(ValueError, "missing G17 runtime accessor"):
            recover_g17_abi.recover_g17_runtime_controls(allocations, accessors)

    def test_recovers_runtime_initialization(self) -> None:
        allocations = firmware_shared_allocations() + [
            {"host_cpu_member": 0x380, "host_gpu_member": 0x388, "bytes": 0x1CA0}
        ]
        recovered = recover_g17_abi.recover_g17_runtime_initialization(
            allocations, *runtime_initialization_code()
        )
        self.assertEqual(recovered["bytes"], 0x1CA0)
        self.assertEqual(recovered["host_cpu_member"], 0x380)
        self.assertEqual(
            recovered["platform_copies"][2],
            {
                "destination_offset": 0xEC,
                "bytes": 0x6D8,
                "source": "power_controller_snapshot",
                "complete_destination_range": True,
            },
        )
        self.assertEqual(
            [item["destination_offset"] for item in recovered["power_controller_tables"]],
            [0x26C, 0x4B4],
        )
        initialized = {
            (item["offset"], item["bytes"]): item["value"]
            for item in recovered["zero_initialized"]
        }
        self.assertEqual(initialized[(0xA04, 0x28)], 0)
        self.assertEqual(initialized[(0x1C81, 4)], 1)
        dynamic = {item["offset"]: item for item in recovered["dynamic_fields"]}
        self.assertEqual(dynamic[0x1C41]["source"], "normalized_role_count")
        self.assertEqual(
            recovered["platform_copies"][3]["source"], "accelerator+0xe948"
        )

    def test_rejects_incomplete_runtime_initialization(self) -> None:
        allocations = firmware_shared_allocations() + [
            {"host_cpu_member": 0x380, "host_gpu_member": 0x388, "bytes": 0x1CA0}
        ]
        base_init, arm_init, base_power, _arm_power = runtime_initialization_code()
        with self.assertRaisesRegex(ValueError, "host policy snapshot"):
            recover_g17_abi.recover_g17_runtime_initialization(
                allocations, base_init, arm_init, base_power, b""
            )

    def test_recovers_zeroed_runtime_power_policy(self) -> None:
        arm_power, populate = runtime_power_policy_code()
        target = 0x12345678
        with (
            mock.patch.object(
                recover_g17_abi, "recover_vtable_target", return_value=target
            ),
            mock.patch.object(
                recover_g17_abi,
                "macho_symbols",
                return_value={recover_g17_abi.POPULATE_DPE_PPT_CONFIG: target},
            ),
        ):
            recovered = recover_g17_abi.recover_g17_runtime_power_policy(
                b"image", arm_power, populate
            )
        self.assertEqual(recovered["accelerator_vtable_slot"], 0xD80)
        self.assertEqual(recovered["cleared_source_bytes"], 0x6E0)
        self.assertEqual(
            recovered["runtime_range"], {"offset": 0xEC, "bytes": 0x6D8, "value": 0}
        )

    def test_rejects_nonzero_runtime_power_policy_producer(self) -> None:
        arm_power, populate = runtime_power_policy_code()
        target = 0x12345678
        populate = populate[:8] + encode(0x52800001) + populate[12:]
        with (
            mock.patch.object(
                recover_g17_abi, "recover_vtable_target", return_value=target
            ),
            mock.patch.object(
                recover_g17_abi,
                "macho_symbols",
                return_value={recover_g17_abi.POPULATE_DPE_PPT_CONFIG: target},
            ),
            self.assertRaisesRegex(ValueError, "0x6e0-byte clear"),
        ):
            recover_g17_abi.recover_g17_runtime_power_policy(
                b"image", arm_power, populate
            )

    def test_recovers_zeroed_runtime_performance_policy(self) -> None:
        setup, arm_power = runtime_performance_policy_code()
        recovered = recover_g17_abi.recover_g17_runtime_performance_policy(
            setup, arm_power
        )
        self.assertEqual(recovered["host_object_offset"], 0x27C8)
        self.assertEqual(recovered["cleared_source_bytes"], 0x39)
        self.assertEqual(recovered["copied_source_bytes"], 0x40)
        self.assertEqual(
            recovered["runtime_range"], {"offset": 0xA4, "bytes": 0x40}
        )
        self.assertEqual(recovered["reserved_tail_bytes"], 7)

    def test_rejects_incomplete_runtime_performance_policy_clear(self) -> None:
        setup, arm_power = runtime_performance_policy_code()
        with self.assertRaisesRegex(ValueError, "policy clear"):
            recover_g17_abi.recover_g17_runtime_performance_policy(
                setup[:-4], arm_power
            )

    def test_recovers_runtime_platform_policy(self) -> None:
        symbols, functions = runtime_platform_policy_code()
        platform = bytes.fromhex("ffff2800ffffffff")
        smart_high = struct.pack("<4f", 0.1, 0.25, 0.7, 0.9)
        smart_low = struct.pack("<4f", 1.0, 0.8, 0.2, 0.9)

        def vtable_target(_image: bytes, _name: str, slot: int) -> int:
            if slot == recover_g17_abi.G17_CONFIGURE_DEVICE_VTABLE_SLOT:
                return symbols[recover_g17_abi.G17_CONFIGURE_DEVICE]
            if slot == recover_g17_abi.G17_CONFIGURE_POWER_VTABLE_SLOT:
                return symbols[recover_g17_abi.G17_CONFIGURE_POWER]
            raise AssertionError(f"unexpected vtable slot {slot:#x}")

        with (
            mock.patch.object(recover_g17_abi, "macho_symbols", return_value=symbols),
            mock.patch.object(
                recover_g17_abi,
                "symbol_code",
                side_effect=lambda _image, name: functions[name],
            ),
            mock.patch.object(
                recover_g17_abi,
                "recover_vtable_target",
                side_effect=vtable_target,
            ),
            mock.patch.object(
                recover_g17_abi,
                "read_adrp_load",
                side_effect=(platform, smart_high, smart_low),
            ),
        ):
            recovered = recover_g17_abi.recover_g17_runtime_platform_policy(b"image")

        self.assertEqual(
            recovered["platform_halfwords"]["values"], [0xFFFF, 40, 0xFFFF]
        )
        fields = recovered["smart_idle"]["runtime_fields"]
        self.assertEqual(fields["standby_timer_us"], 1500)
        self.assertEqual(fields["gpu_min_confidence_bits"], 0x3F19999A)
        self.assertEqual(fields["reset_iterations_float_bits"], 0x40C00000)
        self.assertEqual(recovered["smart_idle"]["source_offset"], 0xE948)

    def test_rejects_wrong_runtime_platform_policy_vtable(self) -> None:
        symbols, _functions = runtime_platform_policy_code()
        with (
            mock.patch.object(recover_g17_abi, "macho_symbols", return_value=symbols),
            mock.patch.object(
                recover_g17_abi, "recover_vtable_target", return_value=0xDEADBEEF
            ),
            self.assertRaisesRegex(ValueError, "unexpected G17 configureDevice"),
        ):
            recover_g17_abi.recover_g17_runtime_platform_policy(b"image")

    def test_recovers_zero_initialized_allocations(self) -> None:
        recovered = recover_g17_abi.recover_g17_zero_initialized_allocations(
            zero_initialized_allocations_code()
        )
        self.assertEqual([item["bytes"] for item in recovered], [0x68, 0x800, 0x88])
        self.assertEqual(recovered[2]["host_gpu_member"], 0x340)
        self.assertEqual(len(recovered[2]["firmware_shared_offsets"]), 2)

    def test_rejects_incomplete_zero_initialized_allocations(self) -> None:
        with self.assertRaisesRegex(ValueError, "0x68-byte"):
            recover_g17_abi.recover_g17_zero_initialized_allocations(b"")

    def test_recovers_role0_bootstrap_regions(self) -> None:
        recovered = recover_g17_abi.recover_g17_role0_bootstrap_regions(
            role0_bootstrap_regions_code()
        )
        self.assertEqual([item["bytes"] for item in recovered], [0xC18, 0x1048, 0xE10])
        self.assertEqual(recovered[1]["sentinels"][0]["offset"], 0xA18)
        self.assertEqual(recovered[1]["sentinels"][1]["value"], 0xFFFFFFFF)

    def test_rejects_incomplete_role0_bootstrap_regions(self) -> None:
        with self.assertRaisesRegex(ValueError, "region clears"):
            recover_g17_abi.recover_g17_role0_bootstrap_regions(b"")

    def test_recovers_firmware_root_pointer_offsets(self) -> None:
        code = encode(
            *magic(10),
            add_immediate(9, 9, 0x3A8),
            add_immediate(10, 10, 0x3C0),
            ldp_x(19, 11, 10, 0),
            ldp_x(13, 14, 10, 0x90),
            ldp_x(13, 10, 10, 0xA0),
        )
        recovered = recover_g17_abi.recover_firmware_root(code)
        self.assertEqual(tuple(recovered["pointer_offsets"]), recover_g17_abi.ROOT_FIELDS)
        self.assertEqual(recovered["copied_bytes"], 0xC8)

    def test_recovers_driver_root_stores(self) -> None:
        recovered = recover_g17_abi.recover_driver_root(driver_root_code())
        self.assertEqual(tuple(recovered["pointer_offsets"]), recover_g17_abi.ROOT_FIELDS)
        self.assertEqual(recovered["platform_config"]["bytes"], 0x68)
        self.assertEqual(
            recovered["bootstrap_region"]["mapping_address_vtable_offset"], 0x158
        )
        self.assertEqual(recovered["roles"][1]["bindings"][-1]["root_offset"], 0xC0)

    def test_rejects_incomplete_driver_layout(self) -> None:
        code = encode(*magic(21), str_x(0, 20, 0x18))
        with self.assertRaisesRegex(ValueError, "unexpected driver root stores"):
            recover_g17_abi.recover_driver_root(code)

    def test_recovers_firmware_shared_data_publications(self) -> None:
        recovered = recover_g17_abi.recover_firmware_shared_data_layout(
            firmware_shared_allocations(),
            firmware_shared_code(),
            auxiliary_shared_code(),
        )
        self.assertEqual(recovered["bytes"], 0x4C0)
        self.assertEqual(len(recovered["roles"][0]["direct_publications"]), 9)
        self.assertIn(
            {
                "shared_cpu_member": 0xA98,
                "source_gpu_member": 0x338,
                "shared_offset": 0x08,
                "source_bytes": 0,
            },
            recovered["roles"][0]["direct_publications"],
        )
        self.assertIn(
            {"shared_cpu_member": 0xBC8, "source_gpu_member": 0x320,
             "shared_offset": 0x471, "source_bytes": 0x11DD0},
            recovered["roles"][1]["direct_publications"],
        )
        self.assertEqual(
            recovered["conditional_platform_publication"]["pointer_offset"],
            0x13768,
        )

    def test_rejects_incomplete_firmware_shared_data_publications(self) -> None:
        with self.assertRaisesRegex(ValueError, "auxiliary firmware-shared"):
            recover_g17_abi.recover_firmware_shared_data_layout(
                firmware_shared_allocations(), firmware_shared_code(), b""
            )

    def test_recovers_firmware_shared_platform_fields(self) -> None:
        recovered = recover_g17_abi.recover_firmware_shared_platform_fields(
            firmware_shared_platform_code()
        )
        self.assertEqual(
            recovered["primary_service_sources"][1]["platform_pointer_offset"],
            0x11568,
        )
        self.assertTrue(recovered["primary_service_sources"][0]["nullable"])
        self.assertEqual(
            recovered["primary_service_sources"][0]["mapping_address_vtable_offset"],
            0x158,
        )
        self.assertEqual(recovered["calibration"]["shared_offset"], 0x479)
        self.assertEqual(recovered["primary_state"]["status_bytes"], 0x90)

    def test_rejects_incomplete_firmware_shared_platform_fields(self) -> None:
        with self.assertRaisesRegex(ValueError, "platform service pair"):
            recover_g17_abi.recover_firmware_shared_platform_fields(b"")

    def test_recovers_g17_shared_platform_values(self) -> None:
        symbols = {
            recover_g17_abi.BASE_CONFIGURE_DEVICE: 0x100000,
            recover_g17_abi.G17_DEFAULT_USC_MAX_TGMEM: 0x101000,
            recover_g17_abi.SET_GVDM_MODE: 0x102000,
            recover_g17_abi.GET_UMA_MAX_ACTIVE_GTP_KICKS: 0x103000,
            recover_g17_abi.PERF_COUNTER_SOURCE_STOP: 0x104000,
            recover_g17_abi.PERF_COUNTER_LOCK_ACCESS: 0x105000,
        }
        base = bytearray(0x694)
        for offset, word in {
            0x444: 0x52821C08,
            0x448: 0x8B080208,
            0x44C: 0xF9487209,
            0x45C: 0xD73F0931,
            0x464: 0xB9009B00,
            0x68C: 0x6F00E400,
            0x690: 0x3DBDE660,
        }.items():
            struct.pack_into("<I", base, offset, word)
        setter = bytearray(0xF8)
        for offset, word in {
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
        }.items():
            struct.pack_into("<I", setter, offset, word)
        functions = {
            recover_g17_abi.BASE_CONFIGURE_DEVICE: (0x100000, bytes(base)),
            recover_g17_abi.G17_DEFAULT_USC_MAX_TGMEM: (
                0x101000,
                encode(0xD503245F, 0x52800180, 0xD65F03C0),
            ),
            recover_g17_abi.SET_GVDM_MODE: (0x102000, bytes(setter)),
            recover_g17_abi.GET_UMA_MAX_ACTIVE_GTP_KICKS: (
                0x103000,
                encode(
                    0xD503245F,
                    0x529F0688,
                    0x8B080008,
                    0xB9400108,
                    0x34000068,
                    0xB944E800,
                    0xD65F03C0,
                    0x52800020,
                    0xD65F03C0,
                ),
            ),
        }
        callers = {
            recover_g17_abi.PERF_COUNTER_SOURCE_STOP,
            recover_g17_abi.PERF_COUNTER_LOCK_ACCESS,
        }
        with (
            mock.patch.object(recover_g17_abi, "macho_symbols", return_value=symbols),
            mock.patch.object(
                recover_g17_abi,
                "recover_vtable_target",
                return_value=symbols[recover_g17_abi.G17_DEFAULT_USC_MAX_TGMEM],
            ),
            mock.patch.object(
                recover_g17_abi,
                "symbol_code",
                side_effect=lambda _image, name: functions[name],
            ),
            mock.patch.object(
                recover_g17_abi, "find_direct_symbol_callers", return_value=callers
            ),
            mock.patch.object(
                recover_g17_abi,
                "find_authenticated_target_references",
                return_value=[],
            ),
        ):
            recovered = recover_g17_abi.recover_g17_shared_platform_values(b"")

        self.assertEqual(recovered["scalars"][0]["value"], 12)
        self.assertEqual(recovered["scalars"][1]["value"], 0)
        self.assertEqual(recovered["calibration"]["initial_bytes"], "00" * 16)

    def test_rejects_wrong_shared_platform_value_vtable(self) -> None:
        with (
            mock.patch.object(
                recover_g17_abi,
                "macho_symbols",
                return_value={
                    recover_g17_abi.BASE_CONFIGURE_DEVICE: 1,
                    recover_g17_abi.G17_DEFAULT_USC_MAX_TGMEM: 2,
                    recover_g17_abi.SET_GVDM_MODE: 3,
                    recover_g17_abi.GET_UMA_MAX_ACTIVE_GTP_KICKS: 4,
                    recover_g17_abi.PERF_COUNTER_SOURCE_STOP: 5,
                    recover_g17_abi.PERF_COUNTER_LOCK_ACCESS: 6,
                },
            ),
            mock.patch.object(
                recover_g17_abi, "recover_vtable_target", return_value=0xDEADBEEF
            ),
            self.assertRaisesRegex(ValueError, "default USC"),
        ):
            recover_g17_abi.recover_g17_shared_platform_values(b"")

    def test_recovers_checked_ring_accessor(self) -> None:
        code = encode(
            ldr_w(0, 8, 0x20),
            cmp_w_immediate(0, 256),
        )
        self.assertEqual(recover_g17_abi.recover_ring_accessor(code), (0x20, 256))

    def test_recovers_data_master_stride(self) -> None:
        code = encode(movz_w(8, 0x18), umaddl(8, 0, 8))
        self.assertEqual(recover_g17_abi.recover_entry_stride(code), 0x18)

    def test_recovers_accelerator_command_fields(self) -> None:
        code = encode(
            str_unsigned(8, 1, 0x08, 8),
            str_unsigned(2, 1, 0x10, 4),
            str_unsigned(4, 1, 0x14, 2),
            str_unsigned(8, 1, 0x16, 1),
            str_unsigned(8, 1, 0x17, 1),
        )
        fields = recover_g17_abi.recover_accelerator_command_fields(code)
        self.assertEqual(fields["channel_data_address"], {"offset": 8, "bytes": 8})
        self.assertEqual(fields["flags"], {"offset": 0x17, "bytes": 1})

    def test_recovers_complete_accelerator_command_contract(self) -> None:
        code = encode(
            0xD503245F,
            0xB9001022,
            0xF9404068,
            0xF9000428,
            0x79002824,
            0xB9401868,
            0x39005828,
            0x3940F068,
            0x52800029,
            0x0A280128,
            0x39005C28,
            0xD65F03C0,
        )
        contract = recover_g17_abi.recover_accelerator_command_contract(code)
        self.assertEqual(contract["reserved_000"]["encoder_action"], "preserved")
        self.assertEqual(
            contract["channel_sources"]["channel_data_address"]["channel_offset"],
            0x80,
        )
        self.assertEqual(contract["flags_formula"], "1 & ~channel_flag")

    def test_recovers_data_master_submission_publication(self) -> None:
        common = (
            0xB9400284,
            0xF94002B0,
            0xAA1503F1,
            0xF2F9B431,
            0xDAC11A30,
            0xD2804F11,
            0x8B110210,
            0xF9400208,
            0xAA1503E0,
            0xF94007E1,
        )
        tail = (
            0xAA1303E3,
            0xF2E058F0,
            0xD73F0910,
            0xD5033BBF,
            0xF94002D0,
            0xAA1603F1,
            0xF2F3D511,
            0xDAC11A30,
            0xF8438E08,
            0xAA1603E0,
            0xF2F0EB70,
            0xD73F0910,
            0x11000408,
            0xF94002D0,
            0xAA1603F1,
            0xF2F3D511,
            0xDAC11A30,
            0xF8410E09,
            0x12001D01,
            0xAA1603E0,
            0xF2E27510,
            0xD73F0930,
        )
        recovered = recover_g17_abi.recover_data_master_submission_sequence(
            encode(*common, 0x52800022, *tail), 1
        )
        self.assertEqual(recovered["command_type"], 1)
        self.assertEqual(recovered["publish_barrier"], "dmb ish")
        self.assertEqual(
            recovered["next_write_index"], "(write_index + 1) & 0xff"
        )

    def test_rejects_wrong_data_master_command_type(self) -> None:
        with self.assertRaisesRegex(ValueError, "publication"):
            recover_g17_abi.recover_data_master_submission_sequence(
                encode(0x52800042), 1
            )

    def test_recovers_g17_dual_role_boot_transport(self) -> None:
        notify = bytearray(0x134)
        receive = bytearray(0xF0)
        boot = bytearray(0xAC)
        for offset, word in {
            0x018: 0x52833B08,
            0x01C: 0x8B080008,
            0x020: 0x52800709,
            0x024: 0x9BA97C29,
            0x02C: 0x8B29C114,
            0x03C: 0x52800035,
            0x040: 0x3900A295,
            0x048: 0xF9001A80,
            0x0FC: 0xF9400288,
            0x100: 0xD2E01021,
            0x104: 0xB340AC01,
            0x12C: 0x91226202,
            0x130: 0xF9444E10,
        }.items():
            struct.pack_into("<I", notify, offset, word)
        for offset, word in {
            0x014: 0xD370D428,
            0x018: 0xF100251F,
            0x020: 0xF100091F,
            0x060: 0x52834908,
            0x068: 0x8B080000,
            0x080: 0xB91A4A7F,
            0x088: 0xD2E01128,
            0x08C: 0xF90003E8,
            0x090: 0xF94CEE60,
            0x0A4: 0xD2811611,
            0x0A8: 0x8B110210,
            0x0AC: 0xF9400208,
            0x0C0: 0xF94D0A60,
            0x0E8: 0x9122C208,
            0x0EC: 0xF9445A09,
        }.items():
            struct.pack_into("<I", receive, offset, word)
        for offset, word in {
            0x01C: 0x91400415,
            0x020: 0x392802BF,
            0x024: 0x3928E2BF,
            0x028: 0x392B16BF,
            0x02C: 0xF94CEC00,
            0x030: 0xF94CFE61,
            0x044: 0xD2811111,
            0x048: 0x8B110210,
            0x04C: 0xF9400208,
            0x05C: 0xF94D0A60,
            0x060: 0xF94D1A61,
            0x088: 0x91222208,
            0x08C: 0xF9444609,
            0x09C: 0x7100029F,
            0x0A0: 0x7A401804,
            0x0A8: 0x396B16A8,
        }.items():
            struct.pack_into("<I", boot, offset, word)

        recovered = recover_g17_abi.recover_g17_boot_transport(
            bytes(notify), bytes(receive), bytes(boot)
        )
        self.assertEqual(recovered["role_count"], 2)
        self.assertEqual(recovered["role_record_stride"], 0x38)
        self.assertEqual(
            recovered["root_mapping_host_members"], [0x19F8, 0x1A30]
        )
        self.assertEqual(recovered["init_message"], 0x81 << 48)
        self.assertEqual(recovered["init_address_bits"], 44)
        self.assertEqual(recovered["ready_type"], 9)
        self.assertEqual(recovered["callback_type"], 2)
        self.assertEqual(recovered["ready_ack_message"], 0x89 << 48)
        self.assertEqual(recovered["ready_ack_transport_count"], 2)
        self.assertTrue(recovered["requires_both_transport_boots"])

    def test_rejects_single_role_g17_boot_transport(self) -> None:
        notify = bytearray(0x134)
        receive = bytearray(0xF0)
        boot = bytearray(0xAC)
        # A changed second-role transport load must fail rather than silently
        # degrading the G17 contract to the legacy single-ASC model.
        for offset, word in {
            0x018: 0x52833B08,
            0x01C: 0x8B080008,
            0x020: 0x52800709,
            0x024: 0x9BA97C29,
            0x02C: 0x8B29C114,
            0x03C: 0x52800035,
            0x040: 0x3900A295,
            0x048: 0xF9001A80,
            0x0FC: 0xF9400288,
            0x100: 0xD2E01021,
            0x104: 0xB340AC01,
            0x12C: 0x91226202,
            0x130: 0xF9444E10,
        }.items():
            struct.pack_into("<I", notify, offset, word)
        for offset, word in {
            0x014: 0xD370D428,
            0x018: 0xF100251F,
            0x020: 0xF100091F,
            0x060: 0x52834908,
            0x068: 0x8B080000,
            0x080: 0xB91A4A7F,
            0x088: 0xD2E01128,
            0x08C: 0xF90003E8,
            0x090: 0xF94CEE60,
            0x0A4: 0xD2811611,
            0x0A8: 0x8B110210,
            0x0AC: 0xF9400208,
            0x0C0: 0xF94CEE60,
            0x0E8: 0x9122C208,
            0x0EC: 0xF9445A09,
        }.items():
            struct.pack_into("<I", receive, offset, word)
        for offset, word in {
            0x01C: 0x91400415,
            0x020: 0x392802BF,
            0x024: 0x3928E2BF,
            0x028: 0x392B16BF,
            0x02C: 0xF94CEC00,
            0x030: 0xF94CFE61,
            0x044: 0xD2811111,
            0x048: 0x8B110210,
            0x04C: 0xF9400208,
            0x05C: 0xF94D0A60,
            0x060: 0xF94D1A61,
            0x088: 0x91222208,
            0x08C: 0xF9444609,
            0x09C: 0x7100029F,
            0x0A0: 0x7A401804,
            0x0A8: 0x396B16A8,
        }.items():
            struct.pack_into("<I", boot, offset, word)

        with self.assertRaisesRegex(ValueError, "AKF message handling"):
            recover_g17_abi.recover_g17_boot_transport(
                bytes(notify), bytes(receive), bytes(boot)
            )

    def test_recovers_g17_rtbuddy_endpoints(self) -> None:
        read = bytearray(0x14)
        send = bytearray(0x44)
        matched = bytearray(0x104)
        enable = bytearray(0x80)
        received = bytearray(0x0C)
        for target, words in (
            (read, {0x00C: 0xF9409400, 0x010: 0x52800002}),
            (
                send,
                {
                    0x008: 0xF9409400,
                    0x028: 0xD2803D11,
                    0x02C: 0x8B110210,
                    0x030: 0xF9400208,
                    0x03C: 0xD2800002,
                    0x040: 0x52800023,
                },
            ),
            (
                matched,
                {
                    0x01C: 0xB9408828,
                    0x020: 0x7100851F,
                    0x028: 0x7100811F,
                    0x030: 0xF9009674,
                    0x100: 0xF9009A74,
                },
            ),
            (
                enable,
                {
                    0x014: 0xF9409400,
                    0x028: 0xD2802E11,
                    0x02C: 0x8B110210,
                    0x030: 0xF9400208,
                    0x03C: 0xF9409A60,
                    0x064: 0x9105C208,
                    0x068: 0xF940BA09,
                    0x078: 0xF940BA60,
                    0x07C: 0xB9412261,
                },
            ),
            (received, {0x004: 0xF940B808, 0x008: 0xB9412002}),
        ):
            for offset, word in words.items():
                struct.pack_into("<I", target, offset, word)

        recovered = recover_g17_abi.recover_g17_rtbuddy_endpoints(
            bytes(read), bytes(send), bytes(matched), bytes(enable), bytes(received)
        )
        self.assertEqual(recovered["message_endpoint"], 0x20)
        self.assertEqual(recovered["doorbell_endpoint"], 0x21)
        self.assertEqual(recovered["message_endpoint_host_member"], 0x128)
        self.assertEqual(recovered["doorbell_endpoint_host_member"], 0x130)
        self.assertTrue(recovered["receive_forwards_role"])

    def test_recovers_device_control_copy_size(self) -> None:
        code = encode(
            pair_q("load", 0, 1, 21, 0),
            pair_q("load", 2, 3, 21, 0x20),
            pair_q("store", 0, 1, 9, 0),
            pair_q("store", 2, 3, 9, 0x20),
        )
        self.assertEqual(recover_g17_abi.recover_vector_copy_size(code), 0x40)

    def test_recovers_g17_channel_pool_geometry(self) -> None:
        code = encode(
            movz_w(8, 0x11C8),
            movz_w(2, 0xC0),
            movz_w(4, 9),
            movz_w(5, 1),
            movz_w(20, 0x70),
            bfi_x(20, 8, 7, 28),
            movz_w(8, 0x1348),
            movz_w(4, 9),
            movz_w(5, 0),
            movz_w(8, 0x1408),
            movz_w(4, 9),
            movz_w(5, 1),
        )
        pools = recover_g17_abi.recover_g17_channel_pool_geometry(code)
        self.assertEqual(pools["channel_state"]["element_bytes"], 0xC0)
        self.assertEqual(pools["uncached_memory"]["element_base_bytes"], 0x70)
        self.assertEqual(pools["cached_memory"]["bytes_per_configured_queue"], 0x80)

    def test_recovers_g17_channel_layout(self) -> None:
        reset_code = encode(
            ldp_x(9, 10, 0, 0x58),
            ldr_x(8, 0, 0x68),
            *(pair_q("store", 0, 0, 8, offset)
              for offset in (0, 0x20, 0x40, 0x60, 0x80, 0xA0)),
            *(str_unsigned(8, 9, offset, width)
              for offset, width in (
                  (0x00, 8), (0x08, 8), (0x10, 8), (0x18, 4),
                  (0x1C, 4), (0x20, 4), (0x24, 4), (0x28, 4),
                  (0x44, 4), (0x48, 4), (0x84, 4),
              )),
            stur_x(8, 9, 0x9C),
            *(str_unsigned(8, 10, offset, 4)
              for offset in (0x00, 0x10, 0x20, 0x30, 0x40, 0x50, 0x60)),
        )
        write_code = encode(
            ldr_x(8, 0, 0x60),
            ldr_w(9, 8, 0x60),
            ldr_w(10, 8, 0x40),
            ldr_w(11, 8, 0x00),
            ldr_w(9, 0, 0x54),
            ldr_x(9, 0, 0x68),
            ubfiz_x(10, 8, 3, 61),
            str_unsigned(1, 11, 0, 8),
            0xD5033BBF,  # dmb ish
            str_unsigned(8, 9, 0x40, 4),
        )
        channel = recover_g17_abi.recover_g17_channel_layout(
            reset_code, write_code
        )
        self.assertEqual(channel["state"]["bytes"], 0xC0)
        self.assertEqual(channel["uncached_control"]["write_index"], 0x40)
        self.assertEqual(channel["cached_command_pointer_bytes"], 8)
        self.assertEqual(channel["enqueue"]["reserved_entries"], 1)
        self.assertTrue(channel["enqueue"]["write_index_published_last"])

    def test_rejects_incomplete_g17_channel_layout(self) -> None:
        with self.assertRaisesRegex(ValueError, "CPU bindings"):
            recover_g17_abi.recover_g17_channel_layout(b"", b"")

    def test_recovers_g17_handoff_layout(self) -> None:
        ppl_magic = 0x4B1D000000000002
        code = encode(
            movz(8, ppl_magic & 0xFFFF),
            movk(8, (ppl_magic >> 48) & 0xFFFF, 48),
            str_unsigned(8, 0, 0, 8),
            str_unsigned(31, 0, 0x10, 1),
            str_unsigned(31, 0, 0x11, 1),
            str_unsigned(31, 0, 0x14, 4),
            str_unsigned(9, 0, 0x18, 4),
            str_unsigned(8, 0, 0x638, 1),
            str_unsigned(31, 0, 0x640, 8),
            0x52800829,
            0xB81F011F,
            0xF81F811F,
            0xF801851F,
            0xF1000529,
            0x54FFFF81,
        )
        handoff = recover_g17_abi.recover_g17_handoff(code)
        self.assertEqual(handoff["bytes"], 0x648)
        self.assertEqual(handoff["flush_records"], 65)
        self.assertEqual(handoff["current_slot_initial"], 0xFFFFFFFF)

    def test_validates_root_allocation_sizes(self) -> None:
        expected = {
            0xAB8: 0x4C0,
            0xBE8: 0x4C0,
            0x388: 0x1CA0,
            0xAD0: 0x20,
            0xC00: 0x20,
            0xCE0: 0xE440,
            0xCE8: 0x6F0,
            0x398: 0xA8,
        }
        allocations = [
            {"host_cpu_member": member - 8, "host_gpu_member": member, "bytes": size}
            for member, size in expected.items()
        ]
        sizes = recover_g17_abi.recover_root_allocation_sizes(allocations)
        self.assertEqual(sizes["runtime_data"], 0x1CA0)
        self.assertEqual(sizes["primary_region"], 0xE440)

    def test_recovers_firmware_hardware_config_reads(self) -> None:
        prefix = encode(
            *magic(10),
            ldr_x(11, 19, 0),
            ldr_x(8, 11, 0x8F0),
            ldr_x(11, 19, 0),
            ldr_q(0, 11, 0xE90),
            ldr_x(13, 19, 0),
            add_register(13, 13, 14),
            ldr_w(13, 13, 0xFC8),
            ldr_x(16, 19, 0),
            add_register(16, 16, 17),
            ldr_w(16, 16, 0x1008),
            ldr_x(16, 19, 0),
            add_register(16, 16, 17),
            ldr_w(16, 16, 0x1408),
            ldr_x(8, 19, 0),
            movz_w(9, 0x19C8),
            add_register(8, 8, 9),
            pair_q("load", 0, 1, 8, 0),
            ldr_x(11, 19, 0),
            ldr_x(11, 11, 0x2610),
            ldr_x(8, 19, 0),
            movz_w(9, 0x26F9),
            ldrb_register(8, 8, 9),
        )
        copied = encode(
            ldr_x(8, 19, 0),
            movz_w(9, 0x1B90),
            add_immediate(0, 22, 0x510),
            add_register(1, 8, 9),
            movz_w(2, 0x148),
        )
        recovered = recover_g17_abi.recover_firmware_config_reads(
            prefix + copied + bytes(0x800)
        )
        self.assertIn(
            {"offset": 0xFC8, "bytes": 4, "indexed": True},
            recovered["firmware_direct_reads"],
        )
        self.assertEqual(
            recovered["firmware_bulk_reads"],
            [
                {"offset": 0x19C8, "bytes": 0x80},
                {"offset": 0x1B90, "bytes": 0x148},
            ],
        )

    def test_recovers_hardware_config_allocation_and_publication(self) -> None:
        allocations = [
            {
                "host_cpu_member": 0x2B8,
                "host_gpu_member": 0x300,
                "bytes": 0x2710,
            }
        ]
        role = lambda member: (
            ldr_x(1, 19, 0x300),
            ldr_x(8, 19, member),
            str_x(0, 8, 0),
        )
        shared_code = encode(*role(0xA98), *role(0xBC8))
        firmware = encode(
            *magic(10),
            ldr_x(11, 19, 0),
            ldr_x(8, 11, 0x8F0),
            ldr_x(11, 19, 0),
            ldr_q(0, 11, 0xE90),
            ldr_x(13, 19, 0),
            add_register(13, 13, 14),
            ldr_w(13, 13, 0xFC8),
            ldr_x(16, 19, 0),
            add_register(16, 16, 17),
            ldr_w(16, 16, 0x1008),
            ldr_x(16, 19, 0),
            add_register(16, 16, 17),
            ldr_w(16, 16, 0x1408),
            ldr_x(8, 19, 0),
            movz_w(9, 0x19C8),
            add_register(8, 8, 9),
            pair_q("load", 0, 1, 8, 0),
            ldr_x(11, 19, 0),
            ldr_x(11, 11, 0x2610),
            ldr_x(8, 19, 0),
            movz_w(9, 0x26F9),
            ldrb_register(8, 8, 9),
            ldr_x(8, 19, 0),
            movz_w(9, 0x1B90),
            add_immediate(0, 22, 0x510),
            add_register(1, 8, 9),
            movz_w(2, 0x148),
        ) + bytes(0x800)
        recovered = recover_g17_abi.recover_hardware_config(
            allocations, shared_code, firmware
        )
        self.assertEqual(recovered["bytes"], 0x2710)
        self.assertEqual(recovered["published_shared_cpu_members"], [0xA98, 0xBC8])

    def test_recovers_driver_hardware_config_table_layout(self) -> None:
        matrix_loop = (
            0x5280040A,
            0xF940010B,
            0xF9001D2B,
            0xF941810B,
            0xF9019D2B,
            0xF940050B,
            0xF900212B,
            0xF941850B,
            0xF901A12B,
            0xF940090B,
            0xF900252B,
            0xF941890B,
            0xF901A52B,
            0x91006108,
            0x91006129,
            0xF100054A,
            0x54FFFE21,
        )
        io_loop = (
            0xD2800008,
            0xD280000A,
            0xF9415E69,
            0xF9129520,
            0xF9414E60,
            0x8B08000B,
            0xB949896C,
            0xB947856D,
            0x1B0C7DAD,
            0x8B0A012E,
            0xB90651CD,
            0xF943C56D,
            0xF90321CD,
            0xF944C96D,
            0xF9032DCD,
            0xB90655CC,
            0xB947816B,
            0x121F016B,
            0xB90661CB,
            0xF90325DF,
            0x9100A14A,
            0x9110E108,
            0xF121215F,
            0x54FFFDC1,
        )
        base_init = encode(*matrix_loop, *io_loop)
        frequency_conversion = (
            0xF9415E68,
            0xB90FC509,
            0xF9414E69,
            0x91406D29,
            0xB943192B,
            0x529BD06A,
            0x72A8636A,
            0x9BAA7D6B,
            0xD372FD6B,
            0xB90FC90B,
            0xB94B612B,
            0x9BAA7D6B,
            0xD372FD6B,
            0xB918090B,
        )
        base_power = encode(
            *frequency_conversion,
            *(str_unsigned(9, 8, offset, 4) for offset in (0xFC4,)),
            *(str_unsigned(11, 8, offset, 4) for offset in range(0xFC8, 0x1008, 4)),
            *(
                str_unsigned(11, 8, offset, 4)
                for offset in range(0x1808, 0x1848, 4)
            ),
        )
        arm_power = encode(
            0xF9415E6B,
            0x5282010A,
            0x8B0A016A,
            0x91041108,
            0x5283110C,
            0x8B0C016B,
            0x5280020C,
            *(str_unsigned(13, 10, offset, 4) for offset in range(0, 0x40, 4)),
            *(
                str_unsigned(13, 10, 0x400 + offset, 4)
                for offset in range(0, 0x40, 4)
            ),
            0xBC5C0100,
            0xBC1C0160,
            0x91010129,
            0xBC404500,
            0xBC004560,
            0x9101014A,
            0xF100058C,
            0x54FFF721,
            0xF9415E68,
            0x52831909,
            0x8B090101,
            0x52800002,
            0x5283210B,
            0x8B0B0134,
            0x5283290B,
            0x8B0B012B,
            0x52833909,
            0x8B09010A,
        )
        recovered = recover_g17_abi.recover_driver_hardware_config_layout(
            base_init, base_power, arm_power
        )
        self.assertEqual(recovered["color_matrices"]["records"], 64)
        self.assertEqual(recovered["io_mappings"]["records"], 53)
        self.assertEqual(recovered["performance_states"]["voltage_offset"], 0x1008)
        self.assertEqual(
            recovered["performance_states"]["secondary_frequency_source_offset"],
            0x1BB60,
        )
        self.assertEqual(
            recovered["performance_states"]["derived_table_offsets"][-1], 0x1948
        )

    def test_rejects_incomplete_driver_hardware_config_layout(self) -> None:
        with self.assertRaisesRegex(ValueError, "color-matrix"):
            recover_g17_abi.recover_driver_hardware_config_layout(b"", b"", b"")

    def test_recovers_g17_address_space_layout(self) -> None:
        base_init = bytearray(0x16F4)
        expected_words = {
            0x1478: 0xF9415E68,
            0x1480: 0x3DC35920,
            0x1484: 0xD2C00209,
            0x1488: 0x4E080D21,
            0x148C: 0xAD000500,
            0x1490: 0xB27143E9,
            0x1494: 0xF2C05FE9,
            0x1498: 0xF9001109,
            0x1538: 0x91406808,
            0x153C: 0x910D0108,
            0x1540: 0xF9400108,
            0x1544: 0xB40001C8,
            0x1558: 0xD2802B11,
            0x1570: 0xAA0003E8,
            0x1574: 0xF9415E69,
            0x157C: 0xF9001928,
            0x16A8: 0x910B6208,
            0x16B0: 0xD2B02801,
            0x16B4: 0xF2DF8421,
            0x16B8: 0xF2FFFFE1,
            0x16BC: 0xAA1303E0,
            0x16C0: 0x52800002,
            0x16F0: 0xF9001500,
        }
        for offset, word in expected_words.items():
            struct.pack_into("<I", base_init, offset, word)

        symbols = {
            recover_g17_abi.INIT_BASE_FIRMWARE_DATA: 0x1000,
            recover_g17_abi.G17_SETUP_CSC_ALLOCATION: 0x2000,
            recover_g17_abi.CONVERT_GPU_VA_TO_FW_VA: 0x3000,
        }
        stubs = {
            recover_g17_abi.G17_SETUP_CSC_ALLOCATION: encode(
                0xD503245F, 0x52800020, 0xD65F03C0
            ),
            recover_g17_abi.CONVERT_GPU_VA_TO_FW_VA: encode(
                0xD503245F, 0xAA0103E0, 0xD65F03C0
            ),
        }

        def vtable_target(_image: bytes, _name: str, slot: int) -> int:
            if slot == recover_g17_abi.G17_SETUP_CSC_ALLOCATION_VTABLE_SLOT:
                return symbols[recover_g17_abi.G17_SETUP_CSC_ALLOCATION]
            if slot == recover_g17_abi.FIRMWARE_ADDRESS_CONVERSION_VTABLE_SLOT:
                return symbols[recover_g17_abi.CONVERT_GPU_VA_TO_FW_VA]
            raise AssertionError(f"unexpected vtable slot {slot:#x}")

        with (
            mock.patch.object(recover_g17_abi, "macho_symbols", return_value=symbols),
            mock.patch.object(
                recover_g17_abi, "recover_vtable_target", side_effect=vtable_target
            ),
            mock.patch.object(
                recover_g17_abi,
                "symbol_code",
                side_effect=lambda _image, name: (symbols[name], stubs[name]),
            ),
            mock.patch.object(
                recover_g17_abi,
                "read_adrp_load",
                return_value=struct.pack("<QQ", 0x6F00000000, 0xFFC00000),
            ),
        ):
            recovered = recover_g17_abi.recover_g17_address_space_layout(
                b"", bytes(base_init)
            )

        self.assertEqual(recovered["bytes"], 0x38)
        self.assertEqual(recovered["usc_start"], [0x1000000000, 0x1000000000])
        self.assertEqual(recovered["unknown_page"], 0x2FFFFFF8000)
        self.assertEqual(recovered["timestamp_area_base"], 0xFFFFFC2181400000)
        self.assertEqual(recovered["yuv_csc_table_address"], 0)

    def test_rejects_g17_address_space_layout_with_legacy_csc_provider(self) -> None:
        symbols = {
            recover_g17_abi.INIT_BASE_FIRMWARE_DATA: 0x1000,
            recover_g17_abi.G17_SETUP_CSC_ALLOCATION: 0x2000,
            recover_g17_abi.CONVERT_GPU_VA_TO_FW_VA: 0x3000,
        }
        with (
            mock.patch.object(recover_g17_abi, "macho_symbols", return_value=symbols),
            mock.patch.object(
                recover_g17_abi, "recover_vtable_target", return_value=0x4000
            ),
        ):
            with self.assertRaisesRegex(ValueError, "CSC allocation provider"):
                recover_g17_abi.recover_g17_address_space_layout(b"", b"")

    def test_recovers_g17_color_matrices(self) -> None:
        function_address = 0x1000
        tpu_address = 0x3000
        pbe_address = 0x4000
        code = bytearray(0x74)
        expected_words = {
            0x00: 0xD503245F,
            0x04: 0xD2800008,
            0x08: 0x91406809,
            0x0C: 0x910D2129,
            0x10: 0x9140680A,
            0x14: 0x910D614A,
            0x18: 0x9140680B,
            0x1C: 0x9119616B,
            0x24: add_immediate(12, 12, tpu_address & 0xFFF),
            0x2C: add_immediate(13, 13, pbe_address & 0xFFF),
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

        def adrp(source: int, target: int, register: int) -> int:
            pages = ((target & ~0xFFF) - (source & ~0xFFF)) >> 12
            immediate = pages & 0x1FFFFF
            return (
                0x90000000
                | (immediate & 3) << 29
                | ((immediate >> 2) & 0x7FFFF) << 5
                | register
            )

        expected_words[0x20] = adrp(function_address + 0x20, tpu_address, 12)
        expected_words[0x28] = adrp(function_address + 0x28, pbe_address, 13)
        for offset, word in expected_words.items():
            struct.pack_into("<I", code, offset, word)

        tpu = bytearray(0x300)
        pbe = bytearray(0x300)
        struct.pack_into("<12h", tpu, 7 * 0x18, 8200, 0, 0, 0, 0, 8200, 0, 0, 0, 0, 8200, 0)
        struct.pack_into("<12h", pbe, 28 * 0x18, 9797, 19235, 3736, 0, -5537, -10846, 16383, 16384, 16384, -13730, -2654, 16384)
        symbols = {
            recover_g17_abi.G17_GENERATE_CSC_COEFFICIENTS: function_address,
            recover_g17_abi.G17_TPU_CSC_COEFFICIENTS: tpu_address,
            recover_g17_abi.G17_PBE_CSC_COEFFICIENTS: pbe_address,
        }
        blobs = {
            recover_g17_abi.G17_GENERATE_CSC_COEFFICIENTS: bytes(code),
            recover_g17_abi.G17_TPU_CSC_COEFFICIENTS: bytes(tpu),
            recover_g17_abi.G17_PBE_CSC_COEFFICIENTS: bytes(pbe),
        }
        with (
            mock.patch.object(recover_g17_abi, "macho_symbols", return_value=symbols),
            mock.patch.object(
                recover_g17_abi,
                "recover_vtable_target",
                return_value=function_address,
            ),
            mock.patch.object(
                recover_g17_abi,
                "symbol_code",
                side_effect=lambda _image, name: (symbols[name], blobs[name]),
            ),
        ):
            recovered = recover_g17_abi.recover_g17_color_matrices(b"")

        self.assertEqual(recovered["records"], 64)
        self.assertEqual(
            recovered["banks"][0]["nonzero_records"],
            [{"index": 7, "coefficients": [8200, 0, 0, 0, 0, 8200, 0, 0, 0, 0, 8200, 0]}],
        )
        self.assertEqual(recovered["banks"][1]["nonzero_records"][0]["index"], 28)

    def test_recovers_g17_hardware_config_constants(self) -> None:
        base_init = bytearray(0x1678)
        arm_init = bytearray(0x4E8)
        base_words = {
            0x1264: 0xF9415E68,
            0x1268: 0xB90EBD1F,
            0x126C: 0x52800036,
            0x1270: 0xB90EC916,
            0x13AC: 0x913AB128,
            0x13B4: 0x3DC35540,
            0x13B8: 0x3D800100,
            0x13E4: 0x721C017F,
            0x13E8: 0x5280190B,
            0x13EC: 0x1A9F156B,
            0x13F0: 0xB90ED52B,
            0x165C: 0xF9415E68,
            0x1660: 0xF9031D00,
            0x1664: 0x3968A6A9,
            0x1668: 0x5301052A,
            0x166C: 0xB90EA10A,
            0x1670: 0x53041129,
            0x1674: 0xB90EA909,
        }
        arm_words = {
            0x4C: 0x528BB808,
            0x50: 0xB90ED128,
            0x58: 0x913B9128,
            0x5C: 0xB20003EA,
            0x60: 0xF900010A,
            0x64: 0x528003E8,
            0x68: 0xB90F0528,
            0xB0: 0x3DC35100,
            0xB4: 0x3D83CD20,
            0x4E0: 0x52800029,
            0x4E4: 0xB90EE109,
        }
        for offset, word in base_words.items():
            struct.pack_into("<I", base_init, offset, word)
        for offset, word in arm_words.items():
            struct.pack_into("<I", arm_init, offset, word)

        symbols = {
            recover_g17_abi.INIT_BASE_FIRMWARE_DATA: 0x1000,
            recover_g17_abi.INIT_FIRMWARE_DATA: 0x2000,
            recover_g17_abi.G17_GET_BORDER_COLOR_TABLE_GPU_ADDRESS: 0x3000,
        }
        with (
            mock.patch.object(recover_g17_abi, "macho_symbols", return_value=symbols),
            mock.patch.object(
                recover_g17_abi, "recover_vtable_target", return_value=0x3000
            ),
            mock.patch.object(
                recover_g17_abi,
                "symbol_code",
                return_value=(0x3000, encode(0xD503245F, 0xD2800000, 0xD65F03C0)),
            ),
            mock.patch.object(
                recover_g17_abi,
                "read_adrp_load",
                side_effect=[
                    struct.pack("<4I", 0, 0, 0, 1),
                    struct.pack("<4I", 0, 1, 1, 0),
                    b"\0",
                ],
            ),
            mock.patch.object(
                recover_g17_abi,
                "recover_g17_feature_defaults",
                return_value={"fixed_u32": {"0xec0": 1}},
            ),
        ):
            recovered = recover_g17_abi.recover_g17_hardware_config_constants(
                b"", bytes(base_init), bytes(arm_init)
            )

        self.assertEqual(recovered["border_color_table_address"]["value"], 0)
        self.assertEqual(recovered["scalar_block"]["fixed_u32"]["0xec0"], 1)
        self.assertEqual(recovered["scalar_block"]["fixed_u32"]["0xed0"], 24000)
        self.assertEqual(recovered["scalar_block"]["fixed_u32"]["0xf38"], 1)

    def test_recovers_g17_chip_info(self) -> None:
        configure_address = 0x100000
        retrieve_address = 0x110000
        configure = bytearray(0x650)
        retrieve = bytearray(0x164)
        arm_init = bytearray(0x38)
        for offset, word in {
            0x610: 0x529EF908,
            0x634: 0x91358209,
            0x638: 0xF946B20A,
            0x63C: 0x8B080261,
            0x640: 0xAA1303E0,
            0x64C: 0xD73F0951,
        }.items():
            struct.pack_into("<I", configure, offset, word)
        for offset, word in {
            0xBC: 0xB9400008,
            0xC0: 0xB9000288,
            0x154: 0xB9400008,
            0x158: 0x53047D09,
            0x15C: 0x12000908,
            0x160: 0x2900A289,
        }.items():
            struct.pack_into("<I", retrieve, offset, word)
        for offset, word in {
            0x20: 0xF9414E68,
            0x24: 0x529EF909,
            0x28: 0x8B090108,
            0x2C: 0xF9415E69,
            0x30: 0x3DC00100,
            0x34: 0x3D83A520,
        }.items():
            struct.pack_into("<I", arm_init, offset, word)
        symbols = {
            recover_g17_abi.BASE_CONFIGURE_DEVICE: configure_address,
            recover_g17_abi.RETRIEVE_CHIP_INFO: retrieve_address,
        }
        code = {
            recover_g17_abi.BASE_CONFIGURE_DEVICE: (
                configure_address,
                bytes(configure),
            ),
            recover_g17_abi.RETRIEVE_CHIP_INFO: (retrieve_address, bytes(retrieve)),
        }
        with (
            mock.patch.object(recover_g17_abi, "macho_symbols", return_value=symbols),
            mock.patch.object(
                recover_g17_abi,
                "recover_vtable_target",
                return_value=retrieve_address,
            ),
            mock.patch.object(
                recover_g17_abi,
                "symbol_code",
                side_effect=lambda _image, name: code[name],
            ),
        ):
            recovered = recover_g17_abi.recover_g17_chip_info(
                b"chip-id\0chip-revision\0", bytes(arm_init)
            )

        self.assertEqual(recovered["offset"], 0xE90)
        self.assertEqual(recovered["source_record_offset"], 0xF7C8)
        self.assertEqual(recovered["fields"][1]["formula"], "value >> 4")
        self.assertEqual(recovered["fields"][2]["formula"], "value & 7")

    def test_recovers_g17_power_sample_period(self) -> None:
        configure_address = 0x100000
        getter_address = 0x200000
        configure = bytearray(0x810)
        for offset, word in {
            0x34: 0x529EE508,
            0x38: 0x8B080018,
            0x5CC: 0x91049317,
            0x7C4: 0xB0FF41E1,
            0x7C8: 0x9115E821,
            0x808: 0xB9400008,
            0x80C: 0xB90002E8,
        }.items():
            struct.pack_into("<I", configure, offset, word)
        getter = b"".join(
            struct.pack("<I", word)
            for word in (
                0xD503245F,
                0x529F0988,
                0x8B080008,
                0xB9400100,
                0xD65F03C0,
            )
        )
        arm_init = bytearray(0xF8)
        for offset, word in {
            0xDC: 0x913DC208,
            0xE0: 0xF947BA09,
            0xE4: 0xAA0803F1,
            0xE8: 0xF2EDFA71,
            0xEC: 0xD73F0931,
            0xF0: 0xF9415E68,
            0xF4: 0xB90ED900,
        }.items():
            struct.pack_into("<I", arm_init, offset, word)
        symbols = {
            recover_g17_abi.BASE_CONFIGURE_DEVICE: configure_address,
            recover_g17_abi.G17_GET_SAMPLE_PERIOD: getter_address,
        }
        code = {
            recover_g17_abi.BASE_CONFIGURE_DEVICE: (
                configure_address,
                bytes(configure),
            ),
            recover_g17_abi.G17_GET_SAMPLE_PERIOD: (getter_address, getter),
        }
        image = b"gpu-power-sample-period\0"
        with (
            mock.patch.object(recover_g17_abi, "macho_symbols", return_value=symbols),
            mock.patch.object(
                recover_g17_abi,
                "recover_vtable_target",
                return_value=getter_address,
            ),
            mock.patch.object(
                recover_g17_abi,
                "symbol_code",
                side_effect=lambda _image, name: code[name],
            ),
            mock.patch.object(recover_g17_abi, "virtual_to_file", return_value=0),
        ):
            recovered = recover_g17_abi.recover_g17_power_sample_period(
                image, bytes(arm_init)
            )

        self.assertEqual(recovered["offset"], 0xED8)
        self.assertEqual(recovered["property"], "gpu-power-sample-period")
        self.assertEqual(recovered["accelerator_offset"], 0xF84C)
        self.assertEqual(recovered["formula"], "value")

    def test_recovers_g17_default_mcache_writes(self) -> None:
        configure_address = 0x100000
        getter_address = 0x200000
        configure = bytearray(0x4F0)
        for offset, word in {
            0x34: 0x529EE508,
            0x38: 0x8B080018,
            0x4D0: 0x913FC208,
            0x4D4: 0xF947FA09,
            0x4D8: 0xAA1303E0,
            0x4E4: 0xD73F0931,
            0x4EC: 0xF9000700,
        }.items():
            struct.pack_into("<I", configure, offset, word)
        getter = b"".join(
            struct.pack("<I", word)
            for word in (
                0xD503245F,
                0xD2800080,
                0xF2A0F000,
                0xF2C000C0,
                0xD65F03C0,
            )
        )
        arm_init = bytearray(0x720)
        for offset, word in {
            0x6A4: 0xF9414E68,
            0x6B0: 0x91403D09,
            0x714: 0xF943992A,
            0x718: 0x913C916C,
            0x71C: 0xF900018A,
        }.items():
            struct.pack_into("<I", arm_init, offset, word)
        symbols = {
            recover_g17_abi.BASE_CONFIGURE_DEVICE: configure_address,
            recover_g17_abi.G17_DEFAULT_MCACHE_WRITES: getter_address,
        }
        code = {
            recover_g17_abi.BASE_CONFIGURE_DEVICE: (
                configure_address,
                bytes(configure),
            ),
            recover_g17_abi.G17_DEFAULT_MCACHE_WRITES: (getter_address, getter),
        }
        with (
            mock.patch.object(recover_g17_abi, "macho_symbols", return_value=symbols),
            mock.patch.object(
                recover_g17_abi,
                "recover_vtable_target",
                return_value=getter_address,
            ),
            mock.patch.object(
                recover_g17_abi,
                "symbol_code",
                side_effect=lambda _image, name: code[name],
            ),
        ):
            recovered = recover_g17_abi.recover_g17_default_mcache_writes(
                b"", bytes(arm_init)
            )

        self.assertEqual(recovered["offset"], 0xF24)
        self.assertEqual(recovered["value"], 0x0000000607800004)
        self.assertEqual(recovered["source_offset"], 0xF730)

    def test_recovers_g17_enabled_usc_config(self) -> None:
        configure_address = 0x100000
        getter_address = 0x200000
        configure = bytearray(0x510)
        for offset, word in {
            0x34: 0x529EE508,
            0x38: 0x8B080018,
            0x44: 0x5295D014,
            0x48: 0x72BFFFD4,
            0x50C: 0xF9000F14,
        }.items():
            struct.pack_into("<I", configure, offset, word)
        getter_words = {
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
        }
        getter = bytearray(0x44)
        for offset, word in getter_words.items():
            struct.pack_into("<I", getter, offset, word)
        arm_init = bytearray(0xF24)
        for offset, word in {
            0xED4: 0xF9414E60,
            0xEE8: 0xD2815411,
            0xEEC: 0x8B110210,
            0xEF0: 0xF9400208,
            0xEF8: 0xD73F0910,
            0xEFC: 0xF9415E68,
            0xF08: 0x913E310A,
            0xF0C: 0xB90F8900,
            0xF10: 0xF9414E6B,
            0xF14: 0x529EE80C,
            0xF18: 0x8B0C016C,
            0xF1C: 0xF940018C,
            0xF20: 0xF900014C,
        }.items():
            struct.pack_into("<I", arm_init, offset, word)
        symbols = {
            recover_g17_abi.BASE_CONFIGURE_DEVICE: configure_address,
            recover_g17_abi.G17_GET_ENABLED_NUM_USCS: getter_address,
        }
        code = {
            recover_g17_abi.BASE_CONFIGURE_DEVICE: (
                configure_address,
                bytes(configure),
            ),
            recover_g17_abi.G17_GET_ENABLED_NUM_USCS: (
                getter_address,
                bytes(getter),
            ),
        }
        with (
            mock.patch.object(recover_g17_abi, "macho_symbols", return_value=symbols),
            mock.patch.object(
                recover_g17_abi,
                "recover_vtable_target",
                return_value=getter_address,
            ),
            mock.patch.object(
                recover_g17_abi,
                "symbol_code",
                side_effect=lambda _image, name: code[name],
            ),
        ):
            recovered = recover_g17_abi.recover_g17_enabled_usc_config(
                b"", bytes(arm_init)
            )

        self.assertEqual(recovered["enabled_usc_count"]["offset"], 0xF88)
        self.assertEqual(recovered["fixed_value"]["offset"], 0xF8C)
        self.assertEqual(recovered["fixed_value"]["value"], 0x00000000FFFEAE80)

    def test_recovers_g17_setup_config_constants(self) -> None:
        configure = bytearray(0x924)
        for offset, word in {
            0x34: 0x529EE508,
            0x38: 0x8B080018,
            0x52C: 0xB907067F,
            0x5A8: 0x6F00E401,
            0x5AC: 0x3D802F01,
            0x5B8: 0xFC044301,
            0x918: 0x52800008,
            0x91C: 0x52800629,
            0x920: 0xB9004709,
        }.items():
            struct.pack_into("<I", configure, offset, word)
        arm_setup = bytearray(0x2FAC)
        for offset, word in {
            0x28: 0xF9414E68,
            0x34: 0x529EED8A,
            0x38: 0x8B0A010A,
            0x44: 0xF9415E6C,
            0x5C: 0xB940014B,
            0x60: 0xB90F4D8B,
            0x64: 0x3CC6C140,
            0x68: 0x3D83DD80,
            0x2FA0: 0xB9470509,
            0x2FA4: 0xF9415E6A,
            0x2FA8: 0xB90EDD49,
        }.items():
            struct.pack_into("<I", arm_setup, offset, word)

        recovered = recover_g17_abi.recover_g17_setup_config_constants(
            bytes(configure), bytes(arm_setup)
        )

        self.assertEqual(recovered["fixed_u32"]["offset"], 0xF4C)
        self.assertEqual(recovered["fixed_u32"]["value"], 0x31)
        self.assertEqual(
            list(recovered["zero_u32"]),
            ["0xedc", "0xf70", "0xf74", "0xf78", "0xf7c"],
        )

    def test_recovers_g17_uat_config_flag(self) -> None:
        pi_address = 0x100000
        g17_address = 0x200000
        pi_start = bytearray(0x4C)
        for offset, word in {
            0x18: 0x91407008,
            0x1C: 0x912E8108,
            0x20: 0x529EEE89,
            0x24: 0x8B090009,
            0x3C: 0x52800088,
            0x40: 0xB9000128,
            0x44: 0x52800028,
            0x48: 0x39001528,
        }.items():
            struct.pack_into("<I", pi_start, offset, word)
        g17_start = bytearray(0x1E4)
        for offset, word in {
            0x1D4: 0xAA1303E0,
            0x1D8: 0xAA1403E1,
            0x1DC: bl(g17_address + 0x1DC, pi_address),
            0x1E0: 0x340012E0,
        }.items():
            struct.pack_into("<I", g17_start, offset, word)
        arm_init = bytearray(0x4B0)
        for offset, word in {
            0x498: 0x529EEE89,
            0x49C: 0x8B090009,
            0x4A0: 0xB9400129,
            0x4A4: 0x7100013F,
            0x4A8: 0x1A9F07E9,
            0x4AC: 0xB90FAD09,
        }.items():
            struct.pack_into("<I", arm_init, offset, word)
        symbols = {
            recover_g17_abi.PI300_ACCELERATOR_START: pi_address,
            recover_g17_abi.G17_ACCELERATOR_START: g17_address,
        }
        code = {
            recover_g17_abi.PI300_ACCELERATOR_START: (
                pi_address,
                bytes(pi_start),
            ),
            recover_g17_abi.G17_ACCELERATOR_START: (
                g17_address,
                bytes(g17_start),
            ),
        }
        with (
            mock.patch.object(recover_g17_abi, "macho_symbols", return_value=symbols),
            mock.patch.object(
                recover_g17_abi,
                "symbol_code",
                side_effect=lambda _image, name: code[name],
            ),
        ):
            recovered = recover_g17_abi.recover_g17_uat_config_flag(
                b"", bytes(arm_init)
            )

        self.assertEqual(recovered["offset"], 0xFAC)
        self.assertEqual(recovered["value"], 1)
        self.assertEqual(recovered["source_value"], 4)

    def test_recovers_g17_gptbat_base(self) -> None:
        getter_address = 0x100000
        new_monitor_address = 0x200000
        monitor_init_address = 0x300000
        descriptor_getter_address = 0x400000
        register_reader_address = 0x500000
        setup_address = 0x600000
        property_address = 0x700123
        physical_helper_address = 0x800000

        getter = bytearray(0x60)
        for offset, word in {
            0x00: 0xD503245F,
            0x04: 0x91407008,
            0x08: 0x912CC108,
            0x0C: 0xF9400100,
            0x30: 0xD2802B11,
            0x34: 0x8B110210,
            0x38: 0xF9400208,
            0x40: 0xD73F0910,
            0x58: b(getter_address + 0x58, physical_helper_address),
            0x5C: 0xD65F03C0,
        }.items():
            struct.pack_into("<I", getter, offset, word)

        monitor_init = bytearray(0x204)
        for offset, word in {
            0xDC: adrp(monitor_init_address + 0xDC, property_address, 1),
            0xE0: add_immediate(1, 1, property_address & 0xFFF),
            0xF0: 0xAA0003F7,
            0xF4: 0xB4000220,
            0xF8: 0xF9400270,
            0x108: 0xD2802711,
            0x10C: 0x8B110210,
            0x110: 0xF9400208,
            0x114: 0xAA1303E0,
            0x11C: 0xD73F0910,
            0x120: 0xAA1503E1,
            0x124: 0x52800062,
            0x128: bl(monitor_init_address + 0x128, physical_helper_address),
            0x12C: 0xAA0003F4,
            0x130: 0xB5000140,
            0x1F8: 0xB40000D7,
            0x1FC: 0xA9015A74,
            0x200: 0xF9001260,
        }.items():
            struct.pack_into("<I", monitor_init, offset, word)

        descriptor_getter = b"".join(
            struct.pack("<I", word)
            for word in (0xD503245F, 0xF9400800, 0xD65F03C0)
        )
        register_reader = bytearray(0x44)
        for offset, word in {
            0x1C: 0xD2803A11,
            0x20: 0x8B110210,
            0x24: 0xF9400208,
            0x28: 0x52900581,
            0x2C: 0x72A01A01,
            0x34: 0xD73F0910,
            0x38: 0xD3727C00,
            0x40: 0xD65F0FFF,
        }.items():
            struct.pack_into("<I", register_reader, offset, word)
        setup = bytearray(0xAC)
        for offset, word in {
            0x8C: 0xD2802B11,
            0x90: 0x8B110210,
            0x94: 0xF9400208,
            0x98: 0xAA1303E0,
            0xA0: 0xD73F0910,
            0xA4: bl(setup_address + 0xA4, physical_helper_address),
            0xA8: 0xD34EA402,
        }.items():
            struct.pack_into("<I", setup, offset, word)
        arm_init = bytearray(0x4E0)
        for offset, word in {
            0x4B0: 0xF9400010,
            0x4C0: 0xD2823A11,
            0x4C4: 0x8B110210,
            0x4C8: 0xF9400208,
            0x4D0: 0xD73F0910,
            0x4D4: 0xF9415E68,
            0x4D8: 0x9140090A,
            0x4DC: 0xF907D900,
        }.items():
            struct.pack_into("<I", arm_init, offset, word)

        symbols = {
            recover_g17_abi.ACCELERATOR_GET_GPTBAT_BASE: getter_address,
            recover_g17_abi.PI300_NEW_SECURE_MONITOR: new_monitor_address,
            recover_g17_abi.SECURE_MONITOR_INIT: monitor_init_address,
            recover_g17_abi.SECURE_MONITOR_GET_GPTBAT_DESC: descriptor_getter_address,
            recover_g17_abi.PI300_READ_GPTBAT_BASE: register_reader_address,
            recover_g17_abi.PI300_SETUP_MMU_CONFIG: setup_address,
        }
        code = {
            recover_g17_abi.ACCELERATOR_GET_GPTBAT_BASE: (
                getter_address,
                bytes(getter),
            ),
            recover_g17_abi.SECURE_MONITOR_INIT: (
                monitor_init_address,
                bytes(monitor_init),
            ),
            recover_g17_abi.SECURE_MONITOR_GET_GPTBAT_DESC: (
                descriptor_getter_address,
                descriptor_getter,
            ),
            recover_g17_abi.PI300_READ_GPTBAT_BASE: (
                register_reader_address,
                bytes(register_reader),
            ),
            recover_g17_abi.PI300_SETUP_MMU_CONFIG: (
                setup_address,
                bytes(setup),
            ),
        }
        selected_targets = {
            (
                recover_g17_abi.G17_ACCELERATOR_VTABLE,
                recover_g17_abi.G17_NEW_SECURE_MONITOR_VTABLE_SLOT,
            ): new_monitor_address,
            (
                recover_g17_abi.G17_ACCELERATOR_VTABLE,
                recover_g17_abi.G17_GET_GPTBAT_BASE_VTABLE_SLOT,
            ): getter_address,
            (
                recover_g17_abi.PI300_SECURE_MONITOR_VTABLE,
                recover_g17_abi.SECURE_MONITOR_INIT_VTABLE_SLOT,
            ): monitor_init_address,
            (
                recover_g17_abi.PI300_SECURE_MONITOR_VTABLE,
                recover_g17_abi.SECURE_MONITOR_READ_GPTBAT_BASE_VTABLE_SLOT,
            ): register_reader_address,
            (
                recover_g17_abi.PI300_SECURE_MONITOR_VTABLE,
                recover_g17_abi.SECURE_MONITOR_GET_GPTBAT_DESC_VTABLE_SLOT,
            ): descriptor_getter_address,
        }
        with (
            mock.patch.object(recover_g17_abi, "macho_symbols", return_value=symbols),
            mock.patch.object(
                recover_g17_abi,
                "recover_vtable_target",
                side_effect=lambda _image, vtable, slot: selected_targets[(vtable, slot)],
            ),
            mock.patch.object(
                recover_g17_abi,
                "symbol_code",
                side_effect=lambda _image, name: code[name],
            ),
            mock.patch.object(recover_g17_abi, "virtual_to_file", return_value=0),
        ):
            recovered = recover_g17_abi.recover_g17_gptbat_base(
                b"gptbat-ready\0", bytes(arm_init)
            )

        self.assertEqual(recovered["offset"], 0xFB0)
        self.assertEqual(recovered["bytes"], 8)
        self.assertEqual(recovered["ready_property"], "gptbat-ready")
        self.assertEqual(recovered["hardware_register"], 0xD0802C)
        self.assertEqual(recovered["uat_page_shift"], 14)

    def test_recovers_g17_gpu_identity_config(self) -> None:
        pi_address = 0x100000
        g17_address = 0x200000
        config_address = 0x300000
        pi = bytearray(0x580)
        for offset, word in {
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
        }.items():
            struct.pack_into("<I", pi, offset, word)
        g17 = bytearray(0x34)
        for offset, word in {
            0x10: 0xAA0103F3,
            0x14: bl(g17_address + 0x14, pi_address),
            0x20: 0xBC089260,
            0x24: 0x3902127F,
            0x30: 0xD65F0FFF,
        }.items():
            struct.pack_into("<I", g17, offset, word)
        config = bytearray(0x50)
        for offset, word in {
            0x08: 0x3DC12100,
            0x0C: 0x3DC12501,
            0x10: 0x3DC12902,
            0x14: 0x3DC12D03,
            0x3C: 0xAD019023,
            0x40: 0xAD008821,
            0x44: 0x3D800020,
            0x4C: 0xD65F03C0,
        }.items():
            struct.pack_into("<I", config, offset, word)
        base_init = bytearray(0x168C)
        for offset, word in {
            0x1678: 0xF9414E69,
            0x167C: 0xFD425120,
            0x1680: 0xFD07DD00,
            0x1684: 0xB944B129,
            0x1688: 0xB90FC109,
        }.items():
            struct.pack_into("<I", base_init, offset, word)
        symbols = {
            recover_g17_abi.PI300_READ_CHIP_INFO: pi_address,
            recover_g17_abi.G17_READ_CHIP_INFO: g17_address,
            recover_g17_abi.DEVICE_USER_GET_CONFIG: config_address,
        }
        code = {
            recover_g17_abi.PI300_READ_CHIP_INFO: (pi_address, bytes(pi)),
            recover_g17_abi.G17_READ_CHIP_INFO: (g17_address, bytes(g17)),
            recover_g17_abi.DEVICE_USER_GET_CONFIG: (
                config_address,
                bytes(config),
            ),
        }
        with (
            mock.patch.object(recover_g17_abi, "macho_symbols", return_value=symbols),
            mock.patch.object(
                recover_g17_abi,
                "recover_vtable_target",
                return_value=g17_address,
            ),
            mock.patch.object(
                recover_g17_abi,
                "symbol_code",
                side_effect=lambda _image, name: code[name],
            ),
        ):
            recovered = recover_g17_abi.recover_g17_gpu_identity_config(
                b"", bytes(base_init)
            )

        self.assertEqual(recovered["core_type"]["offset"], 0xFB8)
        self.assertEqual(recovered["core_type"]["selector_value"], 0x22)
        self.assertEqual(recovered["revision_id"]["c0_decoder_value"], 4)
        self.assertEqual(recovered["active_core_count"]["offset"], 0xFC0)

    def test_recovers_g17_feature_defaults(self) -> None:
        base_address = 0x100000
        pi_address = 0x101000
        g17_address = 0x102000
        base_init = bytearray(0x13D8)
        for offset, word in {
            0x1398: 0xF9414E60,
            0x139C: 0xB946D008,
            0x13CC: 0xB946D00B,
            0x13D0: 0x530A296B,
            0x13D4: 0xB90EC12B,
        }.items():
            struct.pack_into("<I", base_init, offset, word)

        pi_code = bytearray(0xAC)
        struct.pack_into("<I", pi_code, 0x48, bl(pi_address + 0x48, base_address))
        for offset, word in {
            0x84: 0xF9436A68,
            0x9C: 0x52909809,
            0xA0: 0x72B00029,
            0xA4: 0xAA090108,
            0xA8: 0xF9036A68,
        }.items():
            struct.pack_into("<I", pi_code, offset, word)

        g17_code = bytearray(0xA8)
        struct.pack_into("<I", g17_code, 0x70, bl(g17_address + 0x70, pi_address))
        for offset, word in {
            0x94: 0xF9436A68,
            0x98: 0xD2A30049,
            0x9C: 0xF2E00029,
            0xA0: 0xAA090108,
            0xA4: 0xF9036A68,
        }.items():
            struct.pack_into("<I", g17_code, offset, word)

        symbols = {
            recover_g17_abi.BASE_CONFIGURE_DEVICE: base_address,
            recover_g17_abi.PI300_CONFIGURE_DEVICE: pi_address,
            recover_g17_abi.G17_CONFIGURE_DEVICE: g17_address,
        }
        code = {
            recover_g17_abi.PI300_CONFIGURE_DEVICE: (pi_address, bytes(pi_code)),
            recover_g17_abi.G17_CONFIGURE_DEVICE: (g17_address, bytes(g17_code)),
        }
        with (
            mock.patch.object(recover_g17_abi, "macho_symbols", return_value=symbols),
            mock.patch.object(
                recover_g17_abi, "recover_vtable_target", return_value=g17_address
            ),
            mock.patch.object(
                recover_g17_abi,
                "symbol_code",
                side_effect=lambda _image, name: code[name],
            ),
        ):
            recovered = recover_g17_abi.recover_g17_feature_defaults(
                b"", bytes(base_init)
            )

        self.assertEqual(recovered["pi300_unconditional_mask"], 0x800184C0)
        self.assertEqual(recovered["fixed_u32"], {"0xec0": 1})

    def test_recovers_g17_relative_boost_frequency_table(self) -> None:
        setup_address = 0x100000
        setup_code = bytearray(0x550)
        for offset, word in {
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
        }.items():
            struct.pack_into("<I", setup_code, offset, word)

        arm_power = bytearray(0xDBC)
        for offset, word in {
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
        }.items():
            struct.pack_into("<I", arm_power, offset, word)

        image = b"gpu-perf-base-pstate\0"
        with (
            mock.patch.object(
                recover_g17_abi,
                "macho_symbols",
                return_value={recover_g17_abi.INIT_BASE_SETUP_CONFIG: setup_address},
            ),
            mock.patch.object(
                recover_g17_abi,
                "symbol_code",
                return_value=(setup_address, bytes(setup_code)),
            ),
            mock.patch.object(recover_g17_abi, "virtual_to_file", return_value=0),
        ):
            recovered = recover_g17_abi.recover_g17_relative_boost_frequency_table(
                image, bytes(arm_power)
            )

        self.assertEqual(recovered["offset"], 0x1908)
        self.assertEqual(recovered["base_state_property"], "gpu-perf-base-pstate")
        self.assertEqual(recovered["maximum_state_value"], 100)

    def test_recovers_g17_sram_power_scale_table(self) -> None:
        setup = bytearray(0x250)
        for offset, word in {
            0x224: 0xF9414E60,
            0x228: 0xB94F3661,
            0x22C: 0xF9400010,
            0x23C: 0xD2819811,
            0x240: 0x8B110210,
            0x244: 0xF9400208,
            0x24C: 0xD73F0910,
        }.items():
            struct.pack_into("<I", setup, offset, word)

        configure = bytearray(0xA8)
        for offset, word in {
            0x94: 0xF9436A68,
            0x98: 0xD2A30049,
            0x9C: 0xF2E00029,
            0xA0: 0xAA090108,
            0xA4: 0xF9036A68,
        }.items():
            struct.pack_into("<I", configure, offset, word)

        producer = bytearray(0x88)
        for offset, word in {
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
        }.items():
            struct.pack_into("<I", producer, offset, word)

        sram = bytearray(0xD4)
        for offset, word in {
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
        }.items():
            struct.pack_into("<I", sram, offset, word)

        base_power = bytearray(0x44)
        for offset, word in {
            0x20: 0xF9416C00,
            0x24: 0x5283BA01,
            0x28: 0x72A00021,
            0x2C: 0x94AA6439,
            0x30: 0xF9416E68,
            0x34: 0x91029100,
            0x38: 0x9133C261,
            0x3C: 0x52802C02,
            0x40: 0x94AA63C8,
        }.items():
            struct.pack_into("<I", base_power, offset, word)

        arm_power = bytearray(0x53C)
        for offset, word in {
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
        }.items():
            struct.pack_into("<I", arm_power, offset, word)

        symbols = {
            recover_g17_abi.INIT_BASE_SETUP_CONFIG: 0x100000,
            recover_g17_abi.G17_CONFIGURE_DEVICE: 0x101000,
            recover_g17_abi.G17_POPULATE_POWER_ESTIMATION_CONFIG: 0x102000,
            recover_g17_abi.G17_POPULATE_SRAM_POWER_SCALE_DATA: 0x103000,
            recover_g17_abi.G17_POPULATE_CHIP_LEAKAGE_DATA: 0x104000,
        }
        code = {
            recover_g17_abi.INIT_BASE_SETUP_CONFIG: bytes(setup),
            recover_g17_abi.G17_CONFIGURE_DEVICE: bytes(configure),
            recover_g17_abi.G17_POPULATE_POWER_ESTIMATION_CONFIG: bytes(producer),
            recover_g17_abi.G17_POPULATE_SRAM_POWER_SCALE_DATA: bytes(sram),
        }
        with (
            mock.patch.object(recover_g17_abi, "macho_symbols", return_value=symbols),
            mock.patch.object(
                recover_g17_abi,
                "recover_vtable_target",
                side_effect=lambda _image, _vtable, slot: {
                    recover_g17_abi.G17_POPULATE_POWER_ESTIMATION_VTABLE_SLOT: symbols[
                        recover_g17_abi.G17_POPULATE_POWER_ESTIMATION_CONFIG
                    ],
                    recover_g17_abi.G17_POPULATE_SRAM_POWER_SCALE_VTABLE_SLOT: symbols[
                        recover_g17_abi.G17_POPULATE_SRAM_POWER_SCALE_DATA
                    ],
                    recover_g17_abi.G17_POPULATE_CHIP_LEAKAGE_VTABLE_SLOT: symbols[
                        recover_g17_abi.G17_POPULATE_CHIP_LEAKAGE_DATA
                    ],
                }[slot],
            ),
            mock.patch.object(
                recover_g17_abi,
                "symbol_code",
                side_effect=lambda _image, name: (symbols[name], code[name]),
            ),
        ):
            recovered = recover_g17_abi.recover_g17_sram_power_scale_table(
                b"", bytes(base_power), bytes(arm_power)
            )

        self.assertEqual(recovered["offset"], 0x1848)
        self.assertEqual(recovered["raw_float"], 0x3F828F5C)
        self.assertAlmostEqual(recovered["value"], 1.02)
        self.assertEqual(recovered["state_count_source_offset"], 0x1B310)
        self.assertEqual(recovered["feature_bit"], 17)

    def test_recovers_zero_g17_static_power_scale_table(self) -> None:
        alloc_address = 0x100000
        type_view_address = 0x200330
        operator_new_address = 0x500000
        kalloc_address = 0x501000
        static_address = 0x600000

        alloc = bytearray(0x9B0)
        for offset, word in {
            0x18: adrp(alloc_address + 0x18, type_view_address, 0),
            0x1C: add_immediate(0, 0, 0x330),
            0x20: movz_w(1, 0x2920),
            0x24: bl(alloc_address + 0x24, operator_new_address),
            0x28: 0xAA0003F3,
        }.items():
            struct.pack_into("<I", alloc, offset, word)

        operator_new = bytearray(0x64)
        for offset, word in {
            0x14: 0xB9402C08,
            0x18: 0x92405D08,
            0x1C: 0xEB08003F,
            0x20: 0x54000129,
            0x44: 0x52800081,
            0x48: bl(operator_new_address + 0x48, kalloc_address),
        }.items():
            struct.pack_into("<I", operator_new, offset, word)

        sram = bytearray(0xC8)
        for offset, word in {
            0x0C: 0xB9400108,
            0x1C: 0xF9400129,
            0xB4: 0x8B0A0929,
            0xB8: 0x91008129,
            0xC4: 0xB800452A,
        }.items():
            struct.pack_into("<I", sram, offset, word)

        leakage = bytearray(0x540)
        for offset, word in {
            0x2C0: 0xF942DABA,
            0x2C4: 0x91394348,
            0x2C8: 0x913A4349,
            0x330: 0x913B4348,
            0x334: 0x913C4349,
            0x3FC: 0x913C8348,
            0x400: 0x913CA349,
        }.items():
            struct.pack_into("<I", leakage, offset, word)

        arm_power = bytearray(0x53C)
        for offset, word in {
            0x40C: 0x91041108,
            0x410: 0x5283110C,
            0x414: 0x8B0C016B,
            0x418: 0x5280020C,
            0x528: 0xBC404500,
            0x52C: 0xBC004560,
            0x534: 0xF100058C,
            0x538: 0x54FFF721,
        }.items():
            struct.pack_into("<I", arm_power, offset, word)

        driver_image_bytes = bytearray(0x40)
        struct.pack_into("<I", driver_image_bytes, 0x2C, 0x2920)
        driver_image = bytes(driver_image_bytes)
        kernel_image = b"kernel"
        driver_symbols = {
            recover_g17_abi.G17_ARM_FIRMWARE_ASC_META_ALLOC: alloc_address,
            recover_g17_abi.G17_POPULATE_SRAM_POWER_SCALE_DATA: 0x300000,
            recover_g17_abi.G17_POPULATE_CHIP_LEAKAGE_DATA: 0x301000,
            recover_g17_abi.G17_POPULATE_STATIC_POWER_DATA: static_address,
        }
        kernel_symbols = {
            recover_g17_abi.OS_OBJECT_TYPED_OPERATOR_NEW: operator_new_address,
            recover_g17_abi.KALLOC_TYPE_IMPL: kalloc_address,
        }
        driver_code = {
            recover_g17_abi.G17_ARM_FIRMWARE_ASC_META_ALLOC: bytes(alloc),
            recover_g17_abi.G17_POPULATE_SRAM_POWER_SCALE_DATA: bytes(sram),
            recover_g17_abi.G17_POPULATE_CHIP_LEAKAGE_DATA: bytes(leakage),
            recover_g17_abi.G17_POPULATE_STATIC_POWER_DATA: struct.pack(
                "<2I", 0xD503245F, 0xD65F03C0
            ),
        }
        with (
            mock.patch.object(
                recover_g17_abi,
                "macho_symbols",
                side_effect=lambda image: kernel_symbols
                if image == kernel_image
                else driver_symbols,
            ),
            mock.patch.object(
                recover_g17_abi,
                "symbol_code",
                side_effect=lambda image, name: (
                    (kernel_symbols[name], bytes(operator_new))
                    if image == kernel_image
                    else (driver_symbols[name], driver_code[name])
                ),
            ),
            mock.patch.object(
                recover_g17_abi, "virtual_to_file", return_value=0
            ),
            mock.patch.object(
                recover_g17_abi,
                "recover_vtable_target",
                return_value=static_address,
            ),
        ):
            recovered = recover_g17_abi.recover_g17_static_power_scale_table(
                driver_image, kernel_image, bytes(arm_power)
            )

        self.assertEqual(recovered["offset"], 0x1888)
        self.assertEqual(recovered["values"], [0] * 16)
        self.assertEqual(recovered["allocator_flag_name"], "Z_ZERO")
        self.assertEqual(recovered["type_bytes"], 0x2920)
        self.assertEqual(recovered["static_provider_vtable_slot"], 0xCE0)

    def _linear_power_transfer_fixtures(self) -> tuple[bytes, dict[str, object]]:
        power_address = 0x600000
        linear_address = power_address + 0x958 - 0x55734
        max_power_address = 0x700000
        cs_power_address = 0x710000
        leakage_address = 0x720000
        vdd_address = 0x730000
        afr_address = 0x740000

        image = bytearray(0x60000)
        count_va = 0x1000
        struct.pack_into("<I", image, count_va, 2)
        tables = {
            "vdd_default": 0x2000,
            "vdd_variant": 0x3000,
            "afr_default": 0x4000,
            "afr_variant": 0x5000,
        }
        for base in tables.values():
            struct.pack_into("<11d", image, base, 1000.0, *([1.0] * 10))
            struct.pack_into("<11d", image, base + 0x58, -1.0, *([1.0] * 10))

        selector_table = 0x6000
        descriptor_table = selector_table + 0x20
        struct.pack_into("<8I", image, selector_table, 0, 1, 2, 3, 0, 1, 2, 3)
        descriptors = (
            (0x40000000, 0, 0x198, 8, 0x3FFF, 0, 0, 0, 0, 0),
            (0x40000000, 1, 0x198, 22, 0x3FF, 0, 0x19C, 0, 0xF, 10),
            (0x40000000, 1, 0x198, 22, 0x3FF, 0, 0x19C, 0, 0xF, 10),
            (0x40000000, 0, 0x198, 8, 0x3FFF, 0, 0, 0, 0, 0),
        )
        for index, descriptor in enumerate(descriptors):
            struct.pack_into(
                "<10I", image, descriptor_table + index * 0x28, *descriptor
            )

        arm_power = bytearray(0xC00)
        for offset, word in {
            0x948: 0xF9415E68,
            0x94C: 0x52831909,
            0x950: 0x8B090101,
            0x954: 0x52800002,
            0x958: 0x97FEAA33,
            0x95C: 0xF9414E68,
            0x960: 0x91407109,
            0x964: 0x9113A12A,
            0x968: 0xF9415E69,
            0x96C: 0xB940014E,
            0x974: 0x710041DF,
            0x97C: 0x5283290B,
            0x980: 0x8B0B012B,
            0x984: 0xB944ED0C,
            0x98C: 0x5299460D,
            0x990: 0x72A0002D,
            0x994: 0x510005CF,
            0x998: 0xD37DF1EE,
            0xB8C: 0x4B0E01EF,
            0xB94: 0x52800C91,
            0xBA0: 0x4B0E0040,
            0xBA4: 0x1B117C00,
            0xBA8: 0x1ACF0800,
            0xBAC: 0xB82C7960,
            0xBB8: 0x91002210,
            0xBBC: 0x910021AD,
        }.items():
            struct.pack_into("<I", arm_power, offset, word)

        linear = bytearray(0x460)
        for offset, word in {
            0x010: 0x91406C08,
            0x014: 0x910C4108,
            0x018: 0xB940010B,
            0x01C: 0x7100417F,
            0x024: 0x5298C609,
            0x028: 0x72A00029,
            0x02C: 0xB944E40D,
            0x034: 0x5100056C,
            0x038: 0xD37AE58A,
            0x2DC: 0x4B0A018B,
            0x2F0: 0x52800C8E,
            0x300: 0x1B0E7DEF,
            0x304: 0x1ACB09EF,
            0x320: 0xB900022F,
        }.items():
            struct.pack_into("<I", linear, offset, word)

        max_power = bytearray(0x3E0)
        for offset, word in {
            0x034: 0xB944E415,
            0x038: 0xB944EC18,
            0x088: 0x9118C131,
            0x090: 0x9128C121,
            0x0A4: 0x52A88F44,
            0x0A8: 0x529BD065,
            0x0AC: 0x72A86365,
            0x0B8: 0x1AD80ABA,
            0x244: 0x529AE148,
            0x248: 0x72A7F468,
            0x258: 0x52866668,
            0x25C: 0x72A83428,
            0x278: 0x528E8009,
            0x27C: 0x72A8E7A9,
            0x308: 0xB912DB08,
        }.items():
            struct.pack_into("<I", max_power, offset, word)

        cs_power = bytearray(0x258)
        for offset, word in {
            0x030: 0xB944A009,
            0x034: 0x7100853F,
            0x038: 0x52933348,
            0x03C: 0x72A835A8,
            0x044: 0x52947AE8,
            0x048: 0x72A82888,
            0x068: 0x5292D90A,
            0x06C: 0x528C1C0B,
            0x080: 0x9128C14D,
            0x084: 0x9114E2B7,
            0x1D0: 0xB90502E8,
        }.items():
            struct.pack_into("<I", cs_power, offset, word)

        leakage = bytearray(0x540)
        for offset, word in {
            0xB8: 0xD2880000,
            0xBC: movk(0, 0x8837, 16),
            0xC0: movk(0, 0x23, 32),
            0xC4: 0x52820001,
            0xCC: bl(leakage_address + 0xCC, 0x800000),
            0x14C: 0xB944E6BB,
            0x170: adrp(leakage_address + 0x170, descriptor_table, 8),
            0x174: add_immediate(8, 8, descriptor_table & 0xFFF),
            0x18C: adrp(leakage_address + 0x18C, selector_table, 12),
            0x190: add_immediate(12, 12, selector_table & 0xFFF),
            0x1A0: 0xB9400210,
            0x1A4: 0x29444620,
            0x1AC: 0x9AD12210,
            0x1B0: 0x9ACE25AD,
            0x1B4: 0x8A0F01AD,
            0x1B8: 0xAA0D020D,
            0x1BC: 0x9E2301A0,
            0x1C0: 0x1E202800,
            0x1C8: 0xB9419F0D,
            0x1CC: 0x53043DAD,
            0x1D0: 0x1E03FDA0,
            0x260: 0x9E2301A1,
            0x264: 0x1E212821,
            0x268: 0x1E200821,
            0x270: 0xB9419F0D,
            0x274: 0x53043DAD,
            0x278: 0x1E03F9A1,
            0x398: 0xB944EEB5,
            0x3AC: 0xB9419F08,
            0x3B0: 0xB941A309,
            0x3B4: 0x13886528,
            0x3B8: 0x531F2D08,
        }.items():
            struct.pack_into("<I", leakage, offset, word)

        def leakage_reader(address: int, default: int, variant: int) -> bytearray:
            code = bytearray(0x78)
            for offset, word in {
                0x10: adrp(address + 0x10, default, 8),
                0x14: add_immediate(8, 8, default & 0xFFF),
                0x1C: adrp(address + 0x1C, count_va, 8),
                0x20: 0xFD400000 | ((count_va & 0xFFF) // 8) << 10 | (8 << 5) | 3,
                0x38: adrp(address + 0x38, variant, 8),
                0x3C: add_immediate(8, 8, variant & 0xFFF),
            }.items():
                struct.pack_into("<I", code, offset, word)
            return code

        codes = {
            recover_g17_abi.G17_POPULATE_LINEAR_POWER_TRANSFER: (
                linear_address,
                bytes(linear),
            ),
            recover_g17_abi.G17_POPULATE_MAX_PERF_POWER: (
                max_power_address,
                bytes(max_power),
            ),
            recover_g17_abi.G17_POPULATE_MAX_PERF_POWER_CS: (
                cs_power_address,
                bytes(cs_power),
            ),
            recover_g17_abi.G17_POPULATE_CHIP_LEAKAGE: (
                leakage_address,
                bytes(leakage),
            ),
            recover_g17_abi.G17_CALCULATE_VDD_GPU_LEAKAGE: (
                vdd_address,
                bytes(
                    leakage_reader(
                        vdd_address, tables["vdd_default"], tables["vdd_variant"]
                    )
                ),
            ),
            recover_g17_abi.G17_CALCULATE_AFR_LEAKAGE: (
                afr_address,
                bytes(
                    leakage_reader(
                        afr_address, tables["afr_default"], tables["afr_variant"]
                    )
                ),
            ),
        }
        symbols = {
            recover_g17_abi.INIT_POWER_DATA: power_address,
            recover_g17_abi.G17_APPLY_LEAKAGE_EQUATION: 0x750000,
        } | {name: address for name, (address, _code) in codes.items()}
        slots = {
            recover_g17_abi.G17_POPULATE_MAX_PERF_POWER_VTABLE_SLOT: max_power_address,
            recover_g17_abi.G17_POPULATE_MAX_PERF_POWER_CS_VTABLE_SLOT: cs_power_address,
            recover_g17_abi.G17_CALCULATE_VDD_GPU_LEAKAGE_VTABLE_SLOT: vdd_address,
            recover_g17_abi.G17_CALCULATE_AFR_LEAKAGE_VTABLE_SLOT: afr_address,
            recover_g17_abi.G17_APPLY_LEAKAGE_EQUATION_VTABLE_SLOT: 0x750000,
            recover_g17_abi.G17_POPULATE_CHIP_LEAKAGE_VTABLE_SLOT: leakage_address,
        }
        return bytes(arm_power), {
            "image": bytes(image),
            "symbols": symbols,
            "codes": codes,
            "slots": slots,
        }

    def _run_linear_power_transfer(
        self, arm_power: bytes, fixtures: dict[str, object], slots=None
    ) -> dict[str, object]:
        codes = fixtures["codes"]
        with (
            mock.patch.object(
                recover_g17_abi, "macho_symbols", return_value=fixtures["symbols"]
            ),
            mock.patch.object(
                recover_g17_abi,
                "symbol_code",
                side_effect=lambda _image, name: codes[name],
            ),
            mock.patch.object(
                recover_g17_abi, "virtual_to_file", side_effect=lambda _image, a: a
            ),
            mock.patch.object(
                recover_g17_abi,
                "recover_vtable_target",
                side_effect=lambda _image, _vtable, slot: (
                    slots or fixtures["slots"]
                )[slot],
            ),
        ):
            return recover_g17_abi.recover_g17_linear_power_transfer_tables(
                fixtures["image"], arm_power
            )

    def test_recovers_g17_secondary_performance_block(self) -> None:
        code = bytearray(0x800)
        for offset, word in {
            0x740: 0x395416C8,
            0x744: 0x36000608,
            0x74C: 0xF9415E75,
            0x750: 0x52839B08,
            0x758: 0x52810901,
            0x760: 0xB94B5A88,
            0x764: 0x51000509,
            0x768: 0xB91CDAA9,
            0x77C: 0x52839B8A,
            0x784: 0x912E828B,
            0x788: 0x5283A38C,
            0x790: 0x529BD06D,
            0x794: 0x72A8636D,
            0x7A4: 0x9101016B,
            0x7A8: 0x9101018C,
            0x7B4: 0xB868792E,
            0x7B8: 0x9BAD7DCE,
            0x7BC: 0xD372FDCE,
            0x7C0: 0xB828794E,
            0x7C4: 0xB94B5E8E,
            0x7E0: 0xB9440211,
            0x7E4: 0xB90401F1,
        }.items():
            struct.pack_into("<I", code, offset, word)

        probe = bytearray(0xC78)
        struct.pack_into("<I", probe, 0xC2C, 0x3CC802A0)
        struct.pack_into("<I", probe, 0xC30, 0x3D814260)
        codes = {
            recover_g17_abi.INIT_POWER_DATA: (0xB00000, bytes(code)),
            recover_g17_abi.FAMILY_GET_PROBE_SCORE: (0xB10000, bytes(probe)),
        }
        with (
            mock.patch.object(
                recover_g17_abi,
                "macho_symbols",
                return_value={n: a for n, (a, _c) in codes.items()},
            ),
            mock.patch.object(
                recover_g17_abi,
                "symbol_code",
                side_effect=lambda _image, name: codes[name],
            ),
        ):
            recovered = recover_g17_abi.recover_g17_secondary_performance_block(b"")

        self.assertEqual(recovered["offset"], 0x1CD8)
        self.assertEqual(recovered["zeroed_bytes"], 0x848)
        self.assertEqual(recovered["frequency_offset"], 0x1CDC)
        self.assertEqual(recovered["voltage_offset"], 0x1D1C)
        self.assertEqual(recovered["sram_voltage_offset"], 0x211C)
        self.assertEqual(recovered["frequency_source"], 0x1BB60)
        self.assertEqual(recovered["gate_byte"], 0x505)
        # The block must fit inside the span the producer clears.
        self.assertEqual(recovered["trailing_bytes"], 4)
        # The gate is chip-info +0x85, which G17 never sets, so the block is
        # recovered for its layout but is not filled on this part.
        self.assertFalse(recovered["populated_on_g17"])
        self.assertEqual(recovered["gate_chip_info_byte"], 0x85)

    def test_recovers_g17_final_late_controls(self) -> None:
        driver = Path("build/kext/g17c/AGXG17X.macho")
        if not driver.exists():
            self.skipTest("extracted AGXG17X.macho is not available")
        recovered = recover_g17_abi.recover_g17_final_late_controls(
            driver.read_bytes()
        )
        self.assertEqual(recovered["literal_field"], {"config": 0x26C0, "value": 1})
        converted = recovered["converted_field"]
        self.assertEqual(converted["config"], 0x269C)
        self.assertEqual(converted["firmware_member"], 0x1AB8)
        # Both halves matter: identity converter, and a member only ever cleared.
        self.assertTrue(converted["identity"])
        self.assertEqual(converted["value"], 0)

    def test_recovers_g17_remaining_late_controls(self) -> None:
        driver = Path("build/kext/g17c/AGXG17X.macho")
        if not driver.exists():
            self.skipTest("extracted AGXG17X.macho is not available")
        recovered = recover_g17_abi.recover_g17_remaining_late_controls(
            driver.read_bytes()
        )

        # 48 bytes of ones, written as a store pair plus a single store.
        self.assertEqual(recovered["ones_run"], {"offset": 0x25BC, "bytes": 0x30, "value": 0xFF})
        self.assertEqual(recovered["copied_bytes"], {0x26F8: 0x6F0, 0x26F9: 0x6F8})
        # The guarded field would take a pair of ones, but its bit is clear.
        self.assertFalse(recovered["guarded"]["written"])
        self.assertEqual(recovered["guarded"]["would_be"], 0x100000001)

    def test_ones_run_stops_before_the_next_field(self) -> None:
        # The run must not reach +0x25ec, which the producer sets to zero
        # afterwards; overlapping would make the order matter.
        driver = Path("build/kext/g17c/AGXG17X.macho")
        if not driver.exists():
            self.skipTest("extracted AGXG17X.macho is not available")
        recovered = recover_g17_abi.recover_g17_remaining_late_controls(
            driver.read_bytes()
        )
        run = recovered["ones_run"]
        self.assertEqual(run["offset"] + run["bytes"], 0x25EC)

    def test_recovers_g17_cleared_accelerator_inputs(self) -> None:
        driver = Path("build/kext/g17c/AGXG17X.macho")
        if not driver.exists():
            self.skipTest("extracted AGXG17X.macho is not available")
        recovered = recover_g17_abi.recover_g17_cleared_accelerator_inputs(
            driver.read_bytes()
        )

        self.assertTrue(recovered["zeroed_allocation"])
        self.assertEqual(recovered["accelerator_bytes"], 0x1CBD0)
        self.assertEqual(
            recovered["fields"],
            {0x2544: 0x72C, 0x25F4: 0x730, 0x25F8: 0xF91C, 0x26A4: 0xF914, 0x26BC: 0xF958},
        )
        # Every member must lie inside the allocation it is cleared by.
        for member in recovered["cleared_members"]:
            self.assertLess(member, recovered["accelerator_bytes"])

    def test_idle_timer_store_is_not_an_accelerator_member_write(self) -> None:
        # A width-aware sweep flags idlePowerOffTimer's store at +0x728 as
        # covering +0x72c, but its base is the accelerator plus 0x13000, so the
        # store lands at +0x13728. Without that the field would look written.
        driver = Path("build/kext/g17c/AGXG17X.macho")
        if not driver.exists():
            self.skipTest("extracted AGXG17X.macho is not available")
        image = driver.read_bytes()
        _address, code = recover_g17_abi.symbol_code(
            image, recover_g17_abi.IDLE_POWER_OFF_TIMER
        )
        self.assertTrue(recover_g17_abi.stores_covering(code, 20, 0x72C))
        base = struct.unpack_from("<I", code, 0x2C)[0]
        decoded = recover_g17_abi.decode_add_immediate(base)
        self.assertIsNotNone(decoded)
        # Shifted add: the decoder already folds in the lsl #12.
        self.assertEqual((base >> 22) & 1, 1)
        self.assertEqual(decoded[2], 0x13000)
        # So the store lands well past the member the sweep flagged.
        self.assertEqual(decoded[2] + 0x728, 0x13728)

    def test_recovers_g17_unit_mask_field(self) -> None:
        driver = Path("build/kext/g17c/AGXG17X.macho")
        if not driver.exists():
            self.skipTest("extracted AGXG17X.macho is not available")
        recovered = recover_g17_abi.recover_g17_unit_mask_field(driver.read_bytes())

        self.assertEqual(recovered["config_offset"], 0x2554)
        self.assertEqual(recovered["identity_register"], 0xD04018)
        self.assertEqual(recovered["count_chip_info"], 0x50)
        self.assertEqual(recovered["count_accelerator_member"], 0x4D0)
        # The three products pair a low nibble with one 16 bits above it.
        self.assertEqual(
            [product["shifts"] for product in recovered["nibble_products"]],
            [[0, 16], [4, 20], [8, 24]],
        )

    def test_unit_mask_saturates_the_way_apple_builds_it(self) -> None:
        # Apple shifts in 64 bits and keeps the low word, so any count of 32 or
        # more is all ones; a count past 63 is saturated rather than wrapping.
        def mask(count: int) -> int:
            if count > 63:
                return 0xFFFFFFFF
            return (~(0xFFFFFFFFFFFFFFFF << count)) & 0xFFFFFFFF

        for count in (0, 1, 10, 31):
            self.assertEqual(mask(count), (1 << count) - 1)
        for count in (32, 40, 63, 64, 225):
            self.assertEqual(mask(count), 0xFFFFFFFF)

    def test_recovers_g17_core_count_gate(self) -> None:
        driver = Path("build/kext/g17c/AGXG17X.macho")
        if not driver.exists():
            self.skipTest("extracted AGXG17X.macho is not available")
        recovered = recover_g17_abi.recover_g17_core_count_gate(driver.read_bytes())

        self.assertEqual(recovered["config_offset"], 0x2570)
        self.assertTrue(recovered["gate"]["always_set"])
        self.assertEqual(recovered["selected"], "popcount")
        # The scaled core count is explicitly the path not taken.
        self.assertEqual(recovered["unused_fallback"]["accelerator_member"], 0x4B0)
        self.assertEqual(recovered["popcount_source"]["accelerator_member"], 0x490)
        # Knowing which producer runs is not the same as knowing the value.
        self.assertTrue(recovered["resolved"])

    def test_scaled_core_count_is_not_the_core_count_field_source(self) -> None:
        # chip_info_decode records the scaled column count at accelerator +0x4b0.
        # The gate proves that producer never runs, so the two recoveries must
        # agree that +0x4b0 is unused rather than one implying it is the source.
        driver = Path("build/kext/g17c/AGXG17X.macho")
        if not driver.exists():
            self.skipTest("extracted AGXG17X.macho is not available")
        image = driver.read_bytes()
        decode = recover_g17_abi.recover_g17_chip_info_decode(image)
        gate = recover_g17_abi.recover_g17_core_count_gate(image)
        scaled = decode["fields"]["scaled_column_count"]["accelerator_member"]
        self.assertEqual(scaled, gate["unused_fallback"]["accelerator_member"])
        self.assertNotEqual(scaled, gate["popcount_source"]["accelerator_member"])

    def test_recovers_g17_chip_info_decode(self) -> None:
        code = bytearray(0x61C)
        for offset, word in {
            0x19C: 0x53104EA8,
            0x1A0: 0xB9006E68,
            0x1A4: 0x53083EA9,
            0x1A8: 0x1B087D28,
            0x1AC: 0xB9006668,
            0x1B0: 0x12001EA9,
            0x1B4: 0xB9007A69,
            0x1B8: 0x1B097D09,
            0x1CC: 0x29062A69,
        }.items():
            struct.pack_into("<I", code, offset, word)

        with (
            mock.patch.object(
                recover_g17_abi,
                "macho_symbols",
                return_value={recover_g17_abi.PI300_READ_CHIP_INFO: 0xD00000},
            ),
            mock.patch.object(
                recover_g17_abi, "symbol_code", return_value=(0xD00000, bytes(code))
            ),
        ):
            recovered = recover_g17_abi.recover_g17_chip_info_decode(b"")

        fields = recovered["fields"]
        self.assertEqual(recovered["source_register"], 0xD04010)
        self.assertEqual(fields["power_group_count"]["chip_info"], 0x6C)
        self.assertEqual(fields["power_group_count"]["accelerator_member"], 0x4EC)
        self.assertEqual(fields["power_column_count"]["chip_info"], 0x64)
        self.assertEqual(fields["power_column_count"]["accelerator_member"], 0x4E4)
        self.assertEqual(fields["scaled_column_count"]["accelerator_member"], 0x4B0)

    def test_chip_info_power_dimensions_match_their_consumers(self) -> None:
        driver = Path("build/kext/g17c/AGXG17X.macho")
        if not driver.exists():
            self.skipTest("extracted AGXG17X.macho is not available")
        image = driver.read_bytes()
        decode = recover_g17_abi.recover_g17_chip_info_decode(image)["fields"]
        _, power_code = recover_g17_abi.symbol_code(
            image, recover_g17_abi.INIT_POWER_DATA
        )
        power = recover_g17_abi.recover_g17_linear_power_transfer_tables(
            image, power_code
        )
        tables = power["tables"]

        self.assertEqual(
            decode["power_column_count"]["accelerator_member"],
            tables[0]["matrix_column_count_offset"],
        )
        self.assertEqual(
            decode["power_group_count"]["accelerator_member"],
            tables[1]["matrix_column_count_offset"],
        )
        self.assertEqual(len(power["chip_leakage"]["core_selectors"]), 8)

    def test_recovers_g17_chip_info_registers(self) -> None:
        code = bytearray(0x61C)
        for offset, word in {
            0x03C: 0x5288001A,
            0x040: 0x72A01A1A,
            0x054: 0x52880001,
            0x058: 0x72A01A01,
            0x070: 0x91004341,
            0x08C: 0x91005341,
            0x0A8: 0x91006341,
            0x0C4: 0x91007341,
            0x0EC: 0x53187EE8,
            0x0F0: 0x71002D1F,
            0x0F8: 0x53105EE8,
            0x0FC: 0x7100111F,
            0x104: 0x71000D1F,
            0x10C: 0x7100091F,
            0x114: 0x52800148,
            0x118: 0xB9007668,
            0x11C: 0x52800408,
            0x120: 0xB9002268,
            0x564: 0x52800288,
            0x56C: 0x52800428,
            0x578: 0x52800448,
            0x57C: 0xB9002268,
        }.items():
            struct.pack_into("<I", code, offset, word)

        with (
            mock.patch.object(
                recover_g17_abi,
                "macho_symbols",
                return_value={recover_g17_abi.PI300_READ_CHIP_INFO: 0xC00000},
            ),
            mock.patch.object(
                recover_g17_abi, "symbol_code", return_value=(0xC00000, bytes(code))
            ),
        ):
            recovered = recover_g17_abi.recover_g17_chip_info_registers(b"")

        self.assertEqual(recovered["register_block"], 0xD04000)
        self.assertEqual(recovered["registers"]["version"], 0xD04000)
        self.assertEqual(recovered["registers"]["cluster_config"], 0xD04010)
        self.assertEqual(recovered["registers"]["identity_1c"], 0xD0401C)
        self.assertEqual(recovered["version_family_byte"], {"shift": 24, "value": 0xB})
        self.assertEqual(recovered["variants"], {2: 0x20, 3: 0x21, 4: 0x22})
        # The variant must land where the power model reads it.
        self.assertEqual(recovered["accelerator_variant_member"], 0x4A0)

    def test_chip_variant_reaches_the_power_model_field(self) -> None:
        # The relay delta and the chip-info variant offset must compose to the
        # accelerator member the CS power producer compares against 0x21.
        driver = Path("build/kext/g17c/AGXG17X.macho")
        if not driver.exists():
            self.skipTest("extracted AGXG17X.macho is not available")
        image = driver.read_bytes()
        registers = recover_g17_abi.recover_g17_chip_info_registers(image)
        relay = recover_g17_abi.recover_g17_core_mask_relay(image)
        self.assertEqual(
            relay["record_delta"] + registers["chip_info_variant_offset"],
            registers["accelerator_variant_member"],
        )
        power = recover_g17_abi.recover_g17_linear_power_transfer_tables(
            image,
            recover_g17_abi.symbol_code(image, recover_g17_abi.INIT_POWER_DATA)[1],
        )
        self.assertEqual(
            power["tables"][1]["chip_variant_offset"],
            registers["accelerator_variant_member"],
        )

    def test_cleared_hardware_config_gaps_are_supported(self) -> None:
        # The hardware-config gap mask is now clear. Keep proof here for the
        # two formerly open pieces: the power rows remain explicitly
        # die-dependent and every late-control field is accounted for.
        driver = Path("build/kext/g17c/AGXG17X.macho")
        if not driver.exists():
            self.skipTest("extracted AGXG17X.macho is not available")
        image = driver.read_bytes()

        power = recover_g17_abi.recover_g17_linear_power_transfer_tables(
            image, recover_g17_abi.symbol_code(image, recover_g17_abi.INIT_POWER_DATA)[1]
        )
        self.assertTrue(power["die_dependent"])

        # The late-control bit has been cleared, so the recovery must now show
        # every field accounted for. If this regresses, the bit is wrong.
        late = recover_g17_abi.recover_g17_late_controls(image)
        self.assertTrue(late["complete"])
        self.assertEqual(late["runtime_dependent"], [])
        self.assertEqual(
            len(late["fixed"]) + len(late["derived"]), late["written_offsets"]
        )

    def test_recovers_g17_late_controls_from_the_real_producer(self) -> None:
        # This one is checked against the shipped binary rather than a stub:
        # the point of the derived scan is that a hand-built store list was
        # wrong, so a hand-built fixture would not exercise it.
        driver = Path("build/kext/g17c/AGXG17X.macho")
        if not driver.exists():
            self.skipTest("extracted AGXG17X.macho is not available")
        recovered = recover_g17_abi.recover_g17_late_controls(driver.read_bytes())

        self.assertEqual(recovered["region"], {"offset": 0x2540, "bytes": 0x1D0})
        # Writes through a computed base must be counted too.
        self.assertEqual(recovered["written_offsets"], 36)
        self.assertEqual(recovered["fixed"][0x2578], 1)
        self.assertEqual(recovered["fixed"][0x25A0], 1)
        self.assertEqual(recovered["fixed"][0x26F0], 1)
        for offset in (0x259C, 0x25A4, 0x25B4, 0x26C4, 0x2548):
            self.assertEqual(recovered["fixed"][offset], 0)
        for offset in (0x258C, 0x2706, 0x270A, 0x2600):
            self.assertEqual(recovered["fixed"][offset], 0)
        # +0x2560 only copies the core-mask pair when a half is nonzero, and
        # those halves are chip-info bytes no G17C reader writes.
        self.assertEqual(recovered["fixed"][0x2560], 0)
        self.assertFalse(recovered["core_mask_relay"]["written"])
        self.assertEqual(recovered["core_mask_relay"]["record_delta"], 0x480)
        # +0x2570 is computed rather than constant, so it counts as emitted
        # but is tracked apart from the fixed values.
        self.assertIn(0x2570, recovered["derived"])
        self.assertIn(0x2554, recovered["derived"])
        self.assertNotIn(0x2570, recovered["runtime_dependent"])
        self.assertEqual(
            len(recovered["fixed"])
            + len(recovered["derived"])
            + len(recovered["runtime_dependent"]),
            recovered["written_offsets"],
        )
        # Every field is now accounted for, which is what lets the boot gate's
        # late-control bit be cleared.
        self.assertEqual(recovered["runtime_dependent"], [])
        self.assertTrue(recovered["complete"])

    def test_stores_covering_spans_wide_and_paired_stores(self) -> None:
        # A byte is covered by a wider store at a lower offset, and by the
        # second half of a pair; both must count as written.
        wide = struct.pack("<I", 0x3D800260)  # str q0, [x19]
        self.assertEqual(recover_g17_abi.stores_covering(wide, 19, 0x0C), [0])
        pair = struct.pack("<I", 0xA9008260)  # stp x0, x0, [x19, #8]
        self.assertEqual(recover_g17_abi.stores_covering(pair, 19, 0x10), [0])
        # A store through a different base must not count.
        other = struct.pack("<I", 0x3D8002A0)  # str q0, [x21]
        self.assertEqual(recover_g17_abi.stores_covering(other, 19, 0x0C), [])

    def test_config_pointer_stores_ignores_foreign_bases(self) -> None:
        # A store at the same offset through a register that never held the
        # config pointer must not be attributed to the config.
        code = struct.pack(
            "<3I",
            0xF9415E68,  # ldr x8, [x19, #0x2b8]
            0xB9254109,  # str w9, [x8, #0x2540]   (config)
            0xB92541A9,  # str w9, [x13, #0x2540]  (foreign base)
        )
        stores = recover_g17_abi.config_pointer_stores(code, 0x2540, 0x2710)
        self.assertEqual([store["offset"] for store in stores], [0x2540])

    def test_config_pointer_stores_follows_computed_bases(self) -> None:
        code = struct.pack(
            "<4I",
            0xF9415E68,  # ldr x8, [x19, #0x2b8]
            0x52854C09,  # mov w9, #0x2a60
            0x8B090108,  # add x8, x8, x9
            0xB900011F,  # str wzr, [x8]
        )
        stores = recover_g17_abi.config_pointer_stores(code, 0x2540, 0x2B00)
        self.assertEqual(len(stores), 1)
        self.assertEqual(stores[0]["offset"], 0x2A60)
        self.assertTrue(stores[0]["zero_source"])

    def test_recovers_g17_command_stream_format(self) -> None:
        code = bytearray(0x3F4)
        for offset, word in {
            0x004: 0xF9400829,
            0x008: 0xF9400028,
            0x00C: 0xEB08013F,
            0x014: 0xB1030128,
            0x01C: 0xF940042A,
            0x058: 0xF9000828,
            0x070: 0x52802009,
            0x074: 0xB9000C09,
            0x080: 0xB940AC09,
            0x084: 0xAB090109,
            0x098: 0xF9000829,
            0x0A4: 0x3D803400,
            0x0A8: 0xF9007008,
            0x0B4: 0xB940A009,
            0x0DC: 0x91004129,
            0x11C: 0x3DC00100,
            0x120: 0x3C8E8000,
            0x124: 0xB940E80A,
            0x128: 0xAB0A056A,
            0x158: 0xB940EC08,
            0x15C: 0x8B080508,
            0x160: 0xAB080D48,
            0x170: 0xF900800A,
            0x17C: 0xB9409809,
            0x194: 0xB9409C0B,
            0x23C: 0x3DC00100,
            0x240: 0x3D804800,
            0x244: 0xB941200B,
            0x264: 0xF900980A,
            0x278: 0xB941240B,
            0x298: 0xF9009C0B,
            0x2AC: 0xB941280D,
            0x2CC: 0xF900A00D,
            0x2D8: 0xB9412C08,
            0x2F4: 0xF900A408,
            0x1C4: 0xB940A409,
            0x1E0: 0xB940A80C,
            0x370: 0x3DC00160,
            0x374: 0x3D805400,
            0x378: 0xB941580A,
            0x37C: 0xB9415C0C,
            0x380: 0xB941540D,
            0x384: 0xB941500E,
            0x388: 0x0B0E01AD,
            0x3A8: 0xF900B008,
            0x3B4: 0x0B0A0188,
            0x3D0: 0xF900B408,
            0x3D4: 0x52800028,
            0x3D8: 0x39002008,
            0x3EC: 0x52802049,
        }.items():
            struct.pack_into("<I", code, offset, word)

        with (
            mock.patch.object(
                recover_g17_abi,
                "macho_symbols",
                return_value={recover_g17_abi.PARSE_HARDWARE_KERNEL_COMMAND: 0x900000},
            ),
            mock.patch.object(
                recover_g17_abi, "symbol_code", return_value=(0x900000, bytes(code))
            ),
        ):
            recovered = recover_g17_abi.recover_g17_command_stream_format(b"")

        self.assertEqual(recovered["parser"], {"start": 0x00, "end": 0x08, "cursor": 0x10})
        self.assertEqual(recovered["header_bytes"], 0xC0)
        # The field is at 0xac of the command, which is 0x9c of the record.
        self.assertEqual(recovered["payload_length_offset"], 0x9C)
        self.assertEqual(
            recovered["primary_extension"]["stream_length_offset"], 0x90
        )
        self.assertEqual(
            recovered["primary_extension"]["element_bytes"], [2, 24]
        )
        self.assertEqual(
            recovered["auxiliary_stream_extensions"]["u16_arrays"],
            {
                "flag_offset": 0x88,
                "stream_length_offset": 0x8C,
                "header_bytes": 0x10,
                "count_offsets": [0, 4, 8, 12],
                "element_bytes": [2, 2, 2, 2],
                "header_member": 0x120,
                "array_members": [0x130, 0x138, 0x140, 0x148],
            },
        )
        self.assertEqual(
            recovered["auxiliary_stream_extensions"]["u64_groups"]
            ["group_count_indices"],
            [[0, 1], [2, 3]],
        )
        self.assertEqual(
            recovered["auxiliary_stream_extensions"]["u64_groups"]
            ["group_array_members"],
            [0x160, 0x168],
        )
        self.assertEqual(recovered["success"], {"member": 8, "value": 1})
        self.assertEqual(recovered["error_markers"]["auxiliary_stream"], 0x102)
        self.assertEqual(recovered["terminator_marker"], 0x100)

    def test_recovers_g17_render_payload_format(self) -> None:
        code = bytearray(0x224)
        for offset, word in {
            0x004: 0xF9400828,
            0x008: 0xF9400029,
            0x014: 0xF9000C1F,
            0x020: 0xB9000C09,
            0x02C: 0xB1274109,
            0x040: 0xF9000829,
            0x044: 0xF9000C08,
            0x04C: 0x91032109,
            0x064: 0xAD010400,
            0x070: 0xF9409D09,
            0x074: 0xF9004809,
            0x07C: 0x3D801800,
            0x080: 0x91136109,
            0x0B4: 0x3C898000,
            0x0B8: 0x3DC05100,
            0x0BC: 0x3D804400,
            0x0C8: 0xF940C109,
            0x0CC: 0xF900A809,
            0x0DC: 0x3DC15500,
            0x0E0: 0x3D800120,
            0x0F0: 0xF942C90A,
            0x0F4: 0xF900CC0A,
            0x100: 0x91093109,
            0x10C: 0xB901A80A,
            0x118: 0xF9432D0A,
            0x124: 0xF900012A,
            0x12C: 0x12000169,
            0x134: 0x3962C109,
            0x138: 0x12000129,
            0x144: 0xB901BC09,
            0x184: 0xAD000520,
            0x188: 0xF9433509,
            0x18C: 0xF9010009,
            0x190: 0x39608509,
            0x194: 0x39082009,
            0x1A8: 0x3D808400,
            0x1C0: 0xAD120400,
            0x1C8: 0x12000149,
            0x1D4: 0x1200012C,
            0x1E0: 0x1200018C,
            0x1EC: 0x1200018C,
            0x1F4: 0x395F8108,
            0x1F8: 0x4A0B0108,
            0x200: 0x3600004A,
            0x204: 0x360000A9,
            0x208: 0x52800028,
            0x20C: 0x39002008,
            0x21C: 0x52800149,
        }.items():
            struct.pack_into("<I", code, offset, word)

        with (
            mock.patch.object(
                recover_g17_abi,
                "macho_symbols",
                return_value={
                    recover_g17_abi.PARSE_RENDER_HARDWARE_KERNEL_COMMAND: 0x920000
                },
            ),
            mock.patch.object(
                recover_g17_abi, "symbol_code", return_value=(0x920000, bytes(code))
            ),
        ):
            recovered = recover_g17_abi.recover_g17_render_payload_format(b"")

        self.assertEqual(recovered["payload_bytes"], 0x9D0)
        self.assertEqual(recovered["payload_pointer_member"], 0x18)
        self.assertEqual(len(recovered["copy_ranges"]), 11)
        self.assertEqual(
            recovered["copy_ranges"][0],
            {"payload_offset": 0xC8, "command_member": 0x20, "bytes": 0x78},
        )
        self.assertEqual(len(recovered["bit_fields"]), 10)
        self.assertEqual(recovered["bit_fields"][0]["mask"], 1)
        self.assertEqual(
            recovered["validation"][1],
            {
                "operation": "implies",
                "condition": {"payload_offset": 0x23C, "bit": 0},
                "required": {"payload_offset": 0x646, "bit": 0},
            },
        )
        self.assertEqual(recovered["error_markers"]["validation"], 0xA)

    def test_recovers_g17_channel_command_common_fields(self) -> None:
        code = bytearray(0x300)
        for offset, word in {
            0x024: 0xAA0303F6,
            0x218: 0xB80222F6,
            0x21C: 0x52800028,
            0x220: 0xB801A2E8,
            0x224: 0xB80322FF,
            0x228: 0xF80622FF,
        }.items():
            struct.pack_into("<I", code, offset, word)

        with (
            mock.patch.object(
                recover_g17_abi,
                "macho_symbols",
                return_value={recover_g17_abi.SUBMIT_NOP_UNPREPARED: 0x910000},
            ),
            mock.patch.object(
                recover_g17_abi, "symbol_code", return_value=(0x910000, bytes(code))
            ),
        ):
            recovered = recover_g17_abi.recover_g17_channel_command_common_fields(b"")

        self.assertEqual(recovered["known_prefix_bytes"], 0x6A)
        self.assertTrue(recovered["preserve_other_bytes"])
        self.assertEqual(recovered["fields"]["control_01a"]["value"], 1)
        self.assertEqual(recovered["fields"]["data_master_type"]["offset"], 0x22)
        self.assertEqual(recovered["fields"]["control_062"]["bytes"], 8)

    def test_rejects_changed_g17_channel_command_common_field(self) -> None:
        code = bytearray(0x300)
        with (
            mock.patch.object(
                recover_g17_abi,
                "macho_symbols",
                return_value={recover_g17_abi.SUBMIT_NOP_UNPREPARED: 0x910000},
            ),
            mock.patch.object(
                recover_g17_abi, "symbol_code", return_value=(0x910000, bytes(code))
            ),
        ):
            with self.assertRaises(ValueError):
                recover_g17_abi.recover_g17_channel_command_common_fields(b"")

    def test_recovers_g17_register_selectors(self) -> None:
        def producer(literals, emissions: int) -> bytes:
            code = bytearray()
            for value in literals:
                code += struct.pack("<I", 0x52800000 | ((value & 0xFFFF) << 5) | 11)
                if value >> 16:
                    code += struct.pack(
                        "<I", 0x72A00000 | (((value >> 16) & 0xFFFF) << 5) | 11
                    )
                code += struct.pack("<I", 0x2A0B014A)  # orr w10, w10, w11
            code += struct.pack("<I", 0x528C0416)  # mov w22, #0x6020
            code += struct.pack("<I", 0x72A00036)  # movk w22, #1, lsl #16
            code += struct.pack("<I", 0x910083E0)  # add x0, sp, #0x20
            code += struct.pack("<I", 0x5132A2C2)  # sub w2, w22, #0xca8
            code += struct.pack("<I", 0x52800003)  # mov w3, #0
            code += struct.pack("<I", 0xD2800004)  # mov x4, #0
            code += struct.pack("<I", 0xD73F0910)  # blraa x8, x16
            for _ in range(emissions):
                code += struct.pack("<I", 0x11003129)  # add w9, w9, #0xc
                code += struct.pack("<I", 0x790E1509)  # strh w9, [x8, #0x70a]
            return bytes(code)

        literals = {
            "3D": [0x1739, 0x17E1, 0x16020],
            "CL": [0x90, 0x98, 0x1A440],
            "FastBlit": [0x28, 0x1498],
            "TA": [0x128, 0x130, 0x1C880],
        }
        codes = {
            recover_g17_abi.REGISTER_LIST_PRODUCERS[label]: (
                0x800000,
                producer(values, 40),
            )
            for label, values in literals.items()
        }
        symbols = {name: address for name, (address, _c) in codes.items()}
        with (
            mock.patch.object(recover_g17_abi, "macho_symbols", return_value=symbols),
            mock.patch.object(
                recover_g17_abi,
                "symbol_code",
                side_effect=lambda _image, name: codes[name],
            ),
        ):
            recovered = recover_g17_abi.recover_g17_register_selectors(b"")

        self.assertEqual(recovered["encoded_field"], 0x0003FFF9)
        self.assertEqual(recovered["selector_field"], 0x0003FFF8)
        self.assertEqual(recovered["mode_bit"], 1)
        self.assertEqual(recovered["flag_bit"], 1)
        self.assertEqual(recovered["alignment"], 8)
        # The sets are a sample, never a complete list.
        self.assertFalse(recovered["selectors_complete"])
        self.assertFalse(recovered["address_space_identified"])
        self.assertEqual(
            recovered["producers"]["3D"]["encoded_fields"],
            [0x1739, 0x17E1, 0x16020],
        )
        self.assertEqual(
            recovered["producers"]["3D"]["selectors"],
            [0x1738, 0x17E0, 0x16020],
        )
        self.assertEqual(recovered["producers"]["3D"]["entry_emission_sites"], 40)
        self.assertEqual(recovered["producers"]["3D"]["encoder_call_sites"], 1)
        self.assertEqual(recovered["producers"]["3D"]["mode_0_calls"], 1)
        self.assertEqual(recovered["producers"]["3D"]["mode_1_calls"], 0)
        self.assertEqual(recovered["producers"]["3D"]["constant_value_calls"], 1)
        value_source = recovered["producers"]["3D"]["encoder_entries"][0][
            "value_source"
        ]
        self.assertEqual(value_source["kind"], "constant")
        self.assertEqual(value_source["value"], 0)
        self.assertEqual(
            recovered["producers"]["3D"]["resolved_encoder_selectors"],
            [0x15378],
        )
        self.assertIn(0x15378, recovered["producers"]["3D"]["static_selectors"])
        self.assertEqual(recovered["distinct_literal_selectors"], 11)

    def test_recovers_g17_register_entry_codec(self) -> None:
        code = bytearray(0x28)
        for offset, word in {
            0x004: 0xB9400028,
            0x008: 0x121F7908,
            0x00C: 0x120E4108,
            0x010: 0x121D3849,
            0x014: 0x33000069,
            0x018: 0x2A080128,
            0x01C: 0xB9000028,
            0x020: 0xF8004024,
            0x024: 0xD65F03C0,
        }.items():
            struct.pack_into("<I", code, offset, word)
        with (
            mock.patch.object(
                recover_g17_abi,
                "macho_symbols",
                return_value={recover_g17_abi.RCE_ENCODE_ENTRY: 0x810000},
            ),
            mock.patch.object(
                recover_g17_abi,
                "symbol_code",
                return_value=(0x810000, bytes(code)),
            ),
        ):
            recovered = recover_g17_abi.recover_g17_register_entry_codec(b"")

        self.assertEqual(recovered["entry_bytes"], 12)
        self.assertEqual(recovered["selector_mask"], 0x3FFF8)
        self.assertEqual(recovered["mode_mask"], 1)
        self.assertEqual(recovered["preserved_template_mask"], 0xFFFC0006)
        self.assertEqual(recovered["value_offset"], 4)

    def test_recovers_g17_constant_virtual_returns(self) -> None:
        providers = {
            recover_g17_abi.G17_DUPM_MIN_COUNT: (0x810000, 1),
            recover_g17_abi.G17_DUPM_MAX_COUNT: (0x81000C, 2),
        }
        targets = {
            0x10F8: 0x810000,
            0x1100: 0x81000C,
        }
        with (
            mock.patch.object(
                recover_g17_abi,
                "macho_symbols",
                return_value={
                    name: address
                    for name, (address, _value) in providers.items()
                },
            ),
            mock.patch.object(
                recover_g17_abi,
                "recover_vtable_target",
                side_effect=lambda _image, _vtable, slot: targets[slot],
            ),
            mock.patch.object(
                recover_g17_abi,
                "symbol_code",
                side_effect=lambda _image, name: (
                    providers[name][0],
                    struct.pack(
                        "<3I",
                        0xD503245F,
                        0x52800000 | providers[name][1] << 5,
                        0xD65F03C0,
                    ),
                ),
            ),
        ):
            recovered = recover_g17_abi.recover_g17_constant_virtual_returns(b"")

        self.assertEqual(
            recovered["accelerator_vtable"], "__ZTV18AGXAcceleratorG17X"
        )
        self.assertEqual(recovered["methods"]["dup_min_count"]["value"], 1)
        self.assertEqual(
            recovered["methods"]["dup_min_count"]["vtable_slot"], 0x10F8
        )
        self.assertEqual(recovered["methods"]["dup_max_count"]["value"], 2)
        self.assertEqual(
            recovered["methods"]["dup_max_count"]["vtable_slot"], 0x1100
        )

    def test_rejects_changed_g17_constant_virtual_return(self) -> None:
        providers = {
            recover_g17_abi.G17_DUPM_MIN_COUNT: 0x810000,
            recover_g17_abi.G17_DUPM_MAX_COUNT: 0x81000C,
        }
        with (
            mock.patch.object(
                recover_g17_abi, "macho_symbols", return_value=providers
            ),
            mock.patch.object(
                recover_g17_abi,
                "recover_vtable_target",
                side_effect=lambda _image, _vtable, slot: 0x810000
                if slot == 0x10F8
                else 0x81000C,
            ),
            mock.patch.object(
                recover_g17_abi,
                "symbol_code",
                return_value=(
                    0x810000,
                    struct.pack("<3I", 0xD503245F, 0, 0xD65F03C0),
                ),
            ),
        ):
            with self.assertRaisesRegex(ValueError, "not the checked constant stub"):
                recover_g17_abi.recover_g17_constant_virtual_returns(b"")

    def test_recovers_g17_memory_map_virtual_address(self) -> None:
        driver = b"driver"
        iogpu = b"iogpu"
        provider_address = 0xA483B6C
        symbols = {
            driver: {
                recover_g17_abi.AGX_LEGACY_MEMORY_MAP_VTABLE: 0x810000,
                recover_g17_abi.AGX_SECURE_MEMORY_MAP_VTABLE: 0x820000,
            },
            iogpu: {
                recover_g17_abi.IOGPU_MEMORY_MAP_VTABLE: 0x830000,
                recover_g17_abi.IOGPU_MEMORY_MAP_GPU_VA: provider_address,
            },
        }
        with (
            mock.patch.object(
                recover_g17_abi,
                "macho_symbols",
                side_effect=lambda image: symbols[image],
            ),
            mock.patch.object(
                recover_g17_abi,
                "recover_vtable_target",
                return_value=provider_address,
            ),
            mock.patch.object(
                recover_g17_abi,
                "symbol_code",
                return_value=(
                    provider_address,
                    struct.pack("<3I", 0xD503245F, 0xF9401400, 0xD65F03C0),
                ),
            ),
        ):
            recovered = recover_g17_abi.recover_g17_memory_map_virtual_address(
                driver, iogpu
            )

        self.assertEqual(recovered["vtable_slot"], 0x158)
        self.assertEqual(recovered["object_member"], 0x28)
        self.assertEqual(recovered["provider_address"], provider_address)
        self.assertEqual(
            recovered["inherited_by"],
            [
                recover_g17_abi.IOGPU_MEMORY_MAP_VTABLE,
                recover_g17_abi.AGX_LEGACY_MEMORY_MAP_VTABLE,
                recover_g17_abi.AGX_SECURE_MEMORY_MAP_VTABLE,
            ],
        )

    def test_decodes_g17_selector_logical_immediate(self) -> None:
        # orr w2, w27, #0x10
        self.assertEqual(
            recover_g17_abi.decode_logical_immediate_w(0x321C0362),
            ("orr", 2, 27, 0x10),
        )

    def test_classifies_g17_register_value_source(self) -> None:
        descriptor_load = [(0x40, 0xF943B264)]  # ldr x4, [x19, #0x760]
        self.assertEqual(
            recover_g17_abi.classify_g17_value_argument(descriptor_load, 1),
            {
                "kind": "descriptor_load",
                "producer_offset": 0x40,
                "base_register": 19,
                "member": 0x760,
                "bytes": 8,
                "signed": False,
            },
        )
        with self.assertRaises(ValueError):
            recover_g17_abi.classify_g17_value_argument([(0, 0xD503201F)], 1)

        negative_one = [(0x44, 0x92800004)]  # mov x4, #-1
        self.assertEqual(
            recover_g17_abi.classify_g17_value_argument(negative_one, 1),
            {
                "kind": "constant",
                "producer_offset": 0x44,
                "value": 0xFFFFFFFFFFFFFFFF,
            },
        )
        negative_one_w = [(0x46, 0x12800004)]  # mov w4, #-1
        self.assertEqual(
            recover_g17_abi.classify_g17_value_argument(negative_one_w, 1),
            {
                "kind": "constant",
                "producer_offset": 0x46,
                "value": 0xFFFFFFFF,
            },
        )

        copied_descriptor = [
            (0x48, 0xF943B276),  # ldr x22, [x19, #0x760]
            (0x4C, 0xAA1603E4),  # mov x4, x22
        ]
        self.assertEqual(
            recover_g17_abi.classify_g17_value_argument(copied_descriptor, 2),
            {
                "kind": "descriptor_load",
                "producer_offset": 0x4C,
                "source_offset": 0x48,
                "via_register": 22,
                "base_register": 19,
                "member": 0x760,
                "bytes": 8,
                "signed": False,
            },
        )

        copied_constant = [
            (0x50, 0xD2804016),  # mov x22, #0x200
            (0x54, 0xAA1603E4),  # mov x4, x22
        ]
        self.assertEqual(
            recover_g17_abi.classify_g17_value_argument(copied_constant, 2),
            {
                "kind": "constant",
                "producer_offset": 0x54,
                "source_offset": 0x50,
                "via_register": 22,
                "value": 0x200,
            },
        )

    def test_does_not_trace_g17_register_copy_across_join(self) -> None:
        instructions = [
            (0x00, 0xF943B276),  # ldr x22, [x19, #0x760]
            (0x04, 0x14000002),  # b +0x8
            (0x08, 0xF943B676),  # alternate ldr x22, [x19, #0x768]
            (0x0C, 0xAA1603E4),  # mov x4, x22
        ]
        self.assertEqual(
            recover_g17_abi.classify_g17_value_argument(instructions, 4),
            {
                "kind": "computed",
                "producer_offset": 0x0C,
                "operation": "register_copy",
                "source_register": 22,
                "bytes": 8,
                "instruction": 0xAA1603E4,
            },
        )

    def test_recovers_g17_single_conditional_branch_merge(self) -> None:
        instructions = [
            (0x00, 0xF943B264),  # ldr x4, [x19, #0x760]
            (0x04, 0x395F8668),  # ldrb w8, [x19, #0x7e1]
            (0x08, 0x7200011F),  # tst w8, #1
            (0x0C, b_cond(0x0C, 0x14, 0)),  # b.eq +0x8
            (0x10, 0xB2400084),  # orr x4, x4, #1
            (0x14, 0xD503201F),
        ]
        recovered = recover_g17_abi.classify_g17_value_argument(instructions, 6)
        expression = recovered["expression"]
        self.assertEqual(expression["operation"], "branch_select")
        self.assertEqual(expression["condition"], "eq")
        self.assertEqual(expression["predicate"]["operation"], "tst")
        self.assertEqual(expression["taken"]["member"], 0x760)
        self.assertEqual(expression["fallthrough"]["operation"], "orr")

    def test_recovers_g17_test_bit_branch_merge(self) -> None:
        instructions = [
            (0x00, 0xF943B264),  # ldr x4, [x19, #0x760]
            (0x04, 0x395F8668),  # ldrb w8, [x19, #0x7e1]
            (0x08, tbz(0x08, 0x10, 8, 0)),
            (0x0C, 0xB2400084),  # orr x4, x4, #1
            (0x10, 0xD503201F),
        ]
        recovered = recover_g17_abi.classify_g17_value_argument(instructions, 5)
        expression = recovered["expression"]
        self.assertEqual(expression["operation"], "branch_select")
        self.assertEqual(expression["condition"], "bit_clear")
        self.assertEqual(expression["predicate"]["operation"], "test_bit")
        self.assertEqual(expression["predicate"]["source"]["member"], 0x7E1)
        self.assertEqual(expression["taken"]["member"], 0x760)
        self.assertEqual(expression["fallthrough"]["operation"], "orr")

    def test_recovers_g17_test_bit_branch_diamond(self) -> None:
        instructions = [
            (0x00, 0x395F8668),  # ldrb w8, [x19, #0x7e1]
            (0x04, tbz(0x04, 0x10, 8, 0)),
            (0x08, 0xB9476264),  # ldr w4, [x19, #0x760]
            (0x0C, b(0x0C, 0x14)),
            (0x10, 0x528000E4),  # mov w4, #7
            (0x14, 0xD503201F),
        ]
        expression = recover_g17_abi.trace_g17_value_expression(
            instructions, 6, 4
        )
        self.assertIsNotNone(expression)
        self.assertEqual(expression["operation"], "branch_select")
        self.assertEqual(expression["condition"], "bit_clear")
        self.assertEqual(expression["taken"]["value"], 7)
        self.assertEqual(expression["fallthrough"]["member"], 0x760)

    def test_recovers_g17_compare_zero_branch_merge(self) -> None:
        instructions = [
            (0x00, 0xF943B264),  # ldr x4, [x19, #0x760]
            (0x04, cbz(0x04, 0x0C, 4, nonzero=True)),
            (0x08, 0xF943C264),  # ldr x4, [x19, #0x780]
            (0x0C, 0xD503201F),
        ]
        expression = recover_g17_abi.trace_g17_value_expression(
            instructions, 4, 4
        )
        self.assertIsNotNone(expression)
        self.assertEqual(expression["operation"], "branch_select")
        self.assertEqual(expression["condition"], "nonzero")
        self.assertEqual(expression["predicate"]["operation"], "compare_zero")
        self.assertEqual(expression["predicate"]["source"]["member"], 0x760)
        self.assertEqual(expression["taken"]["member"], 0x760)
        self.assertEqual(expression["fallthrough"]["member"], 0x780)

    def test_recovers_g17_four_way_compare_merge(self) -> None:
        instructions = [
            (0x00, 0xF943B264),  # ldr x4, [x19, #0x760]
            (0x04, ldr_w(9, 19, 0x8C8)),
            (0x08, 0x7100213F),  # cmp w9, #8
            (0x0C, b_cond(0x0C, 0x30, 0)),
            (0x10, 0x7100113F),  # cmp w9, #4
            (0x14, b_cond(0x14, 0x28, 0)),
            (0x18, 0x7100093F),  # cmp w9, #2
            (0x1C, b_cond(0x1C, 0x34, 1)),
            (0x20, 0xB2400084),  # orr x4, x4, #1
            (0x24, b(0x24, 0x34)),
            (0x28, 0xB27F0084),  # orr x4, x4, #2
            (0x2C, b(0x2C, 0x34)),
            (0x30, 0xB2400484),  # orr x4, x4, #3
            (0x34, 0xD503201F),
        ]
        recovered = recover_g17_abi.classify_g17_value_argument(instructions, 14)
        expression = recovered["expression"]
        self.assertEqual(expression["operation"], "multiway_select")
        self.assertEqual(expression["selector"]["member"], 0x8C8)
        self.assertEqual(expression["default"]["member"], 0x760)
        self.assertEqual(
            [case["equals"] for case in expression["cases"]], [8, 4, 2]
        )
        self.assertEqual(
            [case["value"]["immediate"] for case in expression["cases"]],
            [3, 2, 1],
        )

    def test_recovers_g17_nested_optional_bit_set(self) -> None:
        instructions = [
            (0x00, 0xF943B264),  # ldr x4, [x19, #0x760]
            (0x04, 0x39400268),  # ldrb w8, [x19]
            (0x08, tbz(0x08, 0x24, 8, 0)),
            (0x0C, 0xB9400269),  # ldr w9, [x19]
            (0x10, cbz(0x10, 0x20, 9, nonzero=True, width=4)),
            (0x14, 0xB9400669),  # ldr w9, [x19, #4]
            (0x18, 0x3100053F),  # cmn w9, #1
            (0x1C, b_cond(0x1C, 0x24, 0)),
            (0x20, 0xB2750084),  # orr x4, x4, #0x800
            (0x24, 0xD503201F),
        ]
        expression = recover_g17_abi.trace_g17_value_expression(
            instructions, 10, 4
        )
        self.assertIsNotNone(expression)
        self.assertEqual(expression["condition"], "bit_clear")
        self.assertEqual(expression["taken"]["member"], 0x760)
        compare_zero = expression["fallthrough"]
        self.assertEqual(compare_zero["condition"], "nonzero")
        self.assertEqual(compare_zero["taken"]["immediate"], 0x800)
        inner = compare_zero["fallthrough"]
        self.assertEqual(inner["condition"], "eq")
        self.assertEqual(inner["taken"]["member"], 0x760)
        self.assertEqual(inner["fallthrough"]["immediate"], 0x800)

    def test_recovers_g17_cl_table_or_fallback_base(self) -> None:
        instructions = [
            (0x31C, ldrb(10, 19, 0x58)),
            (0x320, tbz(0x320, 0x35C, 10, 0)),
            (0x324, ldr_w(10, 19, 0x5C)),
            (0x328, 0x5100054A),  # sub w10, w10, #1
            (0x32C, 0x7100195F),  # cmp w10, #6
            (0x330, b_cond(0x330, 0x36C, 8)),  # b.hi
            (0x334, adrp(0x334, 0x5000, 11)),
            (0x338, add_immediate(11, 11, 0x40)),
            (0x33C, 0xD37D7D4A),  # ubfiz x10, x10, #3, #32
            (0x340, 0xEB2AC15F),  # cmp x10, w10, sxtw
            (0x344, 0x8B2AC16C),  # add x12, x11, w10, sxtw
            (0x348, 0x8B0A0170),  # add x16, x11, x10
            (0x34C, 0xF2E575B0),  # movk x16, #0x2bad, lsl #48
            (0x350, 0x9A90018C),  # csel x12, x12, x16, eq
            (0x354, 0xF940018A),  # ldr x10, [x12]
            (0x358, b(0x358, 0x378)),
            (0x35C, 0xD2884018),
            (0x360, 0xF2AA8058),
            (0x364, 0xF2C00038),
            (0x368, b(0x368, 0x390)),
            (0x36C, 0xD284402A),
            (0x370, 0xF2AA800A),
            (0x374, 0xF2C0002A),
            (0x378, ldr_w(11, 19, 0x6C)),
            (0x37C, 0xAA0B454A),  # orr x10, x10, x11, lsl #17
            (0x380, 0x9293BFEB),
            (0x384, 0xF2BFFDCB),
            (0x388, 0xF2E0002B),
            (0x38C, 0x8A0B0158),  # and x24, x10, x11
            (0x390, 0xD503201F),
        ]
        expression = recover_g17_abi.trace_g17_value_expression(
            instructions, 30, 24
        )
        self.assertIsNotNone(expression)
        self.assertEqual(expression["operation"], "branch_select")
        self.assertEqual(expression["condition"], "bit_clear")
        self.assertEqual(expression["taken"]["value"], 0x154024200)
        dynamic = expression["fallthrough"]
        self.assertEqual(dynamic["operation"], "and")
        self.assertEqual(dynamic["first"]["first"]["condition"], "hi")
        self.assertEqual(dynamic["first"]["first"]["taken"]["value"], 0x154002201)

    def test_recovers_g17_cl_mode_selected_low_bit(self) -> None:
        instructions = [
            (0x390, ldr_w(10, 19, 0x100)),
            (0x394, 0x7100095F),  # cmp w10, #2
            (0x398, b_cond(0x398, 0x3D8, 0)),
            (0x39C, 0x7100055F),  # cmp w10, #1
            (0x3A0, b_cond(0x3A0, 0x3C0, 0)),
            (0x3A4, cbz(0x3A4, 0x3EC, 10, nonzero=True, width=4)),
            (0x3A8, ldrb(10, 19, 0x44)),
            (0x3AC, tbz(0x3AC, 0x410, 10, 0)),
            (0x3B0, ldr_w(10, 19, 0x48)),
            (0x3B4, 0x7100015F),  # cmp w10, #0
            (0x3B8, 0x1A9F17EA),  # cset w10, eq
            (0x3BC, b(0x3BC, 0x414)),
            (0x3C0, ldrb(10, 19, 0x44)),
            (0x3C4, tbz(0x3C4, 0x3F0, 10, 0)),
            (0x3C8, ldr_w(10, 19, 0x48)),
            (0x3CC, 0x7100015F),  # cmp w10, #0
            (0x3D0, 0x1A9F17EA),  # cset w10, eq
            (0x3D4, b(0x3D4, 0x3F4)),
            (0x3D8, recover_g17_abi.G17_CL_RANDOM_CALL_WORD),
            (0x3DC, 0x1200000A),  # and w10, w0, #1
            (0x3E0, 0xD503201F),
            (0x3E4, 0xD503201F),
            (0x3E8, b(0x3E8, 0x414)),
            (0x3EC, b(0x3EC, 0x414)),
            (0x3F0, ldr_w(10, 19, 0x40)),
            (0x3F4, adrp(0x3F4, 0x5000, 11)),
            (0x3F8, ldrb(12, 11, 8)),
            (0x3FC, 0x1100058D),  # add w13, w12, #1
            (0x400, 0x3900216D),  # strb w13, [x11, #8]
            (0x404, 0x0B0C014A),  # add w10, w10, w12
            (0x408, 0x1200014A),  # and w10, w10, #1
            (0x40C, b(0x40C, 0x414)),
            (0x410, ldr_w(10, 19, 0x40)),
            (0x414, 0xD503201F),
        ]
        expression = recover_g17_abi.trace_g17_value_expression(
            instructions, 34, 10
        )
        self.assertIsNotNone(expression)
        self.assertEqual(expression["operation"], "multiway_select")
        self.assertEqual([case["equals"] for case in expression["cases"]], [2, 1, 0])
        self.assertEqual(expression["cases"][0]["value"]["source"]["provider"], "_random")
        counter = expression["cases"][1]["value"]["source"]["second"]
        self.assertEqual(counter["kind"], "object_load")
        self.assertEqual(counter["update"], "postincrement")

    def test_rejects_g17_ambiguous_conditional_branch_merge(self) -> None:
        instructions = [
            (0x00, 0xF943B264),  # ldr x4, [x19, #0x760]
            (0x04, b_cond(0x04, 0x14, 0)),
            (0x08, b_cond(0x08, 0x14, 1)),
            (0x0C, 0xB2400084),  # orr x4, x4, #1
            (0x10, 0xD503201F),
            (0x14, 0xD503201F),
        ]
        recovered = recover_g17_abi.classify_g17_value_argument(instructions, 6)
        self.assertEqual(recovered["kind"], "computed")
        self.assertNotIn("expression", recovered)

    def test_g17_prologue_definition_dominates_loop_backedge(self) -> None:
        ldr_x8_x20_020 = 0xF9400008 | (20 << 5) | ((0x20 // 8) << 10)
        instructions = [
            (0x00, 0xAA0103F4),  # mov x20, x1 (command argument)
            (0x04, ldr_x8_x20_020),
            (0x08, 0x927AE504),  # and x4, x8, #0xffffffffffffffc0
            (0x0C, 0x17FFFFFE),  # loop back to +0x4
        ]
        recovered = recover_g17_abi.classify_g17_value_argument(instructions, 3)
        source = recovered["expression"]["source"]
        self.assertEqual(source["kind"], "object_load")
        self.assertEqual(source["base"]["source"]["name"], "command")

    def test_recovers_g17_register_value_expression(self) -> None:
        instructions = [
            (0x00, 0xF943B268),  # ldr x8, [x19, #0x760]
            (0x04, 0x927AE504),  # and x4, x8, #0xffffffffffffffc0
        ]
        recovered = recover_g17_abi.classify_g17_value_argument(instructions, 2)
        self.assertEqual(recovered["kind"], "computed")
        self.assertEqual(
            recovered["expression"],
            {
                "kind": "expression",
                "producer_offset": 0x04,
                "operation": "and",
                "bytes": 8,
                "immediate": 0xFFFFFFFFFFFFFFC0,
                "source": {
                    "kind": "descriptor_load",
                    "producer_offset": 0x00,
                    "member": 0x760,
                    "bytes": 8,
                    "signed": False,
                },
            },
        )

    def test_recovers_g17_movk_over_expression(self) -> None:
        instructions = [
            (0x00, 0xB27053EC),  # mov x12, #0x1fffff0000
            (0x04, 0xF29F0C0C),  # movk x12, #0xf860
            (0x08, 0xAA0C03E4),  # mov x4, x12
        ]
        recovered = recover_g17_abi.classify_g17_value_argument(instructions, 3)
        expression = recovered["expression"]["source"]
        self.assertEqual(expression["operation"], "movk")
        self.assertEqual(expression["bytes"], 8)
        self.assertEqual(expression["immediate"], 0xF860)
        self.assertEqual(expression["shift"], 0)
        self.assertEqual(expression["source"]["operation"], "orr")

    def test_recovers_bounded_deep_g17_value_expression(self) -> None:
        instructions = [(0x00, 0xF943B268)]  # ldr x8, [x19, #0x760]
        instructions.extend(
            (index * 4, 0xB2400108)  # orr x8, x8, #1
            for index in range(1, 15)
        )
        instructions.append((0x3C, 0xAA0803E4))  # mov x4, x8
        recovered = recover_g17_abi.classify_g17_value_argument(instructions, 16)
        expression = recovered["expression"]
        self.assertEqual(expression["operation"], "copy")
        for _ in range(14):
            expression = expression["source"]
            self.assertEqual(expression["operation"], "orr")
        self.assertEqual(expression["source"]["member"], 0x760)

    def test_recovers_g17_dup_count_virtual_call_expression(self) -> None:
        blraa_x9_x17 = 0xD73F0800 | 9 << 5 | 17
        orr_x4_x23_x0_lsl_32 = 0xAA000000 | 32 << 10 | 23 << 5 | 4
        instructions = [
            (0x00, ldr_x(9, 16, 0x10F8)),
            (0x04, blraa_x9_x17),
            (0x08, 0xAA0003F7),  # mov x23, x0
            (0x0C, ldr_x(9, 16, 0x1100)),
            (0x10, blraa_x9_x17),
            (0x14, orr_x4_x23_x0_lsl_32),
        ]
        recovered = recover_g17_abi.classify_g17_value_argument(instructions, 6)
        expression = recovered["expression"]
        self.assertEqual(expression["operation"], "orr")
        self.assertEqual(expression["first"]["source"]["kind"], "constant_call")
        self.assertEqual(expression["first"]["source"]["method"], "dup_min_count")
        self.assertEqual(expression["first"]["source"]["value"], 1)
        self.assertEqual(expression["second"]["kind"], "constant_call")
        self.assertEqual(expression["second"]["method"], "dup_max_count")
        self.assertEqual(expression["second"]["value"], 2)

    def test_explicit_g17_x0_writer_overrides_constant_call(self) -> None:
        instructions = [
            (0x00, ldr_x(9, 16, 0x10F8)),
            (0x04, 0xD73F0800 | 9 << 5 | 17),
            (0x08, 0x528000E0),  # mov w0, #7
            (0x0C, 0xAA0003E4),  # mov x4, x0
        ]
        recovered = recover_g17_abi.classify_g17_value_argument(instructions, 4)
        source = recovered["expression"]["source"]
        self.assertEqual(source["kind"], "constant")
        self.assertEqual(source["value"], 7)

    def test_recovers_g17_memory_map_virtual_address_expression(self) -> None:
        instructions = [
            (0x00, ldr_x(8, 19, 0xB80)),
            (0x04, ldr_w(24, 19, 0xB88)),
            (0x08, ldr_x(8, 8, 0x30)),
            (0x0C, ldr_x(0, 8, 0x68)),
            (0x10, ldr_x(16, 0, 0)),
            (0x14, ldr_x(9, 16, 0x158)),
            (0x18, 0xD73F0800 | 9 << 5 | 17),
            (0x1C, 0x8B000000 | 24 << 16 | 8),  # add x8, x0, x24
            (0x20, 0x927A9108),  # and x8, x8, #0x7ffffffffc0
            (0x24, 0xB2400104),  # orr x4, x8, #1
        ]
        recovered = recover_g17_abi.classify_g17_value_argument(instructions, 10)
        address = recovered["expression"]["source"]["source"]["first"]
        self.assertEqual(address["kind"], "virtual_load")
        self.assertEqual(address["method"], "gpu_virtual_address")
        self.assertEqual(address["vtable_slot"], 0x158)
        self.assertEqual(address["member"], 0x28)
        self.assertEqual(address["receiver"]["member"], 0x68)
        self.assertEqual(address["receiver"]["base"]["member"], 0x30)
        self.assertEqual(
            address["receiver"]["base"]["base"]["member"], 0xB80
        )

    def test_rejects_untyped_g17_memory_map_slot_call(self) -> None:
        instructions = [
            (0x00, ldr_x(16, 0, 0)),
            (0x04, ldr_x(9, 16, 0x158)),
            (0x08, 0xD73F0800 | 9 << 5 | 17),
            (0x0C, 0xAA0003E4),  # mov x4, x0
        ]
        recovered = recover_g17_abi.classify_g17_value_argument(instructions, 4)
        self.assertNotIn("expression", recovered)

    def test_g17_bitfield_insert_expression_keeps_old_destination(self) -> None:
        and_x4_x8 = (0x92405D24 & ~0x3E0) | (8 << 5)
        instructions = [
            (0x00, 0xB94B2A68),  # ldr w8, [x19, #0xb28]
            (0x04, and_x4_x8),  # and x4, x8, #0xffffff
            (0x08, 0xB94B2E69),  # ldr w9, [x19, #0xb2c]
            (0x0C, 0xD343FD29),  # lsr x9, x9, #3
            (0x10, 0xB3687124),  # bfi x4, x9, #24, #29
        ]
        recovered = recover_g17_abi.classify_g17_value_argument(instructions, 5)
        expression = recovered["expression"]
        self.assertEqual(expression["operation"], "bfm")
        self.assertEqual(expression["destination"]["operation"], "and")
        self.assertEqual(expression["source"]["operation"], "ubfm")

    def test_recovers_g17_register_add_expression(self) -> None:
        instructions = [
            (0x00, 0xF943B279),  # ldr x25, [x19, #0x760]
            (0x04, 0xF943B67C),  # ldr x28, [x19, #0x768]
            (0x08, 0x8B1C0324),  # add x4, x25, x28
        ]
        recovered = recover_g17_abi.classify_g17_value_argument(instructions, 3)
        expression = recovered["expression"]
        self.assertEqual(expression["operation"], "add")
        self.assertEqual(expression["modifier"], "lsl")
        self.assertEqual(expression["amount"], 0)
        self.assertEqual(expression["first"]["member"], 0x760)
        self.assertEqual(expression["second"]["member"], 0x768)

    def test_recovers_g17_conditional_value_and_predicate(self) -> None:
        instructions = [
            (0x00, 0xF943A269),  # ldr x9, [x19, #0x740]
            (0x04, 0x395F866A),  # ldrb w10, [x19, #0x7e1]
            (0x08, 0x7200015F),  # tst w10, #1
            (0x0C, 0x926BE92A),  # and x10, x9, #0xffffffffffe0ffff
            (0x10, 0xB26C014A),  # orr x10, x10, #0x100000
            (0x14, 0x9A891144),  # csel x4, x10, x9, ne
        ]
        recovered = recover_g17_abi.classify_g17_value_argument(instructions, 6)
        expression = recovered["expression"]
        self.assertEqual(expression["operation"], "csel")
        self.assertEqual(expression["condition"], "ne")
        self.assertEqual(expression["first"]["operation"], "orr")
        self.assertEqual(expression["second"]["member"], 0x740)
        self.assertEqual(expression["predicate"]["operation"], "tst")
        self.assertEqual(expression["predicate"]["source"]["member"], 0x7E1)
        self.assertEqual(expression["predicate"]["immediate"], 1)

    def test_recovers_g17_argument_rooted_object_load(self) -> None:
        ldr_w8_x21_020 = 0xB9400008 | (21 << 5) | ((0x20 // 4) << 10)
        instructions = [
            (0x00, 0xAA0103F5),  # mov x21, x1 (command argument)
            (0x04, ldr_w8_x21_020),
            (0x08, 0x92401904),  # and x4, x8, #0x7f
        ]
        recovered = recover_g17_abi.classify_g17_value_argument(instructions, 3)
        source = recovered["expression"]["source"]
        self.assertEqual(source["kind"], "object_load")
        self.assertEqual(source["member"], 0x20)
        self.assertEqual(source["base"]["operation"], "copy")
        self.assertEqual(source["base"]["source"]["kind"], "argument")
        self.assertEqual(source["base"]["source"]["name"], "command")

    def test_recovers_g17_argument_through_stack_spill(self) -> None:
        orr_x24_x10_x9_lsl_32 = (
            0xAA000000 | 9 << 16 | 32 << 10 | 10 << 5 | 24
        )
        instructions = [
            (0x00, str_x(1, 31, 0x38)),
            (0x04, ldr_x(25, 31, 0x38)),
            (0x08, ldr_w(10, 25, 0x20)),
            (0x0C, ldr_w(9, 19, 0x760)),
            (0x10, orr_x24_x10_x9_lsl_32),
            (0x14, 0xAA1803E4),  # mov x4, x24
        ]
        recovered = recover_g17_abi.classify_g17_value_argument(instructions, 6)
        expression = recovered["expression"]["source"]
        self.assertEqual(expression["operation"], "orr")
        stack = expression["first"]["base"]
        self.assertEqual(stack["kind"], "stack_reload")
        self.assertEqual(stack["slot"], 0x38)
        self.assertEqual(stack["store_offset"], 0)
        self.assertEqual(stack["source"]["name"], "command")

    def test_does_not_trace_g17_stack_spill_across_join(self) -> None:
        instructions = [
            (0x00, b(0x00, 0x08)),
            (0x04, str_x(1, 31, 0x38)),
            (0x08, ldr_x(8, 31, 0x38)),
            (0x0C, 0xAA0803E4),  # mov x4, x8
        ]
        recovered = recover_g17_abi.classify_g17_value_argument(instructions, 4)
        self.assertEqual(recovered["kind"], "computed")
        self.assertNotIn("expression", recovered)

    def test_recovers_g17_paired_object_and_stack_loads(self) -> None:
        object_instructions = [
            (0x00, 0xAA0103F5),  # mov x21, x1 (command argument)
            (0x04, ldp_x(8, 9, 21, 0x20)),
            (0x08, 0x927AE524),  # and x4, x9, #0xffffffffffffffc0
        ]
        recovered = recover_g17_abi.classify_g17_value_argument(
            object_instructions, 3
        )
        source = recovered["expression"]["source"]
        self.assertEqual(source["kind"], "object_load")
        self.assertEqual(source["member"], 0x28)
        self.assertEqual(source["base"]["source"]["name"], "command")

        stack_instructions = [
            (0x00, stp_x(1, 2, 31, 0x20)),
            (0x04, ldp_x(8, 9, 31, 0x20)),
            (0x08, 0xAA0903E4),  # mov x4, x9
        ]
        recovered = recover_g17_abi.classify_g17_value_argument(
            stack_instructions, 3
        )
        stack = recovered["expression"]["source"]
        self.assertEqual(stack["kind"], "stack_reload")
        self.assertEqual(stack["slot"], 0x28)
        self.assertEqual(stack["source"]["name"], "descriptor")

    def test_recovers_g17_expression_through_value_copy(self) -> None:
        instructions = [
            (0x00, 0xF943B268),  # ldr x8, [x19, #0x760]
            (0x04, 0x927AE516),  # and x22, x8, #0xffffffffffffffc0
            (0x08, 0xAA1603E4),  # mov x4, x22
        ]
        recovered = recover_g17_abi.classify_g17_value_argument(instructions, 3)
        self.assertEqual(recovered["operation"], "register_copy")
        self.assertEqual(recovered["expression"]["operation"], "copy")
        self.assertEqual(recovered["expression"]["source"]["operation"], "and")
        self.assertEqual(
            recovered["expression"]["source"]["source"]["member"], 0x760
        )

    def test_resolves_selector_across_mutually_exclusive_call(self) -> None:
        instructions = [
            (0x00, 0x5294E802),  # mov w2, #0xa740
            (0x04, 0xD503201F),  # nop (the real producer branches here)
            (0x08, 0xD73F0910),  # blraa x8, x16
            (0x0C, 0x14000003),  # b +0xc, skipping the alternate call
            (0x10, 0x52800024),  # mov w4, #1
            (0x14, 0xD73F0910),  # alternate blraa x8, x16
            (0x18, 0xD503201F),
        ]
        self.assertEqual(
            recover_g17_abi.resolve_static_w_register(instructions, 5, 2),
            0xA740,
        )
        self.assertIsNone(
            recover_g17_abi.resolve_static_w_register(instructions[:4], 3, 2)
        )

    def test_recovers_g17_inline_register_records(self) -> None:
        anchors = {
            "3D": {
                0x100: 0x0A18014A, 0x104: 0x5282E72B, 0x108: 0x2A0B014A,
                0x10C: 0xB900A12A, 0x114: 0x5280002B, 0x178: 0x0A180129,
                0x17C: 0x5282FC2B, 0x180: 0x2A0B0129, 0x184: 0xB9000109,
                0x188: 0xF800410A, 0x194: 0x11003129,
            },
            "TA": {
                0x088: 0x0A0A0129, 0x08C: 0x5282FC2B, 0x090: 0x2A0B0129,
                0x094: 0xB90062A9, 0x098: 0x52800029, 0x09C: 0xF80642A9,
                0x0C8: 0x0A0A0129, 0x0CC: 0x5282FE2A, 0x0D0: 0x2A0A0129,
                0x0D4: 0xB9000109, 0x0DC: 0xF8004109, 0x0F4: 0x11003129,
            },
            "FastBlit": {
                0x06C: 0x120E4D29, 0x070: 0x5282E72A, 0x074: 0x2A0A0129,
                0x078: 0xB9000109, 0x080: 0xF8004109, 0x114: 0x5280F21C,
                0x118: 0x72A0003C, 0x124: 0x120E4129, 0x128: 0x0B1C0129,
                0x12C: 0x511E1D29, 0x130: 0xB9000D09, 0x134: 0xF9000916,
                0x140: 0x11003129,
            },
            "CL": {
                0x03C: 0xF9400815, 0x090: 0x0A0B0129, 0x094: 0x5282FC2A,
                0x098: 0x2A0A0129, 0x09C: 0xB9004289, 0x0A4: 0xF8044289,
                0x0B8: 0x91404EAA, 0x0BC: 0x91080156, 0x0D8: 0x0A0B0129,
                0x0DC: 0x5282FE2A, 0x0E0: 0x2A0A0129, 0x0E4: 0xB9000109,
                0x0EC: 0xF8004109, 0x1330: 0xF9420A69,
                0x1334: 0xA95B22EA, 0x1338: 0xB944B2AB,
                0x133C: 0x9276810C, 0x1340: 0x528000A8,
                0x1344: 0xAA08018D, 0x134C: 0xF90001CD,
                0x1360: 0x8B0B0569, 0x1364: 0xD375D137,
                0x1368: 0x8B0C02E9, 0x137C: 0x0A0B014A,
                0x1380: 0x0B0A02CA, 0x1384: 0x1100254A,
                0x1388: 0xB907628A, 0x139C: 0x0A0B014A,
                0x13A0: 0x0B0A02CA, 0x13A4: 0x1100054A,
                0x13A8: 0xB9076E8A, 0x13AC: 0xF903BA89,
                0x13B8: 0x1100314A,
            },
        }
        codes = {}
        for label, values in anchors.items():
            code = bytearray(max(values) + 4)
            for offset, word in values.items():
                struct.pack_into("<I", code, offset, word)
            name = recover_g17_abi.REGISTER_LIST_PRODUCERS[label]
            codes[name] = (0x800000, bytes(code))
        with (
            mock.patch.object(
                recover_g17_abi,
                "macho_symbols",
                return_value={name: address for name, (address, _code) in codes.items()},
            ),
            mock.patch.object(
                recover_g17_abi,
                "symbol_code",
                side_effect=lambda _image, name: codes[name],
            ),
        ):
            recovered = recover_g17_abi.recover_g17_inline_register_records(b"")

        self.assertTrue(recovered["all_inline_forms_located"])
        self.assertTrue(recovered["all_inline_values_recovered"])
        self.assertFalse(recovered["control_flow_complete"])
        self.assertEqual(recovered["static_record_count"], 8)
        self.assertEqual(recovered["dynamic_record_count"], 2)
        self.assertEqual(
            recovered["static_records"]["FastBlit"][1]["selector"], 0x10008
        )
        self.assertEqual(recovered["static_records"]["FastBlit"][1]["mode"], 1)
        self.assertIn(
            "accelerator_base + 0x13200",
            recovered["dynamic_records"]["CL"][0]["selector_expression"],
        )
        dynamic = recovered["dynamic_records"]["CL"]
        self.assertEqual(dynamic[0]["value_expression"]["immediate"], 5)
        self.assertEqual(
            dynamic[0]["value_expression"]["source"]["mask"],
            0x7FFFFFFFC00,
        )
        self.assertEqual(
            dynamic[1]["value_expression"]["first"]["factor"], 0x1800
        )
        self.assertEqual(
            dynamic[1]["value_expression"]["second"]["source"]["member"],
            0x1B8,
        )

        cl_name = recover_g17_abi.REGISTER_LIST_PRODUCERS["CL"]
        changed_cl = bytearray(codes[cl_name][1])
        struct.pack_into("<I", changed_cl, 0x13A4, 0)
        changed_codes = dict(codes)
        changed_codes[cl_name] = (0x800000, bytes(changed_cl))
        with (
            mock.patch.object(
                recover_g17_abi,
                "macho_symbols",
                return_value={name: address for name, (address, _code) in changed_codes.items()},
            ),
            mock.patch.object(
                recover_g17_abi,
                "symbol_code",
                side_effect=lambda _image, name: changed_codes[name],
            ),
        ):
            with self.assertRaises(ValueError):
                recover_g17_abi.recover_g17_inline_register_records(b"")

    def test_collapses_g17_register_emission_cfg(self) -> None:
        instructions = [
            (0x00, b_cond(0x00, 0x0C, 0)),
            (0x04, 0xD503201F),  # event A
            (0x08, b(0x08, 0x14)),
            (0x0C, 0xD503201F),  # event B
            (0x10, b(0x10, 0x14)),
            (0x14, 0xD503201F),  # shared event C
            (0x18, 0xD65F03C0),
        ]
        recovered = recover_g17_abi.build_g17_emission_cfg(
            instructions, {0x04, 0x0C, 0x14}
        )
        self.assertEqual(recovered["entry"], [0x04, 0x0C])
        self.assertFalse(recovered["empty_return_path"])
        self.assertFalse(recovered["pre_emission_trap"])
        self.assertEqual(recovered["semantic_decision_count"], 1)
        self.assertEqual(recovered["trap_guard_count"], 0)
        self.assertEqual(recovered["decisions"][0]["condition"], "eq")
        self.assertEqual(recovered["nodes"][0]["next"], [0x14])
        self.assertEqual(recovered["nodes"][1]["next"], [0x14])
        self.assertTrue(recovered["nodes"][2]["can_return"])

        authenticated_guard = [
            (0x00, b_cond(0x00, 0x08, 0)),
            (0x04, 0xD4388E40),
            (0x08, 0xD503201F),
            (0x0C, 0xD65F03C0),
        ]
        guarded = recover_g17_abi.build_g17_emission_cfg(
            authenticated_guard, {0x08}
        )
        self.assertEqual(guarded["entry"], [0x08])
        self.assertFalse(guarded["empty_return_path"])
        self.assertTrue(guarded["pre_emission_trap"])
        self.assertEqual(guarded["semantic_decision_count"], 0)
        self.assertEqual(guarded["trap_guard_count"], 1)

    def test_rejects_g17_selector_sample_matching_emission_count(self) -> None:
        # If the literal sample ever reached the emission count the set would
        # be claiming completeness it has not earned.
        def producer() -> bytes:
            code = bytearray()
            for value in (0x1739, 0x17E1):
                code += struct.pack("<I", 0x52800000 | (value << 5) | 11)
                code += struct.pack("<I", 0x2A0B014A)
            for _ in range(2):
                code += struct.pack("<I", 0x11003129)
                code += struct.pack("<I", 0x790E1509)
            return bytes(code)

        codes = {
            name: (0x800000, producer())
            for name in recover_g17_abi.REGISTER_LIST_PRODUCERS.values()
        }
        with (
            mock.patch.object(
                recover_g17_abi,
                "macho_symbols",
                return_value={n: 0x800000 for n in codes},
            ),
            mock.patch.object(
                recover_g17_abi,
                "symbol_code",
                side_effect=lambda _image, name: codes[name],
            ),
        ):
            with self.assertRaises(ValueError):
                recover_g17_abi.recover_g17_register_selectors(b"")

    def test_recovers_g17_3d_register_lists(self) -> None:
        code = bytearray(0x27DC)
        for offset, word in {
            0x034: 0x528000D8,
            0x038: 0x72BFFF98,
            0x0C0: 0x911C82B5,
            0x0C4: 0xF10012FF,
            0x0CC: 0x8B150329,
            0x0D0: 0x91028128,
            0x0D4: 0xB907A93F,
            0x0D8: 0xF942226A,
            0x0E4: 0xF903D12A,
            0x100: 0x0A18014A,
            0x188: 0xF800410A,
            0x190: 0x794E1509,
            0x194: 0x11003129,
            0x198: 0x790E1509,
            0x19C: 0x794E110A,
            0x1A0: 0x1100054A,
            0x1A4: 0x790E110A,
            0x2560: 0x794F532A,
            0x2564: 0x7901032A,
            0x275C: 0x7910627F,
            0x2760: 0xF9041E7F,
            0x2764: 0x91210268,
            0x277C: 0xF943D329,
            0x2780: 0xF9041669,
            0x2784: 0x79410329,
            0x2788: 0x79106269,
            0x278C: 0x913B2329,
            0x2790: 0x5280006A,
            0x2794: 0xF85F812B,
            0x2798: 0xF81F810B,
            0x279C: 0x7940012B,
            0x27A0: 0x7801050B,
            0x27A4: 0x911C8129,
        }.items():
            struct.pack_into("<I", code, offset, word)

        with (
            mock.patch.object(
                recover_g17_abi,
                "macho_symbols",
                return_value={recover_g17_abi.GENERATE_REGISTER_LIST_3D: 0x700000},
            ),
            mock.patch.object(
                recover_g17_abi, "symbol_code", return_value=(0x700000, bytes(code))
            ),
        ):
            recovered = recover_g17_abi.recover_g17_3d_register_lists(b"")

        self.assertEqual(recovered["passes"], 4)
        self.assertEqual(recovered["stride"], 0x720)
        self.assertEqual(recovered["stream_offset"], 0xA0)
        self.assertEqual(recovered["entry_bytes"], 0xC)
        self.assertEqual(recovered["selector_template_mask"], 0xFFFC0006)
        self.assertEqual(recovered["gpu_base_descriptor_member"], 0x440)
        # Framing is settled: a pass owns 0x700 stream bytes and the next pass
        # begins 0x14 bytes after the previous metadata ends.
        self.assertTrue(recovered["record_framing_resolved"])
        self.assertEqual(recovered["stream_bytes"], 0x700)
        self.assertEqual(recovered["inter_pass_gap"], 0x14)
        self.assertEqual(recovered["descriptor_summary"]["offset"], 0x828)
        self.assertEqual(recovered["descriptor_summary"]["stride"], 0x10)
        self.assertEqual(recovered["descriptor_summary"]["records"], 4)

    def test_rejects_changed_g17_3d_register_entry_stride(self) -> None:
        code = bytearray(0x27DC)
        for offset, word in {
            0x034: 0x528000D8,
            0x038: 0x72BFFF98,
            0x0C0: 0x911C82B5,
            0x0C4: 0xF10012FF,
            0x0CC: 0x8B150329,
            0x0D0: 0x91028128,
            0x0D4: 0xB907A93F,
            0x0D8: 0xF942226A,
            0x0E4: 0xF903D12A,
            0x100: 0x0A18014A,
            0x188: 0xF800410A,
            0x190: 0x794E1509,
            0x194: 0x11004129,
            0x198: 0x790E1509,
            0x19C: 0x794E110A,
            0x1A0: 0x1100054A,
            0x1A4: 0x790E110A,
            0x2560: 0x794F532A,
            0x2564: 0x7901032A,
            0x275C: 0x7910627F,
            0x2760: 0xF9041E7F,
            0x2764: 0x91210268,
            0x277C: 0xF943D329,
            0x2780: 0xF9041669,
            0x2784: 0x79410329,
            0x2788: 0x79106269,
            0x278C: 0x913B2329,
            0x2790: 0x5280006A,
            0x2794: 0xF85F812B,
            0x2798: 0xF81F810B,
            0x279C: 0x7940012B,
            0x27A0: 0x7801050B,
            0x27A4: 0x911C8129,
        }.items():
            struct.pack_into("<I", code, offset, word)
        with (
            mock.patch.object(
                recover_g17_abi,
                "macho_symbols",
                return_value={recover_g17_abi.GENERATE_REGISTER_LIST_3D: 0},
            ),
            mock.patch.object(
                recover_g17_abi, "symbol_code", return_value=(0, bytes(code))
            ),
        ):
            with self.assertRaises(ValueError):
                recover_g17_abi.recover_g17_3d_register_lists(b"")

    def test_recovers_g17_channel_command_pools(self) -> None:
        sizes_address = 0x600000
        alloc_address = 0x610000
        literal_base = 0x1000

        image = bytearray(0x4000)
        struct.pack_into("<QQ", image, literal_base + 0x00, 0x2240, 0xA00)
        struct.pack_into("<QQ", image, literal_base + 0x10, 0x1040, 0x80)
        struct.pack_into("<QQ", image, literal_base + 0x20, 0x40, 0x80)
        struct.pack_into("<QQ", image, literal_base + 0x30, 0xC0, 0x40)

        sizes = bytearray(0x54)
        for offset, word in {
            0x04: 0x52813808,
            0x08: 0xF9010C08,
            0x0C: adrp(sizes_address + 0x0C, literal_base + 0x00, 8),
            0x10: 0x3DC00000 | (((literal_base & 0xFFF) // 16) << 10) | (8 << 5),
            0x14: adrp(sizes_address + 0x14, literal_base + 0x10, 8),
            0x18: 0x3DC00000 | ((((literal_base + 0x10) & 0xFFF) // 16) << 10) | (8 << 5) | 1,
            0x1C: 0xAD110400,
            0x20: 0x52800808,
            0x24: 0xF9012408,
            0x28: adrp(sizes_address + 0x28, literal_base + 0x20, 9),
            0x2C: 0x3DC00000 | ((((literal_base + 0x20) & 0xFFF) // 16) << 10) | (9 << 5),
            0x30: 0x3D809400,
            0x34: 0x52801009,
            0x38: 0x4E080D00,
            0x3C: 0xF9013409,
            0x40: adrp(sizes_address + 0x40, literal_base + 0x30, 9),
            0x44: 0x3DC00000 | ((((literal_base + 0x30) & 0xFFF) // 16) << 10) | (9 << 5) | 1,
            0x48: 0xAD138400,
            0x4C: 0xF9014808,
        }.items():
            struct.pack_into("<I", sizes, offset, word)

        # allocFirmwareData: one movz/ldr pair per pool block.
        bindings = [
            (0x1688, 0x220),
            (0x16C8, 0x228),
            (0x1708, 0x230),
            (0x1748, 0x238),
            (0x1788, 0x248),
            (0x17C8, 0x250),
            (0x1808, 0x258),
            (0x1848, 0x268),
            (0x1888, 0x270),
            (0x18C8, 0x278),
            (0x1908, 0x280),
            (0x1948, 0x288),
            (0x1988, 0x290),
        ]
        alloc = bytearray(len(bindings) * 0x10)
        for index, (block, member) in enumerate(bindings):
            base = index * 0x10
            struct.pack_into("<I", alloc, base, 0x52800000 | (block << 5) | 8)
            struct.pack_into(
                "<I", alloc, base + 4, 0xF9400000 | ((member // 8) << 10) | (19 << 5) | 9
            )

        def request(block: int) -> bytes:
            code = bytearray(0x124)
            struct.pack_into(
                "<I", code, 0x14, 0xF9400000 | (((block + 0x18) // 8) << 10) | 8
            )
            return bytes(code)

        barrier = bytearray(request(0x1748))
        for offset, word in {
            0x014: 0xF94BB008,
            0x024: 0xF94BC000,
            0x02C: 0xB9577268,
            0x034: 0xB9577669,
            0x078: 0xB9576A68,
            0x07C: 0x1B087EB6,
            0x0AC: 0x8B160008,
            0x0B0: 0xF9000288,
            0x0DC: 0xB9177668,
            0x0EC: 0xF94BAE68,
            0x0F0: 0x8B160114,
        }.items():
            struct.pack_into("<I", barrier, offset, word)

        codes = {
            recover_g17_abi.CONFIGURE_POOL_ELEMENT_SIZES: (sizes_address, bytes(sizes)),
            recover_g17_abi.BASE_ALLOC_FIRMWARE_DATA: (alloc_address, bytes(alloc)),
            recover_g17_abi.REQUEST_CHANNEL_COMMAND_BARRIER: (0x620000, bytes(barrier)),
            "__ZN11AGXFirmware23requestChannelCommand3DEPyS0_": (0x630000, request(0x1688)),
            "__ZN11AGXFirmware23requestChannelCommandTAEPyS0_": (0x640000, request(0x1648)),
        }
        symbols = {name: address for name, (address, _c) in codes.items()}
        with (
            mock.patch.object(recover_g17_abi, "macho_symbols", return_value=symbols),
            mock.patch.object(
                recover_g17_abi,
                "symbol_code",
                side_effect=lambda _image, name: codes[name],
            ),
            mock.patch.object(
                recover_g17_abi, "virtual_to_file", side_effect=lambda _image, a: a
            ),
        ):
            recovered = recover_g17_abi.recover_g17_channel_command_pools(bytes(image))

        self.assertEqual(recovered["block_bytes"], 0x40)
        self.assertEqual(recovered["block_layout"]["element_bytes"], 0x20)
        self.assertEqual(recovered["commands"]["3D"]["command_bytes"], 0x2240)
        self.assertEqual(recovered["commands"]["3D"]["block"], 0x1688)
        self.assertEqual(recovered["commands"]["Barrier"]["command_bytes"], 0x80)
        self.assertEqual(recovered["commands"]["TA"]["command_bytes"], 0x9C0)

    def test_rejects_short_g17_pool_size_producer(self) -> None:
        codes = {
            recover_g17_abi.CONFIGURE_POOL_ELEMENT_SIZES: (0, b"\x00" * 0x40),
            recover_g17_abi.BASE_ALLOC_FIRMWARE_DATA: (0, b""),
        }
        with (
            mock.patch.object(
                recover_g17_abi,
                "macho_symbols",
                return_value={n: 0 for n in codes},
            ),
            mock.patch.object(
                recover_g17_abi,
                "symbol_code",
                side_effect=lambda _image, name: codes[name],
            ),
        ):
            with self.assertRaises(ValueError):
                recover_g17_abi.recover_g17_channel_command_pools(b"")

    def test_recovers_g17_command_pool_backing(self) -> None:
        addresses = {
            recover_g17_abi.BASE_ALLOC_FIRMWARE_DATA: 0x610000,
            recover_g17_abi.COMMAND_POOL_CREATE_BACKING: 0x620000,
            recover_g17_abi.PI300_CONFIGURE_DEVICE: 0x630000,
            recover_g17_abi.G17_CONFIGURE_DEVICE: 0x640000,
        }
        alloc = bytearray(0x600)
        for offset, word in {
            0x38: 0xF9414C01,
            0x3C: 0x91404428,
            0x40: 0x91058108,
            0x44: 0xB9400119,
            0x48: 0x35000059,
            0x4C: 0xB9471839,
            0x300: 0x0B190734,
            0x580: 0x5282D108,
            0x594: 0xAA1403E1,
            0x5A0: 0x5282D908,
            0x5B4: 0xAA1403E1,
            0x5C0: 0x5282E108,
            0x5D4: 0xAA1403E1,
        }.items():
            struct.pack_into("<I", alloc, offset, word)
        for offset in (0x598, 0x5B8, 0x5D8):
            struct.pack_into(
                "<I",
                alloc,
                offset,
                bl(addresses[recover_g17_abi.BASE_ALLOC_FIRMWARE_DATA] + offset,
                   addresses[recover_g17_abi.COMMAND_POOL_CREATE_BACKING]),
            )

        create = bytearray(0x300)
        for offset, word in {
            0x28: 0xF9000002,
            0x2C: 0xF9401017,
            0x68: 0x2A1503E8,
            0x6C: 0x52800029,
            0x70: 0x1AD82129,
            0x78: 0x9B0826E8,
            0x7C: 0xD1000508,
            0x80: 0xCB0903E9,
            0x84: 0x8A090115,
            0x29C: 0xF9000674,
            0x2C8: 0xF9000A60,
            0x2D0: 0xF9401268,
            0x2D4: 0x9AC80AA8,
            0x2D8: 0xB9002A68,
            0x2E4: 0xF9000E60,
        }.items():
            struct.pack_into("<I", create, offset, word)

        pi_configure = bytearray(0x90)
        struct.pack_into("<II", pi_configure, 0x88, 0x52800A09, 0xB9071A69)
        g17_configure = bytearray(0xC8)
        for offset, word in {
            0x30: 0x91404408,
            0x34: 0x91058114,
            0xA8: 0xB9400288,
            0xAC: 0x35000048,
            0xB0: 0xB9471A68,
            0xC4: 0xB9072A68,
        }.items():
            struct.pack_into("<I", g17_configure, offset, word)

        codes = {
            recover_g17_abi.BASE_ALLOC_FIRMWARE_DATA: bytes(alloc),
            recover_g17_abi.COMMAND_POOL_CREATE_BACKING: bytes(create),
            recover_g17_abi.PI300_CONFIGURE_DEVICE: bytes(pi_configure),
            recover_g17_abi.G17_CONFIGURE_DEVICE: bytes(g17_configure),
        }
        with (
            mock.patch.object(recover_g17_abi, "macho_symbols", return_value=addresses),
            mock.patch.object(
                recover_g17_abi,
                "symbol_code",
                side_effect=lambda _image, name: (addresses[name], codes[name]),
            ),
        ):
            recovered = recover_g17_abi.recover_g17_command_pool_backing(b"")

        self.assertEqual(recovered["capacity_override_member"], 0x11160)
        self.assertEqual(recovered["fallback_capacity"], 80)
        self.assertEqual(recovered["work_pool_multiplier"], 3)
        self.assertEqual(recovered["fallback_work_requested_slots"], 240)
        self.assertEqual(recovered["slot_count_formula"],
                         "backing_bytes / element_bytes")

    def test_rejects_changed_g17_command_pool_backing(self) -> None:
        addresses = {
            recover_g17_abi.BASE_ALLOC_FIRMWARE_DATA: 0x610000,
            recover_g17_abi.COMMAND_POOL_CREATE_BACKING: 0x620000,
            recover_g17_abi.PI300_CONFIGURE_DEVICE: 0x630000,
            recover_g17_abi.G17_CONFIGURE_DEVICE: 0x640000,
        }
        codes = {name: bytearray(0x600) for name in addresses}
        with (
            mock.patch.object(recover_g17_abi, "macho_symbols", return_value=addresses),
            mock.patch.object(
                recover_g17_abi,
                "symbol_code",
                side_effect=lambda _image, name: (addresses[name], bytes(codes[name])),
            ),
        ):
            with self.assertRaises(ValueError):
                recover_g17_abi.recover_g17_command_pool_backing(b"")

    def test_recovers_g17_3d_command_reclamation(self) -> None:
        code = bytearray(0x300)
        for offset, word in {
            0x16C: 0xF9421E68,
            0x1F4: 0xF942D934,
            0x1F8: 0xB9569A89,
            0x1FC: 0x4B090108,
            0x200: 0xF94B5689,
            0x204: 0x9AC90915,
            0x208: 0xF94B6280,
            0x210: 0xF94B5288,
            0x214: 0x8B150109,
            0x218: 0x39400129,
            0x21C: 0x34000069,
            0x220: 0x51000529,
            0x224: 0x38356909,
            0x238: 0xF9021E7F,
        }.items():
            struct.pack_into("<I", code, offset, word)

        with (
            mock.patch.object(
                recover_g17_abi,
                "macho_symbols",
                return_value={recover_g17_abi.COMPLETE_COMMAND_3D: 0x920000},
            ),
            mock.patch.object(
                recover_g17_abi, "symbol_code", return_value=(0x920000, bytes(code))
            ),
        ):
            recovered = recover_g17_abi.recover_g17_3d_command_reclamation(b"")

        self.assertEqual(recovered["descriptor_command_cpu_member"], 0x438)
        self.assertEqual(recovered["pool_block"], 0x1688)
        self.assertEqual(recovered["pool_in_use_member"], 0x16A0)
        self.assertTrue(recovered["decrement_if_nonzero"])
        self.assertTrue(recovered["clear_descriptor_pointer"])

    def test_rejects_changed_g17_3d_command_reclamation(self) -> None:
        code = bytearray(0x300)
        with (
            mock.patch.object(
                recover_g17_abi,
                "macho_symbols",
                return_value={recover_g17_abi.COMPLETE_COMMAND_3D: 0x920000},
            ),
            mock.patch.object(
                recover_g17_abi, "symbol_code", return_value=(0x920000, bytes(code))
            ),
        ):
            with self.assertRaises(ValueError):
                recover_g17_abi.recover_g17_3d_command_reclamation(b"")

    def test_recovers_g17_queue_device_inputs(self) -> None:
        queue_address = 0x500000
        device_address = 0x510000
        shared_address = 0x520000
        role_address = 0x530000
        proc_pid_address = 0x540000

        queue = bytearray(0x200)
        for offset, word in {
            0x0F8: 0xF9024A74,
            0x0FC: 0xB9406288,
            0x100: 0xB9049A68,
        }.items():
            struct.pack_into("<I", queue, offset, word)

        device = bytearray(0x21C)
        for offset, word in {
            0x0E0: bl(device_address + 0x0E0, proc_pid_address),
            0x0E4: 0xB9006260,
            0x104: bl(device_address + 0x104, proc_pid_address),
            0x108: 0xB9006260,
        }.items():
            struct.pack_into("<I", device, offset, word)

        shared = bytearray(0x210)
        for offset, word in {0x100: 0x52800048, 0x104: 0x39048268}.items():
            struct.pack_into("<I", shared, offset, word)

        role = bytearray(0x300)
        for offset, word in {
            0x2EC: 0x7100111F,
            0x2F0: 0x54000D22,
            0x2F8: 0x39048118,
        }.items():
            struct.pack_into("<I", role, offset, word)

        iogpu_codes = {
            recover_g17_abi.IOGPU_COMMAND_QUEUE_INIT: (queue_address, bytes(queue)),
            recover_g17_abi.IOGPU_DEVICE_INIT: (device_address, bytes(device)),
        }
        driver_codes = {
            recover_g17_abi.AGX_SHARED_INIT: (shared_address, bytes(shared)),
            recover_g17_abi.AGX_SHARED_SET_APP_GPU_ROLE: (role_address, bytes(role)),
        }
        symbol_tables = {
            b"iogpu": {n: a for n, (a, _c) in iogpu_codes.items()},
            b"driver": {n: a for n, (a, _c) in driver_codes.items()},
        }
        codes = iogpu_codes | driver_codes
        with (
            mock.patch.object(
                recover_g17_abi,
                "macho_symbols",
                side_effect=lambda image: symbol_tables[image],
            ),
            mock.patch.object(
                recover_g17_abi,
                "symbol_code",
                side_effect=lambda _image, name: codes[name],
            ),
        ):
            recovered = recover_g17_abi.recover_g17_queue_device_inputs(
                b"driver", b"iogpu"
            )

        self.assertEqual(recovered["queue_device_member"], 0x490)
        self.assertEqual(recovered["queue_value_member"], 0x498)
        self.assertEqual(recovered["process_id"]["channel_state_offset"], 0x48)
        self.assertEqual(recovered["process_id"]["device_member"], 0x60)
        self.assertEqual(recovered["process_id"]["producer_address"], proc_pid_address)
        self.assertEqual(recovered["app_gpu_role"]["default"], 2)
        self.assertEqual(recovered["app_gpu_role"]["maximum"], 3)
        self.assertEqual(recovered["app_gpu_role"]["scheduler_state_offset"], 0x26)

    def test_rejects_split_g17_device_process_id_producers(self) -> None:
        # Both IOGPUDevice::init paths must reach the same producer.
        queue_address = 0x500000
        device_address = 0x510000
        queue = bytearray(0x200)
        for offset, word in {
            0x0F8: 0xF9024A74,
            0x0FC: 0xB9406288,
            0x100: 0xB9049A68,
        }.items():
            struct.pack_into("<I", queue, offset, word)
        device = bytearray(0x21C)
        for offset, word in {
            0x0E0: bl(device_address + 0x0E0, 0x540000),
            0x0E4: 0xB9006260,
            0x104: bl(device_address + 0x104, 0x550000),
            0x108: 0xB9006260,
        }.items():
            struct.pack_into("<I", device, offset, word)
        codes = {
            recover_g17_abi.IOGPU_COMMAND_QUEUE_INIT: (queue_address, bytes(queue)),
            recover_g17_abi.IOGPU_DEVICE_INIT: (device_address, bytes(device)),
        }
        symbols = {n: a for n, (a, _c) in codes.items()} | {
            recover_g17_abi.AGX_SHARED_INIT: 0,
            recover_g17_abi.AGX_SHARED_SET_APP_GPU_ROLE: 0,
        }
        with (
            mock.patch.object(
                recover_g17_abi, "macho_symbols", return_value=symbols
            ),
            mock.patch.object(
                recover_g17_abi,
                "symbol_code",
                side_effect=lambda _image, name: codes[name],
            ),
        ):
            with self.assertRaises(ValueError):
                recover_g17_abi.recover_g17_queue_device_inputs(b"d", b"i")

    def test_recovers_g17_channel_runtime_resources(self) -> None:
        fixtures = {
            recover_g17_abi.PI300_CONFIGURE_DEVICE: bytearray(0x90),
            recover_g17_abi.BASE_ALLOC_FIRMWARE_DATA: bytearray(0xB4),
            recover_g17_abi.AGX_COMMAND_QUEUE_INIT: bytearray(0xE4),
            recover_g17_abi.AGX_WORK_QUEUE_INIT: bytearray(0x3C),
            recover_g17_abi.ALLOCATE_3D_WORK_QUEUE: bytearray(0x1B0),
            recover_g17_abi.ALLOCATE_CL_WORK_QUEUE: bytearray(0x11C),
            recover_g17_abi.TIMESTAMP_QUEUE_INIT: bytearray(0x490),
            recover_g17_abi.RESET_TIMESTAMP_QUEUE: bytearray(0x38),
            recover_g17_abi.IOGPU_WORK_QUEUE_INIT: bytearray(0x58),
        }
        expected = {
            recover_g17_abi.PI300_CONFIGURE_DEVICE: {
                0x084: 0xF9436A68,
                0x088: 0x52800A09,
                0x08C: 0xB9071A69,
            },
            recover_g17_abi.BASE_ALLOC_FIRMWARE_DATA: {
                0x038: 0xF9414C01,
                0x03C: 0x91404428,
                0x040: 0x91058108,
                0x044: 0xB9400119,
                0x048: 0x35000059,
                0x04C: 0xB9471839,
                0x050: 0x52825108,
                0x054: 0x8B080274,
                0x074: 0xAA1403E0,
                0x078: 0x52800302,
                0x07C: 0x52800124,
                0x080: 0x52800005,
                0x084: 0xD2800006,
                0x088: 0x52800007,
            },
            recover_g17_abi.AGX_COMMAND_QUEUE_INIT: {
                0x0C8: 0xF9429E68,
                0x0CC: 0x91404509,
                0x0D0: 0x91058129,
                0x0D4: 0xB9400129,
                0x0D8: 0x35000049,
                0x0DC: 0xB9471909,
                0x0E0: 0xB9088269,
            },
            recover_g17_abi.AGX_WORK_QUEUE_INIT: {
                0x02C: 0xF940A908,
                0x030: 0xAA0903F1,
                0x034: 0xF2E76F11,
                0x038: 0xD73F0911,
            },
            recover_g17_abi.ALLOCATE_3D_WORK_QUEUE: {
                0x058: 0xF9429E81,
                0x05C: 0xB9488283,
                0x0A0: 0xF9434288,
                0x0A4: 0xF9401515,
                0x12C: 0xAA1503E5,
                0x1A8: 0xF9434288,
                0x1AC: 0xF9401501,
            },
            recover_g17_abi.ALLOCATE_CL_WORK_QUEUE: {
                0x04C: 0xF9429E81,
                0x050: 0xB9488283,
                0x08C: 0xF9434288,
                0x090: 0xF9401515,
                0x118: 0xAA1503E5,
            },
            recover_g17_abi.TIMESTAMP_QUEUE_INIT: {
                0x05C: 0xF942DA95,
                0x064: 0x8B0802B4,
                0x24C: 0x8B160008,
                0x250: 0xF9001668,
                0x2C0: 0x8B160008,
                0x2D4: 0xF9001268,
            },
            recover_g17_abi.RESET_TIMESTAMP_QUEUE: {
                0x004: 0xF9401008,
                0x008: 0xA9007D1F,
                0x00C: 0xF900091F,
                0x018: 0xA9422009,
                0x01C: 0xF9000528,
                0x020: 0xB9403808,
                0x024: 0x7100091F,
                0x028: 0x1A9F17E8,
                0x02C: 0xF9401009,
                0x030: 0x29027D28,
            },
            recover_g17_abi.IOGPU_WORK_QUEUE_INIT: {
                0x018: 0xAA0303F7,
                0x050: 0xF9002268,
                0x054: 0xB9005677,
            },
        }
        for name, words in expected.items():
            for offset, word in words.items():
                struct.pack_into("<I", fixtures[name], offset, word)

        driver_names = set(expected) - {recover_g17_abi.IOGPU_WORK_QUEUE_INIT}
        driver_codes = {
            name: (0x600000 + index * 0x10000, bytes(fixtures[name]))
            for index, name in enumerate(driver_names)
        }
        iogpu_codes = {
            recover_g17_abi.IOGPU_WORK_QUEUE_INIT: (
                0x800000,
                bytes(fixtures[recover_g17_abi.IOGPU_WORK_QUEUE_INIT]),
            )
        }
        tables = {
            b"driver": {name: address for name, (address, _code) in driver_codes.items()},
            b"iogpu": {name: address for name, (address, _code) in iogpu_codes.items()},
        }
        codes = driver_codes | iogpu_codes
        with (
            mock.patch.object(
                recover_g17_abi,
                "macho_symbols",
                side_effect=lambda image: tables[image],
            ),
            mock.patch.object(
                recover_g17_abi,
                "symbol_code",
                side_effect=lambda _image, name: codes[name],
            ),
        ):
            recovered = recover_g17_abi.recover_g17_channel_runtime_resources(
                b"driver", b"iogpu"
            )

        self.assertEqual(recovered["configured_queues"]["default"], 80)
        self.assertEqual(recovered["configured_queues"]["command_queue_member"], 0x880)
        self.assertEqual(recovered["channel_ring"]["default_entries"], 1280)
        self.assertEqual(recovered["channel_ring"]["default_pointer_bytes"], 0x2800)
        self.assertEqual(recovered["timestamp_state"]["bytes"], 0x18)
        self.assertEqual(recovered["timestamp_state"]["object_gpu_member"], 0x28)
        self.assertEqual(
            recovered["timestamp_state"]["context_cookie_state_offset"], 0x10
        )

    def test_rejects_changed_g17_channel_runtime_resources(self) -> None:
        with self.assertRaises(ValueError):
            recover_g17_abi.recover_g17_channel_runtime_resources(b"", b"")

    def test_recovers_g17_scheduler_state(self) -> None:
        alloc_address = 0x400000
        stack_init_address = 0x410000
        queue_address = 0x420000
        name_address = 0x1000

        image = bytearray(0x2000)
        image[name_address : name_address + 23] = b"AGFICmdQueueSchedState\0"

        alloc = bytearray(0xE38)
        for offset, word in {
            0xD54: 0xF9414E61,
            0xD58: 0x52829908,
            0xD5C: 0x8B080274,
            0xD74: adrp(alloc_address + 0xD74, name_address, 3),
            0xD78: add_immediate(3, 3, name_address & 0xFFF),
            0xD7C: 0xAA1403E0,
            0xD80: 0x52800802,
            0xD84: 0x52800124,
            0xD88: 0x52800025,
            0xD8C: 0xD2800006,
            0xD90: 0x52800007,
        }.items():
            struct.pack_into("<I", alloc, offset, word)

        stack = bytearray(0xC4)
        for offset, word in {
            0x20: 0xAA0203F5,
            0x68: 0xF9005275,
            0x7C: 0x8B150509,
            0x80: 0xD1000529,
            0x84: 0xCB0803E8,
            0x88: 0x8A080128,
            0x8C: 0xF9002E68,
            0x90: 0x9AD50908,
            0x94: 0xB9006268,
        }.items():
            struct.pack_into("<I", stack, offset, word)

        queue = bytearray(0x42C)
        for offset, word in {
            0x028: 0xF9429C08,
            0x02C: 0xF942D915,
            0x030: 0x52829908,
            0x0EC: 0xB9552ABB,
            0x0F0: 0x1ADB0B1C,
            0x144: 0xF9045660,
            0x1E8: 0x1B1BE389,
            0x1EC: 0x9B097ED6,
            0x220: 0x8B160008,
            0x224: 0xF9045E68,
            0x2A8: 0xF9045268,
            0x348: 0xB908B278,
            0x3BC: 0xF9445268,
            0x3C0: 0xF900191F,
            0x3C8: 0xAD008100,
            0x3CC: 0x3D800100,
            0x3D0: 0xF9445268,
            0x3D4: 0x529FFFE9,
            0x3D8: 0x79000109,
            0x3DC: 0x52800020,
            0x3E0: 0x39001500,
            0x3E4: 0x52801FE9,
            0x3E8: 0x3900CD09,
            0x3EC: 0xB802211F,
            0x3F0: 0xF9424A69,
            0x3F4: 0x39448129,
            0x3F8: 0x39009909,
        }.items():
            struct.pack_into("<I", queue, offset, word)

        codes = {
            recover_g17_abi.ARM_ALLOC_FIRMWARE_DATA: (alloc_address, bytes(alloc)),
            recover_g17_abi.SCHEDULER_STATE_STACK_INIT: (
                stack_init_address,
                bytes(stack),
            ),
            recover_g17_abi.ALLOCATE_SCHEDULER_STATE: (queue_address, bytes(queue)),
        }
        symbols = {name: address for name, (address, _c) in codes.items()}
        symbols[recover_g17_abi.SCHEDULER_STATE_STACK_VTABLE] = 0x430000
        with (
            mock.patch.object(
                recover_g17_abi, "macho_symbols", return_value=symbols
            ),
            mock.patch.object(
                recover_g17_abi,
                "symbol_code",
                side_effect=lambda _image, name: codes[name],
            ),
            mock.patch.object(
                recover_g17_abi, "virtual_to_file", side_effect=lambda _image, a: a
            ),
            mock.patch.object(
                recover_g17_abi,
                "recover_vtable_target",
                return_value=stack_init_address,
            ),
        ):
            recovered = recover_g17_abi.recover_g17_scheduler_state(bytes(image))

        self.assertEqual(recovered["pool_name"], "AGFICmdQueueSchedState")
        self.assertEqual(recovered["element_bytes"], 0x40)
        self.assertEqual(recovered["queue_bindings"]["gpu_address"], 0x8B8)
        self.assertEqual(recovered["queue_bindings"]["cpu_address"], 0x8A0)
        self.assertEqual(recovered["stack_host_member"], 0x14C8)
        self.assertEqual(recovered["zeroed_bytes"], 0x38)
        self.assertEqual(
            [field["offset"] for field in recovered["initial_fields"]],
            [0x00, 0x05, 0x22, 0x26, 0x33],
        )
        self.assertEqual(recovered["initial_fields"][0]["value"], 0xFFFF)
        self.assertEqual(recovered["initial_fields"][-1]["value"], 0xFF)

    def test_rejects_changed_g17_scheduler_state_element_size(self) -> None:
        with self.assertRaises(ValueError):
            recover_g17_abi.recover_g17_scheduler_state(b"")

    def test_recovers_g17_channel_state_sources(self) -> None:
        init_address = 0x300000
        qos_address = 0x310000

        reset = bytearray(0x224)
        for offset, word in {
            0x05C: 0xB9404C08,
            0x064: 0xB9004928,
            0x078: 0xF9407C0A,
            0x07C: 0xF809C12A,
            0x088: 0xB940540B,
            0x08C: 0xB900614B,
        }.items():
            struct.pack_into("<I", reset, offset, word)

        qos = bytearray(0x28)
        for offset, word in {
            0x04: 0xF9466808,
            0x08: 0x5298E509,
            0x0C: 0x8B090108,
            0x10: 0x52800029,
            0x14: 0xB9000109,
            0x18: 0xF941C008,
            0x1C: 0xB9005101,
            0x20: 0xB9004D02,
        }.items():
            struct.pack_into("<I", qos, offset, word)

        init = bytearray(0x1514)
        for offset, word in {
            0x068: 0xB9449AA8,
            0x078: 0xF9445EA9,
            0x07C: 0xF9007E69,
            0x094: 0x12800009,
            0x098: 0x29092269,
            0x5B8: 0x52801009,
            0x5BC: 0x710202DF,
            0x5C0: 0x1A8932C9,
            0x5C4: 0x531C6D29,
            0x5C8: 0xB9005669,
        }.items():
            struct.pack_into("<I", init, offset, word)

        codes = {
            recover_g17_abi.CHANNEL_INIT: (init_address, bytes(init)),
            recover_g17_abi.SET_KICK_CHANNEL_QOS: (qos_address, bytes(qos)),
        }
        with (
            mock.patch.object(
                recover_g17_abi,
                "macho_symbols",
                return_value={
                    recover_g17_abi.CHANNEL_INIT: init_address,
                    recover_g17_abi.SET_KICK_CHANNEL_QOS: qos_address,
                },
            ),
            mock.patch.object(
                recover_g17_abi,
                "symbol_code",
                side_effect=lambda _image, name: codes[name],
            ),
        ):
            recovered = recover_g17_abi.recover_g17_channel_state_sources(
                b"", bytes(reset)
            )

        self.assertEqual(recovered["queue_value"]["state_offset"], 0x48)
        self.assertEqual(recovered["queue_value"]["queue_seed_member"], 0x498)
        self.assertEqual(recovered["queue_address"]["state_offset"], 0x9C)
        self.assertEqual(recovered["queue_address"]["queue_seed_member"], 0x8B8)
        self.assertEqual(recovered["ring_entries"]["multiplier"], 16)
        self.assertEqual(recovered["ring_entries"]["maximum_request"], 0x80)
        # The runtime QoS pair shares the +0x4c offset but is a different object.
        self.assertTrue(
            recovered["runtime_kick_channel_qos"]["distinct_from_channel_state"]
        )
        self.assertEqual(
            recovered["runtime_kick_channel_qos"]["runtime_host_member"], 0x380
        )

    def test_recovers_g17_channel_data_master_types(self) -> None:
        base_address = 0x300000
        wrapper_addresses = {
            "TA": 0x310000,
            "3D": 0x320000,
            "CL": 0x330000,
        }
        symbols = {recover_g17_abi.CHANNEL_INIT: base_address}
        codes = {}
        for kind, value in (("TA", 0), ("3D", 1), ("CL", 2)):
            symbol = recover_g17_abi.G17_CHANNEL_INITIALIZERS[kind]
            address = wrapper_addresses[kind]
            symbols[symbol] = address
            codes[symbol] = (
                address,
                struct.pack(
                    "<II",
                    0x52800006 | value << 5,
                    bl(address + 4, base_address),
                ),
            )

        with (
            mock.patch.object(recover_g17_abi, "macho_symbols", return_value=symbols),
            mock.patch.object(
                recover_g17_abi,
                "symbol_code",
                side_effect=lambda _image, name: codes[name],
            ),
        ):
            recovered = recover_g17_abi.recover_g17_channel_data_master_types(b"")

        self.assertEqual(
            {
                kind: item["data_master_type"]
                for kind, item in recovered["subclasses"].items()
            },
            {"TA": 0, "3D": 1, "CL": 2},
        )
        self.assertEqual(recovered["base_initializer"], recover_g17_abi.CHANNEL_INIT)

    def test_rejects_changed_g17_channel_data_master_type(self) -> None:
        base_address = 0x300000
        symbols = {recover_g17_abi.CHANNEL_INIT: base_address}
        codes = {}
        for index, kind in enumerate(("TA", "3D", "CL")):
            symbol = recover_g17_abi.G17_CHANNEL_INITIALIZERS[kind]
            address = 0x310000 + index * 0x10000
            symbols[symbol] = address
            codes[symbol] = (
                address,
                struct.pack(
                    "<II",
                    0x52800006,
                    bl(address + 4, base_address),
                ),
            )

        with (
            mock.patch.object(recover_g17_abi, "macho_symbols", return_value=symbols),
            mock.patch.object(
                recover_g17_abi,
                "symbol_code",
                side_effect=lambda _image, name: codes[name],
            ),
            self.assertRaises(ValueError),
        ):
            recover_g17_abi.recover_g17_channel_data_master_types(b"")

    def test_recovers_g17_channel_identity(self) -> None:
        channel = bytearray(0x64)
        for offset, word in {
            0x048: 0x91052109,
            0x04C: 0xF940A508,
            0x050: 0xF9429C21,
            0x054: 0x52801002,
            0x060: 0xD73F0911,
        }.items():
            struct.pack_into("<I", channel, offset, word)
        base = bytearray(0x48)
        for offset, word in {
            0x018: 0xAA0203F4,
            0x040: 0xF9000A75,
            0x044: 0xB9001A74,
        }.items():
            struct.pack_into("<I", base, offset, word)

        def symbols(image: bytes):
            if image == b"driver":
                return {recover_g17_abi.CHANNEL_INIT: 0x300000}
            return {recover_g17_abi.IOGPU_CHANNEL_INIT: 0x400000}

        def code(image: bytes, name: str):
            if image == b"driver" and name == recover_g17_abi.CHANNEL_INIT:
                return 0x300000, bytes(channel)
            if image == b"iogpu" and name == recover_g17_abi.IOGPU_CHANNEL_INIT:
                return 0x400000, bytes(base)
            raise AssertionError(name)

        with (
            mock.patch.object(recover_g17_abi, "macho_symbols", side_effect=symbols),
            mock.patch.object(recover_g17_abi, "symbol_code", side_effect=code),
        ):
            recovered = recover_g17_abi.recover_g17_channel_identity(
                b"driver", b"iogpu"
            )

        self.assertEqual(recovered["value"], 0x80)
        self.assertEqual(recovered["channel_member"], 0x18)
        self.assertEqual(recovered["outer_entry_bytes"], 1)
        self.assertEqual(recovered["base_owner"]["command_queue_member"], 0x538)

    def test_rejects_changed_g17_channel_identity(self) -> None:
        with self.assertRaises(ValueError):
            recover_g17_abi.recover_g17_channel_identity(b"", b"")

    def test_recovers_g17_linear_power_transfer_tables(self) -> None:
        arm_power, fixtures = self._linear_power_transfer_fixtures()
        recovered = self._run_linear_power_transfer(arm_power, fixtures)

        self.assertTrue(recovered["die_dependent"])
        self.assertEqual(
            [table["offset"] for table in recovered["tables"]], [0x18C8, 0x1948]
        )
        primary, afr = recovered["tables"]
        self.assertEqual(primary["matrix_source_offset"], 0x1C630)
        self.assertEqual(primary["matrix_row_bytes"], 0x40)
        self.assertEqual(primary["matrix_column_count_offset"], 0x4E4)
        self.assertEqual(primary["clamp"], 48500.0)
        self.assertEqual(afr["matrix_source_offset"], 0x1CA30)
        self.assertEqual(afr["matrix_row_bytes"], 8)
        self.assertEqual(afr["matrix_column_count_offset"], 0x4EC)
        self.assertEqual(afr["clamp"], [38600.0, 24800.0])
        self.assertEqual(recovered["maximum_state_value"], 100)
        self.assertEqual(
            recovered["chip_leakage"]["fuse_physical_address"], 0x23_8837_4000
        )
        self.assertEqual(recovered["chip_leakage"]["fuse_bytes"], 0x1000)
        self.assertEqual(
            recovered["chip_leakage"]["fuse_word_offsets"], [0x198, 0x19C, 0x1A0]
        )
        self.assertEqual(
            recovered["chip_leakage"]["core_selectors"], [0, 1, 2, 3, 0, 1, 2, 3]
        )
        self.assertEqual(
            [
                descriptor["primary_shift"]
                for descriptor in recovered["chip_leakage"]["core_descriptors"]
            ],
            [8, 22, 22, 8],
        )
        self.assertEqual(
            recovered["chip_leakage"]["group_field"],
            {
                "low_word_offset": 0x19C,
                "high_word_offset": 0x1A0,
                "right_shift": 25,
                "width": 12,
                "multiplier": 2,
            },
        )
        self.assertEqual(recovered["leakage_model"]["temperature"], 110.0)
        self.assertTrue(recovered["leakage_model"]["input_linear"])
        self.assertEqual(recovered["leakage_model"]["pow_terms"], 4)
        self.assertIn("max(V-1.06,0)", recovered["leakage_model"]["factor_formula"])
        self.assertEqual(recovered["leakage_model"]["vdd_gpu"]["buckets"], 2)
        self.assertEqual(
            recovered["leakage_model"]["vdd_gpu"]["default_records"][0],
            [1000.0] + [1.0] * 10,
        )
        self.assertEqual(
            recovered["leakage_model"]["afr"]["default_thresholds"], [1000.0, -1.0]
        )

    def test_rejects_g17_linear_power_transfer_stub_selection(self) -> None:
        arm_power, fixtures = self._linear_power_transfer_fixtures()
        slots = dict(fixtures["slots"])
        slots[recover_g17_abi.G17_POPULATE_MAX_PERF_POWER_VTABLE_SLOT] = 0x7F0000
        with self.assertRaises(ValueError):
            self._run_linear_power_transfer(arm_power, fixtures, slots)

    def test_rejects_changed_g17_linear_power_transfer_normalization(self) -> None:
        arm_power, fixtures = self._linear_power_transfer_fixtures()
        codes = dict(fixtures["codes"])
        address, linear = codes[recover_g17_abi.G17_POPULATE_LINEAR_POWER_TRANSFER]
        patched = bytearray(linear)
        struct.pack_into("<I", patched, 0x2F0, 0x52800C8F)
        codes[recover_g17_abi.G17_POPULATE_LINEAR_POWER_TRANSFER] = (
            address,
            bytes(patched),
        )
        fixtures = dict(fixtures) | {"codes": codes}
        with self.assertRaises(ValueError):
            self._run_linear_power_transfer(arm_power, fixtures)

    def test_recovers_g17_afr_relative_boost_frequency_table(self) -> None:
        afr_address = 0x200000
        afr_config = bytearray(0xE8)
        for offset, word in {
            0x1C: 0x91407008,
            0x20: 0x9113A114,
            0xDC: 0xB9400289,
            0xE4: 0x1B082929,
        }.items():
            struct.pack_into("<I", afr_config, offset, word)

        arm_power = bytearray(0xE90)
        for offset, word in {
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
        }.items():
            struct.pack_into("<I", arm_power, offset, word)

        with (
            mock.patch.object(
                recover_g17_abi,
                "macho_symbols",
                return_value={recover_g17_abi.POPULATE_AFR_FAST_DIE_CONFIG: afr_address},
            ),
            mock.patch.object(
                recover_g17_abi,
                "symbol_code",
                return_value=(afr_address, bytes(afr_config)),
            ),
        ):
            recovered = recover_g17_abi.recover_g17_afr_relative_boost_frequency_table(
                b"afr-perf-states\0", bytes(arm_power)
            )

        self.assertEqual(recovered["offset"], 0x1988)
        self.assertEqual(recovered["domain"], "AFR")
        self.assertEqual(recovered["frequency_source_offset"], 0x1C4F0)
        self.assertEqual(recovered["maximum_state_value"], 100)

    def test_recovers_g17_performance_state_map_block(self) -> None:
        probe_address = 0x100000
        pi_address = 0x200000
        g17_address = 0x201000
        parser_address = 0x202000

        probe = bytearray(0xC78)
        for offset, word in {
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
        }.items():
            struct.pack_into("<I", probe, offset, word)

        pi_code = bytes(0x61C)
        g17_code = bytearray(0x34)
        struct.pack_into("<I", g17_code, 0x14, bl(g17_address + 0x14, pi_address))
        struct.pack_into("<I", g17_code, 0x20, 0xBC089260)
        struct.pack_into("<I", g17_code, 0x24, 0x3902127F)
        parser_code = struct.pack("<2I", 0xD503245F, 0xD65F03C0)

        arm_power = bytearray(0x92C)
        for offset, word in {
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
        }.items():
            struct.pack_into("<I", arm_power, offset, word)

        symbols = {
            recover_g17_abi.FAMILY_GET_PROBE_SCORE: probe_address,
            recover_g17_abi.PI300_READ_CHIP_INFO: pi_address,
            recover_g17_abi.G17_READ_CHIP_INFO: g17_address,
            recover_g17_abi.G17_PARSE_PERF_STATE_MAP_REGS: parser_address,
        }
        code = {
            recover_g17_abi.FAMILY_GET_PROBE_SCORE: (
                probe_address,
                bytes(probe),
            ),
            recover_g17_abi.PI300_READ_CHIP_INFO: (pi_address, pi_code),
            recover_g17_abi.G17_READ_CHIP_INFO: (g17_address, bytes(g17_code)),
            recover_g17_abi.G17_PARSE_PERF_STATE_MAP_REGS: (
                parser_address,
                parser_code,
            ),
        }
        vectors = [
            struct.pack("<4I", start, start + 1, start + 2, start + 3)
            for start in range(0, 16, 4)
        ]
        with (
            mock.patch.object(recover_g17_abi, "macho_symbols", return_value=symbols),
            mock.patch.object(
                recover_g17_abi,
                "recover_vtable_target",
                return_value=parser_address,
            ),
            mock.patch.object(
                recover_g17_abi,
                "symbol_code",
                side_effect=lambda _image, name: code[name],
            ),
            mock.patch.object(
                recover_g17_abi,
                "read_adrp_load",
                side_effect=vectors,
            ),
        ):
            recovered = recover_g17_abi.recover_g17_perf_state_map_block(
                b"", bytes(arm_power)
            )

        self.assertEqual(recovered["offset"], 0x19C8)
        self.assertEqual(recovered["enable_byte_value"], 0)
        self.assertEqual(recovered["banks"][0]["values"], list(range(16)))
        self.assertEqual(recovered["banks"][1]["values"], [0] * 16)

    def test_recovers_g17_auxiliary_performance_layout(self) -> None:
        property_selector = (
            0x7100045F,
            0x5280A128,
            0x9A880508,
            0x8B080008,
            0x39400108,
            0xF900A07F,
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
        )
        dimensions = (
            0xA9402ACB,
            0x52800108,
            0x2A0A1108,
            0x52800209,
            0x1B0B2508,
            0x51004549,
            0x6B08001F,
            0x3A4F2920,
            0x54001043,
            0xB944EEA8,
            0x7100097F,
            0x7A4B9100,
            0x54000FC1,
            0x29002E8A,
            0x340007AB,
        )
        conversion = (
            0xA9400E30,
            0xD343FE10,
            0x9BCC7E10,
            0xD344FE10,
            0xB8008410,
            0x91004230,
            0xB8004423,
        )
        clamp = (0xB840458F, 0xB85801B0, 0x6B0F021F, 0x1A8F820F, 0xB80045AF)
        parser = encode(*property_selector, *dimensions, *conversion, *clamp)
        cap = encode(
            0xD503245F,
            0x721E783F,
            0x54000081,
            0x3900005F,
            0x528001C0,
            0xD65F03C0,
        )
        cs_binding = (
            0xB943A109,
            0x5100052B,
            0xB91A49AB,
            0xB94F3E6B,
            0xB91A4DAB,
            0x34000489,
            0xD2800009,
            0x9140714A,
            0x910EA14A,
            0x52834A0B,
            0x8B0B01AB,
            0x9111A10C,
            0x5283620E,
            0x8B0E01AD,
        )
        afr_binding = (
            0xB944E909,
            0x5100052B,
            0xB91B91AB,
            0xB94F426B,
            0xB91B95AB,
            0x34000489,
            0xD2800009,
            0x9140714A,
            0x9113C14A,
            0x5283730B,
            0x8B0B01AB,
            0x9116C10C,
            0x52838B0E,
            0x8B0E01AD,
        )
        row_copy = (0xB8580200, 0xB8180220, 0xB8404600, 0xB8004620)
        arm_power = encode(*cs_binding, *row_copy, *afr_binding)
        symbols = {
            recover_g17_abi.POPULATE_AUX_PERF_STATE_INFO: 0x1000,
            recover_g17_abi.G17_GET_PERF_STATE_CAP: 0x2000,
        }

        def code(_image: bytes, name: str) -> tuple[int, bytes]:
            if name == recover_g17_abi.POPULATE_AUX_PERF_STATE_INFO:
                return 0x1000, parser
            if name == recover_g17_abi.G17_GET_PERF_STATE_CAP:
                return 0x2000, cap
            raise AssertionError(name)

        image = b"cs-perf-states\0afr-perf-states\0"
        with (
            mock.patch.object(recover_g17_abi, "macho_symbols", return_value=symbols),
            mock.patch.object(
                recover_g17_abi,
                "recover_vtable_target",
                return_value=symbols[recover_g17_abi.G17_GET_PERF_STATE_CAP],
            ),
            mock.patch.object(recover_g17_abi, "symbol_code", side_effect=code),
        ):
            recovered = recover_g17_abi.recover_g17_aux_performance_layout(
                image, arm_power
            )

        self.assertEqual(recovered["domain_cap"], 14)
        self.assertEqual(recovered["source_layout"]["sram_voltage_offset"], 0xC8)
        self.assertEqual(
            [block["offset"] for block in recovered["firmware_blocks"]],
            [0x1A48, 0x1B90],
        )

    def test_recovers_g17_pio_mappings(self) -> None:
        image, symbols, functions = g17_pio_mapping_fixture()

        def vtable_target(_image: bytes, _name: str, slot: int) -> int:
            if slot == recover_g17_abi.G17_PIO_TABLE_VTABLE_SLOT:
                return symbols[recover_g17_abi.G17_PIO_TABLE]
            if slot == recover_g17_abi.G17_PIO_TABLE_LENGTH_VTABLE_SLOT:
                return symbols[recover_g17_abi.G17_PIO_TABLE_LENGTH]
            raise AssertionError(f"unexpected vtable slot {slot:#x}")

        with (
            mock.patch.object(recover_g17_abi, "macho_symbols", return_value=symbols),
            mock.patch.object(
                recover_g17_abi, "recover_vtable_target", side_effect=vtable_target
            ),
            mock.patch.object(
                recover_g17_abi,
                "symbol_code",
                side_effect=lambda _image, name: functions[name],
            ),
            mock.patch.object(recover_g17_abi, "virtual_to_file", return_value=0),
        ):
            recovered = recover_g17_abi.recover_g17_pio_mappings(image)

        self.assertEqual(recovered["table_entries"], 19)
        self.assertEqual(len(recovered["records"]), 12)
        self.assertEqual(recovered["records"][0]["index"], 17)
        self.assertEqual(recovered["records"][0]["total_size"], 0x21500)
        self.assertEqual(recovered["records"][-1]["index"], 43)
        self.assertEqual(recovered["records"][-1]["relative_offset"], 0xE60000)
        self.assertTrue(all(record["writable"] for record in recovered["records"]))
        self.assertEqual(recovered["alternate_entries"][-1]["alternate_offset"], 0xD24000)

    def test_rejects_modified_g17_pio_source_producer(self) -> None:
        image, symbols, functions = g17_pio_mapping_fixture()
        base_address, base_code = functions[recover_g17_abi.BASE_CONFIGURE_DEVICE]
        modified = bytearray(base_code)
        struct.pack_into("<I", modified, 0x1020, movz_w(20, 1))
        functions[recover_g17_abi.BASE_CONFIGURE_DEVICE] = (
            base_address,
            bytes(modified),
        )

        def vtable_target(_image: bytes, _name: str, slot: int) -> int:
            if slot == recover_g17_abi.G17_PIO_TABLE_VTABLE_SLOT:
                return symbols[recover_g17_abi.G17_PIO_TABLE]
            return symbols[recover_g17_abi.G17_PIO_TABLE_LENGTH]

        with (
            mock.patch.object(recover_g17_abi, "macho_symbols", return_value=symbols),
            mock.patch.object(
                recover_g17_abi, "recover_vtable_target", side_effect=vtable_target
            ),
            mock.patch.object(
                recover_g17_abi,
                "symbol_code",
                side_effect=lambda _image, name: functions[name],
            ),
            mock.patch.object(recover_g17_abi, "virtual_to_file", return_value=0),
            self.assertRaisesRegex(ValueError, "source producer"),
        ):
            recover_g17_abi.recover_g17_pio_mappings(image)

    def test_recovers_g17_pio_uat_mapping(self) -> None:
        image, symbols, functions = g17_pio_uat_fixture()
        with (
            mock.patch.object(recover_g17_abi, "macho_symbols", return_value=symbols),
            mock.patch.object(
                recover_g17_abi,
                "symbol_code",
                side_effect=lambda _image, name: functions[name],
            ),
            mock.patch.object(recover_g17_abi, "virtual_to_file", return_value=0),
        ):
            recovered = recover_g17_abi.recover_g17_pio_uat_mapping(image)

        self.assertEqual(recovered["gart_range"], 10)
        self.assertEqual(recovered["va_start"], 0xFFFFFC2180000000)
        self.assertEqual(recovered["va_size"], 0x01400000)
        self.assertEqual(recovered["uat_page_bytes"], 0x4000)
        self.assertEqual(recovered["writable_gpu_mapping_options"], 7)
        self.assertEqual(
            recovered["firmware_virtual_address"],
            "mapping_gpu_va_plus_physical_page_offset",
        )

    def test_rejects_modified_g17_pio_uat_range(self) -> None:
        image, symbols, functions = g17_pio_uat_fixture()
        modified = bytearray(image)
        struct.pack_into("<Q", modified, 8, 0x01000000)
        with (
            mock.patch.object(recover_g17_abi, "macho_symbols", return_value=symbols),
            mock.patch.object(
                recover_g17_abi,
                "symbol_code",
                side_effect=lambda _image, name: functions[name],
            ),
            mock.patch.object(recover_g17_abi, "virtual_to_file", return_value=0),
            self.assertRaisesRegex(ValueError, "firmware-PIO GART range"),
        ):
            recover_g17_abi.recover_g17_pio_uat_mapping(bytes(modified))

    def test_recovers_accelerator_ring_bindings(self) -> None:
        allocations = [
            {"host_cpu_member": 0xAE0, "host_gpu_member": 0xAE8, "bytes": 0x30},
            {"host_cpu_member": 0xAF0, "host_gpu_member": 0xAF8, "bytes": 0x4000},
            {"host_cpu_member": 0xC10, "host_gpu_member": 0xC18, "bytes": 0x30},
            {"host_cpu_member": 0xC20, "host_gpu_member": 0xC28, "bytes": 0x4000},
        ]
        code = encode(
            *sum(
                (
                    (
                        0xF9400000 | (member // 8) << 10 | 19 << 5 | 8,
                        str_x(0, 8, offset),
                    )
                    for member in (0xAA0, 0xBD0)
                    for offset in (0x180, 0x188, 0x190, 0x198)
                ),
                (),
            )
        )
        bindings = recover_g17_abi.recover_accelerator_ring_bindings(allocations, code)
        self.assertEqual(bindings[0]["host_object_member"], 0xAD8)
        self.assertEqual(bindings[1]["host_entries_gpu_member"], 0xC28)
        self.assertEqual(
            bindings[0]["firmware_shared_offsets"]["entries_address"], 0x1B8
        )

    def test_rejects_incomplete_accelerator_ring_publication(self) -> None:
        allocations = [
            {"host_cpu_member": 0xAE0, "host_gpu_member": 0xAE8, "bytes": 0x30},
            {"host_cpu_member": 0xAF0, "host_gpu_member": 0xAF8, "bytes": 0x4000},
            {"host_cpu_member": 0xC10, "host_gpu_member": 0xC18, "bytes": 0x30},
            {"host_cpu_member": 0xC20, "host_gpu_member": 0xC28, "bytes": 0x4000},
        ]
        code = encode(
            0xF9400000 | (0xAA0 // 8) << 10 | 19 << 5 | 8,
            str_x(0, 8, 0x180),
        )
        with self.assertRaisesRegex(ValueError, "accelerator addresses"):
            recover_g17_abi.recover_accelerator_ring_bindings(allocations, code)


if __name__ == "__main__":
    unittest.main()
