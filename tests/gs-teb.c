#include <windows.h>
#include <stdio.h>
static DWORD WINAPI worker(void *arg)
{
    DWORD le, ok = 1;
    void *self, *peb;
    SetLastError(0x1234 + (DWORD)(ULONG_PTR)arg);
    __asm__ volatile("movl %%gs:0x68,%0" : "=r"(le));
    __asm__ volatile("movq %%gs:0x30,%0" : "=r"(self));
    __asm__ volatile("movq %%gs:0x60,%0" : "=r"(peb));
    if (le != GetLastError()) { printf("thread %lu: gs:0x68=%#lx GetLastError=%#lx\n", (ULONG)(ULONG_PTR)arg, le, GetLastError()); ok = 0; }
    if (self != NtCurrentTeb()) { printf("thread %lu: gs:0x30 != TEB\n", (ULONG)(ULONG_PTR)arg); ok = 0; }
    if (peb != ((void **)NtCurrentTeb())[12]) { printf("thread %lu: gs:0x60 != PEB\n", (ULONG)(ULONG_PTR)arg); ok = 0; }
    Sleep(10); /* go through a syscall and come back */
    SetLastError(0x5678);
    __asm__ volatile("movl %%gs:0x68,%0" : "=r"(le));
    if (le != 0x5678) { printf("thread %lu: after Sleep gs:0x68=%#lx\n", (ULONG)(ULONG_PTR)arg, le); ok = 0; }
    return ok;
}
int main(void)
{
    HANDLE h[4]; DWORD i, code, ok = worker(0);
    for (i = 0; i < 4; i++) h[i] = CreateThread(NULL, 0, worker, (void *)(ULONG_PTR)(i + 1), 0, NULL);
    WaitForMultipleObjects(4, h, TRUE, INFINITE);
    for (i = 0; i < 4; i++) { GetExitCodeThread(h[i], &code); ok &= code; }
    printf(ok ? "GS-TEB PASS\n" : "GS-TEB FAIL\n");
    return ok ? 0 : 1;
}
