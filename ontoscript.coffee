# ######################################################################################################################
# Project      : Ontoscript
# Description  : A DSL to build ontologies consisting of OWL individuals in a simple, structured way.
# Author       : Wim Pessemier
# Contact      : w**.p********@ster.kuleuven.be (replace *)
# Organization : Institute of Astronomy, KU Leuven
# License      : LGPL
# ######################################################################################################################


# Disclaimer: below is a long coffeescript file containing multiple classes and functions. This basically means that
# without a decent editor (i.e. one that provides a "clickable" structured overview of the code), you will get lost
# in the code in no time. JetBrains WebStorm is one that works well.
# The benefit of having all code in one file is of course that this script is self contained.



# ######################################################################################################################
# Requirements.
# ######################################################################################################################



# try to load the filesystem (fs) module and the path module
#(only required if ontoscript is used in a server environment!)
try
    fs = require "fs"
catch error
    fs = undefined
try
    path = require "path"
catch error
    path = undefined

try
    util = require "util"
catch error
    util = undefined


# ######################################################################################################################
# Some global variable declarations.
# ######################################################################################################################



# define "root" as the global scope
root = global ? this

# define some variables
root.LOG_VERBOSE          ?= false      # true to log verbose info (can be set via -v flag)
root.LOG_SUMMARY          ?= false      # true to log summary info (can be set via -s flag)
root.MODEL_NO_WRITE       ?= false      # true if the model should not be written to the std output (see -n flag)
root.MODEL_WRITE_COMPACT  ?= false      # true if the written model should be "compact" RDF-JSON (see -c flag)
root.MODEL_WRITE_FORCE    ?= false      # true if the written model should be "compact" RDF-JSON (see -c flag)
root.REQUIRE_PATHS         ?= []         # a list of paths to find .coffee files
root.READ_PATHS           ?= []         # a list of paths to find .jsonld files
root.MODEL_OUTPUT_PATH    ?= undefined  # path to store the output .jsonld file(s)
root.MODEL_WRITE_ALL      ?= false      # true to write all models (including the imported ones)
root.NSURI_TO_METAMODEL   ?= {}         # internal variable to map namespace URIs to MetaModel instances
root.NSURI_TO_MODEL       ?= {}         # internal variable to map namespace URIs to Model instances
root.ALL_PREFIXES         ?= []         # internal variable that stores all model and metamodel prefixes as strings
root.CURRENT_MODEL        ?= undefined  # pointer to the current model (so the model that was last defined by MODEL ...)
root.MODEL_WRITE_TOPBRAID ?= false      # true if headers must be written for the Topbraid software
#root.STACKS               ?= []
root.INDIVIDUAL_COUNT     ?= 0
root.OBJECTASSERTION_COUNT ?= 0
root.DATATYPEASSERTION_COUNT ?= 0
root.STANDARD_NS_PREFIXES = ["rdf", "owl", "rdfs"]

INDIVIDUAL_COUNTER = 0


# ######################################################################################################################
# Helper functions
# ######################################################################################################################

# add capitalize() function to String
String::capitalize = ->
  @substr(0, 1).toUpperCase() + @substr(1)

# ######################################################################################################################
# Logging functions.
# ######################################################################################################################



# The logging used in this script is "structured", with more indentation the deeper the call stack.
# E.g.
#   0.000  [functionA]  I'm functionA
#   0.001  [functionA]  I'm now calling functionB
#   0.001     [functionB]  I'm functionB and I'm being called!
#   0.001     [functionB]  I will now call functionC
#   0.002        [functionC]  I'm functionC and I'm being called!
#   0.003  [functionA]  functionB has been called so I'm now continuing with something else
#
# 'functionA', 'functionB' and 'functionC' are called a "sources" below and are stored in LOG_SOURCES.
# The indentation is increased by LOG_INCREMENT() and decreased by LOG_DECREMENT().
# The floating point number is the number of seconds that passed (in this case the whole script took 3 milliseconds).


# some logging related variables
LOG_SOURCES          = [""]                   # Array of source names (index 0 corresponds to the currently used source)
LOG_INDENT           = ""                     # current total indentation
LOG_INDENT_INC       = "   "                  # whitespace that will be added/removed on each increment/decrement
LOG_INDENT_INC_SIZE  = LOG_INDENT_INC.length  # number of whitespace characters per increment/decrement
LOG_START_TIME       = Date.now()             # starting time of the script as the number of milliseconds past the epoch
LOG_MAX_PADDING      = "                                "
LOG_MAX_PADDING_SIZE = LOG_MAX_PADDING.length


# ----------------------------------------------------------------------------------------------------------------------
# FUNCTIONS : LOG_INCREMENT() and LOG_DECREMENT()
#
# Add some more whitespace to the logging indentation, or remove some whitespace from the logging indentation.
# ----------------------------------------------------------------------------------------------------------------------
LOG_INCREMENT = -> LOG_INDENT += LOG_INDENT_INC
LOG_DECREMENT = -> LOG_INDENT = LOG_INDENT[LOG_INDENT_INC_SIZE..]


# ----------------------------------------------------------------------------------------------------------------------
# FUNCTIONS : LOG_SET(source) and LOG_UNSET()
#
# Increment the indentation and add a source (to become the currently active source), or decrement the indentation
# and remove the current source
# ----------------------------------------------------------------------------------------------------------------------
LOG_SET = (source, msg="") ->
    LOG_SOURCES.unshift(source)
    LOG msg
    LOG_INCREMENT()
LOG_UNSET = ->
    LOG_SOURCES = LOG_SOURCES[1..]
    LOG_DECREMENT()


# ----------------------------------------------------------------------------------------------------------------------
# FUNCTIONS : LOG_DIAGNOSTICS()
#
# Log some diagnostics.
# ----------------------------------------------------------------------------------------------------------------------
LOG_DIAGNOSTICS = ->
    LOG "Diagmostics:"
    LOG " - #Individuals        : #{INDIVIDUAL_COUNT}"
    LOG " - #ObjectAssertions   : #{OBJECTASSERTION_COUNT}"
    LOG " - #DatatypeAssertions : #{DATATYPEASSERTION_COUNT}"


# ----------------------------------------------------------------------------------------------------------------------
# FUNCTION : LOG(args...)
#
# If args... = a string: log a message using the currently active source.
# If args... = two strings: set a new source (first string), log a message (second string), and unset the source again.
# ----------------------------------------------------------------------------------------------------------------------
root.LOG = (args...) ->
    if root.LOG_VERBOSE

        if args.length is 1

            message = args[0]

            allLines = message.split('\n')

            # create a string like "14:00:37.948"
            #timeStr = (new Date()).toISOString().substring(11, 23)
            timeStr = ((Date.now() - LOG_START_TIME) / 1000.0).toFixed(3)

            # loop through the lines and log them to the console
            for line in allLines
                if line.length > 0
                    if not (LOG_SOURCES[0]?) then LOG_SOURCES[0] = ""
                    console.log("#{timeStr} [#{LOG_SOURCES[0]}] #{LOG_MAX_PADDING[-(LOG_MAX_PADDING_SIZE - LOG_SOURCES[0].length)..]}  #{LOG_INDENT}  #{line}")

        else
            LOG_SET(args[0])
            LOG args[1]
            LOG_UNSET()

root.SUMMARY = (msg) ->
    console.log(msg)

# loop through the arguments to find the -v argument at this point, so that we can enable the logging already
# before executing the rest of the script:
for arg, i in process.argv
    if arg is "-v"
        LOG_VERBOSE = true
        LOG "Verbose logging is ON"
    if arg is "-s"
        LOG_SUMMARY = true
        LOG "Summary logging is ON"


# ######################################################################################################################
# Create some helper functions
# ######################################################################################################################



# ----------------------------------------------------------------------------------------------------------------------
# FUNCTION : ABORT(msg)
#
# Helper function to throw an Error with a given message 'msg'.
# ----------------------------------------------------------------------------------------------------------------------
root.ABORT = (msg) -> throw new Error(msg)

# ----------------------------------------------------------------------------------------------------------------------
#
# Helper function to stop execution
# ----------------------------------------------------------------------------------------------------------------------
root.STOP = () ->
    console.log("")
    console.log("==================== STOPPED ====================")
    process.exit()

# ----------------------------------------------------------------------------------------------------------------------
# FUNCTION : isString(s)
#
# Helper function to check if an object 's' is a string
# ----------------------------------------------------------------------------------------------------------------------
isString = (s) -> return typeof s == "string" or s instanceof String
root.IS_STRING = isString

# ----------------------------------------------------------------------------------------------------------------------
# FUNCTION : IS_ARRAY(o)
#
# Helper function to check if an object 'o' is an array
# ----------------------------------------------------------------------------------------------------------------------
root.IS_ARRAY = (o) -> return o instanceof Array

# ----------------------------------------------------------------------------------------------------------------------
# FUNCTION : IS_FUNCTION(f)
#
# Helper function to check if an object 'f' is a function
# ----------------------------------------------------------------------------------------------------------------------
root.IS_FUNCTION = (f) -> return f instanceof Function


# ----------------------------------------------------------------------------------------------------------------------
# FUNCTION : isNumeric(x)
#
# Helper function to check if n is a number
# ----------------------------------------------------------------------------------------------------------------------
root.IS_NUMBER = (x) -> not isNaN(x)

# ----------------------------------------------------------------------------------------------------------------------
# FUNCTION : CHECK_KEY(o, key)
#
# Helper function, throws error if o.key exists but is undefined!
# ----------------------------------------------------------------------------------------------------------------------
root.CHECK_KEY = (o, key) ->
    if o?
        if key in Object.keys(o)
            if o[key] is undefined then ABORT("Key '#{key}' of the object below is mentioned, but undefined!\n#{__INSPECT__(o, depth=2)}")
    else
        ABORT("Cannot check key '#{key}': undefined object")


# ----------------------------------------------------------------------------------------------------------------------
# FUNCTION : JSONIFY(obj)
#
# Return a JSON string of the object.
# ----------------------------------------------------------------------------------------------------------------------
root.__INSPECT__ = (obj, depth=null) ->
    if util?
        util.inspect(obj, { showHidden: true, depth: depth })
    else
        output = ''
        for property of obj
            output += property + ': ' + obj[property]+'; '
        return "{ " + output + "}"


# ----------------------------------------------------------------------------------------------------------------------
# FUNCTION : isStringDictionary(d, levels)
#
# Helper function to check if an object 'd' corresponds to an associative container of string values. The 'levels'
# argument specifies how many levels deep the dictionary should be.
# ----------------------------------------------------------------------------------------------------------------------
isStringDictionary = (d, levels=1) ->
    if not (d instanceof Object)
        return false
    else
        for key, value of d
            if levels == 1
                return isString(value)
            else if levels > 1
                return isStringDictionary(value, levels - 1)
            else
                ABORT "BUG: unexpected levels #{levels} for isStringDictionary"


# ----------------------------------------------------------------------------------------------------------------------
# FUNCTION : IS_INDIVIDUAL(i)
#
# Helper function to check if an object i is an Individual
# ----------------------------------------------------------------------------------------------------------------------
isIndividual = (i) -> return i instanceof Individual
root.IS_INDIVIDUAL = isIndividual

# ----------------------------------------------------------------------------------------------------------------------
# FUNCTION : isStack(i)
#
# Helper function to check if an object i is a Stack
# ----------------------------------------------------------------------------------------------------------------------
isStack = (i) -> return i instanceof Stack

# ----------------------------------------------------------------------------------------------------------------------
# FUNCTION : isModel(m)
#
# Helper function to check if an object i is a Model
# ----------------------------------------------------------------------------------------------------------------------
isModel = (m) -> return m instanceof Model

# ----------------------------------------------------------------------------------------------------------------------
# FUNCTION : isMetaModel(m)
#
# Helper function to check if an object i is a MetaModel
# ----------------------------------------------------------------------------------------------------------------------
isMetaModel = (m) -> return m instanceof MetaModel

