#macro PARSLEY_DEBUG_ERROR_CHECKING true
#macro PARSLEY_CHAR_LIST_BEGIN "<"
#macro PARSLEY_CHAR_LIST_END ">"
#macro PARSLEY_CHAR_STRING_1 "'"
#macro PARSLEY_CHAR_STRING_2 "`"

function __psl_char_is_digit(c) { return (ord(c) >= ord("0") && ord(c) <= ord("9")) }
function __psl_char_is_space(c) { return c == " " || c == "\t" || c == "\v" || c == "\f" || c == "\n" || c == "\r"; }
function __psl_ds_list_to_array(list)
{
	var size = ds_list_size(list);
	var tmp = array_create(size);
	for (var i = 0; i < size; i++)
		tmp[i] = list[| i];
	return tmp;
}
function __psl_error(type)
{
	var msg = "Parsley Error " + string(type) + "; ";
	for ( var i = 1; i < argument_count; i++ )
	{
		msg += string(argument[i]);
	}
	show_error(msg, true);
}
function __psl_token_is_real(token)
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
		} else if ( __psl_char_is_digit(c) )
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
function Parsley(write_name, write_func) constructor
{
	tokens = ds_map_create();
	tokens[? write_name] = write_func;
	self.__write_func = write_func;
	
	self.custom_validate_list = undefined; // function custom_validate_list(list, level) : undefined ( throw for error )
	self.custom_evaluate_token = undefined;  // function custom_evaluate_token(token) : any
	self.custom_override_token = undefined; // function custom_override_token(token) : any/undefined
	self.custom_parse_token = undefined; // function custom_parse_token(str, index, start_character) : { data: any, new_index: real }
	/* INTERNAL FUNCTIONS */
	__evaluate_token = function(token)
	{
		if ( !is_undefined(self.custom_override_token) )
		{
			var ceto_type = typeof(self.custom_override_token);
			if ( PARSLEY_DEBUG_ERROR_CHECKING && ceto_type != "function" && ceto_type != "method" )
				__psl_error(0, "Expected a function in 'evaluate_token_override', got ", ceto_type);
			// Override any and all token avaluations, even numbers
			var t = self.custom_override_token(token);
			if ( !is_undefined(t) )
				return t;
		}
		var c = string_char_at(token, 1);
		if ( __psl_char_is_digit(c) || c == "-" || c == "." )
		{
			if ( string_length(token) == 1 ) // hack for single "-" token to work
				return token;

			if ( __psl_token_is_real(token) )
				return real(token);

			__psl_error(1, "Invalid number token '", token, "'.");
		} else {
			// Custom token evaluation
			if ( ds_map_exists(self.tokens, token) )
			{
				return self.tokens[? token];
			} else if ( !is_undefined(self.custom_evaluate_token) )
			{
				var cet_type = typeof(self.custom_evaluate_token);
				if ( PARSLEY_DEBUG_ERROR_CHECKING && cet_type != "function" && cet_type != "method" )
					__psl_error(2, "Expected a function in 'evaluate_token', got '", cet_type, "'");

				var t = self.custom_evaluate_token(token);
				if ( !is_undefined(t) )
					return t;
			}
		}
		__psl_error(3, "Unhandled token '", token, "'.");
	}
	__read_expression = function(str, length, index, level)
	{
		var i = index + 1; // Skip over beginning "<"
		var list = ds_list_create();
		var buffer = "";
		while ( i <= length )
		{
			var c = string_char_at(str, i);
			if ( __psl_char_is_space(c) ) // Whitespace
			{
				// Flush token buffer if not empty
				if ( buffer != "" )
				{
					ds_list_add(list, self.__evaluate_token(buffer));
					buffer = "";
				}
				// Skip over whitespace
				i++;
			} else if ( c == PARSLEY_CHAR_LIST_BEGIN ) { // Recursively parse list
				var expr = self.__read_expression(str, length, i, level + 1);
				if ( !is_undefined(self.custom_validate_list) )
				{
					var clv_type = typeof(self.custom_validate_list);
					if ( PARSLEY_DEBUG_ERROR_CHECKING && clv_type != "function" && clv_type != "method" )
						__psl_error(-1, "Expected a function in 'custom_validate_list', got '", clv_type, "'.");
					
					try {
						self.custom_validate_list(expr.data, level + 1);
					} catch (e)
					{
						__psl_error(-1, "Invalid list: ", e);
					}
						
				} 
				// Have index end up on the character right after the closing bracket
				i = expr.end_index;
				
				c = string_char_at(str, i);
				if ( PARSLEY_DEBUG_ERROR_CHECKING && !(__psl_char_is_space(c) || (c == PARSLEY_CHAR_LIST_END)) )
					__psl_error(4, "Expected whitespace or another '", PARSLEY_CHAR_LIST_BEGIN, "' after '", PARSLEY_CHAR_LIST_END, "', found '", c, "' instead.");
				
				ds_list_add(list, expr.data);
			} else if ( c == PARSLEY_CHAR_LIST_END) { // End list parsing, go up one level
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
			} else if ( (c == PARSLEY_CHAR_STRING_1) || (c == PARSLEY_CHAR_STRING_2) ) { // Parse string
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
				if ( PARSLEY_DEBUG_ERROR_CHECKING && !( __psl_char_is_space(c) || (c == PARSLEY_CHAR_LIST_END) ))
					__psl_error(5, "Expected whitespace or '", PARSLEY_CHAR_LIST_END, "' after end of string '", buffer, "', found '", c, "' instead.");

				// Add string to list and clear buffer
				ds_list_add(list, buffer);
				buffer = "";
			} else {
				if ( !is_undefined(self.custom_parse_token) )
				{
					var t = self.custom_parse_token(str, i, c);
					if ( !is_undefined(t) )
					{
						ds_list_add(list, t.data);
						i = t.new_index;
						continue;
					}
				}

				// Add character to buffer
				buffer += c;
				i++;
			}
		}
		__psl_error(6, "Could not find '", PARSLEY_CHAR_LIST_END , "' to end list at level ", level, ".");
	}
	
	/* API */
	/// @description Registers a token 
	/// @param name Name of token
	/// @param value Value of token
	add_token = function(name, value)
	{
		if ( PARSLEY_DEBUG_ERROR_CHECKING && ds_map_exists(self.tokens, name) )
			__psl_error(7, "Can not replace token '", name, "'.");
		self.tokens[? name] = value;
	}
	
	/// @description Registers tokens from a ds_map.
	/// @param map
	add_tokens_from_map = function(map)
	{
		if ( PARSLEY_DEBUG_ERROR_CHECKING && !ds_exists(map, ds_type_map) )
			__psl_error(8, "Can not add tokens from non-existent map.");

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
			if ( c == PARSLEY_CHAR_LIST_BEGIN )
			{
				// Flush buffer when finding the start of a list
				if ( buffer != "" )
				{
					ds_list_add(list, [self.__write_func, buffer]);
					buffer = "";
				}
				
				var cmd = self.__read_expression(str, length, i, 0);
				i = cmd.end_index;
				if ( PARSLEY_DEBUG_ERROR_CHECKING && array_length(cmd.data) == 0 )
				{
					__psl_error(9, "Empty top-level list is invalid.");
				}
				if ( !is_undefined(self.custom_validate_list) )
				{
					try {
						self.custom_validate_list(cmd.data, 0);
					} catch (e)
					{
						__psl_error(-1, "Invalid list: ", e);
					}
				} else {
					var token0_type = typeof(cmd.data[0]);
					if ( PARSLEY_DEBUG_ERROR_CHECKING && token0_type != "function" && token0_type != "method" )
					{
						__psl_error(10, "Expected function as the first token of top-level list, got '", token0_type, "'.");
					}
				}
				ds_list_add(list, cmd.data);
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
			ds_list_add(list, [self.__write_func, buffer]);
			buffer = "";
		}
		
		var arr = __psl_ds_list_to_array(list);
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