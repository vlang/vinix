/* SPDX-License-Identifier: GPL-2.0-or-later */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <grp.h>
#include <limits.h>
#include <pthread.h>
#include <sched.h>
#include <signal.h>
#include <stdint.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ipc.h>
#include <sys/mman.h>
#include <sys/mount.h>
#include <sys/msg.h>
#include <sys/wait.h>
#include <unistd.h>

#ifndef MSG_COPY
#define MSG_COPY 040000
#endif

#define CHECK(x) do { if (!(x)) { printf("SYSVMSG FAIL line %d: %s errno=%d\n", __LINE__, #x, errno); return 1; } } while (0)
#define ERR(x, e) do { errno=0; CHECK((x)==-1 && errno==(e)); } while (0)
struct message { long type; char text[8192]; };
static char slab_text[65536];
static atomic_int received;
static atomic_int thread_failed;
static int thread_queue;

static int reap(pid_t child) {
	int status;
	while (waitpid(child,&status,0)<0) if (errno!=EINTR) return -1;
	return WIFEXITED(status) ? WEXITSTATUS(status) : -1;
}

static int basic(void) {
	struct message m={3,"three"}, out;
	struct msqid_ds ds;
	_Static_assert(sizeof(struct msqid_ds)==120,"64-bit msqid_ds ABI");
	int q=msgget(0x21707,IPC_CREAT|IPC_EXCL|0600);
	CHECK(q>=0);
	ERR(msgget(0x21707,IPC_CREAT|IPC_EXCL|0600),EEXIST);
	CHECK(msgget(0x21707,0600)==q);
	ERR(msgget(0x21708,0600),ENOENT);
	ERR(msgsnd(q,&m,8193,0),EINVAL);
	m.type=0; ERR(msgsnd(q,&m,1,0),EINVAL); m.type=3;
	ERR(msgsnd(q,(void *)1,1,0),EFAULT);
	CHECK(msgsnd(q,&m,6,0)==0);
	m.type=1; memcpy(m.text,"first",6); CHECK(msgsnd(q,&m,6,0)==0);
	m.type=2; memcpy(m.text,"two",4); CHECK(msgsnd(q,&m,4,0)==0);
	CHECK(msgctl(q,IPC_STAT,&ds)==0 && ds.msg_qnum==3 && ds.msg_cbytes==16 && ds.msg_qbytes==16384 && ds.msg_lspid==getpid());
	ERR(msgrcv(q,&out,2,3,IPC_NOWAIT),E2BIG);
	CHECK(msgctl(q,IPC_STAT,&ds)==0 && ds.msg_qnum==3);
	CHECK(msgrcv(q,&out,sizeof(out.text),-3,IPC_NOWAIT)==6 && out.type==1 && !strcmp(out.text,"first"));
	CHECK(msgrcv(q,&out,2,3,MSG_NOERROR|IPC_NOWAIT)==2 && out.type==3 && !memcmp(out.text,"th",2));
	CHECK(msgrcv(q,&out,sizeof(out.text),1,MSG_EXCEPT|IPC_NOWAIT)==4 && out.type==2);
	ERR(msgrcv(q,&out,1,0,IPC_NOWAIT),ENOMSG);
	m.type=LONG_MAX; CHECK(msgsnd(q,&m,0,0)==0);
	CHECK(msgrcv(q,&out,0,LONG_MIN,IPC_NOWAIT)==0 && out.type==LONG_MAX);
	m.type=7; CHECK(msgsnd(q,&m,0,0)==0);
	CHECK(msgrcv(q,&out,0,0,IPC_NOWAIT)==0 && out.type==7);
	ERR(msgrcv(q,&out,1,0,MSG_COPY),EINVAL);
	ERR(msgrcv(q,&out,1,0,MSG_COPY|MSG_EXCEPT|IPC_NOWAIT),EINVAL);
	ERR(msgrcv(q,&out,1,0,MSG_COPY|IPC_NOWAIT),ENOMSG);
	CHECK(msgsnd(q,&m,0,0)==0);
	CHECK(msgrcv(q,&out,0,0,MSG_COPY|IPC_NOWAIT)==0 && out.type==m.type);
	CHECK(msgctl(q,IPC_STAT,&ds)==0 && ds.msg_qnum==1);
	CHECK(msgrcv(q,&out,0,0,IPC_NOWAIT)==0 && out.type==m.type);
	ERR(msgctl(q,99,&ds),EINVAL);
	ERR(msgctl(q,IPC_STAT,(void *)1),EFAULT);
	ERR(msgctl(q,IPC_SET,(void *)1),EFAULT);
	CHECK(msgctl(q,IPC_STAT,&ds)==0);
	ds.msg_qbytes=4; CHECK(msgctl(q,IPC_SET,&ds)==0);
	CHECK(msgsnd(q,&m,4,IPC_NOWAIT)==0);
	ERR(msgsnd(q,&m,1,IPC_NOWAIT),EAGAIN);
	CHECK(msgrcv(q,&out,4,0,0)==4);
	for (int i=0;i<4;i++) CHECK(msgsnd(q,&m,0,IPC_NOWAIT)==0);
	ERR(msgsnd(q,&m,0,IPC_NOWAIT),EAGAIN);
	for (int i=0;i<4;i++) CHECK(msgrcv(q,&out,0,0,IPC_NOWAIT)==0);
	ds.msg_qbytes=1024*1024+1; ERR(msgctl(q,IPC_SET,&ds),EINVAL);
	ds.msg_qbytes=16384; CHECK(msgctl(q,IPC_SET,&ds)==0);
	CHECK(msgsnd(q,&m,3,0)==0);
	ERR(msgrcv(q,(void *)1,3,0,IPC_NOWAIT),EFAULT);
	CHECK(msgctl(q,IPC_STAT,&ds)==0 && ds.msg_qnum==0);
	CHECK(msgctl(q,IPC_RMID,0)==0);
	ERR(msgctl(q,IPC_STAT,&ds),EINVAL);
	ERR(msgsnd(q,&m,0,IPC_NOWAIT),EINVAL);
	printf("SYSVMSG basic PASS\n");
	return 0;
}

