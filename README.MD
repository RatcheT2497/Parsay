

# Parsley

A single-file, extensible text command parser for GameMaker Studio 2.

A parsable string of text is a series of commands, interspersed with regular text.



By default, commands take the form of `<COMMAND arg1 arg2 arg3...>` and are parsed into standard GML arrays of values.

Regular text gets identified and replaced with a command specified during Parsley object creation, with a single argument, that being the text.



Supported argument data types are:

- Decimal numbers (both positive, negative and with or without the decimal point).
- Strings - starting and ending either with `'` or `.
- Lists - starting with `<` and ending with `>` - can be nested.

It supports user-definable tokens, which can hold any value. Anything that doesn't match the previous rules gets identified as a token and (usually) replaced.

As for the 'extensibility', in addition to these tokens, you can define four functions in the Parsley object:

-  `function custom_validate_list(list, level) : undefined ( throw for error )` - A replacement for the fairly basic built-in validation. By default the parser will check if the top level list's first token is a function, and throws an error. This function gets called after every single list gets parsed, instead of just the top-level one.
- `function custom_evaluate_token(token) : any` - happens after token evaluation, only works on already-identified tokens and those which aren't defined in the token map.
- `function custom_override_token(token) : any/undefined` - happens before token evaluation and before the above rule matching. If it returns undefined, token evaluation takes place as normal. Otherwise, token evaluation is skipped in favour of using this function's return value.
- `function custom_parse_token(str, index, start_character) : { data: any, new_index: real }`

## Usage

1. Create a Parsley object
2. Add tokens and optionally implement the above custom functions using standard variable syntax
3. Call `object.parse_string(string)` or `object.parse_string_index(string, index)`, expecting an array of commands.
4. Call `object.free()` and destroy it using the `delete` operator
5. Interpret the parsed commands however you like

NOTE: This object is designed to only run once, preferably at start-up. String operations are very costly, and this library uses those heavily. If you parse strings every frame, expect slowdown to happen.

I will add more documentation (and some examples) later.