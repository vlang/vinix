/* Declaration-only addition to the system libarchive boundary. */
#ifndef VINIX_UPSTREAMSOURCE_ARCHIVE_EXTRA_ABI_H
#define VINIX_UPSTREAMSOURCE_ARCHIVE_EXTRA_ABI_H
#include "../hosttest/archive_abi.h"
const char *archive_entry_hardlink(struct archive_entry *);
#endif
