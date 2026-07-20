config_file="${AWS_CONFIG_FILE:-$HOME/.aws/config}"

login_config=$(mktemp)
trap 'rm -f "$login_config"' EXIT
cp "$AWS_LOGIN_BASE_CONFIG" "$login_config"
chmod 600 "$login_config"

# `aws login` writes login_session into the isolated candidate. A failed login
# exits before crudini can merge a partial result into the real config.
AWS_CONFIG_FILE="$login_config" aws login "$@"

crudini --merge "$config_file" <"$login_config"
