// SPDX-License-Identifier: GPL-2.0-or-later
extern int ioctl(int,unsigned long,...),socketpair(int,int,int,int *),socket(int,int,int),close(int),fcntl(int,int,...);
extern long send(int,const void *,unsigned long,int),recv(int,void *,unsigned long,int);
extern int *__error(void),puts(const char *),printf(const char *,...),strcmp(const char *,const char *);
extern void *memset(void *,int,unsigned long);
extern int pthread_create(unsigned long *,const void *,void *(*)(void *),void *),pthread_join(unsigned long,void **);
struct ifaddrs { struct ifaddrs *next;char *name;unsigned flags;void *address,*mask,*destination,*data; };
extern int getifaddrs(struct ifaddrs **);extern void freeifaddrs(struct ifaddrs *);
#define CHECK(value,code) do { if (!(value)) { printf("IOS-IOCTL: failure %d errno %d\n",code,*__error()); return code; } } while (0)
#define FIONBIO 0x8004667eUL
#define FIONREAD 0x4004667fUL
#define FIOCLEX 0x20006601UL
#define FIONCLEX 0x20006602UL
static int descriptors(void) {
    int pair[2];CHECK(socketpair(1,1,0,pair)==0,1);
    int alias=fcntl(pair[0],67,100);CHECK(alias>=100,2);
    *__error()=177;CHECK(ioctl(pair[0],FIOCLEX)==0 && *__error()==177 && fcntl(pair[0],1)==1,3);
    CHECK(ioctl(pair[0],FIONCLEX)==0 && fcntl(pair[0],1)==0 && fcntl(alias,1)==1,4);
    int on=1;CHECK(ioctl(pair[0],FIONBIO,&on)==0 && (fcntl(alias,3)&4),5);
    char bytes[16];CHECK(recv(pair[0],bytes,1,0)==-1 && *__error()==35,6);
    CHECK(send(pair[1],"1234567",7,0)==7,7);
    struct { unsigned before; int count; unsigned after; } guard={0xabcdef01, -1, 0x12345678};
    *__error()=177;CHECK(ioctl(alias,FIONREAD,&guard.count)==0 && *__error()==177 && guard.count==7,8);
    CHECK(guard.before==0xabcdef01 && guard.after==0x12345678,9);
    CHECK(recv(pair[0],bytes,3,0)==3 && ioctl(alias,FIONREAD,&guard.count)==0 && guard.count==4,10);
    on=0;CHECK(ioctl(alias,FIONBIO,&on)==0 && !(fcntl(pair[0],3)&4),11);
    CHECK(ioctl(pair[0],FIONREAD,0)==-1 && *__error()==14,12);
    CHECK(ioctl(-1,FIONBIO,0)==-1 && *__error()==14,13);
    CHECK(ioctl(-1,FIONBIO,&on)==-1 && *__error()==9,35);
    CHECK(ioctl(-1,0x1234UL)==-1 && *__error()==9,14);
#ifndef IOS_IOCTL_REFERENCE
    CHECK(ioctl(pair[0],0x1234UL)==-1 && *__error()==45,15);
#endif
    CHECK(close(alias)==0 && close(pair[0])==0 && close(pair[1])==0,16);
    return 0;
}
static int interfaces(void) {
    struct ifaddrs *list;CHECK(getifaddrs(&list)==0,17);
    char name[16]={0};unsigned flags=0;
    for(struct ifaddrs *p=list;p;p=p->next) if(p->flags&8){for(int i=0;i<15 && p->name[i];i++) name[i]=p->name[i];flags=p->flags;break;}
    freeifaddrs(list);CHECK(name[0],18);
    int fd=socket(2,2,0);CHECK(fd>=0,19);
    struct { unsigned char before[8],name[16],value[16],after[8]; } guard;
    unsigned long queries[]={0xc0206911UL,0xc0206917UL,0xc0206921UL,0xc0206925UL,0xc0206933UL};
    for(int i=0;i<5;i++) {
        memset(&guard,0xa5,sizeof guard);for(int j=0;j<16;j++)guard.name[j]=(unsigned char)name[j];
        *__error()=177;CHECK(ioctl(fd,queries[i],guard.name)==0 && *__error()==177,20);
        for(int j=0;j<8;j++) CHECK(guard.before[j]==0xa5 && guard.after[j]==0xa5,21);
        CHECK(!strcmp((char *)guard.name,name),22);
        if(i==0) {
            unsigned actual=guard.value[0] | (unsigned)guard.value[1]<<8;
            CHECK(actual==(flags&0xffff),23);
            for(int j=2;j<16;j++) CHECK(guard.value[j]==0xa5,24);
        } else if(i==1 || i==4) {
            int actual=*(int *)guard.value;CHECK(i==1 ? actual==0 : actual>0,25);
            for(int j=4;j<16;j++) CHECK(guard.value[j]==0xa5,26);
        } else {
            CHECK(guard.value[1]==2 && guard.value[0]==(i==2 ? 16 : 5),27);
            CHECK(guard.value[4]==(i==2 ? 127 : 255) && guard.value[5]==0 && guard.value[6]==0 && guard.value[7]==(i==2 ? 1 : 0),28);
        }
    }
    CHECK(ioctl(fd,0xc0206923UL,guard.name)==-1 && *__error()==22,29);
    memset(guard.name,0,sizeof guard.name);guard.name[0]='?';
    CHECK(ioctl(fd,0xc0206911UL,guard.name)==-1 && *__error()==6,30);
    CHECK(ioctl(fd,0xc0206911UL,0)==-1 && *__error()==14,31);
    CHECK(close(fd)==0,32);
    return 0;
}
struct job { int result; };
static void *worker(void *argument) { struct job *job=argument;for(int i=0;i<16;i++){job->result=descriptors();if(job->result) break;}return 0; }
int main(void) {
    int error=descriptors();if(error) return error;
    error=interfaces();if(error) return error;
    unsigned long clients[8];struct job jobs[8]={0};
    int started=0,failed=0;
    for(int i=0;i<8;i++){if(pthread_create(&clients[i],0,worker,&jobs[i])!=0)break;started++;}
    for(int i=0;i<started;i++)if(pthread_join(clients[i],0)!=0 || jobs[i].result)failed=1;
    CHECK(started==8,33);
    CHECK(!failed,34);
    puts("IOS-IOCTL: descriptor flags, shared nonblocking I/O, queued bytes, native interfaces and eight threads");
    return 0;
}
