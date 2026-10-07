/* Native libc declarations and storage layouts only; job-control policy is V. */
#ifndef VINIX_TERMINAL_JOBS_NATIVE_ABI_H
#define VINIX_TERMINAL_JOBS_NATIVE_ABI_H
#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdint.h>
#include <stddef.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/wait.h>
#include <sys/stat.h>
#include <sys/resource.h>
#include <poll.h>
#include <time.h>
#include <termios.h>
#include <unistd.h>
struct tj_signal_word { volatile sig_atomic_t value; };
struct tj_transition_word { volatile int value; };
_Static_assert(sizeof(int)==4 && sizeof(pid_t)==4 && sizeof(sig_atomic_t)==4, "original status/signal words");
_Static_assert(sizeof(long)==8 && sizeof(size_t)==8 && sizeof(ssize_t)==8 && sizeof(intptr_t)==8 && sizeof(dev_t)==8, "original LP64 words");
_Static_assert(sizeof(struct tj_signal_word)==4 && _Alignof(struct tj_signal_word)==4 && offsetof(struct tj_signal_word,value)==0, "original volatile signal word");
_Static_assert(sizeof(struct tj_transition_word)==4 && _Alignof(struct tj_transition_word)==4 && offsetof(struct tj_transition_word,value)==0, "original volatile transition indexing");
_Static_assert(sizeof(pthread_t)==8 && _Alignof(pthread_t)==8, "original joined worker handle");
_Static_assert(sizeof(sigset_t)==128 && sizeof(struct sigaction)==152 && _Alignof(struct sigaction)==8, "native signal records");
_Static_assert(sizeof(struct timespec)==16 && _Alignof(struct timespec)==8, "native grace timestamps");
_Static_assert(sizeof(struct termios)==60 && sizeof(((struct termios *)0)->c_lflag)==4 && sizeof(((struct termios *)0)->c_cc)==32, "native termios flags and control array");
_Static_assert(sizeof(struct rlimit)==16 && _Alignof(struct rlimit)==8 && sizeof(((struct rlimit *)0)->rlim_cur)==8, "native descriptor limit");
_Static_assert(sizeof(struct pollfd)==8 && _Alignof(struct pollfd)==4, "native poll record");
_Static_assert(__builtin_types_compatible_p(int32_t,int) && __builtin_types_compatible_p(sig_atomic_t,int) && __builtin_types_compatible_p(pid_t,int), "native signal/process/status nominal types");
_Static_assert(__builtin_types_compatible_p(int64_t,long) && __builtin_types_compatible_p(intptr_t,long) && __builtin_types_compatible_p(ssize_t,long) && __builtin_types_compatible_p(time_t,long), "native long variadic timestamps/counts");
_Static_assert(__builtin_types_compatible_p(uint32_t,unsigned int) && __builtin_types_compatible_p(mode_t,unsigned int) && __builtin_types_compatible_p(tcflag_t,unsigned int), "native unsigned flag words");
_Static_assert(__builtin_types_compatible_p(uint64_t,unsigned long) && __builtin_types_compatible_p(dev_t,unsigned long) && __builtin_types_compatible_p(nfds_t,unsigned long), "native unsigned long device/poll words");
_Static_assert(offsetof(struct sigaction,sa_handler)==0 && offsetof(struct sigaction,sa_mask)==8 && offsetof(struct sigaction,sa_flags)==136, "native signal fields");
_Static_assert(offsetof(struct timespec,tv_sec)==0 && offsetof(struct timespec,tv_nsec)==8, "native timestamp fields");
_Static_assert(offsetof(struct termios,c_lflag)==12 && offsetof(struct termios,c_cc)==17, "native terminal fields");
_Static_assert(__builtin_types_compatible_p(rlim_t,unsigned long long), "native limit fields retain nominal unsigned long long inside the foreign struct");
_Static_assert(offsetof(struct rlimit,rlim_cur)==0 && offsetof(struct rlimit,rlim_max)==8, "native limit fields");
_Static_assert(offsetof(struct pollfd,fd)==0 && offsetof(struct pollfd,events)==4 && offsetof(struct pollfd,revents)==6, "native polling fields");
#if defined(__aarch64__)
_Static_assert(sizeof(struct stat)==128 && offsetof(struct stat,st_mode)==16 && offsetof(struct stat,st_rdev)==32, "native ARM stat fields");
#elif defined(__x86_64__)
_Static_assert(sizeof(struct stat)==144 && offsetof(struct stat,st_mode)==24 && offsetof(struct stat,st_rdev)==40, "native x86 stat fields");
#else
#error This independent fixture supports the two kernel LP64 architectures.
#endif
void vinix_terminal_acquire_foreground(int);
void vinix_terminal_caught(int);
void vinix_terminal_transition_signal(int);
void *vinix_terminal_race_open(void *);
#endif