# ----------------------------------------------------------------------------------------------------------------------
# FUNCTION : isMethod(x)
#
# Helper function to check if an object 'x' corresponds to an object like this: { <string> : <Function> }
# ----------------------------------------------------------------------------------------------------------------------
isMethod = (x) ->
    try
        keys = Object.keys(x)
        #if keys.length != 1 then return false
        for key in keys
            if isString(key)
                return x[key] instanceof Function
            else
                return false
    catch error
        return false

## ----------------------------------------------------------------------------------------------------------------------
## FUNCTION : isMethodContainer(x)
##
## Helper function to check if an object 'x' corresponds to an object like this: { <string> : <Function> , <string> : <Function> , ... }
## ----------------------------------------------------------------------------------------------------------------------
#isMethodContainer = (x) ->
#    try
#        keys = Object.keys(x)
#        if keys.length != 1 then return false
#        for key in keys
#            if isString(key)
#                return x[key] instanceof Function
#            else
#                return false
#    catch error
#        return false


# ----------------------------------------------------------------------------------------------------------------------
# FUNCTION : CHECK_ARGS(name, args, validArgs)
#
# Helper function to check if given arguments are valid
# ----------------------------------------------------------------------------------------------------------------------
root.CHECK_ARGS = (name, args, validArgs) ->

    for arg in Object.keys(args)
        if not (arg in validArgs)
            ABORT("Invalid argument '#{arg}' for #{name}! Expected: #{validArgs}")

        CHECK_KEY(args, arg)

    return undefined

# ----------------------------------------------------------------------------------------------------------------------
# FUNCTION : CHECK_ARGS_INVALID_COMBINATION(args, invalidCombination)
#
# Helper function to check if two arguments aren't used together
# ----------------------------------------------------------------------------------------------------------------------
root.CHECK_ARGS_INVALID_COMBINATION = (name, args, invalidCombination) ->
    counter = 0
    for arg in Object.keys(args)
        if arg in invalidCombination
            counter = counter + 1
            if counter > 1
                ABORT("Illegal argument '#{arg}': cannot coexist with these: #{invalidCombination}")
    return undefined


# ----------------------------------------------------------------------------------------------------------------------
# FUNCTION : FILTER_ARGS(args, filter)
#
# Helper function to filter (keep or remove) args
# ----------------------------------------------------------------------------------------------------------------------
root.FILTER_ARGS = (args, filter={}) ->
    ret = {}

    if filter.keep? and filter.remove?
        ABORT("Invalid argument for FILTER_ARGS: only provide 'keep' or 'remove', not both!")

    if filter.keep?
        for key in Object.keys(args)
            if key in filter.keep
                ret[key] = args[key]

    if filter.remove?
        for  key in Object.keys(args)
            if not (key in filter.remove)
                ret[key] = args[key]

    return ret



class Pair
    constructor: (@key, @value) ->
root.__PAIR__ = (key,value) -> new Pair(key,value)



root.__BUILD__ = ( pairs ) ->
    ret = {}
    for pair in pairs
        ret[pair.key] = pair.value
    return ret


# ----------------------------------------------------------------------------------------------------------------------
# FUNCTION : findFile(fileName, dirs=undefined, extension=undefined)
#
# Helper function to find a file, either with an absolute fileName (leave 'dirs' undefined), or relative to one
# of the directories specified in the 'dirs' list. You may provide an extension that will be verified.
# ----------------------------------------------------------------------------------------------------------------------
findFile = (fileName, dirs=undefined, extension=undefined) ->
        LOG_SET("", "findFile '#{fileName}', dirs=#{JSON.stringify(dirs)}, extension='#{extension}'")

        if extension?
            # abort if the file extension doesn't match
            if fileName[-(extension.length)..] isnt extension
                ABORT "Cannot READ #{fileName}: this file should have a #{extension} extension"

        ret = undefined

        if dirs?
            filesFound = 0
            realPaths  = []
            for dir in dirs
                fullPath = path.join(dir, fileName)
                if fs.existsSync(fullPath)
                    LOG "Searching #{fileName} in '#{dir}': FOUND!"
                    realPaths.push(fs.realpathSync(fullPath))
                    filesFound += 1
                else
                    LOG "Searching #{fileName} in #{dir}: not found"

            if realPaths.length == 1
                LOG "The file was found (real path: #{realPaths[0]})"
                ret = realPaths[0]
            else if realPaths.length == 0
                ABORT "File #{fileName} could not be found, did you specify the correct include path(s)?"
            else
                s =  "File #{fileName} could be resolved to multiple files: \n"
                s += " - #{dir}\n" for dir in realPaths
                s += "Change filenames to avoid ambiguity!"
                ABORT s
        else
            if fs.existsSync(fileName)
                ret = fileName
            else
                ABORT "The file with absolute path '#{fileName}' could not be found"

        LOG_UNSET()

        return ret

# METHOD: require a coffeescript file.
root.REQUIRE = (fileName, ABSOLUTE=false) ->
    LOG_SET("", "REQUIRE '#{fileName}', ABSOLUTE=#{ABSOLUTE}")

    if not ABSOLUTE then dirs = REQUIRE_PATHS
    f = findFile(fileName, dirs, ".coffee")

    original_MODEL_NO_WRITE = root.MODEL_NO_WRITE

    if not root.MODEL_WRITE_ALL then root.MODEL_NO_WRITE = true

    try
        require f
    catch error
        ABORT "Could not REQUIRE '#{fileName}': #{error.stack}?"

    root.MODEL_NO_WRITE = original_MODEL_NO_WRITE

    LOG_UNSET()




# ----------------------------------------------------------------------------------------------------------------------
# FUNCTION : UNIQUE(prefix="node")
#
# Helper function to create a unique string.
# ----------------------------------------------------------------------------------------------------------------------
root.UNIQUE_SEQ_NUMBER = -1
root.UNIQUE_START_NUMBER = ((Date.now() / 1000) | 0) * 1000000
root.UNIQUE = (prefix = "node") ->

    root.UNIQUE_SEQ_NUMBER += 1
    return "#{prefix}#{root.UNIQUE_START_NUMBER + root.UNIQUE_SEQ_NUMBER}"




# ######################################################################################################################
# Create a class to store namespace details
# ######################################################################################################################



# ----------------------------------------------------------------------------------------------------------------------
# CLASS : NameSpace
#
# A NameSpace instance stores some namespace details such as the URI and prefix.
#
# Example: ns = new NameSpace("http://my.namespace/uri", "myprefix")
# ----------------------------------------------------------------------------------------------------------------------
class NameSpace


    # CONSTRUCTOR
    constructor: (@uri, @prefix) ->


    # METHOD: check if the NameSpace has a valid URI and/or prefix
    isDefined: () ->
        return (@uri?) or (@prefix?)


    # METHOD: get a string representation
    toString: ->
        s = "NameSpace("
        s += if @uri? then "uri='#{@uri}'" else "uri=???"
        s += ", "
        s += if @prefix? then "prefix='#{@prefix}'" else "prefix=???"
        s += ")"
        return s


    # METHOD: get a compact string representation
    toCompactString: () ->
        return if @prefix? then @prefix else if @uri? then @uri else ""


    # METHOD: serialize the NameSpace as RDF/JSON
    getJsonld: () ->
        return { "@id" : @uri }



# ######################################################################################################################
# Create a class to store a Qualified Name
# ######################################################################################################################



# ----------------------------------------------------------------------------------------------------------------------
# CLASS : QName
#
# A QName instance stores a qualified name.
#
# A qualified name can be structured, e.g. "myapp:statemachine.states.start" could specify the "start state" of a
# state machine defined like this:
#   qn = new QName(new NameSpace("http://myorg.org/myapplication", "myapp"),
#                  "start",
#                  ["statemachine", "states"])
#   console.log(qn.fullName()) # will give you "statemachine.states.start"
# ----------------------------------------------------------------------------------------------------------------------
class QName


    # CONSTRUCTOR
    constructor: (@ns, @_name, @namePrefixes=[]) ->


    # METHOD: get the concatenation of the @namePrefixes + the @_name, separated by dots (.)
    fullName: () ->
        s = ""
        s += namePrefix + "." for namePrefix in @namePrefixes
        s += @_name
        return s

    partName: () ->
        return @_name

    # METHOD: get a compact string representation
    toCompactString: () ->
        return "#{@ns.toCompactString()}:#{@fullName()}"


    # METHOD: get a string representation
    toString: () ->
        return "#{@ns}:#{@fullName()}"


    # METHOD: get the RDF-JSON serialization of the qualified name
    getJsonld: () ->
        return { "@id" : "#{@ns.prefix}:#{@fullName()}" }


    # CLASS METHOD: create a QName from a NameSpace instance and a full name (such as "a.b.c")
    @fromNsAndFullName: (ns, fullName) ->
        @ns = ns
        split = fullName.split(".").reverse()
        name = split[0]
        namePrefixes = split[1..]
        return new QName(ns, name, namePrefixes)

    # CLASS METHOD: extract the QName from an URI serialized as JSON-LD
    # If the URI is anonymous (e.g. _:N3a140f03d97c44468c8ab48a1593d18d), undefined will be returned
    @fromJsonldUri = (uri, context=undefined, strict=false) ->
        if uri is "@type" then uri = "rdf:type"

        # parse the uri
        if not IS_STRING(uri)
            # do nothing
        else if uri.indexOf("#") isnt -1
            split = uri.split("#")
            nsUri = split[0]
            name  = split[1]
        else if (uri.indexOf(":") isnt -1) and (uri.indexOf("/") is -1)
            split    = uri.split(":")
            nsPrefix = split[0]
            name     = split[1]
            if nsPrefix is "_" # return 'undefined' for anonymous nodes!
                return
            else if context?
                nsUriWithTrailingHash = context[nsPrefix]
                if nsUriWithTrailingHash?
                    nsUri = nsUriWithTrailingHash.substr(0, nsUriWithTrailingHash.length - 1)
                else if not strict
                    return
                else
                    ABORT """Error while parsing #{uri}: prefix #{nsPrefix} was
                             not found in the following context: #{JSON.stringify(context)}"""
            else if not strict
                return
            else
                ABORT """Error while parsing #{uri}: a context was needed to find the matching
                         URI of #{nsPrefix}, but no context was found"""
        else
            nsUri = uri
            name  = ""

        # now verify if the namespace is already known, and update the namespace prefix if we can!
        mm = NSURI_TO_METAMODEL[nsUri]

        if mm?
            return new QName(mm.ns, name)
        else if not strict
            return
        else
            ABORT "Error while parsing #{uri}: MetaModel #{nsUri} is unknown, did you forget to REQUIRE it?"




# ----------------------------------------------------------------------------------------------------------------------
# FUNCTION : getObjectReference(qName)
#
# Get a reference (a pointer) to the object as specified by the QName argument.
#
# Example:  reference = getObjectReference(new QName(new NameSpace("http://myorg/myapp", "myapp"), "statemachine"))
#           if reference? then console.log reference.toString()
# ----------------------------------------------------------------------------------------------------------------------
getObjectReference = (qName) ->

    # create an undefined reference (a pointer) and try to incrementally update it to find the object
    reference = undefined
    if qName?
        reference = root[qName.ns.prefix]
        reference = reference[namePrefix] for namePrefix in qName.namePrefixes
        reference = reference[qName._name]

    # log a nice message
    if reference?
        if reference instanceof Individual
            LOG_SET "", "Getting reference for #{qName.toCompactString()}: OK (Individual)"
        else if reference instanceof Function
            LOG_SET "", "Getting reference for #{qName.toCompactString()}: OK (Class or Property)"
        else
            ABORT("Unexpected object reference found (#{reference}) for #{qName.toCompactString()}")
    else
        LOG_SET "", "#{qName.toCompactString()} --> Nothing found!"

    LOG_UNSET()

    return reference



