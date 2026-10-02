#define _GNU_SOURCE
#include <cpuid.h>
#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <sched.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/syscall.h>
#include <sys/time.h>
#include <sys/wait.h>
#include <unistd.h>

#define CHECK(x) do { if (!(x)) { printf("CPU MITIGATION FAIL line %d errno %d\n", __LINE__, errno); _exit(1); } } while (0)
extern int mitigation_syscall_probe(void);
static volatile sig_atomic_t signals;
static void alarm_handler(int number) { (void)number; signals++; }
static void *worker(void *arg) {
    (void)arg;
    for (int i = 0; i < 3000; i++) {
        if (!mitigation_syscall_probe()) return (void *)(uintptr_t)1;
        if (!(i % 100)) sched_yield();
    }
    return NULL;
}
static unsigned long slab_kb(void) {
    FILE *file = fopen("/proc/meminfo", "r"); CHECK(file);
    char line[256]; unsigned long value = 0;
    while (fgets(line,sizeof(line),file)) if (sscanf(line,"Slab: %lu",&value)==1) break;
    fclose(file); CHECK(value); return value;
}
struct user_desc {
    unsigned entry_number, base_addr, limit;
    unsigned seg_32bit:1, contents:2, read_exec_only:1, limit_in_pages:1;
    unsigned seg_not_present:1, useable:1, lm:1;
};
static void segment_reload_faults(void) {
    struct user_desc desc={.entry_number=(unsigned)-1,.limit=0xfffff,
        .seg_32bit=1,.limit_in_pages=1,.useable=1};
    CHECK(syscall(SYS_set_thread_area,&desc)==0);
    unsigned short selector=(unsigned short)((desc.entry_number<<3)|3);
    __asm__ volatile("mov %0, %%ds; mov %0, %%es" :: "r"(selector):"memory");
    CHECK(mitigation_syscall_probe());
    struct user_desc empty={.entry_number=desc.entry_number,.read_exec_only=1,.seg_not_present=1};
    CHECK(syscall(SYS_set_thread_area,&empty)==0);
    unsigned short ds,es;
    __asm__ volatile("mov %%ds, %0; mov %%es, %1":"=r"(ds),"=r"(es));
    CHECK(ds==0 && es==0 && mitigation_syscall_probe());
    puts("CPU MITIGATION PASS: faulting DS and ES syscall restores recover");
}
int main(void) {
    int serial = open("/dev/com1", O_WRONLY | O_NOCTTY);
    if (serial >= 0) { dup2(serial,1); dup2(serial,2); close(serial); }
    setbuf(stdout,NULL);
    unsigned a,b,c,d,maxleaf,maxsub=0,leaf7=0,leaf72=0,amd=0;
    __cpuid(0,maxleaf,b,c,d);
    printf("CPU MITIGATION CPUID vendor=%08x:%08x:%08x max=%u\n",b,d,c,maxleaf);
    if (maxleaf>=7) {
        __cpuid_count(7,0,maxsub,b,c,leaf7);
        if (maxsub>=2) __cpuid_count(7,2,a,b,c,leaf72);
    }
    __cpuid(0x80000000,a,b,c,d);
    if (a>=0x80000008) __cpuid(0x80000008,a,amd,c,d);
    printf("CPU MITIGATION CPUID leaf7=%08x leaf7.2=%08x amd=%08x\n",leaf7,leaf72,amd);
    printf("CPU MITIGATION INITIAL SLAB %lu KiB\n",slab_kb());
    for (int i=0;i<10000;i++) CHECK(mitigation_syscall_probe());
    puts("CPU MITIGATION PASS: syscall register preservation");
    segment_reload_faults();
    struct sigaction action={0}; action.sa_handler=alarm_handler;
    CHECK(sigaction(SIGALRM,&action,NULL)==0);
    struct itimerval timer={.it_interval={.tv_usec=1000},.it_value={.tv_usec=1000}};
    CHECK(setitimer(ITIMER_REAL,&timer,NULL)==0);
    for (int i=0;i<15000;i++) CHECK(mitigation_syscall_probe());
    struct itimerval stop={0}; CHECK(setitimer(ITIMER_REAL,&stop,NULL)==0);
    CHECK(signals>0); puts("CPU MITIGATION PASS: timer interrupts and signed signal returns");
    pthread_t threads[4];
    for (int i=0;i<4;i++) CHECK(pthread_create(&threads[i],NULL,worker,NULL)==0);
    for (int i=0;i<4;i++) { void *result; CHECK(pthread_join(threads[i],&result)==0 && !result); }
    cpu_set_t original; CHECK(sched_getaffinity(0,sizeof(original),&original)==0);
    for (int cpu=0;cpu<CPU_SETSIZE;cpu++) if (CPU_ISSET(cpu,&original)) {
        cpu_set_t one; CPU_ZERO(&one); CPU_SET(cpu,&one);
        CHECK(sched_setaffinity(0,sizeof(one),&one)==0);
        for (int i=0;i<100;i++) CHECK(mitigation_syscall_probe());
    }
    CHECK(sched_setaffinity(0,sizeof(original),&original)==0);
    for (int i=0;i<40;i++) {
        pid_t child=fork(); CHECK(child>=0);
        if (!child) { for(int j=0;j<100;j++) if (!mitigation_syscall_probe()) _exit(1); _exit(0); }
        int status; CHECK(waitpid(child,&status,0)==child && WIFEXITED(status) && !WEXITSTATUS(status));
    }
    puts("CPU MITIGATION PASS: threads, CPU migration and process switches");
    unsigned long before=slab_kb();
    for (int i=0;i<30000;i++) CHECK(mitigation_syscall_probe());
    unsigned long after=slab_kb();
    printf("CPU MITIGATION RETENTION slab=%lu->%lu KiB\n",before,after);
    CHECK(after<=before+16);
    puts("CPU MITIGATION GUEST: PASS");
    for(;;) pause();
}
