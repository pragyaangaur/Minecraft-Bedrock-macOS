// winput: inject mouse clicks and key presses into the game window from inside
// Wine, so no macOS Accessibility permission is needed. It is a freestanding
// console program, built by stubs/build.sh with the import libraries from stubs/lib.
//
// Usage (run inside the Wine prefix):
//   winput info                    print the client size and origin of the "Bedrock" window
//   winput click <xf> <yf>         SetCursorPos + SendInput left click at client fraction xf, yf (0..1)
//   winput pmclick <xf> <yf>       PostMessage WM_LBUTTONDOWN/UP with client coords (no cursor move)
//   winput key <vk> [vk2 ...]      SendInput down+up for each virtual key code (decimal or 0x..)
//   winput hold <ms> <vk> [vk2 ...] press all keys together, hold for ms, release (walk, sprint, jump)
//   winput look <dx> <dy> [steps]  relative mouse move in mickeys, split into steps (turn the camera)
// Fractions are decimals such as 0.77. Window class name: "Bedrock".

typedef unsigned short WCHAR;
typedef unsigned int UINT;
typedef unsigned long DWORD;
typedef unsigned short WORD;
typedef unsigned long long ULONG_PTR;
typedef unsigned long long WPARAM;
typedef long long LPARAM;
typedef long LONG;
typedef int BOOL;
typedef void *HWND;
typedef void *HANDLE;
typedef unsigned long long size_t;

typedef struct { LONG left, top, right, bottom; } RECT;
typedef struct { LONG x, y; } POINT;
typedef struct {
  DWORD type;
  union {
    struct { LONG dx, dy; DWORD mouseData; DWORD dwFlags; DWORD time; ULONG_PTR extra; } mi;
    struct { WORD wVk; WORD wScan; DWORD dwFlags; DWORD time; ULONG_PTR extra; } ki;
  } u;
} INPUT;

__declspec(dllimport) WCHAR *__stdcall GetCommandLineW(void);
__declspec(dllimport) __attribute__((noreturn)) void __stdcall ExitProcess(UINT);
__declspec(dllimport) HANDLE __stdcall GetStdHandle(DWORD);
__declspec(dllimport) BOOL __stdcall WriteFile(HANDLE, const void *, DWORD, DWORD *, void *);
__declspec(dllimport) void __stdcall Sleep(DWORD);

__declspec(dllimport) HWND __stdcall FindWindowW(const WCHAR *, const WCHAR *);
__declspec(dllimport) BOOL __stdcall SetForegroundWindow(HWND);
__declspec(dllimport) BOOL __stdcall GetClientRect(HWND, RECT *);
__declspec(dllimport) BOOL __stdcall ClientToScreen(HWND, POINT *);
__declspec(dllimport) BOOL __stdcall SetCursorPos(int, int);
__declspec(dllimport) UINT __stdcall SendInput(UINT, INPUT *, int);
__declspec(dllimport) BOOL __stdcall PostMessageW(HWND, UINT, WPARAM, LPARAM);

#define INPUT_MOUSE 0
#define INPUT_KEYBOARD 1
#define MOUSEEVENTF_MOVE 0x0001
#define MOUSEEVENTF_LEFTDOWN 0x0002
#define MOUSEEVENTF_LEFTUP 0x0004
#define KEYEVENTF_KEYUP 0x0002
#define WM_MOUSEMOVE 0x0200
#define WM_LBUTTONDOWN 0x0201
#define WM_LBUTTONUP 0x0202
#define MK_LBUTTON 0x0001
#define STD_OUTPUT_HANDLE ((DWORD)-11)

// The freestanding build has no libc, so supply the two helpers clang may emit.
void *memset(void *d, int c, size_t n) {
  unsigned char *p = d;
  while (n--) *p++ = (unsigned char)c;
  return d;
}
void *memcpy(void *d, const void *s, size_t n) {
  unsigned char *p = d;
  const unsigned char *q = s;
  while (n--) *p++ = *q++;
  return d;
}

static void out(const char *s) {
  DWORD n = 0;
  while (s[n]) n++;
  DWORD written = 0;
  WriteFile(GetStdHandle(STD_OUTPUT_HANDLE), s, n, &written, 0);
}

