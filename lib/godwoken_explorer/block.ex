defmodule GodwokenExplorer.Block do
  use GodwokenExplorer, :schema

  import Ecto.Changeset
  import GodwokenRPC.Util, only: [utc_to_unix: 1]

  @fields [
    :hash,
    :parent_hash,
    :number,
    :timestamp,
    :status,
    :aggregator_id,
    :transaction_count,
    :layer1_tx_hash,
    :layer1_block_number,
    :size,
    :tx_fees,
    :average_gas_price
  ]
  @required_fields [
    :hash,
    :parent_hash,
    :number,
    :timestamp,
    :status,
    :aggregator_id,
    :transaction_count
  ]

  @primary_key {:hash, :binary, autogenerate: false}
  schema "blocks" do
    field :number, :integer
    field :parent_hash, :binary
    field :timestamp, :utc_datetime_usec
    field :status, Ecto.Enum, values: [:committed, :finalized], default: :committed
    field :aggregator_id, :integer
    field :transaction_count, :integer
    field :layer1_tx_hash, :binary
    field :layer1_block_number, :integer
    field :size, :integer
    field :tx_fees, :integer
    field :average_gas_price, :decimal

    has_many :transactions, GodwokenExplorer.Transaction, foreign_key: :block_hash

    timestamps()
  end

  @doc false
  def changeset(block, attrs) do
    block
    |> cast(attrs, @fields)
    |> validate_required(@required_fields)
  end

  def create_block(attrs \\ %{}) do
    %Block{}
    |> Block.changeset(attrs)
    |> Repo.insert()
  end

  def find_by_number_or_hash("0x" <> _ = param) do
    from(b in Block, where: b.hash == ^param) |> Repo.one()
  end

  def find_by_number_or_hash(number_string) when is_binary(number_string) do
    from(b in Block, where: b.number == ^number_string) |> Repo.one()
  end

  def get_next_number do
    case Repo.one(from block in Block, order_by: [desc: block.number], limit: 1) do
      %Block{number: number} -> number + 1
      nil -> 0
    end
  end

  def latest_10_records do
    from(b in "blocks",
      select: %{
        hash: b.hash,
        number: b.number,
        timestamp: b.timestamp,
        tx_count: b.transaction_count
      },
      order_by: [desc: b.number],
      limit: 10
    )
    |> Repo.all()
    |> Enum.map(fn record ->
      Map.replace(record, :timestamp, utc_to_unix(record[:timestamp]))
    end)
  end

  def transactions_count_per_second(interval \\ 10) do
    with timestamp_with_tx_count when length(timestamp_with_tx_count) != 0 <-
           from(b in Block,
             select: %{timestamp: b.timestamp, tx_count: b.transaction_count},
             order_by: [desc: b.number],
             limit: ^interval
           )
           |> Repo.all(),
         all_tx_count when all_tx_count != 0 <-
           timestamp_with_tx_count
           |> Enum.map(fn %{timestamp: _, tx_count: tx_count} -> tx_count end)
           |> Enum.sum() do
      %{timestamp: last_timestamp, tx_count: _} = timestamp_with_tx_count |> List.first()
      %{timestamp: first_timestamp, tx_count: _} = timestamp_with_tx_count |> List.last()
      (NaiveDateTime.diff(last_timestamp, first_timestamp) / all_tx_count) |> Float.floor(1)
    end
  end

  def update_blocks_finalized(latest_finalized_block_number) do
    from(b in Block, where: b.number <= ^latest_finalized_block_number and b.status == :committed)
    |> Repo.update_all(set: [status: "finalized", updated_at: DateTime.now!("Etc/UTC")])

    from(t in Transaction,
      where: t.block_number <= ^latest_finalized_block_number and t.status == :unfinalized
    )
    |> Repo.update_all(set: [status: "finalized", updated_at: DateTime.now!("Etc/UTC")])
  end

  def bind_l1_l2_block(l2_block_number, l1_block_number, l1_tx_hash) do
    with %Block{} = block <- Repo.get_by(Block, number: l2_block_number) do
      block
      |> Ecto.Changeset.change(%{layer1_block_number: l1_block_number, layer1_tx_hash: l1_tx_hash})
      |> Repo.update!()
    end
  end

  def find_last_bind_l1_block() do
    from(b in Block,
      where: not is_nil(b.layer1_block_number),
      order_by: [desc: :number],
      limit: 1
    )
    |> Repo.one()
  end
end
