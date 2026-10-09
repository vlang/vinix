#define _GNU_SOURCE
#include <errno.h>
#include <pthread.h>
#include <sched.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <signal.h>
#include <string.h>
#include <sys/eventfd.h>
#include <sys/mman.h>
#include <sys/prctl.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

enum { LOCK_PI=6, UNLOCK_PI=7, TRYLOCK_PI=8, LOCK_PI2=13, PRIVATE=128 };
#define WAITERS UINT32_C(0x80000000)
#define OWNER_DIED UINT32_C(0x40000000)
#define CHECK(x) do { if (!(x)) { printf("SCHED-QOS FAIL line=%d errno=%d\n", __LINE__, errno); _exit(1); } } while (0)
static uint64_t now(void) {
    struct timespec t; CHECK(!clock_gettime(CLOCK_MONOTONIC, &t));
    return (uint64_t)t.tv_sec * 1000000000 + t.tv_nsec;
}
static void until(atomic_int *word, int value) {
    uint64_t end=now()+UINT64_C(60000000000);
    while (atomic_load(word)<value) { CHECK(now()<end); usleep(1000); }
}
static void pin(int cpu, int priority) {
    cpu_set_t set; CPU_ZERO(&set); CPU_SET(cpu,&set);
    CHECK(!sched_setaffinity(0,sizeof set,&set));
    struct sched_param p={.sched_priority=priority};
    CHECK(!syscall(SYS_sched_setscheduler,0,priority?SCHED_FIFO:SCHED_OTHER,&p));
}
static int pi(atomic_uint *word, int operation, const struct timespec *deadline) {
    return syscall(SYS_futex,word,operation|PRIVATE,0,deadline,NULL,0);
}
static atomic_uint lock_a,lock_b;
static atomic_int ready,low_go,medium_go,high_go,release_owner,completed,stop_busy;
static atomic_ullong low_heartbeat;
static int nested;
static void *low(void *unused) {
    (void)unused; pin(1,10); ready++;
    while (!low_go) usleep(1000);
    CHECK(!pi(&lock_a,LOCK_PI,NULL));
    ready++;
    while (!release_owner) atomic_fetch_add_explicit(&low_heartbeat,1,memory_order_relaxed);
    CHECK(!pi(&lock_a,UNLOCK_PI,NULL));
    return NULL;
}
static void *middle(void *unused) {
    (void)unused; pin(1,30); ready++;
    while (!medium_go) usleep(1000);
    CHECK(!pi(&lock_b,LOCK_PI,NULL));
    CHECK(!pi(&lock_a,LOCK_PI,NULL));
    CHECK(!pi(&lock_a,UNLOCK_PI,NULL));
    CHECK(!pi(&lock_b,UNLOCK_PI,NULL));
    return NULL;
}
static void *medium(void *unused) {
    (void)unused; pin(1,50); ready++;
    while (!(nested?high_go:medium_go)) usleep(1000);
    while (!stop_busy) atomic_signal_fence(memory_order_seq_cst);
    return NULL;
}
static void *high(void *unused) {
    (void)unused; pin(1,80); ready++;
    while (!high_go) usleep(1000);
    atomic_uint *word=nested?&lock_b:&lock_a;
    CHECK(!pi(word,LOCK_PI,NULL));
    CHECK(!pi(word,UNLOCK_PI,NULL));
    completed=1;
    return NULL;
}
static void wait_contended(atomic_uint *word) {
    uint64_t end=now()+UINT64_C(60000000000);
    while (!(atomic_load(word)&WAITERS)) { CHECK(now()<end); usleep(1000); }
}
static void inversion(int chain) {
    nested=chain; ready=0;low_go=0;medium_go=0;high_go=0;release_owner=0;completed=0;stop_busy=0;
    lock_a=0;lock_b=0;low_heartbeat=0;
    pthread_t a,b,c,d;
    CHECK(!pthread_create(&a,NULL,low,NULL));
    CHECK(!pthread_create(&b,NULL,chain?middle:medium,NULL));
    CHECK(!pthread_create(&c,NULL,high,NULL));
    if(chain) CHECK(!pthread_create(&d,NULL,medium,NULL));
    until(&ready,chain?4:3);low_go=1;until(&ready,chain?5:4);
    medium_go=1;
    if (chain) wait_contended(&lock_a); else usleep(10000);
    high_go=1;wait_contended(chain?&lock_b:&lock_a);
    uint64_t started=now();release_owner=1;until(&completed,1);
    printf("SCHED-QOS PI nested=%d handoff_ns=%llu\n",chain,(unsigned long long)(now()-started));
    stop_busy=1;
    CHECK(!pthread_join(a,NULL));CHECK(!pthread_join(b,NULL));CHECK(!pthread_join(c,NULL));
    if(chain) CHECK(!pthread_join(d,NULL));
    CHECK(!lock_a&&!lock_b);
}
static atomic_int held,leave_owner;
static void *abandon(void *unused) {
    (void)unused;pin(1,0);CHECK(!pi(&lock_a,LOCK_PI,NULL));held=1;
    while (!leave_owner) usleep(1000);
    return NULL;
}
static void *die_later(void *unused) {
    (void)unused; usleep(30000);leave_owner=1;return NULL;
}
static void pi_errors_and_death(void) {
    lock_a=0;
    CHECK(!pi(&lock_a,TRYLOCK_PI,NULL));
    errno=0;CHECK(pi(&lock_a,LOCK_PI,NULL)==-1&&errno==EDEADLK);
    CHECK(!pi(&lock_a,UNLOCK_PI,NULL));
    errno=0;CHECK(pi(&lock_a,UNLOCK_PI,NULL)==-1&&errno==EPERM);
    errno=0;CHECK(pi((atomic_uint *)1,LOCK_PI,NULL)==-1&&errno==EINVAL);
    errno=0;CHECK(pi((atomic_uint *)4096,LOCK_PI,NULL)==-1&&errno==EFAULT);
    atomic_uint *shared=mmap(NULL,4096,PROT_READ|PROT_WRITE,MAP_SHARED|MAP_ANONYMOUS,-1,0);
    CHECK(shared!=MAP_FAILED);errno=0;CHECK(pi(shared,LOCK_PI,NULL)==-1&&errno==ENOTSUP);CHECK(!munmap(shared,4096));
    held=0;leave_owner=0;pthread_t owner,killer;
    CHECK(!pthread_create(&owner,NULL,abandon,NULL));until(&held,1);
    errno=0;CHECK(pi(&lock_a,TRYLOCK_PI,NULL)==-1&&errno==EAGAIN);
    uint64_t deadline=now()+UINT64_C(10000000);
    struct timespec ts={(time_t)(deadline/1000000000),(long)(deadline%1000000000)};
    errno=0;CHECK(pi(&lock_a,LOCK_PI2,&ts)==-1&&errno==ETIMEDOUT);
    CHECK(!pthread_create(&killer,NULL,die_later,NULL));
    CHECK(!pi(&lock_a,LOCK_PI,NULL));CHECK(atomic_load(&lock_a)&OWNER_DIED);
    atomic_fetch_and(&lock_a,~OWNER_DIED);CHECK(!pi(&lock_a,UNLOCK_PI,NULL));
    CHECK(!pthread_join(owner,NULL));CHECK(!pthread_join(killer,NULL));
    puts("SCHED-QOS PI timeout-owner-death-errors PASS");
}

