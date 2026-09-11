{
  arguments,
  original,
  ...
}:
arguments.prefix + builtins.replaceStrings [ arguments.from ] [ arguments.to ] original
