/* SPDX-License-Identifier: GPL-2.0-or-later */
#include "agx_fake_g17.h"

static uint16_t read_le16(const uint8_t *bytes)
{
    return (uint16_t)bytes[0] | ((uint16_t)bytes[1] << 8);
}

static uint32_t read_le32(const uint8_t *bytes)
{
    return (uint32_t)bytes[0] |
           ((uint32_t)bytes[1] << 8) |
           ((uint32_t)bytes[2] << 16) |
           ((uint32_t)bytes[3] << 24);
}

static uint64_t read_le64(const uint8_t *bytes)
{
    return (uint64_t)read_le32(bytes) |
           ((uint64_t)read_le32(bytes + 4) << 32);
}

static void clear_report(struct vinix_fake_g17_report *report,
                         uint32_t expected_writes)
{
    *report = (struct vinix_fake_g17_report){0};
    report->expected_writes = expected_writes;
}

static int fail(struct vinix_fake_g17_report *report, int error,
                uint32_t pass, uint32_t entry,
                uint64_t observed, uint64_t expected)
{
    report->error = (uint32_t)error;
    report->pass = pass;
    report->entry = entry;
    report->observed = observed;
    report->expected = expected;
    return error;
}

static int power_of_two(uint32_t value)
{
    return value && !(value & (value - 1));
}

static int address_allowed(uint64_t address, uint32_t alignment,
                           const struct vinix_fake_g17_address_range *ranges,
                           uint32_t range_count)
{
    uint32_t i;

    if (!power_of_two(alignment) || (address & (alignment - 1)))
        return 0;

    for (i = 0; i < range_count; i++) {
        /* Subtraction after the lower-bound check avoids end-address
         * overflow for canonical-high GPU virtual address ranges. */
        if (ranges[i].size && address >= ranges[i].address &&
            address - ranges[i].address < ranges[i].size)
            return 1;
    }
    return 0;
}

static int range_allowed(uint64_t address, uint64_t size, uint32_t access,
                         const struct vinix_fake_g17_address_range *ranges,
                         uint32_t range_count)
{
    uint32_t i;

    if (!address || !size || address > UINT64_MAX - size || !access ||
        (access & ~(VINIX_FAKE_G17_VM_READ | VINIX_FAKE_G17_VM_WRITE)))
        return 0;

    for (i = 0; i < range_count; i++) {
        const struct vinix_fake_g17_address_range *range = &ranges[i];

        if (range->size && range->object_handle && range->access &&
            !(range->access &
              ~(VINIX_FAKE_G17_VM_READ | VINIX_FAKE_G17_VM_WRITE)) &&
            address >= range->address &&
            address - range->address <= range->size &&
            size <= range->size - (address - range->address) &&
            (range->access & access) == access)
            return 1;
    }
    return 0;
}

size_t vinix_fake_g17_expected_write_size(void)
{
    return sizeof(struct vinix_fake_g17_expected_write);
}

size_t vinix_fake_g17_address_range_size(void)
{
    return sizeof(struct vinix_fake_g17_address_range);
}

size_t vinix_fake_g17_resource_reference_size(void)
{
    return sizeof(struct vinix_fake_g17_resource_reference);
}

size_t vinix_fake_g17_report_size(void)
{
    return sizeof(struct vinix_fake_g17_report);
}

int vinix_fake_g17_verify(const void *command_pointer, size_t command_bytes,
                          const void *descriptor_pointer,
                          size_t descriptor_bytes,
                          uint64_t command_gpu_address,
                          const struct vinix_fake_g17_expected_write *writes,
                          uint32_t write_count,
                          const struct vinix_fake_g17_address_range *ranges,
                          uint32_t range_count,
                          const struct vinix_fake_g17_resource_reference *resources,
                          uint32_t resource_count,
                          struct vinix_fake_g17_report *report)
{
    const uint8_t *command = command_pointer;
    const uint8_t *descriptor = descriptor_pointer;
    uint32_t observed_writes = 0;
    uint32_t pass;

    if (!report)
        return VINIX_FAKE_G17_INVALID_ARGUMENT;
    clear_report(report, write_count);

