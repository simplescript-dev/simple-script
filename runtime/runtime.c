#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <time.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <unistd.h>
#include <arpa/inet.h>

void ym_println(const char* s) {
    puts(s);
}

char* ym_string_concat(const char* a, const char* b) {
    size_t la = strlen(a);
    size_t lb = strlen(b);
    char* result = (char*)malloc(la + lb + 1);
    memcpy(result, a, la);
    memcpy(result + la, b, lb);
    result[la + lb] = '\0';
    return result;
}

char* ym_int_to_string(int value) {
    char* buf = (char*)malloc(32);
    snprintf(buf, 32, "%d", value);
    return buf;
}

char* ym_double_to_string(double value) {
    char* buf = (char*)malloc(64);
    snprintf(buf, 64, "%g", value);
    return buf;
}

char* ym_bool_to_string(int value) {
    const char* s = value ? "true" : "false";
    return strdup(s);
}

void ym_print(const char* s) {
    fputs(s, stdout);
    fflush(stdout);
}

char* ym_readLine() {
    char* buf = (char*)malloc(1024);
    if (fgets(buf, 1024, stdin) == NULL) {
        buf[0] = '\0';
        return buf;
    }
    size_t len = strlen(buf);
    if (len > 0 && buf[len-1] == '\n') {
        buf[len-1] = '\0';
    }
    return buf;
}

int ym_parseInt(const char* s) {
    return atoi(s);
}

double ym_parseDouble(const char* s) {
    return atof(s);
}

int ym_stringLength(const char* s) {
    return (int)strlen(s);
}

int ym_string_eq(const char* a, const char* b) {
    return strcmp(a, b) == 0;
}

int ym_string_ne(const char* a, const char* b) {
    return strcmp(a, b) != 0;
}

int ym_startsWith(const char* s, const char* prefix) {
    return strncmp(s, prefix, strlen(prefix)) == 0;
}

int ym_endsWith(const char* s, const char* suffix) {
    size_t slen = strlen(s);
    size_t suflen = strlen(suffix);
    if (suflen > slen) return 0;
    return strcmp(s + slen - suflen, suffix) == 0;
}

char* ym_trim(const char* s) {
    while (*s == ' ' || *s == '\t' || *s == '\n' || *s == '\r') s++;
    size_t len = strlen(s);
    while (len > 0 && (s[len-1] == ' ' || s[len-1] == '\t' || s[len-1] == '\n' || s[len-1] == '\r')) len--;
    char* result = (char*)malloc(len + 1);
    memcpy(result, s, len);
    result[len] = '\0';
    return result;
}

char* ym_replace(const char* s, const char* old, const char* new_str) {
    size_t slen = strlen(s);
    size_t oldlen = strlen(old);
    size_t newlen = strlen(new_str);
    if (oldlen == 0) {
        char* copy = (char*)malloc(slen + 1);
        strcpy(copy, s);
        return copy;
    }
    // Count occurrences
    int count = 0;
    const char* p = s;
    while ((p = strstr(p, old)) != NULL) { count++; p += oldlen; }
    // Build result
    size_t rlen = slen + count * (newlen - oldlen);
    char* result = (char*)malloc(rlen + 1);
    char* w = result;
    p = s;
    while (*p) {
        if (strncmp(p, old, oldlen) == 0) {
            memcpy(w, new_str, newlen);
            w += newlen;
            p += oldlen;
        } else {
            *w++ = *p++;
        }
    }
    *w = '\0';
    return result;
}

char* ym_toUpperCase(const char* s) {
    size_t len = strlen(s);
    char* result = (char*)malloc(len + 1);
    for (size_t i = 0; i < len; i++) {
        result[i] = (s[i] >= 'a' && s[i] <= 'z') ? s[i] - 32 : s[i];
    }
    result[len] = '\0';
    return result;
}

char* ym_toLowerCase(const char* s) {
    size_t len = strlen(s);
    char* result = (char*)malloc(len + 1);
    for (size_t i = 0; i < len; i++) {
        result[i] = (s[i] >= 'A' && s[i] <= 'Z') ? s[i] + 32 : s[i];
    }
    result[len] = '\0';
    return result;
}

int ym_contains(const char* s, const char* sub) {
    return strstr(s, sub) != NULL;
}

char* ym_charAt(const char* s, int index) {
    size_t len = strlen(s);
    if (index < 0 || (size_t)index >= len) return "";
    char* result = (char*)malloc(2);
    result[0] = s[index];
    result[1] = '\0';
    return result;
}

