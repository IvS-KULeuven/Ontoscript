ontoscript
==========

A DSL to build ontologies consisting of OWL individuals in a simple, structured way.

Some more info and example code are still in the pipeline ... just contact if it's needed earlier.


```
Usage: coffee DSL_SCRIPT

DSL_SCRIPT could be any coffeescript file that requires ontoscript.coffee
(e.g. by having a line "require ./ontoscript.coffee").

Optional arguments:
-I MM_PATH Import path for .jsonld MetaModels
           (You may provide this argument multiple times to include multiple paths.)
-i M_PATH  Import path for .coffee Models
           (You may provide this argument multiple times to include multiple paths.)
-n         No write: do not write the model to the stdout nor to a file.
-a         Write all: when writing out the model, also write out all imported models.
-c         Compact write: add as little whitespace to the JSON output as possible.
-f         Force write: write a new file even if this file exists already.
-t         Topbraid headers: write separate header files that can be inserted into
           RDF/TTL/... files for use with the TopQuadrant Topbraid Composer software.
           (If large RDF/TTL/... files don't contain this header info, they may not
           load correctly into the Topbraid software.)
-o O_PATH  Write the .jsonld model (and all imported models in case -a is given) to a
           file in this output path instead of to the stdout.
           (Unless -n is given, in which case no output will be written at all.)
-v         Verbosely log how the semantic model is being built.
```
