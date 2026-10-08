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

# Public contract values are maintained in V; the binding preserves Python
# scalar, tuple and dictionary types for existing imports.
globals().update(_native_g17.public_constants())


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
        report = _native_g17._query(
            driver, "recover_g17_report", kernel=kernel.hex(),
            firmware=firmware.hex(), iogpu=iogpu.hex(),
            iosurface=iosurface.hex(), rtbuddy=rtbuddy.hex())
        for field in ("chip_info_registers", "late_controls"):
            report["hardware_config"][field] = _native_g17._integer_keys(
                report["hardware_config"][field])
    except (OSError, ValueError) as error:
        parser.error(str(error))
    print(json.dumps(report, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
