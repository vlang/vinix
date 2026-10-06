/* SPDX-License-Identifier: ISC */
#ifndef VINIX_WIFI_PROTOCOL_NATIVE_ABI_H
#define VINIX_WIFI_PROTOCOL_NATIVE_ABI_H
#include <assert.h>
#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include "brcm_wifi.h"
typedef void (*wifi_protocol_receive_fn)(void *, const uint8_t *, size_t);
uint32_t wifi_protocol_read(void *, uint32_t, uint32_t, uint32_t);
void wifi_protocol_write(void *, uint32_t, uint32_t, uint32_t, uint32_t);
uint64_t wifi_protocol_time(void *);
void wifi_protocol_delay(void *, uint32_t);
void wifi_protocol_sync(void *, void *, size_t, int32_t);
void wifi_protocol_stop(void *);
void wifi_protocol_receive(void *, bw_const_byte *, size_t);
_Static_assert(__builtin_types_compatible_p(__typeof__(((struct bw_ops *)0)->receive), wifi_protocol_receive_fn), "original const receive callback type");
_Static_assert(sizeof(((struct bw_ops *)0)->receive) == sizeof(wifi_protocol_receive_fn), "native receive callback width");
#endif
