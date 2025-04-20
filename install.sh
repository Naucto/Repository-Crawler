#!/bin/sh

SV_REPO_PATH="`dirname "$0"`"

SV_INSTALL_PATH="/opt/naucto-repository-crawler"
SV_INSTALL_DEFAULT_CERT_FNAME="cert"
SV_INSTALL_DEFAULT_CERT_PATH="$SV_INSTALL_PATH/$SV_INSTALL_DEFAULT_CERT_FNAME"
SV_LOCK_PATH="$SV_REPO_PATH/.`basename "$0"`.lock"
SV_TEMP_PATH="$SV_REPO_PATH/.repo"

SV_SERVICE_USER="nrc"
SV_SERVICE_NAME="naucto-repository-crawler"
SV_SERVICE_PATH="/etc/systemd/system/$SV_SERVICE_NAME.service"
SV_SERVICE_SCRIPT_FNAME="service.sh"
SV_SERVICE_SCRIPT_PATH="$SV_INSTALL_PATH/$SV_SERVICE_SCRIPT_FNAME"
SV_SERVICE_ENV_FNAME=".config"
SV_SERVICE_ENV_PATH="$SV_INSTALL_PATH/$SV_SERVICE_ENV_FNAME"
SV_SERVICE_VENV_FNAME=".env"
SV_SERVICE_VENV_PATH="$SV_INSTALL_PATH/$SV_SERVICE_VENV_FNAME"

sv_require()
{
    tool_name="$1"
    error_message="$2"

    tool_path=`which "$tool_name" 2>&1`

    if [ $? -ne 0 ]; then
        echo "$0: Cannot find '$tool_name' on your system. $error_message" >&2
        # Note: As `` spawns a subshell, exit = return.
        exit 1
    fi

    echo $tool_path
}

sv_usage()
{
    echo "Usage: $0 [-h] [install|uninstall]" >&2
}

sv_question()
{
    question="$1"
    default_value="$2"
    variable_name="$3"

    echo -n "$question [$default_value]: " >&2
    read input_value

    [ -z "$input_value" ] && echo "$default_value" || echo "$input_value"
}

sv_try()
{
    why="$1"
    command="$2"

    tool_output="`sh -c "$command" 2>&1`"
    tool_status="$?"

    if [ "$tool_status" -ne 0 ]; then
        echo "$0: Failed to run '$command' (exit status $tool_status)"
        echo "The installer tried to: $why"
        echo "The command output: $tool_output"

        exit 1
    fi
}

sv_try_as()
{
    su_tool="$1"
    user="$2"
    why="$3"
    command="$4"

    sv_try "$why" "echo $command | $su_tool $user"
}

sv_lock()
{
    if [ -f "$SV_LOCK_PATH" ]; then
        cat >&2 <<EOF
$0: The installer lock file is already present.

Either another instance of this script is running, or the script has
prematurely stopped. If you are sure no other instance of this script is
running, you can delete the lock file with this command:

rm -f '$SV_LOCK_PATH'
EOF

        exit 1
    fi

    cp "$0" "$SV_LOCK_PATH"
}

sv_unlock()
{
    rm -f "$SV_LOCK_PATH"
}

sv_status_show()
{
   echo "$@... "
}

