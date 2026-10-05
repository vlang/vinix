// SPDX-License-Identifier: GPL-2.0-or-later
// Repeated successful and failing raw stat calls must return checked ABI data
// and leave every live heap class, slab pages, large-page count and post-free
// marker flat.
#define REQUIRE_FLAT 1
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <sched.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/reboot.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>
#define CHECK(x) do { if (!(x)) { printf("XNU STAT FAIL line=%d errno=%d\n",__LINE__,errno); return -1; } } while (0)
struct snapshot { unsigned count; unsigned long long size[32],live[32],pages[32],large,uaf; long free,slab,cached; };
static int target;
static char text[131072];
static int pause_ns(unsigned long long interval) {
 struct timespec t; CHECK(clock_gettime(CLOCK_MONOTONIC,&t)==0);
 unsigned long long end=(unsigned long long)t.tv_sec*1000000000ull+t.tv_nsec+interval;
 for(;;) {
  CHECK(clock_gettime(CLOCK_MONOTONIC,&t)==0); unsigned long long now=(unsigned long long)t.tv_sec*1000000000ull+t.tv_nsec;
  if(now>=end) return 0;
  unsigned long long left=end-now; struct timespec req={left/1000000000ull,left%1000000000ull};
  CHECK(nanosleep(&req,0)==0||errno==EINTR);
 }
}
static int read_proc(const char *path) { int fd=open(path,O_RDONLY);if(fd<0&&errno==ENOENT&&!strcmp(path,"/proc/allocstart"))return 0;CHECK(fd>=0);ssize_t n=read(fd,text,sizeof(text)-1);int result=close(fd);CHECK(n>0&&result==0);text[n]=0;return 0; }
static int snapshot(struct snapshot *out) {
 memset(out,0,sizeof(*out));out->free=out->slab=out->cached=-1;
 CHECK(read_proc("/proc/meminfo")==0);
 for(char *s=strtok(text,"\n");s;s=strtok(0,"\n")) {long value;if(sscanf(s,"MemFree: %ld",&value)==1)out->free=value;else if(sscanf(s,"Slab: %ld",&value)==1)out->slab=value;else if(sscanf(s,"Cached: %ld",&value)==1)out->cached=value;}
 CHECK(out->free>=0&&out->slab>=0&&out->cached>=0&&read_proc("/proc/slabinfo")==0);int large=0,uaf=0;
 for(char *s=strtok(text,"\n");s;s=strtok(0,"\n")) {unsigned long long label,size,live,pages;
  if(sscanf(s,"size-%llu %llu %llu %llu",&label,&size,&live,&pages)==4) {CHECK(label==size&&out->count<32);unsigned i=out->count++;out->size[i]=size;out->live[i]=live;out->pages[i]=pages;}
  else if(sscanf(s,"large - - %llu",&out->large)==1)large=1;else if(sscanf(s,"# written after free %llu",&out->uaf)==1)uaf=1;
 }
#ifdef __aarch64__
 CHECK(out->count==18&&large&&uaf);
#else
 CHECK(out->count==14&&large&&uaf);
#endif
 return 0;
}
static int sites(const char *name,int cohort) {
 int fd=open("/proc/allocsites",O_RDONLY);if(fd<0&&errno==ENOENT)return 0;CHECK(fd>=0); FILE *f=fdopen(fd,"r");CHECK(f);char line[2048];while(fgets(line,sizeof(line),f))printf("PERF-SITE program=%s cohort=%d %s",name,cohort,line);CHECK(!ferror(f)&&fclose(f)==0);return 0;
}
static int report(const char *name,int cohort,int runs,const struct snapshot *before,const struct snapshot *after) {
 CHECK(before->count==after->count&&before->uaf==after->uaf);unsigned nonzero=0;
 for(unsigned i=0;i<after->count;i++) { CHECK(before->size[i]==after->size[i]);long long d=(long long)after->live[i]-before->live[i];long long pages=(long long)after->pages[i]-before->pages[i];if(d||pages) {nonzero++;printf("XNU CHURN CLASS program=%s cohort=%d size=%llu objects=%+lld pages=%+lld\n",name,cohort,after->size[i],d,pages);} }
 printf("XNU CHURN MEASURE program=%s cohort=%d runs=%d classes=%u nonzero=%u used_kib=%+ld slab_kib=%+ld cached_kib=%+ld large_pages=%+lld written_after_free=%llu\n",name,cohort,runs,after->count,nonzero,before->free-after->free,after->slab-before->slab,after->cached-before->cached,(long long)after->large-before->large,after->uaf-before->uaf);CHECK(sites(name,cohort)==0);return 0;
}
static int operation(void) {
 struct stat first,second;
 CHECK(syscall(SYS_fstat,target,&first)==0&&S_ISCHR(first.st_mode));
 CHECK(syscall(SYS_fstat,-1,&second)==-1&&errno==EBADF);
 CHECK(syscall(SYS_fstat,target,(void*)1)==-1&&errno==EFAULT);
 CHECK(syscall(SYS_newfstatat,target,"",&second,AT_EMPTY_PATH)==0&&second.st_ino==first.st_ino&&second.st_dev==first.st_dev&&second.st_mode==first.st_mode);
 CHECK(syscall(SYS_newfstatat,AT_FDCWD,"/dev/null",&second,0)==0&&second.st_ino==first.st_ino&&second.st_dev==first.st_dev&&second.st_mode==first.st_mode);
 CHECK(syscall(SYS_newfstatat,AT_FDCWD,"/absent-stat-probe",&second,0)==-1&&errno==ENOENT);
 CHECK(syscall(SYS_newfstatat,AT_FDCWD,(void*)1,&second,0)==-1&&errno==EFAULT);
 CHECK(syscall(SYS_newfstatat,AT_FDCWD,"/dev/null",(void*)1,0)==-1&&errno==EFAULT);
 return 0;
}
static int measurement(void) {
 for(int i=0;i<30;i++) { CHECK(operation()==0); }
 CHECK(pause_ns(6100000000ull)==0);
 struct snapshot a,b;CHECK(snapshot(&a)==0);
 for(int cohort=1;cohort<=3;cohort++) {
  CHECK(read_proc("/proc/allocstart")==0&&snapshot(&a)==0);
  for(int i=0;i<300;i++)CHECK(operation()==0);
  CHECK(pause_ns(6100000000ull)==0&&snapshot(&b)==0&&report("stat",cohort,300,&a,&b)==0);
#ifdef REQUIRE_FLAT
  for(unsigned i=0;i<a.count;i++) CHECK(a.live[i]==b.live[i]&&a.pages[i]==b.pages[i]);
  CHECK(a.large==b.large&&a.uaf==b.uaf);
#endif
 }
 puts("XNU STAT SEMANTICS PASS good=2 empty_path=1 EBADF=1 EFAULT=3 ENOENT=1");return 0;
}
int main(void) {
 setvbuf(stdout,0,_IONBF,0);target=open("/dev/null",O_RDWR);int result=target<0?-1:measurement();
 printf("XNU STAT %s\n",result?"FAIL":"PASS");sync();reboot(RB_POWER_OFF);return result!=0;
}
