defmodule ExLisp.Thread do
  @moduledoc """
  Represents an SB-THREAD thread instance in ExLisp.
  """
  defstruct [:pid, :ref, :name]
end

defmodule ExLisp.Mutex do
  @moduledoc """
  Represents an SB-THREAD mutex instance in ExLisp.
  """
  defstruct [:name, :agent]
end

defmodule ExLisp.Semaphore do
  @moduledoc """
  Represents an SB-THREAD semaphore instance in ExLisp.
  """
  defstruct [:name, :agent]
end

defmodule ExLisp.SBCLProcess do
  @moduledoc """
  Represents an SB-EXT process instance returned by run-program.
  """
  defstruct [:pid, :status, :output, :program, :args]
end

defmodule ExLisp.SBCLCompat do
  @moduledoc """
  Compatibility layer for SBCL-specific packages (SB-THREAD, SB-EXT, SB-POSIX, SB-SYS).
  """

  @threads_table :exlisp_sb_threads_table

  def ensure_tables do
    case :ets.whereis(@threads_table) do
      :undefined ->
        try do
          :ets.new(@threads_table, [:set, :public, :named_table])
        rescue
          _ -> :ok
        end

      _ ->
        :ok
    end
  end

  # --- SB-THREAD: Threads ---

  def make_thread(args) when is_list(args) do
    ensure_tables()

    case args do
      [f | rest_opts] ->
        opts = ExLisp.Builtins.parse_lisp_keywords(rest_opts)
        name = Keyword.get(opts, :name, "thread") |> ExLisp.Builtins.to_string_val()
        arguments = Keyword.get(opts, :arguments, [])
        args_list = if is_list(arguments), do: arguments, else: [arguments]

        ref = make_ref()
        parent_env = ExLisp.Package.current_package()

        pid =
          Kernel.spawn(fn ->
            ExLisp.Package.set_current_package(parent_env)

            result =
              try do
                cond do
                  match?(%ExLisp.Closure{}, f) ->
                    ExLisp.Builtins.invoke_fn(f, args_list)

                  is_function(f) ->
                    case :erlang.fun_info(f, :arity) do
                      {:arity, arity} when arity == length(args_list) ->
                        apply(f, args_list)

                      _ ->
                        f.(args_list)
                    end

                  is_atom(f) ->
                    fun = ExLisp.Env.get_fun(f)

                    if fun do
                      ExLisp.Builtins.funcall(fun, args_list)
                    else
                      raise ArgumentError, "Undefined function for make-thread: #{inspect(f)}"
                    end

                  true ->
                    raise ArgumentError, "Invalid thread target: #{inspect(f)}"
                end
              catch
                kind, reason ->
                  {:error, {kind, reason}}
              end

            :ets.insert(@threads_table, {ref, {:done, result}})
          end)

        thread = %ExLisp.Thread{pid: pid, ref: ref, name: name}
        :ets.insert(@threads_table, {ref, {:running, thread}})
        thread

      _ ->
        raise ArgumentError, "make-thread requires a function argument"
    end
  end

  def make_thread(f), do: make_thread([f])

  def join_thread(args) when is_list(args) do
    ensure_tables()

    case args do
      [%ExLisp.Thread{ref: ref, pid: pid} = thread | rest_opts] ->
        opts = ExLisp.Builtins.parse_lisp_keywords(rest_opts)
        default_val = Keyword.get(opts, :default, nil)
        timeout = Keyword.get(opts, :timeout, nil)

        timeout_ms =
          case timeout do
            nil -> :infinity
            n when is_number(n) -> Kernel.trunc(n * 1000)
            _ -> :infinity
          end

        wait_thread_result(ref, pid, timeout_ms, default_val, thread)

      [pid | rest_opts] when is_pid(pid) ->
        join_thread([%ExLisp.Thread{pid: pid, ref: nil, name: "thread"} | rest_opts])

      _ ->
        raise ArgumentError, "join-thread requires a thread object"
    end
  end

  def join_thread(thread), do: join_thread([thread])

  defp wait_thread_result(ref, pid, timeout_ms, default_val, thread) do
    start_time = :erlang.monotonic_time(:millisecond)

    do_wait_loop(ref, pid, timeout_ms, default_val, start_time, thread)
  end

  defp do_wait_loop(ref, pid, timeout_ms, default_val, start_time, thread) do
    case :ets.lookup(@threads_table, ref) do
      [{^ref, {:done, result}}] ->
        case result do
          {:error, {kind, reason}} ->
            :erlang.raise(kind, reason, [])

          val ->
            val
        end

      _ ->
        if not Process.alive?(pid) do
          case :ets.lookup(@threads_table, ref) do
            [{^ref, {:done, result}}] ->
              case result do
                {:error, {kind, reason}} -> :erlang.raise(kind, reason, [])
                val -> val
              end

            _ ->
              default_val
          end
        else
          elapsed = :erlang.monotonic_time(:millisecond) - start_time

          if timeout_ms != :infinity and elapsed >= timeout_ms do
            default_val
          else
            Process.sleep(5)
            do_wait_loop(ref, pid, timeout_ms, default_val, start_time, thread)
          end
        end
    end
  end

  def thread_alive_p(%ExLisp.Thread{pid: pid}), do: if(Process.alive?(pid), do: :t, else: nil)
  def thread_alive_p(pid) when is_pid(pid), do: if(Process.alive?(pid), do: :t, else: nil)
  def thread_alive_p([t]), do: thread_alive_p(t)
  def thread_alive_p(_), do: nil

  def thread_p(%ExLisp.Thread{}), do: :t
  def thread_p([%ExLisp.Thread{}]), do: :t
  def thread_p(pid) when is_pid(pid), do: :t
  def thread_p([pid]) when is_pid(pid), do: :t
  def thread_p(_), do: nil

  def current_thread do
    %ExLisp.Thread{pid: Kernel.self(), ref: nil, name: "main"}
  end

  def current_thread([]), do: current_thread()

  def thread_name(%ExLisp.Thread{name: name}), do: name
  def thread_name(pid) when is_pid(pid), do: "process_#{inspect(pid)}"
  def thread_name([t]), do: thread_name(t)
  def thread_name(_), do: nil

  def list_all_threads do
    ensure_tables()

    running =
      :ets.tab2list(@threads_table)
      |> Enum.flat_map(fn
        {_ref, {:running, %ExLisp.Thread{pid: pid} = t}} ->
          if Process.alive?(pid), do: [t], else: []

        _ ->
          []
      end)

    [current_thread() | running] |> Enum.uniq_by(& &1.pid)
  end

  def list_all_threads([]), do: list_all_threads()

  def destroy_thread(%ExLisp.Thread{pid: pid}) do
    Process.exit(pid, :kill)
    :t
  end

  def destroy_thread(pid) when is_pid(pid) do
    Process.exit(pid, :kill)
    :t
  end

  def destroy_thread([t]), do: destroy_thread(t)
  def destroy_thread(_), do: nil

  def thread_yield do
    :erlang.yield()
    :t
  end

  def thread_yield([]), do: thread_yield()

  # --- SB-THREAD: Mutexes ---

  def make_mutex(args \\ []) do
    args_list = if is_list(args), do: args, else: [args]
    opts = ExLisp.Builtins.parse_lisp_keywords(args_list)
    name = Keyword.get(opts, :name, "mutex") |> ExLisp.Builtins.to_string_val()

    {:ok, agent} = Agent.start_link(fn -> %{owner: nil, count: 0} end)
    %ExLisp.Mutex{name: name, agent: agent}
  end

  def mutex_p(%ExLisp.Mutex{}), do: :t
  def mutex_p([%ExLisp.Mutex{}]), do: :t
  def mutex_p(_), do: nil

  def grab_mutex(args) when is_list(args) do
    case args do
      [%ExLisp.Mutex{agent: agent} | rest_opts] ->
        opts = ExLisp.Builtins.parse_lisp_keywords(rest_opts)
        wait = Keyword.get(opts, :wait, :t) not in [nil, false]
        timeout = Keyword.get(opts, :timeout, nil)

        timeout_ms =
          case timeout do
            nil -> :infinity
            n when is_number(n) -> Kernel.trunc(n * 1000)
            _ -> :infinity
          end

        caller = Kernel.self()
        start_time = :erlang.monotonic_time(:millisecond)

        do_grab_mutex(agent, caller, wait, timeout_ms, start_time)

      _ ->
        nil
    end
  end

  def grab_mutex(%ExLisp.Mutex{} = m), do: grab_mutex([m])

  defp do_grab_mutex(agent, caller, wait, timeout_ms, start_time) do
    acquired =
      try do
        Agent.get_and_update(agent, fn %{owner: owner, count: count} = state ->
          cond do
            owner == caller ->
              {:ok, %{state | count: count + 1}}

            owner == nil ->
              {:ok, %{owner: caller, count: 1}}

            true ->
              {:busy, state}
          end
        end)
      rescue
        _ -> :error
      end

    case acquired do
      :ok ->
        :t

      :busy ->
        if not wait do
          nil
        else
          elapsed = :erlang.monotonic_time(:millisecond) - start_time

          if timeout_ms != :infinity and elapsed >= timeout_ms do
            nil
          else
            Process.sleep(2)
            do_grab_mutex(agent, caller, wait, timeout_ms, start_time)
          end
        end

      _ ->
        nil
    end
  end

  def release_mutex(%ExLisp.Mutex{agent: agent}) do
    caller = Kernel.self()

    try do
      Agent.get_and_update(agent, fn %{owner: owner, count: count} = state ->
        if owner == caller do
          new_count = count - 1

          if new_count <= 0 do
            {:t, %{owner: nil, count: 0}}
          else
            {:t, %{state | count: new_count}}
          end
        else
          {:nil, state}
        end
      end)
    rescue
      _ -> nil
    end
  end

  def release_mutex([m]), do: release_mutex(m)
  def release_mutex(_), do: nil

  def mutex_name(%ExLisp.Mutex{name: name}), do: name
  def mutex_name([m]), do: mutex_name(m)
  def mutex_name(_), do: nil

  def mutex_value(%ExLisp.Mutex{agent: agent}) do
    try do
      Agent.get(agent, fn s -> s.owner end)
    rescue
      _ -> nil
    end
  end

  def mutex_value([m]), do: mutex_value(m)
  def mutex_value(_), do: nil

  # --- SB-THREAD: Semaphores ---

  def make_semaphore(args \\ []) do
    args_list = if is_list(args), do: args, else: [args]
    opts = ExLisp.Builtins.parse_lisp_keywords(args_list)
    name = Keyword.get(opts, :name, "semaphore") |> ExLisp.Builtins.to_string_val()
    count = Keyword.get(opts, :count, 0)
    c = if is_integer(count), do: count, else: 0

    {:ok, agent} = Agent.start_link(fn -> c end)
    %ExLisp.Semaphore{name: name, agent: agent}
  end

  def semaphore_p(%ExLisp.Semaphore{}), do: :t
  def semaphore_p([%ExLisp.Semaphore{}]), do: :t
  def semaphore_p(_), do: nil

  def wait_on_semaphore(args) when is_list(args) do
    case args do
      [%ExLisp.Semaphore{agent: agent} | rest_opts] ->
        opts = ExLisp.Builtins.parse_lisp_keywords(rest_opts)
        n = Keyword.get(opts, :n, 1)
        req = if is_integer(n) and n > 0, do: n, else: 1
        timeout = Keyword.get(opts, :timeout, nil)

        timeout_ms =
          case timeout do
            nil -> :infinity
            num when is_number(num) -> Kernel.trunc(num * 1000)
            _ -> :infinity
          end

        start_time = :erlang.monotonic_time(:millisecond)
        do_wait_semaphore(agent, req, timeout_ms, start_time)

      _ ->
        nil
    end
  end

  def wait_on_semaphore(%ExLisp.Semaphore{} = s), do: wait_on_semaphore([s])

  defp do_wait_semaphore(agent, req, timeout_ms, start_time) do
    acquired =
      try do
        Agent.get_and_update(agent, fn count ->
          if count >= req do
            {:ok, count - req}
          else
            {:busy, count}
          end
        end)
      rescue
        _ -> :error
      end

    case acquired do
      :ok ->
        :t

      :busy ->
        elapsed = :erlang.monotonic_time(:millisecond) - start_time

        if timeout_ms != :infinity and elapsed >= timeout_ms do
          nil
        else
          Process.sleep(2)
          do_wait_semaphore(agent, req, timeout_ms, start_time)
        end

      _ ->
        nil
    end
  end

  def signal_semaphore(args) when is_list(args) do
    case args do
      [%ExLisp.Semaphore{agent: agent}, n | _] when is_integer(n) ->
        Agent.update(agent, fn c -> c + n end)
        :t

      [%ExLisp.Semaphore{agent: agent} | _] ->
        Agent.update(agent, fn c -> c + 1 end)
        :t

      _ ->
        nil
    end
  end

  def signal_semaphore(%ExLisp.Semaphore{} = s), do: signal_semaphore([s])
  def signal_semaphore(%ExLisp.Semaphore{} = s, n), do: signal_semaphore([s, n])

  # --- SB-EXT: Environment & Process ---

  def posix_getenv([var]), do: posix_getenv(var)

  def posix_getenv(var) do
    var_str = ExLisp.Builtins.to_string_val(var)
    System.get_env(var_str)
  end

  def sb_posix_setenv([var, val | _rest]), do: sb_posix_setenv(var, val)

  def sb_posix_setenv(var, val) do
    System.put_env(ExLisp.Builtins.to_string_val(var), ExLisp.Builtins.to_string_val(val))
    0
  end

  def sb_posix_unsetenv([var]), do: sb_posix_unsetenv(var)

  def sb_posix_unsetenv(var) do
    System.delete_env(ExLisp.Builtins.to_string_val(var))
    0
  end

  def sb_ext_exit(args \\ []) do
    args_list = if is_list(args), do: args, else: [args]
    opts = ExLisp.Builtins.parse_lisp_keywords(args_list)
    code = Keyword.get(opts, :code, 0)
    System.stop(code)
    :t
  end

  def run_program(args) when is_list(args) do
    case args do
      [program, prog_args | rest_opts] ->
        prog_str = ExLisp.Builtins.to_string_val(program)

        args_strs =
          cond do
            is_list(prog_args) -> Enum.map(prog_args, &ExLisp.Builtins.to_string_val/1)
            is_binary(prog_args) -> [prog_args]
            true -> []
          end

        opts = ExLisp.Builtins.parse_lisp_keywords(rest_opts)
        _wait = Keyword.get(opts, :wait, :t) not in [nil, nil, false]

        try do
          {output, exit_code} = System.cmd(prog_str, args_strs, stderr_to_stdout: true)

          %ExLisp.SBCLProcess{
            pid: nil,
            status: exit_code,
            output: output,
            program: prog_str,
            args: args_strs
          }
        rescue
          e ->
            %ExLisp.SBCLProcess{
              pid: nil,
              status: -1,
              output: Exception.message(e),
              program: prog_str,
              args: args_strs
            }
        end

      [program] ->
        run_program([program, []])

      _ ->
        raise ArgumentError, "run-program requires at least a program name"
    end
  end

  def run_program(program, args), do: run_program([program, args])

  def process_exit_code(%ExLisp.SBCLProcess{status: code}), do: code
  def process_exit_code([%ExLisp.SBCLProcess{status: code}]), do: code
  def process_exit_code(_), do: nil

  def process_p(%ExLisp.SBCLProcess{}), do: :t
  def process_p([%ExLisp.SBCLProcess{}]), do: :t
  def process_p(_), do: nil

  def process_alive_p(%ExLisp.SBCLProcess{}), do: nil
  def process_alive_p([%ExLisp.SBCLProcess{}]), do: nil
  def process_alive_p(_), do: nil

  def process_kill(%ExLisp.SBCLProcess{}), do: :t
  def process_kill([%ExLisp.SBCLProcess{}]), do: :t
  def process_kill(_), do: nil

  def process_wait(%ExLisp.SBCLProcess{} = p), do: p
  def process_wait([%ExLisp.SBCLProcess{} = p]), do: p
  def process_wait(_), do: nil

  def process_close(%ExLisp.SBCLProcess{}), do: :t
  def process_close([%ExLisp.SBCLProcess{}]), do: :t
  def process_close(_), do: nil

  def sb_ext_gc(_args \\ []) do
    :erlang.garbage_collect()
    nil
  end

  def bytes_consed_between_gcs, do: 12_582_912
  def bytes_consed_between_gcs([]), do: 12_582_912

  def get_time_of_day do
    usec_total = :os.system_time(:microsecond)
    sec = div(usec_total, 1_000_000)
    usec = rem(usec_total, 1_000_000)
    [:_values_, [sec, usec]]
  end

  def get_time_of_day([]), do: get_time_of_day()
end
