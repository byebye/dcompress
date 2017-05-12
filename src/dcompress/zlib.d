/++
 + Provides compressing and decompressing abstractions built on top of
 + the $(LINK2 http://www.zlib.net, zlib library).
 +
 + Authors: Jakub Łabaj, uaaabbjjkl@gmail.com
 +/
module dcompress.zlib;

debug = zlib;
debug(zlib)
{
    import std.stdio;
}

import c_zlib = etc.c.zlib;

/++
 + Status codes returned by zlib library.
 +/
private enum ZlibStatus
{
    ok = c_zlib.Z_OK,
    streamEnd = c_zlib.Z_STREAM_END,
    needDict = c_zlib.Z_NEED_DICT,
    errno = c_zlib.Z_ERRNO,
    streamError = c_zlib.Z_STREAM_ERROR,
    dataError = c_zlib.Z_DATA_ERROR,
    memoryError = c_zlib.Z_MEM_ERROR,
    bufferError = c_zlib.Z_BUF_ERROR,
    libVersionError = c_zlib.Z_VERSION_ERROR,
}

private string getErrorMessage(int status)
in
{
    // These are not errors.
    assert(status != ZlibStatus.ok);
    assert(status != ZlibStatus.streamEnd);
    assert(status != ZlibStatus.needDict);
}
body
{
     switch(status)
     {
        case ZlibStatus.bufferError:
            return "Buffer error";
        case ZlibStatus.streamError:
            return "Stream error";
        case ZlibStatus.dataError:
            return "Data error";
        case ZlibStatus.libVersionError:
            return "Incompatible zlib library version";
        case ZlibStatus.errno:
            return "Error outside the zlib library";
        default:
            return "Unknown error";
     }
}

/++
 + Exceptions thrown by this module on error.
 +/
class ZlibException : Exception
{
    this(int status)
    {
        super(getErrorMessage(status));
    }
}

/++
 + Compression methods supported by zlib library.
 +/
private enum CompressionMethod
{
    deflate = c_zlib.Z_DEFLATED,
}

/++
 + Selection of compression levels for convenience,
 + in fact all values from `-1` to `9` are supported.
 +/
enum CompressionLevel
{
    noCompression = c_zlib.Z_NO_COMPRESSION, ///
    bestSpeed = c_zlib.Z_BEST_SPEED, ///
    bestCompression = c_zlib.Z_BEST_COMPRESSION, ///
    default_ = c_zlib.Z_DEFAULT_COMPRESSION, ///
}

/++
 + Compression strategies used to tune the compression algorithm.
 +/
enum CompressionStrategy
{
    /// Best for data produced by a filter i.e. consisting mostly of small
    /// values with a somewhat random distribution. Forces more Huffman coding
    /// and less string matching, lies between `default_` and `huffmanOnly` strategies.
    filtered = c_zlib.Z_FILTERED,
    /// Forces Huffman encoding only, disabling entirely string matching.
    huffmanOnly = c_zlib.Z_HUFFMAN_ONLY,
    /// Designed to be almost as fast as `huffmanOnly`, but gives better compression
    /// for `PNG` image data.
    rle = c_zlib.Z_RLE,
    /// Prevents the use of dynamic Huffman codes, allowing for a simpler decoder
    /// for special applications.
    fixed = c_zlib.Z_FIXED,
    /// Default strategy for regular data.
    default_ = c_zlib.Z_DEFAULT_STRATEGY,
}

/++
 + Supported headers for the compressed data.
 +
 + The library supports only one compression method called `deflate`, which may
 + be wrapped around with `zlib` or `gzip` headers, including integrity check
 + values.
 +
 + The `zlib` format was designed to be compact and fast, for use in memory and
 + on communications channels, makes use of `Adler-32` for integrity check.
 + The `gzip` format was designed for a single file compression on file systems,
 + has a larger header than `zlib` to maintain file information, and uses
 + a slower `CRC-32` check method.
 +/
enum DataHeader
{
    /// zlib wrapper around a deflate stream. See the specification
    /// $(LINK2 https://tools.ietf.org/html/rfc1950, RFC 1950).
    zlib,
    /// Raw deflate stream, without any header or check value. See the
    /// specification $(LINK2 https://tools.ietf.org/html/rfc1951, RFC 1951).
    rawDeflate,
    /// gzip wrapper around a deflate stream. See the specification
    /// $(LINK2 https://tools.ietf.org/html/rfc1952, RFC 1952).
    gzip,
    /// Automatic header detection - only for decompressing.
    automatic
}

/++
 + Returns window size value depending on the header. Used to initialize
 + a zlib stream:
 + * default = 15
 + * 9..15 - base 2 log of the window size
 + * -9..-15 - raw deflate, without zlib header or trailer and no crc
 + * 25..31 = 16 + (9..15) - low 4 bits of the value is the window size log,
 +                           while including a basic gzip header and checksum
 + * 41..47 = 32 + (9..15) - automatic header detection in decompressed data
 +/
private int getWindowBitsValue(int windowBits, DataHeader header)
in
{
    assert(9 <= windowBits && windowBits <= 15);
}
body
{
    final switch (header)
    {
        case DataHeader.zlib: return windowBits;
        case DataHeader.rawDeflate: return -windowBits;
        case DataHeader.gzip: return 16 + windowBits;
        case DataHeader.automatic: return 32 + windowBits;
    }
}

/++
 + Settings allowing to adjust the compression process.
 +/
struct CompressionPolicy
{
private:
    import std.typecons : Nullable;

    DataHeader _header = DataHeader.zlib;
    int _compressionLevel = CompressionLevel.default_;
    int _windowBits = 15;
    int _memoryLevel = 8;
    CompressionStrategy _strategy = CompressionStrategy.default_;
    Nullable!(ubyte[]) _buffer;
    size_t _defaultBufferSize = 1024;
    size_t _maxInputChunkSize = 1024;

public:

    /++
     + Returns the policy with options set to zlib defaults and buffer set to
     + empty `Nullable` (see `buffer` for details).
     +
     + Default settings:
     + $(OL
     +     $(LI `header = DataHeader.zlib`)
     +     $(LI `compressionLevel = CompressionLevel.default_`)
     +     $(LI `windowBits = 15`)
     +     $(LI `memoryLevel = 8`)
     +     $(LI `strategy = CompressionStrategy.default_`)
     +     $(LI `buffer.isEmpty == true`)
     +     $(LI `defaultBufferSize = 1024`)
     +     $(LI `inputChunkSize = 1024`)
     + )
     +/
    static CompressionPolicy defaultPolicy()
    {
         return CompressionPolicy.init;
    }

    /++
     + Specifies the default buffer size being allocated by compressing
     + functions when `buffer.isNull == true`.
     +
     + Returns: The current default size for the buffer.
     +/
    @property size_t defaultBufferSize()
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
     + Specifies the maximum chunk size when an input cannot be compressed
     + directly but needs to be copied into a temporary array.
     +
     + Returns: The current maximum input chunk size.
     +/
    @property size_t maxInputChunkSize()
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
     + Header to wrap the compressed data with. See `DataHeader` for details.
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
     + Controls the level of compression.
     +
     + `0` means no compression at all, `1` gives the best speed but poor
     + compression, `9` gives the best compression, but is slow.
     + `-1` is a default compromise between speed and compression
     + (currently equivalent to level 6).
     +
     + Returns: A number between `-1` and `9` indicating the compression level.
     +/
    @property int compressionLevel() const
    {
         return _compressionLevel;
    }

    /++
     + Sets the compression level to the given value.
     +
     + Params:
     + newLevel = New compression level, must be a number from `-1` to `9`.
     +/
    @property void compressionLevel(int newLevel)
    in
    {
        assert(-1 <= newLevel && newLevel <= 9);
    }
    body
    {
         _compressionLevel = newLevel;
    }

    /++
     + Controls the size of the history buffer (i.e. window size) used when
     + compressing data.
     +
     + Returns: A number between `9` and `15` being a base `2` logarithm of
     +          the current window size.
     +/
    @property int windowBits() const
    {
        return _windowBits;
    }

    /++
     + Sets the window size.
     +
     + Params:
     + newWindowBits = New base `2` logarithm of the window size. Must be
     +                 a number from `9` (`512`-byte window) to `15`
     +                 (`32`KB window - default).
     +/
    @property void windowBits(int newWindowBits)
    in
    {
        assert(9 <= newWindowBits && newWindowBits <= 15);
    }
    body
    {
         _windowBits = newWindowBits;
    }

    /++
     + Stores in one value the window size and header, according to the zlib
     + specification. Used to initialize the zlib library compression process.
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
     + Specifies how much memory should be allocated for the internal
     + compression state of the zlib library.
     +
     + It is a number from `1` - using minimum memory but slow and reducing
     + compression ratio, to `9` - using maximum memory for the best speed
     + and compression. The default value is `8`.
     +
     + The approximate memory requirements are (in bytes):
     + $(UL
     +     $(LI for compression: `(1 << (windowBits + 2)) + (1 << (memLevel + 9))`
     +       plus a few kilobytes for small objects.)
     +     $(LI for decompression: `(1 << windowBits)` plus about `7`KB.)
     + )
     + Returns: The current memory level.
     +/
    @property int memoryLevel() const
    {
         return _memoryLevel;
    }

    /++
     + Sets the memory level to the given value.
     +
     + Params:
     + newLevel = New memory level value.
     +/
    @property void memoryLevel(int newLevel)
    in
    {
        assert(1 <= newLevel && newLevel <= 9);
    }
    body
    {
         _memoryLevel = newLevel;
    }

    /++
     + Tunes the compression algorithm. See `CompressionStrategy` for details.
     +
     + Returns: The current compression strategy.
     +/
    @property CompressionStrategy strategy() const
    {
         return _strategy;
    }

    /++
     + Sets the compression strategy to the given value.
     +
     + Params:
     + newStrategy = New strategy value.
     +/
    @property void strategy(CompressionStrategy newStrategy)
    {
         _strategy = newStrategy;
    }

    /++
     + Gets the buffer serving as an intermediate output for the compressed data.
     +
     + Returns: The current buffer.
     +/
    @property inout(Nullable!(ubyte[])) buffer() inout
    {
        return _buffer;
    }

    /++
     + Sets the buffer to the given value.
     +
     + If `null`-state buffer is passed, i.e. `buffer.isNull == true`,
     + functions using the policy will allocate the buffer according to their
     + specification, for example `compress(void[])` reserves enough memory
     + to fit the whole compressed data at once, whereas other functions usually
     + allocate buffer with size equal to `defaultBufferSize`.
     +
     + If `newBuffer` is not in `null` state, then the underlying array should
     + not be empty.
     +
     + Params:
     + newBuffer = A `Nullable` array to be set as the buffer.
     +/
    @property void buffer(Nullable!(ubyte[]) newBuffer)
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
    @property void buffer(ubyte[] newBuffer)
    in
    {
        assert(newBuffer.length > 0);
    }
    body
    {
        import std.typecons : nullable;
        _buffer = newBuffer.nullable;
    }
}

/++
 + A structure used to compress data incrementally. For one-shot compression,
 + use `compress` function.
 +
 + All the compressed data produced by calls to `compress`, `compressPending`
 + and `flush` should be concatenated together.
 +
 + `Compressor` keeps an internal buffer of fixed size for the compressed data
 + produced the zlib library. The compressing methods return a slice of this
 + internal buffer which means that the buffer is being modified between calls,
 + but also no memory allocations are performed directly by any of the methods.
 +/
struct Compressor
{
private:

    c_zlib.z_stream _zlibStream;
    CompressionPolicy _policy;
    bool _outputPending;

public:

    /++
     + Modifies behavior of `Compressor.flush`.
     +
     + Note: Frequent flushing may seriously degrade the compression.
     +/
    enum FlushMode
    {
        /// All pending output is flushed and the output is aligned on a byte
        /// boundary so that all the available input so far will be processed
        /// (assuming enough space in the output buffer).
        sync    = c_zlib.Z_SYNC_FLUSH,
        /// All output is flushed as with `FlushMode.sync` and the compression
        /// state is reset so that decompression can restart from this point,
        /// e.g. if previous compressed data has been damaged or if random
        /// access is desired.
        full    = c_zlib.Z_FULL_FLUSH,
        /// Default mode. Used to correctly finish the compression process.
        finish  = c_zlib.Z_FINISH,
        /// A deflate block is completed and emitted, as for `FlushMode.sync`,
        /// except the output is not aligned on a byte boundary and up to seven
        /// bits of the current block may be held to be written as the next byte
        /// until the next deflate block is completed. In this case, the
        /// compressor may need to wait for more input for the next block to be
        /// emitted. This is for advanced applications that need to control the
        /// emission  of deflate blocks.
        block   = c_zlib.Z_BLOCK,
        /// No flushing mode, allows decide how much data to accumulate before
        /// producing output, in order to maximize compression. `flush` called
        /// with this mode is equivalent to `compressPending`.
        noFlush = c_zlib.Z_NO_FLUSH,
    }

    @disable this();

    private this(CompressionPolicy policy)
    {
        immutable status = c_zlib.deflateInit2(
            &_zlibStream,
            policy.compressionLevel,
            CompressionMethod.deflate,
            policy.windowBitsWithHeader,
            policy.memoryLevel,
            policy.strategy);

        if (status != ZlibStatus.ok)
            throw new ZlibException(status);
    }

    /++
     + Creates a compressor with the given settings.
     +
     + If `policy.buffer.isNull`, it will be allocated with size equal to
     + `CompressionPolicy.defaultBufferSize`.
     +
     + Params:
     + policy = A policy defining different aspects of the compression process.
     +
     + Throws: `ZlibException` if unable to initialize the zlib library, e.g.
     +         there is no enough memory or the library version is incompatible.
     +/
    static Compressor create(CompressionPolicy policy = CompressionPolicy.defaultPolicy)
    in
    {
        assert(policy.header != DataHeader.automatic);
    }
    body
    {
        auto comp = Compressor(policy);

        if (policy.buffer.isNull)
        {
            import std.typecons : nullable;
            policy.buffer = nullable(new ubyte[policy.defaultBufferSize]);
        }
        comp._policy = policy;

        return comp;
    }

    /++
     + Creates a compressor with the given settings and allocates buffer to
     + a size sufficient to fit the compressed data assuming a one-shot
     + compression of input with size equal to `inputLength`.
     +
     + The `policy.buffer` will not be touched if it has already a sufficient
     + size, otherwise it will be reallocated.
     +
     + Params:
     + inputLength = Length of an input to be compressed later on at once.
     + policy = A policy defining different aspects of the compression process.
     +
     + Throws: `ZlibException` if unable to initialize the zlib library, e.g.
     +         there is no enough memory or the library version is incompatible.
     +/
    static Compressor createWithSufficientBuffer(size_t inputLength,
        CompressionPolicy policy = CompressionPolicy.defaultPolicy)
    in
    {
        assert(policy.header != DataHeader.automatic);
    }
    body
    {
        auto comp = Compressor(policy);

        immutable minBufferSize = comp.getCompressedSizeBound(inputLength);

        if (policy.buffer.isNull)
        {
            import std.typecons : nullable;
            policy.buffer = nullable(new ubyte[minBufferSize]);
        }
        else if (policy.buffer.get.length < minBufferSize)
        {
            policy.buffer.get.length = minBufferSize;
        }
        comp._policy = policy;

        return comp;
    }

    ~this()
    {
        c_zlib.deflateEnd(&_zlibStream);
    }

    /++
     + Gets the current policy used during the compression process.
     +
     + Returns: The current compression policy.
     +/
    @property const(CompressionPolicy) policy() const
    {
        return _policy;
    }


    /++
     + Gets the current internal array buffer. Note that the buffer does not
     + remember where the compressed data ends.
     +
     + Returns: The current internal buffer.
     +/
    private @property ubyte[] buffer()
    {
         return _policy.buffer.get;
    }

    /++
     + Checks if there is compressed data available to retrieve without
     + providing more input.
     +
     + `true` effectively means that there wasn't enough space in the buffer to
     + fit all the compressed data at once and more steps are needed to transfer
     + it. This can be done either by calling `compressPending` or `flush`.
     +
     + Returns: `true` if there is compressed data available, `false` otherwise.
     +/
    @property bool outputPending() const
    {
        return _outputPending;
    }

    /++
     + Checks how many complete bytes of the compressed data is available to
     + retrieve without providing more input.
     +
     + It can be done either by calling `compressPending` or `flush`.
     +
     + Note: There may be more compressed bytes kept internally by the zlib
     +       library, so this method does not give good estimate of the total
     +       data size that is to be produced.
     +
     + Returns: The number of compressed bytes that can be obtained without
     +          providing additional input.
     +/
    @property uint bytesPending() const
    {
        uint bytes;
        // Casting away const here is safe as deflatePending does not modify the stream.
        immutable status = c_zlib.deflatePending(cast(c_zlib.z_stream*) &_zlibStream, &bytes, null);
        // This structure ensures a consistent state of the stream.
        assert(status == ZlibStatus.ok);
        return bytes;
    }

    /++
     + Checks if the last input has been completely processed.
     +
     + `true` means more input data can be safely provided for compression.
     +
     + Note: There still may be compressed data available to retrieve by calling
     +       `compressPending` or `flush`, without the need to provide more input.
     +
     + Returns: `true` if the input has been processed, `false` otherwise.
     +/
    @property bool inputProcessed() const
    {
         return _zlibStream.avail_in == 0;
    }

    /++
     + Only sets the input to be compressed in the next call `compressPending`
     + or `flush`, without advancing the compression process.
     +
     + Note: The previous input that has not been fully processed is overriden.
     +
     + Params:
     + data = An input data to be compressed.
     +/
    @property void input(const(void)[] data)
    {
        _zlibStream.next_in = cast(const(ubyte)*) data.ptr;
        _zlibStream.avail_in = cast(uint) data.length; // TODO check for overflow
    }

    /++
     + Provides more data to be compressed and proceeds with the compression.
     +
     + This method is an equivalent of the following code:
     +
     + ---
     + input = data;
     + return compressPending();
     + ---
     +
     + If there is no enough space in the buffer for the compressed data then
     + `outputPending` will become `true`. The `data` should be completely
     +  processed, i.e. `inputProcessed == true`, before the next invocation
     +  of this method, otherwise the compression process may be broken.
     +
     + Params:
     + data = An input data to be compressed.
     +
     + Returns: Slice of the internal buffer with the compressed data.
     +
     + Throws: `ZlibException` if the zlib library returns error. It may happen
     +          especially when `compress` is being called after `flush`
     +          while `outputPending == true`.
     +/
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

    /++
     + Retrieves the remaining compressed data that didn't fit into the internal
     + buffer during call to `compress` and continues to compress the input.
     +
     + Note: Check `inputProcessed` to see if additional calls are required to
     +       fully retrieve the data before providing more input.
     +
     + Returns: Slice of the internal buffer with the compressed data.
     +
     + Throws: `ZlibException` if the zlib library returns error. It may happen
     +          especially when `compressPending` is being called after `flush`
     +          while `outputPending == true`.
     +/
    const(void)[] compressPending()
    {
        return compress(FlushMode.noFlush);
    }

    /++
     + Flushes the remaining compressed data.
     +
     + Note: Repeat invoking this method with the same `mode` argument until
     +       `outputPending == false`, otherwise the compression may be invalid
     +       and exception may be thrown.
     +
     + Params:
     + mode = Mode to be applied for flushing. See `FlushMode` for details.
     +
     + Returns: Slice of the internal buffer with the compressed data.
     +
     + Throws: `ZlibException` if the zlib library returns error. It may happen
     +         especially when `flush` is being called again with different
     +         `mode` argument while `outputPending == true`.
     +/
    const(void)[] flush(FlushMode mode = FlushMode.finish)
    {
        return compress(mode);
    }

    private const(void)[] compress(FlushMode mode)
    {
        _zlibStream.next_out = buffer.ptr;
        _zlibStream.avail_out = cast(uint) buffer.length;

        debug(zlib) {
            import std.stdio;
            writefln("In bytes: %d, Out bytes: %d", _zlibStream.avail_in, _zlibStream.avail_out);
        }

        // * ZlibStatus.ok -- progress has been made
        // * ZlibStatus.bufferError -- no progress possible
        // * ZlibStatus.streamEnd -- all input has been consumed and all output
        //   has been produced (only when mode == FlushMode.finish)
        auto status = c_zlib.deflate(&_zlibStream, mode);

        if (status == ZlibStatus.ok)
        {
            if (mode == FlushMode.finish)
                _outputPending = true;
            else
                _outputPending = (_zlibStream.avail_out == 0 && bytesPending > 0);
        }
        else
        {
            // TODO Think whether output buffer can be corrupted.
            assert(status != ZlibStatus.bufferError);

            if (status == ZlibStatus.streamEnd)
            {
                _outputPending = false;
                status = c_zlib.deflateReset(&_zlibStream);
                assert(status == ZlibStatus.ok);
            }
            else
            {
                throw new ZlibException(status);
            }
        }

        immutable writtenBytes = buffer.length - _zlibStream.avail_out;
        return buffer[0 .. writtenBytes];
    }
}

/++
 + Get an upper bound of the compressed data size. It gives a correct estimate
 + only when called on just created `Compressor` and when all the data will be
 + compressed at once.
 +/
private size_t getCompressedSizeBound(ref Compressor comp, size_t inputLength)
{
    return c_zlib.deflateBound(&comp._zlibStream, inputLength);
}

/++
 + Compresses all the bytes at once using the given compression policy.
 +
 + Params:
 + data = Bytes to be compressed.
 + policy = A policy defining different aspects of the compression process.
 +
 + Returns: Compressed data.
 +
 + Throws: `ZlibException` if any error occurs.
 +/
void[] compress(const(void)[] data, CompressionPolicy policy = CompressionPolicy.defaultPolicy)
{
    debug(zlib) writeln("compress!void[]");

    auto comp = Compressor.createWithSufficientBuffer(data.length, policy);
    comp.input = data;
    return cast(void[]) comp.flush();
}

import dcompress.primitives : isCompressInput, isCompressOutput;

/++
 + ditto
 +/
void[] compress(InR)(InR data, CompressionPolicy policy = CompressionPolicy.defaultPolicy)
if (isCompressInput!InR)
{
    debug(zlib) writeln("compress!Range");

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

                auto comp = Compressor.createWithSufficientBuffer(data.length, policy);
                auto input = new ubyte[data.length];
                import std.range.mutation : copy;
                copy(data, input);
                comp.input = input;
                return comp.flush();
            }
        }
        void[] output;
        auto comp = Compressor.create(policy);
        comp.compressAllByCopyChunk(data, output);
        return output;
    }
    else // isArray!(ElementType!InR)
    {
        debug(zlib) writeln("isArray!(ElementType!InR)");

        void[] output;
        auto comp = Compressor.create(policy);
        comp.compressAllByChunk(data, output);
        return output;
    }
}

