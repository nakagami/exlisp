defmodule ExLisp.GrayStreamsCompat do
  @moduledoc false

  @generic_names [
    :stream_write_byte,
    :stream_write_sequence,
    :stream_write_char,
    :stream_write_string,
    :stream_element_type,
    :stream_finish_output,
    :stream_file_position,
    :open_stream_p
  ]

  def install do
    ExLisp.Package.ensure_tables()

    for class <- [
          :fundamental_stream,
          :fundamental_input_stream,
          :fundamental_output_stream,
          :fundamental_character_stream,
          :fundamental_binary_stream
        ] do
      ExLisp.CLOS.register_class(class, [], [], [])
    end

    Enum.each(@generic_names, fn name ->
      generic_args =
        case name do
          n when n in [:stream_write_sequence, :stream_write_string] ->
            List.duplicate(:t, 4)

          :stream_write_byte ->
            [:t, :t]

          :stream_write_char ->
            [:t, :t]

          _ ->
            [:t]
        end

      ExLisp.CLOS.register_generic(name, generic_args)
    end)

    ExLisp.CLOS.register_method(
      :stream_element_type,
      nil,
      [:t],
      &ExLisp.Stream.stream_element_type/1
    )

    ExLisp.CLOS.register_method(:open_stream_p, nil, [:t], &ExLisp.Stream.open_stream_p/1)

    :t
  end
end
