# general zlib constants, definitions

@unix_only    const _zlib = "libz"
@windows_only const _zlib = "zlib1"

# Constants

zlib_version = bytestring(ccall((:zlibVersion, _zlib), Ptr{UInt8}, ()))
ZLIB_VERSION = tuple([parse(Int, c) for c in split(zlib_version, '.')]...)

# Flush values
const Z_NO_FLUSH       = @compat Int32(0)
const Z_PARTIAL_FLUSH  = @compat Int32(1)
const Z_SYNC_FLUSH     = @compat Int32(2)
const Z_FULL_FLUSH     = @compat Int32(3)
const Z_FINISH         = @compat Int32(4)
const Z_BLOCK          = @compat Int32(5)
const Z_TREES          = @compat Int32(6)

# Return codes
const Z_OK             = @compat Int32(0)
const Z_STREAM_END     = @compat Int32(1)
const Z_NEED_DICT      = @compat Int32(2)
const Z_ERRNO          = @compat Int32(-1)
const Z_STREAM_ERROR   = @compat Int32(-2)
const Z_DATA_ERROR     = @compat Int32(-3)
const Z_MEM_ERROR      = @compat Int32(-4)
const Z_BUF_ERROR      = @compat Int32(-5)
const Z_VERSION_ERROR  = @compat Int32(-6)


# Zlib errors as Exceptions
zerror(e::Integer) = bytestring(ccall((:zError, _zlib), Ptr{UInt8}, (Int32,), e))
type ZError <: Exception
    err::Int32
    err_str::String

    ZError(e::Integer) = (e == Z_ERRNO ? new(e, strerror()) : new(e, zerror(e)))
end

# Compression Levels
const Z_NO_COMPRESSION      = @compat Int32(0)
const Z_BEST_SPEED          = @compat Int32(1)
const Z_BEST_COMPRESSION    = @compat Int32(9)
const Z_DEFAULT_COMPRESSION = @compat Int32(-1)

# Compression Strategy
const Z_FILTERED             = @compat Int32(1)
const Z_HUFFMAN_ONLY         = @compat Int32(2)
const Z_RLE                  = @compat Int32(3)
const Z_FIXED                = @compat Int32(4)
const Z_DEFAULT_STRATEGY     = @compat Int32(0)

# data_type field
const Z_BINARY    = @compat Int32(0)
const Z_TEXT      = @compat Int32(1)
const Z_ASCII     = Z_TEXT
const Z_UNKNOWN   = @compat Int32(2)

# deflate compression method
const Z_DEFLATED    = @compat Int32(8)

# misc
const Z_NULL   = C_NULL

# Constants for use with gzbuffer
const Z_DEFAULT_BUFSIZE = 8192
const Z_BIG_BUFSIZE = 131072

# Constants for use with gzseek
const SEEK_SET = @compat Int32(0)
const SEEK_CUR = @compat Int32(1)

# Create ZFileOffset alias
# This is usually the same as FileOffset,
# unless we're on a 32-bit system and
# 64-bit functions are not available

# Get compile-time option flags
zlib_compile_flags = ccall((:zlibCompileFlags, _zlib), UInt, ())

let _zlib_h = Libdl.dlopen(_zlib)
    global ZFileOffset

    z_off_t_sz   = 2 << ((zlib_compile_flags >> 6) & @compat(UInt(3)))
    if z_off_t_sz == sizeof(FileOffset) ||
       (sizeof(FileOffset) == 8 && Libdl.dlsym_e(_zlib_h, :gzopen64) != C_NULL)
        typealias ZFileOffset FileOffset
    elseif z_off_t_sz == 4      # 64-bit functions not available
        typealias ZFileOffset Int32
    else
        error("Can't figure out what to do with ZFileOffset.  sizeof(z_off_t) = ", z_off_t_sz)
    end
end


# The zlib z_stream structure.
type ZStream
    next_in::Ptr{Uint8}
    avail_in::Cuint
    total_in::Culong

    next_out::Ptr{Uint8}
    avail_out::Cuint
    total_out::Culong

    msg::Ptr{Uint8}
    state::Ptr{Void}

    zalloc::Ptr{Void}
    zfree::Ptr{Void}
    opaque::Ptr{Void}

    data_type::Cint
    adler::Culong
    reserved::Culong

    function ZStream()
        strm = new()
        strm.next_in   = C_NULL
        strm.avail_in  = 0
        strm.total_in  = 0
        strm.next_out  = C_NULL
        strm.avail_out = 0
        strm.total_out = 0
        strm.msg       = C_NULL
        strm.state     = C_NULL
        strm.zalloc    = C_NULL
        strm.zfree     = C_NULL
        strm.opaque    = C_NULL
        strm.data_type = 0
        strm.adler     = 0
        strm.reserved  = 0
        return strm
    end
end


"""
Initialize a ZStream for inflation.
"""
function init_inflate_zstream(gzip::Bool)
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

    return zstream
end


"""
Initialize a ZStream for deflation.
"""
function init_deflate_stream(gzip::Bool, level::Int, mem_level::Int,
                             strategy::Int)
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

   return zstream
end


