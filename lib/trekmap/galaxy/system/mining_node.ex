defmodule Trekmap.Galaxy.System.MiningNode do
  defstruct id: nil,
            is_active: nil,
            is_occupied: nil,
            occupied_by_fleet_id: nil,
            occupied_by_user_id: nil,
            occupied_at: nil,
            remaining_count: nil,
            resource_id: nil,
            resource_name: nil,
            system: nil,
            coords: {0, 0}
end
