defmodule ExLisp.PerformanceBenchmark do
  @source """
  (defun fib (n)
    (if (<= n 1)
        n
        (+ (fib (- n 1)) (fib (- n 2)))))

  (defun sum-loop (n)
    (let ((sum 0))
      (dotimes (i n sum)
        (setq sum (+ sum i)))))

  (defun list-test (n)
    (let ((items nil))
      (dotimes (i n (length items))
        (setq items (cons i items)))))
  """

  def run do
    ExLisp.Env.reset()
    load_interpreter_source()

    {:ok, compiled_module, _binary} =
      ExLisp.Compiler.compile_string(
        @source,
        module: ExLisp.PerformanceBenchmark.Compiled,
        execute_top_level: false
      )

    cases =
      if System.get_env("EXLISP_BENCH_FAST") do
        [
          {"fib(25)", :fib, [25]},
          {"sum-loop(100,000)", :sum_loop, [100_000]},
          {"list-test(5,000)", :list_test, [5_000]}
        ]
      else
        [
          {"fib(30)", :fib, [30]},
          {"sum-loop(1,000,000)", :sum_loop, [1_000_000]},
          {"list-test(50,000)", :list_test, [50_000]}
        ]
      end

    repetitions =
      case Integer.parse(System.get_env("EXLISP_BENCH_REPETITIONS", "3")) do
        {value, ""} when value > 0 -> value
        _ -> raise "EXLISP_BENCH_REPETITIONS must be a positive integer"
      end

    IO.puts("ExLisp performance baseline (median of #{repetitions})")
    IO.puts(String.duplicate("=", 76))

    Enum.each(cases, fn {label, function, args} ->
      interpreted =
        ExLisp.JIT.with_disabled(fn ->
          benchmark(repetitions, fn -> ExLisp.call(function, args) end)
        end)

      compiled = benchmark(repetitions, fn -> apply(compiled_module, function, args) end)

      if interpreted.result != compiled.result do
        raise "#{label} produced different interpreter and compiled results"
      end

      speedup = interpreted.time_us / max(compiled.time_us, 1)

      IO.puts(
        String.pad_trailing(label, 24) <>
          " interpreter " <>
          format_time(interpreted.time_us) <>
          "  compiled " <>
          format_time(compiled.time_us) <>
          "  speedup #{Float.round(speedup, 1)}x"
      )
    end)
  end

  defp load_interpreter_source do
    @source
    |> ExLisp.Reader.split_expressions()
    |> Enum.each(&ExLisp.eval/1)
  end

  defp benchmark(repetitions, fun) do
    fun.()

    results =
      Enum.map(1..repetitions, fn _ ->
        {time_us, result} = :timer.tc(fun)
        {time_us, result}
      end)

    times = results |> Enum.map(&elem(&1, 0)) |> Enum.sort()
    %{time_us: Enum.at(times, div(length(times), 2)), result: results |> hd() |> elem(1)}
  end

  defp format_time(time_us) when time_us < 1_000, do: "#{time_us} us"
  defp format_time(time_us) when time_us < 1_000_000, do: "#{Float.round(time_us / 1_000, 2)} ms"
  defp format_time(time_us), do: "#{Float.round(time_us / 1_000_000, 2)} s"
end

ExLisp.PerformanceBenchmark.run()
