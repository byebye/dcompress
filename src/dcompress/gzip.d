module dcompress.gzip;

import etc.c.zlib;

import dcompress.primitives;

enum FlushMode
{
    sync,
    full,
    finish
}

/+ Compressor +/
struct Compressor(OutR)
if (isCompressOutput!OutR)
{
private:

    OutR _output;

public:

    void compress(const(void)[] data)
    {

    }

    void flush(FlushMode mode = FlushMode.finish)
    {

    }
}

/+ compress +/
void[] compress(const(void)[] data)
{
    return new void[0];
}

void compress(R)(const(void)[] data, R output)
if (isCompressOutput!R)
{

}

void[] compress(R)(R data)
if (isCompressInput!R)
{
    return new void[0];
}

void compress(InR, OutR)(InR data, OutR output)
if (isCompressInput!InR && isCompressOutput!OutR)
{
}

/+ Decompressor +/
struct Decompressor(OutR)
if (isDecompressOutput!OutR)
{
private:

    OutR _output;

public:

    void decompress(const(void)[] data)
    {

    }

    void flush(FlushMode mode = FlushMode.finish)
    {

    }
}

/+ decompress +/

void[] decompress(const(void)[] data)
{
    return new void[0];
}

void decompress(R)(const(void)[] data, R output)
if (isCompressOutput!R)
{

}

void[] decompress(R)(R data)
if (isCompressInput!R)
{
    return new void[0];
}

void decompress(InR, OutR)(InR data, OutR output)
if (isCompressInput!InR && isCompressOutput!OutR)
{
}

