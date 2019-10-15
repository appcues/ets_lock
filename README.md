# EtsLock

EtsLock is an Elixir library for acquiring exclusive locks on data in
[ETS](http://erlang.org/doc/man/ets.html) tables.

Using `with_ets_lock/4`, you can process all `{key, value}` tuples for a
given `key` while being sure other processes using `with_ets_lock/4`
are not mutating the data stored for this key.

Processing is performed in a separate process so that an execution
timeout (`:exec_timeout`) can be enforced.

For high concurrent performance, all locks are stored in a separate
ETS table, and no GenServers or other processes are used to coordinate
access.  This is in contrast to the
(erlang-ets-lock library)[https://github.com/afiskon/erlang-ets-lock/],
which uses a single GenServer to serialize access to ETS.

## Docs

Full documentation is available on
(Hexdocs.pm)[https://hexdocs.pm/ets_lock/EtsLock.html].

## Example usage

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

## Options

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

## Installation

Add `ets_lock` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:ets_lock, "~> 0.2.0"}
  ]
end
```

## Authorship and License

EtsLock is copyright 2019, Appcues, Inc.

EtsLock is released under the MIT License, available at
[LICENSE.txt](LICENSE.txt).
