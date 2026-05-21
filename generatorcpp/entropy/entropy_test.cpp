// Created by Roel Van de Paar, MariaDB
// Standalone entropy test for the xoshiro256++ PRNG used by generator.cpp.
// Build:  g++ -std=c++20 -O3 -march=native entropy_test.cpp -o entropy_test
// Run:    ./entropy_test [N]      (default N = 100,000,000)
//
// Tests:
//   1. Speed (ns per draw)
//   2. 64-bit bit-balance (each bit should be 50% ones)
//   3. Byte-frequency histogram + chi-square (uniform expected)
//   4. Modulo-4377 bucket distribution (matches dispatcher modulus)
//   5. Runs test (consecutive same-bit sequences)
//   6. Top-31-bit slice quality (the form rnd() actually uses)

#include <array>
#include <bit>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <random>

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
  inline uint64_t next() {
    const uint64_t result = std::rotl(s[0] + s[3], 23) + s[0];
    const uint64_t t = s[1] << 17;
    s[2] ^= s[0]; s[3] ^= s[1]; s[1] ^= s[2]; s[0] ^= s[3];
    s[2] ^= t;
    s[3] = std::rotl(s[3], 45);
    return result;
  }
};

int main(int argc, char** argv) {
  long N = (argc > 1) ? std::atol(argv[1]) : 100'000'000L;
  if (N < 1000) N = 1000;

  Xoshiro256pp rng;
  std::random_device rd;
  rng.seed((uint64_t(rd()) << 32) ^ rd());

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

  std::printf("== done ==\n");
  return 0;
}
