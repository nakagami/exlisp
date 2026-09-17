defmodule ExLisp.LispParser do
  @moduledoc """
  Custom S-expression parser for ExLisp.
  Performs lexical analysis and parsing (S-expression generation) of Lisp
  without external dependencies or regular expressions.
  """

  @doc """
  Parses a Lisp code string and returns an AST.
  Returns `{:ok, ast}` on success, or `{:error, reason}` on failure.
  """
  def parse(input) when is_binary(input) do
    trimmed = String.trim(input)

    if trimmed == "" do
      {:ok, {:lit, nil}}
    else
      case tokenize(trimmed) do
        {:ok, []} ->
          {:ok, {:lit, nil}}

        {:ok, tokens} ->
          parse_tokens(tokens)

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc """
  Parses a Lisp code string and returns an AST. Raises an exception on failure.
  """
  def parse!(input) when is_binary(input) do
    case parse(input) do
      {:ok, ast} ->
        ast

      {:error, reason} ->
        raise SyntaxError, description: reason, file: "nofile", line: 1
    end
  end

  @doc """
  Parses a Lisp code string containing multiple expressions and returns an AST list.
  Returns `{:ok, [ast, ...]}` on success, or `{:error, reason}` on failure.
  """
  def parse_multiple(input) when is_binary(input) do
    trimmed = String.trim(input)

    if trimmed == "" do
      {:ok, []}
    else
      case tokenize(trimmed) do
        {:ok, []} ->
          {:ok, []}

        {:ok, tokens} ->
          parse_all_top_level(tokens, [])

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc """
  Parses a Lisp code string containing multiple expressions and returns an AST list. Raises an exception on failure.
  """
  def parse_multiple!(input) when is_binary(input) do
    case parse_multiple(input) do
      {:ok, asts} ->
        asts

      {:error, reason} ->
        raise SyntaxError, description: reason, file: "nofile", line: 1
    end
  end

  # =========================================================================
  # Lexical Analysis (Tokenizer)
  # =========================================================================

  @doc """
  Tokenizes a Lisp code string into a token list.
  """
  def tokenize(input) when is_binary(input) do
    tokenize_chars(String.to_charlist(input), 1, [])
  end

  defp tokenize_chars([], _line, acc) do
    {:ok, Enum.reverse(acc)}
  end

  # Newline
  defp tokenize_chars([?\n | rest], line, acc) do
    tokenize_chars(rest, line + 1, acc)
  end

  # Whitespace characters
  defp tokenize_chars([c | rest], line, acc) when c in [?\s, ?\t, ?\r] do
    tokenize_chars(rest, line, acc)
  end

  # Comment (skip from ; to end of line)
  defp tokenize_chars([?; | rest], line, acc) do
    skip_comment(rest, line, acc)
  end

  # String literal
  defp tokenize_chars([?\" | rest], line, acc) do
    read_string(rest, line, [], acc)
  end

  # Block comment (#| ... |# with nesting support)
  defp tokenize_chars([?#, ?| | rest], line, acc) do
    skip_block_comment(rest, line, 1, acc)
  end

  # Vector (#(...) -> {:vec_lparen, line})
  defp tokenize_chars([?#, ?( | rest], line, acc) do
    tokenize_chars(rest, line, [{:vec_lparen, line} | acc])
  end

  # Read-time eval (#.form)
  defp tokenize_chars([?#, ?. | rest], line, acc) do
    tokenize_chars(rest, line, [{:read_eval, line} | acc])
  end

  # Pathname literal (#P"..." / #p"...")
  defp tokenize_chars([?#, p, ?\" | rest], line, acc) when p in [?p, ?P] do
    read_string(rest, line, [], acc)
  end

  # Complex number literal (#c(...) / #C(...))
  defp tokenize_chars([?#, c, ?( | rest], line, acc) when c in [?c, ?C] do
    tokenize_chars(rest, line, [{:complex_lparen, line} | acc])
  end

  # Bit vector literal (#*0101...)
  defp tokenize_chars([?#, ?* | rest], line, acc) do
    {bit_chars, rem} = read_token_chars(rest, [])
    bit_str = List.to_string(bit_chars)

    bits =
      if bit_str == "" do
        []
      else
        String.graphemes(bit_str)
        |> Enum.map(fn
          "1" -> 1
          _ -> 0
        end)
      end

    tokenize_chars(rem, line, [{:bit_vector, line, bits} | acc])
  end

  # Reader conditionals (#+ / #-)
  defp tokenize_chars([?#, ?+ | rest], line, acc) do
    tokenize_chars(rest, line, [{:feature_plus, line} | acc])
  end

  defp tokenize_chars([?#, ?- | rest], line, acc) do
    tokenize_chars(rest, line, [{:feature_minus, line} | acc])
  end

  # Uninterned symbols (#:name, #|...|)
  defp tokenize_chars([?#, ?:, ?| | rest], line, acc) do
    {sym_str, rem} = read_pipe_symbol_chars(rest, [])
    uninterned = :"#:UNINTERNED_#{System.unique_integer([:positive, :monotonic])}_|#{sym_str}|"
    tokenize_chars(rem, line, [{:symbol, line, uninterned} | acc])
  end

  defp tokenize_chars([?#, ?: | rest], line, acc) do
    {tok_chars, rem} = read_token_chars(rest, [])
    tok_str = List.to_string(tok_chars)
    normalized = normalize_symbol_name(tok_str)
    uninterned = :"#:UNINTERNED_#{System.unique_integer([:positive, :monotonic])}_#{normalized}"
    tokenize_chars(rem, line, [{:symbol, line, uninterned} | acc])
  end

  # Keyword pipe-escaped symbol (:|...|)
  defp tokenize_chars([?:, ?| | rest], line, acc) do
    {sym_str, rem} = read_pipe_symbol_chars(rest, [])
    atom = String.to_atom(":|#{sym_str}|")
    ExLisp.Env.register_keyword(atom)
    tokenize_chars(rem, line, [{:keyword, line, atom} | acc])
  end

  # Pipe-escaped symbol (|...|)
  defp tokenize_chars([?| | rest], line, acc) do
    {sym_str, rem} = read_pipe_symbol_chars(rest, [])
    sym_atom = String.to_atom("|#{sym_str}|")
    tokenize_chars(rem, line, [{:symbol, line, sym_atom} | acc])
  end

  # Function quote (#'form)
  defp tokenize_chars([?#, ?' | rest], line, acc) do
    tokenize_chars(rest, line, [{:func_quote, line} | acc])
  end

  # Character literal (#\...)
  defp tokenize_chars([?#, ?\\ | rest], line, acc) do
    read_char_literal(rest, line, acc)
  end

  # Radix notation (#b, #o, #x)
  defp tokenize_chars([?#, b | rest], line, acc) when b in [?b, ?B, ?o, ?O, ?x, ?X] do
    read_radix_number(rest, b, line, acc, 1)
  end

  # Signed radix notation (+#b, -#b, etc.)
  defp tokenize_chars([?+, ?#, b | rest], line, acc) when b in [?b, ?B, ?o, ?O, ?x, ?X] do
    read_radix_number(rest, b, line, acc, 1)
  end

  defp tokenize_chars([?-, ?#, b | rest], line, acc) when b in [?b, ?B, ?o, ?O, ?x, ?X] do
    read_radix_number(rest, b, line, acc, -1)
  end

  # Quote ('form)
  defp tokenize_chars([?' | rest], line, acc) do
    tokenize_chars(rest, line, [{:quote, line} | acc])
  end

  # Backquote (`form)
  defp tokenize_chars([?` | rest], line, acc) do
    tokenize_chars(rest, line, [{:backquote, line} | acc])
  end

  # Comma-at (,@form)
  defp tokenize_chars([?,, ?@ | rest], line, acc) do
    tokenize_chars(rest, line, [{:comma_at, line} | acc])
  end

  # Comma-dot (,.form)
  defp tokenize_chars([?,, ?. | rest], line, acc) do
    tokenize_chars(rest, line, [{:comma_at, line} | acc])
  end

  # Comma (,form)
  defp tokenize_chars([?, | rest], line, acc) do
    tokenize_chars(rest, line, [{:comma, line} | acc])
  end

  # Parentheses and brackets
  defp tokenize_chars([?( | rest], line, acc) do
    tokenize_chars(rest, line, [{:lparen, line} | acc])
  end

  defp tokenize_chars([?) | rest], line, acc) do
    tokenize_chars(rest, line, [{:rparen, line} | acc])
  end

  defp tokenize_chars([?[ | rest], line, acc) do
    tokenize_chars(rest, line, [{:lbracket, line} | acc])
  end

  defp tokenize_chars([?] | rest], line, acc) do
    tokenize_chars(rest, line, [{:rbracket, line} | acc])
  end

  defp tokenize_chars([?{ | rest], line, acc) do
    tokenize_chars(rest, line, [{:lbrace, line} | acc])
  end

  defp tokenize_chars([?} | rest], line, acc) do
    tokenize_chars(rest, line, [{:rbrace, line} | acc])
  end

  # Other tokens (numbers, symbols, identifiers, atoms)
  defp tokenize_chars(chars, line, acc) do
    {tok_chars, rest} = read_token_chars(chars, [])
    tok_str = List.to_string(tok_chars)
    token = parse_token_string(tok_str, line)
    tokenize_chars(rest, line, [token | acc])
  end

  # Skip comment
  defp skip_comment([], _line, acc) do
    {:ok, Enum.reverse(acc)}
  end

  defp skip_comment([?\n | rest], line, acc) do
    tokenize_chars(rest, line + 1, acc)
  end

  defp skip_comment([_ | rest], line, acc) do
    skip_comment(rest, line, acc)
  end

  # Skip block comment (#| ... |# with nesting support)
  defp skip_block_comment([], line, _depth, _acc) do
    {:error, "unclosed block comment #| starting before line #{line}"}
  end

  defp skip_block_comment([?#, ?| | rest], line, depth, acc) do
    skip_block_comment(rest, line, depth + 1, acc)
  end

  defp skip_block_comment([?|, ?# | rest], line, 1, acc) do
    tokenize_chars(rest, line, acc)
  end

  defp skip_block_comment([?|, ?# | rest], line, depth, acc) when depth > 1 do
    skip_block_comment(rest, line, depth - 1, acc)
  end

  defp skip_block_comment([?\n | rest], line, depth, acc) do
    skip_block_comment(rest, line + 1, depth, acc)
  end

  defp skip_block_comment([_ | rest], line, depth, acc) do
    skip_block_comment(rest, line, depth, acc)
  end

  # Read string
  defp read_string([], line, _curr, _acc) do
    {:error, "unclosed string literal at line #{line}"}
  end

  defp read_string([?\\, ?\" | rest], line, curr, acc) do
    read_string(rest, line, [?\" | curr], acc)
  end

  defp read_string([?\\, ?\\ | rest], line, curr, acc) do
    read_string(rest, line, [?\\ | curr], acc)
  end

  defp read_string([?\\, ?n | rest], line, curr, acc) do
    read_string(rest, line, [?\n | curr], acc)
  end

  defp read_string([?\\, ?t | rest], line, curr, acc) do
    read_string(rest, line, [?\t | curr], acc)
  end

  defp read_string([?\\, ?r | rest], line, curr, acc) do
    read_string(rest, line, [?\r | curr], acc)
  end

  defp read_string([?\\, c | rest], line, curr, acc) do
    read_string(rest, line, [c | curr], acc)
  end

  defp read_string([?\" | rest], line, curr, acc) do
    str_val = curr |> Enum.reverse() |> List.to_string()
    tokenize_chars(rest, line, [{:string, line, str_val} | acc])
  end

  defp read_string([?\n | rest], line, curr, acc) do
    read_string(rest, line + 1, [?\n | curr], acc)
  end

  defp read_string([c | rest], line, curr, acc) do
    read_string(rest, line, [c | curr], acc)
  end

  # Read character literal (#\...)
  defp read_char_literal([], line, _acc) do
    {:error, "unexpected EOF after #\\ at line #{line}"}
  end

  defp read_char_literal([c | rest], line, acc)
       when c in [?(, ?), ?[, ?], ?{, ?}, ?\", ?;, ?\s, ?\t, ?\n, ?\r, ?', ?`, ?,] do
    tokenize_chars(rest, line, [{:char, line, c} | acc])
  end

  defp read_char_literal(chars, line, acc) do
    {name_chars, rest} = read_token_chars(chars, [])
    name = List.to_string(name_chars)

    case String.downcase(name) do
      "newline" ->
        tokenize_chars(rest, line, [{:char, line, ?\n} | acc])

      "space" ->
        tokenize_chars(rest, line, [{:char, line, ?\s} | acc])

      "tab" ->
        tokenize_chars(rest, line, [{:char, line, ?\t} | acc])

      "page" ->
        tokenize_chars(rest, line, [{:char, line, 12} | acc])

      "rubout" ->
        tokenize_chars(rest, line, [{:char, line, 127} | acc])

      "return" ->
        tokenize_chars(rest, line, [{:char, line, ?\r} | acc])

      "linefeed" ->
        tokenize_chars(rest, line, [{:char, line, ?\n} | acc])

      "backspace" ->
        tokenize_chars(rest, line, [{:char, line, 8} | acc])

      _ ->
        if String.length(name) == 1 do
          <<c::utf8>> = name
          tokenize_chars(rest, line, [{:char, line, c} | acc])
        else
          {:error, "unknown character literal #\\#{name} at line #{line}"}
        end
    end
  end

  # Read radix number (#b, #o, #x)
  defp read_radix_number(chars, radix_char, line, acc, sign) do
    radix =
      case radix_char do
        b when b in [?b, ?B] -> 2
        o when o in [?o, ?O] -> 8
        x when x in [?x, ?X] -> 16
      end

    {digits_chars, rest} = read_token_chars(chars, [])
    digits = List.to_string(digits_chars)

    case Integer.parse(digits, radix) do
      {val, ""} ->
        tokenize_chars(rest, line, [{:int, line, val * sign} | acc])

      _ ->
        {:error, "invalid radix integer ##{<<radix_char>>}#{digits} at line #{line}"}
    end
  end

  defp read_token_chars([], acc), do: {Enum.reverse(acc), []}

  defp read_token_chars([c | _] = chars, acc)
       when c in [?\s, ?\t, ?\n, ?\r, ?(, ?), ?[, ?], ?{, ?}, ?\", ?;, ?`, ?,] do
    {Enum.reverse(acc), chars}
  end

  defp read_token_chars([c | rest], acc), do: read_token_chars(rest, [c | acc])

  defp read_pipe_symbol_chars([], acc), do: {acc |> Enum.reverse() |> List.to_string(), []}
  defp read_pipe_symbol_chars([?\\, c | rest], acc), do: read_pipe_symbol_chars(rest, [c | acc])

  defp read_pipe_symbol_chars([?| | rest], acc),
    do: {acc |> Enum.reverse() |> List.to_string(), rest}

  defp read_pipe_symbol_chars([c | rest], acc), do: read_pipe_symbol_chars(rest, [c | acc])

  # Parse token string (number, keyword, identifier, symbol)
  defp parse_token_string(str, line) do
    case parse_number(str, line) do
      {:ok, num_tok} ->
        num_tok

      :not_number ->
        parse_symbol_or_keyword(str, line)
    end
  end

  # Parse number
  defp parse_number(str, line) do
    # Standalone punctuation is not a number
    if str in ["+", "-", ".", "..", "..."] do
      :not_number
    else
      case parse_ratio(str, line) do
        {:ok, ratio_tok} ->
          {:ok, ratio_tok}

        :not_ratio ->
          norm_str =
            Regex.replace(
              ~r/^([+-]?(?:[0-9]+\.[0-9]*|\.[0-9]+|[0-9]+))[dDsSfFlL]([+-]?[0-9]+)$/,
              str,
              "\\1e\\2"
            )

          case Integer.parse(str) do
            {int_val, ""} ->
              {:ok, {:int, line, int_val}}

            _ ->
              case Float.parse(norm_str) do
                {float_val, ""} ->
                  {:ok, {:float, line, float_val}}

                _ ->
                  :not_number
              end
          end
      end
    end
  end

  defp parse_ratio(str, line) do
    case String.split(str, "/") do
      [num_str, den_str] when num_str != "" and den_str != "" ->
        with {num, ""} <- parse_signed_int(num_str),
             {den, ""} <- Integer.parse(den_str),
             true <-
               den > 0 and not String.starts_with?(den_str, "+") and
                 not String.starts_with?(den_str, "-") do
          case ExLisp.Ratio.new(num, den) do
            %ExLisp.Ratio{} = ratio ->
              {:ok, {:ratio, line, ratio}}

            int_val when is_integer(int_val) ->
              {:ok, {:int, line, int_val}}
          end
        else
          _ -> :not_ratio
        end

      _ ->
        :not_ratio
    end
  end

  defp parse_signed_int("+" <> rest), do: Integer.parse(rest)
  defp parse_signed_int(str), do: Integer.parse(str)

  # Parse keyword / identifier / symbol
  defp parse_symbol_or_keyword(str, line) do
    cond do
      # 1. nil / NIL
      String.downcase(str) in ["nil", "n.i.l"] ->
        {nil, line}

      # 2. t / T
      String.downcase(str) == "t" ->
        {:t, line}

      # 3. Module function remote call (e.g., :math:sqrt, :io:read, math:sqrt, IO.puts, String.upcase)
      is_remote_call?(str) ->
        parts = split_remote_parts(str)
        {:id, line, parts}

      # 4. Single keyword (e.g., :foo, :bar, :my-key, :nil, :t)
      String.starts_with?(str, ":") ->
        keyword_name = String.slice(str, 1..-1//1) |> normalize_symbol_name()

        atom =
          case keyword_name do
            "nil" -> :":nil"
            "t" -> :":t"
            _ -> String.to_atom(keyword_name)
          end

        ExLisp.Env.register_keyword(atom)
        {:keyword, line, atom}

      # 5. Regular symbol
      true ->
        normalized = normalize_symbol_name(str)
        {:symbol, line, normalized}
    end
  end

  defp is_remote_call?(str) do
    cleaned = if String.starts_with?(str, ":"), do: String.slice(str, 1..-1//1), else: str

    (String.contains?(cleaned, ":") or String.contains?(cleaned, ".")) and
      str not in [":", "."]
  end

  defp split_remote_parts(str) do
    cleaned = if String.starts_with?(str, ":"), do: String.slice(str, 1..-1//1), else: str

    cleaned
    |> String.split([":", "."])
    |> Enum.reject(&(&1 == ""))
  end

  # Symbol operators and special symbols (not undergoing hyphen conversion)
  @preserved_symbols [
    "+",
    "-",
    "*",
    "/",
    "1+",
    "1-",
    "=",
    "/=",
    "<",
    "<=",
    ">",
    ">=",
    "**",
    "***",
    "++",
    "+++",
    "string=",
    "string/=",
    "string<",
    "string<=",
    "string>",
    "string>=",
    "char=",
    "char/=",
    "char<",
    "char<=",
    "char>",
    "char>=",
    "list*",
    "let*"
  ]

  @doc """
  Normalizes a symbol string to ExLisp's standard symbol representation.
  Converts to lower case and replaces hyphens `-` with underscores `_` for general symbols.
  """
  def normalize_symbol_name(str) do
    down = String.downcase(str)

    cond do
      down in @preserved_symbols ->
        down

      String.starts_with?(down, "+") and String.ends_with?(down, "+") and String.length(down) > 2 ->
        inner = String.slice(down, 1..-2//1) |> String.replace("-", "_")
        "+#{inner}+"

      String.starts_with?(down, "*") and String.ends_with?(down, "*") and String.length(down) > 2 ->
        inner = String.slice(down, 1..-2//1) |> String.replace("-", "_")
        "*#{inner}*"

      true ->
        String.replace(down, "-", "_")
    end
  end

  # =========================================================================
  # Syntax Analysis (S-expression Parser)
  # =========================================================================

  defp parse_tokens(tokens) do
    case parse_all_top_level(tokens, []) do
      {:ok, []} ->
        {:ok, {:lit, nil}}

      {:ok, [single_expr]} ->
        {:ok, single_expr}

      {:ok, exprs} when is_list(exprs) and exprs != [] ->
        # When multiple expressions are written at top-level (unparenthesized function calls, etc.)
        # Group them into a list expression {:list, 1, exprs}
        {:ok, {:list, 1, exprs}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_all_top_level([], acc), do: {:ok, Enum.reverse(acc)}

  defp parse_all_top_level([{:feature_plus, _line} | rest], acc) do
    case parse_expr(rest) do
      {:ok, feature_expr, rem1} ->
        if feature_matches?(feature_expr) do
          parse_all_top_level(rem1, acc)
        else
          case skip_next_expr(rem1) do
            {:ok, rem2} -> parse_all_top_level(rem2, acc)
            err -> err
          end
        end

      err ->
        err
    end
  end

  defp parse_all_top_level([{:feature_minus, _line} | rest], acc) do
    case parse_expr(rest) do
      {:ok, feature_expr, rem1} ->
        if not feature_matches?(feature_expr) do
          parse_all_top_level(rem1, acc)
        else
          case skip_next_expr(rem1) do
            {:ok, rem2} -> parse_all_top_level(rem2, acc)
            err -> err
          end
        end

      err ->
        err
    end
  end

  defp parse_all_top_level(tokens, acc) do
    case parse_expr(tokens) do
      {:ok, expr, rest} ->
        parse_all_top_level(rest, [expr | acc])

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_expr([{:int, _line, val} | rest]), do: {:ok, {:lit, val}, rest}
  defp parse_expr([{:float, _line, val} | rest]), do: {:ok, {:lit, val}, rest}
  defp parse_expr([{:ratio, _line, val} | rest]), do: {:ok, {:lit, val}, rest}
  defp parse_expr([{:string, _line, val} | rest]), do: {:ok, {:lit, val}, rest}
  defp parse_expr([{:char, _line, val} | rest]), do: {:ok, {:lit, val}, rest}
  defp parse_expr([{:keyword, line, nil} | rest]), do: {:ok, {:keyword, line, nil}, rest}
  defp parse_expr([{:keyword, _line, val} | rest]), do: {:ok, {:lit, val}, rest}
  defp parse_expr([{nil, _line} | rest]), do: {:ok, {:lit, nil}, rest}
  defp parse_expr([{:t, _line} | rest]), do: {:ok, {:lit, :t}, rest}
  defp parse_expr([{:id, line, parts} | rest]), do: {:ok, {:id, line, parts}, rest}
  defp parse_expr([{:symbol, line, name} | rest]), do: {:ok, {:id, line, [name]}, rest}

  defp parse_expr([{:bit_vector, line, bits} | rest]) do
    elem_nodes = Enum.map(bits, fn b -> {:lit, b} end)
    {:ok, {:list, line, [{:id, line, ["vector"]} | elem_nodes]}, rest}
  end

  # Read-time eval (#.form)
  defp parse_expr([{:read_eval, _line} | rest]) do
    case parse_expr(rest) do
      {:ok, form, rem} ->
        try do
          val = LispBeam.evaluate_ast(form)
          {:ok, {:lit, val}, rem}
        rescue
          _ ->
            {:ok, form, rem}
        end

      err ->
        err
    end
  end

  # Complex number (#c(real imag))
  defp parse_expr([{:complex_lparen, line} | rest]) do
    case parse_list(rest, line, :rparen, []) do
      {:ok, {:list, l, [real, imag]}, rem} ->
        {:ok, {:list, l, [{:id, l, ["complex"]}, real, imag]}, rem}

      {:ok, {:list, l, elems}, rem} ->
        {:ok, {:list, l, [{:id, l, ["complex"]} | elems]}, rem}

      err ->
        err
    end
  end

  # Reader conditionals (#+ / #-)
  defp parse_expr([{:feature_plus, _line} | rest]) do
    case parse_expr(rest) do
      {:ok, feature_expr, rem1} ->
        if feature_matches?(feature_expr) do
          parse_expr(rem1)
        else
          case skip_next_expr(rem1) do
            {:ok, []} -> {:ok, {:lit, nil}, []}
            {:ok, rem2} -> parse_expr(rem2)
            err -> err
          end
        end

      err ->
        err
    end
  end

  defp parse_expr([{:feature_minus, _line} | rest]) do
    case parse_expr(rest) do
      {:ok, feature_expr, rem1} ->
        if not feature_matches?(feature_expr) do
          parse_expr(rem1)
        else
          case skip_next_expr(rem1) do
            {:ok, []} -> {:ok, {:lit, nil}, []}
            {:ok, rem2} -> parse_expr(rem2)
            err -> err
          end
        end

      err ->
        err
    end
  end

  # Vector literal: #( ... ) -> {:vector, line, elems}
  defp parse_expr([{:vec_lparen, line} | rest]) do
    case parse_list(rest, line, :rparen, []) do
      {:ok, {:list, l, elems}, rem} ->
        {:ok, {:vector, l, elems}, rem}

      err ->
        err
    end
  end

  # Quote: 'expr -> (quote expr)
  defp parse_expr([{:quote, line} | rest]) do
    case parse_expr(rest) do
      {:ok, form, rem} ->
        {:ok, {:list, line, [{:id, line, ["quote"]}, form]}, rem}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Function quote: #'expr -> (function expr)
  defp parse_expr([{:func_quote, line} | rest]) do
    case parse_expr(rest) do
      {:ok, form, rem} ->
        {:ok, {:list, line, [{:id, line, ["function"]}, form]}, rem}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Backquote: `expr -> {:backquote, line, form}
  defp parse_expr([{:backquote, line} | rest]) do
    case parse_expr(rest) do
      {:ok, form, rem} ->
        {:ok, {:backquote, line, form}, rem}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Comma-at: ,@expr -> {:comma_at, line, form}
  defp parse_expr([{:comma_at, line} | rest]) do
    case parse_expr(rest) do
      {:ok, form, rem} ->
        {:ok, {:comma_at, line, form}, rem}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Comma: ,expr -> {:comma, line, form}
  defp parse_expr([{:comma, line} | rest]) do
    case parse_expr(rest) do
      {:ok, form, rem} ->
        {:ok, {:comma, line, form}, rem}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # List: ( ... )
  defp parse_expr([{:lparen, line} | rest]) do
    parse_list(rest, line, :rparen, [])
  end

  # Quoted list / vector: [ ... ]
  defp parse_expr([{:lbracket, line} | rest]) do
    case parse_list(rest, line, :rbracket, []) do
      {:ok, {:list, l, elems}, rem} ->
        {:ok, {:quoted, l, elems}, rem}

      {:ok, {:dotted_list, l, elems, tail}, rem} ->
        {:ok, {:dotted_list, l, elems, tail}, rem}

      err ->
        err
    end
  end

  # Braces: { ... }
  defp parse_expr([{:lbrace, line} | rest]) do
    parse_list(rest, line, :rbrace, [])
  end

  # Unexpected delimiter
  defp parse_expr([{unexpected, line} | _rest])
       when unexpected in [:rparen, :rbracket, :rbrace] do
    {:error, "unexpected delimiter #{token_to_delimiter(unexpected)} at line #{line}"}
  end

  defp parse_expr([]), do: {:error, "unexpected EOF"}

  defp parse_list([], line, _expected_close, _acc) do
    {:error, "unclosed delimiter starting at line #{line}"}
  end

  defp parse_list([{close_tok, _} | rest], line, close_tok, acc) do
    {:ok, {:list, line, Enum.reverse(acc)}, rest}
  end

  defp parse_list([{unexpected, l} | _rest], _line, expected_close, _acc)
       when unexpected in [:rparen, :rbracket, :rbrace] and unexpected != expected_close do
    {:error, "unexpected delimiter #{token_to_delimiter(unexpected)} at line #{l}"}
  end

  defp parse_list([{:feature_plus, _line} | rest], line, close_tok, acc) do
    case parse_expr(rest) do
      {:ok, feature_expr, rem1} ->
        if feature_matches?(feature_expr) do
          parse_list(rem1, line, close_tok, acc)
        else
          case skip_next_expr(rem1) do
            {:ok, rem2} -> parse_list(rem2, line, close_tok, acc)
            err -> err
          end
        end

      err ->
        err
    end
  end

  defp parse_list([{:feature_minus, _line} | rest], line, close_tok, acc) do
    case parse_expr(rest) do
      {:ok, feature_expr, rem1} ->
        if not feature_matches?(feature_expr) do
          parse_list(rem1, line, close_tok, acc)
        else
          case skip_next_expr(rem1) do
            {:ok, rem2} -> parse_list(rem2, line, close_tok, acc)
            err -> err
          end
        end

      err ->
        err
    end
  end

  # Dotted pair (a . b) or (a b . c)
  defp parse_list([{tok_type, dot_line, "."} | rest], line, close_tok, acc)
       when tok_type in [:symbol, :id] do
    if acc == [] do
      {:error, "unexpected dot at beginning of list at line #{dot_line}"}
    else
      case parse_expr(rest) do
        {:ok, tail_expr, after_tail} ->
          case after_tail do
            [{^close_tok, _} | remaining] ->
              {:ok, build_dotted_list(line, Enum.reverse(acc), tail_expr), remaining}

            [{_unexpected, err_line} | _] ->
              {:error,
               "expected #{token_to_delimiter(close_tok)} after dotted tail at line #{err_line}"}

            [] ->
              {:error, "unclosed delimiter after dotted tail starting at line #{line}"}
          end

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp parse_list(tokens, line, close_tok, acc) do
    case parse_expr(tokens) do
      {:ok, expr, rest} ->
        parse_list(rest, line, close_tok, [expr | acc])

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_dotted_list(line, elements, tail_expr) do
    case tail_expr do
      {:lit, nil} ->
        {:list, line, elements}

      {:list, _l, tail_elems} ->
        {:list, line, elements ++ tail_elems}

      {:dotted_list, _l, tail_elems, final_tail} ->
        {:dotted_list, line, elements ++ tail_elems, final_tail}

      other ->
        {:dotted_list, line, elements, other}
    end
  end

  defp skip_next_expr(tokens) do
    case parse_expr(tokens) do
      {:ok, _ast, rest} -> {:ok, rest}
      err -> err
    end
  end

  @doc """
  Determines whether a reader conditional (#+ / #-) matches the current ExLisp environment.
  """
  def feature_matches?(feature_expr) do
    case feature_expr do
      {:list, _pos, [{:id, _, ["or"]} | subs]} ->
        Enum.any?(subs, &feature_matches?/1)

      {:list, _pos, [{:id, _, ["and"]} | subs]} ->
        Enum.all?(subs, &feature_matches?/1)

      {:list, _pos, [{:id, _, ["not"]}, sub]} ->
        not feature_matches?(sub)

      {:id, _pos, [name]} ->
        check_feature_name(name)

      {:id, _pos, parts} when is_list(parts) ->
        check_feature_name(List.last(parts))

      {:lit, atom} when is_atom(atom) ->
        check_feature_name(Atom.to_string(atom))

      atom when is_atom(atom) ->
        check_feature_name(Atom.to_string(atom))

      name when is_binary(name) ->
        check_feature_name(name)

      _ ->
        false
    end
  end

  defp check_feature_name(name) do
    down = String.downcase(to_string(name)) |> String.trim_leading(":")

    known_features = [
      "exlisp",
      "cl",
      "common_lisp",
      "common-lisp",
      "ansi_cl",
      "ansi-cl",
      "beam",
      "erlang",
      "elixir"
    ]

    if down in known_features do
      true
    else
      try do
        cond do
          ExLisp.Env.has_var?(:_cl_features_) ->
            env_feats = ExLisp.Env.get_var(:_cl_features_)
            match_env_feature?(down, env_feats)

          ExLisp.Env.has_var?(:features) ->
            env_feats = ExLisp.Env.get_var(:features)
            match_env_feature?(down, env_feats)

          true ->
            false
        end
      rescue
        _ -> false
      end
    end
  end

  defp match_env_feature?(name, feats) when is_list(feats) do
    Enum.any?(feats, fn f ->
      f_str = f |> to_string() |> String.downcase() |> String.trim_leading(":")
      f_str == name
    end)
  end

  defp match_env_feature?(_, _), do: false

  defp token_to_delimiter(:rparen), do: ")"
  defp token_to_delimiter(:rbracket), do: "]"
  defp token_to_delimiter(:rbrace), do: "}"
  defp token_to_delimiter(other), do: to_string(other)
end
