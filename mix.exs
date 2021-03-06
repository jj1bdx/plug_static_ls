defmodule PlugStaticLs.Mixfile do
  use Mix.Project

  @version "0.6.1"

  def project do
    [app: :plug_static_ls,
     version: @version,
     elixir: "~> 1.3",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     deps: deps(),
	 package: package(),
     description: "Directory Index for Plug/Phoenix Static Assets", 
	 name: "Plug_Static_Ls",
	 source_url: "https://github.com/jj1bdx/plug_static_ls",
	 homepage_url: "http://github.com/jj1bdx/plug_static_ls",
     docs: [extras: ["README.md"], main: "readme",
            source_ref: "v#{@version}",
            source_url: "https://github.com/jj1bdx/plug_static_ls"],
     dialyzer: [plt_add_deps: :transitive,
                flags: ["-Wunmatched_returns","-Werror_handling","-Wrace_conditions", "-Wno_opaque"]]]
  end

  defp package do
    [licenses: ["Apache 2"],
     maintainers: ["Kenji Rikitake"],
	 links: %{"GitHub" => "https://github.com/jj1bdx/plug_static_ls"}]
  end

  def application do
    [applications: []]
  end

  defp deps do
    [
      {:plug, "~> 1.3.2"},
      {:ex_doc, "~> 0.14", only: :dev},
      {:dialyxir, "~> 0.4", only: [:dev], runtime: false}
    ]
  end
end
