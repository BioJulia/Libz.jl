
# TODO:
#   * Is there any way to make ZlibInputStream seekable?
#   * Faster readline function like in GZip.jl
#   * ZlibOutputStream
#   * compress/decompress functions
#   * tests

module Libz

using Compat

export ZlibInputStream

include("zlib_h.jl")

type ZlibInputStream{T<:IO} <: IO
    stream::Base.RefValue{ZStream}
    input::T

    input_buffer::Vector{Uint8}
    output_buffer::Vector{Uint8}
    output_pos::Int
    output_avail::Int
    finished::Bool
end


"""
Construct a zlib input stream to decompress gzip/zlib data.

# Args
  * `input`: input stream containing compressed data.
  * `bufsize`: buffer size
  * `gzip`: If true, assume the input is in gzip format, if false, raw zlib.

"""
function ZlibInputStream{T<:IO}(input::T; bufsize::Int=8192, gzip::Bool=true)
    stream = Ref(ZStream())
    ret = ccall((:inflateInit2_, _zlib),
                Int32, (Ptr{ZStream}, Cint, Ptr{Uint8}, Int32),
                stream, gzip ? 32 + 15 : -15, zlib_version, sizeof(ZStream))
    if ret != Z_OK
        if ret == Z_MEM_ERROR
            error("Insufficient memory to allocate zlib stream.")
        elseif ret == Z_VERSION_ERROR
            error("Mismatching versions of zlib.")
        elseif ret == Z_STREAM_ERROR
            error("Invalid parameters for zlib stream initialiation.")
        end
        error("Error initializing zlib stream.")
    end
    zstream = ZlibInputStream{T}(stream, input,
                                 Array(Uint8, bufsize), Array(Uint8, bufsize),
                                 1, 0, false)
    finalizer(zstream, close)
    return zstream
end


# Refill zstream's output buffer. Should only be called when all available
# output has been consumed.
function fillbuffer!(zstream::ZlibInputStream)
    stream = getindex(zstream.stream)

    stream.next_out  = pointer(zstream.output_buffer)
    stream.avail_out = length(zstream.output_buffer)

    while stream.avail_out > 0
        if stream.avail_in == 0
            nb = readbytes!(zstream.input, zstream.input_buffer,
                            length(zstream.input_buffer))
            if nb == 0
                break
            end
            stream.next_in  = pointer(zstream.input_buffer)
            stream.avail_in = nb
        end

        ret = ccall((:inflate, _zlib),
                    Int32, (Ptr{ZStream}, Int32),
                    zstream.stream, Z_NO_FLUSH)

        if ret == Z_FINISH
            break
        elseif ret == Z_STREAM_END
            zstream.finished = true
            break
        elseif ret != Z_OK
            error(ret)
        end
    end

    zstream.output_pos = 1
    zstream.output_avail = length(zstream.output_buffer) - stream.avail_out
    return zstream.output_avail
end


@inline function Base.read(zstream::ZlibInputStream, ::Type{UInt8})
    output_pos = zstream.output_pos
    if output_pos > zstream.output_avail
        if fillbuffer!(zstream) < 1
            throw(EOFError())
        end
        output_pos = zstream.output_pos
    end
    @inbounds c = zstream.output_buffer[output_pos]
    zstream.output_pos = output_pos + 1
    return c
end


function Base.readbytes!(zstream::ZlibInputStream,
                         b::AbstractArray{Uint8}, nb=length(b))
    olb = lb = length(b)
    outpos = 1
    while !eof(zstream)
        if zstream.output_pos > zstream.output_avail && fillbuffer!(zstream) < 1
            throw(EOFError())
        end

        if outpos > length(b)
            lb = 2 * (1+length(b))
            resize!(b, lb)
        end

        num_chunk_bytes = min(zstream.output_avail - zstream.output_pos + 1,
                              length(b) - outpos + 1)
        copy!(b, outpos, zstream.output_buffer, zstream.output_pos, num_chunk_bytes)
        zstream.output_pos += num_chunk_bytes
        outpos += num_chunk_bytes
    end

    if lb > olb
        resize!(b, outpos - 1)
    end

    return outpos - 1
end


@inline function Base.eof(zstream::ZlibInputStream)
    return zstream.finished && zstream.output_pos > zstream.output_avail
end


function Base.close(zstream::ZlibInputStream)
    zstream.finished = true
    ccall((:inflateEnd, _zlib), Cint, (Ptr{ZStream},), zstream.stream)
end

end # module Libz
