{
  binName = "textlint";
  entry = "bin/textlint.js";
  modes.tech-jp = {
    config = ./configs/tech-jp.textlintrc.yaml;
  };
  nodeDir = ./node;
  packageName = "textlint";
}
