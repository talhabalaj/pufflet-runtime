#define COBJMACROS
#include <windows.h>
#include <mfapi.h>
#include <mfidl.h>
#include <mfreadwrite.h>
#include <dshow.h>
#include <stdio.h>
static void mf_test(const WCHAR *url)
{
    IMFSourceReader *r; IMFMediaType *t; HRESULT hr; DWORD idx, flags, frames[2] = {0}; LONGLONG ts; IMFSample *s;
    hr = MFCreateSourceReaderFromURL(url, NULL, &r);
    if (FAILED(hr)) { printf("mf: open FAIL %#lx\n", hr); return; }
    MFCreateMediaType(&t); IMFMediaType_SetGUID(t, &MF_MT_MAJOR_TYPE, &MFMediaType_Video);
    IMFMediaType_SetGUID(t, &MF_MT_SUBTYPE, &MFVideoFormat_RGB32);
    hr = IMFSourceReader_SetCurrentMediaType(r, MF_SOURCE_READER_FIRST_VIDEO_STREAM, NULL, t);
    printf("mf: video RGB32 output %s (%#lx)\n", SUCCEEDED(hr) ? "ok" : "FAIL", hr);
    IMFMediaType_SetGUID(t, &MF_MT_MAJOR_TYPE, &MFMediaType_Audio);
    IMFMediaType_SetGUID(t, &MF_MT_SUBTYPE, &MFAudioFormat_PCM);
    hr = IMFSourceReader_SetCurrentMediaType(r, MF_SOURCE_READER_FIRST_AUDIO_STREAM, NULL, t);
    printf("mf: audio PCM output %s (%#lx)\n", SUCCEEDED(hr) ? "ok" : "FAIL", hr);
    for (int i = 0; i < 200; i++) {
        hr = IMFSourceReader_ReadSample(r, MF_SOURCE_READER_ANY_STREAM, 0, &idx, &flags, &ts, &s);
        if (FAILED(hr) || (flags & MF_SOURCE_READERF_ENDOFSTREAM)) break;
        if (s) { frames[idx & 1]++; IMFSample_Release(s); }
    }
    printf("mf: decoded samples stream0=%lu stream1=%lu\n", frames[0], frames[1]);
}
static void ds_test(const WCHAR *file)
{
    IGraphBuilder *g; HRESULT hr;
    CoCreateInstance(&CLSID_FilterGraph, NULL, CLSCTX_INPROC_SERVER, &IID_IGraphBuilder, (void **)&g);
    hr = IGraphBuilder_RenderFile(g, file, NULL);
    printf("dshow (gstreamer): RenderFile %s (%#lx)\n", SUCCEEDED(hr) ? "ok" : "FAIL", hr);
}
int main(int argc, char **argv)
{
    WCHAR path[MAX_PATH];
    CoInitializeEx(NULL, COINIT_MULTITHREADED);
    MFStartup(MF_VERSION, 0);
    MultiByteToWideChar(CP_ACP, 0, argv[1], -1, path, MAX_PATH);
    mf_test(path);
    ds_test(path);
    return 0;
}
