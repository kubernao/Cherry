defmodule Cherry.Workspace.DeletionPurger do
  use GenServer

  alias Cherry.Workspace

  @initial_delay :timer.seconds(5)
  @interval :timer.hours(24)

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    Process.send_after(self(), :purge, @initial_delay)
    {:ok, %{}}
  end

  @impl true
  def handle_info(:purge, state) do
    _ = Workspace.purge_deleted_items()
    Process.send_after(self(), :purge, @interval)
    {:noreply, state}
  end
end
