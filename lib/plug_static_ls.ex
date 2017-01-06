defmodule Plug.Static.Ls do
  @moduledoc """
  A plug for serving directory listing on a static asset directory.

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

  If a static asset directory cannot be found, `Plug.Static.Ls`
  simply forwards the connection to the rest of the pipeline.

  ## Options

    * `:only` - filters which requests to serve. This is useful to avoid
      file system traversals on every request when this plug is mounted
      at `"/"`. For example, if `only: ["images", "favicon.ico"]` is
      specified, only files in the "images" directory and the exact
      "favicon.ico" file will be served by `Plug.Static`. Defaults
      to `nil` (no filtering).

    * `:only_matching` - a relaxed version of `:only` that will
      serve any request as long as one of the given values matches the
      given path. For example, `only_matching: ["images", "favicon"]`
      will match any request that starts at "images" or "favicon",
      be it "/images/foo.png", "/images-high/foo.png", "/favicon.ico"
      or "/favicon-high.ico". Such matches are useful when serving
      digested files at the root. Defaults to `nil` (no filtering).

  ## Acknowledgment

  The source code is derived from `Plug.Static` module.

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

  defp allowed?(_only, _prefix, []), do: false
  defp allowed?([], [], _list), do: true
  defp allowed?(only, prefix, [h|_]) do
    h in only or match?({0, _}, prefix != [] and :binary.match(h, prefix))
  end

  defp serve_directory_listing({:ok, conn, _file_info, path}, at, segments) do
    subpath = at <> "/" <> segments
    conn
    |> put_resp_header("content-type", "text/html")
    |> send_resp(200, make_ls(path, subpath))
    |> halt
  end

  defp serve_directory_listing({:error, conn}, _at, _segments) do
    conn
  end

  def make_ls(path, subpath) do
    {:ok, pathlist} = :prim_file.list_dir_all(path)
    # preamble
    """
    <html>
    <head>
    </head>
    <body>
    """
    <>
    "<p>Directory listing of " <>
    Plug.HTML.html_escape(subpath) <>
    "</p>\n" <>
    """
    <hr><ul>
    """
    <>
    # list entries
    :erlang.list_to_binary(
      Enum.map(pathlist,
               fn(x) ->
                 gen_ls_entry(:erlang.list_to_binary(x), subpath) end))
    <>
    # postamble
    """
    </ul>
    </body>
    </html>
    """
  end

  defp gen_ls_entry(path, subpath) do
    "<li><a href=\"" <> URI.encode(subpath <> path) <> "\">" <>
    Plug.HTML.html_escape(path) <> "</a></li>\n"
  end

  defp file_directory_info(conn, path) do
    cond do
      file_info = directory_file_info(path) ->
        {:ok, conn, file_info, path}
      true ->
        {:error, conn}
    end
  end

  # XXX: should this code be like this? Isn't File module function sufficient?
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

  defp subset([h|expected], [h|actual]),
    do: subset(expected, actual)
  defp subset([], actual),
    do: actual
  defp subset(_, _),
    do: []

  defp invalid_path?([h|_]) when h in [".", "..", ""], do: true
  defp invalid_path?([h|t]), do: String.contains?(h, ["/", "\\", ":"]) or invalid_path?(t)
  defp invalid_path?([]), do: false
end
