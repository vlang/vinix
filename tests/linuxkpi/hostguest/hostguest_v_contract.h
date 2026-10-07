#ifndef VINIX_HOST_MODEL_GUEST_V_CONTRACT_H
#define VINIX_HOST_MODEL_GUEST_V_CONTRACT_H
#include <errno.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>
int vmh_host_entry(int, char **);
#endif
