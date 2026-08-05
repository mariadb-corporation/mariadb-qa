// Standalone high-entropy random generator (xoshiro256++), the entropy source for the
// MariaDB QA framework shell scripts. Same PRNG and same seeding as generatorcpp/generator.cpp,
// revgen/revgen.cpp and reducercpp/reducer.cpp.
//
//   random                      one integer 0..32767      (drop-in for bash ${RANDOM})
//   random N                    one integer 0..N-1
//   random MIN MAX              one integer MIN..MAX      (inclusive)
//   random -n COUNT [range]     COUNT integers, one per line, same range rules
//   random --digits N           exactly N decimal digits, zero padded (uniform)
//   random --raw [BYTES]        raw random bytes on stdout, endless when BYTES is omitted
//
// --digits is for directory and file name suffixes: it keeps the length fixed and every
// value equally likely, unlike concatenating several ${RANDOM} draws.
//
// --raw feeds shuf. shuf --random-source needs a path it can read bytes from, so pass the
// stream, not this binary:
//
//   shuf --random-source=<(${HOME}/mariadb-qa/random --raw) -n 100 file.sql
//
// Passing the binary itself reads the executable's own bytes and gives the same order on
// every call.
//
// Ranges use rejection sampling, so there is no modulo bias.
#include <bit>
#include <csignal>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <ctime>
#include <string>
#include <sys/auxv.h>
#include <sys/random.h>
#include <unistd.h>
#if defined(__x86_64__)
#include <x86intrin.h>
#endif

