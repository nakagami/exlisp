defmodule ExLisp.BabelCompat do
  @moduledoc false

  def install do
    ExLisp.Package.ensure_tables()
    package = ExLisp.Package.find_package!("BABEL")

    %{
      string_to_octets: &string_to_octets/1,
      octets_to_string: &octets_to_string/1,
      concatenate_strings_to_octets: &concatenate_strings_to_octets/1,
      string_size_in_octets: &string_size_in_octets/1,
      vector_size_in_chars: &vector_size_in_chars/1,
      encodable_character_p: &encodable_character_p/1,
      encodable_string_p: &encodable_string_p/1,
      list_character_encodings: fn _args -> [:utf_8, :ascii, :latin_1] end
    }
    |> Enum.each(fn {name, function} ->
      closure = ExLisp.Closure.new(function, name, package: package.name)

      for package_name <- [package.name, "BABEL"],
          prefix <- [
            String.downcase(package_name),
            String.replace(String.downcase(package_name), "_", "-")
          ],
          separator <- [".", ":"] do
        ExLisp.Env.put_fun(:"#{prefix}#{separator}#{name}", closure)
      end
    end)

    ExLisp.Env.put_var(:"*default-character-encoding*", :utf_8)
    ExLisp.Env.put_var(:"babel-encodings.*default-character-encoding*", :utf_8)
    :t
  end

  def string_to_octets([string | opts]) do
    options = options(opts)
    start = Keyword.get(options, :start, 0) || 0
    finish = Keyword.get(options, :end, String.length(string))

    data =
      string
      |> ExLisp.Builtins.to_string_val()
      |> String.slice(start, finish - start)
      |> encode(Keyword.get(options, :encoding, :utf_8))

    bytes = :binary.bin_to_list(data)

    ExLisp.Builtins.make_array([
      length(bytes),
      :element_type,
      [:unsigned_byte, 8],
      :initial_contents,
      bytes
    ])
  end

  def octets_to_string([octets | opts]) do
    options = options(opts)
    values = ExLisp.Builtins.seq_to_list(octets)
    start = Keyword.get(options, :start, 0) || 0
    finish = Keyword.get(options, :end, length(values))

    binary =
      values
      |> Enum.slice(start, finish - start)
      |> :erlang.list_to_binary()

    decode(binary, encoding(opts))
  end

  def concatenate_strings_to_octets(args) do
    {strings, opts} = pop_options(args)
    options = options(opts)
    encoding = Keyword.get(options, :encoding, :utf_8)

    strings
    |> Enum.map(&encode(&1 |> ExLisp.Builtins.to_string_val(), encoding))
    |> IO.iodata_to_binary()
    |> then(&:binary.bin_to_list/1)
    |> make_octet_vector()
  end

  def string_size_in_octets([string | opts]) do
    string
    |> ExLisp.Builtins.to_string_val()
    |> substring(opts)
    |> encode(encoding(opts))
    |> byte_size()
  end

  def vector_size_in_chars([octets | opts]) do
    octets
    |> ExLisp.Builtins.seq_to_list()
    |> :erlang.list_to_binary()
    |> decode(encoding(opts))
    |> substring(opts)
    |> String.length()
  end

  def encodable_character_p([character | opts]) do
    character
    |> ExLisp.Builtins.char_code()
    |> then(&<<&1::utf8>>)
    |> encode(encoding(opts))
    |> then(fn _ -> :t end)
  rescue
    _ -> nil
  end

  def encodable_string_p([string | opts]) do
    string |> ExLisp.Builtins.to_string_val() |> encode(encoding(opts))
    :t
  rescue
    _ -> nil
  end

  defp substring(string, opts) do
    options = options(opts)
    start = Keyword.get(options, :start, 0) || 0
    finish = Keyword.get(options, :end, String.length(string))
    String.slice(string, start, finish - start)
  end

  defp encoding(opts), do: opts |> options() |> Keyword.get(:encoding, :utf_8)

  defp encode(string, encoding) do
    case encoding_name(encoding) do
      :utf_8 -> :unicode.characters_to_binary(string, :utf8)
      :ascii -> encode_one_byte(string, 127)
      :latin_1 -> encode_one_byte(string, 255)
      other -> raise ArgumentError, "unsupported character encoding: #{other}"
    end
  end

  defp encode_one_byte(string, maximum) do
    string
    |> String.to_charlist()
    |> Enum.map(fn
      code when code <= maximum -> code
      code -> raise ArgumentError, "character code #{code} is not encodable"
    end)
    |> :erlang.list_to_binary()
  end

  defp encoding_name(encoding) do
    encoding
    |> ExLisp.Builtins.to_string_val()
    |> String.downcase()
    |> String.replace(["-", ":"], "_")
    |> String.to_atom()
  end

  defp pop_options(args) do
    case Enum.find_index(args, fn value -> value in [:encoding, :start, :end] end) do
      nil -> {args, []}
      index -> Enum.split(args, index)
    end
  end

  defp decode(binary, encoding) do
    case encoding_name(encoding) do
      :utf_8 -> :unicode.characters_to_binary(binary, :utf8)
      :ascii -> binary |> :binary.bin_to_list() |> ensure_bytes_max(127) |> List.to_string()
      :latin_1 -> binary |> :binary.bin_to_list() |> ensure_bytes_max(255) |> List.to_string()
      other -> raise ArgumentError, "unsupported character encoding: #{other}"
    end
  end

  defp ensure_bytes_max(bytes, maximum) do
    if Enum.any?(bytes, &(&1 > maximum)) do
      raise ArgumentError, "byte sequence is not valid for this encoding"
    else
      bytes
    end
  end

  defp make_octet_vector(bytes) do
    ExLisp.Builtins.make_array([
      length(bytes),
      :element_type,
      [:unsigned_byte, 8],
      :initial_contents,
      bytes
    ])
  end

  defp options(opts) do
    ExLisp.Builtins.parse_lisp_keywords(opts)
  rescue
    _ -> []
  end
end
