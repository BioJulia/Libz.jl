

using FactCheck, Libz, BufferedStreams


facts("Source") do
    function test_round_trip(data)
        return data == readbytes(data |> ZlibDeflateInputStream |> ZlibInflateInputStream)
    end

    @fact test_round_trip(UInt8[]) --> true
    @fact test_round_trip(rand(UInt8, 1)) --> true
    @fact test_round_trip(rand(UInt8, 1000000)) --> true
end


facts("Sink") do
    function test_round_trip(data)
        outbuf = BufferedOutputStream()
        stream = outbuf |> ZlibInflateOutputStream |> ZlibDeflateOutputStream
        write(stream, data)
        close(stream)
        return takebuf_array(outbuf) == data
    end

    @fact test_round_trip(UInt8[]) --> true
    @fact test_round_trip(rand(UInt8, 1)) --> true
    @fact test_round_trip(rand(UInt8, 1000000)) --> true
end


facts("Inflate/Deflate") do
    data = rand(UInt8, 100000)
    @fact Libz.inflate(Libz.deflate(data)) --> data
end



facts("Checksums") do
    # checking correctness isn't our job, just make sure they're usable
    data = rand(UInt8, 100000)

    c32 = crc32(data)
    @fact typeof(c32) --> UInt32

    a32 = adler32(data)
    @fact typeof(a32) --> UInt32

    @fact crc32(BufferedInputStream(IOBuffer(data), 1024)) --> c32
    @fact adler32(BufferedInputStream(IOBuffer(data), 1024)) --> a32
end


facts("Files") do

    testgz = joinpath(Pkg.dir("Libz"), "test/test.gz")
    @fact crc32(readgz(testgz)) --> 0x2b082899

    f = tempname() * ".gz"
    writegz(f, "Hello World!")
    @fact readgzstring(f) --> "Hello World!"
end
