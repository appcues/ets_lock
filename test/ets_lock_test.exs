defmodule EtsLockTest do
  use ExUnit.Case
  import EtsLock
  doctest EtsLock

  test "exec_timeout" do
    table = :ets.new(:exec_timeout_test, [:duplicate_bag, :public])
    key = :key

    spawn(fn ->
      assert {:error, :exec_timeout} =
               with_ets_lock(
                 table,
                 key,
                 fn _ -> Process.sleep(200) end,
                 exec_timeout: 100
               )
    end)

    spawn(fn ->
      assert {:ok, _} =
               with_ets_lock(
                 table,
                 key,
                 fn _ -> :ets.insert(table, {key, :yup}) end,
                 wait_timeout: 150
               )
    end)

    Process.sleep(200)

    assert [{^key, :yup}] = :ets.lookup(table, key)
  end

  test "wait_timeout" do
    table = :ets.new(:wait_timeout_test, [:duplicate_bag, :public])
    key = :key

    spawn(fn ->
      assert {:ok, _} =
               with_ets_lock(
                 table,
                 key,
                 fn _ ->
                   Process.sleep(200)
                   :ets.insert(table, {key, :yup})
                 end
               )
    end)

    spawn(fn ->
      Process.sleep(50)

      assert {:error, :wait_timeout} =
               with_ets_lock(
                 table,
                 key,
                 fn _ -> :ets.insert(table, {key, :nope}) end,
                 wait_timeout: 100
               )
    end)

    Process.sleep(250)

    assert [{^key, :yup}] = :ets.lookup(table, key)
  end

  test "fail_timeout" do
    table = :ets.new(:wait_timeout_test, [:duplicate_bag, :public])
    key = :key

    pid =
      spawn(fn ->
        with_ets_lock(
          table,
          key,
          fn _ ->
            Process.sleep(500)
          end,
          exec_timeout: 100,
          fail_timeout: 100
        )
      end)

    Process.sleep(50)
    Process.exit(pid, :kill)

    assert {:ok, _} = with_ets_lock(table, key, fn _ -> nil end, wait_timeout: 300)
  end

  test "no key collisions between tables" do
    table1 = :ets.new(:table_one, [:duplicate_bag, :public])
    table2 = :ets.new(:table_two, [:duplicate_bag, :public])
    key = :key

    spawn(fn ->
      with_ets_lock(table1, key, fn _ ->
        Process.sleep(500)
      end)
    end)

    spawn(fn ->
      Process.sleep(50)

      assert {:ok, _} =
               with_ets_lock(
                 table2,
                 key,
                 fn _ ->
                   :ets.insert(table2, {key, :yup})
                 end,
                 wait_timeout: 100
               )
    end)

    Process.sleep(100)

    assert [{^key, :yup}] = :ets.lookup(table2, key)
  end
end
