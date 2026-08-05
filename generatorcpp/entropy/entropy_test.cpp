// Created by Roel Van de Paar, MariaDB
// Standalone entropy test for the xoshiro256++ PRNG and the seed mix shared by
// generator.cpp, revgen.cpp, reducer.cpp and random.cpp.
// Build:  ./build.sh
// Run:    ./entropy_test [N]      (default N = 100,000,000)
//
// Tests:
//   1. Speed (ns per draw)
//   2. 64-bit bit-balance (each bit should be 50% ones)
//   3. Byte-frequency histogram + chi-square (uniform expected)
//   4. Modulo-4377 bucket distribution (matches dispatcher modulus)
//   5. Runs test (consecutive same-bit sequences)
//   6. Top-31-bit slice quality (the form rnd() actually uses)
//   7. bounded() rejection sampler, over a range that is not a power of two
//   8. seed_full(): all 256 state bits independent, no repeat across rapid calls

#include <array>
#include <bit>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <set>
#include <ctime>
#include <vector>
#include <sys/auxv.h>
#include <sys/random.h>
#include <unistd.h>
#if defined(__x86_64__)
#include <x86intrin.h>
#endif

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
  // Uniform 0..range-1 without modulo bias.
  inline uint64_t bounded(uint64_t range) {
    if (range == 0) return next();
    if ((range & (range - 1)) == 0) return next() & (range - 1);
    const uint64_t threshold = (0ULL - range) % range;
    uint64_t x;
    do { x = next(); } while (x < threshold);
    return x % range;
  }
};


