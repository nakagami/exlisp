defmodule ExLisp.Stream do
  @moduledoc """
  ANSI Common Lisp Streams implementation for ExLisp.
  Supports:
  - streamp, open-stream-p, input-stream-p, output-stream-p, interactive-stream-p, stream-element-type, close
  - make-string-input-stream, make-string-output-stream, get-output-stream-string
  - make-broadcast-stream, make-concatenated-stream, make-two-way-stream, make-echo-stream, make-synonym-stream
  - broadcast-stream-streams, concatenated-stream-streams, two-way-stream-input-stream, two-way-stream-output-stream,
    echo-stream-input-stream, echo-stream-output-stream, synonym-stream-symbol
  - open, file-length, file-position
  - read-char, unread-char, peek-char, read-line, read-sequence
  - write-char, write-string, write-line, write-sequence
  - terpri, fresh_line, finish-output, force-output, clear-output, listen, clear-input
  """

  defstruct id: nil,
            type: :file,
            device: nil,
            mode: :input,
            element_type: :character,
            open: true,
            unread_chars: [],
            extra: %{}

  @type t :: %__MODULE__{
          id: any(),
          type: :file | :string_input | :string_output | :broadcast | :concatenated | :two_way | :echo | :synonym | :standard,
          device: any(),
          mode: :input | :output | :io,
          element_type: any(),
          open: boolean(),
          unread_chars: list(integer()),
          extra: map()
        }

  # --- Stream Predicates ---

  def streamp(%__MODULE__{}), do: :t
  def streamp(pid) when is_pid(pid), do: :t
  def streamp(:standard_io), do: :t
  def streamp([%__MODULE__{}]), do: :t
  def streamp([pid]) when is_pid(pid), do: :t
  def streamp(_), do: nil

  def open_stream_p(%__MODULE__{open: open}), do: lisp_bool(open)
  def open_stream_p(pid) when is_pid(pid), do: lisp_bool(Process.alive?(pid))
  def open_stream_p(:standard_io), do: :t
  def open_stream_p([s]), do: open_stream_p(s)
  def open_stream_p(_), do: nil

  def input_stream_p(%__MODULE__{mode: mode, open: true}) when mode in [:input, :io], do: :t
  def input_stream_p(%__MODULE__{type: :synonym, extra: %{symbol: sym}}) do
    target = resolve_synonym(sym)
    input_stream_p(target)
  end
  def input_stream_p(pid) when is_pid(pid), do: :t
  def input_stream_p(:standard_io), do: :t
  def input_stream_p([s]), do: input_stream_p(s)
  def input_stream_p(_), do: nil

  def output_stream_p(%__MODULE__{mode: mode, open: true}) when mode in [:output, :io], do: :t
  def output_stream_p(%__MODULE__{type: :synonym, extra: %{symbol: sym}}) do
    target = resolve_synonym(sym)
    output_stream_p(target)
  end
  def output_stream_p(pid) when is_pid(pid), do: :t
  def output_stream_p(:standard_io), do: :t
  def output_stream_p([s]), do: output_stream_p(s)
  def output_stream_p(_), do: nil

  def interactive_stream_p(%__MODULE__{type: :standard}), do: :t
  def interactive_stream_p(:standard_io), do: :t
  def interactive_stream_p([s]), do: interactive_stream_p(s)
  def interactive_stream_p(_), do: nil

  def stream_element_type(%__MODULE__{element_type: etype}), do: etype
  def stream_element_type([s]), do: stream_element_type(s)
  def stream_element_type(_), do: :character

  # --- Closing Streams ---

  def close(stream, opts \\ [])
  def close(%__MODULE__{type: :synonym} = s, _opts), do: s

  def close(%__MODULE__{device: dev, type: t, open: true}, _opts) do
    if is_pid(dev) and Process.alive?(dev) do
      if t in [:string_input, :string_output] do
        try do
          StringIO.close(dev)
        rescue
          _ -> :ok
        catch
          _, _ -> :ok
        end
      else
        try do
          :file.close(dev)
        rescue
          _ -> :ok
        catch
          _, _ -> :ok
        end
      end
    end

    :t
  end

  def close(pid, _opts) when is_pid(pid) do
    if Process.alive?(pid) do
      try do
        :file.close(pid)
      rescue
        _ -> :ok
      catch
        _, _ -> :ok
      end
    end
    :t
  end

  def close([s | _], opts), do: close(s, opts)
  def close(other, _opts), do: other

  # --- String Streams ---

  def make_string_input_stream(string, arg2 \\ 0, arg3 \\ nil) do
    str = ExLisp.Builtins.to_string_val(string)

    {start, end_pos} =
      cond do
        is_integer(arg2) ->
          {arg2, arg3}

        is_list(arg2) ->
          opts = ExLisp.Builtins.parse_lisp_keywords(arg2)
          s = Keyword.get(opts, :start, 0)
          e = Keyword.get(opts, :end, nil)
          {s, e}

        arg2 in [:start, :":start"] ->
          {arg3, nil}

        true ->
          {0, nil}
      end

    s = if is_integer(start) and start > 0, do: start, else: 0

    sliced =
      if is_integer(end_pos) and end_pos >= s do
        String.slice(str, s, end_pos - s)
      else
        String.slice(str, s..-1//1)
      end

    {:ok, pid} = StringIO.open(sliced)

    %__MODULE__{
      id: System.unique_integer([:positive, :monotonic]),
      type: :string_input,
      device: pid,
      mode: :input,
      element_type: :character,
      open: true,
      extra: %{string: sliced}
    }
  end

  def make_string_output_stream(opts \\ []) do
    opt_list = if is_list(opts), do: opts, else: [opts]
    parsed_opts = ExLisp.Builtins.parse_lisp_keywords(opt_list)
    etype = Keyword.get(parsed_opts, :element_type, :character)

    {:ok, pid} = StringIO.open("")

    %__MODULE__{
      id: System.unique_integer([:positive, :monotonic]),
      type: :string_output,
      device: pid,
      mode: :output,
      element_type: etype,
      open: true
    }
  end

  def get_output_stream_string(%__MODULE__{device: pid}) when is_pid(pid) do
    StringIO.flush(pid)
  end

  def get_output_stream_string(pid) when is_pid(pid) do
    StringIO.flush(pid)
  end

  def get_output_stream_string([s]), do: get_output_stream_string(s)
  def get_output_stream_string(_), do: ""

  # --- Composite Streams ---

  def make_broadcast_stream(streams \\ [])

  def make_broadcast_stream(streams) when is_list(streams) do
    %__MODULE__{
      id: System.unique_integer([:positive, :monotonic]),
      type: :broadcast,
      device: nil,
      mode: :output,
      element_type: :character,
      open: true,
      extra: %{streams: streams}
    }
  end

  def make_broadcast_stream(single_stream), do: make_broadcast_stream([single_stream])

  def broadcast_stream_streams(%__MODULE__{type: :broadcast, extra: %{streams: streams}}), do: streams
  def broadcast_stream_streams([s]), do: broadcast_stream_streams(s)
  def broadcast_stream_streams(_), do: []

  def make_concatenated_stream(streams \\ [])

  def make_concatenated_stream(streams) when is_list(streams) do
    %__MODULE__{
      id: System.unique_integer([:positive, :monotonic]),
      type: :concatenated,
      device: nil,
      mode: :input,
      element_type: :character,
      open: true,
      extra: %{streams: streams}
    }
  end

  def make_concatenated_stream(single_stream), do: make_concatenated_stream([single_stream])

  def concatenated_stream_streams(%__MODULE__{type: :concatenated, extra: %{streams: streams}}), do: streams
  def concatenated_stream_streams([s]), do: concatenated_stream_streams(s)
  def concatenated_stream_streams(_), do: []

  def make_two_way_stream(input_stream, output_stream) do
    %__MODULE__{
      id: System.unique_integer([:positive, :monotonic]),
      type: :two_way,
      device: nil,
      mode: :io,
      element_type: :character,
      open: true,
      extra: %{input: input_stream, output: output_stream}
    }
  end

  def two_way_stream_input_stream(%__MODULE__{type: :two_way, extra: %{input: in_s}}), do: in_s
  def two_way_stream_input_stream([s]), do: two_way_stream_input_stream(s)
  def two_way_stream_input_stream(_), do: nil

  def two_way_stream_output_stream(%__MODULE__{type: :two_way, extra: %{output: out_s}}), do: out_s
  def two_way_stream_output_stream([s]), do: two_way_stream_output_stream(s)
  def two_way_stream_output_stream(_), do: nil

  def make_echo_stream(input_stream, output_stream) do
    %__MODULE__{
      id: System.unique_integer([:positive, :monotonic]),
      type: :echo,
      device: nil,
      mode: :io,
      element_type: :character,
      open: true,
      extra: %{input: input_stream, output: output_stream}
    }
  end

  def echo_stream_input_stream(%__MODULE__{type: :echo, extra: %{input: in_s}}), do: in_s
  def echo_stream_input_stream([s]), do: echo_stream_input_stream(s)
  def echo_stream_input_stream(_), do: nil

  def echo_stream_output_stream(%__MODULE__{type: :echo, extra: %{output: out_s}}), do: out_s
  def echo_stream_output_stream([s]), do: echo_stream_output_stream(s)
  def echo_stream_output_stream(_), do: nil

  def make_synonym_stream(symbol) do
    sym_atom =
      cond do
        is_atom(symbol) -> symbol
        is_binary(symbol) -> String.to_atom(symbol)
        match?(%ExLisp.Symbol{}, symbol) -> String.to_atom(symbol.name)
        true -> :":*standard-input*:"
      end

    %__MODULE__{
      id: System.unique_integer([:positive, :monotonic]),
      type: :synonym,
      device: nil,
      mode: :io,
      element_type: :character,
      open: true,
      extra: %{symbol: sym_atom}
    }
  end

  def synonym_stream_symbol(%__MODULE__{type: :synonym, extra: %{symbol: sym}}), do: sym
  def synonym_stream_symbol([s]), do: synonym_stream_symbol(s)
  def synonym_stream_symbol(_), do: nil

  # --- File Streams & Open ---

  @doc """
  Opens a file stream.
  filespec: pathname or string
  options: :direction, :element_type, :if_exists, :if_does_not_exist, :external_format
  """
  def open(filespec, opts \\ [])

  def open(filespec, opts) when is_list(opts) do
    path_str = ExLisp.Pathname.namestring(filespec)
    parsed_opts = ExLisp.Builtins.parse_lisp_keywords(opts)

    direction = Keyword.get(parsed_opts, :direction, :input)
    element_type = Keyword.get(parsed_opts, :element_type, :character)
    if_exists = Keyword.get(parsed_opts, :if_exists, :supersede)
    if_does_not_exist = Keyword.get(parsed_opts, :if_does_not_exist, :error)

    modes =
      case direction do
        :input ->
          [:read, :utf8]

        :output ->
          case if_exists do
            :append -> [:append, :utf8]
            :supersede -> [:write, :utf8]
            :overwrite -> [:write, :utf8]
            :error ->
              if File.exists?(path_str), do: raise("File already exists: #{path_str}"), else: [:write, :utf8]
            nil ->
              if File.exists?(path_str), do: :abort, else: [:write, :utf8]
            _ -> [:write, :utf8]
          end

        :io ->
          [:read, :write, :utf8]

        :probe ->
          [:read]

        _ ->
          [:read, :utf8]
      end

    if modes == :abort do
      nil
    else
      file_exists = File.exists?(path_str)

      cond do
        not file_exists and direction == :input and if_does_not_exist == nil ->
          nil

        not file_exists and direction == :input and if_does_not_exist == :error ->
          raise "File does not exist: #{path_str}"

        not file_exists and direction == :input and if_does_not_exist == :create ->
          File.touch(path_str)
          case File.open(path_str, modes) do
            {:ok, pid} ->
              build_file_stream(pid, path_str, direction, element_type)
            {:error, reason} ->
              raise "Error opening file #{path_str}: #{inspect(reason)}"
          end

        true ->
          case File.open(path_str, modes) do
            {:ok, pid} ->
              build_file_stream(pid, path_str, direction, element_type)

            {:error, reason} ->
              if if_does_not_exist == nil do
                nil
              else
                raise "Error opening file #{path_str}: #{inspect(reason)}"
              end
          end
      end
    end
  end

  def open(filespec, other), do: open(filespec, [other])

  defp build_file_stream(pid, path_str, direction, element_type) do
    %__MODULE__{
      id: System.unique_integer([:positive, :monotonic]),
      type: :file,
      device: pid,
      mode: direction,
      element_type: element_type,
      open: true,
      extra: %{path: path_str}
    }
  end

  def file_length(%__MODULE__{extra: %{path: path}}) when is_binary(path) do
    case File.stat(path) do
      {:ok, %{size: size}} -> size
      _ -> nil
    end
  end

  def file_length(%__MODULE__{device: pid}) when is_pid(pid) do
    case :file.position(pid, :eof) do
      {:ok, size} ->
        :file.position(pid, :bof)
        size

      _ ->
        nil
    end
  end

  def file_length(pid) when is_pid(pid) do
    case :file.position(pid, :eof) do
      {:ok, size} ->
        :file.position(pid, :bof)
        size

      _ ->
        nil
    end
  end

  def file_length([s]), do: file_length(s)
  def file_length(_), do: nil

  def file_position(stream, pos_spec \\ nil)

  def file_position(%__MODULE__{device: dev}, pos_spec) do
    case pos_spec do
      nil ->
        if is_pid(dev) do
          0
        else
          case :file.position(dev, :cur) do
            {:ok, pos} -> pos
            _ -> 0
          end
        end

      :start ->
        if is_pid(dev) do
          :ok
        else
          case :file.position(dev, :bof) do
            {:ok, pos} -> pos
            _ -> :t
          end
        end

      :end ->
        if is_pid(dev) do
          :ok
        else
          case :file.position(dev, :eof) do
            {:ok, pos} -> pos
            _ -> :t
          end
        end

      offset when is_integer(offset) ->
        if is_pid(dev) do
          :t
        else
          case :file.position(dev, {:bof, offset}) do
            {:ok, pos} -> pos
            _ -> :t
          end
        end
    end
  end

  def file_position(pid, pos_spec) when is_pid(pid) do
    file_position(%__MODULE__{device: pid}, pos_spec)
  end

  def file_position(other, _), do: other

  # --- Character & Line I/O ---

  @doc """
  Reads a single character (as an integer character code) from stream.
  """
  def read_char(stream \\ nil, eof_error_p \\ :t, eof_value \\ nil, _recursive_p \\ nil) do
    s = resolve_input_stream(stream)

    case s do
      %__MODULE__{type: :concatenated, extra: %{streams: []}} ->
        handle_eof(eof_error_p, eof_value)

      %__MODULE__{type: :concatenated, extra: %{streams: [head_s | tail_s]}} = concat_s ->
        case read_char(head_s, nil, :eof) do
          :eof ->
            read_char(%{concat_s | extra: %{streams: tail_s}}, eof_error_p, eof_value)

          c ->
            c
        end

      %__MODULE__{type: :echo, extra: %{input: in_s, output: out_s}} ->
        case read_char(in_s, eof_error_p, eof_value) do
          c when is_integer(c) ->
            write_char(c, out_s)
            c

          other ->
            other
        end

      %__MODULE__{type: :two_way, extra: %{input: in_s}} ->
        read_char(in_s, eof_error_p, eof_value)

      %__MODULE__{device: pid} when is_pid(pid) ->
        read_char_from_pid(pid, s, eof_error_p, eof_value)

      pid when is_pid(pid) ->
        read_char_from_pid(pid, pid, eof_error_p, eof_value)

      _ ->
        case IO.getn(:stdio, "", 1) do
          :eof -> handle_eof(eof_error_p, eof_value)
          <<c::utf8>> -> c
          _ -> handle_eof(eof_error_p, eof_value)
        end
    end
  end

  defp read_char_from_pid(pid, s_ref, eof_error_p, eof_value) do
    key = {:exlisp_stream_unread, stream_id(s_ref)}
    case Process.get(key, []) do
      [c | rest] ->
        Process.put(key, rest)
        c

      [] ->
        case IO.getn(pid, "", 1) do
          :eof ->
            handle_eof(eof_error_p, eof_value)

          {:error, _} ->
            handle_eof(eof_error_p, eof_value)

          "" ->
            handle_eof(eof_error_p, eof_value)

          <<c::utf8>> ->
            c

          char_str when is_binary(char_str) and byte_size(char_str) > 0 ->
            hd(String.to_charlist(char_str))
        end
    end
  end

  @doc """
  Pushes character back to input stream.
  """
  def unread_char(char, stream \\ nil) do
    s = resolve_input_stream(stream)
    code = ExLisp.Builtins.char_code(char)
    key = {:exlisp_stream_unread, stream_id(s)}
    existing = Process.get(key, [])
    Process.put(key, [code | existing])
    nil
  end

  @doc """
  Peeks at next character without consuming it.
  """
  def peek_char(_peek_type \\ nil, stream \\ nil, eof_error_p \\ :t, eof_value \\ nil, _rec \\ nil) do
    s = resolve_input_stream(stream)

    case read_char(s, eof_error_p, eof_value) do
      c when is_integer(c) ->
        unread_char(c, s)
        c

      other ->
        other
    end
  end

  @doc """
  Reads a line from stream.
  """
  def read_line(stream \\ nil, eof_error_p \\ :t, eof_value \\ nil, rec \\ nil) do
    case read_line_mv(stream, eof_error_p, eof_value, rec) do
      [:_values_, [line | _]] -> line
      other -> other
    end
  end

  @doc """
  Reads a line from stream.
  Returns multiple values: `(values line missing_newline_p)`.
  """
  def read_line_mv(stream \\ nil, eof_error_p \\ :t, eof_value \\ nil, _rec \\ nil) do
    s = resolve_input_stream(stream)

    case s do
      %__MODULE__{type: :file, device: pid} when is_pid(pid) ->
        read_line_from_pid(pid, eof_error_p, eof_value)

      %__MODULE__{type: :string_input, device: pid} when is_pid(pid) ->
        read_line_from_pid(pid, eof_error_p, eof_value)

      %__MODULE__{device: pid} when is_pid(pid) ->
        read_line_from_pid(pid, eof_error_p, eof_value)

      pid when is_pid(pid) ->
        read_line_from_pid(pid, eof_error_p, eof_value)

      %__MODULE__{} ->
        read_line_generic(s, eof_error_p, eof_value)

      _ ->
        case IO.read(:stdio, :line) do
          :eof ->
            res = handle_eof(eof_error_p, eof_value)
            [:_values_, [res, :t]]

          line when is_binary(line) ->
            if String.ends_with?(line, "\n") do
              trimmed = String.trim_trailing(line, "\n") |> String.trim_trailing("\r")
              [:_values_, [trimmed, nil]]
            else
              [:_values_, [line, :t]]
            end
        end
    end
  end

  defp read_line_generic(s, eof_error_p, eof_value) do
    case read_char(s, nil, :eof) do
      :eof ->
        res = handle_eof(eof_error_p, eof_value)
        [:_values_, [res, :t]]

      c when is_integer(c) ->
        collect_line_chars(s, [c])
    end
  end

  defp collect_line_chars(s, acc) do
    if hd(acc) == ?\n do
      line = acc |> tl() |> Enum.reverse() |> List.to_string() |> String.trim_trailing("\r")
      [:_values_, [line, nil]]
    else
      case read_char(s, nil, :eof) do
        :eof ->
          line = acc |> Enum.reverse() |> List.to_string()
          [:_values_, [line, :t]]

        ?\n ->
          line = acc |> Enum.reverse() |> List.to_string() |> String.trim_trailing("\r")
          [:_values_, [line, nil]]

        c when is_integer(c) ->
          collect_line_chars(s, [c | acc])
      end
    end
  end

  defp read_line_from_pid(pid, eof_error_p, eof_value) do
    case IO.read(pid, :line) do
      :eof ->
        res = handle_eof(eof_error_p, eof_value)
        [:_values_, [res, :t]]

      {:error, _} ->
        res = handle_eof(eof_error_p, eof_value)
        [:_values_, [res, :t]]

      line when is_binary(line) ->
        if String.ends_with?(line, "\n") do
          trimmed = String.trim_trailing(line, "\n") |> String.trim_trailing("\r")
          [:_values_, [trimmed, nil]]
        else
          [:_values_, [line, :t]]
        end
    end
  end

  @doc """
  Reads elements into sequence. Returns the end index.
  """
  def read_sequence(sequence, stream, opts \\ []) do
    opt_list = if is_list(opts), do: opts, else: [opts]
    parsed_opts = ExLisp.Builtins.parse_lisp_keywords(opt_list)
    start_idx = Keyword.get(parsed_opts, :start, 0) || 0
    end_idx = Keyword.get(parsed_opts, :end, nil)

    total_len =
      case sequence do
        list when is_list(list) -> length(list)
        {:array, [d], _} -> d
        bin when is_binary(bin) -> String.length(bin)
        _ -> 0
      end

    actual_end = if is_integer(end_idx), do: min(end_idx, total_len), else: total_len
    count_to_read = max(0, actual_end - start_idx)

    curr_idx =
      Enum.reduce_while(0..(count_to_read - 1)//1, start_idx, fn i, cur ->
        case read_char(stream, nil, :eof) do
          :eof ->
            {:halt, cur}

          c when is_integer(c) ->
            set_sequence_elt(sequence, start_idx + i, c)
            {:cont, cur + 1}
        end
      end)

    curr_idx
  end

  # --- Output Operations ---

  defp unwrap_mv(val) do
    case val do
      [:_values_, [first | _]] -> first
      other -> other
    end
  end

  def write_char(char, stream \\ nil) do
    char = unwrap_mv(char)
    s = resolve_output_stream(stream)
    code = ExLisp.Builtins.char_code(char)
    char_str = <<code::utf8>>

    do_write_string(s, char_str)
    char
  end

  def write_string(string, stream \\ nil, opts \\ []) do
    string = unwrap_mv(string)

    unless is_binary(string) do
      raise ArgumentError, "The value #{inspect(string)} is not of type STRING"
    end

    s = resolve_output_stream(stream)
    opt_list = if is_list(opts), do: opts, else: [opts]
    parsed_opts = ExLisp.Builtins.parse_lisp_keywords(opt_list)
    start_idx = Keyword.get(parsed_opts, :start, 0) || 0
    end_idx = Keyword.get(parsed_opts, :end, nil)

    sliced =
      if is_integer(end_idx) do
        String.slice(string, start_idx, end_idx - start_idx)
      else
        String.slice(string, start_idx..-1//1)
      end

    do_write_string(s, sliced)
    string
  end

  def write_line(string, stream \\ nil, opts \\ []) do
    string = unwrap_mv(string)

    unless is_binary(string) do
      raise ArgumentError, "The value #{inspect(string)} is not of type STRING"
    end

    s = resolve_output_stream(stream)
    write_string(string, s, opts)
    write_char(?\n, s)
    string
  end

  def write_sequence(sequence, stream, opts \\ []) do
    s = resolve_output_stream(stream)
    opt_list = if is_list(opts), do: opts, else: [opts]
    parsed_opts = ExLisp.Builtins.parse_lisp_keywords(opt_list)
    start_idx = Keyword.get(parsed_opts, :start, 0) || 0
    end_idx = Keyword.get(parsed_opts, :end, nil)

    elements =
      cond do
        is_list(sequence) -> sequence
        match?({:array, [_], _}, sequence) ->
          for i <- 0..(ExLisp.Builtins.length(sequence) - 1), do: ExLisp.Builtins.aref(sequence, i)
        is_binary(sequence) -> String.to_charlist(sequence)
        true -> []
      end

    total_len = length(elements)
    actual_end = if is_integer(end_idx), do: min(end_idx, total_len), else: total_len
    sub_elements = Enum.slice(elements, start_idx, max(0, actual_end - start_idx))

    Enum.each(sub_elements, fn elem ->
      if is_integer(elem) do
        write_char(elem, s)
      else
        write_string(ExLisp.Builtins.to_string_val(elem), s)
      end
    end)

    sequence
  end

  def terpri(stream \\ nil) do
    s = resolve_output_stream(stream)
    do_write_string(s, "\n")
    nil
  end

  def fresh_line(stream \\ nil) do
    s = resolve_output_stream(stream)
    at_newline = Process.get({:exlisp_stream_at_newline, stream_id(s)}, true)

    if at_newline do
      nil
    else
      do_write_string(s, "\n")
      :t
    end
  end

  def finish_output(_stream \\ nil), do: nil
  def force_output(_stream \\ nil), do: nil
  def clear_output(_stream \\ nil), do: nil
  def listen(_stream \\ nil), do: :t
  def clear_input(_stream \\ nil), do: nil

  # --- Internal Helpers ---

  defp resolve_input_stream(nil), do: resolve_synonym(:":*standard-input*:")
  defp resolve_input_stream(:t), do: resolve_synonym(:":*terminal-io*:")
  defp resolve_input_stream(%__MODULE__{type: :synonym, extra: %{symbol: sym}}), do: resolve_synonym(sym)
  defp resolve_input_stream(stream), do: stream

  defp resolve_output_stream(nil), do: resolve_synonym(:":*standard-output*:")
  defp resolve_output_stream(:t), do: resolve_synonym(:":*terminal-io*:")
  defp resolve_output_stream(%__MODULE__{type: :synonym, extra: %{symbol: sym}}), do: resolve_synonym(sym)
  defp resolve_output_stream(stream), do: stream

  defp resolve_synonym(sym) do
    norm_sym =
      cond do
        is_atom(sym) -> sym
        is_binary(sym) -> String.to_atom(sym)
        match?(%ExLisp.Symbol{}, sym) -> String.to_atom(sym.name)
        true -> :":*standard-input*:"
      end

    try do
      case ExLisp.Env.get_var(norm_sym) do
        nil -> :stdio
        val -> val
      end
    rescue
      _ -> :stdio
    end
  end

  defp do_write_string(s, str) do
    if is_binary(str) and byte_size(str) > 0 do
      Process.put({:exlisp_stream_at_newline, stream_id(s)}, String.ends_with?(str, "\n"))
    end

    case s do
      %__MODULE__{type: :broadcast, extra: %{streams: streams}} ->
        Enum.each(streams, fn child -> do_write_string(child, str) end)

      %__MODULE__{type: :two_way, extra: %{output: out_s}} ->
        do_write_string(out_s, str)

      %__MODULE__{device: pid} when is_pid(pid) ->
        IO.write(pid, str)

      pid when is_pid(pid) ->
        IO.write(pid, str)

      _ ->
        IO.write(str)
    end
  end

  defp handle_eof(:t, _eof_val), do: raise("End of file on stream")
  defp handle_eof(nil, eof_val), do: eof_val
  defp handle_eof(false, eof_val), do: eof_val
  defp handle_eof(_, eof_val), do: eof_val

  defp stream_id(%__MODULE__{id: id}) when id != nil, do: id
  defp stream_id(pid) when is_pid(pid), do: pid
  defp stream_id(other), do: other

  defp set_sequence_elt(list, index, val) when is_list(list) do
    List.replace_at(list, index, val)
  end

  defp set_sequence_elt({:array, _, _} = arr, index, val) do
    ExLisp.Builtins.set_aref(arr, index, val)
  end

  defp set_sequence_elt(_seq, _index, _val), do: :ok

  defp lisp_bool(true), do: :t
  defp lisp_bool(false), do: nil
  defp lisp_bool(val) when val in [nil, false, []], do: nil
  defp lisp_bool(_), do: :t
end