static void quiet_signal(int sig) { (void)sig; }
static atomic_int contender_started,contender_done;
static void *interrupted_contender(void *unused) {
    (void)unused;pin(1,80);contender_started=1;
    errno=0;CHECK(pi(&lock_a,LOCK_PI,NULL)==-1&&errno==EINTR);
    contender_done=1;return NULL;
}
static void pi_interrupt(void) {
    struct sigaction action={.sa_handler=quiet_signal};sigemptyset(&action.sa_mask);
    CHECK(!sigaction(SIGUSR1,&action,NULL));lock_a=0;held=0;leave_owner=0;
    contender_started=0;contender_done=0;pthread_t owner,waiter;
    CHECK(!pthread_create(&owner,NULL,abandon,NULL));until(&held,1);
    CHECK(!pthread_create(&waiter,NULL,interrupted_contender,NULL));until(&contender_started,1);
    wait_contended(&lock_a);CHECK(!pthread_kill(waiter,SIGUSR1));until(&contender_done,1);
    CHECK(!pthread_join(waiter,NULL));leave_owner=1;CHECK(!pthread_join(owner,NULL));
    // No live waiter remains, so this uncontended word is recovered by the
    // robust protocol only when registered. Start the next case with zero.
    lock_a=0;puts("SCHED-QOS PI interrupt-withdrawal PASS");
}
struct retirement { atomic_int ready,done;atomic_int survivor;atomic_uint *word;int mode; };
static void *claimed_owner(void *arg) {
    struct retirement *r=arg;pin(1,0);CHECK(!pi(r->word,LOCK_PI,NULL));r->ready=1;
    for(;;) atomic_signal_fence(memory_order_seq_cst);
    return NULL;
}
static int surviving_waiter(void *arg) {
    struct retirement *r=arg;
    CHECK(!pi(r->word,LOCK_PI,NULL));CHECK(atomic_load(r->word)&OWNER_DIED);
    atomic_fetch_and(r->word,~OWNER_DIED);CHECK(!pi(r->word,UNLOCK_PI,NULL));r->done=1;
    return 0;
}
static void pi_retirement(void) {
    for(int mode=0;mode<2;mode++) {
        struct retirement *r=mmap(NULL,4096,PROT_READ|PROT_WRITE,MAP_SHARED|MAP_ANONYMOUS,-1,0);CHECK(r!=MAP_FAILED);
        pid_t owner=fork();CHECK(owner>=0);
        if(!owner) {
            r->word=mmap(NULL,4096,PROT_READ|PROT_WRITE,MAP_PRIVATE|MAP_ANONYMOUS,-1,0);CHECK(r->word!=MAP_FAILED);
            char *stack=mmap(NULL,1024*1024,PROT_READ|PROT_WRITE,MAP_PRIVATE|MAP_ANONYMOUS,-1,0);CHECK(stack!=MAP_FAILED);
            if(mode) { pthread_t thread;CHECK(!pthread_create(&thread,NULL,claimed_owner,r));until(&r->ready,1); }
            else CHECK(!pi(r->word,LOCK_PI,NULL));
            int survivor=clone(surviving_waiter,stack+1024*1024,CLONE_VM|SIGCHLD,r);CHECK(survivor>0);r->survivor=survivor;
            wait_contended(r->word);
            char *argv[]={"/sbin/init","--exec-ok",NULL};execv(argv[0],argv);_exit(95);
        }
        int status;CHECK(waitpid(owner,&status,0)==owner&&status==0);until(&r->done,1);
        CHECK(waitpid(r->survivor,&status,0)==r->survivor&&status==0);
        CHECK(!munmap(r,4096));
        printf("SCHED-QOS PI retirement forced=%d PASS\n",mode);
    }
}

