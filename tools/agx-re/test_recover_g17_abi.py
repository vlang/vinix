import struct
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
