// SPDX-License-Identifier: GPL-2.0-or-later
// Optional allocation-site diagnostics for an ALLOC_TRACK=1 kernel.
#include <stdlib.h>
#include <stdio.h>
static void start_tracking(void) {
  if (!getenv("VINIX_VENUS_ALLOC_TRACK"))
    return;
  FILE *f = fopen("/proc/allocstart", "r");
  if (f) {
    (void)fgetc(f);
    fclose(f);
  }
}
static void dump_sites(const char *label) {
  if (!getenv("VINIX_VENUS_ALLOC_TRACK"))
    return;
  FILE *f = fopen("/proc/allocsites", "r");
  if (!f)
    return;
  char line[2048];
  while (fgets(line, sizeof(line), f)) {
    if (line[0] != '#' && line[0] >= '0' && line[0] <= '9')
      printf("PERF-SITE %s %s", label, line);
  }
  fclose(f);
  fflush(stdout);
}
