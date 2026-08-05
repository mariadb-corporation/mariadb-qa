# Setup guide

## 1. What the host must provide

A QA box needs kernel settings that a container cannot change, because the
kernel is shared. The table shows where each setting of
`mariadb-qa/setup_server.sh` belongs.

| Setting | Where it belongs | How you get it |
|---|---|---|
| `kernel.core_pattern=core` | Host | `sudo sysctl -w kernel.core_pattern=core` |
| apport off, so it cannot take the core pattern back | Host | `sudo systemctl mask --now apport.service` |
| `fs.suid_dumpable=2` | Host | `sudo sysctl -w fs.suid_dumpable=2` |
| `vm.max_map_count`, `vm.overcommit_memory`, `vm.swappiness`, the `vm.oom_*` pair, `vm.nr_hugepages`, `fs.aio-max-nr`, `fs.file-max`, `kernel.pid_max`, `kernel.threads-max` | Host | See `setup_server.sh`. The box inherits every one of them |
| Core file size, open files, locked memory, stack size | Container | The control script passes `--ulimit` |
| `/dev/shm` size | Container | The control script passes `--shm-size` |
| Process count | Container | The control script passes `--pids-limit -1` |
| vim, gdb and screen settings, no `/etc/mysql` | Container | `box-setup.sh`, in the image |
| `kernel.sem`, `kernel.shmmni`, the `kernel.msg*` set | Neither | System V IPC, which the server does not use. Add `--sysctl` yourself if you want the exact values |

The core pattern is the one setting you must not skip. Without it the kernel
writes no usable core file, and a crash then gives no stack trace. A container
cannot set it: `/proc/sys/kernel/core_pattern` is read only inside a container
and shows the host value. On Ubuntu, apport takes that setting back at every
boot, so mask the service as well.

Only the two core file settings and the System V IPC set need attention. Every
other kernel setting of `setup_server.sh` is global, so the box reads the value
the host already holds, and `qa-check` reports what it finds.

To keep the host settings over a reboot, add them to `/etc/sysctl.conf` and run
`sudo sysctl -p`, the same way `setup_server.sh` does.

### Resources

| Resource | Guide |
|---|---|
| Memory | 32 GB is a working minimum. Give `/dev/shm` about half of the memory. One step needs more than the rest: the testing SQL generator is a single source file of 22 MB, and building it peaks at 10 to 15 GB |
| Disk for `/test` | Per version: 3 GB for a source tree, 3 GB for an optimised plus debug pair of builds, 4 GB for a sanitizer pair. On top of that, an optimised build needs about 7 GB of scratch space while it runs, and a debug build more. That space is freed when the build finishes |
| Disk for `/data` | 50 GB and up. A saved trial with a core file is large |
| CPU | Any count works. A build uses every core |

### Docker

Install Docker Engine from the Docker repository. `mariadb-qa/docker_info_new.txt`
holds the command list. Add your user to the `docker` group, then sign out and in
again.

## 2. Get the image

### Pull

```bash
docker pull ghcr.io/mariadb-corporation/mariadb-qa:latest
```

### Build

```bash
cd mariadb-qa/docker
./mariadb-qa build
```

Two parts of the build are heavy, and both are optional. Measured on a 48 core
box:

| Build | Time | Image |
|---|---|---|
| `--no-clang-source` | 10 minutes | 3.2 GB |
| Default, so clang from source | 27 minutes | 6.2 GB |

The clang build needs about 20 GB of free disk while it runs, and frees it
again. Keep 30 GB free for a build.

| Build option | Effect |
|---|---|
| `--no-clang-source` | Use apt clang-20 only. Cuts 17 minutes and 3 GB. LTO with the gold linker is then not available |
| `--no-claude` | Leave out Claude Code |
| `--with-msan-libs` | Try to build `/MSAN_libs` during the image build. See the next section |
| `--tag TAG` | Build a tag other than `latest` |

A rebuild reuses the layer cache, so the framework clone in the image can be
older than the repository. To take the newest framework into a rebuild, add
`--build-arg CLONE_DATE=$(date +%F)`. In a running box, `qa-update` does the
same thing and is the normal way to stay current.

A lean image, useful for a quick start:

```bash
./mariadb-qa build --no-clang-source --tag lean
```

The build arguments are also plain Docker arguments, so a CI job can call
`docker build` with `--build-arg WITH_CLANG_SOURCE=0` and the rest.

### Why the MSAN libraries are not in the image

MSAN builds need instrumented copies of every runtime library, in `/MSAN_libs`.
That build runs MSAN test binaries, and an MSAN binary turns address space
randomisation off through `personality()`. The default seccomp profile of a
container blocks that call, so the library build stops early, while it configures
ncurses.

The control script starts a box with that profile turned off, so the same build
completes inside a running box:

```bash
qa-upgrade msan       # An hour or more
```

The result lives in the box. To keep it for later boxes, copy it out once and
map it back in:

