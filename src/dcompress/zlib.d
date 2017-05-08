module dcompress.zlib;

import c_zlib = etc.c.zlib;

enum FlushMode
{
    noFlush = c_zlib.Z_NO_FLUSH,
    partial = c_zlib.Z_PARTIAL_FLUSH,
    sync    = c_zlib.Z_SYNC_FLUSH,
    full    = c_zlib.Z_FULL_FLUSH,
    finish  = c_zlib.Z_FINISH,
    block   = c_zlib.Z_BLOCK,
    trees   = c_zlib.Z_TREES,
}

enum ZlibStatus
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

enum CompressionMethod
{
    deflate = c_zlib.Z_DEFLATED,
}

enum CompressionLevel
{
    noCompression = c_zlib.Z_NO_COMPRESSION,
    bestSpeed = c_zlib.Z_BEST_SPEED,
    bestCompression = c_zlib.Z_BEST_COMPRESSION,
    default_ = c_zlib.Z_DEFAULT_COMPRESSION,
}

enum CompressionStrategy
{
    filtered = c_zlib.Z_FILTERED,
    huffman = c_zlib.Z_HUFFMAN_ONLY,
    rle = c_zlib.Z_RLE,
    fixed = c_zlib.Z_FIXED,
    default_ = c_zlib.Z_DEFAULT_STRATEGY,
}

enum CompressionEncoding
{
    deflate,
    rawDeflate,
    gzip,
}

struct Compressor
{
private:

    c_zlib.z_stream _zlibStream;
    ubyte[] _buffer;
    bool _outputPending;

    int getWindowBitsValue(int windowBits, CompressionEncoding encoding)
    {
        final switch (encoding)
        {
            case CompressionEncoding.deflate: return windowBits;
            case CompressionEncoding.rawDeflate: return -windowBits;
            case CompressionEncoding.gzip: return 16 + windowBits;
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

    this(uint bufferSize,
        CompressionEncoding encoding = CompressionEncoding.deflate,
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
        // * memLevel:
        //     default = 8
        //     1..9 - minimum memory + slow .. maximum memory + best speed
        // The memory requirements for deflate are (in bytes):
        //     (1 << (windowBits+2)) + (1 << (memLevel+9)) + 'a few'KB
        // The memory requirements for inflate are (in bytes):
        //     1 << windowBits + ~7KB
        immutable windowBitsValue = getWindowBitsValue(windowBits, encoding);
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

    @property bool outputPending() const
    {
        return _outputPending;
    }

    @property uint bytesPending() const
    {
        uint bytes;
        // Casting away const here is safe as deflatePending does not modify the stream.
        immutable status = c_zlib.deflatePending(cast(c_zlib.z_stream*)&_zlibStream, &bytes, null);
        // This structure ensures a consistent state of the stream.
        assert (status == ZlibStatus.ok);
        return bytes;
    }

    @property bool needsInput() const
    {
        return _zlibStream.avail_in == 0 && !outputPending;
    }

    const(void)[] compress(const(void)[] data)
    in
    {
        // Ensure no leftovers from previous calls.
        assert (needsInput);
    }
    body
    {
        _zlibStream.next_in = cast(const(ubyte)*) data.ptr;
        _zlibStream.avail_in = cast(uint) data.length; // TODO check for overflow
        return compress(FlushMode.noFlush);
    }

    const(void)[] compressPending()
    {
        return compress(FlushMode.noFlush);
    }

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
        // * ZlibStatus.streamEnd -- all input has been consumed and all output has been produced (only when mode == FlushMode.finish)
        immutable status = c_zlib.deflate(&_zlibStream, mode);

        if (status == ZlibStatus.ok)
            _outputPending = (_zlibStream.avail_out == 0 && bytesPending > 0);
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
