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
  - read-char, read-char-no-hang, read-byte, unread-char, peek-char, read-line, read-sequence
  - write-char, write-byte, write-string, write-line, write-sequence
  - terpri, fresh_line, finish-output, force-output, clear-output, listen, clear-input
  - file-string-length, stream-external-format
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
          type:
            :file
            | :string_input
            | :string_output
            | :broadcast
            | :concatenated
            | :two_way
            | :echo
            | :synonym
            | :standard,
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

  def open_stream_p(%__MODULE__{open: open, device: device}) when is_pid(device) do
    ExLisp.Builtins.lisp_bool(open and Process.alive?(device))
  end

  def open_stream_p(%__MODULE__{id: id, open: open}) do
    ExLisp.Builtins.lisp_bool(Process.get({:exlisp_stream_open, id}, open))
  end
  def open_stream_p(pid) when is_pid(pid), do: ExLisp.Builtins.lisp_bool(Process.alive?(pid))
  def open_stream_p(:standard_io), do: :t
  def open_stream_p([s]), do: open_stream_p(s)
  def open_stream_p(_), do: nil

  def input_stream_p(%__MODULE__{type: :synonym, extra: %{symbol: sym}}) do
    target = resolve_synonym(sym)
    input_stream_p(target)
  end

  def input_stream_p(%__MODULE__{mode: mode, open: true}) when mode in [:input, :io], do: :t

  def input_stream_p(pid) when is_pid(pid), do: :t
  def input_stream_p(:standard_io), do: :t
  def input_stream_p([s]), do: input_stream_p(s)
  def input_stream_p(_), do: nil

  def output_stream_p(%__MODULE__{type: :synonym, extra: %{symbol: sym}}) do
    target = resolve_synonym(sym)
    output_stream_p(target)
  end

  def output_stream_p(%__MODULE__{mode: mode, open: true}) when mode in [:output, :io], do: :t

  def output_stream_p(pid) when is_pid(pid), do: :t
  def output_stream_p(:standard_io), do: :t
  def output_stream_p([s]), do: output_stream_p(s)
  def output_stream_p(_), do: nil

  def interactive_stream_p(%__MODULE__{type: :standard}), do: :t
  def interactive_stream_p(:standard_io), do: :t
  def interactive_stream_p([s]), do: interactive_stream_p(s)
  def interactive_stream_p(_), do: nil

  def stream_element_type(%__MODULE__{type: type, extra: %{input: input}})
      when type in [:two_way, :echo],
      do: stream_element_type(input)

  def stream_element_type(%__MODULE__{
        id: id,
        type: :concatenated,
        extra: %{streams: streams}
      }) do
    active = Process.get({:exlisp_concatenated_streams, id}, streams)

    case active do
      [head | _] -> stream_element_type(head)
      [] -> :character
    end
  end

  def stream_element_type(%__MODULE__{element_type: etype}), do: etype
  def stream_element_type([s]), do: stream_element_type(s)
  def stream_element_type(_), do: :character

  # --- Closing Streams ---

  def close(stream, opts \\ [])
  def close(%__MODULE__{type: :synonym} = s, _opts), do: s

  def close(
        %__MODULE__{id: id, type: type},
        _opts
      )
      when type in [:broadcast, :concatenated, :two_way, :echo] do
    Process.put({:exlisp_stream_open, id}, false)
    :t
  end

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
      extra: %{string: sliced, start: s}
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

  def broadcast_stream_streams(%__MODULE__{type: :broadcast, extra: %{streams: streams}}),
    do: streams

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

  def concatenated_stream_streams(%__MODULE__{
        id: id,
        type: :concatenated,
        extra: %{streams: streams}
      }) do
    Process.get({:exlisp_concatenated_streams, id}, streams)
  end

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

  def two_way_stream_output_stream(%__MODULE__{type: :two_way, extra: %{output: out_s}}),
    do: out_s

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
    external_format = Keyword.get(parsed_opts, :external_format, :default)
    if_exists = Keyword.get(parsed_opts, :if_exists, if(direction == :input, do: nil, else: :error))
    if_does_not_exist =
      Keyword.get(
        parsed_opts,
        :if_does_not_exist,
        case direction do
          :input -> :error
          :probe -> nil
          _ -> :create
        end
      )
    file_exists = File.exists?(path_str)

    if direction == :probe do
      cond do
        file_exists ->
          %__MODULE__{
            id: System.unique_integer([:positive, :monotonic]),
            type: :file,
            device: nil,
            mode: :probe,
            element_type: element_type,
            open: false,
            extra: %{path: path_str, external_format: external_format}
          }

        if_does_not_exist == :create ->
          File.touch!(path_str)

          %__MODULE__{
            id: System.unique_integer([:positive, :monotonic]),
            type: :file,
            device: nil,
            mode: :probe,
            element_type: element_type,
            open: false,
            extra: %{path: path_str, external_format: external_format}
          }

        true ->
          nil
      end
    else
      cond do
        file_exists and direction != :input and if_exists == :error ->
          raise "File already exists: #{path_str}"

        file_exists and direction != :input and if_exists == nil ->
          nil

        not file_exists and if_does_not_exist == nil ->
          nil

        not file_exists and if_does_not_exist == :error ->
          raise "File does not exist: #{path_str}"

        true ->
          if not file_exists, do: File.touch!(path_str)

          if direction in [:output, :io] and
               if_exists in [:supersede, :new_version, :rename, :rename_and_delete] do
            File.write!(path_str, "")
          end

          modes =
            case {direction, if_exists} do
              {:input, _} ->
                [:read, :binary]

              {:output, :append} ->
                [:append, :binary]

              {:output, :overwrite} ->
                [:read, :write, :binary]

              {:output, _} ->
                [:write, :binary]

              {:io, :append} ->
                [:append, :read, :binary]

              {:io, if_existing}
              when if_existing in [:supersede, :new_version, :rename, :rename_and_delete] ->
                [:write, :read, :binary]

              {:io, :overwrite} ->
                [:read, :write, :binary]

              {:io, _} ->
                [:read, :write, :binary]

              _ ->
                [:read, :binary]
            end

          case File.open(path_str, modes) do
            {:ok, pid} ->
              build_file_stream(pid, path_str, direction, element_type, external_format)

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

  defp build_file_stream(pid, path_str, direction, element_type, external_format) do
    register_file_element_type(path_str, element_type)
    if direction == :output, do: register_file_element_count(path_str, 0)

    %__MODULE__{
      id: System.unique_integer([:positive, :monotonic]),
      type: :file,
      device: pid,
      mode: direction,
      element_type: element_type,
      open: true,
      extra: %{path: path_str, external_format: external_format}
    }
  end

  def file_length(%__MODULE__{extra: %{path: path}}) when is_binary(path) do
    case lookup_file_element_count(path) do
      {:ok, count} ->
        count

      :error ->
    case File.stat(path) do
      {:ok, %{size: size}} ->
        unit = element_type_width(resolve_file_element_type(path))
        div(size, unit)

      _ -> nil
    end
    end
  end

  def file_length(%__MODULE__{type: :synonym, extra: %{symbol: symbol}}),
    do: file_length(resolve_synonym(symbol))

  def file_length(%__MODULE__{type: :broadcast, extra: %{streams: []}}), do: 0

  def file_length(%__MODULE__{type: :broadcast, extra: %{streams: streams}}) do
    file_length(List.last(streams))
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

  @doc "Returns the number of file-position units occupied by `string` on `stream`."
  def file_string_length(stream, string, opts \\ []) do
    if match?(%__MODULE__{type: :broadcast, extra: %{streams: []}}, stream) do
      1
    else
    text = if is_binary(string), do: string, else: ExLisp.Builtins.to_string_val(string)
    opt_list = if is_list(opts), do: opts, else: [opts]
    parsed_opts = ExLisp.Builtins.parse_lisp_keywords(opt_list)
    start_idx = Keyword.get(parsed_opts, :start, 0) || 0
    end_idx = Keyword.get(parsed_opts, :end, nil)

    slice =
      if is_integer(end_idx),
        do: String.slice(text, start_idx, end_idx - start_idx),
        else: String.slice(text, start_idx..-1//1)

    case stream_external_format(stream) do
      format when format in [:utf_8, :"utf-8", :default, :utf8] -> byte_size(slice)
      _ -> byte_size(slice)
    end
    end
  end

  @doc "Returns the external format associated with a stream."
  def stream_external_format(stream \\ nil) do
    case resolve_stream(stream) do
      %__MODULE__{extra: %{external_format: format}} ->
        normalize_external_format(format)

      %__MODULE__{type: :string_input} ->
        :utf_8

      %__MODULE__{type: :string_output} ->
        :utf_8

      %__MODULE__{type: :two_way, extra: %{output: output}} ->
        stream_external_format(output)

      %__MODULE__{type: :echo, extra: %{input: input}} ->
        stream_external_format(input)

      %__MODULE__{type: :broadcast, extra: %{streams: streams}} ->
        case streams do
          [] -> :default
          _ -> Enum.map(streams, &stream_external_format/1) |> normalize_external_format()
        end

      _ ->
        :utf_8
    end
  end

  def file_position(stream, pos_spec \\ nil)

  def file_position(
        %__MODULE__{type: :broadcast, extra: %{streams: []}},
        pos_spec
      ) do
    if is_nil(pos_spec), do: 0, else: nil
  end

  def file_position(
        %__MODULE__{type: :broadcast, extra: %{streams: streams}},
        pos_spec
      ) do
    file_position(List.last(streams), pos_spec)
  end

  def file_position(%__MODULE__{type: :file, device: dev} = stream, pos_spec) do
    case pos_spec do
      nil ->
        case :file.position(dev, :cur) do
          {:ok, pos} -> div(pos, element_type_width(stream.element_type))
          _ -> 0
        end

      :start ->
        case :file.position(dev, :bof) do
          {:ok, _pos} -> :t
          _ -> nil
        end

      :end ->
        case :file.position(dev, :eof) do
          {:ok, _pos} -> :t
          _ -> nil
        end

      offset when is_integer(offset) ->
        case :file.position(dev, {:bof, offset * element_type_width(stream.element_type)}) do
          {:ok, _pos} -> :t
          _ -> nil
        end
    end
  end

  def file_position(%__MODULE__{id: id, type: type}, nil)
      when type in [:string_output, :broadcast] do
    Process.get({:exlisp_stream_position, id}, 0)
  end

  def file_position(
        %__MODULE__{id: id, type: :string_input, device: pid, extra: %{string: string} = extra},
        nil
      ) do
    remaining =
      case StringIO.contents(pid) do
        {input, _output} -> String.length(input)
      end

    start = Map.get(extra, :start, 0)
    unread = Process.get({:exlisp_stream_unread, id}, [])
    start + String.length(string) - remaining - length(unread)
  end

  def file_position(%__MODULE__{}, nil), do: 0
  def file_position(%__MODULE__{}, _pos_spec), do: nil

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

    raw_res =
      case s do
        %__MODULE__{type: :concatenated, extra: %{streams: []}} ->
          handle_eof(eof_error_p, eof_value)

        %__MODULE__{id: id, type: :concatenated, extra: %{streams: initial_streams}} =
            concat_s ->
          streams = Process.get({:exlisp_concatenated_streams, id}, initial_streams)
          unread_key = {:exlisp_stream_unread, id}

          case Process.get(unread_key, []) do
            [char | rest] ->
              Process.put(unread_key, rest)
              char

            [] ->
              case streams do
                [] ->
                  handle_eof(eof_error_p, eof_value)

                [head_s | tail_s] ->
                  case read_char(head_s, nil, :eof) do
                    :eof ->
                      Process.put({:exlisp_concatenated_streams, id}, tail_s)
                      read_char(%{concat_s | extra: %{streams: tail_s}}, eof_error_p, eof_value)

                    c ->
                      c
                  end
              end
          end

        %__MODULE__{type: :echo, extra: %{input: in_s, output: out_s}} ->
          input_unread = Process.get({:exlisp_stream_unread, stream_id(in_s)}, []) != []

          case read_char(in_s, nil, :eof) do
            :eof ->
              handle_eof(eof_error_p, eof_value)

            %ExLisp.Character{} = c ->
              unless input_unread, do: write_char(c, out_s)
              c

            c when is_integer(c) ->
              unless input_unread, do: write_char(c, out_s)
              ExLisp.Character.new(c)

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

    case raw_res do
      %ExLisp.Character{} = c -> c
      c when is_integer(c) -> ExLisp.Character.new(c)
      other -> other
    end
  end

  @doc """
  Reads and returns a character if input is immediately available.

  Interactive terminal input that is not already buffered is not polled, avoiding
  an accidental blocking read.
  """
  def read_char_no_hang(
        stream \\ nil,
        eof_error_p \\ :t,
        eof_value \\ nil,
        recursive_p \\ nil
      ) do
    s = resolve_input_stream(stream)

    case s do
      %__MODULE__{id: id, type: :concatenated, extra: %{streams: initial_streams}} =
          concat ->
        streams = Process.get({:exlisp_concatenated_streams, id}, initial_streams)

        case Process.get({:exlisp_stream_unread, id}, []) do
          [char | rest] ->
            Process.put({:exlisp_stream_unread, id}, rest)
            char

          [] ->
            case streams do
              [] ->
                handle_eof(eof_error_p, eof_value)

              [head | tail] ->
                case read_char_no_hang(head, nil, :eof) do
                  :eof ->
                    Process.put({:exlisp_concatenated_streams, id}, tail)

                    read_char_no_hang(
                      %{concat | extra: %{streams: tail}},
                      eof_error_p,
                      eof_value
                    )

                  value ->
                    value
                end
            end
        end

      %__MODULE__{type: :two_way, extra: %{input: input}} ->
        read_char_no_hang(input, eof_error_p, eof_value, recursive_p)

      %__MODULE__{type: :echo, extra: %{input: input, output: output}} ->
        case read_char_no_hang(input, nil, :eof, recursive_p) do
          :eof ->
            handle_eof(eof_error_p, eof_value)

          %ExLisp.Character{} = char ->
            write_char(char, output)
            char

          other ->
            other
        end

      %__MODULE__{type: :string_input} ->
        read_char(s, eof_error_p, eof_value, recursive_p)

      %__MODULE__{type: :file, device: pid} when is_pid(pid) ->
        if immediately_available?(s),
          do: read_char(s, eof_error_p, eof_value, recursive_p),
          else: nil

      pid when pid == :stdio ->
        nil

      _ when s == :stdio ->
        nil

      pid when is_pid(pid) ->
        if Process.alive?(pid),
          do: read_char(s, eof_error_p, eof_value, recursive_p),
          else: nil

      _ ->
        nil
    end
  end

  @doc "Reads one octet from a binary stream."
  def read_byte(stream \\ nil, eof_error_p \\ :t, eof_value \\ nil) do
    s = resolve_input_stream(stream)

    case s do
      %__MODULE__{type: :concatenated, extra: %{streams: []}} ->
        handle_eof(eof_error_p, eof_value)

      %__MODULE__{type: :concatenated, extra: %{streams: [head | tail]}} = concat ->
        case read_byte(head, nil, :eof) do
          :eof -> read_byte(%{concat | extra: %{streams: tail}}, eof_error_p, eof_value)
          byte -> byte
        end

      %__MODULE__{type: :two_way, extra: %{input: input}} ->
        read_byte(input, eof_error_p, eof_value)

      %__MODULE__{type: :echo, extra: %{input: input, output: output}} ->
        case read_byte(input, nil, :eof) do
          :eof ->
            handle_eof(eof_error_p, eof_value)

          byte when is_integer(byte) ->
            write_byte(byte, output)
            byte

          other ->
            other
        end

      %__MODULE__{device: pid} when is_pid(pid) ->
        read_byte_from_pid(pid, s, eof_error_p, eof_value)

      pid when is_pid(pid) ->
        read_byte_from_pid(pid, pid, eof_error_p, eof_value)

      :stdio ->
        read_byte_from_pid(:stdio, :stdio, eof_error_p, eof_value)

      _ ->
        handle_eof(eof_error_p, eof_value)
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

  defp read_byte_from_pid(pid, s_ref, eof_error_p, eof_value) do
    key = {:exlisp_stream_unread_byte, stream_id(s_ref)}
    width = element_type_width(stream_element_type(s_ref))

    case Process.get(key, []) do
      [byte | rest] ->
        Process.put(key, rest)
        byte

      [] ->
        result =
          try do
            IO.binread(pid, width)
          rescue
            _ -> {:error, :not_binary_io}
          catch
            _, _ -> {:error, :not_binary_io}
          end

        case result do
          bytes when is_binary(bytes) and byte_size(bytes) == width ->
            :binary.decode_unsigned(bytes)
          :eof -> handle_eof(eof_error_p, eof_value)
          {:error, _} -> handle_eof(eof_error_p, eof_value)
          _ -> handle_eof(eof_error_p, eof_value)
        end
    end
  end

  @doc """
  Pushes character back to input stream.
  """
  def unread_char(char, stream \\ nil) do
    s =
      case resolve_input_stream(stream) do
        %__MODULE__{type: type, extra: %{input: input}} when type in [:echo, :two_way] ->
          input

        resolved ->
          resolved
      end
    code = ExLisp.Builtins.char_code(char)
    key = {:exlisp_stream_unread, stream_id(s)}
    existing = Process.get(key, [])
    Process.put(key, [code | existing])
    nil
  end

  @doc """
  Peeks at next character without consuming it.
  """
  def peek_char(
        peek_type \\ nil,
        stream \\ nil,
        eof_error_p \\ :t,
        eof_value \\ nil,
        _rec \\ nil
      ) do
        resolved = resolve_input_stream(stream)

        s =
          case {peek_type, resolved} do
            {nil, %__MODULE__{type: :echo, extra: %{input: input}}} -> input
            {false, %__MODULE__{type: :echo, extra: %{input: input}}} -> input
            _ -> resolved
          end

    result =
      cond do
        peek_type in [:t, true] ->
          read_until_peek(s, eof_error_p, eof_value, fn character ->
            ExLisp.Readtable.syntax_type(character_code(character)) != :whitespace
          end)

        peek_type in [nil, false] ->
          read_char(s, eof_error_p, eof_value)

        true ->
          target = ExLisp.Builtins.char_code(peek_type)

          read_until_peek(s, eof_error_p, eof_value, fn character ->
            character_code(character) == target
          end)
      end

    case result do
      %ExLisp.Character{} = c ->
        unread_char(c, s)
        c

      c when is_integer(c) ->
        unread_char(c, s)
        ExLisp.Character.new(c)

      other ->
        other
    end
  end

  defp read_until_peek(stream, eof_error_p, eof_value, predicate) do
    case read_char(stream, eof_error_p, eof_value) do
      value when eof_error_p in [nil, false] and value == eof_value ->
        value

      :eof ->
        :eof

      character ->
        if predicate.(character), do: character, else: read_until_peek(stream, eof_error_p, eof_value, predicate)
    end
  end

  defp character_code(%ExLisp.Character{code: code}), do: code
  defp character_code(code) when is_integer(code), do: code

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

      %ExLisp.Character{code: c} ->
        collect_line_chars(s, [c])

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

        %ExLisp.Character{code: ?\n} ->
          line = acc |> Enum.reverse() |> List.to_string() |> String.trim_trailing("\r")
          [:_values_, [line, nil]]

        %ExLisp.Character{code: c} ->
          collect_line_chars(s, [c | acc])

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
        {:array, _, _} -> ExLisp.Builtins.length(sequence)
        bin when is_binary(bin) -> String.length(bin)
        _ -> 0
      end

    actual_end = if is_integer(end_idx), do: min(end_idx, total_len), else: total_len
    count_to_read = max(0, actual_end - start_idx)
    binary_input = binary_element_type?(stream_element_type(resolve_input_stream(stream)))
    indices = if count_to_read > 0, do: 0..(count_to_read - 1), else: []

    curr_idx =
      Enum.reduce_while(indices, start_idx, fn i, cur ->
        reader = if binary_input, do: &read_byte/3, else: &read_char/4
        value = if binary_input, do: reader.(stream, nil, :eof), else: reader.(stream, nil, :eof, nil)

        case value do
          :eof ->
            {:halt, cur}

          %ExLisp.Character{} = character ->
            set_sequence_elt(sequence, start_idx + i, character)
            {:cont, cur + 1}

          c when is_integer(c) ->
            set_sequence_elt(sequence, start_idx + i, c)
            {:cont, cur + 1}
        end
      end)

    curr_idx
  end

  defp binary_element_type?([:unsigned_byte | _]), do: true
  defp binary_element_type?([:signed_byte | _]), do: true
  defp binary_element_type?([:integer | _]), do: true
  defp binary_element_type?([:or | types]), do: Enum.all?(types, &binary_element_type?/1)
  defp binary_element_type?(type) when type in [:bit, :unsigned_byte, :signed_byte], do: true
  defp binary_element_type?(_), do: false

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

  @doc "Writes one octet to a binary stream and returns it."
  def write_byte(byte, stream \\ nil)

  def write_byte(byte, stream) when is_integer(byte) and byte >= 0 do
    s = resolve_output_stream(stream)
    width = element_type_width(stream_element_type(s))
    max_value = Bitwise.bsl(1, width * 8) - 1

    if byte > max_value do
      raise ArgumentError, "BYTE does not fit stream element type"
    end

    encoded = :binary.encode_unsigned(byte)
    do_write_binary(s, :binary.copy(<<0>>, width - byte_size(encoded)) <> encoded)
    increment_file_element_count(s)
    byte
  end

  def write_byte(byte, _stream) do
    raise ArgumentError, "BYTE must be an octet, got: #{inspect(byte)}"
  end

  defp resolve_file_element_type(path) do
    case :ets.whereis(:exlisp_file_element_types) do
      :undefined ->
        :character

      table ->
        case :ets.lookup(table, path) do
          [{^path, element_type}] -> element_type
          [] -> :character
        end
    end
  end

  defp register_file_element_type(path, element_type) do
    table =
      case :ets.whereis(:exlisp_file_element_types) do
        :undefined ->
          try do
            :ets.new(:exlisp_file_element_types, [:named_table, :public, :set])
          rescue
            ArgumentError -> :exlisp_file_element_types
          end

        existing ->
          existing
      end

    :ets.insert(table, {path, element_type})
  end

  defp register_file_element_count(path, count) do
    table =
      case :ets.whereis(:exlisp_file_element_counts) do
        :undefined ->
          try do
            :ets.new(:exlisp_file_element_counts, [:named_table, :public, :set])
          rescue
            ArgumentError -> :exlisp_file_element_counts
          end

        existing ->
          existing
      end

    :ets.insert(table, {path, count})
  end

  defp lookup_file_element_count(path) do
    case :ets.whereis(:exlisp_file_element_counts) do
      :undefined ->
        :error

      table ->
        case :ets.lookup(table, path) do
          [{^path, count}] -> {:ok, count}
          [] -> :error
        end
    end
  end

  defp increment_file_element_count(stream, count \\ 1)

  defp increment_file_element_count(%__MODULE__{extra: %{path: path}}, count) do
    case :ets.whereis(:exlisp_file_element_counts) do
      :undefined -> :ok
      table -> :ets.update_counter(table, path, {2, count}, {path, 0})
    end
  end

  defp increment_file_element_count(%__MODULE__{
         type: :broadcast,
         extra: %{streams: streams}
       }, count),
       do: Enum.each(streams, &increment_file_element_count(&1, count))

  defp increment_file_element_count(_, _), do: :ok

  defp element_type_width([:unsigned_byte, bits]) when is_integer(bits) and bits > 0,
    do: max(div(bits + 7, 8), 1)

  defp element_type_width([:signed_byte, bits]) when is_integer(bits) and bits > 0,
    do: max(div(bits + 7, 8), 1)

  defp element_type_width(_), do: 1

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
        is_list(sequence) ->
          sequence

        match?({:array, [_], _}, sequence) ->
          len = ExLisp.Builtins.length(sequence)
          if len > 0, do: for(i <- 0..(len - 1), do: ExLisp.Builtins.aref(sequence, i)), else: []

        is_binary(sequence) ->
          String.to_charlist(sequence)

        true ->
          []
      end

    total_len = length(elements)
    actual_end = if is_integer(end_idx), do: min(end_idx, total_len), else: total_len
    sub_elements = Enum.slice(elements, start_idx, max(0, actual_end - start_idx))
    binary_output = binary_element_type?(stream_element_type(s))

    Enum.each(sub_elements, fn elem ->
      cond do
        binary_output and is_integer(elem) ->
          write_byte(elem, s)

        is_integer(elem) ->
          write_char(elem, s)

        true ->
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

  def finish_output(stream \\ nil) do
    flush_output(resolve_output_stream(stream), true)
    nil
  end

  def force_output(stream \\ nil) do
    flush_output(resolve_output_stream(stream), false)
    nil
  end

  def clear_output(stream \\ nil) do
    # BEAM IO devices do not expose a portable "discard pending writes" operation.
    # Synchronizing is the safe behavior; no successful output is lost.
    flush_output(resolve_output_stream(stream), false)
    nil
  end

  def listen(stream \\ nil) do
    s = resolve_input_stream(stream)
    key = {:exlisp_stream_unread, stream_id(s)}
    byte_key = {:exlisp_stream_unread_byte, stream_id(s)}

    cond do
      Process.get(key, []) != [] ->
        :t

      Process.get(byte_key, []) != [] ->
        :t

      true ->
        case read_char_no_hang(s, nil, :eof) do
          nil ->
            nil

          :eof ->
            nil

          char ->
            unread_char(char, s)
            :t
        end
    end
  end

  def clear_input(stream \\ nil) do
    s = resolve_input_stream(stream)
    Process.delete({:exlisp_stream_unread, stream_id(s)})
    Process.delete({:exlisp_stream_unread_byte, stream_id(s)})
    clear_buffered_input(s)
    nil
  end

  # --- Internal Helpers ---

  def standard_input_stream do
    Process.get(:exlisp_standard_input_stream) || resolve_input_stream(nil)
  end

  def terminal_io_stream do
    Process.get(:exlisp_terminal_io_stream) || resolve_input_stream(:t)
  end

  defp resolve_input_stream(nil),
    do: Process.get(:exlisp_standard_input_stream) || resolve_synonym(:":*standard-input*:")
  defp resolve_input_stream(:t),
    do: terminal_input_stream(Process.get(:exlisp_terminal_io_stream) || resolve_synonym(:":*terminal-io*:"))

  defp resolve_input_stream(%__MODULE__{type: :synonym, extra: %{symbol: sym}}),
    do: resolve_synonym(sym)

  defp resolve_input_stream(stream), do: stream

  defp resolve_output_stream(nil), do: resolve_synonym(:":*standard-output*:")
  defp resolve_output_stream(:t),
    do: Process.get(:exlisp_terminal_io_stream) || resolve_synonym(:":*terminal-io*:")

  defp resolve_output_stream(%__MODULE__{type: :synonym, extra: %{symbol: sym}}),
    do: resolve_synonym(sym)

  defp resolve_output_stream(%__MODULE__{type: type, extra: %{output: output}})
       when type in [:two_way, :echo],
       do: resolve_output_stream(output)

  defp resolve_output_stream(stream), do: stream

  defp resolve_stream(nil),
    do: Process.get(:exlisp_standard_input_stream) || resolve_synonym(:":*standard-input*:")
  defp resolve_stream(:t),
    do: Process.get(:exlisp_terminal_io_stream) || resolve_synonym(:":*terminal-io*:")

  defp resolve_stream(%__MODULE__{type: :synonym, extra: %{symbol: sym}}),
    do: resolve_synonym(sym)

  defp resolve_stream(stream), do: stream

  defp terminal_input_stream(%__MODULE__{type: type, extra: extra})
       when type in [:two_way, :echo],
       do: Map.fetch!(extra, :input)

  defp terminal_input_stream(stream), do: stream

  def resolve_synonym(sym) do
    norm_sym =
      cond do
        is_atom(sym) ->
          sym |> Atom.to_string() |> String.trim(":") |> String.to_atom()

        is_binary(sym) ->
          sym |> String.trim(":") |> String.to_atom()
        match?(%ExLisp.Symbol{}, sym) -> String.to_atom(sym.name)
        true -> :":*standard-input*:"
      end

    normalized = ExLisp.Env.normalize_name(norm_sym)
    normalized_text = Atom.to_string(normalized)
    process_value =
      Process.get({:exlisp_special_stream, normalized}) ||
        Process.get(
          {:exlisp_special_stream,
           normalized_text |> String.replace("_", "-") |> String.to_atom()}
        )

    case process_value do
      value when not is_nil(value) ->
        value

      nil ->
        resolve_synonym_from_env(norm_sym)
    end
  end

  defp resolve_synonym_from_env(norm_sym) do
    try do
      candidates = [norm_sym, norm_sym |> Atom.to_string() |> String.replace("-", "_") |> String.to_atom()]

      Enum.find_value(candidates, fn candidate ->
        try do
          case ExLisp.Env.get_var(candidate) do
            nil -> false
            val -> {:value, val}
          end
        rescue
          _ -> false
        end
      end)
      |> case do
        {:value, val} -> val
        _ -> :stdio
      end
    rescue
      _ -> :stdio
    end
  end

  defp do_write_string(s, str) do
    if is_binary(str) and byte_size(str) > 0 do
      Process.put({:exlisp_stream_at_newline, stream_id(s)}, String.ends_with?(str, "\n"))
      Process.put(
        {:exlisp_stream_position, stream_id(s)},
        Process.get({:exlisp_stream_position, stream_id(s)}, 0) + String.length(str)
      )
      increment_file_element_count(s, String.length(str))
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

  defp do_write_binary(s, bytes) do
    case s do
      %__MODULE__{type: :broadcast, extra: %{streams: streams}} ->
        Enum.each(streams, &do_write_binary(&1, bytes))

      %__MODULE__{type: :two_way, extra: %{output: output}} ->
        do_write_binary(output, bytes)

      %__MODULE__{device: pid} when is_pid(pid) ->
        IO.binwrite(pid, bytes)

      pid when is_pid(pid) or pid in [:stdio, :stderr] ->
        IO.binwrite(pid, bytes)

      _ ->
        IO.binwrite(bytes)
    end
  end

  defp flush_output(%__MODULE__{type: :broadcast, extra: %{streams: streams}}, synchronous) do
    Enum.each(streams, &flush_output(&1, synchronous))
  end

  defp flush_output(%__MODULE__{type: :two_way, extra: %{output: output}}, synchronous),
    do: flush_output(output, synchronous)

  defp flush_output(%__MODULE__{type: type, device: pid}, synchronous)
       when type not in [:string_input, :string_output] and is_pid(pid) do
    if synchronous, do: sync_file(pid)
    IO.write(pid, "")
  end

  defp flush_output(pid, synchronous) when is_pid(pid) do
    if synchronous, do: sync_file(pid)
    IO.write(pid, "")
  end

  defp flush_output(device, _synchronous) when device in [:stdio, :stderr],
    do: IO.write(device, "")

  defp flush_output(_stream, _synchronous), do: :ok

  defp sync_file(pid) do
    case :file.sync(pid) do
      :ok -> :ok
      _ -> :ok
    end
  rescue
    _ -> :ok
  catch
    _, _ -> :ok
  end

  defp immediately_available?(%__MODULE__{type: :string_input}), do: true

  defp immediately_available?(%__MODULE__{type: :file, device: pid}) when is_pid(pid) do
    case :file.position(pid, :cur) do
      {:ok, pos} ->
        case :file.pread(pid, pos, 1) do
          {:ok, _} -> true
          :eof -> true
          _ -> false
        end

      _ ->
        false
    end
  end

  defp immediately_available?(_), do: false

  defp normalize_external_format(:default), do: :utf_8
  defp normalize_external_format(:utf8), do: :utf_8
  defp normalize_external_format(:"utf-8"), do: :utf_8
  defp normalize_external_format([format]), do: normalize_external_format(format)

  defp normalize_external_format(formats) when is_list(formats),
    do: Enum.map(formats, &normalize_external_format/1)

  defp normalize_external_format(format), do: format

  defp clear_buffered_input(%__MODULE__{type: :string_input, device: pid}) when is_pid(pid) do
    try do
      IO.binread(pid, :eof)
    rescue
      _ -> :ok
    catch
      _, _ -> :ok
    end
  end

  defp clear_buffered_input(%__MODULE__{
         type: type,
         extra: %{input: input}
       })
       when type in [:two_way, :echo],
       do: clear_buffered_input(input)

  defp clear_buffered_input(%__MODULE__{type: :concatenated, extra: %{streams: streams}}),
    do: Enum.each(streams, &clear_buffered_input/1)

  defp clear_buffered_input(_), do: :ok

  defp handle_eof(:t, _eof_val),
    do: ExLisp.Condition.error(:end_of_file, "End of file on stream")
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
end
