defmodule EtsLock do
  @moduledoc ~S"""
  EtsLock is a library for acquiring exclusive locks on data in
  [ETS](http://erlang.org/doc/man/ets.html) tables.

  Using `with_ets_lock/4`, you can process all `{key, value}` tuples for a
  given `key` while being sure other processes using `with_ets_lock/4`
  are not mutating the data stored for this key.

  Processing is performed in a separate process so that an execution
  timeout (`:exec_timeout`) can be enforced.

  For high concurrent performance, all locks are stored in a separate
  ETS table, and no GenServers or other processes are used to coordinate
  access.  This is in contrast to the
  [erlang-ets-lock library](https://github.com/afiskon/erlang-ets-lock/),
  which uses a single GenServer to serialize access to ETS.
  """

  @type opts :: [option]

  @type option ::
          {:wait_timeout, non_neg_integer | :infinity}
          | {:exec_timeout, non_neg_integer | :infinity}
          | {:fail_timeout, non_neg_integer | :infinity}
          | {:spin_delay, non_neg_integer}
          | {:lock_table, :ets.tab()}

  @type key :: any

  @type value :: any

  @type error_reason :: :wait_timeout | :exec_timeout | any

  @defaults [
    wait_timeout: 5000,
    exec_timeout: 5000,
    fail_timeout: 1000,
    spin_delay: 2,
    lock_table: EtsLock.Locks
  ]

  defp config(opt, opts), do: opts[opt] || @defaults[opt]

  defp now, do: :erlang.system_time(:millisecond)

  @doc ~S"""
  Locks a key in ETS and invokes `fun` on the `{key, value}` tuples for
  that key.  Returns `{:ok, fun.(tuples)}` on success.

  If the key is already locked, this function spins until the lock is
  released or the `:wait_timeout` is reached.

  Example:

      iex> table = :ets.new(:whatever, [:set, :public])
      iex> spawn(fn ->
      ...>   ## Wait 50ms, try to acquire lock, then insert
      ...>   Process.sleep(50)
      ...>   EtsLock.with_ets_lock(table, :key, fn _ ->
      ...>     :ets.insert(table, {:key, :yup})
      ...>   end)
      ...> end)
      iex> spawn(fn ->
      ...>   ## Acquire lock immediately, hold it for 100ms, then insert
      ...>   EtsLock.with_ets_lock(table, :key, fn _ ->
      ...>     Process.sleep(100)
      ...>     :ets.insert(table, {:key, :nope})
      ...>   end)
      ...> end)
      iex> Process.sleep(200)
      iex> :ets.lookup(table, :key)
      [{:key, :yup}]

  Options:

  * `:wait_timeout` - Milliseconds to wait when acquiring a lock.
    Default 5000.  Set to `:infinity` to try forever to acquire a lock.

  * `:exec_timeout` - Milliseconds to allow `fun` to hold the lock before
    its execution is cancelled and the lock is released.  Default 5000.
    Set to `:infinity` to hold the lock indefinitely until `fun` has finished.

  * `:fail_timeout` - Milliseconds to wait before forcibly deleting a
    lock after it _should_ have been released, but wasn't.  Default 1000.
    Provides protection against permanently hanging locks in the case that
    both the caller and the spawned task crash.  Set to `:infinity` to
    disable this protection (not recommended).

  * `:spin_delay` - Milliseconds to wait between every attempt to acquire a
    lock.  Default 2.

  * `:lock_table` - ETS table in which to store locks. Default `EtsLock.Locks`.
  """
  @spec with_ets_lock(:ets.tab(), key, ([{key, value}] -> any), opts) ::
          {:ok, any} | {:error, error_reason}
  def with_ets_lock(table, key, fun, opts \\ []) do
    wait_timeout = config(:wait_timeout, opts)
    exec_timeout = config(:exec_timeout, opts)
    fail_timeout = config(:fail_timeout, opts)
    spin_delay = config(:spin_delay, opts)
    lock_table = config(:lock_table, opts)

    now = now()
    wait_timeout_at = if wait_timeout == :infinity, do: :infinity, else: now + wait_timeout

    with_ets_lock(
      table,
      key,
      fun,
      wait_timeout_at,
      exec_timeout,
      fail_timeout,
      spin_delay,
      lock_table
    )
  end

  ## Strategy:
  ## Take advantage of ETS' serializability
  ## Use `:ets.insert_new/2` for atomic lock acquisition
  ## Use `:ets.delete_object/2` to ensure we release only our own lock,
  ##   or the stale lock we intend to destroy
  defp with_ets_lock(
         table,
         key,
         fun,
         wait_timeout_at,
         exec_timeout,
         fail_timeout,
         spin_delay,
         lock_table
       ) do
    lock_key = {EtsLock.Lock, table, key}
    now = now()

    if wait_timeout_at != :infinity && now >= wait_timeout_at do
      {:error, :wait_timeout}
    else
      case :ets.lookup(lock_table, lock_key) do
        [{_lock_key, {_pid, release_at}} = object] ->
          if release_at != :infinity && now >= release_at do
            ## Stale lock -- release it
            :ets.delete_object(lock_table, object)
          else
            Process.sleep(spin_delay)
          end

          with_ets_lock(
            table,
            key,
            fun,
            wait_timeout_at,
            exec_timeout,
            fail_timeout,
            spin_delay,
            lock_table
          )

        [] ->
          release_at =
            cond do
              exec_timeout == :infinity -> :infinity
              fail_timeout == :infinity -> :infinity
              :else -> now + exec_timeout + fail_timeout
            end

          lock_value = {self(), release_at}

          case :ets.insert_new(lock_table, {lock_key, lock_value}) do
            false ->
              ## We lost a race and need to wait our turn
              Process.sleep(spin_delay)

              with_ets_lock(
                table,
                key,
                fun,
                wait_timeout_at,
                exec_timeout,
                fail_timeout,
                spin_delay,
                lock_table
              )

            true ->
              ## We acquired a lock
              task = Task.async(fn -> :ets.lookup(table, key) |> fun.() end)

              return_value =
                case Task.yield(task, exec_timeout) do
                  nil ->
                    Task.shutdown(task, :brutal_kill)
                    {:error, :exec_timeout}

                  other ->
                    other
                end

              :ets.delete_object(lock_table, {lock_key, lock_value})
              return_value
          end
      end
    end
  end
end