char* ym_repeat(const char* s, int n) {
    size_t slen = strlen(s);
    char* result = (char*)malloc(slen * n + 1);
    char* w = result;
    for (int i = 0; i < n; i++) {
        memcpy(w, s, slen);
        w += slen;
    }
    *w = '\0';
    return result;
}

char* ym_padStart(const char* s, int width, const char* pad) {
    int slen = (int)strlen(s);
    if (slen >= width) return strdup(s);
    int plen = (int)strlen(pad);
    char* result = (char*)malloc(width + 1);
    int fill = width - slen;
    for (int i = 0; i < fill; i++) result[i] = pad[i % plen];
    memcpy(result + fill, s, slen);
    result[width] = '\0';
    return result;
}

char* ym_padEnd(const char* s, int width, const char* pad) {
    int slen = (int)strlen(s);
    if (slen >= width) return strdup(s);
    int plen = (int)strlen(pad);
    char* result = (char*)malloc(width + 1);
    memcpy(result, s, slen);
    int fill = width - slen;
    for (int i = 0; i < fill; i++) result[slen + i] = pad[i % plen];
    result[width] = '\0';
    return result;
}

// split(s, delim) — returns array of strings
long long* ym_split(const char* s, const char* delim) {
    size_t dlen = strlen(delim);
    // Count parts
    int count = 1;
    const char* p = s;
    while ((p = strstr(p, delim)) != NULL) { count++; p += dlen; }

    // Allocate array (slot 0 = length, then string pointers as i64)
    long long* arr = (long long*)calloc(count + 1, sizeof(long long));
    arr[0] = count;

    // Fill parts
    int idx = 0;
    p = s;
    while (1) {
        const char* next = strstr(p, delim);
        size_t plen = next ? (size_t)(next - p) : strlen(p);
        char* part = (char*)malloc(plen + 1);
        memcpy(part, p, plen);
        part[plen] = '\0';
        arr[idx + 1] = (long long)(size_t)part;
        idx++;
        if (!next) break;
        p = next + dlen;
    }
    return arr;
}

char* ym_join(long long* arr, const char* delim) {
    int len = (int)arr[0];
    if (len == 0) return strdup("");
    size_t dlen = strlen(delim);
    size_t total = 0;
    for (int i = 0; i < len; i++) {
        total += strlen((const char*)(size_t)arr[i + 1]);
    }
    total += dlen * (len - 1);
    char* result = (char*)malloc(total + 1);
    char* w = result;
    for (int i = 0; i < len; i++) {
        if (i > 0) { memcpy(w, delim, dlen); w += dlen; }
        const char* s = (const char*)(size_t)arr[i + 1];
        size_t slen = strlen(s);
        memcpy(w, s, slen);
        w += slen;
    }
    *w = '\0';
    return result;
}

char* ym_readFile(const char* path) {
    FILE* f = fopen(path, "rb");
    if (!f) return "";
    fseek(f, 0, SEEK_END);
    long size = ftell(f);
    fseek(f, 0, SEEK_SET);
    char* buf = (char*)malloc(size + 1);
    fread(buf, 1, size, f);
    buf[size] = '\0';
    fclose(f);
    return buf;
}

void ym_writeFile(const char* path, const char* content) {
    FILE* f = fopen(path, "w");
    if (!f) return;
    fputs(content, f);
    fclose(f);
}

void ym_appendFile(const char* path, const char* content) {
    FILE* f = fopen(path, "a");
    if (!f) return;
    fputs(content, f);
    fclose(f);
}

char* ym_substring(const char* s, int start, int len) {
    int slen = (int)strlen(s);
    if (start < 0 || start >= slen) return "";
    if (start + len > slen) len = slen - start;
    char* buf = (char*)malloc(len + 1);
    memcpy(buf, s + start, len);
    buf[len] = '\0';
    return buf;
}

int ym_indexOf(const char* s, const char* sub) {
    const char* p = strstr(s, sub);
    if (!p) return -1;
    return (int)(p - s);
}

char* ym_arrayToString(long long* arr) {
    int len = (int)arr[0];
    size_t cap = len * 24 + 4;
    char* result = (char*)malloc(cap);
    char* w = result;
    *w++ = '[';
    for (int i = 0; i < len; i++) {
        if (i > 0) { *w++ = ','; *w++ = ' '; }
        long long v = arr[i + 1];
        if (v > 0x100000) {
            // Likely string pointer
            const char* s = (const char*)(size_t)v;
            size_t slen = strlen(s);
            // Grow if needed
            size_t used = w - result;
            if (used + slen + 10 > cap) {
                cap = cap * 2 + slen;
                result = (char*)realloc(result, cap);
                w = result + used;
            }
            *w++ = '"';
            memcpy(w, s, slen); w += slen;
            *w++ = '"';
        } else {
            w += snprintf(w, 20, "%lld", v);
        }
    }
    *w++ = ']';
    *w = '\0';
    return result;
}

