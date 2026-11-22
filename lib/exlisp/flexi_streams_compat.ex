defmodule ExLisp.FlexiStreamsCompat do
  @moduledoc false

  def install do
    ExLisp.Package.ensure_tables()

    slot =
      {:list, 1,
       [
         {:id, 1, ["vector"]},
         {:lit, :initarg},
         {:lit, :vector}
       ]}

    ExLisp.CLOS.register_class(:vector_stream, [:fundamental_binary_stream], [slot])
    ExLisp.CLOS.register_class(:in_memory_input_stream, [:vector_stream], [])

    ExLisp.Env.put_fun(
      :"flexi-streams.make-in-memory-input-stream",
      ExLisp.Closure.new(&make_in_memory_input_stream/1, :make_in_memory_input_stream)
    )

    ExLisp.Env.put_fun(
      :"flex.vector-stream-vector",
      ExLisp.Closure.new(&vector_stream_vector/1, :vector_stream_vector)
    )

    ExLisp.Env.put_fun(
      :"flex.make-in-memory-input-stream",
      ExLisp.Closure.new(&make_in_memory_input_stream/1, :make_in_memory_input_stream)
    )

    :t
  end

  defp make_in_memory_input_stream([vector | _]) do
    ExLisp.CLOS.make_instance(:vector_stream, [:vector, vector])
  end

  defp vector_stream_vector([instance | _]), do: ExLisp.CLOS.slot_value(instance, :vector)
end
