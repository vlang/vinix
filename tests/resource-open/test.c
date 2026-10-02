#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <termios.h>
#include <unistd.h>

#define CHECK(condition) do { if (!(condition)) { \
 printf("FAIL: resource open line=%d %s errno=%d\n",__LINE__,#condition,errno); return 1; \
} } while (0)

struct heap {
 unsigned count;
 unsigned long long size[32],live[32],large,written_after_free;
};

static int snapshot(struct heap *out) {
 char text[65536]; memset(out,0,sizeof(*out));
 int fd=open("/proc/slabinfo",O_RDONLY); CHECK(fd>=0);
 ssize_t count=read(fd,text,sizeof(text)-1); CHECK(count>0&&close(fd)==0); text[count]=0;
 int have_large=0,have_frees=0;
 for(char *line=strtok(text,"\n");line;line=strtok(0,"\n")) {
  unsigned long long size,live,pages;
  if(sscanf(line,"size-%*u %llu %llu %llu",&size,&live,&pages)==3) {
   CHECK(out->count<32); unsigned i=out->count++; out->size[i]=size; out->live[i]=live;
  } else if(sscanf(line,"large - - %llu",&out->large)==1) have_large=1;
  else if(sscanf(line,"# written after free %llu",&out->written_after_free)==1) have_frees=1;
 }
#ifdef __aarch64__
 CHECK(out->count==18&&have_large&&have_frees);
#else
 CHECK(out->count==14&&have_large&&have_frees);
#endif
 return 0;
}

static int trace(int start,int window) {
 int fd=open(start?"/proc/allocstart":"/proc/allocsites",O_RDONLY);
 if(fd<0) { CHECK(errno==ENOENT); return 0; }
 static char text[262144]; ssize_t n=read(fd,text,sizeof(text)-1); CHECK(n>0&&close(fd)==0); text[n]=0;
 if(!start) for(char *line=strtok(text,"\n");line;line=strtok(0,"\n"))
  printf("PERF-SITE resource-open window=%d %s\n",window,line);
 return 0;
}

static int pty_cycle(int reverse_close) {
 int master=posix_openpt(O_RDWR|O_NOCTTY); CHECK(master>=0);
 CHECK(grantpt(master)==0&&unlockpt(master)==0);
 char name[64]; CHECK(ptsname_r(master,name,sizeof(name))==0);
 int slave=open(name,O_RDWR|O_NOCTTY); CHECK(slave>=0);
 struct termios settings; CHECK(tcgetattr(slave,&settings)==0); cfmakeraw(&settings);
 CHECK(tcsetattr(slave,TCSANOW,&settings)==0);
 char byte=0;
 CHECK(write(master,"m",1)==1&&read(slave,&byte,1)==1&&byte=='m');
 CHECK(write(slave,"s",1)==1&&read(master,&byte,1)==1&&byte=='s');
 if(reverse_close) {
  CHECK(close(master)==0&&read(slave,&byte,1)==0&&close(slave)==0);
 } else CHECK(close(slave)==0&&close(master)==0);
 errno=0; CHECK(access(name,F_OK)==-1&&errno==ENOENT);
 return 0;
}