static void noop(int s) { (void)s; }
enum operation { RECEIVE, SEND };
static int blocking_case(enum operation op, int remove_queue, int signal_child) {
	int q=msgget(IPC_PRIVATE,0600), p[2];
	struct message m={9,"data"}; struct msqid_ds ds;
	CHECK(q>=0 && pipe(p)==0);
	if (op==SEND) {
		CHECK(msgctl(q,IPC_STAT,&ds)==0); ds.msg_qbytes=4;
		CHECK(msgctl(q,IPC_SET,&ds)==0 && msgsnd(q,&m,4,0)==0);
	}
	pid_t child=fork(); CHECK(child>=0);
	if (!child) {
		close(p[0]); alarm(5);
		struct sigaction sa={.sa_handler=noop,.sa_flags=SA_RESTART}; sigemptyset(&sa.sa_mask);
		if (sigaction(SIGUSR1,&sa,0) || write(p[1],"r",1)!=1) _exit(1);
		errno=0;
		int r=op==RECEIVE ? (int)msgrcv(q,&m,4,9,0) : msgsnd(q,&m,4,0);
		if (remove_queue) _exit(r==-1 && errno==EIDRM ? 0:2);
		if (signal_child) _exit(r==-1 && errno==EINTR ? 0:3);
		_exit(r==(op==RECEIVE ? 4:0) ? 0:4);
	}
	close(p[1]); char c; CHECK(read(p[0],&c,1)==1); close(p[0]); usleep(50000);
	if (remove_queue) CHECK(msgctl(q,IPC_RMID,0)==0);
	else if (signal_child) CHECK(kill(child,SIGUSR1)==0);
	else if (op==RECEIVE) CHECK(msgsnd(q,&m,4,0)==0);
	else CHECK(msgrcv(q,&m,4,0,0)==4);
	CHECK(reap(child)==0);
	if (!remove_queue) CHECK(msgctl(q,IPC_RMID,0)==0);
	return 0;
}

