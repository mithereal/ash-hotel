defmodule AshPhoenixStarterWeb.Components.FolioLedger do
  use Phoenix.Component

  attr :accounts, :list, required: true

  def chart_of_accounts_bar(assigns) do
    ~H"""
    <div class="grid grid-cols-2 lg:grid-cols-4 gap-3">
      <%= for acct <- @accounts do %>
        <div class="bg-slate-900 border border-slate-800 rounded-xl p-3.5">
          <div class="flex items-center justify-between text-[11px] text-slate-400">
            <span class="font-mono text-indigo-400">{acct.code}</span>
            <span class="uppercase tracking-wider text-[10px] px-1.5 py-0.5 rounded bg-slate-800 text-slate-300">
              {acct.category}
            </span>
          </div>
          <div class="text-xs font-medium text-slate-300 mt-1 truncate">{acct.name}</div>
          <div class="text-lg font-bold text-white mt-1.5 font-mono">
            {Money.to_string!(acct.net_balance || Money.zero(acct.currency))}
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  attr :reservation, :map, required: true
  attr :entries, :list, required: true

  def folio_postings(assigns) do
    ~H"""
    <div class="bg-slate-900 border border-slate-800 rounded-xl p-4 space-y-4">
      <div class="flex items-center justify-between border-b border-slate-800 pb-3">
        <div>
          <h3 class="text-xs font-bold uppercase tracking-wider text-slate-300">
            Double-Entry Folio Ledger
          </h3>
          <p class="text-[11px] text-slate-500">
            Ref: <span class="font-mono text-indigo-400">{@reservation.booking_ref}</span>
          </p>
        </div>

        <%= if @reservation.status != :check_out do %>
          <button
            type="button"
            phx-click="checkout_reservation"
            phx-value-id={@reservation.id}
            class="bg-emerald-600 hover:bg-emerald-500 text-white text-[11px] font-semibold px-3 py-1.5 rounded-lg transition"
          >
            Check Out & Post Revenue
          </button>
        <% else %>
          <span class="text-[10px] uppercase tracking-wider px-2 py-1 rounded bg-slate-800 text-emerald-400 border border-emerald-500/30">
            Revenue Recognized
          </span>
        <% end %>
      </div>

      <%= if Enum.empty?(@entries) do %>
        <p class="text-xs text-slate-500 text-center py-4">
          No journal entries recorded for this reservation yet.
        </p>
      <% else %>
        <div class="space-y-3 max-h-80 overflow-y-auto pr-1">
          <%= for entry <- @entries do %>
            <div class="bg-slate-950 border border-slate-800 rounded-lg p-3 text-xs space-y-2">
              <div class="flex items-center justify-between">
                <span class="font-mono font-semibold text-indigo-400">{entry.reference}</span>
                <span class="text-[10px] text-slate-500">
                  {Calendar.strftime(entry.posted_at, "%b %d, %H:%M UTC")}
                </span>
              </div>
              <p class="text-[11px] text-slate-400">{entry.description}</p>

              <table class="w-full text-[11px] border-t border-slate-800/80 pt-1.5">
                <thead>
                  <tr class="text-slate-500 text-left">
                    <th class="py-1 font-medium">Account</th>
                    <th class="py-1 text-right font-medium">Debit</th>
                    <th class="py-1 text-right font-medium">Credit</th>
                  </tr>
                </thead>
                <tbody class="divide-y divide-slate-900">
                  <%= for p <- entry.postings do %>
                    <tr>
                      <td class="py-1 text-slate-300">
                        <span class="font-mono text-slate-500 mr-1">{p.account.code}</span>
                        {p.account.name}
                      </td>
                      <td class="py-1 text-right font-mono text-emerald-400">
                        {if p.direction == :debit, do: Money.to_string!(p.amount), else: "—"}
                      </td>
                      <td class="py-1 text-right font-mono text-amber-300">
                        {if p.direction == :credit, do: Money.to_string!(p.amount), else: "—"}
                      </td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            </div>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end
end