# ######################################################################################################################
# Define the primitive data types
# ######################################################################################################################



# ----------------------------------------------------------------------------------------------------------------------
# CLASS : Primitive
#
# A Primitive instance stores a primitive value.
#
# Primitive values can be conveniently created by the global bool(), int8(), float(), string(), ... functions.
# ----------------------------------------------------------------------------------------------------------------------
Primitive = class


    # CONSTRUCTOR: create a primitive type.
    constructor: (@_name, @value, @xsdType) ->
        if not @value?
            ABORT "No argument given for #{@_name}()!"

        if @value is Infinity
            @value = "INF"
            @xsdValue = @value
        else if @value is -Infinity
            @value = "-INF"
            @xsdValue = @value
        else if @_name is "bool"
            @xsdValue = Boolean(value).toString()
        else
            @xsdValue = value.toString()


    # METHOD: get a string representation.
    toString: ->
        return "#{@_name}(#{@value})"


    # METHOD: serialize as JSON-LD.
    getJsonld: ->
        return { "@value" : "#{@xsdValue}" , "@type" : "#{xsd.ns.prefix}:#{@xsdType}" }


# ----------------------------------------------------------------------------------------------------------------------
# FUNCTION : bool(value), int8(value), float(value), string(value), ...
#
# Create a Primitive instance of a praticular type.
# ----------------------------------------------------------------------------------------------------------------------
root.bool       = (value) -> return new Primitive("bool"        , value, "boolean"      )
root.int8       = (value) -> return new Primitive("int8"        , value, "byte"         )
root.uint8      = (value) -> return new Primitive("uint8"       , value, "unsignedByte" )
root.int16      = (value) -> return new Primitive("int16"       , value, "short"        )
root.uint16     = (value) -> return new Primitive("uint16"      , value, "unsignedShort")
root.int32      = (value) -> return new Primitive("int32"       , value, "int"          )
root.uint32     = (value) -> return new Primitive("uint32"      , value, "unsignedInt"  )
root.int64      = (value) -> return new Primitive("int64"       , value, "long"         )
root.uint64     = (value) -> return new Primitive("uint64"      , value, "unsignedLong" )
root.float      = (value) -> return new Primitive("float"       , value, "float"        )
root.double     = (value) -> return new Primitive("double"      , value, "double"       )
root.string     = (value) -> return new Primitive("string"      , value, "string"       )
root.bytestring = (value) -> return new Primitive("bytestring"  , value, "hexBinary"    )
root.int        = (value) -> return int32(value)



root.time       = (Y,M,D,h,m,s,ms,tz) ->
                    dt = ""
                    if Y? or M? or D?
                        if Y? and M? and D?
                            dt += Y + '-' + (if M<=9 then '0'+M else M) + '-' + (if D<=9 then '0'+D else D)
                        else
                            ABORT "Invalid arguments for time(): either all of Y,M,D are given, or none at all"

                    if h? or m? or s?
                        if h? and m? and s?
                            if dt.length > 0 then dt += "T"
                            dt +=  (if h<=9 then '0'+h else h) + ':' \
                                 + (if m<=9 then '0'+m else m) + ':' \
                                 + (if s<=9 then '0'+s else s)
                        else
                            ABORT "Invalid arguments for time(): either all of h,m,s are given, or none at all"

                    if ms?
                        if s?
                            dt += "." + (if ms<9 then '00'+ms else if ms<99 then '0'+ms else ms)
                        else
                            ABORT "Invalid arguments for time(): cannot specify ms without specifying h,m,s"

                    if tz? then dt += "Z"

                    return new Primitive("time", dt , "dateTime")


root.timeUtcNow  = () ->
                    now = new Date()
                    return time(now.getUTCFullYear(),
                                now.getUTCMonth(),
                                now.getUTCDate(),
                                now.getUTCHours(),
                                now.getUTCMinutes(),
                                now.getUTCSeconds(),
                                now.getUTCMilliseconds(),
                                "Z")




# ######################################################################################################################
# Create a class to identify classes and properties
# ######################################################################################################################


class NameIdentifier
    constructor: () ->

class TypeIdentifier
    constructor: () ->

NAME_IDENTIFIER = new NameIdentifier()
TYPE_IDENTIFIER = new TypeIdentifier()


# ######################################################################################################################
# Create a class for Object assertions, and one for Datatype assertions
# ######################################################################################################################



# ----------------------------------------------------------------------------------------------------------------------
# CLASS : ObjectAssertion
#
# An ObjectAssertion holds a predicate + object, with the predicate being an object property.
# ----------------------------------------------------------------------------------------------------------------------
class ObjectAssertion


    # CONSTRUCTOR
    constructor: (@predicate, @object) ->
        LOG_SET "ObjectAssertion", "new #{@toCompactString()}"
        LOG_UNSET()
        OBJECTASSERTION_COUNT += 1

    # METHOD: get a string representation
    toString: () ->
        return "ObjectAssertion(#{@predicate}, #{@object})"


    # METHOD: get a compact string representation
    toCompactString: () ->
        if @predicate.toCompactString? then predStr = @predicate.toCompactString() else predStr = @predicate.toString()
        if @object.toCompactString?    then objStr  = @object.toCompactString()    else objStr = @object.toString()
        return "#{predStr} #{objStr}"


    # METHOD: serialize the assertion to RDF/JSON starting from the predicates part (so without the subject part).
    # So the resulting JSON would look like { P0 : [O0a, O0b, ...], P1 : [O1a, O1b, ...], ... }
    getJsonldPredicates: () ->
        ret = {}
        if (@predicate.ns.uri is rdf.ns.uri) and (@predicate.fullName() == "type")
            pred = "@type"
        else
            pred = "#{@predicate.ns.prefix}:#{@predicate.fullName()}"

        if (@object instanceof Individual)
            ret[pred] = @object.qName().getJsonld()
        else if (@object instanceof QName)
            if @predicate.ns.prefix in ["owl", "rdf", "rdfs"]
                ret[pred] = "#{@object.ns.prefix}:#{@object.fullName()}"
            else
                ret[pred] = { "@id" : "#{@object.ns.prefix}:#{@object.fullName()}" }
        else if (@object instanceof Model) or (@object instanceof MetaModel)
            ret[pred] = @object.ns.getJsonld()
        else
            ABORT("Cannot serialize #{@object}!")
        return ret


    # METHOD: Check the namespace prefixes of the predicate and object against a set of allowed prefixes.
    # E.g. myObjectAssertion.checkNameSpacePrefixes([ "owl", "rdf", "rdfs", "myns0", "myns1", ...])
    checkNameSpacePrefixes: (allowedPrefixes) ->
        for item in [@object, @predicate]
            if item.ns?
                if not (item.ns.prefix in allowedPrefixes)
                    ABORT("Invalid #{@toCompactString()}: '#{item.ns.prefix}' is not an imported or standard namespace. Full item: #{item.toString()}")



# ----------------------------------------------------------------------------------------------------------------------
# CLASS : DatatypeAssertion
#
# A DatatypeAssertion holds a predicate + object, with the predicate being a datatype property.
# ----------------------------------------------------------------------------------------------------------------------
class DatatypeAssertion


    # CONSTRUCTOR
    constructor: (@predicate, @data, @datatype) ->
        LOG_SET "DatatypeAssertion", "new #{@toCompactString()}"
        LOG_UNSET()
        DATATYPEASSERTION_COUNT += 1


    # METHOD: get a string representation
    toString: () ->
        return "DatatypeAssertion(#{@predicate}, #{@data})"


    # METHOD: get a compact string representation
    toCompactString: () ->
        if @predicate.toCompactString? then predStr = @predicate.toCompactString() else predStr = @predicate.toString()
        if @data.toCompactString?
            dataStr = @data.toCompactString()
        else if isString(@data)
            dataStr = "\"#{@data.toString()}\""
        else
            dataStr = @data.toString()
        return "#{predStr} #{dataStr}"


    # METHOD: serialize the assertion to RDF/JSON starting from the predicates part (so without the subject part).
    # So the resulting JSON would look like { P0 : [O0a, O0b, ...], P1 : [O1a, O1b, ...], ... }
    getJsonldPredicates: () ->
        ret = {}
        pred = "#{@predicate.ns.prefix}:#{@predicate.fullName()}"
        if (@data instanceof QName) or (@data instanceof NameSpace) or (@data instanceof Primitive)
            ret[pred] = @data.getJsonld()
        else
            ret[pred] = "#{@data}"
        return ret


    # METHOD: Check the namespace prefixes of the predicate against a set of allowed prefixes.
    # E.g. myObjectAssertion.checkNameSpacePrefixes([ "owl", "rdf", "rdfs", "myns0", "myns1", ...])
    checkNameSpacePrefixes: (allowedPrefixes) ->
        if not @predicate.ns.prefix in allowedPrefixes
            ABORT("Invalid #{@toCompactString()}: #{@predicate.ns.prefix} is not an imported or standard namespace")



# ######################################################################################################################
# Create some helper functions for the RDF/JSON serialization
# ######################################################################################################################



# ----------------------------------------------------------------------------------------------------------------------
# FUNCTION : combineJsonldObjects(objects1, objects2)
#
# Combine a list of objects from two sources (where object is part of a subject-predicate-object triple as serialized
# in JSON-LD) and return a new list containing the merged lists.
# ----------------------------------------------------------------------------------------------------------------------
combineJsonldObjects = (objects1, objects2) =>
    # first of all, check if both objects are not equal
    if JSON.stringify(objects1) is JSON.stringify(objects2) then return objects1

    ret = []
    if objects1 instanceof Array
        ret.push(item) for item in objects1
    else
        ret.push(objects1)

    if objects2 instanceof Array
        ret.push(item) for item in objects2
    else
        ret.push(objects2)

    return ret



# ----------------------------------------------------------------------------------------------------------------------
# FUNCTION : mergeJsonldPredicates(destination, source)
#
# Merge the source JSON-LD "predicates" part with the destination JSON "predicates" part.
# The source argument will not be modified, but the destination argument will be expanded.
# ----------------------------------------------------------------------------------------------------------------------
mergeJsonldPredicates = (destination, source) ->
    for pred, objects of source
        if destination[pred]?
            destination[pred] = combineJsonldObjects(destination[pred], objects)
        else
            destination[pred] = objects


# ----------------------------------------------------------------------------------------------------------------------
# FUNCTION : mergeJsonld(destination, source)
#
# Merge the source JSON-LD serialization with the destination JSON serialization.
# The arguments should contain Subjects, Predicates and Objects.
# The source argument will not be modified, but the destination argument will be expanded.
# ----------------------------------------------------------------------------------------------------------------------
mergeJsonld = (destination, source) ->

    for sourceTriplesOfASubject in source

        merged = false

        for destinationTriplesOfASubject in destination
            if sourceTriplesOfASubject["@id"] == destinationTriplesOfASubject["@id"]
                mergeJsonldPredicates( destinationTriplesOfASubject, sourceTriplesOfASubject )
                merged = true
                break

        if not merged then destination.push(sourceTriplesOfASubject)






# ######################################################################################################################
# CREATE
# ######################################################################################################################
class Construction
    constructor: (@macro) ->

root.CONSTRUCTION = Construction

root.CONSTRUCT = (args) ->
    if not args?
        ABORT("Undefined arguments of CONSTRUCT")
    return new CONSTRUCTION(args)





# ######################################################################################################################
# Create a "stack" class for storing Individuals before they are added to other Individuals or to a Model.
# ######################################################################################################################





