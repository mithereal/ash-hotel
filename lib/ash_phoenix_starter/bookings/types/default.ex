# lib/ash_phoenix_starter/bookings/types/default_handler.ex
defmodule AshPhoenixStarter.Bookings.Types.DefaultHandler do
  @moduledoc """
  Fallback booking handler inheriting default no-op lifecycle callbacks.
  """
  use AshPhoenixStarter.Bookings.BookingHandler
end
