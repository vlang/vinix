/* SPDX-License-Identifier: GPL-2.0-or-later */
#include <stdio.h>
#include <stdlib.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

int main(void) {
    setvbuf(stdout, NULL, _IONBF, 0);
    mkdir("/run", 0755); mkdir("/root/.config", 0755);
    FILE *profile = fopen("/root/.vinix-user", "w");
    if (!profile) return 1;
    fputs("version=1\nname=694f532054657374\nkdf=scrypt\nn=16384\nr=8\np=1\n"
          "salt=00112233445566778899aabbccddeeff\n"
          "hash=00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff\n", profile);
    fclose(profile); chmod("/root/.vinix-user", 0600);
    setenv("VINIX_IOS_TRACE", "1", 1);
    setenv("VINIX_SYSTEM_SESSION", "1", 1);
    pid_t child = fork();
    if (child == 0) {
        execl("/usr/bin/vinix-desktop", "vinix-desktop", "--open=iOS Calculator", (char *)NULL);
        perror("desktop exec"); _exit(127);
    }
    if (child < 0) return 1;
    int status;
    waitpid(child, &status, 0);
    printf("iOS DESKTOP FAIL: compositor exited status=%d\n", status);
    for (;;) pause();
}
