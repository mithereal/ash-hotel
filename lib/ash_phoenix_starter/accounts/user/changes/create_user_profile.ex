defmodule AshPhoenixStarter.Accounts.User.Changes.CreateUserProfile do
  use Ash.Resource.Change

  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, &create_profile/2)
  end

  def atomic(changeset, opts, context) do
    {:ok, change(changeset, opts, context)}
  end

  defp create_profile(changeset, user) do
    [local_part | _] = String.split(to_string(user.email), "@")
    attrs = %{first_name: Phoenix.Naming.humanize(local_part), user_id: user.id}

    Ash.create(AshPhoenixStarter.Accounts.UserProfile, attrs, actor: user)
    {:ok, user}
  end
end
