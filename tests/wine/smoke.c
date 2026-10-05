// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

#define WIN32_LEAN_AND_MEAN
#include <windows.h>

int main(void) {
    static const char marker[] = "VINIX WINE SMOKE: PASS\n";
    DWORD written = 0;
    HANDLE output = GetStdHandle(STD_OUTPUT_HANDLE);

    if (output == INVALID_HANDLE_VALUE)
        return 1;
    if (!WriteFile(output, marker, sizeof(marker) - 1, &written, NULL))
        return 1;
    return written == sizeof(marker) - 1 ? 0 : 1;
}