// Heuristic i64 to string
char* ym_i64_to_string(long long value) {
    // Heuristic: values > 0x100000 are likely pointers on 64-bit
    if (value > 0x100000) {
        return (char*)(size_t)value;
    }
    char* buf = (char*)malloc(32);
    snprintf(buf, 32, "%lld", value);
    return buf;
}

// Array operations — slot 0 stores length, data starts at slot 1
long long* ym_newArray(int size) {
    long long* arr = (long long*)calloc(size + 1, sizeof(long long));
    arr[0] = size;  // length stored at index 0
    return arr;
}

long long ym_arrayGet(long long* arr, int index) {
    return arr[index + 1];  // data offset by 1
}

void ym_arraySet(long long* arr, int index, long long value) {
    arr[index + 1] = value;  // data offset by 1
}

int ym_arrayLen(long long* arr) {
    return (int)arr[0];
}

long long* ym_arrayPush(long long* arr, long long value) {
    int len = (int)arr[0];
    // Reallocate with one more slot
    long long* new_arr = (long long*)realloc(arr, (len + 2) * sizeof(long long));
    new_arr[0] = len + 1;
    new_arr[len + 1] = value;
    return new_arr;
}

void ym_arrayReverse(long long* arr) {
    int len = (int)arr[0];
    for (int i = 0; i < len / 2; i++) {
        long long tmp = arr[i + 1];
        arr[i + 1] = arr[len - i];
        arr[len - i] = tmp;
    }
}

int ym_arrayIndexOf(long long* arr, long long value) {
    int len = (int)arr[0];
    for (int i = 0; i < len; i++) {
        if (arr[i + 1] == value) return i;
    }
    return -1;
}

long long ym_arrayFirst(long long* arr) {
    return arr[0] > 0 ? arr[1] : 0;
}

long long ym_arrayLast(long long* arr) {
    int len = (int)arr[0];
    return len > 0 ? arr[len] : 0;
}

long long* ym_arraySlice(long long* arr, int start, int end) {
    int len = (int)arr[0];
    if (start < 0) start = 0;
    if (end > len) end = len;
    if (start >= end) {
        long long* empty = (long long*)calloc(1, sizeof(long long));
        return empty;
    }
    int new_len = end - start;
    long long* result = (long long*)calloc(new_len + 1, sizeof(long long));
    result[0] = new_len;
    for (int i = 0; i < new_len; i++) {
        result[i + 1] = arr[start + i + 1];
    }
    return result;
}

static int cmp_asc(const void* a, const void* b) {
    long long va = *(const long long*)a;
    long long vb = *(const long long*)b;
    return (va > vb) - (va < vb);
}

void ym_arraySort(long long* arr) {
    int len = (int)arr[0];
    if (len > 1) qsort(arr + 1, len, sizeof(long long), cmp_asc);
}

long long* ym_arrayConcat(long long* a, long long* b) {
    int la = (int)a[0], lb = (int)b[0];
    long long* result = (long long*)calloc(la + lb + 1, sizeof(long long));
    result[0] = la + lb;
    memcpy(result + 1, a + 1, la * sizeof(long long));
    memcpy(result + 1 + la, b + 1, lb * sizeof(long long));
    return result;
}

// ym_mapKeys and ym_mapDelete defined after HashMap

// Command line args (set by main wrapper)
static int ym_argc = 0;
static char** ym_argv = NULL;

void ym_initArgs(int argc, char** argv) {
    ym_argc = argc;
    ym_argv = argv;
}

int ym_argCount() {
    return ym_argc;
}

char* ym_argGet(int index) {
    if (index < 0 || index >= ym_argc) return "";
    return ym_argv[index];
}

