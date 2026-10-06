// Declaration-only ABI for host and Windows64 licensing fixtures.
#ifndef VINIX_OFFICE_TEST_ABI_H
#define VINIX_OFFICE_TEST_ABI_H
#include "sppc-office-v-abi.h"
#include <stddef.h>
#ifndef _WIN32
typedef int32_t HRESULT;
typedef int32_t BOOL;
typedef uint32_t DWORD;
typedef uint32_t UINT;
typedef uint8_t BYTE;
typedef uintptr_t UINT_PTR;
typedef void *HINSTANCE;
typedef void *LPVOID;
#define WINAPI
#define __declspec(x)
#define TRUE 1
#define S_OK ((HRESULT)0)
#define E_INVALIDARG ((HRESULT)0x80070057)
#define E_NOTIMPL ((HRESULT)0x80004001)
#endif
int32_t DllMain(void *, uint32_t, void *);
int32_t SLLoadApplicationPolicies(const GUID *, const GUID *, uint32_t, void **);
int32_t SLGetApplicationPolicy(void *, const WCHAR *, uint32_t *, uint32_t *, uint8_t **);
int32_t SLUnloadApplicationPolicies(void *);
int32_t SLOpen(void **);
int32_t SLClose(void *);
int32_t SLGetLicensingStatusInformation(void *, const GUID *, const GUID *, const WCHAR *, uint32_t *, void **);
int32_t SLActivateProduct(void);
int32_t SLConsumeRight(void);
int32_t SLDepositOfflineConfirmationId(void);
int32_t SLDepositTokenActivationResponse(void);
int32_t SLFreeTokenActivationCertificates(void);
int32_t SLFreeTokenActivationGrants(void);
int32_t SLGenerateOfflineInstallationId(void);
int32_t SLGenerateTokenActivationChallenge(void);
int32_t SLGetAuthenticationResult(void);
int32_t SLGetInstalledProductKeyIds(void);
int32_t SLGetPKeyId(void);
int32_t SLGetPKeyInformation(void);
int32_t SLGetPolicyInformation(void);
int32_t SLGetProductSkuInformation(void);
int32_t SLGetSLIDList(void);
int32_t SLGetServiceInformation(void);
int32_t SLGetTokenActivationCertificates(void);
int32_t SLGetTokenActivationGrants(void);
int32_t SLInstallLicense(void);
int32_t SLInstallProofOfPurchase(void);
int32_t SLPersistApplicationPolicies(void);
int32_t SLPersistRTSPayloadOverride(void);
int32_t SLRegisterPlugin(void);
int32_t SLSetAuthenticationData(void);
int32_t SLSignTokenActivationChallenge(void);
int32_t SLUninstallLicense(void);
int32_t SLUninstallProofOfPurchase(void);
#endif
