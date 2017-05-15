/++
 + Provides decompressing abstractions for bz2 format.
 +/
module dcompress.bz2.decompress;


debug = bz2;
debug(bz2)
{
    import std.stdio;
}

import c_bz2 = dcompress.etc.c.bz2;
public import dcompress.bz2.common;

struct DecompressionPolicy
{
private:

    import std.typecons : Nullable;

    Nullable!(void[]) _buffer;
    int _verbosity = 0;
    size_t _defaultBufferSize = 1024;
    size_t _maxInputChunkSize = 1024;
    bool _minimizeMemory = false;

public:

    static DecompressionPolicy defaultPolicy()
    {
        return DecompressionPolicy.init;
    }

    @property size_t defaultBufferSize() const
    {
        return _defaultBufferSize;
    }

    @property void defaultBufferSize(size_t newSize)
    in
    {
        assert(newSize > 0);
    }
    body
    {
         _defaultBufferSize = newSize;
    }

    @property size_t maxInputChunkSize() const
    {
        return _maxInputChunkSize;
    }

    @property void maxInputChunkSize(size_t newMaxChunkSize)
    in
    {
        assert(0 < newMaxChunkSize && newMaxChunkSize <= 4 * 1024UL ^^ 3);
    }
    body
    {
         _maxInputChunkSize = newMaxChunkSize;
    }

    @property bool minimizeMemory() const
    {
        return _minimizeMemory;
    }

    @property void minimizeMemory(bool minimize)
    {
        _minimizeMemory = minimize;
    }

    @property int verbosityLevel() const
    {
        return _verbosity;
    }

    @property void verbosityLevel(int newVerbosity)
    in
    {
        assert(0 <= newVerbosity && newVerbosity <= 4);
    }
    body
    {
        _verbosity = newVerbosity;
    }

    @property inout(Nullable!(void[])) buffer() inout
    {
        return _buffer;
    }

    @property void buffer(Nullable!(void[]) newBuffer)
    in
    {
        assert(newBuffer.isNull || newBuffer.get.length > 0);
    }
    body
    {
        _buffer = newBuffer;
    }

    @property void buffer(void[] newBuffer)
    in
    {
        assert(newBuffer.length > 0);
    }
    body
    {
        _buffer = newBuffer;
    }
}

struct Decompressor
{
private:

    c_bz2.bz_stream _bzStream;
    DecompressionPolicy _policy;
    enum Status : ubyte
    {
        idle,
        running,
    }
    Status _status = Status.idle;

    size_t totalBytesIn() const
    {
        return (size_t(_bzStream.total_in_hi32) << 32) + _bzStream.total_in_lo32;
    }

    size_t totalBytesOut() const
    {
        return (size_t(_bzStream.total_out_hi32) << 32) + _bzStream.total_out_lo32;
    }

public:

    @disable this();

    ~this()
    {
        if (_status != Status.idle)
            c_bz2.BZ2_bzDecompressEnd(&_bzStream);
    }

    static Decompressor create(DecompressionPolicy policy = DecompressionPolicy.defaultPolicy)
    {
        auto decomp = Decompressor.init;

        if (policy.buffer.isNull)
            policy.buffer = new ubyte[policy.defaultBufferSize];
        decomp._policy = policy;

        return decomp;
    }

    @property const(DecompressionPolicy) policy() const
    {
        return _policy;
    }

    private @property void[] buffer()
    {
         return _policy.buffer.get;
    }

    @property bool outputPending() const
    {
        writeln("pending: ", _status);
        return _status == Status.running;
    }

    @property bool inputProcessed() const
    {
         return _bzStream.avail_in == 0;
    }

    @property void input(const(void)[] data)
    {
        writeln("input");
        if (_status == Status.idle)
            initStream();
        _bzStream.next_in = cast(ubyte*) data.ptr;
        _bzStream.avail_in = cast(uint) data.length; // TODO check for overflow
    }

    private void initStream()
    {
        auto status = c_bz2.BZ2_bzDecompressInit(
            &_bzStream,
            policy.verbosityLevel,
            policy.minimizeMemory);

        if (status != Bz2Status.ok)
            throw new Bz2Exception(status);

        _status = Status.running;
    }

    const(void)[] decompress(const(void)[] data)
    in
    {
        // Ensure no leftovers from previous calls.
        assert(inputProcessed);
    }
    body
    {
        input = data;
        return decompressPending();
    }

    const(void)[] decompressPending()
    {
        return decompress();
    }

    const(void)[] flush()
    {
        return decompress();
    }