/++
 + Compresses all the bytes using the given compression policy and outputs
 + the compressed data directly to `output`.
 +
 + Params:
 + data = Bytes to be compressed.
 + output = Output range taking the compressed bytes.
 + policy = A policy defining different aspects of the compression process.
 +
 + Throws: `ZlibException` if any error occurs.
 +/
void compress(OutR)(const(void)[] data, ref OutR output, CompressionPolicy policy = CompressionPolicy.defaultPolicy)
if (isCompressOutput!OutR)
{
    debug(zlib) writeln("compress!(void[], OutputRange)");

    import std.traits : Unqual, isArray;
    static if (isArray!OutR)
    {
        debug(zlib) writeln("isArray!OutR");

        if (policy.buffer.isNull)
        {
            // The output will be directly reallocated this way.
            policy.buffer = output;
        }
        auto comp = Compressor.createWithSufficientBuffer(data.length, policy);
        comp.input = data;
        output = cast(OutR) comp.flush();
    }
    else
    {
        debug(zlib) writeln("isArray!OutR == false");

        auto comp = Compressor.create(policy);
        immutable minBufferSize = comp.getCompressedSizeBound(data.length);
        if (minBufferSize <= comp.buffer.length)
        {
            import std.range.mutation : copy;
            comp.input = data;
            comp.flush().copy(output);
        }
        else
        {
            comp.compressAll(data, output);
            comp.flushAll(output);
        }
    }
}

