

# Parsley

A single-file, extensible text command parser for GameMaker Studio 2.

A parsable string of text is a series of commands, or lists, interspersed with regular text.

By default, commands take the form of `<COMMAND arg1 arg2 arg3...>` and are parsed into standard GML arrays of values.

Regular text gets identified and replaced with a command specified during Parsley object creation with a single argument, that being the text.

Supported argument data types are:

- Decimal numbers (both positive, negative and with or without the decimal point).
- Strings - starting and ending either with `'` or ` 
- Lists - starting with `<` and ending with `>` - can be nested.

The characters that define strings and lists are set in macros at the very top of the file. Specifically, `PARSLEY_CHAR_STRING_1` and `PARSLEY_CHAR_STRING_2` define strings, while `PARSLEY_CHAR_LIST_BEGIN` and `PARSLEY_CHAR_LIST_END` define lists.

It supports user-definable tokens, which can hold any value. Anything that doesn't match the previous rules gets identified as a token and (usually) replaced.

As for the 'extensibility', in addition to these tokens, you can define a subclass of the Parsley object and override the following functions:

-  `function user_postprocess_list(list, level) : list( throw for error )` - This function gets called after each list is handled. Can be used for verification or additional formatting. The default list postprocessor checks if a top level list isn't empty and if its first value is a function. After that it returns the original list. This function is also stored in `default_postprocess_list`, so if you wish to build on that verification step you're able to reuse it.
- `function user_evaluate_token(token) : any` - happens after token evaluation, only works on already-identified tokens and those which aren't defined in the token map.
- `function user_override_token(token) : any/undefined` - happens before token evaluation and before the above rule matching. If it returns undefined, token evaluation takes place as normal. Otherwise, token evaluation is skipped in favour of using this function's return value.
- `function user_parse_token(str, index, buffer) : { data: any, new_index: real }/undefined` - This only gets called if a token doesn't fit the rules for a number or a string.

## Usage

1. Create a Parsley object
2. Add tokens and optionally implement the above custom functions using standard variable syntax
3. Call `object.parse_string(string)` or `object.parse_string_index(string, index)`, expecting an array of commands.
4. Call `object.free()` and destroy it using the `delete` operator
5. Interpret the parsed commands however you like

NOTE: This object is designed to only run once, preferably at start-up. String operations are very costly, and this library uses those heavily. If you parse strings every frame, expect slowdown to happen.

I will add more documentation (and some examples) later.