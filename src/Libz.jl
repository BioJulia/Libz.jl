
# TODO:
#   * seekable ZlibInputStream
#   * compress/decompress functions
#   * tests

module Libz

using BufferedStreams, Compat

export ZlibInputStream, ZlibOutputStream, adler32, crc32

include("zlib_h.jl")
include("checksums.jl")


type ZlibInputStreamSource{T <: BufferedInputStream}
    input::T
    zstream::Base.RefValue{ZStream}
    zstream_end::Bool

    function ZlibInputStreamSource(input_stream::T, gzip::Bool)
        zstream = Ref(ZStream())
        ret = ccall((:inflateInit2_, _zlib),
        Cint, (Ptr{ZStream}, Cint, Ptr{Cchar}, Cint),
        zstream, gzip ? 32 + 15 : -15, zlib_version, sizeof(ZStream))
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

        source = new(input_stream, zstream, false)
        finalizer(source, close)
        return source
    end

end

function ZlibInputStreamSource(input::IO, bufsize::Int, gzip::Bool)
    input_stream = BufferedInputStream(input, bufsize)
    return ZlibInputStreamSource(input_stream, bufsize, gzip)
end


function ZlibInputStreamSource{T <: BufferedInputStream}(input::T, bufsize::Int, gzip::Bool)
    return ZlibInputStreamSource{T}(input, gzip)
end


function ZlibInputStreamSource(input::Vector{UInt8}, bufsize::Int, gzip::Bool)
    return ZlibInputStreamSource{BufferedInputStream{EmptyStreamSource}}(BufferedInputStream(input),  gzip)
end


function Base.readbytes!(source::ZlibInputStreamSource, buffer::Vector{UInt8},
                         from::Int, to::Int)
    if source.zstream_end
        return 0
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

        ret = ccall((:inflate, _zlib),
                    Cint, (Ptr{ZStream}, Cint),
                    source.zstream, Z_NO_FLUSH)

        if ret == Z_FINISH
            break
        elseif ret == Z_STREAM_END
            source.zstream_end = true
            break
        elseif ret != Z_OK
            if ret == Z_DATA_ERROR
                error("Input is not zlib compressed data.")
            else
                error(string("zlib errror: ", ret))
            end
        end
    end

    nb = (to - from + 1) - zstream.avail_out
    return (to - from + 1) - zstream.avail_out
end


@inline function Base.eof(source::ZlibInputStreamSource)
    return source.zstream_end
end


function Base.close(source::ZlibInputStreamSource)
    return ccall((:inflateEnd, _zlib), Cint, (Ptr{ZStream},), source.zstream)
end


function ZlibInputStream(input; bufsize::Int=8192, gzip::Bool=true)
    return BufferedInputStream(ZlibInputStreamSource(input, bufsize, gzip))
end


# ZlibOutputStream
# ----------------

type ZlibOutputStreamSink{T <: BufferedOutputStream}
    output::T
    zstream::Base.RefValue{ZStream}
    zstream_end::Bool

    function ZlibOutputStreamSink(output::T, gzip::Bool, level::Int,
                                  mem_level::Int, strategy::Int)
        if !(1 <= level <= 9)
            error("Invalid zlib compression level.")
        end

        if !(1 <= mem_level <= 9)
            error("Invalid zlib memory level.")
        end

        if strategy != Z_DEFAULT_STRATEGY &&
            strategy != Z_FILTERED &&
            strategy != Z_HUFFMAN_ONLY &&
            strategy != Z_RLE &&
            strategy != Z_FIXED
            error("Invalid zlib strategy.")
        end

        zstream = Ref(ZStream())
        window_bits = gzip ? 16 + 15 : 15
        # TODO: when gzip is true, it will write a "simple" gzip header/trailer that
        # doesn't include a filename, modification time, etc. We may want to support
        # that.
        ret = ccall((:deflateInit2_, _zlib),
                    Cint, (Ptr{ZStream}, Cint, Cint, Cint, Cint, Cint, Ptr{Cchar}, Cint),
                    zstream, level, Z_DEFLATED, window_bits, mem_level, strategy,
                    zlib_version, sizeof(ZStream))
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

        sink = new(output, zstream, false)

        # TODO: free the ZStream if it hasn't been already
        #finalizer(sink, close)
    end
end


function ZlibOutputStreamSink(output::IO, bufsize::Int, gzip::Bool,
                              level::Int, mem_level::Int, strategy::Int)
    output_stream = BufferedOutputStream(output, bufsize)
    return ZlibOutputStreamSink(output_stream, bufsize, gzip, level, mem_level, strategy)
end


function ZlibOutputStreamSink{T <: BufferedOutputStream}(
                            output::T, bufsize::Int, gzip::Bool,
                            level::Int, mem_level::Int, strategy::Int)
    return ZlibOutputStreamSink{T}(output, gzip, level, mem_level, strategy)
end


function ZlibOutputStreamSink(output::Vector{UInt8}, bufsize::Int, gzip::Bool,
                              level::Int, mem_level::Int, strategy::Int)
    return ZlibOutputStreamSink{BufferedOutputStream{EmptyStreamSink}}(
                BufferedOutputStream(output), gzip, level, mem_level, strategy)
end


function BufferedStreams.writebytes(sink::ZlibOutputStreamSink,
                                    buffer::Vector{UInt8}, n::Int, eof::Bool)
    zstream = getindex(sink.zstream)

    zstream.next_in = pointer(buffer)
    zstream.avail_in = n
    zstream.next_out = pointer(sink.output.buffer, sink.output.position)
    zstream.avail_out = length(sink.output.buffer) - sink.output.position + 1
    flushmode = eof ? Z_FINISH : Z_NO_FLUSH

    while zstream.avail_in > 0 || eof
        ret = ccall((:deflate, _zlib),
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
            flush(sink.output)

            ret = ccall((:deflateEnd, _zlib), Cint, (Ptr{ZStream},), sink.zstream)
            if ret != Z_OK
                error(string("Unable to close zlib stream: ", ret))
            end

            sink.zstream_end = true
            break
        elseif ret != Z_OK
            error(string("zlib errror: ", ret))
        end
    end

    sink.output.position = length(sink.output.buffer) - zstream.avail_out + 1
    nb = n - zstream.avail_in
    return nb
end


"""
Construct a zlib output stream to compress gzip/zlib data.

# Args
  * `output`: Output stream to write compressed data to.
  * `gzip`: If true, write gzip header and trailer.
  * `level`: Compression level in 1-9
  * `mem_level`: Memory to use for compression in 1-9
  * `strategy`: Compression strategy. See zlib documentation.
  * `bufsize`: Input and output buffer size.

"""
function ZlibOutputStream(input; bufsize::Int=10000, gzip::Bool=true,
                          level=6, mem_level=8, strategy=Z_DEFAULT_STRATEGY)
    return BufferedOutputStream(
        ZlibOutputStreamSink(input, Int(bufsize), gzip, Int(level),
                             Int(mem_level), Int(strategy)), bufsize)
end


end # module Libz


