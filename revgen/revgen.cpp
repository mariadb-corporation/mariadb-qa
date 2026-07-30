// revgen - reverse SQL generator driven by the MariaDB bison grammar.
//
// Reads a sql_yacc.yy grammar, replays the MARIADB/ORACLE preprocessor
// (keeping the MARIADB branch), builds the rule set, then derives random
// statements top-down up to a depth budget. Identifier leaves are filled with
// names typed by the slot they sit in - t1-t4 tables, c1-c4 columns, sp/f for
// stored procedures and functions, p for partitions, and so on (kNameKinds) -
// so a name a statement creates is a name a later statement can reference.
// Literal tokens get random data; keyword tokens resolve to real SQL text via
// the sibling lex.h symbol tables. Statement classes are weighted
// (kVerbWeights) and kSetupSql is interjected at intervals, so the generated
// DML has real tables to work on and the session recovers from held locks.
//
// Generation is multi-threaded. Output can be PREPARE-checked (drop
// session-releasing / known-bad statements) and PREPARE-validated against a
// live server, dropping statements the server rejects with a parse error.

#include <algorithm>
#include <atomic>
#include <bit>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <map>
#include <mutex>
#include <optional>
#include <random>
#include <sstream>
#include <string>
#include <thread>
#include <unordered_map>
#include <unordered_set>
#include <vector>

#include <mysql/mysql.h>
#include <unistd.h>

namespace {

constexpr int kInf = 1 << 29;

// xoshiro256++ - BigCrush-clean 64-bit PRNG, period 2^256-1 (same RNG as generatorcpp).
// Seeded via splitmix64 from a high-entropy mix (random_device + clock + pid).
struct Xoshiro256pp {
  uint64_t s[4];
  Xoshiro256pp() = default;
  explicit Xoshiro256pp(uint64_t z) { seed(z); }
  static inline uint64_t splitmix64(uint64_t &x) {
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
  inline uint64_t next() {
    const uint64_t result = std::rotl(s[0] + s[3], 23) + s[0];
    const uint64_t t = s[1] << 17;
    s[2] ^= s[0]; s[3] ^= s[1]; s[1] ^= s[2]; s[0] ^= s[3];
    s[2] ^= t;
    s[3] = std::rotl(s[3], 45);
    return result;
  }
  uint64_t operator()() { return next(); }  // lets call sites use rng_() directly
};

// Identifier kinds. A name is generated from the kind of slot it sits in, so
// the name a statement creates is the name a later statement references. Keep
// the order in step with kNameKinds.
enum class Role {
  Generic, Table, Column, Proc, Func, View, Trigger, Event, Sequence,
  Index, Constraint, Partition, Savepoint, User, RoleName, Var, Db, Server,
  Cursor, Alias, Stmt, ColumnSeq, SysVar, ExplainFormat
};

// A keyword appearing in a production types the identifiers that come after it
// in that same production. The grammar routes both CREATE PROCEDURE and CREATE
// FUNCTION through sp_name, and a savepoint or partition name is often a bare
// ident, so the enclosing rule name alone cannot tell them apart.
const std::unordered_map<std::string, Role> kKeywordRoles = {
    {"PROCEDURE_SYM", Role::Proc},     {"CALL_SYM", Role::Proc},
    {"FUNCTION_SYM", Role::Func},      {"VIEW_SYM", Role::View},
    {"TRIGGER_SYM", Role::Trigger},    {"EVENT_SYM", Role::Event},
    {"SEQUENCE_SYM", Role::Sequence},  {"INDEX_SYM", Role::Index},
    {"CONSTRAINT_SYM", Role::Constraint},
    {"PARTITION_SYM", Role::Partition},
    {"SUBPARTITION_SYM", Role::Partition},
    {"SAVEPOINT_SYM", Role::Savepoint}, {"ROLE_SYM", Role::RoleName},
    {"DATABASE", Role::Db},            {"SCHEMA", Role::Db},
    {"SERVER_SYM", Role::Server},   {"PRECEDES_SYM", Role::Trigger},
    {"FOLLOWS_SYM", Role::Trigger}, {"NEXTVAL_SYM", Role::Sequence},
    {"LASTVAL_SYM", Role::Sequence}, {"SETVAL_SYM", Role::Sequence},
    {"PREVIOUS_SYM", Role::Sequence}, {"NEXT_SYM", Role::Sequence}};

// Relative weights for the verb_clause alternatives (the statement classes).
// An unweighted walk picks one of the 48 alternatives uniformly, which puts
// every class near 2%. The weight sits on the statements that carry the deep
// expression and subquery grammar - SELECT, the SELECT inside INSERT/REPLACE,
// and the WHERE/subquery side of UPDATE/DELETE. Tables come from kSetupSql
// rather than from the grammar's own CREATE TABLE, which almost never derives a
// column list. Anything not listed gets kDefaultVerbWeight, so the whole
// grammar stays reachable.
constexpr int kDefaultVerbWeight = 1;
const std::unordered_map<std::string, int> kVerbWeights = {
    {"select", 26},     {"insert", 16}, {"update", 8}, {"delete", 8},
    {"replace", 6},     {"set", 6},     {"create", 6}, {"alter", 5},
    {"select_into", 4}, {"show", 2},    {"call", 2},   {"drop", 2}};

// Schema and session reset, interjected into the generated SQL. Two reasons it
// is needed. A grammar walk cannot build a usable table: its CREATE TABLE
// derivations almost never reach a plain column list, so t1/t2 would never
// exist and the generated DML would have nothing to act on. And a walk freely
// emits statements that leave the session unusable - a held table or backup
// lock, an open read-only transaction - after which everything else fails. One
// of these is emitted every --schema-every statements, using the t1/t2 and
// c1/c2 names the identifier leaves produce.
// Emitted as a block at every interval. A held table or backup lock rejects
// every other table until it is released, and LOCK TABLES turns up about once
// per 130 statements, so releasing has to be at least as frequent.
const char *kResetSql[] = {"UNLOCK TABLES", "BACKUP UNLOCK", "COMMIT"};
constexpr size_t kResetCount = sizeof(kResetSql) / sizeof(kResetSql[0]);

const char *kSetupSql[] = {
    "CREATE TABLE IF NOT EXISTS t1 (c1 INT NOT NULL AUTO_INCREMENT PRIMARY KEY, c2 VARCHAR(100) DEFAULT 'd', c3 TEXT DEFAULT 'd', c4 DECIMAL(10,2) DEFAULT 0, KEY(c2)) ENGINE=InnoDB PARTITION BY HASH(c1) (PARTITION p1, PARTITION p2)",
    "CREATE TABLE IF NOT EXISTS t2 (c1 INT NOT NULL AUTO_INCREMENT PRIMARY KEY, c2 DATETIME DEFAULT NOW(), c3 BLOB DEFAULT 'd', c4 DOUBLE DEFAULT 0, KEY(c2)) ENGINE=InnoDB WITH SYSTEM VERSIONING",
    "CREATE TABLE IF NOT EXISTS t3 (c1 INT NOT NULL AUTO_INCREMENT PRIMARY KEY, c2 CHAR(10) DEFAULT 'd', c3 VARCHAR(200) DEFAULT 'd', c4 BIGINT UNSIGNED DEFAULT 0, KEY(c2)) ENGINE=Aria PARTITION BY HASH(c1) (PARTITION p1, PARTITION p2)",
    "CREATE TABLE IF NOT EXISTS t4 (c1 INT NOT NULL AUTO_INCREMENT PRIMARY KEY, c2 VARCHAR(50) DEFAULT 'd', c3 VARBINARY(64) DEFAULT 'd', c4 FLOAT DEFAULT 0, KEY(c2)) ENGINE=MyISAM",
    "INSERT IGNORE INTO t1 (c2,c3,c4) VALUES ('a','x',1.5),('b','y',2.5),(REPEAT('c',90),NULL,3.5)",
    "INSERT IGNORE INTO t2 (c2,c3,c4) VALUES (NOW(),'x',1.5),('2020-01-01 10:20:30',NULL,2.5)",
    "INSERT IGNORE INTO t3 (c2,c3,c4) VALUES ('a','x',1),('b','y',2)",
    "INSERT IGNORE INTO t4 (c2,c3,c4) VALUES ('a','x',1.5),('b','y',2.5)",
    // A generated ALTER can coalesce or remove the partitions, and CREATE TABLE
    // IF NOT EXISTS will not put them back on a table that still exists. Only
    // t1 and t3 are partitioned: naming a partitioned table in DML with a
    // PARTITION() clause hits a known partitioning assert often enough that
    // partitioning all four tables spent a third of the trials on it, so two
    // tables carry partitions and two do not.
    "ALTER TABLE t1 PARTITION BY HASH(c1) (PARTITION p1, PARTITION p2)",
    "ALTER TABLE t3 PARTITION BY HASH(c1) (PARTITION p1, PARTITION p2)",
    "CREATE SEQUENCE IF NOT EXISTS sq1 START WITH 1 INCREMENT BY 1",
    "CREATE SEQUENCE IF NOT EXISTS sq2 START WITH 100 INCREMENT BY 2",
    // The identifier leaves name routines and views (sp1, f1, v1) wherever the
    // grammar has a slot for one, so without these every CALL and every
    // function call comes back as "does not exist" and the whole statement is
    // lost. One takes no argument and one takes an integer, so both call shapes
    // resolve.
    "CREATE OR REPLACE PROCEDURE sp1() SELECT c1, c2 FROM t1 LIMIT 3",
    "CREATE OR REPLACE PROCEDURE sp2(a INT) SELECT c1 FROM t3 WHERE c1 > a LIMIT 3",
    "CREATE OR REPLACE FUNCTION f1() RETURNS INT DETERMINISTIC RETURN 1",
    "CREATE OR REPLACE FUNCTION f2(a INT) RETURNS INT DETERMINISTIC RETURN a + 1",
    "CREATE OR REPLACE VIEW v1 AS SELECT c1, c2, c3, c4 FROM t1",
    "CREATE OR REPLACE VIEW v2 AS SELECT c1, c2 FROM t3 WHERE c1 > 0"};
constexpr size_t kSetupCount = sizeof(kSetupSql) / sizeof(kSetupSql[0]);

// A statement holding any of these is derived again instead. Each one either ends
// the session, stops the server, stalls the run, or sets a variable to a value that
// makes everything after it useless. Case as the walk emits it: keywords upper,
// system variables lower.
const char *kSkipText[] = {"RELEASE", "SHUTDOWN", "SLEEP", "dbug",
                           "KILL", "key_buffer_size", "net_retry_count",
                           "innodb_flush_log_at_timeout"};
constexpr size_t kSkipCount = sizeof(kSkipText) / sizeof(kSkipText[0]);

bool skip_statement(const std::string &sql) {
  for (size_t i = 0; i < kSkipCount; ++i)
    if (sql.find(kSkipText[i]) != std::string::npos) return true;
  return false;
}

// Rule head -> per-alternative hit count. Ordered so the report is stable.
using Coverage = std::map<std::string, std::vector<long>>;

// How the walk spent its choices. exits are the choices where nothing fitted the
// remaining depth, so a shortest alternative was forced; a high share of those
// means the depth budget, not the weighting, is picking the SQL. lends are the
// choices that borrowed depth to take an alternative that overshot the budget.
struct GenStats {
  long choices = 0, exits = 0, lends = 0;
  // For --probe RULE: how much depth was left each time that rule was entered,
  // and how many of its alternatives that depth could pay for. A rule entered at
  // depth 1 can only ever take its cheapest alternative, however it is weighted.
  long probe_hits = 0, probe_alts = 0;
  std::map<int, long> probe_depth, probe_afford;
  void operator+=(const GenStats &o) {
    choices += o.choices; exits += o.exits; lends += o.lends;
    probe_hits += o.probe_hits;
    if (o.probe_alts) probe_alts = o.probe_alts;
    for (const auto &kv : o.probe_depth) probe_depth[kv.first] += kv.second;
    for (const auto &kv : o.probe_afford) probe_afford[kv.first] += kv.second;
  }
};

struct Sym {
  bool char_lit = false;  // true: emit text verbatim; false: named symbol
  std::string text;
  // Index into the grammar's symbol table, assigned by Grammar::intern() after
  // parsing and pruning. Every per-symbol fact the walk needs is kept in arrays
  // indexed by this, because looking those facts up by name was the bulk of the
  // run: three string-keyed hash maps and the hash itself came to 59% of the time.
  int id = -1;
};
using Production = std::vector<Sym>;

// A production as grammar text, for the diagnostics.
std::string production_text(const Production &p) {
  if (p.empty()) return "<empty>";
  std::string s;
  for (const Sym &y : p) {
    if (!s.empty()) s += ' ';
    s += y.char_lit ? "'" + y.text + "'" : y.text;
  }
  return s;
}

// ---- file IO -------------------------------------------------------------

std::string read_file(const std::string &path) {
  std::ifstream in(path, std::ios::binary);
  if (!in) {
    std::cerr << "revgen: cannot open " << path << "\n";
    std::exit(2);
  }
  std::ostringstream ss;
  ss << in.rdbuf();
  return ss.str();
}

std::string trim(const std::string &s) {
  size_t a = s.find_first_not_of(" \t\r\n");
  if (a == std::string::npos) return "";
  size_t b = s.find_last_not_of(" \t\r\n");
  return s.substr(a, b - a + 1);
}

// Replay gen_yy_files.cmake: keep the common lines and the MARIADB branch,
// drop the ORACLE branch. Directive lines become blank (line count kept).
std::string preprocess_mariadb(const std::string &data) {
  std::istringstream in(data);
  std::string line, out;
  int where = 0;  // 0 common, 1 ORACLE (drop), 2 MARIADB (keep)
  while (std::getline(in, line)) {
    std::string t = trim(line);
    bool directive = true;
    if (t.rfind("%ifdef", 0) == 0 && t.find("ORACLE") != std::string::npos) {
      where = 1;
    } else if (t.rfind("%ifdef", 0) == 0 &&
               t.find("MARIADB") != std::string::npos) {
      where = 2;
    } else if (t.rfind("%else", 0) == 0 && where > 0) {
      where = 3 - where;
    } else if (t.rfind("%endif", 0) == 0) {
      where = 0;
    } else {
      directive = false;
    }
    if (!directive && (where == 0 || where == 2)) out += line;
    out += '\n';
  }
  return out;
}

// ---- grammar scanner -----------------------------------------------------

struct Token {
  enum Kind { Ident, CharLit, Colon, Pipe, Semi, End } kind;
  std::string text;
};

class Scanner {
 public:
  explicit Scanner(std::string s) : s_(std::move(s)) {}

