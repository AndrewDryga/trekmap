defmodule Trekmap.Galaxy.System.Station.DetailedScan do
  use Protobuf, syntax: :proto3

  defmodule Response do
    use Protobuf, syntax: :proto3

    defmodule Information do
      use Protobuf, syntax: :proto3

      defmodule Properties do
        use Protobuf, syntax: :proto3

        defmodule Resources do
          use Protobuf, syntax: :proto3

          defstruct [:id, :name, :amount]

          field(:id, 1, type: :uint32)
          field(:amount, 2, type: :int32)
        end

        defstruct [:resources]

        field(:resources, 4,
          type:
            Trekmap.Galaxy.System.Station.DetailedScan.Response.Information.Properties.Resources,
          repeated: true
        )
      end

      defstruct [:properties]

      field(:properties, 1,
        type: Trekmap.Galaxy.System.Station.DetailedScan.Response.Information.Properties
      )
    end

    defstruct [:information]

    field(:information, 2, type: Trekmap.Galaxy.System.Station.DetailedScan.Response.Information)
  end

  defstruct [:response]

  field(:response, 1, type: Trekmap.Galaxy.System.Station.DetailedScan.Response)
  field(:error, 6, type: Trekmap.APIClient.JsonResponse.Payload, optional: true)
end