```bash
docker cp mariadb-qa:/MSAN_libs /my/msan_libs
./mariadb-qa --test /my/test --data /my/data --msan /my/msan_libs
```

The build itself needs a box without `--msan`, because the framework script
creates `/MSAN_libs` itself and a mapped directory does not allow that.

`--with-msan-libs` at build time works only on a build worker that allows an
MSAN binary to run, which is not the default Docker setup.

### Why the image builds clang twice

`build_clang.sh` builds clang from source to get `LLVMgold.so`, which the apt
packages leave out. That script removes the apt clang packages, and the MSAN
scripts need apt clang-20 exactly. The Dockerfile keeps the two in separate
stages and copies only `/usr/local` from the clang stage, so both compilers are
present in the final image and neither removes the other.

## 3. Start the box

```bash
./mariadb-qa --test /my/test --data /my/data
```

The command starts the box in the background and opens a shell in it. Run it
again later to open the shell of a box that already runs.

| Option | Meaning |
|---|---|
| `--test DIR` | Host directory mapped to `/test`, holding the server builds |
| `--data DIR` | Host directory mapped to `/data`, holding the test runs |
| `--shm SIZE` | Size of `/dev/shm`, for example `32g`. The default is half the memory |
| `--claude-home DIR` | Host directory mapped to `~/.claude`, which keeps the Claude Code sign-in |
| `--msan DIR` | Host directory mapped to `/MSAN_libs`, which keeps the MSAN instrumented libraries |
| `--tz ZONE` | Time zone, for example `Australia/Sydney` |
| `--privileged` | Needed by `rr` only |
| `--name NAME` | Run more than one box at the same time |
| `--force` | Map a `/test` that another install already owns |

Without `--test` and `--data` the control script uses
`~/mariadb-qa-box/test` and `~/mariadb-qa-box/data`, and creates them.

The control script also adds `SYS_PTRACE` and turns the default seccomp profile
off, so that gdb and the sanitizer runtimes are not restricted. Whether gdb can
attach to a running server still follows the host setting
`kernel.yama.ptrace_scope`, exactly as on a QA server. Reading a core file with
gdb always works.

### Directory mapping

The framework writes absolute paths into the helper scripts of every build. In
the box that path is `/home/qa/mariadb-qa`. So use a `/test` directory for the
box alone. If you map a `/test` that a native install already owns, the control
script stops and explains, because starting the box would repoint the helper
links of that install. `--force` overrides the check.

`/dev/shm` is inside the container and is not mapped. Test runs and reducers work
there, so give it room.

### What happens at every start

1. The box user takes your user and group id, so files in `/test` and `/data`
   belong to you on the host.
2. `linkit` runs. It creates every helper in `/test`, `/data` and the home
   directory, links the Claude Code skills, and writes the alias list.
3. The alias list is added to `.bashrc` once.
4. The banner reports the framework revision, the compiler and `/dev/shm`.

`sudo` works without a password in the box, as on a QA server.

## 4. Push to the registry

The image name is `ghcr.io/mariadb-corporation/mariadb-qa`.

```bash
# A GitHub token with write:packages, held in an environment variable
echo "${GITHUB_TOKEN}" | docker login ghcr.io -u <your-github-user> --password-stdin

cd mariadb-qa/docker
./mariadb-qa build
./mariadb-qa push
```

`push` sends two tags: `latest` and the date, for example `20260804`. The date
tag lets an engineer stay on a known image while `latest` moves on.

To use another registry, pass `--image`, or set `MARIADB_QA_IMAGE`:

```bash
./mariadb-qa build --image docker.io/myuser/mariadb-qa:latest
./mariadb-qa push  --image docker.io/myuser/mariadb-qa:latest
```

A new package on ghcr.io is private. To let colleagues pull it, open the package
page on GitHub and set the visibility, or give them a token with
`read:packages`.

## 5. Three kinds of update

| You want | Command | Effect |
|---|---|---|
| The latest framework | `qa-update`, or `./mariadb-qa update` | Pulls `mariadb-qa`, runs `linkit`, rebuilds a tool whose source changed |
| A newer compiler or newer MSAN libraries | `qa-upgrade`, or `./mariadb-qa upgrade` | Rebuilds clang from source and the MSAN instrumented libraries, in the running box. About an hour per part |
| A new image, with the newest packages | `./mariadb-qa build` then `push` | A fresh toolchain and a fresh framework clone, for everyone who pulls it |

`qa-update` covers daily work. `qa-upgrade` changes one box only, so a colleague
who pulls the image does not get it. Build and push a new image when the change
has to reach everybody.

## 6. Disk cleanup

```bash
docker builder prune        # Build cache, safe to drop
docker image prune          # Images with no tag
docker system df            # What uses the space
```

The mapped `/test` and `/data` are host directories, so Docker never removes
them. Use the framework tools for those: `dt` for one trial, `ca` for known
bugs, and `/data/VARIOUS_BUILDS/cleanup_builds_which_have_tar.sh` for builds
that have a saved tarball.