// Time
long long ym_timeMs() {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (long long)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

// Process
void ym_exit(int code) {
    exit(code);
}

int ym_system(const char* cmd) {
    return system(cmd);
}

// Math
double ym_sqrt(double x) { return sqrt(x); }
double ym_abs(double x) { return fabs(x); }
double ym_floor(double x) { return floor(x); }
double ym_ceil(double x) { return ceil(x); }
double ym_round(double x) { return round(x); }
double ym_pow(double base, double exp) { return pow(base, exp); }
double ym_log(double x) { return log(x); }
double ym_sin(double x) { return sin(x); }
double ym_cos(double x) { return cos(x); }
double ym_random() { return (double)rand() / RAND_MAX; }
double ym_min(double a, double b) { return a < b ? a : b; }
double ym_max(double a, double b) { return a > b ? a : b; }

// HashMap — simple chained hash map for string keys
#define MAP_BUCKETS 64

typedef struct MapEntry {
    char* key;
    long long value;
    struct MapEntry* next;
} MapEntry;

typedef struct {
    MapEntry* buckets[MAP_BUCKETS];
    int size;
} HashMap;

static unsigned int hash_str(const char* s) {
    unsigned int h = 5381;
    while (*s) { h = h * 33 + (unsigned char)*s++; }
    return h % MAP_BUCKETS;
}

HashMap* ym_mapNew() {
    HashMap* m = (HashMap*)calloc(1, sizeof(HashMap));
    return m;
}

void ym_mapSet(HashMap* m, const char* key, long long value) {
    unsigned int idx = hash_str(key);
    MapEntry* e = m->buckets[idx];
    while (e) {
        if (strcmp(e->key, key) == 0) {
            e->value = value;
            return;
        }
        e = e->next;
    }
    MapEntry* ne = (MapEntry*)malloc(sizeof(MapEntry));
    ne->key = strdup(key);
    ne->value = value;
    ne->next = m->buckets[idx];
    m->buckets[idx] = ne;
    m->size++;
}

long long ym_mapGet(HashMap* m, const char* key) {
    unsigned int idx = hash_str(key);
    MapEntry* e = m->buckets[idx];
    while (e) {
        if (strcmp(e->key, key) == 0) return e->value;
        e = e->next;
    }
    return 0;
}

int ym_mapHas(HashMap* m, const char* key) {
    unsigned int idx = hash_str(key);
    MapEntry* e = m->buckets[idx];
    while (e) {
        if (strcmp(e->key, key) == 0) return 1;
        e = e->next;
    }
    return 0;
}

int ym_mapSize(HashMap* m) {
    return m->size;
}

char* ym_mapKeys(HashMap* m) {
    int total_len = 0;
    for (int i = 0; i < MAP_BUCKETS; i++) {
        MapEntry* e = m->buckets[i];
        while (e) { total_len += strlen(e->key) + 1; e = e->next; }
    }
    char* result = (char*)malloc(total_len + 1);
    char* w = result;
    for (int i = 0; i < MAP_BUCKETS; i++) {
        MapEntry* e = m->buckets[i];
        while (e) {
            size_t klen = strlen(e->key);
            memcpy(w, e->key, klen);
            w += klen;
            *w++ = '\n';
            e = e->next;
        }
    }
    if (w > result) w--;  // remove trailing newline
    *w = '\0';
    return result;
}

void ym_mapDelete(HashMap* m, const char* key) {
    unsigned int idx = hash_str(key);
    MapEntry* e = m->buckets[idx];
    MapEntry* prev = NULL;
    while (e) {
        if (strcmp(e->key, key) == 0) {
            if (prev) prev->next = e->next;
            else m->buckets[idx] = e->next;
            free(e->key);
            free(e);
            m->size--;
            return;
        }
        prev = e;
        e = e->next;
    }
}

// ── TCP Server ────────────────────────────────────────────────

int ym_tcpListen(int port) {
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) return -1;
    int opt = 1;
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));
    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = INADDR_ANY;
    addr.sin_port = htons(port);
    if (bind(fd, (struct sockaddr*)&addr, sizeof(addr)) < 0) { close(fd); return -1; }
    if (listen(fd, 128) < 0) { close(fd); return -1; }
    return fd;
}

int ym_tcpAccept(int serverFd) {
    struct sockaddr_in client;
    socklen_t len = sizeof(client);
    return accept(serverFd, (struct sockaddr*)&client, &len);
}

char* ym_tcpRead(int fd, int maxLen) {
    char* buf = (char*)malloc(maxLen + 1);
    int n = read(fd, buf, maxLen);
    if (n <= 0) { buf[0] = '\0'; return buf; }
    buf[n] = '\0';
    return buf;
}

int ym_tcpWrite(int fd, const char* data) {
    int len = strlen(data);
    return write(fd, data, len);
}

int ym_tcpWriteBytes(int fd, const char* data, int len) {
    return write(fd, data, len);
}

void ym_tcpClose(int fd) {
    close(fd);
}

char* ym_getenv(const char* name) {
    const char* val = getenv(name);
    if (!val) return "";
    return strdup(val);
}

long long ym_timeUnix() {
    return (long long)time(NULL);
}

// ── File system ───────────────────────────────────────────────

#include <sys/stat.h>
#include <dirent.h>

int ym_mkdir(const char* path) {
    return mkdir(path, 0755);
}

