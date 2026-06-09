defmodule Mix.Tasks.Cherry.Backup do
  use Mix.Task

  @shortdoc "Copies the SQLite database to a timestamped backup file"

  def run(_args) do
    Mix.Task.run("app.start")

    repo_config = Cherry.Repo.config()
    database = Keyword.fetch!(repo_config, :database)
    backup_dir = System.get_env("BACKUP_DIR") || Path.join(Path.dirname(database), "backups")
    File.mkdir_p!(backup_dir)

    timestamp = DateTime.utc_now() |> Calendar.strftime("%Y%m%d%H%M%S")
    target = Path.join(backup_dir, "cherry-#{timestamp}.db")

    Cherry.Repo.query!("VACUUM INTO ?", [target])
    Mix.shell().info("Wrote #{target}")
  end
end
