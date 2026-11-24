# lib/ash_phoenix_starter/bookings/booking_handler.ex
defmodule AshPhoenixStarter.Bookings.BookingHandler do
  alias AshPhoenixStarter.Bookings.Booking
  alias AshPhoenixStarter.Bookings.Workers.BookingNotificationWorker

  @callback validate_custom_rules(changeset :: Ash.Changeset.t(), actor :: term()) ::
              Ash.Changeset.t()

  @callback on_booked(booking :: Booking.t(), actor :: term()) ::
              {:ok, term()} | {:error, term()}

  @callback on_updated(booking :: Booking.t(), actor :: term()) ::
              {:ok, term()} | {:error, term()}

  @callback on_cancelled(booking :: Booking.t(), actor :: term()) ::
              {:ok, term()} | {:error, term()}

  @optional_callbacks [on_updated: 2, on_cancelled: 2]

  @doc """
  Enqueues an asynchronous Oban job to notify all booking attendees.
  """
  def notify_attendees(%Booking{} = booking, event)
      when event in [:booked, :updated, :cancelled] do
    tenant = Map.get(booking.__metadata__, :tenant)

    %{
      booking_id: booking.id,
      tenant: tenant,
      event: Atom.to_string(event)
    }
    |> BookingNotificationWorker.new()
    |> Oban.insert()
  end

  defmacro __using__(_opts) do
    quote do
      @behaviour AshPhoenixStarter.Bookings.BookingHandler
      import AshPhoenixStarter.Bookings.BookingHandler, only: [notify_attendees: 2]

      @impl true
      def validate_custom_rules(changeset, _actor), do: changeset

      @impl true
      def on_booked(booking, _actor) do
        notify_attendees(booking, :booked)
        {:ok, booking}
      end

      @impl true
      def on_updated(booking, _actor) do
        notify_attendees(booking, :updated)
        {:ok, booking}
      end

      @impl true
      def on_cancelled(booking, _actor) do
        notify_attendees(booking, :cancelled)
        {:ok, booking}
      end

      defoverridable validate_custom_rules: 2,
                     on_booked: 2,
                     on_updated: 2,
                     on_cancelled: 2
    end
  end
end
