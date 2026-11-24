defmodule ExLisp.MutableCons do
  @moduledoc false

  @table :exlisp_mutable_cons_table
  @owner :exlisp_mutable_cons_owner
  @active_key :exlisp_mutable_cons_active
  @mapping_key :exlisp_mutable_cons_mappings

  def ensure_table do
    case :ets.whereis(@table) do
      :undefined -> start_table_owner()
      _ -> :ok
    end
  end

  defp start_table_owner do
    :global.trans({__MODULE__, @table}, fn ->
      if :ets.whereis(@table) == :undefined do
        parent = self()

        pid =
          spawn(fn ->
            try do
              Process.register(self(), @owner)
            rescue
              ArgumentError -> :ok
            end

            :ets.new(@table, [:set, :public, :named_table])
            send(parent, {:exlisp_mutable_cons_table, self()})
            table_owner_loop()
          end)

        receive do
          {:exlisp_mutable_cons_table, ^pid} -> :ok
        end
      end
    end)

    :ok
  end

  defp table_owner_loop do
    receive do
      :stop -> :ok
    end
  end

  def reset do
    ensure_table()
    scope = scope()
    Process.delete({@active_key, scope})
    Process.delete({@mapping_key, scope})

    try do
      :ets.select_delete(@table, [{{{scope, :_}, :_}, [], [true]}])
    rescue
      ArgumentError -> reset()
    end

    :ok
  end

  def resolve([]), do: []

  def resolve([_ | _] = value) do
    if mutable_cons_active?(), do: resolve(value, []), else: value
  end

  def resolve(value), do: value

  def resolve_cell(value) when is_list(value), do: resolve_root(value, [])
  def resolve_cell(value), do: value

  def replace(original, replacement) do
    register(original, resolve(original), replacement)
  end

  defp resolve(value, seen) do
    ensure_table()

    if Enum.any?(seen, &:erts_debug.same(&1, value)) do
      value
    else
      seen = [value | seen]

      current =
        case find_replacement(scope(), value) do
          {:ok, replacement} -> resolve(replacement, seen)
          :error -> value
        end

      case current do
        [head | tail] ->
          resolved_head = if is_list(head) and head != [], do: resolve(head, seen), else: head
          resolved_tail = if is_list(tail) and tail != [], do: resolve(tail, seen), else: tail

          if :erts_debug.same(head, resolved_head) and :erts_debug.same(tail, resolved_tail) do
            current
          else
            [resolved_head | resolved_tail]
          end

        _ ->
          current
      end
    end
  end

  defp find_replacement(scope, value) do
    case Process.get({@mapping_key, scope}) do
      nil ->
        case :ets.lookup(@table, {scope, value}) do
          [{{^scope, ^value}, replacement}] -> {:ok, replacement}
          [] -> :error
        end

      mappings ->
        Enum.find_value(mappings, :error, fn {original, replacement} ->
          if :erts_debug.same(original, value), do: {:ok, replacement}
        end)
    end
  end

  def rplaca(cons, object) do
    current = resolve(cons)

    case current do
      [_head | tail] ->
        replacement = [object | tail]
        register(cons, current, replacement)
        replacement

      _ ->
        raise ArgumentError, "rplaca requires a cons, got: #{inspect(cons)}"
    end
  end

  def rplacd(cons, object) do
    current = resolve(cons)

    case current do
      [head | _tail] ->
        replacement = [head | object]
        register(cons, current, replacement)
        replacement

      _ ->
        raise ArgumentError, "rplacd requires a cons, got: #{inspect(cons)}"
    end
  end

  def set_nth(index, cons, object) when is_integer(index) and index >= 0 do
    current = resolve(cons)
    replacement = List.replace_at(current, index, object)

    if replacement == current and Enum.at(current, index) == nil do
      raise ArgumentError, "index #{index} is outside the list"
    end

    register_root(cons, replacement)
    replacement
  end

  def list_length(list) do
    list_length(resolve_root(list, []), [])
  end

  defp list_length(nil, _seen), do: 0
  defp list_length([], _seen), do: 0

  defp list_length(list, seen) when is_list(list) do
    if Enum.any?(seen, &:erts_debug.same(&1, list)) do
      nil
    else
      [_head | tail] = list
      next = resolve_root(tail, [])

      case list_length(next, [list | seen]) do
        nil -> nil
        length -> length + 1
      end
    end
  end

  defp list_length(dotted, _seen),
    do: ExLisp.Condition.error(:type_error, datum: dotted, expected_type: :list)

  defp resolve_root(value, seen) do
    ensure_table()

    if Enum.any?(seen, &:erts_debug.same(&1, value)) do
      value
    else
      case find_replacement(scope(), value) do
        {:ok, replacement} -> resolve_root(replacement, [value | seen])
        :error -> value
      end
    end
  end

  defp register(original, current, replacement) do
    ensure_table()
    scope = scope()
    mark_active(scope)

    register_pair(scope, original, replacement)
    register_pair(scope, current, replacement)

    replacement
  end

  defp register_root(original, replacement) do
    ensure_table()
    scope = scope()
    mark_active(scope)
    register_pair(scope, original, replacement)
    replacement
  end

  defp register_pair(scope, original, replacement) do
    mappings =
      Process.get({@mapping_key, scope}, [])
      |> Enum.reject(fn {candidate, _replacement} -> :erts_debug.same(candidate, original) end)

    Process.put({@mapping_key, scope}, [{original, replacement} | mappings])
    :ets.insert(@table, {{scope, original}, replacement})
  end

  defp mark_active(scope) do
    Process.put({@active_key, scope}, true)
    ensure_table()
    :ets.insert(@table, {{scope, :__mutable_cons_active__}, true})
  end

  defp mutable_cons_active? do
    scope = scope()
    Process.get({@active_key, scope}, false)
  end

  def scope, do: Process.get(:exlisp_mutable_cons_scope, self())

  def set_scope(scope) do
    Process.put(:exlisp_mutable_cons_scope, scope)

    ensure_table()

    if :ets.member(@table, {scope, :__mutable_cons_active__}) do
      Process.put({@active_key, scope}, true)
    end

    :ok
  end
end
