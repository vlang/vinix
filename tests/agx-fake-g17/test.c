#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "../../kernel/c/agx_fake_g17.h"

#define CHECK(expression) do {                                               \
    if (!(expression)) {                                                     \
        fprintf(stderr, "check failed at line %d: %s\n",                   \
                __LINE__, #expression);                                      \
        return 1;                                                            \
    }                                                                        \
} while (0)

#define CHECK_ERROR(expected_error) do {                                     \
    int actual_error = verify(&fixture, writes, write_count, ranges, 1,       \
                              &report);                                       \
    if (actual_error != (expected_error)) {                                  \
        fprintf(stderr, "line %d: expected %s, got %s\n",                  \
                __LINE__, vinix_fake_g17_error_string(expected_error),       \
                vinix_fake_g17_error_string(actual_error));                  \
        return 1;                                                            \
    }                                                                        \
} while (0)

#define TEMPLATE_BITS UINT32_C(0xa5a40006)
#define GPU_BASE UINT64_C(0x700000000)
#define ADDRESS_BASE UINT64_C(0x80000000)

struct fixture {
    uint8_t command[VINIX_FAKE_G17_COMMAND_BYTES];
    uint8_t descriptor[VINIX_FAKE_G17_DESCRIPTOR_BYTES];
};

static void write_le16(uint8_t *bytes, uint16_t value)
{
    bytes[0] = (uint8_t)value;
    bytes[1] = (uint8_t)(value >> 8);
}

static void write_le32(uint8_t *bytes, uint32_t value)
{
    bytes[0] = (uint8_t)value;
    bytes[1] = (uint8_t)(value >> 8);
    bytes[2] = (uint8_t)(value >> 16);
    bytes[3] = (uint8_t)(value >> 24);
}

static void write_le64(uint8_t *bytes, uint64_t value)
{
    write_le32(bytes, (uint32_t)value);
    write_le32(bytes + 4, (uint32_t)(value >> 32));
}

static uint8_t *stream(struct fixture *fixture, uint32_t pass)
{
    return fixture->command + (size_t)pass * VINIX_FAKE_G17_REGISTER_STRIDE +
           VINIX_FAKE_G17_STREAM_OFFSET;
}

static uint8_t *metadata(struct fixture *fixture, uint32_t pass)
{
    return fixture->command + (size_t)pass * VINIX_FAKE_G17_REGISTER_STRIDE +
           VINIX_FAKE_G17_METADATA_OFFSET;
}

static uint8_t *summary(struct fixture *fixture, uint32_t pass)
{
    return fixture->descriptor + VINIX_FAKE_G17_SUMMARY_OFFSET +
           (size_t)pass * VINIX_FAKE_G17_SUMMARY_STRIDE;
}

static void build_fixture(struct fixture *fixture,
                          struct vinix_fake_g17_expected_write *writes,
                          const uint16_t counts[VINIX_FAKE_G17_REGISTER_PASSES])
{
    uint32_t index = 0;
    uint32_t pass;

    memset(fixture, 0, sizeof(*fixture));
    for (pass = 0; pass < VINIX_FAKE_G17_REGISTER_PASSES; pass++) {
        uint64_t stream_gpu = GPU_BASE +
            (uint64_t)pass * VINIX_FAKE_G17_REGISTER_STRIDE +
            VINIX_FAKE_G17_STREAM_OFFSET;
        uint16_t entry;

        write_le64(metadata(fixture, pass), stream_gpu);
        write_le16(metadata(fixture, pass) + 8, counts[pass]);
        write_le16(metadata(fixture, pass) + 10,
                   (uint16_t)(counts[pass] * VINIX_FAKE_G17_ENTRY_BYTES));
        write_le64(summary(fixture, pass), stream_gpu);
        write_le16(summary(fixture, pass) + 8, counts[pass]);

        for (entry = 0; entry < counts[pass]; entry++, index++) {
            struct vinix_fake_g17_expected_write *write = &writes[index];
            uint8_t *encoded = stream(fixture, pass) +
                (size_t)entry * VINIX_FAKE_G17_ENTRY_BYTES;

            *write = (struct vinix_fake_g17_expected_write){
                .value = UINT64_C(0x100000000) + index,
                .value_mask = UINT64_MAX,
                .selector = (index + 1) * 8,
                .template_bits = TEMPLATE_BITS,
                .template_mask = VINIX_FAKE_G17_TEMPLATE_MASK,
                .pass = pass,
                .mode = index & 1,
            };
            if (!(index % 31)) {
                write->value = ADDRESS_BASE + (uint64_t)index * 0x100;
                write->address_alignment = 16;
                write->flags = VINIX_FAKE_G17_VALUE_IS_ADDRESS;
            }

            write_le32(encoded, TEMPLATE_BITS | write->selector | write->mode);
            write_le64(encoded + 4, write->value);
        }
    }
}

