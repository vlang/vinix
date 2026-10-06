// SPDX-License-Identifier: GPL-2.0-or-later
// Independent socket flags, descriptor retirement and retained-heap fixture.
@[translated; has_globals]
module socketfixture
#include <socket-native-abi.h>

@[typedef] struct C.FILE {}
@[typedef] struct C.pthread_t {}
@[typedef] struct C.vso_control { mut: buffer [24]char }
struct C.iovec { mut: iov_base voidptr iov_len usize }
struct C.msghdr { mut: msg_name voidptr msg_namelen u32 msg_iov &C.iovec msg_iovlen usize msg_control voidptr msg_controllen usize msg_flags i32 }
struct C.cmsghdr { mut: cmsg_len usize cmsg_level i32 cmsg_type i32 }
struct C.sockaddr_storage {}
struct C.in_addr { mut: s_addr u32 }
struct C.sockaddr_in { mut: sin_family u16 sin_port u16 sin_addr C.in_addr }
@[c_extern] __global C.errno i32
@[c_extern] __global C.stdout &C.FILE
__global ( baseline i32 socket_pair [2]i32 passed_file i32 udp [2]i32 udp_address C.sockaddr_in )
struct Heap { mut: size [32]i64 objects [32]i64 large i64 n i32 }
struct BlockingCall { mut: fd i32 use_msg i32 entered i32 done i32 result isize byte char }
struct SendingCall { mut: fd i32 use_control i32 entered i32 done i32 result isize }

fn C.printf(&char,...) i32
fn C.puts(&char) i32
fn C.pause() i32
fn C.memset(voidptr,i32,usize) voidptr
fn C.memcpy(voidptr,voidptr,usize) voidptr
fn C.memcmp(voidptr,voidptr,usize) i32
fn C.fopen(&char,&char) &C.FILE
fn C.fgets(&char,i32,&C.FILE) &char
fn C.sscanf(&char,&char,...) i32
fn C.fclose(&C.FILE) i32
fn C.ferror(&C.FILE) i32
fn C.sysconf(i32) i64
fn C.socketpair(i32,i32,i32,&i32) i32
fn C.socket(i32,i32,i32) i32
fn C.dup(i32) i32
fn C.dup2(i32,i32) i32
fn C.close(i32) i32
fn C.open(&char,i32,...) i32
fn C.access(&char,i32) i32
fn C.fcntl(i32,i32,...) i32
fn C.pthread_create(&C.pthread_t,voidptr,fn(voidptr)voidptr,voidptr) i32
fn C.pthread_join(C.pthread_t,voidptr) i32
fn C.vso_blocking_receive(voidptr) voidptr
fn C.vso_blocking_send(voidptr) voidptr
fn C.__atomic_store_n(&i32,i32,i32)
fn C.__atomic_load_n(&i32,i32) i32
fn C.usleep(u32) i32
fn C.recv(i32,voidptr,usize,i32) isize
fn C.send(i32,voidptr,usize,i32) isize
fn C.recvmsg(i32,&C.msghdr,i32) isize
fn C.sendmsg(i32,&C.msghdr,i32) isize
fn C.recvfrom(i32,voidptr,usize,i32,voidptr,&u32) isize
fn C.sendto(i32,voidptr,usize,i32,voidptr,u32) isize
fn C.CMSG_FIRSTHDR(&C.msghdr) &C.cmsghdr
fn C.CMSG_DATA(&C.cmsghdr) voidptr
fn C.CMSG_LEN(usize) usize
fn C.lseek(i32,i64,i32) i64
fn C.read(i32,voidptr,usize) isize
fn C.write(i32,voidptr,usize) isize
fn C.malloc(usize) voidptr
fn C.free(voidptr)
fn C.htonl(u32) u32
fn C.bind(i32,voidptr,u32) i32
fn C.getsockname(i32,voidptr,&u32) i32
fn C.setvbuf(&C.FILE,&char,i32,usize) i32