  void unget(const Token &t) { pb_.push_back(t); }

  // True once an action was skipped whose body only raises a parse error; the
  // production it belongs to can never be typed. Cleared by the reader.
  bool take_action_error() {
    bool v = action_error_;
    action_error_ = false;
    return v;
  }

  Token next() {
    if (!pb_.empty()) { Token t = pb_.back(); pb_.pop_back(); return t; }
    for (;;) {
      if (pos_ >= s_.size()) return {Token::End, ""};
      char c = s_[pos_];
      if (c == ' ' || c == '\t' || c == '\r' || c == '\n') { ++pos_; continue; }
      if (c == '/' && peek(1) == '*') { skip_block_comment(); continue; }
      if (c == '/' && peek(1) == '/') { skip_line_comment(); continue; }
      if (c == '{') { skip_action(); continue; }
      if (c == '"') { skip_dquote(); continue; }
      if (c == '\'') return maybe_drop(read_char_lit());
      if (c == '%') { handle_directive(); continue; }
      if (c == ':') { ++pos_; return maybe_drop({Token::Colon, ":"}); }
      if (c == '|') { ++pos_; return maybe_drop({Token::Pipe, "|"}); }
      if (c == ';') { ++pos_; return maybe_drop({Token::Semi, ";"}); }
      if (is_ident_start(c)) return maybe_drop(read_ident());
      ++pos_;  // stray punctuation outside any construct
    }
  }

 private:
  char peek(size_t d) const {
    return pos_ + d < s_.size() ? s_[pos_ + d] : '\0';
  }
  static bool is_ident_start(char c) {
    return std::isalpha((unsigned char)c) || c == '_';
  }
  static bool is_ident(char c) {
    return std::isalnum((unsigned char)c) || c == '_';
  }

  // A %prec directive is followed by one symbol that must not enter output.
  Token maybe_drop(Token t) {
    if (drop_next_ && (t.kind == Token::Ident || t.kind == Token::CharLit)) {
      drop_next_ = false;
      return next();
    }
    return t;
  }

  Token read_ident() {
    size_t start = pos_;
    while (pos_ < s_.size() && is_ident(s_[pos_])) ++pos_;
    return {Token::Ident, s_.substr(start, pos_ - start)};
  }

  Token read_char_lit() {
    ++pos_;  // opening quote
    std::string out;
    while (pos_ < s_.size() && s_[pos_] != '\'') {
      if (s_[pos_] == '\\' && pos_ + 1 < s_.size()) {
        out += s_[pos_ + 1];  // decode a backslash escape to its char
        pos_ += 2;
      } else {
        out += s_[pos_++];
      }
    }
    if (pos_ < s_.size()) ++pos_;  // closing quote
    return {Token::CharLit, out};
  }

  void handle_directive() {
    size_t start = pos_ + 1;
    size_t p = start;
    while (p < s_.size() && std::isalpha((unsigned char)s_[p])) ++p;
    std::string word = s_.substr(start, p - start);
    pos_ = p;
    if (word == "prec") {
      drop_next_ = true;  // discard the following symbol
    } else if (word == "empty") {
      // marks an empty production; contributes nothing
    } else {
      while (pos_ < s_.size() && s_[pos_] != '\n') ++pos_;  // skip line
    }
  }

  void skip_block_comment() {
    pos_ += 2;
    while (pos_ + 1 < s_.size() && !(s_[pos_] == '*' && s_[pos_ + 1] == '/'))
      ++pos_;
    pos_ = std::min(pos_ + 2, s_.size());
  }
  void skip_line_comment() {
    while (pos_ < s_.size() && s_[pos_] != '\n') ++pos_;
  }
  void skip_dquote() {
    ++pos_;
    while (pos_ < s_.size() && s_[pos_] != '"') {
      if (s_[pos_] == '\\') ++pos_;
      ++pos_;
    }
    if (pos_ < s_.size()) ++pos_;
  }

  // Skip a balanced { } semantic action, honouring strings/chars/comments.
  // The grammar carries productions that exist only to give a better message,
  // e.g. LIMIT n ROWS EXAMINED { thd->parse_error(); MYSQL_YYABORT; }. Walking
  // one always yields invalid SQL, so flag it. A conditional parse_error is a
  // normal production and is left alone.
  void skip_action() {
    const size_t begin = pos_;
    int depth = 0;
    while (pos_ < s_.size()) {
      char c = s_[pos_];
      if (c == '/' && peek(1) == '*') { skip_block_comment(); continue; }
      if (c == '/' && peek(1) == '/') { skip_line_comment(); continue; }
      if (c == '"') { skip_dquote(); continue; }
      if (c == '\'') { read_char_lit(); continue; }
      if (c == '{') ++depth;
      else if (c == '}') {
        --depth;
        if (depth == 0) {
          ++pos_;
          const std::string body = s_.substr(begin, pos_ - begin);
          if (body.find("parse_error") != std::string::npos &&
              body.find("if") == std::string::npos)
            action_error_ = true;
          return;
        }
      }
      ++pos_;
    }
  }

  std::string s_;
  size_t pos_ = 0;
  bool drop_next_ = false;
  bool action_error_ = false;
  std::vector<Token> pb_;
};

// ---- grammar model -------------------------------------------------------

class Grammar {
 public:
  void parse(const std::string &rules) {
    Scanner sc(rules);
    Token t = sc.next();
    while (t.kind != Token::End) {
      if (t.kind != Token::Ident) { t = sc.next(); continue; }
      std::string head = t.text;
      Token colon = sc.next();
      if (colon.kind != Token::Colon) { t = colon; continue; }
      std::vector<Production> &prods = rules_[head];
      if (order_.find(head) == order_.end()) {
        order_.insert(head);
        heads_.push_back(head);
      }
      Production cur;
      bool bad = false;  // production carries an unconditional parse_error
      for (;;) {
        Token x = sc.next();
        bad = bad || sc.take_action_error();
        if (x.kind == Token::Pipe) {
          if (!bad) prods.push_back(cur);
          else ++error_prods_;
          cur.clear(); bad = false;
        }
        else if (x.kind == Token::Semi || x.kind == Token::End) {
          if (!bad) prods.push_back(cur); else ++error_prods_;
          break;
        }
        else if (x.kind == Token::CharLit) cur.push_back({true, x.text});
        else if (x.kind == Token::Ident) {
          // GNU bison lets a rule omit its trailing ';'. If this ident is
          // immediately followed by ':', it is the next rule's head, not a
          // symbol - so the current rule ends here.
          Token nx = sc.next();
          if (nx.kind == Token::Colon) {
            sc.unget(nx); sc.unget(x);
            if (!bad) prods.push_back(cur); else ++error_prods_;
            break;
          }
          sc.unget(nx);
          cur.push_back({false, x.text});
        }
        // a stray Colon mid-rule is ignored
      }
      t = sc.next();
    }
  }

  // Drop every production that references an excluded name, then the excluded
  // rules themselves. Used to remove internal, un-typeable parser entries.
  void prune(const std::unordered_set<std::string> &ex) {
    for (auto &kv : rules_) {
      auto &prods = kv.second;
      prods.erase(std::remove_if(prods.begin(), prods.end(),
                                 [&](const Production &p) {
                                   for (const Sym &s : p)
                                     if (!s.char_lit && ex.count(s.text))
                                       return true;
                                   return false;
                                 }),
                  prods.end());
    }
    for (const auto &e : ex) { rules_.erase(e); order_.erase(e); }
    std::vector<std::string> keep;
    for (const std::string &h : heads_)
      if (rules_.count(h)) keep.push_back(h);
    heads_.swap(keep);
  }

  // Drop the productions of one rule that reference every listed symbol, or
  // keep only those. Prefix a symbol with '!' to require its absence. Used to remove a single self-destructive or always-invalid
  // alternative without losing the rule. Symbols match named tokens and
  // character literals alike, so "." selects the qualified-name alternatives.
  // Drop the productions of a rule that hold more than n symbols. For the
  // qualified-name rules the alternatives differ only in how many qualifiers
  // they carry, which a symbol-set match cannot tell apart.
  void prune_longer_than(const std::string &head, size_t n) {
    auto it = rules_.find(head);
    if (it == rules_.end()) return;
    auto &prods = it->second;
    prods.erase(std::remove_if(prods.begin(), prods.end(),
                               [n](const Production &p) { return p.size() > n; }),
                prods.end());
  }

  void prune_production(const std::string &head,
                        const std::vector<std::string> &syms) {
    filter_productions(head, syms, false);
  }
  void keep_production(const std::string &head,
                       const std::vector<std::string> &syms) {
    filter_productions(head, syms, true);
  }

  // Drop productions referencing an Oracle-mode-only token (name contains
  // "ORACLE"). The MARIADB-mode lexer never emits these, so such an alternative
  // is dead - keeping it lets the generator pick a silent token and emit an
  // empty slot (e.g. NUMBER_ORACLE_SYM in statement_information_item_name).
  void drop_oracle_productions() {
    for (auto &kv : rules_) {
      auto &prods = kv.second;
      prods.erase(std::remove_if(prods.begin(), prods.end(),
                                 [](const Production &p) {
                                   for (const Sym &s : p)
                                     if (!s.char_lit &&
                                         s.text.find("ORACLE") !=
                                             std::string::npos)
                                       return true;
                                   return false;
                                 }),
                  prods.end());
    }
  }

  // Number every symbol that appears anywhere, and record each one's productions.
  // Called once, after the grammar is final and before any thread starts, so the
  // ids the walk reads are fixed and shared read-only.
  void intern() {
    auto id_for = [&](const std::string &name) {
      auto it = ids_.find(name);
      if (it != ids_.end()) return it->second;
      const int id = (int)names_.size();
      ids_.emplace(name, id);
      names_.push_back(name);
      return id;
    };
    for (const std::string &h : heads_) id_for(h);
    for (const std::string &h : heads_)
      for (Production &pr : rules_.at(h))
        for (Sym &sy : pr) sy.id = sy.char_lit ? -1 : id_for(sy.text);
    prods_.assign(names_.size(), nullptr);
    for (const std::string &h : heads_) prods_[ids_.at(h)] = &rules_.at(h);
  }
  int symbol_id(const std::string &n) const {
    auto it = ids_.find(n);
    return it == ids_.end() ? -1 : it->second;
  }
  size_t symbol_count() const { return names_.size(); }
  const std::string &symbol_name(int id) const { return names_[(size_t)id]; }
  // Null for a terminal: it has no productions of its own.
  const std::vector<Production> *productions_by_id(int id) const {
    return id < 0 ? nullptr : prods_[(size_t)id];
  }

