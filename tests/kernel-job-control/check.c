#define _GNU_SOURCE
#ifndef JOB_FORK_ONLY
#define JOB_FORK_ONLY 0
#endif
#ifndef JOB_CYCLES_ONLY
#define JOB_CYCLES_ONLY 0
#endif
#ifndef JOB_TEARDOWN_ONLY
#define JOB_TEARDOWN_ONLY 0
#endif
#ifndef JOB_DETACHED_CHURN
#define JOB_DETACHED_CHURN 0
#endif
#ifndef JOB_TEARDOWN_PROCESSES
#define JOB_TEARDOWN_PROCESSES 30
#endif
#ifndef JOB_TEARDOWN_BATCHES
#define JOB_TEARDOWN_BATCHES 2
#endif
// x86 currently reserves two 2 MiB kernel stacks per thread. Stay below the
// 256 MiB creator ceiling while still exceeding 32 simultaneous waiters.
#if defined(__x86_64__)
#define JOB_WAITERS 48
#define JOB_WORKERS 48
#else
#define JOB_WAITERS 70
#define JOB_WORKERS 64
#endif
#include <errno.h>
#include <limits.h>
#include <pthread.h>
#include <sched.h>
#include <signal.h>
#define atomic_load(p) __atomic_load_n((p), __ATOMIC_ACQUIRE)
#define atomic_store(p,v) __atomic_store_n((p),(v),__ATOMIC_RELEASE)
#define atomic_fetch_add(p,v) __atomic_fetch_add((p),(v),__ATOMIC_RELAXED)
#define atomic_fetch_add_explicit(p,v,m) __atomic_fetch_add((p),(v),(m))
#define memory_order_relaxed __ATOMIC_RELAXED
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ipc.h>
#include <sys/mman.h>
#include <sys/msg.h>
#include <sys/prctl.h>
#include <sys/reboot.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

static int failures;
struct shared { unsigned long loops[4], admission_retries; int command, seen_usr, seen_cont, seen_tstp;
               int orphan_hups[40], orphan_conts[40]; };