static int verify(struct fixture *fixture,
                  struct vinix_fake_g17_expected_write *writes,
                  uint32_t write_count,
                  struct vinix_fake_g17_address_range *ranges,
                  uint32_t range_count,
                  struct vinix_fake_g17_report *report)
{
    return vinix_fake_g17_verify(fixture->command, sizeof(fixture->command),
                                 fixture->descriptor,
                                 sizeof(fixture->descriptor), GPU_BASE,
                                 writes, write_count, ranges, range_count,
                                 NULL, 0,
                                 report);
}

static int test_exact_trace(void)
{
    struct fixture fixture;
    struct vinix_fake_g17_expected_write writes[4];
    struct vinix_fake_g17_address_range ranges[] = {
        {ADDRESS_BASE, 0x100000,
         VINIX_FAKE_G17_VM_READ | VINIX_FAKE_G17_VM_WRITE, 7},
    };
    struct vinix_fake_g17_report report;
    const uint16_t counts[] = {1, 1, 1, 1};
    const uint32_t write_count = 4;

    build_fixture(&fixture, writes, counts);
    CHECK_ERROR(VINIX_FAKE_G17_OK);
    CHECK(report.observed_writes == write_count);
    CHECK(report.expected_writes == write_count);

    stream(&fixture, 0)[0] ^= 8;
    CHECK_ERROR(VINIX_FAKE_G17_SELECTOR);
    build_fixture(&fixture, writes, counts);

    stream(&fixture, 0)[0] ^= VINIX_FAKE_G17_MODE_FIELD;
    CHECK_ERROR(VINIX_FAKE_G17_MODE);
    build_fixture(&fixture, writes, counts);

    stream(&fixture, 0)[0] ^= 2;
    CHECK_ERROR(VINIX_FAKE_G17_TEMPLATE_BITS);
    build_fixture(&fixture, writes, counts);

    stream(&fixture, 0)[4] ^= 0x80;
    CHECK_ERROR(VINIX_FAKE_G17_VALUE);
    build_fixture(&fixture, writes, counts);

    writes[0].value = ADDRESS_BASE + 1;
    write_le64(stream(&fixture, 0) + 4, writes[0].value);
    CHECK_ERROR(VINIX_FAKE_G17_ADDRESS);
    build_fixture(&fixture, writes, counts);

    writes[0].pass = 1;
    CHECK_ERROR(VINIX_FAKE_G17_PASS_ORDER);
    build_fixture(&fixture, writes, counts);

    metadata(&fixture, 0)[10]++;
    CHECK_ERROR(VINIX_FAKE_G17_STREAM_COUNTERS);
    build_fixture(&fixture, writes, counts);

    summary(&fixture, 0)[10] = 1;
    CHECK_ERROR(VINIX_FAKE_G17_DESCRIPTOR_SUMMARY);
    build_fixture(&fixture, writes, counts);

    metadata(&fixture, 0)[0] ^= 0x10;
    CHECK_ERROR(VINIX_FAKE_G17_STREAM_ADDRESS);
    build_fixture(&fixture, writes, counts);

    CHECK(vinix_fake_g17_verify(fixture.command,
          VINIX_FAKE_G17_COMMAND_BYTES - 1, fixture.descriptor,
          sizeof(fixture.descriptor), GPU_BASE, writes, write_count,
          ranges, 1, NULL, 0,
          &report) == VINIX_FAKE_G17_COMMAND_TOO_SMALL);
    CHECK(vinix_fake_g17_verify(fixture.command, sizeof(fixture.command),
          fixture.descriptor, VINIX_FAKE_G17_DESCRIPTOR_BYTES - 1,
          GPU_BASE, writes, write_count, ranges, 1,
          NULL, 0,
          &report) == VINIX_FAKE_G17_DESCRIPTOR_TOO_SMALL);
    CHECK(vinix_fake_g17_verify(fixture.command, sizeof(fixture.command),
          fixture.descriptor, sizeof(fixture.descriptor), UINT64_MAX - 0x50,
          writes, write_count, ranges, 1,
          NULL, 0,
          &report) == VINIX_FAKE_G17_STREAM_ADDRESS);

    return 0;
}