  bool is_nonterminal(const std::string &n) const {
    return rules_.count(n) != 0;
  }
  const std::vector<Production> &productions(const std::string &n) const {
    return rules_.at(n);
  }
  size_t rule_count() const { return rules_.size(); }
  size_t error_prod_count() const { return error_prods_; }
  const std::vector<std::string> &heads() const { return heads_; }

  void dump(const std::string &name) const {
    auto it = rules_.find(name);
    if (it == rules_.end()) { std::cerr << name << ": <not a rule>\n"; return; }
    std::cerr << name << ": (" << it->second.size() << " productions)\n";
    for (const Production &p : it->second) {
      std::cerr << "  |";
      for (const Sym &s : p)
        std::cerr << ' ' << (s.char_lit ? "'" + s.text + "'" : s.text);
      std::cerr << "\n";
    }
  }

  // Report every production of the form '(' X ')' where X can derive nothing,
  // so the pair renders as an empty "()" that the server rejects. Finds the
  // whole family in one pass instead of one rule at a time.
  void audit_empty_parens() const {
    std::unordered_set<std::string> nullable;
    for (const auto &kv : rules_)
      for (const Production &p : kv.second)
        if (p.empty()) nullable.insert(kv.first);
    // Scan every position, not just a production that is exactly '(' X ')'.
    // The empty-argument-list cases that matter sit behind a keyword -
    // CONTAINS_SYM '(' opt_expr_list ')' - and a whole-production match misses
    // every one of them.
    for (const std::string &h : heads_)
      for (const Production &p : rules_.at(h))
        for (size_t i = 0; i + 2 < p.size(); ++i) {
          if (!p[i].char_lit || p[i].text != "(") continue;
          if (!p[i + 2].char_lit || p[i + 2].text != ")") continue;
          if (p[i + 1].char_lit || !nullable.count(p[i + 1].text)) continue;
          std::cout << h << " : '(' " << p[i + 1].text << " ')'  in  "
                    << production_text(p) << "\n";
        }
  }

  // Count distinct named symbols referenced that are not rule heads.
  size_t terminal_count() const { return terminal_refs().size(); }

  // Referenced named terminals -> number of productions referencing them.
  std::unordered_map<std::string, int> terminal_refs() const {
    std::unordered_map<std::string, int> t;
    for (const auto &kv : rules_)
      for (const Production &p : kv.second)
        for (const Sym &s : p)
          if (!s.char_lit && !rules_.count(s.text)) ++t[s.text];
    return t;
  }

 private:
  void filter_productions(const std::string &head,
                          const std::vector<std::string> &syms, bool keep) {
    auto it = rules_.find(head);
    if (it == rules_.end()) return;
    auto &prods = it->second;
    // A symbol prefixed with '!' must be absent for the production to match.
    // The sentinel "<empty>" matches a production with no symbols at all.
    auto matches = [&](const Production &p) {
      for (const std::string &n : syms) {
        if (n == "<empty>") { if (!p.empty()) return false; continue; }
        bool want = n[0] != '!';
        const std::string t = want ? n : n.substr(1);
        bool seen = false;
        for (const Sym &s : p)
          if (s.text == t) { seen = true; break; }
        if (seen != want) return false;
      }
      return true;
    };
    prods.erase(std::remove_if(prods.begin(), prods.end(),
                               [&](const Production &p) {
                                 return matches(p) != keep;
                               }),
                prods.end());
  }

  size_t error_prods_ = 0;
  std::unordered_map<std::string, std::vector<Production>> rules_;
  std::unordered_set<std::string> order_;
  std::vector<std::string> heads_;
  std::unordered_map<std::string, int> ids_;
  std::vector<std::string> names_;
  std::vector<const std::vector<Production> *> prods_;
};

// ---- lexer keyword table -------------------------------------------------

// Parse lex.h { "KEYWORD", SYM(TOKEN) } entries into token -> keyword.
std::unordered_map<std::string, std::string> load_keywords(
    const std::string &lex) {
  std::unordered_map<std::string, std::string> map;
  size_t p = 0;
  while ((p = lex.find("SYM(", p)) != std::string::npos) {
    // walk back to the "..." keyword before SYM(
    size_t q = lex.rfind('"', p);
    if (q == std::string::npos) { p += 4; continue; }
    size_t q0 = lex.rfind('"', q - 1);
    if (q0 == std::string::npos) { p += 4; continue; }
    std::string kw = lex.substr(q0 + 1, q - q0 - 1);
    size_t e = lex.find(')', p);
    if (e == std::string::npos) break;
    std::string tok = trim(lex.substr(p + 4, e - (p + 4)));
    if (!tok.empty() && map.find(tok) == map.end() && !kw.empty())
      map[tok] = kw;
    p = e + 1;
  }
  return map;
}

// ---- generator -----------------------------------------------------------

class Generator {
 public:
  Generator(const Grammar &g,
            const std::unordered_map<std::string, std::string> &kw,
            uint64_t seed, int max_chain = 3, int chain_share = 30,
            int grants = 2)
      : g_(g), kw_(kw), rng_(seed), max_chain_(max_chain),
        grants_start_(grants), chain_share_(chain_share) {
    build_roles();
    build_leaves();
    compute_min_height();
    build_symbols();
  }

  // With a range configured, one statement in four is derived deeper. The
  // constructs worth reaching - a subquery, a UNION, a CTE - need a derivation
  // around 20 levels deep (revgen --trace shows subselect at 21), while most
  // statements are better off short so the trial gets through more of them.
  std::string generate_mixed(const std::string &start, int depth, int depth_max) {
    int d = depth;
    if (depth_max > depth && (rng_() & 3) == 0)
      d = depth + 1 + (int)(rng_() % (uint64_t)(depth_max - depth));
    return generate(start, d);
  }

  // True when the last generate() ran into kMaxSteps or kMaxTokens, so the walk
  // stopped part-way and the statement it returned is cut off.
  bool truncated() const { return truncated_; }

  std::string generate(const std::string &start, int depth) {
    tokens_.clear();
    steps_ = 0;
    truncated_ = false;
    pending_ = Role::Generic;
    sticky_role_ = Role::Generic;
    for (unsigned &c : seq_) c = 0;
    expand({false, start, g_.symbol_id(start)}, depth, Role::Generic, 0);
    return join();
  }

  // Print the deterministic minimum-height derivation of a symbol, flagging
  // silent terminals and empty productions - the sources of degenerate output.
  void trace_min(const std::string &start) {
    trace_sym({false, start, g_.symbol_id(start)}, 0);
  }

  // Text a terminal token would emit (empty = silent, emits nothing).
  std::string terminal_text(const std::string &name) {
    return terminal_value(name, Role::Generic);
  }

  // Shortest derivation depth of a rule, in the units --depth counts.
  int min_height(const std::string &name) const {
    auto it = min_h_.find(name);
    return it == min_h_.end() ? 0 : it->second;
  }

  // Record which grammar alternative each derivation step takes, into a map the
  // caller owns and merges. Without it a run's reach into the grammar can only
  // be guessed at from the SQL it happens to produce.
  void count_coverage(Coverage *into, GenStats *stats) {
    cov_ = into;
    stats_ = stats;
  }

  void probe_rule(const std::string &head) { probe_id_ = g_.symbol_id(head); }

  // Rules no derivation can complete: pruning took the last production of a rule,
  // or of everything a rule could reach. Harmless where the parent has an empty
  // alternative, a silently lost statement class where it does not, so --info
  // names them rather than leaving it to be noticed in the output.
  std::vector<std::string> unreachable_rules() const {
    std::vector<std::string> out;
    for (const std::string &h : g_.heads()) {
      if (is_leaf(h)) continue;
      auto it = min_h_.find(h);
      if (it != min_h_.end() && it->second >= kInf) out.push_back(h);
    }
    return out;
  }

  // Print every production that holds an identifier leaf, rendering keywords as
  // the SQL they emit and the leaf as <ID>. Lets the identifier-role table be
  // checked against the whole grammar instead of a guessed subset.
  void audit_names() {
    for (const std::string &h : g_.heads())
      for (const Production &p : g_.productions(h)) {
        bool has_leaf = false;
        for (const Sym &s : p)
          if (!s.char_lit && is_leaf(s.text)) has_leaf = true;
        if (!has_leaf) continue;
        std::cout << h << " :";
        for (const Sym &s : p) {
          if (s.char_lit) { std::cout << " '" << s.text << "'"; continue; }
          if (is_leaf(s.text)) { std::cout << " <ID>"; continue; }
          std::string v = terminal_value(s.text, Role::Generic);
          std::cout << ' ' << (v.empty() ? s.text : v);
        }
        std::cout << '\n';
      }
  }

 private:
  void trace_sym(const Sym &s, int ind) {
    std::string pad(ind * 2, ' ');
    if (ind > 40) { std::cerr << pad << "...\n"; return; }
    if (s.char_lit) { std::cerr << pad << "'" << s.text << "'\n"; return; }
    if (is_leaf(s.text)) { std::cerr << pad << s.text << " [id leaf]\n"; return; }
    if (!g_.is_nonterminal(s.text)) {
      std::string v = terminal_value(s.text, Role::Generic);
      std::cerr << pad << s.text << " -> \"" << v << "\""
                << (v.empty() ? "   <<< SILENT TERMINAL" : "") << "\n";
      return;
    }
    const std::vector<Production> &prods = g_.productions(s.text);
    int best = kInf, bi = 0;
    for (int i = 0; i < (int)prods.size(); ++i) {
      int h = prod_height(prods[i]);
      if (h < best) { best = h; bi = i; }
    }
    std::cerr << pad << s.text << " (minH=" << min_h_.at(s.text) << ", prod#"
              << bi << (prods[bi].empty() ? ", EMPTY" : "") << ")\n";
    for (const Sym &c : prods[bi]) trace_sym(c, ind + 1);
  }
  // Nonterminals that switch the identifier role for their subtree.
  void build_roles() {
    for (const char *n :
         {"table_ident", "table_name", "table_ident_nodb",
          "table_ident_opt_wild", "table_alias_ref", "table_alias_ref_list",
          "table_list", "table_name_with_opt_use_partition"})
      role_of_[n] = Role::Table;
    for (const char *n :
         {"field_ident", "simple_ident", "simple_ident_nospvar",
          "simple_ident_q", "field_list", "field_spec", "key_part",
          "column_list", "column_default_expr"})
      role_of_[n] = Role::Column;
    // The rest of the identifier slots --names reports, grouped by what the
    // name refers to. A keyword inside the production still wins over these.
    for (const char *n : {"table_column_list", "optionally_qualified_column_ident",
                          "on_update_cols", "ref_list", "view_list", "using_list"})
      role_of_[n] = Role::Column;
    // The identifier in "t1.*" is the table, not a column.
    for (const char *n : {"select_sublist_qualified_asterisk", "table_wild"})
      role_of_[n] = Role::Table;
    for (const char *n : {"variable_aux", "simple_target_specification",
                          "ident_directly_assignable"})
      role_of_[n] = Role::Var;
    // A bare name in SET, with or without GLOBAL/SESSION/LOCAL/STATEMENT in
    // front, has to be a system variable the server knows.
    for (const char *n : {"option_value_no_option_type", "set_stmt_option",
                          "option_value_following_option_type"})
      role_of_[n] = Role::SysVar;
    for (const char *n : {"sp_proc_stmt_open", "open_for",
                          "fetch_statement_source", "sp_fetch_list"})
      role_of_[n] = Role::Cursor;
    for (const char *n : {"sp_param_anchored", "sf_return_type"})
      role_of_[n] = Role::Table;
    role_of_["function_call_generic"] = Role::Func;
    for (const char *n : {"use_partition", "opt_use_partition",
                          "alt_part_name_list", "alt_part_name_item"}) {
      role_of_[n] = Role::Partition;
      sticky_.insert(n);
    }
    role_of_["sp_name"] = Role::Proc;
    role_of_["user_name"] = Role::User;
    role_of_["select_alias"] = Role::Alias;
    role_of_["ident_table_alias"] = Role::Alias;
    for (const char *n : {"update_elem", "ident_eq_value"}) {
      role_of_[n] = Role::ColumnSeq;
      sticky_.insert(n);
    }
    role_of_["sql_statement_name"] = Role::Stmt;
    for (const char *n : {"ident_sysvar_name", "keyword_sysvar_name"})
      role_of_[n] = Role::SysVar;
    role_of_["opt_format_json"] = Role::ExplainFormat;
  }

