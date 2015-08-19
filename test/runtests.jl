

using FactCheck, Libz, BufferedStreams


#facts("Compression/Decompression round trip") do
    #function test_round_trip(data)
        #outbuf = BufferedOutputStream()
        #outstream = ZlibOutputStream(outbuf)
        #write(outstream, data)
        #close(outstream)
        #compressed_data = takebuf_array(outbuf)

        #instream = ZlibInputStream(BufferedInputStream(compressed_data))
        #readbytes(instream) == data
    #end

    #@fact test_round_trip(UInt8[]) --> true
    #@fact test_round_trip(rand(UInt8, 1)) --> true
    #@fact test_round_trip(rand(UInt8, 1000000)) --> true
#end


#facts("Source") do
    #function test_round_trip(data)
        #outbuf = BufferedOutputStream()
        #outstream = ZlibDeflateOutputStream(outbuf)
        #write(outstream, data)
        #close(outstream)
        #compressed_data = takebuf_array(outbuf)

        #instream = ZlibInflateInputStream(BufferedInputStream(compressed_data))
        #readbytes(instream) == data
    #end

    #@fact test_round_trip(UInt8[]) --> true
    #@fact test_round_trip(rand(UInt8, 1)) --> true
    #@fact test_round_trip(rand(UInt8, 1000000)) --> true
#end


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

        # TODO: This would be more clear as:
        #stream = outbuf <| ZlibInflateOutputStream <| ZlibDeflateOutputStream

        write(stream, data)
        close(stream)
        return takebuf_array(outbuf) == data
    end

    @fact test_round_trip(UInt8[]) --> true
    @fact test_round_trip(rand(UInt8, 1)) --> true
    @fact test_round_trip(rand(UInt8, 1000000)) --> true
end




