defmodule GodwokenExplorer.Transaction do
  use GodwokenExplorer, :schema

  import Ecto.Changeset

  alias GodwokenExplorer.Chain.Cache.Transactions

  @primary_key {:hash, :binary, autogenerate: false}
  schema "transactions" do
    field :args, :binary
    field :from_account_id, :integer
    field :nonce, :integer
    field :status, Ecto.Enum, values: [:committed, :finalized], default: :committed
    field :to_account_id, :integer
    field :type, Ecto.Enum, values: [:sudt, :polyjuice_creator, :polyjuice, :withdrawal]
    field :block_number, :integer
    field :block_hash, :binary

    belongs_to(:block, Block, foreign_key: :block_hash, references: :hash, define_field: false)

    timestamps()
  end

  def changeset(transaction, attrs) do
    transaction
    |> cast(attrs, [
      :hash,
      :block_hash,
      :type,
      :from_account_id,
      :to_account_id,
      :nonce,
      :args,
      :status,
      :block_number
    ])
    |> validate_required([
      :hash,
      :from_account_id,
      :to_account_id,
      :nonce,
      :args,
      :status,
      :block_number
    ])
  end

  def create_transaction(%{type: :sudt} = attrs) do
    transaction =
      %Transaction{}
      |> Transaction.changeset(attrs)
      |> Ecto.Changeset.put_change(:block_hash, attrs[:block_hash])
      |> Repo.insert()

    UDTTransfer.create_udt_transfer(attrs)
    transaction
  end

  def create_transaction(%{type: :polyjuice_creator} = attrs) do
    transaction =
      %Transaction{}
      |> Transaction.changeset(attrs)
      |> Ecto.Changeset.put_change(:block_hash, attrs[:block_hash])
      |> Repo.insert()

    PolyjuiceCreator.create_polyjuice_creator(attrs)
    transaction
  end

  def create_transaction(%{type: :withdrawal} = attrs) do
    transaction =
      %Transaction{}
      |> Transaction.changeset(attrs)
      |> Repo.insert()

    Withdrawal.create_withdrawal(attrs)
    transaction
  end

  def create_transaction(%{type: :polyjuice} = attrs) do
    transaction =
      %Transaction{}
      |> Transaction.changeset(attrs)
      |> Repo.insert()

    Polyjuice.create_polyjuice(attrs)
    transaction
  end

  def latest_10_records do
    case Transactions.all do
      txs when is_list(txs) and length(txs) == 10 ->
        txs |> Enum.map(fn t ->
          t |> Map.take([:hash, :from_account_id, :to_account_id, :type]) |> Map.merge(%{timestamp: t.block.timestamp, success: true})
        end)
      _ ->
        from(t in Transaction,
          join: b in Block,
          on: [hash: t.block_hash],
          select: %{
            hash: t.hash,
            timestamp: b.timestamp,
            from_account_id: t.from_account_id,
            to_account_id: t.to_account_id,
            type: t.type,
            success: true
          },
          order_by: [desc: t.block_number, desc: t.inserted_at],
          limit: 10
        )
        |> Repo.all()
    end
  end

  def find_by_hash(hash) do
    tx =
      from(t in Transaction,
        join: b in Block,
        on: [hash: t.block_hash],
        where: t.hash == ^hash,
        select: %{
          hash: t.hash,
          l2_block_number: t.block_number,
          timestamp: b.timestamp,
          l1_block_number: b.layer1_block_number,
          from: t.from_account_id,
          to: t.to_account_id,
          type: t.type,
          status: t.status,
          nonce: t.nonce,
          args: t.args
        }
      )
      |> Repo.one()
    case tx do
      nil -> %{}
      _ ->
        args = join_args(tx) || %{}
        tx |> Map.merge(args)
    end
  end

  def list_by_account_id(account_id) do
    from(t in Transaction,
      join: b in Block,
      on: [hash: t.block_hash],
      where: t.from_account_id == ^account_id or t.to_account_id == ^account_id,
      select: %{
        hash: t.hash,
        block_number: b.number,
        timestamp: b.timestamp,
        from: t.from_account_id,
        to: t.to_account_id,
        type: t.type
      },
      order_by: [desc: t.inserted_at]
    )
  end

  def account_transactions_data(account_id, page) do
    txs = list_by_account_id(account_id)
    original_struct = Repo.paginate(txs, page: page)
    parsed_result =
      Enum.map(original_struct.entries, fn record ->
        stringify_and_unix_maps(record)
      end)

    %{
      page: Integer.to_string(original_struct.page_number),
      total_count: Integer.to_string(original_struct.total_entries),
      txs: parsed_result
    }
  end

  defp join_args(%{type: :polyjuice, hash: tx_hash}) do
    from(p in Polyjuice,
      where: p.tx_hash == ^tx_hash,
      select: %{gas_price: p.gas_price}
    )
    |> Repo.one()
  end

  defp join_args(_) do
    %{}
  end
end
