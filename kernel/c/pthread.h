#ifndef _PTHREAD_H
#define _PTHREAD_H

typedef void *pthread_t;
typedef void *pthread_attr_t;

int pthread_create(pthread_t *thread, const pthread_attr_t *attr,
                   void *(*start_routine)(void *), void *arg);

#endif