  // Identifier leaves: emit one generic name for the active role, no descent.
  void build_leaves() {
    for (const char *n : {"ident", "ident_cli", "ident_sys", "IDENT_sys",
                          "ident_or_text", "ident_directly_assignable",
                          "label_ident", "sp_name"})
      leaves_.insert(n);
  }

  bool is_leaf(const std::string &n) const { return leaves_.count(n) != 0; }

  int min_height_sym(const Sym &s) const {
    if (s.char_lit) return 0;
    if (is_leaf(s.text)) return 0;
    auto it = min_h_.find(s.text);
    if (it != min_h_.end()) return it->second;  // nonterminal
    return 0;                                     // named terminal
  }

  // A production of exactly one nonterminal emits no text of its own, so it adds
  // no height. Counting it did, and the operator-precedence cascade and the
  // query_expression chain are almost entirely made of them: select measured
  // height 20 against a depth budget of 13, which put SELECT - the
  // highest-weighted statement - permanently out of reach. Heights and the depth
  // the walk actually spends have to agree, so both discount unit productions.
  // Identifier leaves keep their cost so a name-emitting rule stays above empty.
  bool unit_production(const Production &p) const {
    return p.size() == 1 && !p[0].char_lit && g_.is_nonterminal(p[0].text) &&
           !is_leaf(p[0].text);
  }

  int prod_height(const Production &p) const {
    if (p.empty()) return 0;
    int m = 0;
    for (const Sym &s : p) m = std::max(m, min_height_sym(s));
    if (m >= kInf) return kInf;
    return unit_production(p) ? m : m + 1;
  }

  void compute_min_height() {
    for (const std::string &h : g_.heads())
      if (!is_leaf(h)) min_h_[h] = kInf;
    bool changed = true;
    while (changed) {
      changed = false;
      for (const std::string &h : g_.heads()) {
        if (is_leaf(h)) continue;
        int best = kInf;
        for (const Production &p : g_.productions(h))
          best = std::min(best, prod_height(p));
        if (best < min_h_[h]) { min_h_[h] = best; changed = true; }
      }
    }
  }

  // Prefix and pool size per Role, same order as the enum. Tables and columns
  // get four names so a multi-table statement can name two different ones.
  struct NameKind { const char *prefix; int count; };
  static constexpr NameKind kNameKinds[] = {
      {"i", 2},    // Generic - no more specific slot known
      {"t", 4},    // Table
      {"c", 4},    // Column
      {"sp", 2},   // Proc - stored procedure
      {"f", 2},    // Func
      {"v", 2},    // View
      {"tr", 2},   // Trigger
      {"ev", 2},   // Event
      {"sq", 2},   // Sequence
      {"idx", 2},  // Index
      {"cn", 2},   // Constraint
      {"p", 2},    // Partition
      {"s", 2},    // Savepoint
      {"u", 2},    // User
      {"r", 2},    // RoleName
      {"var", 2},  // Var
      {"d", 2},    // Db
      {"srv", 2},  // Server
      {"cur", 2},  // Cursor
      {"a", 8},    // Alias
      {"st", 2},   // Stmt - prepared statement name
      {"c", 4},    // ColumnSeq - column in a position that must not repeat
      {"", 0},     // SysVar - fixed vocabulary, see id_for
      {"", 0},     // ExplainFormat - fixed vocabulary, see id_for
  };

  // Roles handed out in order within one statement rather than at random, so a
  // list of them (aliases, assignment targets) does not name the same thing
  // twice - which the server rejects.
  static bool sequential(Role r) {
    return r == Role::Alias || r == Role::ColumnSeq;
  }

  std::string id_for(Role r) {
    // Two slots take a name from a fixed vocabulary: a system variable and an
    // EXPLAIN format both have to be one the server knows.
    if (r == Role::SysVar) {
      static const char *v[] = {"sort_buffer_size",   "join_buffer_size",
                                "tmp_table_size",     "max_heap_table_size",
                                "read_buffer_size",   "max_sort_length",
                                "group_concat_max_len", "long_query_time"};
      return v[rng_() % 8];
    }
    if (r == Role::ExplainFormat) {
      static const char *v[] = {"TRADITIONAL", "JSON"};
      return v[rng_() % 2];
    }
    const NameKind &k = kNameKinds[(int)r];
    int n = sequential(r) ? (int)(seq_[(int)r]++ % k.count)
                          : (int)(rng_() % k.count);
    return std::string(k.prefix) + std::to_string(1 + n);
  }

  // Random string literal: 1-100 printable chars, SQL-escaped and quoted.
  std::string rand_text() {
    int len = 1 + (int)(rng_() % 100);
    std::string s = "'";
    for (int i = 0; i < len; ++i) {
      char c = (char)(0x20 + rng_() % (0x7f - 0x20));  // printable ASCII
      if (c == '\'' || c == '\\') s += c;              // double it to escape
      s += c;
    }
    s += "'";
    return s;
  }

  std::string terminal_value(const std::string &name, Role r) {
    if (name == "IDENT" || name == "IDENT_QUOTED") return id_for(r);
    if (name == "TEXT_STRING") return rand_text();
    if (name == "NCHAR_STRING") return "N" + rand_text();
    if (name == "NUM" || name == "LONG_NUM" || name == "ULONGLONG_NUM")
      return std::to_string(rng_() % 301);  // 0-300 (NUM is unsigned; sign is
                                            // added by the grammar's unary minus)
    if (name == "DECIMAL_NUM" || name == "FLOAT_NUM")
      return std::to_string(rng_() % 301) + "." +
             std::to_string(rng_() % 100);
    // Same magnitude as NUM above. The grammar reuses these in count positions
    // (PARTITIONS, LIMIT), where a wide hex literal asks for tens of thousands
    // of partitions and the statement takes minutes.
    if (name == "HEX_NUM") return "0x" + hex_digits(1 + rng_() % 2);
    if (name == "BIN_NUM") {
      std::string b = "0b";
      int n = 1 + (int)(rng_() % 8);
      for (int i = 0; i < n; ++i) b += (rng_() & 1) ? '1' : '0';
      return b;
    }
    if (name == "HEX_STRING") return "X'" + hex_digits(2 * (1 + rng_() % 8)) + "'";
    if (name == "LEX_HOSTNAME") return "'localhost'";
    if (name == "UNDERSCORE_CHARSET") {
      static const char *cs[] = {"_utf8mb4", "_latin1", "_utf8", "_binary"};
      return cs[rng_() % 4];
    }
    if (name == "PARAM_MARKER") return "?";
    // Operator tokens the lexer synthesizes; lex.h has no text for them.
    if (name == "SET_VAR") return ":=";
    // NOT2_SYM has no default-sql_mode spelling; the productions offering it are
    // pruned, and '!' is what the lexer accepts for the high-precedence form.
    if (name == "NOT2_SYM") return "!";
    if (name == "JSON_SEPARATOR_SYM") return "->";
    // Tokens the lexer builds by collapsing two keywords in a lookahead
    // (sql_lex.cc). lex.h has no entry, so without these the pair is dropped and
    // the statement comes out truncated - "PARTITION p1 THAN MAXVALUE".
    if (name == "VALUES_LESS_SYM") return "VALUES LESS";
    if (name == "VALUES_IN_SYM") return "VALUES IN";
    if (name == "WITH_SYSTEM_SYM") return "WITH SYSTEM";
    if (name == "WITH_ROLLUP_SYM") return "WITH ROLLUP";
    if (name == "WITH_CUBE_SYM") return "WITH CUBE";
    if (name == "FOR_SYSTEM_TIME_SYM") return "FOR SYSTEM_TIME";
    if (name == "MYSQL_CONCAT_SYM") return "||";
    if (name == "DOT_DOT_SYM") return "..";
    if (name == "JSON_UNQUOTED_SEPARATOR_SYM") return "->>";
    // Internal '(' variants the lexer emits in lookahead contexts; paired with
    // a literal ')' in the grammar, so they must render as '(' to stay balanced.
    if (name == "LEFT_PAREN_ALT" || name == "LEFT_PAREN_WITH" ||
        name == "LEFT_PAREN_LIKE")
      return "(";
    auto it = kw_.find(name);
    if (it != kw_.end()) return it->second;
    return "";  // internal or unknown token: no text
  }

  std::string hex_digits(int n) {
    static const char *h = "0123456789ABCDEF";
    std::string s;
    for (int i = 0; i < n; ++i) s += h[rng_() % 16];
    return s;
  }

  // chain counts how many times this same nonterminal has recursed directly into
  // itself on the way here - the difference between a long "a OR b OR c" chain
  // and the structural nesting of an expression inside a subquery. free counts
  // the unit productions taken in a row on the way here; both describe this path
  // only, so a sibling subtree cannot spend either budget.
  void expand(const Sym &s, int depth, Role role, int chain, int free = 0,
              int grants = -1) {
    if (grants < 0) grants = grants_start_;
    if (++steps_ > kMaxSteps || tokens_.size() > kMaxTokens) {
      truncated_ = true;
      return;
    }
    if (s.char_lit) { push(s.text); return; }
    if (s.id < 0) return;  // symbol the grammar never mentions
    SymInfo &in = sym_[(size_t)s.id];
    if (in.leaf) {
      // A keyword names the one object that follows it, so it types the next
      // identifier emitted and then stops applying: in CREATE TRIGGER tr1 ..
      // ON t1 the keyword names the trigger, and the table keeps its own role.
      Role r = role_of(in, role);
      if (pending_ != Role::Generic) { r = pending_; pending_ = Role::Generic; }
      push(id_for(r));
      return;
    }
    if (!in.prods) {                      // a terminal: emits its own text
      if (in.varies) {
        const std::string v = terminal_value(s.text, role);
        if (!v.empty()) push(v);
      } else if (!in.text.empty()) {
        push(in.text);
      }
      return;
    }
    const std::vector<Production> &prods = *in.prods;
    if (prods.empty()) return;
    const Role child_role = role_of(in, role);
    const Role saved_sticky = sticky_role_;
    if (in.sticky) sticky_role_ = in.role;
    bool granted = false;
    const Production &p = prods[choose(in, s.id, prods, depth, chain, grants,
                                       &granted)];
    // Unit productions pass through free, matching prod_height(). A grammar can
    // hold a cycle of them (a: b; b: a), so the run of consecutive free steps is
    // capped; past the cap depth is charged again and the walk terminates.
    const int child_grants = granted ? grants - 1 : grants;
    const bool free_step = unit_production(p) && free < kMaxFreeChain;
    const int child_depth = free_step ? depth : depth - 1;
    const int child_free = free_step ? free + 1 : 0;
    for (const Sym &c : p) {
      if (!c.char_lit) {
        const SymInfo &ci = sym_[(size_t)c.id];
        if (ci.has_kw_role) pending_ = ci.kw_role;
      }
      expand(c, child_depth, child_role,
             (!c.char_lit && c.id == s.id) ? chain + 1 : 0, child_free,
             child_grants);
    }
    sticky_role_ = saved_sticky;
  }

  static bool self_recursive(const std::string &head, const Production &p) {
    for (const Sym &s : p)
      if (!s.char_lit && s.text == head) return true;
    return false;
  }

  // One entry per grammar symbol, indexed by Sym::id. Filled in build_symbols()
  // before the walk starts, so nothing in the hot path hashes a string.
  struct SymInfo {
    const std::vector<Production> *prods = nullptr;  // null for a terminal
    bool leaf = false;          // identifier leaf: emits a generated name
    bool sticky = false;        // role covers the whole subtree
    bool has_role = false;
    bool has_kw_role = false;
    bool varies = false;        // terminal whose text depends on the role
    Role role = Role::Generic;
    Role kw_role = Role::Generic;
    std::string text;           // cached terminal text, when it does not vary
    std::vector<int> weight;    // explicit relative weight, 1 unless set
    std::vector<long> used;     // times this alternative has been taken
    std::vector<int> height;    // prod_height of each alternative
    std::vector<char> chains;   // alternative holds its own head
  };

  // Returns the index of the chosen alternative, so coverage is recorded in one
  // place rather than at each exit.
  int choose(SymInfo &st, int id, const std::vector<Production> &prods,
             int depth, int chain, int grants, bool *granted) {
    int picked = pick(st, id, prods, depth, chain, grants, granted);
    if (cov_) {
      std::vector<long> &c = (*cov_)[g_.symbol_name(id)];
      if (c.size() != prods.size()) c.resize(prods.size(), 0);
      ++c[picked];
    }
    return picked;
  }

