// Offline stand-in for XCurl.dll, the GDK's libcurl build that libHttpClient
// uses for every HTTP request. It models a PC with no network: handles work,
// but every transfer finishes with CURLE_COULDNT_CONNECT (7) after 250 ms, which
// is about as long as a failed connection takes. Finishing at once raced the
// game's own bookkeeping in libHttpClient's completion path. Each function logs
// to stderr the first time it is called. Variadic setopt and getinfo take their
// third argument as one pointer-sized value, which is what the x64 ABI passes.
typedef unsigned long ULONG;
typedef unsigned long long usize;
typedef struct { int a; } Dummy;

__declspec(dllimport) void *__stdcall GetStdHandle(ULONG);
__declspec(dllimport) int __stdcall WriteFile(void *, const void *, ULONG, ULONG *, void *);
__declspec(dllimport) void *__stdcall GetProcessHeap(void);
__declspec(dllimport) void *__stdcall HeapAlloc(void *, ULONG, usize);
__declspec(dllimport) int __stdcall HeapFree(void *, ULONG, void *);
__declspec(dllimport) void __stdcall Sleep(ULONG);
__declspec(dllimport) usize __stdcall GetTickCount64(void);
/* stubs/build.sh also builds a variant with a huge FAIL_DELAY_MS, so requests
   never finish. tools/run_wine.sh uses it when XCURL=hang is set. */
#ifndef FAIL_DELAY_MS
#define FAIL_DELAY_MS 250
#endif

int _fltused;  // we touch a double; no CRT to define this
#define EXPORT __declspec(dllexport)
#define CURLE_OK 0
#define CURLE_NOT_BUILT_IN 4
#define CURLE_COULDNT_CONNECT 7
#define CURLOPT_PRIVATE 10103
#define CURLINFO_PRIVATE 0x100015
#define CURLUE_UNSUPPORTED_SCHEME 4

static void put(const char *s)
{
    ULONG n = 0, w;
    while (s[n]) n++;
    WriteFile(GetStdHandle((ULONG)-12), s, n, &w, 0);
}

// Log "XCurl: <name>" once per call site. 'flag' is a static byte per function.
static void first(char *flag, const char *name)
{
    if (*flag) return;
    *flag = 1;
    put("XCurl: "); put(name); put("\n");
}
#define LOG() do { static char f_; first(&f_, __func__); } while (0)

static void *alloc(usize n) { return HeapAlloc(GetProcessHeap(), 8, n); }  // zeroed
static void release(void *p) { if (p) HeapFree(GetProcessHeap(), 0, p); }
static usize slen(const char *s) { usize n = 0; while (s[n]) n++; return n; }

typedef struct Easy Easy;
typedef struct Multi Multi;
struct Easy { void *priv; Easy *next; Multi *multi; usize due; };
struct Multi { Easy *head; long queued; struct { int msg; void *easy; usize result; } msg; };

EXPORT int curl_global_init(long flags) { LOG(); return CURLE_OK; }
EXPORT int curl_global_init_mem(long flags, void *m, void *f, void *r, void *s, void *c) { LOG(); return CURLE_OK; }
EXPORT int xcurl_global_init_mem(long flags, void *m, void *f, void *r, void *s, void *c) { LOG(); return CURLE_OK; }
EXPORT void curl_global_cleanup(void) { LOG(); }
EXPORT int curl_global_sslset(int id, const char *name, const void ***avail) { LOG(); if (avail) *avail = 0; return 2; /* CURLSSLSET_UNKNOWN_BACKEND */ }
EXPORT int xcurl_global_resume(void) { LOG(); return CURLE_OK; }
EXPORT int xcurl_global_suspend(void) { LOG(); return CURLE_OK; }
EXPORT int xcurl_global_set_request_limit(unsigned long n) { LOG(); return CURLE_OK; }