sv_action_install()
{
    cat >&2 <<EOF
This assistant will ask you a handful set of questions to install the service
and its components on this computer.

Default values are shown right besides the question. Press Enter if you want
to accept said default value, or type in the appropriate value if necessary.

The service requires the use of SSL certificates so that GitHub can contact it
through a webhook. Consequently, this requires an associated domain name for
this task.

Only change this value if you are not going to use auto-renewed
certification bots like certbot.

We recommend you use certbot to automatically generate keys for your domain
name, and keep them up-to-date.

The path must be a folder containing the following two files:

   - cert.pem, the public key exposed to end users/clients
   - privkey.pem, the private key used to encrypt responses to be decoded by
     end users/clients
EOF
    certificates_path="`sv_question "Where are the SSL public and private keys located?" \
                        "$SV_INSTALL_DEFAULT_CERT_PATH"`"

    if [ ! -d "$certificates_path" ] || \
       [ ! -f "$certificates_path/fullchain.pem" ] || \
       [ ! -f "$certificates_path/privkey.pem" ]; then
        echo "$0: Bad certificates path passed, cannot continue." >&2
        exit 1
    fi

    certificates_path="`realpath "$certificates_path"`"    

    # ---

    cat >&2 <<EOF

As we indirectly use 'git' and 'ssh' by extension, we require the service to
have a SSH private key.

As an Epitech student, you need to generate a public and private key
associated to your user account and authenticated to single sign-on.

Since this is risky, we HIGHLY recommend you to generate a separate key pair,
distinct from your work key pair.

The private key will not be exposed to the users of this machine nor to the
outsiders that use the hosted service through HTTPS.

EOF

    private_key_path="`sv_question "Where is the SSH private key located?" \
                                   ""`"

    if [ -z "$private_key_path" ] || \
       [ ! -f "$private_key_path" ]; then
        echo "$0: Bad SSH private key path passed, cannot continue." >&2
        exit 1
    fi

    private_key_path="`realpath "$private_key_path"`"

    cat >&2 <<EOF

The service requires write access to the project owner's student repository.
Thus, we need to have a fine-grained GitHub token associated to a student
account.

Creating a fine-grained GitHub token is easy. Follow the guide on the official
GitHub documentation website:

https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens#creating-a-fine-grained-personal-access-token

Make sure to authenticate your fine-grained GitHub token against the official
Epitech organization associated with your account.

EOF
    github_token="`sv_question "What is the student GitHub token that you want to use?" \
                               "")`"

    if [ -z "$github_token" ]; then
        echo "$0: No GitHub token provided, cannot continue." >&2
        exit 1
    fi

    # ---

    cat >&2 <<EOF

The service needs to know from which GitHub organization you want to synchronize
the main student repository to.

You do not need to specify the full URL path to it, only the name/identifier of
that organization. For example, Naucto is located at https://github.com/Naucto,
so we shall specify 'Naucto' for this question.

EOF

    source_organization="`sv_question "What is the source GitHub organization you want to sync from?" \
                                      "Naucto"`"

    if [ -z "$source_organization" ]; then
        echo "$0: No GitHub source organization specified, cannot continue." >&2
        exit 1
    fi

    # ---
    
    cat >&2 <<EOF

The service needs to know where to store all of the synchronized repositories
to.

Just like with the previous question, you do not need to specify the full blown
path to your repository. For example, if your repository is located at the
following location:

    https://github.com/EpitechPromo2027/G-EIP-600-MPL-6-1-eip-alexis.belmonte

You only need to specify the following path:

    EpitechPromo2027/G-EIP-600-MPL-6-1-eip-alexis.belmonte

EOF

    target_repository="`sv_question "What is the target GitHub student repository you want to sync to?" \
                                    "EpitechPromo2027/G-EIP-600-MPL-6-1-eip-alexis.belmonte"`"

    if [ -z "$target_repository" ]; then
        echo "$0: No GitHub target repository specified, cannot continue." >&2
        exit 1
    fi

    cat >&2 <<EOF

Everything has been collected and the service is now being installed and
configured.

The service will be installed to '$SV_INSTALL_PATH'.

EOF

    sv_status_show "Setting-up a dedicated service user for systemd"

    if ! id -u "$SV_SERVICE_USER" >/dev/null 2>/dev/null; then
        sv_try "Create a dedicated service user" \
               "$tool_useradd -m $SV_SERVICE_USER"
    fi

    sv_try_as "$tool_su" "$SV_SERVICE_USER" "Create the SSH directory" \
              "mkdir -p '~/.ssh'"
    sv_try "Copy the SSH private key over to the dedicated service user" \
           "cp '$private_key_path' '/home/$SV_SERVICE_USER/.ssh/id_ed25519'"
    sv_try "Configure SSH private key file ownership" \
           "chown $SV_SERVICE_USER:$SV_SERVICE_USER '/home/$SV_SERVICE_USER/.ssh/id_ed25519'"
    sv_try "Configure SSH private key file permissions" \
           "chmod 700 '/home/$SV_SERVICE_USER/.ssh/id_ed25519'"
    sv_try_as "$tool_su" "$SV_SERVICE_USER" "Discover the SSH private key" \
              "ssh-keyscan -H github.com >> /home/$SV_SERVICVE_USER/.ssh/known_hosts"

    sv_status_show "Downloading service repository and installing it in $SV_INSTALL_PATH"

    if [ -d "$SV_TEMP_PATH" ]; then
        sv_try "Remove the old service repository from the temporary path." \
               "rm -rf '$SV_TEMP_PATH'"
    fi

    sv_try_as "$tool_su" "$sv_repo_userowner" "Clone the service repository to a temporary path." \
              "$tool_git clone '$sv_repo_url' '$SV_TEMP_PATH'"

    if [ -d "$SV_INSTALL_PATH" ]; then
        sv_try "Mirror the hierarchy of the cloned repository to the installation path." \
               "(cd '$SV_TEMP_PATH' && find . -mindepth 1 -type d -exec mkdir -p $SV_INSTALL_PATH/{} \;)"
        sv_try "Move the contents of the cloned repository to the installation path." \
               "(cd '$SV_TEMP_PATH' && find . -mindepth 1 -type f -exec mv {} $SV_INSTALL_PATH/{} \;)"
        sv_try "Remove the directory from the previously cloned repository." \
               "rm -rf '$SV_TEMP_PATH'"
    else
        sv_try "Move the cloned repository to the installation path." \
               "mv '$SV_TEMP_PATH' '$SV_INSTALL_PATH'"
    fi

    sv_status_show "Installing the systemd service file"

    cat >"$SV_SERVICE_PATH" <<EOF
[Unit]
Description=Naucto Repository Crawler Service
After=network.target
ConditionPathExists=$SV_INSTALL_PATH

[Service]
User=$SV_SERVICE_USER
EnvironmentFile=$SV_SERVICE_ENV_PATH
ExecStart=$SV_SERVICE_SCRIPT_PATH
Restart=on-failure

[Install]
WantedBy=network.target
EOF

    sv_status_show "Installing the environment file"

    cat >"$SV_SERVICE_ENV_PATH" <<EOF
LOGURU_LEVEL=INFO

CW_HOST=1
CW_HOST_CERT=$certificates_path
CW_GITHUB_TOKEN=$github_token
CW_GITHUB_SOURCE=$source_organization
CW_GITHUB_TARGET=$target_repository
EOF

    sv_status_show "Installing the service script file"

    cat >"$SV_SERVICE_SCRIPT_PATH" <<EOF
#!/bin/sh

SV_INSTALL_PATH="\`dirname "\$0"\`"
SV_ENV_PATH="$SV_SERVICE_VENV_PATH"

. "\$SV_ENV_PATH/bin/activate"

python3 -B "$SV_INSTALL_PATH/main.py"
EOF
    chmod +x "$SV_INSTALL_PATH/service.sh"

    sv_status_show "Initializing the Python virtual environment"

    sv_try "Initialize a virtual Python environment in the installation path." \
           "$tool_python -m venv $SV_SERVICE_VENV_PATH"

    sv_try "Install dependencies in the virtual Python environment." \
           ". $SV_SERVICE_VENV_PATH/bin/activate && pip install -r '$SV_INSTALL_PATH/requirements.txt'"

    sv_try "Add a certificates folder for auto-renewing certificate bots." \
           "mkdir -p '$SV_INSTALL_DEFAULT_CERT_PATH'"

    sv_status_show "Configuring filesystem permissions"

    sv_try "Set ownership of the service installation location to $SV_SERVICE_USER:root." \
           "chown -R '$SV_SERVICE_USER:root' '$SV_INSTALL_PATH'"
    sv_try "Set permissions of the service installation location." \
           "chmod -R 700 '$SV_INSTALL_PATH'"

    sv_status_show "Notifying systemd that a new service has been installed"

    sv_try "Notify systemd that we have installed a new service." \
           "$tool_systemctl daemon-reload"

    sv_status_show "Configuring and starting up the service"

    sv_try "Enable the service to automatically start at boot-up." \
           "$tool_systemctl enable $SV_SERVICE_NAME"
    sv_try "Start the service on the machine." \
           "$tool_systemctl start $SV_SERVICE_NAME"

    sv_status_show "Waiting for the service to boot-up"
    sleep 6

    sv_try "Check if the service is alive and well on the machine." \
           "$tool_systemctl is-active $SV_SERVICE_NAME"

    cat >&2 <<EOF

Congratulations! The Naucto Repository Crawler service is now up and running on
your machine.

You may update or uninstall this service by using this installer script again
with a different verb, in the installation location or where you just executed
this script.

Report any issues here: https://github.com/Naucto/Repository-Crawler/issues

We hope that it will satisfy you, just as much as it satisfies us! :]
EOF
}