  // Everything about one rule that the walk needs, worked out the first time the
  // rule is reached. height and chains were being recomputed for every alternative
  // at every choice, and prod_height walks a production doing a hash lookup per
  // symbol, so a rule with 30 alternatives cost 30 of those walks per entry.
  // Weight an alternative by how little it has been used, so the run spreads over
  // a rule's alternatives instead of re-picking whichever the RNG favours. The
  // least-used gets (span + 1) times the pull of the most-used, where span is the
  // gap between them, and any explicit rule weight multiplies through. Uniform
  // random choice looks fair per call but is not fair over a run: the alternatives
  // that only fit at generous depth get offered far less often than the cheap
  // ones, so their share compounds down to nothing.
  long balance_weight(const SymInfo &st, int i, long span) const {
    return (long)st.weight[i] * (span - st.used[i] + 1);
  }

  int pick(SymInfo &st, int id, const std::vector<Production> &prods,
           int depth, int chain, int grants, bool *granted) {
    if (stats_) ++stats_->choices;
    // A rule reached deep in the tree has almost no depth left, so only its
    // cheapest alternatives fit and the interesting ones are never offered:
    // sum_expr costs 1 for COUNT(*) and 2 for AVG(expr), and by the time the
    // walk reaches it the budget is 1, which is why COUNT(*) turned up 7578
    // times per 20000 statements and AVG once. A statement carries a small pool
    // of extra depth that a choice can borrow to take an alternative that
    // overshoots, capped per choice so one greedy pick cannot drain it.
    std::vector<int> &feasible = scratch_;
    feasible.clear();
    int best = kInf, best_i = 0;
    for (int i = 0; i < (int)prods.size(); ++i) {
      const int h = st.height[i];
      const bool chains = st.chains[i] != 0;
      // Once a rule has chained into itself max_chain_ times, stop offering the
      // alternatives that chain again. Left to itself the walk spends the whole
      // depth budget on one boolean chain or one value list, and the constructs
      // that need the depth - a subquery, a UNION, a CTE - stay out of reach.
      if (chains && chain >= max_chain_) continue;
      // A rule that does not chain into itself may overshoot the remaining depth
      // by grant_. Without it the bottom of every expression is reached with a
      // budget of exactly 1, because the precedence cascade is about eleven rules
      // deep and nesting takes the depth on the way down: sum_expr was entered
      // 7912 times per 5000 statements and every single time at depth 1, where
      // COUNT(*) is the one alternative of its 22 that costs only 1. The grant is
      // a constant, not an allowance that earlier choices can spend, so it is
      // still there at the leaf. It cannot run away either: a chain is charged
      // full depth, every other step still takes one level off its children, so
      // the walk runs out at depth -grant_ whatever it picks.
      if (h <= depth) feasible.push_back(i);
      if (h < best) { best = h; best_i = i; }
    }
    // A rule with one affordable alternative is not making a choice, and that is
    // where every expression ends up: the descent spends the budget, so the leaf
    // grammar is reached with 1 left and takes the alternative that costs 1.
    // sum_expr was entered 3188 times per 5000 statements with one of its 22
    // affordable, so COUNT(*) was the only aggregate it could build. Here, and only
    // here, the budget is widened. Grants are counted per path and each is spent
    // for good, so a widened subtree cannot widen again and the walk still ends:
    // depth keeps falling by one at every step that is not a pass-through.
    // A pass-through is skipped: widening a rule whose one affordable alternative
    // is a single nonterminal buys nothing, and spending a grant there left none
    // for the rule at the bottom that could have used it. The precedence cascade is
    // eleven such rules deep, so this is the difference between the grant arriving
    // at sum_expr and being gone long before.
    if (feasible.size() == 1 && grants > 0 && prods.size() > 1 &&
        !unit_production(prods[feasible[0]])) {
      wider_.clear();
      for (int i = 0; i < (int)prods.size(); ++i) {
        if (st.chains[i] && chain >= max_chain_) continue;
        if (st.height[i] <= depth + kGrantDepth) wider_.push_back(i);
      }
      if (wider_.size() > 1) {
        feasible.swap(wider_);
        *granted = true;
      }
    }
    if (feasible.empty() && best == kInf) {  // every alternative chains
      for (int i = 0; i < (int)prods.size(); ++i)
        if (st.height[i] < best) { best = st.height[i]; best_i = i; }
    }
    if (feasible.empty()) {
      // Budget exhausted with nothing to borrow: take a shortest exit, at random
      // when several tie. Always taking the first collapses every deep subtree
      // to one shape.
      if (stats_) ++stats_->exits;
      wider_.clear();
      for (int i = 0; i < (int)prods.size(); ++i)
        if (st.height[i] == best) wider_.push_back(i);
      return wider_.size() > 1 ? wider_[rng_() % wider_.size()] : best_i;
    }
    if (stats_ && id == probe_id_) {
      ++stats_->probe_hits;
      stats_->probe_alts = (long)prods.size();
      ++stats_->probe_depth[depth];
      ++stats_->probe_afford[(int)feasible.size()];
    }
    long span = 0;
    for (int i : feasible) span = std::max(span, st.used[i]);
    // How often a rule chains into itself has to be set, not left to how many of
    // its alternatives happen to chain. expr offers seven chaining alternatives
    // against one exit into the next precedence level, so an even choice chains
    // seven times in eight; over the eleven levels of the cascade that spends the
    // whole depth budget on operator nesting before any leaf is reached, and the
    // leaf grammar is then derived with a budget of 1 - which is why sum_expr was
    // entered 7912 times per 5000 statements and every single time at depth 1,
    // where COUNT(*) is the one of its 22 alternatives that fits. Scaling the two
    // groups to a set ratio leaves depth in hand at the bottom.
    long w_chain = 0, w_exit = 0;
    for (int i : feasible)
      (st.chains[i] ? w_chain : w_exit) += balance_weight(st, i, span);
    long mul_chain = 1, mul_exit = 1;
    if (w_chain > 0 && w_exit > 0) {
      mul_chain = chain_share_ * w_exit;
      mul_exit = (100 - chain_share_) * w_chain;
    }
    auto weight = [&](int i) {
      return balance_weight(st, i, span) * (st.chains[i] ? mul_chain : mul_exit);
    };
    long total = 0;
    for (int i : feasible) total += weight(i);
    int idx = feasible[0];
    if (total > 0) {
      long r = (long)(rng_() % (uint64_t)total);
      for (int i : feasible) {
        r -= weight(i);
        if (r < 0) { idx = i; break; }
      }
    }
    // Balance counts only the alternatives that emit something. A unit production
    // is a pass-through - it routes to another rule and writes no SQL of its own -
    // so a pick of one is not an output occurrence, and counting it holds back
    // everything behind it: primary_base_expr routes to
    // column_default_non_parenthesized_expr, which is the only way to any
    // aggregate, and once that route had been taken often enough balance read it as
    // over-used and stopped taking it. Counting emitting alternatives only, against
    // counting every pick, is the difference between 37% of statements carrying a
    // subquery and 11%, and between 192 window functions per 1000 and 1.
    if (!unit_production(prods[idx])) ++st.used[idx];
    return idx;
  }

  // Per-rule state, created on first use: the explicit weights (only verb_clause
  // has any) plus everything else the walk used to look up by name.
  void build_symbols() {
    sym_.assign(g_.symbol_count(), SymInfo{});
    for (size_t id = 0; id < sym_.size(); ++id) {
      SymInfo &in = sym_[id];
      const std::string &name = g_.symbol_name((int)id);
      in.prods = g_.productions_by_id((int)id);
      in.leaf = is_leaf(name);
      in.sticky = sticky_.count(name) != 0;
      auto r = role_of_.find(name);
      if (r != role_of_.end()) { in.has_role = true; in.role = r->second; }
      auto k = kKeywordRoles.find(name);
      if (k != kKeywordRoles.end()) { in.has_kw_role = true; in.kw_role = k->second; }
      // A terminal's text is worked out once here unless it is drawn fresh each
      // time - a random literal, or a name that depends on the role it sits in.
      static const std::unordered_set<std::string> kFresh = {
          "IDENT", "IDENT_QUOTED", "TEXT_STRING", "NCHAR_STRING", "NUM",
          "LONG_NUM", "ULONGLONG_NUM", "DECIMAL_NUM", "FLOAT_NUM", "HEX_NUM",
          "BIN_NUM", "HEX_STRING", "UNDERSCORE_CHARSET"};
      in.varies = kFresh.count(name) != 0;
      if (!in.prods && !in.leaf && !in.varies)
        in.text = terminal_value(name, Role::Generic);
      if (!in.prods || in.prods->empty()) continue;
      const std::vector<Production> &prods = *in.prods;
      in.weight.assign(prods.size(), kDefaultVerbWeight);
      in.used.assign(prods.size(), 0);
      in.height.reserve(prods.size());
      in.chains.reserve(prods.size());
      for (const Production &pr : prods) {
        in.height.push_back(prod_height(pr));
        in.chains.push_back(self_recursive(name, pr) ? 1 : 0);
      }
      if (name == "verb_clause")
        for (size_t i = 0; i < prods.size(); ++i) {
          if (prods[i].size() != 1 || prods[i][0].char_lit) continue;
          auto w = kVerbWeights.find(prods[i][0].text);
          if (w != kVerbWeights.end()) in.weight[i] = w->second;
        }
    }
  }

  // Inside a sticky subtree (a partition-name list) the ancestor's type wins: the
  // list rule is shared with JOIN .. USING, which is a column list.
  Role role_of(const SymInfo &in, Role inherited) const {
    if (sticky_role_ != Role::Generic) return sticky_role_;
    return in.has_role ? in.role : inherited;
  }

  void push(const std::string &t) {
    if (!t.empty()) tokens_.push_back(t);
  }

  // Join tokens with light spacing so the SQL is readable and parses.
  std::string join() const {
    // '.' is deliberately spaced: gluing it to a preceding keyword (DESC.t1)
    // mis-lexes, while spaced qualified names (a . b) parse fine.
    static const std::unordered_set<std::string> no_space_before = {
        ",", ";", ")", "(", "@"};
    static const std::unordered_set<std::string> no_space_after = {"(", "@"};
    std::string out;
    std::string prev;
    for (size_t i = 0; i < tokens_.size(); ++i) {
      const std::string &t = tokens_[i];
      if (i != 0) {
        bool skip = no_space_before.count(t) || no_space_after.count(prev);
        if (!skip) out += ' ';
      }
      out += t;
      prev = t;
    }
    return out;
  }

  static constexpr int kMaxSteps = 200000;
  static constexpr size_t kMaxTokens = 4000;
  // Longest run of consecutive free (unit-production) steps. The real chains run
  // to about twenty; this only has to break a cycle.
  static constexpr int kMaxFreeChain = 64;
  // Depth a widened choice may reach past what is left. Three covers an aggregate
  // or a window function over an expression.
  static constexpr int kGrantDepth = 3;
  // Most depth one choice may borrow. Two covers the alternatives that were being
  // starved (an aggregate over an expression, a two-argument window function);
  // more lets a single choice bring in a whole nested query.

