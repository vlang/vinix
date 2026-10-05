/* Reuse the repository's real compatibility and exceptional-return tests. */
#define main original_core_main
#include "../qemu-core/test.c"
#undef main
int main(int argc, char **argv) {
    if (argc==2 && !strcmp(argv[1],"--exec-segment-probe")) return exec_segment_probe();
    int serial = open("/dev/com1", O_WRONLY | O_NOCTTY);
    if (serial >= 0) { dup2(serial,1); dup2(serial,2); close(serial); }
    setbuf(stdout,NULL);
    pid_t worker=fork(); CHECK(worker>=0);
    if (!worker) _exit(test_x86_segments());
    CHECK(reap_ok(worker)==0);
    puts("CPU MITIGATION GUEST: PASS");
    for (;;) pause();
}
