// Created by Roel Van de Paar, MariaDB
// corlogic - query correctness and logic differential tester. Single-file C++20.
//
// Feeds one deterministic SQL stream (simplified generatorcpp output) to N server "sides"
// in lockstep, compares per-query outcomes (state/errors/warnings/results/affected rows),
// execution plans (EXPLAIN rows-product ratio), performance (factor + absolute delta),
// and table checksums (client-side content hashes). Any difference is natively reduced
// (deterministic replay, no sporadic logic) and emitted as paste-ready bug artifacts:
// bugN.report (Jira syntax, self-contained) + bugN.log.sh per bug; a crash adds
// bugN.sql / bugN.core / bugN.master.err / reducer<trial>.sh.
//
// Sides: any mix of MariaDB/MySQL basedirs (tar-style or in-tree), engines, server options,
// or optimizer_switch combinatorics (pairwise-exhaustive, cursor-resumable). Runtime lives
// in RUNDIR_BASE/<7-digit runid>, tmpfs by default; results in WORKDIR_BASE/<7-digit runid>.
// Known diffs are filtered via
// mechanism-keyed UIDs (CATEGORY|MECHANISM|CONSTRUCTS|STATEMENT) in corlogic.known.
//
// Build: ./build.sh   Usage: corlogic [--config F] [--seed N] [--check] [--resume ID]
//                            [--selftest [N]] [KEY=VALUE ...] [basedir1 basedir2 ...]
#include <algorithm>
#include <array>
#include <atomic>
#include <cctype>
#include <cerrno>
#include <charconv>
#include <chrono>
#include <cinttypes>
#include <cmath>
#include <condition_variable>
#include <future>
#include <csignal>
#include <cstdarg>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <deque>
#include <filesystem>
#include <fstream>
#include <functional>
#include <map>
#include <mutex>
#include <optional>
#include <regex>
#include <set>
#include <sstream>
#include <string>
#include <string_view>
#include <thread>
#include <unordered_map>
#include <unordered_set>
#include <vector>
#include <fcntl.h>
#include <glob.h>
#include <poll.h>
#include <pwd.h>
#include <spawn.h>
#include <strings.h>
#include <sys/statvfs.h>
#include <sys/ioctl.h>
#include <sys/random.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/prctl.h>
#include <sys/wait.h>
#include <termios.h>
#include <unistd.h>
#include <mysql/mysql.h>

namespace fs = std::filesystem;
using std::string;
using std::vector;

static const char* CORLOGIC_VERSION = "1.0";

// The client library allocates state for a thread on its first use there, and the thread
// gives it back. Every thread that talks to a server declares one of these.
struct MysqlThreadScope {
  ~MysqlThreadScope() { mysql_thread_end(); }
};

// ---------------------------------------------------------------------------
// xoshiro256++ (matches the framework RNG; generator.cpp carries the same core)
// ---------------------------------------------------------------------------
struct Xoshiro256pp {
  uint64_t s[4]{};
  static inline uint64_t splitmix64(uint64_t& x) {
    uint64_t z = (x += 0x9E3779B97F4A7C15ULL);
    z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9ULL;
    z = (z ^ (z >> 27)) * 0x94D049BB133111EBULL;
    return z ^ (z >> 31);
  }
  void seed(uint64_t z) {
    s[0] = splitmix64(z); s[1] = splitmix64(z);
    s[2] = splitmix64(z); s[3] = splitmix64(z);
    if ((s[0] | s[1] | s[2] | s[3]) == 0) s[0] = 0x9E3779B97F4A7C15ULL;
  }
  void seed_full() {
    uint64_t z = 0;
    if (getrandom(s, sizeof(s), 0) != (ssize_t)sizeof(s)) {
      z = (uint64_t)time(nullptr);
    }
    z ^= (uint64_t)getpid() << 32;
    z ^= (uint64_t)std::chrono::steady_clock::now().time_since_epoch().count();
    uint64_t stackaddr = (uint64_t)(uintptr_t)&z;
    z ^= stackaddr;
    for (auto& w : s) w ^= splitmix64(z);
    if ((s[0] | s[1] | s[2] | s[3]) == 0) s[0] = 0x9E3779B97F4A7C15ULL;
  }
  static inline uint64_t rotl(uint64_t x, int k) { return (x << k) | (x >> (64 - k)); }
  uint64_t next() {
    uint64_t r = rotl(s[0] + s[3], 23) + s[0];
    uint64_t t = s[1] << 17;
    s[2] ^= s[0]; s[3] ^= s[1]; s[1] ^= s[2]; s[0] ^= s[3]; s[2] ^= t;
    s[3] = rotl(s[3], 45);
    return r;
  }
  uint64_t below(uint64_t n) { return n ? next() % n : 0; }
};

// ---------------------------------------------------------------------------
// small utilities
// ---------------------------------------------------------------------------
static inline uint64_t fnv1a(std::string_view s) {
  uint64_t h = 1469598103934665603ULL;
  for (unsigned char c : s) { h ^= c; h *= 1099511628211ULL; }
  return h;
}
static inline string trim(std::string_view v) {
  size_t a = 0, b = v.size();
  while (a < b && isspace((unsigned char)v[a])) a++;
  while (b > a && isspace((unsigned char)v[b - 1])) b--;
  return string(v.substr(a, b - a));
}
static inline string upper(std::string_view v) {
  string r(v);
  for (auto& c : r) c = (char)toupper((unsigned char)c);
  return r;
}
static inline string lower(std::string_view v) {
  string r(v);
  for (auto& c : r) c = (char)tolower((unsigned char)c);
  return r;
}
static vector<string> split(std::string_view v, char sep) {
  vector<string> out;
  size_t p = 0;
  while (p <= v.size()) {
    size_t q = v.find(sep, p);
    if (q == string::npos) { out.push_back(trim(v.substr(p))); break; }
    out.push_back(trim(v.substr(p, q - p)));
    p = q + 1;
  }
  while (!out.empty() && out.back().empty()) out.pop_back();
  return out;
}
static inline bool icontains(std::string_view hay, std::string_view needle) {
  if (needle.empty()) return true;
  auto it = std::search(hay.begin(), hay.end(), needle.begin(), needle.end(),
    [](char a, char b) { return toupper((unsigned char)a) == toupper((unsigned char)b); });
  return it != hay.end();
}
static inline bool starts_with_i(std::string_view s, std::string_view p) {
  if (s.size() < p.size()) return false;
  for (size_t i = 0; i < p.size(); i++)
    if (toupper((unsigned char)s[i]) != toupper((unsigned char)p[i])) return false;
  return true;
}
static string read_file(const string& path) {
  std::ifstream f(path, std::ios::binary);
  if (!f) return {};
  std::ostringstream ss; ss << f.rdbuf();
  return ss.str();
}
static bool write_file(const string& path, std::string_view content) {
  std::ofstream f(path, std::ios::binary | std::ios::trunc);
  if (!f) return false;
  f.write(content.data(), (std::streamsize)content.size());
  return (bool)f;
}
static bool append_file(const string& path, std::string_view content) {
  std::ofstream f(path, std::ios::binary | std::ios::app);
  if (!f) return false;
  f.write(content.data(), (std::streamsize)content.size());
  return (bool)f;
}
static string now_hms() {
  time_t t = time(nullptr);
  struct tm tmv{};
  localtime_r(&t, &tmv);
  char buf[32];
  strftime(buf, sizeof(buf), "%H:%M:%S", &tmv);
  return buf;
}
static double now_ms() {
  return (double)std::chrono::duration_cast<std::chrono::microseconds>(
    std::chrono::steady_clock::now().time_since_epoch()).count() / 1000.0;
}
static string human_bytes(uint64_t b) {
  char buf[32];
  if (b >= (1ULL << 30)) snprintf(buf, sizeof(buf), "%.1fG", (double)b / (1ULL << 30));
  else if (b >= (1ULL << 20)) snprintf(buf, sizeof(buf), "%.1fM", (double)b / (1ULL << 20));
  else snprintf(buf, sizeof(buf), "%" PRIu64 "K", b >> 10);
  return buf;
}
static string home_dir() {
  const char* h = getenv("HOME");
  if (h && *h) return h;
  struct passwd* pw = getpwuid(getuid());
  return pw ? pw->pw_dir : "/tmp";
}
// RAM: returns {total_kb, available_kb}
static std::pair<uint64_t, uint64_t> meminfo() {
  std::ifstream f("/proc/meminfo");
  string k; uint64_t v; string unit;
  uint64_t total = 0, avail = 0;
  while (f >> k >> v >> unit) {
    if (k == "MemTotal:") total = v;
    else if (k == "MemAvailable:") { avail = v; break; }
  }
  return {total, avail};
}

// bytes a directory tree holds, in KB
static uint64_t dir_kb(const string& p) {
  uint64_t b = 0;
  std::error_code ec;
  for (fs::recursive_directory_iterator it(p, ec), end; it != end; it.increment(ec)) {
    if (ec) break;
    if (!it->is_regular_file(ec) || ec) continue;
    uintmax_t sz = it->file_size(ec);                  // a file the server just removed
    if (!ec) b += sz;
  }
  return b / 1024;
}
// resident size of a live process, in KB
static uint64_t rss_kb(pid_t pid) {
  std::ifstream f("/proc/" + std::to_string((long)pid) + "/statm");
  uint64_t pages = 0, res = 0;
  if (f >> pages >> res) return res * (uint64_t)(sysconf(_SC_PAGESIZE) / 1024);
  return 0;
}
// free space where p lives, in KB
static uint64_t fs_free_kb(const string& p) {
  struct statvfs v;
  if (statvfs(p.c_str(), &v) != 0) return 0;
  return (uint64_t)v.f_bavail * (uint64_t)v.f_frsize / 1024;
}

// ---------------------------------------------------------------------------
// logging (plain log always; TUI reads the same event stream later)
// ---------------------------------------------------------------------------
static std::mutex g_log_mtx;
static FILE* g_logf = nullptr;
static std::atomic<bool> g_tui_active{false};
static void logline(const char* fmt, ...) {
  char body[4096];
  va_list ap;
  va_start(ap, fmt);
  vsnprintf(body, sizeof(body), fmt, ap);
  va_end(ap);
  std::lock_guard<std::mutex> lk(g_log_mtx);
  string line = "[" + now_hms() + "] " + body + "\n";
  if (g_logf) { fputs(line.c_str(), g_logf); fflush(g_logf); }
  if (!g_tui_active.load()) { fputs(line.c_str(), stdout); fflush(stdout); }
}
// an outcome that needs a person to look at it: red on the terminal, plain in the log
static void logline_alert(const char* fmt, ...) {
  char body[4096];
  va_list ap;
  va_start(ap, fmt);
  vsnprintf(body, sizeof(body), fmt, ap);
  va_end(ap);
  std::lock_guard<std::mutex> lk(g_log_mtx);
  string line = "[" + now_hms() + "] " + body + "\n";
  if (g_logf) { fputs(line.c_str(), g_logf); fflush(g_logf); }
  if (!g_tui_active.load()) {
    bool tty = isatty(1);
    fputs(tty ? ("\x1b[1;31m" + line.substr(0, line.size() - 1) + "\x1b[0m\n").c_str()
              : line.c_str(), stdout);
    fflush(stdout);
  }
}
static void die(const char* fmt, ...) {
  char body[4096];
  va_list ap;
  va_start(ap, fmt);
  vsnprintf(body, sizeof(body), fmt, ap);
  va_end(ap);
  logline("FATAL: %s", body);
  if (!g_logf) fprintf(stderr, "FATAL: %s\n", body);
  exit(1);
}

// ---------------------------------------------------------------------------
// configuration
// ---------------------------------------------------------------------------
struct Cfg {
  // sides
  vector<string> basedirs;                 // resolved absolute paths
  vector<string> pos_basedirs;             // positional CLI paths, merged after BASEDIRS=
  std::map<int, string> bin_side;          // BIN_SIDE<N> overrides (1-based)
  string engine = "innodb";                // forced engine when ENGINES empty
  vector<string> engines;                  // engine-matrix sides on one basedir
  int engine_mix = 0;                      // rotate engines per table (same map all sides)
  string fk = "auto";                      // auto|0|1
  vector<string> options_sets;             // ';'-separated option groups -> sides
  string myextra;                          // all sides
  std::map<int, string> myextra_side;      // per side
  string myinit;                           // extra init options
  // stream
  long queries_per_trial = 1000;
  long trials = 0;                         // 0 = infinite
  uint64_t seed = 0;                       // 0 = entropy
  int partitioning = 1;                    // 0|1|2(=full)
  int views = 0, sequences = 0, generated_columns = 0, tx = 1;
  string sql_filter_file;                  // user ERE drop-list
  string seed_sql;                         // seed override file
  int seed_schema = 1;
  // compare
  string error_compare = "auto";           // auto|state|code|text
  string warning_compare = "auto";         // auto|off|state|codes|text
  int warnings_as_bug = 0;                 // 0: warning-only deltas are counted notes
  int version_sweep = 1;                   // replay each reduced bug across gendirs.sh builds
  int ver_sweep_jobs = 7;                  // version sweeps replaying at the same time
  int float_digits = 10;
  long rows_cap = 100000;
  int skip_parse_errors = 1;
  long checkpoint_every = 250;
  long stats_sample_pages = 2000;          // ANALYZE sample size: high enough to count
  int reduce_step_attempts = 3;            // most passes one reduction step may spend
  string pin_mode = "fixed";               // fixed values, or each side's own global value
  string plan_perf_report = "auto";        // auto: off when the sides differ only by options
  int max_sporadic_attempts = 15;          // fresh-instance replays a sporadic diff gets
  int plan_compare = 1;
  int plan_stats_refresh = 1;              // ANALYZE both sides between the two plan reads
  double plan_factor = 3.0, plan_factor_cross = 10.0;
  double perf_factor = 4.0;
  double perf_min_delta = 250.0;           // ms
  double query_timeout = 60.0;             // s
  // combinatorics
  int optimizer_switch_combinatorics = 0;
  string optimizer_switch_flags = "all-common";
  // reduction
  long reduce_timeout = 1800;              // s
  int strict_reduce = 0;
  // runtime
  int workers = 0;                         // 0 = one and a half per cpu thread
  string workdir_base = "/data";
  string rundir_base = "/dev/shm";
  int keep_all_trials = 0;
  string known_file;                       // one path, or several comma separated
  bool known_file_set = false;             // named on the command line or in the config
  string generator_bin;                    // default resolved at startup
  string weights_file;                     // default resolved at startup
  string client_plugin_dir;                // client auth plugins; default resolved at startup
  string tui = "auto";                     // auto|0|1
  int ram_limit_pct = 85;
  string charset = "utf8mb4";
  string collation = "utf8mb4_general_ci";
  string sql_mode;                         // replaces default when set
  string sql_mode_add, sql_mode_remove;
  string mem_caps =                        // memory + speed preset pack, overridable
    "--loose-innodb_buffer_pool_size=256M --loose-max_allowed_packet=64M "
    "--loose-innodb_stats_persistent=1 --loose-innodb_stats_auto_recalc=0 "
    "--loose-performance_schema=OFF --loose-skip-log-bin "
    "--loose-innodb_flush_log_at_trx_commit=0 --loose-sync_binlog=0";
  // modes
  bool check_only = false;
  string resume_id;
  // raw config values seen (for the workdir copy)
  vector<std::pair<string, string>> raw_kv;
};
static Cfg g_cfg;
static vector<string> g_resume_notes;    // what a resumed run had to say about its config
static string g_cli_block;               // the command line, as config lines, for conf.used

// ONLY_FULL_GROUP_BY is required: a bare column under GROUP BY returns an arbitrary
// row of the group, which no differential compare can verify
static const char* SQL_MODE_DEFAULT =
  "STRICT_TRANS_TABLES,ERROR_FOR_DIVISION_BY_ZERO,NO_ENGINE_SUBSTITUTION,ONLY_FULL_GROUP_BY";

static bool cfg_set(Cfg& c, const string& key_in, const string& val) {
  string key = upper(key_in);
  // a setting that is not a number at all is a typo, and a silent 0 for it costs a run
  auto want_long = [&]() {
    char* end = nullptr;
    long v = strtol(val.c_str(), &end, 10);
    if (val.empty() || !end || *end) die("%s=%s: a whole number is expected", key.c_str(), val.c_str());
    return v;
  };
  // a seed uses the whole 64-bit range, so it is read unsigned, and the same check applies
  auto want_ull = [&]() {
    char* end = nullptr;
    errno = 0;
    unsigned long long v = strtoull(val.c_str(), &end, 10);
    if (val.empty() || !end || *end || errno == ERANGE || val[0] == '-')
      die("%s=%s: a whole number is expected", key.c_str(), val.c_str());
    return (uint64_t)v;
  };
  auto as_long = [&](long& t) { t = want_long(); };
  auto as_int = [&](int& t) { t = (int)want_long(); };
  auto as_dbl = [&](double& t) {
    char* end = nullptr;
    double v = strtod(val.c_str(), &end);
    if (val.empty() || !end || *end) die("%s=%s: a number is expected", key.c_str(), val.c_str());
    t = v;
  };
  if (key == "BASEDIRS") {
    c.basedirs.clear();
    for (auto& b : split(val, ',')) { string t = trim(b); if (!t.empty()) c.basedirs.push_back(t); }
  }
  else if (key.rfind("BIN_SIDE", 0) == 0 && key.size() > 8 &&
           key.find_first_not_of("0123456789", 8) == string::npos)
    c.bin_side[atoi(key.c_str() + 8)] = val;   // BIN_SIDE with no number is an unknown key
  else if (key == "ENGINE") c.engine = lower(val);
  else if (key == "ENGINES") { c.engines.clear(); for (auto& e : split(val, ',')) if (!e.empty()) c.engines.push_back(lower(e)); }
  else if (key == "ENGINE_MIX") as_int(c.engine_mix);
  else if (key == "FK") c.fk = lower(val);
  else if (key == "OPTIONS_SETS") { c.options_sets.clear(); for (auto& o : split(val, ';')) c.options_sets.push_back(o); }
  else if (key == "MYEXTRA") c.myextra = val;
  else if (key.rfind("MYEXTRA_SIDE", 0) == 0 && key.size() > 12 &&
           key.find_first_not_of("0123456789", 12) == string::npos)
    c.myextra_side[atoi(key.c_str() + 12)] = val;   // MYEXTRA_SIDE with no number is unknown
  else if (key == "MYINIT") c.myinit = val;
  else if (key == "QUERIES_PER_TRIAL") as_long(c.queries_per_trial);
  else if (key == "TRIALS") as_long(c.trials);
  else if (key == "SEED") c.seed = want_ull();
  else if (key == "PARTITIONING") c.partitioning = (lower(val) == "full") ? 2 : (int)want_long();
  else if (key == "VIEWS") as_int(c.views);
  else if (key == "SEQUENCES") as_int(c.sequences);
  else if (key == "GENERATED_COLUMNS") as_int(c.generated_columns);
  else if (key == "TX") as_int(c.tx);
  else if (key == "SQL_FILTER_FILE") c.sql_filter_file = val;
  else if (key == "SEED_SQL") c.seed_sql = val;
  else if (key == "SEED_SCHEMA") as_int(c.seed_schema);
  else if (key == "ERROR_COMPARE") c.error_compare = lower(val);
  else if (key == "WARNING_COMPARE") c.warning_compare = lower(val);
  else if (key == "WARNINGS_AS_BUG") as_int(c.warnings_as_bug);
  else if (key == "VERSION_SWEEP") as_int(c.version_sweep);
  else if (key == "VER_SWEEP_JOBS") as_int(c.ver_sweep_jobs);
  else if (key == "FLOAT_DIGITS") as_int(c.float_digits);
  else if (key == "ROWS_CAP") as_long(c.rows_cap);
  else if (key == "SKIP_PARSE_ERRORS") as_int(c.skip_parse_errors);
  else if (key == "CHECKPOINT_EVERY") as_long(c.checkpoint_every);
  else if (key == "STATS_SAMPLE_PAGES") as_long(c.stats_sample_pages);
  else if (key == "REDUCE_STEP_ATTEMPTS") as_int(c.reduce_step_attempts);
  else if (key == "PIN_MODE") c.pin_mode = lower(val);
  else if (key == "PLAN_PERF_REPORT") c.plan_perf_report = lower(val);
  else if (key == "MAX_SPORADIC_ISSUE_REPEAT_ATTEMPTS") as_int(c.max_sporadic_attempts);
  else if (key == "PLAN_COMPARE") as_int(c.plan_compare);
  else if (key == "PLAN_STATS_REFRESH") as_int(c.plan_stats_refresh);
  else if (key == "PLAN_FACTOR") as_dbl(c.plan_factor);
  else if (key == "PLAN_FACTOR_CROSS") as_dbl(c.plan_factor_cross);
  else if (key == "PERF_FACTOR") as_dbl(c.perf_factor);
  else if (key == "PERF_MIN_DELTA") as_dbl(c.perf_min_delta);
  else if (key == "QUERY_TIMEOUT") as_dbl(c.query_timeout);
  else if (key == "OPTIMIZER_SWITCH_COMBINATORICS") as_int(c.optimizer_switch_combinatorics);
  else if (key == "OPTIMIZER_SWITCH_FLAGS") c.optimizer_switch_flags = lower(val);
  else if (key == "REDUCE_TIMEOUT") as_long(c.reduce_timeout);
  else if (key == "STRICT_REDUCE") as_int(c.strict_reduce);
  else if (key == "WORKERS") as_int(c.workers);
  else if (key == "WORKDIR_BASE") c.workdir_base = val;
  else if (key == "RUNDIR_BASE") c.rundir_base = val;
  else if (key == "KEEP_ALL_TRIALS") as_int(c.keep_all_trials);
  else if (key == "KNOWN_FILE") { c.known_file = val; c.known_file_set = !val.empty(); }
  else if (key == "CLIENT_PLUGIN_DIR") c.client_plugin_dir = val;
  else if (key == "GENERATOR_BIN") c.generator_bin = val;
  else if (key == "WEIGHTS_FILE") c.weights_file = val;
  else if (key == "TUI") c.tui = lower(val);
  else if (key == "RAM_LIMIT_PCT") as_int(c.ram_limit_pct);
  else if (key == "CHARSET") c.charset = lower(val);
  else if (key == "COLLATION") c.collation = lower(val);
  else if (key == "SQL_MODE") c.sql_mode = val;
  else if (key == "SQL_MODE_ADD") c.sql_mode_add = val;
  else if (key == "SQL_MODE_REMOVE") c.sql_mode_remove = val;
  else if (key == "MEM_CAPS") c.mem_caps = val;
  else return false;
  c.raw_kv.emplace_back(key, val);
  return true;
}

static void cfg_load_file(Cfg& c, const string& path, bool required) {
  std::ifstream f(path);
  if (!f) {
    if (required) die("cannot read config file %s", path.c_str());
    return;
  }
  string line;
  int ln = 0;
  while (std::getline(f, line)) {
    ln++;
    // strip comments: # outside quotes
    bool in_s = false, in_d = false;
    for (size_t i = 0; i < line.size(); i++) {
      char ch = line[i];
      if (ch == '\'' && !in_d) in_s = !in_s;
      else if (ch == '"' && !in_s) in_d = !in_d;
      else if (ch == '#' && !in_s && !in_d) { line.resize(i); break; }
    }
    line = trim(line);
    if (line.empty()) continue;
    size_t eq = line.find('=');
    if (eq == string::npos) { logline("config %s:%d ignored (no '='): %s", path.c_str(), ln, line.c_str()); continue; }
    string key = trim(line.substr(0, eq));
    string val = trim(line.substr(eq + 1));
    if (val.size() >= 2 && ((val.front() == '"' && val.back() == '"') || (val.front() == '\'' && val.back() == '\'')))
      val = val.substr(1, val.size() - 2);
    if (!cfg_set(c, key, val))
      logline("config %s:%d unknown key: %s", path.c_str(), ln, key.c_str());
  }
}

// ---------------------------------------------------------------------------
// vendors and basedir probing
// ---------------------------------------------------------------------------
enum class Vendor { MariaDB, MySQL, Unknown };
static const char* vendor_name(Vendor v) {
  return v == Vendor::MariaDB ? "MariaDB" : v == Vendor::MySQL ? "MySQL" : "Unknown";
}

// An engine name is written the way its own documentation writes it, so a report reads
// InnoDB and MyISAM, not innodb and myisam. A name that is not in the list is passed on
// as it was given.
static string engine_name(const string& e) {
  static const char* names[] = {
    "InnoDB", "Aria", "MyISAM", "MEMORY", "RocksDB", "Spider", "CONNECT", "ARCHIVE",
    "CSV", "S3", "Mroonga", "FederatedX", "BLACKHOLE", "SEQUENCE", "MRG_MyISAM",
    "OQGRAPH", "PERFORMANCE_SCHEMA", "Columnstore", "MyRocks", "SphinxSE", "HEAP",
    "MERGE", "PARTITION"};
  string lo = e;
  for (auto& c : lo) c = (char)tolower((unsigned char)c);
  for (const char* n : names) {
    string nl = n;
    for (auto& c : nl) c = (char)tolower((unsigned char)c);
    if (nl == lo) return n;
  }
  return e;
}

// The Jira component for an engine, exactly as the MDEV project spells it. An engine with
// no component of its own returns an empty string.
static string engine_component(const string& e) {
  static const std::pair<const char*, const char*> map[] = {
    {"innodb", "InnoDB"}, {"aria", "Aria"}, {"myisam", "MyISAM"}, {"memory", "Memory"},
    {"heap", "Memory"}, {"rocksdb", "RocksDB"}, {"csv", "CSV"}, {"archive", "Archive"},
    {"connect", "Connect"}, {"spider", "Spider"}, {"mroonga", "Mroonga"}, {"s3", "S3"},
    {"sequence", "Sequence"}, {"oqgraph", "OQGRAPH"}, {"sphinx", "SphinxSE"},
    {"federated", "Federated"}, {"federatedx", "Federated"}, {"columnstore", "ColumnStore"},
    {"duckdb", "DuckDB"}, {"videx", "Videx"}, {"xtradb", "XtraDB"}, {"tokudb", "TokuDB"},
    {"cassandra", "Cassandra"}};
  string lo = e;
  for (auto& c : lo) c = (char)tolower((unsigned char)c);
  for (auto& [k, v] : map) if (lo == k) return string("Storage Engine - ") + v;
  return {};
}

// What a testcase must run before it can use an engine. MTR's main suite starts with the
// built-in engines only, so a plugin engine is installed first, and where the test tree
// ships a guard include that is sourced as well, which makes the test skip cleanly on a
// build without the engine. A built-in engine needs neither line.
static string engine_prelude(const string& basedir, const string& engine) {
  string e = engine;
  for (auto& c : e) c = (char)tolower((unsigned char)c);
  if (e.empty()) return {};
  std::error_code ec;
  string out;
  if (fs::exists(basedir + "/lib/plugin/ha_" + e + ".so", ec))
    out += "INSTALL SONAME 'ha_" + e + "';\n";
  for (const char* d : {"/mariadb-test/include/", "/mysql-test/include/"})
    if (fs::exists(basedir + d + "have_" + e + ".inc", ec)) {
      out += "--source include/have_" + e + ".inc\n";
      break;
    }
  return out;
}

struct SideSpec {
  int idx = 0;                       // 1-based
  string basedir;                    // absolute
  string bin;                        // server binary (absolute)
  string init_tool;                  // install-db script or bin (--initialize-insecure)
  bool init_via_bin = false;
  string srcdir;                     // in-tree builds only: the source tree
  string builddir;                   // in-tree builds only: build dir (== srcdir when in-source)
  Vendor vendor = Vendor::Unknown;
  long ver_major = 0, ver_minor = 0, ver_patch = 0;
  string ver_string;                 // from BIN --version
  bool debug_build = false;
  string engine;                     // default engine for this side
  string options;                    // extra server options (options_set + myextra)
  string label;                      // short display label
  long vnum() const { return ver_major * 10000 + ver_minor * 100 + ver_patch; }
};

static string probe_server_bin(const string& basedir) {
  static const char* cands[] = {
    "bin/mariadbd", "bin/mysqld", "bin/mysqld-debug", "sql/mariadbd", "sql/mysqld",
    "bld/sql/mariadbd", "build/sql/mariadbd"
  };
  for (auto* c : cands) {
    fs::path p = fs::path(basedir) / c;
    std::error_code ec;
    if (fs::exists(p, ec) && !fs::is_directory(p, ec) && access(p.c_str(), X_OK) == 0) return p.string();
  }
  return {};
}

// run a command, capture combined output (bounded), return exit status or -1.
// Hard timeout: the child is killed and status is -2, so a wedged external
// call (or one whose descendants keep the pipe open) can never hang corlogic.
struct RunOut { int status = -1; string out; };
static RunOut run_capture(const vector<string>& argv, const string& cwd = "",
                          size_t max_out = 262144, int timeout_sec = 60) {
  RunOut r;
  int pfd[2];
  if (pipe(pfd) != 0) return r;
  vector<char*> av;
  for (auto& a : argv) av.push_back(const_cast<char*>(a.c_str()));
  av.push_back(nullptr);
  posix_spawn_file_actions_t fa;
  posix_spawn_file_actions_init(&fa);
  posix_spawn_file_actions_adddup2(&fa, pfd[1], 1);
  posix_spawn_file_actions_adddup2(&fa, pfd[1], 2);
  posix_spawn_file_actions_addclose(&fa, pfd[0]);
  if (!cwd.empty()) posix_spawn_file_actions_addchdir_np(&fa, cwd.c_str());
  pid_t pid = -1;
  int rc = posix_spawnp(&pid, argv[0].c_str(), &fa, nullptr, av.data(), environ);
  posix_spawn_file_actions_destroy(&fa);
  close(pfd[1]);
  if (rc != 0) { close(pfd[0]); return r; }
  char buf[8192];
  bool timed_out = false;
  int st = 0;
  double deadline = now_ms() + timeout_sec * 1000.0;
  for (;;) {
    if (now_ms() > deadline) {
      timed_out = true;
      if (pid > 0) kill(pid, SIGKILL);
      break;
    }
    struct pollfd pf = { pfd[0], POLLIN, 0 };
    int pr = poll(&pf, 1, 250);
    if (pr > 0) {
      ssize_t n = read(pfd[0], buf, sizeof(buf));
      if (n <= 0) break;
      if (r.out.size() < max_out)
        r.out.append(buf, (size_t)std::min<ssize_t>(n, (ssize_t)(max_out - r.out.size())));
      continue;
    }
    // child gone and pipe idle = done even if a descendant still holds the write end
    if (pid > 0 && waitpid(pid, &st, WNOHANG) == pid) { pid = -1; break; }
  }
  fcntl(pfd[0], F_SETFL, O_NONBLOCK);              // drain output written just before exit
  for (ssize_t n; (n = read(pfd[0], buf, sizeof(buf))) > 0; )
    if (r.out.size() < max_out)
      r.out.append(buf, (size_t)std::min<ssize_t>(n, (ssize_t)(max_out - r.out.size())));
  close(pfd[0]);
  if (pid > 0) {                                   // EOF seen but child still running
    while (waitpid(pid, &st, WNOHANG) == 0) {
      if (now_ms() > deadline) {
        timed_out = true;
        kill(pid, SIGKILL);
        waitpid(pid, &st, 0);
        break;
      }
      usleep(50000);
    }
  }
  r.status = timed_out ? -2 : (WIFEXITED(st) ? WEXITSTATUS(st) : -1);
  return r;
}

// parse "<bin> Ver X.Y.Z[-MariaDB][...-debug]" style --version output
static void parse_version(SideSpec& s) {
  RunOut r = run_capture({s.bin, "--no-defaults", "--version"});
  s.ver_string = trim(r.out.substr(0, r.out.find('\n')));
  string o = r.out;
  if (icontains(o, "MariaDB")) s.vendor = Vendor::MariaDB;
  else if (icontains(o, "mysql") || icontains(o, "MySQL")) s.vendor = Vendor::MySQL;
  size_t v = o.find("Ver ");
  if (v != string::npos) {
    v += 4;
    sscanf(o.c_str() + v, "%ld.%ld.%ld", &s.ver_major, &s.ver_minor, &s.ver_patch);
  }
  if (icontains(o, "debug") || s.basedir.find("-dbg") != string::npos || s.basedir.find("_dbg") != string::npos)
    s.debug_build = true;
}

// non-empty return = the reason no init tool could be resolved
static string resolve_init_tool_soft(SideSpec& s) {
  auto exists = [&](const string& p) {
    std::error_code ec;
    return fs::exists(p, ec) ? p : string();
  };
  // in-tree build: binary at <basedir>/sql/ (in-source) or <basedir>/{bld,build}/sql/
  for (const char* bd : {"", "/bld", "/build"}) {
    string d = s.basedir + bd;
    if (s.bin == d + "/sql/mariadbd" || s.bin == d + "/sql/mysqld") {
      s.srcdir = s.basedir;
      s.builddir = d;
      break;
    }
  }
  if (s.vendor == Vendor::MariaDB) {
    string t;
    if (!s.builddir.empty()) t = exists(s.builddir + "/scripts/mariadb-install-db");
    if (t.empty()) t = exists(s.basedir + "/scripts/mariadb-install-db");
    if (t.empty()) t = exists(s.basedir + "/scripts/mysql_install_db");
    if (t.empty()) t = exists(s.basedir + "/bin/mariadb-install-db");
    if (!t.empty()) { s.init_tool = t; return {}; }
    return "no mariadb-install-db found under " + s.basedir;
  }
  if (s.vendor == Vendor::MySQL) {
    if (s.ver_major > 5 || (s.ver_major == 5 && s.ver_minor >= 7)) {
      s.init_tool = s.bin;             // mysqld --initialize-insecure
      s.init_via_bin = true;
      return {};
    }
    string t = exists(s.basedir + "/scripts/mysql_install_db");
    if (t.empty()) t = exists(s.basedir + "/bin/mysql_install_db");
    if (!t.empty()) { s.init_tool = t; return {}; }
    return "no mysql_install_db found under " + s.basedir;
  }
  return "unknown vendor for " + s.basedir + " (" + s.ver_string + ")";
}

static void resolve_init_tool(SideSpec& s) {
  string e = resolve_init_tool_soft(s);
  if (!e.empty()) die("side%d: %s", s.idx, e.c_str());
}

// ---------------------------------------------------------------------------
// CLI
// ---------------------------------------------------------------------------
static void usage() {
  printf(
    "corlogic %s - query correctness/logic differential tester\n"
    "Usage: corlogic [options] [KEY=VALUE ...] [basedir1 basedir2 ...]\n"
    "  --config FILE   config file (default: ./corlogic.conf, else tool-dir corlogic.conf)\n"
    "  --seed N        xoshiro256++ seed (reproducible runs)\n"
    "  --check         run the pre-flight side probes, print the support matrix, exit\n"
    "  --selftest [N]  run the built-in unit tests (N threads for the concurrent pass), exit\n"
    "  --resume ID     resume workdir <ID>: its sides, options and counters come back\n"
    "  --version       print version, exit\n"
    "Any KEY=VALUE from corlogic.conf can be given on the command line (overrides file).\n"
    "Basedirs may also be globs (quoted). At least 2 sides are needed for a run.\n",
    CORLOGIC_VERSION);
}

static int g_selftest_threads = -1;               // --selftest: 0 or more threads, -1 off

static void parse_cli(int argc, char** argv, string& config_path) {
  for (int i = 1; i < argc; i++) {
    string a = argv[i];
    auto need = [&](const char* what) -> string {
      if (i + 1 >= argc) die("%s needs a value", what);
      return argv[++i];
    };
    if (a == "--help" || a == "-h") { usage(); exit(0); }
    else if (a == "--version") { printf("corlogic %s\n", CORLOGIC_VERSION); exit(0); }
    else if (a == "--config") config_path = need("--config");
    else if (a == "--seed") {
      // the same check the config file gets: a seed that is not a number would silently
      // become 0, and the run is then not the one that was asked for
      string v = need("--seed");
      char* end = nullptr;
      errno = 0;
      unsigned long long n = strtoull(v.c_str(), &end, 10);
      if (v.empty() || !end || *end || errno == ERANGE || v[0] == '-')
        die("--seed %s: a whole number is expected", v.c_str());
      g_cfg.seed = (uint64_t)n;
    }
    else if (a == "--check") g_cfg.check_only = true;
    else if (a == "--selftest") {
      g_selftest_threads = 8;
      if (i + 1 < argc && argv[i + 1][0] >= '0' && argv[i + 1][0] <= '9')
        g_selftest_threads = atoi(argv[++i]);
    }
    else if (a == "--resume") g_cfg.resume_id = need("--resume");
    else if (a.size() > 1 && a[0] == '-' && a[1] == '-') die("unknown option %s (see --help)", a.c_str());
    else if (a.find('=') != string::npos && a[0] != '/' && a[0] != '.') {
      size_t eq = a.find('=');
      if (!cfg_set(g_cfg, a.substr(0, eq), a.substr(eq + 1)))
        die("unknown config key on command line: %s", a.substr(0, eq).c_str());
    } else {
      // basedir path or glob. Expanded in the process, so a pattern holding a shell
      // metacharacter is a pattern and never a command.
      if (a.find_first_of("*?[") != string::npos) {
        glob_t gb{};
        if (glob(a.c_str(), 0, nullptr, &gb) == 0)
          for (size_t gi = 0; gi < gb.gl_pathc; gi++) g_cfg.pos_basedirs.push_back(gb.gl_pathv[gi]);
        globfree(&gb);
      } else {
        g_cfg.pos_basedirs.push_back(a);
      }
    }
  }
}

// ---------------------------------------------------------------------------
// run identity, directories, signals
// ---------------------------------------------------------------------------
struct Run {
  string id;                       // 7 random digits
  string workdir;                  // <WORKDIR_BASE>/<id> - results, log, cursor, bugs
  string rundir;                   // <RUNDIR_BASE>/<id> - templates + live datadirs
  Xoshiro256pp rng;                // seeded from SEED or entropy
  std::mutex rng_mtx;
  uint64_t rnd() { std::lock_guard<std::mutex> lk(rng_mtx); return rng.next(); }
};
static Run g_run;
static std::atomic<bool> g_stop{false};
static std::atomic<bool> g_pause{false};
static std::atomic<bool> g_auto_pause{false};           // the run paused itself, not a key
static std::atomic<bool> g_reduce_now{false};           // hold the trials, drain the reductions
static std::atomic<int> g_sigint_count{0};
static std::mutex g_children_mtx;
static std::set<pid_t> g_children;      // live server pids, for teardown

static void register_child(pid_t p) { std::lock_guard<std::mutex> lk(g_children_mtx); g_children.insert(p); }
static void unregister_child(pid_t p) { std::lock_guard<std::mutex> lk(g_children_mtx); g_children.erase(p); }

static void teardown_all() {
  std::set<pid_t> kids;
  { std::lock_guard<std::mutex> lk(g_children_mtx); kids = g_children; }
  // Killed, not asked to stop. These are throwaway instances on tmpfs and this is the exit
  // path, so a clean shutdown would only flush into directories that are about to go, and a
  // stop request depends on the server being in a state to act on it
  for (pid_t p : kids) kill(p, SIGKILL);
  for (int i = 0; i < 100 && !kids.empty(); i++) {
    for (auto it = kids.begin(); it != kids.end();) {
      int st;
      if (waitpid(*it, &st, WNOHANG) == *it) it = kids.erase(it); else ++it;
    }
    if (!kids.empty()) usleep(100000);
  }
  for (pid_t p : kids) { kill(p, SIGKILL); int st; waitpid(p, &st, 0); }
  // Only what this run owns. A refused resume leaves g_run naming a run that is still
  // live, and that run's directories are not this process's to remove. The marker files
  // say whose they are; a path with no marker yet is one this run has just made.
  auto ours = [](const string& marker) {
    string owner = trim(read_file(marker));
    return owner.empty() || owner == std::to_string((long)getpid());
  };
  if (!g_run.rundir.empty() && ours(g_run.rundir + "/corlogic.pid")) {
    std::error_code ec;
    fs::remove_all(g_run.rundir, ec);
  }
  if (!g_run.workdir.empty() && ours(g_run.workdir + "/corlogic.lock")) {
    std::error_code ec;
    fs::remove(g_run.workdir + "/corlogic.lock", ec);
  }
  if (g_tui_active.load()) {
    g_tui_active.store(false);
    printf("\x1b[?25h\x1b[?1049l");
    fflush(stdout);
    extern termios g_tui_oldt;
    extern std::atomic<bool> g_tui_have_oldt;
    if (g_tui_have_oldt.load()) tcsetattr(0, TCSANOW, &g_tui_oldt);
  }
}
static void on_sigint(int) {          // a handler sets flags only
  ++g_sigint_count;
  g_stop.store(true);
}

// the second Ctrl+C exits at once, with the teardown done off the handler where taking a
// lock, waiting for a child and printing are all allowed
static void start_signal_watcher() {
  std::thread([] {
    while (true) {
      usleep(100000);
      if (g_sigint_count.load() >= 2) { teardown_all(); _exit(130); }
    }
  }).detach();
}

// one live run per workdir: the lock file holds the pid, so a resume of a run that is
// still going is refused instead of two runs sharing a workdir
static void claim_workdir_lock() {
  string lf = g_run.workdir + "/corlogic.lock";
  long pid = atol(trim(read_file(lf)).c_str());
  if (pid > 0 && pid != (long)getpid() && kill((pid_t)pid, 0) == 0)
    die("run %s is still live under pid %ld: stop it first", g_run.id.c_str(), pid);
  write_file(lf, std::to_string((long)getpid()) + "\n");
}

// --resume ID: the workdir of an earlier run, in either of the two shapes it can have
static string find_run_workdir(const string& base, const string& id) {
  for (const string& p : {base + "/" + id, base + "/corlogic-" + id, id, "corlogic-" + id}) {
    std::error_code ec;
    if (fs::is_directory(p, ec)) return fs::absolute(p).string();
  }
  return "";
}

// The run dir holds the pid of the run that owns it. A run that is killed outright never
// reaches its own teardown, so the directory stays behind full of datadirs; the pid is what
// lets a sweeper tell that from a run still going.
static void mark_rundir_owner() {
  write_file(g_run.rundir + "/corlogic.pid", std::to_string((long)getpid()) + "\n");
}

// A unix socket path is capped at 107 characters by the kernel, and every server puts its
// socket inside the run dir. The longest path the run can build is the run id, the deepest
// sub-directory a sweep replay uses, and the socket name; a base longer than what is left
// starts nothing, and says so here rather than in a server error log.
static constexpr size_t RUNDIR_BASE_MAX = 107 - sizeof("/1234567/swp123456789-123/side12/socket.sock") + 1;

static void make_run_dirs() {
  std::error_code bec;
  while (g_cfg.rundir_base.size() > 1 && g_cfg.rundir_base.back() == '/')
    g_cfg.rundir_base.pop_back();                    // a trailing slash is an easy typo
  // a server resolves its datadir against its own working directory, so a relative base
  // builds the run dir under the caller's directory and then no side can start
  if (g_cfg.rundir_base.empty() || g_cfg.rundir_base[0] != '/')
    die("RUNDIR_BASE %s is not an absolute path", g_cfg.rundir_base.c_str());
  if (g_cfg.rundir_base.size() > RUNDIR_BASE_MAX)
    die("RUNDIR_BASE %s is %zu characters; %zu is the most a server socket path leaves",
        g_cfg.rundir_base.c_str(), g_cfg.rundir_base.size(), RUNDIR_BASE_MAX);
  if (!fs::is_directory(g_cfg.rundir_base, bec)) fs::create_directories(g_cfg.rundir_base, bec);
  if (!fs::is_directory(g_cfg.rundir_base, bec) ||
      access(g_cfg.rundir_base.c_str(), W_OK) != 0)
    die("RUNDIR_BASE %s is not a writable directory", g_cfg.rundir_base.c_str());
  if (!g_cfg.resume_id.empty()) {                    // resume: keep the id and workdir
    string wd = find_run_workdir(g_cfg.workdir_base, g_cfg.resume_id);
    if (wd.empty())
      die("--resume %s: no workdir for that id under %s", g_cfg.resume_id.c_str(),
          g_cfg.workdir_base.c_str());
    std::error_code ec;
    string rd = g_cfg.rundir_base + "/" + g_cfg.resume_id;
    fs::create_directories(rd, ec);
    if (!fs::is_directory(rd, ec)) die("cannot create the run dir %s", rd.c_str());
    g_run.id = g_cfg.resume_id; g_run.workdir = wd; g_run.rundir = rd;
    claim_workdir_lock();
    mark_rundir_owner();
    return;
  }
  // pick a free 7-digit id (6-digit ids are pquery runs)
  std::error_code last_ec; string last_path;
  for (int tries = 0; tries < 100; tries++) {
    char idb[16];
    snprintf(idb, sizeof(idb), "%07" PRIu64, (uint64_t)(g_run.rng.next() % 9000000 + 1000000));
    string wd_base = g_cfg.workdir_base;
    std::error_code ec;
    if (!fs::is_directory(wd_base, ec)) fs::create_directories(wd_base, ec);
    if (!fs::is_directory(wd_base, ec) || access(wd_base.c_str(), W_OK) != 0) {
      static bool warned = false;
      if (!warned) { printf("NOTE: %s not writable, using ./corlogic-<id> for results\n", wd_base.c_str()); warned = true; }
      wd_base = fs::current_path().string();
    }
    string wd = (g_cfg.workdir_base == wd_base) ? wd_base + "/" + idb
                                                : wd_base + "/corlogic-" + idb;
    string rd = g_cfg.rundir_base + "/" + idb;
    if (wd == rd) wd = wd_base + "/corlogic-" + idb;   // both bases the same directory
    if (fs::exists(wd, ec) || fs::exists(rd, ec)) continue;
    if (!fs::create_directories(wd, ec)) {
      if (ec) { last_ec = ec; last_path = wd; }
      continue;
    }
    if (!fs::create_directories(rd, ec)) {
      if (ec) { last_ec = ec; last_path = rd; }
      fs::remove_all(wd, ec);
      continue;
    }
    g_run.id = idb; g_run.workdir = wd; g_run.rundir = rd;
    claim_workdir_lock();
    mark_rundir_owner();
    return;
  }
  if (last_ec)
    die("could not create a run dir: %s: %s", last_path.c_str(), last_ec.message().c_str());
  die("could not allocate a run id under %s and %s", g_cfg.workdir_base.c_str(),
      g_cfg.rundir_base.c_str());
}

// ./pr in the workdir: pr-style results (bugs with UID, trials, reduction state)
static void write_pr_script() {
  static const char* sh = R"SH(#!/bin/bash
# pr-style results for this corlogic workdir: every bug with its UID, title and state
cd "$(dirname "$0")" || exit 1
log=$(ls corlogic-*.log 2>/dev/null | head -n1)
seen=bugs.seen
bugs=$(ls bug[0-9]*.report 2>/dev/null | sed 's/[^0-9]//g' | sort -n)
[ -z "$bugs" ] && echo "no bugs (yet)"
for n in $bugs; do
  r="bug$n.report"
  uid=$(/bin/grep -m1 '^UID: ' "$r" | cut -d' ' -f2-)
  ttl=$(head -n1 "$r")
  tc=$(awk '/^\{code:sql\}$/{f=1;next} /^\{code\}$/{f=0}
            f{ if (!b && ($0 ~ /^--/ || $0 ~ /^INSTALL SONAME / || $0 ~ /^SET /)) next; b=1; c++ }
            END{print c+0}' "$r")
  sw=$(awk '/^\{noformat:title=Bug Detection Matrix\}/{f=1;next} f&&/^\{noformat\}/{f=0}
            f&&/^(CS|ES|MS) /{t++; if (index($0,"DIFF")) a++}
            END{if (t) printf " | affects %d/%d builds", a, t}' "$r")
  duid=$(awk -F'\t' -v b="bug$n" '$1==b{print $2; exit}' "$seen" 2>/dev/null)
  hits=$(awk -F'\t' -v u="$duid" '$1 ~ /^cand/ && $2==u {c++; t=t" "substr($3,6)} END{print c+0"|"t}' "$seen" 2>/dev/null)
  cnt=${hits%%|*}; trials=${hits#*|}
  echo "trial$n  $uid"
  echo "      $ttl"
  echo "      seen ${cnt:-0}x, trial(s):${trials} | ready ($tc-line testcase$sw)"
  near=$(/bin/grep -m1 '^Near: ' "$r" | cut -d' ' -f2-)
  [ -n "$near" ] && echo "      near a known one: $near"
done
if [ -s "$seen" ]; then
  cands=$(awk -F'\t' '$1 ~ /^cand/{print $1}' "$seen" | sort -u | wc -l)
  nb=$(awk -F'\t' '$1 ~ /^bug/{print $1}' "$seen" | sort -u | wc -l)
  drop=0; unver=0
  if [ -n "$log" ]; then
    drop=$(/bin/grep -cE ': dropped - the (trial replay|reduced testcase) did not reproduce' "$log")
    unver=$(/bin/grep -cE ': dropped - the (run stopped|reduction instances|trial replay could not|final replay ran out)' "$log")
  fi
  echo
  echo "candidates: $cands ($nb confirmed as bugs, $drop dropped - the diff did not replay, $unver left unverified)"
fi
)SH";
  string p = g_run.workdir + "/pr";
  write_file(p, sh);
  chmod(p.c_str(), 0755);
}

// VIEWS and SEQUENCES need the matching generator class on as well, or the toggle lets
// through statements the generator never produces. The run gets its own weights file with
// those lines rewritten, and the workdir keeps it as the record of what the run drew from.
static void resolve_weights_file() {
  if (!g_cfg.views && !g_cfg.sequences) return;
  if (g_cfg.weights_file.empty() || !fs::exists(g_cfg.weights_file)) {
    logline("VIEWS/SEQUENCES are on but there is no weights file, so the generator classes "
            "keep their own defaults");
    return;
  }
  string out, on;
  for (auto& ln : split(read_file(g_cfg.weights_file), '\n')) {
    string t = trim(ln);
    if (g_cfg.views && t.rfind("ddl_view", 0) == 0) { out += "ddl_view 100\n"; on += " ddl_view"; }
    else if (g_cfg.sequences && t.rfind("ddl_seq", 0) == 0) { out += "ddl_seq 100\n"; on += " ddl_seq"; }
    else out += ln + "\n";
  }
  string wf = g_run.workdir + "/corlogic.weights";
  if (!write_file(wf, out)) return;
  g_cfg.weights_file = wf;
  logline("weights:%s turned on -> %s", on.c_str(), wf.c_str());
}

static void open_run_log() {
  string lf = g_run.workdir + "/corlogic-" + g_run.id + ".log";
  g_logf = fopen(lf.c_str(), "a");
  if (!g_logf) die("cannot open %s", lf.c_str());
  write_pr_script();
}

// A binary in the directory can be older than the source beside it, and then the run is
// testing a tool that is not the one on the page. The sanitizer binaries are the ones this
// happens to, because they are built by hand and one at a time. Said once, at startup.
static void check_build_stamp() {
  std::error_code ec;
  char exe[4096];
  ssize_t n = readlink("/proc/self/exe", exe, sizeof(exe) - 1);
  if (n <= 0) return;
  exe[n] = 0;
  fs::path src = fs::path(exe).parent_path() / "corlogic.cpp";
  if (!fs::is_regular_file(src, ec)) return;
  auto ts = fs::last_write_time(src, ec);
  if (ec) return;
  auto tb = fs::last_write_time(exe, ec);
  if (ec || ts <= tb) return;
  long behind = (long)std::chrono::duration_cast<std::chrono::seconds>(ts - tb).count();
  logline_alert("%s is %ld second(s) newer than this binary: rebuild with ./build.sh, or "
                "this run is testing an older tool", src.string().c_str(), behind);
}

// ---------------------------------------------------------------------------
// sql_mode resolution (SET/ADD/REMOVE on the common-subset default)
// ---------------------------------------------------------------------------
static string resolve_sql_mode() {
  string base = g_cfg.sql_mode.empty() ? SQL_MODE_DEFAULT : g_cfg.sql_mode;
  vector<string> modes = split(upper(base), ',');
  for (auto& a : split(upper(g_cfg.sql_mode_add), ','))
    if (!a.empty() && std::find(modes.begin(), modes.end(), a) == modes.end()) modes.push_back(a);
  for (auto& r : split(upper(g_cfg.sql_mode_remove), ','))
    modes.erase(std::remove(modes.begin(), modes.end(), r), modes.end());
  string out;
  for (auto& m : modes) { if (!m.empty()) { if (!out.empty()) out += ","; out += m; } }
  return out;
}

// ---------------------------------------------------------------------------
// server instance: template init, start, stop, liveness
// ---------------------------------------------------------------------------
// A server outlives its run if the run is killed outright, and its datadir on /dev/shm goes
// with it, so every server asks the kernel to kill it when the run dies. That needs a fork
// of our own, because posix_spawn has no action for it, and between the fork and the exec
// only calls that are safe there are made.
//
// The kernel sends that signal when the thread that forked exits, not when the process
// exits, so a worker thread must never be the one to fork: its servers would die the moment
// it moved on. Every start goes through one thread that lives as long as the run. Without
// that thread the fork still works and asks for nothing, which is what the selftest uses.
static pid_t spawn_now(const vector<string>& argv, const string& logfile, bool die_with_us) {
  vector<char*> av;
  for (auto& a : argv) av.push_back(const_cast<char*>(a.c_str()));
  av.push_back(nullptr);
  int lfd = open(logfile.c_str(), O_WRONLY | O_CREAT | O_APPEND, 0644);
  if (lfd < 0) return -1;
  bool path_given = argv[0].find('/') != string::npos;
  pid_t pid = fork();
  if (pid == 0) {
    if (die_with_us) {
      prctl(PR_SET_PDEATHSIG, SIGKILL);
      // Its own process group, so a signal aimed at ours does not reach the server. Child
      // lifetime is handled here instead: the death signal above, and kills on a single pid
      setpgid(0, 0);
      if (getppid() == 1) _exit(127);        // the run died while this fork was under way
    }
    if (dup2(lfd, 1) < 0 || dup2(lfd, 2) < 0) _exit(127);
    if (lfd > 2) close(lfd);
    if (path_given) execv(av[0], av.data());
    else execvp(av[0], av.data());
    _exit(127);
  }
  close(lfd);
  return pid > 0 ? pid : -1;
}

struct SpawnReq {
  const vector<string>* argv;
  const string* logfile;
  pid_t pid = -1;
  bool done = false;
};
// The service thread waits on these for the whole life of the process, so they are never
// destroyed: destroying a condition variable that still has a waiter hangs the exit.
struct SpawnSvc {
  std::mutex mtx;
  std::condition_variable cv, done_cv;
  std::deque<SpawnReq*> q;
  bool up = false;                                     // guarded by mtx
};
static SpawnSvc* g_spawn = new SpawnSvc();

static void spawn_service() {
  std::unique_lock<std::mutex> lk(g_spawn->mtx);
  for (;;) {
    g_spawn->cv.wait(lk, [] { return !g_spawn->q.empty(); });
    SpawnReq* r = g_spawn->q.front();
    g_spawn->q.pop_front();
    lk.unlock();
    pid_t p = spawn_now(*r->argv, *r->logfile, true);
    lk.lock();
    r->pid = p;
    r->done = true;
    g_spawn->done_cv.notify_all();
  }
}

// It runs from before the first server until the process ends, and it is detached: a thread
// still joinable when the process leaves main ends the process on std::terminate, and there
// is no moment where stopping it early would be right, because the servers go with it.
static void start_spawn_service() {
  std::lock_guard<std::mutex> lk(g_spawn->mtx);
  if (g_spawn->up) return;
  g_spawn->up = true;
  std::thread(spawn_service).detach();
}

static pid_t spawn_logged(const vector<string>& argv, const string& logfile) {
  SpawnReq r{&argv, &logfile, -1, false};
  std::unique_lock<std::mutex> lk(g_spawn->mtx);
  if (!g_spawn->up) {                                  // no service: the selftest, and --help
    lk.unlock();
    return spawn_now(argv, logfile, false);
  }
  g_spawn->q.push_back(&r);
  g_spawn->cv.notify_one();
  g_spawn->done_cv.wait(lk, [&r] { return r.done; });
  return r.pid;
}

// one datadir template per unique basedir+init-options; shared across sides/workers.
// Creation is parallel across different keys; the same key is created once (the tpl
// path is key-derived, so two creators of one key would corrupt each other) and
// concurrent requesters wait for the creator, then read the cache.
static std::mutex g_tpl_mtx;
static std::condition_variable g_tpl_cv;
static std::map<string, string> g_templates;   // key -> template dir (ready)
static std::set<string> g_tpl_inflight;        // keys being created right now
static string template_for(const SideSpec& s) {
  string key = s.basedir + "|" + g_cfg.myinit;
  {
    std::unique_lock<std::mutex> lk(g_tpl_mtx);
    for (;;) {
      auto it = g_templates.find(key);
      if (it != g_templates.end()) return it->second;
      if (!g_tpl_inflight.count(key)) { g_tpl_inflight.insert(key); break; }
      g_tpl_cv.wait(lk);
    }
  }
  string bn = s.basedir;
  while (!bn.empty() && bn.back() == '/') bn.pop_back();
  size_t sl = bn.rfind('/');
  if (sl != string::npos) bn = bn.substr(sl + 1);
  // The key is basedir plus the init options, so the path carries the same hash: two
  // basedirs whose last path component matches would otherwise share one template, and a
  // server must only ever start from a template its own build initialised
  char kb[32];
  snprintf(kb, sizeof(kb), "-%08x", (uint32_t)fnv1a(key));
  string tpl = g_run.rundir + "/datadir_template-" + bn + kb;
  string tmp = tpl + ".tmp";
  string initlog = g_run.workdir + "/init-" + tpl.substr(tpl.rfind('/') + 1) + ".log";
  bool any_failed = false;       // a failed attempt names this log, so a later pass keeps it
  for (int attempt = 1; attempt <= 10; attempt++) {
    std::error_code ec;
    fs::remove_all(tpl, ec); fs::remove_all(tmp, ec);
    fs::create_directories(tmp, ec);
    vector<string> argv;
    if (s.init_via_bin) {
      argv = {s.init_tool, "--no-defaults", "--initialize-insecure",
              "--basedir=" + s.basedir, "--datadir=" + tpl, "--tmpdir=" + tmp,
              "--log-error=" + initlog};
    } else {
      argv = {s.init_tool, "--no-defaults", "--force",
              "--datadir=" + tpl, "--tmpdir=" + tmp};
      if (!s.srcdir.empty()) {                      // in-tree: --basedir does not apply
        argv.push_back("--srcdir=" + s.srcdir);
        argv.push_back("--builddir=" + s.builddir);
      } else {
        argv.push_back("--basedir=" + s.basedir);
      }
      if (s.vendor == Vendor::MariaDB) argv.push_back("--auth-root-authentication-method=normal");
    }
    for (auto& o : split(g_cfg.myinit, ' ')) if (!o.empty()) argv.push_back(o);
    pid_t pid = spawn_logged(argv, initlog);
    int st = -1;
    if (pid > 0) waitpid(pid, &st, 0);
    int rc = (pid > 0 && WIFEXITED(st)) ? WEXITSTATUS(st) : -1;
    size_t files = 0;
    if (fs::is_directory(tpl + "/mysql", ec))
      for (auto& e : fs::directory_iterator(tpl + "/mysql", ec)) { (void)e; files++; }
    // MariaDB: privilege tables as files under mysql/. MySQL 8+: data dictionary in mysql.ibd.
    bool sane = files > 50 || fs::exists(tpl + "/mysql.ibd", ec);
    if (rc == 0 && sane) {
      fs::remove_all(tmp, ec);
      if (!any_failed) fs::remove(initlog, ec);
      {
        std::lock_guard<std::mutex> lk(g_tpl_mtx);
        g_templates[key] = tpl;
        g_tpl_inflight.erase(key);
      }
      g_tpl_cv.notify_all();
      logline("side%d: datadir template ready (%s)", s.idx, tpl.c_str());
      return tpl;
    }
    any_failed = true;
    logline("side%d: template init attempt %d/10 failed (rc=%d files=%zu, log: %s)",
            s.idx, attempt, rc, files, initlog.c_str());
    sleep(2);
  }
  {
    std::lock_guard<std::mutex> lk(g_tpl_mtx);
    g_tpl_inflight.erase(key);
  }
  g_tpl_cv.notify_all();
  logline("side%d: datadir template creation failed 10x - see %s", s.idx, initlog.c_str());
  return {};                     // callers treat an empty template as a start failure
}

// Client auth plugin dir. MySQL 8+ authenticates with caching_sha2_password, which the
// linked MariaDB client library loads as a dynamic plugin; its compiled-in default dir
// rarely exists. Baked build-time dir first, else the newest /test MariaDB -opt basedir.
#ifndef CORLOGIC_PLUGIN_DIR
#define CORLOGIC_PLUGIN_DIR ""
#endif
static string g_client_plugin_dir;
static void resolve_client_plugin_dir() {
  auto has = [](const string& d) {
    return !d.empty() && access((d + "/caching_sha2_password.so").c_str(), F_OK) == 0;
  };
  if (!g_cfg.client_plugin_dir.empty()) { g_client_plugin_dir = g_cfg.client_plugin_dir; return; }
  if (has(CORLOGIC_PLUGIN_DIR)) { g_client_plugin_dir = CORLOGIC_PLUGIN_DIR; return; }
  auto [rc, out] = run_capture({"bash", "-c",
    "ls -d /test/MD*-mariadb-*-opt/lib/plugin 2>/dev/null | sort -V | tail -1"});
  string d = trim(out);
  if (rc == 0 && has(d)) g_client_plugin_dir = d;
}
static void apply_client_options(MYSQL* h) {
  unsigned t = 10;
  mysql_options(h, MYSQL_OPT_CONNECT_TIMEOUT, &t);
  if (!g_client_plugin_dir.empty())
    mysql_options(h, MYSQL_PLUGIN_DIR, g_client_plugin_dir.c_str());
}

// A permission failure on tmpfs, same user throughout, means a mode or owner anomaly on
// one path component. Naming every component's mode and owner turns a single occurrence
// into a full picture, where the path alone would leave the anomalous component unknown.
static string path_modes(const string& p) {
  string out;
  fs::path cur;
  for (const auto& part : fs::path(p)) {
    cur /= part;
    if (cur.native() == "/") continue;
    struct stat st;
    char b[300];
    if (::stat(cur.c_str(), &st) == 0)
      snprintf(b, sizeof(b), " %s=%03o,uid%u", part.c_str(),
               (unsigned)(st.st_mode & 07777), (unsigned)st.st_uid);
    else
      snprintf(b, sizeof(b), " %s=%s", part.c_str(), strerror(errno));
    out += b;
  }
  return out;
}

// why carries the reason the copy failed, so a run dir that filled up says so, and which
// file it stopped on: the error_code overload of fs::copy carries no path, so every failure
// reads the same in the log, while the throwing overload carries both.
static bool copy_dir(const string& from, const string& to, string* why = nullptr) {
  std::error_code ec, mkec, stec;
  fs::remove_all(to, ec);
  fs::create_directories(to, mkec);
  // a destination that could not be made turns into a copy error further down, where the
  // reason reads as a problem with a file rather than with the directory that is missing
  if (!fs::is_directory(to, stec)) {
    if (why) {
      *why = "cannot make the destination directory " + to +
             (mkec ? ": " + mkec.message() : string());
      if (mkec == std::errc::permission_denied) *why += " [" + path_modes(to) + " ]";
    }
    return false;
  }
  try {
    fs::copy(from, to, fs::copy_options::recursive | fs::copy_options::copy_symlinks);
  } catch (const fs::filesystem_error& e) {
    if (why) {
      *why = e.code().message();
      if (!e.path1().empty()) *why += " on " + e.path1().string();
      if (!e.path2().empty()) *why += " -> " + e.path2().string();
      if (e.code() == std::errc::permission_denied) {
        if (!e.path1().empty()) *why += " [" + path_modes(e.path1().string()) + " ]";
        if (!e.path2().empty()) *why += " -> [" + path_modes(e.path2().string()) + " ]";
      }
    }
    return false;
  } catch (const std::exception& e) {
    if (why) *why = e.what();
    return false;
  }
  return true;
}

struct Instance {
  const SideSpec* spec = nullptr;
  string root, datadir, tmpdir, sock, errlog, pidfile;
  pid_t pid = -1;
  bool start_failed = false;
  string start_note;               // why the last start did not happen, where no log says

  void set_paths(const string& base_root) {
    root = base_root;
    datadir = root + "/data";
    tmpdir = root + "/tmp";
    sock = root + "/socket.sock";
    errlog = root + "/log/master.err";           // framework convention
    pidfile = root + "/pid.pid";
  }
  bool alive() {
    if (pid <= 0) return false;
    int st;
    pid_t r = waitpid(pid, &st, WNOHANG);
    if (r == pid) { unregister_child(pid); pid = -1; return false; }
    return kill(pid, 0) == 0;
  }
  vector<string> server_argv() const {
    vector<string> a = {spec->bin, "--no-defaults",
      "--basedir=" + spec->basedir, "--datadir=" + datadir, "--tmpdir=" + tmpdir,
      "--socket=" + sock, "--pid-file=" + pidfile, "--log-error=" + errlog,
      "--skip-networking", "--core-file", "--log-output=none"};
    if (!spec->builddir.empty()) {                 // in-tree: share files live under sql/share
      std::error_code ec;
      string share = spec->builddir + "/sql/share";
      if (fs::is_directory(share, ec)) a.push_back("--lc-messages-dir=" + share);
      if (fs::is_directory(share + "/charsets", ec)) a.push_back("--character-sets-dir=" + share + "/charsets");
    }
    for (auto& o : split(g_cfg.mem_caps, ' ')) if (!o.empty()) a.push_back(o);
    // exact statistics from boot as well: the sample covers the whole index, so ANALYZE
    // counts the rows instead of estimating them from 20 pages
    if (g_cfg.stats_sample_pages > 0)
      a.push_back("--loose-innodb_stats_persistent_sample_pages=" +
                  std::to_string(g_cfg.stats_sample_pages));
    if (!spec->engine.empty()) a.push_back("--default-storage-engine=" + spec->engine);
    // an engine that ships as a plugin has to be loaded before it can be the default
    if (!spec->engine.empty()) {
      std::error_code pec;
      if (fs::exists(spec->basedir + "/lib/plugin/ha_" + spec->engine + ".so", pec))
        a.push_back("--plugin-load-add=ha_" + spec->engine);
    }
    if (spec->vendor == Vendor::MySQL) a.push_back("--loose-mysqlx=OFF");
    for (auto& o : split(g_cfg.myextra, ' ')) if (!o.empty()) a.push_back(o);
    for (auto& o : split(spec->options, ' ')) if (!o.empty()) a.push_back(o);
    return a;
  }
  // fresh datadir from template + start + wait for the socket to accept connections
  bool start_fresh(const string& tpl) {
    std::error_code ec;
    fs::create_directories(root, ec);
    fs::create_directories(root + "/log", ec);
    { int fd = open(errlog.c_str(), O_WRONLY | O_CREAT | O_TRUNC, 0644);   // no older run in it
      if (fd >= 0) close(fd); }
    fs::remove_all(tmpdir, ec);
    fs::create_directories(tmpdir, ec);
    string why;
    for (int attempt = 1; !copy_dir(tpl, datadir, &why); attempt++) {
      logline("side%d: datadir copy failed (attempt %d/5) - %s", spec->idx, attempt, why.c_str());
      if (attempt == 5) {
        // the server was never started, so its error log says nothing: the reason is kept
        // here, where the caller reporting the drop can reach it
        start_note = "datadir copy failed - " + why;
        return false;
      }
      sleep(1);
    }
    return start_only();
  }
  bool start_only() {
    start_failed = false;
    pid = spawn_logged(server_argv(), errlog);
    if (pid <= 0) { start_failed = true; return false; }
    register_child(pid);
    unsigned last_err = 0;
    string last_msg;
    // Bounded by the clock, not by a count of tries: a try that does not come back leaves the
    // count where it started. A single connect can still overrun the deadline, because it can
    // sit far longer than MYSQL_OPT_CONNECT_TIMEOUT on a socket bound but not yet accepting
    double deadline = now_ms() + 90000.0;
    while (now_ms() < deadline) {
      if (g_stop.load() || !alive()) { start_failed = true; return false; }
      if (access(sock.c_str(), F_OK) == 0) {
        MYSQL* m = mysql_init(nullptr);
        apply_client_options(m);
        if (mysql_real_connect(m, nullptr, "root", "", nullptr, 0, sock.c_str(), 0)) {
          mysql_close(m);
          return true;
        }
        last_err = mysql_errno(m);
        last_msg = mysql_error(m);
        mysql_close(m);
      }
      usleep(100000);
    }
    if (last_err)
      logline("side%d: connect probe kept failing: %u %s", spec->idx, last_err, last_msg.c_str());
    else
      logline("side%d: server did not become ready within 90s", spec->idx);
    start_failed = true;
    return false;
  }
  // hard: the datadir is about to be replaced, so a clean shutdown would only flush a
  // buffer pool into a directory that is deleted a moment later. A server whose start did not
  // finish is killed for the same reason, and because a process that never finished starting
  // cannot be relied on to act on a stop request
  void stop(bool hard = false) {
    if (pid <= 0) return;
    if (hard || start_failed) {
      kill(pid, SIGKILL);
      int st; waitpid(pid, &st, 0);
      unregister_child(pid);
      pid = -1;
      return;
    }
    kill(pid, SIGTERM);
    for (int i = 0; i < 300; i++) {
      int st;
      if (waitpid(pid, &st, WNOHANG) == pid) { unregister_child(pid); pid = -1; return; }
      usleep(100000);
    }
    kill(pid, SIGKILL);
    int st; waitpid(pid, &st, 0);
    unregister_child(pid);
    pid = -1;
  }
};

// ---------------------------------------------------------------------------
// client connection + query outcomes
// ---------------------------------------------------------------------------
struct Warning { unsigned code = 0; string level, msg; };
enum class QState { OK, WARN, ERR, CRASH, TIMEOUT, SKIP };
struct QOutcome {
  QState state = QState::OK;
  unsigned err = 0;
  string errmsg;
  unsigned cols = 0;
  long long affected = -1;             // DML only (field_count==0)
  vector<string> rows;                 // canonical rows, up to ROWS_CAP
  bool capped = false;
  uint64_t multiset_hash = 0;          // order-independent row-content hash (all rows)
  size_t row_count = 0;
  vector<Warning> warnings;
  double ms = 0;
};

struct Conn {
  MYSQL* h = nullptr;
  string sock;
  unsigned long thread_id = 0;
  bool connect(const string& sock_path, const char* db = nullptr) {
    close();
    sock = sock_path;
    h = mysql_init(nullptr);
    apply_client_options(h);
    my_bool rc0 = 0;
    mysql_options(h, MYSQL_OPT_RECONNECT, &rc0);
    if (!mysql_real_connect(h, nullptr, "root", "", db, 0, sock.c_str(), 0)) {
      return false;
    }
    mysql_set_character_set(h, g_cfg.charset.c_str());
    thread_id = mysql_thread_id(h);
    return true;
  }
  unsigned last_errno() { return h ? mysql_errno(h) : 2013; }
  string last_error() { return h ? mysql_error(h) : "no connection"; }
  void close() {
    if (h) { mysql_close(h); h = nullptr; }
  }
  ~Conn() { close(); }
};

// canonical value: NULL -> \N, control chars escaped, binary hex, floats rounded
static void canon_value(string& out, const char* v, unsigned long len, const MYSQL_FIELD& f) {
  if (!v) { out += "\\N"; return; }
  bool bin = (f.charsetnr == 63) &&
             (f.type == MYSQL_TYPE_BLOB || f.type == MYSQL_TYPE_TINY_BLOB ||
              f.type == MYSQL_TYPE_MEDIUM_BLOB || f.type == MYSQL_TYPE_LONG_BLOB ||
              f.type == MYSQL_TYPE_STRING || f.type == MYSQL_TYPE_VAR_STRING ||
              f.type == MYSQL_TYPE_GEOMETRY || f.type == MYSQL_TYPE_BIT);
  if (bin) {
    out += "0x";
    static const char* hex = "0123456789ABCDEF";
    for (unsigned long i = 0; i < len; i++) {
      unsigned char c = (unsigned char)v[i];
      out += hex[c >> 4]; out += hex[c & 15];
    }
    return;
  }
  if ((f.type == MYSQL_TYPE_FLOAT || f.type == MYSQL_TYPE_DOUBLE) && g_cfg.float_digits > 0) {
    char* endp = nullptr;
    double d = strtod(v, &endp);
    if (endp && *endp == '\0') {
      char buf[64];
      snprintf(buf, sizeof(buf), "%.*g", g_cfg.float_digits, d);
      out += buf;
      return;
    }
  }
  for (unsigned long i = 0; i < len; i++) {
    char c = v[i];
    if (c == '\t') out += "\\t";
    else if (c == '\n') out += "\\n";
    else if (c == '\r') out += "\\r";
    else if (c == '\\') out += "\\\\";
    else out += c;
  }
}

static void fetch_warnings(Conn& c, QOutcome& o) {
  if (!c.h || mysql_warning_count(c.h) == 0) return;
  if (mysql_real_query(c.h, "SHOW WARNINGS", 13) != 0) return;
  MYSQL_RES* res = mysql_store_result(c.h);
  if (!res) return;
  MYSQL_ROW row;
  while ((row = mysql_fetch_row(res))) {
    Warning w;
    w.level = row[0] ? row[0] : "";
    w.code = row[1] ? (unsigned)atoi(row[1]) : 0;
    w.msg = row[2] ? row[2] : "";
    o.warnings.push_back(std::move(w));
  }
  mysql_free_result(res);
}

// every query this run sends a server, on every side and from every job: trials,
// reduction probes, checkpoint scans and replays. This is what speed counts, so a busy
// reducer queue reads as work and not as a stall
static std::atomic<long> g_qexec{0};

// execute one statement, canonicalize the outcome; want_warnings avoids the SHOW WARNINGS
// round trip when the compare level does not need it; keep_rows=false hashes and counts
// only (checkpoint scans), skipping row storage
static void exec_stmt(Conn& c, std::string_view sql, QOutcome& o, bool want_warnings,
                      bool keep_rows = true) {
  o = QOutcome{};
  if (!c.h) { o.state = QState::CRASH; o.err = 2013; o.errmsg = "no connection"; return; }
  double t0 = now_ms();
  int rc = mysql_real_query(c.h, sql.data(), sql.size());
  g_qexec++;
  if (rc != 0) {
    o.err = mysql_errno(c.h);
    o.errmsg = mysql_error(c.h);
    o.ms = now_ms() - t0;
    if (o.err == 2006 || o.err == 2013) { o.state = QState::CRASH; return; }
    o.state = QState::ERR;
    if (want_warnings) fetch_warnings(c, o);
    return;
  }
  o.cols = mysql_field_count(c.h);
  if (o.cols == 0) {
    o.affected = (long long)mysql_affected_rows(c.h);
  } else {
    MYSQL_RES* res = mysql_use_result(c.h);
    if (!res) {
      // columns were promised and no result set came back: one side failing to deliver its
      // rows would otherwise read as OK with none, and compare equal to a side that
      // returned none
      o.err = mysql_errno(c.h);
      o.errmsg = mysql_error(c.h);
      if (!o.err) { o.err = 2000; o.errmsg = "no result set for a statement with columns"; }
      o.state = (o.err == 2006 || o.err == 2013) ? QState::CRASH : QState::ERR;
    } else {
      unsigned nf = mysql_num_fields(res);
      MYSQL_FIELD* fields = mysql_fetch_fields(res);
      MYSQL_ROW row;
      string rowbuf;
      while ((row = mysql_fetch_row(res))) {
        unsigned long* lens = mysql_fetch_lengths(res);
        rowbuf.clear();
        for (unsigned i = 0; i < nf; i++) {
          if (i) rowbuf += '\t';
          canon_value(rowbuf, row[i], lens[i], fields[i]);
        }
        o.row_count++;
        // commutative accumulate (avalanche each row hash, then sum), so row order
        // never changes the hash; ORDER BY ties legally differ in order between sides
        uint64_t rh = fnv1a(rowbuf);
        o.multiset_hash += Xoshiro256pp::splitmix64(rh);
        if (!keep_rows) { }
        else if ((long)o.rows.size() < g_cfg.rows_cap) o.rows.push_back(rowbuf);
        else o.capped = true;
      }
      if (mysql_errno(c.h) != 0) {                  // mid-result error (incl. server gone)
        o.err = mysql_errno(c.h);
        o.errmsg = mysql_error(c.h);
        o.state = (o.err == 2006 || o.err == 2013) ? QState::CRASH : QState::ERR;
      }
      mysql_free_result(res);
    }
  }
  o.ms = now_ms() - t0;
  if (o.state == QState::OK || o.state == QState::WARN) {
    if (want_warnings) fetch_warnings(c, o);
    if (c.h && mysql_warning_count(c.h) > 0) o.state = QState::WARN;
    else if (!o.warnings.empty()) o.state = QState::WARN;
  }
}

// PREPARE-parse a statement; returns 0 ok / errno; 1064 = parse error, 1295 = non-preparable
static unsigned prepare_check(Conn& c, std::string_view sql) {
  if (!c.h) return 2013;
  MYSQL_STMT* st = mysql_stmt_init(c.h);
  if (!st) return 2008;
  unsigned rc = 0;
  if (mysql_stmt_prepare(st, sql.data(), sql.size()) != 0) rc = mysql_stmt_errno(st);
  mysql_stmt_close(st);
  return rc;
}

// simple query -> single string result (first column of first row)
static string query_scalar(Conn& c, const string& sql) {
  if (!c.h || mysql_real_query(c.h, sql.c_str(), sql.size()) != 0) return {};
  MYSQL_RES* res = mysql_store_result(c.h);
  if (!res) return {};
  string out;
  MYSQL_ROW row = mysql_fetch_row(res);
  if (row && row[0]) out = row[0];
  mysql_free_result(res);
  return out;
}
static vector<vector<string>> query_rows(Conn& c, const string& sql) {
  vector<vector<string>> out;
  if (!c.h || mysql_real_query(c.h, sql.c_str(), sql.size()) != 0) return out;
  MYSQL_RES* res = mysql_store_result(c.h);
  if (!res) return out;
  unsigned nf = mysql_num_fields(res);
  MYSQL_ROW row;
  while ((row = mysql_fetch_row(res))) {
    vector<string> r;
    for (unsigned i = 0; i < nf; i++) r.push_back(row[i] ? row[i] : "\\N");
    out.push_back(std::move(r));
  }
  mysql_free_result(res);
  return out;
}

// ---------------------------------------------------------------------------
// side capabilities (pre-flight probes; always run at startup)
// ---------------------------------------------------------------------------
struct SideCaps {
  string version_full;                 // SELECT VERSION()
  string version_banner;               // myver/m output or version_full
  std::set<string> engines;            // SHOW ENGINES support YES/DEFAULT (lowercase)
  std::set<string> tx_engines;         // transactional engines
  std::set<string> optimizer_flags;    // names from @@optimizer_switch
  std::map<string, string> optimizer_switch_map;   // ... with the on/off each one is set to
  bool has_partitioning = false;
  bool explain_extended = false;       // MariaDB dialect
  bool has_collation = false;
  bool sql_mode_ok = false;
  bool connected = false;
  bool has_stats_pins = false;         // the InnoDB statistics variables exist here
  bool has_stat_sample_pages = false;  // innodb_stats_persistent_sample_pages is settable
  bool has_stat_tables = false;        // engine-independent statistics (MariaDB)
  bool has_purge_wait = false;         // innodb_max_purge_lag_wait exists here
  bool has_old_mode = false;           // old_mode exists here (MariaDB)
  string old_mode;                     // what it is set to
  bool has_engine_var = false;         // default_storage_engine exists here
  std::set<string> pin_vars;           // the per-trial pin variables this side has
  string fail_reason;
};

// Session variables pinned at the start of every trial: a result or a plan depends on
// them, so every trial starts from the same value. The value comes from the side's own
// global, so a per-side server option stays in force. A per-side value that changes per
// trial (the optimizer_switch combinations) is applied after the preamble, not before.
// The settings the plan depends on, with the value each one is pinned to. A fixed value
// means both sides plan with the same number, so a plan difference is the server and not
// the configuration. An empty value has no portable fixed form, so that variable keeps
// each side's own global value; PIN_MODE=global does that for all of them.
struct PinVar { const char* name; const char* fixed; };
static const PinVar PIN_VARS[] = {
  {"optimizer_switch",                    ""},          // the value string is version-specific
  {"optimizer_search_depth",              "62"},
  {"optimizer_prune_level",               "1"},
  {"optimizer_use_condition_selectivity", "4"},
  {"join_buffer_size",                    "262144"},
  {"sort_buffer_size",                    "262144"},
  {"read_buffer_size",                    "131072"},
  {"read_rnd_buffer_size",                "262144"},
  {"tmp_table_size",                      "1048576"},
  {"max_heap_table_size",                 "1048576"}
};

// a full 40-hex commit id is shortened to 12 characters for LOG display only; the
// bug-report {noformat:title=...} version strings keep the full id
static string shorten_commit_ids_log_only(string s) {
  for (size_t i = 0; i + 40 <= s.size();) {
    if (isxdigit((unsigned char)s[i]) && (i == 0 || !isalnum((unsigned char)s[i - 1]))) {
      size_t j = i;
      while (j < s.size() && isxdigit((unsigned char)s[j])) j++;
      if (j - i == 40 && (j == s.size() || !isalnum((unsigned char)s[j]))) {
        s.erase(i + 12, 28);
        i += 12;
        continue;
      }
      i = j;
    } else i++;
  }
  return s;
}

// Version banner via the framework's myver, run with the basedir as cwd. myver only reads
// the binary's version info. Never run other basedir scripts: they manage live servers.
// The banner is kept verbatim (full commit id).
static string myver_banner(const SideSpec& s) {
  string myver = home_dir() + "/mariadb-qa/homedir_scripts/myver";
  if (access(myver.c_str(), X_OK) == 0) {
    RunOut r = run_capture({myver}, s.basedir);
    string first = trim(r.out.substr(0, r.out.find('\n')));
    if (r.status == 0 && starts_with_i(first, "{noformat")) return first;
  }
  return {};
}

static SideCaps probe_side(const SideSpec& s, Instance& inst, const string& sql_mode) {
  SideCaps cap;
  Conn c;
  if (!c.connect(inst.sock)) {
    cap.fail_reason = "connect failed: " + c.last_error();
    return cap;
  }
  cap.connected = true;
  cap.version_full = query_scalar(c, "SELECT VERSION()");
  cap.version_banner = myver_banner(s);
  if (cap.version_banner.empty()) cap.version_banner = cap.version_full;
  for (auto& r : query_rows(c, "SHOW ENGINES")) {
    if (r.size() >= 3 && (r[1] == "YES" || r[1] == "DEFAULT")) {
      string e = lower(r[0]);
      cap.engines.insert(e);
      if (r[2] == "YES") cap.tx_engines.insert(e);
    }
  }
  cap.has_partitioning =
    s.vendor == Vendor::MySQL ? cap.engines.count("innodb") > 0
      : !query_scalar(c, "SELECT PLUGIN_STATUS FROM INFORMATION_SCHEMA.PLUGINS "
                         "WHERE PLUGIN_NAME='partition' AND PLUGIN_STATUS='ACTIVE'").empty();
  string osw = query_scalar(c, "SELECT @@optimizer_switch");
  for (auto& kvs : split(osw, ',')) {
    size_t eq = kvs.find('=');
    if (eq == string::npos) continue;
    string n = trim(kvs.substr(0, eq)), v = trim(kvs.substr(eq + 1));
    cap.optimizer_flags.insert(n);
    cap.optimizer_switch_map[n] = v;
  }
  cap.has_collation = !query_rows(c,
    "SELECT COLLATION_NAME FROM INFORMATION_SCHEMA.COLLATIONS WHERE COLLATION_NAME='" +
    g_cfg.collation + "'").empty();
  // the setup statements the stream carries in-band are only emitted where they exist
  cap.has_stats_pins = !query_scalar(c, "SELECT @@global.innodb_stats_auto_recalc").empty() &&
                       !query_scalar(c, "SELECT @@global.innodb_stats_persistent").empty();
  cap.has_stat_sample_pages =
      !query_scalar(c, "SELECT @@global.innodb_stats_persistent_sample_pages").empty();
  cap.has_stat_tables = s.vendor == Vendor::MariaDB &&
                        !query_scalar(c, "SELECT @@session.use_stat_tables").empty();
  cap.has_purge_wait = !query_scalar(c, "SELECT @@global.innodb_max_purge_lag_wait").empty();
  // old_mode is legitimately empty on a recent MariaDB, so the marker separates "no flags"
  // from "no such variable"
  string om = query_scalar(c, "SELECT CONCAT('|', @@session.old_mode)");
  cap.has_old_mode = !om.empty();
  if (cap.has_old_mode) cap.old_mode = om.substr(1);
  cap.has_engine_var = !query_scalar(c, "SELECT @@session.default_storage_engine").empty();
  for (auto& v : PIN_VARS)
    if (!query_scalar(c, string("SELECT @@SESSION.") + v.name).empty()) cap.pin_vars.insert(v.name);
  string set_mode = "SET SESSION sql_mode='" + sql_mode + "'";
  cap.sql_mode_ok = (mysql_real_query(c.h, set_mode.c_str(), set_mode.size()) == 0);
  if (!cap.sql_mode_ok) cap.fail_reason = "sql_mode rejected: " + string(mysql_error(c.h));
  cap.explain_extended = (mysql_real_query(c.h, "EXPLAIN EXTENDED SELECT 1", 25) == 0);
  if (cap.explain_extended) {
    MYSQL_RES* r = mysql_store_result(c.h);
    if (r) mysql_free_result(r);
  }
  return cap;
}

// ===== PART 3 ===============================================================
// CORLOGIC_PART_MARKER

// ---------------------------------------------------------------------------
// side resolution + startup + --check
// ---------------------------------------------------------------------------
static vector<SideSpec> g_sides;
static vector<SideCaps> g_caps;        // parallel to g_sides

static const SideCaps* caps_for(const SideSpec* s) {
  for (size_t k = 0; k < g_sides.size(); k++)
    if (&g_sides[k] == s) return &g_caps[k];
  return nullptr;
}

// leading numeric version components, for newer/older ordering
static vector<long> version_key(const string& vf) {
  vector<long> k;
  long cur = -1;
  for (char c : vf) {
    if (c >= '0' && c <= '9') cur = (cur < 0 ? 0 : cur) * 10 + (c - '0');
    else if (c == '.' && cur >= 0) { k.push_back(cur); cur = -1; }
    else break;
  }
  if (cur >= 0) k.push_back(cur);
  return k;
}

// PLAN/PERF regression gate. Same version on both sides (option/engine sides): any
// direction counts. Cross-version, same vendor: only a worse NEWER build is a bug - a
// better newer build is a fix. Cross-vendor: only a worse MariaDB side is reportable.
static bool regression_reportable(const SideSpec* ref, const SideSpec* other, bool other_worse) {
  const SideSpec* worse = other_worse ? other : ref;
  if (ref->vendor != other->vendor) return worse->vendor == Vendor::MariaDB;
  const SideCaps* ca = caps_for(ref);
  const SideCaps* cb = caps_for(other);
  if (!ca || !cb) return true;
  vector<long> va = version_key(ca->version_full), vb = version_key(cb->version_full);
  if (va == vb) return true;
  const SideSpec* newer = (vb > va) ? other : ref;
  return worse == newer;
}
static string g_sql_mode_final;
// Partition forms only MariaDB has. PARTITIONING=1 keeps what MariaDB and MySQL share, so
// these are filtered out; PARTITIONING=2 lets them through, and the capability guard has
// already established that every side is MariaDB.
static const char* MARIADB_PARTITION_FORMS[] = {
  "PARTITION BY SYSTEM_TIME"
};
static vector<const char*> g_mariadb_partition_forms;   // empty when a side is not MariaDB

static bool g_setup_stats_pins = false;      // all sides have the InnoDB statistics variables
static bool g_setup_stat_pages = false;      // all sides take the ANALYZE sample size
static bool g_setup_stat_tables = false;     // all sides have engine-independent statistics
static bool g_setup_old_mode = false;        // every side can be put on the same old_mode
static string g_setup_old_mode_val;          // the value they all get
static string old_mode_without_utf8mb3(const string& v);
static string g_setup_engine;                // one engine on every side: settable in-band
static vector<string> g_setup_pins;          // PIN_VARS every side has
static vector<string> g_engine_pool;         // ENGINE_MIX pool: engines every side has
static bool g_engine_axis = false;           // the sides differ by engine
static bool g_same_vendor = true;            // ... or by vendor: resolve_compare_modes sets it
static bool g_engine_tx_mixed = false;       // ... and not every one of them is transactional
static bool g_engine_var_all = false;        // every side has default_storage_engine
static bool g_fk_allow = true;               // foreign keys are kept in the stream

static void resolve_sides() {
  if (g_cfg.basedirs.empty()) die("no basedirs given (config BASEDIRS= or command line)");
  // expand: basedirs x engines x options_sets -> sides (any axis of size 1 collapses)
  // with ENGINE_MIX on, the ENGINES list is the per-table pool and does not make sides
  vector<string> engines = (g_cfg.engines.empty() || g_cfg.engine_mix)
                             ? vector<string>{g_cfg.engine} : g_cfg.engines;
  vector<string> osets = g_cfg.options_sets.empty() ? vector<string>{""} : g_cfg.options_sets;
  int idx = 0;
  for (auto& b : g_cfg.basedirs) {
    for (auto& e : engines) {
      for (auto& o : osets) {
        SideSpec s;
        s.idx = ++idx;
        s.basedir = fs::absolute(trim(b)).lexically_normal().string();
        {                                  // bare basedir names resolve against /test
          std::error_code ec;
          string alt = "/test/" + trim(b);
          if (!fs::is_directory(s.basedir, ec) && fs::is_directory(alt, ec)) s.basedir = alt;
        }
        auto bo = g_cfg.bin_side.find(s.idx);
        s.bin = (bo != g_cfg.bin_side.end()) ? bo->second : probe_server_bin(s.basedir);
        if (s.bin.empty()) die("side%d: no server binary found under %s "
                               "(probed bin/mariadbd, bin/mysqld, sql/mariadbd, ...; BIN_SIDE%d= overrides)",
                               s.idx, s.basedir.c_str(), s.idx);
        parse_version(s);
        if (s.vendor == Vendor::Unknown) die("side%d: cannot determine vendor from '%s'", s.idx, s.ver_string.c_str());
        resolve_init_tool(s);
        s.engine = e;
        s.options = o;
        auto me = g_cfg.myextra_side.find(s.idx);
        if (me != g_cfg.myextra_side.end()) s.options += (s.options.empty() ? "" : " ") + me->second;
        char lb[160];
        snprintf(lb, sizeof(lb), "side%d %s %ld.%ld.%ld%s%s%s", s.idx, vendor_name(s.vendor),
                 s.ver_major, s.ver_minor, s.ver_patch,
                 g_cfg.engines.empty() ? "" : (" " + e).c_str(),
                 o.empty() ? "" : " ", o.empty() ? "" : o.c_str());
        s.label = lb;
        if (s.debug_build)
          logline("WARNING: side%d uses a DEBUG build (%s) - slow; an -opt build is recommended", s.idx, s.basedir.c_str());
        g_sides.push_back(std::move(s));
      }
    }
  }
  if (g_sides.size() == 1) {
    // one side only: duplicate it - combo side under combinatorics, plain A/A otherwise
    SideSpec s = g_sides[0];
    s.idx = 2;
    auto me = g_cfg.myextra_side.find(s.idx);
    if (me != g_cfg.myextra_side.end()) s.options += (s.options.empty() ? "" : " ") + me->second;
    if (g_cfg.optimizer_switch_combinatorics) {
      s.label = "side2 " + string(vendor_name(s.vendor)) + " combo";
    } else {
      // built the same way side 1's label is, off this side's own options: copying side 1's
      // label and appending would print the options it already carries a second time
      char lb[160];
      snprintf(lb, sizeof(lb), "side%d %s %ld.%ld.%ld%s%s%s", s.idx, vendor_name(s.vendor),
               s.ver_major, s.ver_minor, s.ver_patch,
               g_cfg.engines.empty() ? "" : (" " + s.engine).c_str(),
               s.options.empty() ? "" : " ", s.options.empty() ? "" : s.options.c_str());
      s.label = lb;
      logline("single side given - running A/A (side2 = the same basedir)");
    }
    g_sides.push_back(std::move(s));
  }
  if (g_sides.size() < 2)
    die("only %zu side(s) resolved - need at least 2", g_sides.size());
}

// start one instance per side under <rundir>/<tag>/sideN, probe caps
static bool start_sides(vector<Instance>& insts, const string& tag, bool probe) {
  insts.clear();
  insts.resize(g_sides.size());
  for (size_t i = 0; i < g_sides.size(); i++) {
    if (g_stop.load()) return false;
    SideSpec& s = g_sides[i];
    string tpl = template_for(s);
    insts[i].spec = &s;
    insts[i].set_paths(g_run.rundir + "/" + tag + "/side" + std::to_string(s.idx));
    if (!insts[i].start_fresh(tpl)) {
      logline("side%d: server failed to start - tail of %s follows", s.idx, insts[i].errlog.c_str());
      RunOut t = run_capture({"tail", "-5", insts[i].errlog});
      for (auto& l : split(t.out, '\n')) if (!l.empty()) logline("  side%d| %s", s.idx, l.c_str());
      return false;
    }
    if (probe) logline("side%d: server started (%zu/%zu)", s.idx, i + 1, g_sides.size());
  }
  if (probe) {
    logline("pre-flight check started (probing %zu sides)", g_sides.size());
    g_caps.assign(g_sides.size(), SideCaps{});
    for (size_t i = 0; i < g_sides.size(); i++)
      g_caps[i] = probe_side(g_sides[i], insts[i], g_sql_mode_final);
  }
  return true;
}

static bool caps_gate() {
  bool ok = true;
  for (size_t i = 0; i < g_sides.size(); i++) {
    SideSpec& s = g_sides[i];
    SideCaps& c = g_caps[i];
    if (!c.connected) { logline("side%d: FAIL - %s", s.idx, c.fail_reason.c_str()); ok = false; continue; }
    if (!c.has_collation) { logline("side%d: FAIL - collation %s not available", s.idx, g_cfg.collation.c_str()); ok = false; }
    if (!c.sql_mode_ok) { logline("side%d: FAIL - %s", s.idx, c.fail_reason.c_str()); ok = false; }
    if (!s.engine.empty() && !c.engines.count(s.engine)) {
      logline("side%d: FAIL - engine %s not available (has:%s)", s.idx, s.engine.c_str(),
              [&]{ string e; for (auto& x : c.engines) e += " " + x; return e; }().c_str());
      ok = false;
    }
    if (g_cfg.partitioning && !c.has_partitioning)
      logline("side%d: NOTE - no partitioning support; partition SQL will be skipped by the parse guard", s.idx);
  }
  // in-band setup statements are only emitted where every side accepts them
  g_setup_stats_pins = true;
  g_setup_stat_pages = true;
  g_setup_stat_tables = true;
  g_setup_old_mode = !g_sides.empty();
  g_setup_old_mode_val.clear();
  for (size_t i = 0; i < g_caps.size() && g_setup_old_mode; i++) {
    string want = old_mode_without_utf8mb3(g_caps[i].old_mode);
    if (!g_caps[i].has_old_mode) {
      logline("old_mode: side%d does not have it, so `_utf8` keeps each side's own meaning",
              g_sides[i].idx);
      g_setup_old_mode = false;
    } else if (i == 0) {
      g_setup_old_mode_val = want;
    } else if (want != g_setup_old_mode_val) {
      logline("old_mode: side%d wants '%s' where side%d wants '%s', so it is left alone",
              g_sides[i].idx, want.c_str(), g_sides[0].idx, g_setup_old_mode_val.c_str());
      g_setup_old_mode = false;
    }
  }
  if (g_setup_old_mode) {                    // only worth a statement if a side moves
    bool moves = false;
    for (auto& c : g_caps) if (c.old_mode != g_setup_old_mode_val) moves = true;
    g_setup_old_mode = moves;
    if (moves)
      logline("old_mode: every side runs with '%s', so `_utf8` means utf8mb4 on all of them",
              g_setup_old_mode_val.c_str());
  }
  if (!g_setup_old_mode) g_setup_old_mode_val.clear();
  bool engine_var = true, engine_same = true;
  for (size_t i = 0; i < g_sides.size(); i++) {
    if (!g_caps[i].has_stats_pins) g_setup_stats_pins = false;
    if (!g_caps[i].has_stat_sample_pages) g_setup_stat_pages = false;
    if (!g_caps[i].has_stat_tables) g_setup_stat_tables = false;
    if (!g_caps[i].has_engine_var) engine_var = false;
    if (g_sides[i].engine != g_sides[0].engine) engine_same = false;
  }
  g_engine_var_all = engine_var;
  g_setup_engine = (engine_var && engine_same && !g_sides[0].engine.empty())
                     ? g_sides[0].engine : string();
  // ENGINE_MIX pool: the engines every side has, so the same table gets the same engine
  g_engine_pool.clear();
  if (g_cfg.engine_mix) {
    string dropped;
    for (auto& e : g_cfg.engines) {
      bool all = true;
      for (auto& c : g_caps) if (!c.engines.count(lower(e))) all = false;
      if (all) g_engine_pool.push_back(lower(e));
      else dropped += (dropped.empty() ? "" : ", ") + e;
    }
    if (!dropped.empty()) logline("ENGINE_MIX: a side does not have %s - left out", dropped.c_str());
    string pool;
    for (auto& e : g_engine_pool) pool += " " + e;
    if (g_engine_pool.size() < 2)
      logline("ENGINE_MIX: needs two engines every side has (ENGINES=) - running on one engine");
    else
      logline("ENGINE_MIX: one engine per table from%s", pool.c_str());
  }
  // sides that differ by engine: a plan, a timing and a DDL row count are engine
  // properties, so only the outcomes an engine must agree on stay comparable
  // PARTITIONING=2 asks for the MariaDB-only partition forms: allowed only when no side
  // is MySQL, since one text run goes to every side
  g_mariadb_partition_forms.clear();
  if (g_cfg.partitioning == 1) {
    for (auto& f : MARIADB_PARTITION_FORMS) g_mariadb_partition_forms.push_back(f);
  } else if (g_cfg.partitioning >= 2) {
    bool all_mariadb = true;
    for (auto& sp : g_sides) if (sp.vendor != Vendor::MariaDB) all_mariadb = false;
    if (!all_mariadb) {
      logline("PARTITIONING=2 needs MariaDB on every side - the MariaDB-only partition "
              "forms stay filtered out");
      for (auto& f : MARIADB_PARTITION_FORMS) g_mariadb_partition_forms.push_back(f);
    }
  }
  g_engine_axis = !engine_same;
  if (g_engine_axis && (g_cfg.plan_compare || g_cfg.perf_factor > 0)) {
    g_cfg.plan_compare = 0;
    g_cfg.perf_factor = 0;
    logline("sides differ by engine: plan and perf compare are off, and the row count of a "
            "DDL is not compared; result, error and table data still compare");
  }
  if (g_engine_axis) {                    // is every side's engine transactional
    bool all_tx = true;
    for (size_t i = 0; i < g_sides.size() && i < g_caps.size(); i++) {
      string e = lower(g_sides[i].engine.empty() ? g_cfg.engine : g_sides[i].engine);
      if (!g_caps[i].tx_engines.count(e)) all_tx = false;
    }
    g_engine_tx_mixed = !all_tx;
    if (g_engine_tx_mixed)
      logline("one side is not transactional: a trial stops at a statement that fails on "
              "every side, because each engine undoes a different part of it");
  }
  // foreign keys: kept only where every engine in use enforces them
  {
    vector<string> in_use = g_engine_pool;
    for (auto& s : g_sides) if (!s.engine.empty()) in_use.push_back(lower(s.engine));
    bool enforced = true;
    for (auto& e : in_use) if (e != "innodb" && e != "rocksdb") enforced = false;
    g_fk_allow = g_cfg.fk == "1" ? true : (g_cfg.fk == "0" ? false : enforced);
    if (!g_fk_allow)
      logline("foreign keys are filtered out of the stream (FK=%s)", g_cfg.fk.c_str());
  }
  g_setup_pins.clear();
  {
    string missing;
    for (auto& v : PIN_VARS) {
      bool all = true;
      for (auto& c : g_caps) if (!c.pin_vars.count(v.name)) all = false;
      if (all) g_setup_pins.push_back(v.name);
      else missing += (missing.empty() ? "" : ", ") + string(v.name);
    }
    if (!missing.empty())
      logline("not pinned per trial (a side does not have it): %s", missing.c_str());
  }
  return ok;
}

// one aligned line per side, so sides compare column by column
static void print_check_matrix() {
  for (size_t i = 0; i < g_sides.size(); i++)
    if (!g_caps[i].version_banner.empty() && g_caps[i].version_banner != g_caps[i].version_full)
      logline("side%d: %s", g_sides[i].idx, shorten_commit_ids_log_only(g_caps[i].version_banner).c_str());
  vector<vector<string>> rows;
  rows.push_back({"side", "version", "DB", "connect", "engine", "collation",
                  "sql_mode", "partition", "explain", "opt-flags", "stat-pages",
                  "stat-tables"});
  for (size_t i = 0; i < g_sides.size(); i++) {
    SideSpec& s = g_sides[i];
    SideCaps& c = g_caps[i];
    string vshort = c.version_full.substr(0, c.version_full.find('-'));
    string db = s.vendor == Vendor::MySQL ? "MySQL" : "MariaDB";
    if (!c.connected) {
      rows.push_back({std::to_string(s.idx), vshort, db, "FAIL", c.fail_reason});
      continue;
    }
    rows.push_back({std::to_string(s.idx), vshort, db, "OK",
                    s.engine + (c.engines.count(s.engine) ? " OK" : " MISSING"),
                    c.has_collation ? "OK" : "MISSING", c.sql_mode_ok ? "OK" : "REJECTED",
                    c.has_partitioning ? "yes" : "no", c.explain_extended ? "EXTENDED" : "plain",
                    std::to_string(c.optimizer_flags.size()),
                    c.has_stat_sample_pages ? std::to_string(g_cfg.stats_sample_pages) : "no",
                    c.has_stat_tables ? "yes" : "no"});
  }
  size_t w[12] = {0};
  for (auto& r : rows)
    for (size_t j = 0; j < r.size(); j++) w[j] = std::max(w[j], r[j].size());
  for (auto& r : rows) {
    string line;
    for (size_t j = 0; j < r.size(); j++) {
      line += r[j];
      if (j + 1 < r.size()) line.append(w[j] - r[j].size() + 2, ' ');
    }
    logline("%s", line.c_str());
  }
}

// ---------------------------------------------------------------------------
// SQL stream: preamble, seed schema, generator invocation, statement filter
// ---------------------------------------------------------------------------
struct StreamStmt {
  string sql;
  bool state_only = false;     // compare outcome state only (ANALYZE and similar)
  bool checkpoint = false;     // a statistics refresh point: the sides are compared here
};

// Every setting the stream depends on is a statement in the stream: nothing that
// shapes a result or a plan is passed on the server command line, so a replay and
// a reported testcase carry the same state the discovery run had. One per line.
// `_utf8` means utf8mb3 while UTF8_IS_UTF8MB3 is in old_mode and utf8mb4 without it, so a
// literal changes meaning between a build that carries the flag by default and one that
// dropped it. Taking that one flag off every side, and leaving the rest of old_mode alone,
// makes the literal mean the same thing everywhere.
static string old_mode_without_utf8mb3(const string& v) {
  string out;
  for (auto& f : split(v, ',')) {
    string t = trim(f);
    if (t.empty() || upper(t) == "UTF8_IS_UTF8MB3") continue;
    out += (out.empty() ? "" : ",") + t;
  }
  return out;
}

static vector<string> session_setup_sql() {
  vector<string> v = {
    "SET sql_mode='" + g_sql_mode_final + "'",
    "SET NAMES " + g_cfg.charset + " COLLATE " + g_cfg.collation,
    "SET time_zone='+00:00'",
    "SET TIMESTAMP=1700000000"
  };
  if (g_setup_old_mode) v.push_back("SET SESSION old_mode='" + g_setup_old_mode_val + "'");
  if (!g_setup_engine.empty()) v.push_back("SET default_storage_engine=" + g_setup_engine);
  if (g_setup_stats_pins) {
    // persistent statistics that are never recalculated in the background, so the
    // estimates do not move under a running trial
    v.push_back("SET GLOBAL innodb_stats_persistent=ON");
    v.push_back("SET GLOBAL innodb_stats_auto_recalc=OFF");
  }
  // ANALYZE samples 20 leaf pages per index by default and scales the answer up, so two
  // servers holding the same rows can still store different row estimates. A sample this
  // large covers the whole index, so ANALYZE counts and both sides plan from one number.
  if (g_setup_stat_pages)
    v.push_back("SET GLOBAL innodb_stats_persistent_sample_pages=" +
                std::to_string(g_cfg.stats_sample_pages));
  // engine-independent statistics are preferred for queries by default; the value is
  // pinned here so the testcase names it and a changed default cannot move the finding
  if (g_setup_stat_tables) v.push_back("SET SESSION use_stat_tables=PREFERABLY_FOR_QUERIES");
  for (auto& p : g_setup_pins) {
    string val;
    if (g_cfg.pin_mode != "global")
      for (auto& pv : PIN_VARS) if (p == pv.name) { val = pv.fixed; break; }
    v.push_back("SET SESSION " + p + "=" + (val.empty() ? "@@GLOBAL." + p : val));
  }
  return v;
}
// Each trial works in its own database, so nothing a trial leaves behind can be read by
// the next one.
static string trial_db(long trial) { return "db" + std::to_string(trial); }
static vector<StreamStmt> preamble_sql(long trial) {
  string db = trial_db(trial);
  vector<StreamStmt> v;
  v.push_back({"ROLLBACK", true});     // clear any open transaction from the previous trial
  for (auto& s : session_setup_sql()) v.push_back({s, false});
  v.push_back({"DROP DATABASE IF EXISTS " + db, true});
  v.push_back({"CREATE DATABASE " + db + " CHARACTER SET " + g_cfg.charset + " COLLATE " + g_cfg.collation, false});
  v.push_back({"USE " + db, false});
  return v;
}

// Deterministic seed schema t1..t8: formula-driven values (no RNG), so the data is
// byte-identical across trials, runs and boxes. Engines come from each side's
// --default-storage-engine; the SQL itself carries no ENGINE/charset clauses.
static void seed_insert_rows(vector<StreamStmt>& out, const string& head, long rows,
                             const std::function<void(string&, long)>& row_fn) {
  const long batch = 200;
  string s;
  for (long i = 0; i < rows; i++) {
    if (i % batch == 0) { if (i) { out.push_back({std::move(s), false}); } s = head; }
    else s += ",";
    s += "(";
    row_fn(s, i);
    s += ")";
  }
  if (rows) out.push_back({std::move(s), false});
}
static string seed_date(long i) {         // fixed grid over 1990..2037
  char b[16];
  snprintf(b, sizeof(b), "%04ld-%02ld-%02ld", 1990 + (i * 7) % 48, 1 + (i * 5) % 12, 1 + (i * 3) % 28);
  return b;
}
static vector<StreamStmt> seed_schema_sql(bool with_partition) {
  vector<StreamStmt> v;
  if (!g_cfg.seed_schema) return v;
  if (!g_cfg.seed_sql.empty()) {
    if (!fs::is_regular_file(g_cfg.seed_sql) ||
        access(g_cfg.seed_sql.c_str(), R_OK) != 0)
      die("SEED_SQL %s is not a readable file", g_cfg.seed_sql.c_str());
    string body = read_file(g_cfg.seed_sql);
    for (auto& l : split(body, '\n')) {
      string s = trim(l);
      if (!s.empty() && s.rfind("--", 0) != 0 && s[0] != '#') {
        if (s.back() == ';') s.pop_back();
        v.push_back({s, false});
      }
    }
    return v;
  }
  auto num = [](string& s, long long n) { s += std::to_string(n); };
  // t1: empty table
  v.push_back({"CREATE TABLE t1 (id INT NOT NULL PRIMARY KEY, c1 INT, c2 VARCHAR(32), "
               "c3 DECIMAL(10,2), c4 DATETIME, c5 CHAR(8), KEY k1 (c1), KEY k2 (c2(8)))", false});
  // t2: 1 row, no PK, composite prefix key
  v.push_back({"CREATE TABLE t2 (c1 INT, c2 VARCHAR(32), c3 DATE, KEY k1 (c1, c2(4)))", false});
  v.push_back({"INSERT INTO t2 VALUES (1,'one','2001-01-01')", false});
  // t3: 10 rows, NULLs every 3rd
  v.push_back({"CREATE TABLE t3 (id INT NOT NULL PRIMARY KEY, c1 SMALLINT, c2 VARCHAR(16), "
               "c3 DECIMAL(8,3), KEY k1 (c1, id))", false});
  seed_insert_rows(v, "INSERT INTO t3 VALUES ", 10, [&](string& s, long i) {
    num(s, i); s += ",";
    if (i % 3 == 0) s += "NULL"; else num(s, (i * 13) % 100 - 50);
    s += ",'v" + std::to_string(i % 4) + "',";
    if (i % 5 == 4) s += "NULL"; else { num(s, i * 7); s += "." + std::to_string(i % 1000); }
  });
  // t4: 100 rows, heavy duplicates, ENUM + DATE
  v.push_back({"CREATE TABLE t4 (id INT NOT NULL PRIMARY KEY, c1 INT, c2 ENUM('a','b','c','d'), "
               "c3 DATE, c4 VARCHAR(24), KEY k1 (c1), KEY k2 (c2))", false});
  seed_insert_rows(v, "INSERT INTO t4 VALUES ", 100, [&](string& s, long i) {
    num(s, i); s += ","; num(s, i % 7); s += ",'";
    s += (char)('a' + i % 4); s += "','" + seed_date(i) + "','w" + std::to_string(i % 11) + "'";
  });
  // t5: 1000 rows, type-edge values
  v.push_back({"CREATE TABLE t5 (id BIGINT NOT NULL PRIMARY KEY, c1 BIGINT, c2 DECIMAL(20,6), "
               "c3 VARCHAR(40), c4 DATETIME, KEY k1 (c1), KEY k2 (c3(10), c1))", false});
  seed_insert_rows(v, "INSERT INTO t5 VALUES ", 1000, [&](string& s, long i) {
    num(s, i); s += ",";
    switch (i % 9) {
      case 0: s += "NULL"; break;
      case 1: s += "-9223372036854775808"; break;
      case 2: s += "9223372036854775807"; break;
      case 3: s += "0"; break;
      case 4: s += "-1"; break;
      default: num(s, (i * 37) % 2000 - 1000);
    }
    s += ",";
    switch (i % 7) {
      case 0: s += "NULL"; break;
      case 1: s += "-99999999999999.999999"; break;
      case 2: s += "99999999999999.999999"; break;
      case 3: s += "0.000001"; break;
      default: s += std::to_string((i * 11) % 500) + "." + std::to_string(i % 1000000);
    }
    s += ",";
    if (i % 13 == 12) s += "''";
    else s += "'s" + std::to_string(i % 100) + "x" + std::to_string((i * 3) % 17) + "'";
    s += ",'" + seed_date(i) + " " + (i % 24 < 10 ? "0" : "") + std::to_string(i % 24) + ":00:0" +
         std::to_string(i % 10) + "'";
  });
  // t6: 10000 rows, the join workhorse
  v.push_back({"CREATE TABLE t6 (id INT NOT NULL PRIMARY KEY, c1 INT, c2 INT, c3 VARCHAR(32), "
               "c4 DECIMAL(12,4), c5 DATE, KEY k1 (c1), KEY k2 (c2, c1), KEY k3 (c3(6)))", false});
  seed_insert_rows(v, "INSERT INTO t6 VALUES ", 10000, [&](string& s, long i) {
    num(s, i); s += ","; num(s, i % 100); s += ",";
    if (i % 17 == 16) s += "NULL"; else num(s, (i * 31) % 1000);
    s += ",'j" + std::to_string(i % 250) + "',";
    num(s, (i * 3) % 10000); s += "." + std::to_string(i % 10000);
    s += ",'" + seed_date(i) + "'";
  });
  // t7: partitioned when supported and enabled, plain otherwise
  string t7 = "CREATE TABLE t7 (id INT NOT NULL, c1 INT, c2 VARCHAR(20), PRIMARY KEY (id))";
  if (with_partition) t7 += " PARTITION BY HASH (id) PARTITIONS 4";
  v.push_back({t7, false});
  seed_insert_rows(v, "INSERT INTO t7 VALUES ", 100, [&](string& s, long i) {
    num(s, i); s += ","; num(s, (i * 13) % 40); s += ",'p" + std::to_string(i % 9) + "'";
  });
  // t8: binary/text
  v.push_back({"CREATE TABLE t8 (id INT NOT NULL PRIMARY KEY, b1 BLOB, x1 TEXT, vb VARBINARY(64))", false});
  seed_insert_rows(v, "INSERT INTO t8 VALUES ", 10, [&](string& s, long i) {
    num(s, i);
    s += ",x'" + string((size_t)(2 + (i % 5) * 2), "0123456789ABCDEF"[i % 16]) + "'";
    s += ",'text" + std::to_string(i) + "',x'FF00" + string((size_t)((i % 4) * 2), 'A') + "'";
  });
  // t9: the numeric and temporal types the tables above leave out, with a UNIQUE key
  v.push_back({"CREATE TABLE t9 (id INT NOT NULL PRIMARY KEY, c1 TINYINT UNSIGNED, "
               "c2 SMALLINT UNSIGNED, c3 FLOAT, c4 DOUBLE, c5 BIT(8), c6 YEAR, c7 TIME, "
               "c8 TIMESTAMP NULL DEFAULT NULL, UNIQUE KEY u1 (c1, c2), KEY k1 (c4))", false});
  seed_insert_rows(v, "INSERT INTO t9 VALUES ", 200, [&](string& s, long i) {
    num(s, i); s += ","; num(s, i % 256); s += ","; num(s, (i * 257) % 65536); s += ",";
    if (i % 11 == 10) s += "NULL"; else s += std::to_string((i % 400) - 200) + ".5";
    s += ",";
    if (i % 13 == 12) s += "NULL";
    else s += "0." + std::to_string(100000000 + (i * 7919) % 899999999);
    s += ",b'" + string(8 - (size_t)(i % 8) - 1, '0') + "1" + string((size_t)(i % 8), '0') + "'";
    s += "," + std::to_string(1990 + i % 40);
    s += ",'" + std::to_string(i % 24) + ":" + std::to_string(i % 60) + ":" +
         std::to_string((i * 7) % 60) + "'";
    s += ",";
    if (i % 7 == 6) s += "NULL"; else s += "'" + seed_date(i) + " 12:00:00'";
  });
  // t10: text the collation decides on - trailing space, case, multi-byte, empty
  v.push_back({"CREATE TABLE t10 (id INT NOT NULL PRIMARY KEY, c1 VARCHAR(32), c2 CHAR(16), "
               "c3 TEXT, KEY k1 (c1), KEY k2 (c3(12)))", false});
  {
    static const char* TXT[] = {"abc", "ABC", "abc ", " abc", "AbC", "", "aaa", "\u00e4bc",
                               "\u00c4BC", "\u65e5\u672c", "a", "A", "abcd", "ab", "zzz", "ZZZ"};
    seed_insert_rows(v, "INSERT INTO t10 VALUES ", 100, [&](string& s, long i) {
      const char* t = TXT[i % (sizeof(TXT) / sizeof(TXT[0]))];
      num(s, i);
      s += string(",'") + t + "','" + t + "','" + t + std::to_string(i % 5) + "'";
    });
  }
  // t11: one value on nearly every row, the rest distinct - the shape that makes two
  // optimizers pick different plans
  v.push_back({"CREATE TABLE t11 (id INT NOT NULL PRIMARY KEY, c1 INT, c2 INT, "
               "c3 VARCHAR(16), KEY k1 (c1), KEY k2 (c2))", false});
  seed_insert_rows(v, "INSERT INTO t11 VALUES ", 1000, [&](string& s, long i) {
    num(s, i); s += ",";
    if (i % 20) s += "0"; else num(s, i);         // 95% one value
    s += ",";
    if (i < 990) s += "1"; else num(s, i);        // 99% one value
    s += ",'k" + std::to_string(i % 3) + "'";
  });
  // t12: a wide row and a long composite index
  {
    string c12 = "CREATE TABLE t12 (id INT NOT NULL PRIMARY KEY";
    for (int i = 1; i <= 24; i++) c12 += ", c" + std::to_string(i) + " INT";
    c12 += ", KEY k1 (c1, c2, c3, c4, c5, c6, c7, c8))";
    v.push_back({c12, false});
    seed_insert_rows(v, "INSERT INTO t12 VALUES ", 50, [&](string& s, long i) {
      num(s, i);
      for (int k = 1; k <= 24; k++) {
        s += ",";
        if ((i + k) % 9 == 8) s += "NULL"; else num(s, (i * k) % 37);
      }
    });
  }
  // t13: a child row set that points at t6, when foreign keys are in play
  if (g_fk_allow) {
    v.push_back({"CREATE TABLE t13 (id INT NOT NULL PRIMARY KEY, ref INT, c1 VARCHAR(16), "
                 "KEY k1 (ref), CONSTRAINT fk1 FOREIGN KEY (ref) REFERENCES t6 (id))", false});
    seed_insert_rows(v, "INSERT INTO t13 VALUES ", 200, [&](string& s, long i) {
      num(s, i); s += ","; num(s, (i * 47) % 10000); s += ",'r" + std::to_string(i % 6) + "'";
    });
  }
  string an = "ANALYZE TABLE t1, t2, t3, t4, t5, t6, t7, t8, t9, t10, t11, t12";
  if (g_fk_allow) an += ", t13";
  v.push_back({an, true});               // result text varies per version; state compare only
  return v;
}

// ---------------------------------------------------------------------------
// statement filter: allowlist, deny tokens, LIMIT strip, user regex filter
// ---------------------------------------------------------------------------
struct FilterStats {
  std::atomic<long> not_allowed{0}, denied{0}, toggled_off{0}, user_filtered{0},
                    limit_stripped{0}, kept{0};
};
static FilterStats g_fstat;
static vector<std::pair<std::regex, std::atomic<long>*>> g_user_filters;
static vector<std::atomic<long>> g_user_filter_hits;

static void load_user_filters() {
  if (g_cfg.sql_filter_file.empty()) return;
  string body = read_file(g_cfg.sql_filter_file);
  vector<string> pats;
  for (auto& l : split(body, '\n')) {
    string p = trim(l);
    if (p.empty() || p[0] == '#') continue;
    pats.push_back(p);
  }
  g_user_filter_hits = vector<std::atomic<long>>(pats.size());
  for (size_t i = 0; i < pats.size(); i++) {
    try {
      g_user_filters.emplace_back(
        std::regex(pats[i], std::regex::extended | std::regex::icase), &g_user_filter_hits[i]);
    } catch (const std::regex_error& e) {
      die("SQL_FILTER_FILE %s: bad pattern '%s' (%s)", g_cfg.sql_filter_file.c_str(),
          pats[i].c_str(), e.what());
    }
  }
  logline("sql filter: %zu pattern(s) from %s", g_user_filters.size(), g_cfg.sql_filter_file.c_str());
}

// skip string literals and quoted identifiers; returns the position after the literal
static size_t skip_quoted(const string& s, size_t i) {
  char q = s[i++];
  while (i < s.size()) {
    if (s[i] == '\\' && q != '`' && i + 1 < s.size()) { i += 2; continue; }
    if (s[i] == q) { if (i + 1 < s.size() && s[i + 1] == q) { i += 2; continue; } return i + 1; }
    i++;
  }
  return i;
}
static bool ident_ch(char c) { return isalnum((unsigned char)c) || c == '_' || c == '$'; }

// strip every LIMIT clause (any depth), quote-aware; LIMIT n | n,m | n OFFSET m | ROWS EXAMINED n
static bool strip_limit(string& s) {
  bool stripped = false;
  for (size_t i = 0; i + 5 <= s.size(); ) {
    char c = s[i];
    if (c == '\'' || c == '"' || c == '`') { i = skip_quoted(s, i); continue; }
    if ((c == 'L' || c == 'l') && (i == 0 || !ident_ch(s[i - 1])) &&
        strncasecmp(s.c_str() + i, "LIMIT", 5) == 0 && (i + 5 == s.size() || !ident_ch(s[i + 5]))) {
      size_t j = i + 5;
      auto ws = [&]{ while (j < s.size() && isspace((unsigned char)s[j])) j++; };
      auto number = [&]{ size_t st = j; while (j < s.size() && isdigit((unsigned char)s[j])) j++; return j > st; };
      ws();
      if (strncasecmp(s.c_str() + j, "ROWS", 4) == 0) {
        j += 4; ws();
        if (strncasecmp(s.c_str() + j, "EXAMINED", 8) == 0) { j += 8; ws(); number(); }
        else { i++; continue; }                     // not a LIMIT form we know; leave it
      } else if (number()) {
        size_t save = j; ws();
        if (j < s.size() && s[j] == ',') { j++; ws(); number(); }
        else if (strncasecmp(s.c_str() + j, "OFFSET", 6) == 0 &&
                 (j + 6 == s.size() || !ident_ch(s[j + 6]))) { j += 6; ws(); number(); }
        else j = save;
      } else { i++; continue; }                     // LIMIT ? or expression: leave it
      s.erase(i, j - i);
      if (i > 0 && i < s.size() && !isspace((unsigned char)s[i - 1]) && !isspace((unsigned char)s[i]))
        s.insert(i, " ");
      stripped = true;
      continue;
    }
    i++;
  }
  if (stripped) {
    string t;
    t.reserve(s.size());
    for (size_t i = 0; i < s.size(); i++) {         // collapse doubled spaces outside quotes
      if (s[i] == '\'' || s[i] == '"' || s[i] == '`') {
        size_t e = skip_quoted(s, i);
        t.append(s, i, e - i);
        i = e - 1;
        continue;
      }
      if (s[i] == ' ' && !t.empty() && t.back() == ' ') continue;
      t += s[i];
    }
    s = trim(t);
  }
  return stripped;
}

// case-insensitive token found outside quotes
static bool stmt_readonly(const string& sql);

static bool has_token(const string& up, const char* tok) {
  size_t tl = strlen(tok);
  for (size_t i = 0; i + tl <= up.size(); ) {
    char c = up[i];
    if (c == '\'' || c == '"' || c == '`') { i = skip_quoted(up, i); continue; }
    if (up.compare(i, tl, tok) == 0) return true;
    i++;
  }
  return false;
}

static const char* ALLOW_PREFIXES[] = {
  "SELECT", "(SELECT", "WITH", "INSERT", "REPLACE", "UPDATE", "DELETE",
  "CREATE TABLE", "CREATE INDEX", "CREATE UNIQUE INDEX", "CREATE OR REPLACE TABLE",
  "ALTER TABLE", "TRUNCATE", "DROP TABLE", "DROP INDEX",
  "BEGIN", "START TRANSACTION", "COMMIT", "ROLLBACK",
  // reached only when the matching toggle is on; the token rules below drop them again
  "CREATE VIEW", "CREATE OR REPLACE VIEW", "ALTER VIEW", "DROP VIEW",
  "CREATE SEQUENCE", "CREATE OR REPLACE SEQUENCE", "ALTER SEQUENCE", "DROP SEQUENCE"
};
static const char* DENY_TOKENS[] = {   // matched against the uppercased statement
  "NOW(", "CURRENT_TIMESTAMP", "CURDATE", "CURTIME", "SYSDATE", "UNIX_TIMESTAMP", "UTC_",
  "CURRENT_DATE", "CURRENT_TIME", "LOCALTIME",
  "RAND(", "RANDOM_BYTES", "UUID", "SYS_GUID", "ENCRYPT(", "CONNECTION_ID", "LAST_INSERT_ID", "ROW_COUNT(",
  "OVER (", "OVER(", " WINDOW ",              // window frames: tie order is unspecified
  "GROUP_CONCAT", "ANY_VALUE(", "JSON_ARRAYAGG", "JSON_OBJECTAGG",  // unspecified aggregation order
  "FOUND_ROWS", "USER(", "CURRENT_USER", "SESSION_USER", "SYSTEM_USER", "CURRENT_ROLE",
  "DATABASE()", "SCHEMA()", "VERSION()", "@", "SLEEP(", "BENCHMARK(", "GET_LOCK",
  "RELEASE_LOCK", "IS_USED_LOCK", "IS_FREE_LOCK", "MASTER_", "WAIT_FOR",
  "CHARACTER SET", "CHARSET", "COLLATE", "ENGINE=", "ENGINE =",
  "INFORMATION_SCHEMA", "PERFORMANCE_SCHEMA", "MYSQL.", "SYS.",
  "DATA DIRECTORY", "INDEX DIRECTORY", "LOAD_FILE", "INTO OUTFILE", "INTO DUMPFILE",
  "SQL_CACHE", "SQL_NO_CACHE",
  "HIGH_PRIORITY", "LOW_PRIORITY", "DELAYED",
  "DROP DATABASE", "DROP SCHEMA", "CREATE DATABASE", "CREATE SCHEMA", "ALTER DATABASE",
  "RENAME TABLE", "EXCHANGE PARTITION", "IMPORT TABLESPACE", "DISCARD TABLESPACE"
};

// set when any side has no vector support (MariaDB CS < 11.8, ES < 11.4, MySQL always)
static bool g_deny_vector_sql = false;

// SQL constructs added in a specific version. When any side is older than the version its
// vendor needs (0 = that vendor never has the construct), matching statements are denied:
// the newer side would succeed while the older side raises an error, which is a version
// difference and not a bug. `also` (when set) must be present in the same statement for
// the entry to match. Versions use the vnum() form (12.3.0 = 120300).
struct VersionGated { const char* token; const char* also; long mariadb; long mysql; };
static const VersionGated VERSION_GATED[] = {
  {"ST_GEOHASH",          nullptr,     120300, 50700},
  {"ST_LATFROMGEOHASH",   nullptr,     120300, 50700},
  {"ST_LONGFROMGEOHASH",  nullptr,     120300, 50700},
  {"ST_POINTFROMGEOHASH", nullptr,     120300, 50700},
  {"MONTHS_BETWEEN",      nullptr,     120300, 0},
  {"ADD_MONTHS",          nullptr,     120300, 0},
  {"GEOMETRY",            "PARTITION", 110400, 0},
};
static vector<const VersionGated*> g_gated_deny;  // the entries denied for this run's sides


// the close paren matching the open one at `from`, quoted text skipped
static size_t matching_paren(const string& s, size_t from) {
  int depth = 0;
  for (size_t i = from; i < s.size(); i++) {
    char c = s[i];
    if (c == '\'' || c == '"' || c == '`') {           // skip a quoted run
      char q = c;
      for (i++; i < s.size(); i++) {
        if (s[i] == '\\' && q != '`') { i++; continue; }
        if (s[i] == q) break;
      }
      continue;
    }
    if (c == '(') depth++;
    else if (c == ')' && --depth == 0) return i;
  }
  return string::npos;
}

// ENGINE_MIX: one engine per table, picked from its name, the same on every side. One run
// the first keyword of a statement, upper case
static string leading_word(const string& sql) {
  size_t i = 0;
  while (i < sql.size() && (isspace((unsigned char)sql[i]) || sql[i] == '(')) i++;
  string w;
  while (i < sql.size() && isalpha((unsigned char)sql[i]) && w.size() < 12)
    w += (char)toupper((unsigned char)sql[i++]);
  return w;
}

// ALGORITHM= and LOCK= on an ALTER are online-DDL options only InnoDB takes, so a side on
// another engine answers ER_ALTER_OPERATION_NOT_SUPPORTED where InnoDB does the work.
// upper_blanked blanks out every string literal and quoted name, so a COMMENT='LOCK=NONE'
// keeps the bytes the stream held.
static string upper_blanked(const string& s);
static void strip_online_ddl(string& sql) {
  if (leading_word(sql) != "ALTER") return;
  for (const char* key : {"ALGORITHM", "LOCK"}) {
    string want = string(key) + "=";
    for (;;) {
      string up = upper_blanked(sql);
      size_t k = up.find(want);
      if (k == string::npos) break;
      size_t e = k + want.size();                      // over the value word
      while (e < sql.size() && (isalnum((unsigned char)sql[e]) || sql[e] == '_')) e++;
      size_t b = k;                                    // and back over ", "
      while (b > 0 && isspace((unsigned char)sql[b - 1])) b--;
      if (b > 0 && sql[b - 1] == ',') b--;
      sql.erase(b, e - b);
    }
  }
}

// The clauses come out where the two sides need not agree on them. Engines do not: only
// InnoDB carries the online forms. Vendors do not either: ALGORITHM=NOCOPY is a MariaDB
// keyword MySQL refuses as unknown, and MySQL wants a lock for ALGORITHM=COPY where a
// MariaDB from 11.4 on carries the copy with LOCK=NONE. The ALTER itself still runs on
// every side, so what it does to the table is still compared.
static bool stream_strips_online_ddl() { return g_engine_axis || !g_same_vendor; }

// then covers several engines while the sides still compare like for like. The clause goes
// straight after the column list, where a table option belongs.
static bool engine_mix_rewrite(string& sql) {
  if (g_engine_pool.size() < 2) return false;
  string up = upper(sql);
  if (up.rfind("CREATE", 0) != 0) return false;
  size_t tp = up.find(" TABLE ");
  size_t open = sql.find('(');
  if (tp == string::npos || open == string::npos) return false;
  size_t sel = up.find(" SELECT "), lik = up.find(" LIKE ");
  if ((sel != string::npos && sel < open) || (lik != string::npos && lik < open)) return false;
  size_t p = tp + 7;
  while (p < sql.size() && isspace((unsigned char)sql[p])) p++;
  if (up.compare(p, 14, "IF NOT EXISTS ") == 0) {
    p += 14;
    while (p < sql.size() && isspace((unsigned char)sql[p])) p++;
  }
  size_t e = p;
  while (e < sql.size() && !isspace((unsigned char)sql[e]) && sql[e] != '(') e++;
  string name;
  for (size_t i = p; i < e; i++) if (sql[i] != '`') name += (char)tolower((unsigned char)sql[i]);
  if (name.empty()) return false;
  size_t close = matching_paren(sql, open);
  if (close == string::npos) return false;
  sql.insert(close + 1, " ENGINE=" + g_engine_pool[fnv1a(name) % g_engine_pool.size()]);
  return true;
}

// returns true when the statement survives; may rewrite it (LIMIT strip)
static bool stream_filter_keep(string& stmt) {
  string up = upper(stmt);
  if (g_deny_vector_sql &&
      (up.find("VECTOR") != string::npos || up.find("VEC_") != string::npos))
    { g_fstat.denied++; return false; }
  for (auto* g : g_gated_deny)
    if (up.find(g->token) != string::npos &&
        (!g->also || up.find(g->also) != string::npos))
      { g_fstat.denied++; return false; }
  // A global or persisted value outlives the trial that sets it, so only a session value
  // may ever be set. The scope word decides, at any spacing and in any case, so the rule
  // holds if SET is ever allowed into the stream.
  if (up.rfind("SET", 0) == 0) {
    size_t p = 3;
    while (p < up.size() && isspace((unsigned char)up[p])) p++;
    if (up.compare(p, 6, "GLOBAL") == 0 || up.compare(p, 7, "PERSIST") == 0 ||
        up.compare(p, 8, "@@GLOBAL") == 0 || up.compare(p, 9, "@@PERSIST") == 0)
      { g_fstat.denied++; return false; }
  }
  bool allowed = false;
  for (auto* p : ALLOW_PREFIXES) {
    if (starts_with_i(stmt, p)) {
      // transactions only when enabled and every side runs a transactional engine
      if ((p[0] == 'B' || p[0] == 'S' || p[0] == 'C' || p[0] == 'R') &&
          (up.rfind("BEGIN", 0) == 0 || up.rfind("START", 0) == 0 ||
           up.rfind("COMMIT", 0) == 0 || up.rfind("ROLLBACK", 0) == 0)) {
        if (!g_cfg.tx) { g_fstat.toggled_off++; return false; }
      }
      allowed = true;
      break;
    }
  }
  if (!allowed) { g_fstat.not_allowed++; return false; }
  for (auto* t : DENY_TOKENS)
    if (has_token(up, t)) { g_fstat.denied++; return false; }
  if (!g_cfg.views && has_token(up, " VIEW ")) { g_fstat.toggled_off++; return false; }
  if (!g_cfg.sequences &&
      (has_token(up, "SEQUENCE") || has_token(up, "NEXT VALUE") || has_token(up, "NEXTVAL") ||
       has_token(up, "SETVAL") || has_token(up, "PREVIOUS VALUE") || has_token(up, "LASTVAL")))
    { g_fstat.toggled_off++; return false; }
  if (!g_fk_allow && up.find("FOREIGN KEY") != string::npos) { g_fstat.toggled_off++; return false; }
  if (!g_cfg.generated_columns && has_token(up, "GENERATED ALWAYS")) { g_fstat.toggled_off++; return false; }
  if (!g_cfg.partitioning && has_token(up, "PARTITION")) { g_fstat.toggled_off++; return false; }
  // PARTITIONING=1 keeps the forms MariaDB and MySQL share; 2 adds the MariaDB-only ones,
  // and the capability guard has already checked every side is MariaDB
  if (g_cfg.partitioning == 1 && !g_mariadb_partition_forms.empty())
    for (auto* t : g_mariadb_partition_forms)
      if (has_token(up, t)) { g_fstat.toggled_off++; return false; }
  // DROP TABLE/INDEX stays inside the t* namespace
  if (up.rfind("DROP TABLE", 0) == 0) {
    size_t p = 10;
    while (p < up.size() && isspace((unsigned char)up[p])) p++;
    if (up.compare(p, 10, "IF EXISTS ") == 0) { p += 10; while (p < up.size() && isspace((unsigned char)up[p])) p++; }
    if (p >= up.size() || (up[p] != 'T' && !(up[p] == '`' && p + 1 < up.size() && up[p + 1] == 'T')))
      { g_fstat.denied++; return false; }
  }
  for (auto& [re, hits] : g_user_filters) {
    if (std::regex_search(stmt, re)) { (*hits)++; g_fstat.user_filtered++; return false; }
  }
  // A LIMIT is where an optimizer earns its keep, so a read-only statement keeps it and is
  // compared by row count: which rows come back at a tie is the server's own choice. A
  // LIMIT on DML would write a different set of rows on each side and leave the two holding
  // different data, so there it goes.
  if (!stmt_readonly(stmt) && strip_limit(stmt)) g_fstat.limit_stripped++;
  if (stmt.empty()) { g_fstat.denied++; return false; }
  g_fstat.kept++;
  return true;
}

// call generatorcpp, over-generate 4x, filter down to queries_per_trial survivors
static uint64_t g_gen_seed_base = 0;              // SEED, or entropy, logged at startup
static std::atomic<uint64_t> g_gen_batches{0};    // + the batch number = a replayable seed

static vector<StreamStmt> generator_batch(int wid) {
  string raw = g_run.rundir + "/gen.w" + std::to_string(wid) + ".sql";
  long want = g_cfg.queries_per_trial;
  if (want <= 0) return {};                       // QUERIES_PER_TRIAL=0 means the seed alone
  long seed = (long)(g_gen_seed_base + g_gen_batches.fetch_add(1));
  vector<string> argv = {g_cfg.generator_bin, "--output", raw, "--seed", std::to_string(seed)};
  if (!g_cfg.weights_file.empty() && fs::exists(g_cfg.weights_file)) {
    argv.push_back("--weights");
    argv.push_back(g_cfg.weights_file);
  }
  argv.push_back(std::to_string(want * 4));
  RunOut r;
  for (int try_n = 1; try_n <= 3; try_n++) {
    r = run_capture(argv, g_run.rundir, 65536, 300);
    if (r.status == 0) break;
    logline("generator failed (status %d, attempt %d of 3): %s", r.status, try_n, trim(r.out).c_str());
    usleep(500000);
  }
  if (r.status != 0) {                    // the run keeps what it has and carries on
    logline("generator gave nothing after 3 attempts - this batch runs on the seed alone");
    return {};
  }
  string body = read_file(raw);
  vector<StreamStmt> out;
  out.reserve((size_t)want);
  size_t pos = 0;
  while (pos < body.size() && (long)out.size() < want) {
    size_t nl = body.find('\n', pos);
    if (nl == string::npos) nl = body.size();
    string stmt = trim(body.substr(pos, nl - pos));
    pos = nl + 1;
    if (stmt.empty() || stmt[0] == '#' || stmt.rfind("--", 0) == 0) continue;
    if (!stmt.empty() && stmt.back() == ';') { stmt.pop_back(); stmt = trim(stmt); }
    if (!stream_filter_keep(stmt)) continue;
    engine_mix_rewrite(stmt);              // after the filter: the pool decides the engine
    if (stream_strips_online_ddl()) strip_online_ddl(stmt);
    // the result text of a maintenance statement varies by version: compare the state
    bool state_only = starts_with_i(stmt, "ANALYZE") || starts_with_i(stmt, "OPTIMIZE") ||
                      starts_with_i(stmt, "CHECK") || starts_with_i(stmt, "REPAIR") ||
                      starts_with_i(stmt, "CHECKSUM");
    out.push_back({std::move(stmt), state_only});
  }
  return out;
}

// ---------------------------------------------------------------------------
// compare
// ---------------------------------------------------------------------------
static int g_error_mode = 1;     // 0 state, 1 code, 2 text
static int g_warning_mode = 0;   // -1 off, 0 state, 1 codes, 2 text

// The run's modes come from the run's own sides. A version sweep measures a different pair,
// and comparing a MySQL error number against a MariaDB one says nothing, so the pair being
// measured sets the mode for the length of that measurement.
static thread_local int t_error_mode = -2;      // -2 leaves the run's own mode in place
static thread_local int t_warning_mode = -2;
static int error_mode() { return t_error_mode == -2 ? g_error_mode : t_error_mode; }
static int warning_mode() { return t_warning_mode == -2 ? g_warning_mode : t_warning_mode; }

// A fractional second going into a temporal that carries no sub-second precision: MariaDB
// cuts it and MySQL rounds it, so one value prints one second apart. Which side cuts has
// to be known before that can be read as one value rather than as a difference, and it is
// known only where one vendor sits on each end.
static int trunc_side_for(Vendor a, Vendor b) {
  if (a == Vendor::MariaDB && b == Vendor::MySQL) return 0;
  if (a == Vendor::MySQL && b == Vendor::MariaDB) return 1;
  return -1;
}
static int g_trunc_side = -1;                   // -1 off, else the side that cuts
static thread_local int t_trunc_side = -2;      // -2 leaves the run's own side in place
static int trunc_side() { return t_trunc_side == -2 ? g_trunc_side : t_trunc_side; }

// a setting names the mode outright; "auto" follows the vendors
static int pick_mode(const string& v, bool same_vendor, int dflt_same, int dflt_cross) {
  if (v == "state") return 0;
  if (v == "code" || v == "codes") return 1;
  if (v == "text") return 2;
  if (v == "off") return -1;
  return same_vendor ? dflt_same : dflt_cross;
}

// the modes for one measured pair, as resolve_compare_modes would have picked them
struct CompareModeFor {
  CompareModeFor(Vendor a, Vendor b) {
    bool same = a == b;
    t_error_mode = pick_mode(g_cfg.error_compare, same, 1, 0);
    if (t_error_mode < 0) t_error_mode = 0;
    t_warning_mode = pick_mode(g_cfg.warning_compare, same, 1, 0);
    t_trunc_side = trunc_side_for(a, b);
  }
  ~CompareModeFor() { t_error_mode = -2; t_warning_mode = -2; t_trunc_side = -2; }
};

// The option group under test is there to change plans, so on an OPTIONS_SETS run every
// plan and timing difference is the option doing its job. auto turns both off there and
// leaves RESULT, ERROR, AFFECTED, CHECKSUM and CRASH to carry the run.
// OPTIMIZER_SWITCH_COMBINATORICS: side 1 runs the server default and side 2 runs one
// combination per trial. The list is every single flag flipped away from its default,
// then every pair of them, so a two-flag interaction is covered as well as one flag on
// its own. A flag whose default is not the same on every side is left out, because then
// the sides would differ before the combination is applied.
static vector<string> g_combos;                    // each entry is one optimizer_switch value
static std::atomic<long> g_combo_next{0};          // the next combination to hand out

static void resolve_combos() {
  if (!g_cfg.optimizer_switch_combinatorics || g_caps.empty()) return;
  std::map<string, string> def = g_caps[0].optimizer_switch_map;
  for (size_t i = 1; i < g_caps.size(); i++)
    for (auto it = def.begin(); it != def.end();) {
      auto o = g_caps[i].optimizer_switch_map.find(it->first);
      if (o == g_caps[i].optimizer_switch_map.end() || o->second != it->second) it = def.erase(it);
      else ++it;
    }
  def.erase("default");
  vector<string> names;
  if (g_cfg.optimizer_switch_flags == "all-common") {
    for (auto& kv : def) names.push_back(kv.first);
  } else {
    for (auto& n : split(g_cfg.optimizer_switch_flags, ',')) {
      string t = trim(lower(n));
      if (t.empty()) continue;
      if (!def.count(t))
        logline("OPTIMIZER_SWITCH_FLAGS: %s is not set the same on every side, left out", t.c_str());
      else names.push_back(t);
    }
  }
  auto flip = [&](const string& n) { return n + "=" + (def[n] == "on" ? "off" : "on"); };
  for (auto& n : names) g_combos.push_back(flip(n));
  for (size_t i = 0; i + 1 < names.size(); i++)
    for (size_t j = i + 1; j < names.size(); j++)
      g_combos.push_back(flip(names[i]) + "," + flip(names[j]));
  if (g_combos.empty())
    die("OPTIMIZER_SWITCH_COMBINATORICS: no optimizer_switch flag is set the same on every side");
  logline("optimizer_switch combinatorics: %zu flag(s), %zu combination(s) (%zu single, %zu pair)",
          names.size(), g_combos.size(), names.size(), g_combos.size() - names.size());
}

// The cursor holds the next combination, so a resumed run carries on where it stopped.
// It is written as combinations are handed out, so a run killed mid-trial can leave one
// combination untested rather than test it twice.
static string combo_cursor_path() { return g_run.workdir + "/corlogic.cursor"; }
static void combo_cursor_load() {
  if (g_combos.empty()) return;
  long v = atol(trim(read_file(combo_cursor_path())).c_str());
  if (v <= 0) return;
  g_combo_next.store(v);
  logline("optimizer_switch combinatorics: carrying on at combination %ld of %zu",
          v + 1, g_combos.size());
}
static void combo_cursor_save() {
  if (!g_combos.empty()) write_file(combo_cursor_path(), std::to_string(g_combo_next.load()) + "\n");
}

static void resolve_plan_perf_report() {
  bool opts_axis = g_cfg.options_sets.size() > 1 || g_cfg.optimizer_switch_combinatorics;
  bool on = g_cfg.plan_perf_report == "1"   ? true
            : g_cfg.plan_perf_report == "0" ? false
                                            : !opts_axis;
  if (on) return;
  if (g_cfg.plan_compare || g_cfg.perf_factor > 0)
    logline("plan and timing differences are not reported on this run (PLAN_PERF_REPORT=%s%s)",
            g_cfg.plan_perf_report.c_str(),
            opts_axis && g_cfg.plan_perf_report == "auto"
                ? (g_cfg.optimizer_switch_combinatorics ? ", the sides differ by optimizer_switch"
                                                        : ", the sides differ by options")
                : "");
  g_cfg.plan_compare = 0;
  g_cfg.perf_factor = 0;
}

static void resolve_compare_modes() {
  for (size_t i = 1; i < g_sides.size(); i++)
    if (g_sides[i].vendor != g_sides[0].vendor) g_same_vendor = false;
  g_error_mode = pick_mode(g_cfg.error_compare, g_same_vendor, 1, 0);
  g_warning_mode = pick_mode(g_cfg.warning_compare, g_same_vendor, 1, 0);
  if (g_error_mode < 0) g_error_mode = 0;
  // one vendor on each end, so a temporal one second apart can be read as one value
  g_trunc_side = -1;
  for (size_t i = 1; i < g_sides.size(); i++) {
    int ts = trunc_side_for(g_sides[0].vendor, g_sides[i].vendor);
    if (i == 1) g_trunc_side = ts;
    else if (ts != g_trunc_side) g_trunc_side = -1;
    if (g_trunc_side < 0) break;
  }
  if (g_trunc_side >= 0)
    logline("compare: side%d cuts a fractional second where the other side rounds it, so a "
            "temporal one second apart is one value",
            g_sides[g_trunc_side == 0 ? 0 : 1].idx);
  logline("compare: vendors %s, errors by %s, warnings %s", g_same_vendor ? "match" : "differ",
          g_error_mode == 2 ? "text" : g_error_mode == 1 ? "code" : "state",
          g_warning_mode == 2 ? "by text" : g_warning_mode == 1 ? "by codes" : g_warning_mode == 0 ? "by state" : "off");
  logline("compare: rows are compared as a set; the same rows in another order are "
          "counted as order-only notes, not as a difference");
}

struct DiffHit {
  string category;               // RESULT ERROR WARNING AFFECTED CHECKSUM CRASH TIMEOUT PLAN PERF
  long stmt_index = -1;
  string statement;
  string detail;                 // per-side one-liners
  int side_a = 0, side_b = 1;    // the diffing pair (0-based)
  string mech;                   // PLAN/PERF: precomputed UID mechanism (ratio + access delta)
  bool ref_worse = false;        // PLAN/PERF: the reference side is the worse one
  string combo;                  // combinatorics: the optimizer_switch side 2 ran with
  string diag;                   // PLAN: the plans and row counts detection measured
};

// A read-only statement keeps its LIMIT, and a LIMIT leaves the choice of rows at a tie to
// the server. Only the row count of such a statement is specified. Checked on a difference
// alone, so the scan costs nothing on the statements that agree.
static string upper_blanked(const string& s);
static size_t find_word_top(const string& up, const string& word, size_t from);

// A total tiebreaker for a statement that already has a top-level ORDER BY: every output
// column, by position, appended to the terms it sorts by. Rows that tie on those terms and
// on every column are the same row, so the result is one sequence and not a choice. Two
// sides that still return different sequences disagree about sorting itself. An empty
// return means the statement is not one this can rewrite safely.
static string order_by_total(const string& sql, unsigned cols) {
  if (cols == 0 || cols > 64) return {};
  string up = upper_blanked(sql);
  size_t ob = find_word_top(up, "ORDER BY", 0);
  if (ob == string::npos) return {};
  size_t at = sql.size();                    // the clauses that may follow the terms
  for (const char* t : {"LIMIT", "PROCEDURE", "INTO", "FOR UPDATE", "LOCK IN SHARE MODE",
                        "FOR SHARE", "OFFSET", "FETCH"}) {
    size_t p = find_word_top(up, t, ob + 8);
    if (p != string::npos && p < at) at = p;
  }
  string head = sql.substr(0, at);
  while (!head.empty() && isspace((unsigned char)head.back())) head.pop_back();
  string tail;
  for (unsigned c = 1; c <= cols; c++) tail += ", " + std::to_string(c);
  return head + tail + (at < sql.size() ? " " + sql.substr(at) : string());
}

static std::atomic<long> g_limit_ties{0};   // a kept LIMIT returned another tied row set
static std::atomic<long> g_limit_checked{0}; // of those, the ones a total ORDER BY confirmed
static std::atomic<long> g_order_checked{0}; // order notes a total ORDER BY confirmed as ties
// LIMIT clauses outside quotes, at any depth
static int limit_count(const string& sql) {
  int n = 0;
  for (size_t i = 0; i + 5 <= sql.size(); ) {
    char c = sql[i];
    if (c == '\'' || c == '"' || c == '`') { i = skip_quoted(sql, i); continue; }
    if ((c == 'L' || c == 'l') && (i == 0 || !ident_ch(sql[i - 1])) &&
        strncasecmp(sql.c_str() + i, "LIMIT", 5) == 0 &&
        (i + 5 == sql.size() || !ident_ch(sql[i + 5]))) {
      n++;
      i += 5;
      continue;
    }
    i++;
  }
  return n;
}

// The row set is not specified when a LIMIT chooses among rows the sort cannot separate: a
// LIMIT inside a subquery, more than one LIMIT, or a top-level LIMIT with no top-level
// ORDER BY. One top-level LIMIT under a top-level ORDER BY is not counted here: that one is
// settled by asking both sides again with a total tiebreaker.
static bool stmt_rows_unspecified(const string& sql) {
  int n = limit_count(sql);
  if (n != 1) return n > 1;
  string up = upper_blanked(sql);
  if (find_word_top(up, "LIMIT", 0) == string::npos) return true;
  return find_word_top(up, "ORDER BY", 0) == string::npos;
}

// one top-level LIMIT under a top-level ORDER BY: the case the tiebreaker can settle
static bool stmt_limit_ordered(const string& sql) {
  return limit_count(sql) == 1 && !stmt_rows_unspecified(sql);
}

static string outcome_brief(const QOutcome& o) {
  char b[192];
  switch (o.state) {
    case QState::OK:
    case QState::WARN:
      if (o.cols)
        snprintf(b, sizeof(b), "%s %zu row(s) %u col(s) hash=%016" PRIx64 "%s",
                 o.state == QState::WARN ? "WARN" : "OK", o.row_count, o.cols,
                 o.multiset_hash, o.capped ? " (capped)" : "");
      else
        snprintf(b, sizeof(b), "%s affected=%lld", o.state == QState::WARN ? "WARN" : "OK", o.affected);
      break;
    case QState::ERR: snprintf(b, sizeof(b), "ERROR %u: %s", o.err, o.errmsg.c_str()); break;
    case QState::CRASH: snprintf(b, sizeof(b), "CRASH (%u: %s)", o.err, o.errmsg.c_str()); break;
    case QState::TIMEOUT: snprintf(b, sizeof(b), "TIMEOUT (%u)", o.err); break;
    case QState::SKIP: snprintf(b, sizeof(b), "SKIP"); break;
  }
  string s = b;
  if (o.state == QState::WARN || !o.warnings.empty()) {
    s += " warn[";
    for (size_t i = 0; i < o.warnings.size(); i++)
      s += (i ? "," : "") + std::to_string(o.warnings[i].code);
    s += "]";
    bool first = true;
    for (auto& w : o.warnings)
      if (!w.msg.empty()) { s += first ? " " : "; "; s += w.msg; first = false; }
  }
  return s;
}

static vector<unsigned> warning_codes_sorted(const QOutcome& o) {
  vector<unsigned> v;
  for (auto& w : o.warnings) v.push_back(w.code);
  std::sort(v.begin(), v.end());
  return v;
}

// A table-maintenance statement (OPTIMIZE, ANALYZE, CHECK, REPAIR, also in their ALTER
// ... PARTITION forms) reports its failure as a result grid on one build - a Msg_type
// Error row carrying the message - and raises it as a plain error on another. The same
// words through the two channels are one outcome, not a difference.
static bool admin_error_equivalent(const QOutcome& e, const QOutcome& grid) {
  if (e.state != QState::ERR || grid.cols != 4 || e.errmsg.empty()) return false;
  for (auto& r : grid.rows) {
    size_t p = r.rfind('\t');
    if (p == string::npos || p == 0) continue;
    if (r.compare(p + 1, string::npos, e.errmsg) != 0) continue;
    size_t q = r.rfind('\t', p - 1);
    if (q != string::npos && r.compare(q + 1, p - q - 1, "Error") == 0) return true;
  }
  return false;
}

// One build raises as an error what the other keeps a warning. Across vendors the same
// complaint - the same code, or the same words - through the two severity channels is
// one outcome, not a difference. Between builds of one vendor it stays a difference:
// there a severity change is a real behaviour change.
static bool err_warn_equivalent(const QOutcome& e, const QOutcome& w) {
  if (g_same_vendor || e.state != QState::ERR || w.state != QState::WARN) return false;
  for (auto& x : w.warnings)
    if (x.code == e.err || (!e.errmsg.empty() && x.msg == e.errmsg)) return true;
  return false;
}

// One side computes a result in DECIMAL where the other picks DOUBLE (an aggregate over
// an ENUM does this), so one number prints at two precisions: 2.3333 against
// 2.3333333333333335. Cells that agree after rounding to the shorter fraction are one
// value under each vendor's own result-type policy, not a difference. Cells at the same
// precision, and anything not purely numeric, stay a difference.
static bool num_policy_equal(const string& x, const string& y) {
  if (x == y) return true;
  if (x.empty() || y.empty()) return false;
  char* e = nullptr;
  double dx = strtod(x.c_str(), &e);
  if (!e || *e) return false;
  double dy = strtod(y.c_str(), &e);
  if (!e || *e) return false;
  if (!std::isfinite(dx) || !std::isfinite(dy)) return false;
  auto frac = [](const string& s) {
    size_t d = s.find('.');
    return d == string::npos ? (size_t)0 : s.size() - d - 1;
  };
  size_t fx = frac(x), fy = frac(y);
  if (fx == fy) return false;
  double sc = std::pow(10.0, (double)std::min(fx, fy));
  double px = dx * sc, py = dy * sc;
  if (std::fabs(px) > 9e15 || std::fabs(py) > 9e15) return false;
  return std::llround(px) == std::llround(py);
}

static bool num_policy_row(const string& ra, const string& rb) {
  size_t ia = 0, ib = 0;
  for (;;) {
    size_t ta = ra.find('\t', ia), tb = rb.find('\t', ib);
    string ca = ra.substr(ia, ta == string::npos ? string::npos : ta - ia);
    string cb = rb.substr(ib, tb == string::npos ? string::npos : tb - ib);
    if (!num_policy_equal(ca, cb)) return false;
    if ((ta == string::npos) != (tb == string::npos)) return false;
    if (ta == string::npos) return true;
    ia = ta + 1;
    ib = tb + 1;
  }
}

static bool num_policy_match(const QOutcome& a, const QOutcome& b) {
  if (g_same_vendor || a.capped || b.capped || a.rows.empty() ||
      a.rows.size() != b.rows.size()) return false;
  vector<string> ra = a.rows, rb = b.rows;
  std::sort(ra.begin(), ra.end());
  std::sort(rb.begin(), rb.end());
  for (size_t i = 0; i < ra.size(); i++)
    if (!num_policy_row(ra[i], rb[i])) return false;
  return true;
}

// A TIME as [-]HH:MM:SS or a DATETIME as YYYY-MM-DD HH:MM:SS, in seconds, with kind saying
// which of the two it is. A cell carrying a fraction, and a bare DATE, are not either of
// them: a fraction that survived was never cut, and a DATE holds no seconds to differ by.
static bool temporal_seconds(const string& v, int& kind, long long& out) {
  int y, mo, d, h, mi, s;
  char tail;
  if (sscanf(v.c_str(), "%4d-%2d-%2d %2d:%2d:%2d%c", &y, &mo, &d, &h, &mi, &s, &tail) == 6) {
    struct tm t {};
    t.tm_year = y - 1900;
    t.tm_mon = mo - 1;
    t.tm_mday = d;
    t.tm_hour = h;
    t.tm_min = mi;
    t.tm_sec = s;
    time_t e = timegm(&t);
    if (e == (time_t)-1) return false;
    kind = 2;
    out = (long long)e;
    return true;
  }
  bool neg = !v.empty() && v[0] == '-';
  if (sscanf(v.c_str() + (neg ? 1 : 0), "%3d:%2d:%2d%c", &h, &mi, &s, &tail) == 3 &&
      h >= 0 && mi >= 0 && s >= 0) {
    kind = 1;
    out = (long long)h * 3600 + mi * 60 + s;
    if (neg) out = -out;
    return true;
  }
  return false;
}

// the rounded side is one second past the side that cut, and both are the same kind
static bool temporal_round_equal(const string& cut, const string& rnd) {
  if (cut == rnd) return true;
  int kc, kr;
  long long c, r;
  if (!temporal_seconds(cut, kc, c) || !temporal_seconds(rnd, kr, r)) return false;
  return kc == kr && r == c + 1;
}

static bool temporal_round_row(const string& rc, const string& rr) {
  size_t ic = 0, ir = 0;
  for (;;) {
    size_t tc = rc.find('\t', ic), tr = rr.find('\t', ir);
    if (!temporal_round_equal(rc.substr(ic, tc == string::npos ? string::npos : tc - ic),
                              rr.substr(ir, tr == string::npos ? string::npos : tr - ir)))
      return false;
    if ((tc == string::npos) != (tr == string::npos)) return false;
    if (tc == string::npos) return true;
    ic = tc + 1;
    ir = tr + 1;
  }
}

// Every cell that differs is one temporal value under each vendor's own rounding rule, so
// the result is one result. This reads the cells, not the statement, so a second expression
// in the same SELECT that really does differ still carries the statement to a report.
static bool temporal_round_match(const QOutcome& a, const QOutcome& b) {
  int ts = trunc_side();
  if (ts < 0 || a.capped || b.capped || a.rows.empty() || a.rows.size() != b.rows.size())
    return false;
  vector<string> ra = a.rows, rb = b.rows;
  std::sort(ra.begin(), ra.end());
  std::sort(rb.begin(), rb.end());
  const vector<string>& cut = ts == 0 ? ra : rb;
  const vector<string>& rnd = ts == 0 ? rb : ra;
  for (size_t i = 0; i < cut.size(); i++)
    if (!temporal_round_row(cut[i], rnd[i])) return false;
  return true;
}

// compare side b against side a for one statement; returns the category or "" on match
static bool stmt_is_dml(const string& sql) {
  string w = leading_word(sql);
  return w == "INSERT" || w == "UPDATE" || w == "DELETE" || w == "REPLACE" || w == "LOAD";
}

static string compare_pair(const QOutcome& a, const QOutcome& b, bool state_only,
                           const string& sql = "") {
  auto cls = [&](const QOutcome& o) {
    if (o.state == QState::WARN) return warning_mode() < 0 ? QState::OK : QState::WARN;
    return o.state;
  };
  QState sa = cls(a), sb = cls(b);
  if (state_only) {                    // warnings vary legitimately on these statements
    if (sa == QState::WARN) sa = QState::OK;
    if (sb == QState::WARN) sb = QState::OK;
  }
  if (sa == QState::CRASH || sb == QState::CRASH) return sa == sb ? "" : "CRASH";
  if (sa == QState::TIMEOUT || sb == QState::TIMEOUT) return sa == sb ? "" : "TIMEOUT";
  if (sa == QState::ERR || sb == QState::ERR) {
    if (sa != sb) {
      if (admin_error_equivalent(a, b) || admin_error_equivalent(b, a)) return "";
      if (err_warn_equivalent(a, b) || err_warn_equivalent(b, a)) return "";
      return "ERROR";
    }
    if (state_only) return "";
    // the same words are the same complaint, whatever code carries them
    if (!a.errmsg.empty() && a.errmsg == b.errmsg) return "";
    if (error_mode() >= 1 && a.err != b.err) return "ERROR";
    if (error_mode() >= 2 && a.errmsg != b.errmsg) return "ERROR";
    return "";
  }
  if (state_only) return "";           // the two states are equal by here
  if (warning_mode() >= 0 && sa != sb) return "WARNING";
  if (warning_mode() >= 1 && warning_codes_sorted(a) != warning_codes_sorted(b)) return "WARNING";
  if (warning_mode() >= 2) {
    auto txt = [](const QOutcome& o) {
      vector<string> v;
      for (auto& w : o.warnings) v.push_back(w.msg);
      std::sort(v.begin(), v.end());
      return v;
    };
    if (txt(a) != txt(b)) return "WARNING";
  }
  if (a.cols != b.cols) return "RESULT";
  if (a.cols) {
    if (a.row_count != b.row_count) return "RESULT";
    // the count a LIMIT returns is specified, the choice of rows at a tie is not
    if (a.multiset_hash != b.multiset_hash) {
      if (num_policy_match(a, b)) {}                   // one number, two result types
      else if (temporal_round_match(a, b)) {}          // one temporal, one cut and one round
      else if (!stmt_rows_unspecified(sql)) return "RESULT";
      else g_limit_ties++;
    }
  } else if (a.affected != b.affected) {
    // the count a DDL reports is the rows it copied, and each engine, and each vendor,
    // decides for itself whether it copies them at all: an ALTER one side runs instantly
    // reports none where a side that rebuilt the table reports every row it moved
    if (!((g_engine_axis || !g_same_vendor) && !sql.empty() && !stmt_is_dml(sql)))
      return "AFFECTED";
  }
  return "";
}

// --- plan and perf compare ---
static bool stmt_explainable(const string& sql) {
  string w = leading_word(sql);
  return w == "SELECT" || w == "WITH" || w == "INSERT" || w == "UPDATE" ||
         w == "DELETE" || w == "REPLACE";
}
// The statement a WITH feeds, upper case, or "" when it cannot be read. The CTE list is
// `name [(columns)] AS ( ... )` repeated and comma separated, so the body is the first word
// at bracket depth 0 that names a statement. A CTE name cannot be one of those words unless
// it is quoted, and a quoted name is blanked out before the walk.
static string with_body_word(const string& sql) {
  string up = upper_blanked(sql);
  size_t i = 0;
  auto skip_space = [&] { while (i < up.size() && isspace((unsigned char)up[i])) i++; };
  // leading_word reads over an opening bracket, so this starts where it started
  while (i < up.size() && (isspace((unsigned char)up[i]) || up[i] == '(')) i++;
  if (up.compare(i, 4, "WITH") != 0) return {};
  i += 4;
  skip_space();
  if (up.compare(i, 9, "RECURSIVE") == 0) i += 9;
  while (i < up.size()) {
    skip_space();
    if (i >= up.size()) break;
    if (up[i] == '(') {                              // a column list or a CTE body
      int depth = 0;
      for (; i < up.size(); i++) {
        if (up[i] == '(') depth++;
        else if (up[i] == ')' && --depth == 0) { i++; break; }
      }
      continue;
    }
    if (up[i] == ',') { i++; continue; }
    string w;
    while (i < up.size() && (isalnum((unsigned char)up[i]) || up[i] == '_')) w += up[i++];
    if (w.empty()) { i++; continue; }                // punctuation between the parts
    for (const char* body : {"SELECT", "INSERT", "UPDATE", "DELETE", "REPLACE", "TABLE",
                             "VALUES"})
      if (w == body) return w;
  }
  return {};
}

// A read-only statement keeps its LIMIT, is compared by timing, does not stop a trial on a
// timing error and is written twice into the testcase, so a write graded read-only goes
// wrong four ways. A WITH can carry any of the DML verbs after its CTE list.
static bool stmt_readonly(const string& sql) {
  string w = leading_word(sql);
  if (w == "SELECT") return true;
  if (w != "WITH") return false;
  string body = with_body_word(sql);
  return body.empty() ? false : body == "SELECT" || body == "TABLE" || body == "VALUES";
}

struct PlanInfo {
  bool ok = false;
  double rows_product = 1.0;     // per plan line, floored at 1
  string access;                 // comma-joined access types (type column)
  int lines = 0;                 // EXPLAIN rows: the shape of the plan
  string tables;                 // sorted table column, so the same shape is comparable
  string table_order;            // the same column in EXPLAIN row order: join order
  bool key_declined = false;     // this side said which key it could not use, and why
};

// A derived or materialised plan line carries a generated name, <subquery2> and the like,
// and the number in it is not guaranteed to agree across two builds. Folding the name to
// one token keeps an ordered comparison about the tables rather than about the numbering.
static string plan_table_key(const char* t) {
  if (!t) return "NULL";
  return t[0] == '<' ? string("<gen>") : string(t);
}
static PlanInfo explain_plan(Conn& c, const string& stmt) {
  PlanInfo pi;
  if (!c.h) return pi;
  string q = "EXPLAIN " + stmt;
  if (mysql_real_query(c.h, q.data(), q.size()) != 0) return pi;
  MYSQL_RES* res = mysql_store_result(c.h);
  if (!res) return pi;
  int rows_i = -1, type_i = -1, tbl_i = -1, extra_i = -1;
  unsigned nf = mysql_num_fields(res);
  MYSQL_FIELD* f = mysql_fetch_fields(res);
  for (unsigned i = 0; i < nf; i++) {
    if (strcasecmp(f[i].name, "rows") == 0) rows_i = (int)i;
    else if (strcasecmp(f[i].name, "type") == 0) type_i = (int)i;
    else if (strcasecmp(f[i].name, "table") == 0) tbl_i = (int)i;
    else if (strcasecmp(f[i].name, "Extra") == 0) extra_i = (int)i;
  }
  MYSQL_ROW row;
  std::multiset<string> tbls;
  while ((row = mysql_fetch_row(res))) {
    pi.lines++;
    // A table function line carries a fixed number in rows, not an estimate of the
    // document it reads, and each server picks its own constant. Multiplying it in
    // compares two constants, so leave the line out of the product.
    bool fixed_rows = extra_i >= 0 && row[extra_i] &&
                      strstr(row[extra_i], "Table function:") != nullptr;
    if (rows_i >= 0 && row[rows_i] && !fixed_rows)
      pi.rows_product *= std::max(1.0, atof(row[rows_i]));
    if (type_i >= 0) {
      if (!pi.access.empty()) pi.access += ",";
      pi.access += row[type_i] ? row[type_i] : "NULL";
    }
    if (tbl_i >= 0) {
      tbls.insert(row[tbl_i] ? row[tbl_i] : "NULL");
      pi.table_order += plan_table_key(row[tbl_i]) + ",";
    }
  }
  for (auto& t : tbls) pi.tables += t + ",";
  mysql_free_result(res);
  // A note naming the key it could not use, and the two types that stopped it, is this
  // side explaining the plan it picked. The count comes back with the result the EXPLAIN
  // returned, so the extra round trip only happens where there is something to read.
  if (mysql_warning_count(c.h) && mysql_real_query(c.h, "SHOW WARNINGS", 13) == 0) {
    if (MYSQL_RES* w = mysql_store_result(c.h)) {
      bool has_msg = mysql_num_fields(w) > 2;
      while ((row = mysql_fetch_row(w)))
        if (has_msg && row[2] && strstr(row[2], "Cannot use key") &&
            strstr(row[2], " of type "))
          pi.key_declined = true;
      mysql_free_result(w);
    }
  }
  pi.ok = true;
  return pi;
}

// What the optimizer was looking at, both sides side by side: one line per EXPLAIN row,
// then the row count of every base table of the current database. A plan candidate that
// does not replay is read against this, so the reason is measured rather than guessed.
static string plan_diag(Conn& a, Conn& b, const string& stmt, const string& la,
                        const string& lb) {
  string out;
  Conn* cs[2] = {&a, &b};
  const string* ls[2] = {&la, &lb};
  for (int i = 0; i < 2; i++) {
    out += "    " + *ls[i] + " EXPLAIN:";
    for (auto& r : query_rows(*cs[i], "EXPLAIN " + stmt)) {
      out += " [";
      for (size_t c = 0; c < r.size(); c++) out += (c ? "|" : "") + (r[c].empty() ? "-" : r[c]);
      out += "]";
    }
    // the bytes a table occupies, beside its row count: a plan choice can turn on the
    // pages the optimizer costs, and churn leaves a long-running server holding more of
    // them for the same rows
    std::map<string, string> bytes;
    for (auto& r : query_rows(*cs[i], "SELECT TABLE_NAME, IFNULL(DATA_LENGTH,0)+"
                                      "IFNULL(INDEX_LENGTH,0) FROM information_schema.TABLES"
                                      " WHERE TABLE_SCHEMA=DATABASE()"))
      if (r.size() > 1) bytes[r[0]] = r[1];
    out += "\n    " + *ls[i] + " rows:";
    for (auto& r : query_rows(*cs[i], "SHOW FULL TABLES WHERE Table_type='BASE TABLE'"))
      if (!r.empty() && !r[0].empty()) {
        out += " " + r[0] + "=" +
               query_scalar(*cs[i], "SELECT COUNT(*) FROM `" + r[0] + "`") + "rows/" +
               (bytes.count(r[0]) ? bytes[r[0]] : string("?")) + "bytes";
        for (auto& x : query_rows(*cs[i], "SHOW INDEX FROM `" + r[0] + "`"))
          if (x.size() > 6) out += "/" + x[2] + ":" + x[6];
      }
    out += "\n    " + *ls[i] + " stats: use_stat_tables=" +
           query_scalar(*cs[i], "SELECT @@use_stat_tables") + " cond_sel=" +
           query_scalar(*cs[i], "SELECT @@optimizer_use_condition_selectivity") +
           " sample_pages=" +
           query_scalar(*cs[i], "SELECT @@innodb_stats_persistent_sample_pages") +
           " eits_this_db=" +
           query_scalar(*cs[i], "SELECT COUNT(*) FROM mysql.index_stats WHERE db_name=DATABASE()") +
           "/" +
           query_scalar(*cs[i], "SELECT COUNT(*) FROM mysql.column_stats WHERE db_name=DATABASE()") +
           " eits_all=" + query_scalar(*cs[i], "SELECT COUNT(*) FROM mysql.index_stats") + "/" +
           query_scalar(*cs[i], "SELECT COUNT(*) FROM mysql.column_stats") + " history=" +
           query_scalar(*cs[i], "SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_STATUS "
                                "WHERE VARIABLE_NAME='INNODB_HISTORY_LIST_LENGTH'") +
           " uptime=" + query_scalar(*cs[i], "SELECT VARIABLE_VALUE FROM "
                                             "information_schema.GLOBAL_STATUS WHERE "
                                             "VARIABLE_NAME='UPTIME'");
    out += "\n";
  }
  return out;
}

// A range estimate is a live dive into the B-tree, so a row that is deleted but not yet
// purged still counts towards it. Purge runs in the background, so two servers holding the
// same rows dive to different numbers while one of them is behind. Waiting for the history
// list to drain puts every side in the state a fresh replay measures in, which is what
// makes a plan finding reproducible. The wait is capped, so a busy server cannot hold a
// worker: an incomplete wait costs a measurement, never the run.
static void purge_settle(Conn& c, const SideSpec* sp) {
  const SideCaps* cp = caps_for(sp);
  if (!c.h || !cp || !cp->has_purge_wait) return;
  static const char q[] = "SET STATEMENT max_statement_time=30 FOR "
                          "SET GLOBAL innodb_max_purge_lag_wait=0";
  mysql_real_query(c.h, q, sizeof(q) - 1);
}

// A transaction the stream opened stays open until something commits it. BEGIN and START
// TRANSACTION open one, COMMIT and ROLLBACK end one, and DDL and the statistics refresh
// commit on their own. Nothing else a stream can hold changes that state.
static bool stmt_opens_tx(const string& sql) {
  string w = leading_word(sql);
  if (w == "BEGIN") return true;
  return w == "START" && upper(sql).find("TRANSACTION") != string::npos;
}
static bool stmt_ends_tx(const string& sql) {
  string w = leading_word(sql);
  for (const char* c : {"COMMIT", "ROLLBACK", "CREATE", "ALTER", "DROP", "TRUNCATE",
                        "RENAME", "ANALYZE", "OPTIMIZE", "CHECK", "REPAIR", "FLUSH"})
    if (w == c) return true;
  return false;
}

// Statistics that match the data: ANALYZE every base table of the current database.
// The optimizer estimates rows from stored statistics, not from the rows themselves, so
// two sides holding different statistics for the same data report a plan difference the
// data does not carry. It runs on the stream connection at the refresh points the stream
// carries, and inside a plan check, so both sides and every replay refresh after the same
// statement. ANALYZE commits, so an open transaction would end here, at a point that moves
// with the row estimates: a plan check is therefore held back while one is open, and the
// refresh points the stream carries are fixed.
// A plan's table column carries aliases and <derived> names, so it cannot drive the list.
static void analyze_all(Conn& c) {
  if (!c.h) return;
  vector<string> names;
  for (auto& r : query_rows(c, "SHOW FULL TABLES WHERE Table_type='BASE TABLE'"))
    if (!r.empty() && !r[0].empty()) names.push_back(r[0]);
  const size_t chunk = 50;
  for (size_t i = 0; i < names.size(); i += chunk) {
    string q = "ANALYZE TABLE ";
    for (size_t j = i; j < names.size() && j < i + chunk; j++)
      q += (j > i ? ",`" : "`") + names[j] + "`";
    if (g_setup_stat_tables) q += " PERSISTENT FOR ALL";
    if (mysql_real_query(c.h, q.c_str(), q.size()) != 0) continue;
    MYSQL_RES* r = mysql_store_result(c.h);
    if (r) mysql_free_result(r);
  }
}

// A rows-product delta counts only when two EXPLAIN pairs agree on it, numbers and
// direction. A range estimate is a live dive into the B-tree, so it moves as the purge
// backlog moves, with no statement running: measured on CS 13.0.2, one table reported 1
// row for a range holding 74, and a clean replay of the same stream reported 74.
// PLAN_STATS_REFRESH=1, the default, puts an ANALYZE between the two reads, which settles
// the estimate and separates the reads by real work rather than by microseconds.
// why gets the reason when the delta does not hold.
// A plan that trades a key lookup for a full scan is a plan difference whatever the row
// estimate says, so it counts on its own. A move between two keyed accesses, or between two
// kinds of scan, tracks the estimate and is left to the ratio.
static bool access_keyed(const string& t) {
  return t == "system" || t == "const" || t == "eq_ref" || t == "ref" || t == "ref_or_null";
}
static bool access_scan_swap(const string& a, const string& b) {
  vector<string> va = split(a, ','), vb = split(b, ',');
  if (va.size() != vb.size()) return false;
  for (size_t i = 0; i < va.size(); i++)
    if ((access_keyed(va[i]) && vb[i] == "ALL") || (access_keyed(vb[i]) && va[i] == "ALL"))
      return true;
  return false;
}

// The key-traded-for-a-scan test walks the two access lists by position, so it says what it
// means only when position names the same table on both sides. The shape gate in front of it
// compares the table list as a sorted set, so it lets a pair through that joins the same
// tables in a different order, and there element i is a different table on each side. Where
// the orders differ the pair falls through to the rows-product, which is a product over the
// plan lines and does not depend on the order they were printed in.
static bool plans_line_up(const PlanInfo& a, const PlanInfo& b) {
  return a.table_order == b.table_order;
}

// which side does the full scan where the other uses a key: that side is the worse one
static bool scan_side_is_b(const string& a, const string& b) {
  vector<string> va = split(a, ','), vb = split(b, ',');
  for (size_t i = 0; i < va.size() && i < vb.size(); i++) {
    if (access_keyed(va[i]) && vb[i] == "ALL") return true;
    if (access_keyed(vb[i]) && va[i] == "ALL") return false;
  }
  return false;
}

static bool plan_delta_holds(Conn& ca, Conn& cb, const SideSpec* sa, const SideSpec* sb,
                            const string& stmt, double factor, PlanInfo& a, PlanInfo& b,
                            string* why) {
  bool dir = false;
  double first_a = 0, first_b = 0;
  string first_acc_a, first_acc_b;
  // Two reads, always. The first EXPLAIN of a statement can report a row estimate the next
  // one does not: measured on CS 13.0.2 against CS 13.1.0, the reference side gave a
  // rows-product of 2 on the first read and 12656 on the second, with the same access
  // types. Only the settled read is a plan measurement.
  for (int round = 0; round < 2; round++) {
    purge_settle(ca, sa);
    purge_settle(cb, sb);
    if (g_cfg.plan_stats_refresh) { analyze_all(ca); analyze_all(cb); }
    a = explain_plan(ca, stmt);
    b = explain_plan(cb, stmt);
    if (!a.ok || !b.ok) {
      if (why) *why = "EXPLAIN failed on a side";
      return false;
    }
    double hi = std::max(a.rows_product, b.rows_product);
    double lo = std::min(a.rows_product, b.rows_product);
    bool ratio = factor > 0 && hi > lo * factor;
    bool lined_up = plans_line_up(a, b);
    bool swap = lined_up && access_scan_swap(a.access, b.access);
    if (!ratio && !swap) {
      if (why) {
        char nb[384];
        snprintf(nb, sizeof(nb), "plan rows-product %.0f (%s) vs %.0f (%s), under the %.0fx "
                                 "factor and %s",
                 a.rows_product, a.access.c_str(), b.rows_product, b.access.c_str(), factor,
                 lined_up ? "no key traded for a scan"
                          : "the two plans join the tables in a different order, so the "
                            "access types are not comparable");
        *why = nb;
      }
      return false;
    }
    bool d = a.rows_product > b.rows_product;
    if (round == 0) {
      dir = d;
      first_a = a.rows_product;
      first_b = b.rows_product;
      first_acc_a = a.access;
      first_acc_b = b.access;
      continue;
    }
    if (d != dir) {
      if (why) *why = "plan delta changed direction between two reads";
      return false;
    }
    if (a.access != first_acc_a || b.access != first_acc_b) {
      if (why) *why = "the access types moved between two reads";
      return false;
    }
    // the same direction is not enough: a read that moved is not a measurement
    if (a.rows_product != first_a || b.rows_product != first_b) {
      if (why) {
        char nb[256];
        snprintf(nb, sizeof(nb), "the rows-product moved between two reads: %.0f/%.0f then %.0f/%.0f",
                 first_a, first_b, a.rows_product, b.rows_product);
        *why = nb;
      }
      return false;
    }
  }
  return true;
}

// the access-type delta keys a plan or perf finding; the size of the gap belongs in the
// report, not in the UID, or one defect returns as a new UID per gap size
static string plan_mech(const string& access) { return access.empty() ? "rows" : access; }

// first differing access type between two plans, "same" when equal
static string access_delta(const string& a, const string& b) {
  vector<string> va = split(a, ','), vb = split(b, ',');
  for (size_t i = 0; i < va.size() || i < vb.size(); i++) {
    string xa = i < va.size() ? va[i] : "-", xb = i < vb.size() ? vb[i] : "-";
    if (xa != xb) return xa + ">" + xb;
  }
  return "same";
}

// The mechanism a plan or perf finding carries. The access delta is read by position, so it
// names an access change only where position names the same table on both sides. Where it
// does not, the row estimate is what moved, and the mechanism says that rather than naming
// a change between two unrelated plan lines.
static string plan_mech_of(const PlanInfo& a, const PlanInfo& b) {
  return plans_line_up(a, b) ? plan_mech(access_delta(a.access, b.access)) : plan_mech("");
}

// serial median-of-5 wall time for one statement on one side (rows discarded)
static double perf_median5(Conn& c, const string& sql) {
  double t[5];
  for (int i = 0; i < 5; i++) {
    QOutcome o;
    exec_stmt(c, sql, o, false, false);
    if (o.state != QState::OK && o.state != QState::WARN) return -1;
    t[i] = o.ms;
  }
  std::sort(t, t + 5);
  return t[2];
}
static std::atomic<long> g_perf_gap_max{0};    // largest read-only side gap seen, in ms
static bool perf_exceeds(double fast, double slow) {
  return g_cfg.perf_factor > 0 && g_cfg.perf_min_delta > 0 &&
         slow > fast * g_cfg.perf_factor && slow - fast > g_cfg.perf_min_delta;
}

// ---------------------------------------------------------------------------
// lockstep trial engine
// ---------------------------------------------------------------------------
struct SideRun {
  Instance inst;
  Conn conn;                     // the single lockstep connection
  Conn ctl;                      // control connection: KILL QUERY on timeout
  string tpl;
  int revivals = 0;
  string connect_error;          // the client's own words when a started server took no session
  bool reconnect_all() {
    if (!conn.connect(inst.sock)) { connect_error = conn.last_error(); return false; }
    if (!ctl.connect(inst.sock)) { connect_error = ctl.last_error(); return false; }
    // the stream is identical on every side, so a per-side engine cannot ride in it
    if (g_engine_var_all && inst.spec && !inst.spec->engine.empty()) {
      string q = "SET default_storage_engine=" + inst.spec->engine;
      mysql_real_query(conn.h, q.data(), q.size());
    }
    return true;
  }
};

struct Stats {
  std::atomic<long> trials{0}, stmts{0}, parse_skips{0}, all_timeouts{0}, diffs{0},
                    order_notes{0}, warn_notes{0}, improve_notes{0}, crashes{0}, revivals{0},
                    unreproduced{0}, unverified{0}, plan_flux{0}, plan_shape{0},
                    plan_order{0}, plan_explained{0}, plan_in_tx{0}, engine_stops{0},
                    timing_notes{0};
  std::atomic<long> stmt_ms{0};              // summed trial wall time
};
static Stats g_stats;

// What every worker slot is doing right now: the dashboard's threads panel reads this.
// One line per slot, and a slot is one server, so a line reads
// "t12  tr833: s2: 125/2080 stmts" or "t13  tr200: s1: reducing: 300l left".
static std::mutex g_status_mtx;
static vector<string> g_slot_text;                    // per slot; empty = free
static std::map<long, long> g_red_lines;              // candidate -> testcase lines now

static thread_local vector<int> t_slots;              // the slots this thread holds
static thread_local vector<int> t_side_idx;           // the side each slot runs
static thread_local long t_trial = 0;                 // the trial they are working on

// fit text to a column without cutting a word in half: step back to the last space when
// one is near the end, and cut where it must otherwise
// A count that does not fit its cell is shortened, never cut. Cutting turns 1025637 into
// 102563, which reads as a smaller number, so a counter that only grows appears to fall
static string fit_number(const string& v, int w) {
  if ((int)v.size() <= w || v.empty()) return v;
  if (v.find_first_not_of("0123456789") != string::npos) return v;
  double d = strtod(v.c_str(), nullptr);
  static const char* const suf[] = {"k", "M", "G", "T", "P"};
  for (int i = 0; i < 5; i++) {
    d /= 1000.0;
    char b1[32];
    snprintf(b1, sizeof(b1), "%.1f%s", d, suf[i]);
    if ((int)strlen(b1) <= w) return b1;
    snprintf(b1, sizeof(b1), "%.0f%s", d, suf[i]);
    if ((int)strlen(b1) <= w) return b1;
  }
  return v;
}

static string fit_cell(const string& t, size_t w) {
  if (t.size() <= w) return t;
  size_t cut = t.rfind(' ', w);
  if (cut != string::npos && cut + 1 >= w - w / 4) return t.substr(0, cut);
  return t.substr(0, w);
}

static string lines_word(long n) {
  return std::to_string(n) + "l";
}

// which = index within this job's slots; empty text frees the line
static void slot_text_set(size_t which, const string& s) {
  std::lock_guard<std::mutex> lk(g_status_mtx);
  if (which >= t_slots.size()) return;
  int id = t_slots[which];
  if (id < 0 || id >= (int)g_slot_text.size()) return;
  int side = which < t_side_idx.size() ? t_side_idx[which] : (int)which + 1;
  g_slot_text[id] = s.empty() ? string()
                              : "t" + std::to_string(t_trial) + ": s" +
                                std::to_string(side) + ": " + s;
}
static void slot_text_all(const string& s) {
  for (size_t i = 0; i < t_slots.size(); i++) slot_text_set(i, s);
}
// the real side numbers of this job's slots, so the panel names the side it runs
static void slots_name_sides(const vector<int>& idx) {
  std::lock_guard<std::mutex> lk(g_status_mtx);
  for (size_t i = 0; i < idx.size() && i < t_side_idx.size(); i++) t_side_idx[i] = idx[i];
}
// reduction stage, on every slot of the job; lines < 0 leaves the count as it was.
// The line reads "<stage>: rt<n>: <lines>l left": rt<n> is the reducer trial, one per
// replay, so a slow stage looks slow and not hung; every replay is a fresh datadir copy
// and a server start per side.
static void set_red_status(long cand, const string& s, long lines, long probe = -1) {
  long ln = -1;
  {
    std::lock_guard<std::mutex> lk(g_status_mtx);
    if (s.empty()) { g_red_lines.erase(cand); }
    else {
      if (lines >= 0) g_red_lines[cand] = lines;
      auto it = g_red_lines.find(cand);
      if (it != g_red_lines.end()) ln = it->second;
    }
  }
  if (s.empty()) { slot_text_all(""); return; }
  string txt = s;
  if (probe > 0) txt += ": rt" + std::to_string(probe);
  if (ln >= 0) txt += ": " + lines_word(ln) + " left";
  slot_text_all(txt);
}

class Lockstep {
public:
  vector<SideRun>& sides;
  vector<QOutcome> outs;
  explicit Lockstep(vector<SideRun>& s) : sides(s), outs(s.size()) {
    side_done.assign(s.size(), 0);
    timed_flag.assign(s.size(), 0);
    forced_flag.assign(s.size(), 0);
    for (size_t i = 0; i < s.size(); i++) thr.emplace_back(&Lockstep::worker, this, i);
  }
  ~Lockstep() {
    {
      std::lock_guard<std::mutex> lk(mx);
      quit = true;
    }
    cv_go.notify_all();
    for (auto& t : thr) t.join();
  }
  // run one statement on every side concurrently; timeout -> KILL QUERY -> hard kill
  void exec_all(std::string_view sql, bool want_warn, bool keep_rows) {
    {
      std::lock_guard<std::mutex> lk(mx);
      cur = sql;
      this->want_warn = want_warn;
      this->keep_rows = keep_rows;
      std::fill(side_done.begin(), side_done.end(), 0);
      std::fill(timed_flag.begin(), timed_flag.end(), 0);
      std::fill(forced_flag.begin(), forced_flag.end(), 0);
      done = 0;
      epoch++;
    }
    cv_go.notify_all();
    std::unique_lock<std::mutex> lk(mx);
    auto all_done = [&] { return done == sides.size(); };
    double tmo = g_cfg.query_timeout;
    if (tmo <= 0) { cv_done.wait(lk, all_done); }
    else if (!cv_done.wait_for(lk, std::chrono::duration<double>(tmo), all_done)) {
      for (size_t i = 0; i < sides.size(); i++) {
        if (side_done[i]) continue;
        timed_flag[i] = 1;
        char kq[64];
        snprintf(kq, sizeof(kq), "KILL QUERY %lu", sides[i].conn.thread_id);
        if (sides[i].ctl.h) mysql_real_query(sides[i].ctl.h, kq, strlen(kq));
      }
      if (!cv_done.wait_for(lk, std::chrono::duration<double>(std::max(tmo, 15.0)), all_done)) {
        for (size_t i = 0; i < sides.size(); i++)      // wedged server: force it down
          if (!side_done[i] && sides[i].inst.pid > 0) {
            forced_flag[i] = 1;
            kill(sides[i].inst.pid, SIGKILL);
          }
        // a worker that is still out has to be waited for: returning leaves it writing into
        // outs. Say what is being waited for, so the run is not stopped with no message.
        for (int w = 0; !cv_done.wait_for(lk, std::chrono::seconds(30), all_done); w++)
          logline("lockstep: still waiting for %zu side(s) %ds after the kill",
                  sides.size() - done, (w + 1) * 30);
      }
    }
    // a side we forced down ourselves is a timeout: the crash is ours, not the server's
    for (size_t i = 0; i < sides.size(); i++)
      if (timed_flag[i] && (forced_flag[i] || outs[i].state != QState::CRASH))
        outs[i].state = QState::TIMEOUT;
    // an error on one side against a warning on another is adjudicated on the warning's
    // code and words, so the warning content is fetched even when the compare mode
    // alone would not ask for it
    if (!want_warn) {
      bool any_err = false, any_warn = false;
      for (auto& o : outs) {
        any_err |= o.state == QState::ERR;
        any_warn |= o.state == QState::WARN;
      }
      if (any_err && any_warn)
        for (size_t i = 0; i < sides.size(); i++)
          if (outs[i].state == QState::WARN && outs[i].warnings.empty())
            fetch_warnings(sides[i].conn, outs[i]);
    }
  }
private:
  std::mutex mx;
  std::condition_variable cv_go, cv_done;
  vector<std::thread> thr;
  std::string_view cur;
  bool want_warn = true, keep_rows = true, quit = false;
  uint64_t epoch = 0;
  size_t done = 0;
  vector<uint8_t> side_done, timed_flag, forced_flag;
  void worker(size_t i) {
    MysqlThreadScope mts;
    uint64_t seen = 0;
    for (;;) {
      std::string_view sql;
      bool ww, kr;
      {
        std::unique_lock<std::mutex> lk(mx);
        cv_go.wait(lk, [&] { return quit || epoch != seen; });
        if (quit) return;
        seen = epoch;
        sql = cur;
        ww = want_warn;
        kr = keep_rows;
      }
      QOutcome o;
      exec_stmt(sides[i].conn, sql, o, ww, kr);
      {
        std::lock_guard<std::mutex> lk(mx);
        outs[i] = std::move(o);
        side_done[i] = 1;
        done++;
      }
      cv_done.notify_all();
    }
  }
};

// write the trial stream (one statement per line, with trailing ;) for replay/reduction
static void write_stream_file(const string& path, const vector<StreamStmt>& stream) {
  string body;
  body.reserve(1 << 20);
  for (auto& s : stream) { body += s.sql; body += ";\n"; }
  write_file(path, body);
}

// cores are written sparse by the kernel; a plain copy materializes the holes
static void copy_core_sparse(const string& src, const string& dst) {
  run_capture({"/bin/cp", "--sparse=always", src, dst});
}

static string newest_core_in(const string& dir) {
  string newest_core;
  fs::file_time_type newest{};
  std::error_code ec;
  for (auto& de : fs::directory_iterator(dir, ec)) {
    string fn = de.path().filename().string();
    if (fn.rfind("core", 0) == 0 && de.last_write_time(ec) >= newest) {
      newest = de.last_write_time(ec);
      newest_core = de.path().string();
    }
  }
  return newest_core;
}

static void save_diff_artifacts(long trial, int wid, const vector<StreamStmt>& stream,
                                const DiffHit& hit, vector<SideRun>& sides) {
  string base = g_run.workdir + "/trial" + std::to_string(trial);
  bool crash = hit.category == "CRASH";
  // A candidate is a bug only once its replay confirms it, and then the report
  // carries everything: no working files unless a crash needs its evidence.
  if (crash || g_cfg.keep_all_trials) {
    write_stream_file(base + ".sql", stream);
    string rep = "category: " + hit.category + "\n";
    // shown 1-based, matching the line number in trial<N>.sql (internal indexes are 0-based)
    rep += "statement line: " + std::to_string(hit.stmt_index + 1) + "\n";
    rep += "statement: " + hit.statement + "\n\n" + hit.detail + "\n";
    write_file(base + ".diff.txt", rep);
  }
  if (crash) {
    // secure the error log now: the revive wipes the datadir (cores are copied
    // in handle_diff, only when the crash turns out to be a new bug - they are large)
    for (auto& sr : sides) {
      if (sr.inst.alive()) continue;
      std::error_code ec;
      string sfx = "-side" + std::to_string(sr.inst.spec->idx);
      fs::copy_file(sr.inst.errlog, base + sfx + ".err", fs::copy_options::overwrite_existing, ec);
    }
  }
  logline("set %d: trial %ld: %s diff at line %ld", wid, trial,
          hit.category.c_str(), hit.stmt_index + 1);
}

// ---------------------------------------------------------------------------
// worker slots: one budget for the whole box
// ---------------------------------------------------------------------------
// A slot is one running server, and the pool holds one slot per cpu thread. Every piece
// of work draws from the same pool for as long as it runs: a trial takes one slot per
// side, a reduction takes two (its replays, its version sweep and its report included).
// Discovery therefore gets whatever reduction is not using, and the other way round,
// instead of each having a fixed share.
struct SlotPool {
  std::mutex m;
  std::condition_variable cv;
  vector<char> busy;                   // one entry per slot, 1 = taken
  struct Waiter { long ticket; bool prio; };
  vector<Waiter> waiting;              // who is asking; served in order, work on a
  long next_ticket = 0;                // candidate first
  void init(int n) {
    std::lock_guard<std::mutex> lk(m);
    busy.assign((size_t)std::max(1, n), 0);
  }
  int total() { std::lock_guard<std::mutex> lk(m); return (int)busy.size(); }
  int in_use() {
    std::lock_guard<std::mutex> lk(m);
    int u = 0;
    for (char c : busy) u += c ? 1 : 0;
    return u;
  }
  vector<int> take(int n, bool prio) {
    std::unique_lock<std::mutex> lk(m);
    long mine = next_ticket++;
    waiting.push_back({mine, prio});
    cv.wait(lk, [&] { return g_stop.load() || (head_ticket() == mine && free_now() >= n); });
    for (size_t i = 0; i < waiting.size(); i++)
      if (waiting[i].ticket == mine) { waiting.erase(waiting.begin() + i); break; }
    vector<int> got;
    for (size_t i = 0; i < busy.size() && (int)got.size() < n; i++)
      if (!busy[i]) { busy[i] = 1; got.push_back((int)i); }
    lk.unlock();
    cv.notify_all();
    return got;
  }
  void give(const vector<int>& ids) {
    {
      std::lock_guard<std::mutex> lk(m);
      for (int i : ids) if (i >= 0 && i < (int)busy.size()) busy[i] = 0;
    }
    cv.notify_all();
  }
 private:
  int free_now() {
    int f = 0;
    for (char c : busy) f += c ? 0 : 1;
    return f;
  }
  // work on a candidate goes first; within a class the oldest asker goes first
  long head_ticket() {
    long best = -1;
    bool best_prio = false;
    for (auto& w : waiting) {
      if (best < 0 || (w.prio && !best_prio)) { best = w.ticket; best_prio = w.prio; continue; }
      if (w.prio == best_prio && w.ticket < best) best = w.ticket;
    }
    return best;
  }
};
static SlotPool g_slots;

// Hold slots for the length of one job, with every line of the panel named by its trial.
// Returns how many were taken: a stopping run hands back what is free, which can be fewer
// than were asked for, and a caller that needs all of them has to see that.
static size_t slots_take(int n, long trial, bool prio = false,
                         const string& text = "starting") {
  t_slots = g_slots.take(n, prio);
  t_trial = trial;
  t_side_idx.clear();
  for (int i = 0; i < (int)t_slots.size(); i++) t_side_idx.push_back(i + 1);
  // named as it is taken: the panel drops a slot with nothing to say, so a slot named
  // later reads as a thread that is not there while the count still holds it
  slot_text_all(text);
  return t_slots.size();
}
static void slots_give() {
  slot_text_all("");
  g_slots.give(t_slots);
  t_slots.clear();
}

// ---------------------------------------------------------------------------
// UIDs: CATEGORY|MECHANISM|CONSTRUCTS - mechanism-keyed, version-free
// ---------------------------------------------------------------------------
static std::atomic<long> g_known_matches{0}, g_dup_diffs{0}, g_cands{0}, g_bugs{0}, g_reds_done{0};
static std::atomic<int> g_reds_active{0};              // jobs holding their two slots
static std::atomic<int> g_reds_admitted{0};            // jobs taken off the queue, slots or not
static std::atomic<int> g_reds_report{0};              // reporting, and still holding slots
static std::atomic<int> g_sweeps_pending{0};           // queued for a sweep, or sweeping now
static std::atomic<int> g_ver_sweeps{0};               // version sweeps replaying right now
static std::atomic<int> g_ver_sweeps_q{0};             // ... and waiting their turn, holding nothing
static std::atomic<long> g_final_fails{0};             // reduced testcases that did not replay
static std::atomic<int> g_red_slots{0};                // slots reductions hold right now
static int g_red_slot_max = 2;                         // the slots reductions may hold
static int g_red_max = 1;                              // that budget in whole jobs

// A reduction takes two slots for its whole life, its version sweep and its report
// included, so the share of the pool it holds is counted in slots and not in jobs. One more
// job is admitted only while its two slots fit the budget.
static bool reduction_admits(int held, int budget) {
  return held + 2 <= budget;
}

// The slots reductions may hold, weighed again on every admission. Each function asks for
// what its own work needs: a reduction wants two slots per candidate waiting or running, a
// trial always has more work to hand. Proving a difference is worth more than one more
// trial, so a deep queue takes the pool up to three quarters of it, and discovery keeps one
// trial's worth whatever happens.
// How many slots the box carries. A slot is one server, so it costs a datadir in the run
// dir and a resident set, both measured off the pre-flight rather than assumed. Most of a
// worker's time is spent waiting on a server and not on a cpu, so the cpu limit is one and
// a half slots a thread; RAM and the run dir are hard limits, and the smallest of the three
// wins. A cost that could not be measured leaves that limit out.
struct PoolFit { int by_cpu, by_ram, by_shm, chosen; const char* bound; };
static PoolFit pool_fit(unsigned cpus, uint64_t ram_free_kb, int ram_pct,
                        uint64_t shm_free_kb, uint64_t slot_ram_kb, uint64_t slot_shm_kb) {
  PoolFit f{};
  f.by_cpu = std::max(2, (int)(cpus * 3 / 2));
  auto fits = [](uint64_t room, uint64_t cost) {        // slots that much room holds
    return (int)std::min<uint64_t>(room / cost, 4096);
  };
  f.by_ram = slot_ram_kb ? fits(ram_free_kb * (uint64_t)ram_pct / 100, slot_ram_kb) : f.by_cpu;
  f.by_shm = slot_shm_kb ? fits(shm_free_kb, slot_shm_kb) : f.by_cpu;
  int m = std::min(f.by_cpu, std::min(f.by_ram, f.by_shm));
  f.bound = m == f.by_cpu ? "cpu" : (m == f.by_ram ? "RAM" : "rundir");
  f.chosen = std::max(2, m);
  return f;
}

static int reduction_slot_ceiling(int pool, int sides) {
  int keep = std::max(2, sides);                       // one trial always fits
  return std::max(2, std::min(pool * 3 / 4, pool - keep));
}
// Sweeps draw from the same pool as trials and reductions, so they take at most a third of
// it: a small box still runs one, and discovery always keeps its share
static int sweep_worker_count(int pool, int asked) {
  return std::clamp(asked, 1, std::max(1, pool / 6));
}
static int g_sweep_slots = 0;                          // what those workers may hold at once
static int reduction_slot_budget(int pool, int sides, size_t queued, int running) {
  long want = 2 * ((long)queued + running);
  return (int)std::clamp(want, (long)2, (long)reduction_slot_ceiling(pool, sides));
}

// reduce-now ends by itself once the reductions left, queued and running, fit inside that
// cap with room over. From there one reduction slot is free, so a new trial takes nothing
// away from a reduction.
static bool reduce_now_over(size_t queued, int running, int cap) {
  return (long)cap > (long)queued + running;
}
static constexpr int MAX_SIDE_STATS = 65;                // per-side counters, 1-based idx
static std::atomic<long> g_side_diffs[MAX_SIDE_STATS];
static std::atomic<long> g_side_revs[MAX_SIDE_STATS];
static std::mutex g_uid_mtx;
static std::map<string, long> g_uids_seen;             // UID -> candidate number (first sighting)
static std::map<string, long> g_uid1_seen;             // testcase id -> the trial that reported it
static std::map<string, long> g_uid_drops;             // UID -> how often its candidate dropped
static long g_trial_base = 0;                          // a resumed run numbers trials after this
static long g_cand_base = 0, g_bug_base = 0;           // and counts its own candidates and bugs

// the highest trial number the workdir already accounts for: its files, the trials named
// in bugs.seen, and the trial count of the last run that finished
static long last_trial_used() {
  long n = 0;
  std::error_code ec;
  for (auto& e : fs::directory_iterator(g_run.workdir, ec)) {
    string fn = e.path().filename().string();
    if (fn.rfind("trial", 0) == 0) n = std::max(n, atol(fn.c_str() + 5));
  }
  std::ifstream lf(g_run.workdir + "/corlogic-" + g_run.id + ".log");
  if (lf) {                                        // every log line names its trial
    lf.seekg(0, std::ios::end);
    long end = (long)lf.tellg();
    lf.seekg(std::max(0L, end - 65536), std::ios::beg);
    string line;
    while (std::getline(lf, line))
      for (size_t p = line.find("trial "); p != string::npos; p = line.find("trial ", p + 1))
        n = std::max(n, atol(line.c_str() + p + 6));
  }
  return n;
}

// --resume: the counters and the reported UIDs come back from bugs.seen, so numbering
// carries on and a bug already reported is not reported twice. A candidate that was
// dropped is not restored: a later sighting gets a fresh attempt.
static void resume_state() {
  g_trial_base = last_trial_used();
  std::ifstream f(g_run.workdir + "/bugs.seen");
  if (!f) {
    logline("resume: no bugs.seen in the workdir, so the counts start at zero after trial %ld",
            g_trial_base);
    return;
  }
  std::map<string, long> cand_of;
  std::set<string> bug_uids, cand_tags, bug_tags;
  string line;
  while (std::getline(f, line)) {
    size_t t1 = line.find('\t');
    if (t1 == string::npos) continue;
    size_t t2 = line.find('\t', t1 + 1);
    string tag = line.substr(0, t1);
    string uid = line.substr(t1 + 1, t2 == string::npos ? string::npos : t2 - t1 - 1);
    if (tag.rfind("bug", 0) == 0) {
      bug_tags.insert(tag);
      bug_uids.insert(uid);
    } else if (tag.rfind("cand", 0) == 0) {
      cand_tags.insert(tag);
      cand_of.emplace(uid, atol(tag.c_str() + 4));
    }
    if (t2 != string::npos) {
      size_t t3 = line.find('\t', t2 + 1);
      string tf = line.substr(t2 + 1, t3 == string::npos ? string::npos : t3 - t2 - 1);
      if (tf.rfind("trial", 0) == 0)                  // the field reads "trial<N>"
        g_trial_base = std::max(g_trial_base, atol(tf.c_str() + 5));
      if (t3 != string::npos && tag.rfind("bug", 0) == 0) {
        string rep = trim(line.substr(t3 + 1));         // the UID the report carries
        size_t sl = rep.find("//");
        if (sl != string::npos) g_uid1_seen[rep.substr(0, sl)] = atol(tag.c_str() + 3);
      }
    }
  }
  for (auto& u : bug_uids) {
    auto it = cand_of.find(u);
    g_uids_seen[u] = it == cand_of.end() ? 0 : it->second;
  }
  g_cands.store((long)cand_tags.size());
  g_bugs.store((long)bug_tags.size());
  g_cand_base = (long)cand_tags.size();
  g_bug_base = (long)bug_tags.size();
  logline("resume: the workdir holds %zu candidate(s) and %zu bug(s) up to trial %ld; "
          "%zu reported UID(s) and %zu reported testcase(s) muted",
          cand_tags.size(), bug_tags.size(), g_trial_base, g_uids_seen.size(),
          g_uid1_seen.size());
}

// per-detection ledger (first sightings and duplicates); ./pr reads it. Column 1 is
// cand<trial> at detection and bug<trial> once the replay confirms it, where the trial
// is the one the diff was first seen in: one number identifies it end to end.
static void append_seen(const string& tag, const string& uid, long trial,
                        const string& reported = "") {
  std::ofstream f(g_run.workdir + "/bugs.seen", std::ios::app);
  f << tag << "\t" << uid << "\ttrial" << trial;
  if (!reported.empty()) f << "\t" << reported;
  f << "\n";
}
// the categories a UID can carry; a known-bug line naming anything else is a typo
static bool is_uid_category(const string& c) {
  for (const char* k : {"RESULT", "ERROR", "AFFECTED", "WARNING", "PLAN", "PERF",
                        "CHECKSUM", "CRASH", "TIMEOUT"})
    if (c == k) return true;
  return false;
}

static vector<std::array<string, 5>> g_known;     // UID pattern, plus the ticket named above it
static std::set<string> g_known_uid1;             // corlogic.known testcase ids

static string upper_blanked(const string& s);

// The vocabulary a mute pattern is written against: query shape, statement verb, and the
// dialect features a version or a vendor difference turns on. The value is the tokens that
// matched, sorted and comma separated, and every token here is one a person can name.
static string constructs_of(std::string_view stmt) {
  string up = upper_blanked(string(stmt));
  static const std::pair<const char*, const char*> TOKS[] = {
    {" JOIN ", "JOIN"}, {"GROUP BY", "GROUPBY"}, {"ORDER BY", "ORDERBY"}, {"HAVING", "HAVING"},
    {"(SELECT", "SUBQ"}, {"WITH ", "CTE"}, {"DISTINCT", "DISTINCT"}, {"UNION", "UNION"},
    {"ROLLUP", "ROLLUP"}, {"PARTITION", "PARTITION"}, {"EXISTS", "EXISTS"}, {" IN ", "IN"},
    {"BETWEEN", "BETWEEN"}, {" LIKE ", "LIKE"}, {"CASE ", "CASE"}, {"CAST(", "CAST"},
    {"COUNT(", "AGG"}, {"SUM(", "AGG"}, {"AVG(", "AGG"}, {"MIN(", "AGG"}, {"MAX(", "AGG"},
    {"INSERT", "INSERT"}, {"UPDATE", "UPDATE"}, {"DELETE", "DELETE"}, {"REPLACE", "REPLACE"},
    {"ALTER", "ALTER"}, {"CREATE", "CREATE"}, {"DROP", "DROP"}, {"TRUNCATE", "TRUNCATE"},
    {"INDEX", "INDEX"}, {"CHECKSUM", "CHECKSUMTBL"},
    // a charset introducer: what it resolves to moved between versions, so it names a
    // family of its own
    {"_UTF8", "CSINTRO"}, {"_UTF8MB3", "CSINTRO"}, {"_UTF8MB4", "CSINTRO"},
    {"_LATIN1", "CSINTRO"}, {"_UCS2", "CSINTRO"}, {"_BINARY", "CSINTRO"},
    {"COLLATE", "COLLATE"}, {"JSON", "JSON"}, {"JSON_", "JSON"}, {"OVER (", "WINDOW"},
    {"NEXTVAL", "SEQ"}, {"PREVVAL", "SEQ"}, {"GENERATED ", "GENCOL"},
    {"ST_", "SPATIAL"}, {"VEC_", "VECTOR"},
  };
  // A token that starts with an identifier character has to start a word, and one that
  // ends in a letter or a digit has to end one, so a name that merely contains the token
  // is not read as the construct. A token written to end in "_", "(" or a space is a
  // prefix on purpose and keeps matching what follows it.
  auto has_tok = [&up](const char* pat) {
    size_t n = strlen(pat);
    bool lead = ident_ch(pat[0]), trail = isalnum((unsigned char)pat[n - 1]);
    for (size_t p = up.find(pat); p != string::npos; p = up.find(pat, p + 1)) {
      if (lead && p > 0 && ident_ch(up[p - 1])) continue;
      if (trail && p + n < up.size() && ident_ch(up[p + n])) continue;
      return true;
    }
    return false;
  };
  std::set<string> found;
  for (auto& [pat, tok] : TOKS)
    if (has_tok(pat)) found.insert(tok);
  string out;
  for (auto& t : found) {                    // every token that matched: a pattern written
    if (!out.empty()) out += ",";            // against this field has to find it here
    out += t;
  }
  return out.empty() ? "PLAIN" : out;
}

// crash mechanism from the dead side's error log: signal + up to two frames
static string crash_mechanism(const string& errlog_path) {
  string log = read_file(errlog_path);
  if (log.size() > 65536) log = log.substr(log.size() - 65536);
  string sig = "sig";
  size_t p = log.rfind("got signal ");
  if (p != string::npos) {
    size_t d = p + 11;
    while (d < log.size() && isdigit((unsigned char)log[d])) sig += log[d++];
  } else if ((p = log.rfind("Assertion")) != string::npos) {
    sig += "6";
  } else {
    return "sig?";        // no handler block in the log (e.g. an external kill): no frames
  }
  string frames;
  int nf = 0;
  size_t q = p;
  while (nf < 2 && (q = log.find('(', q)) != string::npos) {
    size_t e = log.find(')', q);
    if (e == string::npos) break;
    string fn = log.substr(q + 1, e - q - 1);
    q = e + 1;
    size_t cut = fn.find_first_of("+(");             // drop offset / C++ argument list
    if (cut != string::npos) fn = fn.substr(0, cut);
    if (fn.empty() || fn.find('/') != string::npos || fn.find(' ') != string::npos ||
        fn.find('*') != string::npos || fn.find('?') != string::npos ||
        fn.rfind("__", 0) == 0 || fn.find("0x") == 0 ||
        fn == "my_print_stacktrace" || fn == "handle_fatal_signal" ||
        fn == "raise" || fn == "abort" || fn == "pthread_kill" || fn == "_nl_load_domain")
      continue;                                      // unwinder / libc noise frames
    frames += ":" + fn;
    nf++;
  }
  return sig + frames;
}

// undo the hex rendering of one canonical row, so two rows carrying the same bytes but a
// different column charset compare equal
static string canon_unhex(const string& row) {
  string out;
  size_t i = 0;
  while (true) {
    size_t e = row.find('\t', i);
    string f = row.substr(i, e == string::npos ? string::npos : e - i);
    if (f.size() > 2 && f.compare(0, 2, "0x") == 0 && f.size() % 2 == 0 &&
        f.find_first_not_of("0123456789ABCDEF", 2) == string::npos) {
      string t;
      for (size_t k = 2; k + 1 < f.size(); k += 2) {
        char c = (char)strtol(f.substr(k, 2).c_str(), nullptr, 16);
        if (c == '\t') t += "\\t";
        else if (c == '\n') t += "\\n";
        else if (c == '\r') t += "\\r";
        else if (c == '\\') t += "\\\\";
        else t += c;
      }
      f = t;
    }
    out += f;
    if (e == string::npos) return out;
    out += '\t';
    i = e + 1;
  }
}

// what a terminal shows of a canonical row: the hex rendering undone, spacing and the
// escapes for tab, newline and return removed
static string print_form(const string& row) {
  string t = canon_unhex(row), out;
  for (size_t i = 0; i < t.size(); i++) {
    if (t[i] == '\\' && i + 1 < t.size() && (t[i + 1] == 't' || t[i + 1] == 'n' || t[i + 1] == 'r')) {
      i++;
      continue;
    }
    if (isspace((unsigned char)t[i])) continue;
    out += t[i];
  }
  return out;
}

static vector<string> sorted_map(const vector<string>& rows, string (*fn)(const string&)) {
  vector<string> v;
  for (auto& r : rows) v.push_back(fn(r));
  std::sort(v.begin(), v.end());
  return v;
}

// the two sides return the same bytes, and the column charset is the only difference
static bool same_bytes_diff_type(const QOutcome& a, const QOutcome& b) {
  if (a.capped || b.capped || a.rows.empty() || a.rows.size() != b.rows.size()) return false;
  if (a.rows == b.rows) return false;
  return sorted_map(a.rows, canon_unhex) == sorted_map(b.rows, canon_unhex);
}

// the bytes differ, but a client prints both sides the same, so the report has to say it
// in hex to show anything at all
static bool print_alike_diff_bytes(const QOutcome& a, const QOutcome& b) {
  if (a.capped || b.capped || a.rows.empty() || a.rows.size() != b.rows.size()) return false;
  if (a.rows == b.rows || same_bytes_diff_type(a, b)) return false;
  return sorted_map(a.rows, print_form) == sorted_map(b.rows, print_form);
}

static string uid_mech(const string& uid) {
  size_t a = uid.find('|');
  if (a == string::npos) return {};
  size_t b = uid.find('|', a + 1);
  return uid.substr(a + 1, b == string::npos ? string::npos : b - a - 1);
}

// A UID is CATEGORY|MECHANISM|CONSTRUCTS|STATEMENT, and a statement can hold a bar of its
// own, so only the first three bars divide fields and the rest of the line is the
// statement. A trailing empty field is kept as well, or a UID with no statement comes back
// with three fields and never lines up against a four-field pattern.
static vector<string> uid_fields(const string& uid) {
  vector<string> f;
  size_t p = 0;
  for (int i = 0; i < 3; i++) {
    size_t q = uid.find('|', p);
    if (q == string::npos) break;
    f.push_back(trim(uid.substr(p, q - p)));
    p = q + 1;
  }
  f.push_back(trim(uid.substr(p)));
  return f;
}

// Which numbered table or column a statement names is not what makes a finding, so every
// table reads tX and every column cX. Two findings that differ only in the number they
// touch then share one UID.
static string generic_name(const string& id) {
  if (id.size() > 1 && (id[0] == 't' || id[0] == 'c')) {
    size_t d = id.find_first_not_of("0123456789", 1);
    if (d == string::npos) return string(1, id[0]) + "X";
    // a numbered name with a suffix (c2_renamed) is the same name family
    if (d > 1 && id[d] == '_') return string(1, id[0]) + "X" + id.substr(d);
  }
  return id;
}

// the failing statement as it goes into a UID: each string literal becomes a letter in
// order of first appearance, each number becomes N, each table and column name is
// generic, spacing collapses, length is capped
static string norm_stmt(const string& sql) {
  static const char* LET = "XYZABCDEFGHIJKLMNOPQRSTUVW";
  std::map<string, string> lets;
  string out;
  size_t i = 0, n = sql.size();
  while (i < n) {
    char c = sql[i];
    if (c == '\'' || c == '"') {
      size_t j = i + 1;
      string lit;
      while (j < n) {
        if (sql[j] == '\\' && j + 1 < n) { lit += sql[j]; lit += sql[j + 1]; j += 2; continue; }
        if (sql[j] == c) {
          if (j + 1 < n && sql[j + 1] == c) { lit += c; j += 2; continue; }
          break;
        }
        lit += sql[j++];
      }
      auto it = lets.find(lit);
      if (it == lets.end()) {
        size_t k = lets.size();
        string tag(1, LET[k % 26]);
        if (k >= 26) tag += std::to_string(k / 26 + 1);
        it = lets.emplace(lit, tag).first;
      }
      out += "'" + it->second + "'";
      i = j < n ? j + 1 : n;
      continue;
    }
    if (c == '`' || isalpha((unsigned char)c) || c == '_') {   // a name, quoted or bare
      bool quoted = c == '`';
      size_t j = quoted ? i + 1 : i;
      string id;
      while (j < n) {
        char d = sql[j];
        if (quoted) {
          if (d == '`') {
            if (j + 1 < n && sql[j + 1] == '`') { id += d; j += 2; continue; }
            break;
          }
        } else if (!(isalnum((unsigned char)d) || d == '_' || d == '$')) {
          break;
        }
        id += d;
        j++;
      }
      string g = generic_name(id);
      out += quoted ? "`" + g + "`" : g;
      i = quoted ? (j < n ? j + 1 : n) : j;
      continue;
    }
    bool num_start = isdigit((unsigned char)c) &&
                     (out.empty() || !(isalnum((unsigned char)out.back()) || out.back() == '_'));
    if (num_start) {
      if (c == '0' && i + 1 < n && (sql[i + 1] == 'x' || sql[i + 1] == 'X')) {
        i += 2;
        while (i < n && isxdigit((unsigned char)sql[i])) i++;
      } else {
        while (i < n && (isdigit((unsigned char)sql[i]) || sql[i] == '.' ||
                         ((sql[i] == 'e' || sql[i] == 'E') && i + 1 < n &&
                          isdigit((unsigned char)sql[i + 1])))) i++;
      }
      out += 'N';
      continue;
    }
    if (isspace((unsigned char)c)) {
      if (!out.empty() && out.back() != ' ') out += ' ';
      i++;
      continue;
    }
    out += c;
    i++;
  }
  out = trim(out);
  while (!out.empty() && out.back() == ';') out.pop_back();
  if (out.size() > 120) out = out.substr(0, 117) + "...";
  return out;
}

// UID1: the first 12 hex characters of the md5 of the testcase text, so one exact
// testcase has one id. By hand, from a report:
//   sed -n '/^{code:sql}$/,/^{code}$/p' bugN.report | sed '1d;$d' | md5sum
static string uid1_of(const string& testcase, long tag) {
  string f = g_run.rundir + "/uid1." + std::to_string(tag);
  write_file(f, testcase);
  RunOut r = run_capture({"md5sum", f});
  std::error_code ec;
  fs::remove(f, ec);
  string h = trim(r.out);
  if (r.status != 0 || h.size() < 32) return {};
  return h.substr(0, 12);
}

// The mechanism field of a UID: what the two sides did differently, said in the terms of
// the category. Detection builds it from the outcomes it saw. A reduction ends on other
// data, so the counts move, and the final replay builds it again from what it measured.
static string outcome_mech(const string& category, const QOutcome& a, const QOutcome& b,
                           const string& statement, const string& crash_errlog,
                           const string& hit_mech) {
  string mech;
  char m[160];
  if (category == "ERROR") {
    snprintf(m, sizeof(m), "%uv%u", a.err, b.err);
    mech = m;
  } else if (category == "WARNING") {
    std::multiset<unsigned> wa, wb;
    for (auto& w : a.warnings) wa.insert(w.code);
    for (auto& w : b.warnings) wb.insert(w.code);
    for (auto c : wb) if (wa.erase(c) == 0) mech += "+" + std::to_string(c);
    for (auto c : wa) mech += "-" + std::to_string(c);
    if (mech.empty()) mech = "count";
  } else if (category == "AFFECTED") {
    snprintf(m, sizeof(m), "%lldv%lld", a.affected, b.affected);
    mech = m;
  } else if (category == "RESULT") {
    if (a.row_count != b.row_count) {
      snprintf(m, sizeof(m), "rows%ldv%ld", a.row_count, b.row_count);
      mech = m;
    } else if (same_bytes_diff_type(a, b)) mech = "coltype";
    else if (print_alike_diff_bytes(a, b)) mech = "bytes";
    else mech = "content";
  } else if (category == "CHECKSUM") {
    size_t t1 = statement.find('`'), t2 = statement.rfind('`');
    mech = (t1 != string::npos && t2 > t1) ? "tbl:" + statement.substr(t1 + 1, t2 - t1 - 1)
                                           : "tables";
  } else if (category == "TIMEOUT") {
    mech = "oneside";
  } else if (category == "PLAN" || category == "PERF") {
    mech = hit_mech.empty() ? "?" : hit_mech;
  } else if (category == "CRASH") {
    mech = crash_errlog.empty() ? "gone" : crash_mechanism(crash_errlog);
  } else mech = "?";
  return mech;
}

// A mechanism the final replay can measure again: the count pairs and the code pairs. A
// crash mechanism comes out of the error log, which the replay does not read, and a
// CHECKSUM table name is settled from the replay's own scan.
static bool mech_is_remeasurable(const string& category) {
  return category == "ERROR" || category == "WARNING" || category == "AFFECTED" ||
         category == "RESULT";
}

static string uid_build(const DiffHit& hit, const QOutcome& a, const QOutcome& b,
                        const string& crash_errlog) {
  return hit.category + "|" +
         outcome_mech(hit.category, a, b, hit.statement, crash_errlog, hit.mech) + "|" +
         constructs_of(hit.statement) + "|" + norm_stmt(hit.statement);
}

// a testcase id is the 12 hex characters a report prints before the "//"
static bool is_uid1(const string& s) {
  return s.size() == 12 && s.find_first_not_of("0123456789abcdef") == string::npos;
}

static long load_known_one(const string& path) {
  const char* kf = path.c_str();
  long bad = 0;
  string ticket;                                       // from the comment block above an entry
  for (auto& ln : split(read_file(path), '\n')) {
    string t = trim(ln);
    if (t.empty()) { ticket.clear(); continue; }
    if (t[0] == '#') {
      string up = upper(t);
      for (const char* pre : {"MDEV-", "MENT-"}) {
        size_t p = up.find(pre);
        if (p == string::npos) continue;
        size_t e = p + 5;
        while (e < t.size() && isdigit((unsigned char)t[e])) e++;
        if (e > p + 5) ticket = t.substr(p, e - p);
      }
      continue;
    }
    size_t sl = t.find("//");                          // a full UID line: keep both halves
    if (sl != string::npos) {
      string id = trim(t.substr(0, sl));
      if (is_uid1(id)) g_known_uid1.insert(id);
      else { logline("%s: skipping line, %s is not a testcase id: %s", kf, id.c_str(), t.c_str()); bad++; continue; }
      t = trim(t.substr(sl + 2));
      if (t.empty()) continue;
    }
    if (t.find('|') == string::npos) {                   // a bare UID1: one exact testcase
      if (is_uid1(t)) g_known_uid1.insert(t);
      else { logline("%s: skipping line, no UID field and not a testcase id: %s", kf, t.c_str()); bad++; }
      continue;
    }
    vector<string> f = uid_fields(t);
    if (f.size() < 3 || f[0].empty() || f[1].empty() || f[2].empty()) {
      logline("%s: skipping malformed line: %s", kf, t.c_str());
      bad++;
      continue;
    }
    // The category is a closed set and it is matched exactly, so a typo here would load
    // as a pattern that can never hit and mute nothing, without saying so
    if (!is_uid_category(f[0])) {
      logline("%s: skipping line, %s is not a category: %s", kf, f[0].c_str(), t.c_str());
      bad++;
      continue;
    }
    // a line that names no statement, or ends on a bare bar, keeps muting a whole family
    g_known.push_back({f[0], f[1], f[2],
                       (f.size() > 3 && !f[3].empty()) ? f[3] : "*", ticket});
  }
  return bad;
}

// every file KNOWN_FILE names, comma separated, in the order given: a list for one vendor or
// one engine matrix adds to the base list rather than replacing it
static void load_known_file() {
  long bad = 0;
  size_t files = 0;
  for (auto& one : split(g_cfg.known_file, ',')) {
    string path = trim(one);
    if (path.empty()) continue;
    // a path that is not a readable file mutes nothing, so one the user named is a
    // configuration error: the run would report every known bug again without saying so
    if (!fs::is_regular_file(path) || access(path.c_str(), R_OK) != 0) {
      if (g_cfg.known_file_set)
        die("KNOWN_FILE %s is not a readable file", path.c_str());
      logline("known filter: %s is not there, so nothing from it is muted", path.c_str());
      continue;
    }
    bad += load_known_one(path);
    files++;
  }
  if (!files) return;
  string note = bad ? ", " + std::to_string(bad) + " line(s) skipped" : string();
  logline("known filter: %zu UID pattern(s), %zu testcase id(s) from %zu file(s)%s",
          g_known.size(), g_known_uid1.size(), files, note.c_str());
}

// the statement field of a pattern is a wildcard when the line does not carry one, so a
// three-field line keeps muting a whole family
// One field of a pattern against the same field of a UID. A pattern field of "*" matches
// anything, a field ending in "*" matches by prefix, and a field wrapped in "*" matches
// anywhere in the value. That last one is for a family a construct triggers rather than a
// statement shape: the construct can sit anywhere in the statement, so a prefix cannot name
// it. CONSTRUCTS is a comma-separated token set, so the wrapped form is anchored on the
// commas there: *IN* means the token IN and not the IN inside INSERT.
static bool known_field_hit(const string& pat, const string& val, bool token_set = false) {
  if (pat == "*") return true;
  if (pat.size() > 2 && pat.front() == '*' && pat.back() == '*') {
    string want = pat.substr(1, pat.size() - 2);
    if (!token_set) return val.find(want) != string::npos;
    return ("," + val + ",").find("," + want + ",") != string::npos;
  }
  if (pat.size() > 1 && pat.back() == '*')
    return val.compare(0, pat.size() - 1, pat, 0, pat.size() - 1) == 0;
  return pat == val;
}

static bool known_match(const string& uid) {
  vector<string> f = uid_fields(uid);
  if (f.size() < 3) return false;
  for (auto& k : g_known) {
    if (k[0] != f[0]) continue;
    if (!known_field_hit(k[1], f[1])) continue;
    if (!known_field_hit(k[2], f[2], true)) continue;        // CONSTRUCTS: a token set
    if (!known_field_hit(k[3], f.size() > 3 ? f[3] : string())) continue;
    return true;
  }
  return false;
}

// An error pair, an affected-count pair or an access-type swap says how the two sides
// differ. These words name neither side, so two findings sharing one of them share nothing.
static bool mech_names_both_sides(const string& mech) {
  for (const char* g : {"content", "bytes", "coltype", "count", "oneside", "tables", "gone", "?"})
    if (mech == g) return false;
  return true;
}

// AFFECTED and a row-count RESULT carry a pair of counts, and the counts come from the data
// the statement met, so two sightings of one defect almost never carry the same pair. The
// count pair is read out here, and it is read for those two categories only: an ERROR
// mechanism is also a pair of numbers, but they are error codes and a code is an identity.
static bool mech_count_pair(const string& cat, const string& mech, long long& a, long long& b) {
  string s = mech;
  if (cat == "RESULT") {
    if (s.rfind("rows", 0) != 0) return false;
    s = s.substr(4);
  } else if (cat != "AFFECTED") return false;
  size_t v = s.find('v');
  if (v == string::npos || v == 0 || v + 1 >= s.size()) return false;
  string sa = s.substr(0, v), sb = s.substr(v + 1);
  if (sa.find_first_not_of("-0123456789") != string::npos ||
      sb.find_first_not_of("-0123456789") != string::npos) return false;
  a = atoll(sa.c_str());
  b = atoll(sb.c_str());
  return true;
}

// The mechanism of a muted entry against the mechanism of a finding. Two count pairs are
// the same mechanism when they say the same thing about the two sides: which one reported
// more, or that the two agreed. Everything else is compared as it is written.
static bool mech_near(const string& cat, const string& pat, const string& val) {
  long long pa, pb, va, vb;
  if (mech_count_pair(cat, pat, pa, pb) && mech_count_pair(cat, val, va, vb))
    return (pa < pb) == (va < vb) && (pa > pb) == (va > vb);
  return known_field_hit(pat, val);
}

// A finding that agrees with a muted entry on the category and the mechanism, where that
// entry names one statement and this is another, is very likely the same defect reached a
// different way. It is still reported, because the statement is a shape nobody has judged,
// and the report says which entry it sits beside so it can be filed against that ticket
// instead of as a new bug. An entry whose statement field is a wildcard cannot produce this,
// because it would have muted the finding outright, and neither can one whose mechanism
// field is a wildcard or names neither side.
static string known_near(const string& uid) {
  vector<string> f = uid_fields(uid);
  if (f.size() < 4) return {};
  for (auto& k : g_known) {
    if (k[3] == "*" || k[1] == "*" || k[0] != f[0]) continue;
    if (!mech_names_both_sides(k[1])) continue;
    if (!mech_near(f[0], k[1], f[1])) continue;
    if (known_field_hit(k[3], f[3])) continue;         // that one is muted, not near
    string out = k[0] + "|" + k[1] + "|" + k[2] + "|" + k[3];
    if (!k[4].empty()) out += " (" + k[4] + ")";
    return out;
  }
  return {};
}

static bool known_uid1(const string& h) {
  return !h.empty() && g_known_uid1.count(h) > 0;
}

static void enqueue_reduction(long cand, long trial, const string& uid, const DiffHit& hit,
                              const vector<StreamStmt>& stream);

// every confirmed diff funnels through here: artifacts, UID, known filter, dedup, reduction
// the combination the running trial gave side 2, so a finding carries it into its
// reduction and its report; one worker thread runs one trial at a time
static thread_local string t_combo;

static void handle_diff(long trial, int wid, const vector<StreamStmt>& stream, DiffHit hit,
                        const QOutcome& a, const QOutcome& b, vector<SideRun>& sides) {
  hit.combo = t_combo;
  int sidx = (hit.side_b >= 0 && hit.side_b < (int)sides.size())
               ? sides[hit.side_b].inst.spec->idx : 0;
  if (sidx > 0 && sidx < MAX_SIDE_STATS) g_side_diffs[sidx]++;
  string crash_log;
  if (hit.category == "CRASH") {
    for (auto& sr : sides)
      if (!sr.inst.alive()) { crash_log = sr.inst.errlog; break; }
  }
  string uid = uid_build(hit, a, b, crash_log);
  if (known_match(uid)) {
    g_known_matches++;
    logline("known diff muted: %s", uid.c_str());
    return;
  }
  if (string near = known_near(uid); !near.empty())
    logline("trial %ld: a muted entry is close to this one: %s", trial, near.c_str());
  long cand;
  {
    std::lock_guard<std::mutex> lk(g_uid_mtx);
    auto it = g_uids_seen.find(uid);
    if (it != g_uids_seen.end()) {
      g_dup_diffs++;
      append_seen("cand" + std::to_string(it->second), uid, trial);
      logline("duplicate diff (this run): %s", uid.c_str());
      return;
    }
    g_cands++;                                       // the trial number is the ID
    cand = trial;
    g_uids_seen[uid] = cand;
  }
  append_seen("cand" + std::to_string(cand), uid, trial);
  save_diff_artifacts(trial, wid, stream, hit, sides); // candidates only; muted/dup leave no files
  if (hit.category == "CRASH") {                     // secure the core before the revive
    string base = g_run.workdir + "/trial" + std::to_string(trial);
    for (auto& sr : sides) {
      if (sr.inst.alive()) continue;
      string core = newest_core_in(sr.inst.datadir);
      if (!core.empty())
        copy_core_sparse(core, base + "-side" + std::to_string(sr.inst.spec->idx) + ".core");
    }
  }
  logline("trial %ld: candidate (%s, UID %s)", cand, hit.category.c_str(), uid.c_str());
  enqueue_reduction(cand, trial, uid, hit, stream);
}

// Contention, deadlock and interruption: a server error whose cause is timing. Compared
// as a difference it is a false one, because the same statement on the same rows can meet
// it on one side and not on the other.
static bool timing_error(unsigned err) {
  return err == 1205 ||          // lock wait timeout
         err == 1213 ||          // deadlock
         err == 1317 ||          // query interrupted
         err == 1614 ||          // XA transaction rolled back on a timeout
         err == 1615 ||          // XA transaction rolled back on a deadlock
         err == 1969 ||          // statement time exceeded
         err == 3024;            // statement time exceeded, MySQL
}

// any side met one on the statement just run, so the outcomes are not comparable
static bool any_timing_error(Lockstep& ls) {
  for (auto& o : ls.outs)
    if (o.state == QState::ERR && timing_error(o.err)) return true;
  return false;
}

// checkpoint: SHOW TABLES + per-table content hash on every side via the lockstep barrier
static bool checkpoint_compare(Lockstep& ls, long trial, int wid, long after_idx,
                               const vector<StreamStmt>& stream, vector<SideRun>& sides) {
  ls.exec_all("SHOW TABLES", false, true);
  if (any_timing_error(ls)) { g_stats.timing_notes++; return true; }
  for (size_t i = 1; i < ls.outs.size(); i++) {
    if (ls.outs[0].row_count != ls.outs[i].row_count ||
        ls.outs[0].multiset_hash != ls.outs[i].multiset_hash) {
      DiffHit hit{"CHECKSUM", after_idx, "SHOW TABLES (checkpoint)", "", 0, (int)i};
      for (size_t k = 0; k < ls.outs.size(); k++)
        hit.detail += sides[k].inst.spec->label + ": " + outcome_brief(ls.outs[k]) + "\n";
      g_stats.diffs++;
      handle_diff(trial, wid, stream, hit, ls.outs[0], ls.outs[i], sides);
      return false;
    }
  }
  vector<string> tables = ls.outs[0].rows;
  std::sort(tables.begin(), tables.end());
  for (auto& t : tables) {
    if (g_stop.load()) return true;
    string q = "SELECT * FROM `" + t + "`";
    ls.exec_all(q, false, false);                    // hash-only scan, no row storage
    if (any_timing_error(ls)) { g_stats.timing_notes++; continue; }
    string cat;
    size_t diff_i = 1;
    for (size_t i = 1; i < ls.outs.size() && cat.empty(); i++) {
      cat = compare_pair(ls.outs[0], ls.outs[i], false);
      diff_i = i;
    }
    if (!cat.empty()) {
      DiffHit hit{"CHECKSUM", after_idx, "checkpoint content hash of `" + t + "`", "", 0, (int)diff_i};
      for (size_t k = 0; k < ls.outs.size(); k++)
        hit.detail += sides[k].inst.spec->label + ": " + outcome_brief(ls.outs[k]) + "\n";
      g_stats.diffs++;
      handle_diff(trial, wid, stream, hit, ls.outs[0], ls.outs[diff_i], sides);
      return false;
    }
  }
  // CHECKSUM TABLE EXTENDED is not used: its value is not stable across identical
  // replays on one server (boot-state dependent), so it cannot serve as an invariant
  return true;
}

// The trial's checkpoint reads every table, which leaves the buffer pool in the state the
// plan and the timing were measured in. A probe does the same reading, so both paths
// measure the same server. It is not a verdict here: detection already judged the content.
static void checkpoint_warm(Lockstep& ls) {
  ls.exec_all("SHOW TABLES", false, true);
  vector<string> tables = ls.outs[0].rows;
  std::sort(tables.begin(), tables.end());
  for (auto& t : tables) {
    if (g_stop.load()) return;
    ls.exec_all("SELECT * FROM `" + t + "`", false, false);
  }
}

static string upper_blanked(const string& s);

// the word appears at any paren depth, bounded by non-identifier characters
static bool contains_word(const string& up, const string& w) {
  auto idc = [](char c) { return isalnum((unsigned char)c) || c == '_' || c == '$'; };
  if (w.empty()) return false;
  for (size_t p = up.find(w); p != string::npos; p = up.find(w, p + 1)) {
    char b = p ? up[p - 1] : ' ';
    char a = p + w.size() < up.size() ? up[p + w.size()] : ' ';
    if (!idc(b) && !idc(a)) return true;
  }
  return false;
}

// A plan delta measured on data that is no longer the same on both sides is a data
// difference, not a plan difference. The tables the statement reads are compared before a
// PLAN candidate is accepted; the name returned is the first table that differs. The
// caller's ls.outs is overwritten, so it keeps its own copies.
static string first_unsynced_table(Lockstep& ls, const string& sql, size_t side_i) {
  ls.exec_all("SHOW TABLES", false, true);
  if (ls.outs[0].state == QState::ERR || any_timing_error(ls)) return "";
  vector<string> tabs = ls.outs[0].rows;
  string up = upper_blanked(sql);
  for (auto& t : tabs) {
    string tu = t;
    for (auto& ch : tu) ch = (char)toupper((unsigned char)ch);
    if (!contains_word(up, tu)) continue;
    ls.exec_all("SELECT * FROM `" + t + "`", false, false);
    if (any_timing_error(ls)) continue;
    if (side_i < ls.outs.size() && !compare_pair(ls.outs[0], ls.outs[side_i], false).empty())
      return t;
  }
  return "";
}

// Restart every side from a fresh datadir copy. The sides are independent, so they go
// together and the wall time is one restart rather than one per side. The old server is
// killed outright: its datadir is replaced next, so a clean shutdown would only flush a
// buffer pool into a directory that is about to be deleted.
static bool restart_sides_fresh(vector<SideRun>& sides) {
  for (auto& sr : sides) { sr.conn.close(); sr.ctl.close(); }
  vector<char> ok(sides.size(), 0);
  vector<std::thread> th;
  for (size_t i = 0; i < sides.size(); i++)
    th.emplace_back([&sides, &ok, i] {
      MysqlThreadScope mts;                            // start_fresh connects to probe
      sides[i].inst.stop(true);
      ok[i] = sides[i].inst.start_fresh(sides[i].tpl) ? 1 : 0;
    });
  for (auto& t : th) t.join();
  bool all = true;
  for (size_t i = 0; i < sides.size(); i++) all = all && ok[i] && sides[i].reconnect_all();
  return all;
}

// revive a crashed side between trials; false when it will not come back
static bool revive_side(SideRun& sr) {
  sr.inst.stop();
  if (++sr.revivals > 3) return false;
  if (!sr.inst.start_fresh(sr.tpl)) return false;
  return sr.reconnect_all();
}

// ---------------------------------------------------------------------------
// reduction: queued jobs, own 2-side instances per job, discovery continues
// ---------------------------------------------------------------------------
static void governor_wait(const string& what);

struct ReduceJob {
  long cand = 0;                   // candidate number, given at detection
  long bug = 0;                    // bug number, given when the replay confirms it
  long trial = 0;                  // source trial: crash artifacts fall back to its copies
  string uid;
  DiffHit hit;
  vector<StreamStmt> stream;       // tail-cut at capture: ends at the diffing statement
};
static std::mutex g_red_mtx;
static std::condition_variable g_red_cv;
static std::deque<ReduceJob> g_red_queue;
static std::atomic<bool> g_trials_out{false};          // no trial left to hand out

static void enqueue_reduction(long cand, long trial, const string& uid, const DiffHit& hit,
                              const vector<StreamStmt>& stream) {
  ReduceJob j;
  j.cand = cand;
  j.trial = trial;
  j.uid = uid;
  j.hit = hit;
  long end = std::min((long)stream.size() - 1, hit.stmt_index);
  j.stream.assign(stream.begin(), stream.begin() + end + 1);
  {
    // PLAN and PERF rest on row estimates and timing, which a fresh replay often does
    // not repeat, so they queue behind the categories that carry a hard outcome
    bool soft = j.hit.category == "PLAN" || j.hit.category == "PERF";
    std::lock_guard<std::mutex> lk(g_red_mtx);
    if (soft) g_red_queue.push_back(std::move(j));
    else
      g_red_queue.insert(std::find_if(g_red_queue.begin(), g_red_queue.end(),
                                      [](const ReduceJob& q) {
                                        return q.hit.category == "PLAN" ||
                                               q.hit.category == "PERF";
                                      }),
                         std::move(j));
  }
  g_red_cv.notify_one();
}

// the last error line of a server that did not come up, in the server's own words, so a
// sweep row states the reason instead of the bare fact
static string start_error_from_log(const string& errlog) {
  vector<string> ls = split(read_file(errlog), '\n');
  for (size_t i = ls.size(); i > 0; i--) {
    string l = trim(ls[i - 1]);
    size_t e = l.find("[ERROR]");
    if (e == string::npos) continue;
    string m = trim(l.substr(e + 7));
    while (m.size() > 1 && m[0] == '[') {            // [MY-010077] [Server] and the like
      size_t c = m.find(']');
      if (c == string::npos) break;
      m = trim(m.substr(c + 1));
    }
    if (m.empty() || m == "Aborting") continue;
    if (m.size() > 90) m = m.substr(0, 87) + "...";
    return m;
  }
  return {};
}

enum class Probe { REPRO, NO, INFRA };

struct Reducer {
  ReduceJob job;
  vector<SideRun> sides;           // [0]=reference side, [1]=diffing side
  std::unique_ptr<Lockstep> ls;
  double deadline = 0;
  bool is_checkpoint = false;      // CHECKSUM jobs reproduce via the end-state scan
  string base_ref, base_diff;      // baseline outcome briefs (STRICT_REDUCE pin)
  string repro_ref, repro_diff;    // briefs of the last reproduction
  string repro_mech;               // the mechanism the last reproduction measured
  vector<string> session_sets = session_setup_sql();  // reducible preamble SETs
  string out_ref, out_diff;        // captured .out text (filled on capture probes)
  string diff_table;               // CHECKSUM: the table the final replay differs on
  bool read_failed = false;        // ... and one side could not read it at all
  bool read_failed_ref = false;    // ... that side being the reference side
  // taken while this job's servers are still up, because the version sweep runs on their
  // slots and the report is written after it
  string ex_ref, ex_diff;          // the EXPLAIN of the last statement, per side
  int dead_side = -1;              // the side that died, or -1 if both were up
  string start_error;              // the server's own words when a side did not come up

  string root;                     // this reduction's /dev/shm working directory
  string dbname;                   // the trial's database name
  string perf_note;                // PERF: amplification summary for the report
  int perf_rounds = 0;             // ... over every amplification pass, for that summary
  string no_note;                  // why the last probe said NO (baseline drop diagnosis)
  string replay_diag;              // PLAN: the plans and row counts the last replay measured
  bool budget_spent = false;       // the deadline passed: the probe measured nothing
  int attempts_used = 0;           // passes the last reproduction check needed
  int inner_attempts = 1;          // passes each reduction step gets
  // a 1064 depends on the statement text, not on the server state, so one PREPARE per
  // text answers for the whole reduction instead of two round trips per probe
  std::map<string, bool> parse_skip;
  string stage;                    // what the panel says this job is doing
  long red_trial = 0;              // replays this reduction has run

  long stage_lines = 0;            // the count the panel shows, kept for the log

  // the panel line for this job; lines < 0 keeps the count it already shows. A change of
  // pass is logged as well, with the replays spent so far, so a long reduction can be read
  // from the log alone.
  // A stage after the reduction is finished. The job leaves the reducing set, so the
  // panel's count and its average testcase size cover the same jobs, and the stage names
  // itself on every slot it holds.
  void stage_done(const string& s) {
    if (!s.empty() && s != stage) logline("trial %ld: %s", job.cand, s.c_str());
    stage = s;
    set_red_status(job.cand, "", -1);
    slot_text_all(s);
  }
  void stage_set(const string& s, long lines) {
    if (lines >= 0) stage_lines = lines;
    if (!s.empty() && s != stage)
      logline("trial %ld: %s (%ld statements, %ld replays so far)", job.cand, s.c_str(),
              stage_lines, red_trial);
    stage = s;
    set_red_status(job.cand, s, lines, red_trial);
  }

  bool setup_at(SideSpec* ref_sp, SideSpec* diff_sp, const string& root_) {
    root = root_;
    dbname = trial_db(job.trial);      // the trial's own database, so a replay matches it
    SideSpec* sps[2] = {ref_sp, diff_sp};
    sides.resize(2);
    for (int i = 0; i < 2; i++) {
      sides[i].tpl = template_for(*sps[i]);
      sides[i].inst.spec = sps[i];
      sides[i].inst.set_paths(root + "/side" + std::to_string(sps[i]->idx));
      if (!sides[i].inst.start_fresh(sides[i].tpl)) {
        start_error = start_error_from_log(sides[i].inst.errlog);
        if (start_error.empty()) start_error = sides[i].inst.start_note;
        logline("trial %ld: side%d failed to start under %s%s%s", job.cand, sps[i]->idx,
                root.c_str(), start_error.empty() ? "" : " - ", start_error.c_str());
        return false;
      }
      // a server that is up but takes no session is a different failure, and its reason is
      // on the client side, so the server log has nothing to say about it
      if (!sides[i].reconnect_all()) {
        start_error = "no connection" +
                      (sides[i].connect_error.empty() ? string()
                                                      : " - " + sides[i].connect_error);
        logline("trial %ld: side%d started but took no connection under %s%s%s", job.cand,
                sps[i]->idx, root.c_str(), sides[i].connect_error.empty() ? "" : " - ",
                sides[i].connect_error.c_str());
        return false;
      }
    }
    ls = std::make_unique<Lockstep>(sides);
    is_checkpoint = job.hit.category == "CHECKSUM";
    return true;
  }
  bool setup() {
    int diff_pos = (job.hit.side_b > 0 && job.hit.side_b < (int)g_sides.size()) ? job.hit.side_b : 1;
    return setup_at(&g_sides[0], &g_sides[diff_pos],
                    g_run.rundir + "/red" + std::to_string(job.cand));
  }
  // the error log and any core stay on disk, so the report can still be written
  void stop_servers() {
    ls.reset();
    for (auto& sr : sides) { sr.conn.close(); sr.ctl.close(); sr.inst.stop(); }
  }
  // What the report still wants is the error log and, on a crash, the core. The rest of
  // the datadir is the largest thing a job holds, and a confirmed bug can wait a long
  // while for its version sweep, so it goes now rather than at teardown
  void shed_data() {
    std::error_code ec;
    for (auto& sr : sides) {
      fs::remove_all(sr.inst.tmpdir, ec);
      vector<fs::path> drop;                          // listed first: the walk is over the
      for (auto& de : fs::directory_iterator(sr.inst.datadir, ec))   // same directory
        if (de.path().filename().string().rfind("core", 0) != 0) drop.push_back(de.path());
      for (auto& d : drop) fs::remove_all(d, ec);
    }
  }
  void teardown() {
    stop_servers();
    if (!root.empty()) {
      std::error_code ec;
      fs::remove_all(root, ec);
    }
  }
  bool restart_dead() {
    for (auto& sr : sides) {
      if (!sr.inst.alive()) {
        sr.inst.stop();
        if (!sr.inst.start_fresh(sr.tpl) || !sr.reconnect_all()) return false;
      }
    }
    return true;
  }
  // Every replay starts from a fresh datadir. A server that has already run the candidate
  // carries physical state (statistics, page reuse, purge lag) that the next replay would
  // otherwise inherit, so what a probe accepts is what the final replay and the report see.
  bool fresh_reset() {
    if (!restart_sides_fresh(sides)) return false;
    return oob_reset();
  }
  // session SETs and an empty trial database, so preamble lines can be trimmed
  bool oob_reset() {
    vector<string> pre = {"ROLLBACK"};
    for (auto& s : session_sets) pre.push_back(s);
    pre.push_back("DROP DATABASE IF EXISTS " + dbname);
    pre.push_back("CREATE DATABASE " + dbname + " CHARACTER SET " + g_cfg.charset + " COLLATE " + g_cfg.collation);
    pre.push_back("USE " + dbname);
    for (auto& sr : sides)
      for (auto& q : pre) {
        if (!sr.conn.h) return false;
        if (mysql_real_query(sr.conn.h, q.c_str(), q.size()) != 0) {
          unsigned e = mysql_errno(sr.conn.h);
          if (e == 2006 || e == 2013) return false;
        }
      }
    // combinatorics: side 2 alone carries the combination, after the settings above
    if (!job.hit.combo.empty() && sides.size() > 1) {
      if (!sides[1].conn.h) return false;
      string q = "SET SESSION optimizer_switch='" + job.hit.combo + "'";
      if (mysql_real_query(sides[1].conn.h, q.c_str(), q.size()) != 0) {
        unsigned e = mysql_errno(sides[1].conn.h);
        if (e == 2006 || e == 2013) return false;
      }
    }
    return true;
  }
  // replay a candidate; REPRO when the pinned diff is back. capture fills out_ref/out_diff.
  // errmap (sized to cand) records which statements returned an error, for the error-drop pass.
  // the reproduction rule used at both drop gates: a diff that needs a background thread
  // to catch up shows on a later pass, so a single quiet pass is not a verdict
  // A reduction step asks "does it still reproduce without these lines?". On a diff that
  // needs several passes to show, one quiet pass is not an answer, so a step gets as many
  // passes as the trial replay needed. A diff that came back first time keeps one pass.
  Probe probe_try(const vector<StreamStmt>& cand) {
    Probe p = Probe::NO;
    for (int i = 0; i < std::max(1, inner_attempts); i++) {
      p = probe(cand);
      if (p != Probe::NO || budget_spent || g_stop.load()) break;
    }
    return p;
  }
  // A pass gets a share of what is left of the budget. Without this, one bulk INSERT's
  // tuples can spend everything the later passes need: the seed writes 200 rows per
  // statement, and chunk-halving those costs about 400 replays for that one statement.
  double pass_end(double share) const {
    double left = deadline - now_ms();
    return now_ms() + (left > 0 ? left * share : 0.0);
  }
  // a pause stops a reduction between replays, and the waiting time is given back to
  // the reduce budget so a pause never costs the reduction its time
  void pause_hold() {
    if (!g_pause.load() || g_stop.load()) return;
    double t0 = now_ms();
    set_red_status(job.cand, "paused", -1, red_trial);
    while (g_pause.load() && !g_stop.load()) usleep(200000);
    deadline += now_ms() - t0;
  }
  Probe probe_repeat(const vector<StreamStmt>& cand, bool capture = false,
                     vector<uint8_t>* errmap = nullptr) {
    int lim = std::max(1, g_cfg.max_sporadic_attempts);
    Probe p = Probe::NO;
    for (attempts_used = 1; attempts_used <= lim; attempts_used++) {
      p = probe(cand, capture, errmap);
      if (p != Probe::NO || budget_spent || g_stop.load()) break;
    }
    if (attempts_used > lim) attempts_used = lim;
    return p;
  }
  Probe probe(const vector<StreamStmt>& cand, bool capture = false,
              vector<uint8_t>* errmap = nullptr) {
    pause_hold();
    if (!stage.empty()) set_red_status(job.cand, stage, -1, ++red_trial);
    if (!fresh_reset()) {
      bool re = true;
      for (auto& sr : sides) re = re && sr.reconnect_all();
      if (!re || !oob_reset()) return Probe::INFRA;
    }
    if (capture) { out_ref.clear(); out_diff.clear(); }
    no_note.clear();
    bool tx_open = false;              // the replay opened a transaction and has not closed it
    for (size_t k = 0; k < cand.size(); k++) {
      // out of time or stopping: the probe measured nothing, so say so instead of
      // letting the caller read it as a diff that did not come back
      if (g_stop.load()) { no_note = "the run stopped mid-replay"; return Probe::NO; }
      if (now_ms() > deadline) {
        budget_spent = true;
        no_note = "the reduce budget was spent";
        return Probe::NO;
      }
      const string& sql = cand[k].sql;
      bool pinned = !is_checkpoint && k + 1 == cand.size();
      if (g_cfg.skip_parse_errors) {
        auto it = parse_skip.find(sql);
        if (it == parse_skip.end()) {
          bool skip = false;
          for (auto& sr : sides)
            if (prepare_check(sr.conn, sql) == 1064) { skip = true; break; }
          it = parse_skip.emplace(sql, skip).first;
        }
        if (it->second) continue;
      }
      ls->exec_all(sql, warning_mode() >= 1 || capture, true);
      if (stmt_opens_tx(sql)) tx_open = true;
      else if (stmt_ends_tx(sql)) tx_open = false;
      for (int i = 0; i < 2; i++) {                    // client-side break, server alive
        if (ls->outs[i].state == QState::CRASH && sides[i].inst.alive()) {
          if (sides[i].reconnect_all()) {
            for (auto& s : session_sets) mysql_real_query(sides[i].conn.h, s.c_str(), s.size());
            string ut = "USE " + dbname;
            mysql_real_query(sides[i].conn.h, ut.c_str(), ut.size());
            // combinatorics: the combination is a session setting, so it goes with the
            // session that broke. Without it side 2 replays on the default switch while
            // the report and the testcase still name the combination.
            if (i == 1 && !job.hit.combo.empty()) {
              string cq = "SET SESSION optimizer_switch='" + job.hit.combo + "'";
              mysql_real_query(sides[i].conn.h, cq.c_str(), cq.size());
            }
          }
          ls->outs[i].state = QState::ERR;
        }
      }
      if (errmap && k < errmap->size())
        (*errmap)[k] = (ls->outs[0].state == QState::ERR) ? 1 : 0;
      if (capture) {
        char pfx[32];
        snprintf(pfx, sizeof(pfx), "%zu| ", k + 1);
        out_ref += pfx + outcome_brief(ls->outs[0]) + "\n";
        out_diff += pfx + outcome_brief(ls->outs[1]) + "\n";
        if (pinned) {
          for (size_t r = 0; r < ls->outs[0].rows.size() && r < 200; r++)
            out_ref += string(pfx) + "row| " + ls->outs[0].rows[r] + "\n";
          for (size_t r = 0; r < ls->outs[1].rows.size() && r < 200; r++)
            out_diff += string(pfx) + "row| " + ls->outs[1].rows[r] + "\n";
        }
      }
      if (ls->outs[0].state == QState::TIMEOUT && ls->outs[1].state == QState::TIMEOUT) continue;
      // contention or a time limit on one side: nothing was measured on this statement
      if (any_timing_error(*ls)) {
        if (!pinned) continue;
        no_note = "a side met contention or a time limit on the pinned statement";
        return Probe::NO;
      }
      string cat = compare_pair(ls->outs[0], ls->outs[1], cand[k].state_only, cand[k].sql);
      // detection counts a warning-only delta as a note, not a bug: so does the probe,
      // or the probe rejects a replay on the one class detection was told to ignore
      if (cat == "WARNING" && !g_cfg.warnings_as_bug) cat.clear();
      // the same for a tie under one top-level LIMIT, settled the same way detection
      // settles it, so both judge the same phenomenon
      if (cat == "RESULT" && stmt_limit_ordered(cand[k].sql) && ls->outs[0].cols &&
          !ls->outs[0].capped && !ls->outs[1].capped &&
          ls->outs[0].row_count == ls->outs[1].row_count) {
        string tb = order_by_total(cand[k].sql, ls->outs[0].cols);
        if (!tb.empty() && ls->outs[0].rows.size() <= 10000) {
          auto ra = query_rows(sides[0].conn, tb);
          auto rb = query_rows(sides[1].conn, tb);
          if (!ra.empty() && ra == rb) cat.clear();
        }
      }
      if (!cat.empty()) {
        if (!pinned || cat != job.hit.category) {      // a different bug
          no_note = cat + " diff at line " + std::to_string(k + 1);
          return Probe::NO;
        }
        string br = outcome_brief(ls->outs[0]), bd = outcome_brief(ls->outs[1]);
        if (g_cfg.strict_reduce && !base_ref.empty() && (br != base_ref || bd != base_diff))
          return Probe::NO;
        repro_ref = br;
        repro_diff = bd;
        if (mech_is_remeasurable(cat))
          repro_mech = outcome_mech(cat, ls->outs[0], ls->outs[1], cand[k].sql, "",
                                    job.hit.mech);
        return Probe::REPRO;
      }
      // PLAN/PERF: the outcomes match by design - re-detect on the pinned statement
      if (pinned && job.hit.category == "PLAN") {
        // detection never reads a plan inside an open transaction, because the refresh it
        // needs would commit one. A reduction that drops the COMMIT puts the pinned
        // statement inside one, and this says so, so that line is kept.
        if (tx_open) {
          no_note = "the pinned statement sits inside an open transaction, where a plan "
                    "read would commit it";
          return Probe::NO;
        }
        // the same gates as detection, so both judge the same phenomenon: a plan measured
        // on data that has diverged is a data difference, and a plan whose shape moved is
        // a different plan, not a worse one
        string unsynced = first_unsynced_table(*ls, sql, 1);
        if (!unsynced.empty()) {
          no_note = "table `" + unsynced + "` no longer holds the same rows on both sides";
          return Probe::NO;
        }
        PlanInfo a, b;
        bool cross = sides[0].inst.spec->basedir != sides[1].inst.spec->basedir;
        double factor = cross ? g_cfg.plan_factor_cross : g_cfg.plan_factor;
        if (!plan_delta_holds(sides[0].conn, sides[1].conn, sides[0].inst.spec,
                              sides[1].inst.spec, sql, factor, a, b, &no_note)) {
          replay_diag = plan_diag(sides[0].conn, sides[1].conn, sql,
                                  sides[0].inst.spec->label, sides[1].inst.spec->label);
          return Probe::NO;
        }
        if (a.lines != b.lines || a.tables != b.tables) {
          no_note = "the plan shape moved: " + std::to_string(a.lines) + " against " +
                    std::to_string(b.lines) + " EXPLAIN rows";
          return Probe::NO;
        }
        // the same notion of "worse" detection used: the scanning side on a swap, the
        // larger estimate otherwise
        bool a_worse = (plans_line_up(a, b) && access_scan_swap(a.access, b.access))
                           ? !scan_side_is_b(a.access, b.access)
                           : a.rows_product > b.rows_product;
        if (a_worse != job.hit.ref_worse) {
          no_note = "plan direction flipped";          // the regression direction gate
          return Probe::NO;
        }
        repro_mech = plan_mech_of(a, b);
        char pb[128];
        snprintf(pb, sizeof(pb), "plan rows-product %.0f access %s", a.rows_product, a.access.c_str());
        repro_ref = pb;
        snprintf(pb, sizeof(pb), "plan rows-product %.0f access %s", b.rows_product, b.access.c_str());
        repro_diff = pb;
        return Probe::REPRO;
      }
      if (pinned && job.hit.category == "PERF") {
        double m0 = perf_median5(sides[0].conn, sql), m1 = perf_median5(sides[1].conn, sql);
        if (m0 < 0 || m1 < 0 || !perf_exceeds(std::min(m0, m1), std::max(m0, m1))) {
          char nb[96];
          snprintf(nb, sizeof(nb), "medians %.1f vs %.1f ms, under the thresholds", m0, m1);
          no_note = nb;
          return Probe::NO;
        }
        if ((m0 > m1) != job.hit.ref_worse) {
          no_note = "perf direction flipped";          // the regression direction gate
          return Probe::NO;
        }
        char pb[96];
        snprintf(pb, sizeof(pb), "median %.1f ms (5 serial runs)", m0);
        repro_ref = pb;
        snprintf(pb, sizeof(pb), "median %.1f ms (5 serial runs)", m1);
        repro_diff = pb;
        return Probe::REPRO;
      }
      if (pinned) {                                    // pinned statement no longer diffs
        no_note = "the pinned statement no longer diffs";
        return Probe::NO;
      }
      if (cand[k].checkpoint) checkpoint_warm(*ls);     // the trial's own checkpoint work
    }
    if (!is_checkpoint) {
      if (no_note.empty()) no_note = "the pinned statement was skipped (parse or timeout)";
      return Probe::NO;
    }
    // CHECKSUM: end-state scan, same shape as the discovery checkpoint
    ls->exec_all("SHOW TABLES", false, true);
    if (any_timing_error(*ls)) {                       // this pass measured nothing
      no_note = "a side met contention or a time limit while reading the tables";
      return Probe::NO;
    }
    string cat = compare_pair(ls->outs[0], ls->outs[1], false);
    if (!cat.empty()) {
      repro_ref = outcome_brief(ls->outs[0]);
      repro_diff = outcome_brief(ls->outs[1]);
      if (capture) { out_ref += "tables| " + repro_ref + "\n"; out_diff += "tables| " + repro_diff + "\n"; }
      return Probe::REPRO;
    }
    vector<string> tables = ls->outs[0].rows;
    std::sort(tables.begin(), tables.end());
    bool found = false;
    for (auto& t : tables) {
      ls->exec_all("SELECT * FROM `" + t + "`", false, false);
      if (any_timing_error(*ls)) continue;              // that table was not read on a side
      string c2 = compare_pair(ls->outs[0], ls->outs[1], false);
      if (capture) {
        out_ref += "table " + t + "| " + outcome_brief(ls->outs[0]) + "\n";
        out_diff += "table " + t + "| " + outcome_brief(ls->outs[1]) + "\n";
      }
      if (!c2.empty() && !found) {
        repro_ref = outcome_brief(ls->outs[0]);
        repro_diff = outcome_brief(ls->outs[1]);
        found = true;
        if (!capture) return Probe::REPRO;
      }
    }
    return found ? Probe::REPRO : Probe::NO;
  }
};

// One probe can take most of a trial away: keep only the statements that name a table the
// pinned statement uses. A statement naming no table is kept, so settings stay. The strict
// set is tried first, then one grown by the tables those statements bring in.
static std::set<string> table_names_of(const string& sql) {
  std::set<string> out;
  string up = upper(sql);
  for (size_t i = 0; i < up.size();) {
    if (up[i] != 'T' || (i && (isalnum((unsigned char)up[i - 1]) || up[i - 1] == '_'))) { i++; continue; }
    size_t j = i + 1;
    while (j < up.size() && isdigit((unsigned char)up[j])) j++;
    if (j > i + 1 && (j == up.size() || !(isalnum((unsigned char)up[j]) || up[j] == '_')))
      out.insert(up.substr(i, j - i));
    i = j > i ? j : i + 1;
  }
  return out;
}

static void reduce_table_slice(Reducer& rd, vector<StreamStmt>& lines) {
  if (rd.is_checkpoint || lines.size() < 8) return;
  std::set<string> keep = table_names_of(lines.back().sql);
  if (keep.empty()) return;
  // a statement that only shapes a table, as against one that puts rows in it
  auto structural = [](const string& sql) {
    return starts_with_i(sql, "CREATE") || starts_with_i(sql, "ALTER") ||
           starts_with_i(sql, "DROP") || starts_with_i(sql, "RENAME") ||
           starts_with_i(sql, "TRUNCATE") || starts_with_i(sql, "SET") ||
           starts_with_i(sql, "ANALYZE") || starts_with_i(sql, "USE");
  };
  // three shapes, strictest first, one probe each. The pinned statement always stays.
  //   0  only what names a table the pinned statement uses, plus what names none
  //   1  the same, plus the structure of every other table, without its rows
  //   2  the same as 0 over the grown table set: the tables shape 0 brought in
  for (int shape = 0; shape < 3 && !g_stop.load() && now_ms() <= rd.deadline; shape++) {
    vector<StreamStmt> cand;
    std::set<string> grown = keep;
    for (size_t i = 0; i + 1 < lines.size(); i++) {
      std::set<string> t = table_names_of(lines[i].sql);
      bool touch = t.empty();
      for (auto& nm : t) if (keep.count(nm)) { touch = true; break; }
      if (!touch && shape == 1) touch = structural(lines[i].sql);
      if (touch) { cand.push_back(lines[i]); grown.insert(t.begin(), t.end()); }
    }
    cand.push_back(lines.back());
    if (cand.size() < lines.size()) {
      rd.stage_set("table slice", (long)lines.size());
      if (rd.probe_try(cand) == Probe::REPRO) {
        lines = std::move(cand);
        rd.stage_set("table slice", (long)lines.size());
        return;
      }
    }
    if (shape == 2 || (shape == 1 && grown.size() == keep.size())) return;
    if (shape == 1) keep = std::move(grown);           // shape 2 works on the grown set
  }
}

// chunk elimination to a single-line fixpoint; the pinned last statement never moves
static void reduce_lines(Reducer& rd, vector<StreamStmt>& lines) {
  rd.stage_set("reduce chunks", (long)lines.size());
  double end = rd.pass_end(0.6);                   // the rest is kept for the data passes
  size_t removable = lines.size() - (rd.is_checkpoint ? 0 : 1);
  size_t chunk = std::max<size_t>(1, removable / 2);
  int infra = 0;
  for (;;) {
    if (g_stop.load() || now_ms() > end) return;
    bool removed = false;
    for (size_t start = 0; start + (rd.is_checkpoint ? 0 : 1) < lines.size() && start < lines.size();) {
      if (g_stop.load() || now_ms() > end) return;
      size_t rem_end = std::min(start + chunk, lines.size() - (rd.is_checkpoint ? 0 : 1));
      if (rem_end <= start) break;
      vector<StreamStmt> cand;
      cand.reserve(lines.size());
      for (size_t i = 0; i < lines.size(); i++)
        if (i < start || i >= rem_end) cand.push_back(lines[i]);
      Probe p = rd.probe_try(cand);
      if (p == Probe::INFRA && ++infra >= 3) return;
      if (p == Probe::REPRO) {
        lines = std::move(cand);
        removed = true;
        infra = 0;
        rd.stage_set("reduce chunks", (long)lines.size());     // the panel follows it down
      } else {
        start += chunk;
      }
    }
    if (chunk == 1) { if (!removed) return; }
    else chunk = std::max<size_t>(1, chunk / 2);
  }
}

// --- data and column brevity helpers (quote- and paren-aware) ---
static vector<string> split_top_level(const string& s) {
  vector<string> out;
  int depth = 0;
  size_t st = 0, i = 0;
  while (i < s.size()) {
    char c = s[i];
    if (c == '\'' || c == '"' || c == '`') { i = skip_quoted(s, i); continue; }
    if (c == '(') depth++;
    else if (c == ')') depth--;
    else if (c == ',' && depth == 0) { out.push_back(s.substr(st, i - st)); st = i + 1; }
    i++;
  }
  out.push_back(s.substr(st));
  return out;
}

static string join_list(const vector<string>& v, const string& sep) {
  string out;
  for (size_t i = 0; i < v.size(); i++) { if (i) out += sep; out += v[i]; }
  return out;
}

static string trim_ws(const string& s) {
  size_t a = s.find_first_not_of(" \t");
  if (a == string::npos) return "";
  size_t b = s.find_last_not_of(" \t");
  return s.substr(a, b - a + 1);
}

// uppercase copy with quoted regions blanked, for keyword position searches
static string upper_blanked(const string& s) {
  string up;
  up.reserve(s.size());
  for (size_t i = 0; i < s.size();) {
    char c = s[i];
    if (c == '\'' || c == '"' || c == '`') {
      size_t j = skip_quoted(s, i);
      up.append(j - i, ' ');
      i = j;
      continue;
    }
    up += (char)toupper((unsigned char)c);
    i++;
  }
  return up;
}

// first occurrence of word at paren depth 0 (in an upper_blanked copy)
static size_t find_word_top(const string& up, const string& word, size_t from = 0) {
  int depth = 0;
  for (size_t i = from; i < up.size(); i++) {
    char c = up[i];
    if (c == '(') depth++;
    else if (c == ')') depth--;
    else if (depth == 0 && c == word[0] && up.compare(i, word.size(), word) == 0 &&
             (i == 0 || !ident_ch(up[i - 1])) &&
             (i + word.size() >= up.size() || !ident_ch(up[i + word.size()])))
      return i;
  }
  return string::npos;
}

static string strip_ticks(string t) {
  t = trim(t);
  if (t.size() >= 2 && t.front() == '`' && t.back() == '`') t = t.substr(1, t.size() - 2);
  return t;
}

// INSERT/REPLACE [INTO] t [(cols)] VALUES ...: table name, column-list presence,
// and the position right after the VALUES keyword
static bool parse_insert_values(const string& s, const string& up, string& tname,
                                bool& has_collist, size_t& vend) {
  if (up.rfind("INSERT", 0) != 0 && up.rfind("REPLACE", 0) != 0) return false;
  size_t v = find_word_top(up, "VALUES");
  if (v == string::npos) return false;
  size_t p = find_word_top(up, "INTO");
  p = (p == string::npos) ? (up[0] == 'I' ? 6 : 7) : p + 4;
  while (p < s.size() && isspace((unsigned char)s[p])) p++;
  size_t q = p;
  if (q < s.size() && s[q] == '`') q = skip_quoted(s, q);
  else while (q < s.size() && ident_ch(s[q])) q++;
  tname = strip_ticks(s.substr(p, q - p));
  has_collist = false;
  for (size_t i = q; i < v; i++) if (up[i] == '(') { has_collist = true; break; }
  vend = v + 6;
  return !tname.empty() && vend < s.size();
}

// CREATE TABLE [IF NOT EXISTS] t ( <defs> ) ...: name + the def-list span [bs,be)
static bool parse_create_table(const string& s, const string& up, string& tname,
                               size_t& bs, size_t& be) {
  size_t p = 0;
  if (up.rfind("CREATE TABLE", 0) == 0) p = 12;
  else if (up.rfind("CREATE OR REPLACE TABLE", 0) == 0) p = 23;
  else return false;
  while (p < s.size() && isspace((unsigned char)s[p])) p++;
  if (up.compare(p, 13, "IF NOT EXISTS") == 0) p += 13;
  while (p < s.size() && isspace((unsigned char)s[p])) p++;
  size_t q = p;
  if (q < s.size() && s[q] == '`') q = skip_quoted(s, q);
  else while (q < s.size() && ident_ch(s[q])) q++;
  tname = strip_ticks(s.substr(p, q - p));
  while (q < s.size() && isspace((unsigned char)s[q])) q++;
  if (q >= s.size() || s[q] != '(') return false;      // AS SELECT / LIKE form
  bs = q + 1;
  int depth = 1;
  size_t i = bs;
  while (i < s.size() && depth) {
    char c = s[i];
    if (c == '\'' || c == '"' || c == '`') { i = skip_quoted(s, i); continue; }
    if (c == '(') depth++;
    if (c == ')') depth--;
    i++;
  }
  if (depth) return false;
  be = i - 1;
  return !tname.empty();
}

static bool is_key_def(const string& def) {
  string w = upper(trim(def));
  static const char* kws[] = {"PRIMARY", "UNIQUE", "KEY", "INDEX", "CONSTRAINT", "FOREIGN",
                              "FULLTEXT", "SPATIAL", "CHECK", "PERIOD", "VECTOR"};
  for (auto* k : kws)
    if (w.rfind(k, 0) == 0 && (w.size() == strlen(k) || !ident_ch(w[strlen(k)]))) return true;
  return false;
}

// remove element k from a "(a,b,c)" tuple; a tuple without element k stays as-is
static bool tuple_drop_elem(string& tup, size_t k) {
  string t = trim(tup);
  if (t.size() < 2 || t.front() != '(' || t.back() != ')') return false;
  vector<string> el = split_top_level(t.substr(1, t.size() - 2));
  if (k < el.size()) {
    el.erase(el.begin() + k);
    tup = "(" + join_list(el, ",") + ")";
  }
  return true;
}

// data brevity: drop excess tuples from multi-row INSERT/REPLACE VALUES lists
static void reduce_insert_rows(Reducer& rd, vector<StreamStmt>& lines) {
  constexpr size_t ROW_TAIL_MAX = 24;                 // rows the chunk pass may still cut
  rd.stage_set("reduce rows", (long)lines.size());
  double end = rd.pass_end(0.25);
  int infra = 0;
  for (size_t li = 0; li < lines.size(); li++) {
    if (g_stop.load() || now_ms() > end) return;
    string tname;
    bool cl;
    size_t vend;
    if (!parse_insert_values(lines[li].sql, upper_blanked(lines[li].sql), tname, cl, vend)) continue;
    string head = lines[li].sql.substr(0, vend);
    vector<string> tup = split_top_level(lines[li].sql.substr(vend));
    if (tup.size() < 2) continue;
    // a row list is homogeneous, so the shortest reproducing prefix is found by doubling
    // and then bisecting: about 2*log2(n) replays, where cutting chunk by chunk costs 2n
    auto try_prefix = [&](size_t k) -> bool {
      vector<string> keep(tup.begin(), tup.begin() + k);
      vector<StreamStmt> cand = lines;
      cand[li].sql = head + join_list(keep, ",");
      Probe p = rd.probe_try(cand);
      if (p == Probe::INFRA) infra++;
      if (p != Probe::REPRO) return false;
      lines = std::move(cand);
      tup = std::move(keep);
      infra = 0;
      return true;
    };
    size_t n = tup.size(), lo = 0, hi = 0;             // lo does not reproduce, hi does
    for (size_t k = 1; k < n; k *= 2) {
      if (g_stop.load() || now_ms() > end || infra >= 3) return;
      if (try_prefix(k)) { hi = k; break; }
      lo = k;
    }
    while (hi > lo + 1) {
      if (g_stop.load() || now_ms() > end || infra >= 3) return;
      size_t mid = lo + (hi - lo) / 2;
      if (try_prefix(mid)) hi = mid; else lo = mid;
    }
    // cut chunk by chunk over what is left, which drops a row the prefix kept. Only over
    // a short list: on a long one it costs two replays a row for very little
    if (tup.size() < 2 || tup.size() > ROW_TAIL_MAX) continue;
    size_t chunk = std::max<size_t>(1, tup.size() / 2);
    for (;;) {
      if (g_stop.load() || now_ms() > end) return;
      bool removed = false;
      for (size_t st = 0; st < tup.size() && tup.size() > 1;) {
        if (g_stop.load() || now_ms() > end) return;
        size_t re = std::min(st + chunk, tup.size());
        if (re - st >= tup.size()) re = tup.size() - 1;         // keep one tuple
        if (re <= st) break;
        vector<string> keep;
        for (size_t i = 0; i < tup.size(); i++)
          if (i < st || i >= re) keep.push_back(tup[i]);
        vector<StreamStmt> cand = lines;
        cand[li].sql = head + join_list(keep, ",");
        Probe p = rd.probe_try(cand);
        if (p == Probe::INFRA && ++infra >= 3) return;
        if (p == Probe::REPRO) {
          lines = std::move(cand);
          tup = std::move(keep);
          removed = true;
          infra = 0;
        } else {
          st += chunk;
        }
      }
      if (chunk == 1) { if (!removed) break; }
      else chunk = std::max<size_t>(1, chunk / 2);
    }
  }
}

// column brevity: drop CREATE TABLE defs one at a time (backward); dropping a data
// column also drops the matching element from every no-column-list INSERT into
// that table. The probe validates every candidate, so load-bearing columns stay.
static void reduce_columns(Reducer& rd, vector<StreamStmt>& lines) {
  rd.stage_set("reduce cols", (long)lines.size());
  double end = rd.pass_end(0.25);
  int infra = 0;
  for (size_t ci = 0; ci < lines.size(); ci++) {
    string tname;
    size_t bs, be;
    if (!parse_create_table(lines[ci].sql, upper_blanked(lines[ci].sql), tname, bs, be)) continue;
    size_t k = split_top_level(lines[ci].sql.substr(bs, be - bs)).size();
    while (k-- > 0) {
      if (g_stop.load() || now_ms() > end) return;
      size_t bs2, be2;
      string tn2;
      if (!parse_create_table(lines[ci].sql, upper_blanked(lines[ci].sql), tn2, bs2, be2)) break;
      vector<string> defs = split_top_level(lines[ci].sql.substr(bs2, be2 - bs2));
      if (defs.size() <= 1 || k >= defs.size()) continue;
      bool keydef = is_key_def(defs[k]);
      size_t colpos = 0;
      for (size_t i = 0; i < k; i++)
        if (!is_key_def(defs[i])) colpos++;
      vector<string> keep;
      for (size_t i = 0; i < defs.size(); i++)
        if (i != k) keep.push_back(trim_ws(defs[i]));
      vector<StreamStmt> cand = lines;
      cand[ci].sql = lines[ci].sql.substr(0, bs2) + join_list(keep, ", ") + lines[ci].sql.substr(be2);
      bool ok = true;
      if (!keydef) {
        for (size_t j = 0; j < cand.size() && ok; j++) {
          if (j == ci) continue;
          string itn;
          bool cl;
          size_t vend;
          if (!parse_insert_values(cand[j].sql, upper_blanked(cand[j].sql), itn, cl, vend)) continue;
          if (itn != tname || cl) continue;
          vector<string> tups = split_top_level(cand[j].sql.substr(vend));
          for (auto& t : tups)
            if (!tuple_drop_elem(t, colpos)) { ok = false; break; }
          if (ok) cand[j].sql = cand[j].sql.substr(0, vend) + join_list(tups, ",");
        }
      }
      if (!ok) continue;
      Probe p = rd.probe_try(cand);
      if (p == Probe::INFRA && ++infra >= 3) return;
      if (p == Probe::REPRO) {
        lines = std::move(cand);
        infra = 0;
      }
    }
  }
}

// list brevity: ANALYZE/OPTIMIZE/CHECK/REPAIR TABLE name lists lose entries one at a
// time; the probe keeps a name only when it is load-bearing
static void reduce_table_lists(Reducer& rd, vector<StreamStmt>& lines) {
  rd.stage_set("reduce table", (long)lines.size());
  double end = rd.pass_end(0.15);
  int infra = 0;
  static const char* heads[] = {"ANALYZE TABLE ", "OPTIMIZE TABLE ", "CHECK TABLE ",
                                "REPAIR TABLE "};
  for (size_t li = 0; li < lines.size(); li++) {
    if (g_stop.load() || now_ms() > end) return;
    const char* hit = nullptr;
    for (auto* h : heads)
      if (starts_with_i(lines[li].sql, h)) { hit = h; break; }
    if (!hit) continue;
    size_t hl = string(hit).size();
    vector<string> names = split(lines[li].sql.substr(hl), ',');
    if (names.size() < 2) continue;
    {                                   // the biggest cut first: one name, one replay
      vector<StreamStmt> cand = lines;
      cand[li].sql = hit + trim_ws(names[0]);
      if (rd.probe_try(cand) == Probe::REPRO) {
        lines = std::move(cand);
        continue;
      }
    }
    for (size_t n = names.size(); n-- > 0 && names.size() > 1;) {
      if (g_stop.load() || now_ms() > end) return;
      vector<string> keep;
      for (size_t i = 0; i < names.size(); i++)
        if (i != n) keep.push_back(trim_ws(names[i]));
      vector<StreamStmt> cand = lines;
      cand[li].sql = hit + join_list(keep, ", ");
      Probe p = rd.probe_try(cand);
      if (p == Probe::INFRA && ++infra >= 3) return;
      if (p == Probe::REPRO) {
        lines = std::move(cand);
        names = std::move(keep);
        infra = 0;
      }
    }
  }
}

// literal brevity: an extreme numeric literal (15+ digits) in INSERT/REPLACE values
// becomes 1 (or 1.1) when the probe holds. The row count never changes, so the
// PLAN/PERF row mass stays intact.
static void reduce_literals(Reducer& rd, vector<StreamStmt>& lines) {
  rd.stage_set("reduce literals", (long)lines.size());
  double end = rd.pass_end(0.15);
  int infra = 0;
  for (size_t li = 0; li < lines.size(); li++) {
    if (!starts_with_i(lines[li].sql, "INSERT") && !starts_with_i(lines[li].sql, "REPLACE"))
      continue;
    std::set<string> tried;
    for (;;) {
      if (g_stop.load() || now_ms() > end) return;
      string ub = upper_blanked(lines[li].sql);        // string literals blanked out
      const string& sq = lines[li].sql;
      string val;
      for (size_t i = 0; i < ub.size() && val.empty();) {
        if (isdigit((unsigned char)ub[i]) &&
            (i == 0 || (!isalnum((unsigned char)ub[i - 1]) && ub[i - 1] != '.' && ub[i - 1] != '_'))) {
          size_t j = i, digits = 0;
          bool dot = false;
          while (j < ub.size() && (isdigit((unsigned char)ub[j]) || (ub[j] == '.' && !dot))) {
            if (ub[j] == '.') dot = true;
            else digits++;
            j++;
          }
          string tok = sq.substr(i, j - i);
          if (digits >= 15 && !tried.count(tok)) val = tok;
          i = j;
        } else i++;
      }
      if (val.empty()) break;
      string repl = val.find('.') != string::npos ? "1.1" : "1";
      string ns;
      ns.reserve(sq.size());
      size_t p = 0;
      while (p < sq.size()) {
        if (sq.compare(p, val.size(), val) == 0 &&
            (p == 0 || (!isalnum((unsigned char)sq[p - 1]) && sq[p - 1] != '.'))) {
          char after = p + val.size() < sq.size() ? sq[p + val.size()] : ' ';
          if (!isalnum((unsigned char)after) && after != '.') {
            ns += repl;
            p += val.size();
            continue;
          }
        }
        ns += sq[p++];
      }
      vector<StreamStmt> cand = lines;
      cand[li].sql = ns;
      Probe pr = rd.probe_try(cand);
      if (pr == Probe::INFRA && ++infra >= 3) return;
      if (pr == Probe::REPRO) {
        lines = std::move(cand);
        infra = 0;
      } else {
        tried.insert(val);                             // load-bearing; try the next one
      }
    }
  }
}

// session-setting brevity: each preamble SET that is not load-bearing is dropped
static void reduce_session_sets(Reducer& rd, vector<StreamStmt>& lines) {
  rd.stage_set("session init", (long)lines.size());
  int infra = 0;
  for (size_t n = rd.session_sets.size(); n-- > 0 && !rd.session_sets.empty();) {
    if (g_stop.load() || now_ms() > rd.deadline) return;
    vector<string> save = rd.session_sets;
    rd.session_sets.erase(rd.session_sets.begin() + n);
    Probe p = rd.probe_try(lines);
    if (p == Probe::INFRA && ++infra >= 3) { rd.session_sets = std::move(save); return; }
    if (p != Probe::REPRO) rd.session_sets = std::move(save);
    else infra = 0;
  }
}

// Name brevity: the generator numbers every identifier, and a reduced testcase keeps a
// sparse few. Renumbering by first appearance reads better (a lone t3 becomes t1), and a
// family of one drops its number outright (one table is t, its one column c). A name can
// still be load-bearing (a plan echoes it, a literal can quote one), so the whole rename
// is a single candidate the probe decides; when the bare names are what fails, a dense
// numbering alone gets the second and last try.
static void name_scan(const string& sql, char prefix, bool& bare_taken,
                      vector<string>& seen) {
  auto take = [&](const string& tok) {
    if (tok.size() == 1) { bare_taken = true; return; }
    for (size_t k = 1; k < tok.size(); k++)
      if (!isdigit((unsigned char)tok[k])) return;
    if (std::find(seen.begin(), seen.end(), tok) == seen.end()) seen.push_back(tok);
  };
  string ub = upper_blanked(sql);
  for (size_t i = 0; i < sql.size(); i++) {
    if (sql[i] == '`') {                               // `t1` hides in the blanked copy
      size_t close = sql.find('`', i + 1);
      if (close == string::npos) break;
      if (close > i + 1 && sql[i + 1] == prefix) take(sql.substr(i + 1, close - i - 1));
      i = close;
    } else if (ub[i] != ' ' && sql[i] == prefix && (i == 0 || !ident_ch(ub[i - 1]))) {
      size_t j = i + 1;
      while (j < sql.size() && ident_ch(ub[j])) j++;
      take(sql.substr(i, j - i));
      i = j - 1;
    }
  }
}
static vector<std::pair<string, string>> name_plan(const vector<StreamStmt>& lines,
                                                   char prefix, bool bare) {
  vector<string> seen;                                 // in order of first appearance
  bool bare_taken = false;                             // the bare name is already in use
  for (auto& l : lines) name_scan(l.sql, prefix, bare_taken, seen);
  vector<std::pair<string, string>> map;
  for (size_t k = 0; k < seen.size(); k++) {
    string to = (bare && !bare_taken && seen.size() == 1)
                    ? string(1, prefix)
                    : string(1, prefix) + std::to_string(k + 1);
    if (to != seen[k]) map.emplace_back(seen[k], to);
  }
  return map;
}
// every occurrence in one pass over the input, so a swapped pair cannot collide;
// string literals stay as they are, and a backtick-quoted name keeps its quotes
static string rename_idents(const string& sql,
                            const vector<std::pair<string, string>>& map) {
  if (map.empty()) return sql;
  string ub = upper_blanked(sql);
  string out;
  out.reserve(sql.size());
  for (size_t i = 0; i < sql.size();) {
    if (sql[i] == '`') {
      size_t close = sql.find('`', i + 1);
      if (close == string::npos) { out += sql.substr(i); break; }
      string tok = sql.substr(i + 1, close - i - 1);
      for (auto& m : map) {
        if (m.first == tok) { tok = m.second; break; }
        // a renamed name is also the head of its suffixed forms: c2_renamed follows c2
        if (tok.size() > m.first.size() && tok[m.first.size()] == '_' &&
            tok.compare(0, m.first.size(), m.first) == 0) {
          tok = m.second + tok.substr(m.first.size());
          break;
        }
      }
      out += '`';
      out += tok;
      out += '`';
      i = close + 1;
      continue;
    }
    const string* to = nullptr;
    if (ub[i] != ' ' && (i == 0 || !ident_ch(ub[i - 1]))) {
      for (auto& m : map) {
        if (sql.compare(i, m.first.size(), m.first) == 0 &&
            (i + m.first.size() >= sql.size() || !ident_ch(ub[i + m.first.size()]) ||
             sql[i + m.first.size()] == '_')) {   // c2_renamed follows family c2
          to = &m.second;
          i += m.first.size();
          break;
        }
      }
    }
    if (to) out += *to;
    else out += sql[i++];
  }
  return out;
}
// A testcase reduced to one data row proves a difference and still reads poorly: over
// one row every aggregate returns the same number. Each added row is a small step on the
// first - letters and digits move up by the copy index - and only a grown list that
// still reproduces, with no new error, is kept.
static string mutate_tuple(const string& tup, int k) {
  string out;
  bool q = false;
  for (size_t i = 0; i < tup.size(); i++) {
    char c = tup[i];
    if (q) {
      if (c == '\'') { q = false; out += c; continue; }
      bool lone = i > 0 && tup[i - 1] == '\'' && i + 1 < tup.size() && tup[i + 1] == '\'';
      if (lone && ((c >= 'a' && c <= 'z' - k) || (c >= 'A' && c <= 'Z' - k)))
        out += (char)(c + k);
      else out += c;
      continue;
    }
    if (c == '\'') { q = true; out += c; continue; }
    if (isdigit((unsigned char)c)) {
      size_t j = i;
      while (j < tup.size() && isdigit((unsigned char)tup[j])) j++;
      string run = tup.substr(i, j - i);
      bool id_part = i > 0 && (isalnum((unsigned char)tup[i - 1]) || tup[i - 1] == '_');
      if (!id_part && run.size() <= 15) out += std::to_string(atoll(run.c_str()) + k);
      else out += run;
      i = j - 1;
      continue;
    }
    out += c;
  }
  return out;
}

static void enrich_insert_rows(Reducer& rd, vector<StreamStmt>& lines) {
  const string& cat = rd.job.hit.category;
  if (cat != "RESULT" && cat != "AFFECTED" && cat != "CHECKSUM" && cat != "PLAN" &&
      cat != "PERF") return;
  vector<StreamStmt> cand = lines;
  vector<size_t> grown;
  for (size_t li = 0; li + 1 < cand.size(); li++) {    // never the pinned statement
    string tname;
    bool cl;
    size_t vend;
    if (!parse_insert_values(cand[li].sql, upper_blanked(cand[li].sql), tname, cl, vend))
      continue;
    string head = cand[li].sql.substr(0, vend);
    vector<string> tup = split_top_level(cand[li].sql.substr(vend));
    if (tup.empty() || tup.size() >= 3) continue;
    for (int k = 1; tup.size() < 3; k++) tup.push_back(mutate_tuple(tup[0], k));
    cand[li].sql = head + join_list(tup, ",");
    grown.push_back(li);
  }
  if (grown.empty()) return;
  rd.stage_set("enrich rows", (long)lines.size());
  string sb_r = rd.base_ref, sb_d = rd.base_diff;      // grown data may move the outcome
  rd.base_ref.clear();
  rd.base_diff.clear();
  vector<uint8_t> em(cand.size(), 0);
  bool ok = rd.probe_repeat(cand, false, &em) == Probe::REPRO;
  for (size_t li : grown)
    if (em[li]) ok = false;
  if (!ok) {
    rd.base_ref = sb_r;
    rd.base_diff = sb_d;
    return;
  }
  rd.base_ref = rd.repro_ref;                          // re-base on the enriched outcome
  rd.base_diff = rd.repro_diff;
  lines = std::move(cand);
  logline("trial %ld: enrich: %zu INSERT(s) grown to 3 rows", rd.job.cand, grown.size());
}

static void reduce_names(Reducer& rd, vector<StreamStmt>& lines) {
  vector<std::pair<string, string>> full, dense;
  for (char pfx : {'t', 'c'}) {
    auto f = name_plan(lines, pfx, true);
    auto d = name_plan(lines, pfx, false);
    full.insert(full.end(), f.begin(), f.end());
    dense.insert(dense.end(), d.begin(), d.end());
  }
  if (full.empty()) return;
  rd.stage_set("rename", (long)lines.size());
  for (auto* m : {&full, &dense}) {
    if (g_stop.load() || now_ms() > rd.deadline) return;
    if (m->empty() || (m == &dense && dense == full)) continue;
    vector<StreamStmt> cand = lines;
    for (auto& l : cand) l.sql = rename_idents(l.sql, *m);
    if (rd.probe_try(cand) == Probe::REPRO) {
      lines = std::move(cand);
      return;
    }
  }
}

// PERF amplification: double the data of the tables the pinned statement reads
// (self-INSERT) while the gap holds, up to 16x, so the effect is unmistakable and
// survives reduction; /dev/shm headroom guarded. A doubling INSERT that fails (e.g.
// duplicate key) contributes nothing and the line passes remove it again.
static void amplify_perf(Reducer& rd, vector<StreamStmt>& lines) {
  rd.stage_set("amplify", (long)lines.size());
  if (lines.size() < 2) return;
  string pup = upper_blanked(lines.back().sql);
  vector<string> tabs;
  for (auto& l : lines) {
    string tn;
    size_t bs, be;
    if (!parse_create_table(l.sql, upper_blanked(l.sql), tn, bs, be)) continue;
    string tu = tn;
    for (auto& ch : tu) ch = (char)toupper((unsigned char)ch);
    if (find_word_top(pup, tu) != string::npos) tabs.push_back(tn);
  }
  if (tabs.empty()) return;
  int rounds = 0;
  while (rounds < 4 && !g_stop.load() && now_ms() <= rd.deadline) {
    struct statvfs sv;
    if (statvfs(rd.root.c_str(), &sv) == 0 &&
        (double)sv.f_bavail < 0.20 * (double)std::max<fsblkcnt_t>(1, sv.f_blocks)) break;
    vector<StreamStmt> cand = lines;
    for (auto& t : tabs)
      cand.insert(cand.end() - 1, {"INSERT INTO " + t + " SELECT * FROM " + t, false});
    if (rd.probe_try(cand) != Probe::REPRO) break;
    lines = std::move(cand);
    rounds++;
  }
  if (rounds > 0) {
    rd.perf_rounds += rounds;
    rd.perf_note = "data amplified " + std::to_string(1 << rd.perf_rounds) + "x on";
    for (auto& t : tabs) rd.perf_note += " " + t;
    logline("trial %ld: %s", rd.job.trial, rd.perf_note.c_str());
  }
}

// light clause pass on the pinned statement: drop WHERE/GROUP/HAVING/ORDER tails,
// shrink long string literals; each attempt must keep the diff alive
static void reduce_pinned_stmt(Reducer& rd, vector<StreamStmt>& lines) {
  rd.stage_set("pinned", (long)lines.size());
  if (rd.is_checkpoint || lines.empty()) return;
  auto try_stmt = [&](const string& s) -> bool {
    if (trim(s).empty()) return false;
    vector<StreamStmt> cand = lines;
    cand.back().sql = s;
    if (rd.probe_try(cand) != Probe::REPRO) return false;
    lines = std::move(cand);
    return true;
  };
  const char* clauses[] = {" WHERE ", " GROUP BY ", " HAVING ", " ORDER BY "};
  for (auto* cl : clauses) {
    if (g_stop.load() || now_ms() > rd.deadline) return;
    // the clause of this statement, not one inside a subquery or a literal
    size_t p = find_word_top(upper_blanked(lines.back().sql), cl);
    if (p == string::npos) continue;
    try_stmt(lines.back().sql.substr(0, p));
  }
  // shrink every long quoted literal to one character; a literal the diff needs is left
  // as it is and the scan carries on past it
  size_t from = 0;
  for (;;) {
    if (g_stop.load() || now_ms() > rd.deadline) return;
    const string& s = lines.back().sql;
    size_t hit_at = string::npos, hit_end = 0;
    for (size_t i = from; i < s.size();) {
      if (s[i] == '\'' || s[i] == '"') {
        size_t j = skip_quoted(s, i);
        if (j - i > 4) { hit_at = i; hit_end = j; break; }
        i = j;
      } else i++;
    }
    if (hit_at == string::npos) break;
    string cand_s = s.substr(0, hit_at + 2) + s.substr(hit_end - 1);
    from = try_stmt(cand_s) ? hit_at + 3 : hit_end;
  }
}

// EXPLAIN text for the pinned statement on one live reducer side
// the EXPLAIN for the report, rendered by the side's own client (bordered table
// output, exactly what a developer sees); C API tab output is the fallback
// The session state a new client process has to set up to see what that side saw: the
// preamble the testcase keeps, and on a combinatorics run the optimizer_switch that side 2
// carries. Without the second part a fresh client renders the default plan under a heading
// that promises the other one.
static string side_session_prefix(Reducer& rd, int i) {
  string sql;
  for (auto& s : rd.session_sets) sql += s + "; ";
  if (i == 1 && !rd.job.hit.combo.empty())
    sql += "SET SESSION optimizer_switch='" + rd.job.hit.combo + "'; ";
  return sql;
}

static string explain_pinned(Reducer& rd, int i, const string& stmt) {
  string up = upper(trim(stmt));
  bool can = up.rfind("SELECT", 0) == 0 || up.rfind("INSERT", 0) == 0 || up.rfind("UPDATE", 0) == 0 ||
             up.rfind("DELETE", 0) == 0 || up.rfind("REPLACE", 0) == 0 || up.rfind("WITH", 0) == 0;
  if (!can || !rd.sides[i].inst.alive() || !rd.sides[i].conn.h) return {};
  bool ext = false;
  for (size_t k = 0; k < g_sides.size(); k++)
    if (&g_sides[k] == rd.sides[i].inst.spec) ext = g_caps[k].explain_extended;
  string q = string(ext ? "EXPLAIN EXTENDED " : "EXPLAIN ") + stmt;
  const SideSpec* sp = rd.sides[i].inst.spec;
  string cli = sp->basedir + "/bin/mariadb";
  if (access(cli.c_str(), X_OK) != 0) cli = sp->basedir + "/bin/mysql";
  if (access(cli.c_str(), X_OK) == 0) {
    string sql = side_session_prefix(rd, i) + q;
    RunOut r = run_capture({cli, "--no-defaults", "-uroot", "-S", rd.sides[i].inst.sock,
                            "-t", "-e", sql, rd.dbname});
    if (r.status == 0 && !trim(r.out).empty()) return r.out;
  }
  string outp;
  for (auto& r : query_rows(rd.sides[i].conn, q)) {
    string line;
    for (auto& c : r) { if (!line.empty()) line += "\t"; line += c; }
    outp += line + "\n";
  }
  return outp;
}

static string crash_text_from_log(const string& errlog) {
  string log = read_file(errlog);
  size_t p = log.rfind("Assertion ");
  if (p == string::npos) p = log.rfind("got signal ");
  if (p == string::npos) return {};
  size_t e = log.find('\n', p);
  return log.substr(p, e == string::npos ? string::npos : e - p);
}

// ---------------------------------------------------------------------------
// version sweep: replay the reduced testcase across every gendirs.sh basedir
// ---------------------------------------------------------------------------
// A column type difference does not show in the printed value, so the report proves it
// with the type the result column gets, taken from the side's own client.
static string one_nl(string s);

// run statements on the side's own client, in the testcase database, and return what the
// client printed
static string client_sql(Reducer& rd, int i, const string& sql) {
  if (!rd.sides[i].inst.alive() || !rd.sides[i].conn.h) return {};
  const SideSpec* sp = rd.sides[i].inst.spec;
  string cli = sp->basedir + "/bin/mariadb";
  if (access(cli.c_str(), X_OK) != 0) cli = sp->basedir + "/bin/mysql";
  if (access(cli.c_str(), X_OK) != 0) return {};
  string body = side_session_prefix(rd, i) + sql;
  RunOut r = run_capture({cli, "--no-defaults", "-uroot", "-S", rd.sides[i].inst.sock,
                          "-t", "-e", body, rd.dbname});
  return r.status == 0 ? r.out : string();
}

// the result of the failing statement, kept in a table, so the column type and the bytes
// can be read back plainly
static string proof_table(Reducer& rd, int i, const string& stmt, const string& tbl,
                          const string& engine) {
  string out = client_sql(rd, i, "DROP TABLE IF EXISTS " + tbl + "; CREATE TABLE " + tbl +
                                     (engine.empty() ? "" : " ENGINE=" + engine) + " AS " + stmt +
                                     "; SHOW CREATE TABLE " + tbl + "\\G");
  size_t c = out.find("CREATE TABLE");
  return c == string::npos ? string() : one_nl(out.substr(c));
}

// the columns of that table, so a HEX read needs no guesswork about the select list
static vector<string> proof_columns(Reducer& rd, int i, const string& tbl) {
  vector<string> v;
  for (auto& r : query_rows(rd.sides[i].conn,
                            "SELECT COLUMN_NAME FROM information_schema.columns WHERE "
                            "table_schema='" + rd.dbname + "' AND table_name='" + tbl +
                            "' ORDER BY ORDINAL_POSITION"))
    if (!r.empty()) v.push_back(r[0]);
  return v;
}

// A plan that reaches no table (every "table" cell NULL) tells a reader nothing about a
// result difference, so it stays out of the report unless the plan itself is the finding.
// A plan explains a difference in the rows a statement returns, touches or leaves behind.
// It explains nothing about an error code, a warning or a crash, so those reports do not
// carry one.
static bool plan_explains(const string& category) {
  return category == "RESULT" || category == "AFFECTED" || category == "CHECKSUM" ||
         category == "TIMEOUT";
}

static bool plan_reaches_a_table(const string& ex) {
  for (auto& ln : split(ex, '\n')) {
    string l = trim(ln);
    if (l.empty() || l[0] == '+') continue;
    vector<string> cells;
    for (auto& c : split(l, l[0] == '|' ? '|' : '\t')) cells.push_back(trim(c));
    if (!cells.empty() && cells[0].empty()) cells.erase(cells.begin());
    if (cells.size() < 3 || cells[2] == "table") continue;      // header row, or too narrow
    if (cells[2] != "NULL" && !cells[2].empty()) return true;
  }
  return false;
}

// the matrix verdict wording: the category in the words a report reader knows
static string diff_phrase(const string& cat) {
  if (cat == "RESULT") return "QUERY RESULT";
  if (cat == "AFFECTED") return "AFFECTED ROWS";
  if (cat == "CHECKSUM") return "TABLE DATA";
  if (cat == "PLAN") return "QUERY PLAN";
  if (cat == "PERF") return "QUERY TIME";
  return cat;
}

struct SweepRow {
  string name;                     // basedir name
  string banner;                   // full version string for the report row
  string verdict;                  // DIFF: <what> | no diff | no result (...)
  bool affected = false;
  bool is_base = false;            // the build the run compared against
  bool vs_base = true;             // side 1 was held on that build while this one was probed
};

static string banner_title(const string& b) {    // "{noformat:title=X}" -> "X"
  size_t t = b.find("title=");
  if (t == string::npos) return b;
  size_t e = b.rfind('}');
  if (e == string::npos || e <= t + 6) return b.substr(t + 6);
  return b.substr(t + 6, e - t - 6);
}

// build a sweep side from a model side, with the basedir swapped; "" = ok
static string sweep_spec_from(const SideSpec& model, const string& basedir, int idx,
                              SideSpec& out) {
  out = model;                     // engine, options and session deltas carry over
  out.idx = idx;
  out.basedir = basedir;
  out.srcdir.clear();
  out.builddir.clear();
  out.init_via_bin = false;
  out.bin = probe_server_bin(basedir);
  if (out.bin.empty()) return "no server binary";
  parse_version(out);
  if (out.vendor == Vendor::Unknown) return "unknown vendor";
  return resolve_init_tool_soft(out);
}

static vector<SweepRow> version_sweep(Reducer& rd, const vector<StreamStmt>& lines) {
  vector<SweepRow> rows;
  RunOut g = run_capture({"/bin/bash", "gendirs.sh"}, "/test", 262144, 60);
  if (g.status != 0 || trim(g.out).empty()) {
    logline("trial %ld: version sweep skipped (gendirs.sh gave no builds)", rd.job.trial);
    return rows;
  }
  const SideSpec model_ref = *rd.sides[0].inst.spec;
  const SideSpec model_diff = *rd.sides[1].inst.spec;
  bool aa = model_ref.basedir == model_diff.basedir;   // A/A bug: both sides move per version
  vector<string> builds;                               // the total is wanted for the panel
  for (auto& ln : split(g.out, '\n')) {
    string name = trim(ln);
    if (name.empty() || name[0] == '#') continue;
    std::error_code ec;
    if (fs::is_directory("/test/" + name, ec)) builds.push_back(name);
  }
  int n = 0;
  for (auto& name : builds) {
    string bd = "/test/" + name;
    if (g_stop.load()) break;
    slot_text_all("version sweep " + std::to_string(n + 1) + "/" +
                  std::to_string(builds.size()));
    SweepRow row;
    row.name = name;
    row.is_base = !aa && bd == model_ref.basedir;
    // A/A moves both sides to the swept build, so a row that shows nothing was not compared
    // against anything else and "no diff found" is the whole of it
    row.vs_base = !aa;
    SideSpec sa, sb;
    string e1 = sweep_spec_from(model_ref, aa ? bd : model_ref.basedir, 1, sa);
    string e2 = sweep_spec_from(model_diff, bd, 2, sb);
    if (!e2.empty() || !e1.empty()) {
      row.verdict = "no result (" + (e2.empty() ? e1 : e2) + ")";
      row.banner = name;
      rows.push_back(row);
      continue;
    }
    string bn = myver_banner(sb);
    row.banner = bn.empty() ? (sb.ver_string.empty() ? name : sb.ver_string) : banner_title(bn);
    Reducer sw;
    sw.job = rd.job;
    sw.session_sets = rd.session_sets;                 // replay exactly what the testcase keeps
    sw.deadline = now_ms() + 180 * 1000.0;
    if (!sw.setup_at(&sa, &sb, g_run.rundir + "/swp" + std::to_string(rd.job.cand) + "-" +
                                   std::to_string(n))) {
      row.verdict = "no result (" +
                    (sw.start_error.empty() ? string("server failed to start") : sw.start_error) +
                    ")";
    } else {
      sw.inner_attempts = rd.inner_attempts;             // a sporadic bug needs its passes here too
      CompareModeFor modes(sa.vendor, sb.vendor);        // this pair, not the run's pair
      Probe p = sw.probe_try(lines);
      row.verdict = p == Probe::REPRO   ? "DIFF: " + diff_phrase(rd.job.hit.category)
                    : sw.budget_spent   ? "no result (out of time)"
                    : p == Probe::NO    ? "no diff"
                                        : "no result (instance trouble)";
      row.affected = p == Probe::REPRO;
      if (row.affected)                          // what the build did, not only that it differs
        logline("trial %ld: ver-sweep %s: %s against %s", rd.job.cand, name.c_str(),
                sw.repro_ref.c_str(), sw.repro_diff.c_str());
    }
    sw.teardown();
    rows.push_back(row);
    n++;
  }
  return rows;
}

// mainline X.Y (numeric) sets for the Jira version fields, split CS / ES
static void sweep_versions(const vector<SweepRow>& rows, vector<string>& cs, vector<string>& es) {
  std::set<std::pair<long, long>> csv, esv;
  for (auto& r : rows) {
    if (!r.affected) continue;
    bool is_es = r.name.rfind("EMD", 0) == 0;
    bool is_cs = !is_es && r.name.rfind("MD", 0) == 0;
    if (!is_es && !is_cs) continue;                    // MySQL rows carry no MDEV field
    size_t p = r.name.find("-mariadb-");
    if (p == string::npos) continue;
    long ma = 0, mi = 0;
    if (sscanf(r.name.c_str() + p + 9, "%ld.%ld", &ma, &mi) != 2) continue;
    (is_es ? esv : csv).insert({ma, mi});
  }
  for (auto& v : csv) cs.push_back(std::to_string(v.first) + "." + std::to_string(v.second));
  for (auto& v : esv) es.push_back(std::to_string(v.first) + "." + std::to_string(v.second));
}

// The bug detection matrix in the layout the framework's bug reports use: one row per
// build, vendor tag, release, build flavour, build date, full commit id, observation.
static string matrix_block(const vector<SweepRow>& sweep) {
  if (sweep.empty()) return {};
  vector<std::array<string, 6>> rows;
  rows.push_back({"", "Rel", "o/d", "Build", "Commit", "Diff observed"});
  for (auto& r : sweep) {
    std::array<string, 6> m = {"", "", "", "", "", ""};
    string n = r.name;
    for (const char* p : {"UBASAN_", "ASAN_", "MSAN_", "TSAN_", "VAL_"})
      if (n.rfind(p, 0) == 0) n = n.substr(strlen(p));
    string pfx = n.substr(0, n.find('-'));
    if (pfx.rfind("EMD", 0) == 0) { m[0] = "ES"; m[3] = pfx.substr(3); }
    else if (pfx.rfind("MD", 0) == 0) { m[0] = "CS"; m[3] = pfx.substr(2); }
    else if (pfx.rfind("MS", 0) == 0) { m[0] = "MS"; m[3] = pfx.substr(2); }
    else m[0] = pfx;
    for (const char* tag : {"-mariadb-", "-mysql-"}) {
      size_t v = n.find(tag);
      if (v == string::npos) continue;
      string ver = n.substr(v + strlen(tag));
      ver = ver.substr(0, ver.find('-'));
      long a = 0, b = 0;
      m[1] = sscanf(ver.c_str(), "%ld.%ld", &a, &b) == 2
               ? std::to_string(a) + "." + std::to_string(b) : ver;
      break;
    }
    if (n.size() > 4) {
      string tail = n.substr(n.size() - 4);
      if (tail == "-opt") m[2] = "opt";
      else if (tail == "-dbg") m[2] = "dbg";
    }
    for (size_t i = 0; i + 40 <= r.banner.size(); i++) {   // the 40-hex commit id
      size_t j = i;
      while (j < r.banner.size() && isxdigit((unsigned char)r.banner[j])) j++;
      if (j - i == 40) { m[4] = r.banner.substr(i, 40); break; }
      i = j;
    }
    if (m[1].empty()) m[1] = r.banner.empty() ? r.name : r.banner;
    // A probe against a held reference answers "did this build behave like the reference",
    // and the reference itself is never assessed. Where a defect is one the reference shares,
    // that is not the same as clean, so the cell says what was measured.
    m[5] = r.is_base    ? "BASE/SOURCE"
           : r.affected ? r.verdict
                        : (r.verdict.rfind("no result", 0) == 0
                             ? "No result" + r.verdict.substr(9)
                             : (r.vs_base ? "Same as base/source" : "No diff found"));
    rows.push_back(m);
  }
  size_t w[6] = {0};
  for (auto& r : rows)
    for (size_t j = 0; j < 6; j++) w[j] = std::max(w[j], r[j].size());
  string out = "{noformat:title=Bug Detection Matrix}\n";
  for (auto& r : rows) {
    string line;
    for (size_t j = 0; j < 6; j++) {
      line += r[j];
      if (j + 1 < 6) line.append(w[j] - r[j].size() + 2, ' ');
    }
    out += line + "\n";
  }
  out += "{noformat}\n";
  return out + "\n";
}

// a captured block ends with exactly one newline, so a {noformat} closes tight
static string one_nl(string s) {
  while (!s.empty() && (s.back() == '\n' || s.back() == '\r' || s.back() == ' ')) s.pop_back();
  return s.empty() ? s : s + "\n";
}

static string sh_quote(const string& s) {
  string out = "'";
  for (char c : s) {
    if (c == '\'') out += "'\\''";
    else out += c;
  }
  out += "'";
  return out;
}

// the release a version string names: "13.0.2-MariaDB" -> "13.0"
static string release_of(const string& ver) {
  size_t d1 = ver.find('.');
  if (d1 == string::npos) return ver;
  size_t d2 = ver.find('.', d1 + 1);
  return d2 == string::npos ? ver : ver.substr(0, d2);
}

// the statement in a few words: its verb and the first function it calls, else the verb
// and what it is built on
static string stmt_head(const string& stmt) {
  static const char* SKIP[] = {"SELECT", "VALUES", "IN", "EXISTS", "ON", "USING", "AND", "OR",
                               "NOT", "WHERE", "BY", "TABLE", "KEY", "INDEX", "PARTITION"};
  string up = upper(trim(stmt));
  size_t sp = up.find_first_of(" \t");
  string head = sp == string::npos ? up : up.substr(0, sp);
  for (size_t i = 1; i < up.size(); i++) {
    if (up[i] != '(') continue;
    size_t b = i;
    while (b > 0 && (isalnum((unsigned char)up[b - 1]) || up[b - 1] == '_')) b--;
    if (b == i) continue;
    string fn = up.substr(b, i - b);
    bool skip = fn == head;
    for (const char* k : SKIP) skip = skip || fn == k;
    if (fn.size() > 1 && (fn[0] == 'T' || fn[0] == 'C') &&
        fn.find_first_not_of("0123456789", 1) == string::npos) skip = true;
    if (!skip) { head += " " + fn; break; }
  }
  if (head.find(' ') == string::npos) {
    if (up.find("(SELECT") != string::npos) head += " with a subquery";
    else if (up.find(" JOIN ") != string::npos) head += " with a join";
    else if (up.find("GROUP BY") != string::npos) head += " with GROUP BY";
  }
  return head;
}

// the report's first line: what the bug is, in one sentence
static string bug_title(const Reducer& rd, const string& ver_r, const string& ver_d,
                        const string& pinned) {
  const string& cat = rd.job.hit.category;
  string aspect = "Difference in query result";
  if (cat == "PLAN") aspect = "Difference in query plan";
  else if (cat == "PERF") aspect = "Difference in query time";
  else if (cat == "ERROR") aspect = "Difference in error code";
  else if (cat == "WARNING") aspect = "Difference in warning";
  else if (cat == "AFFECTED") aspect = "Difference in affected row count";
  else if (cat == "CHECKSUM")
    aspect = rd.read_failed ? "Failure to read a table" : "Difference in table content";
  else if (cat == "TIMEOUT") aspect = "Query timeout";
  else if (cat == "CRASH") aspect = "Server crash";
  const SideSpec* a = rd.sides[0].inst.spec;
  const SideSpec* b = rd.sides[1].inst.spec;
  string where;
  if (a->basedir == b->basedir) {
    where = "in " + release_of(ver_r);
    if (!rd.job.hit.combo.empty()) where += " with optimizer_switch='" + rd.job.hit.combo + "'";
    else if (!b->options.empty()) where += " with " + b->options;
    else if (a->engine != b->engine)
      where += " when using " + engine_name(a->engine) + " vs " + engine_name(b->engine);
  } else {
    bool one_vendor = a->vendor == b->vendor;
    string ra = release_of(ver_r), rb = release_of(ver_d);
    if (!one_vendor) {
      ra = string(vendor_name(a->vendor)) + " " + ra;
      rb = string(vendor_name(b->vendor)) + " " + rb;
    }
    where = "in " + ra + " vs " + rb;
  }
  return aspect + " " + where + " on " +
         stmt_head(pinned.empty() ? rd.job.hit.statement : pinned);
}

// bugN.log.sh: a ready ~/jira filing call. Title and description come out of
// bugN.report when the script runs, so any edit made there is what gets filed. The
// operator reviews the version fields and runs it; ~/jira itself asks for
// confirmation three times before posting (--dry-run validates without posting).
static void write_log_script(Reducer& rd, const vector<SweepRow>& sweep,
                             const string& ver_r, const string& ver_d) {
  (void)ver_r; (void)ver_d;
  const string nb = std::to_string(rd.job.bug);
  string jira = home_dir() + "/jira";
  if (access(jira.c_str(), X_OK) != 0) return;       // standalone box: no filing helper
  const string& cat = rd.job.hit.category;
  vector<string> cs, es;
  sweep_versions(sweep, cs, es);
  // Where the two sides differ by engine, the engines are what the finding is about, so
  // they are the components. Otherwise the category picks one.
  vector<string> comps;
  {
    const SideSpec* a = rd.sides[0].inst.spec;
    const SideSpec* b = rd.sides[1].inst.spec;
    if (a && b && a->engine != b->engine)
      for (const string& e : {a->engine, b->engine}) {
        string c = engine_component(e);
        if (!c.empty() && std::find(comps.begin(), comps.end(), c) == comps.end())
          comps.push_back(c);
      }
    if (comps.empty())
      comps.push_back((cat == "RESULT" || cat == "PLAN" || cat == "PERF") ? "Optimizer" : "Server");
  }
  // Fix Version is Affects without its newest branch: a fix lands in the earliest
  // affected branch and up-merges. A single affected branch is its own fix version.
  vector<string> fixv = cs;
  if (fixv.size() > 1) fixv.pop_back();
  vector<string> labels;
  if (cat == "CRASH") labels.push_back("crash");
  // A regression is the newer build being the worse one, so the sides are weighed by
  // version and not by the order they were given. Which side is worse is measured for PLAN
  // and PERF; for every other category the compared side is the one that differed.
  if (rd.sides.size() >= 2 && rd.sides[0].inst.spec && rd.sides[1].inst.spec &&
      rd.sides[0].inst.spec->basedir != rd.sides[1].inst.spec->basedir &&
      regression_reportable(rd.sides[0].inst.spec, rd.sides[1].inst.spec,
                            !rd.job.hit.ref_worse))
    labels.push_back("regression");
  string prio = cat == "CRASH" ? "Critical" : "Major";
  string body = "bug" + nb + ".body";
  string sh = "#!/bin/bash\n";
  sh += "# corlogic filing helper for bug" + nb + ".report (trial " + nb + ").\n";
  sh += "# The title is line 1 of bug" + nb + ".report and the description is the rest, read\n";
  sh += "# when this script runs: edit the report, and that is what gets filed.\n";
  sh += "# ~/jira asks for confirmation three times before posting; pass --dry-run to validate only.\n";
  sh += "cd \"$(dirname \"$0\")\" || exit 1\n";
  sh += "title=$(head -n1 bug" + nb + ".report)\n";
  sh += "tail -n +3 bug" + nb + ".report > " + body + "\n";
  sh += jira + " -p MDEV -t Bug \\\n";
  sh += "  -s \"$title\" \\\n";
  sh += "  --description-file " + body + " \\\n";
  for (auto& v : cs) sh += "  --affects-version " + v + " \\\n";
  // no Enterprise version affected is stated as N/A, not left empty
  if (es.empty()) sh += "  --es-version N/A \\\n";
  else for (auto& v : es) sh += "  --es-version " + v + " \\\n";
  for (auto& v : fixv) sh += "  --fix-version " + v + " \\\n";
  for (auto& c : comps) sh += "  -c " + sh_quote(c) + " \\\n";
  for (auto& l : labels) sh += "  --label " + l + " \\\n";
  sh += "  --priority " + prio + " \\\n";
  sh += "  \"$@\"\n";
  sh += "rc=$?\n";
  sh += "rm -f " + body + "\n";                     // the description file has served its purpose
  sh += "exit $rc\n";
  string p = g_run.workdir + "/bug" + nb + ".log.sh";
  write_file(p, sh);
  chmod(p.c_str(), 0755);
}

// short version for prose: the first two numeric components, MySQL-prefixed for MySQL
static string short_version(const SideSpec* s) {
  const SideCaps* c = caps_for(s);
  string vf = c ? c->version_full : "";
  string out;
  int dots = 0;
  for (char ch : vf) {
    if (ch >= '0' && ch <= '9') out += ch;
    else if (ch == '.') { if (++dots == 2) break; out += ch; }
    else break;
  }
  if (out.empty()) out = vf;
  return s->vendor == Vendor::MySQL ? "MySQL " + out : out;
}

// prose descriptor: the version plus what makes this side different
// server options in Jira markup: monospaced, and a leading -- escaped so Jira does
// not read it as strikethrough
static string jira_opts(const string& o) {
  string out;
  bool at_start = true;
  for (size_t i = 0; i < o.size(); i++) {
    if (at_start && o[i] == '-') out += '\\';
    out += o[i];
    at_start = o[i] == ' ';
  }
  return "{{" + out + "}}";
}

static string side_desc(const SideSpec* s) {
  string d = short_version(s);
  if (!s->options.empty()) d += " with " + jira_opts(s->options);
  return d;
}

// {noformat:title=...} opener from the cached myver banner (fallback: plain version)
static string banner_open(const SideSpec* s) {
  const SideCaps* c = caps_for(s);
  string b = c ? c->version_banner : "";
  if (starts_with_i(b, "{noformat")) return b;
  return "{noformat:title=" + (b.empty() ? string("unknown version") : b) + "}";
}

// outcome trace capped for the report: at most max_rows row-lines per statement
// keep the first max lines of a block, and say how many were left out
// The trace numbers the statements it ran. The report block puts --source and SET lines
// above them, so the numbers are shifted to the line the reader sees.
static string renumber_trace(const string& out, size_t offset) {
  if (!offset) return out;
  string res;
  size_t p = 0;
  while (p < out.size()) {
    size_t nl = out.find('\n', p);
    if (nl == string::npos) nl = out.size();
    string line = out.substr(p, nl - p);
    size_t d = 0;
    while (d < line.size() && isdigit((unsigned char)line[d])) d++;
    if (d && d < line.size() && line[d] == '|')
      line = std::to_string(atol(line.c_str()) + (long)offset) + line.substr(d);
    res += line + "\n";
    p = nl + 1;
  }
  return res;
}

static string cap_lines(const string& out, size_t max) {
  string res;
  size_t p = 0, kept = 0, dropped = 0;
  while (p < out.size()) {
    size_t nl = out.find('\n', p);
    if (nl == string::npos) nl = out.size();
    if (kept < max) { res += out.substr(p, nl - p) + "\n"; kept++; }
    else dropped++;
    p = nl + 1;
  }
  if (dropped) res += "... (" + std::to_string(dropped) + " more line(s))\n";
  return res;
}

static string cap_trace(const string& out, size_t max_rows, size_t max_total) {
  vector<string> in;
  size_t p = 0;
  while (p < out.size()) {
    size_t nl = out.find('\n', p);
    if (nl == string::npos) nl = out.size();
    in.push_back(out.substr(p, nl - p));
    p = nl + 1;
  }
  string res;
  size_t emitted = 0, run = 0, skip = 0;
  string cur;
  for (size_t i = 0; i <= in.size(); i++) {
    bool end = i == in.size();
    string idx;
    if (!end) {
      size_t bar = in[i].find("| row| ");
      if (bar != string::npos) idx = in[i].substr(0, bar + 2);
    }
    if (end || idx != cur) {
      if (skip) {
        res += cur + "... (" + std::to_string(skip) + " more row(s))\n";
        emitted++;
        skip = 0;
      }
      cur = idx;
      run = 0;
    }
    if (end) break;
    if (emitted >= max_total) {
      res += "... (" + std::to_string(in.size() - i) + " more line(s))\n";
      break;
    }
    if (!idx.empty() && ++run > max_rows) { skip++; continue; }
    res += in[i] + "\n";
    emitted++;
  }
  return res;
}

// plain-English outcome phrase from a brief like "OK 501 row(s) ..." / "ERROR 1104: ..."
static string outcome_phrase(const string& in) {
  string b = in;
  if (starts_with_i(b, "WARN")) b = "OK" + b.substr(4);
  if (starts_with_i(b, "ERROR ")) {
    size_t c = b.find(':');
    return "fails with " + (c == string::npos ? b : b.substr(0, c));
  }
  if (starts_with_i(b, "OK affected=")) return "succeeds (" + b.substr(3) + ")";
  if (starts_with_i(b, "OK ")) {
    size_t r = b.find(" row(s)");
    if (r != string::npos) return "returns " + b.substr(3, r - 3) + " row(s)";
    return "succeeds";
  }
  if (starts_with_i(b, "OK")) return "succeeds";
  if (starts_with_i(b, "TIMEOUT")) return "does not finish before the query timeout";
  if (b.find("crash") != string::npos || b.find("gone away") != string::npos ||
      b.find("Lost connection") != string::npos)
    return "crashes the server";
  return b.empty() ? string("gives no result") : b;
}

static string warn_codes_of(const string& brief) {
  size_t p = brief.find("warn[");
  if (p == string::npos) return {};
  size_t e = brief.find(']', p);
  return e == string::npos ? string() : brief.substr(p + 5, e - p - 5);
}

// Every object of one kind the testcase creates, in the order it creates them. MTR checks
// the schema after a test and reports anything left behind, so the testcase drops its own
// tables, views, sequences and routines on the last line.
static vector<string> created_objects(const string& tc, const string& kind) {
  vector<string> out;
  for (auto& line : split(tc, '\n')) {
    string up = upper(line);
    if (up.rfind("CREATE ", 0) != 0) continue;
    size_t k = up.find(" " + kind + " ");
    if (k == string::npos) continue;
    size_t p = k + kind.size() + 2;
    while (p < up.size() && isspace((unsigned char)up[p])) p++;
    if (up.compare(p, 14, "IF NOT EXISTS ") == 0) p += 14;
    while (p < up.size() && isspace((unsigned char)up[p])) p++;
    string name;
    if (p < line.size() && line[p] == '`') {
      size_t e = line.find('`', p + 1);
      if (e == string::npos) continue;
      name = line.substr(p, e - p + 1);
    } else {
      size_t q = p;
      while (q < line.size() &&
             (isalnum((unsigned char)line[q]) || line[q] == '_' || line[q] == '$' || line[q] == '.'))
        q++;
      name = line.substr(p, q - p);
    }
    if (!name.empty() && std::find(out.begin(), out.end(), name) == out.end())
      out.push_back(name);
  }
  return out;
}

// the one line that clears what the testcase made, so a run of it under MTR ends clean
static string cleanup_line(const string& tc) {
  static const char* kinds[] = {"VIEW", "SEQUENCE", "TABLE", "FUNCTION", "PROCEDURE"};
  string out;
  for (const char* kind : kinds) {
    vector<string> names = created_objects(tc, kind);
    if (names.empty()) continue;
    string list;
    for (auto& n : names) list += (list.empty() ? "" : ", ") + n;
    out += string("DROP ") + kind + " IF EXISTS " + list + ";\n";
  }
  return out;
}

// one plain-English sentence, only where it says something the title and the blocks below
// do not: what each side did when the two did different things, or what a plan or timing
// difference leaves the same. An empty string leaves the sentence out.
static string explain_bug(const Reducer& rd, const string& da, const string& db) {
  const string& cat = rd.job.hit.category;
  if (cat == "CHECKSUM") {
    if (rd.read_failed)
      return "After the same statements, a plain read of table " + rd.diff_table +
             " succeeds on " + (rd.read_failed_ref ? db : da) + " and fails on " +
             (rd.read_failed_ref ? da : db) + ".";
    return "Running the same statements leaves different table data on " + da + " and on " + db + ".";
  }
  if (cat == "PLAN" || cat == "PERF")
    return "Both servers return the same rows.";
  if (cat == "WARNING") {
    string wa = warn_codes_of(rd.repro_ref), wb = warn_codes_of(rd.repro_diff);
    return "The last statement gives the same result on both, but raises " +
           (wa.empty() ? string("no warning") : "warning " + wa) + " on " + da + " and " +
           (wb.empty() ? string("none") : "warning " + wb) + " on " + db + ".";
  }
  if (uid_mech(rd.job.uid) == "coltype")
    return "Both servers return the same bytes, but the result column type differs.";
  if (uid_mech(rd.job.uid) == "bytes")
    return "The client prints the same output on both servers, but the bytes differ.";
  string pa = outcome_phrase(rd.repro_ref), pb = outcome_phrase(rd.repro_diff);
  if (pa == pb) return "";
  return "The last statement " + pa + " on " + da + ", but " + pb + " on " + db + ".";
}

// bugN.report and bugN.log.sh are the deliverables; a core, an error log, and the
// reducer's input testcase are the only content that also gets its own file
// returns the UID the report carries, or "" when the finding was muted and not written
static string write_bug_artifacts(Reducer& rd, const vector<StreamStmt>& lines,
                                  const vector<SweepRow>& sweep) {
  const string base = g_run.workdir + "/bug" + std::to_string(rd.job.bug);
  const SideSpec* sp_r = rd.sides[0].inst.spec;
  const SideSpec* sp_d = rd.sides[1].inst.spec;
  int idx_r = sp_r->idx, idx_d = sp_d->idx;
  // taken before the servers stopped, because the version sweep ran on their slots
  const string& ex_r = rd.ex_ref;
  const string& ex_d = rd.ex_diff;
  // a column type difference, and a byte difference the client prints the same, are both
  // invisible in the query output, so the result is kept in a table and read back plainly
  string mech = uid_mech(rd.job.uid);
  // The mechanism describes the testcase the report ships, not the trial that found it: a
  // count that came out of the trial's data is not the count the reduced testcase produces,
  // and a UID whose two halves describe different things mutes nothing when it is copied
  // into corlogic.known.
  if (!rd.repro_mech.empty()) mech = rd.repro_mech;
  // A checkpoint reduction can end on a different table than detection found, so the
  // table the report names comes from the final replay and not from the first sighting
  if (rd.is_checkpoint) {
    vector<string> la = split(rd.out_ref, '\n'), lb = split(rd.out_diff, '\n');
    for (size_t i = 0; i < la.size() && i < lb.size(); i++) {
      if (la[i] == lb[i] || la[i].rfind("table ", 0) != 0 || lb[i].rfind("table ", 0) != 0)
        continue;
      size_t bar = la[i].find("| ");
      if (bar == string::npos || la[i].compare(0, bar, lb[i], 0, bar) != 0) continue;
      rd.diff_table = trim(la[i].substr(6, bar - 6));
      bool ea = la[i].find("| ERROR ") != string::npos;
      bool eb = lb[i].find("| ERROR ") != string::npos;
      rd.read_failed = ea != eb;
      rd.read_failed_ref = ea;
      break;
    }
    if (!rd.diff_table.empty()) mech = "tbl:" + rd.diff_table;
    else if (mech.rfind("tbl:", 0) == 0) rd.diff_table = mech.substr(4);
  }
  bool hidden = (mech == "coltype" || mech == "bytes") && !rd.is_checkpoint && !lines.empty() &&
                stmt_readonly(lines.back().sql);
  string ptbl, pf_read, ct_r, ct_d;
  string ver_r, ver_d;
  for (size_t k = 0; k < g_sides.size(); k++) {
    if (&g_sides[k] == sp_r) ver_r = g_caps[k].version_full;
    if (&g_sides[k] == sp_d) ver_d = g_caps[k].version_full;
  }
  string desc_r = side_desc(sp_r), desc_d = side_desc(sp_d);
  if (!rd.job.hit.combo.empty()) desc_d += " with optimizer_switch='" + rd.job.hit.combo + "'";
  string eng_r = sp_r->engine.empty() ? g_cfg.engine : sp_r->engine;
  string eng_d = sp_d->engine.empty() ? g_cfg.engine : sp_d->engine;
  if (eng_r != eng_d) {                                // the engine is part of what differs
    desc_r += " (" + engine_name(eng_r) + ")";
    desc_d += " (" + engine_name(eng_d) + ")";
  }
  if (hidden) {
    std::set<string> used;
    for (auto& s : lines) for (auto& t : table_names_of(s.sql)) used.insert(t);
    for (int k = 1; k <= 99 && ptbl.empty(); k++)
      if (!used.count("T" + std::to_string(k))) ptbl = "t" + std::to_string(k);
    string peng = eng_r == eng_d ? eng_r : string();
    string tr = proof_table(rd, 0, lines.back().sql, ptbl, peng);
    string td = proof_table(rd, 1, lines.back().sql, ptbl, peng);
    if (mech == "coltype") {                            // the type is in the table definition
      pf_read = "SHOW CREATE TABLE " + ptbl;
      ct_r = tr;
      ct_d = td;
    } else if (!tr.empty() && !td.empty()) {            // the bytes are in a HEX read
      string sel;
      for (auto& c : proof_columns(rd, 0, ptbl))
        sel += string(sel.empty() ? "" : ", ") + "HEX(`" + c + "`)";
      if (!sel.empty()) {
        pf_read = "SELECT " + sel + " FROM " + ptbl;
        ct_r = one_nl(client_sql(rd, 0, pf_read + ";"));
        ct_d = one_nl(client_sql(rd, 1, pf_read + ";"));
      }
    }
    hidden = !ct_r.empty() && !ct_d.empty();
  }
  // crash bridge: error log + core + a ready reducer script (its input testcase file)
  string crash_note, server_uid;
  if (rd.job.hit.category == "CRASH") {
    write_stream_file(base + ".sql", lines);
    std::error_code ec;
    // which side died was recorded while both were still up; by now both are stopped
    SideRun* dead = (rd.dead_side >= 0 && rd.dead_side < (int)rd.sides.size())
                      ? &rd.sides[rd.dead_side] : nullptr;
    if (dead) {                                      // the reduction reproduced the crash
      fs::copy_file(dead->inst.errlog, base + ".master.err", fs::copy_options::overwrite_existing, ec);
      string core = newest_core_in(dead->inst.datadir);
      if (!core.empty()) copy_core_sparse(core, base + ".core");
      crash_note = crash_text_from_log(dead->inst.errlog);
      string nts = home_dir() + "/mariadb-qa/new_text_string.sh";
      if (access(nts.c_str(), X_OK) == 0) {
        RunOut r = run_capture({nts}, dead->inst.root);
        string first = trim(r.out.substr(0, r.out.find('\n')));
        if (r.status == 0 && !first.empty()) server_uid = first;
      }
    } else {                                         // not reproduced: use the trial-time copies
      string tbase = g_run.workdir + "/trial" + std::to_string(rd.job.trial) + "-side" +
                     std::to_string(idx_d);
      if (fs::exists(tbase + ".err", ec)) {
        fs::copy_file(tbase + ".err", base + ".master.err", fs::copy_options::overwrite_existing, ec);
        crash_note = crash_text_from_log(tbase + ".err");
      }
      if (fs::exists(tbase + ".core", ec))
        copy_core_sparse(tbase + ".core", base + ".core");
    }
    // ready-to-run reducer<trial>.sh: the reducer_cpp.sh wrapper with a
    // pquery-prep-red.sh style #VARMOD# block (inserted above the marker)
    string red_tpl = home_dir() + "/mariadb-qa/reducer_cpp.sh";
    if (access(red_tpl.c_str(), R_OK) != 0) red_tpl = home_dir() + "/mariadb-qa/OLD/reducer.sh";
    if (access(red_tpl.c_str(), R_OK) == 0) {
      string body = read_file(red_tpl);
      const SideSpec* cs = rd.sides[1].inst.spec;    // the crashing side
      string myx = "--no-defaults";           // the testcase carries its own SETs
      for (auto& o : split(g_cfg.mem_caps, ' ')) if (!o.empty()) myx += " " + o;
      if (!cs->engine.empty()) myx += " --default-storage-engine=" + cs->engine;
      for (auto& o : split(g_cfg.myextra, ' ')) if (!o.empty()) myx += " " + o;
      for (auto& o : split(cs->options, ' ')) if (!o.empty()) myx += " " + o;
      string vars;
      if (!server_uid.empty()) {
        string esc = server_uid;
        for (size_t q = 0; (q = esc.find('"', q)) != string::npos; q += 2) esc.replace(q, 1, "\\\"");
        vars += "MODE=3\n";
        vars += "USE_NEW_TEXT_STRING=1\n";
        vars += "# IMPORTANT NOTE; Leave the 3 spaces before TEXT on the next line; pquery-results.sh uses these\n";
        vars += "   TEXT=\"" + esc + "\"\n";
      } else {                                       // no UID available: match any crash
        vars += "MODE=4\n";
        vars += "USE_NEW_TEXT_STRING=0\n";
      }
      vars += "BASEDIR=\"" + cs->basedir + "\"\n";
      vars += "INPUTFILE=\"" + base + ".sql\"\n";
      vars += "SCAN_FOR_NEW_BUGS=" + string(server_uid.empty() ? "0" : "1") + "\n";
      vars += "KNOWN_BUGS_LOC=\"" + home_dir() + "/mariadb-qa/known_bugs.strings\"\n";
      vars += "TEXT_STRING_LOC=\"" + home_dir() + "/mariadb-qa/new_text_string.sh\"\n";
      vars += "DISABLE_TOKUDB_AUTOLOAD=1\n";
      vars += "MYEXTRA=\"" + myx + "\"\n";
      vars += "USE_PQUERY=0\n";
      vars += "PQUERY_LOC=" + home_dir() + "/mariadb-qa/pquery/pquery2-md.NEW\n";
      size_t vm = body.find("#VARMOD#");
      if (vm != string::npos) {
        body.insert(vm, vars);
        string rs = g_run.workdir + "/reducer" + std::to_string(rd.job.trial) + ".sh";
        write_file(rs, body);
        chmod(rs.c_str(), 0755);
      }
    }
  }
  // Jira report: line 1 the title, then the testcase, the outcomes and the matrix.
  // The testcase is emitted MTR-ready: the needed --source includes, the session
  // settings inline, and engine-explicit CREATE TABLE statements.
  bool planperf = rd.job.hit.category == "PLAN" || rd.job.hit.category == "PERF";
  string tc;
  bool has_part = false;
  for (auto& s : lines) {
    string sql = s.sql;
    string usql = upper(sql);
    if (usql.find("PARTITION BY") != string::npos) has_part = true;
    if (eng_r == eng_d && starts_with_i(sql, "CREATE TABLE") &&
        usql.find("ENGINE") == string::npos) {
      size_t pb = usql.find(" PARTITION BY");
      string ec = " ENGINE=" + engine_name(eng_r);
      if (pb != string::npos) sql.insert(pb, ec);
      else sql += ec;
    }
    tc += sql + ";\n";
  }
  // the plan belongs in the testcase: PLAN/PERF always, and any other difference a
  // plan explains, so the developer replays what the report shows
  if (!rd.is_checkpoint && !lines.empty() &&
      (planperf || (plan_explains(rd.job.hit.category) &&
                    (plan_reaches_a_table(rd.ex_ref) || plan_reaches_a_table(rd.ex_diff)))))
    tc += "EXPLAIN " + lines.back().sql + ";\n";
  if (hidden)
    tc += "CREATE TABLE " + ptbl + (eng_r == eng_d ? " ENGINE=" + engine_name(eng_r) : "") + " AS " +
          lines.back().sql + ";\n" + pf_read + ";\n";
  string pinned = (!rd.is_checkpoint && !lines.empty()) ? lines.back().sql : rd.job.hit.statement;
  // combinatorics: both sides are the same build, so one script shows both outcomes -
  // the statement under the default optimizer_switch, then under the combination
  if (!rd.job.hit.combo.empty()) {
    if (!rd.is_checkpoint && !lines.empty() && stmt_readonly(pinned))
      tc += "SET SESSION optimizer_switch='" + rd.job.hit.combo + "';\n" + pinned + ";\n";
    else
      tc += "# run the statements above again after SET SESSION optimizer_switch='" +
            rd.job.hit.combo + "' for the other outcome\n";
  }
  tc += cleanup_line(tc);              // MTR reports anything the test leaves behind
  string utc = upper(tc);
  bool makes_a_table = utc.find("CREATE TABLE") != string::npos ||
                       utc.find("CREATE OR REPLACE TABLE") != string::npos;
  string block;                                       // exactly what the {code:sql} shows
  if (eng_r == eng_d) {
    if (makes_a_table) block += engine_prelude(sp_r->basedir, eng_r);
  } else {                                     // both engines are named, so both are prepared
    block += engine_prelude(sp_r->basedir, eng_r);
    block += engine_prelude(sp_d->basedir, eng_d);
  }
  if (has_part) block += "--source include/have_partition.inc\n";
  if (eng_r != eng_d && !eng_r.empty())        // the other side ran the same lines on eng_d
    block += "SET default_storage_engine=" + engine_name(eng_r) + ";\n";
  for (auto& s : rd.session_sets) block += s + ";\n";  // only the load-bearing SETs survive
  size_t block_head = (size_t)std::count(block.begin(), block.end(), '\n');
  block += tc;
  // the finding's identity: the testcase id, then what differs and where
  string uid1 = uid1_of(block, rd.job.trial);
  string tail = rd.job.hit.category + "|" + mech + "|" + constructs_of(pinned) +
                "|" + norm_stmt(pinned);
  string uid = (uid1.empty() ? string() : uid1 + "//") + tail;
  auto drop_files = [&] {                             // a muted finding leaves nothing behind
    std::error_code ec;
    for (const char* ext : {".sql", ".master.err", ".core"}) fs::remove(base + ext, ec);
    fs::remove(g_run.workdir + "/reducer" + std::to_string(rd.job.trial) + ".sh", ec);
  };
  if (known_uid1(uid1) || known_match(tail)) {
    g_known_matches++;
    logline("trial %ld: known testcase muted: %s", rd.job.trial, uid.c_str());
    drop_files();
    return {};
  }
  {
    std::lock_guard<std::mutex> lk(g_uid_mtx);
    auto it = g_uid1_seen.find(uid1);
    if (!uid1.empty() && it != g_uid1_seen.end()) {
      g_dup_diffs++;
      logline("trial %ld: the same testcase as trial %ld, not reported again",
              rd.job.trial, it->second);
      append_seen("cand" + std::to_string(it->second), rd.job.uid, rd.job.trial);
      drop_files();
      return {};
    }
    if (!uid1.empty()) g_uid1_seen[uid1] = rd.job.trial;
  }
  string rep = bug_title(rd, ver_r, ver_d, pinned) + "\n\n";   // line 1 is the title, line 2 blank
  rep += "{code:sql}\n" + block + "{code}\n\n";
  string note = explain_bug(rd, desc_r, desc_d);   // empty when the phrases match
  if (!note.empty()) rep += note + "\n\n";
  // PLAN/PERF blocks lead with the full client-rendered EXPLAIN, then the measurement
  string tr_r, tr_d;
  if (planperf) {
    bool is_perf = rd.job.hit.category == "PERF";
    tr_r = one_nl(ex_r);
    tr_d = one_nl(ex_d);
    // the measured numbers stay in the report even when the rendered EXPLAIN is there:
    // the size of the gap is what the finding is about, and it is not in the UID
    tr_r += rd.repro_ref + "\n";
    tr_d += rd.repro_diff + "\n";
    (void)is_perf;
  } else {
    tr_r = rd.out_ref.empty() ? rd.repro_ref + "\n"
                              : cap_trace(renumber_trace(rd.out_ref, block_head), 8, 80);
    tr_d = rd.out_diff.empty() ? rd.repro_diff + "\n"
                               : cap_trace(renumber_trace(rd.out_diff, block_head), 8, 80);
    if (hidden) { tr_r += ct_r; tr_d += ct_d; }
    // the checkpoint scan compares hashes with the rows discarded, so a confirmed
    // content difference has no row data yet: read the differing table again, with rows
    if (rd.is_checkpoint && !rd.diff_table.empty() && !rd.read_failed) {
      string q = "SELECT * FROM `" + rd.diff_table + "` ORDER BY 1";
      tr_r += one_nl(cap_lines(client_sql(rd, 0, q + ";"), 60));
      tr_d += one_nl(cap_lines(client_sql(rd, 1, q + ";"), 60));
    }
  }
  rep += "Leads to, on " + desc_r + ":\n" + banner_open(sp_r) + "\n" + tr_r + "{noformat}\n\n";
  rep += "Leads to, on " + desc_d + ":\n" + banner_open(sp_d) + "\n" + tr_d;
  if (!crash_note.empty()) rep += crash_note + "\n";
  rep += "{noformat}\n\n";
  if (!planperf) {                                     // literal diff of the two traces
    string fa = g_run.rundir + "/bugdiff" + std::to_string(rd.job.bug) + ".a";
    string fb = g_run.rundir + "/bugdiff" + std::to_string(rd.job.bug) + ".b";
    write_file(fa, tr_r);
    write_file(fb, tr_d);
    RunOut d = run_capture({"diff", "-u", fa, fb});
    std::error_code ec;
    fs::remove(fa, ec);
    fs::remove(fb, ec);
    string body;
    size_t p = 0, ln = 0, kept = 0, dropped = 0;
    while (p < d.out.size()) {
      size_t nl = d.out.find('\n', p);
      if (nl == string::npos) nl = d.out.size();
      string line = d.out.substr(p, nl - p);
      p = nl + 1;
      ln++;
      if (ln <= 2 && (starts_with_i(line, "---") || starts_with_i(line, "+++"))) continue;
      if (kept >= 60) { dropped++; continue; }
      body += line + "\n";
      kept++;
    }
    if (dropped) body += "... (" + std::to_string(dropped) + " more line(s))\n";
    if (!body.empty())
      rep += "Difference, side" + std::to_string(idx_r) + " vs side" + std::to_string(idx_d) +
             ":\n{noformat}\n" + body + "{noformat}\n\n";
  }
  if (!rd.perf_note.empty()) rep += "Perf: " + rd.perf_note + "; the medians above are from the amplified data.\n\n";
  // PLAN/PERF already lead with the plans. Elsewhere a plan explains a difference in the
  // rows a statement returns, touches or leaves behind, and explains nothing about an error
  // code, a warning or a crash.
  bool show_plan = !planperf && plan_explains(rd.job.hit.category) &&
                   (plan_reaches_a_table(ex_r) || plan_reaches_a_table(ex_d));
  if (show_plan && !ex_r.empty())
    rep += "Plan on " + desc_r + ":\n" + banner_open(sp_r) + "\n" + one_nl(ex_r) +
           "{noformat}\n\n";
  if (show_plan && !ex_d.empty())
    rep += "Plan on " + desc_d + ":\n" + banner_open(sp_d) + "\n" + one_nl(ex_d) +
           "{noformat}\n\n";
  rep += sweep.empty() ? "The version sweep did not run, so only the two sides above were "
                         "tested.\n\n"
                       : matrix_block(sweep);
  if (!server_uid.empty()) rep += "Server UID: " + server_uid + "\n";
  rep += "UID: " + uid + "\n";
  // the same defect reached another way: say so, so it is filed against that one
  if (string near = known_near(tail); !near.empty())
    rep += "Near: " + near + "\nA difference already known sits next to this one, same "
           "category and same mechanism on another statement. Read it as the same bug "
           "before filing this as a new one.\n";
  write_file(base + ".report", rep);
  write_log_script(rd, sweep, ver_r, ver_d);
  // the count is what the code block shows: the SETs, the statements, the EXPLAIN
  size_t tc_lines = lines.size() + rd.session_sets.size() +
                    ((planperf && !rd.is_checkpoint && !lines.empty()) ? 1 : 0);
  logline("trial %ld: report written -> %s.report (%zu-line testcase)", rd.job.trial, base.c_str(), tc_lines);
  return uid;
}

// trial-time working copies; the report carries everything (KEEP_ALL_TRIALS keeps them).
// The per-side error logs and cores belong to a crash job alone: one trial can feed
// several bugs, so a non-crash job must not sweep another job's crash evidence away.
static void remove_trial_files(long trial, bool crash) {
  if (g_cfg.keep_all_trials) return;
  std::error_code ec;
  string base = g_run.workdir + "/trial" + std::to_string(trial);
  fs::remove(base + ".sql", ec);
  fs::remove(base + ".diff.txt", ec);
  if (!crash) return;
  for (size_t i = 1; i <= g_sides.size(); i++) {
    fs::remove(base + "-side" + std::to_string(i) + ".err", ec);
    fs::remove(base + "-side" + std::to_string(i) + ".core", ec);
  }
}

// A confirmed bug leaves the reduction here. Its testcase is final and its own servers are
// already stopped, so the version sweep and the report do not need the reduction's pair of
// slots any more. The reduction ends, its budget goes back to the next candidate, and the
// job waits on this queue holding nothing at all: no slots, no worker, no admission charge.
// A small pool of sweep workers drains the queue, so how many sweeps run at once is the
// number of those workers and never a limit on how many bugs can be reduced
struct SweepJob {
  std::unique_ptr<Reducer> rd;
  vector<StreamStmt> lines;
};
static std::mutex g_sweep_q_mtx;
static std::condition_variable g_sweep_q_cv;
static std::deque<SweepJob> g_sweep_q;
static std::atomic<bool> g_sweep_drain{false};         // set when no more jobs can be queued

static void finish_bug_report(Reducer& rd, const vector<StreamStmt>& lines,
                              const vector<SweepRow>& sweep) {
  rd.stage_done("writing the report");
  string reported = write_bug_artifacts(rd, lines, sweep);
  if (!reported.empty()) {
    g_bugs++;
    append_seen("bug" + std::to_string(rd.job.bug), rd.job.uid, rd.job.trial, reported);
  }
  remove_trial_files(rd.job.trial, rd.job.hit.category == "CRASH");  // the report has it all
  rd.stage_done("");
  rd.teardown();
  g_reds_done++;
}

// the sweep runs on two slots of its own, and the report is written where the sweep ends
static void run_sweep_job(SweepJob&& j) {
  Reducer& rd = *j.rd;
  slots_take(2, rd.job.trial, true);
  vector<SweepRow> sweep;
  if (!g_stop.load()) {
    rd.stage_done("version sweep");
    logline("trial %ld: version sweep across the gendirs.sh builds", rd.job.trial);
    g_ver_sweeps++;
    sweep = version_sweep(rd, j.lines);
    g_ver_sweeps--;
    long aff = 0;
    for (auto& r : sweep) aff += r.affected;
    logline("trial %ld: version sweep done - %ld of %zu builds affected", rd.job.trial, aff,
            sweep.size());
  }
  finish_bug_report(rd, j.lines, sweep);
  g_sweeps_pending--;
  slots_give();
}

// a stopping run still drains the queue: a bug that is already confirmed gets its report
static void sweep_worker_loop() {
  MysqlThreadScope mts;
  for (;;) {
    SweepJob j;
    {
      std::unique_lock<std::mutex> lk(g_sweep_q_mtx);
      g_sweep_q_cv.wait(lk, [] { return !g_sweep_q.empty() || g_sweep_drain.load(); });
      if (g_sweep_q.empty()) return;
      j = std::move(g_sweep_q.front());
      g_sweep_q.pop_front();
      g_ver_sweeps_q.store((int)g_sweep_q.size());
    }
    run_sweep_job(std::move(j));
  }
}

static void reduce_one(ReduceJob&& job) {
  auto rdp = std::make_unique<Reducer>();
  Reducer& rd = *rdp;
  rd.job = std::move(job);
  rd.deadline = now_ms() + g_cfg.reduce_timeout * 1000.0;
  vector<StreamStmt> lines = rd.job.stream;
  // Every probe applies the preamble out of band (Reducer::oob_reset), so a second copy
  // in the stream would let a reduction drop those lines and still see a reproduction on
  // a state the testcase no longer names.
  {
    vector<StreamStmt> pre = preamble_sql(rd.job.trial);
    size_t k = 0;
    while (k < pre.size() && k < lines.size() && lines[k].sql == pre[k].sql) k++;
    lines.erase(lines.begin(), lines.begin() + k);
  }
  // a candidate whose diff does not replay is not a bug: count it, free its UID so a
  // later sighting gets a fresh attempt, and write nothing
  // a candidate that never got its replay is unverified, not disproved: it is counted
  // apart from a candidate whose diff was replayed and did not come back
  auto drop_reason = [&](const string& why, bool verified) {
    if (verified) g_stats.unreproduced++;
    else g_stats.unverified++;
    {
      std::lock_guard<std::mutex> lk(g_uid_mtx);
      if (++g_uid_drops[rd.job.uid] < 3) g_uids_seen.erase(rd.job.uid);   // try it again
      else logline("trial %ld: %s dropped three times - muted for this run", rd.job.cand,
                   rd.job.uid.c_str());
    }
    logline("trial %ld: dropped - %s", rd.job.cand, why.c_str());
    rd.stage_set("", -1);
    // a crash keeps its evidence (core + error log); everything else leaves no files
    if (rd.job.hit.category != "CRASH") remove_trial_files(rd.job.trial, false);
    rd.teardown();
  };
  auto drop = [&](const string& why) { drop_reason(why, true); };
  if (g_stop.load()) {
    drop_reason("the run stopped before reduction", false);
    return;
  }
  rd.stage_set("starting the instances", (long)lines.size());
  if (!rd.setup()) {
    drop_reason("the reduction instances did not start" +
                (rd.start_error.empty() ? string() : " (" + rd.start_error + ")"), false);
    return;
  }
  vector<uint8_t> errmap(lines.size(), 0);
  if (rd.sides.size() >= 2 && rd.sides[0].inst.spec && rd.sides[1].inst.spec)
    slots_name_sides({rd.sides[0].inst.spec->idx, rd.sides[1].inst.spec->idx});
  rd.stage_set("replay", (long)lines.size());
  double t_base = now_ms();
  Probe basep = g_stop.load() ? Probe::NO : rd.probe_repeat(lines, false, &errmap);
  if (basep != Probe::REPRO) {
    // a stop measures nothing, so it leaves the candidate unverified, never disproved
    if (g_stop.load()) { drop_reason("the run stopped before the replay finished", false); return; }
    if (rd.budget_spent || basep == Probe::INFRA) {
      drop_reason("the trial replay could not be measured (" +
                  (rd.no_note.empty() ? string("the instances went away") : rd.no_note) + ")",
                  false);
      return;
    }
    string found = trim(rd.job.hit.detail);          // what detection measured, for comparison
    for (auto& ch : found) if (ch == '\n') ch = ';';
    string stmt = trim(rd.job.hit.statement);         // and on which statement, to judge the drop
    for (auto& ch : stmt) if (ch == '\n') ch = ' ';
    if (stmt.size() > 200) stmt = stmt.substr(0, 197) + "...";
    if (!rd.job.hit.diag.empty() || !rd.replay_diag.empty())
      logline("trial %ld: plan diagnosis\n  at detection:\n%s  on replay:\n%s", rd.job.cand,
              rd.job.hit.diag.c_str(), rd.replay_diag.c_str());
    drop("the trial replay did not reproduce the diff in " + std::to_string(rd.attempts_used) +
         " pass(es) (" + (rd.no_note.empty() ? string("no diff on replay") : rd.no_note) +
         "); found as: " + found + "; on: " + stmt);
    return;
  }
  // A step that does not reproduce is retried as often as the first replay needed, which
  // on a 14-pass diff turns every rejected removal into 14 probes and the reduction into a
  // stall. The cap keeps the sporadic case reducible.
  rd.inner_attempts = std::min(rd.attempts_used, std::max(1, g_cfg.reduce_step_attempts));
  if (rd.attempts_used > 1)
    logline("trial %ld: the replay needed %d passes; each reduction step gets %d",
            rd.job.cand, rd.attempts_used, rd.inner_attempts);
  // Chunk elimination costs about 2n probes, so one flat number cannot finish both a
  // 60-statement candidate and a 1600-statement one. The budget is scaled from the probe
  // cost this candidate just measured, and capped so one candidate cannot hold two slots
  // all day.
  {
    double probe_ms = (now_ms() - t_base) / std::max(1, rd.attempts_used);
    double flat = g_cfg.reduce_timeout * 1000.0;
    double budget = std::min(flat * 4, std::max(flat, 2.2 * (double)lines.size() * probe_ms));
    rd.deadline = t_base + budget;
    logline("trial %ld: %zu statements at %.0f ms a probe - reduce budget %.0f s",
            rd.job.cand, lines.size(), probe_ms, budget / 1000.0);
  }
  bool final_ok = false;
  {
    rd.base_ref = rd.repro_ref;
    rd.base_diff = rd.repro_diff;
    size_t n0 = lines.size();
    // errors are often load-bearing, so dropping them all is only attempted once
    {
      vector<StreamStmt> cand;
      for (size_t i = 0; i < lines.size(); i++)
        if (!errmap[i] || (!rd.is_checkpoint && i + 1 == lines.size()))
          cand.push_back(lines[i]);
      if (cand.size() < lines.size() && rd.probe_try(cand) == Probe::REPRO)
        lines = std::move(cand);
    }
    if (rd.job.hit.category == "PERF") amplify_perf(rd, lines);
    reduce_table_slice(rd, lines);
    reduce_lines(rd, lines);
    // rows+columns repeat until stable: a probe-flaked candidate gets retried
    for (int round = 0; round < 3 && !g_stop.load() && now_ms() <= rd.deadline; round++) {
      size_t bytes = 0;
      for (auto& l : lines) bytes += l.sql.size();
      reduce_insert_rows(rd, lines);
      reduce_columns(rd, lines);
      reduce_table_lists(rd, lines);
      reduce_literals(rd, lines);
      size_t after = 0;
      for (auto& l : lines) after += l.sql.size();
      if (after == bytes) break;
    }
    reduce_pinned_stmt(rd, lines);
    reduce_session_sets(rd, lines);
    reduce_names(rd, lines);
    enrich_insert_rows(rd, lines);
    // A timing gap is a property of the data, and every pass above takes rows or columns
    // away, so the slow side gets faster as the testcase shrinks. Amplifying once at the
    // start does not survive that: the gap falls under PERF_MIN_DELTA and the final replay
    // reports a testcase that no longer shows what was found. Amplifying again here is the
    // last thing before the replay, and each round has to reproduce before it is kept.
    if (rd.job.hit.category == "PERF") amplify_perf(rd, lines);
    rd.stage_set("final replay", (long)lines.size());
    logline("trial %ld: reduced %zu -> %zu statements", rd.job.cand, n0, lines.size());
    // the final replay gets its own budget: a reduction that spent the whole one must not
    // leave the verification with no time, which would read as a diff that went away
    rd.budget_spent = false;
    rd.deadline = now_ms() + std::max(120000.0, g_cfg.reduce_timeout * 1000.0);
    final_ok = rd.probe_repeat(lines, true) == Probe::REPRO;
    if (final_ok && rd.attempts_used > 1)
      logline("trial %ld: the final replay needed %d passes", rd.job.cand, rd.attempts_used);
  }
  if (!final_ok) {
    if (g_stop.load()) {                               // measured nothing: not a disproof
      drop_reason("the run stopped before the final replay finished", false);
      return;
    }
    if (rd.budget_spent) {
      drop_reason("the final replay ran out of budget", false);
      return;
    }
    // the trial stream replayed the diff and the reduced testcase does not: the reduction
    // cut something load-bearing, so this one wants a person to look at it
    g_final_fails++;
    logline_alert("trial %ld: the trial-stream replay reproduced and the reduced testcase did "
                  "not - the reduction needs a look", rd.job.trial);
    drop("the reduced testcase did not reproduce (" +
         (rd.no_note.empty() ? string("no diff on replay") : rd.no_note) + ")");
    return;
  }
  rd.job.bug = rd.job.trial;                           // verified twice: now it is a bug
  logline("trial %ld: confirmed as a bug (%s)", rd.job.trial, rd.job.uid.c_str());
  g_reds_report++;                                     // sweep + report stage (TUI stat)
  // The EXPLAIN pair and the crashed side are the last things the report needs from this
  // job's own servers, so both are taken here and the servers then stop. The version sweep
  // runs on the two slots they held, so a sweep costs two slots and not four.
  rd.stage_done("EXPLAIN diffset");
  if (!rd.is_checkpoint && !lines.empty()) {
    rd.ex_ref = explain_pinned(rd, 0, lines.back().sql);
    rd.ex_diff = explain_pinned(rd, 1, lines.back().sql);
  }
  for (size_t i = 0; i < rd.sides.size(); i++)
    if (!rd.sides[i].inst.alive()) { rd.dead_side = (int)i; break; }
  rd.stop_servers();
  rd.shed_data();
  if (g_cfg.version_sweep && !g_sweep_drain.load()) {
    rd.stage_done("waiting for a version sweep");
    g_reds_report--;                                   // it stops holding slots at the return
    g_sweeps_pending++;
    std::lock_guard<std::mutex> lk(g_sweep_q_mtx);
    g_sweep_q.push_back({std::move(rdp), std::move(lines)});
    g_ver_sweeps_q.store((int)g_sweep_q.size());
    g_sweep_q_cv.notify_one();
    return;                                            // the caller frees the pair on return
  }
  finish_bug_report(rd, lines, {});
  g_reds_report--;
}

// one queued candidate, taken by whichever worker is free; the RAM governor gates the start.
// Artifact writing and the version sweep run at the tail of each job, so they
// parallelize with the pool as well.
static void run_reduce_job(ReduceJob&& job) {
  // The slots are charged from the moment the job leaves the queue until the job is done,
  // through every wait inside it, so the budget bounds how many workers a reduction can tie
  // up. The panel counts jobs that hold their slots, so it names work that is running and
  // not work that waits.
  g_reds_admitted++;
  g_red_slots += 2;                                    // charged at admission, not at the take
  bool held = false;
  if (!g_stop.load()) {
    // two sides, for the whole job, and ahead of a trial in the queue for slots: a diff
    // that is not proven yet is worth more than one more trial
    slots_take(2, job.trial, true);
    held = true;
    g_reds_active++;
    set_red_status(job.cand, "waiting for the RAM governor", -1);
    governor_wait("reduction of trial " + std::to_string(job.cand));
  }
  reduce_one(std::move(job));
  if (held) { slots_give(); g_reds_active--; }
  g_red_slots -= 2;
  g_reds_admitted--;
}

// The tables the stream has created up to this point. ANALYZE names them explicitly, so
// the refresh reaches the report testcase as SQL a reader can run.
static void collect_table_names(const string& sql, std::set<string>& live) {
  string up = upper(sql);            // a quoted name must stay readable, so not blanked
  auto ident = [&](size_t p) {                         // the identifier starting at p
    while (p < up.size() && isspace((unsigned char)up[p])) p++;
    if (p < up.size() && up[p] == '`') p++;
    size_t b = p;
    while (p < up.size() && (isalnum((unsigned char)up[p]) || up[p] == '_' || up[p] == '$')) p++;
    return sql.substr(b, p - b);
  };
  for (const char* h : {"CREATE TABLE IF NOT EXISTS ", "CREATE OR REPLACE TABLE ",
                        "CREATE TEMPORARY TABLE ", "CREATE TABLE "}) {
    if (up.rfind(h, 0) != 0) continue;
    string t = ident(strlen(h));
    if (!t.empty()) live.insert(t);
    return;
  }
  for (const char* h : {"DROP TABLE IF EXISTS ", "DROP TABLE "}) {
    if (up.rfind(h, 0) != 0) continue;
    size_t at = strlen(h);
    while (at <= sql.size()) {                         // one name per comma-separated piece
      string t = ident(at);                            // the name, not the CASCADE after it
      if (!t.empty()) live.erase(t);
      size_t c = sql.find(',', at);
      if (c == string::npos) break;
      at = c + 1;
    }
    return;
  }
}

// ANALYZE TABLE over the tables that exist at this point of the stream. PERSISTENT FOR
// ALL reads every column of every table and stores exact counts, so both sides plan from
// the same numbers; it needs MariaDB on every side.
static string stats_refresh_sql(const std::set<string>& live) {
  if (live.empty()) return "";
  string q = "ANALYZE TABLE ";
  bool first = true;
  for (auto& t : live) { q += (first ? "`" : ",`") + t + "`"; first = false; }
  if (g_setup_stat_tables) q += " PERSISTENT FOR ALL";
  return q;
}

// The refresh is part of the stream, at fixed positions. A probe replays it where the
// trial ran it, the reducer can drop it when it is not load-bearing, and the reported
// testcase carries the statistics the finding was measured with. A count kept by the
// harness would move under every cut instead, and vanish below the checkpoint size.
static void insert_stats_refresh(vector<StreamStmt>& stream, long every) {
  if (every <= 0) return;
  vector<StreamStmt> out;
  out.reserve(stream.size() + stream.size() / (size_t)every + 2);
  std::set<string> live;
  long since = 0;
  for (auto& st : stream) {
    collect_table_names(st.sql, live);
    bool refresh = ++since >= every && !live.empty();
    out.push_back(std::move(st));
    if (refresh) { since = 0; out.push_back({stats_refresh_sql(live), true, true}); }
  }
  stream = std::move(out);
}

// returns false when the run must stop
static bool run_trial(long trial, int wid, vector<SideRun>& sides, Lockstep& ls,
                      const vector<StreamStmt>& base, vector<StreamStmt>&& gen) {
  // the panel names each line by the side it runs
  {
    vector<int> idx;
    for (auto& sr : sides) idx.push_back(sr.inst.spec ? sr.inst.spec->idx : (int)idx.size() + 1);
    slots_name_sides(idx);
  }
  // a new session per trial, so nothing at session level survives the trial before it
  for (auto& sr : sides)
    if (!sr.reconnect_all() && sr.inst.alive())
      logline("set %d: side%d: reconnect failed: %s", wid, sr.inst.spec->idx,
              sr.conn.last_error().c_str());
  // the preamble is per trial: its own database, and every pinned setting set again
  vector<StreamStmt> stream = preamble_sql(trial);
  const size_t preamble_n = stream.size();
  // combinatorics: one combination per trial, side 2 only, applied after the preamble
  // because the preamble pins optimizer_switch to the side's own global
  string combo;
  if (!g_combos.empty()) {
    long ci = g_combo_next.fetch_add(1);
    if (ci >= (long)g_combos.size()) {
      static std::atomic<bool> said{false};
      if (!said.exchange(true))
        logline("every optimizer_switch combination has been run (%zu); no more trials",
                g_combos.size());
      g_trials_out.store(true);           // the reductions in flight still finish
      g_red_cv.notify_all();
      return true;
    }
    combo = g_combos[(size_t)ci];
    combo_cursor_save();
    logline("set %d: trial %ld: combination %ld of %zu: %s", wid, trial, ci + 1,
            g_combos.size(), combo.c_str());
  }
  t_combo = combo;
  stream.reserve(stream.size() + base.size() + gen.size());
  for (auto& b : base) stream.push_back(b);
  for (auto& g : gen) stream.push_back(std::move(g));
  insert_stats_refresh(stream, g_cfg.checkpoint_every);
  if (g_cfg.keep_all_trials)
    write_stream_file(g_run.workdir + "/trial" + std::to_string(trial) + ".sql", stream);
  bool want_warn = warning_mode() >= 1;
  double t0 = now_ms();
  long executed = 0, parse_skips = 0;
  bool had_diff = false;
  bool engine_stop = false;          // the engines undid a failed statement differently
  bool timing_stop = false;          // a write met contention or interruption on one side
  bool tx_open = false;              // the stream opened a transaction and has not closed it
  for (size_t k = 0; k < stream.size(); k++) {
    if (g_stop.load()) return false;
    if (k == preamble_n && !combo.empty() && sides.size() > 1 && sides[1].conn.h) {
      string q = "SET SESSION optimizer_switch='" + combo + "'";
      if (mysql_real_query(sides[1].conn.h, q.c_str(), q.size()) != 0)
        logline("set %d: side%d: the combination was refused: %s", wid,
                sides[1].inst.spec->idx, sides[1].conn.last_error().c_str());
    }
    if ((k % 25) == 0) {                             // live position, for the threads panel
      for (size_t i = 0; i < sides.size(); i++) {
        char sb[96];
        snprintf(sb, sizeof(sb), "%zu/%zu stmts", k, stream.size());
        slot_text_set(i, sb);
      }
    }
    const string& sql = stream[k].sql;
    // parse guard: a statement one side cannot parse is skipped everywhere
    if (g_cfg.skip_parse_errors) {
      bool skip = false;
      for (auto& sr : sides)
        if (prepare_check(sr.conn, sql) == 1064) { skip = true; break; }
      if (skip) { parse_skips++; continue; }
    }
    ls.exec_all(sql, want_warn, true);
    executed++;
    if (stmt_opens_tx(sql)) tx_open = true;
    else if (stmt_ends_tx(sql)) tx_open = false;
    // connection lost but server alive: client-side break, reconnect and grade as ERR
    for (size_t i = 0; i < sides.size(); i++) {
      if (ls.outs[i].state == QState::CRASH && sides[i].inst.alive()) {
        logline("set %d: side%d: connection lost (server alive) at line %zu; reconnecting",
                wid, sides[i].inst.spec->idx, k + 1);
        if (sides[i].reconnect_all())
          for (auto& s : session_setup_sql()) mysql_real_query(sides[i].conn.h, s.c_str(), s.size());
        string use_db = "USE " + trial_db(trial);
        if (sides[i].conn.h) mysql_real_query(sides[i].conn.h, use_db.c_str(), use_db.size());
        // combinatorics: the combination is a session setting and it went with the session.
        // Side 2 would otherwise run the rest of the trial on the default switch while the
        // trial, the report and the testcase all name the combination.
        if (i == 1 && !combo.empty() && k >= preamble_n && sides[i].conn.h) {
          string cq = "SET SESSION optimizer_switch='" + combo + "'";
          mysql_real_query(sides[i].conn.h, cq.c_str(), cq.size());
        }
        ls.outs[i].state = QState::ERR;
      }
    }
    // all sides timed out: skip the statement, state stays aligned
    {
      bool all_to = true;
      for (auto& o : ls.outs) if (o.state != QState::TIMEOUT) { all_to = false; break; }
      if (all_to) { g_stats.all_timeouts++; continue; }
    }
    // Contention and interruption are outcomes of timing, not of logic: a lock wait, a
    // deadlock, a statement that ran out of its time or was killed. One side can hit one
    // where the other does not, and a replay does not land the same way, so the statement
    // is not comparable. A statement that writes leaves the sides holding different rows
    // from there on as well, so the trial stops there.
    {
      bool timing = false;
      for (auto& o : ls.outs) if (o.state == QState::ERR && timing_error(o.err)) timing = true;
      if (timing) {
        g_stats.timing_notes++;
        if (!stmt_readonly(sql)) { timing_stop = true; break; }
        continue;
      }
    }
    string cat;
    size_t diff_side = 0;
    for (size_t i = 1; i < sides.size() && cat.empty(); i++) {
      cat = compare_pair(ls.outs[0], ls.outs[i], stream[k].state_only, stream[k].sql);
      if (cat == "WARNING" && !g_cfg.warnings_as_bug) {  // warning-only delta: a note, not a bug
        g_stats.warn_notes++;
        cat.clear();
        continue;
      }
      // The two sides returned as many rows as each other under one top-level LIMIT, and
      // different ones. The sort decides which rows those are, so asking again with a total
      // tiebreaker says whether the two sides disagree about the rows or only tied on the
      // terms they were given.
      if (cat == "RESULT" && stmt_limit_ordered(sql) && ls.outs[0].cols &&
          !ls.outs[0].capped && !ls.outs[i].capped &&
          ls.outs[0].row_count == ls.outs[i].row_count) {
        string tb = order_by_total(stream[k].sql, ls.outs[0].cols);
        if (!tb.empty() && ls.outs[0].rows.size() <= 10000) {
          auto ra = query_rows(sides[0].conn, tb);
          auto rb = query_rows(sides[i].conn, tb);
          if (!ra.empty() && ra == rb) {
            g_limit_ties++;
            g_limit_checked++;                       // this one was shown, not assumed
            cat.clear();
            continue;
          }
        }
      }
      diff_side = i;
    }
    if (!cat.empty()) {
      DiffHit hit{cat, (long)k, sql, "", 0, (int)diff_side};
      for (size_t i = 0; i < sides.size(); i++)
        hit.detail += sides[i].inst.spec->label + ": " + outcome_brief(ls.outs[i]) + "\n";
      g_stats.diffs++;
      had_diff = true;
      if (cat == "CRASH") g_stats.crashes++;
      handle_diff(trial, wid, stream, hit, ls.outs[0], ls.outs[diff_side], sides);
      break;                                         // state diverged: stop this trial
    }
    // Engine axis with a non-transactional side: a DML that fails part-way keeps what it
    // already wrote on that side and is undone whole on a transactional one. The two
    // sides now hold different rows and report the same failure, so nothing after this
    // statement is a comparison of like with like.
    if (g_engine_tx_mixed && stmt_is_dml(sql)) {
      bool all_err = true;
      for (auto& o : ls.outs) if (o.state != QState::ERR) all_err = false;
      if (all_err) { g_stats.engine_stops++; engine_stop = true; break; }
    }
    // Same rows, different order, top-level ORDER BY. With ties on the sort terms that is
    // legal, and without them it is a wrong result. Asking again with a total tiebreaker
    // separates the two: the answer is then one sequence, so two sides that still differ
    // differ about sorting. An error or an unrewritable statement leaves it a note.
    if (ls.outs[0].cols && !ls.outs[0].capped) {
      for (size_t i = 1; i < sides.size(); i++) {
        if (ls.outs[i].capped || ls.outs[0].rows == ls.outs[i].rows ||
            ls.outs[0].multiset_hash != ls.outs[i].multiset_hash)
          continue;
        string tb = order_by_total(stream[k].sql, ls.outs[0].cols);
        bool honoured = true;
        if (!tb.empty() && ls.outs[0].rows.size() <= 10000) {
          auto ra = query_rows(sides[0].conn, tb);
          auto rb = query_rows(sides[i].conn, tb);
          if (!ra.empty() && ra.size() == rb.size()) {
            g_order_checked++;                       // the check ran and had rows to judge
            if (ra != rb) honoured = false;
          }
        }
        if (honoured) { g_stats.order_notes++; break; }
        logline("set %d: trial %ld: the same rows come back in a different order under a "
                "total ORDER BY", wid, trial);
        DiffHit hit{"RESULT", (long)k, sql, "", 0, (int)i, "ordering"};
        for (size_t m = 0; m < sides.size(); m++)
          hit.detail += sides[m].inst.spec->label + ": " + outcome_brief(ls.outs[m]) + "\n";
        g_stats.diffs++;
        had_diff = true;
        handle_diff(trial, wid, stream, hit, ls.outs[0], ls.outs[i], sides);
        break;
      }
    }
    // plan compare: rows-product ratio across sides (outcomes matched above)
    // A plan check refreshes the statistics, and that commits. Inside an open transaction
    // it would commit at a point that moves with the row estimates, so the replay of the
    // same stream need not commit there at all. The check waits for the transaction to end.
    bool plan_check = g_cfg.plan_compare && stmt_explainable(sql);
    if (plan_check && tx_open) g_stats.plan_in_tx++;
    if (plan_check && !tx_open) {
      PlanInfo p0 = explain_plan(sides[0].conn, sql);
      for (size_t i = 1; p0.ok && i < sides.size(); i++) {
        PlanInfo pi = explain_plan(sides[i].conn, sql);
        if (!pi.ok) continue;
        // a flattened subquery or a restructured UNION returns a different number of
        // EXPLAIN rows, so the product moves because the shape moved: not comparable
        if (p0.lines != pi.lines || p0.tables != pi.tables) {
          g_stats.plan_shape++;
          continue;
        }
        // A plan difference one side has already explained. It named the key it declined
        // and the two types it declined it for, where the other vendor takes the same
        // lookup after casting both sides to double and reads the same rows. Between
        // builds of one vendor the same note is a real change and still reports.
        if (!g_same_vendor && (p0.key_declined || pi.key_declined) &&
            access_scan_swap(p0.access, pi.access)) {
          g_stats.plan_explained++;
          continue;
        }
        double hi = std::max(p0.rows_product, pi.rows_product);
        double lo = std::min(p0.rows_product, pi.rows_product);
        bool cross = sides[0].inst.spec->basedir != sides[i].inst.spec->basedir;
        double factor = cross ? g_cfg.plan_factor_cross : g_cfg.plan_factor;
        // the row estimate is one signal; a key traded for a full scan is the other
        bool lined_up = plans_line_up(p0, pi);
        bool ratio = factor > 0 && hi > lo * factor;
        if (!ratio && !lined_up && access_scan_swap(p0.access, pi.access)) {
          g_stats.plan_order++;       // the swap is a position artifact, not a plan change
          continue;
        }
        if (ratio || (lined_up && access_scan_swap(p0.access, pi.access))) {
          // statistics estimates drift on a live server: the delta has to survive
          // two refreshes on both sides before it counts as a plan difference
          if (!plan_delta_holds(sides[0].conn, sides[i].conn, sides[0].inst.spec,
                                sides[i].inst.spec, sql, factor, p0, pi, nullptr)) {
            g_stats.plan_flux++;
            continue;
          }
          hi = std::max(p0.rows_product, pi.rows_product);
          lo = std::min(p0.rows_product, pi.rows_product);
          // on a scan swap the side doing the full scan is the worse one, whatever the
          // estimate says; otherwise the larger estimate is
          bool i_worse = (plans_line_up(p0, pi) && access_scan_swap(p0.access, pi.access))
                             ? scan_side_is_b(p0.access, pi.access)
                             : pi.rows_product > p0.rows_product;
          if (!regression_reportable(sides[0].inst.spec, sides[i].inst.spec, i_worse)) {
            g_stats.improve_notes++;                   // the newer build is the better one
            continue;
          }
          QOutcome o0 = ls.outs[0], oi = ls.outs[i];   // the scans below reuse ls.outs
          string unsynced = first_unsynced_table(ls, sql, i);
          if (!unsynced.empty()) {                     // the data diverged: report that
            DiffHit chit{"CHECKSUM", (long)k, "content of `" + unsynced + "`", "", 0, (int)i};
            for (size_t m = 0; m < ls.outs.size(); m++)
              chit.detail += sides[m].inst.spec->label + ": " + outcome_brief(ls.outs[m]) + "\n";
            g_stats.diffs++;
            had_diff = true;
            handle_diff(trial, wid, stream, chit, ls.outs[0], ls.outs[i], sides);
            break;
          }
          DiffHit hit{"PLAN", (long)k, sql, "", 0, (int)i, plan_mech_of(p0, pi)};
          hit.ref_worse = !i_worse;
          char pb[160];
          snprintf(pb, sizeof(pb), "%s: plan rows-product %.0f access %s\n",
                   sides[0].inst.spec->label.c_str(), p0.rows_product, p0.access.c_str());
          hit.detail = pb;
          snprintf(pb, sizeof(pb), "%s: plan rows-product %.0f access %s\n",
                   sides[i].inst.spec->label.c_str(), pi.rows_product, pi.access.c_str());
          hit.detail += pb;
          hit.diag = plan_diag(sides[0].conn, sides[i].conn, sql,
                               sides[0].inst.spec->label, sides[i].inst.spec->label);
          g_stats.diffs++;
          had_diff = true;
          handle_diff(trial, wid, stream, hit, o0, oi, sides);
          break;
        }
      }
      if (had_diff) break;
    }
    // perf compare: both thresholds on the lockstep timing, then a serial median-of-5
    if (stmt_readonly(sql)) {
      for (size_t i = 1; i < sides.size(); i++) {
        double fast = std::min(ls.outs[0].ms, ls.outs[i].ms);
        double slow = std::max(ls.outs[0].ms, ls.outs[i].ms);
        for (long g = (long)(slow - fast), seen = g_perf_gap_max.load(); g > seen;)
          if (g_perf_gap_max.compare_exchange_weak(seen, g)) break;
        if (!perf_exceeds(fast, slow)) continue;
        double m0 = perf_median5(sides[0].conn, sql);
        double mi = perf_median5(sides[i].conn, sql);
        if (m0 < 0 || mi < 0 || !perf_exceeds(std::min(m0, mi), std::max(m0, mi))) continue;
        bool i_worse = mi > m0;
        if (!regression_reportable(sides[0].inst.spec, sides[i].inst.spec, i_worse)) {
          g_stats.improve_notes++;                     // the newer build is the faster one
          continue;
        }
        PlanInfo p0 = explain_plan(sides[0].conn, sql), pi = explain_plan(sides[i].conn, sql);
        DiffHit hit{"PERF", (long)k, sql, "", 0, (int)i, plan_mech_of(p0, pi)};
        hit.ref_worse = !i_worse;
        char pb[160];
        snprintf(pb, sizeof(pb), "%s: median %.1f ms (5 serial runs) access %s\n",
                 sides[0].inst.spec->label.c_str(), m0, p0.access.c_str());
        hit.detail = pb;
        snprintf(pb, sizeof(pb), "%s: median %.1f ms (5 serial runs) access %s\n",
                 sides[i].inst.spec->label.c_str(), mi, pi.access.c_str());
        hit.detail += pb;
        g_stats.diffs++;
        had_diff = true;
        handle_diff(trial, wid, stream, hit, ls.outs[0], ls.outs[i], sides);
        break;
      }
      if (had_diff) break;
    }
    if (stream[k].checkpoint)                        // the stream says where, so a replay
      if (!checkpoint_compare(ls, trial, wid, (long)k, stream, sides)) { had_diff = true; break; }
  }
  // End-of-trial checkpoint. Not after a stop: the sides are known to hold different rows
  // from the statement that stopped the trial, so the tables differ by definition and where
  // the stop lands moves between runs.
  if (!had_diff && !engine_stop && !timing_stop && !g_stop.load())
    checkpoint_compare(ls, trial, wid, (long)stream.size() - 1, stream, sides);
  for (auto& sr : sides) {
    if (!sr.inst.alive()) {
      logline("set %d: side%d: reviving after crash (attempt %d/3)", wid, sr.inst.spec->idx,
              sr.revivals + 1);
      g_stats.revivals++;
      int sidx = sr.inst.spec->idx;
      if (sidx > 0 && sidx < MAX_SIDE_STATS) g_side_revs[sidx]++;
      if (!revive_side(sr)) {
        logline("set %d: side%d: revive failed - stopping run", wid, sr.inst.spec->idx);
        return false;
      }
    }
  }
  // the trial's database is dropped when the trial ends, out of band: the space and the
  // open tables go with it, and a replay only ever holds the database it replays
  {
    string dq = "DROP DATABASE IF EXISTS " + trial_db(trial);
    for (auto& sr : sides)
      if (sr.conn.h && sr.inst.alive()) mysql_real_query(sr.conn.h, dq.c_str(), dq.size());
  }
  g_stats.trials++;
  g_stats.stmts += executed;
  g_stats.parse_skips += parse_skips;
  double ms = now_ms() - t0;
  g_stats.stmt_ms += (long)ms;
  logline("set %d: trial %ld: %ld stmts (%ld parse-skip), %ld diff(s) total, %.1fs (%.0f stmts/s)",
          wid, trial, executed, parse_skips, g_stats.diffs.load(), ms / 1000.0,
          executed / std::max(0.001, ms / 1000.0));
  return true;
}

// ---------------------------------------------------------------------------
// RAM governor + TUI dashboard
// ---------------------------------------------------------------------------

static int ram_used_pct() {
  FILE* f = fopen("/proc/meminfo", "r");
  if (!f) return 0;
  long total = 0, avail = 0, v;
  char k[64], u[16];
  while (fscanf(f, "%63s %ld %15s", k, &v, u) >= 2) {
    if (strcmp(k, "MemTotal:") == 0) total = v;
    else if (strcmp(k, "MemAvailable:") == 0) { avail = v; break; }
  }
  fclose(f);
  if (total <= 0) return 0;
  return (int)(100 - (avail * 100) / total);
}

// Block until the run dir has room again. A start that goes ahead into a full run dir
// fails on its datadir copy, and a side set whose start fails is retired, so the run
// waits here instead. The wait is bounded: the room a run holds is freed by work that is
// already running, and that work must never end up waiting behind a worker that waits here.
static uint64_t g_rundir_floor_kb = 0;                 // set once a slot's cost is known
static void rundir_wait(const string& what) {
  if (!g_rundir_floor_kb) return;
  bool noted = false;
  double deadline = now_ms() + 120000.0;
  for (;;) {
    if (g_stop.load()) return;
    uint64_t free_kb = fs_free_kb(g_run.rundir);
    if (free_kb >= g_rundir_floor_kb) break;
    if (now_ms() >= deadline) {
      logline("run dir governor: %lu MB free after 120s - %s goes ahead",
              (unsigned long)(free_kb / 1024), what.c_str());
      return;
    }
    if (!noted) {
      logline("run dir governor: %lu MB free (floor %lu MB) - %s waits",
              (unsigned long)(free_kb / 1024), (unsigned long)(g_rundir_floor_kb / 1024),
              what.c_str());
      noted = true;
    }
    usleep(500000);
  }
  if (noted) logline("run dir governor: released - %s continues", what.c_str());
}

// block until RAM use is below the limit (new starts wait; running work continues)
static void governor_wait(const string& what) {
  bool noted = false;
  while (!g_stop.load()) {
    int used = ram_used_pct();
    if (g_cfg.ram_limit_pct <= 0 || used < g_cfg.ram_limit_pct) break;
    if (!noted) {
      logline("RAM governor: %d%% used (limit %d%%) - %s waits", used, g_cfg.ram_limit_pct, what.c_str());
      noted = true;
    }
    usleep(500000);
  }
  if (noted) logline("RAM governor: released - %s continues", what.c_str());
  rundir_wait(what);
}

// afl-style alternate-screen dashboard; keys q/p/r; ~1s refresh.
// Lines are built with visible-width tracking so colors never shift the box borders.
static int term_width() {
  winsize ws{};
  if (ioctl(1, TIOCGWINSZ, &ws) == 0 && ws.ws_col > 10) return ws.ws_col;
  return 100;
}

static int term_height() {
  winsize ws{};
  if (ioctl(1, TIOCGWINSZ, &ws) == 0 && ws.ws_row > 10) return ws.ws_row;
  return 40;
}

struct TuiLine {
  string s;
  size_t vis = 0;
  void add(const char* color, const string& t) {
    if (color) s += color;
    s += t;
    if (color) s += "\x1b[0m";
    vis += t.size();
  }
};

termios g_tui_oldt{};                                // teardown restores these on a hard exit
std::atomic<bool> g_tui_have_oldt{false};

static void tui_thread_fn(double t0) {
  termios oldt{};
  bool have_t = tcgetattr(0, &oldt) == 0;
  if (have_t) {
    g_tui_oldt = oldt;
    g_tui_have_oldt.store(true);
    termios raw = oldt;
    // the dashboard reads single keys and echoes nothing, and Ctrl+S never freezes the
    // output. ISIG stays on, so Ctrl+C stops the run the way it stops any other program.
    raw.c_lflag &= ~(ICANON | ECHO);
    raw.c_iflag &= ~(IXON | IXOFF);
    raw.c_cc[VMIN] = 0; raw.c_cc[VTIME] = 0;
    tcsetattr(0, TCSANOW, &raw);
  }
  printf("\x1b[?1049h\x1b[?25l\x1b[2J");
  fflush(stdout);
  const char* TTL = "\x1b[1;36m";                    // bold cyan
  const char* DIM = "\x1b[38;5;245m";                // grey labels
  const char* OK  = "\x1b[32m";
  const char* WRN = "\x1b[33m";
  const char* BAD = "\x1b[1;31m";
  const char* BUG = "\x1b[1;35m";
  const char* BLD = "\x1b[1;38;5;245m";              // the key of a legend line
  const char* BLU = "\x1b[94m";                      // a reduction
  const char* INI = "\x1b[38;5;173m";                // server init, the orange the screen
                                                     // lister gives pr/ge/s screens
  while (!g_stop.load()) {
    char ch;
    while (read(0, &ch, 1) == 1) {
      if (ch == 'q') { g_stop.store(true); logline("TUI: q pressed - stopping"); }
      else if (ch == 'p') {
        g_auto_pause.store(false);
        g_pause.store(!g_pause.load());
        logline("TUI: %s", g_pause.load() ? "paused" : "resumed");
      }
      else if (ch == 'r') {
        bool on = !g_reduce_now.load();
        g_reduce_now.store(on);
        logline("TUI: reduce-now %s", on ? "on - the reductions drain before the next trial"
                                        : "off");
        g_red_cv.notify_all();
      }
    }
    int W = std::clamp(term_width() - 1, 78, 240);   // screen width minus one
    int inner = W - 2;
    string frame;
    auto rule = [&](const char* lft, const char* rgt, const string& title) {
      string ln = lft;
      int used = 0;
      if (!title.empty()) {
        ln += "─ " + title + " ";
        used = (int)title.size() + 3;
      }
      for (int i = used; i < inner; i++) ln += "─";
      ln += rgt;
      frame += ln + "\x1b[K\n";
    };
    auto push = [&](TuiLine& L) {
      string ln = "│";
      ln += L.s;
      for (size_t i = L.vis; i < (size_t)inner; i++) ln += ' ';
      ln += "│\x1b[K\n";
      frame += ln;
    };
    int cw = inner / 4;                              // four aligned stat columns
    auto n2s = [](long v) { return std::to_string(v); };
    double up = (now_ms() - t0) / 1000.0;
    long st = g_stats.stmts.load(), tr = g_stats.trials.load();
    long diffs = g_stats.diffs.load(), crashes = g_stats.crashes.load();
    long bugs = g_bugs.load();
    size_t red_q;
    {
      std::lock_guard<std::mutex> lk(g_red_mtx);
      red_q = g_red_queue.size();
    }
    // the diffs still to work through: queued for reduction plus the jobs running now
    long todo = (long)red_q + g_reds_admitted.load();
    int ram = ram_used_pct();

    rule("┌", "┐", "");
    {
      TuiLine L;
      string title = string(" corlogic ") + CORLOGIC_VERSION;
      char rb[80];
      snprintf(rb, sizeof(rb), "up %02d:%02d:%02d  [q]uit [p]ause [r]educe-now ",
               (int)up / 3600, ((int)up / 60) % 60, (int)up % 60);
      string right = rb;
      // a paused run says so where the eye already is, next to the clock
      string paused = g_pause.load() ? "PAUSED  " : string();
      // the results dir, then the live dir on /dev/shm. A long path keeps its tail, so the
      // header never breaks the frame
      string pre = "  ", wd = g_run.workdir + "  " + g_run.rundir;
      int room = inner - (int)title.size() - (int)pre.size() - (int)right.size() -
                 (int)paused.size() - 2;
      if (room < 8) room = 8;
      if ((int)wd.size() > room) wd = "..." + wd.substr(wd.size() - (room - 3));
      L.add(TTL, title);
      L.add(nullptr, pre + wd);
      if (L.vis + paused.size() + right.size() + 2 < (size_t)inner)
        L.add(nullptr, string(inner - L.vis - paused.size() - right.size(), ' '));
      else L.add(nullptr, "  ");
      if (!paused.empty()) L.add(BAD, paused);
      L.add(DIM, right);
      push(L);
    }
    rule("├", "┤", "");
    // the stat grid, built first so a column's label field is as wide as its longest
    // label; two spaces follow it, so every value in a column starts in the same place
    {
      // a cell carries its value in the forms it can take, longest first: the render
      // picks the first one that fits the column
      struct Cell { const char* label; vector<string> forms; const char* vc;
                    string tail = string(); const char* tc = nullptr; };
      char wb[48];
      char wbs[48];                                  // the same cell, one word narrower
      char wbn[48];                                  // and the counts on their own
      snprintf(wb, sizeof(wb), "%d/%d%s", g_slots.in_use(), g_slots.total(),
               g_pause.load() ? " PAUSED" : (g_reduce_now.load() ? " REDUCING" : ""));
      snprintf(wbs, sizeof(wbs), "%d/%d%s", g_slots.in_use(), g_slots.total(),
               g_pause.load() ? " PAUSED" : (g_reduce_now.load() ? " REDUCE" : ""));
      snprintf(wbn, sizeof(wbn), "%d/%d", g_slots.in_use(), g_slots.total());
      char rb[48], rbs[48];                            // used/governor, then used alone
      snprintf(rb, sizeof(rb), "%d%%/%d%%", ram, g_cfg.ram_limit_pct);
      snprintf(rbs, sizeof(rbs), "%d%%", ram);
      char sb[48], sb2[48], sb3[48];
      double qps = g_qexec.load() / std::max(0.001, up);
      snprintf(sb, sizeof(sb), "%.0f queries/s", qps);
      snprintf(sb2, sizeof(sb2), "%.0f q/s", qps);
      snprintf(sb3, sizeof(sb3), "%.0f", qps);
      int rep = g_reds_report.load() + g_sweeps_pending.load();
      int red = std::max(0, g_reds_active.load() - g_reds_report.load());
      long lines_sum = 0, lines_n = 0;
      {
        std::lock_guard<std::mutex> lk(g_status_mtx);
        for (auto& kv : g_red_lines) { lines_sum += kv.second; lines_n++; }
      }
      // the average testcase size rides along with the count, in whatever room the
      // column has; the threads panel carries the per-reducer line counts
      vector<string> redtxt;
      // every counted job holds two slots, so this is the slots they hold and not a guess
      if (lines_n) {
        string avg = n2s(lines_sum / lines_n);
        redtxt.push_back(n2s(red) + " ~" + avg + "l/tc " + n2s(red * 2) + "w");
        redtxt.push_back(n2s(red) + " ~" + avg + "l/tc");
      }
      redtxt.push_back(n2s(red) + " " + n2s(red * 2) + "w");
      redtxt.push_back(n2s(red));
      long vsr = g_ver_sweeps.load(), vsq = g_ver_sweeps_q.load();
      vector<string> vsw;                               // a queued sweep holds no thread
      if (vsq) vsw.push_back(n2s(vsr) + " " + n2s(vsq) + "q");
      vsw.push_back(n2s(vsr));
      int ram_bad = g_cfg.ram_limit_pct > 0 ? g_cfg.ram_limit_pct : 85;
      int ram_wrn = std::max(1, ram_bad - 10);
      long ff = g_final_fails.load();                  // a reduced testcase that stopped
      // the second number is part of the first, so the cell says so where it has the room
      vector<string> nrepro;                           // reproducing needs a look
      if (ff) {
        nrepro.push_back(n2s(g_stats.unreproduced.load()) + ", " + n2s(ff) + " of them tc");
        nrepro.push_back(n2s(g_stats.unreproduced.load()) + ", " + n2s(ff) + " tc");
      }
      nrepro.push_back(n2s(g_stats.unreproduced.load()));
      vector<vector<Cell>> grid = {
        // "threads" for easy understanding: a slot is one server, one thread waits on it
        {{"threads", {wb, wbs, wbn},
          g_pause.load() ? BAD : (g_reduce_now.load() ? WRN : nullptr)},
         // red at the point the governor holds a trial back, amber ten points before it
         {"RAM", {rb, rbs}, ram >= ram_bad ? BAD : (ram >= ram_wrn ? WRN : OK)},
         // done out of the number asked for; no number asked for means it runs on
         {"trials", {g_cfg.trials > 0 ? n2s(tr) + "/" + n2s(g_cfg.trials) : n2s(tr), n2s(tr)},
          nullptr},
         {"speed", {sb, sb2, sb3}, nullptr}},
        {{"stmts", {n2s(st)}, nullptr},
         {"parse-skips", {n2s(g_stats.parse_skips.load())}, nullptr},
         {"timeouts", {n2s(g_stats.all_timeouts.load())}, nullptr},
         // same rows on both sides, in a different order
         {"order-only", {n2s(g_stats.order_notes.load())}, nullptr}},
        {{"diffs", {n2s(diffs)}, diffs ? WRN : OK,
          todo ? " " + n2s(todo) + " todo" : string(), OK},
         {"crashes", {n2s(crashes)}, crashes ? BAD : OK},
         {"known-muted", {n2s(g_known_matches.load())}, nullptr},
         {"improvements", {n2s(g_stats.improve_notes.load())}, nullptr}},
        {{"candidates", {n2s(g_cands.load())}, nullptr},
         {"ver-sweeps", vsw, vsr ? WRN : nullptr},
         {"dup-muted", {n2s(g_dup_diffs.load())}, nullptr},
         {"not-repro", nrepro, ff ? BAD : nullptr}},
        {{"to-reduce", {n2s((long)red_q)}, red_q ? WRN : nullptr},   // the bug pipeline
         {"reducing", redtxt, red ? WRN : nullptr},
         {"report-gen", {n2s(rep)}, rep ? WRN : nullptr},
         {"bugs", {n2s(bugs)}, bugs ? BUG : OK}},
      };
      vector<int> lw(4, 0);
      for (auto& row : grid)
        for (size_t c = 0; c < row.size() && c < lw.size(); c++)
          lw[c] = std::max(lw[c], (int)strlen(row[c].label));
      for (auto& row : grid) {
        TuiLine L;
        for (size_t c = 0; c < row.size(); c++) {
          char b[256];
          snprintf(b, sizeof(b), " %-*s  ", lw[c], row[c].label);
          L.add(DIM, b);
          int vw = std::max(4, cw - lw[c] - 3);
          int tl = (int)row[c].tail.size();             // the second figure, if it fits
          if (tl && tl + 1 >= vw) tl = 0;
          string val = row[c].forms.empty() ? string() : row[c].forms.back();
          for (auto& f : row[c].forms)
            if ((int)f.size() + tl <= vw) { val = f; break; }
          val = fit_number(val, vw - tl);
          if ((int)val.size() > vw - tl) val = val.substr(0, (size_t)std::max(0, vw - tl));
          L.add(row[c].vc, val);
          int used = (int)val.size();
          if (tl) { L.add(row[c].tc, row[c].tail); used += tl; }
          L.add(nullptr, string((size_t)std::max(0, vw - used), ' '));
        }
        push(L);
      }
    }
    rule("├", "┤", "sides");
    {
      // one short line per side: what it is, its part in the run, and its restarts.
      // Only the field names are dim, as in the counters above.
      auto side_label = [](const SideSpec& s) {         // "side1 X" reads as "side 1: X"
        string lab = s.label, pre = "side" + std::to_string(s.idx);
        if (lab.rfind(pre, 0) == 0)
          lab = "side " + std::to_string(s.idx) + ":" + lab.substr(pre.size());
        return lab;
      };
      int lw = 0;
      for (auto& s : g_sides) lw = std::max(lw, (int)side_label(s).size());
      for (auto& s : g_sides) {
        TuiLine L;
        char b[192];
        snprintf(b, sizeof(b), " %-*.*s  ", lw, lw, side_label(s).c_str());
        L.add(nullptr, b);
        L.add(nullptr, s.idx == 1 ? "reference  " : "compared   ");
        if (s.idx < MAX_SIDE_STATS && g_sides.size() > 2) {
          // with one compared side its diff count is the run total already on screen
          L.add(DIM, "diffs ");
          snprintf(b, sizeof(b), "%-7ld", g_side_diffs[s.idx].load());
          L.add(nullptr, b);
        }
        if (s.idx < MAX_SIDE_STATS) {                  // every side, the reference too
          L.add(DIM, "restarts ");
          snprintf(b, sizeof(b), "%ld", g_side_revs[s.idx].load());
          L.add(nullptr, b);
        }
        push(L);
      }
    }
    // the thread statuses that do not explain themselves. Shown under the panel when the
    // terminal is tall enough to spare the rows, so a short screen loses the glossary
    // rather than the panel
    static const char* const gloss[] = {
      "version sweep: final testcase run on every MD/MS build",
      "ver-sweeps: 2 12q: 2 sweeps running, 12 queued",
      "EXPLAIN diffset: both sides' plan for the last statement",
      "final replay: proving the reduced testcase still differs",
      "writing the report: report, testcase and log script",
      "table slice: keeping only the tables the diff needs",
      "server init: a fresh datadir, then the servers come back",
      "session init: dropping preamble SETs the diff can spare",
      "reduction passes: chunks, rows, cols, table, literals",
      "rename: sparse names go dense, a family of one goes bare",
      "enrich rows: a lone data row grows to three when the diff holds",
      "not-repro 6, 2 of them tc: 6 dropped, 2 with a testcase",
      "pinned: trimming clauses from the last statement",
      "amplify: growing the data until a timing gap is plain",
    };
    const int gn = (int)(sizeof(gloss) / sizeof(gloss[0]));
    // each column is as wide as its own widest entry, so what sits between two columns is
    // a gap and not the slack of a fixed cell. Two spaces between columns, one when the
    // width is tight, and a single column when even one space will not fit. One space is
    // always left free on the right
    int gcols = 1, ggap = 2, grows = gn;
    vector<int> gw;
    for (int c = 3; c >= 2 && gcols == 1; c--) {
      int rows = (gn + c - 1) / c;
      if ((c - 1) * rows >= gn) continue;            // that column count leaves one empty
      vector<int> w(c, 0);
      for (int i = 0; i < gn; i++) w[i / rows] = std::max(w[i / rows], (int)strlen(gloss[i]));
      int sum = 0;
      for (int x : w) sum += x;
      for (int g = 2; g >= 1; g--)
        if (1 + sum + g * (c - 1) + 1 <= inner) {
          gcols = c; ggap = g; grows = rows; gw = w;
          break;
        }
    }
    if (gcols == 1) {
      gw.assign(1, 0);
      for (int i = 0; i < gn; i++) gw[0] = std::max(gw[0], (int)strlen(gloss[i]));
      gw[0] = std::min(gw[0], std::max(1, inner - 2));
    }
    bool show_gloss = term_height() - (12 + (int)g_sides.size()) - (grows + 1) >= 3;
    rule("├", "┤", "threads");
    {
      // what every thread is doing; the panel fills the rest of the screen
      int fixed = 12 + (int)g_sides.size();            // rules + stat rows + side rows
      if (show_gloss) fixed += grows + 1;              // the glossary and its rule
      int panelrows = std::max(3, term_height() - fixed);
      vector<string> cells;
      {
        std::lock_guard<std::mutex> lk(g_status_mtx);
        for (size_t i = 0; i < g_slot_text.size(); i++) {   // one line per busy slot
          if (g_slot_text[i].empty()) continue;
          char b[192];
          snprintf(b, sizeof(b), "t%-3zu %s", i + 1, g_slot_text[i].c_str());
          cells.push_back(b);
        }
      }
      int cols = std::max(1, inner / 40);
      int colw = inner / cols;
      int need = ((int)cells.size() + cols - 1) / cols;
      if (need > panelrows) {                          // last cell says what is not shown
        int fits = panelrows * cols;
        long more = (long)cells.size() - fits + 1;
        cells.resize(std::max(0, fits - 1));
        cells.push_back("... and " + std::to_string(more) + " more");
        need = panelrows;
      }
      for (int r = 0; r < panelrows; r++) {
        TuiLine L;
        for (int c = 0; c < cols; c++) {
          size_t i = (size_t)(c * need + r);
          string t = (r < need && i < cells.size()) ? cells[i] : string();
          char b[256];
          snprintf(b, sizeof(b), " %-*.*s", colw - 1, colw - 1,
                   fit_cell(t, (size_t)std::max(1, colw - 1)).c_str());
          // a trial line is grey like the labels; work on a candidate stands out green, a
          // reduction blue within that, and a server coming up orange
          bool ini = t.find("server init") != string::npos;
          bool red = t.find("reduc") != string::npos;
          bool bug = red || t.find("replay") != string::npos ||
                     t.find("sweep") != string::npos || t.find("report") != string::npos ||
                     t.find("instances") != string::npos;
          L.add(ini ? INI : red ? BLU : (bug ? OK : DIM), b);
        }
        push(L);
      }
    }
    if (show_gloss) {
      rule("├", "┤", "thread status legend");
      for (int r = 0; r < grows; r++) {
        TuiLine L;
        for (int c = 0; c < gcols; c++) {
          int i = c * grows + r;
          L.add(nullptr, string(c ? (size_t)ggap : (size_t)1, ' '));
          string t = i < gn ? fit_cell(gloss[i], (size_t)std::max(1, gw[c])) : string();
          size_t k = t.find(':');                      // the status itself, then what it means
          if (k == string::npos) {
            L.add(DIM, t);
          } else {
            L.add(BLD, t.substr(0, k + 1));
            L.add(DIM, t.substr(k + 1));
          }
          if (c + 1 < gcols)
            L.add(nullptr, string((size_t)std::max(0, gw[c] - (int)t.size()), ' '));
        }
        push(L);
      }
    }
    rule("└", "┘", "");
    printf("\x1b[H%s\x1b[J", frame.c_str());
    fflush(stdout);
    for (int i = 0; i < 10 && !g_stop.load(); i++) usleep(100000);
  }
  printf("\x1b[?25h\x1b[?1049l");
  fflush(stdout);
  if (have_t) tcsetattr(0, TCSANOW, &oldt);
  g_tui_active.store(false);
}

// ---------------------------------------------------------------------------
// the worker pool: one pool, and any worker does any kind of work
// ---------------------------------------------------------------------------
// A worker takes whatever is next: a queued candidate to reduce, verify and report, or
// the next trial. The slot pool is what bounds the box, so trials and reductions share
// it instead of each having a fixed share. A trial's servers live in a set that is
// handed back after the trial, so the next trial reuses them.
struct SideSet {
  int id = 0;
  vector<SideRun> sides;
  std::unique_ptr<Lockstep> ls;
  std::future<vector<StreamStmt>> pre;               // the next trial's SQL, generated ahead
};

static std::mutex g_sets_mtx;
static std::condition_variable g_sets_cv;
static vector<std::unique_ptr<SideSet>> g_sets;      // every set that was created
static vector<SideSet*> g_sets_free;
static int g_sets_max = 1;
static int g_set_seq = 0;                            // ids are never reused: a dropped set
                                                     // would otherwise pass its dir on
static std::atomic<int> g_sets_live{0};              // sets whose sides came up

// a set that will not come back leaves nothing behind: its datadirs are the largest
// thing the run holds, and the set that replaces it needs the room
static void set_dir_remove(int id) {
  std::error_code ec;
  fs::remove_all(g_run.rundir + "/w" + std::to_string(id), ec);
}

static void set_prefetch(SideSet& s) {
  s.pre = std::async(std::launch::async, [id = s.id] { return generator_batch(id); });
}

// bring one set of sides up, on its own instances under <rundir>/w<N>/
static bool set_start(SideSet& s) {
  governor_wait("side set " + std::to_string(s.id) + " start");
  s.sides.resize(g_sides.size());
  for (size_t i = 0; i < g_sides.size(); i++) {
    SideRun& sr = s.sides[i];
    sr.tpl = template_for(g_sides[i]);
    sr.inst.spec = &g_sides[i];
    sr.inst.set_paths(g_run.rundir + "/w" + std::to_string(s.id) + "/side" +
                      std::to_string(g_sides[i].idx));
    if (!sr.inst.start_fresh(sr.tpl) || !sr.reconnect_all()) {
      string why = start_error_from_log(sr.inst.errlog);
      logline("side set %d: side%d did not start%s%s", s.id, g_sides[i].idx,
              why.empty() ? "" : " - ", why.c_str());
      for (auto& done : s.sides) { done.conn.close(); done.ctl.close(); done.inst.stop(true); }
      s.sides.clear();
      return false;
    }
  }
  s.ls = std::make_unique<Lockstep>(s.sides);
  set_prefetch(s);
  return true;
}

// A start can fail on a passing shortage rather than on anything about the run, so it is
// retried before it counts. With no set left the run pauses instead of stopping: a pause
// can be lifted with 'p' once there is room again, where a stop cannot be undone.
static void sets_gone_pause() {
  if (g_pause.load()) return;
  logline("no side set is up - pausing; the run resumes itself once a set starts again");
  g_auto_pause.store(true);
  g_pause.store(true);
}

// an idle set, else a new one while the pool has room for it
static SideSet* set_take() {
  std::unique_lock<std::mutex> lk(g_sets_mtx);
  for (;;) {
    if (g_stop.load()) return nullptr;
    if (!g_sets_free.empty()) {
      SideSet* s = g_sets_free.back();
      g_sets_free.pop_back();
      return s;
    }
    if ((int)g_sets.size() < g_sets_max) {
      g_sets.push_back(std::make_unique<SideSet>());
      SideSet* s = g_sets.back().get();
      s->id = ++g_set_seq;
      lk.unlock();
      bool up = false;
      for (int a = 1; a <= 3 && !up && !g_stop.load(); a++) {
        up = set_start(*s);
        if (!up) {
          logline("side set %d: start attempt %d/3 failed", s->id, a);
          if (a < 3) sleep(2);
        }
      }
      if (!up) {
        int id = s->id;
        logline("side set %d: start failed - running with %d set(s)", id,
                g_sets_live.load());
        {                                    // the dead set must not hold a place in the max
          std::lock_guard<std::mutex> lk2(g_sets_mtx);
          for (size_t k = 0; k < g_sets.size(); k++)
            if (g_sets[k].get() == s) { g_sets.erase(g_sets.begin() + k); break; }
        }
        set_dir_remove(id);
        g_sets_cv.notify_all();
        if (g_sets_live.load() == 0) sets_gone_pause();
        return nullptr;
      }
      g_sets_live++;
      logline("side set %d up (%zu sides)", s->id, s->sides.size());
      return s;
    }
    if (g_sets_live.load() == 0) return nullptr;       // nothing left that can run a trial
    g_sets_cv.wait_for(lk, std::chrono::milliseconds(200));
  }
}
// An automatic pause belongs to the run, so the run lifts it as well. What retired the
// last set - the box out of memory, the run dir out of room - can pass, so a set start is
// tried again now and then, and the first one that comes up puts the run back to work.
static void auto_pause_retry() {
  if (!g_auto_pause.load() || !g_pause.load() || g_stop.load()) return;
  static std::mutex m;
  static double next = 0;
  std::unique_lock<std::mutex> lk(m, std::try_to_lock);
  if (!lk.owns_lock() || now_ms() < next) return;
  next = now_ms() + 30000.0;
  if (g_rundir_floor_kb && fs_free_kb(g_run.rundir) < g_rundir_floor_kb) return;
  if (g_cfg.ram_limit_pct > 0 && ram_used_pct() >= g_cfg.ram_limit_pct) return;
  SideSet* s = set_take();
  if (!s) return;
  {
    std::lock_guard<std::mutex> lk2(g_sets_mtx);
    g_sets_free.push_back(s);
  }
  g_sets_cv.notify_all();
  bool mine = true;              // a key press in the meantime owns the pause now, not the run
  if (!g_auto_pause.compare_exchange_strong(mine, false)) return;
  g_pause.store(false);
  g_red_cv.notify_all();
  logline("side set %d is up - the automatic pause is lifted", s->id);
}

// A set is restarted from a fresh datadir before it goes back on the free list, so every
// trial runs on a server with no history: the same state a reduction probe measures on.
// Doing it here rather than on take keeps the restart off the next trial's critical path,
// and set_take never hands out a set that is still coming up.
static void set_give(SideSet* s) {
  if (g_stop.load()) return;                          // the run is closing: nothing reuses it
  slot_text_all("server init");
  bool ok = restart_sides_fresh(s->sides);   // the Lockstep holds the sides by reference,
  {                                         // so a reconnect in place is all it needs
    std::lock_guard<std::mutex> lk(g_sets_mtx);
    if (ok) g_sets_free.push_back(s);
  }
  if (!ok) {
    int id = s->id;
    logline("side set %d: restart failed - the set is retired", id);
    // Dropped, not parked. A retired set left in the list holds a place in the max, and
    // while it does, set_take can never build the set that replaces it: with every set
    // retired the run has nothing to run a trial on and no way back
    for (auto& sr : s->sides) { sr.conn.close(); sr.ctl.close(); sr.inst.stop(true); }
    std::unique_ptr<SideSet> dead;
    {
      std::lock_guard<std::mutex> lk(g_sets_mtx);
      for (size_t k = 0; k < g_sets.size(); k++)
        if (g_sets[k].get() == s) {
          dead = std::move(g_sets[k]);
          g_sets.erase(g_sets.begin() + k);
          break;
        }
    }
    dead.reset();                        // its prefetch is joined here, off the lock
    set_dir_remove(id);
    if (--g_sets_live == 0) sets_gone_pause();
  }
  g_sets_cv.notify_all();
}

static std::atomic<int> g_trials_active{0};            // trials being run right now

static void run_one_trial(long t, const vector<StreamStmt>& base) {
  slots_take((int)g_sides.size(), t);                  // one slot per side, for this trial
  // named before the wait, not after it: set_take blocks while every set is restarting,
  // and a slot held with nothing to say is a thread the panel drops off the list
  slot_text_all("waiting for a server set");
  SideSet* set = set_take();
  // no set to be had: hand the slots back and leave the box a moment, rather than taking
  // them straight back and asking again
  if (!set) { slots_give(); if (!g_stop.load()) usleep(200000); return; }
  int wid = set->id;
  slot_text_all("waiting for generated SQL");
  vector<StreamStmt> gen = set->pre.get();
  set_prefetch(*set);
  bool cont = run_trial(t, wid, set->sides, *set->ls, base, std::move(gen));
  // The slots stay held while the set is copying a fresh datadir and waiting for a socket:
  // a slot is one server, and those two servers are neither free nor idle. Giving them
  // back early only lets another worker take slots it cannot run anything on, because a
  // trial needs a set as well. The set is withheld from g_sets_free until it is up, so
  // nobody can take a half-started set, and the number of sets still bounds how many
  // servers a run holds.
  set_give(set);
  slots_give();
  if (!cont) g_stop.store(true);
}

static void worker_loop(const vector<StreamStmt>& base, std::atomic<long>& next_trial) {
  MysqlThreadScope mts;
  while (!g_stop.load()) {
    // a candidate that is waiting comes first: proving a diff is worth more than one
    // more trial, and the slot pool keeps both sides of that honest
    ReduceJob job;
    bool got = false;
    {
      std::unique_lock<std::mutex> lk(g_red_mtx);
      if (g_pause.load()) {                 // a pause takes no new trial and no new candidate
        g_red_cv.wait_for(lk, std::chrono::milliseconds(200));
        lk.unlock();
        auto_pause_retry();
        continue;
      }
      if (g_reduce_now.load() &&
          reduce_now_over(g_red_queue.size(), g_reds_admitted.load(), g_red_max)) {
        g_reduce_now.store(false);
        logline("reduce-now: the reductions left fit the pool, so trials start again");
      }
      // what reductions may hold is weighed against the queue on every pass, so discovery
      // keeps running while candidates are proven
      int budget = reduction_slot_budget(g_slots.total() - g_sweep_slots, (int)g_sides.size(),
                                         g_red_queue.size(), g_reds_admitted.load());
      if (!g_red_queue.empty() && reduction_admits(g_red_slots.load(), budget)) {
        job = std::move(g_red_queue.front());
        g_red_queue.pop_front();
        got = true;
      } else if (g_reduce_now.load()) {      // reduce-now: no new trial while the queue is full
        g_red_cv.wait_for(lk, std::chrono::milliseconds(200));
        continue;
      } else if (g_trials_out.load()) {
        // nothing left to discover: stop once nothing can queue another candidate
        if (g_trials_active.load() == 0 && g_reds_admitted.load() == 0) break;
        g_red_cv.wait_for(lk, std::chrono::milliseconds(200));
        continue;
      }
    }
    if (got) { run_reduce_job(std::move(job)); continue; }
    long t = next_trial.fetch_add(1);
    if (g_cfg.trials != 0 && t > g_trial_base + g_cfg.trials) {   // TRIALS is per run
      g_trials_out.store(true);
      g_red_cv.notify_all();
      continue;
    }
    g_trials_active++;
    run_one_trial(t, base);
    g_trials_active--;
    g_red_cv.notify_all();                              // may have been the last trial
  }
}

static int run_discovery(vector<Instance>&& preflight) {
  // the slot pool is the box budget: one slot is one running server, a trial takes one
  // per side and a reduction takes two, so a set of sides can only run while the pool
  // has room for it
  // The pre-flight is still up, so the cost of a slot can be measured off it: the datadir
  // template each side was built from, and the resident set of the server running on it.
  uint64_t slot_ram = 0, slot_shm = 0;
  for (auto& inst : preflight) {
    slot_ram = std::max(slot_ram, rss_kb(inst.pid));
    if (!inst.datadir.empty()) slot_shm = std::max(slot_shm, dir_kb(inst.datadir));
  }
  // What a start needs is room for one fresh set of datadirs, and the copy of them is what
  // fails when it is not there. The floor keeps that much back, with room to spare, so a
  // start waits for the room instead of failing for the want of it
  g_rundir_floor_kb = slot_shm * (uint64_t)g_sides.size() * 4;
  if (g_cfg.workers <= 0) {
    auto mem = meminfo();
    PoolFit f = pool_fit(std::max(1u, std::thread::hardware_concurrency()), mem.second,
                         g_cfg.ram_limit_pct, fs_free_kb(g_run.rundir), slot_ram, slot_shm);
    g_cfg.workers = f.chosen;
    logline("pool: %d slots (%s), a slot costs %lu MB of RAM and %lu MB of run dir; "
            "cpu allows %d, RAM %d, run dir %d",
            f.chosen, f.bound, (unsigned long)(slot_ram / 1024),
            (unsigned long)(slot_shm / 1024), f.by_cpu, f.by_ram, f.by_shm);
  }
  int nslots = std::max((int)g_sides.size(), g_cfg.workers);
  g_slots.init(nslots);
  {
    std::lock_guard<std::mutex> lk(g_status_mtx);
    g_slot_text.assign((size_t)nslots, string());
  }
  g_sets_max = std::max(1, nslots / (int)g_sides.size());
  int nsweep = g_cfg.version_sweep ? sweep_worker_count(nslots, g_cfg.ver_sweep_jobs) : 0;
  g_sweep_slots = nsweep * 2;
  g_red_slot_max = reduction_slot_ceiling(nslots - g_sweep_slots, (int)g_sides.size());
  g_red_max = g_red_slot_max / 2;                      // the same budget in whole jobs
  // The pre-flight instances are not reused: the probe has run against them, so their
  // datadir has a history and a trial on them would not be measuring the same server a
  // reduction probe does. Every set comes up fresh as work asks for it.
  for (auto& inst : preflight) inst.stop(true);
  preflight.clear();
  { std::error_code ec; fs::remove_all(g_run.rundir + "/preflight", ec); }
  vector<StreamStmt> base;                           // the preamble is added per trial
  bool part_ok = g_cfg.partitioning > 0;
  for (auto& c : g_caps) part_ok = part_ok && c.has_partitioning;
  for (auto& s : seed_schema_sql(part_ok)) base.push_back(std::move(s));
  logline("stream base: %zu seed statements; %ld generated per trial",
          base.size(), g_cfg.queries_per_trial);
  bool tui_on = g_cfg.tui == "1" || (g_cfg.tui == "auto" && isatty(1));
  std::thread tui;
  if (tui_on) {
    g_tui_active.store(true);
    tui = std::thread(tui_thread_fn, now_ms());
  }
  logline("%d slots, one pool: trials, reductions, replays and reports all draw from it "
          "- up to %d trial(s) of %zu sides, %d reduction(s) and %d version sweep(s) at once",
          nslots, g_sets_max, g_sides.size(), g_red_max, nsweep);
  std::atomic<long> next_trial{g_trial_base + 1};
  vector<std::thread> sweepers;                        // how many sweeps may run at once
  for (int w = 0; w < nsweep; w++) sweepers.emplace_back(sweep_worker_loop);
  vector<std::thread> ths;
  for (int w = 2; w <= nslots; w++)
    ths.emplace_back(worker_loop, std::cref(base), std::ref(next_trial));
  worker_loop(base, next_trial);
  for (auto& th : ths) th.join();
  // a stop can leave candidates queued: account for each one, then the run is closed
  for (;;) {
    ReduceJob job;
    {
      std::lock_guard<std::mutex> lk(g_red_mtx);
      if (g_red_queue.empty()) break;
      job = std::move(g_red_queue.front());
      g_red_queue.pop_front();
    }
    run_reduce_job(std::move(job));
  }
  // every confirmed bug still queued gets its sweep and its report before the run closes
  g_sweep_drain.store(true);
  g_sweep_q_cv.notify_all();
  for (auto& th : sweepers) th.join();
  for (auto& s : g_sets) {
    if (s->pre.valid()) s->pre.wait();
    s->ls.reset();
    for (auto& sr : s->sides) { sr.conn.close(); sr.ctl.close(); sr.inst.stop(); }
  }
  if (tui.joinable()) { g_stop.store(true); tui.join(); }
  logline("done: %ld trials, %ld stmts, %ld parse-skips, %ld diffs (%ld crash), "
          "%ld order-only notes (%ld shown to be ties), "
          "%ld limit-tie notes (%ld shown to be ties), %ld warn-notes, "
          "%ld improvement-notes, %ld plan-flux notes, %ld plan-shape notes, "
          "%ld plan-order notes, %ld plan-explained notes, "
          "%ld plan-in-transaction notes, %ld timing notes%s",
          g_stats.trials.load(), g_stats.stmts.load(), g_stats.parse_skips.load(),
          g_stats.diffs.load(), g_stats.crashes.load(), g_stats.order_notes.load(),
          g_order_checked.load(), g_limit_ties.load(), g_limit_checked.load(),
          g_stats.warn_notes.load(),
          g_stats.improve_notes.load(), g_stats.plan_flux.load(), g_stats.plan_shape.load(),
          g_stats.plan_order.load(), g_stats.plan_explained.load(), g_stats.plan_in_tx.load(),
          g_stats.timing_notes.load(), g_stats.engine_stops.load()
              ? (", " + std::to_string(g_stats.engine_stops.load()) +
                 " trial(s) stopped at a failed statement the engines undo differently").c_str()
              : "");
  logline("candidates: %ld (%ld confirmed as bugs, %ld dropped - the diff did not replay, "
          "%ld left unverified), %ld known-muted, %ld duplicate-muted",
          g_cands.load() - g_cand_base, g_bugs.load() - g_bug_base,
          g_stats.unreproduced.load(), g_stats.unverified.load(), g_known_matches.load(),
          g_dup_diffs.load());
  if (g_final_fails.load())                          // reduced away, so worth a look
    logline_alert("%ld candidate(s) replayed as a trial and not as a reduced testcase",
                  g_final_fails.load());
  if (g_cand_base || g_bug_base)                   // a resumed run: what the workdir holds
    logline("workdir totals: %ld candidates, %ld bugs", g_cands.load(), g_bugs.load());
  if (g_cfg.perf_factor > 0)                       // helps size PERF_MIN_DELTA for a workload
    logline("perf: largest read-only side gap seen %ld ms", g_perf_gap_max.load());
  logline("filter: %ld kept, %ld not-allowlisted, %ld denied, %ld toggled-off, %ld user-filtered, %ld LIMIT-stripped",
          g_fstat.kept.load(), g_fstat.not_allowed.load(), g_fstat.denied.load(),
          g_fstat.toggled_off.load(), g_fstat.user_filtered.load(), g_fstat.limit_stripped.load());
  for (size_t i = 0; i < g_user_filters.size(); i++)
    if (g_user_filter_hits[i].load())
      logline("  user filter pattern %zu: %ld drop(s)", i + 1, g_user_filter_hits[i].load());
  logline("results: %s", g_run.workdir.c_str());
  return 0;
}

// ------------------------------------------------------------------ selftest
// --selftest runs every part of corlogic that needs no server: the SQL parsing, the
// stream filters, the compare core, the UID chain, the reduction rewrites and the report
// helpers. It then runs the same checks from several threads at once, which is where a
// shared buffer or a static local would show up. build.sh runs it on every build.

static std::atomic<long> g_st_pass{0}, g_st_fail{0};
static std::mutex g_st_out;
static bool g_st_quiet = false;

static void st_eq(const string& got, const string& want, const char* what) {
  if (got == want) { g_st_pass++; return; }
  g_st_fail++;
  if (g_st_quiet) return;
  std::lock_guard<std::mutex> lk(g_st_out);
  printf("  FAIL %-34s got [%s] want [%s]\n", what, got.c_str(), want.c_str());
}
static void st_true(bool cond, const char* what) {
  if (cond) { g_st_pass++; return; }
  g_st_fail++;
  if (g_st_quiet) return;
  std::lock_guard<std::mutex> lk(g_st_out);
  printf("  FAIL %-34s false\n", what);
}

static void st_text() {
  st_eq(trim("  a b \t"), "a b", "trim");
  st_eq(upper("aB_1"), "AB_1", "upper");
  st_eq(lower("aB_1"), "ab_1", "lower");
  st_eq(join_list(split("a,b,,c", ','), "|"), "a|b||c", "split keeps empties");
  st_true(starts_with_i("SeLect 1", "select"), "starts_with_i");
  st_true(icontains("aXbYc", "xby"), "icontains");
  st_eq(human_bytes(1536), "1K", "human_bytes KB");
  st_eq(human_bytes(3ULL << 20), "3.0M", "human_bytes MB");
  st_eq(human_bytes(5ULL << 30), "5.0G", "human_bytes GB");
  st_eq(trim_ws("  a   b  "), "a   b", "trim_ws trims the ends");
  st_eq(trim_ws("   "), "", "trim_ws on blanks");
  st_eq(join_list(split_top_level("a,(b,c),d"), "|"), "a|(b,c)|d", "split_top_level");
  st_eq(join_list(split_top_level("'a,b',c"), "|"), "'a,b'|c", "split_top_level quotes");
  st_eq(strip_ticks("`a`"), "a", "strip_ticks");
  st_eq(leading_word("  select 1"), "SELECT", "leading_word");
  st_eq(std::to_string(matching_paren("f(a,(b))x", 1)), "7", "matching_paren");
  st_eq(std::to_string(skip_quoted("'a''b'c", 0)), "6", "skip_quoted doubled quote");
  st_eq(lines_word(2), "2l", "lines_word");
  st_eq(sh_quote("a'b"), "'a'\\''b'", "sh_quote");
  st_eq(one_nl("x\n\n\n"), "x\n", "one_nl");
  st_eq(release_of("11.4.5-MariaDB"), "11.4", "release_of");
  st_eq(seed_date(0).substr(0, 4), "1990", "seed_date base");
  st_eq(shorten_commit_ids_log_only("abcdef0123456789abcdef0123456789abcdef01"), "abcdef012345",
        "commit id shortened");
}

static void st_upper_blanked() {
  st_eq(upper_blanked("SELECT 'a,b' FROM t"), "SELECT       FROM T", "literal blanked");
  st_eq(upper_blanked("SELECT `x y` FROM t"), "SELECT       FROM T", "identifier blanked");
  st_eq(std::to_string(upper_blanked("SELECT 'a,b' FROM t").size()),
        std::to_string(string("SELECT 'a,b' FROM t").size()), "blanking keeps the length");
  st_eq(std::to_string(find_word_top("SELECT A FROM T", "FROM")), "9", "find_word_top");
  st_eq(std::to_string(find_word_top("(SELECT A FROM T) X", "FROM")), std::to_string(string::npos),
        "find_word_top stays at depth 0");
  st_eq(std::to_string(find_word_top("SELECT FROMX A FROM T", "FROM")), "15",
        "find_word_top needs a word boundary");
  st_true(has_token("SELECT UNION ALL", "UNION"), "has_token");
  st_true(!has_token("SELECT 'UNION'", "UNION"), "has_token skips a literal");
  st_true(contains_word("A UNION B", "UNION"), "contains_word");
  st_true(!contains_word("A UNIONX B", "UNION"), "contains_word needs a boundary");
}

static void st_stmt_readonly() {
  st_true(stmt_readonly("SELECT 1"), "a SELECT is read-only");
  st_true(stmt_readonly("  select c1 from t1"), "leading space and lower case");
  st_true(stmt_readonly("WITH cte AS (SELECT 1) SELECT * FROM cte"), "a WITH over a SELECT");
  st_true(stmt_readonly("WITH RECURSIVE cte(c1) AS (SELECT 1) SELECT * FROM cte"),
          "RECURSIVE and a column list");
  st_true(!stmt_readonly("WITH cte AS (SELECT c1 FROM t1) DELETE FROM t1 "
                         "WHERE c1 IN (SELECT c1 FROM cte) LIMIT 3"),
          "a WITH over a DELETE is a write");
  st_true(!stmt_readonly("WITH a AS (SELECT 1), b AS (SELECT 2) UPDATE t1 SET c1=1"),
          "two CTEs then an UPDATE");
  st_true(!stmt_readonly("WITH cte AS (SELECT 1) INSERT INTO t1 SELECT * FROM cte"),
          "a WITH over an INSERT");
  st_true(!stmt_readonly("UPDATE t1 SET c1=1"), "an UPDATE is a write");
  st_eq(with_body_word("WITH `select` AS (SELECT 1) DELETE FROM t1"), "DELETE",
        "a quoted CTE name is not the body");
  st_eq(with_body_word("SELECT 1"), "", "no WITH, no body word");
  st_true(stmt_readonly("(WITH cte AS (SELECT 1) SELECT * FROM cte)"),
          "a bracketed WITH is read the same way");
}

static void st_access_swap() {
  st_true(access_scan_swap("eq_ref,ref", "ALL,ref"), "a key traded for a scan");
  st_true(access_scan_swap("ALL,ref", "ALL,ALL"), "the other way round");
  st_true(!access_scan_swap("ref,range", "range,range"), "keyed to keyed is not a swap");
  st_true(!access_scan_swap("index,ALL", "ALL,ALL"), "scan to scan is not a swap");
  st_true(!access_scan_swap("eq_ref", "eq_ref,ALL"), "a different shape is not comparable");
  st_true(scan_side_is_b("eq_ref,ref", "ALL,ref"), "side b does the scan");
  st_true(!scan_side_is_b("ALL,ref", "eq_ref,ref"), "side a does the scan");
  // the swap test compares by position, so it only applies where position names the same
  // table on both sides
  PlanInfo pa, pb;
  pa.table_order = "t1,o,";
  pb.table_order = "t1,o,";
  st_true(plans_line_up(pa, pb), "the same join order lines up");
  pb.table_order = "o,t1,";
  st_true(!plans_line_up(pa, pb), "the other join order does not");
  pa.table_order = "t1,<gen>,";
  pb.table_order = "t1,<gen>,";
  st_true(plans_line_up(pa, pb), "a generated name is folded to one token");
  st_eq(plan_table_key("<subquery2>"), "<gen>", "generated name folded");
  st_eq(plan_table_key("t1"), "t1", "a base table keeps its name");
  // the mechanism a finding carries rests on the same comparison
  PlanInfo ma, mb;
  ma.table_order = "o,t1,"; ma.access = "index,ALL";
  mb.table_order = "o,t1,"; mb.access = "ALL,ref";
  st_eq(plan_mech_of(ma, mb), "index>ALL", "same order names the access change");
  mb.table_order = "t1,o,";
  st_eq(plan_mech_of(ma, mb), "rows",
        "a different join order leaves the estimate as the mechanism");
}

static void st_order_by_total() {
  st_eq(order_by_total("SELECT c1, c2 FROM t1 ORDER BY c1", 2),
        "SELECT c1, c2 FROM t1 ORDER BY c1, 1, 2", "tiebreaker appended");
  st_eq(order_by_total("SELECT c1 FROM t1 ORDER BY c1 DESC LIMIT 5", 1),
        "SELECT c1 FROM t1 ORDER BY c1 DESC, 1 LIMIT 5", "tiebreaker before the LIMIT");
  st_eq(order_by_total("SELECT c1 FROM t1 ORDER BY c1 FOR UPDATE", 1),
        "SELECT c1 FROM t1 ORDER BY c1, 1 FOR UPDATE", "tiebreaker before the lock clause");
  st_eq(order_by_total("SELECT * FROM (SELECT c1 FROM t1 ORDER BY c1) d", 1), "",
        "no top-level ORDER BY, no rewrite");
  st_eq(order_by_total("SELECT c1 FROM t1 ORDER BY c1", 0), "", "no columns, no rewrite");
}

static void st_tx_tracking() {
  st_true(stmt_opens_tx("BEGIN"), "BEGIN opens one");
  st_true(stmt_opens_tx("START TRANSACTION"), "START TRANSACTION opens one");
  st_true(!stmt_opens_tx("START SLAVE"), "START on its own does not");
  st_true(stmt_ends_tx("COMMIT"), "COMMIT ends one");
  st_true(stmt_ends_tx("ROLLBACK"), "ROLLBACK ends one");
  st_true(stmt_ends_tx("CREATE TABLE t1 (c1 INT)"), "DDL commits");
  st_true(stmt_ends_tx("ANALYZE TABLE `t1`"), "the statistics refresh commits");
  st_true(!stmt_ends_tx("SELECT 1"), "a read changes nothing");
  st_true(!stmt_ends_tx("INSERT INTO t1 VALUES (1)"), "a write changes nothing");
}

static void st_rows_unspecified() {
  st_true(stmt_rows_unspecified("SELECT * FROM t1 LIMIT 5"), "LIMIT makes the choice open");
  st_true(stmt_rows_unspecified("SELECT * FROM (SELECT c1 FROM t1 LIMIT 2) d"),
          "LIMIT in a subquery counts");
  st_true(!stmt_rows_unspecified("SELECT 'LIMIT 1' FROM t1"), "LIMIT in a literal does not");
  st_true(!stmt_rows_unspecified("SELECT limitless FROM t1"), "a name that starts with it does not");
  st_true(!stmt_rows_unspecified("SELECT * FROM t1"), "no LIMIT, nothing open");
  st_true(!stmt_rows_unspecified(""), "no statement");
  st_true(!stmt_rows_unspecified("SELECT * FROM t1 ORDER BY c1 LIMIT 5"),
          "a top-level ORDER BY with the LIMIT is asked again, not assumed");
  st_true(stmt_rows_unspecified("SELECT * FROM (SELECT c1 FROM t1 LIMIT 2) d ORDER BY c1 LIMIT 3"),
          "a second LIMIT below it stays open");
  st_true(stmt_limit_ordered("SELECT * FROM t1 ORDER BY c1 LIMIT 5"), "the settleable case");
  st_true(!stmt_limit_ordered("SELECT * FROM t1 LIMIT 5"), "no ORDER BY, not settleable");
  st_true(stmt_limit_ordered("SELECT c1 FROM t1 UNION SELECT c1 FROM t2 ORDER BY 1 LIMIT 3"),
          "a UNION with both is settleable");
  st_true(stmt_rows_unspecified("SELECT * FROM t1 WHERE c1 IN (SELECT c1 FROM t2 ORDER BY c1 LIMIT 2)"),
          "the ORDER BY belongs to the subquery, so the rows stay open");
  st_true(stmt_rows_unspecified("WITH d AS (SELECT c1 FROM t1 LIMIT 2) SELECT * FROM d"),
          "a LIMIT in a CTE stays open");
}

static void st_strip_limit() {
  string s = "SELECT 1 LIMIT 5";
  st_true(strip_limit(s), "LIMIT found");
  st_eq(trim(s), "SELECT 1", "LIMIT stripped");
  s = "SELECT (SELECT 1 LIMIT 1) LIMIT 2, 3";
  st_true(strip_limit(s), "nested LIMIT found");
  st_true(!icontains(s, "LIMIT"), "every LIMIT stripped");
  s = "SELECT 'LIMIT 5'";
  st_true(!strip_limit(s), "LIMIT in a literal is left alone");
  st_eq(s, "SELECT 'LIMIT 5'", "literal untouched");
}

static void st_stream_rewrites() {
  string s = "ALTER TABLE t ADD c INT, ALGORITHM=INPLACE, LOCK=NONE";
  strip_online_ddl(s);
  st_true(!icontains(s, "ALGORITHM") && !icontains(s, "LOCK=NONE"), "online DDL clauses gone");
  st_eq(trim(s), "ALTER TABLE t ADD c INT", "ALTER body kept");
  s = "ALTER TABLE t1 COMMENT='LOCK=NONE'";
  strip_online_ddl(s);
  st_eq(s, "ALTER TABLE t1 COMMENT='LOCK=NONE'", "a clause inside a literal is text");
  s = "ALTER TABLE t1 COMMENT='LOCK=NONE', ALGORITHM=COPY";
  strip_online_ddl(s);
  st_eq(s, "ALTER TABLE t1 COMMENT='LOCK=NONE'", "the real clause goes, the literal stays");
  bool save_axis = g_engine_axis, save_vendor = g_same_vendor;
  g_engine_axis = false;
  g_same_vendor = true;
  st_true(!stream_strips_online_ddl(), "one vendor on one engine keeps the clauses");
  g_same_vendor = false;
  st_true(stream_strips_online_ddl(), "two vendors drop them");
  g_same_vendor = true;
  g_engine_axis = true;
  st_true(stream_strips_online_ddl(), "two engines drop them");
  g_engine_axis = save_axis;
  g_same_vendor = save_vendor;
  int save_mix = g_cfg.engine_mix;
  vector<string> save_pool = g_engine_pool;
  g_cfg.engine_mix = 1;
  g_engine_pool = {"innodb", "myisam", "aria"};
  s = "CREATE TABLE t3 (a INT)";
  st_true(engine_mix_rewrite(s), "engine_mix_rewrite adds an engine");
  st_true(icontains(s, "ENGINE="), "the clause is there");
  string s2 = "CREATE TABLE t3 (a INT)";
  engine_mix_rewrite(s2);
  st_eq(s2, s, "the same table name picks the same engine");
  g_engine_pool = {"innodb"};
  s = "CREATE TABLE t3 (a INT)";
  st_true(!engine_mix_rewrite(s), "a pool of one is not a mix");
  g_engine_pool = save_pool;
  g_cfg.engine_mix = save_mix;
}

static void st_compare_core() {
  int se = g_error_mode, sw = g_warning_mode;
  g_error_mode = 1; g_warning_mode = 0;
  QOutcome a, b;
  a.cols = b.cols = 1;
  a.row_count = b.row_count = 2;
  a.multiset_hash = b.multiset_hash = 77;
  st_eq(compare_pair(a, b, false), "", "same result, no diff");
  b.multiset_hash = 78;
  st_eq(compare_pair(a, b, false), "RESULT", "row content differs");
  b.multiset_hash = 77;
  b.cols = 2;
  st_eq(compare_pair(a, b, false), "RESULT", "column count differs");
  b.cols = 1;
  a.state = QState::ERR; a.err = 1064;
  st_eq(compare_pair(a, b, false), "ERROR", "one side errors");
  b.state = QState::ERR; b.err = 1064;
  st_eq(compare_pair(a, b, false), "", "same error code");
  b.err = 1146;
  st_eq(compare_pair(a, b, false), "ERROR", "error code differs");
  a.errmsg = b.errmsg = "same words";
  st_eq(compare_pair(a, b, false), "", "the same words match across differing codes");
  b.err = 1064; b.errmsg = "other words";
  g_error_mode = 2;
  st_eq(compare_pair(a, b, false), "ERROR", "same code, different words, text mode");
  g_error_mode = 1;
  a.errmsg.clear(); b.errmsg.clear(); b.err = 1146;
  g_error_mode = 0;
  st_eq(compare_pair(a, b, false), "", "state compare ignores the code");
  g_error_mode = 1;
  st_eq(compare_pair(a, b, true), "", "state_only ignores the code");
  a.state = b.state = QState::OK;
  a.state = QState::CRASH;
  st_eq(compare_pair(a, b, false), "CRASH", "one side crashes");
  a.state = QState::TIMEOUT;
  st_eq(compare_pair(a, b, false), "TIMEOUT", "one side times out");
  b.state = QState::TIMEOUT;
  st_eq(compare_pair(a, b, false), "", "both sides time out");
  {
    QOutcome ge, gr;
    ge.state = QState::ERR;
    ge.err = 1505;
    ge.errmsg = "Partition management on a not partitioned table is not possible";
    gr.state = QState::OK;
    gr.cols = 4;
    gr.row_count = 2;
    gr.rows = {"db1.t3\toptimize\tError\tPartition management on a not partitioned table"
               " is not possible",
               "db1.t3\toptimize\tstatus\tOperation failed"};
    st_eq(compare_pair(ge, gr, false), "", "a grid Error row carrying the raised words");
    st_eq(compare_pair(gr, ge, false), "", "either side may be the raising one");
    st_eq(compare_pair(ge, gr, true), "", "state_only sees the same equivalence");
    gr.rows[0] = "db1.t3\toptimize\tError\tother words";
    st_eq(compare_pair(ge, gr, false), "ERROR", "different words stay a difference");
  }
  {
    bool sv = g_same_vendor;
    g_same_vendor = false;
    QOutcome e, w;
    e.state = QState::ERR; e.err = 1292;
    e.errmsg = "Truncated incorrect DOUBLE value: 'one'";
    w.state = QState::WARN;
    w.warnings.push_back({1292, "Warning", "Truncated incorrect DECIMAL value: 'one'"});
    st_eq(compare_pair(e, w, false), "", "an error against a warning with the same code");
    st_eq(compare_pair(w, e, false), "", "either side may be the raising one");
    st_eq(compare_pair(e, w, true), "", "state_only sees the same equivalence");
    w.warnings[0].code = 1265;
    st_eq(compare_pair(e, w, false), "ERROR", "a different warning code stays a difference");
    w.warnings[0].msg = e.errmsg;
    st_eq(compare_pair(e, w, false), "", "the same words match across differing codes");
    w.warnings.clear();
    st_eq(compare_pair(e, w, false), "ERROR", "no warning content, no equivalence");
    w.warnings.push_back({1292, "Warning", "x"});
    g_same_vendor = true;
    st_eq(compare_pair(e, w, false), "ERROR", "same-vendor severity change stays a difference");
    g_same_vendor = sv;
  }
  {
    bool sv = g_same_vendor;
    g_same_vendor = false;
    QOutcome x, y;
    x.cols = y.cols = 2;
    x.row_count = y.row_count = 1;
    x.multiset_hash = 1;
    y.multiset_hash = 2;
    x.rows = {"7\t2.3333333333333335"};
    y.rows = {"7\t2.3333"};
    st_eq(compare_pair(x, y, false), "", "one number under two vendor result types");
    y.rows = {"7\t2.3334"};
    st_eq(compare_pair(x, y, false), "RESULT", "the shorter fraction with another value");
    y.rows = {"8\t2.3333"};
    st_eq(compare_pair(x, y, false), "RESULT", "an integer cell that differs");
    x.rows = {"1\tab"};
    y.rows = {"1.0\tab"};
    st_eq(compare_pair(x, y, false), "", "a trailing-zero rendering of one number");
    x.rows = {"2.34\tab"};
    y.rows = {"2.35\tab"};
    st_eq(compare_pair(x, y, false), "RESULT", "same precision stays a difference");
    // an aggregate over an ENUM: one side reads the numeric index and answers in DECIMAL,
    // the other reads the string and answers in DOUBLE, and the value is the same
    x.rows = {"1\t1.0000"};
    y.rows = {"1\t1"};
    st_eq(compare_pair(x, y, false), "", "SUM and AVG over an ENUM, one value, two types");
    // a fractional second into a temporal: the side that cuts against the side that rounds
    int sts = g_trunc_side;
    g_trunc_side = 0;
    x.rows = {"00:00:35"};
    y.rows = {"00:00:36"};
    st_eq(compare_pair(x, y, false), "", "a TIME cut on one side and rounded on the other");
    st_eq(compare_pair(y, x, false), "RESULT", "the other way round is not that rule");
    x.rows = {"ab\t2020-01-01 10:00:00"};
    y.rows = {"ab\t2020-01-01 10:00:01"};
    st_eq(compare_pair(x, y, false), "", "a DATETIME beside a cell that matches");
    x.rows = {"2020-12-31 23:59:59"};
    y.rows = {"2021-01-01 00:00:00"};
    st_eq(compare_pair(x, y, false), "", "the second carries over the year");
    x.rows = {"cd\t00:00:35"};
    y.rows = {"ef\t00:00:36"};
    st_eq(compare_pair(x, y, false), "RESULT",
          "a second cell that differs still carries the statement");
    x.rows = {"00:00:35"};
    y.rows = {"00:00:37"};
    st_eq(compare_pair(x, y, false), "RESULT", "two seconds apart is a difference");
    x.rows = {"00:00:35.500000"};
    y.rows = {"00:00:36.500000"};
    st_eq(compare_pair(x, y, false), "RESULT", "a fraction that survived was never cut");
    x.rows = {"2020-01-01"};
    y.rows = {"2020-01-02"};
    st_eq(compare_pair(x, y, false), "RESULT", "a DATE holds no seconds");
    g_trunc_side = -1;
    x.rows = {"00:00:35"};
    y.rows = {"00:00:36"};
    st_eq(compare_pair(x, y, false), "RESULT", "no side known to cut, so no rule");
    g_trunc_side = sts;
    x.rows = {"7\t2.3333333333333335"};
    y.rows = {"7\t2.3333"};
    g_same_vendor = true;
    st_eq(compare_pair(x, y, false), "RESULT", "same-vendor precision change stays a difference");
    g_same_vendor = sv;
  }
  a.state = b.state = QState::OK;
  a.cols = b.cols = 0;
  a.affected = 1; b.affected = 2;
  st_eq(compare_pair(a, b, false), "AFFECTED", "affected rows differ");
  bool sax = g_engine_axis;
  g_engine_axis = true;
  st_eq(compare_pair(a, b, false, "ALTER TABLE t1 FORCE"), "",
        "engine axis forgives a DDL row count");
  st_eq(compare_pair(a, b, false, "UPDATE t1 SET c1=1"), "AFFECTED",
        "engine axis still compares DML");
  g_engine_axis = false;
  bool svx = g_same_vendor;
  g_same_vendor = false;
  st_eq(compare_pair(a, b, false, "ALTER TABLE t1 CHANGE c1 c2 VARCHAR(168) FIRST"), "",
        "two vendors forgive a DDL row count");
  st_eq(compare_pair(a, b, false, "UPDATE t1 SET c1=1"), "AFFECTED",
        "two vendors still compare DML");
  g_same_vendor = true;
  st_eq(compare_pair(a, b, false, "ALTER TABLE t1 CHANGE c1 c2 VARCHAR(168) FIRST"),
        "AFFECTED", "one vendor on one engine still compares a DDL row count");
  g_same_vendor = svx;
  g_engine_axis = sax;
  a.affected = b.affected = 1;
  a.state = QState::WARN;
  st_eq(compare_pair(a, b, false), "WARNING", "warn state differs");
  st_eq(compare_pair(a, b, true), "", "state_only forgives a warning");
  g_warning_mode = -1;
  st_eq(compare_pair(a, b, false), "", "warnings off");
  g_error_mode = se; g_warning_mode = sw;
}

static void st_canon_value() {
  MYSQL_FIELD f{};
  string out;
  canon_value(out, nullptr, 0, f);
  st_eq(out, "\\N", "NULL canonical");
  out.clear();
  f.type = MYSQL_TYPE_STRING; f.charsetnr = 63;
  canon_value(out, "\x01\xff", 2, f);
  st_eq(out, "0x01FF", "binary as hex");
  out.clear();
  f.type = MYSQL_TYPE_DOUBLE; f.charsetnr = 8;
  canon_value(out, "0.30000000000000004", 19, f);
  st_eq(out, "0.3", "double rounded to FLOAT_DIGITS");
  out.clear();
  f.type = MYSQL_TYPE_VAR_STRING;
  canon_value(out, "a\tb\nc", 5, f);
  st_eq(out, "a\\tb\\nc", "tab and newline escaped");
}

static void st_bytes_helpers() {
  st_eq(canon_unhex("0x4142\tz"), "AB\tz", "canon_unhex");
  st_eq(print_form("0x41200942"), "AB", "print_form drops spacing");
  QOutcome a, b;
  a.rows = {"0x4142"}; b.rows = {"AB"};
  st_true(same_bytes_diff_type(a, b), "same bytes, other type");
  st_true(!print_alike_diff_bytes(a, b), "type case is not the print case");
  a.rows = {"A B"}; b.rows = {"A\\tB"};
  st_true(print_alike_diff_bytes(a, b), "prints alike, bytes differ");
}

static void st_uid_chain() {
  st_eq(uid_mech("RESULT|coltype|JOIN|SELECT 1"), "coltype", "uid_mech");
  st_eq(constructs_of("SELECT a FROM t1 JOIN t2 UNION SELECT 1"), "JOIN,UNION", "constructs");
  st_eq(constructs_of("SELECT 'JOIN UNION' FROM t1"), "PLAIN", "constructs skip a literal");
  st_eq(constructs_of("SELECT c1 FROM t1 WHERE c1 IS NULL"), "PLAIN", "NULL is not a construct");
  st_eq(constructs_of("SELECT CONCAT(_utf8 'h', _binary 'w')"), "CSINTRO", "charset introducers");
  st_eq(constructs_of("SELECT c1 FROM t1 WHERE c1 = 'x' COLLATE utf8mb4_bin"), "COLLATE",
        "a collation");
  st_eq(constructs_of("SELECT JSON_VALID(c1) FROM t1"), "JSON", "a JSON function");
  st_eq(constructs_of("CREATE TABLE t1 (c1 JSON)"), "CREATE,JSON", "the JSON type");
  st_eq(constructs_of("SELECT ROW_NUMBER() OVER (ORDER BY c1) FROM t1"), "ORDERBY,WINDOW",
        "a window function");
  st_eq(constructs_of("SELECT NEXTVAL(s1)"), "SEQ", "a sequence");
  st_eq(constructs_of("SELECT ST_ASTEXT(c1) FROM t1"), "SPATIAL", "spatial");
  st_eq(constructs_of("SELECT VEC_DISTANCE_EUCLIDEAN(c1, c1) FROM t1"), "VECTOR", "vector");
  st_eq(constructs_of("SELECT c1 FROM t1 WHERE cunion = 1"), "PLAIN",
        "a name that contains a token is not the construct");
  st_eq(constructs_of("SELECT jsonx FROM t1"), "PLAIN", "nor one that starts with it");
  st_eq(constructs_of("SELECT c1 FROM t1 JOIN t2 ON t1.c1 = t2.c1 WHERE EXISTS "
                      "(SELECT 1) GROUP BY c1 HAVING COUNT(*) > 1 ORDER BY c1 UNION "
                      "SELECT DISTINCT c1 FROM t3 WHERE c1 IN (2) AND c1 LIKE 'a'"),
        "AGG,DISTINCT,EXISTS,GROUPBY,HAVING,IN,JOIN,LIKE,ORDERBY,SUBQ,UNION",
        "every token that matched, no cap");
  st_eq(norm_stmt("SELECT  c1  FROM t1 WHERE c1 = 12345 AND c2 = 'abc'"),
        "SELECT cX FROM tX WHERE cX = N AND cX = 'X'", "norm_stmt");
  st_eq(norm_stmt("UPDATE t3 SET c3=DEFAULT"), "UPDATE tX SET cX=DEFAULT",
        "norm_stmt, table and column generic");
  st_eq(norm_stmt("SELECT * FROM `t12` JOIN t7 ON `t12`.`c2` = t7.c11"),
        "SELECT * FROM `tX` JOIN tX ON `tX`.`cX` = tX.cX", "norm_stmt, quoted names");
  st_eq(norm_stmt("ALTER TABLE t4 CHANGE c2 c2_renamed VARCHAR(32) FIRST"),
        "ALTER TABLE tX CHANGE cX cX_renamed VARCHAR(N) FIRST",
        "a numbered name with a suffix is the same family");
  st_eq(norm_stmt("SELECT count1, tab2, t1x FROM utf8mb4 WHERE 0x1F = 1e5"),
        "SELECT count1, tab2, t1x FROM utf8mb4 WHERE N = N",
        "norm_stmt, other names are left alone");
  DiffHit h;
  h.category = "ERROR";
  h.statement = "SELECT 1 FROM t1";
  QOutcome a, b;
  a.err = 0; b.err = 1064;
  st_eq(uid_mech(uid_build(h, a, b, "")), "0v1064", "ERROR mechanism");
  h.category = "PLAN"; h.mech = "ALL>index";
  st_eq(uid_mech(uid_build(h, a, b, "")), "ALL>index", "PLAN mechanism is the access delta");
  st_eq(access_delta("ALL,ref", "index,ref"), "ALL>index", "access_delta");
  st_eq(access_delta("ALL,ref", "ALL,ref"), "same", "access_delta on no change");
  st_eq(access_delta("ALL", "ALL,ref"), "->ref", "access_delta on a longer plan");
  st_eq(plan_mech(""), "rows", "plan_mech with no access change");
}

static void st_uid1_chain() {
  string save = g_run.rundir;
  g_run.rundir = "/dev/shm";
  st_eq(std::to_string(uid1_of("SELECT 1", 7).size()), "12", "uid1 is 12 hex");
  st_eq(uid1_of("SELECT 1", 7), uid1_of("SELECT 1", 9), "uid1 ignores the trial number");
  st_true(uid1_of("SELECT 1", 7) != uid1_of("SELECT 2", 7), "uid1 follows the testcase");
  g_run.rundir = save;
}

static void st_known_filter() {
  string f = "/dev/shm/corlogic_selftest_known.txt";
  write_file(f, "# a comment\nRESULT|content|*|ANALYZE TABLE*\nPLAN|*|*|*\n"
                "RESULT|coltype|*|*_utf8 *\nAFFECTED|*|*IN*|*\n");
  string save = g_cfg.known_file;
  g_cfg.known_file = f;
  g_known.clear();
  g_known_uid1.clear();
  load_known_file();
  st_true(known_match("RESULT|content|PLAIN|ANALYZE TABLE `t1`"), "known statement prefix");
  st_true(!known_match("RESULT|rows|PLAIN|ANALYZE TABLE `t1`"), "known field must match");
  st_true(!known_match("RESULT|content|PLAIN|OPTIMIZE TABLE `t1`"), "another statement is not muted");
  st_true(known_match("PLAN|x|y|z"), "known wildcards");
  st_true(!known_match("ERROR|x|y|z"), "unknown category is not muted");
  st_eq(known_near("RESULT|content|PLAIN|OPTIMIZE TABLE `t1`"), "",
        "a mechanism naming neither side cannot be near");
  g_known.push_back({"RESULT", "rows1v2", "*", "ANALYZE TABLE*", ""});
  st_eq(known_near("RESULT|rows1v2|PLAIN|OPTIMIZE TABLE `t1`"),
        "RESULT|rows1v2|*|ANALYZE TABLE*", "near a narrow entry, another statement");
  st_eq(known_near("RESULT|rows1v2|PLAIN|ANALYZE TABLE `t1`"), "",
        "the muted one itself is not near");
  g_known.pop_back();
  st_eq(known_near("PLAN|x|y|z"), "", "a wildcard entry cannot be near");
  st_eq(known_near("RESULT|rows3v4|PLAIN|OPTIMIZE TABLE `t1`"), "",
        "another mechanism is not near");
  g_known.push_back({"AFFECTED", "*", "*", "UPDATE tX*", ""});
  st_eq(known_near("AFFECTED|0v1|UPDATE|DELETE FROM tX"), "",
        "a wildcard mechanism cannot be near");
  g_known.back() = {"AFFECTED", "0v1", "*", "UPDATE tX*", "MDEV-1"};
  st_eq(known_near("AFFECTED|0v1|UPDATE|DELETE FROM tX"),
        "AFFECTED|0v1|*|UPDATE tX* (MDEV-1)", "the ticket rides along");
  g_known.pop_back();
  st_true(known_match("RESULT|coltype|PLAIN|SELECT CONCAT(_utf8 'X', 'Y', _binary 'Z')"),
          "a construct anywhere in the statement");
  st_true(!known_match("RESULT|coltype|PLAIN|SELECT CONCAT(cX, cX) FROM tX"),
          "the same mechanism without the construct is not muted");
  // a statement can hold a bar of its own: only the first three divide the fields
  st_eq(std::to_string(uid_fields("RESULT|rows1v2|PLAIN|SELECT a|b FROM t1").size()), "4",
        "a bar in the statement keeps four fields");
  st_eq(uid_fields("RESULT|rows1v2|PLAIN|SELECT a|b FROM t1")[3], "SELECT a|b FROM t1",
        "the statement is the whole of the rest");
  st_eq(std::to_string(uid_fields("RESULT|rows1v2|PLAIN|").size()), "4",
        "an empty statement is still a field");
  g_known.push_back({"RESULT", "rows1v2", "*", "SELECT a|b FROM t1", ""});
  st_true(known_match("RESULT|rows1v2|PLAIN|SELECT a|b FROM t1"),
          "a pattern holding a bar matches the whole statement");
  g_known.pop_back();
  // AFFECTED and a row-count RESULT carry counts the data decides, so near reads the shape
  st_true(mech_near("AFFECTED", "0v1", "232v279"), "two count pairs, the same direction");
  st_true(!mech_near("AFFECTED", "0v1", "279v232"), "the other direction is not the same");
  st_true(mech_near("RESULT", "rows1v2", "rows7v9"), "row counts read the same way");
  st_true(!mech_near("RESULT", "content", "coltype"), "a named mechanism is compared as written");
  st_true(!mech_near("ERROR", "0v1064", "0v1054"), "an error code is an identity, not a count");
  g_known.push_back({"AFFECTED", "0v1", "*", "UPDATE tX SET cX=DEFAULT", "MDEV-40874"});
  st_eq(known_near("AFFECTED|232v279|ORDERBY,UPDATE|UPDATE IGNORE tX SET cX=cX+N WHERE cX>N"),
        "AFFECTED|0v1|*|UPDATE tX SET cX=DEFAULT (MDEV-40874)",
        "a count pair finds the entry it sits beside");
  g_known.pop_back();
  st_true(known_match("AFFECTED|1v2|IN,JOIN|SELECT 1"), "a token in the construct set");
  st_true(!known_match("AFFECTED|1v2|INSERT,UPDATE|SELECT 1"),
          "a token that only sits inside another one is not a match");
  g_cfg.known_file = save;
  g_known.clear();
  g_known_uid1.clear();
  std::error_code ec;
  fs::remove(f, ec);
}

static void st_mutate_tuple() {
  st_eq(mutate_tuple("('a')", 1), "('b')", "a lone quoted letter steps");
  st_eq(mutate_tuple("(-37)", 1), "(-38)", "an integer literal steps");
  st_eq(mutate_tuple("(1,'one',2.5)", 2), "(3,'one',4.7)", "words hold, numbers step");
  st_eq(mutate_tuple("('z')", 1), "('z')", "the end of the alphabet holds");
  st_eq(mutate_tuple("(NULL,x2)", 1), "(NULL,x2)", "keywords and identifiers hold");
}

static void st_reduce_rewrites() {
  string tn;
  bool cl = false;
  size_t vend = 0;
  string s = "INSERT INTO `t1` (c1,c2) VALUES (1,2),(3,4)";
  st_true(parse_insert_values(s, upper_blanked(s), tn, cl, vend), "parse_insert_values");
  st_eq(tn, "t1", "insert table name");
  st_true(cl, "column list seen");
  st_eq(trim_ws(join_list(split_top_level(s.substr(vend)), "|")), "(1,2)|(3,4)", "tuples split");
  s = "INSERT INTO t1 VALUES (1)";
  st_true(parse_insert_values(s, upper_blanked(s), tn, cl, vend) && !cl, "no column list");
  size_t bs = 0, be = 0;
  s = "CREATE OR REPLACE TABLE t2 (a INT, b INT, KEY k1 (a)) ENGINE=InnoDB";
  st_true(parse_create_table(s, upper_blanked(s), tn, bs, be), "parse CREATE OR REPLACE");
  st_eq(tn, "t2", "create table name");
  st_eq(join_list(split_top_level(s.substr(bs, be - bs)), "|"), "a INT| b INT| KEY k1 (a)",
        "defs split");
  s = "CREATE TABLE t3 AS SELECT 1";
  st_true(!parse_create_table(s, upper_blanked(s), tn, bs, be), "AS SELECT form skipped");
  st_true(is_key_def("PRIMARY KEY (a)"), "is_key_def PRIMARY");
  st_true(is_key_def("KEY k1 (a)"), "is_key_def KEY");
  st_true(!is_key_def("keyword INT"), "a column named keyword is not a key");
  string tup = "(1,2,3)";
  st_true(tuple_drop_elem(tup, 1), "tuple_drop_elem");
  st_eq(tup, "(1,3)", "element dropped");
  vector<StreamStmt> nl = {{"CREATE TABLE t3 (c4 INT)"},
                           {"INSERT INTO `t3` VALUES (1)"},
                           {"SELECT c4, ct3, t3x FROM t3 WHERE 't3'='x'"}};
  auto tp = name_plan(nl, 't', true);
  st_true(tp.size() == 1 && tp[0].first == "t3" && tp[0].second == "t",
          "a lone table goes bare");
  auto cp = name_plan(nl, 'c', true);
  st_true(cp.size() == 1 && cp[0].first == "c4" && cp[0].second == "c",
          "a lone column goes bare");
  vector<std::pair<string, string>> nm = tp;
  nm.insert(nm.end(), cp.begin(), cp.end());
  st_eq(rename_idents(nl[2].sql, nm), "SELECT c, ct3, t3x FROM t WHERE 't3'='x'",
        "word boundaries and the literal hold");
  st_eq(rename_idents(nl[1].sql, nm), "INSERT INTO `t` VALUES (1)",
        "a backtick-quoted name is renamed in its quotes");
  vector<StreamStmt> n2 = {{"SELECT * FROM t5, t2"}};
  auto sp = name_plan(n2, 't', true);
  st_true(sp.size() == 1 && sp[0].first == "t5" && sp[0].second == "t1",
          "sparse goes dense by first appearance");
  st_eq(rename_idents(n2[0].sql, sp), "SELECT * FROM t1, t2", "the kept name is untouched");
  vector<StreamStmt> n3 = {{"SELECT t FROM t4"}};
  auto bp = name_plan(n3, 't', true);
  st_true(bp.size() == 1 && bp[0].second == "t1", "a bare name in use blocks the bare step");
  vector<std::pair<string, string>> sw = {{"t1", "t2"}, {"t2", "t1"}};
  st_eq(rename_idents("SELECT t1.c4 FROM t1, t2", sw), "SELECT t2.c4 FROM t2, t1",
        "a swapped pair renames simultaneously");
  vector<std::pair<string, string>> sx = {{"t3", "t"}, {"c2", "c"}};
  st_eq(rename_idents("ALTER TABLE t3 CHANGE c2 c2_renamed VARCHAR(8)", sx),
        "ALTER TABLE t CHANGE c c_renamed VARCHAR(8)",
        "a suffixed form follows its family");
  st_eq(rename_idents("ALTER TABLE `t3` CHANGE `c2` `c2_renamed` VARCHAR(8)", sx),
        "ALTER TABLE `t` CHANGE `c` `c_renamed` VARCHAR(8)",
        "a quoted suffixed form follows too");
  vector<std::pair<string, string>> sy = {{"c2", "c1"}, {"c21", "c2"}};
  st_eq(rename_idents("SELECT c21_renamed, c2_renamed FROM t1", sy),
        "SELECT c2_renamed, c1_renamed FROM t1",
        "the digits end the family, the underscore starts the suffix");
}

static void st_stats_refresh() {
  std::set<string> live;
  collect_table_names("CREATE TABLE `t1` (a INT)", live);
  collect_table_names("CREATE OR REPLACE TABLE t2 (a INT)", live);
  collect_table_names("SELECT 1", live);
  st_eq(std::to_string(live.size()), "2", "table names collected");
  bool save = g_setup_stat_tables;
  g_setup_stat_tables = false;
  st_eq(stats_refresh_sql(live), "ANALYZE TABLE `t1`,`t2`", "refresh SQL");
  g_setup_stat_tables = true;
  st_eq(stats_refresh_sql(live), "ANALYZE TABLE `t1`,`t2` PERSISTENT FOR ALL",
        "refresh SQL with EITS");
  g_setup_stat_tables = save;
  st_eq(stats_refresh_sql({}), "", "no tables, no refresh");
  collect_table_names("DROP TABLE t2 CASCADE", live);
  st_true(live.size() == 1 && *live.begin() == "t1", "dropped, list ends in CASCADE");
  collect_table_names("CREATE TABLE t4 (a INT)", live);
  collect_table_names("DROP TABLE t1, t4 CASCADE", live);
  st_true(live.empty(), "dropped, two names and a trailing keyword");
  vector<StreamStmt> st;
  for (int i = 0; i < 7; i++) st.push_back({"CREATE TABLE t" + std::to_string(i) + " (a INT)", false, false});
  insert_stats_refresh(st, 3);
  long marks = 0;
  for (auto& x : st) if (x.checkpoint) marks++;
  st_eq(std::to_string(marks), "2", "one refresh every 3 statements, none trailing");
  st_true(st.back().sql.rfind("CREATE", 0) == 0, "the stream does not end on a refresh");
}

static void st_report_helpers() {
  st_true(timing_error(1205) && timing_error(1213) && timing_error(1317) &&
          timing_error(1969), "contention and interruption errors");
  st_true(!timing_error(0) && !timing_error(1064) && !timing_error(1365),
          "a logic error is not one of them");
  st_true(plan_explains("RESULT") && plan_explains("AFFECTED") && plan_explains("CHECKSUM") &&
          plan_explains("TIMEOUT"), "a plan explains a row difference");
  st_true(!plan_explains("ERROR") && !plan_explains("WARNING") && !plan_explains("CRASH"),
          "a plan explains no error, warning or crash");
  st_eq(fit_cell("version sweep: rt45: 2 left", 21), "version sweep: rt45:", "cell cut at a space");
  st_eq(fit_cell("supercalifragilistic", 8), "supercal", "cell with no space to cut on");
  st_eq(fit_cell("short", 20), "short", "cell that fits");
  st_eq(fit_number("1025637", 6), "1026k", "a count too wide is shortened, not cut");
  st_eq(fit_number("1025637", 4), "1.0M", "a narrow cell takes the next unit up");
  st_eq(fit_number("822863", 6), "822863", "a count that fits is left alone");
  st_eq(fit_number("40%/70%", 5), "40%/70%", "only a plain count is shortened");
  st_eq(diff_phrase("CHECKSUM"), "TABLE DATA", "diff_phrase");
  st_eq(banner_title("{noformat:title=CS 13.1.0 abc}"), "CS 13.1.0 abc", "banner_title");
  st_eq(renumber_trace("1| OK\n2| row| x\ntable t1| OK\n", 2), "3| OK\n4| row| x\ntable t1| OK\n",
        "trace renumbered by the block head");
  st_eq(renumber_trace("1| OK\n", 0), "1| OK\n", "no offset, no change");
  st_eq(cap_lines("a\nb\nc\n", 2), "a\nb\n... (1 more line(s))\n", "cap_lines");
  st_eq(cap_trace("1| OK\n1| row| a\n1| row| b\n1| row| c\n", 2, 80),
        "1| OK\n1| row| a\n1| row| b\n1| ... (1 more row(s))\n", "cap_trace caps rows");
  st_eq(stmt_head("SELECT c1 FROM t1"), "SELECT", "stmt_head");
  st_true(stmt_is_dml("update t1 set c1=1"), "stmt_is_dml");
  st_true(!stmt_is_dml("ALTER TABLE t1 FORCE"), "DDL is not DML");
  st_true(stmt_explainable("WITH x AS (SELECT 1) SELECT * FROM x"), "WITH is explainable");
  st_true(!stmt_explainable("SET @a=1"), "SET is not explainable");
  st_true(stmt_readonly("SELECT 1"), "SELECT is read-only");
  st_true(!stmt_readonly("DELETE FROM t1"), "DELETE is not read-only");
  st_true(perf_exceeds(100, 100 * g_cfg.perf_factor + g_cfg.perf_min_delta + 1),
          "perf_exceeds trips on both thresholds");
  st_true(!perf_exceeds(1, 1 * g_cfg.perf_factor + 1), "a small absolute gap does not trip");
  vector<long> v = version_key("13.1.0-MariaDB");
  st_eq(std::to_string(v.size()) + ":" + std::to_string(v[0]) + "." + std::to_string(v[1]),
        "3:13.1", "version_key");
  st_true(version_key("13.0.2") < version_key("13.1.0"), "version_key orders");
}

static void st_slot_pool() {
  SlotPool sp;
  sp.init(4);
  st_eq(std::to_string(sp.total()), "4", "pool size");
  vector<int> a = sp.take(2, false);
  st_eq(std::to_string(a.size()) + ":" + std::to_string(sp.in_use()), "2:2", "two taken");
  vector<int> b = sp.take(2, true);
  st_eq(std::to_string(sp.in_use()), "4", "pool full");
  sp.give(a);
  sp.give(b);
  st_eq(std::to_string(sp.in_use()), "0", "all given back");
  // every slot is handed to one holder at a time, under contention
  std::atomic<int> peak{0}, live{0};
  std::atomic<bool> bad{false};
  vector<std::thread> th;
  for (int t = 0; t < 8; t++)
    th.emplace_back([&, t] {
      for (int i = 0; i < 40; i++) {
        int n = (t % 2) ? 1 : 2;
        vector<int> got = sp.take(n, t % 3 == 0);
        if ((int)got.size() != n) { bad = true; return; }
        int now = live += n;
        int was = peak.load();
        while (now > was && !peak.compare_exchange_weak(was, now)) {}
        live -= n;
        sp.give(got);
      }
    });
  for (auto& x : th) x.join();
  st_true(!bad, "every take got what it asked for");
  st_true(peak.load() <= 4, "the pool is never oversubscribed");
  st_eq(std::to_string(sp.in_use()), "0", "no slot leaked");
}

static void st_reduce_now() {
  st_true(reduce_now_over(0, 0, 1), "nothing to drain, so the mode is over at once");
  st_true(!reduce_now_over(0, 1, 1), "one cap, one running: not over");
  st_true(!reduce_now_over(1, 0, 1), "one cap, one queued: not over");
  st_true(!reduce_now_over(2, 2, 4), "four cap, four left: not over");
  st_true(reduce_now_over(2, 1, 4), "four cap, three left: over");
  st_true(reduce_now_over(0, 3, 4), "the running ones count too");
  // the budget is slots, so a job in its sweep stage counts double
  st_eq(std::to_string(sweep_worker_count(72, 7)), "7", "seven sweeps fit a 72 slot pool");
  st_eq(std::to_string(sweep_worker_count(72, 20)), "12", "sweeps stop at a third of it");
  st_eq(std::to_string(sweep_worker_count(12, 10)), "2", "a small pool takes two");
  st_eq(std::to_string(sweep_worker_count(8, 10)), "1", "the smallest pool still sweeps");
  st_true(reduction_admits(0, 24), "an empty budget admits a job");
  st_true(reduction_admits(22, 24), "the last pair still fits");
  st_true(!reduction_admits(23, 24), "one slot short admits nobody");
  st_true(!reduction_admits(26, 24), "over the budget admits nobody");
  st_true(reduction_admits(0, 2), "the smallest pool admits one job");
  st_true(!reduction_admits(2, 2), "and only one");
  // the budget follows the work waiting, up to three quarters of the pool
  st_eq(std::to_string(reduction_slot_budget(72, 2, 0, 0)), "2", "an empty queue asks for one job");
  st_eq(std::to_string(reduction_slot_budget(72, 2, 5, 0)), "10", "five waiting ask for five jobs");
  st_eq(std::to_string(reduction_slot_budget(72, 2, 500, 0)), "54", "a deep queue stops at the ceiling");
  st_eq(std::to_string(reduction_slot_budget(72, 2, 0, 12)), "24", "the running jobs are counted");
  st_eq(std::to_string(reduction_slot_budget(4, 2, 500, 0)), "2", "a small pool keeps a trial's slots");
  st_eq(std::to_string(reduction_slot_ceiling(8, 2)), "6", "eight slots leave two for a trial");
  // the pool size takes the smallest of the three limits and names it
  PoolFit f = pool_fit(48, 64ul * 1024 * 1024, 70, 80ul * 1024 * 1024, 500ul * 1024, 200ul * 1024);
  st_eq(std::to_string(f.by_cpu), "72", "one and a half slots a cpu thread");
  st_eq(std::to_string(f.by_ram), "91", "RAM at the limit percentage");
  st_eq(std::to_string(f.by_shm), "409", "a datadir each in the run dir");
  st_eq(std::to_string(f.chosen) + " " + f.bound, "72 cpu", "the cpu limit bound it");
  PoolFit g = pool_fit(48, 8ul * 1024 * 1024, 70, 80ul * 1024 * 1024, 500ul * 1024, 200ul * 1024);
  st_eq(std::to_string(g.chosen) + " " + g.bound, "11 RAM", "a small box is bound by RAM");
  PoolFit h = pool_fit(48, 64ul * 1024 * 1024, 70, 2ul * 1024 * 1024, 500ul * 1024, 200ul * 1024);
  st_eq(std::to_string(h.chosen) + " " + h.bound, "10 rundir", "a full run dir binds it");
  PoolFit i = pool_fit(48, 64ul * 1024 * 1024, 70, 80ul * 1024 * 1024, 0, 0);
  st_eq(std::to_string(i.chosen) + " " + i.bound, "72 cpu", "a cost that did not measure is left out");
  PoolFit j = pool_fit(48, 64ul * 1024 * 1024, 70, 80ul * 1024 * 1024, 1, 1);
  st_true(j.by_ram <= 4096 && j.by_shm <= 4096, "a cost read too small cannot run away");
  // the cost of a slot, off a directory the run can measure
  string d = "/dev/shm/corlogic_selftest_dir-" +                 // the pass runs in parallel
             std::to_string(std::hash<std::thread::id>{}(std::this_thread::get_id()));
  std::error_code dec;
  fs::remove_all(d, dec);
  fs::create_directories(d + "/sub", dec);
  write_file(d + "/a", string(1024, 'x'));
  write_file(d + "/sub/b", string(2048, 'x'));
  st_eq(std::to_string(dir_kb(d)), "3", "a directory tree measures in KB");
  st_eq(std::to_string(dir_kb(d + "/missing")), "0", "a directory that is not there is nothing");
  st_true(rss_kb(getpid()) > 0, "this process has a resident set");
  st_true(fs_free_kb("/dev/shm") > 0, "/dev/shm has room");
  fs::remove_all(d, dec);
}

static void st_rng() {
  Xoshiro256pp r1, r2;
  r1.seed(12345); r2.seed(12345);
  bool same = true;
  for (int i = 0; i < 64; i++) if (r1.next() != r2.next()) same = false;
  st_true(same, "the RNG repeats for one seed");
  Xoshiro256pp r3, r4;
  r3.seed(1); r4.seed(2);
  st_true(r3.next() != r4.next(), "another seed, another stream");
  r3.seed(7);
  st_true(r3.below(10) < 10, "below stays inside the bound");
  st_true(fnv1a("a") != fnv1a("b"), "fnv1a separates");
  st_eq(std::to_string(fnv1a("abc")), std::to_string(fnv1a("abc")), "fnv1a is stable");
}

static void st_config() {
  Cfg c = g_cfg;
  st_true(cfg_set(c, "QUERIES_PER_TRIAL", "42"), "cfg_set a long");
  st_eq(std::to_string(c.queries_per_trial), "42", "long parsed");
  st_true(cfg_set(c, "PLAN_FACTOR", "2.5"), "cfg_set a double");
  st_true(!cfg_set(c, "NO_SUCH_KEY", "1"), "an unknown key is refused");
  st_true(cfg_set(c, "TUI", "0"), "cfg_set a string");
  st_eq(c.tui, "0", "string parsed");
  // a per-side key needs its number, or a typo would be taken as a key and dropped
  st_true(cfg_set(c, "MYEXTRA_SIDE2", "--x"), "MYEXTRA_SIDE with a number");
  st_eq(c.myextra_side[2], "--x", "and it lands on that side");
  st_true(!cfg_set(c, "MYEXTRA_SIDE", "--x"), "MYEXTRA_SIDE with no number is refused");
  st_true(!cfg_set(c, "MYEXTRA_SIDES", "--x"), "MYEXTRA_SIDES is refused");
  st_true(cfg_set(c, "BIN_SIDE3", "/bin/x"), "BIN_SIDE with a number");
  st_true(!cfg_set(c, "BIN_SIDES", "/bin/x"), "BIN_SIDES is refused");
  st_true(cfg_set(c, "VER_SWEEP_JOBS", "3"), "cfg_set VER_SWEEP_JOBS");
  st_eq(std::to_string(c.ver_sweep_jobs), "3", "sweep job cap parsed");
  st_eq(g_cfg.rundir_base, "/dev/shm", "the run dir is tmpfs unless it is set");
  st_true(cfg_set(c, "RUNDIR_BASE", "/data/shm"), "cfg_set RUNDIR_BASE");
  st_eq(c.rundir_base, "/data/shm", "the run dir base moves");
  st_eq(std::to_string(RUNDIR_BASE_MAX), "63", "what a 107-byte socket path leaves the base");
  st_true(cfg_set(c, "RUNDIR_BASE", "./relshm"), "cfg_set takes a relative RUNDIR_BASE");
  st_true(!c.rundir_base.empty() && c.rundir_base[0] != '/',
          "a relative RUNDIR_BASE is what make_run_dirs refuses");
}

static void st_known_category() {
  for (const char* k : {"RESULT", "ERROR", "AFFECTED", "WARNING", "PLAN", "PERF",
                        "CHECKSUM", "CRASH", "TIMEOUT"})
    st_true(is_uid_category(k), k);
  // a category is matched exactly, so a typo must be refused rather than stored
  for (const char* k : {"RESLUT", "result", "", "*", "RESULT ", "SEGV"})
    st_true(!is_uid_category(k), "not a category");
}

// every check below reads global state and never writes it, so the concurrent pass can
// run the whole set from as many threads as it likes
static void st_report_prose() {
  st_eq(outcome_phrase("OK 5 row(s) 2 col(s) hash=1"), "returns 5 row(s)", "phrase, rows");
  st_eq(outcome_phrase("WARN 5 row(s) 2 col(s) hash=1 warn[1292]"), "returns 5 row(s)",
        "phrase, rows with a warning");
  st_eq(outcome_phrase("OK affected=3"), "succeeds (affected=3)", "phrase, affected");
  st_eq(outcome_phrase("WARN affected=3"), "succeeds (affected=3)",
        "phrase, affected with a warning");
  st_eq(outcome_phrase("ERROR 1064: bad syntax"), "fails with ERROR 1064", "phrase, error");
  st_eq(outcome_phrase("TIMEOUT (0)"), "does not finish before the query timeout",
        "phrase, timeout");
  st_eq(warn_codes_of("WARN 1 row(s) warn[1292,1366]"), "1292,1366", "warning codes");
  st_eq(warn_codes_of("OK 1 row(s) 1 col(s) hash=1"), "", "no warning codes");
  st_true(is_uid1("fa969630e78d"), "testcase id");
  st_true(!is_uid1("fa969630e78"), "testcase id, too short");
  st_true(!is_uid1("fa969630e78de"), "testcase id, too long");
  st_true(!is_uid1("fa969630e78g"), "testcase id, not hex");
  st_true(!is_uid1(""), "testcase id, empty");
}

static void st_old_mode() {
  st_eq(old_mode_without_utf8mb3(""), "", "nothing set");
  st_eq(old_mode_without_utf8mb3("UTF8_IS_UTF8MB3"), "", "only that flag");
  st_eq(old_mode_without_utf8mb3("utf8_is_utf8mb3"), "", "the same, lower case");
  st_eq(old_mode_without_utf8mb3("UTF8_IS_UTF8MB3,ZERO_DATE_TIME_CAST"), "ZERO_DATE_TIME_CAST",
        "first of two");
  st_eq(old_mode_without_utf8mb3("ZERO_DATE_TIME_CAST,UTF8_IS_UTF8MB3"), "ZERO_DATE_TIME_CAST",
        "last of two");
  st_eq(old_mode_without_utf8mb3("A,UTF8_IS_UTF8MB3,B"), "A,B", "in the middle");
  st_eq(old_mode_without_utf8mb3("NO_DUP_KEY_WARNINGS_WITH_IGNORE"),
        "NO_DUP_KEY_WARNINGS_WITH_IGNORE", "another flag is left alone");
}

static void st_engine_and_cleanup() {
  st_eq(engine_name("innodb"), "InnoDB", "engine name, InnoDB");
  st_eq(engine_name("MyISAM"), "MyISAM", "engine name, already cased");
  st_eq(engine_name("memory"), "MEMORY", "engine name, MEMORY");
  st_eq(engine_name("nosuchengine"), "nosuchengine", "engine name, passed through");
  st_eq(engine_component("aria"), "Storage Engine - Aria", "engine component");
  st_eq(engine_component("federatedx"), "Storage Engine - Federated", "engine component, alias");
  st_eq(engine_component("blackhole"), "", "engine component, none of its own");
  vector<string> t = created_objects("CREATE TABLE t1 (c1 INT);\n"
                                     "CREATE OR REPLACE TABLE `t 2` (c1 INT);\n"
                                     "CREATE VIEW v1 AS SELECT 1;\n"
                                     "INSERT INTO t1 VALUES(1);\n", "TABLE");
  st_true(t.size() == 2 && t[0] == "t1" && t[1] == "`t 2`", "created tables");
  st_eq(created_objects("CREATE TABLE IF NOT EXISTS t9(c1 INT);\n", "TABLE").at(0), "t9",
        "created table, IF NOT EXISTS");
  st_eq(cleanup_line("CREATE TABLE t1 (c1 INT);\nCREATE SEQUENCE s1;\n"),
        "DROP SEQUENCE IF EXISTS s1;\nDROP TABLE IF EXISTS t1;\n", "cleanup line");
  st_eq(cleanup_line("SELECT 1;\n"), "", "nothing made, nothing dropped");
}

static void st_all_pure() {
  st_text();
  st_upper_blanked();
  st_strip_limit();
  st_stmt_readonly();
  st_tx_tracking();
  st_rows_unspecified();
  st_order_by_total();
  st_access_swap();
  st_canon_value();
  st_bytes_helpers();
  st_uid_chain();
  st_reduce_rewrites();
  st_mutate_tuple();
  st_report_helpers();
  st_reduce_now();
  st_rng();
  st_config();
  st_known_category();
  st_report_prose();
  st_engine_and_cleanup();
  st_old_mode();
}

// these move a global out of the way and put it back, so they run on one thread
static void st_start_error() {
  string f = "/dev/shm/corlogic_selftest_errlog.txt";
  write_file(f, "2026-08-21  2:44:30 0 [Note] Server socket created\n"
                "2026-08-21  2:44:30 0 [ERROR] Unknown storage engine 'aria'\n"
                "2026-08-21  2:44:30 0 [ERROR] Aborting\n");
  st_eq(start_error_from_log(f), "Unknown storage engine 'aria'", "start error, last reason");
  write_file(f, "2026-08-21T02:44:30.000623Z 0 [ERROR] [MY-010077] [Server] "
                "Unknown/unsupported storage engine: aria\n"
                "2026-08-21T02:44:30.000643Z 0 [ERROR] [MY-010119] [Server] Aborting\n");
  st_eq(start_error_from_log(f), "Unknown/unsupported storage engine: aria",
        "start error, tags stripped");
  write_file(f, "2026-08-21  2:44:30 0 [Note] nothing wrong here\n");
  st_eq(start_error_from_log(f), "", "start error, none to report");
  st_eq(start_error_from_log("/dev/shm/corlogic_selftest_no_such_log"), "",
        "start error, no log at all");
  write_file(f, "2026-08-21  2:44:30 0 [ERROR] " + string(120, 'x') + "\n");
  st_true(start_error_from_log(f).size() == 90, "start error, capped");
  std::error_code ec;
  fs::remove(f, ec);
}

// The coverage shapes run with the version sweep off, so a report matrix and its version
// fields only ever exist after a real sweep. Both are proved here from made-up rows.
static void st_sweep_matrix() {
  vector<SweepRow> rows = {
    {"MD180826-mariadb-13.1.0-linux-x86_64-opt",
     "CS 13.1.0 da18481158c8aa112233445566778899aabbccdd (Optimized)",
     "DIFF: wrong result", true, true, true},
    {"EMD180826-mariadb-11.4.13-10-linux-x86_64-dbg", "ES 11.4.13-10", "DIFF: wrong result",
     true, false, true},
    {"UBASAN_MS211024-mysql-9.1.0-linux-x86_64-opt", "MySQL 9.1.0", "no diff", false, false, true},
  };
  string m = matrix_block(rows);
  for (const char* want : {"CS", "ES", "MS", "13.1", "11.4", "9.1", "opt", "dbg", "180826",
                           "211024", "da18481158c8aa112233445566778899aabbccdd",
                           "BASE/SOURCE", "DIFF: wrong result", "Same as base/source"})
    st_true(m.find(want) != string::npos, want);
  // a build measured against a held reference is not cleared by agreeing with it
  st_true(m.find("No diff found") == string::npos,
          "a row probed against a reference does not read as clean");
  // A/A moves both sides, so there is no reference to agree with and the plain phrase stands
  vector<SweepRow> aa_rows = rows;
  for (auto& r : aa_rows) { r.vs_base = false; r.is_base = false; }
  st_true(matrix_block(aa_rows).find("No diff found") != string::npos,
          "A/A row with no diff reads plainly");
  st_true(matrix_block({}).empty(), "no sweep, no matrix");

  vector<string> cs, es;
  sweep_versions(rows, cs, es);
  st_eq(join_list(cs, ","), "13.1", "affected Community mainlines");
  st_eq(join_list(es, ","), "11.4", "affected Enterprise mainlines");
  // MySQL carries no MDEV version field, and an unaffected build is not a version
  vector<string> cs2, es2;
  sweep_versions({rows[2]}, cs2, es2);
  st_true(cs2.empty() && es2.empty(), "an unaffected MySQL row adds no version");
}

// A crashed server is what the coverage shapes never produce, so the log the report reads
// is served from a file here instead.
static void st_crash_mechanism() {
  string f = "/dev/shm/corlogic_selftest_crashlog.txt";
  write_file(f, "2026-08-21  2:44:30 0 [Note] Server socket created\n"
                "260821  2:44:31 [ERROR] mysqld got signal 11 ;\n"
                "/test/bin/mariadbd(my_print_stacktrace+0x2e)[0x55f0]\n"
                "/test/bin/mariadbd(handle_fatal_signal+0x2f5)[0x55f1]\n"
                "/test/bin/mariadbd(_ZN4JOIN8optimizeEv+0x41)[0x55f2]\n"
                "/test/bin/mariadbd(_ZN13st_select_lex7prep_whEv+0x11)[0x55f3]\n");
  st_eq(crash_mechanism(f), "sig11:_ZN4JOIN8optimizeEv:_ZN13st_select_lex7prep_whEv",
        "signal and the first two useful frames");
  write_file(f, "260821  2:44:31 [ERROR] Assertion `0' failed\n"
                "/test/bin/mariadbd(_ZN4JOIN8optimizeEv+0x41)[0x55f2]\n");
  st_eq(crash_mechanism(f), "sig6:_ZN4JOIN8optimizeEv", "an assert reads as signal 6");
  write_file(f, "2026-08-21  2:44:30 0 [Note] nothing happened here\n");
  st_eq(crash_mechanism(f), "sig?", "no handler block, no frames");
  st_eq(crash_mechanism("/dev/shm/corlogic_selftest_no_such_crashlog"), "sig?",
        "no log at all");
  // the one line the report quotes back, taken from the same log
  write_file(f, "260821  2:44:31 [ERROR] mysqld got signal 11 ;\n"
                "Attempting backtrace\n");
  st_eq(crash_text_from_log(f), "got signal 11 ;", "the signal line");
  write_file(f, "mariadbd: sql_select.cc:1234: int JOIN::optimize(): "
                "Assertion `fixed()' failed.\n");
  st_eq(crash_text_from_log(f), "Assertion `fixed()' failed.", "the assert line");
  write_file(f, "2026-08-21  2:44:30 0 [Note] nothing happened here\n");
  st_eq(crash_text_from_log(f), "", "nothing to quote");
  std::error_code ec;
  fs::remove(f, ec);
}

// outcome_brief is what every candidate line, every replay note and every sweep row shows,
// so a change in its shape is a change in every report at once.
static void st_outcome_brief() {
  QOutcome o;
  o.state = QState::OK; o.cols = 2; o.row_count = 20; o.multiset_hash = 0xa73f696e4965ddb6ull;
  st_eq(outcome_brief(o), "OK 20 row(s) 2 col(s) hash=a73f696e4965ddb6", "a read that returned rows");
  o.capped = true;
  st_true(outcome_brief(o).find("(capped)") != string::npos, "a capped row list says so");
  QOutcome d;
  d.state = QState::OK; d.cols = 0; d.affected = 7;
  st_eq(outcome_brief(d), "OK affected=7", "a write reports its affected count");
  QOutcome e;
  e.state = QState::ERR; e.err = 1104; e.errmsg = "The SELECT would examine too many rows";
  st_eq(outcome_brief(e), "ERROR 1104: The SELECT would examine too many rows", "an error");
  QOutcome c;
  c.state = QState::CRASH; c.err = 2013; c.errmsg = "Lost connection";
  st_eq(outcome_brief(c), "CRASH (2013: Lost connection)", "a crash");
  QOutcome t;
  t.state = QState::TIMEOUT; t.err = 1969;
  st_eq(outcome_brief(t), "TIMEOUT (1969)", "a timeout");
  QOutcome k;
  k.state = QState::SKIP;
  st_eq(outcome_brief(k), "SKIP", "a statement that was not run");
  QOutcome w;
  w.state = QState::WARN; w.cols = 0; w.affected = 1;
  w.warnings.push_back({1292, "Truncated incorrect DOUBLE value"});
  st_true(outcome_brief(w).find("warn[1292") != string::npos, "a warning lists its code");
  w.warnings[0].msg = "Truncated incorrect DECIMAL value: 'one'";
  w.warnings.push_back({1264, "Warning", "Out of range value"});
  st_eq(outcome_brief(w),
        "WARN affected=1 warn[1292,1264] Truncated incorrect DECIMAL value: 'one'; Out of range value",
        "warning words follow the codes");
}

// The gate never crashes a server, so the two steps that secure a core run only here.
static void st_core_pickup() {
  string d = "/dev/shm/corlogic_selftest_cores";
  std::error_code ec;
  fs::remove_all(d, ec);
  fs::create_directories(d, ec);
  st_eq(newest_core_in(d), "", "an empty datadir has no core");
  write_file(d + "/ibdata1", "not a core");
  st_eq(newest_core_in(d), "", "a datadir file is not a core");
  write_file(d + "/core", "older");
  write_file(d + "/core.12345", "newer");
  string got = newest_core_in(d);
  st_true(got == d + "/core" || got == d + "/core.12345", "a core is found by its name");
  st_eq(newest_core_in("/dev/shm/corlogic_selftest_no_such_dir"), "", "no datadir, no core");
  copy_core_sparse(d + "/core.12345", d + "/bug1.core");
  st_eq(read_file(d + "/bug1.core"), "newer", "the core is copied to the report name");
  fs::remove_all(d, ec);
}

// what a confirmed bug drops while it waits, and what it must keep for its report
static void st_shed_data() {
  string d = "/dev/shm/corlogic_selftest_shed";
  std::error_code ec;
  fs::remove_all(d, ec);
  Reducer rd;
  rd.sides.resize(1);
  rd.sides[0].inst.set_paths(d + "/side1");
  fs::create_directories(d + "/side1/data/test", ec);
  fs::create_directories(d + "/side1/tmp", ec);
  fs::create_directories(d + "/side1/log", ec);
  write_file(d + "/side1/data/ibdata1", "pages");
  write_file(d + "/side1/data/test/t1.ibd", "pages");
  write_file(d + "/side1/data/core.7", "core");
  write_file(d + "/side1/tmp/scratch", "scratch");
  write_file(d + "/side1/log/master.err", "log");
  rd.shed_data();
  st_eq(read_file(d + "/side1/log/master.err"), "log", "the error log is kept");
  st_eq(read_file(d + "/side1/data/core.7"), "core", "the core is kept");
  st_true(!fs::exists(d + "/side1/data/ibdata1", ec), "a datadir file is dropped");
  st_true(!fs::exists(d + "/side1/data/test", ec), "a datadir subdirectory is dropped");
  st_true(!fs::exists(d + "/side1/tmp", ec), "the tmpdir is dropped");
  rd.sides.clear();                                  // no server ran: nothing to stop
  fs::remove_all(d, ec);
}

static void st_mutating() {
  st_core_pickup();
  st_shed_data();
  st_outcome_brief();
  st_sweep_matrix();
  st_crash_mechanism();
  st_stream_rewrites();
  st_compare_core();
  st_stats_refresh();
  st_uid1_chain();
  st_slot_pool();
  st_known_filter();
  st_start_error();
}

static int run_selftest(int threads) {
  printf("corlogic selftest\n");
  st_all_pure();
  st_mutating();
  long single = g_st_pass.load() + g_st_fail.load();
  printf("  %-24s %ld checks, %ld failed\n", "single thread:", single, g_st_fail.load());
  // the same checks from several threads at once: a shared buffer or a static local in
  // any of them shows up as a failure here and not in the pass above
  long before_fail = g_st_fail.load();
  vector<std::thread> th;
  for (int i = 0; i < threads; i++) th.emplace_back([] { st_all_pure(); });
  for (auto& t : th) t.join();
  printf("  %-24s %d threads, %ld failed\n", "concurrent:", threads,
         g_st_fail.load() - before_fail);
  long fail = g_st_fail.load();
  printf("selftest: %ld pass, %ld fail\n", g_st_pass.load(), fail);
  return fail ? 1 : 0;
}

static int main_real(int argc, char** argv);
int main(int argc, char** argv) { return main_real(argc, argv); }

static int main_real(int argc, char** argv) {
  // keep server cores small: drop shared/file-backed mappings (the InnoDB buffer pool);
  // the filter is inherited by every mariadbd corlogic spawns
  if (FILE* cf = fopen("/proc/self/coredump_filter", "w")) {
    fputs("0x11", cf);
    fclose(cf);
  }
  string config_path;
  parse_cli(argc, argv, config_path);
  if (g_selftest_threads >= 0) return run_selftest(std::max(1, g_selftest_threads));
  if (config_path.empty()) {
    if (fs::exists("corlogic.conf")) config_path = "corlogic.conf";
    else {
      string tool_conf = home_dir() + "/mariadb-qa/corlogic/corlogic.conf";
      if (fs::exists(tool_conf)) config_path = tool_conf;
    }
  }
  {
    Cfg cli_cfg = g_cfg;                 // CLI-parsed values
    g_cfg = Cfg{};
    if (!config_path.empty()) cfg_load_file(g_cfg, config_path, true);
    for (auto& [k, v] : cli_cfg.raw_kv) {
      cfg_set(g_cfg, k, v);
      if (k != "BASEDIRS") g_cli_block += k + "=" + v + "\n";   // written resolved, below
    }
    for (auto& b : cli_cfg.pos_basedirs) g_cfg.basedirs.push_back(b);
    if (cli_cfg.seed) g_cfg.seed = cli_cfg.seed;
    g_cfg.check_only = cli_cfg.check_only;
    g_cfg.resume_id = cli_cfg.resume_id;
    // A resumed run keeps the config it ran with: corlogic.conf.used is the base and a
    // value given on the command line still wins. A key the live config file now sets
    // differently is reported once the log is open.
    if (!g_cfg.resume_id.empty()) {
      string wd = find_run_workdir(g_cfg.workdir_base, g_cfg.resume_id);
      if (wd.empty())                                // said here, before any other setting
        die("--resume %s: no workdir for that id under %s", g_cfg.resume_id.c_str(),
            g_cfg.workdir_base.c_str());
      string used = wd + "/corlogic.conf.used";
      std::error_code ec;
      if (!fs::exists(used, ec)) {
        g_resume_notes.push_back("the workdir has no corlogic.conf.used, so the live config is used");
      } else {
        g_resume_notes.push_back("options read from " + used);
        std::map<string, string> live_kv;
        if (!config_path.empty()) {
          Cfg live_only{};
          cfg_load_file(live_only, config_path, false);
          for (auto& [k, v] : live_only.raw_kv) live_kv[k] = v;
        }
        Cfg merged{};
        cfg_load_file(merged, used, true);
        // what the earlier run set on its command line is a choice, not config drift
        std::set<string> cli_keys;
        {
          string txt = read_file(used);
          size_t cut = txt.find("# from the command line");
          for (size_t p = cut == string::npos ? txt.size() : cut; p < txt.size();) {
            size_t nl = txt.find('\n', p);
            string ln = txt.substr(p, nl == string::npos ? string::npos : nl - p);
            size_t eq = ln.find('=');
            if (eq != string::npos && !ln.empty() && ln[0] != '#')
              cli_keys.insert(trim(ln.substr(0, eq)));
            if (nl == string::npos) break;
            p = nl + 1;
          }
        }
        for (auto& [k, v] : merged.raw_kv) {
          if (cli_keys.count(k)) continue;
          auto it = live_kv.find(k);
          if (it != live_kv.end() && it->second != v)
            g_resume_notes.push_back("the config file now sets " + k + " to " + it->second +
                                     ", the run used " + v);
        }
        for (auto& [k, v] : cli_cfg.raw_kv) cfg_set(merged, k, v);
        merged.basedirs.insert(merged.basedirs.end(), cli_cfg.pos_basedirs.begin(),
                               cli_cfg.pos_basedirs.end());
        merged.seed = cli_cfg.seed ? cli_cfg.seed : merged.seed;
        merged.check_only = cli_cfg.check_only;
        merged.resume_id = cli_cfg.resume_id;
        g_cfg = std::move(merged);
      }
    }
  }
  if (g_cfg.generator_bin.empty()) g_cfg.generator_bin = home_dir() + "/mariadb-qa/generatorcpp/generator";
  if (g_cfg.weights_file.empty()) {
    string w = home_dir() + "/mariadb-qa/corlogic/corlogic.weights";
    if (fs::exists(w)) g_cfg.weights_file = w;
  }
  if (g_cfg.known_file.empty()) {
    string k = home_dir() + "/mariadb-qa/corlogic/corlogic.known";
    g_cfg.known_file = k;                // loaded if present
  }
  if (g_cfg.basedirs.empty())
    die("no basedirs given (config BASEDIRS= or command line; see --help)");

  if (g_cfg.seed) g_run.rng.seed(g_cfg.seed); else g_run.rng.seed_full();
  g_gen_seed_base = g_cfg.seed ? g_cfg.seed : g_run.rng.next();
  start_signal_watcher();
  start_spawn_service();                 // every server is forked from there, see spawn_logged
  signal(SIGINT, on_sigint);
  signal(SIGTERM, on_sigint);
  signal(SIGPIPE, SIG_IGN);
  mysql_library_init(0, nullptr, nullptr);

  g_sql_mode_final = resolve_sql_mode();
  // armed before the directories exist: an exit between the two would otherwise leave them
  // behind. It reads the paths off g_run, and those are empty until make_run_dirs sets them.
  atexit(teardown_all);
  make_run_dirs();
  open_run_log();
  check_build_stamp();
  resolve_weights_file();
  logline("corlogic %s starting - run %s", CORLOGIC_VERSION, g_run.id.c_str());
  logline("workdir: %s  rundir: %s", g_run.workdir.c_str(), g_run.rundir.c_str());
  logline("config: %s  seed: %" PRIu64 "  generator seed base: %" PRIu64,
          config_path.empty() ? "(defaults)" : config_path.c_str(), g_cfg.seed, g_gen_seed_base);
  logline("sql_mode: %s", g_sql_mode_final.c_str());
  logline("server caps: %s", g_cfg.mem_caps.c_str());   // every side runs with these
  if (!g_cfg.resume_id.empty()) {
    logline("resuming run %s from %s", g_run.id.c_str(), g_run.workdir.c_str());
    for (auto& d : g_resume_notes) logline("resume: %s", d.c_str());
    resume_state();
  } else {
    // conf.used is the whole run: the config file plus what the command line set, so
    // `corlogic --resume <id>` needs no options of its own
    string used;
    if (!config_path.empty()) used = read_file(config_path);
    if (!used.empty() && used.back() != '\n') used += "\n";
    used += "\n# from the command line\n" + g_cli_block;
    string bl;
    for (auto& b : g_cfg.basedirs) bl += (bl.empty() ? "" : ",") + b;
    used += "BASEDIRS=" + bl + "\n";
    write_file(g_run.workdir + "/corlogic.conf.used", used);
  }

  resolve_client_plugin_dir();
  if (!g_client_plugin_dir.empty())
    logline("client plugin dir: %s", g_client_plugin_dir.c_str());

  resolve_sides();
  // The pool size is measured off the pre-flight, so it is settled in run_discovery. A
  // WORKERS in the config is taken as given.
  logline("%u cpu threads, %zu sides: %s", std::max(1u, std::thread::hardware_concurrency()),
          g_sides.size(),
          g_cfg.workers > 0 ? ("WORKERS=" + std::to_string(g_cfg.workers)).c_str()
                            : "the pool is measured off the pre-flight");
  logline("sides: %zu", g_sides.size());
  for (auto& s : g_sides) logline("  %s  (%s)", s.label.c_str(), s.basedir.c_str());

  vector<Instance> insts;
  if (!start_sides(insts, "preflight", true)) {
    for (auto& i : insts) i.stop();
    die("pre-flight side startup failed");
  }
  bool gate_ok = caps_gate();
  print_check_matrix();
  if (!gate_ok) {
    for (auto& i : insts) i.stop();
    die("pre-flight capability gate failed - see messages above");
  }
  if (g_cfg.check_only) {
    for (auto& i : insts) i.stop();
    logline("--check requested: pre-flight OK, exiting");
    return 0;
  }
  resolve_combos();
  combo_cursor_load();
  logline("pre-flight OK");
  // vector SQL runs only when every side supports it: MariaDB CS >= 11.8, ES >= 11.4, MySQL never
  for (size_t i = 0; i < g_sides.size() && !g_deny_vector_sql; i++) {
    SideSpec& s = g_sides[i];
    bool ent = lower(g_caps[i].version_full + s.ver_string).find("enterprise") != string::npos;
    bool sup = s.vendor == Vendor::MariaDB && s.vnum() >= (ent ? 110400 : 110800);
    if (!sup) {
      g_deny_vector_sql = true;
      logline("vector SQL: filtered out - side%d (%s) has no vector support",
              s.idx, g_caps[i].version_full.c_str());
    }
  }
  // version-gated constructs: deny each entry some side cannot run
  for (auto& g : VERSION_GATED) {
    for (size_t i = 0; i < g_sides.size(); i++) {
      SideSpec& s = g_sides[i];
      long need = s.vendor == Vendor::MariaDB ? g.mariadb : g.mysql;
      if (need > 0 && s.vnum() >= need) continue;
      g_gated_deny.push_back(&g);
      logline("version-gated SQL: %s%s%s filtered out - no support on side%d (%s)",
              g.token, g.also ? " with " : "", g.also ? g.also : "",
              s.idx, g_caps[i].version_full.c_str());
      break;
    }
  }
  load_user_filters();
  // Which known list fits is a property of the run, so the run picks it: a MariaDB side
  // against a MySQL side needs the dialect list, an engine matrix needs the engine list.
  // Either one is added to the base list, never swapped for it, so the differences that are
  // known whatever the sides are stay muted. A KNOWN_FILE that was named wins outright.
  if (!g_cfg.known_file_set) {
    bool mysql = false, maria = false;
    for (auto& s : g_sides) {
      if (s.vendor == Vendor::MySQL) mysql = true;
      if (s.vendor == Vendor::MariaDB) maria = true;
    }
    string extra, why;
    if (mysql && maria) { extra = "corlogic.known.mysql"; why = "a MariaDB side against a MySQL side"; }
    else if (g_cfg.engines.size() > 1) { extra = "corlogic.known.engines"; why = "an engine matrix"; }
    if (!extra.empty()) {
      string path = home_dir() + "/mariadb-qa/corlogic/" + extra;
      if (fs::exists(path)) {
        g_cfg.known_file += "," + path;
        logline("known filter: %s added, the run is %s", extra.c_str(), why.c_str());
      } else {
        logline("known filter: the run is %s and %s is not there", why.c_str(), path.c_str());
      }
    }
  }
  load_known_file();
  resolve_plan_perf_report();
  resolve_compare_modes();
  return run_discovery(std::move(insts));
}
