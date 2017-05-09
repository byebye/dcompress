/++
 + Provides compressing and decompressing abstractions built on top of
 + the $(LINK2 http://www.zlib.net, zlib library).
 +
 + Authors: Jakub Łabaj, uaaabbjjkl@gmail.com
 +/
module dcompress.zlib;

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
            return "Error outside the library";
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
 + be wrapped around with `zlib` or `gzip` headers.
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
    /// Automatic header detection for decompressing functions.
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
    DataHeader _header = DataHeader.zlib;
    int _compressionLevel = CompressionLevel.default_;
    int _windowBits = 15;
    int _memoryLevel = 8;
    CompressionStrategy _strategy = CompressionStrategy.default_;

public:

    static CompressionPolicy defaultPolicy()
    {
         return CompressionPolicy.init;
    }

    /++
     + Header to wrap the compressed data. See `DataHeader` for details.
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
    ubyte[] _buffer;
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

    /++
     + Creates a compressor with the given settings.
     +
     + Params:
     + buffer = The internal buffer which serves as an output for the compressed
     +          data.
     + policy = A policy defining different aspects of the compression process.
     +
     + Throws: `ZlibException` if unable to initialize the zlib library, e.g.
     +         there is no enough memory or the library version is incompatible.
     +/
    this(ubyte[] buffer, CompressionPolicy policy = CompressionPolicy.defaultPolicy)
    in
    {
        assert(policy.header != DataHeader.automatic);
    }
    body
    {
        _buffer = buffer;
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

    ~this()
    {
        c_zlib.deflateEnd(&_zlibStream);
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
        immutable status = c_zlib.deflatePending(cast(c_zlib.z_stream*)&_zlibStream, &bytes, null);
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
     + Provides more data to be compressed.
     +
     + If there is no enough space in the buffer for the compressed data then
     + `outputPending` will become `true`. The `data` must be completely
     +  processed, i.e. `inputProcessed == true`, before the next invocation
     +  of this method.
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
        _zlibStream.next_in = cast(const(ubyte)*) data.ptr;
        _zlibStream.avail_in = cast(uint) data.length; // TODO check for overflow
        return compress(FlushMode.noFlush);
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
        _zlibStream.next_out = _buffer.ptr;
        _zlibStream.avail_out = cast(uint) _buffer.length;

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

        immutable writtenBytes = _buffer.length - _zlibStream.avail_out;
        return _buffer[0 .. writtenBytes];
    }
}

/++
 + Compresses at once all the bytes using the given compression policy.
 +
 + Params:
 + data = Bytes to be compressed.
 + poicy = A policy defining different aspects of the compression process.
 +
 + Returns: Compressed data.
 +
 + Throws: `ZlibException` if any error occurs.
 +/
void[] compress(const(void)[] data, CompressionPolicy policy = CompressionPolicy.defaultPolicy)
{
    return new void[0];
}

/++
 + ditto
 +/
void[] compress(R)(R data, CompressionPolicy policy = CompressionPolicy.defaultPolicy)
if (isCompressInput!R)
{
    return new void[0];
}

/++
 + Compresses all the bytes using the given compression policy and outputs
 + the compressed data directly to `output`.
 +
 + Params:
 + data = Bytes to be compressed.
 + output = Output range taking the compressed bytes.
 + poicy = A policy defining different aspects of the compression process.
 +
 + Throws: `ZlibException` if any error occurs.
 +/
void compress(R)(const(void)[] data, R output, CompressionPolicy policy = CompressionPolicy.defaultPolicy)
if (isCompressOutput!R)
{

}

/++
 + ditto
 +/
void compress(InR, OutR)(InR data, OutR output, CompressionPolicy policy = CompressionPolicy.defaultPolicy)
if (isCompressInput!InR && isCompressOutput!OutR)
{
}