    private const(void)[] decompress()
    {
        if (_status == Status.idle)
            return buffer[0 .. 0];

        _bzStream.next_out = cast(ubyte*) buffer.ptr;
        _bzStream.avail_out = cast(uint) buffer.length;

        writeln(_status, " ", _bzStream.avail_in);

        auto status = c_bz2.BZ2_bzDecompress(&_bzStream);

        if (status == Bz2Status.streamEnd)
        {
            _status = Status.idle;
            status = c_bz2.BZ2_bzDecompressEnd(&_bzStream);
            assert(status == Bz2Status.ok);
        }
        else if (status != Bz2Status.ok)
        {
            throw new Bz2Exception(status);
        }
        immutable writtenBytes = buffer.length - _bzStream.avail_out;
        return buffer[0 .. writtenBytes];
    }
}

/++
 + Decompresses all the bytes from the array at once using the given decompression policy.
 +
 + Params:
 + data = Array of bytes to be decompressed.
 + policy = A policy defining different aspects of the decompression process.
 +
 + Returns: Decompressed data.
 +
 + Throws: `Bz2Exception` if any error occurs.
 +/
void[] decompress(const(void)[] data, DecompressionPolicy policy = DecompressionPolicy.defaultPolicy)
{
    debug(zlib) writeln("decompress(void[])");

    auto decomp = Decompressor.create(policy);

    decomp.input = data;
    void[] output;
    output.reserve(data.length);
    decomp.flushAll(output);
    return output;
}

/++
 + One-shot decompression of an array of data.
 +/
unittest
{
    debug(zlib) writeln("decompress(void[])");

    auto uncompressed = "Lorem ipsum dolor sit amet";
    ubyte[] compressed = [66, 90, 104, 54, 49, 65, 89, 38, 83, 89, 227, 213,
    231, 186, 0, 0, 2, 21, 128, 64, 0, 0, 4, 38, 38, 222, 0, 32, 0, 49, 0, 0, 8,
    141, 169, 163, 25, 34, 150, 46, 25, 195, 163, 151, 86, 138, 243, 86, 9, 191,
    139, 185, 34, 156, 40, 72, 113, 234, 243, 221, 0];

    auto output = cast(string) decompress(compressed);
    assert(output == uncompressed);
}

import dcompress.primitives : isCompressInput, isCompressOutput;
import std.traits : isArray;

/++
 + Decompresses all the bytes from the input range at once using the given compression policy.
 +
 + Because the zlib library is used underneath, the `data` needs to be provided
 + as a built-in array - this is done by allocating an array and copying the input
 + into it chunk by chunk. This chunk size is controlled by `policy.maxInputChunkSize`.
 + The greater the chunk the decompression may be faster and reduce zlib memory
 + usage. In particular, the best effect can be achieved when
 + `policy.maxInputChunkSize` is equal or greater than number of bytes in `data`,
 + which means that entire input can be provided to the zlib library at once.
 +
 + Params:
 + data = Input range of bytes to be decompressed.
 + policy = A policy defining different aspects of the decompression process.
 +
 + Returns: Decompressed data.
 +
 + Throws: `Bz2Exception` if any error occurs.
 +/
void[] decompress(InR)(InR data, DecompressionPolicy policy = DecompressionPolicy.defaultPolicy)
if (!isArray!InR && isCompressInput!InR)
{
    debug(zlib) writeln("decompress(InputRange)");

    void[] output;
    decompress(data, output, policy);
    return output;
}

/++
 + One-shot decompression of a `ubyte`-input range of data.
 +/
unittest
{
    debug(zlib) writeln("decompress(InputRange!ubyte) -- no length");

    auto uncompressed = "Lorem ipsum dolor sit amet";
    ubyte[] compressed = [66, 90, 104, 54, 49, 65, 89, 38, 83, 89, 227, 213,
    231, 186, 0, 0, 2, 21, 128, 64, 0, 0, 4, 38, 38, 222, 0, 32, 0, 49, 0, 0, 8,
    141, 169, 163, 25, 34, 150, 46, 25, 195, 163, 151, 86, 138, 243, 86, 9, 191,
    139, 185, 34, 156, 40, 72, 113, 234, 243, 221, 0];

    import dcompress.test : inputRange;
    auto range = inputRange(compressed);
    auto output = cast(string) decompress(range);
    assert(output == uncompressed);
}

/++
 + One-shot decompression of a `ubyte`-input range with length which is optimized
 + when `policy.maxInputChunkSize >= data.length`.
 +/
