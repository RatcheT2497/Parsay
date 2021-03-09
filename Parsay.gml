#macro PARSAY_DEBUG_ERROR_CHECKING true
#macro PARSAY_CHAR_LIST_BEGIN "<"
#macro PARSAY_CHAR_LIST_END ">"
#macro PARSAY_CHAR_STRING_1 "'"
#macro PARSAY_CHAR_STRING_2 "`"

function __psy_char_is_digit(c) { return (ord(c) >= ord("0") && ord(c) <= ord("9")) }
function __psy_char_is_whitespace(c) { return c == " " || c == "\t" || c == "\v" || c == "\f" || c == "\n" || c == "\r"; }
function __psy_token_is_real(token)
{
	var negative = false;
	var decimal = false;
	var afterdecimal = 0;
	for ( var i = 1; i <= string_length(token); i++ )
	{
		var c = string_char_at(token, i);
		if ( c == "-" )
		{
			if ( negative || i != 1 )
				return false;
			negative = true;
		} else if ( c == "." )
		{
			if (decimal)
				return false;
			decimal = true;
		} else if ( __psy_char_is_digit(c) )
		{
			if ( decimal )
				afterdecimal++;
		} else {
			return false;
		}
	}
	if ( decimal && (afterdecimal == 0) )
		return false;

	return true;
}
function __psy_ds_list_to_array(list)
{
	var size = ds_list_size(list);
	var tmp = array_create(size);
	for (var i = 0; i < size; i++)
		tmp[i] = list[| i];
	return tmp;
}
function __psy_error(type)
{
	var msg = "Parsay Error " + string(type) + "; ";
	for ( var i = 1; i < argument_count; i++ )
	{
		msg += string(argument[i]);
	}
	show_error(msg, true);
}

