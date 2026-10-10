// SPDX-License-Identifier: GPL-2.0-or-later
// Header-free Darwin ABI checks shared by the Mac and loaded iOS images.
#ifndef VINIX_IOS_SOCKET_MESSAGES_H
#define VINIX_IOS_SOCKET_MESSAGES_H
struct message_vector { void *base; unsigned long length; };
struct message_header {
 void *name; unsigned int name_length;
 struct message_vector *vectors; int vector_count;
 void *control; unsigned int control_length; int flags;
};
extern long sendmsg(int,const struct message_header *,int),recvmsg(int,struct message_header *,int);
extern int socket(int,int,int),socketpair(int,int,int,int *),bind(int,const void *,unsigned int);
extern int getsockname(int,void *,unsigned int *),setsockopt(int,int,int,const void *,unsigned int);
extern int getsockopt(int,int,int,void *,unsigned int *),close(int),pipe(int *);
extern long send(int,const void *,unsigned long,int),read(int,void *,unsigned long),write(int,const void *,unsigned long);
extern int inet_pton(int,const char *,void *),*__error(void),puts(const char *),printf(const char *,...);
extern int memcmp(const void *,const void *,unsigned long);
extern void *memcpy(void *,const void *,unsigned long),*memset(void *,int,unsigned long);
extern int pthread_create(unsigned long *,const void *,void *(*)(void *),void *),pthread_join(unsigned long,void **);
#define MESSAGE_CHECK(condition,code) do { if(!(condition)) { \
 printf("IOS-MESSAGES: failure %d errno %d\n",code,*__error()); return code; } } while(0)
