/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_AGX_FAKE_G17_H
#define VINIX_AGX_FAKE_G17_H

#include <stddef.h>
#include <stdint.h>

/* Host-side verifier for a HAL300 3D register-list command.  Keep these
 * constants in lockstep with kernel/modules/gpu/agx/fw/g17.v. */
enum {
    VINIX_FAKE_G17_COMMAND_BYTES = 0x2240,
    VINIX_FAKE_G17_DESCRIPTOR_BYTES = 0x15b0,
    VINIX_FAKE_G17_REGISTER_PASSES = 4,
    VINIX_FAKE_G17_REGISTER_STRIDE = 0x720,
    VINIX_FAKE_G17_STREAM_OFFSET = 0xa0,
    VINIX_FAKE_G17_STREAM_BYTES = 0x700,
    VINIX_FAKE_G17_METADATA_OFFSET = 0x7a0,
    VINIX_FAKE_G17_ENTRY_BYTES = 0x0c,
    VINIX_FAKE_G17_SUMMARY_OFFSET = 0x828,
    VINIX_FAKE_G17_SUMMARY_STRIDE = 0x10,
};

#define VINIX_FAKE_G17_SELECTOR_FIELD UINT32_C(0x0003fff8)
#define VINIX_FAKE_G17_MODE_FIELD UINT32_C(0x00000001)
#define VINIX_FAKE_G17_TEMPLATE_MASK UINT32_C(0xfffc0006)

enum vinix_fake_g17_error {
    VINIX_FAKE_G17_OK = 0,
    VINIX_FAKE_G17_INVALID_ARGUMENT = 1,
    VINIX_FAKE_G17_COMMAND_TOO_SMALL = 2,
    VINIX_FAKE_G17_DESCRIPTOR_TOO_SMALL = 3,
    VINIX_FAKE_G17_STREAM_ADDRESS = 4,
    VINIX_FAKE_G17_STREAM_COUNTERS = 5,
    VINIX_FAKE_G17_DESCRIPTOR_SUMMARY = 6,
    VINIX_FAKE_G17_WRITE_COUNT = 7,
    VINIX_FAKE_G17_PASS_ORDER = 8,
    VINIX_FAKE_G17_SELECTOR = 9,
    VINIX_FAKE_G17_MODE = 10,
    VINIX_FAKE_G17_TEMPLATE_BITS = 11,
    VINIX_FAKE_G17_VALUE = 12,
    VINIX_FAKE_G17_ADDRESS = 13,
    VINIX_FAKE_G17_RESOURCE_METADATA = 14,
    VINIX_FAKE_G17_RESOURCE_ADDRESS = 15,
    VINIX_FAKE_G17_RESOURCE_VALUE = 16,
    VINIX_FAKE_G17_QUEUE_FULL = 17,
};

enum vinix_fake_g17_vm_access {
    VINIX_FAKE_G17_VM_READ = 1u << 0,
    VINIX_FAKE_G17_VM_WRITE = 1u << 1,
};

enum vinix_fake_g17_descriptor_provenance {
    VINIX_FAKE_G17_PROVENANCE_CONSTANT = 0,
    VINIX_FAKE_G17_PROVENANCE_MESA_COMMAND = 1,
    VINIX_FAKE_G17_PROVENANCE_BO_RESOURCE = 2,
    VINIX_FAKE_G17_PROVENANCE_GPU_VA = 3,
    VINIX_FAKE_G17_PROVENANCE_FORMAT_STRIDE = 4,
    VINIX_FAKE_G17_PROVENANCE_EXTERNAL_HARDWARE = 5,
};