# ----------------------------------------------------------------------------------------------------------------------
# CLASS : Stack
#
# A Stack is a container to temporarily store Individuals before they are stored permanently (as either an attribute
# of another individual, or an Individual of a Model). Without a stack, it would not be possible to refer to
# Individual "bryanMay" at line 3 in the following example, since music:queen.bryanMay was not added to the ontology yet
# when this line is interpreted.
#
# 0|   music.ADD music.Band "queen" : [
# 1|       """ Queen, the British rock band. """
# 2|       music.hasMember music.Artist "bryanMay" : [ foaf.name "Bryan May" ]
# 3|       music.hasGuitarPlayer self.bryanMay
# 4|   ]
# ----------------------------------------------------------------------------------------------------------------------
class Stack


    # CONSTRUCTOR: create a stack with a certain name
    constructor: (@_name) ->
        @log_set("new Stack '#{_name}'")
        @fullName_to_individual = {}
        @shortcut_to_individual = {}
        @log_unset()

    # METHODs: logging-related methods for this particular class (see LOG_SET, LOG and LOG_UNSET for more info).
    log_set   : (msg) -> LOG_SET "Stack #{@_name}", msg
    log       : (msg) -> LOG(msg)
    log_unset : ()    -> LOG_UNSET()


    # METHOD: clear the memory of the stack
    clear: () ->
        @log_set("clear()")
        this[fullName] = undefined for fullName, individual of @fullName_to_individual
        this[name]     = undefined for name, individual of @shortcut_to_individual
        @fullName_to_individual = {}
        @shortcut_to_individual = {}
        @log_unset()


    # METHOD: add an individual (temporarily) to the stack
    add: (individual) ->
        @log_set("add(#{individual.toCompactString()})")
        @fullName_to_individual[individual.fullName()] = individual
        this[individual.fullName()] = individual
        @log_unset()

    addShortcut: (shortcut) ->
        @log_set("addShortcut(#{shortcut.toCompactString()})")
        @shortcut_to_individual[shortcut.name] = shortcut.item
        this[shortcut.name] = shortcut.item
        @log_unset()


    # METHOD: check if the stack contains a certain Individual
    contains: (individual) ->
        return @fullName_to_individual[individual.fullName()]?


    # METHOD: get a string representation.
    toString: (indent="") ->
        s =  "Stack '#{@_name}'\n"
        s += "#{indent} - fullName_to_individual:"
        s += "\n#{indent}     * #{name} : #{indiv.toCompactString()}" for name, indiv of @fullName_to_individual
        s += "\n#{indent} - shortcut_to_individual:"
        s += "\n#{indent}     * #{name} : #{indiv.toCompactString()}" for name, indiv of @shortcut_to_individual
        if @$?
            s += "\n#{indent} - $:"
            s += "\n#{indent}     #{@$.toString(indent + "     ")}"
        return s

#    @setActiveStack: (stack) ->
#        LOG_SET "Stack", "Setting active stack to #{stack._name}"
#
#        root.STACKS.unshift(stack)
#        stackNames = []
#        stackNames.push(stack._name) for stack in root.STACKS
#        LOG "Stacks: [#{stackNames}]"
#        LOG_UNSET()

#    @clearActiveStack: (checkStack) ->
#        LOG_SET "Stack", "Clearing active stack #{checkStack._name}"
#
#        if checkStack isnt root.STACKS[0]
#            ABORT "Clearing the active stack failed: STACKS[0]=#{root.STACKS[0]} doesn't correspond to #{checkStack}"
#
#        checkStack.clear()
#        root.STACKS = root.STACKS[1..]
#
#        stackNames = []
#        stackNames.push(stack._name) for stack in root.STACKS
#        LOG "Stacks: [#{stackNames}]"
#        LOG_UNSET()
    @clearActiveStack: (stack) ->
        LOG_SET "Stack", "Clearing active stack #{stack._name}"
        stack.clear()
        if stack.$?
            root[stack.$._name] = stack.$.clone(stack.$._name)
        LOG_UNSET()


    clone: (newName) ->
        LOG_SET "Stack", "clone(#{newName})"
        s = new Stack(newName)
        for name, indiv of @fullName_to_individual
            s.fullName_to_individual[name] = indiv
            s[name] = indiv
        for name, indiv of @shortcut_to_individual
            s.shortcut_to_individual[name] = indiv
            s[name] = indiv
        if @$?
            s.$ = @$
        LOG(s.toString())
        LOG_UNSET()
        return s


root.STACK = Stack

# ######################################################################################################################
# Create some Stacks and an INIT function
# ######################################################################################################################



class Initor
    constructor: () ->

INITOR = new Initor()

root.APPLY = (calledMacro) ->
    return calledMacro.apply(undefined, [INITOR])


root.INIT = (args) ->

    if args? then ABORT "INIT with args!!!"

    LOG_SET "", "INIT"
    if root.self == undefined
        root.self = new Stack('self')
    else
        root.self.$ = root.self.clone('$')
        root.self.clear()
        root.$ = root.self.$

    LOG_UNSET()
    return root.self


root.EXIT = (args) ->

    if args? then ABORT "EXIT with args!!!"

    LOG_SET "", "EXIT"
    if root.self.$?
        root.self = root.self.$.clone('self')
        if root.self.$?
            root.$ = root.self.$
        else
            root.$ = undefined
    else
        root.self = undefined
        root.$ = undefined

    LOG_UNSET()
    return []



# ######################################################################################################################
# Create a class for the individuals that we will be creating with this DSL
# ######################################################################################################################



# ----------------------------------------------------------------------------------------------------------------------
# CLASS : Shortcut
# ----------------------------------------------------------------------------------------------------------------------
class Shortcut

    constructor: (@name, @item) ->


    # METHODs: logging-related methods for this particular class (see LOG_SET, LOG and LOG_UNSET for more info).
    log_set   : (msg) -> LOG_SET "#{@toCompactString()}", msg
    log       : (msg) -> LOG(msg)
    log_unset : ()    -> LOG_UNSET()


    toCompactString : () ->
        if @item.qName?
            return "#{@name} -> #{@item.qName().toCompactString()}"
        else if @item.toCompactString?
            return "#{@name} -> #{@item.toCompactString()}"
        else if @item.toString?
            return "#{@name} -> #{@item.toString()}"
        else
            return "#{@name} -> #{@item}"

    toString : () ->
        if @item.toString?
            return "#{@name} -> #{@item.toString()}"
        else if @item.toCompactString?
            return "#{@name} -> #{@item.toCompactString()}"
        else if @item.qName?
            return "#{@name} -> #{@item.qName().toCompactString()}"
        else
            return "#{@name} -> #{@item}"

    addToStackIfNeeded: () ->
        @log_set "Stacking this shortcut"
        root.self.addShortcut(this)
        @log_unset()

root.SHORTCUT = (name,item) ->
    ret = new Shortcut(name,item)
    ret.addToStackIfNeeded()
    return ret



class Update
    constructor: (@property, @value) ->

root.__UPDATE__ = (property, value) ->
    return new Update(property, value)



# ----------------------------------------------------------------------------------------------------------------------
# CLASS : Individual
#
# An Individual represents an OWL:NamedIndividual, can hold assertions about this individual, and can hold
# other individuals (called "attributes"). These attributes are actually just regular inidividuals, the only thing
# "special" about them is that their name is structured (via dots), and that the first segments ("namePrefixes") of
# their structered name correspond to the name of the individual that was used to create them. Within the DSL these
# attributes seem to be "owned" by a parent Individual, but when translated to RDF triples, they become just regular
# Individuals (only their name will contain dots).
# ----------------------------------------------------------------------------------------------------------------------
class Individual


    # CONSTRUCTOR: create an Individual of a certain type (a certain owl:Class) and with a certain name.
    # Label can be undefined (in which case label=name), or false (no rdfs:label added) or a string (the new label)
    constructor: (type, name, more={}) ->
        @_name              = name
        @_type               = type
        @namePrefixes       = []
        @ns                 = new NameSpace()
        @datatypeAssertions = []
        @objectAssertions   = []
        @attributes         = []
        @macros             = []
        @shortcuts          = []
        @isAdded            = false
        @hasLabel           = false
        @hasOntoscriptProperties = true
        @log_set("new Individual #{type.toCompactString()} '#{name}'")

        # since we're creating a new individual, add the appropriate assertions for it
        @ADD rdf.type @_type

        if more.label is undefined
            @ADD LABEL name
            @hasLabel = true
        else
            if IS_STRING(more.label)
                @ADD LABEL more.label
                @hasLabel = true
            else if more.label is false
                # do nothing
            else
                ABORT("Wrong label agument for individual #{name}")

        if more.ontoscriptProperties?
            @hasOntoscriptProperties = more.ontoscriptProperties

        INDIVIDUAL_COUNT += 1

        @log_unset()



    # METHODs: logging-related methods for this particular class (see LOG_SET, LOG and LOG_UNSET for more info).
    log_set   : (msg) -> LOG_SET "#{@qName().toCompactString()}", msg
    log       : (msg) -> LOG(msg)
    log_unset : ()    -> LOG_UNSET()


    addToStackIfNeeded: () ->
        #if root.STACKS.length is 0
            #@log_set "Not stacking this individual, since there's no active Stack"
        #

        if root.self == undefined
            @log_set "Not stacking this individual, since there's no active Stack"
        else if root.self.contains(this)
            @log_set "Not stacking this Individual, since it was already stacked"
        else
            @log_set "Stacking this Individual, since it wasn't stacked before"
            root.self.add(this)
        @log_unset()


    # METHOD: add another "sub"Individual, or add an assertion, or add a comments string.
    ADD: (x) ->

        if x instanceof Array
            @ADD(item) for item in x
        else
            if (x is undefined)
                @log_set "ADD (undefined)"
            else if x instanceof Individual
                @log_set "ADD #{x.toCompactString()}"
                if this[x._name]?
                    #JOIN(this[x._name], x)
                    ABORT("Cannot ADD #{x.toCompactString()}: an invidual already exists with that name!\n"+@toString())
                else
                    x.addNamePrefix(@_name)
                    # if we have a valid namespace, propagate it to the individual
                    if @ns.isDefined() then x.setNs(@ns)
                    # store the individual as an attribute
                    @attributes.push(x)
                    # also store the name of the individual
                    this[x._name] = x
                    x.isAdded = true
            else if x instanceof Shortcut
                @log_set "ADD #{x.toCompactString()}"
                @shortcuts.push(x)
                this[x.name] = x.item
            else if x instanceof DatatypeAssertion
                @log_set "ADD #{x.toCompactString()}"
                # for Datatype assertions, replace the data instead of adding it!
                replaced = false
                for assertion in @datatypeAssertions
                    if assertion.predicate.toCompactString() == x.predicate.toCompactString()
                        @log "replacing #{assertion.data} with #{x.data}"
                        assertion.data = x.data
                        @log "replacing #{assertion.datatype} with #{x.datatype}"
                        assertion.datatype = x.datatype
                        replaced = true
                # simply add the assertion if the predicate was not found
                if not replaced
                    @datatypeAssertions.push(x)
            else if x instanceof ObjectAssertion
                @log_set "ADD #{x.toCompactString()}"
                l = []
                l.push assertion.toCompactString() for assertion in @objectAssertions
                if not (x.toCompactString() in l)
                    @objectAssertions.push(x)
            else if isString(x)
                @log_set "ADD \"#{x}\""
                trimmed = x.trim()
                if trimmed isnt "" then @ADD(rdfs.comment trimmed)
            else if x instanceof Stack
                # clear the stack and remove it from first position of the STACKS array
                # (as STACKS[0] points to the currently active Stack)
                @log_set "ADD Stack \"#{x}\""
                Stack.clearActiveStack(x)

            else if x instanceof Macro
                @log_set "ADD #{x.toCompactString()}"
                if @ns.isDefined() then x.setNs(@ns)
                this[x._name] = x.execute()
            else if x instanceof Update
                @UPDATE_ATTRIBUTE( x.property, x.value, true)
            else if isMethod(x)
                for name, callable of x
                    this[name] = callable
            else if JSON.stringify(x) == "{}"
                @log_set "ADD ({})"
            else
                ABORT("Trying to add an unknown object (#{JSON.stringify(x)}) to #{@toCompactString()}")
            @log_unset()


    # METHOD: check if the namespace prefixes used in the attributes and assertions are allowed.
    checkNameSpacePrefixes: (prefixes) ->
        @log_set("checkNameSpacePrefixes")
        for assertion in @datatypeAssertions
            @log("checkNameSpacePrefixes for DatatypeAssertion #{assertion.toCompactString()}")
            assertion.checkNameSpacePrefixes(prefixes)

        for assertion in @objectAssertions
            @log("checkNameSpacePrefixes for ObjectAssertion #{assertion.toCompactString()}")
            assertion.checkNameSpacePrefixes(prefixes)

        for attribute in @attributes
            @log("checkNameSpacePrefixes for attribute #{attribute.toCompactString()}")
            attribute.checkNameSpacePrefixes(prefixes)

        @log_unset()


    # METHOD: add a name prefix to this individual, and all attributes. This method is used during the building of the
    # semantic model, since this model will be built incrementally from the most-nested individual to the least-nested
    # individual (i.e. the one that is eventually added to the Model).
    addNamePrefix: (namePrefix) ->
        @log_set("addNamePrefix #{namePrefix}")
        @namePrefixes.unshift(namePrefix)

        for attribute in @attributes
            attribute.addNamePrefix(namePrefix)
            this[attribute._name] = attribute

        @log_unset()


    # METHOD: set the namespace of the Individual.
    setNs: (ns) ->
        @log_set("setNs #{ns.toCompactString()}")

        # update the namespace details of this instance
        @ns = ns

        # also recursively update the namespace details of the owned attributes
        for attribute in @attributes
            attribute.setNs(ns)

        @log_unset()


    # METHOD: get the Qualified Name of the Individual, as a QName instance.
    qName: () =>
        return new QName(@ns, @_name, @namePrefixes)


    # METHOD: get the full name of the Individual.
    fullName: () =>
        return @qName().fullName()


    # METHOD: get a compact (one line) string representation.
    toCompactString: () ->
        return @qName().toCompactString()


    # METHOD: get a (potentially long) multi-line string representation.
    toString: (indent="") ->
        s =  "Individual '#{@_name}'\n"
        s += "#{indent} - qName: #{@qName().toCompactString()}\n"
        s += "#{indent} - type: #{@_type.toCompactString()}"
        if @datatypeAssertions.length > 0
            s += "\n#{indent} - datatypeAssertions:"
            for assertion in @datatypeAssertions
                s += "\n#{indent}    - #{assertion.toCompactString()}"
        if @objectAssertions.length > 0
            s += "\n#{indent} - objectAssertions:"
            for assertion in @objectAssertions
                s += "\n#{indent}    - #{assertion.toCompactString()}"
        if @shortcuts.length > 0
            s += "\n#{indent} - shortcuts:"
            for shortcut in @shortcuts
                s += "\n#{indent}    - #{shortcut.toCompactString(indent + "      ")}"
        if @attributes.length > 0
            s += "\n#{indent} - attributes:"
            for attribute in @attributes
                s += "\n#{indent}    - #{attribute.toString(indent + "      ")}"
        return s


    UPDATE_ATTRIBUTE : (predicate, newData, overwrite) =>
        predQName    = predicate.apply(undefined, [NAME_IDENTIFIER])
        predNsUri    = predQName.ns.uri
        predFullName = predQName.fullName()

        found = false
        for assertion in @datatypeAssertions
            if predNsUri is assertion.predicate.ns.uri and predFullName is assertion.predicate.fullName()
                found = true
                if overwrite?
                    assertion.data = newData

        if not found
            @ADD predicate newData


    # METHOD: serialize the Individual (and all its assertions and attributes) as JSON-LD.
    getJsonld: () ->
        if @hasLabel and @hasOntoscriptProperties
            #@UPDATE_ATTRIBUTE(ontoscript.fullName, @fullName(), true)
            @UPDATE_ATTRIBUTE(ontoscript.counter,  INDIVIDUAL_COUNTER, true)
            INDIVIDUAL_COUNTER = INDIVIDUAL_COUNTER + 1

        ret = []
        subj = "#{@ns.uri}##{@fullName()}"
        ret.push({ "@id" : subj })
        # add the triples for the object assertions and datatype assertions
        mergeJsonldPredicates(ret[0], assertion.getJsonldPredicates()) for assertion in @objectAssertions
        mergeJsonldPredicates(ret[0], assertion.getJsonldPredicates()) for assertion in @datatypeAssertions
        # add the triples for the attributes
        mergeJsonld(ret, attribute.getJsonld()) for attribute in @attributes
        return ret


