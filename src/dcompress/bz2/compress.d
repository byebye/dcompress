/++
 + Provides decompressing abstractions for bz2 format.
 +/
module dcompress.bz2.compress;

debug = bz2;
debug(bz2)
{
    import std.stdio;
}

import c_bz2 = dcompress.etc.c.bz2;
public import dcompress.bz2.common;

struct CompressionPolicy
{
private:

    import std.typecons : Nullable;

    Nullable!(void[]) _buffer;
    int _blockSize = 6;
    int _verbosity = 0;
    int _workFactor = 30;
    size_t _defaultBufferSize = 1024;
    size_t _maxInputChunkSize = 1024;

public:

    static CompressionPolicy defaultPolicy()
    {
        return CompressionPolicy.init;
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

    @property int blockSize() const
    {
        return _blockSize;
    }

    @property void blockSize(int newSize)
    in
    {
        assert(1 <= newSize && newSize <= 9);
    }
    body
    {
        _blockSize = newSize;
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

    @property int workFactor() const
    {
        return _workFactor;
    }

    @property void workFactor(int newWorkFactor)
    in
    {
        assert(0 <= newWorkFactor && newWorkFactor <= 250);
    }
    body
    {
        _workFactor = newWorkFactor;
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

struct Compressor
{
private:

    c_bz2.bz_stream _bzStream;
    CompressionPolicy _policy;
    enum Status : ubyte
    {
        idle,
        running,
        finishing
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
        c_bz2.BZ2_bzCompressEnd(&_bzStream);
    }

    static Compressor create(CompressionPolicy policy = CompressionPolicy.defaultPolicy)
    {
        auto comp = Compressor.init;

        if (policy.buffer.isNull)
            policy.buffer = new ubyte[policy.defaultBufferSize];
        comp._policy = policy;

        return comp;
    }

    @property const(CompressionPolicy) policy() const
    {
        return _policy;
    }

    private @property void[] buffer()
    {
         return _policy.buffer.get;
    }

    @property bool outputPending() const
    {
        return _status == Status.finishing ||
            (_status == Status.running && !inputProcessed);
    }

    @property bool inputProcessed() const
    {
         return _bzStream.avail_in == 0;
    }

    @property void input(const(void)[] data)
    {
        if (_status == Status.idle)
            initStream();
        _bzStream.next_in = cast(ubyte*) data.ptr;
        _bzStream.avail_in = cast(uint) data.length; // TODO check for overflow
    }

    private void initStream()
    {
        auto status = c_bz2.BZ2_bzCompressInit(
            &_bzStream,
            policy.blockSize,
            policy.verbosityLevel,
            policy.workFactor);

        if (status != Bz2Status.ok)
            throw new Bz2Exception(status);

        _status = Status.running;
    }

    const(void)[] compress(const(void)[] data)
    in
    {
        // Ensure no leftovers from previous calls.
        assert(inputProcessed);
    }
    body
    {
        input = data;
        return compressPending();
    }

    const(void)[] compressPending()
    {
        return compress(Bz2Action.run);
    }

    const(void)[] flush()
    {
        return compress(Bz2Action.finish);
    }

    private const(void)[] compress(Bz2Action action)
    {
        _bzStream.next_out = cast(ubyte*) buffer.ptr;
        _bzStream.avail_out = cast(uint) buffer.length;

        auto status = c_bz2.BZ2_bzCompress(&_bzStream, action);

        if (status == Bz2Status.streamEnd)
        {
            _status = Status.idle;
            status = c_bz2.BZ2_bzCompressEnd(&_bzStream);
            assert(status == Bz2Status.ok);
        }
        else if (isOk(action, status))
        {
            if (action == Bz2Action.finish)
                _status = Status.finishing;
        }
        else
        {
            throw new Bz2Exception(status);
        }
        immutable writtenBytes = buffer.length - _bzStream.avail_out;
        return buffer[0 .. writtenBytes];
    }

    private bool isOk(Bz2Action action, int status)
    {
        final switch (action) with (Bz2Action)
        {
            case run: return (status == Bz2Status.runOk);
            case finish: return (status == Bz2Status.finishOk);
            case flush: return (status == Bz2Status.flushOk);
        }
    }
}

/++
 + Compresses all the bytes from the array at once using the given compression policy.
 +
 + Params:
 + data = Array of bytes to be compressed.
 + policy = A policy defining different aspects of the compression process.
 +
 + Returns: Compressed data.
 +
 + Throws: `Bz2Exception` if any error occurs.
 +/
void[] compress(const(void)[] data, CompressionPolicy policy = CompressionPolicy.defaultPolicy)
{
    debug(bz2) writeln("compress(void[])");

    auto comp = Compressor.create(policy);
    comp.input = data;

    void[] output;
    do
    {
        writeln("flush");
        output ~= comp.flush();
    } while (comp.outputPending);

    return output;
}

/++
 + One-shot compression of an array of data.
 +/
unittest
{
    debug(bz2) writeln("compress(void[])");
    auto data =  "Lorem ipsum dolor sit amet, consectetur adipiscing elit. ";

    auto output = compress(data);
    //import dcompress.bz2 : decompress;
    //assert(decompress(output) == data);
}

import dcompress.primitives : isCompressInput, isCompressOutput;
import std.traits : isArray;

/++
 + Compresses all the bytes from the input range at once using the given compression policy.
 +
 + Because the libbzip2 library is used underneath, the `data` needs to be provided
 + as a built-in array - this is done by allocating an array and copying the input
 + into it chunk by chunk. This chunk size is controlled by `policy.maxInputChunkSize`.
 + The greater the chunk the better and faster the compression is. In particular,
 + if `data` has `length` property and `policy.maxInputChunkSize >= data.length`,
 + data will be compressed at once - which is faster and gives a better
 + compression compared to compression in chunks.
 +
 + Params:
 + data = Input range of bytes to be compressed.
 + policy = A policy defining different aspects of the compression process.
 +
 + Returns: Compressed data.
 +
 + Throws: `Bz2Exception` if any error occurs.
 +/
void[] compress(InR)(InR data, CompressionPolicy policy = CompressionPolicy.defaultPolicy)
if (!isArray!InR && isCompressInput!InR)
{
    debug(bz2) writeln("compress(InputRange)");

    void[] output;
    compress(data, output, policy);
    return output;
}

/++
 + One-shot compression of a `ubyte`-input range of data.
 +/
unittest
{
    debug(bz2) writeln("compress(InputRange)");
    const(void)[] data = "Lorem ipsum dolor sit amet, consectetur adipiscing elit. ";

    import dcompress.test : inputRange;
    auto range = inputRange(cast(ubyte[]) data);
    auto output = compress(range);

    //import dcompress.bz2 : decompress;
    //assert(decompress(output) == data);
}

/++
 + One-shot compression of a `ubyte`-input range with length which is optimized.
 +/
unittest
{
    debug(bz2) writeln("compress(InputRange)");
    const(void)[] data = "Lorem ipsum dolor sit amet, consectetur adipiscing elit. ";

    import dcompress.test : inputRange;
    auto range = inputRange!"withLength"(cast(ubyte[]) data);
    auto policy = CompressionPolicy.defaultPolicy;
    // Provide enough room to copy data to.
    policy.maxInputChunkSize = 1024 ^^ 3;
    auto output = compress(range, policy);

    // Input won't fit entirely into a chunk, compression at once not possible.
    policy.maxInputChunkSize = 4;
    auto output2 = compress(range, policy);

    //import dcompress.bz2 : decompress;
    //assert(decompress(output) == data);
}

/++
 + One-shot compression of an array-input range of data.
 +/
unittest
{
    debug(bz2) writeln("compress(InputRange)");
    auto data = ["Lorem ipsum", " dolor sit amet,", " consectetur", " adipiscing elit. "];

    import dcompress.test : inputRange;
    auto range = inputRange(data);
    auto output = compress(range);

    //import dcompress.bz2 : decompress;
    //import std.range : join;
    //assert(decompress(output) == data.join);
}

/++
 + Compresses all the bytes using the given compression policy and outputs
 + the compressed data directly to the provided output range.
 +
 + If `output` is an array, the compressed data will replace its content - instead
 + of being appended.
 +
 + Params:
 + data = Array of bytes to be compressed.
 + output = Output range taking the compressed bytes.
 + policy = A policy defining different aspects of the compression process.
 +
 + Throws: `Bz2Exception` if any error occurs.
 +/
void compress(OutR)(const(void)[] data, ref OutR output, CompressionPolicy policy = CompressionPolicy.defaultPolicy)
if (isCompressOutput!OutR)
{
    debug(bz2) writeln("compress(void[], OutputRange)");

    auto comp = Compressor.create(policy);
    comp.input = data;

    import std.traits : isArray;
    static if (isArray!OutR)
        output.length = 0;

    comp.flushAll(output);
}

/++
 + One-shot compression of an array of data to the provided output.
 +/
unittest
{
    debug(bz2) writeln("compress(void[], OutputRange)");
    const(void)[] data = "Lorem ipsum dolor sit amet, consectetur adipiscing elit. ";

    import dcompress.test : OutputRange;
    OutputRange!ubyte output;
    compress(data, output);
    assert(output.buffer == compress(data));

    //import dcompress.bz2 : decompress;
    //assert(decompress(output.buffer) == data);

    void[] outputBuff;
    compress(data, outputBuff);
    assert(outputBuff == output.buffer);
}

/++
 + Compresses all the bytes from the input range at once using the given compression policy
 + and outputs the compressed data directly to the provided output range.
 +
 + If `output` is an array, the compressed data will replace its content - instead
 + of being appended.
 +
 + Because the libbzip2 library is used underneath, the `data` needs to be provided
 + as a built-in array - this is done by allocating an array and copying the input
 + into it chunk by chunk. This chunk size is controlled by `policy.maxInputChunkSize`.
 + The greater the chunk the better and faster the compression is. In particular,
 + if `data` has `length` property and `policy.maxInputChunkSize >= data.length`,
 + the data will be compressed at once - which is faster and gives a better
 + compression compared to compression in chunks.
 +
 + Params:
 + data = Input range of bytes to be compressed.
 + output = Output range taking the compressed bytes.
 + policy = A policy defining different aspects of the compression process.
 +
 + Returns: Compressed data.
 +
 + Throws: `Bz2Exception` if any error occurs.
 +/
void compress(InR, OutR)(InR data, ref OutR output, CompressionPolicy policy = CompressionPolicy.defaultPolicy)
if (!isArray!InR && isCompressInput!InR && isCompressOutput!OutR)
{
    debug(bz2) writeln("compress(InputRange, OutputRange)");

    import std.range.primitives : ElementType;
    import std.traits : Unqual, isArray;
    static if (is(Unqual!(ElementType!InR) == ubyte))
    {
        debug(bz2) writeln("ElementType!InR == ubyte");

        import std.range.primitives : hasLength;
        static if (hasLength!InR)
        {
            if (policy.maxInputChunkSize >= data.length)
            {
                debug(bz2) writeln("hasLength!InR && policy.maxInputChunkSize >= data.length");

                import std.algorithm.mutation : copy;
                auto input = new ubyte[data.length];
                copy(data, input);
                compress(input, output, policy);
                return;
            }
        }
        auto comp = Compressor.create(policy);
        // Array content is be replaced.
        static if (isArray!OutR)
            output.length = 0;
        comp.compressAllByCopyChunk(data, output);
    }
    else // isArray!(ElementType!InR)
    {
        debug(bz2) writeln("isArray!(ElementType!InR)");

        auto comp = Compressor.create(policy);
        comp.compressAllByChunk(data, output);
    }
}

/++
 + One-shot compression of an input range of data to an output.
 +/
unittest
{
    debug(bz2) writeln("compress(InputRange, OutputRange)");
    const(void)[] data = "Lorem ipsum dolor sit amet, consectetur adipiscing elit. ";

    import dcompress.test : inputRange, OutputRange;
    auto range = inputRange!"withLength"(cast(const(ubyte)[]) data);

    OutputRange!ubyte output;
    compress(range, output);
    assert(output.buffer == compress(data));

    //import dcompress.bz2 : decompress;
    //assert(decompress(output.buffer) == data);

    // Output to an array, which will be reallocated.
    auto range2 = inputRange!"withLength"(cast(ubyte[]) data);
    auto outputBuff = new ubyte[10];
    compress(range2, outputBuff);
    assert(outputBuff == output.buffer);

    // Input range without length.
    auto range3 = inputRange(cast(ubyte[]) data);
    auto outputBuff2 = new ubyte[10];
    compress(range3, outputBuff2);
    assert(outputBuff2 == output.buffer);
}

private void compressAllByChunk(InR, OutR)(ref Compressor comp, ref InR data, ref OutR output)
{
    foreach (chunk; data)
    {
        comp.compressAll(chunk, output);
    }
    comp.flushAll(output);
}

private void compressAllByCopyChunk(InR, OutR)(ref Compressor comp, ref InR data, ref OutR output)
{
    // TODO On-stack allocation for chunk - argument switch?
    import std.range.primitives : hasLength;
    static if (hasLength!InR)
    {
        import std.algorithm.comparison : min;
        immutable chunkSize = min(data.length, comp.policy.maxInputChunkSize);
    }
    else
        immutable chunkSize = comp.policy.maxInputChunkSize;

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
        comp.compressAll(chunk, output);
    }
    comp.flushAll(output);
}

private void compressAll(OutR)(ref Compressor comp, const(void)[] data, ref OutR output)
if (isCompressOutput!OutR)
{
    import std.traits : isArray;
    static if (isArray!OutR)
    {
        output ~= cast(OutR) comp.compress(data);
        while (!comp.inputProcessed)
            output ~= cast(OutR) comp.compressPending();
    }
    else
    {
        import std.range.primitives : put;
        put(output, cast(const(ubyte)[]) comp.compress(data));
        while (!comp.inputProcessed)
            put(output, cast(const(ubyte)[]) comp.compressPending());
    }
}

private void flushAll(OutR)(ref Compressor comp, ref OutR output)
if (isCompressOutput!OutR)
{
    do
    {
        import std.traits : isArray;
        static if (isArray!OutR)
        {
            output ~= cast(OutR) comp.flush();
        }
        else
        {
            import std.range.primitives : put;
            put(output, cast(const(ubyte)[]) comp.flush());
        }
    } while (comp.outputPending);
}