EXPORT void *curl_easy_init(void) { LOG(); return alloc(sizeof(Easy)); }
EXPORT void curl_easy_cleanup(void *h) { LOG(); release(h); }
EXPORT void *curl_easy_duphandle(void *h)
{
    LOG();
    Easy *e = alloc(sizeof(Easy));
    if (e && h) e->priv = ((Easy *)h)->priv;
    return e;
}
EXPORT void curl_easy_reset(void *h) { LOG(); if (h) { ((Easy *)h)->priv = 0; } }
EXPORT int curl_easy_setopt(void *h, int opt, usize v)
{
    LOG();
    if (h) {
        Easy *e = h;
        switch (opt) {
        case CURLOPT_PRIVATE: e->priv = (void *)v; break;
        }
    }
    return CURLE_OK;
}
EXPORT int curl_easy_getinfo(void *h, int info, void *out)
{
    LOG();
    if (!out) return CURLE_OK;
    switch (info & 0xf00000) {
    case 0x100000:  // string
        *(void **)out = info == CURLINFO_PRIVATE && h ? ((Easy *)h)->priv : 0; break;
    case 0x200000: *(long *)out = 0; break;  // long; 0x200002 = RESPONSE_CODE
    case 0x300000: *(double *)out = 0; break;
    case 0x400000: case 0x500000: *(void **)out = 0; break;  // slist, ptr
    case 0x600000: *(usize *)out = ~(usize)0; break;          // socket
    case 0x700000: *(long long *)out = 0; break;              // off_t
    }
    return CURLE_OK;
}
EXPORT int curl_easy_perform(void *h) { LOG(); return CURLE_COULDNT_CONNECT; }
EXPORT const char *curl_easy_strerror(int code)
{
    LOG();
    switch (code) {
    case 0: return "No error";
    case 4: return "Feature not enabled in this build";
    case 7: return "Couldn't connect to server (offline stub)";
    default: return "Unknown error (offline stub)";
    }
}
EXPORT char *curl_easy_escape(void *h, const char *s, int len) { LOG(); return 0; }
EXPORT char *curl_easy_unescape(void *h, const char *s, int len, int *outlen) { LOG(); if (outlen) *outlen = 0; return 0; }
EXPORT char *curl_escape(const char *s, int len) { LOG(); return 0; }
EXPORT char *curl_unescape(const char *s, int len) { LOG(); return 0; }
EXPORT void curl_free(void *p) { LOG(); release(p); }
EXPORT long curl_getdate(const char *s, const long *now) { LOG(); return -1; }

EXPORT void *curl_multi_init(void) { LOG(); return alloc(sizeof(Multi)); }
EXPORT int curl_multi_cleanup(void *m) { LOG(); release(m); return 0; }
EXPORT int curl_multi_setopt(void *m, int opt, usize v) { LOG(); return 0; }
EXPORT int curl_multi_add_handle(void *mh, void *eh)
{
    LOG();
    Multi *m = mh; Easy *e = eh, **pp;
    if (!m || !e) return 1;  // CURLM_BAD_HANDLE
    if (e->multi) return 7;  // CURLM_ADDED_ALREADY
    e->multi = m; e->next = 0;
    e->due = GetTickCount64() + FAIL_DELAY_MS;
    for (pp = &m->head; *pp; pp = &(*pp)->next) ;
    *pp = e; m->queued++;
    return 0;
}
EXPORT int curl_multi_remove_handle(void *mh, void *eh)
{
    LOG();
    Multi *m = mh; Easy *e = eh, **pp;
    if (!m || !e) return 1;
    for (pp = &m->head; *pp; pp = &(*pp)->next)
        if (*pp == e) { *pp = e->next; m->queued--; break; }
    e->multi = 0; e->next = 0;
    return 0;
}
EXPORT int curl_multi_perform(void *mh, int *running)
{
    LOG();
    Multi *m = mh;
    int n = 0;
    usize now = GetTickCount64();
    for (Easy *e = m ? m->head : 0; e; e = e->next) {
        if (now < e->due) n++;
    }
    if (running) *running = n;
    return 0;
}
EXPORT void *curl_multi_info_read(void *mh, int *left)
{
    LOG();
    Multi *m = mh;
    if (!m || !m->head || GetTickCount64() < m->head->due) { if (left) *left = 0; return 0; }
    Easy *e = m->head;
    m->head = e->next; e->next = 0; e->multi = 0; m->queued--;
    m->msg.msg = 1;  // CURLMSG_DONE
    m->msg.easy = e;
    m->msg.result = CURLE_COULDNT_CONNECT;
    if (left) *left = (int)m->queued;
    return &m->msg;
}
static int nap(int ms) { Sleep(ms < 0 ? 0 : ms > 10 ? 10 : ms); return 0; }
EXPORT int curl_multi_wait(void *m, void *fds, unsigned n, int ms, int *numfds) { LOG(); if (numfds) *numfds = 0; return nap(ms); }
EXPORT int curl_multi_poll(void *m, void *fds, unsigned n, int ms, int *numfds) { LOG(); if (numfds) *numfds = 0; return nap(ms); }
EXPORT int curl_multi_wakeup(void *m) { LOG(); return 0; }
EXPORT const char *curl_multi_strerror(int code) { LOG(); return code == 0 ? "No error" : "Unknown error (offline stub)"; }