static int pi_retry(atomic_uint *word,int op) {
    for(int i=0;i<1024;i++) { int rc=pi(word,op,NULL);if(!rc||errno!=EAGAIN)return rc; }
    return -1;
}
static atomic_uint *paged_word;
static atomic_int pageout_stop,pageout_ready,pageout_waiting;
static void *pageout_worker(void *unused) {
    (void)unused;pin(2,0);pageout_ready=1;
    for(int i=0;i<2048&&!pageout_stop;i++) { CHECK(!madvise(paged_word,4096,21));sched_yield(); }
    return NULL;
}
static void *pageout_contender(void *unused) {
    (void)unused;pin(1,0);pageout_waiting=1;
    CHECK(!pi_retry(paged_word,LOCK_PI));CHECK(!pi_retry(paged_word,UNLOCK_PI));return NULL;
}
static void pi_pageout(void) {
    paged_word=mmap(NULL,4096,PROT_READ|PROT_WRITE,MAP_PRIVATE|MAP_ANONYMOUS,-1,0);CHECK(paged_word!=MAP_FAILED);
    puts("SCHED-QOS PI pageout START");
    pageout_stop=0;pageout_ready=0;pthread_t pager;CHECK(!pthread_create(&pager,NULL,pageout_worker,NULL));until(&pageout_ready,1);
    for(int i=0;i<64;i++) {
        CHECK(!pi_retry(paged_word,LOCK_PI));pageout_waiting=0;pthread_t contender;
        CHECK(!pthread_create(&contender,NULL,pageout_contender,NULL));until(&pageout_waiting,1);wait_contended(paged_word);
        CHECK(!pi_retry(paged_word,UNLOCK_PI));CHECK(!pthread_join(contender,NULL));
        if(i%16==15)printf("SCHED-QOS PI pageout rounds=%d\n",i+1);
    }
    pageout_stop=1;CHECK(!pthread_join(pager,NULL));CHECK(!munmap(paged_word,4096));
    puts("SCHED-QOS PI concurrent-pageout PASS");
}