#
#root.JOIN = (main, other) ->
#    # copy missing assertions
#    main.datatypeAssertions.concat other.datatypeAssertions
#    main.objectAssertions.concat other.objectAssertions
#
##    for otherAssertion in other.datatypeAssertions
##        main.ADD otherAssertion
##    for otherAssertion in other.objectAssertions
##        main.ADD otherAssertion
#    for attr in other.attributes
#        if not main[attr._name]?
#            main.ADD new Individual(attr._type, attr._name)
#
#        JOIN(main[attr._name], attr)



#root.COPY_MISSING_ATTRIBUTES = (from, relation, reference) ->
#    ret = []
#
#    referenceAttributeNames = []
#    for attribute in reference.attributes
#        referenceAttributeNames.push attribute._name
#
#    for attr in from.attributes
#        if not (attr._name in referenceAttributeNames)
#            individual = new Individual(attr._type, attr._name)
#            individual.ADD relation attr
#            ret.push individual
#
#        COPY_MISSING_ATTRIBUTES(attr, relation, reference[attr._name])
#
#    return ret



# ######################################################################################################################
# Create a function to extract explicit information from an Individual or Class using a sort-of "browse path"
# ######################################################################################################################

root.PATH = (subject, predicate) ->
    if not (subject?)
        ABORT("PATH(<subject>, <predicate>) has an undefined subject!")
    if not (predicate?)
        ABORT("PATH(<subject>, <predicate>) has an undefined predicate!")
    predQName = predicate.apply(undefined, [NAME_IDENTIFIER])
    predNsUri    = predQName.ns.uri
    predFullName = predQName.fullName()
    for assertion in subject.datatypeAssertions
        if predNsUri is assertion.predicate.ns.uri and predFullName is assertion.predicate.fullName()
            return assertion.data
    for assertion in subject.objectAssertions
        if predNsUri is assertion.predicate.ns.uri and predFullName is assertion.predicate.fullName()
            return assertion.object

    return undefined


root.PATHS = (subject, predicate) ->
    ret = []
    predQName = predicate.apply(undefined, [NAME_IDENTIFIER])
    predNsUri    = predQName.ns.uri
    predFullName = predQName.fullName()
    for assertion in subject.datatypeAssertions
        if predNsUri is assertion.predicate.ns.uri and predFullName is assertion.predicate.fullName()
            ret.push assertion.data
    for assertion in subject.objectAssertions
        if predNsUri is assertion.predicate.ns.uri and predFullName is assertion.predicate.fullName()
            ret.push assertion.object
    return ret

# ######################################################################################################################
# Create a class for the macros that we will be creating with this DSL
# ######################################################################################################################



# ----------------------------------------------------------------------------------------------------------------------
# CLASS : Macro
#
# A Macro is a function that can be added to a Model just like an Individual. A macro is created by the DSL user when
# he/she has to create multiple similar Individuals of the same type. The macros can contain parameters in order to
# "customize" the Individual creation.
#
# For example:
#
# music.ADD music.Band "CreateRockBand" : (country=countries.UK) -> [   # notice the default value for country
#     music.hasGenre music.ROCK
#     music.hasFoundingCountry country
# ]
#
# music.ADD CreateRockBand(1970) "queen" : [ foaf.name "Queen" ]
#
# # we may also create a nested macro:
# music.ADD music.CreateRockBand(countries.Ireland) "CreateIrishRockBand" : () -> []
#
# music.ADD music.CreateIrishRockBand() "u2" : [ foaf.name "U2" ]
# ----------------------------------------------------------------------------------------------------------------------
class Macro


    # CONSTRUCTOR: add a Macro by specifying
    #                - the function used to build the individual, e.g. music.Band
    #                - the Macro name, e.g. "CreateIrishRockBand"
    #                - the macro function, e.g .(country=countries.UK) -> [ music.hasFoundingCountry country ]
    constructor: (@individualBuilder, @_name, @function) ->
        @ns = new NameSpace()
        @log_set("new Macro <function>, '#{@_name}', <function>")
        @log_unset()


    # METHODs: logging-related methods for this particular class (see LOG_SET, LOG and LOG_UNSET for more info).
    log_set   : (msg) -> LOG_SET @toCompactString(), msg
    log       : (msg) -> LOG(msg)
    log_unset : ()    -> LOG_UNSET()


    # METHOD: set a new namespace.
    setNs: (ns) ->
        @log_set("setNs '#{ns}'")
        # update the namespace details of this macro
        @ns = ns
        @log_unset()


    # METHOD: execute the macro
    execute: () =>

        # Suppose we have the following statements:
        #    example 1: mymodel.ADD SomeMacro(arg0, arg1) "someIndividual"
        #    example 2: mymodel.ADD SomeMacro(arg0, arg1) "someIndividual" : [ mymetamodel.says "Hi!" ]
        #    example 3: mymodel.ADD SomeMacro(arg0, arg1) "SomeOtherMacro" : () ->
        # then
        #    'SomeMacro' returns a function with (in this case) 'args...' equal to 'arg0, arg1'
        #    'SomeMacro(args...)' returns a function that accepts a string (example 1) or an object (example 2 and 3)
        #    'SomeMacro(args...) nameOrObject' returns an Individual (example 1 and 2) or another Macro (example 3)
        return (args...) =>

            # make a nice string of the arguments
            argsString = ""
            for arg in args
                if argsString.length > 0 then argsString += ", "
                if arg?
                    if arg.toCompactString? then argsString += arg.toCompactString()
                    else if arg.toString? then argsString += arg.toString()
                    else argsString += JSON.stringify(arg)
                else
                    argsString += "undefined"

            @log_set("Executing the macro with arguments [#{argsString}]")

            @log "Returning a Macro/Individual building function for #{@_name}(#{argsString})"

            ret = (nameOrObject, more) =>
                @log_set()

                # we will first check if the macro is being used as in example 1, 2 or 3
                name         = undefined # name of the Individual or Macro (examples 1,2,3)
                assertions   = undefined # assertions of the Individual (example 1,2)
                newFunction  = undefined # function of the new Macro being created (example 3)
                creatingIndividual = false
                creatingMacro      = false

                if nameOrObject is INITOR
                    # apply the macro
                    @log "INIT: Now applying #{@_name}(#{argsString})"
                    macroResults = @function.apply(undefined, args)

                    # log the results
                    @log "Results of applying #{@_name}(#{argsString}):"
                    for macroResult in macroResults
                        if macroResult instanceof Array
                            for item in macroResult
                                if item?
                                    if item.toCompactString?
                                        @log " - #{item.toCompactString()}"
                                    else if isIndividual(item) or isStack(item) or isModel(item) or isMetaModel(item)
                                        @log " - #{item.toString("   ")}"
                                    else
                                        @log " - #{item}"
                        else
                            if macroResult?
                                if macroResult.toCompactString?
                                    @log " - #{macroResult.toCompactString()}"
                                else if isIndividual(item) or isStack(item) or isModel(item) or isMetaModel(item)
                                    @log " - #{item.toString("   ")}"
                                else
                                    @log " - #{macroResult}"

                    @log "Now returning the macro results"
                    @log_unset()
                    return macroResults

                else if isString(nameOrObject)
                    name               = nameOrObject
                    assertions         = []
                    creatingIndividual = true
                    @log "Creating an Individual with name '#{name}' and no extra assertions"
                else
                    for nameString, arrayOrFunction of nameOrObject
                        name = nameString
                        if arrayOrFunction instanceof Array
                            assertions         = arrayOrFunction
                            creatingIndividual = true
                            @log "Creating an Individual with name '#{name}' and #{assertions.length} assertions"
                        else if arrayOrFunction instanceof Function
                            newFunction   = arrayOrFunction
                            creatingMacro = true
                            @log "Creating a Macro with name '#{name}'"
                        else
                            ABORT "Invalid argument #{JSON.stringify(nameOrObject)} for #{@toString()}"


                if creatingIndividual

                    @log "We found an Individual builder"

                    individual = @individualBuilder.call(undefined, nameOrObject, more)

                    # when a Macro is executed, currently existing Stacks (e.g. $ and $$) may also be used by the Macro.
                    # Therefore we must temporarily store the existing stacks, and make a new set of cleared available
                    # stacks
