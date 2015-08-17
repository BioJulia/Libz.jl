
# TODO:
#   * write(s::ZlibOutputStream, ::Ptr, ::Integer)
#   * seekable ZlibInputStream
#   * faster readline function like in GZip.jl
#   * compress/decompress functions
#   * adler32, crc32
#   * tests

module Libz

using Compat, BufferedStreams

export ZlibInputStream, ZlibOutputStream

include("zlib_h.jl")


type ZlibInputStreamSource{T <: IO}
    input::BufferedInputStream{T}
    zstream::Base.RefValue{ZStream}
    zstream_end::Bool

    function ZlibInputStreamSource(input::T, bufsize::Int, gzip::Bool)
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
        source = new(BufferedInputStream(input), zstream, false)
        finalizer(source, close)
        return source
    end
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


function Base.eof(source::ZlibInputStreamSource)
    return source.zstream_end
end


function Base.close(source::ZlibInputStreamSource)
    ccall((:inflateEnd, _zlib), Cint, (Ptr{ZStream},), source.zstream)
end


function ZlibInputStream{T <: IO}(input::T; bufsize::Int=8192, gzip::Bool=true)
    return BufferedInputStream(ZlibInputStreamSource{T}(input, bufsize, gzip))
end



#function Base.readbytes!(zstream::ZlibInputStream,
                         #b::AbstractArray{Uint8}, nb=length(b))
    #olb = lb = length(b)
    #outpos = 1
    #while !eof(zstream)
        #if zstream.output_pos > zstream.output_avail && fillbuffer!(zstream) < 1
            #throw(EOFError())
        #end

        #if outpos > length(b)
            #lb = 2 * (1+length(b))
            #resize!(b, lb)
        #end

        #num_chunk_bytes = min(zstream.output_avail - zstream.output_pos + 1,
                              #length(b) - outpos + 1)
        #copy!(b, outpos, zstream.output_buffer, zstream.output_pos, num_chunk_bytes)
        #zstream.output_pos += num_chunk_bytes
        #outpos += num_chunk_bytes
    #end

    #if lb > olb
        #resize!(b, outpos - 1)
    #end

    #return outpos - 1
#end



# ZlibOutputStream
# ----------------

type ZlibOutputStream{T<:IO} <: IO
    stream::Base.RefValue{ZStream}
    output::T

    output_buffer::Vector{Uint8}
    input_buffer::Vector{Uint8}
    input_pos::Int
    finished::Bool
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
function ZlibOutputStream{T<:IO}(output::T; gzip::Bool=true, level=6,
                                 mem_level=8, strategy=Z_DEFAULT_STRATEGY,
                                 bufsize=8192)
                             
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

    stream = Ref(ZStream())
    window_bits = gzip ? 16 + 15 : 15
    # TODO: when gzip is true, it will write a "simple" gzip header/trailer that
    # doesn't include a filename, modification time, etc. We may want to support
    # that.
    ret = ccall((:deflateInit2_, _zlib),
                Cint, (Ptr{ZStream}, Cint, Cint, Cint, Cint, Cint, Ptr{Cchar}, Cint),
                stream, level, Z_DEFLATED, window_bits, mem_level, strategy,
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
    zstream = ZlibOutputStream{T}(stream, output, Array(Uint8, bufsize),
                                  Array(Uint8, bufsize), 1, false)

    getindex(zstream.stream).avail_out = bufsize
    getindex(zstream.stream).next_out = pointer(zstream.output_buffer)

    finalizer(zstream, close)
    return zstream
end


function flushbuffer!(zstream::ZlibOutputStream, flushvalue::Cint=Z_NO_FLUSH)
    stream = getindex(zstream.stream)

    stream.next_in = pointer(zstream.input_buffer)
    stream.avail_in = zstream.input_pos - 1

    while stream.avail_in > 0 || flushvalue == Z_FINISH
        ret = ccall((:deflate, _zlib),
                    Cint, (Ptr{ZStream}, Cint),
                    zstream.stream, flushvalue)

        if ret == Z_BUF_ERROR
            if stream.avail_out == 0
                write(zstream.output, pointer(zstream.output_buffer),
                      length(zstream.output_buffer))
                stream.next_out = pointer(zstream.output_buffer)
                stream.avail_out = length(zstream.output_buffer)
            else
                error("Buffer error during zlib compression.")
            end
        elseif flushvalue == Z_FINISH && ret == Z_STREAM_END
            write(zstream.output, pointer(zstream.output_buffer),
                  length(zstream.output_buffer) - stream.avail_out)

            ret = ccall((:deflateEnd, _zlib), Cint, (Ptr{ZStream},), zstream.stream)
            if ret != Z_OK
                error(string("Unable to close zlib stream: ", ret))
            end

            zstream.finished = true
            break
        elseif ret != Z_OK
            error(string("zlib errror: ", ret))
        end
    end

    nb = zstream.input_pos - (stream.avail_in + 1) # number of bytes flushed
    zstream.input_pos = 1
    return nb
end


@inline function Base.write(zstream::ZlibOutputStream, b::Uint8)
    if zstream.input_pos > length(zstream.input_buffer)
        flushbuffer!(zstream)
    end
    zstream.input_buffer[zstream.input_pos] = b
    zstream.input_pos += 1
    return 1
end


function Base.flush(zstream::ZlibOutputStream)
    if !zstream.finished
        flushbuffer!(zstream, Z_FINISH)
    end
end


function Base.close(zstream::ZlibOutputStream)
    flush(zstream)
end


end # module Libz
