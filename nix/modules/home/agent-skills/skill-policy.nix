# skill 定義を検証し、customization と invocation policy を適用する。
# YAML テキスト処理は yaml-frontmatter.nix の汎用関数を使う。
{ lib }:
let
  yaml = import ./yaml-frontmatter.nix { inherit lib; };
  inherit (yaml)
    filterFrontmatterFields
    findFrontmatterFields
    frontmatterFieldNames
    frontmatterStringValue
    isFrontmatterFieldName
    normalizeDescription
    setFrontmatterField
    splitFrontmatter
    utf8CodePointLength
    ;
in
rec {
  unknownAttrs =
    allowed: attrs: lib.filter (name: !builtins.elem name allowed) (builtins.attrNames attrs);

  validateKnownAttrs =
    context: allowed: attrs:
    let
      unknown = unknownAttrs allowed attrs;
    in
    assert lib.assertMsg (
      unknown == [ ]
    ) "${context}: unknown attributes: ${lib.concatStringsSep ", " unknown}";
    attrs;

  isSkillName =
    name:
    builtins.isString name
    && builtins.stringLength name <= 64
    && builtins.match "^[a-z0-9]+(-[a-z0-9]+)*$" name != null;

  validateFrontmatterFieldNames =
    context: names:
    assert lib.assertMsg (builtins.isList names) "${context} must be a list";
    assert lib.assertMsg (lib.all builtins.isString names) "${context} must contain only strings";
    assert lib.assertMsg (lib.all isFrontmatterFieldName names)
      "${context} contains an invalid frontmatter field name";
    names;

  # sources.nix の customization DSL を正規化し、未知の key や誤った型を
  # eval 時に拒否する。設定 typo を黙って無視すると policy が fail open に
  # なるため、各階層を closed schema として扱う。
  validateCustomization =
    context: value:
    assert lib.assertMsg (builtins.isAttrs value) "${context} must be an attribute set";
    let
      customization = validateKnownAttrs context [
        "frontmatter"
        "body"
        "disableAutomaticInvocation"
      ] value;
      rawFrontmatter = customization.frontmatter or { };
      body = customization.body or null;
    in
    assert lib.assertMsg (builtins.isAttrs rawFrontmatter)
      "${context}.frontmatter must be an attribute set";
    assert lib.assertMsg (body == null || lib.isFunction body) "${context}.body must be a function";
    let
      frontmatter = validateKnownAttrs "${context}.frontmatter" [
        "description"
        "set"
        "inheritFields"
        "excludeFields"
      ] rawFrontmatter;
      rawDescription = frontmatter.description or null;
      description = if rawDescription == null then null else normalizeDescription rawDescription;
      set = frontmatter.set or { };
      inheritFields = validateFrontmatterFieldNames ("${context}.frontmatter.inheritFields") (
        frontmatter.inheritFields or [ ]
      );
      excludeFields = validateFrontmatterFieldNames ("${context}.frontmatter.excludeFields") (
        frontmatter.excludeFields or [ ]
      );
      disableAutomaticInvocation = customization.disableAutomaticInvocation or false;
    in
    assert lib.assertMsg (
      rawDescription == null || builtins.isString rawDescription
    ) "${context}.frontmatter.description must be a string";
    assert lib.assertMsg (
      description == null || description != ""
    ) "${context}.frontmatter.description must not be empty";
    assert lib.assertMsg (builtins.isAttrs set) "${context}.frontmatter.set must be an attribute set";
    assert lib.assertMsg (lib.all isFrontmatterFieldName (
      builtins.attrNames set
    )) "${context}.frontmatter.set contains an invalid frontmatter field name";
    assert lib.assertMsg (
      !set ? description
    ) "${context}.frontmatter.set.description is unsupported; use ${context}.frontmatter.description";
    assert lib.assertMsg (
      !set ? name || builtins.isString set.name
    ) "${context}.frontmatter.set.name must be a string";
    assert lib.assertMsg (lib.all
      (
        name:
        !builtins.elem name [
          "name"
          "description"
        ]
      )
      excludeFields
    ) "${context}.frontmatter.excludeFields cannot exclude required name or description fields";
    assert lib.assertMsg (builtins.isBool disableAutomaticInvocation)
      "${context}.disableAutomaticInvocation must be a boolean";
    {
      frontmatter = {
        inherit
          description
          set
          inheritFields
          excludeFields
          ;
      };
      inherit body disableAutomaticInvocation;
    };

  validateSkillDefinition =
    name: value:
    assert lib.assertMsg (builtins.isAttrs value) "skill ${name} definition must be an attribute set";
    let
      skill = validateKnownAttrs "skill ${name} definition" [
        "root"
        "customization"
      ] value;
      customization = validateCustomization "skill ${name} customization" (skill.customization or { });
    in
    assert lib.assertMsg (skill ? root) "skill ${name} definition requires root";
    assert lib.assertMsg (
      builtins.isPath skill.root || builtins.isString skill.root
    ) "skill ${name} definition root must be a path or string";
    {
      inherit (skill) root;
      inherit customization;
      hasCustomization =
        customization.frontmatter.description != null
        || builtins.attrNames customization.frontmatter.set != [ ]
        || customization.frontmatter.inheritFields != [ ]
        || customization.frontmatter.excludeFields != [ ]
        || customization.body != null
        || customization.disableAutomaticInvocation;
    };

  setFrontmatterValues =
    values: original:
    lib.foldl' (text: key: setFrontmatterField key (builtins.toJSON values.${key}) text) original (
      builtins.attrNames values
    );

  applyCustomization =
    {
      name,
      root,
      customization,
    }:
    original:
    let
      frontmatter = customization.frontmatter or { };
      bodyTransform = customization.body or null;
      description = frontmatter.description or null;
      frontmatterValues =
        (frontmatter.set or { })
        // lib.optionalAttrs (description != null) {
          inherit description;
        };
      withFrontmatter = setFrontmatterValues frontmatterValues original;
      split = splitFrontmatter withFrontmatter;
      transformedBody =
        if bodyTransform == null then
          split.body
        else
          bodyTransform {
            original = split.body;
            skillName = name;
            inherit root;
          };
    in
    assert lib.assertMsg (builtins.isString transformedBody)
      "skill ${name} customization.body must return a string";
    split.frontmatter + transformedBody;

  disableModelInvocation = setFrontmatterField "disable-model-invocation" "true";

  validateRequiredFrontmatter =
    expectedName: text:
    let
      s = splitFrontmatter text;
      names = findFrontmatterFields "name" text;
      descriptions = findFrontmatterFields "description" text;
      name = if builtins.length names == 1 then frontmatterStringValue (builtins.head names) else null;
      description =
        if builtins.length descriptions == 1 then
          frontmatterStringValue (builtins.head descriptions)
        else
          null;
    in
    assert lib.assertMsg (
      s.frontmatter != ""
    ) "skill ${expectedName}: SKILL.md requires YAML frontmatter";
    assert lib.assertMsg (
      builtins.length names == 1
    ) "skill ${expectedName}: frontmatter must contain exactly one name field";
    assert lib.assertMsg (
      builtins.length descriptions == 1
    ) "skill ${expectedName}: frontmatter must contain exactly one description field";
    assert lib.assertMsg (
      name == expectedName
    ) "skill ${expectedName}: frontmatter.name must be a string matching its distribution name";
    assert lib.assertMsg (
      description != null
    ) "skill ${expectedName}: frontmatter.description must be a non-empty string";
    assert lib.assertMsg (
      utf8CodePointLength description <= 1024
    ) "skill ${expectedName}: frontmatter.description must not exceed 1024 characters";
    assert lib.assertMsg (
      builtins.match ".*<[^>]+>.*" (builtins.replaceStrings [ "\n" ] [ " " ] description) == null
    ) "skill ${expectedName}: frontmatter.description must not contain XML tags";
    text;

  # Upstream filtering, local overrides, and invocation policy are intentionally
  # one pipeline so callers cannot accidentally change their security-sensitive
  # ordering.
  prepareSkill =
    {
      name,
      root,
      defaultInheritedFields,
      customization ? { },
      requireExplicitFieldDecisions ? false,
    }:
    original:
    let
      context = "skill ${name} customization";
      checkedCustomization = validateCustomization context customization;
      frontmatter = checkedCustomization.frontmatter;
      source = splitFrontmatter original;
      sourceFields = frontmatterFieldNames original;
      explicitInheritedFields = frontmatter.inheritFields;
      explicitExcludedFields = frontmatter.excludeFields;
      explicitlyClassifiedFields = lib.unique (
        defaultInheritedFields ++ explicitInheritedFields ++ explicitExcludedFields
      );
      unclassifiedFields = lib.filter (
        field: !builtins.elem field explicitlyClassifiedFields
      ) sourceFields;
      declaredFieldsNotInSource = lib.filter (field: !builtins.elem field sourceFields) (
        lib.unique (explicitInheritedFields ++ explicitExcludedFields)
      );
      conflictingFieldDecisions = lib.intersectLists explicitInheritedFields explicitExcludedFields;
      inheritedFields = lib.unique (defaultInheritedFields ++ frontmatter.inheritFields);
      effectiveInheritedFields = lib.subtractLists frontmatter.excludeFields inheritedFields;
      filtered = filterFrontmatterFields effectiveInheritedFields original;
      customized = applyCustomization {
        inherit name root;
        customization = checkedCustomization;
      } filtered;
      transformedSkillMd =
        if checkedCustomization.disableAutomaticInvocation then
          disableModelInvocation customized
        else
          customized;
      skillMd = validateRequiredFrontmatter name transformedSkillMd;
    in
    assert lib.assertMsg (isSkillName name)
      "skill distribution name must use 1-64 lowercase letters, digits, and hyphens: ${name}";
    assert lib.assertMsg (
      source.frontmatter != ""
    ) "skill ${name}: upstream SKILL.md requires YAML frontmatter";
    assert lib.assertMsg (conflictingFieldDecisions == [ ])
      "${context}.frontmatter fields cannot be both inherited and excluded: ${lib.concatStringsSep ", " conflictingFieldDecisions}";
    assert lib.assertMsg (declaredFieldsNotInSource == [ ])
      "${context}.frontmatter decisions reference fields missing from upstream: ${lib.concatStringsSep ", " declaredFieldsNotInSource}";
    assert lib.assertMsg (!requireExplicitFieldDecisions || unclassifiedFields == [ ])
      "${context}.frontmatter has unclassified upstream fields: ${lib.concatStringsSep ", " unclassifiedFields}";
    builtins.seq skillMd {
      inherit skillMd;
      frontmatterWasFiltered = filtered != original;
      inherit (checkedCustomization) disableAutomaticInvocation;
    };

}
