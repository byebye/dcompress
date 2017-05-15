/++
 + Provides compressing and decompressing abstractions built on top of
 + the $(LINK2 http://www.zlib.net, zlib library).
 +
 + Groups together all the `dcompress.zlib.*` modules.
 +
 + Authors: Jakub Łabaj, uaaabbjjkl@gmail.com
 +/
module dcompress.zlib;

public import dcompress.zlib.common;
public import dcompress.zlib.compress;
public import dcompress.zlib.decompress;