struct slab { unsigned long bytes,objects; };
static int slabs(struct slab *out) {
    FILE *f=fopen("/proc/slabinfo","r");CHECK(f!=NULL);char line[256];int n=0;
    while(fgets(line,sizeof line,f)) {
        unsigned long size,total,used;
        if(sscanf(line,"size-%lu %*u %lu %lu",&size,&used,&total)==3) {
            CHECK(n<32);out[n++]=(struct slab){size,used};
        }
    }
    fclose(f);return n;
}
static void donation_retention(void) {
    struct slab before[32],after[32];
    inversion(1);sleep(7);int n=slabs(before);CHECK(n>0);
    for(int batch=0;batch<2;batch++) {
        for(int i=0;i<16;i++)inversion(i&1);
        sleep(7);CHECK(slabs(after)==n);
        for(int i=0;i<n;i++) {
            long delta=(long)after[i].objects-(long)before[i].objects;
            printf("SCHED-QOS SLAB batch=%d class=%lu delta=%ld\n",batch+1,after[i].bytes,delta);
            CHECK(delta<=2);
        }
        memcpy(before,after,sizeof before);
    }
    puts("SCHED-QOS donation-retention PASS");
}

struct attr {
    uint32_t size,policy;uint64_t flags;int32_t nice;uint32_t priority;
    uint64_t runtime,deadline,period;uint32_t util_min,util_max;
};
static void qos_and_slack(void) {
    struct attr a={.size=sizeof a,.flags=0x60,.util_min=512,.util_max=800};
    CHECK(!syscall(SYS_sched_setattr,0,&a,0));
    struct attr b={0};CHECK(!syscall(SYS_sched_getattr,0,&b,sizeof b,0));CHECK(b.util_min==512&&b.util_max==800);
    struct sched_param p={0};CHECK(!syscall(SYS_sched_setscheduler,0,SCHED_OTHER,&p));
    CHECK(!syscall(SYS_sched_getattr,0,&b,sizeof b,0));CHECK(b.util_min==512&&b.util_max==800);
    a.util_min=900;errno=0;CHECK(syscall(SYS_sched_setattr,0,&a,0)==-1&&errno==EINVAL);
    a.util_min=0;a.util_max=1025;errno=0;CHECK(syscall(SYS_sched_setattr,0,&a,0)==-1&&errno==EINVAL);
    a.util_min=UINT32_MAX;a.util_max=UINT32_MAX;CHECK(!syscall(SYS_sched_setattr,0,&a,0));
    CHECK(!syscall(SYS_sched_getattr,0,&b,48,0));CHECK(b.size==48);
    CHECK(!prctl(PR_SET_TIMERSLACK,UINT64_C(500000),0,0,0));CHECK(prctl(PR_GET_TIMERSLACK,0,0,0,0)==500000);
    a.util_min=512;a.util_max=800;CHECK(!syscall(SYS_sched_setattr,0,&a,0));
    pid_t child=fork();CHECK(child>=0);if(!child) { char *argv[]={"/sbin/init","--exec-hints",NULL};execv(argv[0],argv);_exit(96); }
    int status;CHECK(waitpid(child,&status,0)==child&&status==0);
    a.util_min=UINT32_MAX;a.util_max=UINT32_MAX;CHECK(!syscall(SYS_sched_setattr,0,&a,0));
    CHECK(!prctl(PR_SET_TIMERSLACK,0,0,0,0));CHECK(prctl(PR_GET_TIMERSLACK,0,0,0,0)==50000);
    for(int i=0;i<50;i++) { uint64_t start=now();struct timespec sleep={0,300000};CHECK(!nanosleep(&sleep,NULL));CHECK(now()-start>=300000); }
    puts("SCHED-QOS hints-legacy-ABI-timer-slack PASS");
}

