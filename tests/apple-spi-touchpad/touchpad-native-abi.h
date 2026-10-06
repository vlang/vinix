/* Native layouts and callback declarations only. */
#ifndef VINIX_SPI_TOUCHPAD_FIXTURE_ABI_H
#define VINIX_SPI_TOUCHPAD_FIXTURE_ABI_H
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
int vsf_reference_entry(void);
#include "core_fixture.h"
uint32_t vsf_touchpad_mock_read(void *, uint64_t);
void vsf_touchpad_mock_write(void *, uint64_t, uint32_t);
uint64_t vsf_touchpad_mock_now(void *);
void vsf_touchpad_mock_delay(void *, uint32_t);
_Static_assert(sizeof(int)==4 && sizeof(unsigned)==4 && sizeof(uint64_t)==8, "native SPI fixture integer widths");
#endif