static struct shared *state;
static void check(int ok, const char *name) {
 printf("JOB-CHECK %s %s\n", ok ? "PASS" : "FAIL", name);
 if (!ok) failures++;
}
static void handler(int sig) {
 if (sig == SIGUSR1) atomic_fetch_add(&state->seen_usr, 1);
 if (sig == SIGCONT) atomic_fetch_add(&state->seen_cont, 1);
 if (sig == SIGTSTP) atomic_fetch_add(&state->seen_tstp, 1);
}
static void *loop(void *index) {
 uintptr_t slot = (uintptr_t)index;
 for (;;) atomic_fetch_add_explicit(&state->loops[slot], 1, memory_order_relaxed);
 return NULL;
}
static pid_t start_loop(int mode) {
 memset(state, 0, sizeof(*state));
 int pipefd[2]; if (pipe(pipefd)) return -1;
 pid_t child = fork();
 if (!child) {
  close(pipefd[0]);
  struct sigaction act = {.sa_handler=handler}; sigemptyset(&act.sa_mask);
  sigaction(SIGUSR1, &act, NULL);
  if (mode == 1) {
   sigaction(SIGCONT, &act, NULL);
   sigset_t mask; sigemptyset(&mask); sigaddset(&mask, SIGCONT); sigprocmask(SIG_BLOCK, &mask, NULL);
  }
  if (mode == 2) signal(SIGTSTP, SIG_IGN);
  if (mode == 3) sigaction(SIGTSTP, &act, NULL);
  pthread_t threads[3];
  for (uintptr_t i=1; i<4; ++i) if (pthread_create(&threads[i-1], NULL, loop, (void *)i)) _exit(90);
  write(pipefd[1], "r", 1); close(pipefd[1]);
  for (;;) {
   atomic_fetch_add_explicit(&state->loops[0], 1, memory_order_relaxed);
   int command = atomic_load(&state->command);
   if (command == 1) {
    sigset_t mask; sigemptyset(&mask); sigaddset(&mask, SIGCONT); sigprocmask(SIG_UNBLOCK, &mask, NULL);
    atomic_store(&state->command, 0);
   }
   if (command == 2) _exit(0);
  }
 }
 close(pipefd[1]); char c=0; int ready=read(pipefd[0], &c, 1); close(pipefd[0]);
 if (ready != 1) { kill(child, SIGKILL); waitpid(child, NULL, 0); return -1; }
 return child;
}
static int stopped(pid_t child, int sig) {
 int status=0;
 return waitpid(child, &status, WUNTRACED) == child && WIFSTOPPED(status) && WSTOPSIG(status) == sig;
}
static void stop_continue(void) {
 pid_t child=start_loop(1);
 check(child>0, "start four CPU-loop siblings");
 kill(child, SIGSTOP);
 siginfo_t info={0};
 check(waitid(P_PID, child, &info, WSTOPPED|WNOWAIT)==0 && info.si_pid==child &&
       info.si_code==CLD_STOPPED && info.si_status==SIGSTOP, "waitid reports group stop with WNOWAIT");
 info=(siginfo_t){0};
 check(waitid(P_PID, child, &info, WSTOPPED|WNOWAIT)==0 && info.si_code==CLD_STOPPED,
       "WNOWAIT preserves stop event");
 errno=0;
 check(syscall(SYS_wait4, child, UINTPTR_MAX, WUNTRACED, NULL)==-1 && errno==EFAULT,
       "faulted stop copy preserves wait event");
 check(stopped(child, SIGSTOP), "waitpid WUNTRACED reports uncatchable SIGSTOP");
 unsigned long counts[4]; for(int i=0;i<4;i++) counts[i]=atomic_load(&state->loops[i]);
 usleep(100000);
 int all=1; for(int i=0;i<4;i++) all &= counts[i]==atomic_load(&state->loops[i]);
 check(all, "stop status waits until every live thread parks");
 kill(child, SIGUSR1); usleep(30000);
 check(!atomic_load(&state->seen_usr), "ordinary pending handler stays deferred while stopped");
 info=(siginfo_t){0};
 check(waitid(P_PID, child, &info, WEXITED|WNOHANG)==0 && !info.si_pid,
       "WEXITED does not consume stop state");
 kill(child, SIGCONT);
 int status=0;
 check(waitpid(child, &status, WCONTINUED)==child && WIFCONTINUED(status),
       "blocked SIGCONT resumes group and reports continued status");
 usleep(40000);
 check(atomic_load(&state->loops[0])>counts[0] && !atomic_load(&state->seen_cont) &&
       atomic_load(&state->seen_usr), "resume keeps blocked CONT pending and delivers other handler");
 atomic_store(&state->command, 1); usleep(40000);
 check(atomic_load(&state->seen_cont)==1, "unblocking SIGCONT delivers caught handler once");
 kill(child, SIGSTOP); check(stopped(child,SIGSTOP), "group can stop again after continue");
 kill(child, SIGKILL);
 check(waitpid(child, &status, 0)==child && WIFSIGNALED(status) && WTERMSIG(status)==SIGKILL,
       "SIGKILL tears down every stopped sibling");
}
static void dispositions(void) {
 for(int mode=2;mode<=3;mode++) {
  pid_t child=start_loop(mode); kill(child,SIGTSTP); usleep(40000);
  int status=0;
  check(waitpid(child,&status,WUNTRACED|WNOHANG)==0 &&
        (mode==2 || atomic_load(&state->seen_tstp)==1),
        mode==2 ? "ignored SIGTSTP never stops group" : "caught SIGTSTP invokes handler without stopping group");
  kill(child,SIGSTOP); check(stopped(child,SIGSTOP), "SIGSTOP bypasses catchable stop disposition");
  kill(child,SIGCONT); siginfo_t info={0};
  check(waitid(P_PID,child,&info,WCONTINUED|WNOWAIT)==0 && info.si_code==CLD_CONTINUED &&
        info.si_status==SIGCONT, "waitid CLD_CONTINUED ABI status");
  int result=waitpid(child,&status,WCONTINUED);
  check(result==child && status==0xffff, "waitpid consumes preserved continue event");
  atomic_store(&state->command,2); waitpid(child,&status,0);
 }
}
static void blocking_ipc(void) {
 int queue=msgget(IPC_PRIVATE,0600); int p[2]; pipe(p);
 pid_t child=fork();
 if (!child) { close(p[0]); write(p[1],"r",1); close(p[1]); struct {long kind;char text;} message;
  if(msgrcv(queue,&message,1,0,0)!=1 || message.text!='x') { _exit(1); }
  _exit(0); }
 close(p[1]);char c;read(p[0],&c,1);close(p[0]);usleep(20000);
 kill(child,SIGSTOP);check(stopped(child,SIGSTOP), "blocked message receiver reaches group-stop boundary");
 kill(child,SIGCONT);struct {long kind;char text;} msg={1,'x'};msgsnd(queue,&msg,1,0);
 int status=0;check(waitpid(child,&status,0)==child && WIFEXITED(status) && !WEXITSTATUS(status),
                  "continued blocked message receiver restarts without losing message");
 msgctl(queue,IPC_RMID,NULL);
}
static void orphan_default_stops(void) {
 pid_t child=start_loop(0);unsigned long before=atomic_load(&state->loops[0]);
 kill(child,SIGTSTP);kill(child,SIGTTIN);kill(child,SIGTTOU);usleep(40000);
 int status=0;pid_t got=waitpid(child,&status,WUNTRACED|WNOHANG);
 check(got==0 && atomic_load(&state->loops[0])>before,"orphaned group ignores default catchable stop signals");
 if(got==child && WIFSTOPPED(status)){kill(child,SIGCONT);waitpid(child,&status,WCONTINUED);}
 kill(child,SIGSTOP);check(stopped(child,SIGSTOP),"orphaned group still honors SIGSTOP");
 kill(child,SIGKILL);waitpid(child,NULL,0);
 pid_t parent=fork();
 if(!parent){pid_t job=fork();if(!job){for(;;)pause();}setpgid(job,job);
  int good=kill(job,SIGTSTP)==0 && stopped(job,SIGTSTP);kill(job,SIGCONT);waitpid(job,&status,WCONTINUED);
  kill(job,SIGKILL);waitpid(job,NULL,0);_exit(good?0:1);}
 check(waitpid(parent,&status,0)==parent && WIFEXITED(status) && !WEXITSTATUS(status),
       "non-orphaned group honors default SIGTSTP");
}

