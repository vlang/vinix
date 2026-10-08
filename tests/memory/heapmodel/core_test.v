module heapmodel

import os

fn source_root() string { return os.dir(os.dir(os.dir(os.dir(@FILE)))) }

fn test_source_geometry_and_classes() { source_geometry(source_root())! }

fn test_bit_search_all_positions_and_random_words() { bit_search() }

fn test_all_classes_multi_page_lifecycle() { all_classes_lifecycle() }

fn test_single_slot_full_to_empty() { single_slot() }

fn test_partial_preferred_to_spare() { partial_before_spare() }

fn test_payload_poison_and_zero_on_reuse() { poison_and_zero() }

fn test_invalid_and_double_free_on_resident_page() { invalid_free() }

fn test_random_mixed_size_churn() { mixed_size_churn() }

fn test_arithmetic_guards() { arithmetic_guards(source_root())! }

fn test_irq_snapshot_source_order() { irq_snapshot(source_root())! }
