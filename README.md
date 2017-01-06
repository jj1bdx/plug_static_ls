# Plug.Static.Ls

Directory Index for Plug/Phoenix Static Assets

## This module is still experimental

More thorough testing on directory traversal prevention is required.
Use at your own risk.

## WARNING: inherent vulnerability regarding directory listing

Providing directory listing may reveal following vulnerabilities:

* Contents of unintended files left in the directory

*Do not provide* directory listing unless you are 100% sure about the contents in the directory.

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed as:

  1. Add `plug_static_ls` to your list of dependencies in `mix.exs`:

    ```elixir
    def deps do
      [{:plug_static_ls, "~> 0.1.0"}]
    end
    ```

  2. Ensure `plug_static_ls` is started before your application:

    ```elixir
    def application do
      [applications: [:plug_static_ls]]
    end
    ```

## Prerequisites

The filename locale of the Erlang VM must be explicitly specified to UTF-8.
See Erlang's [`erl +fnu` option description](http://erlang.org/doc/man/erl.html) for the details.

Note: Elixir assumes UTF-8 usage on the filenames and internal strings.

## Usage

Add `Plug.Static.Ls` *after* `Plug.Static` in `endpoint.ex`

```Elixir
plug Plug.Static, at: "/", from: :my_app
plug Plug.Static.Ls, at: "/", from: :my_app, only: ~w(with_listing)
```

## License

[Apache License 2](https://www.apache.org/licenses/LICENSE-2.0)

## Acknowledment

The basic skeleton of this package is derived from
[`static.ex`](https://github.com/elixir-lang/plug/blob/master/lib/plug/static.ex)
aka `Plug.Static` module of the [Plug](https://github.com/elixir-lang/plug) repository.
