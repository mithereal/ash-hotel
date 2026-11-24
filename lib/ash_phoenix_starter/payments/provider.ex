defmodule AshPhoenixStarter.Payments.Provider do
  @type amount_cents :: pos_integer()
  @type currency :: String.t()
  @type config :: map()
  @type transaction_id :: String.t()
  @type provider_response :: %{
          required(:transaction_id) => transaction_id(),
          required(:status) => :authorized | :captured | :pending | :failed,
          optional(:raw_response) => map(),
          optional(:redirect_url) => String.t() | nil
        }

  @callback metadata() :: %{
              id: String.t(),
              name: String.t(),
              regions: [String.t()],
              currencies: [String.t()],
              supports_holds?: boolean()
            }

  @callback config_schema() :: [{String.t(), atom(), keyword()}]

  @callback authorize(amount_cents(), currency(), opts :: keyword()) ::
              {:ok, provider_response()} | {:error, term()}

  @callback capture(transaction_id(), opts :: keyword()) ::
              {:ok, provider_response()} | {:error, term()}

  @callback void(transaction_id(), opts :: keyword()) ::
              {:ok, provider_response()} | {:error, term()}

  @callback refund(transaction_id(), amount_cents(), opts :: keyword()) ::
              {:ok, provider_response()} | {:error, term()}

  @callback handle_webhook(raw_body :: binary(), headers :: map(), config()) ::
              {:ok, %{event: atom(), transaction_id: transaction_id(), raw: map()}}
              | {:error, term()}
end
