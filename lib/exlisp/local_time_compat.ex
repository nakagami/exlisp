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

    :t
  end

  def now(_args), do: {:local_time_timestamp, DateTime.utc_now()}

  def today(_args) do
    {:local_time_timestamp, Date.utc_today() |> DateTime.new!(~T[00:00:00], "Etc/UTC")}
  end

  def timestamp_year([timestamp | _]), do: datetime(timestamp).year

  def timestamp_century([timestamp | _]) do
    year = datetime(timestamp).year
    sign = if year < 0, do: -1, else: 1
    sign + sign * div(abs(year) - 1, 100)
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
end
