// SPDX-License-Identifier: GPL-2.0-or-later
// Public test CA only; no system keychain or network access. The supported
// explicit-anchor cases run unchanged against Mac Security and Vinix.
#include "security-fixtures.h"
typedef const void *Object;
typedef unsigned long Type;
typedef unsigned char Boolean;
typedef struct {
 long version;
 Object (*retain)(Object,Object);
 void (*release)(Object,Object);
 Object (*description)(Object);
 Boolean (*equal)(Object,Object);
} Callbacks;
extern const Callbacks kCFTypeArrayCallBacks;
extern int puts(const char *), printf(const char *,...), strcmp(const char *,const char *), memcmp(const void *,const void *,unsigned long);
extern Object CFDataCreate(Object,const unsigned char *,long), CFArrayCreate(Object,const Object *,long,const Callbacks *);
extern long CFDataGetLength(Object), CFArrayGetCount(Object);
extern const unsigned char *CFDataGetBytePtr(Object);
extern Object CFArrayGetValueAtIndex(Object,long), CFRetain(Object);
extern void CFRelease(Object);
extern Type CFGetTypeID(Object), CFDateGetTypeID(void), SecTrustGetTypeID(void), SecPolicyGetTypeID(void), CFErrorGetTypeID(void);
extern Object CFDateCreate(Object,double);
extern double CFDateGetAbsoluteTime(Object);
extern Boolean CFEqual(Object,Object);
extern Type CFHash(Object);
extern Object SecCertificateCreateWithData(Object,Object), SecCertificateCopyKey(Object), SecKeyCopyExternalRepresentation(Object,Object *);
extern Object SecPolicyCreateBasicX509(void), SecPolicyCreateSSL(Boolean,Object);
extern int SecTrustCreateWithCertificates(Object,Object,Object *), SecTrustEvaluate(Object,unsigned *), SecTrustGetTrustResult(Object,unsigned *);
extern Boolean SecTrustEvaluateWithError(Object,Object *);
extern Object SecTrustCopyPublicKey(Object), SecTrustCopyKey(Object), SecTrustGetCertificateAtIndex(Object,long);
extern long SecTrustGetCertificateCount(Object);
extern int SecTrustSetAnchorCertificates(Object,Object), SecTrustSetAnchorCertificatesOnly(Object,Boolean), SecTrustSetVerifyDate(Object,Object);
extern int SecTrustSetPolicies(Object,Object), SecTrustCopyPolicies(Object,Object *);
extern int SecTrustSetNetworkFetchAllowed(Object,Boolean), SecTrustGetNetworkFetchAllowed(Object,Boolean *);
extern long CFErrorGetCode(Object);
extern Object CFErrorGetDomain(Object);
extern Boolean CFStringGetCString(Object,char *,long,unsigned);
#define REQUIRE(test) do { if(!(test)){printf("IOS-SECURITY-TRUST FAIL: line %d: %s\n",__LINE__,#test);return 1;} } while(0)
static Object certificate(const unsigned char *bytes,long length) {
 Object data=CFDataCreate(0,bytes,length), cert=SecCertificateCreateWithData(0,data);CFRelease(data);return cert;
}
static int failed(Object trust,long code) {
 Object error=(Object)0x1234;
 REQUIRE(!SecTrustEvaluateWithError(trust,&error));
 REQUIRE(error && error!=(Object)0x1234 && CFGetTypeID(error)==CFErrorGetTypeID() && CFErrorGetCode(error)==code);
 char domain[64]={0};REQUIRE(CFStringGetCString(CFErrorGetDomain(error),domain,sizeof domain,0x08000100));
 REQUIRE(!strcmp(domain,"NSOSStatusErrorDomain"));
 CFRetain(error);CFRelease(error);CFRelease(error);
 REQUIRE(!SecTrustEvaluateWithError(trust,0));return 0;
}
static int set_date(Object trust,double unix_seconds) {
 Object date=CFDateCreate(0,unix_seconds-978307200.),duplicate=CFDateCreate(0,unix_seconds-978307200.);
 REQUIRE(date && CFGetTypeID(date)==CFDateGetTypeID());
 REQUIRE(CFDateGetAbsoluteTime(date)==unix_seconds-978307200. && CFEqual(date,duplicate) && CFHash(date)==CFHash(duplicate));
 REQUIRE(!SecTrustSetVerifyDate(trust,date));CFRelease(date);CFRelease(duplicate);return 0;
}
static int check_trust(void) {
 Object cert=certificate(ec,sizeof ec),policy=SecPolicyCreateBasicX509(),trust=0;
 REQUIRE(cert && policy);
 Object certs=CFArrayCreate(0,&cert,1,&kCFTypeArrayCallBacks),policies=CFArrayCreate(0,&policy,1,&kCFTypeArrayCallBacks);
 REQUIRE(!SecTrustCreateWithCertificates(certs,policies,&trust) && trust && CFGetTypeID(trust)==SecTrustGetTypeID());
 CFRelease(certs);CFRelease(policies);CFRelease(policy);CFRelease(cert);
 REQUIRE(SecTrustGetCertificateCount(trust)==1);
 Object leaf=SecTrustGetCertificateAtIndex(trust,0),leaf_key=SecCertificateCopyKey(leaf);
 Object key=SecTrustCopyPublicKey(trust),alias=SecTrustCopyKey(trust);
 REQUIRE(key && alias && leaf_key);
 // The deprecated Mac getter uses a different key class: compare exported
 // bytes, not pointer identity or CFEqual across those key implementations.
 Object key_data=SecKeyCopyExternalRepresentation(key,0),alias_data=SecKeyCopyExternalRepresentation(alias,0),leaf_data=SecKeyCopyExternalRepresentation(leaf_key,0);
 REQUIRE(key_data && alias_data && leaf_data && CFEqual(key_data,alias_data) && CFEqual(key_data,leaf_data));
 CFRelease(key_data);CFRelease(alias_data);CFRelease(leaf_data);CFRelease(alias);CFRelease(leaf_key);
 Boolean allowed=9;REQUIRE(!SecTrustGetNetworkFetchAllowed(trust,&allowed) && !allowed);
 REQUIRE(!SecTrustSetNetworkFetchAllowed(trust,1) && !SecTrustGetNetworkFetchAllowed(trust,&allowed) && allowed);
 REQUIRE(!SecTrustSetNetworkFetchAllowed(trust,0) && !SecTrustGetNetworkFetchAllowed(trust,&allowed) && !allowed);
 REQUIRE(!set_date(trust,1791583200.25));
 unsigned result=99;
#ifdef IOS_TRUST_REFERENCE
 REQUIRE(!SecTrustGetTrustResult(trust,&result) && result==5);
 REQUIRE(!failed(trust,-67843));
#else
 // Vinix has no system trust store: it reports the missing service explicitly.
 REQUIRE(SecTrustGetTrustResult(trust,&result)==-4 && result==0);
 REQUIRE(!failed(trust,-4));
#endif
 // An explicitly empty trust set is a real negative decision, not a missing API.
 Object empty=CFArrayCreate(0,0,0,&kCFTypeArrayCallBacks);
 REQUIRE(!SecTrustSetAnchorCertificates(trust,empty));
 REQUIRE(!SecTrustEvaluate(trust,&result) && result==5 && !failed(trust,-67843));
 Object other=certificate(ec384,sizeof ec384),anchors=CFArrayCreate(0,&other,1,&kCFTypeArrayCallBacks);
 REQUIRE(!SecTrustSetAnchorCertificates(trust,anchors));CFRelease(anchors);CFRelease(other);
 REQUIRE(!SecTrustGetTrustResult(trust,&result) && result==5 && !failed(trust,-67843));
 // A separately parsed DER-identical anchor succeeds and is retained by trust.
 other=certificate(ec,sizeof ec);anchors=CFArrayCreate(0,&other,1,&kCFTypeArrayCallBacks);
 REQUIRE(!SecTrustSetAnchorCertificates(trust,anchors));CFRelease(anchors);CFRelease(other);
 REQUIRE(!SecTrustSetAnchorCertificatesOnly(trust,1));
 Object error=(Object)0x1234;
 REQUIRE(SecTrustEvaluateWithError(trust,&error) && !error);
 REQUIRE(SecTrustEvaluateWithError(trust,0));
 REQUIRE(!SecTrustGetTrustResult(trust,&result) && result==4);
 REQUIRE(!SecTrustEvaluate(trust,&result) && result==4);
 // A date change must discard the previous successful result, in both directions.
 REQUIRE(!set_date(trust,1735689600.));
 REQUIRE(!SecTrustGetTrustResult(trust,&result) && result==5 && !failed(trust,-67818));
 REQUIRE(!set_date(trust,1798761600.));
 REQUIRE(!SecTrustEvaluate(trust,&result) && result==5 && !failed(trust,-67818));
 REQUIRE(!set_date(trust,1791583200.));
 REQUIRE(!SecTrustGetTrustResult(trust,&result) && result==4);
 Object copied=0;REQUIRE(!SecTrustCopyPolicies(trust,&copied) && CFArrayGetCount(copied)==1);
 REQUIRE(CFGetTypeID(CFArrayGetValueAtIndex(copied,0))==SecPolicyGetTypeID());
#ifndef IOS_TRUST_REFERENCE
 // A cached positive basic-X.509 result must never authorize an SSL policy or
 // fall back silently to the absent system trust/chain-building implementation.
 Object ssl=SecPolicyCreateSSL(1,0);
 REQUIRE(!SecTrustSetPolicies(trust,ssl));CFRelease(ssl);
 REQUIRE(SecTrustEvaluate(trust,&result)==-4 && result==0 && !failed(trust,-4));
 REQUIRE(!SecTrustSetPolicies(trust,copied));
 REQUIRE(!SecTrustGetTrustResult(trust,&result) && result==4);
 REQUIRE(!SecTrustSetAnchorCertificatesOnly(trust,0));
 REQUIRE(SecTrustEvaluate(trust,&result)==-4 && result==0 && !failed(trust,-4));
 REQUIRE(!SecTrustSetAnchorCertificatesOnly(trust,1));
 REQUIRE(!SecTrustGetTrustResult(trust,&result) && result==4);
#endif
 CFRelease(trust); // Copied policies and extracted keys outlive the trust.
 REQUIRE(CFArrayGetCount(copied)==1);CFRelease(copied);
 Object exported=SecKeyCopyExternalRepresentation(key,0);CFRelease(key);
 REQUIRE(exported && CFDataGetLength(exported)==sizeof ec_key && !memcmp(CFDataGetBytePtr(exported),ec_key,sizeof ec_key));CFRelease(exported);
 // Empty constructor input is rejected without overwriting the caller's output.
 trust=(Object)0x1234;REQUIRE(SecTrustCreateWithCertificates(empty,0,&trust)==-50 && trust==(Object)0x1234);CFRelease(empty);
 cert=certificate(ec,sizeof ec);REQUIRE(!SecTrustCreateWithCertificates(cert,0,&trust));CFRelease(cert);CFRelease(trust);
 return 0;
}
static int check_anchor_signature(void) {
 // An anchor is explicitly trusted by the caller. Its self-signature is not
 // an issuer-link proof, and the Mac accepts this exact anchor as well.
 unsigned char altered[sizeof ec];
 for(unsigned long i=0;i<sizeof ec;i++)altered[i]=ec[i];
 altered[sizeof ec-1]^=1;
 Object cert=certificate(altered,sizeof altered),policy=SecPolicyCreateBasicX509(),trust=0;
 REQUIRE(cert && !SecTrustCreateWithCertificates(cert,policy,&trust));CFRelease(policy);
 Object anchors=CFArrayCreate(0,&cert,1,&kCFTypeArrayCallBacks);CFRelease(cert);
 REQUIRE(!SecTrustSetAnchorCertificates(trust,anchors));CFRelease(anchors);
 REQUIRE(!set_date(trust,1791583200.));
 REQUIRE(SecTrustEvaluateWithError(trust,0));CFRelease(trust);return 0;
}
#ifndef IOS_TRUST_REFERENCE
static int check_rejected_profile(void) {
 for(int variant=0;variant<5;variant++) {
  unsigned char altered[sizeof ec];
  for(unsigned long i=0;i<sizeof ec;i++)altered[i]=ec[i];
  int found=0;
  if(variant==0 || variant==1) {
   for(unsigned long i=0;i+14<sizeof ec;i++)if(!memcmp(altered+i,"\x06\x03\x55\x1d\x13",5)) {
    if(variant==0)altered[i+4]=0x7f; // Unknown critical constraint.
    else altered[i+14]=0; // CA:false instead of CA:true.
    found=1;break;
   }
  } else if(variant==2) {
   for(unsigned long i=0;i+13<sizeof ec;i++)if(!memcmp(altered+i,"261009083659Z",13)) {
    altered[i+2]='1';altered[i+3]='3';found=1;break; // Impossible month.
   }
  } else if(variant==3) {
   for(unsigned long i=0;i+sizeof ec_key<sizeof ec;i++)if(!memcmp(altered+i,ec_key,sizeof ec_key)) {
    for(unsigned long j=1;j<sizeof ec_key;j++)altered[i+j]=0;
    found=1;break; // Off-curve key.
   }
  } else found=1;
  REQUIRE(found);
  Object cert=certificate(altered,sizeof altered),policy=SecPolicyCreateBasicX509(),trust=0;
  REQUIRE(cert);
  Object items[2]={cert,cert};
  Object certs=CFArrayCreate(0,items,variant==4?2:1,&kCFTypeArrayCallBacks);
  REQUIRE(!SecTrustCreateWithCertificates(certs,policy,&trust));CFRelease(certs);CFRelease(policy);
  Object anchors=CFArrayCreate(0,&cert,1,&kCFTypeArrayCallBacks);CFRelease(cert);
  REQUIRE(!SecTrustSetAnchorCertificates(trust,anchors));CFRelease(anchors);
  REQUIRE(!set_date(trust,1791583200.));
  unsigned result=99;REQUIRE(SecTrustEvaluate(trust,&result)==-4 && result==0 && !failed(trust,-4));
  CFRelease(trust);
 }
 return 0;
}
#endif
int main(void) {
 for(int repeat=0;repeat<8;repeat++)REQUIRE(!check_trust());
 REQUIRE(!check_anchor_signature());
#ifndef IOS_TRUST_REFERENCE
 REQUIRE(!check_rejected_profile());
#endif
 puts("IOS-SECURITY-TRUST: owned trust/key snapshots, explicit CA anchors, verify dates, negative decisions and cache invalidation");
 return 0;
}