static void out_int(long v) {
  char buf[24];
  int i = 0, neg = v < 0;
  unsigned long u = neg ? (unsigned long)(-v) : (unsigned long)v;
  do { buf[i++] = (char)('0' + u % 10); u /= 10; } while (u);
  if (neg) buf[i++] = '-';
  buf[i] = 0;
  for (int a = 0, b = i - 1; a < b; a++, b--) { char t = buf[a]; buf[a] = buf[b]; buf[b] = t; }
  out(buf);
}

// Next space-separated token of a wide command line, or 0 when none is left.
// Double quotes group a token. Writes a NUL-terminated ASCII copy to dst.
static WCHAR *next_token(WCHAR *p, char *dst, int cap) {
  while (*p == ' ') p++;
  if (!*p) { dst[0] = 0; return 0; }
  int quoted = 0, n = 0;
  if (*p == '"') { quoted = 1; p++; }
  while (*p && (quoted ? *p != '"' : *p != ' ')) {
    if (n < cap - 1) dst[n++] = (char)*p;
    p++;
  }
  if (quoted && *p == '"') p++;
  dst[n] = 0;
  return p;
}

// Parse a decimal or 0x hex number. Returns 0 for anything else.
static long parse_num(const char *s) {
  long v = 0;
  if (s[0] == '0' && (s[1] == 'x' || s[1] == 'X')) {
    for (s += 2; *s; s++) {
      char c = *s;
      int d = (c >= '0' && c <= '9') ? c - '0' : (c >= 'a' && c <= 'f') ? c - 'a' + 10 : (c >= 'A' && c <= 'F') ? c - 'A' + 10 : -1;
      if (d < 0) break;
      v = v * 16 + d;
    }
    return v;
  }
  int neg = *s == '-';
  if (neg) s++;
  for (; *s >= '0' && *s <= '9'; s++) v = v * 10 + (*s - '0');
  return neg ? -v : v;
}

// Parse a fraction such as 0.77 into thousandths (770), clamped to 0..1000.
static long parse_frac(const char *s) {
  long whole = 0, frac = 0, scale = 1;
  while (*s >= '0' && *s <= '9') whole = whole * 10 + (*s++ - '0');
  if (*s == '.') {
    s++;
    while (*s >= '0' && *s <= '9' && scale < 1000) { frac = frac * 10 + (*s++ - '0'); scale *= 10; }
  }
  long v = whole * 1000 + frac * (1000 / scale);
  if (v < 0) v = 0;
  if (v > 1000) v = 1000;
  return v;
}

static HWND find_game(void) {
  static const WCHAR cls[] = { 'B', 'e', 'd', 'r', 'o', 'c', 'k', 0 };
  HWND h = FindWindowW(cls, 0);
  if (!h) out("winput: no window of class Bedrock\n");
  return h;
}

static void mouse(DWORD flags) {
  INPUT in;
  memset(&in, 0, sizeof in);
  in.type = INPUT_MOUSE;
  in.u.mi.dwFlags = flags;
  SendInput(1, &in, sizeof in);
}

static void key(WORD vk, int up) {
  INPUT in;
  memset(&in, 0, sizeof in);
  in.type = INPUT_KEYBOARD;
  in.u.ki.wVk = vk;
  in.u.ki.dwFlags = up ? KEYEVENTF_KEYUP : 0;
  SendInput(1, &in, sizeof in);
}

// Client-area point for the fractions, plus the window's screen origin.
static int locate(HWND h, long xf, long yf, POINT *client, POINT *screen) {
  RECT r;
  POINT origin = { 0, 0 };
  if (!GetClientRect(h, &r)) return 0;
  ClientToScreen(h, &origin);
  client->x = (r.right - r.left) * xf / 1000;
  client->y = (r.bottom - r.top) * yf / 1000;
  screen->x = origin.x + client->x;
  screen->y = origin.y + client->y;
  return 1;
}