// xoshiro256++ - BigCrush-clean 64-bit PRNG, period 2^256-1. seed_full() fills all 256 bits of
// state from the kernel CSPRNG, the kernel's per-exec random bytes, the wall clock date and
// time, a monotonic clock, the CPU cycle counter, the pid, the tid and a stack address.
struct Xoshiro256pp {
  uint64_t s[4];
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
  // Seed all 256 bits of state from independent entropy. A single 64-bit seed expanded by
  // splitmix64 can only reach 2^64 of the 2^256 states; filling every word directly removes
  // that ceiling. Sources:
  //   getrandom        kernel CSPRNG, the pool /dev/urandom serves, 32 bytes in one syscall
  //   AT_RANDOM        16 kernel-random bytes placed at exec, no syscall
  //   CLOCK_REALTIME   wall clock date and time, true nanosecond resolution
  //   CLOCK_MONOTONIC  monotonic, nanosecond; a wall clock step cannot repeat it
  //   rdtsc            CPU cycle counter, finer still than the clocks
  //   pid, tid         separate concurrent processes and threads
  //   frame address    this thread's stack, ASLR-varying per process
  // clock_gettime is used rather than std::chrono because system_clock counts microseconds
  // under libc++, so it would not carry the nanosecond.
  // Each word is then run through splitmix64, so a weak bit in any one source cannot leave a
  // whole state word structured.
  void seed_full() {
    // Pre-set to splitmix64/xoshiro constants so the words are always defined, then let
    // getrandom overwrite them. A short read or an error leaves constants in place and the
    // seven sources below still fill every word - no branch, nothing untestable.
    uint64_t w[4] = { 0x9E3779B97F4A7C15ULL, 0xBF58476D1CE4E5B9ULL,
                      0x94D049BB133111EBULL, 0x2545F4914F6CDD1DULL };
    (void)getrandom(w, sizeof(w), 0);
    if (const void* ar = reinterpret_cast<const void*>(getauxval(AT_RANDOM))) {
      uint64_t k[2];
      std::memcpy(k, ar, sizeof(k));
      w[0] ^= k[0]; w[1] ^= k[1];
    }
    struct timespec rt, mt;
    clock_gettime(CLOCK_REALTIME, &rt);
    clock_gettime(CLOCK_MONOTONIC, &mt);
    w[0] ^= uint64_t(rt.tv_sec) * 1000000000ULL + uint64_t(rt.tv_nsec);
    w[1] ^= std::rotl(uint64_t(mt.tv_sec) * 1000000000ULL + uint64_t(mt.tv_nsec), 32);
#if defined(__x86_64__)
    w[2] ^= uint64_t(__rdtsc());
#endif
    w[2] ^= uint64_t(getpid()) << 16;
    w[3] ^= uint64_t(gettid()) << 8;
    w[3] ^= uint64_t(reinterpret_cast<uintptr_t>(&w));
    for (auto& v : w) { uint64_t t = v; v = splitmix64(t); }
    s[0] = w[0]; s[1] = w[1]; s[2] = w[2]; s[3] = w[3];
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
};

// Uniform 0..range-1 without modulo bias.
static inline uint64_t bounded(Xoshiro256pp& r, uint64_t range) {
  if (range == 0) return r.next();                                 // full 64-bit span
  if ((range & (range - 1)) == 0) return r.next() & (range - 1);    // power of two
  const uint64_t threshold = (0ULL - range) % range;
  uint64_t x;
  do { x = r.next(); } while (x < threshold);
  return x % range;
}

static void usage() {
  std::fprintf(stderr,
    "usage: random                    one integer 0..32767\n"
    "       random N                  one integer 0..N-1\n"
    "       random MIN MAX            one integer MIN..MAX inclusive\n"
    "       random -n COUNT [range]   COUNT integers, one per line\n"
    "       random --digits N         exactly N decimal digits, zero padded\n"
    "       random --raw [BYTES]      raw bytes on stdout, endless when BYTES is omitted\n"
    "\n"
    "shuf: shuf --random-source=<(random --raw) -n 100 file\n");
}

// Emit raw bytes. Endless when total is 0. A closed pipe ends the stream, which is what
// happens once shuf has read all it needs.
static int emit_raw(Xoshiro256pp& rng, unsigned long long total) {
  std::signal(SIGPIPE, SIG_IGN);
  uint64_t buf[8192];
  unsigned long long done = 0;
  while (total == 0 || done < total) {
    size_t want = sizeof(buf);
    if (total != 0 && total - done < want) want = size_t(total - done);
    for (size_t i = 0; i < (want + 7) / 8; ++i) buf[i] = rng.next();
    if (std::fwrite(buf, 1, want, stdout) != want) return 0;  // pipe closed
    done += want;
  }
  std::fflush(stdout);
  return 0;
}

// N uniform decimal digits, zero padded, built in chunks of at most 18 digits so any N works.
static std::string digits(Xoshiro256pp& rng, unsigned n) {
  static const uint64_t pow10[19] = {
    1ULL, 10ULL, 100ULL, 1000ULL, 10000ULL, 100000ULL, 1000000ULL, 10000000ULL,
    100000000ULL, 1000000000ULL, 10000000000ULL, 100000000000ULL, 1000000000000ULL,
    10000000000000ULL, 100000000000000ULL, 1000000000000000ULL, 10000000000000000ULL,
    100000000000000000ULL, 1000000000000000000ULL };
  std::string out;
  out.reserve(n);
  while (n > 0) {
    const unsigned chunk = n > 18 ? 18 : n;
    char tmp[32];
    std::snprintf(tmp, sizeof(tmp), "%0*llu", int(chunk),
                  static_cast<unsigned long long>(bounded(rng, pow10[chunk])));
    out += tmp;
    n -= chunk;
  }
  return out;
}

int main(int argc, char** argv) {
  std::signal(SIGPIPE, SIG_IGN);  // A reader that stops early ends the run cleanly
  Xoshiro256pp rng;
  rng.seed_full();

  unsigned long long count = 1;
  unsigned ndigits = 0;
  long long lo = 0, hi = 32767;
  int i = 1;

  for (; i < argc; ++i) {
    if (std::strcmp(argv[i], "-h") == 0 || std::strcmp(argv[i], "--help") == 0) {
      usage(); return 0;
    } else if (std::strcmp(argv[i], "--raw") == 0) {
      unsigned long long bytes = 0;
      if (i + 1 < argc) {
        char* end = nullptr;
        unsigned long long v = std::strtoull(argv[i + 1], &end, 10);
        if (end && *end == '\0') { bytes = v; ++i; }
      }
      return emit_raw(rng, bytes);
    } else if (std::strcmp(argv[i], "-n") == 0) {
      if (i + 1 >= argc) { usage(); return 2; }
      char* end = nullptr;
      const long long v = std::strtoll(argv[++i], &end, 10);
      if (!end || *end != '\0' || v < 0) {
        std::fprintf(stderr, "random: -n COUNT must be 0 or higher\n");
        return 1;
      }
      count = static_cast<unsigned long long>(v);
      if (count == 0) return 0;
    } else if (std::strcmp(argv[i], "--digits") == 0) {
      if (i + 1 >= argc) { usage(); return 2; }
      long v = std::atol(argv[++i]);
      if (v < 1) { std::fprintf(stderr, "random: --digits N must be >= 1\n"); return 1; }
      ndigits = unsigned(v);
    } else {
      break;  // what is left is the range
    }
  }

  const int nrange = argc - i;
  if (nrange == 1) {
    long long n = std::atoll(argv[i]);
    if (n <= 0) { std::fprintf(stderr, "random: N must be > 0\n"); return 1; }
    lo = 0; hi = n - 1;
  } else if (nrange >= 2) {
    long long a = std::atoll(argv[i]), b = std::atoll(argv[i + 1]);
    if (a > b) { long long t = a; a = b; b = t; }
    lo = a; hi = b;
  }

  // Buffered, flushed in blocks, so a large -n COUNT does not build the whole result in memory.
  const uint64_t range = uint64_t(hi) - uint64_t(lo) + 1;  // 0 means the full 64-bit span
  std::string out;
  out.reserve(1 << 16);
  for (unsigned long long k = 0; k < count; ++k) {
    if (ndigits > 0) out += digits(rng, ndigits);
    else             out += std::to_string(static_cast<long long>(uint64_t(lo) + bounded(rng, range)));
    out += '\n';
    if (out.size() >= (1u << 15)) {
      if (std::fwrite(out.data(), 1, out.size(), stdout) != out.size()) return 0;  // pipe closed
      out.clear();
    }
  }
  std::fwrite(out.data(), 1, out.size(), stdout);
  return 0;
}
