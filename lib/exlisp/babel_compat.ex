defmodule ExLisp.BabelCompat do
  @moduledoc false

  def install do
    ExLisp.Package.ensure_tables()
    package = ExLisp.Package.find_package!("BABEL")

    %{
      string_to_octets: &string_to_octets/1,
      octets_to_string: &octets_to_string/1,
      string_size_in_octets: &string_size_in_octets/1,
      vector_size_in_chars: &vector_size_in_chars/1,
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
      |> :unicode.characters_to_binary()

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

    values
    |> Enum.slice(start, finish - start)
    |> :erlang.list_to_binary()
    |> :unicode.characters_to_binary(:utf8)
  end

  def string_size_in_octets([string | opts]) do
    string |> ExLisp.Builtins.to_string_val() |> substring(opts) |> byte_size()
  end

  def vector_size_in_chars([octets | opts]) do
    octets
    |> ExLisp.Builtins.seq_to_list()
    |> :erlang.list_to_binary()
    |> :unicode.characters_to_binary(:utf8)
    |> substring(opts)
    |> String.length()
  end

  defp substring(string, opts) do
    options = options(opts)
    start = Keyword.get(options, :start, 0) || 0
    finish = Keyword.get(options, :end, String.length(string))
    String.slice(string, start, finish - start)
  end

  defp options(opts) do
    ExLisp.Builtins.parse_lisp_keywords(opts)
  rescue
    _ -> []
  end
end
