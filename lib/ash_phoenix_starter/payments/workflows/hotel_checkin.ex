defmodule AshPhoenixStarter.Payments.Workflows.CheckInWorkflow do
  use Ash.Reactor

  input :actor
  input :property_id
  input :reservation_id
  input :provider_id
  # e.g., Money.new(:MXN, "4800.00")
  input :room_total_money
  # e.g., Money.new(:MXN, "1500.00")
  input :security_deposit_money
  # DateTime of guest checkout
  input :checkout_at
  input :payment_method_opts

  step :authorize_room_stay do
    argument :actor, input(:actor)
    argument :property_id, input(:property_id)
    argument :reservation_id, input(:reservation_id)
    argument :provider_id, input(:provider_id)
    argument :amount, input(:room_total_money)
    argument :opts, input(:payment_method_opts)

    run fn args, _context ->
      AshPhoenixStarter.Payments.Transaction
      |> Ash.Changeset.for_create(
        :initiate_authorization,
        %{
          property_id: args.property_id,
          reservation_id: args.reservation_id,
          provider_id: args.provider_id,
          idempotency_key: "stay_#{args.reservation_id}",
          hold_type: :room_stay,
          amount: args.amount,
          provider_opts: args.opts
        },
        actor: args.actor
      )
      |> Ash.create()
    end

    compensate fn tx, args, _context ->
      if tx.state == :authorized do
        tx
        |> Ash.Changeset.for_update(:void, %{}, actor: args.actor)
        |> Ash.update()
      end

      :ok
    end
  end

  step :capture_room_stay do
    argument :actor, input(:actor)
    argument :tx, result(:authorize_room_stay)

    run fn %{tx: tx, actor: actor}, _context ->
      if tx.state == :authorized do
        tx
        |> Ash.Changeset.for_update(:capture, %{}, actor: actor)
        |> Ash.update()
      else
        {:ok, tx}
      end
    end
  end

  step :hold_security_deposit do
    argument :actor, input(:actor)
    argument :property_id, input(:property_id)
    argument :reservation_id, input(:reservation_id)
    argument :provider_id, input(:provider_id)
    argument :deposit, input(:security_deposit_money)
    argument :checkout_at, input(:checkout_at)
    argument :opts, input(:payment_method_opts)

    run fn args, _context ->
      # Schedule automatic deposit release 48 hours after guest checkout
      release_after = DateTime.add(args.checkout_at, 48, :hour)

      AshPhoenixStarter.Payments.Transaction
      |> Ash.Changeset.for_create(
        :initiate_authorization,
        %{
          property_id: args.property_id,
          reservation_id: args.reservation_id,
          provider_id: args.provider_id,
          idempotency_key: "deposit_#{args.reservation_id}",
          hold_type: :security_deposit,
          amount: args.deposit,
          release_after: release_after,
          provider_opts: args.opts
        },
        actor: args.actor
      )
      |> Ash.create()
    end
  end

  return :hold_security_deposit
end