static void process_groups(void) {
 pid_t first=fork();if(!first){for(;;)pause();}
 int setup=setpgid(first,first)==0;
 pid_t second=fork();if(!second){for(;;)pause();}
 setup &= setpgid(second,first)==0;
 check(setup,"create sibling job process group");
 kill(-first,SIGSTOP);int status=0;pid_t a=waitpid(-first,&status,WUNTRACED);
 int ok=(a==first || a==second) && WIFSTOPPED(status) && WSTOPSIG(status)==SIGSTOP;
 pid_t b=waitpid(-first,&status,WUNTRACED);
 ok &= b!=a && (b==first || b==second) && WIFSTOPPED(status);
 check(ok,"group-directed SIGSTOP and wait group selection cover every process");
 kill(-first,SIGCONT);a=waitpid(-first,&status,WCONTINUED);ok=WIFCONTINUED(status);
 b=waitpid(-first,&status,WCONTINUED);ok &= a!=b && WIFCONTINUED(status);
 check(ok,"group-directed SIGCONT publishes distinct continuation events");
 kill(-first,SIGKILL);waitpid(first,NULL,0);waitpid(second,NULL,0);
}

static int orphan_slot;
static void orphan_handler(int sig) {
 if(sig==SIGHUP)atomic_fetch_add(&state->orphan_hups[orphan_slot],1);
 if(sig==SIGCONT)atomic_fetch_add(&state->orphan_conts[orphan_slot],1);
}
static int process_is_stopped(pid_t child) {
 char path[64],line[256];snprintf(path,sizeof(path),"/proc/%d/status",child);
 FILE *f=fopen(path,"r");if(!f)return 0;int stopped=0;
 while(fgets(line,sizeof(line),f))if(!strncmp(line,"State:",6)){stopped=strchr(line,'T')!=NULL;break;}
 fclose(f);return stopped;
}
static int orphan_adoption_case(int subreaper) {
 enum {N=40};memset(state,0,sizeof(*state));int control[2],ready[2];pipe(control);pipe(ready);
 pid_t parent=fork();
 if(!parent) {
  close(control[1]);close(ready[0]);setpgid(0,0);
  for(int i=0;i<N;i++) {
   int started[2];pipe(started);pid_t job=fork();
   if(!job) {
    close(started[0]);close(control[0]);close(ready[1]);orphan_slot=i;
    struct sigaction act={.sa_handler=orphan_handler};sigemptyset(&act.sa_mask);
    sigaction(SIGHUP,&act,NULL);sigaction(SIGCONT,&act,NULL);
    write(started[1],"r",1);close(started[1]);for(;;)pause();
   }
   close(started[1]);char c;read(started[0],&c,1);close(started[0]);
   if(setpgid(job,job) || kill(job,SIGSTOP) || !stopped(job,SIGSTOP))_exit(1);
   write(ready[1],&job,sizeof(job));
  }
  close(ready[1]);char c;read(control[0],&c,1);close(control[0]);_exit(0);
 }
 close(control[0]);close(ready[1]);pid_t jobs[N];int created=0;
 for(;created<N;created++)if(read(ready[0],&jobs[created],sizeof(pid_t))!=sizeof(pid_t))break;
 close(ready[0]);write(control[1],"x",1);close(control[1]);int status=0;
 int valid=created==N && waitpid(parent,&status,0)==parent && !status;usleep(100000);
 for(int i=0;i<created;i++) {
  valid &= atomic_load(&state->orphan_hups[i])==!subreaper &&
           atomic_load(&state->orphan_conts[i])==!subreaper &&
           process_is_stopped(jobs[i])==subreaper;
  kill(jobs[i],SIGKILL);
 }
 for(int i=0;i<created;i++)valid &= waitpid(jobs[i],&status,0)==jobs[i] && WIFSIGNALED(status);
 return valid;
}
static void orphan_transitions(void) {
 check(orphan_adoption_case(0),"parent exit resumes 40 newly orphaned stopped groups with HUP and CONT");
 pid_t subreaper=fork();if(!subreaper){prctl(PR_SET_CHILD_SUBREAPER,1);_exit(orphan_adoption_case(1)?0:1);}
 int status=0;check(waitpid(subreaper,&status,0)==subreaper && !status,
                   "same-session external subreaper keeps 40 adopted groups stopped");
}

