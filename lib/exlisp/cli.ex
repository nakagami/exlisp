defmodule ExLisp.CLI do
  @moduledoc """
  ExLisp CLI entry point.
  Starts an IEx-based Lisp REPL when launched with the `exlisp` command.
  Also executes compilation to BEAM modules when files are specified.
  """

  @doc """
  Escript entry point function.
  """
  def main(args \\ []) do
    {opts, rest, _invalid} =
      OptionParser.parse(args,
        switches: [
          script: :string,
          load: :keep,
          compile: :boolean,
          output: :string,
          module: :string,
          eval: :string,
          format: :boolean,
          help: :boolean
        ],
        aliases: [
          s: :script,
          l: :load,
          c: :compile,
          o: :output,
          m: :module,
          e: :eval,
          f: :format,
          h: :help
        ]
      )

    cond do
      opts[:help] ->
        print_help()

      opts[:format] ->
        handle_format(rest)

      opts[:script] ->
        file = opts[:script]
        do_run_script(file)

      opts[:compile] && rest != [] ->
        [file | _] = rest
        do_compile(file, opts)

      opts[:load] != nil ->
        load_files = Keyword.get_values(opts, :load)
        Enum.each(load_files, &do_load_file/1)

        if opts[:eval] do
          code = opts[:eval]
          result = ExLisp.eval_repl(code)
          IO.inspect(result)
        else
          start_repl()
        end

      opts[:eval] ->
        code = opts[:eval]
        result = ExLisp.eval_repl(code)
        IO.inspect(result)

      rest != [] ->
        Enum.each(rest, &do_run_script/1)

      true ->
        start_repl()
    end
  end

  defp do_run_script(file) do
    case ExLisp.load_file(file) do
      _ ->
        :ok
    end
  rescue
    e ->
      IO.puts(:stderr, "Error in #{file}: #{Exception.message(e)}")
      System.halt(1)
  end

  defp do_load_file(file) do
    ExLisp.load_file(file)
  rescue
    e ->
      IO.puts(:stderr, "Error loading #{file}: #{Exception.message(e)}")
      System.halt(1)
  end

  defp do_compile(file, opts) do
    compile_opts = []

    compile_opts =
      if opts[:output],
        do: Keyword.put(compile_opts, :output_dir, opts[:output]),
        else: compile_opts

    compile_opts =
      if opts[:module],
        do: Keyword.put(compile_opts, :module, Module.concat([opts[:module]])),
        else: compile_opts

    case ExLisp.compile_file(file, compile_opts) do
      {:ok, mod, beam_path} ->
        IO.puts("Compiled #{file} to #{beam_path} (module: #{inspect(mod)})")

      {:error, reason} ->
        IO.puts(:stderr, "Compilation error: #{inspect(reason)}")
        System.halt(1)
    end
  end

  @doc false
  def run_repl(opts) do
    configure_repl()

    spawn(fn ->
      :ok = :io.setopts([{:binary, true}, {:encoding, :unicode}])
      IEx.Server.run(opts)
    end)
  end

  defp configure_repl do
    Application.put_env(:kernel, :shell_history, :enabled)
    Application.ensure_all_started(:iex)
    ExLisp.Hex.ensure_mix_loaded()

    enable_ctrl_d_exit()

    vsn =
      case Application.spec(:exlisp, :vsn) do
        nil ->
          if Code.ensure_loaded?(ExLisp.MixProject),
            do: ExLisp.MixProject.project()[:version],
            else: "0.1.0"

        chars ->
          to_string(chars)
      end

    custom_banner = "Interactive ExLisp (#{vsn}) - press Ctrl+D or Ctrl+C to exit"
    intercept_banner(custom_banner)

    IEx.configure(
      history_size: 50,
      default_prompt: "%prefix(%counter)> ",
      continuation_prompt: "",
      parser: {ExLisp.Parser, :parse, []}
    )
  end

  defp enable_ctrl_d_exit do
    if Code.ensure_loaded?(:edlin) do
      try do
        :code.unstick_mod(:edlin)

        case :beam_lib.chunks(:code.which(:edlin), [:abstract_code]) do
          {:ok, {_, [abstract_code: {_, ac}]}} ->
            eof_clause =
              {:clause, 1,
               [
                 {:cons, 1, {:integer, 1, 4}, {nil, 1}},
                 {:tuple, 1,
                  [
                    {:atom, 1, :line},
                    {:var, 1, :_P},
                    {:tuple, 1, [{nil, 1}, {:tuple, 1, [{nil, 1}, {nil, 1}]}, {nil, 1}]},
                    {:tuple, 1, [{:atom, 1, :normal}, {:var, 1, :_M}]}
                  ]}
               ], [],
               [
                 {:call, 1, {:atom, 1, :exit}, [{:atom, 1, :die}]}
               ]}

            new_ac =
              Enum.map(ac, fn
                {:function, anno, :edit_line, 2, clauses} ->
                  {:function, anno, :edit_line, 2, [eof_clause | clauses]}

                other ->
                  other
              end)

            case :compile.forms(new_ac, [:return_errors, :return_warnings]) do
              {:ok, :edlin, binary, _warnings} ->
                :code.load_binary(:edlin, ~c"edlin.erl", binary)
                :ok

              _ ->
                :ok
            end

          _ ->
            :ok
        end
      catch
        _, _ -> :ok
      end
    end
  end

  defp start_repl do
    if Code.ensure_loaded?(:user_drv) and function_exported?(:user_drv, :start_shell, 1) do
      case :user_drv.start_shell(%{
             initial_shell: {__MODULE__, :run_repl, [[prefix: "exlisp", on_eof: :halt]]}
           }) do
        :ok ->
          group = :user_drv.whereis_group()
          ref = Process.monitor(group)

          receive do
            {:DOWN, ^ref, :process, _, _} -> :ok
          end

        _ ->
          configure_repl()
          IEx.Server.run(prefix: "exlisp", on_eof: :halt)
      end
    else
      configure_repl()
      IEx.Server.run(prefix: "exlisp", on_eof: :halt)
    end
  end

  defp intercept_banner(custom_banner) do
    target_gl = Process.group_leader()

    interceptor =
      spawn_link(fn ->
        banner_loop(target_gl, custom_banner, true)
      end)

    Process.group_leader(self(), interceptor)
  end

  defp banner_loop(target_gl, custom_banner, first?) do
    receive do
      {:io_request, from, reply_as, {:put_chars, encoding, chars}} ->
        str = IO.chardata_to_string(chars)

        if first? and String.starts_with?(str, "Interactive Elixir") do
          send(
            target_gl,
            {:io_request, from, reply_as, {:put_chars, encoding, custom_banner <> "\n"}}
          )

          Process.group_leader(from, target_gl)
          banner_loop(target_gl, custom_banner, false)
        else
          send(target_gl, {:io_request, from, reply_as, {:put_chars, encoding, chars}})
          banner_loop(target_gl, custom_banner, first?)
        end

      {:io_request, from, reply_as, req} ->
        send(target_gl, {:io_request, from, reply_as, req})
        banner_loop(target_gl, custom_banner, first?)

      other ->
        send(target_gl, other)
        banner_loop(target_gl, custom_banner, first?)
    end
  end

  defp handle_format(files) do
    case files do
      [] ->
        # Read from stdin, format, and write to stdout
        case IO.read(:stdio, :eof) do
          :eof ->
            :ok

          {:error, reason} ->
            IO.puts(:stderr, "Error reading stdin: #{inspect(reason)}")
            System.halt(1)

          content ->
            formatted = ExLisp.format(content)
            IO.write(formatted)
        end

      _ ->
        Enum.each(files, fn file ->
          case ExLisp.format_file(file, in_place: true) do
            {:ok, _formatted} ->
              :ok

            {:error, reason} ->
              IO.puts(:stderr, "Error formatting #{file}: #{inspect(reason)}")
              System.halt(1)
          end
        end)
    end
  end

  defp print_help do
    IO.puts("""
    Usage:
      exlisp                      Start interactive REPL
      exlisp <file.lisp>          Run Lisp file as a script and exit
      exlisp --load <file.lisp>   Load Lisp file and start interactive REPL
      exlisp --script <file.lisp> Run Lisp file as a script and exit
      exlisp -c <file.lisp> [-o <dir>] [-m <Module>]
      exlisp -e "<expression>"    Evaluate Lisp expression
      exlisp -f <file.lisp>...    Format Lisp file(s) in-place

    Options:
      -s, --script <file>         Execute file as a script and exit
      -l, --load <file>           Load file and start interactive REPL
      -c, --compile               Compile file to .beam bytecode
      -o, --output <dir>          Output directory for .beam files (default: ebin or mix compile_path)
      -m, --module <Module>       Module name for compiled file (default: ExLisp.Global)
      -e, --eval <expr>           Evaluate expression and print result
      -f, --format                Format Lisp source file(s) in-place (or stdin)
      -h, --help                  Print this help message
    """)
  end
end
