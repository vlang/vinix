/*
 * Minimal Windows Software Licensing API surface for Wine.
 *
 * Wine 10 exports most of sppc.dll as aborting spec-file stubs.  Office 2013
 * probes the application-policy API during startup and is unable to display
 * even its unlicensed UI when one of those stubs aborts the process.  Keep the
 * probe non-fatal while accurately reporting that Wine has no persisted
 * licensing policy.  This does not install a key, report a licensed state, or
 * activate Office.
 */

#include <windows.h>

#define SL_E_RIGHT_NOT_CONSUMED ((HRESULT)0xc004f014L)
#define SL_E_VALUE_NOT_FOUND ((HRESULT)0xc004f012L)

typedef void *HSLP;
typedef void *HSLC;

BOOL WINAPI DllMain(HINSTANCE instance, DWORD reason, LPVOID reserved)
{
    (void)instance;
    (void)reason;
    (void)reserved;
    return TRUE;
}

__declspec(dllexport) HRESULT WINAPI SLLoadApplicationPolicies(
    const GUID *application, const GUID *product, DWORD flags, HSLP *context)
{
    (void)product;
    (void)flags;
    if (!application || !context)
        return E_INVALIDARG;

    *context = (HSLP)(UINT_PTR)1;
    return S_OK;
}

__declspec(dllexport) HRESULT WINAPI SLGetApplicationPolicy(
    HSLP context, const WCHAR *name, DWORD *type, UINT *size, BYTE **value)
{
    if (!context || !name || !size || !value)
        return E_INVALIDARG;

    if (type)
        *type = 0;
    *size = 0;
    *value = NULL;
    return SL_E_VALUE_NOT_FOUND;
}

__declspec(dllexport) HRESULT WINAPI SLUnloadApplicationPolicies(HSLP context)
{
    return context ? S_OK : E_INVALIDARG;
}

__declspec(dllexport) HRESULT WINAPI SLOpen(HSLC *context)
{
    if (!context)
        return E_INVALIDARG;
    *context = (HSLC)(UINT_PTR)1;
    return S_OK;
}

__declspec(dllexport) HRESULT WINAPI SLClose(HSLC context)
{
    return context ? S_OK : E_INVALIDARG;
}

__declspec(dllexport) HRESULT WINAPI SLGetLicensingStatusInformation(
    HSLC context, const GUID *application, const GUID *product,
    const WCHAR *name, UINT *count, void **status)
{
    (void)context;
    (void)application;
    (void)product;
    (void)name;
    if (count)
        *count = 0;
    if (status)
        *status = NULL;
    return SL_E_RIGHT_NOT_CONSUMED;
}

/* Office resolves the remaining APIs dynamically.  Returning E_NOTIMPL is
 * preferable to Wine's generated stub, which raises EXCEPTION_WINE_STUB and
 * terminates the application.  No output is provided and no licensed state is
 * synthesized. */
#define UNIMPLEMENTED(name) \
    __declspec(dllexport) HRESULT WINAPI name(void) { return E_NOTIMPL; }

UNIMPLEMENTED(SLActivateProduct)
UNIMPLEMENTED(SLConsumeRight)
UNIMPLEMENTED(SLDepositOfflineConfirmationId)
UNIMPLEMENTED(SLDepositTokenActivationResponse)
UNIMPLEMENTED(SLFreeTokenActivationCertificates)
UNIMPLEMENTED(SLFreeTokenActivationGrants)
UNIMPLEMENTED(SLGenerateOfflineInstallationId)
UNIMPLEMENTED(SLGenerateTokenActivationChallenge)
UNIMPLEMENTED(SLGetAuthenticationResult)
UNIMPLEMENTED(SLGetInstalledProductKeyIds)
UNIMPLEMENTED(SLGetPKeyId)
UNIMPLEMENTED(SLGetPKeyInformation)
UNIMPLEMENTED(SLGetPolicyInformation)
UNIMPLEMENTED(SLGetProductSkuInformation)
UNIMPLEMENTED(SLGetSLIDList)
UNIMPLEMENTED(SLGetServiceInformation)
UNIMPLEMENTED(SLGetTokenActivationCertificates)
UNIMPLEMENTED(SLGetTokenActivationGrants)
UNIMPLEMENTED(SLInstallLicense)
UNIMPLEMENTED(SLInstallProofOfPurchase)
UNIMPLEMENTED(SLPersistApplicationPolicies)
UNIMPLEMENTED(SLPersistRTSPayloadOverride)
UNIMPLEMENTED(SLRegisterPlugin)
UNIMPLEMENTED(SLSetAuthenticationData)
UNIMPLEMENTED(SLSignTokenActivationChallenge)
UNIMPLEMENTED(SLUninstallLicense)
UNIMPLEMENTED(SLUninstallProofOfPurchase)
