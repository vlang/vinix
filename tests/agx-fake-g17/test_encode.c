#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "../../kernel/c/agx_fake_g17_encode.h"

#define CHECK(expression) do {                                               \
    if (!(expression)) {                                                     \
        fprintf(stderr, "check failed at line %d: %s\n",                   \
                __LINE__, #expression);                                      \
        return 1;                                                            \
    }                                                                        \
} while (0)

#define TEMPLATE_BITS UINT32_C(0xa5a40006)
#define GPU_BASE UINT64_C(0x700000000)

/* FNV-1a of command followed by descriptor for every
 * {descriptor[0x800].bit0, descriptor[0x418].bit0,
 * descriptor[0xb48].bit0, decision-0x2410} combination. These were produced
 * by the separate recovered-ABI Python reference encoder. */
static const uint64_t reference_hashes[16] = {
    UINT64_C(0x6cabfeb77c9ff1fd),
    UINT64_C(0x282c4f2a02c7f519),
    UINT64_C(0x7491ab191654b3ac),
    UINT64_C(0x5cf196038cbea110),
    UINT64_C(0x199f053e72e02a90),
    UINT64_C(0x5b4de52a868a3444),
    UINT64_C(0x76f7da63224818e9),
    UINT64_C(0x9d965fd57942c7ed),
    UINT64_C(0x234cdfde0a19be54),
    UINT64_C(0x298930b6716d6770),
    UINT64_C(0xde4912d2d4c7b135),
    UINT64_C(0x53cd3a872ec54cb1),
    UINT64_C(0x4ee9ed17891f0119),
    UINT64_C(0x85de7990d86d82b5),
    UINT64_C(0x8889c25a0b3dd158),
    UINT64_C(0xbb15e534477d8fbc),
};

struct fixture {
    uint8_t command[VINIX_FAKE_G17_COMMAND_BYTES];
    uint8_t descriptor[VINIX_FAKE_G17_DESCRIPTOR_BYTES];
    struct vinix_fake_g17_expected_write
        writes[VINIX_FAKE_G17_MAX_WRITES];
    struct vinix_fake_g17_encoder_inputs inputs;
};

static void write_le32(uint8_t *bytes, uint32_t value)
{
    bytes[0] = (uint8_t)value;
    bytes[1] = (uint8_t)(value >> 8);
    bytes[2] = (uint8_t)(value >> 16);
    bytes[3] = (uint8_t)(value >> 24);
}

static uint64_t fnv1a(const uint8_t *bytes, size_t size, uint64_t hash)
{
    size_t index;

    for (index = 0; index < size; index++) {
        hash ^= bytes[index];
        hash *= UINT64_C(0x100000001b3);
    }
    return hash;
}

static void initialize_fixture(struct fixture *fixture)
{
    uint32_t pass;

    memset(fixture, 0, sizeof(*fixture));
    for (pass = 0; pass < VINIX_FAKE_G17_REGISTER_PASSES; pass++) {
        uint8_t *stream = fixture->command +
            (size_t)pass * VINIX_FAKE_G17_REGISTER_STRIDE +
            VINIX_FAKE_G17_STREAM_OFFSET;
        uint32_t entry;

        for (entry = 0;
             (size_t)(entry + 1) * VINIX_FAKE_G17_ENTRY_BYTES <=
                 VINIX_FAKE_G17_STREAM_BYTES;
             entry++)
            write_le32(stream + (size_t)entry * VINIX_FAKE_G17_ENTRY_BYTES,
                       TEMPLATE_BITS);
        for (entry = 0; entry < VINIX_FAKE_G17_EXTERNAL_EVENT_COUNT; entry++)
            fixture->inputs.values[pass][entry] =
                UINT64_C(0xdead000000000000) |
                (uint64_t)pass << 16 | entry;
    }
}