sv_action_update()
{
    if [ ! -f "$SV_SERVICE_ENV_PATH" ]; then
        echo "$0: The service is not installed on this system."
        exit 1
    fi

    sv_status_show "Stopping the executing service if it is still running"
    $tool_systemctl stop "$SV_SERVICE_NAME" >/dev/null 2>/dev/null

    sv_status_show "Saving virtual Python environment and settings"
    save_dir_path="`mktemp -d`"
    if [ -z "$save_dir_path" ]; then
        echo "$0: Failed to create a temporary path to save the virtual environment and settings, cannot continue."
        exit 1
    fi

    cp -r "$SV_SERVICE_ENV_PATH" \
          "$SV_SERVICE_VENV_PATH" \
          "$SV_SERVICE_SCRIPT_PATH" \
          "$SV_INSTALL_DEFAULT_CERT_PATH" \
          "$save_dir_path"

    sv_status_show "Cleaning-up old installation directory"
    sv_try "Clean old installation directory to prepare new installation. Settings and virtual environment are located at '$save_dir_path'." \
           "rm -rf '$SV_INSTALL_PATH'"

    sv_status_show "Downloading service repository and copying it in $SV_INSTALL_PATH"

    sv_try_as "$tool_su" "$sv_repo_userowner" "Clone the service repository to a temporary path." \
              "$tool_git clone '$sv_repo_url' '$SV_TEMP_PATH'"

    sv_try "Move the cloned repository to the installation path" \
           "mv '$SV_TEMP_PATH' '$SV_INSTALL_PATH'"

    sv_status_show "Moving back the virtual Python environment and settings"

    sv_try "Move back the virtual Python environment and settings in the installation location." \
           "mv '$save_dir_path/$SV_SERVICE_ENV_FNAME' '$SV_SERVICE_ENV_PATH' && \
            mv '$save_dir_path/$SV_SERVICE_VENV_FNAME' '$SV_SERVICE_VENV_PATH' && \
            mv '$save_dir_path/$SV_SERVICE_SCRIPT_FNAME' '$SV_SERVICE_SCRIPT_PATH' && \
            mv '$save_dir_path/$SV_INSTALL_DEFAULT_CERT_FNAME' '$SV_INSTALL_DEFAULT_CERT_PATH'"
    sv_try "Remove temporary directory that contained the virtual Python environment and settings." \
           "rm -rf '$save_dir_path'"

    sv_status_show "Updating the virtual Python environment"

    sv_try "Update dependencies in the virtual Python environment." \
           ". $SV_SERVICE_VENV_PATH/bin/activate && pip install -r '$SV_INSTALL_PATH/requirements.txt'"

    sv_status_show "Starting back the service"

    sv_try "Start the service back after updating it" \
           "$tool_systemctl start '$SV_SERVICE_NAME'"
    sv_try "Check if the service is alive and well on the machine." \
           "$tool_systemctl is-active $SV_SERVICE_NAME"

    cat <<EOF

Done updating the service, and now back online!

Report any issues here: https://github.com/Naucto/Repository-Crawler/issues
EOF
}

