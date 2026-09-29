import json
import tempfile
import unittest
from pathlib import Path

import compile_fake_g17_plan as fake
import encode_fake_g17_3d as encoder


GPU_BASE = 0x700000000
TEMPLATE = 0xA5A40006


def recovered_abi():
    entries = [
        {
            "producer_offset": 0x100,
            "selector": 0x8,
            "mode": 0,
            "value_source": {"kind": "constant", "value": 5},
        },
        {
            "producer_offset": 0x200,
            "selector": 0x10,
            "mode": 1,
            "value_source": {
                "kind": "descriptor_load",
                "member": 0,
                "bytes": 4,
                "signed": False,
            },
        },
        {
            "producer_offset": 0x300,
            "selector": 0x18,
            "mode": 0,
            "value_source": {
                "kind": "computed",
                "expression": {
                    "kind": "expression",
                    "operation": "add",
                    "bytes": 8,
                    "source": {
                        "kind": "descriptor_load",
                        "member": 0,
                        "bytes": 4,
                        "signed": False,
                    },
                    "immediate": 3,
                },
            },
        },
        {
            "producer_offset": 0x400,
            "selector": 0x20,
            "mode": 1,
            "value_source": {
                "kind": "object_load",
                "base": {"kind": "argument", "name": "channel"},
                "member": 8,
                "bytes": 8,
                "signed": False,
            },
        },
    ]
    nodes = [
        {"producer_offset": 0x50, "next": [0x100, 0x200], "can_return": False},
        {"producer_offset": 0x100, "next": [0x200], "can_return": False},
        {"producer_offset": 0x200, "next": [0x300], "can_return": False},
        {"producer_offset": 0x300, "next": [0x400], "can_return": False},
        {"producer_offset": 0x400, "next": [], "can_return": True},
    ]
    return {
        "schema": 1,
        "driver_uuid": "driver-test-uuid",
        "firmware_uuid": "firmware-test-uuid",
        "channels": {
            "command_3d_register_lists": {
                "command_bytes": 0x2240,
                "passes": 4,
                "stride": 0x720,
                "stream_offset": 0xA0,
                "stream_bytes": 0x700,
                "gpu_address_offset": 0x7A0,
                "entry_count_offset": 0x7A8,
                "byte_length_offset": 0x7AA,
                "entry_bytes": 12,
                "selector_template_mask": 0xFFFC0006,
                "descriptor_summary": {
                    "offset": 0x828,
                    "stride": 0x10,
                    "records": 4,
                },
                "record_framing_resolved": True,
            },
            "register_entry_codec": {
                "entry_bytes": 12,
                "selector_mask": 0x3FFF8,
                "mode_mask": 1,
                "preserved_template_mask": 0xFFFC0006,
                "value_offset": 4,
            },
            "register_selectors": {
                "selector_formulas_complete": True,
                "producers": {"3D": {"encoder_entries": entries}},
            },
            "inline_register_records": {
                "all_inline_forms_located": True,
                "all_inline_values_recovered": True,
                "static_records": {
                    "3D": [
                        {
                            "producer_offset": 0x50,
                            "selector": 0x28,
                            "mode": 1,
                            "value": 1,
                        }
                    ]
                },
                "dynamic_records": {},
            },
            "register_emission_cfg": {
                "machine_order_complete": True,
                "predicate_expressions_complete": True,
                "producers": {
                    "3D": {
                        "entry": [0x50],
                        "empty_return_path": False,
                        "predicates_complete": True,
                        "decisions": [
                            {
                                "producer_offset": 0x80,
                                "condition": "bit_set",
                                "predicate": {
                                    "kind": "condition",
                                    "operation": "test_bit",
                                    "bytes": 4,
                                    "bit": 0,
                                    "source": {
                                        "kind": "object_load",
                                        "base": {
                                            "kind": "argument",
                                            "name": "channel",
                                        },
                                        "member": 4,
                                        "bytes": 4,
                                        "signed": False,
                                    },
                                },
                                "taken": {
                                    "next": [0x100],
                                    "can_return": False,
                                },
                                "fallthrough": {
                                    "next": [0x200],
                                    "can_return": False,
                                },
                            }
                        ],
                        "nodes": nodes,
                    }
                },
            },
        },
    }


