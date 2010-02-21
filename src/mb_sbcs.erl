%% User-defined behaviour module
-module(mb_sbcs).
-export([init/1, decode/2, decode/3, encode/2, encode/3]).

-record(encode_profile, {
      encode_dict        :: dict(),            % encode mapping dict
      output             :: atom(),            % output format, binary or list
      error              :: atom(),            % error option
	  error_replace_char :: char()             % error replace char
     }).
-define(ENCODE_ERROR_REPLACE_CHAR, $?).        % default replace char

-record(decode_profile, {
      undefined_set      :: set(),             % undefined char set
      decode_dict        :: dict(),            % decode mapping dict
      error              :: atom(),            % error option
	  error_replace_char :: non_neg_integer()  % error replace char
     }).
-define(DECODE_ERROR_REPLACE_CHAR, 16#FFFD).   % default replace char

init(Mod) ->
	{MB_MODULE, PROCESS_DICT_ATOM, CONF_NAME, BIN_NAME} = Mod:codecs_config(), 
    Path = code:priv_dir(MB_MODULE),
    Txtname = filename:join(Path, CONF_NAME),
    Binname = filename:join(Path, BIN_NAME),
    case filelib:is_file(Binname) of
        true ->
            {ok, Binary} = file:read_file(Binname),
            erlang:put(PROCESS_DICT_ATOM, binary_to_term(Binary)),
            ok;
        false ->
            {ok, [PropList]} = file:consult(Txtname),
			DecodeUndefinedSet = sets:from_list(proplists:get_value(undefined,PropList)),
            DecodeList = proplists:get_value(mapping, PropList),
            DecodeDict = dict:from_list(DecodeList),
            EncodeDict = dict:from_list([{Value, Key} || {Key, Value} <- DecodeList]),
            ok = file:write_file(Binname, term_to_binary({{DecodeUndefinedSet, DecodeDict}, {EncodeDict}})),
            init(Mod)
    end.

process_encode_options(Options) when is_list(Options) ->
	OptionDefeault = [{output, binary}, {error, strict}, {error_replace_char, ?ENCODE_ERROR_REPLACE_CHAR}],
	process_encode_options1(Options, dict:from_list(OptionDefeault)).
	
process_encode_options1([], OptionDict) ->
	{ok, OptionDict};
process_encode_options1([Option | OptionsTail], OptionDict) ->
	case Option of
		binary ->
			process_encode_options1(OptionsTail, dict:store(output, binary, OptionDict));
		list ->   
			process_encode_options1(OptionsTail, dict:store(output, list, OptionDict));
		ignore -> 
			process_encode_options1(OptionsTail, dict:store(error, ignore, OptionDict));
		strict -> 
			process_encode_options1(OptionsTail, dict:store(error, strict, OptionDict));
		replace -> 
			process_encode_options1(OptionsTail, dict:store(error, replace, OptionDict));
		{replace, Char} when is_integer(Char) -> 
			process_encode_options1(OptionsTail, dict:store(error_replace_char, Char, dict:store(error, replace, OptionDict)));
		UnknownOption ->
			{error, {cannot_encode, [{reason, unknown_option}, {option, UnknownOption}]}}
	end.
 
encode(Mod, Unicode) when is_atom(Mod), is_list(Unicode) ->
    encode(Mod, Unicode, [strict]).

encode(Mod, Unicode, Options) when is_atom(Mod), is_list(Unicode), is_list(Options) ->
	{_MB_MODULE, PROCESS_DICT_ATOM, _CONF_NAME, _BIN_NAME} = Mod:codecs_config(), 
	case process_encode_options(Options) of
		{ok, OptionDict} ->
			case erlang:get(PROCESS_DICT_ATOM) of
				{_, {EncodeDict}} ->
					EncodeProfile = #encode_profile{encode_dict        = EncodeDict,
													output             = dict:fetch(output, OptionDict),
													error              = dict:fetch(error, OptionDict),
													error_replace_char = dict:fetch(error_replace_char, OptionDict)},
					encode1(Unicode, EncodeProfile, 1, []);
				_OtherDict ->
					{error, {cannot_encode, [{reson, illegal_process_dict}, {process_dict, PROCESS_DICT_ATOM}, {detail, "maybe you should call mb:init() first"}]}}
			end;
		{error, Reason} ->
			{error, Reason}
	end.    

encode1([], EncodeProfile, _, String) when is_record(EncodeProfile, encode_profile), is_list(String) ->
    OutputString = lists:reverse(String),
    case EncodeProfile#encode_profile.output of
        list   -> OutputString;
        binary -> erlang:list_to_binary(OutputString)
    end;
