/* SPDX-License-Identifier: GPL-2.0-or-later */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <poll.h>
#include <sched.h>
#include <signal.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/epoll.h>
#include <sys/mount.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/resource.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <time.h>
#include <termios.h>
#include <unistd.h>
#define CHECK(x) do { if (!(x)) { printf("PIDFD FAIL line %d: %s errno=%d\n",__LINE__,#x,errno); return 1; } } while (0)
#define ERR(x,e) do { errno=0; CHECK((x)==-1 && errno==(e)); } while (0)
static int p_open(pid_t p,unsigned f) { return syscall(434,p,f); }
static int p_signal(int fd,int s,void *i,unsigned f) { return syscall(424,fd,s,i,f); }
static int reap(pid_t p) { int s; while(waitpid(p,&s,0)<0) if(errno!=EINTR) return -1; return WIFEXITED(s)?WEXITSTATUS(s):-1; }
static pid_t sleeper(int *release) {
 int pipefd[2]; if(pipe(pipefd)) return -1;
 pid_t child=fork();
 if(!child) { close(pipefd[1]); char c; while(read(pipefd[0],&c,1)<0 && errno==EINTR) {} _exit(23); }
 close(pipefd[0]); *release=pipefd[1]; return child;
}
static int unsupported_clone(void) {
 int fd=-99; errno=0; long r=syscall(SYS_clone,CLONE_PIDFD|SIGCHLD,0,&fd,0,0);
 if(!r) _exit(77);
 if(r>0) (void)reap((pid_t)r);
 CHECK(r==-1&&errno==EINVAL&&fd==-99);
 uint64_t args[11]={CLONE_PIDFD,(uintptr_t)&fd,0,0,SIGCHLD}; errno=0;
 r=syscall(435,args,sizeof(args));
 if(!r) _exit(77);
 if(r>0) (void)reap((pid_t)r);
 CHECK(r==-1&&errno==EINVAL&&fd==-99);
 printf("PIDFD unsupported clone PASS\n"); return 0;
}
static int basic(void) {
 ERR(p_open(0,0),EINVAL); ERR(p_open(-1,0),EINVAL); ERR(p_open(65536,0),ESRCH); ERR(p_open(getpid(),1),EINVAL);
 int self=p_open(getpid(),O_NONBLOCK); CHECK(self>=0);
 CHECK(fcntl(self,F_GETFD)&FD_CLOEXEC); CHECK(fcntl(self,F_GETFL)&O_NONBLOCK);
 struct pollfd p={self,POLLIN,0}; CHECK(poll(&p,1,0)==0); char b;
 ERR(read(self,&b,1),EINVAL); ERR(p_signal(self,65,0,0),EINVAL); ERR(p_signal(self,0,0,1),EINVAL);
 ERR(p_signal(-1,0,0,0),EBADF); int ordinary=open("/proc/meminfo",O_RDONLY); CHECK(ordinary>=0);
 ERR(p_signal(ordinary,0,0,0),EBADF); close(ordinary);
 ERR(p_signal(self,0,(void *)1,0),EFAULT); siginfo_t info={0}; ERR(p_signal(self,0,&info,0),ENOSYS);
 CHECK(p_signal(self,0,0,0)==0); close(self);
 int release; pid_t child=sleeper(&release); CHECK(child>0);
 int fd=p_open(child,0),other=p_open(child,0),dupfd=dup(fd); CHECK(fd>=0 && other>=0 && dupfd>=0);
 int ep=epoll_create1(EPOLL_CLOEXEC); CHECK(ep>=0); struct epoll_event ev={.events=EPOLLIN|EPOLLET,.data.u64=42};
 CHECK(epoll_ctl(ep,EPOLL_CTL_ADD,fd,&ev)==0); CHECK(epoll_wait(ep,&ev,1,0)==0);
 close(release); p=(struct pollfd){fd,POLLIN,0}; CHECK(poll(&p,1,3000)==1 && (p.revents&POLLIN) && !(p.revents&POLLHUP));
 CHECK(epoll_wait(ep,&ev,1,100)==1 && (ev.events&EPOLLIN) && !(ev.events&EPOLLHUP) && ev.data.u64==42);
 CHECK(epoll_wait(ep,&ev,1,30)==0); // delivered ET must sleep, not spin
 p=(struct pollfd){fd,0,0}; CHECK(poll(&p,1,30)==0); // unrequested exit readiness
 p.events=POLLPRI; CHECK(poll(&p,1,30)==0);
 CHECK(p_signal(fd,0,0,0)==0); CHECK(p_signal(fd,SIGTERM,0,0)==0); // zombie retained
 CHECK(reap(child)==23); p=(struct pollfd){dupfd,0,0}; CHECK(poll(&p,1,0)==1 && (p.revents&POLLHUP));
 CHECK(epoll_wait(ep,&ev,1,100)==1 && (ev.events&(EPOLLIN|EPOLLHUP))==(EPOLLIN|EPOLLHUP));
 CHECK(epoll_wait(ep,&ev,1,30)==0); ERR(p_signal(fd,0,0,0),ESRCH); ERR(p_signal(other,SIGKILL,0,0),ESRCH);
 close(fd); close(other); close(dupfd); close(ep);
 child=sleeper(&release); CHECK(child>0); fd=p_open(child,0); CHECK(fd>=0); CHECK(p_signal(fd,SIGKILL,0,0)==0);
 int status; CHECK(waitpid(child,&status,0)==child && WIFSIGNALED(status) && WTERMSIG(status)==SIGKILL);
 close(release); close(fd); printf("PIDFD basic PASS\n"); return 0;
}
static int across_exec(void) {
 int gate[2]; CHECK(pipe(gate)==0); pid_t child=fork(); CHECK(child>=0);
 if(!child) {
  close(gate[1]); char c; if(read(gate[0],&c,1)!=1) _exit(1); close(gate[0]);
  int self=p_open(getpid(),0); if(self<0) _exit(2); char fd_text[32]; snprintf(fd_text,sizeof(fd_text),"%d",self);
  char *args[]={"init","pidfd-child-exec",fd_text,0}; execv("/sbin/init",args); _exit(3);
 }
 close(gate[0]); int fd=p_open(child,0); CHECK(fd>=0); CHECK(write(gate[1],"x",1)==1); close(gate[1]);
 struct pollfd p={fd,POLLIN,0}; CHECK(poll(&p,1,5000)==1&&(p.revents&POLLIN));
 CHECK(reap(child)==55); ERR(p_signal(fd,0,0,0),ESRCH); close(fd); printf("PIDFD exec identity PASS\n"); return 0;
}
static char oversized_exec_arg[60001];
static int exec_abort(void) {
 memset(oversized_exec_arg,'x',sizeof(oversized_exec_arg)-1);
 for(int mode=0;mode<2;mode++) for(int round=0;round<10;round++) {
  int gate[2]; CHECK(pipe(gate)==0); pid_t child=fork(); CHECK(child>=0);
  if(!child) {
   close(gate[1]); struct rlimit limit={mode?65536:0,RLIM_INFINITY};
   if(setrlimit(RLIMIT_STACK,&limit)) _exit(1);
   char c; if(read(gate[0],&c,1)!=1) _exit(2); close(gate[0]);
   char *args[]={"init",oversized_exec_arg,oversized_exec_arg,0};
   execv("/sbin/init",args); _exit(3);
  }
  close(gate[0]); int fd=p_open(child,0); CHECK(fd>=0);
  CHECK(write(gate[1],"x",1)==1); close(gate[1]);
  struct pollfd p={fd,POLLIN,0}; CHECK(poll(&p,1,5000)==1&&(p.revents&POLLIN));
  int status; CHECK(waitpid(child,&status,0)==child&&WIFSIGNALED(status)&&WTERMSIG(status)==SIGKILL);
  ERR(p_signal(fd,0,0,0),ESRCH); close(fd);
 }
 printf("PIDFD destructive exec failure PASS rounds=20\n"); return 0;
}
struct exec_sender { int fd; atomic_int stop,failed; };
static void *exec_sender(void *arg) {
 struct exec_sender *sender=arg;
 while(!atomic_load(&sender->stop)) {
  if(p_signal(sender->fd,SIGUSR1,0,0)||p_signal(sender->fd,SIGUSR2,0,0)||
     p_signal(sender->fd,SIGTSTP,0,0)||p_signal(sender->fd,SIGCONT,0,0)) atomic_store(&sender->failed,1);
 }
 return 0;
}
static int exec_race_child(int rounds,int ready,int gate) {
 if(rounds) {
  char round_text[32],ready_text[32],gate_text[32];
  snprintf(round_text,sizeof(round_text),"%d",rounds-1);
  snprintf(ready_text,sizeof(ready_text),"%d",ready); snprintf(gate_text,sizeof(gate_text),"%d",gate);
  char *args[]={"init","pidfd-exec-race",round_text,ready_text,gate_text,0};
  execv("/sbin/init",args); return 11;
 }
 sigset_t mask,pending; struct sigaction disposition;
 if(sigprocmask(SIG_SETMASK,0,&mask)||!sigismember(&mask,SIGUSR1)) return 12;
 if(sigaction(SIGUSR2,0,&disposition)||disposition.sa_handler!=SIG_IGN) return 13;
 if(sigpending(&pending)||!sigismember(&pending,SIGUSR1)||sigismember(&pending,SIGUSR2)) return 14;
 if(write(ready,"d",1)!=1) return 15;
 char c; if(read(gate,&c,1)!=1) return 16;
 if(sigpending(&pending)||sigismember(&pending,SIGTSTP)||!sigismember(&pending,SIGCONT)) return 17;
 return 0;
}
static int exec_signals(void) {
 int ready[2],gate[2]; CHECK(pipe(ready)==0&&pipe(gate)==0); pid_t child=fork(); CHECK(child>=0);
 if(!child) {
  close(ready[0]); close(gate[1]); sigset_t mask; sigemptyset(&mask); sigaddset(&mask,SIGUSR1);
  sigaddset(&mask,SIGTSTP); sigaddset(&mask,SIGCONT);
  struct sigaction ignored={.sa_handler=SIG_IGN};
  if(sigprocmask(SIG_BLOCK,&mask,0)||sigaction(SIGUSR2,&ignored,0)||kill(getpid(),SIGUSR1)) _exit(1);
  if(write(ready[1],"r",1)!=1) _exit(2);
  _exit(exec_race_child(40,ready[1],gate[0]));
 }
 close(ready[1]); close(gate[0]); char c; CHECK(read(ready[0],&c,1)==1&&c=='r');
 struct exec_sender sender={.fd=p_open(child,0)}; CHECK(sender.fd>=0);
 pthread_t thread; CHECK(pthread_create(&thread,0,exec_sender,&sender)==0);
 CHECK(read(ready[0],&c,1)==1&&c=='d'); atomic_store(&sender.stop,1); CHECK(pthread_join(thread,0)==0);
 CHECK(!atomic_load(&sender.failed)); CHECK(p_signal(sender.fd,SIGCONT,0,0)==0);
 CHECK(write(gate[1],"x",1)==1);
 close(ready[0]); close(gate[1]); CHECK(reap(child)==0); ERR(p_signal(sender.fd,0,0,0),ESRCH); close(sender.fd);
 printf("PIDFD exec signal race PASS rounds=40\n"); return 0;
}
static atomic_int pty_send_failed;
static void *pty_sender(void *arg) {
 int fd=*(int *)arg;
 for(int i=0;i<4000;i++) if(p_signal(fd,SIGCONT,0,0)) atomic_store(&pty_send_failed,1);
 return 0;
}
static int pty_signals(void) {
 int master=posix_openpt(O_RDWR|O_NOCTTY); CHECK(master>=0&&grantpt(master)==0&&unlockpt(master)==0);
 char name[64]; CHECK(ptsname_r(master,name,sizeof(name))==0);
 int ready[2],gate[2]; CHECK(pipe(ready)==0&&pipe(gate)==0); pid_t child=fork(); CHECK(child>=0);
 if(!child) {
  close(ready[0]); close(gate[1]); close(master);
  if(setsid()<0) _exit(1);
  int slave=open(name,O_RDWR);
  if(slave<0||ioctl(slave,TIOCSCTTY,0)||tcsetpgrp(slave,getpgrp())) _exit(2);
  struct termios settings; if(tcgetattr(slave,&settings)) _exit(3);
  settings.c_lflag=(settings.c_lflag|ISIG)&~ECHO; settings.c_cc[VINTR]=3;
  if(tcsetattr(slave,TCSANOW,&settings)) _exit(4);
  sigset_t blocked; sigemptyset(&blocked); sigaddset(&blocked,SIGINT);
  if(sigprocmask(SIG_BLOCK,&blocked,0)||write(ready[1],"r",1)!=1) _exit(5);
  char c; if(read(gate[0],&c,1)!=1||sigpending(&blocked)||!sigismember(&blocked,SIGINT)) _exit(6);
  _exit(0);
 }
 close(ready[1]); close(gate[0]); char c; CHECK(read(ready[0],&c,1)==1); close(ready[0]);
 int fd=p_open(child,0); CHECK(fd>=0); pthread_t sender; CHECK(pthread_create(&sender,0,pty_sender,&fd)==0);
 for(int i=0;i<2000;i++) CHECK(write(master,"\3",1)==1);
 CHECK(pthread_join(sender,0)==0&&!atomic_load(&pty_send_failed));
 CHECK(write(gate[1],"x",1)==1); close(gate[1]); CHECK(reap(child)==0); close(fd); close(master);
 printf("PIDFD PTY signal race PASS\n"); return 0;
}
static atomic_int wait_ready,wait_failed;
struct waiter { int fd, epoll; };
static void *waiter(void *arg) {
 struct waiter *w=arg; atomic_fetch_add(&wait_ready,1);
 if(w->epoll) { struct epoll_event ev; int r; do { r=epoll_wait(w->fd,&ev,1,3000); } while(r<0&&errno==EINTR);
  if(r!=1||!(ev.events&EPOLLIN)) atomic_store(&wait_failed,1);
 } else { struct pollfd p={w->fd,POLLIN,0}; int r; do { r=poll(&p,1,3000); } while(r<0&&errno==EINTR);
  if(r!=1||!(p.revents&POLLIN)) atomic_store(&wait_failed,1);
 }
 return 0;
}
static int waiters(void) {
 for(int round=0;round<80;round++) {
  int release; pid_t child=sleeper(&release); CHECK(child>0); int fd=p_open(child,0); CHECK(fd>=0);
  int ep[2]={epoll_create1(0),epoll_create1(0)}; CHECK(ep[0]>=0&&ep[1]>=0);
  struct epoll_event ev={.events=EPOLLIN|EPOLLONESHOT};
  for(int i=0;i<2;i++) CHECK(epoll_ctl(ep[i],EPOLL_CTL_ADD,fd,&ev)==0);
  struct waiter args[4]={{fd,0},{fd,0},{ep[0],1},{ep[1],1}}; pthread_t th[4];
  atomic_store(&wait_ready,0);
  for(int i=0;i<4;i++) CHECK(pthread_create(&th[i],0,waiter,&args[i])==0);
  while(atomic_load(&wait_ready)!=4) sched_yield();
  if(round%2) usleep(1000);
  close(release);
  for(int i=0;i<4;i++) CHECK(pthread_join(th[i],0)==0);
  CHECK(!atomic_load(&wait_failed));
  CHECK(epoll_wait(ep[0],&ev,1,20)==0); ev.events=EPOLLIN|EPOLLONESHOT;
  CHECK(epoll_ctl(ep[0],EPOLL_CTL_MOD,fd,&ev)==0); CHECK(epoll_wait(ep[0],&ev,1,20)==1);
  CHECK(reap(child)==23); close(fd); close(ep[0]); close(ep[1]);
 }
 printf("PIDFD multiple waiters PASS\n"); return 0;
}
static int permissions(void) {
 int release; pid_t child=sleeper(&release); CHECK(child>0); int fd=p_open(child,0); CHECK(fd>=0);
 pid_t probe=fork(); CHECK(probe>=0);
 if(!probe) { if(setuid(1234)) _exit(1); if(p_signal(fd,0,0,0)!=-1||errno!=EPERM) _exit(2);
  if(p_signal(fd,SIGCONT,0,0)) _exit(5);
  if(unshare(CLONE_NEWUSER)) _exit(3);
  if(p_signal(fd,SIGTERM,0,0)!=-1||errno!=EPERM) _exit(4);
  _exit(0); }
 CHECK(reap(probe)==0);
 probe=fork(); CHECK(probe>=0);
 if(!probe) {
  if(getuid()!=0||unshare(CLONE_NEWUSER)) _exit(1);
  if(p_signal(fd,0,0,0)!=-1||errno!=EPERM) _exit(2);
  if(p_signal(fd,SIGTERM,0,0)!=-1||errno!=EPERM) _exit(3);
  if(p_signal(fd,SIGCONT,0,0)) _exit(4);
  if(unshare(CLONE_NEWUSER)) _exit(5);
  if(p_signal(fd,0,0,0)!=-1||errno!=EPERM) _exit(6);
  if(setsid()<0||p_signal(fd,SIGCONT,0,0)!=-1||errno!=EPERM) _exit(7);
  _exit(0);
 }
 CHECK(reap(probe)==0);
 CHECK(unshare(CLONE_NEWPID)==0); probe=fork(); CHECK(probe>=0);
 if(!probe) { if(getpid()!=1) _exit(1); if(p_signal(fd,0,0,0)!=-1||errno!=EINVAL) _exit(2);
  int own=p_open(getpid(),0); if(own<0||p_signal(own,0,0,0)) _exit(3); close(own); _exit(0); }
 CHECK(reap(probe)==0); // subsequent children remain in own fresh pid namespace
 close(release); CHECK(reap(child)==23); close(fd);
 printf("PIDFD permissions and namespaces PASS\n"); return 0;
}
static atomic_int race_pid,race_fd,race_stop,race_failed;
static void *opener(void *unused) {
 (void)unused;
 while(!atomic_load(&race_stop)) {
  int p=atomic_load(&race_pid); if(!p) { sched_yield(); continue; }
  int fd=p_open(p,0); if(fd<0) { if(errno!=ESRCH&&errno!=ENFILE) atomic_store(&race_failed,1); continue; }
  int r=p_signal(fd,0,0,0); if(r<0&&errno!=ESRCH&&errno!=EINVAL) atomic_store(&race_failed,1);
  struct pollfd pollfd={fd,POLLIN,0}; if(poll(&pollfd,1,0)<0&&errno!=EINTR) atomic_store(&race_failed,1);
  close(fd);
 }
 return 0;
}
static void *closer(void *unused) {
 (void)unused;
 while(!atomic_load(&race_stop)) {
  int fd=atomic_exchange(&race_fd,-1); if(fd<0) { sched_yield(); continue; }
  int copy=dup(fd); if(copy>=0) { int r=p_signal(copy,SIGCONT,0,0); if(r<0&&errno!=ESRCH&&errno!=EINVAL) atomic_store(&race_failed,1); close(copy); }
  close(fd);
 }
 return 0;
}
static void *timer_churn(void *unused) {
 (void)unused; struct sigevent se={.sigev_notify=SIGEV_SIGNAL,.sigev_signo=SIGUSR2};
 struct itimerspec its={{0,1000000},{0,1000000}};
 while(!atomic_load(&race_stop)) { timer_t t; if(timer_create(CLOCK_MONOTONIC,&se,&t)) { atomic_store(&race_failed,1); break; }
  if(timer_settime(t,0,&its,0)||timer_delete(t)) atomic_store(&race_failed,1); }
 return 0;
}
static int races(void) {
 sigset_t set; sigemptyset(&set); sigaddset(&set,SIGUSR2); CHECK(pthread_sigmask(SIG_BLOCK,&set,0)==0);
 timer_t periodic; struct sigevent se={.sigev_notify=SIGEV_SIGNAL,.sigev_signo=SIGUSR2};
 struct itimerspec its={{0,100000000},{0,100000000}};
 CHECK(timer_create(CLOCK_MONOTONIC,&se,&periodic)==0&&timer_settime(periodic,0,&its,0)==0);
 pthread_t op[2],cl,timer; atomic_store(&race_fd,-1);
 CHECK(pthread_create(&op[0],0,opener,0)==0&&pthread_create(&op[1],0,opener,0)==0);
 CHECK(pthread_create(&cl,0,closer,0)==0&&pthread_create(&timer,0,timer_churn,0)==0);
 for(int i=0;i<1200;i++) {
  int release; pid_t child=sleeper(&release); CHECK(child>0); atomic_store(&race_pid,child);
  int fd=p_open(child,0); CHECK(fd>=0); int duplicate=dup(fd); CHECK(duplicate>=0);
  while(atomic_load(&race_fd)!=-1) sched_yield();
  atomic_store(&race_fd,duplicate);
  CHECK(p_signal(fd,SIGCONT,0,0)==0); close(release); CHECK(reap(child)==23);
  ERR(p_signal(fd,SIGCONT,0,0),ESRCH); close(fd); atomic_store(&race_pid,0);
  if((i+1)%100==0) printf("PIDFD lifecycle progress rounds=%d\n",i+1);
 }
 atomic_store(&race_stop,1);
 for(int i=0;i<2;i++) CHECK(pthread_join(op[i],0)==0);
 CHECK(pthread_join(cl,0)==0&&pthread_join(timer,0)==0); int left=atomic_exchange(&race_fd,-1); if(left>=0) close(left);
 CHECK(sigpending(&set)==0&&sigismember(&set,SIGUSR2)==1); CHECK(timer_delete(periodic)==0);
 CHECK(!atomic_load(&race_failed)); printf("PIDFD lifecycle and timer race PASS\n"); return 0;
}
static char slab_text[65536];
struct slab_snapshot {
 unsigned count;
 unsigned long long sizes[32],live[32],bytes,large_pages,written_after_free;
};
static int slab_snapshot(struct slab_snapshot *out) {
 memset(out,0,sizeof(*out)); int fd=open("/proc/slabinfo",O_RDONLY); CHECK(fd>=0);
 ssize_t n=read(fd,slab_text,sizeof(slab_text)-1); close(fd); CHECK(n>0); slab_text[n]=0;
 int have_large=0,have_frees=0;
 for(char *s=strtok(slab_text,"\n");s;s=strtok(0,"\n")) { unsigned long long size,live,pages;
  if(sscanf(s,"size-%*u %llu %llu %llu",&size,&live,&pages)==3) {
   CHECK(out->count<32); unsigned i=out->count++; out->sizes[i]=size; out->live[i]=live; out->bytes+=size*live;
  } else if(sscanf(s,"large - - %llu",&out->large_pages)==1) have_large=1;
  else if(sscanf(s,"# written after free %llu",&out->written_after_free)==1) have_frees=1;
 }
#ifdef __aarch64__
 CHECK(out->count==18&&have_large&&have_frees);
#else
 CHECK(out->count==14&&have_large&&have_frees);
#endif
 return 0;
}
static int slab_flat(const struct slab_snapshot *before,const struct slab_snapshot *after,const char *label,int window) {
 CHECK(before->count==after->count); int flat=1;
 for(unsigned i=0;i<after->count;i++) {
  CHECK(before->sizes[i]==after->sizes[i]);
  long long delta=(long long)after->live[i]-(long long)before->live[i];
  if(delta) { flat=0; printf("PIDFD CLASS %s window=%d size=%llu objects=%+lld\n",label,window,after->sizes[i],delta); }
 }
 long long large=(long long)after->large_pages-(long long)before->large_pages;
 printf("PIDFD HEAP %s window=%d classes=%u flat=%d large_pages=%+lld written_after_free=%llu\n",
  label,window,after->count,flat,large,after->written_after_free-before->written_after_free);
 CHECK(flat&&large==0&&after->written_after_free==before->written_after_free); return 0;
}
static int wait_change(pid_t child,int *status,int options) {
 for(int i=0;i<3000;i++) {
  int got=waitpid(child,status,options|WNOHANG);
  if(got!=0) { if(got<0&&errno==EINTR) continue; return got; }
  usleep(1000);
 }
 errno=ETIMEDOUT; return -1;
}
struct job_shared { atomic_ulong ticks[2]; };
static void *job_spin(void *arg) {
 atomic_ulong *ticks=arg;
 for(;;) atomic_fetch_add_explicit(ticks,1,memory_order_relaxed);
 return 0;
}
static int job_case(struct job_shared *shared,int mode,int rounds) {
 memset(shared,0,sizeof(*shared));
 int ready[2],gate[2]; CHECK(pipe(ready)==0&&pipe(gate)==0);
 pid_t child=fork(); CHECK(child>=0);
 if(!child) {
  close(ready[0]); close(gate[1]); sigset_t blocked,pending; sigemptyset(&blocked);
  sigaddset(&blocked,SIGTSTP); sigaddset(&blocked,SIGTTIN); sigaddset(&blocked,SIGTTOU);
  if(mode==0) sigaddset(&blocked,SIGCONT);
  struct sigaction ignored={.sa_handler=SIG_IGN};
  if(sigprocmask(SIG_BLOCK,&blocked,0)||(mode==1&&sigaction(SIGCONT,&ignored,0))) _exit(1);
  pthread_t threads[2];
  for(int i=0;i<2;i++) if(pthread_create(&threads[i],0,job_spin,&shared->ticks[i])) _exit(2);
  int self=p_open(getpid(),0); if(self<0||write(ready[1],"r",1)!=1) _exit(3);
  // Self-stop must finish pidfd's deferred parent notification before parking.
  if(p_signal(self,SIGSTOP,0,0)) _exit(4);
  char c; if(read(gate[0],&c,1)!=1||sigpending(&pending)) _exit(5);
  if(sigismember(&pending,SIGCONT)!=(mode==0)||sigismember(&pending,SIGTSTP)||
     sigismember(&pending,SIGTTIN)||sigismember(&pending,SIGTTOU)) _exit(6);
  close(self); _exit(0);
 }
 close(ready[1]); close(gate[0]); char c; CHECK(read(ready[0],&c,1)==1&&c=='r'); close(ready[0]);
 int fd=p_open(child,0); CHECK(fd>=0); int status;
 CHECK(wait_change(child,&status,WUNTRACED)==child&&WIFSTOPPED(status)&&WSTOPSIG(status)==SIGSTOP);
 CHECK(p_signal(fd,SIGCONT,0,0)==0);
 CHECK(wait_change(child,&status,WCONTINUED)==child&&WIFCONTINUED(status));
 for(int i=0;i<3000&&(!atomic_load(&shared->ticks[0])||!atomic_load(&shared->ticks[1]));i++) usleep(1000);
 CHECK(atomic_load(&shared->ticks[0])&&atomic_load(&shared->ticks[1]));
 for(int round=0;round<rounds;round++) {
  // All three catchable stops stay blocked, but cancel pending CONT immediately.
  CHECK(p_signal(fd,SIGTSTP,0,0)==0&&p_signal(fd,SIGTTIN,0,0)==0&&p_signal(fd,SIGTTOU,0,0)==0);
  CHECK(p_signal(fd,SIGSTOP,0,0)==0);
  CHECK(wait_change(child,&status,WUNTRACED)==child&&WIFSTOPPED(status)&&WSTOPSIG(status)==SIGSTOP);
  CHECK(waitpid(child,&status,WUNTRACED|WNOHANG)==0);
  unsigned long ticks[2];
  if(round==0) {
   usleep(50000);
   for(int i=0;i<2;i++) ticks[i]=atomic_load(&shared->ticks[i]);
   usleep(30000);
   for(int i=0;i<2;i++) CHECK(ticks[i]==atomic_load(&shared->ticks[i]));
  }
  CHECK(p_signal(fd,SIGCONT,0,0)==0);
  CHECK(wait_change(child,&status,WCONTINUED)==child&&WIFCONTINUED(status));
  CHECK(waitpid(child,&status,WCONTINUED|WNOHANG)==0);
  if(round==0) {
   for(int i=0;i<3000&&atomic_load(&shared->ticks[0])==ticks[0];i++) usleep(1000);
   CHECK(atomic_load(&shared->ticks[0])>ticks[0]);
  }
 }
 CHECK(write(gate[1],"x",1)==1); close(gate[1]); CHECK(reap(child)==0); close(fd);
 printf("PIDFD job control PASS mode=%d stop_cont_cycles=%d\n",mode,rounds+1); return 0;
}
static int retire_cpu_sweep(const cpu_set_t *allowed) {
 for(int cpu=0;cpu<CPU_SETSIZE;cpu++) if(CPU_ISSET(cpu,allowed)) {
  pid_t child=fork(); CHECK(child>=0);
  if(!child) {
   cpu_set_t one; CPU_ZERO(&one); CPU_SET(cpu,&one);
   if(sched_setaffinity(0,sizeof(one),&one)) _exit(1);
   for(int retry=0;retry<1000;retry++) {
    int actual=sched_getcpu(); if(actual==cpu) _exit(0); if(actual<0) _exit(2);
    sched_yield();
   }
   _exit(3);
  }
  CHECK(reap(child)==0);
 }
 return 0;
}
static int drain_retired(void) {
 cpu_set_t allowed; CHECK(sched_getaffinity(0,sizeof(allowed),&allowed)==0);
 CHECK(CPU_COUNT(&allowed)>0);
 // Replace every CPU's last dead thread before waiting out process quarantine.
 // The second sweep leaves one ordinary retiree per CPU in both snapshots.
 CHECK(retire_cpu_sweep(&allowed)==0); usleep(2200000);
 CHECK(retire_cpu_sweep(&allowed)==0); usleep(100000); return 0;
}
static int flush_reaped_jobs(void) { return drain_retired(); }
static int job_control(void) {
 struct job_shared *shared=mmap(0,sizeof(*shared),PROT_READ|PROT_WRITE,MAP_SHARED|MAP_ANONYMOUS,-1,0);
 CHECK(shared!=MAP_FAILED); struct slab_snapshot before,after;
 CHECK(job_case(shared,0,10)==0&&flush_reaped_jobs()==0);
 for(int i=0;i<4;i++) CHECK(slab_snapshot(&before)==0);
 for(int mode=0;mode<3;mode++) {
  CHECK(slab_snapshot(&before)==0&&job_case(shared,mode,200)==0&&flush_reaped_jobs()==0&&slab_snapshot(&after)==0);
  CHECK(slab_flat(&before,&after,"job-control-reaped",mode)==0);
 }
 CHECK(munmap(shared,sizeof(*shared))==0); return 0;
}
static int live_fd_cycles(int fd,int ep,int count) {
 sigset_t mask; CHECK(pthread_sigmask(SIG_SETMASK,0,&mask)==0);
 struct timespec zero={0};
 for(int i=0;i<count;i++) {
  struct pollfd p={fd,POLLIN,0}; struct epoll_event ev;
  CHECK(poll(&p,1,0)==0&&ppoll(&p,1,&zero,&mask)==0&&epoll_wait(ep,&ev,1,0)==0);
  CHECK(p_signal(fd,0,0,0)==0);
 }
 return 0;
}
static int live_retention(void) {
 int release; pid_t child=sleeper(&release); CHECK(child>0); int fd=p_open(child,0); CHECK(fd>=0);
 int ep=epoll_create1(0); CHECK(ep>=0); struct epoll_event ev={.events=EPOLLIN};
 CHECK(epoll_ctl(ep,EPOLL_CTL_ADD,fd,&ev)==0&&live_fd_cycles(fd,ep,200)==0);
 struct slab_snapshot before,after;
 for(int i=0;i<4;i++) CHECK(slab_snapshot(&before)==0);
 for(int window=0;window<2;window++) {
  CHECK(slab_snapshot(&before)==0&&live_fd_cycles(fd,ep,2000)==0&&slab_snapshot(&after)==0);
  CHECK(slab_flat(&before,&after,"live-poll-epoll",window)==0);
 }
 CHECK(epoll_ctl(ep,EPOLL_CTL_DEL,fd,0)==0); close(ep); close(release); CHECK(reap(child)==23); close(fd);
 printf("PIDFD live poll/ppoll/epoll retention PASS rounds=4000\n"); return 0;
}
static int exec_abort_retention(void) {
 CHECK(exec_abort()==0&&drain_retired()==0);
 struct slab_snapshot before,after;
 for(int i=0;i<5;i++) CHECK(slab_snapshot(&before)==0);
 for(int i=0;i<10;i++) CHECK(exec_abort()==0);
 CHECK(drain_retired()==0&&slab_snapshot(&after)==0);
 CHECK(slab_flat(&before,&after,"exec-abort",0)==0);
 printf("PIDFD destructive exec retention PASS rounds=200\n"); return 0;
}
static int fd_cycles(int count) {
 for(int i=0;i<count;i++) { int fd=p_open(getpid(),0); CHECK(fd>=0); int d=dup(fd); CHECK(d>=0);
  int ep=epoll_create1(0); CHECK(ep>=0); struct epoll_event e={.events=EPOLLIN};
  CHECK(epoll_ctl(ep,EPOLL_CTL_ADD,fd,&e)==0&&epoll_wait(ep,&e,1,0)==0);
  struct pollfd p={d,POLLIN,0}; CHECK(poll(&p,1,0)==0&&p_signal(fd,0,0,0)==0);
  CHECK(epoll_ctl(ep,EPOLL_CTL_DEL,fd,0)==0); close(ep); close(d); close(fd); }
 return 0;
}
static int retention(void) {
 struct slab_snapshot before,after; CHECK(fd_cycles(300)==0);
 for(int i=0;i<4;i++) CHECK(slab_snapshot(&before)==0);
 CHECK(slab_snapshot(&before)==0&&fd_cycles(10000)==0&&slab_snapshot(&after)==0);
 printf("PIDFD RETENTION retained_bytes=%lld rounds=10000\n",(long long)after.bytes-(long long)before.bytes);
 CHECK(slab_flat(&before,&after,"descriptors",0)==0);
 printf("PIDFD retention PASS\n"); return 0;
}
static int timed_cycles(int fd,int ep,int count) {
 for(int i=0;i<count;i++) {
  struct pollfd p={fd,POLLPRI,0}; struct epoll_event ev;
  CHECK(poll(&p,1,1)==0 && epoll_wait(ep,&ev,1,1)==0);
 }
 return 0;
}
static int timed_retention(void) {
 int release; pid_t child=sleeper(&release); CHECK(child>0); int fd=p_open(child,0); CHECK(fd>=0);
 int ep=epoll_create1(0); CHECK(ep>=0); struct epoll_event ev={.events=EPOLLIN|EPOLLET};
 CHECK(epoll_ctl(ep,EPOLL_CTL_ADD,fd,&ev)==0); close(release);
 CHECK(epoll_wait(ep,&ev,1,3000)==1 && (ev.events&EPOLLIN));
 struct slab_snapshot before,after; CHECK(timed_cycles(fd,ep,200)==0);
 for(int i=0;i<4;i++) CHECK(slab_snapshot(&before)==0);
 for(int window=0;window<3;window++) {
  CHECK(slab_snapshot(&before)==0&&timed_cycles(fd,ep,2000)==0&&slab_snapshot(&after)==0);
  printf("PIDFD WAIT RETENTION retained_bytes=%lld rounds=2000 window=%d\n",(long long)after.bytes-(long long)before.bytes,window);
  CHECK(slab_flat(&before,&after,"timed-waits",window)==0);
 }
 CHECK(reap(child)==23); close(ep); close(fd); return 0;
}
static int exhaustion(void) {
 pid_t children[1100]; int count=0;
 for(;count<1100;count++) {
  pid_t child=fork(); CHECK(child>=0); if(!child) _exit(0); children[count]=child;
  int fd=p_open(child,0);
  if(fd<0) { CHECK(errno==ENFILE); count++; break; }
  struct pollfd p={fd,POLLIN,0}; CHECK(poll(&p,1,3000)==1 && (p.revents&POLLIN)); close(fd);
 }
 CHECK(count==1024); // one identity belongs to the still-live test init
 CHECK(reap(children[0])==0); int recovered=p_open(children[count-1],0); CHECK(recovered>=0); close(recovered);
 for(int i=1;i<count;i++) CHECK(reap(children[i])==0);
 CHECK(fd_cycles(10)==0); printf("PIDFD identity bound PASS identities=%d\n",count); return 0;
}
static int identity_reuse(void) {
 enum { COUNT=512 }; int fds[COUNT]; pid_t old[COUNT],p; int request[2],reply[2];
 CHECK(pipe(request)==0&&pipe(reply)==0); pid_t runner=fork(); CHECK(runner>=0);
 if(!runner) {
  close(request[1]); close(reply[0]); char command;
  while(read(request[0],&command,1)==1 && command=='n') {
   int release; pid_t target=sleeper(&release);
   if(target<=0 || write(reply[1],&target,sizeof(target))!=sizeof(target)) _exit(1);
   if(read(request[0],&command,1)!=1 || command!='x') _exit(2);
   close(release); int result=reap(target);
   if(write(reply[1],&result,sizeof(result))!=sizeof(result)) _exit(3);
  }
  _exit(0);
 }
 close(request[0]); close(reply[1]);
 for(int i=0;i<COUNT;i++) {
  CHECK(write(request[1],"n",1)==1&&read(reply[0],&p,sizeof(p))==sizeof(p));
  old[i]=p; fds[i]=p_open(p,0); CHECK(fds[i]>=0);
  int result; CHECK(write(request[1],"x",1)==1&&read(reply[0],&result,sizeof(result))==sizeof(result)&&result==23);
 }
 int reused=0;
 for(int j=0;j<5000;j++) {
  CHECK(write(request[1],"n",1)==1&&read(reply[0],&p,sizeof(p))==sizeof(p));
  for(int i=0;i<COUNT;i++) if(p==old[i]) { reused++; ERR(p_signal(fds[i],0,0,0),ESRCH); ERR(p_signal(fds[i],SIGKILL,0,0),ESRCH); }
  int result; CHECK(write(request[1],"x",1)==1&&read(reply[0],&result,sizeof(result))==sizeof(result)&&result==23);
  if((j+1)%1000==0) printf("PIDFD numeric reuse progress rounds=%d collisions=%d\n",j+1,reused);
 }
 CHECK(write(request[1],"q",1)==1); close(request[1]); close(reply[0]); CHECK(reap(runner)==0);
 for(int i=0;i<COUNT;i++) { struct pollfd p={fds[i],POLLIN,0}; CHECK(poll(&p,1,0)==1&&(p.revents&POLLHUP)); close(fds[i]); }
 CHECK(reused>0); printf("PIDFD numeric reuse PASS collisions=%d\n",reused); return 0;
}
int main(int argc,char **argv) {
 if(argc==3&&!strcmp(argv[1],"pidfd-child-exec")) {
  int fd=atoi(argv[2]); if(fcntl(fd,F_GETFD)!=-1||errno!=EBADF) _exit(4); _exit(55);
 }
 if(argc==5&&!strcmp(argv[1],"pidfd-exec-race")) _exit(exec_race_child(atoi(argv[2]),atoi(argv[3]),atoi(argv[4])));
 setvbuf(stdout,0,_IONBF,0); if(access("/proc/slabinfo",F_OK)) mount("proc","/proc","proc",0,0);
 if(argc==2&&!strcmp(argv[1],"pidfd-job-check")) {
  CHECK(job_control()==0&&live_retention()==0&&exec_abort_retention()==0&&exec_signals()==0&&pty_signals()==0);
  printf("PIDFD PASS\n"); for(;;) pause();
 }
 // PTY removal waits out a separate VFS grace; run that semantic cohort after
 // every retention snapshot so its node/name cleanup cannot alter a baseline.
 CHECK(unsupported_clone()==0&&basic()==0&&across_exec()==0&&exec_abort()==0&&exec_signals()==0&&job_control()==0&&live_retention()==0&&waiters()==0&&races()==0&&exhaustion()==0&&exec_abort_retention()==0&&retention()==0&&timed_retention()==0&&identity_reuse()==0&&permissions()==0&&pty_signals()==0);
 printf("PIDFD PASS\n"); for(;;) pause();
}
