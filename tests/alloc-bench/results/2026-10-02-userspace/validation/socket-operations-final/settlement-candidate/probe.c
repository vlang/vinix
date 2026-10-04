#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mount.h>
#include <sys/socket.h>
#include <sys/sysinfo.h>
#include <unistd.h>
static int pair[2], passed_fd;
static unsigned char sent[8192], received[8192];
static int operation(unsigned kind)
{
 struct iovec input={sent,kind==4 ? sizeof sent : 1},output={received,kind==4 ? sizeof received : 1};
 struct msghdr write_msg={.msg_iov=&input,.msg_iovlen=1},read_msg={.msg_iov=&output,.msg_iovlen=1};
 if(kind==0) return recvmsg(pair[0],&read_msg,MSG_DONTWAIT)==-1 && errno==EAGAIN ? 0:1;
 if(kind==1) return recvfrom(pair[0],received,1,MSG_DONTWAIT,NULL,NULL)==-1 && errno==EAGAIN ? 0:1;
 if(kind==2) return sendto(pair[0],sent,1,0,NULL,0)==1 && recvfrom(pair[1],received,1,0,NULL,NULL)==1 ? 0:1;
 if(kind==3 || kind==4) return sendmsg(pair[0],&write_msg,0)==(ssize_t)input.iov_len && recvmsg(pair[1],&read_msg,0)==(ssize_t)input.iov_len ? 0:1;
 if(kind==5) {
  struct sockaddr_storage address;socklen_t length=sizeof address;
  if(getsockname(pair[0],(struct sockaddr*)&address,&length))return 1;
  length=sizeof address;return getpeername(pair[0],(struct sockaddr*)&address,&length)!=0;
 }
 if(kind==13 || kind==14 || kind==15) {
  int temporary[2]; if(socketpair(AF_UNIX,kind==14?SOCK_DGRAM:SOCK_STREAM,0,temporary)) return 1;
  int saved0=pair[0],saved1=pair[1];pair[0]=temporary[0];pair[1]=temporary[1];
  int result=0;
  if(kind==15) { close(pair[1]);struct iovec bytes={sent,1};struct msghdr msg={.msg_iov=&bytes,.msg_iovlen=1};result=sendmsg(pair[0],&msg,MSG_NOSIGNAL)!=-1 || errno!=EPIPE; }
  else { result=operation(16);close(pair[1]); }
  close(pair[0]);pair[0]=saved0;pair[1]=saved1;return result;
 }
 union {struct cmsghdr alignment; char bytes[CMSG_SPACE(sizeof(int))];} out_control,in_control;
 memset(&out_control,0,sizeof out_control);memset(&in_control,0,sizeof in_control);
 write_msg.msg_control=out_control.bytes;write_msg.msg_controllen=sizeof out_control.bytes;
 struct cmsghdr *c=CMSG_FIRSTHDR(&write_msg);c->cmsg_len=CMSG_LEN(sizeof(int));c->cmsg_level=SOL_SOCKET;c->cmsg_type=SCM_RIGHTS;memcpy(CMSG_DATA(c),&passed_fd,sizeof passed_fd);
 read_msg.msg_control=in_control.bytes;read_msg.msg_controllen=sizeof in_control.bytes;
 if(sendmsg(pair[0],&write_msg,MSG_NOSIGNAL)!=1)return 1;
 if(kind==16) return 0;
 if(kind==11 || kind==12)return read(pair[1],received,1)!=1;
 if(kind==9 || kind==10) {read_msg.msg_control=NULL;read_msg.msg_controllen=0;return recvmsg(pair[1],&read_msg,0)!=1 || !(read_msg.msg_flags&MSG_CTRUNC);}
 if(kind==17) {if(recvmsg(pair[1],&read_msg,MSG_PEEK)!=1)return 1;c=CMSG_FIRSTHDR(&read_msg);if(!c)return 1;int peek_fd=-1;memcpy(&peek_fd,CMSG_DATA(c),sizeof peek_fd);if(peek_fd<0 || close(peek_fd))return 1;memset(in_control.bytes,0,sizeof in_control.bytes);read_msg.msg_controllen=sizeof in_control.bytes;}
 if(recvmsg(pair[1],&read_msg,0)!=1)return 1;
 c=CMSG_FIRSTHDR(&read_msg);if(!c || c->cmsg_type!=SCM_RIGHTS)return 1;
 int fd=-1;memcpy(&fd,CMSG_DATA(c),sizeof fd);return fd<0 || close(fd);
}
static void slab(unsigned kind,const char *phase)
{
 char buffer[4096];int fd=open("/proc/slabinfo",O_RDONLY);printf("SOCKET-OPS-SLAB-BEGIN operation=%u phase=%s\n",kind,phase);
 if(fd>=0){ssize_t n;while((n=read(fd,buffer,sizeof buffer))>0)fwrite(buffer,1,(size_t)n,stdout);close(fd);}
 printf("SOCKET-OPS-SLAB-END operation=%u phase=%s\n",kind,phase);
}
int main(void)
{
 setbuf(stdout,NULL);setbuf(stderr,NULL);int console=open("/dev/console",O_WRONLY);if(console>=0){dup2(console,1);dup2(console,2);close(console);}
 mount("proc","/proc","proc",0,NULL);alarm(600);passed_fd=open("/dev/null",O_RDONLY);memset(sent,0x61,sizeof sent);
 const char *names[]={"empty_recvmsg","empty_recvfrom","sendto_recvfrom","sendmsg_recvmsg","large_sendmsg_recvmsg","socket_names","stream_fd_sendmsg_recvmsg","datagram_fd_sendmsg_recvmsg","seqpacket_fd_sendmsg_recvmsg","stream_control_truncate","datagram_control_truncate","stream_read_discards_rights","datagram_read_discards_rights","stream_close_queued_rights","datagram_close_queued_rights","closed_stream_send","stream_fd_sendmsg_recvmsg_duplicate","stream_fd_peek_receive"};
 int result=0,completed=0;
 for(unsigned kind=11;kind<16;++kind){int type=(kind==7 || kind==10 || kind==12)?SOCK_DGRAM:kind==8?SOCK_SEQPACKET:SOCK_STREAM;if(socketpair(AF_UNIX,type,0,pair)){perror("socketpair");result=1;break;}
  for(unsigned warm=0;warm<64;++warm)if(operation(kind)){printf("SOCKET-OPS-FAIL kind=%u warm=%u errno=%d\n",kind,warm,errno);result=1;goto done;}
  slab(kind,"before");struct sysinfo before,after;sysinfo(&before);
  for(unsigned i=0;i<8192;++i)if(operation(kind)){printf("SOCKET-OPS-FAIL kind=%u i=%u errno=%d\n",kind,i,errno);result=1;goto done;}
  sysinfo(&after);printf("SOCKET-OPS-RESULT operation=%u name=%s calls=8192 before=%lu after=%lu retained=%ld\n",kind,names[kind],before.freeram,after.freeram,(long)(before.freeram-after.freeram));slab(kind,"after");
  sleep(1);struct sysinfo settled;sysinfo(&settled);printf("SOCKET-OPS-SETTLED operation=%u name=%s calls=8192 retained=%ld\n",kind,names[kind],(long)(before.freeram-settled.freeram));slab(kind,"settled");
  close(pair[0]);close(pair[1]);completed++;}
 done:printf("SOCKET-OPS-DONE result=%d completed=%d\n",result,completed);for(;;)sleep(1);
}
