// SPDX-License-Identifier: GPL-2.0-or-later
// Identical calls and independent vectors against Mac CommonCrypto and Vinix.
#include "common-crypto-vectors.h"
extern int puts(const char *), printf(const char *,...), memcmp(const void *,const void *,unsigned long);
extern void *memcpy(void *,const void *,unsigned long), *memset(void *,int,unsigned long);
typedef unsigned char *(*Hash)(const void *,unsigned int,unsigned char *);
extern unsigned char *CC_SHA1(const void *,unsigned int,unsigned char *), *CC_SHA224(const void *,unsigned int,unsigned char *);
extern unsigned char *CC_SHA256(const void *,unsigned int,unsigned char *), *CC_SHA384(const void *,unsigned int,unsigned char *), *CC_SHA512(const void *,unsigned int,unsigned char *);
extern void CCHmac(unsigned int,const void *,unsigned long,const void *,unsigned long,void *);
extern int CCCrypt(unsigned int,unsigned int,unsigned int,const void *,unsigned long,const void *,const void *,unsigned long,void *,unsigned long,unsigned long *);
#define REQUIRE(condition) do { if (!(condition)) { printf("IOS-CRYPTO FAIL: line %d: %s\n",__LINE__,#condition); return 1; } } while (0)
static unsigned char hex_byte(const char *hex) {
 unsigned char a=(unsigned char)hex[0],b=(unsigned char)hex[1];
 return (unsigned char)(((a>='a'?a-'a'+10:a-'0')<<4)|(b>='a'?b-'a'+10:b-'0'));
}
static int equals_hex(const unsigned char *bytes,unsigned long length,const char *hex) {
 for(unsigned long i=0;i<length;i++)if(!hex[2*i]||!hex[2*i+1]||bytes[i]!=hex_byte(hex+2*i))return 0;
 return !hex[length*2];
}
static void from_hex(unsigned char *bytes,unsigned long length,const char *hex) {
 for(unsigned long i=0;i<length;i++)bytes[i]=hex_byte(hex+2*i);
}
static int check_hashes(void) {
 Hash hashes[]={CC_SHA1,CC_SHA224,CC_SHA256,CC_SHA384,CC_SHA512};
 unsigned int sizes[]={20,28,32,48,64},algorithms[]={0,5,2,3,4};
 unsigned char data[1024],key[200],output[66],overlap[1024];
 for(unsigned long i=0;i<sizeof data;i++)data[i]=(unsigned char)(i*37+11);
 for(unsigned long i=0;i<sizeof key;i++)key[i]=(unsigned char)(i*13+7);
 for(unsigned long a=0;a<5;a++) {
  REQUIRE(!hashes[a](data,3,0));
  for(unsigned long t=0;t<14;t++) {
   memset(output,0xa5,sizeof output);
   unsigned long n=hash_lengths[t];
   REQUIRE(hashes[a](n?data:0,(unsigned int)n,output+1)==output+1);
   REQUIRE(output[0]==0xa5 && output[sizes[a]+1]==0xa5);
   REQUIRE(equals_hex(output+1,sizes[a],hash_expected[a][t]));
  }
  // Digest output may overlap input after the entire input is consumed.
  memcpy(overlap,data,sizeof data);
  REQUIRE(hashes[a](overlap,sizeof overlap,overlap)==overlap);
  REQUIRE(equals_hex(overlap,sizes[a],hash_expected[a][13]));
  for(unsigned long t=0;t<7;t++) {
   memset(output,0xa5,sizeof output);
   unsigned long k=hmac_pairs[t][0],n=hmac_pairs[t][1];
   CCHmac(algorithms[a],k?key:0,k,n?data:0,n,output+1);
   REQUIRE(output[0]==0xa5 && output[sizes[a]+1]==0xa5);
   REQUIRE(equals_hex(output+1,sizes[a],hmac_expected[a][t]));
  }
  memcpy(overlap,data,sizeof data);
  CCHmac(algorithms[a],key,sizeof key,overlap,sizeof overlap,overlap);
  REQUIRE(equals_hex(overlap,sizes[a],hmac_expected[a][6]));
 }
 return 0;
}
static int check_aes(void) {
 // NIST SP 800-38A, four AES blocks for each supported key size and mode.
 const char *keys[]={"2b7e151628aed2a6abf7158809cf4f3c","8e73b0f7da0e6452c810f32b809079e562f8ead2522c6b7b","603deb1015ca71be2b73aef0857d77811f352c073b6108d72d9810a30914dff4"};
 const char *ecb[]={"3ad77bb40d7a3660a89ecaf32466ef97f5d3d58503b9699de785895a96fdbaaf43b1cd7f598ece23881b00e3ed0306887b0c785e27e8ad3f8223207104725dd4","bd334f1d6e45f25ff712a214571fa5cc974104846d0ad3ad7734ecb3ecee4eefef7afd2270e2e60adce0ba2face6444e9a4b41ba738d6c72fb16691603c18e0e","f3eed1bdb5d2a03c064b5a7e3db181f8591ccb10d410ed26dc5ba74a31362870b6ed21b99ca6f4f9f153e7b1beafed1d23304b7a39f9f3ff067d8d8f9e24ecc7"};
 const char *cbc[]={"7649abac8119b246cee98e9b12e9197d5086cb9b507219ee95db113a917678b273bed6b8e3c1743b7116e69e222295163ff1caa1681fac09120eca307586e1a7","4f021db243bc633d7178183a9fa071e8b4d9ada9ad7dedf4e5e738763f69145a571b242012fb7ae07fa9baac3df102e008b0e27988598881d920a9e64f5615cd","f58c4c04d6e5f1ba779eabfb5f7bfbd69cfc4e967edb808d679f777bc6702c7d39f23369a9d9bacfa530e26304231461b2eb05e2c39be9fcda6c19078c6a9d1b"};
 unsigned char key[32],iv[16],plain[64],output[66],decoded[66],inplace[64];
 from_hex(plain,64,"6bc1bee22e409f96e93d7e117393172aae2d8a571e03ac9c9eb76fac45af8e5130c81c46a35ce411e5fbc1191a0a52eff69f2445df4f9b17ad2b417be66c3710");
 for(unsigned long i=0;i<16;i++)iv[i]=(unsigned char)i;
 for(unsigned long k=0;k<3;k++)for(unsigned int mode=0;mode<=2;mode+=2) {
  unsigned long key_size=16+8*k,moved=0x1234;
  from_hex(key,key_size,keys[k]);memset(output,0xa5,sizeof output);
  REQUIRE(!CCCrypt(0,0,mode,key,key_size,iv,plain,64,output+1,64,&moved) && moved==64);
  REQUIRE(output[0]==0xa5 && output[65]==0xa5);
  REQUIRE(equals_hex(output+1,64,mode?ecb[k]:cbc[k]));
  memset(decoded,0xa5,sizeof decoded);
  REQUIRE(!CCCrypt(1,0,mode,key,key_size,iv,output+1,64,decoded+1,64,&moved) && moved==64);
  REQUIRE(decoded[0]==0xa5 && decoded[65]==0xa5 && !memcmp(decoded+1,plain,64));
  memcpy(inplace,plain,64);
  REQUIRE(!CCCrypt(0,0,mode,key,key_size,iv,inplace,64,inplace,64,&moved));
  REQUIRE(!memcmp(inplace,output+1,64));
  REQUIRE(!CCCrypt(1,0,mode,key,key_size,iv,inplace,64,inplace,64,&moved));
  REQUIRE(!memcmp(inplace,plain,64));
  memset(decoded,0xa5,sizeof decoded);
  REQUIRE(CCCrypt(0,0,mode,key,key_size,iv,plain,31,decoded+1,15,&moved)==-4301 && moved==16 && decoded[1]==0xa5);
  REQUIRE(CCCrypt(0,0,mode,key,key_size,iv,plain,31,decoded+1,16,&moved)==-4303 && moved==16);
  REQUIRE(!memcmp(decoded+1,output+1,16) && decoded[17]==0xa5);
 }
 unsigned char zero_key[16]={0},data[64];
 for(unsigned long i=0;i<sizeof data;i++)data[i]=(unsigned char)(i*37+11);
 for(unsigned long t=0;t<8;t++) {
  unsigned long n=padded_lengths[t],expected=(n/16+1)*16,moved=0x1234;
  memset(output,0xa5,sizeof output);
  REQUIRE(!CCCrypt(0,0,1,zero_key,16,0,n?data:0,n,output+1,64,&moved) && moved==expected);
  REQUIRE(output[0]==0xa5 && output[expected+1]==0xa5 && equals_hex(output+1,moved,padded_expected[t]));
  memset(decoded,0xa5,sizeof decoded);
  REQUIRE(!CCCrypt(1,0,1,zero_key,16,0,output+1,expected,decoded+1,64,&moved) && moved==n);
  REQUIRE(decoded[0]==0xa5 && decoded[n+1]==0xa5 && !memcmp(decoded+1,data,n));
  memcpy(inplace,output+1,expected);
  REQUIRE(!CCCrypt(1,0,1,zero_key,16,0,inplace,expected,inplace,64,&moved) && moved==n);
  REQUIRE(!memcmp(inplace,data,n));
  moved=0x1234;memset(decoded,0xa5,sizeof decoded);
  REQUIRE(CCCrypt(0,0,1,zero_key,16,0,n?data:0,n,decoded+1,expected-1,&moved)==-4301);
  REQUIRE(moved==expected && decoded[1]==0xa5);
  moved=0x1234;
  REQUIRE(CCCrypt(1,0,1,zero_key,16,0,output+1,expected,decoded+1,expected-1,&moved)==-4301 && moved==expected);
 }
 unsigned long moved=0x1234;
 REQUIRE(CCCrypt(0,0,0,zero_key,15,0,data,16,output,64,&moved)==-4310 && moved==0x1234);
 REQUIRE(CCCrypt(0,0,0,zero_key,16,0,data,15,output,64,&moved)==-4303 && moved==0);
 REQUIRE(!CCCrypt(0,0,0,zero_key,16,0,0,0,0,0,&moved) && moved==0);
 // Legacy unpadding uses the length byte even with unequal preceding bytes.
 memset(data,5,16);data[0]=42;data[14]=1;
 REQUIRE(!CCCrypt(0,0,2,zero_key,16,0,data,16,output,64,&moved));
 memset(decoded,0xa5,sizeof decoded);
 REQUIRE(!CCCrypt(1,0,3,zero_key,16,0,output,16,decoded,64,&moved) && moved==11);
 REQUIRE(!memcmp(decoded,data,11) && decoded[11]==0xa5);
 return 0;
}
int main(void) {
 for(int repeat=0;repeat<8;repeat++) { REQUIRE(!check_hashes());REQUIRE(!check_aes()); }
 puts("IOS-CRYPTO: SHA digests, long-key HMAC, NIST AES CBC/ECB, padding, in-place buffers and error/size ABI");
 return 0;
}
