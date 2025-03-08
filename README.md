
# zig-cmake

integrating cmake directly into the Zig build system

## Why?

There are a lot of projects out there that make use of cmake to check the what the target is capable of to enable or disable various options.
Zig is still relatively new and doesn't provide a way of doing many of the checks that C projects have come to rely on, this project is a stop-gap solution that aims to build cmake and ninja locally, build a cmake project and then make the relevant information (include and library paths, linked libraries, C flags, etc.) available within the Zig build system.

This project took some inspiration from [someday](https://github.com/vspefs/someday-dev)

## How?
We invoke cmake directly with zig cc as the compiler and the `--trace` flag
this gives us a file of line separated json objects that contain every expanded step for us, enabling us to figure out how to build a cmake project without having to implement most of the logic ourselves.
 