sv_action_uninstall()
{
    if [ ! -f "$SV_SERVICE_ENV_PATH" ]; then
        cat >&2 <<EOF
NOTE: The service is not installed on this system. We'll still allow you to
proceed to the uninstallation if you have remnants, but please report issues
like this. A link will be available at the end of the process.

EOF
    fi

    cat >&2 <<EOF
ATTENTION! You are about to uninstall the repository crawler service. All files
and the associated service user will be removed from this machine.

EOF
    uninstall_question="`sv_question "Type in 'UNINSTALL' without quotes, all caps to confirm" \
                         ""`"

    if [ "$uninstall_question" != "UNINSTALL" ]; then
        echo "$0: Question unanswered incorrectly, cancelling." >&2
        exit 1
    fi

    echo

    sv_status_show "Stopping the executing service if it is still running and disable it"
    $tool_systemctl stop "$SV_SERVICE_NAME" >/dev/null 2>/dev/null
    $tool_systemctl disable "$SV_SERVICE_NAME" >/dev/null 2>/dev/null

    sv_status_show "Uninstalling service software & system files"
    rm -rf "$SV_INSTALL_PATH" "$SV_SERVICE_PATH"

    sv_status_show "Reloading systemd daemon"
    sv_try "Notify systemd that we have removed a service." \
           "$tool_systemctl daemon-reload"

    sv_status_show "Removing service user"
    $tool_userdel --remove "$SV_SERVICE_USER" >/dev/null 2>/dev/null

    cat >&2 <<EOF

Done uninstalling the repository crawler service. Goodbye world! :]

