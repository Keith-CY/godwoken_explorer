defmodule GodwokenExplorer.Chain.Cache.Blocks do
  @moduledoc """
  Caches the last imported blocks
  """

  alias GodwokenExplorer.Block

  use GodwokenExplorer.Chain.OrderedCache,
    name: :blocks,
    max_size: 10,
    ids_list_key: "block_numbers",
    ttl_check_interval: Application.get_env(:godwoken_explorer, __MODULE__)[:ttl_check_interval]

  @type id :: non_neg_integer()

  def element_to_id(%Block{number: number}), do: number

  def drop_nonconsensus(numbers) when is_nil(numbers) or numbers == [], do: :ok

  def drop_nonconsensus(numbers) when is_list(numbers) do
    ConCache.update(cache_name(), ids_list_key(), fn ids ->
      nonconsensus = MapSet.new(numbers)

      {lost_consensus, kept_consensus} = Enum.split_with(ids, &MapSet.member?(nonconsensus, &1))

      # immediately delete the blocks that lost consensus
      Enum.each(lost_consensus, &ConCache.delete(cache_name(), &1))

      # ids_list is set to never expire
      {:ok, %ConCache.Item{value: kept_consensus, ttl: :infinity}}
    end)
  end

  def drop_nonconsensus(number) when not is_nil(number), do: drop_nonconsensus([number])
end
