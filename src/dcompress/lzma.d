module dcompress.lzma;

import dcompress.primitives;

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

