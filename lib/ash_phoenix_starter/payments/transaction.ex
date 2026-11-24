defmodule AshPhoenixStarter.Payments.Transaction do
  use Ash.Resource,
      domain: AshPhoenixStarter.Payments.Domain,
      data_layer: AshPostgres.DataLayer,
      extensions: [AshStateMachine, AshOban],
      authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "ash_payment_transactions"
    repo AshPhoenixStarter.Repo
  end

  policies do
    policy action_type(:read) do
      authorize_if expr(property_id == ^actor(:property_id) or ^actor(:role) == :super_admin)
    end

    policy action([:initiate_authorization, :capture, :void, :webhook_transition]) do
      authorize_if expr(
                     (property_id == ^actor(:property_id) and ^actor(:role) in [:front_desk, :manager, :property_admin]) or
                     ^actor(:role) in [:super_admin, :system]
                   )
    end

    policy action(:refund) do
      authorize_if expr(
                     (property_id == ^actor(:property_id) and ^actor(:role) in [:manager, :property_admin]) or
                     ^actor(:role) == :super_admin
                   )
    end
  end

  state_machine do
    initial_states [:pending]
    default_initial_state :pending

    transitions do
      transition :authorize, from: :pending, to: [:authorized, :captured, :failed]
      transition :capture, from: [:pending, :authorized], to: [:captured, :failed]
      transition :void, from: :authorized, to: [:voided, :failed]
      transition :refund, from: :captured, to: [:refunded, :partially_refunded, :failed]
      transition :webhook_transition, from: [:pending, :authorized, :captured], to: [:authorized, :captured, :voided, :refunded, :failed]
    end
  end

  oban do
    triggers do
      # Automatically releases uncaptured security deposit holds 48 hours after checkout
      trigger :auto_release_expired_holds do
        action :void
        where expr(state == :authorized and hold_type == :security_deposit and release_after
        Ash.Changeset.after_action(changeset, fn _changeset, tx ->
          AshPhoenixStarter.Payments.Actions.DispatchProvider.run_authorize(tx, changeset.arguments.provider_opts)
        end)
      end
    end

    update :authorize do
      require_atomic? false
      accept [:provider_transaction_id, :redirect_url, :raw_response, :error_reason]
      argument :next_state, :atom, allow_nil?: false
      change transition_state(arg(:next_state))
    end

    update :capture do
      require_atomic? false
      argument :capture_amount, AshMoney.Types.Money
      change &AshPhoenixStarter.Payments.Actions.DispatchProvider.run_capture/2
    end

    update :void do
      require_atomic? false
      change &AshPhoenixStarter.Payments.Actions.DispatchProvider.run_void/2
    end

    update :refund do
      require_atomic? false
      argument :refund_amount, AshMoney.Types.Money, allow_nil?: false
      argument :reason, :string, default: "Guest refund"
      change &AshPhoenixStarter.Payments.Actions.DispatchProvider.run_refund/2
    end

    update :webhook_transition do
      require_atomic? false
      accept [:raw_response]
      argument :next_state, :atom, allow_nil?: false
      change transition_state(arg(:next_state))
    end
  end
end




