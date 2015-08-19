


"""
The `M` type parameter should be either :inflate or :deflate
"""
type ZlibSource{M, T <: BufferedInputStream}
    input::T
    zstream::Base.RefValue{ZStream}
    zstream_end::Bool
end


# inflate source constructors
# ---------------------------

function ZlibInflateSource{T <: BufferedInputStream}(input::T, gzip::Bool)
    source = ZlibSource{:inflate, T}(input, init_inflate_zstream(gzip), false)
    finalizer(source, close)
    return source
end


function ZlibInflateSource(input::BufferedInputStream, bufsize::Int, gzip::Bool)
    return ZlibInflateSource(input, gzip)
end


function ZlibInflateSource(input::IO, bufsize::Int, gzip::Bool)
    input_stream = BufferedInputStream(input, bufsize)
    return ZlibInflateSource(input_stream, gzip)
end


function ZlibInflateSource(input::Vector{UInt8}, bufsize::Int, gzip::Bool)
    return ZlibInflateSource(BufferedInputStream(input), gzip)
end


function ZlibInflateInputStream(input; bufsize::Int=8192, gzip::Bool=true)
    return BufferedInputStream(ZlibInflateSource(input, bufsize, gzip), bufsize)
end


# deflate source constructors
# ---------------------------

function ZlibDeflateSource{T <: BufferedInputStream}(
                    input::T, gzip::Bool, level::Int, mem_level::Int, strategy::Int)
    source = ZlibSource{:deflate, T}(input, init_deflate_stream(gzip, level, mem_level, strategy))
    finalizer(source, close)
    return source
end


function ZlibDeflateSource(input::BufferedInputStream, bufsize::Int, gzip::Bool,
                           level::Int, mem_level::Int, strategy::Int)
    return ZlibDeflateSource(input, gzip, level, mem_level, strategy)
end


function ZlibDeflateSource(input::IO, bufsize::Int, gzip::Bool, level::Int,
                            mem_level::Int, strategy::Int)
    input_stream = BufferedInputStream(input, bufsize)
    return ZlibDeflateSource(input_stream, gzip, level, mem_level, strategy)
end


function ZlibDeflateSource(input::Vector{UInt8}, bufsize::Int, gzip::Bool,
                           level::Int, mem_level::Int, strategy::Int)
    return ZlibDeflateSource{BufferedInputStream{EmptyStreamSource}}(
        BufferedInputStream(input), gzip, level, mem_level, strategy)
end


function ZlibDeflatInputStream(input; bufsize::Int=8192, gzip::Bool=true,
                               level=6, mem_level=8, strategy=Z_DEFAULT_STRATEGY)
    return BufferedInputStream(ZlibDeflateSource(input, bufsize, gzip, level,
                                                  mem_level, strategy), bufsize)
end


"""
Read bytes from the zlib stream to a buffer. Satisfies the BufferedStreams source interface.
"""
function Base.readbytes!{M}(source::ZlibSource{M}, buffer::Vector{UInt8},
                            from::Int, to::Int)
    if source.zstream_end
    end

    zstream = getindex(source.zstream)
    input = source.input
    zstream.next_out  = pointer(buffer, from)
    zstream.avail_out = to - from + 1

    while zstream.avail_out > 0
        if zstream.avail_in == 0
            if input.position > input.available
                nb = fillbuffer!(input)
                if nb == 0
                    break
                end
            end

            zstream.next_in = pointer(input.buffer, input.position)
            zstream.avail_in = input.available - input.position + 1

            # advance to the end and let zlib keep track of what's used
            input.position = input.available + 1
        end

        ret = ccall((M, _zlib),
                    Cint, (Ptr{ZStream}, Cint),
                    source.zstream, Z_NO_FLUSH)

        if ret == Z_FINISH
            break
        elseif ret == Z_STREAM_END
            close(source)
            break
        elseif ret != Z_OK
            if ret == Z_DATA_ERROR
                error("Input is not zlib compressed data.")
            else
                error(string("zlib errror: ", ret))
            end
        end
    end

    return (to - from + 1) - zstream.avail_out
end


@inline function Base.eof(source::ZlibSource)
    return source.zstream_end
end


function Base.close(source::ZlibSource{:inflate})
    if !source.zstream_end
        source.zstream_end = true
        ccall((:inflateEnd, _zlib), Cint, (Ptr{ZStream},), source.zstream)
    end
end


function Base.close(source::ZlibSource{:deflate})
    if !source.zstream_end
        source.zstream_end = true
        ccall((:deflateEnd, _zlib), Cint, (Ptr{ZStream},), source.zstream)
    end
end


