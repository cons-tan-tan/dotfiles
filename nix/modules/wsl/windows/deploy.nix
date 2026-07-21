# Windows companion の store 内 src から /mnt/c 配下 dst への配置を集約し、
# 配置先の宣言と mkdir/install の実行方法が別々に増えないようにする。
# rsync でツリー同期する static.nix は対象外。
{ lib }:
{
  mkDeployActivation =
    { dirs, files }:
    lib.hm.dag.entryAfter [ "writeBoundary" ] (
      (lib.concatStringsSep "\n" (
        [ "run mkdir -p ${lib.concatMapStringsSep " " (dir: ''"${dir}"'') dirs}" ]
        ++ map (file: ''run install -m644 "${file.src}" "${file.dst}"'') files
      ))
      + "\n"
    );
}
