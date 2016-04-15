
"""
The `mode` type parameter should be either :inflate or :deflate.
"""
type Sink{mode,T<:BufferedOutputStream}
    output::T
    zstream::Base.RefValue{ZStream}
    zstream_end::Bool
end


# inflate sink constructors
# -------------------------

function InflateSink{T <: BufferedOutputStream}(output::T, gzip::Bool)
    sink = Sink{:inflate, T}(output, init_inflate_zstream(gzip), false)
    finalizer(sink, close)
    return sink
end


function InflateSink(output::BufferedOutputStream, bufsize::Int, gzip::Bool)
    return InflateSink(output, gzip)
end


function InflateSink(output::IO, bufsize::Int, gzip::Bool)
    output_stream = BufferedOutputStream(output, bufsize)
    return InflateSink(output_stream, gzip)
end


function InflateSink(output::Vector{UInt8}, bufsize::Int, gzip::Bool)
    return InflateSink(BufferedOutputStream(output), gzip)
end


"""
Open a zlib inflate output stream.

# Args
  * `output`: A byte vector, IO object, or BufferedInputStream to which
              decompressed data should be written.

# Named Args
  * `bufsize`: size of buffer in bytes
  * `gzip`: if true, data is gzip compressed, if false plain zlib compression

"""
function ZlibInflateOutputStream(output; bufsize::Int=8192, gzip::Bool=true)
    return BufferedOutputStream(InflateSink(output, bufsize, gzip), bufsize)
end


# deflate sink constructors
# -------------------------

function DeflateSink{T <: BufferedOutputStream}(
                    output::T, gzip::Bool, level::Int, mem_level::Int, strategy::Int)
    sink = Sink{:deflate, T}(output, init_deflate_stream(gzip, level, mem_level, strategy), false)
    finalizer(sink, close)
    return sink
end


function DeflateSink(output::BufferedOutputStream, bufsize::Int, gzip::Bool,
                       level::Int, mem_level::Int, strategy::Int)
    return DeflateSink(output, gzip, level, mem_level, strategy)
end


function DeflateSink(output::IO, bufsize::Int, gzip::Bool, level::Int,
                       mem_level::Int, strategy::Int)
    output_stream = BufferedOutputStream(output, bufsize)
    return DeflateSink(output_stream, gzip, level, mem_level, strategy)
end


function DeflateSink(output::Vector{UInt8}, bufsize::Int, gzip::Bool,
                       level::Int, mem_level::Int, strategy::Int)
    return DeflateSink(BufferedOutputStream(output), gzip, level, mem_level, strategy)
end


"""
Construct a zlib deflate output stream to compress gzip/zlib data.

# Args
  * `output`: A byte vector, IO object, or BufferedInputStream to which
              compressed data should be written.

# Named Args
  * `bufsize`: Input and output buffer size.
  * `gzip`: If true, write gzip header and trailer.
  * `level`: Compression level in 1-9
  * `mem_level`: Memory to use for compression in 1-9
  * `strategy`: Compression strategy. See zlib documentation.
"""
function ZlibDeflateOutputStream(output; bufsize::Int=8192, gzip::Bool=true,
                                 level=6, mem_level=8, strategy=Z_DEFAULT_STRATEGY)
    return BufferedOutputStream(DeflateSink(output, bufsize, gzip, Int(level),
                                            Int(mem_level), Int(strategy)), bufsize)
end


"""
Write some bytes from a given buffer. Satisfies the BufferedStreams sink
interface.
"""
function BufferedStreams.writebytes{mode}(sink::Sink{mode}, buffer::Vector{UInt8},
                                          n::Int, eof::Bool)
    zstream = getindex(sink.zstream)

    zstream.next_in = pointer(buffer)
    zstream.avail_in = n
    zstream.next_out = pointer(sink.output.buffer, sink.output.position)
    zstream.avail_out = length(sink.output.buffer) - sink.output.position + 1
    flushmode = eof ? Z_FINISH : Z_NO_FLUSH

    while zstream.avail_in > 0 || eof
        ret = ccall((mode, _zlib),
                    Cint, (Ptr{ZStream}, Cint),
                    sink.zstream, flushmode)

        if ret == Z_BUF_ERROR
            if zstream.avail_out == 0
                sink.output.position = length(sink.output.buffer) + 1
                flush(sink.output)
                zstream.next_out = pointer(sink.output.buffer, sink.output.position)
                zstream.avail_out = length(sink.output.buffer) - sink.output.position + 1
            else
                error("Buffer error during zlib compression.")
            end
        elseif eof && ret == Z_STREAM_END
            close(sink)
            break
        elseif ret != Z_OK
            error(string("zlib errror: ", ret))
        end
    end

    sink.output.position = length(sink.output.buffer) - zstream.avail_out + 1
    if eof && sink.zstream_end
        close(sink.output)
    end

    nb = n - zstream.avail_in
    return nb
end


function Base.close(sink::Sink{:inflate})
    if !sink.zstream_end
        sink.zstream_end = true
        ccall((:inflateEnd, _zlib), Cint, (Ptr{ZStream},), sink.zstream)
    end
end


function Base.close(sink::Sink{:deflate})
    if !sink.zstream_end
        sink.zstream_end = true
        ccall((:deflateEnd, _zlib), Cint, (Ptr{ZStream},), sink.zstream)
    end
end
