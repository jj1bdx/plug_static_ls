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

  @typep file_info :: record(:file_info)

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
    conn = fetch_query_params(conn)
    query = validate_query(conn.params["sort"])

    if allowed?(only, prefix, segments) do
      segments = Enum.map(segments, &uri_decode/1)

      if invalid_path?(segments) do
        raise InvalidPathError
      end

      path = path(from, segments)
      directory_info = path_directory_info(conn, path)
      serve_directory_listing(directory_info,
                              at, segments, query)
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
  defp allowed?([], [], _list), do: true
  defp allowed?(_only, _prefix, []), do: false
  defp allowed?(only, prefix, [h|_]) do
    h in only or match?({0, _}, prefix != [] and :binary.match(h, prefix))
  end

  defp serve_directory_listing({:ok, conn, path}, at, segments, query) do
    basepath = Path.join("/", Path.join(
                 Path.join(rewrite_nullpath(at)),
                 Path.join(rewrite_nullpath(segments))))
    conn
    |> put_resp_header("content-type", "text/html")
    |> send_resp(200, make_ls(path, basepath, conn.host, query))
    |> halt
  end

  defp serve_directory_listing({:error, conn}, _at, _segments, _query) do
    conn
  end

  require EEx
  EEx.function_from_file :defp, :header_html,
      "lib/templates/plug_static_ls_header.html.eex",
      [:basepath, :query]
  EEx.function_from_file :defp, :footer_html,
      "lib/templates/plug_static_ls_footer.html.eex", [:host]
  EEx.function_from_file :defp, :direntry_html,
      "lib/templates/plug_static_ls_direntry.html.eex",
      [:path, :basepath, :info, :query]

  defp make_ls(dirpath, basepath, host, query) do
    # Plug.conn.send_resp/3 accepts IOlist in the body
    [header_html(basepath, query),
      Enum.map(dir_file_list(dirpath, get_sortfn(query)),
       fn({pathchar, {flag, info}}) ->
         case flag do
           :ok -> direntry_html(
                    to_string(pathchar), basepath, info, query)
           :error -> ""
         end
       end),
      footer_html(host)]
  end

  defp dir_file_list(dirpath, sortfn) do
    {:ok, list} = :prim_file.list_dir(dirpath)
    Enum.sort(
      Enum.map(list,
        fn(name) ->
          {name,
           :prim_file.read_link_info(
              to_charlist(Path.join(dirpath, to_string(name))))}
        end),
    sortfn)
  end

  @typep read_link_info :: {:ok | :error, file_info}
  @typep name_info :: {String.t, read_link_info}

  @spec validate_query(String.t) :: atom

  defp validate_query(""), do: :none
  defp validate_query("name"), do: :name
  defp validate_query("name_rev"), do: :name_rev
  defp validate_query("mtime"), do: :mtime
  defp validate_query("mtime_rev"), do: :mtime_rev
  defp validate_query("size"), do: :size
  defp validate_query("size_rev"), do: :size_rev
  defp validate_query(_), do: :none

  @spec get_sortfn(atom()) :: (name_info, name_info -> boolean())

  defp get_sortfn(:none), do: &sortfn_name/2
  defp get_sortfn(:name), do: &sortfn_name/2
  defp get_sortfn(:name_rev), do: &sortfn_name_rev/2
  defp get_sortfn(:mtime), do: &sortfn_mtime/2
  defp get_sortfn(:mtime_rev), do: &sortfn_mtime_rev/2
  defp get_sortfn(:size), do: &sortfn_size/2
  defp get_sortfn(:size_rev), do: &sortfn_size_rev/2

  @spec map_sortopt(atom()) ::
    %{:name => String.t, :mtime => String.t, :size => String.t}

  defp map_sortopt(:none) do
    %{:name => "name", :mtime => "mtime", :size => "size"}
  end
  defp map_sortopt(:name) do
    %{:name => "name_rev", :mtime => "mtime", :size => "size"}
  end
  defp map_sortopt(:name_rev) do
    %{:name => "name", :mtime => "mtime", :size => "size"}
  end
  defp map_sortopt(:mtime) do
    %{:name => "name", :mtime => "mtime_rev", :size => "size"}
  end
  defp map_sortopt(:mtime_rev) do
    %{:name => "name", :mtime => "mtime", :size => "size"}
  end
  defp map_sortopt(:size) do
    %{:name => "name", :mtime => "mtime", :size => "size_rev"}
  end
  defp map_sortopt(:size_rev) do
    %{:name => "name", :mtime => "mtime", :size => "size"}
  end

  @spec sortfn_name(name_info, name_info) :: boolean()

  defp sortfn_name({name1, _}, {name2, _}), do: name1 <= name2

  @spec sortfn_name_rev(name_info, name_info) :: boolean()

  defp sortfn_name_rev({name1, _}, {name2, _}), do: name1 >= name2

  @spec sortfn_mtime(name_info, name_info) :: boolean()

  defp sortfn_mtime({_, {:ok, info1}}, {_, {:ok, info2}}) do
    mtime_to_string(file_info(info1, :mtime)) <=
    mtime_to_string(file_info(info2, :mtime))
  end

  @spec sortfn_mtime_rev(name_info, name_info) :: boolean()

  defp sortfn_mtime_rev({_, {:ok, info1}}, {_, {:ok, info2}}) do
    mtime_to_string(file_info(info1, :mtime)) >=
    mtime_to_string(file_info(info2, :mtime))
  end

  @spec sortfn_size(name_info, name_info) :: boolean()

  defp sortfn_size({_, {:ok, info1}}, {_, {:ok, info2}}) do
    file_size_check(info1) <= file_size_check(info2)
  end

  @spec sortfn_size_rev(name_info, name_info) :: boolean()

  defp sortfn_size_rev({_, {:ok, info1}}, {_, {:ok, info2}}) do
    file_size_check(info1) >= file_size_check(info2)
  end

  @spec mtime_to_string(:calendar.datetime) :: String.t()

  defp mtime_to_string({{year, month, day}, {hour, min, sec}}) do
    to_string(
      :io_lib.format("~.4.0w-~.2.0w-~.2.0w ~.2.0w:~.2.0w:~.2.0w",
      [year, month, day, hour, min, sec]))
  end

  @spec file_size_check(file_info) :: non_neg_integer()

  defp file_size_check(info) do
    case file_info(info, :type) do
      :regular ->
        case file_info(info, :size) do
          :undefined -> 0
          s -> s
        end
      _other -> 0
    end
  end

  defp path_directory_info(conn, path) do
    case :prim_file.read_file_info(path) do
      {:ok, file_info(type: :directory) = _file_info} ->
        {:ok, conn, path}
      _other ->
        {:error, conn}
    end
  end

  @spec path({atom, String.t}, [String.t]) :: String.t
  @spec path(String.t, [String.t]) :: String.t

  defp path({app, from}, segments) when is_atom(app) and is_binary(from),
    do: Path.join([Application.app_dir(app), from|segments])
  defp path(from, segments),
    do: Path.join([from|segments])

  @spec subset([String.t], [String.t]) :: [String.t] | nil

  # if not a subset, returns nil instead of []
  defp subset([h|expected], [h|actual]),
    do: subset(expected, actual)
  defp subset([], actual),
    do: actual
  defp subset(_, _),
    do: nil

  @spec invalid_path?([String.t] | []) :: boolean()

  defp invalid_path?([h|_]) when h in [".", "..", ""], do: true
  defp invalid_path?([h|t]), do: String.contains?(h, ["/", "\\", ":"]) or invalid_path?(t)
  defp invalid_path?([]), do: false

  @spec rewrite_nullpath([String.t] | []) :: [String.t]

  defp rewrite_nullpath([]), do: ["/"]
  defp rewrite_nullpath(list), do: list
end
