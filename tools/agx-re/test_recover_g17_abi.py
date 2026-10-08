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


def str_post_x(source: int, base: int, immediate: int) -> int:
    return 0xF8000400 | (immediate & 0x1FF) << 12 | base << 5 | source


def str_register_x(source: int, base: int, index: int) -> int:
    return 0xF8206800 | index << 16 | base << 5 | source


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






















    def test_recovers_device_control_copy_size(self) -> None:
        code = encode(
            pair_q("load", 0, 1, 21, 0),
            pair_q("load", 2, 3, 21, 0x20),
            pair_q("store", 0, 1, 9, 0),
            pair_q("store", 2, 3, 9, 0x20),
        )
        self.assertEqual(recover_g17_abi.recover_vector_copy_size(code), 0x40)




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














    def test_census_finds_direct_derived_and_escaping_member_writes(self) -> None:
        base = 0x100000
        second = base + 0x100
        deadline = 0x900000
        bzero = 0x900100
        code = bytearray(0x200)
        instructions = [
            str_x(8, 0, 0x6D0),  # this->flags
            add_immediate(9, 19, 0x600),
            str_unsigned(1, 9, 0xD0, 4),  # interior pointer + 0xd0
            adrp(base + 0xC, 0x200000, 8),
            str_x(0, 8, 0x6D0),  # a global
            str_x(8, 31, 0x6D0),  # the stack is not an object
            stp_x(8, 10, 9, 0xC8),  # a pair through the interior pointer
            movz(9, 0x6D0),
            str_register_x(8, 0, 9),  # this + constant index
            str_post_x(8, 0, 0x10),
            str_x(9, 0, 0x6C0),  # after writeback: this + 0x6d0
            add_immediate(2, 20, 0x6C8),
            bl(base + 0x30, deadline),  # escapes this + 0x6c8
            add_immediate(0, 19, 0x600),
            movz_w(1, 0x100),
            bl(base + 0x3C, bzero),  # clears 0x600..0x700
            ldr_x(0, 0, 0),
            str_x(8, 0, 0x6D0),  # through a loaded pointer
        ]
        struct.pack_into(f"<{len(instructions)}I", code, 0, *instructions)
        # A new symbol forgets every derivation.
        struct.pack_into("<I", code, 0x100, str_unsigned(8, 9, 0xD0, 4))
        result = recover_g17_abi.census_g17_code_member_writes(
            bytes(code),
            base,
            [(base, "first"), (second, "second")],
            0x6D0,
            0x6D8,
            {bzero: ("___bzero", (0, 1))},
        )

        stores = [(item["offset"], item["member"], item["origin"]) for item in result["stores"]]
        self.assertEqual(
            stores,
            [
                (0x00, 0x6D0, "arg0"),
                (0x08, 0x6D0, "unknown"),
                (0x18, 0x6C8, "unknown"),
                (0x20, 0x6D0, "arg0"),
                (0x28, 0x6D0, "arg0"),
                (0x44, 0x6D0, "unknown"),
            ],
        )
        self.assertEqual([item["offset"] for item in result["global_stores"]], [0x10])
        self.assertEqual(
            [(item["offset"], item["member"], item["argument"]) for item in result["escapes"]],
            [(0x30, 0x6C8, 2)],
        )
        routine = result["memory_routines"][0]
        self.assertEqual((routine["member"], routine["bytes"], routine["clears_only"]), (0x600, 0x100, True))

    def test_recovers_g17_accelerator_channel_inputs(self) -> None:
        addresses = {
            recover_g17_abi.BASE_CONFIGURE_DEVICE: 0x100000,
            recover_g17_abi.PI300_CONFIGURE_DEVICE: 0x110000,
            recover_g17_abi.G17_CONFIGURE_DEVICE: 0x120000,
            recover_g17_abi.G17_SET_SMART_IDLE_OFF_ENABLE: 0x130000,
            recover_g17_abi.G17_RETRIEVE_CHIP_INFO: 0x140000,
            recover_g17_abi.G17_ACCELERATOR_X_START: 0x150000,
            recover_g17_abi.G17_PERF_SAMPLER_INIT: 0x160000,
            recover_g17_abi.G17_PERF_SAMPLER_START: 0x170000,
            recover_g17_abi.G17_PERF_SAMPLER_VTABLE: 0x180598,
        }
        code = {name: bytearray(0x2600) for name in addresses}
        start = code[recover_g17_abi.G17_ACCELERATOR_X_START]
        for offset, word in {
            0x1E4: 0x91404668, 0x1E8: 0x91074116, 0x1F4: 0x52802301,
            0x220: 0x91166210, 0x224: 0x91004210, 0x248: 0xF9000010,
            0x264: 0xF90002D4,
        }.items():
            struct.pack_into("<I", start, offset, word)
        struct.pack_into("<I", start, 0x21C, adrp(0x150000 + 0x21C, 0x180000, 16))
        struct.pack_into("<I", code[recover_g17_abi.G17_PERF_SAMPLER_INIT], 0x88, 0x3901529F)
        for offset in (0x150, 0x184, 0x1AC):
            struct.pack_into("<I", code[recover_g17_abi.G17_PERF_SAMPLER_START], offset, 0x39015268)
        for symbol, _offset, pins, _recipe in recover_g17_abi.G17_FEATURE_FLAG_WRITERS:
            for offset, word in pins.items():
                struct.pack_into("<I", code[symbol], offset, word)
        base = code[recover_g17_abi.BASE_CONFIGURE_DEVICE]
        for offset, word in {
            0x610: 0x529EF908, 0x638: 0xF946B20A, 0x63C: 0x8B080261,
            0x640: 0xAA1303E0, 0x64C: 0xD73F0951,
        }.items():
            struct.pack_into("<I", base, offset, word)
        g17_address = addresses[recover_g17_abi.G17_CONFIGURE_DEVICE]
        g17 = code[recover_g17_abi.G17_CONFIGURE_DEVICE]
        struct.pack_into(
            "<I", g17, 0x70,
            bl(g17_address + 0x70, addresses[recover_g17_abi.PI300_CONFIGURE_DEVICE]),
        )
        struct.pack_into("<I", g17, 0x740, adrp(g17_address + 0x740, 0x200000, 8))
        struct.pack_into("<I", g17, 0x744, 0x3DC35500)
        struct.pack_into("<I", g17, 0x748, 0x3DBDFE60)
        panic = 0x900000
        literal = bytes(8) + struct.pack("<Q", 1 << 32)

        def census(_image, low, _high, _kernel):
            if low == recover_g17_abi.G17_ACCELERATOR_FEATURE_FLAGS:
                stores = [
                    {"kind": "store", "symbol": symbol, "offset": offset}
                    for symbol, offset, _pins, _recipe in recover_g17_abi.G17_FEATURE_FLAG_WRITERS
                ]
                return {
                    "stores": stores,
                    "global_stores": [],
                    "memory_routines": [
                        {"kind": "memory_routine", "symbol": "other", "offset": 4, "clears_only": True}
                    ],
                    "escapes": [
                        {"kind": "escape", "symbol": "other", "offset": 8, "member": 0x6C8,
                         "origin": "arg0", "target": panic}
                    ],
                    "unbounded": [{}],
                }
            return {
                "stores": [
                    {"kind": "store", "symbol": recover_g17_abi.G17_CONFIGURE_DEVICE, "offset": 0x748}
                ],
                "global_stores": [],
                "memory_routines": [],
                "escapes": [
                    {"kind": "escape", "symbol": recover_g17_abi.BASE_CONFIGURE_DEVICE, "offset": 0x64C}
                ],
                "unbounded": [{}],
            }

        def symbols(image):
            return {"_panic": panic} if image == b"kernel" else dict(addresses)

        chip_info = {"fields": {"power_column_count": {"accelerator_member": 0x4E4}}}
        with (
            mock.patch.object(recover_g17_abi, "macho_symbols", side_effect=symbols),
            mock.patch.object(
                recover_g17_abi, "symbol_code",
                side_effect=lambda _image, name: (addresses[name], bytes(code[name])),
            ),
            mock.patch.object(
                recover_g17_abi, "recover_vtable_target",
                return_value=addresses[recover_g17_abi.G17_RETRIEVE_CHIP_INFO],
            ),
            mock.patch.object(
                recover_g17_abi, "require_zeroed_accelerator_allocation",
                return_value={"allocator_flag_name": "Z_ZERO"},
            ),
            mock.patch.object(recover_g17_abi, "census_g17_member_writes", side_effect=census),
            mock.patch.object(recover_g17_abi, "virtual_to_file", return_value=0),
        ):
            recovered = recover_g17_abi.recover_g17_accelerator_channel_inputs(
                literal, b"kernel", b"iogpu", chip_info
            )
            flags = recovered["feature_flags"]
            for bit in (20, 29, 53):
                self.assertEqual(flags["never_set_mask"] >> bit & 1, 1)
            for bit in (0, 1, 2, 8, 21, 25, 34, 57):
                self.assertEqual(flags["may_set_mask"] >> bit & 1, 1)
            self.assertEqual(recovered["chip_information"]["override_value"], literal.hex())
            sampler = recovered["perf_counter_sampler"]
            self.assertEqual((sampler["pointer_member"], sampler["running_member"]), (0x111D0, 0x54))
            self.assertEqual(sampler["vinix_policy"]["running"], 0)

            # A branch that jumps past the override to anything but a panic.
            struct.pack_into("<I", g17, 0x100, b(g17_address + 0x100, g17_address + 0x800))
            with self.assertRaisesRegex(ValueError, "can skip the override"):
                recover_g17_abi.recover_g17_accelerator_channel_inputs(
                    literal, b"kernel", b"iogpu", chip_info
                )
            struct.pack_into("<I", g17, 0x800, bl(g17_address + 0x800, panic))
            recover_g17_abi.recover_g17_accelerator_channel_inputs(
                literal, b"kernel", b"iogpu", chip_info
            )

            # A writer that is not in the table fails closed.
            original = census
            census_with_extra = lambda *args: {  # noqa: E731
                **original(*args),
                "stores": original(*args)["stores"]
                + [{"kind": "store", "symbol": "unknown", "offset": 0}],
            }
            with mock.patch.object(
                recover_g17_abi, "census_g17_member_writes", side_effect=census_with_extra
            ):
                with self.assertRaisesRegex(ValueError, "unclassified"):
                    recover_g17_abi.recover_g17_accelerator_channel_inputs(
                        literal, b"kernel", b"iogpu", chip_info
                    )









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






    def test_decodes_g17_selector_logical_immediate(self) -> None:
        # orr w2, w27, #0x10
        self.assertEqual(
            recover_g17_abi.decode_logical_immediate_w(0x321C0362),
            ("orr", 2, 27, 0x10),
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








    def test_recovers_device_control_ring_bindings(self) -> None:
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
        bindings = recover_g17_abi.recover_device_control_ring_bindings(
            allocations, code
        )
        self.assertEqual(bindings[0]["host_object_member"], 0xAD8)
        self.assertEqual(bindings[1]["host_entries_gpu_member"], 0xC28)
        self.assertEqual(
            bindings[0]["firmware_shared_offsets"]["entries_address"], 0x1B8
        )

    def test_rejects_incomplete_device_control_ring_publication(self) -> None:
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
        with self.assertRaisesRegex(ValueError, "device-control addresses"):
            recover_g17_abi.recover_device_control_ring_bindings(allocations, code)


if __name__ == "__main__":
    unittest.main()
