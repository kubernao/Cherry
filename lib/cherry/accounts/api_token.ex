defmodule Cherry.Accounts.ApiToken do
  use Ecto.Schema
  import Ecto.Changeset

  alias Cherry.Accounts.User

  @scopes ~w(read write admin)

  schema "api_tokens" do
    field :name, :string
    field :token_hash, :string
    field :scopes, :string, default: "read"
    field :last_used_at, :utc_datetime
    field :revoked_at, :utc_datetime

    belongs_to :user, User

    timestamps(type: :utc_datetime)
  end

  def changeset(token, attrs) do
    token
    |> cast(attrs, [:name, :token_hash, :scopes, :last_used_at, :revoked_at, :user_id])
    |> validate_required([:name, :token_hash, :scopes, :user_id])
    |> validate_scopes()
    |> unique_constraint(:token_hash)
  end

  defp validate_scopes(changeset) do
    validate_change(changeset, :scopes, fn :scopes, scopes ->
      invalid =
        scopes
        |> String.split(",", trim: true)
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 in @scopes))

      if invalid == [],
        do: [],
        else: [scopes: "contains invalid scopes: #{Enum.join(invalid, ", ")}"]
    end)
  end
end
