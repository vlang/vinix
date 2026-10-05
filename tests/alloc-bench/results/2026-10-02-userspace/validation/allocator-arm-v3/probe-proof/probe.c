#define main original_verify_main
#include "/Users/alex/code/vinix/build/useralloc-arm-v3/verify-original.c"
#undef main
int main(void) { setbuf(stdout, NULL); setbuf(stderr, NULL); alarm(30); return rejects_corruption(); }