EXPORT void *curl_share_init(void) { LOG(); return alloc(8); }
EXPORT int curl_share_cleanup(void *s) { LOG(); release(s); return 0; }
EXPORT int curl_share_setopt(void *s, int opt, usize v) { LOG(); return 0; }
EXPORT const char *curl_share_strerror(int code) { LOG(); return code == 0 ? "No error" : "Unknown share error (offline stub)"; }

typedef struct Slist { char *data; struct Slist *next; } Slist;
EXPORT Slist *curl_slist_append(Slist *list, const char *s)
{
    LOG();
    Slist *n = alloc(sizeof(Slist));
    usize len = s ? slen(s) : 0;
    char *c = alloc(len + 1);
    if (!n || !c) { release(n); release(c); return 0; }
    for (usize i = 0; i < len; i++) c[i] = s[i];
    n->data = c;
    if (!list) return n;
    Slist *t = list;
    while (t->next) t = t->next;
    t->next = n;
    return list;
}
EXPORT void curl_slist_free_all(Slist *l)
{
    LOG();
    while (l) { Slist *n = l->next; release(l->data); release(l); l = n; }
}

static const char *protocols[] = { 0 };
static struct {
    unsigned age; const char *version; unsigned version_num; const char *host; int features;
    const char *ssl_version; long ssl_version_num; const char *libz_version; const char **protocols;
    const char *ares; int ares_num; const char *libidn; int iconv_ver_num; const char *libssh_version;
    unsigned brotli_ver_num; const char *brotli_version; char pad[128];
} vinfo = { 3, "8.0.0", 0x080000, "x86_64-pc-windows-msvc", 0, 0, 0, 0, protocols };
EXPORT const char *curl_version(void) { LOG(); return "libcurl/8.0.0 (offline stub)"; }
EXPORT void *curl_version_info(int age) { LOG(); return &vinfo; }

EXPORT void *curl_url(void) { LOG(); return 0; }
EXPORT void curl_url_cleanup(void *u) { LOG(); }
EXPORT void *curl_url_dup(void *u) { LOG(); return 0; }
EXPORT int curl_url_get(void *u, int part, char **out, unsigned flags) { LOG(); if (out) *out = 0; return CURLUE_UNSUPPORTED_SCHEME; }
EXPORT int curl_url_set(void *u, int part, const char *s, unsigned flags) { LOG(); return CURLUE_UNSUPPORTED_SCHEME; }

EXPORT int curl_formadd(void *a, void *b, ...) { LOG(); return 3; /* CURL_FORMADD_UNKNOWN_OPTION */ }
EXPORT int curl_formget(void *f, void *a, void *cb) { LOG(); return -1; }
EXPORT void curl_formfree(void *f) { LOG(); }
EXPORT void *curl_mime_init(void *e) { LOG(); return 0; }
EXPORT void curl_mime_free(void *m) { LOG(); }
EXPORT void *curl_mime_addpart(void *m) { LOG(); return 0; }
EXPORT int curl_mime_name(void *p, const char *s) { LOG(); return CURLE_NOT_BUILT_IN; }
EXPORT int curl_mime_filename(void *p, const char *s) { LOG(); return CURLE_NOT_BUILT_IN; }
EXPORT int curl_mime_type(void *p, const char *s) { LOG(); return CURLE_NOT_BUILT_IN; }
EXPORT int curl_mime_encoder(void *p, const char *s) { LOG(); return CURLE_NOT_BUILT_IN; }
EXPORT int curl_mime_data(void *p, const char *d, usize n) { LOG(); return CURLE_NOT_BUILT_IN; }
EXPORT int curl_mime_filedata(void *p, const char *s) { LOG(); return CURLE_NOT_BUILT_IN; }
EXPORT int curl_mime_data_cb(void *p, long long n, void *a, void *b, void *c, void *d) { LOG(); return CURLE_NOT_BUILT_IN; }
EXPORT int curl_mime_subparts(void *p, void *m) { LOG(); return CURLE_NOT_BUILT_IN; }
EXPORT int curl_mime_headers(void *p, void *l, int own) { LOG(); return CURLE_NOT_BUILT_IN; }