def encoded_buffers():
    command = bytearray(0x2240)
    descriptor = bytearray(0x15B0)
    descriptor[0:4] = (0x11223344).to_bytes(4, "little")
    events = [
        (0x28, 1, 1),
        (0x8, 0, 5),
        (0x10, 1, 0x11223344),
        (0x18, 0, 0x11223347),
        (0x20, 1, 0xDEADBEEF000),
    ]
    for pass_index in range(4):
        base = pass_index * 0x720
        address = GPU_BASE + base + 0xA0
        command[base + 0x7A0 : base + 0x7A8] = address.to_bytes(8, "little")
        command[base + 0x7A8 : base + 0x7AA] = len(events).to_bytes(2, "little")
        command[base + 0x7AA : base + 0x7AC] = (len(events) * 12).to_bytes(2, "little")
        summary = 0x828 + pass_index * 0x10
        descriptor[summary : summary + 8] = address.to_bytes(8, "little")
        descriptor[summary + 8 : summary + 10] = len(events).to_bytes(2, "little")
        for entry_index, (selector, mode, value) in enumerate(events):
            offset = base + 0xA0 + entry_index * 12
            command[offset : offset + 4] = (TEMPLATE | selector | mode).to_bytes(
                4, "little"
            )
            command[offset + 4 : offset + 12] = value.to_bytes(8, "little")
    return command, descriptor


