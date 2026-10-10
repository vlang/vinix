// SPDX-License-Identifier: GPL-2.0-or-later
#include "pthread-mutexattr.h"
int main(int argc,char **argv) {
    return mutexattr_checks(argc>1 && !strcmp(argv[1],"--adapter"));
}