enum vinix_fake_g17_render_resource_field {
    VINIX_FAKE_G17_RESOURCE_ENCODER = 0,
    VINIX_FAKE_G17_RESOURCE_VERTEX_HELPER_ARGUMENT = 1,
    VINIX_FAKE_G17_RESOURCE_FRAGMENT_HELPER_ARGUMENT = 2,
    VINIX_FAKE_G17_RESOURCE_DEPTH_BUFFER_LOAD = 3,
    VINIX_FAKE_G17_RESOURCE_DEPTH_BUFFER_STORE = 4,
    VINIX_FAKE_G17_RESOURCE_DEPTH_BUFFER_PARTIAL = 5,
    VINIX_FAKE_G17_RESOURCE_DEPTH_META_BUFFER_LOAD = 6,
    VINIX_FAKE_G17_RESOURCE_DEPTH_META_BUFFER_STORE = 7,
    VINIX_FAKE_G17_RESOURCE_DEPTH_META_BUFFER_PARTIAL = 8,
    VINIX_FAKE_G17_RESOURCE_STENCIL_BUFFER_LOAD = 9,
    VINIX_FAKE_G17_RESOURCE_STENCIL_BUFFER_STORE = 10,
    VINIX_FAKE_G17_RESOURCE_STENCIL_BUFFER_PARTIAL = 11,
    VINIX_FAKE_G17_RESOURCE_STENCIL_META_BUFFER_LOAD = 12,
    VINIX_FAKE_G17_RESOURCE_STENCIL_META_BUFFER_STORE = 13,
    VINIX_FAKE_G17_RESOURCE_STENCIL_META_BUFFER_PARTIAL = 14,
    VINIX_FAKE_G17_RESOURCE_SCISSOR_ARRAY = 15,
    VINIX_FAKE_G17_RESOURCE_DEPTH_BIAS_ARRAY = 16,
    VINIX_FAKE_G17_RESOURCE_VISIBILITY_RESULT_BUFFER = 17,
    VINIX_FAKE_G17_RESOURCE_VERTEX_SAMPLER_ARRAY = 18,
    VINIX_FAKE_G17_RESOURCE_FRAGMENT_SAMPLER_ARRAY = 19,
    VINIX_FAKE_G17_RESOURCE_VERTEX_ATTACHMENT = 20,
    VINIX_FAKE_G17_RESOURCE_FRAGMENT_ATTACHMENT = 21,
    VINIX_FAKE_G17_RESOURCE_FIELD_COUNT = 22,
};

enum {
    /* No recovered native member is claimed for this input yet. */
    VINIX_FAKE_G17_DESCRIPTOR_MEMBER_PENDING = UINT32_MAX,
};

enum vinix_fake_g17_write_flags {
    /* Treat the encoded value as a GPU virtual address and require it to be
     * aligned and contained in one supplied address range. */
    VINIX_FAKE_G17_VALUE_IS_ADDRESS = 1u << 0,
};

/* A path-specific golden trace.  One record describes one physical HAL300
 * entry after the recovered control-flow predicates have been evaluated.
 * A zero value_mask or template_mask means that field is intentionally not
 * constrained.  selector, pass and mode are always checked. */
struct vinix_fake_g17_expected_write {
    uint64_t value;
    uint64_t value_mask;
    uint32_t selector;
    uint32_t template_bits;
    uint32_t template_mask;
    uint32_t address_alignment;
    uint32_t flags;
    uint32_t pass;
    uint32_t mode;
};

struct vinix_fake_g17_address_range {
    uint64_t address;
    uint64_t size;
    uint32_t access;
    uint32_t object_handle;
};

/* A Mesa-derived resource that must resolve through the fake VM.  Until a
 * native G17 descriptor member is proven, descriptor_member is PENDING and
 * descriptor_bytes is zero.  Once mapped, the verifier also checks that the
 * descriptor contains this exact GPU VA. */
struct vinix_fake_g17_resource_reference {
    uint64_t address;
    uint64_t size;
    uint32_t field;
    uint32_t provenance;
    uint32_t descriptor_member;
    uint32_t descriptor_bytes;
    uint32_t access;
    uint32_t reserved;
};

struct vinix_fake_g17_report {
    uint64_t observed;
    uint64_t expected;
    uint32_t error;
    uint32_t pass;
    uint32_t entry;
    uint32_t observed_writes;
    uint32_t expected_writes;
};

size_t vinix_fake_g17_expected_write_size(void);
size_t vinix_fake_g17_address_range_size(void);
size_t vinix_fake_g17_resource_reference_size(void);
size_t vinix_fake_g17_report_size(void);

int vinix_fake_g17_verify(const void *command, size_t command_bytes,
                          const void *descriptor, size_t descriptor_bytes,
                          uint64_t command_gpu_address,
                          const struct vinix_fake_g17_expected_write *writes,
                          uint32_t write_count,
                          const struct vinix_fake_g17_address_range *ranges,
                          uint32_t range_count,
                          const struct vinix_fake_g17_resource_reference *resources,
                          uint32_t resource_count,
                          struct vinix_fake_g17_report *report);

const char *vinix_fake_g17_error_string(int error);

#endif
