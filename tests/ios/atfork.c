// SPDX-License-Identifier: GPL-2.0-or-later
extern int pthread_atfork(void (*)(void),void (*)(void),void (*)(void));
extern int pthread_create(unsigned long *,const void *,void *(*)(void *),void *),pthread_join(unsigned long,void **);
extern int fork(void),waitpid(int,int *,int),getpid(void),kill(int,int),pipe(int *),close(int),*__error(void);
extern long read(int,void *,unsigned long),write(int,const void *,unsigned long);
extern int open(const char *,int,...),strcmp(const char *,const char *),puts(const char *),printf(const char *,...);
extern unsigned long strlen(const char *);
extern void _exit(int) __attribute__((noreturn));
static _Thread_local int prepared,parent_calls,child_calls,stage;
static int trace_fd=-1,adapter;
#define CHECK(value,code) do { if(!(value)){printf("IOS-ATFORK: failure %d errno %d\n",code,*__error());return code;} } while(0)
static void emit(char value) { if(trace_fd>=0 && write(trace_fd,&value,1)!=1)_exit(90); }
static void advance(int expected) { if(stage!=expected)_exit(91);stage++; }
static void registered_prepare(void){prepared++;}
static void registered_parent(void){parent_calls++;}
static void registered_child(void){child_calls++;}
static void a_prepare(void){advance(1);emit('a');}
static void b_prepare(void){
    advance(0);emit('b');
    if(adapter){
        *__error()=178;
        if(pthread_atfork(registered_prepare,0,0)!=11 || *__error()!=178)_exit(92);
    }
}
static void a_parent(void){advance(2);emit('A');}
static void b_parent(void){advance(3);emit('B');}
static void a_child(void){advance(2);emit('x');}
static void b_child(void){advance(3);emit('y');}
struct job { int result,index; };
static void *registrar(void *argument){
    struct job *job=argument;
    for(int i=0;i<4;i++){
        *__error()=177;
        if(pthread_atfork(0,0,0) || pthread_atfork(registered_prepare,registered_parent,registered_child) || *__error()!=177){job->result=1;break;}
    }
    return 0;
}
static void reset(void){prepared=parent_calls=child_calls=stage=0;}
static int start_child(int code){
    reset();*__error()=177;
    int pid=fork();
    if(!pid){if(prepared!=32 || child_calls!=32 || parent_calls || stage!=4)_exit(93);_exit(code);}
    if(pid<0 || *__error()!=177 || prepared!=32 || parent_calls!=32 || child_calls || stage!=4)return -1;
    return pid;
}
static void *forker(void *argument){
    struct job *job=argument;int pid=start_child(17+job->index);
    struct {unsigned before;int status;unsigned after;} value={0x12345678,-1,0x87654321};
    if(pid<0 || waitpid(pid,&value.status,0)!=pid || value.status!=(17+job->index)*256 ||
       value.before!=0x12345678 || value.after!=0x87654321)job->result=1;
    return 0;
}
static int threads(void *(*worker)(void *)){
    unsigned long ids[8];struct job jobs[8]={0};int started=0,failed=0;
    for(int i=0;i<8;i++){jobs[i].index=i;if(pthread_create(&ids[i],0,worker,&jobs[i]))break;started++;}
    for(int i=0;i<started;i++)if(pthread_join(ids[i],0) || jobs[i].result)failed=1;
    return started==8 && !failed ? 0 : -1;
}
static int control(const char *group,const char *file,char *value,int writing){
    char path[4096];unsigned long n=strlen(group),m=strlen(file);
    if(n+m+2>=sizeof(path))return -1;
    for(unsigned long i=0;i<n;i++)path[i]=group[i];path[n++]='/';
    for(unsigned long i=0;i<=m;i++)path[n+i]=file[i];
    int fd=open(path,writing?1:0);if(fd<0)return -1;
    long count=writing?write(fd,value,strlen(value)):read(fd,value,63);
    int cleanup=close(fd);if(count<=0 || cleanup)return -1;
    if(!writing)value[count]=0;
    return 0;
}
int main(int argc,char **argv){
    adapter=argc>1 && !strcmp(argv[1],"--adapter");
    CHECK(threads(registrar)==0,1);
    CHECK(pthread_atfork(a_prepare,a_parent,a_child)==0 && pthread_atfork(b_prepare,b_parent,b_child)==0,2);
    if(argc==3 && !strcmp(argv[1],"--fork-failure")){
        char count[64];CHECK(control(argv[2],"pids.current",count,0)==0 && control(argv[2],"pids.max",count,1)==0,3);
        reset();*__error()=177;int pid=fork(),error=*__error();
        if(!pid)_exit(94);
        CHECK(control(argv[2],"pids.max","max",1)==0,4);
        CHECK(pid==-1 && error==35 && prepared==32 && parent_calls==32 && !child_calls && stage==4,5);
        CHECK(pthread_atfork(0,0,0)==0,6);
        puts("IOS-ATFORK: native fork failure, Darwin EAGAIN, parent callbacks and unlocked registry");return 0;
    }
    int descriptors[2];CHECK(pipe(descriptors)==0,7);trace_fd=descriptors[1];
    int pid=start_child(42);CHECK(pid>0,8);
    int status=-1;CHECK(waitpid(pid,&status,0)==pid && status==42*256,9);
    CHECK(close(descriptors[1])==0,10);trace_fd=-1;
    char bytes[16]={0};int length=0;
    for(;;){long n=read(descriptors[0],bytes+length,sizeof(bytes)-length-1);CHECK(n>=0,11);if(!n)break;length+=(int)n;CHECK(length<15,12);}
    CHECK(close(descriptors[0])==0 && length==6 && bytes[0]=='b' && bytes[1]=='a',13);
    int a=-1,b=-1,x=-1,y=-1;
    for(int i=2;i<6;i++){if(bytes[i]=='A')a=i;if(bytes[i]=='B')b=i;if(bytes[i]=='x')x=i;if(bytes[i]=='y')y=i;}
    CHECK(a>=2 && b>a && x>=2 && y>x,14);
    CHECK(threads(forker)==0,15);
    /* A blocked child makes WNOHANG deterministic and leaves status untouched. */
    CHECK(pipe(descriptors)==0,16);reset();pid=fork();CHECK(pid>=0,17);
    if(!pid){char byte;if(close(descriptors[1]) || read(descriptors[0],&byte,1)!=1)_exit(95);_exit(19);}
    CHECK(close(descriptors[0])==0,18);status=0x12345678;
    CHECK(waitpid(pid,&status,1)==0 && status==0x12345678,19);
    CHECK(write(descriptors[1],"x",1)==1 && close(descriptors[1])==0,20);
    CHECK(waitpid(pid,&status,0)==pid && status==19*256,21);
    CHECK(waitpid(pid,&status,0)==-1 && *__error()==10,22);
    CHECK(waitpid(-1,&status,0x4000)==-1 && *__error()==22,23);
    reset();pid=fork();CHECK(pid>=0,24);
    if(!pid){kill(getpid(),30);_exit(96);}
    CHECK(waitpid(pid,&status,0)==pid && (status&0x7f)==30,25);
    reset();pid=fork();CHECK(pid>=0,26);if(!pid)_exit(23);
    CHECK(waitpid(pid,0,0)==pid,27);
    /* Keep the resumed child blocked until its continued event is consumed. */
    CHECK(pipe(descriptors)==0,28);reset();pid=fork();CHECK(pid>=0,29);
    if(!pid){
        char byte;if(close(descriptors[1]) || kill(getpid(),17) || read(descriptors[0],&byte,1)!=1)_exit(97);
        _exit(24);
    }
    CHECK(close(descriptors[0])==0,30);
    CHECK(waitpid(pid,&status,2)==pid && status==(17*256+0x7f),31);
    CHECK(kill(pid,19)==0 && waitpid(pid,&status,0x10)==pid && status==0x137f,32);
    CHECK(write(descriptors[1],"x",1)==1 && close(descriptors[1])==0,33);
    CHECK(waitpid(pid,&status,0)==pid && status==24*256,34);
    puts("IOS-ATFORK: real forks, ordered callbacks, eight-thread registration/forking, image TLS, guarded wait status, signals and errno");
    return 0;
}
