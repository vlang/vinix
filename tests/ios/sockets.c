// SPDX-License-Identifier: GPL-2.0-or-later
// Identical Darwin ABI calls run against Apple's libraries and the V bridge.
typedef unsigned int socklen;
struct address4 { unsigned char length,family; unsigned short port; unsigned int address; unsigned char zero[8]; };
struct address6 { unsigned char length,family; unsigned short port; unsigned int flow; unsigned char address[16]; unsigned int scope; };
struct timeout { long seconds; int micros,padding; };
extern int socket(int,int,int),socketpair(int,int,int,int *),bind(int,const void *,socklen),connect(int,const void *,socklen);
extern int listen(int,int),accept(int,void *,socklen *),getsockname(int,void *,socklen *),getpeername(int,void *,socklen *);
extern int setsockopt(int,int,int,const void *,socklen),getsockopt(int,int,int,void *,socklen *),shutdown(int,int),close(int);
extern long send(int,const void *,unsigned long,int),recv(int,void *,unsigned long,int);
extern long sendto(int,const void *,unsigned long,int,const void *,socklen),recvfrom(int,void *,unsigned long,int,void *,socklen *);
extern int inet_pton(int,const char *,void *);
extern const char *inet_ntop(int,const void *,char *,socklen);
extern unsigned int inet_addr(const char *),htonl(unsigned int),ntohl(unsigned int);
extern unsigned short htons(unsigned short),ntohs(unsigned short);
extern int *__error(void);
extern int puts(const char *),printf(const char *,...),strcmp(const char *,const char *),memcmp(const void *,const void *,unsigned long);
extern void *memset(void *,int,unsigned long);
extern int usleep(unsigned int);
extern int pthread_create(unsigned long *,const void *,void *(*)(void *),void *),pthread_join(unsigned long,void **);
#define CHECK(condition,code) do { if(!(condition)) { printf("IOS-SOCKETS: failure %d errno %d\n",code,*__error()); return code; } } while(0)

