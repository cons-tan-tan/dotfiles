{ lib }:
{
  den,
  system,
}:
let
  resolveTarget =
    {
      entities,
      environment,
      label,
      output,
    }:
    let
      candidates = lib.filterAttrs (
        _: entity: (entity.dotfiles.environment or null) == environment
      ) entities;
      candidateNames = builtins.attrNames candidates;
      candidateCount = builtins.length candidateNames;
      entityName = if candidateCount == 1 then builtins.head candidateNames else null;
      entity = if entityName == null then null else candidates.${entityName};
      intoAttr = if entity == null then null else entity.intoAttr or null;
      validIntoAttr =
        builtins.isList intoAttr
        && builtins.length intoAttr == 2
        && builtins.elemAt intoAttr 0 == output
        && builtins.isString (builtins.elemAt intoAttr 1)
        && builtins.elemAt intoAttr 1 != "";
    in
    if candidateCount != 1 then
      throw "${label} requires exactly one ${environment} entity for ${system}, found ${toString candidateCount}"
    else if !validIntoAttr then
      throw "${label} entity ${entityName} must declare intoAttr = [ \"${output}\" <non-empty-name> ]"
    else
      {
        inherit entity entityName;
        outputName = builtins.elemAt intoAttr 1;
      };

  resolveWindows =
    {
      dotfiles,
      environment,
      label,
    }:
    let
      raw = dotfiles.windows or { };
      windows = {
        enable = raw.enable or false;
        username = raw.username or null;
        homedir = raw.homedir or null;
      };
      expectedHomedir =
        if builtins.isString windows.username then "/mnt/c/Users/${windows.username}" else null;
    in
    if !builtins.isBool windows.enable then
      throw "${label}.dotfiles.windows.enable must be a boolean"
    else if
      windows.username != null && (!builtins.isString windows.username || windows.username == "")
    then
      throw "${label}.dotfiles.windows.username must be null or a non-empty string"
    else if
      windows.homedir != null && (!builtins.isString windows.homedir || windows.homedir == "")
    then
      throw "${label}.dotfiles.windows.homedir must be null or a non-empty string"
    else if environment == "wsl" && !windows.enable then
      throw "${label}.dotfiles.windows.enable must be true for a WSL entity"
    else if windows.enable && windows.username == null then
      throw "${label}.dotfiles.windows.username is required when the Windows companion is enabled"
    else if windows.enable && windows.homedir == null then
      throw "${label}.dotfiles.windows.homedir is required when the Windows companion is enabled"
    else if windows.enable && windows.homedir != expectedHomedir then
      throw "${label}.dotfiles.windows.homedir must equal /mnt/c/Users/<dotfiles.windows.username>"
    else if
      environment != "wsl"
      &&
        windows != {
          enable = false;
          username = null;
          homedir = null;
        }
    then
      throw "${label}.dotfiles.windows must be disabled and empty outside WSL"
    else
      windows;

  resolveEntityContext =
    {
      environment,
      label,
      target,
    }:
    let
      dotfiles = target.entity.dotfiles or { };
      source = dotfiles.source or null;
    in
    if !builtins.isString source || source == "" then
      throw "${label}.dotfiles.source must be a non-empty string"
    else
      {
        inherit environment source;
        inherit (target) entityName outputName;
        windows = resolveWindows {
          inherit dotfiles environment label;
        };
      };

  resolvePrimaryUser =
    {
      host,
      label,
    }:
    let
      users = host.users or { };
      primaryUsers = lib.filterAttrs (_: user: user.dotfiles.primary or false) users;
      names = builtins.attrNames primaryUsers;
      count = builtins.length names;
      entityName = if count == 1 then builtins.head names else null;
      user = if entityName == null then null else primaryUsers.${entityName};
      username = if user == null then null else user.userName or null;
    in
    if count != 1 then
      throw "${label}.users requires exactly one dotfiles.primary user, found ${toString count}"
    else if !builtins.isString username || username == "" then
      throw "${label}.users.${entityName}.userName must be a non-empty string"
    else if entityName != username then
      throw "${label}.users.${entityName}.userName must match its entity name"
    else
      {
        inherit entityName username;
      };

  resolveHomeContext =
    {
      environment,
      label,
      target,
    }:
    let
      context = resolveEntityContext {
        inherit environment label target;
      };
      userName = target.entity.userName or null;
      derivedHomedir = if builtins.isString userName then "/home/${userName}" else null;
      explicitHomedir = target.entity.homeDirectory or null;
      homedir = if explicitHomedir == null then derivedHomedir else explicitHomedir;
    in
    if !builtins.isString userName || userName == "" then
      throw "${label}.userName must be a non-empty string"
    else if explicitHomedir != null && explicitHomedir != derivedHomedir then
      throw "${label}.homeDirectory must match /home/<userName>"
    else
      context
      // {
        inherit homedir userName;
      };

  hosts = den.hosts.${system} or { };
  homes = den.homes.${system} or { };