  const Grammar &g_;
  const std::unordered_map<std::string, std::string> &kw_;
  Xoshiro256pp rng_;
  int max_chain_ = 3;
  int grants_start_ = 2;   // widenings one path may spend
  long chain_share_ = 30;  // percent of picks a rule chains into itself, where
                           // it has both chaining and non-chaining alternatives
  std::unordered_map<std::string, Role> role_of_;
  std::unordered_set<std::string> leaves_;
  std::unordered_map<std::string, int> min_h_;
  std::vector<SymInfo> sym_;
  std::vector<std::string> tokens_;
  std::unordered_set<std::string> sticky_;  // rules whose role covers the subtree
  Role sticky_role_ = Role::Generic;
  Role pending_ = Role::Generic;  // keyword-set role awaiting the next identifier
  unsigned seq_[32] = {};         // per-statement counters for sequential roles
  long steps_ = 0;
  bool truncated_ = false;
  std::vector<int> scratch_, wider_;  // reused per choice, not reallocated
  Coverage *cov_ = nullptr;       // set by count_coverage(); off costs one branch
  GenStats *stats_ = nullptr;     // set by count_coverage(); off costs one branch
  int probe_id_ = -1;             // --probe RULE, -1 when off
};

// ---- coverage report -----------------------------------------------------

// A rule whose every alternative is one bare terminal is a keyword pool - the
// grammar's lists of keywords usable as an identifier or a label. They hold
// nearly a thousand alternatives between them, all interchangeable, so counting
// them buries the structural gaps that are worth acting on.
bool keyword_pool(const Grammar &g, const std::vector<Production> &prods) {
  if (prods.size() < 8) return false;
  for (const Production &p : prods) {
    if (p.size() != 1 || p[0].char_lit) return false;
    if (g.is_nonterminal(p[0].text)) return false;
  }
  return true;
}

// The nonterminals a derivation from start can reach. Only these belong in the
// coverage denominator: counting the whole grammar against a narrow --start
// reports a fraction of a percent for a run that covered everything it could.
std::unordered_set<std::string> reachable_from(const Grammar &g,
                                               const std::string &start) {
  std::unordered_set<std::string> seen;
  std::vector<std::string> todo{start};
  seen.insert(start);
  while (!todo.empty()) {
    std::string h = todo.back();
    todo.pop_back();
    if (!g.is_nonterminal(h)) continue;
    for (const Production &p : g.productions(h))
      for (const Sym &s : p)
        if (!s.char_lit && g.is_nonterminal(s.text) && seen.insert(s.text).second)
          todo.push_back(s.text);
  }
  return seen;
}

// What fraction of the grammar a run actually reached. Counts alternatives, not
// rules: a rule entered once still leaves most of its alternatives untried, and
// those are the parts of the grammar the run is not testing. Reported twice -
// over everything reachable from the start symbol, and over the structural rules
// only, with the keyword pools set aside. Rules never entered are listed
// separately; that list also holds everything pruned by default, so it shrinks
// under --allow-unsafe.
void report_coverage(const Grammar &g, const Coverage &cov, const GenStats &st,
                     const std::string &start, long limit) {
  size_t total = 0, hit = 0, s_total = 0, s_hit = 0, rules_entered = 0;
  std::vector<std::pair<size_t, std::string>> partial;  // unhit count, head
  std::vector<std::string> untouched;
  const std::unordered_set<std::string> live = reachable_from(g, start);
  for (const std::string &h : g.heads()) {
    if (!live.count(h)) continue;
    const std::vector<Production> &prods = g.productions(h);
    bool pool = keyword_pool(g, prods);
    total += prods.size();
    if (!pool) s_total += prods.size();
    auto it = cov.find(h);
    if (it == cov.end()) { untouched.push_back(h); continue; }
    ++rules_entered;
    size_t unhit = 0;
    for (size_t i = 0; i < prods.size(); ++i) {
      if (i < it->second.size() && it->second[i] > 0) {
        ++hit;
        if (!pool) ++s_hit;
      } else {
        ++unhit;
      }
    }
    if (unhit && !pool) partial.push_back({unhit, h});
  }
  std::sort(partial.rbegin(), partial.rend());
  auto pct = [](size_t a, size_t b) { return b ? 100.0 * (double)a / (double)b : 0.0; };
  std::cerr << "coverage from " << start << ": " << hit << "/" << total
            << " productions (" << pct(hit, total) << "%), structural "
            << s_hit << "/" << s_total << " (" << pct(s_hit, s_total)
            << "%, keyword pools excluded), " << rules_entered << "/"
            << live.size() << " rules entered\n";
  // A large exits share says the depth budget is choosing the SQL: at those
  // choices nothing else fitted, so the weighting never got a say.
  if (st.choices)
    std::cerr << "choices: " << st.choices << ", " << st.exits << " forced to a"
              << " shortest exit (" << pct((size_t)st.exits, (size_t)st.choices)
              << "%), " << st.lends << " borrowed depth ("
              << pct((size_t)st.lends, (size_t)st.choices) << "%)\n";
  if (st.probe_hits) {
    std::cerr << "probe: entered " << st.probe_hits << " times, "
              << st.probe_alts << " alternatives\n  depth at entry:";
    for (const auto &kv : st.probe_depth)
      std::cerr << " " << kv.first << ":" << kv.second;
    std::cerr << "\n  alternatives affordable:";
    for (const auto &kv : st.probe_afford)
      std::cerr << " " << kv.first << ":" << kv.second;
    std::cerr << "\n";
  }
  std::cerr << "\nrules never entered (" << untouched.size()
            << "; includes everything pruned by default):\n";
  for (const std::string &h : untouched) std::cerr << "  " << h << "\n";
  std::cerr << "\nstructural rules with untried alternatives, most first"
            << (limit > 0 ? " (--coverage N caps the list)" : "") << ":\n";
  long shown = 0;
  for (const auto &pr : partial) {
    if (limit > 0 && ++shown > limit) {
      std::cerr << "  ... " << (partial.size() - (size_t)limit) << " more\n";
      break;
    }
    const std::vector<Production> &prods = g.productions(pr.second);
    const std::vector<long> &c = cov.at(pr.second);
    std::cerr << "  " << pr.second << " (" << pr.first << "/" << prods.size()
              << " untried)\n";
    for (size_t i = 0; i < prods.size(); ++i)
      if (!(i < c.size() && c[i] > 0))
        std::cerr << "      | " << production_text(prods[i]) << "\n";
  }
}

// ---- rules slice + CLI ---------------------------------------------------

std::string rules_section(const std::string &grammar) {
  std::istringstream in(grammar);
  std::string line;
  std::string out;
  bool in_rules = false;
  while (std::getline(in, line)) {
    if (!in_rules) {
      if (trim(line) == "%%") in_rules = true;
      continue;
    }
    out += line;
    out += '\n';
  }
  return out;
}

std::string dir_of(const std::string &path) {
  size_t p = path.find_last_of('/');
  return p == std::string::npos ? "." : path.substr(0, p);
}

// ---- PREPARE validation --------------------------------------------------

// Valid SQL that cannot be prepared (server returns ER_UNSUPPORTED_PS 1295).
// Skip PREPARE for these so a valid query is not dropped, and a PREPARE-wrapper
// quirk cannot mis-flag it as a parse error.
const std::string_view kSkipPrepare[] = {
    "USE ", "BEGIN", "START ", "COMMIT", "ROLLBACK", "RELEASE ", "SAVEPOINT ",
    "XA ", "LOCK ", "UNLOCK ", "HANDLER ", "LOAD ", "INSTALL ", "UNINSTALL ",
    "KILL ", "CHANGE ", "PURGE ", "RESET ", "HELP", "BACKUP ", "RESTORE ",
    "BINLOG ", "DELIMITER ", "CACHE ", "UNCACHE ", "GET DIAGNOSTICS"};

bool skip_prepare(const std::string &s) {
  size_t i = s.find_first_not_of(" \t\n");
  if (i == std::string::npos) return true;
  std::string head = s.substr(i, 20);
  for (char &c : head) if (c >= 'a' && c <= 'z') c -= 32;
  for (auto p : kSkipPrepare)
    if (head.compare(0, p.size(), p) == 0) return true;
  return false;
}

// Per-thread connection that PREPARE-tests statements. rc!=0 with errno 1064 is
// a parse error (drop, and log); other errors are semantic - syntax is fine, so
// keep. 2006/2013 mean the server went away: reconnect and keep the statement.
struct Validator {
  MYSQL *conn = nullptr;
  MYSQL_STMT *stmt = nullptr;
  std::string socket_path, db;
  std::FILE *fails = nullptr;
  std::mutex *fails_mu = nullptr;
  uint64_t total = 0, dropped = 0, lost = 0, other = 0, skipped = 0;