class FakeG17PlanTests(unittest.TestCase):
    def test_evaluates_recovered_bitfield_and_condition_forms(self):
        descriptor = bytes(0x15B0)
        command = bytes(0x2240)

        # UBFM aliases used by the recovered graph: a one-bit left shift and
        # a logical right shift with an all-ones mask end.
        self.assertEqual(
            fake._evaluate(
                {
                    "kind": "expression",
                    "operation": "ubfm",
                    "bytes": 8,
                    "rotate": 40,
                    "mask_end": 0,
                    "source": {"kind": "constant", "value": 1},
                },
                descriptor,
                command,
            ),
            1 << 24,
        )
        self.assertEqual(
            fake._evaluate(
                {
                    "kind": "expression",
                    "operation": "ubfm",
                    "bytes": 8,
                    "rotate": 60,
                    "mask_end": 63,
                    "source": {"kind": "constant", "value": 0xF000000000000000},
                },
                descriptor,
                command,
            ),
            0xF,
        )
        self.assertEqual(
            fake._evaluate(
                {
                    "kind": "expression",
                    "operation": "bfm",
                    "bytes": 8,
                    "rotate": 45,
                    "mask_end": 0,
                    "source": {"kind": "constant", "value": 1},
                    "destination": {"kind": "constant", "value": 0},
                },
                descriptor,
                command,
            ),
            1 << 19,
        )

        conditional = {
            "kind": "expression",
            "operation": "csel",
            "bytes": 8,
            "condition": "hi",
            "predicate": {
                "kind": "condition",
                "operation": "cmp",
                "bytes": 8,
                "source": {"kind": "constant", "value": 9},
                "immediate": 4,
            },
            "first": {"kind": "constant", "value": 0xAA},
            "second": {"kind": "constant", "value": 0x55},
        }
        self.assertEqual(fake._evaluate(conditional, descriptor, command), 0xAA)

        zero_predicate = {
            "kind": "condition",
            "operation": "compare_zero",
            "bytes": 4,
            "source": {"kind": "constant", "value": 0},
        }
        self.assertTrue(
            fake._condition(zero_predicate, "zero", descriptor, command)
        )
        self.assertFalse(
            fake._condition(zero_predicate, "nonzero", descriptor, command)
        )

        movk = {
            "kind": "expression",
            "operation": "movk",
            "bytes": 8,
            "source": {"kind": "constant", "value": 0x1122334455667788},
            "immediate": 0xABCD,
            "shift": 16,
        }
        self.assertEqual(
            fake._evaluate(movk, descriptor, command), 0x11223344ABCD7788
        )

    def test_compiles_path_exact_plan(self):
        command, descriptor = encoded_buffers()
        plan = fake.compile_plan(recovered_abi(), command, descriptor, GPU_BASE)

        self.assertEqual(plan["schema"], fake.PLAN_SCHEMA)
        self.assertEqual(plan["coverage"]["total_writes"], 20)
        self.assertEqual(plan["coverage"]["recovered_values"], 16)
        self.assertEqual(plan["coverage"]["external_values"], 4)
        self.assertEqual(
            plan["passes"][0]["producer_offsets"],
            [0x50, 0x100, 0x200, 0x300, 0x400],
        )
        self.assertEqual(plan["writes"][2]["value"], 0x11223344)
        self.assertEqual(plan["writes"][2]["value_mask"], fake.UINT64_MASK)
        self.assertEqual(plan["writes"][4]["value_mask"], 0)
        self.assertEqual(plan["writes"][4]["value_status"], "external")

    def test_reference_encoder_round_trips_through_plan_compiler(self):
        _, descriptor = encoded_buffers()
        template = bytearray(0x2240)
        for pass_index in range(4):
            base = pass_index * 0x720 + 0xA0
            for entry_index in range(5):
                offset = base + entry_index * 12
                template[offset : offset + 4] = TEMPLATE.to_bytes(4, "little")
        external_values = [0xDEADBEEF000 + pass_index for pass_index in range(4)]

        command, output_descriptor, plan = encoder.encode_3d(
            recovered_abi(),
            descriptor,
            GPU_BASE,
            template,
            {
                "decisions": {"0x80": "taken"},
                "values": {"0x400": external_values},
            },
        )

        self.assertEqual(plan["coverage"]["total_writes"], 20)
        self.assertEqual(plan["encoder"]["external_event_offsets"], [0x400])
        self.assertFalse(plan["encoder"]["zero_template"])
        self.assertEqual(plan["passes"][0]["producer_offsets"], [
            0x50, 0x100, 0x200, 0x300, 0x400,
        ])
        first_word = int.from_bytes(command[0xA0 : 0xA4], "little")
        self.assertEqual(first_word & 0xFFFC0006, TEMPLATE & 0xFFFC0006)
        self.assertEqual(
            int.from_bytes(command[0xA0 + 4 * 12 + 4 : 0xA0 + 5 * 12], "little"),
            external_values[0],
        )
        self.assertEqual(
            int.from_bytes(output_descriptor[0x828 : 0x830], "little"),
            GPU_BASE + 0xA0,
        )

    def test_reference_encoder_fails_closed_without_external_inputs(self):
        _, descriptor = encoded_buffers()
        with self.assertRaisesRegex(fake.PlanError, "decision 0x80"):
            encoder.encode_3d(
                recovered_abi(), descriptor, GPU_BASE, None, None
            )
        with self.assertRaisesRegex(fake.PlanError, "event 0x400"):
            encoder.encode_3d(
                recovered_abi(),
                descriptor,
                GPU_BASE,
                None,
                {"decisions": {"0x80": True}},
            )

    def test_reference_encoder_selects_fallthrough_path(self):
        _, descriptor = encoded_buffers()
        _, _, plan = encoder.encode_3d(
            recovered_abi(),
            descriptor,
            GPU_BASE,
            None,
            {
                "decisions": {"0x80": "fallthrough"},
                "values": {"0x400": 0},
            },
        )

        self.assertEqual(plan["coverage"]["total_writes"], 16)
        self.assertTrue(plan["encoder"]["zero_template"])
        self.assertEqual(
            plan["passes"][0]["producer_offsets"],
            [0x50, 0x200, 0x300, 0x400],
        )

    def test_reference_encoder_cli_writes_buffers_and_plan(self):
        _, descriptor = encoded_buffers()
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            abi_path = root / "abi.json"
            descriptor_path = root / "descriptor.bin"
            externals_path = root / "externals.json"
            command_path = root / "command.bin"
            output_descriptor_path = root / "output-descriptor.bin"
            plan_path = root / "plan.json"
            abi_path.write_text(json.dumps(recovered_abi()))
            descriptor_path.write_bytes(descriptor)
            externals_path.write_text(json.dumps({
                "decisions": {"0x80": "taken"},
                "values": {"0x400": "0x123456789abcdef0"},
            }))

            status = encoder.main([
                "--abi", str(abi_path),
                "--descriptor", str(descriptor_path),
                "--command-gpu-address", hex(GPU_BASE),
                "--zero-template",
                "--externals", str(externals_path),
                "--command-output", str(command_path),
                "--descriptor-output", str(output_descriptor_path),
                "--plan-output", str(plan_path),
            ])

            self.assertEqual(status, 0)
            self.assertEqual(len(command_path.read_bytes()), 0x2240)
            self.assertEqual(len(output_descriptor_path.read_bytes()), 0x15B0)
            plan = json.loads(plan_path.read_text())
            self.assertEqual(plan["schema"], fake.PLAN_SCHEMA)
            self.assertEqual(plan["coverage"]["total_writes"], 20)

    def test_rejects_non_recovered_order(self):
        command, descriptor = encoded_buffers()
        command[0xA0 : 0xA4] = (TEMPLATE | 0x10 | 1).to_bytes(4, "little")
        with self.assertRaisesRegex(fake.PlanError, "no recovered"):
            fake.compile_plan(recovered_abi(), command, descriptor, GPU_BASE)

    def test_rejects_recovered_value_mismatch(self):
        command, descriptor = encoded_buffers()
        command[0xA0 + 12 + 4] ^= 1
        with self.assertRaisesRegex(fake.PlanError, "recovered"):
            fake.compile_plan(recovered_abi(), command, descriptor, GPU_BASE)

    def test_rejects_descriptor_summary_mismatch(self):
        command, descriptor = encoded_buffers()
        descriptor[0x832] = 1
        with self.assertRaisesRegex(fake.PlanError, "summary mismatch"):
            fake.compile_plan(recovered_abi(), command, descriptor, GPU_BASE)

    def test_cli_writes_versioned_plan(self):
        command, descriptor = encoded_buffers()
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            abi_path = root / "abi.json"
            command_path = root / "command.bin"
            descriptor_path = root / "descriptor.bin"
            output_path = root / "plan.json"
            abi_path.write_text(json.dumps(recovered_abi()))
            command_path.write_bytes(command)
            descriptor_path.write_bytes(descriptor)

            result = fake.main(
                [
                    "--abi",
                    str(abi_path),
                    "--command",
                    str(command_path),
                    "--descriptor",
                    str(descriptor_path),
                    "--command-gpu-address",
                    hex(GPU_BASE),
                    "--output",
                    str(output_path),
                ]
            )
            self.assertEqual(result, 0)
            self.assertEqual(json.loads(output_path.read_text())["schema"], fake.PLAN_SCHEMA)


