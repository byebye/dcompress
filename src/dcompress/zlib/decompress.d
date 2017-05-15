/++
 + Provides decompressing abstractions for zlib format.
 +/
module dcompress.zlib.decompress;

debug = zlib;
debug(zlib)
{
    import std.stdio;
}

import c_zlib = etc.c.zlib;
public import dcompress.zlib.common;

/++
 + Keeps settings allowing to adjust the decompression process.
 +/
struct DecompressionPolicy
{
private:
    import std.typecons : Nullable;

    DataHeader _header = DataHeader.automatic;
    int _windowBits = 15;
    Nullable!(void[]) _buffer;
    size_t _defaultBufferSize = 1024;
    size_t _maxInputChunkSize = 1024;

public:

    /++
     + Returns the policy with options set to zlib defaults and buffer set to
     + empty `Nullable` (see `buffer` for details).
     +
     + Default settings:
     + $(OL
     +     $(LI `header = DataHeader.automatic`)
     +     $(LI `windowBits = 15`)
     +     $(LI `buffer.isEmpty == true`)
     +     $(LI `defaultBufferSize = 1024`)
     +     $(LI `inputChunkSize = 1024`)
     + )
     +/
    static DecompressionPolicy defaultPolicy()
    {
         return DecompressionPolicy.init;
    }

    /++
     + Specifies the default buffer size being allocated by decompressing
     + functions when `buffer.isNull == true`.
     +
     + Returns: The current default size for the buffer.
     +/
    @property size_t defaultBufferSize() const
    {
        return _defaultBufferSize;
    }

    /++
     + Sets the default buffer size.
     +
     + Params:
     + newSize = The new default size for the buffer, must be positive.
     +/
    @property void defaultBufferSize(size_t newSize)
    in
    {
        assert(newSize > 0);
    }
    body
    {
         _defaultBufferSize = newSize;
    }

    /++
     + Specifies the maximum chunk size when an input cannot be decompressed
     + directly but needs to be copied into a temporary array.
     +
     + Returns: The current maximum input chunk size.
     +/
    @property size_t maxInputChunkSize() const
    {
        return _maxInputChunkSize;
    }

    /++
     + Sets the maximum chunk size.
     +
     + Params:
     + newMaxChunkSize = The new maximum input chunk size, must be positive but
     +                   not greater than `4`GB.
     +/
    @property void maxInputChunkSize(size_t newMaxChunkSize)
    in
    {
        assert(0 < newMaxChunkSize && newMaxChunkSize <= 4 * 1024UL ^^ 3);
    }
    body
    {
         _maxInputChunkSize = newMaxChunkSize;
    }

    /++
     + Header that the decompressed data is wrapped with. See `DataHeader` for details.
     +
     + Returns: The current header value.
     +/
    @property DataHeader header() const
    {
         return _header;
    }

    /++
     + Sets the header to the given value.
     +
     + Params:
     + newHeader = New header value.
     +/
    @property void header(DataHeader newHeader)
    {
         _header = newHeader;
    }

    /++
     + Controls the size of the history buffer (i.e. window size) used when
     + decompressing data.
     +
     + Returns: A number between `9` and `15` being a base `2` logarithm of
     +          the current window size or `0` if window size is to be
     +          detected automatically (only if `header == DataHeader.zlib`).
     +/
    @property int windowBits() const
    {
        return _windowBits;
    }

