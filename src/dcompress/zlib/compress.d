/++
 + Provides compressing abstractions for zlib format.
 +/
module dcompress.zlib.compress;

debug = zlib;
debug(zlib)
{
    import std.stdio;
}

import c_zlib = etc.c.zlib;
public import dcompress.zlib.common;

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

struct GzipHeader
{
private:
    c_zlib.gz_header _header;
    string _filename;
    string _comment;
    void[] _data;

public:

    enum FileSystem
    {
        fat = 0,
        amiga = 1,
        vms = 2,
        unix = 3,
        vm = 4,
        atari = 5,
        hpfs = 6,
        mac = 7,
        zSystem = 8,
        cpm = 9,
        tops20 = 10,
        ntfs = 11,
        qdos = 12,
        acorn = 13,
        unknown = 255,
    }

    this(string name)
    {
        filename = name;
    }

    @property void isTextFile(bool value)
    {
        _header.text = value;
    }

    @property void modificationTime(long time)
    {
        _header.time = time;
    }

    @property void fileSystem(FileSystem fs)
    {
        _header.os = fs;
    }

    @property void extraData(void[] data)
    in
    {
        assert(data.length < 4 * 1024 ^^ 3);
    }
    body
    {
        _data = data;
        _header.extra = cast(byte*) data.ptr;
        _header.extra_len = cast(int) data.length;
    }

    @property void filename(string name)
    {
        _filename = name;
        import std.string : toStringz;
        _header.name = cast(byte*) _filename.toStringz;
    }

    @property void comment(string comm)
    {
        _comment = comm;
        import std.string : toStringz;
        _header.comment = cast(byte*) comm.toStringz;
    }

    @property void includeCrc(bool value)
    {
        _header.hcrc = value;
    }
}

