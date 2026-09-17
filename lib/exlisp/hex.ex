defmodule ExLisp.Hex do
  @moduledoc """
  Hex.pm client module.
  Provides functionality to dynamically download, compile, and load
  Hex.pm libraries from within the REPL or Lisp scripts.
  """

  @installed_table :exlisp_hex_installed

  @doc """
  Loads and initializes the Mix and Hex runtime environments.
  Even in environments like escripts where Mix is not loaded by default,
  dynamically loads from system Erlang / Elixir installation paths.
  """
  def ensure_mix_loaded do
    find_and_add_beam_libs()

    Application.ensure_all_started(:ssl)
    Application.ensure_all_started(:inets)
    Application.ensure_all_started(:logger)
    Application.ensure_all_started(:mix)

    try do
      Mix.Local.append_archives()
      Mix.Local.append_paths()
    rescue
      _ -> :ok
    end

    Application.ensure_all_started(:hex)
    reconsolidate_protocols()
    :ok
  rescue
    _ ->
      :ok
  end

  @doc """
  Installs and loads the specified Hex package (single or list).

  ## Examples (Lisp)
  - `(hex:install :jason)`
  - `(hex:install :jason "~> 1.4")`
  - `(hex:install '(:jason :floki))`
  - `(hex:install '((:jason "~> 1.4") (:floki "~> 0.36")))`
  """
  def install(packages, req_or_opts \\ nil)

  def install(package, req) when is_binary(req) do
    dep = normalize_dep_spec(package, req)
    do_install([dep])
  end

  def install(packages, opts) when is_list(opts) do
    deps = normalize_packages_arg(packages)
    do_install(deps, opts)
  end

  def install(packages, nil) do
    deps = normalize_packages_arg(packages)
    do_install(deps)
  end

  @doc """
  Searches packages on Hex.pm and returns a symbol list of matching package names.
  Equivalent to `(hex:search "query")`.
  """
  def search(query) when is_binary(query) or is_atom(query) do
    q = query |> to_string() |> String.trim() |> URI.encode_www_form()
    url = "https://hex.pm/api/packages?search=#{q}"

    case fetch_json(url) do
      {:ok, items} when is_list(items) ->
        items
        |> Enum.map(fn
          %{"name" => name} -> String.upcase(name) |> ExLisp.Symbol.new()
          _ -> nil
        end)
        |> Enum.reject(&is_nil/1)

      _ ->
        []
    end
  end

  @doc """
  Retrieves and returns package information for the specified package.
  Equivalent to `(hex:info :package-name)`.
  """
  def info(package) do
    pkg_name = normalize_app_name(package) |> to_string()
    url = "https://hex.pm/api/packages/#{pkg_name}"

    case fetch_json(url) do
      {:ok, data} when is_map(data) ->
        name = Map.get(data, "name", pkg_name)
        meta = Map.get(data, "meta", %{})
        desc = Map.get(meta, "description", "")
        licenses = Map.get(meta, "licenses", [])
        links = Map.get(meta, "links", %{})
        releases = Map.get(data, "releases", [])

        latest_version =
          case releases do
            [%{"version" => v} | _] -> v
            _ -> ""
          end

        [
          [ExLisp.Symbol.new("NAME"), name],
          [ExLisp.Symbol.new("LATEST-VERSION"), latest_version],
          [ExLisp.Symbol.new("DESCRIPTION"), desc],
          [ExLisp.Symbol.new("LICENSES"), licenses],
          [ExLisp.Symbol.new("LINKS"), Enum.map(links, fn {k, v} -> [k, v] end)]
        ]

      _ ->
        nil
    end
  end

  @doc """
  Returns the installation directory path for the specified package.
  """
  def where_is_package(package) do
    app = normalize_app_name(package)

    try do
      Application.app_dir(app)
    rescue
      _ ->
        case :code.lib_dir(app) do
          {:error, _} -> nil
          dir when is_list(dir) -> to_string(dir)
          dir when is_binary(dir) -> dir
        end
    end
  end

  # --- Internal processing ---

  defp do_install(deps, opts \\ []) do
    ensure_mix_loaded()
    ensure_installed_table()

    # Merge with existing dependencies
    existing_deps = get_all_installed_deps()
    merged_deps = merge_deps(existing_deps, deps)

    Code.put_compiler_option(:ignore_module_conflict, true)

    # If running inside a Mix project, temporarily pop from stack
    saved_project =
      if Code.ensure_loaded?(Mix.Project) and Mix.Project.get() != nil do
        Mix.Project.pop()
      else
        nil
      end

    try do
      # Reset Mix.install single-call restriction within VM
      reset_mix_install_state()

      # Execute installation
      install_opts =
        [consolidate_protocols: false]
        |> Keyword.merge(opts)

      Mix.install(merged_deps, install_opts)

      # Save to ETS
      save_installed_deps(merged_deps)
      reconsolidate_protocols()

      # Return list of module symbols for loaded packages
      installed_apps =
        deps
        |> Enum.map(fn
          {app, _} -> app
          {app, _, _} -> app
          app when is_atom(app) -> app
        end)
        |> Enum.map(&get_main_module_symbol/1)

      installed_apps
    after
      if saved_project != nil and Code.ensure_loaded?(Mix.ProjectStack) do
        try do
          Mix.ProjectStack.push(
            saved_project.name,
            saved_project.config,
            saved_project.file
          )
        rescue
          _ -> :ok
        end
      end
    end
  end

  defp get_main_module_symbol(app) do
    case :application.get_key(app, :modules) do
      {:ok, modules} ->
        elixir_mod =
          Enum.find(modules, fn mod ->
            mod_str = to_string(mod)

            String.starts_with?(mod_str, "Elixir.") and
              String.downcase(String.replace_prefix(mod_str, "Elixir.", "")) ==
                String.downcase(to_string(app))
          end) ||
            Enum.find(modules, fn mod ->
              mod_str = to_string(mod)

              String.starts_with?(mod_str, "Elixir.") and
                String.downcase(String.replace_prefix(mod_str, "Elixir.", "")) ==
                  String.downcase(Macro.camelize(to_string(app)))
            end) ||
            Enum.find(modules, fn mod ->
              String.starts_with?(to_string(mod), "Elixir.")
            end)

        case elixir_mod do
          nil ->
            case modules do
              [first | _] -> ExLisp.Symbol.new(to_string(first))
              [] -> ExLisp.Symbol.new(Macro.camelize(to_string(app)))
            end

          mod ->
            name = String.replace_prefix(to_string(mod), "Elixir.", "")
            ExLisp.Symbol.new(name)
        end

      _ ->
        ExLisp.Symbol.new(Macro.camelize(to_string(app)))
    end
  end

  defp normalize_packages_arg(packages) do
    cond do
      is_atom(packages) or is_binary(packages) or is_struct(packages, ExLisp.Symbol) ->
        [normalize_dep_spec(packages, ">= 0.0.0")]

      is_list(packages) ->
        case packages do
          # Single pair like [:jason, "~> 1.4"]
          [app, req]
          when (is_atom(app) or is_binary(app) or is_struct(app, ExLisp.Symbol)) and
                 is_binary(req) ->
            [normalize_dep_spec(app, req)]

          _ ->
            Enum.map(packages, fn
              [app, req]
              when (is_atom(app) or is_binary(app) or is_struct(app, ExLisp.Symbol)) and
                     is_binary(req) ->
                normalize_dep_spec(app, req)

              [app, req, opts]
              when (is_atom(app) or is_binary(app) or is_struct(app, ExLisp.Symbol)) and
                     is_binary(req) and is_list(opts) ->
                {normalize_app_name(app), req, opts}

              {app, req} ->
                {normalize_app_name(app), req}

              {app, req, opts} ->
                {normalize_app_name(app), req, opts}

              item ->
                normalize_dep_spec(item, ">= 0.0.0")
            end)
        end

      true ->
        raise ArgumentError, "Invalid package specification: #{inspect(packages)}"
    end
  end

  defp normalize_dep_spec(app, req) do
    {normalize_app_name(app), req}
  end

  defp normalize_app_name(app) do
    cond do
      is_atom(app) ->
        app
        |> Atom.to_string()
        |> String.trim_leading(":")
        |> String.downcase()
        |> String.to_atom()

      is_binary(app) ->
        app |> String.trim_leading(":") |> String.downcase() |> String.to_atom()

      is_struct(app, ExLisp.Symbol) ->
        app.name |> String.trim_leading(":") |> String.downcase() |> String.to_atom()

      true ->
        raise ArgumentError, "Invalid application name: #{inspect(app)}"
    end
  end

  defp merge_deps(existing, new_deps) do
    new_map =
      Map.new(new_deps, fn
        {app, req} -> {app, {app, req}}
        {app, req, opts} -> {app, {app, req, opts}}
        app when is_atom(app) -> {app, {app, ">= 0.0.0"}}
      end)

    existing_map =
      Map.new(existing, fn
        {app, req} -> {app, {app, req}}
        {app, req, opts} -> {app, {app, req, opts}}
        app when is_atom(app) -> {app, {app, ">= 0.0.0"}}
      end)

    Map.merge(existing_map, new_map)
    |> Map.values()
  end

  defp reset_mix_install_state do
    case :ets.whereis(Mix.State) do
      :undefined ->
        :ok

      _tid ->
        try do
          :ets.delete(Mix.State, :installed)
        rescue
          _ -> :ok
        end
    end
  end

  defp ensure_installed_table do
    case :ets.info(@installed_table) do
      :undefined ->
        try do
          :ets.new(@installed_table, [:set, :public, :named_table])
        rescue
          _ -> :ok
        end

      _ ->
        :ok
    end
  end

  defp get_all_installed_deps do
    ensure_installed_table()

    case :ets.lookup(@installed_table, :deps) do
      [{:deps, deps}] -> deps
      _ -> []
    end
  end

  defp save_installed_deps(deps) do
    ensure_installed_table()
    :ets.insert(@installed_table, {:deps, deps})
  end

  defp find_and_add_beam_libs do
    # Add Erlang standard library paths
    erl_root = :code.root_dir() |> to_string()

    Path.wildcard(Path.join(erl_root, "lib/*/ebin"))
    |> Enum.each(&Code.append_path/1)

    # Add Elixir standard library paths
    case System.cmd("elixir", ["-e", "IO.puts(:code.lib_dir(:mix))"]) do
      {output, 0} ->
        mix_lib = output |> String.trim() |> Path.expand()
        elixir_lib_dir = Path.dirname(mix_lib)

        Path.wildcard(Path.join(elixir_lib_dir, "*/ebin"))
        |> Enum.each(&Code.append_path/1)

      _ ->
        [
          "/usr/lib/elixir/lib/*/ebin",
          "/usr/local/lib/elixir/lib/*/ebin"
        ]
        |> Enum.flat_map(&Path.wildcard/1)
        |> Enum.each(&Code.append_path/1)
    end
  rescue
    _ ->
      :ok
  end

  defp fetch_json(url) do
    case System.cmd("curl", ["-sSL", "-H", "User-Agent: ExLisp", url]) do
      {body, 0} ->
        parse_json(body)

      _ ->
        {:error, :fetch_failed}
    end
  rescue
    _ ->
      {:error, :fetch_failed}
  end

  defp parse_json(body) when is_binary(body) do
    if Code.ensure_loaded?(:json) and function_exported?(:json, :decode, 1) do
      try do
        {:ok, :json.decode(body)}
      rescue
        _ -> {:error, :json_decode_failed}
      end
    else
      if Code.ensure_loaded?(Jason) do
        apply(Jason, :decode, [body])
      else
        {:error, :no_json_parser}
      end
    end
  end

  defp reconsolidate_protocols do
    [String.Chars, Inspect, List.Chars, Enumerable, Collectable]
    |> Enum.each(fn proto ->
      if Protocol.consolidated?(proto) do
        consolidated_ok =
          try do
            impls = Protocol.extract_impls(proto, :code.get_path())

            case Protocol.consolidate(proto, impls) do
              {:ok, binary} ->
                :code.load_binary(proto, ~c"nofile", binary)
                true

              _ ->
                false
            end
          rescue
            _ -> false
          end

        if not consolidated_ok do
          unconsolidate_protocol(proto)
        end
      end
    end)
  end

  defp unconsolidate_protocol(proto) do
    proto_file = "#{proto}.beam"

    case System.cmd("elixir", ["-e", "IO.puts(:code.lib_dir(:elixir))"]) do
      {output, 0} ->
        elixir_ebin = output |> String.trim() |> Path.join("ebin")
        beam_path = Path.join(elixir_ebin, proto_file)

        if File.exists?(beam_path) do
          :code.purge(proto)
          :code.delete(proto)
          :code.load_abs(String.to_charlist(Path.rootname(beam_path)))
        end

      _ ->
        :ok
    end
  rescue
    _ ->
      :ok
  end
end
