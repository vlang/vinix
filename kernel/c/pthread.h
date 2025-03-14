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