    if (!command || !descriptor || !command_gpu_address ||
        (write_count && !writes) || (range_count && !ranges) ||
        (resource_count && !resources))
        return fail(report, VINIX_FAKE_G17_INVALID_ARGUMENT, 0, 0, 0, 0);
    if (command_bytes < VINIX_FAKE_G17_COMMAND_BYTES)
        return fail(report, VINIX_FAKE_G17_COMMAND_TOO_SMALL, 0, 0,
                    command_bytes, VINIX_FAKE_G17_COMMAND_BYTES);
    if (descriptor_bytes < VINIX_FAKE_G17_DESCRIPTOR_BYTES)
        return fail(report, VINIX_FAKE_G17_DESCRIPTOR_TOO_SMALL, 0, 0,
                    descriptor_bytes, VINIX_FAKE_G17_DESCRIPTOR_BYTES);

    for (pass = 0; pass < resource_count; pass++) {
        const struct vinix_fake_g17_resource_reference *resource =
            &resources[pass];

        if (resource->reserved ||
            resource->field >= VINIX_FAKE_G17_RESOURCE_FIELD_COUNT ||
            (resource->provenance != VINIX_FAKE_G17_PROVENANCE_BO_RESOURCE &&
             resource->provenance != VINIX_FAKE_G17_PROVENANCE_GPU_VA) ||
            (resource->descriptor_member ==
                 VINIX_FAKE_G17_DESCRIPTOR_MEMBER_PENDING
                 ? resource->descriptor_bytes != 0
                 : resource->descriptor_bytes != 8 ||
                   resource->descriptor_member > descriptor_bytes ||
                   resource->descriptor_bytes >
                       descriptor_bytes - resource->descriptor_member))
            return fail(report, VINIX_FAKE_G17_RESOURCE_METADATA, 0,
                        pass, resource->field, resource->provenance);
        if (!range_allowed(resource->address, resource->size,
                           resource->access, ranges, range_count))
            return fail(report, VINIX_FAKE_G17_RESOURCE_ADDRESS, 0,
                        pass, resource->address, resource->size);
        if (resource->descriptor_member !=
                VINIX_FAKE_G17_DESCRIPTOR_MEMBER_PENDING &&
            read_le64(descriptor + resource->descriptor_member) !=
                resource->address)
            return fail(report, VINIX_FAKE_G17_RESOURCE_VALUE, 0,
                        pass,
                        read_le64(descriptor + resource->descriptor_member),
                        resource->address);
    }