  bool reconnect() {
    if (stmt) { mysql_stmt_close(stmt); stmt = nullptr; }
    if (conn) { mysql_close(conn); conn = nullptr; }
    conn = mysql_init(nullptr);
    if (!conn) return false;
    if (!mysql_real_connect(conn, nullptr, "root", nullptr, db.c_str(), 0,
                            socket_path.c_str(), 0)) {
      std::fprintf(stderr, "[validator] connect failed: %s\n",
                   mysql_error(conn));
      mysql_close(conn); conn = nullptr;
      return false;
    }
    stmt = mysql_stmt_init(conn);
    return stmt != nullptr;
  }
  bool init(const std::string &sock, const std::string &database,
            std::FILE *log, std::mutex *mu) {
    socket_path = sock; db = database; fails = log; fails_mu = mu;
    return reconnect();
  }
  bool keep(const std::string &sql) {  // true: keep, false: drop (parse error)
    ++total;
    if (skip_prepare(sql)) { ++skipped; return true; }
    if (!stmt && !reconnect()) return true;
    if (mysql_stmt_prepare(stmt, sql.c_str(), (unsigned long)sql.size()) == 0)
      return true;
    unsigned err = mysql_stmt_errno(stmt);
    if (err == 1064) {
      ++dropped;
      if (fails) {
        std::lock_guard<std::mutex> lk(*fails_mu);
        std::fwrite(sql.data(), 1, sql.size(), fails);
        std::fwrite(";\n", 1, 2, fails);
      }
      return false;
    }
    if (err == 2006 || err == 2013) { ++lost; reconnect(); return true; }
    ++other;
    return true;
  }
  ~Validator() {
    if (stmt) mysql_stmt_close(stmt);
    if (conn) mysql_close(conn);
  }
};

void usage() {
  std::cerr <<
      "usage: revgen [options]\n"
      "  --yacc PATH     grammar file (default $HOME/mariadb-qa/yacc/13.1_sql_yacc.yy)\n"
      "  --lex PATH      lex.h keyword table (default: sibling of --yacc)\n"
      "  --queries N     statements to emit (default 100000)\n"
      "  --depth N       derivation depth budget (default 9)\n"
      "  --depth-max N   derive one statement in four at a random depth between\n"
      "                  --depth and this, for subqueries/UNION/CTE (default off)\n"
      "  --max-chain N   times a rule may chain into itself before its chaining\n"
      "                  alternatives are withheld (default 3)\n"
      "  --grants N      times one derivation may widen a choice the depth left with\n"
      "                  a single alternative, so the bottom of an expression can still\n"
      "                  reach the aggregates and window functions (default 2)\n"
      "  --chain-share N  percent of the time a rule chains into itself rather than\n"
      "                  moving on, where it can do either; lower leaves more depth\n"
      "                  for the bottom of an expression (default 30)\n"
      "  --schema-every N  interject the setup/reset block (t1-t4 plus lock and\n"
      "                  transaction release) every N statements (default 25, 0 off);\n"
      "                  the schema itself is rebuilt every fourth interval\n"
      "  --start SYM     start symbol (default verb_clause)\n"
      "  --seed N        base RNG seed (default: random)\n"
      "  --threads N     generation threads (default: nproc/4)\n"
      "  --output FILE   write output here (default: out.sql; '-' for stdout)\n"

      "  --validate-sql  PREPARE-test each statement; drop on parse error (1064)\n"
      "  --socket PATH   server socket for --validate-sql\n"
      "                  (default /test/CLAUDE1/socket.sock)\n"
      "  --db NAME       database for --validate-sql (default test)\n"
      "  --fails FILE    log dropped 1064 statements (default\n"
      "                  <output-dir>/revgen_failed_1064.sql)\n"
      "  --exclude A,B    also prune these nonterminals (internal entries are\n"
      "                  pruned by default: parse_vcol_expr, partition_entry, ...)\n"
      "  --allow-unsafe  keep admin/replication statements (CHANGE MASTER, SHUTDOWN,\n"
      "                  KILL, INSTALL, RESET, ...); they are skipped by default\n"
      "  --allow-locking keep LOCK TABLES, BACKUP LOCK and XA; worth having only\n"
      "                  when several client threads contend (implied by --allow-unsafe)\n"
      "  --info          print grammar stats and exit\n"
      "  --trace         print the min-derivation of --start and exit\n"
      "  --dump          print all productions of --start and exit\n"
      "  --audit         print silent terminals (emit nothing) and exit\n"
      "  --names         print every production holding an identifier leaf and exit\n"
      "  --parens        print every '(' X ')' where X can be empty, and exit\n"
      "  --probe RULE    with --coverage, report the depth left and the number of\n"
      "                  alternatives affordable each time RULE was entered\n"
      "  --coverage [N]  after generating, report which grammar alternatives the\n"
      "                  run reached; N caps the untried-alternatives list\n";
}

}  // namespace

int main(int argc, char **argv) {
  const char *home = std::getenv("HOME");
  std::string yacc = std::string(home ? home : "") + "/mariadb-qa/yacc/13.1_sql_yacc.yy";
  std::string lex, fails_path;
  std::string output = "out.sql";  // "-" writes to stdout
  long queries = 100000;
  int depth = 9;
  int max_chain = 3;
  int chain_share = 30;
  int grants = 2;
  std::string probe;
  int depth_max = 0;  // 0: every statement uses --depth
  long schema_every = 25;
  std::string start = "verb_clause";
  std::optional<uint64_t> seed;
  unsigned threads = 0;
  bool validate = false;
  std::string socket_path = "/test/CLAUDE1/socket.sock";
  std::string db = "test";
  bool info = false, trace = false, audit = false, dump = false, names = false,
       parens = false, coverage = false;
  long coverage_limit = 40;
  bool allow_unsafe = false;   // --allow-unsafe keeps the admin/replication statements
  bool allow_locking = false;  // --allow-locking keeps LOCK/BACKUP/XA (multi-threaded runs)
  // Internal / Oracle-mode-only entries the MARIADB-mode lexer never emits.
  std::unordered_set<std::string> exclude = {"parse_vcol_expr", "partition_entry",
                                             "keep_gcc_happy", "raise_stmt_oracle"};

  auto need = [&](int &i) -> std::string {
    if (i + 1 >= argc) { usage(); std::exit(2); }
    return argv[++i];
  };
  // Every numeric option goes through this. std::stol throws on a value that is
  // not a number or does not fit, and an uncaught throw ends the run with a
  // libc++abi message that says nothing about which option was wrong - a typo in
  // REVGEN_OPTIONS would look like a crash.
  auto num = [&](const std::string &flag, const std::string &v) -> long long {
    try {
      size_t used = 0;
      long long n = std::stoll(v, &used);
      if (used != v.size()) throw std::invalid_argument("trailing");
      return n;
    } catch (const std::exception &) {
      std::cerr << "revgen: " << flag << " needs a whole number, got '" << v
                << "'\n";
      std::exit(2);
    }
  };
  for (int i = 1; i < argc; ++i) {
    std::string a = argv[i];
    if (a == "--yacc") yacc = need(i);
    else if (a == "--lex") lex = need(i);
    else if (a == "--queries") queries = (long)num(a, need(i));
    else if (a == "--depth") depth = (int)std::clamp(num(a, need(i)), 0LL, 2000LL);
    else if (a == "--schema-every") schema_every = (long)num(a, need(i));
    else if (a == "--max-chain") max_chain = (int)std::clamp(num(a, need(i)), 1LL, 1000LL);
    else if (a == "--chain-share") chain_share = (int)std::clamp(num(a, need(i)), 1LL, 99LL);
    else if (a == "--grants") grants = (int)std::clamp(num(a, need(i)), 0LL, 100LL);
    else if (a == "--probe") probe = need(i);
    else if (a == "--depth-max") depth_max = (int)std::clamp(num(a, need(i)), 0LL, 2000LL);
    else if (a == "--start") start = need(i);
    // A seed is an opaque 64-bit value, so it is the one number read unsigned.
    else if (a == "--seed") {
      std::string v = need(i);
      try {
        size_t used = 0;
        seed = std::stoull(v, &used);
        if (used != v.size()) throw std::invalid_argument("trailing");
      } catch (const std::exception &) {
        std::cerr << "revgen: --seed needs a whole number, got '" << v << "'\n";
        return 2;
      }
    }
    else if (a == "--threads") threads = (unsigned)std::clamp(num(a, need(i)), 0LL, 4096LL);
    else if (a == "--output") output = need(i);
    else if (a == "--validate-sql") validate = true;
    else if (a == "--socket") socket_path = need(i);
    else if (a == "--db") db = need(i);
    else if (a == "--fails") fails_path = need(i);
    else if (a == "--exclude") {
      std::string v = need(i), tok;
      std::istringstream ss(v);
      while (std::getline(ss, tok, ',')) if (!tok.empty()) exclude.insert(tok);
    }
    else if (a == "--info") info = true;
    else if (a == "--trace") trace = true;
    else if (a == "--audit") audit = true;
    else if (a == "--names") names = true;
    else if (a == "--parens") parens = true;
    else if (a == "--coverage") {  // optional count argument
      coverage = true;
      if (i + 1 < argc && argv[i + 1][0] != '-') {
        ++i;
        coverage_limit = (long)std::clamp(num(a, argv[i]), 0LL, 100000LL);
      }
    }
    else if (a == "--dump") dump = true;
    else if (a == "--allow-unsafe") allow_unsafe = true;
    else if (a == "--allow-locking") allow_locking = true;
    else if (a == "-h" || a == "--help") { usage(); return 0; }
    else { std::cerr << "revgen: unknown arg " << a << "\n"; usage(); return 2; }
  }
  if (lex.empty()) {  // version-matched sibling: 13.1_sql_yacc.yy -> 13.1_lex.h; sql_yacc.yy -> lex.h
    std::filesystem::path yp(yacc);
    std::string base = yp.filename().string();
    auto pos = base.rfind("sql_yacc.yy");
    std::string prefix = (pos != std::string::npos) ? base.substr(0, pos) : "";
    lex = yp.parent_path().string() + "/" + prefix + "lex.h";
  }
  // --depth, --depth-max, --max-chain and --threads are clamped where they are
  // read; only these two are left to bound here.
  if (schema_every < 0) schema_every = 0;
  if (queries <= 0) { std::cerr << "revgen: --queries must be > 0\n"; return 2; }
  if (!std::filesystem::exists(yacc)) {
    std::cerr << "revgen: yacc grammar not found: " << yacc
              << "\n  set --yacc PATH (the shipped grammar is "
              << (home ? home : "$HOME") << "/mariadb-qa/yacc/13.1_sql_yacc.yy)\n";
    return 2;
  }

  // Admin and replication statements flood pquery runs and destabilize the
  // server (CHANGE MASTER alone makes thousands of named connections).
  // CURRENT_ROLE as a GRANT/REVOKE/DENY target aims the statement at the running
  // account. USE moves the session onto a generated database, and dropping that
  // one leaves the session with no default database at all. --allow-unsafe keeps
  // them, for standalone full-grammar use.
  if (!allow_unsafe)
    for (const char *n : {"change", "install", "uninstall", "kill", "shutdown",
                          "slave", "reset", "purge", "binlog_base64_event",
                          "current_role", "use"})
      exclude.insert(n);
  // These serialise the session rather than the server: XA leaves it in an XA
  // transaction, after which everything else returns ER_XAER_RMFAIL, and LOCK
  // TABLES and BACKUP LOCK do the same through a held lock. With one client
  // thread there is no second session for a lock to be interesting against, so
  // they are only cost. With several there is real contention to find bugs in,
  // which is what --allow-locking is for; --allow-unsafe implies it.
  if (!allow_unsafe && !allow_locking)
    for (const char *n : {"xa", "lock", "unlock", "backup"}) exclude.insert(n);

  Grammar g;
  g.parse(rules_section(preprocess_mariadb(read_file(yacc))));
  g.prune(exclude);
  g.drop_oracle_productions();
  if (!allow_unsafe) {
    // Single alternatives that turn a statement against the running session.
    // CURRENT_USER as a GRANT/REVOKE/DENY target rewrites the account the run
    // connects with; MAX_USER_CONNECTIONS takes a signed number, so a negative
    // one locks that account out of every new connection.
    g.prune_production("user_maybe_role", {"CURRENT_USER"});
    g.prune_production("resource_option", {"MAX_USER_CONNECTIONS_SYM"});
    g.prune_production("set_param", {"SESSION_SYM", "AUTHORIZATION_SYM"});
    // OLD_VALUE() is the cheapest exit from expr, so a depth-limited walk ends
    // every expression with it. The server only accepts it inside UPDATE, and
    // the walk has no statement context to keep it there.
    g.prune_production("expr", {"OLD_VALUE_SYM"});
    // COMMIT/ROLLBACK .. RELEASE closes the connection the run works over.
    g.prune_production("opt_release", {"RELEASE_SYM"});
    // SET PASSWORD with no FOR clause changes the password of the account the
    // run connects with, so every later connection is refused.
    g.prune_production("option_value_no_option_type", {"PASSWORD_SYM", "!user"});
    // An empty row in a table value constructor - VALUES() - is rejected.
    for (const char *r : {"opt_values", "opt_values_with_names"})
      g.prune_production(r, {"<empty>"});
    // A standalone VALUES(..) statement shares its row list with INSERT, where
    // DEFAULT is legal; on its own the server rejects DEFAULT. Drop the
    // standalone form and keep INSERT .. VALUES (DEFAULT, ..).
    g.prune_production("simple_table", {"table_value_constructor"});
    // Without an alias, naming the same table twice in one FROM is rejected.
    g.prune_production("opt_table_alias_clause", {"<empty>"});
    // INSERT/REPLACE DELAYED is rejected by every engine here.
    g.prune_production("insert_replace_option", {"DELAYED_SYM"});
    // LIMIT .. ROWS EXAMINED is a SELECT-only clause, but the grammar shares
    // limit_clause with UPDATE and DELETE, where the server rejects it.
    g.prune_production("limit_clause", {"EXAMINED_SYM"});
    // '?' only binds in a prepared statement; these run directly.
    g.prune_production("param_marker", {"PARAM_MARKER"});
    // The lexer only returns NOT2_SYM for the NOT keyword under
    // HIGH_NOT_PRECEDENCE (sql_lex.cc), so under the default sql_mode nothing
    // produces it. Both rules that offer it have a working alternative - NOT_SYM
    // for not, '!' for not2 - so drop the alternative rather than guess a
    // spelling for a token the lexer never emits.
    for (const char *r : {"not", "not2"}) g.prune_production(r, {"NOT2_SYM"});
    // bit_expr has three interval-first forms whose trailing symbol is a full
    // expr - INTERVAL_SYM expr interval '+' expr - so a logical operator ends up
    // at bit_expr level. The narrow contexts that take a bit_expr, such as
    // UPDATE .. FOR PORTION OF .. FROM .. TO, then fail to parse: bison's
    // precedence rules do not admit what the productions allow. The common
    // "expr + INTERVAL n unit" form is a separate production and stays.
    g.prune_production("bit_expr", {"INTERVAL_SYM", "!bit_expr"});
    // The lexer only returns MYSQL_CONCAT_SYM for '||' when the session has
    // PIPES_AS_CONCAT set (sql_lex.cc); by default '||' lexes as OR, which the
    // narrower expression contexts - FOR PORTION OF .. FROM .. TO, BEFORE
    // SYSTEM_TIME - do not accept, so the statement fails to parse. Same class
    // as NOT2_SYM, which the lexer only returns under HIGH_NOT_PRECEDENCE.
    g.prune_production("mysql_concatenation_expr", {"MYSQL_CONCAT_SYM"});
    // CONTAINS, OVERLAPS and WITHIN take opt_expr_list, so the grammar accepts
    // CONTAINS() with no arguments while the server needs two geometries. They
    // are the cheapest function-call exits, so the walk reached for them
    // constantly and every one came back as a wrong-parameter-count error.
    for (const char *k : {"CONTAINS_SYM", "OVERLAPS_SYM", "WITHIN"})
      g.prune_production("function_call_generic", {k});
    // FLUSH TABLES WITH READ LOCK holds a global read lock over the whole
    // server until the session unlocks. FOR EXPORT needs a table list, and the
    // list the grammar pairs it with can be empty, so it usually comes out as
    // FLUSH TABLES FOR EXPORT, which does not parse.
    g.prune_production("flush_lock", {"READ_SYM", "LOCK_SYM"});
    g.prune_production("flush_lock", {"EXPORT_SYM"});
    // A server PORT option takes a number, not a string.
    g.prune_production("server_option", {"PORT_SYM", "TEXT_STRING_sys"});
    // LOAD DATA LOCAL INFILE makes the client open the named file, and a random
    // name carrying a '%' reaches a printf format string in the client's error
    // path, which glibc aborts on. The non-LOCAL form stays.
    g.prune_production("opt_local", {"LOCAL_SYM"});
    // A SELECT with no FROM clause cannot name a column.
    g.prune_production("opt_from_clause", {"<empty>"});
    // DUAL is the cheapest table reference, so every FROM collapsed to it and
    // SELECT * FROM DUAL is rejected. Without it the walk names real tables.
    g.prune_production("table_reference_list", {"DUAL_SYM"});
    // LOOP/WHILE/REPEAT in a stored program or trigger body. A grammar walk
    // cannot build a terminating condition, so the body spins forever and the
    // statement that fires it never returns. FOR loops keep their bounds.
    for (const char *r : {"sp_unlabeled_control", "sp_labeled_control"})
      for (const char *k : {"LOOP_SYM", "WHILE_SYM", "REPEAT_SYM"})
        g.prune_production(r, {k});
    // A read-only transaction rejects every write for as long as it is open.
    for (const char *r : {"start_transaction_option", "transaction_access_mode_types"})
      g.prune_production(r, {"ONLY_SYM"});
    // Every rule --names reports with a '.'-qualified identifier production.
    // Identifier leaves are one flat pool, so a qualified name puts a table name
    // in the database slot (t1.t1) or none at all (.t1); neither resolves.
    for (const char *r :
         {"table_ident", "table_ident_opt_wild", "simple_ident", "call",
          "drop_routine", "field_ident", "function_call_generic", "grant_ident",
          "limit_option", "opt_object_member_access",
          "option_value_following_option_type", "option_value_no_option_type",
          "optionally_qualified_column_ident", "set_stmt_option",
          "sf_return_type", "simple_ident_nospvar", "sp_name",
          "sp_param_anchored", "variable_aux"})
      g.prune_production(r, {"."});
    // "t1.*" is the exception: one qualifier names the table and resolves, and
    // both these rules only ever offer a qualified form, so pruning every one
    // leaves them empty and SELECT t1.* out of reach. Keep the single-qualifier
    // production and drop the "db.t1.*" one, which the flat name pool cannot fill.
    for (const char *r : {"table_wild", "select_sublist_qualified_asterisk"})
      g.prune_longer_than(r, 3);
    // SELECT .. INTO a bare name needs a declared stored-program variable;
    // only the user-variable form works in a plain session.
    g.keep_production("select_outvar", {"@"});
    // The run connects to one database and has to stay there. CREATE/ALTER/DROP
    // DATABASE builds a second one and dropping it leaves the session with no
    // default database, after which every statement fails.
    g.prune_production("create", {"DATABASE"});
    g.prune_production("alter", {"DATABASE"});
    g.prune_production("drop", {"DATABASE"});
    // ALTER TABLE .. DROP PARTITION IF EXISTS asserts on a debug build
    // (MDEV-36371). Drop this line once that bug is fixed.
    g.prune_production("alter_commands", {"DROP", "PARTITION_SYM", "opt_if_exists"});
    // SET STATEMENT <var> = <predicate over a column> FOR REPAIR/CHECK/OPTIMIZE/
    // ANALYZE TABLE asserts on a debug build (MDEV-28506, open). It took 7 of 12
    // trials before this, and every one of them is deleted as a known bug, so the
    // whole SET STATEMENT .. FOR form goes until that is fixed - the statement the
    // FOR clause wraps is the top-level statement rule, so there is no narrower
    // cut. Drop this line once that bug is fixed.
    g.prune_production("set_param", {"STATEMENT_SYM"});
    // A CTE's CYCLE clause is only accepted on a WITH RECURSIVE (sql_yacc.yy
    // checks with_recursive and calls parse_error), and which of the two the WITH
    // gets is decided in a different rule, so the walk cannot pair them. It was
    // 458 of the 677 statements the server rejected as a syntax error.
    g.prune_production("opt_cycle", {"CYCLE_SYM"});
  }
  if (!g.is_nonterminal(start)) {
    std::cerr << "revgen: start symbol '" << start
              << "' not found in grammar\n";
    return 2;
  }
  g.intern();  // grammar is final from here; the walk reads symbols by id
  auto kw = load_keywords(read_file(lex));

  if (info) {
    Generator gen(g, kw, 1, max_chain, chain_share, grants);
    std::vector<std::string> dead = gen.unreachable_rules();
    std::cerr << "yacc:      " << yacc << "\n"
              << "lex:       " << lex << "\n"
              << "rules:     " << g.rule_count() << " nonterminals\n"
              << "terminals: " << g.terminal_count() << " referenced\n"
              << "keywords:  " << kw.size() << " from lex.h\n"
              << "dropped:   " << g.error_prod_count()
              << " productions whose action only raises a parse error\n"
              << "start:     " << start << " (min height "
              << gen.min_height(start) << ")\n"
              << "unreachable: " << dead.size()
              << " rules no derivation can complete\n";
    for (const std::string &h : dead) std::cerr << "  " << h << "\n";
    return 0;
  }

  if (trace) {
    Generator gen(g, kw, seed ? *seed : 1);
    gen.trace_min(start);
    return 0;
  }
  if (dump) { g.dump(start); return 0; }
  if (names) { Generator gen(g, kw, 1); gen.audit_names(); return 0; }
  if (parens) { g.audit_empty_parens(); return 0; }

  if (audit) {
    Generator gen(g, kw, 1);
    std::vector<std::pair<int, std::string>> silent;
    for (const auto &kv : g.terminal_refs())
      if (gen.terminal_text(kv.first).empty())
        silent.push_back({kv.second, kv.first});
    std::sort(silent.rbegin(), silent.rend());
    std::cerr << "silent terminals (emit nothing), by production ref-count:\n";
    for (const auto &s : silent)
      std::cerr << "  " << s.first << "\t" << s.second << "\n";
    return 0;
  }


  if (threads == 0) threads = std::max(1u, std::thread::hardware_concurrency() / 4);
  if ((long)threads > queries) threads = (unsigned)queries;

  std::FILE *fails = nullptr;
  std::mutex fails_mu;
  if (validate) {
    mysql_library_init(0, nullptr, nullptr);
    if (fails_path.empty()) {
      std::string d = output == "-" ? "." : dir_of(output);
      fails_path = d + "/revgen_failed_1064.sql";
    }
    fails = std::fopen(fails_path.c_str(), "w");
    // Measuring the parse-valid rate means writing the output to /dev/null, which
    // derives a fails path under /dev that cannot be created. Losing the log in
    // exactly the run that wants it is no good, so fall back to the temp dir.
    if (!fails) {
      std::string alt = std::filesystem::temp_directory_path().string() +
                        "/revgen_failed_1064." + std::to_string(getpid()) + ".sql";
      fails = std::fopen(alt.c_str(), "w");
      std::cerr << "revgen: cannot write " << fails_path << "; "
                << (fails ? "logging to " + alt : std::string("1064 log disabled"))
                << "\n";
      if (fails) fails_path = alt;
    }
  }

  uint64_t base;
  if (seed) {
    base = *seed;
  } else {  // high-entropy mix (matches generatorcpp); distinct per parallel revgen process
    std::random_device rd;
    base = (uint64_t(rd()) << 32) ^ rd();
    base ^= uint64_t(std::chrono::high_resolution_clock::now().time_since_epoch().count());
    base ^= uint64_t(getpid());
  }
  std::cerr << "revgen: queries=" << queries << " threads=" << threads
            << " depth=" << depth << " start=" << start
            << " yacc=" << yacc
            << (validate ? " validate=on" : "") << "\n";

  std::string base_part = output == "-"
      ? (std::filesystem::temp_directory_path().string() + "/revgen." +
         std::to_string(getpid()))
      : output;
  std::vector<std::string> parts(threads);
  std::vector<std::thread> ts;
  std::atomic<uint64_t> a_total{0}, a_drop{0}, a_lost{0}, a_other{0},
      a_skip{0}, a_cut{0}, a_skipped{0}, a_emitted{0};
  Coverage all_cov;
  GenStats all_stats;
  std::mutex cov_mu;

  auto t0 = std::chrono::steady_clock::now();
  long per = queries / threads, rem = queries % threads;
  for (unsigned i = 0; i < threads; ++i) {
    long n = per + ((long)i < rem ? 1 : 0);
    parts[i] = base_part + ".part" + std::to_string(i);
    ts.emplace_back([&, i, n]() {
      Generator gen(g, kw, base + i * 0x9E3779B97F4A7C15ULL, max_chain,
                    chain_share, grants);
      Coverage my_cov;
      GenStats my_stats;
      if (coverage) gen.count_coverage(&my_cov, &my_stats);
      if (!probe.empty()) gen.probe_rule(probe);
      Validator v;
      bool val = false;
      if (validate) {
        mysql_thread_init();
        val = v.init(socket_path, db, fails, &fails_mu);
        if (!val)
          std::fprintf(stderr, "thread %u: validation disabled (no conn)\n", i);
      }
      std::ofstream f(parts[i], std::ios::binary | std::ios::trunc);
      std::string buf;
      buf.reserve(1 << 16);
      long emitted = 0, attempts = 0, reset_round = 0;
      const long cap = (validate ? 10 : 3) * n + 100;
      Xoshiro256pp srng(base + 0xA5A5A5A5A5A5A5A5ULL + i);
      // Spread the interjections over +/-20% of the interval so they do not
      // land on a fixed stride.
      const long gap_lo = std::max(1L, schema_every * 4 / 5);
      const long gap_span = std::max(1L, schema_every * 2 / 5);
      auto next_gap = [&]() { return gap_lo + (long)(srng() % (uint64_t)gap_span); };
      long next_schema = schema_every ? next_gap() : 0;
      while (emitted < n && attempts < cap) {
        ++attempts;
        if (next_schema && emitted >= next_schema) {
          // Releases have to keep pace with LOCK TABLES, which the walk emits
          // about once per 130 statements. Rebuilding the schema is only needed
          // when a generated DROP or ALTER has taken a table away, so it runs at
          // a quarter of that rate.
          for (size_t k = 0; k < kResetCount; ++k) { buf += kResetSql[k]; buf += ";\n"; }
          long added = (long)kResetCount;
          if (++reset_round % 4 == 0) {
            for (size_t k = 0; k < kSetupCount; ++k) { buf += kSetupSql[k]; buf += ";\n"; }
            added += (long)kSetupCount;
          }
          next_schema = emitted + next_gap();
          if (buf.size() >= (1 << 16)) { f.write(buf.data(), buf.size()); buf.clear(); }
          emitted += added;
          continue;
        }
        std::string q = gen.generate_mixed(start, depth, depth_max);
        // The walk stopped at its step or token cap, so this statement is cut off
        // mid-derivation. Emitting it only adds a parse failure; derive another.
        if (gen.truncated()) { ++a_cut; continue; }
        if (skip_statement(q)) { ++a_skipped; continue; }
        if (q.find_first_not_of(" \t\n") == std::string::npos) continue;
        if (val && !v.keep(q)) continue;
        buf += q; buf += ";\n";
        if (buf.size() >= (1 << 16)) { f.write(buf.data(), buf.size()); buf.clear(); }
        ++emitted;
      }
      if (!buf.empty()) f.write(buf.data(), buf.size());
      f.close();
      a_emitted += emitted;
      if (coverage) {
        std::lock_guard<std::mutex> lk(cov_mu);
        all_stats += my_stats;
        for (const auto &kv : my_cov) {
          std::vector<long> &dst = all_cov[kv.first];
          if (dst.size() < kv.second.size()) dst.resize(kv.second.size(), 0);
          for (size_t k = 0; k < kv.second.size(); ++k) dst[k] += kv.second[k];
        }
      }
      if (val) {
        a_total += v.total; a_drop += v.dropped; a_lost += v.lost;
        a_other += v.other; a_skip += v.skipped;
      }
      if (validate) mysql_thread_end();
    });
  }
  for (auto &t : ts) t.join();
  auto t1 = std::chrono::steady_clock::now();

  // Merge part files into the output sink, then remove them.
  std::ofstream fout;
  std::ostream *sink = &std::cout;
  if (output != "-") {
    fout.open(output, std::ios::binary | std::ios::trunc);
    if (!fout) { std::cerr << "revgen: cannot open " << output << "\n"; return 1; }
    sink = &fout;
  }
  std::vector<char> cbuf(1 << 20);
  for (auto &p : parts) {
    std::ifstream in(p, std::ios::binary);
    while (in) { in.read(cbuf.data(), cbuf.size()); sink->write(cbuf.data(), in.gcount()); }
    in.close();
    std::error_code ec;
    std::filesystem::remove(p, ec);
  }
  sink->flush();

  double secs = std::chrono::duration<double>(t1 - t0).count();
  std::cerr << "revgen: emitted " << a_emitted << "/" << queries << " in "
            << secs << "s";
  if (a_cut) std::cerr << " cut=" << a_cut;
  if (a_skipped) std::cerr << " skipped=" << a_skipped;
  std::cerr << (output == "-" ? "" : " -> " + output) << "\n";
  if (validate) {
    std::cerr << "[validate] prepared=" << a_total << " skipped(non-prep)="
              << a_skip << " dropped(1064)=" << a_drop << " server_lost="
              << a_lost << " other_err=" << a_other << "\n";
    uint64_t judged = a_total - a_skip;
    if (judged)
      std::cerr << "[validate] parse-valid rate="
                << (100.0 * (judged - a_drop) / judged) << "% (of preparable); "
                << "1064 logged to " << fails_path << "\n";
    if (fails) std::fclose(fails);
    mysql_library_end();
  }
  if (coverage) report_coverage(g, all_cov, all_stats, start, coverage_limit);
  return 0;
}
