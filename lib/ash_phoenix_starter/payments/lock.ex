defmodule Hotel.Payments.Lock do
  @doc """
  Acquires a cluster-wide lock for a reservation during payment execution.
  Uses Horde.Registry when :cluster_backend == :horde, or :global otherwise.
  """
  def with_reservation_lock(reservation_id, fun) when is_function(fun, 0) do
    lock_key = {:reservation_payment_lock, reservation_id}

    if Application.get_env(:hotel, :cluster_backend) == :horde and
         Code.ensure_loaded?(Horde.Registry) do
      case Horde.Registry.register(Hotel.Payments.HordeRegistry, lock_key, :locked) do
        {:ok, _pid} ->
          try do
            fun.()
          after
            Horde.Registry.unregister(Hotel.Payments.HordeRegistry, lock_key)
          end

        {:error, {:already_registered, _pid}} ->
          {:error, :payment_in_progress}
      end
    else
      :global.trans({lock_key, self()}, fun, [node() | Node.list()], 0)
      |> case do
        :aborted -> {:error, :payment_in_progress}
        result -> result
      end
    end
  end
end
