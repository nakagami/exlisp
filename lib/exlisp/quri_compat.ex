defmodule ExLisp.QURICompat do
  @moduledoc false

  def install do
    ExLisp.Package.ensure_tables()
    package = ExLisp.Package.find_package!("QURI")

    %{
      uri: &uri/1,
      uri_scheme: &uri_field(&1, :scheme),
      uri_host: &uri_field(&1, :host),
      uri_port: &uri_field(&1, :port),
      uri_path: &uri_field(&1, :path),
      uri_query: &uri_field(&1, :query),
      url_encode: &url_encode/1,
      url_decode: &url_decode/1,
      url_encode_params: &url_encode_params/1,
      url_decode_params: &url_decode_params/1,
      merge_uris: &merge_uris/1
    }
    |> Enum.each(fn {name, function} ->
      closure = ExLisp.Closure.new(function, name, package: package.name)
      ExLisp.Env.put_fun(:"quri.#{name}", closure)
      ExLisp.Env.put_fun(:"quri:#{name}", closure)
    end)

    :t
  end

  def uri([value]), do: uri(value)
  def uri({:uri, _map} = value), do: value
  def uri(value), do: {:uri, URI.parse(ExLisp.Builtins.to_string_val(value))}

  def uri_field([{:uri, parsed}], field), do: Map.get(parsed, field)
  def uri_field({:uri, parsed}, field), do: Map.get(parsed, field)

  def url_encode([value | _opts]) do
    value
    |> ExLisp.Builtins.to_string_val()
    |> URI.encode(&URI.char_unreserved?/1)
  end

  def url_decode([value | _opts]) do
    value |> ExLisp.Builtins.to_string_val() |> URI.decode()
  end

  def url_encode_params([params | _opts]) do
    params
    |> ExLisp.Builtins.seq_to_list()
    |> Enum.map(fn
      [key, value] -> {ExLisp.Builtins.to_string_val(key), ExLisp.Builtins.to_string_val(value)}
      {key, value} -> {ExLisp.Builtins.to_string_val(key), ExLisp.Builtins.to_string_val(value)}
    end)
    |> URI.encode_query()
  end

  def url_decode_params([query | _opts]) do
    query
    |> ExLisp.Builtins.to_string_val()
    |> URI.decode_query()
    |> Enum.to_list()
    |> Enum.flat_map(fn {key, value} -> [key, value] end)
  end

  def merge_uris([reference, base]) do
    {:uri, reference_uri} = uri(reference)
    {:uri, base_uri} = uri(base)
    {:uri, URI.merge(base_uri, reference_uri)}
  end
end
