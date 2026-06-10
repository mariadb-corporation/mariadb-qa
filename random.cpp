// Standalone high-entropy random integer generator (xoshiro256++).
// Mirrors the PRNG in generatorcpp/generator.cpp. Prints one integer:
//   random            -> 0..32767   (drop-in for bash ${RANDOM})
//   random N          -> 0..N-1
//   random MIN MAX    -> MIN..MAX    (inclusive)
// Seeded per invocation from std::random_device + high-resolution clock.
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <bit>
#include <random>
#include <chrono>

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
  Xoshiro256pp rng;
  std::random_device rd;
  uint64_t seed = (uint64_t(rd()) << 32) ^ rd();
  seed ^= uint64_t(std::chrono::high_resolution_clock::now().time_since_epoch().count());
  seed ^= uint64_t(reinterpret_cast<uintptr_t>(&rng));
  rng.seed(seed);

  uint64_t lo = 0, hi = 32767;
  if (argc == 2) {
    long long n = std::atoll(argv[1]);
    if (n <= 0) { std::fprintf(stderr, "random: N must be > 0\n"); return 1; }
    lo = 0; hi = static_cast<uint64_t>(n) - 1;
  } else if (argc >= 3) {
    long long a = std::atoll(argv[1]), b = std::atoll(argv[2]);
    if (a > b) { long long t = a; a = b; b = t; }
    lo = static_cast<uint64_t>(a); hi = static_cast<uint64_t>(b);
  }
  const uint64_t range = hi - lo + 1;  // range==0 only on a full 64-bit span (not reachable via the CLI above)
  const uint64_t r = (range == 0) ? rng.next() : (lo + rng.next() % range);
  std::printf("%llu\n", static_cast<unsigned long long>(r));
  return 0;
}