    for (pass = 0; pass < VINIX_FAKE_G17_REGISTER_PASSES; pass++) {
        size_t stream_offset = (size_t)pass * VINIX_FAKE_G17_REGISTER_STRIDE +
                               VINIX_FAKE_G17_STREAM_OFFSET;
        size_t metadata_offset =
            (size_t)pass * VINIX_FAKE_G17_REGISTER_STRIDE +
            VINIX_FAKE_G17_METADATA_OFFSET;
        size_t summary_offset = VINIX_FAKE_G17_SUMMARY_OFFSET +
                                (size_t)pass * VINIX_FAKE_G17_SUMMARY_STRIDE;
        const uint8_t *metadata = command + metadata_offset;
        const uint8_t *summary = descriptor + summary_offset;
        uint64_t stream_gpu = read_le64(metadata);
        uint16_t entry_count = read_le16(metadata + 8);
        uint16_t byte_length = read_le16(metadata + 10);
        uint64_t expected_stream_gpu;
        uint32_t entry;

        if (command_gpu_address > UINT64_MAX - stream_offset)
            return fail(report, VINIX_FAKE_G17_STREAM_ADDRESS, pass, 0,
                        stream_gpu, 0);
        expected_stream_gpu = command_gpu_address + stream_offset;
        if (stream_gpu != expected_stream_gpu)
            return fail(report, VINIX_FAKE_G17_STREAM_ADDRESS, pass, 0,
                        stream_gpu, expected_stream_gpu);

        if (byte_length > VINIX_FAKE_G17_STREAM_BYTES ||
            byte_length % VINIX_FAKE_G17_ENTRY_BYTES ||
            entry_count != byte_length / VINIX_FAKE_G17_ENTRY_BYTES)
            return fail(report, VINIX_FAKE_G17_STREAM_COUNTERS, pass, 0,
                        ((uint64_t)entry_count << 32) | byte_length,
                        byte_length / VINIX_FAKE_G17_ENTRY_BYTES);

        if (read_le64(summary) != stream_gpu ||
            read_le16(summary + 8) != entry_count ||
            summary[10] || summary[11] || summary[12] || summary[13] ||
            summary[14] || summary[15])
            return fail(report, VINIX_FAKE_G17_DESCRIPTOR_SUMMARY, pass, 0,
                        read_le64(summary), stream_gpu);

        if ((uint64_t)observed_writes + entry_count > write_count)
            return fail(report, VINIX_FAKE_G17_WRITE_COUNT, pass, 0,
                        (uint64_t)observed_writes + entry_count, write_count);

        for (entry = 0; entry < entry_count; entry++) {
            const struct vinix_fake_g17_expected_write *golden =
                &writes[observed_writes];
            const uint8_t *encoded = command + stream_offset +
                                     (size_t)entry * VINIX_FAKE_G17_ENTRY_BYTES;
            uint32_t selector_word = read_le32(encoded);
            uint32_t selector = selector_word & VINIX_FAKE_G17_SELECTOR_FIELD;
            uint32_t mode = selector_word & VINIX_FAKE_G17_MODE_FIELD;
            uint64_t value = read_le64(encoded + 4);

            report->observed_writes = observed_writes + 1;
            if (golden->pass != pass)
                return fail(report, VINIX_FAKE_G17_PASS_ORDER, pass, entry,
                            pass, golden->pass);
            if (golden->selector & ~VINIX_FAKE_G17_SELECTOR_FIELD)
                return fail(report, VINIX_FAKE_G17_INVALID_ARGUMENT,
                            pass, entry, golden->selector,
                            VINIX_FAKE_G17_SELECTOR_FIELD);
            if (selector != golden->selector)
                return fail(report, VINIX_FAKE_G17_SELECTOR, pass, entry,
                            selector, golden->selector);
            if (golden->mode > 1)
                return fail(report, VINIX_FAKE_G17_INVALID_ARGUMENT,
                            pass, entry, golden->mode, 1);
            if (mode != golden->mode)
                return fail(report, VINIX_FAKE_G17_MODE, pass, entry,
                            mode, golden->mode);
            if (golden->template_mask & ~VINIX_FAKE_G17_TEMPLATE_MASK)
                return fail(report, VINIX_FAKE_G17_INVALID_ARGUMENT,
                            pass, entry, golden->template_mask,
                            VINIX_FAKE_G17_TEMPLATE_MASK);
            if ((selector_word & golden->template_mask) !=
                (golden->template_bits & golden->template_mask))
                return fail(report, VINIX_FAKE_G17_TEMPLATE_BITS,
                            pass, entry,
                            selector_word & golden->template_mask,
                            golden->template_bits & golden->template_mask);
            if (golden->value_mask &&
                (value & golden->value_mask) !=
                (golden->value & golden->value_mask))
                return fail(report, VINIX_FAKE_G17_VALUE, pass, entry,
                            value & golden->value_mask,
                            golden->value & golden->value_mask);
            if ((golden->flags & VINIX_FAKE_G17_VALUE_IS_ADDRESS) &&
                !address_allowed(value, golden->address_alignment,
                                 ranges, range_count))
                return fail(report, VINIX_FAKE_G17_ADDRESS, pass, entry,
                            value, golden->address_alignment);
            if (golden->flags & ~VINIX_FAKE_G17_VALUE_IS_ADDRESS)
                return fail(report, VINIX_FAKE_G17_INVALID_ARGUMENT,
                            pass, entry, golden->flags,
                            VINIX_FAKE_G17_VALUE_IS_ADDRESS);

            observed_writes++;
        }
    }

    report->observed_writes = observed_writes;
    if (observed_writes != write_count)
        return fail(report, VINIX_FAKE_G17_WRITE_COUNT,
                    VINIX_FAKE_G17_REGISTER_PASSES, 0,
                    observed_writes, write_count);

    report->error = VINIX_FAKE_G17_OK;
    return VINIX_FAKE_G17_OK;
}

const char *vinix_fake_g17_error_string(int error)
{
    static const char *const errors[] = {
        "ok",
        "invalid verifier request",
        "3D command buffer is too small",
        "3D descriptor is too small",
        "register stream GPU address mismatch",
        "register stream counters are invalid",
        "descriptor summary mismatch",
        "register write count mismatch",
        "register pass/order mismatch",
        "register selector mismatch",
        "register mode mismatch",
        "register template bits mismatch",
        "register value mismatch",
        "GPU address is outside the allowed ranges",
        "descriptor resource metadata is invalid",
        "descriptor resource is outside its permitted VM binding",
        "descriptor resource value does not match its Mesa GPU VA",
        "fake G17 work queue is full",
    };

    if (error < 0 || (size_t)error >= sizeof(errors) / sizeof(errors[0]))
        return "unknown fake-G17 verifier error";
    return errors[error];
}
