#ifndef VINIX_G17_ENCODER_FIXTURE_ABI_H
#define VINIX_G17_ENCODER_FIXTURE_ABI_H
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include "agx_fake_g17_encode.h"
struct vg17_encoder_fixture {
    uint8_t command[VINIX_FAKE_G17_COMMAND_BYTES];
    uint8_t descriptor[VINIX_FAKE_G17_DESCRIPTOR_BYTES];
    struct vinix_fake_g17_expected_write writes[VINIX_FAKE_G17_MAX_WRITES];
    struct vinix_fake_g17_encoder_inputs inputs;
};
_Static_assert(VINIX_FAKE_G17_COMMAND_BYTES == 0x2240, "original command extent");
_Static_assert(VINIX_FAKE_G17_DESCRIPTOR_BYTES == 0x15b0, "original descriptor extent");
_Static_assert(VINIX_FAKE_G17_MAX_WRITES == 404, "original writes extent");
_Static_assert(VINIX_FAKE_G17_REGISTER_PASSES == 4, "original pass extent");
_Static_assert(VINIX_FAKE_G17_EXTERNAL_EVENT_COUNT == 2, "original event extent");
#endif
