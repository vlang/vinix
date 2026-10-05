// SPDX-License-Identifier: GPL-2.0-or-later
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <grp.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mount.h>
#include <sys/ioctl.h>
#include <time.h>
#include <sys/reboot.h>
#include <sys/stat.h>
#include <sys/statfs.h>
#include <sys/wait.h>
#include <unistd.h>
#include <sys/xattr.h>

#define ACCESS "system.posix_acl_access"
#define DEFAULT "system.posix_acl_default"
#define CHECK(c) do { if (!(c)) { printf("FAIL: ACL line %d errno=%d\n", __LINE__, errno); return 1; } } while (0)
#define ERROR(c,e) do { errno=0; CHECK((c)==-1 && errno==(e)); } while (0)
#define UNDEFINED UINT32_MAX
struct entry { uint16_t tag, perm; uint32_t id; };
struct acl { uint32_t version; struct entry entries[7]; };
static struct acl sample(void) {
 return (struct acl){2, {{1,7,UNDEFINED},{2,6,1000},{4,1,UNDEFINED},
  {8,4,2000},{8,2,3000},{16,6,UNDEFINED},{32,7,UNDEFINED}}};
}
static int child_access(const char *path, uid_t uid, gid_t gid,
                        const gid_t *groups, size_t count, int mode, int error)
{
 pid_t pid=fork(); CHECK(pid>=0);
 if (!pid) {
  CHECK(setgroups(count, groups)==0 && setgid(gid)==0 && setuid(uid)==0);
  if (error) { ERROR(access(path,mode),error); }
  else { CHECK(access(path,mode)==0); }
  _exit(0);
 }
 int status; CHECK(waitpid(pid,&status,0)==pid && WIFEXITED(status) && WEXITSTATUS(status)==0);
 return 0;
}
static int permission_cases(const char *directory)
{
 char path[128]; snprintf(path,sizeof(path),"%s/permissions",directory);
 int fd=open(path,O_CREAT|O_EXCL|O_RDWR,0600); CHECK(fd>=0);
 CHECK(fchown(fd,500,500)==0);
 struct acl acl=sample(), got;
 CHECK(fsetxattr(fd,ACCESS,&acl,sizeof(acl),XATTR_REPLACE)==0);
 CHECK(fsetxattr(fd,ACCESS,&acl,sizeof(acl),XATTR_CREATE)==0); // Linux ACLs ignore valid existence flags.
 struct stat st; CHECK(fstat(fd,&st)==0 && (st.st_mode&0777)==0767);
 CHECK(fgetxattr(fd,ACCESS,&got,sizeof(got))==sizeof(got) && !memcmp(&got,&acl,sizeof(got)));
 CHECK(child_access(path,500,999,NULL,0,R_OK|W_OK|X_OK,0)==0);
 CHECK(child_access(path,1000,999,NULL,0,R_OK|W_OK,0)==0);
 CHECK(child_access(path,1000,999,NULL,0,X_OK,EACCES)==0);
 CHECK(child_access(path,900,500,NULL,0,R_OK,EACCES)==0); // Matching group denies other fallback.
 CHECK(child_access(path,900,999,NULL,0,R_OK|W_OK|X_OK,0)==0);
 gid_t groups[]={2000,3000};
 CHECK(child_access(path,900,999,groups,1,R_OK,0)==0);
 CHECK(child_access(path,900,999,groups,2,R_OK|W_OK,EACCES)==0); // Group grants are not unioned.
 acl.entries[1].perm=0;
 CHECK(fsetxattr(fd,ACCESS,&acl,sizeof(acl),0)==0);
 CHECK(child_access(path,1000,999,NULL,0,R_OK,EACCES)==0); // Named user denies other fallback.
 acl=sample(); CHECK(fsetxattr(fd,ACCESS,&acl,sizeof(acl),0)==0);
 CHECK(fchmod(fd,0740)==0);
 CHECK(fgetxattr(fd,ACCESS,&got,sizeof(got))==sizeof(got));
 CHECK(got.entries[1].perm==6 && got.entries[5].perm==4 && got.entries[6].perm==0);
 CHECK(child_access(path,1000,999,NULL,0,R_OK,0)==0);
 CHECK(child_access(path,1000,999,NULL,0,W_OK,EACCES)==0);
 CHECK(fchmod(fd,0700)==0);
 CHECK(child_access(path,1000,999,NULL,0,R_OK,EACCES)==0);
 CHECK(fchmod(fd,0760)==0);
 CHECK(child_access(path,1000,999,NULL,0,R_OK|W_OK,0)==0);
 pid_t pid=fork(); CHECK(pid>=0);
 if (!pid) {
  CHECK(setgroups(0,NULL)==0 && setgid(999)==0 && setuid(1000)==0);
  ERROR(fsetxattr(fd,ACCESS,&acl,sizeof(acl),0),EPERM);
  ERROR(fremovexattr(fd,ACCESS),EPERM);
  CHECK(fremovexattr(fd,DEFAULT)==0);
  _exit(0);
 }
 int status; CHECK(waitpid(pid,&status,0)==pid && WIFEXITED(status) && WEXITSTATUS(status)==0);
 CHECK(fchmod(fd,0760)==0);
 pid=fork(); CHECK(pid>=0);
 if (!pid) {
  CHECK(setgroups(0,NULL)==0 && setgid(999)==0 && setreuid(1000,500)==0);
  ERROR(access(path,X_OK),EACCES);
  CHECK(faccessat(AT_FDCWD,path,X_OK,AT_EACCESS)==0);
  _exit(0);
 }
 CHECK(waitpid(pid,&status,0)==pid && WIFEXITED(status) && WEXITSTATUS(status)==0);
 CHECK(fchmod(fd,0640)==0 && access(path,R_OK|W_OK)==0);
 ERROR(access(path,X_OK),EACCES); // CAP_DAC_OVERRIDE still requires an execute bit.
 CHECK(fchmod(fd,02760)==0); // Root retains CAP_FSETID despite owning-group mismatch.
 CHECK(fstat(fd,&st)==0 && (st.st_mode&02000));
 pid=fork(); CHECK(pid>=0);
 if (!pid) {
  CHECK(setgroups(0,NULL)==0 && setgid(999)==0 && setuid(500)==0);
  CHECK(fsetxattr(fd,ACCESS,&acl,sizeof(acl),0)==0);
  CHECK(fstat(fd,&st)==0 && !(st.st_mode&02000));
  CHECK(fchmod(fd,02760)==0 && fstat(fd,&st)==0 && !(st.st_mode&02000));
  ERROR(fsetxattr(fd,ACCESS,&acl,sizeof(acl),4),EINVAL); // Internal policy flag is never accepted from userspace.
  _exit(0);
 }
 CHECK(waitpid(pid,&status,0)==pid && WIFEXITED(status) && WEXITSTATUS(status)==0);
 CHECK(fchmod(fd,02760)==0);
 pid=fork(); CHECK(pid>=0);
 if (!pid) {
  gid_t owning=500;
  CHECK(setgroups(1,&owning)==0 && setgid(999)==0 && setuid(500)==0);
  CHECK(fsetxattr(fd,ACCESS,&acl,sizeof(acl),0)==0);
  CHECK(fstat(fd,&st)==0 && (st.st_mode&02000));
  CHECK(fchmod(fd,02760)==0 && fstat(fd,&st)==0 && (st.st_mode&02000));
  _exit(0);
 }
 CHECK(waitpid(pid,&status,0)==pid && WIFEXITED(status) && WEXITSTATUS(status)==0);
 struct acl invalid=acl; invalid.version=1;
 ERROR(fsetxattr(fd,ACCESS,&invalid,sizeof(invalid),0),EINVAL);
 invalid=acl; invalid.entries[1].id=UNDEFINED;
 ERROR(fsetxattr(fd,ACCESS,&invalid,sizeof(invalid),0),EINVAL);
 invalid=acl; invalid.entries[5].perm=8;
 ERROR(fsetxattr(fd,ACCESS,&invalid,sizeof(invalid),0),EINVAL);
 ERROR(fsetxattr(fd,ACCESS,&acl,sizeof(acl)-1,0),EINVAL);
 ERROR(fsetxattr(fd,DEFAULT,&acl,sizeof(acl),0),EACCES);
 ERROR(fgetxattr(fd,DEFAULT,&got,sizeof(got)),ENODATA);
 CHECK(fremovexattr(fd,ACCESS)==0);
 ERROR(fgetxattr(fd,ACCESS,&got,sizeof(got)),ENODATA);
 struct { uint32_t version; struct entry entries[3]; } minimal={2,{{1,6,UNDEFINED},{4,4,UNDEFINED},{32,1,UNDEFINED}}};
 CHECK(fsetxattr(fd,ACCESS,&minimal,sizeof(minimal),0)==0);
 CHECK(fstat(fd,&st)==0 && (st.st_mode&0777)==0641);
 ERROR(fgetxattr(fd,ACCESS,&got,sizeof(got)),ENODATA);
 CHECK(fsetxattr(fd,ACCESS,&acl,sizeof(acl),0)==0);
 uint32_t empty=2; CHECK(fsetxattr(fd,ACCESS,&empty,sizeof(empty),0)==0);
 CHECK(fremovexattr(fd,ACCESS)==0 && fremovexattr(fd,DEFAULT)==0);
 CHECK(fsetxattr(fd,DEFAULT,&empty,sizeof(empty),0)==0 && fsetxattr(fd,DEFAULT,NULL,0,0)==0);
 ERROR(fgetxattr(fd,ACCESS,&got,sizeof(got)),ENODATA);
 CHECK(close(fd)==0);
 snprintf(path,sizeof(path),"%s/symlink",directory);
 CHECK(symlink("permissions",path)==0);
 ERROR(lsetxattr(path,ACCESS,&acl,sizeof(acl),0),EOPNOTSUPP);
 ERROR(lgetxattr(path,ACCESS,&got,sizeof(got)),EOPNOTSUPP);
 return 0;
}
static int inheritance(const char *directory, int after_reboot)
{
 char parent[128], path[160]; snprintf(parent,sizeof(parent),"%s/inherit",directory);
 struct acl acl=sample(),got; acl.entries[1].perm=7; acl.entries[5].perm=7; acl.entries[6].perm=0;
 struct stat st;
 if (!after_reboot) {
  CHECK(mkdir(parent,0777)==0 && chown(parent,0,654)==0 && chmod(parent,02777)==0);
  CHECK(setxattr(parent,DEFAULT,&acl,sizeof(acl),0)==0);
  mode_t previous=umask(0777);
  snprintf(path,sizeof(path),"%s/file",parent);
  int fd=open(path,O_CREAT|O_EXCL|O_RDWR,0666); CHECK(fd>=0 && close(fd)==0);
  snprintf(path,sizeof(path),"%s/dir",parent); CHECK(mkdir(path,0777)==0);
  snprintf(path,sizeof(path),"%s/link",parent); CHECK(symlink("file",path)==0);
  umask(previous);
 }
 CHECK(getxattr(parent,DEFAULT,&got,sizeof(got))==sizeof(got) && !memcmp(&got,&acl,sizeof(got)));
 snprintf(path,sizeof(path),"%s/file",parent);
 CHECK(stat(path,&st)==0 && (st.st_mode&07777)==0660 && st.st_gid==654);
 CHECK(getxattr(path,ACCESS,&got,sizeof(got))==sizeof(got));
 CHECK(got.entries[0].perm==6 && got.entries[1].perm==7 && got.entries[5].perm==6 && got.entries[6].perm==0);
 ERROR(getxattr(path,DEFAULT,&got,sizeof(got)),ENODATA);
 CHECK(child_access(path,1000,999,NULL,0,R_OK|W_OK,0)==0);
 snprintf(path,sizeof(path),"%s/dir",parent);
 CHECK(stat(path,&st)==0 && (st.st_mode&07777)==02770 && st.st_gid==654);
 CHECK(getxattr(path,DEFAULT,&got,sizeof(got))==sizeof(got) && !memcmp(&got,&acl,sizeof(got)));
 CHECK(child_access(path,1000,999,NULL,0,R_OK|W_OK|X_OK,0)==0);
 snprintf(path,sizeof(path),"%s/link",parent);
 ERROR(lgetxattr(path,ACCESS,&got,sizeof(got)),EOPNOTSUPP);
 return 0;
}
struct heap { long size[32],objects[32],large; int count; };
static int heap_snapshot(struct heap *h) {
 FILE *file=fopen("/proc/slabinfo","r"); CHECK(file);
 memset(h,0,sizeof(*h)); char line[256];
 while(fgets(line,sizeof(line),file)) { long label,size,objects,pages;
  if(sscanf(line,"size-%ld %ld %ld %ld",&label,&size,&objects,&pages)==4 && label==size && h->count<32) {
   h->size[h->count]=size; h->objects[h->count++]=objects;
  } else if(sscanf(line,"large - - %ld",&pages)==1) h->large=pages;
 } fclose(file); CHECK(h->count); return 0;
}
static int operations(int fd, const char *path, int repeats) {
 struct acl acl=sample(),got;
 for(int i=0;i<repeats;i++) {
  CHECK(fsetxattr(fd,ACCESS,&acl,sizeof(acl),0)==0);
  CHECK(fgetxattr(fd,ACCESS,&got,sizeof(got))==sizeof(got));
  CHECK(access(path,R_OK|W_OK)==0 && fchmod(fd,0640)==0);
  CHECK(fgetxattr(fd,ACCESS,&got,sizeof(got))==sizeof(got) && got.entries[1].perm==6 && got.entries[5].perm==4);
  CHECK(fremovexattr(fd,ACCESS)==0);
 }
 return 0;
}
static void tracking_begin(void) {
 int fd=open("/proc/allocstart",O_RDONLY);
 if(fd>=0) { char scratch[256]; while(read(fd,scratch,sizeof(scratch))>0) {} close(fd); }
}
static void tracking_sites(const char *backend) {
 FILE *file=fopen("/proc/allocsites","r"); if(!file) return;
 char line[512]; while(fgets(line,sizeof(line),file)) printf("PERF-SITE ACL backend=%s %s",backend,line); fclose(file);
}
static int measure(const char *directory,const char *backend) {
 char path[128]; snprintf(path,sizeof(path),"%s/repeat",directory);
 int fd=open(path,O_CREAT|O_EXCL|O_RDWR,0600); CHECK(fd>=0);
 CHECK(operations(fd,path,100)==0); struct heap a,b;
 tracking_begin();
 CHECK(heap_snapshot(&a)==0 && operations(fd,path,200)==0 && heap_snapshot(&b)==0 && a.count==b.count);
 tracking_sites(backend);
 int flat=b.large==a.large;
 for(int i=0;i<a.count;i++) { long kept=b.objects[i]-a.objects[i];
  printf("PERF-ACL %s class=%ld objects=%ld kept-bytes=%ld\n",backend,a.size[i],kept,kept*a.size[i]); flat &= kept==0 && a.size[i]==b.size[i];
 } printf("PERF-ACL %s large-pages=%ld\n",backend,b.large-a.large); CHECK(flat);
 CHECK(close(fd)==0); return 0;
}
struct race { int fd; const char *path; atomic_int stop,failed; };
static void *chmod_thread(void *argument) {
 struct race *r=argument;
 while(!atomic_load(&r->stop)) {
  if(fchmod(r->fd,0640)||fchmod(r->fd,0660)) { atomic_store(&r->failed,1); break; }
 } return NULL;
}
static int concurrent(const char *directory) {
 char path[128]; snprintf(path,sizeof(path),"%s/race",directory);
 int fd=open(path,O_CREAT|O_EXCL|O_RDWR,0600); CHECK(fd>=0);
 struct acl acl=sample(); acl.entries[6].perm=0;
 CHECK(fsetxattr(fd,ACCESS,&acl,sizeof(acl),0)==0);
 struct race r={.fd=fd,.path=path}; pthread_t thread;
 CHECK(pthread_create(&thread,NULL,chmod_thread,&r)==0);
 for(int i=0;i<500;i++) CHECK(access(path,R_OK)==0); // EIO would expose a mixed ACL/mode snapshot, even for root.
 atomic_store(&r.stop,1); CHECK(pthread_join(thread,NULL)==0 && !atomic_load(&r.failed));
 CHECK(close(fd)==0); return 0;
}
static int creation_failure(void) {
 const char *parent="/root/acl/too-large", *child="/root/acl/too-large/rejected";
 CHECK(mkdir(parent,0777)==0);
 struct { uint32_t version; struct entry entries[256]; } acl={.version=2};
 acl.entries[0]=(struct entry){1,7,UNDEFINED};
 for(int i=0;i<252;i++) acl.entries[i+1]=(struct entry){2,7,(uint32_t)(1000+i)};
 acl.entries[253]=(struct entry){4,7,UNDEFINED};
 acl.entries[254]=(struct entry){16,7,UNDEFINED};
 acl.entries[255]=(struct entry){32,7,UNDEFINED};
 CHECK(setxattr(parent,DEFAULT,&acl,sizeof(acl),0)==0);
 struct statfs a,b; CHECK(statfs(parent,&a)==0);
 for(int phase=0;phase<2;phase++) {
  struct heap before,after;
  if(phase) { tracking_begin(); CHECK(heap_snapshot(&before)==0); }
  for(int i=0;i<200;i++) ERROR(mkdir(child,0777),ENOSPC);
  struct timespec start,end,remaining={15,0}; CHECK(clock_gettime(CLOCK_MONOTONIC,&start)==0);
  while(nanosleep(&remaining,&remaining)==-1) CHECK(errno==EINTR);
  CHECK(clock_gettime(CLOCK_MONOTONIC,&end)==0 && end.tv_sec-start.tv_sec>=15);
  // Wait beyond node grace and the background reaper interval.
  if(phase) {
   CHECK(heap_snapshot(&after)==0 && before.count==after.count); tracking_sites("creation-failure");
   int flat=after.large==before.large;
   for(int i=0;i<before.count;i++) { long kept=after.objects[i]-before.objects[i];
    printf("PERF-ACL-FAILURE ext2 class=%ld objects=%ld kept-bytes=%ld\n",before.size[i],kept,kept*before.size[i]);
    flat &= kept==0 && before.size[i]==after.size[i];
   }
   printf("PERF-ACL-FAILURE ext2 large-pages=%ld\n",after.large-before.large); CHECK(flat);
  }
 }
 struct stat st; ERROR(stat(child,&st),ENOENT);
 CHECK(statfs(parent,&b)==0 && a.f_bfree==b.f_bfree && a.f_ffree==b.f_ffree);
 CHECK(removexattr(parent,DEFAULT)==0 && mkdir(child,0777)==0);
 return 0;
}
static int policy_errors(const char *directory) {
 char path[128]; snprintf(path,sizeof(path),"%s/policy",directory);
 int fd=open(path,O_CREAT|O_EXCL|O_RDWR,0600); CHECK(fd>=0); struct acl acl=sample();
 unsigned long flags=16; CHECK(ioctl(fd,0x40086602UL,&flags)==0);
 ERROR(fsetxattr(fd,ACCESS,&acl,sizeof(acl),0),EPERM); ERROR(fremovexattr(fd,ACCESS),EPERM);
 ERROR(fchmod(fd,0644),EPERM); flags=0; CHECK(ioctl(fd,0x40086602UL,&flags)==0 && close(fd)==0);
 snprintf(path,sizeof(path),"%s/readonly",directory); CHECK(mkdir(path,0700)==0);
 CHECK(mount("tmpfs",path,"tmpfs",MS_RDONLY,NULL)==0);
 ERROR(setxattr(path,DEFAULT,&acl,sizeof(acl),0),EROFS); ERROR(chmod(path,0700),EROFS);
 CHECK(umount(path)==0); return 0;
}
static int malformed(void) {
 const char *path="/root/acl-corrupt"; struct stat st;
 if(stat(path,&st)==-1 && errno==ENOENT) { puts("ACL: malformed fixture missing"); return 1; }
 struct acl got;
 ERROR(getxattr(path,ACCESS,&got,sizeof(got)),EIO);
 ERROR(access(path,R_OK),EIO);
 ERROR(open(path,O_RDONLY),EIO); // CAP_DAC_OVERRIDE cannot bypass malformed ACLs.
 ERROR(chmod(path,0600),EIO);
 ERROR(chmod(path,st.st_mode&07777),EIO);
 const char *directory="/root/acl-corrupt-dir", *missing="/root/acl-corrupt-dir/missing";
 ERROR(access(missing,R_OK),EIO); ERROR(mkdir(missing,0700),EIO);
 ERROR(open(missing,O_CREAT|O_RDWR,0600),EIO); ERROR(mknod(missing,S_IFREG|0600,0),EIO);
 ERROR(symlink("anything",missing),EIO); ERROR(unlink(missing),EIO);
 ERROR(rename("/root/acl/repeat",missing),EIO);
 CHECK(removexattr(directory,ACCESS)==0);
 CHECK(removexattr(path,ACCESS)==0); // Administrator can recover the file.
 CHECK(access(path,R_OK)==0);
 path="/root/acl-inconsistent";
 CHECK(stat(path,&st)==0 && getxattr(path,ACCESS,&got,sizeof(got))>0);
 ERROR(access(path,R_OK),EIO); ERROR(open(path,O_RDONLY),EIO);
 ERROR(chmod(path,st.st_mode&07777),EIO); ERROR(chmod(path,0640),EIO);
 CHECK(removexattr(path,ACCESS)==0 && access(path,R_OK)==0);
 return 0;
}
int main(void) {
 setbuf(stdout,NULL); puts("XATTR: START");
 int marker=open("/root/xattr-marker",O_RDONLY);
 if(marker>=0) {
  CHECK(close(marker)==0 && inheritance("/root/acl",1)==0);
  puts("ACL: REBOOT-PASS"); puts("XATTR: PASS"); reboot(RB_POWER_OFF); for(;;) pause();
 }
 CHECK(errno==ENOENT);
 CHECK(mkdir("/root/acl",0777)==0 && mkdir("/tmp/acl",0777)==0);
 CHECK(mount("tmpfs","/tmp/acl","tmpfs",0,NULL)==0 && chmod("/tmp/acl",0777)==0);
 CHECK(permission_cases("/tmp/acl")==0 && permission_cases("/root/acl")==0);
 CHECK(inheritance("/tmp/acl",0)==0 && inheritance("/root/acl",0)==0);
 CHECK(concurrent("/tmp/acl")==0 && concurrent("/root/acl")==0);
 CHECK(policy_errors("/tmp/acl")==0 && policy_errors("/root/acl")==0);
 CHECK(measure("/tmp/acl","tmpfs")==0 && measure("/root/acl","ext2")==0);
 CHECK(creation_failure()==0 && malformed()==0);
 marker=open("/root/xattr-marker",O_CREAT|O_EXCL|O_RDWR,0600); CHECK(marker>=0);
 CHECK(fsetxattr(marker,"user.binary","a",1,0)==0 && fsetxattr(marker,"trusted.secret","b",1,0)==0 &&
       fsetxattr(marker,"security.test","c",1,0)==0 && fsync(marker)==0 && close(marker)==0);
 sync(); puts("XATTR: REBOOT"); reboot(RB_AUTOBOOT); CHECK(0);
}
