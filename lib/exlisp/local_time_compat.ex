defmodule ExLisp.LocalTimeCompat do
  @moduledoc false

  @epoch 62_167_219_200

  def install do
    ExLisp.Package.ensure_tables()
    package = ExLisp.Package.find_package!("LOCAL-TIME")

    %{
      now: &now/1,
      today: &today/1,
      timestamp_year: &timestamp_year/1,
      timestamp_century: &timestamp_century/1,
      timestamp_month: &timestamp_month/1,
      timestamp_day: &timestamp_day/1,
      timestamp_hour: &timestamp_hour/1,
      timestamp_minute: &timestamp_minute/1,
      timestamp_second: &timestamp_second/1,
      timestamp_millisecond: &timestamp_millisecond/1,
      timestamp_microsecond: &timestamp_microsecond/1,
      timestamp_day_of_week: &timestamp_day_of_week/1,
      timestamp_plus: &timestamp_plus/1,
      timestamp_minus: &timestamp_minus/1,
      timestamp_difference: &timestamp_difference/1,
      timestamp_lt: &timestamp_compare(&1, :lt),
      timestamp_le: &timestamp_compare(&1, :le),
      timestamp_eq: &timestamp_compare(&1, :eq),
      timestamp_ge: &timestamp_compare(&1, :ge),
      timestamp_gt: &timestamp_compare(&1, :gt),
      timestamp_to_universal: &timestamp_to_universal/1,
      universal_to_timestamp: &universal_to_timestamp/1,
      encode_timestamp: &encode_timestamp/1,
      format_timestring: &format_timestring/1
    }
    |> Enum.each(fn {name, function} ->
      closure = ExLisp.Closure.new(function, name, package: package.name)

      for package_name <- [package.name | package.nicknames],
          separator <- [".", ":"] do
        ExLisp.Env.put_fun(:"#{String.downcase(package_name)}#{separator}#{name}", closure)
      end
    end)

    aliases = %{
      timestamp_plus: ["timestamp+"],
      timestamp_minus: ["timestamp-"],
      timestamp_lt: ["timestamp<"],
      timestamp_le: ["timestamp<="],
      timestamp_eq: ["timestamp="],
      timestamp_ge: ["timestamp>="],
      timestamp_gt: ["timestamp>"]
    }

    Enum.each(aliases, fn {source, names} ->
      closure = ExLisp.Env.get_fun(:"local-time.#{source}")

      if closure do
        for separator <- [".", ":"], name <- names do
          ExLisp.Env.put_fun(:"local-time#{separator}#{name}", closure)
        end
      end
    end)

    :t
  end

  def now(_args), do: {:local_time_timestamp, DateTime.utc_now()}

  def today(_args) do
    {:local_time_timestamp, Date.utc_today() |> DateTime.new!(~T[00:00:00], "Etc/UTC")}
  end

  def timestamp_year([timestamp | _]), do: datetime(timestamp).year
  def timestamp_month([timestamp | _]), do: datetime(timestamp).month
  def timestamp_day([timestamp | _]), do: datetime(timestamp).day
  def timestamp_hour([timestamp | _]), do: datetime(timestamp).hour
  def timestamp_minute([timestamp | _]), do: datetime(timestamp).minute
  def timestamp_second([timestamp | _]), do: datetime(timestamp).second
  def timestamp_millisecond([timestamp | _]), do: datetime(timestamp).microsecond |> div(1_000)
  def timestamp_microsecond([timestamp | _]), do: datetime(timestamp).microsecond

  def timestamp_day_of_week([timestamp | _]) do
    timestamp |> datetime() |> DateTime.to_date() |> Date.day_of_week() |> rem(7)
  end

  def timestamp_century([timestamp | _]) do
    year = datetime(timestamp).year
    sign = if year < 0, do: -1, else: 1
    sign + sign * div(abs(year) - 1, 100)
  end

  def timestamp_plus([timestamp, amount, unit | _opts]) do
    seconds = to_seconds(amount, unit)
    {:local_time_timestamp, DateTime.add(datetime(timestamp), seconds, :second)}
  end

  def timestamp_minus([timestamp, amount, unit | _opts]) do
    {:local_time_timestamp, DateTime.add(datetime(timestamp), -to_seconds(amount, unit), :second)}
  end

  def timestamp_difference([left, right]) do
    DateTime.diff(datetime(left), datetime(right), :microsecond) / 1_000_000
  end

  def timestamp_compare(args, relation) do
    comparisons =
      args
      |> Enum.map(fn value -> datetime(value) |> DateTime.to_unix(:microsecond) end)
      |> Enum.chunk_every(2, 1, :discard)

    Enum.all?(comparisons, fn [left, right] ->
      case relation do
        :lt -> left < right
        :le -> left <= right
        :eq -> left == right
        :ge -> left >= right
        :gt -> left > right
      end
    end)
    |> ExLisp.Builtins.lisp_bool()
  end

  def timestamp_to_universal([timestamp | _]) do
    DateTime.to_unix(datetime(timestamp)) + @epoch
  end

  def universal_to_timestamp([universal | opts]) do
    nsec = ExLisp.Builtins.parse_lisp_keywords(opts)[:nsec] || 0
    unix = universal - @epoch

    {:local_time_timestamp,
     DateTime.from_unix!(unix) |> DateTime.add(div(nsec, 1_000), :microsecond)}
  end

  def encode_timestamp([nsec, second, minute, hour, day, month, year | _]) do
    {:ok, datetime} =
      DateTime.new(Date.new!(year, month, day), Time.new!(hour, minute, second), "Etc/UTC")

    {:local_time_timestamp, DateTime.add(datetime, div(nsec, 1_000), :microsecond)}
  end

  def format_timestring([destination | args]) do
    format = fn timestamp ->
      DateTime.to_iso8601(datetime(timestamp))
    end

    case destination do
      nil -> format.(List.last(args) || today([]))
      true -> format.(List.last(args) || today([]))
      _ -> format.(destination)
    end
  end

  defp datetime({:local_time_timestamp, %DateTime{} = value}), do: value
  defp datetime(%DateTime{} = value), do: value

  defp datetime({:instance, :timestamp, tid}) do
    day = ExLisp.CLOS.slot_value({:instance, :timestamp, tid}, :day) || 0
    sec = ExLisp.CLOS.slot_value({:instance, :timestamp, tid}, :sec) || 0
    DateTime.from_unix!(day * 86400 + sec)
  end

  defp to_seconds(value, unit) when is_number(value) do
    case unit do
      :second -> value
      :seconds -> value
      :minute -> value * 60
      :minutes -> value * 60
      :hour -> value * 3_600
      :hours -> value * 3_600
      :day -> value * 86_400
      :days -> value * 86_400
      :week -> value * 604_800
      :weeks -> value * 604_800
      _ -> value
    end
  end
end
