defmodule Trekmap.Base.DetailedScan do
  use Protobuf, syntax: :proto3

  defmodule Result do
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
          type: Trekmap.Base.DetailedScan.Result.Information.Properties.Resources,
          repeated: true
        )
      end

      defstruct [:properties]

      field(:properties, 1, type: Trekmap.Base.DetailedScan.Result.Information.Properties)
    end

    defstruct [:information]

    field(:information, 2, type: Trekmap.Base.DetailedScan.Result.Information)
  end

  defstruct [:result]

  field(:result, 1, type: Trekmap.Base.DetailedScan.Result)
end
