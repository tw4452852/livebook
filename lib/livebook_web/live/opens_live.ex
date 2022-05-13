defmodule LivebookWeb.OpensLive do
  use LivebookWeb, :live_view

  import LivebookWeb.UserHelpers

  alias Livebook.Tracker

  @impl true
  def mount(_param, _session, socket) do
    Phoenix.PubSub.subscribe(Livebook.PubSub, "tracker_opens")

    {:ok,
     socket
     |> assign(:opens, Tracker.list_opens())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="p-6 flex flex-col space-y-5">
      <h3 class="text-2xl font-semibold text-gray-800">
         Opens per user
       </h3>
       <%= for {user, count} <- @opens do %>
         <div class="flex items-center justify-between space-x-2">
           <.user_avatar user={user} class="shrink-0 h-7 w-7" text_class="text-xs" />
           <span><%= user.name || user.id |> binary_part(0, 4) %></span>
           <span><%= count %></span>
         </div>
       <% end %>
    </div>
    """
  end

  @impl true
  def handle_info({:opens_change}, socket) do
    {:noreply, assign(socket, :opens, Tracker.list_opens())}
  end
end