static int run_branch_matrix(void)
{
    unsigned int bit_800;
    unsigned int bit_418;
    unsigned int bit_b48;
    unsigned int external_branch;

    for (bit_800 = 0; bit_800 <= 1; bit_800++) {
        for (bit_418 = 0; bit_418 <= 1; bit_418++) {
            for (bit_b48 = 0; bit_b48 <= 1; bit_b48++) {
                for (external_branch = 0; external_branch <= 1;
                     external_branch++) {
                    struct fixture fixture;
                    struct vinix_fake_g17_report report;
                    uint32_t expected_per_pass = 94 + 2 * bit_800 +
                        2 * bit_b48 - 2 * external_branch;
                    uint32_t expected_writes = 4 * expected_per_pass;
                    uint32_t branch_key = bit_800 << 3 | bit_418 << 2 |
                                          bit_b48 << 1 | external_branch;
                    uint32_t external_writes = 0;
                    uint32_t write_count = UINT32_MAX;
                    uint32_t pass;
                    uint32_t index;
                    int result;

                    initialize_fixture(&fixture);
                    fixture.descriptor[0x800] = bit_800;
                    fixture.descriptor[0x418] = bit_418;
                    fixture.descriptor[0xb48] = bit_b48;
                    for (pass = 0;
                         pass < VINIX_FAKE_G17_REGISTER_PASSES; pass++)
                        fixture.inputs.decisions[pass][0] = external_branch;

                    result = vinix_fake_g17_encode_3d(
                        fixture.command, sizeof(fixture.command),
                        fixture.descriptor, sizeof(fixture.descriptor),
                        GPU_BASE, &fixture.inputs, fixture.writes,
                        VINIX_FAKE_G17_MAX_WRITES, &write_count);
                    CHECK(result == VINIX_FAKE_G17_ENCODE_OK);
                    CHECK(write_count == expected_writes);
                    CHECK(fnv1a(
                        fixture.descriptor, sizeof(fixture.descriptor),
                        fnv1a(fixture.command, sizeof(fixture.command),
                              UINT64_C(0xcbf29ce484222325))) ==
                          reference_hashes[branch_key]);
                    for (index = 0; index < write_count; index++) {
                        const struct vinix_fake_g17_expected_write *write =
                            &fixture.writes[index];

                        CHECK(write->template_bits == TEMPLATE_BITS);
                        CHECK(write->template_mask ==
                              VINIX_FAKE_G17_TEMPLATE_MASK);
                        CHECK(write->value_mask == UINT64_MAX);
                        if ((write->value & UINT64_C(0xffff000000000000)) ==
                            UINT64_C(0xdead000000000000))
                            external_writes++;
                    }
                    CHECK(external_writes ==
                          VINIX_FAKE_G17_REGISTER_PASSES *
                          VINIX_FAKE_G17_EXTERNAL_EVENT_COUNT);
                    CHECK(vinix_fake_g17_verify(
                        fixture.command, sizeof(fixture.command),
                        fixture.descriptor, sizeof(fixture.descriptor),
                        GPU_BASE, fixture.writes, write_count, NULL, 0,
                        NULL, 0,
                        &report) == VINIX_FAKE_G17_OK);
                    CHECK(report.observed_writes == write_count);
                }
            }
        }
    }
    return 0;
}

