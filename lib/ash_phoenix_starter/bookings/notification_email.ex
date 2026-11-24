defmodule AshPhoenixStarter.Bookings.NotificationEmail do
  import Swoosh.Email

  def build(booking, attendee, event) do
    resource_name =
      case booking.resource do
        %{name: name} when is_binary(name) -> name
        _ -> "Scheduled Resource"
      end

    recipient_email =
      attendee.email ||
        case Map.get(attendee, :user) do
          %{email: email} -> to_string(email)
          _ -> nil
        end

    recipient_name = attendee.name || recipient_email || "Guest"

    from_email =
      Application.get_env(:AshPhoenixStarter, :mailer_from_email, "noreply@example.com")

    from_name = Application.get_env(:AshPhoenixStarter, :mailer_from_name, "Bookings")

    {subject, headline, body_intro} =
      case event do
        :booked ->
          {
            "Booking Confirmed: #{resource_name}",
            "Your booking is confirmed",
            "You have been scheduled for #{resource_name}."
          }

        :updated ->
          {
            "Booking Rescheduled: #{resource_name}",
            "Your booking details were updated",
            "The schedule or details for #{resource_name} have been updated."
          }

        :cancelled ->
          {
            "Booking Cancelled: #{resource_name}",
            "Your booking has been cancelled",
            "The booking for #{resource_name} has been cancelled."
          }
      end

    new()
    |> to({recipient_name, recipient_email})
    |> from({from_name, from_email})
    |> subject(subject)
    |> text_body("""
    Hi #{recipient_name},

    #{headline}
    #{body_intro}

    Resource: #{resource_name}
    Start: #{Calendar.strftime(booking.start_time, "%B %d, %Y at %I:%M %p UTC")}
    End: #{Calendar.strftime(booking.end_time, "%B %d, %Y at %I:%M %p UTC")}
    #{if booking.notes not in [nil, ""], do: "Notes: #{booking.notes}\n", else: ""}
    """)
  end
end
