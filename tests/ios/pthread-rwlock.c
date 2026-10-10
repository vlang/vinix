// SPDX-License-Identifier: GPL-2.0-or-later
#include "pthread-rwlock.h"
int main(int argc,char **argv){return rwlock_checks(argc>1 && !strcmp(argv[1],"--adapter"));}
