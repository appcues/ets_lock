defmodule EtsLockTest do
  use ExUnit.Case
  import EtsLock
  doctest EtsLock

  test "ttl" do
    table = :ets.new(:ttl_test, [:duplicate_bag, :public])
    key = :random.uniform() |> to_string

    spawn(fn ->
      with_ets_lock(
        table,
        key,
        fn _ -> Process.sleep(200) end,
        ttl: 100
      )
    end)

    spawn(fn ->
      assert {:ok, _} =
               with_ets_lock(
                 table,
                 key,
                 fn _ -> :ets.insert(table, {key, :yup}) end,
                 timeout: 150
               )
    end)

    Process.sleep(200)

    assert [{^key, :yup}] = :ets.lookup(table, key)
  end
end
