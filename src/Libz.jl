

module Libz

using BufferedStreams

export ZlibInflateInputStream, ZlibDeflateInputStream,
       ZlibInflateOutputStream, ZlibDeflateOutputStream,
       gzopen, gzwrite, gzreadbytes, gzreadall,
       adler32, crc32


include("zlib_h.jl")
include("source.jl")
include("sink.jl")
include("checksums.jl")


function deflate(data::Vector{UInt8})
    return readbytes(ZlibDeflateOutputStream(data))
end

const compress = deflate


function inflate(data::Vector{UInt8})
    return readbytes(ZlibInflateOutputStream(data))
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
readgz(filename::AbstractString) = gzopen(readbytes, filename)
readgzstring(filename::AbstractString) = gzopen(readall, filename)

end # module Libz


