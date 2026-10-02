/* Optional native tests use the actual V gate, IRQ timers and scheduler. */
#ifdef VINIX_ACPI_SYNC_TEST
#include "../../tests/acpi-sync/native.c"
#endif