static int test_recovered_call_site_scale(void)
{
    /* 314 is the recovered set of virtual HAL300 encoder call sites, not a
     * promise that every site executes for one render.  This proves that a
     * path-specific trace of that size fits and is checked exactly. */
    enum { recovered_calls = 314 };
    struct fixture fixture;
    struct vinix_fake_g17_expected_write *writes =
        calloc(recovered_calls, sizeof(*writes));
    struct vinix_fake_g17_address_range ranges[] = {
        {ADDRESS_BASE, 0x100000,
         VINIX_FAKE_G17_VM_READ | VINIX_FAKE_G17_VM_WRITE, 7},
    };
    struct vinix_fake_g17_report report;
    const uint16_t counts[] = {79, 79, 78, 78};

    CHECK(writes != NULL);
    build_fixture(&fixture, writes, counts);
    CHECK(verify(&fixture, writes, recovered_calls, ranges, 1, &report) ==
          VINIX_FAKE_G17_OK);
    CHECK(report.observed_writes == recovered_calls);

    /* Removing one golden event catches a path/count disagreement before any
     * synthetic completion can be reported to Mesa. */
    CHECK(verify(&fixture, writes, recovered_calls - 1, ranges, 1, &report) ==
          VINIX_FAKE_G17_WRITE_COUNT);

    free(writes);
    return 0;
}