static int run(WCHAR *cmdline) {
  char cmd[32], a1[64], a2[64];
  WCHAR *p = cmdline;
  // Skip the program name (quoted or not).
  p = next_token(p, cmd, sizeof cmd);
  if (!p) return 2;
  p = next_token(p, cmd, sizeof cmd);
  if (!p || !cmd[0]) { out("usage: winput info | click x y | pmclick x y | key vk... | hold ms vk... | look dx dy [steps]\n"); return 2; }

  HWND h = find_game();
  if (!h) return 1;

  if (cmd[0] == 'i' && cmd[1] == 'n') {  // info
    RECT r;
    POINT origin = { 0, 0 };
    GetClientRect(h, &r);
    ClientToScreen(h, &origin);
    out("client w="); out_int(r.right - r.left);
    out(" h="); out_int(r.bottom - r.top);
    out(" origin="); out_int(origin.x); out(","); out_int(origin.y); out("\n");
    return 0;
  }

  if (cmd[0] == 'k' && cmd[1] == 'e') {  // key
    SetForegroundWindow(h);
    Sleep(200);
    for (;;) {
      p = next_token(p, a1, sizeof a1);
      if (!p || !a1[0]) break;
      WORD vk = (WORD)parse_num(a1);
      key(vk, 0);
      Sleep(60);
      key(vk, 1);
      Sleep(120);
      out("key "); out_int(vk); out(" sent\n");
    }
    return 0;
  }

  if (cmd[0] == 'h') {  // hold <ms> <vk...>
    WORD vks[16];
    int n = 0;
    p = next_token(p, a1, sizeof a1);
    if (!p) return 2;
    long ms = parse_num(a1);
    while (n < 16) {
      p = next_token(p, a2, sizeof a2);
      if (!p || !a2[0]) break;
      vks[n++] = (WORD)parse_num(a2);
    }
    SetForegroundWindow(h);
    Sleep(200);
    for (int i = 0; i < n; i++) { key(vks[i], 0); Sleep(40); }
    Sleep((DWORD)ms);
    for (int i = n - 1; i >= 0; i--) key(vks[i], 1);
    out("held "); out_int(n); out(" keys for "); out_int(ms); out(" ms\n");
    return 0;
  }

  if (cmd[0] == 'l' && cmd[1] == 'o') {  // look <dx> <dy> [steps]
    char a3[16];
    p = next_token(p, a1, sizeof a1);
    if (!p) return 2;
    p = next_token(p, a2, sizeof a2);
    if (!p) return 2;
    WCHAR *q = next_token(p, a3, sizeof a3);
    long dx = parse_num(a1), dy = parse_num(a2), steps = q && a3[0] ? parse_num(a3) : 10;
    if (steps < 1) steps = 1;
    SetForegroundWindow(h);
    Sleep(100);
    for (long i = 0; i < steps; i++) {
      INPUT in;
      memset(&in, 0, sizeof in);
      in.type = INPUT_MOUSE;
      in.u.mi.dx = dx * (i + 1) / steps - dx * i / steps;
      in.u.mi.dy = dy * (i + 1) / steps - dy * i / steps;
      in.u.mi.dwFlags = MOUSEEVENTF_MOVE;
      SendInput(1, &in, sizeof in);
      Sleep(16);
    }
    out("look sent\n");
    return 0;
  }

  // click / pmclick need two fractions.
  p = next_token(p, a1, sizeof a1);
  if (!p) return 2;
  p = next_token(p, a2, sizeof a2);
  if (!p || !a2[0]) return 2;
  long xf = parse_frac(a1), yf = parse_frac(a2);
  POINT client, screen;
  if (!locate(h, xf, yf, &client, &screen)) { out("winput: GetClientRect failed\n"); return 1; }
  out("target client="); out_int(client.x); out(","); out_int(client.y);
  out(" screen="); out_int(screen.x); out(","); out_int(screen.y); out("\n");

  if (cmd[0] == 'p') {  // pmclick
    LPARAM lp = (LPARAM)(((unsigned long)client.y << 16) | ((unsigned long)client.x & 0xffff));
    PostMessageW(h, WM_MOUSEMOVE, 0, lp);
    Sleep(100);
    PostMessageW(h, WM_LBUTTONDOWN, MK_LBUTTON, lp);
    Sleep(100);
    PostMessageW(h, WM_LBUTTONUP, 0, lp);
    out("pmclick posted\n");
    return 0;
  }

  // click: bring the window forward, move the real cursor, then click.
  SetForegroundWindow(h);
  Sleep(200);
  SetCursorPos((int)screen.x, (int)screen.y);
  Sleep(150);
  mouse(MOUSEEVENTF_LEFTDOWN);
  Sleep(80);
  mouse(MOUSEEVENTF_LEFTUP);
  out("click sent\n");
  return 0;
}

// Entry point: /entry:winput_entry, console subsystem.
void winput_entry(void) {
  int code = run(GetCommandLineW());
  ExitProcess((UINT)code);
}
