# MariaDB QA Framework Container

A container image that holds a complete MariaDB QA box: the build toolchain, the
`mariadb-qa` framework, the testing SQL generators and the testcase reducer. You
map a `/test` directory for the server builds and a `/data` directory for the
test runs, then work inside the box the same way as on a QA server.

The image holds no MariaDB server build. You clone the sources and build them in
the box, so the box always tests the versions you choose.

| Guide | Content |
|---|---|
| [SETUP.md](SETUP.md) | Host prerequisites, image build, registry push and pull, directory mapping |
| [USAGE.md](USAGE.md) | Daily use: build servers, run testing SQL, analyse, reduce, report |

## Quick start (SETUP.md has the full detail)

```bash
# 1. One host setting for now, needed for core files
sudo sysctl -w kernel.core_pattern=core

# 2. Get the image
docker pull ghcr.io/mariadb-corporation/mariadb-qa:latest

# 3. Start the box and open a shell in it
./mariadb-qa --test /my/test --data /my/data

# 4. In the box: check it, then read the usage guide
qa-check
qa-guide
```

`/test` and `/data` stay on the host, so a box that you stop or remove never
loses a build or a test result.

## What is in the box

| Item | Detail |
|---|---|
| Base | Ubuntu 24.04 |
| Compilers | clang built from source in `/usr/local`, and apt clang-20 for MSAN |
| Framework | `~/mariadb-qa`, a shallow clone that you update with `qa-update` |
| Testing SQL | `generatorcpp/generator` and `revgen/revgen` |
| Reducer | `reducercpp/reducer` |
| Sanitizers | UBSAN, ASAN and TSAN. For MSAN, build the instrumented libraries once with `qa-upgrade msan` |
| Debug tools | gdb, valgrind, rr, screen |
| Claude Code | `claude`, with the framework skills wired up by `linkit` |

## Commands

On the host:

```
./mariadb-qa           Start the box and open a shell in it
./mariadb-qa build     Build the image from this directory
./mariadb-qa start     Start the box only, without a shell
./mariadb-qa shell     Open a shell in the box
./mariadb-qa check     Check the box
./mariadb-qa update    Pull mariadb-qa and run linkit
./mariadb-qa upgrade   Rebuild clang and the MSAN libraries in the box
./mariadb-qa status    Show the box, the mappings and the disk use
./mariadb-qa stop      Stop the box, keeping /test and /data
./mariadb-qa rm        Stop and remove the box
./mariadb-qa pull      Pull the image
./mariadb-qa push      Push the image
```

In the box:

```
qa-check       Check the box: compiler, core files, mapped directories, tools
qa-guide       Read a guide: usage, setup, readme, cheatsheet
cb             Clone the sources and build them, optimised plus debug
cb-san         The same, UBSAN plus ASAN. Also cb-msan, cb-tsan, cb-val
qa-run         Point gomd at a build and a configuration, then start the runs
qa-tools       Build the reducer and the testing SQL generators
qa-update      Pull mariadb-qa and run linkit
qa-upgrade     Rebuild clang from source, and the MSAN instrumented libraries
```

Run `./mariadb-qa help` for every option.

## Layout

```
docker/
  Dockerfile          The image, in stages
  mariadb-qa          Host side control script
  README.md           This file
  SETUP.md            Setup guide
  USAGE.md            Usage guide
  files/
    entrypoint.sh     Aligns the box user with you, runs linkit, keeps the box up
    box-setup.sh      Per-user settings: vim, gdb, screen
    qa-check.sh       Box check
    qa-clonebuild.sh  The cb, cb-san, cb-msan, cb-tsan and cb-val commands
    qa-guide.sh       Opens a guide
    qa-run.sh         Sets up gomd and starts the testing SQL runs
    qa-tools.sh       Builds the reducer and the testing SQL generators
    qa-update.sh      Pulls mariadb-qa and runs linkit
    qa-upgrade.sh     Rebuilds clang and the MSAN instrumented libraries
```
