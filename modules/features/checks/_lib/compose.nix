{ ciCheck, ... }:
{
  producers,
  reservedCheckNames ? [ ],
}:
ciCheck.composeBuildProducers { inherit producers reservedCheckNames; }
