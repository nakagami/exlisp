defmodule ExLisp.IOTracker do
  @moduledoc """
  Helper module for tracking standard output during REPL evaluation and outputting
  a newline (fresh-line) if no trailing newline exists at the end of evaluation.
  """

  @doc """
  Monitors output to `group_leader` during function execution, and outputs
  a newline if output was produced and does not end with a newline.
  """
  def with_tracker(fun) do
    original_gl = Process.group_leader()
    parent = self()

    tracker =
      spawn_link(fn ->
        loop(original_gl, false)
      end)

    Process.group_leader(parent, tracker)

    try do
      result = fun.()
      send(tracker, {:get_needs_fresh_line, self()})

      needs_fresh_line =
        receive do
          {:needs_fresh_line, val} -> val
        after
          1000 -> false
        end

      if needs_fresh_line do
        IO.write(original_gl, "\n")
      end

      result
    after
      Process.group_leader(parent, original_gl)
      send(tracker, :stop)
    end
  end

  defp loop(target_gl, needs_fresh_line) do
    receive do
      :stop ->
        :ok

      {:get_needs_fresh_line, from} ->
        send(from, {:needs_fresh_line, needs_fresh_line})
        loop(target_gl, needs_fresh_line)

      {:io_request, from, reply_as, req} ->
        new_needs_fresh_line = update_status(req, needs_fresh_line)
        send(target_gl, {:io_request, from, reply_as, req})
        loop(target_gl, new_needs_fresh_line)

      other ->
        send(target_gl, other)
        loop(target_gl, needs_fresh_line)
    end
  end

  defp update_status({:put_chars, _encoding, chars}, prev) do
    check_chars(chars, prev)
  end

  defp update_status({:put_chars, chars}, prev) do
    check_chars(chars, prev)
  end

  defp update_status({:requests, reqs}, prev) when is_list(reqs) do
    Enum.reduce(reqs, prev, &update_status/2)
  end

  defp update_status(_other, prev), do: prev

  defp check_chars(chars, prev) do
    case IO.chardata_to_string(chars) do
      "" -> prev
      str -> not String.ends_with?(str, "\n")
    end
  rescue
    _ -> prev
  end
end
