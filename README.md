# PlugStaticLs

Directory Index for Plug/Phoenix Static Assets

## WARNING: inherent vulnerabilities regarding directory listing

Providing directory listing may reveal following vulnerabilities:

* Contents of unintended files left in the directory will be shown to the HTTP clients, including the search engines.
* Directory listing requires file stat operations and may result in consuming computing resources.
* Directory listing reveals not only the file contents but the file name, the last modification time (mtime), and the size.

Here is a list of security advisories *against* making directory listing available to the public:

* [Mitre: CWE-548: Information Exposure Through Directory Listing](http://cwe.mitre.org/data/definitions/548.html)
* [OWASP Periodic Table of Vulnerabilities - Directory Indexing](https://www.owasp.org/index.php/OWASP_Periodic_Table_of_Vulnerabilities_-_Directory_Indexing)
* [The Web Application Security Consortium / Directory Indexing](http://projects.webappsec.org/w/page/13246922/Directory%20Indexing)

*Do not provide* directory listing unless you are 100% sure about the contents in the directory.

## Installation

This package is available in Hex as [plug\_static\_ls](https://hex.pm/packages/plug_static_ls). The package can be installed as:

  1. Add `plug_static_ls` to your list of dependencies in `mix.exs`:

    ```elixir
    def deps do
      [{:plug_static_ls, "~> 0.5.2"}]
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

Add `PlugStaticLs` *after* `Plug.Static` in `endpoint.ex`. The access restriction options for `PlugStaticLs` should include the corresponding setting of `Plug.Static`. Allow access *only* to the directories where the index is really required.

```Elixir
plug Plug.Static, at: "/", from: :my_app
plug PlugStaticLs, at: "/", from: :my_app, only: ~w(with_listing)

# Note: non-existent file will be routed here
# Explicit plug to catch this case is required
```

Dialyzer via [dialyxir](https://github.com/jeremyjh/dialyxir) can be used via `mix dialyzer`.

## License

[Apache License 2](https://www.apache.org/licenses/LICENSE-2.0)

## Acknowledment

The basic skeleton of this package is derived from
[`static.ex`](https://github.com/elixir-lang/plug/blob/master/lib/plug/static.ex)
aka `Plug.Static` module of the [Plug](https://github.com/elixir-lang/plug) repository.

The directory listing page design is derived from [Yaws](http://yaws.hyber.org) Web Server.