fn ck(ok bool,line i32) { unsafe { if !ok { C.printf(c'SOCKET IO FAIL line=%d errno=%d\n',line,C.errno);for { C.pause() } } } }
fn heap_snapshot(h &Heap) { unsafe {
 C.memset(h,0,sizeof(Heap));f:=C.fopen(c'/proc/slabinfo',c'r');ck(f!=nil, 20)
 mut line:=[256]char{};mut index:=i64(0);mut size:=i64(0);mut objects:=i64(0);mut pages:=i64(0)
 for C.fgets(&line[0],i32(sizeof(line)),f)!=nil {
  if C.sscanf(&line[0],c'size-%ld %ld %ld %ld',&index,&size,&objects,&pages)==4 && h.n<32 {
   h.size[h.n]=size;h.objects[h.n]=objects;h.n++
  } else if C.sscanf(&line[0],c'large - - %ld',&pages)==1 { h.large=pages }
 }
 ck(C.fclose(f)==0 && h.n>0, 27)
} }
fn sites(path &char,label &char) { unsafe {
 f:=C.fopen(path,c'r');ck(f!=nil, 31);mut line:=[512]char{}
 for C.fgets(&line[0],i32(sizeof(line)),f)!=nil { if label!=nil { C.printf(c'PERF-SITE variant=focus scenario=ops round=1 op=%s dir=/tmp %s',label,&line[0]) } }
 ck(C.ferror(f)==0 && C.fclose(f)==0, 33)
} }
fn measure(label &char,operation fn(),count i32) { unsafe {
 for i:=i32(0);i<20;i++ { operation() }
 mut before:=Heap{};mut after:=Heap{};heap_snapshot(&before);sites(c'/proc/allocstart',nil)
 for i:=i32(0);i<count;i++ { operation() }
 heap_snapshot(&after);sites(c'/proc/allocsites',label);ck(before.n==after.n, 40)
 mut kept:=(after.large-before.large)*C.sysconf(C._SC_PAGESIZE)
 for i:=i32(0);i<before.n;i++ {
  delta:=after.objects[i]-before.objects[i]
  C.printf(c'SOCKET IO HEAP op=%s size=%ld delta=%ld\n',label,before.size[i],delta)
  kept+=delta*before.size[i];if baseline==0 { ck(delta<32, 45) }
 }
 C.printf(c'SOCKET IO MEASURE op=%s count=%d retained=%ld large=%ld\n',label,count,kept,after.large-before.large)
 if baseline==0 { ck(kept<16384 && after.large-before.large<2, 48) }
} }
@[export:'vso_blocking_receive']
pub fn blocking_receive(data voidptr) voidptr { unsafe {
 b:=&BlockingCall(data);mut v:=C.iovec{iov_base:&b.byte,iov_len:1};mut m:=C.msghdr{msg_iov:&v,msg_iovlen:1}
 C.__atomic_store_n(&b.entered,1,5)
 b.result=if b.use_msg!=0 { C.recvmsg(b.fd,&m,0) } else { C.recv(b.fd,&b.byte,1,0) }
 C.__atomic_store_n(&b.done,1,5);return nil
} }
fn flag_tests() { unsafe {
 mut lost:=i32(0)
 for use_msg:=i32(0);use_msg<=1;use_msg++ {
  C.printf(c'SOCKET IO STEP receive mode=%d\n',use_msg)
  mut pair:=[2]i32{};ck(C.socketpair(C.AF_UNIX,C.SOCK_STREAM,0,&pair[0])==0, 64)
  alias:=C.dup(pair[1]);ck(alias>=0, 65)
  mut b:=BlockingCall{fd:pair[1],use_msg:use_msg};mut native_thread:=C.pthread_t{}
  ck(C.pthread_create(&native_thread,nil,C.vso_blocking_receive,&b)==0, 67)
  for C.__atomic_load_n(&b.entered,5)==0 { C.usleep(1000) }
  C.usleep(40000);ck(C.__atomic_load_n(&b.done,5)==0, 69)
  mut byte:=char(0)
  for i:=i32(0);i<100;i++ {
   ck(C.recv(alias,&byte,1,C.MSG_DONTWAIT)== -1 && C.errno==C.EAGAIN, 73)
   ck((C.fcntl(alias,C.F_GETFL)&C.O_NONBLOCK)==0, 74)
  }
  ck(C.__atomic_load_n(&b.done,5)==0, 76)
  ck(C.fcntl(alias,C.F_SETFL,i32(C.O_NONBLOCK))==0, 78)
  ck((C.fcntl(pair[1],C.F_GETFL)&C.O_NONBLOCK)!=0, 79)
  C.puts(c'SOCKET IO STEP receiver wake');ck(C.send(pair[0],c'x',1,0)==1, 80)
  ck(C.pthread_join(native_thread,nil)==0 && b.result==1 && b.byte==`x`, 81)
  if (C.fcntl(alias,C.F_GETFL)&C.O_NONBLOCK)==0 { lost++ }
  ck(C.close(alias)==0 && C.close(pair[0])==0 && C.close(pair[1])==0, 83)
 }
 C.printf(c'SOCKET IO FLAGS lost_updates=%d\n',lost);if baseline==0 { ck(lost==0, 85) }
 C.puts(c'SOCKET IO PASS: flags')
} }
@[export:'vso_blocking_send']
pub fn blocking_send(data voidptr) voidptr { unsafe {
 b:=&SendingCall(data);mut byte:=char(`s`);mut control:=C.vso_control{}
 mut v:=C.iovec{iov_base:&byte,iov_len:1};mut m:=C.msghdr{msg_iov:&v,msg_iovlen:1,msg_control:&control.buffer[0],msg_controllen:sizeof(control)}
 c:=C.CMSG_FIRSTHDR(&m);c.cmsg_level=C.SOL_SOCKET;c.cmsg_type=C.SCM_RIGHTS;c.cmsg_len=C.CMSG_LEN(sizeof(i32))
 C.memcpy(C.CMSG_DATA(c),&passed_file,sizeof(passed_file))
 C.__atomic_store_n(&b.entered,1,5)
 mut result:=isize(0)
 if b.use_control!=0 { result=C.sendmsg(b.fd,&m,0) } else { result=C.send(b.fd,&byte,1,0) }
 b.result=result
 C.__atomic_store_n(&b.done,1,5);return nil
} }
fn sender_flag_tests() { unsafe {
 mut lost:=i32(0);mut fill:=[65536]char{};C.memset(&fill[0],`f`,sizeof(fill))
 for controlled:=i32(0);controlled<=1;controlled++ {
  mut sockets:=[2]i32{};ck(C.socketpair(C.AF_UNIX,C.SOCK_STREAM,0,&sockets[0])==0, 106)
  alias:=C.dup(sockets[0]);ck(alias>=0, 107);mut n:=isize(0);mut chunks:=i32(0)
  for { n=C.send(sockets[0],&fill[0],sizeof(fill),C.MSG_DONTWAIT);if n<=0 { break };ck(n==isize(sizeof(fill)), 108);chunks++;ck(chunks<=16, 108) }
  ck(n== -1 && C.errno==C.EAGAIN && chunks==16, 109)
  mut b:=SendingCall{fd:sockets[0],use_control:controlled};mut native_thread:=C.pthread_t{}
  ck(C.pthread_create(&native_thread,nil,C.vso_blocking_send,&b)==0, 111)
  for C.__atomic_load_n(&b.entered,5)==0 { C.usleep(1000) }
  C.usleep(40000);ck(C.__atomic_load_n(&b.done,5)==0, 113)
  ck(C.fcntl(alias,C.F_SETFL,i32(C.O_NONBLOCK))==0, 114)
  mut byte:=char(0);ck(C.recv(sockets[1],&byte,1,0)==1 && byte==`f`, 115)
  ck(C.pthread_join(native_thread,nil)==0 && b.result==1, 116)
  if (C.fcntl(alias,C.F_GETFL)&C.O_NONBLOCK)==0 { lost++ }
  ck(C.close(alias)==0 && C.close(sockets[0])==0 && C.close(sockets[1])==0, 119)
 }
 C.printf(c'SOCKET IO SENDER FLAGS lost_updates=%d\n',lost);if baseline==0 { ck(lost==0, 121) }
} }
fn datagram() { unsafe {
 mut out:=[16]char{};C.memcpy(&out[0],c'socket-datagram',16);mut input:=[64]char{};mut addr:=C.sockaddr_storage{};mut length:=u32(sizeof(addr))
 ck(C.sendto(socket_pair[0],&out[0],sizeof(out),C.MSG_DONTWAIT,nil,0)==isize(sizeof(out)), 127)
 ck(C.recvfrom(socket_pair[1],&input[0],sizeof(input),C.MSG_DONTWAIT,voidptr(&addr),&length)==isize(sizeof(out)), 128)
 ck(C.memcmp(&out[0],&input[0],sizeof(out))==0, 129)
} }
fn message() { unsafe {
 mut a:=[6]char{};mut b:=[7]char{};C.memcpy(&a[0],c'first',sizeof(a));C.memcpy(&b[0],c'second',sizeof(b))
 mut input:=[64]char{};mut addr:=C.sockaddr_storage{}
 mut outv:=[C.iovec{iov_base:&a[0],iov_len:sizeof(a)},C.iovec{iov_base:&b[0],iov_len:sizeof(b)}]!
 mut inv:=[C.iovec{iov_base:&input[0],iov_len:sizeof(a)},C.iovec{iov_base:&input[sizeof(a)],iov_len:sizeof(b)}]!
 mut out:=C.msghdr{msg_iov:&outv[0],msg_iovlen:2};mut incoming:=C.msghdr{msg_name:&addr,msg_namelen:u32(sizeof(addr)),msg_iov:&inv[0],msg_iovlen:2}
 ck(C.sendmsg(socket_pair[0],&out,C.MSG_DONTWAIT)==isize(sizeof(a)+sizeof(b)), 137)
 ck(C.recvmsg(socket_pair[1],&incoming,C.MSG_DONTWAIT)==isize(sizeof(a)+sizeof(b)), 138)
 ck(C.memcmp(&input[0],&a[0],sizeof(a))==0 && C.memcmp(&input[sizeof(a)],&b[0],sizeof(b))==0, 139)
} }
fn rights() { unsafe {
 mut byte:=char(`r`);mut got:=char(0);mut control:=C.vso_control{};mut received:=C.vso_control{}
 mut outv:=C.iovec{iov_base:&byte,iov_len:1};mut inv:=C.iovec{iov_base:&got,iov_len:1}
 mut out:=C.msghdr{msg_iov:&outv,msg_iovlen:1,msg_control:&control.buffer[0],msg_controllen:sizeof(control)}
 mut c:=C.CMSG_FIRSTHDR(&out);ck(c!=nil, 147)
 c.cmsg_level=C.SOL_SOCKET;c.cmsg_type=C.SCM_RIGHTS;c.cmsg_len=C.CMSG_LEN(sizeof(i32));C.memcpy(C.CMSG_DATA(c),&passed_file,sizeof(passed_file))
 ck(C.sendmsg(socket_pair[0],&out,C.MSG_DONTWAIT)==1, 150)
 mut input:=C.msghdr{msg_iov:&inv,msg_iovlen:1,msg_control:&received.buffer[0],msg_controllen:sizeof(received)}
 ck(C.recvmsg(socket_pair[1],&input,C.MSG_DONTWAIT | C.MSG_CMSG_CLOEXEC)==1 && got==`r`, 152)
 c=C.CMSG_FIRSTHDR(&input);ck(c!=nil && c.cmsg_level==C.SOL_SOCKET && c.cmsg_type==C.SCM_RIGHTS, 153)
 mut fd:=i32(0);C.memcpy(&fd,C.CMSG_DATA(c),sizeof(fd));ck(fd>=0 && (C.fcntl(fd,C.F_GETFD)&C.FD_CLOEXEC)!=0, 154)
 ck(C.lseek(fd,0,C.SEEK_SET)==0, 155);mut text:=[5]char{};ck(C.read(fd,&text[0],sizeof(text))==isize(sizeof(text)) && C.memcmp(&text[0],c'owned',5)==0, 155)
 ck(C.close(fd)==0, 156)
} }
fn rejected_rights() { unsafe {
 mut byte:=char(`r`);mut control:=C.vso_control{};mut v:=C.iovec{iov_base:&byte,iov_len:1}
 mut m:=C.msghdr{msg_iov:&v,msg_iovlen:1,msg_control:&control.buffer[0],msg_controllen:sizeof(control)}
 c:=C.CMSG_FIRSTHDR(&m);c.cmsg_level=C.SOL_SOCKET;c.cmsg_type=C.SCM_RIGHTS;c.cmsg_len=C.CMSG_LEN(sizeof(i32));C.memcpy(C.CMSG_DATA(c),&passed_file,sizeof(passed_file))
 ck(C.sendmsg(socket_pair[0],&m,C.MSG_DONTWAIT)== -1 && C.errno==C.EAGAIN, 164)
} }
fn queue_retirement() { unsafe {
 mut byte:=char(`q`);mut got:=char(0);original:=passed_file
 for typ:=i32(C.SOCK_STREAM);typ<=C.SOCK_SEQPACKET;typ++ {
  if typ!=C.SOCK_STREAM && typ!=C.SOCK_DGRAM && typ!=C.SOCK_SEQPACKET { continue }
  mut sockets:=[2]i32{};ck(C.socketpair(C.AF_UNIX,typ,0,&sockets[0])==0, 171)
  passed_file=C.dup(original);ck(passed_file>=0, 172);mut control:=C.vso_control{};mut input_control:=C.vso_control{}
  mut v:=C.iovec{iov_base:&byte,iov_len:1};mut m:=C.msghdr{msg_iov:&v,msg_iovlen:1,msg_control:&control.buffer[0],msg_controllen:sizeof(control)}
  mut c:=C.CMSG_FIRSTHDR(&m);c.cmsg_level=C.SOL_SOCKET;c.cmsg_type=C.SCM_RIGHTS;c.cmsg_len=C.CMSG_LEN(sizeof(i32));C.memcpy(C.CMSG_DATA(c),&passed_file,sizeof(passed_file))
  ck(C.sendmsg(sockets[0],&m,C.MSG_DONTWAIT)==1 && C.close(passed_file)==0, 177)
  mut inv:=C.iovec{iov_base:&got,iov_len:1};mut input:=C.msghdr{msg_iov:&inv,msg_iovlen:1,msg_control:&input_control.buffer[0],msg_controllen:sizeof(input_control)}
  ck(C.recvmsg(sockets[1],&input,C.MSG_DONTWAIT | C.MSG_CMSG_CLOEXEC)==1 && got==`q`, 179)
  c=C.CMSG_FIRSTHDR(&input);ck(c!=nil && c.cmsg_type==C.SCM_RIGHTS, 180);mut received:=i32(0);C.memcpy(&received,C.CMSG_DATA(c),sizeof(received))
  ck(C.lseek(received,0,C.SEEK_SET)==0, 181);mut text:=[5]char{};ck(C.read(received,&text[0],5)==5 && C.memcmp(&text[0],c'owned',5)==0, 181);ck(C.close(received)==0, 181)
  C.memcpy(C.CMSG_DATA(C.CMSG_FIRSTHDR(&m)),&original,sizeof(original))
  ck(C.sendmsg(sockets[0],&m,C.MSG_DONTWAIT)==1 && C.recv(sockets[1],&got,1,0)==1, 184)
  ck(C.sendmsg(sockets[0],&m,C.MSG_DONTWAIT)==1, 185);input.msg_control=nil;input.msg_controllen=0
  ck(C.recvmsg(sockets[1],&input,C.MSG_DONTWAIT)==1 && (input.msg_flags&C.MSG_CTRUNC)!=0, 187)
  ck(C.sendmsg(sockets[0],&m,C.MSG_DONTWAIT)==1, 188)
  ck(C.close(sockets[0])==0 && C.close(sockets[1])==0, 189)
 }
 passed_file=original
} }
fn fault_tests() { unsafe {
 mut data:=[4]char{};C.memcpy(&data[0],c'abc',sizeof(data));mut got:=[4]char{};mut v:=C.iovec{iov_base:voidptr(1),iov_len:sizeof(data)}
 mut bad:=C.msghdr{msg_iov:&v,msg_iovlen:1}
 ck(C.sendmsg(socket_pair[0],&bad,C.MSG_DONTWAIT)== -1 && C.errno==C.EFAULT, 197)
 ck(C.recv(socket_pair[1],&got[0],sizeof(got),C.MSG_DONTWAIT)== -1 && C.errno==C.EAGAIN, 198)
 ck(C.send(socket_pair[0],&data[0],sizeof(data),0)==isize(sizeof(data)), 199)
 ck(C.recvmsg(socket_pair[1],&bad,C.MSG_DONTWAIT)== -1 && C.errno==C.EFAULT, 200)
 ck(C.recv(socket_pair[1],&got[0],sizeof(got),C.MSG_DONTWAIT)==isize(sizeof(got)) && C.memcmp(&data[0],&got[0],sizeof(data))==0, 201)
} }
fn udp_datagram() { unsafe {
 mut out:=[4]char{};C.memcpy(&out[0],c'udp',sizeof(out));mut input:=[16]char{};mut source:=C.sockaddr_in{};mut length:=u32(sizeof(source))
 ck(C.sendto(udp[0],&out[0],sizeof(out),C.MSG_DONTWAIT,voidptr(&udp_address),u32(sizeof(udp_address)))==isize(sizeof(out)), 207)
 ck(C.recvfrom(udp[1],&input[0],sizeof(input),C.MSG_DONTWAIT,voidptr(&source),&length)==isize(sizeof(out)), 208)
 ck(length==sizeof(source) && source.sin_family==C.AF_INET && C.memcmp(&input[0],&out[0],sizeof(out))==0, 209)
} }
@[export:'main']
pub fn run() i32 { unsafe {
 $if amd64 {
  console:=C.open(c'/dev/com1',C.O_WRONLY);ck(console>=0 && C.dup2(console,1)==1 && C.dup2(console,2)==2 && C.close(console)==0, 216)
 }
 C.setvbuf(C.stdout,nil,C._IONBF,0);baseline=if C.access(c'/socket-io-baseline',C.F_OK)==0 { 1 } else { 0 }
 C.puts(c'SOCKET IO STEP begin');flag_tests();ck(C.socketpair(C.AF_UNIX,C.SOCK_DGRAM,0,&socket_pair[0])==0, 219)
 passed_file=C.open(c'/rights-data',C.O_CREAT | C.O_RDWR,i32(0o600));ck(passed_file>=0 && C.write(passed_file,c'owned',5)==5, 220)
 C.puts(c'SOCKET IO STEP rights');rights();C.puts(c'SOCKET IO STEP faults');fault_tests();C.puts(c'SOCKET IO STEP queue');queue_retirement();C.puts(c'SOCKET IO STEP sender');sender_flag_tests();C.puts(c'SOCKET IO PASS: rights')
 measure(c'socket_datagram',datagram,1000);measure(c'socket_message',message,1000);measure(c'socket_rights',rights,200)
 full:=C.malloc(1024*1024);ck(full!=nil, 223);C.memset(full,`b`,1024*1024)
 ck(C.send(socket_pair[0],full,1024*1024,C.MSG_DONTWAIT)==1024*1024, 224)
 measure(c'socket_rights_rejected',rejected_rights,200)
 ck(C.recv(socket_pair[1],full,1024*1024,C.MSG_DONTWAIT)==1024*1024, 226);C.free(full)
 ck(C.close(socket_pair[0])==0 && C.close(socket_pair[1])==0 && C.close(passed_file)==0, 227)
 udp[0]=C.socket(C.AF_INET,C.SOCK_DGRAM,0);udp[1]=C.socket(C.AF_INET,C.SOCK_DGRAM,0);ck(udp[0]>=0 && udp[1]>=0, 228)
 udp_address=C.sockaddr_in{sin_family:u16(C.AF_INET),sin_addr:C.in_addr{s_addr:C.htonl(u32(C.INADDR_LOOPBACK))}}
 ck(C.bind(udp[1],voidptr(&udp_address),u32(sizeof(udp_address)))==0, 230)
 mut length:=u32(sizeof(udp_address));ck(C.getsockname(udp[1],voidptr(&udp_address),&length)==0, 231)
 measure(c'socket_udp',udp_datagram,1000);ck(C.close(udp[0])==0 && C.close(udp[1])==0, 232)
 C.puts(c'SOCKET IO PASS: growth');C.puts(c'SOCKET IO GUEST: PASS');for { C.pause() };return 0
} }
