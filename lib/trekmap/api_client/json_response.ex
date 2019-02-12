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

defmodule Trekmap.APIClient.JsonResponsePrimeSync1 do
  use Protobuf, syntax: :proto3

  defmodule ActiveJob do
    use Protobuf, syntax: :proto3

    defmodule Item do
      use Protobuf, syntax: :proto3

      defstruct [:kind, :id, :duration, :remaining_duration, :start_timestamp]

      field(:kind, 1, type: :uint32)
      field(:id, 2, type: :string)
      field(:duration, 3, type: :uint32, optional: true)
      field(:start_timestamp, 4, type: Trekmap.APIClient.JsonResponse.Timestamp)
    end

    defmodule List do
      use Protobuf, syntax: :proto3

      defstruct [:items]

      field(:items, 1,
        type: Trekmap.APIClient.JsonResponsePrimeSync1.ActiveJob.Item,
        repeated: true
      )
    end

    defstruct [:list]

    field(:list, 2, type: Trekmap.APIClient.JsonResponsePrimeSync1.ActiveJob.List)
  end

  defstruct [:response, :active_jobs, :current_timestamp, :error]

  field(:response, 1, type: Trekmap.APIClient.JsonResponse.Payload)

  field(:active_jobs, 2,
    type: Trekmap.APIClient.JsonResponsePrimeSync1.ActiveJob,
    optional: true
  )

  field(:current_timestamp, 3, type: Trekmap.APIClient.JsonResponse.Timestamp)

  field(:error, 6, type: Trekmap.APIClient.JsonResponse.Payload, optional: true)
end
