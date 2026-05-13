defmodule NextLS.Communication.LocalTCP do
  @moduledoc """
  TCP communication adapter that binds to localhost by default.

  macOS Firewall prompts for unsigned executables that accept inbound network
  connections. Binding the development TCP transport to loopback keeps editor
  connections local and avoids exposing the language server on external
  interfaces.
  """

  @behaviour GenLSP.Communication.Adapter

  @separator "\r\n\r\n"

  @options_schema NimbleOptions.new!(
                    port: [
                      type: :integer,
                      default: 6890,
                      doc: "The port number to use when starting the TCP socket."
                    ],
                    ip: [
                      type: :tuple,
                      default: {127, 0, 0, 1},
                      doc: "The IP address to bind the TCP socket to."
                    ]
                  )

  @impl true
  def init(args) do
    args = NimbleOptions.validate!(args, @options_schema)

    {:ok, lsocket} =
      :gen_tcp.listen(args[:port], [
        :binary,
        packet: :raw,
        active: false,
        reuseaddr: true,
        ip: args[:ip]
      ])

    {:ok, %{lsocket: lsocket}}
  end

  @impl true
  def listen(state) do
    {:ok, socket} = :gen_tcp.accept(state.lsocket)
    {:ok, Map.merge(state, %{socket: socket})}
  end

  @impl true
  def write(body, state) do
    content_length =
      body
      |> IO.iodata_length()
      |> Integer.to_string()

    :gen_tcp.send(
      state.socket,
      IO.iodata_to_binary(["Content-Length: ", content_length, @separator, body])
    )
  end

  @impl true
  def read(state, "") do
    case :gen_tcp.recv(state.socket, 0) do
      {:ok, packet} ->
        read(state, packet)

      {:error, _} ->
        :eof
    end
  end

  def read(state, buffer) do
    {%{"Content-Length" => length}, buffer} = read_headers(buffer, state.socket)

    {body, buffer} = read_body(state.socket, buffer, String.to_integer(length))

    {:ok, body, buffer}
  end

  defp read_body(_socket, buffer, length) when byte_size(buffer) >= length do
    <<body::binary-size(length), buffer::binary>> = buffer

    {body, buffer}
  end

  defp read_body(socket, buffer, length) do
    size = length - byte_size(buffer)
    {:ok, packet} = :gen_tcp.recv(socket, size)

    read_body(socket, buffer <> packet, length)
  end

  defp read_headers(packet, socket) do
    packet
    |> decode_header(socket)
    |> read_headers(Map.new(), socket)
  end

  defp read_headers({:ok, :http_eoh, body}, headers, _socket) do
    {headers, body}
  end

  defp read_headers({:ok, {:http_header, _, header, _header, value}, more}, headers, socket) do
    headers = Map.put(headers, to_string(header), value)

    more
    |> decode_header(socket)
    |> read_headers(headers, socket)
  end

  defp decode_header(packet, socket) do
    case :erlang.decode_packet(:httph_bin, packet, []) do
      {:more, size} ->
        size = if size == :undefined, do: 0, else: size
        {:ok, more} = :gen_tcp.recv(socket, size)

        decode_header(packet <> more, socket)

      other ->
        other
    end
  end
end