static int test_descriptor_resource_provenance(void)
{
    struct fixture fixture;
    struct vinix_fake_g17_expected_write writes[4];
    struct vinix_fake_g17_address_range ranges[] = {
        {ADDRESS_BASE, 0x1000,
         VINIX_FAKE_G17_VM_READ | VINIX_FAKE_G17_VM_WRITE, 19},
    };
    struct vinix_fake_g17_resource_reference resource = {
        .address = ADDRESS_BASE + 0x100,
        .size = 0x80,
        .field = VINIX_FAKE_G17_RESOURCE_DEPTH_BUFFER_LOAD,
        .provenance = VINIX_FAKE_G17_PROVENANCE_GPU_VA,
        .descriptor_member = VINIX_FAKE_G17_DESCRIPTOR_MEMBER_PENDING,
        .access = VINIX_FAKE_G17_VM_READ,
    };
    struct vinix_fake_g17_report report;
    const uint16_t counts[] = {1, 1, 1, 1};

    build_fixture(&fixture, writes, counts);
    CHECK(vinix_fake_g17_verify(
              fixture.command, sizeof(fixture.command), fixture.descriptor,
              sizeof(fixture.descriptor), GPU_BASE, writes, 4, ranges, 1,
              &resource, 1, &report) == VINIX_FAKE_G17_OK);

    /* The last USC-derived resource identifier is part of the stable V/C
     * sidecar ABI; the following value is not. */
    resource.field = VINIX_FAKE_G17_RESOURCE_PARTIAL_STORE_PIPELINE;
    CHECK(vinix_fake_g17_verify(
              fixture.command, sizeof(fixture.command), fixture.descriptor,
              sizeof(fixture.descriptor), GPU_BASE, writes, 4, ranges, 1,
              &resource, 1, &report) == VINIX_FAKE_G17_OK);
    resource.field = VINIX_FAKE_G17_RESOURCE_FIELD_COUNT;
    CHECK(vinix_fake_g17_verify(
              fixture.command, sizeof(fixture.command), fixture.descriptor,
              sizeof(fixture.descriptor), GPU_BASE, writes, 4, ranges, 1,
              &resource, 1, &report) == VINIX_FAKE_G17_RESOURCE_METADATA);
    resource.field = VINIX_FAKE_G17_RESOURCE_DEPTH_BUFFER_LOAD;

    resource.access = VINIX_FAKE_G17_VM_WRITE;
    ranges[0].access = VINIX_FAKE_G17_VM_READ;
    CHECK(vinix_fake_g17_verify(
              fixture.command, sizeof(fixture.command), fixture.descriptor,
              sizeof(fixture.descriptor), GPU_BASE, writes, 4, ranges, 1,
              &resource, 1, &report) == VINIX_FAKE_G17_RESOURCE_ADDRESS);

    resource.access = VINIX_FAKE_G17_VM_READ;
    ranges[0].access |= VINIX_FAKE_G17_VM_WRITE;
    resource.address = ADDRESS_BASE + 0xff0;
    CHECK(vinix_fake_g17_verify(
              fixture.command, sizeof(fixture.command), fixture.descriptor,
              sizeof(fixture.descriptor), GPU_BASE, writes, 4, ranges, 1,
              &resource, 1, &report) == VINIX_FAKE_G17_RESOURCE_ADDRESS);

    resource.address = ADDRESS_BASE + 0x100;
    resource.descriptor_member = 0x100;
    resource.descriptor_bytes = 8;
    write_le64(fixture.descriptor + resource.descriptor_member,
               resource.address);
    CHECK(vinix_fake_g17_verify(
              fixture.command, sizeof(fixture.command), fixture.descriptor,
              sizeof(fixture.descriptor), GPU_BASE, writes, 4, ranges, 1,
              &resource, 1, &report) == VINIX_FAKE_G17_OK);
    fixture.descriptor[resource.descriptor_member] ^= 1;
    CHECK(vinix_fake_g17_verify(
              fixture.command, sizeof(fixture.command), fixture.descriptor,
              sizeof(fixture.descriptor), GPU_BASE, writes, 4, ranges, 1,
              &resource, 1, &report) == VINIX_FAKE_G17_RESOURCE_VALUE);

    resource.descriptor_member = VINIX_FAKE_G17_DESCRIPTOR_MEMBER_PENDING;
    CHECK(vinix_fake_g17_verify(
              fixture.command, sizeof(fixture.command), fixture.descriptor,
              sizeof(fixture.descriptor), GPU_BASE, writes, 4, ranges, 1,
              &resource, 1, &report) == VINIX_FAKE_G17_RESOURCE_METADATA);
    resource.descriptor_bytes = 0;
    resource.provenance = VINIX_FAKE_G17_PROVENANCE_CONSTANT;
    CHECK(vinix_fake_g17_verify(
              fixture.command, sizeof(fixture.command), fixture.descriptor,
              sizeof(fixture.descriptor), GPU_BASE, writes, 4, ranges, 1,
              &resource, 1, &report) == VINIX_FAKE_G17_RESOURCE_METADATA);
    return 0;
}

