defmodule Cherry.Accounts do
  import Ecto.Query

  alias Cherry.Accounts.{ApiToken, User}
  alias Cherry.Repo

  @token_prefix "cherry_"

  def get_user!(id), do: Repo.get!(User, id)

  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: String.downcase(email))
  end

  def ensure_owner!(attrs) do
    case Repo.one(from u in User, limit: 1) do
      nil ->
        {:ok, user} =
          %User{}
          |> User.changeset(%{
            email: attrs.email |> String.downcase(),
            password: attrs.password
          })
          |> Repo.insert()

        user

      user ->
        user
    end
  end

  def owner_exists? do
    Repo.exists?(from u in User, limit: 1)
  end

  def authenticate_user(email, password) do
    user = get_user_by_email(email || "")

    cond do
      user && valid_password?(user, password || "") -> {:ok, user}
      true -> :error
    end
  end

  def valid_password?(%User{hashed_password: encoded}, password) do
    with ["pbkdf2_sha256", iterations, salt, expected] <- String.split(encoded, "$"),
         {iterations, ""} <- Integer.parse(iterations),
         {:ok, salt} <- Base.decode64(salt),
         {:ok, expected} <- Base.decode64(expected) do
      actual = :crypto.pbkdf2_hmac(:sha256, password, salt, iterations, byte_size(expected))
      Plug.Crypto.secure_compare(actual, expected)
    else
      _ -> false
    end
  end

  def create_api_token(%User{} = user, attrs) do
    raw = @token_prefix <> Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)

    changeset =
      ApiToken.changeset(%ApiToken{}, %{
        user_id: user.id,
        name: Map.get(attrs, :name, "CLI token"),
        scopes: Map.get(attrs, :scopes, "read,write"),
        token_hash: hash_token(raw)
      })

    with {:ok, token} <- Repo.insert(changeset) do
      {:ok, raw, token}
    end
  end

  def authenticate_api_token(raw) when is_binary(raw) do
    query =
      from token in ApiToken,
        where: token.token_hash == ^hash_token(raw) and is_nil(token.revoked_at),
        preload: [:user]

    case Repo.one(query) do
      nil ->
        :error

      token ->
        token
        |> ApiToken.changeset(%{last_used_at: DateTime.utc_now() |> DateTime.truncate(:second)})
        |> Repo.update()

        {:ok, token}
    end
  end

  def authenticate_api_token(_), do: :error

  def token_has_scope?(%ApiToken{scopes: scopes}, required) do
    split = scopes |> String.split(",", trim: true) |> Enum.map(&String.trim/1)
    "admin" in split or to_string(required) in split
  end

  defp hash_token(raw), do: :crypto.hash(:sha256, raw) |> Base.encode16(case: :lower)
end
