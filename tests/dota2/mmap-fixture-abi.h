/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_DOTA_MMAP_FIXTURE_ABI_H
#define VINIX_DOTA_MMAP_FIXTURE_ABI_H
int vinix_dota_next_gap(unsigned long, unsigned long, unsigned long, unsigned long *);
void *fixture_mmap(void *, unsigned long, int, int, int, long);
void *fixture_mmap64(void *, unsigned long, int, int, int, long);
#endif
