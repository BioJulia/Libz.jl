
function _crc32(crc::Uint, data::Ptr{UInt8}, n::Int)
    return ccall((:crc32, _zlib), Culong, (Culong, Ptr{Cchar}, Cuint), crc, data, n)
end


function _crc32()
    return ccall((:crc32, _zlib), Culong, (Culong, Ptr{Void}, Cuint), 0, C_NULL, 0)
end


"""
Compute the CRC-32 checksum over an input stream.
"""
function crc32(stream::BufferedInputStream)
    crc = _crc32()
    while !eof(stream)
        crc = _crc32(crc, pointer(stream.buffer), stream.available)
        stream.position = 1
        stream.available = 0
        BufferedStreams.fillbuffer!(stream)
    end
    return UInt32(crc)
end


"""
Compute the CRC-32 checksum over a byte array.
"""
function crc32(data::Vector{UInt8})
    return UInt32(_crc32(_crc32(), pointer(data), length(data)))
end


function _adler32(adler::Uint, data::Ptr{UInt8}, n::Int)
    return ccall((:adler32, _zlib), Culong, (Culong, Ptr{Cchar}, Cuint), adler, data, n)
end


function _adler32()
    return ccall((:adler32, _zlib), Culong, (Culong, Ptr{Void}, Cuint), 0, C_NULL, 0)
end


"""
Compute the Adler-32 checksum over an input stream.
"""
function adler32(stream::BufferedInputStream)
    adler = _adler32()
    while !eof(stream)
        adler = _adler32(adler, pointer(stream.buffer), stream.available)
        stream.position = 1
        stream.available = 0
        BufferedStreams.fillbuffer!(stream)
    end
    return UInt32(adler)
end


"""
Compute the Adler-32 checksum over a byte array.
"""
function adler32(data::Vector{UInt8})
    return UInt32(_adler32(_adler32(), pointer(data), length(data)))
end


