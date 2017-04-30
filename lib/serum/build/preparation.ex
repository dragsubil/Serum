defmodule Serum.Build.Preparation do
  @moduledoc """
  This module contains functions which are used to prepare the site building
  process.
  """

  alias Serum.Build
  alias Serum.Error

  @type state :: Build.state

  @spec check_tz(state) :: Error.result(nil)

  def check_tz(_state) do
    try do
      Timex.local
      {:ok, nil}
    rescue
      _ -> {:error, :system_error, "system timezone is not set"}
    end
  end

  @spec load_templates(state) :: Error.result(map)

  def load_templates(state) do
    IO.puts "Loading templates..."
    result =
      ["base", "list", "page", "post", "nav"]
      |> Enum.map(&do_load_templates(&1, state))
      |> Error.filter_results_with_values(:load_templates)
    case result do
      {:ok, list} -> {:ok, Map.new(list)}
      error = {:error, _, _} -> error
    end
  end

  @spec do_load_templates(binary, state) :: Error.result({binary, Macro.t})

  defp do_load_templates(name, state) do
    path = "#{state.src}templates/#{name}.html.eex"
    case File.read path do
      {:ok, data} ->
        try do
          base = state.project_info.base_url
          ast = data |> EEx.compile_string() |> preprocess_template(base)
          {:ok, {"template__#{name}", ast}}
        rescue
          e in EEx.SyntaxError ->
            {:error, :invalid_template, {e.message, path, e.line}}
          e in SyntaxError ->
            {:error, :invalid_template, {e.description, path, e.line}}
          e in TokenMissingError ->
            {:error, :invalid_template, {e.description, path, e.line}}
        end
      {:error, reason} ->
        {:error, :file_error, {reason, path, 0}}
    end
  end

  @spec preprocess_template(Macro.t, binary) :: Macro.t

  def preprocess_template(ast, base) do
    Macro.postwalk ast, fn
      expr = {_name, _meta, _children} ->
        eval_helpers expr, base
      x -> x
    end
  end

  defp eval_helpers({:base, meta, children}, base) do
    if children == nil do
      {:base, meta, nil}
    else
      case extract_args children do
        []       -> base
        [path|_] -> base <> path
      end
    end
  end

  defp eval_helpers({:page, meta, children}, base) do
    if children == nil do
      {:page, meta, nil}
    else
      arg = children |> extract_args() |> hd()
      "#{base}#{arg}.html"
    end
  end

  defp eval_helpers({:post, meta, children}, base) do
    if children == nil do
      {:post, meta, nil}
    else
      arg = children |> extract_args() |> hd()
      "#{base}posts/#{arg}.html"
    end
  end

  defp eval_helpers({:asset, meta, children}, base) do
    if children == nil do
      {:asset, meta, nil}
    else
      arg = children |> extract_args() |> hd()
      "#{base}assets/#{arg}"
    end
  end

  defp eval_helpers({x, y, z}, _) do
    {x, y, z}
  end

  @spec extract_args(Macro.t) :: [term]

  defp extract_args(children) do
    children |> Code.eval_quoted() |> elem(0)
  end

  @spec scan_pages(state) :: Error.result(map)

  def scan_pages(state) do
    %{src: src, dest: dest} = state
    dir = src <> "pages/"
    IO.puts "Scanning `#{dir}` directory..."
    if File.exists? dir do
      {:ok, %{"pages_file" => List.flatten(do_scan_pages dir, src, dest)}}
    else
      {:error, :file_error, {:enoent, dir, 0}}
    end
  end

  @spec do_scan_pages(binary, binary, binary) :: list(any)

  defp do_scan_pages(path, src, dest) do
    path
    |> File.ls!()
    |> Enum.reduce([], fn x, acc ->
      f = Regex.replace ~r(/+), "#{path}/#{x}", "/"
      cond do
        File.dir? f ->
          f |> String.replace_prefix("#{src}pages/", dest) |> File.mkdir_p!()
          [do_scan_pages(f, src, dest)|acc]
        String.ends_with?(f, ".md") or String.ends_with?(f, ".html") ->
          [f|acc]
        :otherwise -> acc
      end
    end)
  end
end
