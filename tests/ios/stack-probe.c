// SPDX-License-Identifier: GPL-2.0-or-later
// Compiler-generated Darwin stack probes must preserve integer/FP arguments,
// LR and SP. The identical source also runs against the Mac reference.
#ifdef IOS_STACK_REFERENCE
#include <pthread.h>
typedef pthread_t StackThread;
#else
typedef unsigned long StackThread;
extern int pthread_create(unsigned long *,const void *,void *(*)(void *),void *);
extern int pthread_join(unsigned long,void **);
#endif
extern int puts(const char *);

__attribute__((noinline)) long large_frame(long a,long b,long c,long d,long e,long f,long g,long h,
 double p,double q,double r,double s,double t,double u,double v,double w) {
 unsigned char bytes[32768];
 // Escape the entire buffer so optimization cannot shrink the stack frame.
 __asm__ volatile("" : : "r"(bytes) : "memory");
 for(unsigned long i=0;i<sizeof bytes;i+=4096)bytes[i]=(unsigned char)(a+i/4096);
 bytes[sizeof bytes-1]=63;
 __asm__ volatile("" : : "r"(bytes) : "memory");
 long result=a+b+c+d+e+f+g+h+(long)((p+q+r+s+t+u+v+w)*2.0)+bytes[sizeof bytes-1];
 for(unsigned long i=0;i<sizeof bytes;i+=4096)result+=bytes[i];
 return result;
}

static int check(void) {
 for(int repeat=0;repeat<32;repeat++)
  if(large_frame(1,2,3,4,5,6,7,8,0.5,1.5,2.5,3.5,4.5,5.5,6.5,7.5)!=199)return 1;
 return 0;
}
static void *worker(void *context) {
 *(int *)context=check();
 return 0;
}
int main(void) {
 if(check())return 1;
 StackThread threads[8];int errors[8]={0};
 for(int i=0;i<8;i++)if(pthread_create(&threads[i],0,worker,&errors[i]))return 2;
 for(int i=0;i<8;i++)if(pthread_join(threads[i],0)||errors[i])return 3;
 puts("IOS-STACK-PROBE: 32 KiB frames, integer/FP arguments and eight native threads");
 return 0;
}
