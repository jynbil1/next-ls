defmodule NextLS.Communication.LocalTCPTest do
  use ExUnit.Case, async: true

  alias NextLS.Communication.LocalTCP

  test "binds to localhost by default" do
    {:ok, state} = LocalTCP.init(port: 0)

    assert {:ok, {{127, 0, 0, 1}, _port}} = :inet.sockname(state.lsocket)

    :gen_tcp.close(state.lsocket)
  end
end