static int timeout_on(int fd) {
 // Nonzero padding must never become Linux's high microsecond bits.
 struct timeout time={1,234567,0x12345678};
 if(setsockopt(fd,0xffff,0x1006,&time,sizeof time))return 1;
 struct timeout actual={0};socklen size=sizeof actual;
 if(getsockopt(fd,0xffff,0x1006,&actual,&size)||size!=16||actual.seconds!=1||actual.micros<234567||actual.micros>240000||actual.padding)return 2;
 return 0;
}
struct delayed_send { int fd,result; };
static void *send_later(void *argument) {
 struct delayed_send *job=argument;
 if(usleep(30000)||send(job->fd,"two",3,0)!=3)job->result=1;
 return 0;
}
static int split_receive(int sender,int receiver,int peek) {
 if(send(sender,"one",3,0)!=3)return 1;
 struct delayed_send job={sender,0};unsigned long thread;
 if(pthread_create(&thread,0,send_later,&job))return 2;
 char bytes[8]={0};long got=recv(receiver,bytes,6,0x40|(peek?2:0));
 if(pthread_join(thread,0)||job.result)return 3;
 if(got!=6||memcmp(bytes,"onetwo",6)){printf("IOS-SOCKETS: split peek%d got%ld errno%d\n",peek,got,*__error());return 4;}
 if(peek&&(recv(receiver,bytes,6,0x40)!=6||memcmp(bytes,"onetwo",6)))return 5;
 return 0;
}
static int partial_peek(int sender,int receiver) {
 struct timeout limit={0,40000,0};char bytes[8];
 if(setsockopt(receiver,0xffff,0x1006,&limit,16)||send(sender,"end",3,0)!=3)return 1;
 long partial=recv(receiver,bytes,8,0x40|2);if(partial!=-1||*__error()!=35){printf("IOS-SOCKETS: timeout peek got%ld errno%d\n",partial,*__error());return 2;}
 if(recv(receiver,bytes,3,0)!=3||memcmp(bytes,"end",3))return 3;
 return timeout_on(receiver);
}
static int tcp(int family) {
 int listener=socket(family,1,0);CHECK(listener>=0,10);
 int yes=1;CHECK(setsockopt(listener,0xffff,4,&yes,4)==0,11);
 unsigned char address[28]={0};socklen size=family==2?16:28;address[0]=(unsigned char)size;address[1]=(unsigned char)family;
 CHECK(inet_pton(family,family==2?"127.0.0.1":"::1",address+(family==2?4:8))==1,12);
 CHECK(bind(listener,address,size)==0&&listen(listener,8)==0,13);
 socklen length=size;CHECK(getsockname(listener,address,&length)==0&&length==size&&address[0]==size&&address[1]==family,14);
 CHECK(address[2]||address[3],15);
 int listening=0;length=4;CHECK(getsockopt(listener,0xffff,0x1008,&listening,&length)==0&&listening==1,16);
 int client=socket(family,1,0);CHECK(client>=0&&timeout_on(client)==0,17);
 CHECK(connect(client,address,size)==0,18);
 unsigned char peer[40];memset(peer,0xab,sizeof peer);length=1;
 int server=accept(listener,peer,&length);CHECK(server>=0&&length==size&&peer[0]==size&&peer[1]==0xab,19);
 CHECK(timeout_on(server)==0,20);
 length=sizeof peer;CHECK(getpeername(client,peer,&length)==0&&length==size&&memcmp(peer,address,size)==0,21);
 CHECK(setsockopt(client,6,1,&yes,4)==0,22);
 int linger[2]={1,2},actual_linger[2]={0};length=8;
 CHECK(setsockopt(client,0xffff,0x1080,linger,8)==0&&getsockopt(client,0xffff,0x1080,actual_linger,&length)==0&&length==8&&memcmp(linger,actual_linger,8)==0,77);
 CHECK(send(client,"abcdef",6,0)==6,23);
 char bytes[16]={0};CHECK(recv(server,bytes,3,2)==3&&memcmp(bytes,"abc",3)==0,24);
 CHECK(recv(server,bytes,6,0x40)==6&&memcmp(bytes,"abcdef",6)==0,25);
 CHECK(send(server,"reply",5,0x80000)==5&&recv(client,bytes,5,0x40)==5&&memcmp(bytes,"reply",5)==0,26);
 CHECK(split_receive(client,server,0)==0&&split_receive(client,server,1)==0&&partial_peek(client,server)==0,27);
 CHECK(send(client,"tail",4,0)==4&&shutdown(client,1)==0,29);
 CHECK(recv(server,bytes,8,0x40|2)==4&&memcmp(bytes,"tail",4)==0,83);
 CHECK(recv(server,bytes,8,0x40)==4&&memcmp(bytes,"tail",4)==0&&recv(server,bytes,1,0)==0,73);
 CHECK(close(server)==0&&close(client)==0&&close(listener)==0,28);
 return 0;
}
static int udp(void) {
 int server=socket(2,2,0),client=socket(2,2,0);CHECK(server>=0&&client>=0,30);
 struct address4 address={0,2,0,0,{0}};CHECK(inet_pton(2,"127.0.0.1",&address.address)==1,31);
 CHECK(bind(server,&address,16)==0,32);socklen length=16;
 CHECK(getsockname(server,&address,&length)==0&&address.length==16&&address.family==2&&length==16,33);
 for(unsigned capacity=0;capacity<24;capacity++) {
  unsigned char short_address[32];memset(short_address,0xab,sizeof short_address);length=capacity;
  CHECK(getsockname(server,short_address,&length)==0&&length==16,34);
  unsigned copied=capacity<16?capacity:16;
  CHECK(memcmp(short_address,&address,copied)==0,35);
  for(unsigned i=copied;i<sizeof short_address;i++)CHECK(short_address[i]==0xab,36);
 }
 CHECK(timeout_on(server)==0&&timeout_on(client)==0,37);
 char bytes[16];*__error()=0;CHECK(recv(server,bytes,1,0x80)==-1&&*__error()==35,38);
 CHECK(sendto(client,"datagram",8,0,&address,16)==8,39);
 struct address4 sender={0};length=16;
 CHECK(recvfrom(server,bytes,3,2,&sender,&length)==3&&memcmp(bytes,"dat",3)==0,74);length=16;
 CHECK(recvfrom(server,bytes,sizeof bytes,0,&sender,&length)==8&&length==16&&memcmp(bytes,"datagram",8)==0&&sender.family==2&&sender.length==16,40);
 CHECK(sendto(server,"return",6,0,&sender,16)==6,41);
 unsigned char truncated[24];memset(truncated,0xab,sizeof truncated);length=2;
 CHECK(recvfrom(client,bytes,sizeof bytes,0,truncated,&length)==6&&length==16&&truncated[0]==16&&truncated[1]==2&&truncated[2]==0xab,42);
 CHECK(memcmp(bytes,"return",6)==0,43);
 for(unsigned capacity=0;capacity<=8;capacity++) {
  unsigned char option[16];memset(option,0xab,sizeof option);length=capacity;
  CHECK(getsockopt(server,0xffff,0x1008,option,&length)==0&&length==(capacity<4?capacity:4),44);
  int expected=2;CHECK(memcmp(option,&expected,length)==0,45);
  for(unsigned i=length;i<sizeof option;i++)CHECK(option[i]==0xab,46);
 }
 int other=socket(2,2,0);CHECK(other>=0,47);
 CHECK(bind(other,&address,16)==-1&&*__error()==48,48);
 CHECK(bind(other,&address,15)==-1&&*__error()==22,49);
 CHECK(bind(other,&address,18)==-1&&*__error()==22,50);
 CHECK(getsockname(server,0,0)==-1&&*__error()==14,51);
 CHECK(sendto(client,"",0,0,&address,16)==0,78);length=16;
 // macOS can omit the source address for a cached empty loopback datagram.
 CHECK(recvfrom(server,bytes,0,2,&sender,&length)==0&&(length==0||length==16),79);length=16;
 CHECK(recvfrom(server,bytes,0,0,&sender,&length)==0&&(length==0||length==16),81);
 CHECK(recv(server,bytes,1,0x80)==-1&&*__error()==35,82);
 CHECK(close(other)==0&&close(client)==0&&close(server)==0,52);
 return 0;
}
static int unix_pair(void) {
 int pair[2];CHECK(socketpair(1,1,0,pair)==0,60);
 unsigned char address[32];memset(address,0xab,sizeof address);socklen length=sizeof address;
 CHECK(getsockname(pair[0],address,&length)==0&&length==16&&address[0]==16&&address[1]==1&&address[2]==0,61);
 CHECK(send(pair[0],"pair",4,0)==4,62);char data[8];CHECK(recv(pair[1],data,4,0x40)==4&&memcmp(data,"pair",4)==0,63);
 CHECK(split_receive(pair[0],pair[1],0)==0&&split_receive(pair[0],pair[1],1)==0,75);
 CHECK(partial_peek(pair[0],pair[1])==0&&recv(pair[1],data,0,0)==0,76);
 CHECK(close(pair[1])==0,64);
 CHECK(send(pair[0],"x",1,0x80000)==-1&&*__error()==32,65);
 CHECK(close(pair[0])==0,66);return 0;
}
static void *worker(void *context) {
 int *result=context;*result=tcp(2);
 if(!*result&&(recv(-1,context,0,0)!=-1||*__error()!=9))*result=80;
 return 0;
}
int main(void) {
 CHECK(htons(0x1234)==0x3412&&ntohs(0x3412)==0x1234,1);
 CHECK(htonl(0x12345678)==0x78563412&&ntohl(0x78563412)==0x12345678,2);
 unsigned char value[16];char text[64];
 CHECK(inet_pton(30,"2001:db8::1234",value)==1&&inet_ntop(30,value,text,sizeof text)&&strcmp(text,"2001:db8::1234")==0,3);
 CHECK(inet_pton(2,"127.0.0.1",value)==1&&inet_addr("127.0.0.1")==*(unsigned int *)(void*)value,4);
 CHECK(inet_pton(2,"invalid",value)==0&&inet_pton(31,"x",value)==-1&&*__error()==47,5);
 CHECK(!inet_ntop(30,value,text,2)&&*__error()==28,6);
 CHECK(accept(-1,0,0)==-1&&*__error()==9,7);
 int error=tcp(2);if(error)return error;
 error=tcp(30);if(error)return error;
 error=udp();if(error)return error;
 error=unix_pair();if(error)return error;
 unsigned long threads[8];int errors[8]={0};*__error()=12345;
 for(int i=0;i<8;i++)CHECK(pthread_create(&threads[i],0,worker,&errors[i])==0,70);
 for(int i=0;i<8;i++)CHECK(pthread_join(threads[i],0)==0&&errors[i]==0,71);
 CHECK(*__error()==12345,72);
 puts("IOS-SOCKETS: IPv4/IPv6 TCP, UDP, socketpair, truncation, timeouts, flags, errors and eight threads");return 0;
}