/++
 + ditto
 +/
void compress(InR, OutR)(InR data, ref OutR output, CompressionPolicy policy = CompressionPolicy.defaultPolicy)
if (isCompressInput!InR && isCompressOutput!OutR)
{
    debug(zlib) writeln("compress!(InputRange, OutputRange)");

    import std.range.primitives : ElementType;
    import std.traits : Unqual, isArray;
    static if (is(Unqual!(ElementType!InR) == ubyte))
    {
        debug(zlib) writeln("ElementType!InR == ubyte");

        import std.range.primitives : hasLength;
        static if (hasLength!InR)
        {
            if (policy.maxInputChunkSize >= data.length)
            {
                debug(zlib) writeln("hasLength!InR && policy.maxInputChunkSize >= data.length");

                import std.range.mutation : copy;
                auto input = new ubyte[data.length];
                copy(data, input);
                compress(input, output, policy);
                return;
            }
        }
        auto comp = Compressor.create(policy);
        comp.compressAllByCopyChunk(data, output);
    }
    else // isArray!(ElementType!InR)
    {
        debug(zlib) writeln("isArray!(ElementType!InR)");

        auto comp = Compressor.create(policy);
        comp.compressAllByChunk(data, output);
    }
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
    immutable chunkSize = comp.policy.maxInputChunkSize;
    ubyte[] chunk = new ubyte[chunkSize];
    while (!data.empty)
    {
        foreach (i; 0 .. chunkSize)
        {
            chunk[i] = data.front;
            data.popFront();
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
        output ~= comp.compress(data);
        while (!comp.inputProcessed)
            output ~= comp.compressPending();
    }
    else
    {
        import std.range.primitives : put;
        put(output, comp.compress(data));
        while (!comp.inputProcessed)
            put(output, comp.compressPending());
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
            output ~= comp.flush();
        }
        else
        {
            import std.range.primitives : put;
            put(output, comp.flush());
        }
    } while (comp.outputPending);
}