static int permissions(void) {
	int q=msgget(0x21709,IPC_CREAT|IPC_EXCL|0600); CHECK(q>=0);
	int initial_ipc=open("/proc/self/ns/ipc",O_RDONLY); CHECK(initial_ipc>=0);
	pid_t child=fork(); CHECK(child>=0);
	if (!child) {
		struct message m={1,"x"}; struct msqid_ds ds;
		if (setgroups(0,0) || setgid(1000) || setuid(1000)) _exit(1);
		errno=0; if (msgget(0x21709,0600)!=-1 || errno!=EACCES) _exit(2);
		errno=0; if (msgsnd(q,&m,1,IPC_NOWAIT)!=-1 || errno!=EACCES) _exit(3);
		errno=0; if (msgrcv(q,&m,1,0,IPC_NOWAIT)!=-1 || errno!=EACCES) _exit(4);
		errno=0; if (msgctl(q,IPC_STAT,&ds)!=-1 || errno!=EACCES) _exit(5);
		errno=0; if (msgctl(q,IPC_RMID,0)!=-1 || errno!=EPERM) _exit(6);
		_exit(0);
	}
	CHECK(reap(child)==0);
	struct msqid_ds ds; CHECK(msgctl(q,IPC_STAT,&ds)==0);
	ds.msg_perm.gid=2000; ds.msg_perm.mode=0060; CHECK(msgctl(q,IPC_SET,&ds)==0);
	child=fork(); CHECK(child>=0);
	if (!child) {
		gid_t group=2000; struct message m={1,"x"};
		if (setgroups(1,&group) || setgid(1000) || setuid(1000)) _exit(1);
		if (msgsnd(q,&m,1,0) || msgrcv(q,&m,1,0,0)!=1) _exit(2);
		_exit(0);
	}
	CHECK(reap(child)==0 && msgctl(q,IPC_RMID,0)==0);
	q=msgget(IPC_PRIVATE,0); CHECK(q>=0);
	child=fork(); CHECK(child>=0);
	if (!child) {
		if (unshare(CLONE_NEWUSER)) _exit(1);
		errno=0; if (setns(initial_ipc,CLONE_NEWIPC)!=-1 || errno!=EPERM) _exit(6);
		errno=0; if (msgctl(q,IPC_STAT,&ds)!=-1 || errno!=EACCES) _exit(2);
		int own=msgget(IPC_PRIVATE,0600);
		if (own<0 || msgctl(own,IPC_STAT,&ds)) _exit(3);
		ds.msg_qbytes=16385;
		errno=0; if (msgctl(own,IPC_SET,&ds)!=-1 || errno!=EPERM) _exit(4);
		if (msgctl(own,IPC_RMID,0)) _exit(5);
		_exit(0);
	}
	CHECK(reap(child)==0 && msgctl(q,IPC_RMID,0)==0);
	child=fork(); CHECK(child>=0);
	if (!child) {
		if (unshare(CLONE_NEWUSER|CLONE_NEWIPC)) _exit(1);
		int own=msgget(IPC_PRIVATE,0600);
		if (own<0 || msgctl(own,IPC_STAT,&ds)) _exit(2);
		int own_ipc=open("/proc/self/ns/ipc",O_RDONLY);
		if (own_ipc<0 || unshare(CLONE_NEWIPC) || setns(own_ipc,CLONE_NEWIPC)) _exit(4);
		close(own_ipc);
		ds.msg_qbytes=16385;
		if (msgctl(own,IPC_SET,&ds) || msgctl(own,IPC_RMID,0)) _exit(3);
		_exit(0);
	}
	CHECK(reap(child)==0);
	close(initial_ipc);
	printf("SYSVMSG permissions PASS\n"); return 0;
}