#                    for stack in root.STACKS
#                        stackNames.push(stack._name)
#                        oldStacks.push(stack)
#                        root[stack._name] = new Stack(stack._name)
#                        root[stack._name].$ = stack.clone()
#
#                                        #root.$  = new Stack('$')
#                                        #root.$.$ = $.clone()
#
#                    @log "The following stacks have been stored:"
#                    for stack in root.STACKS
#                        @log root[stack._name].toString()
#
#                    root.STACKS = []
#
#                    @log "The stacks are now stored"

                    # apply the macro while using the macro Stack:
                    @log "Creating individual: now applying #{@_name}(#{argsString})"

                    root.INIT()

                    macroResults = @function.apply(undefined, args)

                    # log the results
                    @log "Results of applying #{@_name}(#{argsString}):"
                    for macroResult in macroResults
                        if macroResult instanceof Array
                            for item in macroResult
                                if item?
                                    if item.toCompactString?
                                        @log " - #{item.toCompactString()}"
                                    else
                                        @log " - #{item.toString("   ")}"
                        else
                            if macroResult?
                                if macroResult.toCompactString?
                                    @log " - #{macroResult.toCompactString()}"
                                else if isIndividual(item) or isStack(item) or isModel(item) or isMetaModel(item)
                                    @log " - #{item.toString("   ")}"
                                else
                                    @log " - #{macroResult}"


                    @log "Now adding the assertions that were found by executing the macro, to the individual"
                    individual.ADD(macroResults)

#                    # restore the stacks
#                    stackNames = []
#                    root.STACKS = []
#                    for stack in oldStacks
#                        stackNames.push(stack._name)
#                        root.STACKS.push(stack)
#                        root[stack._name] = stack
#
#                    @log "The following stacks have been restored: [#{stackNames}]"
#
#                    for stack in root.STACKS
#                        @log stack.toString()

                    root.EXIT()

                    @log_unset()
                    return individual

                else if creatingMacro
                    # the new macro will also need to have a function to build Individuals:
                    individualBuilder = (newNameOrObject...) =>
                        return root[@ns.prefix][@_name].apply(undefined, args).apply(undefined, newNameOrObject)

                    # define the new macro
                    newMacro = new Macro(individualBuilder, name, newFunction)

                    @log_unset()
                    return newMacro
                else
                    ABORT("Bug in ontoscript: neither creating an Individual or a Macro")


            @log_unset()
            return ret


    # METHOD: get a string representation.
    toString: () ->
        return "Macro #{@_name}"


    # METHOD: get a string representation.
    toCompactString: () ->
        return @toString()


# ######################################################################################################################
# Create a class for the existing metamodels that we can import
# ######################################################################################################################



# ----------------------------------------------------------------------------------------------------------------------
# CLASS : MetaModel
#
# A MetaModel is an imported ontology, consisting of classes, properties and individuals. MetaModels cannot be created
# from scratch by the DSL as the DSL cannot define OWL classes nor properties.
# So you need to create a MetaModel (=an OWL ontology) with another editor (such as Protege) and import it with the
# DSL. Only ontologies serialized as JSON-LD can be imported.
# Third party tools (such as the python RDFlib) can be used to convert other formats (e.g. turtle or XML/RDF) into
# JSON-LD.
# ----------------------------------------------------------------------------------------------------------------------
class MetaModel


    # CONSTRUCTOR: create a new MetaModel for the given namespace URI and prefix.
    constructor: (nsUri, nsPrefix) ->
        @ns = new NameSpace(nsUri, nsPrefix)
        @log_set("new MetaModel '#{nsUri}', '#{nsPrefix}'")
        @classes = []
        @datatypeProperties = []
        @objectProperties = []
        @individuals = []
        @imports = []
        @log_unset()


    # METHODs: logging-related methods for this particular class (see LOG_SET, LOG and LOG_UNSET for more info).
    log_set   : (msg) -> LOG_SET "#{@ns.toCompactString()}", msg
    log       : (msg) -> LOG(msg)
    log_once  : (msg) -> LOG("#{@ns.toCompactString()}", msg)
    log_unset : ()    -> LOG_UNSET()


    # METHOD: read the contents of a json-ld file.
    READ : (fileName, ABSOLUTE=false, STRICT=false) ->
        @log_set "READ '#{fileName}', ABSOLUTE=#{ABSOLUTE}"
        if not ABSOLUTE then dirs = READ_PATHS
        f = findFile(fileName, dirs, ".jsonld")
        @log "Now reading the contents of the file"
        contents = fs.readFileSync(f)
        @log "Now parsing as JSON"
        jsonld = JSON.parse(contents)
        @log "Now building the RDF graph"
        @parseJsonld(jsonld, STRICT)
        @log_unset()

    getImportedNameSpacePrefixes : () =>
        ret = []
        for ontology in @imports
            if ontology.ns.prefix isnt @ns.prefix # prevent self-inclusion (will result in infinite loop!)
                ret.push( ontology.ns.prefix ) if ontology.ns.prefix not in ret
                prefixes = ontology.getImportedNameSpacePrefixes()
                for prefix in prefixes
                    ret.push( prefix ) if prefix not in ret
        return ret



    getAllowedNameSpacePrefixes : () ->
        # populate the list first with the standard prefixes:
        ret = STANDARD_NS_PREFIXES.slice()
        # then at the prefix of this Model instance
        ret.push(@ns.prefix)
        # then at the prefixes of the imported metamodels and models
        importedPrefixes = @getImportedNameSpacePrefixes()
        for prefix in importedPrefixes
            ret.push( prefix ) if prefix not in ret
        return ret



    # METHOD: parse some triples serialized as JSON-LD and extract the classes, individuals and properties.
    parseJsonld : (jsonld, strict=false) ->
        @log_set("parseJsonld(..., strict=#{strict})")

        if jsonld["@context"]?
            context = jsonld["@context"]
            graph   = jsonld["@graph"]
        else
            graph = jsonld

        # see http://www.w3.org/TR/owl-parsing/ for more info about the different parsing passes
        NAMED_OBJECTS_PASS   = 0
        #AXIOMS_PASS = 1
        #TRANSLATING_LISTS_PASS = 2
        #TRANSLATING_CLASS_DESCRIPTIONS_PASS = 3
        #TRANSLATING_DATA_RANGES_PASS = 4
        #STRUCTURE_SHARING_PASS = 5
        EVERYTHING_ELSE_PASS   = 6


        for pass in [NAMED_OBJECTS_PASS, EVERYTHING_ELSE_PASS]

            @log "Starting pass #{pass}"

            # iterate over all triples of the graph
            for triples in graph
                subject = triples["@id"]

                if triples["@id"]?

                    # parse the subject, so that we get a nice QName
                    subject = QName.fromJsonldUri(triples["@id"], context, strict)

                    if not subject?
                        # anonymous or unknown node, nothing to do
                    else if subject.fullName() is ""
                        # we're dealing with the ontology itself
                        imports = triples["owl:imports"]
                        if imports?
                            uris = []
                            if imports["@id"]?
                                uris.push(imports["@id"])
                            else if imports instanceof Array
                                for im in imports
                                    uris.push(im["@id"])

                            for uri in uris
                                @addImport uri
                    else

                        # add the named objects pass
                        if pass is NAMED_OBJECTS_PASS

                            # make a list of the types (which are serialized as strings)
                            if not triples["@type"]
                                typeStrings = []
                            if isString(triples["@type"])
                                typeStrings = [ triples["@type"] ]
                            else if triples["@type"] instanceof Array
                                typeStrings = triples["@type"]
                            else
                                typeStrings = []

                            for typeString in typeStrings

                                # parse the type string, so that we get a nice QName
                                type = QName.fromJsonldUri(typeString, context, strict)

                                # only proceed if we get a valid type (i.e. a known, non-blank, well formatted node)
                                if type?

                                    # get a reference to the metamodel
                                    mm = root[subject.ns.prefix]

                                    if mm[subject.fullName()]?
                                        # the class or property already exists! Skip it!
                                    else if type.ns.prefix is owl.ns.prefix
                                        if type.fullName() is "Class"
                                            mm.addClass(subject.fullName())
                                        else if type.fullName() is "DatatypeProperty"
                                            mm.addDatatypeProperty(subject.fullName())
                                        else if type.fullName() in [ "ObjectProperty",
                                                                     "TransitiveProperty",
                                                                     "InverseFunctionalProperty",
                                                                     "SymmetricProperty" ]
                                            mm.addObjectProperty(subject.fullName())

                                    else if type.ns.prefix is rdfs.ns.prefix
                                        if type.fullName() is "Class"
                                            mm.addClass(subject.fullName())
                                        else if type.fullName() is "Datatype"
                                            mm.addClass(subject.fullName())


                        else if EVERYTHING_ELSE_PASS

                            # Every @id we encounter now must be either:
                            #   - already existing (e.g. a Class, a property, or an Individual)
                            #   - a new Individual

                            # first check if the subject is already known
                            subjectRef = getObjectReference(subject)

                            # if it's undefined, we can create an individual
                            if not subjectRef?
                                subjectRef = mm.addIndividual(subject.fullName())

                            # if the subject is an individual, we can add more axioms to it
                            if subjectRef instanceof Individual

                                # iterate over the triples and add everything useful
                                for predicateString, objectContents of triples

                                    if not (predicateString in ["@id"])

                                        predicate = QName.fromJsonldUri(predicateString, context, strict)

                                        if not (predicate?)
                                            @log "Warning: couldn't add #{subjectRef.toCompactString()} " \
                                                 + "#{predicateString} #{JSON.stringify(objectContents)} " \
                                                 + "because #{predicateString} is unknown"

                                        else
                                            preficateRef = getObjectReference(predicate)

                                            if preficateRef instanceof Function
                                                # if the predicate is an owl:Class, we can add the class name
                                                # as the type of the individual
                                                predicateName  = preficateRef.apply(undefined, [NAME_IDENTIFIER])
                                                predicateType  = preficateRef.apply(undefined, [TYPE_IDENTIFIER])

                                                if objectContents instanceof Array
                                                    objectContentList = objectContents
                                                else
                                                    objectContentList = [ objectContents ]

                                                for objectContent in objectContentList

                                                    if (predicateType is "ObjectProperty") and (objectContent["@id"]?)

                                                        object = QName.fromJsonldUri(objectContent["@id"], context, strict)

                                                        objectRef = getObjectReference(object)
                                                        if objectRef?
                                                            subjectRef.ADD preficateRef objectRef
                                                    else if predicateType is "DatatypeProperty"
                                                        if objectContent["@value"]
                                                            object = objectContent["@value"]
                                                        else
                                                            object = objectContent

                                                        subjectRef.ADD preficateRef object

        @log_unset()


    # METHOD: add an imported ontology.
    addImport: (uriOrMetaModel) =>
        if isString(uriOrMetaModel)
            uri = uriOrMetaModel
            @log_set("addImport '#{uri}'")
            mm = NSURI_TO_METAMODEL[uri]
            if mm?
                alreadyAdded = false
                for im in @imports
                    if im.ns.prefix is mm.ns.prefix
                        alreadyAdded = true
                if not alreadyAdded
                    @imports.push(mm)
                    @log "imported #{mm.ns.prefix}"
            else
                ABORT "Trying to import <#{uri}> but this URI is unknown. Did you REQUIRE the correct file(s)?"
            @log_unset()
        else if uriOrMetaModel instanceof MetaModel
            mm = uriOrMetaModel
            @log_set("addImport '#{mm.ns.prefix}'")
            @imports.push(mm)
            @log_unset()
        else
            ABORT "Invalid argument of <#{@ns.prefix}>.addImport(#{uriOrMetaModel}): expected URI or MetaModel instance"


    # METHOD: add an OWL class to the MetaModel.
    addClass: (className) ->
        @log_set("addClass '#{className}'")

        @classes.push(className)

        this[className] = (nameOrDictionary, more) =>
            # to use this property, we require that a namespace prefix is defined!
            if @ns.prefix?
                ret = undefined

                if nameOrDictionary is NAME_IDENTIFIER
                    ret = new QName(@ns, className)
                else if nameOrDictionary is TYPE_IDENTIFIER
                    ret = "class"
                else if isString(nameOrDictionary)
                    @log_set "Now calling #{className} \"#{nameOrDictionary}\" to create an Individual without assertions"
                    ret = new Individual(new QName(@ns, className), nameOrDictionary, more)
                    ret.addToStackIfNeeded()
                    @log "Declaring #{ret.toCompactString()}"

                else if nameOrDictionary instanceof Individual
                    ABORT "Invalid argument for  #{@ns.uri}##{className} " \
                            + "(expected \"someName\" or \"someName\" : [ some assertions... ], but got an " \
                            + "Individual instead!)"

                else
                    for name, argument of nameOrDictionary

                        if ret? then ABORT("Syntax error: #{@ns.uri}##{className} accepts only one list " \
                                           + "of assertions, or one macro")

                        if argument instanceof Array
                            @log_set "Now calling #{className} \"#{name}\" to create an Individual with #{argument.length} assertions"
                            ret = new Individual(new QName(@ns, className), name, more)
                            ret.ADD(argument)
                            ret.addToStackIfNeeded()
                        else if argument instanceof Function
                            @log_set "Now calling #{className} \"#{name}\" to create a Macro"
                            #ret = new Macro(new QName(@ns, className), name, argument)
                            ret = new Macro(this[className], name, argument)
                        else
                            ABORT("Invalid arg")

                if ret?
                    @log_unset()
                    return ret
                else
                    ABORT("Syntax error: no valid arguments for #{@ns.uri}##{className}(#{nameOrDictionary})")
            else
                ABORT("Could not declare #{@ns.uri}##{className}(#{nameOrDictionary}) because no " \
                      + "namespace prefix is known for '#{@ns.uri}'. " \
                      + "Has a valid namespace prefix been set (e.g. by importing the namespace)?")

        @log_unset()


    # METHOD: add an OWL object property to the MetaModel.
    addObjectProperty: (propertyName) =>
        @log_set("addObjectProperty '#{propertyName}'")
        @objectProperties.push(propertyName)

        this[propertyName] = (x) =>
            if x is NAME_IDENTIFIER
                return new QName(@ns, propertyName)
            else if x is TYPE_IDENTIFIER
                return "ObjectProperty"
            else if x instanceof Function
                x = x.call(undefined, NAME_IDENTIFIER)

            if not (x?)
                ABORT "Argument of #{@ns.prefix}.#{propertyName} is undefined!"
            else if x.toCompactString?
                @log_set "#{@ns.prefix}:#{propertyName} #{x.toCompactString()}"
            else
                @log_set "#{@ns.prefix}:#{propertyName} '#{x.toString()}'"

            ret = []
            if x instanceof Individual
                oa = new ObjectAssertion(new QName(@ns, propertyName), x)
                ret.push(oa)
                # also store the object itself if it has not been defined before
                if x.isAdded
                    @log "Not returning #{x.toCompactString()} since it was already added"
                else
                    @log "Also returning #{x.toCompactString()}"
                    ret.push(x)
                    x.isAdded = true
            else if (x instanceof MetaModel) or (x instanceof Model)
                oa = new ObjectAssertion(new QName(@ns, propertyName), x)
                ret.push(oa)
            else if x instanceof QName
                oa = new ObjectAssertion(new QName(@ns, propertyName), x)
                ret.push(oa)
            else if x instanceof Array
                for element in x
                    ret.push( this[propertyName](element) )
            else if x instanceof Function
                qName = x.call(undefined, NAME_IDENTIFIER)
                if qName?
                    oa = new ObjectAssertion(new QName(@ns, propertyName), qName)
                    ret.push(oa)
                else
                    ABORT("""Invalid range for ObjectProperty #{@ns.uri}##{propertyName}:
                          '#{x}' is not a valid callable argument!""")
            else
                ABORT("""Invalid range for ObjectProperty #{@ns.uri}##{propertyName}:
                      '#{x}' is not a valid argument!""")
            @log_unset()
            return ret

        @log_unset()


    # METHOD: add an OWL datatype property to the MetaModel.
    addDatatypeProperty: (propertyName) =>
        @log_set("addDatatypeProperty '#{propertyName}'")
        @datatypeProperties.push(propertyName)

        this[propertyName] = (contents) =>
            if contents is NAME_IDENTIFIER
                return new QName(@ns, propertyName)
            else if contents is TYPE_IDENTIFIER
                return "DatatypeProperty"

            @log_set "Now calling property '#{propertyName}'"

            da = new DatatypeAssertion(new QName(@ns, propertyName), contents)
            #@log "Declaring #{da.toCompactString()}"
            @log_unset()

            return [ da ]

        @log_unset()


    # METHOD: add an OWL individual to the MetaModel.
    addIndividual: (name, type=new QName(owl.ns, "Thing")) =>
        @log_set("addIndividual '#{name}'")
        @individuals.push(name)
        individual = new Individual(type, name)
        individual.addToStackIfNeeded()
        individual.isAdded = true
        individual.setNs(@ns)
        this[name] = individual

        @log_unset()
        return individual


    # METHOD: add a macro
    ADD: (x) ->
        if x instanceof Macro
            @log_set "ADD #{x.toCompactString()}"
            x.setNs(@ns)
            this[x._name] = x.execute()
        else if x instanceof Stack
            # clear the stack and remove it from first position of the STACKS array
            # (as STACKS[0] points to the currently active Stack)
            @log_set "ADD Stack \"#{x._name}\""
            Stack.clearActiveStack(x)
        else
            ABORT("Cannot add #{x} to model #{@ns.prefix}: only Macros can be added to MetaModels!")

        @log_unset()


    # METHOD: Get a compact, single line string representation.
    toCompactString: () ->
        return  "#{@ns.prefix}"


    # METHOD: Get a full string representation.
    toString: (indent="") ->
        s =  "MetaModel '#{@ns.uri}'\n"
        # for the nsPrefix, omit the '' if undefined:
        s += "#{indent} - ns: #{@ns}\n"
        # add the class names:
        s += "#{indent} - classes:\n"
        s += "#{indent}    * '#{className}'\n" for className in @classes
        # add the object property names:
        s += "#{indent} - individuals:\n"
        s += "#{indent}    * #{this[individualName].toString(indent + "      ")}\n" for individualName in @individuals
        # add the object property names:
        s += "#{indent} - objectProperties:\n"
        s += "#{indent}    * '#{propertyName}'\n" for propertyName in @objectProperties
        # add the datatype property names:
        s += "#{indent} - datatypeProperties:"
        s += "\n#{indent}    * '#{propertyName}'" for propertyName in @datatypeProperties
        return s


