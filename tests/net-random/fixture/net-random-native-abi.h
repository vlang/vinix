/* Native declarations; fixture generators, callbacks and checks live in V. */
#ifndef VINIX_NET_RANDOM_FIXTURE_ABI_H
#define VINIX_NET_RANDOM_FIXTURE_ABI_H
#include <net_random.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
int nrf_port_taken(uint16_t, void *);
int nrf_single_port_taken(uint16_t, void *);
#endif
