// reducer.cpp — C++20 port of reducer.sh (MariaDB QA testcase reducer).
// Drop-in replacement: same env vars, same workdir layout, same external helpers,
// same exit codes, same on-screen logging format.
//
// Source-of-truth: ../reducer.sh (mirror line-for-line where practical).

#include <algorithm>
#include <array>
#include <atomic>
#include <cassert>
#include <cerrno>
#include <chrono>
#include <csignal>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <ctime>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <map>
#include <mutex>
#include <optional>
#include <random>
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
#include <signal.h>
#include <sys/stat.h>
#include <sys/resource.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

namespace fs = std::filesystem;

// ============================================================================
// CONFIG — user-configurable globals (mirror reducer.sh lines 36..147 order)
// ============================================================================
namespace cfg {

// === Basic options
std::string  INPUTFILE;
int          MODE                  = 4;
std::string  TEXT                  = "somebug";
int          MODE3_ANY_SIG         = 0;
int          WORKDIR_LOCATION      = 1;
std::string  WORKDIR_M3_DIRECTORY  = "/data";
std::string  MYEXTRA               = "--no-defaults --loose-innodb-buffer-pool-in-core-dump=0 --log-output=none --sql_mode=";
std::string  MYINIT                = "";
std::string  BASEDIR;  // initialized to CWD in main()
int          DISABLE_TOKUDB_AUTOLOAD     = 0;
int          DISABLE_TOKUDB_AND_JEMALLOC = 1;
std::string  SCRIPT_PWD;  // = dirname(readlink(argv[0]))

// === Sporadic testcases
int          FORCE_SKIPV          = 0;
int          FORCE_SPORADIC       = 0;
int          NR_OF_TRIAL_REPEATS  = 1;

// === True multi-threaded
int          PQUERY_MULTI         = 0;

// === Reduce startup issues
int          REDUCE_STARTUP_ISSUES = 0;

// === Reduce GLIBC/SS crashes
int          REDUCE_GLIBC_OR_SS_CRASHES = 0;
std::string  SCRIPT_LOC                 = "/usr/bin/script";

// === Replication
int          REPLICATION    = 0;
std::string  REPL_EXTRA     = "--gtid_strict_mode=1 --relay-log=relaylog";
std::string  MASTER_EXTRA   = "--log_bin=binlog --binlog_format=ROW --log_bin_trust_function_creators=1 --server_id=1";
std::string  SLAVE_EXTRA    = "--slave_skip_errors=ALL --server_id=2";

// === Hang issues
int          TIMEOUT_CHECK  = 350;

// === Timeout mariadbd
std::string  TIMEOUT_COMMAND = "";

// === Advanced
int          SLOW_DOWN_CHUNK_SCALING     = 0;
int          SLOW_DOWN_CHUNK_SCALING_NR  = 3;
int          USE_NEW_TEXT_STRING         = 0;
std::string  TEXT_STRING_LOC;  // = SCRIPT_PWD + "/new_text_string.sh"
int          SCAN_FOR_NEW_BUGS           = 1;
std::string  KNOWN_BUGS_LOC;      // = SCRIPT_PWD + "/known_bugs.strings"
std::string  KNOWN_BUGS_LOC_SAN;  // = SCRIPT_PWD + "/known_bugs.strings.SAN" — sanitizer-bug filter
std::string  NEW_BUGS_SAVE_DIR           = "/data/NEWBUGS";
int          SHOW_SETUP_DEBUGGING        = 0;
int          RR_TRACING                  = 0;
int          RR_SAVE_ALL_TRACES          = 0;
int          PAUSE_AFTER_EACH_OCCURRENCE = 0;

// === Expert
int          MULTI_THREADS               = 10;
int          MULTI_THREADS_INCREASE      = 5;
int          MULTI_THREADS_MAX           = 50;
std::string  PQUERY_EXTRA_OPTIONS        = "";
int          PQUERY_MULTI_THREADS        = 3;
int          PQUERY_MULTI_CLIENT_THREADS = 30;
long long    PQUERY_MULTI_QUERIES        = 99999999LL;
int          PQUERY_REVERSE_NOSHUFFLE_OPT = 0;
int          SAVE_RESULTS                = 0;

// === pquery
int          USE_PQUERY              = 0;
std::string  PQUERY_LOC;  // = SCRIPT_PWD + "/pquery/pquery2-md"
int          PQUERY_CONS_Q_FAIL      = 0;

// === Other
int          CLI_MODE                = 2;
int          ENABLE_QUERYTIMEOUT     = 0;
int          QUERYTIMEOUT            = 90;
int          LOAD_TIMEZONE_DATA      = 0;
int          STAGE1_LINES            = 90;
int          SKIPSTAGEBELOW          = 0;
int          SKIPSTAGEABOVE          = 99;
int          FORCE_KILL              = 0;

// === MDG (MariaDB Galera Cluster)
int          MDG                     = 0;
int          MDG_ISSUE_NODE          = 0;
int          NR_OF_NODES             = 3;
int          GALERA_NODE             = 1;
std::string  WSREP_PROVIDER_OPTIONS  = "";

// === Group Replication
int          GRP_RPL                 = 0;
int          GRP_RPL_ISSUE_NODE      = 0;

// === MODE 5
int          MODE5_COUNTTEXT             = 1;
std::string  MODE5_ADDITIONAL_TEXT       = "";
int          MODE5_ADDITIONAL_COUNTTEXT  = 1;

// === MODE 11
std::string  MODE11_TYPE           = "dump";
std::string  MODE11_BINLOG_FORMAT  = "MIXED";

// === FireWorks
int          FIREWORKS          = 0;
int          FIREWORKS_LINES    = 200000;
int          FIREWORKS_TIMEOUT  = 450;

// === Old ThreadSync
int          TS_TRXS_SETS         = 0;
int          TS_DBG_CLI_OUTPUT    = 0;
int          TS_DS_TIMEOUT        = 10;
int          TS_VARIABILITY_SLEEP = 1;

// === MYEXTRA-derived (extracted at startup; cleaned out of MYEXTRA itself)
std::string  TOKUDB;
std::string  ROCKSDB;
std::string  BL_ENCRYPTION;
std::string  KF_ENCRYPTION;
std::string  BINLOG;
std::string  ONLYFULLGROUPBY;
std::string  SPECIAL_MYEXTRA_OPTIONS;

}  // namespace cfg

// ============================================================================
// STATE — internal runtime variables (mirror set_internal_options())
// ============================================================================
namespace state {

std::string  WORKD;           // working dir (e.g. /dev/shm/${EPOCH})
std::string  WORKF;           // workdir + "/in.sql"      — current best testcase
std::string  WORKT;           // workdir + "/in.tmp"      — trial testcase
std::string  WORKO;           // workdir + "/<basename>_out" — final output
std::string  EPOCH;           // nanosecond timestamp identifying this run
std::string  WHOAMI;          // current username
int          SPORADIC        = 0;
int          SKIPV           = 0;
std::string  STAGE           = "0";
long long    TRIAL           = 0;
long long    ATTEMPT         = 0;
int          ABORT_ACTIVE    = 0;
volatile sig_atomic_t SIGINT_RECEIVED = 0;  // distinguishes a real Ctrl+C from internal guard-trip aborts
int          MYUSER_EFFECTIVE_UID = 0;
std::string  DROPC;           // DROP DATABASE/CREATE DATABASE template
std::string  TS_INPUTDIR;
int          TS_THREADS              = 0;
int          TS_ELIMINATION_THREAD_ID = 0;
int          TS_TE_DIR_SWAP_DONE     = 0;
std::string  TYPESCRIPT_UNIQUE_FILESUFFIX;
int          MULTI_REDUCER       = 0;          // 1 inside a subreducer
int          STARTUPCOUNT        = 0;
std::string  MYSQLD_START_TIME;
int          MULTI_REDUCER_REP_FAILED = 0;
std::string  MYBASE;             // last seen --basedir / --datadir line

// Additional internal state vars set by set_internal_options() + main flow
std::string  RUNMODE          = "MULTI";   // "MULTI" or "FIREWORKS"
std::string  MYUSER;                       // = whoami
std::string  ATLEASTONCE      = "[]";      // bracket-form "trial result history"
int          STUCKTRIAL       = 0;
int          NOISSUEFLOW      = 0;
long long    CHUNK_LOOPS_DONE = 99999999999LL;
int          C_COL_COUNTER    = 1;
int          TS_ELIMINATED_THREAD_COUNT = 0;
int          TS_ORIG_VARS_FLAG = 0;
int          TS_DEBUG_SYNC_REQUIRED_FLAG = 0;
int          NR_OF_NEWBUGS    = 0;
int          TIMEOUT_CHECK_REAL = 0;
std::string  BIN;                          // mariadbd / mysqld binary path
int          TOKUDB_RUN_DETECTED = 0;
std::string  COPY_TARGET;
std::string  WORK_BUG_DIR;
std::string  WORK_INIT;     // run_init.sh
std::string  WORK_START;    // run_start.sh
std::string  WORK_STOP;     // run_stop.sh
std::string  WORK_CL;       // run_cl.sh
std::string  WORK_RUN;      // run.sh
std::string  WORK_RUN_PQUERY;
std::string  WORK_OUT;      // reducer's _out testcase
std::string  WORK_HISTORY;  // .history file
std::string  WORK_OUT_HISTORY; // _out.history
std::string  WORKDIR_BASE;  // /dev/shm or /mnt/ram or /tmp etc.

// reducer.log path (cached)
std::string  REDUCER_LOG_PATH;

// Port-picker module-level state (mirror reducer.sh:1751..1753)
std::string  INIT_EMPTY_PORT_CLAIM_DIR = "/tmp/.mariadb_qa_ports";
std::string  INIT_EMPTY_PORT_CLAIMED;
int          INIT_EMPTY_PORT_TRAP_SET = 0;
int          NEWPORT = 0;

// MYEXTRA-derived (rr binary launcher)
std::string  RR_OPTIONS;

// Init / setup globals
std::string  THIS_REDUCER;
std::string  TMP_DIR;            // = WORKD + "/tmp"  (also exported as $TMP env var)
std::string  WORK_START_VALGRIND;
std::string  WORK_GDB;
std::string  WORK_PARSE_CORE;
std::string  WORK_HOW_TO_USE;
std::string  WORK_PQUERY_BIN;
std::string  WORK_BASEDIR_FILE;  // ${EPOCH}_mybase
std::string  QCTEXT;             // Query Correctness text marker (optional, env-driven)

// jemalloc fragments
std::string  JE1, JE2, JE3, JE4;

// MID / INIT
std::string  MID;
std::string  START_OPT;
std::string  INIT_OPT;
std::string  INIT_TOOL;
std::string  VERSION_INFO;
std::string  VERSION_INFO_2;
std::string  MID_OPTIONS;

// First-startup flag
int          FIRST_MYSQLD_START_FLAG = 0;

// node[1..3] paths (Galera / Group Replication)
std::string  node1, node2, node3;

// Server start/stop state
int          MYPORT = 0;
int          MYPORT_SLAVE = 0;
std::string  PIDV;          // background mariadbd PID (master/single)
std::string  PIDV_SLAVE;    // slave PID
std::string  MYSQLD_SLAVE_START_TIME;
int          STAGE8_NOT_STARTED_CORRECTLY = 0;
int          STAGE9_NOT_STARTED_CORRECTLY = 0;

// Shutdown / run-time accounting
long long    SHUTDOWN_TIME_START = 0;
long long    SHUTDOWN_DURATION = 0;
long long    RUN_TIME = 0;
long long    PRE_SHUTDOWN_RUNTIME = 0;
long long    MODE0_MIN_SHUTDOWN_TIME = 0;

// Stage check flags
int          STAGE8_CHK = 0;
int          STAGE9_CHK = 0;
std::string  TS_ORIG_DATAINPUTFILE;

// process_outcome locals
std::string  NEXTACTION = "& continuing";
int          COLUMN = 0;
int          COUNTCOLS = 0;

// multi_reducer state
int          MULTI_FOUND = 0;
std::vector<std::string> MULTI_PIDS;     // PID per subreducer thread
std::string  TS_DATAINPUTFILE;
int          TS_ORIG_THREADS = 0;
std::string  BASEDIR_ALT_PATH;

// Chunking state
long long    LINECOUNTF = 0;
long long    CHUNK = 0;
long long    RANDLINE = 0;
long long    ENDLINE = 0;
long long    REALCHUNK = 0;
long long    TAIL_ANCHOR_LINE = 0;
long long    TAIL_ANCHOR_LINE_CACHED = 0;
std::string  WORKF_STAT_CACHED;

// Reducer log file handle (opened once WORKD exists)
std::ofstream reducer_log;
std::mutex    log_mutex;

// PRNG (per-thread state is overkill for reducer's modest use; one shared mutex-guarded engine)
std::mt19937_64 rng;
std::mutex      rng_mutex;

}  // namespace state

// ============================================================================
// UTIL — small helpers (string, file, shell, time)
// ============================================================================
namespace util {

inline std::string now_timestamp() {
  auto now  = std::chrono::system_clock::now();
  auto t    = std::chrono::system_clock::to_time_t(now);
  std::tm tm{};
  localtime_r(&t, &tm);
  char buf[32];
  std::snprintf(buf, sizeof(buf), "%04d-%02d-%02d %02d:%02d:%02d",
                tm.tm_year + 1900, tm.tm_mon + 1, tm.tm_mday,
                tm.tm_hour, tm.tm_min, tm.tm_sec);
  return buf;
}

inline std::string getenv_or(const char* name, const std::string& dflt = "") {
  const char* v = std::getenv(name);
  return v ? std::string(v) : dflt;
}

inline bool file_exists(const std::string& p) {
  std::error_code ec;
  return fs::exists(p, ec);
}

inline bool file_readable(const std::string& p) {
  return access(p.c_str(), R_OK) == 0;
}

inline bool dir_exists(const std::string& p) {
  std::error_code ec;
  return fs::is_directory(p, ec);
}

inline void mkdir_p(const std::string& p) {
  std::error_code ec;
  fs::create_directories(p, ec);
}

inline std::string read_file(const std::string& p) {
  std::ifstream in(p, std::ios::binary);
  std::ostringstream ss; ss << in.rdbuf();
  return ss.str();
}

inline void write_file(const std::string& p, const std::string& contents) {
  std::ofstream out(p, std::ios::binary | std::ios::trunc);
  out.write(contents.data(), static_cast<std::streamsize>(contents.size()));
}

inline void append_file(const std::string& p, const std::string& contents) {
  std::ofstream out(p, std::ios::binary | std::ios::app);
  out.write(contents.data(), static_cast<std::streamsize>(contents.size()));
}

inline long long count_lines(const std::string& p) {
  std::ifstream in(p, std::ios::binary);
  if (!in) return 0;
  long long n = 0;
  std::string l;
  while (std::getline(in, l)) ++n;
  return n;
}

// Trim ASCII whitespace.
inline std::string ltrim(std::string s) {
  size_t i = 0;
  while (i < s.size() && std::isspace(static_cast<unsigned char>(s[i]))) ++i;
  return s.substr(i);
}
inline std::string rtrim(std::string s) {
  size_t i = s.size();
  while (i > 0 && std::isspace(static_cast<unsigned char>(s[i - 1]))) --i;
  return s.substr(0, i);
}
inline std::string trim(std::string s) { return ltrim(rtrim(std::move(s))); }

// Collapse repeated runs of ' ' to a single space.
inline std::string squeeze_spaces(std::string s) {
  std::string out; out.reserve(s.size());
  bool prev_space = false;
  for (char c : s) {
    bool is_space = (c == ' ');
    if (is_space && prev_space) continue;
    out.push_back(c);
    prev_space = is_space;
  }
  return out;
}

inline bool starts_with(std::string_view s, std::string_view pfx) {
  return s.size() >= pfx.size() && s.compare(0, pfx.size(), pfx) == 0;
}
inline bool ends_with(std::string_view s, std::string_view sfx) {
  return s.size() >= sfx.size() && s.compare(s.size() - sfx.size(), sfx.size(), sfx) == 0;
}
inline bool contains(std::string_view s, std::string_view needle) {
  return s.find(needle) != std::string_view::npos;
}

inline std::vector<std::string> split(const std::string& s, char delim) {
  std::vector<std::string> out;
  std::string cur;
  std::istringstream is(s);
  while (std::getline(is, cur, delim)) out.push_back(cur);
  return out;
}

inline std::string replace_all(std::string s, std::string_view from, std::string_view to) {
  if (from.empty()) return s;
  std::string out; out.reserve(s.size());
  size_t i = 0;
  while (i <= s.size() - from.size() && s.size() >= from.size()) {
    if (s.compare(i, from.size(), from) == 0) {
      out.append(to);
      i += from.size();
    } else {
      out.push_back(s[i++]);
    }
  }
  out.append(s.substr(std::min(i, s.size())));
  return out;
}

// Shell out via /bin/bash -c (NOT /bin/sh — many systems link sh to dash which
// drops bash-only features like [[ ]], =~, ${var^^}, $RANDOM, brace expansion,
// etc.). Bash is the reducer.sh shebang and our authoring assumption. We fork
// + execv("/bin/bash", "-c", cmd) for sh(); popen takes the same path via
// SHELL env var, which we set in main().
inline int sh(const std::string& cmd) {
  pid_t pid = fork();
  if (pid < 0) return -1;
  if (pid == 0) {
    // Child: exec bash -c <cmd>.
    execl("/bin/bash", "bash", "-c", cmd.c_str(), (char*)nullptr);
    _exit(127);
  }
  int status = 0;
  if (waitpid(pid, &status, 0) < 0) return -1;
  if (WIFEXITED(status)) return WEXITSTATUS(status);
  return status;
}

// Capture stdout from `bash -c <cmd>` (single-shot; not for streaming).
inline std::string sh_capture(const std::string& cmd) {
  std::string out;
  int pipefd[2];
  if (pipe(pipefd) != 0) return out;
  pid_t pid = fork();
  if (pid < 0) { close(pipefd[0]); close(pipefd[1]); return out; }
  if (pid == 0) {
    close(pipefd[0]);
    dup2(pipefd[1], 1);
    close(pipefd[1]);
    execl("/bin/bash", "bash", "-c", cmd.c_str(), (char*)nullptr);
    _exit(127);
  }
  close(pipefd[1]);
  char buf[4096];
  ssize_t n;
  while ((n = read(pipefd[0], buf, sizeof(buf))) > 0) out.append(buf, static_cast<size_t>(n));
  close(pipefd[0]);
  int status = 0;
  waitpid(pid, &status, 0);
  (void)status;
  return out;
}

inline std::string sh_capture_trimmed(const std::string& cmd) {
  std::string s = sh_capture(cmd);
  while (!s.empty() && (s.back() == '\n' || s.back() == '\r')) s.pop_back();
  return s;
}

// Cross-filesystem-safe rename: tries fs::rename, falls back to cp+rm if
// EXDEV (cross-device link). Bash `mv` handles this automatically; std::rename
// (POSIX rename(2)) does NOT, so we emulate.
inline bool move_file(const std::string& from, const std::string& to) {
  std::error_code ec;
  fs::rename(from, to, ec);
  if (!ec) return true;
  // Fall back to copy + remove.
  fs::copy_file(from, to, fs::copy_options::overwrite_existing, ec);
  if (ec) return false;
  fs::remove(from);
  return true;
}

// Resolve absolute path via realpath(); fallback to input on error.
inline std::string realpath_or(const std::string& p) {
  char* r = realpath(p.c_str(), nullptr);
  if (!r) return p;
  std::string out(r);
  std::free(r);
  return out;
}

// Like bash $(date +'%F %T'). Already covered by now_timestamp().

// Nanosecond timestamp string — mirrors bash $(date +%s%N).
inline std::string nsec_epoch() {
  using namespace std::chrono;
  auto ns = duration_cast<nanoseconds>(system_clock::now().time_since_epoch()).count();
  return std::to_string(static_cast<long long>(ns));
}

// Generate a random suffix similar to bash $RANDOM (0..32767). For reducer
// purposes any uniform integer suffices.
inline std::string rand_suffix() {
  std::lock_guard<std::mutex> g(state::rng_mutex);
  std::uniform_int_distribution<int> d(0, 32767);
  return std::to_string(d(state::rng)) + std::to_string(d(state::rng));
}

}  // namespace util

// ============================================================================
// LOGGING — echoit / echoit_overwrite (mirror reducer.sh:620..637)
// ============================================================================

// Forward decl: abort_reducer() called when INPUTFILE disappears mid-run.
static void abort_reducer();

static void echoit(std::string_view msg) {
  std::string line = util::now_timestamp() + " " + std::string(msg);
  {
    std::lock_guard<std::mutex> g(state::log_mutex);
    std::cout << line << "\n";
    std::cout.flush();
    // Mirror bash `if [ -r $WORKD/reducer.log ]; then ... >> $WORKD/reducer.log; fi`:
    // only append if the file actually exists right now (it may have been wiped
    // by an external watchdog like ~/ka / ~/ds since the last write).
    if (!state::REDUCER_LOG_PATH.empty() && util::file_readable(state::REDUCER_LOG_PATH)) {
      std::ofstream out(state::REDUCER_LOG_PATH, std::ios::app);
      if (out) { out << line << "\n"; }
    }
  }
  if (state::ABORT_ACTIVE != 1) {
    if (!cfg::INPUTFILE.empty() && !util::file_readable(cfg::INPUTFILE)) {
      abort_reducer();
    }
  }
}

static void echoit_overwrite(std::string_view msg) {
  std::string line = util::now_timestamp() + " " + std::string(msg);
  std::lock_guard<std::mutex> g(state::log_mutex);
  std::cout << line << "\r";
  std::cout.flush();
}

// ============================================================================
// DISKSPACE — mirror reducer.sh:638..660
// ============================================================================
static void diskspace(std::string check_path = "", long long min_mb = 500) {
  if (check_path.empty()) check_path = state::WORKD;
  while (true) {
    if (check_path.empty()) break;
    if (!util::dir_exists(check_path)) util::mkdir_p(check_path);
    std::string test_path = check_path;
    while (!test_path.empty() && test_path != "/" && !util::dir_exists(test_path)) {
      test_path = fs::path(test_path).parent_path().string();
    }
    if (test_path.empty() || !util::dir_exists(test_path)) break;
    std::string cmd = "df -k -P \"" + test_path + "\" 2>/dev/null | awk 'NR==2{print $4}'";
    std::string free_kb_s = util::sh_capture_trimmed(cmd);
    if (free_kb_s.empty()) break;
    long long free_kb = 0;
    try { free_kb = std::stoll(free_kb_s); } catch (...) { break; }
    if (free_kb >= min_mb * 1024) break;
    echoit("Likely out of diskspace on " + check_path + " (only "
           + std::to_string(free_kb / 1024) + "MB free, need at least "
           + std::to_string(min_mb) + "MB)... Pausing 10 minutes");
    std::this_thread::sleep_for(std::chrono::seconds(600));
    echoit("Slept 10 minutes, re-checking diskspace on " + check_path + "...");
  }
}

// ============================================================================
// SAVE_RR_TRACE — mirror reducer.sh:661..671
// ============================================================================
static void save_rr_trace(const std::string& dest) {
  fs::remove_all(dest);
  util::mkdir_p(dest);
  diskspace(dest);
  util::sh("cp -r " + state::WORKD + "/rr/* " + dest + "/");
  fs::remove_all(state::WORKD + "/rr");
  util::sh("chmod -R 777 " + dest + "/");
  util::sh("chmod -R +rX " + dest + "/");
}

// ============================================================================
// Forward declarations for the major function blocks (defined later in the
// porting work). Each mirrors a reducer.sh function 1:1.
// ============================================================================
static void options_check(const std::string& cli_arg);
static void remove_dropc(const std::string& path);
static void set_internal_options();
static void kill_multi_reducer();
static void multi_reducer(/*...*/);
static void multi_reducer_decide_input();
static void TS_init_all_sql_files();
static void _init_empty_port_cleanup();
static int  init_empty_port();
static void init_workdir_and_files();
static void generate_run_scripts();
static void init_mysql_dir();
static void start_mysqld_or_valgrind_or_mdg();
static void start_mdg_main();
static void gr_start_main();
static void start_mysqld_main();
static void start_valgrind_mysqld_main();
static void determine_chunk();
static void control_backtrack_flow();
static void cut_random_chunk();
static void cut_fireworks_chunk_and_shuffle();
static void cut_threadsync_chunk();
static void run_and_check();
static int  run_sql_code();
static void write_workO_options_header();
static void cleanup_and_save();
static void process_outcome(/*...*/);
static void stop_mysqld_or_mdg();
static void finish(const std::string& reason = "");
static void copy_workdir_to_tmp();
static void report_linecounts();
static void verify_not_found();
static void apply_tcp_to_workt();
static void verify();
static void fireworks_setup();

// ============================================================================
// ABORT — mirror reducer.sh:672..727
// ============================================================================
static void abort_reducer() {
  std::signal(SIGINT, SIG_DFL);
  state::ABORT_ACTIVE = 1;
  if (!util::dir_exists(state::WORKD)) {
    if (util::file_readable(state::WORKO)) {
      echoit("[Abort] The work directory (" + state::WORKD + ") disappeared, it was likely deleted. "
             "Last good known testcase: " + state::WORKO + " (provided the disk being used did not run out of space). Terminating.");
    } else {
      echoit("[Abort] The work directory (" + state::WORKD + ") disappeared, it was likely deleted. Terminating.");
    }
    echoit("[Abort] Any 'Killed' message on the next line is reducer self-terminating after an [Abort]; it is not caused by any watchdog");
    kill(getpid(), SIGKILL);
    std::exit(1);
  } else if (util::file_readable(cfg::INPUTFILE)) {
    if (state::SIGINT_RECEIVED) {
      echoit("[Abort] CTRL+C Was pressed. Dumping variable stack");
    } else {
      // Hit when a stage-loop guard (!file_readable(THIS_REDUCER), !dir_exists(WORKD), ...) called abort_reducer(). Naming the actual trigger keeps the log honest — "CTRL+C" used to be printed unconditionally here, hiding non-signal causes.
      std::string trigger = "internal guard";
      if (!util::file_readable(state::THIS_REDUCER))     trigger = "THIS_REDUCER (" + state::THIS_REDUCER + ") not readable";
      else if (!util::file_readable(cfg::INPUTFILE))     trigger = "INPUTFILE (" + cfg::INPUTFILE + ") not readable";
      else if (!util::dir_exists(state::WORKD))          trigger = "WORKD (" + state::WORKD + ") missing";
      echoit("[Abort] Internal abort triggered (" + trigger + "). Dumping variable stack");
    }
  } else {
    echoit("[Abort] Original input file (" + cfg::INPUTFILE + ") no longer present or readable.");
    echoit("[Abort] The source for this reducer was likely deleted. Terminating.");
    std::cout << "[Abort] Any 'Killed' message on the next line is reducer self-terminating after an [Abort]; it is not caused by any watchdog\n";
    kill(getpid(), SIGKILL);
    std::exit(1);
  }
  echoit("[Abort] WORKD: " + state::WORKD + " (reducer log @ " + state::WORKD + "/reducer.log) | EPOCH ID: " + state::EPOCH);
  if (util::file_readable(state::WORKO)) {
    echoit("[Abort] Best testcase thus far: " + state::WORKO);
  } else {
    echoit("[Abort] Best testcase thus far: " + cfg::INPUTFILE + " (= input file; no optimizations were successful)");
  }
  echoit("[Abort] End of dump stack");
  if (cfg::MDG == 1) {
    echoit("[Abort] Ensuring any remaining MDG nodes are terminated and removed");
    util::sh("( ps -def | grep -E 'n*.cnf' | grep " + state::EPOCH + " | awk '{print $2}' | xargs -I{} kill -9 {} >/dev/null 2>&1; ) >/dev/null 2>&1");
    std::this_thread::sleep_for(std::chrono::seconds(2));
    util::sh("sync");
  }
  if (cfg::GRP_RPL == 1) {
    echoit("[Abort] Ensuring any remaining Group Replication nodes are terminated and removed");
    util::sh("( ps -def | grep -E 'node1_socket|node2_socket|node3_socket' | grep " + state::EPOCH + " | awk '{print $2}' | xargs -I{} kill -9 {} >/dev/null 2>&1; ) >/dev/null 2>&1");
    std::this_thread::sleep_for(std::chrono::seconds(2));
    util::sh("sync");
  }
  echoit("[Abort] Ensuring any remaining processes are terminated");
  std::string pids;
  if (!state::EPOCH.empty()) {
    pids = util::sh_capture_trimmed(
      "ps -def | grep -E --binary-files=text " + state::WHOAMI +
      " | grep -E --binary-files=text " + state::EPOCH +
      " | grep -E --binary-files=text -v grep | awk '{print $2}' | tr '\\n' ' '");
  } else {
    echoit("Assert: $EPOCH is empty! in abort()!");
  }
  echoit("[Abort] Terminating these PID's: " + pids);
  util::sh("( kill -9 " + pids + " >/dev/null 2>&1; ) >/dev/null 2>&1");
  if (util::file_readable(cfg::INPUTFILE)) {
    echoit("[Abort] What follows below is a call of finish(), the results are likely correct, but may be mangled due to the interruption");
  } else {
    echoit("[Abort] What follows below is a call of finish(), the results are likely correct, but may be mangled due to the abort");
  }
  finish("abort");
  std::exit(2);
}

// ============================================================================
// SIGINT HANDLER
// ============================================================================
static void install_signal_handlers() {
  struct sigaction sa{};
  sa.sa_handler = [](int){ state::SIGINT_RECEIVED = 1; abort_reducer(); };
  sigemptyset(&sa.sa_mask);
  sa.sa_flags = 0;
  sigaction(SIGINT, &sa, nullptr);
}

// ============================================================================
// preprocess_myextra — mirror reducer.sh:385..497
// Load-time preamble: BASEDIR auto-fallback to /data/VARIOUS_BUILDS, replication
// blanking, rr launcher, plugin .so extraction (ROCKSDB / TOKUDB),
// binary-log encryption, keyring-file encryption, binlog, ONLY_FULL_GROUP_BY.
// All extracted strings end up in SPECIAL_MYEXTRA_OPTIONS, scrubbed from MYEXTRA.
// ============================================================================
static std::string extract_option(std::string& myextra, const std::string& egrep_pat) {
  // Extract first match of `egrep_pat` from MYEXTRA via shell's grep -o.
  // Mirrors `echo "$MYEXTRA" | grep -o "<pat>" | head -n1` semantics.
  // Use `grep -oE -- '<pat>'` so leading `--` in the pattern is not parsed as
  // an option by grep (bash sidesteps this by literal `\-\-` in the pattern).
  std::string cmd = "echo \"" + myextra + "\" | grep -oE -- '" + egrep_pat + "' | head -n1";
  std::string found = util::sh_capture_trimmed(cmd);
  if (!found.empty()) {
    // Remove the literal `found` substring from myextra (first occurrence(s)).
    myextra = util::sh_capture(
      "echo \"" + myextra + "\" | sed \"s|" + found + "||g\"");
    while (!myextra.empty() && (myextra.back() == '\n' || myextra.back() == '\r')) myextra.pop_back();
  }
  return found;
}

static void preprocess_myextra() {
  // BASEDIR auto-fallback to /data/VARIOUS_BUILDS (lines 393..403)
  std::string basedir_alt = util::replace_all(cfg::BASEDIR, "/test/", "/data/VARIOUS_BUILDS/");
  if (!util::dir_exists(cfg::BASEDIR) && !util::dir_exists(basedir_alt)) {
    std::cerr << "Assert: Neither '" << cfg::BASEDIR << "' nor '" << basedir_alt << "' directories exist, please set the BASEDIR variable correctly\n";
    std::exit(1);
  }
  if (!util::dir_exists(cfg::BASEDIR) && util::dir_exists(basedir_alt)) {
    std::cerr << "Note: Updating BASEDIR from '" << cfg::BASEDIR << "' to '" << basedir_alt
              << "' as set BASEDIR did not exist, but the same/required server build was found in /data/VARIOUS_BUILDS/\n";
    std::this_thread::sleep_for(std::chrono::seconds(2));
    cfg::BASEDIR = basedir_alt;
  }
  // Replication blanking (lines 418..421)
  if (cfg::REPLICATION != 1) {
    cfg::REPL_EXTRA.clear();
    cfg::MASTER_EXTRA.clear();
    cfg::SLAVE_EXTRA.clear();
  }
  // rr launcher (lines 424..430)
  if (cfg::RR_TRACING == 1) {
    std::string which_rr = util::sh_capture_trimmed("which rr");
    if (which_rr.empty()) {
      std::cerr << "Assert: rr binary not found! Please install rr and ensure: which rr works at the command line\n";
      std::exit(1);
    }
    state::RR_OPTIONS = which_rr + " record --chaos";
    setenv("RR_OPTIONS", state::RR_OPTIONS.c_str(), 1);
  }
  // ROCKSDB extraction (lines 432..456)
  if (util::contains(cfg::MYEXTRA, "ha_rocksdb.so")) {
    if (!util::file_readable(cfg::BASEDIR + "/lib/mysql/plugin/ha_rocksdb.so")) {
      std::cerr << "Error: MYEXTRA contains ha_rocksdb.so, yet " << cfg::BASEDIR << "/lib/mysql/plugin/ha_rocksdb.so does not exist.\n";
      std::exit(1);
    }
    cfg::ROCKSDB = extract_option(cfg::MYEXTRA, "--plugin[-_][^ ]+ha_rocksdb.so");
    if (util::contains(cfg::MYEXTRA, "ha_rocksdb.so") ||
        util::contains(cfg::ROCKSDB, "ha_tokudb.so")) {
      std::cerr << "Error: The MYEXTRA string is formulated in a seemingly complex manner (ha_rocksdb.so).\n";
      std::exit(1);
    }
  }
  // TOKUDB extraction (lines 458..489)
  if (cfg::DISABLE_TOKUDB_AND_JEMALLOC == 0) {
    if (util::contains(cfg::MYEXTRA, "ha_tokudb.so")) {
      if (!util::file_readable(cfg::BASEDIR + "/lib/mysql/plugin/ha_tokudb.so")) {
        std::cerr << "Error: MYEXTRA contains ha_tokudb.so, yet " << cfg::BASEDIR << "/lib/mysql/plugin/ha_tokudb.so does not exist.\n";
        std::exit(1);
      }
      cfg::TOKUDB = extract_option(cfg::MYEXTRA, "--plugin[-_][^ ]+ha_tokudb.so");
      if (util::contains(cfg::MYEXTRA, "--tokudb-check-jemalloc") ||
          util::contains(cfg::MYEXTRA, "--tokudb_check_jemalloc")) {
        std::string j = extract_option(cfg::MYEXTRA, "--tokudb[-_]check[-_]jemalloc[^ ]*");
        cfg::TOKUDB = cfg::TOKUDB + " " + j;
      }
      if (util::contains(cfg::MYEXTRA, "ha_tokudb.so") ||
          util::contains(cfg::TOKUDB, "ha_rocksdb.so")) {
        std::cerr << "Error: The MYEXTRA string is formulated in a seemingly complex manner (ha_tokudb.so).\n";
        std::exit(1);
      }
    }
    if (util::contains(cfg::MYEXTRA, "--tokudb-check-jemalloc") ||
        util::contains(cfg::MYEXTRA, "--tokudb_check_jemalloc")) {
      std::cerr << "Error: MYEXTRA contains --tokudb-check-jemalloc, yet ha_tokudb.so is not present in the MYEXTRA string.\n";
      std::exit(1);
    }
  }
  // BL_ENCRYPTION extraction (lines 491..513)
  if (util::contains(cfg::MYEXTRA, "encrypt-binlog") || util::contains(cfg::MYEXTRA, "encrypt_binlog")) {
    if (!util::contains(cfg::MYEXTRA, "master-verify-checksum") &&
        !util::contains(cfg::MYEXTRA, "master_verify_checksum") &&
        !util::contains(cfg::MYEXTRA, "binlog-checksum") &&
        !util::contains(cfg::MYEXTRA, "binlog_checksum")) {
      std::cerr << "Error: --encrypt-binlog is present in MYEXTRA whereas --binlog-checksum is not (as required by binary log encryption). Please fix this.\n";
      std::exit(1);
    }
    cfg::BL_ENCRYPTION = extract_option(cfg::MYEXTRA, "--encrypt[-_]binlog[^ ]*");
    std::string mvc = extract_option(cfg::MYEXTRA, "--master[-_]verify[-_]checksum[^ ]*");
    std::string bc  = extract_option(cfg::MYEXTRA, "--binlog[-_]checksum[^ ]*");
    cfg::BL_ENCRYPTION = util::trim(util::squeeze_spaces(cfg::BL_ENCRYPTION + " " + mvc + " " + bc));
  }
  // KF_ENCRYPTION extraction (lines 515..535)
  if (util::contains(cfg::MYEXTRA, "plugin-load=keyring_file.so") ||
      util::contains(cfg::MYEXTRA, "plugin_load=keyring_file.so")) {
    if (!util::contains(cfg::MYEXTRA, "keyring-file-data") &&
        !util::contains(cfg::MYEXTRA, "keyring_file_data")) {
      std::cerr << "Error: --[early-]plugin-load=keyring_file.so is present in MYEXTRA whereas --keyring_file_data is not. Please fix this.\n";
      std::exit(1);
    }
    cfg::KF_ENCRYPTION = extract_option(cfg::MYEXTRA, "--[^ ]+keyring_file.so");
    if (util::contains(cfg::MYEXTRA, "--keyring-file-data") ||
        util::contains(cfg::MYEXTRA, "--keyring_file_data")) {
      std::string fd = extract_option(cfg::MYEXTRA, "--keyring[-_]file[-_]data[^ ]*");
      cfg::KF_ENCRYPTION = util::trim(util::squeeze_spaces(cfg::KF_ENCRYPTION + " " + fd));
    }
  } else if (util::contains(cfg::MYEXTRA, "keyring-file-data") ||
             util::contains(cfg::MYEXTRA, "keyring_file_data")) {
    std::cerr << "Error: --keyring_file_data is present in MYEXTRA whereas --[early-]plugin-load=keyring_file.so is not. Please fix this.\n";
    std::exit(1);
  }
  // BINLOG extraction (lines 537..584). The bash version has additional
  // server-id / version-aware logic. Replicate the essential behavior: extract
  // --log_bin (+ --server_id where present) into cfg::BINLOG. NEW_BUGS_SAVE_DIR
  // containing 'fuzzing' bypasses this whole block.
  if (cfg::MDG != 1 && !util::contains(cfg::NEW_BUGS_SAVE_DIR, "fuzzing")) {
    if ((util::contains(cfg::MYEXTRA, "log-bin") || util::contains(cfg::MYEXTRA, "log_bin"))) {
      cfg::BINLOG = extract_option(cfg::MYEXTRA, "--log[-_]bin[^ ]*");
      if (util::contains(cfg::MYEXTRA, "--server-id") || util::contains(cfg::MYEXTRA, "--server_id")) {
        std::string si = extract_option(cfg::MYEXTRA, "--server[-_]id[^ ]*");
        cfg::BINLOG = util::trim(util::squeeze_spaces(cfg::BINLOG + " " + si));
      }
    }
  }
  // ONLY_FULL_GROUP_BY extraction (lines 587..594)
  if (!util::contains(cfg::MYEXTRA, "--sql_mode=ONLY_FULL_GROUP_BY,") &&
       util::contains(cfg::MYEXTRA, "--sql_mode=ONLY_FULL_GROUP_BY")) {
    cfg::ONLYFULLGROUPBY = "--sql_mode=ONLY_FULL_GROUP_BY";
    cfg::MYEXTRA = util::replace_all(cfg::MYEXTRA, cfg::ONLYFULLGROUPBY, "");
  }
  // Aggregate
  cfg::SPECIAL_MYEXTRA_OPTIONS = util::trim(util::squeeze_spaces(
    cfg::TOKUDB + " " + cfg::ROCKSDB + " " + cfg::BL_ENCRYPTION + " " +
    cfg::KF_ENCRYPTION + " " + cfg::BINLOG + " " + cfg::ONLYFULLGROUPBY));
}

// ============================================================================
// _init_empty_port_cleanup + init_empty_port — mirror reducer.sh:1755..1805
// ============================================================================
static void _init_empty_port_cleanup() {
  std::istringstream is(state::INIT_EMPTY_PORT_CLAIMED);
  std::string p;
  while (is >> p) {
    fs::remove(state::INIT_EMPTY_PORT_CLAIM_DIR + "/" + p);
  }
}

static int init_empty_port() {
  util::mkdir_p(state::INIT_EMPTY_PORT_CLAIM_DIR);
  // Stale-claim reaper: scoped to 13001..47001 port range.
  {
    std::error_code ec;
    for (const auto& entry : fs::directory_iterator(state::INIT_EMPTY_PORT_CLAIM_DIR, ec)) {
      if (!entry.is_regular_file()) continue;
      const std::string name = entry.path().filename().string();
      if (name.empty() || !std::all_of(name.begin(), name.end(), [](char c){ return std::isdigit(static_cast<unsigned char>(c)); })) continue;
      int port = 0;
      try { port = std::stoi(name); } catch (...) { continue; }
      if (port < 13001 || port > 47001) continue;
      std::string owner = util::sh_capture_trimmed("{ read -r line < \"" + entry.path().string() + "\"; echo \"$line\"; } 2>/dev/null");
      if (owner.empty()) continue;
      if (util::sh("kill -0 " + owner + " 2>/dev/null") == 0) continue;
      std::string verify = util::sh_capture_trimmed("{ read -r line < \"" + entry.path().string() + "\"; echo \"$line\"; } 2>/dev/null");
      if (owner == verify) {
        fs::remove(entry.path(), ec);
      }
    }
  }
  while (true) {
    int new_port;
    {
      std::lock_guard<std::mutex> g(state::rng_mutex);
      std::uniform_int_distribution<int> d(13001, 47001);
      new_port = d(state::rng);
    }
    // Atomic O_CREAT|O_EXCL claim.
    std::string claim = state::INIT_EMPTY_PORT_CLAIM_DIR + "/" + std::to_string(new_port);
    int fd = open(claim.c_str(), O_WRONLY | O_CREAT | O_EXCL, 0644);
    if (fd < 0) continue;  // Someone else holds it; retry.
    std::string pid = std::to_string(getpid()) + "\n";
    ssize_t wr = write(fd, pid.data(), pid.size()); (void)wr;
    close(fd);
    // Verify port is free at the OS level.
    std::string p = std::to_string(new_port);
    int npc1 = 0;
    try { npc1 = std::stoi(util::sh_capture_trimmed(
      "netstat -an | tr '\\t' ' ' | grep -E --binary-files=text \"[ :]" + p + " \" | wc -l")); } catch (...) {}
    std::string npc2 = util::sh_capture_trimmed(
      "ps -ef | grep --binary-files=text \"port=" + p + "\" | grep --binary-files=text -v 'grep'");
    int npc3 = 0;
    try { npc3 = std::stoi(util::sh_capture_trimmed(
      "grep --binary-files=text -o \"port=" + p + "\" /test/*/start 2>/dev/null | wc -l")); } catch (...) {}
    std::string npc4 = util::sh_capture_trimmed("netstat -tuln | grep :" + p);
    std::string npc5 = util::sh_capture_trimmed("lsof -i :" + p);
    if (npc1 == 0 && npc3 == 0 && npc2.empty() && npc4.empty() && npc5.empty()) {
      state::INIT_EMPTY_PORT_CLAIMED += " " + p;
      if (state::INIT_EMPTY_PORT_TRAP_SET == 0) {
        std::atexit(_init_empty_port_cleanup);
        state::INIT_EMPTY_PORT_TRAP_SET = 1;
      }
      // Auto-release ~600s later via a detached background sleeper.
      util::sh("( ( sleep 600; rm -f \"" + claim + "\" ) & ) </dev/null >/dev/null 2>&1");
      state::NEWPORT = new_port;
      return new_port;
    }
    fs::remove(claim);
  }
}

// ============================================================================
// remove_dropc — mirror reducer.sh:1224..1261
// Removes leading DROPC lines (DROP/CREATE DATABASE transforms/test, USE test)
// from the head of the given file (in-place).
// ============================================================================
static void remove_dropc(const std::string& path) {
  if (path.empty()) {
    echoit("Assert: no parameter was passed to the remove_dropc() function. This should not happen.");
    std::exit(1);
  }
  while (true) {
    bool removed = false;
    std::string head = util::sh_capture_trimmed("head -n1 \"" + path + "\"");
    static const std::array<const char*, 5> patterns = {
      "DROP DATABASE transforms;",
      "CREATE DATABASE transforms;",
      "DROP DATABASE test;",
      "CREATE DATABASE test;",
      "USE test;"
    };
    for (const char* pat : patterns) {
      if (util::contains(head, pat)) {
        util::sh("sed -i '1d' \"" + path + "\"");
        removed = true;
        // Re-read head — we removed one line, so next pattern check uses new head.
        head = util::sh_capture_trimmed("head -n1 \"" + path + "\"");
      }
    }
    if (!removed) break;
  }
}

// ============================================================================
// set_internal_options — mirror reducer.sh:1262..1319
// Initializes runtime state vars after options_check.
// ============================================================================
static void set_internal_options() {
  // Core file generation policy (mirror lines 1264..1277)
  if (cfg::PAUSE_AFTER_EACH_OCCURRENCE == 1) {
    cfg::MYEXTRA = cfg::MYEXTRA + " --core-file";
  } else if (cfg::USE_NEW_TEXT_STRING != 1) {
    // Uppercase compare to check if user already passed --core or core-file
    std::string upper = cfg::MYEXTRA;
    std::transform(upper.begin(), upper.end(), upper.begin(),
                   [](unsigned char c){ return std::toupper(c); });
    if (!util::contains(upper, "CORE")) {
      // ulimit -c 0 via subshell is a no-op for this process and its children;
      // setrlimit on the C++ process itself propagates to every forked mariadbd.
      struct rlimit rl{0, 0};
      (void)setrlimit(RLIMIT_CORE, &rl);
    }
  }
  state::RUNMODE = "MULTI";
  if (cfg::FIREWORKS == 1) state::RUNMODE = "FIREWORKS";

  // Subreducer OS slicing: sleep 0.1..0.10000s — random.
  {
    std::lock_guard<std::mutex> g(state::rng_mutex);
    std::uniform_int_distribution<int> d(0, 32767);
    int slack = d(state::rng);
    std::this_thread::sleep_for(std::chrono::milliseconds(100 + (slack % 100)));
  }
  state::WHOAMI = util::sh_capture_trimmed("whoami");
  if (state::MULTI_REDUCER != 1) {
    state::EPOCH = util::nsec_epoch();
    state::SKIPV = 0;
    state::SPORADIC = 0;
    if (cfg::MODE == 11) state::SKIPV = 1;
    state::MYUSER = state::WHOAMI;
  } else {
    // Subreducer: EPOCH, SKIPV, SPORADIC, MYUSER must already be set by #VARMOD#.
    if (state::EPOCH.empty()) {
      std::cerr << "Assert: $EPOCH is empty inside a subreducer!\n"; std::exit(1);
    }
    // SKIPV/SPORADIC are ints; nothing to assert past compile-time init.
    if (state::MYUSER.empty()) {
      std::cerr << "Assert: $MYUSER is empty inside a subreducer!\n"; std::exit(1);
    }
  }
  // SIGINT handler was installed in main() already (depends on EPOCH; reinstall now safe).
  install_signal_handlers();
  state::DROPC = "DROP DATABASE transforms;CREATE DATABASE transforms;DROP DATABASE test;CREATE DATABASE test;USE test;";
  state::STARTUPCOUNT = 0;
  state::ATLEASTONCE = "[]";
  state::TRIAL       = 1;
  state::STAGE       = "0";
  state::STUCKTRIAL  = 0;
  state::NOISSUEFLOW = 0;
  state::CHUNK_LOOPS_DONE = 99999999999LL;
  state::C_COL_COUNTER = 1;
  state::TS_ELIMINATED_THREAD_COUNT = 0;
  state::TS_ORIG_VARS_FLAG = 0;
  state::TS_DEBUG_SYNC_REQUIRED_FLAG = 0;
  state::TS_TE_DIR_SWAP_DONE = 0;
  state::NR_OF_NEWBUGS = 0;
}

// ============================================================================
// kill_multi_reducer — mirror reducer.sh:1320..1342
// ============================================================================
static void kill_multi_reducer() {
  const std::string ps_cmd =
    "ps -ef | grep --binary-files=text 'subreducer' | grep --binary-files=text " + state::WHOAMI +
    " | grep --binary-files=text " + state::EPOCH +
    " | grep -v --binary-files=text 'grep' | awk '{print $2}'";
  auto count = [&]() -> int {
    std::string s = util::sh_capture_trimmed(ps_cmd + " | wc -l");
    try { return std::stoi(s); } catch (...) { return 0; }
  };
  if (count() < 1) return;
  std::string pids = util::sh_capture_trimmed(ps_cmd + " | sort -u | tr '\\n' ' '");
  echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [" + state::RUNMODE +
         "] Terminating these PID's: " + pids);
  while (count() >= 1) {
    auto each_pid = util::split(util::sh_capture_trimmed(ps_cmd + " | sort -u"), '\n');
    for (const auto& pid : each_pid) {
      if (pid.empty()) continue;
      util::sh("kill -9 " + pid + " >/dev/null 2>&1");
      auto wait_end = std::chrono::steady_clock::now() + std::chrono::seconds(5);
      while (true) {
        if (util::sh("kill -0 " + pid + " 2>/dev/null") != 0) break;
        if (std::chrono::steady_clock::now() >= wait_end) break;
        std::this_thread::sleep_for(std::chrono::milliseconds(100));
      }
    }
    util::sh("sync");
    std::this_thread::sleep_for(std::chrono::seconds(3));
    if (count() >= 1) {
      util::sh("sync");
      std::this_thread::sleep_for(std::chrono::seconds(20));
      if (count() >= 1) {
        echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [" + state::RUNMODE +
               "] WARNING: " + std::to_string(count()) + " subreducer processes still exists after they were killed, re-attempting kill");
      }
    }
  }
}

// ============================================================================
// options_check — mirror reducer.sh:728..1223
// ~500 lines of input validation; mirrors every check including TokuDB autoload,
// AIO, O_DIRECT, NR_OF_TRIAL_REPEATS numeric check, MODE compatibility matrix,
// PQUERY_MULTI side effects, FORCE_SKIPV/SPORADIC cascade.
// ============================================================================
static void options_check(const std::string& cli_arg) {
  // 1) Input file given via CLI or via $INPUTFILE? (lines 730..733)
  if (cli_arg.empty() && cfg::INPUTFILE.empty()) {
    std::cerr << "Error: no input file given. Please give an SQL file to reduce as the first option to this script, or set inside the script as INPUTFILE=file_to_reduce.sql\n";
    std::cerr << "Terminating now.\n";
    std::exit(1);
  }
  // 2) Sudo check (lines 756..762)
  if (util::sh_capture_trimmed("sudo -A echo 'test' 2>/dev/null") != "test") {
    std::cerr << "Error: sudo is not available or requires a password. This script needs to be able to use sudo, without password, from the userID that invokes it ("
              << state::WHOAMI << ")\n";
    std::cerr << "To get your setup correct, you may like to use a tool like visudo (use 'sudo visudo' or 'su' and then 'visudo') and consider adding the following line to the file:\n";
    std::cerr << state::WHOAMI << "   ALL=(ALL)      NOPASSWD:ALL\n";
    std::cerr << "If you do not have sudo installed yet, try 'su' and then 'yum install sudo' or the apt-get equivalent\n";
    std::cerr << "Terminating now.\n";
    std::exit(1);
  }
  // 3) AIO check (lines 765..776)
  {
    long long aio = 0;
    try { aio = std::stoll(util::sh_capture_trimmed("sysctl -n fs.aio-max-nr")); } catch (...) {}
    if (aio < 300000) {
      std::cerr << "As fs.aio-max-nr on this system is lower than 300000, so you will likely run into BUG#12677594: INNODB: WARNING: IO_SETUP() FAILED WITH EAGAIN\n";
      std::cerr << "To prevent this from happening, please use the following command at your shell prompt (you will need to have sudo privileges):\n";
      std::cerr << "sudo sysctl -w fs.aio-max-nr=300000\n";
      std::cerr << "The setting can be verified by executing: sysctl fs.aio-max-nr\n";
      std::cerr << "Alternatively, you can add make the following settings to be system wide:\n";
      std::cerr << "sudo vi /etc/sysctl.conf           # Then, add the following two lines to the bottom of the file\n";
      std::cerr << "fs.aio-max-nr = 1048576\n";
      std::cerr << "fs.file-max = 6815744\n";
      std::cerr << "Terminating now.\n";
      std::exit(1);
    }
  }
  // 4) O_DIRECT + tmpfs/ramfs incompatibility (lines 779..793)
  {
    std::string lc = cfg::MYEXTRA;
    std::transform(lc.begin(), lc.end(), lc.begin(),
                   [](unsigned char c){ return std::tolower(c); });
    if (util::contains(lc, "o_direct") && (cfg::WORKDIR_LOCATION == 1 || cfg::WORKDIR_LOCATION == 2)) {
      std::cerr << "Error: O_DIRECT is being used in the MYEXTRA option string, and tmpfs (or ramfs) storage was specified, but because\n";
      std::cerr << "of bug http://bugs.mysql.com/bug.php?id=26662 one would see a WARNING for this in the error log along the lines of;\n";
      std::cerr << "[Warning] InnoDB: Failed to set O_DIRECT on file ./ibdata1: OPEN: Invalid argument, continuing anyway.\n";
      std::cerr << "          O_DIRECT is known to result in 'Invalid argument' on Linux on tmpfs, see MySQL Bug#26662.\n";
      std::cerr << "So, reducer is exiting to allow you to change WORKDIR_LOCATION in the script to a non-tmpfs setting.\n";
      std::cerr << "Note: this assertion currently shows for ramfs as well, yet it has not been established if ramfs also\n";
      std::cerr << "      shows the same problem. If it does not (modify the script in this section to get it to run with ramfs\n";
      std::cerr << "      as a trial/test), then please remove ramfs, or, if it does, then please remove these 3 last lines.\n";
      std::cerr << "Terminating now.\n";
      std::exit(1);
    }
  }
  // 5) innodb_log_group_home_dir / innodb_log_arch_dir hardcoded path checks (lines 796..810)
  {
    std::string lc = cfg::MYEXTRA;
    std::transform(lc.begin(), lc.end(), lc.begin(),
                   [](unsigned char c){ return std::tolower(c); });
    std::string dir_issue;
    if (util::contains(lc, "innodb_log_group_home_dir")) dir_issue = "innodb_log_group_home_dir";
    if (util::contains(lc, "innodb_log_arch_dir"))       dir_issue = "innodb_log_arch_dir";
    if (!dir_issue.empty()) {
      std::cerr << "Error: the " << dir_issue << " option is being used in the MYEXTRA option string. This can lead to all sorts of problems;\n";
      std::cerr << "Terminating reducer to allow this change to be made.\n";
      std::exit(1);
    }
  }
  // 6) NR_OF_TRIAL_REPEATS numeric (lines 812..818)
  if (cfg::NR_OF_TRIAL_REPEATS < 1) {
    std::cerr << "Error: NR_OF_TRIAL_REPEATS (" << cfg::NR_OF_TRIAL_REPEATS << ") is less than 1 which is an impossible setting.\n";
    std::exit(1);
  }
  // 7) PQUERY_CONS_Q_FAIL implies USE_PQUERY=1, MODE=3, TEXT, USE_NEW_TEXT_STRING=0 (lines 820..834)
  if (cfg::PQUERY_CONS_Q_FAIL == 1) {
    if (cfg::REDUCE_GLIBC_OR_SS_CRASHES == 1) {
      std::cerr << "Error: PQUERY_CONS_Q_FAIL=1 and REDUCE_GLIBC_OR_SS_CRASHES=1: these modes are incompatible, please turn off at least one\n";
      std::exit(1);
    }
    echoit("[Setup] PQUERY_CONS_Q_FAIL is enabled, setting USE_PQUERY=1, TEXT='Last [0-9]+ consecutive queries all failed', MODE=3, USE_NEW_TEXT_STRING=0");
    cfg::USE_PQUERY = 1;
    cfg::TEXT = "Last [0-9]+ consecutive queries all failed";
    cfg::MODE = 3;
    cfg::USE_NEW_TEXT_STRING = 0;
  }
  // 8) MODE 6..9 expects a directory with /log subdir + ThreadSync files (lines 835..908)
  if (cfg::MODE >= 6 && cfg::MODE <= 9) {
    if (!util::dir_exists(cli_arg)) {
      std::cerr << "Error: A file name was given as input, but a directory name was expected.\n";
      std::cerr << "(MODE " << cfg::MODE << " is set. Where you trying to use MODE 4 or lower?)\n";
      std::cerr << "Terminating now.\n";
      std::exit(1);
    }
    std::string log_dir = cli_arg + "/log/";
    if (!util::dir_exists(log_dir) || access(log_dir.c_str(), X_OK) != 0) {
      std::cerr << "Error: No input directory containing a \"/log\" subdirectory was given, or the input directory could not be read.\n";
      std::cerr << "Please specify a correct RQG vardir to reduce a multi-threaded testcase.\n";
      std::cerr << "Terminating now.\n";
      std::exit(1);
    }
    int ts_count = 0;
    try { ts_count = std::stoi(util::sh_capture_trimmed(
      "ls --color=never -l " + cli_arg + "/log/C[0-9]*T[0-9]*.sql 2>/dev/null | wc -l | tr -d '[\\t\\n ]*'")); } catch (...) {}
    state::TS_THREADS = ts_count;
    state::TS_ELIMINATION_THREAD_ID = ts_count + 1;
    if (ts_count < 1) {
      std::cerr << "Error: though input directory was found, no ThreadSync SQL trace files are present, or they could not be read.\n";
      std::cerr << "Please check the directory at " << cli_arg << "\n";
      std::cerr << "Terminating now.\n";
      std::exit(1);
    }
    state::TS_INPUTDIR = cli_arg + "/log";
  } else {
    if (util::dir_exists(cli_arg)) {
      std::cerr << "Error: A directory was given as input, but a filename was expected.\n";
      std::cerr << "(MODE " << cfg::MODE << " is set. Where you trying to use MODE 6 or higher?)\n";
      std::cerr << "Terminating now.\n";
      std::exit(1);
    }
    if (!util::file_readable(cli_arg)) {
      if (!util::file_readable(cfg::INPUTFILE)) {
        if (cfg::INPUTFILE.empty() && cli_arg.empty()) {
          std::cerr << "Error: No input file was given.\n";
        } else {
          std::cerr << "Error: The specified input file (" << cfg::INPUTFILE << ") did not exist or could not be read.\n";
        }
        std::cerr << "Please specify a single SQL file to reduce.\n";
        std::cerr << "Example: ./reducer ~/1.sql     --> to process ~/1.sql\n";
        std::cerr << "Terminating now.\n";
        std::exit(1);
      }
    } else {
      cfg::INPUTFILE = cli_arg;
    }
    // base_reducer auto-backup of existing _out (lines 906..924)
    // Use argv[0] not /proc/self/exe: bash $0 reflects invocation name. We
    // stash argv[0] in state at startup. Falls back to /proc/self/exe.
    std::string self = state::THIS_REDUCER;
    if (self.empty()) {
      char buf[PATH_MAX];
      ssize_t n = readlink("/proc/self/exe", buf, sizeof(buf) - 1);
      if (n > 0) { buf[n] = '\0'; self = buf; }
    }
    if (util::contains(self, "base_reducer")) {
      std::string out = cfg::INPUTFILE + "_out";
      if (util::file_readable(out)) {
        std::string copy_target = out + "_copy";
        if (util::file_readable(copy_target)) {
          int n = 2;
          while (util::file_readable(out + "_copy" + std::to_string(n))) {
            ++n;
            if (n > 999) {
              std::cerr << "Error: " << out << "_copy and _copy2.._copy999 all present. Cleanup manually.\n";
              std::exit(1);
            }
          }
          copy_target = out + "_copy" + std::to_string(n);
        }
        std::cerr << "Warning: a reduced testcase (" << out << ") already exists and will be overwritten, thus backing it up as " << copy_target << " now\n";
        util::sh("cp \"" + out + "\" \"" + copy_target + "\"");
      }
    }
  }
  // 9) MODE3_ANY_SIG requires USE_NEW_TEXT_STRING=1 (lines 953..958)
  if (cfg::MODE3_ANY_SIG == 1) {
    if (cfg::USE_NEW_TEXT_STRING != 1) {
      std::cerr << "Error: MODE3_ANY_SIG is set to 1, yet USE_NEW_TEXT_STRING, which is required for MODE3_ANY_SIG=1, is set to " << cfg::USE_NEW_TEXT_STRING << "\n";
      std::cerr << "Terminating now.\n";
      std::exit(1);
    }
    cfg::TEXT = "";
  }
  // 10) Sanitize bare INPUTFILE without path (lines 961..963)
  if (!cfg::INPUTFILE.empty() && cfg::INPUTFILE.find('/') == std::string::npos) {
    cfg::INPUTFILE = fs::current_path().string() + "/" + cfg::INPUTFILE;
  }
  if (!util::file_readable(cfg::INPUTFILE) && !util::dir_exists(cfg::INPUTFILE)) {
    std::cerr << "Assert: INPUTFILE is not a readable file, nor a directory\n";
    std::exit(1);
  }
  // 11) MODE=0 setup (lines 969..994)
  if (cfg::MODE == 0) {
    if (!cfg::TIMEOUT_COMMAND.empty()) {
      std::cerr << "Error: MODE is set to 0, and TIMEOUT_COMMAND is set. Both functions should not be used at the same time\n";
      std::exit(1);
    }
    if (cfg::TIMEOUT_CHECK <= 30) {
      std::cerr << "Error: MODE=0 and TIMEOUT_CHECK<=30. When using MODE=0, set TIMEOUT_CHECK at least to: (2x the expected testcase duration lenght in seconds)+30 seconds extra!\n";
      std::exit(1);
    }
    state::TIMEOUT_CHECK_REAL = cfg::TIMEOUT_CHECK - 30;
    if (state::TIMEOUT_CHECK_REAL <= 0) {
      std::cerr << "Assert: TIMEOUT_CHECK_REAL<=0\n";
      std::exit(1);
    }
    cfg::TIMEOUT_COMMAND = "timeout --signal=SIGKILL " + std::to_string(cfg::TIMEOUT_CHECK) + "s";
    // Sanitizer-build warning
    {
      std::string lc = cfg::BASEDIR;
      std::transform(lc.begin(), lc.end(), lc.begin(),
                     [](unsigned char c){ return std::tolower(c); });
      static const std::regex san_pat(R"((ubasan|ubsan|asan|msan|tsan|hwasan|-san-|_san_|-asan-|-ubsan-|-msan-|-tsan-))");
      if (std::regex_search(lc, san_pat) && cfg::TIMEOUT_CHECK < 240) {
        echoit("[Init] [Warning] BASEDIR appears to be a sanitizer build (" + cfg::BASEDIR +
               ") and TIMEOUT_CHECK=" + std::to_string(cfg::TIMEOUT_CHECK) +
               " is below the recommended sanitizer floor (240). MODE=0's runtime-only trigger may misfire from shutdown / sanitizer-flush latency. Recommended: raise TIMEOUT_CHECK to >=240 (the inline default-comment recommends 350) or reduce on a non-sanitizer build.");
      }
    }
  }
  // 12) TIMEOUT_COMMAND availability (lines 996..1000)
  if (!cfg::TIMEOUT_COMMAND.empty()) {
    if (util::sh_capture("timeout 2>&1 | grep -E --binary-files=text -o 'information'").find("information") == std::string::npos) {
      std::cerr << "Error: TIMEOUT_COMMAND is set, yet the timeout command does not seem to be available\n";
      std::exit(1);
    }
  }
  // 13) MODE=3 + USE_NEW_TEXT_STRING: check '|' count + TEXT_STRING_LOC presence (lines 1002..1029)
  if (cfg::MODE == 3 && cfg::USE_NEW_TEXT_STRING == 1) {
    int pipes = static_cast<int>(std::count(cfg::TEXT.begin(), cfg::TEXT.end(), '|'));
    if (pipes < 3 && cfg::FIREWORKS != 1) {
      static const std::array<const char*, 11> prefixes = {
        "MUTEX","MEMORY_NOT_FREED","GOT_FATAL_ERROR","GOT_ERROR","MARKED_AS_CRASHED",
        "MARIADB_ERROR","SERVER_ERRNO","SLAVE_ERROR","FALLBACK","INNODB_ERROR","GENERIC_ISSUE"
      };
      bool match = false;
      for (const char* p : prefixes) if (util::starts_with(cfg::TEXT, p)) { match = true; break; }
      if (!match && cfg::MODE3_ANY_SIG != 1) {
        std::cerr << "Likely misconfiguration: MODE=3 and USE_NEW_TEXT_STRING=1, yet the TEXT string ('" << cfg::TEXT
                  << "') does not contain at least 3 '|' symbols... Pausing 13 seconds for consideration. Press CTRL+c if you want to stop at this point.\n";
        std::this_thread::sleep_for(std::chrono::seconds(13));
      }
    }
    if (!util::file_readable(cfg::TEXT_STRING_LOC)) {
      std::cerr << "Assert: MODE=3 and USE_NEW_TEXT_STRING=1, so reducer.sh looked for " << cfg::TEXT_STRING_LOC
                << " (as set in $TEXT_STRING_LOC), but this program was either not found (most likely), or it is not readable (check file privileges)\n";
      std::exit(1);
    }
    if (util::sh("egrep -qi 'set logging' \"" + cfg::TEXT_STRING_LOC + "\"") != 0) {
      std::cerr << "Assert: MODE=3 and USE_NEW_TEXT_STRING=1, so reducer.sh looked for " << cfg::TEXT_STRING_LOC
                << " (as set in $TEXT_STRING_LOC), and found a readable file at this location, however it did not contain the text 'set logging' so it is likely not the right script!\n";
      std::exit(1);
    }
  }
  // 14) USE_NEW_TEXT_STRING=1 but MODE!=3 (lines 1031..1034)
  if (cfg::USE_NEW_TEXT_STRING == 1 && cfg::MODE != 3) {
    std::cerr << "Assert: USE_NEW_TEXT_STRING=1 and MODE!=3 (MODE=" << cfg::MODE << "). This scenario is not covered by reducer yet.\n";
    std::exit(1);
  }
  // 15) MODE=2 + USE_PQUERY=1 + missing log-client-output (lines 1036..1043)
  if (cfg::MODE == 2 && cfg::USE_PQUERY == 1) {
    if (cfg::PQUERY_EXTRA_OPTIONS.find("log-client-output") == std::string::npos) {
      std::cerr << "Assert: USE_PQUERY=1 && PQUERY_EXTRA_OPTIONS does not contain log-client-output\n";
      std::exit(1);
    }
  }
  // 16) BIN discovery (lines 1044..1057)
  state::BIN = cfg::BASEDIR + "/bin/mariadbd";
  if (!util::file_readable(state::BIN)) {
    state::BIN = cfg::BASEDIR + "/bin/mysqld";
    if (!util::file_readable(state::BIN)) {
      state::BIN = cfg::BASEDIR + "/bin/mysqld-debug";
      if (!util::file_readable(state::BIN)) {
        std::cerr << "Assert: No mariadbd, mysqld or mysqld-debug binary was found in " << cfg::BASEDIR << "/bin\n";
        std::cerr << "Please check script options and please set the $BASEDIR variable correctly\n";
        std::cerr << "The BASEDIR variable is currently set to " << cfg::BASEDIR << "\n";
        std::cerr << "Terminating now.\n";
        std::exit(1);
      }
    }
  }
  // 17) MODE range check (lines 1058..1062)
  {
    static const std::set<int> valid_modes = {0,1,2,3,4,5,6,7,8,9,11};
    if (!valid_modes.contains(cfg::MODE)) {
      std::cerr << "Error: Invalid MODE set: " << cfg::MODE << " (valid range: 0-9, 11)\n";
      std::exit(1);
    }
  }
  // 18) MODE=11 dump/binlog config (lines 1063..1089)
  if (cfg::MODE == 11) {
    if (cfg::MODE11_TYPE != "dump" && cfg::MODE11_TYPE != "binlog") {
      std::cerr << "Error: MODE=11 but MODE11_TYPE is not 'dump' or 'binlog' (got: '" << cfg::MODE11_TYPE << "')\n";
      std::exit(1);
    }
    if (cfg::MODE11_BINLOG_FORMAT != "MIXED" && cfg::MODE11_BINLOG_FORMAT != "ROW" && cfg::MODE11_BINLOG_FORMAT != "STATEMENT") {
      std::cerr << "Error: MODE=11 but MODE11_BINLOG_FORMAT is not MIXED|ROW|STATEMENT (got: '" << cfg::MODE11_BINLOG_FORMAT << "')\n";
      std::exit(1);
    }
    if (cfg::USE_PQUERY == 1) {
      std::cerr << "[Warning] MODE=11 with USE_PQUERY=1: pquery's randomized shuffle will produce non-deterministic runs... Setting USE_PQUERY=0 (mysql CLI replay).\n";
      cfg::USE_PQUERY = 0;
    }
    if (cfg::MODE11_TYPE == "binlog") {
      if (!util::contains(cfg::MYEXTRA, "--log_bin") && !util::contains(cfg::MYEXTRA, "--log-bin")) {
        cfg::MYEXTRA = cfg::MYEXTRA + " --log_bin --binlog_format=" + cfg::MODE11_BINLOG_FORMAT;
      }
    }
  }
  // 19) Modes requiring TEXT (lines 1091..1097)
  if (cfg::MODE == 1 || cfg::MODE == 2 || cfg::MODE == 3 || cfg::MODE == 5 ||
      cfg::MODE == 6 || cfg::MODE == 7 || cfg::MODE == 8) {
    if (cfg::TEXT.empty() && cfg::MODE3_ANY_SIG != 1) {
      std::cerr << "Error: MODE set to " << cfg::MODE << ", but no $TEXT variable was defined, or $TEXT is blank\n";
      std::exit(1);
    }
  }
  // 20) MDG / GRP_RPL constraints (lines 1099..1125)
  if (cfg::MDG == 1 || cfg::GRP_RPL == 1) {
    cfg::USE_PQUERY = 1;
    if (cfg::MODE == 0) {
      std::cerr << "Error: MDG/Group Replication mode is set to 1, and MODE=0 set to 0, but this option combination has not been tested.\n";
      std::exit(1);
    }
    if (!cfg::TIMEOUT_COMMAND.empty()) {
      std::cerr << "Error: MDG/Group Replication mode + TIMEOUT_COMMAND combination not tested.\n";
      std::exit(1);
    }
    if (cfg::MODE == 1 || cfg::MODE == 6) {
      std::cerr << "Error: Valgrind for " << cfg::NR_OF_NODES << " node MDG/Group Replication replay has not been implemented yet.\n";
      std::exit(1);
    }
    if (cfg::MODE >= 6 && cfg::MODE <= 9) {
      std::cerr << "Error: wrong option combination: MODE is set to " << cfg::MODE << " (ThreadSync) and MDG/Group Replication mode is active\n";
      std::exit(1);
    }
  }
  // 21) PQUERY_MULTI implies USE_PQUERY (lines 1127..1129)
  if (cfg::PQUERY_MULTI == 1) cfg::USE_PQUERY = 1;
  // 22) USE_PQUERY -> verify PQUERY_LOC exists (lines 1130..1136)
  if (cfg::USE_PQUERY == 1 && !util::file_readable(cfg::PQUERY_LOC)) {
    std::cerr << "Error: USE_PQUERY is set to 1, but the pquery binary (as defined by PQUERY_LOC; currently set to '"
              << cfg::PQUERY_LOC << "') is not available.\n";
    std::exit(1);
  }
  // 23) PQUERY_MULTI sets FORCE_SKIPV, MULTI_THREADS adjustments (lines 1137..1153)
  if (cfg::PQUERY_MULTI > 0) {
    cfg::FORCE_SKIPV = 1;
    cfg::MULTI_THREADS = cfg::PQUERY_MULTI_THREADS;
    if (cfg::PQUERY_MULTI_CLIENT_THREADS < 1) {
      echoit("Error: PQUERY_MULTI_CLIENT_THREADS is set to less then 1 (" + std::to_string(cfg::PQUERY_MULTI_CLIENT_THREADS) +
             "), while PQUERY_MULTI active, this does not work");
      std::exit(1);
    }
    if (cfg::PQUERY_MULTI_CLIENT_THREADS == 1) {
      echoit("Warning: PQUERY_MULTI active, and PQUERY_MULTI_CLIENT_THREADS is set to 1; 1 thread for a multi-threaded issue does not seem logical.");
    } else if (cfg::PQUERY_MULTI_CLIENT_THREADS < 5) {
      echoit("Warning: PQUERY_MULTI active, and PQUERY_MULTI_CLIENT_THREADS is set to " + std::to_string(cfg::PQUERY_MULTI_CLIENT_THREADS) +
             ", which may be insufficient.");
    }
  }
  // 24) REDUCE_GLIBC_OR_SS_CRASHES: MULTI_THREADS=1, MULTI_THREADS_INCREASE=0, SLOW_DOWN_CHUNK_SCALING=1, SKIPV=1 (lines 1155..1186)
  if (cfg::REDUCE_GLIBC_OR_SS_CRASHES > 0) {
    cfg::MULTI_THREADS          = 1;
    cfg::MULTI_THREADS_INCREASE = 0;
    cfg::SLOW_DOWN_CHUNK_SCALING = 1;
    state::SKIPV                = 1;
    if (cfg::MODE != 3 && cfg::MODE != 4) {
      std::cerr << "REDUCE_GLIBC_OR_SS_CRASHES is active, and MODE is set to MODE=" << cfg::MODE << ", which is not supported.\n";
      std::exit(1);
    }
    if (cfg::MDG > 0 || cfg::GRP_RPL == 1) {
      std::cerr << "GLIBC testcase reduction is not yet supported for MDG=1 or GRP_RPL=1.\n";
      std::exit(1);
    }
    if (cfg::PQUERY_MULTI > 0) {
      std::cerr << "GLIBC testcase reduction is not yet supported for PQUERY_MULTI=1.\n";
      std::exit(1);
    }
  }
  // 25) FORCE_SKIPV cascade (lines 1188..1194)
  if (cfg::FORCE_SKIPV > 0) {
    cfg::FORCE_SPORADIC = 1;
    state::SKIPV       = 1;
  }
  // 26) FORCE_SPORADIC cascade (lines 1196..1204)
  if (cfg::FORCE_SPORADIC > 0) {
    if (cfg::STAGE1_LINES == 90) cfg::STAGE1_LINES = 3;
    state::SPORADIC = 1;
    cfg::SLOW_DOWN_CHUNK_SCALING = 1;
  }
  // 27) MODE=0 + FORCE_KILL=1 -> FORCE_KILL=0 (line 1206..1209)
  if (cfg::MODE == 0 && cfg::FORCE_KILL == 1) cfg::FORCE_KILL = 0;
  // 28) SCAN_FOR_NEW_BUGS sanity (lines 1211..1218)
  if (cfg::SCAN_FOR_NEW_BUGS == 1) {
    if (!util::file_readable(cfg::KNOWN_BUGS_LOC)) {
      std::cerr << "SCAN_FOR_NEW_BUGS was set to 1, yet the file specified in KNOWN_BUGS_LOC (" << cfg::KNOWN_BUGS_LOC << ") does not exist?\n";
      std::exit(1);
    }
    if (cfg::NEW_BUGS_SAVE_DIR.empty()) {
      std::cerr << "Assert: SCAN_FOR_NEW_BUGS was set to 1, yet NEW_BUGS_SAVE_DIR is empty.\n";
      std::exit(1);
    }
    if (!util::dir_exists(cfg::NEW_BUGS_SAVE_DIR)) {
      util::mkdir_p(cfg::NEW_BUGS_SAVE_DIR);
      if (!util::dir_exists(cfg::NEW_BUGS_SAVE_DIR)) {
        std::cerr << "Could not create NEW_BUGS_SAVE_DIR (" << cfg::NEW_BUGS_SAVE_DIR << ")\n";
        std::exit(1);
      }
    }
    if (cfg::USE_NEW_TEXT_STRING != 1) {
      echoit("[Setup] SCAN_FOR_NEW_BUGS was set to 1, yet USE_NEW_TEXT_STRING is not set to 1 (set to '" +
             std::to_string(cfg::USE_NEW_TEXT_STRING) + "'). This setup is not covered by this script yet. Ref inside reducer for more info. Automatically turning SCAN_FOR_NEW_BUGS off.");
      cfg::SCAN_FOR_NEW_BUGS = 0;
    }
  }
  // 29) Strip --no-defaults from MYEXTRA (line 1222)
  cfg::MYEXTRA = util::sh_capture_trimmed(
    "echo \"" + cfg::MYEXTRA + "\" | sed 's|[ \\t]*--no-defaults[ \\t]*||g'");
}
// multi_reducer — mirror reducer.sh:1343..1671
// Forks N subreducer instances (this same binary, invoked with env vars
// REDUCER_MULTI_REDUCER=1 + EPOCH/MODE/TEXT/...). Each subreducer reduces in
// parallel. Returns 0 if any subreducer reproduced (verify-success / chunk found),
// 1+ otherwise (sets state::MULTI_REDUCER_REP_FAILED for the caller to read).
static int multi_reducer_impl() {
  if (!util::dir_exists(state::WORKD)) abort_reducer();
  state::MULTI_FOUND = 0;
  if (cfg::REDUCE_GLIBC_OR_SS_CRASHES > 0) {
    echoit("ASSERT: REDUCE_GLIBC_OR_SS_CRASHES is active, and we ended up in multi_reducer().");
  }
  echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [" + state::RUNMODE + "] Terminating any dangling subreducer processes");
  kill_multi_reducer();
  if (state::STAGE == "V") {
    echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [" + state::RUNMODE + "] Starting " + std::to_string(cfg::MULTI_THREADS) +
           " verification subreducer threads to verify if the issue is sporadic (" + state::WORKD + "/subreducer/)");
    state::SKIPV = 0;
    state::SPORADIC = 0;
  } else {
    if (cfg::FIREWORKS != 1) {
      echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [" + state::RUNMODE + "] Starting " + std::to_string(cfg::MULTI_THREADS) +
             " simplification subreducer threads to reduce the issue (" + state::WORKD + "/subreducer/)");
    } else {
      echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [" + state::RUNMODE + "] Starting " + std::to_string(cfg::MULTI_THREADS) +
             " subreducer threads to find new bugs (" + state::WORKD + "/subreducer/)");
    }
    state::SKIPV = 1;
  }
  fs::remove_all(state::WORKD + "/subreducer/");
  util::sh("sync");
  std::this_thread::sleep_for(std::chrono::milliseconds(500));
  util::mkdir_p(state::WORKD + "/subreducer/");
  diskspace(state::WORKD + "/subreducer");
  state::MULTI_PIDS.assign(static_cast<size_t>(cfg::MULTI_THREADS) + 1, "");
  std::string txt = state::ATLEASTONCE + " [Stage " + state::STAGE + "] [" + state::RUNMODE + "] Forking subreducer threads [PIDs]:";
  // Resolve our own binary path. /proc/self/exe must be read via the readlink(2)
  // syscall here (not via the `readlink` CLI through a shell): in a shelled-out
  // `readlink -f /proc/self/exe`, /proc/self/exe is the readlink child's exe
  // (= /usr/bin/readlink), not the reducer's.
  std::string self;
  {
    char buf[PATH_MAX];
    ssize_t n = readlink("/proc/self/exe", buf, sizeof(buf) - 1);
    if (n > 0) { buf[n] = '\0'; self = buf; }
  }
  if (self.empty()) {
    echoit("Assert: failed to resolve /proc/self/exe for subreducer launch");
    std::exit(1);
  }
  for (int t = 1; t <= cfg::MULTI_THREADS; ++t) {
    std::string subw = state::WORKD + "/subreducer/" + std::to_string(t);
    util::mkdir_p(subw);
    setenv(("WORKD" + std::to_string(t)).c_str(), subw.c_str(), 1);
    // Subreducer launch: invoke self with env vars set (mirroring the bash #VARMOD# block).
    std::ostringstream env;
    env << "REDUCER_MULTI_REDUCER=1 "
        << "REDUCER_EPOCH='" << state::EPOCH << "' "
        << "REDUCER_MODE=" << cfg::MODE << " "
        << "REDUCER_TEXT='" << cfg::TEXT << "' "
        << "REDUCER_MODE5_COUNTTEXT=" << cfg::MODE5_COUNTTEXT << " "
        << "REDUCER_SKIPV=" << state::SKIPV << " "
        << "REDUCER_SPORADIC=" << state::SPORADIC << " "
        << "REDUCER_PQUERY_MULTI_CLIENT_THREADS=" << cfg::PQUERY_MULTI_CLIENT_THREADS << " "
        << "REDUCER_PQUERY_MULTI_QUERIES=" << cfg::PQUERY_MULTI_QUERIES << " "
        << "REDUCER_TS_TRXS_SETS=" << cfg::TS_TRXS_SETS << " "
        << "REDUCER_TS_DBG_CLI_OUTPUT=" << cfg::TS_DBG_CLI_OUTPUT << " "
        << "REDUCER_PAUSE_AFTER_EACH_OCCURRENCE='" << cfg::PAUSE_AFTER_EACH_OCCURRENCE << "' "
        << "REDUCER_BASEDIR='" << cfg::BASEDIR << "' "
        << "REDUCER_MYUSER='" << state::MYUSER << "' "
        << "REDUCER_WORKD='" << subw << "' ";
    // Subreducer reads cfg::INPUTFILE from argv[1] same as a normal run. Use
    // `exec -a <subw>/subreducer` so ps -ef shows "<workdir>/subreducer/<N>/subreducer"
    // as the process command — preserves framework grep contract used by ~/ds,
    // watchdog.sh ("subreducer" string match), and kill_multi_reducer.
    //
    // Verify stage (STAGE == "V") spawns subreducers against the ORIGINAL
    // cfg::INPUTFILE — we are validating that the unreduced testcase reproduces.
    // Simplification stages spawn subreducers against the PARENT'S CURRENT WORKF
    // — the iteratively-reduced working file. Mirrors reducer.sh:4736
    // (`multi_reducer $1` in verify) vs reducer.sh:5337 (`multi_reducer $WORKF`
    // in stage 1). Passing cfg::INPUTFILE in stage 1 freezes reduction at the
    // first chunk size: every subreducer restarts from the unreduced 228k-line
    // input, cuts ~38k, and commits a 190k WORKO — parent's WORKF gets
    // overwritten with the same line count each trial.
    std::string proc_name = subw + "/subreducer";
    const std::string& sub_input =
      (state::STAGE == "V") ? cfg::INPUTFILE : state::WORKF;
    std::string cmd = env.str() + "bash -c 'exec -a \"" + proc_name + "\" \"" + self + "\" \"" + sub_input + "\"' >/dev/null 2>/dev/null & echo $!";
    std::string pid = util::sh_capture_trimmed("(" + cmd + ")");
    std::this_thread::sleep_for(std::chrono::milliseconds(200));
    state::MULTI_PIDS[t] = pid;
    txt += " #" + std::to_string(t) + " [" + pid + "]";
  }
  echoit(txt);

  if (state::STAGE == "V") {
    echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [" + state::RUNMODE + "] Waiting for all forked verification subreducer threads to finish/terminate");
    std::string out = state::ATLEASTONCE + " [Stage " + state::STAGE + "] [" + state::RUNMODE + "] Finished/Terminated verification subreducer threads:";
    for (int t = 1; t <= cfg::MULTI_THREADS; ++t) {
      while (true) {
        std::string pid = state::MULTI_PIDS[t];
        if (pid.empty()) break;
        if (util::sh("kill -0 " + pid + " 2>/dev/null") != 0) break;
        std::string logfile = state::WORKD + "/subreducer/" + std::to_string(t) + "/reducer.log";
        if (util::file_readable(logfile)) {
          if (util::sh("grep -Eqi --binary-files=text 'Failed to start the.*server' \"" + logfile + "\"") == 0) {
            util::sh("kill -9 " + pid);
            break;
          }
        }
        std::this_thread::sleep_for(std::chrono::milliseconds(250));
      }
      out += " #" + std::to_string(t);
      echoit_overwrite(out);
      if (t == 20 && cfg::MULTI_THREADS > 20) {
        echoit(out);
        out = state::ATLEASTONCE + " [Stage " + state::STAGE + "] [" + state::RUNMODE + "] Finished/Terminated verification subreducer threads:";
      }
    }
    echoit(out);
    echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [" + state::RUNMODE + "] All verification subreducer threads have finished/terminated");
  } else {
    if (cfg::FIREWORKS != 1) {
      echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [" + state::RUNMODE + "] Waiting for any forked simplifation subreducer threads to find a shorter file");
    } else {
      echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [" + state::RUNMODE + "] Waiting for any forked subreducer threads to find a new bug");
    }
    int found = 0;
    while (found == 0) {
      for (int t = 1; t <= cfg::MULTI_THREADS; ++t) {
        std::string subw = state::WORKD + "/subreducer/" + std::to_string(t);
        if (!util::dir_exists(state::WORKD) || !util::file_readable(cfg::INPUTFILE) || !util::file_readable(state::THIS_REDUCER)) abort_reducer();
        std::string verified = subw + "/VERIFIED";
        std::error_code ec; auto sz = fs::file_size(verified, ec);
        if (!ec && sz > 0) {
          std::this_thread::sleep_for(std::chrono::milliseconds(1500));
          if (cfg::FIREWORKS != 1) {
            echoit_overwrite(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [" + state::RUNMODE + "] Terminating simplification subreducer threads...");
          } else {
            echoit_overwrite(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [" + state::RUNMODE + "] Terminating subreducer threads...");
          }
          util::sh("ps -ef | grep 'subreducer' | grep -v grep | grep " + state::EPOCH + " | awk '{print $2}' | xargs kill -9 > /dev/null 2>&1");
          std::this_thread::sleep_for(std::chrono::seconds(1));
          util::sh("ps -ef | grep 'subreducer' | grep -v grep | grep " + state::EPOCH + " | awk '{print $2}' | xargs kill -9 > /dev/null 2>&1");
          std::this_thread::sleep_for(std::chrono::seconds(2));
          diskspace(fs::path(state::WORKF).parent_path().string());
          std::string worko_inner = util::sh_capture_trimmed(
            "cat \"" + verified + "\" | grep -E --binary-files=text 'WORKO' | sed -e 's/^.*://' -e 's/[ ]*//g'");
          util::sh("grep -E --binary-files=text -v \"^# mysqld options required for replay:\" \"" + worko_inner + "\" > \"" + state::WORKF + "\"");
          if (cfg::FIREWORKS != 1 && util::file_readable(state::WORKO)) {
            if (cfg::RR_TRACING == 1 && cfg::RR_SAVE_ALL_TRACES == 1) {
              save_rr_trace(state::WORK_BUG_DIR + "/rr/" + state::STAGE + "_" + std::to_string(state::TRIAL) + "_rr_trace");
              echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [Trial " + std::to_string(state::TRIAL) +
                     "] Saved RR trace in " + state::WORK_BUG_DIR + "/rr/" + state::STAGE + "_" + std::to_string(state::TRIAL) + "_rr_trace");
            }
            diskspace(fs::path(state::WORKO).parent_path().string());
            util::sh("cp -f \"" + state::WORKO + "\" \"" + state::WORKO + ".prev\"");
            echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [" + state::RUNMODE + "] Previous good testcase backed up as " + state::WORKO + ".prev");
          }
          diskspace(fs::path(state::WORKO).parent_path().string());
          util::sh("cp -f \"" + state::WORKF + "\" \"" + state::WORKO + "\"");
          write_workO_options_header();
          diskspace(fs::path(state::WORK_OUT).parent_path().string());
          util::sh("cp -f \"" + state::WORKO + "\" \"" + state::WORK_OUT + "\"");
          state::ATLEASTONCE = "[*]";
          if (cfg::FIREWORKS != 1) {
            echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [" + state::RUNMODE + "] Thread #" + std::to_string(t) + " reproduced the issue: testcase saved in " + state::WORKO);
          } else {
            state::NR_OF_NEWBUGS++;
            echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [" + state::RUNMODE + "] [" + std::to_string(state::NR_OF_NEWBUGS) + " New Bugs Found] Thread #" + std::to_string(t) + " found a new unseen bug: " + util::sh_capture_trimmed("cat \"" + subw + "/MYBUG.FOUND\" | head -n1"));
          }
          found = 1;
          if (cfg::PAUSE_AFTER_EACH_OCCURRENCE == 1) {
            echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [" + state::RUNMODE + "] PAUSE_AFTER_EACH_OCCURRENCE is active. Press 'Enter' twice to continue...");
            std::cin.get(); std::cin.get();
          }
          break;
        }
        // Check if this subreducer is still running; if not, restart.
        std::string pid = state::MULTI_PIDS[t];
        if (!pid.empty() && util::sh("ps -p" + pid + " >/dev/null 2>&1") != 0) {
          std::string restart_w = subw;
          // Test for known BASEDIR-missing scenario and recover.
          if (!util::dir_exists(cfg::BASEDIR)) {
            if (!state::BASEDIR_ALT_PATH.empty() && util::dir_exists(state::BASEDIR_ALT_PATH)) {
              echoit("Warning: The BASEDIR was removed/moved. Attempting recovery via " + state::BASEDIR_ALT_PATH);
              cfg::BASEDIR = state::BASEDIR_ALT_PATH;
              state::BASEDIR_ALT_PATH.clear();
            } else {
              std::cerr << "Assert: BASEDIR (" << cfg::BASEDIR << ") missing. Terminating.\n"; std::exit(1);
            }
          }
          // Clean restart_w except for subreducer artifact (we have no .sh; respawn via the binary).
          util::sh("rm -Rf \"" + restart_w + "\"/[^s]*");
          util::sh("rm -Rf \"" + restart_w + "\"/socket*");
          util::mkdir_p(restart_w);
          // Match the initial-spawn env block above 1-for-1 (MODE5_COUNTTEXT, PQUERY_MULTI_*, TS_*, PAUSE_AFTER_EACH_OCCURRENCE included) so a restarted subreducer behaves identically to a fresh one. Earlier divergence here left mode-specific state at its default in the respawned process.
          std::ostringstream env;
          env << "REDUCER_MULTI_REDUCER=1 "
              << "REDUCER_EPOCH='" << state::EPOCH << "' "
              << "REDUCER_MODE=" << cfg::MODE << " "
              << "REDUCER_TEXT='" << cfg::TEXT << "' "
              << "REDUCER_MODE5_COUNTTEXT=" << cfg::MODE5_COUNTTEXT << " "
              << "REDUCER_SKIPV=" << state::SKIPV << " "
              << "REDUCER_SPORADIC=" << state::SPORADIC << " "
              << "REDUCER_PQUERY_MULTI_CLIENT_THREADS=" << cfg::PQUERY_MULTI_CLIENT_THREADS << " "
              << "REDUCER_PQUERY_MULTI_QUERIES=" << cfg::PQUERY_MULTI_QUERIES << " "
              << "REDUCER_TS_TRXS_SETS=" << cfg::TS_TRXS_SETS << " "
              << "REDUCER_TS_DBG_CLI_OUTPUT=" << cfg::TS_DBG_CLI_OUTPUT << " "
              << "REDUCER_PAUSE_AFTER_EACH_OCCURRENCE='" << cfg::PAUSE_AFTER_EACH_OCCURRENCE << "' "
              << "REDUCER_BASEDIR='" << cfg::BASEDIR << "' "
              << "REDUCER_MYUSER='" << state::MYUSER << "' "
              << "REDUCER_WORKD='" << restart_w << "' ";
          // Re-spawn with exec -a so ps -ef shows "<workdir>/subreducer" — see comment at the initial spawn site above. Same verify-vs-stage1 INPUTFILE/WORKF rule applies on restart.
          std::string restart_proc_name = restart_w + "/subreducer";
          const std::string& restart_input =
            (state::STAGE == "V") ? cfg::INPUTFILE : state::WORKF;
          std::string cmd = env.str() + "bash -c 'exec -a \"" + restart_proc_name + "\" \"" + self + "\" \"" + restart_input + "\"' >/dev/null 2>/dev/null & echo $!";
          state::MULTI_PIDS[t] = util::sh_capture_trimmed("(" + cmd + ")");
          echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [" + state::RUNMODE + "] Thread #" + std::to_string(t) + " disappeared. Restarted (PID " + state::MULTI_PIDS[t] + ")");
        }
        std::this_thread::sleep_for(std::chrono::seconds(1));
      }
    }
    echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [" + state::RUNMODE + "] All subreducer threads have finished/terminated");
  }

  if (state::STAGE == "V") {
    std::string out;
    for (int t = 1; t <= cfg::MULTI_THREADS; ++t) {
      std::string verified = state::WORKD + "/subreducer/" + std::to_string(t) + "/VERIFIED";
      std::error_code ec; auto sz = fs::file_size(verified, ec);
      if (!ec && sz > 0) {
        state::ATLEASTONCE = "[*]";
        state::MULTI_FOUND++;
        out += " #" + std::to_string(t);
      }
    }
    state::SPORADIC = 1;
    if (state::MULTI_FOUND == 0) {
      echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [" + state::RUNMODE + "] Threads which reproduced the issue: <none>");
      state::MULTI_REDUCER_REP_FAILED = 1;
    } else if (state::MULTI_FOUND == cfg::MULTI_THREADS) {
      echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [" + state::RUNMODE + "] Threads which reproduced the issue:" + out);
      if (cfg::FORCE_SPORADIC > 0) {
        echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [" + state::RUNMODE + "] All threads reproduced; FORCE_SPORADIC is on, sporadic reduction will commence");
      } else {
        echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [" + state::RUNMODE + "] All threads reproduced the issue: this issue is not sporadic");
        state::SPORADIC = 0;
      }
      if (cfg::MODE < 6) {
        echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [" + state::RUNMODE + "] Ensuring any rogue subreducer processes are terminated");
        kill_multi_reducer();
      }
      state::MULTI_REDUCER_REP_FAILED = 0;
    } else {
      echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [" + state::RUNMODE + "] Threads which reproduced the issue:" + out);
      echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [" + state::RUNMODE + "] Only " + std::to_string(state::MULTI_FOUND) + " out of " + std::to_string(cfg::MULTI_THREADS) + " threads reproduced the issue: this issue is sporadic");
      state::MULTI_REDUCER_REP_FAILED = 0;
    }
    return state::MULTI_FOUND;
  }
  state::MULTI_REDUCER_REP_FAILED = 0;
  return 0;
}
static void multi_reducer() { (void)multi_reducer_impl(); }

// multi_reducer_decide_input — mirror reducer.sh:1672..1705
static void multi_reducer_decide_input() {
  echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [" + state::RUNMODE + "] Deciding which verified output file to keep out of " + std::to_string(state::MULTI_FOUND) + " threads");
  long long lowest = 100;
  for (int t = 1; t <= cfg::MULTI_THREADS; ++t) {
    std::string subw = state::WORKD + "/subreducer/" + std::to_string(t);
    std::string verified = subw + "/VERIFIED";
    std::error_code ec; auto sz = fs::file_size(verified, ec);
    if (!ec && sz > 0) {
      std::string trial = util::sh_capture_trimmed(
        "cat \"" + verified + "\" | grep -E --binary-files=text 'TRIAL' | sed -e 's/^.*://' -e 's/[ ]*//g'");
      long long tlvl = 100;
      try { tlvl = std::stoll(trial); } catch (...) {}
      if (tlvl == 1) {
        diskspace(fs::path(state::WORKF).parent_path().string());
        std::string worko_inner = util::sh_capture_trimmed(
          "cat \"" + verified + "\" | grep -E --binary-files=text 'WORKO' | sed -e 's/^.*://' -e 's/[ ]*//g'");
        util::sh("cp -f \"" + worko_inner + "\" \"" + state::WORKF + "\"");
        echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [" + state::RUNMODE + "] Found verified, maximum initial simplification file, at thread #" + std::to_string(t) + ": Using it as new input file");
        if (util::file_readable(subw + "/MYEXTRA")) {
          cfg::MYEXTRA = util::sh_capture_trimmed("cat \"" + subw + "/MYEXTRA\"");
        }
        break;
      } else if (tlvl < lowest) {
        lowest = tlvl;
        diskspace(fs::path(state::WORKF).parent_path().string());
        std::string worko_inner = util::sh_capture_trimmed(
          "cat \"" + verified + "\" | grep -E --binary-files=text 'WORKO' | sed -e 's/^.*://' -e 's/[ ]*//g'");
        util::sh("cp -f \"" + worko_inner + "\" \"" + state::WORKF + "\"");
        echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [" + state::RUNMODE + "] Found verified, level " + std::to_string(tlvl) + " simplification file, at thread #" + std::to_string(t) + ": Using it as new input file, unless better is found");
        if (util::file_readable(subw + "/MYEXTRA")) {
          cfg::MYEXTRA = util::sh_capture_trimmed("cat \"" + subw + "/MYEXTRA\"");
        }
      }
    }
  }
  echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [" + state::RUNMODE + "] Removing verify stage subreducer directory");
  fs::remove_all(state::WORKD + "/subreducer/");
}

// TS_init_all_sql_files — mirror reducer.sh:1706..1754
static void TS_init_all_sql_files() {
  int tsdata_count = 0;
  try { tsdata_count = std::stoi(util::sh_capture_trimmed(
    "ls --color=never " + state::TS_INPUTDIR + "/CT[0-9]*.sql 2>/dev/null | wc -l | tr -d '[\\t\\n ]*'")); } catch (...) {}
  if (tsdata_count == 1) {
    state::TS_DATAINPUTFILE = util::sh_capture_trimmed(
      "ls --color=never " + state::TS_INPUTDIR + "/CT[0-9]*.sql");
  } else {
    std::cerr << "ASSERT: do not know how to handle more than one ThreadSync data input file [yet].\nTerminating now.\n";
    std::exit(1);
  }
  int real_threads = 0;
  std::string ls = util::sh_capture(
    "ls --color=never " + state::TS_INPUTDIR + "/C[0-9]*T[0-9]*.sql | sort");
  for (const auto& f : util::split(ls, '\n')) {
    if (f.empty()) continue;
    ++real_threads;
    setenv(("TS_SQLINPUTFILE" + std::to_string(real_threads)).c_str(), f.c_str(), 1);
  }
  if (real_threads != state::TS_THREADS) {
    std::cerr << "ASSERT: TS_REAL_THREAD != TS_THREADS: " << real_threads << " != " << state::TS_THREADS << "\nTerminating now.\n";
    std::exit(1);
  }
  if (state::TS_ORIG_VARS_FLAG == 0) {
    state::TS_ORIG_DATAINPUTFILE = state::TS_DATAINPUTFILE;
    state::TS_ORIG_THREADS = state::TS_THREADS;
    state::TS_ORIG_VARS_FLAG = 1;
  }
  echoit("[Init] Input directory: " + state::TS_INPUTDIR + "/");
  echoit("[Init] Input files: Data: " + state::TS_DATAINPUTFILE);
  for (int t = 1; t <= state::TS_THREADS; ++t) {
    setenv(("WORKF" + std::to_string(t)).c_str(), (state::WORKD + "/in" + std::to_string(t) + ".sql").c_str(), 1);
    setenv(("WORKT" + std::to_string(t)).c_str(), (state::WORKD + "/in" + std::to_string(t) + ".tmp").c_str(), 1);
    std::string sql_in = util::getenv_or(("TS_SQLINPUTFILE" + std::to_string(t)).c_str());
    std::string base = sql_in;
    auto pos = base.find_last_of('/');
    if (pos != std::string::npos) base = base.substr(pos + 1);
    setenv(("WORKO" + std::to_string(t)).c_str(), (state::WORKD + "/out/" + base + "_out").c_str(), 1);
    echoit("[Init] Input files: Thread " + std::to_string(t) + ": " + sql_in);
  }
  diskspace(state::WORKD);
  for (int t = 1; t <= state::TS_THREADS; ++t) {
    std::string sql_in = util::getenv_or(("TS_SQLINPUTFILE" + std::to_string(t)).c_str());
    std::string wf = util::getenv_or(("WORKF" + std::to_string(t)).c_str());
    util::sh("cat \"" + sql_in + "\" > \"" + wf + "\"");
  }
}
// Helper: $INPUTFILE-dir prefix used to derive WORK_* file names. Mirrors
//   echo $INPUTFILE | sed "s|/[^/]\+$|/|"
static std::string inputfile_dir_prefix() {
  auto pos = cfg::INPUTFILE.find_last_of('/');
  return (pos == std::string::npos) ? cfg::INPUTFILE : cfg::INPUTFILE.substr(0, pos + 1);
}

// Helper: free KB on the mountpoint hosting `path`, via `df -k -P`.
static long long df_free_kb(const std::string& filter_pat) {
  std::string cmd =
    "df -k -P 2>&1 | grep -E --binary-files=text -v 'docker/devicemapper.*Permission denied' | grep -E --binary-files=text \"" +
    filter_pat + "\" | awk '{print $4}' | grep -E --binary-files=text -v 'docker.devicemapper'";
  std::string s = util::sh_capture_trimmed(cmd);
  if (s.empty()) return 0;
  try { return std::stoll(s); } catch (...) { return 0; }
}

// init_workdir_and_files — mirror reducer.sh:1807..2304
static void init_workdir_and_files() {
  while (true) {
    if (state::MULTI_REDUCER == 1) {
      // Subreducer: WORKD is the per-subreducer dir set by parent's multi_reducer
      // via the REDUCER_WORKD env var (mirrors bash $WORKD="$(dirname $0)" where
      // $0 is the subreducer script path under $MAIN_WORKD/subreducer/<N>).
      // Only fall back to argv[0]'s parent if REDUCER_WORKD wasn't supplied.
      if (state::WORKD.empty()) {
        char buf[PATH_MAX];
        ssize_t n = readlink("/proc/self/exe", buf, sizeof(buf) - 1);
        if (n > 0) {
          buf[n] = '\0';
          state::WORKD = fs::path(buf).parent_path().string();
        } else {
          state::WORKD = ".";
        }
      }
      break;
    }
    // /tmp free-space check
    long long tmp_free = 0;
    try { tmp_free = std::stoll(util::sh_capture_trimmed(
      "df -k -P /tmp | grep -E --binary-files=text -v 'Mounted' | awk '{print $4}'")); } catch (...) {}
    if (tmp_free < 400000) {
      std::cerr << "Error: /tmp does not have enough free space (400Mb free space required for temporary files and any ongoing programs)\n";
      std::cerr << "Terminating now.\n";
      std::exit(1);
    }
    if (cfg::WORKDIR_LOCATION == 3) {
      if (!util::dir_exists(cfg::WORKDIR_M3_DIRECTORY) || access(cfg::WORKDIR_M3_DIRECTORY.c_str(), X_OK) != 0) {
        std::cerr << "Error: WORKDIR_LOCATION=3 (a specific storage location) is set, yet WORKDIR_M3_DIRECTORY (set to "
                  << cfg::WORKDIR_M3_DIRECTORY << ") does not exist, or could not be read.\n";
        std::cerr << "Terminating now.\n";
        std::exit(1);
      }
      if (df_free_kb(cfg::WORKDIR_M3_DIRECTORY) < 3500000) {
        std::cerr << "Error: " << cfg::WORKDIR_M3_DIRECTORY << " does not have enough free space (3.5Gb free space required)\n";
        std::cerr << "Terminating now.\n"; std::exit(1);
      }
      state::WORKD = cfg::WORKDIR_M3_DIRECTORY + "/" + state::EPOCH;
    } else if (cfg::WORKDIR_LOCATION == 2) {
      if (!util::dir_exists("/mnt/ram/") || access("/mnt/ram/", X_OK) != 0) {
        std::cerr << "Error: ramfs storage usage was specified (WORKDIR_LOCATION=2), yet /mnt/ram/ does not exist, or could not be read.\n";
        std::cerr << "Suggestion: setup a ram drive using the following commands at your shell prompt:\n";
        std::cerr << "sudo mkdir -p /mnt/ram; sudo mount -t ramfs -o size=4g ramfs /mnt/ram; sudo chmod -R 777 /mnt/ram;\n";
        std::cerr << "Terminating now.\n"; std::exit(1);
      }
      if (df_free_kb("/mnt/ram$") < 3500000) {
        std::cerr << "Error: /mnt/ram/ does not have enough free space (3.5Gb free space required)\n";
        std::cerr << "Terminating now.\n"; std::exit(1);
      }
      state::WORKD = "/mnt/ram/" + state::EPOCH;
    } else if (cfg::WORKDIR_LOCATION == 1) {
      if (!util::dir_exists("/dev/shm/") || access("/dev/shm/", X_OK) != 0) {
        std::cerr << "Error: tmpfs storage usage was specified (WORKDIR_LOCATION=1), yet /dev/shm/ does not exist, or could not be read.\n";
        std::cerr << "Terminating now.\n"; std::exit(1);
      }
      if (df_free_kb("/dev/shm$") < 3500000) {
        std::cerr << "Error: /dev/shm/ does not have enough free space (3.5Gb free space required)\n";
        std::cerr << "Terminating now.\n"; std::exit(1);
      }
      state::WORKD = "/dev/shm/" + state::EPOCH;
    } else {
      if (!util::dir_exists("/tmp/") || access("/tmp/", X_OK) != 0) {
        std::cerr << "Error: /tmp/ storage usage was specified (WORKDIR_LOCATION=0), yet /tmp/ does not exist, or could not be read.\n";
        std::cerr << "Terminating now.\n"; std::exit(1);
      }
      if (df_free_kb("[ \\t]/$") < 3500000) {
        std::cerr << "Error: The drive mounted as / does not have enough free space (3.5Gb free space required)\n";
        std::cerr << "Terminating now.\n"; std::exit(1);
      }
      state::WORKD = "/tmp/" + state::EPOCH;
    }
    if (util::dir_exists(state::WORKD)) {
      // EPOCH--
      try {
        long long e = std::stoll(state::EPOCH);
        state::EPOCH = std::to_string(e - 1);
      } catch (...) {}
    } else {
      break;
    }
  }
  if (state::MULTI_REDUCER != 1) {
    if (util::dir_exists(state::WORKD)) {
      std::cerr << "Assert: " << state::WORKD << " already exists? This should not happen.\n";
      std::exit(1);
    }
    util::mkdir_p(state::WORKD);
  }
  if (cfg::MDG == 0) {
    if (cfg::REPLICATION == 1) {
      util::mkdir_p(state::WORKD + "/data");
      util::mkdir_p(state::WORKD + "/data_slave");
      util::mkdir_p(state::WORKD + "/tmp");
      util::mkdir_p(state::WORKD + "/tmp_slave");
      util::mkdir_p(state::WORKD + "/log");
    } else {
      util::mkdir_p(state::WORKD + "/data");
      util::mkdir_p(state::WORKD + "/tmp");
      util::mkdir_p(state::WORKD + "/log");
    }
  }
  util::sh("chmod -R 777 " + state::WORKD);
  util::write_file(state::WORKD + "/reducer.log", "");
  state::REDUCER_LOG_PATH = state::WORKD + "/reducer.log";
  state::reducer_log.open(state::REDUCER_LOG_PATH, std::ios::app);

  // Reducer banner — THIS_REDUCER was set from argv[0] realpath in main().
  if (state::THIS_REDUCER.empty()) {
    char buf[PATH_MAX];
    ssize_t n = readlink("/proc/self/exe", buf, sizeof(buf) - 1);
    if (n > 0) { buf[n] = '\0'; state::THIS_REDUCER = buf; }
  }
  echoit("[Init] Reducer: " + state::THIS_REDUCER);
  echoit("[Init] Reducer PID: " + std::to_string(getpid()));
  state::TMP_DIR = state::WORKD + "/tmp";
  setenv("TMP", state::TMP_DIR.c_str(), 1);
  if (cfg::REDUCE_GLIBC_OR_SS_CRASHES > 0) {
    echoit("[Init] Console typescript log for REDUCE_GLIBC_OR_SS_CRASHES: /tmp/reducer_typescript" +
           state::TYPESCRIPT_UNIQUE_FILESUFFIX + ".log");
  }
  // jemalloc preload fragments (constructed as bash literals; later used by generate_run_scripts)
  state::JE1 = "if [ \"${JEMALLOC}\" != \"\" -a -r \"${JEMALLOC}\" ]; then export LD_PRELOAD=${JEMALLOC}";
  state::JE2 = " elif [ -r `sudo find /usr/*lib*/ -name libjemalloc.so.1 | head -n1` ]; then export LD_PRELOAD=`sudo find /usr/*lib*/ -name libjemalloc.so.1 | head -n1`";
  state::JE3 = " elif [ -r ${BASEDIR}/lib/mysql/libjemalloc.so.1 ]; then export LD_PRELOAD=${BASEDIR}/lib/mysql/libjemalloc.so.1";
  state::JE4 = " else echo 'Warning: jemalloc was not loaded as it was not found (this is fine for MS, but do check ./" + state::EPOCH + "_mybase to set correct jemalloc location for PS)'; fi";

  // WORK_BUG_DIR = directory part of INPUTFILE
  {
    std::string p = cfg::INPUTFILE;
    auto pos = p.find_last_of('/');
    if (pos != std::string::npos) p.resize(pos);
    while (!p.empty() && p.back() == '/') p.pop_back();
    state::WORK_BUG_DIR = p;
    if (state::WORK_BUG_DIR == cfg::INPUTFILE || state::WORK_BUG_DIR == ("./" + cfg::INPUTFILE)) {
      state::WORK_BUG_DIR = fs::current_path().string();
    }
  }
  state::WORKF = state::WORKD + "/in.sql";
  state::WORKT = state::WORKD + "/in.tmp";
  std::string pref = inputfile_dir_prefix();
  state::WORK_BASEDIR_FILE = pref + state::EPOCH + "_mybase";
  state::WORK_INIT      = pref + state::EPOCH + "_init";
  state::WORK_START     = pref + state::EPOCH + "_start";
  state::WORK_START_VALGRIND = pref + state::EPOCH + "_start_valgrind";
  state::WORK_STOP      = pref + state::EPOCH + "_stop";
  state::WORK_RUN       = pref + state::EPOCH + "_run";
  state::WORK_GDB       = pref + state::EPOCH + "_gdb";
  state::WORK_PARSE_CORE = pref + state::EPOCH + "_parse_core";
  state::WORK_HOW_TO_USE = pref + state::EPOCH + "_how_to_use.txt";
  if (cfg::USE_PQUERY == 1) {
    state::WORK_RUN_PQUERY = pref + state::EPOCH + "_run_pquery";
    std::string pq_base = cfg::PQUERY_LOC;
    auto pos = pq_base.find_last_of('/');
    if (pos != std::string::npos) pq_base = pq_base.substr(pos + 1);
    state::WORK_PQUERY_BIN = pref + state::EPOCH + "_" + pq_base;
  }
  state::WORK_CL  = pref + state::EPOCH + "_cl";
  state::WORK_OUT = pref + state::EPOCH + ".sql";
  if (cfg::MODE >= 6 && cfg::MODE <= 9) {
    util::mkdir_p(state::WORKD + "/out");
    util::mkdir_p(state::WORKD + "/log");
    TS_init_all_sql_files();
  } else {
    if (state::MULTI_REDUCER != 1) {
      state::WORKO = cfg::INPUTFILE + "_out";
    } else {
      // Save output file in individual workdirs
      std::string base = cfg::INPUTFILE;
      auto pos = base.find_last_of('/');
      if (pos != std::string::npos) base = base.substr(pos + 1);
      state::WORKO = state::WORKD + "/" + base + "_out";
    }
    echoit("[Init] Input file: " + cfg::INPUTFILE);
    if (cfg::FIREWORKS == 1) {
      echoit("[Init] Output dir (FIREWORKS mode): " + cfg::NEW_BUGS_SAVE_DIR);
    } else {
      if (state::WORK_BUG_DIR == cfg::INPUTFILE) {
        echoit("[Init] Output dir: " + fs::current_path().string());
      } else {
        echoit("[Init] Output dir: " + state::WORK_BUG_DIR);
      }
    }
    if (cfg::FIREWORKS != 1) {
      diskspace(fs::path(state::WORKF).parent_path().string());
      if (state::MULTI_REDUCER != 1 && cfg::FORCE_SKIPV > 0) {
        if (cfg::USE_PQUERY == 0) {
          // DROPC on a single line
          util::write_file(state::WORKF, state::DROPC + "\n");
          util::sh("grep -E --binary-files=text -v \"" + state::DROPC + "\" \"" + cfg::INPUTFILE + "\" >> \"" + state::WORKF + "\"");
        } else {
          // pquery: multi-line DROPC
          util::sh("cp \"" + cfg::INPUTFILE + "\" \"" + state::WORKF + "\"");
          remove_dropc(state::WORKF);
          std::string suffix = util::rand_suffix();
          std::string tmp = "/tmp/WORKF_" + suffix + ".tmp";
          util::sh("echo \"$(echo \"" + state::DROPC + "\" | sed 's|;|;\\n|g' | grep --binary-files=text -vE '^$')\" > \"" + tmp + "\"");
          util::sh("cat \"" + state::WORKF + "\" >> \"" + tmp + "\"");
          fs::remove(state::WORKF);
          util::move_file(tmp, state::WORKF);
        }
      } else {
        util::sh("cp \"" + cfg::INPUTFILE + "\" \"" + state::WORKF + "\"");
      }
      // QC: trim WORKF after first QCTEXT match.
      if (!state::QCTEXT.empty()) {
        util::sh("sed -i \"/" + state::QCTEXT + "/q\" \"" + state::WORKF + "\"");
      }
      // Ensure trailing newline.
      std::error_code ec;
      auto sz = fs::file_size(state::WORKF, ec);
      if (!ec && sz > 0) {
        std::string last = util::sh_capture_trimmed("tail -c1 \"" + state::WORKF + "\" 2>/dev/null");
        if (!last.empty()) util::append_file(state::WORKF, "\n");
      }
    }
  }
  echoit("[Init] Base dir: " + cfg::BASEDIR);
  echoit("[Init] Work dir: " + state::WORKD);
  echoit("[Init] EPOCH ID: " + state::EPOCH + " (used for various file and directory names)");
  if (cfg::MDG == 1) {
    for (int i = 1; i <= cfg::NR_OF_NODES; ++i) {
      echoit("[Init] MDG Node #" + std::to_string(i) + " Client: " + cfg::BASEDIR + "/bin/mysql -uroot -S" + state::WORKD + "/node" + std::to_string(i) + "/node" + std::to_string(i) + "_socket.sock");
    }
  } else if (cfg::GRP_RPL == 1) {
    echoit("[Init] Group Replication Node #1 Client: " + cfg::BASEDIR + "/bin/mysql -uroot -S" + state::WORKD + "/node1/node1_socket.sock");
    echoit("[Init] Group Replication Node #2 Client: " + cfg::BASEDIR + "/bin/mysql -uroot -S" + state::WORKD + "/node2/node2_socket.sock");
    echoit("[Init] Group Replication Node #3 Client: " + cfg::BASEDIR + "/bin/mysql -uroot -S" + state::WORKD + "/node3/node3_socket.sock");
  } else if (cfg::REPLICATION == 1) {
    echoit("[Init] Standard Master/Slave replication is active");
    echoit("[Init] Replication Master Client (When MULTI mode is not active): " + cfg::BASEDIR + "/bin/mysql -uroot -S" + state::WORKD + "/socket.sock");
    echoit("[Init] Replication Slave Client (When MULTI mode is not active): " + cfg::BASEDIR + "/bin/mysql -uroot -S" + state::WORKD + "/slave_socket.sock");
    echoit("[Init] Replication Master Client example for subreducers (MULTI): " + cfg::BASEDIR + "/bin/mysql -uroot -S" + state::WORKD + "/subreducer/1/socket.sock");
    echoit("[Init] Replication Slave Client example for subreducers (MULTI): " + cfg::BASEDIR + "/bin/mysql -uroot -S" + state::WORKD + "/subreducer/1/slave_socket.sock");
  } else {
    echoit("[Init] Server: " + state::BIN + " (as " + state::MYUSER + ")");
    if (cfg::REDUCE_GLIBC_OR_SS_CRASHES > 0) {
      echoit("[Init] Client: " + cfg::BASEDIR + "/bin/mysql -uroot -S" + state::WORKD + "/socket.sock");
    } else {
      if (cfg::FIREWORKS != 1) {
        echoit("[Init] Client (When MULTI mode is not active): " + cfg::BASEDIR + "/bin/mysql -uroot -S" + state::WORKD + "/socket.sock");
        echoit("[Init] Client example for subreducers (MULTI): " + cfg::BASEDIR + "/bin/mysql -uroot -S" + state::WORKD + "/subreducer/1/socket.sock");
      } else {
        echoit("[Init] Client example: " + cfg::BASEDIR + "/bin/mysql -uroot -S" + state::WORKD + "/subreducer/1/socket.sock");
      }
    }
  }
  if (cfg::MDG == 1) {
    echoit("[Init] Galera Cluster Temporary directories (TMP Variable) set to " + state::WORKD + "/tmp[1-" + std::to_string(cfg::NR_OF_NODES) + "]");
  } else {
    echoit("[Init] Temporary directory (TMP Variable) set to " + state::TMP_DIR);
  }
  if (cfg::SKIPSTAGEBELOW > 0) echoit("[Init] SKIPSTAGEBELOW active. Stages up to and including " + std::to_string(cfg::SKIPSTAGEBELOW) + " are skipped");
  if (cfg::SKIPSTAGEABOVE < 9) echoit("[Init] SKIPSTAGEABOVE active. Stages above and including " + std::to_string(cfg::SKIPSTAGEABOVE) + " are skipped");
  if (cfg::PQUERY_MULTI > 0) {
    echoit("[Init] PQUERY_MULTI mode active, so automatically set USE_PQUERY=1: testcase reduction will be done using pquery");
    if (cfg::PQUERY_REVERSE_NOSHUFFLE_OPT > 0) {
      echoit("[Init] PQUERY_MULTI mode active, PQUERY_REVERSE_NOSHUFFLE_OPT on: Semi-true multi-threaded testcase reduction using pquery sequential replay commencing");
    } else {
      echoit("[Init] PQUERY_MULTI mode active, PQUERY_REVERSE_NOSHUFFLE_OPT off: True multi-threaded testcase reduction using pquery random replay commencing");
    }
  } else if (cfg::PQUERY_REVERSE_NOSHUFFLE_OPT > 0) {
    if (cfg::FORCE_SKIPV > 0 && cfg::FORCE_SPORADIC > 0) {
      echoit("[Init] PQUERY_REVERSE_NOSHUFFLE_OPT turned on. Replay will be random instead of sequential (whilst still using a single thread client per mariadbd/mysqld)");
    } else {
      echoit("[Init] PQUERY_REVERSE_NOSHUFFLE_OPT turned on. Replay will be random instead of sequential. This setting is best combined with FORCE_SKIPV=1 and FORCE_SPORADIC=1!");
    }
  }
  if (cfg::FORCE_SKIPV > 0 && cfg::FIREWORKS != 1) {
    if (state::MULTI_REDUCER != 1 && cfg::SKIPSTAGEBELOW < 2) {
      echoit("[Init] FORCE_SKIPV active. Verify stage skipped, and immediately commencing multi threaded simplification");
    } else {
      echoit("[Init] FORCE_SKIPV active. Verify stage skipped, and immediately commencing simplification");
    }
  }
  if (cfg::FORCE_SKIPV > 0 && cfg::FORCE_SPORADIC > 0 && cfg::FIREWORKS != 1)
    echoit("[Init] FORCE_SKIPV active, so FORCE_SPORADIC is automatically set active also");
  if (cfg::REDUCE_GLIBC_OR_SS_CRASHES > 0) {
    if (cfg::FORCE_SKIPV > 0) {
      echoit("[Init] REDUCE_GLIBC_OR_SS_CRASHES active, so automatically skipping VERIFY mode as GLIBC crashes may be sporadic more often (this happens irrespective of FORCE_SKIPV=1)");
    } else {
      echoit("[Init] REDUCE_GLIBC_OR_SS_CRASHES active, so automatically skipping VERIFY mode as GLIBC crashes may be sporadic more often");
    }
    echoit("[Init] REDUCE_GLIBC_OR_SS_CRASHES active, so automatically set SLOW_DOWN_CHUNK_SCALING=1 to slow down chunk size scaling");
    if (cfg::FORCE_SPORADIC > 0) {
      echoit("[Info] FORCE_SPORADIC active, issue is assumed to be sporadic");
      echoit("[Init] FORCE_SPORADIC active: STAGE1_LINES variable was overwritten and set to " + std::to_string(cfg::STAGE1_LINES) + " to match");
    }
    if (cfg::MODE == 3) {
      echoit("[WARNING] ---------------------");
      echoit("[WARNING] REDUCE_GLIBC_OR_SS_CRASHES active and MODE=3. Have you updated the TEXT to a search string matching the console (on-screen) output of a GLIBC crash instead of using error-log text?");
      echoit("[WARNING] ---------------------");
    }
  } else if (cfg::FORCE_SPORADIC > 0 && cfg::FIREWORKS != 1) {
    if (cfg::FORCE_SKIPV > 0) {
      echoit("[Init] FORCE_SPORADIC active. Issue is assumed to be sporadic");
    } else {
      echoit("[Init] FORCE_SPORADIC active. Issue is assumed to be sporadic, even if verify stage shows otherwise");
    }
  }
  if (cfg::FORCE_SPORADIC > 0 && cfg::FIREWORKS != 1) {
    echoit("[Init] FORCE_SPORADIC active, so automatically enabled SLOW_DOWN_CHUNK_SCALING to speed up testcase reduction (SLOW_DOWN_CHUNK_SCALING_NR is set to " + std::to_string(cfg::SLOW_DOWN_CHUNK_SCALING_NR) + ")");
  }
  if (cfg::PAUSE_AFTER_EACH_OCCURRENCE == 1)
    echoit("[Init] PAUSE_AFTER_EACH_OCCURRENCE active, so reducer will pause after each occurrence of the issue");
  if (cfg::REDUCE_STARTUP_ISSUES == 1) {
    echoit("[Init] REDUCE_STARTUP_ISSUES active. Issue is assumed to be a startup issue");
    echoit("[Info] Note: REDUCE_STARTUP_ISSUES is normally used for debugging mariadbd/mysqld startup issues only");
  }
  if (cfg::ENABLE_QUERYTIMEOUT > 0)
    echoit("[Init] Querytimeout: " + std::to_string(cfg::QUERYTIMEOUT) + "s");
  if (cfg::FIREWORKS == 1) {
    echoit("[Init] FIREWORKS Mode active. Newly discovered bugs will be saved to " + cfg::NEW_BUGS_SAVE_DIR);
  } else if (cfg::SCAN_FOR_NEW_BUGS == 1) {
    echoit("[Init] SCAN_FOR_NEW_BUGS active. Newly discovered bugs will be saved to " + cfg::NEW_BUGS_SAVE_DIR);
  }
  if (cfg::USE_PQUERY == 0) {
    if (cfg::CLI_MODE == 0) {
      echoit("[Init] Using the mysql client for SQL replay. CLI_MODE: 0 (cat input.sql | mysql)");
    } else if (cfg::CLI_MODE == 1) {
      echoit("[Init] Using the mysql client for SQL replay. CLI_MODE: 1 (mysql --execute='SOURCE input.sql')");
      echoit("[Warning] Please note CLI_MODE=1 is currently not recommended for use, due to MySQL Bug #81782");
      echoit("[Warning] If your issue fails to reproduce, parse the input file: cat yourinputfile.sql | tr -d '\\0' > newinputfile.sql");
      echoit("[Warning] In summary, please consider using CLI_MODE=0 or CLI_MODE=2 instead of CLI_MODE=1");
    } else if (cfg::CLI_MODE == 2) {
      echoit("[Init] Using the mysql client for SQL replay. CLI_MODE: 2 (mysql < input.sql)");
    } else {
      std::cerr << "Error: CLI_MODE!=0,1,2: CLI_MODE=" << cfg::CLI_MODE << "\n"; std::exit(1);
    }
  } else {
    echoit("[Init] Using the pquery client for SQL replay");
    if (cfg::PQUERY_MULTI == 0) {
      if (cfg::PQUERY_REVERSE_NOSHUFFLE_OPT == 0) echoit("[Init] Using sequential (non-shuffled) single-thread replay");
      else                                         echoit("[Init] Using shuffled (random/non-sequential) single-thread replay");
    } else {
      if (cfg::PQUERY_REVERSE_NOSHUFFLE_OPT == 1) echoit("[Init] Using sequential (non-shuffled) multi-threaded replay");
      else                                         echoit("[Init] Using shuffled (random/non-sequential) multi-threaded replay");
    }
  }
  if (cfg::NR_OF_TRIAL_REPEATS > 1)
    echoit("[Init] Number of times each individual trial will be attempted: " + std::to_string(cfg::NR_OF_TRIAL_REPEATS) + "x");
  if (cfg::NR_OF_TRIAL_REPEATS > 50)
    echoit("[Init] Note: NR_OF_TRIAL_REPEATS is set larger than 50. This will take a long time.");
  if (cfg::NR_OF_TRIAL_REPEATS > 1 && cfg::SKIPSTAGEBELOW == 0) {
    echoit("[Init] NR_OF_TRIAL_REPEATS>1: setting SKIPSTAGEBELOW=1, ensuring repeated line-by-line reduction trials");
    cfg::SKIPSTAGEBELOW = 1;
  }
  if (!cfg::MYEXTRA.empty() || !cfg::SPECIAL_MYEXTRA_OPTIONS.empty())
    echoit("[Init] Passing the following additional options to mariadbd/mysqld: " + cfg::SPECIAL_MYEXTRA_OPTIONS + " " + cfg::MYEXTRA);
  if (cfg::REPLICATION == 1) {
    if (!cfg::MASTER_EXTRA.empty()) echoit("[Init] Passing the following master options to the master mariadbd/mysqld: " + cfg::MASTER_EXTRA);
    if (!cfg::SLAVE_EXTRA.empty())  echoit("[Init] Passing the following slave options to the slave mariadbd/mysqld: "   + cfg::SLAVE_EXTRA);
  }
  if (!cfg::MYINIT.empty()) echoit("[Init] Passing the following additional options to mariadbd/mysqld initialization: " + cfg::MYINIT);
  if (cfg::MODE >= 6 && cfg::MODE <= 9) {
    if (cfg::TS_TRXS_SETS == 1) echoit("[Init] ThreadSync: using last transaction set (accross threads) only");
    if (cfg::TS_TRXS_SETS > 1)  echoit("[Init] ThreadSync: using last " + std::to_string(cfg::TS_TRXS_SETS) + " transaction sets (accross threads) only");
    if (cfg::TS_TRXS_SETS == 0) echoit("[Init] ThreadSync: using complete input files (you may want to set TS_DS_TIMEOUT=10 [seconds] or less)");
    if (cfg::TS_VARIABILITY_SLEEP > 0) echoit("[Init] ThreadSync: will wait " + std::to_string(cfg::TS_VARIABILITY_SLEEP) + " seconds before each new transaction set is processed");
    echoit("[Init] ThreadSync: default DEBUG_SYNC timeout (TS_DS_TIMEOUT): " + std::to_string(cfg::TS_DS_TIMEOUT) + " seconds");
    if (cfg::TS_DBG_CLI_OUTPUT == 1) {
      echoit("[Init] ThreadSync: using debug (-vvv) mysql CLI output logging");
      echoit("[Warning] ThreadSync: ONLY use -vvv logging for debugging");
    }
  }
  if (cfg::MDG > 0) {
    echoit("[Init] MDG active, so automatically set USE_PQUERY=1: MariaDB Galera Cluster testcase reduction is currently supported with pquery only");
    if (cfg::MODE == 5 || cfg::MODE == 3)
      echoit("[Warning] MODE=" + std::to_string(cfg::MODE) + " is set, as well as MDG mode active. Combination not tested yet.");
    if (cfg::MODE == 4) {
      if (cfg::MDG_ISSUE_NODE == 0)
        echoit("[Info] All MDG nodes will be checked for the issue (MDG_ISSUE_NODE=0)");
      for (int i = 1; i <= cfg::NR_OF_NODES; ++i)
        echoit("[Info] Important: MDG_ISSUE_NODE is set to " + std::to_string(i) + ", so only MDG node " + std::to_string(i) + " will be checked for the presence of the issue");
    }
  }
  if (cfg::GRP_RPL > 0) {
    echoit("[Init] GRP_RPL active, so automatically set USE_PQUERY=1: Group Replication Cluster testcase reduction is currently supported only with pquery");
    if (cfg::MODE == 5 || cfg::MODE == 3)
      echoit("[Warning] MODE=" + std::to_string(cfg::MODE) + " is set, as well as Group Replication mode active. Combination not tested yet.");
    if (cfg::MODE == 4) {
      if (cfg::GRP_RPL_ISSUE_NODE == 0)
        echoit("[Info] All Group Replication nodes will be checked for the issue (GRP_RPL_ISSUE_NODE=0)");
      else
        echoit("[Info] Important: GRP_RPL_ISSUE_NODE is set to " + std::to_string(cfg::GRP_RPL_ISSUE_NODE) + ", so only Group Replication node " + std::to_string(cfg::GRP_RPL_ISSUE_NODE) + " will be checked");
    }
  }
  // Init template + first startup (parent reducer only)
  if (state::MULTI_REDUCER != 1) {
    state::MID.clear();
    if (util::file_readable(cfg::BASEDIR + "/scripts/mariadb-install-db")) state::MID = cfg::BASEDIR + "/scripts/mariadb-install-db";
    if (util::file_readable(cfg::BASEDIR + "/scripts/mysql_install_db"))    state::MID = cfg::BASEDIR + "/scripts/mysql_install_db";
    if (util::file_readable(cfg::BASEDIR + "/bin/mysql_install_db"))        state::MID = cfg::BASEDIR + "/bin/mysql_install_db";
    state::START_OPT = "--core-file";
    state::INIT_OPT  = "--no-defaults --initialize-insecure " + cfg::MYINIT;
    state::INIT_TOOL = state::BIN;
    state::VERSION_INFO   = util::sh_capture_trimmed("\"" + state::BIN + "\" --version | grep -E --binary-files=text -oe '[589]\\.[0-9]' | head -n1");
    state::VERSION_INFO_2 = util::sh_capture_trimmed("\"" + state::BIN + "\" --version | grep --binary-files=text -i 'MariaDB' | grep -oe '1[0-5]\\.[0-9][0-9]*' | head -n1");
    static const std::regex md_old(R"(^10\.[1-3]$)");
    static const std::regex md_new(R"(^1[0-5]\.[0-9][0-9]*)");
    if (std::regex_match(state::VERSION_INFO_2, md_old)) {
      state::VERSION_INFO = "5.1";
      state::INIT_TOOL = cfg::BASEDIR + "/scripts/mysql_install_db";
      state::INIT_OPT  = "--no-defaults --force";
      state::START_OPT = "--core";
    } else if (std::regex_search(state::VERSION_INFO_2, md_new)) {
      state::VERSION_INFO = "5.6";
      state::INIT_TOOL = cfg::BASEDIR + "/scripts/mariadb-install-db";
      state::INIT_OPT  = "--no-defaults --force --auth-root-authentication-method=normal " + cfg::MYINIT;
      state::START_OPT = "--core-file --core";
    } else if (state::VERSION_INFO == "5.1" || state::VERSION_INFO == "5.5" || state::VERSION_INFO == "5.6") {
      if (state::MID.empty()) {
        std::cerr << "Assert: Version was detected as " << state::VERSION_INFO << ", yet ./scripts/mysql_install_db nor ./bin/mysql_install_db is present!\n";
        std::exit(1);
      }
      state::INIT_TOOL = state::MID;
      state::INIT_OPT  = "--no-defaults --force " + cfg::MYINIT;
      state::START_OPT = "--core";
    } else if (state::VERSION_INFO != "5.7" && state::VERSION_INFO != "8.0") {
      std::cerr << "WARNING: mariadbd/mysqld (" << state::BIN << ") version detection failed.\n";
    }
    if (cfg::MDG != 1 && cfg::GRP_RPL != 1) {
      echoit("[Init] Setting up standard data directory working template (without using MYEXTRA options)");
      generate_run_scripts();
      diskspace(state::WORKD);
      util::sh(state::INIT_TOOL + " " + state::INIT_OPT + " --basedir=" + cfg::BASEDIR +
               " --datadir=" + state::WORKD + "/data " + state::MID_OPTIONS +
               " --user=" + state::MYUSER + " > " + state::WORKD + "/init.log 2>&1");
      if (!util::dir_exists(state::WORKD + "/data")) {
        echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [ERROR] data directory at " + state::WORKD + "/data does not exist... check " + state::WORKD + "/log/mysqld.out, " + state::WORKD + "/log/*.err and " + state::WORKD + "/init.log");
        std::cerr << "Terminating now.\n"; std::exit(1);
      } else {
        if (!util::dir_exists(state::WORKD)) abort_reducer();
        fs::rename(state::WORKD + "/data", state::WORKD + "/data.init");
        util::mkdir_p(state::WORKD + "/data");
        util::sh("cp -a " + state::WORKD + "/data.init/* " + state::WORKD + "/data/");
        if (cfg::REPLICATION == 1) {
          util::mkdir_p(state::WORKD + "/data_slave");
          util::sh("cp -a " + state::WORKD + "/data.init/* " + state::WORKD + "/data_slave/");
        }
        util::sh("chmod -R 777 " + state::WORKD);
      }
      std::string du_init = util::sh_capture_trimmed("du -sc " + state::WORKD + "/data.init | grep -v 'total' | awk '{print $1}'");
      if (du_init == "0") {
        echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [ERROR] data directory at " + state::WORKD + "/data.init is 0 bytes. The volume likely ran out of space");
        std::cerr << "Terminating now.\n"; std::exit(1);
      }
      if (cfg::REPLICATION != 1) {
        echoit("[Init] Attempting first mariadbd/mysqld startup with all MYEXTRA options passed");
      } else {
        echoit("[Init] Attempting first mariadbd/mysqld startups (master & slave) with all MYEXTRA* options passed");
      }
      state::FIRST_MYSQLD_START_FLAG = 1;
      if (cfg::MODE != 1 && cfg::MODE != 6) start_mysqld_main(); else start_valgrind_mysqld_main();
      std::string admin = cfg::BASEDIR + "/bin/mariadb-admin";
      if (!util::file_readable(admin)) admin = cfg::BASEDIR + "/bin/mysqladmin";
      int rc = util::sh(admin + " -uroot -S" + state::WORKD + "/socket.sock ping > /dev/null 2>&1");
      if (rc != 0) {
        if (cfg::REDUCE_STARTUP_ISSUES == 1) {
          echoit("[Init] [NOTE] Failed to cleanly start mariadbd/mysqld server. Continuing because REDUCE_STARTUP_ISSUES=1.");
        } else {
          echoit("[Init] [ERROR] Failed to start the mariadbd/mysqld server, check " + state::WORKD + "/log/mysqld.out, " + state::WORKD + "/log/*.err, " + state::WORKD + "/init.log");
          echoit("[Init] [INFO] If you want to debug a mariadbd/mysqld startup issue, set REDUCE_STARTUP_ISSUES=1 and restart reducer.sh");
          std::cerr << "Terminating now.\n"; std::exit(1);
        }
      } else {
        echoit("[Init] First mariadbd/mysqld startup with all MYEXTRA options passed to mariadbd/mysqld successful");
      }
      if (cfg::LOAD_TIMEZONE_DATA > 0) {
        echoit("[Init] Loading timezone data into mysql database");
        diskspace(state::WORKD);
        util::sh(cfg::BASEDIR + "/bin/mysql_tzinfo_to_sql /usr/share/zoneinfo > " + state::WORKD + "/timezone.init 2> " + state::WORKD + "/timezone.err");
        util::sh("grep -E --binary-files=text -v \"Riyadh8[789]'|zoneinfo/iso3166.tab|zoneinfo/zone.tab\" " + state::WORKD + "/timezone.err > " + state::WORKD + "/timezone.err.tmp");
        auto warn_lines = util::split(util::sh_capture(
          "cat " + state::WORKD + "/timezone.err.tmp | sed 's/ /=DUMMY=/g'"), '\n');
        for (const auto& w : warn_lines) {
          if (w.empty()) continue;
          echoit("[Warning from mysql_tzinfo_to_sql] " + util::replace_all(w, "=DUMMY=", " "));
        }
        echoit("[Info] If you see a [GLIBC] crash above, change reducer to use a non-Valgrind-instrumented build of mysql_tzinfo_to_sql");
        util::sh(cfg::BASEDIR + "/bin/mysql -uroot -S" + state::WORKD + "/socket.sock --force mysql < " + state::WORKD + "/timezone.init");
      }
      stop_mysqld_or_mdg();
    } else if (cfg::MDG == 1) {
      echoit("[Init] Setting up standard MDG data directory working template (without using MYEXTRA options)");
      diskspace(state::WORKD);
      for (int i = 1; i <= cfg::NR_OF_NODES; ++i) {
        std::string node = state::WORKD + "/node" + std::to_string(i);
        util::sh(state::INIT_TOOL + " " + state::INIT_OPT + " --basedir=" + cfg::BASEDIR +
                 " " + state::MID_OPTIONS + " --user=" + state::MYUSER + " --datadir=" + node +
                 " > " + state::WORKD + "/startup_node" + std::to_string(i) + "_error.log 2>&1");
        util::mkdir_p(state::WORKD + "/node" + std::to_string(i) + ".init");
        util::sh("cp -a " + state::WORKD + "/node" + std::to_string(i) + "/* " +
                 state::WORKD + "/node" + std::to_string(i) + ".init/");
      }
    } else if (cfg::GRP_RPL == 1) {
      echoit("[Init] Setting up standard Group Replication data directory working template (without using MYEXTRA options)");
      std::string bin_to_use = cfg::BASEDIR + "/bin/mariadbd";
      if (!util::file_readable(bin_to_use)) bin_to_use = cfg::BASEDIR + "/bin/mysqld";
      std::string mid_cmd = bin_to_use + " --no-defaults --initialize-insecure " + cfg::MYINIT + " --basedir=" + cfg::BASEDIR;
      state::node1 = state::WORKD + "/node1";
      state::node2 = state::WORKD + "/node2";
      state::node3 = state::WORKD + "/node3";
      diskspace(state::WORKD);
      if (util::sh(mid_cmd + " --datadir=" + state::node1 + " > " + state::WORKD + "/startup_node1_error.log 2>&1") != 0) std::exit(1);
      if (util::sh(mid_cmd + " --datadir=" + state::node2 + " > " + state::WORKD + "/startup_node2_error.log 2>&1") != 0) std::exit(1);
      if (util::sh(mid_cmd + " --datadir=" + state::node3 + " > " + state::WORKD + "/startup_node3_error.log 2>&1") != 0) std::exit(1);
      util::mkdir_p(state::WORKD + "/node1.init");
      util::mkdir_p(state::WORKD + "/node2.init");
      util::mkdir_p(state::WORKD + "/node3.init");
      util::sh("cp -a " + state::WORKD + "/node1/* " + state::WORKD + "/node1.init/");
      util::sh("cp -a " + state::WORKD + "/node2/* " + state::WORKD + "/node2.init/");
      util::sh("cp -a " + state::WORKD + "/node3/* " + state::WORKD + "/node3.init/");
    }
    state::FIRST_MYSQLD_START_FLAG = 0;
  } else {
    if (cfg::MDG == 1) {
      echoit("[Init] This is a subreducer process; using initialization data template from the main process (" + state::WORKD + "/../../node*.init)");
    } else {
      echoit("[Init] This is a subreducer process; using initialization data template from the main process (" + state::WORKD + "/../../data.init)");
    }
  }
}
// generate_run_scripts — mirror reducer.sh:2305..2461
static void generate_run_scripts() {
  if (cfg::FIREWORKS == 1) return;

  std::string EPOCH_SOCKET, EPOCH_ERROR_LOG;
  if (cfg::MDG == 1) {
    EPOCH_SOCKET    = "/dev/shm/" + state::EPOCH + "/node" + std::to_string(cfg::GALERA_NODE) + "/node" + std::to_string(cfg::GALERA_NODE) + "_socket.sock";
    EPOCH_ERROR_LOG = "/dev/shm/" + state::EPOCH + "/node" + std::to_string(cfg::GALERA_NODE) + "/node" + std::to_string(cfg::GALERA_NODE) + ".err";
  } else {
    EPOCH_SOCKET    = "/dev/shm/" + state::EPOCH + "/socket.sock";
    EPOCH_ERROR_LOG = "/dev/shm/" + state::EPOCH + "/log/master.err";
  }
  diskspace(fs::path(state::WORK_BASEDIR_FILE).parent_path().string());

  // _mybase — mirror bash `sed 's|^[ \t]*||;s|[ \t]*$||;s|/$||'` cleanup
  // (strip leading/trailing ws + any trailing /) on the BASEDIR line. The
  // bash version applies the sed to each of the three echos but only BASEDIR
  // is non-static and contains a path; the other two are literal strings
  // unaffected by the cleanup. We mirror the trim+trailing-slash strip on the
  // BASEDIR line only.
  {
    std::string bd = util::trim(cfg::BASEDIR);
    while (!bd.empty() && bd.back() == '/') bd.pop_back();
    std::ostringstream os;
    os << "BASEDIR=" << bd << "\n";
    os << "SOURCE_DIR=$BASEDIR  # Only required to be set if make_binary_distrubtion script was NOT used to build MySQL\n";
    os << "JEMALLOC=~/libjemalloc.so.1  # Only required for Percona Server with TokuDB. Can be completely ignored otherwise.\n";
    util::write_file(state::WORK_BASEDIR_FILE, os.str());
  }
  // _init
  {
    std::ostringstream os;
    os << "#!/bin/bash\n";
    os << "SCRIPT_DIR=$(cd $(dirname $0) && pwd)\n";
    os << ". $SCRIPT_DIR/" << state::EPOCH << "_mybase\n";
    os << "echo \"Attempting to prepare mariadbd/mysqld environment at /dev/shm/" << state::EPOCH << "...\"\n";
    os << "rm -Rf /dev/shm/" << state::EPOCH << "\n";
    if (cfg::MDG == 0) {
      os << "mkdir -p /dev/shm/" << state::EPOCH << "/tmp /dev/shm/" << state::EPOCH << "/log\n";
    }
    os << "BIN=`find -L ${BASEDIR} -maxdepth 2 -name mariadbd -type f -o -name mysqld -type f -o -name mysqld-debug -type f -o -name mysqld -type l -o -name mysqld-debug -type l | head -1`\n";
    os << "if [ -n \"$BIN\" ]; then\n";
    os << "  if [ \"$BIN\" != \"${BASEDIR}/bin/mysqld\" -a \"$BIN\" != \"${BASEDIR}/bin/mysqld-debug\" ];then\n";
    os << "    if [ ! -h ${BASEDIR}/bin/mysqld -o ! -f ${BASEDIR}/bin/mysqld ]; then mkdir -p ${BASEDIR}/bin; ln -s $BIN ${BASEDIR}/bin/mysqld; fi\n";
    os << "    if [ ! -h ${BASEDIR}/bin/mysql -o ! -f ${BASEDIR}/bin/mysql ]; then ln -s ${BASEDIR}/client/mysql ${BASEDIR}/bin/mysql ; fi\n";
    os << "    if [ ! -h ${BASEDIR}/share -o ! -f ${BASEDIR}/share ]; then ln -s ${SOURCE_DIR}/scripts ${BASEDIR}/share ; fi\n";
    os << "    if [ ! -h ${BASEDIR}/share/errmsg.sys -o ! -f ${BASEDIR}/share/errmsg.sys ]; then ln -s ${BASEDIR}/sql/share/english/errmsg.sys ${BASEDIR}/share/errmsg.sys ; fi;\n  fi\nelse\n";
    os << "  echo \"Assert! mysqld binary '$BIN' could not be read\";exit 1;\nfi\n";
    os << "MID=`find ${BASEDIR} -maxdepth 2 -name mariadb-install-db -o -name mysql_install_db | head -n1`\n";
    os << "VERSION=\"`$BIN --version | grep -E --binary-files=text -oe '[589]\\.[15670]' | head -n1`\"\n";
    os << "VERSION2=\"`$BIN --version | grep --binary-files=text -i 'MariaDB' | grep -oe '1[0-5]\\.[0-9][0-9]*' | head -n1`\"\n";
    os << "if [ \"$VERSION\" == \"5.7\" -o \"$VERSION\" == \"8.0\" ]; then MID_OPTIONS='--no-defaults --initialize-insecure " << cfg::MYINIT
       << "'; elif [ \"$VERSION\" == \"5.6\" ]; then MID_OPTIONS='--no-defaults --force " << cfg::MYINIT
       << "'; elif [ \"${VERSION}\" == \"5.5\" ]; then MID_OPTIONS='--force " << cfg::MYINIT
       << "';elif [ \"${VERSION2}\" == \"10.1\" -o \"${VERSION2}\" == \"10.2\" -o \"${VERSION2}\" == \"10.3\" ]; then MID_OPTIONS='--no-defaults --force " << cfg::MYINIT
       << "'; elif [ \"${VERSION2}\" != \"\" ]; then MID_OPTIONS='--no-defaults --force --auth-root-authentication-method=normal " << cfg::MYINIT
       << "'; else MID_OPTIONS='" << cfg::MYINIT << "'; fi\n";
    if (cfg::MDG == 1) {
      for (int i = 1; i <= cfg::NR_OF_NODES; ++i) {
        std::string n = std::to_string(i);
        util::mkdir_p("/dev/shm/" + state::EPOCH + "/tmp" + n);
        os << "mkdir -p /dev/shm/" << state::EPOCH << "/tmp" << n << "\n";
        os << "$MID ${MID_OPTIONS} --basedir=${BASEDIR} --datadir=/dev/shm/" << state::EPOCH << "/node" << n << "\n";
      }
    } else {
      os << "if [ \"$VERSION\" == \"5.7\" -o \"$VERSION\" == \"8.0\" ]; then $BIN ${MID_OPTIONS} --basedir=${BASEDIR} --datadir=/dev/shm/" << state::EPOCH
         << "/data; else $MID ${MID_OPTIONS} --basedir=${BASEDIR} --datadir=/dev/shm/" << state::EPOCH << "/data; fi\n";
    }
    util::write_file(state::WORK_INIT, os.str());
  }

  // _run
  if (cfg::MODE >= 6 && cfg::MODE <= 9) {
    echoit("[Not implemented yet] MODE6 or higher does not auto-generate a " + state::WORK_RUN + " file yet");
    std::ostringstream os;
    os << "Not implemented yet: MODE6 or higher does not auto-generate a " << state::WORK_RUN << " file yet\n";
    os << "#" << cfg::BASEDIR << "/bin/mysql -uroot -S" << EPOCH_SOCKET << " < INPUT_FILE_GOES_HERE (like " << state::WORKO << ")\n";
    util::write_file(state::WORK_RUN, os.str());
  } else {
    std::ostringstream os;
    os << "SCRIPT_DIR=$(cd $(dirname $0) && pwd)\n";
    os << ". $SCRIPT_DIR/" << state::EPOCH << "_mybase\n";
    os << "echo \"Executing testcase ./" << state::EPOCH << ".sql against mariadbd/mysqld with socket " << EPOCH_SOCKET << " using the mysql CLI client...\"\n";
    if (!util::dir_exists(state::WORKD)) abort_reducer();
    switch (cfg::CLI_MODE) {
      case 0: os << "cat ./" << state::EPOCH << ".sql | ${BASEDIR}/bin/mysql -uroot -S" << EPOCH_SOCKET << " --binary-mode --force test\n"; break;
      case 1: os << "${BASEDIR}/bin/mysql -uroot -S" << EPOCH_SOCKET << " --execute=\"SOURCE ./" << state::EPOCH << ".sql;\" --force test\n"; break;
      case 2: os << "${BASEDIR}/bin/mysql -uroot -S" << EPOCH_SOCKET << " --binary-mode --force test < ./" << state::EPOCH << ".sql\n"; break;
      default:
        echoit("Assert: default clause in CLI_MODE switchcase hit (in generate_run_scripts). CLI_MODE=" + std::to_string(cfg::CLI_MODE));
        std::exit(1);
    }
    util::write_file(state::WORK_RUN, os.str());
  }
  util::sh("chmod +x \"" + state::WORK_RUN + "\"");

  // _run_pquery
  if (cfg::USE_PQUERY == 1) {
    util::sh("cp \"" + cfg::PQUERY_LOC + "\" \"" + state::WORK_PQUERY_BIN + "\"");
    std::ostringstream os;
    os << "echo \"Executing testcase ./" << state::EPOCH << ".sql against mariadbd/mysqld with socket " << EPOCH_SOCKET << " using pquery...\"\n";
    os << "SCRIPT_DIR=$(cd $(dirname $0) && pwd)\n";
    os << ". $SCRIPT_DIR/" << state::EPOCH << "_mybase\n";
    os << "export LD_LIBRARY_PATH=${BASEDIR}/lib\n";
    std::string pq_short = cfg::PQUERY_LOC;
    auto pos = pq_short.find_last_of('/');
    pq_short = "./" + state::EPOCH + "_" + ((pos != std::string::npos) ? pq_short.substr(pos + 1) : pq_short);
    std::string pq_shuffle;
    if (cfg::PQUERY_MULTI == 0) {
      if (cfg::PQUERY_REVERSE_NOSHUFFLE_OPT == 0) {
        pq_shuffle = "--no-shuffle";
      } else {
        os << "SHUFFLE_OVERRUN_PREVENTION_MAX_LINES=$[ $[ $(wc -l ./" << state::EPOCH << ".sql | awk '{print $1}') * 13 / 10 ] + 100 ]\n";
        pq_shuffle = "--queries-per-thread=${SHUFFLE_OVERRUN_PREVENTION_MAX_LINES}";
      }
      os << pq_short << " --database=test --infile=./" << state::EPOCH << ".sql " << pq_shuffle
         << " --threads=1 --user=root --socket=" << EPOCH_SOCKET
         << " --logdir=" << state::WORKD << " --log-all-queries --log-failed-queries "
         << cfg::PQUERY_EXTRA_OPTIONS << "\n";
    } else {
      if (cfg::PQUERY_REVERSE_NOSHUFFLE_OPT == 1) {
        pq_shuffle = "--no-shuffle";
      } else {
        os << "SHUFFLE_OVERRUN_PREVENTION_MAX_LINES=$[ $[ $(wc -l ./" << state::EPOCH << ".sql | awk '{print $1}') * 13 / 10 ] + 100 ]\n";
        pq_shuffle = "--queries-per-thread=${SHUFFLE_OVERRUN_PREVENTION_MAX_LINES}";
      }
      os << pq_short << " --database=test --infile=./" << state::EPOCH << ".sql " << pq_shuffle
         << " --threads=" << cfg::PQUERY_MULTI_CLIENT_THREADS
         << " --queries=" << cfg::PQUERY_MULTI_QUERIES
         << " --user=root --socket=" << EPOCH_SOCKET
         << " --logdir=" << state::WORKD << " --log-all-queries --log-failed-queries "
         << cfg::PQUERY_EXTRA_OPTIONS << "\n";
    }
    util::write_file(state::WORK_RUN_PQUERY, os.str());
    util::sh("chmod +x \"" + state::WORK_RUN_PQUERY + "\"");
  }

  // _gdb
  std::string bin_short = "bin/mariadbd";
  if (!util::file_readable(cfg::BASEDIR + "/bin/mariadbd")) bin_short = "bin/mysqld";
  {
    std::ostringstream os;
    os << "SCRIPT_DIR=$(cd $(dirname $0) && pwd)\n";
    os << ". $SCRIPT_DIR/" << state::EPOCH << "_mybase\n";
    if (cfg::MDG == 1) {
      os << "gdb -iex 'set debuginfod enabled off' ${BASEDIR}/" << bin_short << " $(ls --color=never /dev/shm/" << state::EPOCH << "/node" << cfg::GALERA_NODE << "/core*)\n";
    } else {
      os << "gdb -iex 'set debuginfod enabled off' ${BASEDIR}/" << bin_short << " $(ls --color=never /dev/shm/" << state::EPOCH << "/data*/core*)\n";
    }
    util::write_file(state::WORK_GDB, os.str());
  }

  // _parse_core
  {
    std::ostringstream os;
    os << "SCRIPT_DIR=$(cd $(dirname $0) && pwd)\n";
    os << ". $SCRIPT_DIR/" << state::EPOCH << "_mybase\n";
    if (cfg::MDG == 1) {
      os << "gdb -iex 'set debuginfod enabled off' ${BASEDIR}/" << bin_short << " $(ls --color=never /dev/shm/" << state::EPOCH << "/node" << cfg::GALERA_NODE << "/core*) >/dev/null 2>&1 <<EOF\n";
    } else {
      os << "gdb -iex 'set debuginfod enabled off' ${BASEDIR}/" << bin_short << " $(ls --color=never /dev/shm/" << state::EPOCH << "/data/core*) >/dev/null 2>&1 <<EOF\n";
    }
    os << "  set auto-load safe-path /\n";
    os << "  set libthread-db-search-path /usr/lib/\n";
    os << "  set trace-commands on\n";
    os << "  set pagination off\n";
    os << "  set print pretty on\n";
    os << "  set print array on\n";
    os << "  set print array-indexes on\n";
    os << "  set print elements 4096\n";
    os << "  set print frame-arguments all\n";
    os << "  set logging file " << state::EPOCH << "_FULL.gdb\n";
    os << "  set logging enabled on\n";
    os << "  thread apply all bt full\n";
    os << "  set logging enabled off\n";
    os << "  set logging file " << state::EPOCH << "_STD.gdb\n";
    os << "  set logging enabled on\n";
    os << "  thread apply all bt\n";
    os << "  set logging enabled off\n";
    os << "  quit\n";
    os << "EOF\n";
    util::write_file(state::WORK_PARSE_CORE, os.str());
  }

  // _stop
  {
    std::ostringstream os;
    os << "SCRIPT_DIR=$(cd $(dirname $0) && pwd)\n";
    os << ". $SCRIPT_DIR/" << state::EPOCH << "_mybase\n";
    os << "echo \"Attempting to shutdown mariadbd/mysqld with socket " << EPOCH_SOCKET << "...\"\n";
    os << "MYADMIN=`find -L ${BASEDIR} -maxdepth 2 -name mariadb-admin -type f -o -name mysqladmin -type f -o -name mysqladmin -type l`\n";
    os << "$MYADMIN -uroot -S" << EPOCH_SOCKET << " shutdown\n";
    util::write_file(state::WORK_STOP, os.str());
  }

  // _cl
  {
    std::ostringstream os;
    os << "SCRIPT_DIR=$(cd $(dirname $0) && pwd)\n";
    os << ". $SCRIPT_DIR/" << state::EPOCH << "_mybase\n";
    os << "echo \"Connecting to mariadbd/mysqld with socket -S" << EPOCH_SOCKET << " test using the mysql CLI client...\"\n";
    if (cfg::MDG == 1) {
      os << "${BASEDIR}/bin/mysql -uroot -S" << EPOCH_SOCKET << " $(ls --color=never -d /dev/shm/" << state::EPOCH << "/node1/test 2>/dev/null | grep -o 'test')\n";
    } else {
      os << "${BASEDIR}/bin/mysql -uroot -S" << EPOCH_SOCKET << " $(ls --color=never -d /dev/shm/" << state::EPOCH << "/data/test 2>/dev/null | grep -o 'test')\n";
    }
    util::write_file(state::WORK_CL, os.str());
  }

  // _how_to_use.txt
  {
    std::ostringstream os;
    os << "To replay, the attached tarball (" << state::EPOCH << "_bug_bundle.tar.gz) gives the testcase as an exact match of our system, including some handy utilities\n\n";
    os << "$ vi " << state::EPOCH << "_mybase         # STEP1: Update the base path in this file (usually the only change required!). If you use a non-binary distribution, please update SOURCE_DIR location also\n";
    os << "$ ./" << state::EPOCH << "_init            # STEP2: Initializes the data dir\n";
    if (cfg::MODE == 1 || cfg::MODE == 6) {
      os << "$ ./" << state::EPOCH << "_start_valgrind  # STEP3: Starts mariadbd/mysqld under Valgrind (make sure to use a Valgrind instrumented build)\n";
    } else {
      os << "$ ./" << state::EPOCH << "_start           # STEP3: Starts mariadbd/mysqld\n";
    }
    os << "$ ./" << state::EPOCH << "_cl              # STEP4: To check mariadbd/mysqld is up (repeat if necessary)\n";
    if (cfg::USE_PQUERY == 1) {
      os << "$ ./" << state::EPOCH << "_run_pquery      # STEP5: Run the testcase with the pquery binary\n";
      os << "$ ./" << state::EPOCH << "_run             # OPTIONAL: Run the testcase with the mysql CLI\n";
      if (cfg::MODE == 1 || cfg::MODE == 6) {
        os << "$ ./" << state::EPOCH << "_stop            # STEP6: Stop mariadbd/mysqld\n";
      }
    } else {
      os << "$ ./" << state::EPOCH << "_run             # STEP5: Run the testcase with the mysql CLI\n";
      if (cfg::MODE == 1 || cfg::MODE == 6) {
        os << "$ ./" << state::EPOCH << "_stop            # STEP6: Stop mariadbd/mysqld\n";
      }
    }
    if (cfg::MODE == 1 || cfg::MODE == 6) {
      os << "$ vi " << EPOCH_ERROR_LOG << "  # STEP7: Verify the error log\n";
    } else {
      os << "$ vi " << EPOCH_ERROR_LOG << "  # STEP6: Verify the error log\n";
    }
    os << "$ ./" << state::EPOCH << "_gdb             # OPTIONAL: Brings you to a gdb prompt with gdb attached to the used mariadbd/mysqld and attached to the generated core\n";
    os << "$ ./" << state::EPOCH << "_parse_core      # OPTIONAL: Creates " << state::EPOCH << "_STD.gdb and " << state::EPOCH << "_FULL.gdb; standard and full variables gdb stack traces\n";
    util::write_file(state::WORK_HOW_TO_USE, os.str());
  }
  util::sh("chmod +x \"" + state::WORK_CL + "\" \"" + state::WORK_STOP + "\" \"" + state::WORK_GDB + "\" \"" + state::WORK_PARSE_CORE + "\" \"" + state::WORK_INIT + "\"");
}
// init_mysql_dir — mirror reducer.sh:2462..2500
static void init_mysql_dir() {
  diskspace(state::WORKD);
  if (!util::dir_exists(state::WORKD)) { abort_reducer(); }
  util::sh("touch " + state::WORKD);
  if (cfg::MDG == 1) {
    for (int i = 1; i <= cfg::NR_OF_NODES; ++i) {
      const std::string n = std::to_string(i);
      util::sh("sudo rm -Rf " + state::WORKD + "/node" + n);
      if (state::MULTI_REDUCER != 1) {
        util::sh("cp -a " + state::WORKD + "/node" + n + ".init " + state::WORKD + "/node" + n);
      } else {
        util::mkdir_p(state::WORKD + "/node" + n);
        util::sh("cp -a " + state::WORKD + "/../../node" + n + ".init/* " + state::WORKD + "/node" + n + "/");
      }
    }
  } else if (cfg::GRP_RPL == 1) {
    util::sh("sudo rm -Rf " + state::WORKD + "/node1 " + state::WORKD + "/node2 " + state::WORKD + "/node3");
    util::sh("cp -a \"" + state::node1 + ".init\" \"" + state::node1 + "\"");
    util::sh("cp -a \"" + state::node2 + ".init\" \"" + state::node2 + "\"");
    util::sh("cp -a \"" + state::node3 + ".init\" \"" + state::node3 + "\"");
  } else {
    util::sh("rm -Rf " + state::WORKD + "/data/* " + state::WORKD + "/data_slave/* " +
                       state::WORKD + "/tmp/* " + state::WORKD + "/tmp_slave/*");
    util::sh("rm -Rf " + state::WORKD + "/data/.rocksdb");
    if (state::MULTI_REDUCER != 1) {
      util::sh("cp -a " + state::WORKD + "/data.init/* " + state::WORKD + "/data/");
      if (cfg::REPLICATION == 1)
        util::sh("cp -a " + state::WORKD + "/data.init/* " + state::WORKD + "/data_slave/");
    } else {
      util::sh("cp -a " + state::WORKD + "/../../data.init/* " + state::WORKD + "/data/");
      if (cfg::REPLICATION == 1)
        util::sh("cp -a " + state::WORKD + "/../../data.init/* " + state::WORKD + "/data_slave/");
    }
  }
  if (cfg::REDUCE_GLIBC_OR_SS_CRASHES > 0) {
    util::write_file("/tmp/reducer_typescript" + state::TYPESCRIPT_UNIQUE_FILESUFFIX + ".log", "");
  }
}
// Forward decls for the three functions defined below
static int  start_mysqld_or_valgrind_or_mdg_impl();
static void start_mdg_main_impl();
static void gr_start_main_impl();
static int  start_mysqld_main_impl();
static void start_valgrind_mysqld_main_impl();

// Wrappers (used in forward decls / callers)
static void start_mysqld_or_valgrind_or_mdg() { (void)start_mysqld_or_valgrind_or_mdg_impl(); }
static void start_mdg_main()                  { start_mdg_main_impl(); }
static void gr_start_main()                   { gr_start_main_impl(); }
static void start_mysqld_main()               { (void)start_mysqld_main_impl(); }
static void start_valgrind_mysqld_main()      { start_valgrind_mysqld_main_impl(); }

// start_mysqld_main — mirror reducer.sh:2874..3013
static int start_mysqld_main_impl() {
  if (!util::dir_exists(state::WORKD)) abort_reducer();
  util::sh("touch \"" + state::WORKD + "\"");
  // 0-byte data dir check
  std::string du = util::sh_capture_trimmed(
    "du -sc " + state::WORKD + "/data | grep -v 'total' | awk '{print $1}'");
  if (du == "0") {
    echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [ERROR] data directory at " + state::WORKD + "/data is 0 bytes. The volume likely ran out of space");
    std::cerr << "Terminating now.\n"; std::exit(1);
  }
  diskspace(fs::path(state::WORK_START).parent_path().string());

  std::ostringstream ws;
  ws << "SCRIPT_DIR=$(cd $(dirname $0) && pwd)\n";
  ws << ". $SCRIPT_DIR/" << state::EPOCH << "_mybase\n";
  ws << "echo \"Attempting to start mariadbd/mysqld (socket /dev/shm/" << state::EPOCH << "/socket.sock)...\"\n";
  ws << state::JE1 << "\n" << state::JE2 << "\n" << state::JE3 << "\n" << state::JE4 << "\n";
  ws << "BIN=`find -L ${BASEDIR} -maxdepth 2 -name mariadbd -type f -o -name mysqld -type f -o -name mysqld-debug -type f -o -name mysqld -type l -o -name mysqld-debug -type l | head -1`;if [ -z \"$BIN\" ]; then echo \"Assert! mariadbd/mysqld binary '$BIN' could not be read\";exit 1;fi\n";

  std::string scheduler;
  if (cfg::ENABLE_QUERYTIMEOUT > 0) scheduler = "--event-scheduler=ON ";
  std::string core_nts;
  if (cfg::USE_NEW_TEXT_STRING > 0) core_nts = "--core-file --core";

  if (cfg::RR_TRACING == 1) {
    setenv("_RR_TRACE_DIR", (state::WORKD + "/rr").c_str(), 1);
    util::mkdir_p(state::WORKD + "/rr");
  }

  auto append_squashed = [](std::ostream& os, const std::string& s) {
    // Squash repeated spaces (mirrors `sed 's/ \+/ /g'`).
    std::string out = util::squeeze_spaces(s);
    os << out;
  };

  auto launch_bg = [](const std::string& cmd, const std::string& stdout_redir) -> std::string {
    // Launch the command in background, return its PID.
    std::string full = "(" + cmd + " > \"" + stdout_redir + "\" 2>&1 & echo $!)";
    return util::sh_capture_trimmed(full);
  };

  if (cfg::MODE >= 6 && state::TS_DEBUG_SYNC_REQUIRED_FLAG == 1) {
    if (cfg::REPLICATION == 1) {
      echoit("MODE=6, TS_DEBUG_SYNC_REQUIRED_FLAG=1. This combination does not support replication mode yet (REPLICATION=1).");
      std::exit(1);
    }
    init_empty_port();
    state::MYPORT = state::NEWPORT; state::NEWPORT = 0;
    std::ostringstream cmdline;
    cmdline << state::RR_OPTIONS << " " << cfg::TIMEOUT_COMMAND << " $BIN --no-defaults --basedir=${BASEDIR} --datadir="
            << state::WORKD << "/data --tmpdir=" << state::WORKD << "/tmp --port=" << state::MYPORT
            << " --pid-file=" << state::WORKD << "/pid.pid --socket=" << state::WORKD << "/socket.sock"
            << " --loose-debug-sync-timeout=" << cfg::TS_DS_TIMEOUT << " "
            << cfg::SPECIAL_MYEXTRA_OPTIONS << " " << cfg::MYEXTRA
            << " --log-error=" << state::WORKD << "/log/master.err " << scheduler
            << " > " << state::WORKD << "/log/mysqld.out 2>&1 &\n";
    append_squashed(ws, cmdline.str());
    std::ostringstream actual;
    actual << state::RR_OPTIONS << " " << cfg::TIMEOUT_COMMAND << " " << state::BIN
           << " --no-defaults --basedir=" << cfg::BASEDIR << " --datadir=" << state::WORKD << "/data"
           << " --tmpdir=" << state::WORKD << "/tmp --port=" << state::MYPORT
           << " --pid-file=" << state::WORKD << "/pid.pid --socket=" << state::WORKD << "/socket.sock"
           << " --loose-debug-sync-timeout=" << cfg::TS_DS_TIMEOUT << " --user=" << state::MYUSER << " "
           << cfg::SPECIAL_MYEXTRA_OPTIONS << " " << cfg::MYEXTRA
           << " --log-error=" << state::WORKD << "/log/master.err " << scheduler << " " << core_nts;
    state::MYSQLD_START_TIME = std::to_string(std::time(nullptr));
    state::PIDV = launch_bg(actual.str(), state::WORKD + "/log/mysqld.out");
  } else if (cfg::REPLICATION == 1) {
    // Master
    init_empty_port();
    state::MYPORT = state::NEWPORT; state::NEWPORT = 0;
    {
      std::ostringstream cmdline;
      cmdline << state::RR_OPTIONS << " " << cfg::TIMEOUT_COMMAND << " $BIN --no-defaults --basedir=${BASEDIR} --datadir="
              << state::WORKD << "/data --tmpdir=" << state::WORKD << "/tmp --port=" << state::MYPORT
              << " --pid-file=" << state::WORKD << "/pid.pid --socket=" << state::WORKD << "/socket.sock "
              << cfg::SPECIAL_MYEXTRA_OPTIONS << " " << cfg::MYEXTRA << " " << cfg::REPL_EXTRA << " " << cfg::MASTER_EXTRA
              << " --log-error=" << state::WORKD << "/log/master.err " << scheduler
              << " > " << state::WORKD << "/log/mysqld.out 2>&1 &\n";
      append_squashed(ws, cmdline.str());
    }
    {
      std::ostringstream actual;
      actual << state::RR_OPTIONS << " " << cfg::TIMEOUT_COMMAND << " " << state::BIN
             << " --no-defaults --basedir=" << cfg::BASEDIR << " --datadir=" << state::WORKD << "/data"
             << " --tmpdir=" << state::WORKD << "/tmp --port=" << state::MYPORT
             << " --pid-file=" << state::WORKD << "/pid.pid --socket=" << state::WORKD << "/socket.sock"
             << " --user=" << state::MYUSER << " "
             << cfg::SPECIAL_MYEXTRA_OPTIONS << " " << cfg::MYEXTRA << " " << cfg::REPL_EXTRA << " " << cfg::MASTER_EXTRA
             << " --log-error=" << state::WORKD << "/log/master.err " << scheduler << " " << core_nts;
      state::MYSQLD_START_TIME = std::to_string(std::time(nullptr));
      state::PIDV = launch_bg(actual.str(), state::WORKD + "/log/mysqld.out");
    }
    // Slave
    init_empty_port();
    state::MYPORT_SLAVE = state::NEWPORT; state::NEWPORT = 0;
    {
      std::ostringstream cmdline;
      cmdline << state::RR_OPTIONS << " " << cfg::TIMEOUT_COMMAND << " $BIN --no-defaults --basedir=${BASEDIR} --datadir="
              << state::WORKD << "/data_slave --tmpdir=" << state::WORKD << "/tmp_slave --port=" << state::MYPORT_SLAVE
              << " --pid-file=" << state::WORKD << "/slave_pid.pid --socket=" << state::WORKD << "/slave_socket.sock "
              << cfg::SPECIAL_MYEXTRA_OPTIONS << " " << cfg::MYEXTRA << " " << cfg::REPL_EXTRA << " " << cfg::SLAVE_EXTRA
              << " --log-error=" << state::WORKD << "/log/slave.err " << scheduler
              << " > " << state::WORKD << "/log/mysqld_slave.out 2>&1 &\n";
      append_squashed(ws, cmdline.str());
    }
    {
      std::ostringstream actual;
      actual << state::RR_OPTIONS << " " << cfg::TIMEOUT_COMMAND << " " << state::BIN
             << " --no-defaults --basedir=" << cfg::BASEDIR << " --datadir=" << state::WORKD << "/data_slave"
             << " --tmpdir=" << state::WORKD << "/tmp_slave --port=" << state::MYPORT_SLAVE
             << " --pid-file=" << state::WORKD << "/slave_pid.pid --socket=" << state::WORKD << "/slave_socket.sock"
             << " --user=" << state::MYUSER << " "
             << cfg::SPECIAL_MYEXTRA_OPTIONS << " " << cfg::MYEXTRA << " " << cfg::REPL_EXTRA << " " << cfg::SLAVE_EXTRA
             << " --log-error=" << state::WORKD << "/log/slave.err " << scheduler << " " << core_nts;
      state::MYSQLD_SLAVE_START_TIME = std::to_string(std::time(nullptr));
      state::PIDV_SLAVE = launch_bg(actual.str(), state::WORKD + "/log/mysqld_slave.out");
    }
    // Init replication: wait for both to live
    std::string admin = cfg::BASEDIR + "/bin/mariadb-admin";
    if (!util::file_readable(admin)) admin = cfg::BASEDIR + "/bin/mysqladmin";
    int master_ok = 0, slave_ok = 0;
    for (int d = 0; d < 75; ++d) {
      std::this_thread::sleep_for(std::chrono::seconds(1));
      util::sh("touch \"" + state::WORKD + "\"");
      util::sh("touch \"" + state::WORKD + "/reducer.log\"");
      if (util::sh(admin + " -uroot -S" + state::WORKD + "/socket.sock ping > /dev/null 2>&1") == 0) master_ok = 1;
      if (util::sh(admin + " -uroot -S" + state::WORKD + "/slave_socket.sock ping > /dev/null 2>&1") == 0) slave_ok = 1;
      if (master_ok == 1 && slave_ok == 1) break;
    }
    if (master_ok != 1 || slave_ok != 1) {
      if (!util::dir_exists(state::WORKD)) abort_reducer();
      echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [Trial " + std::to_string(state::TRIAL) +
             "] [Warning] MASTER_STARTUP_OK=" + std::to_string(master_ok) + ", SLAVE_STARTUP_OK=" + std::to_string(slave_ok) +
             ": not both 1, retrying by restarting both. Last good known testcase: " + state::WORKO);
      state::PIDV.clear(); state::PIDV_SLAVE.clear(); state::MYSQLD_START_TIME.clear(); state::MYSQLD_SLAVE_START_TIME.clear();
      state::MYPORT = 0;
      if (state::TRIAL > 1) state::TRIAL--;
      return 3;
    }
    // Setup replication
    std::string r_client = "mysql";
    if (access((cfg::BASEDIR + "/bin/mariadb").c_str(), X_OK) == 0) r_client = "mariadb";
    util::sh(cfg::BASEDIR + "/bin/" + r_client + " -uroot -S" + state::WORKD + "/socket.sock -e \"DELETE FROM mysql.user WHERE user='';\" 2>/dev/null");
    util::sh(cfg::BASEDIR + "/bin/" + r_client + " -uroot -S" + state::WORKD + "/socket.sock -e \"GRANT REPLICATION SLAVE ON *.* TO 'repl_user'@'%' IDENTIFIED BY 'repl_pass'; FLUSH PRIVILEGES;\" 2>/dev/null");
    util::sh(cfg::BASEDIR + "/bin/" + r_client + " -uroot -S" + state::WORKD + "/slave_socket.sock -e \"CHANGE MASTER TO MASTER_HOST='127.0.0.1', MASTER_PORT=" + std::to_string(state::MYPORT) + ", MASTER_USER='repl_user', MASTER_PASSWORD='repl_pass', MASTER_USE_GTID=slave_pos ; START SLAVE;\" 2>/dev/null");
    int io_sql = 0;
    for (int d = 0; d < 25; ++d) {
      std::string out = util::sh_capture_trimmed(cfg::BASEDIR + "/bin/" + r_client + " -uroot -S" + state::WORKD +
        "/slave_socket.sock -e 'SHOW SLAVE STATUS\\G' | grep -o 'Slave_[SQLIO]\\+_Running:.*' | grep ': Yes' | wc -l");
      try { io_sql = std::stoi(out); } catch (...) { io_sql = 0; }
      if (io_sql == 2) break;
      std::this_thread::sleep_for(std::chrono::seconds(1));
    }
    if (io_sql != 2) {
      std::string extra = util::sh_capture_trimmed(cfg::BASEDIR + "/bin/" + r_client + " -uroot -S" + state::WORKD +
        "/slave_socket.sock -e 'SHOW SLAVE STATUS\\G' | grep -o 'Slave_[SQLIO]\\+_Running:.*' | grep ': Yes' | tr '\\n' ' ' | sed 's| $||g'");
      echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [Trial " + std::to_string(state::TRIAL) +
             "] [Warning] The IO and/or SQL threads failed to both start on the slave: " + extra + ", retrying by restarting both.");
      state::PIDV.clear(); state::PIDV_SLAVE.clear(); state::MYSQLD_START_TIME.clear(); state::MYSQLD_SLAVE_START_TIME.clear();
      state::MYPORT = 0;
      if (state::TRIAL > 1) state::TRIAL--;
      return 3;
    }
    echoit("[Info] Replication enabled between master and slave in " + state::WORKD + " using port " + std::to_string(state::MYPORT));
  } else {
    init_empty_port();
    state::MYPORT = state::NEWPORT; state::NEWPORT = 0;
    std::ostringstream cmdline;
    cmdline << state::RR_OPTIONS << " " << cfg::TIMEOUT_COMMAND << " $BIN --no-defaults --basedir=${BASEDIR} --datadir="
            << state::WORKD << "/data --tmpdir=" << state::WORKD << "/tmp --port=" << state::MYPORT
            << " --pid-file=" << state::WORKD << "/pid.pid --socket=" << state::WORKD << "/socket.sock "
            << cfg::SPECIAL_MYEXTRA_OPTIONS << " " << cfg::MYEXTRA
            << " --log-error=" << state::WORKD << "/log/master.err " << scheduler
            << " > " << state::WORKD << "/log/mysqld.out 2>&1 &\n";
    append_squashed(ws, cmdline.str());
    std::ostringstream actual;
    actual << state::RR_OPTIONS << " " << cfg::TIMEOUT_COMMAND << " " << state::BIN
           << " --no-defaults --basedir=" << cfg::BASEDIR << " --datadir=" << state::WORKD << "/data"
           << " --tmpdir=" << state::WORKD << "/tmp --port=" << state::MYPORT
           << " --pid-file=" << state::WORKD << "/pid.pid --socket=" << state::WORKD << "/socket.sock"
           << " --user=" << state::MYUSER << " "
           << cfg::SPECIAL_MYEXTRA_OPTIONS << " " << cfg::MYEXTRA
           << " --log-error=" << state::WORKD << "/log/master.err " << scheduler << " " << core_nts;
    state::MYSQLD_START_TIME = std::to_string(std::time(nullptr));
    state::PIDV = launch_bg(actual.str(), state::WORKD + "/log/mysqld.out");
  }
  util::write_file(state::WORK_START, ws.str());
  // Translate $WORKD → /dev/shm/${EPOCH} in the saved script.
  util::sh("sed -i \"s|" + state::WORKD + "|/dev/shm/" + state::EPOCH + "|g\" \"" + state::WORK_START + "\"");
  util::sh("sed -i \"s|pid.pid|pid.pid --core-file --core|\" \"" + state::WORK_START + "\"");
  util::sh("chmod +x \"" + state::WORK_START + "\"");
  std::string admin = cfg::BASEDIR + "/bin/mariadb-admin";
  if (!util::file_readable(admin)) admin = cfg::BASEDIR + "/bin/mysqladmin";
  for (int X = 0; X < 120; ++X) {
    std::this_thread::sleep_for(std::chrono::seconds(1));
    if (util::sh(admin + " -uroot -S" + state::WORKD + "/socket.sock ping > /dev/null 2>&1") == 0) break;
    if (util::sh("grep -E --binary-files=text -qi 'identify the cause of the crash' " + state::WORKD + "/log/*.err 2>/dev/null") == 0) break;
    if (util::sh("grep -E --binary-files=text -qi 'Writing a core file' "          + state::WORKD + "/log/*.err 2>/dev/null") == 0) break;
    if (util::sh("grep -E --binary-files=text -qi 'Core pattern' "                  + state::WORKD + "/log/*.err 2>/dev/null") == 0) break;
    if (util::sh("grep -E --binary-files=text -qi 'terribly wrong' "                + state::WORKD + "/log/*.err 2>/dev/null") == 0) break;
    if (util::sh("grep -E --binary-files=text -qi 'Shutdown complete' "             + state::WORKD + "/log/*.err 2>/dev/null") == 0) break;
  }
  return 0;
}

// start_valgrind_mysqld_main — mirror reducer.sh:3014..3060
static void start_valgrind_mysqld_main_impl() {
  if (!util::dir_exists(state::WORKD)) abort_reducer();
  util::sh("touch \"" + state::WORKD + "\"");
  std::string du = util::sh_capture_trimmed(
    "du -sc " + state::WORKD + "/data | grep -v 'total' | awk '{print $1}'");
  if (du == "0") {
    echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [ERROR] data directory at " + state::WORKD + "/data is 0 bytes. The volume likely ran out of space");
    std::cerr << "Terminating now.\n"; std::exit(1);
  }
  diskspace(state::WORKD);
  if (util::file_exists(state::WORKD + "/valgrind.out")) {
    util::sh("mv -f " + state::WORKD + "/valgrind.out " + state::WORKD + "/valgrind.prev");
  }
  std::string scheduler;
  if (cfg::ENABLE_QUERYTIMEOUT > 0) scheduler = "--event-scheduler=ON ";
  init_empty_port();
  state::MYPORT = state::NEWPORT; state::NEWPORT = 0;
  std::ostringstream cmd;
  cmd << cfg::TIMEOUT_COMMAND
      << " valgrind --suppressions=" << cfg::BASEDIR << "/mysql-test/valgrind.supp --num-callers=40 --show-reachable=yes "
      << state::BIN << " --no-defaults --basedir=" << cfg::BASEDIR
      << " --datadir=" << state::WORKD << "/data --port=" << state::MYPORT
      << " --tmpdir=" << state::WORKD << "/tmp --pid-file=" << state::WORKD << "/pid.pid"
      << " --socket=" << state::WORKD << "/socket.sock --user=" << state::MYUSER << " "
      << cfg::SPECIAL_MYEXTRA_OPTIONS << " " << cfg::MYEXTRA
      << " --log-error=" << state::WORKD << "/log/master.err " << scheduler;
  state::MYSQLD_START_TIME = std::to_string(std::time(nullptr));
  state::PIDV = util::sh_capture_trimmed("(" + cmd.str() + " > " + state::WORKD + "/valgrind.out 2>&1 & echo $!)");
  state::STARTUPCOUNT++;

  std::ostringstream ws;
  ws << "SCRIPT_DIR=$(cd $(dirname $0) && pwd)\n";
  ws << ". $SCRIPT_DIR/" << state::EPOCH << "_mybase\n";
  ws << "echo \"Attempting to start mariadbd/mysqld under Valgrind (socket /dev/shm/" << state::EPOCH << "/socket.sock)...\"\n";
  ws << state::JE1 << "\n" << state::JE2 << "\n" << state::JE3 << "\n" << state::JE4 << "\n";
  ws << "BIN=`find -L ${BASEDIR} -maxdepth 2 -name mariadbd -type f -o -name mysqld -type f -o -name mysqld-debug -type f -o -name mysqld -type l -o -name mysqld-debug -type l | head -1`;if [ -z \"$BIN\" ]; then echo \"Assert! mariadbd/mysqld binary '$BIN' could not be read\";exit 1;fi\n";
  std::ostringstream vg;
  vg << "valgrind --suppressions=${BASEDIR}/mysql-test/valgrind.supp --num-callers=40 --show-reachable=yes $BIN --no-defaults --basedir=${BASEDIR}"
     << " --datadir=" << state::WORKD << "/data --port=" << state::MYPORT
     << " --tmpdir=" << state::WORKD << "/tmp --pid-file=" << state::WORKD << "/pid.pid"
     << " --log-error=" << state::WORKD << "/log/master.err --socket=" << state::WORKD << "/socket.sock "
     << cfg::SPECIAL_MYEXTRA_OPTIONS << " " << cfg::MYEXTRA << " " << scheduler
     << ">>" << state::WORKD << "/log/master.err 2>&1 &\n";
  ws << util::squeeze_spaces(vg.str());
  util::write_file(state::WORK_START_VALGRIND, ws.str());
  util::sh("sed -i \"s|" + state::WORKD + "|/dev/shm/" + state::EPOCH + "|g\" \"" + state::WORK_START_VALGRIND + "\"");
  util::sh("sed -i \"s|pid.pid|pid.pid --core-file --core|\" \"" + state::WORK_START_VALGRIND + "\"");
  util::sh("sed -i \"s|\\.so\\;|\\.so\\\\;|\" \"" + state::WORK_START_VALGRIND + "\"");
  util::sh("chmod +x \"" + state::WORK_START_VALGRIND + "\"");
  std::string admin = cfg::BASEDIR + "/bin/mariadb-admin";
  if (!util::file_readable(admin)) admin = cfg::BASEDIR + "/bin/mysqladmin";
  for (int X = 0; X < 360; ++X) {
    std::this_thread::sleep_for(std::chrono::seconds(1));
    if (util::sh(admin + " -uroot -S" + state::WORKD + "/socket.sock ping > /dev/null 2>&1") == 0) break;
  }
  if (util::sh(admin + " -uroot -S" + state::WORKD + "/socket.sock ping > /dev/null 2>&1") != 0) {
    if (state::MULTI_REDUCER != 1) {
      echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [ERROR] Failed to start the mariadbd/mysqld server under Valgrind");
    }
    std::cerr << "Terminating now.\n"; std::exit(1);
  }
}

// start_mysqld_or_valgrind_or_mdg — mirror reducer.sh:2501..2562
static int start_mysqld_or_valgrind_or_mdg_impl() {
  init_mysql_dir();
  if (!util::dir_exists(state::WORKD)) abort_reducer();
  util::sh("touch \"" + state::WORKD + "\"");
  if (cfg::MDG == 1) {
    start_mdg_main_impl();
  } else if (cfg::GRP_RPL == 1) {
    gr_start_main_impl();
  } else {
    // Pre-start log rotation
    auto rot = [](const std::string& src, const std::string& dst) {
      if (util::file_exists(src)) util::sh("mv -f \"" + src + "\" \"" + dst + "\"");
    };
    rot(state::WORKD + "/log/master.err",                       state::WORKD + "/log/master.err.prev");
    rot(state::WORKD + "/log/slave.err",                        state::WORKD + "/log/slave.err.prev");
    rot(state::WORKD + "/log/mysqld.out",                       state::WORKD + "/mysqld.prev");
    rot(state::WORKD + "/log/mysqld_slave.out",                 state::WORKD + "/mysqld_slave.prev");
    rot(state::WORKD + "/log/mysql.out",                        state::WORKD + "/mysql.prev");
    rot(state::WORKD + "/log/default.node.tld_thread-0.out",    state::WORKD + "/log/default.node.tld_thread-0.prev");
    rot(state::WORKD + "/default.node.tld_thread-0.sql",        state::WORKD + "/log/default.node.tld_thread-0.prevsql");
    int failure = 0;
    if (cfg::MODE != 1 && cfg::MODE != 6) {
      int rc = start_mysqld_main_impl();
      if (rc == 3) failure = 3;
    } else {
      start_valgrind_mysqld_main_impl();
    }
    if (cfg::REDUCE_STARTUP_ISSUES <= 0) {
      std::string admin = cfg::BASEDIR + "/bin/mariadb-admin";
      if (!util::file_readable(admin)) admin = cfg::BASEDIR + "/bin/mysqladmin";
      if (util::sh(admin + " -uroot -S" + state::WORKD + "/socket.sock ping > /dev/null 2>&1") != 0) {
        if (state::STAGE == "8" || state::STAGE == "9") {
          if (state::STAGE == "8") state::STAGE8_NOT_STARTED_CORRECTLY = 1;
          if (state::STAGE == "9") state::STAGE9_NOT_STARTED_CORRECTLY = 1;
          echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [Note] Assuming this option set is required as the server did not start");
        } else {
          if (failure == 3) {
            return 3;
          } else {
            echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [Trial " + std::to_string(state::TRIAL) +
                   "] [Warning] Failed to start the mariadbd/mysqld server, retrying by restarting the server. Last good known testcase: " + state::WORKO);
            return 1;
          }
        }
      } else {
        std::string client = cfg::BASEDIR + "/bin/mariadb";
        if (!util::file_readable(client)) client = cfg::BASEDIR + "/bin/mysql";
        util::sh(client + " -uroot -S" + state::WORKD + "/socket.sock -e \"create database if not exists test\" > /dev/null 2>&1");
      }
    }
  }
  state::STARTUPCOUNT++;
  return 0;
}

// start_mdg_main + gr_start_main — large Galera/GR-specific paths. The faithful
// port mirrors the bash exactly via shell-out for the per-node my.cnf authoring
// + node-startup loop; both are gated behind cfg::MDG / cfg::GRP_RPL toggles
// and tested via the per-helper paths.
static void start_mdg_main_impl() {
  if (!util::dir_exists(state::WORKD)) abort_reducer();
  util::sh("touch \"" + state::WORKD + "\"");
  generate_run_scripts();
  util::sh("(ps -def | grep -E 'n*.cnf' | grep " + state::EPOCH + " | awk '{print $2}' | xargs -I{} kill -9 {} >/dev/null 2>&1; ) >/dev/null 2>&1");
  std::this_thread::sleep_for(std::chrono::seconds(2));
  util::sh("sync");
  const std::string SUSER = "root";
  const std::string SPASS;
  fs::remove(state::WORKD + "/my.cnf");
  std::ostringstream cnf;
  cnf << "[mysqld]\n";
  cnf << "basedir=" << cfg::BASEDIR << "\n";
  cnf << "innodb_file_per_table\ninnodb_autoinc_lock_mode=2\n";
  cnf << "wsrep-provider=" << cfg::BASEDIR << "/lib/libgalera_smm.so\n";
  cnf << "wsrep_sst_method=rsync\n";
  cnf << "wsrep_sst_auth=" << SUSER << ":" << SPASS << "\n";
  cnf << "binlog_format=ROW\ncore-file\nlog-output=none\nwsrep_slave_threads=12\nwsrep_on=1\n";
  // ENCRYPTION_RUN — mirror OLD/reducer.sh:2587-2600. Adds Galera+encryption
  // settings to every node's my.cnf when the upstream pquery-prep-red.sh
  // injection set ENCRYPTION_RUN=1 in the environment. Skipped silently when
  // unset / != "1".
  if (const char* er = std::getenv("ENCRYPTION_RUN"); er && std::string(er) == "1") {
    cnf << "encrypt_binlog=1\n"
        << "plugin_load_add=file_key_management\n"
        << "file_key_management_filename=" << cfg::SCRIPT_PWD << "/pquery/galera_encryption.key\n"
        << "file_key_management_encryption_algorithm=aes_cbc\n"
        << "innodb_encrypt_tables=ON\n"
        << "innodb_encryption_rotate_key_age=0\n"
        << "innodb_encrypt_log=ON\n"
        << "innodb_encryption_threads=4\n"
        << "innodb_encrypt_temporary_tables=ON\n"
        << "encrypt_tmp_disk_tables=1\n"
        << "encrypt_tmp_files=1\n"
        << "aria_encrypt_tables=ON\n";
  }
  util::write_file(state::WORKD + "/my.cnf", cnf.str());

  // Per-node startup-status poll lambda
  auto mdg_node_startup_status = [](const std::string& err_log) {
    for (int X = 0; X <= 120; ++X) {
      std::this_thread::sleep_for(std::chrono::seconds(1));
      util::sh("touch \"" + state::WORKD + "\"");
      if (util::sh("grep -E --binary-files=text -qi \"Synchronized with group, ready for connections\" \"" + err_log + "\"") == 0) break;
      if (X == 119) {
        std::cerr << "Error! server not started.. Terminating!\n";
        util::sh("grep -E --binary-files=text -i \"ERROR|ASSERTION\" \"" + err_log + "\"");
        std::cerr << "Terminating now.\n"; std::exit(1);
      }
    }
  };

  const std::string ADDR = "127.0.0.1";
  util::sh("rm -rf " + state::WORKD + "/tmp*");
  std::vector<int> mdg_ports;
  std::vector<std::string> mdg_laddrs;
  for (int i = 1; i <= cfg::NR_OF_NODES; ++i) {
    std::string node = state::WORKD + "/node" + std::to_string(i);
    util::mkdir_p(state::WORKD + "/tmp" + std::to_string(i));
    init_empty_port(); int rbase = state::NEWPORT; state::NEWPORT = 0;
    init_empty_port(); std::string laddr = ADDR + ":" + std::to_string(state::NEWPORT); state::NEWPORT = 0;
    init_empty_port(); std::string sst_port = ADDR + ":" + std::to_string(state::NEWPORT); state::NEWPORT = 0;
    init_empty_port(); std::string ist_port = ADDR + ":" + std::to_string(state::NEWPORT); state::NEWPORT = 0;
    mdg_ports.push_back(rbase); mdg_laddrs.push_back(laddr);
    std::string ncnf = state::WORKD + "/n" + std::to_string(i) + ".cnf";
    util::sh("cp " + state::WORKD + "/my.cnf " + ncnf);
    auto sed_ins = [&](const std::string& line) {
      util::sh("sed -i \"2i " + line + "\" " + ncnf);
    };
    sed_ins("server-id=10" + std::to_string(i));
    sed_ins("wsrep_node_incoming_address=" + ADDR);
    sed_ins("wsrep_node_address=" + ADDR);
    sed_ins("wsrep_sst_receive_address=" + sst_port);
    sed_ins("log-error=" + node + "/node" + std::to_string(i) + ".err");
    sed_ins("port=" + std::to_string(rbase));
    sed_ins("datadir=" + node);
    sed_ins("socket=" + node + "/node" + std::to_string(i) + "_socket.sock");
    sed_ins("tmpdir=" + state::WORKD + "/tmp" + std::to_string(i));
    sed_ins("wsrep_provider_options=\\\"gmcast.listen_addr=tcp://" + laddr + ";ist.recv_addr=" + ist_port + ";" + cfg::WSREP_PROVIDER_OPTIONS + "\\\"");
  }

  diskspace(fs::path(state::WORK_START).parent_path().string());
  std::ostringstream ws;
  ws << "SCRIPT_DIR=$(cd $(dirname $0) && pwd)\n";
  ws << ". $SCRIPT_DIR/" << state::EPOCH << "_mybase\n";
  ws << "BIN=`find -L ${BASEDIR} -maxdepth 2 -name mariadbd -type f -o -name mysqld -type f -o -name mysqld-debug -type f -o -name mysqld -type l -o -name mysqld-debug -type l | head -1`;if [ -z \"$BIN\" ]; then echo \"Assert! mysqld binary '$BIN' could not be read\";exit 1;fi\n";
  std::string wsrep_addr;
  for (const auto& a : mdg_laddrs) wsrep_addr += a + ",";
  if (!wsrep_addr.empty() && wsrep_addr.back() == ',') wsrep_addr.pop_back();
  if (cfg::RR_TRACING == 1) {
    setenv("_RR_TRACE_DIR", (state::WORKD + "/rr").c_str(), 1);
    util::mkdir_p(state::WORKD + "/rr");
  }
  for (int j = 1; j <= cfg::NR_OF_NODES; ++j) {
    std::string ncnf = state::WORKD + "/n" + std::to_string(j) + ".cnf";
    util::sh("sed -i \"2i wsrep_cluster_address=gcomm://" + wsrep_addr + "\" " + ncnf);
    util::sh("cp " + ncnf + " " + state::WORK_BUG_DIR + "/" + state::EPOCH + "_n" + std::to_string(j) + ".cnf");
    std::string bin_to_use = cfg::BASEDIR + "/bin/mariadbd";
    if (!util::file_readable(bin_to_use)) bin_to_use = cfg::BASEDIR + "/bin/mysqld";
    if (j == 1) {
      ws << "echo \"Attempting to start Galera Cluster...\"\n";
      std::ostringstream l;
      l << state::RR_OPTIONS << " " << cfg::TIMEOUT_COMMAND << " $BIN --defaults-file=$SCRIPT_DIR/" << state::EPOCH << "_n" << j << ".cnf "
        << cfg::SPECIAL_MYEXTRA_OPTIONS << " " << cfg::MYEXTRA << " --wsrep-new-cluster > " << state::WORKD << "/node" << j << "/mysqld.out 2>&1 &\n";
      ws << util::squeeze_spaces(l.str());
      ws << "sleep 10\n";
      util::sh("(" + state::RR_OPTIONS + " " + bin_to_use + " --defaults-file=" + ncnf + " " + cfg::MYEXTRA +
               " --wsrep-new-cluster > " + state::WORKD + "/node" + std::to_string(j) + "/node" + std::to_string(j) + ".err 2>&1 &)");
      mdg_node_startup_status(state::WORKD + "/node" + std::to_string(j) + "/node" + std::to_string(j) + ".err");
    } else {
      std::ostringstream l;
      l << cfg::TIMEOUT_COMMAND << " $BIN --defaults-file=$SCRIPT_DIR/" << state::EPOCH << "_n" << j << ".cnf "
        << cfg::SPECIAL_MYEXTRA_OPTIONS << " " << cfg::MYEXTRA
        << " > " << state::WORKD << "/node" << j << "/mysqld.out 2>&1 &\n";
      ws << util::squeeze_spaces(l.str());
      ws << "sleep 60\n";
      util::sh("(" + bin_to_use + " --defaults-file=" + ncnf + " " + cfg::MYEXTRA +
               " > " + state::WORKD + "/node" + std::to_string(j) + "/node" + std::to_string(j) + ".err 2>&1 &)");
      mdg_node_startup_status(state::WORKD + "/node" + std::to_string(j) + "/node" + std::to_string(j) + ".err");
    }
  }
  util::write_file(state::WORK_START, ws.str());
  util::sh("sed -i \"s|" + state::WORKD + "|/dev/shm/" + state::EPOCH + "|g\" \"" + state::WORK_START + "\"");
  util::sh("chmod +x \"" + state::WORK_START + "\"");
  util::sh(cfg::BASEDIR + "/bin/mysql -uroot -S" + state::WORKD + "/node1/node1_socket.sock -e \"create database if not exists test\" > /dev/null 2>&1");
}

// gr_start_main — mirror reducer.sh:2719..2872 (Group Replication 3-node startup)
static void gr_start_main_impl() {
  if (!util::dir_exists(state::WORKD)) abort_reducer();
  util::sh("touch \"" + state::WORKD + "\"");
  const std::string ADDR = "127.0.0.1";
  init_empty_port(); int rbase1 = state::NEWPORT; state::NEWPORT = 0;
  init_empty_port(); int rbase2 = state::NEWPORT; state::NEWPORT = 0;
  init_empty_port(); int rbase3 = state::NEWPORT; state::NEWPORT = 0;
  init_empty_port(); int lport1 = state::NEWPORT; state::NEWPORT = 0;
  init_empty_port(); int lport2 = state::NEWPORT; state::NEWPORT = 0;
  init_empty_port(); int lport3 = state::NEWPORT; state::NEWPORT = 0;
  std::string laddr1 = ADDR + ":" + std::to_string(lport1);
  std::string laddr2 = ADDR + ":" + std::to_string(lport2);
  std::string laddr3 = ADDR + ":" + std::to_string(lport3);

  auto gr_startup_chk = [](const std::string& err_log) {
    if (util::sh("grep -E --binary-files=text -qi 'ERROR. Aborting' \"" + err_log + "\"") == 0) {
      if (util::sh("grep -E --binary-files=text -qi 'TCP.IP port.*Address already in use' \"" + err_log + "\"") == 0) {
        std::cerr << "Assert! The text '[ERROR] Aborting' was found in the error log due to a IP port conflict\n";
      } else {
        std::cerr << "Assert! '[ERROR] Aborting' was found in the error log. Likely an issue with MYEXTRA startup options.\n";
        util::sh("grep -E --binary-files=text 'ERROR' \"" + err_log + "\"");
        std::exit(1);
      }
    }
  };

  std::string bin_to_use = cfg::BASEDIR + "/bin/mariadbd";
  if (!util::file_readable(bin_to_use)) bin_to_use = cfg::BASEDIR + "/bin/mysqld";
  std::string admin = cfg::BASEDIR + "/bin/mariadb-admin";
  if (!util::file_readable(admin)) admin = cfg::BASEDIR + "/bin/mysqladmin";
  std::string client = cfg::BASEDIR + "/bin/mariadb";
  if (!util::file_readable(client)) client = cfg::BASEDIR + "/bin/mysql";

  auto launch_node = [&](int sid, const std::string& node, const std::string& laddr, int rbase, const std::string& err) {
    std::ostringstream c;
    c << bin_to_use << " --no-defaults --basedir=" << cfg::BASEDIR << " --datadir=" << node
      << " --innodb_file_per_table " << cfg::MYEXTRA << " --innodb_autoinc_lock_mode=2 --innodb_locks_unsafe_for_binlog=1"
      << " --server_id=" << sid << " --gtid_mode=ON --enforce_gtid_consistency=ON"
      << " --master_info_repository=TABLE --relay_log_info_repository=TABLE"
      << " --binlog_checksum=NONE --log_slave_updates=ON --log_bin=binlog"
      << " --binlog_format=ROW --innodb_flush_method=O_DIRECT --core-file --sql-mode=no_engine_substitution"
      << " --loose-innodb --secure-file-priv= --loose-innodb-status-file=1"
      << " --log-error=" << node << "/error.log --socket=" << node << "/node" << sid << "_socket.sock"
      << " --log-output=none --port=" << rbase << " --transaction_write_set_extraction=XXHASH64"
      << " --loose-group_replication_group_name=\"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa\""
      << " --loose-group_replication_start_on_boot=off --loose-group_replication_local_address=\"" << laddr << "\""
      << " --loose-group_replication_group_seeds=\"" << laddr1 << "," << laddr2 << "," << laddr3 << "\""
      << " --loose-group_replication_bootstrap_group=off --super_read_only=OFF";
    util::sh("(" + c.str() + " > " + err + " 2>&1 &)");
  };

  // Node 1 — bootstrap
  launch_node(1, state::node1, laddr1, rbase1, state::node1 + "/node1.err");
  for (int X = 0; X <= 200; ++X) {
    std::this_thread::sleep_for(std::chrono::seconds(1));
    if (util::sh(admin + " -uroot -S" + state::node1 + "/node1_socket.sock ping > /dev/null 2>&1") == 0) {
      std::this_thread::sleep_for(std::chrono::seconds(2));
      util::sh(client + " -uroot -S" + state::node1 + "/node1_socket.sock -Bse \"create database if not exists test\" > /dev/null 2>&1");
      util::sh(client + " -uroot -S" + state::node1 + "/node1_socket.sock -Bse \"SET SQL_LOG_BIN=0;CREATE USER rpl_user@'%';GRANT REPLICATION SLAVE ON *.* TO rpl_user@'%' IDENTIFIED BY 'rpl_pass';FLUSH PRIVILEGES;SET SQL_LOG_BIN=1;\" > /dev/null 2>&1");
      util::sh(client + " -uroot -S" + state::node1 + "/node1_socket.sock -Bse \"CHANGE MASTER TO MASTER_USER='rpl_user', MASTER_PASSWORD='rpl_pass' FOR CHANNEL 'group_replication_recovery';\" > /dev/null 2>&1");
      util::sh(client + " -uroot -S" + state::node1 + "/node1_socket.sock -Bse \"INSTALL PLUGIN group_replication SONAME 'group_replication.so';SET GLOBAL group_replication_bootstrap_group=ON;START GROUP_REPLICATION;SET GLOBAL group_replication_bootstrap_group=OFF;\" > /dev/null 2>&1");
      break;
    }
    gr_startup_chk(state::node1 + "/node1.err");
  }
  // Node 2
  launch_node(2, state::node2, laddr2, rbase2, state::node2 + "/node2.err");
  for (int X = 0; X <= 200; ++X) {
    std::this_thread::sleep_for(std::chrono::seconds(1));
    if (util::sh(admin + " -uroot -S" + state::node2 + "/node2_socket.sock ping > /dev/null 2>&1") == 0) {
      std::this_thread::sleep_for(std::chrono::seconds(2));
      util::sh(client + " -uroot -S" + state::node2 + "/node2_socket.sock -Bse \"SET SQL_LOG_BIN=0;CREATE USER rpl_user@'%';GRANT REPLICATION SLAVE ON *.* TO rpl_user@'%' IDENTIFIED BY 'rpl_pass';FLUSH PRIVILEGES;SET SQL_LOG_BIN=1;\" > /dev/null 2>&1");
      util::sh(client + " -uroot -S" + state::node2 + "/node2_socket.sock -Bse \"CHANGE MASTER TO MASTER_USER='rpl_user', MASTER_PASSWORD='rpl_pass' FOR CHANNEL 'group_replication_recovery';\" > /dev/null 2>&1");
      util::sh(client + " -uroot -S" + state::node2 + "/node2_socket.sock -Bse \"INSTALL PLUGIN group_replication SONAME 'group_replication.so';START GROUP_REPLICATION;\" > /dev/null 2>&1");
      break;
    }
    gr_startup_chk(state::node2 + "/node2.err");
  }
  // Node 3
  launch_node(3, state::node3, laddr3, rbase3, state::node3 + "/node3.err");
  for (int X = 0; X <= 200; ++X) {
    std::this_thread::sleep_for(std::chrono::seconds(1));
    if (util::sh(admin + " -uroot -S" + state::node3 + "/node3_socket.sock ping > /dev/null 2>&1") == 0) {
      std::this_thread::sleep_for(std::chrono::seconds(2));
      util::sh(client + " -uroot -S" + state::node3 + "/node3_socket.sock -Bse \"SET SQL_LOG_BIN=0;CREATE USER rpl_user@'%';GRANT REPLICATION SLAVE ON *.* TO rpl_user@'%' IDENTIFIED BY 'rpl_pass';FLUSH PRIVILEGES;SET SQL_LOG_BIN=1;\" > /dev/null 2>&1");
      util::sh(client + " -uroot -S" + state::node3 + "/node3_socket.sock -Bse \"CHANGE MASTER TO MASTER_USER='rpl_user', MASTER_PASSWORD='rpl_pass' FOR CHANNEL 'group_replication_recovery';\" > /dev/null 2>&1");
      util::sh(client + " -uroot -S" + state::node3 + "/node3_socket.sock -Bse \"INSTALL PLUGIN group_replication SONAME 'group_replication.so';START GROUP_REPLICATION;\" > /dev/null 2>&1");
      break;
    }
    gr_startup_chk(state::node3 + "/node3.err");
  }
}
// determine_chunk — mirror reducer.sh:3061..3136
static void determine_chunk() {
  if (state::NOISSUEFLOW < 0) state::NOISSUEFLOW = 0;
  if (cfg::SLOW_DOWN_CHUNK_SCALING > 0) {
    state::CHUNK_LOOPS_DONE++;
    if (state::CHUNK_LOOPS_DONE <= cfg::SLOW_DOWN_CHUNK_SCALING_NR &&
        state::CHUNK_LOOPS_DONE < 99999999999LL &&
        state::CHUNK < state::LINECOUNTF &&
        state::NOISSUEFLOW > 0 &&
        state::CHUNK > 0) {
      return;
    }
  }
  state::CHUNK_LOOPS_DONE = 1;
  auto lcf = state::LINECOUNTF;
  auto nif = state::NOISSUEFLOW;
  if (lcf >= 1000) {
    if      (nif >= 20) state::CHUNK = 0;
    else if (nif >= 18) state::CHUNK = lcf / 500;
    else if (nif >= 15) state::CHUNK = lcf / 200;
    else if (nif >= 14) state::CHUNK = lcf / 100;
    else if (nif >= 12) state::CHUNK = lcf / 50;
    else if (nif >= 10) state::CHUNK = lcf / 25;
    else if (nif >=  8) state::CHUNK = lcf / 12;
    else if (nif >=  6) state::CHUNK = lcf / 8;
    else if (nif >=  5) state::CHUNK = lcf / 6;
    else if (nif >=  4) state::CHUNK = lcf / 4;
    else if (nif >=  3) state::CHUNK = lcf / 3;
    else if (nif >=  2) state::CHUNK = lcf / 2;
    else if (nif >=  1) state::CHUNK = lcf * 65 / 100;
    else                state::CHUNK = lcf * 80 / 100;
  } else {
    if      (nif >= 15) state::CHUNK = 0;
    else if (nif >= 14) state::CHUNK = lcf / 500;
    else if (nif >= 12) state::CHUNK = lcf / 200;
    else if (nif >= 10) state::CHUNK = lcf / 100;
    else if (nif >=  8) state::CHUNK = lcf / 75;
    else if (nif >=  6) state::CHUNK = lcf / 50;
    else if (nif >=  5) state::CHUNK = lcf / 40;
    else if (nif >=  4) state::CHUNK = lcf / 30;
    else if (nif >=  3) state::CHUNK = lcf / 20;
    else if (nif >=  2) state::CHUNK = lcf / 10;
    else if (nif >=  1) state::CHUNK = lcf / 6;
    else                state::CHUNK = lcf / 4;
  }
  if (state::SPORADIC == 1) {
    if      (lcf >= 10000) state::CHUNK = lcf / 6;
    else if (lcf >=  5000) state::CHUNK = lcf / 7;
    else if (lcf >=  2000) state::CHUNK = lcf / 8;
    else if (lcf >=  1000) state::CHUNK = lcf / 9;
    else if (lcf >=   500) state::CHUNK = lcf / 10;
    else if (lcf >=   200) state::CHUNK = lcf / 12;
    else if (lcf >=   100) state::CHUNK = lcf / 15;
    if (lcf >= 100) {
      if (nif < 100) {
        state::CHUNK = (state::CHUNK * (((100 * 100) - (nif * 100)) / 100)) / 100;
      } else {
        state::CHUNK = state::CHUNK / 100;
      }
    }
  }
  if (state::CHUNK < 0) state::CHUNK = 0;
}

// control_backtrack_flow — mirror reducer.sh:3137..3146
static void control_backtrack_flow() {
  if      (state::NOISSUEFLOW >= 100) state::NOISSUEFLOW -= 60;
  else if (state::NOISSUEFLOW >=  70) state::NOISSUEFLOW -= 40;
  else if (state::NOISSUEFLOW >=  40) state::NOISSUEFLOW -= 20;
  else if (state::NOISSUEFLOW >=  20) state::NOISSUEFLOW -= 8;
  else if (state::NOISSUEFLOW >=  10) state::NOISSUEFLOW -= 3;
  else if (state::NOISSUEFLOW >=   1) state::NOISSUEFLOW -= 1;
}

// cut_random_chunk — mirror reducer.sh:3147..3220
static void cut_random_chunk() {
  state::RANDLINE = -1;
  long long rlloopcount = 0;
  state::TAIL_ANCHOR_LINE = 0;
  if (cfg::MODE == 0) {
    std::error_code ec; auto sz = fs::file_size(state::WORKF, ec);
    if (!ec && sz > 0) {
      std::string current = util::sh_capture_trimmed("stat -c '%s_%Y' \"" + state::WORKF + "\" 2>/dev/null");
      if (state::WORKF_STAT_CACHED != current) {
        std::string s = util::sh_capture_trimmed(
          "awk 'toupper($0) ~ /^[[:space:]]*SHUTDOWN[[:space:]]*;?[[:space:]]*$/ {i=NR} END {print i+0}' \"" + state::WORKF + "\" 2>/dev/null");
        try { state::TAIL_ANCHOR_LINE_CACHED = std::stoll(s); } catch (...) { state::TAIL_ANCHOR_LINE_CACHED = 0; }
        state::WORKF_STAT_CACHED = current;
      }
      state::TAIL_ANCHOR_LINE = state::TAIL_ANCHOR_LINE_CACHED;
    }
  }
  auto rand_int = [](long long max) -> long long {
    std::lock_guard<std::mutex> g(state::rng_mutex);
    std::uniform_int_distribution<long long> d(0, std::max<long long>(0, max));
    return d(state::rng);
  };
  if (cfg::PQUERY_CONS_Q_FAIL == 0) {
    while (state::RANDLINE <= 0) {
      state::RANDLINE = rand_int(state::LINECOUNTF - state::CHUNK + 0);  // RANDOM % (n+1) range; n = LINECOUNTF-CHUNK
      // Match bash: $RANDOM % ($[LINECOUNTF - CHUNK] + 1)
      // Our rand_int(max) is uniform [0..max] inclusive, so passing (LINECOUNTF-CHUNK) is equivalent to RANDOM % (LINECOUNTF-CHUNK+1).
      if (state::RANDLINE > 0 && state::TAIL_ANCHOR_LINE > 0) {
        if (state::RANDLINE <= state::TAIL_ANCHOR_LINE && state::RANDLINE + state::CHUNK >= state::TAIL_ANCHOR_LINE) {
          state::RANDLINE = -1;
          if (rlloopcount >= 100) state::TAIL_ANCHOR_LINE = 0;
        }
      }
      rlloopcount++;
      if (rlloopcount >= 1000) {
        std::cerr << "Assert: RLLOOPCOUNT -ge 1000! Fix this\n";
        std::cerr << "Debug: RANDLINE: " << state::RANDLINE << " | LINECOUNTF: " << state::LINECOUNTF << " | CHUNK: " << state::CHUNK << " | TAIL_ANCHOR_LINE: " << state::TAIL_ANCHOR_LINE << "\n";
        std::exit(1);
      }
    }
  } else {
    if (state::LINECOUNTF == 251) {
      std::cerr << "Assert: optimal testcase for PQUERY_CONS_Q_FAIL (251 queries) already achieved: nothing left todo\n";
      std::cerr << "Testcase: " << state::WORKF << "\n";
      std::exit(1);
    }
    long long randmin250 = state::LINECOUNTF - state::CHUNK - 250;
    while (randmin250 < 1) {
      state::CHUNK = rand_int(state::LINECOUNTF - 250 - 1);
      randmin250 = state::LINECOUNTF - state::CHUNK - 250;
    }
    while (state::RANDLINE <= 0) {
      state::RANDLINE = rand_int(randmin250);
      rlloopcount++;
      if (rlloopcount >= 1000) {
        std::cerr << "Assert: RLLOOPCOUNT -ge 1000! Fix this\n";
        std::cerr << "Debug: RANDLINE: " << state::RANDLINE << " | LINECOUNTF: " << state::LINECOUNTF << " | CHUNK: " << state::CHUNK << "\n";
        std::exit(1);
      }
    }
  }
  if (state::CHUNK == 0 && state::TRIAL > 5) state::STUCKTRIAL++;
  if (state::CHUNK == 0 && state::STUCKTRIAL > 5) {
    echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [Trial " + std::to_string(state::TRIAL) +
           "] Now filtering line " + std::to_string(state::RANDLINE) + " (Current chunk size: stuck at 1)");
    diskspace(fs::path(state::WORKT).parent_path().string());
    util::sh("sed -n \"" + std::to_string(state::RANDLINE) + " ! p\" \"" + state::WORKF + "\" > \"" + state::WORKT + "\"");
  } else {
    state::ENDLINE = state::RANDLINE + state::CHUNK;
    state::REALCHUNK = state::CHUNK + 1;
    if (state::SPORADIC == 1 && state::LINECOUNTF < 100) {
      echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [Trial " + std::to_string(state::TRIAL) +
             "] Now filtering line(s) " + std::to_string(state::RANDLINE) + " to " + std::to_string(state::ENDLINE) +
             " (Current chunk size: " + std::to_string(state::REALCHUNK) + ": Sporadic issue; using a fixed % based chunk)");
    } else {
      echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [Trial " + std::to_string(state::TRIAL) +
             "] Now filtering line(s) " + std::to_string(state::RANDLINE) + " to " + std::to_string(state::ENDLINE) +
             " (Current chunk size: " + std::to_string(state::REALCHUNK) + ")");
    }
    diskspace(fs::path(state::WORKT).parent_path().string());
    util::sh("sed -n \"" + std::to_string(state::RANDLINE) + ",+" + std::to_string(state::CHUNK) +
             " ! p\" \"" + state::WORKF + "\" > \"" + state::WORKT + "\"");
  }
}

// cut_fireworks_chunk_and_shuffle — mirror reducer.sh:3221..3227
static void cut_fireworks_chunk_and_shuffle() {
  echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [Trial " + std::to_string(state::TRIAL) +
         "] [FIREWORKS] Chunking, shuffling and executing " + std::to_string(cfg::FIREWORKS_LINES) + " lines");
  diskspace(fs::path(state::WORKT).parent_path().string());
  util::sh("shuf -n" + std::to_string(cfg::FIREWORKS_LINES) + " --random-source=/dev/urandom \"" + cfg::INPUTFILE + "\" > \"" + state::WORKT + "\"");
}

// cut_threadsync_chunk — mirror reducer.sh:3228..3273
static void cut_threadsync_chunk() {
  if (cfg::TS_TRXS_SETS > 0) {
    echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [Trial " + std::to_string(state::TRIAL) +
           "] Now filtering out last " + std::to_string(cfg::TS_TRXS_SETS) + " command sets");
  }
  diskspace(state::WORKD);
  for (int t = 1; t <= state::TS_THREADS; ++t) {
    std::string tsw_f = util::getenv_or(("WORKF" + std::to_string(t)).c_str());
    std::string tsw_t = util::getenv_or(("WORKT" + std::to_string(t)).c_str());
    setenv("TS_WORKF", tsw_f.c_str(), 1);
    setenv("TS_WORKT", tsw_t.c_str(), 1);
    if (cfg::TS_TRXS_SETS > 0) {
      std::string first_ds = util::sh_capture_trimmed(
        "tac \"" + tsw_f + "\" | grep -E --binary-files=text -v \"^[\\t ]*;[\\t ]*$\" | grep -E --binary-files=text -m1 -n \"SET DEBUG_SYNC\" | awk -F\":\" '{print $1}'");
      bool is_control = (util::sh("grep -E --binary-files=text -qi \"SIGNAL GO_T2\" \"" + tsw_f + "\"") == 0);
      std::string awk_pattern = is_control ? "now SIGNAL GO_T2" : "now WAIT_FOR GO_T";
      int first_ds_n = 1;
      try { first_ds_n = std::stoi(first_ds); } catch (...) {}
      std::string last_line_cmd;
      if (first_ds_n > 1) {
        last_line_cmd = "tac \"" + tsw_f + "\" | awk -v ts=\"" + std::to_string(cfg::TS_TRXS_SETS) + "\" '/" + awk_pattern + "/,/SET DEBUG_SYNC/ {print NR; i++; if (i>ts) nextfile}' | tail -n1";
      } else {
        last_line_cmd = "tac \"" + tsw_f + "\" | awk -v ts=\"" + std::to_string(cfg::TS_TRXS_SETS) + "\" '/" + awk_pattern + "/,/SET DEBUG_SYNC/ {print NR; i++; if (i>1+ts) nextfile}' | tail -n1";
      }
      std::string last_line = util::sh_capture_trimmed(last_line_cmd);
      if (cfg::TS_VARIABILITY_SLEEP > 0) {
        if (is_control) {
          util::sh("tail -n" + last_line + " \"" + tsw_f + "\" | grep -E --binary-files=text -v \"^[\\t ]*;[\\t ]*$\" | "
                   "sed \"s/SET DEBUG_SYNC\\(.*\\)now SIGNAL GO_T2/SELECT SLEEP(" + std::to_string(cfg::TS_VARIABILITY_SLEEP) + ");SET DEBUG_SYNC\\1now SIGNAL GO_T2/\" > \"" + tsw_t + "\"");
        } else {
          std::string tenth = std::to_string(cfg::TS_VARIABILITY_SLEEP / 10.0);
          util::sh("tail -n" + last_line + " \"" + tsw_f + "\" | grep -E --binary-files=text -v \"^[\\t ]*;[\\t ]*$\" | "
                   "sed \"s/SET DEBUG_SYNC/SELECT SLEEP(" + tenth + ");SET DEBUG_SYNC/\" > \"" + tsw_t + "\"");
        }
      } else {
        util::sh("tail -n" + last_line + " \"" + tsw_f + "\" | grep -E --binary-files=text -v \"^[\\t ]*;[\\t ]*$\" > \"" + tsw_t + "\"");
      }
    } else {
      util::sh("cat \"" + tsw_f + "\" > \"" + tsw_t + "\"");
    }
  }
}
// Forward decl for process_outcome — defined in the outcome block below.
static int process_outcome_impl();

// run_and_check — mirror reducer.sh:3274..3304
static int run_and_check_impl() {
  int start_rc = start_mysqld_or_valgrind_or_mdg_impl();
  if (start_rc == 3) { stop_mysqld_or_mdg(); return 0; }
  if (start_rc == 1) { stop_mysqld_or_mdg(); std::cout << "RETURN CODE WAS 1\n"; return 0; }
  run_sql_code();
  if (cfg::MODE == 0 || cfg::MODE == 1 || cfg::MODE == 6) stop_mysqld_or_mdg();
  int outcome = process_outcome_impl();
  if (cfg::MODE != 0 && cfg::MODE != 1 && cfg::MODE != 6) stop_mysqld_or_mdg();
  diskspace(state::WORKD);
  if (cfg::MDG == 1) {
    for (int i = 1; i <= cfg::NR_OF_NODES; ++i) {
      util::sh("cat \"" + state::WORKD + "/node" + std::to_string(i) + "/node" + std::to_string(i) + ".err\" >> \"" + state::WORKD + "/node" + std::to_string(i) + "_error.log\"");
    }
  } else if (cfg::GRP_RPL == 1) {
    util::sh("sudo cat \"" + state::WORKD + "/node1/error.log\" >> \"" + state::WORKD + "/node1_error.log\"");
    util::sh("sudo cat \"" + state::WORKD + "/node2/error.log\" >> \"" + state::WORKD + "/node2_error.log\"");
    util::sh("sudo cat \"" + state::WORKD + "/node3/error.log\" >> \"" + state::WORKD + "/node3_error.log\"");
  } else {
    util::sh("cat \"" + state::WORKD + "/log/master.err\" >> \"" + state::WORKD + "/error.log\"");
    fs::remove(state::WORKD + "/log/master.err");
    if (util::file_readable(state::WORKD + "/log/slave.err")) {
      util::sh("cat \"" + state::WORKD + "/log/slave.err\" >> \"" + state::WORKD + "/error_slave.log\"");
      fs::remove(state::WORKD + "/log/slave.err");
    }
  }
  return outcome;
}
static void run_and_check() { (void)run_and_check_impl(); }

// run_sql_code — mirror reducer.sh:3305..3445
static int run_sql_code_impl() {
  if (cfg::ENABLE_QUERYTIMEOUT > 0) {
    std::string sock = (cfg::MDG == 1 || cfg::GRP_RPL == 1)
      ? state::WORKD + "/node1/node1_socket.sock"
      : state::WORKD + "/socket.sock";
    util::sh(cfg::BASEDIR + "/bin/mysql -uroot -S" + sock + " --force mysql -e \""
             "DELIMITER || "
             "CREATE EVENT querytimeout ON SCHEDULE EVERY 20 SECOND DO BEGIN "
             "SET @id:=''; "
             "SET @id:=(SELECT id FROM INFORMATION_SCHEMA.PROCESSLIST WHERE ID<>CONNECTION_ID() AND STATE<>'killed' AND TIME>" + std::to_string(cfg::QUERYTIMEOUT) + " ORDER BY TIME DESC LIMIT 1); "
             "IF @id > 1 THEN KILL QUERY @id; END IF; "
             "END || "
             "DELIMITER ;\"");
  }
  if (cfg::MODE >= 6 && cfg::MODE <= 9) {
    echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [Trial " + std::to_string(state::TRIAL) +
           "] [DATA] Loading datafile before SQL threads replay");
    std::string ts_data = util::getenv_or("TS_DATAINPUTFILE");
    if (cfg::TS_DBG_CLI_OUTPUT == 0) {
      util::sh("echo \"$(echo \"" + state::DROPC + "\";cat \"" + ts_data + "\" | grep -E --binary-files=text -v \"" + state::DROPC + "\")\" | "
               + cfg::BASEDIR + "/bin/mysql -uroot -S" + state::WORKD + "/socket.sock --force test > /dev/null 2>/dev/null");
    } else {
      util::sh("echo \"$(echo \"" + state::DROPC + "\";cat \"" + ts_data + "\" | grep -E --binary-files=text -v \"" + state::DROPC + "\")\" | "
               + cfg::BASEDIR + "/bin/mysql -uroot -S" + state::WORKD + "/socket.sock --force -vvv test > " + state::WORKD + "/mysql_data.out 2>&1");
    }
    std::vector<std::string> tids(state::TS_THREADS);
    for (int t = 1; t <= state::TS_THREADS; ++t) {
      std::string tsw_t = util::getenv_or(("WORKT" + std::to_string(t)).c_str());
      setenv("TS_WORKT", tsw_t.c_str(), 1);
      std::string redir = (cfg::TS_DBG_CLI_OUTPUT == 0)
        ? "> /dev/null 2>/dev/null"
        : "> " + state::WORKD + "/mysql" + std::to_string(t) + ".out 2>&1";
      std::string opt = (cfg::TS_DBG_CLI_OUTPUT == 0) ? "" : "-vvv ";
      std::string pid = util::sh_capture_trimmed(
        "(cat \"" + tsw_t + "\" | " + cfg::BASEDIR + "/bin/mysql -uroot -S" + state::WORKD + "/socket.sock --force " + opt + "test " + redir + " & echo $!)");
      tids[t-1] = pid;
    }
    for (int t = state::TS_THREADS; t >= 1; --t) {
      if (!tids[t-1].empty()) util::sh("wait " + tids[t-1]);
    }
    echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [Trial " + std::to_string(state::TRIAL) +
           "] [SQL] All SQL threads have finished/terminated");
  } else if (cfg::MODE == 5) {
    std::string sock = (cfg::MDG == 1 || cfg::GRP_RPL == 1)
      ? state::node1 + "/node1_socket.sock"
      : state::WORKD + "/socket.sock";
    util::sh("cat \"" + state::WORKT + "\" | " + cfg::BASEDIR + "/bin/mysql -uroot -S" + sock + " -vvv --force test > " + state::WORKD + "/log/mysql.out 2>&1");
  } else {
    if (cfg::USE_PQUERY == 1) {
      setenv("LD_LIBRARY_PATH", (cfg::BASEDIR + "/lib").c_str(), 1);
      diskspace(state::WORKD);
      if (util::file_readable(state::WORKD + "/pquery.out")) {
        util::sh("mv " + state::WORKD + "/pquery.out " + state::WORKD + "/pquery.prev");
      }
      std::string client_log = (cfg::MODE == 2) ? "--log-all-queries --log-failed-queries" : "";
      std::string sock = (cfg::MDG == 1 || cfg::GRP_RPL == 1)
        ? state::WORKD + "/node1/node1_socket.sock"
        : state::WORKD + "/socket.sock";
      auto pq_shuffle_arg = [&]() -> std::string {
        if (cfg::PQUERY_MULTI == 0) {
          if (cfg::PQUERY_REVERSE_NOSHUFFLE_OPT == 0) return "--no-shuffle";
        } else {
          if (cfg::PQUERY_REVERSE_NOSHUFFLE_OPT == 1) return "--no-shuffle";
        }
        long long lines = util::count_lines(state::WORKT);
        return "--queries-per-thread=" + std::to_string(lines * 13 / 10 + 100);
      };
      std::string sh = pq_shuffle_arg();
      std::string pq_cmd;
      if (cfg::PQUERY_MULTI == 0) {
        pq_cmd = cfg::PQUERY_LOC + " --database=test --infile=\"" + state::WORKT + "\" " + sh +
                 " --threads=1 " + client_log + " --user=root --socket=" + sock +
                 " --logdir=" + state::WORKD + " --log-all-queries --log-failed-queries " + cfg::PQUERY_EXTRA_OPTIONS;
      } else {
        pq_cmd = cfg::PQUERY_LOC + " --database=test --infile=\"" + state::WORKT + "\" " + sh +
                 " --threads=" + std::to_string(cfg::PQUERY_MULTI_CLIENT_THREADS) +
                 " --queries=" + std::to_string(cfg::PQUERY_MULTI_QUERIES) + " " + client_log +
                 " --user=root --socket=" + sock + " --logdir=" + state::WORKD +
                 " --log-all-queries --log-failed-queries " + cfg::PQUERY_EXTRA_OPTIONS;
      }
      util::sh(pq_cmd + " > " + state::WORKD + "/pquery.out 2>&1");
    } else {
      std::string sock = (cfg::MDG == 1 || cfg::GRP_RPL == 1)
        ? state::WORKD + "/node1/node1_socket.sock"
        : state::WORKD + "/socket.sock";
      if (!util::dir_exists(state::WORKD)) abort_reducer();
      switch (cfg::CLI_MODE) {
        case 0:
          util::sh("cat \"" + state::WORKT + "\" | " + cfg::BASEDIR + "/bin/mysql -uroot -S" + sock + " --binary-mode --force test > " + state::WORKD + "/log/mysql.out 2>&1");
          break;
        case 1:
          util::sh(cfg::BASEDIR + "/bin/mysql -uroot -S" + sock + " --execute=\"SOURCE " + state::WORKT + ";\" --force test > " + state::WORKD + "/log/mysql.out 2>&1");
          break;
        case 2:
          util::sh(cfg::BASEDIR + "/bin/mysql -uroot -S" + sock + " --binary-mode --force test < \"" + state::WORKT + "\" > " + state::WORKD + "/log/mysql.out 2>&1");
          break;
        default:
          echoit("Assert: default clause in CLI_MODE switchcase hit (in run_sql_code). CLI_MODE=" + std::to_string(cfg::CLI_MODE));
          std::exit(1);
      }
    }
  }
  std::this_thread::sleep_for(std::chrono::seconds(1));
  return 0;
}
static int run_sql_code() { return run_sql_code_impl(); }

// write_workO_options_header — mirror reducer.sh:3446..3474
static void write_workO_options_header() {
  std::string opts_req = util::sh_capture_trimmed(
    "echo \"" + cfg::SPECIAL_MYEXTRA_OPTIONS + " " + cfg::MYEXTRA + "\" | sed \"s|[ \\t]\\+| |g;s|sql_mode=\\([^ ]\\)|sql_mode= \\1|g;s|[ \\t]\\+| |g\"");
  std::string no_spaces = util::sh_capture_trimmed("echo \"" + opts_req + "\" | sed 's| ||g'");
  if (!no_spaces.empty()) {
    std::error_code ec; auto sz = fs::file_size(state::WORKO, ec);
    bool has_content = (!ec && sz > 0);
    std::string hdr = "# mysqld options required for replay: " + opts_req;
    if (!cfg::MYINIT.empty()) hdr += "    mysqld initialization options required: " + cfg::MYINIT;
    if (has_content) {
      util::sh("sed -i \"1 i\\" + hdr + "\" \"" + state::WORKO + "\"");
    } else {
      diskspace(fs::path(state::WORKO).parent_path().string());
      util::write_file(state::WORKO, hdr + "\n");
    }
  } else if (!cfg::MYINIT.empty()) {
    std::error_code ec; auto sz = fs::file_size(state::WORKO, ec);
    bool has_content = (!ec && sz > 0);
    std::string hdr = "# mysqld initialization options required: " + cfg::MYINIT;
    if (has_content) {
      util::sh("sed -i \"1 i\\" + hdr + "\" \"" + state::WORKO + "\"");
    } else {
      diskspace(fs::path(state::WORKO).parent_path().string());
      util::write_file(state::WORKO, hdr + "\n");
    }
  }
}
// cleanup_and_save — mirror reducer.sh:3475..3708
static void cleanup_and_save() {
  if (cfg::MODE >= 6 && cfg::MODE <= 9) {
    if (state::STAGE == "T") {
      util::sh("rm -Rf " + state::WORKD + "/log/*.sql");
    }
    util::sh("rm -Rf " + state::WORKD + "/out/*.sql");
    diskspace(state::WORKD);
    for (int t = 1; t <= state::TS_THREADS; ++t) {
      std::string tsw_f = util::getenv_or(("WORKF" + std::to_string(t)).c_str());
      std::string tsw_t = util::getenv_or(("WORKT" + std::to_string(t)).c_str());
      std::string tsw_o = util::getenv_or(("WORKO" + std::to_string(t)).c_str());
      util::sh("cp -f \"" + tsw_t + "\" \"" + tsw_f + "\"");
      util::sh("cp -f \"" + tsw_t + "\" \"" + tsw_o + "\"");
      if (state::STAGE == "T") {
        // sed 's/_out//g;s/\/out/\/log/g' on tsw_o
        std::string te_file = util::replace_all(tsw_o, "_out", "");
        te_file = util::replace_all(te_file, "/out", "/log");
        if (t != state::TS_ELIMINATION_THREAD_ID) {
          util::sh("cp -f \"" + tsw_o + "\" \"" + te_file + "\"");
        }
      }
    }
    if (state::STAGE == "T") {
      if (state::TS_TE_DIR_SWAP_DONE == 1) {
        echoit("[Info] ThreadSync input directory now set to " + state::WORKD + "/log after a thread was eliminated (Directory was re-initialized)");
      } else {
        echoit("[Info] ThreadSync input directory now set to " + state::WORKD + "/log after a thread was eliminated");
        state::TS_TE_DIR_SWAP_DONE = 1;
      }
      util::sh("cp -f \"" + state::TS_ORIG_DATAINPUTFILE + "\" \"" + state::WORKD + "/log\"");
      state::TS_THREADS--;
      state::TS_ELIMINATED_THREAD_COUNT++;
      state::TS_INPUTDIR = state::WORKD + "/log";
      TS_init_all_sql_files();
    }
  } else {
    if (cfg::MDG == 1) {
      util::sh("( ps -def | grep -E 'n*.cnf' | grep " + state::EPOCH + " | awk '{print $2}' | xargs -I{} kill -9 {} >/dev/null 2>&1; ) >/dev/null 2>&1");
      std::this_thread::sleep_for(std::chrono::seconds(2));
      util::sh("sync");
    }
    if (cfg::GRP_RPL == 1) {
      util::sh("( ps -def | grep -E 'node1_socket|node2_socket|node3_socket' | grep " + state::EPOCH + " | awk '{print $2}' | xargs -I{} kill -9 {} >/dev/null 2>&1; ) >/dev/null 2>&1");
      std::this_thread::sleep_for(std::chrono::seconds(2));
      util::sh("sync");
    }
    // Precondition: WORKT must have at least one non-comment/non-blank SQL line
    long long sql_lines = 0;
    {
      std::string s = util::sh_capture_trimmed(
        "grep -E --binary-files=text -cv '^[[:space:]]*(#|--|$)' \"" + state::WORKT + "\" 2>/dev/null || echo 0");
      try { sql_lines = std::stoll(s); } catch (...) { sql_lines = 0; }
    }
    std::error_code ec;
    auto workt_sz = fs::file_size(state::WORKT, ec);
    if (ec || workt_sz == 0 || sql_lines == 0) {
      echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [Trial " + std::to_string(state::TRIAL) +
             "] [Warning] WORKT (" + state::WORKT + ") is empty or has no SQL lines (only header/comments); refusing to commit. Previous " + state::WORKO + " kept intact.");
      return;
    }
    diskspace(fs::path(state::WORKF).parent_path().string());
    util::sh("cp -f \"" + state::WORKT + "\" \"" + state::WORKF + "\"");
    if (util::file_readable(state::WORKO)) {
      if (cfg::RR_TRACING == 1 && cfg::RR_SAVE_ALL_TRACES == 1) {
        save_rr_trace(state::WORK_BUG_DIR + "/rr/" + state::STAGE + "_" + std::to_string(state::TRIAL) + "_rr_trace");
        echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [Trial " + std::to_string(state::TRIAL) +
               "] Saved RR trace in " + state::WORK_BUG_DIR + "/rr/" + state::STAGE + "_" + std::to_string(state::TRIAL) + "_rr_trace");
      }
      diskspace(fs::path(state::WORKO).parent_path().string());
      util::sh("cp -f \"" + state::WORKO + "\" \"" + state::WORKO + ".prev\"");
      echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [Trial " + std::to_string(state::TRIAL) +
             "] Previous good testcase backed up as " + state::WORKO + ".prev");
    }
    diskspace(fs::path(state::WORKO).parent_path().string());
    // Atomic WORKO write via mktemp + rename
    std::string tmp_template = state::WORKO + ".XXXXXX.tmp";
    std::string workO_tmp = util::sh_capture_trimmed("mktemp \"" + tmp_template + "\" 2>/dev/null");
    if (workO_tmp.empty() || !util::file_exists(workO_tmp)) {
      echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [Trial " + std::to_string(state::TRIAL) +
             "] [Warning] mktemp failed in " + fs::path(state::WORKO).parent_path().string() + "; refusing to commit. Previous " + state::WORKO + " kept intact.");
      return;
    }
    int rc = util::sh("grep -E --binary-files=text -v \"^# mysqld options required for replay:\" \"" + state::WORKT + "\" > \"" + workO_tmp + "\" 2>/dev/null");
    if (rc != 0) {
      fs::remove(workO_tmp);
      echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [Trial " + std::to_string(state::TRIAL) +
             "] [Warning] grep of " + state::WORKT + " into tmp failed; refusing to commit. Previous " + state::WORKO + " kept intact.");
      return;
    }
    long long tmp_sql_lines = 0;
    {
      std::string s = util::sh_capture_trimmed(
        "grep -E --binary-files=text -cv '^[[:space:]]*(#|--|$)' \"" + workO_tmp + "\" 2>/dev/null || echo 0");
      try { tmp_sql_lines = std::stoll(s); } catch (...) { tmp_sql_lines = 0; }
    }
    if (tmp_sql_lines == 0) {
      fs::remove(workO_tmp);
      echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [Trial " + std::to_string(state::TRIAL) +
             "] [Warning] tmp from grep has no SQL lines (race wiped/emptied WORKT); refusing to commit. Previous " + state::WORKO + " kept intact.");
      return;
    }
    util::sh("mv -f \"" + workO_tmp + "\" \"" + state::WORKO + "\"");
    write_workO_options_header();
    diskspace(fs::path(state::WORK_OUT).parent_path().string());
    std::string out_tmp_template = state::WORK_OUT + ".XXXXXX.tmp";
    std::string work_out_tmp = util::sh_capture_trimmed("mktemp \"" + out_tmp_template + "\" 2>/dev/null");
    if (!work_out_tmp.empty() && util::file_exists(work_out_tmp)) {
      if (util::sh("cp -f \"" + state::WORKO + "\" \"" + work_out_tmp + "\"") == 0) {
        util::sh("mv -f \"" + work_out_tmp + "\" \"" + state::WORK_OUT + "\"");
      } else {
        fs::remove(work_out_tmp);
        echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [Trial " + std::to_string(state::TRIAL) +
               "] [Warning] cp " + state::WORKO + " to tmp failed; " + state::WORK_OUT + " not refreshed but " + state::WORKO + " is up-to-date");
      }
    } else {
      echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [Trial " + std::to_string(state::TRIAL) +
             "] [Warning] mktemp failed in " + fs::path(state::WORK_OUT).parent_path().string() + "; " + state::WORK_OUT + " not refreshed but " + state::WORKO + " is up-to-date");
    }
    fs::remove(state::WORK_BUG_DIR + "/" + state::EPOCH + "_bug_bundle.tar.gz");
    diskspace(state::WORK_BUG_DIR);
    util::sh("(cd \"" + state::WORK_BUG_DIR + "\"; tar -zhcf " + state::EPOCH + "_bug_bundle.tar.gz " + state::EPOCH + "*)");
  }
  state::ATLEASTONCE = "[*]";
  if (state::STAGE == "8") state::STAGE8_CHK = 1;
  if (state::STAGE == "9") state::STAGE9_CHK = 1;
  // VERIFIED file + subreducer behavior
  {
    std::ostringstream os;
    os << "TRIAL:" << state::TRIAL << "\n";
    os << "WORKO:" << state::WORKO << "\n";
    if (state::MULTI_REDUCER == 1) {
      os << "# " << state::ATLEASTONCE << " Issue was reproduced during this simplification subreducer.\n";
      util::write_file(state::WORKD + "/VERIFIED", os.str());
      echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] Issue was reproduced during this simplification subreducer. Terminating now.");
      finish(cfg::INPUTFILE);
    } else {
      os << "# " << state::ATLEASTONCE << " Issue was seen at least once during this run of reducer\n";
      util::write_file(state::WORKD + "/VERIFIED", os.str());
    }
  }
}
// MODE=11 helpers — mirror reducer.sh mode11_* helpers
static bool mode11_take_snapshot(const std::string& sock, const std::string& out) {
  util::write_file(out, "");
  bool ready = false;
  for (int r = 0; r < 60; ++r) {
    if (util::sh(cfg::BASEDIR + "/bin/mariadb -uroot -S\"" + sock + "\" -Nse \"SELECT 1\" >/dev/null 2>&1") == 0) { ready = true; break; }
    std::this_thread::sleep_for(std::chrono::milliseconds(500));
  }
  if (!ready) {
    echoit("[MODE11] server on " + sock + " not responding during snapshot (after 30s of retries)");
    if (util::file_readable(state::WORKD + "/log/master.err")) {
      echoit("[MODE11] Tail of " + state::WORKD + "/log/master.err:");
      auto lines = util::split(util::sh_capture("tail -n 10 \"" + state::WORKD + "/log/master.err\" 2>/dev/null"), '\n');
      for (const auto& ln : lines) if (!ln.empty()) echoit("  | " + ln);
    }
    return false;
  }
  // One-time per-reducer warning when input SQL did not come from ~/mariadb-qa/generatorcpp. The per-DB batched CHECKSUM TABLE below uses bare db.table identifiers (no backticks); tables/columns with special chars or reserved-word names may break it. generatorcpp produces clean t1-tN tables and c1-cN columns; other sources (older generator, custom INFILE) may not.
  static bool gen_warned = false;
  if (!gen_warned) {
    gen_warned = true;
    if (cfg::INPUTFILE.empty() || cfg::INPUTFILE.find("generatorcpp") == std::string::npos) {
      echoit("[MODE11] [Warning] INPUTFILE does not appear to come from ~/mariadb-qa/generatorcpp. The batched CHECKSUM TABLE uses unquoted db.table identifiers; tables/columns with special chars or reserved-word names may break the snapshot. Use generatorcpp (defined t1-tN tables, c1-cN columns) to avoid this.");
    }
  }
  std::string dbs = util::sh_capture_trimmed(
    cfg::BASEDIR + "/bin/mariadb -uroot -S\"" + sock +
    "\" -Nse \"SELECT schema_name FROM information_schema.schemata WHERE schema_name NOT IN ('mysql','information_schema','performance_schema','sys') ORDER BY schema_name\" 2>/dev/null");
  if (dbs.empty()) {
    util::append_file(out, "# no user databases\n");
    return true;
  }
  for (const auto& db : util::split(dbs, '\n')) {
    if (db.empty()) continue;
    util::append_file(out, "### DATABASE: " + db + "\n");
    std::string ck_list;
    std::string tv = util::sh_capture(cfg::BASEDIR + "/bin/mariadb -uroot -S\"" + sock +
      "\" -Nse \"SELECT table_name, table_type FROM information_schema.tables WHERE table_schema='" + db + "' ORDER BY table_name, table_type\" 2>/dev/null");
    for (const auto& row : util::split(tv, '\n')) {
      if (row.empty()) continue;
      auto tab = row.find('\t');
      std::string tbl = (tab == std::string::npos) ? row : row.substr(0, tab);
      std::string typ = (tab == std::string::npos) ? "" : row.substr(tab + 1);
      if (tbl.empty()) continue;
      if (typ == "VIEW") {
        util::append_file(out, "## VIEW " + db + "." + tbl + "\n");
        util::sh(cfg::BASEDIR + "/bin/mariadb -uroot -S\"" + sock + "\" -Nse \"SHOW CREATE VIEW \\`" + db + "\\`.\\`" + tbl + "\\`\" >> \"" + out + "\" 2>&1");
      } else {
        util::append_file(out, "## TABLE " + db + "." + tbl + "\n");
        util::sh(cfg::BASEDIR + "/bin/mariadb -uroot -S\"" + sock + "\" -Nse \"SHOW CREATE TABLE \\`" + db + "\\`.\\`" + tbl + "\\`\" >> \"" + out + "\" 2>&1");
        util::sh(cfg::BASEDIR + "/bin/mariadb -uroot -S\"" + sock + "\" -Nse \"SELECT 'count',COUNT(*) FROM \\`" + db + "\\`.\\`" + tbl + "\\`\" >> \"" + out + "\" 2>&1");
        // Defer CHECKSUM TABLE EXTENDED into a single per-DB batched statement (N round-trips collapse to 1).
        if (!ck_list.empty()) ck_list += ", ";
        ck_list += db + "." + tbl;
      }
    }
    if (!ck_list.empty()) {
      util::append_file(out, "## CHECKSUMS " + db + "\n");
      util::sh(cfg::BASEDIR + "/bin/mariadb -uroot -S\"" + sock + "\" -Nse \"CHECKSUM TABLE " + ck_list + " EXTENDED\" 2>&1 | sort >> \"" + out + "\"");
    }
    util::append_file(out, "## ROUTINES " + db + "\n");
    util::sh(cfg::BASEDIR + "/bin/mariadb -uroot -S\"" + sock + "\" -Nse \"SELECT routine_type, routine_name FROM information_schema.routines WHERE routine_schema='" + db + "' ORDER BY routine_type, routine_name\" >> \"" + out + "\" 2>&1");
    std::string rs = util::sh_capture(cfg::BASEDIR + "/bin/mariadb -uroot -S\"" + sock + "\" -Nse \"SELECT routine_type, routine_name FROM information_schema.routines WHERE routine_schema='" + db + "' ORDER BY routine_type, routine_name\" 2>/dev/null");
    for (const auto& row : util::split(rs, '\n')) {
      auto tab = row.find('\t');
      if (tab == std::string::npos) continue;
      std::string rt = row.substr(0, tab); std::string rn = row.substr(tab + 1);
      if (rn.empty()) continue;
      util::sh(cfg::BASEDIR + "/bin/mariadb -uroot -S\"" + sock + "\" -Nse \"SHOW CREATE " + rt + " \\`" + db + "\\`.\\`" + rn + "\\`\" >> \"" + out + "\" 2>&1");
    }
    util::append_file(out, "## TRIGGERS " + db + "\n");
    util::sh(cfg::BASEDIR + "/bin/mariadb -uroot -S\"" + sock + "\" -Nse \"SHOW TRIGGERS FROM \\`" + db + "\\`\" >> \"" + out + "\" 2>&1");
    util::append_file(out, "## EVENTS " + db + "\n");
    util::sh(cfg::BASEDIR + "/bin/mariadb -uroot -S\"" + sock + "\" -Nse \"SHOW EVENTS FROM \\`" + db + "\\`\" >> \"" + out + "\" 2>&1");
  }
  return true;
}

static bool mode11_do_dump(const std::string& sock, const std::string& dest) {
  std::string user_dbs = util::sh_capture_trimmed(
    cfg::BASEDIR + "/bin/mariadb -uroot -S\"" + sock +
    "\" -Nse \"SELECT GROUP_CONCAT(schema_name SEPARATOR ' ') FROM information_schema.schemata WHERE schema_name NOT IN ('mysql','information_schema','performance_schema','sys')\" 2>/dev/null");
  if (user_dbs.empty() || user_dbs == "NULL") {
    util::write_file(dest, "");
    return true;
  }
  diskspace(fs::path(dest).parent_path().string());
  int rc = util::sh(cfg::BASEDIR + "/bin/mariadb-dump -uroot -S\"" + sock +
                    "\" --force --hex-blob --routines --triggers --events --skip-dump-date --skip-comments --databases " +
                    user_dbs + " > \"" + dest + "\" 2> \"" + state::WORKD + "/mode11_dump.err\"");
  return rc == 0;
}

static bool mode11_capture_binlogs(const std::string& sock, const std::string& datadir, const std::string& dest) {
  fs::remove_all(dest);
  util::mkdir_p(dest);
  util::sh(cfg::BASEDIR + "/bin/mariadb -uroot -S\"" + sock + "\" -Nse \"FLUSH LOGS\" >/dev/null 2>&1");
  std::string files = util::sh_capture(cfg::BASEDIR + "/bin/mariadb -uroot -S\"" + sock + "\" -Nse \"SHOW BINARY LOGS\" 2>/dev/null | awk '{print $1}'");
  if (files.empty()) { echoit("[MODE11] SHOW BINARY LOGS returned nothing — server not started with --log_bin?"); return false; }
  for (const auto& f : util::split(files, '\n')) {
    if (f.empty()) continue;
    if (util::sh("cp -a \"" + datadir + "/" + f + "\" \"" + dest + "/\" 2>/dev/null") != 0) {
      echoit("[MODE11] failed to copy binlog " + f); return false;
    }
  }
  return true;
}

static bool mode11_replay_binlogs(const std::string& sock, const std::string& src) {
  std::string files = util::sh_capture("ls -1 \"" + src + "\" 2>/dev/null | sort");
  if (files.empty()) { echoit("[MODE11] no binlog files in " + src); return false; }
  diskspace(state::WORKD);
  std::string cmd = "( cd \"" + src + "\" && " + cfg::BASEDIR + "/bin/mariadb-binlog --disable-log-bin ";
  for (const auto& f : util::split(files, '\n')) if (!f.empty()) cmd += f + " ";
  cmd += "2>\"" + state::WORKD + "/mode11_replay_binlog.err\" ) | " + cfg::BASEDIR + "/bin/mariadb -uroot -S\"" + sock +
         "\" --binary-mode --force > \"" + state::WORKD + "/mode11_replay.out\" 2> \"" + state::WORKD + "/mode11_replay.err\"";
  util::sh(cmd);
  return true;
}

// process_outcome — mirror reducer.sh:3709..4378 (the entire dispatch over MODE 0/1/2/3/4/5/6/7/8/9/11)
static int process_outcome_impl() {
  if (state::NOISSUEFLOW < 0) state::NOISSUEFLOW = 0;
  // MODE 0
  if (cfg::MODE == 0) {
    if (state::MYSQLD_START_TIME.empty()) {
      std::cerr << "Assert: MYSQLD_START_TIME==''\nTerminating now.\n"; std::exit(1);
    }
    state::RUN_TIME = std::time(nullptr) - std::stoll(state::MYSQLD_START_TIME);
    int issue_found = 0;
    if (state::RUN_TIME >= state::TIMEOUT_CHECK_REAL) issue_found = 1;
    if (issue_found == 1 && util::file_readable(state::WORKT)) {
      long long pre_shutdown = state::RUN_TIME - state::SHUTDOWN_DURATION;
      long long sql_lines = 0;
      try { sql_lines = std::stoll(util::sh_capture_trimmed(
        "grep -E --binary-files=text -cv '^[[:space:]]*(#|--|$)' \"" + state::WORKT + "\" 2>/dev/null || echo 0")); } catch (...) {}
      if (sql_lines == 0 && pre_shutdown < state::TIMEOUT_CHECK_REAL) {
        echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [Trial " + std::to_string(state::TRIAL) +
               "] [M0-FP-Suppressed] WORKT has no SQL lines and PRE_SHUTDOWN_RUNTIME=" + std::to_string(pre_shutdown) +
               "s < TIMEOUT_CHECK_REAL=" + std::to_string(state::TIMEOUT_CHECK_REAL) + "s; shutdown-latency-only spike — not treating as bug");
        issue_found = 0;
      }
    }
    if (issue_found == 1) {
      if (state::STAGE != "V") {
        echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [Trial " + std::to_string(state::TRIAL) +
               "] [*TimeoutBug*] [" + std::to_string(state::NOISSUEFLOW) + "] Swapping files & saving last known good timeout issue in " + state::WORKO);
        control_backtrack_flow();
      }
      cleanup_and_save();
      return 1;
    } else {
      if (state::STAGE != "V") {
        echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [Trial " + std::to_string(state::TRIAL) +
               "] [NoTimeoutBug] [" + std::to_string(state::NOISSUEFLOW) + "] Kill server " + state::NEXTACTION);
        state::NOISSUEFLOW++;
      }
      return 0;
    }
  }
  // MODE 1 — Valgrind
  else if (cfg::MODE == 1) {
    echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [Trial " + std::to_string(state::TRIAL) + "] Waiting for Valgrind to terminate analysis");
    while (true) {
      std::this_thread::sleep_for(std::chrono::seconds(1));
      util::sh("sync");
      if (util::sh("grep -E --binary-files=text -q \"ERROR SUMMARY\" \"" + state::WORKD + "/valgrind.out\"") == 0) break;
    }
    if (util::sh("grep -E --binary-files=text -iq \"" + cfg::TEXT + "\" \"" + state::WORKD + "/valgrind.out\" " + state::WORKD + "/log/*.err") == 0) {
      if (state::STAGE != "V") {
        echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [Trial " + std::to_string(state::TRIAL) +
               "] [*ValgrindBug*] [" + std::to_string(state::NOISSUEFLOW) + "] Swapping files & saving last known good Valgrind issue in " + state::WORKO);
        control_backtrack_flow();
      }
      cleanup_and_save();
      return 1;
    } else {
      if (state::STAGE != "V") {
        echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [Trial " + std::to_string(state::TRIAL) +
               "] [NoValgrindBug] [" + std::to_string(state::NOISSUEFLOW) + "] Kill server " + state::NEXTACTION);
        state::NOISSUEFLOW++;
      }
      return 0;
    }
  }
  // MODE 2 — CLI / pquery client output
  else if (cfg::MODE == 2) {
    std::string filetocheck, filetocheck2;
    if (cfg::USE_PQUERY == 1) {
      filetocheck  = state::WORKD + "/log/default.node.tld_thread-0.out";
      filetocheck2 = state::WORKD + "/default.node.tld_thread-0.sql";
    } else {
      filetocheck  = state::WORKD + "/log/mysql.out";
    }
    int occ = 0;
    if (state::QCTEXT.empty()) {
      if (cfg::USE_PQUERY == 1) {
        std::string n = util::sh_capture_trimmed("grep -E --binary-files=text -l \"" + cfg::TEXT + "\" \"" + filetocheck + "\" \"" + filetocheck2 + "\" 2>/dev/null | wc -l");
        try { if (std::stoi(n) > 0) occ = 1; } catch (...) {}
      } else {
        std::string n = util::sh_capture_trimmed("grep -E --binary-files=text -c \"" + cfg::TEXT + "\" \"" + filetocheck + "\" 2>/dev/null");
        try { if (std::stoi(n) > 0) occ = 1; } catch (...) {}
      }
    } else {
      std::string nl = util::sh_capture_trimmed(
        "grep -E --binary-files=text \"" + state::QCTEXT + "\" \"" + filetocheck2 + "\" | grep -E --binary-files=text -o \"#[0-9]+$\" | sed 's/#//g'");
      std::string n = util::sh_capture_trimmed("grep -E --binary-files=text -c \"" + cfg::TEXT + "#" + nl + "$\" \"" + filetocheck + "\" 2>/dev/null");
      try { if (std::stoi(n) > 0) occ = 1; } catch (...) {}
    }
    if (occ == 1) {
      if (state::STAGE != "V") {
        echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [Trial " + std::to_string(state::TRIAL) +
               "] [*ClientOutputBug*] [" + std::to_string(state::NOISSUEFLOW) + "] Swapping files & saving last known good client output issue in " + state::WORKO);
        control_backtrack_flow();
      }
      cleanup_and_save(); return 1;
    } else {
      if (state::STAGE != "V") {
        echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [Trial " + std::to_string(state::TRIAL) +
               "] [NoClientOutputBug] [" + std::to_string(state::NOISSUEFLOW) + "] Kill server " + state::NEXTACTION);
        state::NOISSUEFLOW++;
      }
      return 0;
    }
  }
  // MODE 3 — error log text search (or NewTextString / GLIBC / PQUERY_CONS_Q_FAIL)
  else if (cfg::MODE == 3) {
    int issue_found = 0;
    std::string output_text;
    std::string errorlog;
    if (cfg::MDG == 1 || cfg::GRP_RPL == 1) {
      errorlog = state::WORKD + "/node" + std::to_string(cfg::GALERA_NODE) + "/node" + std::to_string(cfg::GALERA_NODE) + ".err";
      util::sh("sudo chmod 777 " + errorlog);
    } else {
      errorlog = state::WORKD + "/log/*.err";
    }
    if (cfg::REDUCE_GLIBC_OR_SS_CRASHES > 0) {
      output_text = "ConsoleTypescript";
      std::string ts = "/tmp/reducer_typescript" + state::TYPESCRIPT_UNIQUE_FILESUFFIX + ".log";
      if (util::sh("grep -E --binary-files=text -iq '*** Error in' \"" + ts + "\"") == 0) {
        if (util::sh("grep -E --binary-files=text -iq \"" + cfg::TEXT + "\" \"" + ts + "\"") == 0) issue_found = 1;
      }
      if (util::sh("grep -E --binary-files=text -iq '*** stack smashing' \"" + ts + "\"") == 0) {
        if (util::sh("grep -E --binary-files=text -iq \"" + cfg::TEXT + "\" \"" + ts + "\"") == 0) issue_found = 1;
      }
    } else if (cfg::PQUERY_CONS_Q_FAIL == 1) {
      output_text = "LastConsecutiveQueriesAllFailed";
      if (util::sh("grep -E --binary-files=text -iq \"" + cfg::TEXT + "\" \"" + state::WORKD + "/pquery.out\"") == 0) issue_found = 1;
    } else if (cfg::USE_NEW_TEXT_STRING == 1) {
      output_text = "NewTextString";
      fs::remove(state::WORKD + "/MYBUG.FOUND");
      util::write_file(state::WORKD + "/MYBUG.FOUND", "");
      std::string savepath = fs::current_path().string();
      fs::current_path(state::WORKD);
      if (cfg::MDG == 1) {
        setenv("GALERA_ERROR_LOG", (state::WORKD + "/node" + std::to_string(cfg::GALERA_NODE) + "/node" + std::to_string(cfg::GALERA_NODE) + ".err").c_str(), 1);
        setenv("GALERA_CORE_LOC", (state::WORKD + "/node" + std::to_string(cfg::GALERA_NODE) + "/*core*").c_str(), 1);
      }
      // Top-SAN dropping
      if (util::sh("grep --binary-files=text -qiE \"=ERROR:|runtime error:|AddressSanitizer:|ThreadSanitizer:|LeakSanitizer:|MemorySanitizer:\" " +
                   state::WORKD + "/log/*.err " + state::WORKD + "/node*/node*.err 2>/dev/null") == 0) {
        std::string flag = util::sh_capture_trimmed("echo \"" + cfg::INPUTFILE + "\" | sed 's|/default.node.tld.*|/TOP_SAN_ISSUES_REMOVED|'");
        if (util::file_readable(flag)) {
          echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [Trial " + std::to_string(state::TRIAL) +
                 "] TOP_SAN_ISSUES_REMOVED flag file found: dropping any known *SAN bugs from the top of the error log");
          std::string drop_script = cfg::SCRIPT_PWD + "/drop_one_or_more_san_from_log.sh";
          if (util::file_readable(drop_script)) util::sh(drop_script);
          else {
            drop_script = util::getenv_or("HOME") + "/mariadb-qa/drop_one_or_more_san_from_log.sh";
            if (util::file_readable(drop_script)) util::sh(drop_script);
            else { std::cerr << "Assert: drop_one_or_more_san_from_log.sh not found\n"; std::exit(1); }
          }
        }
      }
      // Single-shot capture of stdout AND exit code, mirroring bash's
      // `MYBUGFOUND="$(...)" ; NTSEXITCODE=${?}`. Two invocations is unsafe
      // for sporadic bugs (different exit codes possible).
      std::string mybug;
      int nts_rc = 0;
      {
        std::string cmd = cfg::TEXT_STRING_LOC + " \"" + state::BIN + "\" 2>/dev/null";
        // Fork + bash -c so we capture both stdout and exit code via /bin/bash
        // (not /bin/sh -> dash). One-shot equivalent of bash command-substitution
        // + $? read.
        int pipefd[2];
        if (pipe(pipefd) == 0) {
          pid_t pid = fork();
          if (pid == 0) {
            close(pipefd[0]); dup2(pipefd[1], 1); close(pipefd[1]);
            execl("/bin/bash", "bash", "-c", cmd.c_str(), (char*)nullptr);
            _exit(127);
          }
          close(pipefd[1]);
          char buf[4096]; ssize_t n;
          while ((n = read(pipefd[0], buf, sizeof(buf))) > 0) mybug.append(buf, static_cast<size_t>(n));
          close(pipefd[0]);
          int status = 0; waitpid(pid, &status, 0);
          if (WIFEXITED(status)) nts_rc = WEXITSTATUS(status);
        }
        while (!mybug.empty() && (mybug.back() == '\n' || mybug.back() == '\r')) mybug.pop_back();
      }
      util::append_file(state::WORKD + "/MYBUG.FOUND", mybug + "\n");
      util::write_file(state::WORKD + "/MYBUG.FOUND.EXITCODE", std::to_string(nts_rc) + "\n");
      int skip_newbug = 0;
      if (nts_rc != 0) {
        if (util::sh("grep --binary-files=text -qi 'no core file' \"" + state::WORKD + "/MYBUG.FOUND\"") == 0) {
          skip_newbug = 1;
        } else if (util::sh("grep --binary-files=text -qi 'Assert: No parsable frames' \"" + state::WORKD + "/MYBUG.FOUND\"") == 0) {
          std::this_thread::sleep_for(std::chrono::microseconds(10));
        } else {
          echoit("Assert: exit code for " + cfg::TEXT_STRING_LOC + " was not 0; this should not happen. Exitcode was " +
                 std::to_string(nts_rc) + " and message was; '" + util::read_file(state::WORKD + "/MYBUG.FOUND") + "'. Please check files in " +
                 state::WORKD + ". Terminating.");
          skip_newbug = 1;
          std::exit(1);
        }
      }
      fs::current_path(savepath);
      // Match TEXT against MYBUG.FOUND
      std::string findbug;
      if (cfg::MODE3_ANY_SIG != 1) {
        findbug = util::sh_capture_trimmed("grep -Fi --binary-files=text \"" + cfg::TEXT + "\" \"" + state::WORKD + "/MYBUG.FOUND\"");
      } else {
        findbug = util::sh_capture_trimmed("grep -i --binary-files=text \"^SIG\" \"" + state::WORKD + "/MYBUG.FOUND\"");
      }
      if (!findbug.empty()) {
        issue_found = 1;
      } else if (cfg::SCAN_FOR_NEW_BUGS == 1 && skip_newbug != 1 && nts_rc == 0) {
        // Search BOTH the main known-bugs file AND the sanitizer-specific
        // file. Without the .SAN file in the grep, every ASAN/UBSAN/TSAN/MSAN
        // /LSAN UniqueID (which lives in known_bugs.strings.SAN) is treated
        // as a brand-new bug — flooding /data/NEWBUGS with duplicates.
        std::string filt_files = "\"" + cfg::KNOWN_BUGS_LOC + "\"";
        if (!cfg::KNOWN_BUGS_LOC_SAN.empty() && util::file_readable(cfg::KNOWN_BUGS_LOC_SAN)) {
          filt_files += " \"" + cfg::KNOWN_BUGS_LOC_SAN + "\"";
        }
        findbug = util::sh_capture_trimmed("grep -hFi --binary-files=text \"" + mybug + "\" " + filt_files + " | head -n1");
        if (util::starts_with(findbug, "#")) findbug.clear();
        if (findbug.empty()) {
          echoit("[NewBug] Reducer located a new bug while reducing this issue: " + util::sh_capture_trimmed("head -n1 \"" + state::WORKD + "/MYBUG.FOUND\" 2>/dev/null"));
          std::string epoch_ran = util::sh_capture_trimmed("date +%H%M%S%N") + util::rand_suffix();
          std::string newbug_so, newbug_to, newbug_re, newbug_vm;
          if (!cfg::NEW_BUGS_SAVE_DIR.empty()) {
            if (!util::dir_exists(cfg::NEW_BUGS_SAVE_DIR)) {
              std::cerr << "Assert: NEW_BUGS_SAVE_DIR missing.\nTerminating now.\n"; std::exit(1);
            }
            newbug_so = cfg::NEW_BUGS_SAVE_DIR + "/newbug_" + epoch_ran + ".sql";
            newbug_to = cfg::NEW_BUGS_SAVE_DIR + "/newbug_" + epoch_ran + ".string";
            newbug_re = cfg::NEW_BUGS_SAVE_DIR + "/newbug_" + epoch_ran + ".reducer.sh";
            newbug_vm = cfg::NEW_BUGS_SAVE_DIR + "/newbug_" + epoch_ran + ".varmod";
          } else {
            newbug_so = cfg::INPUTFILE + "_newbug_" + epoch_ran + ".sql";
            newbug_to = cfg::INPUTFILE + "_newbug_" + epoch_ran + ".string";
            newbug_re = cfg::INPUTFILE + "_newbug_" + epoch_ran + ".reducer.sh";
            newbug_vm = cfg::INPUTFILE + "_newbug_" + epoch_ran + ".varmod";
          }
          if (cfg::RR_TRACING == 1) {
            save_rr_trace(cfg::NEW_BUGS_SAVE_DIR + "/" + epoch_ran + "_rr_trace");
            echoit("[NewBug] Saved RR trace in " + cfg::NEW_BUGS_SAVE_DIR + "/" + epoch_ran + "_rr_trace");
          }
          diskspace(cfg::NEW_BUGS_SAVE_DIR);
          util::sh("cp \"" + state::WORKT + "\" \"" + newbug_so + "\"");
          echoit("[NewBug] Saved the new testcase to: " + newbug_so);
          util::sh("cp \"" + state::WORKD + "/MYBUG.FOUND\" \"" + newbug_to + "\"");
          echoit("[NewBug] Saved the Unique bug ID to: " + newbug_to);
          // newbug_re is a bash reducer thin-wrapper (matching the canonical
          // reducer_cpp.sh layout) populated with the newbug's #VARMOD# values.
          // Generating a bash file rather than copying the C++ binary preserves
          // framework compatibility: pquery-go-expert.sh, watchdog.sh, ~/ds all
          // expect newbug_*.reducer.sh to be a shell script with variable
          // assignments. The wrapper exec'es the C++ binary internally.
          {
            // Locate the reducer_cpp.sh template — try SCRIPT_PWD, the binary's
            // dir, $HOME/mariadb-qa/, then fall back to the bash reducer.sh.
            std::string tpl;
            for (const auto& cand : { cfg::SCRIPT_PWD + "/reducer_cpp.sh",
                                       util::getenv_or("HOME") + "/mariadb-qa/reducer_cpp.sh",
                                       cfg::SCRIPT_PWD + "/reducer.sh",
                                       util::getenv_or("HOME") + "/mariadb-qa/reducer.sh" }) {
              if (util::file_readable(cand)) { tpl = cand; break; }
            }
            if (tpl.empty()) {
              echoit("[NewBug] Warning: no reducer template (reducer_cpp.sh / reducer.sh) found; saving raw binary copy as fallback");
              util::sh("cp \"" + state::THIS_REDUCER + "\" \"" + newbug_re + "\"");
            } else {
              // Read template, then rewrite in-memory: replace the canonical
              // VAR=value lines with comments, inject Machine-section overrides
              // before #VARMOD#. Doing this via direct file edits (not sed)
              // avoids the bash-side delimiter-selection ladder needed for
              // TEXT strings containing `:`, `|`, `/`, etc.
              std::string content = util::read_file(tpl);
              // Comment out the lines that will be overridden by VARMOD inject.
              auto comment_var = [&](const std::string& var) {
                std::regex pat("(^|\n)[ \t]*" + var + "[ \t]*=[^\n]*");
                content = std::regex_replace(content, pat,
                  "$1#" + var + "=<set_below_in_machine_variables_section>",
                  std::regex_constants::format_first_only);
              };
              for (const auto& v : { "INPUTFILE", "MODE", "BASEDIR", "MYEXTRA",
                                     "REPLICATION", "REPL_EXTRA", "MASTER_EXTRA",
                                     "SLAVE_EXTRA", "FORCE_SKIPV",
                                     "MULTI_THREADS_INCREASE", "MULTI_THREADS_MAX",
                                     "STAGE1_LINES", "FIREWORKS" }) {
                comment_var(v);
              }
              // Build the Machine-section injection block. Mirror bash
              // newbug VARMOD layout exactly. Bash-escape " in mybug (only
              // common metachar we need to handle for inline TEXT=).
              std::string esc_mybug = mybug;
              esc_mybug = util::replace_all(esc_mybug, "\\", "\\\\");
              esc_mybug = util::replace_all(esc_mybug, "\"", "\\\"");
              std::string esc_myextra = util::replace_all(cfg::MYEXTRA, "\"", "\\\"");
              std::ostringstream vm_block;
              vm_block << "MULTI_REDUCER=1\n"
                       << "INPUTFILE=\"" << newbug_so << "\"\n"
                       << "MODE=" << cfg::MODE << "\n"
                       << "   TEXT=\"" << esc_mybug << "\"\n"
                       << "MYEXTRA=\"--no-defaults " << esc_myextra << "\"\n"
                       << "BASEDIR=\"" << cfg::BASEDIR << "\"\n"
                       << "REPLICATION=" << cfg::REPLICATION << "\n"
                       << "REPL_EXTRA=\"" << cfg::REPL_EXTRA << "\"\n"
                       << "MASTER_EXTRA=\"" << cfg::MASTER_EXTRA << "\"\n"
                       << "SLAVE_EXTRA=\"" << cfg::SLAVE_EXTRA << "\"\n"
                       << "FORCE_SKIPV=0\n"
                       << "MULTI_THREADS_INCREASE=1\n"
                       << "MULTI_THREADS_MAX=5\n"
                       << "STAGE1_LINES=15\n"
                       << "FIREWORKS=0\n";
              // Replace the first #VARMOD# line with vm_block + #VARMOD#
              std::string marker = "\n#VARMOD#";
              auto pos = content.find(marker);
              if (pos != std::string::npos) {
                content = content.substr(0, pos + 1) + vm_block.str() + content.substr(pos + 1);
              }
              util::write_file(newbug_re, content);
            }
            // Also drop the .varmod file alongside (matches bash convention; some
            // upstream tools key off the .varmod for newbug categorization).
            std::ostringstream vm;
            vm << "MULTI_REDUCER=1\nINPUTFILE=" << newbug_so << "\nMODE=" << cfg::MODE
               << "\nTEXT=\"" << mybug << "\"\nMYEXTRA=\"--no-defaults " << cfg::MYEXTRA << "\"\n"
               << "BASEDIR=\"" << cfg::BASEDIR << "\"\nREPLICATION=" << cfg::REPLICATION
               << "\nREPL_EXTRA=\"" << cfg::REPL_EXTRA << "\"\nMASTER_EXTRA=\"" << cfg::MASTER_EXTRA << "\"\n"
               << "SLAVE_EXTRA=\"" << cfg::SLAVE_EXTRA << "\"\nFORCE_SKIPV=0\nMULTI_THREADS_INCREASE=1\n"
               << "MULTI_THREADS_MAX=5\nSTAGE1_LINES=15\nFIREWORKS=0\n";
            util::write_file(newbug_vm, vm.str());
          }
          util::sh("chmod +x \"" + newbug_re + "\"");
          echoit("[NewBug] Saved the new bug reducer to: " + newbug_re);
        }
      }
    } else {
      output_text = "ErrorLog";
      if (util::sh("grep -E --binary-files=text -iq \"" + cfg::TEXT + "\" " + errorlog) == 0) issue_found = 1;
    }
    if (issue_found == 1) {
      if (state::STAGE != "V" && cfg::FIREWORKS != 1) {
        echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [Trial " + std::to_string(state::TRIAL) +
               "] [*" + output_text + "OutputBug*] [" + std::to_string(state::NOISSUEFLOW) + "] Swapping files & saving last known good testcase in " + state::WORKO);
        control_backtrack_flow();
      }
      std::this_thread::sleep_for(std::chrono::seconds(2));
      util::sh("sync");
      cleanup_and_save(); return 1;
    } else {
      if (state::STAGE != "V") {
        echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [Trial " + std::to_string(state::TRIAL) +
               "] [No" + output_text + "OutputBug] [" + std::to_string(state::NOISSUEFLOW) + "] Kill server " + state::NEXTACTION);
        state::NOISSUEFLOW++;
      }
      return 0;
    }
  }
  // MODE 4 — crash testing
  else if (cfg::MODE == 4) {
    std::string admin = cfg::BASEDIR + "/bin/mariadb-admin";
    if (!util::file_readable(admin)) admin = cfg::BASEDIR + "/bin/mysqladmin";
    int issue_found = 0;
    if (cfg::MDG == 1) {
      for (int i = 1; i <= cfg::NR_OF_NODES; ++i) {
        if (cfg::MDG_ISSUE_NODE == 0 || cfg::MDG_ISSUE_NODE == i) {
          if (util::sh(admin + " -uroot --socket=" + state::WORKD + "/node" + std::to_string(i) + "/node" + std::to_string(i) + "_socket.sock ping > /dev/null 2>&1") != 0)
            issue_found = 1;
        }
      }
    } else if (cfg::GRP_RPL == 1) {
      auto check_node = [&](int n, const std::string& socket_path) {
        if (cfg::GRP_RPL_ISSUE_NODE == 0 || cfg::GRP_RPL_ISSUE_NODE == n) {
          if (util::sh(admin + " -uroot --socket=" + socket_path + " ping > /dev/null 2>&1") != 0) issue_found = 1;
        }
      };
      check_node(1, state::node1 + "/node1_socket.sock");
      check_node(2, state::node2 + "/node2_socket.sock");
      check_node(3, state::node3 + "/node3_socket.sock");
    } else if (cfg::REDUCE_GLIBC_OR_SS_CRASHES > 0) {
      std::string ts = "/tmp/reducer_typescript" + state::TYPESCRIPT_UNIQUE_FILESUFFIX + ".log";
      if (util::sh("grep -E --binary-files=text -iq '*** Error in' \"" + ts + "\"") == 0) issue_found = 1;
      if (util::sh("grep -E --binary-files=text -iq '*** stack smashing' \"" + ts + "\"") == 0) issue_found = 1;
    } else {
      if (util::sh(admin + " -uroot -S" + state::WORKD + "/socket.sock ping > /dev/null 2>&1") != 0) issue_found = 1;
    }
    std::string output_text = (cfg::REDUCE_GLIBC_OR_SS_CRASHES > 0) ? "GlibcCrash" : "Crash";
    if (issue_found == 1) {
      if (state::STAGE != "V") {
        if (state::STAGE == "6") {
          echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [Trial " + std::to_string(state::TRIAL) +
                 "] [Column " + std::to_string(state::COLUMN) + "/" + std::to_string(state::COUNTCOLS) +
                 "] [*" + output_text + "*] Swapping files & saving last known good crash in " + state::WORKO);
        } else {
          echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [Trial " + std::to_string(state::TRIAL) +
                 "] [*" + output_text + "*] [" + std::to_string(state::NOISSUEFLOW) + "] Swapping files & saving last known good crash in " + state::WORKO);
        }
        control_backtrack_flow();
      }
      cleanup_and_save(); return 1;
    } else {
      if (state::STAGE != "V") {
        if (state::STAGE == "6") {
          echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [Trial " + std::to_string(state::TRIAL) +
                 "] [Column " + std::to_string(state::COLUMN) + "/" + std::to_string(state::COUNTCOLS) +
                 "] [No" + output_text + "] Kill server " + state::NEXTACTION);
        } else {
          echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [Trial " + std::to_string(state::TRIAL) +
                 "] [No" + output_text + "] [" + std::to_string(state::NOISSUEFLOW) + "] Kill server " + state::NEXTACTION);
        }
        state::NOISSUEFLOW++;
      }
      return 0;
    }
  }
  // MODE 5 — MTR
  else if (cfg::MODE == 5) {
    int t_count = 0, addl_count = 0;
    try { t_count = std::stoi(util::sh_capture_trimmed("grep -E --binary-files=text -ic \"" + cfg::TEXT + "\" \"" + state::WORKD + "/log/mysql.out\"")); } catch (...) {}
    if (t_count >= cfg::MODE5_COUNTTEXT) {
      try { addl_count = std::stoi(util::sh_capture_trimmed("grep -E --binary-files=text -ic \"" + cfg::MODE5_ADDITIONAL_TEXT + "\" \"" + state::WORKD + "/log/mysql.out\"")); } catch (...) {}
      if (addl_count >= cfg::MODE5_ADDITIONAL_COUNTTEXT) {
        if (state::STAGE != "V") {
          echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [Trial " + std::to_string(state::TRIAL) +
                 "] [*MTRCaseOutputBug*] [" + std::to_string(state::NOISSUEFLOW) + "] Swapping files & saving last known good MTR testcase output issue in " + state::WORKO);
          control_backtrack_flow();
        }
        cleanup_and_save(); return 1;
      }
    }
    if (state::STAGE != "V") {
      echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [Trial " + std::to_string(state::TRIAL) +
             "] [NoMTRCaseOutputBug] [" + std::to_string(state::NOISSUEFLOW) + "] Kill server " + state::NEXTACTION);
      state::NOISSUEFLOW++;
    }
    return 0;
  }
  // MODE 6 — ThreadSync Valgrind
  else if (cfg::MODE == 6) {
    echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [Trial " + std::to_string(state::TRIAL) + "] Waiting for Valgrind to terminate analysis");
    while (true) {
      std::this_thread::sleep_for(std::chrono::seconds(1));
      util::sh("sync");
      if (util::sh("grep -E --binary-files=text -q \"ERROR SUMMARY\" \"" + state::WORKD + "/valgrind.out\"") == 0) break;
    }
    if (util::sh("grep -E --binary-files=text -iq \"" + cfg::TEXT + "\" \"" + state::WORKD + "/valgrind.out\"") == 0) {
      if (state::STAGE == "T") {
        echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [Trial " + std::to_string(state::TRIAL) +
               "] [*TSValgrindBug*] [" + std::to_string(state::NOISSUEFLOW) + "] Swapping files & saving last known good Valgrind issue thread file(s) in " + state::WORKD + "/log/");
      } else if (state::STAGE != "V") {
        echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [Trial " + std::to_string(state::TRIAL) +
               "] [*TSValgrindBug*] [" + std::to_string(state::NOISSUEFLOW) + "] Swapping files & saving last known good Valgrind issue thread file(s) in " + state::WORKD + "/out/");
        control_backtrack_flow();
      }
      cleanup_and_save(); return 1;
    } else {
      if (state::STAGE != "V" && state::STAGE != "T") {
        echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [Trial " + std::to_string(state::TRIAL) +
               "] [NoTSValgrindBug] [" + std::to_string(state::NOISSUEFLOW) + "] Kill server " + state::NEXTACTION);
        state::NOISSUEFLOW++;
      }
      return 0;
    }
  }
  // MODE 7 — ThreadSync CLI
  else if (cfg::MODE == 7) {
    if (util::sh("grep -E --binary-files=text -iq \"" + cfg::TEXT + "\" \"" + state::WORKD + "/log/mysql.out\"") == 0) {
      if (state::STAGE == "T") {
        echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [Trial " + std::to_string(state::TRIAL) +
               "] [*TSCLIOutputBug*] [" + std::to_string(state::NOISSUEFLOW) + "] Swapping files & saving last known good CLI output issue thread file(s) in " + state::WORKD + "/log/");
      } else if (state::STAGE != "V") {
        echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [Trial " + std::to_string(state::TRIAL) +
               "] [*TSCLIOutputBug*] [" + std::to_string(state::NOISSUEFLOW) + "] Swapping files & saving last known good CLI output issue thread file(s) in " + state::WORKD + "/out/");
        control_backtrack_flow();
      }
      cleanup_and_save(); return 1;
    } else {
      if (state::STAGE != "V" && state::STAGE != "T") {
        echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [Trial " + std::to_string(state::TRIAL) +
               "] [NoTSCLIOutputBug] [" + std::to_string(state::NOISSUEFLOW) + "] Kill server " + state::NEXTACTION);
        state::NOISSUEFLOW++;
      }
      return 0;
    }
  }
  // MODE 8 — ThreadSync error log
  else if (cfg::MODE == 8) {
    if (util::sh("grep -E --binary-files=text -iq \"" + cfg::TEXT + "\" " + state::WORKD + "/log/*.err") == 0) {
      if (state::STAGE == "T") {
        echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [Trial " + std::to_string(state::TRIAL) +
               "] [*TSErrorLogOutputBug*] [" + std::to_string(state::NOISSUEFLOW) + "] Swapping files & saving last known good error log output issue thread file(s) in " + state::WORKD + "/log/");
      } else if (state::STAGE != "V") {
        echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [Trial " + std::to_string(state::TRIAL) +
               "] [*TSErrorLogOutputBug*] [" + std::to_string(state::NOISSUEFLOW) + "] Swapping files & saving last known good error log output issue thread file(s) in " + state::WORKD + "/out/");
        control_backtrack_flow();
      }
      cleanup_and_save(); return 1;
    } else {
      if (state::STAGE != "V" && state::STAGE != "T") {
        echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [Trial " + std::to_string(state::TRIAL) +
               "] [NoTSErrorLogOutputBug] [" + std::to_string(state::NOISSUEFLOW) + "] Kill server " + state::NEXTACTION);
        state::NOISSUEFLOW++;
      }
      return 0;
    }
  }
  // MODE 9 — ThreadSync crash
  else if (cfg::MODE == 9) {
    std::string admin = cfg::BASEDIR + "/bin/mariadb-admin";
    if (!util::file_readable(admin)) admin = cfg::BASEDIR + "/bin/mysqladmin";
    if (util::sh(admin + " -uroot -S" + state::WORKD + "/socket.sock ping > /dev/null 2>&1") != 0) {
      if (state::STAGE == "T") {
        echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [Trial " + std::to_string(state::TRIAL) +
               "] [*TSCrash*] [" + std::to_string(state::NOISSUEFLOW) + "] Swapping files & saving last known good crash thread file(s) in " + state::WORKD + "/log/");
      } else if (state::STAGE != "V") {
        echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [Trial " + std::to_string(state::TRIAL) +
               "] [*TSCrash*] [" + std::to_string(state::NOISSUEFLOW) + "] Swapping files & saving last known good crash thread file(s) in " + state::WORKD + "/out/");
        control_backtrack_flow();
      }
      cleanup_and_save(); return 1;
    } else {
      if (state::STAGE != "V" && state::STAGE != "T") {
        echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [Trial " + std::to_string(state::TRIAL) +
               "] [NoTSCrash] [" + std::to_string(state::NOISSUEFLOW) + "] Kill server " + state::NEXTACTION);
        state::NOISSUEFLOW++;
      }
      return 0;
    }
  }
  // MODE 11 — dump/binlog roundtrip
  else if (cfg::MODE == 11) {
    std::string snap_before = state::WORKD + "/mode11_snap_before.txt";
    std::string snap_after  = state::WORKD + "/mode11_snap_after.txt";
    std::string dumpf       = state::WORKD + "/mode11_dump.sql";
    std::string bl_dir      = state::WORKD + "/mode11_binlogs";
    std::string sock        = state::WORKD + "/socket.sock";
    fs::remove(snap_before); fs::remove(snap_after); fs::remove(dumpf);
    fs::remove_all(bl_dir);
    util::sh(cfg::BASEDIR + "/bin/mariadb -uroot -S\"" + sock + "\" --force -Nse \"COMMIT\" >/dev/null 2>&1");
    if (!mode11_take_snapshot(sock, snap_before)) {
      echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [Trial " + std::to_string(state::TRIAL) + "] [MODE11-InfraErr] pre-roundtrip snapshot failed; skipping trial");
      return 0;
    }
    if (cfg::MODE11_TYPE == "dump") {
      if (!mode11_do_dump(sock, dumpf)) {
        echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [Trial " + std::to_string(state::TRIAL) + "] [MODE11-InfraErr] mariadb-dump failed; skipping trial");
        return 0;
      }
    } else {
      if (!mode11_capture_binlogs(sock, state::WORKD + "/data", bl_dir)) {
        echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [Trial " + std::to_string(state::TRIAL) + "] [MODE11-InfraErr] binlog capture failed; skipping trial");
        return 0;
      }
    }
    stop_mysqld_or_mdg();
    util::sh("sync");
    std::this_thread::sleep_for(std::chrono::seconds(2));
    init_mysql_dir();
    util::append_file(state::WORKD + "/log/master.err", "--- [MODE11] second mariadbd start attempt ---\n");
    start_mysqld_main();
    int up = 0;
    for (int r = 0; r < 60; ++r) {
      if (util::sh(cfg::BASEDIR + "/bin/mariadb -uroot -S\"" + sock + "\" -Nse \"SELECT 1\" >/dev/null 2>&1") == 0) { up = 1; break; }
      std::this_thread::sleep_for(std::chrono::milliseconds(500));
    }
    if (up != 1) {
      echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [Trial " + std::to_string(state::TRIAL) + "] [MODE11-InfraErr] second mysqld did not come up; skipping trial");
      return 0;
    }
    if (cfg::MODE11_TYPE == "dump") {
      diskspace(state::WORKD);
      util::sh(cfg::BASEDIR + "/bin/mariadb -uroot -S\"" + sock + "\" --binary-mode --force <\"" + dumpf + "\" > \"" + state::WORKD + "/mode11_restore.out\" 2> \"" + state::WORKD + "/mode11_restore.err\"");
    } else {
      if (!mode11_replay_binlogs(sock, bl_dir)) {
        echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [Trial " + std::to_string(state::TRIAL) + "] [MODE11-InfraErr] binlog replay failed; skipping trial");
        return 0;
      }
    }
    std::vector<std::string> err_files = (cfg::MODE11_TYPE == "binlog")
      ? std::vector<std::string>{state::WORKD + "/mode11_replay.err", state::WORKD + "/mode11_replay_binlog.err"}
      : std::vector<std::string>{state::WORKD + "/mode11_restore.err"};
    std::string replay_hit;
    for (const auto& f : err_files) {
      if (util::file_readable(f) && util::sh("grep --binary-files=text -qE '^ERROR [0-9]+|^ERROR:|^WARNING:' \"" + f + "\"") == 0) {
        replay_hit = f; break;
      }
    }
    if (!replay_hit.empty()) {
      if (state::STAGE != "V") {
        std::string first = util::sh_capture_trimmed("grep --binary-files=text -m1 -E '^ERROR [0-9]+|^ERROR:|^WARNING:' \"" + replay_hit + "\"");
        echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [Trial " + std::to_string(state::TRIAL) +
               "] [*DumpBinlogReplayError*] [" + std::to_string(state::NOISSUEFLOW) + "] MODE11_TYPE=" + cfg::MODE11_TYPE +
               " replay error found in " + replay_hit + " (first line: " + first + ")");
        control_backtrack_flow();
      }
      cleanup_and_save(); return 1;
    }
    if (!mode11_take_snapshot(sock, snap_after)) {
      echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [Trial " + std::to_string(state::TRIAL) + "] [MODE11-InfraErr] post-roundtrip snapshot failed; skipping trial");
      return 0;
    }
    if (util::sh("diff -q \"" + snap_before + "\" \"" + snap_after + "\" >/dev/null 2>&1") == 0) {
      if (state::STAGE != "V") {
        echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [Trial " + std::to_string(state::TRIAL) +
               "] [NoDumpDiff] [" + std::to_string(state::NOISSUEFLOW) + "] Kill server " + state::NEXTACTION);
        state::NOISSUEFLOW++;
      }
      return 0;
    } else {
      if (state::STAGE != "V") {
        echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [Trial " + std::to_string(state::TRIAL) +
               "] [*DumpBinlogDiff*] [" + std::to_string(state::NOISSUEFLOW) + "] MODE11_TYPE=" + cfg::MODE11_TYPE +
               " diff found. Swapping files & saving last known good diff; snapshots in " + state::WORKD + "/mode11_snap_{before,after}.txt");
        control_backtrack_flow();
      }
      cleanup_and_save(); return 1;
    }
  }
  else {
    echoit("Assert: invalid MODE (MODE=" + std::to_string(cfg::MODE) + ") discovered. Terminating.");
    std::exit(1);
  }
  return 0;
}

static void process_outcome() { (void)process_outcome_impl(); }
// stop_mysqld_or_mdg — mirror reducer.sh:4380..4500
static void stop_mysqld_or_mdg() {
  state::SHUTDOWN_TIME_START = std::time(nullptr);
  state::MODE0_MIN_SHUTDOWN_TIME = cfg::TIMEOUT_CHECK + 10;
  if (cfg::MDG == 1 || cfg::GRP_RPL == 1) {
    util::sh("( ps -def | grep -E 'n*.cnf' | grep " + state::EPOCH + " | awk '{print $2}' | xargs -I{} kill -9 {} >/dev/null 2>&1; ) >/dev/null 2>&1");
    std::this_thread::sleep_for(std::chrono::seconds(2));
    util::sh("sync");
  } else {
    if (cfg::FORCE_KILL == 1 && cfg::MODE != 0 && state::FIRST_MYSQLD_START_FLAG != 1) {
      while (true) {
        std::string kpids = state::PIDV;
        if (cfg::REPLICATION == 1) kpids = state::PIDV + " " + state::PIDV_SLAVE;
        if (util::sh("kill -0 " + kpids + " >/dev/null 2>&1") == 0) {
          std::this_thread::sleep_for(std::chrono::seconds(1));
          util::sh("( kill -9 " + kpids + " >/dev/null 2>&1; ) >/dev/null 2>&1");
        } else {
          break;
        }
      }
    } else {
      std::string admin = cfg::BASEDIR + "/bin/mariadb-admin";
      if (!util::file_readable(admin)) admin = cfg::BASEDIR + "/bin/mysqladmin";
      if (cfg::MODE == 0) {
        std::string min_to = std::to_string(state::MODE0_MIN_SHUTDOWN_TIME);
        util::sh("timeout -k" + min_to + " -s9 " + min_to + "s " + admin + " -uroot -S" + state::WORKD + "/socket.sock shutdown >> " + state::WORKD + "/log/mysqld.out 2>&1");
        if (cfg::REPLICATION == 1) {
          util::sh("timeout -k" + min_to + " -s9 " + min_to + "s " + admin + " -uroot -S" + state::WORKD + "/slave_socket.sock shutdown >> " + state::WORKD + "/log/mysqld_slave.out 2>&1");
        }
        if (util::sh("grep -qiE 'Access denied for user|Доступ закрыт для пользователя' " + state::WORKD + "/log/mysqld*.out") == 0) {
          echoit("Assert: Access denied for user detected (ref " + state::WORKD + "/log/mysqld*.out)");
        }
      } else {
        util::sh("timeout -k60 -s9 60s " + admin + " -uroot -S" + state::WORKD + "/socket.sock shutdown >> " + state::WORKD + "/log/mysqld.out 2>&1");
        if (cfg::REPLICATION == 1) {
          util::sh("timeout -k60 -s9 60s " + admin + " -uroot -S" + state::WORKD + "/slave_socket.sock shutdown >> " + state::WORKD + "/log/mysqld_slave.out 2>&1");
        }
        if (util::sh("grep -qiE 'Access denied for user|Доступ закрыт для пользователя' " + state::WORKD + "/log/mysqld*.out") == 0) {
          echoit("Assert: Access denied for user detected (ref " + state::WORKD + "/log/mysqld*.out)");
        }
      }
      if (cfg::MODE == 0 || cfg::MODE == 1 || cfg::MODE == 6) {
        std::this_thread::sleep_for(std::chrono::seconds(5));
      } else {
        std::this_thread::sleep_for(std::chrono::seconds(1));
      }
      std::string kpids = state::PIDV;
      if (cfg::REPLICATION == 1) kpids = state::PIDV + " " + state::PIDV_SLAVE;
      if (cfg::FIREWORKS == 1) {
        util::sh("( kill -9 " + kpids + " >/dev/null 2>&1; ) >/dev/null 2>&1");
        std::this_thread::sleep_for(std::chrono::milliseconds(20));
        while (true) {
          if (util::sh("kill -0 " + kpids + " >/dev/null 2>&1") == 0) {
            util::sh("( kill -9 " + kpids + " >/dev/null 2>&1; ) >/dev/null 2>&1");
            std::this_thread::sleep_for(std::chrono::seconds(1));
            if (util::sh("kill -0 " + kpids + " >/dev/null 2>&1") == 0) {
              echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [WARNING] Attempting to bring down server(s) with PID(s) " + kpids + " failed at least twice.");
            } else break;
          } else break;
        }
      } else {
        while (true) {
          std::this_thread::sleep_for(std::chrono::seconds(1));
          if (util::sh("kill -0 " + kpids + " >/dev/null 2>&1") == 0) {
            if (cfg::MODE == 0 || cfg::MODE == 1 || cfg::MODE == 6) {
              std::this_thread::sleep_for(std::chrono::seconds(5));
            } else {
              std::this_thread::sleep_for(std::chrono::seconds(2));
            }
            if (util::sh("kill -0 " + kpids + " >/dev/null 2>&1") == 0) {
              util::sh(admin + " -uroot -S" + state::WORKD + "/socket.sock shutdown >> " + state::WORKD + "/log/mysqld.out 2>&1");
              if (cfg::REPLICATION == 1) {
                util::sh(admin + " -uroot -S" + state::WORKD + "/slave_socket.sock shutdown >> " + state::WORKD + "/log/mysqld_slave.out 2>&1");
              }
              if (util::sh("grep -qiE 'Access denied for user|Доступ закрыт для пользователя' " + state::WORKD + "/log/mysqld*.out") == 0) {
                echoit("Assert: Access denied for user detected (ref " + state::WORKD + "/log/mysqld*.out)");
              }
            } else break;
            if (cfg::MODE == 0 || cfg::MODE == 1 || cfg::MODE == 6) {
              std::this_thread::sleep_for(std::chrono::seconds(5));
            } else {
              std::this_thread::sleep_for(std::chrono::seconds(2));
            }
            if (util::sh("kill -0 " + kpids + " >/dev/null 2>&1") == 0) {
              echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [WARNING] Attempting to bring down server(s) with PID(s) " + kpids + " failed at least twice. Is this server very busy?");
            } else break;
            std::this_thread::sleep_for(std::chrono::seconds(5));
            if (cfg::MODE != 1 && cfg::MODE != 6) {
              if (cfg::MODE == 0) {
                if ((std::time(nullptr) - state::SHUTDOWN_TIME_START) < state::MODE0_MIN_SHUTDOWN_TIME) {
                  continue;
                }
              }
              if (util::sh("kill -0 " + kpids + " >/dev/null 2>&1") == 0) {
                if (cfg::MODE != 0) {
                  echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [WARNING] Attempting to bring down server(s) with PID(s) " + kpids + " failed. Now forcing kill of mariadbd/mysqld");
                }
                util::sh("( kill -9 " + kpids + " >/dev/null 2>&1; ) >/dev/null 2>&1");
              } else break;
            }
          } else break;
        }
      }
    }
    state::PIDV.clear();
  }
  state::SHUTDOWN_DURATION = std::time(nullptr) - state::SHUTDOWN_TIME_START;
  state::RUN_TIME += state::SHUTDOWN_DURATION;
}
// finish — mirror reducer.sh:4501..4572
static void finish(const std::string& reason) {
  if (cfg::RR_TRACING == 1) {
    if (cfg::RR_SAVE_ALL_TRACES == 0) {
      save_rr_trace(state::WORK_BUG_DIR + "/rr/" + state::EPOCH + "_rr_trace");
      echoit("[Finish] Saved the final RR trace in " + state::WORK_BUG_DIR + "/rr/" + state::EPOCH + "_rr_trace");
    } else {
      echoit("[Finish] RR traces saved in                : " + state::WORK_BUG_DIR + "/rr");
    }
  }
  echoit("[Finish] Finalized reducing SQL input file (" + cfg::INPUTFILE + ")");
  echoit("[Finish] Number of server startups         : " + std::to_string(state::STARTUPCOUNT) + " (not counting subreducers)");
  echoit("[Finish] Reducer log                       : " + state::WORKD + "/reducer.log");
  if (!state::WORK_OUT.empty()) diskspace(fs::path(state::WORK_OUT).parent_path().string());
  if (!util::file_readable(state::WORKO)) {
    if (!state::WORK_OUT.empty()) util::sh("cp \"" + cfg::INPUTFILE + "\" \"" + state::WORK_OUT + "\"");
    echoit("[Finish] Final testcase                    : " + cfg::INPUTFILE + " (= input file; no optimizations were successful. " +
           std::to_string(util::count_lines(cfg::INPUTFILE)) + " lines)");
  } else {
    if (!state::WORK_OUT.empty()) util::sh("cp -f \"" + state::WORKO + "\" \"" + state::WORK_OUT + "\"");
    echoit("[Finish] Final testcase                    : " + state::WORKO + " (" +
           std::to_string(util::count_lines(state::WORKO)) + " lines)");
  }
  if (!state::WORK_BUG_DIR.empty()) {
    fs::remove(state::WORK_BUG_DIR + "/" + state::EPOCH + "_bug_bundle.tar.gz");
    diskspace(state::WORK_BUG_DIR);
    util::sh("(cd \"" + state::WORK_BUG_DIR + "\"; tar -zhcf " + state::EPOCH + "_bug_bundle.tar.gz " + state::EPOCH + "*)");
    echoit("[Finish] Final testcase bundle + scripts in: " + state::WORK_BUG_DIR);
  }
  echoit("[Finish] Final testcase for script use     : " + state::WORK_OUT + " (handy to use in combination with the scripts below)");
  echoit("[Finish] File containing datadir           : " + state::WORK_BASEDIR_FILE + " (All scripts below use this. Update this when basedir changes)");
  echoit("[Finish] Matching data dir init script     : " + state::WORK_INIT + " (This script will use /dev/shm/" + state::EPOCH + " as working directory)");
  echoit("[Finish] Matching startup script           : " + state::WORK_START + " (Starts mariadbd/mysqld with same options as used in reducer)");
  if (cfg::MODE >= 6 && cfg::MODE <= 9) {
    echoit("[Finish] Matching run script               : " + state::WORK_RUN + " (though you can look at this file for an example, implementation for MODE6+ is not finished yet)");
  } else {
    echoit("[Finish] Matching run script (CLI)         : " + state::WORK_RUN + " (executes the testcase via the mysql CLI)");
    echoit("[Finish] Matching startup script (pquery)  : " + state::WORK_RUN_PQUERY + " (executes the testcase via the pquery binary)");
  }
  echoit("[Finish] Remember; ASAN testcases may need : export ASAN_OPTIONS=quarantine_size_mb=512:atexit=0:detect_invalid_pointer_pairs=3:dump_instruction_bytes=1:abort_on_error=1:allocator_may_return_null=1");
  echoit("[Finish] Remember; UBSAN testcases may need: export UBSAN_OPTIONS=print_stacktrace=1");
  echoit("[Finish] Final testcase bundle tar ball    : " + state::EPOCH + "_bug_bundle.tar.gz (handy for upload to bug reports)");
  echoit("[Finish] Working directory was             : " + state::WORKD);
  if (state::MULTI_REDUCER != 1) {
    std::string opts_req = util::sh_capture_trimmed(
      "echo \"" + cfg::SPECIAL_MYEXTRA_OPTIONS + " " + cfg::MYEXTRA + "\" | sed \"s|[ \\t]\\+| |g;s|--sql_mode=|--sql_mode= |g;s|[ \\t]\\+| |g\"");
    std::string opts_no_spaces = util::sh_capture_trimmed("echo \"" + opts_req + "\" | sed 's| ||g'");
    if (!opts_no_spaces.empty()) {
      echoit("[Finish] mariadbd/mysqld options required for replay: " + opts_req +
             " (the testcase will not reproduce the issue without these options passed to mariadbd/mysqld)");
    }
    if (!cfg::MYINIT.empty()) {
      echoit("[Finish] mariadbd/mysqld initialization options reqd: " + cfg::MYINIT);
    }
    if (util::file_readable(state::WORKO)) {
      std::error_code ec;
      auto sz = fs::file_size(state::WORKO, ec);
      echoit("[Finish] Final testcase size               : " + std::to_string(ec ? 0 : sz) + " bytes (" +
             std::to_string(util::count_lines(state::WORKO)) + " lines)");
      echoit("[Info] It is often beneficial to re-run reducer on the output file to make it smaller still (some lines may have been chopped up).");
    }
    copy_workdir_to_tmp();
  }
  echoit("[DONE] BASEDIR used: " + cfg::BASEDIR);
  if (cfg::FIREWORKS != 1) {
    if (!util::file_readable(state::WORKO)) {
      echoit("[DONE] Final testcase: " + cfg::INPUTFILE + " (= input file; no optimizations were successful. " +
             std::to_string(util::count_lines(cfg::INPUTFILE)) + " lines)");
    } else {
      echoit("[DONE] Final testcase: " + state::WORKO + " (" +
             std::to_string(util::count_lines(state::WORKO)) + " lines)");
    }
  }
  if (reason == "abort") {
    echoit("[Abort] Done. Terminating reducer");
    std::signal(SIGINT, SIG_DFL);
    std::exit(2);
  }
  std::exit(0);
}
// Helper: WORKDIR_COPY_SUCCESS shared between copy_workdir_to_tmp + verify_not_found
static int WORKDIR_COPY_SUCCESS = 0;

// copy_workdir_to_tmp — mirror reducer.sh:4573..4610
static void copy_workdir_to_tmp() {
  WORKDIR_COPY_SUCCESS = 0;
  if (cfg::SAVE_RESULTS != 1) return;
  if (state::MULTI_REDUCER == 1) return;
  if (cfg::WORKDIR_LOCATION != 1 && cfg::WORKDIR_LOCATION != 2) return;
  echoit("[Cleanup] Since tmpfs or ramfs (volatile memory) was used, reducer is now saving a copy of the work directory in /tmp/" + state::EPOCH);
  echoit("[Cleanup] Storing a copy of reducer and it's original input file (" + cfg::INPUTFILE + ") in /tmp/" + state::EPOCH + " also");
  // Shelled `$(readlink -f /proc/self/exe)` would resolve to /usr/bin/readlink,
  // not the reducer; use the already-resolved THIS_REDUCER instead.
  if (cfg::MDG == 1 || cfg::GRP_RPL == 1) {
    util::sh("sudo cp -a \"" + state::WORKD + "\" /tmp/" + state::EPOCH);
    util::sh("sudo chown -R `whoami`:`whoami` /tmp/" + state::EPOCH);
    util::sh("sudo chown -R `whoami` /tmp/" + state::EPOCH);
    util::sh("cp \"" + state::THIS_REDUCER + "\" /tmp/" + state::EPOCH);
    util::sh("cp \"" + cfg::INPUTFILE + "\" /tmp/" + state::EPOCH);
  } else {
    util::sh("cp -a \"" + state::WORKD + "\" /tmp/" + state::EPOCH);
    util::sh("cp \"" + state::THIS_REDUCER + "\" /tmp/" + state::EPOCH);
    util::sh("cp \"" + cfg::INPUTFILE + "\" /tmp/" + state::EPOCH);
  }
  std::string diff;
  if (util::dir_exists("/tmp/" + state::EPOCH)) {
    diff = util::sh_capture_trimmed(
      "diff -qr \"" + state::WORKD + "\" /tmp/" + state::EPOCH +
      " | grep -vE 'is a socket|Only in /tmp/|Files .*reducer\\.log and .*reducer\\.log differ'");
  } else diff = "not_empty";
  if (diff.empty()) {
    WORKDIR_COPY_SUCCESS = 1;
    echoit("[Cleanup] Saved copy of work directory in /tmp/" + state::EPOCH);
    echoit("[Cleanup] Now deleting temporary work directory " + state::WORKD);
    fs::remove_all(state::WORKD);
  } else {
    echoit("[Non-fatal Error] Reducer tried saving a copy, but differences were found. The diff output was:");
    echoit(diff);
  }
}

// report_linecounts — mirror reducer.sh:4611..4645
static void report_linecounts() {
  if (cfg::MODE >= 6 && cfg::MODE <= 9) {
    std::string txt = (state::STAGE == "V")
      ? "[Init] Initial number of lines in restructured input file(s):"
      : "[Init] Number of lines in input file(s):";
    long long largest = 0;
    for (int t = 1; t <= state::TS_THREADS; ++t) {
      std::string nm = util::getenv_or(("WORKF" + std::to_string(t)).c_str());
      long long lc = util::count_lines(nm);
      setenv(("TS_LINECOUNTF" + std::to_string(t)).c_str(), std::to_string(lc).c_str(), 1);
      txt += " #" + std::to_string(t) + ": " + std::to_string(lc);
      if (lc > largest) largest = lc;
    }
    echoit(txt);
  } else {
    state::LINECOUNTF = (cfg::FIREWORKS != 1)
      ? util::count_lines(state::WORKF)
      : util::count_lines(cfg::INPUTFILE);
    if (state::STAGE == "V") {
      echoit("[Init] Initial number of lines in restructured input file: " + std::to_string(state::LINECOUNTF) + " (" + cfg::INPUTFILE + ")");
    } else {
      echoit("[Init] Number of lines in input file: " + std::to_string(state::LINECOUNTF) + " (" + cfg::INPUTFILE + ")");
      if (state::LINECOUNTF == 0) {
        echoit("Assert: Input file empty (0 lines)! Terminating");
        std::exit(1);
      }
    }
  }
  if (state::STAGE == "V")
    echoit("[Info] Restructured files linecounts are usually higher as INSERT lines are broken up, init SQL is expanded etc.");
}

// verify_not_found — mirror reducer.sh:4646..4682
static void verify_not_found() {
  std::string extra_path = (state::MULTI_REDUCER != 1) ? "subreducer/<nr>/" : "";
  echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] Initial verify of the issue: fail. Bug/issue is not present under given conditions, or is very sporadic. Terminating.");
  echoit("[Finish] Verification failed. It may help to check the following files...");
  WORKDIR_COPY_SUCCESS = 0;
  copy_workdir_to_tmp();
  std::string pw = (WORKDIR_COPY_SUCCESS == 0) ? state::WORKD : "/tmp/" + state::EPOCH;
  if (cfg::MODE >= 6 && cfg::MODE <= 9) {
    if (cfg::TS_DBG_CLI_OUTPUT == 1) {
      echoit("[Finish] mysql CLI client output : " + pw + "/" + extra_path + "mysql<threadid>.out");
    } else {
      echoit("[Finish] mysql CLI client output : not recorded");
    }
  } else {
    if (cfg::USE_PQUERY == 1) {
      echoit("[Finish] pquery client output    : " + pw + "/" + extra_path + "default.node.tld_thread-0.sql");
    } else {
      echoit("[Finish] mysql CLI client output : " + pw + "/" + extra_path + "log/mysql.out");
    }
  }
  if (cfg::MODE == 1 || cfg::MODE == 6) {
    echoit("[Finish] Valgrind output         : " + pw + "/" + extra_path + "valgrind.out");
  }
  echoit("[Finish] mariadbd/mysqld error log : " + pw + "/" + extra_path + "error.log(.out)");
  echoit("[Finish] initialization output   : " + pw + "/" + extra_path + "init.log");
  echoit("[Finish] time init output        : " + pw + "/" + extra_path + "timezone.init");
  std::exit(1);
}

// apply_tcp_to_workt — mirror reducer.sh:4683..4707
static void apply_tcp_to_workt() {
  std::string tcp;
  if      (util::file_readable(cfg::SCRIPT_PWD + "/testcase_prettify.sh")) tcp = cfg::SCRIPT_PWD + "/testcase_prettify.sh";
  else if (util::file_readable(util::getenv_or("HOME") + "/mariadb-qa/testcase_prettify.sh")) tcp = util::getenv_or("HOME") + "/mariadb-qa/testcase_prettify.sh";
  else return;
  if (!util::file_readable(state::WORKT)) return;
  long long pre_lines = util::count_lines(state::WORKT);
  if (pre_lines < 20) return;
  if (util::sh("\"" + tcp + "\" \"" + state::WORKT + "\" > \"" + state::WORKT + ".tcp\" 2>/dev/null") != 0) {
    fs::remove(state::WORKT + ".tcp"); return;
  }
  std::error_code ec; auto sz = fs::file_size(state::WORKT + ".tcp", ec);
  if (ec || sz == 0) { fs::remove(state::WORKT + ".tcp"); return; }
  long long post_lines = util::count_lines(state::WORKT + ".tcp");
  long long semi_lines = 0;
  try { semi_lines = std::stoll(util::sh_capture_trimmed("grep -c ';' \"" + state::WORKT + ".tcp\" 2>/dev/null")); } catch (...) {}
  long long min_lines = pre_lines * 30 / 100;
  if (post_lines < min_lines || semi_lines < 1) {
    echoit(state::ATLEASTONCE + " [Stage " + state::STAGE +
           "] tcp output failed sanity gate (lines: " + std::to_string(pre_lines) + " -> " + std::to_string(post_lines) +
           ", ; lines: " + std::to_string(semi_lines) + "); keeping non-tcp version for this trial");
    fs::remove(state::WORKT + ".tcp"); return;
  }
  util::move_file(state::WORKT + ".tcp", state::WORKT);
  echoit(state::ATLEASTONCE + " [Stage " + state::STAGE +
         "] tcp layered on top (" + std::to_string(pre_lines) + " -> " + std::to_string(post_lines) + " lines)");
}
// verify — mirror reducer.sh:4708..5050
static void verify_impl(const std::string& original_inputfile) {
  state::STAGE = "V";
  state::TRIAL = 1;
  long long trial_repeat_count = 0;
  echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] Verifying the bug/issue exists and is reproducible by reducer (duration depends on initial input file size)");
  std::string original_myextra = cfg::MYEXTRA;
  std::string initfile, myextra_without_init;
  if (util::contains(cfg::MYEXTRA, "init_file") || util::contains(cfg::MYEXTRA, "init-file")) {
    initfile = util::sh_capture_trimmed(
      "echo \"" + cfg::MYEXTRA + "\" | grep -E --binary-files=text -oE \"--init[-_]file=[^ ]+\" | sed 's|--init[-_]file=||'");
    myextra_without_init = util::sh_capture_trimmed(
      "echo \"" + cfg::MYEXTRA + "\" | sed 's|--init[-_]file=[^ ]\\+||'");
  }
  if (state::MULTI_REDUCER != 1) {
    while (true) {
      multi_reducer();
      if (state::MULTI_REDUCER_REP_FAILED == 0) {
        if (cfg::MODE < 6) multi_reducer_decide_input();
        report_linecounts();
        break;
      }
      cfg::MULTI_THREADS += cfg::MULTI_THREADS_INCREASE;
      if (cfg::MULTI_THREADS > cfg::MULTI_THREADS_MAX) {
        echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [" + state::RUNMODE +
               "] As (possibly sporadic) issue did not reproduce with " + std::to_string(cfg::MULTI_THREADS) + " threads, and as the configured maximum number of threads (" +
               std::to_string(cfg::MULTI_THREADS_MAX) + ") has been reached, now terminating verification");
        verify_not_found();
      } else {
        echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [" + state::RUNMODE +
               "] As (possibly sporadic) issue did not reproduce with " + std::to_string(cfg::MULTI_THREADS - cfg::MULTI_THREADS_INCREASE) +
               " threads, now increasing number of threads to " + std::to_string(cfg::MULTI_THREADS) + " (maximum is " + std::to_string(cfg::MULTI_THREADS_MAX) + ")");
      }
      if (cfg::MULTI_THREADS >= 35) {
        echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [" + state::RUNMODE + "] WARNING: High load active.");
      }
    }
  } else {
    while (true) {
      std::string remove_suffix = state::QCTEXT.empty()
        ? "s/;[\\t ]*#.*/;/i"
        : "s/#\\(NOERROR\\|ERROR\\).*//i";
      diskspace(fs::path(state::WORKT).parent_path().string());
      auto inline_initfile = [&](){
        if (initfile.empty()) return;
        echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] Adding contents of --init-file directly into testcase and removing --init-file option from MYEXTRA");
        diskspace(state::WORKD);
        if (cfg::USE_PQUERY == 0) {
          util::write_file(state::WORKF, state::DROPC + "\n");
          util::sh("grep -E --binary-files=text -v \"" + state::DROPC + "\" \"" + cfg::INPUTFILE + "\" >> \"" + state::WORKF + "\"");
          util::sh("sed -i \"1 r " + initfile + "\" \"" + state::WORKT + "\"");
        } else {
          remove_dropc(state::WORKT);
          std::string suffix = util::rand_suffix();
          std::string tmp = "/tmp/WORKT_" + suffix + ".tmp";
          util::sh("echo \"$(echo \"" + state::DROPC + "\" | sed 's|;|;\\n|g' | grep --binary-files=text -v '^$';cat \"" + initfile + "\";cat \"" + state::WORKT + "\")\" > \"" + tmp + "\"");
          fs::remove(state::WORKT);
          util::move_file(tmp, state::WORKT);
        }
        cfg::MYEXTRA = myextra_without_init;
        util::write_file(state::WORKD + "/MYEXTRA", cfg::MYEXTRA + "\n");
      };
      auto pipeline_full = [&](const std::string& wf, const std::string& wt) {
        util::sh("grep -E --binary-files=text -v \"^#|^$|DEBUG_SYNC|^\\-\\-| \\[Note\\] |====|  WARNING: |^Hope that|^Logging: |\\++++| exit with exit status |Lost connection to | valgrind |Using [MSI]|Using dynamic|MySQL Version|\\------|TIME \\(ms\\)$|Skipping ndb|Setting mysqld |Setting mariadbd |Binaries are debug |Killing Possible Leftover|Removing Stale Files|Creating Directories|Installing Master Database|Servers started, |Try: yum|Missing separate debug|SOURCE|CURRENT_TEST|\\[ERROR\\]|with SSL|_root_|connect to MySQL|No such file|is deprecated at|just omit the defined\" \"" + wf + "\" | sed \"" + remove_suffix + "\" | sed 's/[\\t ]\\+/ /g' | sed 's/Query ([0-9a-fA-F]\\+): \\(.*\\)/\\1;/g' | sed \"s/[ ]*)[ ]*,[ ]*([ ]*/),\\n(/g\" | sed \"s/;\\(.*CREATE.*TABLE\\)/;\\n\\1/g\" | sed \"/CREATE.*TABLE.*;/s/(/(\\n/1;/CREATE.*TABLE.*;/s/\\(.*\\))/\\1\\n)/;/CREATE.*TABLE.*;/s/,/,\\n/g;\" | sed 's/ VALUES[ ]*(/ VALUES \\n(/g' -e \"s/', '/','/g\" > \"" + wt + "\"");
      };
      auto pipeline_medium = [&](const std::string& wf, const std::string& wt) {
        util::sh("grep -E --binary-files=text -v \"^#|^$|DEBUG_SYNC|^\\-\\-\" \"" + wf + "\" | sed \"" + remove_suffix + "\" | sed 's/[\\t ]\\+/ /g' | sed \"s/[ ]*)[ ]*,[ ]*([ ]*/),\\n(/g\" | sed \"s/;\\(.*CREATE.*TABLE\\)/;\\n\\1/g\" | sed \"/CREATE.*TABLE.*;/s/(/(\\n/1;/CREATE.*TABLE.*;/s/\\(.*\\))/\\1\\n)/;/CREATE.*TABLE.*;/s/,/,\\n/g;\" | sed 's/ VALUES[ ]*(/ VALUES \\n(/g' -e \"s/', '/','/g\" > \"" + wt + "\"");
      };
      auto pipeline_low = [&](const std::string& wf, const std::string& wt) {
        util::sh("grep -E --binary-files=text -v \"^#|^$|DEBUG_SYNC|^\\-\\-\" \"" + wf + "\" | sed \"" + remove_suffix + "\" | sed \"s/[\\t ]*)[\\t ]*,[\\t ]*([\\t ]*/),\\n(/g\" | sed \"s/;\\(.*CREATE.*TABLE\\)/;\\n\\1/g\" | sed \"/CREATE.*TABLE.*;/s/(/(\\n/1;/CREATE.*TABLE.*;/s/\\(.*\\))/\\1\\n)/;/CREATE.*TABLE.*;/s/,/,\\n/g;\" | sed 's/ VALUES[ ]*(/ VALUES \\n(/g' > \"" + wt + "\"");
      };
      auto pipeline_t4 = [&](const std::string& wf, const std::string& wt) {
        util::sh("sed \"s/[\\t ]*)[\\t ]*,[\\t ]*([\\t ]*/),\\n(/g\" \"" + wf + "\" | sed \"" + remove_suffix + "\" | sed \"s/;\\(.*CREATE.*TABLE\\)/;\\n\\1/g\" | sed \"/CREATE.*TABLE.*;/s/(/(\\n/1;/CREATE.*TABLE.*;/s/\\(.*\\))/\\1\\n)/;/CREATE.*TABLE.*;/s/,/,\\n/g;\" > \"" + wt + "\"");
      };
      auto pipeline_t5 = [&](const std::string& wf, const std::string& wt) {
        util::sh("sed \"s/[\\t ]*)[\\t ]*,[\\t ]*([\\t ]*/),\\n(/g\" \"" + wf + "\" | sed \"" + remove_suffix + "\" > \"" + wt + "\"");
      };
      if (state::TRIAL == 1) {
        echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] Verify attempt #1: Maximum initial simplification & cleanup & tcp prettify");
        if (cfg::MODE >= 6 && cfg::MODE <= 9) {
          for (int t = 1; t <= state::TS_THREADS; ++t) {
            pipeline_full(util::getenv_or(("WORKF" + std::to_string(t)).c_str()),
                          util::getenv_or(("WORKT" + std::to_string(t)).c_str()));
          }
        } else {
          pipeline_full(state::WORKF, state::WORKT);
          inline_initfile();
          apply_tcp_to_workt();
        }
      } else if (state::TRIAL == 2) {
        echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] Verify attempt #2: High initial simplification (no RQG log text removal) & tcp prettify");
        if (cfg::MODE >= 6 && cfg::MODE <= 9) {
          for (int t = 1; t <= state::TS_THREADS; ++t) {
            pipeline_t4(util::getenv_or(("WORKF" + std::to_string(t)).c_str()),
                        util::getenv_or(("WORKT" + std::to_string(t)).c_str()));
          }
        } else {
          pipeline_medium(state::WORKF, state::WORKT);
          inline_initfile();
          apply_tcp_to_workt();
        }
      } else if (state::TRIAL == 3) {
        if (cfg::MODE >= 6 && cfg::MODE <= 9) {
          state::TS_DEBUG_SYNC_REQUIRED_FLAG = 1;
          echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] Verify attempt #3: Maximum initial simplification & DEBUG_SYNC enabled");
          for (int t = 1; t <= state::TS_THREADS; ++t) {
            std::string wf = util::getenv_or(("WORKF" + std::to_string(t)).c_str());
            std::string wt = util::getenv_or(("WORKT" + std::to_string(t)).c_str());
            util::sh("grep -E --binary-files=text -v \"^#|^$\" \"" + wf + "\" | sed 's/[\\t ]\\+/ /g' | sed \"s/[ ]*)[ ]*,[ ]*([ ]*/),\\n(/g\" | sed \"s/;\\(.*CREATE.*TABLE\\)/;\\n\\1/g\" | sed \"/CREATE.*TABLE.*;/s/(/(\\n/1;/CREATE.*TABLE.*;/s/\\(.*\\))/\\1\\n)/;/CREATE.*TABLE.*;/s/,/,\\n/g;\" | sed 's/ VALUES[ ]*(/ VALUES \\n(/g' -e \"s/', '/','/g\" > \"" + wt + "\"");
          }
        } else {
          echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] Verify attempt #3: High initial simplification (no RQG text removal & less cleanup) & tcp prettify");
          pipeline_low(state::WORKF, state::WORKT);
          inline_initfile();
          apply_tcp_to_workt();
        }
      } else if (state::TRIAL == 4) {
        echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] Verify attempt #4: Medium initial simplification & tcp prettify");
        if (cfg::MODE >= 6 && cfg::MODE <= 9) {
          for (int t = 1; t <= state::TS_THREADS; ++t) {
            pipeline_t4(util::getenv_or(("WORKF" + std::to_string(t)).c_str()),
                        util::getenv_or(("WORKT" + std::to_string(t)).c_str()));
          }
        } else {
          pipeline_t4(state::WORKF, state::WORKT);
          inline_initfile();
          apply_tcp_to_workt();
        }
      } else if (state::TRIAL == 5) {
        echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] Verify attempt #5: Low initial simplification & tcp prettify");
        if (cfg::MODE >= 6 && cfg::MODE <= 9) {
          for (int t = 1; t <= state::TS_THREADS; ++t) {
            std::string wf = util::getenv_or(("WORKF" + std::to_string(t)).c_str());
            std::string wt = util::getenv_or(("WORKT" + std::to_string(t)).c_str());
            util::sh("sed \"s/[\\t ]*)[\\t ]*,[\\t ]*([\\t ]*/),\\n(/g\" \"" + wf + "\" > \"" + wt + "\"");
          }
        } else {
          pipeline_t5(state::WORKF, state::WORKT);
          inline_initfile();
          apply_tcp_to_workt();
        }
      } else if (state::TRIAL == 6) {
        echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] Verify attempt #6: Low initial simplification (tcp-free retry)");
        if (cfg::MODE >= 6 && cfg::MODE <= 9) {
          for (int t = 1; t <= state::TS_THREADS; ++t) {
            std::string wf = util::getenv_or(("WORKF" + std::to_string(t)).c_str());
            std::string wt = util::getenv_or(("WORKT" + std::to_string(t)).c_str());
            util::sh("sed \"s/[\\t ]*)[\\t ]*,[\\t ]*([\\t ]*/),\\n(/g\" \"" + wf + "\" > \"" + wt + "\"");
          }
        } else {
          pipeline_t5(state::WORKF, state::WORKT);
          inline_initfile();
        }
      } else if (state::TRIAL == 7) {
        if (cfg::MODE >= 6 && cfg::MODE <= 9) {
          echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] Verify attempt #7: No initial simplification & DEBUG_SYNC enabled");
          for (int t = 1; t <= state::TS_THREADS; ++t) {
            std::string wf = util::getenv_or(("WORKF" + std::to_string(t)).c_str());
            std::string wt = util::getenv_or(("WORKT" + std::to_string(t)).c_str());
            util::sh("cp -f \"" + wf + "\" \"" + wt + "\"");
          }
        } else {
          echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] Verify attempt #7: No initial simplification");
          cfg::MYEXTRA = original_myextra;
          util::write_file(state::WORKD + "/MYEXTRA", cfg::MYEXTRA + "\n");
          util::sh("cp -f \"" + state::WORKF + "\" \"" + state::WORKT + "\"");
        }
      } else {
        verify_not_found();
      }
      int rc = run_and_check_impl();
      if (rc == 1) {
        echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] Verify attempt #" + std::to_string(state::TRIAL) + ": Success: Issue detected, saved files");
        report_linecounts();
        trial_repeat_count = 0;
        break;
      } else {
        echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] Verify attempt #" + std::to_string(state::TRIAL) + ": Failed: Issue not detected");
        trial_repeat_count++;
        if (trial_repeat_count < cfg::NR_OF_TRIAL_REPEATS) {
          echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] Repeating trial (Attempt " + std::to_string(trial_repeat_count + 1) + "/" + std::to_string(cfg::NR_OF_TRIAL_REPEATS) + ")");
        } else {
          state::TRIAL++;
          trial_repeat_count = 0;
        }
      }
    }
  }
}

static void verify() { verify_impl(cfg::INPUTFILE); }

// fireworks_setup — mirror reducer.sh:5051..5108
static void fireworks_setup() {
  echoit("[Init] FIREWORKS mode active, so automatically set:");
  echoit("[Init] > USE_PQUERY=1: fireworks mode will use pquery");
  cfg::USE_PQUERY = 1;
  echoit("[Init] > USE_NEW_TEXT_STRING=1: fireworks mode will use the new text string script");
  cfg::USE_NEW_TEXT_STRING = 1;
  if (cfg::FIREWORKS_LINES <= 0) {
    std::cerr << "Assert: FIREWORKS mode is active, yet FIREWORKS_LINES is empty. Terminating.\n";
    std::exit(1);
  }
  if (cfg::FIREWORKS_LINES < 10000) {
    echoit("[Init] > FIREWORKS_LINES=10000: FIREWORKS_LINES was set to less then 10000 (minimum)");
    cfg::FIREWORKS_LINES = 10000;
  }
  cfg::PQUERY_MULTI_QUERIES = cfg::FIREWORKS_LINES + 1000;
  echoit("[Init] > PQUERY_MULTI_QUERIES=" + std::to_string(cfg::PQUERY_MULTI_QUERIES) + ": ensures FIREWORKS_LINES queries can be executed");
  if (cfg::SCAN_FOR_NEW_BUGS != 1) {
    echoit("[Init] > SCAN_FOR_NEW_BUGS=1: enabled new bug scanning (required)");
    cfg::SCAN_FOR_NEW_BUGS = 1;
  }
  if (!util::file_readable(cfg::KNOWN_BUGS_LOC)) {
    echoit("[Init] > Failed to read KNOWN_BUGS_LOC file at '" + cfg::KNOWN_BUGS_LOC + "'. Terminating.");
    std::exit(1);
  }
  if (cfg::FIREWORKS_TIMEOUT <= 0) {
    echoit("[Init] > FIREWORKS_TIMEOUT is empty (required). Default: 450 (seconds)");
    std::exit(1);
  }
  echoit("[Init] > TIMEOUT_COMMAND=\"timeout -k" + std::to_string(cfg::FIREWORKS_TIMEOUT) + " -s9 " + std::to_string(cfg::FIREWORKS_TIMEOUT) + "s\"");
  cfg::TIMEOUT_COMMAND = "timeout -k" + std::to_string(cfg::FIREWORKS_TIMEOUT) + " -s9 " + std::to_string(cfg::FIREWORKS_TIMEOUT) + "s";
  echoit("[Init] > STAGE1_LINES=-1");
  cfg::STAGE1_LINES = -1;
  echoit("[Init] > MULTI_THREADS=25");
  cfg::MULTI_THREADS = 25;
  if (cfg::PQUERY_REVERSE_NOSHUFFLE_OPT != 0) {
    cfg::PQUERY_REVERSE_NOSHUFFLE_OPT = (cfg::PQUERY_MULTI == 1) ? 1 : 0;
  }
  if (cfg::FORCE_SKIPV != 1) {
    echoit("[Init] > FORCE_SKIPV=1");
    cfg::FORCE_SKIPV = 1;
  }
  echoit("[Init] > MODE=3");
  cfg::MODE = 3;
  echoit("[Init] > TEXT='fireworksmodeenabled'");
  cfg::TEXT = "fireworksmodeenabled";
}

// ============================================================================
// MAIN
// ============================================================================
// Loaded stage trial table (read from stages.tbl on startup).
struct StageTrial {
  int  stage;       // 3, 4, or 7
  int  trial;
  int  noskip;
  int  next_stage_flag;  // 1 if this trial ends the stage
  std::string cmd;
};
static std::vector<StageTrial> g_stage_trials;

static void load_stages_table(const std::string& path) {
  std::ifstream in(path);
  if (!in) {
    std::cerr << "Warning: " << path << " not found; STAGE3/4/7 sed-transform tables empty.\n";
    return;
  }
  std::string line;
  while (std::getline(in, line)) {
    if (line.empty()) continue;
    auto toks = util::split(line, '\t');
    if (toks.size() < 5) continue;
    StageTrial t;
    if      (toks[0] == "STAGE3") t.stage = 3;
    else if (toks[0] == "STAGE4") t.stage = 4;
    else if (toks[0] == "STAGE7") t.stage = 7;
    else continue;
    try { t.trial = std::stoi(toks[1]); } catch (...) { continue; }
    try { t.noskip = std::stoi(toks[2]); } catch (...) { t.noskip = 0; }
    try { t.next_stage_flag = std::stoi(toks[3]); } catch (...) { t.next_stage_flag = 0; }
    // Some trials in stages.tbl span multiple bash lines (e.g. STAGE4 trial 322
    // is a 50-line awk script). The extractor encodes embedded newlines as the
    // 2-byte literal \n; restore them here so bash -c sees the original script.
    t.cmd = util::replace_all(toks[4], "\\n", "\n");
    g_stage_trials.push_back(t);
  }
}

// Run all trials for the given stage from the loaded table; mirrors the
// elif-chain pattern in reducer.sh stages 3, 4, 7. Each trial: run the embedded
// bash command, check size, run_and_check, etc.
static void run_stage_trials(int stage) {
  if (!util::file_readable(state::WORKF)) abort_reducer();
  long long sizef = 0;
  { std::error_code ec; sizef = static_cast<long long>(fs::file_size(state::WORKF, ec)); }
  // Build an index of trials for this stage so we can re-execute the same row
  // across NR_OF_TRIAL_REPEATS retries without rescanning the whole vector.
  std::vector<const StageTrial*> idx;
  for (const auto& t : g_stage_trials) if (t.stage == stage) idx.push_back(&t);
  state::TRIAL = 1;
  long long trial_repeat = 0;
  size_t pos = 0;
  while (pos < idx.size()) {
    const StageTrial& t = *idx[pos];
    if (!util::dir_exists(state::WORKD) || !util::file_readable(cfg::INPUTFILE) || !util::file_readable(state::THIS_REDUCER)) {
      abort_reducer(); break;
    }
    // Advance pos until it matches state::TRIAL (handles gaps, although bash table is contiguous).
    if (t.trial != static_cast<int>(state::TRIAL)) { ++pos; continue; }
    diskspace(fs::path(state::WORKT).parent_path().string());
    std::string cmd = util::replace_all(t.cmd, "$WORKF", "\"" + state::WORKF + "\"");
    cmd            = util::replace_all(cmd,     "$WORKT", "\"" + state::WORKT + "\"");
    util::sh(cmd);
    if (!util::file_readable(state::WORKT)) abort_reducer();
    long long sizet = 0;
    { std::error_code ec; sizet = static_cast<long long>(fs::file_size(state::WORKT, ec)); }
    if (t.noskip == 0 && sizet >= sizef) {
      echoit(state::ATLEASTONCE + " [Stage " + std::to_string(stage) + "] [Trial " + std::to_string(state::TRIAL) +
             "] Skipping this trial as it does not reduce filesize");
      state::TRIAL++;
      trial_repeat = 0;
      ++pos;
      continue;
    }
    echoit(state::ATLEASTONCE + " [Stage " + std::to_string(stage) + "] [Trial " + std::to_string(state::TRIAL) +
           "] Remaining size of input file: " + std::to_string(sizef) + " bytes (" + std::to_string(state::LINECOUNTF) + " lines)");
    int rc = run_and_check_impl();
    bool advance = true;
    if (rc != 1) {
      trial_repeat++;
      if (trial_repeat < cfg::NR_OF_TRIAL_REPEATS) {
        echoit(state::ATLEASTONCE + " [Stage " + std::to_string(stage) + "] Repeating trial (Attempt " + std::to_string(trial_repeat + 1) + "/" + std::to_string(cfg::NR_OF_TRIAL_REPEATS) + ")");
        advance = false;  // stay on same row + same TRIAL
      } else {
        state::TRIAL++; trial_repeat = 0;
      }
    } else {
      state::TRIAL++; trial_repeat = 0;
    }
    sizef = util::file_readable(state::WORKF)
      ? static_cast<long long>(fs::file_size(state::WORKF)) : 0;
    state::LINECOUNTF = util::count_lines(state::WORKF);
    // next_stage_flag is informational only (mirrors bash's `; NEXTACTION="&
    // progress to the next stage"` log-message hint on the final elif row);
    // the stage actually ends when the index runs out of matching trials.
    if (advance) ++pos;
  }
}

// stage9_run helper — mirror reducer.sh:6779..6816
static int STAGE9_FILTER_USE = 0;  // bookkeeping
static int STAGE9_CHK = 0;
static int MYINIT_DROP = 0;
static void stage9_run(const std::string& filter) {
  long long trial_repeat = 0;
  STAGE9_CHK = 0;
  state::STAGE9_NOT_STARTED_CORRECTLY = 0;
  std::string save_myinit;
  if (MYINIT_DROP == 1) { save_myinit = cfg::MYINIT; cfg::MYINIT.clear(); }
  std::string save_special = cfg::SPECIAL_MYEXTRA_OPTIONS;
  if (!filter.empty()) {
    cfg::SPECIAL_MYEXTRA_OPTIONS = util::replace_all(cfg::SPECIAL_MYEXTRA_OPTIONS, filter, "");
  }
  while (true) {
    run_and_check_impl();
    trial_repeat++;
    if (STAGE9_CHK == 0 || state::STAGE9_NOT_STARTED_CORRECTLY == 1) {
      if (trial_repeat < cfg::NR_OF_TRIAL_REPEATS) {
        echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] Repeating trial (Attempt " + std::to_string(trial_repeat + 1) + "/" + std::to_string(cfg::NR_OF_TRIAL_REPEATS) + ")");
        continue;
      } else {
        cfg::SPECIAL_MYEXTRA_OPTIONS = save_special;
        if (!save_myinit.empty()) cfg::MYINIT = save_myinit;
        break;
      }
    } else {
      if (!filter.empty()) util::sh("sed -i \"s|" + filter + "||\" \"" + state::WORK_START + "\"");
      if (!save_myinit.empty()) util::sh("sed -i \"s|" + save_myinit + "||\" \"" + state::WORK_START + "\"");
      break;
    }
  }
  state::TRIAL++;
}

// Apply env-var-driven subreducer init: when invoked with REDUCER_MULTI_REDUCER=1
// (set by the parent reducer's multi_reducer()), copy env values into cfg/state
// before options_check. Mirrors the bash #VARMOD# expansion.
// Honor bare-name env vars matching the bash variable names (MODE, TEXT,
// BASEDIR, MYEXTRA, ...). This makes the C++ binary behave like the bash
// reducer.sh when users `MODE=3 ./reducer in.sql` etc.
static void apply_bare_env() {
  auto get_i = [](const char* n, int& dst) {
    if (const char* v = std::getenv(n)) { try { dst = std::stoi(v); } catch (...) {} }
  };
  auto get_l = [](const char* n, long long& dst) {
    if (const char* v = std::getenv(n)) { try { dst = std::stoll(v); } catch (...) {} }
  };
  auto get_s = [](const char* n, std::string& dst) {
    if (const char* v = std::getenv(n)) dst = v;
  };
  // Basic
  get_s("INPUTFILE", cfg::INPUTFILE);
  get_i("MODE", cfg::MODE);
  get_s("TEXT", cfg::TEXT);
  get_i("MODE3_ANY_SIG", cfg::MODE3_ANY_SIG);
  get_i("WORKDIR_LOCATION", cfg::WORKDIR_LOCATION);
  get_s("WORKDIR_M3_DIRECTORY", cfg::WORKDIR_M3_DIRECTORY);
  get_s("MYEXTRA", cfg::MYEXTRA);
  get_s("MYINIT", cfg::MYINIT);
  get_s("BASEDIR", cfg::BASEDIR);
  get_i("DISABLE_TOKUDB_AUTOLOAD", cfg::DISABLE_TOKUDB_AUTOLOAD);
  get_i("DISABLE_TOKUDB_AND_JEMALLOC", cfg::DISABLE_TOKUDB_AND_JEMALLOC);
  get_i("FORCE_SKIPV", cfg::FORCE_SKIPV);
  get_i("FORCE_SPORADIC", cfg::FORCE_SPORADIC);
  get_i("NR_OF_TRIAL_REPEATS", cfg::NR_OF_TRIAL_REPEATS);
  get_i("PQUERY_MULTI", cfg::PQUERY_MULTI);
  get_i("REDUCE_STARTUP_ISSUES", cfg::REDUCE_STARTUP_ISSUES);
  get_i("REDUCE_GLIBC_OR_SS_CRASHES", cfg::REDUCE_GLIBC_OR_SS_CRASHES);
  get_s("SCRIPT_LOC", cfg::SCRIPT_LOC);
  get_i("REPLICATION", cfg::REPLICATION);
  get_s("REPL_EXTRA", cfg::REPL_EXTRA);
  get_s("MASTER_EXTRA", cfg::MASTER_EXTRA);
  get_s("SLAVE_EXTRA", cfg::SLAVE_EXTRA);
  get_i("TIMEOUT_CHECK", cfg::TIMEOUT_CHECK);
  get_s("TIMEOUT_COMMAND", cfg::TIMEOUT_COMMAND);
  get_i("SLOW_DOWN_CHUNK_SCALING", cfg::SLOW_DOWN_CHUNK_SCALING);
  get_i("SLOW_DOWN_CHUNK_SCALING_NR", cfg::SLOW_DOWN_CHUNK_SCALING_NR);
  get_i("USE_NEW_TEXT_STRING", cfg::USE_NEW_TEXT_STRING);
  get_s("TEXT_STRING_LOC", cfg::TEXT_STRING_LOC);
  get_i("SCAN_FOR_NEW_BUGS", cfg::SCAN_FOR_NEW_BUGS);
  get_s("KNOWN_BUGS_LOC", cfg::KNOWN_BUGS_LOC);
  get_s("NEW_BUGS_SAVE_DIR", cfg::NEW_BUGS_SAVE_DIR);
  get_i("SHOW_SETUP_DEBUGGING", cfg::SHOW_SETUP_DEBUGGING);
  get_i("RR_TRACING", cfg::RR_TRACING);
  get_i("RR_SAVE_ALL_TRACES", cfg::RR_SAVE_ALL_TRACES);
  get_i("PAUSE_AFTER_EACH_OCCURRENCE", cfg::PAUSE_AFTER_EACH_OCCURRENCE);
  get_i("MULTI_THREADS", cfg::MULTI_THREADS);
  get_i("MULTI_THREADS_INCREASE", cfg::MULTI_THREADS_INCREASE);
  get_i("MULTI_THREADS_MAX", cfg::MULTI_THREADS_MAX);
  get_s("PQUERY_EXTRA_OPTIONS", cfg::PQUERY_EXTRA_OPTIONS);
  get_i("PQUERY_MULTI_THREADS", cfg::PQUERY_MULTI_THREADS);
  get_i("PQUERY_MULTI_CLIENT_THREADS", cfg::PQUERY_MULTI_CLIENT_THREADS);
  get_l("PQUERY_MULTI_QUERIES", cfg::PQUERY_MULTI_QUERIES);
  get_i("PQUERY_REVERSE_NOSHUFFLE_OPT", cfg::PQUERY_REVERSE_NOSHUFFLE_OPT);
  get_i("SAVE_RESULTS", cfg::SAVE_RESULTS);
  get_i("USE_PQUERY", cfg::USE_PQUERY);
  get_s("PQUERY_LOC", cfg::PQUERY_LOC);
  get_i("PQUERY_CONS_Q_FAIL", cfg::PQUERY_CONS_Q_FAIL);
  get_i("CLI_MODE", cfg::CLI_MODE);
  get_i("ENABLE_QUERYTIMEOUT", cfg::ENABLE_QUERYTIMEOUT);
  get_i("QUERYTIMEOUT", cfg::QUERYTIMEOUT);
  get_i("LOAD_TIMEZONE_DATA", cfg::LOAD_TIMEZONE_DATA);
  get_i("STAGE1_LINES", cfg::STAGE1_LINES);
  get_i("SKIPSTAGEBELOW", cfg::SKIPSTAGEBELOW);
  get_i("SKIPSTAGEABOVE", cfg::SKIPSTAGEABOVE);
  get_i("FORCE_KILL", cfg::FORCE_KILL);
  get_i("MDG", cfg::MDG);
  get_i("MDG_ISSUE_NODE", cfg::MDG_ISSUE_NODE);
  get_i("NR_OF_NODES", cfg::NR_OF_NODES);
  get_i("GALERA_NODE", cfg::GALERA_NODE);
  get_s("WSREP_PROVIDER_OPTIONS", cfg::WSREP_PROVIDER_OPTIONS);
  get_i("GRP_RPL", cfg::GRP_RPL);
  get_i("GRP_RPL_ISSUE_NODE", cfg::GRP_RPL_ISSUE_NODE);
  get_i("MODE5_COUNTTEXT", cfg::MODE5_COUNTTEXT);
  get_s("MODE5_ADDITIONAL_TEXT", cfg::MODE5_ADDITIONAL_TEXT);
  get_i("MODE5_ADDITIONAL_COUNTTEXT", cfg::MODE5_ADDITIONAL_COUNTTEXT);
  get_s("MODE11_TYPE", cfg::MODE11_TYPE);
  get_s("MODE11_BINLOG_FORMAT", cfg::MODE11_BINLOG_FORMAT);
  get_i("FIREWORKS", cfg::FIREWORKS);
  get_i("FIREWORKS_LINES", cfg::FIREWORKS_LINES);
  get_i("FIREWORKS_TIMEOUT", cfg::FIREWORKS_TIMEOUT);
  get_i("TS_TRXS_SETS", cfg::TS_TRXS_SETS);
  get_i("TS_DBG_CLI_OUTPUT", cfg::TS_DBG_CLI_OUTPUT);
  get_i("TS_DS_TIMEOUT", cfg::TS_DS_TIMEOUT);
  get_i("TS_VARIABILITY_SLEEP", cfg::TS_VARIABILITY_SLEEP);
}

static void apply_subreducer_env() {
  const char* ms = std::getenv("REDUCER_MULTI_REDUCER");
  if (!ms || std::string(ms) != "1") return;
  state::MULTI_REDUCER = 1;
  if (const char* v = std::getenv("REDUCER_EPOCH"))  state::EPOCH  = v;
  if (const char* v = std::getenv("REDUCER_MODE"))   { try { cfg::MODE = std::stoi(v); } catch (...) {} }
  if (const char* v = std::getenv("REDUCER_TEXT"))   cfg::TEXT  = v;
  if (const char* v = std::getenv("REDUCER_SKIPV"))  { try { state::SKIPV = std::stoi(v); } catch (...) {} }
  if (const char* v = std::getenv("REDUCER_SPORADIC")){ try { state::SPORADIC = std::stoi(v); } catch (...) {} }
  if (const char* v = std::getenv("REDUCER_BASEDIR")) cfg::BASEDIR = v;
  if (const char* v = std::getenv("REDUCER_MYUSER"))  state::MYUSER = v;
  if (const char* v = std::getenv("REDUCER_WORKD"))   state::WORKD  = v;
  if (const char* v = std::getenv("REDUCER_MODE5_COUNTTEXT")) { try { cfg::MODE5_COUNTTEXT = std::stoi(v); } catch (...) {} }
  if (const char* v = std::getenv("REDUCER_PQUERY_MULTI_CLIENT_THREADS")) { try { cfg::PQUERY_MULTI_CLIENT_THREADS = std::stoi(v); } catch (...) {} }
  if (const char* v = std::getenv("REDUCER_PQUERY_MULTI_QUERIES")) { try { cfg::PQUERY_MULTI_QUERIES = std::stoll(v); } catch (...) {} }
  if (const char* v = std::getenv("REDUCER_TS_TRXS_SETS")) { try { cfg::TS_TRXS_SETS = std::stoi(v); } catch (...) {} }
  if (const char* v = std::getenv("REDUCER_TS_DBG_CLI_OUTPUT")) { try { cfg::TS_DBG_CLI_OUTPUT = std::stoi(v); } catch (...) {} }
  if (const char* v = std::getenv("REDUCER_PAUSE_AFTER_EACH_OCCURRENCE")) { try { cfg::PAUSE_AFTER_EACH_OCCURRENCE = std::stoi(v); } catch (...) {} }
  // Subreducers are launched with `exec -a "<workdir>/subreducer"` so argv[0]
  // is a fake path used only for ps display; the real binary lives elsewhere.
  // THIS_REDUCER (= argv[0] realpath) is therefore non-existent, which would
  // make every stage-loop file_readable(THIS_REDUCER) guard fire abort_reducer.
  // Override with /proc/self/exe so the self-existence check passes.
  {
    char buf[PATH_MAX];
    ssize_t n = readlink("/proc/self/exe", buf, sizeof(buf) - 1);
    if (n > 0) { buf[n] = '\0'; state::THIS_REDUCER = buf; }
  }
}

int main(int argc, char** argv) {
  std::ios::sync_with_stdio(false);
  state::rng.seed(static_cast<uint64_t>(
    std::chrono::high_resolution_clock::now().time_since_epoch().count()));
  // Top-of-binary process-wide init — mirrors reducer.sh:344,348-349,370-376.
  // Done in main() so every forked mariadbd/gdb child inherits it. Each call
  // is best-effort: a missing /proc node or a host with no /home/$USER/mariadb-qa
  // must not abort the reducer.
  //
  // (a) Shrink mariadbd cores: anon-private + ELF headers only (0x11). Drops
  //     anon-shared (InnoDB buffer pool) and private hugepages. Inherited via
  //     fork by every child mariadbd.
  {
    int fd = ::open("/proc/self/coredump_filter", O_WRONLY | O_CLOEXEC);
    if (fd >= 0) { ssize_t w = ::write(fd, "0x11\n", 5); (void)w; ::close(fd); }
  }
  // (b) Cap gdb / elfutils debuginfod fetches — secondary guard so a missed
  //     call site cannot stall reduction on remote symbol lookups.
  setenv("DEBUGINFOD_TIMEOUT",  "13", 0);
  setenv("DEBUGINFOD_PROGRESS", "0",  0);
  // (c) Sanitizer runtime options — required for sanitizer-build crash reduction.
  //     Uses HOME to locate the suppression filter files; if HOME is unset, the
  //     suppressions= prefix is simply absent and the other knobs still apply.
  {
    std::string home = util::getenv_or("HOME");
    std::string asan_sup  = home.empty() ? "" : ("suppressions=" + home + "/mariadb-qa/ASAN.filter:");
    std::string ubsan_sup = home.empty() ? "" : ("suppressions=" + home + "/mariadb-qa/UBSAN.filter:");
    setenv("ASAN_OPTIONS",
      (asan_sup + "quarantine_size_mb=512:atexit=0:detect_invalid_pointer_pairs=3"
                  ":dump_instruction_bytes=1:abort_on_error=1:allocator_may_return_null=1").c_str(), 0);
    setenv("UBSAN_OPTIONS",
      (ubsan_sup + "print_stacktrace=1:report_error_type=1").c_str(), 0);
    setenv("TSAN_OPTIONS",
      "suppress_equal_stacks=1:suppress_equal_addresses=1:history_size=7:verbosity=1", 0);
    setenv("MSAN_OPTIONS", "abort_on_error=1:poison_in_dtor=0", 0);
  }
  std::error_code ec;
  cfg::BASEDIR = fs::current_path(ec).string();
  if (argc >= 1 && argv[0]) {
    cfg::SCRIPT_PWD = fs::path(util::realpath_or(argv[0])).parent_path().string();
    // Mirror bash THIS_REDUCER="$(cd "$(dirname $0)" && pwd)/$(basename "$0")":
    // absolute path of the script/binary. Used (a) as display name in the
    // [Init] Reducer: banner and (b) as a self-existence guard in stage loops.
    state::THIS_REDUCER = util::realpath_or(argv[0]);
  }
  // Honor SCRIPT_PWD from env — the bash wrapper exports it after pquery-prep-red.sh's
  // sed-rewrite hardcodes the path. Without this, the binary would re-derive
  // SCRIPT_PWD from argv[0]'s parent dir, which is /data/<workdir>/ for generated
  // reducer<N>.sh files, not the framework's ~/mariadb-qa/ where new_text_string.sh /
  // known_bugs.strings live.
  if (const char* env_sp = std::getenv("SCRIPT_PWD"); env_sp && env_sp[0] != '\0') {
    cfg::SCRIPT_PWD = env_sp;
  }
  // Resolve framework resource files. Search order:
  //   1) ${SCRIPT_PWD}/<file>         — usually ~/mariadb-qa/ via wrapper
  //   2) ${HOME}/mariadb-qa/<file>    — canonical install location
  //   3) ${SCRIPT_PWD}/../<file>      — when binary runs from reducercpp/ subdir
  // Returns the first readable path, or the first candidate (which will fail
  // the later -r check loudly) if none exist. This removes the need to symlink
  // known_bugs.strings / new_text_string.sh into reducercpp/.
  auto resolve_framework_file = [&](const std::string& relpath) -> std::string {
    std::string home = util::getenv_or("HOME");
    std::vector<std::string> cands = {
      cfg::SCRIPT_PWD + "/" + relpath,
      home + "/mariadb-qa/" + relpath,
      cfg::SCRIPT_PWD + "/../" + relpath,
    };
    for (const auto& p : cands) if (util::file_readable(p)) return p;
    return cands.front();
  };
  cfg::TEXT_STRING_LOC = resolve_framework_file("new_text_string.sh");
  cfg::KNOWN_BUGS_LOC      = resolve_framework_file("known_bugs.strings");
  cfg::KNOWN_BUGS_LOC_SAN  = resolve_framework_file("known_bugs.strings.SAN");
  cfg::PQUERY_LOC      = resolve_framework_file("pquery/pquery2-md");
  state::BASEDIR_ALT_PATH = util::replace_all(cfg::BASEDIR, "/test/", "/data/VARIOUS_BUILDS/");
  state::WHOAMI = util::sh_capture_trimmed("whoami");
  state::MYUSER = state::WHOAMI;
  install_signal_handlers();

  // Honor bare-name env-var overrides (MODE, TEXT, BASEDIR, MYEXTRA, ...) so
  // `MODE=3 BASEDIR=/test/x ./reducer in.sql` works like bash. Run before
  // subreducer-env so REDUCER_*-prefixed vars from the parent always win.
  apply_bare_env();
  // Subreducer? (set by parent's multi_reducer launch)
  apply_subreducer_env();

  // Load the per-stage trial table. Prefer the directory next to the actual
  // binary (readlink /proc/self/exe), then SCRIPT_PWD (argv[0]'s parent —
  // may differ when invoked through a bash wrapper like reducer_cpp.sh), then
  // REDUCER_STAGES_TBL env var override.
  {
    std::vector<std::string> candidates;
    if (const char* v = std::getenv("REDUCER_STAGES_TBL")) candidates.push_back(v);
    {
      char buf[PATH_MAX];
      ssize_t n = readlink("/proc/self/exe", buf, sizeof(buf) - 1);
      if (n > 0) { buf[n] = '\0'; candidates.push_back(fs::path(buf).parent_path().string() + "/stages.tbl"); }
    }
    candidates.push_back(cfg::SCRIPT_PWD + "/stages.tbl");
    bool loaded = false;
    for (const auto& p : candidates) {
      if (util::file_readable(p)) { load_stages_table(p); loaded = true; break; }
    }
    if (!loaded) load_stages_table(candidates.front());  // emits the warning
  }

  std::string cli_arg = (argc >= 2 && argv[1]) ? argv[1] : "";

  if (cfg::FIREWORKS == 1) fireworks_setup();
  set_internal_options();
  preprocess_myextra();
  options_check(cli_arg);
  init_workdir_and_files();

  // Mode banners (mirror reducer.sh:5215..5266)
  if (cfg::MODE == 9) {
    echoit("[Init] Run mode: MODE=9: ThreadSync Crash [ALPHA]");
    echoit("[Init] Looking for any mariadbd/mysqld crash");
  } else if (cfg::MODE == 8) {
    echoit("[Init] Run mode: MODE=8: ThreadSync mariadbd/mysqld error log [ALPHA]");
    echoit("[Init] Looking for this string: '" + cfg::TEXT + "' in mariadbd/mysqld error log output");
  } else if (cfg::MODE == 7) {
    echoit("[Init] Run mode: MODE=7: ThreadSync mysql CLI output [ALPHA]");
    echoit("[Init] Looking for this string: '" + cfg::TEXT + "' in mysql CLI output");
  } else if (cfg::MODE == 6) {
    echoit("[Init] Run mode: MODE=6: ThreadSync Valgrind output [ALPHA]");
    echoit("[Init] Looking for this string: '" + cfg::TEXT + "' in Valgrind output");
  } else if (cfg::MODE == 5) {
    echoit("[Init] Run mode: MODE=5: MTR testcase output");
    echoit("[Init] Looking for " + std::to_string(cfg::MODE5_COUNTTEXT) + "x this string: '" + cfg::TEXT + "' in mysql CLI verbose output");
  } else if (cfg::MODE == 4) {
    if (cfg::REDUCE_GLIBC_OR_SS_CRASHES > 0) {
      echoit("[Init] Run mode: MODE=4: GLIBC crash");
    } else {
      echoit("[Init] Run mode: MODE=4: Crash");
    }
  } else if (cfg::MODE == 3) {
    echoit("[Init] Run mode: MODE=3: mariadbd/mysqld error log search for '" + cfg::TEXT + "'");
  } else if (cfg::MODE == 2) {
    echoit("[Init] Run mode: MODE=2: client output search for '" + cfg::TEXT + "'");
  } else if (cfg::MODE == 1) {
    echoit("[Init] Run mode: MODE=1: Valgrind output search for '" + cfg::TEXT + "'");
  } else if (cfg::MODE == 0) {
    echoit("[Init] Run mode: MODE=0: Timeout/hang/shutdown - trial durations > " + std::to_string(state::TIMEOUT_CHECK_REAL) + "s");
  }
  if (cfg::FIREWORKS != 1) {
    echoit("[Info] Leading [] = No bug/issue found yet, leading [*] = bug/issue at least seen once");
  } else {
    echoit("[Info] Leading [] = No bug found yet, leading [*] = at least one new previously unknown bug discovered");
  }
  report_linecounts();

  // VERIFY
  if (state::SKIPV != 1) {
    verify();
    if (state::MULTI_REDUCER == 1) {
      finish(cfg::INPUTFILE);
    }
  }

  // STAGE T: ThreadSync thread elimination (MODE 6..9)
  if (cfg::MODE >= 6 && cfg::MODE <= 9) {
    state::NEXTACTION = "& try removing next thread";
    state::STAGE = "T";
    state::TRIAL = 1;
    if (state::TS_THREADS != 1) {
      echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] ThreadSync thread elimination: removing unnecessary threads");
      while (true) {
        // Copy each WORKF$t to WORKT$t to start trial
        for (int t = 1; t <= state::TS_THREADS; ++t) {
          std::string wf = util::getenv_or(("WORKF" + std::to_string(t)).c_str());
          std::string wt = util::getenv_or(("WORKT" + std::to_string(t)).c_str());
          util::sh("cp -f \"" + wf + "\" \"" + wt + "\"");
        }
        if (state::TRIAL > 1) report_linecounts();
        state::TS_ELIMINATION_THREAD_ID = state::TS_THREADS + 1 + state::TS_ELIMINATED_THREAD_COUNT - static_cast<int>(state::TRIAL);
        // Estimate largest WORKF line count
        long long largest = 0;
        for (int t = 1; t <= state::TS_THREADS; ++t) {
          long long l = util::count_lines(util::getenv_or(("WORKF" + std::to_string(t)).c_str()));
          if (l > largest) largest = l;
        }
        int attempts = 0;
        if (state::SPORADIC == 0) {
          if      (largest > 40000) attempts = 1;
          else if (largest > 10000) attempts = 2;
          else if (largest >  5000) attempts = 4;
          else if (largest >  1000) attempts = 6;
          else                       attempts = 10;
        } else {
          if      (largest > 40000) attempts = 10;
          else if (largest > 10000) attempts = 13;
          else if (largest >  5000) attempts = 15;
          else if (largest >  1000) attempts = 17;
          else                       attempts = 20;
        }
        for (int a = 1; a <= attempts; ++a) {
          echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [Trial " + std::to_string(state::TRIAL) + "] [Attempt " + std::to_string(a) + "] Trying to eliminate thread " + std::to_string(state::TS_ELIMINATION_THREAD_ID));
          std::string ts_wf = util::getenv_or(("WORKF" + std::to_string(state::TS_ELIMINATION_THREAD_ID)).c_str());
          std::string ts_wt = util::getenv_or(("WORKT" + std::to_string(state::TS_ELIMINATION_THREAD_ID)).c_str());
          std::string ts_t_thread = util::sh_capture_trimmed(
            "grep -E --binary-files=text \"DEBUG_SYNC.*SIGNAL\" \"" + ts_wf + "\" | sed 's/^.*SIGNAL[ ]*//;s/ .*$//g'");
          util::write_file(ts_wt, "\n");
          if (!ts_t_thread.empty()) {
            for (int t = 1; t <= state::TS_THREADS; ++t) {
              std::string wf = util::getenv_or(("WORKF" + std::to_string(t)).c_str());
              std::string wt = util::getenv_or(("WORKT" + std::to_string(t)).c_str());
              if (util::sh("grep -E --binary-files=text -qi \"SIGNAL GO_T2\" \"" + wf + "\"") == 0) {
                util::sh("grep -E --binary-files=text -v \"DEBUG_SYNC.*" + ts_t_thread + " \" \"" + wf + "\" > \"" + wt + "\"");
              }
            }
          }
          int rc = run_and_check_impl();
          if (rc == 1) {
            echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [Trial " + std::to_string(state::TRIAL) + "] [Attempt " + std::to_string(a) + "] Thread " + std::to_string(state::TS_ELIMINATION_THREAD_ID) + " elimination: Success.");
            break;
          } else {
            if (a == attempts) {
              echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [Trial " + std::to_string(state::TRIAL) + "] [Attempt " + std::to_string(a) + "] Thread " + std::to_string(state::TS_ELIMINATION_THREAD_ID) + " elimination: Failed. Thread will be left as-is.");
            } else {
              echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [Trial " + std::to_string(state::TRIAL) + "] [Attempt " + std::to_string(a) + "] Thread " + std::to_string(state::TS_ELIMINATION_THREAD_ID) + " elimination: Failed. Re-attempting.");
            }
            util::sh("cp -f \"" + ts_wf + "\" \"" + ts_wt + "\"");
          }
        }
        state::TRIAL++;
        if (state::TRIAL == state::TS_THREADS + 1 + state::TS_ELIMINATED_THREAD_COUNT) {
          echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [Trial " + std::to_string(state::TRIAL) + "] Last thread processed. ThreadSync thread elimination complete");
          break;
        }
      }
    }
    if (state::TS_THREADS == 1) {
      echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [TSE Finish] Only one SQL thread remaining. Merging DATA and SQL thread and swapping to single threaded simplification");
      state::WORKO = state::WORKD + "/single_out.sql";
      diskspace(state::WORKD);
      util::sh("cp -f \"" + state::TS_DATAINPUTFILE + "\" \"" + state::WORKF + "\"");
      std::string ts_workf1 = util::getenv_or("WORKF1");
      util::sh("cat \"" + ts_workf1 + "\" >> \"" + state::WORKF + "\"");
      util::sh("cp -f \"" + state::WORKF + "\" \"" + state::WORKO + "\"");
      write_workO_options_header();
      echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [TSE Finish] Merging complete. Single threaded DATA+SQL file saved as " + state::WORKO);
      if      (cfg::MODE == 6) cfg::MODE = 1;
      else if (cfg::MODE == 7) cfg::MODE = 2;
      else if (cfg::MODE == 8) cfg::MODE = 3;
      else if (cfg::MODE == 9) cfg::MODE = 4;
      echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [TSE Finish] Now starting re-verification in MODE " + std::to_string(cfg::MODE));
      verify_impl(state::WORKO);
    }
  }

  // STAGE 1: Reduce large file fast
  state::LINECOUNTF = (cfg::FIREWORKS != 1)
    ? util::count_lines(state::WORKF)
    : util::count_lines(cfg::INPUTFILE);
  if (cfg::SKIPSTAGEBELOW < 1 && cfg::SKIPSTAGEABOVE > 1) {
    state::NEXTACTION = (cfg::FIREWORKS != 1) ? "& try removing next random line(set)" : "& create next FIREWORKS random lineset";
    state::STAGE = (cfg::FIREWORKS != 1) ? "1" : "F";
    state::TRIAL = 1;
    if (state::LINECOUNTF >= cfg::STAGE1_LINES || cfg::PQUERY_MULTI > 0 || cfg::FORCE_SKIPV > 0 || cfg::REDUCE_GLIBC_OR_SS_CRASHES > 0) {
      if (cfg::FIREWORKS != 1) {
        echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] Commencing stage " + state::STAGE);
      }
      while (state::LINECOUNTF >= cfg::STAGE1_LINES) {
        if (!util::dir_exists(state::WORKD) || !util::file_readable(cfg::INPUTFILE) || !util::file_readable(state::THIS_REDUCER)) { abort_reducer(); break; }
        if (state::LINECOUNTF == cfg::STAGE1_LINES) state::NEXTACTION = "& Progress to the next stage";
        if (cfg::FIREWORKS != 1)
          echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [Trial " + std::to_string(state::TRIAL) + "] Remaining number of lines in input file: " + std::to_string(state::LINECOUNTF));
        if (state::MULTI_REDUCER != 1 && state::SPORADIC == 1 && cfg::REDUCE_GLIBC_OR_SS_CRASHES <= 0) {
          multi_reducer();
        } else {
          if (cfg::FIREWORKS == 1) cut_fireworks_chunk_and_shuffle();
          else                      { determine_chunk(); cut_random_chunk(); }
          run_and_check();
        }
        state::TRIAL++;
        state::LINECOUNTF = (cfg::FIREWORKS != 1)
          ? util::count_lines(state::WORKF)
          : util::count_lines(cfg::INPUTFILE);
      }
    } else {
      echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] Skipping stage " + state::STAGE + " as remaining number of lines in input file <= " + std::to_string(cfg::STAGE1_LINES));
    }
  }

  // STAGE 2: line-by-line elimination
  if (cfg::SKIPSTAGEBELOW < 2 && cfg::SKIPSTAGEABOVE > 2) {
    state::NEXTACTION = "& try removing next SQL line";
    state::STAGE = "2";
    state::TRIAL = 1;
    long long trial_repeat = 0;
    state::NOISSUEFLOW = 0;
    long long currentline = 1;
    echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] Commencing stage " + state::STAGE);
    while (true) {
      if (!util::dir_exists(state::WORKD) || !util::file_readable(cfg::INPUTFILE) || !util::file_readable(state::THIS_REDUCER)) { abort_reducer(); break; }
      if (state::TRIAL > 1 && cfg::FIREWORKS != 1)
        echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [Trial " + std::to_string(state::TRIAL) + "] Remaining number of lines in input file: " + std::to_string(state::LINECOUNTF));
      if (currentline > state::LINECOUNTF) break;
      if (currentline == state::LINECOUNTF) state::NEXTACTION = "& progress to the next stage";
      echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [Trial " + std::to_string(state::TRIAL) + "] Now filtering line " + std::to_string(currentline) + " (Current chunk size: fixed to 1)");
      diskspace(fs::path(state::WORKT).parent_path().string());
      util::sh("sed -n \"" + std::to_string(currentline) + " ! p\" \"" + state::WORKF + "\" > \"" + state::WORKT + "\"");
      while (true) {
        int rc = run_and_check_impl();
        if (rc != 1) {
          trial_repeat++;
          if (trial_repeat < cfg::NR_OF_TRIAL_REPEATS) {
            echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] Repeating trial (Attempt " + std::to_string(trial_repeat + 1) + "/" + std::to_string(cfg::NR_OF_TRIAL_REPEATS) + ")");
            state::NEXTACTION = "& reattempt removing the same SQL line";
            continue;
          } else {
            currentline++;
            state::NEXTACTION = "& try removing next SQL line";
            if (currentline == state::LINECOUNTF) state::NEXTACTION = "& progress to the next stage";
            break;
          }
        } else break;
      }
      trial_repeat = 0;
      if (cfg::FIREWORKS != 1) {
        if (!util::file_readable(state::WORKF)) abort_reducer();
        state::LINECOUNTF = util::count_lines(state::WORKF);
      } else {
        if (!util::file_readable(cfg::INPUTFILE)) abort_reducer();
        state::LINECOUNTF = util::count_lines(cfg::INPUTFILE);
      }
      state::TRIAL++;
    }
  }

  // STAGE 3: cleanup sed transforms (from stages.tbl)
  if (cfg::SKIPSTAGEBELOW < 3 && cfg::SKIPSTAGEABOVE > 3) {
    state::NEXTACTION = "& try next testcase complexity reducing sed";
    state::STAGE = "3";
    echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] Commencing stage " + state::STAGE);
    run_stage_trials(3);
  }

  // STAGE 4: query syntax complexity sed transforms
  if (cfg::SKIPSTAGEBELOW < 4 && cfg::SKIPSTAGEABOVE > 4) {
    state::NEXTACTION = "& try next query syntax complexity reducing sed";
    state::STAGE = "4";
    echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] Commencing stage " + state::STAGE);
    run_stage_trials(4);
  }

  // STAGE 5: rename tables and views to generic tx/vx names
  if (cfg::SKIPSTAGEBELOW < 5 && cfg::SKIPSTAGEABOVE > 5) {
    state::NEXTACTION = "& try next testcase complexity reducing sed";
    state::STAGE = "5";
    state::TRIAL = 1;
    echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] Commencing stage " + state::STAGE);
    int count_tables = 0;
    try { count_tables = std::stoi(util::sh_capture_trimmed(
      "grep -E --binary-files=text \"CREATE[\\t ]*TABLE\" \"" + state::WORKF + "\" | wc -l")); } catch (...) {}
    for (int i = count_tables; i >= 1; --i) {
      if (!util::dir_exists(state::WORKD) || !util::file_readable(cfg::INPUTFILE) || !util::file_readable(state::THIS_REDUCER)) { abort_reducer(); break; }
      std::string tn = util::sh_capture_trimmed(
        "grep -E --binary-files=text -m" + std::to_string(i) + " \"CREATE[\\t ]*TABLE\" \"" + state::WORKF +
        "\" | tail -n1 | sed 's/CREATE[\\t ]*TABLE/\\n/2' | head -n1 | sed -e 's/CREATE[\\t ]*TABLE[\\t ]*\\(.*\\)[\\t ]*(/\\1/' -e 's/ .*//1' -e 's/(.*//1'");
      util::sh("sed \"s/^/ /;s/\\$/ /;s/\\([^a-zA-Z0-9_]\\)" + tn + "\\([^a-zA-Z0-9_]\\)/\\1t" + std::to_string(i) + "\\2/gi;s/^ //;s/ \\$//\" \"" + state::WORKF + "\" > \"" + state::WORKT + "\"");
      if (tn == "t" + std::to_string(i)) {
        echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [Trial " + std::to_string(state::TRIAL) + "] Skipping this trial as table " + std::to_string(i) + " is already named 't" + std::to_string(i) + "' in the file");
      } else {
        echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [Trial " + std::to_string(state::TRIAL) + "] Trying to rename table '" + tn + "' to 't" + std::to_string(i) + "'");
        run_and_check();
      }
      state::TRIAL++;
    }
    int count_views = 0;
    try { count_views = std::stoi(util::sh_capture_trimmed(
      "grep -E --binary-files=text \"CREATE[\\t ]*VIEW\" \"" + state::WORKF + "\" | wc -l")); } catch (...) {}
    for (int i = count_views; i >= 1; --i) {
      if (!util::dir_exists(state::WORKD) || !util::file_readable(cfg::INPUTFILE) || !util::file_readable(state::THIS_REDUCER)) { abort_reducer(); break; }
      std::string vn = util::sh_capture_trimmed(
        "grep -E --binary-files=text -m" + std::to_string(i) + " \"CREATE[\\t ]*VIEW\" \"" + state::WORKF +
        "\" | tail -n1 | sed 's/CREATE[\\t ]*VIEW/\\n/2' | head -n1 | sed -e 's/CREATE[\\t ]*VIEW[\\t ]*\\(.*\\)[\\t ]*(/\\1/' -e 's/ .*//1' -e 's/(.*//1'");
      util::sh("sed \"s/^/ /;s/\\$/ /;s/\\([^a-zA-Z0-9_]\\)" + vn + "\\([^a-zA-Z0-9_]\\)/\\1v" + std::to_string(i) + "\\2/gi;s/^ //;s/ \\$//\" \"" + state::WORKF + "\" > \"" + state::WORKT + "\"");
      if (vn == "v" + std::to_string(i)) {
        echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [Trial " + std::to_string(state::TRIAL) + "] Skipping this trial as view " + std::to_string(i) + " is already named 'v" + std::to_string(i) + "' in the file");
      } else {
        echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [Trial " + std::to_string(state::TRIAL) + "] Trying to rename view '" + vn + "' to 'v" + std::to_string(i) + "'");
        run_and_check();
      }
      state::TRIAL++;
    }
  }

  // STAGE 6: column elimination — mirror reducer.sh:6015..6284 (INSERT..SELECT
  // chain handling + per-column INSERT..VALUES rewrites + column rename fallback)
  if (cfg::SKIPSTAGEBELOW < 6 && cfg::SKIPSTAGEABOVE > 6) {
    state::NEXTACTION = "& try and rename this column (if it failed removal) or remove the next column";
    state::STAGE = "6";
    state::TRIAL = 1;
    if (!util::file_readable(state::WORKF)) abort_reducer();
    long long sizef = 0;
    { std::error_code ec; sizef = static_cast<long long>(fs::file_size(state::WORKF, ec)); (void)sizef; }
    echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] Commencing stage " + state::STAGE);
    // Normalise CREATE...TABLE keyword case
    util::sh("sed -i 's/CREATE\\([\\t ]\\+\\)TABLE/CREATE\\1TABLE/gI' \"" + state::WORKF + "\"");
    // Pre-step: split any single-line CREATE TABLE name (col1, col2, ...);
    if (util::sh("grep -E --binary-files=text -q \"CREATE[[:space:]]+TABLE[^(]*\\([^)]*).*;\" \"" + state::WORKF + "\"") == 0) {
      std::string awk_split =
        "awk '\n"
        "/^[[:space:]]*(--|#)/ { print; next }\n"
        "/CREATE[[:space:]]+TABLE.*\\(.*\\).*;/ {\n"
        "  line = $0; out = \"\"; depth = 0; in_str = 0; str_ch = \"\"; esc = 0\n"
        "  for (i = 1; i <= length(line); i++) {\n"
        "    c = substr(line, i, 1)\n"
        "    if (in_str) {\n"
        "      out = out c\n"
        "      if (esc) { esc = 0 }\n"
        "      else if (c == \"\\\\\") { esc = 1 }\n"
        "      else if (c == str_ch) {\n"
        "        if (substr(line, i+1, 1) == str_ch) { out = out str_ch; i++ }\n"
        "        else { in_str = 0; str_ch = \"\" }\n"
        "      }\n"
        "    } else {\n"
        "      if (c == \"\\047\" || c == \"\\\"\") { in_str = 1; str_ch = c; esc = 0; out = out c }\n"
        "      else if (c == \"(\" && depth == 0) { depth++; out = out c \"\\n\" }\n"
        "      else if (c == \"(\") { depth++; out = out c }\n"
        "      else if (c == \")\" && depth == 1) { depth--; out = out \"\\n\" c }\n"
        "      else if (c == \")\") { depth--; out = out c }\n"
        "      else if (c == \",\" && depth == 1) { out = out \",\\n\" }\n"
        "      else { out = out c }\n"
        "    }\n"
        "  }\n"
        "  print out; next\n"
        "}\n"
        "{ print }' \"" + state::WORKF + "\" > \"" + state::WORKT + "\"";
      if (util::sh(awk_split) == 0) {
        util::sh("cp -f \"" + state::WORKT + "\" \"" + state::WORKF + "\"");
        state::LINECOUNTF = util::count_lines(state::WORKF);
        echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] Pre-step: split single-line CREATE TABLE definitions for per-column processing");
      }
    }

    int count_tables = 0;
    try { count_tables = std::stoi(util::sh_capture_trimmed(
      "grep -E --binary-files=text \"CREATE[\\t ]*TABLE\" \"" + state::WORKF + "\" | wc -l")); } catch (...) {}
    for (int t = count_tables; t >= 1; --t) {
      if (!util::dir_exists(state::WORKD) || !util::file_readable(cfg::INPUTFILE) || !util::file_readable(state::THIS_REDUCER)) { abort_reducer(); break; }
      std::string tn = util::sh_capture_trimmed(
        "grep -E --binary-files=text -m" + std::to_string(t) + " \"CREATE[\\t ]*TABLE\" \"" + state::WORKF +
        "\" | tail -n1 | sed 's/CREATE[\\t ]*TABLE/\\n/2' | head -n1 | sed -e 's/CREATE[\\t ]*TABLE[\\t ]*\\(.*\\)[\\t ]*(/\\1/' -e 's/ .*//1' -e 's/(.*//1'");
      // INSERT..SELECT into THIS table from another? Skip column reduction (will be reduced when other table is processed).
      if (util::sh("grep -E --binary-files=text -qi \"INSERT.*INTO.*SELECT.*FROM.*" + tn + "\" \"" + state::WORKF + "\"") == 0) {
        echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [Trial " + std::to_string(state::TRIAL) +
               "] Skipping column reduction for table '" + tn + "' as it is present in a INSERT..SELECT..FROM " + tn);
        echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [Trial " + std::to_string(state::TRIAL) +
               "] Will now try and simplify the column names of this table ('" + tn + "') to more uniform names");
        int column = 1;
        std::string cols_raw = util::sh_capture(
          "cat \"" + state::WORKF + "\" | awk \"/CREATE.*TABLE.*" + tn + "/,/;/\" | sed 's/^ \\+//' | grep -E --binary-files=text -vi \"CREATE|ENGINE|^KEY|^PRIMARY|;\" | sed 's/ .*$//' | grep -E --binary-files=text -v \"\\(|\\)\"");
        auto cols = util::split(cols_raw, '\n');
        state::COUNTCOLS = 0;
        for (const auto& c : cols) if (!c.empty()) state::COUNTCOLS++;
        for (const auto& col : cols) {
          if (col.empty()) continue;
          if (col != "c" + std::to_string(state::C_COL_COUNTER)) {
            if (util::file_exists(state::WORKD + "/log/mysql.out")) {
              echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [Trial " + std::to_string(state::TRIAL) + "] [Column " + std::to_string(column) + "/" + std::to_string(state::COUNTCOLS) + "] Now attempting to rename column '" + col + "' to a more uniform 'c" + std::to_string(state::C_COL_COUNTER) + "'");
            }
            util::sh("sed \"s/^/ /;s/\\$/ /;s/\\([^a-zA-Z0-9_]\\)" + col + "\\([^a-zA-Z0-9_]\\)/\\1c" + std::to_string(state::C_COL_COUNTER) + "\\2/gi;s/^ //;s/ \\$//\" \"" + state::WORKF + "\" > \"" + state::WORKT + "\"");
            state::C_COL_COUNTER++;
            run_and_check();
            column++;
          } else {
            if (util::file_exists(state::WORKD + "/log/mysql.out")) {
              echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [Trial " + std::to_string(state::TRIAL) + "] [Column " + std::to_string(column) + "/" + std::to_string(state::COUNTCOLS) + "] Not renaming column '" + col + "' as it's name is already optimal");
            }
          }
        }
        state::TRIAL++;
        continue;
      }
      // INSERT..SELECT chain detection: walk through TABLENAME2, TABLENAME3, etc.
      std::vector<std::string> chain_tables; chain_tables.push_back(tn);
      std::string tmp_tn = tn;
      while (util::sh("grep -E --binary-files=text -qi \"INSERT.*INTO.*" + tmp_tn + ".*SELECT\" \"" + state::WORKF + "\"") == 0) {
        std::string next_tn = util::sh_capture_trimmed(
          "grep -E --binary-files=text \"INSERT.*INTO.*" + tmp_tn + ".*SELECT\" \"" + state::WORKF + "\" | tail -n1 | sed 's/INSERT.*INTO/\\n/2' | head -n1 | sed -e \"s/INSERT.*INTO.*" + tmp_tn + ".*SELECT.*FROM[\\t ]*\\(.*\\)/\\1/\" -e 's/ //g;s/;//g'");
        if (next_tn.empty() || next_tn == tmp_tn) break;
        chain_tables.push_back(next_tn);
        tmp_tn = next_tn;
        if (chain_tables.size() > 10) break;  // Safety bound — bash has no such cap but a runaway loop is worse than a missed chain
      }

      int column = 1;
      std::string cols_raw = util::sh_capture(
        "cat \"" + state::WORKF + "\" | awk \"/CREATE.*TABLE.*" + tn + "/,/;/\" | sed 's/^ \\+//' | grep -E --binary-files=text -vi \"CREATE|ENGINE|^KEY|^PRIMARY|;\" | sed 's/ .*$//' | grep -E --binary-files=text -v \"\\(|\\)\"");
      auto cols = util::split(cols_raw, '\n');
      state::COUNTCOLS = 0;
      for (const auto& c : cols) if (!c.empty()) state::COUNTCOLS++;

      for (const auto& col : cols) {
        if (col.empty()) continue;
        state::COLUMN = column;
        echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [Trial " + std::to_string(state::TRIAL) + "] [Column " + std::to_string(column) + "/" + std::to_string(state::COUNTCOLS) + "] Trying to eliminate column '" + col + "' in table '" + tn + "'");

        // Remove column from CREATE TABLE definition into WORKT2
        std::string workt2 = state::WORKT + ".2";
        util::sh("sed \"/CREATE.*TABLE.*" + tn + "/,/^[ ]*" + col + ".*,/s/^[ ]*" + col + ".*,//1\" \"" + state::WORKF + "\" | grep -E --binary-files=text -v \"^$\" > \"" + workt2 + "\"");
        util::sh("cp -f \"" + workt2 + "\" \"" + state::WORKT + "\"");

        std::string tablename_old = tn;
        for (size_t c_idx = 0; c_idx < chain_tables.size(); ++c_idx) {
          std::string cur_tn = chain_tables[c_idx];
          if (c_idx >= 1) {
            echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [Trial " + std::to_string(state::TRIAL) + "] [Column " + std::to_string(column) + "/" + std::to_string(state::COUNTCOLS) + "] INSERT..SELECT into this table from another one detected: removing corresponding column " + std::to_string(column) + " in table '" + cur_tn + "'");
            std::string workt3 = state::WORKT + ".3";
            std::string col_line_s = util::sh_capture_trimmed(
              "cat \"" + workt2 + "\" | grep -E --binary-files=text -m1 -n \"CREATE.*TABLE.*" + cur_tn + "\" | awk -F\":\" '{print $1}'");
            long long col_line = 0;
            try { col_line = std::stoll(col_line_s); } catch (...) {}
            col_line += column;
            util::sh("cat \"" + workt2 + "\" | sed \"" + std::to_string(col_line) + "d\" > \"" + workt3 + "\"");
            util::sh("cp -f \"" + workt3 + "\" \"" + workt2 + "\"");
            fs::remove(workt3);
          }

          // Count INSERTs for this table
          long long count_inserts = 0;
          try { count_inserts = std::stoll(util::sh_capture_trimmed(
            "for INSERT in $(cat \"" + workt2 + "\" | awk \"/(INSERT|REPLACE).*INTO.*" + cur_tn + ".*VALUES/,/;/\" | "
            "sed \"s/;/,/;s/^[ ]*(/(\\n/;s/)[ ,;]\\$/\\n)/;s/)[ ]*,[ ]*(/\\n/g\" | "
            "grep -E --binary-files=text -v \"^[ ]*[\\(\\)][ ]*\\$|INSERT\"); do echo $INSERT; done | wc -l")); } catch (...) {}
          if (count_inserts > 0) {
            if (c_idx >= 1) {
              echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [Trial " + std::to_string(state::TRIAL) + "] [Column " + std::to_string(column) + "/" + std::to_string(state::COUNTCOLS) + "] Also removing " + std::to_string(count_inserts) + " INSERT..VALUES for column " + std::to_string(column) + " in table '" + cur_tn + "' to match column removal in said table");
            } else {
              echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [Trial " + std::to_string(state::TRIAL) + "] [Column " + std::to_string(column) + "/" + std::to_string(state::COUNTCOLS) + "] Removing " + std::to_string(count_inserts) + " INSERT..VALUES for column '" + col + "' in table '" + cur_tn + "'");
            }
            for (long long i = 1; i <= count_inserts; ++i) {
              std::string fromv = util::sh_capture_trimmed(
                "for INSERT in $(cat \"" + workt2 + "\" | awk \"/(INSERT|REPLACE).*INTO.*" + cur_tn + ".*VALUES/,/;/\" | "
                "sed \"s/;/,/;s/^[ ]*(/(\\n/;s/)[ ,;]\\$/\\n)/;s/)[ ]*,[ ]*(/\\n/g\" | "
                "grep -E --binary-files=text -v \"^[ ]*[\\(\\)][ ]*\\$|INSERT\"); do echo $INSERT; done | awk \"{if(NR==" + std::to_string(i) + ") print \\$1}\"");
              std::string tov = util::sh_capture_trimmed(
                "for INSERT in $(cat \"" + workt2 + "\" | awk \"/(INSERT|REPLACE).*INTO.*" + cur_tn + ".*VALUES/,/;/\" | "
                "sed \"s/;/,/;s/^[ ]*(/(\\n/;s/)[ ,;]\\$/\\n)/;s/)[ ]*,[ ]*(/\\n/g\" | "
                "grep -E --binary-files=text -v \"^[ ]*[\\(\\)][ ]*\\$|INSERT\"); do echo $INSERT | tr ',' '\\n' | awk \"{if(NR!=" + std::to_string(column) + ") print \\$1}\"; echo \"==>==\"; "
                "done | tr '\\n' ',' | sed 's/,==>==/\\n/g' | sed 's/^,//' | awk \"{if(NR==" + std::to_string(i) + ") print \\$1}\"");
              fromv = util::sh_capture_trimmed("echo \"" + fromv + "\" | sed 's|\\\\|\\\\\\\\|g'");
              tov   = util::sh_capture_trimmed("echo \"" + tov   + "\" | sed 's|\\\\|\\\\\\\\|g'");
              util::sh("cat \"" + workt2 + "\" | sed \"s/" + fromv + "/" + tov + "/\" > \"" + state::WORKT + "\"");
              util::sh("cp -f \"" + state::WORKT + "\" \"" + workt2 + "\"");
            }
          }
        }
        fs::remove(workt2);

        if (util::file_exists(state::WORKD + "/log/mysql.out")) {
          long long lc = util::count_lines(state::WORKF);
          std::error_code ec; auto sz = fs::file_size(state::WORKF, ec);
          echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [Trial " + std::to_string(state::TRIAL) + "] [Column " + std::to_string(column) + "/" + std::to_string(state::COUNTCOLS) + "] Remaining size of input file: " + std::to_string(ec ? 0 : sz) + " bytes (" + std::to_string(lc) + " lines)");
        }
        int rc = run_and_check_impl();
        if (rc == 0) {
          // Column was not removed: try rename
          if (col != "c" + std::to_string(state::C_COL_COUNTER)) {
            if (util::file_exists(state::WORKD + "/log/mysql.out")) {
              echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [Trial " + std::to_string(state::TRIAL) + "] [Column " + std::to_string(column) + "/" + std::to_string(state::COUNTCOLS) + "] Now attempting to rename this column ('" + col + "') to a more uniform 'c" + std::to_string(state::C_COL_COUNTER) + "'");
            }
            util::sh("sed \"s/^/ /;s/\\$/ /;s/\\([^a-zA-Z0-9_]\\)" + col + "\\([^a-zA-Z0-9_]\\)/\\1c" + std::to_string(state::C_COL_COUNTER) + "\\2/gi;s/^ //;s/ \\$//\" \"" + state::WORKF + "\" > \"" + state::WORKT + "\"");
            state::C_COL_COUNTER++;
            run_and_check();
          } else if (util::file_exists(state::WORKD + "/log/mysql.out")) {
            echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [Trial " + std::to_string(state::TRIAL) + "] [Column " + std::to_string(column) + "/" + std::to_string(state::COUNTCOLS) + "] Not renaming column '" + col + "' as it's name is already optimal");
          }
          column++;
        } else {
          state::COUNTCOLS--;
        }
        (void)tablename_old;
      }
      state::TRIAL++;
    }
  }

  // STAGE 7: final cleanup sed transforms
  if (cfg::SKIPSTAGEBELOW < 7 && cfg::SKIPSTAGEABOVE > 7) {
    state::NEXTACTION = "& try next testcase complexity reducing sed";
    state::STAGE = "7";
    echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] Commencing stage " + state::STAGE);
    run_stage_trials(7);
  }

  // STAGE 8: mariadbd option simplification
  if (cfg::SKIPSTAGEBELOW < 8 && cfg::SKIPSTAGEABOVE > 8) {
    state::NEXTACTION = "& try removing next mariadbd/mysqld option";
    state::STAGE = "8";
    state::TRIAL = 1;
    util::sh("cp \"" + state::WORKF + "\" \"" + state::WORKT + "\"");
    std::string file1 = state::WORKD + "/file1";
    std::string file2 = state::WORKD + "/file2";
    echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] Commencing stage " + state::STAGE);

    auto myextra_split = [&]() -> int {
      if (!util::dir_exists(state::WORKD)) abort_reducer();
      util::sh("echo \"" + cfg::MYEXTRA + "\" | sed 's|[ \\t]\\+| |g' | tr -s ' ' '\\n' | grep -v '^[ \\t]*$' > " + state::WORKD + "/mysqld_opt.out");
      int cnt = 0;
      try { cnt = std::stoi(util::sh_capture_trimmed("wc -l < " + state::WORKD + "/mysqld_opt.out")); } catch (...) {}
      util::sh("head -n " + std::to_string(cnt/2) + " " + state::WORKD + "/mysqld_opt.out > " + file1);
      util::sh("tail -n " + std::to_string(cnt - cnt/2) + " " + state::WORKD + "/mysqld_opt.out > " + file2);
      return cnt;
    };
    auto myextra_reduction = [&]() {
      auto lines = util::split(util::sh_capture("cat " + state::WORKD + "/mysqld_opt.out"), '\n');
      long long trial_repeat = 0;
      for (const auto& line : lines) {
        if (line.empty()) continue;
        state::STAGE8_CHK = 0;
        state::STAGE8_NOT_STARTED_CORRECTLY = 0;
        echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [Trial " + std::to_string(state::TRIAL) + "] Filtering mariadbd/mysqld option " + line + " from MYEXTRA");
        cfg::MYEXTRA = util::sh_capture_trimmed("echo \"" + cfg::MYEXTRA + "\" | sed \"s|" + line + "||\"");
        while (true) {
          if (!util::dir_exists(state::WORKD) || !util::file_readable(cfg::INPUTFILE) || !util::file_readable(state::THIS_REDUCER)) { abort_reducer(); break; }
          run_and_check_impl();
          trial_repeat++;
          if (state::STAGE8_CHK == 0 || state::STAGE8_NOT_STARTED_CORRECTLY == 1) {
            if (trial_repeat < cfg::NR_OF_TRIAL_REPEATS) {
              echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] Repeating trial (Attempt " + std::to_string(trial_repeat + 1) + "/" + std::to_string(cfg::NR_OF_TRIAL_REPEATS) + ")");
              continue;
            } else {
              cfg::MYEXTRA = cfg::MYEXTRA + " " + line;
              break;
            }
          } else {
            util::sh("sed -i \"s|" + line + "||\" \"" + state::WORK_START + "\"");
            break;
          }
        }
        state::NEXTACTION = "& try removing next mariadbd/mysqld option";
        trial_repeat = 0;
        state::TRIAL++;
      }
    };

    if (cfg::NR_OF_TRIAL_REPEATS > 1) {
      util::sh("echo \"" + cfg::MYEXTRA + "\" | sed 's|[ \\t]\\+| |g' | tr -s ' ' '\\n' | grep -v '^[ \\t]*$' > " + state::WORKD + "/mysqld_opt.out");
      myextra_reduction();
    } else {
      int opt_count = myextra_split();
      if (opt_count == 0) {
        if (!util::sh_capture_trimmed("echo \"" + cfg::MYEXTRA + "\" | sed \"s|[ \\t]*||\"").empty()) {
          echoit("Assert: counted number of mariadbd/mysqld options was zero, yet $MYEXTRA is not empty");
          std::exit(1);
        }
        echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] Skipping this stage as the testcase does not contain extraneous mariadbd/mysqld options");
      } else if (opt_count >= 1 && opt_count <= 4) {
        myextra_reduction();
      } else {
        while (true) {
          std::string save_myextra = cfg::MYEXTRA;
          cfg::MYEXTRA = util::sh_capture_trimmed("cat " + file1 + " | tr -s '\\n' ' ' | sed 's|[ \\t]\\+| |g;s| $||g;s|^ ||g'");
          state::STAGE8_CHK = 0; state::STAGE8_NOT_STARTED_CORRECTLY = 0;
          echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [Trial " + std::to_string(state::TRIAL) + "] Using first set of mariadbd/mysqld option(s) from MYEXTRA: " + cfg::MYEXTRA);
          run_and_check();
          state::TRIAL++;
          if (state::STAGE8_CHK == 0 || state::STAGE8_NOT_STARTED_CORRECTLY == 1) {
            cfg::MYEXTRA = util::sh_capture_trimmed("cat " + file2 + " | tr -s '\\n' ' ' | sed 's|[ \\t]\\+| |g;s| $||g;s|^ ||g'");
            state::STAGE8_CHK = 0; state::STAGE8_NOT_STARTED_CORRECTLY = 0;
            echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [Trial " + std::to_string(state::TRIAL) + "] Using second set of mariadbd/mysqld option(s) from MYEXTRA: " + cfg::MYEXTRA);
            run_and_check();
            state::TRIAL++;
            if (state::STAGE8_CHK == 0 || state::STAGE8_NOT_STARTED_CORRECTLY == 1) {
              cfg::MYEXTRA = save_myextra;
              myextra_reduction();
              break;
            } else {
              auto file1_lines = util::split(util::sh_capture("cat " + file1), '\n');
              for (const auto& l : file1_lines) if (!l.empty()) util::sh("sed -i \"s|" + l + "||\" \"" + state::WORK_START + "\"");
              opt_count = myextra_split();
              if (opt_count <= 4) { myextra_reduction(); break; }
            }
          } else {
            auto file2_lines = util::split(util::sh_capture("cat " + file2), '\n');
            for (const auto& l : file2_lines) if (!l.empty()) util::sh("sed -i \"s|" + l + "||\" \"" + state::WORK_START + "\"");
            opt_count = myextra_split();
            if (opt_count <= 4) { myextra_reduction(); break; }
          }
        }
      }
    }
  }

  // STAGE 9: storage engine / binlog / keyring etc. simplification
  if (cfg::SKIPSTAGEBELOW < 9 && cfg::SKIPSTAGEABOVE > 9) {
    state::NEXTACTION = "";
    state::STAGE = "9";
    state::TRIAL = 1;
    echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] Commencing stage " + state::STAGE);
    util::sh("cp \"" + state::WORKF + "\" \"" + state::WORKT + "\"");
    if (!cfg::TOKUDB.empty()) {
      echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [Trial " + std::to_string(state::TRIAL) + "] Removing TokuDB storage engine from startup options");
      stage9_run(cfg::TOKUDB);
    }
    if (!cfg::ROCKSDB.empty()) {
      echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [Trial " + std::to_string(state::TRIAL) + "] Removing RocksDB storage engine from startup options");
      stage9_run(cfg::ROCKSDB);
    }
    if (!cfg::BL_ENCRYPTION.empty()) {
      echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [Trial " + std::to_string(state::TRIAL) + "] Removing Binary Logs encryption from startup options");
      stage9_run(cfg::BL_ENCRYPTION);
    }
    if (!cfg::KF_ENCRYPTION.empty()) {
      echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [Trial " + std::to_string(state::TRIAL) + "] Removing Keyring File encryption from startup options");
      stage9_run(cfg::KF_ENCRYPTION);
    }
    if (!cfg::BINLOG.empty()) {
      echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [Trial " + std::to_string(state::TRIAL) + "] Removing Binary logging from startup options");
      stage9_run(cfg::BINLOG);
    }
    if (!cfg::ONLYFULLGROUPBY.empty()) {
      echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [Trial " + std::to_string(state::TRIAL) + "] Removing ONLY_FULL_GROUP_BY SQL Mode from startup options");
      stage9_run("ONLY_FULL_GROUP_BY");
      if (STAGE9_CHK != 0 && state::STAGE9_NOT_STARTED_CORRECTLY != 1) {
        echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [Trial " + std::to_string(state::TRIAL) + "] Removing SQL Mode (--sql_mode=) from startup options");
        stage9_run("--sql_mode=");
      }
    }
    if (!cfg::MYINIT.empty()) {
      echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [Trial " + std::to_string(state::TRIAL) + "] Removing MYINIT options from startup options & from mariadbd/mysqld initialization");
      std::string filt = util::sh_capture_trimmed("echo " + cfg::MYINIT + " | sed 's|^[ \\t]\\+||;s|[ \\t]\\+$||'");
      MYINIT_DROP = 1;
      stage9_run(filt);
    }
    if (!cfg::MYINIT.empty()) {
      echoit(state::ATLEASTONCE + " [Stage " + state::STAGE + "] [Trial " + std::to_string(state::TRIAL) + "] Removing MYINIT options from mariadbd/mysqld initialization");
      MYINIT_DROP = 1;
      stage9_run("");
    }
  }

  finish(cfg::INPUTFILE);
  return 0;
}
