defmodule CherryWeb.Markdown do
  import Phoenix.HTML

  def render(nil), do: ""
  def render(""), do: ""

  def render(markdown) do
    markdown
    |> Phoenix.HTML.html_escape()
    |> Phoenix.HTML.safe_to_string()
    |> String.split("\n")
    |> Enum.map(&line_to_html/1)
    |> Enum.join("")
    |> raw()
  end

  defp line_to_html("### " <> text),
    do: "<h3 class=\"mt-4 text-sm font-semibold\">#{inline(text)}</h3>"

  defp line_to_html("## " <> text),
    do: "<h2 class=\"mt-5 text-base font-semibold\">#{inline(text)}</h2>"

  defp line_to_html("# " <> text),
    do: "<h1 class=\"mt-6 text-lg font-semibold\">#{inline(text)}</h1>"

  defp line_to_html("- " <> text),
    do: "<p class=\"pl-4 text-sm text-zinc-700\">• #{inline(text)}</p>"

  defp line_to_html(""), do: "<br/>"
  defp line_to_html(text), do: "<p class=\"text-sm leading-6 text-zinc-700\">#{inline(text)}</p>"

  defp inline(text) do
    text
    |> String.replace(~r/\*\*([^*]+)\*\*/, "<strong>\\1</strong>")
    |> String.replace(
      ~r/`([^`]+)`/,
      "<code class=\"rounded bg-zinc-100 px-1 py-0.5 text-xs\">\\1</code>"
    )
  end
end