def accelerator_pointer(offset=0):
    pointer = {
        "kind": "object_load",
        "member": 0x10,
        "bytes": 8,
        "signed": False,
        "base": {"kind": "argument", "register": 0, "name": "channel"},
    }
    if not offset:
        return pointer
    return {
        "kind": "stack_reload",
        "source": {
            "kind": "expression",
            "operation": "add",
            "bytes": 8,
            "first": pointer,
            "second": {"kind": "constant", "value": offset},
        },
    }


def accelerator_load(member, width, offset=0):
    return {
        "kind": "object_load",
        "member": member,
        "bytes": width,
        "signed": False,
        "base": accelerator_pointer(offset),
    }


def folding_abi():
    flags = accelerator_load(0x6D0, 8)
    entries = [
        {
            "producer_offset": 0x10,
            "value_source": {
                "kind": "expression", "operation": "and", "bytes": 8,
                "source": flags, "immediate": 1 << 20,
            },
        },
        {
            "producer_offset": 0x20,
            "value_source": {
                "kind": "expression", "operation": "and", "bytes": 8,
                "source": flags, "immediate": 1,
            },
        },
        {
            "producer_offset": 0x30,
            "value_source": {
                "kind": "expression", "operation": "csel", "bytes": 8,
                "condition": "ls",
                "predicate": {
                    "kind": "condition", "operation": "cmp", "bytes": 4,
                    "source": accelerator_load(0x4E4, 4), "immediate": 4,
                },
                "first": {"kind": "constant", "value": 7},
                "second": {"kind": "constant", "value": 9},
            },
        },
        {
            "producer_offset": 0x40,
            "value_source": {
                "kind": "expression", "operation": "orr", "bytes": 8,
                "first": accelerator_load(8, 8, 0xF7EC),
                "second": accelerator_load(0, 8, 0xF7EC),
                "shift": "lsr", "amount": 32,
            },
        },
    ]
    decisions = [
        {
            "producer_offset": 0x50,
            "condition": "bit_clear",
            "predicate": {
                "kind": "condition", "operation": "test_bit", "bytes": 4, "bit": 5,
                "source": accelerator_load(0x6D3, 1),
            },
            "taken": {"next": [0x60]},
            "fallthrough": {"next": [0x70]},
        },
        {
            "producer_offset": 0x58,
            "condition": "bit_set",
            "predicate": {
                "kind": "condition", "operation": "test_bit", "bytes": 4, "bit": 0,
                "source": {"kind": "descriptor_load", "member": 0, "bytes": 1},
            },
            "taken": {"next": [0x60]},
            "fallthrough": {"next": [0x70]},
        },
    ]
    return {
        "channels": {
            "register_selectors": {"producers": {"3D": {"encoder_entries": entries}}},
            "register_emission_cfg": {"producers": {"3D": {"decisions": decisions}}},
            "accelerator_inputs": {
                "power_column_count": {
                    "member": 0x4E4, "bytes": 4, "hardware_input": "column_count",
                },
                "feature_flags": {
                    "member": 0x6D0, "bytes": 8,
                    "never_set_mask": fake.UINT64_MASK & ~1,
                },
                "chip_information": {
                    "override_member": 0xF7F0,
                    "override_bytes": 16,
                    "override_value": (bytes(8) + (1 << 32).to_bytes(8, "little")).hex(),
                },
            },
        }
    }


