defmodule AshPhoenixStarterWeb.Components.RetroDateComponent do
  use AshPhoenixStarterWeb, :html

  attr :date, :any, default: nil, doc: "A Date, NaiveDateTime, or DateTime struct"

  attr :font, :string,
    default: "font-newspaper",
    doc: "Tailwind font class (e.g., font-newspaper, font-typewriter)"

  attr :class, :string, default: "", doc: "Optional custom CSS classes"

  def retro_date(assigns) do
    date = assigns.date || Date.utc_today()

    day_name = Calendar.strftime(date, "%A")
    month_name = Calendar.strftime(date, "%B")
    day_num = Calendar.strftime(date, "%d")
    year = Calendar.strftime(date, "%Y")

    assigns =
      assigns
      |> assign(:day_name, day_name)
      |> assign(:month_name, month_name)
      |> assign(:day_num, day_num)
      |> assign(:year, year)

    ~H"""
    <div class={[
      "flex items-center justify-center py-3 px-1 border-y-2 border-current bg-transparent text-white select-none",
      @font,
      @class
    ]}>
      <!-- Center Date Display -->
      <div class="text-center">
        <span class="block text-xs uppercase tracking-widest font-semibold border-b border-current pb-0.5 mb-0.5 opacity-90">
          {@day_name}
        </span>
        <span class="text-sm font-bold tracking-wider uppercase">
          {@month_name} {@day_num}, {@year}
        </span>
      </div>
    </div>
    """
  end
end
