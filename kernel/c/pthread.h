// pthread.h: POSIX thread function definitions.
// Code is governed by the GPL-2.0 license.
// Copyright (C) 2021-2022 The Vinix authors.

#ifndef _PTHREAD_H
#define _PTHREAD_H

struct __thread_data {
    void *ptr;
};

struct __threadattr {
    void *ptr;
};

typedef struct __thread_data *pthread_t;

#endif