int ym_mkdirp(const char* path) {
    char tmp[1024];
    snprintf(tmp, sizeof(tmp), "%s", path);
    size_t len = strlen(tmp);
    if (tmp[len - 1] == '/') tmp[len - 1] = 0;
    for (char* p = tmp + 1; *p; p++) {
        if (*p == '/') {
            *p = 0;
            mkdir(tmp, 0755);
            *p = '/';
        }
    }
    return mkdir(tmp, 0755);
}

int ym_fileExists(const char* path) {
    struct stat st;
    return stat(path, &st) == 0;
}

long long ym_fileSize(const char* path) {
    struct stat st;
    if (stat(path, &st) != 0) return -1;
    return (long long)st.st_size;
}

int ym_removeFile(const char* path) {
    return remove(path);
}

int ym_renameFile(const char* oldPath, const char* newPath) {
    return rename(oldPath, newPath);
}

char* ym_listDir(const char* path) {
    DIR* dir = opendir(path);
    if (!dir) return strdup("");
    struct dirent* entry;
    size_t cap = 1024;
    char* result = (char*)malloc(cap);
    char* w = result;
    *w = '\0';
    while ((entry = readdir(dir)) != NULL) {
        if (entry->d_name[0] == '.') continue; // skip . and ..
        size_t nlen = strlen(entry->d_name);
        size_t used = w - result;
        if (used + nlen + 2 > cap) {
            cap *= 2;
            result = (char*)realloc(result, cap);
            w = result + used;
        }
        if (used > 0) { *w++ = '\n'; }
        memcpy(w, entry->d_name, nlen);
        w += nlen;
        *w = '\0';
    }
    closedir(dir);
    return result;
}

// ── SHA-256 ───────────────────────────────────────────────────

static void sha256_transform(unsigned int state[8], const unsigned char block[64]) {
    static const unsigned int k[64] = {
        0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
        0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
        0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
        0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
        0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
        0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
        0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
        0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2
    };
    unsigned int w[64], a,b,c,d,e,f,g,h,t1,t2;
    for (int i = 0; i < 16; i++)
        w[i] = (block[i*4]<<24)|(block[i*4+1]<<16)|(block[i*4+2]<<8)|block[i*4+3];
    for (int i = 16; i < 64; i++) {
        unsigned int s0 = ((w[i-15]>>7)|(w[i-15]<<25))^((w[i-15]>>18)|(w[i-15]<<14))^(w[i-15]>>3);
        unsigned int s1 = ((w[i-2]>>17)|(w[i-2]<<15))^((w[i-2]>>19)|(w[i-2]<<13))^(w[i-2]>>10);
        w[i] = w[i-16]+s0+w[i-7]+s1;
    }
    a=state[0]; b=state[1]; c=state[2]; d=state[3];
    e=state[4]; f=state[5]; g=state[6]; h=state[7];
    for (int i = 0; i < 64; i++) {
        unsigned int S1 = ((e>>6)|(e<<26))^((e>>11)|(e<<21))^((e>>25)|(e<<7));
        unsigned int ch = (e&f)^((~e)&g);
        t1 = h+S1+ch+k[i]+w[i];
        unsigned int S0 = ((a>>2)|(a<<30))^((a>>13)|(a<<19))^((a>>22)|(a<<10));
        unsigned int maj = (a&b)^(a&c)^(b&c);
        t2 = S0+maj;
        h=g; g=f; f=e; e=d+t1; d=c; c=b; b=a; a=t1+t2;
    }
    state[0]+=a; state[1]+=b; state[2]+=c; state[3]+=d;
    state[4]+=e; state[5]+=f; state[6]+=g; state[7]+=h;
}

char* ym_sha256(const char* data) {
    size_t len = strlen(data);
    unsigned int state[8] = {
        0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,
        0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19
    };
    unsigned char block[64];
    size_t i = 0;
    // Process full blocks
    for (; i + 64 <= len; i += 64)
        sha256_transform(state, (const unsigned char*)data + i);
    // Padding
    size_t rem = len - i;
    memset(block, 0, 64);
    memcpy(block, data + i, rem);
    block[rem] = 0x80;
    if (rem >= 56) {
        sha256_transform(state, block);
        memset(block, 0, 64);
    }
    unsigned long long bits = (unsigned long long)len * 8;
    for (int j = 0; j < 8; j++)
        block[56+j] = (bits >> (56-j*8)) & 0xff;
    sha256_transform(state, block);
    // Format as hex
    char* hex = (char*)malloc(65);
    for (int j = 0; j < 8; j++)
        snprintf(hex + j*8, 9, "%08x", state[j]);
    hex[64] = '\0';
    return hex;
}