static int test_depth_stencil_resource_rejections(void)
{
    struct fixture fixture;
    struct vinix_fake_g17_expected_write writes[4];
    struct vinix_fake_g17_address_range ranges[] = {
        {ADDRESS_BASE, 0x1000, VINIX_FAKE_G17_VM_READ, 29},
    };
    struct vinix_fake_g17_resource_reference resources[] = {
        {
            .address = ADDRESS_BASE + 0x200,
            .size = 0x80,
            .field = VINIX_FAKE_G17_RESOURCE_DEPTH_META_BUFFER_LOAD,
            .provenance = VINIX_FAKE_G17_PROVENANCE_GPU_VA,
            .descriptor_member =
                VINIX_FAKE_G17_DESCRIPTOR_DEPTH_META_BUFFER_LOAD,
            .descriptor_bytes = 8,
            .access = VINIX_FAKE_G17_VM_READ,
        },
        {
            .address = ADDRESS_BASE + 0x400,
            .size = 0x80,
            .field = VINIX_FAKE_G17_RESOURCE_STENCIL_META_BUFFER_STORE,
            .provenance = VINIX_FAKE_G17_PROVENANCE_GPU_VA,
            .descriptor_member =
                VINIX_FAKE_G17_DESCRIPTOR_STENCIL_META_BUFFER_STORE,
            .descriptor_bytes = 8,
            .access = VINIX_FAKE_G17_VM_WRITE,
        },
    };
    struct vinix_fake_g17_report report;
    const uint16_t counts[] = {1, 1, 1, 1};

    build_fixture(&fixture, writes, counts);
    write_le64(fixture.descriptor + resources[0].descriptor_member,
               resources[0].address);
    write_le64(fixture.descriptor + resources[1].descriptor_member,
               resources[1].address);

    CHECK(vinix_fake_g17_verify(
              fixture.command, sizeof(fixture.command), fixture.descriptor,
              sizeof(fixture.descriptor), GPU_BASE, writes, 4, ranges, 1,
              resources, 1, &report) == VINIX_FAKE_G17_OK);

    /* A descriptor address alone is insufficient: an unbound depth metadata
     * BO must be rejected before the recovered command can complete. */
    resources[0].address = ADDRESS_BASE + 0x2000;
    write_le64(fixture.descriptor + resources[0].descriptor_member,
               resources[0].address);
    CHECK(vinix_fake_g17_verify(
              fixture.command, sizeof(fixture.command), fixture.descriptor,
              sizeof(fixture.descriptor), GPU_BASE, writes, 4, ranges, 1,
              resources, 1, &report) == VINIX_FAKE_G17_RESOURCE_ADDRESS);

    resources[0].address = ADDRESS_BASE + 0x200;
    write_le64(fixture.descriptor + resources[0].descriptor_member,
               resources[0].address);

    /* Store metadata requires a writable VM binding; read-only provenance is
     * not upgraded just because the descriptor member is otherwise exact. */
    CHECK(vinix_fake_g17_verify(
              fixture.command, sizeof(fixture.command), fixture.descriptor,
              sizeof(fixture.descriptor), GPU_BASE, writes, 4, ranges, 1,
              resources, 2, &report) == VINIX_FAKE_G17_RESOURCE_ADDRESS);
    ranges[0].access |= VINIX_FAKE_G17_VM_WRITE;
    CHECK(vinix_fake_g17_verify(
              fixture.command, sizeof(fixture.command), fixture.descriptor,
              sizeof(fixture.descriptor), GPU_BASE, writes, 4, ranges, 1,
              resources, 2, &report) == VINIX_FAKE_G17_OK);

    fixture.descriptor[resources[1].descriptor_member] ^= 1;
    CHECK(vinix_fake_g17_verify(
              fixture.command, sizeof(fixture.command), fixture.descriptor,
              sizeof(fixture.descriptor), GPU_BASE, writes, 4, ranges, 1,
              resources, 2, &report) == VINIX_FAKE_G17_RESOURCE_VALUE);
    return 0;
}

int main(void)
{
    CHECK(vinix_fake_g17_expected_write_size() ==
          sizeof(struct vinix_fake_g17_expected_write));
    CHECK(vinix_fake_g17_address_range_size() ==
          sizeof(struct vinix_fake_g17_address_range));
    CHECK(vinix_fake_g17_resource_reference_size() ==
          sizeof(struct vinix_fake_g17_resource_reference));
    CHECK(vinix_fake_g17_report_size() ==
          sizeof(struct vinix_fake_g17_report));
    CHECK(test_exact_trace() == 0);
    CHECK(test_recovered_call_site_scale() == 0);
    CHECK(test_descriptor_resource_provenance() == 0);
    CHECK(test_depth_stencil_resource_rejections() == 0);
    puts("fake G17 HAL300 verifier tests passed");
    return 0;
}
