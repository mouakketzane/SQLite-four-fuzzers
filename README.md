## What is this Repo

This repo compares Data Coverage fuzzers available

## Setup

Run this command to pull the submodules like sqlite
```bash
git submodule update --init --recursive
```

## How to build 

First make the build directory
```bash
mkdir build && cd build
```

```bash
cmake ..
```

```bash
make
```

This will build sqlite and wingfuzz all inside the build folder. Currently only sqlite builds