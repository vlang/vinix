#include <stdio.h>
#include <unistd.h>

int main(void) {
    char buf[256];
    getcwd(buf, 256);
    printf("Hello world: %s\n", buf);
    return 0;
}
