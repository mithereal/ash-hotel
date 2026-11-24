defmodule HotelWeb.FrontDeskLive do
  use HotelWeb, :live_view

  alias Hotel.FrontDesk.{Booking, QRCode}
  alias Hotel.Payments.Registry

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      HotelWeb.Endpoint.subscribe("front_desk:bookings:created")
      HotelWeb.Endpoint.subscribe("front_desk:bookings:updated")
      HotelWeb.Endpoint.subscribe("front_desk:bookings:finalized")
    end

    providers = Registry.list_providers()
    default_provider = List.first(providers)

    socket =
      socket
      |> assign(:providers, providers)
      |> assign(:selected_provider, default_provider)
      |> assign(:pending_bookings, Ash.read!(Booking, action: :pending_review))
      |> assign(:active_booking, nil)
      |> assign(:window_qr_svg, QRCode.window_booking_svg(HotelWeb.Endpoint.url()))
      |> assign(:form, build_checkin_form(default_provider))
      |> allow_upload(:license_pic,
        accept: ~w(.jpg .jpeg .png .webp),
        max_entries: 1,
        max_file_size: 10_000_000
      )

    {:ok, socket}
  end

  defp build_checkin_form(provider) do
    provider_id = if provider, do: Atom.to_string(provider.id()), else: ""

    Booking
    |> AshPhoenix.Form.for_create(:create, forms: [])
    |> AshPhoenix.Form.validate(%{"payment_provider" => provider_id})
    |> to_form()
  end

  @impl true
  def handle_event("select_provider", %{"provider" => provider_id}, socket) do
    {:ok, provider_mod} = Registry.fetch_provider(provider_id)

    form =
      socket.assigns.form.source
      |> AshPhoenix.Form.validate(
        Map.put(socket.assigns.form.params || %{}, "payment_provider", provider_id)
      )
      |> to_form()

    {:noreply,
     socket
     |> assign(:selected_provider, provider_mod)
     |> assign(:form, form)}
  end

  @impl true
  def handle_event("validate", %{"form" => params}, socket) do
    form = AshPhoenix.Form.validate(socket.assigns.form, params)
    {:noreply, assign(socket, :form, form)}
  end

  @impl true
  def handle_event("save_checkin", %{"form" => params}, socket) do
    uploaded_urls =
      consume_uploaded_entries(socket, :license_pic, fn %{path: path}, entry ->
        dest =
          Path.join([
            "priv/static/uploads/licenses",
            "#{Ash.UUID.generate()}-#{entry.client_name}"
          ])

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
      {:ok, booking} ->
        {:noreply,
         socket
         |> put_flash(
           :info,
           "Authorized via #{booking.payment_provider} (#{booking.payment_transaction_id}). Ready to sign contract."
         )
         |> assign(:active_booking, booking)
         |> assign(:pending_bookings, Ash.read!(Booking, action: :pending_review))
         |> assign(:form, build_checkin_form(socket.assigns.selected_provider))}

      {:error, form} ->
        {:noreply, assign(socket, :form, form)}
    end
  end

  @impl true
  def handle_event("select_booking", %{"id" => id}, socket) do
    {:noreply, assign(socket, :active_booking, Ash.get!(Booking, id))}
  end

  @impl true
  def handle_event("clear_active", _params, socket) do
    {:noreply, assign(socket, :active_booking, nil)}
  end

  @impl true
  def handle_event("complete_contract", %{"booking_id" => id, "room_number" => room}, socket) do
    booking = Ash.get!(Booking, id)
    {:ok, _finalized} = Ash.update(booking, %{room_number: room}, action: :finalize_contract)

    {:noreply,
     socket
     |> put_flash(:info, "Room #{room} checked in and guest account activated.")
     |> assign(:active_booking, nil)
     |> assign(:pending_bookings, Ash.read!(Booking, action: :pending_review))}
  end

  @impl true
  def handle_info(%{topic: "front_desk:bookings:" <> _}, socket) do
    pending = Ash.read!(Booking, action: :pending_review)

    active =
      if socket.assigns.active_booking do
        Ash.get!(Booking, socket.assigns.active_booking.id)
      else
        nil
      end

    {:noreply,
     socket
     |> assign(:pending_bookings, pending)
     |> assign(:active_booking, active)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-slate-950 text-slate-100 flex flex-col font-sans">
      <!-- PMS Top Application Bar -->
      <header class="h-14 bg-slate-900 border-b border-slate-800 px-6 flex items-center justify-between">
        <div class="flex items-center gap-3">
          <span class="h-2.5 w-2.5 rounded-full bg-emerald-400 animate-pulse"></span>
          <h1 class="font-semibold tracking-wide text-sm uppercase text-slate-200">
            Front Desk Operations Console
          </h1>
          <span class="text-xs px-2 py-0.5 rounded bg-slate-800 text-slate-400 border border-slate-700">
            GraphQL / Scanner Sync Active
          </span>
        </div>
        <div class="flex items-center gap-4 text-xs text-slate-400">
          <span>
            Active Gateways: <strong class="text-slate-200">{length(@providers)}</strong>
          </span>
          <span>
            Pending Contracts: <strong class="text-amber-400">{length(@pending_bookings)}</strong>
          </span>
        </div>
      </header>

      <div class="flex-1 grid grid-cols-1 lg:grid-cols-12 overflow-hidden">
        <!-- Left Rail: Incoming QR & Mobile Queue -->
        <aside class="lg:col-span-3 bg-slate-900/60 border-r border-slate-800 flex flex-col">
          <div class="p-4 border-b border-slate-800 flex items-center justify-between">
            <h2 class="text-xs font-bold uppercase tracking-wider text-slate-400">
              Arrivals & QR Queue
            </h2>
            <span class="text-xs bg-amber-500/10 text-amber-400 border border-amber-500/30 px-2 py-0.5 rounded-full">
              {length(@pending_bookings)}
            </span>
          </div>

          <div class="flex-1 overflow-y-auto divide-y divide-slate-800/80">
            <div :if={Enum.empty?(@pending_bookings)} class="p-6 text-center text-xs text-slate-500">
              No pending QR self-bookings. Waiting for window scans or walk-ins.
            </div>

            <button
              :for={b <- @pending_bookings}
              type="button"
              phx-click="select_booking"
              phx-value-id={b.id}
              class={[
                "w-full text-left p-4 transition hover:bg-slate-800/60 flex items-start justify-between gap-2",
                @active_booking && @active_booking.id == b.id &&
                  "bg-slate-800 border-l-2 border-indigo-500"
              ]}
            >
              <div>
                <p class="font-medium text-sm text-slate-100">{b.guest_name}</p>
                <p class="text-xs text-slate-400 mt-0.5">
                  Room <span class="text-slate-200 font-semibold">{b.room_number}</span>
                  • ${format_cents(b.amount_cents)}
                </p>
                <span class="inline-block mt-1.5 text-[10px] uppercase tracking-wider px-1.5 py-0.5 rounded bg-slate-800 text-slate-300 border border-slate-700">
                  {b.payment_provider}
                </span>
              </div>
              <span class={[
                "text-[10px] px-2 py-0.5 rounded font-medium",
                if(b.license_image_url,
                  do: "bg-emerald-500/10 text-emerald-400",
                  else: "bg-rose-500/10 text-rose-400"
                )
              ]}>
                {if b.license_image_url, do: "ID Ready", else: "Needs ID"}
              </span>
            </button>
          </div>
        </aside>
        
    <!-- Center Pane: Walk-In Check-In & Pluggable Payment Terminal -->
        <main class="lg:col-span-6 p-6 overflow-y-auto space-y-6">
          <div class="bg-slate-900 border border-slate-800 rounded-xl p-6 shadow-xl">
            <div class="flex items-center justify-between border-b border-slate-800 pb-4 mb-5">
              <div>
                <h2 class="text-base font-semibold text-white">Walk-In Registration & Terminal</h2>
                <p class="text-xs text-slate-400">
                  Capture government ID, authorize payment, and provision guest account
                </p>
              </div>
              <span class="text-xs font-mono text-indigo-400 bg-indigo-500/10 border border-indigo-500/30 px-2.5 py-1 rounded">
                NEW FOLIO
              </span>
            </div>

            <.form for={@form} phx-change="validate" phx-submit="save_checkin" class="space-y-5">
              <!-- Guest Details -->
              <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
                <div>
                  <label class="block text-xs font-medium text-slate-400 mb-1">
                    Guest Full Name
                  </label>
                  <input
                    type="text"
                    name="form[guest_name]"
                    value={@form[:guest_name].value}
                    required
                    class="w-full bg-slate-950 border border-slate-700 rounded-lg px-3 py-2 text-sm text-white focus:border-indigo-500 focus:outline-none"
                  />
                </div>
                <div>
                  <label class="block text-xs font-medium text-slate-400 mb-1">
                    Guest Email (Account Login)
                  </label>
                  <input
                    type="email"
                    name="form[guest_email]"
                    value={@form[:guest_email].value}
                    required
                    class="w-full bg-slate-950 border border-slate-700 rounded-lg px-3 py-2 text-sm text-white focus:border-indigo-500 focus:outline-none"
                  />
                </div>
              </div>

              <div class="grid grid-cols-1 sm:grid-cols-3 gap-4">
                <div>
                  <label class="block text-xs font-medium text-slate-400 mb-1">Mobile Phone</label>
                  <input
                    type="tel"
                    name="form[phone]"
                    value={@form[:phone].value}
                    class="w-full bg-slate-950 border border-slate-700 rounded-lg px-3 py-2 text-sm text-white focus:border-indigo-500 focus:outline-none"
                  />
                </div>
                <div>
                  <label class="block text-xs font-medium text-slate-400 mb-1">
                    Room Assignment
                  </label>
                  <input
                    type="text"
                    name="form[room_number]"
                    value={@form[:room_number].value}
                    required
                    class="w-full bg-slate-950 border border-slate-700 rounded-lg px-3 py-2 text-sm text-white focus:border-indigo-500 focus:outline-none"
                  />
                </div>
                <div>
                  <label class="block text-xs font-medium text-slate-400 mb-1">
                    Charge Amount (Cents)
                  </label>
                  <input
                    type="number"
                    name="form[amount_cents]"
                    value={@form[:amount_cents].value}
                    min="0"
                    required
                    class="w-full bg-slate-950 border border-slate-700 rounded-lg px-3 py-2 text-sm text-white focus:border-indigo-500 focus:outline-none"
                  />
                </div>
              </div>
              
    <!-- Driver's License / ID Capture -->
              <div class="space-y-2">
                <label class="block text-xs font-medium text-slate-400">
                  Driver's License / ID Capture
                </label>
                <p class="text-xs text-slate-500">
                  Drop file, camera capture, or push via GraphQL Scanner
                </p>
                <.live_file_input
                  upload={@uploads.license_pic}
                  class="block w-full text-xs text-slate-400 file:mr-3 file:py-1.5 file:px-3 file:rounded file:border-0 file:text-xs file:font-semibold file:bg-slate-800 file:text-slate-200 hover:file:bg-slate-700"
                />

                <div :for={entry <- @uploads.license_pic.entries} class="flex items-center gap-3 pt-2">
                  <.live_img_preview entry={entry} class="h-20 w-32 object-cover rounded" />
                  <div class="text-xs text-slate-300 space-y-1">
                    <p>{entry.client_name}</p>
                    <p class="text-slate-400">Upload progress: {entry.progress}%</p>
                  </div>
                </div>
              </div>
              
    <!-- Select Payment Provider -->
              <div class="space-y-2">
                <label class="block text-xs font-medium text-slate-400">
                  Select Payment Provider
                </label>
                <input
                  type="hidden"
                  name="form[payment_provider]"
                  value={@selected_provider && Atom.to_string(@selected_provider.id())}
                />
                <div class="grid grid-cols-2 sm:grid-cols-3 gap-2">
                  <button
                    :for={provider <- @providers}
                    type="button"
                    phx-click="select_provider"
                    phx-value-provider={Atom.to_string(provider.id())}
                    class={[
                      "px-3 py-2.5 rounded-lg border text-left text-xs font-medium transition",
                      if(@selected_provider && @selected_provider.id() == provider.id(),
                        do: "bg-indigo-600/20 border-indigo-500 text-white",
                        else: "bg-slate-950 border-slate-800 text-slate-400 hover:border-slate-700"
                      )
                    ]}
                  >
                    <div class="font-semibold">{provider.label()}</div>
                    <div class="text-[10px] text-slate-500 mt-0.5">ID: {provider.id()}</div>
                  </button>
                </div>
              </div>
              
    <!-- Provider Hook or Cash Terminal -->
              <div
                :if={@selected_provider}
                class="bg-slate-950 border border-slate-800 rounded-lg p-4"
              >
                <%= if @selected_provider.client_hook() do %>
                  <div
                    id={"payment-hook-#{@selected_provider.id()}"}
                    phx-hook={@selected_provider.client_hook()}
                    phx-update="ignore"
                    class="text-xs text-slate-400"
                  >
                    Mounting {@selected_provider.label()} secure terminal...
                  </div>
                <% else %>
                  <div>
                    <label class="block text-xs font-medium text-slate-400 mb-1">
                      Cash Tendered (Cents)
                    </label>
                    <input
                      type="number"
                      name="form[cash_tendered_cents]"
                      value={@form[:cash_tendered_cents].value}
                      min="0"
                      class="w-full bg-slate-900 border border-slate-700 rounded-lg px-3 py-2 text-sm text-white focus:border-indigo-500 focus:outline-none"
                    />
                  </div>
                <% end %>
              </div>

              <button
                type="submit"
                class="w-full py-2.5 px-4 rounded-lg bg-indigo-600 hover:bg-indigo-500 text-white text-sm font-semibold transition"
              >
                Authorize Payment & Provision Guest Account
              </button>
            </.form>
          </div>
        </main>
        
    <!-- Right Rail: Contract & ID Inspector + Window QR -->
        <aside class="lg:col-span-3 bg-slate-900/60 border-l border-slate-800 p-5 overflow-y-auto space-y-6">
          <div class="bg-slate-900 border border-slate-800 rounded-xl p-4 space-y-4">
            <div class="flex items-start justify-between gap-2 border-b border-slate-800 pb-3">
              <div>
                <h2 class="text-xs font-bold uppercase tracking-wider text-slate-400">
                  Contract & ID Inspector
                </h2>
              </div>
              <button
                :if={@active_booking}
                type="button"
                phx-click="clear_active_booking"
                class="text-xs text-slate-400 hover:text-white"
              >
                Close
              </button>
            </div>

            <%= if @active_booking do %>
              <div class="space-y-3 text-xs">
                <div>
                  <p class="font-semibold text-sm text-white">{@active_booking.guest_name}</p>
                  <p class="text-slate-400">{@active_booking.guest_email}</p>
                </div>

                <div class="grid grid-cols-2 gap-2 bg-slate-950 p-3 rounded-lg border border-slate-800">
                  <div>
                    <span class="text-slate-500 block">Gateway:</span>
                    <span class="text-slate-200 font-medium">{@active_booking.payment_provider}</span>
                  </div>
                  <div>
                    <span class="text-slate-500 block">Tx Ref:</span>
                    <span class="text-slate-200 font-mono truncate block">
                      {@active_booking.payment_transaction_id || "—"}
                    </span>
                  </div>
                  <div class="col-span-2">
                    <span class="text-slate-500 block">Account ID:</span>
                    <span class="text-slate-200 font-mono">
                      {@active_booking.guest_account_id || "Pending"}
                    </span>
                  </div>
                </div>

                <div>
                  <p class="text-slate-400 font-medium mb-1.5">Government ID on File</p>
                  <%= if @active_booking.license_image_url do %>
                    <img
                      src={@active_booking.license_image_url}
                      alt="Guest government ID"
                      class="w-full h-36 object-cover rounded-lg border border-slate-800"
                    />
                  <% else %>
                    <div class="p-3 rounded-lg bg-slate-950 border border-dashed border-slate-800 text-slate-500">
                      Awaiting ID scan from desktop scanner or mobile app via GraphQL...
                    </div>
                  <% end %>
                </div>

                <button
                  type="button"
                  phx-click="sign_contract"
                  phx-value-id={@active_booking.id}
                  class="w-full py-2 px-3 rounded-lg bg-emerald-600 hover:bg-emerald-500 text-white font-semibold transition"
                >
                  Confirm Room #{@active_booking.room_number} • Sign Contract & Check In
                </button>
              </div>
            <% else %>
              <p class="text-xs text-slate-500">
                Select a guest from the left queue or complete a walk-in payment to inspect their ID and sign the contract.
              </p>
            <% end %>
          </div>
          
    <!-- Window Self-Book QR -->
          <div class="bg-slate-900 border border-slate-800 rounded-xl p-4 text-center space-y-2">
            <h3 class="text-xs font-bold uppercase tracking-wider text-slate-400">
              Window Self-Book QR
            </h3>
            <p class="text-[11px] text-slate-500">
              Scans route to Express Booking & push alert your phone
            </p>
            <div class="flex justify-center pt-2 bg-white p-3 rounded-lg">
              {Phoenix.HTML.raw(@window_qr_svg)}
            </div>
          </div>
        </aside>
      </div>
    </div>
    """
  end

  defp format_cents(cents) when is_integer(cents) do
    :erlang.float_to_binary(cents / 100, decimals: 2)
  end

  defp format_cents(_), do: "0.00"
end
