


"""
The `M` type parameter should be either :inflate or :deflate
"""
type Source{M, T <: BufferedInputStream}
    input::T
    zstream::Base.RefValue{ZStream}
    zstream_end::Bool
end


# inflate source constructors
# ---------------------------

function InflateSource{T <: BufferedInputStream}(input::T, gzip::Bool)
    source = Source{:inflate, T}(input, init_inflate_zstream(gzip), false)
    finalizer(source, close)
    return source
end


function InflateSource(input::BufferedInputStream, bufsize::Int, gzip::Bool)
    return InflateSource(input, gzip)
end


function InflateSource(input::IO, bufsize::Int, gzip::Bool)
    input_stream = BufferedInputStream(input, bufsize)
    return InflateSource(input_stream, gzip)
end


function InflateSource(input::Vector{UInt8}, bufsize::Int, gzip::Bool)
    return InflateSource(BufferedInputStream(input), gzip)
end


"""
Open a zlib inflate input stream.

# Args
  * `input`: A byte vector, IO object, or BufferedInputStream containing
            compressed data to inflate.

# Named Args
  * `bufsize`: size of buffer in bytes
  * `gzip`: if true, data is gzip compressed, if false plain zlib compression

"""
function ZlibInflateInputStream(input; bufsize::Int=8192, gzip::Bool=true)
    return BufferedInputStream(InflateSource(input, bufsize, gzip), bufsize)
end


# deflate source constructors
# ---------------------------

function DeflateSource{T <: BufferedInputStream}(
                    input::T, gzip::Bool, level::Int, mem_level::Int, strategy::Int)
    source = Source{:deflate, T}(input, init_deflate_stream(gzip, level, mem_level, strategy), false)
    finalizer(source, close)
    return source
end


function DeflateSource(input::BufferedInputStream, bufsize::Int, gzip::Bool,
                       level::Int, mem_level::Int, strategy::Int)
    return DeflateSource(input, gzip, level, mem_level, strategy)
end


function DeflateSource(input::IO, bufsize::Int, gzip::Bool, level::Int,
                       mem_level::Int, strategy::Int)
    input_stream = BufferedInputStream(input, bufsize)
    return DeflateSource(input_stream, gzip, level, mem_level, strategy)
end


function DeflateSource(input::Vector{UInt8}, bufsize::Int, gzip::Bool,
                       level::Int, mem_level::Int, strategy::Int)
    return DeflateSource(BufferedInputStream(input), gzip, level, mem_level, strategy)
end


# TODO: docs
"""
"""
function ZlibDeflateInputStream(input; bufsize::Int=8192, gzip::Bool=true,
                                level=6, mem_level=8, strategy=Z_DEFAULT_STRATEGY)
    return BufferedInputStream(DeflateSource(input, bufsize, gzip, Int(level),
                                             Int(mem_level), Int(strategy)), bufsize)
end


"""
Read bytes from the zlib stream to a buffer. Satisfies the BufferedStreams source interface.
"""
function Base.readbytes!{M}(source::Source{M}, buffer::Vector{UInt8},
                            from::Int, to::Int)
    if source.zstream_end
        return 0
    end

    zstream = getindex(source.zstream)
    input = source.input
    zstream.next_out  = pointer(buffer, from)
    zstream.avail_out = to - from + 1
    flushmode = Z_NO_FLUSH

    while zstream.avail_out > 0
        if zstream.avail_in == 0
            if input.position > input.available
                nb = fillbuffer!(input)
                if nb == 0
                    flushmode = Z_FINISH
                end
            end

            zstream.next_in = pointer(input.buffer, input.position)
            zstream.avail_in = input.available - input.position + 1

            # advance to the end and let zlib keep track of what's used
            input.position = input.available + 1
        end

        ret = ccall((M, _zlib),
                    Cint, (Ptr{ZStream}, Cint),
                    source.zstream, flushmode)

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


@inline function Base.eof(source::Source)
    return source.zstream_end
end


function Base.close(source::Source{:inflate})
    if !source.zstream_end
        source.zstream_end = true
        ccall((:inflateEnd, _zlib), Cint, (Ptr{ZStream},), source.zstream)
    end
end


function Base.close(source::Source{:deflate})
    if !source.zstream_end
        source.zstream_end = true
        ccall((:deflateEnd, _zlib), Cint, (Ptr{ZStream},), source.zstream)
    end
end


