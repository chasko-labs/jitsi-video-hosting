#!/usr/bin/with-contenv bash
# Start SSM agent for ECS Exec support.
# Only starts if ECS_ENABLE_EXEC_COMMAND is set (ECS sets this automatically
# when the service has enableExecuteCommand=true).
if [ "${ECS_ENABLE_EXEC_COMMAND}" = "true" ] || [ -f /var/lib/amazon/ssm/registration ]; then
	exec /usr/bin/amazon-ssm-agent
fi
# If exec command not enabled, just sleep forever (s6 requires the run script to not exit)
exec sleep infinity
