# Copyright (c) 2013 Plataformatec.
# Copyright (c) 2017 Kenji Rikitake.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

defmodule PlugStaticLs do
  @moduledoc """

A plug for serving directory listing on a static asset directory.

Note: this module only serves the directory listing. For serving
the static asset contents, use `Plug.Static`.

It requires two options:

* `:at` - the request path to reach for the static assets.
  It must be a string.

* `:from` - the file system path to read the static assets from.
  It can be either: a string containing a file system path, an
  atom representing the application name (where assets will
  be served from `priv/static`), or a tuple containing the
  application name and the directory to serve assets from (besides
  `priv/static`).

The preferred form is to use `:from` with an atom or tuple,
since it will make your application independent from the
starting directory. On the other hand, if you want to serve
the directory listing for a specific directory, use the file
system path.

If a static asset directory specified is not found, `PlugStaticLs`
simply forwards the connection to the rest of the pipeline.
If the directory is found, `PlugStaticLs` verifies the path
given in `conn.path_info` and the path must be a subset of `:at` path
for showing the directory listing; otherwise `PlugStaticLs`
forwards the connection to the rest of the pipeline.

## Options

* `:only` - filters which requests to serve. This is useful to avoid
  file system traversals on every request when this plug is mounted
  at `"/"`. For example, if `only: ["dir1", "dir2"]` is
  specified, only files under the "dir1" and "dir2" directories
  will be served by `PlugStaticLs`. Defaults to `nil` (no filtering).

* `:only_matching` - a relaxed version of `:only` that will
  serve any request as long as one of the given values matches the
  given path. For example, `only_matching: ["images", "logos"]`
  will match any request that starts at "images" or "logos",
  be it "/images", "/images-high", "/logos"
  or "/logos-high". Such matches are useful when serving
  digested files at the root. Defaults to `nil` (no filtering).

## Templates

The following EEx templates are used to build the directory listing page:

* `lib/templates/plug_static_ls_header.html.eex`
* `lib/templates/plug_static_ls_direntry.html.eex`
* `lib/templates/plug_static_ls_footer.html.eex`

## Examples

This plug can be mounted in a `Plug.Builder` pipeline as follows,
with and *after* `Plug.Static`:

      defmodule MyPlug do
        use Plug.Builder

        plug Plug.Static,
          at: "/public",
          from: :my_app,
          only: ~w(images robots.txt)
        plug PlugStaticLs,
          at: "/public",
          from: :my_app,
          only: ~w(images)

        plug :not_found

        def not_found(conn, _) do
          send_resp(conn, 404, "not found")
        end
      end

## Related modules

For serving `index.html` for a directory name, use [`Plug.Static.IndexHtml`](https://github.com/mbuhot/plug_static_index_html/).

For serving static files, use `Plug.Static`.

## Acknowledgment

The source code is derived from `Plug.Static` module.

The directory listing page design is derived from [Yaws](http://yaws.hyber.org) Web Server.

"""

  # Note for module development:
  # No compression
  # No caching (since the contents of directory may vary every time)

  @behaviour Plug
  @allowed_methods ~w(GET HEAD)

  import Plug.Conn
  alias Plug.Conn

  # In this module, the `:prim_info` Erlang module along with the `:file_info`
  # record are used instead of the more common and Elixir-y `File` module and
  # `File.Stat` struct, respectively. The reason behind this is performance: all
  # the `File` operations pass through a single process in order to support node
  # operations that we simply don't need when serving assets.

  require Record
  Record.defrecordp :file_info, Record.extract(:file_info, from_lib: "kernel/include/file.hrl")

  defmodule InvalidPathError do
    defexception message: "invalid path for static asset directory listing",
				 plug_status: 400
  end

  def init(opts) do
    at = Keyword.fetch!(opts, :at)
    from = Keyword.fetch!(opts, :from)
    only = Keyword.get(opts, :only, [])
    prefix = Keyword.get(opts, :only_matching, [])

    from =
      case from do
        {_, _} -> from
        _ when is_atom(from) -> {from, "priv/static"}
        _ when is_binary(from) -> from
        _ -> raise ArgumentError, ":from must be an atom, a binary or a tuple"
      end

    {Plug.Router.Utils.split(at), from, only, prefix}
  end

  def call(conn = %Conn{method: meth}, {at, from, only, prefix})
      when meth in @allowed_methods do
    segments = subset(at, conn.path_info)

    if allowed?(only, prefix, segments) do
      segments = Enum.map(segments, &uri_decode/1)

      if invalid_path?(segments) do
        raise InvalidPathError
      end

      path = path(from, segments)
      directory_info = file_directory_info(conn, path)
      serve_directory_listing(directory_info, at, segments)
    else
      conn
    end
  end

  def call(conn, _opts) do
    conn
  end

  defp uri_decode(path) do
    try do
      URI.decode(path)
    rescue
      ArgumentError ->
        raise InvalidPathError
    end
  end

  # null directory is allowed here
  defp allowed?(_only, _prefix, nil), do: false
  defp allowed?(_only, _prefix, []), do: true
  defp allowed?([], [], _list), do: true
  defp allowed?(only, prefix, [h|_]) do
    h in only or match?({0, _}, prefix != [] and :binary.match(h, prefix))
  end

  defp serve_directory_listing({:ok, conn, _file_info, path}, at, segments) do
    segments =
      # rewrite null segments to "/"
      case segments do
        [] -> ["/"]
        other -> other
      end
    at =
      # rewrite null "at" to "/"
      case at do
        [] -> ["/"]
        other -> other
      end
    basepath = Path.join("/", Path.join(Path.join(at), Path.join(segments)))
    conn
    |> put_resp_header("content-type", "text/html")
    |> send_resp(200, make_ls(path, basepath, conn.host))
    |> halt
  end

  defp serve_directory_listing({:error, conn}, _at, _segments) do
    conn
  end

  require EEx
  EEx.function_from_file :defp, :header_html, 
      "lib/templates/plug_static_ls_header.html.eex", [:basepath]
  EEx.function_from_file :defp, :footer_html, 
      "lib/templates/plug_static_ls_footer.html.eex", [:host]
  EEx.function_from_file :defp, :direntry_html,
      "lib/templates/plug_static_ls_direntry.html.eex",
      [:path, :basepath, :dirpath]

  defp make_ls(dirpath, basepath, host) do
    # returns UTF-8 pathnames
    {:ok, pathlist} = :prim_file.list_dir(dirpath)
    :erlang.list_to_binary(
      [header_html(basepath), 
       Enum.map(pathlist,
                fn(x) -> direntry_html(to_string(x), basepath, dirpath) end),
       footer_html(host)])
  end

  defp file_directory_info(conn, path) do
    cond do
      file_info = directory_file_info(path) ->
        {:ok, conn, file_info, path}
      true ->
        {:error, conn}
    end
  end

  defp directory_file_info(path) do
    case :prim_file.read_file_info(path) do
      {:ok, file_info(type: :directory) = file_info} ->
        file_info
      _ ->
        nil
    end
  end

  defp path({app, from}, segments) when is_atom(app) and is_binary(from),
    do: Path.join([Application.app_dir(app), from|segments])
  defp path(from, segments),
    do: Path.join([from|segments])

  # if not a subset, returns nil instead of []
  defp subset([h|expected], [h|actual]),
    do: subset(expected, actual)
  defp subset([], actual),
    do: actual
  defp subset(_, _),
    do: nil

  defp invalid_path?([h|_]) when h in [".", "..", ""], do: true
  defp invalid_path?([h|t]), do: String.contains?(h, ["/", "\\", ":"]) or invalid_path?(t)
  defp invalid_path?([]), do: false
end
