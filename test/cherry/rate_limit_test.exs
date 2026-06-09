defmodule Cherry.RateLimitTest do
  use ExUnit.Case

  alias Cherry.RateLimit

  test "allows requests up to the limit within a window" do
    key = {:test_limit, System.unique_integer([:positive])}

    assert RateLimit.allow?(key, 2, 1_000)
    assert RateLimit.allow?(key, 2, 1_000)
    refute RateLimit.allow?(key, 2, 1_000)

    RateLimit.reset(key)
    assert RateLimit.allow?(key, 2, 1_000)
  end
end
