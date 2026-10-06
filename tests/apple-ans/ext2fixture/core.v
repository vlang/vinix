// SPDX-License-Identifier: GPL-2.0-or-later
// Independent byte image, corruption oracle and persistent-write goldens.
@[translated]
@[has_globals]
module ext2fixture
#include "ext2-fixture-v-abi.h"
@[typedef] struct C.ext2_fixture_const_p {}
struct C.e2_fs { mut: opened u32 }
struct C.image { mut: data &u8 bytes usize bs u32 isize u32 reads u32 writes u32 fail i32 fail_write i32 fs C.e2_fs }
type Reader = fn(voidptr,voidptr,u64,usize) i32
type Writer = fn(voidptr,C.ext2_fixture_const_p,u64,usize) i32
fn C.assert(bool)
fn C.calloc(usize,usize) voidptr
fn C.malloc(usize) voidptr
fn C.free(voidptr)
fn C.memset(voidptr,i32,usize) voidptr
fn C.memcpy(voidptr,voidptr,usize) voidptr
fn C.memcmp(voidptr,voidptr,usize) i32
fn C.strlen(&char) usize
fn C.strcmp(&char,&char) i32
fn C.printf(&char,...) i32
fn C.puts(&char) i32
fn C.fflush(voidptr) i32
fn C.pause() i32
fn C.ext2_fixture_read(voidptr,voidptr,u64,usize) i32
fn C.ext2_fixture_write(voidptr,C.ext2_fixture_const_p,u64,usize) i32
fn C.e2_u16(&u8) u16
fn C.e2_u32(&u8) u32
fn C.e2_lookup(voidptr,u32,&char,usize,&u32,&u8) i32
fn C.vinix_ext2_context_size() usize
fn C.vinix_ext2_open(voidptr,usize,Reader,voidptr,u64) i32
fn C.vinix_ext2_open_rw(voidptr,usize,Reader,Writer,voidptr,u64) i32
fn C.vinix_ext2_stat(voidptr,u32,&u64) i32
fn C.vinix_ext2_read(voidptr,u32,voidptr,u64,usize) i64
fn C.vinix_ext2_write(voidptr,u32,voidptr,u64,usize) i64
fn C.vinix_ext2_next(voidptr,u32,&u64,&u32,&char,usize) i32
fn C.vinix_ext2_begin_write(voidptr) i32
fn C.vinix_ext2_close_clean(voidptr) i32
fn C.vinix_ext2_create(voidptr,u32,&char,usize,u32,&u32) i32
fn C.vinix_ext2_truncate(voidptr,u32,u64) i32
fn C.vinix_ext2_link(voidptr,u32,&char,usize,u32) i32
fn C.vinix_ext2_rename(voidptr,u32,&char,usize,u32,&char,usize,i32) i32
fn C.vinix_ext2_symlink(voidptr,u32,&char,usize,&char,usize,&u32) i32
fn C.vinix_ext2_unlink(voidptr,u32,&char,usize,i32) i32
@[c_extern] __global (
 C.E2_REGULAR u32
 C.E2_DIRECTORY u32
 C.E2_IO i32
 C.E2_ROFS i32
)
fn p16(p &u8,value u32) { unsafe { p[0]=u8(value); p[1]=u8(value>>8) } }
fn p32(p &u8,value u32) { unsafe { p16(p,value); p16(p+2,value>>16) } }
@[export: 'ext2_fixture_read']
pub fn disk_read(cookie voidptr,buffer voidptr,offset u64,count usize) i32 { unsafe {
 im:=&C.image(cookie); C.assert(offset<=im.bytes && count<=im.bytes-offset); im.reads++
 if im.fail!=0 { return -1 }; C.memcpy(buffer,im.data+offset,count); return 0
} }
@[export: 'ext2_fixture_write']
pub fn disk_write(cookie voidptr,native_buffer C.ext2_fixture_const_p,offset u64,count usize) i32 { unsafe {
 im:=&C.image(cookie); C.assert(offset<=im.bytes && count<=im.bytes-offset); im.writes++
 if im.fail_write!=0 { return -1 }; mut buffer:=voidptr(nil); C.memcpy(&buffer,&native_buffer,sizeof(buffer)); C.memcpy(im.data+offset,buffer,count); return 0
} }
fn inode(im &C.image,n u32) &u8 { unsafe { return im.data+5*im.bs+(n-1)*im.isize } }
fn set_inode(im &C.image,n u32,mode u32,size u64,block u32) { unsafe {
 p:=inode(im,n); C.memset(p,0,im.isize); p16(p,mode); p16(p+26,1); p32(p+4,u32(size))
 if (mode&0xf000)==u32(C.E2_REGULAR) { p32(p+108,u32(size>>32)) }; p32(p+28,if block!=0 { im.bs/512 } else { u32(0) }); p32(p+40,block)
} }
fn dirent(p &u8,number u32,record u32,kind u32,name &char) { unsafe {
 p32(p,number); p16(p+4,record); p[6]=u8(C.strlen(name)); p[7]=u8(kind); C.memcpy(p+8,name,C.strlen(name))
} }
@[export: 'ext2_fixture_setup']
pub fn setup(im &C.image,bs u32,inode_size u32) { unsafe {
 C.memset(im,0,sizeof(C.image)); im.bs=bs; im.isize=inode_size; im.bytes=256*bs; im.data=&u8(C.calloc(1,im.bytes)); C.assert(im.data!=nil)
 s:=im.data+1024; p32(s,32); p32(s+4,256); p32(s+20,if bs==1024 { u32(1) } else { u32(0) }); p32(s+24,if bs==1024 { u32(0) } else if bs==2048 { u32(1) } else { u32(2) })
 p32(s+28,C.e2_u32(s+24)); p32(s+32,256); p32(s+36,256); p32(s+40,32); p16(s+56,0xef53); p16(s+58,1); p32(s+76,1); p16(s+88,inode_size)
 p32(s+92,0x38); p32(s+96,2); p32(s+100,3); g:=im.data+(if bs==1024 { u32(2) } else { u32(1) })*bs; p32(g+8,5)
 set_inode(im,2,0x41ed,bs,16); set_inode(im,12,0x81ed,3*bs,17); p32(inode(im,12)+48,18)
 p16(inode(im,12)+2,0x5678); p16(inode(im,12)+120,0x1234); p16(inode(im,12)+24,0xcdef); p16(inode(im,12)+122,0x89ab)
 p32(inode(im,12)+8,123); p32(inode(im,12)+16,456); p32(inode(im,12)+12,789); C.memset(im.data+17*bs,0x31,bs); C.memset(im.data+18*bs,0x72,bs)
 set_inode(im,13,0xa1ff,10,0); C.memcpy(inode(im,13)+40,c'/sbin/init',10); set_inode(im,14,0xa1ff,100,19); C.memset(im.data+19*bs,97,100)
 d:=im.data+16*bs; dirent(d,2,12,2,c'.'); dirent(d+12,2,12,2,c'..'); dirent(d+24,12,16,1,c'kernel'); dirent(d+40,0,12,0,c''); dirent(d+52,13,12,7,c'fast'); dirent(d+64,14,bs-64,7,c'long')
 C.assert(C.vinix_ext2_context_size()==sizeof(im.fs)); C.assert(C.vinix_ext2_open(&im.fs,sizeof(im.fs),C.ext2_fixture_read,im,im.bytes)==0)
} }
@[export: 'ext2_fixture_destroy']
pub fn destroy(im &C.image) { unsafe { C.free(im.data) } }
fn setup_rw(im &C.image,bs u32) { unsafe {
 setup(im,bs,128); s:=im.data+1024; g:=im.data+(if bs==1024 { u32(2) } else { u32(1) })*bs
 p32(s+84,11); p32(s+92,8); p32(s+12,236); p32(s+16,17); p32(g,3); p32(g+4,4); p32(g+8,5); p16(g+12,236); p16(g+14,17); p16(g+16,1)
 C.memset(im.data+3*bs,0,bs); C.memset(im.data+4*bs,0,bs); first:=if bs==1024 { u32(1) } else { u32(0) }
 for block:=first; block<=19; block++ { im.data[3*bs+(block-first)/8]|=u8(u32(1)<<((block-first)&7)) }
 for number:=u32(1); number<=15; number++ { im.data[4*bs+(number-1)/8]|=u8(u32(1)<<((number-1)&7)) }
 p16(inode(im,2)+26,2); C.assert(C.vinix_ext2_open_rw(&im.fs,sizeof(im.fs),C.ext2_fixture_read,C.ext2_fixture_write,im,im.bytes)==0)
} }
fn t_layout() { unsafe {
 for bs:=u32(1024); bs<=4096; bs*=2 { for inode_size:=u32(128); inode_size<=256; inode_size*=2 {
  mut im:=C.image{}; setup(&im,bs,inode_size); mut fields:=[10]u64{}; C.assert(C.vinix_ext2_stat(&im.fs,12,&fields[0])==0)
  C.assert(fields[0]==3*bs && fields[1]==0x81ed && fields[2]==0x12345678 && fields[3]==0x89abcdef)
  C.assert(fields[6]==123 && fields[7]==456 && fields[8]==789 && fields[9]==bs); destroy(&im)
 } }
} }
fn t_reads() { unsafe {
 for bs:=u32(1024); bs<=4096; bs*=2 {
  mut im:=C.image{}; setup(&im,bs,256); p:=&u8(C.malloc(3*bs+2)); C.assert(p!=nil); C.memset(p,0xa5,3*bs+2)
  C.assert(C.vinix_ext2_read(&im.fs,12,p+1,7,3*bs)==i64(3*bs-7))
  for i:=u32(0); i<3*bs-7; i++ { C.assert(p[1+i]==if i+7<bs { u8(0x31) } else if i+7<2*bs { u8(0) } else { u8(0x72) }) }
  C.assert(p[0]==0xa5 && p[3*bs-6]==0xa5); C.assert(C.vinix_ext2_read(&im.fs,12,nil,3*bs,0)==0); C.assert(C.vinix_ext2_read(&im.fs,12,p,3*bs+1,1)<0); C.free(p); destroy(&im)
 }
} }
fn t_links_dirs() { unsafe {
 mut im:=C.image{}; setup(&im,4096,128); mut name:=[256]char{}; mut text:=[128]char{}
 C.assert(C.vinix_ext2_read(&im.fs,13,&text[0],0,sizeof(text))==10 && C.memcmp(&text[0],c'/sbin/init',10)==0); C.assert(C.vinix_ext2_read(&im.fs,14,&text[0],0,sizeof(text))==100)
 for i:=u32(0); i<100; i++ { C.assert(text[i]==97) }; mut offset:=u64(0); mut number:=u32(0); expected:=[&char(c'.'),&char(c'..'),&char(c'kernel'),&char(c'fast'),&char(c'long')]!
 for i:=u32(0); i<5; i++ { C.assert(C.vinix_ext2_next(&im.fs,2,&offset,&number,&name[0],sizeof(name))==1); C.assert(C.strcmp(&name[0],expected[i])==0) }
 C.assert(C.vinix_ext2_next(&im.fs,2,&offset,&number,&name[0],sizeof(name))==0); C.assert(C.vinix_ext2_next(&im.fs,12,&offset,&number,&name[0],sizeof(name)) == -20); destroy(&im)
} }
fn t_indirect() { unsafe {
 for bs:=u32(1024); bs<=4096; bs*=2 {
  mut im:=C.image{}; setup(&im,bs,128); per:=u64(bs/4); single:=u64(12); double:=12+per+2*per+3; triple:=12+per+per*per+per*per+2*per+3
  set_inode(&im,15,0x81a4,(triple+1)*bs,0); p:=inode(&im,15); p32(p+40+12*4,24); p32(p+40+13*4,26); p32(p+40+14*4,29)
  p32(im.data+24*bs,25); im.data[25*bs]=0x11; p32(im.data+26*bs+2*4,27); p32(im.data+27*bs+3*4,28); im.data[28*bs]=0x22
  p32(im.data+29*bs+4,30); p32(im.data+30*bs+2*4,31); p32(im.data+31*bs+3*4,32); im.data[32*bs]=0x33
  mut byte:=u8(0); C.assert(C.vinix_ext2_read(&im.fs,15,&byte,single*bs,1)==1 && byte==0x11); C.assert(C.vinix_ext2_read(&im.fs,15,&byte,double*bs,1)==1 && byte==0x22); C.assert(C.vinix_ext2_read(&im.fs,15,&byte,triple*bs,1)==1 && byte==0x33)
  p32(im.data+31*bs+3*4,256); C.assert(C.vinix_ext2_read(&im.fs,15,&byte,triple*bs,1)<0); destroy(&im)
 }
} }
fn t_corruption() { unsafe {
 mut im:=C.image{}; setup(&im,1024,128); mut saved:=[1024]u8{}; C.memcpy(&saved[0],im.data+1024,1024); offsets:=[u32(24),32,40,88,96,100,58,232]!
 for offset in offsets { C.memcpy(im.data+1024,&saved[0],1024); p32(im.data+1024+offset,~u32(0)); C.assert(C.vinix_ext2_open(&im.fs,sizeof(im.fs),C.ext2_fixture_read,&im,im.bytes)<0 && im.fs.opened==0) }
 C.memcpy(im.data+1024,&saved[0],1024); p32(im.data+1024+92,4); C.assert(C.vinix_ext2_open(&im.fs,sizeof(im.fs),C.ext2_fixture_read,&im,im.bytes)<0)
 C.memcpy(im.data+1024,&saved[0],1024); C.assert(C.vinix_ext2_open(&im.fs,sizeof(im.fs),C.ext2_fixture_read,&im,im.bytes)==0)
 mut offset:=u64(0); mut number:=u32(0); mut name:=[256]char{}; d:=im.data+16*1024
 p16(d+4,0); C.assert(C.vinix_ext2_next(&im.fs,2,&offset,&number,&name[0],256)<0 && offset==0); p16(d+4,12); d[8]=47; C.assert(C.vinix_ext2_next(&im.fs,2,&offset,&number,&name[0],256)<0); d[8]=46; p32(d,33); C.assert(C.vinix_ext2_next(&im.fs,2,&offset,&number,&name[0],256)<0); destroy(&im)
} }
fn t_failures() { unsafe {
 mut im:=C.image{}; setup(&im,2048,128); mut fields:=[10]u64{}; mut bytes:=[8]u8{}
 C.assert(C.vinix_ext2_stat(nil,2,&fields[0])<0); C.assert(C.vinix_ext2_stat(&im.fs,0,&fields[0])<0 && C.vinix_ext2_stat(&im.fs,33,&fields[0])<0); C.assert(C.vinix_ext2_read(&im.fs,12,nil,0,1)<0)
 im.fail=1; C.assert(C.vinix_ext2_read(&im.fs,12,&bytes[0],0,sizeof(bytes))==i64(C.E2_IO)); C.assert(C.vinix_ext2_open(&im.fs,sizeof(im.fs),C.ext2_fixture_read,&im,im.bytes)==i32(C.E2_IO)); C.assert(C.vinix_ext2_open(&im.fs,sizeof(im.fs)-1,C.ext2_fixture_read,&im,im.bytes)<0); destroy(&im)
} }
__global rng = u32(0x5718e357)
fn random32() u32 { rng^=rng<<13; rng^=rng>>17; rng^=rng<<5; return rng }
fn t_mutation() { unsafe {
 mut im:=C.image{}; setup(&im,1024,128); mut saved:=[1024]u8{}; C.memcpy(&saved[0],im.data+1024,1024)
 for i:=u32(0); i<10000; i++ { C.memcpy(im.data+1024,&saved[0],1024); for j:=u32(0); j<1+(i%8); j++ { position:=random32()%1024; im.data[1024+position]^=u8(random32()) }
  if C.vinix_ext2_open(&im.fs,sizeof(im.fs),C.ext2_fixture_read,&im,im.bytes)==0 { mut bytes:=[128]u8{}; mut fields:=[10]u64{}; C.vinix_ext2_stat(&im.fs,12,&fields[0]); C.vinix_ext2_read(&im.fs,12,&bytes[0],random32()%4096,sizeof(bytes)) }
 }; destroy(&im)
} }
fn t_rw_persistence() { unsafe {
 for bs:=u32(1024); bs<=4096; bs*=2 { mut im:=C.image{}; setup_rw(&im,bs); mut number:=u32(0); mut name:=[256]char{}
  C.assert(C.vinix_ext2_begin_write(&im.fs)==0); C.assert(C.e2_u16(im.data+1024+58)==2); C.assert(C.vinix_ext2_create(&im.fs,2,c'notes.txt',9,u32(C.E2_REGULAR)|0o644,&number)==0); C.assert(C.vinix_ext2_write(&im.fs,number,c'saved on ssd',0,12)==12)
  C.assert(C.vinix_ext2_close_clean(&im.fs)==0); C.assert(C.e2_u16(im.data+1024+58)==1); C.assert(C.vinix_ext2_open_rw(&im.fs,sizeof(im.fs),C.ext2_fixture_read,C.ext2_fixture_write,&im,im.bytes)==0)
  mut offset:=u64(0); mut found:=u32(0); for C.vinix_ext2_next(&im.fs,2,&offset,&found,&name[0],sizeof(name))==1 { if C.strcmp(&name[0],c'notes.txt')==0 { break } }; C.assert(found==number)
  mut text:=[16]char{}; C.assert(C.vinix_ext2_read(&im.fs,found,&text[0],0,sizeof(text))==12); C.assert(C.memcmp(&text[0],c'saved on ssd',12)==0); C.assert(C.vinix_ext2_begin_write(&im.fs)==0); C.assert(C.vinix_ext2_close_clean(&im.fs)==0); destroy(&im)
 }
} }
fn t_rw_sparse_truncate() { unsafe {
 mut im:=C.image{}; setup_rw(&im,1024); mut number:=u32(0); mut bytes:=[1040]u8{}
 C.assert(C.vinix_ext2_begin_write(&im.fs)==0); C.assert(C.vinix_ext2_create(&im.fs,2,c'sparse',6,u32(C.E2_REGULAR)|0o600,&number)==0); C.assert(C.vinix_ext2_write(&im.fs,number,c'q',0,1)==1)
 block:=C.e2_u32(inode(&im,number)+40); C.assert(block!=0); C.memset(im.data+block*im.bs+1,0x7e,7); C.assert(C.vinix_ext2_write(&im.fs,number,c'x',5,1)==1)
 C.memset(&bytes[0],0xa5,8); C.assert(C.vinix_ext2_read(&im.fs,number,&bytes[0],0,8)==6); C.assert(bytes[0]==113); for i:=u32(1); i<5; i++ { C.assert(bytes[i]==0) }; C.assert(bytes[5]==120)
 C.assert(C.vinix_ext2_truncate(&im.fs,number,0)==0); C.assert(C.vinix_ext2_write(&im.fs,number,c'abc',1027,3)==3); C.memset(&bytes[0],0xa5,sizeof(bytes)); C.assert(C.vinix_ext2_read(&im.fs,number,&bytes[0],0,sizeof(bytes))==1030)
 for i:=u32(0); i<1027; i++ { C.assert(bytes[i]==0) }; C.assert(C.memcmp(&bytes[1027],c'abc',3)==0); C.assert(C.vinix_ext2_truncate(&im.fs,number,2)==0); C.assert(C.vinix_ext2_write(&im.fs,number,c'z',5,1)==1)
 C.memset(&bytes[0],0xa5,8); C.assert(C.vinix_ext2_read(&im.fs,number,&bytes[0],0,8)==6); for i:=u32(0); i<5; i++ { C.assert(bytes[i]==0) }; C.assert(bytes[5]==122); C.assert(C.vinix_ext2_close_clean(&im.fs)==0); destroy(&im)
} }
fn t_rw_directories_links() { unsafe {
 mut im:=C.image{}; setup_rw(&im,2048); mut dir:=u32(0); mut file:=u32(0); mut link:=u32(0); C.assert(C.vinix_ext2_begin_write(&im.fs)==0)
 C.assert(C.vinix_ext2_create(&im.fs,2,c'docs',4,u32(C.E2_DIRECTORY)|0o755,&dir)==0); C.assert(C.vinix_ext2_create(&im.fs,dir,c'a',1,u32(C.E2_REGULAR)|0o644,&file)==0); C.assert(C.vinix_ext2_link(&im.fs,dir,c'b',1,file)==0); C.assert(C.vinix_ext2_rename(&im.fs,dir,c'a',1,dir,c'b',1,1)==0)
 mut found:=u32(0); mut fields:=[10]u64{}; C.assert(C.e2_lookup(&im.fs,dir,c'a',1,&found,nil)==0 && found==file); C.assert(C.e2_lookup(&im.fs,dir,c'b',1,&found,nil)==0 && found==file); C.assert(C.vinix_ext2_stat(&im.fs,file,&fields[0])==0 && fields[4]==2)
 C.assert(C.vinix_ext2_symlink(&im.fs,dir,c'latest',6,c'a',1,&link)==0); mut target:=[4]char{}; C.assert(C.vinix_ext2_read(&im.fs,link,&target[0],0,sizeof(target))==1 && target[0]==97)
 C.assert(C.vinix_ext2_rename(&im.fs,dir,c'a',1,dir,c'renamed',7,0)==0); C.assert(C.vinix_ext2_unlink(&im.fs,dir,c'renamed',7,0)==0); C.assert(C.vinix_ext2_unlink(&im.fs,dir,c'b',1,0)==0); C.assert(C.vinix_ext2_unlink(&im.fs,dir,c'latest',6,0)==0); C.assert(C.vinix_ext2_unlink(&im.fs,2,c'docs',4,1)==0); C.assert(C.vinix_ext2_close_clean(&im.fs)==0)
 C.assert(C.vinix_ext2_open(&im.fs,sizeof(im.fs),C.ext2_fixture_read,&im,im.bytes)==0); C.assert(C.e2_lookup(&im.fs,2,c'docs',4,&dir,nil)==-2); destroy(&im)
} }
fn t_rw_dirty_and_failure() { unsafe {
 mut im:=C.image{}; setup_rw(&im,4096); mut number:=u32(0); C.assert(C.vinix_ext2_begin_write(&im.fs)==0); mut second:=C.e2_fs{}
 C.assert(C.vinix_ext2_open_rw(&second,sizeof(second),C.ext2_fixture_read,C.ext2_fixture_write,&im,im.bytes)<0); C.assert(C.vinix_ext2_create(&im.fs,2,c'failure',7,u32(C.E2_REGULAR)|0o644,&number)==0)
 im.fail_write=1; C.assert(C.vinix_ext2_write(&im.fs,number,c'x',0,1)==i64(C.E2_IO)); im.fail_write=0; C.assert(C.vinix_ext2_write(&im.fs,number,c'x',0,1)==i64(C.E2_ROFS)); C.assert(C.vinix_ext2_close_clean(&im.fs)==i32(C.E2_IO)); C.assert(C.e2_u16(im.data+1024+58)==2); C.assert(C.vinix_ext2_open_rw(&second,sizeof(second),C.ext2_fixture_read,C.ext2_fixture_write,&im,im.bytes)<0); destroy(&im)
} }
@[export: 'ext2_fixture_run']
pub fn run() i32 { unsafe {
 tests:=[t_layout,t_reads,t_links_dirs,t_indirect,t_corruption,t_failures,t_mutation,t_rw_persistence,t_rw_sparse_truncate,t_rw_directories_links,t_rw_dirty_and_failure]!
 names:=[&char(c'superblock at byte 1024; block/inode sizes and metadata'),&char(c'unaligned reads, sparse holes, EOF and buffer guards'),&char(c'inline/block symlinks and unused directory entries'),&char(c'single/double/triple indirection and large sparse files'),&char(c'unsupported features, dirty roots and malformed directories'),&char(c'I/O, null, allocation-size and inode bounds'),&char(c'10000 bounded superblock mutations'),&char(c'create, write, clean shutdown and cold-open persistence'),&char(c'sparse writes, truncate and zero-fill semantics'),&char(c'persistent directories, hard links, symlinks, rename and unlink'),&char(c'dirty-mount refusal and write failure propagation')]!
 for i:=u32(0); i<tests.len; i++ { tests[i](); C.printf(c'ok ext2 %u - %s\n',i+1,names[i]) }; C.puts(c'PASS: 11 ext2 test groups (7 read-only, 4 persistent-write)'); return 0
} }
