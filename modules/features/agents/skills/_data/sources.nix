# デプロイ対象skillの宣言。CLIやappなど別の責務も持つskillは、
# この共有catalogではなく所有featureからagent-skills quirkへ寄与する。
{ inputs }:
let
  inherit (inputs)
    anthropic-skills
    improve-skill
    ;
in
{
  frontend-design = {
    root = anthropic-skills.outPath + "/skills/frontend-design";
  };

  improve = {
    root = improve-skill.outPath + "/skills/improve";
  };
}