static int namespaces(void) {
	int q=msgget(0x21710,IPC_CREAT|IPC_EXCL|0600); CHECK(q>=0);
	pid_t child=fork(); CHECK(child>=0);
	if (!child) {
		struct msqid_ds ds;
		if (unshare(CLONE_NEWIPC)) _exit(1);
		errno=0; if (msgctl(q,IPC_STAT,&ds)!=-1 || errno!=EINVAL) _exit(2);
		errno=0; if (msgget(0x21710,0)!=-1 || errno!=ENOENT) _exit(3);
		int own=msgget(0x21710,IPC_CREAT|0600);
		if (own<0 || own==q) _exit(4);
		// nsfs descriptors keep IPC state alive after the last process leaves.
		int ns=open("/proc/self/ns/ipc",O_RDONLY);
		if (ns<0 || unshare(CLONE_NEWIPC) || setns(ns,CLONE_NEWIPC)) _exit(5);
		if (msgget(0x21710,0600)!=own) _exit(6);
		close(ns);
		_exit(0); // the final namespace reference destroys 'own'.
	}
	CHECK(reap(child)==0 && msgget(0x21710,0600)==q && msgctl(q,IPC_RMID,0)==0);
	// More abandoned namespaces than registry slots prove queue reclamation.
	for (int i=0;i<140;i++) {
		child=fork(); CHECK(child>=0);
		if (!child) { if (unshare(CLONE_NEWIPC) || msgget(IPC_PRIVATE,0600)<0) _exit(1); _exit(0); }
		CHECK(reap(child)==0);
	}
	printf("SYSVMSG namespaces PASS\n"); return 0;
}

static void *namespace_creator(void *unused) {
	(void)unused;
	for (int i=0;i<4000;i++) {
		int q=msgget(IPC_PRIVATE,0600);
		if (q<0) { if (errno==EIDRM) continue; return (void *)1; }
		int r=msgctl(q,IPC_RMID,0);
		if (r && errno!=EINVAL && errno!=EIDRM) return (void *)2;
	}
	return 0;
}

static int namespace_race(void) {
	pid_t child=fork(); CHECK(child>=0);
	if (!child) {
		alarm(20);
		pthread_t thread;
		if (unshare(CLONE_NEWIPC) || pthread_create(&thread,0,namespace_creator,0)) _exit(1);
		for (int i=0;i<400;i++) if (unshare(CLONE_NEWIPC)) _exit(2);
		void *result;
		if (pthread_join(thread,&result) || result) _exit(3);
		_exit(0);
	}
	CHECK(reap(child)==0);
	printf("SYSVMSG namespace race PASS\n"); return 0;
}

static unsigned long long slab_bytes(void) {
	int fd=open("/proc/slabinfo",O_RDONLY); if (fd<0) return ~0ULL;
	ssize_t n=read(fd,slab_text,sizeof(slab_text)-1); close(fd);
	if (n<0) return ~0ULL;
	slab_text[n]=0;
	unsigned long long total=0;
	for (char *s=strtok(slab_text,"\n");s;s=strtok(0,"\n")) {
		unsigned long long size,live,pages;
		if (sscanf(s,"size-%*u %llu %llu %llu",&size,&live,&pages)==3) total+=size*live;
	}
	return total;
}

static int cycles(int rounds) {
	struct message m={7,"payload"};
	for (int i=0;i<rounds;i++) {
		int q=msgget(IPC_PRIVATE,0600); CHECK(q>=0);
		CHECK(msgsnd(q,&m,37,0)==0 && msgrcv(q,&m,37,0,0)==37);
		CHECK(msgsnd(q,&m,8192,0)==0 && msgctl(q,IPC_RMID,0)==0);
	}
	return 0;
}

static int retention(void) {
	CHECK(cycles(200)==0);
	for (int i=0;i<4;i++) CHECK(slab_bytes()!=~0ULL);
	unsigned long long before=slab_bytes();
	CHECK(cycles(10000)==0);
	unsigned long long after=slab_bytes();
	printf("SYSVMSG RETENTION retained_bytes=%lld rounds=10000\n",(long long)(after-before));
	CHECK(after<=before+1024);
	printf("SYSVMSG retention PASS\n"); return 0;
}

static void *consumer(void *unused) {
	(void)unused;
	struct message m;
	for (int i=0;i<11000;i++) {
		if (msgrcv(thread_queue,&m,8192,0,0)!=8192 || m.type!=1) {
			atomic_store(&thread_failed,1); return 0;
		}
		atomic_fetch_add(&received,1);
	}
	return 0;
}