static void many_children(void) {
 enum {N=40};pid_t children[N];
 puts("JOB-CHECK TRACE creating 40 children");
 for(int i=0;i<N;i++) { children[i]=fork(); if(!children[i]) {if(i==N-1){usleep(100000);_exit(13);}for(;;)pause();}
  if(children[i]<0){check(0,"create40children");return;} }
 puts("JOB-CHECK TRACE all 40 children created");
 int status=0;
 check(waitpid(-1,&status,0)==children[N-1] && WIFEXITED(status) && WEXITSTATUS(status)==13,
       "blocking wait wakes for child beyond first 32 events");
 for(int i=0;i<N-1;i++) kill(children[i],SIGKILL);
 for(int i=0;i<N-1;i++) waitpid(children[i],NULL,0);
}
struct waiting { pid_t child; int result, error, status; };
static int waiters_started;
static void *child_waiter(void *arg) {
 struct waiting *wait=arg; atomic_fetch_add(&waiters_started,1);
 wait->result=waitpid(wait->child,&wait->status,0);wait->error=errno;
 return NULL;
}
static void many_waiters(void) {
 enum {N=JOB_WAITERS}; int p[2];pipe(p);pid_t child=fork();
 if(!child){close(p[1]);char c;read(p[0],&c,1);_exit(23);}
 close(p[0]);struct waiting waits[N];pthread_t threads[N];int created=0;
 for(int i=0;i<N;i++) { waits[i]=(struct waiting){.child=child};
  if(pthread_create(&threads[i],NULL,child_waiter,&waits[i])) { break; }
  created++; }
 while(atomic_load(&waiters_started)<created)usleep(1000);
 usleep(100000);write(p[1],"x",1);close(p[1]);
 int won=0, errors=0;
 for(int i=0;i<created;i++){pthread_join(threads[i],NULL);
  if(waits[i].result==child && waits[i].status==(23<<8))won++;
  else if(waits[i].result==-1 && waits[i].error==ECHILD)errors++;
 }
 check(created==N && won==1 && errors==N-1,"more than 32 same-parent waiters safely compete for one exit event");
}