unittest
{
    debug(zlib) writeln("decompress(InputRange!ubyte) -- with length");

    auto uncompressed = "Lorem ipsum dolor sit amet";
    ubyte[] compressed = [66, 90, 104, 54, 49, 65, 89, 38, 83, 89, 227, 213,
    231, 186, 0, 0, 2, 21, 128, 64, 0, 0, 4, 38, 38, 222, 0, 32, 0, 49, 0, 0, 8,
    141, 169, 163, 25, 34, 150, 46, 25, 195, 163, 151, 86, 138, 243, 86, 9, 191,
    139, 185, 34, 156, 40, 72, 113, 234, 243, 221, 0];

    DecompressionPolicy policy = DecompressionPolicy.defaultPolicy;

    import dcompress.test : inputRange;
    // Optimized.
    policy.maxInputChunkSize = compressed.length * 2;

    auto optRange = inputRange!"withLength"(compressed);
    auto optOutput = cast(string) decompress(optRange, policy);
    assert(optOutput == uncompressed);

    // Not optimized.
    policy.maxInputChunkSize = compressed.length / 2;

    auto range = inputRange!"withLength"(compressed);
    auto output = cast(string) decompress(range, policy);
    assert(output == uncompressed);
}

/++
 + One-shot decompression of an array-input range of data.
 +/
unittest
{
    debug(zlib) writeln("decompress(InputRange!(ubyte[])");

    auto uncompressed = "Lorem ipsum dolor sit amet";
    ubyte[][] compressed = [[66, 90, 104, 54, 49, 65, 89, 38, 83, 89, 227, 213],
    [231, 186, 0], [0], [2, 21, 128, 64, 0, 0, 4, 38, 38, 222, 0, 32, 0, 49, 0, 0, 8],
    [141, 169, 163], [25, 34, 150, 46, 25, 195, 163, 151, 86, 138, 243, 86, 9, 191,
    139, 185, 34, 156, 40, 72], [113, 234, 243, 221, 0]];

    import dcompress.test : inputRange;
    auto range = inputRange(compressed);
    auto output = cast(string) decompress(range);
    assert(output == uncompressed);
}

/++
 + Decompresses all the bytes from the array using the given decompression policy
 + and outputs the data directly to the provided output range.
 +
 + If `output` is an array, the compressed data will replace its content - instead
 + of being appended.
 +
 + Params:
 + data = Array of bytes to be decompressed.
 + output = Output range taking the decompressed bytes.
 + policy = A policy defining different aspects of the decompression process.
 +
 + Throws: `Bz2Exception` if any error occurs.
 +/
void decompress(OutR)(const(void)[] data, ref OutR output, DecompressionPolicy policy = DecompressionPolicy.defaultPolicy)
if (isCompressOutput!OutR)
{
    debug(zlib) writeln("decompress(void[], OutputRange)");

    auto decomp = Decompressor.create(policy);
    decomp.input = data;

    import std.traits : isArray;
    static if (isArray!OutR)
    {
        output.reserve(data.length);
        output.length = 0;
    }
    decomp.flushAll(output);
}

/++
 + One-shot decompression of an array of data to the provided output.
 +/
unittest
{
    debug(zlib) writeln("decompress(void[], OutputRange)");

    auto uncompressed = "Lorem ipsum dolor sit amet";
    ubyte[] compressed = [66, 90, 104, 54, 49, 65, 89, 38, 83, 89, 227, 213,
    231, 186, 0, 0, 2, 21, 128, 64, 0, 0, 4, 38, 38, 222, 0, 32, 0, 49, 0, 0, 8,
    141, 169, 163, 25, 34, 150, 46, 25, 195, 163, 151, 86, 138, 243, 86, 9, 191,
    139, 185, 34, 156, 40, 72, 113, 234, 243, 221, 0];

    import dcompress.test : OutputRange;

    OutputRange!ubyte output;
    decompress(compressed, output);
    assert(output.buffer == cast(void[]) uncompressed);
}

/++
 + Decompresses all the bytes from the input range using the given decompression
 + policy and outputs the data directly to the provided output range.
 +
 + If `output` is an array, the compressed data will replace its content - instead
 + of being appended.
 +
 + Because the zlib library is used underneath, the `data` needs to be provided
 + as a built-in array - this is done by allocating an array and copying the input
 + into it chunk by chunk. This chunk size is controlled by `policy.maxInputChunkSize`.
 + The greater the chunk the decompression may be faster and reduce zlib memory
 + usage. In particular, the best effect can be achieved when
 + `policy.maxInputChunkSize` is equal or greater than number of bytes in `data`,
 + which means that entire input can be provided to the zlib library at once.
 +
 + Params:
 + data = Input range of bytes to be decompressed.
 + output = Output range taking the decompressed bytes.
 + policy = A policy defining different aspects of the decompression process.
 +
 + Throws: `Bz2Exception` if any error occurs.
 +/