static int run_failure_checks(void)
{
    struct fixture fixture;
    struct vinix_fake_g17_report report;
    uint32_t write_count;

    initialize_fixture(&fixture);
    write_count = UINT32_MAX;
    CHECK(vinix_fake_g17_encode_3d(
        fixture.command, sizeof(fixture.command), fixture.descriptor,
        sizeof(fixture.descriptor), GPU_BASE, &fixture.inputs,
        fixture.writes, VINIX_FAKE_G17_MAX_WRITES - 1, &write_count) ==
        VINIX_FAKE_G17_ENCODE_WRITE_CAPACITY);
    CHECK(write_count == 0);

    fixture.inputs.decisions[0][0] = 2;
    write_count = UINT32_MAX;
    CHECK(vinix_fake_g17_encode_3d(
        fixture.command, sizeof(fixture.command), fixture.descriptor,
        sizeof(fixture.descriptor), GPU_BASE, &fixture.inputs,
        fixture.writes, VINIX_FAKE_G17_MAX_WRITES, &write_count) ==
        VINIX_FAKE_G17_ENCODE_INVALID_ARGUMENT);
    CHECK(write_count == 0);

    initialize_fixture(&fixture);
    CHECK(vinix_fake_g17_encode_3d(
        fixture.command, sizeof(fixture.command), fixture.descriptor,
        sizeof(fixture.descriptor), GPU_BASE, &fixture.inputs,
        fixture.writes, VINIX_FAKE_G17_MAX_WRITES, &write_count) ==
        VINIX_FAKE_G17_ENCODE_OK);
    fixture.command[VINIX_FAKE_G17_STREAM_OFFSET] ^= 2;
    CHECK(vinix_fake_g17_verify(
        fixture.command, sizeof(fixture.command), fixture.descriptor,
        sizeof(fixture.descriptor), GPU_BASE, fixture.writes, write_count,
        NULL, 0, NULL, 0,
        &report) == VINIX_FAKE_G17_TEMPLATE_BITS);
    fixture.command[VINIX_FAKE_G17_STREAM_OFFSET] ^= 2;
    fixture.command[VINIX_FAKE_G17_STREAM_OFFSET + 4] ^= 1;
    CHECK(vinix_fake_g17_verify(
        fixture.command, sizeof(fixture.command), fixture.descriptor,
        sizeof(fixture.descriptor), GPU_BASE, fixture.writes, write_count,
        NULL, 0, NULL, 0,
        &report) == VINIX_FAKE_G17_VALUE);
    return 0;
}

static int run_dense_reference(void)
{
    struct fixture fixture;
    struct vinix_fake_g17_report report;
    uint32_t write_count = 0;
    uint32_t pass;
    uint32_t event;
    uint64_t hash;

    memset(&fixture, 1, sizeof(fixture));
    memset(&fixture.inputs, 0, sizeof(fixture.inputs));
    for (pass = 0; pass < VINIX_FAKE_G17_REGISTER_PASSES; pass++) {
        fixture.inputs.decisions[pass][0] = pass & 1;
        for (event = 0; event < VINIX_FAKE_G17_EXTERNAL_EVENT_COUNT; event++)
            fixture.inputs.values[pass][event] =
                UINT64_C(0xcafe000000000000) |
                (uint64_t)pass << 16 | event;
    }
    CHECK(vinix_fake_g17_encode_3d(
        fixture.command, sizeof(fixture.command), fixture.descriptor,
        sizeof(fixture.descriptor), GPU_BASE, &fixture.inputs,
        fixture.writes, VINIX_FAKE_G17_MAX_WRITES, &write_count) ==
        VINIX_FAKE_G17_ENCODE_OK);
    CHECK(write_count == 388);
    hash = fnv1a(fixture.descriptor, sizeof(fixture.descriptor),
                 fnv1a(fixture.command, sizeof(fixture.command),
                       UINT64_C(0xcbf29ce484222325)));
    CHECK(hash == UINT64_C(0x6bdce89bf0d9eaf1));
    CHECK(vinix_fake_g17_verify(
        fixture.command, sizeof(fixture.command), fixture.descriptor,
        sizeof(fixture.descriptor), GPU_BASE, fixture.writes, write_count,
        NULL, 0, NULL, 0, &report) == VINIX_FAKE_G17_OK);
    return 0;
}

int main(void)
{
    CHECK(vinix_fake_g17_encoder_inputs_size() ==
          sizeof(struct vinix_fake_g17_encoder_inputs));
    CHECK(VINIX_FAKE_G17_EXTERNAL_EVENT_COUNT == 5);
    CHECK(VINIX_FAKE_G17_EXTERNAL_DECISION_COUNT == 1);
    CHECK(VINIX_FAKE_G17_MAX_WRITES == 392);
    CHECK(run_branch_matrix() == 0);
    CHECK(run_dense_reference() == 0);
    CHECK(run_failure_checks() == 0);
    puts("fake G17 recovered 3D encoder tests passed");
    return 0;
}
