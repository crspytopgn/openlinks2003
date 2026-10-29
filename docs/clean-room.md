# Clean-room rules

This project reimplements Links 2003 for interoperability: so people who own
the game can keep playing it on modern systems. To keep the project safe to
publish, every contribution follows these rules.

## Never commit

- Any file from the original game: executables, DLLs, archives, courses,
  textures, sounds, videos or save files, in whole or in part.
- Decompiled or disassembled code from the original executable, including
  Ghidra or IDA output pasted into source files.
- Large hex dumps of original files. Short excerpts of a few bytes are fine
  when needed to illustrate a field in a format document.

`.gitignore` blocks the usual locations and extensions as a safety net. It is
not a substitute for checking what you commit.

## How knowledge flows

1. **Research:** study the original files and executable. Write what you learn
   as a plain-language description in `docs/formats/`: field offsets, types,
   meanings and behaviour, in your own words.
2. **Implementation:** write code from those documents, not from decompiler
   output. Where practical, the person implementing a format should work from
   the document rather than from the disassembly.

## Assets at runtime

The engine asks the player for their Links 2003 install folder and reads data
from there. Nothing is copied into this repository or bundled with builds.

## Not legal advice

Interoperability reverse engineering is treated differently in different
countries. In the US, DMCA section 1201(f) applies; in the EU, Article 6 of
the Software Directive does. If the project grows, get proper legal advice.