_Static_assert(sizeof(struct message_header)==48,"Darwin msghdr");
_Static_assert(__builtin_offsetof(struct message_header,vectors)==16,"Darwin vectors");
_Static_assert(__builtin_offsetof(struct message_header,control)==32,"Darwin control");
_Static_assert(__builtin_offsetof(struct message_header,flags)==44,"Darwin flags");
_Static_assert(sizeof(struct message_vector)==16,"Darwin iovec");
static unsigned int message_word(const void *address) {
 unsigned int value;memcpy(&value,address,4);return value;
}
static void message_put(void *address,unsigned int value) { memcpy(address,&value,4); }
static int message_datagram(void) {
 int pair[2];MESSAGE_CHECK(socketpair(1,2,0,pair)==0,201);
 struct message_vector outgoing[2]={{"abc",3},{"defgh",5}};
 struct message_header sent={.vectors=outgoing,.vector_count=2,.flags=0x76543210},before=sent;
 *__error()=177;MESSAGE_CHECK(sendmsg(pair[0],&sent,0)==8&&*__error()==177,202);
 MESSAGE_CHECK(!memcmp(&sent,&before,48),203);
 unsigned char a[8],b[8],name[128],control[64];memset(a,0x5a,8);memset(b,0x5a,8);
 struct message_vector incoming[2]={{a+1,3},{b+1,2}};
 struct message_header got={.vectors=incoming,.vector_count=2,.flags=0x76543210};
 long peek=recvmsg(pair[1],&got,2);
 if(peek<0) {
  MESSAGE_CHECK(*__error()==102&&got.flags==0x76543210&&a[1]==0x5a&&b[1]==0x5a,204);
 } else {
  MESSAGE_CHECK(peek==5&&got.flags==0x12&&*__error()==177,204);
  MESSAGE_CHECK(!memcmp(a+1,"abc",3)&&!memcmp(b+1,"de",2),205);
 }
 *__error()=177;
 MESSAGE_CHECK(recvmsg(pair[1],&got,0)==5&&got.flags==0x10&&*__error()==177,274);
 MESSAGE_CHECK(!memcmp(a+1,"abc",3)&&!memcmp(b+1,"de",2)&&a[0]==0x5a&&a[4]==0x5a&&b[0]==0x5a&&b[3]==0x5a,205);
 MESSAGE_CHECK(sendmsg(pair[0],&sent,0)==8,275);
 incoming[1].length=5;memset(name,0x5a,128);memset(control,0x5a,64);
 got=(struct message_header){name,1,incoming,2,control,64,0x76543210};
 MESSAGE_CHECK(recvmsg(pair[1],&got,0)==8&&got.flags==0&&got.name_length==16&&got.control_length==0,206);
 MESSAGE_CHECK(!memcmp(b+1,"defgh",5)&&name[0]==16&&name[1]==0x5a&&control[0]==0x5a,207);
 MESSAGE_CHECK(got.name==name&&got.vectors==incoming&&got.vector_count==2&&got.control==control,208);
 before=got;MESSAGE_CHECK(recvmsg(pair[1],&got,0x80)==-1&&*__error()==35&&!memcmp(&got,&before,48),209);
 int bad_counts[3]={0,-1,1025};
 for(int i=0;i<3;i++) {
  got.vector_count=bad_counts[i];before=got;
  MESSAGE_CHECK(recvmsg(pair[1],&got,0)==-1&&*__error()==40&&!memcmp(&got,&before,48),210);
  MESSAGE_CHECK(sendmsg(pair[0],&got,0)==-1&&*__error()==40&&!memcmp(&got,&before,48),211);
 }
 got.vector_count=1;got.vectors=0;before=got;
 MESSAGE_CHECK(recvmsg(pair[1],&got,0)==-1&&*__error()==14&&!memcmp(&got,&before,48),212);
 got.vectors=incoming;before=got;
 MESSAGE_CHECK(recvmsg(-1,&got,0)==-1&&*__error()==9&&!memcmp(&got,&before,48),213);
 MESSAGE_CHECK(recvmsg(-1,0,0)==-1&&*__error()==14&&sendmsg(-1,0,0)==-1&&*__error()==14,214);
 MESSAGE_CHECK(sendmsg(pair[0],&sent,0)==8,215);
 incoming[0].length=0;got=(struct message_header){.vectors=incoming,.vector_count=1};
 MESSAGE_CHECK(recvmsg(pair[1],&got,0)==0&&got.flags==0x10,216);
 incoming[0].length=3;before=got;
 MESSAGE_CHECK(recvmsg(pair[1],&got,0x80)==-1&&*__error()==35&&!memcmp(&got,&before,48),217);
 MESSAGE_CHECK(sendmsg(pair[0],&sent,0)==8,218);
 got=(struct message_header){0,128,incoming,2,0,64,0x76543210};*__error()=177;
 MESSAGE_CHECK(recvmsg(pair[1],&got,0x80)==8&&got.name_length==128&&got.control_length==64&&got.flags==0x80&&*__error()==177,219);
 struct message_vector many[1024]={0};many[0]=(struct message_vector){a,1};
 got=(struct message_header){.vectors=many,.vector_count=1024};
 MESSAGE_CHECK(send(pair[0],"z",1,0)==1&&recvmsg(pair[1],&got,0)==1&&a[0]=='z'&&got.flags==0,220);
 MESSAGE_CHECK(close(pair[0])==0&&close(pair[1])==0,221);
 return 0;
}
static int message_rights(unsigned int capacity) {
 int pair[2],descriptors[2];MESSAGE_CHECK(socketpair(1,2,0,pair)==0&&pipe(descriptors)==0,230);
 unsigned char ancillary[21]={0},out[65];
 // Deliberately unaligned control storage; no typed cmsghdr/timeval loads.
 message_put(ancillary+1,20);message_put(ancillary+5,0xffff);message_put(ancillary+9,1);
 memcpy(ancillary+13,descriptors,8);
 struct message_vector vector={"fd",2};
 struct message_header header={.vectors=&vector,.vector_count=1,.control=ancillary+1,.control_length=20};
 struct message_header before=header;
 *__error()=177;MESSAGE_CHECK(sendmsg(pair[0],&header,0)==2&&*__error()==177&&!memcmp(&header,&before,48),231);
 char data[4];vector=(struct message_vector){data,4};memset(out,0x5a,65);
 header=(struct message_header){.vectors=&vector,.vector_count=1,.control=out+1,.control_length=capacity};
 MESSAGE_CHECK(recvmsg(pair[1],&header,0)==2&&!memcmp(data,"fd",2)&&*__error()==177,232);
 unsigned int used=capacity<20?capacity:20;
 MESSAGE_CHECK(header.control_length==used&&header.flags==((capacity&&capacity<20)?0x20:0)&&out[0]==0x5a,233);
 for(unsigned int i=1+used;i<65;i++)MESSAGE_CHECK(out[i]==0x5a,234);
 unsigned int prefix[3]={20,0xffff,1};unsigned int prefix_size=used<12?used:12;
 MESSAGE_CHECK(!memcmp(out+1,prefix,prefix_size),235);
 int received[2]={-1,-1};
 for(int i=0;i<2;i++)if(used>=16+4*(unsigned int)i)received[i]=(int)message_word(out+13+4*i);
 if(received[0]>=0) {
  MESSAGE_CHECK(write(descriptors[1],"R",1)==1&&read(received[0],data,1)==1&&data[0]=='R',236);
  MESSAGE_CHECK(close(received[0])==0,237);
 }
 if(received[1]>=0) {
  MESSAGE_CHECK(write(received[1],"W",1)==1&&read(descriptors[0],data,1)==1&&data[0]=='W',238);
  MESSAGE_CHECK(close(received[1])==0,239);
 }
 MESSAGE_CHECK(close(pair[0])==0&&close(pair[1])==0&&close(descriptors[0])==0&&close(descriptors[1])==0,240);
 return 0;
}
static int message_udp(int family) {
 unsigned char address[28]={0},peer[33],control[65],data[12];unsigned int length=family==2?16:28;
 address[0]=(unsigned char)length;address[1]=(unsigned char)family;
 MESSAGE_CHECK(inet_pton(family,family==2?"127.0.0.1":"::1",address+(family==2?4:8))==1,250);
 int server=socket(family,2,0),client=socket(family,2,0);
 MESSAGE_CHECK(server>=0&&client>=0&&bind(server,address,length)==0&&getsockname(server,address,&length)==0,251);
 struct message_vector outgoing[2]={{"abc",3},{"defgh",5}},incoming[2]={{data+1,3},{data+5,5}};
 struct message_header sent={address,length,outgoing,2,0,0,0};
 MESSAGE_CHECK(sendmsg(client,&sent,0)==8,252);memset(data,0x5a,12);memset(peer,0x5a,33);memset(control,0x5a,65);
 struct message_header got={peer+1,1,incoming,2,control+1,64,0};*__error()=177;
 MESSAGE_CHECK(recvmsg(server,&got,0)==8&&got.name_length==length&&got.control_length==0&&got.flags==0&&*__error()==177,253);
 MESSAGE_CHECK(!memcmp(data+1,"abc",3)&&!memcmp(data+5,"defgh",5)&&data[0]==0x5a&&data[4]==0x5a&&data[10]==0x5a,254);
 MESSAGE_CHECK(peer[0]==0x5a&&peer[1]==length&&peer[2]==0x5a&&control[0]==0x5a&&control[1]==0x5a,255);
 MESSAGE_CHECK(sendmsg(client,&sent,0)==8,256);incoming[1].length=2;got.name_length=32;got.control_length=64;
 MESSAGE_CHECK(recvmsg(server,&got,0)==5&&got.flags==0x10&&got.name_length==length&&peer[2]==family,257);
 int yes=1;int enabled=setsockopt(server,0xffff,0x400,&yes,4);
 if(enabled) {
  MESSAGE_CHECK(*__error()==42,258);
  puts("IOS-MESSAGES: native backend reports SO_TIMESTAMP unsupported");
 } else {
  int actual=0;unsigned int size=4;
  MESSAGE_CHECK(getsockopt(server,0xffff,0x400,&actual,&size)==0&&size==4&&actual==0x400,259);
  unsigned int capacities[8]={0,1,11,12,13,27,28,64};incoming[1].length=5;
  for(int c=0;c<8;c++) {
   unsigned int capacity=capacities[c];memset(control,0x5a,65);got.name_length=32;got.control_length=capacity;
   MESSAGE_CHECK(sendmsg(client,&sent,0)==8&&recvmsg(server,&got,0)==8,260);
   unsigned int used=capacity<28?capacity:28;
   MESSAGE_CHECK(got.control_length==used&&got.flags==((capacity&&capacity<28)?0x20:0)&&control[0]==0x5a,261);
   for(unsigned int i=used+1;i<65;i++)MESSAGE_CHECK(control[i]==0x5a,262);
   unsigned int prefix[3]={28,0xffff,2};MESSAGE_CHECK(!memcmp(control+1,prefix,used<12?used:12),263);
   if(used==28) {
    long seconds;memcpy(&seconds,control+13,8);
    MESSAGE_CHECK(seconds>0&&message_word(control+21)<1000000&&message_word(control+25)==0,264);
   }
  }
 }
 MESSAGE_CHECK(close(server)==0&&close(client)==0,265);return 0;
}
static void *message_worker(void *argument) {
 int *result=argument;*result=0;
 for(int i=0;i<8&&!*result;i++) {
  *result=message_datagram();if(!*result)*result=message_rights(20);
 }
 if(!*result&&(recvmsg(-1,0,0)!=-1||*__error()!=14))*result=270;
 return 0;
}
static int socket_message_checks(void) {
 int result=message_datagram();if(result)return result;
 unsigned int capacities[6]={0,1,12,13,16,20};
 for(int i=0;i<6;i++){result=message_rights(capacities[i]);if(result)return result;}
 result=message_udp(2);if(result)return result;
 result=message_udp(30);if(result)return result;
 unsigned long threads[8];int results[8]={0};*__error()=12345;
 for(int i=0;i<8;i++)MESSAGE_CHECK(pthread_create(&threads[i],0,message_worker,&results[i])==0,271);
 for(int i=0;i<8;i++)MESSAGE_CHECK(pthread_join(threads[i],0)==0&&results[i]==0,272);
 MESSAGE_CHECK(*__error()==12345,273);
 puts("IOS-MESSAGES: scatter/gather, guarded truncation, real descriptor passing, timestamp capability and eight threads");
 return 0;
}
#undef MESSAGE_CHECK
#endif
