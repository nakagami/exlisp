defmodule ExLisp.QURICompat do
  @moduledoc false

  def install do
    ExLisp.Package.ensure_tables()
    package = ExLisp.Package.find_package!("QURI")

    %{
      uri: &uri/1,
      parse_uri: &parse_uri/1,
      make_uri: &make_uri/1,
      make_uri_http: &make_uri_http/1,
      make_uri_https: &make_uri_https/1,
      make_uri_ftp: &make_uri_ftp/1,
      make_uri_file: &make_uri_file/1,
      uri_p: &uri_p/1,
      uri_equal: &uri_equal/1,
      uri_scheme: &uri_field(&1, :scheme),
      uri_userinfo: &uri_field(&1, :userinfo),
      uri_host: &uri_field(&1, :host),
      uri_port: &uri_field(&1, :port),
      uri_path: &uri_field(&1, :path),
      uri_query: &uri_field(&1, :query),
      uri_fragment: &uri_field(&1, :fragment),
      uri_authority: &uri_authority/1,
      uri_query_params: &uri_query_params/1,
      uri_file_pathname: &uri_file_pathname/1,
      copy_uri: &copy_uri/1,
      render_uri: &render_uri/1,
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

  def parse_uri([value]), do: uri(value)

  def make_uri(args) do
    options = ExLisp.Builtins.parse_lisp_keywords(args)

    {:uri,
     %URI{
       scheme: option_string(options, :scheme),
       userinfo: option_string(options, :userinfo),
       host: option_string(options, :host),
       port: options[:port],
       path: option_string(options, :path),
       query: option_string(options, :query),
       fragment: option_string(options, :fragment)
     }}
  end

  def make_uri_http(args), do: make_uri_with_defaults(args, "http", 80)
  def make_uri_https(args), do: make_uri_with_defaults(args, "https", 443)
  def make_uri_ftp(args), do: make_uri_with_defaults(args, "ftp", 21)
  def make_uri_file(args), do: make_uri_with_defaults(args, "file", nil)

  def uri_p([{:uri, %URI{}}]), do: :t
  def uri_p(_args), do: nil
  def uri_equal([left, right]), do: if(uri(left) == uri(right), do: :t, else: nil)

  def uri_field([{:uri, parsed}], field), do: Map.get(parsed, field)
  def uri_field({:uri, parsed}, field), do: Map.get(parsed, field)

  def uri_authority([value]), do: uri_authority(value)

  def uri_authority({:uri, %URI{} = parsed}) do
    case {parsed.userinfo, parsed.host, parsed.port} do
      {nil, nil, _} ->
        nil

      {userinfo, host, port} ->
        userinfo = if(userinfo, do: "#{userinfo}@", else: "")
        port = if(port, do: ":#{port}", else: "")
        "#{userinfo}#{host}#{port}"
    end
  end

  def uri_query_params([value]) do
    case uri_field(value, :query) do
      nil ->
        []

      query ->
        query
        |> URI.decode_query()
        |> Enum.map(fn {key, val} -> [key | val] end)
    end
  end

  def uri_file_pathname([value]), do: uri_file_pathname(value)
  def uri_file_pathname({:uri, %URI{path: path}}), do: ExLisp.Pathname.pathname(path)

  def copy_uri([value]), do: copy_uri(value)

  def copy_uri({:uri, %URI{} = parsed}),
    do: {:uri, Map.from_struct(parsed) |> then(&struct!(URI, &1))}

  def render_uri([value]), do: render_uri(value)
  def render_uri({:uri, parsed}), do: URI.to_string(parsed)
  def render_uri(value), do: value |> uri() |> render_uri()

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
      [key, value] ->
        {ExLisp.Builtins.to_string_val(key), ExLisp.Builtins.to_string_val(value)}

      [key | value] ->
        {ExLisp.Builtins.to_string_val(key), ExLisp.Builtins.to_string_val(value)}

      {key, value} ->
        {ExLisp.Builtins.to_string_val(key), ExLisp.Builtins.to_string_val(value)}
    end)
    |> URI.encode_query()
  end

  def url_decode_params([query | _opts]) do
    query
    |> ExLisp.Builtins.to_string_val()
    |> URI.decode_query()
    |> Enum.to_list()
    |> Enum.map(fn {key, value} -> [key | value] end)
  end

  def merge_uris([reference, base]) do
    {:uri, reference_uri} = uri(reference)
    {:uri, base_uri} = uri(base)
    {:uri, URI.merge(base_uri, reference_uri)}
  end

  defp option_string(options, key) do
    case options[key] do
      nil -> nil
      value -> ExLisp.Builtins.to_string_val(value)
    end
  end

  defp make_uri_with_defaults(args, scheme, port) do
    {:uri, parsed} = make_uri(args)
    {:uri, %URI{parsed | scheme: parsed.scheme || scheme, port: parsed.port || port}}
  end
end