enum PARSAY_ERROR
{
	TOKEN_REPLACE_INVALID,
	TOKEN_MAP_INVALID,
	LIST_POSTPROCESSING_ERROR,
	TOKEN_NUMBER_INVALID,
	LIST_INVALID,
	UNHANDLED_TOKEN,
	UNEXPECTED_CHARACTER
}
function Parsay(write_name, write_func) constructor
{
	tokens = ds_map_create();
	tokens[? write_name] = write_func;
	
	__write_func = write_func;
	
	default_postprocess_list = function(list, level) { 
		if ( level == 0 )
		{
			if ( PARSAY_DEBUG_ERROR_CHECKING && array_length(list) == 0 )
				throw "Can not have zero-length list at top level.";	
			
			var token0_type = typeof(list[0]);
			if ( PARSAY_DEBUG_ERROR_CHECKING && token0_type != "function" && token0_type != "method" )
				throw "Expected function as the first token of top-level list, got '" + token0_type + "'.";
		}
		return list; 
	}; 
	
	user_postprocess_list = default_postprocess_list;
	user_evaluate_token = function(token) {};
	user_override_token = function(token) {};
	user_parse_token = function(str, index, buffer) {};
	
	/* INTERNAL FUNCTIONS */
	__evaluate_token = function(token)
	{
		// Override any and all token avaluations, even numbers
		var t = self.user_override_token(token);
		if ( !is_undefined(t) )
			return t;

		var c = string_char_at(token, 1);
		if ( __psy_char_is_digit(c) || c == "-" || c == "." && (token != "-") )
		{
			if ( __psy_token_is_real(token) )
				return real(token);

			__psy_error(PARSAY_ERROR.TOKEN_NUMBER_INVALID, "Invalid number token '", token, "'.");
		} else {
			// Custom token evaluation
			if ( ds_map_exists(self.tokens, token) )
			{
				return self.tokens[? token];
			} else
			{
				var t = self.user_evaluate_token(token);
				if ( !is_undefined(t) )
					return t;
			}
		}
		__psy_error(PARSAY_ERROR.UNHANDLED_TOKEN, "Unhandled token '", token, "'.");
	}
	__read_expression = function(str, length, index, level)
	{
		var i = index + 1; // Skip over beginning "<"
		var list = ds_list_create();
		var buffer = "";
		while ( i <= length )
		{
			var c = string_char_at(str, i);
			if ( __psy_char_is_whitespace(c) ) // Whitespace
			{
				// Flush token buffer if not empty
				if ( buffer != "" )
				{
					ds_list_add(list, self.__evaluate_token(buffer));
					buffer = "";
				}
				// Skip over whitespace
				i++;
			} else if ( c == PARSAY_CHAR_LIST_BEGIN ) { // Recursively parse list
				var expr = self.__read_expression(str, length, i, level + 1);
				var finished_list = expr.data;

				try {
					var res = self.user_postprocess_list(expr.data, level + 1);
					if ( !is_undefined(res) )
						finished_list = res;
				} catch (e)
				{
					__psy_error(PARSAY_ERROR.LIST_POSTPROCESSING_ERROR, "List postprocessing error: ", e);
				}

				// Have index end up on the character right after the closing bracket
				i = expr.end_index;
				
				c = string_char_at(str, i);
				if ( PARSAY_DEBUG_ERROR_CHECKING && !(__psy_char_is_whitespace(c) || (c == PARSAY_CHAR_LIST_END)) )
					__psy_error(PARSAY_ERROR.UNEXPECTED_CHARACTER, "Expected whitespace or another '", PARSAY_CHAR_LIST_BEGIN, "' after '", PARSAY_CHAR_LIST_END, "', found '", c, "' instead.");
				
				ds_list_add(list, finished_list);
			} else if ( c == PARSAY_CHAR_LIST_END) { // End list parsing, go up one level
				// Flush token buffer if not empty before returning the parsed list
				if ( buffer != "" )
				{
					ds_list_add(list, self.__evaluate_token(buffer));
					buffer = "";
				}

				// Convert the token list to an array and free the list's memory
				var arr = ds_list_to_array(list);
				ds_list_destroy(list);

				return {
					data: arr,
					end_index: i + 1
				};
			} else if ( (c == PARSAY_CHAR_STRING_1) || (c == PARSAY_CHAR_STRING_2) ) { // Parse string
				var begin_string_char = c;
				// Skip over beginning identifier
				i++;
				c = string_char_at(str, i);
				while ( c != begin_string_char )
				{
					// Add characters to buffer; if an '\' is encountered, 
					// unconditionally add the next character to the buffer (allowing for inline ' and \ characters)
					if ( c == "\\" )
					{
						c = string_char_at(str, ++i);
					}
					buffer += c;
					c = string_char_at(str, ++i);
				}
				
				// End parsing on space character
				c = string_char_at(str, ++i);
				if ( PARSAY_DEBUG_ERROR_CHECKING && !( __psy_char_is_whitespace(c) || (c == PARSAY_CHAR_LIST_END) ))
					__psy_error(PARSAY_ERROR.UNEXPECTED_CHARACTER, "Expected whitespace or '", PARSAY_CHAR_LIST_END, "' after end of string '", buffer, "', found '", c, "' instead.");

				// Add string to list and clear buffer
				ds_list_add(list, buffer);
				buffer = "";
			} else {
				// Add character to buffer
				buffer += c;
				i++;
				
				var t = self.user_parse_token(str, i, buffer);
				if ( !is_undefined(t) )
				{
					ds_list_add(list, t.data);
					i = t.new_index;
				}
			}
		}
		__psy_error(PARSAY_ERROR.UNEXPECTED_CHARACTER, "Could not find '", PARSAY_CHAR_LIST_END , "' to end list at level ", level, ".");
	}
	
	/* API */
	/// @description Registers a token 
	/// @param name Name of token
	/// @param value Value of token
	add_token = function(name, value)
	{
		if ( PARSAY_DEBUG_ERROR_CHECKING && ds_map_exists(self.tokens, name) )
			__psy_error(PARSAY_ERROR.TOKEN_REPLACE_INVALID, "Can't replace token '", name, "'.");
		self.tokens[? name] = value;
	}
	
	/// @description Registers tokens from a ds_map.
	/// @param map
	add_tokens_from_map = function(map)
	{
		if ( PARSAY_DEBUG_ERROR_CHECKING && !ds_exists(map, ds_type_map) )
			__psy_error(PARSAY_ERROR.TOKEN_MAP_INVALID, "Can't add tokens from non-existent map.");

		var key = ds_map_find_first(map);
		while ( !is_undefined(key) )
		{
			self.tokens[? key] = map[? key];
			key = ds_map_find_next(map, key);
		}
	}
	
	/// @description Parses string into an array of tokens, starting from argument specified value.
	/// @param string String to parse. Includes text interspersed with commands.
	/// @param index Where to begin parsing the string from.
	parse_string_index = function(str, index)
	{
		var i = index;
		var length = string_length(str);
		var buffer = "";
		var list = ds_list_create();
		while ( i <= length )
		{
			var c = string_char_at(str, i);
			if ( c == PARSAY_CHAR_LIST_BEGIN )
			{
				// Flush buffer when finding the start of a list
				if ( buffer != "" )
				{
					var tmp = [self.__write_func, buffer];
					try {
						var t = self.user_postprocess_list(tmp, 0);
						if ( !is_undefined(t) )
							tmp = t;
					} catch (e)
					{
						__psy_error(PARSAY_ERROR.LIST_POSTPROCESSING_ERROR, "List postprocessing error: ", e);
					}
					ds_list_add(list, tmp);
					buffer = "";
				}
				
				var cmd = self.__read_expression(str, length, i, 0);
				i = cmd.end_index;

				// List validation/postprocessing
				var finished_list = cmd.data;
				try {
					var t = self.user_postprocess_list(cmd.data, 0);
					if ( !is_undefined(t) )
						finished_list = t;
				} catch (e)
				{
					__psy_error(PARSAY_ERROR.LIST_POSTPROCESSING_ERROR, "List postprocessing error: ", e);
				}

				ds_list_add(list, finished_list);
			} else {
				if ( c == "\\" )
				{
					c = string_char_at(str, ++i);
				}

				buffer += c;
				i++;
			}
		}

		// Flush buffer when reaching the end of the string
		if ( buffer != "" )
		{
			var tmp = [self.__write_func, buffer];
			try {
				var t = self.user_postprocess_list(tmp, 0);
				if ( !is_undefined(t) )
					tmp = t;
			} catch (e)
			{
				__psy_error(PARSAY_ERROR.LIST_POSTPROCESSING_ERROR, "List postprocessing error: ", e);
			}
			ds_list_add(list, tmp);
			buffer = "";
		}
		
		var arr = __psy_ds_list_to_array(list);
		ds_list_destroy(list);
		return arr;
	}
	
	/// @description Parses string into an array of tokens, starting from the first character.
	/// @param string String to parse. Includes text interspersed with commands.
	parse_string = function(str)
	{
		return self.parse_string_index(str, 1);
	}
	
	/// @description Frees the internal token ds_map.
	free = function()
	{
		ds_map_destroy(tokens);
	}
}