static int semantics(void) {
 int master=posix_openpt(O_RDWR|O_NOCTTY); CHECK(master>=0);
 char name[64]; CHECK(ptsname_r(master,name,sizeof(name))==0);
 errno=0; CHECK(open(name,O_RDWR|O_NOCTTY)==-1&&errno==EIO);
 CHECK(unlockpt(master)==0);
 int slave=open(name,O_RDWR|O_NOCTTY); CHECK(slave>=0);
 int duplicate=dup(slave); CHECK(duplicate>=0&&close(slave)==0&&close(master)==0);
 char byte; CHECK(read(duplicate,&byte,1)==0&&close(duplicate)==0);
 errno=0; CHECK(access(name,F_OK)==-1&&errno==ENOENT);
 errno=0; CHECK(open("/dev/tty",O_RDWR|O_NOCTTY)==-1&&errno==ENXIO);

 // A mknod alias must dispatch to its backing factory and keep its returned box.
 struct stat info; CHECK(stat("/dev/ptmx",&info)==0);
 CHECK(mknod("/tmp/open-ptmx",S_IFCHR|0600,info.st_rdev)==0);
 master=open("/tmp/open-ptmx",O_RDWR|O_NOCTTY); CHECK(master>=0&&unlockpt(master)==0);
 CHECK(ptsname_r(master,name,sizeof(name))==0);
 slave=open(name,O_RDWR|O_NOCTTY); CHECK(slave>=0&&close(slave)==0&&close(master)==0);
 CHECK(unlink("/tmp/open-ptmx")==0);

 // A backing device without an open callback retains the mknod node's own box.
 CHECK(stat("/dev/null",&info)==0&&mknod("/tmp/open-null",S_IFCHR|0600,info.st_rdev)==0);
 int fd=open("/tmp/open-null",O_RDWR); CHECK(fd>=0);
 CHECK(read(fd,&byte,1)==0&&write(fd,"x",1)==1&&close(fd)==0&&unlink("/tmp/open-null")==0);
 fd=open("/tmp/open-regular",O_CREAT|O_EXCL|O_RDWR,0600); CHECK(fd>=0);
 CHECK(write(fd,"f",1)==1&&lseek(fd,0,SEEK_SET)==0&&read(fd,&byte,1)==1&&byte=='f');
 CHECK(close(fd)==0&&unlink("/tmp/open-regular")==0);

 // The anonymous-descriptor path creates an independent pipe description.
 int pipefd[2]; CHECK(pipe(pipefd)==0);
 snprintf(name,sizeof(name),"/proc/self/fd/%d",pipefd[0]);
 fd=open(name,O_RDONLY|O_NONBLOCK); CHECK(fd>=0&&close(pipefd[0])==0);
 CHECK(write(pipefd[1],"p",1)==1&&read(fd,&byte,1)==1&&byte=='p');
 CHECK(close(pipefd[1])==0&&read(fd,&byte,1)==0&&close(fd)==0);
 printf("RESOURCE OPEN semantics PASS\n"); return 0;
}

static int cohort(void) {
 for(int i=0;i<200;i++) CHECK(pty_cycle(i&1)==0);
 // Removed device nodes wait for the VFS grace and its periodic reaper.
 usleep(11000000); return 0;
}

int main(void) {
 setvbuf(stdout,0,_IONBF,0);
 if(access("/proc/slabinfo",F_OK)) CHECK(mount("proc","/proc","proc",0,0)==0);
 CHECK(semantics()==0&&cohort()==0);
 CHECK(trace(1,-1)==0&&trace(0,-1)==0);
 struct heap before,after;
 for(int i=0;i<5;i++) CHECK(snapshot(&before)==0);
 for(int window=0;window<2;window++) {
  CHECK(trace(1,window)==0&&snapshot(&before)==0&&cohort()==0&&snapshot(&after)==0);
  CHECK(before.count==after.count); int flat=1;
  for(unsigned i=0;i<after.count;i++) {
   CHECK(before.size[i]==after.size[i]);
   long long delta=(long long)after.live[i]-(long long)before.live[i];
   printf("RESOURCE-OPEN window=%d class=%llu objects=%+lld\n",window,after.size[i],delta);
   if(delta) flat=0;
  }
  long long large=(long long)after.large-(long long)before.large;
  printf("RESOURCE-OPEN window=%d large_pages=%+lld written_after_free=%llu flat=%d\n",
         window,large,after.written_after_free-before.written_after_free,flat);
  CHECK(trace(0,window)==0);
  CHECK(flat&&large==0&&after.written_after_free==before.written_after_free);
 }
 printf("RESOURCE OPEN: PASS\n"); for(;;) pause();
}
