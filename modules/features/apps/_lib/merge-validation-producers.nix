{ lib }:
{
  args,
  producers,
}:
if !builtins.isList producers then
  throw "app-validations must be a list of producer records"
else
  let
    invalidRecordIndexes = lib.concatLists (
      lib.imap0 (
        index: producer:
        lib.optional (!builtins.isAttrs producer || builtins.attrNames producer != [ "produce" ]) index
      ) producers
    );
  in
  if invalidRecordIndexes != [ ] then
    throw "app-validation producers must be { produce = <function>; } records: ${builtins.toJSON invalidRecordIndexes}"
  else
    let
      invalidProduceIndexes = lib.concatLists (
        lib.imap0 (index: producer: lib.optional (!builtins.isFunction producer.produce) index) producers
      );
    in
    if invalidProduceIndexes != [ ] then
      throw "app-validation producer records must contain produce functions: ${builtins.toJSON invalidProduceIndexes}"
    else
      let
        produced = map (producer: producer.produce args) producers;
        invalidProducerIndexes = lib.concatLists (
          lib.imap0 (index: validations: lib.optional (!builtins.isAttrs validations) index) produced
        );
      in
      if invalidProducerIndexes != [ ] then
        throw "app-validation producers must return attribute sets: ${builtins.toJSON invalidProducerIndexes}"
      else
        let
          invalidPackages = lib.concatLists (
            lib.imap0 (
              index: validations:
              lib.concatLists (
                lib.mapAttrsToList (
                  name: validation: lib.optional (!lib.isDerivation validation) "${toString index}.${name}"
                ) validations
              )
            ) produced
          );
          names = lib.concatMap builtins.attrNames produced;
          duplicateNames = builtins.filter (
            name: builtins.length (builtins.filter (other: other == name) names) > 1
          ) (lib.unique names);
          merged = lib.foldl' (acc: validations: acc // validations) { } produced;
        in
        if invalidPackages != [ ] then
          throw "app-validation producers must return derivations: ${builtins.toJSON invalidPackages}"
        else if duplicateNames != [ ] then
          throw "app-validation names must be unique across producers: ${builtins.toJSON duplicateNames}"
        else
          merged