static int blocked_retention(void) {
	thread_queue=msgget(IPC_PRIVATE,0600); CHECK(thread_queue>=0);
	struct msqid_ds ds; CHECK(msgctl(thread_queue,IPC_STAT,&ds)==0);
	ds.msg_qbytes=8192; CHECK(msgctl(thread_queue,IPC_SET,&ds)==0);
	pthread_t thread; CHECK(pthread_create(&thread,0,consumer,0)==0);
	struct message m={1,{0}};
	for (int i=0;i<1000;i++) CHECK(msgsnd(thread_queue,&m,8192,0)==0);
	while (atomic_load(&received)<1000 && !atomic_load(&thread_failed)) sched_yield();
	CHECK(!atomic_load(&thread_failed));
	for (int i=0;i<4;i++) CHECK(slab_bytes()!=~0ULL);
	unsigned long long before=slab_bytes();
	for (int i=0;i<10000;i++) CHECK(msgsnd(thread_queue,&m,8192,0)==0);
	while (atomic_load(&received)<11000 && !atomic_load(&thread_failed)) sched_yield();
	CHECK(!atomic_load(&thread_failed));
	unsigned long long after=slab_bytes();
	printf("SYSVMSG BLOCKED RETENTION retained_bytes=%lld messages=10000\n",(long long)(after-before));
	CHECK(after<=before+1024);
	CHECK(pthread_join(thread,0)==0 && msgctl(thread_queue,IPC_RMID,0)==0);
	return 0;
}

static int exhaustion(void) {
	int ids[128];
	for (int i=0;i<128;i++) { ids[i]=msgget(IPC_PRIVATE,0600); CHECK(ids[i]>=0); }
	ERR(msgget(IPC_PRIVATE,0600),ENOSPC);
	int stale=ids[0]; CHECK(msgctl(ids[0],IPC_RMID,0)==0);
	ids[0]=msgget(IPC_PRIVATE,0600); CHECK(ids[0]>=0 && ids[0]!=stale);
	struct msqid_ds ds; ERR(msgctl(stale,IPC_STAT,&ds),EINVAL);
	for (int i=0;i<128;i++) CHECK(msgctl(ids[i],IPC_RMID,0)==0);
	struct message m={1,{0}}; int count=0, stopped=0;
	for (int i=0;i<40;i++) {
		ids[i]=msgget(IPC_PRIVATE,0600); CHECK(ids[i]>=0);
		CHECK(msgctl(ids[i],IPC_STAT,&ds)==0); ds.msg_qbytes=1024*1024;
		CHECK(msgctl(ids[i],IPC_SET,&ds)==0);
		for (int j=0;j<128;j++) {
			int r=msgsnd(ids[i],&m,sizeof(m.text),IPC_NOWAIT);
			if (r<0) { CHECK(errno==ENOMEM); stopped=1; break; }
			count++;
		}
		if (stopped) { for (int j=0;j<=i;j++) CHECK(msgctl(ids[j],IPC_RMID,0)==0); break; }
	}
	CHECK(stopped && count>0 && count<4096);
	CHECK(cycles(100)==0);
	printf("SYSVMSG exhaustion PASS messages=%d\n",count); return 0;
}

int main(void) {
	setvbuf(stdout,0,_IONBF,0);
	if (access("/proc/slabinfo",F_OK)) mount("proc","/proc","proc",0,0);
	CHECK(basic()==0);
	for (int op=0;op<2;op++) {
		CHECK(blocking_case(op,0,0)==0);
		CHECK(blocking_case(op,1,0)==0);
		CHECK(blocking_case(op,0,1)==0);
	}
	printf("SYSVMSG blocking PASS\n");
	CHECK(permissions()==0 && namespaces()==0 && namespace_race()==0 && exhaustion()==0 && retention()==0 && blocked_retention()==0);
	printf("SYSVMSG PASS\n");
	for (;;) pause();
}