struct slab { unsigned long bytes, objects; };
static int read_slab(struct slab result[32]) {
 FILE *f=fopen("/proc/slabinfo","r");if(!f)return -1;char line[256];memset(result,0,32*sizeof(*result));
 int count=0;
 while(fgets(line,sizeof(line),f)) { unsigned long size,active,total;
  if(sscanf(line,"size-%lu %*u %lu %lu",&size,&active,&total)==3 && count<32)
   result[count++]=(struct slab){size,active};
 }
 fclose(f);return count;
}
static void allocation_cycles(void) {
 pid_t child=start_loop(0);int status=0,valid=1;
 for(int i=0;i<10;i++){printf("JOB-CHECK TRACE warmup cycle=%d\n",i);kill(child,SIGSTOP);if(!stopped(child,SIGSTOP)){printf("JOB-CHECK TRACE warmup stop cycle=%d errno=%d\n",i,errno);valid=0;}kill(child,SIGCONT);waitpid(child,&status,WCONTINUED);}
 struct slab before[32],after[32];int classes=read_slab(before);valid &= classes>0;
 for(int batch=0;batch<2;batch++) {
  for(int i=0;i<200;i++) {if(!(i%25))printf("JOB-CHECK TRACE allocation batch=%d cycle=%d\n",batch,i);kill(child,SIGSTOP);if(!stopped(child,SIGSTOP)){printf("JOB-CHECK TRACE allocation stop batch=%d cycle=%d errno=%d\n",batch,i,errno);valid=0;}
   kill(child,SIGCONT);int got=waitpid(child,&status,WCONTINUED);if(got!=child || !WIFCONTINUED(status)){printf("JOB-CHECK TRACE allocation continue batch=%d cycle=%d result=%d status=%x errno=%d\n",batch,i,got,status,errno);valid=0;}}
  valid &= read_slab(after)==classes;
  for(int i=0;i<classes;i++) {
   if((long)after[i].objects-(long)before[i].objects>2)valid=0;
   printf("JOB-SLAB batch=%d class=%lu delta=%ld\n",batch+1,after[i].bytes,(long)after[i].objects-(long)before[i].objects);
  }
  memcpy(before,after,sizeof(before));
 }
 check(valid,"400 stop/continue cycles preserve wait state and bounded storage");
 kill(child,SIGKILL);waitpid(child,NULL,0);
}

