defmodule ExLisp.IroncladCompat do
  @moduledoc false

  def install do
    ExLisp.Package.ensure_tables()
    package = ExLisp.Package.find_package!("IRONCLAD")

    %{
      random_data: &random_data/1,
      byte_array_to_hex_string: &byte_array_to_hex_string/1,
      hex_string_to_byte_array: &hex_string_to_byte_array/1,
      digest_sequence: &digest_sequence/1,
      digest_file: &digest_file/1,
      make_digest: &make_digest/1
    }
    |> Enum.each(fn {name, function} ->
      closure = ExLisp.Closure.new(function, name, package: package.name)

      for package_name <- [package.name | package.nicknames],
          separator <- [".", ":"] do
        ExLisp.Env.put_fun(:"#{String.downcase(package_name)}#{separator}#{name}", closure)
      end
    end)

    :t
  end

  def random_data([size]), do: make_bytes(:crypto.strong_rand_bytes(size))

  def byte_array_to_hex_string([array]), do: array |> to_binary() |> Base.encode16(case: :lower)

  def hex_string_to_byte_array([hex]),
    do: hex |> to_string() |> Base.decode16!(case: :mixed) |> make_bytes()

  def digest_sequence([algorithm, data | _opts]) do
    :crypto.hash(hash_name(algorithm), to_binary(data)) |> make_bytes()
  end

  def digest_file([algorithm, path | _opts]) do
    :crypto.hash(hash_name(algorithm), File.read!(ExLisp.Builtins.to_string_val(path)))
    |> make_bytes()
  end

  def make_digest([algorithm]),
    do: {:ironclad_digest, hash_name(algorithm), :crypto.hash_init(hash_name(algorithm))}

  defp hash_name(name) do
    case name |> ExLisp.Builtins.to_string_val() |> String.downcase() do
      "sha1" -> :sha
      "sha-1" -> :sha
      "sha224" -> :sha224
      "sha256" -> :sha256
      "sha384" -> :sha384
      "sha512" -> :sha512
      "md5" -> :md5
      other -> String.to_atom(other)
    end
  end

  defp to_binary(%ExLisp.Symbol{name: value}), do: to_binary(value)
  defp to_binary(value) when is_binary(value), do: value
  defp to_binary(value), do: value |> ExLisp.Builtins.seq_to_list() |> :erlang.list_to_binary()

  defp make_bytes(binary) do
    bytes = :binary.bin_to_list(binary)

    ExLisp.Builtins.make_array([
      length(bytes),
      :element_type,
      [:unsigned_byte, 8],
      :initial_contents,
      bytes
    ])
  end
end