encode1([Code | RestCodes], #encode_profile{encode_dict=EncodeDict,error=Error, error_replace_char=ErrorReplaceChar}=EncodeProfile, Pos, String) when is_integer(Pos), is_list(String) ->
    case catch dict:fetch(Code, EncodeDict) of
        {'EXIT',{badarg, _}} ->
            case Error of
                ignore ->
                    encode1(RestCodes, EncodeProfile, Pos+1, String);
                replace ->
                    encode1(RestCodes, EncodeProfile, Pos+1, [ErrorReplaceChar | String]);
                strict ->
                    {error, {cannot_encode, [{reason, unmapping_unicode}, {unicode, Code}, {pos, Pos}]}}
            end;
        MultibyteChar ->
            case MultibyteChar > 16#FF of
                false ->
                    encode1(RestCodes, EncodeProfile, Pos+1, [MultibyteChar | String]);
                true ->
                    encode1(RestCodes, EncodeProfile, Pos+1, [MultibyteChar band 16#FF, MultibyteChar bsr 8 | String])
            end
    end.
	
process_decode_options(Options) when is_list(Options) ->
	OptionDefeault = [{error, strict}, {error_replace_char, ?DECODE_ERROR_REPLACE_CHAR}],
	process_decode_options1(Options, dict:from_list(OptionDefeault)).

process_decode_options1([], OptionDict) ->
	{ok, OptionDict};
process_decode_options1([Option | OptionsTail], OptionDict) ->
	case Option of
		strict ->
			process_decode_options1(OptionsTail, dict:store(error, strict, OptionDict));
		ignore -> 
			process_decode_options1(OptionsTail, dict:store(error, ignore, OptionDict));
		replace -> 
			process_decode_options1(OptionsTail, dict:store(error, replace, OptionDict));
		{replace, Char} when is_integer(Char) -> 
			process_decode_options1(OptionsTail, dict:store(error_replace_char, Char, dict:store(error, replace, OptionDict)));
		UnknownOption ->
			{error, {cannot_decode, [{reason, unknown_option}, {option, UnknownOption}]}}	
	end.

decode(Mod, Binary) when is_atom(Mod), is_binary(Binary) ->
    decode(Mod, Binary, [strict]).

decode(Mod, Binary, Options) when is_atom(Mod), is_binary(Binary), is_list(Options) ->
	{_MB_MODULE, PROCESS_DICT_ATOM, _CONF_NAME, _BIN_NAME} = Mod:codecs_config(), 
	case process_decode_options(Options) of
		{ok, OptionDict} ->
			case erlang:get(PROCESS_DICT_ATOM) of
				{{DecodeUndefinedSet, DecodeDict}, _} ->
					DecodeProfile = #decode_profile{undefined_set      = DecodeUndefinedSet, 
													decode_dict        = DecodeDict, 
													error              = dict:fetch(error, OptionDict),
													error_replace_char = dict:fetch(error_replace_char, OptionDict)},
					decode1(Binary, DecodeProfile, 1, []);
				_OtherDict ->
					{error, {cannot_decode, [{reson, illegal_process_dict}, {process_dict, PROCESS_DICT_ATOM}, {detail, "maybe you should call mb:init() first"}]}}
			end;
		{error, Reason} ->
			{error, Reason}
	end.

decode1(<<>>, _, _, Unicode) when is_list(Unicode) ->
    lists:reverse(Unicode);
decode1(<<Byte:8, Rest/binary>>, #decode_profile{undefined_set=UndefinedSet, decode_dict=DecodeDict, error=Error, error_replace_char=ErrorReplaceChar}=DecodeProfile, Pos, Unicode) when is_integer(Pos), is_list(Unicode) ->
    case sets:is_element(Byte, UndefinedSet) of
        true ->
            case Error of
                ignore ->
                    decode1(Rest, DecodeProfile, Pos+1, Unicode);
                replace ->
                    decode1(Rest, DecodeProfile, Pos+1, [ErrorReplaceChar | Unicode]);
                strict ->
                    {error, {cannot_decode, [{reason, undefined_character}, {character, Byte}, {pos, Pos}]}}
            end;
        false ->	
			case catch dict:fetch(Byte, DecodeDict) of
				{'EXIT',{badarg, _}} ->
					case Error of
						ignore ->
							decode1(Rest, DecodeProfile, Pos+1, Unicode);
						replace ->
							decode1(Rest, DecodeProfile, Pos+1, [ErrorReplaceChar | Unicode]);
						strict ->
							{error, {cannot_encode, [{reason, unmapping_character}, {character, Byte}, {pos, Pos}]}}
					end;
				Char ->
					decode1(Rest, DecodeProfile, Pos+1, [Char | Unicode])
			end
	end.