int main(int argc, char** argv) {
  long N = (argc > 1) ? std::atol(argv[1]) : 100'000'000L;
  if (N < 1000) N = 1000;

  Xoshiro256pp rng;
  rng.seed_full();

  // --- Speed ---
  std::printf("== xoshiro256++ entropy test ==\n");
  std::printf("N = %ld draws\n\n", N);

  auto t0 = std::chrono::steady_clock::now();
  uint64_t sink = 0;
  for (long i = 0; i < N; ++i) sink ^= rng.next();
  auto t1 = std::chrono::steady_clock::now();
  double ns_per_draw =
      std::chrono::duration<double, std::nano>(t1 - t0).count() / double(N);
  std::printf("1. Speed:         %.2f ns/draw  (%.1f M draws/sec)  [sink=%016lx]\n\n",
              ns_per_draw, 1000.0 / ns_per_draw, (unsigned long)sink);

  // --- Bit-balance (per-bit zeros vs ones over 64 bits) ---
  uint64_t bit_ones[64] = {};
  for (long i = 0; i < N; ++i) {
    uint64_t v = rng.next();
    for (int b = 0; b < 64; ++b) if ((v >> b) & 1) ++bit_ones[b];
  }
  double worst_bias = 0.0;
  int worst_bit = -1;
  for (int b = 0; b < 64; ++b) {
    double ratio = double(bit_ones[b]) / double(N);
    double bias = std::abs(ratio - 0.5);
    if (bias > worst_bias) { worst_bias = bias; worst_bit = b; }
  }
  std::printf("2. Bit-balance:   worst bit=%d  ones-ratio bias = %.6f  (expect <0.0005 for N=1e8)\n",
              worst_bit, worst_bias);
  std::printf("   verdict: %s\n\n", worst_bias < 0.001 ? "OK" : "SUSPICIOUS");

  // --- Byte histogram + chi-square (treat output as 8-byte little-endian) ---
  uint64_t byte_count[256] = {};
  long total_bytes = 0;
  for (long i = 0; i < N; ++i) {
    uint64_t v = rng.next();
    for (int k = 0; k < 8; ++k) {
      byte_count[(v >> (8 * k)) & 0xFF]++;
    }
    total_bytes += 8;
  }
  double expected = double(total_bytes) / 256.0;
  double chi2 = 0.0;
  for (int b = 0; b < 256; ++b) {
    double diff = double(byte_count[b]) - expected;
    chi2 += diff * diff / expected;
  }
  // 255 dof: 99% threshold ≈ 310.46, 99.9% ≈ 330.5
  std::printf("3. Byte chi^2:    %.2f  (255 dof; expect <310 at 99%% confidence)\n", chi2);
  std::printf("   verdict: %s\n\n", chi2 < 330.0 ? "OK" : "SUSPICIOUS");

  // --- Modulo-4377 bucket distribution (matches dispatcher modulus) ---
  const int M = 4377;
  std::vector<uint64_t> mbuck(M, 0);
  for (long i = 0; i < N; ++i) {
    int v = static_cast<int>(rng.next() >> 33);  // matches rnd() in generator.cpp
    mbuck[v % M]++;
  }
  double m_exp = double(N) / double(M);
  double m_chi2 = 0.0;
  uint64_t m_min = mbuck[0], m_max = mbuck[0];
  for (int b = 0; b < M; ++b) {
    if (mbuck[b] < m_min) m_min = mbuck[b];
    if (mbuck[b] > m_max) m_max = mbuck[b];
    double diff = double(mbuck[b]) - m_exp;
    m_chi2 += diff * diff / m_exp;
  }
  // 4376 dof: critical 99.9% ≈ 4376 + 3.29 * sqrt(2*4376) ≈ 4683
  std::printf("4. mod-4377 chi^2: %.2f  (4376 dof; expect <4683 at 99.9%% conf)\n", m_chi2);
  std::printf("   bucket spread: min=%lu  max=%lu  expected=%.0f\n", m_min, m_max, m_exp);
  std::printf("   verdict: %s\n\n", m_chi2 < 4683.0 ? "OK" : "SUSPICIOUS");

  // --- Runs test: count alternations of bit-31 ---
  uint64_t runs = 1;
  int prev_bit = static_cast<int>((rng.next() >> 31) & 1);
  for (long i = 1; i < N; ++i) {
    int bit = static_cast<int>((rng.next() >> 31) & 1);
    if (bit != prev_bit) ++runs;
    prev_bit = bit;
  }
  double expected_runs = double(N) / 2.0 + 0.5;
  double sd_runs = std::sqrt(double(N) - 1.0) / 2.0;
  double z = (double(runs) - expected_runs) / sd_runs;
  std::printf("5. Runs test:     bit-31 alternations = %lu  expected~%.0f  z=%.3f\n",
              runs, expected_runs, z);
  std::printf("   verdict: %s\n\n", std::abs(z) < 3.5 ? "OK" : "SUSPICIOUS");

  // --- Top-31-bit slice quality (what rnd() actually produces) ---
  // Quick sanity: full int range usage when masked to 31 bits.
  int slice_min = INT32_MAX, slice_max = 0;
  for (long i = 0; i < 1'000'000L; ++i) {
    int v = static_cast<int>(rng.next() >> 33);
    if (v < slice_min) slice_min = v;
    if (v > slice_max) slice_max = v;
  }
  std::printf("6. Top-31 range:  min=%d  max=%d  (over 1M samples; 2^31-1 = %d)\n",
              slice_min, slice_max, INT32_MAX);
  std::printf("   verdict: %s\n\n",
              (slice_max > (INT32_MAX - INT32_MAX / 1000) && slice_min < INT32_MAX / 1000) ? "OK" : "SUSPICIOUS");

  // --- bounded() rejection sampler over a range that is not a power of two ---
  {
    const uint64_t B = 4377;
    std::vector<uint64_t> bb(B, 0);
    const long BN = (N > 43'770'000L) ? 43'770'000L : N;
    for (long i = 0; i < BN; ++i) bb[rng.bounded(B)]++;
    double b_exp = double(BN) / double(B);
    double b_chi2 = 0.0;
    uint64_t b_min = bb[0], b_max = bb[0], hit = 0;
    for (uint64_t b = 0; b < B; ++b) {
      if (bb[b] < b_min) b_min = bb[b];
      if (bb[b] > b_max) b_max = bb[b];
      if (bb[b] > 0) ++hit;
      double diff = double(bb[b]) - b_exp;
      b_chi2 += diff * diff / b_exp;
    }
    std::printf("7. bounded(%lu) chi^2: %.2f  (%lu dof; expect <4683 at 99.9%% conf)\n",
                (unsigned long)B, b_chi2, (unsigned long)(B - 1));
    std::printf("   values hit: %lu/%lu   bucket spread: min=%lu max=%lu expected=%.0f\n",
                hit, (unsigned long)B, b_min, b_max, b_exp);
    std::printf("   verdict: %s\n\n", (b_chi2 < 4683.0 && hit == B) ? "OK" : "SUSPICIOUS");
  }

  // --- seed_full(): every state word from independent entropy, no repeats across rapid calls ---
  {
    const int SN = 10000;
    std::set<uint64_t> words;
    for (int i = 0; i < SN; ++i) {
      Xoshiro256pp t;
      t.seed_full();
      for (int k = 0; k < 4; ++k) words.insert(t.s[k]);
    }
    std::printf("8. seed_full():   %zu distinct state words over %d rapid calls (%d words)\n",
                words.size(), SN, SN * 4);
    std::printf("   verdict: %s\n\n", words.size() == size_t(SN) * 4 ? "OK" : "SUSPICIOUS");
  }

  std::printf("== done ==\n");
  return 0;
}
