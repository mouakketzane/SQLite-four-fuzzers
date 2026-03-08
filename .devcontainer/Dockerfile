# Install Ubuntu since it provides a easy access to cclang
FROM ubuntu:22.04

# Install  dependencies
RUN apt-get update && apt-get install -y \
    wget gnupg software-properties-common cmake \
    git build-essential python3 zlib1g-dev

# Add LLVM 13 Official Repository & Install
RUN wget https://apt.llvm.org/llvm.sh && \
    chmod +x llvm.sh && \
    ./llvm.sh 13 all

# Set Environment Variables to point to Clang 13
ENV LLVM_DIR=/usr/lib/llvm-13
ENV PATH="${LLVM_DIR}/bin:${PATH}"
ENV CC=clang-13
ENV CXX=clang++-13

# Clone Binutils (Only if Wingfuzz specifically needs the Gold headers)
#RUN git clone --depth 1 git://sourceware.org/git/binutils-gdb.git /home/vscode/binutils

WORKDIR /home/vscode