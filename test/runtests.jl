using Libz, BufferedStreams, Compat

if VERSION >= v"0.5-"
    using Base.Test
else
    using BaseTestNext
    const Test = BaseTestNext
end

@testset "Source" begin
    function test_round_trip(data)
        return data == readbytes(data |> ZlibDeflateInputStream |> ZlibInflateInputStream)
    end

    @test test_round_trip(UInt8[])
    @test test_round_trip(rand(UInt8, 1))
    @test test_round_trip(rand(UInt8, 1000000))
end

@testset "Sink" begin
    function test_round_trip(data)
        outbuf = BufferedOutputStream()
        stream = outbuf |> ZlibInflateOutputStream |> ZlibDeflateOutputStream
        write(stream, data)
        close(stream)
        return takebuf_array(outbuf) == data
    end

    @test test_round_trip(UInt8[])
    @test test_round_trip(rand(UInt8, 1))
    @test test_round_trip(rand(UInt8, 1000000))
end

@testset "Inflate/Deflate" begin
    data = rand(UInt8, 100000)
    @test Libz.inflate(Libz.deflate(data)) == data
end

@testset "Checksums" begin
    # checking correctness isn't our job, just make sure they're usable
    data = rand(UInt8, 100000)

    c32 = crc32(data)
    @test isa(c32, UInt32)

    a32 = adler32(data)
    @test isa(a32, UInt32)

    @test crc32(BufferedInputStream(IOBuffer(data), 1024)) == c32
    @test adler32(BufferedInputStream(IOBuffer(data), 1024)) == a32
end


@testset "Files" begin

    testgz = joinpath(Pkg.dir("Libz"), "test/test.gz")
    @test crc32(readgz(testgz)) === 0x2b082899

    f = tempname() * ".gz"
    writegz(f, "Hello World!")
    @test readgzstring(f) == "Hello World!"
end

@testset "Concatenated gzip files" begin
    filepath = Pkg.dir("Libz", "test", "foobar.txt.gz")
    s = readstring(open(filepath) |> ZlibInflateInputStream)
    @test s == "foo\nbar\n"
end
