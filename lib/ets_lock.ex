defmodule EtsLock do
  @moduledoc ~S"""
  EtsLock is a library for acquiring exclusive locks on data in
  [ETS](http://erlang.org/doc/man/ets.html) tables.

  Using `with_ets_lock/4`, you can process all `{key, value}` tuples for a
  given `key` while being sure other processes using `with_ets_lock/4`
  are not mutating the data stored for this key.

  For high concurrent performance, all locks are stored in a separate
  ETS table, and no GenServers or other processes are used to coordinate
  access.  This is in contrast to the
  (erlang-ets-lock library)[https://github.com/afiskon/erlang-ets-lock/],
  which uses a single GenServer to serialize access to ETS.
  """

  @type opts :: [option]

  @type option ::
          {:ttl, non_neg_integer | :infinity}
          | {:timeout, non_neg_integer | :infinity}
          | {:spin_delay, non_neg_integer}
          | {:lock_table, :ets.tab()}

  @type key :: any

  @type value :: any

  @defaults [
    ttl: 5000,
    timeout: 5000,
    spin_delay: 2,
    lock_table: EtsLock.Locks
  ]

  defp config(opt, opts), do: opts[opt] || @defaults[opt]

  defp now, do: :erlang.system_time(:millisecond)

  @doc ~S"""
  Locks a key in ETS and invokes `fun` on the `{key, value}` tuples for
  that key.  Returns `{:ok, fun.(tuples)}` on success.

  If the key is already locked, this function spins until the lock is
  released or the timeout is reached.

  Example:

  iex> table = :ets.new(:whatever, [:set, :public])
  iex> spawn(fn ->
  ...>   ## Wait 50ms, then try to acquire lock
  ...>   Process.sleep(50)
  ...>   EtsLock.with_ets_lock(table, :key, fn _ ->
  ...>     :ets.insert(table, {:key, :yup})
  ...>   end)
  ...> end)
  iex> spawn(fn ->
  ...>   ## Acquire lock immediately, hold it for 100ms, then release
  ...>   EtsLock.with_ets_lock(table, :key, fn _ ->
  ...>     Process.sleep(100)
  ...>     :ets.insert(table, {:key, :nope})
  ...>   end)
  ...> end)
  iex> Process.sleep(200)
  iex> :ets.lookup(table, :key)
  [{:key, :yup}]

  Options:

  * `:ttl` - Milliseconds after which this lock should be automatically
    destroyed (i.e., time to live).  Default 5000.  Set to `:infinity` if
    this lock must never be destroyed automatically.  This option does
    *not* cancel the execution of `fun`.

  * `:timeout` - Milliseconds to wait when acquiring a lock.
    Default 5000.  Set to `:infinity` to try forever to acquire a lock.

  * `:spin_delay` - Milliseconds to wait between every attempt to acquire a
    lock.  Default 2.

  * `:lock_table` - ETS table in which to store locks. Default `EtsLock.Locks`.
  """
  @spec with_ets_lock(:ets.tab(), key, ([{key, value}] -> any), opts) :: {:ok, any} | :timeout
  def with_ets_lock(table, key, fun, opts \\ []) do
    ttl = config(:ttl, opts)
    timeout = config(:timeout, opts)
    spin_delay = config(:spin_delay, opts)
    lock_table = config(:lock_table, opts)

    now = now()
    timeout_at = if timeout == :infinity, do: :infinity, else: now + timeout

    with_ets_lock(table, key, fun, ttl, timeout_at, spin_delay, lock_table)
  end

  ## Strategy:
  ## Take advantage of ETS' serializability
  ## Use `:ets.insert_new/2` for atomic lock acquisition
  ## Use `:ets.delete_object/2` to ensure we release only our own lock,
  ##   or the stale lock we intend to destroy
  defp with_ets_lock(table, key, fun, ttl, timeout_at, spin_delay, lock_table) do
    lock_key = {EtsLock.Lock, key}
    now = now()

    if timeout_at != :infinity && now >= timeout_at do
      :timeout
    else
      case :ets.lookup(lock_table, lock_key) do
        [] ->
          release_at = if ttl == :infinity, do: :infinity, else: now + ttl
          lock_value = {self(), release_at}

          case :ets.insert_new(lock_table, {lock_key, lock_value}) do
            false ->
              ## We lost a race and need to wait our turn
              Process.sleep(spin_delay)
              with_ets_lock(table, key, fun, ttl, timeout_at, spin_delay, lock_table)

            true ->
              return_value = :ets.lookup(table, key) |> fun.()
              :ets.delete_object(lock_table, {lock_key, lock_value})
              {:ok, return_value}
          end

        [{_lock_key, {_pid, release_at}} = object] ->
          if release_at != :infinity && now >= release_at do
            :ets.delete_object(lock_table, object)
          else
            Process.sleep(spin_delay)
          end

          with_ets_lock(table, key, fun, ttl, timeout_at, spin_delay, lock_table)
      end
    end
  end
end
