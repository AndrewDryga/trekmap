defmodule Trekmap.APIClient.JsonResponse do
  use Protobuf, syntax: :proto3

  defmodule Payload do
    use Protobuf, syntax: :proto3

    defstruct [:type, :body]

    field(:type, 1, type: :uint32)
    field(:body, 2, type: :string)
  end

  defmodule Timestamp do
    use Protobuf, syntax: :proto3

    defstruct [:value]

    field(:value, 1, type: :uint32)
  end

  defstruct [:response, :error]

  field(:response, 1, type: Payload, optional: true)
  field(:error, 6, type: Payload, optional: true)
end