enum { PROCESSES=20, WORKERS=30 };
struct cohort { atomic_int ready,go;atomic_ullong work; };
static struct cohort *cohort;
static void *churn(void *unused) {
    (void)unused;atomic_fetch_add(&cohort->ready,1);
    while(!cohort->go) sched_yield();
    for(int i=0;i<40;i++) {
        int fd=eventfd(0,EFD_CLOEXEC);CHECK(fd>=0);CHECK(!close(fd));
        atomic_fetch_add(&cohort->work,1);sched_yield();
    }
    return NULL;
}
static void scalable_queue(void) {
    cohort=mmap(NULL,4096,PROT_READ|PROT_WRITE,MAP_SHARED|MAP_ANONYMOUS,-1,0);CHECK(cohort!=MAP_FAILED);
    pid_t children[PROCESSES];uint64_t start=now();
    for(int i=0;i<PROCESSES;i++) {
        children[i]=fork();CHECK(children[i]>=0);
        if(!children[i]) {
            cpu_set_t set;CPU_ZERO(&set);for(int c=0;c<4;c++)CPU_SET(c,&set);CHECK(!sched_setaffinity(0,sizeof set,&set));
            pthread_attr_t attr;CHECK(!pthread_attr_init(&attr));CHECK(!pthread_attr_setstacksize(&attr,65536));
            pthread_t workers[WORKERS];for(int j=0;j<WORKERS;j++) { int error=pthread_create(&workers[j],&attr,churn,NULL);if(error)printf("SCHED-QOS create process=%d worker=%d error=%d ready=%d\n",i,j,error,atomic_load(&cohort->ready));CHECK(!error); }
            for(int j=0;j<WORKERS;j++)CHECK(!pthread_join(workers[j],NULL));
            _exit(0);
        }
    }
    until(&cohort->ready,PROCESSES*WORKERS);cohort->go=1;
    for(int i=0;i<PROCESSES;i++) { int status;CHECK(waitpid(children[i],&status,0)==children[i]&&status==0); }
    CHECK(cohort->work==PROCESSES*WORKERS*40);
    printf("SCHED-QOS queue runnable=%d operations=%llu elapsed_ns=%llu PASS\n",PROCESSES*WORKERS,
        (unsigned long long)cohort->work,(unsigned long long)(now()-start));
    CHECK(!munmap(cohort,4096));
}
int main(int argc,char **argv) {
    if(argc>1&&!strcmp(argv[1],"--exec-ok"))return 0;
    if(argc>1&&!strcmp(argv[1],"--exec-hints")) { struct attr a={0};CHECK(!syscall(SYS_sched_getattr,0,&a,sizeof a,0));CHECK(a.util_min==512&&a.util_max==800);CHECK(prctl(PR_GET_TIMERSLACK,0,0,0,0)==500000);return 0; }
    setvbuf(stdout,NULL,_IONBF,0);puts("SCHED-QOS START");pin(0,0);
    qos_and_slack();pi_errors_and_death();pi_interrupt();pi_retirement();
    for(int i=0;i<8;i++) { inversion(0);inversion(1); }
#ifndef SCHED_QOS_SMALL
    pi_pageout();donation_retention();scalable_queue();
#else
    (void)scalable_queue;(void)donation_retention;(void)pi_pageout;
#endif
    puts("SCHED-QOS PASS");for(;;)pause();
}
