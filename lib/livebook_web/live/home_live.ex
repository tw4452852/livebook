defmodule LivebookWeb.HomeLive do
  use LivebookWeb, :live_view

  import LivebookWeb.SessionHelpers
  import LivebookWeb.UserHelpers

  alias LivebookWeb.{SidebarHelpers, ExploreHelpers}
  alias Livebook.{Sessions, Session, LiveMarkdown, Notebook, FileSystem}

  @impl true
  def mount(params, _session, socket) do
    if connected?(socket) do
      Livebook.Sessions.subscribe()
      Livebook.SystemResources.subscribe()
    end

    sessions = Sessions.list_sessions()
    notebook_infos = Notebook.Explore.visible_notebook_infos() |> Enum.take(3)

    {:ok,
     socket
     |> SidebarHelpers.shared_home_handlers()
     |> assign(
       self_path: Routes.home_path(socket, :page),
       file: determine_file(params),
       file_info: %{exists: true, access: :read_write},
       sessions: sessions,
       notebook_infos: notebook_infos,
       page_title: "Livebook",
       new_version: Livebook.UpdateCheck.new_version(),
       update_instructions_url: Livebook.Config.update_instructions_url(),
       app_service_url: Livebook.Config.app_service_url(),
       memory: Livebook.SystemResources.memory()
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex grow h-full">
      <.live_region role="alert" />
      <SidebarHelpers.sidebar>
        <SidebarHelpers.button_item
          icon="group-fill"
          label="Opens"
          button_attrs={[phx_click: show_opens_modal()]} />
        <SidebarHelpers.shared_home_footer socket={@socket} current_user={@current_user} />
      </SidebarHelpers.sidebar>
      <div class="grow overflow-y-auto">
        <.update_notification version={@new_version} instructions_url={@update_instructions_url} />
        <.memory_notification memory={@memory} app_service_url={@app_service_url} />
        <div class="max-w-screen-lg w-full mx-auto px-8 pt-8 pb-32 space-y-4">
          <div class="flex flex-col space-y-2 items-center pb-4 border-b border-gray-200
                      sm:flex-row sm:space-y-0 sm:justify-between">
            <div class="text-2xl text-gray-800 font-semibold">
              <img src="/images/logo-with-text.png" class="h-[50px]" alt="Livebook" />
              <h1 class="sr-only">Livebook</h1>
            </div>
            <div class="flex space-x-2 pt-2" role="navigation" aria-label="new notebook">
              <%= live_patch "Import",
                    to: Routes.home_path(@socket, :import, "url"),
                    class: "button-base button-outlined-gray whitespace-nowrap" %>
              <button class="button-base button-blue" phx-click="new">
                New notebook
              </button>
            </div>
          </div>

          <div class="h-80" role="region" aria-label="file system">
            <.live_component module={LivebookWeb.FileSelectComponent}
                id="home-file-select"
                file={@file}
                extnames={[LiveMarkdown.extension()]}
                running_files={files(@sessions)}>
              <div class="flex justify-end space-x-2">
                <button class="button-base button-outlined-gray whitespace-nowrap"
                  phx-click="fork"
                  disabled={not path_forkable?(@file, @file_info)}>
                  <.remix_icon icon="git-branch-line" class="align-middle mr-1" />
                  <span>Fork</span>
                </button>
                <%= if file_running?(@file, @sessions) do %>
                  <%= live_redirect "Join session",
                        to: Routes.session_path(@socket, :page, session_id_by_file(@file, @sessions)),
                        class: "button-base button-blue" %>
                <% else %>
                  <span {open_button_tooltip_attrs(@file, @file_info)}>
                    <button class="button-base button-blue"
                      phx-click="open"
                      disabled={not path_openable?(@file, @file_info, @sessions)}>
                      Open
                    </button>
                  </span>
                <% end %>
              </div>
            </.live_component>
          </div>

          <div class="py-12" data-el-explore-section role="region" aria-label="explore section">
            <div class="mb-4 flex justify-between items-center">
              <h2 class="uppercase font-semibold text-gray-500">
                Explore
              </h2>
              <%= live_redirect to: Routes.explore_path(@socket, :page),
                    class: "flex items-center text-blue-600" do %>
                <span class="font-semibold">See all</span>
                <.remix_icon icon="arrow-right-line" class="align-middle ml-1" />
              <% end %>
            </div>
            <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
              <%# Note: it's fine to use stateless components in this comprehension,
                  because @notebook_infos never change %>
              <%= for info <- @notebook_infos do %>
                <ExploreHelpers.notebook_card notebook_info={info} socket={@socket} />
              <% end %>
            </div>
          </div>
          <div id="running-sessions" class="py-12" role="region" aria-label="running sessions">
            <.live_component module={LivebookWeb.HomeLive.SessionListComponent}
              id="session-list"
              sessions={@sessions}
              memory={@memory} />
          </div>
        </div>
      </div>
    </div>

    <.current_user_modal current_user={@current_user} />
    <.opens_modal socket={@socket} />

    <%= if @live_action == :close_session do %>
      <.modal id="close-session-modal" show class="w-full max-w-xl" patch={@self_path}>
        <.live_component module={LivebookWeb.HomeLive.CloseSessionComponent}
          id="close-session"
          return_to={@self_path}
          session={@session} />
      </.modal>
    <% end %>

    <%= if @live_action == :import do %>
      <.modal id="import-modal" show class="w-full max-w-xl" patch={@self_path}>
        <.live_component module={LivebookWeb.HomeLive.ImportComponent}
          id="import"
          tab={@tab}
          import_opts={@import_opts} />
      </.modal>
    <% end %>

    <%= if @live_action == :edit_sessions do %>
      <.modal id="edit-sessions-modal" show class="w-full max-w-xl" patch={@self_path}>
        <.live_component module={LivebookWeb.HomeLive.EditSessionsComponent}
          id="edit-sessions"
          action={@bulk_action}
          return_to={@self_path}
          sessions={@sessions}
          selected_sessions={selected_sessions(@sessions, @selected_session_ids)} />
      </.modal>
    <% end %>
    """
  end

  defp open_button_tooltip_attrs(file, file_info) do
    if regular?(file, file_info) and not writable?(file_info) do
      [class: "tooltip top", data_tooltip: "This file is write-protected, please fork instead"]
    else
      []
    end
  end

  defp update_notification(%{version: nil} = assigns), do: ~H""

  defp update_notification(assigns) do
    ~H"""
    <div class="px-2 py-2 bg-blue-200 text-gray-900 text-sm text-center">
      <span>
        Livebook v<%= @version %> available!
        <%= if @instructions_url do %>
          Check out the news on
          <a class="font-medium border-b border-gray-900 hover:border-transparent" href="https://livebook.dev/" target="_blank">
            livebook.dev
          </a>
          and follow the
          <a class="font-medium border-b border-gray-900 hover:border-transparent" href={@instructions_url} target="_blank">
            update instructions
          </a>
        <% else %>
          Check out the news and installation steps on
          <a class="font-medium border-b border-gray-900 hover:border-transparent" href="https://livebook.dev/" target="_blank">livebook.dev</a>
        <% end %>
        🚀
      </span>
    </div>
    """
  end

  defp memory_notification(assigns) do
    ~H"""
    <%= if @app_service_url && @memory.free < 30_000_000 do %>
      <div class="px-2 py-2 bg-red-200 text-gray-900 text-sm text-center">
        <.remix_icon icon="alarm-warning-line" class="align-text-bottom mr-0.5" />
        Less than 30 MB of memory left, consider
        <a class="font-medium border-b border-gray-900 hover:border-transparent" href={@app_service_url} target="_blank">adding more resources to the instance</a>
        or closing
        <a class="font-medium border-b border-gray-900 hover:border-transparent" href="#running-sessions">running sessions</a>
      </div>
    <% end %>
    """
  end

  @impl true
  def handle_params(%{"session_id" => session_id}, _url, socket) do
    session = Enum.find(socket.assigns.sessions, &(&1.id == session_id))
    {:noreply, assign(socket, session: session)}
  end

  def handle_params(%{"action" => action}, _url, socket)
      when socket.assigns.live_action == :edit_sessions do
    {:noreply, assign(socket, bulk_action: action)}
  end

  def handle_params(%{"tab" => tab} = params, _url, socket)
      when socket.assigns.live_action == :import do
    import_opts = [url: params["url"]]
    {:noreply, assign(socket, tab: tab, import_opts: import_opts)}
  end

  def handle_params(%{"url" => url}, _url, socket)
      when socket.assigns.live_action == :public_import do
    origin = Notebook.ContentLoader.url_to_location(url)

    origin
    |> Notebook.ContentLoader.fetch_content_from_location()
    |> case do
      {:ok, content} ->
        socket = import_content(socket, content, origin: origin)
        {:noreply, socket}

      {:error, _message} ->
        {:noreply, push_patch(socket, to: Routes.home_path(socket, :import, "url", url: url))}
    end
  end

  def handle_params(%{"path" => path} = _params, _uri, socket)
      when socket.assigns.live_action == :public_open do
    path = Path.expand(path)
    file = FileSystem.File.local(path)

    if file_running?(file, socket.assigns.sessions) do
      session_id = session_id_by_file(file, socket.assigns.sessions)
      {:noreply, push_redirect(socket, to: Routes.session_path(socket, :page, session_id))}
    else
      {:noreply, open_notebook(socket, FileSystem.File.local(path))}
    end
  end

  def handle_params(_params, _url, socket), do: {:noreply, socket}

  @impl true
  def handle_event("new", %{}, socket) do
    {:noreply, create_session(socket)}
  end

  def handle_event("fork", %{}, socket) do
    file = socket.assigns.file

    socket =
      case import_notebook(file) do
        {:ok, {notebook, messages}} ->
          notebook = Notebook.forked(notebook)
          images_dir = Session.images_dir_for_notebook(file)

          socket
          |> put_import_warnings(messages)
          |> create_session(
            notebook: notebook,
            copy_images_from: images_dir,
            origin: {:file, file}
          )

        {:error, error} ->
          put_flash(socket, :error, Livebook.Utils.upcase_first(error))
      end

    {:noreply, socket}
  end

  def handle_event("open", %{}, socket) do
    file = socket.assigns.file
    {:noreply, open_notebook(socket, file)}
  end

  def handle_event("bulk_action", %{"action" => "disconnect"} = params, socket) do
    socket = assign(socket, selected_session_ids: params["session_ids"])
    {:noreply, push_patch(socket, to: Routes.home_path(socket, :edit_sessions, "disconnect"))}
  end

  def handle_event("bulk_action", %{"action" => "close_all"} = params, socket) do
    socket = assign(socket, selected_session_ids: params["session_ids"])
    {:noreply, push_patch(socket, to: Routes.home_path(socket, :edit_sessions, "close_all"))}
  end

  def handle_event("open_autosave_directory", %{}, socket) do
    file =
      Livebook.Settings.autosave_path()
      |> FileSystem.Utils.ensure_dir_path()
      |> FileSystem.File.local()

    file_info = %{exists: true, access: file_access(file)}
    {:noreply, assign(socket, file: file, file_info: file_info)}
  end

  @impl true
  def handle_info({:set_file, file, info}, socket) do
    file_info = %{exists: info.exists, access: file_access(file)}
    {:noreply, assign(socket, file: file, file_info: file_info)}
  end

  def handle_info({:session_created, session}, socket) do
    if session in socket.assigns.sessions do
      {:noreply, socket}
    else
      {:noreply, assign(socket, sessions: [session | socket.assigns.sessions])}
    end
  end

  def handle_info({:session_updated, session}, socket) do
    sessions =
      Enum.map(socket.assigns.sessions, fn other ->
        if other.id == session.id, do: session, else: other
      end)

    {:noreply, assign(socket, sessions: sessions)}
  end

  def handle_info({:session_closed, session}, socket) do
    sessions = Enum.reject(socket.assigns.sessions, &(&1.id == session.id))
    {:noreply, assign(socket, sessions: sessions)}
  end

  def handle_info({:import_content, content, session_opts}, socket) do
    socket = import_content(socket, content, session_opts)
    {:noreply, socket}
  end

  def handle_info({:memory_update, memory}, socket) do
    {:noreply, assign(socket, memory: memory)}
  end

  defp files(sessions) do
    Enum.map(sessions, & &1.file)
  end

  defp path_forkable?(file, file_info) do
    regular?(file, file_info)
  end

  defp path_openable?(file, file_info, sessions) do
    regular?(file, file_info) and not file_running?(file, sessions) and
      writable?(file_info)
  end

  defp regular?(file, file_info) do
    file_info.exists and not FileSystem.File.dir?(file)
  end

  defp writable?(file_info) do
    file_info.access in [:read_write, :write]
  end

  defp file_running?(file, sessions) do
    running_files = files(sessions)
    file in running_files
  end

  defp import_notebook(file) do
    with {:ok, content} <- FileSystem.File.read(file) do
      {:ok, LiveMarkdown.notebook_from_livemd(content)}
    end
  end

  defp session_id_by_file(file, sessions) do
    session = Enum.find(sessions, &(&1.file == file))
    session.id
  end

  defp import_content(socket, content, session_opts) do
    {notebook, messages} = Livebook.LiveMarkdown.notebook_from_livemd(content)

    socket =
      socket
      |> put_import_warnings(messages)
      |> put_flash(
        :info,
        "You have imported a notebook, no code has been executed so far. You should read and evaluate code as needed."
      )

    session_opts = Keyword.merge(session_opts, notebook: notebook)
    create_session(socket, session_opts)
  end

  defp file_access(file) do
    case FileSystem.File.access(file) do
      {:ok, access} -> access
      {:error, _} -> :none
    end
  end

  defp selected_sessions(sessions, selected_session_ids) do
    Enum.filter(sessions, &(&1.id in selected_session_ids))
  end

  defp determine_file(%{"path" => path} = _params) do
    path = Path.expand(path)

    cond do
      File.dir?(path) ->
        path
        |> FileSystem.Utils.ensure_dir_path()
        |> FileSystem.File.local()

      File.regular?(path) ->
        FileSystem.File.local(path)

      true ->
        Livebook.Config.local_filesystem_home()
    end
  end

  defp determine_file(_params), do: Livebook.Config.local_filesystem_home()

  defp open_notebook(socket, file) do
    case import_notebook(file) do
      {:ok, {notebook, messages}} ->
        socket
        |> put_import_warnings(messages)
        |> create_session(notebook: notebook, file: file, origin: {:file, file})

      {:error, error} ->
        put_flash(socket, :error, Livebook.Utils.upcase_first(error))
    end
  end
end
