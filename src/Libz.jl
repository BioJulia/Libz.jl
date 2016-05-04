

module Libz

using BufferedStreams, Compat

export ZlibInflateInputStream, ZlibDeflateInputStream,
       ZlibInflateOutputStream, ZlibDeflateOutputStream,
       gzopen, writegz, readgz, readgzstring,
       adler32, crc32


include("zlib_h.jl")
include("state.jl")
include("source.jl")
include("sink.jl")
include("checksums.jl")


function deflate(data::Vector{UInt8})
    return read(ZlibDeflateInputStream(data))
end

const compress = deflate


function inflate(data::Vector{UInt8})
    return read(ZlibInflateInputStream(data))
end

const decompress = inflate


function gzopen(f::Function, filename::AbstractString, mode)
    @assert mode == "w"
    open(filename, mode) do io
        zio = ZlibDeflateOutputStream(io)
        try f(zio)
        finally close(zio)
        end
    end
end

function gzopen(f::Function, filename::AbstractString)
    open(io->f(ZlibInflateInputStream(io)), filename)
end

writegz(filename::AbstractString, data) = gzopen(io->write(io, data), filename, "w")
readgz(filename::AbstractString) = gzopen(read, filename)
readgzstring(filename::AbstractString) = gzopen(readstring, filename)

end # module Libz
