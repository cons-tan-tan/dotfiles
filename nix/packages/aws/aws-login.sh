config_file="${AWS_CONFIG_FILE:-$HOME/.aws/config}"

exec "$AWS_CONFIG_HELPER_BIN" login \
  --aws-bin "$AWS_LOGIN_AWS_BIN" \
  --baseline "$AWS_LOGIN_BASE_CONFIG" \
  --target "$config_file" \
  -- "$@"
