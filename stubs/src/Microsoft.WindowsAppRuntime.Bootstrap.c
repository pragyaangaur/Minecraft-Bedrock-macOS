// Stand-in for the Windows App SDK bootstrapper. The real one asks the
// PackageManager WinRT class to add the framework package to the process,
// which Wine does not have. Report success and do nothing.
typedef unsigned int UINT32;
typedef long HRESULT;
typedef const unsigned short *PCWSTR;
typedef struct { unsigned long long Version; } PACKAGE_VERSION;

__declspec(dllexport) HRESULT MddBootstrapInitialize2(UINT32 majorMinor, PCWSTR tag, PACKAGE_VERSION minVersion, int options)
{
    return 0;
}

__declspec(dllexport) HRESULT MddBootstrapInitialize(UINT32 majorMinor, PCWSTR tag, PACKAGE_VERSION minVersion)
{
    return 0;
}

__declspec(dllexport) void MddBootstrapShutdown(void)
{
}
