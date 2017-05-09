/++
 + Provides compressing and decompressing abstractions built on top of
 + the $(LINK2 http://www.zlib.net, zlib library).
 +
 + Authors: Jakub Łabaj, uaaabbjjkl@gmail.com
 +/
module dcompress.zlib;

import c_zlib = etc.c.zlib;

/++
 + Modifies behavior of `Compressor.flush`.
 +/
enum FlushMode
{
    noFlush = c_zlib.Z_NO_FLUSH, ///
    partial = c_zlib.Z_PARTIAL_FLUSH, ///
    sync    = c_zlib.Z_SYNC_FLUSH, ///
    full    = c_zlib.Z_FULL_FLUSH, ///
    finish  = c_zlib.Z_FINISH, ///
    block   = c_zlib.Z_BLOCK, ///
    trees   = c_zlib.Z_TREES, ///
}

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
}

/++
 + A structure used to compress data incrementally.
 + For one-shot compression, use `dcompress.zlib.compress` function.
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

    int getWindowBitsValue(int windowBits, DataHeader header)
    {
        final switch (header)
        {
            case DataHeader.zlib: return windowBits;
            case DataHeader.rawDeflate: return -windowBits;
            case DataHeader.gzip: return 16 + windowBits;
        }
    }

    void throwException(ZlibStatus status)
    {
        // TODO status description
        throw new Exception("Error");
    }

    void checkForError(int status)
    {
        if (status != ZlibStatus.ok)
        {
            // c_zlib.deflateEnd(&_zlibStream); // TODO think about it.
            import std.conv : to;
            throwException(to!ZlibStatus(status));
        }
    }

public:

    @disable this();

    /++
     + Creates a compressor with the given settings.
     +
     + Params:
     + bufferSize = The internal buffer size in bytes. Indicates the upper limit
     +              of compressed data that may be returned by one call to
     +              `compress`, `compressPending` and `flush`.
     + header = Header to use for the compressed data. See `DataHeader` for details.
     + compressionLevel = A number between `-1` and `9`: `0` indicates no
     +                    compression at all, `1` gives the best speed but poor
     +                    compression, `9` gives the best compression, but is slow,
     +                    `-1` is a default compromise between speed and compression
     +                    (currently equivalent to level 6).
     + windowBits = Controls the size of the history buffer (i.e. window size)
     +              used when compressing data. It is the base `2` logarithm of
     +              window size. Must be a number from `9` (`512`-byte window)
     +              to `15` (`32`KB window - default).
     + memoryLevel = Specifies how much memory should be allocated for the
     +               internal compression state of the zlib library. Must be
     +               a number from `1` - uses minimum memory but is slow and
     +               reduces compression ratio, to `9` - using maximum memory
     +               for the best speed and compression. The default value
     +               is `8`. The approximate memory requirements are (in bytes):
     +               `(1 << (windowBits+2)) + (1 << (memLevel+9))` plus a few
     +               kilobytes for small objects.
     + strategy = Tunes the compression algorithm. See `CompressionStrategy` for details.
     +/
    this(uint bufferSize,
        DataHeader header = DataHeader.zlib,
        int compressionLevel = CompressionLevel.default_,
        int windowBits = 15,
        int memoryLevel = 8,
        CompressionStrategy strategy = CompressionStrategy.default_)
    in
    {
        assert (-1 <= compressionLevel && compressionLevel <= 9);
        assert (9 <= windowBits && windowBits <= 15);
        assert (1 <= memoryLevel && memoryLevel <= 9);
    }
    body
    {
        _buffer = new ubyte[bufferSize];
        // int deflateInit2(z_streamp strm, int level, int method, int windowBits, int memLevel, int strategy);
        // * windowsBits:
        //     default = 15
        //     8 - not supported
        //     9..15 - base 2 log of the window size
        //     -9..-15 - raw deflate, without zlib header or trailer and no crc
        //     25..31 = 16 + (9..15) - low 4 bits of the value is the window size log,
        //                             while including a basic gzip header and trailing checksum
        // The memory requirements for inflate are (in bytes):
        //     1 << windowBits + ~7KB
        immutable windowBitsValue = getWindowBitsValue(windowBits, header);
        immutable status = c_zlib.deflateInit2(&_zlibStream, compressionLevel,
            CompressionMethod.deflate,
            windowBitsValue, memoryLevel, strategy);
        checkForError(status);
    }

    ~this()
    {
        c_zlib.deflateEnd(&_zlibStream);
        // import core.memory : GC;
        // GC.free(_buffer.ptr);
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
        assert (status == ZlibStatus.ok);
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
     +/
    const(void)[] compress(const(void)[] data)
    in
    {
        // Ensure no leftovers from previous calls.
        assert (inputProcessed);
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
     +/
    const(void)[] compressPending()
    {
        return compress(FlushMode.noFlush);
    }

    /++
     + Flushes the remaining compressed data.
     +
     + Note: Calls should be repeated with the same `mode` argument until
     +       `outputPending == false`, otherwise the stream will corrupt and
     +       an exception will be thrown.
     +
     + Params:
     + mode = Mode to be applied for flushing. See `FlushMode` for details.
     +
     + Returns: Slice of the internal buffer with the compressed data.
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
        immutable status = c_zlib.deflate(&_zlibStream, mode);

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
            assert (status != ZlibStatus.bufferError);

            if (status == ZlibStatus.streamEnd)
            {
                _outputPending = false;
                // TODO deflateReset or deflateEnd
            }
            else
            {
                import std.conv : to;
                throwException(to!ZlibStatus(status));
            }
        }

        immutable writtenBytes = _buffer.length - _zlibStream.avail_out;
        return _buffer[0 .. writtenBytes];
    }
}