class AcceleratorFoldingTests(unittest.TestCase):
    def values(self, abi):
        entries = abi["channels"]["register_selectors"]["producers"]["3D"]["encoder_entries"]
        return {entry["producer_offset"]: entry["value_source"] for entry in entries}

    def evaluate(self, node):
        return fake._evaluate(node, bytes(0x10), bytes(0x10))

    def test_folds_proven_accelerator_bits_and_leaves_the_rest(self):
        abi = folding_abi()
        folded = fake.fold_accelerator_inputs(abi)
        values = self.values(folded)

        self.assertEqual(values[0x10]["kind"], "constant")
        self.assertEqual(self.evaluate(values[0x10]), 0)
        with self.assertRaises(fake.UnresolvedValue):
            self.evaluate(values[0x20])
        with self.assertRaisesRegex(fake.UnresolvedValue, "column_count"):
            self.evaluate(values[0x30])
        # Only the literal's bytes survive the shift, and they are zero.
        self.assertEqual(self.evaluate(values[0x40]), 0)

        decisions = folded["channels"]["register_emission_cfg"]["producers"]["3D"]["decisions"]
        self.assertEqual(decisions[0]["condition"], "eq")
        self.assertTrue(fake._condition(decisions[0]["predicate"], "eq", b"", b""))
        self.assertIn("folded_from", decisions[0])
        self.assertEqual(decisions[1], abi["channels"]["register_emission_cfg"]["producers"]["3D"]["decisions"][1])
        # The input ABI is not modified.
        self.assertEqual(self.values(abi)[0x10]["kind"], "expression")

    def test_hardware_inputs_select_the_topology_branch(self):
        narrow = self.values(fake.fold_accelerator_inputs(folding_abi(), {"column_count": 4}))
        wide = self.values(fake.fold_accelerator_inputs(folding_abi(), {"column_count": 8}))
        self.assertEqual(self.evaluate(narrow[0x30]), 7)
        self.assertEqual(self.evaluate(wide[0x30]), 9)

    def test_register_comparisons_use_first_and_shifted_second(self):
        predicate = {
            "kind": "condition", "operation": "cmp", "bytes": 4,
            "first": {"kind": "descriptor_load", "member": 0, "bytes": 4},
            "second": {"kind": "constant", "value": 1},
            "modifier": "lsl", "amount": 4,
        }
        descriptor = (15).to_bytes(4, "little")
        self.assertTrue(fake._condition(predicate, "cc", descriptor, b""))
        self.assertFalse(fake._condition(predicate, "cs", descriptor, b""))
        descriptor = (16).to_bytes(4, "little")
        self.assertTrue(fake._condition(predicate, "hs", descriptor, b""))
        self.assertIn("source", fake.normalize_predicate(predicate))

    def test_abi_without_accelerator_inputs_is_unchanged(self):
        abi = folding_abi()
        del abi["channels"]["accelerator_inputs"]
        self.assertIs(fake.fold_accelerator_inputs(abi), abi)


if __name__ == "__main__":
    unittest.main()
