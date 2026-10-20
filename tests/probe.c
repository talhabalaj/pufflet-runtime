#define COBJMACROS
#include <windows.h>
#include <bcrypt.h>
#include <d3d11.h>
#include <dxgi.h>
#include <stdio.h>
static int fonts;
static int CALLBACK font_cb(const LOGFONTA *lf, const TEXTMETRICA *tm, DWORD type, LPARAM p) { fonts++; return 1; }
int main(void)
{
    BCRYPT_ALG_HANDLE alg; BCRYPT_KEY_HANDLE key; NTSTATUS st;
    st = BCryptOpenAlgorithmProvider(&alg, BCRYPT_RSA_ALGORITHM, NULL, 0);
    if (!st) st = BCryptGenerateKeyPair(alg, &key, 2048, 0);
    if (!st) st = BCryptFinalizeKeyPair(key, 0);
    printf("gnutls rsa keygen: %s (%#lx)\n", st ? "FAIL" : "ok", st);

    HDC dc = GetDC(NULL); LOGFONTA lf = {0}; lf.lfCharSet = DEFAULT_CHARSET;
    EnumFontFamiliesExA(dc, &lf, font_cb, 0, 0);
    printf("freetype fonts: %d\n", fonts);

    ID3D11Device *dev; ID3D11DeviceContext *ctx; D3D_FEATURE_LEVEL fl; HRESULT hr;
    hr = D3D11CreateDevice(NULL, D3D_DRIVER_TYPE_HARDWARE, NULL, 0, NULL, 0, D3D11_SDK_VERSION, &dev, &fl, &ctx);
    if (SUCCEEDED(hr)) {
        IDXGIDevice *dxgi; IDXGIAdapter *ad; DXGI_ADAPTER_DESC d;
        ID3D11Device_QueryInterface(dev, &IID_IDXGIDevice, (void **)&dxgi);
        IDXGIDevice_GetAdapter(dxgi, &ad); IDXGIAdapter_GetDesc(ad, &d);
        printf("d3d11: ok, feature level %#x, adapter %ls\n", fl, d.Description);
    } else printf("d3d11: FAIL %#lx\n", hr);
    HMODULE m = GetModuleHandleA("winemetal.dll");
    printf("winemetal.dll loaded: %s\n", m ? "yes" : "no");
    return 0;
}
