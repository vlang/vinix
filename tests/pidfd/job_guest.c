/* SPDX-License-Identifier: GPL-2.0-or-later */
/* A bounded native job-control and retention run; guest.c retains the full suite. */
#define main pidfd_full_main
#include "guest.c"
#undef main
int main(int argc,char **argv) {
 if(argc>1) return pidfd_full_main(argc,argv);
 char *job_argv[]={"init","pidfd-job-check",0};
 return pidfd_full_main(2,job_argv);
}
