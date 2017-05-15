/++
 + Provides compressing and decompressing abstractions built on top of
 + the $(LINK2 http://www.bzip.org/, libbzip2 library).
 +
 + Groups together all the `dcompress.bz2.*` modules.
 +
 + Authors: Jakub Łabaj, uaaabbjjkl@gmail.com
 +/
module dcompress.bz2;

public import dcompress.bz2.common;
public import dcompress.bz2.compress;
public import dcompress.bz2.decompress;

