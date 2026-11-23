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
      make_digest: &make_digest/1,
      copy_digest: &copy_digest/1,
      update_digest: &update_digest/1,
      produce_digest: &produce_digest/1,
      digest_supported_p: &digest_supported_p/1,
      list_all_digests: &list_all_digests/1,
      digest_length: &digest_length/1,
      integer_to_octets: &integer_to_octets/1,
      octets_to_integer: &octets_to_integer/1,
      random_bits: &random_bits/1,
      make_hmac: &make_hmac/1,
      update_hmac: &update_hmac/1,
      hmac_digest: &hmac_digest/1,
      pbkdf2_hash_password: &pbkdf2_hash_password/1
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

  def digest_sequence([algorithm, data | opts]) do
    bytes = to_binary(data)
    options = ExLisp.Builtins.parse_lisp_keywords(opts)
    start = Keyword.get(options, :start, 0) || 0
    finish = Keyword.get(options, :end, byte_size(bytes)) || byte_size(bytes)
    :crypto.hash(hash_name(algorithm), binary_part(bytes, start, finish - start)) |> make_bytes()
  end

  def digest_file([algorithm, path | _opts]) do
    :crypto.hash(hash_name(algorithm), File.read!(ExLisp.Builtins.to_string_val(path)))
    |> make_bytes()
  end

  def make_digest([algorithm]),
    do: {:ironclad_digest, hash_name(algorithm), :crypto.hash_init(hash_name(algorithm))}

  def copy_digest([{:ironclad_digest, algorithm, context}]),
    do: {:ironclad_digest, algorithm, context}

  def update_digest([{:ironclad_digest, algorithm, context}, data | opts]) do
    options = ExLisp.Builtins.parse_lisp_keywords(opts)
    bytes = to_binary(data)
    start = Keyword.get(options, :start, 0) || 0
    finish = Keyword.get(options, :end, byte_size(bytes)) || byte_size(bytes)

    {:ironclad_digest, algorithm,
     :crypto.hash_update(context, binary_part(bytes, start, finish - start))}
  end

  def produce_digest([{:ironclad_digest, _algorithm, context}]),
    do: :crypto.hash_final(context) |> make_bytes()

  def produce_digest([{:ironclad_digest, _algorithm, context}, :digest]),
    do: :crypto.hash_final(context) |> make_bytes()

  def digest_supported_p([algorithm]) do
    ExLisp.Builtins.lisp_bool(hash_name(algorithm) in :crypto.supports()[:hashs])
  rescue
    _ -> nil
  end

  def list_all_digests(_args \\ []) do
    :crypto.supports()[:hashs]
    |> Enum.map(&Atom.to_string/1)
    |> Enum.map(&String.to_atom(String.replace(&1, "_", "-")))
  end

  def digest_length([algorithm | _rest]) do
    :crypto.hash(hash_name(algorithm), <<>>) |> byte_size()
  end

  def integer_to_octets([integer | opts]) do
    options = ExLisp.Builtins.parse_lisp_keywords(opts)
    bits = Keyword.get(options, :n_bits) || :erlang.bit_size(integer)
    endian = (Keyword.get(options, :big_endian, :t) in [nil, false] && :little) || :big
    integer = Bitwise.band(integer, Bitwise.bsl(1, bits) - 1)
    size = div(bits + 7, 8)
    integer |> encode_integer(endian) |> pad_binary(size, endian) |> make_bytes()
  end

  def octets_to_integer([octets | opts]) do
    options = ExLisp.Builtins.parse_lisp_keywords(opts)
    values = ExLisp.Builtins.seq_to_list(octets)
    start = Keyword.get(options, :start, 0) || 0
    finish = Keyword.get(options, :end, length(values)) || length(values)
    bits = Keyword.get(options, :n_bits, (finish - start) * 8)
    endian = (Keyword.get(options, :big_endian, :t) in [nil, false] && :little) || :big

    values
    |> Enum.slice(start, finish - start)
    |> :erlang.list_to_binary()
    |> decode_integer(endian)
    |> Bitwise.band(Bitwise.bsl(1, bits) - 1)
  end

  def random_bits([bits]), do: random_bytes(div(bits + 7, 8), bits)

  def make_hmac([key, algorithm]) do
    {:ironclad_hmac, hash_name(algorithm),
     :crypto.mac_init(:hmac, hash_name(algorithm), to_binary(key))}
  end

  def update_hmac([{:ironclad_hmac, algorithm, context}, data | opts]) do
    options = ExLisp.Builtins.parse_lisp_keywords(opts)
    bytes = to_binary(data)
    start = Keyword.get(options, :start, 0) || 0
    finish = Keyword.get(options, :end, byte_size(bytes)) || byte_size(bytes)

    {:ironclad_hmac, algorithm,
     :crypto.mac_update(context, binary_part(bytes, start, finish - start))}
  end

  def hmac_digest([{:ironclad_hmac, _algorithm, context} | _opts]) do
    context |> :crypto.mac_final() |> make_bytes()
  end

  def pbkdf2_hash_password([password | opts]) do
    options = ExLisp.Builtins.parse_lisp_keywords(opts)
    algorithm = Keyword.get(options, :digest, :sha256) |> hash_name()

    salt =
      Keyword.get_lazy(options, :salt, fn -> :crypto.strong_rand_bytes(16) end) |> to_binary()

    iterations = Keyword.get(options, :iterations, 1_000)
    key_length = digest_length([algorithm])

    hash =
      :crypto.pbkdf2_hmac(
        algorithm,
        to_binary(password),
        salt,
        iterations,
        key_length
      )

    [:_values_, [make_bytes(hash), make_bytes(salt)]]
  end

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

  defp pad_binary(binary, size, :big) when byte_size(binary) < size,
    do: :binary.copy(<<0>>, size - byte_size(binary)) <> binary

  defp pad_binary(binary, size, :little) when byte_size(binary) < size,
    do: binary <> :binary.copy(<<0>>, size - byte_size(binary))

  defp pad_binary(binary, size, _endian) when byte_size(binary) > size,
    do: raise(ArgumentError, "integer does not fit in #{size} bytes")

  defp pad_binary(binary, _size, _endian), do: binary

  defp random_bytes(bytes, bits) do
    binary = :crypto.strong_rand_bytes(bytes)

    if rem(bits, 8) == 0 do
      :binary.decode_unsigned(binary)
    else
      <<head::size(bits), _::bitstring>> = binary
      head
    end
  end

  defp encode_integer(integer, :big), do: :binary.encode_unsigned(integer)

  defp encode_integer(integer, :little),
    do:
      integer
      |> :binary.encode_unsigned()
      |> :binary.bin_to_list()
      |> Enum.reverse()
      |> :erlang.list_to_binary()

  defp decode_integer(binary, :big), do: :binary.decode_unsigned(binary)

  defp decode_integer(binary, :little),
    do:
      binary
      |> :binary.bin_to_list()
      |> Enum.reverse()
      |> :erlang.list_to_binary()
      |> :binary.decode_unsigned()
end
