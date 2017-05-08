module dcompress.core;

import std.range.primitives : isInputRange;

struct Archive(R)
if (isInputRange!R) 
{
}

