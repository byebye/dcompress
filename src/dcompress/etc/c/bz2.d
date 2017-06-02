/++
 + D bindings for $(LINK2 http://www.bzip.org/, libbzip2 library) written in C.
 +/
module dcompress.etc.c.bz2;

extern(C) nothrow @nogc:

enum
{
    BZ_RUN    = 0,
    BZ_FLUSH  = 1,
    BZ_FINISH = 2,
}

enum
{
    BZ_OK               = 0,
    BZ_RUN_OK           = 1,
    BZ_FLUSH_OK         = 2,
    BZ_FINISH_OK        = 3,
    BZ_STREAM_END       = 4,
    BZ_SEQUENCE_ERROR   = -1,
    BZ_PARAM_ERROR      = -2,
    BZ_MEM_ERROR        = -3,
    BZ_DATA_ERROR       = -4,
    BZ_DATA_ERROR_MAGIC = -5,
    BZ_IO_ERROR         = -6,
    BZ_UNEXPECTED_EOF   = -7,
    BZ_OUTBUFF_FULL     = -8,
    BZ_CONFIG_ERROR     = -9,
}

struct bz_stream
{
    ubyte* next_in;
    uint avail_in;
    uint total_in_lo32;
    uint total_in_hi32;

    ubyte* next_out;
    uint avail_out;
    uint total_out_lo32;
    uint total_out_hi32;

    void* state;

    void* function(void*, int, int) nothrow bzalloc;
    void function(void*, void*) nothrow bzfree;
    void* opaque;
}

/*-- Core (low-level) library functions --*/

int BZ2_bzCompressInit(
    bz_stream* strm,
    int blockSize100k,
    int verbosity,
    int workFactor);

int BZ2_bzCompress(
    bz_stream* strm,
    int action);

int BZ2_bzCompressEnd(bz_stream* strm);

int BZ2_bzDecompressInit(
    bz_stream* strm,
    int verbosity,
    int small);

int BZ2_bzDecompress(bz_stream* strm);

int BZ2_bzDecompressEnd(bz_stream *strm);

/*-- High(er) level library functions --*/

version(BZ_NO_STDIO) {}
else
{
    import core.stdc.stdio;

    enum BZ_MAX_UNUSED = 5000;

    alias void BZFILE;

    BZFILE* BZ2_bzReadOpen(
        int* bzerror,
        FILE* f,
        int verbosity,
        int small,
        void* unused,
        int nUnused);

    void BZ2_bzReadClose(
        int* bzerror,
        BZFILE* b);

    void BZ2_bzReadGetUnused(
        int* bzerror,
        BZFILE* b,
        void** unused,
        int* nUnused);

    int BZ2_bzRead(
        int* bzerror,
        BZFILE* b,
        void* buf,
        int len);

    BZFILE* BZ2_bzWriteOpen(
        int* bzerror,
        FILE* f,
        int blockSize100k,
        int verbosity,
        int workFactor);

    void BZ2_bzWrite(
        int* bzerror,
        BZFILE* b,
        void* buf,
        int len);

    void BZ2_bzWriteClose(
        int* bzerror,
        BZFILE* b,
        int abandon,
        uint* nbytes_in,
        uint* nbytes_out);

    void BZ2_bzWriteClose64(
        int* bzerror,
        BZFILE* b,
        int abandon,
        uint* nbytes_in_lo32,
        uint* nbytes_in_hi32,
        uint* nbytes_out_lo32,
        uint* nbytes_out_hi32);
}

/*-- Utility functions --*/

int BZ2_bzBuffToBuffCompress(
    ubyte* dest,
    uint* destLen,
    ubyte* source,
    uint sourceLen,
    int blockSize100k,
    int verbosity,
    int workFactor);

int BZ2_bzBuffToBuffDecompress(
    ubyte* dest,
    uint* destLen,
    ubyte* source,
    uint sourceLen,
    int small,
    int verbosity);

const(char)* BZ2_bzlibVersion();

version(BZ_NO_STDIO) {}
else
{
    BZFILE* BZ2_bzopen(
        const(char)* path,
        const(char)* mode);

    BZFILE * BZ2_bzdopen(
        int fd,
        const(char)* mode);

    int BZ2_bzread(
        BZFILE* b,
        void* buf,
        int len);

    int BZ2_bzwrite(
        BZFILE* b,
        void* buf,
        int len);

    int BZ2_bzflush(BZFILE* b);

    void BZ2_bzclose(BZFILE* b);

    const(char)* BZ2_bzerror(
        BZFILE* b,
        int* errnum);
}