static void *short_thread(void *unused) {
 (void)unused;for(int i=0;i<10000;i++)atomic_fetch_add(&state->loops[1],1);return NULL;
}
static int teardown_create(pthread_t *thread,const pthread_attr_t *attr,
                           void *(*entry)(void *)) {
 // Retired kernel stacks remain charged until their reaper finishes. A burst
 // can legitimately refuse admission; keep racing teardown during that wait.
 // Unexpected errors or exhausting 2000 one-millisecond retries still fail.
 int result=0;
 for(int attempt=0;attempt<2000;attempt++) {
  result=pthread_create(thread,attr,entry,NULL);
  if(!result || (result!=EAGAIN && result!=ENOMEM))return result;
  atomic_fetch_add(&state->admission_retries,1);usleep(1000);
 }
 return result;
}
static void clone_exit_races(void) {
 memset(state,0,sizeof(*state));int p[2];pipe(p);pid_t child=fork();
 if(!child){close(p[0]);write(p[1],"r",1);close(p[1]);for(;;){pthread_t t;
  if(pthread_create(&t,NULL,short_thread,NULL))_exit(91);
  pthread_join(t,NULL);if(atomic_load(&state->command)==2)_exit(0);}}
 close(p[1]);char c;read(p[0],&c,1);close(p[0]);int valid=1,status=0;
 for(int i=0;i<40;i++){kill(child,SIGSTOP);if(!stopped(child,SIGSTOP))valid=0;
  unsigned long count=atomic_load(&state->loops[1]);usleep(3000);
  if(count!=atomic_load(&state->loops[1]))valid=0;
  kill(child,SIGCONT);if(waitpid(child,&status,WCONTINUED)!=child || !WIFCONTINUED(status))valid=0;}
 atomic_store(&state->command,2);
 valid &= waitpid(child,&status,0)==child && WIFEXITED(status) && !WEXITSTATUS(status);
 check(valid,"clone and sibling exit races cannot publish an incomplete stop");
}
static void *terminate_group(void *unused){(void)unused;usleep(3000);syscall(SYS_exit_group,0);return NULL;}
static void *teardown_loop(void *unused){(void)unused;for(;;)__asm__ __volatile__("" ::: "memory");return NULL;}
static int clone_teardown_batch(int count) {
 int valid=1,status=0;
 for(int i=0;i<count;i++) {
  int p[2];pipe(p);pid_t child=fork();
  if(!child){close(p[0]);if(i%2){pthread_t terminator;if(teardown_create(&terminator,NULL,terminate_group))_exit(92);}
   write(p[1],"r",1);close(p[1]);
   if(JOB_DETACHED_CHURN){for(;;){pthread_t t;
    if(teardown_create(&t,NULL,short_thread)) { _exit(91); }
    pthread_detach(t);}}
   pthread_attr_t attr;
   if(pthread_attr_init(&attr)||pthread_attr_setdetachstate(&attr,PTHREAD_CREATE_DETACHED))_exit(93);
   for(int worker=0;worker<JOB_WORKERS;worker++){pthread_t t;
    if(teardown_create(&t,&attr,teardown_loop))_exit(91);}
   for(;;)pause();}
  close(p[1]);char c;read(p[0],&c,1);close(p[0]);if(!(i%2)){usleep(3000);kill(child,SIGKILL);}
  pid_t got=waitpid(child,&status,0);
  int okay=got==child && (i%2 ? !status : WIFSIGNALED(status) && WTERMSIG(status)==SIGKILL);
  if(!okay)printf("JOB-CHECK TRACE teardown i=%d child=%d got=%d status=%x errno=%d\n",i,child,got,status,errno);
  valid &= okay;
 }
 return valid;
}
static unsigned long free_memory_kib(void) {
 FILE *f=fopen("/proc/meminfo","r");if(!f)return 0;char line[256];unsigned long free=0,slab=0,cached=0;
 while(fgets(line,sizeof(line),f)) {
  if(sscanf(line,"MemFree: %lu kB",&free)==1)continue;
  if(sscanf(line,"Slab: %lu kB",&slab)==1)continue;
  sscanf(line,"Cached: %lu kB",&cached);
 }
 printf("JOB-MEM snapshot free_kib=%lu slab_kib=%lu cached_kib=%lu\n",free,slab,cached);
 fclose(f);return free;
}
static void settle_teardown(void) {
 // Cover both the two-second process quarantine and five-second reader grace.
 // x86 teardown also drains guarded stacks page by page through SMP shootdowns.
 usleep(6500000);pid_t child=fork();if(!child)_exit(0);waitpid(child,NULL,0);usleep(10000);
 // waitpid observes exit before the final scheduler stack reclamation. SMP
 // shootdowns can leave that reaper actively returning pages at the sample.
 // Require a quiet half-second, with a bounded deadline; retained pages still
 // count against the unchanged 512 KiB per-batch limit below.
 unsigned long previous=free_memory_kib();int stable=0;
 for(int sample=0;sample<100 && stable<5;sample++) {
  usleep(100000);unsigned long current=free_memory_kib();
  stable=current==previous?stable+1:0;previous=current;
 }
 check(stable==5,"physical page reclamation settles before retention measurement");
}
static void allocation_tracking(int dump) {
 FILE *f=fopen(dump?"/proc/allocsites":"/proc/allocstart","r");if(!f)return;
 char line[1024];while(fgets(line,sizeof(line),f))if(dump)printf("PERF-SITE teardown %s",line);
 fclose(f);
}
static void clone_teardown_races(void) {
 unsigned long retries=atomic_load(&state->admission_retries);
 int valid=clone_teardown_batch(JOB_TEARDOWN_PROCESSES);settle_teardown();
 allocation_tracking(0);
 struct slab before[32],after[32];int classes=read_slab(before);unsigned long free_before=free_memory_kib();
 valid &= classes>0 && free_before>0;
 // Measure the diagnostics themselves: older kernels retain a Text scratch
 // descriptor for each /proc read. Keep that cost separate from child churn.
 long diagnostics[32]={0};valid &= read_slab(after)==classes;
 unsigned long free_control=free_memory_kib();
 for(int i=0;i<classes;i++) {
  long delta=(long)after[i].objects-(long)before[i].objects;
  diagnostics[i]=delta>0?delta:0;
  printf("JOB-SLAB teardown_control class=%lu delta=%ld\n",after[i].bytes,delta);
 }
 memcpy(before,after,sizeof(before));free_before=free_control;
 for(int batch=0;batch<JOB_TEARDOWN_BATCHES;batch++) {
  valid &= clone_teardown_batch(JOB_TEARDOWN_PROCESSES);settle_teardown();valid &= read_slab(after)==classes;
  unsigned long free_after=free_memory_kib();
  printf("JOB-MEM teardown_batch=%d free_kib_delta=%ld\n",batch+1,(long)free_after-(long)free_before);
  if(free_before>free_after+512)valid=0;
  for(int i=0;i<classes;i++) {
   long delta=(long)after[i].objects-(long)before[i].objects;
   printf("JOB-SLAB teardown_batch=%d class=%lu delta=%ld\n",batch+1,after[i].bytes,delta);
   if(delta>diagnostics[i]+2)valid=0;
  }
  memcpy(before,after,sizeof(before));free_before=free_after;
 }
 allocation_tracking(1);
 printf("JOB-ADMISSION teardown retries=%lu\n",atomic_load(&state->admission_retries)-retries);
 check(valid,"thread attachment racing teardown returns physical pages and slab objects");
}
static volatile sig_atomic_t children_signaled;
static void child_handler(int sig){(void)sig;children_signaled++;}
static void interrupted_waits(void) {
 for(int mode=0;mode<3;mode++) {
  int p[2];pipe(p);pid_t waiter=fork();
  if(!waiter) {
   close(p[0]);children_signaled=0;
   struct sigaction act={.sa_handler=child_handler,.sa_flags=mode==1?SA_RESTART:0};
   sigemptyset(&act.sa_mask);sigaction(SIGUSR1,&act,NULL);
   pid_t target=fork();if(!target){close(p[1]);for(;;)pause();}
   write(p[1],&target,sizeof(target));close(p[1]);int status=0;
   pid_t got=waitpid(target,&status,0);int error=errno;
   int valid=mode==2 ? got==-1 && error==EINTR && children_signaled==1 :
                     got==target && WIFSIGNALED(status) && WTERMSIG(status)==SIGTERM;
   if(got!=target){kill(target,SIGKILL);waitpid(target,NULL,0);}
   _exit(valid?0:1);
  }
  close(p[1]);pid_t target=0;int ready=read(p[0],&target,sizeof(target));close(p[0]);
  usleep(30000);int valid=ready==sizeof(target) && target>0,status=0;
  if(!mode) {
   kill(waiter,SIGSTOP);valid &= stopped(waiter,SIGSTOP);kill(waiter,SIGCONT);
   valid &= waitpid(waiter,&status,WCONTINUED)==waiter && WIFCONTINUED(status);
  } else kill(waiter,SIGUSR1);
  usleep(30000);kill(target,SIGTERM);
  valid &= waitpid(waiter,&status,0)==waiter && WIFEXITED(status) && !WEXITSTATUS(status);
  check(valid,mode==0?"continued stopped parent resumes its original child wait":
              mode==1?"caught SA_RESTART handler preserves blocking child wait":
                      "caught handler without SA_RESTART interrupts child wait");
 }
}
static void no_cld_stop(void) {
 struct sigaction act={.sa_handler=child_handler,.sa_flags=SA_NOCLDSTOP};sigemptyset(&act.sa_mask);
 sigaction(SIGCHLD,&act,NULL);children_signaled=0;
 pid_t child=fork();if(!child){for(;;)pause();}
 kill(child,SIGSTOP);int valid=stopped(child,SIGSTOP);kill(child,SIGCONT);
 int status=0;valid &= waitpid(child,&status,WCONTINUED)==child;
 valid &= !children_signaled;
 kill(child,SIGKILL);waitpid(child,NULL,0);usleep(10000);valid &= children_signaled>0;
 act.sa_handler=SIG_DFL;act.sa_flags=0;sigaction(SIGCHLD,&act,NULL);
 check(valid,"SA_NOCLDSTOP suppresses stop/continue signals while retaining wait events");
}

