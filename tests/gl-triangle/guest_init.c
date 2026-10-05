/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Minimal native shell fixture for the existing eight-case Mesa harness. */
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
int main(void) {
    char line[4096];
    setenv("PATH","/usr/bin:/bin",1);
    for(;;) {
        fputs("\n# ",stdout);fflush(stdout);
        if(!fgets(line,sizeof(line),stdin))pause();
        else { system(line);fflush(NULL); }
    }
}