void decompress(InR, OutR)(InR data, ref OutR output, DecompressionPolicy policy = DecompressionPolicy.defaultPolicy)
if (!isArray!InR && isCompressInput!InR && isCompressOutput!OutR)
{
    debug(zlib) writeln("decompress!(InputRange, OutputRange)");

    import std.range.primitives : ElementType;
    import std.traits : Unqual;
    static if (is(Unqual!(ElementType!InR) == ubyte))
    {
        debug(zlib) writeln("ElementType!InR == ubyte");

        import std.range.primitives : hasLength;
        static if (hasLength!InR)
        {
            if (policy.maxInputChunkSize >= data.length)
            {
                debug(zlib) writeln("hasLength!InR && policy.maxInputChunkSize >= data.length");

                auto input = new ubyte[data.length];
                import std.algorithm.mutation : copy;
                copy(data, input);
                decompress(input, output, policy);
                return;
            }
        }

        auto decomp = Decompressor.create(policy);
        decomp.decompressAllByCopyChunk(data, output);
    }
    else // isArray!(ElementType!InR)
    {
        debug(zlib) writeln("isArray!(ElementType!InR)");

        auto decomp = Decompressor.create(policy);
        decomp.decompressAllByChunk(data, output);
    }
}

/++
 + One-shot decompression of an input range of data to an output.
 +/
unittest
{
    debug(zlib) writeln("decompress(InputRange, OutputRange)");

    auto uncompressed = "Lorem ipsum dolor sit amet";
    ubyte[] compressed = [66, 90, 104, 54, 49, 65, 89, 38, 83, 89, 227, 213,
    231, 186, 0, 0, 2, 21, 128, 64, 0, 0, 4, 38, 38, 222, 0, 32, 0, 49, 0, 0, 8,
    141, 169, 163, 25, 34, 150, 46, 25, 195, 163, 151, 86, 138, 243, 86, 9, 191,
    139, 185, 34, 156, 40, 72, 113, 234, 243, 221, 0];

    import dcompress.test : inputRange, OutputRange;

    auto range = inputRange(compressed);
    OutputRange!ubyte output;
    decompress(range, output);
    assert(output.buffer == cast(void[]) uncompressed);
}

/++
 + One-shot decompression of an input range of data to an array.
 +/
unittest
{
    debug(zlib) writeln("decompress(InputRange, array)");

    auto uncompressed = "Lorem ipsum dolor sit amet";
    ubyte[] compressed = [66, 90, 104, 54, 49, 65, 89, 38, 83, 89, 227, 213,
    231, 186, 0, 0, 2, 21, 128, 64, 0, 0, 4, 38, 38, 222, 0, 32, 0, 49, 0, 0, 8,
    141, 169, 163, 25, 34, 150, 46, 25, 195, 163, 151, 86, 138, 243, 86, 9, 191,
    139, 185, 34, 156, 40, 72, 113, 234, 243, 221, 0];

    import dcompress.test : inputRange;

    auto range = inputRange!"withLength"(compressed);
    void[] output;
    decompress(range, output);
    assert(cast(string) output == uncompressed);
}

private void decompressAllByChunk(InR, OutR)(ref Decompressor decomp, ref InR data, ref OutR output)
{
    foreach (chunk; data)
    {
        decomp.decompressAll(chunk, output);
    }
    decomp.flushAll(output);
}

private void decompressAllByCopyChunk(InR, OutR)(ref Decompressor decomp, ref InR data, ref OutR output)
{
    // TODO On-stack allocation for chunk - argument switch?
    import std.range.primitives : hasLength;
    static if (hasLength!InR)
    {
        import std.algorithm.comparison : min;
        immutable chunkSize = min(data.length, decomp.policy.maxInputChunkSize);
    }
    else
        immutable chunkSize = decomp.policy.maxInputChunkSize;
    // TODO optimize when all the data fits in chunk.
    ubyte[] chunk = new ubyte[chunkSize];
    while (!data.empty)
    {
        foreach (i; 0 .. chunkSize)
        {
            chunk[i] = data.front;
            data.popFront();
            if (data.empty)
            {
                chunk.length = i + 1;
                break;
            }
        }
        decomp.decompressAll(chunk, output);
    }
    decomp.flushAll(output);
}

private void decompressAll(OutR)(ref Decompressor decomp, const(void)[] data, ref OutR output)
if (isCompressOutput!OutR)
{
    import std.traits : isArray;
    static if (isArray!OutR)
    {
        output ~= cast(OutR) decomp.decompress(data);
        while (!decomp.inputProcessed)
            output ~= cast(OutR) decomp.decompressPending();
    }
    else
    {
        import std.range.primitives : put;
        put(output, cast(const(ubyte)[]) decomp.decompress(data));
        while (!decomp.inputProcessed)
            put(output, cast(const(ubyte)[]) decomp.decompressPending());
    }
}

private void flushAll(OutR)(ref Decompressor decomp, ref OutR output)
if (isCompressOutput!OutR)
{
    do
    {
        import std.traits : isArray;
        static if (isArray!OutR)
        {
            output ~= cast(OutR) decomp.flush();
        }
        else
        {
            import std.range.primitives : put;
            put(output, cast(const(ubyte)[]) decomp.flush());
        }
    } while (decomp.outputPending);
}