# ----------------------------------------------------------------------------------------------------------------------
# FUNCTION : METAMODEL(nsUriAndPrefix)
#
# Declare a MetaModel with a given namespace URI and prefix.
# ----------------------------------------------------------------------------------------------------------------------
root.METAMODEL = (nsUriAndPrefix) ->
    if not isStringDictionary(nsUriAndPrefix, levels=1)
        ABORT "Invalid argument '#{nsUriAndPrefix}' for METAMODEL <uri> : <prefix>"

    for nsUri, nsPrefix of nsUriAndPrefix
        # check if the namespace details are already known
        if root[nsPrefix]?
            ABORT "Cannot define MetaModel #{nsPrefix}, this namespace prefix is already assigned!"
        if NSURI_TO_METAMODEL[nsUri]?
            ABORT "Cannot define MetaModel #{nsUri}, this namespace URI is already assigned"

        # create a new MetaModel
        mm = new MetaModel(nsUri, nsPrefix)
        # store some pointers the metamodel
        root[nsPrefix]            = mm
        NSURI_TO_METAMODEL[nsUri] = mm
        # and store the namespace prefix in the ALL_PREFIXES list
        if not (nsPrefix in root.ALL_PREFIXES) then root.ALL_PREFIXES.push(nsPrefix)
        # return a pointer to the metamodel
        return mm



# ######################################################################################################################
# Create a class for the models that we will be creating with this DSL
# ######################################################################################################################



