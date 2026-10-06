#ifndef VINIX_G17_VERIFIER_FIXTURE_ABI_H
#define VINIX_G17_VERIFIER_FIXTURE_ABI_H
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#define VINIX_V_RUNTIME
#include "agx_fake_g17.h"
struct vg17_verifier_fixture {
    uint8_t command[VINIX_FAKE_G17_COMMAND_BYTES];
    uint8_t descriptor[VINIX_FAKE_G17_DESCRIPTOR_BYTES];
};
_Static_assert(VINIX_FAKE_G17_COMMAND_BYTES == 0x2240, "original command extent");
_Static_assert(VINIX_FAKE_G17_DESCRIPTOR_BYTES == 0x15b0, "original descriptor extent");
_Static_assert(VINIX_FAKE_G17_REGISTER_PASSES == 4, "original pass extent");
#endif
