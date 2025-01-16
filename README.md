
# zig-cmake

integrating cmake directly into the Zig build system

## Why?

There are a lot of projects out there that make use of cmake to check the what the target is capable of to enable or disable various options.
Zig is still relatively new and doesn't provide a way of doing many of the checks that C projects have come to rely on, this project is a stop-gap solution that aims to build cmake and ninja locally, build a cmake project and then make the relevant information (include and library paths, linked libraries, C flags, etc.) available within the Zig build system.

This project took some inspiration from [someday](https://github.com/vspefs/someday-dev)
