defmodule ExLisp.YasonCompat do
  @moduledoc false

  def install do
    ExLisp.Package.ensure_tables()
    package = ExLisp.Package.find_package!("YASON")

    %{
      parse: &parse/1,
      encode: &encode/1,
      encode_alist: &encode/1,
      encode_plist: &encode/1,
      encode_scalar: &encode/1
    }
    |> Enum.each(fn {name, function} ->
      closure = ExLisp.Closure.new(function, name, package: package.name)

      for separator <- [".", ":"] do
        ExLisp.Env.put_fun(:"yason#{separator}#{name}", closure)
      end
    end)

    :t
  end

  def parse([value | _opts]), do: to_lisp_hash_table(:json.decode(to_string(value)))
  def parse(value), do: parse([value])

  def encode([value | _opts]) do
    value
    |> normalize_json()
    |> :json.encode()
    |> IO.iodata_to_binary()
  end

  defp to_lisp_hash_table(map) when is_map(map) do
    table = ExLisp.Builtins.make_hash_table([:test, :equal])

    Enum.each(map, fn {key, value} ->
      ExLisp.Builtins.set_gethash(key, table, to_lisp_hash_table(value))
    end)

    table
  end

  defp to_lisp_hash_table(list) when is_list(list), do: Enum.map(list, &to_lisp_hash_table/1)
  defp to_lisp_hash_table(value), do: value

  defp normalize_json({:hash_table, _test, tid}) do
    :ets.tab2list(tid)
    |> Enum.reject(&(elem(&1, 0) == :__meta__))
    |> Map.new(fn {key, value} -> {to_string(key), normalize_json(value)} end)
  end

  defp normalize_json(list) when is_list(list) and list != [] do
    if Enum.all?(Enum.chunk_every(list, 2), &(length(&1) == 2)) and
         Enum.all?(Enum.take_every(list, 2), fn key ->
           is_atom(key) or is_binary(key)
         end) do
      list
      |> Enum.chunk_every(2)
      |> Map.new(fn [key, value] -> {to_string(key), normalize_json(value)} end)
    else
      Enum.map(list, &normalize_json/1)
    end
  end

  defp normalize_json(%ExLisp.Symbol{name: name}), do: name
  defp normalize_json(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_json(value), do: value
end