    /++
     + Sets the window size.
     +
     + `newWindowBits` must be greater or equal to `DecompressionPolicy.windowBits`
     + value provided while compressing. If `header == DataHeader.zlib`,
     + `windowBits` can be set to `0` causing decompressor to use window size
     + stored in the zlib header of the compressed data.
     +
     + Params:
     + newWindowBits = New base `2` logarithm of the window size. Must be
     +                 a number from `9` (`512`-byte window) to `15`
     +                 (`32`KB window - default). If `header == DataHeader.zlib,
     +                 `0` is also allowed.
     +/
    @property void windowBits(int newWindowBits)
    in
    {
        assert(9 <= newWindowBits && newWindowBits <= 15 ||
            _header == DataHeader.zlib && newWindowBits == 0);
    }
    body
    {
         _windowBits = newWindowBits;
    }

    /++
     + Stores in one value the window size and header, according to the zlib
     + specification. Used to initialize the zlib library decompression process.
     +
     + Returns: The window size with included header value.
     +/
    @property int windowBitsWithHeader() const
    {
        final switch (_header)
        {
            case DataHeader.zlib: return _windowBits;
            case DataHeader.rawDeflate: return -_windowBits;
            case DataHeader.gzip: return 16 + _windowBits;
            case DataHeader.automatic: return 32 + _windowBits;
        }
    }

    /++
     + Gets the buffer serving as an intermediate output for the decompressed data.
     +
     + Returns: The current buffer.
     +/
    @property inout(Nullable!(void[])) buffer() inout
    {
        return _buffer;
    }

    /++
     + Sets the buffer to the given value.
     +
     + If `null`-state buffer is passed, i.e. `buffer.isNull == true`,
     + functions using the policy will allocate the buffer according to their
     + specification, for example `decompress(void[])` reserves enough memory
     + to fit the whole decompressed data at once, whereas other functions usually
     + allocate buffer with size equal to `defaultBufferSize`.
     +
     + If `newBuffer` is not in `null` state, then the underlying array must
     + not be empty.
     +
     + Params:
     + newBuffer = A `Nullable` array to be set as the buffer.
     +/
    @property void buffer(Nullable!(void[]) newBuffer)
    in
    {
        assert(newBuffer.isNull || newBuffer.get.length > 0);
    }
    body
    {
        _buffer = newBuffer;
    }

    /++
     + Sets the buffer to the given value.
     +
     + Params:
     + newBuffer = An non empty array to be set as the buffer.
     +/
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

/++
 + A structure used to decompress data incrementally. For one-shot decompression,
 + use `decompress` function.
 +
 + All the decompressed data produced by calls to `decompress`, `decompressPending`
 + and `flush` should be concatenated together.
 +
 + `Decompressor` keeps an internal buffer of fixed size for the decompressed data
 + produced the zlib library. The decompressing methods return a slice of this
 + internal buffer which means that the buffer is being modified between calls,
 + but also no memory allocations are performed directly by any of the methods.
 +/
struct Decompressor
{
private:

    c_zlib.z_stream _zlibStream;
    DecompressionPolicy _policy;
    enum Status : ubyte
    {
        outputPending,
        needsMoreInput,
        finished
    }
    Status _status = Status.needsMoreInput;

public:

    @disable this();

    private this(DecompressionPolicy policy)
    {
        immutable status = c_zlib.inflateInit2(
            &_zlibStream,
            policy.windowBitsWithHeader);

        if (status != ZlibStatus.ok)
            throw new ZlibException(status);
    }

    /++
     + Creates a decompressor with the given settings.
     +
     + If `policy.buffer.isNull`, it will be allocated with size equal to
     + `policy.defaultBufferSize`.
     +
     + Params:
     + policy = A policy defining different aspects of the decompression process.
     +
     + Throws: `ZlibException` if unable to initialize the zlib library, e.g.
     +         there is no enough memory or the library version is incompatible.
     +/
    static Decompressor create(DecompressionPolicy policy = DecompressionPolicy.defaultPolicy)
    {
        auto decomp = Decompressor(policy);

        if (policy.buffer.isNull)
            policy.buffer = new ubyte[policy.defaultBufferSize];
        decomp._policy = policy;

        return decomp;
    }

    /++
     + Default policy forces allocation of the buffer during the creation.
     +/
    unittest
    {
        debug(zlib) writeln("Decompressor.create -- default policy");
        auto decomp = Decompressor.create();
        auto policy = DecompressionPolicy.defaultPolicy;
        assert(policy.buffer.isNull);
        assert(decomp.buffer.length == policy.defaultBufferSize);
    }

    /++
     + Configuration may be tweaked on behalf of a policy, especially serves
     + to provide a custom buffer.
     +/
    unittest
    {
        debug(zlib) writeln("Decompressor.create -- custom buffer on heap");
        auto policy = DecompressionPolicy.defaultPolicy;
        auto buffer = new ubyte[10];
        policy.buffer = buffer;

        auto decomp = Decompressor.create(policy);
        assert(decomp.buffer.ptr == buffer.ptr);
        assert(decomp.buffer.length == buffer.length);

        debug(zlib) writeln("Decompressor.create -- custom config and buffer on stack");
        ubyte[5] bufStatic;
        policy.buffer = bufStatic[];
        policy.defaultBufferSize = 1;

        auto decompStatic = Decompressor.create(policy);
        assert(decompStatic.buffer.ptr == bufStatic.ptr);
        assert(decompStatic.buffer.length == bufStatic.length);
        assert(decompStatic.policy.defaultBufferSize == 1);

        // The previous Decompressor's settings should not be modified.
        assert(decomp.buffer.ptr == buffer.ptr);
        assert(decomp.policy.defaultBufferSize == DecompressionPolicy.defaultPolicy.defaultBufferSize);
    }

    ~this()
    {
        c_zlib.inflateEnd(&_zlibStream);
    }

    /++
     + Gets the current policy used during the decompression process.
     +
     + Returns: The current decompression policy.
     +/
    @property const(DecompressionPolicy) policy() const
    {
        return _policy;
    }

    /++
     + Gets the current internal array buffer. Note that the buffer does not
     + remember where the decompressed data ends.
     +
     + Returns: The current internal buffer.
     +/
    private @property void[] buffer()
    {
         return _policy.buffer.get;
    }

    /++
     + Checks if there is decompressed data available to retrieve without
     + providing more input.
     +
     + `true` effectively means that there wasn't enough space in the buffer to
     + fit all the decompressed data at once and more steps are needed to transfer
     + it. This can be done either by calling `decompressPending` or `flush`.
     +
     + Returns: `true` if there is decompressed data available, `false` otherwise.
     +/
    @property bool outputPending() const
    {
        return _status == Status.outputPending;
    }

    /++
     + Check whether there is output left from previous calls to `decompress`.
     +/
    unittest
    {
        debug(zlib) writeln("Decompressor.outputPending");

        auto uncompressed = "Lorem ipsum dolor sit amet";
        ubyte[] compressed = [
            120, 156, 243, 201, 47, 74, 205, 85, 200, 44, 40, 46, 205, 85, 72, 201,
            207, 201, 47, 82, 40, 206, 44, 81, 72, 204, 77, 45, 1, 0, 131, 213, 9, 197];

        auto policy = DecompressionPolicy.defaultPolicy;
        // Very small buffer just for presentation purposes.
        policy.buffer = new ubyte[1];
        auto decomp = Decompressor.create(policy);

        auto output = decomp.decompress(compressed).dup;
        assert(output.length == 1);
        assert(decomp.outputPending);
        // More decompressed data without providing more input.
        output ~= decomp.decompressPending();
        assert(output.length == 2);
    }

    /++
     + Checks if the last input has been completely processed.
     +
     + `true` means more input data can be safely provided for decompression.
     +
     + Note: There still may be decompressed data available to retrieve by calling
     +       `decompressPending` or `flush`, without the need to provide more input,
     +       see `outputPending`.
     +
     + Returns: `true` if the input has been processed, `false` otherwise.
     +/
    @property bool inputProcessed() const
    {
         return _zlibStream.avail_in == 0;
    }

    /++
     + Typical use case while compressing multiple chunks of data.
     +/
    unittest
    {
        debug(zlib) writeln("Decompressor.inputProcessed");

        auto uncompressed = "Lorem ipsum dolor sit amet";
        ubyte[][] compressed = [
            [120, 156, 243, 201, 47, 74], [205, 85, 200, 44], [40, 46, 205, 85, 72, 201],
            [207, 201, 47, 82], [40, 206, 44, 81, 72, 204, 77, 45], [1, 0, 131, 213, 9, 197]];

        auto policy = DecompressionPolicy.defaultPolicy;
        // Very small buffer just for testing purposes.
        policy.buffer = new ubyte[2];
        auto decomp = Decompressor.create(policy);

        void[] output;
        foreach (chunk; compressed)
        {
            output ~= decomp.decompress(chunk);
            while (!decomp.inputProcessed)
                output ~= decomp.decompressPending();
        }
        do
        {
            output ~= decomp.flush();
        } while (decomp.outputPending);

        assert(cast(string) output == uncompressed);
    }

    /++
     + Only sets the input to be compressed in the next call `decompressPending`
     + or `flush`, without advancing the decompression process.
     +
     + Note: The previous input that has not been fully processed is overriden.
     +
     + Params:
     + data = An input data to be decompressed.
     +/
    @property void input(const(void)[] data)
    {
        _zlibStream.next_in = cast(const(ubyte)*) data.ptr;
        _zlibStream.avail_in = cast(uint) data.length; // TODO check for overflow
        _status = Status.outputPending;
    }

    /++
     + Setting the input may be used to force one-shot decompression using `flush`,
     + although for this kind of decompression `decompress` functions are implemented.
     +/
    unittest
    {
        debug(zlib) writeln("Decompressor.input -- one-shot decompression");

        auto uncompressed = "Lorem ipsum dolor sit amet";
        ubyte[] compressed = [
            120, 156, 243, 201, 47, 74, 205, 85, 200, 44, 40, 46, 205, 85, 72, 201,
            207, 201, 47, 82, 40, 206, 44, 81, 72, 204, 77, 45, 1, 0, 131, 213, 9, 197];

        // Warning: for one-shot decompression enough buffer space needs to be provided.
        auto policy = DecompressionPolicy.defaultPolicy;
        policy.buffer = new ubyte[uncompressed.length];

        auto decomp = Decompressor.create(policy);
        decomp.input = compressed;
        auto output = decomp.flush().dup;

        assert(decomp.inputProcessed);
        assert(decomp.outputPending == false);
        assert(cast(string) output == uncompressed);
    }

    /++
     + Provides more data to be decompressed and proceeds with the decompression.
     +
     + This method is an equivalent of the following code:
     +
     + ---
     + input = data;
     + return decompressPending();
     + ---
     +
     + If there is no enough space in the buffer for the decompressed data then
     + `outputPending` will become `true`. The `data` should be completely
     + processed, i.e. `inputProcessed == true`, before the next invocation
     + of this method, otherwise the decompression process may be broken.
     +
     + Params:
     + data = An input data to be decompressed.
     +
     + Returns: Slice of the internal buffer with the decompressed data.
     +
     + Throws: `ZlibException` if the zlib library returns error.
     +/
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

    /++
     + Decompress the provided data.
     +/
    unittest
    {
        debug(zlib) writeln("Decompressor.decompress");

        auto uncompressed = "Lorem ipsum dolor sit amet";
        ubyte[][] compressed = [
            [120, 156, 243, 201, 47, 74], [205, 85, 200, 44], [40, 46, 205, 85, 72, 201],
            [207, 201, 47, 82], [40, 206, 44, 81, 72, 204, 77, 45], [1, 0, 131, 213, 9, 197]];

        // Provide enough buffer which will fit all the decompressed data.
        auto policy = DecompressionPolicy.defaultPolicy;
        policy.buffer = new ubyte[uncompressed.length];
        auto decomp = Decompressor.create(policy);

        // Warning: if not enough buffer space is provided, `inputProcessed`
        // and `outputPending` should be used for a safe decompression.
        void[] output;
        foreach (chunk; compressed)
            output ~= decomp.decompress(chunk);
        output ~= decomp.flush();

        assert(cast(string) output == uncompressed);
    }

    /++
     + Modifies decompression mode.
     +/
    private enum FlushMode
    {
        /// Default mode. Used to correctly finish the decompression process i.e.
        /// all pending input is processed and all pending output is flushed.
        finish = c_zlib.Z_FINISH,
        /// No flushing mode, just decompression.
        noFlush = c_zlib.Z_NO_FLUSH,
    }

    /++
     + Retrieves the remaining decompressed data that didn't fit into the internal
     + buffer during call to `decompress` and continues to decompress the input.
     +
     + Note: Check `inputProcessed` to see if additional calls are required to
     +       fully retrieve the data before providing more input.
     +
     + Returns: Slice of the internal buffer with the decompressed data.
     +
     + Throws: `ZlibException` if the zlib library returns error.
     +/
    const(void)[] decompressPending()
    {
        return decompress(FlushMode.noFlush);
    }

    /++
     + Retrieve the remaining decompressed data that didn't fit into the buffer.
     +/
    unittest
    {
        debug(zlib) writeln("Decompressor.decompressPending");

        auto uncompressed = "Lorem ipsum dolor sit amet";
        ubyte[] compressed = [
            120, 156, 243, 201, 47, 74, 205, 85, 200, 44, 40, 46, 205, 85, 72, 201,
            207, 201, 47, 82, 40, 206, 44, 81, 72, 204, 77, 45, 1, 0, 131, 213, 9, 197];

        auto policy = DecompressionPolicy.defaultPolicy;
        // Very small buffer just for presentation purposes.
        policy.buffer = new ubyte[5];
        auto decomp = Decompressor.create(policy);

        auto output = decomp.decompress(compressed).dup;
        assert(output.length == 5);
        assert(decomp.outputPending);

        output ~= decomp.decompressPending();
        assert(output.length == 10);
    }

    /++
     + Flushes the remaining decompressed data and finishes compressing the input.
     +
     + Returns: Slice of the internal buffer with the decompressed data.
     +
     + Throws: `ZlibException` if the zlib library returns error.
     +/
    const(void)[] flush()
    {
        return decompress(FlushMode.finish);
    }

    /++
     + Flush the remaining output and finish the current decompression process.
     +/
    unittest
    {
        debug(zlib) writeln("Decompressor.flush");

        auto uncompressed = "Lorem ipsum dolor sit amet";
        ubyte[] compressed = [
            120, 156, 243, 201, 47, 74, 205, 85, 200, 44, 40, 46, 205, 85, 72, 201,
            207, 201, 47, 82, 40, 206, 44, 81, 72, 204, 77, 45, 1, 0, 131, 213, 9, 197];

        auto policy = DecompressionPolicy.defaultPolicy;
        // Very small buffer just for presentation purposes.
        policy.buffer = new ubyte[15];
        auto decomp = Decompressor.create(policy);

        auto output = decomp.decompress(compressed).dup;
        assert(output.length == 15);

        // Using flush indicates that all the input data has been provided.
        output ~= decomp.flush();
        assert(cast(string) output == uncompressed);
    }

    private const(void)[] decompress(FlushMode mode)
    {
        // Nothing to do here.
        if (_status != Status.outputPending)
            return buffer[0 .. 0];

        _zlibStream.next_out = cast(ubyte*) buffer.ptr;
        _zlibStream.avail_out = cast(uint) buffer.length;

        auto status = c_zlib.inflate(&_zlibStream, mode);

        if (status == ZlibStatus.streamEnd)
        {
            _status = Status.finished;
            status = c_zlib.inflateReset(&_zlibStream);
            assert(status == ZlibStatus.ok);
        }
        else if (status == ZlibStatus.ok || status == ZlibStatus.bufferError)
        {
            if (_zlibStream.avail_out == 0)
                _status = Status.outputPending;
            else
                _status = Status.needsMoreInput;
        }
        else
        {
            // TODO Consider calling inflateEnd or inflateSync
            if (status == ZlibStatus.dataError)
                throw new ZlibException(status, _zlibStream.msg);
            else
                throw new ZlibException(status);
        }

        immutable writtenBytes = buffer.length - _zlibStream.avail_out;
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
 + Throws: `ZlibException` if any error occurs.
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
    ubyte[] compressed = [
        120, 156, 243, 201, 47, 74, 205, 85, 200, 44, 40, 46, 205, 85, 72, 201,
        207, 201, 47, 82, 40, 206, 44, 81, 72, 204, 77, 45, 1, 0, 131, 213, 9, 197];

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
 + Throws: `ZlibException` if any error occurs.
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
    ubyte[] compressed = [
        120, 156, 243, 201, 47, 74, 205, 85, 200, 44, 40, 46, 205, 85, 72, 201,
        207, 201, 47, 82, 40, 206, 44, 81, 72, 204, 77, 45, 1, 0, 131, 213, 9, 197];

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
    ubyte[] compressed = [
        120, 156, 243, 201, 47, 74, 205, 85, 200, 44, 40, 46, 205, 85, 72, 201,
        207, 201, 47, 82, 40, 206, 44, 81, 72, 204, 77, 45, 1, 0, 131, 213, 9, 197];

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
    ubyte[][] compressed = [
        [120, 156, 243, 201, 47], [74], [205, 85, 200, 44, 40, 46],
        [205, 85, 72, 201, 207, 201, 47], [82, 40, 206, 44, 81, 72, 204, 77],
        [45, 1, 0, 131, 213, 9, 197]];

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
 + output = Output range taking the compressed bytes.
 + policy = A policy defining different aspects of the compression process.
 +
 + Throws: `ZlibException` if any error occurs.
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
    ubyte[] compressed = [
        120, 156, 243, 201, 47, 74, 205, 85, 200, 44, 40, 46, 205, 85, 72, 201,
        207, 201, 47, 82, 40, 206, 44, 81, 72, 204, 77, 45, 1, 0, 131, 213, 9, 197];

    import dcompress.test : OutputRange;

    OutputRange!ubyte output;
    decompress(compressed, output);
    assert(output.buffer == cast(void[]) uncompressed);
}

/++
 + Decompresses all the bytes from the input range using the given decompression
 + policy and outputs the data directly to the provided output range.
 +
 + If `output` is an array, the decompressed data will replace its content - instead
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
 + Throws: `ZlibException` if any error occurs.
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
 + One-shot compression of an input range of data to an output.
 +/
unittest
{
    debug(zlib) writeln("decompress(InputRange, OutputRange)");

    auto uncompressed = "Lorem ipsum dolor sit amet";
    ubyte[] compressed = [
        120, 156, 243, 201, 47, 74, 205, 85, 200, 44, 40, 46, 205, 85, 72, 201,
        207, 201, 47, 82, 40, 206, 44, 81, 72, 204, 77, 45, 1, 0, 131, 213, 9, 197];

    import dcompress.test : inputRange, OutputRange;

    auto range = inputRange(compressed);
    OutputRange!ubyte output;
    decompress(range, output);
    assert(output.buffer == cast(void[]) uncompressed);
}

/++
 + One-shot compression of an input range of data to an array.
 +/
unittest
{
    debug(zlib) writeln("decompress(InputRange, array)");

    auto uncompressed = "Lorem ipsum dolor sit amet";
    ubyte[] compressed = [
        120, 156, 243, 201, 47, 74, 205, 85, 200, 44, 40, 46, 205, 85, 72, 201,
        207, 201, 47, 82, 40, 206, 44, 81, 72, 204, 77, 45, 1, 0, 131, 213, 9, 197];

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