in
if lib.hasSuffix "-darwin" system then
  let
    target = resolveTarget {
      entities = hosts;
      environment = "darwin";
      label = "Darwin configuration target";
      output = "darwinConfigurations";
    };
    context = resolveEntityContext {
      environment = "darwin";
      label = "Darwin configuration target ${target.entityName}";
      inherit target;
    };
    primary = resolvePrimaryUser {
      host = target.entity;
      label = "Darwin configuration target ${target.entityName}";
    };
  in
  {
    darwin = target.outputName;
    entityNames.darwin = target.entityName;
    inherit (primary) username;
    inherit (context) windows;
    contexts.darwin = context // {
      inherit (primary) username;
    };
  }
else if lib.hasSuffix "-linux" system then
  let
    nixosWslTarget = resolveTarget {
      entities = hosts;
      environment = "wsl";
      label = "NixOS-WSL configuration target";
      output = "nixosConfigurations";
    };
    linuxHomeTarget = resolveTarget {
      entities = homes;
      environment = "linux";
      label = "standalone Linux Home Manager target";
      output = "homeConfigurations";
    };
    wslHomeTarget = resolveTarget {
      entities = homes;
      environment = "wsl";
      label = "standalone WSL Home Manager target";
      output = "homeConfigurations";
    };
    nixosWsl = resolveEntityContext {
      environment = "wsl";
      label = "NixOS-WSL configuration target ${nixosWslTarget.entityName}";
      target = nixosWslTarget;
    };
    linuxHome = resolveHomeContext {
      environment = "linux";
      label = "standalone Linux Home Manager target ${linuxHomeTarget.entityName}";
      target = linuxHomeTarget;
    };
    wslHome = resolveHomeContext {
      environment = "wsl";
      label = "standalone WSL Home Manager target ${wslHomeTarget.entityName}";
      target = wslHomeTarget;
    };
    primary = resolvePrimaryUser {
      host = nixosWslTarget.entity;
      label = "NixOS-WSL configuration target ${nixosWslTarget.entityName}";
    };
  in
  if linuxHomeTarget.outputName == wslHomeTarget.outputName then
    throw "standalone Linux and WSL entities for ${system} must declare distinct homeConfigurations targets"
  else if linuxHome.userName != wslHome.userName then
    throw "standalone home userName mismatch for ${system}: linux=${linuxHome.userName}, wsl=${wslHome.userName}"
  else if primary.username != linuxHome.userName then
    throw "integrated host primary userName must match standalone home userName for ${system}"
  else if nixosWsl.windows != wslHome.windows then
    throw "integrated and standalone WSL dotfiles.windows identity must match for ${system}"
  else
    {
      nixosWsl = nixosWslTarget.outputName;
      home = {
        linux = linuxHomeTarget.outputName;
        wsl = wslHomeTarget.outputName;
      };
      entityNames = {
        nixosWsl = nixosWslTarget.entityName;
        home = {
          linux = linuxHomeTarget.entityName;
          wsl = wslHomeTarget.entityName;
        };
      };
      inherit (primary) username;
      linuxHomedir = linuxHome.homedir;
      inherit (nixosWsl) windows;
      contexts = {
        nixosWsl = nixosWsl // {
          inherit (primary) username;
          homedir = linuxHome.homedir;
        };
        home = {
          linux = linuxHome;
          wsl = wslHome;
        };
      };
    }
else
  throw "configuration targets do not support system ${system}"
