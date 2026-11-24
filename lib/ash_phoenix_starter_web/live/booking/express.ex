defmodule HotelWeb.ExpressBookingLive do
  use PlatformWeb, :live_view

  alias Hotel.FrontDesk.Reservation
  alias Platform.Payments.Registry

  @available_rooms [
    %{number: "101", type: "Standard King", rate: Money.new(:USD, "129.00")},
    %{number: "102", type: "Standard King", rate: Money.new(:USD, "129.00")},
    %{number: "103", type: "Double Queen", rate: Money.new(:USD, "149.00")},
    %{number: "201", type: "Deluxe Suite", rate: Money.new(:USD, "199.00")},
    %{number: "202", type: "Executive King", rate: Money.new(:USD, "229.00")}
  ]

  @impl true
  def mount(params, _session, socket) do
    source_terminal = Map.get(params, "source", "window-main")
    today = Date.utc_today()
    tomorrow = Date.add(today, 1)

    # Filter out CashDesk for unattended window QR self-bookings
    online_providers =
      Registry.list_providers()
      |> Enum.reject(&(&1.id() == :cash_desk))

    default_provider = List.first(online_providers)
    default_room = List.first(@available_rooms)

    socket =
      socket
      |> assign(:source_terminal, source_terminal)
      |> assign(:rooms, @available_rooms)
      |> assign(:selected_room, default_room)
      |> assign(:nights, 1)
      |> assign(:providers, online_providers)
      |> assign(:selected_provider, default_provider)
      |> assign(:completed_booking, nil)
      |> assign(:form, build_express_form(default_room, default_provider, today, tomorrow, 1, source_terminal))
      |> allow_upload(:license_pic,
           accept: ~w(.jpg .jpeg .png .webp),
           max_entries: 1,
           max_file_size: 10_000_000
         )

    {:ok, socket}
  end

  defp build_express_form(room, provider, check_in, check_out, nights, source) do
    provider_id = if provider, do: Atom.to_string(provider.id()), else: "stripe"
    total = Money.mult!(room.rate, nights)

    Reservation
    |> AshPhoenix.Form.for_create(:create)
    |> AshPhoenix.Form.validate(%{
      "booking_ref" => "QR-#{System.unique_integer([:positive])}",
      "room_number" => room.number,
      "check_in_date" => Date.to_iso8601(check_in),
      "check_out_date" => Date.to_iso8601(check_out),
      "payment_provider" => provider_id,
      "status" => "check_in",
      "notes" => "Self-booked via QR terminal: #{source}",
      "total_amount" => %{
        "amount" => Decimal.to_string(total.amount),
        "currency" => Atom.to_string(total.currency)
      }
    })
    |> to_form()
  end

  @impl true
  def handle_event("select_room", %{"number" => room_number}, socket) do
    room = Enum.find(@available_rooms, &(&1.number == room_number))
    total = Money.mult!(room.rate, socket.assigns.nights)

    updated_params =
      (socket.assigns.form.params || %{})
      |> Map.put("room_number", room.number)
      |> Map.put("total_amount", %{
        "amount" => Decimal.to_string(total.amount),
        "currency" => Atom.to_string(total.currency)
      })

    form =
      socket.assigns.form.source
      |> AshPhoenix.Form.validate(updated_params)
      |> to_form()

    {:noreply, socket |> assign(:selected_room, room) |> assign(:form, form)}
  end

  @impl true
  def handle_event("update_nights", %{"nights" => nights_str}, socket) do
    nights = max(1, String.to_integer(nights_str))
    check_in = Date.utc_today()
    check_out = Date.add(check_in, nights)
    total = Money.mult!(socket.assigns.selected_room.rate, nights)

    updated_params =
      (socket.assigns.form.params || %{})
      |> Map.put("check_in_date", Date.to_iso8601(check_in))
      |> Map.put("check_out_date", Date.to_iso8601(check_out))
      |> Map.put("total_amount", %{
        "amount" => Decimal.to_string(total.amount),
        "currency" => Atom.to_string(total.currency)
      })

    form =
      socket.assigns.form.source
      |> AshPhoenix.Form.validate(updated_params)
      |> to_form()

    {:noreply, socket |> assign(:nights, nights) |> assign(:form, form)}
  end

  @impl true
  def handle_event("select_provider", %{"provider" => provider_id}, socket) do
    {:ok, provider_mod} = Registry.fetch(provider_id)

    updated_params =
      Map.put(socket.assigns.form.params || %{}, "payment_provider", provider_id)

    form =
      socket.assigns.form.source
      |> AshPhoenix.Form.validate(updated_params)
      |> to_form()

    {:noreply, socket |> assign(:selected_provider, provider_mod) |> assign(:form, form)}
  end

  @impl true
  def handle_event("validate", %{"form" => params}, socket) do
    {:noreply, assign(socket, :form, AshPhoenix.Form.validate(socket.assigns.form, params))}
  end

  @impl true
  def handle_event("submit_express_booking", %{"form" => params}, socket) do
    uploaded_urls =
      consume_uploaded_entries(socket, :license_pic, fn %{path: path}, entry ->
        dest = Path.join(["priv/static/uploads/licenses", "#{Ash.UUID.generate()}-#{entry.client_name}"])
        File.mkdir_p!(Path.dirname(dest))
        File.cp!(path, dest)
        {:ok, "/uploads/licenses/#{Path.basename(dest)}"}
      end)

    params =
      case uploaded_urls do
        [url | _] -> Map.put(params, "license_image_url", url)
        [] -> params
      end

    case AshPhoenix.Form.submit(socket.assigns.form, params: params) do
      {:ok, reservation} ->
        {:noreply,
          socket
          |> assign(:completed_booking, reservation)
          |> put_flash(:info, "Room booked! Front desk has been notified to complete your key & contract.")}

      {:error, form} ->
        {:noreply, assign(socket, :form, form)}
    end
  end

  @impl true
  def render(assigns) do
    total_price = Money.mult!(assigns.selected_room.rate, assigns.nights)
    assigns = assign(assigns, :total_price, total_price)

    ~H"""
        <div class="min-h-screen bg-slate-950 text-slate-100 py-8 px-4">
          <div class="max-w-md mx-auto">
            <div class="text-center mb-6">
              <span class="text-[11px] uppercase tracking-widest px-2.5 py-1 rounded-full bg-indigo-500/10 text-indigo-400 border border-indigo-500/30">
                Express Window Check-In • <%= @source_terminal %>
              </span>
              <h1 class="text-2xl font-bold text-white mt-3">Instant Room Booking</h1>
              <p class="text-xs text-slate-400 mt-1">
                Select a room, snap your ID, and pay. Staff will meet you to finalize your contract.
              </p>
            </div>

            <%= if @completed_booking do %>
              <!-- Confirmation Screen -->
              <div class="bg-slate-900 border border-emerald-500/40 rounded-2xl p-6 text-center space-y-4 shadow-xl">
                <div class="w-12 h-12 rounded-full bg-emerald-500/20 text-emerald-400 flex items-center justify-center mx-auto text-xl font-bold">
                  ✓
                </div>
                <h2 class="text-lg font-bold text-white">Reservation Confirmed</h2>
                <p class="text-xs text-slate-300">
                  Reference <span class="font-mono text-indigo-400 font-bold"><%= @completed_booking.booking_ref %></span>
                  for <strong class="text-white">Room <%= @completed_booking.room_number %></strong>.
                </p>
                <div class="bg-slate-950 rounded-xl p-4 text-left text-xs space-y-2 border border-slate-800">
                  <div class="flex justify-between">
                    <span class="text-slate-500">Guest:</span>
                    <span class="text-slate-200"><%= @completed_booking.guest_name %></span>
                  </div>
                  <div class="flex justify-between">
                    <span class="text-slate-500">Paid:</span>
                    <span class="text-emerald-400 font-semibold"><%= Money.to_string!(@completed_booking.total_amount) %></span>
                  </div>
                  <div class="flex justify-between">
                    <span class="text-slate-500">Status:</span>
                    <span class="text-amber-300">Staff Notified — Contract Ready</span>
                  </div>
                </div>
                <p class="text-[11px] text-slate-400">
                  Your account has been created under <strong><%= @completed_booking.guest_email %></strong>.
                </p>
              </div>
            <% else %>
              <!-- Express Self-Booking Form -->
              <.form for={@form} phx-change="validate" phx-submit="submit_express_booking" class="space-y-5 bg-slate-900 border border-slate-800 rounded-2xl p-5 shadow-xl">
                <input type="hidden" name="form[booking_ref]" value={@form[:booking_ref].value} />
                <input type="hidden" name="form[room_number]" value={@selected_room.number} />
                <input type="hidden" name="form[check_in_date]" value={@form[:check_in_date].value} />
                <input type="hidden" name="form[check_out_date]" value={@form[:check_out_date].value} />
                <input type="hidden" name="form[status]" value="check_in" />
                <input type="hidden" name="form[notes]" value={@form[:notes].value} />
                <input type="hidden" name="form[total_amount][amount]" value={Decimal.to_string(@total_price.amount)} />
                <input type="hidden" name="form[total_amount][currency]" value={Atom.to_string(@total_price.currency)} />

                <!-- Step 1: Room Selection -->
                <div>
                  <label class="block text-xs font-semibold uppercase tracking-wider text-slate-400 mb-2">
                    1. Choose Available Room
                  </label>
                  <div class="grid grid-cols-1 gap-2">
                    <%= for room <- @rooms do %>
                      <% active = @selected_room.number == room.number %>
                      <button
                        type="button"
                        phx-click="select_room"
                        phx-value-number={room.number}
                        class={[
                          "flex items-center justify-between p-3 rounded-xl border text-left transition",
                          if(active,
                            do: "bg-indigo-600/20 border-indigo-500 text-white",
    else: "bg-slate-950 border-slate-800 text-slate-300 hover:border-slate-700"
    )
    ]}
    >

    Room <%= room.number %> — <%= room.type %>
    Ready for immediate check-in


    <%= Money.to_string!(room.rate) %>/nt


    <% end %>

    Number of Nights
    <%= for n <- 1..7 do %>
    <option value={n} selected={@nights == n}>
    <%= n %> <%= if n == 1, do: "Night", else: "Nights" %> — <%= Money.to_string!(Money.mult!(@selected_room.rate, n)) %>

    <% end %>

    1. Your Details (Creates Guest Account)
    1. Snap Driver's License / ID
    <.live_file_input
    upload={@uploads.license_pic}
    class="block w-full text-xs text-slate-400 file:mr-3 file:py-2 file:px-3 file:rounded-lg file:border-0 file:text-xs file:font-semibold file:bg-indigo-600 file:text-white"
    />
    <%= for entry <- @uploads.license_pic.entries do %>

    <.live_img_preview entry={entry} class="h-16 w-28 object-cover rounded-lg border border-slate-700" />
    <%= entry.progress %>% uploaded

    <% end %>

    1. Payment Method
    <input
    type="hidden"
    name="form[payment_provider]"
    value={@selected_provider && Atom.to_string(@selected_provider.id())}
    />
    <%= for provider <- @providers do %>
    <% active = @selected_provider && @selected_provider.id() == provider.id() %>
    <button
    type="button"
    phx-click="select_provider"
    phx-value-provider={Atom.to_string(provider.id())}
    class={[
    "p-2.5 rounded-xl border text-xs font-semibold text-center transition",
    if(active,
    do: "bg-indigo-600/20 border-indigo-500 text-white",
    else: "bg-slate-950 border-slate-800 text-slate-400"
    )
    ]}
    >
    <%= provider.label() %>

    <% end %>
    <%= if @selected_provider && @selected_provider.client_hook() do %>
    <div
    id={"express-hook-#{@selected_provider.id()}"}
    phx-hook={@selected_provider.client_hook()}
    phx-update="ignore"
    class="p-3 rounded-xl bg-slate-950 border border-slate-800 text-xs text-slate-400"
    >
    Secure <%= @selected_provider.label() %> Checkout Ready



    <% end %>
    Pay <%= Money.to_string!(@total_price) %> & Notify Front Desk

    </.form>
    <% end %>


    """
  end
end