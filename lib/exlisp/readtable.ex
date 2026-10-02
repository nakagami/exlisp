defmodule ExLisp.Readtable do
  @moduledoc """
  ANSI Common Lisp Readtable implementation.
  Supports *readtable*, copy-readtable, readtablep,
  set-macro-character, get-macro-character,
  set-dispatch-macro-character, get-dispatch-macro-character,
  set-syntax-from-char, and readtable-case.
  """

  # A Readtable is represented as {:readtable, tid} backed by ETS
  # to support Common Lisp in-place mutation semantics.

  @standard_syntax %{
    ?\s => :whitespace,
    ?\t => :whitespace,
    ?\n => :whitespace,
    ?\r => :whitespace,
    12 => :whitespace,
    ?\\ => :single_escape,
    ?| => :multiple_escape,
    ?( => :terminating_macro,
    ?) => :terminating_macro,
    ?' => :terminating_macro,
    ?; => :terminating_macro,
    ?\" => :terminating_macro,
    ?` => :terminating_macro,
    ?, => :terminating_macro,
    ?# => :non_terminating_macro
  }

  def new(opts \\ []) do
    tid = :ets.new(:exlisp_readtable, [:set, :public])
    case_mode = Keyword.get(opts, :case, :upcase)
    syntax = Keyword.get(opts, :syntax, @standard_syntax)
    macros = Keyword.get(opts, :macros, %{})
    dispatch_macros = Keyword.get(opts, :dispatch_macros, %{})

    :ets.insert(tid, {:case, case_mode})
    :ets.insert(tid, {:syntax, syntax})
    :ets.insert(tid, {:macros, macros})
    :ets.insert(tid, {:dispatch_macros, dispatch_macros})

    {:readtable, tid}
  end

  def standard_readtable do
    case Process.get(:cl_standard_readtable) do
      nil ->
        rt = new()
        Process.put(:cl_standard_readtable, rt)
        rt
      rt ->
        rt
    end
  end

  def current_readtable do
    case Process.get(:cl_current_readtable) do
      nil ->
        rt = new()
        Process.put(:cl_current_readtable, rt)
        rt
      rt ->
        rt
    end
  end

  def set_current_readtable({:readtable, _} = rt) do
    Process.put(:cl_current_readtable, rt)
    rt
  end
  def set_current_readtable(_), do: current_readtable()

  def readtablep({:readtable, _}), do: :t
  def readtablep(_), do: nil

  def copy_readtable(from \\ nil, to \\ nil) do
    src = resolve_rt(from)
    {:readtable, src_tid} = src

    [{:case, c}] = :ets.lookup(src_tid, :case)
    [{:syntax, syn}] = :ets.lookup(src_tid, :syntax)
    [{:macros, mac}] = :ets.lookup(src_tid, :macros)
    [{:dispatch_macros, disp}] = :ets.lookup(src_tid, :dispatch_macros)

    case to do
      nil ->
        new(case: c, syntax: Map.new(syn), macros: Map.new(mac), dispatch_macros: Map.new(disp))

      {:readtable, dest_tid} ->
        :ets.insert(dest_tid, {:case, c})
        :ets.insert(dest_tid, {:syntax, Map.new(syn)})
        :ets.insert(dest_tid, {:macros, Map.new(mac)})
        :ets.insert(dest_tid, {:dispatch_macros, Map.new(disp)})
        {:readtable, dest_tid}

      _ ->
        new(case: c, syntax: Map.new(syn), macros: Map.new(mac), dispatch_macros: Map.new(disp))
    end
  end

  def set_macro_character(char, function, non_terminating_p \\ nil, readtable \\ nil) do
    {:readtable, tid} = resolve_rt(readtable)
    char_code = to_char_code(char)
    non_term = non_terminating_p not in [nil, false, :nil]

    [{:syntax, syn}] = :ets.lookup(tid, :syntax)
    [{:macros, mac}] = :ets.lookup(tid, :macros)

    new_syn =
      if non_term do
        Map.put(syn, char_code, :non_terminating_macro)
      else
        Map.put(syn, char_code, :terminating_macro)
      end

    new_mac = Map.put(mac, char_code, {function, non_term})

    :ets.insert(tid, {:syntax, new_syn})
    :ets.insert(tid, {:macros, new_mac})
    :t
  end

  def get_macro_character(char, readtable \\ nil) do
    {:readtable, tid} = resolve_rt(readtable)
    char_code = to_char_code(char)

    [{:macros, mac}] = :ets.lookup(tid, :macros)

    case Map.get(mac, char_code) do
      {func, non_term} ->
        [:_values_, [func, if(non_term, do: :t, else: nil)]]

      _ ->
        case char_code do
          ?# ->
            [:_values_, [fn _s, _c -> nil end, :t]]

          c when c in [?(, ?), ?', ?;, ?\", ?`, ?,] ->
            [:_values_, [fn _s, _c -> nil end, nil]]

          _ ->
            [:_values_, [nil, nil]]
        end
    end
  end

  def make_dispatch_macro_character(char, non_terminating_p \\ nil, readtable \\ nil) do
    {:readtable, tid} = resolve_rt(readtable)
    char_code = to_char_code(char)
    non_term = non_terminating_p not in [nil, false, :nil]

    [{:syntax, syn}] = :ets.lookup(tid, :syntax)
    [{:macros, mac}] = :ets.lookup(tid, :macros)

    new_syn =
      if non_term do
        Map.put(syn, char_code, :non_terminating_macro)
      else
        Map.put(syn, char_code, :terminating_macro)
      end

    new_mac = Map.put(mac, char_code, {fn _s, _c -> nil end, non_term})

    :ets.insert(tid, {:syntax, new_syn})
    :ets.insert(tid, {:macros, new_mac})
    :t
  end

  def set_dispatch_macro_character(disp_char, sub_char, function, readtable \\ nil) do
    {:readtable, tid} = resolve_rt(readtable)
    disp_code = to_char_code(disp_char)
    sub_code = to_char_code(sub_char) |> char_upcase()

    [{:dispatch_macros, disp}] = :ets.lookup(tid, :dispatch_macros)
    new_disp = Map.put(disp, {disp_code, sub_code}, function)
    :ets.insert(tid, {:dispatch_macros, new_disp})
    :t
  end

  def get_dispatch_macro_character(disp_char, sub_char, readtable \\ nil) do
    {:readtable, tid} = resolve_rt(readtable)
    disp_code = to_char_code(disp_char)
    sub_code = to_char_code(sub_char) |> char_upcase()

    [{:dispatch_macros, disp}] = :ets.lookup(tid, :dispatch_macros)
    Map.get(disp, {disp_code, sub_code}, nil)
  end

  def set_syntax_from_char(to_char, from_char, to_rt \\ nil, from_rt \\ nil) do
    {:readtable, src_tid} = resolve_rt(from_rt)
    {:readtable, dest_tid} = resolve_rt(to_rt)
    to_code = to_char_code(to_char)
    from_code = to_char_code(from_char)

    [{:syntax, src_syn}] = :ets.lookup(src_tid, :syntax)
    [{:macros, src_mac}] = :ets.lookup(src_tid, :macros)

    syntax = Map.get(src_syn, from_code, :constituent)
    macro_info =
      case Map.get(src_mac, from_code) do
        nil ->
          if from_code in [?(, ?), ?', ?;, ?\", ?`, ?,] do
            {fn _s, _c -> nil end, false}
          else
            nil
          end
        info ->
          info
      end

    [{:syntax, dest_syn}] = :ets.lookup(dest_tid, :syntax)
    [{:macros, dest_mac}] = :ets.lookup(dest_tid, :macros)

    new_dest_syn = Map.put(dest_syn, to_code, syntax)
    new_dest_mac =
      if macro_info do
        Map.put(dest_mac, to_code, macro_info)
      else
        Map.delete(dest_mac, to_code)
      end

    :ets.insert(dest_tid, {:syntax, new_dest_syn})
    :ets.insert(dest_tid, {:macros, new_dest_mac})
    :t
  end

  def readtable_case(readtable \\ nil) do
    {:readtable, tid} = resolve_rt(readtable)
    [{:case, c}] = :ets.lookup(tid, :case)
    c || :upcase
  end

  def set_readtable_case(readtable, new_case) do
    {:readtable, tid} = resolve_rt(readtable)
    c = normalize_case(new_case)
    :ets.insert(tid, {:case, c})
    c
  end

  # --- Helper functions ---

  defp resolve_rt(nil), do: current_readtable()
  defp resolve_rt({:readtable, _} = rt), do: rt
  defp resolve_rt(_), do: current_readtable()

  defp to_char_code(c) when is_integer(c), do: c
  defp to_char_code(s) when is_binary(s) and byte_size(s) > 0 do
    s |> String.to_charlist() |> hd()
  end
  defp to_char_code(a) when is_atom(a) do
    a |> Atom.to_string() |> String.to_charlist() |> hd()
  end
  defp to_char_code(_), do: ??

  defp char_upcase(c) when c >= ?a and c <= ?z, do: c - 32
  defp char_upcase(c), do: c

  defp normalize_case(k) when is_atom(k) do
    k_str = k |> Atom.to_string() |> String.trim_leading(":") |> String.downcase()
    case k_str do
      "upcase" -> :upcase
      "downcase" -> :downcase
      "preserve" -> :preserve
      "invert" -> :invert
      _ -> :upcase
    end
  end
  defp normalize_case(_), do: :upcase
end

