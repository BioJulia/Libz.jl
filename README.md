
This is yet another zlib interface for Julia. There are two existing, and more
mature packages:

  * [GZip.jl](https://github.com/JuliaLang/GZip.jl)
  * [Zlib.jl](https://github.com/dcjones/Zlib.jl)

Both have shortcomings that this package aims to address, specifically:

  * Zlib.jl is very slow.
  * GZip.jl is not as slow as Zlib.jl, but still slower than it could to be.
  * GZip.jl only supports file I/O.
  * GZip.jl doesn't support reading/writing plain zlib data.

The goal of this package is to replace both of these as the one true Julia zlib
bindings.


# Preliminary benchmarks

See `perf/zlib-bench.jl`

*Writing*

| Zlib.jl | 50.14 seconds |
| GZip.jl | 13.29 seconds |
| Libz.jl | 13.23 seconds |

*Reading Lines*

| Zlib.jl          | 3.64 seconds |
| GZip.jl          | 1.34 seconds |
| GZBufferedStream | 2.44 seconds |
| Libz.jl          | 2.38 seconds |

*Reading Bytes*

| Zlib.jl          | 15.66 seconds |
| GZip.jl          |  5.10 seconds |
| GZBufferedStream |  0.45 seconds |
| Libz.jl          |  0.51 seconds |