/++
 + Keeps settings allowing to adjust the compression process.
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
    Nullable!(void[]) _buffer;
    size_t _defaultBufferSize = 1024;
    size_t _maxInputChunkSize = 1024;
    GzipHeader* _gzipHeader;

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
    static CompressionPolicy default_()
    {
        return CompressionPolicy.init;
    }

    static CompressionPolicy gzip()(GzipHeader* gzipHeader)
    {
        CompressionPolicy policy;
        policy.header = DataHeader.gzip;
        policy._gzipHeader = gzipHeader;
        return policy;
    }

    @property inout(c_zlib.gz_header)* gzipHeader() inout
    {
        return &_gzipHeader._header;
    }

    /++
     + Specifies the default buffer size being allocated by compressing
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
     + Specifies the maximum chunk size when an input cannot be compressed
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
    @property inout(Nullable!(void[])) buffer() inout
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

    import std.typecons : RefCounted, RefCountedAutoInitialize;

    RefCounted!(ZStreamWrapper, RefCountedAutoInitialize.no) _zStreamWrapper;
    CompressionPolicy _policy;

    inout(c_zlib.z_stream)* _zlibStream() inout
    {
        return &_zStreamWrapper.zlibStream;
    }

    @property ProcessingStatus _status() const
    {
        return _zStreamWrapper.status;
    }

    @property void _status(ProcessingStatus status)
    {
        _zStreamWrapper.status = status;
    }

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
        /// e.g. if previously compressed data has been damaged or if random
        /// access is desired.
        full    = c_zlib.Z_FULL_FLUSH,
        /// Default mode. Used to correctly finish the compression process i.e.
        /// all pending output is flushed and, unless the data is being
        /// compressed with `DataHeader.rawDeflate`, with CRC value appended.
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

    private this(ref CompressionPolicy policy)
    {
        _zStreamWrapper.refCountedStore.ensureInitialized;

        auto status = c_zlib.deflateInit2(
            _zlibStream,
            policy.compressionLevel,
            CompressionMethod.deflate,
            policy.windowBitsWithHeader,
            policy.memoryLevel,
            policy.strategy);

        if (status != ZlibStatus.ok)
            throw new ZlibException(status);

        if (policy.header == DataHeader.gzip)
        {
            assert(policy.gzipHeader !is null);
            status = c_zlib.deflateSetHeader(_zlibStream, policy.gzipHeader);

            if (status != ZlibStatus.ok)
                throw new ZlibException(status);
        }
    }

    /++
     + Creates a compressor with the given settings.
     +
     + If `policy.buffer.isNull`, it will be allocated with size equal to
     + `policy.defaultBufferSize`.
     +
     + Params:
     + policy = A policy defining different aspects of the compression process.
     +
     + Throws: `ZlibException` if unable to initialize the zlib library, e.g.
     +         there is no enough memory or the library version is incompatible.
     +/
    static Compressor create(CompressionPolicy policy = CompressionPolicy.default_)
    in
    {
        assert(policy.header != DataHeader.automatic);
    }
    body
    {
        auto comp = Compressor(policy);

        if (policy.buffer.isNull)
            policy.buffer = new ubyte[policy.defaultBufferSize];
        comp._policy = policy;

        return comp;
    }

    /++
     + Default policy forces allocation of the buffer during the creation.
     +/
    unittest
    {
        debug(zlib) writeln("Compressor.create -- default policy");
        auto comp = Compressor.create();
        auto policy = CompressionPolicy.default_;
        assert(policy.buffer.isNull);
        assert(comp.buffer.length == policy.defaultBufferSize);
    }

    /++
     + Configuration may be tweaked on behalf of a policy, especially serves
     + to provide a custom buffer.
     +/
    unittest
    {
        debug(zlib) writeln("Compressor.create -- custom buffer on heap");
        auto policy = CompressionPolicy.default_;
        auto buffer = new ubyte[10];
        policy.buffer = buffer;

        auto comp = Compressor.create(policy);
        assert(comp.buffer.ptr == buffer.ptr);
        assert(comp.buffer.length == buffer.length);

        debug(zlib) writeln("Compressor.create -- custom config and buffer on stack");
        ubyte[5] bufStatic;
        policy.buffer = bufStatic[];
        policy.compressionLevel = 2;

        auto compStatic = Compressor.create(policy);
        assert(compStatic.buffer.ptr == bufStatic.ptr);
        assert(compStatic.buffer.length == bufStatic.length);
        assert(compStatic.policy.compressionLevel == 2);

        // The previous Compressor's settings should not be modified.
        assert(comp.buffer.ptr == buffer.ptr);
        assert(comp.policy.compressionLevel == CompressionPolicy.default_.compressionLevel);
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
        CompressionPolicy policy = CompressionPolicy.default_)
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
            // Reallocate existing buffer.
            auto buffer = policy.buffer.get;
            buffer.length = minBufferSize;
            policy.buffer = buffer;
        }
        comp._policy = policy;

        return comp;
    }

    /++
     + One-shot compression may be done using `flush` assuming the buffer has enough space.
     +/
    // TODO more tests with different headers <-- create set of header to test.
    unittest
    {
        debug(zlib) writeln("Compressor.createWithSufficientBuffer -- one-shot compression");
        auto data = "Lorem ipsum dolor sit amet, consectetur adipiscing elit.";

        auto comp = Compressor.createWithSufficientBuffer(data.length);
        comp.input = data;
        auto compressed = comp.flush();

        assert(comp.buffer.length >= compressed.length);
        assert(comp.outputPending == false);

        import dcompress.zlib : decompress;
        assert(decompress(compressed) == data);
    }

    /++
     + If the buffer is already large enough, do not touch it.
     +/
    unittest
    {
        debug(zlib) writeln("Compressor.createWithSufficientBuffer -- do not reallocate large enough buffer");
        auto data = "Lorem ipsum dolor sit amet, consectetur adipiscing elit.";

        auto policy = CompressionPolicy.default_;
        policy.buffer = new ubyte[200];
        auto comp = Compressor.createWithSufficientBuffer(data.length, policy);

        assert(comp.buffer.ptr == policy.buffer.ptr);
        assert(comp.buffer.length == 200);
    }

    /++
     + Gets the current policy used during the compression process.
     +
     + Returns: The current compression policy.
     +/
    // TODO Consider returning a reference.
    @property ref const(CompressionPolicy) policy() const
    {
        return _policy;
    }

    /++
     + Gets the current internal array buffer. Note that the buffer does not
     + remember where the compressed data ends.
     +
     + Returns: The current internal buffer.
     +/
    private @property void[] buffer()
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
        return _status == ProcessingStatus.outputPending;
    }

    /++
     + Check whether there is output left from previous calls to `compress`.
     +/
    unittest
    {
        debug(zlib) writeln("Compressor.outputPending");
        auto data = "Lorem ipsum dolor sit amet, consectetur adipiscing elit. ";

        auto policy = CompressionPolicy.default_;
        // Very small buffer just for presentation purposes.
        policy.buffer = new ubyte[1];
        auto comp = Compressor.create(policy);

        auto output = comp.compress(data).dup;
        assert(output.length == 1);
        assert(comp.outputPending);
        // More compressed data without providing more input.
        output ~= comp.compressPending();
        assert(output.length == 2);
    }

    /++
     + Checks how many complete bytes of the compressed data is available to
     + retrieve without providing more input.
     +
     + The data can be retrieved by calling `compressPending` or `flush`.
     + Pending bytes may increase after call to `flush` as it forces the
     + compression of remaining data.
     +
     + Note: There may be more compressed bytes kept internally by the zlib
     +       library and not counted by this method, so it does not give good
     +       estimate of the total data size that is to be produced.
     +
     +
     + Returns: The number of compressed bytes that can be obtained without
     +          providing additional input.
     +/
    @property uint bytesPending() const
    {
        uint bytes;
        // Casting away const here is safe as deflatePending does not modify the stream.
        immutable status = c_zlib.deflatePending(cast(c_zlib.z_stream*) _zlibStream, &bytes, null);
        // This structure ensures a consistent state of the stream.
        assert(status == ZlibStatus.ok);
        return bytes;
    }

    /++
     + Check how much output is left from previous calls to `compress`.
     +/
    unittest
    {
        debug(zlib) writeln("Compressor.bytesPending");
        auto data = "Lorem ipsum dolor sit amet, consectetur adipiscing elit. ";

        auto policy = CompressionPolicy.default_;
        // Very small buffer just for presentation purposes.
        policy.buffer = new ubyte[1];
        auto comp = Compressor.create(policy);

        // zlib header which is returned immediately occupies 2 bytes.
        // More output may not be returned until additional input has been
        // provided - for a better compression.
        auto output = comp.compress(data).dup;
        assert(output.length == 1);
        assert(comp.bytesPending == 1);
        // More compressed data without providing more input.
        output ~= comp.compressPending();
        assert(output.length == 2);
        assert(comp.bytesPending == 0);
        // Force a return of the compressed data using `flush` (which still
        // will not fit in such a small buffer).
        output ~= comp.flush();
        assert(output.length == 3);
        assert(comp.bytesPending > 0);
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
     + Check if more data to compress may be provided safely.
     +/
    unittest
    {
        debug(zlib) writeln("Compressor.inputProcessed");
        auto data = "Lorem ipsum dolor sit amet, consectetur adipiscing elit. ";

        auto policy = CompressionPolicy.default_;
        // Very small buffer just for presentation purposes.
        policy.buffer = new ubyte[1];
        auto comp = Compressor.create(policy);

        // zlib header which is returned immediately occupies 2 bytes and
        // will delay the compression process.
        auto output = comp.compress(data).dup;
        assert(output.length == 1);
        assert(comp.inputProcessed == false);
        // Grabbing the 2-byte header allows to compress the input entirely
        // in the next call.
        output ~= comp.compressPending();
        output ~= comp.compressPending();
        assert(comp.inputProcessed);
    }

    /++
     + Typical use case while compressing multiple chunks of data.
     +/
    unittest
    {
        debug(zlib) writeln("Compressor.inputProcessed -- multiple chunks of data");
        auto data = ["Lorem ipsum", " dolor sit amet,", " consectetur", " adipiscing elit. "];

        auto policy = CompressionPolicy.default_;
        // Very small buffer just for testing purposes.
        policy.buffer = new ubyte[2];
        auto comp = Compressor.create(policy);

        void[] output;
        foreach (chunk; data)
        {
            output ~= comp.compress(chunk);
            while (!comp.inputProcessed)
                output ~= comp.compressPending();
        }
        do
        {
            output ~= comp.flush();
        } while (comp.outputPending);

        import dcompress.zlib : decompress;
        import std.range : join;
        assert(decompress(output) == data.join);
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
        _status = ProcessingStatus.outputPending;
    }

    /++
     + Setting the input may be used to force one-shot compression using `flush`,
     + although for this kind compression `compress` functions are implemented.
     +/
    unittest
    {
        debug(zlib) writeln("Compressor.input -- one-shot compression");
        auto data =  "Lorem ipsum dolor sit amet, consectetur adipiscing elit. ";

        auto comp = Compressor.create();
        comp.input = data;
        // Warning: for one-shot compression enough buffer space needs to be provided.
        auto output = comp.flush().dup;
        assert(comp.inputProcessed);
        assert(comp.outputPending == false);

        import dcompress.zlib : decompress;
        assert(decompress(output) == data);
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
     + Compress the provided data.
     +/
    unittest
    {
        debug(zlib) writeln("Compressor.compress");
        auto data =  "Lorem ipsum dolor sit amet, consectetur adipiscing elit. ";

        auto comp = Compressor.create();
        auto output = comp.compress(data).dup;
        assert(output.length > 0);

        // Warning: if not enough buffer space is provided, `inputProcessed`
        // and `outputPending` should be used for a safe compression.
        output ~= comp.flush();
        import dcompress.zlib : decompress;
        assert(decompress(output) == data);
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
     + Retrieve the remaining compressed data that didn't fit into the buffer.
     +/
    unittest
    {
        debug(zlib) writeln("Compressor.compressPending");
        auto data =  "Lorem ipsum dolor sit amet, consectetur adipiscing elit. ";

        auto policy = CompressionPolicy.default_;
        // Very small buffer just for testing purposes.
        policy.buffer = new ubyte[1];
        auto comp = Compressor.create(policy);

        // zlib header is returned immediately and occupies 2 bytes.
        auto output = comp.compress(data).dup;
        assert(output.length == 1);
        assert(comp.outputPending);
        output ~= comp.compressPending();
        assert(output.length == 2);
    }

    /++
     + Flushes the remaining compressed data and finishes compressing the input.
     +
     + Note: Repeat invoking this method with the same `mode` argument until
     +       `outputPending == false`, otherwise the compression may be invalid
     +       and exception may be thrown. After that the `Compressor` may be
     +       reused to compress more data.
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

    /++
     + Flush the remaining output.
     +/
    unittest
    {
        debug(zlib) writeln("Compressor.flush");
        auto data =  "Lorem ipsum dolor sit amet, consectetur adipiscing elit. ";

        auto comp = Compressor.create();

        // zlib header is returned immediately and occupies 2 bytes.
        auto output = comp.compress(data).dup;
        assert(output.length == 2);
        // Input processed but data not returned.
        assert(comp.inputProcessed);
        assert(comp.outputPending == false);

        // Warning: if not enough buffer space is provided, `inputProcessed`
        // and `outputPending` should be used for a safe compression.
        output ~= comp.flush();
        import dcompress.zlib : decompress;
        assert(decompress(output) == data);
    }

    /++
     + Flush should be repeated with same mode until `outputPending == false`.
     +/
    unittest
    {
        debug(zlib) writeln("Compressor.flush -- flush mode changed");
        auto data =  "Lorem ipsum dolor sit amet, consectetur adipiscing elit. ";

        auto policy = CompressionPolicy.default_;
        // Very small buffer just for testing purposes.
        policy.buffer = new ubyte[2];
        auto comp = Compressor.create(policy);

        auto output = comp.compress(data).dup;
        assert(output.length == 2);
        output ~= comp.flush();
        // Repeat with default mode.
        output ~= comp.flush(FlushMode.finish);
        assert(output.length == 6);

        import std.exception : assertThrown;
        // Exception thrown - mode changed while output is pending.
        assert(comp.outputPending);
        assertThrown!ZlibException(comp.flush(FlushMode.full));
    }

    private const(void)[] compress(FlushMode mode)
    {
        // Nothing to do here.
        if (_status == ProcessingStatus.finished)
            return buffer[0 .. 0];

        _zlibStream.next_out = cast(ubyte*) buffer.ptr;
        _zlibStream.avail_out = cast(uint) buffer.length;

        // * ZlibStatus.ok -- progress has been made
        // * ZlibStatus.bufferError -- no progress possible
        // * ZlibStatus.streamEnd -- all input has been consumed and all output
        //   has been produced (only when mode == FlushMode.finish)
        auto status = c_zlib.deflate(_zlibStream, mode);

        if (status == ZlibStatus.streamEnd)
        {
            _status = ProcessingStatus.finished;
            status = c_zlib.deflateReset(_zlibStream);
            assert(status == ZlibStatus.ok);
        }
        else if (status == ZlibStatus.ok)
        {
            if (_zlibStream.avail_out == 0 && bytesPending > 0)
                _status = ProcessingStatus.outputPending;
            else
                _status = ProcessingStatus.needsMoreInput;
        }
        else
        {
            assert(status != ZlibStatus.bufferError);

            // TODO Consider calling deflateEnd
            throw new ZlibException(status);
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
    return c_zlib.deflateBound(comp._zlibStream, inputLength);
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
 + Throws: `ZlibException` if any error occurs.
 +/
void[] compress(const(void)[] data, CompressionPolicy policy = CompressionPolicy.default_)
{
    debug(zlib) writeln("compress!void[]");

    auto comp = Compressor.createWithSufficientBuffer(data.length, policy);
    comp.input = data;
    return cast(void[]) comp.flush();
}

/++
 + One-shot compression of an array of data.
 +/
unittest
{
    debug(zlib) writeln("compress(void[])");
    auto data =  "Lorem ipsum dolor sit amet, consectetur adipiscing elit. ";

    auto output = compress(data);
    import dcompress.zlib : decompress;
    assert(decompress(output) == data);
}

import dcompress.primitives : isCompressInput, isCompressOutput;
import std.traits : isArray;

/++
 + Compresses all the bytes from the input range at once using the given compression policy.
 +
 + Because the zlib library is used underneath, the `data` needs to be provided
 + as a built-in array - this is done by allocating an array and copying the input
 + into it chunk by chunk. This chunk size is controlled by `policy.maxInputChunkSize`.
 + The greater the chunk the better and faster the compression is. In particular,
 + if `data` has `length` property and `policy.maxInputChunkSize >= data.length`,
 + the output size can be estimated and data will be compressed at once - which
 + is faster and gives a better compression compared to compression in chunks.
 +
 + Params:
 + data = Input range of bytes to be compressed.
 + policy = A policy defining different aspects of the compression process.
 +
 + Returns: Compressed data.
 +
 + Throws: `ZlibException` if any error occurs.
 +/
void[] compress(InR)(InR data, CompressionPolicy policy = CompressionPolicy.default_)
if (!isArray!InR && isCompressInput!InR)
{
    debug(zlib) writeln("compress!Range");

    void[] output;
    compress(data, output, policy);
    return output;
}

/++
 + One-shot compression of a `ubyte`-input range of data.
 +/
unittest
{
    debug(zlib) writeln("compress(InputRange)");
    const(void)[] data = "Lorem ipsum dolor sit amet, consectetur adipiscing elit. ";

    import dcompress.test : inputRange;
    auto range = inputRange(cast(ubyte[]) data);
    auto output = compress(range);

    import dcompress.zlib : decompress;
    assert(decompress(output) == data);
}

/++
 + One-shot compression of a `ubyte`-input range with length which is optimized.
 +/
unittest
{
    debug(zlib) writeln("compress(InputRange)");
    const(void)[] data = "Lorem ipsum dolor sit amet, consectetur adipiscing elit. ";

    import dcompress.test : inputRange;
    auto range = inputRange!"withLength"(cast(ubyte[]) data);
    auto policy = CompressionPolicy.default_;
    // Provide enough room to copy data to.
    policy.maxInputChunkSize = 1024 ^^ 3;
    auto output = compress(range, policy);

    // Inptu won't fit entirely into a chunk, no one-call-compress optimization possible.
    policy.maxInputChunkSize = 4;
    auto output2 = compress(range, policy);

    import dcompress.zlib : decompress;
    assert(decompress(output) == data);
}

/++
 + One-shot compression of an array-input range of data.
 +/
unittest
{
    debug(zlib) writeln("compress(InputRange)");
    auto data = ["Lorem ipsum", " dolor sit amet,", " consectetur", " adipiscing elit. "];

    import dcompress.test : inputRange;
    auto range = inputRange(data);
    auto output = compress(range);

    import dcompress.zlib : decompress;
    import std.range : join;
    assert(decompress(output) == data.join);
}

/++
 + Compresses all the bytes using the given compression policy and outputs
 + the data directly to the provided output range.
 +
 + If `output` is an array, the compressed data will replace its content - instead
 + of being appended.
 +
 + Params:
 + data = Array of bytes to be compressed.
 + output = Output range taking the compressed bytes.
 + policy = A policy defining different aspects of the compression process.
 +
 + Throws: `ZlibException` if any error occurs.
 +/
void compress(OutR)(const(void)[] data, auto ref OutR output, CompressionPolicy policy = CompressionPolicy.default_)
if (isCompressOutput!OutR)
{
    debug(zlib) writeln("compress!(void[], OutputRange)");

    import std.traits : Unqual, isArray;
    static if (isArray!OutR)
    {
        debug(zlib) writeln("isArray!OutR");

        if (policy.buffer.isNull)
        {
            // In case the output.length == 0, because cannot be assigned in such case.
            output.length = 1;
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
        comp.input = data;
        comp.flushAll(output);
    }
}

/++
 + One-shot compression of an array of data to the provided output.
 +/
unittest
{
    debug(zlib) writeln("compress(void[], OutputRange)");
    const(void)[] data = "Lorem ipsum dolor sit amet, consectetur adipiscing elit. ";

    import dcompress.test : OutputRange;
    OutputRange!ubyte output;
    compress(data, output);
    assert(output.buffer == compress(data));

    import dcompress.zlib : decompress;
    assert(decompress(output.buffer) == data);

    void[] outputBuff;
    compress(data, outputBuff);
    assert(outputBuff == output.buffer);
}

/++
 + Compresses all the bytes from the input range at once using the given compression policy
 + and outputs the data directly to the provided output range.
 +
 + If `output` is an array, the compressed data will replace its content - instead
 + of being appended.
 +
 + Because the zlib library is used underneath, the `data` needs to be provided
 + as a built-in array - this is done by allocating an array and copying the input
 + into it chunk by chunk. This chunk size is controlled by `policy.maxInputChunkSize`.
 + The greater the chunk the better and faster the compression is. In particular,
 + if `data` has `length` property and `policy.maxInputChunkSize >= data.length`,
 + the output size can be estimated and data will be compressed at once - which
 + is faster and gives a better compression compared to compression in chunks.
 +
 + Params:
 + data = Input range of bytes to be compressed.
 + output = Output range taking the compressed bytes.
 + policy = A policy defining different aspects of the compression process.
 +
 + Returns: Compressed data.
 +
 + Throws: `ZlibException` if any error occurs.
 +/
void compress(InR, OutR)(InR data, auto ref OutR output, CompressionPolicy policy = CompressionPolicy.default_)
if (!isArray!InR && isCompressInput!InR && isCompressOutput!OutR)
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

                import std.algorithm.mutation : copy;
                auto input = new ubyte[data.length];
                copy(data, input);
                compress(input, output, policy);
                return;
            }
        }
        auto comp = Compressor.create(policy);
        // Array content is replaced.
        static if (isArray!OutR)
            output.length = 0;
        comp.compressAllByCopyChunk(data, output);
    }
    else // isArray!(ElementType!InR)
    {
        debug(zlib) writeln("isArray!(ElementType!InR)");

        auto comp = Compressor.create(policy);
        comp.compressAllByChunk(data, output);
    }
}

/++
 + One-shot compression of an input range of data to an output.
 +/
unittest
{
    debug(zlib) writeln("compress(InputRange, OutputRange)");
    const(void)[] data = "Lorem ipsum dolor sit amet, consectetur adipiscing elit. ";

    import dcompress.test : inputRange, OutputRange;
    auto range = inputRange!"withLength"(cast(const(ubyte)[]) data);

    OutputRange!ubyte output;
    compress(range, output);
    assert(output.buffer == compress(data));

    import dcompress.zlib : decompress;
    assert(decompress(output.buffer) == data);

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

/++
 + Helper function constructing `ZlibOutputRange`.
 +/
ZlibOutputRange!OutR zlibOutputRange(OutR)(
    auto ref OutR output, CompressionPolicy policy = CompressionPolicy.default_)
{
    return ZlibOutputRange!OutR(output, policy);
}

/++
 + Compresses data on the fly and outputs it into the given output range.
 +/
struct ZlibOutputRange(OutR)
if (isCompressOutput!OutR)
{

private:

    OutR _output;
    Compressor _comp;

public:

    this()(auto ref OutR output, CompressionPolicy policy = CompressionPolicy.default_)
    {
        _output = output;
        _comp = Compressor.create(policy);
    }

    ~this()
    {
        finish();
    }

    void finish()
    {
        _comp.flushAll(_output);
    }

    import std.range : isInputRange;
    import std.traits : hasIndirections;

    @property void put(T)(T value)
    if (!hasIndirections!T && !isInputRange!T)
    {
        put((&value)[0 .. 1]);
    }

    @property void put(T)(in T[] input)
    if (!hasIndirections!T && !isInputRange!T)
    {
        _comp.compressAll(input, _output);
    }
}
