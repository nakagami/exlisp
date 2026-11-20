defmodule ExLisp.PPrint do
  @moduledoc """
  Common Lisp compatible, stream-based pretty-printer primitives.

  The full pretty printer protocol is represented with ordinary Elixir functions.
  Dispatch tables are process-local by default and can also be passed explicitly.
  """

  defstruct entries: []

  @type dispatch_entry :: {term(), non_neg_integer(), term()}
  @type dispatch_table :: %__MODULE__{entries: [dispatch_entry()]}
  @default_table_key :exlisp_pprint_dispatch
  @block_stack_key :exlisp_pprint_block_stack
  @print_readably_key :exlisp_print_readably

  @doc "Pretty-prints `object`, followed by a fresh line."
  def pprint(object, stream \\ nil) do
    resolved = stream
    write_string(to_pretty_string(object), resolved)
    ExLisp.Stream.terpri(resolved)
    nil
  end

  @doc "Returns the dispatch function selected for `object`."
  def pprint_dispatch(object, table \\ nil) do
    pprint_dispatch_mv(object, table) |> ExLisp.Builtins.unwrap_mv_primary()
  end

  @doc "Returns `(values function found-p)` for a pretty-printer dispatch."
  def pprint_dispatch_mv(object, table \\ nil) do
    entries =
      case resolve_table(table) do
        %__MODULE__{entries: values} -> values
      end

    match =
      entries
      |> Enum.sort_by(fn {_type, priority, _fun} -> -priority end)
      |> Enum.find(fn {type, _priority, fun} -> fun != nil and dispatch_match?(type, object) end)

    case match do
      {_type, _priority, fun} -> multiple_values([fun, :t])
      nil -> multiple_values([&default_print_function/2, nil])
    end
  end

  @doc "Installs a dispatch entry and returns nil."
  def set_pprint_dispatch(type, function, priority \\ 0, table \\ nil) do
    target = resolve_table(table)

    entries =
      target.entries
      |> Enum.reject(fn {existing_type, _old_priority, _fun} ->
        existing_type == type
      end)
      |> then(fn entries -> [{type, normalize_priority(priority), function} | entries] end)

    updated = %{target | entries: entries}

    if is_nil(table) do
      Process.put(@default_table_key, updated)
    else
      Process.put({@default_table_key, table_identity(table)}, updated)
    end

    nil
  end

  @doc "Copies a dispatch table. With no argument, returns the default table copy."
  def copy_pprint_dispatch(table \\ nil) do
    source = resolve_table(table)
    %__MODULE__{entries: List.duplicate(source.entries, 1) |> List.flatten()}
  end

  @doc "Exits the active logical block when `list` is empty."
  def pprint_exit_if_list_exhausted(list) do
    if empty_list?(list) do
      case Process.get(@block_stack_key, []) do
        [tag | _] -> throw({:pprint_exit, tag})
        [] -> :t
      end
    else
      nil
    end
  end

  @doc "Pretty-prints a list using fill (greedy line filling) layout."
  def pprint_fill(stream, list, colon_p \\ nil, at_sign_p \\ nil) do
    pprint_list_layout(:fill, stream, list, colon_p, at_sign_p)
  end

  @doc "Sets the current indentation level for the active logical block."
  def pprint_indent(relative_to, amount, stream \\ nil) do
    key = {:exlisp_pprint_indent, stream_key(stream)}
    base = current_column(stream)

    value =
      case relative_to do
        :block -> amount
        :current -> base + amount
        _ -> base + amount
      end

    Process.put(key, max(value, 0))
    nil
  end

  @doc "Pretty-prints a list using linear (one-line or one-item-per-line) layout."
  def pprint_linear(stream, list, colon_p \\ nil, at_sign_p \\ nil) do
    pprint_list_layout(:linear, stream, list, colon_p, at_sign_p)
  end

  @doc """
  Establishes a logical pretty-printer block and invokes `fun`.

  `fun` may accept `(stream, object)` or just `stream`.
  """
  def pprint_logical_block(
        stream,
        object,
        prefix \\ "",
        per_line_prefix \\ "",
        suffix \\ "",
        fun \\ nil
      ) do
    body =
      cond do
        is_function(fun) -> fun
        match?(%{__struct__: ExLisp.Closure}, suffix) -> suffix
        match?(%{__struct__: ExLisp.Closure}, per_line_prefix) -> per_line_prefix
        match?(%{__struct__: ExLisp.Closure}, prefix) -> prefix
        is_function(suffix) -> suffix
        is_function(per_line_prefix) -> per_line_prefix
        is_function(prefix) -> prefix
        true -> nil
      end

    actual_prefix =
      if is_function(prefix), do: "", else: ExLisp.Builtins.to_string_val(prefix)

    actual_line_prefix =
      if is_function(per_line_prefix),
        do: "",
        else: ExLisp.Builtins.to_string_val(per_line_prefix)

    actual_suffix =
      if is_function(suffix), do: "", else: ExLisp.Builtins.to_string_val(suffix)

    tag = make_ref()
    previous = Process.get(@block_stack_key, [])
    Process.put(@block_stack_key, [tag | previous])

    try do
      write_string(actual_prefix, stream)
      Process.put({:exlisp_pprint_line_prefix, stream_key(stream)}, actual_line_prefix)

      if body do
        cond do
          is_function(body, 2) -> body.(stream, object)
          is_function(body, 1) -> body.(stream)
          is_function(body, 0) -> body.()
          true -> ExLisp.Builtins.invoke_fn(body, [stream, object])
        end
      end

      write_string(actual_suffix, stream)
      object
    catch
      {:pprint_exit, ^tag} ->
        write_string(actual_suffix, stream)
        object
    after
      Process.put(@block_stack_key, previous)
      Process.delete({:exlisp_pprint_line_prefix, stream_key(stream)})
    end
  end

  @doc "Prints a pretty-printer newline."
  def pprint_newline(kind \\ :linear, stream \\ nil) do
    case kind do
      _ ->
        ExLisp.Stream.terpri(stream)
        Process.put({:exlisp_pprint_column, stream_key(stream)}, 0)
        nil
    end
  end

  @doc "Pops one object from the active pprint list."
  def pprint_pop(list \\ nil) do
    actual = if is_nil(list), do: Process.get(:exlisp_pprint_pop_list, []), else: list

    case actual do
      [] ->
        pprint_exit_if_list_exhausted(actual)
        nil

      [head | tail] ->
        Process.put(:exlisp_pprint_pop_list, tail)
        head
    end
  end

  @doc "Advances to the tab stop described by `column` and `increment`."
  def pprint_tab(kind, column, increment, stream \\ nil) do
    current = current_column(stream)

    target =
      case kind do
        :section ->
          if increment <= 0,
            do: current,
            else: ((current + increment - 1) |> div(increment)) * increment

        :section_relative ->
          max(current, normalize_nonnegative(column))

        :line_relative ->
          current + max(increment, 0)

        _ ->
          max(normalize_nonnegative(column), current)
      end

    write_string(String.duplicate(" ", max(target - current, 0)), stream)
    nil
  end

  @doc "Pretty-prints a list in aligned, tabular form."
  def pprint_tabular(stream, list, colon_p \\ nil, at_sign_p \\ nil, tabsize \\ 8) do
    values = normalize_list(list)
    strings = Enum.map(values, &object_string/1)
    width = Enum.reduce(strings, 0, &max(String.length(&1), &2))
    effective = max(normalize_nonnegative(tabsize), 1)
    column_width = ((width + 1 + effective - 1) |> div(effective)) * effective
    rendered = Enum.map_join(strings, "", &String.pad_trailing(&1, column_width))
    delimiter_prefix(colon_p, stream)
    write_string(String.trim_trailing(rendered), stream)
    delimiter_suffix(at_sign_p, stream)
    nil
  end

  @doc "Returns a format function suitable for passing to `format` or `funcall`."
  def formatter(control) do
    fn stream, args ->
      values = if is_list(args), do: args, else: [args]
      output = ExLisp.CLFormat.format(control, values)

      if stream == nil or stream == :t do
        if stream == nil,
          do: output,
          else:
            (
              write_string(output, :t)
              nil
            )
      else
        write_string(output, stream)
        nil
      end
    end
  end

  @doc "Prints an object using a dispatch function when one is installed."
  def print_object(object, stream \\ nil) do
    function = pprint_dispatch(object)
    ExLisp.Builtins.invoke_fn(function, [stream, object])
    object
  end

  @doc """
  Prints an unreadable object representation around an optional body.

  The supported options are `:type` and `:identity`. `body` may be a zero- or
  one-argument function.
  """
  def print_unreadable_object(object, stream \\ nil, opts \\ [], body \\ nil) do
    parsed = if is_list(opts), do: ExLisp.Builtins.parse_lisp_keywords(opts), else: []
    type_p = Keyword.get(parsed, :type, false)
    identity_p = Keyword.get(parsed, :identity, false)

    if truthy?(Process.get(@print_readably_key, nil)) do
      raise_print_not_readable(object)
    end

    pieces =
      []
      |> add_piece(if(truthy?(type_p), do: object_type_name(object)))
      |> add_piece(if(truthy?(identity_p), do: object_identity(object)))

    write_string("#<" <> (pieces |> Enum.reverse() |> Enum.join(" ")), stream)

    if body do
      if is_function(body, 0), do: body.(), else: ExLisp.Builtins.invoke_fn(body, [stream])
    end

    write_string(">", stream)
    object
  end

  @doc "Sets the process-local print-readably flag."
  def set_print_readably(value), do: Process.put(@print_readably_key, value)

  defp pprint_list_layout(kind, stream, list, colon_p, at_sign_p) do
    values = normalize_list(list)
    Process.put(:exlisp_pprint_pop_list, values)
    strings = Enum.map(values, &object_string/1)

    delimiter_prefix(colon_p, stream)

    case kind do
      :linear ->
        one_line = Enum.join(strings, " ")

        if fits_on_line?(stream, one_line) do
          write_string(one_line, stream)
        else
          Enum.intersperse(strings, "\n") |> IO.iodata_to_binary() |> write_string(stream)
        end

      :fill ->
        indent = Process.get({:exlisp_pprint_indent, stream_key(stream)}, current_column(stream))

        strings
        |> Enum.reduce({current_column(stream), []}, fn text, {column, output} ->
          separator = if output == [], do: "", else: " "
          proposed = column + String.length(separator) + String.length(text)

          if proposed > 80 and output != [] do
            {indent + String.length(text), [text, String.duplicate(" ", indent) <> "\n" | output]}
          else
            {proposed, [separator <> text | output]}
          end
        end)
        |> elem(1)
        |> Enum.reverse()
        |> IO.iodata_to_binary()
        |> write_string(stream)
    end

    delimiter_suffix(at_sign_p, stream)
    nil
  end

  defp default_print_function(stream, object) do
    write_string(object_string(object), stream)
    object
  end

  defp to_pretty_string(object) do
    function = pprint_dispatch(object)
    stream = ExLisp.Stream.make_string_output_stream()

    try do
      ExLisp.Builtins.invoke_fn(function, [stream, object])
      ExLisp.Stream.get_output_stream_string(stream)
    after
      ExLisp.Stream.close(stream)
    end
  end

  defp object_string(%ExLisp.Character{} = character), do: inspect(character)
  defp object_string(value), do: ExLisp.Builtins.prin1_to_string(value)

  defp dispatch_match?(type, object) when is_atom(type) do
    case type do
      :t -> true
      :string -> is_binary(object)
      :list -> is_list(object)
      :number -> is_number(object)
      :integer -> is_integer(object)
      :character -> match?(%ExLisp.Character{}, object)
      :stream -> ExLisp.Stream.streamp(object) == :t
      _ -> object == type
    end
  end

  defp dispatch_match?(type, object) when is_function(type, 1), do: type.(object)
  defp dispatch_match?(_, _), do: false

  defp default_table, do: %__MODULE__{}
  defp ensure_table(%__MODULE__{} = table), do: table
  defp ensure_table(_), do: %__MODULE__{}

  defp resolve_table(nil),
    do: ensure_table(Process.get(@default_table_key) || default_table())

  defp resolve_table(table) do
    Process.get({@default_table_key, table_identity(table)}) || ensure_table(table)
  end

  defp table_identity(table), do: :erlang.phash2(table)

  defp multiple_values(values), do: [:_values_, values]
  defp normalize_priority(value) when is_number(value), do: value
  defp normalize_priority(_), do: 0
  defp normalize_nonnegative(value) when is_number(value), do: max(value, 0)
  defp normalize_nonnegative(_), do: 0
  defp normalize_list(list) when is_list(list), do: list
  defp normalize_list(other), do: [other]
  defp empty_list?([]), do: true
  defp empty_list?(nil), do: true
  defp empty_list?(_), do: false
  defp truthy?(nil), do: false
  defp truthy?(false), do: false
  defp truthy?(_), do: true

  defp delimiter_prefix(value, stream) when value in [:t, true], do: write_string("(", stream)
  defp delimiter_prefix(_, _), do: :ok
  defp delimiter_suffix(value, stream) when value in [:t, true], do: write_string(")", stream)
  defp delimiter_suffix(_, _), do: :ok

  defp fits_on_line?(stream, text), do: current_column(stream) + String.length(text) <= 80
  defp stream_key(nil), do: :standard_output
  defp stream_key(%ExLisp.Stream{id: id}), do: id
  defp stream_key(stream), do: stream

  defp current_column(stream) do
    Process.get({:exlisp_pprint_column, stream_key(stream)}, 0)
  end

  defp write_string(text, stream) do
    text = IO.iodata_to_binary(text)
    prefix = Process.get({:exlisp_pprint_line_prefix, stream_key(stream)}, "")
    text = if prefix == "", do: text, else: String.replace(text, "\n", "\n" <> prefix)
    ExLisp.Stream.write_string(text, stream)

    final_column =
      case String.split(text, "\n") do
        [_one] ->
          current_column(stream) + String.length(text)

        parts ->
          List.last(parts)
          |> then(&(String.length(&1) + String.length(prefix)))
      end

    Process.put({:exlisp_pprint_column, stream_key(stream)}, final_column)
    text
  end

  defp add_piece(pieces, nil), do: pieces
  defp add_piece(pieces, ""), do: pieces
  defp add_piece(pieces, piece), do: [piece | pieces]

  defp object_type_name(object) when is_binary(object), do: "STRING"
  defp object_type_name(object) when is_list(object), do: "LIST"
  defp object_type_name(%{__struct__: module}), do: module |> Module.split() |> List.last()
  defp object_type_name(object) when is_atom(object), do: "SYMBOL"
  defp object_type_name(_), do: "OBJECT"
  defp object_identity(object), do: "0x" <> Integer.to_string(:erlang.phash2(object), 16)

  defp raise_print_not_readable(object) do
    condition =
      ExLisp.Condition.make_condition(:print_not_readable, [
        :format_control,
        "Cannot print ~S readably.",
        :format_arguments,
        [object]
      ])

    ExLisp.Condition.error(condition)
  end
end