Report any issues here: https://github.com/Naucto/Repository-Crawler/issues
EOF
}

# ---

if [ "$(id -u)" -ne 0 ]; then
    echo "$0: This script requires administrative privileges." >&2
    exit 1
fi

cd "$SV_REPO_PATH"

tool_git="`sv_require git "This installer uses Git to keep this software up-to-date. Please install it."`"
tool_systemctl="`sv_require systemctl "This installer does not support non-systemd environments."`"
tool_su="`sv_require su "This installer requires to switch back-and-forth between a regular & root account to e.g. update the service."`"
tool_python="`sv_require python3 "The service requires Python 3.11+ along with venv + pip support to run on this machine"`"
tool_useradd="`sv_require useradd "The service requires a user to be created when installing"`"
tool_userdel="`sv_require userdel "The service requires a user to be deleted when uninstalling"`"

[ -z "$tool_git" ] || \
[ -z "$tool_systemctl" ] || \
[ -z "$tool_su" ] || \
[ -z "$tool_python" ] || \
[ -z "$tool_useradd" ] || \
[ -z "$tool_userdel" ] && exit 1

sv_status_show "Determining installation source repository user owner"
sv_repo_userowner="`stat -c "%U" "$SV_REPO_PATH/.git" 2>/dev/null`"

if [ -z "$sv_repo_userowner" ]; then
    cat >&2 <<EOF
$0: Failed to determine the ownership of the repository, cannot continue.

If you have downloaded the repository through the .zip file, please proceed
again by cloning the repository instead. This allows the installer and the
service to update itself when necessary.
EOF
    exit 1
fi

sv_repo_url="`"$tool_git" config --get remote.origin.url 2>/dev/null`"

if [ -z "$sv_repo_url" ]; then
    cat >&2 <<EOF
$0: Failed to get the remote origin URL of the repository, cannot continue.

If you have downloaded the repository through the .zip file, please proceed
again by cloning the repository instead. This allows the installer and the
service to update itself when necessary.
EOF
    exit 1
fi

sv_lock

sv_status_show "Checking for updates on the repository"
sv_try_as "$tool_su" "$sv_repo_userowner" "Attempt to pull the tool's repository to keep the installer up-to-date" \
          "$tool_git pull"

sv_try "Check if the installer has changed. Please reload the script." \
       "diff '$0' '$SV_LOCK_PATH'"

sv_unlock

cat <<EOF

Naucto Repository Crawler service installer script
Copyright (C) 2025 Naucto - Under the MIT license. See license.txt for more details.

EOF

if [ "$#" -ne 1 ]; then
    sv_usage
    exit 1
fi

primary_command="$1"
shift 1

if [ "$primary_command" = "-h" ]; then
    cat >&2 <<EOF
Utility to setup the Naucto Repository Crawler service on a systemd-based
system.

EOF

    sv_usage
   
    cat >&2 <<EOF
Options:

    -h              Show a help message describing the available options

Commands:

    install         Install the Naucto Repository Crawler as a systemd-based
                    service on the current system.
                    This will duplicate the contents of the repository to the
                    installation path, create a systemd service file for it
                    and ask the user a few questions to configure it

    update          Performs an unconditionnal update to the service.
                    This fetches a new copy of the repository and installs it
                    without losing the specified settings during installation.
                    This verb can also be used to repair an installation if
                    it broke in most situations.

    uninstall       Remove the aforementioned service from the system.
EOF

    exit 1
fi

case "$primary_command" in
    install)
        sv_action_install $@
        exit $?
        ;;

    update)
        sv_action_update $@
        exit $?
        ;;

    uninstall)
        sv_action_uninstall $@
        exit $?
        ;;

    *)
        echo "$0: Action '$primary_command' does not exist." >&2
        exit 1
        ;;
esac
