defmodule Trekmap.Bots.FleetCommander.Strategy do
  @callback init(config :: term(), %Trekmap.Session{}) :: {:ok, strategy_state :: term()}
  @callback handle_continue(%Trekmap.Me.Fleet{}, %Trekmap.Session{}, strategy_state :: term()) ::
              {:recall
               | {:fly, %Trekmap.Galaxy.System{}, {x :: integer(), y :: integer()}}
               | {:fly, %Trekmap.Galaxy.System{}, {x :: integer(), y :: integer()}}
               | {:attack, %Trekmap.Galaxy.Spacecraft{}}
               | {:attack, %Trekmap.Galaxy.Marauder{}}
               | {:wait, non_neg_integer()}, strategy_state :: term()}
end