static void races(void) {
 int valid=1;
 for(int i=0;i<30;i++) {
  pid_t child=start_loop(0); if(child<0){valid=0;break;}
  kill(child,SIGSTOP);if(!stopped(child,SIGSTOP))valid=0;
  kill(child,SIGCONT);int status=0;if(waitpid(child,&status,WCONTINUED)!=child || !WIFCONTINUED(status))valid=0;
  atomic_store(&state->command,2);if(waitpid(child,&status,0)!=child || status)valid=0;
 }
 check(valid,"repeated multithread stop continue exit races");
}
int main(void) {
 setvbuf(stdout,NULL,_IONBF,0);setvbuf(stderr,NULL,_IONBF,0);
 state=mmap(NULL,4096,PROT_READ|PROT_WRITE,MAP_SHARED|MAP_ANONYMOUS,-1,0);
 if(state==MAP_FAILED)return 1;
 printf("JOB-CHECK START pid=%d ppid=%d pgrp=%d sid=%d\n",getpid(),getppid(),getpgrp(),getsid(0));
 if(JOB_FORK_ONLY) many_children();
 else if(JOB_CYCLES_ONLY) allocation_cycles();
 else if(JOB_TEARDOWN_ONLY) clone_teardown_races();
 else {stop_continue();dispositions();blocking_ipc();orphan_default_stops();process_groups();orphan_transitions();many_children();many_waiters();clone_exit_races();clone_teardown_races();no_cld_stop();interrupted_waits();races();allocation_cycles();}
 printf("JOB-CHECK DONE failures=%d\n",failures);sync();reboot(RB_POWER_OFF);
 return failures?1:0;
}