# ----------------------------------------------------------------------------------------------------------------------
# CLASS : Model
#
# A Model is an ontology created by the DSL user, consisting of individuals, assertions and macros. The macros exist
# only within the DSL environment and will not be written/serialized.
# ----------------------------------------------------------------------------------------------------------------------
class Model


    # CONSTRUCTOR: create a Model by specifying a namespace URI and namespace prefix.
    constructor: (nsUri, nsPrefix) ->
        @ns = new NameSpace(nsUri, nsPrefix)
        @datatypeAssertions = []
        @objectAssertions   = []
        @instances = []
        @imports = []

        @log_set "new Model '#{nsUri}'"

        @ADD(rdf.type new QName(owl.ns, "Ontology"))
        @ADD(prov.generatedAtTime root.timeUtcNow().value)

        @IMPORT ontoscript

        @log_unset()
        SUMMARY("Model #{@ns.toCompactString()}")


    # METHODs: logging-related methods for this particular class (see LOG_SET, LOG and LOG_UNSET for more info).
    log_set   : (msg) -> LOG_SET "#{@ns.toCompactString()}", msg
    log       : (msg) -> LOG(msg)
    log_once  : (msg) -> LOG("#{@ns.toCompactString()}", msg)
    log_unset : ()    -> LOG_UNSET()


    IMPORT : (ontology) =>

        if (ontology instanceof Model) or (ontology instanceof MetaModel)
            @log_set "IMPORT #{ontology.ns.prefix}"
        else
            ABORT "Cannot IMPORT #{ontology}: invalid arguments (expected: Model or MetaModel)"

        @imports.push(ontology)

        @ADD owl.imports ontology

        @log_unset()


    getImportedNameSpacePrefixes : () =>
        ret = []
        for ontology in @imports
            if ontology.ns.prefix isnt @ns.prefix
                ret.push( ontology.ns.prefix ) if ontology.ns.prefix not in ret
                prefixes = ontology.getImportedNameSpacePrefixes()
                for prefix in prefixes
                    ret.push( prefix ) if prefix not in ret
        @log_unset()
        return ret


    getAllowedNameSpacePrefixes : () ->
        # populate the list first with the standard prefixes:
        ret = STANDARD_NS_PREFIXES.slice()
        # then at the prefix of this Model instance
        ret.push(@ns.prefix)
        # then at the prefixes of the imported metamodels and models
        importedPrefixes = @getImportedNameSpacePrefixes()
        for prefix in importedPrefixes
            ret.push( prefix ) if prefix not in ret
        return ret


    WRITE_TOPBRAID_HEADER: (fullPath) ->
        @log_set "WRITE \"#{fullPath}\""

        header = ""
        header += "# baseURI: #{@ns.uri}\n"

        for assertion in @objectAssertions
            if assertion.predicate.toCompactString() is "owl:imports"
                header += "# imports: #{assertion.object.ns.uri}\n"

        fs.writeFileSync(fullPath, header)

        @log_unset()


    # METHOD: write the model to the stdout and/or a file.
    WRITE: (fileName="") ->

        LOG_DIAGNOSTICS()

        @log_set "WRITE \"#{fileName}\""

        if not root.MODEL_NO_WRITE

            if root.MODEL_WRITE_COMPACT
                jsonString = JSON.stringify(@getJsonld())
            else
                jsonString = JSON.stringify(@getJsonld(), "", "  ")

            if not root.MODEL_OUTPUT_PATH?
                @log "Writing to stdout (because no output directory was not given)"
                console.log jsonString
            else if fileName is ""
                @log "Writing to stdout (because no argument was not given for WRITE)"
                console.log jsonString
            else if fileName[-7..] isnt ".jsonld"
                ABORT "Invalid argument for WRITE '#{fileName}': " \
                    + "the argument should be a filename with a .jsonld extension!"
            else
                fullPath = path.join(root.MODEL_OUTPUT_PATH, fileName)
                @log "Writing to file #{fullPath}"

                if not root.MODEL_WRITE_FORCE
                    if fs.existsSync(fullPath)
                        @log "The file exists already!"
                        ABORT """Cannot write to file #{fullPath} because this file exists already!
                                 Use the 'force write' flag (-f) to overwrite the existing file."""

                fullDirPaths = []
                dirName = path.dirname(fileName)
                while dirName isnt ""
                    fullDirPath = path.join(root.MODEL_OUTPUT_PATH, dirName)
                    if fs.existsSync(fullDirPath)
                        @log "Directory #{fullDirPath} exists"
                        break
                    else
                        @log "Directory #{fullDirPath} does not exist, so we will try to create it"
                        fullDirPaths.unshift(fullDirPath)
                        dirName = path.dirname(dirName)

                for fullDirPath in fullDirPaths
                    @log "Creating directory #{fullDirPath}"
                    fs.mkdirSync(fullDirPath)

                @log "Now writing the JSON output to #{fullPath}"
                fs.writeFileSync(fullPath, jsonString)
                @log "File #{fullPath} has been successfully written"

                if root.MODEL_WRITE_TOPBRAID
                    @WRITE_TOPBRAID_HEADER(fullPath[..-7] + "topbraid.header")

        if LOG_VERBOSE
            @log "All prefixes: #{root.ALL_PREFIXES}"
            @log "Semantic model:"
            console.log @toString()

        @log_unset()

        return @getJsonld()


    # METHOD: add a nested individual, or assertion, or macro, or comments string to the Model.
    ADD: (x) ->

        if x instanceof Array
            @ADD(item) for item in x
        else
            if x instanceof Individual
                @log_set "ADD #{x.toCompactString()}"
                SUMMARY(" #{x.toCompactString()}")
                @log "Setting the namespace to all attributes:"
                x.setNs(@ns)
                @log "Checking the namespace prefixes of all attributes:"
                x.checkNameSpacePrefixes(@getAllowedNameSpacePrefixes())
                @instances.push(x)
                this[x._name] = x
                x.isAdded = true
            else if x instanceof DatatypeAssertion
                @log_set "ADD #{x.toCompactString()}"
                x.checkNameSpacePrefixes(@getAllowedNameSpacePrefixes())
                @datatypeAssertions.push(x)
            else if x instanceof ObjectAssertion
                @log_set "ADD #{x.toCompactString()}"
                x.checkNameSpacePrefixes(@getAllowedNameSpacePrefixes())
                @objectAssertions.push(x)
            else if x instanceof Macro
                @log_set "ADD #{x.toCompactString()}"
                x.setNs(@ns)
                this[x._name] = x.execute()
            else if isString(x)
                @log_set "ADD #{x.toString()}"
                trimmed = x.trim()
                if trimmed isnt "" then @ADD(rdfs.comment trimmed)
            else if x instanceof Stack
                @log_set "ADD Stack \"#{x._name}\""
                # clear the stack and remove it from first position of the STACKS array
                # (as STACKS[0] points to the currently active Stack)
                Stack.clearActiveStack(x)
            else
                ABORT("Cannot add #{x} to model #{@ns.prefix}: invalid type!")

            @log_unset()


    # METHOD: get a compact, single line string representation.
    toCompactString: () ->
        return  @ns.prefix


    # METHOD: get a full string representation.
    toString: (indent="") ->
        s =  "Model '#{@ns.prefix}'\n"
        s += "#{indent} - ns: #{@ns}\n"
        s += "#{indent} - imports: " + (ontology.ns.prefix for ontology in @imports) + "\n"
        s += "#{indent} - allowedNameSpacePrefixes: #{@getAllowedNameSpacePrefixes()}\n"
        s += "#{indent} - datatypeAssertions:\n"
        for assertion in @datatypeAssertions
            s += "#{indent}    - #{assertion.toCompactString()}\n"
        s += "#{indent} - objectAssertions:\n"
        for assertion in @objectAssertions
            s += "#{indent}    - #{assertion.toCompactString()}\n"
        s += "#{indent} - instances:"
        for instance in @instances
            s += "\n#{indent}    * #{instance.toString(indent + "      ")}"
        return s


    # METHOD: serialize the model as JSON-LD
    getJsonld: () ->
        ret = {}

        # create the context
        ret["@context"] = {}
        ret["@context"][nsPrefix] = "#{root[nsPrefix].ns.uri}#" for nsPrefix in root.ALL_PREFIXES

        assertions = { "@id" : @ns.uri }
        mergeJsonldPredicates(assertions, assertion.getJsonldPredicates()) for assertion in @datatypeAssertions
        mergeJsonldPredicates(assertions, assertion.getJsonldPredicates()) for assertion in @objectAssertions
        ret["@graph"] = [ assertions ]

        mergeJsonld(ret["@graph"], instance.getJsonld()) for instance in @instances

        return ret



# ----------------------------------------------------------------------------------------------------------------------
# FUNCTION : MODEL(args)
#
# Create a model by providing
#   nsUri : nsPrefix
# E.g.
#   MODEL "/my/organizations/namespace/uri/some/machine/we/built" : "someMach"
# ----------------------------------------------------------------------------------------------------------------------
root.MODEL = (args) ->
    LOG_SET "", "MODEL #{JSON.stringify(args)}"
    nsUri = undefined
    nsPrefix = undefined

    if isStringDictionary(args, levels=1)
        for key, value of args
            nsUri = key
            nsPrefix = value
    else
        ABORT("""Invalid arguments '#{JSON.stringify(args)}' for MODEL!
              Usage: MODEL \"http://some/uri\" : \"someprefix\" """)


    LOG "Now creating a model for URI='#{nsUri}' PREFIX='#{nsPrefix}'"

    # check if the prefix doesn't exist yet
    if root[nsPrefix]?
        ABORT("Trying to create a model for prefix '#{nsPrefix}', but this prefix is already defined!")

    # check the namespace URI isn't the same as a metamodel namespace URI
    if NSURI_TO_METAMODEL[nsUri]?
        ABORT("Trying to create a model for URI '#{nsUri}', but this URI is already used by a metamodel!")

    # create a new Model and store it
    m = new Model(nsUri, nsPrefix)
    root.CURRENT_MODEL  = m
    root[nsPrefix] = m
    root.NSURI_TO_MODEL[nsUri] = m

    # store the namespace prefix in the CONTEXT list
    root.ALL_PREFIXES.push(nsPrefix)

    LOG_UNSET()



# ######################################################################################################################
# Declare some standard metamodel ontologies.
# ######################################################################################################################



# declare some standard ontologies (=metamodels)
METAMODEL "http://www.w3.org/2002/07/owl"              : "owl"
METAMODEL "http://www.w3.org/2001/XMLSchema"           : "xsd"
METAMODEL "http://www.w3.org/1999/02/22-rdf-syntax-ns" : "rdf"
METAMODEL "http://www.w3.org/2000/01/rdf-schema"       : "rdfs"
METAMODEL "http://www.w3.org/ns/prov"                  : "prov"

# add some commenly used classes and properties:
#  - for owl:
owl.addClass "Thing"
owl.addObjectProperty("imports")
owl.addObjectProperty("sameAs")
owl.addObjectProperty("differentFrom")
#  - for rdf:
rdf.addClass "Bag"
rdf.addObjectProperty("type")
rdf.addDatatypeProperty("value")
#  - for rdfs:
rdfs.addDatatypeProperty("comment")
rdfs.addDatatypeProperty("label")
#  - for prov (Provenance)
prov.addDatatypeProperty("generatedAtTime")


METAMODEL "http://mercator.iac.es/onto/metamodels/ontoscript" : "ontoscript"
ontoscript.addDatatypeProperty("counter")
ontoscript.addDatatypeProperty("hasViewCategory")
ontoscript.addDatatypeProperty("hasViewType")
ontoscript.addDatatypeProperty("hasViewPriority")
ontoscript.addObjectProperty("views")
ontoscript.addClass "View"

# ######################################################################################################################
# Declare "shortcuts" or "built-in predicates" of our DSL
# ######################################################################################################################
root.TYPE = rdf.type
root.COMMENT = rdfs.comment
root.LABEL = rdfs.label
root.BAG = () -> rdf.Bag
root.SAME_AS = owl.sameAs

# special definition of "has" --> syntacic sugar
root.HAS = (individual) ->
    if individual instanceof Individual
        fullPredicate = "has#{individual._type.fullName()}"
        ns = root[individual._type.ns.prefix]
        return ns[fullPredicate] individual
    else
        ABORT("Invalid use of HAS ... : Individual expected!")


# ######################################################################################################################
# HAS_RDF_TYPE
# ######################################################################################################################


root.HAS_RDF_TYPE = (x, rdfType) ->
    rdfTypeQName = rdfType.apply(undefined, [NAME_IDENTIFIER])
    for t in PATHS(x, TYPE)
        if rdfTypeQName.toCompactString() == t.toCompactString()
            return true
    return false


# ######################################################################################################################
# Parse the command line arguments
# ######################################################################################################################


# loop through the arguments and parse them:
# (we do it manually instead of depending on some third-party lib)
for arg, i in process.argv
    if arg is "-n" then root.MODEL_NO_WRITE = true
    else if arg is "-c" then root.MODEL_WRITE_COMPACT = true
    else if arg is "-f" then root.MODEL_WRITE_FORCE = true
    else if arg is "-a" then root.MODEL_WRITE_ALL = true
    else if arg is "-t" then root.MODEL_WRITE_TOPBRAID = true
    else if arg in ["-i", "-I", "-o"]
        # check if fs and path are loaded
        if not fs?   then ABORT "Flag #{arg} can only be given if module fs (filesystem) is available"
        if not path? then ABORT "Flag #{arg} can only be given if module path is available"
        # check if the argument after the flag is an existing path
        dir = process.argv[i+1]
        if not dir?               then ABORT "Argument #{arg} was provided, but no path was given afterwards!"
        if not fs.existsSync(dir) then ABORT "Argument '#{dir}' after the #{arg} flag is not an existing path!"
        # store the directories
        if arg is "-I"
            LOG "Adding path '#{dir}' to the READ_PATHS"
            root.READ_PATHS.push(dir)
        else if arg is "-i"
            LOG "Adding path '#{dir}' to the REQUIRE_PATHS"
            root.REQUIRE_PATHS.push(dir)
        else if arg is "-o"
            if root.MODEL_OUTPUT_PATH? and root.MODEL_OUTPUT_PATH isnt dir
                ABORT "Trying to add output path #{dir} while another output path (#{root.MODEL_OUTPUT_PATH}) " \
                      + "is already given"
            root.MODEL_OUTPUT_PATH = dir
    else if arg in ["-h", "--help"]
        console.log """
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
                    """

# if -i or -I flags were not specified, use the local directory ('.')
if root.REQUIRE_PATHS.length   is 0 then root.REQUIRE_PATHS.push(".")
if root.READ_PATHS.length is 0 then root.READ_PATHS.push(".")


LOG "--- ontoscript was successfully loaded ---"