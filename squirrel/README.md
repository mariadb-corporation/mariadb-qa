# Squirrel

<a href="https://arxiv.org/pdf/2006.02398.pdf"><img src="https://huhong789.github.io/images/squirrel.png" align="right" width="250"></a>

`Squirrel` is a fuzzer that aims at finding memory corruption issues in database managment systems (DBMSs). It is built on [AFL](https://github.com/google/AFL). More details can be found in our [CCS 2020 paper](http://arxiv.org/abs/2006.02398). And the bugs found by `Squirrel` can be found in [here](https://github.com/s3team/Squirrel/wiki/Bug-List).

Currently supported DBMSs:
1. SQLite
2. PostgreSQL
3. MySQL
4. MariaDB

## Build Instruction

Currently we test `Squirrel` on `Ubuntu 16` and `Ubuntu 18`.

1. `Prerequisites`:
    ```
    sudo apt-get -y update && apt-get -y upgrade
    sudo apt-get -y install gdb bison flex git make cmake build-essential gcc-multilib g++-multilib xinetd libreadline-dev zlib1g-dev
    sudo apt-get -y install clang libssl-dev libncurses5-dev

    # Compile AFL, which is used for instrumenting the DBMSs
    cd ~
    git clone https://github.com/google/AFL.git
    cd AFL
    sed -i  's/#define MAP_SIZE_POW2       16/#define MAP_SIZE_POW2       18/' config.h
    make
    cd llvm_mode/
    make
    ```

2. `DBMS-specific requirements:` Headers and libary of `MySQL`, `PostgreSQL` and `MariaDB` if you want to test them. The most direct way is to compile the DBMSs.

3. `Compile Squirrel:`
    ```
    git clone 
    cd Squirrel/DBNAME/AFL
    make afl-fuzz # You need to set the path in the Makefile
    ```

4. `Instrument DBMS:`
    ```
    # SQLite:
    git clone https://github.com/sqlite/sqlite.git
    cd sqlite
    mkdir bld
    cd bld
    CC=/path/to/afl-gcc CXX=/path/to/afl-g++ ../configure # You can also turn on debug flag if you want to find assertion
    make

    # MySQL/PostgreSQL/MariaDB
    cd Squirrel/DBNAME/docker/
    cp ../AFL/afl-fuzz .
    sudo docker build -t IMAGE_ID . 
   ```

## Run

```
# SQLite:
cd Squirrel/SQLite/fuzz_root
./afl-fuzz -i input -o output -- /path/to/sqlite3 --bail

# MySQL, PostgreSQL, MySQL, MariaDB
docker run -it IMAGE_ID bash
python run.py # wait for a few minutes
tmux a -t fuzzing
```

Since the `input` has been well-tested. It is more likely to find new bugs if you use your own seeds.


## Publications

```
SQUIRREL: Testing Database Management Systems with Language Validity and Coverage Feedback

@inproceedings{zhong:squirrel,
  title        = {{SQUIRREL: Testing Database Management Systems with Language Validity and Coverage Feedback}},
  author       = {Rui Zhong and Yongheng Chen and Hong Hu and Hangfan Zhang and Wenke Lee and Dinghao Wu},
  booktitle    = {Proceedings of the 27th ACM Conference on Computer and Communications Security (CCS)},
  month        = nov,
  year         = 2020,
  address      = {Orlando, USA},
}
```
